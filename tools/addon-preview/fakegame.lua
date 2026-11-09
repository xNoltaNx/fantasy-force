-- A pretend World of Warcraft client for the FantasyForce addon: the game API the addon calls, and a frame
-- model that keeps what the game would draw (anchors, sizes, layers, text, textures). One module for both
-- the addon's tests (the harness drives it headless) and the web preview (which draws its frames as DOM).
--
--   local FakeGame = load(FAKEGAME_SRC)()
--   local client = FakeGame.newClient(opts)   -- loads opts.sources (the addon's files, .toc order) into it
--
-- opts (all optional but name and sources):
--   name, class ("MAGE"), race = { "Orc", "Orc" }, level, faction, guild ("Fantasy Force"; "" for none),
--   rankName, rankIndex, db (FantasyForceDB), charDB (FantasyForceCharDB), sources = { { name, src } },
--   now() (GetTime), time() (epoch seconds), date(), after(sec, fn) (C_Timer.After), ticker(sec, fn),
--   roster() -> { { name, class, level, online, rank, rankIndex, note } }, profs = { { name, skill, max } },
--   tradeskill = { prof, list = { { name, id, item } } }, bags = { [bag] = { { id, count } } }, money,
--   items = { [id] = "Name" or { name, quality, icon } }, spells = { [id] = "Name" or { name, icon } },
--   sendAddon(prefix, msg, chan) -> code, onSend(msg, chatType, lang, target), onChat(text, r, g, b),
--   openChat(text), insertLink(link), reload(), cursor() -> x, y, measure(text, font, wrapWidth, spacing) -> w, h,
--   screen = { w, h }, minimap = { x, y, size } (its centre from the screen's top right), pcall,
--   noParse (no chat box hook to post-hook), noSendChat (no SendChatMessage),
--   missingTemplates = { [templateName] = true } (a client without them: CreateFrame errors, as the game does),
--   chat = "global" (the chat box parses through the global ChatEdit_ParseText; the default), "mixin" (the box's
--   own ParseText method; the global is there but never called) or "send" (no parse step to hook: noParse).
-- Taint, as newer clients judge it: the addon writing over one of the game's globals, writing a field onto a
-- game frame, hooking the game's chat box path, putting text in the game's chat box, replacing a game function
-- or adding to UISpecialFrames is recorded (client.taint, FakeGame.tainted); the game then blocks its own
-- chat box (typeInChat fires ADDON_ACTION_BLOCKED naming the addon and sends nothing), as the real one did.
-- items may also say classID, subclassID, type and sub (GetItemInfoInstant); tradeskill recipes may say
-- reagents = { { id, count } }.
-- Frames keep their state in underscore fields (_text, _shown, _checked, _scripts, _lines, _points ...), which
-- the tests read directly.

local FakeGame = {}

local POINTS = {
  TOPLEFT = { 0, 1 }, TOP = { 0.5, 1 }, TOPRIGHT = { 1, 1 },
  LEFT = { 0, 0.5 }, CENTER = { 0.5, 0.5 }, RIGHT = { 1, 0.5 },
  BOTTOMLEFT = { 0, 0 }, BOTTOM = { 0.5, 0 }, BOTTOMRIGHT = { 1, 0 },
}
FakeGame.POINTS = POINTS
FakeGame.STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
FakeGame.LAYERS = { BACKGROUND = 1, BORDER = 2, ARTWORK = 3, OVERLAY = 4, HIGHLIGHT = 5 }

-- Classic's class colours and the class circle's texture coordinates.
FakeGame.CLASS_COLORS = {
  WARRIOR = { r = 0.78, g = 0.61, b = 0.43 }, PALADIN = { r = 0.96, g = 0.55, b = 0.73 },
  HUNTER = { r = 0.67, g = 0.83, b = 0.45 }, ROGUE = { r = 1, g = 0.96, b = 0.41 },
  PRIEST = { r = 1, g = 1, b = 1 }, SHAMAN = { r = 0, g = 0.44, b = 0.87 },
  MAGE = { r = 0.25, g = 0.78, b = 0.92 }, WARLOCK = { r = 0.53, g = 0.53, b = 0.93 },
  DRUID = { r = 1, g = 0.49, b = 0.04 },
}
FakeGame.CLASS_ICON_TCOORDS = {
  WARRIOR = { 0, 0.25, 0, 0.25 }, MAGE = { 0.25, 0.49609375, 0, 0.25 }, ROGUE = { 0.49609375, 0.7421875, 0, 0.25 },
  DRUID = { 0.7421875, 0.98828125, 0, 0.25 }, HUNTER = { 0, 0.25, 0.25, 0.5 }, SHAMAN = { 0.25, 0.49609375, 0.25, 0.5 },
  PRIEST = { 0.49609375, 0.7421875, 0.25, 0.5 }, WARLOCK = { 0.7421875, 0.98828125, 0.25, 0.5 },
  PALADIN = { 0, 0.25, 0.5, 0.75 },
}
FakeGame.QUALITY_COLORS = {
  [0] = { r = 0.62, g = 0.62, b = 0.62 }, [1] = { r = 1, g = 1, b = 1 }, [2] = { r = 0.12, g = 1, b = 0 },
  [3] = { r = 0, g = 0.44, b = 0.87 }, [4] = { r = 0.64, g = 0.21, b = 0.93 }, [5] = { r = 1, g = 0.5, b = 0 },
}
local FONTS = { "GameFontNormal", "GameFontHighlight", "GameFontNormalSmall", "GameFontHighlightSmall",
  "GameFontDisableSmall", "GameFontNormalLarge", "GameFontHighlightLarge", "GameFontDisable", "ChatFontNormal",
  "NumberFontNormal" }

local function copy(t)
  local out = {}
  for k, v in pairs(t) do out[k] = type(v) == "table" and copy(v) or v end
  return out
end

local function hex(r, g, b)
  return string.format("|cff%02x%02x%02x", math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

function FakeGame.newClient(o)
  local name = o.name
  local client = { name = name, eventFrames = {}, chat = {}, online = true, textures = {}, frames = {}, updaters = {}, nextId = 0 }
  client.opts = o -- what it was made with (tests change bags and the like through it)
  local measure = o.measure or function(text) return #tostring(text or "") * 5, 12 end
  client.measure = measure
  local screen = o.screen or { w = 1440, h = 870 }
  client.screenW, client.screenH = screen.w, screen.h

  local function item(id)
    local it = o.items and o.items[tonumber(id) or 0]
    if type(it) == "string" then return { name = it, quality = 1 } end
    return it
  end
  local function spell(id)
    local s = o.spells and o.spells[tonumber(id) or 0]
    if type(s) == "string" then return { name = s } end
    return s
  end
  local function itemLink(id)
    local it = item(id)
    if not it then return nil end
    local c = FakeGame.QUALITY_COLORS[it.quality or 1] or FakeGame.QUALITY_COLORS[1]
    return hex(c.r, c.g, c.b) .. "|Hitem:" .. id .. "::::::::60:::::|h[" .. it.name .. "]|h|r"
  end
  client.itemLink = itemLink

  -- ------------------------------------------------------------- frames --
  local Frame = {}
  local noop = function() end
  -- a template's named pieces: nil unless the template made them (any other capitalised key is a method)
  local PIECES = { Text = true, TitleText = true, TitleBg = true, CloseButton = true, Inset = true, InsetBg = true,
    Instructions = true, Icon = true, IconBorder = true, Count = true, NineSlice = true, Left = true, Middle = true,
    Right = true, Bg = true }
  local mt = { __index = function(_, k)
    local m = Frame[k]
    if m ~= nil then return m end
    if type(k) == "string" and k:match("^[A-Z]") and not PIECES[k] then return noop end
  end }
  local env -- the addon's globals, below

  -- Is the code n levels up the stack the addon's own (one of its files)?
  local ADDON_FILES = { ["@Sync.lua"] = true, ["@Accent.lua"] = true, ["@FantasyForce.lua"] = true, ["@AccentChat.lua"] = true }
  client.taint = {}
  local function fromAddon(level)
    for l = level + 1, level + 3 do
      local info = debug.getinfo(l, "S")
      if not info then return false end
      if ADDON_FILES[info.source] then return true end
      if info.source ~= "=[C]" then return false end
    end
    return false
  end
  client.fromAddon = fromAddon
  local function taint(what) client.taint[#client.taint + 1] = what end
  -- the game's own frames: a field the addon writes onto one taints it
  local gameMt = { __index = mt.__index, __newindex = function(t, k, v)
    if type(k) == "string" and k:sub(1, 1) ~= "_" and fromAddon(2) then taint("a field (" .. k .. ") on " .. tostring(rawget(t, "_name") or "a game frame")) end
    rawset(t, k, v)
  end }
  local function gameFrame(f, chatBox)
    setmetatable(f, gameMt)
    if chatBox then rawset(f, "_chatBox", true) end
    return f
  end

  local function mock(kind, fname, parent, layer, sublevel)
    client.nextId = client.nextId + 1
    local f = setmetatable({ _kind = kind, _name = fname, _parent = parent, _scripts = {}, _shown = true, _text = "",
      _events = {}, _lines = {}, _id = client.nextId, _points = {}, _children = {}, _regions = {}, _alpha = 1,
      _layer = layer, _sublevel = sublevel or 0 }, mt)
    if parent and parent._children then
      if kind == "Texture" or kind == "FontString" then parent._regions[#parent._regions + 1] = f
      else parent._children[#parent._children + 1] = f end
    end
    client.frames[f._id] = f
    return f
  end
  client.mock = mock

  function Frame.IsVisible(f) return f._shown and (f._parent == nil or f._parent:IsVisible()) end
  function Frame.IsShown(f) return f._shown end
  function Frame.Show(f) local was = f._shown f._shown = true if not was and f._scripts.OnShow then f._scripts.OnShow(f) end end
  function Frame.Hide(f) local was = f._shown f._shown = false if was and f._scripts.OnHide then f._scripts.OnHide(f) end end
  function Frame.SetShown(f, on) if on then f:Show() else f:Hide() end end
  function Frame.GetName(f) return f._name end
  function Frame.GetParent(f) return f._parent end
  function Frame.GetObjectType(f) return f._kind end
  function Frame.IsObjectType(f, t) return f._kind == t end
  function Frame.GetAttribute(f, k) return f._attrs and f._attrs[k] end
  function Frame.SetAttribute(f, k, v) f._attrs = f._attrs or {} f._attrs[k] = v end
  function Frame.GetUnit(f) return f._unitName, f._unit end
  function Frame.SetID(f, id) f._idNum = id end
  function Frame.GetID(f) return f._idNum or 0 end

  -- scripts and events
  function Frame.SetScript(f, s, fn)
    f._scripts[s] = fn
    if s == "OnUpdate" then client.updaters[f] = fn end
  end
  function Frame.GetScript(f, s) return f._scripts[s] end
  function Frame.HasScript() return true end
  function Frame.HookScript(f, s, fn)
    local old = f._scripts[s]
    f:SetScript(s, old and function(...) old(...) fn(...) end or fn)
  end
  function Frame.RegisterEvent(f, ev) f._events[ev] = true client.eventFrames[#client.eventFrames + 1] = f end
  function Frame.UnregisterEvent(f, ev) f._events[ev] = nil end
  function Frame.IsEventRegistered(f, ev) return f._events[ev] and true or false end

  -- text
  function Frame.SetText(f, t, r, g, b)
    if f._kind == "GameTooltip" then
      f._text, f._lines, f._colors = tostring(t or ""), {}, {}
      f._textColor = r and { r, g, b } or nil
      return
    end
    if rawget(f, "_chatBox") and fromAddon(2) then taint("text put in the game's chat box") end
    f._text = t
    local fs = rawget(f, "Text")
    if fs and fs ~= f and (f._kind == "Button" or f._kind == "CheckButton") then fs:SetText(t) end
    if f._scripts.OnTextChanged then f._scripts.OnTextChanged(f, false) end
  end
  function Frame.Type(f, t) f._text = t if f._scripts.OnTextChanged then f._scripts.OnTextChanged(f, true) end end
  function Frame.GetText(f) return f._text end
  function Frame.SetFormattedText(f, fmt, ...) f:SetText(string.format(fmt, ...)) end
  local function fontName(fo)
    if type(fo) == "table" then return fo._font end
    if type(fo) == "string" then return fo end
  end
  function Frame.SetFontObject(f, fo) f._font = fontName(fo) or f._font end
  function Frame.GetFontObject(f) return env[f._font or ""] end
  function Frame.SetTextColor(f, r, g, b, a) f._color = { r, g, b, a or 1 } end
  function Frame.GetTextColor(f) local c = f._color or { 1, 1, 1, 1 } return c[1], c[2], c[3], c[4] end
  function Frame.SetJustifyH(f, j) f._justifyH = j end
  function Frame.SetJustifyV(f, j) f._justifyV = j end
  function Frame.SetWordWrap(f, on) f._wrap = on and true or false end
  function Frame.SetSpacing(f, s) f._spacing = s end
  function Frame.GetStringWidth(f) return (measure(f._text or "", f._font, nil, f._spacing)) end
  function Frame.GetStringHeight(f) local _, h = measure(f._text or "", f._font, nil, f._spacing) return h end
  function Frame.GetFontString(f) return rawget(f, "Text") or f end
  function Frame.GetTextWidth(f) local fs = rawget(f, "Text") or f return (measure(fs._text or "", fs._font, nil)) end

  -- regions
  function Frame.CreateTexture(f, _, layer, _, sublevel) return mock("Texture", nil, f, layer or "ARTWORK", sublevel) end
  function Frame.CreateFontString(f, _, layer, inherits)
    local fs = mock("FontString", nil, f, layer or "ARTWORK")
    fs._font = fontName(inherits) or "GameFontNormal"
    return fs
  end
  function Frame.SetTexture(f, path, g, b, a)
    if type(path) == "number" and type(g) == "number" then
      f._colorTex, f._texture = { path, g, b, a or 1 }, nil
      return
    end
    f._texture, f._colorTex = path, nil
    if type(path) == "string" then client.textures[path] = (client.textures[path] or 0) + 1 end
  end
  function Frame.GetTexture(f) return f._texture end
  function Frame.SetColorTexture(f, r, g, b, a) f._colorTex, f._texture = { r, g, b, a or 1 }, nil end
  function Frame.SetTexCoord(f, ...) f._texCoord = { ... } end
  function Frame.SetVertexColor(f, r, g, b, a) f._vertex = { r, g, b, a or 1 } end
  function Frame.SetDesaturated(f, on) f._desaturated = on and true or false end
  function Frame.SetBlendMode(f, mode) f._blend = mode end
  function Frame.SetDrawLayer(f, layer, sub) f._layer, f._sublevel = layer, sub or 0 end
  function Frame.SetAlpha(f, a) f._alpha = a end
  function Frame.GetAlpha(f) return f._alpha end

  -- anchors and sizes
  local function relFrame(f, rel)
    if type(rel) == "string" then return env[rel] end
    return rel
  end
  function Frame.SetPoint(f, point, a, b, c, d)
    point = tostring(point or "CENTER"):upper()
    local rel, relPoint, x, y
    if a == nil or type(a) == "number" then
      rel, relPoint, x, y = nil, point, a, b
    elseif type(b) == "number" then
      rel, relPoint, x, y = relFrame(f, a), point, b, c
    else
      rel, relPoint, x, y = relFrame(f, a), b and tostring(b):upper() or point, c, d
    end
    if not POINTS[point] then error("bad anchor point " .. point, 2) end
    for i, p in ipairs(f._points) do
      if p.point == point then table.remove(f._points, i) break end
    end
    f._points[#f._points + 1] = { point = point, rel = rel, relPoint = POINTS[relPoint] and relPoint or point, x = x or 0, y = y or 0 }
  end
  function Frame.ClearAllPoints(f) f._points = {} end
  function Frame.SetAllPoints(f, rel)
    rel = relFrame(f, rel)
    f._points = {}
    f:SetPoint("TOPLEFT", rel or f._parent, "TOPLEFT", 0, 0)
    f:SetPoint("BOTTOMRIGHT", rel or f._parent, "BOTTOMRIGHT", 0, 0)
  end
  function Frame.GetNumPoints(f) return #f._points end
  function Frame.GetPoint(f, i)
    local p = f._points[i or 1]
    if not p then return nil end
    return p.point, p.rel, p.relPoint, p.x, p.y
  end
  function Frame.SetSize(f, w, h) f._w, f._h = w, h or w end
  function Frame.SetWidth(f, w) f._w = w end
  function Frame.SetHeight(f, h) f._h = h end
  function Frame.GetWidth(f) local _, _, w = FakeGame.rect(client, f) return w or f._w or 0 end
  function Frame.GetHeight(f) local _, _, _, h = FakeGame.rect(client, f) return h or f._h or 0 end
  function Frame.GetSize(f) return f:GetWidth(), f:GetHeight() end
  function Frame.GetLeft(f) local l = FakeGame.rect(client, f) return l end
  function Frame.GetBottom(f) local _, b = FakeGame.rect(client, f) return b end
  function Frame.GetRight(f) local l, _, w = FakeGame.rect(client, f) return l and l + w end
  function Frame.GetTop(f) local _, b, _, h = FakeGame.rect(client, f) return b and b + h end
  function Frame.GetCenter(f)
    local l, b, w, h = FakeGame.rect(client, f)
    if not l then return nil end
    return l + w / 2, b + h / 2
  end
  function Frame.GetRect(f) return FakeGame.rect(client, f) end
  function Frame.GetEffectiveScale() return 1 end
  function Frame.GetScale() return 1 end

  -- strata and levels
  function Frame.SetFrameStrata(f, s) f._strata = s end
  function Frame.GetFrameStrata(f) return FakeGame.strata(f) end
  function Frame.SetFrameLevel(f, l) f._level = l end
  function Frame.GetFrameLevel(f) return FakeGame.level(f) end

  -- mouse, moving
  function Frame.EnableMouse(f, on) f._mouse = on and true or false end
  function Frame.IsMouseEnabled(f) return f._mouse or false end
  function Frame.EnableMouseWheel(f, on) f._wheel = on and true or false end
  function Frame.RegisterForDrag(f, ...) f._drag = select("#", ...) > 0 end
  function Frame.RegisterForClicks(f, ...) f._clicks = { ... } end
  function Frame.SetMovable(f, on) f._movable = on and true or false end
  function Frame.IsMovable(f) return f._movable or false end
  function Frame.SetClampedToScreen(f, on) f._clamped = on and true or false end
  function Frame.StartMoving(f)
    local l, b, _, h = FakeGame.rect(client, f)
    if not l then return end
    f._points = {}
    f:SetPoint("TOPLEFT", env.UIParent, "BOTTOMLEFT", l, b + h)
    f._moving = true
  end
  function Frame.StopMovingOrSizing(f) f._moving = false end

  -- check buttons, buttons
  function Frame.SetChecked(f, v) f._checked = v and true or false end
  function Frame.GetChecked(f) return f._checked end
  function Frame.Enable(f) f._disabled = false end
  function Frame.Disable(f) f._disabled = true end
  function Frame.SetEnabled(f, on) f._disabled = not on end
  function Frame.IsEnabled(f) return not f._disabled end
  function Frame.Click(f, button) FakeGame.click(client, f, button) end
  local function buttonTexture(f, key, path, layer, blend)
    local t = f[key]
    if not t then
      t = mock("Texture", nil, f, layer)
      t:SetAllPoints(f)
      f[key] = t
    end
    t:SetTexture(path)
    if blend then t._blend = blend end
    return t
  end
  function Frame.SetNormalTexture(f, path) buttonTexture(f, "_normalTex", path, "ARTWORK") end
  function Frame.SetPushedTexture(f, path) buttonTexture(f, "_pushedTex", path, "ARTWORK")._pushedOnly = true end
  function Frame.SetHighlightTexture(f, path, blend) buttonTexture(f, "_highlightTex", path, "HIGHLIGHT", blend or "ADD") end
  function Frame.SetCheckedTexture(f, path) buttonTexture(f, "_checkedTex", path, "OVERLAY")._checkedOnly = true end
  function Frame.SetDisabledTexture(f, path) buttonTexture(f, "_disabledTex", path, "ARTWORK")._disabledOnly = true end
  function Frame.GetNormalTexture(f) return f._normalTex end
  function Frame.LockHighlight(f) f._lockHighlight = true end
  function Frame.UnlockHighlight(f) f._lockHighlight = false end
  function Frame.SetHitRectInsets(f, l, r, t, b) f._hitInsets = { l or 0, r or 0, t or 0, b or 0 } end
  function Frame.GetHighlightTexture(f) return f._highlightTex end

  -- edit boxes
  function Frame.SetAutoFocus(f, on) f._autoFocus = on and true or false end
  function Frame.SetTextInsets(f, l, r, t, b) f._textInsets = { l or 0, r or 0, t or 0, b or 0 } end
  function Frame.GetTextInsets(f) local i = f._textInsets or { 0, 0, 0, 0 } return i[1], i[2], i[3], i[4] end
  function Frame.SetFocus(f)
    if client.focus == f then return end
    if client.focus then client.focus:ClearFocus() end
    client.focus = f
    if f._scripts.OnEditFocusGained then f._scripts.OnEditFocusGained(f) end
  end
  function Frame.ClearFocus(f)
    if client.focus ~= f then return end
    client.focus = nil
    if f._scripts.OnEditFocusLost then f._scripts.OnEditFocusLost(f) end
  end
  function Frame.HasFocus(f) return client.focus == f end
  function Frame.EnableKeyboard(f, on) f._keyboard = on and true or false end
  function Frame.SetPropagateKeyboardInput(f, on)
    if client.combat and fromAddon(2) then error("SetPropagateKeyboardInput is blocked in combat", 2) end
    f._propagate = on and true or false
  end
  function Frame.Insert(f, text) f:SetText((f._text or "") .. tostring(text or "")) end
  function Frame.HighlightText(f) f._highlighted = true end
  function Frame.SetCursorPosition(f, p) f._cursor = p end
  function Frame.SetMaxLetters(f, n) f._maxLetters = n end
  function Frame.GetMaxLetters(f) return f._maxLetters or 0 end
  function Frame.Insert(f, t) f:Type((f._text or "") .. tostring(t)) end

  -- sliders
  function Frame.SetMinMaxValues(f, a, b) f._min, f._max = a, b end
  function Frame.GetMinMaxValues(f) return f._min or 0, f._max or 0 end
  function Frame.SetValue(f, v)
    if v ~= f._value then
      f._value = v
      if f._scripts.OnValueChanged then f._scripts.OnValueChanged(f, v) end
    end
  end
  function Frame.GetValue(f) return f._value or 0 end
  function Frame.SetValueStep(f, s) f._step = s end
  function Frame.SetOrientation(f, o2) f._orientation = o2 end
  function Frame.SetThumbTexture(f, path)
    if not f._thumb then
      f._thumb = mock("Texture", nil, f, "OVERLAY")
      f._thumb._isThumb = true
      f._thumb:SetSize(18, 24)
    end
    f._thumb:SetTexture(path)
  end
  function Frame.GetThumbTexture(f) return f._thumb end

  -- backdrops
  function Frame.SetBackdrop(f, b) f._backdrop = b end
  function Frame.SetBackdropColor(f, r, g, b, a) f._backdropColor = { r, g, b, a or 1 } end
  function Frame.SetBackdropBorderColor(f, r, g, b, a) f._backdropBorder = { r, g, b, a or 1 } end

  -- tooltips (GameTooltip)
  function Frame.SetOwner(f, owner, anchor) f._lines, f._colors, f._text, f._owner, f._anchor = {}, {}, "", owner, anchor end
  function Frame.AddLine(f, text, r, g, b, wrap)
    f._lines[#f._lines + 1] = text
    f._colors = f._colors or {}
    f._colors[#f._lines] = { r or 1, g or 0.82, b or 0, wrap and true or false }
  end
  function Frame.AddDoubleLine(f, left, right, r, g, b) f:AddLine(tostring(left) .. "  " .. tostring(right), r, g, b) end
  function Frame.NumLines(f) return #f._lines + ((f._text or "") ~= "" and 1 or 0) end
  function Frame.ClearLines(f) f._lines, f._colors, f._text = {}, {}, "" end
  function Frame.SetItemByID(f, id)
    local it = item(id)
    f._text = it and it.name or ("item " .. id)
    local c = FakeGame.QUALITY_COLORS[it and it.quality or 1]
    f._textColor = { c.r, c.g, c.b }
    f._lines, f._colors = {}, {}
  end
  function Frame.SetHyperlink(f, link)
    local kind, id = tostring(link):match("(%a+):(%d+)")
    if kind == "item" then return f:SetItemByID(tonumber(id)) end
    if kind == "spell" then return f:SetSpellByID(tonumber(id)) end
    error("unknown link " .. tostring(link))
  end
  function Frame.SetSpellByID(f, id)
    local s = spell(id)
    if not s then error("unknown spell " .. tostring(id)) end
    f._text, f._textColor, f._lines, f._colors = s.name, { 1, 1, 1 }, {}, {}
  end

  -- ----------------------------------------------------------- templates --
  local function fontString(parent, font, layer)
    local fs = mock("FontString", nil, parent, layer or "OVERLAY")
    fs._font = font
    return fs
  end
  local TEMPLATES = {}
  function TEMPLATES.BasicFrameTemplateWithInset(f)
    f.CloseButton = env.CreateFrame("Button", nil, f, "UIPanelCloseButton")
    f.CloseButton:SetPoint("TOPRIGHT", f, "TOPRIGHT", 2, 1)
    f.TitleBg = mock("Texture", nil, f, "BACKGROUND")
    f.TitleText = fontString(f, "GameFontNormal")
    f.TitleText:SetPoint("TOP", f, "TOP", 0, -5)
    f.Inset = mock("Frame", nil, f)
    f.Inset._template = "Inset"
    f.Inset:SetPoint("TOPLEFT", f, "TOPLEFT", 4, -24)
    f.Inset:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -6, 4)
  end
  function TEMPLATES.UIPanelCloseButton(f)
    f:SetSize(24, 24)
    f:SetScript("OnClick", function(self) if self._parent then self._parent:Hide() end end)
  end
  function TEMPLATES.UIPanelButtonTemplate(f)
    f:SetSize(80, 22)
    f._font = "GameFontNormal"
    f.Text = fontString(f, "GameFontNormal")
    f.Text:SetPoint("CENTER", f, "CENTER", 0, 0)
  end
  function TEMPLATES.UICheckButtonTemplate(f)
    f:SetSize(32, 32)
    f.Text = fontString(f, "GameFontNormalSmall")
    f.Text:SetPoint("LEFT", f, "RIGHT", -2, 0)
    f.text = f.Text
  end
  function TEMPLATES.PanelTabButtonTemplate(f)
    f:SetSize(80, 32)
    f._font = "GameFontNormalSmall"
    f.Text = fontString(f, "GameFontNormalSmall")
    f.Text:SetPoint("CENTER", f, "CENTER", 0, 2)
  end
  function TEMPLATES.UIRadioButtonTemplate(f)
    f:SetSize(16, 16)
    f.text = fontString(f, "GameFontNormalSmall")
    f.text:SetPoint("LEFT", f, "RIGHT", 5, 0)
  end
  TEMPLATES.CharacterFrameTabButtonTemplate = TEMPLATES.PanelTabButtonTemplate
  function TEMPLATES.InputBoxTemplate(f)
    f:SetHeight(20)
    f._font = "ChatFontNormal"
  end
  function TEMPLATES.SearchBoxTemplate(f)
    f:SetHeight(20)
    f._font = "ChatFontNormal"
    f.Instructions = fontString(f, "GameFontDisableSmall")
    f.Instructions:SetText("Search")
    f.Instructions._isInstructions = true
  end
  function TEMPLATES.BackdropTemplate() end
  -- the Who list's column header, its label 8 in (the preview draws its tab art from the template name)
  function TEMPLATES.WhoFrameColumnHeaderTemplate(f)
    f:SetSize(10, 24)
    f._font = "GameFontHighlightSmall"
    f.Text = fontString(f, "GameFontHighlightSmall")
    f.Text:SetPoint("LEFT", f, "LEFT", 8, 0)
  end
  TEMPLATES.GuildFrameColumnHeaderTemplate = TEMPLATES.WhoFrameColumnHeaderTemplate
  -- a bag slot: its icon, its stack count, and a quality border shown for green and up
  function TEMPLATES.ItemButtonTemplate(f)
    f:SetSize(37, 37)
    f.icon = f:CreateTexture(nil, "BORDER")
    f.icon:SetAllPoints()
    f.Icon = f.icon
    f.Count = fontString(f, "NumberFontNormal")
    f.Count:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -5, 2)
    f.Count:Hide()
    f.IconBorder = f:CreateTexture(nil, "OVERLAY")
    f.IconBorder:SetAllPoints()
    f.IconBorder:SetTexture("Interface\\Common\\WhiteIconFrame")
    f.IconBorder:Hide()
    local hl = f:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hl:SetBlendMode("ADD")
  end

  -- ---------------------------------------------------------------- env --
  local store = {}
  local function own(k)
    return type(k) == "string" and (k:match("^FantasyForce") or k:match("^SLASH_FANTASYFORCE") or k:match("^BINDING_%u+_FANTASYFORCE")) and true or false
  end
  env = setmetatable({}, {
    __index = function(_, k)
      local v = store[k]
      if v == nil then v = _G[k] end
      return v
    end,
    __newindex = function(_, k, v)
      if store[k] ~= nil and not own(k) and fromAddon(2) then taint("the game's global " .. tostring(k)) end
      store[k] = v
    end,
  })
  client.env = env
  env._G = env
  env.pcall = o.pcall or pcall
  env.time = o.time or os.time
  env.GetTime = o.now or os.clock
  env.date = o.date or function() return "2026-11-08 12:00" end
  env.C_Timer = { After = function(sec, fn) o.after(sec, fn) end, NewTicker = o.ticker }
  env.unpack = env.unpack or table.unpack
  for _, f in ipairs(FONTS) do env[f] = { _font = f } end

  env.CreateFrame = function(kind, fname, parent, template)
    local f = mock(kind, fname, parent)
    f._template = template
    if kind == "Button" or kind == "CheckButton" then f._font = "GameFontNormal" end
    if kind == "EditBox" then f._font = "ChatFontNormal" f._autoFocus = true end
    for t in tostring(template or ""):gmatch("[^,%s]+") do
      local build = TEMPLATES[t]
      -- like the game: a template this client doesn't have is an error
      if not build or (o.missingTemplates and o.missingTemplates[t]) then error("Couldn't find inherited node \"" .. t .. "\"", 2) end
      build(f)
    end
    if fname then env[fname] = f end
    return f
  end

  env.UIParent = gameFrame(mock("Frame", "UIParent"))
  client.root = env.UIParent
  env.UIParent._strata = "MEDIUM"
  env.UIParent._level = 0
  local mm = o.minimap or { x = 96, y = 112, size = 140 }
  env.Minimap = gameFrame(mock("Frame", "Minimap", env.UIParent))
  env.Minimap:SetSize(mm.size, mm.size)
  env.Minimap:SetPoint("CENTER", env.UIParent, "TOPRIGHT", -mm.x, -mm.y)
  env.Minimap._strata, env.Minimap._level = "LOW", 2
  env.UISpecialFrames = {}
  client.tooltip = gameFrame(mock("GameTooltip", "GameTooltip", env.UIParent))
  client.tooltip._shown = false
  client.tooltip._strata = "TOOLTIP"
  env.GameTooltip = client.tooltip
  env.DEFAULT_CHAT_FRAME = { AddMessage = function(_, m, r, g, b)
    client.chat[#client.chat + 1] = m
    if o.onChat then o.onChat(m, r, g, b) end
  end }
  env.SlashCmdList = {}
  env.InCombatLockdown = function() return client.combat and true or false end
  env.NUM_CHAT_WINDOWS = 1
  env.ChatTypeInfo = { SAY = { r = 1, g = 1, b = 1 }, YELL = { r = 1, g = 0.25, b = 0.25 }, GUILD = { r = 0.25, g = 1, b = 0.25 },
    OFFICER = { r = 0.25, g = 0.75, b = 0.25 }, PARTY = { r = 0.67, g = 0.67, b = 1 }, RAID = { r = 1, g = 0.5, b = 0 },
    WHISPER = { r = 1, g = 0.5, b = 1 }, CHANNEL = { r = 1, g = 0.75, b = 0.75 } }
  -- the first chat window, where the preview draws its chat log, and its tab
  env.ChatFrame1 = gameFrame(mock("Frame", "ChatFrame1", env.UIParent))
  env.ChatFrame1:SetSize(440, 190)
  env.ChatFrame1:SetPoint("BOTTOMLEFT", env.UIParent, "BOTTOMLEFT", 18, 64)
  env.ChatFrame1Tab = gameFrame(mock("Button", "ChatFrame1Tab", env.UIParent))
  env.ChatFrame1Tab:SetSize(64, 20)
  env.ChatFrame1Tab:SetPoint("BOTTOMLEFT", env.ChatFrame1, "TOPLEFT", 0, 2)
  local tabText = env.ChatFrame1Tab:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  tabText:SetPoint("CENTER", env.ChatFrame1Tab, "CENTER", 0, 0)
  tabText:SetText("General")
  env.GetCursorPosition = function()
    if o.cursor then return o.cursor() end
    return 100, 300
  end
  env.ReloadUI = function()
    client.reloaded = true
    if o.reload then o.reload() end
  end
  env.CLASS_ICON_TCOORDS = copy(FakeGame.CLASS_ICON_TCOORDS)
  env.RAID_CLASS_COLORS = copy(FakeGame.CLASS_COLORS)
  env.ITEM_QUALITY_COLORS = copy(FakeGame.QUALITY_COLORS)
  env.GetCoinTextureString = function(m)
    m = math.floor(tonumber(m) or 0)
    local g, s, c = math.floor(m / 10000), math.floor(m / 100) % 100, m % 100
    local parts = {}
    if g > 0 then parts[#parts + 1] = g .. "|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t" end
    if s > 0 then parts[#parts + 1] = s .. "|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t" end
    if c > 0 or #parts == 0 then parts[#parts + 1] = c .. "|TInterface\\MoneyFrame\\UI-CopperIcon:0:0:2:0|t" end
    return table.concat(parts, " ")
  end

  -- tabs (Blizzard's PanelTemplates)
  env.PanelTemplates_TabResize = function(tab, padding)
    local fs = tab.Text or tab
    tab._w = math.max(60, (measure(fs._text or "", fs._font)) + 32 + (padding or 0))
  end
  env.PanelTemplates_SetNumTabs = function(frame, n) frame.numTabs = n end
  env.PanelTemplates_SetTab = function(frame, id)
    frame.selectedTab = id
    local tabs = frame.Tabs
    if not tabs then
      tabs = {}
      for i = 1, frame.numTabs or 0 do tabs[i] = env[(frame:GetName() or "") .. "Tab" .. i] end
    end
    for i, tab in ipairs(tabs) do
      tab._selected = i == id
      -- the picked tab's label turns white, the others stay gold
      if tab.Text then tab.Text._font = i == id and "GameFontHighlightSmall" or "GameFontNormalSmall" end
    end
  end

  -- the player, the guild
  local race = o.race or { "Human", "Human" }
  env.UnitName = function(unit) if unit == nil or unit == "player" then return name end return client.hoverName end
  env.UnitIsPlayer = function() return true end
  env.UnitFullName = function() return name, "Realm" end
  env.UnitLevel = function() return o.level or 60 end
  env.UnitClass = function() return o.className or o.class, o.class end
  env.UnitRace = function() return race[1], race[2] end
  env.UnitFactionGroup = function() return o.faction or "Alliance" end
  local guild = o.guild == nil and "Fantasy Force" or o.guild
  env.IsInGuild = function() return guild ~= "" end
  env.GetGuildInfo = function()
    if guild == "" then return nil end
    return guild, o.rankName or "Raider", o.rankIndex or 3
  end
  env.CanEditOfficerNote = function() return guild ~= "" and (o.rankIndex or 3) <= 1 end
  local function roster() return o.roster and o.roster() or {} end
  env.GetNumGuildMembers = function() return #roster() end
  env.GetGuildRosterInfo = function(i)
    local m = roster()[i]
    if not m then return nil end
    return m.name .. "-Realm", m.rank or "Raider", m.rankIndex or 3, m.level or 60, m.class, m.zone or "Orgrimmar",
      m.note or "", "", m.online and true or false, 0, m.class
  end
  env.GetProfessions = function()
    if not o.profs then return nil end
    local idx = {}
    for i = 1, math.min(#o.profs, 2) do idx[i] = i end
    return table.unpack(idx)
  end
  env.GetProfessionInfo = function(i) local p = o.profs and o.profs[i] if p then return p.name, 0, p.skill, p.max end end
  env.GetMoney = function() return o.money or 5000000 end
  env.C_Container = {
    GetContainerNumSlots = function(bag) local b = o.bags and o.bags[bag] return b and #b or 0 end,
    GetContainerItemInfo = function(bag, slot)
      local s = o.bags and o.bags[bag] and o.bags[bag][slot]
      if not s then return nil end
      return { hyperlink = itemLink(s.id) or ("|cffffffff|Hitem:" .. s.id .. "::::|h[x]|h|r"), stackCount = s.count, itemID = s.id }
    end,
  }
  env.C_ChatInfo = {
    RegisterAddonMessagePrefix = function() return true end,
    SendAddonMessage = function(prefix, msg, chan)
      if o.sendAddon then return o.sendAddon(prefix, msg, chan) end
      return 0
    end,
    SendChatMessage = (not o.noSendChat) and function(msg, chatType, lang, target)
      client.said = client.said or {}
      client.said[#client.said + 1] = { msg = msg, chatType = chatType, target = target }
      if o.onSend then o.onSend(msg, chatType, lang, target) end
    end or nil,
  }
  env.C_Item = {
    GetItemNameByID = function(id) local it = item(id) return it and it.name end,
    GetItemIconByID = function(id) local it = item(id) return it and it.icon or 134400 end,
    GetItemQualityByID = function(id) local it = item(id) return it and it.quality end,
    GetItemInfo = function(id)
      local it = item(id)
      if it then return it.name, itemLink(id), it.quality or 1 end
    end,
    RequestLoadItemDataByID = function() end,
    -- id, type, subtype, equip slot, icon, class id, subclass id (items say classID and sub)
    GetItemInfoInstant = function(id)
      local it = item(id)
      if not it then return nil end
      return tonumber(id), it.type or "", it.sub or "", "", it.icon or 134400, it.classID, it.subclassID
    end,
  }
  env.GetItemInfoInstant = env.C_Item.GetItemInfoInstant
  env.LOCALIZED_CLASS_NAMES_MALE = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue",
    PRIEST = "Priest", SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" }
  env.TOOLTIP_DEFAULT_BACKGROUND_COLOR = { r = 0, g = 0, b = 0 }
  env.WhoFrameColumn_SetWidth = function(f, width)
    f:SetWidth(width)
    local mid = f._name and env[f._name .. "Middle"]
    if mid then mid:SetWidth(width - 9) end
  end
  env.SetItemButtonTexture = function(b, tex) b.icon:SetTexture(tex) b.icon:Show() end
  env.SetItemButtonCount = function(b, n)
    n = tonumber(n) or 0
    b.Count:SetText(n > 1 and tostring(n) or "")
    if n > 1 then b.Count:Show() else b.Count:Hide() end
  end
  env.SetItemButtonQuality = function(b, q)
    local c = type(q) == "number" and q >= 2 and FakeGame.QUALITY_COLORS[q]
    if c then
      b.IconBorder:SetVertexColor(c.r, c.g, c.b)
      b.IconBorder:Show()
    else
      b.IconBorder:Hide()
    end
  end
  env.C_Spell = {
    GetSpellName = function(id) local s = spell(id) return s and s.name end,
    GetSpellTexture = function(id) local s = spell(id) return s and (s.icon or 136240) or nil end,
    GetSpellLink = function(id)
      local s = spell(id)
      return "|cff71d5ff|Hspell:" .. id .. "|h[" .. (s and s.name or "x") .. "]|h|r"
    end,
  }
  env.ChatFrame_OpenChat = function(text)
    client.opened = text
    if o.openChat then o.openChat(text) end
  end
  env.ChatEdit_InsertLink = function(link)
    client.linked = link
    if o.insertLink then return o.insertLink(link) end
    return true
  end
  env.IsShiftKeyDown = function() return client.shift end
  if o.tradeskill then
    local ts = o.tradeskill
    env.GetTradeSkillLine = function() return ts.prof end
    env.GetNumTradeSkills = function() return #ts.list end
    env.GetTradeSkillInfo = function(i) return ts.list[i].name, "optimal" end
    env.GetTradeSkillRecipeLink = function(i) return "|cffffd000|Henchant:" .. ts.list[i].id .. "|h[x]|h|r" end
    env.GetTradeSkillItemLink = function(i) local it = ts.list[i].item return it and ("|cffffffff|Hitem:" .. it .. "::::|h[x]|h|r") or nil end
    -- reagents = { { id, count } } on a recipe
    env.GetTradeSkillNumReagents = function(i) return #(ts.list[i].reagents or {}) end
    env.GetTradeSkillReagentInfo = function(i, j)
      local r = ts.list[i].reagents[j]
      local it = item(r.id)
      return it and it.name or nil, it and it.icon or nil, r.count, 0
    end
    env.GetTradeSkillReagentItemLink = function(i, j) return itemLink(ts.list[i].reagents[j].id) end
  end
  env.FantasyForceDB = o.db
  env.FantasyForceCharDB = o.charDB

  -- chat filters, unit tooltips, the chat box and the mail window
  client.filters = {}
  env.ChatFrame_AddMessageEventFilter = function(ev, fn) client.filters[ev] = fn end
  env.Enum = { TooltipDataType = { Unit = 2 } }
  env.TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn) if kind == 2 then client.ttPost = fn end end }
  client.hooks = {}
  env.hooksecurefunc = function(a, b, c)
    local tbl, key, fn
    if type(a) == "string" then tbl, key, fn = env, a, b else tbl, key, fn = a, b, c end
    client.hooks[#client.hooks + 1] = key
    if fromAddon(2) and (key == "ParseText" or tostring(key):match("^ChatEdit_") or tbl == env.ChatFrameUtil
      or (type(tbl) == "table" and rawget(tbl, "_chatBox"))) then
      taint("a hook on the chat box (" .. tostring(key) .. ")")
    end
    local orig = tbl[key]
    tbl[key] = function(...)
      local r = table.pack(orig(...))
      fn(...)
      return table.unpack(r, 1, r.n)
    end
  end
  -- the chat box's parse: slash commands run (and empty the box) when Enter is pressed
  local function parse(box, send)
    if send == 1 and type(box) == "table" and FakeGame.runSlash(client, box._text or "", box) then box._text = "" end
  end
  local chatKind = o.noParse and "send" or o.chat or "global"
  client.chatKind = chatKind
  if chatKind ~= "send" then env.ChatEdit_ParseText = parse end
  env.SendMailFrame = mock("Frame", "SendMailFrame")
  env.SendMailBodyEditBox = mock("EditBox", "SendMailBodyEditBox")
  env.SendMailSubjectEditBox = mock("EditBox", "SendMailSubjectEditBox")
  env.SendMailScrollFrame = mock("Frame", "SendMailScrollFrame")
  client.editBox = function(text, chatType, attrs)
    local e = gameFrame(mock("EditBox"), true)
    e._text = text
    e._attrs = attrs or {}
    e._attrs.chatType = chatType
    return e
  end
  client.chatBox = client.editBox("", "SAY")
  client.chatBox._name = "ChatFrame1EditBox"
  env.ChatFrame1EditBox = client.chatBox
  if chatKind == "mixin" then rawset(client.chatBox, "ParseText", function(self, send) parse(self, send) end) end

  client.gameFns = { ["C_ChatInfo.SendChatMessage"] = env.C_ChatInfo.SendChatMessage, SendChatMessage = env.SendChatMessage,
    ChatEdit_ParseText = env.ChatEdit_ParseText, ["ChatFrame1EditBox:ParseText"] = rawget(client.chatBox, "ParseText") }
  local ns = {}
  for _, s in ipairs(o.sources or {}) do
    assert(load(s.src, "@" .. s.name, "t", env))("FantasyForce", ns)
  end
  client.ns = ns

  function client.fire(event, ...)
    for _, f in ipairs(client.eventFrames) do
      if f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
    end
  end
  function client.slash(msg) env.SlashCmdList.FANTASYFORCE(msg) end
  client.db = function() return env.FantasyForceDB end
  client.window = function(key) return env["FantasyForce" .. key .. "Window"] end
  return client
end

-- ---------------------------------------------------------------- layout --
-- Where a frame or region is, as the game would place it: left, bottom, width, height in UI units from the
-- screen's bottom-left corner, or nil when it has no anchors (the game draws nothing then).

local function strata(f)
  while f do
    if f._strata then return f._strata end
    f = f._parent
  end
  return "MEDIUM"
end
FakeGame.strata = strata

local function level(f)
  if f._level then return f._level end
  if f._parent then return level(f._parent) + 1 end
  return 0
end
FakeGame.level = level

local function resolve(client, f, depth)
  if f == client.root then return 0, 0, client.screenW, client.screenH end
  local memo = client.memo
  if memo then
    local r = memo[f]
    if r == false then return nil end
    if r then return r[1], r[2], r[3], r[4] end
  end
  if depth > 50 then return nil end
  local l, b, w, h
  if f._isThumb then
    -- a slider's thumb: centred across the slider, along it by the value
    local sl, sb, sw, sh = resolve(client, f._parent, depth + 1)
    if sl then
      local p = f._parent
      local min, max = p._min or 0, p._max or 0
      local frac = max > min and ((p._value or 0) - min) / (max - min) or 0
      w, h = f._w or 18, f._h or 24
      l = sl + (sw - w) / 2
      b = sb + sh - h - frac * (sh - h)
    end
  else
    local xs, ys = {}, {}
    for _, p in ipairs(f._points) do
      local rel = p.rel or f._parent or client.root
      local rl, rb, rw, rh = resolve(client, rel, depth + 1)
      if rl then
        local rp, op = POINTS[p.relPoint], POINTS[p.point]
        xs[#xs + 1] = { op[1], rl + rp[1] * rw + p.x }
        ys[#ys + 1] = { op[2], rb + rp[2] * rh + p.y }
      end
    end
    if #xs > 0 then
      local isText = f._kind == "FontString"
      -- Two opposite edges set the size; an edge and a centre only when no size is set (TOPLEFT plus RIGHT
      -- with SetHeight keeps the height). Unverified against the game for that last case.
      local function axis(list, explicit, intrinsic)
        local lo, hi, other
        for _, c in ipairs(list) do
          if c[1] == 0 then lo = lo or c elseif c[1] == 1 then hi = hi or c else other = other or c end
        end
        if lo and hi then return lo[2], hi[2] - lo[2] end
        local a = lo or hi or other
        if not explicit then
          for _, c in ipairs(list) do
            if c[1] ~= a[1] then
              local size = (c[2] - a[2]) / (c[1] - a[1])
              return a[2] - a[1] * size, size
            end
          end
        end
        local size = explicit or intrinsic() or 0
        return a[2] - a[1] * size, size
      end
      l, w = axis(xs, f._w, function()
        if isText then return (client.measure(f._text or "", f._font, nil, f._spacing)) end
      end)
      b, h = axis(ys, f._h, function()
        if isText then
          local wrapW = (f._w or w) and w or nil
          local _, th = client.measure(f._text or "", f._font, wrapW, f._spacing)
          return th
        end
      end)
    end
  end
  if memo then memo[f] = l and { l, b, w, h } or false end
  if not l then return nil end
  return l, b, w, h
end

function FakeGame.rect(client, f)
  return resolve(client, f, 0)
end

-- ----------------------------------------------------------------- input --

-- A click as the game does it: a check button flips first, then OnClick runs.
function FakeGame.click(client, f, button)
  if f._disabled then return end
  if f._kind == "CheckButton" then f._checked = not f._checked end
  local s = f._scripts.OnClick
  if s then s(f, button or "LeftButton", false) end
end

-- Escape: the game hides the shown frames named in UISpecialFrames.
function FakeGame.pressEscape(client)
  local closed = false
  -- a shown frame taking keys (OnKeyDown) gets Escape first; one that stops it propagating keeps it
  for id = client.nextId, 1, -1 do
    local f = client.frames[id]
    if f and f._keyboard and f._scripts.OnKeyDown and f:IsVisible() then
      f._scripts.OnKeyDown(f, "ESCAPE")
      closed = true
      if f._propagate == false then return true end
    end
  end
  for _, n in ipairs(client.env.UISpecialFrames) do
    local f = client.env[n]
    if type(f) == "table" and f.IsShown and f:IsShown() then
      f:Hide()
      closed = true
    end
  end
  return closed
end

-- Runs a typed slash command (/ff status) through SlashCmdList, as the chat box does; false when unknown.
function FakeGame.runSlash(client, text, box)
  local cmd, rest = tostring(text):match("^(/%S+)%s*(.-)%s*$")
  if not cmd then return false end
  cmd = cmd:lower()
  local env = client.env
  for key, fn in pairs(env.SlashCmdList) do
    for i = 1, 9 do
      local s = env["SLASH_" .. key .. i]
      if not s then break end
      if s:lower() == cmd then
        fn(rest, box)
        return true
      end
    end
  end
  return false
end

local CHAT_SWITCH = { ["/s"] = "SAY", ["/say"] = "SAY", ["/y"] = "YELL", ["/yell"] = "YELL", ["/g"] = "GUILD",
  ["/guild"] = "GUILD", ["/o"] = "OFFICER", ["/officer"] = "OFFICER", ["/p"] = "PARTY", ["/party"] = "PARTY",
  ["/ra"] = "RAID", ["/raid"] = "RAID", ["/w"] = "WHISPER", ["/whisper"] = "WHISPER", ["/t"] = "WHISPER", ["/tell"] = "WHISPER" }
FakeGame.CHAT_SWITCH = CHAT_SWITCH

-- Everything the addon has done that taints the game's chat box (empty when clean).
function FakeGame.tainted(client)
  local env, out = client.env, {}
  for _, t in ipairs(client.taint) do out[#out + 1] = t end
  local now = { ["C_ChatInfo.SendChatMessage"] = env.C_ChatInfo and env.C_ChatInfo.SendChatMessage, SendChatMessage = env.SendChatMessage,
    ChatEdit_ParseText = env.ChatEdit_ParseText, ["ChatFrame1EditBox:ParseText"] = rawget(client.chatBox, "ParseText") }
  for k, fn in pairs(client.gameFns) do
    if now[k] ~= fn then out[#out + 1] = "the game's " .. k .. " replaced" end
  end
  if #env.UISpecialFrames > 0 then out[#out + 1] = "UISpecialFrames written to" end
  return out
end

-- Pressing Enter in the chat box: a chat switch (/g, /w Name) changes where it goes, a slash command runs,
-- the box's text is parsed (the addon's post-hook may rewrite it) and what's left is sent. Returns the
-- chat type and whisper target the box is left on.
function FakeGame.typeInChat(client, text, chatType, target)
  local env = client.env
  -- a tainted chat box: the game blocks its own chat and slash commands and blames the addon
  local tainted = FakeGame.tainted(client)
  if #tainted > 0 then
    client.blockedPopup = tainted
    client.fire("ADDON_ACTION_BLOCKED", "FantasyForce", tostring(text):match("^/") and "ChatEdit_ParseText()" or "SendChatMessage()")
    return chatType, target
  end
  local word, rest = tostring(text):match("^(/%S+)%s*(.*)$")
  if word and CHAT_SWITCH[word:lower()] then
    chatType = CHAT_SWITCH[word:lower()]
    if chatType == "WHISPER" then target, rest = rest:match("^(%S+)%s*(.*)$") end
    text = rest or ""
  elseif word and client.chatKind == "send" then
    if FakeGame.runSlash(client, text, client.chatBox) then return chatType, target end
  end
  local box = client.chatBox
  box._text = text
  box._attrs = { chatType = chatType, tellTarget = target }
  if client.chatKind == "mixin" then box:ParseText(1)
  elseif type(env.ChatEdit_ParseText) == "function" then env.ChatEdit_ParseText(box, 1) end
  local out = box._text or ""
  if out ~= "" and not out:match("^/") then
    local send = (env.C_ChatInfo and env.C_ChatInfo.SendChatMessage) or env.SendChatMessage
    if send then send(out, chatType, nil, target) end
  end
  box._text = ""
  return chatType, target
end

-- Runs OnUpdate scripts on shown frames.
function FakeGame.update(client, elapsed)
  local any = false
  for f, fn in pairs(client.updaters) do
    if f._scripts.OnUpdate == fn and f:IsVisible() then
      fn(f, elapsed)
      any = true
    end
  end
  return any
end

-- SavedVariables as the game writes them: a Lua table constructor.
function FakeGame.serialize(v, indent)
  indent = indent or ""
  local t = type(v)
  if t == "string" then return string.format("%q", v) end
  if t == "number" or t == "boolean" or t == "nil" then return tostring(v) end
  if t ~= "table" then return "nil" end
  local keys = {}
  for k in pairs(v) do
    if type(k) == "string" or type(k) == "number" then keys[#keys + 1] = k end
  end
  table.sort(keys, function(a, b)
    if type(a) == type(b) then return a < b end
    return type(a) == "number"
  end)
  local inner, parts = indent .. "\t", {}
  for _, k in ipairs(keys) do
    local key = type(k) == "number" and ("[" .. k .. "]") or ("[" .. string.format("%q", k) .. "]")
    parts[#parts + 1] = inner .. key .. " = " .. FakeGame.serialize(v[k], inner) .. ","
  end
  if #parts == 0 then return "{}" end
  return "{\n" .. table.concat(parts, "\n") .. "\n" .. indent .. "}"
end

return FakeGame
