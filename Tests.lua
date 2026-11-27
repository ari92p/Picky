-- Picky / Tests.lua : self tests, run in game with the button in the Developer tab.
-- The tests change nothing permanent: requests, statistics and settings are saved beforehand and
-- restored afterwards; inviting/whispering/leaving run as dry run.
local ADDON, LP = ...
local L = LP.L

local tests = {}
local function T(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

-- Check functions ------------------------------------------------------------------------------
local function fail(msg) error(msg, 0) end
local function eq(actual, expected, what)
    if actual ~= expected then
        fail(("%s: expected %s, got %s"):format(what or "value", tostring(expected), tostring(actual)))
    end
end
local function truthy(v, what) if not v then fail((what or "value") .. " should be true") end end
local function falsy(v, what) if v then fail((what or "value") .. " should be false") end end
-- Shared with Tests2.lua (more tests live there so that this file does not grow without end)
LP.TestKit = { T = T, fail = fail, eq = eq, truthy = truthy, falsy = falsy }

-- Sandbox: saves the state, sets test values, restores everything (even on errors) -----------------
local FINDER_KEYS = { "autoInvite", "onlyWhenFree", "inviteUnknown", "welcome", "thanks", "autoLeave", "idleLeave", "sound", "enabled", "tooHighReply", "tooHighText" }
local UI_KEYS = { "toast", "flash", "chatLine" }
local STAT_KEYS = { "picked", "tips", "invited", "thanked" }
local function Sandbox(setup, fn)
    local db = LP.db
    local saved = {
        requests = LP.requests, pending = LP.pending, partner = LP.partner, partnerSim = LP.partnerSim,
        pickedForPartner = LP.pickedForPartner, waitTradeClose = LP.waitTradeClose,
        skill = LP.skill, skillEstimated = LP.skillEstimated, inGroup = LP.InGroup, groupCount = LP.GroupCount,
        forceDry = LP.forceDry, leaveAt = LP.leaveAt, leaveToken = LP.leaveToken, feed = LP.feed, lastInviter = LP.lastInviter, finder = {}, ui = {}, stats = {},
    }
    for _, k in ipairs(FINDER_KEYS) do saved.finder[k] = db.finder[k] end
    for _, k in ipairs(UI_KEYS) do saved.ui[k] = db.ui[k] end
    for _, k in ipairs(STAT_KEYS) do saved.stats[k] = LP.db.stats[k] end

    -- Starting point: empty, dry run, no notifications/sounds
    LP.requests, LP.pending, LP.partner, LP.partnerSim, LP.pickedForPartner, LP.waitTradeClose = {}, nil, nil, nil, false, false
    LP.forceDry = true
    LP.feed, LP.lastInviter = {}, nil   -- the history of the tests must not end up in the real history
    LP.InGroup = function() return false end
    LP.GroupCount = function() return 1 end
    db.ui.toast, db.ui.flash, db.ui.chatLine, db.finder.sound = false, false, false, false
    db.finder.enabled, db.finder.autoInvite, db.finder.onlyWhenFree, db.finder.inviteUnknown = true, true, true, true
    db.finder.welcome, db.finder.thanks, db.finder.autoLeave = true, true, true
    LP.skill, LP.skillEstimated = 200, false
    local ok, err = pcall(function()   -- setup() is protected too: an error must never permanently distort the state
        if setup then setup(db) end
        fn(db)
    end)

    LP.requests, LP.pending, LP.partner, LP.partnerSim = saved.requests, saved.pending, saved.partner, saved.partnerSim
    LP.pickedForPartner, LP.waitTradeClose = saved.pickedForPartner, saved.waitTradeClose
    LP.skill, LP.skillEstimated, LP.InGroup, LP.GroupCount, LP.forceDry = saved.skill, saved.skillEstimated, saved.inGroup, saved.groupCount, saved.forceDry
    LP.leaveAt, LP.leaveToken = saved.leaveAt, saved.leaveToken
    LP.feed, LP.lastInviter = saved.feed, saved.lastInviter
    for k, v in pairs(saved.finder) do db.finder[k] = v end
    for k, v in pairs(saved.ui) do db.ui[k] = v end
    for k, v in pairs(saved.stats) do LP.db.stats[k] = v end
    if LP.RefreshAll then LP.RefreshAll() end
    if not ok then error(err, 0) end
end

LP.TestKit.Sandbox = Sandbox

local function Req(name, status, extra)
    local r = { name = name, status = status, msg = "x", time = GetTime() }
    if extra then for k, v in pairs(extra) do r[k] = v end end
    return r
end

-- 1) Chat detection -----------------------------------------------------------------------------------------
local ITEM_IRON = "|cffffffff|Hitem:4634::::::::60:::::|h[Iron Lockbox]|h|r"
local CHAT_CASES = {
    -- { message, whispered, should be detected, expected skill (or nil) }
    { "hi can u open some low level chersts for me?", false, true },
    { "hi can u open some low level chersts for me?", true, true },
    { "LF rogue to open lockbox pls", false, true },
    { "Suche Schurke zum Schlösser knacken", false, true },
    { "need rogue for bronze chest", false, true, 25 },
    { "anyone have a rogue? mithril lockbox", false, true, 225 },
    { "can you open this thorium lockbox", true, true, 225 },
    { "Brauche einen Schurken für meine Eisenkiste", false, true, 125 },
    { "can someone unlock my chest", false, true },
    { "LF rogue pls open this " .. ITEM_IRON, false, true, 70 },
    -- Item link in the new color format (|cnIQ1:) as in WoW Forever
    { "Ich hätte eine Kiste |cnIQ1:|Hitem:6355::::::::29:1482:::::::::|h[Stabile verschlossene Truhe]|h|r", true, true, 70 },
    { "anyone know where the chest in SM is?", false, false },
    { "Kann jemand meine Stahlschließkassette öffnen bitte", true, true, 225 },
    { "suche Schurke für eine Stabile Plunderkiste", false, true },
    { "wäre jemand so lieb und könnte mir in ironforge 10 mithrilerz in barren umwandeln bitte", false, false },
    { "kann jemand 20 eisenerz schmelzen bitte", false, false },
    { "LFM dps tank heal for BRD", false, false },
    { "WTS Heavy Bronze Lockbox 5g", false, false },
    { "selling lockboxes cheap", false, false },
    { "LF rogue", false, false },
    { "hello how are you", true, false },
    { "good morning everyone", false, false },
    { "rogue lf group for deadmines", false, false },
    -- explicit skill numbers
    { "lf rogue lockpick 175 /2 me", false, true, 175 },
    { "LF rogue 150 lockpicking pls", false, true, 150 },
    { "need rogue with skill 225+ for lockbox", false, true, 225 },
    { "Suche Schurke Schlossknacken 200", false, true, 200 },
    { "need rogue to open 3 chests", false, true },
    { "LF ROGUE [Thoriumschließkassette]", false, true, 225 },
    -- a box as furniture is not a request (false positive from real chat)
    { "suche Unterschriften für Gilde wäre super gibt auch einen Buff :D  sitze auf den Kisten in sw", false, false },
    { "wer hat Kisten zu viel, suche welche", false, false },
    { "suche jemand der meine Kisten öffnen kann", false, true },
    { "lf lockpicker", false, true },
    -- advertisements of other rogues are not requests
    { "Rogue here, lockpicking 300, tips welcome, invite me", false, false },
    { "Rogue offering lockbox opening, whisper me", false, false },
    { "Schurke öffnet eure Kisten, einfach einladen", false, false },
    { "Rogue |cff71d5ff|Hspell:1804|h[Pick Lock]|h|r tips appreciated", false, false },
    { "LF rogue to open my lockbox, will tip", false, true },
    { "rogue free unlocking boxes", false, false },
    { "Rogue 300 lockpicking, PM me for lockboxes", false, false },
    { "LF lockboxes! Rogue here, tips appreciated", false, false },
    { "Lockpicker available / in Org, whisper me", false, false },
    { "LF rogue to open my lockbox, whisper me", false, true },
    { "Rogue 150 lockpicking needed for chests", false, true, 150 },
    { "Rogue 300 lockpicking, PM me for lockboxes", true, true, 300 },   -- whispered: handled as a direct message
    -- more advertisements of other rogues (EN)
    { "Rogue here, will open your lockboxes for tips", false, false },
    { "Rogue lockpicking 225, whisper me for lockboxes", false, false },
    { "[Lockpicking] Rogue opening boxes, tip if you like", false, false },
    { "Free lockbox opening, rogue in Org", false, false },
    { "Rogue available for lockboxes at the AH", false, false },
    { "Open your lockboxes! Rogue 250 lockpicking here, /w me", false, false },
    { "Rogue opening lockboxes in trade, inv me", false, false },
    { "Lockpicking service - pm me", false, false },
    -- more advertisements of other rogues (DE)
    { "Schurke öffnet Kisten für Trinkgeld", false, false },
    { "Schurke 300 Schlossknacken, flüstern für Kisten", false, false },
    { "Kostenloses Schlossknacken in Orgrimmar", false, false },
    { "Schurke mit 300 Schlossknacken, Kisten öffnen gegen Trinkgeld", false, false },
    { "Biete Schlossknacken an, einfach anflüstern", false, false },
    -- more customer requests (EN)
    { "need a rogue for my chest pls", false, true },
    { "any rogue here that can open boxes?", false, true },
    { "rogue pls open junkbox, will tip", false, true },
    { "Looking for a rogue to pick a lock", false, true },
    -- more customer requests (DE)
    { "Suche Schurke zum Kisten öffnen", false, true },
    { "Kann ein Schurke bitte meine Truhe aufmachen?", false, true },
    { "brauche Schlossknacker für Kiste", false, true },
    { "wer kann mir meine Eisenkiste aufmachen? gebe Trinkgeld", false, true },
    { "Schurke, bitte meine Kiste öffnen, Trinkgeld gibt es", false, true },
}
for i, c in ipairs(CHAT_CASES) do
    T(("chat detection #%d: %s%s"):format(i, c[2] and "[whisper] " or "", c[1]:sub(1, 48)), function()
        local ok, req = LP.Analyze(c[1], c[2])
        eq(ok and true or false, c[3], "recognized")
        if c[4] then eq(req, c[4], "required skill") end
    end)
end

T("chat samples: report (every sample with the verdict, to copy from the log)", function()
    local wrong = 0
    for _, c in ipairs(CHAT_CASES) do
        local ok, req, _, why = LP.Analyze(c[1], c[2])
        ok = ok and true or false
        local good = (ok == c[3])
        if not good then wrong = wrong + 1 end
        LP.Debug("test", "%s %s%s -> %s%s | %s", good and "OK  " or "WRONG", c[2] and "[whisper] " or "", ok and "REQUEST" or (why and why.ad and "ad (ignored)" or "ignored"), req and ("skill " .. req) or "no skill", good and "" or ("  (expected " .. (c[3] and "request" or "ignored") .. ")"), c[1])
    end
    LP.Debug("test", "chat samples: %d total, %d wrong", #CHAT_CASES, wrong)
    eq(wrong, 0, "samples with a wrong verdict")
end)
T("box keyword: whole word only ('iron' is a box, 'ironforge' is a city)", function()
    local ok1, req1 = LP.Analyze("LF rogue open chest in ironforge", false)
    eq(ok1 and true or false, true, "still a request")
    eq(req1, nil, "ironforge gives no skill estimate")
    local _, req2 = LP.Analyze("need rogue for iron chest", false)
    eq(req2, 125, "iron chest")
    local _, req3 = LP.Analyze("Brauche einen Schurken für meine Eisenkiste", false)
    eq(req3, 125, "Eisenkiste")
end)

-- 2) Helper functions -------------------------------------------------------------------------------------------
T("Money formatting", function()
    eq(LP.Money(0), "0g", "0")
    eq(LP.Money(5), "5k", "5")
    eq(LP.Money(100), "1s", "100")
    eq(LP.Money(10000), "1g", "10000")
    eq(LP.Money(12345), "1g 23s 45k", "12345")
    eq(LP.Money(10101), "1g 1s 1k", "10101")
end)
T("time formatting (m:ss)", function()
    eq(LP.Mmss(0), "0:00")
    eq(LP.Mmss(65), "1:05")
    eq(LP.Mmss(3599), "59:59")
    eq(LP.Mmss(-5), "0:00")
end)
T("gear bonus line parsing (English + German)", function()
    eq(LP.ParseBonus("Equip: Lockpicking +4."), 4, "english")
    eq(LP.ParseBonus("Equip: Increased Lockpicking +12."), 12, "english 12")
    eq(LP.ParseBonus("Anlegen: Schlossknacken +4."), 4, "german")
    eq(LP.ParseBonus("Anlegen: Schlösser knacken +3."), 3, "german plural")
    eq(LP.ParseBonus("+6 Agility"), 0, "other stat")
    eq(LP.ParseBonus(nil), 0, "nil")
end)
T("'locked' tooltip words", function()
    truthy(LP.IsLockedText("Locked"), "Locked")
    truthy(LP.IsLockedText("Verschlossen"), "Verschlossen")
    truthy(LP.IsLockedText("Abgeschlossen"), "Abgeschlossen")
    falsy(LP.IsLockedText("<Right Click to Open>"), "open hint")
    falsy(LP.IsLockedText(nil), "nil")
end)
T("just-picked box counts as open for a few seconds (no second pick on an open box)", function()
    -- Slots that do not exist in the real backpack (bag 90/91): the test touches no real slot
    -- A slot number that is new on every run: the grace period (3 s) of an earlier run must not make a second run fail
    local slot = math.floor(GetTime() * 1000)
    falsy(LP.RecentlyPicked(90, slot), "fresh slot")
    LP.MarkPicked(90, slot)
    truthy(LP.RecentlyPicked(90, slot), "marked slot")
    falsy(LP.RecentlyPicked(90, slot + 1), "other slot unaffected")
    falsy(LP.RecentlyPicked(91, slot), "other bag unaffected")
end)
T("feed: events are stored in order and capped", function()
    local saved = LP.feed
    LP.feed = {}
    local ok, err = pcall(function()
        LP.Feed("request", "one")
        LP.Feed("invite", "two")
        eq(#LP.feed, 2, "two entries")
        eq(LP.feed[1].text, "one", "oldest first")
        eq(LP.feed[2].kind, "invite", "kind stored")
        truthy(LP.feed[2].clock and LP.feed[2].clock ~= "", "clock stored")
        for i = 1, 70 do LP.Feed("pick", "x" .. i) end
        truthy(#LP.feed <= 50, "capped at 50")
        eq(LP.feed[#LP.feed].text, "x70", "newest kept")
    end)
    LP.feed = saved
    if LP.RefreshFeed then LP.RefreshFeed() end
    if not ok then error(err, 0) end
end)
T("feed: a chat request writes request + invite lines", function()
    local saved = LP.feed
    LP.feed = {}
    local ok, err = pcall(function()
        Sandbox(nil, function()
            LP.SimulateChat("LF rogue to open a bronze lockbox pls", false)
            local kinds = {}
            for _, e in ipairs(LP.feed) do kinds[#kinds + 1] = e.kind end
            eq(kinds[1], "request", "first entry")
            eq(kinds[2], "invite", "second entry")
        end)
    end)
    LP.feed = saved
    if LP.RefreshFeed then LP.RefreshFeed() end
    if not ok then error(err, 0) end
end)
T("read channels: switched-off sources are skipped, new ones are read, whispers never filtered", function()
    local f = LP.db.finder
    local was = f.readOff
    f.readOff = nil
    truthy(LP.ReadChannelOn("trade"), "default: on")
    LP.SetReadChannel("lookingforgroup", false)
    falsy(LP.ReadChannelOn("lookingforgroup"), "switched off")
    truthy(LP.ReadChannelOn("trade"), "others stay on")
    LP.SetReadChannel("lookingforgroup", true)
    truthy(LP.ReadChannelOn("lookingforgroup"), "switched on again")
    eq(LP.ChatSourceKey("CHAT_MSG_CHANNEL", "5. Trade - Stormwind", nil), "trade", "from channel string")
    eq(LP.ChatSourceKey("CHAT_MSG_CHANNEL", "5. Trade - Stormwind", "Trade"), "trade", "from base name")
    eq(LP.ChatSourceKey("CHAT_MSG_SAY"), "say", "say")
    eq(LP.ChatSourceKey("CHAT_MSG_WHISPER"), nil, "whisper has no source")
    f.readOff = was
end)
T("advertise channels: default is the normal trade channel, never the local one", function()
    local ad = LP.db.ad
    local was = ad.channels
    ad.channels = nil   -- no own choice: the default rule applies
    local function on(name) return LP.AdChannelOn({ name = name, key = LP.ChannelKey(name) }) end
    truthy(on("Trade"), "Trade")
    falsy(on("TradeLocal"), "TradeLocal")
    falsy(on("Services"), "Services (few players, not the default)")
    truthy(on("Trade - City"), "Trade - City")
    truthy(on("Handel - Deutsch 33"), "Handel - Deutsch 33")
    falsy(on("Handel Lokal"), "Handel Lokal")
    falsy(on("General"), "General")
    falsy(on("LookingForGroup"), "LookingForGroup")
    ad.channels = was
end)
T("advertise channels: what the game reports right now (read-only report)", function()
    local ad = LP.db.ad
    LP.Debug("test", "own choice saved: %s", type(ad.channels) == "table" and "YES (default rule is not used)" or "no (default rule)")
    if type(ad.channels) == "table" then
        for k, v in pairs(ad.channels) do LP.Debug("test", "  saved: %s = %s", tostring(k), tostring(v)) end
    end
    local list = LP.ChannelList()
    for _, ch in ipairs(list) do
        LP.Debug("test", "channel %d: '%s' key='%s' advertise=%s listen=%s", ch.id, ch.name, ch.key, tostring(LP.AdChannelOn(ch)), tostring(LP.ReadChannelOn(ch.key)))
    end
    if #list == 0 then return "warn: no channels joined" end
end)
T("guide stage by skill", function()
    eq(LP.StageForSkill(1), 1, "1")
    eq(LP.StageForSkill(109), 1, "109")
    eq(LP.StageForSkill(110), 2, "110")
    eq(LP.StageForSkill(149), 2, "149")
    eq(LP.StageForSkill(150), 3, "150")
    eq(LP.StageForSkill(199), 3, "199")
    eq(LP.StageForSkill(200), 4, "200")
    eq(LP.StageForSkill(249), 4, "249")
    eq(LP.StageForSkill(250), 5, "250")
    eq(LP.StageForSkill(300), 5, "300")
end)
T("announcement text placeholders", function()
    local text = LP.ExpandAd("Skill {skill} and {pick}!")
    falsy(text:find("{skill}", 1, true), "{skill} replaced")
    falsy(LP.ExpandAd("Bin in {city}."):find("{city}", 1, true), "{city} replaced")
    falsy(text:find("{pick}", 1, true), "{pick} replaced")
    truthy(text:find(tostring(LP.Skill()), 1, true), "skill number present")
end)
T("debug log accepts nil/table/number arguments", function()
    local db = LP.db
    local was = db.debug
    db.debug = true
    local before = #LP.debugLog
    local stamp = math.floor(GetTime() * 1000)   -- unique, so the de-duplication (same line within 1 s) does not interfere
    LP.Debug("test", "nil args %d: %s %d %s", stamp, nil, 5, {})
    LP.Debug("test", "no arguments %d", stamp + 1)
    db.debug = was
    eq(#LP.debugLog >= before + 2 or #LP.debugLog == 300, true, "two lines logged")
end)

-- 3) Translations -------------------------------------------------------------------------------------------------
local function count(s, pat)
    local n = 0
    for _ in s:gmatch(pat) do n = n + 1 end
    return n
end
T("translations: same format placeholders in English and German", function()
    local en, de = LP.LOCALE.EN, LP.LOCALE.DE
    local bad = {}
    for key, val in pairs(de) do
        local ref = en[key] or key
        if count(val, "%%[sd]") ~= count(ref, "%%[sd]") then bad[#bad + 1] = key end
        if count(val, "|c") ~= count(ref, "|c") or count(val, "|r") ~= count(ref, "|r") then bad[#bad + 1] = key .. " (color codes)" end
        if val == "" then bad[#bad + 1] = key .. " (empty)" end
    end
    if #bad > 0 then fail("mismatch in: " .. table.concat(bad, "; ")) end
end)
T("translations: ad/welcome defaults keep their placeholders", function()
    local en, de = LP.Both("default.ad")
    truthy(en:find("{pick}", 1, true) and en:find("{skill}", 1, true), "english ad")
    truthy(de:find("{pick}", 1, true) and de:find("{skill}", 1, true), "german ad")
    truthy(en ~= de, "languages differ")
end)
T("translations: saved default text follows the client language", function()
    local en, de = LP.Both("default.welcome")
    local tbl = { a = en, b = de, c = "my own text" }
    LP.FollowLocale(tbl, "a", "default.welcome")
    LP.FollowLocale(tbl, "b", "default.welcome")
    LP.FollowLocale(tbl, "c", "default.welcome")
    eq(tbl.a, L["default.welcome"], "english default switched")
    eq(tbl.b, L["default.welcome"], "german default switched")
    eq(tbl.c, "my own text", "own text untouched")
end)

-- 4) Decision logic (dry run) ---------------------------------------------------
T("decide: skill too low -> not invited", function()
    Sandbox(nil, function()
        LP.skill = 100
        local r = Req("A", "new", { req = 175 })
        LP.Decide(r)
        eq(r.status, "toohigh", "status")
        eq(LP.pending, nil, "pending")
    end)
end)
T("decide: skill enough -> invited", function()
    Sandbox(nil, function()
        local r = Req("A", "new", { req = 175 })
        LP.Decide(r)
        eq(r.status, "invited", "status")
        eq(LP.pending, r, "pending")
    end)
end)
T("decide: box unknown + 'invite unknown' on -> invited", function()
    Sandbox(nil, function()
        local r = Req("A", "new")
        LP.Decide(r)
        eq(r.status, "invited", "status")
    end)
end)
T("decide: box unknown + 'invite unknown' off -> manual", function()
    Sandbox(function(db) db.finder.inviteUnknown = false end, function()
        local r = Req("A", "new")
        LP.Decide(r)
        eq(r.status, "manual", "status")
    end)
end)
T("decide: auto invite off -> waits for click", function()
    Sandbox(function(db) db.finder.autoInvite = false end, function()
        local r = Req("A", "new", { req = 25 })
        LP.Decide(r)
        eq(r.status, "new", "status")
    end)
end)
T("decide: already in a group -> queued", function()
    Sandbox(nil, function()
        LP.InGroup = function() return true end
        local r = Req("A", "new", { req = 25 })
        LP.Decide(r)
        eq(r.status, "queued", "status")
    end)
end)
T("invite: full group -> queued", function()
    Sandbox(nil, function()
        LP.GroupCount = function() return 5 end
        local r = Req("A", "new", { req = 25 })
        LP.TryInvite(r)
        eq(r.status, "queued", "status")
    end)
end)

-- 5) State / display data ------------------------------------------------------------------------------------------
T("state: counts, phase and next invitable", function()
    Sandbox(nil, function()
        local a, b, c = Req("A", "done"), Req("B", "queued"), Req("C", "new")
        LP.requests = { c, b, a }   -- newest first
        local st = LP.GetState()
        eq(st.waiting, 1, "waiting")
        eq(st.open, 2, "open")
        eq(st.phase, "idle", "phase")
        eq(LP.NextInvitable(), b, "oldest invitable")
        LP.pending = Req("P", "invited")
        eq(LP.GetState().phase, "invited", "invited phase")
        LP.pending = nil
        local g = Req("G", "grouped")
        LP.requests[#LP.requests + 1] = g
        LP.partner = "G"
        eq(LP.GetState().phase, "grouped", "grouped phase")
    end)
end)

-- 6) Whole flow with simulation ---------------------------------------------------------------------------------------
T("flow: request -> invite -> join -> tip -> pick -> leave (simulated, nothing real is sent)", function()
    Sandbox(nil, function(db)
        local before = { picked = LP.db.stats.picked, tips = LP.db.stats.tips, invited = LP.db.stats.invited }
        local r = LP.SimulateChat("LF rogue to open a bronze lockbox pls", false)
        truthy(r, "request created")
        eq(r.status, "invited", "after request")
        eq(LP.pending, r, "pending")
        LP.SimulateJoin()
        eq(LP.partner, r.name, "customer in group")
        eq(r.status, "grouped", "status grouped")
        LP.SimulateTip(12500)
        LP.SimulatePick()
        truthy(LP.pickedForPartner, "pick recorded for customer")
        LP.SimulateLeave()
        eq(LP.partner, nil, "customer gone")
        eq(r.status, "done", "status done")
        eq(LP.db.stats.picked, before.picked, "stats.picked unchanged")
        eq(LP.db.stats.tips, before.tips, "stats.tips unchanged")
        eq(LP.db.stats.invited, before.invited, "stats.invited unchanged")
    end)
end)
T("flow: skill too low request is not invited", function()
    Sandbox(function() LP.skill = 50 end, function()
        LP.skill = 50
        local r = LP.SimulateChat("need rogue for thorium lockbox", false)
        truthy(r, "request created")
        eq(r.status, "toohigh", "status")
        eq(LP.pending, nil, "pending")
    end)
end)
T("flow: whisper that needs a higher skill gets the editable reply (once, never in public chat)", function()
    Sandbox(function(db) db.finder.tooHighReply = true db.finder.tooHighText = "need {need} have {skill}" end, function(db)
        local sent, orig = {}, LP.Whisper
        LP.Whisper = function(to, text) sent[#sent + 1] = text end
        local ok, err = pcall(function()
            LP.skill = 160
            local pub = LP.SimulateChat("need rogue for thorium lockbox", false)
            eq(pub.status, "toohigh", "public request too high")
            eq(#sent, 0, "no reply in public chat")
            local w = LP.SimulateChat("hey can you open my thorium lockbox?", true)
            eq(w.status, "toohigh", "whisper too high")
            eq(#sent, 1, "one reply")
            eq(sent[1], "need 225 have 160", "placeholders filled")
            LP.ReplyTooHigh(w, true)
            eq(#sent, 1, "only once per request")
            db.finder.tooHighReply = false
            LP.SimulateChat("hey can you open my thorium lockbox?", true)
            eq(#sent, 1, "off = no reply")
        end)
        LP.Whisper = orig
        if not ok then error(err, 0) end
    end)
end)
T("flow: second request while a customer is in the group is queued", function()
    Sandbox(nil, function()
        local first = LP.SimulateChat("LF rogue open my bronze chest pls", false)
        LP.SimulateJoin()
        LP.InGroup = function() return true end
        local second = LP.SimulateChat("hi can u open my iron lockbox pls", false)
        eq(second.status, "queued", "second status")
        eq(first.status, "grouped", "first still in group")
    end)
end)
T("dry run: invite and whisper are only logged", function()
    Sandbox(nil, function()
        local db = LP.db
        local was = db.debug
        LP.forceDry = false   -- check the TEST MODE itself, not the sandbox
        db.debug = true
        local before = #LP.debugLog
        LP.Invite("Nobody")
        LP.Whisper("Nobody", "test")
        truthy(LP.IsDry(), "test mode makes everything a dry run")
        db.debug = was
        truthy(#LP.debugLog >= before + 2 or #LP.debugLog == 300, "two dry-run lines logged")
    end)
end)

T("group: a requester who invites YOU is recognized as customer", function()
    local orig = LP.InGroupWith
    local ok, err = pcall(function()
        Sandbox(nil, function()
            LP.InGroup = function() return true end
            LP.InGroupWith = function(n) return n == "Anna" end
            local r = Req("Anna", "new", { sender = "Anna" })
            LP.requests = { r }
            truthy(LP.CheckRoster(), "customer detected")
            eq(LP.partner, "Anna", "partner")
            eq(r.status, "grouped", "status")
        end)
    end)
    LP.InGroupWith = orig
    if not ok then error(err, 0) end
end)
T("auto accept: with the setting on and the finder on, every invite is accepted (no announcement needed)", function()
    local saved = { ad = LP.lastAd, seen = LP.lastAdSeen, aa = LP.db.finder.autoAccept }
    local ok, err = pcall(function()
        Sandbox(function(db) db.finder.autoAccept = true end, function()
            LP.lastAd, LP.lastAdSeen = nil, nil
            local yes, why = LP.ShouldAcceptInvite("Stranger Person")
            truthy(yes, "stranger, no announcement: " .. tostring(why))
            LP.lastAdSeen = GetTime() - 700
            truthy(LP.ShouldAcceptInvite("Stranger Person"), "announcement long ago")
        end)
    end)
    LP.lastAd, LP.lastAdSeen, LP.db.finder.autoAccept = saved.ad, saved.seen, saved.aa
    if not ok then error(err, 0) end
end)T("auto accept: known requester, ignored player, existing group and setting off", function()
    local saved = { ad = LP.lastAd, seen = LP.lastAdSeen, aa = LP.db.finder.autoAccept, ig = LP.db.ignore["blocked"] }
    local ok, err = pcall(function()
        Sandbox(function(db) db.finder.autoAccept = true end, function(db)
            LP.lastAd, LP.lastAdSeen = nil, nil
            LP.requests = { Req("Anna Test", "new") }
            truthy(LP.ShouldAcceptInvite("Anna"), "known requester (first name only)")
            LP.lastAdSeen = GetTime()
            db.ignore["blocked"] = true
            falsy(LP.ShouldAcceptInvite("Blocked"), "ignored player even after announcement")
            LP.InGroup = function() return true end
            falsy(LP.ShouldAcceptInvite("Stranger"), "already in a group")
            LP.InGroup = function() return false end
            db.finder.autoAccept = false
            falsy(LP.ShouldAcceptInvite("Stranger"), "setting off")
            db.finder.enabled = false
            db.finder.autoAccept = true
            falsy(LP.ShouldAcceptInvite("Stranger"), "finder off")
        end)
    end)
    LP.lastAd, LP.lastAdSeen, LP.db.finder.autoAccept, LP.db.ignore["blocked"] = saved.ad, saved.seen, saved.aa, saved.ig
    if not ok then error(err, 0) end
end)
T("thanks: tips from a customer in the group are collected, ONE thank-you when leaving", function()
    local got = {}
    local orig = LP.Whisper
    local ok, err = pcall(function()
        Sandbox(nil, function()
            LP.Whisper = function(name, text) got[#got + 1] = name end
            local r = Req("Anna", "grouped", { sender = "Anna" })
            LP.requests = { r }
            LP.partner = "Anna"
            LP.HandleTip("Anna", 15000)
            LP.HandleTip("Anna", 5000)
            eq(#got, 0, "nothing whispered while the customer is still in the group")
            eq(r.tipTotal, 20000, "tips summed")
            LP.DoLeave()
            eq(#got, 1, "exactly one thank-you when leaving")
            LP.HandleLeave()
            eq(#got, 1, "no second thank-you afterwards")
        end)
    end)
    LP.Whisper = orig
    if not ok then error(err, 0) end
end)
T("thanks: tip from someone who is not the customer is thanked right away", function()
    local got = 0
    local orig = LP.Whisper
    local ok, err = pcall(function()
        Sandbox(nil, function()
            LP.Whisper = function() got = got + 1 end
            LP.requests = {}
            LP.partner = nil
            LP.HandleTip("Passerby", 10000)
            eq(got, 1, "thanked immediately")
        end)
    end)
    LP.Whisper = orig
    if not ok then error(err, 0) end
end)
T("thanks: customer leaves on their own -> the collected thank-you is sent then", function()
    local got = 0
    local orig = LP.Whisper
    local ok, err = pcall(function()
        Sandbox(nil, function()
            LP.Whisper = function() got = got + 1 end
            local r = Req("Anna", "grouped", { sender = "Anna" })
            LP.requests = { r }
            LP.partner = "Anna"
            LP.HandleTip("Anna", 15000)
            eq(got, 0, "deferred")
            LP.HandleLeave()
            eq(got, 1, "sent when the group ended")
        end)
    end)
    LP.Whisper = orig
    if not ok then error(err, 0) end
end)
T("leave: a new trade cancels the scheduled leave (several boxes in a row)", function()
    Sandbox(nil, function()
        LP.ScheduleLeave(30)
        local token = LP.leaveToken
        LP.CancelLeave()
        truthy(LP.leaveToken ~= token, "token changed, the pending leave will not fire")
    end)
end)
T("trade without joining: an invited customer who trades counts as accepted", function()
    Sandbox(nil, function()
        local r = Req("Anna", "invited", { invitedAt = GetTime() })
        LP.requests = { r }
        LP.pending = r
        LP.HandleTradeStart("Anna")
        eq(r.status, "done", "order accepted")
        eq(LP.pending, nil, "no longer waiting for the join")
        truthy(r.tradedWithoutGroup, "marked")
        local t = Req("Bob", "timeout")
        LP.requests = { t }
        LP.HandleTradeStart("Bob-Realm")
        eq(t.status, "done", "timed-out invite still becomes accepted")
        local d = Req("Cy", "done")
        LP.requests = { d }
        LP.HandleTradeStart("Cy")
        eq(d.tradedWithoutGroup, nil, "finished orders are untouched")
        LP.HandleTradeStart("Stranger")
    end)
end)
-- Fire a game event through the addon's real event dispatcher (all registered handlers run)
local function Fire(event, ...)
    local f = LP.frame
    f:GetScript("OnEvent")(f, event, ...)
end
-- Replace calls into the game for the duration of fn (restored even on errors). They are the fields of LP.Game (the addon's own table):
-- a test NEVER assigns to a game global, that taints it for Blizzard's own code ("execution tainted by 'Picky'").
local function WithStubs(stubs, fn)
    local saved = {}
    for k, v in pairs(stubs) do saved[k] = LP.Game[k]; LP.Game[k] = v end
    local ok, err = pcall(fn)
    for k in pairs(stubs) do LP.Game[k] = saved[k] end
    if not ok then error(err, 0) end
end

T("flow (real events): invited customer never joins but trades -> order accepted, box and tip counted", function()
    Sandbox(nil, function()
        local r = LP.SimulateChat("LF rogue to open a bronze lockbox pls", false)
        eq(r.status, "invited", "invited first")
        truthy(_G.ERR_TRADE_COMPLETE, "client has the trade complete message")
        local money = 1000000
        local offer = 0
        WithStubs({
            UnitName = function(u) if u == "NPC" then return r.name end return "Me" end,
            GetMoney = function() return money end,
            GetTargetTradeMoney = function() return offer end,
        }, function()
            Fire("TRADE_SHOW")
            eq(r.status, "done", "trade opened -> accepted without joining")
            truthy(r.tradedWithoutGroup, "marked as traded without group")
            eq(LP.pending, nil, "not waiting for a join anymore")
            LP.OnPickSuccess(true)
            eq(r.boxes, 1, "box counted on the order")
            offer = 2000
            Fire("TRADE_MONEY_CHANGED")
            Fire("UI_INFO_MESSAGE", 0, _G.ERR_TRADE_COMPLETE)
            eq(r.tipTotal, 2000, "tip counted on the order")
            truthy(r.thanked, "thanks sent right away (customer is not in the group)")
            Fire("TRADE_CLOSED")
            eq(LP.tradePartner, nil, "trade partner cleared")
        end)
        eq(r.status, "done", "stays done (no 'did not join' timeout)")
    end)
end)
T("flow (real events): customer in group -> trade complete schedules the leave, click thanks and leaves", function()
    Sandbox(nil, function()
        local r = LP.SimulateChat("LF rogue to open a bronze lockbox pls", false)
        LP.SimulateJoin()
        eq(LP.partner, r.name, "customer in group")
        WithStubs({
            UnitName = function(u) if u == "NPC" then return r.name end return "Me" end,
            GetMoney = function() return 1000000 end,
            GetTargetTradeMoney = function() return 0 end,
        }, function()
            Fire("TRADE_SHOW")
            Fire("UI_INFO_MESSAGE", 0, _G.ERR_TRADE_COMPLETE)
            truthy(LP.leaveAt and LP.leaveAt > GetTime(), "leave scheduled after the completed trade (no tip, no pick needed)")
            LP.HandleTip(LP.Short(r.name), 5000, true)   -- tip arrives afterwards, thanks is deferred
            eq(r.thanked, false, "thanks deferred while the customer is in the group")
            LP.DoLeave()                                   -- what a click on the "Trade complete" popup does
            eq(LP.partner, nil, "left the group")
            truthy(r.thanked, "thanks sent when leaving")
            eq(r.status, "done", "order done")
        end)
    end)
end)
T("trade complete: customer in group -> leave is scheduled; others are ignored", function()
    Sandbox(nil, function()
        LP.partner = "Anna"
        LP.HandleTradeComplete("Bob")
        eq(LP.leaveAt, nil, "non-partner ignored")
        LP.HandleTradeComplete("Anna")
        truthy(LP.leaveAt and LP.leaveAt > GetTime(), "leave scheduled")
        LP.leaveAt = nil
        LP.HandleTradeComplete("Anna-Realm")
        truthy(LP.leaveAt ~= nil, "full name with realm matches")
        local at = LP.leaveAt
        LP.HandleTradeComplete("Anna")
        eq(LP.leaveAt, at, "live countdown is not restarted")
        LP.leaveAt = GetTime() - 5   -- stale countdown (timer failed): schedule again
        LP.HandleTradeComplete("Anna")
        truthy(LP.leaveAt > GetTime(), "stale countdown replaced")
    end)
end)
T("orders: saved orders are restored (times, expiry, stale invite, simulated dropped)", function()
    local db = LP.db
    local savedOrders, savedReq = LP.db.orders, LP.requests
    local ok, err = pcall(function()
        local nowE = time()
        LP.db.orders = {
            { name = "Fresh", status = "new", stamp = nowE - 30, msg = "x" },
            { name = "Old", status = "new", stamp = nowE - 5000, msg = "x" },
            { name = "Invited", status = "invited", stamp = nowE - 10, msg = "x" },
            { name = "Done", status = "done", stamp = nowE - 86400, boxes = 3, tipTotal = 20000, msg = "x" },
            { name = "Fake", status = "new", stamp = nowE, sim = true, msg = "x" },
        }
        LP.LoadOrders()
        eq(#LP.requests, 4, "simulated order dropped")
        truthy(LP.requests == LP.db.orders, "requests is the saved table")
        local by = {}
        for _, r in ipairs(LP.requests) do by[r.name] = r end
        eq(by.Fresh.status, "new", "fresh request stays open")
        eq(by.Old.status, "timeout", "old open request expired")
        eq(by.Invited.status, "timeout", "stale invite expired")
        eq(by.Done.status, "done", "finished order kept")
        eq(by.Done.boxes, 3, "boxes kept")
        eq(by.Done.tipTotal, 20000, "tip kept")
        truthy(math.abs((GetTime() - by.Fresh.time) - 30) < 3, "session time recomputed from the saved stamp")
    end)
    LP.db.orders, LP.requests = savedOrders, savedReq
    if not ok then error(err, 0) end
end)
T("orders: boxes are counted per customer", function()
    Sandbox(nil, function()
        local r = Req("Anna", "grouped")
        LP.requests = { r }
        LP.partner = "Anna"
        LP.OnPickSuccess(true)
        LP.OnPickSuccess(true)
        eq(r.boxes, 2, "two boxes")
    end)
end)
T("orders: a tip outside the group is added to the order and thanked right away", function()
    local got = 0
    local orig = LP.Whisper
    local ok, err = pcall(function()
        Sandbox(nil, function()
            LP.Whisper = function() got = got + 1 end
            local r = Req("Anna", "done", { sender = "Anna" })
            LP.requests = { r }
            LP.partner = nil
            LP.HandleTip("Anna", 10000)
            eq(got, 1, "thanked immediately")
            eq(r.tipTotal, 10000, "added to the order")
            truthy(r.thanked, "marked as thanked")
        end)
    end)
    LP.Whisper = orig
    if not ok then error(err, 0) end
end)
T("orders: 'delete finished' keeps open orders, single delete works", function()
    Sandbox(nil, function()
        local a, b, c = Req("A", "done"), Req("B", "new"), Req("C", "timeout")
        LP.requests = { a, b, c }
        eq(LP.ClearDone(), 2, "two finished orders removed")
        eq(#LP.requests, 1, "one left")
        truthy(LP.requests[1] == b, "the open order was kept")
        LP.RemoveOrder(b)
        eq(#LP.requests, 0, "removed by hand")
    end)
end)
T("orders: open requests expire after 15 minutes", function()
    Sandbox(nil, function()
        local old, fresh = Req("Old", "new"), Req("Fresh", "new")
        old.time = GetTime() - 1000
        LP.requests = { fresh, old }
        LP.ExpireOpen()
        eq(old.status, "timeout", "old one expired")
        eq(fresh.status, "new", "fresh one stays")
    end)
end)
T("leave: the 'Leave' button thanks and leaves immediately", function()
    local got = 0
    local orig = LP.Whisper
    local ok, err = pcall(function()
        Sandbox(nil, function()
            LP.Whisper = function() got = got + 1 end
            local r = Req("Anna", "grouped", { sender = "Anna", tipTotal = 15000 })
            LP.requests = { r }
            LP.partner = "Anna"
            LP.LeaveNow()
            eq(LP.partner, nil, "left the group")
            eq(r.status, "done", "order finished")
            truthy(r.endStamp, "end time recorded")
            eq(got, 1, "one thank-you")
        end)
    end)
    LP.Whisper = orig
    if not ok then error(err, 0) end
end)
T("group: with the finder on, everyone who invites you becomes a customer (even without an announcement)", function()
    local orig, ad, seen = LP.InGroupWith, LP.lastAd, LP.lastAdSeen
    local ok, err = pcall(function()
        Sandbox(nil, function()
            LP.db.finder.enabled = true
            LP.lastAd, LP.lastAdSeen = nil, nil
            LP.InGroup = function() return true end
            LP.InGroupWith = function() return true end
            LP.lastInviter = { name = "Friend Name", t = GetTime() }
            LP.requests = {}
            truthy(LP.CheckRoster(), "customer created")
            truthy(LP.partner ~= nil, "partner set")
        end)
    end)
    LP.InGroupWith, LP.lastAd, LP.lastAdSeen = orig, ad, seen
    if not ok then error(err, 0) end
end)
T("group: with the finder off, an invite does not create an order", function()
    local orig = LP.InGroupWith
    local ok, err = pcall(function()
        Sandbox(nil, function()
            LP.db.finder.enabled = false
            LP.InGroup = function() return true end
            LP.InGroupWith = function() return true end
            LP.lastInviter = { name = "Friend Name", t = GetTime() }
            LP.requests = {}
            falsy(LP.CheckRoster(), "no customer")
            eq(#LP.requests, 0, "no order created")
        end)
    end)
    LP.InGroupWith = orig
    if not ok then error(err, 0) end
end)
T("group: a stranger who invites you shortly after your announcement becomes a customer", function()
    local orig, ad, seen = LP.InGroupWith, LP.lastAd, LP.lastAdSeen
    local ok, err = pcall(function()
        Sandbox(nil, function()
            LP.lastAd, LP.lastAdSeen = nil, GetTime() - 30
            LP.InGroup = function() return true end
            LP.InGroupWith = function() return true end
            LP.lastInviter = { name = "Stranger", t = GetTime() }
            LP.requests = {}
            truthy(LP.CheckRoster(), "customer created")
            truthy(LP.partner ~= nil, "partner set")
        end)
    end)
    LP.InGroupWith, LP.lastAd, LP.lastAdSeen = orig, ad, seen
    if not ok then error(err, 0) end
end)
T("queue: a request while another invite is still pending is queued", function()
    Sandbox(nil, function()
        LP.pending = Req("First", "invited")
        local r = Req("Second", "new", { req = 25 })
        LP.Decide(r)
        eq(r.status, "queued", "second request waits")
    end)
end)
T("requests: asking again after 'no answer' / 'skill too low' re-evaluates the request", function()
    Sandbox(nil, function()
        local r = Req("Anna", "timeout", { sender = "Anna" })
        LP.requests = { r }
        LP.OnChat("CHAT_MSG_WHISPER", "can you open my bronze lockbox please", "Anna", true)
        eq(r.status, "invited", "re-decided and invited")
    end)
end)
T("requests: someone whose order is finished and who writes again gets a NEW order", function()
    Sandbox(nil, function()
        LP.requests = { Req("Anna", "done", { sender = "Anna", time = GetTime() }) }
        LP.OnChat("CHAT_MSG_WHISPER", "can you open my bronze lockbox please", "Anna", true)
        eq(#LP.requests, 2, "second order created")
        eq(LP.requests[2].status, "done", "the finished order stays untouched")
    end)
end)T("names: both-part names must match; the ignore list uses the same comparison", function()
    falsy(LP.SameName("Arkanos Spellix", "Arkanos Voidwalker"), "same first name, different second name")
    truthy(LP.SameName("Arkanos Spellix", "Arkanos Spellix-Realm"), "same name with realm")
    local ig = LP.db.ignore["arkanos spellix"]
    LP.db.ignore["arkanos spellix"] = true
    local a, b, c = LP.IsIgnored("Arkanos Spellix"), LP.IsIgnored("Arkanos"), LP.IsIgnored("Arkanos Voidwalker")
    LP.db.ignore["arkanos spellix"] = ig
    truthy(a, "full name ignored")
    truthy(b, "short form of the ignored player")
    falsy(c, "a different player with the same first name")
end)
T("names: two-part names match the short form used by trade and unit names", function()
    truthy(LP.SameName("Arkanos Spellix", "Arkanos"), "full vs first name")
    truthy(LP.SameName("Arkanos", "Arkanos Spellix"), "first name vs full")
    truthy(LP.SameName("Arkanos Spellix", "Arkanos-SomeRealm"), "with realm suffix")
    truthy(LP.SameName("ARKANOS", "arkanos"), "case")
    falsy(LP.SameName("Anna", "Anne"), "different names")
    falsy(LP.SameName(nil, "Anna"), "nil")
    falsy(LP.SameName("", ""), "empty")
end)
T("names: a request is found by the short name", function()
    Sandbox(nil, function()
        local r = Req("Arkanos Spellix", "new")
        LP.requests = { r }
        eq(LP.FindRequest("Arkanos"), r, "found by first name")
        eq(LP.FindRequest("Nobody"), nil, "unknown")
    end)
end)
T("group: invited customer with a two-part name is recognized in the group", function()
    local orig = LP.InGroupWith
    local ok, err = pcall(function()
        Sandbox(nil, function()
            LP.InGroup = function() return true end
            -- the group only reports "Arkanos", the request is named "Arkanos Spellix"
            LP.InGroupWith = function(n) return LP.SameName(n, "Arkanos") end
            local r = Req("Arkanos Spellix", "invited", { sender = "Arkanos Spellix" })
            LP.requests = { r }
            LP.pending = r
            truthy(LP.CheckRoster(), "customer detected")
            eq(r.status, "grouped", "status")
            eq(LP.partner, "Arkanos Spellix", "partner")
        end)
    end)
    LP.InGroupWith = orig
    if not ok then error(err, 0) end
end)
T("group: someone you did not invite (no request) becomes a customer when you join their group", function()
    local orig = LP.InGroupWith
    local ok, err = pcall(function()
        Sandbox(nil, function()
            LP.InGroup = function() return true end
            LP.InGroupWith = function() return true end
            LP.lastInviter = { name = "Esco Ba", t = GetTime(), auto = true }   -- Picky accepted the invite itself
            LP.requests = {}
            truthy(LP.CheckRoster(), "customer created")
            eq(#LP.requests, 1, "one request created")
            eq(LP.requests[1].status, "grouped", "status")
            truthy(LP.partner ~= nil, "partner set")
            eq(LP.lastInviter, nil, "inviter consumed")
        end)
    end)
    LP.InGroupWith = orig
    if not ok then error(err, 0) end
end)
T("group: an old invite (over 3 minutes ago) does not create a customer", function()
    local orig = LP.InGroupWith
    local ok, err = pcall(function()
        Sandbox(nil, function()
            LP.InGroup = function() return true end
            LP.InGroupWith = function() return true end
            LP.lastInviter = { name = "Someone", t = GetTime() - 600 }
            LP.requests = {}
            falsy(LP.CheckRoster(), "no customer")
            eq(LP.partner, nil, "no partner")
        end)
    end)
    LP.InGroupWith = orig
    LP.lastInviter = nil
    if not ok then error(err, 0) end
end)
T("group: customer invited you FIRST, the message comes later -> customer, not 'waiting'", function()
    local orig = LP.InGroupWith
    local ok, err = pcall(function()
        Sandbox(nil, function()
            LP.InGroup = function() return true end
            LP.InGroupWith = function() return true end   -- the sender is already in my group
            local r = LP.SimulateChat("LF rogue to open a bronze lockbox pls", false)
            truthy(r, "request created")
            eq(r.status, "grouped", "status")
            eq(LP.partner, r.name, "customer recognized")
        end)
    end)
    LP.InGroupWith = orig
    if not ok then error(err, 0) end
end)
T("group: a customer already in the group who writes AGAIN is picked up too", function()
    local orig = LP.InGroupWith
    local ok, err = pcall(function()
        Sandbox(nil, function()
            -- first message: not in the group yet -> request waits/invited
            LP.InGroupWith = function() return false end
            local r = LP.SimulateChat("LF rogue to open a bronze lockbox pls", false)
            truthy(r, "request created")
            -- now they are in the group (they invited you) and write again within the wait time
            LP.InGroup = function() return true end
            LP.InGroupWith = function(n) return n == r.name end
            LP.pending = nil
            LP.OnChat("CHAT_MSG_WHISPER", "hello? can you open it", r.name, true)
            eq(LP.partner, r.name, "customer recognized on second message")
        end)
    end)
    LP.InGroupWith = orig
    if not ok then error(err, 0) end
end)
T("group: greeting whisper goes to the full sender name (cross-realm)", function()
    Sandbox(nil, function()
        local got
        local orig = LP.Whisper
        LP.Whisper = function(name) got = name end
        local ok, err = pcall(function()
            local r = Req("Anna", "invited", { sender = "Anna-OtherRealm" })
            LP.requests = { r }
            LP.pending = r
            LP.HandleJoin(r)
        end)
        LP.Whisper = orig
        if not ok then error(err, 0) end
        eq(got, "Anna-OtherRealm", "whisper target")
    end)
end)
T("group: greeting is not sent when the option is off", function()
    Sandbox(function(db) db.finder.welcome = false end, function()
        local got = false
        local orig = LP.Whisper
        LP.Whisper = function() got = true end
        local ok, err = pcall(function()
            local r = Req("Anna", "invited", { sender = "Anna" })
            LP.requests = { r }
            LP.pending = r
            LP.HandleJoin(r)
        end)
        LP.Whisper = orig
        if not ok then error(err, 0) end
        falsy(got, "whisper sent")
    end)
end)

-- 7) Live checks (hints only, do not abort) ------------------------------------------------------------------------
T("live: skill is read from the game (not estimated)", function()
    if not LP.skillEstimated then return end
    -- An estimate is correct as long as this character cannot have the skill yet: not a rogue, or Pick Lock not learned.
    -- Only a rogue who KNOWS Pick Lock and still gets an estimate points to a problem with reading the skill list.
    local known = (IsPlayerSpell and IsPlayerSpell(LP.PICK_SPELL_ID)) or (IsSpellKnown and IsSpellKnown(LP.PICK_SPELL_ID))
    if LP.IsRogue() and known then
        return "warn: Pick Lock is learned but the skill is only estimated - the skill list could not be read (run 'Skill diagnostics')"
    end
    LP.Debug("test", "skill is estimated, which is expected: %s", LP.IsRogue() and "Pick Lock is not learned yet" or "this character is not a rogue")
end)
T("live: Pick Lock spell name is known", function()
    local name = LP.PickName()
    if not name or name == "" then fail("spell name missing") end
    if name == "Pick Lock" and LP.isGerman then return "warn: spell name is the English fallback" end
end)
T("live: bag scan works", function()
    local checked, locked = 0, 0
    for bag = 0, 4 do
        local n = (C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag)) or 0
        for slot = 1, n do
            checked = checked + 1
            local lk = LP.IsLockedItem(bag, slot)
            if lk then locked = locked + 1 end
        end
    end
    LP.Debug("test", "bag scan: %d slots, %d locked", checked, locked)
    if checked == 0 then return "warn: no bag slots found" end
end)

-- Leak detector: a test must leave everything as it found it (saved data, shared state, replaced globals) ------------------------------------
local VOLATILE_DB = { savedLog = true, savedFeed = true, itemNames = true }   -- the addon changes these by itself
local LP_FIELDS = { "requests", "pending", "partner", "partnerSim", "pickedForPartner", "waitTradeClose", "forceDry", "InGroup", "GroupCount",
    "IsRogue", "PickLockKnown", "ReadSkillList", "skill", "skillEstimated", "skillNotLearned", "skillBase", "skillBonus", "skillMax",
    "skillSource", "feed", "recentMsgs", "lastAd", "lastAdSeen", "leaveAt", "leaveToken", "lastInviter", "quoteIndex",
    "Invite", "Whisper", "SendChannel", "SendGuild", "Leave", "After", "boxes", "boxesTooHigh", "lastPickTarget" }
local function DeepCopy(v, top)
    if type(v) ~= "table" then return v end
    local c = {}
    for k, x in pairs(v) do
        if not (top and VOLATILE_DB[k]) and type(x) ~= "function" then c[k] = DeepCopy(x) end
    end
    return c
end
local function Diff(a, b, path)   -- first difference between two copies, or nil
    if type(a) ~= type(b) then return path .. " (" .. type(a) .. " -> " .. type(b) .. ")" end
    if type(a) ~= "table" then
        if a ~= b then return ("%s (%s -> %s)"):format(path, tostring(a), tostring(b)) end
        return nil
    end
    for k, x in pairs(a) do
        local d = Diff(x, b[k], path .. "." .. tostring(k))
        if d then return d end
    end
    for k in pairs(b) do
        if a[k] == nil then return path .. "." .. tostring(k) .. " (added)" end
    end
    return nil
end
local function Snapshot()
    local snap = { db = DeepCopy(LP.db, true), fields = {}, game = {} }
    for _, k in ipairs(LP_FIELDS) do snap.fields[k] = LP[k] end
    for k, v in pairs(LP.Game) do snap.game[k] = v end
    return snap
end
-- Compares with the state before the test, restores shared fields/globals (so one leak does not make later tests fail) and names what leaked
local function Leaks(snap)
    local leaks = {}
    local d = Diff(snap.db, DeepCopy(LP.db, true), "db")
    if d then leaks[#leaks + 1] = "saved data changed: " .. d end
    for _, k in ipairs(LP_FIELDS) do
        if LP[k] ~= snap.fields[k] then
            leaks[#leaks + 1] = "LP." .. k .. " was not restored"
            LP[k] = snap.fields[k]
        end
    end
    for k, v in pairs(snap.game) do   -- the stand-ins for game calls (LP.Game is the addon's own table, so restoring is safe)
        if LP.Game[k] ~= v then
            leaks[#leaks + 1] = "LP.Game." .. k .. " was not restored"
            LP.Game[k] = v
        end
    end
    return leaks
end

-- Game globals must stay exactly as they are: a test (or the addon) that overwrites one taints it for Blizzard's code.
-- Compared once per run: values changed or removed, and new globals that do not belong to Picky.
local function GlobalSnapshot()
    local g = {}
    for k, v in pairs(_G) do g[k] = v end
    return g
end
local function GlobalChanges(before)
    local changed = {}
    for k, v in pairs(before) do
        if _G[k] ~= v then changed[#changed + 1] = tostring(k) .. " (changed)" end
    end
    for k in pairs(_G) do
        if before[k] == nil and not tostring(k):find("^Picky") then changed[#changed + 1] = tostring(k) .. " (added)" end
    end
    table.sort(changed)
    return changed
end

-- Run -------------------------------------------------------------------------------------------------------------------
-- opts.seed: run the tests in a shuffled order (a test that only passes in the usual order depends on another one)
-- Checks that need real time (only meaningful in the game; the offline runner queues timers without running them). The result comes about
-- 3 seconds after the tests and goes to the chat and the log like a test result. Out of combat only.
-- 1) A hidden click area must STAY hidden (a state driver once showed it again every second, over boxes already picked).
function LP.LiveChecks()
    if InCombatLockdown and InCombatLockdown() then return end
    local overlay = _G.PickyOverlay
    if not overlay then return end
    pcall(overlay.Hide, overlay)
    LP.After(3, function()
        if InCombatLockdown and InCombatLockdown() then return end
        local bad = {}
        if overlay:IsShown() then bad[#bad + 1] = "the click area came back by itself after it was hidden" end
        if #bad == 0 then
            LP.Print("|cff4de88aLive checks passed|r (click area stays hidden)")
            LP.Debug("test", "live checks passed")
        else
            for _, m in ipairs(bad) do
                LP.Print("|cffff5959FAIL|r live check - " .. m)
                LP.Debug("test", "FAIL live check - %s", m)
            end
        end
    end)
end

function LP.RunTests(opts)
    opts = opts or {}
    local pass, failed, warned = 0, 0, 0
    local out = {}
    local order = {}
    for i = 1, #tests do order[i] = i end
    if opts.seed then
        math.randomseed(opts.seed)
        for i = #order, 2, -1 do
            local j = math.random(1, i)
            order[i], order[j] = order[j], order[i]
        end
    end
    local globalsBefore = GlobalSnapshot()
    LP.selfTesting = true    -- LP.Print is silent until the result is printed
    for _, idx in ipairs(order) do
        local t = tests[idx]
        local snap = Snapshot()
        local ok, ret = pcall(t.fn)
        local leaks = Leaks(snap)
        if #leaks > 0 then
            failed = failed + 1
            out[#out + 1] = { "fail", t.name, "LEAK: " .. table.concat(leaks, "; ") .. (ok and "" or " | and failed: " .. tostring(ret)) }
        elseif not ok then
            failed = failed + 1
            out[#out + 1] = { "fail", t.name, tostring(ret) }
        elseif type(ret) == "string" and ret:sub(1, 5) == "warn:" then
            warned = warned + 1
            out[#out + 1] = { "warn", t.name, ret:sub(6) }
        else
            pass = pass + 1
        end
    end
    LP.selfTesting = false
    local gc = GlobalChanges(globalsBefore)
    if #gc > 0 then
        failed = failed + 1
        out[#out + 1] = { "fail", "no game global may change during the tests", "TAINT RISK: " .. table.concat(gc, ", ") }
    else
        pass = pass + 1
    end
    LP.lastTests = { pass = pass, fail = failed, warn = warned, total = #tests + 1, lines = out, seed = opts.seed }
    local head = ("%d/%d tests passed, %d failed, %d warnings"):format(pass, #tests + 1, failed, warned)
    LP.Print((failed == 0 and "|cff4de88a" or "|cffff5959") .. head .. "|r")
    LP.Debug("test", "%s", head)
    for _, o in ipairs(out) do
        local color = o[1] == "fail" and "|cffff5959FAIL|r" or "|cffffd100WARN|r"
        LP.Print(("%s %s - %s"):format(color, o[2], o[3]))
        LP.Debug("test", "%s %s - %s", o[1]:upper(), o[2], o[3])
    end
    if LP.OnTestsDone then LP.OnTestsDone(LP.lastTests) end
    if LP.LiveChecks then LP.LiveChecks() end
    return LP.lastTests
end

LP.TestCount = function() return #tests end
