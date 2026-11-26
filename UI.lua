-- Picky / UI.lua : main window in the Forever look (Blizzard window template like HealKit),
-- icon tabs on the right edge (Requests | Guide | Settings), minimap button with state.
local ADDON, LP = ...
local L = LP.L

local ICON_PICK = "Interface\\Icons\\Spell_Nature_MoonKey"
local win, pages, tabs = nil, {}, {}
local rows = {}
local refreshers = {}      -- functions that reload the settings widgets from the DB

-- Copy window: WoW cannot write to the clipboard, so show the text in a selectable box (Ctrl+C, then Esc)
local copyBox
local function ShowCopyBox(text)
    if not copyBox then
        local f = CreateFrame("Frame", "PickyCopyFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        f:SetSize(520, 360)
        f:SetPoint("CENTER")
        f:SetFrameStrata("FULLSCREEN_DIALOG")
        f:EnableMouse(true)
        f:SetMovable(true)
        f:RegisterForDrag("LeftButton")
        f:SetScript("OnDragStart", f.StartMoving)
        f:SetScript("OnDragStop", f.StopMovingOrSizing)
        if f.SetBackdrop then
            f:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true, tileSize = 32, edgeSize = 16, insets = { left = 5, right = 5, top = 5, bottom = 5 } })
        end
        f.hint = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        f.hint:SetPoint("TOPLEFT", 16, -14)
        f.hint:SetText(L["Press Ctrl+C to copy, then Esc"])
        local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        close:SetPoint("TOPRIGHT", -2, -2)
        local sf = CreateFrame("ScrollFrame", "PickyCopyScroll", f, "UIPanelScrollFrameTemplate")
        sf:SetPoint("TOPLEFT", 16, -40)
        sf:SetPoint("BOTTOMRIGHT", -34, 16)
        local eb = CreateFrame("EditBox", nil, sf)
        eb:SetMultiLine(true)
        eb:SetAutoFocus(false)
        eb:SetFontObject("ChatFontNormal")
        eb:SetWidth(460)
        eb:SetMaxLetters(0)
        eb:SetScript("OnEscapePressed", function() f:Hide() end)
        sf:SetScrollChild(eb)
        f.eb = eb
        tinsert(UISpecialFrames, "PickyCopyFrame")
        copyBox = f
    end
    copyBox:Show()
    copyBox.eb:SetText(text)
    copyBox.eb:HighlightText()
    copyBox.eb:SetFocus()
end

local currentTab = 1
local guideStage
local ROWS = 7

-- Build the window -----------------------------------------------------------------------------
local function CreateWindow()
    local ok, f = pcall(CreateFrame, "Frame", "PickyFrame", UIParent, "ButtonFrameTemplate")
    if ok and f and f.SetTitle then
        -- Blizzard's own window template (like the friends window): copper frame, title bar, X, portrait
        f.onCloseCallback = function() f:Hide() return false end
        if f.TitleContainer then
            f.TitleContainer:ClearAllPoints()
            f.TitleContainer:SetPoint("TOPLEFT", 24, -1)
            f.TitleContainer:SetPoint("TOPRIGHT", -24, -1)
        end
        pcall(f.SetPortraitToAsset, f, ICON_PICK)
        if f.SetPortraitTextureSizeAndOffset then pcall(f.SetPortraitTextureSizeAndOffset, f, 62, -6, 9) end
        if f.Inset then   -- no button bar at the bottom: extend the dark area to the bottom
            f.Inset:ClearAllPoints()
            f.Inset:SetPoint("TOPLEFT", 4, -60)
            f.Inset:SetPoint("BOTTOMRIGHT", -6, 4)
        end
    else
        -- fallback in case the client does not have the template
        f = CreateFrame("Frame", "PickyFrame", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 8, right = 8, top = 8, bottom = 8 },
        })
        local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        title:SetPoint("TOP", 0, -14)
        f.SetTitle = function(_, t) title:SetText(t) end
        local x = CreateFrame("Button", nil, f, "UIPanelCloseButton")
        x:SetPoint("TOPRIGHT", -4, -4)
    end
    return f
end

local function SavePos()
    local point, _, _, x, y = win:GetPoint(1)
    LP.db.ui.winPos = { point = point, x = x, y = y }
end

-- Icon tab (pattern HealKit Tabs.lua / Forever professions window)
local function CreateTab(parent)
    local ok, tab = pcall(CreateFrame, "Frame", nil, parent, "LargeSideTabButtonTemplate")
    if ok and tab and tab.Icon then return tab end
    tab = CreateFrame("Frame", nil, parent)
    tab:SetSize(40, 40)
    tab.Icon = tab:CreateTexture(nil, "ARTWORK")
    tab.Icon:SetPoint("CENTER")
    tab.Icon:SetSize(36, 36)
    tab.SelectedTexture = tab:CreateTexture(nil, "OVERLAY")
    tab.SelectedTexture:SetAllPoints()
    tab.SelectedTexture:SetColorTexture(1, 0.82, 0, 0.25)
    tab:SetScript("OnMouseUp", function(self, button)
        if self.customMouseUpHandler then self.customMouseUpHandler(self, button, true) end
    end)
    tab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(self.tooltipText)
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    tab.SetCustomOnMouseUpHandler = function(self, fn) self.customMouseUpHandler = fn end
    return tab
end

local function NewPage()
    local p = CreateFrame("Frame", nil, win)
    p:SetPoint("TOPLEFT", win, "TOPLEFT", 16, -68)
    p:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -16, 14)
    p:Hide()
    return p
end

local function FS(parent, font, text)
    local fs = parent:CreateFontString(nil, "OVERLAY", font or "GameFontHighlight")
    fs:SetJustifyH("LEFT")
    if text then fs:SetText(text) end
    return fs
end

-- Skill bar. Header bar: the scale is what you can reach NOW = the lower of your rank limit and your level limit (5 x level), so "165 / 175".
-- Guide bar (fullScale): the whole route 0-300 without numbers (faint marks where the stages change); the chips below name the stages.
-- Blue = trained skill, green = bonus from gear/buffs. Mouse over: all numbers.
local function MakeSkillBar(parent, w, h, fullScale)
    local bar = CreateFrame("StatusBar", nil, parent)
    bar.fullScale = fullScale
    bar:SetSize(w, h)
    bar.w = w
    bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    bar:SetStatusBarColor(0.80, 0.62, 0.10)   -- amber: fits the copper window frame
    bar:SetMinMaxValues(0, 300)
    bar.bg = bar:CreateTexture(nil, "BACKGROUND")
    bar.bg:SetAllPoints()
    bar.bg:SetColorTexture(0, 0, 0, 0.6)
    bar.bonus = bar:CreateTexture(nil, "OVERLAY")
    bar.bonus:SetColorTexture(0.35, 0.80, 0.40, 1)
    bar.bonus:SetSize(1, h)
    bar.rankTick = bar:CreateTexture(nil, "OVERLAY")
    bar.rankTick:SetColorTexture(1, 1, 1, 0.9)
    bar.rankTick:SetSize(2, h)
    bar.levelTick = bar:CreateTexture(nil, "OVERLAY")
    bar.levelTick:SetColorTexture(1, 0.6, 0.1, 0.9)
    bar.levelTick:SetSize(2, h)
    bar.label = FS(bar, "GameFontHighlightSmall")
    bar.label:SetPoint("CENTER", 0, 0)
    return bar
end

local function UpdateSkillBar(bar)
    local base = LP.skillBase or LP.Skill()
    local bonus = LP.skillBonus or 0
    if LP.skillNotLearned then base, bonus = 0, 0 end
    base = math.max(0, math.min(300, base))
    bonus = math.max(0, bonus)
    local max = (LP.skillMax and LP.skillMax > 0) and math.min(300, LP.skillMax) or 300
    local level = tonumber(LP.Game.UnitLevel()) or 1
    local levelCap = math.min(300, level * 5)
    local reach = LP.SkillReach(LP.skillMax, level, base)
    local scale = bar.fullScale and 300 or reach
    bonus = math.min(bonus, scale - math.min(base, scale))
    bar.info = { base = base, bonus = bonus, max = max, levelCap = levelCap, reach = reach }
    bar:SetMinMaxValues(0, scale)
    bar:SetValue(math.min(base, scale))
    bar.bonus:ClearAllPoints()
    bar.bonus:SetPoint("LEFT", bar, "LEFT", bar.w * math.min(base, scale) / scale, 0)
    bar.bonus:SetWidth(math.max(1, bar.w * bonus / scale))
    bar.bonus:SetShown(bonus > 0)
    bar.rankTick:ClearAllPoints()
    bar.rankTick:SetPoint("LEFT", bar, "LEFT", math.min(bar.w - 2, bar.w * max / 300), 0)
    bar.rankTick:SetShown(false)
    bar.levelTick:ClearAllPoints()
    bar.levelTick:SetPoint("LEFT", bar, "LEFT", math.min(bar.w - 2, bar.w * levelCap / 300), 0)
    bar.levelTick:SetShown(false)
    local num = bonus > 0 and ("%d |cff4de88a+%d|r"):format(base, bonus) or tostring(base)
    if LP.skillNotLearned then num = "0" end
    bar.label:SetText(bar.fullScale and "" or ("%s / %d"):format(num, reach))   -- the guide bar is only the route: the numbers are in the header
end

-- Page 1: Requests --------------------------------------------------------------------------------
-- Two tabs: Open (running orders) and Done (everything finished, stored permanently).
-- Done orders stay until you delete them (x per order or "Delete finished").
local view, offset, armedAt = "open", 0, nil
local RefreshRequests

-- Line 2 of an order: date (Done only) · boxes · tip · duration, otherwise the original message
local function Summary(r)
    local parts = {}
    if not LP.OPEN_STATUS[r.status] and r.stamp then parts[#parts + 1] = date("%d.%m. %H:%M", r.stamp) end
    if (r.boxes or 0) > 0 then parts[#parts + 1] = L["Boxes %d"]:format(r.boxes) end
    if (r.tipTotal or 0) > 0 then parts[#parts + 1] = "|cffffd100" .. LP.Money(r.tipTotal) .. "|r" end
    if r.joinStamp and r.endStamp then parts[#parts + 1] = LP.Mmss(r.endStamp - r.joinStamp) end
    if (r.boxes or 0) == 0 and (r.tipTotal or 0) == 0 and r.msg then parts[#parts + 1] = r.msg end
    return table.concat(parts, "  ·  ")
end

local function BuildRequests(p)
    p.ad = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    p.ad:SetSize(110, 24)
    p.ad:SetPoint("TOPRIGHT", 0, 0)
    p.ad:SetText(L["Announce"])
    p.ad:SetScript("OnClick", function() LP.PostAd(true) end)

    p.ad:SetSize(110, 24)   -- the channel choices are in the settings (Channels)
    p.leave = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    p.leave:SetSize(70, 20)
    p.leave:SetPoint("TOPRIGHT", 0, -28)
    p.leave:SetText(L["Leave"])
    p.leave:SetScript("OnClick", function() LP.LeaveNow() end)
    p.leave:Hide()
    p.now = FS(p, "GameFontNormal")
    p.now:SetPoint("TOPLEFT", 0, -30)
    p.now:SetPoint("RIGHT", p, "RIGHT", -80, 0)
    p.now:SetWordWrap(false)
    p.queue = FS(p, "GameFontHighlightSmall")
    p.queue:SetPoint("TOPLEFT", 0, -48)
    p.queue:SetPoint("RIGHT", p, "RIGHT", -80, 0)
    p.queue:SetWordWrap(false)

    -- Tabs Open / Done
    p.tabOpen = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    p.tabOpen:SetSize(90, 22)
    p.tabOpen:SetPoint("TOPLEFT", 0, -1)
    p.tabOpen:SetScript("OnClick", function() view, offset, armedAt = "open", 0, nil RefreshRequests() end)
    p.tabDone = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    p.tabDone:SetSize(90, 22)
    p.tabDone:SetPoint("LEFT", p.tabOpen, "RIGHT", 4, 0)
    p.tabDone:SetScript("OnClick", function() view, offset, armedAt = "done", 0, nil RefreshRequests() end)
    p.range = FS(p, "GameFontDisableSmall")
    p.range:SetPoint("TOPRIGHT", 0, -32)
    p.range:SetJustifyH("RIGHT")

    p.empty = FS(p, "GameFontDisable")
    p.empty:SetPoint("CENTER", 0, -10)
    p.empty:SetJustifyH("CENTER")

    for i = 1, ROWS do
        local r = CreateFrame("Frame", nil, p)
        r:SetSize(408, 42)
        r:SetPoint("TOPLEFT", 0, -74 - (i - 1) * 46)
        r.bg = r:CreateTexture(nil, "BACKGROUND")
        r.bg:SetAllPoints()
        r.bg:SetColorTexture(1, 1, 1, 0.05)

        r.x = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
        r.x:SetSize(22, 22)
        r.x:SetPoint("RIGHT", -4, 0)
        r.x:SetText("x")
        r.x:SetScript("OnClick", function() if r.req then LP.RemoveOrder(r.req) end end)
        r.w = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
        r.w:SetSize(30, 22)
        r.w:SetPoint("RIGHT", r.x, "LEFT", -2, 0)
        r.w:SetText("/w")
        r.w:SetScript("OnClick", function()
            if r.req then
                local target = r.req.sender or r.req.name
                if ChatFrame_SendTell then ChatFrame_SendTell(target) else ChatFrame_OpenChat("/w " .. target .. " ") end   -- also with two-part names
            end
        end)
        r.inv = CreateFrame("Button", nil, r, "UIPanelButtonTemplate")
        r.inv:SetSize(68, 22)
        r.inv:SetPoint("RIGHT", r.w, "LEFT", -2, 0)
        r.inv:SetText(L["Invite"])
        r.inv:SetScript("OnClick", function() if r.req then LP.TryInvite(r.req) end end)

        r.name = FS(r, "GameFontNormal")
        r.name:SetPoint("TOPLEFT", 8, -6)
        r.name:SetPoint("RIGHT", r.inv, "LEFT", -6, 0)
        r.name:SetWordWrap(false)
        r.msg = FS(r, "GameFontHighlightSmall")
        r.msg:SetPoint("TOPLEFT", 8, -23)
        r.msg:SetPoint("RIGHT", r.inv, "LEFT", -6, 0)
        r.msg:SetWordWrap(false)
        rows[i] = r
    end

    -- Mouse wheel: scroll through long lists
    p:EnableMouseWheel(true)
    p:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta
        RefreshRequests()
    end)

    -- bottom: statistics, Delete finished
    p.clear = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    p.clear:SetSize(150, 20)
    p.clear:SetPoint("BOTTOMRIGHT", 0, 0)
    p.clear:SetScript("OnClick", function()
        if armedAt and GetTime() - armedAt < 4 then   -- a second click within 4 seconds confirms
            armedAt, offset = nil, 0
            LP.ClearDone()
        else
            armedAt = GetTime()
        end
        RefreshRequests()
    end)
end

function RefreshRequests()
    local p = pages[1]
    if not p or not LP.db then return end
    local st = LP.GetState()
    if st.phase == "grouped" then
        local r = st.current
        p.now:SetText("|cff4de88a" .. L["In group"] .. ":|r " .. r.name .. (r.joinedAt and ("  ·  " .. LP.Mmss(GetTime() - r.joinedAt)) or "") .. ((LP.leaveAt and LP.leaveAt > GetTime()) and ("  ·  |cffffd100" .. L["Leaving in %d s"]:format(math.ceil(LP.leaveAt - GetTime())) .. "|r") or ""))
    elseif st.phase == "invited" then
        p.now:SetText("|cff00bdf2" .. L["Invited"] .. ":|r " .. st.current.name)
    elseif st.on then
        p.now:SetText(L["Free - waiting for requests"])
    else
        p.now:SetText("")   -- "Finder is off" is already shown at the switch in the header
    end
    p.leave:SetShown(st.phase == "grouped")
    p.queue:SetText(st.waiting > 0 and (L["Queue"] .. ": " .. table.concat(st.waitingNames, ", ")) or "")
    if win and win.stats then win.stats:SetText(L["Picked %d   ·   Tips %s"]:format(st.picked or 0, LP.Money(st.tips or 0))) end

    -- Split orders into Open / Done (LP.requests is newest first)
    local open, done = {}, {}
    for _, r in ipairs(LP.requests) do
        if LP.OPEN_STATUS[r.status] then open[#open + 1] = r else done[#done + 1] = r end
    end
    local function Tab(btn, label, n, active)
        btn:SetText((active and "|cffffd100" or "") .. label:format(n) .. (active and "|r" or ""))
    end
    Tab(p.tabOpen, L["Open (%d)"], #open, view == "open")
    Tab(p.tabDone, L["Done (%d)"], #done, view == "done")

    local list = (view == "open") and open or done
    offset = math.max(0, math.min(offset, #list - ROWS))
    p.range:SetText(#list > ROWS and ("%d-%d / %d"):format(offset + 1, math.min(#list, offset + ROWS), #list) or "")
    p.empty:SetText(view == "open" and (LP.IsRogue() and L["empty.requests"] or LP.NonRogueQuote()) or L["Nothing finished yet."])
    p.empty:SetShown(#list == 0)

    for i = 1, ROWS do
        local r, q = rows[i], list[offset + i]
        r.req = q
        if q then
            local s = LP.STATUS[q.status] or LP.STATUS.new
            local need = q.req and ("  |cff9aa0ad· " .. L["needs"] .. " " .. q.req .. "|r") or ""
            local box = q.label and ("  |cff00bdf2" .. q.label .. "|r") or ""
            r.name:SetText(q.name .. "  |cff" .. s[2] .. s[1] .. "|r" .. need .. box)
            r.msg:SetText(Summary(q))
            -- also for "invited" and "timeout": invite again if the first invite did not arrive or was not accepted
            r.inv:SetShown(q.status == "new" or q.status == "manual" or q.status == "queued" or q.status == "invited" or q.status == "timeout")
            r:SetAlpha(view == "open" and 1 or 0.8)
            r:Show()
        else
            r:Hide()
        end
    end

    -- Delete only in the Done tab; a second click confirms
    p.clear:SetShown(view == "done" and #done > 0)
    p.clear:SetText((armedAt and GetTime() - armedAt < 4) and L["Really delete?"] or L["Delete finished"])
end
-- Page 2: Guide ------------------------------------------------------------------------------------
-- Tabs: 1-4 = the skill stages, 5 = all boxes by skill. Content sits in a scroll frame made of pooled pieces:
-- spot cards (zone, coordinates, Map button, box icons with tooltip), callouts (red warning, green tip, blue info), box rows.
local GUIDE_TABS = 5
local GUIDE_W = 376
local guideFaction            -- "Alliance" | "Horde" | nil = both (faction unknown): the guide shows the places of your own faction
local guidePool = { cards = {}, callouts = {}, rows = {} }
local CALLOUT = {   -- bar color, background, glyph
    warn = { { 0.95, 0.25, 0.25 }, { 0.35, 0.05, 0.05, 0.6 }, "!", "ff5959" },
    tip  = { { 0.30, 0.91, 0.54 }, { 0.05, 0.25, 0.12, 0.6 }, "+", "4de88a" },
    info = { { 0.00, 0.74, 0.95 }, { 0.00, 0.18, 0.25, 0.6 }, "i", "00bdf2" },
}
local FACTION_TAG = { A = "|cff4a8bff" .. "Alliance" .. "|r", H = "|cffff4a4a" .. "Horde" .. "|r" }

-- The window has no way to measure wrapped text in the tests, so estimate: characters per line of the given width
local function TextHeight(text, width, lineH)
    local plain = tostring(text):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")
    local chars = select(2, plain:gsub("[^\128-\191]", ""))
    return math.max(1, math.ceil(chars / math.floor(width / 6.4))) * (lineH or 12)
end

-- Height of a wrapped text: ask the game (GetStringHeight after SetText); where that gives no number (test runner) fall back to the estimate
local function MeasuredHeight(fs, text, width, lineH)
    local ok, h = pcall(fs.GetStringHeight, fs)
    if ok and type(h) == "number" and h > 0 then return math.ceil(h) end
    return TextHeight(text, width, lineH)
end

local function BoxTip(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    local shown = false
    if self.item then shown = pcall(GameTooltip.SetHyperlink, GameTooltip, "item:" .. self.item) end
    if not shown then GameTooltip:SetText(self.label or "?", 1, 1, 1) end
    if self.hint then GameTooltip:AddLine(self.hint, 0.8, 0.8, 0.8, true) end
    local skill = LP.Skill()
    if self.skill and self.skill > 1 then
        local ok = skill >= self.skill
        GameTooltip:AddLine(L["Needs skill %d"]:format(self.skill), ok and 0.3 or 1, ok and 0.9 or 0.35, ok and 0.55 or 0.35)
    elseif self.skill then
        GameTooltip:AddLine(L["No skill requirement"], 0.8, 0.8, 0.8)
    end
    GameTooltip:Show()
end

local function NewIconButton(parent)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(28, 28)
    b.tex = b:CreateTexture(nil, "ARTWORK")
    b.tex:SetAllPoints()
    b.hl = b:CreateTexture(nil, "HIGHLIGHT")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0.25)
    b.req = FS(b, "GameFontHighlightSmall")
    b.req:SetPoint("BOTTOMRIGHT", 2, 0)
    b:SetScript("OnEnter", BoxTip)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    return b
end

-- Fill an icon button from a box entry: { item = id | iconItem = id, name, skill, hint }
local function FillIcon(b, e)
    local icon = LP.Game.ItemIcon(e.item or e.iconItem) or "Interface\\Icons\\INV_Misc_QuestionMark"
    b.tex:SetTexture(icon)
    b.item = e.item
    b.label, b.hint, b.skill = e.name, e.hint, e.skill
    local ok = (not e.skill) or LP.Skill() >= e.skill
    b.tex:SetDesaturated(not ok)
    b.req:SetText(e.skill and e.skill > 1 and ((ok and "|cff4de88a" or "|cffff5959") .. e.skill .. "|r") or "")
    b:Show()
end

local function ZoneName(spot)
    return LP.Game.MapName(spot.zone) or ("#" .. tostring(spot.zone))
end

-- Plain piece of the guide list: no frame, a faint line under it (the window around it already has the Blizzard look)
local function NewPanel(parent)
    local f = CreateFrame("Frame", nil, parent)
    f.line = f:CreateTexture(nil, "BACKGROUND")
    f.line:SetPoint("BOTTOMLEFT", 0, 0)
    f.line:SetPoint("BOTTOMRIGHT", 0, 0)
    f.line:SetHeight(1)
    f.line:SetColorTexture(1, 0.82, 0, 0.18)
    return f
end

local function NewCard(parent)
    local c = NewPanel(parent)
    c:SetWidth(GUIDE_W)
    c.title = FS(c, "GameFontNormal")
    c.title:SetPoint("TOPLEFT", 8, -7)
    c.title:SetWidth(GUIDE_W - 90)
    c.sub = FS(c, "GameFontHighlightSmall")
    c.sub:SetPoint("TOPLEFT", 8, -24)
    c.sub:SetWidth(GUIDE_W - 90)
    c.map = CreateFrame("Button", nil, c, "UIPanelButtonTemplate")
    c.map:SetSize(60, 22)
    c.map:SetPoint("TOPRIGHT", -6, -6)
    c.map:SetText(L["Map"])
    c.map:SetScript("OnClick", function(self)
        local s = self:GetParent().spot
        if not s then return end
        local name = ZoneName(s)
        LP.Game.OpenMap(s.zone)
        if s.x and LP.Game.SetWaypoint(s.zone, s.x, s.y, name .. " - " .. s.where) then
            LP.Print(L["Pin set: %s (%.1f, %.1f)"]:format(name .. " - " .. s.where, s.x, s.y))
        else
            LP.Print(L["Map opened: %s"]:format(name))
        end
    end)
    c.map:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Click: open the map and set a pin"])
        GameTooltip:Show()
    end)
    c.map:SetScript("OnLeave", function() GameTooltip:Hide() end)
    c.note = FS(c, "GameFontHighlightSmall")
    c.note:SetWidth(GUIDE_W - 16)
    c.note:SetJustifyV("TOP")
    c.icons = {}
    return c
end

-- Tips sit in the game's dialog frame, tinted bronze to match the window border, the kind shows in the sign on the left
local TIP_BACKDROP = { bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 16, insets = { left = 4, right = 4, top = 4, bottom = 4 } }
local function NewCallout(parent)
    local c = CreateFrame("Frame", nil, parent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    if c.SetBackdrop then
        c:SetBackdrop(TIP_BACKDROP)
        c:SetBackdropBorderColor(0.85, 0.55, 0.25, 1)   -- the border texture is silver: tint it bronze like the window frame
        c:SetBackdropColor(0.55, 0.40, 0.28, 1)         -- slightly warm dark body
    end
    c:SetWidth(GUIDE_W)
    c.glyph = FS(c, "GameFontNormalLarge")
    c.glyph:SetPoint("LEFT", 12, 0)
    c.text = FS(c, "GameFontHighlight")
    c.text:SetPoint("TOPLEFT", 32, -8)
    c.text:SetWidth(GUIDE_W - 42)
    c.text:SetJustifyV("TOP")
    return c
end

local function NewRow(parent)
    local r = CreateFrame("Frame", nil, parent)
    r:SetSize(GUIDE_W, 30)
    r.icon = NewIconButton(parent)
    r.icon:SetParent(r)
    r.icon:SetPoint("LEFT", 2, 0)
    r.name = FS(r, "GameFontHighlight")
    r.name:SetPoint("LEFT", 38, 0)
    r.name:SetWidth(GUIDE_W - 150)
    r.skill = FS(r, "GameFontHighlightSmall")
    r.skill:SetPoint("RIGHT", -4, 0)
    return r
end

local function Pooled(list, i, make, parent)
    if not list[i] then list[i] = make(parent) end
    return list[i]
end

local function BuildGuide(p)
    p.sub = FS(p, "GameFontHighlightSmall")
    p.sub:SetPoint("TOPLEFT", 0, -2)

    -- The route: one button per stage, filled by your progress inside it (green = done, blue = you are here, empty = ahead).
    -- The last button is the list of all boxes. Clicking a stage shows its places.
    p.chips = {}
    local gap = 4
    local stageW = 78
    for i = 1, GUIDE_TABS do
        local w = (i <= #LP.GUIDE) and stageW or (408 - #LP.GUIDE * (stageW + gap))
        local x = (i <= #LP.GUIDE) and (i - 1) * (stageW + gap) or #LP.GUIDE * (stageW + gap)
        local c = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")   -- the normal button look, the progress is tinted inside it
        c:SetSize(w, 26)
        c:SetPoint("TOPLEFT", x, -22)
        c.w = w
        c.fill = c:CreateTexture(nil, "OVERLAY")   -- thin progress line along the bottom edge
        c.fill:SetPoint("BOTTOMLEFT", 6, 5)
        c.fill:SetHeight(2)
        c.fill:SetWidth(1)
        c:SetScript("OnClick", function() guideStage = i LP.RefreshUI() end)
        p.chips[i] = c
    end

    local sf = CreateFrame("ScrollFrame", "PickyGuideScroll", p, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 0, -58)
    sf:SetPoint("BOTTOMRIGHT", -24, 40)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(GUIDE_W, 600)
    sf:SetScrollChild(child)
    p.scroll, p.child = sf, child

    p.bags = FS(p, "GameFontHighlightSmall")
    p.bags:SetPoint("BOTTOMLEFT", 0, 0)
    p.bags:SetWidth(408)
    p.bags:SetJustifyV("BOTTOM")
end

-- Layout helpers: each adds one piece below the previous one and returns the new y
local function PlaceCallout(y, kind, text)
    local used = guidePool.calloutsUsed + 1
    guidePool.calloutsUsed = used
    local c = Pooled(guidePool.callouts, used, NewCallout, guidePool.parent)
    local look = CALLOUT[kind] or CALLOUT.info
    c.glyph:SetText("|cff" .. look[4] .. look[3] .. "|r")
    c.text:SetText(text)
    local h = math.max(30, MeasuredHeight(c.text, text, GUIDE_W - 42, 13) + 18)
    c:SetHeight(h)
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", 0, y)
    c:Show()
    return y - h - 6
end

local function PlaceCard(y, spot)
    local used = guidePool.cardsUsed + 1
    guidePool.cardsUsed = used
    local c = Pooled(guidePool.cards, used, NewCard, guidePool.parent)
    c.spot = spot
    local badge = spot.faction and (" |cff9aa0ad[|r" .. (spot.faction == "A" and "|cff4a8bff" .. L["Alliance"] or "|cffff4a4a" .. L["Horde"]) .. "|r|cff9aa0ad]|r") or ""
    local star = spot.best and ("  |cff4de88a* " .. L["Best spot"] .. "|r") or ""
    c.title:SetText(spot.where .. badge .. star)
    local coords = spot.x and ("  |cff9aa0ad(%.1f, %.1f)|r"):format(spot.x, spot.y) or ""
    c.sub:SetText("|cff00bdf2" .. ZoneName(spot) .. "|r" .. coords)
    c.note:SetText(spot.note or "")
    local noteH = MeasuredHeight(c.note, spot.note or "", GUIDE_W - 16, 12)
    c.note:ClearAllPoints()
    c.note:SetPoint("TOPLEFT", 8, -42)
    for i = 1, #c.icons do c.icons[i]:Hide() end
    local iconsY = 42 + noteH + 6
    for i, e in ipairs(spot.boxes or {}) do
        if not c.icons[i] then c.icons[i] = NewIconButton(c) end
        local b = c.icons[i]
        FillIcon(b, e)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 8 + (i - 1) * 34, -iconsY)
    end
    local h = iconsY + (#(spot.boxes or {}) > 0 and 34 or 0) + 4
    c:SetHeight(h)
    c:ClearAllPoints()
    c:SetPoint("TOPLEFT", 0, y)
    c:Show()
    return y - h - 6
end

local function PlaceRow(y, entry)
    local used = guidePool.rowsUsed + 1
    guidePool.rowsUsed = used
    local r = Pooled(guidePool.rows, used, NewRow, guidePool.parent)
    FillIcon(r.icon, entry)
    local ok = LP.Skill() >= (entry.skill or 1)
    r.name:SetText((ok and "|cffffffff" or "|cff9aa0ad") .. entry.name .. "|r" .. (entry.pickpocket and ("  |cff9aa0ad(" .. L["Pick Pocket only"] .. ")|r") or ""))
    r.skill:SetText(entry.skill and entry.skill > 1 and ((ok and "|cff4de88a" or "|cffff5959") .. L["Needs skill %d"]:format(entry.skill) .. "|r") or "")
    r:ClearAllPoints()
    r:SetPoint("TOPLEFT", 0, y)
    r:Show()
    return y - 32
end

-- All boxes from LP.BOXES, sorted by required skill (data from the client tooltips, see Data.lua)
local function SortedBoxes()
    local list = {}
    for id, b in pairs(LP.BOXES) do
        list[#list + 1] = { item = id, skill = b[1], name = LP.BoxName(id), pickpocket = (b[2]:find("Junkbox") or b[2] == "Battered Chest") and true or nil }
    end
    table.sort(list, function(a, b) if a.skill ~= b.skill then return a.skill < b.skill end return a.item < b.item end)
    return list
end

local function RefreshGuide()
    local p = pages[2]
    local skill = LP.Skill()
    local cur = LP.StageForSkill(skill)
    guideStage = guideStage or cur
    local f = LP.Game.Faction()
    guideFaction = (f == "Alliance" or f == "Horde") and f or nil
    p.sub:SetText(L["Current stage %s  ·  %d points to the next"]:format(LP.GUIDE[cur].title, math.max(0, LP.GUIDE[cur].to - skill)))
    for i, c in ipairs(p.chips) do
        local st = LP.GUIDE[i]
        local label = st and st.title or L["All boxes"]
        local frac = 0
        if st then frac = math.max(0, math.min(1, (skill - st.from) / (st.to - st.from))) end
        local done, here = st and skill >= st.to, st and i == cur
        c.fill:SetWidth(math.max(1, (c.w - 12) * frac))
        c.fill:SetShown(st ~= nil and frac > 0)
        if done then c.fill:SetColorTexture(0.35, 0.80, 0.40, 1) else c.fill:SetColorTexture(1, 0.82, 0, 1) end
        if i == guideStage then c:LockHighlight() else c:UnlockHighlight() end
        c:SetText((here and "|cff4de88a" or "") .. label .. (here and "|r" or ""))
    end

    -- content
    guidePool.parent = p.child
    for _, list in pairs({ guidePool.cards, guidePool.callouts, guidePool.rows }) do
        for _, f in ipairs(list) do f:Hide() end
    end
    guidePool.cardsUsed, guidePool.calloutsUsed, guidePool.rowsUsed = 0, 0, 0
    local y = -2
    local st = LP.GUIDE[guideStage]
    if st then
        local kind, advice = LP.GuideAdvice(skill, LP.Game.UnitLevel())
        if kind then y = PlaceCallout(y, kind, advice) end
        y = PlaceCallout(y, "info", L["Skill %d needs level %d."]:format(st.to, st.levelReq))
        for _, t in ipairs(st.tips or {}) do y = PlaceCallout(y, t[1], t[2]) end
        for _, spot in ipairs(st.spots) do
            if (not guideFaction) or (not spot.faction) or (spot.faction == (guideFaction == "Alliance" and "A" or "H")) then
                y = PlaceCard(y, spot)
            end
        end
    elseif guideStage == 5 then
        y = PlaceCallout(y, "info", L["Boxes by required skill. Hover for details."])
        for _, e in ipairs(SortedBoxes()) do y = PlaceRow(y, e) end
    end
    p.child:SetHeight(math.max(10, -y + 4))

    local found = {}
    for bag = 0, 4 do
        local n = (C_Container and C_Container.GetContainerNumSlots(bag)) or (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
        for slot = 1, n do
            local locked, req = LP.IsLockedItem(bag, slot)
            if locked then
                local id = (C_Container and C_Container.GetContainerItemID(bag, slot)) or (GetContainerItemID and GetContainerItemID(bag, slot))
                local name = id and LP.BoxName(id) or L["Box"]
                local ok = (not req) or skill >= req
                found[#found + 1] = ("|cff%s%s%s|r"):format(ok and "4de88a" or "ff5959", name, req and (" (" .. req .. ")") or "")
            end
        end
    end
    p.bags:SetText("|cffffd100" .. L["In your bags"] .. ":|r  " .. (#found > 0 and table.concat(found, "   ") or L["no locked boxes"]))
end

-- Page 3: Settings -------------------------------------------------------------------------------
local function BuildSettings(p)
    local sf = CreateFrame("ScrollFrame", "PickySettingsScroll", p, "UIPanelScrollFrameTemplate")
    sf:SetPoint("TOPLEFT", 0, 0)
    sf:SetPoint("BOTTOMRIGHT", -24, 0)
    local child = CreateFrame("Frame", nil, sf)
    child:SetSize(380, 900)
    sf:SetScrollChild(child)

    local y = -2
    local function Section(title)
        y = y - 10
        local t = FS(child, "GameFontNormalLarge", title)
        t:SetPoint("TOPLEFT", 0, y)
        y = y - 24
    end
    local function Check(label, tbl, key, onchange)
        local cb = CreateFrame("CheckButton", nil, child, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", 0, y)
        local t = FS(child, "GameFontHighlight", label)
        t:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        local function Holder() return tbl and LP.db[tbl] or LP.db end   -- tbl = nil: top-level setting
        cb:SetScript("OnClick", function(self)
            Holder()[key] = self:GetChecked() and true or false
            if onchange then onchange(Holder()[key]) end
            LP.RefreshAll()
        end)
        refreshers[#refreshers + 1] = function() cb:SetChecked(Holder()[key] and true or false) end
        y = y - 26
    end
    local function Edit(label, tbl, key, numeric, w)
        local t = FS(child, "GameFontNormalSmall", label)
        t:SetPoint("TOPLEFT", 4, y)
        y = y - 16
        local e = CreateFrame("EditBox", nil, child, "InputBoxTemplate")
        e:SetSize(w or 364, 22)
        e:SetPoint("TOPLEFT", 10, y)
        e:SetAutoFocus(false)
        e:SetMaxLetters(255)
        e.PickyEdit = true
        local function Load() e:SetText(tostring(LP.db[tbl][key] or "")) e:SetCursorPosition(0) end
        local function Save()
            local v = e:GetText()
            if numeric then v = tonumber(v) or LP.defaults[tbl][key] end
            LP.db[tbl][key] = v
            Load()
        end
        e:SetScript("OnEnterPressed", function(s) Save() s:ClearFocus() end)
        e:SetScript("OnEscapePressed", function(s) Load() s:ClearFocus() end)
        e:SetScript("OnEditFocusLost", Save)
        refreshers[#refreshers + 1] = function() if not e:HasFocus() then Load() end end   -- do not overwrite while typing
        y = y - 30
    end

    Section(L["Duty"])
    Check(L["Invite players automatically"], "finder", "autoInvite")
    Check(L["Only one customer at a time (queue)"], "finder", "onlyWhenFree")
    Check(L["Also invite when no box is mentioned"], "finder", "inviteUnknown")
    Check(L["Accept invites automatically"], "finder", "autoAccept")
    Check(L["Reply to whispers that need a higher skill"], "finder", "tooHighReply")

    Section(L["Channels"])
    do
        -- Generic channel menu: one button, a list with a tick per source. get/set decide what a tick means.
        local rowY = y   -- both buttons sit on the same line (below the explanation)
        local function ChannelMenu(x, sources, isOn, setOn, btnText)
            local btn = CreateFrame("Button", nil, child, "UIPanelButtonTemplate")
            btn:SetSize(178, 24)
            btn:SetPoint("TOPLEFT", x, rowY)
            local menu = CreateFrame("Frame", nil, child, BackdropTemplateMixin and "BackdropTemplate" or nil)
            menu:SetFrameStrata("FULLSCREEN_DIALOG")
            menu:SetPoint("TOPLEFT", btn, "BOTTOMLEFT", 0, -2)
            menu:SetSize(230, 40)
            menu:EnableMouse(true)
            menu:Hide()
            if menu.SetBackdrop then
                menu:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
                menu:SetBackdropColor(0.05, 0.05, 0.08, 0.97)
                menu:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
            end
            menu:SetScript("OnUpdate", function(self)   -- a fresh click elsewhere closes it (the choice is saved already)
                local down = IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")
                if down and not self.wasDown and not self:IsMouseOver() and not btn:IsMouseOver() then self:Hide() end
                self.wasDown = down
            end)
            menu:SetScript("OnShow", function(self) self.wasDown = true end)
            menu.rows = {}
            menu.empty = menu:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
            menu.empty:SetPoint("TOPLEFT", 8, -8)
            menu.empty:SetText(L["You have not joined any channels yet."])
            local function Fill()
                local list = sources()
                for i, src in ipairs(list) do
                    local row = menu.rows[i]
                    if not row then
                        row = CreateFrame("CheckButton", nil, menu, "UICheckButtonTemplate")
                        row:SetSize(22, 22)
                        row:SetHitRectInsets(0, -180, 0, 0)
                        row:SetPoint("TOPLEFT", 6, -6 - (i - 1) * 22)
                        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                        row.text:SetPoint("LEFT", row, "RIGHT", 2, 0)
                        row:SetScript("OnClick", function(self) setOn(self.key, self:GetChecked() and true or false) LP.RefreshAll() end)
                        menu.rows[i] = row
                    end
                    row.key = src.key
                    row.text:SetText(src.label)
                    row:SetChecked(isOn(src.key))
                    row:Show()
                end
                for i = #list + 1, #menu.rows do menu.rows[i]:Hide() end
                menu.empty:SetShown(#list == 0)
                menu:SetHeight(12 + math.max(1, #list) * 22)
            end
            btn:SetScript("OnClick", function() if menu:IsShown() then menu:Hide() else Fill() menu:Show() end end)
            p:HookScript("OnHide", function() menu:Hide() end)
            -- Always current: button text and (if open) the list are rebuilt on every refresh, on every channel event and once a second while the menu is open
            local function Update()
                if not LP.db then return end
                local n, total = 0, 0
                for _, src in ipairs(sources()) do
                    total = total + 1
                    if isOn(src.key) then n = n + 1 end
                end
                btn:SetText(btnText:format(n, total))
                if menu:IsShown() then Fill() end
            end
            refreshers[#refreshers + 1] = Update
            local ev = CreateFrame("Frame")
            for _, e in ipairs({ "CHANNEL_UI_UPDATE", "CHAT_MSG_CHANNEL_NOTICE", "CHAT_MSG_CHANNEL_NOTICE_USER", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
                pcall(ev.RegisterEvent, ev, e)
            end
            ev:SetScript("OnEvent", function() C_Timer.After(0.5, Update) end)   -- the game updates its channel list a moment after the event
            local acc = 0
            menu:HookScript("OnUpdate", function(_, dt)
                acc = acc + dt
                if acc >= 1 then acc = 0 Update() end
            end)
        end

        local hint = FS(child, "GameFontNormalSmall", L["Listen in: Picky only reacts to the ticked chats (whispers are always read). Advertise in: the Announce button posts only into the ticked channels."])
        hint:SetPoint("TOPLEFT", 4, y)
        hint:SetWidth(360)
        hint:SetJustifyH("LEFT")
        y = y - 44
        rowY = y

        -- 1) Where Picky LISTENS for requests (everything by default, whispers are always read)
        ChannelMenu(10,
            LP.ListenSources, LP.ReadChannelOn, LP.SetReadChannel, L["Listen in (%d/%d)"])

        -- 2) Where Picky ADVERTISES (the Announce button, only ticked channels)
        ChannelMenu(196,
            LP.AdvertiseSources, LP.AdSourceOn, LP.SetAdChannel, L["Advertise in (%d/%d)"])
        y = y - 34
    end

    Section(L["Group"])
    Check(L["Whisper a greeting after joining"], "finder", "welcome")
    Check(L["Leave the group after picking"], "finder", "autoLeave")
    Check(L["Thank-you message for tips"], "finder", "thanks")
    Edit(L["Leave after the last trade, in seconds"], "finder", "leaveDelay", true, 120)
    Edit(L["Leave without activity after seconds (0 = off)"], "finder", "idleLeave", true, 120)

    Section(L["Display"])
    Check(L["Pop-up (toast) for requests and tips"], "ui", "toast")
    Check(L["Chat line for new requests"], "ui", "chatLine")
    Check(L["Flash the taskbar"], "ui", "flash")
    Check(L["Sound for new requests"], "finder", "sound")
    -- Choose the request sound: a click plays it and selects it (marked with *)
    do
        local lbl = FS(child, "GameFontNormalSmall", L["Request sound (click to hear and choose)"])
        lbl:SetPoint("TOPLEFT", 28, y)
        y = y - 18
        local btns = {}
        for i, snd in ipairs(LP.ALERT_SOUNDS) do
            local b = CreateFrame("Button", nil, child, "UIPanelButtonTemplate")
            b:SetSize(82, 22)
            b:SetPoint("TOPLEFT", 14 + ((i - 1) % 4) * 85, y - math.floor((i - 1) / 4) * 26)
            b:SetText(snd[2])
            b:SetScript("OnClick", function()
                LP.db.ui.alertSound = snd[1]
                LP.PlayAlertSound(snd[1])
                LP.RefreshAll()
            end)
            btns[i] = b
        end
        y = y - math.ceil(#LP.ALERT_SOUNDS / 4) * 26 - 8
        refreshers[#refreshers + 1] = function()
            local cur = LP.db.ui.alertSound or "AUCTION_WINDOW_OPEN"
            for i, snd in ipairs(LP.ALERT_SOUNDS) do btns[i]:SetText(snd[2] .. (snd[1] == cur and " *" or "")) end
        end
    end
    Check(L["Tooltip hint on locks"], "pick", "hint")
    Check(L["Minimap button"], "ui", "minimap", function() LP.UpdateMinimap() end)

    -- Window size
    local st = FS(child, "GameFontNormalSmall", L["Window size"])
    st:SetPoint("TOPLEFT", 4, y)
    y = y - 22
    local ok, slider = pcall(CreateFrame, "Slider", "PickyScaleSlider", child, "OptionsSliderTemplate")
    if ok and slider then
        slider:SetPoint("TOPLEFT", 14, y)
        slider:SetWidth(220)
        slider:SetMinMaxValues(70, 130)
        slider:SetValueStep(5)
        if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
        local low, high, text = _G["PickyScaleSliderLow"], _G["PickyScaleSliderHigh"], _G["PickyScaleSliderText"]
        if low then low:SetText("70%") end
        if high then high:SetText("130%") end
        -- While dragging only show the number; the window size is applied only on RELEASE.
        -- (If the window scaled while dragging, the slider would move away under the mouse.)
        slider:SetScript("OnValueChanged", function(self, v)
            v = math.floor(v + 0.5)
            if text then text:SetText(v .. "%") end
        end)
        slider:SetScript("OnMouseUp", function(self)
            local v = math.floor(self:GetValue() + 0.5)
            if LP.db and win and v ~= LP.db.ui.scale then
                LP.db.ui.scale = v
                win:SetScale(v / 100)
            end
        end)
        refreshers[#refreshers + 1] = function() slider:SetValue(LP.db.ui.scale or 100) end
    end
    y = y - 34

    Section(L["Messages"])
    Edit(L["Greeting (after joining the group)"], "finder", "welcomeText")
    Edit(L["Thanks (for tips)"], "finder", "thanksText")
    Edit(L["Skill too high reply ({need} = needed skill, {skill} = your skill)"], "finder", "tooHighText")

    Section(L["Announcement"])
    Edit(L["Text ({skill} = skill, {pick} = spell link, {city} = current city; links can be inserted with Shift-click)"], "ad", "text")

    child:SetHeight(-y + 20)
end

local function RefreshSettings()
    for _, f in ipairs(refreshers) do f() end
end

-- Page 4: Debug (only visible in debug mode) -------------------------------------------------------------------------
local MAX_REAL = 6
local testSlots = {}
local simLocked = true

local function SlotHint(tt, req)
    if req and not LP.skillEstimated and LP.Skill() < req then
        tt:AddLine("|cff00ccffPicky|r  |cffff5959" .. L["Your skill is not enough (needs %s)"]:format(tostring(req)) .. "|r")
    else
        tt:AddLine("|cff00ccffPicky|r  |cff4de88a" .. L["Right-click to pick"] .. "|r")
    end
end

local function GetRealSlot(p, i)
    local b = testSlots[i]
    if b then return b end
    b = CreateFrame("Button", nil, p, "SecureActionButtonTemplate")   -- same mechanism as the click area in the inventory
    b:SetSize(36, 36)
    b:SetPoint("TOPLEFT", 44 * i, -164)
    b:RegisterForClicks("RightButtonUp", "RightButtonDown")
    b:SetAttribute("type", "spell")
    b:HookScript("PreClick", function(self, button)   -- also remember here what is picked (grace period after success)
        if button == "RightButton" and self.bag then
            LP.lastPickTarget = { bag = self.bag, slot = self.slot, t = GetTime() }
        end
    end)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    b:SetScript("OnEnter", function(self)
        if not self.bag then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetBagItem(self.bag, self.slot)
        GameTooltip:AddLine(" ")
        SlotHint(GameTooltip, self.req)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:Hide()
    testSlots[i] = b
    return b
end

local function RefreshTestSlots()
    local p = pages[4]
    if not p or not p.testHint or InCombatLockdown() then return end   -- only change secure buttons outside combat
    if not LP.db.debug then   -- test area only in test mode
        for i = 1, MAX_REAL do local b = testSlots[i] if b then b:Hide() end end
        p.testHint:SetText(L["Turn on the test mode to use the test area."])
        return
    end
    local list = {}
    for bag = 0, 4 do
        local n = (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag)) or (GetContainerNumSlots and GetContainerNumSlots(bag)) or 0
        for slot = 1, n do
            if #list < MAX_REAL then
                local locked, req = LP.IsLockedItem(bag, slot)
                if locked then list[#list + 1] = { bag = bag, slot = slot, req = req } end
            end
        end
    end
    for i = 1, MAX_REAL do
        local b, d = GetRealSlot(p, i), list[i]
        if d then
            b.bag, b.slot, b.req = d.bag, d.slot, d.req
            b:SetAttribute("spell", LP.PickName())
            b:SetAttribute("target-bag", d.bag)
            b:SetAttribute("target-slot", d.slot)
            local icon
            if C_Container and C_Container.GetContainerItemInfo then
                local info = C_Container.GetContainerItemInfo(d.bag, d.slot)
                icon = info and info.iconFileID
            end
            b.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            b:Show()
        else
            b.bag, b.slot, b.req = nil, nil, nil
            b:SetAttribute("target-bag", nil)
            b:SetAttribute("target-slot", nil)
            b:Hide()
        end
    end
    p.testHint:SetText(#list == 0 and L["No locked boxes in your bags - only the simulated box is available."]
        or L["The first slot is a simulated box. The other slots are your real locked boxes: right-click picks them with the same mechanism as in your bags."])
    -- if the mouse is still on a slot, update the tooltip immediately
    for i = 1, MAX_REAL do
        local b = testSlots[i]
        if b and b:IsShown() and b:IsMouseOver() then b:GetScript("OnEnter")(b) end
    end
end

-- Buttons that fit their text: a row of buttons (same y) is laid out again from its first button, each one as wide as its text needs
-- (never narrower than the width given), the next one 4 pixels behind it. German texts are longer than the English ones.
local function FitButtonRows(list)
    local rows = {}
    for _, e in ipairs(list) do
        local key = tostring(e.y)
        rows[key] = rows[key] or {}
        table.insert(rows[key], e)
    end
    for _, row in pairs(rows) do
        table.sort(row, function(a, b) return a.x < b.x end)
        local cur = row[1].x
        for _, e in ipairs(row) do
            local fs = e.b.GetFontString and e.b:GetFontString()
            local tw = fs and fs.GetStringWidth and fs:GetStringWidth()
            local w = (type(tw) == "number") and math.max(e.w, math.ceil(tw) + 22) or e.w
            e.b:SetWidth(w)
            e.b:ClearAllPoints()
            e.b:SetPoint("TOPLEFT", cur, e.y)
            cur = cur + w + 4
        end
    end
end

local function BuildDebug(p)
    local fitList = {}
    local function Btn(parent, label, w, x, y, fn)
        local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        b:SetSize(w, 22)
        b:SetPoint("TOPLEFT", x, y)
        b:SetText(label)
        b:SetScript("OnClick", function() fn() end)
        fitList[parent == p and "page" or "tools"] = fitList[parent == p and "page" or "tools"] or {}
        table.insert(fitList[parent == p and "page" or "tools"], { b = b, w = w, x = x, y = y })
        return b
    end

    -- Big test mode switch: on = everything is only simulated + log runs, off = Picky works normally
    local big = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
    big:SetSize(40, 40)
    big:SetPoint("TOPLEFT", -6, 4)
    big:SetScript("OnClick", function(self) LP.SetTestMode(self:GetChecked()) end)
    p.mode = big
    local bl = FS(p, "GameFontNormalLarge", L["Test mode"])
    bl:SetPoint("LEFT", big, "RIGHT", 2, 0)
    p.modeInfo = FS(p, "GameFontHighlightSmall")
    p.modeInfo:SetPoint("TOPLEFT", 4, -40)
    p.modeInfo:SetWidth(404)
    p.modeInfo:SetJustifyV("TOP")

    -- Tools: only usable in test mode
    local tools = CreateFrame("Frame", nil, p)
    tools:SetPoint("TOPLEFT", 0, -72)
    tools:SetPoint("BOTTOMRIGHT", p, "TOPRIGHT", 0, -244)
    p.tools = tools
    p.toolButtons = {}
    local function ToolBtn(label, w, x, y, fn)
        local b = Btn(tools, label, w, x, y, fn)
        p.toolButtons[#p.toolButtons + 1] = b
        return b
    end

    -- Simulate request (goes through the real detection, always as dry run)
    local h = FS(tools, "GameFontNormalSmall", L["Simulate a request"])
    h:SetPoint("TOPLEFT", 2, 0)
    local e = CreateFrame("EditBox", nil, tools, "InputBoxTemplate")
    e:SetSize(228, 22)
    e:SetPoint("TOPLEFT", 10, -16)
    e:SetAutoFocus(false)
    e:SetMaxLetters(200)
    e:SetText("hi can u open some low level chersts for me?")
    e:SetCursorPosition(0)
    e:SetScript("OnEnterPressed", function(s) LP.SimulateChat(s:GetText(), false) s:ClearFocus() end)
    e:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    p.simEdit = e
    ToolBtn(L["As chat"], 66, 242, -15, function() LP.SimulateChat(e:GetText(), false) end)
    ToolBtn(L["As whisper"], 86, 312, -15, function() LP.SimulateChat(e:GetText(), true) end)

    ToolBtn(L["Customer joins"], 98, 0, -44, function() LP.SimulateJoin() end)
    ToolBtn(L["Tip"], 70, 102, -44, function() LP.SimulateTip(12500) end)
    ToolBtn(L["Pick succeeded"], 112, 176, -44, function() LP.SimulatePick() end)
    ToolBtn(L["Customer leaves"], 114, 292, -44, function() LP.SimulateLeave() end)

    -- Test area for the right-click (simulated box; the real boxes appear as slots next to it)
    local t = FS(tools, "GameFontNormalSmall", L["Right-click test area"])
    t:SetPoint("TOPLEFT", 2, -74)
    local sim = CreateFrame("Button", nil, tools)
    sim:SetSize(36, 36)
    sim:SetPoint("TOPLEFT", 0, -92)
    sim:RegisterForClicks("RightButtonUp")
    sim.icon = sim:CreateTexture(nil, "ARTWORK")
    sim.icon:SetAllPoints()
    sim.icon:SetTexture("Interface\\Icons\\INV_Box_01")
    sim.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    sim.tag = FS(sim, "GameFontNormalSmall", "sim")
    sim.tag:SetPoint("BOTTOMRIGHT", -2, 2)
    sim:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    local function SimTooltip(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Practice box (simulated)"])
        GameTooltip:AddLine(simLocked and L["Locked"] or L["Unlocked"], 1, simLocked and 0.2 or 1, 0.2)
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cff00ccffPicky|r  |cff4de88a" .. (simLocked and L["Right-click to pick (simulated)"] or L["Right-click to open (simulated)"]) .. "|r")
        GameTooltip:Show()
    end
    sim:SetScript("OnEnter", SimTooltip)
    sim:SetScript("OnLeave", function() GameTooltip:Hide() end)
    sim:SetScript("OnClick", function(self)
        if simLocked then
            LP.Debug("pick", "simulated right-click: pick on the practice box")
            LP.SimulatePick()
            simLocked = false
        else
            LP.Debug("pick", "simulated right-click: practice box opened, it is locked again now")
            simLocked = true
        end
        self.icon:SetDesaturated(not simLocked)
        SimTooltip(self)   -- update the tooltip immediately without moving the mouse
    end)
    p.simSlot = sim

    p.testHint = FS(p, "GameFontHighlightSmall")
    p.testHint:SetPoint("TOPLEFT", 2, -206)
    p.testHint:SetWidth(404)
    p.testHint:SetJustifyV("TOP")

    -- Log: title, chat switch and "Clear log" in one header row directly above the field
    local lh = FS(p, "GameFontNormalSmall", L["Log"])
    lh:SetPoint("TOPLEFT", 2, -252)
    local cb = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
    cb:SetSize(22, 22)
    cb:SetPoint("LEFT", lh, "RIGHT", 12, 0)
    cb:SetScript("OnClick", function(self) LP.db.debugChat = self:GetChecked() and true or false end)
    p.chatCb = cb
    local cl = FS(p, "GameFontHighlightSmall", L["Also print to chat"])
    cl:SetPoint("LEFT", cb, "RIGHT", 2, 0)

    local log = CreateFrame("ScrollingMessageFrame", nil, p)
    log:SetPoint("TOPLEFT", 0, -276)
    log:SetPoint("BOTTOMRIGHT", 0, 0)
    log:SetFontObject("GameFontHighlightSmall")
    log:SetJustifyH("LEFT")
    log:SetMaxLines(3000)
    log:SetFading(false)
    log:EnableMouseWheel(true)
    log:SetScript("OnMouseWheel", function(self, d) if d > 0 then self:ScrollUp() else self:ScrollDown() end end)
    local bg = log:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.45)
    p.log = log
    Btn(p, L["Clear log"], 110, 298, -250, function()
        wipe(LP.debugLog)
        log:Clear()
    end)
    Btn(p, L["Copy"], 90, 204, -250, function()
        local lines = {}
        for i, line in ipairs(LP.debugLog) do
            lines[i] = (tostring(line):gsub("|cn[^:|]*:", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""))
        end
        ShowCopyBox(#lines > 0 and table.concat(lines, "\n") or "(log is empty)")
    end)
    for _, line in ipairs(LP.debugLog) do log:AddMessage(line) end
    LP.OnDebugLine = function(line) log:AddMessage(line) end

    -- after picking / on changes in the bags rebuild the real slots
    LP.On("BAG_UPDATE_DELAYED", function() if pages[4] and pages[4]:IsShown() then RefreshTestSlots() end end)
    LP.On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit)
        if unit == "player" and pages[4] and pages[4]:IsShown() then LP.After(0.3, RefreshTestSlots) end
    end)
    for _, list in pairs(fitList) do FitButtonRows(list) end
end

local function RefreshDebug()
    local p = pages[4]
    local on = LP.db.debug and true or false
    p.mode:SetChecked(on)
    p.chatCb:SetChecked(LP.db.debugChat and true or false)
    if on then
        p.modeInfo:SetText("|cffff9d00" .. L["Test mode is ON: everything is simulated, nothing real is sent. The log below records what Picky does."] .. "|r")
    else
        p.modeInfo:SetText("|cff4de88a" .. L["Live: Picky works normally. Turn the test mode on to use the tools below."] .. "|r")
    end
    -- tools only usable in test mode
    p.tools:SetAlpha(on and 1 or 0.4)
    for _, b in ipairs(p.toolButtons) do
        if b.SetEnabled then b:SetEnabled(on) end
    end
    if p.simEdit.SetEnabled then pcall(p.simEdit.SetEnabled, p.simEdit, on) end
    if not on then p.simEdit:ClearFocus() end
    p.simSlot:EnableMouse(on)
    RefreshTestSlots()
end

-- Page 5: Developer (hidden, only via /picky dev) -------------------------------------------------------------------
-- Development only: self tests, hover check, diagnostics. Intentionally untranslated.
local RefreshDev   -- defined below BuildDev
local function BuildDev(p)
    local fitList = {}
    local function Btn(label, w, x, y, fn)
        local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        b:SetSize(w, 22)
        b:SetPoint("TOPLEFT", x, y)
        b:SetText(label)
        b:SetScript("OnClick", function() fn() end)
        table.insert(fitList, { b = b, w = w, x = x, y = y })
        return b
    end
    local h = FS(p, "GameFontNormalLarge", "Developer tools")
    h:SetPoint("TOPLEFT", 2, 0)
    local sub = FS(p, "GameFontHighlightSmall", "Hidden tab - toggle with /picky dev. Output appears here and in the chat.")
    sub:SetPoint("TOPLEFT", 2, -24)

    local out = CreateFrame("ScrollingMessageFrame", nil, p)
    out:SetPoint("TOPLEFT", 0, -264)
    out:SetPoint("BOTTOMRIGHT", 0, 0)
    out:SetFontObject("GameFontHighlightSmall")
    out:SetJustifyH("LEFT")
    out:SetMaxLines(3000)
    out:SetFading(false)
    out:EnableMouseWheel(true)
    out:SetScript("OnMouseWheel", function(self, d) if d > 0 then self:ScrollUp() else self:ScrollDown() end end)
    local bg = out:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.45)
    p.out = out
    -- developer log lines (internals) are shown here, never in the Test tab
    for _, line in ipairs(LP.devLog) do out:AddMessage(line) end
    LP.OnDevLine = function(line) out:AddMessage(line) end
    -- Everything printed into the output field (self test result, diagnostics, errors) is also kept in LP.devLog with a time,
    -- so that Copy contains exactly what you see.
    local function Out(line)
        out:AddMessage(line)
        local log = LP.devLog
        log[#log + 1] = date("%H:%M:%S") .. " " .. line
        if #log > 3000 then table.remove(log, 1) end
    end

    -- also write LP.Print output into this field
    local function Capture(fn)
        local old = LP.Print
        LP.Print = function(m) old(m) Out(tostring(m)) end
        local ok, err = pcall(fn)
        LP.Print = old
        if not ok then Out("|cffff5959error:|r " .. tostring(err)) end
    end
    local function P(fmt, ...) LP.Print(string.format(fmt, ...)) end

    local function DumpState()
        local st = LP.GetState()
        local db = LP.db
        P("version %s | locale %s | german %s", tostring(LP.version), GetLocale(), tostring(LP.isGerman))
        P("test mode %s | dev %s | forceDry %s | partnerSim %s | dry now %s",
            tostring(db.debug), tostring(db.dev), tostring(LP.forceDry), tostring(LP.partnerSim), tostring(LP.IsDry()))
        P("finder %s | phase %s | waiting %d | open %d", tostring(st.on), tostring(st.phase), st.waiting, st.open)
        P("skill %d = base %d + bonus %d (source %s, estimated %s)", LP.Skill(), LP.skillBase or 0, LP.skillBonus or 0,
            tostring(LP.skillSource), tostring(LP.skillEstimated))
        P("requests %d | feed %d | log %d lines", #LP.requests, #LP.feed, #LP.debugLog)
        P("pending %s | partner %s", tostring(LP.pending and LP.pending.name), tostring(LP.partner))
        P("stats picked %d | tips %s | invited %d | thanked %d", LP.db.stats.picked, LP.Money(LP.db.stats.tips), LP.db.stats.invited, LP.db.stats.thanked)
    end
    local function ClientInfo()
        local version, build, bdate, toc = GetBuildInfo()
        local _, class = UnitClass("player")
        P("client %s build %s (%s) | interface %s | locale %s", tostring(version), tostring(build), tostring(bdate), tostring(toc), GetLocale())
        P("class %s | level %d | combat lockdown %s | rogue %s", tostring(class), UnitLevel("player"), tostring(InCombatLockdown()), tostring(LP.IsRogue()))
        P("APIs: C_TooltipInfo %s | C_Container %s | C_TradeSkillUI %s | TooltipDataProcessor %s | FlashClientIcon %s",
            tostring(C_TooltipInfo ~= nil), tostring(C_Container ~= nil), tostring(C_TradeSkillUI ~= nil),
            tostring(TooltipDataProcessor ~= nil), tostring(FlashClientIcon ~= nil))
    end

    Btn("Run self tests", 110, 0, -46, function() Capture(function() LP.RunTests() end) end)
    Btn("Inspect hover (3 s)", 130, 114, -46, function()
        Out("inspecting what is under the mouse in 3 s ...")
        LP.After(3, function() Capture(function() LP.InspectHover() end) end)
    end)
    Btn("Skill diagnostics", 120, 248, -46, function() Capture(function() LP.SkillDiagnostics() end) end)
    Btn("Dump state", 110, 0, -74, function() Capture(DumpState) end)
    Btn("Client info", 110, 114, -74, function() Capture(ClientInfo) end)
    -- Output header row directly above the field (same place and size as in the Test tab): title, Copy, Clear
    local oh = FS(p, "GameFontNormalSmall", "Output")
    oh:SetPoint("TOPLEFT", 2, -244)
    Btn("Clear output", 110, 298, -238, function() out:Clear() wipe(LP.devLog) end)
    Btn("Copy", 90, 204, -238, function()   -- Test-tab log + developer output in one list, sorted by time
        local function Clean(l) return (tostring(l):gsub("|cn[^:|]*:", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
        local a, b, lines = LP.debugLog, LP.devLog, {}
        local i, j = 1, 1
        while i <= #a or j <= #b do
            local ta, tb = a[i] and Clean(a[i]):match("^%d%d:%d%d:%d%d"), b[j] and Clean(b[j]):match("^%d%d:%d%d:%d%d")
            if a[i] and (not b[j] or (ta or "") <= (tb or "")) then lines[#lines + 1] = Clean(a[i]) i = i + 1
            else lines[#lines + 1] = Clean(b[j]) j = j + 1 end
        end
        ShowCopyBox(#lines > 0 and table.concat(lines, "\n") or "(both logs are empty)")
    end)
    local live = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
    live:SetSize(24, 24)
    live:SetPoint("TOPLEFT", 0, -100)
    local ll = FS(p, "GameFontHighlightSmall", "Keep a log in normal (live) mode too; saved on /reload or logout")
    ll:SetPoint("LEFT", live, "RIGHT", 2, 0)
    live:SetScript("OnClick", function(self) LP.db.logLive = self:GetChecked() and true or false end)
    p.liveCb = live

    -- Announcement tests
    Btn("Announce (test only)", 130, 0, -128, function()
        Capture(function()
            local old = LP.forceDry
            LP.forceDry = true   -- walks through the whole announcement path but sends NOTHING to any channel
            local ok, err = pcall(function() LP.lastAd = nil LP.PostAd(true) end)
            LP.forceDry = old
            LP.lastAd = nil
            if not ok then error(err, 0) end
        end)
    end)
    Btn("Announce from timer (3 s)", 160, 134, -128, function() Capture(function() LP.AdTest() end) end)

    -- Sound for a new request: click = play, Shift-click = use it (marked with *)
    local sh = FS(p, "GameFontHighlightSmall", "Request sound: click = play, Shift-click = use (* = in use)")
    sh:SetPoint("TOPLEFT", 2, -158)
    p.soundBtns = {}
    for i, snd in ipairs(LP.ALERT_SOUNDS) do
        local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        b:SetSize(49, 22)
        b:SetPoint("TOPLEFT", (i - 1) * 51, -178)
        b:SetText(snd[2])
        b:SetScript("OnClick", function()
            if IsShiftKeyDown() then
                LP.db.ui.alertSound = snd[1]
                Out("request sound: " .. snd[2])
                RefreshDev()
            end
            LP.PlayAlertSound(snd[1])
        end)
        p.soundBtns[i] = b
    end

    -- Language: switch between automatic (client language), English and German. The window texts are built once,
    -- so the UI is reloaded (/reload) to apply it; the choice is saved.
    local lg = FS(p, "GameFontHighlightSmall", "Language (reloads the UI):")
    lg:SetPoint("TOPLEFT", 2, -212)
    p.langBtns = {}
    local LANGS = { { nil, "Auto" }, { "en", "English" }, { "de", "Deutsch" } }
    p.langDefs = LANGS
    for i, lang in ipairs(LANGS) do
        local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        b:SetSize(80, 22)
        b:SetPoint("TOPLEFT", 140 + (i - 1) * 84, -208)
        b:SetText(lang[2])
        b:SetScript("OnClick", function()
            LP.db.lang = lang[1]
            ReloadUI()
        end)
        p.langBtns[i] = b
    end
    FitButtonRows(fitList)
    RefreshDev()
end

function RefreshDev()
    local p = pages[5]
    if p and p.liveCb then p.liveCb:SetChecked(LP.db.logLive and true or false) end
    if p and p.soundBtns then
        local cur = LP.db.ui.alertSound or "AUCTION_WINDOW_OPEN"
        for i, snd in ipairs(LP.ALERT_SOUNDS) do p.soundBtns[i]:SetText(snd[2] .. (snd[1] == cur and "*" or "")) end
    end
    if p and p.langBtns then
        for i, lang in ipairs(p.langDefs) do p.langBtns[i]:SetText(lang[2] .. (lang[1] == LP.db.lang and "*" or "")) end
    end
end-- Assemble the window ----------------------------------------------------------------------------------
-- Window title: "Picky · <tab>", plus a red TEST MODE marker on every tab while test mode is on
local function UpdateTitle()
    if not win then return end
    local titles = { L["Requests"], "Guide", L["Settings"], L["Test mode"], "Developer" }
    local t = "Picky  ·  " .. (titles[currentTab] or "")
    if LP.db.debug and currentTab ~= 4 then t = t .. "  ·  |cffff5959" .. L["Test mode"] .. "|r" end
    win:SetTitle(t)
end

local function SelectTab(i)
    currentTab = i
    for n, pg in ipairs(pages) do
        pg:SetShown(n == i)
        if tabs[n].SelectedTexture then tabs[n].SelectedTexture:SetShown(n == i) end
    end
    UpdateTitle()
    LP.RefreshUI()
end

-- Test tab is always there; when test mode changes only refresh
function LP.RefreshDebugTab()
    UpdateTitle()
    if win and win:IsShown() then LP.RefreshUI() end
end

-- show the Developer tab only when enabled via /picky dev
function LP.RefreshDevTab()
    if not win or not tabs[5] then return end
    tabs[5]:SetShown(LP.db.dev and true or false)
    if not LP.db.dev and currentTab == 5 then SelectTab(1) end
end

-- The box button (window header): one click does the next step on the next box in your bags: pick it or, once it is open, open it.
-- It is a secure button, so it can only be set up outside combat; the list behind it is LP.boxes (Pick.lua).
local ICON_CHEST = "Interface\\Icons\\INV_Misc_Bag_09"
local function UpdateBoxCooldown(b)
    -- In combat the client hands out "secret" numbers for cooldowns and casts: comparing them is an error (and the call comes from a
    -- tainted path). So nothing is read in combat, and anything that still goes wrong is swallowed. After combat the swipe is refreshed.
    if InCombatLockdown() then return end
    pcall(function()
        local start, dur
        local cs, ce = LP.Game.CastTimes()
        if cs and ce and ce > cs then start, dur = cs, ce - cs else start, dur = LP.Game.PickCooldown() end
        if start and dur and dur > 0 then b.cd:SetCooldown(start, dur) else b.cd:Clear() end
    end)
end
local function MakeBoxButton(parent)
    local b = CreateFrame("Button", "PickyBoxButton", parent, "SecureActionButtonTemplate")
    b:SetSize(30, 30)
    b:RegisterForClicks("AnyUp", "AnyDown")   -- the trigger depends on the client setting (down/up)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetAllPoints()
    b.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    b.icon:SetTexture(ICON_CHEST)
    b.glow = b:CreateTexture(nil, "OVERLAY")   -- yellow ring: there is something to do
    b.glow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    b.glow:SetBlendMode("ADD")
    b.glow:SetVertexColor(1, 0.85, 0.2)
    b.glow:SetPoint("CENTER")
    b.glow:SetSize(30 * 1.8, 30 * 1.8)
    b.glow:Hide()
    b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
    b.count:SetPoint("BOTTOMRIGHT", -2, 2)
    b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.cd:SetAllPoints()
    b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square")
    b:HookScript("PreClick", function(self)
        local e = self.entry
        if e and e.action == "pick" then
            LP.lastPickTarget = { bag = e.bag, slot = e.slot, t = GetTime() }   -- grace period after the pick (see Pick.lua)
        end
    end)
    b:HookScript("PostClick", function() LP.RefreshBoxes() end)
    b:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        local e = self.entry
        if e then
            GameTooltip:SetBagItem(e.bag, e.slot)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine("|cff00ccffPicky|r  |cff4de88a" .. (e.action == "pick" and L["Click: pick the next box"] or L["Click: open the next box"]) .. "|r")
            if #LP.boxes > 1 then GameTooltip:AddLine(L["%d boxes in your bags"]:format(#LP.boxes), 0.8, 0.8, 0.8) end
        else
            GameTooltip:AddLine("Picky", 1, 0.82, 0)
            GameTooltip:AddLine(L["No box to pick or open in your bags"], 1, 1, 1)
        end
        if (LP.boxesTooHigh or 0) > 0 then GameTooltip:AddLine(L["%d need more skill"]:format(LP.boxesTooHigh), 1, 0.5, 0.3) end
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
    b:SetScript("OnUpdate", function(self)
        if self.glow:IsShown() then self.glow:SetAlpha(0.55 + 0.45 * math.sin(GetTime() * 3)) end
    end)
    for _, ev in ipairs({ "SPELL_UPDATE_COOLDOWN", "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_SUCCEEDED",
        "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED" }) do
        LP.On(ev, function(_, unit) if (not unit or unit == "player") and win and win.box == b then UpdateBoxCooldown(b) end end)
    end
    return b
end

-- Set the box button up for the first box of the list (out of combat only: a secure button cannot be changed in combat).
function LP.ApplyBoxButton()
    local b = win and win.box
    if not b or InCombatLockdown() then return end
    b:SetShown(LP.IsRogue() and true or false)
    local e = LP.boxes and LP.boxes[1]
    b.entry = e
    if e then
        b.icon:SetTexture(LP.Game.ItemIcon(e.id) or ICON_CHEST)
        b.icon:SetDesaturated(false)
        if e.action == "pick" then
            b:SetAttribute("type", "spell")
            b:SetAttribute("spell", LP.PickName())
            b:SetAttribute("target-bag", e.bag)
            b:SetAttribute("target-slot", e.slot)
            b:SetAttribute("item", nil)
        else
            b:SetAttribute("type", "item")
            b:SetAttribute("item", e.bag .. " " .. e.slot)
            b:SetAttribute("spell", nil)
            b:SetAttribute("target-bag", nil)
            b:SetAttribute("target-slot", nil)
        end
        b.count:SetText(#LP.boxes > 1 and #LP.boxes or "")
        b.glow:Show()
    else
        b.icon:SetTexture(ICON_CHEST)
        b.icon:SetDesaturated(true)
        b:SetAttribute("type", nil)
        b.count:SetText("")
        b.glow:Hide()
    end
    UpdateBoxCooldown(b)
end

local function Build()
    if win then return end
    win = CreateWindow()
    win:SetSize(440, 520)
    local pos = LP.db.ui.winPos
    if type(pos) == "table" and pos.point and pos.x and pos.y then
        win:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
    else
        win:SetPoint("CENTER", 0, 60)
    end
    win:SetScale((LP.db.ui.scale or 100) / 100)
    win:SetFrameStrata("DIALOG")
    win:SetToplevel(true)
    win:HookScript("OnShow", function(self) self:Raise() LP.RefreshSkill() LP.RefreshUI() LP.RefreshBoxes() end)
    tinsert(UISpecialFrames, "PickyFrame")
    win:EnableMouse(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() SavePos() end)

    -- Header: skill + Finder switch
    win.skillText = FS(win, "GameFontHighlight")
    win.skillText:SetPoint("TOPLEFT", 76, -27)
    win.stats = FS(win, "GameFontNormalSmall")
    win.stats:SetPoint("TOPLEFT", 78, -54)
    win.bar = MakeSkillBar(win, 196, 12)
    win.bar:SetPoint("TOPLEFT", 78, -40)

    win.finder = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    win.finder:SetSize(100, 26)
    win.finder:SetPoint("TOPRIGHT", -58, -30)
    win.finder:SetScript("OnClick", function() LP.SetFinder(not LP.db.finder.enabled, true) end)
    win.box = MakeBoxButton(win)
    win.box:SetPoint("TOPRIGHT", -20, -28)

    pages[1], pages[2], pages[3], pages[4], pages[5] = NewPage(), NewPage(), NewPage(), NewPage(), NewPage()
    BuildRequests(pages[1])
    BuildGuide(pages[2])
    BuildSettings(pages[3])
    BuildDebug(pages[4])
    BuildDev(pages[5])

    local defs = {
        { icon = "Interface\\Icons\\INV_Misc_GroupNeedMore", tip = L["Requests"] },
        { icon = "Interface\\Icons\\INV_Misc_Book_09", tip = L["Guide: leveling lockpicking"] },
        { icon = "Interface\\Icons\\INV_Misc_Gear_01", tip = L["Settings"] },
        { icon = "Interface\\Icons\\INV_Misc_Wrench_01", tip = L["Test mode"] },
        { icon = "Interface\\Icons\\INV_Gizmo_01", tip = "Developer" },
    }
    for i, d in ipairs(defs) do
        local tab = CreateTab(win)
        tab:EnableMouse(true)
        tab.Icon:SetTexture(d.icon)
        if tab.SetFillToInterior then
            tab:SetFillToInterior(true, 50)
        else
            tab.Icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
        tab.tooltipText = d.tip
        tab:SetCustomOnMouseUpHandler(function(_, button, upInside)
            if button == "LeftButton" and upInside ~= false then SelectTab(i) end
        end)
        if i == 1 then
            tab:SetPoint("TOPLEFT", win, "TOPRIGHT", -2, -48)
        else
            tab:SetPoint("TOP", tabs[i - 1], "BOTTOM", 0, -3)
        end
        tabs[i] = tab
    end
    SelectTab(1)
    LP.RefreshDevTab()
    C_Timer.NewTicker(1, function() if win and win:IsShown() and currentTab == 1 then RefreshRequests() end end)   -- Countdowns
    win:Hide()
end

function LP.RefreshUI()
    if not win or not win:IsShown() or not LP.db then return end
    local skill = LP.Skill()
    local bonus = (LP.skillBonus and LP.skillBonus > 0) and (" |cff4de88a(+" .. LP.skillBonus .. ")|r") or ""
    UpdateSkillBar(win.bar)
    local est = LP.skillEstimated and "  |cffffd100" .. L["estimated"] .. "|r" or ""
    if LP.skillNotLearned then
        win.skillText:SetText(L["Lockpicking: not learned yet"])
    else
        win.skillText:SetText(L["Lockpicking %d%s / %d%s"]:format(LP.skillBase or skill, bonus, win.bar.info.reach, est))
    end
    local dutyLabel = LP.db.finder.enabled and ("|cff4de88a" .. L["On duty"] .. "|r") or L["Off duty"]
    win.finder:SetText(dutyLabel)
    if currentTab == 1 then RefreshRequests()
    elseif currentTab == 2 then RefreshGuide()
    elseif currentTab == 3 then RefreshSettings()
    elseif currentTab == 4 then RefreshDebug()
    else RefreshDev() end
end

function LP.ShowUI()
    Build()
    win:Show()
end

-- Open the window on the guide page (stage 1-4, 5 = all boxes; nil = the stage for your skill)
function LP.OpenGuide(stage)
    Build()
    guideStage = stage
    SelectTab(2)
    win:Show()
    LP.RefreshUI()
end

-- Current tab of the window (1-5); with a number it switches to that tab first. The self tests use it to put the window back as they found it.
function LP.UITab(i)
    if i and win then SelectTab(i) end
    return currentTab
end

function LP.ToggleUI()
    Build()
    if win:IsShown() then win:Hide() else win:Show() end
end

-- Shift-click on spell/item/link inserts it into the focused Picky text field
local function InsertIntoPickyEdit(link)
    local f = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    if f and f.PickyEdit and link then f:Insert(link) end
end
if ChatFrameUtil and ChatFrameUtil.InsertLink then
    hooksecurefunc(ChatFrameUtil, "InsertLink", InsertIntoPickyEdit)
elseif ChatEdit_InsertLink then
    hooksecurefunc("ChatEdit_InsertLink", InsertIntoPickyEdit)
end

-- Minimap button (with state) ----------------------------------------------------------------------------
local mm
-- true = rounded corner in this quadrant (order: top-right, top-left, bottom-right, bottom-left)
local SHAPES = {
    ["ROUND"] = { true, true, true, true },
    ["SQUARE"] = { false, false, false, false },
    ["CORNER-TOPLEFT"] = { false, false, false, true },
    ["CORNER-TOPRIGHT"] = { false, false, true, false },
    ["CORNER-BOTTOMLEFT"] = { false, true, false, false },
    ["CORNER-BOTTOMRIGHT"] = { true, false, false, false },
    ["SIDE-LEFT"] = { false, true, false, true },
    ["SIDE-RIGHT"] = { true, false, true, false },
    ["SIDE-TOP"] = { false, false, true, true },
    ["SIDE-BOTTOM"] = { true, true, false, false },
}
local function PlaceMinimap()
    local angle = math.rad(LP.db.ui.angle or 215)
    local x, y, q = math.cos(angle), math.sin(angle), 1
    if x < 0 then q = q + 1 end
    if y > 0 then q = q + 2 end
    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    local quad = SHAPES[shape] or SHAPES["ROUND"]
    local w = (Minimap:GetWidth() / 2) + 5
    local h = (Minimap:GetHeight() / 2) + 5
    if quad[q] then
        x, y = x * w, y * h
    else
        local dw = math.sqrt(2 * w ^ 2) - 10
        local dh = math.sqrt(2 * h ^ 2) - 10
        x = math.max(-w, math.min(x * dw, w))
        y = math.max(-h, math.min(y * dh, h))
    end
    mm:ClearAllPoints()
    mm:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

function LP.UpdateMinimap()
    if mm then mm:SetShown(LP.db.ui.minimap) end
end

-- State on the button: gray = Finder off, normal = on, green = customer in the group, number = waiting
function LP.UpdateMinimapState()
    if not mm or not LP.db then return end
    local st = LP.GetState()
    mm.icon:SetDesaturated(not st.on)
    if st.phase == "grouped" then
        mm.icon:SetVertexColor(0.5, 1, 0.6)
    elseif st.phase == "invited" then
        mm.icon:SetVertexColor(0.5, 0.85, 1)
    else
        mm.icon:SetVertexColor(1, 1, 1)
    end
    mm.badge:SetText(st.waiting > 0 and st.waiting or "")
    local n = LP.boxes and #LP.boxes or 0
    mm.boxBadge:SetText(n > 0 and n or "")
end

local function MinimapTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Picky", 1, 0.82, 0)
    local st = LP.GetState()
    GameTooltip:AddLine(L["Duty"] .. ": " .. (st.on and ("|cff4de88a" .. L["on"] .. "|r") or ("|cff9d9d9d" .. L["off"] .. "|r")), 1, 1, 1)
    if st.phase == "grouped" then
        GameTooltip:AddLine(L["In group"] .. ": " .. st.current.name, 1, 1, 1)
    elseif st.phase == "invited" then
        GameTooltip:AddLine(L["Invited"] .. ": " .. st.current.name, 1, 1, 1)
    end
    if st.waiting > 0 then GameTooltip:AddLine(L["Queue"] .. ": " .. st.waiting, 1, 1, 1) end
    if LP.boxes and #LP.boxes > 0 then GameTooltip:AddLine("|cffffd100" .. L["%d boxes in your bags"]:format(#LP.boxes) .. "|r", 1, 1, 1) end
    GameTooltip:AddLine(L["Picked %d  ·  Tips %s"]:format(st.picked or 0, LP.Money(st.tips or 0)), 0.7, 0.7, 0.7)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cffffd100" .. L["Click"] .. "|r " .. L["open window"], 1, 1, 1)
    GameTooltip:AddLine("|cffffd100" .. L["Right-click"] .. "|r " .. L["toggle duty"], 1, 1, 1)
    GameTooltip:AddLine("|cffffd100" .. L["Shift-click"] .. "|r " .. L["announce"], 1, 1, 1)
    GameTooltip:Show()
end

function LP.BuildMinimap()
    if mm then return end
    mm = CreateFrame("Button", "PickyMinimap", Minimap)
    mm:SetSize(31, 31)
    mm:SetFrameStrata("MEDIUM")
    mm:SetFrameLevel(8)
    mm:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    -- same structure as the usual minimap buttons: background, icon, ring
    local bg = mm:CreateTexture(nil, "BACKGROUND")
    bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    bg:SetSize(20, 20)
    bg:SetPoint("TOPLEFT", 7, -5)
    mm.icon = mm:CreateTexture(nil, "ARTWORK")
    mm.icon:SetTexture(ICON_PICK)
    mm.icon:SetSize(17, 17)
    mm.icon:SetPoint("TOPLEFT", 7, -6)
    mm.icon:SetTexCoord(0.05, 0.95, 0.05, 0.95)
    local ring = mm:CreateTexture(nil, "OVERLAY")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    ring:SetSize(50, 50)
    ring:SetPoint("TOPLEFT")
    mm.boxBadge = mm:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mm.boxBadge:SetPoint("BOTTOMRIGHT", mm, "TOPLEFT", 25, -22)   -- inside the round part of the button
    mm.boxBadge:SetTextColor(1, 0.9, 0.3)
    mm.badge = mm:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mm.badge:SetPoint("BOTTOMRIGHT", 2, 0)
    mm.badge:SetTextColor(1, 0.82, 0)

    mm:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    mm:RegisterForDrag("LeftButton")
    mm:SetScript("OnClick", function(_, b)
        if b == "RightButton" then
            LP.SetFinder(not LP.db.finder.enabled)
        elseif IsShiftKeyDown() then
            LP.PostAd(true)   -- a click is allowed to post to channels (a timer is not)
        else
            LP.ToggleUI()
        end
    end)
    mm:SetScript("OnDragStart", function(s)
        s:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local sc = Minimap:GetEffectiveScale()
            LP.db.ui.angle = math.deg(math.atan2(cy / sc - my, cx / sc - mx))
            PlaceMinimap()
        end)
    end)
    mm:SetScript("OnDragStop", function(s) s:SetScript("OnUpdate", nil) end)
    mm:SetScript("OnEnter", MinimapTooltip)
    mm:SetScript("OnLeave", function() GameTooltip:Hide() end)
    PlaceMinimap()
    LP.UpdateMinimap()
    LP.UpdateMinimapState()
end
