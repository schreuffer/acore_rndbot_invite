local MultiBot = _G.MultiBot
if not MultiBot then return end
local D = MultiBot.RandomBotDirectory
local classTokens = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "DEATHKNIGHT", "SHAMAN", "MAGE", "WARLOCK", "", "DRUID" }
local classNames = { "Warrior", "Paladin", "Hunter", "Rogue", "Priest", "Death Knight", "Shaman", "Mage", "Warlock", "", "Druid" }
local races = { "Human", "Orc", "Dwarf", "Night Elf", "Undead", "Tauren", "Gnome", "Troll", "", "Blood Elf", "Draenei" }
local reasons = {
    OK = "Eligible (preflight)",
    OTHER_GROUP = "Already grouped",
    IN_YOUR_GROUP = "Already in your group",
    GROUP_FULL = "Group full", NOT_LEADER = "Not group leader/assistant",
    WRONG_FACTION = "Incompatible faction",
    PERMISSION_DENIED = "Playerbots permission denied",
    LOW_LEVEL = "Your level is too low", GEARSCORE = "Gear score too low",
    BATTLEGROUND = "In battleground", BG_QUEUE = "In battleground queue",
    PENDING_INVITE = "Invitation pending",
    STATUS_UNKNOWN = "Invitation not confirmed. Refresh to check current status.",
    DISABLED = "Disabled by server: RandomBotDirectory.Enable",
    UNAVAILABLE = "Bridge/capability unavailable",
    DISCONNECTED = "Disconnected", BAD_RESPONSE = "Invalid server response",
    BAD_FILTER = "Invalid filters (level 1–80)",
    RATE_LIMIT = "Wait at least 3 seconds between queries",
    BUSY = "Server or request busy",
    TIMEOUT = "Request timed out – refresh to retry",
    TOO_LARGE = "Search too long", TOKEN_USED = "Request already processed",
}
local window, selected, invitation
local result = { rows = {}, page = 0, total = 0 }
local query = { page = 0, class = 0, faction = 0, status = 0, invite = 0, sort = "NAME" }
local refresh, render
local function label(parent, value, x, y, width)
    local f = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f:SetPoint("TOPLEFT", x, y)
    f:SetWidth(width)
    f:SetJustifyH("LEFT")
    f:SetText(value)
    return f
end
local function button(parent, value, x, y, width, callback)
    local f = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    f:SetPoint("TOPLEFT", x, y)
    f:SetWidth(width)
    f:SetHeight(22)
    f:SetText(value)
    f:SetScript("OnClick", callback)
    return f
end
local function edit(parent, title, x, y, width, maxLength, numeric)
    label(parent, title, x, y, width)
    -- Plain EditBox with a sized backdrop: the legacy template's center texture
    -- does not reliably stretch to narrow numeric fields in the 3.3.5 client.
    local f = CreateFrame("EditBox", nil, parent)
    f:SetFontObject("GameFontHighlightSmall")
    f:SetTextInsets(6, 6, 0, 0)
    f:SetBackdrop({ bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border", edgeSize = 10,
        insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    f:SetBackdropColor(0, 0, 0, 0.9)
    f:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)
    f:SetPoint("TOPLEFT", x + 5, y - 18)
    f:SetWidth(width - 10)
    f:SetHeight(20)
    f:SetAutoFocus(false)
    f:SetMaxLetters(maxLength)
    f:SetNumeric(numeric or false)
    f:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f:SetScript("OnEnterPressed", function(self) self:ClearFocus(); refresh(0) end)
    return f
end
local function dropdown(parent, title, x, y, width, choices, initial, change)
    label(parent, title, x, y, width)
    D.dropdownSequence = (D.dropdownSequence or 0) + 1
    local f = CreateFrame("Frame", "MultiBotRandomFilter" .. D.dropdownSequence, parent, "UIDropDownMenuTemplate")
    f:SetPoint("TOPLEFT", x - 16, y - 12)
    UIDropDownMenu_SetWidth(f, width - 20)
    UIDropDownMenu_Initialize(f, function()
        for _, choice in ipairs(choices) do
            local value, caption = choice[1], choice[2]
            local info = UIDropDownMenu_CreateInfo()
            info.text, info.value, info.checked = caption, value, f.value == value
            info.func = function()
                f.value = value
                UIDropDownMenu_SetText(f, caption)
                change(value)
            end
            UIDropDownMenu_AddButton(info)
        end
    end)
    f.value = initial
    for _, choice in ipairs(choices) do if choice[1] == initial then UIDropDownMenu_SetText(f, choice[2]) end end
    return f
end
local function setStatus(message)
    if window then window.status:SetText(message or "") end
end
render = function()
    if not window then return end
    for i = 1, 25 do
        local frame, row = window.rows[i], result.rows[i]
        frame.data = row
        if row then
            frame:Show()
            local token = classTokens[row.class]
            local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[token]
            frame.name:SetText(row.name)
            if color then frame.name:SetTextColor(color.r, color.g, color.b) end
            frame.level:SetText(row.level)
            frame.class:SetText(classNames[row.class] or token)
            frame.race:SetText(races[row.race] or tostring(row.race))
            frame.faction:SetText(row.faction == 1 and "Alliance" or "Horde")
            frame.zone:SetText(row.zoneName or ("#" .. row.zone))
            frame.state:SetText(row.controlled and "Controlled" or (row.grouped and "Grouped" or "Online"))
            if selected == row then frame.selection:Show() else frame.selection:Hide() end
        else frame:Hide() end
    end
    window.page:SetText(string.format("Page %d/%d · %d matches",
        result.page + 1, math.max(1, math.ceil(result.total / 25)), result.total))
    if D.pending or result.page == 0 then window.previous:Disable() else window.previous:Enable() end
    if D.pending or (result.page + 1) * 25 >= result.total then window.next:Disable() else window.next:Enable() end
    window.invite:Show()
    window.invite:SetText(invitation and "Inviting..." or "Invite")
    if selected and selected.reason == "OK" and not D.pending and not invitation then
        window.invite:Enable()
    else
        window.invite:Disable()
    end
    if selected then window.detail:SetText((reasons[selected.reason] or selected.reason) .. " · Role: unknown")
    else window.detail:SetText("Select a bot. Roles unknown; directory contains online bots only.") end
end
refresh = function(page)
    if not window or not window:IsShown() or D.pending then return end
    local low, high = tonumber(window.low:GetText()), tonumber(window.high:GetText())
    if not low or not high or low < 1 or high > 80 or low > high or low % 1 ~= 0 or high % 1 ~= 0 then
        setStatus(reasons.BAD_FILTER); return
    end
    query.name, query.minLevel, query.maxLevel, query.page = window.search:GetText(), low, high, page or 0
    selected = nil
    setStatus("Loading …")
    local requestedStatus = query.status
    D.Request(query, function(data, reason)
        if not window:IsShown() then return end
        if data then
            result = data
            if requestedStatus == 2 then setStatus("Offline directory unavailable in V1; no offline invitations.")
            elseif data.total == 0 then setStatus("No matching online RandomBots.")
            else setStatus("Snapshot. Invitations are checked again by the server.") end
        else
            result = { rows = {}, total = 0, page = 0 }
            setStatus(reasons[reason] or tostring(reason))
        end
        render()
    end)
    render()
end
local function inGroup(name)
    if UnitName("player") == name then return false end
    for i = 1, GetNumRaidMembers() do if UnitName("raid" .. i) == name then return true end end
    for i = 1, GetNumPartyMembers() do if UnitName("party" .. i) == name then return true end end
    return false
end
local function inviteSelected()
    if not selected or selected.reason ~= "OK" or invitation or D.pending then return end
    if InCombatLockdown() then setStatus("Please invite out of combat."); return end
    local pending = { name = selected.name, row = selected }
    invitation = pending
    pending.row.reason = "PENDING_INVITE"
    setStatus("Invitation sent to " .. pending.name)
    InviteUnit(pending.name) -- Native CMSG_GROUP_INVITE; Playerbots owns acceptance/master/follow.
    render()
    MultiBot.TimerAfter(20, function()
        if invitation ~= pending then return end
        invitation = nil
        pending.row.reason = "STATUS_UNKNOWN"
        setStatus("No join confirmed after 20 s. Refresh status.")
        render()
    end)
end
local function onEvent(_, event, message)
    if event == "PLAYER_LEAVING_WORLD" then window:Hide(); return end
    if not invitation then return end
    if event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
        if inGroup(invitation.name) then
            local name = invitation.name
            invitation.row.grouped = true
            invitation.row.reason = "IN_YOUR_GROUP"
            for _, row in ipairs(result.rows) do
                if row.name == name then row.grouped, row.reason = true, "IN_YOUR_GROUP" end
            end
            invitation = nil
            MultiBot.Comm.RequestRoster()
            setStatus(name .. " joined. Normal MultiBot roster refreshed.")
            render()
        end
    elseif event == "CHAT_MSG_SYSTEM" and message then
        -- Native localized group errors remain authoritative. Do not intercept unrelated messages.
        local direct = string.find(message, invitation.name, 1, true)
        local generic = message == ERR_GROUP_FULL or message == ERR_NOT_LEADER or message == ERR_PLAYER_WRONG_FACTION
        if direct or generic then setStatus(message) end
    end
end
local function createWindow()
    window = CreateFrame("Frame", "MultiBotRandomBotBrowser", UIParent)
    local w = window
    w:SetSize(840, 680)
    w:SetPoint("CENTER")
    w:SetFrameStrata("DIALOG")
    w:SetClampedToScreen(true)
    w:SetMovable(true)
    w:EnableMouse(true)
    w:RegisterForDrag("LeftButton")
    w:SetScript("OnDragStart", function(self) self:StartMoving() end)
    w:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
    w:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", tile = true, tileSize = 32, edgeSize = 24, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
    label(w, "MultiBot — RandomBots", 18, -15, 550)
    local close = CreateFrame("Button", nil, w, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
    close:SetScript("OnClick", function() w:Hide() end)
    tinsert(UISpecialFrames, "MultiBotRandomBotBrowser")
    w.search = edit(w, "Name", 20, -42, 200, 48)
    w.low = edit(w, "Min level", 230, -42, 70, 2, true)
    w.high = edit(w, "Max level", 310, -42, 70, 2, true)
    w.low:SetText("1"); w.high:SetText("80")
    button(w, "My level ±5", 390, -58, 135, function()
        local level = UnitLevel("player")
        w.low:SetText(math.max(1, level - 5)); w.high:SetText(math.min(80, level + 5))
        refresh(0)
    end)
    button(w, "Search / Refresh", 560, -58, 250, function() refresh(0) end)
    local classes = { { 0, "All classes" } }
    for id, token in ipairs(classTokens) do
        if token ~= "" then classes[#classes + 1] = { id, classNames[id] or token } end
    end
    dropdown(w, "Class", 20, -90, 180, classes, 0, function(v) query.class = v end)
    dropdown(w, "Faction", 205, -90, 150,
        { { 0, "All" }, { 1, "Alliance" }, { 2, "Horde" } }, 0, function(v) query.faction = v end)
    dropdown(w, "Status", 360, -90, 180,
        { { 0, "All available" }, { 1, "Online" }, { 2, "Offline (V1: empty)" } }, 0, function(v) query.status = v end)
    dropdown(w, "Eligibility", 545, -90, 265,
        { { 0, "All" }, { 1, "Eligible" }, { 2, "Ineligible" } }, 0, function(v) query.invite = v end)
    label(w, "Sort:", 20, -143, 75)
    local function sortBy(key)
        if query.sort == key then query.descending = not query.descending else query.sort, query.descending = key, false end
        w.sortDirection:SetText(query.sort .. (query.descending and " DESC" or " ASC"))
        refresh(0)
    end
    button(w, "Name", 90, -136, 100, function() sortBy("NAME") end)
    button(w, "Level", 195, -136, 100, function() sortBy("LEVEL") end)
    button(w, "Class", 300, -136, 100, function() sortBy("CLASS") end)
    w.sortDirection = label(w, "NAME ASC", 415, -143, 150)
    label(w, "Role: unknown (no role filter)", 580, -143, 240)
    -- Match each heading to its row field rather than spacing proportional text.
    local columns = { { "Name", 20, 145 }, { "Level", 168, 40 }, { "Class", 213, 120 },
        { "Race", 338, 95 }, { "Faction", 438, 80 }, { "Zone", 523, 150 }, { "Status", 678, 135 } }
    for _, column in ipairs(columns) do label(w, column[1], column[2], -165, column[3]) end
    w.rows = {}
    for i = 1, 25 do
        local row = CreateFrame("Button", nil, w)
        row:SetPoint("TOPLEFT", 18, -180 - (i - 1) * 17)
        row:SetSize(800, 17)
        row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
        row.selection = row:CreateTexture(nil, "BACKGROUND")
        row.selection:SetAllPoints()
        row.selection:SetTexture(0.2, 0.4, 0.6, 0.5)
        row.selection:Hide()
        row.name = label(row, "", 2, -2, 145)
        row.level = label(row, "", 150, -2, 40)
        row.class = label(row, "", 195, -2, 120)
        row.race = label(row, "", 320, -2, 95)
        row.faction = label(row, "", 420, -2, 80)
        row.zone = label(row, "", 505, -2, 150)
        row.state = label(row, "", 660, -2, 135)
        row:SetScript("OnClick", function(self) selected = self.data; render() end)
        row:SetScript("OnEnter", function(self)
            if not self.data then return end
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(self.data.name)
            GameTooltip:AddLine(reasons[self.data.reason] or self.data.reason, 1, 1, 1, true)
            GameTooltip:AddLine("Zone ID: " .. self.data.zone, 1, 1, 1)
            GameTooltip:Show()
        end)
        row:SetScript("OnLeave", function() GameTooltip:Hide() end)
        w.rows[i] = row
    end
    w.previous = button(w, "<", 20, -610, 40, function() refresh(result.page - 1) end)
    w.next = button(w, ">", 65, -610, 40, function() refresh(result.page + 1) end)
    w.page = label(w, "", 120, -616, 300)
    w.invite = button(w, "Invite", 690, -610, 120, inviteSelected)
    w.detail = label(w, "", 20, -638, 790)
    w.status = label(w, "", 20, -655, 790)
    w:SetScript("OnEvent", onEvent)
    w:SetScript("OnHide", function(self)
        self:UnregisterAllEvents()
        D.Cancel()
        invitation, selected = nil, nil
        GameTooltip:Hide()
        CloseDropDownMenus()
    end)
    w:SetScript("OnShow", function(self)
        self:RegisterEvent("PARTY_MEMBERS_CHANGED")
        self:RegisterEvent("RAID_ROSTER_UPDATE")
        self:RegisterEvent("CHAT_MSG_SYSTEM")
        self:RegisterEvent("PLAYER_LEAVING_WORLD")
        refresh(0)
    end)
    w:Hide()
end
function MultiBot.ToggleRandomBotDirectory()
    if not window then createWindow() end
    if window:IsShown() then window:Hide() else window:Show() end
end

function MultiBot.BuildRandomBotDirectoryControl(control)
    local opener = control.addButton("RandomBots", 0, 180, "INV_Misc_GroupLooking", "RandomBots")
    opener.doLeft = function() MultiBot.ToggleRandomBotDirectory() end
    local browse = control.buttons and control.buttons.Browse
    local function placeOpener()
        -- Use the free slot when roster pagination is hidden; avoid overlapping it otherwise.
        opener.setPoint(0, browse and browse:IsShown() and 210 or 180)
    end
    if browse then
        browse:HookScript("OnShow", placeOpener)
        browse:HookScript("OnHide", placeOpener)
    end
    placeOpener()
end
