-- FantasyForce Accent: rewrites what you type in a Horde race's accent, for fun.
-- Plain Lua 5.1 with no game API calls, so it can be tested outside the game. AccentChat.lua hooks it
-- into chat and mail. Accent.convert(text, accent, strength) is the whole job:
--   accent   "troll", "orc", "tauren", "undead", "skyborne" (or "off")
--   strength "light" (a few words) or "thick" (more words, and now and then a closing line)
-- Words are swapped whole and keep their casing (the -> da, The -> Da, THE -> DA). Links, colour
-- codes, slash commands, {skull}-style icons, @names, [brackets], URLs and numbers are never touched.
--
-- The lists below are meant to be edited. Keep them fun and readable: game flavour, never slurs or
-- real-world caricature. An empty replacement drops the word ("please" for a blunt orc).

local _, ns = ...
local A = {}
if type(ns) == "table" then ns.Accent = A end

local type, pairs, ipairs, tostring = type, pairs, ipairs, tostring
local floor = math.floor
local concat, sort = table.concat, table.sort
local strfind, strsub, strlower, strupper, strbyte = string.find, string.sub, string.lower, string.upper, string.byte

A.ACCENTS = { "troll", "orc", "tauren", "undead", "skyborne" }

-- --------------------------------------------------------------- the lists --

-- Single words. thick uses light's words too.
A.WORDS = {
  troll = {
    light = {
      you = "ya", your = "ya", ["you're"] = "ya be", ["i'm"] = "I be", the = "da", this = "dis", that = "dat",
      them = "dem", these = "dese", those = "dose", they = "dey", there = "dere", man = "mon",
    },
    thick = {
      hello = "hey mon", hi = "hey mon", hey = "hey mon", yes = "ya mon", yeah = "ya mon", ok = "ya mon",
      okay = "ya mon", friend = "mon", with = "wit", think = "tink", thing = "ting", things = "tings",
      nothing = "nuttin'", something = "someting", ["and"] = "an'", going = "goin'", very = "real",
    },
  },
  orc = {
    light = {
      hello = "Throm-Ka", hi = "Throm-Ka", hey = "Throm-Ka", yes = "Dabu", ok = "Zug zug", okay = "Zug zug",
      sure = "Zug zug", bye = "Lok'tar", goodbye = "Lok'tar", thanks = "Dabu", fth = "For the Horde!",
      victory = "Lok'tar ogar",
    },
    thick = {
      small = "puny", weak = "puny", tiny = "puny", little = "puny", kill = "crush", attack = "smash",
      good = "strong", great = "mighty", awesome = "mighty", friend = "blood-kin", friends = "blood-kin",
      please = "", just = "", maybe = "", fight = "battle", raid = "war party", boss = "warlord",
    },
  },
  tauren = {
    light = {
      hello = "greetings", hi = "greetings", hey = "greetings", bye = "walk with the Earth Mother",
      goodbye = "walk with the Earth Mother", thanks = "my thanks", yes = "indeed", yeah = "indeed",
      ok = "very well", okay = "very well", ["don't"] = "do not", ["can't"] = "cannot", ["won't"] = "will not",
      ["i'm"] = "I am", ["you're"] = "you are", ["it's"] = "it is", ["isn't"] = "is not", ["we're"] = "we are",
      ["they're"] = "they are", gonna = "going to", wanna = "want to", tonight = "this night", ready = "prepared",
    },
    thick = {
      hello = "An'she shine upon you", hi = "An'she shine upon you", hey = "An'she shine upon you",
      wow = "by the Earth Mother", omg = "Earth Mother", fast = "swift", big = "mighty", soon = "in time",
      quickly = "in good time", friend = "kindred", friends = "kindred", lol = "*chuckles*",
    },
  },
  undead = {
    light = {
      hello = "greetings", hi = "greetings", hey = "greetings", people = "living folk", alive = "still breathing",
      life = "unlife", great = "acceptable", awesome = "tolerable", amazing = "mildly interesting",
      love = "tolerate", happy = "less miserable", fun = "diverting", lol = "heh", haha = "heh",
    },
    thick = {
      body = "flesh", queen = "Dark Lady", sylvanas = "the Dark Lady", friend = "fellow corpse",
      friends = "fellow corpses", home = "the Undercity", tired = "dead tired", hungry = "peckish",
      tonight = "tonight under a cold moon", boss = "next victim",
    },
  },
  -- Skyborne is new in Forever: a light, airy placeholder until the race's own voice is known.
  skyborne = {
    light = {
      hello = "fair winds", hi = "fair winds", hey = "fair winds", bye = "ride the wind", goodbye = "ride the wind",
      yes = "aye", great = "sky-high", awesome = "sky-high", cool = "breezy", friend = "wingmate",
      friends = "wingmates",
    },
    thick = {
      fast = "swift", quick = "swift", home = "the high nest", go = "soar", run = "glide", ground = "the lowlands",
      tonight = "under the stars tonight", raid = "sky-raid",
    },
  },
}

-- Phrases of several words, matched before single words.
-- Write replacements in lower case unless they hold a name (Earth Mother, Lok'tar): the casing of
-- what was typed is put back (a capital at the start of a sentence, ALL CAPS).
A.PHRASES = {
  troll = {
    light = { ["i am"] = "I be", ["you are"] = "ya be", ["we are"] = "we be", ["they are"] = "dey be", ["it is"] = "it be" },
    thick = { ["thank you"] = "tanks, mon", ["see you later"] = "later, mon", ["hello friend"] = "hey mon",
      ["hi friend"] = "hey mon", ["hey friend"] = "hey mon" },
  },
  orc = {
    light = { ["for the horde"] = "For the Horde!", ["for da horde"] = "For the Horde!", ["thank you"] = "Dabu",
      ["good luck"] = "Lok'tar ogar!" },
    thick = { ["i think"] = "I know", ["i don't know"] = "who cares" },
  },
  tauren = {
    light = { ["good luck"] = "may the winds guide you", ["thank you"] = "my thanks", ["oh my god"] = "Earth Mother" },
    thick = { ["see you later"] = "until the winds meet again", ["see you"] = "until the winds meet again",
      ["good night"] = "rest beneath An'she's light" },
  },
  undead = {
    light = { ["see you later"] = "until the grave", ["good luck"] = "may your bones hold" },
    thick = { ["good night"] = "rest well, if you can", ["i'm hungry"] = "I could eat... anything" },
  },
  skyborne = {
    light = { ["good luck"] = "tailwinds to you", ["let's go"] = "wings up, let's go" },
    thick = { ["see you later"] = "see you above the clouds", ["see you"] = "see you above the clouds" },
  },
}

-- At thick, about one message in three ends with one of these.
A.TAGS = {
  troll = { "Ya mon!", "Stay away from da voodoo.", "Da spirits be watchin'.", "Ya feel me, mon?" },
  orc = { "Lok'tar!", "Zug zug.", "For the Horde!", "Blood and thunder!", "Strength and honor!" },
  tauren = { "May the winds guide you.", "Walk with the Earth Mother.", "The earth remembers.", "An'she watches over us." },
  undead = { "Victory for the Dark Lady.", "Death is only the beginning.", "Our time will come.", "Watch your back." },
  skyborne = { "Fair winds!", "Above the clouds!", "The sky remembers.", "Feathers up!" },
}

-- Words ending in "ing" a troll says as "in'" at thick (going -> goin'), except these.
A.ING_KEEP = { string = true, spring = true, during = true, ceiling = true, nothing = true, something = true }
A.ING = { troll = true }

-- Race (UnitRace's file name or its name, any case) to accent, for "auto". Others are off.
A.RACES = { troll = "troll", orc = "orc", tauren = "tauren", scourge = "undead", undead = "undead", forsaken = "undead",
  skyborne = "skyborne" }

-- -------------------------------------------------------------- the engine --

function A.valid(accent)
  return type(accent) == "string" and A.WORDS[accent] ~= nil
end

function A.forRace(raceFile, raceName)
  for i = 1, 2 do
    local s = i == 1 and raceFile or raceName
    if type(s) == "string" then
      local key = strlower(s):gsub("[^a-z]", "")
      if A.RACES[key] then return A.RACES[key] end
    end
  end
  return "off"
end

-- A setting ("auto", an accent or "off") as the accent to use.
function A.resolve(setting, raceFile, raceName)
  if setting == "auto" then return A.forRace(raceFile, raceName) end
  if A.valid(setting) then return setting end
  return "off"
end

-- Spans never rewritten, tried at each spot; the earliest (then longest) wins.
local PROTECT = {
  "|c.-|r",              -- coloured text, item and spell links
  "|H.-|h.-|h",          -- bare links, linked player names
  "|T.-|t", "|A.-|a", "|K.-|k", -- textures, atlases, Battle.net names
  "|.",                  -- any other escape
  "{[^}]*}",             -- {skull}, {rt8}
  "%[[^%]]*%]",          -- [Item Name] typed by hand
  "%a[%w+.-]*://[^%s]+", -- URLs
  "www%.[^%s]+",
  "@[^%s]+",             -- @names
  "%d[%w.,:%%/]*",       -- numbers with units: 300g, 10x, 3:30pm, 50%
}

local function segments(text)
  local out, pos, n = {}, 1, #text
  while pos <= n do
    local bestS, bestE
    for _, p in ipairs(PROTECT) do
      local s, e = strfind(text, p, pos)
      if s and (not bestS or s < bestS or (s == bestS and e > bestE)) then bestS, bestE = s, e end
    end
    if not bestS then
      out[#out + 1] = { s = strsub(text, pos) }
      break
    end
    if bestS > pos then out[#out + 1] = { s = strsub(text, pos, bestS - 1) } end
    out[#out + 1] = { s = strsub(text, bestS, bestE), keep = true }
    pos = bestE + 1
  end
  return out
end

local WORD = "[%a\128-\255][%a\128-\255']*"

-- A plain stretch of text as word and gap tokens.
local function tokens(text)
  local out, pos = {}, 1
  while pos <= #text do
    local s, e = strfind(text, WORD, pos)
    if not s then
      out[#out + 1] = { s = strsub(text, pos) }
      break
    end
    while e > s and strsub(text, e, e) == "'" do e = e - 1 end
    if s > pos then out[#out + 1] = { s = strsub(text, pos, s - 1) } end
    out[#out + 1] = { s = strsub(text, s, e), word = true }
    pos = e + 1
  end
  return out
end

local function hasUpper(s) return strfind(s, "%u") ~= nil end
local function hasLower(s) return strfind(s, "%l") ~= nil end

-- repl in the casing of src: ALL CAPS stays caps, Capitalized stays capitalized. A replacement with
-- its own capitals (a name) keeps them.
local function matchCase(src, repl)
  if repl == "" then return repl end
  if #src > 1 and hasUpper(src) and not hasLower(src) then return strupper(repl) end
  if strfind(src, "^%u") then return strupper(strsub(repl, 1, 1)) .. strsub(repl, 2) end
  return repl
end

-- The word and phrase tables for one accent and strength, built once.
local cache = {}
local function tables(accent, strength)
  local key = accent .. "/" .. strength
  if cache[key] then return cache[key] end
  local words, phrases = {}, {}
  local levels = strength == "thick" and { "light", "thick" } or { "light" }
  for _, level in ipairs(levels) do
    for k, v in pairs((A.WORDS[accent] or {})[level] or {}) do words[k] = v end
    for k, v in pairs((A.PHRASES[accent] or {})[level] or {}) do
      local parts = {}
      for w in k:gmatch("[^ ]+") do parts[#parts + 1] = w end
      phrases[#phrases + 1] = { words = parts, repl = v }
    end
  end
  sort(phrases, function(a, b)
    if #a.words ~= #b.words then return #a.words > #b.words end
    return a.repl < b.repl
  end)
  cache[key] = { words = words, phrases = phrases, ing = strength == "thick" and A.ING[accent] }
  return cache[key]
end

-- Does the phrase start at token i? Returns the index of its last token.
local function phraseAt(toks, i, ph)
  local j = i
  for k, w in ipairs(ph.words) do
    local t = toks[j]
    if not t or not t.word or strlower(t.s) ~= w then return nil end
    if k < #ph.words then
      local gap = toks[j + 1]
      if not gap or gap.word or not strfind(gap.s, "^%s+$") then return nil end
      j = j + 2
    end
  end
  return j
end

local function convertPlain(text, t)
  local toks = tokens(text)
  local out, i, capNext = {}, 1, false
  while i <= #toks do
    local tok = toks[i]
    if not tok.word then
      out[#out + 1] = tok.s
      i = i + 1
    else
      local done = false
      for _, ph in ipairs(t.phrases) do
        local last = phraseAt(toks, i, ph)
        if last then
          local src = {}
          for k = i, last do src[#src + 1] = toks[k].s end
          local repl = matchCase(concat(src), ph.repl)
          local after = toks[last + 1]
          if strsub(repl, -1) == "!" and after and strfind(after.s, "^[!.?]") then repl = strsub(repl, 1, -2) end
          out[#out + 1] = repl
          i = last + 1
          done = true
          break
        end
      end
      if not done then
        local lower = strlower(tok.s)
        local repl = t.words[lower]
        if repl == "" then
          -- dropped: take the space after it too, and pass a capital on to the next word
          if strfind(tok.s, "^%u") then capNext = true end
          local gap = toks[i + 1]
          if gap and not gap.word and strfind(gap.s, "^%s+$") then
            i = i + 1
          elseif #out > 0 and (not gap or not strfind(gap.s, "^%s")) then
            out[#out] = out[#out]:gsub("[,;%s]+$", "") -- "boss, please." -> "boss."
          end
        else
          local word
          if repl then
            word = matchCase(tok.s, repl)
          elseif t.ing and #lower >= 6 and strsub(lower, -3) == "ing" and not A.ING_KEEP[lower] then
            local stem = strsub(tok.s, 1, -4)
            word = stem .. (hasUpper(tok.s) and not hasLower(tok.s) and "IN'" or "in'")
          else
            word = tok.s
          end
          if capNext then
            word = strupper(strsub(word, 1, 1)) .. strsub(word, 2)
            capNext = false
          end
          out[#out + 1] = word
        end
        i = i + 1
      end
    end
  end
  return concat(out)
end

local function hash(text)
  local h = 0
  for k = 1, #text do h = (h * 31 + strbyte(text, k)) % 2147483647 end
  return h
end

-- opts: seed (picks whether and which closing line, default from the text), noTags.
function A.convert(text, accent, strength, opts)
  if type(text) ~= "string" or text == "" or not A.valid(accent) then return text end
  if strfind(text, "^%s*/") then return text end -- a slash command
  strength = strength == "thick" and "thick" or "light"
  local t = tables(accent, strength)
  local out = {}
  for _, seg in ipairs(segments(text)) do
    out[#out + 1] = seg.keep and seg.s or convertPlain(seg.s, t)
  end
  local result = concat(out)
  opts = opts or {}
  local tags = A.TAGS[accent]
  if strength == "thick" and not opts.noTags and tags and #tags > 0 then
    local seed = opts.seed or hash(text)
    if seed % 3 == 0 then
      local tag = tags[floor(seed / 3) % #tags + 1]
      local trimmed = result:gsub("%s+$", "")
      if trimmed ~= "" and not strfind(trimmed, "[%.!?]$") and not strfind(trimmed, "|r$") then trimmed = trimmed .. "." end
      result = trimmed .. " " .. tag
    end
  end
  return result
end

-- convert, kept within limit bytes (255 for chat): thick without its closing line, then light, then
-- the text as typed.
function A.fit(text, accent, strength, limit, opts)
  limit = limit or 255
  local out = A.convert(text, accent, strength, opts)
  if type(out) ~= "string" or #out <= limit then return out end
  if strength == "thick" then
    local o = {}
    for k, v in pairs(opts or {}) do o[k] = v end
    o.noTags = true
    out = A.convert(text, accent, "thick", o)
    if #out <= limit then return out end
    out = A.convert(text, accent, "light", o)
    if #out <= limit then return out end
  end
  return text
end

return A
