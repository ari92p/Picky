-- Picky / tools/run_tests.lua : runs the addon's self tests outside the game (with LuaJIT = Lua 5.1, like WoW).
--   luajit tools/run_tests.lua [-v]
-- The WoW API is replaced by a tiny mock: frames accept every call and do nothing, units/channels/spells are fixed values.
-- This checks the LOGIC (chat detection, data, migration, flows). It does not show the real UI and not how the real client behaves.
local verbose, seed, repeats, coverage, dataFile, inspect, bench = false, nil, 1, false, nil, false, false
do
    local i = 1
    local args = arg or {}
    while i <= #args do
        local a = args[i]
        if a == "-v" then verbose = true
        elseif a == "--seed" then i = i + 1 seed = tonumber(args[i])
        elseif a == "--repeat" then i = i + 1 repeats = tonumber(args[i]) or 1
        elseif a == "--coverage" then coverage = true
        elseif a == "--data" then i = i + 1 dataFile = args[i]
        elseif a == "--inspect" then inspect = true
        elseif a == "--bench" then bench = true end
        i = i + 1
    end
end

local root = (arg and arg[0] or "tools/run_tests.lua"):match("^(.*)/tools/[^/]*$") or "."

-- ---------------------------------------------------------------------------------------------------------------
-- Mock WoW API
-- ---------------------------------------------------------------------------------------------------------------
local clock = 1000
function GetTime() clock = clock + 0.001 return clock end

-- A frame/region that accepts every method. Getters of numbers return numbers, SetScript is remembered.
local NUMERIC = { GetWidth = 100, GetHeight = 100, GetLeft = 0, GetRight = 100, GetTop = 100, GetBottom = 0, GetScale = 1,
    GetEffectiveScale = 1, GetNumPoints = 0, GetStringWidth = 100, GetStringHeight = 12, GetFrameLevel = 1, GetValue = 0,
    GetNumLines = 0, NumLines = 0, GetCursorPosition = 0, GetMaxLines = 100, GetNumChildren = 0, GetCenter = 0 }
local FALSY = { IsShown = true, IsVisible = true, IsMouseOver = true, GetChecked = true, HasFocus = true, IsEnabled = true, IsMouseEnabled = true }
local frames = {}
local function NewFrame(name)
    local f = { __scripts = {}, __events = {}, __name = name, __shown = false, __text = "" }
    setmetatable(f, { __index = function(t, k)
        if type(k) ~= "string" or not k:find("^%u") then return nil end   -- methods are CamelCase; a lowercase name is a plain field (nil when unset, as in the game)
        if NUMERIC[k] then return function() return NUMERIC[k] end end
        if FALSY[k] then return function(self) if k == "IsShown" or k == "IsVisible" then return self.__shown end return false end end
        return function(self, ...)
            if k == "SetScript" then self.__scripts[(...)] = select(2, ...) return end
            if k == "HookScript" then
                local ev, fn = ...
                local old = self.__scripts[ev]
                self.__scripts[ev] = function(...) if old then old(...) end fn(...) end
                return
            end
            if k == "GetScript" then return self.__scripts[(...)] end
            if k == "RegisterEvent" or k == "RegisterUnitEvent" then self.__events[(...)] = true return end
            if k == "UnregisterEvent" then self.__events[(...)] = nil return end
            if k == "Show" then self.__shown = true return end
            if k == "Hide" then self.__shown = false return end
            if k == "SetShown" then self.__shown = (...) and true or false return end
            if k == "SetText" then self.__text = tostring((...)) return end
            if k == "GetText" then return self.__text end
            if k == "GetName" then return self.__name end
            if k == "IsProtected" then return false, false end
            if k == "GetRect" then return 10, 10, 30, 30 end
            if k == "SetParent" then rawset(self, "__parent", (...)) return end
            if k == "SetAlpha" then rawset(self, "__alpha", (...)) return end
            if k == "GetAlpha" then return rawget(self, "__alpha") or 1 end
            if k == "GetParent" and rawget(self, "__parent") then return rawget(self, "__parent") end
            if k == "CreateTexture" or k == "CreateFontString" or k == "CreateAnimationGroup" or k == "CreateAnimation" or k == "GetParent"
                or k == "GetNormalTexture" or k == "GetHighlightTexture" or k == "GetPushedTexture" or k == "GetFontString" or k == "GetThumbTexture"
                or k == "GetScrollChild" or k == "GetRegions" or k == "GetChildren" then
                return NewFrame()
            end
            if k == "GetPoint" then return "CENTER", nil, "CENTER", 0, 0 end
            if k == "SetPassThroughButtons" then rawset(self, "__pass", table.concat({ ... }, ",")) return end
            if k == "RegisterForClicks" then rawset(self, "__clicks", table.concat({ ... }, ",")) return end
            if k == "SetAttribute" then local n, v = ... rawset(self, "__attrs", rawget(self, "__attrs") or {}) self.__attrs[n] = v return end
            if k == "GetAttribute" then local at = rawget(self, "__attrs") return at and at[(...)] end
            return self
        end
    end })
    return f
end
function CreateFrame(kind, name, parent, template)
    if template == "ButtonFrameTemplate" or template == "LargeSideTabButtonTemplate" then error("template not available in the test runner") end   -- the addon has fallbacks
    local f = NewFrame(name)
    rawset(f, "__parent", parent)
    if name then _G[name] = f end
    frames[#frames + 1] = f
    return f
end
UIParent = NewFrame("UIParent")
Minimap = NewFrame("Minimap")
GameTooltip = NewFrame("GameTooltip")
DEFAULT_CHAT_FRAME = { AddMessage = function(_, m) if verbose then print("[chat] " .. tostring(m)) end end }
UISpecialFrames = {}
StaticPopupDialogs = {}
SlashCmdList = {}
BackdropTemplateMixin = {}
UNKNOWNOBJECT = "Unknown"
ERR_TRADE_COMPLETE = "Trade complete."   -- client texts the addon compares chat/system messages with
ERR_TRADE_CANCELLED = "Trade cancelled."

-- timers: queued, not run (a test that needs them runs them itself)
local timers = {}
C_Timer = { After = function(sec, fn) timers[#timers + 1] = { sec = sec, fn = fn } end, NewTimer = function() return NewFrame() end, NewTicker = function() return NewFrame() end }

-- player and world
function UnitName() return "Tester" end
function UnitClass() return "Rogue", "ROGUE", 4 end
function UnitLevel() return 60 end
function UnitGUID() return "Player-4440-0123ABCD" end
function UnitExists() return false end
function UnitIsPlayer() return false end
function UnitFactionGroup() return "Alliance" end
function GetRealmName() return "" end
function GetNormalizedRealmName() return "" end
function GetLocale() return "enUS" end
function GetRealZoneText() return "Stormwind City" end
function GetZoneText() return "Stormwind City" end
function IsInGuild() return false end
function IsInGroup() return false end
function IsInRaid() return false end
function GetNumGroupMembers() return 0 end
function GetNumSubgroupMembers() return 0 end
function GetNumPartyMembers() return 0 end
function GetNumRaidMembers() return 0 end
function IsShiftKeyDown() return false end
function IsControlKeyDown() return false end
function IsAltKeyDown() return false end
function IsMouseButtonDown() return false end
function InCombatLockdown() return false end
function GetChannelList() return 1, "General - Stormwind City", false, 2, "Trade - Stormwind City", false, 3, "LocalDefense - Stormwind City", false end
function GetNumSkillLines() return 0 end
function GetSkillLineInfo() return nil end
function GetInventoryItemLink() return nil end
function GetInventorySlotInfo() return 1 end
function GetItemInfo(id) return nil end
function GetSpellInfo(id) if id == 1804 then return "Pick Lock" end end
function GetSpellLink(id) return "|cff71d5ff|Hspell:" .. tostring(id) .. "|h[Pick Lock]|h|r" end
function IsPlayerSpell(id) return id == 1804 end
function IsSpellKnown(id) return id == 1804 end
function GetContainerNumSlots() return 0 end
function GetContainerItemID() return nil end
function GetContainerItemLink() return nil end
function GetTradeTargetItemLink() return nil end
function GetMoney() return 0 end
function PlaySound() end
function PlaySoundFile() end
function FlashClientIcon() end
function InviteUnit() end
function SendChatMessage() end
function LeaveParty() end
function PlayerCanLeaveGroup() return true end
function GetCursorInfo() return nil end
function ClearCursor() end
function GetCursorPosition() return 0, 0 end
function hooksecurefunc() end
function issecurevalue() return false end
function StaticPopup_Show() end
function CloseDropDownMenus() end
function SetCVar() end
function GetCVar() return "0" end
function SecureCmdOptionParse() return nil end
function InterfaceOptions_AddCategory() end
function GetLevel() return 60 end
C_ChatInfo = { SendChatMessage = function() end }
C_Container = { GetContainerNumSlots = function() return 16 end, GetContainerItemID = function() return nil end, GetContainerItemLink = function() return nil end,
    GetContainerItemInfo = function() return nil end, UseContainerItem = function() end }
C_PartyInfo = { InviteUnit = function() end, LeaveParty = function() end }
C_AddOns = { GetAddOnMetadata = function(_, field) if field == "Version" then return "test" end end, IsAddOnLoaded = function() return false end }
C_Item = { RequestLoadItemDataByID = function() end }
C_Spell = nil
C_TooltipInfo = nil
-- a character with Lockpicking 156 in the skill list (the new client API)
C_SkillInfo = { GetNumSkillLines = function() return 1 end,
    GetSkillLineInfo = function(i) return { skillName = "Lockpicking", skillRank = 156, maxRank = 300, skillModifier = 0, numTempPoints = 0, isHeader = false } end }
C_TradeSkillUI = nil

-- Lua 5.1 helpers that WoW adds
time = os.time
date = os.date
difftime = os.difftime
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
tinsert = table.insert
tremove = table.remove
strsplit = function(sep, s) local out = {} for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do out[#out + 1] = part end return unpack(out) end
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
format = string.format
strlower = string.lower
strupper = string.upper
strfind = string.find
strsub = string.sub
strlen = string.len
gsub = string.gsub
floor = math.floor
max = math.max
min = math.min
abs = math.abs
random = math.random

-- ---------------------------------------------------------------------------------------------------------------
-- Load the addon files in the order of the TOC, like the game does: each file gets (addonName, sharedTable)
-- ---------------------------------------------------------------------------------------------------------------
-- line coverage (--coverage): which lines of the addon files run at least once during the tests
local hit = {}
if coverage then
    debug.sethook(function(_, line)
        local info = debug.getinfo(2, "S")
        local src = info and info.source
        if src and src:sub(1, 1) == "@" then
            local f = src:sub(2):match("([^/]+%.lua)$")
            if f then local t = hit[f] if not t then t = {} hit[f] = t end t[line] = true end
        end
    end, "l")
end

local ADDON, LP = "Picky", {}
local toc = assert(io.open(root .. "/Picky.toc", "rb")):read("*a")
local files = {}
for line in toc:gmatch("[^\r\n]+") do
    if not line:match("^#") and line:match("%.lua%s*$") then files[#files + 1] = line:match("^%s*(.-)%s*$") end
end
for _, f in ipairs(files) do
    local chunk, err = loadfile(root .. "/" .. f)
    if not chunk then io.stderr:write("SYNTAX ERROR in " .. f .. ": " .. tostring(err) .. "\n") os.exit(2) end
    local ok, e = pcall(chunk, ADDON, LP)
    if not ok then io.stderr:write("ERROR while loading " .. f .. ": " .. tostring(e) .. "\n") os.exit(2) end
end

-- ---------------------------------------------------------------------------------------------------------------
-- Fire the startup events (a fresh install: no saved data) and run the tests
-- ---------------------------------------------------------------------------------------------------------------
local function Fire(event, ...)
    for _, f in ipairs(frames) do
        if f.__events[event] and f.__scripts.OnEvent then
            local ok, e = pcall(f.__scripts.OnEvent, f, event, ...)
            if not ok then io.stderr:write("ERROR in event " .. event .. ": " .. tostring(e) .. "\n") os.exit(2) end
        end
    end
end
PickyDB = nil
if dataFile then   -- start with a saved-variables file, like the game does: the file sets PickyDB before the addon loads
    local chunk, err = loadfile(dataFile)
    if not chunk then io.stderr:write("cannot read " .. dataFile .. ": " .. tostring(err) .. "\n") os.exit(2) end
    chunk()
end
Fire("ADDON_LOADED", ADDON)
Fire("PLAYER_LOGIN")
Fire("PLAYER_ENTERING_WORLD", true, false)

if inspect then   -- print what the addon made of the loaded data (used by tools/check_testdata.py)
    local db = PickyDB
    local function P(k, v) print(k .. "=" .. tostring(v)) end
    P("picked", db.stats and db.stats.picked) P("tips", db.stats and db.stats.tips)
    P("invited", db.stats and db.stats.invited) P("thanked", db.stats and db.stats.thanked)
    P("orders", db.orders and #db.orders)
    local names = {}
    for _, o in ipairs(db.orders or {}) do names[#names + 1] = tostring(o.name) end
    P("order_names", table.concat(names, ","))
    P("leaveDelay", db.finder and db.finder.leaveDelay)
    P("debug", db.debug) P("dev", db.dev)
    P("skillBase", db.skillBase)
    P("chars", db.chars ~= nil)
    P("tracker", db.ui and db.ui.tracker) P("feed", db.ui and db.ui.feed)
    P("declineText", db.finder and db.finder.declineText) P("outline", db.pick and db.pick.outline)
    local ch = {}
    for k in pairs((db.ad and db.ad.channels) or {}) do ch[#ch + 1] = k end
    table.sort(ch)
    P("ad_channels", table.concat(ch, ","))
    P("welcomeText", db.finder and db.finder.welcomeText ~= nil and db.finder.welcomeText ~= "")
    os.exit(0)
end

if bench then   -- timing of the hot paths (use "luajit -joff tools/run_tests.lua --bench": the game runs plain Lua 5.1 without a JIT)
    local function Time(name, n, fn)
        collectgarbage() collectgarbage()
        local m0 = collectgarbage("count")
        local t0 = os.clock()
        for _ = 1, n do fn() end
        local dt = os.clock() - t0
        local m1 = collectgarbage("count")
        print(("%-46s %9.2f us/call   (%d calls, heap %+.0f KB)"):format(name, dt / n * 1e6, n, m1 - m0))
    end
    local chat = {
        "WTS [Linen Cloth] x20 cheap, pm me", "LFM BRD need tank and healer", "anyone know where the Defias hideout is?",
        "LF rogue to open my lockbox", "Rogue 300 lockpicking, PM me for lockboxes", "Suche Schurke fuer Kiste, bezahle Trinkgeld",
        "hi guys how is everyone doing today, the weather is nice", "Verkaufe Eisenerz, 5 Stack, Preis VB", "GM can you please ban the gold sellers",
    }
    local i = 0
    Time("Analyze (public chat, mixed messages)", 20000, function() i = i % #chat + 1 LP.Analyze(chat[i], false) end)
    Time("Analyze (unrelated chatter)", 20000, function() LP.Analyze(chat[7], false) end)
    LP.db.finder.enabled = false
    Time("OnChat, Finder off (cheapest exit)", 100000, function() LP.OnChat("CHAT_MSG_CHANNEL", chat[7], "Someone-Realm", nil, "2. Trade - City", "Trade") end)
    LP.db.finder.enabled = true
    local keepDry = LP.forceDry
    Time("OnChat, Finder on, unrelated chatter", 20000, function() i = i % #chat + 1 LP.OnChat("CHAT_MSG_CHANNEL", chat[i], "Spieler" .. i .. "-Realm", true and nil, "2. Trade - City", "Trade") end)
    LP.forceDry = keepDry
    -- bags: 5 bags with 20 slots, 12 of them are boxes
    local ids = { 4634, 4637, 4636, 4638, 2589, 6356 }
    Time("  LP.Short", 100000, function() LP.Short("Spieler1-Realm") end)
    Time("  LP.IsIgnored", 100000, function() LP.IsIgnored("Spieler1") end)
    Time("  LP.ChatAllowed", 100000, function() LP.ChatAllowed("CHAT_MSG_CHANNEL", "2. Trade - City", "Trade") end)
    Time("  LP.IsRogue", 100000, function() LP.IsRogue() end)
    Time("  LP.SameName", 100000, function() LP.SameName("Spieler1", "Tester") end)
    LP.Game.BagSlots = function(bag) return bag < 5 and 20 or 0 end
    LP.Game.ContainerItemID = function(bag, slot) if slot % 2 == 0 then return ids[(slot / 2) % #ids + 1] end end
    LP.Game.SlotLocked = function(bag, slot) return slot % 4 == 0 end
    Time("LP.BoxList (100 slots, boxes among them)", 2000, function() LP.BoxList() end)
    LP.Game.BagSlots = function() return 0 end
    Time("LP.RefreshBoxes + ApplyBoxButton (empty bags)", 5000, function() LP.BoxList() end)
    os.exit(0)
end

if not LP.RunTests then io.stderr:write("LP.RunTests is missing\n") os.exit(2) end
-- Run the suite (several times in a row with --repeat; in a shuffled order with --seed). Every run must give exactly the same result.
local function Summary(res)
    local lines = {}
    for _, l in ipairs(res.lines) do lines[#lines + 1] = l[1] .. "|" .. l[2] .. "|" .. l[3] end
    table.sort(lines)
    return ("%d/%d/%d/%d\n%s"):format(res.pass, res.fail, res.warn, res.total, table.concat(lines, "\n"))
end
local first, firstSummary
for run = 1, repeats do
    local res = LP.RunTests({ seed = seed and (seed + run - 1) or nil })
    local sum = Summary(res)
    if run == 1 then first, firstSummary = res, sum
    elseif sum ~= firstSummary then
        print(("RUN %d DIFFERS from run 1: the tests are not repeatable"):format(run))
        print("run 1: " .. firstSummary:match("^[^\n]*"))
        print(("run %d: %s"):format(run, sum:match("^[^\n]*")))
        os.exit(1)
    end
end
local res = first
print(("%d/%d tests passed, %d failed, %d warnings%s%s"):format(res.pass, res.total, res.fail, res.warn,
    seed and (" (shuffled, seed " .. seed .. ")") or "", repeats > 1 and (" (" .. repeats .. " runs in a row, identical)") or ""))
for _, l in ipairs(res.lines) do print(("%s %s - %s"):format(l[1]:upper(), l[2], l[3])) end
if coverage then
    debug.sethook()
    -- a line counts as code when it is not blank, not a comment and not only a closing keyword/bracket
    local function IsCode(l)
        l = l:gsub("%-%-.*$", ""):gsub("^%s+", ""):gsub("%s+$", "")
        if l == "" then return false end
        if l:match("^end[%s,%)%}]*$") or l:match("^else$") or l:match("^[%)%}%],;]+$") or l:match("^end%)") or l:match("^},?$") or l:match("^do$") then return false end
        if l:match("^%[?%[?=*%[") then return false end
        return true
    end
    local total, covered = 0, 0
    local rows = {}
    for _, f in ipairs(files) do
        if f ~= "Tests.lua" and f ~= "Tests2.lua" and f ~= "Locale.lua" then
            local n, c, missed = 0, 0, {}
            local ln = 0
            for line in io.lines(root .. "/" .. f) do
                ln = ln + 1
                if IsCode(line) then
                    n = n + 1
                    if hit[f] and hit[f][ln] then c = c + 1 else missed[#missed + 1] = ln end
                end
            end
            total, covered = total + n, covered + c
            rows[#rows + 1] = { f = f, n = n, c = c, missed = missed }
        end
    end
    print("\nLine coverage (rough: lines that contain code and ran at least once):")
    for _, r in ipairs(rows) do
        local ranges, i = {}, 1
        while i <= #r.missed do
            local a, b = r.missed[i], r.missed[i]
            while r.missed[i + 1] and r.missed[i + 1] - b <= 3 do i = i + 1 b = r.missed[i] end
            ranges[#ranges + 1] = (a == b) and tostring(a) or (a .. "-" .. b)
            i = i + 1
        end
        print(("  %-12s %3d%%  (%d of %d lines)"):format(r.f, r.n > 0 and math.floor(r.c * 100 / r.n) or 100, r.c, r.n))
        if verbose then print("     never run: " .. table.concat(ranges, ", ")) end
    end
    print(("  %-12s %3d%%  (%d of %d lines)"):format("TOTAL", total > 0 and math.floor(covered * 100 / total) or 100, covered, total))
end
os.exit(res.fail == 0 and 0 or 1)
