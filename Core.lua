-- Picky / Core.lua : Namespace, Einstellungen, Hilfsfunktionen, Slash-Befehle
local ADDON, LP = ...
_G.Picky = LP
local L = LP.L
LP.version = "1.0.0"
LP.PICK_SPELL_ID = 1804

_G.BINDING_HEADER_PICKY = "Picky"
_G.BINDING_NAME_PICKY_TOGGLE = L["Picky window"]
_G.BINDING_NAME_PICKY_AD = L["Announce service in trade chat"]

LP.defaults = {
    pick = { hint = true, glow = true },
    finder = {
        enabled = false,
        autoInvite = true,
        onlyWhenFree = true,
        inviteUnknown = true,
        autoAccept = true,
        welcome = true,
        thanks = true,
        autoLeave = true,
        leaveDelay = 10,       -- Sekunden Wartezeit nach dem letzten Handel, dann verlässt Picky die Gruppe
        idleLeave = 180,
        sound = true,
        cooldown = 180,
        maxAge = 120,
        welcomeText = L["default.welcome"],
        thanksText = L["default.thanks"],
    },
    ad = {
        auto = false,
        interval = 300,
        channelMatch = "handel,trade",
        text = L["default.ad"],
    },
    ui = {
        minimap = true, angle = 215,
        toast = true,        -- Meldung bei Anfragen / Beitritt / Trinkgeld
        chatLine = false,    -- zusätzlich eine Zeile im Chat
        flash = true,        -- Taskleiste blinken
        scale = 100,         -- Fenstergröße in Prozent
    },
    stats = { picked = 0, tips = 0, invited = 0, thanked = 0 },
    ignore = {},
    orders = {},         -- alle Aufträge/Anfragen, dauerhaft gespeichert (neueste zuerst); nur du löschst sie
    debug = false,       -- TESTMODUS: Protokoll läuft, Einladen/Flüstern/Verlassen/Ankündigen werden nur simuliert
    debugChat = false,   -- Protokollzeilen zusätzlich in den Chat schreiben
    dev = false,         -- Developer-Tab (nur per /picky dev sichtbar)
    logLive = false,     -- Protokoll auch im Normalbetrieb führen (Developer-Tab)
}

local function Merge(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            Merge(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

-- Event-System ------------------------------------------------------------
local frame = CreateFrame("Frame")
LP.frame = frame
local handlers = {}
function LP.On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        if event == "UNIT_SPELLCAST_SUCCEEDED" and frame.RegisterUnitEvent then
            pcall(frame.RegisterUnitEvent, frame, event, "player")   -- nur eigene Zauber, nicht die aller Spieler im Raid
        else
            pcall(frame.RegisterEvent, frame, event)
        end
    end
    table.insert(handlers[event], fn)
end
frame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if list then
        for i = 1, #list do list[i](event, ...) end
    end
end)

-- Hilfsfunktionen -----------------------------------------------------------
function LP.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffPicky|r: " .. tostring(msg))
end

function LP.After(sec, fn)
    C_Timer.After(sec, fn)
end

-- Debug-Modus ----------------------------------------------------------------------
-- LP.Debug(Bereich, Format, ...) schreibt nur, wenn der Debug-Modus an ist (kostet sonst fast nichts).
-- Bereiche: chat, invite, group, trade, pick, skill, ui, test, sim
LP.debugLog = {}
local DEBUG_MAX = 300
function LP.Debug(cat, fmt, ...)
    if not (LP.db and (LP.db.debug or LP.db.logLive)) then return end
    local n = select("#", ...)
    local args = { ... }
    for i = 1, n do
        if type(args[i]) ~= "number" then args[i] = tostring(args[i]) end   -- nil/Tabellen/Booleans sicher darstellen
    end
    local ok, msg = pcall(string.format, tostring(fmt), unpack(args, 1, n))
    if not ok then msg = tostring(fmt) .. " (format error)" end
    -- dieselbe Zeile innerhalb einer Sekunde nicht mehrfach (sonst läuft das Protokoll mit Wiederholungen voll)
    local key = cat .. "|" .. msg
    local nowT = GetTime()
    if key == LP.lastDebugKey and nowT - (LP.lastDebugT or 0) < 1 then return end
    LP.lastDebugKey, LP.lastDebugT = key, nowT
    local line = ("%s |cff9aa0ad[%s]|r %s"):format(date("%H:%M:%S"), cat, msg)
    local log = LP.debugLog
    log[#log + 1] = line
    if #log > DEBUG_MAX then table.remove(log, 1) end
    if LP.db.debugChat then DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffPicky|r " .. line) end
    if LP.OnDebugLine then LP.OnDebugLine(line) end
end

-- Trockenlauf: Einladen/Flüstern/Verlassen/Ankündigen werden nur protokolliert.
-- LP.forceDry wird von den Simulationen gesetzt, damit sie nie echte Aktionen auslösen.
-- Testmodus ein/aus: Protokoll + alles wird nur simuliert (Einladen, Flüstern, Verlassen, Ankündigen)
function LP.SetTestMode(on)
    on = on and true or false
    LP.db.debug = on
    if not on and LP.partnerSim then
        -- ein simulierter Kunde darf nicht im echten Betrieb hängen bleiben (er würde Einladen/Flüstern/Ankündigen stumm schalten)
        LP.partner, LP.partnerSim, LP.pickedForPartner, LP.leaveAt = nil, nil, false, nil
        LP.leaveToken = (LP.leaveToken or 0) + 1
    end
    LP.Print(L["Test mode: "] .. (on and ("|cff4de88a" .. L["ON"] .. "|r") or ("|cffff5959" .. L["OFF"] .. "|r")))
    if on then
        LP.Print(L["Test mode is on: a log is kept and invites, whispers and announcements are only simulated. The Test tab has the tools; /picky test runs the self tests."])
        LP.Debug("ui", "test mode switched on")
    end
    if LP.RefreshDebugTab then LP.RefreshDebugTab() end
    if LP.RefreshAll then LP.RefreshAll() end
end

function LP.IsDry()
    return LP.forceDry or LP.partnerSim or (LP.db and LP.db.debug) or false
end

function LP.Short(name)
    return name and (name:match("^[^%-]+") or name) or name
end

-- Gleicher Spieler? In diesem Client haben Namen zwei Teile ("Arkanos Spellix"): der Chat meldet den vollen Namen,
-- UnitName() und der Handel nur "Arkanos". Der erste Teil (ohne Realm-Zusatz, klein geschrieben) muss gleich sein;
-- haben BEIDE Namen einen zweiten Teil, muss auch der gleich sein ("Arkanos Spellix" ist nicht "Arkanos Voidwalker").
local function NameParts(n)
    if not n then return "", "" end
    n = tostring(n):lower():gsub("%-.*$", "")
    local first, rest = n:match("^%s*(%S+)%s*(.-)%s*$")
    return first or "", rest or ""
end
function LP.SameName(a, b)
    if a == nil or b == nil then return false end
    local fa, ra = NameParts(a)
    local fb, rb = NameParts(b)
    if fa == "" or fa ~= fb then return false end
    if ra ~= "" and rb ~= "" then return ra == rb end
    return true
end

-- Steht der Spieler auf deiner Ignorierliste? (gleicher Namensvergleich wie überall)
function LP.IsIgnored(name)
    if not name or not LP.db then return false end
    for k in pairs(LP.db.ignore) do
        if LP.SameName(k, name) then return true end
    end
    return false
end

function LP.Money(c)
    c = c or 0
    local g, s, k = math.floor(c / 10000), math.floor((c % 10000) / 100), c % 100
    local t = {}
    if g > 0 then t[#t + 1] = g .. "g" end
    if s > 0 then t[#t + 1] = s .. "s" end
    if k > 0 or #t == 0 then t[#t + 1] = k .. "k" end
    return table.concat(t, " ")
end

function LP.SpellName(id)
    if C_Spell and C_Spell.GetSpellInfo then
        local i = C_Spell.GetSpellInfo(id)
        return i and i.name
    end
    return (GetSpellInfo(id))
end
function LP.PickName() return LP.SpellName(LP.PICK_SPELL_ID) or "Pick Lock" end

-- Klickbarer Zauber-Link, wie er im Chat aussieht: [Pick Lock] bzw. [Schloss knacken]
function LP.PickLink()
    local id = LP.PICK_SPELL_ID
    local link = (C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(id)) or (GetSpellLink and GetSpellLink(id))
    return link or ("[" .. LP.PickName() .. "]")
end

-- Ankündigungstext fertig machen: {skill} = Skill, {pick} = Zauber-Link, {city} = aktuelles Gebiet (z.B. Sturmwind),
-- ein einfaches [Zaubername] ohne Link wird ebenfalls zum Link.
function LP.ExpandAd(text)
    local link = LP.PickLink()
    text = text:gsub("{skill}", function() return tostring(LP.Skill()) end)
    text = text:gsub("{pick}", function() return link end)
    text = text:gsub("{city}", function() return (GetRealZoneText and GetRealZoneText()) or (GetZoneText and GetZoneText()) or "" end)
    if not text:find("|Hspell", 1, true) then
        local plain = "[" .. LP.PickName() .. "]"
        local a, b = text:find(plain, 1, true)
        if a then text = text:sub(1, a - 1) .. link .. text:sub(b + 1) end
    end
    return text
end

function LP.IsRogue()
    local _, class = UnitClass("player")
    return class == "ROGUE"
end

-- Gruppen-Wrapper (alte/neue API)
function LP.InGroup()
    if IsInGroup then return IsInGroup() end
    return GetNumPartyMembers() > 0
end
function LP.GroupCount()
    if GetNumGroupMembers then return GetNumGroupMembers() end
    return GetNumPartyMembers() + 1
end
function LP.Invite(name)
    if LP.IsDry() then LP.Debug("invite", "[dry run] would invite %s", name) return end
    if C_PartyInfo and C_PartyInfo.InviteUnit then C_PartyInfo.InviteUnit(name) else InviteUnit(name) end
end
function LP.Leave()
    if LP.IsDry() then LP.Debug("group", "[dry run] would leave the group") return end
    if C_PartyInfo and C_PartyInfo.LeaveParty then C_PartyInfo.LeaveParty() else LeaveParty() end
end
function LP.InGroupWith(name)
    if IsInRaid and IsInRaid() then   -- Schlachtzugsgruppe: raid1..raidN statt party1..4
        for i = 1, (GetNumGroupMembers and GetNumGroupMembers() or 0) do
            local n = UnitName("raid" .. i)
            if n and LP.SameName(n, name) then return true end
        end
        return false
    end
    for i = 1, 4 do
        local n = UnitName("party" .. i)
        if n and LP.SameName(n, name) then return true end
    end
    return false
end
function LP.Whisper(name, text)
    if LP.IsDry() then LP.Debug("invite", "[dry run] would whisper %s: %s", name, text) return end
    -- neuere Clients haben SendChatMessage nur noch unter C_ChatInfo; Fehler werden protokolliert statt verschluckt
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    local ok, err = pcall(send, text, "WHISPER", nil, name)
    LP.Debug("invite", "whisper to %s: %s", name, ok and "sent" or ("FAILED: " .. tostring(err)))
    if not ok then LP.Print("|cffff5959" .. L["Whisper to %s failed: %s"]:format(tostring(name), tostring(err)) .. "|r") end
end
function LP.SendChannel(text, id)
    if LP.IsDry() then LP.Debug("chat", "[dry run] would post to channel %s: %s", id, text) return true end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    local ok, err = pcall(send, text, "CHANNEL", nil, id)
    if not ok then LP.Debug("chat", "channel post failed: %s", err) end
    return ok
end

-- Skill --------------------------------------------------------------------
-- WoW Forever hat keine Skill-Liste (GetNumSkillLines/GetSkillLineInfo fehlen). Quellen der Reihe nach:
--  1. Skill-Liste (falls der Client eine hat)
--  2. C_TradeSkillUI (Skill-Linie 633 = Schlossknacken)
--  3. zuletzt bekannter Wert: aus der Skill-Meldung im Chat oder per /picky skill <Zahl>
--  4. Schätzung Level x 5 (nur Notlösung, in der Anzeige als "geschätzt" markiert)
-- Der Bonus aus Ausrüstung ("Equip: Lockpicking +4" / "Anlegen: Schlossknacken +4") kommt aus den Tooltips
-- der angelegten Items (Englisch und Deutsch).
local SKILL_NAMES = { "lockpick", "schlossknack", "schlösser", "schloss", "crochetage" }
local LOCKPICKING_SKILL_LINE = 633

local function IsLockWord(l)
    return l:find("lockpick", 1, true) or l:find("schloss", 1, true) or l:find("schlö", 1, true)
end

-- Bonus aus EINER Tooltip-Zeile: "Equip: Lockpicking +4." / "Anlegen: Schlossknacken +4." -> 4, sonst 0
function LP.ParseBonus(text)
    if type(text) ~= "string" then return 0 end
    local l = text:lower()
    if IsLockWord(l) then
        local n = l:match("%+%s*(%d+)")
        if n then return tonumber(n) end
    end
    return 0
end

function LP.GearBonus()
    if not (C_TooltipInfo and C_TooltipInfo.GetInventoryItem) then return 0 end
    local total = 0
    for slot = 1, 19 do
        local data = C_TooltipInfo.GetInventoryItem("player", slot)
        if data and data.lines then
            for _, line in ipairs(data.lines) do
                local b = LP.ParseBonus(line.leftText)
                if b > 0 then
                    total = total + b
                    LP.Debug("skill", "gear bonus +%d from slot %d: %s", b, slot, line.leftText)
                end
            end
        end
    end
    return total
end

function LP.RefreshSkill()
    local base, max, apiBonus, source, estimated
    if GetNumSkillLines and GetSkillLineInfo then
        if ExpandSkillHeader then pcall(ExpandSkillHeader, 0) end
        for i = 1, GetNumSkillLines() do
            local name, header, _, r, temp, mod, m = GetSkillLineInfo(i)
            if name and not header then
                local l = name:lower()
                for _, w in ipairs(SKILL_NAMES) do
                    if l:find(w, 1, true) then
                        base, max, apiBonus, source = r, m, (mod or 0) + (temp or 0), L["Skill list"]
                        break
                    end
                end
            end
            if base then break end
        end
    end
    if not base and C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID then
        local ok, info = pcall(C_TradeSkillUI.GetProfessionInfoBySkillLineID, LOCKPICKING_SKILL_LINE)
        if ok and type(info) == "table" and (info.skillLevel or 0) > 0 then
            base, max, apiBonus, source = info.skillLevel, info.maxSkillLevel, info.skillModifier or 0, "C_TradeSkillUI"
        end
    end
    if not base and LP.db and (LP.db.skillBase or 0) > 0 then
        base, max, source = LP.db.skillBase, 300, L["stored"]
    end
    if not base and LP.IsRogue() then
        base, max, estimated, source = math.min(300, UnitLevel("player") * 5), 300, true, L["estimated"]
    end
    base = base or 0
    local bonus = math.max(apiBonus or 0, LP.GearBonus())
    LP.skillBase, LP.skillBonus, LP.skillMax = base, bonus, max or 0
    LP.skill = base + bonus
    LP.skillEstimated, LP.skillSource = estimated, source
    LP.Debug("skill", "skill %d = base %d + bonus %d (source: %s%s)", LP.skill, base, bonus, tostring(source), estimated and ", ESTIMATED" or "")
    return LP.skill
end
function LP.Skill() return LP.skill or LP.RefreshSkill() end

-- Start ----------------------------------------------------------------------
-- Gespeicherte Standardtexte folgen der Spielsprache: stimmt der Text noch mit einem der beiden
-- mitgelieferten Standardtexte (Deutsch/Englisch) überein, wird er durch den der aktuellen Sprache ersetzt.
-- Selbst geschriebene Texte bleiben unberührt.
local function FollowLocale(tbl, key, id)
    local en, de = LP.Both(id)
    local v = tbl[key]
    if v == en or v == de then tbl[key] = L[id] end
end
LP.FollowLocale = FollowLocale

LP.On("ADDON_LOADED", function(_, name)
    if name ~= ADDON then return end
    PickyDB = PickyDB or {}
    Merge(PickyDB, LP.defaults)
    LP.db = PickyDB
    -- alter Standardtext (ohne Zauber-Link) -> aktueller Standardtext
    if LP.db.ad.text == "Schurke knackt Schlösser/Kisten (Skill {skill})! Schreib mir die Kiste ins Flüstern - Trinkgeld willkommen :)" then
        LP.db.ad.text = LP.defaults.ad.text
    end
    FollowLocale(LP.db.finder, "welcomeText", "default.welcome")
    FollowLocale(LP.db.finder, "thanksText", "default.thanks")
    FollowLocale(LP.db.ad, "text", "default.ad")
    -- Testmodus ersetzt "Debug-Modus + Trockenlauf": war der Debug-Modus OHNE Trockenlauf an, wird er ausgeschaltet
    -- (der Testmodus simuliert immer); die alte Einstellung wird entfernt
    if PickyDB.dryRun ~= nil then
        if PickyDB.dryRun == false then PickyDB.debug = false end
        PickyDB.dryRun = nil
    end
    -- die Mini-Anzeige gibt es nicht mehr: alte Einstellungen dazu entfernen
    PickyDB.ui.tracker, PickyDB.ui.trackerCollapsed, PickyDB.ui.trackerPos = nil, nil, nil
    PickyDB.feedMigrated = nil
    PickyDB.ui.feed, PickyDB.ui.feedExpand, PickyDB.ui.feedPos = nil, nil, nil   -- das Verlauf-Feld auf dem Bildschirm gibt es nicht mehr
    -- Reste früherer Versionen entfernen
    PickyDB.ui.lastDisplay = nil
    if PickyDB.pick then PickyDB.pick.outline, PickyDB.pick.cursor, PickyDB.pick.cursorIcon = nil, nil, nil end
    PickyDB.finder.declineText, PickyDB.finder.declineTooHigh = nil, nil
    -- Wartezeit vor dem Verlassen: alter Standard 2 s -> 15 s (mehrere Kisten nacheinander); einmalig
    if not PickyDB.leaveDelayMigrated then
        PickyDB.leaveDelayMigrated = true
        if PickyDB.finder.leaveDelay == 2 then PickyDB.finder.leaveDelay = 15 end
    end
    -- 15 s waren zu lang (der Kunde wusste nicht, ob noch etwas kommt): neuer Standard 10 s, einmalig
    if not PickyDB.leaveDelay10 then
        PickyDB.leaveDelay10 = true
        if PickyDB.finder.leaveDelay == 15 then PickyDB.finder.leaveDelay = 10 end
    end
    LP.db = PickyDB
    if LP.LoadOrders then LP.LoadOrders() end   -- gespeicherte Aufträge laden (Finder.lua)
end)
LP.On("PLAYER_LOGIN", function()
    LP.RefreshSkill()
    if LP.db.debug then
        LP.Print("|cffff9d00" .. L["Test mode is ON: invites, whispers and announcements are only simulated. Turn it off in the Test tab or with /picky debug."] .. "|r")
    end
    local easy = (C_AddOns and C_AddOns.IsAddOnLoaded and C_AddOns.IsAddOnLoaded("EasyLockpick")) or (IsAddOnLoaded and IsAddOnLoaded("EasyLockpick"))
    if easy then
        LP.Print("|cffff9d00" .. L["EasyLockpick is also active: two lockpicking addons on the same slots can disturb each other. Disable one of them."] .. "|r")
    end
    if not LP.IsRogue() then
        LP.Print(L["You are not a rogue - most features are inactive."])
    else
        LP.Print(L["v%s loaded. /lp opens the window. Right-click a locked box to pick it."]:format(LP.version))
    end
    if LP.OnLogin then LP.OnLogin() end
end)
LP.On("SKILL_LINES_CHANGED", function()
    LP.RefreshSkill()
    if LP.RefreshUI then LP.RefreshUI() end
end)
-- Skill-Meldung im Chat ("Your skill in Lockpicking has increased to 151" / deutsch) -> Wert merken
LP.On("CHAT_MSG_SKILL", function(_, msg)
    if type(msg) == "string" and LP.db and IsLockWord(msg:lower()) then
        local n = tonumber(msg:match("(%d+)%D*$"))
        if n and n > 0 and n <= 300 then LP.db.skillBase = n end
    end
    LP.RefreshSkill()
    if LP.RefreshUI then LP.RefreshUI() end
end)
-- Ausrüstung gewechselt -> Bonus neu lesen (kurz warten, bis die Tooltips aktuell sind)
LP.On("PLAYER_EQUIPMENT_CHANGED", function()
    LP.After(0.3, function()
        LP.RefreshSkill()
        if LP.RefreshUI then LP.RefreshUI() end
    end)
end)

-- Protokoll + Verlauf beim /reload bzw. Abmelden mitspeichern (ohne Farbcodes), damit sie danach lesbar sind
LP.On("PLAYER_LOGOUT", function()
    if not LP.db then return end
    local function Clean(s) return (tostring(s):gsub("|cn[^:|]*:", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    local log = {}
    for i, line in ipairs(LP.debugLog) do log[i] = Clean(line) end
    LP.db.savedLog = log
    -- simulierte Aufträge nicht speichern
    local orders = LP.db.orders
    if type(orders) == "table" then
        for i = #orders, 1, -1 do if orders[i].sim then table.remove(orders, i) end end
    end
    local feed = {}
    for i, e in ipairs(LP.feed or {}) do feed[i] = Clean(e.clock .. " [" .. e.kind .. "] " .. e.text) end
    LP.db.savedFeed = feed
end)
-- Slash ---------------------------------------------------------------------------
SLASH_PICKY1, SLASH_PICKY2, SLASH_PICKY3 = "/picky", "/lp", "/schloss"
SlashCmdList["PICKY"] = function(msg)
    local cmd, arg = (msg or ""):match("^(%S*)%s*(.-)$")
    cmd = cmd:lower()
    if cmd == "" or cmd == "show" then
        LP.ToggleUI()
    elseif cmd == "skill" then
        -- /picky skill          -> Diagnose
        -- /picky skill <Zahl>   -> Basiswert von Hand setzen (ohne Ausrüstungsbonus, z.B. 150)
        local num = tonumber(arg)
        if num and num > 0 and num <= 300 then
            LP.db.skillBase = num
        end
        LP.RefreshSkill()
        if LP.RefreshUI then LP.RefreshUI() end
        LP.Print(L["Skill list in client: %s | C_TradeSkillUI: %s"]:format(
            tostring(GetNumSkillLines ~= nil), tostring(C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID ~= nil)))
        LP.Print(L["Source: %s | Base %d + bonus %d = |cffffd100%d|r"]:format(
            tostring(LP.skillSource), LP.skillBase or 0, LP.skillBonus or 0, LP.skill or 0))
        if LP.skillEstimated then
            LP.Print(L["The value is only estimated. Set it with /picky skill <number> (base value without bonus), e.g. /picky skill 150."])
        end
    elseif cmd == "dev" then
        LP.db.dev = not LP.db.dev
        LP.Print("Developer tab: " .. (LP.db.dev and "ON" or "OFF"))
        if LP.RefreshDevTab then LP.RefreshDevTab() end
    elseif cmd == "debug" or cmd == "testmode" then
        LP.SetTestMode(not LP.db.debug)
    elseif cmd == "test" then
        if LP.RunTests then LP.RunTests() end
    elseif cmd == "hover" then
        LP.Print(L["Inspecting what is under the mouse in 3 seconds ..."])
        LP.After(3, function() if LP.InspectHover then LP.InspectHover() end end)
    elseif cmd == "log" then
        local log = LP.debugLog
        if #log == 0 then LP.Print(L["The log is empty. Turn on the test mode with /picky debug."]) end
        for i = math.max(1, #log - 19), #log do DEFAULT_CHAT_FRAME:AddMessage(log[i]) end
    elseif cmd == "finder" or cmd == "duty" or cmd == "dienst" then
        LP.SetFinder(not LP.db.finder.enabled)
    elseif cmd == "lang" then
        local a = arg:lower()
        if a == "en" or a == "de" then
            PickyDB.lang = a
        elseif a == "auto" then
            PickyDB.lang = nil
        else
            LP.Print("/picky lang en | de | auto   (current: " .. (PickyDB.lang or "auto") .. ")")
            return
        end
        ReloadUI()   -- die Texte werden beim Start gesetzt, daher neu laden
    elseif cmd == "ad" then
        LP.PostAd(true)
    elseif cmd == "stats" then
        local s = LP.db.stats
        LP.Print(L["Picked: %d | Invites: %d | Total tips: %s | Thanks sent: %d"]:format(s.picked, s.invited, LP.Money(s.tips), s.thanked))
    elseif cmd == "ignore" and arg ~= "" then
        LP.db.ignore[arg:lower()] = true
        LP.Print(L["%s will be ignored."]:format(arg))
    elseif cmd == "reset" then
        PickyDB = nil
        ReloadUI()
    else
        LP.Print("/lp | /lp duty | /lp ad | /lp stats | /lp skill [number] | /lp ignore <name> | /lp lang en|de|auto | /lp debug | /lp dev | /lp test | /lp hover | /lp log | /lp reset")
    end
end
