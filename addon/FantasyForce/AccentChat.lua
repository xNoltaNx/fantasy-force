-- FantasyForce Accent, game side: what you say on the accent's own chat line (and with /troll) goes out in
-- your accent (Accent.lua), and the mail window gets an Accent button. Settings are per character
-- (FantasyForceCharDB). /accent auto|troll|orc|tauren|undead|skyborne|off, /accent light|thick,
-- /accent chat <TYPE> on|off, /accent debug, /troll (troll on or off), /troll <message> (one message in troll).
--
-- The game's own chat box is never touched: no hooks on it, nothing written to it, no game function
-- replaced. On newer game versions any of those can taint the chat box, and the game then blocks its own
-- chat and slash commands and blames this addon ("FantasyForce has been blocked from an action only
-- available to the Blizzard UI"). Instead the accent has its own chat line, an edit box of ours docked
-- where the chat box sits: opened by the speech bubble by the chat tab, by a key (Key Bindings > Fantasy
-- Force), and by the addon's Whisper and Ask buttons. Enter sends it with SendChatMessage, the same
-- call /troll makes, on the chat the game's box is on (or a /s, /g, /w Name typed at its start).

local _, ns = ...
if type(ns) ~= "table" or not ns.Accent or not ns.try then return end
local Accent, try, str, print_, after = ns.Accent, ns.try, ns.str, ns.print, ns.after
local type, pcall, pairs, ipairs = type, pcall, pairs, ipairs

local DEFAULT_TYPES = { SAY = true, YELL = true, GUILD = true, OFFICER = true, PARTY = true, RAID = true, WHISPER = true }
local CHAT_LIMIT = 255
local UNDO_SECONDS = 10

-- mode: "line" once the accent line is made ("none" if this game can't make one); blocked: the game
-- blocked something of ours (blockedWhat names it); debug: /accent debug reports the next line sent.
local hooks = { mode = nil, inSend = false, blocked = false, blockedWhat = nil, told = false, debug = false }
local mail = {}
local line = {}

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

local function sendFn()
  return (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
end

local function changed()
  if type(ns.onSettingChanged) == "function" then pcall(ns.onSettingChanged) end
  if line.refresh then pcall(line.refresh) end
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

-- ------------------------------------------------------------ the accent line --

-- A chat switch typed at the start of the line, as in the game's box: "/g ", "/w Name ".
line.SWITCH = { ["/s"] = "SAY", ["/say"] = "SAY", ["/y"] = "YELL", ["/yell"] = "YELL", ["/g"] = "GUILD", ["/guild"] = "GUILD",
  ["/o"] = "OFFICER", ["/officer"] = "OFFICER", ["/p"] = "PARTY", ["/party"] = "PARTY", ["/ra"] = "RAID", ["/raid"] = "RAID",
  ["/rw"] = "RAID_WARNING", ["/i"] = "INSTANCE_CHAT", ["/w"] = "WHISPER", ["/whisper"] = "WHISPER", ["/t"] = "WHISPER",
  ["/tell"] = "WHISPER" }
line.LABELS = { SAY = "Say", YELL = "Yell", GUILD = "Guild", OFFICER = "Officer", PARTY = "Party", RAID = "Raid",
  RAID_WARNING = "Raid Warning", INSTANCE_CHAT = "Instance", CHANNEL = "Channel" }
line.chatType = "SAY"

-- The chat the game's chat box is on (read only), for the line to start on.
function line.gameChat()
  local box = _G and (_G.ChatFrame1EditBox or (_G.ChatFrame1 and _G.ChatFrame1.editBox)) or nil
  local chatType = box and try(box.GetAttribute, box, "chatType")
  chatType = type(chatType) == "string" and chatType or "SAY"
  if chatType == "WHISPER" then return chatType, try(box.GetAttribute, box, "tellTarget") end
  if chatType == "CHANNEL" then return chatType, try(box.GetAttribute, box, "channelTarget") end
  if not line.LABELS[chatType] then return "SAY" end
  return chatType
end

function line.make()
  if line.frame then return line.frame end
  if not CreateFrame then return nil end
  local ok, f = pcall(CreateFrame, "EditBox", "FantasyForceAccentLine", UIParent, "InputBoxTemplate")
  if not ok or not f then ok, f = pcall(CreateFrame, "EditBox", "FantasyForceAccentLine2", UIParent) end
  if not ok or not f then return nil end
  line.frame = f
  f:Hide()
  f:SetHeight(24)
  f:SetAutoFocus(false)
  try(f.SetFontObject, f, ChatFontNormal)
  try(f.SetMaxLetters, f, CHAT_LIMIT)
  try(f.SetHistoryLines, f, 30)
  try(f.SetAltArrowKeyMode, f, false)
  try(f.SetFrameStrata, f, "DIALOG")
  -- where the game's chat box sits, under the first chat window
  local cf = _G and _G.ChatFrame1
  if type(cf) == "table" then
    f:SetPoint("TOPLEFT", cf, "BOTTOMLEFT", 2, -6)
    f:SetPoint("TOPRIGHT", cf, "BOTTOMRIGHT", -2, -6)
  else
    f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 40, 120)
    f:SetWidth(420)
  end
  f.label = f:CreateFontString(nil, "OVERLAY", "ChatFontNormal")
  f.label:SetPoint("LEFT", f, "LEFT", 4, 0)
  f:SetScript("OnEnterPressed", function() pcall(line.send) end)
  f:SetScript("OnEscapePressed", function() pcall(line.close) end)
  f:SetScript("OnTextChanged", function(_, user) if user then pcall(line.switch) end end)
  f:SetScript("OnEditFocusLost", function(self) if str(try(self.GetText, self)) == "" then pcall(line.close) end end)
  return f
end

-- The label in front ("Say (troll):", "Tell Grukka:") in the chat's colour, and the text after it.
function line.draw()
  local f = line.frame
  if not f then return end
  local t = line.chatType
  local label = t == "WHISPER" and ("Tell " .. str(line.target) .. ":") or ((line.LABELS[t] or t) .. ":")
  local accent = current()
  if accent ~= "off" and charDB().chatTypes[t] and not hooks.blocked then label = label:sub(1, -2) .. " (" .. accent .. "):" end
  f.label:SetText(label)
  local info = type(ChatTypeInfo) == "table" and ChatTypeInfo[t]
  if type(info) == "table" and info.r then f.label:SetTextColor(info.r, info.g, info.b) else f.label:SetTextColor(1, 1, 1) end
  try(f.SetTextInsets, f, (tonumber(try(f.label.GetStringWidth, f.label)) or 60) + 10, 6, 0, 0)
end

-- Opens the line on a chat (else the one the game's box is on) with text in it; true when it's open.
function line.open(chatType, target, text)
  local f = line.make()
  if not f then return false end
  if not chatType then chatType, target = line.gameChat() end
  line.chatType, line.target = chatType, target
  line.draw()
  f:Show()
  f:SetText(text or "")
  try(f.SetFocus, f)
  try(f.SetCursorPosition, f, #(text or ""))
  return true
end

function line.close()
  local f = line.frame
  if not f then return end
  f:SetText("")
  try(f.ClearFocus, f)
  f:Hide()
end

-- A link (shift-click in the addon's windows) goes at the cursor of the open line, else opens it.
function line.insertLink(link)
  local f = line.frame
  if f and f:IsShown() then
    if not try(f.Insert, f, link) then f:SetText(str(try(f.GetText, f)) .. link) end
    try(f.SetFocus, f)
    return true
  end
  return line.open(nil, nil, link)
end

-- "/g " or "/w Name " typed at the start switches the chat, as in the game's box.
function line.switch()
  local f = line.frame
  local text = str(try(f.GetText, f))
  local word, rest = text:match("^(/%S+)%s(.*)$")
  local kind = word and line.SWITCH[word:lower()]
  if not kind then return end
  if kind == "WHISPER" then
    local name, after_ = rest:match("^(%S+)%s(.*)$")
    if not name then return end
    line.target, rest = name, after_
  end
  line.chatType = kind
  line.draw()
  f:SetText(rest)
end

-- Enter: the line goes out in the accent (when it's on and the chat is on its list), then closes.
function line.send()
  local f = line.frame
  local text = str(try(f.GetText, f))
  if text:match("^%s*$") then return line.close() end
  if text:sub(1, 1) == "/" then
    print_("slash commands go in the game's chat box; this line is for talking (/s, /g, /w Name switch it).")
    return
  end
  local out = convertOutgoing(text, line.chatType)
  try(f.AddHistoryLine, f, text)
  local target = (line.chatType == "WHISPER" or line.chatType == "CHANNEL") and line.target or nil
  hooks.inSend = true
  local ok = pcall(sendFn(), out, line.chatType, nil, target)
  hooks.inSend = false
  if hooks.debug then
    hooks.debug = false
    print_("accent debug: the accent line sent " .. line.chatType .. (out ~= text and ", in the accent" or ", as typed")
      .. (ok and "" or " (the send failed)") .. ".")
  end
  line.close()
end

-- The speech bubble by the first chat tab: shown while an accent is on.
function line.makeBubble()
  if line.bubble or not CreateFrame then return line.bubble end
  local ok, b = pcall(CreateFrame, "Button", "FantasyForceAccentBubble", UIParent)
  if not ok or not b then return nil end
  line.bubble = b
  b:SetSize(20, 20)
  local tab = _G and _G.ChatFrame1Tab
  local cf = _G and _G.ChatFrame1
  if type(tab) == "table" then
    b:SetPoint("LEFT", tab, "RIGHT", 2, -2)
  elseif type(cf) == "table" then
    b:SetPoint("BOTTOMLEFT", cf, "TOPLEFT", 0, 4)
  else
    b:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 40, 300)
  end
  b.icon = b:CreateTexture(nil, "ARTWORK")
  b.icon:SetAllPoints()
  b.icon:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-Chat-Up")
  local hl = b:CreateTexture(nil, "HIGHLIGHT")
  hl:SetAllPoints()
  hl:SetTexture("Interface\\ChatFrame\\UI-ChatIcon-Chat-Up")
  try(hl.SetBlendMode, hl, "ADD")
  b:SetScript("OnClick", function() pcall(line.open) end)
  b:SetScript("OnEnter", function(self)
    pcall(function()
      local accent, strength = current()
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:SetText("Accent chat")
      local c = type(HIGHLIGHT_FONT_COLOR) == "table" and HIGHLIGHT_FONT_COLOR or { r = 1, g = 1, b = 1 }
      GameTooltip:AddLine("Talk in your accent (" .. accent .. ", " .. strength .. "). Also on a key: Key Bindings, Fantasy Force.", c.r, c.g, c.b, true)
      GameTooltip:Show()
    end)
  end)
  b:SetScript("OnLeave", function() if GameTooltip then try(GameTooltip.Hide, GameTooltip) end end)
  return b
end

function line.refresh()
  local accent = current()
  local b = line.bubble
  if b then
    if accent ~= "off" and not hooks.blocked then b:Show() else b:Hide() end
  end
  if line.frame and line.frame:IsShown() then line.draw() end
end

-- The key binding (Bindings.xml) calls this.
BINDING_HEADER_FANTASYFORCE = "Fantasy Force"
BINDING_NAME_FANTASYFORCE_ACCENTLINE = "Accent chat line"
function FantasyForce_OpenAccentLine()
  pcall(line.open)
end

local function installHooks()
  if hooks.mode then return end
  local f = line.make()
  line.makeBubble()
  hooks.mode = f and "line" or "none"
  line.refresh()
end

local function tellOnceIfUnavailable()
  if hooks.told or not (hooks.mode == "none" or hooks.blocked) then return end
  local accent = current()
  if accent == "off" and not hooks.blocked then return end
  hooks.told = true
  if hooks.blocked then
    print_("the game blocked FantasyForce (" .. str(hooks.blockedWhat) .. "), so the accent line is off. /troll <message> (or the mail button) still works.")
  else
    print_("this game version won't let addons make a chat line, so chat isn't converted. /troll <message> (or the mail button) still works.")
  end
end

-- ---------------------------------------------------------------- setters --
-- The slash commands and the window's controls change settings through these, so they stay in
-- step; each returns the short line the command prints.

local NAMES = { auto = true, off = true }
for _, a in ipairs(Accent.ACCENTS) do NAMES[a] = true end
local SAMPLE = "Hello friend, I am going to the bank with you. Thank you!"

-- Can what you say be converted here (the line is in and the game hasn't blocked us)?
local function canConvert()
  return hooks.mode == "line" and not hooks.blocked
end

-- One short line: which accent is on, or that it's off.
local function nowLine()
  local c = charDB()
  local accent, strength = current()
  if c.accent == "off" then return "accent off." end
  if accent == "off" then return "accent on (auto), but your race has none: try /accent troll." end
  return "accent on: " .. accent .. (c.accent == "auto" and " (auto)" or "") .. ", " .. strength .. "."
end

-- The first time an accent goes on: where to talk in it.
local function withHint(s)
  local c = charDB()
  if c.accent == "off" or c.lineHinted or not canConvert() then return s end
  c.lineHinted = true
  return s .. " Talk in it with the speech bubble by your chat tab (or /troll <message>); the game's chat box stays as typed."
end

-- For the window's accent switch: "Troll, thick" or "Off".
local function shortStatus()
  local c = charDB()
  local accent, strength = current()
  if c.accent == "off" then return "Off" end
  if accent == "off" then return "Auto: your race has none" end
  return accent:sub(1, 1):upper() .. accent:sub(2) .. ", " .. strength
end

-- /accent status: the accent, the chats, and where it applies.
local function statusText()
  local c = charDB()
  local types = {}
  for k, v in pairs(c.chatTypes) do if v then types[#types + 1] = k:lower() end end
  table.sort(types)
  local s = nowLine() .. " Chats: " .. table.concat(types, ", ") .. "."
  if hooks.mode and not canConvert() then
    s = s .. " This game won't let addons change what you say: /troll <message> and the mail button still work."
  elseif hooks.mode then
    s = s .. " It goes on the accent line (the bubble by the chat tab) and /troll."
  end
  return s
end

-- /accent debug: what's in, what's blocked; the line says how the next message went.
local function debugText()
  hooks.debug = true
  return "accent debug: game chat box hooks: none (by design). Accent line: " .. (line.frame and "ready" or "none")
    .. ", bubble: " .. (line.bubble and (line.bubble:IsShown() and "shown" or "hidden") or "none")
    .. ". Blocked: " .. (hooks.blockedWhat and str(hooks.blockedWhat) or "nothing") .. "."
    .. (line.frame and " Send a line from the bubble: the next line says how it went." or "")
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
  return withHint(nowLine())
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
  return withHint(nowLine())
end

-- Our slash commands: our own SLASH_ names and new keys in the game's SlashCmdList (never assigning
-- the SlashCmdList global itself, which would taint the game's chat box).
SLASH_FANTASYFORCEACCENT1 = "/accent"
SLASH_FANTASYFORCETROLL1 = "/troll"
if type(SlashCmdList) == "table" then
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
      elseif msg == "debug" then
        print_(debugText())
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
end

-- ------------------------------------------------------------------- mail --
-- The one place the addon changes a game frame's text: the letter you're writing, when you press Accent.

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
  frame:SetScript("OnEvent", function(_, event, arg1, arg2)
    pcall(function()
      if event == "PLAYER_LOGIN" then
        installHooks()
        tellOnceIfUnavailable()
      elseif event == "MAIL_SHOW" then
        makeMailButton()
      elseif (event == "ADDON_ACTION_BLOCKED" or event == "ADDON_ACTION_FORBIDDEN") and arg1 == "FantasyForce" then
        hooks.blocked = true -- nothing is converted from now on; what you type goes out as typed
        hooks.blockedWhat = str(arg2) ~= "" and arg2 or event
        tellOnceIfUnavailable()
        changed()
      end
    end)
  end)
end

-- For the main file (its Whisper, Ask and link buttons use the line) and the tests.
ns.AccentChat = { installHooks = installHooks, hooks = hooks, current = current, convertOutgoing = convertOutgoing,
  charDB = charDB, setAccent = setAccent, setStrength = setStrength, setChatType = setChatType, toggle = toggle,
  statusText = statusText, shortStatus = shortStatus, canConvert = canConvert, preview = preview, SAMPLE = SAMPLE,
  line = line, openLine = line.open, insertLink = line.insertLink, debugText = debugText,
  -- what the line holds, as typed in chat: "/w Grukka Hi!" for a whisper, else the text
  describeLine = function()
    local f = line.frame
    if not (f and f:IsShown()) then return nil end
    local text = str(try(f.GetText, f))
    if line.chatType == "WHISPER" then return "/w " .. str(line.target) .. " " .. text end
    return text
  end }
