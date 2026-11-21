-- Picky / Toast.lua : small notification for events (pattern: GearQuestForever Toast.lua)
-- Large clickable area with text (for requests: click = invite) + fixed "Open window" button.
-- One toast at a time; a new toast always replaces the current one (the newest wins).
-- A toast stays only as long as it is still relevant: each one has a valid() check that is polled,
-- and info-only toasts have a maxAge. The X or a click closes any toast right away.
local ADDON, LP = ...
local L = LP.L
local T = {}
LP.Toast = T

local FADE_IN = 0.35
local WIDTH, HEIGHT = 380, 70
local ICON = "Interface\\Icons\\Spell_Nature_MoonKey"

local frame, anim, animStart = nil, nil, 0

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
    open:SetPoint("BOTTOMRIGHT", -10, 10)
    open:SetText(L["Window"])
    open:SetScript("OnClick", function() LP.ShowUI() T.Dismiss() end)
    frame.open = open

    -- close button: the toast stays until this X is clicked
    local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
    close:SetSize(22, 22)
    close:SetPoint("TOPRIGHT", -2, -2)
    close:SetScript("OnClick", function() T.Dismiss() end)
    frame.close = close

    frame:SetScript("OnClick", function(self)
        local fn = self.onClick
        T.Dismiss()
        if fn then fn() end
    end)
    frame:SetScript("OnUpdate", function() T.OnUpdate() end)

    -- Position: about 20% above the bottom edge, as in GearQuest
    frame:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, math.floor((UIParent:GetHeight() or 768) * 0.20))
    return frame
end

local function Finish()
    local f = Ensure()
    f:Hide()
    f:SetAlpha(0)
    f.onClick, f.key, f.reqName, f.valid, f.maxAge = nil, nil, nil, nil, nil
    anim = nil
end

function T.Dismiss()
    Finish()
end

-- Dismiss the current toast if its key starts with prefix (e.g. "trade:")
function T.DismissKey(prefix)
    if frame and frame:IsShown() and frame.key and frame.key:find(prefix, 1, true) == 1 then Finish() end
end

-- Dismiss the current toast if it is a request toast for this player
function T.DismissRequest(name)
    if frame and frame:IsShown() and frame.reqName and name and LP.SameName(frame.reqName, name) then Finish() end
end

local lastCheck = 0
function T.OnUpdate()
    if not frame or not frame:IsShown() then return end
    if anim == "in" then
        local t = GetTime() - animStart
        frame:SetAlpha(math.min(1, t / FADE_IN))
        if t >= FADE_IN then anim = "hold" frame:SetAlpha(1) end
    end
    -- relevance check twice a second: gone when its subject is no longer relevant or it is too old
    local now = GetTime()
    if now - lastCheck < 0.5 then return end
    lastCheck = now
    if frame.maxAge and now - frame.shownAt > frame.maxAge then return Finish() end
    if frame.valid then
        local ok, res = pcall(frame.valid)
        if ok and not res then Finish() end
    end
end

-- Show a message. It replaces whatever toast is currently shown.
function T.Push(item)
    local f = Ensure()
    f.icon:SetTexture(item.icon or ICON)
    f.title:SetText(item.title or "")
    f.line:SetText(item.line or "")
    f.hint:SetText(item.hint or "")
    f.onClick, f.key, f.reqName = item.onClick, item.key, item.reqName
    f.valid, f.maxAge, f.shownAt = item.valid, item.maxAge, GetTime()
    if not f:IsShown() then
        f:SetAlpha(0)
        f:Show()
        anim, animStart = "in", GetTime()
    end
end

-- New request: large area. Depending on status: click = invite, or info only.
function T.Request(req)
    local box = req.label or (req.req and L["Box, skill %d"]:format(req.req)) or L["Box unknown"]
    local item = { key = "req:" .. req.name, reqName = req.name, title = L["New request"], line = req.name .. "  ·  " .. box }
    local st = req.status
    -- relevant while the request is still in the list with the same status (invited -> joined/timeout, removed, expired ...)
    item.valid = function()
        if req.status ~= st then return false end
        for _, r in ipairs(LP.requests) do if r == req then return true end end
        return false
    end
    if st == "invited" then
        item.hint = L["Will be invited automatically"]
        item.maxAge = 60   -- in test mode the invite never times out by itself
    elseif st == "grouped" then
        item.hint = L["Already in your group"]
        item.maxAge = 8
    elseif st == "toohigh" then
        return   -- nothing to do about it: no popup
    elseif st == "queued" then
        item.hint = L["Waiting - click: invite now"]
        item.onClick = function() LP.TryInvite(req) end
    else
        item.hint = L["Click: invite"]
        item.onClick = function() LP.TryInvite(req) end
    end
    T.Push(item)
end

-- Tip received. From the customer in the group this is part of the "trade complete" toast.
function T.Tip(name, copper, how)
    if LP.partner and LP.SameName(name, LP.partner) then return T.Trade(name, copper) end
    T.Push({ title = L["Tip"], line = (name or "?") .. "  ·  |cffffd100" .. LP.Money(copper) .. "|r",
        hint = (how == "later" and L["Thank-you follows when you leave"]) or (how == "sent" and L["Thank-you message sent"]) or "", icon = "Interface\\Icons\\INV_Misc_Coin_01",
        maxAge = 10 })
end

-- A trade with the customer in the group is complete (with or without tip). Click = thank + leave the group.
-- Closed automatically when the group ends (see LP.HandleLeave).
function T.Trade(name, copper)
    -- the order holds the total tip of this customer (several boxes/trades in a row)
    local r = LP.FindRequest(name)
    local total = math.max(copper or 0, r and r.tipTotal or 0)
    local tip = total > 0
    local f = LP.db and LP.db.finder
    local thankPending = tip and f and f.thanks and not (r and r.thanked)
    T.Push({ key = "trade:" .. tostring(name), title = L["Trade complete"],
        line = tostring(name) .. "  ·  " .. (tip and ("|cffffd100" .. LP.Money(total) .. "|r") or L["No tip"]),
        hint = thankPending and L["Click: thank & leave group"] or L["Click: leave group"],
        icon = tip and "Interface\\Icons\\INV_Misc_Coin_01" or nil,
        -- relevant while this customer is still in the group
        valid = function() return LP.partner ~= nil and LP.SameName(name, LP.partner) end,
        onClick = function() if LP.partner and (LP.IsDry() or LP.InGroup()) then LP.DoLeave() end end })
end

-- The timed announcement was blocked by the game (channel posts need a click): offer a click instead
function T.AdDue()
    T.Push({ key = "ad:due", title = L["Announcement due"], line = L["The game only allows announcements on a click"],
        hint = L["Click: announce now"], icon = "Interface\\Icons\\INV_Misc_Note_01", maxAge = 120,
        valid = function() return LP.db.ad.auto and not LP.InGroup() end,
        onClick = function() LP.lastAd = nil LP.PostAd(true) end })
end

-- Customer put a box in the trade that needs more skill than you have. Click = tell the customer.
function T.BoxTooHigh(link, msg, who, need, have)
    T.Push({ key = "high:" .. tostring(link), title = L["Box too high"], line = msg, hint = L["Click: tell the customer"],
        icon = "Interface\\Icons\\INV_Misc_Key_03",
        -- relevant while the trade window is open and that box is still offered
        valid = function()
            if not (TradeFrame and TradeFrame:IsShown()) then return false end
            for slot = 1, 7 do if GetTradeTargetItemLink and GetTradeTargetItemLink(slot) == link then return true end end
            return false
        end,
        onClick = who and function()
            local req = who and LP.FindRequest(who)
            LP.Whisper((req and req.sender) or who, L["Sorry, your box needs lockpicking %d, but my skill is only %d."]:format(need, have))
        end or nil })
end
