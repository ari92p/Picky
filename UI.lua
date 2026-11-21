-- Picky / UI.lua : Hauptfenster im Forever-Look (Blizzard-Fensterschablone wie HealKit),
-- Icon-Tabs am rechten Rand (Anfragen | Guide | Einstellungen), Minimap-Button mit Zustand.
local ADDON, LP = ...
local L = LP.L

local ICON_PICK = "Interface\\Icons\\Spell_Nature_MoonKey"
local win, pages, tabs = nil, {}, {}
local rows = {}
local refreshers = {}      -- Funktionen, die die Einstellungs-Widgets aus der DB neu laden
local currentTab = 1
local guideStage
local ROWS = 7

-- Fenster aufbauen -----------------------------------------------------------------------------
local function CreateWindow()
    local ok, f = pcall(CreateFrame, "Frame", "PickyFrame", UIParent, "ButtonFrameTemplate")
    if ok and f and f.SetTitle then
        -- Blizzards eigene Fensterschablone (wie das Freundefenster): Kupferrahmen, Titelleiste, X, Portrait
        f.onCloseCallback = function() f:Hide() return false end
        if f.TitleContainer then
            f.TitleContainer:ClearAllPoints()
            f.TitleContainer:SetPoint("TOPLEFT", 24, -1)
            f.TitleContainer:SetPoint("TOPRIGHT", -24, -1)
        end
        pcall(f.SetPortraitToAsset, f, ICON_PICK)
        if f.SetPortraitTextureSizeAndOffset then pcall(f.SetPortraitTextureSizeAndOffset, f, 62, -6, 9) end
        if f.Inset then   -- keine Button-Leiste unten: dunkles Feld bis unten ziehen
            f.Inset:ClearAllPoints()
            f.Inset:SetPoint("TOPLEFT", 4, -60)
            f.Inset:SetPoint("BOTTOMRIGHT", -6, 4)
        end
    else
        -- Notlösung, falls der Client die Schablone nicht hat
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

-- Icon-Tab (Muster HealKit Tabs.lua / Forevers Berufe-Fenster)
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

-- Seite 1: Anfragen --------------------------------------------------------------------------------
-- Zwei Reiter: Offen (laufende Aufträge) und Erledigt (alles Abgeschlossene, dauerhaft gespeichert).
-- Erledigte bleiben, bis du sie löschst (x je Auftrag oder "Erledigte löschen").
local view, offset, armedAt = "open", 0, nil
local RefreshRequests

-- Zeile 2 eines Auftrags: Datum (nur Erledigte) · Kisten · Trinkgeld · Dauer, sonst die ursprüngliche Nachricht
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

    -- Kanal-Auswahl: kleines Menü mit Häkchen für jeden beigetretenen Kanal
    p.ad:SetSize(100, 24)
    p.chan = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    p.chan:SetSize(95, 24)
    p.chan:SetPoint("RIGHT", p.ad, "LEFT", -4, 0)
    p.chan:SetText(L["Channels (%d)"]:format(0))
    local menu = CreateFrame("Frame", nil, p, BackdropTemplateMixin and "BackdropTemplate" or nil)
    menu:SetFrameStrata("FULLSCREEN_DIALOG")
    -- unsichtbare Fläche hinter dem Menü: ein Klick irgendwo anders schließt es (die Wahl ist schon gespeichert)
    -- (keine Klickfläche: eine frische Maustaste außerhalb von Menü und Knopf schließt es)
    menu:SetScript("OnUpdate", function(self)
        local down = IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton")
        if down and not self.wasDown and not self:IsMouseOver() and not p.chan:IsMouseOver() then self:Hide() end
        self.wasDown = down
    end)
    menu:SetScript("OnShow", function(self) self.wasDown = true end)   -- der Klick, der das Menü öffnet, zählt nicht
    menu:SetPoint("TOPRIGHT", p.chan, "BOTTOMRIGHT", 0, -2)
    menu:SetSize(220, 40)
    menu:EnableMouse(true)
    menu:Hide()
    if menu.SetBackdrop then
        menu:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8X8", edgeFile = "Interface\\Buttons\\WHITE8X8", edgeSize = 1 })
        menu:SetBackdropColor(0.05, 0.05, 0.08, 0.97)
        menu:SetBackdropBorderColor(0.4, 0.4, 0.45, 1)
    end
    menu.title = menu:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    menu.title:SetPoint("TOPLEFT", 8, -7)
    menu.title:SetText(L["Announce in these channels"])
    menu.rows = {}
    local function Fill()
        local list = LP.ChannelList()
        for i, ch in ipairs(list) do
            local row = menu.rows[i]
            if not row then
                row = CreateFrame("CheckButton", nil, menu, "UICheckButtonTemplate")
                row:SetSize(22, 22)
                row:SetHitRectInsets(0, -170, 0, 0)   -- auch ein Klick auf den Namen schaltet um
                row:SetPoint("TOPLEFT", 6, -22 - (i - 1) * 22)
                row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.text:SetPoint("LEFT", row, "RIGHT", 2, 0)
                row:SetScript("OnClick", function(self) LP.SetAdChannel(self.key, self:GetChecked()) end)
                menu.rows[i] = row
            end
            row.key = ch.key
            row.text:SetText(ch.id .. ". " .. ch.name)
            row:SetChecked(LP.AdChannelOn(ch))
            row:Show()
        end
        for i = #list + 1, #menu.rows do menu.rows[i]:Hide() end
        menu:SetHeight(30 + math.max(1, #list) * 22)
        menu.title:SetText(#list > 0 and L["Announce in these channels"] or L["You have not joined any channels yet."])
    end
    p.chan:SetScript("OnClick", function()
        if menu:IsShown() then menu:Hide() else Fill() menu:Show() end
    end)
    p:HookScript("OnHide", function() menu:Hide() end)
    -- Beschriftung: wie viele der aktuellen Kanäle angekreuzt sind
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

    -- Reiter Offen / Erledigt
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
                if ChatFrame_SendTell then ChatFrame_SendTell(target) else ChatFrame_OpenChat("/w " .. target .. " ") end   -- auch mit zweiteiligen Namen
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

    -- Mausrad: durch lange Listen blättern
    p:EnableMouseWheel(true)
    p:SetScript("OnMouseWheel", function(_, delta)
        offset = offset - delta
        RefreshRequests()
    end)

    -- unten: Countdown zur nächsten automatischen Ankündigung (mit x zum Abbrechen), Statistik, Erledigte löschen
    p.adText = FS(p, "GameFontHighlightSmall")
    p.adText:SetPoint("BOTTOMLEFT", 0, 4)   -- gleiche Reihe wie der Knopf "Erledigte löschen"
    p.adText:SetWidth(170)                  -- feste Breite: der x-Knopf bleibt an seinem Platz, egal wie lang die Zeit ist
    p.adText:SetJustifyH("LEFT")
    p.adText:SetWordWrap(false)
    p.adX = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    p.adX:SetSize(20, 18)
    p.adX:SetPoint("LEFT", p.adText, "RIGHT", 8, 0)
    p.adX:SetText("x")
    p.adX:SetScript("OnClick", function() LP.CancelAutoAd() end)
    p.adX:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(L["Stop the automatic announcement"])
        GameTooltip:Show()
    end)
    p.adX:SetScript("OnLeave", function() GameTooltip:Hide() end)

    p.clear = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
    p.clear:SetSize(150, 20)
    p.clear:SetPoint("BOTTOMRIGHT", 0, 0)
    p.clear:SetScript("OnClick", function()
        if armedAt and GetTime() - armedAt < 4 then   -- zweiter Klick innerhalb von 4 Sekunden bestätigt
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
        p.now:SetText("")   -- "Finder ist aus" steht schon am Schalter im Kopf
    end
    do   -- Kanäle-Knopf: Anzahl angekreuzter Kanäle, in denen du gerade bist
        local n = 0
        for _, ch in ipairs(LP.ChannelList()) do if LP.AdChannelOn(ch) then n = n + 1 end end
        p.chan:SetText(L["Channels (%d)"]:format(n))
    end
    p.leave:SetShown(st.phase == "grouped")
    p.queue:SetText(st.waiting > 0 and (L["Queue"] .. ": " .. table.concat(st.waitingNames, ", ")) or "")
    if win and win.stats then win.stats:SetText(L["Picked %d   ·   Tips %s"]:format(st.picked or 0, LP.Money(st.tips or 0))) end

    -- Aufträge in Offen / Erledigt aufteilen (LP.requests ist neueste zuerst)
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
    p.empty:SetText(view == "open" and L["empty.requests"] or L["Nothing finished yet."])
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
            r.inv:SetShown(q.status == "new" or q.status == "manual" or q.status == "queued")
            r:SetAlpha(view == "open" and 1 or 0.8)
            r:Show()
        else
            r:Hide()
        end
    end

    -- Countdown zur nächsten automatischen Ankündigung
    -- nur sichtbar, solange die automatische Ankündigung wirklich läuft (an + Finder an + keine Gruppe): eine Abkürzung zum Abbrechen
    local ad, text = LP.db.ad, nil
    if ad.auto and LP.db.finder.enabled and not LP.InGroup() and LP.nextAdAt then
        text = L["Next announcement in %s"]:format(LP.Mmss(LP.nextAdAt - GetTime()))
    end
    p.adText:SetText(text or "")
    p.adText:SetShown(text ~= nil)
    p.adX:SetShown(text ~= nil)

    -- Löschen nur im Reiter Erledigt; zweiter Klick bestätigt
    p.clear:SetShown(view == "done" and #done > 0)
    p.clear:SetText((armedAt and GetTime() - armedAt < 4) and L["Really delete?"] or L["Delete finished"])
end
-- Seite 2: Guide ------------------------------------------------------------------------------------
local function BuildGuide(p)
    p.head = FS(p, "GameFontNormalLarge")
    p.head:SetPoint("TOPLEFT", 0, -2)
    p.sub = FS(p, "GameFontHighlightSmall")
    p.sub:SetPoint("TOPLEFT", 0, -26)

    p.bar = CreateFrame("StatusBar", nil, p)
    p.bar:SetSize(408, 8)
    p.bar:SetPoint("TOPLEFT", 0, -44)
    p.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    p.bar:SetStatusBarColor(0.0, 0.74, 0.95)
    p.bar:SetMinMaxValues(0, 300)
    p.bar.bg = p.bar:CreateTexture(nil, "BACKGROUND")
    p.bar.bg:SetAllPoints()
    p.bar.bg:SetColorTexture(0, 0, 0, 0.5)

    p.chips = {}
    for i, st in ipairs(LP.GUIDE) do
        local c = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        c:SetSize(98, 22)
        c:SetPoint("TOPLEFT", (i - 1) * 103, -62)
        c:SetScript("OnClick", function() guideStage = i LP.RefreshUI() end)
        p.chips[i] = c
    end

    p.body = FS(p, "GameFontHighlight")
    p.body:SetPoint("TOPLEFT", 4, -96)
    p.body:SetWidth(400)
    p.body:SetJustifyV("TOP")
    p.body:SetSpacing(3)

    p.bags = FS(p, "GameFontHighlightSmall")
    p.bags:SetPoint("BOTTOMLEFT", 0, 0)
    p.bags:SetWidth(408)
    p.bags:SetJustifyV("BOTTOM")
end

local function RefreshGuide()
    local p = pages[2]
    local skill = LP.Skill()
    local max = (LP.skillMax and LP.skillMax > 0) and LP.skillMax or 300
    local cur = LP.StageForSkill(skill)
    guideStage = guideStage or cur
    local bonus = (LP.skillBonus and LP.skillBonus > 0) and (" |cff4de88a(+" .. LP.skillBonus .. ")|r") or ""
    p.head:SetText(L["Lockpicking %d%s / %d"]:format(LP.skillBase or skill, bonus, max))
    p.sub:SetText(L["Current stage %s  ·  %d points to the next"]:format(LP.GUIDE[cur].title, math.max(0, LP.GUIDE[cur].to - skill)))
    p.bar:SetMinMaxValues(0, 300)
    p.bar:SetValue(math.min(300, skill))
    for i, c in ipairs(p.chips) do
        local t = LP.GUIDE[i].title
        c:SetText(i == guideStage and ("|cffffd100" .. t .. "|r") or t)
    end
    local st = LP.GUIDE[guideStage]
    local lines = { "|cffffd100" .. L["Practice on these boxes"] .. "|r" }
    for _, b in ipairs(st.boxes) do lines[#lines + 1] = "  -  " .. b end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "|cffffd100" .. L["Where to find them?"] .. "|r"
    for _, pl in ipairs(st.places) do lines[#lines + 1] = "  -  " .. pl end
    lines[#lines + 1] = ""
    lines[#lines + 1] = "|cff4de88a" .. L["Hint"] .. ":|r " .. st.tip
    p.body:SetText(table.concat(lines, "\n"))

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

-- Seite 3: Einstellungen -------------------------------------------------------------------------------
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
        local function Holder() return tbl and LP.db[tbl] or LP.db end   -- tbl = nil: Einstellung auf oberster Ebene
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
        refreshers[#refreshers + 1] = function() if not e:HasFocus() then Load() end end   -- nicht überschreiben, während getippt wird
        y = y - 30
    end

    Section(L["Duty"])
    Check(L["Invite players automatically"], "finder", "autoInvite")
    Check(L["Only one customer at a time (queue)"], "finder", "onlyWhenFree")
    Check(L["Also invite when no box is mentioned"], "finder", "inviteUnknown")
    Check(L["Accept invites automatically"], "finder", "autoAccept")

    Section(L["Group"])
    Check(L["Whisper a greeting after joining"], "finder", "welcome")
    Check(L["Leave the group after picking"], "finder", "autoLeave")
    Check(L["Thank-you message for tips"], "finder", "thanks")

    Section(L["Display"])
    Check(L["Pop-up (toast) for requests and tips"], "ui", "toast")
    Check(L["Chat line for new requests"], "ui", "chatLine")
    Check(L["Flash the taskbar"], "ui", "flash")
    Check(L["Sound for new requests"], "finder", "sound")
    Check(L["Sparkle on locked boxes in bags"], "pick", "glow", function() if LP.UpdateGlow then LP.UpdateGlow() end end)
    Check(L["Tooltip hint on locks"], "pick", "hint")
    Check(L["Minimap button"], "ui", "minimap", function() LP.UpdateMinimap() end)

    -- Fenstergröße
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
        -- Beim Ziehen nur die Zahl anzeigen; die Fenstergröße wird erst beim LOSLASSEN übernommen.
        -- (Würde das Fenster schon beim Ziehen skalieren, wanderte der Regler unter der Maus weg.)
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

    Section(L["Announcement"])
    Edit(L["Text ({skill} = skill, {pick} = spell link, {city} = current city; links can be inserted with Shift-click)"], "ad", "text")
    Check(L["Repeat automatically (only while on duty)"], "ad", "auto", function() LP.StartAdLoop() end)
    Edit(L["Repeat interval in seconds (min. 180)"], "ad", "interval", true, 120)

    Section(L["Advanced"])
    Edit(L["Leave after the last trade, in seconds"], "finder", "leaveDelay", true, 120)
    Edit(L["Leave without activity after seconds (0 = off)"], "finder", "idleLeave", true, 120)

    child:SetHeight(-y + 20)
end

local function RefreshSettings()
    for _, f in ipairs(refreshers) do f() end
end

-- Seite 4: Debug (nur im Debug-Modus sichtbar) -------------------------------------------------------------------------
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
    b = CreateFrame("Button", nil, p, "SecureActionButtonTemplate")   -- derselbe Mechanismus wie die Klickfläche im Inventar
    b:SetSize(36, 36)
    b:SetPoint("TOPLEFT", 44 * i, -164)
    b:RegisterForClicks("RightButtonUp", "RightButtonDown")
    b:SetAttribute("type", "spell")
    b:HookScript("PreClick", function(self, button)   -- auch hier merken, was geknackt wird (Schonfrist nach Erfolg)
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
    if not p or not p.testHint or InCombatLockdown() then return end   -- Secure-Buttons nur außerhalb des Kampfes ändern
    if not LP.db.debug then   -- Testbereich nur im Testmodus
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
    -- steht die Maus noch auf einem Slot, den Tooltip sofort aktualisieren
    for i = 1, MAX_REAL do
        local b = testSlots[i]
        if b and b:IsShown() and b:IsMouseOver() then b:GetScript("OnEnter")(b) end
    end
end

local function BuildDebug(p)
    local function Btn(parent, label, w, x, y, fn)
        local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        b:SetSize(w, 22)
        b:SetPoint("TOPLEFT", x, y)
        b:SetText(label)
        b:SetScript("OnClick", function() fn() end)
        return b
    end

    -- Großer Testmodus-Schalter: an = alles wird nur simuliert + Protokoll läuft, aus = Picky arbeitet normal
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

    -- Werkzeuge: nur im Testmodus benutzbar
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

    -- Anfrage simulieren (läuft durch die echte Erkennung, immer als Trockenlauf)
    local h = FS(tools, "GameFontNormalSmall", L["Simulate a request"])
    h:SetPoint("TOPLEFT", 2, 0)
    local e = CreateFrame("EditBox", nil, tools, "InputBoxTemplate")
    e:SetSize(284, 22)
    e:SetPoint("TOPLEFT", 10, -16)
    e:SetAutoFocus(false)
    e:SetMaxLetters(200)
    e:SetText("hi can u open some low level chersts for me?")
    e:SetCursorPosition(0)
    e:SetScript("OnEnterPressed", function(s) LP.SimulateChat(s:GetText(), false) s:ClearFocus() end)
    e:SetScript("OnEscapePressed", function(s) s:ClearFocus() end)
    p.simEdit = e
    ToolBtn(L["As chat"], 50, 298, -15, function() LP.SimulateChat(e:GetText(), false) end)
    ToolBtn(L["As whisper"], 58, 350, -15, function() LP.SimulateChat(e:GetText(), true) end)

    ToolBtn(L["Customer joins"], 98, 0, -44, function() LP.SimulateJoin() end)
    ToolBtn(L["Tip"], 70, 102, -44, function() LP.SimulateTip(12500) end)
    ToolBtn(L["Pick succeeded"], 112, 176, -44, function() LP.SimulatePick() end)
    ToolBtn(L["Customer leaves"], 114, 292, -44, function() LP.SimulateLeave() end)

    -- Testbereich für den Rechtsklick (simulierte Kiste; die echten Kisten kommen als Slots daneben)
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
        SimTooltip(self)   -- Tooltip sofort aktualisieren, ohne die Maus zu bewegen
    end)
    p.simSlot = sim

    p.testHint = FS(p, "GameFontHighlightSmall")
    p.testHint:SetPoint("TOPLEFT", 2, -206)
    p.testHint:SetWidth(404)
    p.testHint:SetJustifyV("TOP")

    -- Protokoll: Titel, Chat-Schalter und "Protokoll leeren" in einer Kopfzeile direkt über dem Feld
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
    log:SetMaxLines(300)
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
    for _, line in ipairs(LP.debugLog) do log:AddMessage(line) end
    LP.OnDebugLine = function(line) log:AddMessage(line) end

    -- nach dem Knacken / bei Änderungen in den Taschen die echten Slots neu aufbauen
    LP.On("BAG_UPDATE_DELAYED", function() if pages[4] and pages[4]:IsShown() then RefreshTestSlots() end end)
    LP.On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit)
        if unit == "player" and pages[4] and pages[4]:IsShown() then LP.After(0.3, RefreshTestSlots) end
    end)
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
    -- Werkzeuge nur im Testmodus benutzbar
    p.tools:SetAlpha(on and 1 or 0.4)
    for _, b in ipairs(p.toolButtons) do
        if b.SetEnabled then b:SetEnabled(on) end
    end
    if p.simEdit.SetEnabled then pcall(p.simEdit.SetEnabled, p.simEdit, on) end
    if not on then p.simEdit:ClearFocus() end
    p.simSlot:EnableMouse(on)
    RefreshTestSlots()
end

-- Seite 5: Developer (versteckt, nur per /picky dev) -------------------------------------------------------------------
-- Nur für die Entwicklung: Selbsttests, Maus-Prüfung, Diagnosen. Absichtlich ohne Übersetzung.
local function BuildDev(p)
    local function Btn(label, w, x, y, fn)
        local b = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
        b:SetSize(w, 22)
        b:SetPoint("TOPLEFT", x, y)
        b:SetText(label)
        b:SetScript("OnClick", function() fn() end)
        return b
    end
    local h = FS(p, "GameFontNormalLarge", "Developer tools")
    h:SetPoint("TOPLEFT", 2, 0)
    local sub = FS(p, "GameFontHighlightSmall", "Hidden tab - toggle with /picky dev. Output appears here and in the chat.")
    sub:SetPoint("TOPLEFT", 2, -24)

    local out = CreateFrame("ScrollingMessageFrame", nil, p)
    out:SetPoint("TOPLEFT", 0, -130)
    out:SetPoint("BOTTOMRIGHT", 0, 0)
    out:SetFontObject("GameFontHighlightSmall")
    out:SetJustifyH("LEFT")
    out:SetMaxLines(400)
    out:SetFading(false)
    out:EnableMouseWheel(true)
    out:SetScript("OnMouseWheel", function(self, d) if d > 0 then self:ScrollUp() else self:ScrollDown() end end)
    local bg = out:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 0.45)
    p.out = out

    -- Ausgaben von LP.Print zusätzlich in dieses Feld schreiben
    local function Capture(fn)
        local old = LP.Print
        LP.Print = function(m) old(m) out:AddMessage(tostring(m)) end
        local ok, err = pcall(fn)
        LP.Print = old
        if not ok then out:AddMessage("|cffff5959error:|r " .. tostring(err)) end
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
        P("stats picked %d | tips %s | invited %d | thanked %d", db.stats.picked, LP.Money(db.stats.tips), db.stats.invited, db.stats.thanked)
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
        out:AddMessage("inspecting what is under the mouse in 3 s ...")
        LP.After(3, function() Capture(function() LP.InspectHover() end) end)
    end)
    Btn("Skill diagnostics", 120, 248, -46, function() Capture(function() SlashCmdList["PICKY"]("skill") end) end)
    Btn("Dump state", 110, 0, -74, function() Capture(DumpState) end)
    Btn("Client info", 110, 114, -74, function() Capture(ClientInfo) end)
    Btn("Clear output", 120, 248, -74, function() out:Clear() end)
    local live = CreateFrame("CheckButton", nil, p, "UICheckButtonTemplate")
    live:SetSize(24, 24)
    live:SetPoint("TOPLEFT", 0, -100)
    local ll = FS(p, "GameFontHighlightSmall", "Keep a log in normal (live) mode too; saved on /reload or logout")
    ll:SetPoint("LEFT", live, "RIGHT", 2, 0)
    live:SetScript("OnClick", function(self) LP.db.logLive = self:GetChecked() and true or false end)
    p.liveCb = live
end

local function RefreshDev()
    local p = pages[5]
    if p and p.liveCb then p.liveCb:SetChecked(LP.db.logLive and true or false) end
end-- Fenster zusammenbauen ----------------------------------------------------------------------------------
local function SelectTab(i)
    currentTab = i
    local titles = { L["Requests"], "Guide", L["Settings"], L["Test mode"], "Developer" }
    for n, pg in ipairs(pages) do
        pg:SetShown(n == i)
        if tabs[n].SelectedTexture then tabs[n].SelectedTexture:SetShown(n == i) end
    end
    win:SetTitle("Picky  ·  " .. titles[i])
    LP.RefreshUI()
end

-- Test-Tab ist immer da; bei Änderung des Testmodus nur auffrischen
function LP.RefreshDebugTab()
    if win and win:IsShown() then LP.RefreshUI() end
end

-- Developer-Tab nur zeigen, wenn per /picky dev eingeschaltet
function LP.RefreshDevTab()
    if not win or not tabs[5] then return end
    tabs[5]:SetShown(LP.db.dev and true or false)
    if not LP.db.dev and currentTab == 5 then SelectTab(1) end
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
    win:HookScript("OnShow", function(self) self:Raise() LP.RefreshSkill() LP.RefreshUI() end)
    tinsert(UISpecialFrames, "PickyFrame")
    win:EnableMouse(true)
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", win.StartMoving)
    win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() SavePos() end)

    -- Kopfzeile: Skill + Finder-Schalter
    win.skillText = FS(win, "GameFontHighlight")
    win.skillText:SetPoint("TOPLEFT", 76, -27)
    win.stats = FS(win, "GameFontNormalSmall")
    win.stats:SetPoint("TOPLEFT", 78, -49)
    win.bar = CreateFrame("StatusBar", nil, win)
    win.bar:SetSize(196, 7)
    win.bar:SetPoint("TOPLEFT", 78, -40)
    win.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    win.bar:SetStatusBarColor(0.0, 0.74, 0.95)
    win.bar:SetMinMaxValues(0, 300)
    win.bar.bg = win.bar:CreateTexture(nil, "BACKGROUND")
    win.bar.bg:SetAllPoints()
    win.bar.bg:SetColorTexture(0, 0, 0, 0.5)

    win.finder = CreateFrame("Button", nil, win, "UIPanelButtonTemplate")
    win.finder:SetSize(104, 26)
    win.finder:SetPoint("TOPRIGHT", -16, -30)
    win.finder:SetScript("OnClick", function() LP.SetFinder(not LP.db.finder.enabled, true) end)

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
    local max = (LP.skillMax and LP.skillMax > 0) and LP.skillMax or 300
    local bonus = (LP.skillBonus and LP.skillBonus > 0) and (" |cff4de88a(+" .. LP.skillBonus .. ")|r") or ""
    local est = LP.skillEstimated and "  |cffffd100" .. L["estimated"] .. "|r" or ""
    win.skillText:SetText(L["Lockpicking %d%s / %d%s"]:format(LP.skillBase or skill, bonus, max, est))
    win.bar:SetValue(math.min(300, skill))
    win.finder:SetText(LP.db.finder.enabled and ("|cff4de88a" .. L["On duty"] .. "|r") or L["Off duty"])
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

function LP.ToggleUI()
    Build()
    if win:IsShown() then win:Hide() else win:Show() end
end

-- Shift-Klick auf Zauber/Item/Link fügt ihn in das fokussierte Picky-Textfeld ein
local function InsertIntoPickyEdit(link)
    local f = GetCurrentKeyBoardFocus and GetCurrentKeyBoardFocus()
    if f and f.PickyEdit and link then f:Insert(link) end
end
if ChatFrameUtil and ChatFrameUtil.InsertLink then
    hooksecurefunc(ChatFrameUtil, "InsertLink", InsertIntoPickyEdit)
elseif ChatEdit_InsertLink then
    hooksecurefunc("ChatEdit_InsertLink", InsertIntoPickyEdit)
end

-- Minimap-Button (mit Zustand) ----------------------------------------------------------------------------
local mm
-- true = runde Ecke in diesem Quadranten (Reihenfolge: rechts-oben, links-oben, rechts-unten, links-unten)
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

-- Zustand am Button: grau = Finder aus, normal = an, grün = Kunde in der Gruppe, Zahl = Wartende
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
    GameTooltip:AddLine(L["Picked %d  ·  Tips %s"]:format(st.picked or 0, LP.Money(st.tips or 0)), 0.7, 0.7, 0.7)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("|cffffd100" .. L["Click"] .. "|r " .. L["open window"], 1, 1, 1)
    GameTooltip:AddLine("|cffffd100" .. L["Right-click"] .. "|r " .. L["toggle duty"], 1, 1, 1)
    GameTooltip:Show()
end

function LP.BuildMinimap()
    if mm then return end
    mm = CreateFrame("Button", "PickyMinimap", Minimap)
    mm:SetSize(31, 31)
    mm:SetFrameStrata("MEDIUM")
    mm:SetFrameLevel(8)
    mm:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
    -- gleicher Aufbau wie die üblichen Minimap-Buttons: Hintergrund, Icon, Ring
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
    mm.badge = mm:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    mm.badge:SetPoint("BOTTOMRIGHT", 2, 0)
    mm.badge:SetTextColor(1, 0.82, 0)

    mm:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    mm:RegisterForDrag("LeftButton")
    mm:SetScript("OnClick", function(_, b)
        if b == "RightButton" then
            LP.SetFinder(not LP.db.finder.enabled)
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
