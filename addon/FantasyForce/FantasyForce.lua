-- FantasyForce: records this account's characters and the guild roster into
-- FantasyForceDB (SavedVariables) for the Fantasy Force guild website.
-- Also records the guild bank (or a bank alt's bags and bank), raid attendance and raid loot.
-- Shares the bank and every member's crafting with guildmates who run the addon (guild addon
-- messages, format in Sync.lua). Shares each account's mains and alts too, shown in front of guild
-- chat lines and on unit tooltips. /ff opens one window (and the minimap button toggles it) with
-- tabs Bank, Crafting, Guild, Website and Options; every command is in COMMANDS (/ff help).
-- Accents (/accent, /troll) live in Accent.lua and AccentChat.lua.
-- Plain Lua 5.1; every API call is guarded so a missing function never errors.

local ADDON = "FantasyForce"
local SITE_URL = "https://xnoltanx.github.io/fantasy-force/" -- the guild website, shown on the Website tab
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

-- The game's own text colours (NORMAL_FONT_COLOR gold, HIGHLIGHT white, GRAY, GREEN), with their usual
-- values when a client lacks the global. gameColor gives r, g, b; with asCode, a |cff colour code.
local GAME_COLORS = { NORMAL = { 1, 0.82, 0 }, HIGHLIGHT = { 1, 1, 1 }, GRAY = { 0.5, 0.5, 0.5 }, GREEN = { 0.1, 1, 0.1 } }
local function gameColor(name, asCode)
  local c
  if name == "NORMAL" then c = NORMAL_FONT_COLOR
  elseif name == "GRAY" then c = GRAY_FONT_COLOR
  elseif name == "GREEN" then c = GREEN_FONT_COLOR
  else name, c = "HIGHLIGHT", HIGHLIGHT_FONT_COLOR end
  local d = GAME_COLORS[name]
  local r, g, b = d[1], d[2], d[3]
  if type(c) == "table" and type(c.r) == "number" then r, g, b = c.r, c.g, c.b end
  if asCode then return string.format("|cff%02x%02x%02x", floor(r * 255), floor(g * 255), floor(b * 255)) end
  return r, g, b
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
    DEFAULT_CHAT_FRAME:AddMessage(gameColor("NORMAL", true) .. "FantasyForce:|r " .. msg)
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
    -- every character's roles, for the site: its own pick, else its spec's usual job (Sync.rolesFor)
    if Sync then
      for _, r in pairs(db.characters) do
        if type(r) == "table" then r.roles = Sync.rolesFor(r) end
      end
    end
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

-- An id out of a game link: "item:12784:..." or "enchant:20034" / "spell:20034".
local function linkId(link, kind)
  if type(link) ~= "string" then return nil end
  return tonumber(link:match(kind .. ":(%d+)"))
end

-- What a recipe takes, { { item, count, name } }, or nil: from a recipe schematic, or from the classic
-- window's numbered reagents (numFn, infoFn, linkFn, i: GetTradeSkillNumReagents and the rest).
local function schematicReagents(schematic, numFn, infoFn, linkFn, i)
  local out = {}
  if type(schematic) == "table" then
    for _, slot in ipairs(type(schematic.reagentSlotSchematics) == "table" and schematic.reagentSlotSchematics or {}) do
      local first = type(slot) == "table" and type(slot.reagents) == "table" and slot.reagents[1]
      local id = type(first) == "table" and num(first.itemID, nil)
      if id and (slot.reagentType == nil or slot.reagentType == 1) then
        out[#out + 1] = { item = id, count = num(slot.quantityRequired, 1) }
      end
    end
  elseif type(numFn) == "function" then
    for j = 1, num(try(numFn, i), 0) do
      local name, _, count = try(infoFn, i, j)
      local id = linkId(try(linkFn, i, j), "item")
      if id or str(name) ~= "" then out[#out + 1] = { item = id, count = num(count, 1), name = str(name) ~= "" and name or nil } end
    end
  end
  if #out == 0 then return nil end
  return out
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
      out[#out + 1] = { id = id, item = item, name = info.name, reagents = schematicReagents(schematic) }
    end
  end
  return out
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
        reagents = schematicReagents(nil, GetTradeSkillNumReagents, GetTradeSkillReagentInfo, GetTradeSkillReagentItemLink, i),
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
      out[#out + 1] = { name = name, id = linkId(link, "enchant") or linkId(link, "spell"),
        reagents = schematicReagents(nil, GetCraftNumReagents, GetCraftReagentInfo, GetCraftReagentItemLink, i) }
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

-- A new bank record keeps the scan before it (when, and each item's total) when its items changed, so the
-- window can say what changed since.
local function keepPrevious(new, old)
  local function totals(b)
    local t = {}
    for _, tab in ipairs(type(b) == "table" and type(b.tabs) == "table" and b.tabs or {}) do
      for _, it in ipairs(type(tab) == "table" and type(tab.items) == "table" and tab.items or {}) do
        local id = type(it) == "table" and tonumber(it.id)
        if id then t[id] = (t[id] or 0) + num(it.count, 1) end
      end
    end
    return t
  end
  if type(new) ~= "table" or type(old) ~= "table" or type(old.tabs) ~= "table" then return new end
  local a, b, same = totals(old), totals(new), true
  for id, n in pairs(a) do if b[id] ~= n then same = false end end
  for id, n in pairs(b) do if a[id] ~= n then same = false end end
  if same then new.prev = old.prev else new.prev = { updated = old.updated, counts = a } end
  return new
end

-- A guild bank tab's log, newest last: { [itemId] = { { who, kind, count } } }, three per item at most.
local function readGuildLog(tab, log)
  if type(GetNumGuildBankTransactions) ~= "function" then return end
  for i = 1, num(try(GetNumGuildBankTransactions, tab), 0) do
    local kind, who, link, count = try(GetGuildBankTransaction, tab, i)
    local id = type(link) == "string" and tonumber(link:match("item:(%d+)"))
    if id and (kind == "deposit" or kind == "withdraw") then
      local list = log[id] or {}
      list[#list + 1] = { who = str(who), kind = kind, count = num(count, 1) }
      if #list > 3 then table.remove(list, 1) end
      log[id] = list
    end
  end
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
    local tabs, log = {}, {}
    for tab = 1, n do
      local name, icon, viewable = try(GetGuildBankTabInfo, tab)
      if type(name) == "string" and (viewable == nil or viewable) then
        local items = readGuildTab(tab)
        if #items > 0 or tab == current then guildTabCache[tab] = items end
        if guildTabCache[tab] then
          tabs[#tabs + 1] = { name = name, icon = icon, items = guildTabCache[tab] }
        end
        readGuildLog(tab, log)
      end
    end
    if #tabs == 0 then return end
    local bank = { source = "guild", updated = time(), by = readName(), tabs = tabs, log = next(log) and log or nil }
    local money = try(GetGuildBankMoney)
    if type(money) == "number" then bank.money = money end
    initDB().bank = keepPrevious(bank, initDB().bank)
    if onDataChanged then onDataChanged() end
  end)
end

local function queryGuildBankTabs()
  pcall(function()
    local n = num(try(GetNumGuildBankTabs), 0)
    for tab = 1, n do
      local _, _, viewable = try(GetGuildBankTabInfo, tab)
      if viewable == nil or viewable then
        try(QueryGuildBankTab, tab)
        try(QueryGuildBankLog, tab)
      end
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
    db.bank = keepPrevious(bank, db.bank)
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
  if p.kind ~= "R" then syncState().lastHeard = time() end
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
      db.shared.bank = keepPrevious(stored, db.shared.bank)
      if refreshWindows then refreshWindows() end
    end
  elseif p.kind == "A" then
    if p.subject == accountId() then return end
    local a = Sync.decodeAccount(p.body)
    if a and Sync.storeAccount(db.shared.accounts, p.subject, p.updated, a, who, time()) then
      alts.index = nil
      if refreshWindows then refreshWindows() end
    end
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
      local r, g, b = gameColor("NORMAL")
      tt:AddLine("Alt of " .. e.main, r, g, b)
    elseif #e.alts > 0 then
      local list = {}
      for _, c in ipairs(e.alts) do list[#list + 1] = c.name .. " (" .. num(c.level, 0) .. ")" end
      local r, g, b = gameColor("NORMAL")
      tt:AddLine("Alts: " .. table.concat(list, ", "), r, g, b, true)
    end
    local profs = profText(e.char)
    if profs ~= "" then
      local r, g, b = gameColor("HIGHLIGHT")
      tt:AddLine(profs, r, g, b, true)
    end
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

-- Whispers and links go to the addon's own chat line (AccentChat.lua), never into the game's chat box:
-- an addon writing to the game's chat box can get the game's own chat blocked and blamed on it.
local function chatLine(chatType, target, text)
  local A = type(ns) == "table" and ns.AccentChat
  if A and A.openLine then pcall(A.openLine, chatType, target, text) end
end

local function linkInChat(link)
  local A = type(ns) == "table" and ns.AccentChat
  if type(link) == "string" and A and A.insertLink then pcall(A.insertLink, link) end
end

local function whisper(name)
  if type(name) == "string" and name ~= "" then chatLine("WHISPER", name, "") end
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
  if type(c) ~= "table" or not c.r then return gameColor("HIGHLIGHT", true) end
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

-- Shown, and its parents too.
function ui.visible(f)
  if type(f) ~= "table" then return false end
  if type(f.IsVisible) == "function" then return f:IsVisible() and true or false end
  return f:IsShown() and true or false
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
      -- a filler row is room for the line above it (bag slots are two rows tall), shown only under it
      if item and (item.filler or (item.slots and i == w.visible)) then item = nil end
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
  b = ui.stockButton(w.frame, 20)
  if not b then return nil end
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
  if not (w.frame and ui.visible(w.frame)) then return end
  local data = w.build(w)
  local names, known = w.noFilters and {} or { "All" }, {}
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
      local bw = num(try(b.text.GetStringWidth, b.text), 40) + 20
      if x > 0 and x + bw > maxX then x, y = 0, y + 22 end
      b:SetWidth(bw)
      b:ClearAllPoints()
      b:SetPoint("TOPLEFT", w.frame, "TOPLEFT", 6 + x, w.filterTop - y)
      ui.styleChoice(b, b.value == w.filter)
      b:Show()
      x = x + bw + 4
    end
  end
  for i = #names + 1, #w.filterButtons do w.filterButtons[i]:Hide() end

  local listTop = w.noFilters and (w.filterTop + 2) or (w.filterTop - y - 26)
  w.list:ClearAllPoints()
  w.list:SetPoint("TOPLEFT", w.frame, "TOPLEFT", w.left or 6, listTop)
  w.list:SetPoint("BOTTOMRIGHT", w.frame, "BOTTOMRIGHT", -(w.rightInset or 24), 24)
  w.visible = math.max(1, floor((w.height + listTop - 24) / ROW_H))
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
    if w.art then w.art:Show() end
  else
    w.empty:Hide()
    if w.art then w.art:Hide() end
  end
  if w.after then pcall(w.after, w, data) end
end

function ui.newRow(w, i)
  local row = newFrame("Button", nil, w.list)
  if not row then return nil end
  row:SetHeight(ROW_H)
  -- top corners only, so the height stays ROW_H whatever the game makes of an edge plus a centre anchor
  row:SetPoint("TOPLEFT", w.list, "TOPLEFT", 0, -(i - 1) * ROW_H)
  row:SetPoint("TOPRIGHT", w.list, "TOPRIGHT", 0, -(i - 1) * ROW_H)
  -- the game's list-row highlight (the quest log's)
  local hl = row:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  try(hl.SetBlendMode, hl, "ADD")
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
  try(row.RegisterForClicks, row, "LeftButtonUp", w.rightClick and "RightButtonUp" or nil)
  row:SetScript("OnEnter", function(self) if self.data then pcall(w.enter, w, self, self.data) end end)
  row:SetScript("OnLeave", hideTooltip)
  row:SetScript("OnClick", function(self, button)
    if button == "RightButton" and not w.rightClick then return end
    if self.data then pcall(w.click, w, self.data, nil, button) end
  end)
  try(row.EnableMouseWheel, row, true)
  row:SetScript("OnMouseWheel", function(_, delta) ui.scroll(w, w.offset - delta * 3) end)
  if w.decorate then w.decorate(w, row) end
  w.rows[i] = row
  return row
end

-- A movable window with a title and a close button, its place remembered under key. Errors (a missing
-- template or method) are caught by the caller.
function ui.makeChrome(key, title, width, height)
  local name = "FantasyForce" .. key
  local f = newFrame("Frame", name, UIParent, "BasicFrameTemplateWithInset")
  local framed = f and (f.CloseButton or f.TitleBg or f.Inset or f.InsetBg) and true or false
  if not framed then
    if not f then f = newFrame("Frame", name .. "B", UIParent, "BackdropTemplate") or newFrame("Frame", name .. "P", UIParent) end
    if not f then return nil end
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
  f:Hide()
  f:SetSize(width, height)
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
    db.windows[key] = { point = point, relPoint = relPoint, x = x, y = y }
  end)
  local pos = type(initDB().windows) == "table" and initDB().windows[key]
  f:ClearAllPoints()
  if type(pos) == "table" and type(pos.point) == "string" then
    f:SetPoint(pos.point, UIParent, pos.relPoint or pos.point, num(pos.x, 0), num(pos.y, 0))
  else
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 40)
  end
  -- Escape closes it: the window takes that one key itself (adding it to the game's UISpecialFrames list
  -- would write into a table the game's own code reads). Other keys go on to the game; in combat the
  -- game won't let it keep a key, so Escape closes it and goes on too.
  try(f.EnableKeyboard, f, true)
  try(f.SetPropagateKeyboardInput, f, true)
  f:SetScript("OnKeyDown", function(self, key)
    local fight = try(InCombatLockdown) and true or false
    if key == "ESCAPE" then
      if not fight then try(self.SetPropagateKeyboardInput, self, false) end
      self:Hide()
      if not fight then after(0, function() try(self.SetPropagateKeyboardInput, self, true) end) end
    elseif not fight then
      try(self.SetPropagateKeyboardInput, self, true)
    end
  end)
  -- the template's own title when it has one, else the game's large gold font in the title bar
  local t = f.TitleText
  if not (t and t.SetText) then
    t = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    t:SetPoint("TOP", f, "TOP", 0, framed and -4 or -12)
  end
  t:SetText(title)
  f:SetScript("OnHide", hideTooltip)
  return f, framed
end

-- A searchable, filterable, scrolling list inside host (a tab page): the bank, crafting and guild
-- views are each one of these, filled by their own build, fill, enter and click.
function ui.makeView(w, host, width, height)
  w.frame, w.width, w.height, w.filterTop = host, width, height, w.filterTop or -30
  local name = "FantasyForce" .. w.key
  local sb = not w.noSearch and (newFrame("EditBox", name .. "Search", host, "SearchBoxTemplate")
    or newFrame("EditBox", name .. "SearchInput", host, "InputBoxTemplate")) or nil
  if not sb and not w.noSearch then
    sb = newFrame("EditBox", nil, host)
    if sb then
      sb:SetFontObject(ChatFontNormal or GameFontHighlightSmall)
      local bg = sb:CreateTexture(nil, "BACKGROUND")
      bg:SetAllPoints()
      setColor(bg, 0, 0, 0, 0.5)
    end
  end
  if sb then
    sb:SetSize(w.searchWidth or 200, 20)
    sb:SetPoint("TOPLEFT", host, "TOPLEFT", w.searchX or 12, -4)
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

  local list = newFrame("Frame", nil, host)
  w.list = list
  try(list.EnableMouseWheel, list, true)
  list:SetScript("OnMouseWheel", function(_, delta) ui.scroll(w, w.offset - delta * 3) end)
  -- a scroll bar in the game's slider art (the options sliders' track and the scroll bar knob)
  local sl = newFrame("Slider", nil, host, "BackdropTemplate") or newFrame("Slider", nil, host)
  if sl then
    sl:SetOrientation("VERTICAL")
    sl:SetWidth(12)
    sl:SetPoint("TOPLEFT", list, "TOPRIGHT", 6, 0)
    sl:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 6, 0)
    if sl.SetBackdrop then
      pcall(sl.SetBackdrop, sl, {
        bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 3, right = 3, top = 6, bottom = 6 },
      })
    end
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

  w.footer = host:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  w.footer:SetPoint("BOTTOMLEFT", host, "BOTTOMLEFT", 8, 6)
  w.footer:SetPoint("BOTTOMRIGHT", host, "BOTTOMRIGHT", -8, 6)
  w.footer:SetJustifyH("LEFT")
  w.empty = list:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  w.empty:SetPoint("CENTER", list, "CENTER", 0, 0)
  w.empty:SetWidth(w.emptyWidth or (width - 80))
  if w.emptyArt then
    -- small and soft, above the empty-state words, never behind them
    w.art = list:CreateTexture(nil, "ARTWORK")
    w.art:SetSize(96, 96)
    w.art:SetPoint("BOTTOM", w.empty, "TOP", 0, 12)
    w.art:SetTexture(w.emptyArt)
    try(w.art.SetAlpha, w.art, 0.75)
    w.art:Hide()
  end

  w.rows, w.filterButtons, w.items, w.offset, w.visible = {}, {}, {}, 0, 0
  host:SetScript("OnShow", function() pcall(ui.render, w) end)
  host:SetScript("OnHide", hideTooltip)
  if w.make then w.make(w, host) end
  ui.windows[w.key] = w
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

-- ---------------------------------------------------------- master/detail --
-- Bank and Crafting share one shape, like the game's profession window: a list on the left (bank tabs,
-- professions) with icons and counts, the items in the middle under foldable category headers, and the
-- picked one on the right. These are its shared pieces: the left list, the grouping, the detail pane.

-- Both tabs' list sits between the left list and the detail pane.
ui.MD = { noFilters = true, filterTop = -30, left = 164, rightInset = 262, searchX = 170, searchWidth = 170, emptyWidth = 300 }
function ui.md(w)
  for k, v in pairs(ui.MD) do if w[k] == nil then w[k] = v end end
  return w
end

-- The window's remembered settings (FantasyForceDB.windows).
function ui.state()
  local db = initDB()
  if type(db.windows) ~= "table" then db.windows = {} end
  return db.windows
end

-- An item's category from its class (GetItemInfoInstant), else from words in its name; "Other" when neither.
ui.CLASSES = { [0] = "Consumables", [1] = "Bags", [2] = "Weapons", [3] = "Gems", [5] = "Reagents", [6] = "Ammo",
  [7] = "Trade goods", [8] = "Enhancements", [9] = "Recipes", [12] = "Quest", [16] = "Glyphs" }
ui.WORDS = { { "Bag$", "Bags" }, { "Potion", "Consumables" }, { "Elixir", "Consumables" }, { "Flask", "Consumables" },
  { "Bandage", "Consumables" }, { "^Enchant ", "Enchants" }, { "^Smelt ", "Trade goods" }, { "^Bolt of", "Trade goods" },
  { "^Transmute", "Trade goods" }, { "Armor Kit", "Enhancements" }, { "Sharpening Stone", "Enhancements" },
  { "Weightstone", "Enhancements" } }
function ui.category(item, name)
  if item then
    local _, _, sub, _, _, classID = try((C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant, item)
    classID = tonumber(classID)
    if classID == 4 then return (str(sub) ~= "" and sub ~= "Miscellaneous") and (sub .. " armor") or "Armor" end
    if classID and ui.CLASSES[classID] then return ui.CLASSES[classID] end
  end
  name = str(name)
  for _, wd in ipairs(ui.WORDS) do
    if name:find(wd[1]) then return wd[2] end
  end
  return "Other"
end

-- Items under their categories, alphabetical with "Other" last: { cats = { name }, items = { [cat] = list } }.
function ui.group(items, catOf)
  local g = { cats = {}, items = {} }
  for _, it in ipairs(items) do
    local c = catOf(it)
    if not g.items[c] then
      g.items[c] = {}
      g.cats[#g.cats + 1] = c
    end
    table.insert(g.items[c], it)
  end
  table.sort(g.cats, function(a, b)
    if (a == "Other") ~= (b == "Other") then return b == "Other" end
    return a < b
  end)
  for _, c in ipairs(g.cats) do
    table.sort(g.items[c], function(a, b)
      if a.name ~= b.name then return a.name < b.name end
      return tostring(a.tie or "") < tostring(b.tie or "")
    end)
  end
  return g
end

-- A category's header row: + or -, its name in gold, how many in it.
function ui.fillHeader(row, d)
  row.icon:ClearAllPoints()
  row.icon:SetPoint("LEFT", row, "LEFT", 2, 0)
  row.icon:SetTexture(d.collapsed and "Interface\\Buttons\\UI-PlusButton-Up" or "Interface\\Buttons\\UI-MinusButton-Up")
  row.label:SetText(d.cat)
  row.label:SetTextColor(gameColor("NORMAL"))
  row.right:SetText(gameColor("GRAY", true) .. d.count .. "|r")
  if row.sel then row.sel:Hide() end
end

function ui.toggleHeader(w, d)
  w.collapsed[d.cat] = not w.collapsed[d.cat] or nil
  pcall(ui.render, w)
end

-- The picked row keeps the list's highlight lit.
function ui.decorateRow(w, row)
  row.sel = row:CreateTexture(nil, "BACKGROUND")
  row.sel:SetAllPoints()
  row.sel:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  try(row.sel.SetBlendMode, row.sel, "ADD")
  row.sel:Hide()
end

-- The remembered pick and left-list choice, loaded once; w.masterKey and w.pickKey name them.
function ui.loadState(w)
  if w.loaded then return end
  local st = ui.state()
  w.loaded, w.collapsed = true, {}
  local m = st[w.masterKey]
  w.master = m ~= "All" and m or nil
  w.pick = st[w.pickKey]
end

function ui.setPick(w, key)
  w.pick = key
  if w.detail then w.detail.offset = 0 end
  ui.state()[w.pickKey] = key
  pcall(ui.render, w)
end

-- the left list: { { value (nil for All), label, icon, count } }
function ui.masterButton(w, i)
  local b = w.masterButtons[i]
  if b then return b end
  b = newFrame("Button", nil, w.frame)
  if not b then return nil end
  b:SetSize(150, 20)
  b:SetPoint("TOPLEFT", w.frame, "TOPLEFT", 6, -4 - (i - 1) * 21)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  try(hl.SetBlendMode, hl, "ADD")
  b.sel = b:CreateTexture(nil, "BACKGROUND")
  b.sel:SetAllPoints()
  b.sel:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
  try(b.sel.SetBlendMode, b.sel, "ADD")
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetSize(18, 18)
  b.icon:SetPoint("LEFT", b, "LEFT", 2, 0)
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  b.text:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
  b.text:SetWidth(96)
  b.text:SetJustifyH("LEFT")
  try(b.text.SetWordWrap, b.text, false)
  b.count = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  b.count:SetPoint("RIGHT", b, "RIGHT", -4, 0)
  b:SetScript("OnClick", function(self)
    w.master, w.offset = self.value, 0
    ui.state()[w.masterKey] = self.value or "All"
    pcall(ui.render, w)
  end)
  w.masterButtons[i] = b
  return b
end

function ui.drawMaster(w, entries)
  for i, m in ipairs(entries) do
    local b = ui.masterButton(w, i)
    if b then
      b.value = m.value
      b.icon:SetTexture(m.icon or QUESTION_ICON)
      b.text:SetText(m.label)
      b.text:SetTextColor(gameColor(m.value == w.master and "NORMAL" or "HIGHLIGHT"))
      b.count:SetText(tostring(m.count or 0))
      if m.value == w.master then b.sel:Show() else b.sel:Hide() end
      b:Show()
    end
  end
  for i = #entries + 1, #w.masterButtons do w.masterButtons[i]:Hide() end
  return #entries
end

-- the detail pane: a big icon (the item's tooltip on hover, shift-click links it), the name in its quality
-- colour, a grey line under it, then lines: headings, and lines with an icon, a name, two small right-hand
-- columns and a button. The wheel scrolls lines that don't fit.
ui.DETAIL_LINES = 16
function ui.makeDetail(w, host)
  local d = { x = w.width - 238, offset = 0, lines = {} }
  w.detail = d
  d.icon = newFrame("Button", nil, host)
  if d.icon then
    d.icon:SetSize(37, 37)
    d.icon:SetPoint("TOPLEFT", host, "TOPLEFT", d.x, -4)
    d.icon.tex = d.icon:CreateTexture(nil, "ARTWORK")
    d.icon.tex:SetAllPoints()
    local hl = d.icon:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    try(hl.SetBlendMode, hl, "ADD")
    d.icon:SetScript("OnEnter", function(self)
      local t = d.top
      local tt = t and recipeTooltip(self, t.item, t.spell, t.name)
      if tt then try(tt.Show, tt) end
    end)
    d.icon:SetScript("OnLeave", hideTooltip)
    d.icon:SetScript("OnClick", function() if d.top and d.top.link and shiftDown() then linkInChat(d.top.link) end end)
  end
  d.name = host:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  d.name:SetPoint("TOPLEFT", host, "TOPLEFT", d.x + 45, -5)
  d.name:SetWidth(185)
  d.name:SetJustifyH("LEFT")
  d.sub = host:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  d.sub:SetPoint("TOPLEFT", d.name, "BOTTOMLEFT", 0, -3)
  d.sub:SetWidth(185)
  d.sub:SetJustifyH("LEFT")
  d.wheel = newFrame("Frame", nil, host)
  if d.wheel then
    try(d.wheel.EnableMouseWheel, d.wheel, true)
    d.wheel:SetScript("OnMouseWheel", function(_, delta)
      d.offset = math.max(0, d.offset - delta * 3)
      ui.drawDetail(w, d.top)
    end)
  end
  for i = 1, ui.DETAIL_LINES do
    local l = { icon = host:CreateTexture(nil, "ARTWORK"), text = host:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"),
      a = host:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"), b = host:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall"),
      button = ui.stockButton(host, 18) }
    l.icon:SetSize(16, 16)
    l.text:SetJustifyH("LEFT")
    try(l.text.SetWordWrap, l.text, false)
    l.a:SetWidth(30)
    l.a:SetJustifyH("RIGHT")
    l.b:SetWidth(30)
    l.b:SetJustifyH("RIGHT")
    if l.button then
      l.button:SetWidth(58)
      l.button:SetScript("OnClick", function(self) if self.spec and self.spec.onClick then pcall(self.spec.onClick) end end)
      ui.tip(l.button, function() return l.button.spec and l.button.spec.label end,
        function() return l.button.spec and l.button.spec.tip end)
    end
    d.lines[i] = l
  end
  d.none = host:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  d.none:SetPoint("TOPLEFT", host, "TOPLEFT", d.x, -10)
end

-- top = { item, spell, icon, name, color = { r, g, b }, sub, link, lines = { { head, icon, text, a, b,
-- color = "GRAY", button = { label, onClick, tip, enabled } } } }, or nil (then none, e.g. "Pick a recipe.").
function ui.drawDetail(w, top, none)
  local d = w.detail
  if not d then return end
  d.top = top
  local function show(f, on) if f then if on then f:Show() else f:Hide() end end end
  d.none:SetText(none or "")
  show(d.none, not top)
  show(d.icon, top)
  show(d.name, top)
  show(d.sub, top)
  local lines = top and top.lines or {}
  if top then
    if d.icon then d.icon.tex:SetTexture(top.icon or QUESTION_ICON) end
    d.name:SetText(top.name or "")
    local c = top.color
    if c then d.name:SetTextColor(c[1], c[2], c[3]) else d.name:SetTextColor(gameColor("HIGHLIGHT")) end
    d.sub:SetText(top.sub or "")
  end
  local x, y = d.x, -50
  local room = math.max(1, math.min(#d.lines, floor((w.height - 30 + y) / 20)))
  d.offset = math.max(0, math.min(d.offset, #lines - room))
  if d.wheel then
    d.wheel:ClearAllPoints()
    d.wheel:SetPoint("TOPLEFT", w.frame, "TOPLEFT", x, y)
    d.wheel:SetSize(232, room * 20)
  end
  for i, l in ipairs(d.lines) do
    local spec = i <= room and lines[d.offset + i]
    local ly = y - (i - 1) * 20
    show(l.icon, spec and spec.icon)
    show(l.text, spec)
    show(l.a, spec and spec.a)
    show(l.b, spec and spec.b)
    show(l.button, spec and spec.button)
    if spec then
      local tx = x + (spec.icon and 22 or 0)
      if spec.icon then
        l.icon:ClearAllPoints()
        l.icon:SetPoint("TOPLEFT", w.frame, "TOPLEFT", x + 2, ly - 1)
        l.icon:SetTexture(spec.icon)
      end
      l.text:ClearAllPoints()
      l.text:SetPoint("TOPLEFT", w.frame, "TOPLEFT", tx, ly - 4)
      l.text:SetWidth((spec.button or spec.a) and (104 - (tx - x)) or (230 - (tx - x)))
      l.text:SetText(spec.text or "")
      l.text:SetTextColor(gameColor(spec.head and "NORMAL" or spec.color or "HIGHLIGHT"))
      for _, col in ipairs({ { l.a, spec.a, 130 }, { l.b, spec.b, 162 } }) do
        if col[2] then
          col[1]:ClearAllPoints()
          col[1]:SetPoint("TOPRIGHT", w.frame, "TOPLEFT", x + col[3], ly - 4)
          col[1]:SetText(col[2])
          col[1]:SetTextColor(gameColor(spec.head and "GRAY" or "HIGHLIGHT"))
        end
      end
      if l.button and spec.button then
        l.button.spec = spec.button
        l.button.text:SetText(spec.button.label)
        l.button:ClearAllPoints()
        l.button:SetPoint("TOPLEFT", w.frame, "TOPLEFT", x + 170, ly)
        if spec.button.enabled == false then l.button:Disable() else l.button:Enable() end
      end
    end
  end
end

-- What a master/detail tab makes besides the list: the left list and the detail pane.
function ui.makeMasterDetail(w, host)
  w.masterButtons = {}
  ui.makeDetail(w, host)
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

-- The Bank: its tabs on the left (Bags and Bank for a bank alt), its items in the middle under their
-- categories, as a list or as bag slots (Grid), and the picked item on the right: how many and where, when
-- it was recorded, what changed since the scan before, and Ask (a whisper to the bank alt for one).
local bankWindow = ui.md({ key = "Bank", nameWidth = 236, masterKey = "bankSource", pickKey = "bankPick" })
bankWindow.ICONS = { All = "Interface\\Icons\\INV_Box_01", Bags = "Interface\\Icons\\INV_Misc_Bag_08",
  Bank = "Interface\\Icons\\INV_Box_02", Tab = "Interface\\Icons\\INV_Misc_Bag_10" }
bankWindow.SLOT, bankWindow.PER_LINE = 37, 7

function bankWindow.build(w)
  ui.loadState(w)
  w.grid = ui.state().bankGrid and true or false
  local out = { rows = {}, filters = {}, footer = "", empty = "No bank yet. The bank alt types /ff bankalt.", masters = {} }
  local bank = bankData()
  w.bank, w.items_ = bank, {}
  if not bank then return out end
  local search = searchText(w)
  local known, byId, list, all = {}, {}, {}, 0
  for _, t in ipairs(bank.tabs) do
    local tab = str(type(t) == "table" and t.name)
    if type(t) == "table" and type(t.items) == "table" then
      known[tab] = true
      out.masters[#out.masters + 1] = { value = tab, label = tab, count = #t.items,
        icon = t.icon or bankWindow.ICONS[tab] or bankWindow.ICONS.Tab }
      all = all + #t.items
    end
  end
  table.insert(out.masters, 1, { value = nil, label = "All", count = all, icon = bankWindow.ICONS.All })
  if w.master and not known[w.master] then w.master = nil end
  -- one entry per item (All adds a tab's items to the others'), with where it is
  for _, t in ipairs(bank.tabs) do
    local tab = str(type(t) == "table" and t.name)
    if type(t) == "table" and type(t.items) == "table" and (w.master == nil or w.master == tab) then
      for _, it in ipairs(t.items) do
        local id = type(it) == "table" and tonumber(it.id)
        if id then
          local e = byId[id]
          if not e then
            local name = itemName(id) or str(it.name)
            e = { id = id, key = id, name = name ~= "" and name or ("Item " .. id), count = 0, where = {}, tie = id }
            byId[id] = e
            list[#list + 1] = e
          end
          local n = floor(num(it.count, 1))
          e.count = e.count + n
          e.where[#e.where + 1] = { tab = tab, count = n }
        end
      end
    end
  end
  local shown = {}
  for _, e in ipairs(list) do
    if search == "" or e.name:lower():find(search, 1, true) then shown[#shown + 1] = e end
  end
  local g = ui.group(shown, function(e) return ui.category(e.id, e.name) end)
  for _, cat in ipairs(g.cats) do
    local items = g.items[cat]
    out.rows[#out.rows + 1] = { header = true, cat = cat, count = #items, collapsed = w.collapsed[cat] and true or false }
    if not w.collapsed[cat] then
      if w.grid then
        -- bag slots, a line of them every two rows
        for i = 1, #items, bankWindow.PER_LINE do
          local slots = {}
          for j = i, math.min(#items, i + bankWindow.PER_LINE - 1) do slots[#slots + 1] = items[j] end
          out.rows[#out.rows + 1] = { slots = slots }
          out.rows[#out.rows + 1] = { filler = true }
        end
      else
        for _, e in ipairs(items) do out.rows[#out.rows + 1] = e end
      end
    end
  end
  w.items_ = shown
  if #shown == 0 then out.empty = search ~= "" and "Nothing matches." or "Nothing here." end
  out.footer = #shown .. (#shown == 1 and " item" or " items")
  return out
end

function bankWindow.decorate(w, row)
  ui.decorateRow(w, row)
  row.slots = {}
end

-- One bag slot in the grid: the game's item button, else an icon with a count and a quality border.
function bankWindow.slot(w, row, i)
  local b = row.slots[i]
  if b then return b end
  local size = bankWindow.SLOT
  b = newFrame("Button", nil, row, "ItemButtonTemplate")
  local stock = b and (b.icon or b.Icon) and true or false
  if not stock then
    if b then b:Hide() end
    b = newFrame("Button", nil, row)
    if not b then return nil end
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.IconBorder = b:CreateTexture(nil, "OVERLAY")
    b.IconBorder:SetAllPoints()
    b.IconBorder:SetTexture("Interface\\Common\\WhiteIconFrame")
    b.Count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.Count:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT", -3, 3)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    try(hl.SetBlendMode, hl, "ADD")
  end
  b.stock = stock
  b:SetSize(size, size)
  b:SetPoint("TOPLEFT", row, "TOPLEFT", 2 + (i - 1) * (size + 4), -1)
  try(b.RegisterForClicks, b, "LeftButtonUp")
  b:SetScript("OnEnter", function(self)
    if self.entry then
      local tt = recipeTooltip(self, self.entry.id, nil, self.entry.name)
      if tt then try(tt.Show, tt) end
    end
  end)
  b:SetScript("OnLeave", hideTooltip)
  b:SetScript("OnClick", function(self) if self.entry then pcall(w.click, w, self.entry) end end)
  try(b.EnableMouseWheel, b, true)
  b:SetScript("OnMouseWheel", function(_, delta) ui.scroll(w, w.offset - delta * 3) end)
  row.slots[i] = b
  return b
end

function bankWindow.fillSlot(w, b, e)
  b.entry = e
  local icon = itemIcon(e.id) or QUESTION_ICON
  if not (b.stock and try(SetItemButtonTexture, b, icon)) then (b.icon or b.Icon):SetTexture(icon) end
  if b.stock and type(SetItemButtonCount) == "function" then
    try(SetItemButtonCount, b, e.count)
  elseif b.Count then
    b.Count:SetText(e.count > 1 and tostring(e.count) or "")
  end
  local q = try(C_Item and C_Item.GetItemQualityByID, e.id)
  if b.stock and type(SetItemButtonQuality) == "function" then
    try(SetItemButtonQuality, b, q, e.id)
  elseif b.IconBorder then
    local c = type(q) == "number" and q >= 2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
    if type(c) == "table" then
      b.IconBorder:SetVertexColor(c.r, c.g, c.b)
      b.IconBorder:Show()
    else
      b.IconBorder:Hide()
    end
  end
  if w.pick == e.key then try(b.LockHighlight, b) else try(b.UnlockHighlight, b) end
  b:Show()
end

function bankWindow.fill(w, row, d)
  for _, b in ipairs(row.slots) do b:Hide() end
  if d.header then
    row.label:Show()
    row.icon:Show()
    ui.fillHeader(row, d)
    return
  end
  if d.slots then
    row.icon:Hide()
    row.label:Hide()
    row.right:SetText("")
    row.sel:Hide()
    for i, e in ipairs(d.slots) do
      local b = bankWindow.slot(w, row, i)
      if b then bankWindow.fillSlot(w, b, e) end
    end
    return
  end
  row.icon:Show()
  row.label:Show()
  row.icon:ClearAllPoints()
  row.icon:SetPoint("LEFT", row, "LEFT", 14, 0)
  row.icon:SetTexture(itemIcon(d.id) or QUESTION_ICON)
  row.label:SetText(d.name)
  row.label:SetTextColor(itemQualityColor(d.id))
  row.right:SetText(tostring(d.count))
  if w.pick == d.key then row.sel:Show() else row.sel:Hide() end
end

function bankWindow.enter(w, row, d)
  if d.header or d.slots then return end
  local tt = recipeTooltip(row, d.id, nil, d.name)
  if tt then try(tt.Show, tt) end
end

function bankWindow.click(w, d)
  if d.header then return ui.toggleHeader(w, d) end
  if d.slots then return end
  if shiftDown() then
    linkInChat(itemLink(d.id))
    return
  end
  ui.setPick(w, d.key)
end

function bankWindow.isEmpty()
  return bankData() == nil
end

-- Whom to ask for an item: the bank alt, or for a guild bank the guild master (else who recorded it).
function bankWindow.keeper(bank)
  if bank.source == "guild" then
    for i = 1, num(try(GetNumGuildMembers), 0) do
      local name, _, rankIndex = try(GetGuildRosterInfo, i)
      if rankIndex == 0 and type(name) == "string" then return stripRealm(name) end
    end
  end
  return str(bank.by)
end

-- The prefilled whisper to the keeper: "Hi! Could I have [Runecloth] x1?"
function bankWindow.askText(id, name)
  return "Hi! Could I have " .. (itemLink(id) or ("[" .. str(name) .. "]")) .. " x1?"
end

-- The picked item on the right.
function bankWindow.describe(w, e)
  local bank = w.bank
  if not (e and bank) then return nil end
  local lines = {}
  local all = {}
  for _, t in ipairs(bank.tabs) do
    for _, it in ipairs(type(t) == "table" and type(t.items) == "table" and t.items or {}) do
      if type(it) == "table" and tonumber(it.id) == e.id then all[#all + 1] = { tab = str(t.name), count = floor(num(it.count, 1)) } end
    end
  end
  local total = 0
  for _, p in ipairs(all) do
    total = total + p.count
    lines[#lines + 1] = { text = p.tab, a = tostring(p.count) }
  end
  if #all > 1 then lines[#lines + 1] = { text = "Total", a = tostring(total), color = "NORMAL" } end
  lines[#lines + 1] = { text = "Updated " .. ago(bank.updated), color = "GRAY" }
  lines[#lines + 1] = { text = "by " .. str(bank.by), color = "GRAY" }
  local prev = type(bank.prev) == "table" and type(bank.prev.counts) == "table" and bank.prev or nil
  if prev then
    local diff = total - num(prev.counts[e.id], 0)
    if diff ~= 0 then
      lines[#lines + 1] = { text = (diff > 0 and "+" or "") .. diff .. " since " .. ago(prev.updated), color = diff > 0 and "GREEN" or "GRAY" }
    end
  end
  local log = type(bank.log) == "table" and bank.log[e.id]
  for _, l in ipairs(type(log) == "table" and log or {}) do
    lines[#lines + 1] = { text = str(l.who) .. " " .. (l.kind == "withdraw" and "-" or "+") .. num(l.count, 1), color = "GRAY" }
  end
  local keeper = bankWindow.keeper(bank)
  lines[#lines + 1] = { text = keeper, color = "GRAY", button = { label = "Ask", enabled = keeper ~= "" and keeper ~= readName(),
    tip = "Whispers " .. keeper .. " for one.", onClick = function() chatLine("WHISPER", keeper, bankWindow.askText(e.id, e.name)) end } }
  return { item = e.id, icon = itemIcon(e.id), name = e.name, color = { itemQualityColor(e.id) }, link = itemLink(e.id),
    sub = ui.category(e.id, e.name), lines = lines }
end

function bankWindow.make(w, host)
  ui.makeMasterDetail(w, host)
  w.gold = host:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  w.gold:SetJustifyH("LEFT")
  w.view = ui.stockButton(host, 20)
  if w.view then
    w.view:SetWidth(56)
    w.view:SetPoint("TOPLEFT", host, "TOPLEFT", 350, -4)
    w.view:SetScript("OnClick", function()
      local st = ui.state()
      st.bankGrid = not st.bankGrid or nil
      w.offset = 0
      pcall(ui.render, w)
    end)
    ui.tip(w.view, "View", "A list, or bag slots.")
  end
end

function bankWindow.after(w, data)
  local n = ui.drawMaster(w, data.masters or {})
  w.gold:ClearAllPoints()
  w.gold:SetPoint("TOPLEFT", w.frame, "TOPLEFT", 12, -4 - n * 21 - 8)
  w.gold:SetText(w.bank and moneyText(w.bank.money) or "")
  if w.view then w.view.text:SetText(w.grid and "List" or "Grid") end
  local entry
  for _, e in ipairs(w.items_ or {}) do
    if e.key == w.pick then entry = e break end
  end
  for _, d in ipairs(entry and {} or data.rows) do
    entry = (d.slots and d.slots[1]) or ((not d.header and not d.filler) and d) or nil
    if entry then break end
  end
  local changed = (entry and entry.key) ~= w.pick
  w.pick = entry and entry.key or nil
  if changed then ui.draw(w) end
  ui.drawDetail(w, bankWindow.describe(w, entry), w.bank and "Pick an item." or "")
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
      e = { key = key, prof = prof, id = r.id, item = r.item, name = r.name, crafters = {}, seen = {} }
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

-- Crafting, in the same shape as the Bank: the professions on the left with their icons and recipe counts,
-- the recipes in the middle under their categories, each with its icon and how many can make it, and the
-- picked recipe on the right: what it takes, and everyone who can make it, online first, each with Whisper.
-- Search (recipes and crafters) and Online above the list.
local craftsWindow = ui.md({ key = "Crafts", nameWidth = 236, masterKey = "craftProf", pickKey = "craftPick" })

-- The professions' spells (their icons in the game) and icon paths to fall back on.
craftsWindow.PROFS = {
  Alchemy = { 2259, "Trade_Alchemy" }, Blacksmithing = { 2018, "Trade_BlackSmithing" },
  Enchanting = { 7411, "Trade_Engraving" }, Engineering = { 4036, "Trade_Engineering" },
  Leatherworking = { 2108, "INV_Misc_ArmorKit_17" }, Tailoring = { 3908, "Trade_Tailoring" },
  Cooking = { 2550, "INV_Misc_Food_15" }, ["First Aid"] = { 3273, "Spell_Holy_SealOfSacrifice" },
  Mining = { 2575, "Trade_Mining" }, Herbalism = { 2366, "Spell_Nature_NatureTouchGrow" },
  Skinning = { 8613, "INV_Misc_Pelt_Wolf_01" }, Fishing = { 7620, "Trade_Fishing" },
}
craftsWindow.ALL_ICON = "Interface\\Icons\\INV_Misc_Book_09"

function craftsWindow.profIcon(prof)
  local p = craftsWindow.PROFS[prof]
  if not p then return QUESTION_ICON end
  return try(C_Spell and C_Spell.GetSpellTexture, p[1]) or try(GetSpellTexture, p[1]) or ("Interface\\Icons\\" .. p[2])
end

function craftsWindow.category(e)
  if not e.cat then e.cat = ui.category(e.item, recipeName(e)) end
  return e.cat
end

-- Who can make a recipe, online first (then those with an alt online to whisper), then by skill.
function craftsWindow.who(e, online, groups)
  local who = {}
  for _, c in ipairs(e.crafters) do
    local via
    if not online[c.name] and not c.own and c.group then
      for _, other in ipairs(groups[c.group] or {}) do
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
  return who
end

-- What a recipe takes: as recorded with this account's recipes, else as the game describes it.
function craftsWindow.reagents(e)
  if e.reagents ~= nil then return e.reagents or nil end
  local found
  for _, rec in pairs(initDB().characters) do
    local list = type(rec) == "table" and type(rec.recipes) == "table" and rec.recipes[e.prof]
    for _, r in ipairs(type(list) == "table" and list or {}) do
      if type(r) == "table" and type(r.reagents) == "table" and ((e.id and r.id == e.id) or (e.item and r.item == e.item)) then
        found = r.reagents
        break
      end
    end
    if found then break end
  end
  if not found and e.id and C_TradeSkillUI then found = schematicReagents(try(C_TradeSkillUI.GetRecipeSchematic, e.id, false)) end
  e.reagents = found or false
  return found
end

function craftsWindow.build(w)
  if not ui.crafts then
    local list, profs, groups = craftsIndex()
    ui.crafts = { list = list, profs = profs, groups = groups }
  end
  ui.loadState(w)
  local idx = ui.crafts
  local known, counts = {}, { All = 0 }
  for _, p in ipairs(idx.profs) do known[p] = true end
  if w.master and not known[w.master] then w.master = nil end
  local out = { rows = {}, filters = {}, footer = "", empty = "No recipes yet. Open your professions once.", masters = {} }
  local online, search = onlineNames(), searchText(w)
  local shown, crafterNames = {}, {}
  for _, e in ipairs(idx.list) do
    counts[e.prof] = (counts[e.prof] or 0) + 1
    counts.All = counts.All + 1
    if w.master == nil or w.master == e.prof then
      local name = recipeName(e)
      local who = craftsWindow.who(e, online, idx.groups)
      local match = search == "" or name:lower():find(search, 1, true)
      if not match then
        for _, c in ipairs(who) do
          if c.name:lower():find(search, 1, true) then match = true break end
        end
      end
      local anyOn = who[1] and (who[1].online or who[1].via) and true or false
      if match and (not w.onlineOnly or anyOn) then
        shown[#shown + 1] = { e = e, key = e.key, name = name, who = who, on = anyOn, tie = e.prof }
        for _, c in ipairs(who) do crafterNames[c.name] = true end
      end
    end
  end
  out.masters[1] = { value = nil, label = "All", count = counts.All, icon = craftsWindow.ALL_ICON }
  for _, p in ipairs(idx.profs) do
    out.masters[#out.masters + 1] = { value = p, label = p, count = counts[p], icon = craftsWindow.profIcon(p) }
  end
  local g = ui.group(shown, function(d) return craftsWindow.category(d.e) end)
  for _, cat in ipairs(g.cats) do
    local list = g.items[cat]
    out.rows[#out.rows + 1] = { header = true, cat = cat, count = #list, collapsed = w.collapsed[cat] and true or false }
    if not w.collapsed[cat] then
      for _, d in ipairs(list) do out.rows[#out.rows + 1] = d end
    end
  end
  w.items_ = shown
  if #idx.list > 0 and #shown == 0 then out.empty = "Nothing matches." end
  local n = 0
  for _ in pairs(crafterNames) do n = n + 1 end
  out.footer = #shown .. (#shown == 1 and " recipe, " or " recipes, ") .. n .. (n == 1 and " crafter" or " crafters")
  return out
end

local function recipeLink(e)
  return (e.item and itemLink(e.item)) or (e.id and spellLink(e.id)) or nil
end

local function recipeIcon(e)
  return (e.item and itemIcon(e.item)) or (e.id and spellIcon(e.id)) or QUESTION_ICON
end

craftsWindow.decorate = ui.decorateRow

function craftsWindow.fill(w, row, d)
  if d.header then return ui.fillHeader(row, d) end
  local e = d.e
  row.icon:ClearAllPoints()
  row.icon:SetPoint("LEFT", row, "LEFT", 14, 0)
  row.icon:SetTexture(recipeIcon(e))
  row.label:SetText(d.name)
  if e.item then row.label:SetTextColor(itemQualityColor(e.item)) else row.label:SetTextColor(gameColor("HIGHLIGHT")) end
  row.right:SetText((d.on and ONLINE_ICON or "") .. gameColor(d.on and "HIGHLIGHT" or "GRAY", true) .. #d.who .. "|r")
  if w.pick == e.key then row.sel:Show() else row.sel:Hide() end
end

function craftsWindow.enter(w, row, d)
  if d.header then return end
  local tt = recipeTooltip(row, d.e.item, d.e.id, d.name)
  if tt then try(tt.Show, tt) end
end

-- A category opens or closes; a recipe shows on the right (shift-click links it).
function craftsWindow.click(w, d)
  if d.header then return ui.toggleHeader(w, d) end
  if shiftDown() then
    linkInChat(recipeLink(d.e))
    return
  end
  ui.setPick(w, d.e.key)
end

function craftsWindow.isEmpty()
  return next(initDB().shared.crafters) == nil
end

-- A crafter's level, from what guildmates shared or this account's own record.
function craftsWindow.level(name)
  local e = mainIndex()[name]
  if e and type(e.char) == "table" and num(e.char.level, 0) > 0 then return e.char.level end
  local rec = initDB().characters[name]
  return type(rec) == "table" and rec.level or nil
end

-- The picked recipe on the right: what it takes, then who can make it.
function craftsWindow.describe(w, e)
  if not e then return nil end
  local lines = {}
  local reagents = craftsWindow.reagents(e)
  if reagents then
    lines[#lines + 1] = { head = true, text = "Reagents" }
    for _, g in ipairs(reagents) do
      local n = (g.item and itemName(g.item)) or str(g.name)
      lines[#lines + 1] = { icon = (g.item and itemIcon(g.item)) or QUESTION_ICON,
        text = n .. (num(g.count, 1) > 1 and (gameColor("GRAY", true) .. " x" .. g.count .. "|r") or "") }
    end
  end
  lines[#lines + 1] = { head = true, text = "Crafters", a = "Lvl", b = "Skill" }
  for _, c in ipairs(craftsWindow.who(e, onlineNames(), ui.crafts and ui.crafts.groups or {})) do
    local color = c.online and classHex(c.class) or gameColor(c.via and "HIGHLIGHT" or "GRAY", true)
    local lvl = craftsWindow.level(c.name)
    lines[#lines + 1] = { text = ((c.online or c.via) and ONLINE_ICON or "") .. color .. c.name .. "|r",
      a = lvl and tostring(lvl) or "", b = tostring(c.skill), crafter = c,
      button = { label = "Whisper", enabled = (c.online or c.via) and c.name ~= readName() and true or false,
        tip = c.via and ("On " .. c.via .. ", online") or (not c.online and "Offline" or nil),
        onClick = function() whisper(c.via or c.name) end } }
  end
  return { item = e.item, spell = e.id, icon = recipeIcon(e), name = recipeName(e), link = recipeLink(e),
    color = e.item and { itemQualityColor(e.item) } or nil, sub = e.prof .. ", " .. craftsWindow.category(e), lines = lines }
end

function craftsWindow.make(w, host)
  ui.makeMasterDetail(w, host)
  w.onlineBox = ui.check(host, 350, -2, "Online", function(on)
    w.onlineOnly, w.offset = on, 0
    pcall(ui.render, w)
  end, "Only recipes someone online can make.")
end

-- After each redraw: the professions, and the picked recipe (remembered; else the first one shown).
function craftsWindow.after(w, data)
  ui.drawMaster(w, data.masters or {})
  if w.onlineBox then w.onlineBox:SetChecked(w.onlineOnly and true or false) end
  local entry
  for _, d in ipairs(w.items_ or {}) do
    if d.key == w.pick then entry = d.e break end
  end
  if not entry then
    for _, d in ipairs(data.rows) do
      if not d.header then entry = d.e break end
    end
  end
  local changed = (entry and entry.key) ~= w.pick
  w.pick = entry and entry.key or nil
  if changed then ui.draw(w) end
  ui.drawDetail(w, craftsWindow.describe(w, entry), "Pick a recipe.")
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
    if ui.visible(w.frame) then any = true end
  end
  if not any then return end
  ui.redrawQueued = true
  after(0.3, function()
    ui.redrawQueued = false
    for _, w in pairs(ui.windows) do pcall(ui.render, w) end
  end)
end

-- ---------------------------------------------------------- website tab --
-- Getting characters onto the website, three steps of one line each: Save (reloads, so the game writes
-- the file), the file's path to copy, and the site's address to copy. Under them a checklist of this
-- account's characters: a star on the main, a warning when a profession's recipes aren't recorded.

-- Gathering skills have no recipes to record; Mining's window is called Smelting.
local NO_RECIPES = { Herbalism = true, Skinning = true, Fishing = true }
local RECIPE_WINDOW = { Mining = "Smelting" }
ui.STAR = "|TInterface\\TargetingFrame\\UI-RaidTargetingIcon_1:14:14|t" -- the main
ui.WARN = "|TInterface\\DialogFrame\\UI-Dialog-Icon-AlertNew:14:14|t" -- something to do
local FILE_PATH = "World of Warcraft\\_forever_\\WTF\\Account\\<your account>\\SavedVariables\\FantasyForce.lua"

local siteView = { key = "Site", nameWidth = 300, noFilters = true, noSearch = true, filterTop = -132 }

-- "Open Tailoring once" when a profession's recipes aren't recorded yet, else nil.
function siteView.hint(p)
  if p.gather or (p.recipes and p.recipes > 0) then return nil end
  return "Open " .. (RECIPE_WINDOW[p.name] or p.name) .. " once"
end

function siteView.build(w)
  local db, guild = initDB(), myGuild()
  local out = { rows = {}, filters = {}, footer = "Log in once to add a character.", empty = "No characters yet." }
  local own = ownAccount()
  for name, rec in pairs(db.characters) do
    if type(rec) == "table" then
      local other = guild == "" or rec.guild ~= guild
      local r = { name = name, class = str(rec.class), level = num(rec.level, 0), updated = num(rec.updated, 0),
        other = other, main = not other and own ~= nil and own.main == name, profs = {}, missing = {} }
      for _, p in ipairs(type(rec.professions) == "table" and rec.professions or {}) do
        if type(p) == "table" and str(p.name) ~= "" then
          local list = type(rec.recipes) == "table" and rec.recipes[p.name]
          local prof = { name = p.name, skill = num(p.skill, 0), gather = NO_RECIPES[p.name] or false,
            recipes = type(list) == "table" and #list or nil }
          r.profs[#r.profs + 1] = prof
          local hint = siteView.hint(prof)
          if hint then r.missing[#r.missing + 1] = hint end
        end
      end
      out.rows[#out.rows + 1] = r
    end
  end
  table.sort(out.rows, function(a, b)
    if a.other ~= b.other then return not a.other end
    if a.level ~= b.level then return a.level > b.level end
    return a.name < b.name
  end)
  return out
end

function siteView.fill(w, row, r)
  local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[r.class]
  if type(coords) == "table" then
    row.icon:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
    try(row.icon.SetTexCoord, row.icon, coords[1], coords[2], coords[3], coords[4])
  else
    row.icon:SetTexture(nil)
  end
  row.label:SetText(r.other and (gameColor("GRAY", true) .. r.name .. "|r") or (classHex(r.class) .. r.name .. "|r"))
  row.right:SetText((#r.missing > 0 and (ui.WARN .. " ") or "") .. (r.main and (ui.STAR .. " ") or "")
    .. (r.other and gameColor("GRAY", true) or "") .. r.level .. (r.other and "|r" or ""))
end

function siteView.enter(w, row, r)
  local tt = GameTooltip
  if not tt then return end
  try(tt.SetOwner, tt, row, "ANCHOR_RIGHT")
  try(tt.SetText, tt, r.name)
  if r.main then try(tt.AddLine, tt, "Main", gameColor("NORMAL")) end
  if r.other then try(tt.AddLine, tt, "Another guild", gameColor("GRAY")) end
  try(tt.AddLine, tt, "Level " .. r.level .. ", last recorded " .. ago(r.updated), gameColor("HIGHLIGHT"))
  for _, p in ipairs(r.profs) do
    local hint = siteView.hint(p)
    if hint then
      try(tt.AddLine, tt, p.name .. " " .. p.skill .. ": " .. hint, gameColor("NORMAL"))
    elseif p.gather then
      try(tt.AddLine, tt, p.name .. " " .. p.skill, gameColor("GRAY"))
    else
      try(tt.AddLine, tt, p.name .. " " .. p.skill .. ": " .. p.recipes .. " recipes", gameColor("GREEN"))
    end
  end
  try(tt.Show, tt)
end

function siteView.click() end
function siteView.isEmpty() return false end

-- A one-line box holding text to copy: it selects itself and puts the text back if typed over.
function ui.copyBox(parent, x, y, width, tip)
  local e = newFrame("EditBox", nil, parent, "InputBoxTemplate") or newFrame("EditBox", nil, parent)
  if not e then return nil end
  e:SetSize(width, 20)
  e:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  e:SetAutoFocus(false)
  try(e.SetFontObject, e, GameFontHighlightSmall)
  e:SetScript("OnTextChanged", function(self, userInput)
    if userInput and self.value and self:GetText() ~= self.value then
      self:SetText(self.value)
      try(self.HighlightText, self)
    end
  end)
  e:SetScript("OnEditFocusGained", function(self) try(self.HighlightText, self) end)
  e:SetScript("OnMouseUp", function(self) try(self.HighlightText, self) end)
  e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  function e.setValue(v)
    e.value = v
    e:SetText(v)
    try(e.SetCursorPosition, e, 0)
  end
  ui.tip(e, "Copy", tip)
  return e
end

local function isOfficer()
  if try((C_GuildInfo and C_GuildInfo.CanEditOfficerNote) or CanEditOfficerNote) then return true end
  local _, _, rankIndex = try(GetGuildInfo, "player")
  return type(rankIndex) == "number" and rankIndex <= 1
end

function ui.makeSite(page, width, height)
  local s = {}
  ui.site = s
  local function line(x, y, w, font)
    local fs = page:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", page, "TOPLEFT", x, y)
    fs:SetWidth(w)
    fs:SetJustifyH("LEFT")
    return fs
  end
  line(14, -14, 16, "GameFontNormal"):SetText("1")
  s.save = ui.button(page, 34, -10, 90, "Save", function()
    if not try(ReloadUI) then try(C_UI and C_UI.Reload) end
  end, "Reloads your interface so the game writes the file. It only writes it on reload or logout.")
  line(14, -44, 16, "GameFontNormal"):SetText("2")
  s.path = ui.copyBox(page, 40, -40, width - 52,
    "The file to upload. Ctrl+C copies. Your account folder is the only one in WTF\\Account, or the one named after your account.")
  if s.path then s.path.setValue(FILE_PATH) end
  line(14, -74, 16, "GameFontNormal"):SetText("3")
  line(34, -76, 150):SetText("Drop it on My characters")
  s.address = ui.copyBox(page, 190, -70, width - 202, "The guild website. Ctrl+C copies.")
  if s.address then s.address.setValue(SITE_URL) end
  s.officer = line(34, -100, width - 60, "GameFontDisableSmall")
  local h = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  h:SetPoint("TOPLEFT", page, "TOPLEFT", 12, -116)
  h:SetText("Characters")
  ui.makeView(siteView, page, width, height)
end

function ui.refreshSite()
  local s = ui.site
  if not s then return end
  local db = initDB()
  if isOfficer() then
    local parts = { "guild list" }
    if isBankAlt() then parts[#parts + 1] = "bank" end
    parts[#parts + 1] = (type(db.raids) == "table" and #db.raids or 0) .. " raids"
    s.officer:SetText("Also uploads: " .. table.concat(parts, ", "))
  else
    s.officer:SetText("")
  end
end

-- ------------------------------------------------------------ guild view --
-- Guildmates running the addon, like the game's guild roster: columns to sort by (Name, Role, Class,
-- Level; again reverses, and the pick is remembered), each main with its alts under it. One row of
-- filters: Online, the classes, the roles, and Alts (off lists mains only). Right-click one of your own
-- characters to set its roles.

-- Tank, healer, damage: the group finder's role icons, else a spell icon each.
ui.ROLES = {
  tank = { name = "Tank", coords = { 0, 67 / 256, 67 / 256, 134 / 256 }, icon = "Interface\\Icons\\Ability_Defend" },
  healer = { name = "Healer", coords = { 67 / 256, 134 / 256, 0, 67 / 256 }, icon = "Interface\\Icons\\Spell_Holy_HolyBolt" },
  dps = { name = "Damage", coords = { 67 / 256, 134 / 256, 67 / 256, 134 / 256 }, icon = "Interface\\Icons\\INV_Sword_04" },
}
ui.ROLE_ORDER = { "tank", "healer", "dps" }
ui.ROLE_FILE = "Interface\\LFGFrame\\UI-LFG-ICON-ROLES"
ui.CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

function ui.roleTexture(tex, role)
  local r = ui.ROLES[role]
  if not r then return end
  if try(tex.SetTexture, tex, ui.ROLE_FILE) == false then -- not on this client
    tex:SetTexture(r.icon)
    try(tex.SetTexCoord, tex, 0.08, 0.92, 0.08, 0.92)
  else
    try(tex.SetTexCoord, tex, r.coords[1], r.coords[2], r.coords[3], r.coords[4])
  end
end

function ui.roleNames(roles)
  local names = {}
  for _, r in ipairs(roles or {}) do names[#names + 1] = ui.ROLES[r] and ui.ROLES[r].name or r end
  return table.concat(names, ", ")
end

function ui.className(class)
  local n = type(LOCALIZED_CLASS_NAMES_MALE) == "table" and LOCALIZED_CLASS_NAMES_MALE[class]
  if type(n) == "string" and n ~= "" then return n end
  class = str(class)
  return class:sub(1, 1) .. class:sub(2):lower()
end

function ui.classTexture(tex, class)
  local coords = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
  if type(coords) ~= "table" then
    tex:SetTexture(nil)
    return
  end
  tex:SetTexture("Interface\\TargetingFrame\\UI-Classes-Circles")
  try(tex.SetTexCoord, tex, coords[1], coords[2], coords[3], coords[4])
end

-- A small icon that turns on and off (filters, roles): on wears the game's checked-button glow; while
-- others in its row are on, one that's off is greyed.
function ui.toggleIcon(parent, size, setIcon, title, text, onClick)
  local b = newFrame("Button", nil, parent)
  if not b then return nil end
  b:SetSize(size, size)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  setIcon(b.icon)
  b.glow = b:CreateTexture(nil, "OVERLAY")
  b.glow:SetAllPoints()
  b.glow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
  try(b.glow.SetBlendMode, b.glow, "ADD")
  b.glow:Hide()
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
  try(hl.SetBlendMode, hl, "ADD")
  b:SetScript("OnClick", function(self) pcall(onClick, self) end)
  ui.tip(b, title, text)
  return b
end

function ui.setToggle(b, on, dim)
  if not b then return end
  b.on = on and true or false
  if b.on then b.glow:Show() else b.glow:Hide() end
  local grey = dim and not b.on
  try(b.icon.SetDesaturated, b.icon, grey)
  try(b.icon.SetAlpha, b.icon, grey and 0.45 or 1)
end

-- The game's roster column header (the Who list's), else a stock button.
function ui.columnHeader(parent, name, x, y, width, label, onClick)
  local b = newFrame("Button", name, parent, "WhoFrameColumnHeaderTemplate")
    or newFrame("Button", name .. "G", parent, "GuildFrameColumnHeaderTemplate")
  if b then
    b:SetText(label)
    b.text = b.Text or try(b.GetFontString, b)
    if not (type(WhoFrameColumn_SetWidth) == "function" and pcall(WhoFrameColumn_SetWidth, b, width)) then b:SetWidth(width) end
  else
    b = ui.stockButton(parent, 22)
    if not b then return nil end
    b.text:SetText(label)
    b:SetWidth(width)
  end
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  b:SetScript("OnClick", function() pcall(onClick) end)
  return b
end

local guildView = { key = "Guild", nameWidth = 300, noFilters = true, filterTop = -58, searchWidth = 150, rightClick = true,
  emptyArt = "Interface\\AddOns\\FantasyForce\\Media\\Logo" }
guildView.COLUMNS = { { "name", "Name" }, { "role", "Role" }, { "class", "Class" }, { "level", "Level" } }
guildView.ROLE_RANK = { tank = "1", healer = "2", dps = "3" }

function guildView.sort()
  local st = ui.state()
  if type(st.guildSort) ~= "table" then st.guildSort = { key = "name" } end
  return st.guildSort
end

function guildView.sortBy(key)
  local s = guildView.sort()
  if s.key == key then
    s.desc = not s.desc or nil
  else
    s.key, s.desc = key, nil
  end
end

function guildView.value(c, key)
  if key == "level" then return c.level end
  if key == "class" then return ui.className(c.class) end
  if key == "role" then
    local v = ""
    for _, r in ipairs(c.roles) do v = v .. (guildView.ROLE_RANK[r] or "4") end
    return v == "" and "9" or v
  end
  return c.name
end

function guildView.less(s)
  return function(a, b)
    local va, vb = guildView.value(a, s.key), guildView.value(b, s.key)
    if va ~= vb then
      if s.desc then return va > vb end
      return va < vb
    end
    return a.name < b.name
  end
end

function guildView.passes(w, c, search)
  if search ~= "" and not c.name:lower():find(search, 1, true) then return false end
  if w.onlineOnly and not c.online then return false end
  if not w.showAlts and not c.isMain then return false end
  if next(w.classes) and not w.classes[c.class] then return false end
  if next(w.roles) then
    for _, r in ipairs(c.roles) do
      if w.roles[r] then return true end
    end
    return false
  end
  return true
end

function guildView.build(w)
  local out = { rows = {}, filters = {}, footer = "", empty = "No guildmates with the addon yet." }
  local index, online, search, own = mainIndex(), onlineNames(), searchText(w), initDB().characters
  local groups, list = {}, {}
  for name, e in pairs(index) do
    local g = groups[e.main]
    if not g then
      g = { main = e.main, chars = {}, online = false }
      groups[e.main] = g
      list[#list + 1] = g
    end
    local c = type(e.char) == "table" and e.char or {}
    local on = online[name] and true or false
    local ch = { name = name, class = str(c.class), level = num(c.level, 0), profs = c.profs, online = on,
      roles = Sync and Sync.orderRoles(c.roles) or {}, isMain = name == e.main, main = e.main, group = g,
      own = type(own[name]) == "table" }
    g.chars[#g.chars + 1] = ch
    if ch.isMain then g.mainChar = ch end
    if on then g.online = true end
  end
  local s = guildView.sort()
  local less = guildView.less(s)
  for _, g in ipairs(list) do
    table.sort(g.chars, less)
    g.mainChar = g.mainChar or g.chars[1]
  end
  table.sort(list, function(a, b) return less(a.mainChar, b.mainChar) end)
  local playing, shown = 0, 0
  local filtered = search ~= "" or w.onlineOnly or not w.showAlts or next(w.classes) or next(w.roles)
  for _, g in ipairs(list) do
    if g.online then playing = playing + 1 end
    local mainShown = guildView.passes(w, g.mainChar, search)
    local any = false
    if mainShown then
      out.rows[#out.rows + 1] = g.mainChar
      any = true
    end
    for _, c in ipairs(g.chars) do
      if c ~= g.mainChar and guildView.passes(w, c, search) then
        c.under = mainShown -- indented under its main, else on its own with "alt of"
        out.rows[#out.rows + 1] = c
        any = true
      end
    end
    if any then shown = shown + 1 end
  end
  if #list > 0 and #out.rows == 0 then out.empty = "Nothing matches." end
  if filtered then
    out.footer = shown .. " of " .. #list
  else
    out.footer = #list .. (#list == 1 and " player, " or " players, ") .. playing .. " online"
  end
  return out
end

function guildView.decorate(w, row)
  local c = w.cols
  row.roleIcons = {}
  for i = 1, 3 do
    local t = row:CreateTexture(nil, "ARTWORK")
    t:SetSize(14, 14)
    t:SetPoint("LEFT", row, "LEFT", c.name + 6 + (i - 1) * 16, 0)
    row.roleIcons[i] = t
  end
  row.class = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.class:SetPoint("LEFT", row, "LEFT", c.name + c.role + 8, 0)
  row.class:SetWidth(c.class - 12)
  row.class:SetJustifyH("LEFT")
  row.right:ClearAllPoints()
  row.right:SetPoint("LEFT", row, "LEFT", c.name + c.role + c.class + 8, 0)
  row.right:SetJustifyH("LEFT")
end

function guildView.fill(w, row, c)
  local indent = (not c.isMain and c.under) and 16 or 0
  row.icon:ClearAllPoints()
  row.icon:SetPoint("LEFT", row, "LEFT", 2 + indent, 0)
  ui.classTexture(row.icon, c.class)
  local name = c.online and (classHex(c.class) .. c.name .. "|r") or (gameColor("GRAY", true) .. c.name .. "|r")
  local note = (not c.isMain and not c.under) and (gameColor("GRAY", true) .. "  alt of " .. c.main .. "|r") or ""
  row.label:SetText((c.online and ONLINE_ICON or "") .. name .. note)
  for i, t in ipairs(row.roleIcons) do
    local r = c.roles[i]
    if r then
      ui.roleTexture(t, r)
      t:Show()
    else
      t:Hide()
    end
  end
  row.class:SetText(ui.className(c.class))
  row.class:SetTextColor(gameColor(c.online and "HIGHLIGHT" or "GRAY"))
  row.right:SetText(c.level > 0 and tostring(c.level) or "")
  row.right:SetTextColor(gameColor(c.online and "HIGHLIGHT" or "GRAY"))
end

function guildView.enter(w, row, c)
  local tt = GameTooltip
  if not tt then return end
  try(tt.SetOwner, tt, row, "ANCHOR_RIGHT")
  try(tt.SetText, tt, c.name)
  try(tt.AddLine, tt, c.isMain and "Main" or ("Alt of " .. c.main), gameColor("NORMAL"))
  if c.level > 0 then try(tt.AddLine, tt, "Level " .. c.level .. " " .. ui.className(c.class), gameColor("HIGHLIGHT")) end
  if #c.roles > 0 then try(tt.AddLine, tt, ui.roleNames(c.roles), gameColor("HIGHLIGHT")) end
  local profs = profText(c)
  if profs ~= "" then
    local r, g, b = gameColor("HIGHLIGHT")
    try(tt.AddLine, tt, profs, r, g, b, true)
  end
  if c.online and c.name ~= readName() then try(tt.AddLine, tt, "Click to whisper", gameColor("GRAY")) end
  if c.own then try(tt.AddLine, tt, "Right-click for roles", gameColor("GRAY")) end
  try(tt.Show, tt)
end

-- Click whispers the character (or whichever of the player's characters is online); right-click on one
-- of your own sets its roles.
function guildView.click(w, c, _, button)
  if button == "RightButton" then
    if c.own then guildView.openPopup(w, c) end
    return
  end
  if w.popup then w.popup:Hide() end
  local to = c.online and c.name or nil
  if not to then
    for _, o in ipairs(c.group.chars) do
      if o.online then to = o.name break end
    end
  end
  if to and to ~= readName() then whisper(to) end
end

function guildView.isEmpty()
  return next(initDB().shared.accounts) == nil
end

-- The roles popup: the character's name and its three role toggles, on a tooltip's backdrop.
function guildView.openPopup(w, c)
  local p = w.popup
  if not p then
    p = newFrame("Frame", nil, w.frame, "BackdropTemplate") or newFrame("Frame", nil, w.frame)
    if not p then return end
    p:SetSize(150, 54)
    try(p.SetFrameStrata, p, "DIALOG")
    try(p.EnableMouse, p, true)
    if p.SetBackdrop then
      pcall(p.SetBackdrop, p, { bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 } })
      local bg = TOOLTIP_DEFAULT_BACKGROUND_COLOR
      if type(bg) == "table" and bg.r then try(p.SetBackdropColor, p, bg.r, bg.g, bg.b, 1) else try(p.SetBackdropColor, p, 0, 0, 0, 1) end
    end
    p.title = p:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    p.title:SetPoint("TOPLEFT", p, "TOPLEFT", 10, -9)
    p.title:SetWidth(116)
    p.title:SetJustifyH("LEFT")
    local close = newFrame("Button", nil, p, "UIPanelCloseButton")
    if close then
      close:SetSize(20, 20)
      close:SetPoint("TOPRIGHT", p, "TOPRIGHT", 0, 0)
    end
    p.buttons = {}
    for i, role in ipairs(ui.ROLE_ORDER) do
      local b = ui.toggleIcon(p, 22, function(t) ui.roleTexture(t, role) end, ui.ROLES[role].name, nil,
        function(self) ui.setRole(p.name, role, not self.on) end)
      if b then
        b:SetPoint("TOPLEFT", p, "TOPLEFT", 10 + (i - 1) * 28, -24)
        p.buttons[role] = b
      end
    end
    w.popup = p
  end
  p.name = c.name
  p:ClearAllPoints()
  p:SetPoint("TOPLEFT", w.frame, "TOPLEFT", 6 + w.cols.name - 4, w.filterTop - 10)
  for i, row in ipairs(w.rows) do
    if row.data == c then p:SetPoint("TOPLEFT", w.frame, "TOPLEFT", 6 + w.cols.name - 4, w.filterTop + 2 - i * ROW_H) end
  end
  guildView.drawPopup(w)
  p:Show()
end

function guildView.drawPopup(w)
  local p = w.popup
  local rec = initDB().characters[p.name]
  local set = {}
  for _, r in ipairs(Sync and Sync.rolesFor(rec) or {}) do set[r] = true end
  p.title:SetText(p.name)
  for role, b in pairs(p.buttons) do ui.setToggle(b, set[role], false) end
end

-- Sets or clears one of this account's characters' roles, then shares it.
function ui.setRole(name, role, on)
  local rec = initDB().characters[name]
  if type(rec) ~= "table" or not Sync or not ui.ROLES[role] then return end
  local set = {}
  for _, r in ipairs(Sync.rolesFor(rec)) do set[r] = true end
  set[role] = on and true or nil
  local list = {}
  for _, r in ipairs(Sync.ROLES) do
    if set[r] then list[#list + 1] = r end
  end
  rec.roles, rec.rolesSet = list, true
  alts.index = nil
  if onDataChanged then onDataChanged() end
  ui.changed()
  local w = ui.windows.Guild
  if w then
    pcall(ui.render, w)
    if w.popup and ui.visible(w.popup) then guildView.drawPopup(w) end
  end
end

function guildView.make(w, host)
  w.classes, w.roles, w.showAlts = {}, {}, true
  local function changed()
    w.offset = 0
    pcall(ui.render, w)
  end
  w.onlineBox = ui.check(host, 170, -2, "Online", function(on)
    w.onlineOnly = on
    changed()
  end, "Only who's online now.")
  w.classButtons, w.roleButtons = {}, {}
  for i, class in ipairs(ui.CLASS_ORDER) do
    local b = ui.toggleIcon(host, 20, function(t) ui.classTexture(t, class) end, ui.className(class), nil, function()
      w.classes[class] = not w.classes[class] or nil
      changed()
    end)
    if b then
      b:SetPoint("TOPLEFT", host, "TOPLEFT", 246 + (i - 1) * 22, -4)
      w.classButtons[class] = b
    end
  end
  for i, role in ipairs(ui.ROLE_ORDER) do
    local b = ui.toggleIcon(host, 20, function(t) ui.roleTexture(t, role) end, ui.ROLES[role].name, nil, function()
      w.roles[role] = not w.roles[role] or nil
      changed()
    end)
    if b then
      b:SetPoint("TOPLEFT", host, "TOPLEFT", 458 + (i - 1) * 22, -4)
      w.roleButtons[role] = b
    end
  end
  w.altsBox = ui.check(host, 536, -2, "Alts", function(on)
    w.showAlts = on
    changed()
  end, "Off lists mains only.")
  -- the columns: Name takes what the others leave
  local listW = w.width - 30
  w.cols = { role = 80, class = 150, level = 60 }
  w.cols.name = listW - w.cols.role - w.cols.class - w.cols.level
  w.nameWidth = w.cols.name - 30
  w.headers = {}
  local x = 6
  for _, col in ipairs(guildView.COLUMNS) do
    local key = col[1]
    w.headers[key] = ui.columnHeader(host, "FantasyForceGuildCol" .. col[2], x, -32, w.cols[key], col[2], function()
      guildView.sortBy(key)
      changed()
    end)
    x = x + w.cols[key]
  end
  host:HookScript("OnShow", function() if w.popup then w.popup:Hide() end end)
end

function guildView.after(w)
  local s = guildView.sort()
  for key, b in pairs(w.headers) do
    if b.text then b.text:SetTextColor(gameColor(key == s.key and "NORMAL" or "HIGHLIGHT")) end
  end
  for class, b in pairs(w.classButtons) do ui.setToggle(b, w.classes[class], next(w.classes) ~= nil) end
  for role, b in pairs(w.roleButtons) do ui.setToggle(b, w.roles[role], next(w.roles) ~= nil) end
  if w.onlineBox then w.onlineBox:SetChecked(w.onlineOnly and true or false) end
  if w.altsBox then w.altsBox:SetChecked(w.showAlts and true or false) end
end

-- --------------------------------------------------------------- commands --

-- Every slash command, one plain line each. The window's commands list, /ff help and /accent help
-- all read this list, so they never drift apart.
local COMMANDS = {
  { "/ff", "Open or close this window" },
  { "/ff bank", "Guild bank" },
  { "/ff crafts", "Who can make what" },
  { "/ff guild", "Guildmates and their alts" },
  { "/ff site", "Put your characters on the website" },
  { "/ff options", "Options" },
  { "/ff main", "Make this character your main" },
  { "/ff tags off | on", "Mains in guild chat" },
  { "/ff bankalt", "This character is the bank alt (or not)" },
  { "/ff loot rare | epic", "Raid loot to record" },
  { "/ff minimap off | on", "Minimap button" },
  { "/ff status", "Summary in chat" },
  { "/ff help", "This list in chat" },
  { "/ff reset", "Clear everything recorded" },
  { "/accent", "Accent on or off" },
  { "/accent troll | orc | tauren | undead | skyborne | auto | off", "Pick an accent" },
  { "/accent light | thick", "How strong" },
  { "/accent chat <type> on | off", "Which chats it changes" },
  { "/accent status", "Your accent, in chat" },
  { "/accent debug", "What's in, what the game blocked" },
  { "/accent help", "Accent commands in chat" },
  { "/troll", "Troll on or off" },
  { "/troll <message>", "Say one thing in troll" },
}
ui.COMMANDS = COMMANDS

-- The commands starting with any of the prefixes, as lines.
function ui.commandLines(...)
  local prefixes, out = { ... }, {}
  for _, c in ipairs(COMMANDS) do
    for _, p in ipairs(prefixes) do
      if c[1] == p or c[1]:sub(1, #p + 1) == p .. " " then
        out[#out + 1] = gameColor("NORMAL", true) .. c[1] .. "|r  " .. c[2]
        break
      end
    end
  end
  return out
end

function ui.printHelp(...)
  for _, line in ipairs(ui.commandLines(...)) do print_(line) end
end

-- ---------------------------------------------------------------- setters --
-- A command and its control call the same function, and both leave the window showing the new
-- state. Each returns the line the command prints; controls print nothing.

local cmd = {}
local panel = { pages = {}, tabs = {}, W = 760, H = 520,
  views = { Bank = bankWindow, Crafts = craftsWindow, Guild = guildView },
  ICON = "Interface\\AddOns\\FantasyForce\\Media\\Icon",
  TABS = { { key = "Bank", label = "Bank" }, { key = "Crafts", label = "Crafting" }, { key = "Guild", label = "Guild" },
    { key = "Site", label = "Website" }, { key = "Options", label = "Options" } } }

-- Something a control shows changed (by a command, a control or the game): show it.
function ui.changed()
  if panel.frame and ui.visible(panel.frame) then pcall(panel.refresh) end
end

function cmd.bankAlt(on)
  local db = initDB()
  if type(db.bankAlts) ~= "table" then db.bankAlts = {} end
  local me = readName()
  if on == nil then on = not db.bankAlts[me] end
  if on then
    db.bankAlts[me] = true
    recordAltBank(false)
  else
    db.bankAlts[me] = nil
  end
  ui.changed()
  if on then return me .. " is now the guild's bank alt: its bags and bank are recorded." end
  return me .. " is no longer the guild's bank alt."
end

function cmd.loot(rare)
  local db = initDB()
  db.lootQuality = rare and 3 or 4
  ui.changed()
  return "raid loot recorded from " .. (rare and "rare (blue)" or "epic (purple)") .. " up."
end

function cmd.main()
  local db, guild = initDB(), myGuild()
  if guild == "" then return "mains are kept per guild: join one first." end
  if type(db.mains) ~= "table" then db.mains = {} end
  db.mains[guild] = readName()
  recordCharacter()
  onDataChanged()
  ui.changed()
  return readName() .. " is now your main in " .. guild .. "."
end

function cmd.tags(on)
  local db = initDB()
  if on then db.tags = nil else db.tags = false end
  ui.changed()
  if on then return "guild chat shows a speaker's main in front of their alts." end
  return "guild chat no longer shows mains in front of alts."
end

function cmd.minimap(show)
  local db = initDB()
  if type(db.minimap) ~= "table" then db.minimap = {} end
  db.minimap.hide = not show or nil
  ui.placeMinimap()
  ui.changed()
  return show and "the minimap button is back." or "the minimap button is hidden: /ff minimap on brings it back."
end

-- ----------------------------------------------------------------- window --
-- /ff: one window, tabs along the bottom (Bank, Crafting, Guild, Website, Options). The guild's round
-- icon sits on its top-left corner like a portrait. The header has the character's name and two small
-- icons: the accent switch and the commands list. Short words on every face; the why is in tooltips.

local function accentApi() return type(ns) == "table" and ns.AccentChat or nil end

-- A tooltip on any frame: a title and a line (either may be a function, read when shown).
function ui.tip(f, title, text)
  if not f or not title then return end
  local function enter(self)
    local tt = GameTooltip
    if not tt then return end
    try(tt.SetOwner, tt, self, "ANCHOR_RIGHT")
    try(tt.SetText, tt, type(title) == "function" and title() or title)
    local t = type(text) == "function" and text() or text
    if t then
      local r, g, b = gameColor("HIGHLIGHT")
      try(tt.AddLine, tt, t, r, g, b, true)
    end
    try(tt.Show, tt)
  end
  if f.HookScript then
    f:HookScript("OnEnter", enter)
    f:HookScript("OnLeave", hideTooltip)
  else
    f:SetScript("OnEnter", enter)
    f:SetScript("OnLeave", hideTooltip)
  end
end

-- A small plain button styled by colour: only where the game's button templates are missing.
function ui.choiceButton(parent, height)
  local b = newFrame("Button", nil, parent)
  if not b then return nil end
  b:SetHeight(height or 18)
  b.bg = b:CreateTexture(nil, "BACKGROUND")
  b.bg:SetAllPoints()
  b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  b.text:SetPoint("CENTER")
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  setColor(hl, 1, 1, 1, 0.12)
  return b
end

-- The game's red button (UIPanelButtonTemplate) with its label in b.text; the plain one without it.
function ui.stockButton(parent, height)
  local b = newFrame("Button", nil, parent, "UIPanelButtonTemplate")
  if b then
    b:SetHeight(height or 22)
    b:SetText(" ")
    b.text = b.Text or try(b.GetFontString, b)
    if b.text and b.text.SetText then
      b.stock = true
      return b
    end
    b:Hide()
  end
  b = ui.choiceButton(parent, height)
  if b then ui.styleChoice(b, false) end
  return b
end

-- Picked or not: a stock button keeps its highlight lit; the plain one changes colour. Never a size change.
function ui.styleChoice(b, picked)
  b.picked = picked and true or false
  if b.stock then
    if picked then try(b.LockHighlight, b) else try(b.UnlockHighlight, b) end
  elseif picked then
    b.text:SetTextColor(gameColor("NORMAL"))
    setColor(b.bg, 0.35, 0.27, 0.05, 0.9)
  else
    b.text:SetTextColor(gameColor("HIGHLIGHT"))
    setColor(b.bg, 0.12, 0.12, 0.12, 0.8)
  end
end

-- A row of choices { value, label, tooltip? } as the game's radio buttons (plain buttons without the
-- template); row.set(value) shows which is picked.
function ui.choiceRow(parent, x, y, options, onPick)
  local row, cx = { buttons = {} }, x
  for i, o in ipairs(options) do
    local b, bw = newFrame("CheckButton", nil, parent, "UIRadioButtonTemplate"), nil
    if b then
      b.radio = true
      b:SetSize(16, 16)
      b:SetPoint("TOPLEFT", parent, "TOPLEFT", cx, y - 2)
      b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      b.text:SetPoint("LEFT", b, "RIGHT", 2, 0)
      b.text:SetText(o[2])
      local lw = num(try(b.text.GetStringWidth, b.text), 40)
      try(b.SetHitRectInsets, b, 0, -(lw + 2), 0, 0)
      bw = 18 + lw + 10
    else
      b = ui.choiceButton(parent, 20)
      if b then
        b.text:SetText(o[2])
        bw = num(try(b.text.GetStringWidth, b.text), 40) + 18
        b:SetWidth(bw)
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", cx, y)
        bw = bw + 4
      end
    end
    if b then
      b.value = o[1]
      b:SetScript("OnClick", function(self)
        row.set(self.value)
        pcall(onPick, self.value)
      end)
      ui.tip(b, o[3] and o[2], o[3])
      cx = cx + bw
      row.buttons[i] = b
    end
  end
  function row.set(value)
    for _, b in ipairs(row.buttons) do
      if b.radio then
        b.picked = b.value == value
        b:SetChecked(b.picked)
      else
        ui.styleChoice(b, b.value == value)
      end
    end
  end
  function row.show(on)
    for _, b in ipairs(row.buttons) do
      if on then b:Show() else b:Hide() end
    end
  end
  return row
end

function ui.check(parent, x, y, label, onClick, tip)
  local cb = newFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  if not cb then
    cb = newFrame("CheckButton", nil, parent)
    if not cb then return nil end
    try(cb.SetNormalTexture, cb, "Interface\\Buttons\\UI-CheckBox-Up")
    try(cb.SetPushedTexture, cb, "Interface\\Buttons\\UI-CheckBox-Down")
    try(cb.SetHighlightTexture, cb, "Interface\\Buttons\\UI-CheckBox-Highlight", "ADD")
    try(cb.SetCheckedTexture, cb, "Interface\\Buttons\\UI-CheckBox-Check")
  end
  cb:SetSize(24, 24)
  cb:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  cb.label = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  cb.label:SetPoint("LEFT", cb, "RIGHT", 2, 1)
  cb.label:SetText(label)
  try(cb.SetHitRectInsets, cb, 0, -(num(try(cb.label.GetStringWidth, cb.label), 40) + 2), 0, 0)
  cb:SetScript("OnClick", function(self) pcall(onClick, self:GetChecked() and true or false) end)
  ui.tip(cb, tip and label, tip)
  return cb
end

function ui.button(parent, x, y, width, label, onClick, tip)
  local b = newFrame("Button", nil, parent, "UIPanelButtonTemplate")
  if b then
    b:SetText(label)
  else
    b = ui.choiceButton(parent, 22)
    if not b then return nil end
    b.text:SetText(label)
    ui.styleChoice(b, false)
  end
  b:SetSize(width, 22)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  b:SetScript("OnClick", function() pcall(onClick) end)
  ui.tip(b, tip and label, tip)
  return b
end

-- A small icon button with a tooltip.
function ui.iconButton(parent, texture, size, title, text, onClick)
  local b = newFrame("Button", nil, parent)
  if not b then return nil end
  b:SetSize(size, size)
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b.icon:SetTexture(texture)
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetTexture(texture)
  try(hl.SetBlendMode, hl, "ADD")
  b:SetScript("OnClick", function(self) pcall(onClick, self) end)
  ui.tip(b, title, text)
  return b
end

-- A small "More" button folding rarely used controls; its highlight stays lit while it's open.
function ui.more(parent, x, y, onToggle)
  local b = ui.stockButton(parent, 20)
  if not b then return nil end
  b.text:SetText("More")
  b:SetWidth(num(try(b.text.GetStringWidth, b.text), 30) + 24)
  b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
  b.open = false
  ui.styleChoice(b, false)
  b:SetScript("OnClick", function(self)
    self.open = not self.open
    ui.styleChoice(self, self.open)
    pcall(onToggle, self.open)
  end)
  return b
end

function panel.headerText()
  local me = readName()
  if myGuild() == "" then return me end
  local e = mainIndex()[me]
  if e and e.main ~= me then return me .. "  " .. gameColor("GRAY", true) .. "(alt of " .. e.main .. ")|r" end
  return me .. " " .. ui.STAR
end

local CHAT_LABELS = { { "SAY", "Say" }, { "YELL", "Yell" }, { "GUILD", "Guild" }, { "OFFICER", "Officer" },
  { "PARTY", "Party" }, { "RAID", "Raid" }, { "WHISPER", "Whisper" } }

function panel.makeOptions(page)
  local o = {}
  panel.options = o
  local function heading(y, text)
    local h = page:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h:SetPoint("TOPLEFT", page, "TOPLEFT", 12, y)
    h:SetText(text)
  end
  local function line(x, y, width, font)
    local fs = page:CreateFontString(nil, "OVERLAY", font or "GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", page, "TOPLEFT", x, y)
    fs:SetWidth(width)
    fs:SetJustifyH("LEFT")
    return fs
  end

  heading(-8, "Character")
  o.main = line(16, -32, 200)
  o.setMain = ui.button(page, 220, -27, 90, "Set main", function() cmd.main() end,
    "Make this character your main in this guild.")
  o.bankAlt = ui.check(page, 12, -54, "Bank alt", function(on) cmd.bankAlt(on) end,
    "Share this character's bags and bank as the guild bank.")
  o.minimap = ui.check(page, 120, -54, "Minimap button", function(on) cmd.minimap(on) end,
    "A round button on the minimap that opens this window.")
  o.moreCharacter = ui.more(page, 270, -57, function(open) panel.refreshOptions() end)
  o.rolesLabel = line(330, -32, 40)
  o.rolesLabel:SetText("Roles")
  o.roles = {}
  for i, role in ipairs(ui.ROLE_ORDER) do
    o.roles[role] = ui.toggleIcon(page, 22, function(t) ui.roleTexture(t, role) end, ui.ROLES[role].name,
      "Guildmates see your roles.", function(self) ui.setRole(readName(), role, not self.on) end)
    if o.roles[role] then o.roles[role]:SetPoint("TOPLEFT", page, "TOPLEFT", 372 + (i - 1) * 28, -27) end
  end
  o.lootLabel = line(16, -86, 70)
  o.lootLabel:SetText("Raid loot")
  o.loot = ui.choiceRow(page, 90, -82, { { "rare", "Rare+", "Record rare (blue) raid loot and better." },
    { "epic", "Epic", "Record epic (purple) raid loot and better." } }, function(v) cmd.loot(v == "rare") end)

  heading(-120, "Chat")
  o.tags = ui.check(page, 12, -142, "Mains in chat", function(on) cmd.tags(on) end,
    "Show a guildmate's main in front of what they say on an alt.")

  heading(-180, "Accent")
  o.accent = ui.choiceRow(page, 16, -202, { { "off", "Off" }, { "auto", "Auto", "Your race's accent." }, { "troll", "Troll" },
    { "orc", "Orc" }, { "tauren", "Tauren" }, { "undead", "Undead" }, { "skyborne", "Skyborne" } },
    function(v) local A = accentApi() if A then A.setAccent(v) end end)
  o.strength = ui.choiceRow(page, 16, -226, { { "light", "Light", "A few words." },
    { "thick", "Thick", "More words, and now and then a closing line." } },
    function(v) local A = accentApi() if A then A.setStrength(v) end end)
  o.moreAccent = ui.more(page, 140, -227, function(open) panel.refreshOptions() end)
  o.preview = line(16, -254, 700, "GameFontDisableSmall")
  o.chats = {}
  for i, c in ipairs(CHAT_LABELS) do
    o.chats[c[1]] = ui.check(page, 12 + (i - 1) * 78, -276, c[2], function(on)
      local A = accentApi()
      if A then A.setChatType(c[1], on) end
    end)
  end

  o.status = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  o.status:SetPoint("BOTTOMLEFT", page, "BOTTOMLEFT", 12, 8)
  o.status:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT", -12, 8)
  o.status:SetJustifyH("LEFT")
end

local function setChecked(cb, on)
  if cb then try(cb.SetChecked, cb, on and true or false) end
end

local function showIf(f, on)
  if not f then return end
  if on then f:Show() else f:Hide() end
end

function panel.refreshOptions()
  local o = panel.options
  if not o then return end
  local db, me, guild = initDB(), readName(), myGuild()
  local e = mainIndex()[me]
  if guild == "" then
    o.main:SetText("Main: no guild")
  elseif e and e.main ~= me then
    o.main:SetText("Main: " .. e.main)
  else
    o.main:SetText("Main: " .. me .. " " .. ui.STAR)
  end
  setChecked(o.bankAlt, isBankAlt())
  local roles = {}
  for _, r in ipairs(Sync and Sync.rolesFor(db.characters[me]) or {}) do roles[r] = true end
  for role, b in pairs(o.roles) do ui.setToggle(b, roles[role], false) end
  setChecked(o.minimap, not (type(db.minimap) == "table" and db.minimap.hide))
  local moreChar = o.moreCharacter and o.moreCharacter.open
  showIf(o.lootLabel, moreChar)
  o.loot.show(moreChar)
  o.loot.set(num(db.lootQuality, 4) == 3 and "rare" or "epic")
  setChecked(o.tags, db.tags ~= false)
  local A = accentApi()
  local status = ""
  if A then
    local c = A.charDB()
    o.accent.set(c.accent)
    o.strength.set(c.strength)
    o.preview:SetText("\"" .. A.preview() .. "\"")
    local moreAccent = o.moreAccent and o.moreAccent.open
    for kind, cb in pairs(o.chats) do
      setChecked(cb, c.chatTypes[kind])
      showIf(cb, moreAccent)
    end
    if c.accent ~= "off" then
      status = A.canConvert() and "Talk in it: the bubble by your chat tab, or /troll <message>. The game's chat box stays as typed."
        or "Chat can't be changed here: use /troll <message>."
    end
  end
  o.status:SetText(status)
end

function panel.refresh()
  if panel.header then panel.header:SetText(panel.headerText()) end
  local A = accentApi()
  if panel.accentButton then
    local on = A and A.charDB().accent ~= "off"
    try(panel.accentButton.icon.SetDesaturated, panel.accentButton.icon, not on)
    try(panel.accentButton.icon.SetAlpha, panel.accentButton.icon, on and 1 or 0.45)
    panel.accentOn = on and true or false
  end
  if panel.current == "Options" then panel.refreshOptions() end
  if panel.current == "Site" then ui.refreshSite() end
end

function panel.makeTabs(f)
  local prev
  for i, t in ipairs(panel.TABS) do
    local name = "FantasyForceWindowTab" .. i
    local tab, style = newFrame("Button", name, f, "PanelTabButtonTemplate"), "panel"
    if not tab then tab, style = newFrame("Button", name, f, "CharacterFrameTabButtonTemplate"), "character" end
    if not tab then tab, style = ui.choiceButton(f, 22), "plain" end
    if tab then
      tab.ffStyle = style
      try(tab.SetID, tab, i)
      if style == "plain" then
        tab.text:SetText(t.label)
        tab:SetWidth(num(try(tab.text.GetStringWidth, tab.text), 60) + 24)
      else
        tab:SetText(t.label)
        try(PanelTemplates_TabResize, tab, 0)
      end
      tab:ClearAllPoints()
      if prev then
        tab:SetPoint("LEFT", prev, "RIGHT", style == "character" and -15 or 4, 0)
      else
        tab:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 12, style == "plain" and -2 or 2)
      end
      tab:SetScript("OnClick", function() pcall(panel.select, t.key) end)
      panel.tabs[i] = tab
      prev = tab
    end
  end
  f.Tabs, f.numTabs = panel.tabs, #panel.tabs
  try(PanelTemplates_SetNumTabs, f, #panel.tabs)
end

function panel.styleTabs()
  local idx = 1
  for i, t in ipairs(panel.TABS) do
    if t.key == panel.current then idx = i end
  end
  local first = panel.tabs[1]
  if first and first.ffStyle ~= "plain" and type(PanelTemplates_SetTab) == "function"
    and pcall(PanelTemplates_SetTab, panel.frame, idx) then
    return
  end
  for i, tab in ipairs(panel.tabs) do
    if tab.bg then ui.styleChoice(tab, i == idx) end
  end
end

function panel.make()
  local f = ui.makeChrome("Window", "Fantasy Force", panel.W, panel.H)
  if not f then return false end
  panel.frame = f
  -- the guild's round icon over the top-left corner, like a portrait
  local badge = newFrame("Frame", nil, f)
  if badge then
    badge:SetSize(60, 60)
    badge:SetPoint("TOPLEFT", f, "TOPLEFT", -14, 14)
    try(badge.SetFrameLevel, badge, num(try(f.GetFrameLevel, f), 1) + 10)
    local icon = badge:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(panel.ICON)
    panel.badge = icon
  end
  panel.header = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  panel.header:SetPoint("TOPLEFT", f, "TOPLEFT", 54, -32)
  panel.accentButton = ui.iconButton(f, "Interface\\ChatFrame\\UI-ChatIcon-Chat-Up", 22, "Accent",
    function()
      local A = accentApi()
      if not A then return nil end
      return A.shortStatus() .. (panel.accentOn and "\nClick: off" or "\nClick: on")
    end,
    function(self)
      local A = accentApi()
      if A then A.toggle() end
      local onEnter = self:GetScript("OnEnter")
      if onEnter then onEnter(self) end
    end)
  if panel.accentButton then panel.accentButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", -40, -28) end
  panel.helpButton = ui.iconButton(f, "Interface\\FriendsFrame\\InformationIcon", 18, "Commands", nil, function()
    if panel.commands then
      if panel.commands:IsShown() then panel.commands:Hide() else panel.commands:Show() end
    end
  end)
  if panel.helpButton then panel.helpButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -30) end

  for _, t in ipairs(panel.TABS) do
    local page = newFrame("Frame", nil, f)
    page:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -54)
    page:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
    page:Hide()
    panel.pages[t.key] = page
    local view = panel.views[t.key]
    if view then
      ui.makeView(view, page, panel.W - 12, panel.H - 60)
    elseif t.key == "Site" then
      ui.makeSite(page, panel.W - 12, panel.H - 60)
    else
      panel.makeOptions(page)
    end
  end

  -- the commands list behind the help icon, from the same list as /ff help; it takes the page's place
  -- (the page hides while it shows), so it needs no background of its own
  local c = newFrame("Frame", nil, f)
  if c then
    c:SetPoint("TOPLEFT", f, "TOPLEFT", 6, -54)
    c:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 6)
    try(c.SetFrameLevel, c, num(try(f.GetFrameLevel, f), 1) + 20)
    try(c.EnableMouse, c, true)
    c:SetScript("OnShow", function()
      local page = panel.pages[panel.current]
      if page then page:Hide() end
    end)
    c:SetScript("OnHide", function()
      local page = panel.pages[panel.current]
      if page and ui.visible(f) then page:Show() end
    end)
    local h = c:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    h:SetPoint("TOPLEFT", c, "TOPLEFT", 12, -8)
    h:SetText("Commands")
    c.list = c:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    c.list:SetPoint("TOPLEFT", c, "TOPLEFT", 12, -30)
    c.list:SetWidth(panel.W - 40)
    c.list:SetJustifyH("LEFT")
    try(c.list.SetSpacing, c.list, 3)
    c.list:SetText(table.concat(ui.commandLines("/ff", "/accent", "/troll"), "\n"))
    c:Hide()
    panel.commands = c
  end

  panel.makeTabs(f)
  f:SetScript("OnShow", function() pcall(panel.refresh) end)
  return true
end

function panel.select(key)
  if not panel.pages[key] then key = "Options" end
  panel.current = key
  local db = initDB()
  if type(db.windows) ~= "table" then db.windows = {} end
  db.windows.tab = key
  for k, page in pairs(panel.pages) do
    if k == key then page:Show() else page:Hide() end
  end
  if panel.commands then panel.commands:Hide() end
  panel.styleTabs()
  local view = panel.views[key]
  if view then
    pcall(ui.render, view)
    requestRoster()
    maybeRequest(view.isEmpty())
  elseif key == "Site" then
    pcall(ui.render, siteView)
  end
  pcall(panel.refresh)
end

-- Opens the window on a tab (nil: the one last used, Options the first time).
function panel.open(key)
  if not panel.frame then
    local ok, made = pcall(panel.make)
    if not ok or not made then
      panel.frame = nil
      print_("couldn't open the window in this game version.")
      return false
    end
  end
  panel.frame:Show()
  local db = initDB()
  panel.select(key or (type(db.windows) == "table" and db.windows.tab) or "Options")
  return true
end

-- Closes the window when it's showing that tab (or any tab, for nil), else opens it there.
function panel.toggle(key)
  if panel.frame and ui.visible(panel.frame) and (key == nil or key == panel.current) then
    panel.frame:Hide()
    return true
  end
  return panel.open(key)
end

-- -------------------------------------------------------------- minimap --
-- A plain round button on the minimap's edge: click toggles the window, drag moves it around.

function ui.placeMinimap()
  local b = ui.minimapButton
  if not b then return end
  local db = initDB()
  if type(db.minimap) ~= "table" then db.minimap = {} end
  if db.minimap.hide then
    b:Hide()
    return
  end
  local a = math.rad(num(db.minimap.angle, 200))
  local r = num(try(Minimap.GetWidth, Minimap), 140) / 2 + 10
  b:ClearAllPoints()
  b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
  b:Show()
end

local function dragMinimap()
  local mx, my = try(Minimap.GetCenter, Minimap)
  local cx, cy = try(GetCursorPosition)
  if not (mx and my and cx and cy) then return end
  local s = num(try(Minimap.GetEffectiveScale, Minimap), 1)
  local atan2 = math.atan2 or math.atan
  local db = initDB()
  if type(db.minimap) ~= "table" then db.minimap = {} end
  db.minimap.angle = math.deg(atan2(cy / s - my, cx / s - mx))
  ui.placeMinimap()
end

function ui.makeMinimap()
  if ui.minimapButton or not Minimap then
    ui.placeMinimap()
    return
  end
  local b = newFrame("Button", "FantasyForceMinimapButton", Minimap)
  if not b then return end
  b:SetSize(31, 31)
  b:SetFrameStrata("MEDIUM")
  try(b.SetFrameLevel, b, 8)
  local bg = b:CreateTexture(nil, "BACKGROUND")
  bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  bg:SetSize(20, 20)
  bg:SetPoint("TOPLEFT", b, "TOPLEFT", 7, -5)
  local icon = b:CreateTexture(nil, "ARTWORK")
  icon:SetTexture(panel.ICON)
  icon:SetSize(20, 20)
  icon:SetPoint("TOPLEFT", b, "TOPLEFT", 6, -5)
  b.icon = icon
  local border = b:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT", b, "TOPLEFT", 0, 0)
  try(b.SetHighlightTexture, b, "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
  try(b.RegisterForClicks, b, "LeftButtonUp")
  b:RegisterForDrag("LeftButton")
  b:SetScript("OnClick", function() pcall(panel.toggle, nil) end)
  b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", function() pcall(dragMinimap) end) end)
  b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  ui.tip(b, "Fantasy Force", "Click: open. Drag: move.")
  ui.minimapButton = b
  ui.placeMinimap()
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
        pcall(ui.makeMinimap)
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

-- The text summary /ff used to print, now /ff status.
function ui.printSummary()
  local db = initDB()
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
    .. " /ff opens the window; /ff help lists every command."
    .. " Saved on logout or /reload. /ff reset clears.")
end

-- /ff words that open the window on a tab.
local TAB_COMMANDS = { bank = "Bank", crafts = "Crafts", craft = "Crafts", crafting = "Crafts", guild = "Guild",
  site = "Site", website = "Site", options = "Options" }

-- Registered the standard way: our own SLASH_ name and one new key in the game's SlashCmdList. Never assign
-- the SlashCmdList global itself (SlashCmdList = SlashCmdList or {}): that taints every read of it by the
-- game's chat box, and the game then blocks its own slash commands and blames this addon.
SLASH_FANTASYFORCE1 = "/ff"
if type(SlashCmdList) == "table" then SlashCmdList["FANTASYFORCE"] = function(msg)
  local ok = pcall(function()
    msg = str(msg):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "" then
      if not panel.toggle(nil) then ui.printSummary() end
    elseif TAB_COMMANDS[msg] then
      panel.toggle(TAB_COMMANDS[msg])
    elseif msg == "status" then
      ui.printSummary()
    elseif msg == "help" then
      ui.printHelp("/ff", "/accent", "/troll")
    elseif msg == "reset" then
      FantasyForceDB = nil
      initDB()
      lastGuildRecord = 0
      lastRosterRequest = 0
      recordCharacter()
      if refreshWindows then refreshWindows() end
      ui.changed()
      print_("data cleared (this character re-recorded).")
    elseif msg == "bankalt" then
      print_(cmd.bankAlt())
    elseif msg == "loot rare" or msg == "loot epic" then
      print_(cmd.loot(msg == "loot rare"))
    elseif msg == "main" then
      print_(cmd.main())
    elseif msg == "tags on" or msg == "tags off" then
      print_(cmd.tags(msg == "tags on"))
    elseif msg == "minimap on" or msg == "minimap off" then
      print_(cmd.minimap(msg == "minimap on"))
    else
      print_("there's no /ff " .. msg .. ": /ff help lists the commands.")
    end
  end)
  if not ok then print_("something went wrong.") end
end end

-- For AccentChat.lua (loaded after this file) and the tests.
if type(ns) == "table" then
  ns.try, ns.str, ns.print, ns.after = try, str, print_, after
  ns.printHelp, ns.onSettingChanged = ui.printHelp, ui.changed
  ns.ff = { ui = ui, panel = panel, cmd = cmd,
    views = { Bank = bankWindow, Crafts = craftsWindow, Guild = guildView, Site = siteView } }
end
