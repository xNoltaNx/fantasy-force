-- The preview's side of the pretend game: starts the addon in the shared fake game (fakegame.lua) with the
-- pretend guild (world.lua), passes the page's mouse, keys and chat in, and hands the page what to draw.
-- The page (preview.js) calls PREVIEW_CALL(name, ...) and gets JSON back; it supplies HOST_measure (text
-- size), HOST_now (seconds, for GetTime) and HOST_time (epoch seconds).

local FakeGame = assert(load(FAKEGAME_SRC, "@fakegame.lua", "t"))()
local makeWorld = assert(load(WORLD_SRC, "@world.lua", "t"))()
local SOURCES = {}
for i, name in ipairs(ADDON_FILES) do SOURCES[i] = { name = name, src = ADDON_SOURCES[i] } end

local P = {}
local client, world, settings
local timers, chatOut, notices, errors, caught = {}, {}, {}, {}, 0
local cursorX, cursorY = 0, 0

local RACES = { Troll = { "Troll", "Troll" }, Orc = { "Orc", "Orc" }, Tauren = { "Tauren", "Tauren" },
  Undead = { "Undead", "Scourge" }, Skyborne = { "Skyborne", "Skyborne" }, Human = { "Human", "Human" } }

-- ------------------------------------------------------------------ json --
local function jstr(s)
  return '"' .. tostring(s):gsub('[%c"\\]', function(c)
    if c == '"' then return '\\"' end
    if c == "\\" then return "\\\\" end
    if c == "\n" then return "\\n" end
    return string.format("\\u%04x", c:byte())
  end) .. '"'
end
local function json(v)
  local t = type(v)
  if t == "string" then return jstr(v) end
  if t == "number" then
    if v ~= v or v == math.huge or v == -math.huge then return "0" end
    if math.type and math.type(v) == "integer" then return tostring(v) end
    return string.format("%.3f", v):gsub("%.?0+$", "")
  end
  if t == "boolean" then return tostring(v) end
  if t ~= "table" then return "null" end
  if #v > 0 or next(v) == nil then
    local parts = {}
    for i = 1, #v do parts[i] = json(v[i]) end
    return "[" .. table.concat(parts, ",") .. "]"
  end
  local parts = {}
  for k, val in pairs(v) do parts[#parts + 1] = jstr(k) .. ":" .. json(val) end
  return "{" .. table.concat(parts, ",") .. "}"
end

-- ------------------------------------------------------------------ chat --
local CHAT = {
  SAY = { "%s says: %s", 1, 1, 1 }, YELL = { "%s yells: %s", 1, 0.25, 0.25 },
  GUILD = { "[Guild] %s: %s", 0.25, 1, 0.25 }, OFFICER = { "[Officer] %s: %s", 0.25, 0.75, 0.25 },
  PARTY = { "[Party] %s: %s", 0.67, 0.67, 1 }, RAID = { "[Raid] %s: %s", 1, 0.5, 0 },
  WHISPER = { "%s whispers: %s", 1, 0.5, 1 }, WHISPER_INFORM = { "To %s: %s", 1, 0.5, 1 },
}

local function classOf(name)
  for _, m in ipairs(world.roster) do if m.name == name then return m.class end end
end

local function nameLink(name)
  local c = FakeGame.CLASS_COLORS[classOf(name) or ""]
  local code = c and string.format("|cff%02x%02x%02x", math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255)) or "|cffffffff"
  return "|Hplayer:" .. name .. "|h[" .. code .. name .. "|r]|h"
end

-- A chat event reaching the chat frame: the addon's message filters run first, as in the game.
local function chatEvent(kind, author, msg, target)
  local ev = "CHAT_MSG_" .. kind
  local filter = client.filters[ev]
  if filter then
    local ok, stop, newMsg = pcall(filter, nil, ev, msg, author .. "-Realm")
    if ok and stop then return end
    if ok and type(newMsg) == "string" then msg = newMsg end
  end
  local f = CHAT[kind] or CHAT.SAY
  local who = kind == "WHISPER_INFORM" and nameLink(target or "?") or nameLink(author)
  chatOut[#chatOut + 1] = { text = string.format(f[1], who, msg), r = f[2], g = f[3], b = f[4] }
end

-- ----------------------------------------------------------------- start --
local function copy(t)
  if type(t) ~= "table" then return t end
  local out = {}
  for k, v in pairs(t) do out[k] = copy(v) end
  return out
end

local function deliver(kind, subject, updated, body, sender)
  local S = client.ns.Sync
  for _, msg in ipairs(S.chunk(kind, subject, updated, body) or {}) do
    client.fire("CHAT_MSG_ADDON", "FantasyForce", msg, "GUILD", sender .. "-Realm")
  end
end

-- What guildmates' addons share arrives over the guild channel, through the addon's own receiving code.
local function shareGuild()
  local S = client.ns.Sync
  if not S then return end
  for _, a in ipairs(world.accounts) do
    local sender = a.online[1] or "Pip Ashwhistle" -- someone online passes it on
    local acc = S.accountFromCharacters(a.records, world.guild, a.main)
    if acc then deliver("A", a.id, a.updated, S.encodeAccount(acc), sender) end
    for name, rec in pairs(a.records) do
      local c = S.crafterFromCharacter(rec)
      if c and next(c.professions) then
        c.by = a.main
        deliver("C", name, rec.updated, S.encodeCrafter(c), sender)
      end
    end
  end
  -- the scan before the bank's newest, so the Bank tab can say what changed since
  if world.bankBefore then
    deliver("B", world.bankBefore.by, world.bankBefore.updated, S.encodeBank(world.bankBefore), world.bankBefore.sender)
  end
  deliver("B", world.bank.by, world.bank.updated, S.encodeBank(world.bank), world.bank.sender)
end

-- settings: race, officer, blocked, data ("full" or "empty"); saved: the SavedVariables of the last
-- session (a /reload keeps them) or "" for a first start.
function P.start(race, officer, blocked, data, savedDB, savedChar, openTab, screenW, screenH)
  settings = { race = race, officer = officer, blocked = blocked, data = data }
  timers, chatOut, notices, errors = {}, {}, {}, {}
  local now = HOST_time()
  world = makeWorld(now)
  local db, charDB
  if savedDB and savedDB ~= "" then db = assert(load("return " .. savedDB, "=FantasyForceDB", "t", {}))() end
  if savedChar and savedChar ~= "" then charDB = assert(load("return " .. savedChar, "=FantasyForceCharDB", "t", {}))() end
  if not db and data == "full" then db = { characters = copy(world.own), raids = copy(world.raids) } end
  local roster = world.roster
  client = FakeGame.newClient({
    name = world.player.name, class = world.player.class, className = "Hunter", race = RACES[race] or RACES.Orc,
    level = world.player.level, faction = "Horde", guild = world.guild,
    rankIndex = officer and 1 or 2, rankName = officer and "Officer" or "Raider",
    db = db, charDB = charDB, sources = SOURCES,
    pcall = function(fn, ...)
      local r = table.pack(pcall(fn, ...))
      if not r[1] then caught = caught + 1 end
      return table.unpack(r, 1, r.n)
    end,
    time = HOST_time, now = HOST_now,
    after = function(sec, fn) timers[#timers + 1] = { at = HOST_now() + (tonumber(sec) or 0), fn = fn } end,
    roster = function() return roster end,
    profs = world.player.profs, items = world.items, spells = world.spells, money = 1234567,
    sendAddon = function() return 0 end,
    onSend = function(msg, chatType, _, target)
      chatEvent(chatType == "WHISPER" and "WHISPER_INFORM" or chatType, world.player.name, msg, target)
    end,
    onChat = function(m, r, g, b) chatOut[#chatOut + 1] = { text = m, r = r or 1, g = g or 1, b = b or 0.6 } end,
    openChat = function(t) notices.openChat = t end,
    insertLink = function(l) notices.insertLink = l return true end,
    reload = function() notices.reload = true end,
    cursor = function() return cursorX, cursorY end,
    measure = function(t, font, wrap, sp) return HOST_measure(t, font or "GameFontNormal", wrap or 0, sp or 0) end,
    noParse = blocked,
    screen = { w = screenW, h = screenH },
  })
  client.fire("ADDON_LOADED", "FantasyForce")
  client.fire("PLAYER_LOGIN")
  client.fire("PLAYER_ENTERING_WORLD")
  if blocked then
    -- the game stopped the addon's SendChatMessage wrapper (what ADDON_ACTION_BLOCKED reports)
    client.fire("ADDON_ACTION_BLOCKED", "FantasyForce", "SendChatMessage()")
  end
  if data == "full" then
    shareGuild()
    for _, l in ipairs(world.guildChat) do chatEvent("GUILD", l[1], l[2]) end
  end
  if openTab ~= "" then
    local panel = client.ns.ff and client.ns.ff.panel
    if panel and panel.open then panel.open(openTab ~= "last" and openTab or nil) end
  end
  return true
end

-- ------------------------------------------------------------- snapshot --
local function frameOf(id) return client.frames[tonumber(id)] end

local function alphaOf(f)
  local a = 1
  while f do
    a = a * (f._alpha or 1)
    f = f._parent
  end
  return a
end

local function topOf(f)
  local root = client.root
  while f._parent and f._parent ~= root do f = f._parent end
  return f._id
end

local function color(c) if c then return { c[1], c[2], c[3], c[4] or 1 } end end

-- Everything shown, in drawing order, with CSS positions (pixels from the top left).
function P.snapshot()
  local H = client.screenH
  client.memo = {}
  local frames = {}
  local function visit(f)
    if not f._shown then return end
    frames[#frames + 1] = f
    for _, c in ipairs(f._children) do visit(c) end
  end
  for _, c in ipairs(client.root._children) do visit(c) end
  for i, f in ipairs(frames) do f._order = i end
  table.sort(frames, function(a, b)
    local sa, sb = FakeGame.STRATA[FakeGame.strata(a)] or 3, FakeGame.STRATA[FakeGame.strata(b)] or 3
    if sa ~= sb then return sa < sb end
    local la, lb = FakeGame.level(a), FakeGame.level(b)
    if la ~= lb then return la < lb end
    return a._order < b._order
  end)
  local nodes, z, anyUpdate, tooltip = {}, 0, false, nil
  for _, f in ipairs(frames) do
    if f._kind == "GameTooltip" then
      local ol, ob, ow, oh = FakeGame.rect(client, f._owner or client.root)
      local lines = {}
      for i, text in ipairs(f._lines) do
        local c = f._colors and f._colors[i] or { 1, 0.82, 0, false }
        lines[i] = { text = text, r = c[1], g = c[2], b = c[3], wrap = c[4] }
      end
      tooltip = { title = f._text or "", color = color(f._textColor), lines = lines, anchor = f._anchor or "ANCHOR_RIGHT",
        owner = ol and { ol, H - (ob + oh), ow, oh } or nil }
    else
      local l, b, w, h = FakeGame.rect(client, f)
      if f._scripts.OnUpdate and f:IsVisible() then anyUpdate = true end
      if l then
        z = z + 1
        local s = f._scripts
        local n = { i = f._id, t = "F", k = f._kind, tp = f._template, x = l, y = H - (b + h), w = w, h = h, z = z,
          a = alphaOf(f), top = topOf(f), nm = f._name }
        if f._kind == "Button" or f._kind == "CheckButton" or f._kind == "EditBox" or f._kind == "Slider" or f._mouse
          or s.OnEnter or s.OnMouseDown then n.m = true end
        if f._wheel then n.wh = true end
        if f._drag then n.dr = true end
        if f._moving then n.mv = true end
        if f._checked then n.chk = true end
        if f._selected then n.sel = true end
        if f._lockHighlight then n.lock = true end
        if f._disabled then n.dis = true end
        if f._hitInsets then n.hit = f._hitInsets end
        if f._backdrop then n.bd = f._backdrop.edgeFile or f._backdrop.bgFile or "plain" end
        if f._kind == "EditBox" then
          n.txt = f._text or ""
          n.font = f._font
          n.foc = client.focus == f
          if f._highlighted then n.sela = true f._highlighted = false end
        end
        nodes[#nodes + 1] = n
        local regions = {}
        for _, r in ipairs(f._regions) do
          local hidden = not r._shown or (r._checkedOnly and not f._checked) or r._pushedOnly
            or (r._disabledOnly and not f._disabled)
            or (r._isInstructions and ((f._text or "") ~= "" or client.focus == f))
          if not hidden then regions[#regions + 1] = r end
        end
        table.sort(regions, function(a, b2)
          local la, lb = FakeGame.LAYERS[a._layer or "ARTWORK"] or 3, FakeGame.LAYERS[b2._layer or "ARTWORK"] or 3
          if la ~= lb then return la < lb end
          if (a._sublevel or 0) ~= (b2._sublevel or 0) then return (a._sublevel or 0) < (b2._sublevel or 0) end
          return a._id < b2._id
        end)
        for _, r in ipairs(regions) do
          local rl, rb, rw, rh = FakeGame.rect(client, r)
          if rl then
            z = z + 1
            local rn = { i = r._id, p = f._id, t = r._kind == "FontString" and "S" or "T", x = rl, y = H - (rb + rh), w = rw, h = rh,
              z = z, a = alphaOf(r) }
            if r._layer == "HIGHLIGHT" then rn.hl = true end
            if r._kind == "FontString" then
              rn.text = r._text or ""
              rn.font = r._font
              rn.c = color(r._color)
              -- a disabled button's label in the game's grey (its DisabledFontObject)
              if f._disabled and r == rawget(f, "Text") then rn.font, rn.c = "GameFontDisable", nil end
              rn.jh = r._justifyH
              rn.jv = r._justifyV
              rn.sp = r._spacing
              if r._wrap == false then rn.nw = true end
              if r._w then rn.fw = true end
            else
              if type(r._texture) == "string" or type(r._texture) == "number" then rn.tex = r._texture end
              rn.col = color(r._colorTex)
              rn.tc = r._texCoord
              rn.vc = color(r._vertex)
              if r._desaturated then rn.ds = true end
              if r._blend then rn.bl = r._blend end
            end
            nodes[#nodes + 1] = rn
          end
        end
      end
    end
  end
  client.memo = nil
  local out = { nodes = nodes, tooltip = tooltip, chat = chatOut, notices = notices, errors = errors,
    update = anyUpdate, caught = caught }
  chatOut, notices, errors = {}, {}, {}
  return json(out)
end

-- ----------------------------------------------------------------- input --
function P.enter(id) local f = frameOf(id) if f and f._scripts.OnEnter then f._scripts.OnEnter(f, true) end end
function P.leave(id) local f = frameOf(id) if f and f._scripts.OnLeave then f._scripts.OnLeave(f, true) end end
function P.click(id, button, shift)
  local f = frameOf(id)
  client.shift = shift and true or false
  if f then FakeGame.click(client, f, button) end
  client.shift = false
end
function P.wheel(id, delta) local f = frameOf(id) if f and f._scripts.OnMouseWheel then f._scripts.OnMouseWheel(f, delta) end end
function P.dragStart(id) local f = frameOf(id) if f and f._scripts.OnDragStart then f._scripts.OnDragStart(f, "LeftButton") end end
function P.dragMove(id, dx, dy)
  local f = frameOf(id)
  if not (f and f._moving) then return end
  local p = f._points[1]
  p.x, p.y = p.x + dx, p.y - dy
  if f._clamped then
    local l, b, w, h = FakeGame.rect(client, f)
    if l then
      if l < 0 then p.x = p.x - l elseif l + w > client.screenW then p.x = p.x - (l + w - client.screenW) end
      if b < 0 then p.y = p.y - b elseif b + h > client.screenH then p.y = p.y - (b + h - client.screenH) end
    end
  end
end
function P.dragStop(id) local f = frameOf(id) if f and f._scripts.OnDragStop then f._scripts.OnDragStop(f) end end
function P.cursor(x, y) cursorX, cursorY = x, client.screenH - y end
function P.update(elapsed) FakeGame.update(client, elapsed) end
-- The mouse moved while something runs OnUpdate (the minimap button being dragged).
function P.drive(x, y, elapsed)
  P.cursor(x, y)
  FakeGame.update(client, elapsed)
end
function P.tick()
  local now, due = HOST_now(), {}
  for i = #timers, 1, -1 do
    if timers[i].at <= now then due[#due + 1] = table.remove(timers, i) end
  end
  table.sort(due, function(a, b) return a.at < b.at end)
  for _, t in ipairs(due) do
    local ok, err = xpcall(t.fn, debug.traceback)
    if not ok then errors[#errors + 1] = err end
  end
  return #due > 0
end
function P.focus(id) local f = frameOf(id) if f then f:SetFocus() end end
function P.blur(id) local f = frameOf(id) if f then f:ClearFocus() end end
function P.typed(id, text) local f = frameOf(id) if f then f:Type(text) end end
function P.key(id, key)
  local f = frameOf(id)
  if not f then return end
  if key == "ENTER" then
    if f._scripts.OnEnterPressed then f._scripts.OnEnterPressed(f) end
  elseif key == "ESCAPE" then
    if f._scripts.OnEscapePressed then f._scripts.OnEscapePressed(f) else f:ClearFocus() end
  end
end
function P.escape() return FakeGame.pressEscape(client) end
function P.setSlider(id, frac)
  local f = frameOf(id)
  if not f then return end
  local min, max = f._min or 0, f._max or 0
  local v = min + math.max(0, math.min(1, frac)) * (max - min)
  if f._step and f._step > 0 then v = math.floor(v / f._step + 0.5) * f._step end
  f:SetValue(v)
end
-- The chat box's Enter: returns where the box stays (chat type, whisper target).
function P.chat(text, chatType, target)
  local ct, tg = FakeGame.typeInChat(client, text, chatType, target ~= "" and target or nil)
  notices.chatType, notices.chatTarget = ct, tg
end
-- What a /reload would keep, and whether the window is open (and on which tab).
function P.save()
  local env = client.env
  local panel = client.ns.ff and client.ns.ff.panel
  local open = panel and panel.frame and panel.frame:IsShown() and (panel.current or "last") or ""
  return json({ db = env.FantasyForceDB and FakeGame.serialize(env.FantasyForceDB) or "",
    char = env.FantasyForceCharDB and FakeGame.serialize(env.FantasyForceCharDB) or "", open = open })
end

-- Every call from the page: errors come back as the game's error box would show them.
function PREVIEW_CALL(name, ...)
  local fn = P[name]
  if not fn then error("no preview call " .. tostring(name)) end
  local ok, res = xpcall(fn, debug.traceback, ...)
  if not ok then
    errors[#errors + 1] = res
    if name == "start" then return json({ errors = errors }) end
  end
  if name == "save" then return res end
  if name == "tick" and not res and #errors == 0 then return "" end -- nothing was due: nothing to redraw
  return P.snapshot()
end
