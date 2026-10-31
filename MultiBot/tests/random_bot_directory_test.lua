-- Run from addon root with Lua 5.1; native WoW APIs are isolated fakes.
local now, timers, sent = 100, {}, {}
GetTime = function() return now end
UnitName = function(unit) if unit == "player" then return "Tester" end end
GetNumRaidMembers = function() return 0 end
GetNumPartyMembers = function() return 0 end
GetLocale = function() return "enUS" end
SendAddonMessage = function(...) sent[#sent + 1] = {...} end
MultiBot = { bridge = {}, TimerAfter = function(delay, callback) timers[#timers + 1] = { delay, callback } end }
assert(loadfile("Core/MultiBotComm.lua"))()
assert(loadfile("Features/MultiBotRandomBotDirectory.lua"))()
local D, C = MultiBot.RandomBotDirectory, MultiBot.Comm
local function rx(op, payload, sender)
    return C.HandleAddonMessage("MBOT", op .. (payload and "~" .. payload or ""), "WHISPER", sender or "Tester")
end
rx("CAPS_BEGIN")
rx("CAPS", "RANDOMBOT_DIRECTORY_V1")
rx("CAPS_END")
assert(MultiBot.bridge.randomBotDirectoryCapable)
MultiBot.bridge.connected = true
local received, failure, callbacks
local function request(q)
    now = now + 3.1
    received, failure, callbacks = nil, nil, 0
    assert(D.Request(q or {}, function(data, reason) received, failure = data, reason; callbacks = callbacks + 1 end))
    assert(#sent[#sent][2] + #sent[#sent][1] + 1 <= 255)
    return D.pending.token
end
local function entry(token, id, name)
    return token .. "~" .. (id or 1) .. "~" .. (name or "Priest") .. "~5~58~1~1~UNKNOWN~ONLINE~12~0~0~OK~Elwynn%20Forest"
end
local token = request({class=5, minLevel=55, maxLevel=60, sort="LEVEL"})
assert(string.find(sent[#sent][2], "~5~55~60~0~0~0~0~LEVEL~0~ANY", 1, true))
rx("RBD_BEGIN", token .. "~0~1~1~ONLINE_ONLY", "Attacker")
assert(not D.pending.total) -- Sender validation precedes directory dispatch.
rx("RBD_BEGIN", token .. "~0~1~1~ONLINE_ONLY")
rx("RBD_ENTRY", entry(token))
assert(callbacks == 0) -- Atomic result, only committed after END.
rx("RBD_END", token .. "~0~1~1~ONLINE_ONLY")
assert(callbacks == 1 and received.total == 1 and received.rows[1].level == 58)
assert(received.rows[1].zoneName == "Elwynn Forest" and not received.rows[1].grouped)
token = request({page=1})
rx("RBD_BEGIN", token .. "~1~26~1~ONLINE_ONLY")
rx("RBD_ENTRY", entry(token, 26))
rx("RBD_END", token .. "~1~26~1~ONLINE_ONLY")
assert(received.page == 1 and received.rows[1].guid == 26)
token = request({status=2})
rx("RBD_BEGIN", token .. "~0~0~0~ONLINE_ONLY")
rx("RBD_END", token .. "~0~0~0~ONLINE_ONLY")
assert(received.total == 0 and #received.rows == 0)
token = request()
rx("RBD_BEGIN", token .. "~0~26~26~ONLINE_ONLY")
assert(failure == "BAD_RESPONSE")
token = request()
rx("RBD_ENTRY", entry(token))
assert(failure == "BAD_RESPONSE")
token = request()
rx("RBD_BEGIN", token .. "~0~2~2~ONLINE_ONLY")
rx("RBD_ENTRY", entry(token))
rx("RBD_ENTRY", entry(token))
assert(failure == "BAD_RESPONSE")
token = request()
rx("RBD_BEGIN", token .. "~0~1~1~ONLINE_ONLY")
rx("RBD_ENTRY", entry(token, 1, "%ZZ"))
assert(failure == "BAD_RESPONSE")
token = request()
rx("RBD_BEGIN", token .. "~0~1~1~ONLINE_ONLY")
rx("RBD_END", token .. "~0~1~1~ONLINE_ONLY")
assert(failure == "BAD_RESPONSE")
token = request()
rx("ERR", "GET~RANDOMBOT_DIRECTORY~other~RATE_LIMIT")
assert(D.pending)
rx("ERR", "GET~RANDOMBOT_DIRECTORY~" .. token .. "~RATE_LIMIT")
assert(failure == "RATE_LIMIT")
token = request()
D.Cancel()
rx("RBD_BEGIN", token .. "~0~0~0~ONLINE_ONLY")
rx("RBD_END", token .. "~0~0~0~ONLINE_ONLY")
assert(callbacks == 0 and not D.pending)
token = request()
timers[#timers][2]()
assert(failure == "TIMEOUT" and callbacks == 1)
token = request()
C.MarkDisconnected("test")
assert(failure == "DISCONNECTED" and not D.pending and not MultiBot.bridge.randomBotDirectoryCapable)
MultiBot.bridge.connected, MultiBot.bridge.randomBotDirectoryCapable = true, true
request()
local secondFailure
assert(not D.Request({}, function(_, reason) secondFailure = reason end))
assert(secondFailure == "BUSY")
D.Cancel()
assert(not D.Request({}, function(_, reason) secondFailure = reason end))
assert(secondFailure == "RATE_LIMIT")
now = now + 3.1
assert(not D.Request({name=string.rep("ä",100)}, function(_, reason) secondFailure = reason end))
assert(secondFailure == "TOO_LARGE")
-- UI harness: create every control and invoke real invitation/group/close handlers.
local frames, buttons = {}, {}
local Frame = {}
Frame.__index = function(_, key)
    if Frame[key] then return Frame[key] end
    if string.match(key, "^[A-Z]") then return function() end end
end
function Frame:SetScript(event, fn) self.scripts[event] = fn end
function Frame:HookScript(event, fn)
    local previous = self.scripts[event]
    self.scripts[event] = function(...) if previous then previous(...) end; fn(...) end
end
function Frame:Enable() self.enabled = true end
function Frame:Disable() self.enabled = false end
function Frame:IsEnabled() return self.enabled ~= false end
function Frame:SetBackdrop(value) self.backdrop = value end
function Frame:SetBackdropColor(...) self.backdropColor = {...} end
function Frame:SetTextInsets(...) self.insets = {...} end
function Frame:CreateFontString() return setmetatable({ scripts={} }, Frame) end
function Frame:CreateTexture() return setmetatable({ scripts={} }, Frame) end
function Frame:SetText(value) self.text = tostring(value) end
function Frame:GetText() return self.text or "" end
function Frame:IsShown() return self.shown == true end
function Frame:Show() local old=self.shown; self.shown=true; if not old and self.scripts.OnShow then self.scripts.OnShow(self) end end
function Frame:Hide() local old=self.shown; self.shown=false; if old and self.scripts.OnHide then self.scripts.OnHide(self) end end
function Frame:RegisterEvent(e) self.events[e]=true end
function Frame:UnregisterAllEvents() self.events={} end
function CreateFrame(kind,name,parent)
    local f=setmetatable({scripts={},events={},shown=true,name=name,parent=parent},Frame)
    if name then frames[name]=f end
    if kind=="Button" then buttons[#buttons+1]=f end
    return f
end
UIParent = {}
UISpecialFrames = {}
tinsert = table.insert
UIDropDownMenu_SetWidth = function() end
UIDropDownMenu_Initialize = function(f,fn) f.initialize=fn end
UIDropDownMenu_SetText = function() end
CloseDropDownMenus = function() end
GameTooltip = setmetatable({scripts={}}, Frame)
InCombatLockdown = function() return false end
UnitLevel = function() return 60 end
local invited
InviteUnit = function(name) invited=name end
assert(loadfile("UI/MultiBotRandomBotDirectoryUI.lua"))()
now = now + 3.1
MultiBot.ToggleRandomBotDirectory()
local window=frames.MultiBotRandomBotBrowser
assert(window:IsShown() and D.pending)
assert(window.invite:IsShown() and not window.invite:IsEnabled())
for _, field in ipairs({window.low, window.high}) do
    assert(field.backdrop.bgFile == "Interface\\ChatFrame\\ChatFrameBackground")
    assert(field.backdropColor[4] == 0.9 and field.insets[1] == 6)
end
token = D.pending.token
rx("RBD_BEGIN", token .. "~0~2~2~ONLINE_ONLY")
rx("RBD_ENTRY", entry(token))
rx("RBD_ENTRY", entry(token, 2, "Otherpriest"))
rx("RBD_END", token .. "~0~2~2~ONLINE_ONLY")
local row
for _, b in ipairs(buttons) do if b.data then row=b; break end end
assert(row and row.data.name == "Priest")
row.scripts.OnClick(row)
local invite
for _, b in ipairs(buttons) do if b.text=="Invite" then invite=b end end
assert(invite and invite:IsShown() and invite:IsEnabled())
invite.scripts.OnClick()
assert(invited=="Priest" and invite:IsShown() and not invite:IsEnabled())
assert(row.data.reason == "PENDING_INVITE")
window.scripts.OnEvent(window,"CHAT_MSG_SYSTEM","Priest is already in a group.")
assert(string.find(window.status.text,"Priest",1,true))
GetNumPartyMembers = function() return 1 end
UnitName = function(unit) return unit=="player" and "Tester" or unit=="party1" and "Priest" or nil end
local sends=#sent
window.scripts.OnEvent(window,"PARTY_MEMBERS_CHANGED")
assert(#sent==sends+1 and sent[#sent][2]=="GET~ROSTER")
assert(string.find(window.status.text,"joined",1,true))
assert(invite:IsShown() and not invite:IsEnabled() and row.data.reason == "IN_YOUR_GROUP")
local sendsAfterJoin = #sent
local other = window.rows[2]
other.scripts.OnClick(other)
assert(invite:IsShown() and invite:IsEnabled() and #sent == sendsAfterJoin)
invite.scripts.OnClick()
assert(invited == "Otherpriest" and invite:IsShown() and not invite:IsEnabled())
timers[#timers][2]()
assert(other.data.reason == "STATUS_UNKNOWN" and invite:IsShown() and not invite:IsEnabled())
-- The opener fills the vacant pagination slot and moves only when pagination becomes visible.
local browse = setmetatable({scripts={}, events={}, shown=false}, Frame)
local opener = {}
opener.setPoint = function(x, y) opener.x, opener.y = x, y end
local control = { buttons = { Browse = browse }, addButton = function() return opener end }
MultiBot.BuildRandomBotDirectoryControl(control)
assert(opener.y == 180)
browse:Show()
assert(opener.y == 210)
browse:Hide()
assert(opener.y == 180)
window:Hide()
assert(not next(window.events) and not D.pending)
now=now+3.1
window:Show()
assert(D.pending)
window:Hide()
assert(not D.pending)
print("PASS: Lua 5.1 capability/sender/framing/paging/empty/offline/malformed/rate/errors/timeout/disconnect/UI/native invite/roster/cleanup")
