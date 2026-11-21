-- Picky / Core.lua : namespace, settings, helper functions, slash commands
local ADDON, LP = ...
_G.Picky = LP
local L = LP.L
-- Version comes from the TOC (## Version), so it can never go stale
do
    local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local ok, v = pcall(function() return getMeta and getMeta(ADDON, "Version") end)
    LP.version = (ok and v and v ~= "") and v or "?"
end
LP.PICK_SPELL_ID = 1804

_G.BINDING_HEADER_PICKY = "Picky"
LP.OnLanguage(function()
    _G.BINDING_NAME_PICKY_TOGGLE = L["Picky window"]
    _G.BINDING_NAME_PICKY_AD = L["Announce service in trade chat"]
end)

LP.defaults = {
    pick = { hint = true },
    finder = {
        enabled = false,
        autoInvite = true,
        onlyWhenFree = true,
        inviteUnknown = true,
        autoAccept = true,
        welcome = true,
        thanks = true,
        autoLeave = true,
        leaveDelay = 10,       -- seconds to wait after the last trade, then Picky leaves the group
        idleLeave = 180,
        sound = true,
        cooldown = 180,
        maxAge = 120,
        welcomeText = L["default.welcome"],
        thanksText = L["default.thanks"],
        tooHighReply = true,
        tooHighText = L["default.toohigh"],
    },
    ad = {
        channelMatch = "handel,trade",
        text = L["default.ad"],
    },
    ui = {
        minimap = true, angle = 215,
        toast = true,        -- notification on requests / join / tip
        chatLine = false,    -- additionally a line in chat
        flash = true,        -- flash the taskbar
        scale = 100,         -- window size in percent
    },
    stats = { picked = 0, tips = 0, invited = 0, thanked = 0 },
    ignore = {},
    orders = {},         -- all orders/requests, stored permanently (newest first); only you delete them
    debug = false,       -- TEST MODE: log runs, inviting/whispering/leaving/announcing are only simulated
    debugChat = false,   -- also write log lines to chat
    dev = false,         -- Developer tab (only visible via /picky dev)
    logLive = false,     -- keep the log in normal operation too (Developer tab)
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
            pcall(frame.RegisterUnitEvent, frame, event, "player")   -- only own spells, not those of all players in the raid
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

-- Helper functions -----------------------------------------------------------
function LP.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffPicky|r: " .. tostring(msg))
end

function LP.After(sec, fn)
    C_Timer.After(sec, fn)
end

-- Debug mode ----------------------------------------------------------------------
-- LP.Debug(area, format, ...) only writes when debug mode is on (otherwise costs almost nothing).
-- Areas: chat, invite, group, trade, pick, skill, ui, test, sim
LP.debugLog = {}
local DEBUG_MAX = 300
-- Two separate logs:
--  * LP.debugLog: for the USER (Test tab log): what Picky does and why. Written while test mode (or "live log") is on.
--  * LP.devLog: for the DEVELOPER (Developer tab only): internals like skill/gear scans, hover checks, roster polling.
--    Written only while the Developer tab is on (/picky dev), and never shown in the Test tab.
LP.devLog = {}
local DEV_CATS = { skill = true, ui = true, blocked = true }
local function Log(dev, cat, fmt, ...)
    if dev then
        if not (LP.db and LP.db.dev) then return end
    elseif not (LP.db and (LP.db.debug or LP.db.logLive)) then
        return
    end
    local n = select("#", ...)
    local args = { ... }
    for i = 1, n do
        if type(args[i]) ~= "number" then args[i] = tostring(args[i]) end   -- show nil/tables/booleans safely
    end
    local ok, msg = pcall(string.format, tostring(fmt), unpack(args, 1, n))
    if not ok then msg = tostring(fmt) .. " (format error)" end
    -- do not repeat the same line within a second (otherwise the log fills up with repeats)
    local key = (dev and "d|" or "u|") .. cat .. "|" .. msg
    local nowT = GetTime()
    if key == LP.lastDebugKey and nowT - (LP.lastDebugT or 0) < 1 then return end
    LP.lastDebugKey, LP.lastDebugT = key, nowT
    local line = ("%s |cff9aa0ad[%s]|r %s"):format(date("%H:%M:%S"), cat, msg)
    local log = dev and LP.devLog or LP.debugLog
    log[#log + 1] = line
    if #log > DEBUG_MAX then table.remove(log, 1) end
    if dev then
        if LP.OnDevLine then LP.OnDevLine(line) end
    else
        if LP.db.debugChat then DEFAULT_CHAT_FRAME:AddMessage("|cff00ccffPicky|r " .. line) end
        if LP.OnDebugLine then LP.OnDebugLine(line) end
    end
end
function LP.DevDebug(cat, fmt, ...) Log(true, cat, fmt, ...) end
function LP.Debug(cat, fmt, ...) Log(DEV_CATS[cat] and true or false, cat, fmt, ...) end

-- Dry run: inviting/whispering/leaving/announcing are only logged.
-- LP.forceDry is set by the simulations so they never trigger real actions.
-- Test mode on/off: log + everything is only simulated (inviting, whispering, leaving, announcing)
function LP.SetTestMode(on)
    on = on and true or false
    LP.db.debug = on
    if not on and LP.partnerSim then
        -- a simulated customer must not linger in real operation (it would silence inviting/whispering/announcing)
        LP.partner, LP.partnerSim, LP.pickedForPartner, LP.leaveAt = nil, nil, false, nil
        LP.leaveToken = (LP.leaveToken or 0) + 1
    end
    LP.Print(L["Test mode: "] .. (on and ("|cff4de88a" .. L["ON"] .. "|r") or ("|cffff5959" .. L["OFF"] .. "|r")))
    if on then
        LP.Print(L["Test mode is on: a log is kept and invites, whispers and announcements are only simulated. The Test tab has the tools."])
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

-- Same player? In this client names have two parts ("Arkanos Spellix"): chat reports the full name,
-- UnitName() and trade only "Arkanos". The first part (without realm suffix, lowercase) must match;
-- if BOTH names have a second part, it must match too ("Arkanos Spellix" is not "Arkanos Voidwalker").
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

-- Is the player on your ignore list? (same name comparison as everywhere)
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

-- Clickable spell link as it looks in chat: [Pick Lock] or [Schloss knacken]
function LP.PickLink()
    local id = LP.PICK_SPELL_ID
    local link = (C_Spell and C_Spell.GetSpellLink and C_Spell.GetSpellLink(id)) or (GetSpellLink and GetSpellLink(id))
    return link or ("[" .. LP.PickName() .. "]")
end

-- Finish the announcement text: {skill} = skill, {pick} = spell link, {city} = current zone (e.g. Stormwind),
-- a plain [Spell name] without a link also becomes a link.
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

-- Group wrappers (old/new API)
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
    if IsInRaid and IsInRaid() then   -- raid group: raid1..raidN instead of party1..4
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
    -- newer clients only have SendChatMessage under C_ChatInfo; errors are logged instead of swallowed
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    local ok, err = pcall(send, text, "WHISPER", nil, name)
    LP.Debug("invite", "whisper to %s: %s", name, ok and "sent" or ("FAILED: " .. tostring(err)))
    if not ok then LP.Print("|cffff5959" .. L["Whisper to %s failed: %s"]:format(tostring(name), tostring(err)) .. "|r") end
end
function LP.SendChannel(text, id)
    if LP.IsDry() then LP.Debug("chat", "[dry run] would post to channel %s: %s", id, text) return true end
    local send = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage
    local before = LP.blockCount or 0
    local ok, err = pcall(send, text, "CHANNEL", nil, id)
    if not ok then LP.Debug("chat", "channel post failed: %s", err) end
    -- a blocked protected call does not raise an error: it only fires ADDON_ACTION_BLOCKED (counted in Finder.lua)
    if (LP.blockCount or 0) ~= before then
        LP.Debug("chat", "channel post to %s was BLOCKED by the game (needs a click)", id)
        return false, "blocked"
    end
    return ok
end

-- Skill --------------------------------------------------------------------
-- WoW Forever has no skill list (GetNumSkillLines/GetSkillLineInfo are missing). Sources in order:
--  1. skill list (if the client has one)
--  2. C_TradeSkillUI (skill line 633 = Lockpicking)
--  3. last known value: from the skill message in chat
--  4. estimate level x 5 (last resort, marked "estimated" in the display)
-- The bonus from equipment ("Equip: Lockpicking +4" / "Anlegen: Schlossknacken +4") comes from the tooltips
-- of the equipped items (English and German).
local SKILL_NAMES = { "lockpick", "schlossknack", "schlösser", "schloss", "crochetage" }
local LOCKPICKING_SKILL_LINE = 633

local function IsLockWord(l)
    return l:find("lockpick", 1, true) or l:find("schloss", 1, true) or l:find("schlö", 1, true)
end

-- Bonus from ONE tooltip line: "Equip: Lockpicking +4." / "Anlegen: Schlossknacken +4." -> 4, otherwise 0
function LP.ParseBonus(text)
    if type(text) ~= "string" then return 0 end
    local l = text:lower()
    if IsLockWord(l) then
        local n = l:match("%+%s*(%d+)")
        if n then return tonumber(n) end
    end
    return 0
end

-- Returns the total bonus and a list of log lines (the caller logs them only when something changed)
function LP.GearBonus()
    if not (C_TooltipInfo and C_TooltipInfo.GetInventoryItem) then return 0, {} end
    local total, notes = 0, {}
    for slot = 1, 19 do
        local data = C_TooltipInfo.GetInventoryItem("player", slot)
        if data and data.lines then
            for _, line in ipairs(data.lines) do
                local b = LP.ParseBonus(line.leftText)
                if b > 0 then
                    total = total + b
                    notes[#notes + 1] = ("gear bonus +%d from slot %d: %s"):format(b, slot, tostring(line.leftText))
                end
            end
        end
    end
    return total, notes
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
    local gear, notes = LP.GearBonus()
    local bonus = math.max(apiBonus or 0, gear)
    LP.skillBase, LP.skillBonus, LP.skillMax = base, bonus, max or 0
    LP.skill = base + bonus
    LP.skillEstimated, LP.skillSource = estimated, source
    -- This runs often (window opened, equipment/skill events): log only when the result changed
    local summary = ("skill %d = base %d + bonus %d (source: %s%s)"):format(LP.skill, base, bonus, tostring(source), estimated and ", ESTIMATED" or "")
    local key = summary .. "|" .. table.concat(notes, ";")
    if key ~= LP.lastSkillLog then
        LP.lastSkillLog = key
        for _, n in ipairs(notes) do LP.Debug("skill", "%s", n) end
        LP.Debug("skill", "%s", summary)
    end
    return LP.skill
end
function LP.Skill() return LP.skill or LP.RefreshSkill() end

-- Start ----------------------------------------------------------------------
-- Saved default texts follow the game language: if the text still matches one of the two
-- bundled default texts (German/English), it is replaced by the one for the current language.
-- Custom-written texts are left untouched.
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
    LP.SetLanguage(PickyDB.lang)   -- Developer-tab language override (nil = automatic); rebuilds the texts made at load time
    -- old default text (without spell link) -> current default text
    if LP.db.ad.text == "Schurke knackt Schlösser/Kisten (Skill {skill})! Schreib mir die Kiste ins Flüstern - Trinkgeld willkommen :)" then
        LP.db.ad.text = LP.defaults.ad.text
    end
    FollowLocale(LP.db.finder, "welcomeText", "default.welcome")
    FollowLocale(LP.db.finder, "thanksText", "default.thanks")
    FollowLocale(LP.db.finder, "tooHighText", "default.toohigh")
    FollowLocale(LP.db.ad, "text", "default.ad")
    -- Test mode replaces "debug mode + dry run": if debug mode was on WITHOUT dry run, it is turned off
    -- (test mode always simulates); the old setting is removed
    if PickyDB.dryRun ~= nil then
        if PickyDB.dryRun == false then PickyDB.debug = false end
        PickyDB.dryRun = nil
    end
    -- the mini display no longer exists: remove old settings for it
    PickyDB.ui.tracker, PickyDB.ui.trackerCollapsed, PickyDB.ui.trackerPos = nil, nil, nil
    PickyDB.feedMigrated = nil
    PickyDB.ui.feed, PickyDB.ui.feedExpand, PickyDB.ui.feedPos = nil, nil, nil   -- the history field on screen no longer exists
    -- remove leftovers from earlier versions
    PickyDB.ui.lastDisplay = nil
    if PickyDB.pick then PickyDB.pick.outline, PickyDB.pick.cursor, PickyDB.pick.cursorIcon = nil, nil, nil end
    PickyDB.finder.declineText, PickyDB.finder.declineTooHigh = nil, nil
    -- wait before leaving: old default 2 s -> 15 s (several boxes in a row); once
    if not PickyDB.leaveDelayMigrated then
        PickyDB.leaveDelayMigrated = true
        if PickyDB.finder.leaveDelay == 2 then PickyDB.finder.leaveDelay = 15 end
    end
    -- 15 s was too long (the customer did not know whether more was coming): new default 10 s, once
    if not PickyDB.leaveDelay10 then
        PickyDB.leaveDelay10 = true
        if PickyDB.finder.leaveDelay == 15 then PickyDB.finder.leaveDelay = 10 end
    end
    LP.db = PickyDB
    if LP.LoadOrders then LP.LoadOrders() end   -- load saved orders (Finder.lua)
end)
LP.On("PLAYER_LOGIN", function()
    LP.RefreshSkill()
    if LP.db.debug then
        LP.Print("|cffff9d00" .. L["Test mode is ON: invites, whispers and announcements are only simulated. Turn it off in the Test tab."] .. "|r")
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
-- Skill message in chat ("Your skill in Lockpicking has increased to 151" / German) -> remember value
LP.On("CHAT_MSG_SKILL", function(_, msg)
    if type(msg) == "string" and LP.db and IsLockWord(msg:lower()) then
        local n = tonumber(msg:match("(%d+)%D*$"))
        if n and n > 0 and n <= 300 then LP.db.skillBase = n end
    end
    LP.RefreshSkill()
    if LP.RefreshUI then LP.RefreshUI() end
end)
-- Equipment changed -> re-read bonus (wait briefly until the tooltips are current)
LP.On("PLAYER_EQUIPMENT_CHANGED", function()
    LP.After(0.3, function()
        LP.RefreshSkill()
        if LP.RefreshUI then LP.RefreshUI() end
    end)
end)

-- Also save the log + history on /reload or logout (without color codes) so they are readable afterwards
LP.On("PLAYER_LOGOUT", function()
    if not LP.db then return end
    local function Clean(s) return (tostring(s):gsub("|cn[^:|]*:", ""):gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
    local log = {}
    for i, line in ipairs(LP.debugLog) do log[i] = Clean(line) end
    LP.db.savedLog = log
    -- do not save simulated orders
    local orders = LP.db.orders
    if type(orders) == "table" then
        for i = #orders, 1, -1 do if orders[i].sim then table.remove(orders, i) end end
    end
    local feed = {}
    for i, e in ipairs(LP.feed or {}) do feed[i] = Clean(e.clock .. " [" .. e.kind .. "] " .. e.text) end
    LP.db.savedFeed = feed
end)
-- Slash ---------------------------------------------------------------------------
-- Skill diagnostics (Developer tab button)
function LP.SkillDiagnostics()
    LP.RefreshSkill()
    if LP.RefreshUI then LP.RefreshUI() end
    LP.Print(L["Skill list in client: %s | C_TradeSkillUI: %s"]:format(
        tostring(GetNumSkillLines ~= nil), tostring(C_TradeSkillUI and C_TradeSkillUI.GetProfessionInfoBySkillLineID ~= nil)))
    LP.Print(L["Source: %s | Base %d + bonus %d = |cffffd100%d|r"]:format(
        tostring(LP.skillSource), LP.skillBase or 0, LP.skillBonus or 0, LP.skill or 0))
    if LP.skillEstimated then
        LP.Print(L["The value is only estimated."])
    end
end

-- Slash commands: only /lp (window), /lp duty and /lp stats are meant for users. "dev" is a hidden switch for the Developer tab.
SLASH_PICKY1, SLASH_PICKY2, SLASH_PICKY3 = "/picky", "/lp", "/schloss"
SlashCmdList["PICKY"] = function(msg)
    local cmd = ((msg or ""):match("^(%S*)") or ""):lower()
    if cmd == "" or cmd == "show" then
        LP.ToggleUI()
    elseif cmd == "duty" or cmd == "dienst" then
        LP.SetFinder(not LP.db.finder.enabled)
    elseif cmd == "stats" then
        local s = LP.db.stats
        LP.Print(L["Picked: %d | Invites: %d | Total tips: %s | Thanks sent: %d"]:format(s.picked, s.invited, LP.Money(s.tips), s.thanked))
    elseif cmd == "dev" then
        LP.db.dev = not LP.db.dev
        LP.Print("Developer tab: " .. (LP.db.dev and "ON" or "OFF"))
        if LP.RefreshDevTab then LP.RefreshDevTab() end
    else
        LP.Print("/lp | /lp duty | /lp stats")
    end
end
