-- Picky / Toast.lua : small notification for events (pattern: GearQuestForever Toast.lua)
-- Large clickable area with text (for requests: click = invite) + fixed "Open window" button.
-- Queue, pauses on mouseover, fades out on its own.
local ADDON, LP = ...
local L = LP.L
local T = {}
LP.Toast = T

local FADE_IN, HOLD, FADE_OUT = 0.35, 7.0, 0.6
local WIDTH, HEIGHT = 380, 70
local ICON = "Interface\\Icons\\Spell_Nature_MoonKey"

local frame, queue, anim, animStart, hover = nil, {}, nil, 0, false

local function Ensure()
    if frame then return frame end
    frame = CreateFrame("Button", "PickyToast", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("FULLSCREEN_DIALOG")
    frame:SetFrameLevel(100)
    frame:EnableMouse(true)
    frame:RegisterForClicks("LeftButtonUp")
    frame:Hide()
    if frame.SetBackdrop then
        frame:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 16,
            insets = { left = 5, right = 5, top = 5, bottom = 5 },
        })
        frame:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
        frame:SetBackdropBorderColor(0.85, 0.65, 0.12, 1)
    end

    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetSize(40, 40)
    frame.icon:SetPoint("LEFT", 14, 0)
    frame.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOPLEFT", frame.icon, "TOPRIGHT", 10, 2)
    frame.title:SetPoint("RIGHT", frame, "RIGHT", -88, 0)
    frame.title:SetJustifyH("LEFT")

    frame.line = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.line:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -3)
    frame.line:SetPoint("RIGHT", frame, "RIGHT", -88, 0)
    frame.line:SetJustifyH("LEFT")
    frame.line:SetWordWrap(false)

    frame.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.hint:SetPoint("TOPLEFT", frame.line, "BOTTOMLEFT", 0, -2)
    frame.hint:SetPoint("RIGHT", frame, "RIGHT", -88, 0)
    frame.hint:SetJustifyH("LEFT")
    frame.hint:SetWordWrap(false)

    -- fixed button: open the Picky window
    local open = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    open:SetSize(72, 24)
    open:SetPoint("RIGHT", -10, 0)
    open:SetText(L["Window"])
    open:SetScript("OnClick", function() LP.ShowUI() T.Dismiss() end)
    open:SetScript("OnEnter", function() hover = true end)
    open:SetScript("OnLeave", function() hover = false end)
    frame.open = open

    frame:SetScript("OnClick", function(self)
        local fn = self.onClick
        T.Dismiss()
        if fn then fn() end
    end)
    frame:SetScript("OnEnter", function() hover = true end)
    frame:SetScript("OnLeave", function() hover = false end)
    frame:SetScript("OnUpdate", function() T.OnUpdate() end)

    -- Position: about 20% above the bottom edge, as in GearQuest
    frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, math.floor((UIParent:GetHeight() or 768) * 0.20))
    return frame
end

local function Finish()
    local f = Ensure()
    f:Hide()
    f:SetAlpha(0)
    f.onClick = nil
    anim, hover = nil, false
end

local function ShowNext()
    if anim or #queue == 0 then return end
    local item = table.remove(queue, 1)
    local f = Ensure()
    f.icon:SetTexture(item.icon or ICON)
    f.title:SetText(item.title or "")
    f.line:SetText(item.line or "")
    f.hint:SetText(item.hint or "")
    f.onClick = item.onClick
    f:SetAlpha(0)
    f:Show()
    anim, animStart, hover = "in", GetTime(), false
end

function T.Dismiss()
    Finish()
    ShowNext()
end

function T.OnUpdate()
    if not anim or hover then
        if anim == "out" and hover then anim, animStart = "hold", GetTime() frame:SetAlpha(1) end
        if hover and anim == "hold" then animStart = GetTime() end
        return
    end
    local t = GetTime() - animStart
    if anim == "in" then
        frame:SetAlpha(math.min(1, t / FADE_IN))
        if t >= FADE_IN then anim, animStart = "hold", GetTime() frame:SetAlpha(1) end
    elseif anim == "hold" then
        if t >= HOLD then anim, animStart = "out", GetTime() end
    elseif anim == "out" then
        frame:SetAlpha(math.max(0, 1 - t / FADE_OUT))
        if t >= FADE_OUT then Finish() ShowNext() end
    end
end

-- Queue a message; identical messages (key) are not queued twice
function T.Push(item)
    if item.key then
        for _, q in ipairs(queue) do if q.key == item.key then return end end
    end
    queue[#queue + 1] = item
    while #queue > 3 do table.remove(queue, 1) end   -- avoid a backlog: only the last 3 waiting messages count, older ones are outdated
    ShowNext()
end

-- New request: large area. Depending on status: click = invite, or info only.
function T.Request(req)
    local box = req.label or (req.req and L["Box, skill %d"]:format(req.req)) or L["Box unknown"]
    local item = { key = "req:" .. req.name, title = L["New request"], line = req.name .. "  ·  " .. box }
    local st = req.status
    if st == "invited" then
        item.hint = L["Will be invited automatically"]
    elseif st == "grouped" then
        item.hint = L["Already in your group"]
    elseif st == "toohigh" then
        item.hint = L["Your skill is not enough (needs %s)"]:format(tostring(req.req))
    elseif st == "queued" then
        item.hint = L["Waiting - click: invite now"]
        item.onClick = function() LP.TryInvite(req) end
    else
        item.hint = L["Click: invite"]
        item.onClick = function() LP.TryInvite(req) end
    end
    T.Push(item)
end

function T.Joined(req)
    T.Push({ key = "join:" .. req.name, title = L["In the group"], line = req.name,
        hint = L["Open a trade and put the box in the bottom slot"], onClick = function() LP.ShowUI() end })
end

function T.Tip(name, copper, how)
    T.Push({ title = L["Tip"], line = (name or "?") .. "  ·  |cffffd100" .. LP.Money(copper) .. "|r",
        hint = (how == "later" and L["Thank-you follows when you leave"]) or (how == "sent" and L["Thank-you message sent"]) or "", icon = "Interface\\Icons\\INV_Misc_Coin_01" })
end
