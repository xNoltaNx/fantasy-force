-- Kill on sight on pretend clients (run by kos.test.ts). Two guildmates, Azujin and Grukka, then a third who logs
-- in late. Every addon message one client sends reaches the others, as the guild channel does.

local FakeGame = assert(load(FAKEGAME_SRC, "@fakegame.lua", "t"))()
local SOURCES = {}
for i, name in ipairs(ADDON_FILES) do SOURCES[i] = { name = name, src = ADDON_SOURCES[i] } end
bit = { band = function(a, b) return a & b end } -- the game's bit library

local now = 1793000000
local timers = {}
local function after(sec, fn) timers[#timers + 1] = { at = now + sec, fn = fn } end
local function run(sec)
  local stop = now + sec
  while true do
    local pick
    for i, t in ipairs(timers) do
      if t.at <= stop and (not pick or t.at < timers[pick].at) then pick = i end
    end
    if not pick then break end
    local t = table.remove(timers, pick)
    if t.at > now then now = t.at end
    t.fn()
  end
  now = stop
end

local function check(cond, msg)
  if not cond then error(msg, 2) end
end

local ROSTER = {
  { name = "Azujin Rimetusk", class = "SHAMAN", level = 33, online = true, rank = "Member", rankIndex = 3 },
  { name = "Grukka Bonesaw", class = "WARRIOR", level = 40, online = true, rank = "Member", rankIndex = 3 },
  { name = "Mira Dawnfeather", class = "PRIEST", level = 50, online = true, rank = "Member", rankIndex = 3 },
}

local clients = {}
local function mk(name, class, guid)
  local c
  c = FakeGame.newClient({ name = name, class = class, sources = SOURCES, db = {}, charDB = {},
    time = function() return now end, now = function() return now end, after = after,
    roster = function() return ROSTER end,
    sendAddon = function(prefix, msg, chan)
      for _, o in ipairs(clients) do
        if o ~= c then o.fire("CHAT_MSG_ADDON", prefix, msg, chan, name) end
      end
      return 0
    end })
  local env = c.env
  env.UnitGUID = function(u) if u == "player" then return guid end return nil end
  -- the game's target frame, its portrait where the classic frame keeps it
  env.TargetFrame = env.CreateFrame("Frame", "TargetFrame", env.UIParent)
  env.TargetFrame.portrait = env.TargetFrame:CreateTexture(nil, "ARTWORK")
  clients[#clients + 1] = c
  return c
end

-- Puts a player in a client's "target" unit (nil: no target).
local function setTarget(c, t)
  local env = c.env
  c.base = c.base or { UnitName = env.UnitName, UnitClass = env.UnitClass, UnitRace = env.UnitRace,
    UnitLevel = env.UnitLevel, GetGuildInfo = env.GetGuildInfo, UnitGUID = env.UnitGUID }
  local base = c.base
  local function is(u) return t ~= nil and u == "target" end
  env.UnitExists = function(u) return u == "player" or is(u) end
  env.UnitIsPlayer = function(u) return u == "player" or is(u) end
  env.UnitIsUnit = function(a, b) return a == b end
  env.UnitCanAttack = function(_, u) return is(u) end
  env.UnitName = function(u) if is(u) then return t.name end return base.UnitName(u) end
  env.UnitClass = function(u) if is(u) then return t.class, t.class end return base.UnitClass(u) end
  env.UnitRace = function(u) if is(u) then return t.race, t.race end return base.UnitRace(u) end
  env.UnitLevel = function(u) if is(u) then return t.level end return base.UnitLevel(u) end
  env.GetGuildInfo = function(u) if is(u) then return t.guild end return base.GetGuildInfo(u) end
  env.UnitGUID = function(u) if is(u) then return t.guid end return base.UnitGUID(u) end
end

local function said(c, text)
  for _, m in ipairs(c.chat) do
    if tostring(m):find(text, 1, true) then return true end
  end
  return false
end

local function shown(f) return f and f._shown and true or false end

local A = mk("Azujin Rimetusk", "SHAMAN", "Player-1-A")
local B = mk("Grukka Bonesaw", "WARRIOR", "Player-1-B")
for _, c in ipairs(clients) do
  c.fire("PLAYER_LOGIN")
  c.fire("GUILD_ROSTER_UPDATE")
end
run(30)
local S = A.ns.Sync
local kosA, kosB = A.ns.ff.kos, B.ns.ff.kos

-- ------------------------------------------------------------ the format --
do
  local k = { name = "Itz Shifty", state = "kos", by = "Azujin Rimetusk", added = now, class = "DRUID", race = "Night Elf",
    level = 32, guild = "DYNASTY", guid = "Player-1-S", reason = string.rep("ganker; ~|x ", 30), updated = now + 5 }
  local body = S.encodeKos(k)
  local msgs = S.chunk("K", k.name, k.updated, body)
  check(#msgs == 1 and #msgs[1] <= 255, "a mark is one message")
  local d = S.decodeKos(k.name, k.updated, body)
  check(d.state == "kos" and d.class == "DRUID" and d.race == "Night Elf" and d.level == 32 and d.guild == "DYNASTY"
    and d.guid == "Player-1-S" and d.by == "Azujin Rimetusk" and d.added == now, "a mark comes back whole")
  check(#d.reason > 0 and #d.reason <= S.NOTE_MAX and not d.reason:find("|", 1, true), "the reason is cut and cleaned")
  local marks = {}
  check(S.storeKos(marks, d, now, "x"), "a new mark is kept")
  local older = S.decodeKos(k.name, k.updated - 1, S.encodeKos({ name = k.name, state = "cleared", added = now }))
  check(not S.storeKos(marks, older, now, "x"), "an older copy loses")
  local typed = S.decodeKos("itz shifty", k.updated + 1, S.encodeKos({ name = "itz shifty", state = "kos", added = now }))
  check(S.storeKos(marks, typed, now, "x") and marks["itz shifty"].class == "DRUID", "a newer copy keeps the details it lacks")
  local idx = S.kosIndex({ ["bob a"] = { name = "Bob A", state = "kos" }, ["bob b"] = { name = "Bob B", state = "kos" },
    ["zed q"] = { name = "Zed Q", state = "kos", class = "MAGE" } })
  check(S.findKos(idx, "Bob") == nil, "a first name two marks share matches neither")
  check(S.findKos(idx, "Zed", "MAGE").name == "Zed Q", "a first name alone matches its one mark")
  check(S.findKos(idx, "Zed", "ROGUE") == nil, "but not one of another class")
  check(S.decodeRequest("0~~~").kos == nil, "an addon from before KOS asks for no marks")
  check(S.decodeRequest(S.encodeRequest(0, {}, {}, {}, { ["itz shifty"] = 7 })).kos["itz shifty"] == 7, "R carries mark stamps")
end

-- ------------------------------------------------ marking the target --
local SHIFTY = { name = "Itz Shifty", class = "DRUID", race = "Night Elf", level = 32, guild = "DYNASTY", guid = "Player-1-S" }
setTarget(A, SHIFTY)
A.fire("PLAYER_TARGET_CHANGED")
check(not shown(kosA.frames.target), "no badge before he's marked")
A.slash("kos - ganks lowbies at the crossroads")
local k = A.db().kos["itz shifty"]
check(k and k.state == "kos" and k.reason == "ganks lowbies at the crossroads" and k.class == "DRUID" and k.level == 32
  and k.guild == "DYNASTY" and k.by == "Azujin Rimetusk" and k.guid == "Player-1-S", "/ff kos marks the target with a reason")
check(shown(kosA.frames.target), "the badge is on the target frame")
check(kosA.frames.target.icon._texture == "Interface\\AddOns\\FantasyForce\\Media\\Kos", "with the KOS icon")
check(said(A, "is now kill on sight"), "the marker is told")

run(10)
local kb = B.db().kos["itz shifty"]
check(kb and kb.state == "kos" and kb.reason == "ganks lowbies at the crossroads" and kb.guild == "DYNASTY" and kb.level == 32
  and kb.from == "Azujin Rimetusk", "the mark reaches the guildmate")
check(said(B, "Azujin Rimetusk marked"), "who gets a line about it")

-- -------------------------------------------- the guildmate meets him --
setTarget(B, SHIFTY)
B.fire("PLAYER_TARGET_CHANGED")
check(shown(kosB.frames.target), "the guildmate's target frame wears the badge")
check(said(B, "Kill on sight:"), "and chat says he's here")
local sounds = #B.sounds
B.fire("PLAYER_TARGET_CHANGED")
check(#B.sounds == sounds, "once per player every 5 minutes")
rawset(B.tooltip, "GetUnit", function() return "Itz Shifty", "target" end)
B.ttPost(B.tooltip)
check(FakeGame.serialize(B.tooltip._lines or {}):find("Kill on sight", 1, true), "the tooltip says so")

-- ------------------------------------------------ attacked by someone --
A.env.CombatLogGetCurrentEventInfo = function()
  return 0, "SWING_DAMAGE", false, "Player-1-R", "Sneaky", 0x548, 0, "Player-1-A", "Azujin Rimetusk", 0x511
end
A.env.GetPlayerInfoByGUID = function(g)
  if g == "Player-1-R" then return "Rogue", "ROGUE", "Human", "Human", 2, "Sneaky Stabsworth", "" end
end
A.fire("COMBAT_LOG_EVENT_UNFILTERED")
local toast = A.env.FantasyForceKosToast
check(shown(toast), "being attacked shows the notice")
check(toast.title._text:find("Attacked by", 1, true) and toast.title._text:find("Sneaky Stabsworth", 1, true),
  "naming the attacker by the fuller name")
check(said(A, "/ff kos last"), "and chat says how to mark them")
FakeGame.click(A, toast.mark)
local ks = A.db().kos["sneaky stabsworth"]
check(ks and ks.state == "kos" and ks.class == "ROGUE" and ks.race == "Human" and ks.guid == "Player-1-R", "Mark KOS marks them")
local lines = #A.chat
A.fire("COMBAT_LOG_EVENT_UNFILTERED")
check(not said(A, "Attacked by Sneaky") or #A.chat == lines + 1, "a marked attacker is no new offer")

-- a friendly hit, or one from an NPC, is no attack
A.env.CombatLogGetCurrentEventInfo = function()
  return 0, "SPELL_DAMAGE", false, "Creature-1-W", "Wolf", 0xa48, 0, "Player-1-A", "Azujin Rimetusk", 0x511
end
local before = #kosA.attackers
A.fire("COMBAT_LOG_EVENT_UNFILTERED")
check(#kosA.attackers == before, "an NPC is no attacker")

-- a duel challenge: hits don't count while it may be on, and it's forgotten even if the game never says it ended
A.env.CombatLogGetCurrentEventInfo = function()
  return 0, "SPELL_DAMAGE", false, "Player-1-D", "Duelo", 0x548, 0, "Player-1-A", "Azujin Rimetusk", 0x511
end
A.env.GetPlayerInfoByGUID = function(g)
  if g == "Player-1-D" then return "Mage", "MAGE", "Orc", "Orc", 2, "Duelo Fireborn", "" end
end
A.fire("DUEL_REQUESTED", "Duelo Fireborn")
A.fire("COMBAT_LOG_EVENT_UNFILTERED")
check(kosA.last.name ~= "Duelo Fireborn", "a duel's hits aren't attacks")
run(200) -- declined: no DUEL_FINISHED
A.fire("COMBAT_LOG_EVENT_UNFILTERED")
check(kosA.last.name == "Duelo Fireborn" and toast.title._text:find("Duelo Fireborn", 1, true),
  "a duel challenge the game never closed is forgotten")
A.fire("DUEL_REQUESTED", "Duelo Fireborn")
A.fire("DUEL_FINISHED")
kosA.offered = {}
A.fire("COMBAT_LOG_EVENT_UNFILTERED")
check(toast.title._text:find("Duelo Fireborn", 1, true) and shown(toast), "a finished duel is forgotten at once")

-- ---------------------------------------- a guildmate can't be marked --
A.slash("kos grukka bonesaw")
check(A.db().kos["grukka bonesaw"] == nil and said(A, "is in Fantasy Force"), "guildmates can't be marked")

-- ------------------------------------- a name typed, met by first name --
A.slash("kos bob loblaw - camps the flight master")
check(A.db().kos["bob loblaw"].name == "Bob Loblaw" and A.db().kos["bob loblaw"].class == nil, "a typed name is capitalised")
setTarget(A, { name = "Bob", class = "MAGE", race = "Gnome", level = 28, guid = "Player-1-L" })
A.fire("PLAYER_TARGET_CHANGED")
check(shown(kosA.frames.target), "the game's first name alone finds the typed mark")
run(2)
check(A.db().kos["bob loblaw"].class == "MAGE" and A.db().kos["bob loblaw"].guid == "Player-1-L", "and learns his class")

-- ------------------------------------------------------------ the tab --
setTarget(A, nil)
A.fire("PLAYER_TARGET_CHANGED")
A.slash("kos")
local view = A.ns.ff.views.Kos
check(A.ns.ff.panel.current == "Kos", "/ff kos without a target opens the KOS tab")
local names = {}
for _, d in ipairs(view.items) do names[#names + 1] = d.header or (d.mark and d.mark.name) or (d.attacker and d.attacker.name) end
check(table.concat(names, ",") == "Attacked you,Duelo Fireborn,Kill on sight,Bob Loblaw,Sneaky Stabsworth,Itz Shifty"
  or table.concat(names, ",") == "Attacked you,Duelo Fireborn,Kill on sight,Sneaky Stabsworth,Bob Loblaw,Itz Shifty", "it lists the marks: " .. table.concat(names, ","))

-- ---------------------------------------------------------- clearing --
B.slash("kos clear itz shifty")
check(B.db().kos["itz shifty"].state == "cleared" and not shown(kosB.frames.target), "clearing takes the badge off")
run(10)
check(A.db().kos["itz shifty"].state == "cleared", "the clear reaches the marker")

-- ------------------------------------------------- someone logs in late --
local C = mk("Mira Dawnfeather", "PRIEST", "Player-1-C")
C.fire("PLAYER_LOGIN")
run(120)
local kc = C.db().kos
check(kc["sneaky stabsworth"] and kc["sneaky stabsworth"].state == "kos", "a late login is sent the marks")
check(kc["itz shifty"] and kc["itz shifty"].state == "cleared", "and the clears")
check(not said(C, "marked Sneaky"), "old marks passed on at login don't announce themselves")
