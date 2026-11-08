-- FantasyForce: records this account's characters and the guild roster into
-- FantasyForceDB (SavedVariables) for the Fantasy Force guild website.
-- No UI, no network. Slash commands: /ff, /ff reset.
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

-- ----------------------------------------------------------------- events --

local frame = CreateFrame and CreateFrame("Frame") or nil
if frame then
  local events = {
    "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "SKILL_LINES_CHANGED",
    "PLAYER_TALENT_UPDATE", "ACTIVE_TALENT_GROUP_CHANGED", "CHARACTER_POINTS_CHANGED",
    "PLAYER_GUILD_UPDATE", "GUILD_ROSTER_UPDATE", "PLAYER_LOGOUT",
  }
  for _, ev in ipairs(events) do
    -- An event unknown to this client must not break loading.
    pcall(frame.RegisterEvent, frame, ev)
  end

  frame:SetScript("OnEvent", function(_, event)
    local ok = pcall(function()
      if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
        loggedIn = true
        recordCharacter()
        requestRoster()
      elseif event == "GUILD_ROSTER_UPDATE" then
        if loggedIn then recordGuild() end
      elseif event == "PLAYER_GUILD_UPDATE" then
        recordCharacter()
        requestRoster()
      elseif event == "PLAYER_LOGOUT" then
        recordCharacter()
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
    print_(chars .. " characters, " .. members .. " guild members, last update " .. last
      .. ". Saved on logout or /reload. /ff reset clears.")
  end)
  if not ok then print_("something went wrong.") end
end
