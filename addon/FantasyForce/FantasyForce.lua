-- FantasyForce: records this account's characters and the guild roster into
-- FantasyForceDB (SavedVariables) for the Fantasy Force guild website.
-- Also records the guild bank (or a bank alt's bags and bank), raid attendance and raid loot.
-- No UI, no network. Slash commands: /ff, /ff reset, /ff bankalt, /ff loot rare|epic.
-- Plain Lua 5.1; every API call is guarded so a missing function never errors.

local ADDON = "FantasyForce"
local DB_VERSION = 1
local ROSTER_THROTTLE = 60

local time, type, pcall, pairs, ipairs, tostring, tonumber = time, type, pcall, pairs, ipairs, tostring, tonumber
local floor = math.floor

local lastRosterRequest = 0
local lastGuildRecord = 0
local loggedIn = false

-- Call a function by (possibly nil) reference without ever throwing.
local function try(fn, ...)
  if type(fn) ~= "function" then return nil end
  local ok, a, b, c, d, e, f, g, h, i, j, k = pcall(fn, ...)
  if not ok then return nil end
  return a, b, c, d, e, f, g, h, i, j, k
end

local function str(v)
  if type(v) == "string" then return v end
  return ""
end

local function num(v, default)
  v = tonumber(v)
  if v == nil then return default end
  return v
end

-- "Name-Realm" -> "Name"
local function stripRealm(name)
  name = str(name)
  local base = name:match("^([^%-]+)%-")
  return base or name
end

local function initDB()
  if type(FantasyForceDB) ~= "table" then FantasyForceDB = {} end
  local db = FantasyForceDB
  db.version = DB_VERSION
  if type(db.characters) ~= "table" then db.characters = {} end
  return db
end

local function print_(msg)
  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage("|cffffd100FantasyForce:|r " .. msg)
  end
end

-- ---------------------------------------------------------------- talents --

-- Returns tree list { {name=, points=}, ... } in tree order, or nil.
local function readTrees()
  local trees = {}

  -- Modern style: C_SpecializationInfo / global specialization functions.
  local C = C_SpecializationInfo
  local getNum = (C and C.GetNumSpecializations) or GetNumSpecializations
  local getInfo = (C and C.GetSpecializationInfo) or GetSpecializationInfo
  local n = num(try(getNum), 0)
  if n and n > 0 and type(getInfo) == "function" then
    for i = 1, n do
      local _, name, _, _, _, _, points = try(getInfo, i)
      if type(name) == "string" then
        trees[#trees + 1] = { name = name, points = num(points, 0) }
      end
    end
    if #trees > 0 then return trees end
  end

  -- Classic style: talent tabs.
  local nt = num(try(GetNumTalentTabs), 0)
  if nt and nt > 0 and type(GetTalentTabInfo) == "function" then
    for i = 1, nt do
      local a, b, c, d, e = try(GetTalentTabInfo, i)
      -- Classic: name, icon, pointsSpent, background. Newer: id, name, desc, icon, pointsSpent.
      local name, points
      if type(a) == "string" then
        name, points = a, num(c, 0)
      else
        name, points = b, num(e, 0)
      end
      if type(name) == "string" then
        trees[#trees + 1] = { name = name, points = points }
      end
    end
    if #trees > 0 then return trees end
  end
  return nil
end

local function readSpec(rec)
  local trees = readTrees()
  local spec = ""
  if trees then
    local pts = {}
    local best, bestPoints = nil, 0
    for i, t in ipairs(trees) do
      pts[i] = t.points
      if t.points > bestPoints then best, bestPoints = t.name, t.points end
    end
    rec.talents = pts
    spec = best or ""
  end
  -- Prefer the active spec's own name if the API offers it and points gave nothing.
  if spec == "" then
    local C = C_SpecializationInfo
    local idx = try((C and C.GetSpecialization) or GetSpecialization)
    local getInfo = (C and C.GetSpecializationInfo) or GetSpecializationInfo
    if type(idx) == "number" and idx > 0 then
      local _, name = try(getInfo, idx)
      if type(name) == "string" then spec = name end
    end
  end
  rec.spec = spec
end

-- ------------------------------------------------------------ professions --

local function readProfessions()
  local list, seen = {}, {}

  local function add(name, skill, max)
    if type(name) == "string" and name ~= "" and not seen[name] then
      seen[name] = true
      list[#list + 1] = { name = name, skill = num(skill, 0), max = num(max, 0) }
    end
  end

  -- Modern style.
  if type(GetProfessions) == "function" then
    local p = { try(GetProfessions) }
    for slot = 1, 5 do
      local idx = p[slot]
      if type(idx) == "number" then
        local name, _, skill, max = try(GetProfessionInfo, idx)
        add(name, skill, max)
      end
    end
  end

  -- Classic style: walk the skill list, take rows under the profession headers.
  if #list == 0 and type(GetNumSkillLines) == "function" and type(GetSkillLineInfo) == "function" then
    local n = num(try(GetNumSkillLines), 0)
    local inProf = false
    for i = 1, n do
      local name, header, _, rank, _, _, maxRank, isAbandonable = try(GetSkillLineInfo, i)
      if header then
        -- Headers: "Professions", "Secondary Skills" (localized); skip others (Weapon Skills, Languages...).
        inProf = false
      elseif name then
        -- Heuristic: professions can be abandoned (or have a real rank cap); weapon skills cannot.
        if isAbandonable or (num(maxRank, 0) > 1 and num(maxRank, 0) >= 75 and num(maxRank, 0) % 75 == 0) then
          add(name, rank, maxRank)
        end
      end
    end
    -- Cooking/Fishing/First Aid cannot be abandoned in some builds; the multiple-of-75 cap catches them.
    local _ = inProf
  end

  -- Newer professions API variant (secondary skills may be missing above).
  if C_TradeSkillUI and type(C_TradeSkillUI.GetAllProfessionTradeSkillLines) == "function" and #list == 0 then
    local ids = try(C_TradeSkillUI.GetAllProfessionTradeSkillLines)
    if type(ids) == "table" then
      for _, id in ipairs(ids) do
        local info = try(C_TradeSkillUI.GetProfessionInfoBySkillLineID, id)
        if type(info) == "table" then
          add(info.professionName, info.skillLevel, info.maxSkillLevel)
        end
      end
    end
  end

  return list
end

-- ------------------------------------------------------------- characters --

local function readName()
  local name = try(UnitFullName, "player")
  if type(name) ~= "string" or name == "" then name = try(UnitName, "player") end
  return stripRealm(name)
end

local function recordCharacter()
  local ok = pcall(function()
    local db = initDB()
    local name = readName()
    if name == "" or name == "Unknown" then return end

    local rec = db.characters[name]
    if type(rec) ~= "table" then rec = {} end
    db.characters[name] = rec

    rec.name = name
    rec.level = num(try(UnitLevel, "player"), rec.level or 0)

    local className, classFile = try(UnitClass, "player")
    if type(classFile) == "string" then rec.class = classFile:upper() end

    local raceName, raceFile = try(UnitRace, "player")
    rec.race = str(raceFile) ~= "" and raceFile or str(raceName)
    rec.raceName = str(raceName)

    local faction = try(UnitFactionGroup, "player")
    rec.faction = str(faction)

    local spec = rec.spec
    readSpec(rec)
    if rec.spec == "" and type(spec) == "string" then rec.spec = spec end

    rec.professions = readProfessions()

    local gname, grank = try(GetGuildInfo, "player")
    rec.guild = str(gname)
    rec.rank = str(grank)

    rec.updated = time()
  end)
  return ok
end

-- ------------------------------------------------------------------ guild --

local function requestRoster()
  local now = time()
  if now - lastRosterRequest < ROSTER_THROTTLE then return end
  if not try(IsInGuild) then return end
  lastRosterRequest = now
  if C_GuildInfo and type(C_GuildInfo.GuildRoster) == "function" then
    try(C_GuildInfo.GuildRoster)
  elseif type(GuildRoster) == "function" then
    try(GuildRoster)
  end
end

local function recordGuild()
  pcall(function()
    if not try(IsInGuild) then return end
    local now = time()
    if now - lastGuildRecord < ROSTER_THROTTLE then return end

    local total = num(try(GetNumGuildMembers), 0)
    if not total or total <= 0 then return end

    local db = initDB()
    local members = {}
    for i = 1, total do
      -- name, rankName, rankIndex, level, classDisplayName, zone, publicNote,
      -- officerNote (never read into the record), isOnline, status, classFileName
      local name, rank, rankIndex, level, _, _, note, _, online, _, classFile = try(GetGuildRosterInfo, i)
      if type(name) == "string" and name ~= "" then
        local m = {
          name = stripRealm(name),
          rank = str(rank),
          rankIndex = num(rankIndex, 0),
          level = num(level, 0),
          class = str(classFile):upper(),
          note = str(note),
          online = online and true or false,
        }
        if m.online then
          m.lastOnline = 0
        elseif type(GetGuildRosterLastOnline) == "function" then
          local years, months, days = try(GetGuildRosterLastOnline, i)
          if years or months or days then
            m.lastOnline = floor(num(years, 0) * 365 + num(months, 0) * 30 + num(days, 0))
          end
        end
        members[#members + 1] = m
      end
    end
    if #members == 0 then return end

    lastGuildRecord = now
    db.guild = {
      name = str((try(GetGuildInfo, "player"))),
      updated = now,
      by = readName(),
      members = members,
    }
  end)
end

-- ---------------------------------------------------------------- recipes --
-- The game only lists recipes while a profession window is open, so they're recorded then
-- (per character, per profession) and kept until that window is opened again.

local function viewingSomeoneElse()
  if C_TradeSkillUI then
    if try(C_TradeSkillUI.IsTradeSkillLinked) or try(C_TradeSkillUI.IsTradeSkillGuild) or try(C_TradeSkillUI.IsNPCCrafting) then return true end
  end
  if try(IsTradeSkillLinked) then return true end
  return false
end

local function tradeSkillName()
  if C_TradeSkillUI then
    local info = try(C_TradeSkillUI.GetBaseProfessionInfo)
    if type(info) == "table" and str(info.professionName) ~= "" then return info.professionName end
  end
  local name = try(GetTradeSkillLine)
  if str(name) ~= "" and name ~= "UNKNOWN" then return name end
  return ""
end

local function readRecipesModern()
  if not (C_TradeSkillUI and type(C_TradeSkillUI.GetAllRecipeIDs) == "function") then return nil end
  local ids = try(C_TradeSkillUI.GetAllRecipeIDs)
  if type(ids) ~= "table" then return nil end
  local out = {}
  for _, id in ipairs(ids) do
    local info = try(C_TradeSkillUI.GetRecipeInfo, id)
    if type(info) == "table" and info.learned and str(info.name) ~= "" then
      -- the item it makes, for its icon and tooltip on the site
      local schematic = try(C_TradeSkillUI.GetRecipeSchematic, id, false)
      local item = type(schematic) == "table" and num(schematic.outputItemID, nil) or nil
      out[#out + 1] = { id = id, item = item, name = info.name }
    end
  end
  return out
end

-- An id out of a game link: "item:12784:..." or "enchant:20034" / "spell:20034".
local function linkId(link, kind)
  if type(link) ~= "string" then return nil end
  return tonumber(link:match(kind .. ":(%d+)"))
end

local function readRecipesClassic()
  if type(GetNumTradeSkills) ~= "function" then return nil end
  local out = {}
  for i = 1, num(try(GetNumTradeSkills), 0) do
    local name, kind = try(GetTradeSkillInfo, i)
    if str(name) ~= "" and kind ~= "header" and kind ~= "subheader" then
      local recipeLink = try(GetTradeSkillRecipeLink, i)
      out[#out + 1] = {
        name = name,
        id = linkId(recipeLink, "enchant") or linkId(recipeLink, "spell"),
        item = linkId(try(GetTradeSkillItemLink, i), "item"),
      }
    end
  end
  return out
end

-- Enchanting used its own "craft" window in 2004-style clients.
local function readCraftsClassic()
  if type(GetNumCrafts) ~= "function" then return nil end
  local out = {}
  for i = 1, num(try(GetNumCrafts), 0) do
    local name, _, kind = try(GetCraftInfo, i)
    if str(name) ~= "" and kind ~= "header" then
      local link = try(GetCraftRecipeLink, i) or try(GetCraftItemLink, i)
      out[#out + 1] = { name = name, id = linkId(link, "enchant") or linkId(link, "spell") }
    end
  end
  return out
end

local function recordRecipes(event)
  pcall(function()
    if viewingSomeoneElse() then return end -- a linked or guild recipe list isn't this character's
    local db = initDB()
    local rec = db.characters[readName()]
    if type(rec) ~= "table" then return end
    local prof, list
    if event == "CRAFT_SHOW" or event == "CRAFT_UPDATE" then
      prof = str((try(GetCraftDisplaySkillLine)))
      list = readCraftsClassic()
    else
      prof = tradeSkillName()
      list = readRecipesModern()
      if type(list) ~= "table" or #list == 0 then list = readRecipesClassic() end
    end
    if prof == "" or type(list) ~= "table" or #list == 0 then return end
    if type(rec.recipes) ~= "table" then rec.recipes = {} end
    rec.recipes[prof] = list
  end)
end

local RECIPE_EVENTS = {
  TRADE_SKILL_SHOW = true, TRADE_SKILL_LIST_UPDATE = true, TRADE_SKILL_DATA_SOURCE_CHANGED = true,
  CRAFT_SHOW = true, CRAFT_UPDATE = true, NEW_RECIPE_LEARNED = true,
}

-- ------------------------------------------------------------------- items --

local QUALITY_BY_COLOR = {
  ["9d9d9d"] = 0, ["ffffff"] = 1, ["1eff00"] = 2, ["0070dd"] = 3, ["a335ee"] = 4, ["ff8000"] = 5, ["e6cc80"] = 6,
}

-- Item id, name and quality from a hyperlink; name/quality come from the link text and colour
-- when GetItemInfo hasn't cached the item yet.
local function parseLink(link)
  link = str(link)
  local id = tonumber(link:match("item:(%d+)"))
  if not id then return nil end
  local name = link:match("|h%[(.-)%]|h") or ""
  local quality
  local gi = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  local iname, _, iq = try(gi, link)
  if type(iname) == "string" and iname ~= "" then name = iname end
  if type(iq) == "number" then quality = iq end
  if quality == nil then
    local color = link:match("|cff(%x%x%x%x%x%x)")
    quality = color and QUALITY_BY_COLOR[color:lower()] or 1
  end
  return id, name, quality
end

-- Adds an item to a tab's list, combining stacks of one item.
local function addItem(items, index, link, count)
  local id, name, quality = parseLink(link)
  if not id then return end
  count = num(count, 1)
  if count < 1 then count = 1 end
  local row = index[id]
  if row then
    row.count = row.count + count
  else
    row = { id = id, name = name, count = count, quality = quality }
    index[id] = row
    items[#items + 1] = row
  end
end

-- ------------------------------------------------------------------- bank --
-- A guild bank (if this client has one) is read tab by tab when opened. A "bank alt" (toggled with
-- /ff bankalt) records its bags and its bank instead.

local guildTabCache = {}
local lastBagRecord = 0

local function isBankAlt()
  local db = initDB()
  return type(db.bankAlts) == "table" and db.bankAlts[readName()] == true
end

local function readGuildTab(tab)
  local items, index = {}, {}
  local slots = num(MAX_GUILDBANK_SLOTS_PER_TAB, 98)
  for slot = 1, slots do
    local link = try(GetGuildBankItemLink, tab, slot)
    if type(link) == "string" then
      local _, count = try(GetGuildBankItemInfo, tab, slot)
      addItem(items, index, link, count)
    end
  end
  return items
end

local function recordGuildBank()
  pcall(function()
    local n = num(try(GetNumGuildBankTabs), 0)
    if not n or n <= 0 then return end
    local current = num(try(GetCurrentGuildBankTab), 0)
    local tabs = {}
    for tab = 1, n do
      local name, _, viewable = try(GetGuildBankTabInfo, tab)
      if type(name) == "string" and (viewable == nil or viewable) then
        local items = readGuildTab(tab)
        if #items > 0 or tab == current then guildTabCache[tab] = items end
        if guildTabCache[tab] then
          tabs[#tabs + 1] = { name = name, items = guildTabCache[tab] }
        end
      end
    end
    if #tabs == 0 then return end
    local bank = { source = "guild", updated = time(), by = readName(), tabs = tabs }
    local money = try(GetGuildBankMoney)
    if type(money) == "number" then bank.money = money end
    initDB().bank = bank
  end)
end

local function queryGuildBankTabs()
  pcall(function()
    local n = num(try(GetNumGuildBankTabs), 0)
    for tab = 1, n do
      local _, _, viewable = try(GetGuildBankTabInfo, tab)
      if viewable == nil or viewable then try(QueryGuildBankTab, tab) end
    end
  end)
end

local function readBagContainer(bag, items, index)
  local getSlots = (C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
  local getInfo = (C_Container and C_Container.GetContainerItemInfo) or GetContainerItemInfo
  local getLink = (C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
  local slots = num(try(getSlots, bag), 0)
  for slot = 1, slots do
    local a, b = try(getInfo, bag, slot)
    local link, count
    if type(a) == "table" then
      link, count = a.hyperlink, a.stackCount
    else
      count = b -- legacy: icon, count, ...
    end
    if type(link) ~= "string" then link = try(getLink, bag, slot) end
    if type(link) == "string" then addItem(items, index, link, count) end
  end
end

local function bagTab(name, containers)
  local items, index = {}, {}
  for _, bag in ipairs(containers) do readBagContainer(bag, items, index) end
  return { name = name, items = items }
end

local function bagIds()
  local n = num(NUM_BAG_SLOTS, 4)
  local ids = {}
  for b = 0, n do ids[#ids + 1] = b end
  return ids
end

local function bankIds()
  local first = num(NUM_BAG_SLOTS, 4) + 1
  local last = first + num(NUM_BANKBAGSLOTS, 7) - 1
  local ids = { -1 }
  for b = first, last do ids[#ids + 1] = b end
  return ids
end

local function recordAltBank(withBank)
  pcall(function()
    if not isBankAlt() then return end
    local db = initDB()
    local me = readName()
    local tabs = { bagTab("Bags", bagIds()) }
    if withBank then
      tabs[2] = bagTab("Bank", bankIds())
    elseif type(db.bank) == "table" and db.bank.source == "alt" and db.bank.by == me and type(db.bank.tabs) == "table" then
      for _, t in ipairs(db.bank.tabs) do
        if t.name == "Bank" then tabs[2] = t end
      end
    end
    local bank = { source = "alt", updated = time(), by = me, tabs = tabs }
    local money = try(GetMoney)
    if type(money) == "number" then bank.money = money end
    db.bank = bank
  end)
end

-- ------------------------------------------------------------------ raids --

local MAX_RAIDS = 60
local SNAPSHOT_SECONDS = 600
local curRaid = nil
local lastBoss = ""
local lastBossAt = 0
local tickerStarted = false

local function raidInstanceName()
  local name, instanceType = try(GetInstanceInfo)
  if instanceType == "raid" and type(name) == "string" and name ~= "" then
    if try(IsInRaid) then return name end
  end
  return nil
end

local function readRoster()
  local names, seen = {}, {}
  local n = num(try(GetNumGroupMembers), 0)
  if not n or n <= 0 then n = num(try(GetNumRaidMembers), 0) end
  for i = 1, n do
    local name = stripRealm(str((try(GetRaidRosterInfo, i))))
    if name ~= "" and not seen[name] then
      seen[name] = true
      names[#names + 1] = name
    end
  end
  return names
end

local function mergeNames(into, names)
  local seen = {}
  for _, n in ipairs(into) do seen[n] = true end
  for _, n in ipairs(names) do
    if not seen[n] then
      seen[n] = true
      into[#into + 1] = n
    end
  end
end

-- Finds or starts the record for this raid today. Returns it, or nil when not in a raid instance.
local function ensureRaid()
  local zone = raidInstanceName()
  if not zone then
    curRaid = nil
    return nil
  end
  local now = time()
  local key = zone .. " " .. date("%Y-%m-%d", now)
  if curRaid and curRaid.key == key then return curRaid end
  local db = initDB()
  if type(db.raids) ~= "table" then db.raids = {} end
  curRaid = nil
  for i = #db.raids, math.max(1, #db.raids - 5), -1 do
    if db.raids[i].key == key then curRaid = db.raids[i] break end
  end
  if not curRaid then
    curRaid = { key = key, zone = zone, started = now, ended = now, by = readName(),
      attendees = {}, bosses = {}, loot = {} }
    db.raids[#db.raids + 1] = curRaid
    while #db.raids > MAX_RAIDS do table.remove(db.raids, 1) end
    lastBoss = ""
  end
  return curRaid
end

-- Snapshots the roster into the raid; returns the roster (or nil).
local function snapshotRaid()
  local raid = ensureRaid()
  if not raid then return nil end
  local names = readRoster()
  if #names == 0 then return nil end
  mergeNames(raid.attendees, names)
  raid.ended = time()
  return names
end

local function recordBossKill(bossName)
  pcall(function()
    local raid = ensureRaid()
    if not raid then return end
    bossName = str(bossName)
    local now = time()
    if bossName == lastBoss and now - lastBossAt < 60 then return end -- ENCOUNTER_END and BOSS_KILL both fired
    local names = snapshotRaid() or {}
    raid.bosses[#raid.bosses + 1] = { name = bossName, killed = now, attendees = names }
    lastBoss, lastBossAt = bossName, now
  end)
end

local function startTicker()
  if tickerStarted then return end
  if not (C_Timer and type(C_Timer.NewTicker) == "function") then return end
  tickerStarted = true
  try(C_Timer.NewTicker, SNAPSHOT_SECONDS, function() pcall(snapshotRaid) end)
end

-- ------------------------------------------------------------------- loot --

-- A client format string ("%s receives loot: %s.") as an anchored Lua pattern, so it works in any language.
local function formatToPattern(fmt)
  if type(fmt) ~= "string" or fmt == "" then return nil end
  local p = fmt:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
  p = p:gsub("%%%%%d%%%$s", "(.+)"):gsub("%%%%s", "(.+)")
  p = p:gsub("%%%%%d%%%$d", "(%%d+)"):gsub("%%%%d", "(%%d+)")
  return "^" .. p .. "$"
end

-- Order matters: the "multiple" forms must be tried before the single ones.
local LOOT_FORMS = {
  { global = "LOOT_ITEM_SELF_MULTIPLE", self = true, multi = true },
  { global = "LOOT_ITEM_SELF", self = true },
  { global = "LOOT_ITEM_MULTIPLE", multi = true },
  { global = "LOOT_ITEM" },
}
local lootPatterns = nil

local function getLootPatterns()
  if lootPatterns then return lootPatterns end
  lootPatterns = {}
  for _, f in ipairs(LOOT_FORMS) do
    local p = formatToPattern(_G and _G[f.global])
    if p then lootPatterns[#lootPatterns + 1] = { pattern = p, self = f.self, multi = f.multi } end
  end
  return lootPatterns
end

local function recordLoot(msg)
  pcall(function()
    msg = str(msg)
    if msg == "" then return end
    local raid = ensureRaid()
    if not raid then return end
    for _, f in ipairs(getLootPatterns()) do
      local a, b, c = msg:match(f.pattern)
      if a then
        local who, link
        if f.self then
          who, link = readName(), a
        else
          who, link = stripRealm(a), b
        end
        local id, name, quality = parseLink(link)
        if id and quality >= num(initDB().lootQuality, 4) then
          raid.loot[#raid.loot + 1] = { id = id, name = name, quality = quality, to = who,
            at = time(), boss = lastBoss }
        end
        return
      end
    end
  end)
end

-- ----------------------------------------------------------------- events --

local frame = CreateFrame and CreateFrame("Frame") or nil
if frame then
  local events = {
    "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED",
    "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED", "CHARACTER_POINTS_CHANGED",
    "PLAYER_GUILD_UPDATE", "GUILD_ROSTER_UPDATE", "PLAYER_LOGOUT",
    "GUILDBANKFRAME_OPENED", "GUILDBANKBAGSLOTS_CHANGED", "BANKFRAME_OPENED", "BAG_UPDATE_DELAYED",
    "ZONE_CHANGED_NEW_AREA", "GROUP_ROSTER_UPDATE", "RAID_ROSTER_UPDATE",
    "ENCOUNTER_END", "BOSS_KILL", "CHAT_MSG_LOOT",
  }
  for ev in pairs(RECIPE_EVENTS) do events[#events + 1] = ev end
  for _, ev in ipairs(events) do
    -- An event unknown to this client must not break loading.
    pcall(frame.RegisterEvent, frame, ev)
  end

  frame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4, arg5)
    local ok = pcall(function()
      if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        loggedIn = true
        recordCharacter()
        requestRoster()
        startTicker()
        snapshotRaid()
        if event == "PLAYER_LOGIN" then lastBagRecord = time() recordAltBank(false) end
      elseif event == "GUILDBANKFRAME_OPENED" then
        queryGuildBankTabs()
        recordGuildBank()
      elseif event == "GUILDBANKBAGSLOTS_CHANGED" then
        recordGuildBank()
      elseif event == "BANKFRAME_OPENED" then
        recordAltBank(true)
      elseif event == "BAG_UPDATE_DELAYED" then
        local now = time()
        if loggedIn and now - lastBagRecord >= 10 then
          lastBagRecord = now
          recordAltBank(false)
        end
      elseif event == "ZONE_CHANGED_NEW_AREA" or event == "GROUP_ROSTER_UPDATE" or event == "RAID_ROSTER_UPDATE" then
        if loggedIn then snapshotRaid() end
      elseif event == "ENCOUNTER_END" then
        -- encounterID, encounterName, difficultyID, groupSize, success
        if arg5 == 1 or arg5 == true then recordBossKill(arg2) end
      elseif event == "BOSS_KILL" then
        recordBossKill(arg2)
      elseif event == "CHAT_MSG_LOOT" then
        recordLoot(arg1)
      elseif event == "GUILD_ROSTER_UPDATE" then
        if loggedIn then recordGuild() end
      elseif event == "PLAYER_GUILD_UPDATE" then
        recordCharacter()
        requestRoster()
      elseif RECIPE_EVENTS[event] then
        if loggedIn then recordRecipes(event) end
      elseif event == "PLAYER_LOGOUT" then
        recordCharacter()
        recordAltBank(false)
      else
        if loggedIn then recordCharacter() end
      end
    end)
    return ok
  end)
end

-- ---------------------------------------------------------------- slash ----

SLASH_FANTASYFORCE1 = "/ff"
SlashCmdList = SlashCmdList or {}
SlashCmdList["FANTASYFORCE"] = function(msg)
  local ok = pcall(function()
    local db = initDB()
    msg = str(msg):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "reset" then
      FantasyForceDB = nil
      initDB()
      lastGuildRecord = 0
      lastRosterRequest = 0
      recordCharacter()
      print_("data cleared (this character re-recorded).")
      return
    end
    if msg == "bankalt" then
      if type(db.bankAlts) ~= "table" then db.bankAlts = {} end
      local me = readName()
      if db.bankAlts[me] then
        db.bankAlts[me] = nil
        print_(me .. " is no longer the guild's bank alt.")
      else
        db.bankAlts[me] = true
        print_(me .. " is now the guild's bank alt: its bags and bank are recorded.")
        recordAltBank(false)
      end
      return
    end
    if msg == "loot rare" or msg == "loot epic" then
      db.lootQuality = msg == "loot rare" and 3 or 4
      print_("raid loot recorded from " .. (db.lootQuality == 3 and "rare (blue)" or "epic (purple)") .. " up.")
      return
    end
    local chars = 0
    local latest = 0
    for _, c in pairs(db.characters) do
      chars = chars + 1
      if type(c) == "table" and num(c.updated, 0) > latest then latest = c.updated end
    end
    local members, gupd = 0, 0
    if type(db.guild) == "table" then
      members = type(db.guild.members) == "table" and #db.guild.members or 0
      gupd = num(db.guild.updated, 0)
      if gupd > latest then latest = gupd end
    end
    local last = latest > 0 and date("%Y-%m-%d %H:%M", latest) or "never"
    local raids = type(db.raids) == "table" and #db.raids or 0
    print_(chars .. " characters, " .. members .. " guild members, " .. raids .. " raids, last update " .. last
      .. ". " .. (isBankAlt() and "This character is a bank alt." or "Not a bank alt (/ff bankalt).")
      .. " Saved on logout or /reload. /ff reset clears.")
  end)
  if not ok then print_("something went wrong.") end
end
