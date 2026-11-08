-- FantasyForce: records this account's characters and the guild roster into
-- FantasyForceDB (SavedVariables) for the Fantasy Force guild website.
-- Also records the guild bank (or a bank alt's bags and bank), raid attendance and raid loot.
-- Shares the bank and every member's crafting with guildmates who run the addon (guild addon
-- messages, format in Sync.lua) and shows them in two windows: /ff bank and /ff crafts. Shares
-- each account's mains and alts too, shown in front of guild chat lines and on unit tooltips.
-- Slash commands: /ff, /ff bank, /ff crafts, /ff main, /ff tags off|on, /ff reset, /ff bankalt,
-- /ff loot rare|epic. Accents (/accent, /troll) live in Accent.lua and AccentChat.lua.
-- Plain Lua 5.1; every API call is guarded so a missing function never errors.

local ADDON = "FantasyForce"
local _, ns = ...
local Sync = type(ns) == "table" and ns.Sync or nil
local DB_VERSION = 1
local ROSTER_THROTTLE = 60

local time, type, pcall, pairs, ipairs, tostring, tonumber = time, type, pcall, pairs, ipairs, tostring, tonumber
local floor = math.floor

local lastRosterRequest = 0
local lastGuildRecord = 0
local loggedIn = false
local onDataChanged -- set in the sharing section: what's recorded changed, share it (debounced)

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
  -- what guildmates' addons shared (see the sharing section)
  if type(db.shared) ~= "table" then db.shared = {} end
  if type(db.shared.crafters) ~= "table" then db.shared.crafters = {} end
  if type(db.shared.accounts) ~= "table" then db.shared.accounts = {} end
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
    if onDataChanged then onDataChanged() end
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
    if onDataChanged then onDataChanged() end
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
    if onDataChanged then onDataChanged() end
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

-- ---------------------------------------------------------------- sharing --
-- Guildmates' addons share crafting (each account its own characters in this guild) and the bank
-- over guild addon messages, in the format in Sync.lua. Every payload carries an `updated` stamp and
-- receivers keep only the newest, in FantasyForceDB.shared. Sent on login (after a random 5-20 s, only
-- what changed since it was last sent), 10 s after a change, and in answer to a request, which goes
-- out when a window opens and none went out in the last hour. Anyone may answer for a character or
-- bank alt that's offline (a relay): relays wait longer, and an answer is dropped when someone else
-- starts sending the same or newer data first, so a request gets each thing about once.

local PREFIX = "FantasyForce"
local SEND_TICK = 0.25   -- at most one message every 0.25 s ...
local SEND_BURST = 8     -- ... while the server's allowance lasts (10 per prefix at once,
local SEND_REFILL = 1.05 -- and one more each second), so a long queue drains at about 1 a second
local CHANGE_DELAY = 10
local REQUEST_EVERY = 3600
local CRAFTER_MAX_AGE = 60 * 86400

local share = {
  queue = {},        -- jobs: { kind, subject, updated, body, notBefore, answer, done, msgs, i }
  tokens = SEND_BURST, tokensAt = 0, holdUntil = 0, pumping = false,
  assembler = Sync and Sync.newAssembler() or nil,
  changeGen = 0, registered = false, loginDone = false, timers = {},
}
local refreshWindows -- set in the windows section
local alts = { index = nil } -- mains and alts: the index is rebuilt when what it's made of changes

local function clock()
  local t = try(GetTime)
  if type(t) == "number" then return t end
  return time()
end

-- Runs fn after sec seconds (C_Timer, or an OnUpdate fallback). fn never throws out.
local function after(sec, fn)
  local function run() pcall(fn) end
  if C_Timer and type(C_Timer.After) == "function" and pcall(C_Timer.After, sec, run) then return end
  if not share.timerFrame then
    share.timerFrame = try(CreateFrame, "Frame")
    if not share.timerFrame then return end
    share.timerFrame:SetScript("OnUpdate", function()
      local now, list = clock(), share.timers
      for i = #list, 1, -1 do
        if list[i].at <= now then
          local t = table.remove(list, i)
          pcall(t.fn)
        end
      end
    end)
  end
  share.timers[#share.timers + 1] = { at = clock() + sec, fn = run }
end

local function rand(lo, hi)
  local r = try(math.random)
  if type(r) ~= "number" then r = 0.5 end
  return lo + (hi - lo) * r
end

local function myGuild()
  if not try(IsInGuild) then return "" end
  return str((try(GetGuildInfo, "player")))
end

local function sendFn()
  return (C_ChatInfo and C_ChatInfo.SendAddonMessage) or SendAddonMessage
end

local function registerPrefix()
  if share.registered then return end
  local reg = (C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
  if type(reg) == "function" and pcall(reg, PREFIX) then share.registered = true end
end

local function canShare()
  return Sync ~= nil and type(sendFn()) == "function" and try(IsInGuild) and true or false
end

local function sendResult(name, default)
  local E = Enum and Enum.SendAddonMessageResult
  local v = type(E) == "table" and E[name]
  if type(v) == "number" then return v end
  return default
end

-- "sent", "wait" (throttled or locked down: try again soon) or "drop".
local function sendOne(msg)
  local send = sendFn()
  if type(send) ~= "function" then return "drop" end
  local ok, a, b = pcall(send, PREFIX, msg, "GUILD")
  if not ok then return "drop" end
  local res = b -- before 11.0 the result came second
  if res == nil then res = a end
  if res == nil or res == true or res == 0 then return "sent" end
  if res == false or res == sendResult("AddonMessageThrottle", 3) or res == sendResult("ChannelThrottle", 8)
    or res == sendResult("AddOnMessageLockdown", 11) then
    return "wait"
  end
  return "drop"
end

local pump

local function schedulePump()
  if share.pumping then return end
  share.pumping = true
  after(SEND_TICK, pump)
end

-- Queues a payload. answer: sent in answer to a request, so dropped if someone else sends it first.
-- done runs once its last message is sent.
local function enqueue(kind, subject, updated, body, delay, answer, done)
  local q = share.queue
  for i = #q, 1, -1 do
    local j = q[i]
    if j.kind == kind and j.subject == subject then
      if j.updated >= updated then
        if j.updated == updated and not answer then
          -- a push for what's already queued as an answer: it's a push now (never dropped) and
          -- still records that it went out
          j.answer = false
          j.done = j.done or done
        end
        return
      end
      if not j.msgs then table.remove(q, i) end -- an older version not started yet
    end
  end
  q[#q + 1] = { kind = kind, subject = subject, updated = updated, body = body,
    notBefore = clock() + (delay or 0), answer = answer, done = done }
  schedulePump()
end

pump = function()
  share.pumping = false
  local q = share.queue
  if #q == 0 then return end
  if not canShare() then
    share.queue = {}
    return
  end
  local now = clock()
  share.tokens = math.min(SEND_BURST, share.tokens + (now - share.tokensAt) / SEND_REFILL)
  share.tokensAt = now
  local i = 1
  while now >= share.holdUntil and share.tokens >= 1 and i <= #q do
    local job = q[i]
    if job.notBefore > now then
      i = i + 1
    else
      job.msgs = job.msgs or Sync.chunk(job.kind, job.subject, job.updated, job.body) or {}
      job.i = job.i or 1
      local msg = job.msgs[job.i]
      local result = msg and sendOne(msg) or "drop"
      if result == "sent" then
        share.tokens = share.tokens - 1
        job.i = job.i + 1
        if job.i > #job.msgs then
          table.remove(q, i)
          if job.done then pcall(job.done) end
        end
        break -- one message a tick
      elseif result == "wait" then
        job.waits = (job.waits or 0) + 1
        if job.waits > 20 then table.remove(q, i) end
        share.holdUntil = now + 3
      else
        table.remove(q, i)
      end
    end
  end
  if #q > 0 then schedulePump() end
end

local function syncState()
  local db = initDB()
  if type(db.sync) ~= "table" then db.sync = {} end
  if type(db.sync.own) ~= "table" then db.sync.own = {} end
  return db.sync
end

-- This account's characters in this guild that have crafting, with the version last shared:
-- { [name] = { crafter = ..., version = { updated, sig, by, sent } } }. A new version is stamped
-- when a character's crafting differs from what was last shared.
local function ownCrafters()
  local out = {}
  local guild = myGuild()
  if guild == "" or not Sync then return out end
  local db, st = initDB(), syncState()
  for name, rec in pairs(db.characters) do
    if type(rec) == "table" and rec.guild == guild then
      local c = Sync.crafterFromCharacter(rec)
      if c then
        local sig = Sync.encodeCrafter(c)
        local v = st.own[name]
        if type(v) ~= "table" or v.sig ~= sig then
          local stamp = time()
          if type(v) == "table" and num(v.updated, 0) >= stamp then stamp = v.updated + 1 end
          v = { updated = stamp, sig = sig, by = readName() }
          st.own[name] = v
        end
        c.by = v.by
        out[name] = { crafter = c, version = v }
      end
    end
  end
  return out
end

-- This account's bank record (a bank alt's, or a guild bank it opened) when it's this guild's.
local function ownBank()
  local db = initDB()
  local b = db.bank
  if not Sync or type(b) ~= "table" or type(b.tabs) ~= "table" then return nil end
  local guild = myGuild()
  local rec = db.characters[str(b.by)]
  if guild == "" or type(rec) ~= "table" or rec.guild ~= guild then return nil end
  return b, Sync.encodeBank(b)
end

-- This account's random id, made once: the subject of its A payloads, so a new main replaces the old.
local function accountId()
  local st = syncState()
  if type(st.accountId) ~= "string" or st.accountId == "" then
    st.accountId = Sync.b36(time()) .. Sync.b36(floor(rand(0, 1) * 2000000000))
  end
  return st.accountId
end

-- This account's characters in this guild and its main, with the version last shared (stamped anew
-- when they change: a level, a profession, a new main).
local function ownAccount()
  local guild = myGuild()
  if guild == "" or not Sync then return nil end
  local db, st = initDB(), syncState()
  local a = Sync.accountFromCharacters(db.characters, guild, type(db.mains) == "table" and db.mains[guild] or nil)
  if not a then return nil end
  local sig = Sync.encodeAccount(a)
  local v = st.ownAccount
  if type(v) ~= "table" or v.sig ~= sig then
    local stamp = time()
    if type(v) == "table" and num(v.updated, 0) >= stamp then stamp = v.updated + 1 end
    v = { updated = stamp, sig = sig }
    st.ownAccount = v
  end
  return a, v, sig
end

-- Sends what changed since it was last sent.
local function shareOwn()
  if not canShare() then return end
  local st = syncState()
  for name, mine in pairs(ownCrafters()) do
    local v = mine.version
    if v.sent ~= v.updated then
      enqueue("C", name, v.updated, Sync.encodeCrafter(mine.crafter), 0, false, function() v.sent = v.updated end)
    end
  end
  local b, body = ownBank()
  if b and st.bankSent ~= body then
    enqueue("B", str(b.by), num(b.updated, time()), body, 0, false, function() st.bankSent = body end)
  end
  local a, v, abody = ownAccount()
  if a and v.sent ~= v.updated then
    enqueue("A", accountId(), v.updated, abody, 0, false, function() v.sent = v.updated end)
  end
end

local function answerRequest(req, asker)
  if not canShare() then return end
  local db = initDB()
  local mine = ownCrafters()
  for name, m in pairs(mine) do
    if m.version.updated > num(req.crafters[name], 0) then
      enqueue("C", name, m.version.updated, Sync.encodeCrafter(m.crafter), rand(1, 3), true)
    end
  end
  for name, c in pairs(db.shared.crafters) do
    if not mine[name] and name ~= asker and type(c) == "table" and num(c.updated, 0) > num(req.crafters[name], 0) then
      enqueue("C", name, c.updated, Sync.encodeCrafter(c), rand(4, 12), true)
    end
  end
  local b, body = ownBank()
  local sb = db.shared.bank
  if type(sb) ~= "table" or type(sb.tabs) ~= "table" then sb = nil end
  if b and num(b.updated, 0) > num(req.bank, 0) and (not sb or num(b.updated, 0) >= num(sb.updated, 0)) then
    enqueue("B", str(b.by), b.updated, body, rand(1, 3), true)
  elseif sb and num(sb.updated, 0) > num(req.bank, 0) then
    enqueue("B", str(sb.by), sb.updated, Sync.encodeBank(sb), rand(4, 12), true)
  end
  local stamps = req.accounts or {}
  local a, v, abody = ownAccount()
  local me = accountId()
  if a and v.updated > num(stamps[me], 0) then enqueue("A", me, v.updated, abody, rand(1, 3), true) end
  for id, acct in pairs(db.shared.accounts) do
    if id ~= me and type(acct) == "table" and num(acct.updated, 0) > num(stamps[id], 0) then
      enqueue("A", id, acct.updated, Sync.encodeAccount(acct), rand(4, 12), true)
    end
  end
end

-- Asks the guild for anything newer than what this client holds.
local function sendRequest()
  if not canShare() then return end
  local db, st = initDB(), syncState()
  local stamps = {}
  for name, c in pairs(db.shared.crafters) do
    if type(c) == "table" then stamps[name] = num(c.updated, 0) end
  end
  for name, m in pairs(ownCrafters()) do stamps[name] = m.version.updated end
  local bankStamp = type(db.shared.bank) == "table" and num(db.shared.bank.updated, 0) or 0
  local b = ownBank()
  if b and num(b.updated, 0) > bankStamp then bankStamp = num(b.updated, 0) end
  local accounts = {}
  for id, acct in pairs(db.shared.accounts) do
    if type(acct) == "table" then accounts[id] = num(acct.updated, 0) end
  end
  local _, v = ownAccount()
  if v then accounts[accountId()] = v.updated end
  st.lastRequest = time()
  enqueue("R", readName(), time(), Sync.encodeRequest(bankStamp, stamps, accounts), 0, false)
end

-- A window opened: ask at most once an hour (every 5 minutes while there's nothing to show).
local function maybeRequest(haveNothing)
  local since = time() - num(syncState().lastRequest, 0)
  if since > REQUEST_EVERY or (haveNothing and since > 300) then sendRequest() end
end

local function onPayload(p, who)
  local db = initDB()
  if p.kind == "C" then
    if db.characters[p.subject] then return end -- this account's own: ours is the source
    local c = Sync.decodeCrafter(p.body)
    if c and Sync.storeCrafter(db.shared.crafters, p.subject, p.updated, c, who, time()) and refreshWindows then
      refreshWindows()
    end
  elseif p.kind == "B" then
    if db.characters[p.subject] then return end
    local b = Sync.decodeBank(p.body)
    local stored = b and Sync.storeBank(db.shared.bank, p.subject, p.updated, b, who)
    if stored then
      db.shared.bank = stored
      if refreshWindows then refreshWindows() end
    end
  elseif p.kind == "A" then
    if p.subject == accountId() then return end
    local a = Sync.decodeAccount(p.body)
    if a and Sync.storeAccount(db.shared.accounts, p.subject, p.updated, a, who, time()) then alts.index = nil end
  elseif p.kind == "R" then
    local req = Sync.decodeRequest(p.body)
    if req then answerRequest(req, p.subject) end
  end
end

-- Someone else is sending a payload: an answer of ours for the same (or older) data is dropped if
-- it hasn't started. If both started, the sender whose name sorts first carries on and the other
-- stops, so receivers get one whole copy.
local function dropAnswers(h, who)
  local q, me = share.queue, readName()
  for i = #q, 1, -1 do
    local job = q[i]
    if job.answer and job.kind == h.kind and job.subject == h.subject and job.updated <= h.updated
      and (not job.msgs or job.updated < h.updated or who < me) then
      table.remove(q, i)
    end
  end
end

local function onAddonMessage(prefix, text, channel, sender)
  if prefix ~= PREFIX or channel ~= "GUILD" or not Sync then return end
  local who = stripRealm(sender)
  if who == "" or who == readName() then return end
  local p, h = Sync.assemble(share.assembler, sender, text, clock())
  if h then dropAnswers(h, who) end
  if p then onPayload(p, who) end
end

onDataChanged = function()
  alts.index = nil
  share.changeGen = share.changeGen + 1
  local gen = share.changeGen
  after(CHANGE_DELAY, function()
    if gen == share.changeGen and loggedIn then shareOwn() end
  end)
  if refreshWindows then refreshWindows() end
end

local function onLogin()
  registerPrefix()
  if share.loginDone then return end
  share.loginDone = true
  after(rand(5, 20), function()
    if Sync then
      Sync.prune(initDB().shared.crafters, time(), CRAFTER_MAX_AGE)
      Sync.prune(initDB().shared.accounts, time(), CRAFTER_MAX_AGE)
    end
    alts.index = nil
    shareOwn()
  end)
  -- mains and alts are wanted without opening a window; asked once a guild logging in together has
  -- pushed what it has, so answers only fill real gaps
  after(rand(40, 70), function() maybeRequest(false) end)
end

registerPrefix()

-- ---------------------------------------------------------- mains and alts --
-- Each account shares its characters in the guild and which is its main (A payloads above). Guild
-- chat shows a speaker's main in front of what they say on an alt: "(Morwen) hi". Only what this
-- client shows changes; the message itself is never touched. Unit tooltips say "Alt of Morwen" or
-- "Alts: ...", and the professions. FantasyForceDB.mainOf (every known character to its main) is
-- kept for the website.

-- { [characterName] = { main, account, alts, char } }: guildmates' accounts plus this one.
local function mainIndex()
  if alts.index then return alts.index end
  local db = initDB()
  local accounts = {}
  for id, a in pairs(db.shared.accounts) do accounts[id] = a end
  local own = ownAccount()
  if own then accounts[accountId()] = { updated = math.huge, main = own.main, chars = own.chars } end
  local index = Sync and Sync.mainIndex(accounts) or {}
  local mainOf = {}
  for name, e in pairs(index) do mainOf[name] = e.main end
  db.mainOf = mainOf
  alts.index = index
  return index
end

-- A chat message filter: (Main) in front of a line said on an alt.
local function guildChatFilter(_, _, msg, author, ...)
  if initDB().tags == false then return false end
  local ok, tagged = pcall(function()
    local name = stripRealm(author)
    local e = mainIndex()[name]
    if e and e.main ~= name and e.main ~= "" then return "(" .. e.main .. ") " .. msg end
  end)
  if ok and tagged then return false, tagged, author, ... end
  return false
end

local function registerChatFilters()
  local add = (ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter) or ChatFrame_AddMessageEventFilter
  if type(add) ~= "function" then return end
  pcall(add, "CHAT_MSG_GUILD", guildChatFilter)
  pcall(add, "CHAT_MSG_OFFICER", guildChatFilter)
end

local function profText(c)
  local parts = {}
  for _, p in ipairs(type(c) == "table" and c.profs or {}) do parts[#parts + 1] = p.name .. " " .. num(p.skill, 0) end
  return table.concat(parts, ", ")
end

-- Adds the main or alts and the professions to a guild member's unit tooltip.
local function unitTooltip(tt)
  pcall(function()
    local _, unit = tt:GetUnit()
    if not unit or not try(UnitIsPlayer, unit) then return end
    local name = stripRealm(str((try(UnitName, unit))))
    local e = name ~= "" and mainIndex()[name]
    if not e then return end
    if e.main ~= name then
      tt:AddLine("Alt of " .. e.main, 0.55, 0.8, 1)
    elseif #e.alts > 0 then
      local list = {}
      for _, c in ipairs(e.alts) do list[#list + 1] = c.name .. " (" .. num(c.level, 0) .. ")" end
      tt:AddLine("Alts: " .. table.concat(list, ", "), 0.55, 0.8, 1, true)
    end
    local profs = profText(e.char)
    if profs ~= "" then tt:AddLine(profs, 0.8, 0.8, 0.8, true) end
    tt:Show()
  end)
end

local function hookTooltips()
  local T = TooltipDataProcessor
  local unitType = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit
  if T and type(T.AddTooltipPostCall) == "function" and unitType ~= nil then
    local function post(tt) if tt == GameTooltip then unitTooltip(tt) end end
    if pcall(T.AddTooltipPostCall, unitType, post) then return end
  end
  if GameTooltip and GameTooltip.HookScript then pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", unitTooltip) end
end

registerChatFilters()
hookTooltips()

-- ----------------------------------------------------------------- windows --
-- Two movable windows, openable anywhere: /ff bank (the guild bank) and /ff crafts (who can make
-- what). Both are built by ui.make: a title, a search box, a row of filter buttons, a scrolling list
-- and a footer line. Item and spell names the game hasn't loaded yet fill in when they arrive.

local ROW_H = 20
local FILTER_TOP = -56
local QUESTION_ICON = "Interface\\Icons\\INV_Misc_QuestionMark"
local ONLINE_ICON = "|TInterface\\FriendsFrame\\StatusIcon-Online:12:12|t"
local ui = { windows = {}, onlineAt = 0, redrawQueued = false }

local function itemInfo(id)
  return try((C_Item and C_Item.GetItemInfo) or GetItemInfo, id)
end

local function itemName(id)
  local n = try(C_Item and C_Item.GetItemNameByID, id)
  if type(n) ~= "string" or n == "" then n = itemInfo(id) end
  if type(n) == "string" and n ~= "" then return n end
  try(C_Item and C_Item.RequestLoadItemDataByID, id)
  return nil
end

local function itemIcon(id)
  local icon = try(C_Item and C_Item.GetItemIconByID, id) or try(GetItemIcon, id)
  if not icon then
    local _, _, _, _, i = try((C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant, id)
    icon = i
  end
  return icon
end

local function itemQualityColor(id)
  local q = try(C_Item and C_Item.GetItemQualityByID, id)
  if type(q) ~= "number" then
    local _, _, iq = itemInfo(id)
    q = iq
  end
  local c = type(q) == "number" and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  if type(c) == "table" and c.r then return c.r, c.g, c.b end
  return 1, 1, 1
end

local function itemLink(id)
  local _, link = itemInfo(id)
  if type(link) == "string" then return link end
end

local function spellName(id)
  local n = try(C_Spell and C_Spell.GetSpellName, id)
  if type(n) ~= "string" then
    local info = try(C_Spell and C_Spell.GetSpellInfo, id)
    if type(info) == "table" then n = info.name end
  end
  if type(n) ~= "string" then n = try(GetSpellInfo, id) end
  if type(n) == "string" and n ~= "" then return n end
  try(C_Spell and C_Spell.RequestLoadSpellData, id)
  return nil
end

local function spellIcon(id)
  local icon = try(C_Spell and C_Spell.GetSpellTexture, id)
  if not icon then
    local info = try(C_Spell and C_Spell.GetSpellInfo, id)
    if type(info) == "table" then icon = info.iconID end
  end
  if not icon then icon = try(GetSpellTexture, id) end
  if not icon then
    local _, _, i = try(GetSpellInfo, id)
    icon = i
  end
  return icon
end

local function spellLink(id)
  local link = try(C_Spell and C_Spell.GetSpellLink, id) or try(GetSpellLink, id)
  if type(link) == "string" then return link end
end

local function openChat(text)
  try((ChatFrameUtil and ChatFrameUtil.OpenChat) or ChatFrame_OpenChat, text)
end

local function linkInChat(link)
  if type(link) ~= "string" then return end
  if not try((ChatFrameUtil and ChatFrameUtil.InsertLink) or ChatEdit_InsertLink, link) then openChat(link) end
end

local function whisper(name)
  if type(name) == "string" and name ~= "" then openChat("/w " .. name .. " ") end
end

local function shiftDown()
  return try(IsShiftKeyDown) and true or false
end

local function hideTooltip()
  if GameTooltip then try(GameTooltip.Hide, GameTooltip) end
end

-- Who in the guild is online now, read from the guild roster (looked at most every 15 s).
local function onlineNames()
  local now = time()
  if ui.online and now - ui.onlineAt < 15 then return ui.online end
  local set = {}
  for i = 1, num(try(GetNumGuildMembers), 0) do
    local name, _, _, _, _, _, _, _, online = try(GetGuildRosterInfo, i)
    if online and type(name) == "string" then set[stripRealm(name)] = true end
  end
  set[readName()] = true
  ui.online, ui.onlineAt = set, now
  return set
end

local function classHex(class)
  local c = (CUSTOM_CLASS_COLORS and CUSTOM_CLASS_COLORS[class]) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
  if type(c) ~= "table" or not c.r then return "|cffffffff" end
  return string.format("|cff%02x%02x%02x", floor(c.r * 255), floor(c.g * 255), floor(c.b * 255))
end

local function ago(t)
  t = num(t, 0)
  if t <= 0 then return "never" end
  local s = time() - t
  if s < 120 then return "just now" end
  if s < 7200 then return floor(s / 60) .. " min ago" end
  if s < 172800 then return floor(s / 3600) .. " h ago" end
  return floor(s / 86400) .. " days ago"
end

local function moneyText(m)
  m = floor(num(m, 0))
  local s = try(GetCoinTextureString, m)
  if type(s) == "string" and s ~= "" then return s end
  return floor(m / 10000) .. "g " .. (floor(m / 100) % 100) .. "s " .. (m % 100) .. "c"
end

local function setColor(tex, r, g, b, a)
  if tex.SetColorTexture then tex:SetColorTexture(r, g, b, a) else tex:SetTexture(r, g, b, a) end
end

local function newFrame(kind, name, parent, template)
  local ok, f = pcall(CreateFrame, kind, name, parent, template)
  if ok and f then return f end
  return nil
end

local function searchText(w)
  local t = w.search and try(w.search.GetText, w.search)
  return str(t):lower():gsub("^%s+", ""):gsub("%s+$", "")
end

-- Rows only (scrolling): what's in w.items from w.offset.
function ui.draw(w)
  for i = 1, w.visible do
    local row = w.rows[i] or ui.newRow(w, i)
    if row then
      local item = w.items[w.offset + i]
      row.data = item
      if item then
        w.fill(w, row, item)
        row:Show()
      else
        row:Hide()
      end
    end
  end
  for i = w.visible + 1, #w.rows do w.rows[i]:Hide() end
end

function ui.scroll(w, offset)
  local maxOffset = math.max(0, #w.items - w.visible)
  offset = math.max(0, math.min(maxOffset, floor(offset)))
  if offset == w.offset then return end
  w.offset = offset
  if w.slider then w.slider:SetValue(offset) end
  ui.draw(w)
end

local function filterButton(w, i)
  local b = w.filterButtons[i]
  if b then return b end
  b = newFrame("Button", nil, w.frame)
  if not b then return nil end
  b:SetHeight(18)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.text:SetPoint("CENTER")
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  setColor(hl, 1, 1, 1, 0.12)
  b:SetScript("OnClick", function(self)
    w.filter = self.value
    w.offset = 0
    pcall(ui.render, w)
  end)
  w.filterButtons[i] = b
  return b
end

-- Rebuilds what the window shows: filters, rows, footer.
function ui.render(w)
  if not (w.frame and w.frame:IsShown()) then return end
  local data = w.build(w)
  local names, known = { "All" }, {}
  for _, n in ipairs(data.filters) do
    names[#names + 1] = n
    known[n] = true
  end
  if w.filter and not known[w.filter] then
    w.filter = nil
    data = w.build(w)
  end
  local x, y, maxX = 0, 0, w.width - 24
  for i, n in ipairs(names) do
    local b = filterButton(w, i)
    if b then
      b.value = i > 1 and n or nil
      b.text:SetText(n)
      local bw = num(try(b.text.GetStringWidth, b.text), 40) + 14
      if x > 0 and x + bw > maxX then x, y = 0, y + 20 end
      b:SetWidth(bw)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", w.frame, "TOPLEFT", 12 + x, FILTER_TOP - y)
      -- the picked filter is shown by colour, never a size change
      if b.value == w.filter then
        b.text:SetTextColor(1, 0.82, 0)
        setColor(b.bg, 0.35, 0.27, 0.05, 0.9)
      else
        b.text:SetTextColor(0.75, 0.75, 0.75)
        setColor(b.bg, 0.12, 0.12, 0.12, 0.8)
      end
      b:Show()
      x = x + bw + 4
    end
  end
  for i = #names + 1, #w.filterButtons do w.filterButtons[i]:Hide() end

  local listTop = FILTER_TOP - y - 24
  w.list:ClearAllPoints()
  w.list:SetPoint("TOPLEFT", w.frame, "TOPLEFT", 12, listTop)
  w.list:SetPoint("BOTTOMRIGHT", w.frame, "BOTTOMRIGHT", -28, 30)
  w.visible = math.max(1, floor((w.height + listTop - 30) / ROW_H))
  w.items = data.rows
  local maxOffset = math.max(0, #w.items - w.visible)
  if w.offset > maxOffset then w.offset = maxOffset end
  if w.slider then
    w.slider:SetMinMaxValues(0, maxOffset)
    w.slider:SetValue(w.offset)
    if maxOffset > 0 then w.slider:Show() else w.slider:Hide() end
  end
  ui.draw(w)
  w.footer:SetText(data.footer or "")
  if #w.items == 0 then
    w.empty:SetText(data.empty or "")
    w.empty:Show()
  else
    w.empty:Hide()
  end
end

function ui.newRow(w, i)
  local row = newFrame("Button", nil, w.list)
  if not row then return nil end
  row:SetHeight(ROW_H)
  row:SetPoint("TOPLEFT", w.list, "TOPLEFT", 0, -(i - 1) * ROW_H)
  row:SetPoint("RIGHT", w.list, "RIGHT", 0, 0)
  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  setColor(hl, 1, 1, 1, 0.08)
  row.icon = row:CreateTexture(nil, "ARTWORK")
  row.icon:SetSize(16, 16)
  row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
  row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.label:SetPoint("LEFT", row.icon, "RIGHT", 6, 0)
  row.label:SetWidth(w.nameWidth)
  row.label:SetJustifyH("LEFT")
  try(row.label.SetWordWrap, row.label, false)
  row.right = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.right:SetPoint("RIGHT", row, "RIGHT", -4, 0)
  row.right:SetJustifyH("RIGHT")
  try(row.RegisterForClicks, row, "LeftButtonUp")
  row:SetScript("OnEnter", function(self) if self.data then pcall(w.enter, w, self, self.data) end end)
  row:SetScript("OnLeave", hideTooltip)
  row:SetScript("OnClick", function(self) if self.data then pcall(w.click, w, self.data, nil) end end)
  try(row.EnableMouseWheel, row, true)
  row:SetScript("OnMouseWheel", function(_, delta) ui.scroll(w, w.offset - delta * 3) end)
  if w.decorate then w.decorate(w, row) end
  w.rows[i] = row
  return row
end

-- Builds w's frame. Errors (a missing template or method) are caught by the caller.
function ui.make(w)
  local name = "FantasyForce" .. w.key .. "Window"
  local f = newFrame("Frame", name, UIParent, "BasicFrameTemplateWithInset")
  local framed = f and (f.CloseButton or f.TitleBg or f.Inset or f.InsetBg) and true or false
  if not framed then
    if not f then f = newFrame("Frame", name .. "B", UIParent, "BackdropTemplate") or newFrame("Frame", name .. "P", UIParent) end
    if not f then return false end
    if f.SetBackdrop then
      pcall(f.SetBackdrop, f, {
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true, tileSize = 32, edgeSize = 24,
        insets = { left = 6, right = 6, top = 6, bottom = 6 },
      })
    else
      local bg = f:CreateTexture(nil, "BACKGROUND")
      bg:SetAllPoints()
      setColor(bg, 0.05, 0.05, 0.05, 0.92)
    end
    local close = newFrame("Button", nil, f, "UIPanelCloseButton")
    if close then close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2) end
  end
  w.frame = f
  f:Hide()
  f:SetSize(w.width, w.height)
  f:SetFrameStrata("HIGH")
  try(f.SetToplevel, f, true)
  try(f.SetClampedToScreen, f, true)
  try(f.SetDontSavePosition, f, true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, relPoint, x, y = self:GetPoint(1)
    local db = initDB()
    if type(db.windows) ~= "table" then db.windows = {} end
    db.windows[w.key] = { point = point, relPoint = relPoint, x = x, y = y }
  end)
  local pos = type(initDB().windows) == "table" and initDB().windows[w.key]
  f:ClearAllPoints()
  if type(pos) == "table" and type(pos.point) == "string" then
    f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, num(pos.x, 0), num(pos.y, 0))
  else
    f:SetPoint("CENTER", UIParent, "CENTER", w.startX or 0, 0)
  end
  if type(UISpecialFrames) == "table" then table.insert(UISpecialFrames, f:GetName() or name) end

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  title:SetPoint("TOP", f, "TOP", 0, framed and -5 or -12)
  title:SetText(w.title)

  local sb = newFrame("EditBox", name .. "Search", f, "SearchBoxTemplate")
    or newFrame("EditBox", name .. "SearchInput", f, "InputBoxTemplate")
  if not sb then
    sb = newFrame("EditBox", nil, f)
    if sb then
      sb:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
      local bg = sb:CreateTexture(nil, "BACKGROUND")
      bg:SetAllPoints()
      setColor(bg, 0, 0, 0, 0.5)
    end
  end
  if sb then
    sb:SetSize(200, 20)
    sb:SetPoint("TOPLEFT", f, "TOPLEFT", 18, -28)
    sb:SetAutoFocus(false)
    local function changed()
      w.offset = 0
      pcall(ui.render, w)
    end
    if sb.HookScript then sb:HookScript("OnTextChanged", changed) else sb:SetScript("OnTextChanged", changed) end
    local function unfocus(self) self:ClearFocus() end
    if sb.HookScript then
      sb:HookScript("OnEscapePressed", unfocus)
      sb:HookScript("OnEnterPressed", unfocus)
    end
    w.search = sb
  end

  local list = newFrame("Frame", nil, f)
  w.list = list
  try(list.EnableMouseWheel, list, true)
  list:SetScript("OnMouseWheel", function(_, delta) ui.scroll(w, w.offset - delta * 3) end)
  local sl = newFrame("Slider", nil, f)
  if sl then
    sl:SetOrientation("VERTICAL")
    sl:SetWidth(12)
    sl:SetPoint("TOPLEFT", list, "TOPRIGHT", 6, 0)
    sl:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 6, 0)
    local track = sl:CreateTexture(nil, "BACKGROUND")
    track:SetAllPoints()
    setColor(track, 0, 0, 0, 0.45)
    sl:SetThumbTexture("Interface\\Buttons\\UI-ScrollBar-Knob")
    local thumb = try(sl.GetThumbTexture, sl)
    if thumb then thumb:SetSize(18, 24) end
    sl:SetMinMaxValues(0, 0)
    sl:SetValueStep(1)
    try(sl.SetObeyStepOnDrag, sl, true)
    sl:SetScript("OnValueChanged", function(_, v)
      local o = floor(num(v, 0) + 0.5)
      if o ~= w.offset then
        w.offset = o
        ui.draw(w)
      end
    end)
    w.slider = sl
  end

  w.footer = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  w.footer:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 14, 11)
  w.footer:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -14, 11)
  w.footer:SetJustifyH("LEFT")
  w.empty = list:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  w.empty:SetPoint("CENTER", list, "CENTER", 0, 0)
  w.empty:SetWidth(w.width - 80)

  w.rows, w.filterButtons, w.items, w.offset, w.visible = {}, {}, {}, 0, 0
  f:SetScript("OnShow", function() pcall(ui.render, w) end)
  f:SetScript("OnHide", hideTooltip)
  return true
end

-- Fills the tooltip over owner with an item, else a spell, else just a name.
local function recipeTooltip(owner, item, spell, name)
  local tt = GameTooltip
  if not tt then return nil end
  try(tt.SetOwner, tt, owner, "ANCHOR_RIGHT")
  local shown = false
  if item then shown = pcall(tt.SetItemByID, tt, item) or pcall(tt.SetHyperlink, tt, "item:" .. item) end
  if not shown and spell then shown = pcall(tt.SetSpellByID, tt, spell) or pcall(tt.SetHyperlink, tt, "spell:" .. spell) end
  if not shown then try(tt.SetText, tt, str(name)) end
  return tt
end

-- ------------------------------------------------------------ bank window --

local function bankData()
  local db = initDB()
  local own = type(db.bank) == "table" and type(db.bank.tabs) == "table" and db.bank or nil
  local sh = db.shared.bank
  if type(sh) ~= "table" or type(sh.tabs) ~= "table" then sh = nil end
  if own and sh then
    if num(sh.updated, 0) > num(own.updated, 0) then return sh end
    return own
  end
  return own or sh
end

local bankWindow = { key = "Bank", title = "Fantasy Force: Guild Bank", width = 420, height = 460, nameWidth = 250, startX = -240 }

function bankWindow.build(w)
  local out = { rows = {}, filters = {}, footer = "",
    empty = "No bank yet: the bank alt types /ff bankalt and logs in with the addon on." }
  local bank = bankData()
  if not bank then return out end
  local search = searchText(w)
  for _, t in ipairs(bank.tabs) do
    local tab = str(type(t) == "table" and t.name)
    if type(t) == "table" and type(t.items) == "table" then
      out.filters[#out.filters + 1] = tab
      if w.filter == nil or w.filter == tab then
        for _, it in ipairs(t.items) do
          local id = type(it) == "table" and tonumber(it.id)
          if id then
            local name = itemName(id) or str(it.name)
            if name == "" then name = "Item " .. id end
            if search == "" or name:lower():find(search, 1, true) then
              out.rows[#out.rows + 1] = { id = id, name = name, count = floor(num(it.count, 1)), tab = tab }
            end
          end
        end
      end
    end
  end
  table.sort(out.rows, function(a, b)
    if a.name ~= b.name then return a.name < b.name end
    return a.tab < b.tab
  end)
  if #out.rows == 0 then out.empty = search ~= "" and "Nothing matches." or "Nothing here." end
  out.footer = moneyText(bank.money) .. "    Updated " .. ago(bank.updated) .. " by " .. str(bank.by)
  return out
end

function bankWindow.fill(w, row, it)
  row.icon:SetTexture(itemIcon(it.id) or QUESTION_ICON)
  row.label:SetText(it.name)
  row.label:SetTextColor(itemQualityColor(it.id))
  row.right:SetText(it.count .. "   |cff8c8c8c" .. it.tab .. "|r")
end

function bankWindow.enter(w, row, it)
  local tt = recipeTooltip(row, it.id, nil, it.name)
  if tt then try(tt.Show, tt) end
end

function bankWindow.click(w, it)
  if shiftDown() then linkInChat(itemLink(it.id)) end
end

function bankWindow.isEmpty()
  return bankData() == nil
end

-- ---------------------------------------------------------- crafts window --

-- Every known recipe with who can make it: this account's characters and what guildmates shared.
-- Returns the recipe list, the professions with recipes, and the account groups (characters a
-- guildmate's addon shared together, so an online alt can be whispered for an offline crafter).
local function craftsIndex()
  local db = initDB()
  local list, byKey, profs, groups = {}, {}, {}, {}
  local function add(char, c, prof, skill, r, group, own)
    local key = prof .. "#" .. (r.id and ("s" .. r.id) or r.item and ("i" .. r.item) or ("n" .. str(r.name):lower()))
    local e = byKey[key]
    if not e then
      e = { prof = prof, id = r.id, item = r.item, name = r.name, crafters = {}, seen = {} }
      byKey[key] = e
      list[#list + 1] = e
      profs[prof] = true
    end
    if not e.item and r.item then e.item = r.item end
    if not e.name and r.name then e.name = r.name end
    if not e.seen[char] then
      e.seen[char] = true
      e.crafters[#e.crafters + 1] = { name = char, class = str(c.class), skill = skill, group = group, own = own }
    end
  end
  local function addCrafter(char, c, group, own)
    if type(c) ~= "table" or type(c.professions) ~= "table" then return end
    for prof, p in pairs(c.professions) do
      if type(p) == "table" and type(p.recipes) == "table" then
        for _, r in ipairs(p.recipes) do
          if type(r) == "table" then add(char, c, prof, num(p.skill, 0), r, group, own) end
        end
      end
    end
  end
  if Sync then
    for name, rec in pairs(db.characters) do addCrafter(name, Sync.crafterFromCharacter(rec), nil, true) end
  end
  for name, c in pairs(db.shared.crafters) do
    if type(c) == "table" and not db.characters[name] then
      local group = str(c.by) ~= "" and c.by or name
      groups[group] = groups[group] or { group }
      if name ~= group then table.insert(groups[group], name) end
      addCrafter(name, c, group, false)
    end
  end
  local profList = {}
  for p in pairs(profs) do profList[#profList + 1] = p end
  table.sort(profList)
  return list, profList, groups
end

local function recipeName(e)
  if e.resolved then return e.resolved end
  local n = e.name or (e.id and spellName(e.id)) or (e.item and itemName(e.item))
  if n then
    e.resolved = n
    return n
  end
  return e.id and ("Recipe " .. e.id) or ("Item " .. str(e.item))
end

local craftsWindow = { key = "Crafts", title = "Fantasy Force: Guild Crafting", width = 580, height = 480, nameWidth = 210, startX = 220 }

function craftsWindow.build(w)
  if not ui.crafts then
    local list, profs, groups = craftsIndex()
    ui.crafts = { list = list, profs = profs, groups = groups }
  end
  local idx = ui.crafts
  local out = { rows = {}, filters = idx.profs, footer = "",
    empty = "No crafting yet. Open each profession once on your characters; guildmates' recipes show up when they run FantasyForce too." }
  local online = onlineNames()
  local search = searchText(w)
  local crafterNames = {}
  for _, e in ipairs(idx.list) do
    if w.filter == nil or w.filter == e.prof then
      local name = recipeName(e)
      if search == "" or name:lower():find(search, 1, true) then
        local who = {}
        for _, c in ipairs(e.crafters) do
          crafterNames[c.name] = true
          local via
          if not online[c.name] and not c.own and c.group then
            for _, other in ipairs(idx.groups[c.group] or {}) do
              if other ~= c.name and online[other] then via = other break end
            end
          end
          who[#who + 1] = { name = c.name, class = c.class, skill = c.skill, online = online[c.name] and true or false, via = via }
        end
        table.sort(who, function(a, b)
          local ra = a.online and 2 or a.via and 1 or 0
          local rb = b.online and 2 or b.via and 1 or 0
          if ra ~= rb then return ra > rb end
          if a.skill ~= b.skill then return a.skill > b.skill end
          return a.name < b.name
        end)
        out.rows[#out.rows + 1] = { e = e, name = name, prof = e.prof, who = who }
      end
    end
  end
  table.sort(out.rows, function(a, b)
    if a.name ~= b.name then return a.name < b.name end
    return a.prof < b.prof
  end)
  if #idx.list > 0 and #out.rows == 0 then out.empty = "Nothing matches." end
  local nCrafters = 0
  for _ in pairs(crafterNames) do nCrafters = nCrafters + 1 end
  out.footer = #out.rows .. " recipes, " .. nCrafters .. " crafters.  Click a name to whisper; shift-click links."
  return out
end

local MAX_NAMES = 3

local function crafterText(c)
  if c.online then return ONLINE_ICON .. classHex(c.class) .. c.name .. "|r" end
  if c.via then return ONLINE_ICON .. "|cffbbbbbb" .. c.name .. " (" .. c.via .. ")|r" end
  return "|cff808080" .. c.name .. "|r"
end

local function recipeLink(e)
  return (e.item and itemLink(e.item)) or (e.id and spellLink(e.id)) or nil
end

-- Whispers a crafter (or the online alt for them); shift-click links the recipe instead.
function craftsWindow.click(w, d, c)
  if shiftDown() then
    linkInChat(recipeLink(d.e))
    return
  end
  if not c then
    c = d.who[1]
    if not (c and (c.online or c.via)) then return end -- nobody online to whisper
  end
  if c.name == readName() then return end
  whisper(c.via or c.name)
end

function craftsWindow.enter(w, row, d)
  local e = d.e
  local tt = recipeTooltip(row, e.item, e.id, d.name)
  if not tt then return end
  try(tt.AddLine, tt, " ")
  try(tt.AddLine, tt, d.prof .. ": who can make it", 1, 0.82, 0)
  for _, c in ipairs(d.who) do
    local line = c.name .. " (" .. c.skill .. ")"
    if c.online then
      try(tt.AddLine, tt, line .. ", online", 0.25, 1, 0.25)
    elseif c.via then
      try(tt.AddLine, tt, line .. ", on " .. c.via, 0.6, 0.9, 0.6)
    else
      try(tt.AddLine, tt, line, 0.6, 0.6, 0.6)
    end
  end
  try(tt.Show, tt)
end

function craftsWindow.decorate(w, row)
  row.names = {}
  for i = 1, MAX_NAMES do
    local b = newFrame("Button", nil, row)
    if b then
      b:SetHeight(ROW_H)
      b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      b.text:SetPoint("LEFT", b, "LEFT", 0, 0)
      try(b.RegisterForClicks, b, "LeftButtonUp")
      b:SetScript("OnClick", function(self) if row.data then pcall(w.click, w, row.data, self.crafter) end end)
      b:SetScript("OnEnter", function() if row.data then pcall(w.enter, w, row, row.data) end end)
      b:SetScript("OnLeave", hideTooltip)
      try(b.EnableMouseWheel, b, true)
      b:SetScript("OnMouseWheel", function(_, delta) ui.scroll(w, w.offset - delta * 3) end)
      row.names[i] = b
    end
  end
end

function craftsWindow.fill(w, row, d)
  local e = d.e
  row.icon:SetTexture((e.item and itemIcon(e.item)) or (e.id and spellIcon(e.id)) or QUESTION_ICON)
  row.label:SetText(d.name)
  if e.item then row.label:SetTextColor(itemQualityColor(e.item)) else row.label:SetTextColor(1, 1, 1) end
  local x = w.nameWidth + 30
  local room = w.width - 40 - x - 30
  local shownCount = 0
  for i, b in ipairs(row.names or {}) do
    local c = d.who[i]
    if c then
      b.crafter = c
      b.text:SetText(crafterText(c))
      local bw = num(try(b.text.GetStringWidth, b.text), 60) + 8
      if shownCount > 0 and bw > room then
        b:Hide()
      else
        b:SetWidth(bw)
        b:ClearAllPoints()
        b:SetPoint("LEFT", row, "LEFT", x, 0)
        b:Show()
        x, room = x + bw, room - bw
        shownCount = shownCount + 1
      end
    else
      b.crafter = nil
      b:Hide()
    end
  end
  local more = #d.who - shownCount
  row.right:SetText(more > 0 and ("|cff8c8c8c+" .. more .. "|r") or "")
end

function craftsWindow.isEmpty()
  return next(initDB().shared.crafters) == nil
end

refreshWindows = function()
  ui.crafts = nil -- the data changed: rebuild the recipe index
  if ui.redrawQueued then return end
  ui.redrawQueued = true
  after(0.5, function()
    ui.redrawQueued = false
    for _, w in pairs(ui.windows) do pcall(ui.render, w) end
  end)
end

-- Names and icons the game loaded since the rows were drawn.
local function redrawSoon()
  if ui.redrawQueued then return end
  local any = false
  for _, w in pairs(ui.windows) do
    if w.frame:IsShown() then any = true end
  end
  if not any then return end
  ui.redrawQueued = true
  after(0.3, function()
    ui.redrawQueued = false
    for _, w in pairs(ui.windows) do pcall(ui.render, w) end
  end)
end

local function toggleWindow(w)
  if not ui.windows[w.key] then
    local ok, made = pcall(ui.make, w)
    if not ok or not made then
      print_("couldn't open that window in this game version.")
      return
    end
    ui.windows[w.key] = w
  end
  if w.frame:IsShown() then
    w.frame:Hide()
    return
  end
  w.frame:Show()
  requestRoster()
  maybeRequest(w.isEmpty())
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
    "CHAT_MSG_ADDON", "GET_ITEM_INFO_RECEIVED", "ITEM_DATA_LOAD_RESULT", "SPELL_DATA_LOAD_RESULT",
  }
  for ev in pairs(RECIPE_EVENTS) do events[#events + 1] = ev end
  for _, ev in ipairs(events) do
    -- An event unknown to this client must not break loading.
    pcall(frame.RegisterEvent, frame, ev)
  end

  frame:SetScript("OnEvent", function(_, event, arg1, arg2, arg3, arg4, arg5)
    if event == "CHAT_MSG_ADDON" then
      -- every addon's guild and raid messages come here: ours are picked out first thing
      pcall(onAddonMessage, arg1, arg2, arg3, arg4)
      return true
    end
    local ok = pcall(function()
      if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        loggedIn = true
        onLogin()
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
      elseif event == "GET_ITEM_INFO_RECEIVED" or event == "ITEM_DATA_LOAD_RESULT" or event == "SPELL_DATA_LOAD_RESULT" then
        redrawSoon()
      elseif event == "GUILD_ROSTER_UPDATE" then
        if loggedIn then recordGuild() end
        ui.online = nil -- who's online changed: the crafting window marks them
        redrawSoon()
      elseif event == "PLAYER_GUILD_UPDATE" then
        recordCharacter()
        alts.index = nil
        requestRoster()
      elseif RECIPE_EVENTS[event] then
        if loggedIn then recordRecipes(event) end
      elseif event == "PLAYER_LOGOUT" then
        recordCharacter()
        recordAltBank(false)
      else
        if loggedIn then
          recordCharacter()
          -- a level or a profession skill is in what mains and alts share
          if event == "PLAYER_LEVEL_UP" or event == "SKILL_LINES_CHANGED" then onDataChanged() end
        end
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
      if refreshWindows then refreshWindows() end
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
    if msg == "main" then
      local guild = myGuild()
      if guild == "" then
        print_("mains are kept per guild: join one first.")
        return
      end
      if type(db.mains) ~= "table" then db.mains = {} end
      db.mains[guild] = readName()
      recordCharacter()
      onDataChanged()
      print_(readName() .. " is now your main in " .. guild .. ".")
      return
    end
    if msg == "tags off" or msg == "tags on" then
      if msg == "tags on" then db.tags = nil else db.tags = false end
      print_(db.tags == false and "guild chat no longer shows mains in front of alts." or "guild chat shows a speaker's main in front of their alts.")
      return
    end
    if msg == "bank" then
      toggleWindow(bankWindow)
      return
    end
    if msg == "crafts" or msg == "craft" or msg == "crafting" then
      toggleWindow(craftsWindow)
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
    local shared = 0
    for _ in pairs(db.shared.crafters) do shared = shared + 1 end
    print_(chars .. " characters, " .. members .. " guild members, " .. raids .. " raids, "
      .. shared .. " guildmates' crafters shared, last update " .. last
      .. ". " .. (isBankAlt() and "This character is a bank alt." or "Not a bank alt (/ff bankalt).")
      .. " /ff bank and /ff crafts open the guild bank and crafting windows; /ff main makes this character your main."
      .. " Saved on logout or /reload. /ff reset clears.")
  end)
  if not ok then print_("something went wrong.") end
end

-- For Accent.lua's game side (AccentChat.lua), loaded after this file.
if type(ns) == "table" then
  ns.try, ns.str, ns.print, ns.after = try, str, print_, after
end
