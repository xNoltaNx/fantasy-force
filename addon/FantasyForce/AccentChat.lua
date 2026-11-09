-- FantasyForce Accent, game side: chat you type is rewritten in your accent (Accent.lua) before it's
-- sent, and the mail window gets an Accent button. Settings are per character (FantasyForceCharDB).
-- /accent auto|troll|orc|tauren|undead|skyborne|off, /accent light|thick, /accent chat <TYPE> on|off,
-- /troll (troll on or off), /troll <message> (one message in troll to the current chat).
--
-- How typed chat is caught, in order of preference:
--   1. a hook after the chat box reads what you typed (ChatEdit_ParseText): the box's text is
--      rewritten just before the game sends it, and the game's own send code runs untouched;
--   2. else a wrapper around SendChatMessage (C_ChatInfo.SendChatMessage or the old global).
-- If neither is possible, or the game blocks the wrapper, /troll <message> still works and one line
-- says so, once.

local _, ns = ...
if type(ns) ~= "table" or not ns.Accent or not ns.try then return end
local Accent, try, str, print_, after = ns.Accent, ns.try, ns.str, ns.print, ns.after
local type, pcall, pairs, ipairs = type, pcall, pairs, ipairs

local DEFAULT_TYPES = { SAY = true, YELL = true, GUILD = true, OFFICER = true, PARTY = true, RAID = true, WHISPER = true }
local CHAT_LIMIT = 255
local UNDO_SECONDS = 10

local hooks = { mode = nil, inSend = false, blocked = false, told = false }
local mail = {}

local function charDB()
  if type(FantasyForceCharDB) ~= "table" then FantasyForceCharDB = {} end
  local c = FantasyForceCharDB
  if c.accent ~= "auto" and c.accent ~= "off" and not Accent.valid(c.accent) then c.accent = "off" end
  if c.strength ~= "thick" then c.strength = "light" end
  if type(c.chatTypes) ~= "table" then
    c.chatTypes = {}
    for k, v in pairs(DEFAULT_TYPES) do c.chatTypes[k] = v end
  end
  return c
end

local function race()
  local name, file = try(UnitRace, "player")
  return file, name
end

-- The accent and strength in use now ("off" when none).
local function current()
  local c = charDB()
  local file, name = race()
  return Accent.resolve(c.accent, file, name), c.strength
end

local function convertOutgoing(text, chatType)
  if hooks.blocked or type(text) ~= "string" then return text end
  local c = charDB()
  if not c.chatTypes[str(chatType):upper()] then return text end
  local accent, strength = current()
  if accent == "off" then return text end
  return Accent.fit(text, accent, strength, CHAT_LIMIT)
end

-- 1. After the chat box parsed what you typed (send = 1 means Enter was pressed).
local function afterParse(editBox, send)
  if send ~= 1 or hooks.blocked or type(editBox) ~= "table" then return end
  local text = try(editBox.GetText, editBox)
  if type(text) ~= "string" or text == "" or text == editBox.ffConverted then return end
  local out = convertOutgoing(text, try(editBox.GetAttribute, editBox, "chatType"))
  if out ~= text then
    editBox.ffConverted = out -- a second hook on the same send leaves it alone
    try(editBox.SetText, editBox, out)
  end
end

local function hookParse()
  if type(hooksecurefunc) ~= "function" then return false end
  local hooked = false
  if ChatFrameUtil and type(ChatFrameUtil.ParseText) == "function" then
    hooked = pcall(hooksecurefunc, ChatFrameUtil, "ParseText", afterParse) or hooked
  end
  if type(ChatEdit_ParseText) == "function" then
    hooked = pcall(hooksecurefunc, "ChatEdit_ParseText", afterParse) or hooked
  end
  return hooked
end

-- 2. A wrapper around a send function. Our own sends (and a wrapper calling another) pass through.
local function wrap(tbl, key)
  local orig = type(tbl) == "table" and tbl[key]
  if type(orig) ~= "function" then return false end
  local function wrapped(msg, chatType, ...)
    if hooks.inSend then return orig(msg, chatType, ...) end
    local ok, out = pcall(convertOutgoing, msg, chatType)
    hooks.inSend = true
    local r = { pcall(orig, ok and out or msg, chatType, ...) }
    hooks.inSend = false
    if not r[1] then error(r[2], 0) end
    return r[2], r[3], r[4]
  end
  return (pcall(function() tbl[key] = wrapped end))
end

local function installHooks()
  if hooks.mode then return end
  if hookParse() then
    hooks.mode = "parse"
    return
  end
  local a = C_ChatInfo and wrap(C_ChatInfo, "SendChatMessage")
  local b = wrap(_G or {}, "SendChatMessage")
  hooks.mode = (a or b) and "wrap" or "none"
end

local function tellOnceIfUnavailable()
  if hooks.told or not (hooks.mode == "none" or hooks.blocked) then return end
  local accent = current()
  if accent == "off" then return end
  hooks.told = true
  print_("this game version won't let addons change what you type, so chat isn't converted automatically. /troll <message> (or the mail button) still works.")
end

local function sendFn()
  return (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
end

-- /troll <message>: one message in troll to the chat the box is on.
local function sendOne(msg, editBox, accent)
  local chatType = editBox and try(editBox.GetAttribute, editBox, "chatType") or "SAY"
  chatType = str(chatType) ~= "" and chatType or "SAY"
  local target
  if chatType == "WHISPER" then target = try(editBox.GetAttribute, editBox, "tellTarget")
  elseif chatType == "CHANNEL" then target = try(editBox.GetAttribute, editBox, "channelTarget") end
  local _, strength = current()
  local out = Accent.fit(msg, accent, strength, CHAT_LIMIT)
  hooks.inSend = true
  pcall(sendFn(), out, chatType, nil, target)
  hooks.inSend = false
end

-- ------------------------------------------------------------------ slash --

-- ---------------------------------------------------------------- setters --
-- The slash commands and the window's controls change settings through these, so they stay in
-- step; each returns the short line the command prints.

local NAMES = { auto = true, off = true }
for _, a in ipairs(Accent.ACCENTS) do NAMES[a] = true end
local SAMPLE = "Hello friend, I am going to the bank with you. Thank you!"

local function changed()
  if type(ns.onSettingChanged) == "function" then pcall(ns.onSettingChanged) end
end

-- Can typed chat be converted in this game (a hook is in and the game hasn't blocked it)?
local function canConvert()
  return (hooks.mode == "parse" or hooks.mode == "wrap") and not hooks.blocked
end

-- One short line: which accent is on, or that it's off.
local function nowLine()
  local c = charDB()
  local accent, strength = current()
  if c.accent == "off" then return "accent off." end
  if accent == "off" then return "accent on (auto), but your race has none: try /accent troll." end
  return "accent on: " .. accent .. (c.accent == "auto" and " (auto)" or "") .. ", " .. strength .. "."
end

-- For the window's accent switch: "Troll, thick" or "Off".
local function shortStatus()
  local c = charDB()
  local accent, strength = current()
  if c.accent == "off" then return "Off" end
  if accent == "off" then return "Auto: your race has none" end
  return accent:sub(1, 1):upper() .. accent:sub(2) .. ", " .. strength
end

-- /accent status: the accent, the chats, and whether chat can be converted here.
local function statusText()
  local c = charDB()
  local types = {}
  for k, v in pairs(c.chatTypes) do if v then types[#types + 1] = k:lower() end end
  table.sort(types)
  local s = nowLine() .. " Chats: " .. table.concat(types, ", ") .. "."
  if hooks.mode and not canConvert() then
    s = s .. " This game won't let addons change what you type: /troll <message> and the mail button still work."
  end
  return s
end

-- The sample sentence in the accent now in use (as typed when it's off).
local function preview()
  local c = charDB()
  local accent, strength = current()
  if c.accent == "off" or accent == "off" then return SAMPLE end
  return Accent.convert(SAMPLE, accent, strength, { seed = 0 })
end

local function setAccent(name)
  local c = charDB()
  if not NAMES[name] then return nowLine() end
  if name == "off" and c.accent ~= "off" then c.lastAccent, c.lastStrength = c.accent, c.strength end
  c.accent = name
  changed()
  tellOnceIfUnavailable()
  return nowLine()
end

local function setStrength(s)
  local c = charDB()
  if s == "light" or s == "thick" then c.strength = s end
  changed()
  return nowLine()
end

local function setChatType(kind, on)
  local c = charDB()
  c.chatTypes[str(kind):upper()] = on and true or nil
  changed()
  return statusText()
end

-- /accent with nothing after it: off remembers the accent and strength, on brings them back (the
-- first time ever: auto, from your race).
local function toggle()
  local c = charDB()
  if c.accent ~= "off" then return setAccent("off") end
  c.accent = c.lastAccent or "auto"
  if c.lastStrength then c.strength = c.lastStrength end
  changed()
  tellOnceIfUnavailable()
  return nowLine()
end

SlashCmdList = SlashCmdList or {}
SLASH_FANTASYFORCEACCENT1 = "/accent"
SlashCmdList["FANTASYFORCEACCENT"] = function(msg)
  local ok = pcall(function()
    msg = str(msg):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if msg == "" then
      print_(toggle())
    elseif NAMES[msg] then
      print_(setAccent(msg))
    elseif msg == "light" or msg == "thick" then
      print_(setStrength(msg))
    elseif msg == "status" then
      print_(statusText())
    elseif msg == "help" then
      if type(ns.printHelp) == "function" then ns.printHelp("/accent", "/troll") end
    else
      local kind, onoff = msg:match("^chat%s+(%a+)%s+(%a+)$")
      if kind and (onoff == "on" or onoff == "off") then
        print_(setChatType(kind, onoff == "on"))
      else
        print_("there's no /accent " .. msg .. ": /accent help lists the commands.")
      end
    end
  end)
  if not ok then print_("something went wrong.") end
end

SLASH_FANTASYFORCETROLL1 = "/troll"
SlashCmdList["FANTASYFORCETROLL"] = function(msg, editBox)
  local ok = pcall(function()
    local c = charDB()
    msg = str(msg):gsub("^%s+", ""):gsub("%s+$", "")
    if msg ~= "" then
      sendOne(msg, editBox, "troll")
      return
    end
    if c.accent == "troll" then
      print_(setAccent((c.before and c.before ~= "troll") and c.before or "off"))
    else
      c.before = c.accent
      print_(setAccent("troll"))
    end
  end)
  if not ok then print_("something went wrong.") end
end

-- ------------------------------------------------------------------- mail --

local function mailBody()
  if SendMailBodyEditBox then return SendMailBodyEditBox end
  local m = MailEditBox
  if type(m) ~= "table" then return nil end
  return (type(m.GetEditBox) == "function" and try(m.GetEditBox, m)) or (m.ScrollBox and m.ScrollBox.EditBox) or nil
end

local function mailAccent()
  local accent, strength = current()
  if accent == "off" then
    local file, name = race()
    accent = Accent.forRace(file, name)
  end
  return accent, strength
end

local function onMailClick(b)
  local body, subject = mailBody(), SendMailSubjectEditBox
  if not body then return end
  local now = try(GetTime) or 0
  if mail.undo and now - mail.undo.at <= UNDO_SECONDS then
    try(body.SetText, body, mail.undo.body)
    if subject and mail.undo.subject then try(subject.SetText, subject, mail.undo.subject) end
    mail.undo = nil
    try(b.SetText, b, "Accent")
    return
  end
  local accent, strength = mailAccent()
  if accent == "off" then
    print_("pick an accent first: /accent troll (or orc, tauren, undead, skyborne).")
    return
  end
  local oldBody = str(try(body.GetText, body))
  local oldSubject = subject and str(try(subject.GetText, subject)) or nil
  local limit = tonumber(try(body.GetMaxLetters, body)) or 0
  if limit <= 0 then limit = 500 end
  try(body.SetText, body, Accent.fit(oldBody, accent, strength, limit))
  if oldSubject and oldSubject ~= "" then
    local subjectLimit = tonumber(try(subject.GetMaxLetters, subject)) or 0
    if subjectLimit <= 0 then subjectLimit = 64 end
    try(subject.SetText, subject, Accent.fit(oldSubject, accent, "light", subjectLimit, { noTags = true }))
  end
  local undo = { at = now, body = oldBody, subject = oldSubject }
  mail.undo = undo
  try(b.SetText, b, "Undo")
  after(UNDO_SECONDS, function()
    if mail.undo == undo then
      mail.undo = nil
      try(b.SetText, b, "Accent")
    end
  end)
end

local function makeMailButton()
  if mail.button or not SendMailFrame or not CreateFrame then return end
  local ok, b = pcall(CreateFrame, "Button", "FantasyForceMailAccentButton", SendMailFrame, "UIPanelButtonTemplate")
  if not ok or not b then return end
  mail.button = b
  b:SetSize(64, 20)
  b:SetText("Accent")
  -- in the body box's bottom-right corner
  local anchor = SendMailScrollFrame or MailEditBox or mailBody()
  b:ClearAllPoints()
  if anchor then
    b:SetPoint("BOTTOMRIGHT", anchor, "BOTTOMRIGHT", -4, 4)
  else
    b:SetPoint("TOPRIGHT", SendMailFrame, "TOPRIGHT", -40, -80)
  end
  try(b.SetFrameLevel, b, (tonumber(try(SendMailFrame.GetFrameLevel, SendMailFrame)) or 1) + 10)
  b:SetScript("OnClick", function(self) pcall(onMailClick, self) end)
  b:SetScript("OnEnter", function(self)
    pcall(function()
      local accent, strength = mailAccent()
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText("Accent")
      -- the game's white (HIGHLIGHT_FONT_COLOR)
      local c = type(HIGHLIGHT_FONT_COLOR) == "table" and HIGHLIGHT_FONT_COLOR or { r = 1, g = 1, b = 1 }
      if accent == "off" then
        GameTooltip:AddLine("Rewrites this letter in your accent. Pick one first: /accent troll (or orc, tauren, undead, skyborne).", c.r, c.g, c.b, true)
      else
        GameTooltip:AddLine("Rewrites this letter and its subject in your accent (" .. accent .. ", " .. strength .. "). Press again within 10 seconds to undo.", c.r, c.g, c.b, true)
      end
      GameTooltip:Show()
    end)
  end)
  b:SetScript("OnLeave", function() if GameTooltip then try(GameTooltip.Hide, GameTooltip) end end)
end

-- ----------------------------------------------------------------- events --

local frame = CreateFrame and CreateFrame("Frame") or nil
if frame then
  for _, ev in ipairs({ "PLAYER_LOGIN", "MAIL_SHOW", "ADDON_ACTION_BLOCKED", "ADDON_ACTION_FORBIDDEN" }) do
    pcall(frame.RegisterEvent, frame, ev)
  end
  frame:SetScript("OnEvent", function(_, event, arg1)
    pcall(function()
      if event == "PLAYER_LOGIN" then
        installHooks()
        tellOnceIfUnavailable()
      elseif event == "MAIL_SHOW" then
        makeMailButton()
      elseif (event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN") and arg1 == "FantasyForce"
        and hooks.mode == "wrap" then
        hooks.blocked = true -- the wrapper now passes everything through untouched
        tellOnceIfUnavailable()
        changed()
      end
    end)
  end)
end

-- For the tests.
ns.AccentChat = { installHooks = installHooks, hooks = hooks, current = current, convertOutgoing = convertOutgoing,
  charDB = charDB, setAccent = setAccent, setStrength = setStrength, setChatType = setChatType, toggle = toggle,
  statusText = statusText, shortStatus = shortStatus, canConvert = canConvert, preview = preview, SAMPLE = SAMPLE }
