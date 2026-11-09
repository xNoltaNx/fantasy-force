-- FantasyForce Sync: the text format guildmates' addons share crafting and the bank in.
-- Plain Lua 5.1 functions with no game API calls, so they can be tested outside the game.
-- Loaded before FantasyForce.lua (see the .toc), which reaches them as ns.Sync.
--
-- One addon message (at most 255 bytes):
--   <protocol digit><kind letter>~<subject>~<updated, base 36>~<chunk index><chunk total>~<part of the body>
-- chunk index and total are two base-36 digits each ("0103" is chunk 1 of 3). A payload's body is cut
-- into as many messages as it needs; the receiver joins them (in any order) by sender, kind, subject
-- and updated. Kinds:
--   C  crafting of one character (subject):  class~by~prof~prof...
--        prof   = name;skill;recipe;recipe...
--        recipe = spellId[:itemId]  or  :itemId  or  ::name (only when it has no id)
--   B  the bank (subject = the bank alt):   source~money~tab~tab...
--        tab  = name;item;item...   item = itemId[:count] (count left out when 1)
--   A  one account's characters in the guild (subject = the account's random id):  main~char~char...
--        char = name;class;level;prof;prof...   prof = name:skill
--   R  a request (subject = the asker):     bankUpdated~name:updated;...~accountId:updated;...~requestId:updated;...
--        "send me anything newer than these" (the account and craft request lists came later: older
--        readers skip them, and an R without the craft request list gets no craft requests back)
--   Q  a craft request (subject = its id, asker@recipeKey):  qty~mats~state~claimer~created~class~item~name~note
--        state o (open), c (claimed), d (done), x (cancelled); name only when the key has no id; the note
--        last, cut so the whole request fits in one message
-- Numbers are base 36. Names are escaped (%XX) wherever they hold a separator, "%", "|" or a control
-- character. Receivers ignore a protocol digit they don't know and fields past the ones they read.

local _, ns = ...
local S = {}
if type(ns) == "table" then ns.Sync = S end

local type, pairs, ipairs, tostring, tonumber = type, pairs, ipairs, tostring, tonumber
local floor = math.floor
local concat, sort = table.concat, table.sort
local strbyte, strchar, strfind, strsub, strformat = string.byte, string.char, string.find, string.sub, string.format

S.PROTOCOL = "1"
S.MAX_MESSAGE = 255
S.MAX_CHUNKS = 1295 -- "zz"
S.PARTIAL_TIMEOUT = 120 -- seconds a half-received payload is kept

-- ------------------------------------------------------------- primitives --

local DIGITS = "0123456789abcdefghijklmnopqrstuvwxyz"

function S.b36(n)
  n = tonumber(n)
  if not n or n < 1 then return "0" end
  n = floor(n)
  local out = ""
  while n > 0 do
    local d = n % 36
    out = strsub(DIGITS, d + 1, d + 1) .. out
    n = floor(n / 36)
  end
  return out
end

function S.unb36(s)
  if type(s) ~= "string" or s == "" or strfind(s, "[^0-9a-z]") then return nil end
  return tonumber(s, 36)
end

local function pad2(n)
  local s = S.b36(n)
  if #s < 2 then s = "0" .. s end
  return s
end

function S.esc(s)
  s = tostring(s or "")
  return (s:gsub("[%%~;:,|%c]", function(c) return strformat("%%%02X", strbyte(c)) end))
end

function S.unesc(s)
  if type(s) ~= "string" then return "" end
  return (s:gsub("%%(%x%x)", function(h) return strchar(tonumber(h, 16)) end))
end

-- Splits on a one-character separator, keeping empty fields.
local function split(s, sep)
  local out, start = {}, 1
  while true do
    local i = strfind(s, sep, start, true)
    if not i then
      out[#out + 1] = strsub(s, start)
      return out
    end
    out[#out + 1] = strsub(s, start, i - 1)
    start = i + 1
  end
end
S.split = split

-- ---------------------------------------------------------------- crafting --

local function encodeRecipe(r)
  local id, item = tonumber(r.id), tonumber(r.item)
  local a = id and S.b36(id) or ""
  local b = item and S.b36(item) or ""
  if not id and not item then
    if type(r.name) ~= "string" or r.name == "" then return nil end
    return "::" .. S.esc(r.name)
  end
  if b ~= "" then return a .. ":" .. b end
  return a
end

-- crafter = { class = "MAGE", by = "Name", professions = { [prof] = { skill = n, recipes = { {id, item, name} } } } }
function S.encodeCrafter(c)
  local names = {}
  for prof in pairs(c.professions or {}) do
    if type(prof) == "string" and prof ~= "" then names[#names + 1] = prof end
  end
  sort(names)
  local parts = { S.esc(c.class or ""), S.esc(c.by or "") }
  for _, prof in ipairs(names) do
    local p = c.professions[prof]
    local fields = { S.esc(prof), S.b36(p.skill) }
    for _, r in ipairs(p.recipes or {}) do
      if type(r) == "table" then
        local e = encodeRecipe(r)
        if e then fields[#fields + 1] = e end
      end
    end
    parts[#parts + 1] = concat(fields, ";")
  end
  return concat(parts, "~")
end

function S.decodeCrafter(body)
  if type(body) ~= "string" then return nil end
  local parts = split(body, "~")
  if #parts < 2 then return nil end
  local c = { class = S.unesc(parts[1]), by = S.unesc(parts[2]), professions = {} }
  for i = 3, #parts do
    local fields = split(parts[i], ";")
    local prof = S.unesc(fields[1])
    if prof ~= "" then
      local recipes = {}
      for j = 3, #fields do
        if fields[j] ~= "" then
          local f = split(fields[j], ":")
          local r = { id = S.unb36(f[1]), item = S.unb36(f[2]) }
          if not r.id and not r.item and f[3] and f[3] ~= "" then r.name = S.unesc(f[3]) end
          if r.id or r.item or r.name then recipes[#recipes + 1] = r end
        end
      end
      c.professions[prof] = { skill = S.unb36(fields[2]) or 0, recipes = recipes }
    end
  end
  return c
end

-- A character record (FantasyForceDB.characters[name]) as a crafter, or nil when it has neither
-- professions nor recipes. Recipes keep their name only when they have no id.
function S.crafterFromCharacter(rec)
  if type(rec) ~= "table" then return nil end
  local profs, any = {}, false
  if type(rec.professions) == "table" then
    for _, p in ipairs(rec.professions) do
      if type(p) == "table" and type(p.name) == "string" and p.name ~= "" then
        profs[p.name] = { skill = tonumber(p.skill) or 0, recipes = {} }
        any = true
      end
    end
  end
  if type(rec.recipes) == "table" then
    for prof, list in pairs(rec.recipes) do
      if type(prof) == "string" and prof ~= "" and type(list) == "table" then
        local p = profs[prof] or { skill = 0, recipes = {} }
        profs[prof] = p
        local out = {}
        for _, r in ipairs(list) do
          if type(r) == "table" then
            local id, item = tonumber(r.id), tonumber(r.item)
            local name = type(r.name) == "string" and r.name ~= "" and r.name or nil
            if id or item or name then out[#out + 1] = { id = id, item = item, name = name } end
          end
        end
        p.recipes = out
        any = true
      end
    end
  end
  if not any then return nil end
  return { class = type(rec.class) == "string" and rec.class or "", professions = profs }
end

-- -------------------------------------------------------------------- bank --

-- bank = { source = "alt", money = n, tabs = { { name, items = { {id, count} } } } }
function S.encodeBank(b)
  local parts = { S.esc(b.source or ""), S.b36(b.money) }
  for _, t in ipairs(b.tabs or {}) do
    if type(t) == "table" then
      local fields = { S.esc(t.name or "") }
      for _, it in ipairs(t.items or {}) do
        local id = type(it) == "table" and tonumber(it.id)
        if id then
          local count = tonumber(it.count) or 1
          fields[#fields + 1] = count > 1 and (S.b36(id) .. ":" .. S.b36(count)) or S.b36(id)
        end
      end
      parts[#parts + 1] = concat(fields, ";")
    end
  end
  return concat(parts, "~")
end

function S.decodeBank(body)
  if type(body) ~= "string" then return nil end
  local parts = split(body, "~")
  if #parts < 2 then return nil end
  local b = { source = S.unesc(parts[1]), money = S.unb36(parts[2]) or 0, tabs = {} }
  for i = 3, #parts do
    local fields = split(parts[i], ";")
    local items = {}
    for j = 2, #fields do
      local f = split(fields[j], ":")
      local id = S.unb36(f[1])
      if id then items[#items + 1] = { id = id, count = S.unb36(f[2]) or 1 } end
    end
    b.tabs[#b.tabs + 1] = { name = S.unesc(fields[1]), items = items }
  end
  return b
end

-- ----------------------------------------------------------------- request --

local function encodeStamps(stamps)
  local names = {}
  for name in pairs(stamps or {}) do names[#names + 1] = name end
  sort(names)
  local list = {}
  for _, name in ipairs(names) do list[#list + 1] = S.esc(name) .. ":" .. S.b36(stamps[name]) end
  return concat(list, ";")
end

local function decodeStamps(field)
  local out = {}
  if field and field ~= "" then
    for _, pair in ipairs(split(field, ";")) do
      local f = split(pair, ":")
      local name = S.unesc(f[1])
      if name ~= "" then out[name] = S.unb36(f[2]) or 0 end
    end
  end
  return out
end

-- stamps = { [characterName] = updated }, accounts = { [accountId] = updated }, requests = { [requestId] = updated }
function S.encodeRequest(bankUpdated, stamps, accounts, requests)
  return S.b36(bankUpdated) .. "~" .. encodeStamps(stamps) .. "~" .. encodeStamps(accounts) .. "~" .. encodeStamps(requests)
end

-- requests is nil when the asker's addon doesn't know craft requests (it sent no fourth field).
function S.decodeRequest(body)
  if type(body) ~= "string" then return nil end
  local parts = split(body, "~")
  return { bank = S.unb36(parts[1]) or 0, crafters = decodeStamps(parts[2]), accounts = decodeStamps(parts[3]),
    requests = parts[4] and decodeStamps(parts[4]) or nil }
end

-- ---------------------------------------------------------------- accounts --

-- ------------------------------------------------------------------ roles --
-- Tank, healer, damage: a character's own pick (rec.roles with rec.rolesSet), else its spec's usual job
-- (the website's rule), else none. Shared as letters (T, H, D) after a character's professions.

S.ROLES = { "tank", "healer", "dps" }
local ROLE_LETTER = { tank = "T", healer = "H", dps = "D" }
local LETTER_ROLE = { T = "tank", H = "healer", D = "dps" }
local SPEC_ROLES = {
  WARRIOR = { Protection = "tank" }, PALADIN = { Holy = "healer", Protection = "tank" },
  PRIEST = { Discipline = "healer", Holy = "healer" }, SHAMAN = { Restoration = "healer" },
  DRUID = { ["Feral (bear)"] = "tank", Guardian = "tank", Restoration = "healer" },
}

-- A list of roles in tank, healer, dps order, unknown ones dropped.
function S.orderRoles(list)
  local set, out = {}, {}
  for _, r in ipairs(type(list) == "table" and list or {}) do set[r] = true end
  for _, r in ipairs(S.ROLES) do if set[r] then out[#out + 1] = r end end
  return out
end

function S.rolesFor(rec)
  if type(rec) ~= "table" then return {} end
  if rec.rolesSet and type(rec.roles) == "table" then return S.orderRoles(rec.roles) end
  local spec = type(rec.spec) == "string" and rec.spec or ""
  if spec == "" then return {} end
  local byClass = SPEC_ROLES[type(rec.class) == "string" and rec.class or ""]
  return { byClass and byClass[spec] or "dps" }
end

function S.encodeRoles(list)
  local out = ""
  for _, r in ipairs(S.orderRoles(list)) do out = out .. ROLE_LETTER[r] end
  return out
end

function S.decodeRoles(s)
  local out = {}
  for l in tostring(s or ""):gmatch("[THD]") do out[#out + 1] = LETTER_ROLE[l] end
  return S.orderRoles(out)
end

-- account = { main = "Name", chars = { { name, class, level, profs = { { name, skill } }, roles = { "tank" } } } }
-- Roles go last in a character's fields as "=" and their letters ("=TD"), only when it has any.
function S.encodeAccount(a)
  local parts = { S.esc(a.main or "") }
  for _, c in ipairs(a.chars or {}) do
    local fields = { S.esc(c.name or ""), S.esc(c.class or ""), S.b36(c.level) }
    for _, p in ipairs(c.profs or {}) do fields[#fields + 1] = S.esc(p.name or "") .. ":" .. S.b36(p.skill) end
    local roles = S.encodeRoles(c.roles)
    if roles ~= "" then fields[#fields + 1] = "=" .. roles end
    parts[#parts + 1] = concat(fields, ";")
  end
  return concat(parts, "~")
end

function S.decodeAccount(body)
  if type(body) ~= "string" then return nil end
  local parts = split(body, "~")
  local a = { main = S.unesc(parts[1]), chars = {} }
  for i = 2, #parts do
    local f = split(parts[i], ";")
    local c = { name = S.unesc(f[1]), class = S.unesc(f[2]), level = S.unb36(f[3]) or 0, profs = {}, roles = {} }
    for j = 4, #f do
      if strsub(f[j], 1, 1) == "=" then
        c.roles = S.decodeRoles(strsub(f[j], 2))
      else
        local p = split(f[j], ":")
        local pname = S.unesc(p[1])
        if pname ~= "" then c.profs[#c.profs + 1] = { name = pname, skill = S.unb36(p[2]) or 0 } end
      end
    end
    if c.name ~= "" then a.chars[#a.chars + 1] = c end
  end
  if a.main == "" or #a.chars == 0 then return nil end
  return a
end

-- One account from character records (FantasyForceDB.characters) in one guild: its characters sorted
-- by name, and its main: `chosen` when it's one of them, else the highest level, ties going to the
-- most recently played. nil when the account has nobody in that guild.
function S.accountFromCharacters(characters, guild, chosen)
  local chars, best = {}, nil
  for name, rec in pairs(characters or {}) do
    if type(rec) == "table" and type(name) == "string" and name ~= "" and rec.guild == guild then
      local c = { name = name, class = type(rec.class) == "string" and rec.class or "", level = tonumber(rec.level) or 0,
        profs = {}, played = tonumber(rec.updated) or 0, roles = S.rolesFor(rec) }
      for _, p in ipairs(type(rec.professions) == "table" and rec.professions or {}) do
        if type(p) == "table" and type(p.name) == "string" and p.name ~= "" then
          c.profs[#c.profs + 1] = { name = p.name, skill = tonumber(p.skill) or 0 }
        end
      end
      chars[#chars + 1] = c
      if not best or c.level > best.level or (c.level == best.level and c.played > best.played) then best = c end
    end
  end
  if not best then return nil end
  sort(chars, function(x, y) return x.name < y.name end)
  local main = best.name
  for _, c in ipairs(chars) do
    if c.name == chosen then main = chosen end
    c.played = nil
  end
  return { main = main, chars = chars }
end

-- Who's whose main: { [characterName] = { main, account, alts = { char records }, char = record } } from
-- accounts = { [accountId] = { updated, main, chars } }. A character listed by two accounts (moved
-- between accounts) goes with the newer record.
function S.mainIndex(accounts)
  local owner = {}
  for id, a in pairs(accounts or {}) do
    if type(a) == "table" and type(a.chars) == "table" then
      for _, c in ipairs(a.chars) do
        local o = owner[c.name]
        if not o or (tonumber(a.updated) or 0) > (tonumber(accounts[o].updated) or 0) then owner[c.name] = id end
      end
    end
  end
  local index = {}
  for name, id in pairs(owner) do
    local a = accounts[id]
    local entry = { main = a.main, account = id, alts = {} }
    for _, c in ipairs(a.chars) do
      if c.name == name then entry.char = c end
      if c.name ~= a.main and owner[c.name] == id then entry.alts[#entry.alts + 1] = c end
    end
    index[name] = entry
  end
  return index
end

-- A guild member's main from their public note, only when it says so plainly: "alt of Morwen", "Morwen's alt",
-- "main: Morwen", "Morwen alt" (any case). The name must be a member (names = the guild's names; a one-word
-- note name also matches a member whose name starts with that word, when only one does). nil otherwise.
local NOTE_WORD = "([^%s,%.!%?:;=%(%)%[%]\"]+)"
S.NOTE_PATTERNS = { "%f[%w]alt of%s+" .. NOTE_WORD, NOTE_WORD .. "'s alt%f[%W]", "%f[%w]main%s*[:=%-]?%s*" .. NOTE_WORD,
  NOTE_WORD .. "%s+alt%f[%W]" }

function S.mainFromNote(note, names, self)
  if type(note) ~= "string" or note == "" then return nil end
  local lower = note:lower()
  local exact, first = {}, {}
  for _, n in ipairs(names or {}) do
    local l = n:lower()
    exact[l] = n
    local w = l:match("^(%S+)")
    if w then first[w] = (first[w] == nil) and n or false end
  end
  for _, pat in ipairs(S.NOTE_PATTERNS) do
    local w = lower:match(pat)
    local found = w and (exact[w] or first[w] or nil)
    if found and found ~= self then return found end
  end
  return nil
end

-- --------------------------------------------------------------- chunking --

local function header(kind, subject, updated, idx, total)
  return S.PROTOCOL .. kind .. "~" .. S.esc(subject) .. "~" .. S.b36(updated) .. "~" .. pad2(idx) .. pad2(total) .. "~"
end

-- The messages carrying one payload, each at most maxLen bytes; nil when it can't be sent.
-- A cut never falls inside a UTF-8 character.
function S.chunk(kind, subject, updated, body, maxLen)
  maxLen = maxLen or S.MAX_MESSAGE
  body = body or ""
  local room = maxLen - #header(kind, subject, updated, 1, 1)
  if room < 16 then return nil end
  local parts, pos, n = {}, 1, #body
  if n == 0 then parts[1] = "" end
  while pos <= n do
    local stop = pos + room - 1
    if stop >= n then
      stop = n
    else
      while stop > pos do
        local nextByte = strbyte(body, stop + 1)
        if nextByte < 128 or nextByte >= 192 then break end
        stop = stop - 1
      end
    end
    parts[#parts + 1] = strsub(body, pos, stop)
    pos = stop + 1
  end
  if #parts > S.MAX_CHUNKS then return nil end
  local msgs = {}
  for i, p in ipairs(parts) do msgs[i] = header(kind, subject, updated, i, #parts) .. p end
  return msgs
end

-- One message's header, or nil when it isn't ours or is from a protocol we don't know.
function S.parse(msg)
  if type(msg) ~= "string" then return nil end
  local ver, kind, subject, upd, idx, total, part =
    msg:match("^(%d)(%u)~([^~]*)~([0-9a-z]+)~([0-9a-z][0-9a-z])([0-9a-z][0-9a-z])~(.*)$")
  if ver ~= S.PROTOCOL then return nil end
  idx, total = S.unb36(idx), S.unb36(total)
  if not idx or not total or idx < 1 or total < 1 or idx > total then return nil end
  return { kind = kind, subject = S.unesc(subject), updated = S.unb36(upd) or 0, idx = idx, total = total, part = part }
end

function S.newAssembler(timeout)
  return { partial = {}, timeout = timeout or S.PARTIAL_TIMEOUT }
end

-- Adds one message. Returns the whole payload { kind, subject, updated, sender, body } once every
-- chunk is in, else nil; and the message's header either way (nil when it isn't one of ours).
function S.assemble(state, sender, msg, now)
  local h = S.parse(msg)
  if not h then return nil, nil end
  now = tonumber(now) or 0
  for key, p in pairs(state.partial) do
    if now - p.first > state.timeout then state.partial[key] = nil end
  end
  if h.total == 1 then
    return { kind = h.kind, subject = h.subject, updated = h.updated, sender = sender, body = h.part }, h
  end
  local key = tostring(sender) .. "~" .. h.kind .. "~" .. h.subject .. "~" .. h.updated
  local p = state.partial[key]
  if not p or p.total ~= h.total then
    p = { total = h.total, have = 0, parts = {}, first = now }
    state.partial[key] = p
  end
  if not p.parts[h.idx] then p.have = p.have + 1 end
  p.parts[h.idx] = h.part
  if p.have < p.total then return nil, h end
  state.partial[key] = nil
  return { kind = h.kind, subject = h.subject, updated = h.updated, sender = sender, body = concat(p.parts) }, h
end

-- ---------------------------------------------------------- craft requests --
-- A guildmate asks the guild's crafters to make a recipe. One request per recipe per asker at a time: its id
-- is asker@recipeKey, the Crafting tab's key ("Engineering#s19790": the profession, then s and the spell id,
-- i and the item id, or n and the lower-case name). The newest `updated` wins, except that a done or
-- cancelled request stays so (a claim sent before it heard can't bring it back) until the asker asks again
-- (a newer `created`). Every request is dropped 7 days after it was made, whatever its state.
-- request = { asker, class, prof, key, spell, item, name, qty, mats, note, state, claimer, created, updated }

S.REQUEST_MAX_AGE = 7 * 86400
S.NOTE_MAX = 60
S.QTY_MAX = 999
local STATE_LETTER = { open = "o", claimed = "c", done = "d", cancelled = "x" }
local LETTER_STATE = { o = "open", c = "claimed", d = "done", x = "cancelled" }

function S.craftRequestId(asker, key)
  return tostring(asker or "") .. "@" .. tostring(key or "")
end

-- { asker, key, prof, spell or item or lname } from an id, or nil when it isn't one.
function S.parseCraftRequestId(id)
  if type(id) ~= "string" then return nil end
  local asker, key = id:match("^([^@]+)@(.+)$")
  if not asker then return nil end
  local prof, kind, ref = key:match("^(.+)#([sin])(.+)$")
  if not prof then return nil end
  local out = { asker = asker, key = key, prof = prof }
  if kind == "s" then out.spell = tonumber(ref) elseif kind == "i" then out.item = tonumber(ref) else out.lname = ref end
  if kind ~= "n" and not (out.spell or out.item) then return nil end
  return out
end

-- Open or claimed, and not yet 7 days old.
function S.requestActive(r, now)
  return type(r) == "table" and (r.state == "open" or r.state == "claimed")
    and (tonumber(r.created) or 0) + S.REQUEST_MAX_AGE > (tonumber(now) or 0)
end

local function dropLastLetter(s)
  local i = #s
  while i > 1 do
    local b = strbyte(s, i)
    if b < 128 or b >= 192 then break end
    i = i - 1
  end
  return strsub(s, 1, i - 1)
end

-- A note as it's kept and sent: no links or colours (|), no control characters, at most NOTE_MAX letters.
function S.cleanNote(s)
  s = tostring(s or ""):gsub("|", ""):gsub("%c", " "):gsub("^%s+", ""):gsub("%s+$", "")
  local count, i, n = 0, 1, #s
  while i <= n do
    local c = strbyte(s, i)
    count = count + 1
    if count > S.NOTE_MAX then return strsub(s, 1, i - 1) end
    i = i + (c >= 240 and 4 or c >= 224 and 3 or c >= 192 and 2 or 1)
  end
  return s
end

-- The body of request id as of r.updated; the note is cut (by whole letters) so it all fits in one message.
function S.encodeCraftRequest(id, r)
  local named = not (r.spell or r.item)
  local head = concat({ S.b36(r.qty), r.mats and "1" or "0", STATE_LETTER[r.state] or "o", S.esc(r.claimer or ""),
    S.b36(r.created), S.esc(r.class or ""), S.b36(r.item), named and S.esc(r.name or "") or "" }, "~") .. "~"
  local room = S.MAX_MESSAGE - #header("Q", id, r.updated, 1, 1)
  local note = S.cleanNote(r.note)
  local body = head .. S.esc(note)
  while #body > room and note ~= "" do
    note = dropLastLetter(note)
    body = head .. S.esc(note)
  end
  return body
end

function S.decodeCraftRequest(id, updated, body)
  local p = S.parseCraftRequestId(id)
  if not p or type(body) ~= "string" then return nil end
  local f = split(body, "~")
  local state, created = LETTER_STATE[f[3] or ""], S.unb36(f[5])
  if not state or not created or created < 1 then return nil end
  local claimer = (f[4] and f[4] ~= "") and S.unesc(f[4]) or nil
  if state == "claimed" and not claimer then state = "open" end
  local item = S.unb36(f[7])
  local qty = S.unb36(f[1]) or 1
  return { asker = p.asker, prof = p.prof, key = p.key, spell = p.spell, item = p.item or (item and item > 0 and item) or nil,
    name = (f[8] and f[8] ~= "") and S.unesc(f[8]) or nil, qty = math.max(1, math.min(S.QTY_MAX, qty)), mats = f[2] == "1",
    state = state, claimer = state ~= "open" and claimer or nil, created = created, class = S.unesc(f[6]),
    note = f[9] and S.cleanNote(S.unesc(f[9])) or "", updated = tonumber(updated) or created }
end

-- Keeps a request when it's newer (by the rules above). Returns true when it replaced what was there.
function S.storeCraftRequest(reqs, id, r, now, from)
  if type(r) ~= "table" or not S.parseCraftRequestId(id) then return false end
  local created = tonumber(r.created) or 0
  if created + S.REQUEST_MAX_AGE <= (tonumber(now) or 0) then return false end
  local old = reqs[id]
  if type(old) == "table" then
    local oldCreated = tonumber(old.created) or 0
    if created < oldCreated then return false end
    if created == oldCreated then
      if (tonumber(old.updated) or 0) >= (tonumber(r.updated) or 0) then return false end
      if (old.state == "done" or old.state == "cancelled") and (r.state == "open" or r.state == "claimed") then return false end
    end
  end
  r.from, r.heard = from, now
  reqs[id] = r
  return true
end

-- Drops requests 7 days old, whatever their state.
function S.pruneCraftRequests(reqs, now)
  for id, r in pairs(reqs) do
    if type(r) ~= "table" or (tonumber(r.created) or 0) + S.REQUEST_MAX_AGE <= now then reqs[id] = nil end
  end
end

-- What one account sees, active requests only, newest first, each { id, r }: forYou (open, and one of its
-- characters can make it), taken (claimed, one of its characters can make it) and mine (its own characters'
-- requests). names = { [characterName] = true } on this account; keys = { [recipeKey] = true } it can make.
function S.craftRequestView(reqs, now, names, keys)
  local v = { forYou = {}, taken = {}, mine = {} }
  for id, r in pairs(reqs or {}) do
    if S.requestActive(r, now) then
      local list
      if names[r.asker] then list = v.mine
      elseif keys[r.key] then list = r.state == "open" and v.forYou or v.taken end
      if list then list[#list + 1] = { id = id, r = r } end
    end
  end
  local function newest(a, b)
    if a.r.created ~= b.r.created then return a.r.created > b.r.created end
    return a.id < b.id
  end
  sort(v.forYou, newest)
  sort(v.taken, newest)
  sort(v.mine, newest)
  return v
end

-- ---------------------------------------------------------------- storing --

-- Keeps a crafter's newest data. Returns true when this replaced what was there.
function S.storeCrafter(crafters, subject, updated, c, from, now)
  local old = crafters[subject]
  if type(old) == "table" and (tonumber(old.updated) or 0) >= updated then
    if old.updated == updated then old.heard = now end
    return false
  end
  crafters[subject] = { updated = updated, class = c.class, by = c.by, from = from, heard = now,
    professions = c.professions }
  return true
end

-- Keeps the newest bank. Returns the new shared.bank when it replaced the old one, else nil.
function S.storeBank(old, subject, updated, b, from)
  if type(old) == "table" and (tonumber(old.updated) or 0) >= updated then return nil end
  return { source = b.source, updated = updated, by = subject, money = b.money, tabs = b.tabs, from = from }
end

-- Keeps an account's newest record. Returns true when this replaced what was there.
function S.storeAccount(accounts, id, updated, a, from, now)
  local old = accounts[id]
  if type(old) == "table" and (tonumber(old.updated) or 0) >= updated then
    if old.updated == updated then old.heard = now end
    return false
  end
  accounts[id] = { updated = updated, main = a.main, chars = a.chars, from = from, heard = now }
  return true
end

-- Drops crafters (or accounts) not heard from in maxAge seconds.
function S.prune(crafters, now, maxAge)
  for name, c in pairs(crafters) do
    if type(c) ~= "table" or (tonumber(c.heard) or tonumber(c.updated) or 0) < now - maxAge then
      crafters[name] = nil
    end
  end
end

return S
