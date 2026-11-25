-- Picky / Tests2.lua : more self tests (data, helpers, chat detection, channels, per-character data, upgrade migration).
-- Same rules as Tests.lua: nothing permanent changes, everything that is touched is restored afterwards.
local ADDON, LP = ...
local K = LP.TestKit
local T, eq, truthy, falsy = K.T, K.eq, K.truthy, K.falsy
local Sandbox = K.Sandbox

-- 1) Data -------------------------------------------------------------------------------------------------------------
-- The skill values were read from the item tooltips in WoW Forever (see Data.lua). Pinned here so nobody changes them by accident.
local PINNED = {
    [6712] = 1, [6354] = 1, [16882] = 1, [4632] = 1, [4633] = 25, [4634] = 70, [6355] = 70, [6356] = 1, [16883] = 70,
    [4636] = 125, [4637] = 175, [13875] = 175, [16884] = 175, [4638] = 225, [5758] = 225, [13918] = 250, [5759] = 225,
    [16885] = 250, [5760] = 225,
}
do
    local ids = {}
    for id in pairs(PINNED) do ids[#ids + 1] = id end
    table.sort(ids)
    for _, id in ipairs(ids) do
        T(("data: box %d needs lockpicking %d (checked in the game tooltip)"):format(id, PINNED[id]), function()
            local b = LP.BOXES[id]
            truthy(b, "box is in the table")
            eq(b[1], PINNED[id], "required skill")
        end)
    end
end
T("data: the box table has exactly the pinned boxes", function()
    local n = 0
    for id in pairs(LP.BOXES) do
        n = n + 1
        truthy(PINNED[id] ~= nil, "box " .. tostring(id) .. " is not in the pinned list (add it to Tests2.lua when you add a box)")
    end
    eq(n, 19, "number of boxes")
end)
T("data: every box has a plausible skill and an English name", function()
    for id, b in pairs(LP.BOXES) do
        eq(type(id), "number", "item id type")
        eq(type(b[1]), "number", "skill type of " .. id)
        truthy(b[1] >= 1 and b[1] <= 300, "skill of " .. id .. " is 1-300")
        eq(type(b[2]), "string", "name type of " .. id)
        truthy(#b[2] > 0, "name of " .. id .. " is not empty")
    end
end)
T("data: every box has a name (BoxName never returns '?')", function()
    for id in pairs(LP.BOXES) do
        local n = LP.BoxName(id)
        truthy(type(n) == "string" and n ~= "" and n ~= "?", "name of " .. id .. ": " .. tostring(n))
    end
end)
T("data: chat keywords are well formed", function()
    truthy(#LP.BOXKEYS > 0, "there are keywords")
    for i, k in ipairs(LP.BOXKEYS) do
        eq(type(k[1]), "string", "keyword " .. i)
        truthy(#k[1] > 0, "keyword " .. i .. " is not empty")
        eq(type(k[2]), "number", "skill of keyword " .. i)
        truthy(k[2] >= 1 and k[2] <= 300, "skill of keyword " .. k[1] .. " is 1-300")
        eq(type(k[3]), "string", "label of keyword " .. i)
        local ok = pcall(string.find, "test", k[1], 1, not k[4])
        truthy(ok, "keyword " .. k[1] .. " is a valid pattern/plain string")
    end
end)
T("data: keyword estimates are never below the cheapest box of that metal", function()
    -- bronze boxes need 1 and 25, iron 70 and 125, steel 175 and 225, mithril and thorium 225
    local est = {}
    for _, k in ipairs(LP.BOXKEYS) do est[k[1]] = k[2] end
    truthy(est["bronz"] >= 25, "bronze")
    truthy(est["%f[%a]iron%f[%A]"] >= 70, "iron")
    truthy(est["steel"] >= 175, "steel")
    truthy(est["mithril"] >= 225, "mithril")
    truthy(est["thorium"] >= 225, "thorium")
end)
T("data: the guide stages cover skill 1-300 without gaps", function()
    local g = LP.GUIDE
    eq(#g, 4, "number of stages")
    eq(g[1].from, 1, "starts at 1")
    eq(g[#g].to, 300, "ends at 300")
    for i, s in ipairs(g) do
        truthy(s.from < s.to, "stage " .. i .. " is not empty")
        if i > 1 then eq(s.from, g[i - 1].to, "stage " .. i .. " continues the previous one") end
        truthy(#s.spots > 0, "stage " .. i .. " names places")
        if i == 1 then truthy(#s.tips > 0, "stage 1 has tips") end
        for _, t in ipairs(s.tips or {}) do
            truthy(t[1] == "warn" or t[1] == "tip" or t[1] == "info", "tip kind of stage " .. i)
            truthy(type(t[2]) == "string" and t[2] ~= "", "tip text of stage " .. i)
        end
    end
end)
T("data: a guide stage's level requirement is its end skill / 5", function()
    for i, s in ipairs(LP.GUIDE) do eq(s.levelReq, s.to / 5, "level for stage " .. i) end
end)
T("data: every guide spot has a zone, text, boxes and sane coordinates", function()
    for i, s in ipairs(LP.GUIDE) do
        local best = 0
        for j, sp in ipairs(s.spots) do
            local w = "stage " .. i .. " spot " .. j
            truthy(type(sp.zone) == "number", w .. " zone")
            truthy(type(sp.where) == "string" and sp.where ~= "", w .. " name")
            truthy(type(sp.note) == "string" and sp.note ~= "", w .. " note")
            truthy(#sp.boxes > 0, w .. " boxes")
            truthy(sp.faction == nil or sp.faction == "A" or sp.faction == "H", w .. " faction")
            truthy((sp.x == nil) == (sp.y == nil), w .. " x and y go together")
            if sp.x then truthy(sp.x > 0 and sp.x < 100 and sp.y > 0 and sp.y < 100, w .. " coordinates are percent") end
            for _, b in ipairs(sp.boxes) do
                truthy(type(b.name) == "string" and b.name ~= "", w .. " box name")
                truthy(b.item or b.iconItem, w .. " box icon")
                truthy(b.skill == nil or b.skill <= s.to, w .. " box skill is within the stage")
            end
            if sp.best then best = best + 1 end
        end
        truthy(best >= 1, "stage " .. i .. " has a best spot")
    end
end)
T("data: both factions get a spot in every guide stage", function()
    for i, s in ipairs(LP.GUIDE) do
        for _, f in ipairs({ "A", "H" }) do
            local n = 0
            for _, sp in ipairs(s.spots) do if sp.faction == nil or sp.faction == f then n = n + 1 end end
            truthy(n >= 1, "stage " .. i .. " has a spot for " .. f)
        end
    end
end)
T("data: guide spots of stage 1 are split by faction", function()
    local a, h
    for _, sp in ipairs(LP.GUIDE[1].spots) do if sp.faction == "A" then a = sp elseif sp.faction == "H" then h = sp end end
    truthy(a and h, "one spot per faction")
    truthy(a.zone ~= h.zone, "different zones")
end)
T("skill reach: the lower of rank limit and level limit, never below the skill", function()
    eq(LP.SkillReach(300, 33, 100), 165, "level 33 holds a rank-300 skill back")
    eq(LP.SkillReach(150, 60, 100), 150, "the rank holds back a level-60 rogue")
    eq(LP.SkillReach(300, 60, 100), 300, "both open")
    eq(LP.SkillReach(nil, 20, 10), 100, "unknown rank")
    eq(LP.SkillReach(300, 10, 80), 80, "never below what you have")
    eq(LP.SkillReach(300, 100, 10), 300, "capped at 300")
end)
T("self tests: Picky's chat output is muted while they run", function()
    truthy(LP.selfTesting, "flag is set during a run")
end)
T("guide advice: only warns when the level holds the skill back", function()
    local k, text = LP.GuideAdvice(100, 20)
    eq(k, "warn", "skill 100 at level 20 is capped")
    truthy(text:find("21", 1, true), "tells the next level: 21")
    eq(LP.GuideAdvice(99, 20), nil, "below the cap")
    eq(LP.GuideAdvice(150, 29), "warn", "above the cap of level 29")
    eq(LP.GuideAdvice(144, 29), nil, "just below")
    eq(LP.GuideAdvice(300, 60), nil, "maxed")
    eq(LP.GuideAdvice(100, 0), nil, "unknown level")
end)
T("guide: map ids resolve to zone names (log for the dev: check the names in the log)", function()
    if not (C_Map and C_Map.GetMapInfo) then return end   -- only inside the real game
    local bad = {}
    for i, s in ipairs(LP.GUIDE) do
        for _, sp in ipairs(s.spots) do
            local n = LP.Game.MapName(sp.zone)
            LP.Debug("test", "guide %d: map %d = %s (%s)", i, sp.zone, tostring(n), sp.where)
            if not n then bad[#bad + 1] = sp.zone end
        end
    end
    if #bad > 0 then return "warn: unknown map ids: " .. table.concat(bad, ",") end
end)
T("data: guide stage by skill is in range and never goes down", function()
    local last = 1
    for sk = 0, 300 do
        local st = LP.StageForSkill(sk)
        truthy(st >= 1 and st <= #LP.GUIDE, "stage of " .. sk .. " is in range")
        truthy(st >= last, "stage of " .. sk .. " does not go back")
        last = st
    end
end)

-- 2) Helpers ----------------------------------------------------------------------------------------------------------
T("money: more amounts (a 20 silver tip, no copper, only copper, big amounts)", function()
    eq(LP.Money(nil), "0g", "nil")
    eq(LP.Money(99), "99k", "99")
    eq(LP.Money(101), "1s 1k", "101")
    eq(LP.Money(2000), "20s", "20 silver")
    eq(LP.Money(9999), "99s 99k", "9999")
    eq(LP.Money(10001), "1g 1k", "10001")
    eq(LP.Money(150000), "15g", "15 gold")
    eq(LP.Money(1000000), "100g", "100 gold")
end)
T("names: Short removes the realm part", function()
    eq(LP.Short("Anna-Realm"), "Anna", "with realm")
    eq(LP.Short("Anna"), "Anna", "plain")
    eq(LP.Short("Arkanos Spellix-Realm"), "Arkanos Spellix", "two part name")
    eq(LP.Short(nil), nil, "nil")
    eq(LP.Short(""), "", "empty")
end)
T("names: SameName rules", function()
    truthy(LP.SameName("Anna", "anna"), "case")
    truthy(LP.SameName("Anna-Realm", "Anna"), "realm suffix")
    truthy(LP.SameName("Arkanos Spellix", "Arkanos"), "two part against the short form")
    truthy(LP.SameName("Arkanos", "Arkanos Voidwalker"), "short form against a two part name")
    falsy(LP.SameName("Arkanos Spellix", "Arkanos Voidwalker"), "two different second parts")
    falsy(LP.SameName("Anna", "Anne"), "different names")
    falsy(LP.SameName(nil, "x"), "nil")
    falsy(LP.SameName("", ""), "empty")
end)
T("announcement: placeholders and plain text", function()
    local sk = tostring(LP.Skill())
    eq(LP.ExpandAd("{skill}"), sk, "one placeholder")
    eq(LP.ExpandAd("{skill}-{skill}"), sk .. "-" .. sk, "two placeholders")
    eq(LP.ExpandAd("Hello there"), "Hello there", "no placeholder")
end)
T("channels: key is the name without the zone part, lowercase", function()
    eq(LP.ChannelKey("Trade - City"), "trade", "Trade - City")
    eq(LP.ChannelKey("Handel - Deutsch 33"), "handel", "Handel - Deutsch 33")
    eq(LP.ChannelKey("General - Stormwind City"), "general", "General")
    eq(LP.ChannelKey("TradeLocal"), "tradelocal", "TradeLocal")
    eq(LP.ChannelKey("Services"), "services", "Services")
    eq(LP.ChannelKey("Trade-City"), "trade", "no spaces")
end)

-- 3) Chat detection (public chat unless marked as whisper) ---------------------------------------------------------------
-- { text, whisper, is a request }
local CHAT2 = {
    -- requests (English)
    { "LF rogue open my lockbox", false, true },
    { "LF rogue to unlock chest", false, true },
    { "rogue pls unlock this chest", false, true },
    { "any rogue around to open a lockbox?", false, true },
    { "rogue needed to open junkbox", false, true },
    { "wtb rogue for lockbox", false, true },
    { "need rogue for ironforge lockbox", false, true },
    -- requests (German)
    { "Suche Schurke fuer Kiste", false, true },
    { "Brauche Schurke fuer meine Truhe", false, true },
    { "Wer kann Kisten aufmachen? Schurke gesucht", false, true },
    { "kann ein Schurke bitte diese Eisenkiste oeffnen", false, true },
    { "LF Schurke Bronzekiste", false, true },
    { "Hilfe! Schurke gesucht fuer Plunderkiste", false, true },
    -- not requests
    { "WTS lockbox 5g", false, false },
    { "LFM rogue for BRD", false, false },
    { "rogue lf dps group", false, false },
    { "Looking for rogue guild", false, false },
    { "free hugs", false, false },
    { "box of chocolates for sale", false, false },
    { "can anyone craft a bronze chest", false, false },
    { "anyone want a locked chest quest", false, false },
    { "where is the locked chest in deadmines", false, false },
    { "how do i pick a lock", false, false },
    { "Verkaufe Eisenkiste", false, false },
    { "wo finde ich Truhen", false, false },
    { "Suche Gildenmitglieder fuer Kiste in Org", false, false },
    { "LF rogue in ironforge", false, false },
    -- advertisements of other rogues
    { "Rogue 225 lockpicking, tips appreciated", false, false },
    { "Rogue offering lockpicking", false, false },
    { "Rogue lockpicking free", false, false },
    { "Schurke bietet Schlossknacken an", false, false },
    { "Schurke 300 Schlossknacken, Trinkgeld erwuenscht", false, false },
    { "Rogue here for lockboxes", false, false },
    { "Rogue in Orgrimmar opening boxes", false, false },
    { "Rogue available, lockboxes, /w me", false, false },
    { "rogue lockpicking 300 whisper for chests", false, false },
    -- "LFW" = looking for work: a rogue offering himself (reported on CurseForge: "Rogue LFW Locking!" got invited)
    { "Rogue LFW Locking!", false, false },
    { "Rogue LFW lockpicking", false, false },
    { "LFW rogue lockpicking 300", false, false },
    { "rogue looking for work, lockboxes", false, false },
    { "Rogue for hire: lockpicking", false, false },
    { "Rogue LFW lockboxes, whisper me", true, true },
    -- "for free" / "umsonst": the word "free" marks an offer
    { "Rogue lockpicking for free", false, false },
    { "Opening lockboxes for free, rogue here", false, false },
    { "Rogue opens lockboxes 4 free", false, false },
    { "Schurke öffnet Kisten umsonst", false, false },
    { "Schurke knackt Kisten gratis", false, false },
    { "LF rogue to open my lockbox, I will tip", false, true },
    -- each of these has exactly ONE signal, so every word and rule has to carry its own test
    { "Schurke Schlossknacken umsonst", false, false },       -- only "umsonst"
    { "Rogue lockboxes tips welcome", false, false },         -- only "tips welcome"
    { "Rogue lockboxes pm me", false, false },                -- only "pm me"
    { "WTS rogue lockbox", false, false },                    -- only the sale word
    { "where is a rogue for my chest", false, false },        -- only "where"
    -- customers who use an offer word: the word only marks an ad when nobody is being asked
    { "Kann mir jemand umsonst meine Kisten öffnen?", false, true },
    { "wer kann mir kostenlos eine Kiste aufmachen?", false, true },
    { "can someone open my lockbox for free pls", false, true },
    { "any rogue available to open a lockbox?", false, true },
    { "need a rogue to hire for my chests pls", false, true },
    { "anyone offering lockpicking? I need a chest opened", false, false },   -- 'offering' stays an unconditional ad word   -- whispers are a direct message: still a request
    -- whispers (a box or an open request is enough)
    { "can you open my box", true, true },
    { "Hi, do you open lockboxes?", true, true },
    { "open pls", true, true },
    { "LF rogue 150 lockpicking", true, true },
    { "hello", true, false },
    { "thanks!", true, false },
    { "lol", true, false },
}
for i, c in ipairs(CHAT2) do
    T(("chat detection 2 #%d: %s%s"):format(i, c[2] and "[whisper] " or "", c[1]:sub(1, 50)), function()
        local ok = LP.Analyze(c[1], c[2])
        eq(ok and true or false, c[3], "recognized as a request")
    end)
end

-- Required skill that is read from a message: { text, whisper, expected skill (nil = none) }
local LINK_IRON = "|cff1eff00|Hitem:4634::::::::41:1482:::::::::|h[Iron Lockbox]|h|r"
local LINK_STEEL = "|cff1eff00|Hitem:4637::::::::41:1482:::::::::|h[Steel Lockbox]|h|r"
local LINK_HBRONZE = "|cff1eff00|Hitem:4633::::::::41:1482:::::::::|h[Heavy Bronze Lockbox]|h|r"
local LINK_BATTERED = "|cff1eff00|Hitem:6356::::::::41:1482:::::::::|h[Battered Chest]|h|r"
local LINK_CLOTH = "|cffffffff|Hitem:2589::::::::41:1482:::::::::|h[Linen Cloth]|h|r"
local REQ2 = {
    { "LF rogue lockpicking 19", false, nil },        -- below 20: an amount, not a skill
    { "LF rogue lockpicking 20", false, 20 },
    { "LF rogue lockpicking 300", false, 300 },
    { "LF rogue lockpicking 301", false, nil },       -- above 300: not a skill
    { "need rogue 150 lockpicking", false, 150 },
    { "need rogue skill 225+ lockbox", false, 225 },
    { "need rogue lockbox skill 200+", false, 200 },
    { "Suche Schurke Schlossknacken 150", false, 150 },
    { "LF rogue iron lockbox lockpick 70", false, 125 },          -- a lower number never wins over the keyword
    { "LF rogue steel lockbox lockpicking 100", false, 225 },
    { "LF rogue bronze lockbox lockpicking 150", false, 150 },    -- a higher number wins
    { "LF rogue bronze and mithril lockbox", false, 225 },        -- several keywords: the highest
    { "LF rogue iron or steel lockbox", false, 225 },
    { "need rogue for thorium lockbox", false, 225 },
    { "LF rogue footlocker", false, 70 },
    { "brauche Schurke fuer Stahlkiste", false, 225 },
    { "LF rogue " .. LINK_IRON, false, 70 },                      -- item link = exact value
    { "LF rogue " .. LINK_STEEL .. " " .. LINK_HBRONZE, false, 175 },   -- several links: the highest
    { "LF rogue " .. LINK_BATTERED, false, 1 },
    { "LF rogue 150 lockpicking, skill 225", false, 225 },       -- two explicit numbers: the higher one
    { "LF rogue skill 225 and 150 lockpicking", false, 225 },
    { "LF rogue " .. LINK_HBRONZE .. " " .. LINK_STEEL, false, 175 },   -- links in the other order: still the highest, not the first
    { "LF rogue " .. LINK_HBRONZE .. " thorium", false, 25 },     -- the link wins over the word
    { "LF rogue " .. LINK_CLOTH, false, nil },                    -- a link to something that is not a box
    { "can you open " .. LINK_IRON, true, 70 },                   -- whispers read links too
}
for i, c in ipairs(REQ2) do
    T(("required skill #%d: %s"):format(i, (c[1]:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|H.-|h", ""):gsub("|h", ""):gsub("|r", "")):sub(1, 60)), function()
        local _, req = LP.Analyze(c[1], c[2])
        eq(req, c[3], "required skill")
    end)
end
T("chat detection: a link to something that is not a box is no request", function()
    local ok = LP.Analyze("LF rogue " .. LINK_CLOTH, false)
    falsy(ok, "linen cloth")
end)
T("chat detection: a Pick Lock spell link marks an advertisement even without other words", function()
    local ok = LP.Analyze("Rogue |cff71d5ff|Hspell:1804|h[Pick Lock]|h|r lockboxes", false)
    falsy(ok, "spell link in public chat")
end)

-- 4) Channels ---------------------------------------------------------------------------------------------------------
T("channels: an own choice replaces the default rule", function()
    local ad = LP.db.ad
    local was = ad.channels
    ad.channels = { trade = true }
    local function on(name) return LP.AdChannelOn({ name = name, key = LP.ChannelKey(name) }) end
    truthy(on("Trade - City"), "trade ticked")
    falsy(on("TradeLocal"), "tradelocal not ticked")
    falsy(on("Services"), "services not ticked")
    ad.channels = { tradelocal = true }
    truthy(on("TradeLocal"), "an own choice may tick the local channel")
    falsy(on("Trade"), "trade not ticked any more")
    ad.channels = was
end)
T("channels: the first own choice starts from the old filter and can be undone", function()
    local ad = LP.db.ad
    local saved = { ch = ad.channels, seeded = ad.channelsSeeded, match = ad.channelMatch }
    ad.channels, ad.channelsSeeded, ad.channelMatch = nil, nil, "handel,trade"
    LP.SetAdChannel("services", true)
    truthy(type(ad.channels) == "table", "table created")
    eq(ad.channels.services, true, "services ticked")
    eq(ad.channels.trade, true, "trade kept from the old filter")
    eq(ad.channels.handel, true, "handel kept from the old filter")
    LP.SetAdChannel("services", false)
    eq(ad.channels.services, nil, "services unticked")
    ad.channels, ad.channelsSeeded, ad.channelMatch = saved.ch, saved.seeded, saved.match
end)
T("channels: reading switches are stored as exceptions only", function()
    local f = LP.db.finder
    local was = f.readOff
    f.readOff = nil
    LP.SetReadChannel("x", false)
    eq(f.readOff.x, true, "off is stored")
    LP.SetReadChannel("x", true)
    eq(f.readOff.x, nil, "on removes the entry")
    truthy(LP.ReadChannelOn("never-seen"), "a channel that was never touched is read")
    f.readOff = was
end)
T("channels: chat source keys", function()
    eq(LP.ChatSourceKey("CHAT_MSG_CHANNEL", "5. TradeLocal", nil), "tradelocal", "from the channel string")
    eq(LP.ChatSourceKey("CHAT_MSG_CHANNEL", "1. General - Stormwind City", "General"), "general", "base name wins")
    eq(LP.ChatSourceKey("CHAT_MSG_CHANNEL", "2. Trade - German 33", ""), "trade", "empty base name falls back")
    eq(LP.ChatSourceKey("CHAT_MSG_CHANNEL", nil, nil), nil, "no name at all")
    eq(LP.ChatSourceKey("CHAT_MSG_SAY"), "say", "say")
    eq(LP.ChatSourceKey("CHAT_MSG_YELL"), "yell", "yell")
    eq(LP.ChatSourceKey("CHAT_MSG_OFFICER"), nil, "an event Picky does not read (officer chat)")
    eq(LP.ChatSourceKey("CHAT_MSG_GUILD"), "guild", "guild chat")
end)
T("channels: nothing is filtered when nothing is switched off", function()
    local f = LP.db.finder
    local was = f.readOff
    f.readOff = nil
    truthy(LP.ChatAllowed("CHAT_MSG_CHANNEL", "2. Trade - City"), "trade")
    truthy(LP.ChatAllowed("CHAT_MSG_CHANNEL", "1. General - City"), "general")
    truthy(LP.ChatAllowed("CHAT_MSG_SAY"), "say")
    truthy(LP.ChatAllowed("CHAT_MSG_YELL"), "yell")
    truthy(LP.ChatAllowed("CHAT_MSG_WHISPER"), "whisper")
    truthy(LP.ChatAllowed("CHAT_MSG_GUILD"), "guild")
    truthy(LP.ChatAllowed("CHAT_MSG_OFFICER"), "an unknown source is never filtered")
    f.readOff = was
end)

-- 5) Data lives in PickyDB for the whole account (1.0.17 stored it per character; that was taken back and is merged on load) ---------------
local function WithData(setup, fn)   -- prepare the account data, run, restore everything
    local db = LP.db
    local keep = { stats = db.stats, orders = db.orders, base = db.skillBase, chars = db.chars, claimed = db.legacyClaimed, declined = db.legacyDeclined, reqs = LP.requests }
    local ok, err = pcall(function()
        db.stats, db.orders, db.skillBase, db.chars, db.legacyClaimed, db.legacyDeclined = nil, nil, nil, nil, nil, nil
        setup(db)
        LP.MergeChars()
        fn(db)
    end)
    db.stats, db.orders, db.skillBase, db.chars, db.legacyClaimed, db.legacyDeclined = keep.stats, keep.orders, keep.base, keep.chars, keep.claimed, keep.declined
    LP.requests = keep.reqs
    if not ok then error(err, 0) end
end
T("merge back from 1.0.17: the data of all characters is added up on the account, nothing is lost", function()
    WithData(function(db)
        db.stats = { picked = 1, tips = 10, invited = 0, thanked = 0 }
        db.orders = {}
        db.chars = {
            ["Asda-6939"] = { stats = { picked = 3, tips = 5000, invited = 2, thanked = 1 }, orders = { { name = "A", stamp = 100 } }, skillBase = 90 },
            ["Velina-6939"] = { stats = { picked = 59, tips = 5065, invited = 1, thanked = 4 }, orders = { { name = "B", stamp = 300 }, { name = "C", stamp = 200 } }, skillBase = 156 },
        }
    end, function(db)
        eq(db.stats.picked, 63, "picked is summed (1 + 3 + 59)")
        eq(db.stats.tips, 10075, "tips are summed")
        eq(db.stats.invited, 3, "invited")
        eq(db.stats.thanked, 5, "thanked")
        eq(#db.orders, 3, "all orders")
        eq(db.orders[1].name, "B", "newest first")
        eq(db.orders[2].name, "C", "then")
        eq(db.orders[3].name, "A", "oldest last")
        eq(db.skillBase, 156, "the highest stored skill")
        eq(db.chars, nil, "the per-character table is gone")
    end)
end)
T("merge back: running it again changes nothing", function()
    WithData(function(db)
        db.stats = { picked = 0, tips = 0, invited = 0, thanked = 0 }
        db.orders = {}
        db.chars = { ["X-1"] = { stats = { picked = 4, tips = 7, invited = 0, thanked = 0 }, orders = { { name = "Once", stamp = 5 } } } }
    end, function(db)
        LP.MergeChars()
        LP.MergeChars()
        eq(db.stats.picked, 4, "picked is not doubled")
        eq(db.stats.tips, 7, "tips are not doubled")
        eq(#db.orders, 1, "orders are not doubled")
    end)
end)
T("merge back: orders with the same time keep their order, orders without a time go last", function()
    WithData(function(db)
        db.stats = { picked = 0, tips = 0, invited = 0, thanked = 0 }
        db.orders = {}
        db.chars = {
            ["A-1"] = { orders = { { name = "a1", stamp = 50 }, { name = "a2", stamp = 50 }, { name = "none" } } },
            ["B-1"] = { orders = { { name = "b1", stamp = 50 }, { name = "newer", stamp = 90 } } },
        }
    end, function(db)
        eq(#db.orders, 5, "all orders")
        eq(db.orders[1].name, "newer", "newest first")
        eq(db.orders[2].name, "a1", "same time: first character first")
        eq(db.orders[3].name, "a2", "same time: order kept")
        eq(db.orders[4].name, "b1", "same time: second character after the first")
        eq(db.orders[5].name, "none", "no time: last")
    end)
end)
T("merge back: damaged entries are skipped, the rest is kept", function()
    WithData(function(db)
        db.stats = { picked = 2, tips = 0, invited = 0, thanked = 0 }
        db.orders = {}
        db.chars = {
            ["Bad-1"] = "not a table",
            ["Half-1"] = { stats = { picked = "5", tips = "x" }, orders = { "junk", { name = "ok", stamp = 1 } } },
            ["Empty-1"] = {},
        }
    end, function(db)
        eq(db.stats.picked, 7, "a number written as text still counts (2 + 5)")
        eq(db.stats.tips, 0, "text that is no number counts as 0")
        eq(#db.orders, 1, "only the real order is kept")
        eq(db.orders[1].name, "ok", "the order")
    end)
end)
T("merge back: without per-character data nothing changes (accounts that never had 1.0.17)", function()
    WithData(function(db)
        db.stats = { picked = 8, tips = 123, invited = 1, thanked = 1 }
        db.orders = { { name = "Mine", stamp = 7 } }
        db.skillBase = 120
    end, function(db)
        eq(db.stats.picked, 8, "picked")
        eq(db.stats.tips, 123, "tips")
        eq(#db.orders, 1, "orders")
        eq(db.skillBase, 120, "skill")
        eq(db.chars, nil, "no per-character table is created")
    end)
end)
T("merge back: old claim markers are removed", function()
    WithData(function(db)
        db.stats = { picked = 0, tips = 0, invited = 0, thanked = 0 }
        db.orders = {}
        db.legacyClaimed, db.legacyDeclined = "Asda-6939", { ["X-1"] = true }
    end, function(db)
        eq(db.legacyClaimed, nil, "legacyClaimed")
        eq(db.legacyDeclined, nil, "legacyDeclined")
    end)
end)
T("data: statistics and orders are part of the defaults (new installs)", function()
    truthy(type(LP.defaults.stats) == "table", "stats default")
    eq(LP.defaults.stats.picked, 0, "picked starts at 0")
    eq(LP.defaults.stats.tips, 0, "tips start at 0")
    truthy(type(LP.defaults.orders) == "table", "orders default")
    eq(LP.defaults.chars, nil, "there is no per-character default any more")
end)
T("skill: the stored skill belongs to the account and is not used on a character without Pick Lock", function()
    local db = LP.db
    local keep = { known = LP.PickLockKnown, rogue = LP.IsRogue, list = LP.ReadSkillList, base = db.skillBase, ts = LP.Game.TradeSkillInfo }
    local ok, err = pcall(function()
        LP.Game.TradeSkillInfo = function() return nil end
        LP.IsRogue = function() return true end
        LP.ReadSkillList = function() return nil end
        db.skillBase = 160   -- stored by another character (the main)
        LP.PickLockKnown = function() return false end
        LP.RefreshSkill()
        eq(LP.skillBase, 0, "an alt without Pick Lock does not inherit the 160")
        truthy(LP.skillNotLearned, "not learned")
        LP.PickLockKnown = function() return true end
        LP.RefreshSkill()
        eq(LP.skillBase, 160, "with Pick Lock known the stored value is used as a fallback")
        LP.PickLockKnown = function() return nil end
        LP.RefreshSkill()
        eq(LP.skillBase, 160, "when the client cannot tell, the stored value is used too")
    end)
    LP.PickLockKnown, LP.IsRogue, LP.ReadSkillList, db.skillBase, LP.Game.TradeSkillInfo = keep.known, keep.rogue, keep.list, keep.base, keep.ts
    LP.RefreshSkill()
    if not ok then error(err, 0) end
end)
T("non-rogue classes: nothing is stored for them and the statistics stay shared", function()
    truthy(LP.db.stats ~= nil, "account statistics exist")
    eq(LP.db.chars, nil, "no per-character table")
end)
T("settings: default wait before leaving is 5 seconds", function()
    eq(LP.defaults.finder.leaveDelay, 5, "default")
end)
T("non-rogue sayings: all exist in English and German, same placeholders, none empty", function()
    local function count(t) local _, n = t:gsub("%%s", "") return n end
    local DEtext = LP.isGerman
    for i = 1, LP.NONROGUE_QUOTES do
        local key = "nonrogue." .. i
        local en, de = LP.Both(key)
        truthy(type(en) == "string" and en ~= "" and en ~= key, key .. " has an English text")
        truthy(type(de) == "string" and de ~= "" and de ~= key, key .. " has a German text")
        eq(count(en), count(de), key .. " same number of %s in English and German")
        truthy(count(en) <= 1, key .. " uses at most one %s")
    end
end)
T("non-rogue sayings: every saying can be shown (with the class name) and the pick stays the same in a session", function()
    local was = LP.quoteIndex
    for i = 1, LP.NONROGUE_QUOTES do
        LP.quoteIndex = i
        local q = LP.NonRogueQuote()
        truthy(type(q) == "string" and #q > 0, "saying " .. i .. " is a string")
        falsy(q:find("%%s"), "saying " .. i .. " has no raw %s left")
    end
    LP.quoteIndex = nil
    local first = LP.NonRogueQuote()
    eq(LP.NonRogueQuote(), first, "second call gives the same saying")
    truthy(LP.quoteIndex >= 1 and LP.quoteIndex <= LP.NONROGUE_QUOTES, "picked index is in range")
    LP.quoteIndex = was
end)
T("skill: a rogue without Pick Lock has skill 0 (not learned), not a guess from the level", function()
    local keep = { known = LP.PickLockKnown, rogue = LP.IsRogue, list = LP.ReadSkillList, base = LP.db.skillBase, ts = LP.Game.TradeSkillInfo }
    local ok, err = pcall(function()
        LP.Game.TradeSkillInfo = function() return nil end   -- the second source of the skill must not answer for the real character
        LP.IsRogue = function() return true end
        LP.ReadSkillList = function() return nil end     -- no Lockpicking line in the skill list
        LP.db.skillBase = nil   -- nothing stored
        LP.PickLockKnown = function() return false end
        LP.RefreshSkill()
        eq(LP.Skill(), LP.skillBonus or 0, "skill is only the gear bonus")
        eq(LP.skillBase, 0, "base 0")
        truthy(LP.skillNotLearned, "marked as not learned")
        falsy(LP.skillEstimated, "not an estimate")
        -- the game cannot tell: keep the old behaviour (estimate from the level)
        LP.PickLockKnown = function() return nil end
        LP.RefreshSkill()
        truthy(LP.skillEstimated, "estimated when the client cannot answer")
        falsy(LP.skillNotLearned, "not marked as not learned")
        -- the spell is known but the list gave nothing: estimate as before
        LP.PickLockKnown = function() return true end
        LP.RefreshSkill()
        truthy(LP.skillEstimated, "estimated when the spell is known")
        -- a skill from the list always wins
        LP.ReadSkillList = function() return 42, 300, 0, "test list" end
        LP.RefreshSkill()
        eq(LP.skillBase, 42, "skill from the list")
        falsy(LP.skillEstimated, "not estimated")
        falsy(LP.skillNotLearned, "learned")
    end)
    LP.PickLockKnown, LP.IsRogue, LP.ReadSkillList, LP.db.skillBase, LP.Game.TradeSkillInfo = keep.known, keep.rogue, keep.list, keep.base, keep.ts
    LP.RefreshSkill()
    if not ok then error(err, 0) end
end)
T("skill: a character that is not a rogue is never marked as not learned", function()
    local keep = { rogue = LP.IsRogue, list = LP.ReadSkillList, known = LP.PickLockKnown, ts = LP.Game.TradeSkillInfo, base = LP.db.skillBase }
    local ok, err = pcall(function()
        LP.Game.TradeSkillInfo = function() return nil end
        LP.db.skillBase = nil
        LP.IsRogue = function() return false end
        LP.ReadSkillList = function() return nil end
        LP.PickLockKnown = function() return false end
        LP.RefreshSkill()
        eq(LP.skillBase, 0, "base 0")
        falsy(LP.skillNotLearned, "no 'not learned' flag for other classes")
    end)
    LP.IsRogue, LP.ReadSkillList, LP.PickLockKnown, LP.Game.TradeSkillInfo, LP.db.skillBase = keep.rogue, keep.list, keep.known, keep.ts, keep.base
    LP.RefreshSkill()
    if not ok then error(err, 0) end
end)

-- 6) A request split into two messages ("LF rogue for" + the item link a few seconds later) --------------------------------
local LINK_STRONG_DE = "|cff1eff00|Hitem:4636::::::::41:1482:::::::::|h[Starke Eisenschließkassette]|h|r"
T("chat detection: a lone item link of a box is a box (also with the German name)", function()
    local ok1, req1 = LP.Analyze(LINK_STRONG_DE, false)
    falsy(ok1, "alone in public chat it is no request")
    local _, _, _, why = LP.Analyze(LINK_STRONG_DE, false)
    truthy(why.lock, "the link counts as a box")
    local _, req = LP.Analyze(LINK_STRONG_DE, false)
    eq(req, 125, "required skill from the link")
    local _, _, _, why2 = LP.Analyze("[Starke Eisenschließkassette]", false)
    truthy(why2.lock, "the German box name alone counts as a box (word 'schließkass')")
    local _, _, _, why3 = LP.Analyze("Lf Rogue for", false)
    truthy(why3.rogue and why3.seek, "'Lf Rogue for' asks for a rogue")
    falsy(why3.lock, "and names no box")
end)
T("chat detection: 'LF rogue for' + the box link a few seconds later becomes one request", function()
    local was = LP.recentMsgs
    LP.recentMsgs = {}
    Sandbox(nil, function()
        LP.OnChat("CHAT_MSG_CHANNEL", "Lf Rogue for", "Splitter", true)
        falsy(LP.FindRequest("Splitter"), "no request yet")
        LP.OnChat("CHAT_MSG_CHANNEL", LINK_STRONG_DE, "Splitter", true)
        local r = LP.FindRequest("Splitter")
        truthy(r, "request after the second message")
        eq(r.req, 125, "required skill from the link")
    end)
    LP.recentMsgs = was
end)
T("chat detection: a box link from someone who did not ask for a rogue is no request", function()
    local was = LP.recentMsgs
    LP.recentMsgs = {}
    Sandbox(nil, function()
        LP.OnChat("CHAT_MSG_CHANNEL", LINK_STRONG_DE, "Seller", true)
        falsy(LP.FindRequest("Seller"), "a lone link is no request")
        LP.OnChat("CHAT_MSG_CHANNEL", "Lf Rogue for", "Asker", true)
        LP.OnChat("CHAT_MSG_CHANNEL", LINK_STRONG_DE, "SomeoneElse", true)
        falsy(LP.FindRequest("SomeoneElse"), "another player's link does not use the asker's message")
    end)
    LP.recentMsgs = was
end)
T("chat detection: an advertisement before a box link does not open the follow-up", function()
    local was = LP.recentMsgs
    LP.recentMsgs = {}
    Sandbox(nil, function()
        LP.OnChat("CHAT_MSG_CHANNEL", "Rogue offering lockbox opening", "Adder", true)
        LP.OnChat("CHAT_MSG_CHANNEL", LINK_STRONG_DE, "Adder", true)
        falsy(LP.FindRequest("Adder"), "no request from an advertiser")
    end)
    LP.recentMsgs = was
end)

T("split messages: the earlier part only counts for 5 seconds", function()
    local was = LP.recentMsgs
    LP.recentMsgs = {}
    Sandbox(nil, function()
        LP.recentMsgs["late"] = { { text = "Lf Rogue for", t = GetTime() - 6 } }
        LP.OnChat("CHAT_MSG_CHANNEL", LINK_STRONG_DE, "Late", true)
        falsy(LP.FindRequest("Late"), "too late (6 s)")
        LP.recentMsgs["intime"] = { { text = "Lf Rogue for", t = GetTime() - 3 } }
        LP.OnChat("CHAT_MSG_CHANNEL", LINK_STRONG_DE, "InTime", true)
        truthy(LP.FindRequest("InTime"), "in time (3 s)")
    end)
    LP.recentMsgs = was
end)
T("split messages: the parts are used up by the request", function()
    local was = LP.recentMsgs
    LP.recentMsgs = {}
    Sandbox(nil, function()
        LP.OnChat("CHAT_MSG_CHANNEL", "Lf Rogue for", "Once", true)
        LP.OnChat("CHAT_MSG_CHANNEL", LINK_STRONG_DE, "Once", true)
        truthy(LP.recentMsgs["once"] == nil, "nothing is left over after the request")
    end)
    LP.recentMsgs = was
end)
T("split messages: three parts in any order become one request", function()
    local was = LP.recentMsgs
    LP.recentMsgs = {}
    Sandbox(nil, function()
        local function Say(who, ...) for _, m in ipairs({ ... }) do LP.OnChat("CHAT_MSG_CHANNEL", m, who, true) end end
        Say("Drei1", "LF rogue", "for", LINK_STRONG_DE)
        truthy(LP.FindRequest("Drei1"), "'LF rogue', 'for', link")
        Say("Drei2", LINK_STRONG_DE, "LF rogue")
        truthy(LP.FindRequest("Drei2"), "the link first, then 'LF rogue'")
        Say("Drei3", "LF", "rogue", LINK_STRONG_DE)
        truthy(LP.FindRequest("Drei3"), "'LF', 'rogue', link: every word on its own line")
        Say("Drei4", "need", "a rogue", "to open", "my lockbox")
        truthy(LP.FindRequest("Drei4"), "four short parts")
        Say("Drei6", "LF", "chest", "open it")
        truthy(LP.FindRequest("Drei6"), "three parts that only work TOGETHER: 'LF' + 'chest' + 'open it'")
        Say("Drei5", "Kann", "ein Schurke", "meine Kiste", "aufmachen?")
        truthy(LP.FindRequest("Drei5"), "four German parts")
        eq(LP.FindRequest("Drei1").req, 125, "the skill comes from the link in the third part")
    end)
    LP.recentMsgs = was
end)
T("split messages: unrelated or vetoed parts do not become a request", function()
    local was = LP.recentMsgs
    LP.recentMsgs = {}
    Sandbox(nil, function()
        local function Say(who, ...) for _, m in ipairs({ ... }) do LP.OnChat("CHAT_MSG_CHANNEL", m, who, true) end end
        Say("Veto1", "LF rogue", "WTS", LINK_STRONG_DE)
        falsy(LP.FindRequest("Veto1"), "a sale word between the parts vetoes the combination")
        Say("Veto2", "Rogue offering", LINK_STRONG_DE)
        falsy(LP.FindRequest("Veto2"), "an offer word vetoes it")
        Say("Veto3", "hello everyone", "how are you", "nice weather")
        falsy(LP.FindRequest("Veto3"), "chatter is no request")
        Say("Veto4", "can someone help me", "with this", LINK_STRONG_DE)
        falsy(LP.FindRequest("Veto4"), "a general question and a link is no request")
        Say("Veto5", "LF", "rogue", "lf dps", "for brd")
        falsy(LP.FindRequest("Veto5"), "a group search")
    end)
    LP.recentMsgs = was
end)
T("split messages: only a few parts are kept per player and chatter is not stored", function()
    local was = LP.recentMsgs
    LP.recentMsgs = {}
    Sandbox(nil, function()
        for i = 1, 8 do LP.OnChat("CHAT_MSG_CHANNEL", "LF rogue", "Spammer", true) end
        local list = LP.recentMsgs["spammer"]
        truthy(list == nil or #list <= 4, "at most 4 parts are kept (or the repeated question already became a request)")
        LP.OnChat("CHAT_MSG_CHANNEL", "good morning everyone", "Plauderer", true)
        eq(LP.recentMsgs["plauderer"], nil, "a message without any signal is not stored")
    end)
    LP.recentMsgs = was
end)
T("split messages: old parts of players who stopped writing are forgotten", function()
    local was = LP.recentMsgs
    LP.recentMsgs = { alt = { { text = "LF rogue", t = GetTime() - 30 } } }
    Sandbox(nil, function()
        LP.OnChat("CHAT_MSG_CHANNEL", "LF rogue", "Neu", true)
        eq(LP.recentMsgs["alt"], nil, "the old entry is removed")
        truthy(LP.recentMsgs["neu"] ~= nil, "the new one is kept")
    end)
    LP.recentMsgs = was
end)

-- 7) Real chat: switched-off channels and advertisements (moved here from Tests.lua) --------------------------------------------------------
T("real chat: a switched-off channel is ignored (names as the game sends them), whispers never", function()
    local f = LP.db.finder
    local was = f.readOff
    f.readOff = nil
    local TRADE, GENERAL, SERVICES = "2. Trade - German 33", "1. General - Stormwind City", "4. Services"
    truthy(LP.ChatAllowed("CHAT_MSG_CHANNEL", TRADE), "trade on by default")
    LP.SetReadChannel("trade", false)
    falsy(LP.ChatAllowed("CHAT_MSG_CHANNEL", TRADE), "trade switched off (channel string)")
    falsy(LP.ChatAllowed("CHAT_MSG_CHANNEL", TRADE, "Trade"), "trade switched off (base name)")
    truthy(LP.ChatAllowed("CHAT_MSG_CHANNEL", GENERAL), "general still on")
    truthy(LP.ChatAllowed("CHAT_MSG_CHANNEL", SERVICES), "services still on")
    truthy(LP.ChatAllowed("CHAT_MSG_WHISPER"), "whispers are always read")
    LP.SetReadChannel("general", false)
    LP.SetReadChannel("say", false)
    LP.SetReadChannel("yell", false)
    falsy(LP.ChatAllowed("CHAT_MSG_CHANNEL", GENERAL), "general switched off")
    falsy(LP.ChatAllowed("CHAT_MSG_SAY"), "say switched off")
    falsy(LP.ChatAllowed("CHAT_MSG_YELL"), "yell switched off")
    truthy(LP.ChatAllowed("CHAT_MSG_WHISPER"), "whispers still read with everything off")
    f.readOff = was
end)
T("real chat: an advertisement of another rogue creates no request and is logged", function()
    local db = LP.db
    local wasDebug, n = db.debug, #LP.requests
    db.debug = true   -- the log is only written in test mode
    local ok, err = pcall(function()
        local before = #LP.debugLog
        LP.lastDebugKey = nil
        LP.OnChat("CHAT_MSG_CHANNEL", "Rogue 300 lockpicking, PM me for lockboxes", "Adrogue-Realm", true)
        eq(#LP.requests, n, "no request created")
        local found = false
        for i = before + 1, #LP.debugLog do
            if tostring(LP.debugLog[i]):find("ignored as an advertisement of another rogue", 1, true) then found = true end
        end
        truthy(found, "the ignored advertisement is in the log")
    end)
    db.debug = wasDebug
    if not ok then error(err, 0) end
end)

-- 8) Guild chat can be read (listed in the "Listen in" menu, on by default like every other source) ---------------------------------------------
T("guild chat: it is a source with its own key and is read by default", function()
    eq(LP.ChatSourceKey("CHAT_MSG_GUILD"), "guild", "key")
    local f = LP.db.finder
    local was = f.readOff
    f.readOff = nil
    truthy(LP.ReadChannelOn("guild"), "on by default")
    truthy(LP.ChatAllowed("CHAT_MSG_GUILD"), "allowed by default")
    f.readOff = was
end)
T("guild chat: it can be switched off and on without touching the other sources", function()
    local f = LP.db.finder
    local was = f.readOff
    f.readOff = nil
    LP.SetReadChannel("guild", false)
    falsy(LP.ChatAllowed("CHAT_MSG_GUILD"), "guild switched off")
    truthy(LP.ChatAllowed("CHAT_MSG_SAY"), "say still on")
    truthy(LP.ChatAllowed("CHAT_MSG_YELL"), "yell still on")
    truthy(LP.ChatAllowed("CHAT_MSG_CHANNEL", "2. Trade - City"), "channels still on")
    truthy(LP.ChatAllowed("CHAT_MSG_WHISPER"), "whispers still on")
    LP.SetReadChannel("guild", true)
    truthy(LP.ChatAllowed("CHAT_MSG_GUILD"), "guild on again")
    eq(f.readOff.guild, nil, "no leftover entry")
    f.readOff = was
end)
T("guild chat: a request from a guild member becomes a request, an advertisement does not", function()
    local was = LP.recentMsgs
    LP.recentMsgs = {}
    Sandbox(nil, function()
        LP.OnChat("CHAT_MSG_GUILD", "LF rogue to open my lockbox", "Gildenfreund", true)
        truthy(LP.FindRequest("Gildenfreund"), "request from the guild")
        LP.OnChat("CHAT_MSG_GUILD", "Rogue here, lockpicking 300, tips welcome", "Gildenwerber", true)
        falsy(LP.FindRequest("Gildenwerber"), "advertisement in guild chat")
    end)
    LP.recentMsgs = was
end)
T("guild chat: the menu lists it next to say and yell", function()
    local en, de = LP.Both("Guild")
    truthy(de == "Gilde", "German name")
    truthy(en == "Guild", "English name")
end)

-- 9) The menus only list what the character really has; announcing in guild chat ----------------------------------------------------
local function WithGame(mocks, fn)   -- replace calls into the game (LP.Game fields) for one call; always restore them. NEVER touch a game global.
    local saved = {}
    for name, v in pairs(mocks) do saved[name] = LP.Game[name] LP.Game[name] = v end
    local ok, err = pcall(fn)
    for name in pairs(mocks) do LP.Game[name] = saved[name] end
    if not ok then error(err, 0) end
end
local function keys(list) local t = {} for _, e in ipairs(list) do t[#t + 1] = e.key end return table.concat(t, ",") end
T("guide: Map button data goes through LP.Game and never sends anything", function()
    local opened, pinned
    WithGame({ OpenMap = function(id) opened = id return true end,
               SetWaypoint = function(id, x, y) pinned = { id, x, y } return true end }, function()
        local sp = LP.GUIDE[4].spots[1]
        truthy(LP.Game.OpenMap(sp.zone) and LP.Game.SetWaypoint(sp.zone, sp.x, sp.y), "stubs used")
        eq(opened, 1427, "Searing Gorge map")
        eq(pinned[2], 42.0, "x")
    end)
    eq(LP.Game.SetWaypoint(nil, 1, 1), false, "no zone: no pin")
end)
T("guide: the guide page builds and fills without errors", function()
    -- the window is the user's: leave it open or closed, and on the tab it was on (the self tests run from the Developer tab)
    local before = _G.PickyFrame
    local wasShown = before and before:IsShown()
    local tab = LP.UITab()
    local pos = LP.db.ui and LP.db.ui.winPos
    local ok, err = pcall(function()
        -- every render walks the bags and asks the game for icons, so keep it to the three that matter: places (own faction), all boxes, and
        -- places again with a client that has no icons, no map names and a different faction
        LP.OpenGuide(4)
        LP.OpenGuide(5)
        WithGame({ Faction = function() return "Horde" end, ItemIcon = function() return nil end, MapName = function() return nil end }, function()
            LP.OpenGuide(1)
        end)
    end)
    local win = _G.PickyFrame
    LP.UITab(tab)
    if win and not wasShown then win:Hide() end
    if LP.db.ui then LP.db.ui.winPos = pos end
    if not ok then error(err, 0) end
end)
T("menus: the guild is only listed inside a guild", function()
    WithGame({ IsInGuild = function() return false end, GetChannelList = function() return 1, "General - City", false, 2, "Trade - City", false end }, function()
        eq(keys(LP.ListenSources()), "say,yell,general,trade", "listen list without a guild")
        eq(keys(LP.AdvertiseSources()), "general,trade", "advertise list without a guild")
    end)
    WithGame({ IsInGuild = function() return true end, GetChannelList = function() return 1, "General - City", false, 2, "Trade - City", false end }, function()
        eq(keys(LP.ListenSources()), "say,yell,guild,general,trade", "listen list in a guild")
        eq(keys(LP.AdvertiseSources()), "general,trade,guild", "advertise list in a guild")
    end)
end)
T("menus: only the channels that are really joined are listed", function()
    WithGame({ IsInGuild = function() return false end, GetChannelList = function() return end }, function()
        eq(keys(LP.ListenSources()), "say,yell", "no channel joined: only say and yell")
        eq(keys(LP.AdvertiseSources()), "", "no channel joined: nothing to advertise in")
    end)
    WithGame({ IsInGuild = function() return false end, GetChannelList = function() return 2, "Trade - City", false, 5, "Services", false end }, function()
        eq(keys(LP.AdvertiseSources()), "trade,services", "exactly the joined channels")
    end)
end)
T("announce in guild chat: only by own choice, never by default", function()
    local ad = LP.db.ad
    local was, wasSeeded = ad.channels, ad.channelsSeeded
    ad.channels = nil
    falsy(LP.AdGuildOn(), "not part of the default")
    ad.channels = { trade = true }
    falsy(LP.AdGuildOn(), "not ticked")
    LP.SetAdChannel("guild", true)
    truthy(LP.AdGuildOn(), "ticked")
    truthy(LP.AdSourceOn("guild"), "the menu shows it ticked")
    LP.SetAdChannel("guild", false)
    falsy(LP.AdGuildOn(), "unticked")
    ad.channels, ad.channelsSeeded = was, wasSeeded
end)
T("announce in guild chat: Announce posts into the guild (simulated) only inside a guild", function()
    local db = LP.db
    local ad = db.ad
    local keep = { ch = ad.channels, last = LP.lastAd, debug = db.debug, dry = LP.forceDry }
    local function posted()
        local before = #LP.debugLog
        LP.lastAd = nil
        LP.lastDebugKey = nil
        LP.PostAd(false)
        for i = before + 1, #LP.debugLog do
            if tostring(LP.debugLog[i]):find("would post to guild chat", 1, true) then return true end
        end
        return false
    end
    local ok, err = pcall(function()
        db.debug, LP.forceDry = true, true   -- nothing is sent, the log shows what would happen
        ad.channels = { guild = true }
        WithGame({ IsInGuild = function() return true end, GetChannelList = function() return end }, function()
            truthy(posted(), "in a guild: would post to guild chat")
        end)
        WithGame({ IsInGuild = function() return false end, GetChannelList = function() return end }, function()
            falsy(posted(), "without a guild: nothing is posted")
        end)
        ad.channels = { trade = true }
        WithGame({ IsInGuild = function() return true end, GetChannelList = function() return end }, function()
            falsy(posted(), "guild not ticked: nothing is posted to the guild")
        end)
    end)
    ad.channels, LP.lastAd, db.debug, LP.forceDry = keep.ch, keep.last, keep.debug, keep.dry
    if not ok then error(err, 0) end
end)

-- 10) Rules that were not pinned down yet (found by the mutation test, tools/mutate.py) ------------------------------------------------------
T("follow-up: a box message that is itself an advertisement does not finish the request", function()
    local was = LP.recentMsgs
    LP.recentMsgs = {}
    Sandbox(nil, function()
        LP.OnChat("CHAT_MSG_CHANNEL", "Lf Rogue for", "Mixer", true)
        LP.OnChat("CHAT_MSG_CHANNEL", LINK_STRONG_DE .. " tips appreciated", "Mixer", true)
        falsy(LP.FindRequest("Mixer"), "the second message is an advertisement")
    end)
    LP.recentMsgs = was
end)
T("follow-up: only asking for a ROGUE opens the follow-up (not any question)", function()
    local was = LP.recentMsgs
    LP.recentMsgs = {}
    Sandbox(nil, function()
        LP.OnChat("CHAT_MSG_CHANNEL", "can someone help me", "Helper", true)
        LP.OnChat("CHAT_MSG_CHANNEL", LINK_STRONG_DE, "Helper", true)
        falsy(LP.FindRequest("Helper"), "a general question plus a box link is no request")
    end)
    LP.recentMsgs = was
end)
T("announce: not twice within 60 seconds", function()
    local db = LP.db
    local ad = db.ad
    local keep = { ch = ad.channels, seeded = ad.channelsSeeded, last = LP.lastAd, debug = db.debug, dry = LP.forceDry }
    local function posted()
        local before = #LP.debugLog
        LP.lastDebugKey = nil
        LP.PostAd(false)
        for i = before + 1, #LP.debugLog do
            if tostring(LP.debugLog[i]):find("would post to guild chat", 1, true) then return true end
        end
        return false
    end
    local ok, err = pcall(function()
        db.debug, LP.forceDry = true, true
        ad.channels = { guild = true }
        WithGame({ IsInGuild = function() return true end, GetChannelList = function() return end }, function()
            LP.lastAd = GetTime() - 10
            falsy(posted(), "10 seconds after the last announcement: nothing is posted")
            LP.lastAd = GetTime() - 61
            truthy(posted(), "61 seconds after: posted (simulated)")
            LP.lastAd = nil
            truthy(posted(), "no announcement before: posted (simulated)")
        end)
    end)
    ad.channels, ad.channelsSeeded, LP.lastAd, db.debug, LP.forceDry = keep.ch, keep.seeded, keep.last, keep.debug, keep.dry
    if not ok then error(err, 0) end
end)
T("decide: exactly enough skill is enough, one point less is not", function()
    Sandbox(nil, function()
        LP.skill = 225
        local r = LP.SimulateChat("need rogue for thorium lockbox", false)
        truthy(r, "request created")
        eq(r.req, 225, "the box needs 225")
        eq(r.status, "invited", "skill 225 for a box that needs 225")
        LP.pending = nil
        LP.skill = 224
        local r2 = LP.SimulateChat("need rogue for thorium lockbox", false)
        eq(r2.status, "toohigh", "skill 224 for a box that needs 225")
    end)
end)
T("skill: the estimate is level x 5, at most 300", function()
    local db = LP.db
    local keep = { known = LP.PickLockKnown, rogue = LP.IsRogue, list = LP.ReadSkillList, base = db.skillBase, ts = LP.Game.TradeSkillInfo }
    local ok, err = pcall(function()
        LP.Game.TradeSkillInfo = function() return nil end
        LP.IsRogue = function() return true end
        LP.ReadSkillList = function() return nil end
        db.skillBase = nil
        LP.PickLockKnown = function() return true end   -- known, but the list gives nothing: estimate
        WithGame({ UnitLevel = function() return 40 end }, function()
            LP.RefreshSkill()
            eq(LP.skillBase, 200, "level 40")
            truthy(LP.skillEstimated, "marked as an estimate")
        end)
        WithGame({ UnitLevel = function() return 70 end }, function()
            LP.RefreshSkill()
            eq(LP.skillBase, 300, "never more than 300")
        end)
        WithGame({ UnitLevel = function() return 1 end }, function()
            LP.RefreshSkill()
            eq(LP.skillBase, 5, "level 1")
        end)
    end)
    LP.PickLockKnown, LP.IsRogue, LP.ReadSkillList, db.skillBase, LP.Game.TradeSkillInfo = keep.known, keep.rogue, keep.list, keep.base, keep.ts
    LP.RefreshSkill()
    if not ok then error(err, 0) end
end)
T("defaults: the safe starting values of a new installation", function()
    local f = LP.defaults.finder
    eq(f.enabled, false, "duty is off")
    eq(f.autoInvite, false, "no automatic invites")
    eq(f.inviteUnknown, false, "no invites without a named box")
    eq(f.onlyWhenFree, true, "one customer at a time")
    eq(f.leaveDelay, 5, "wait before leaving")
    eq(f.idleLeave, 180, "leave without activity")
    eq(f.cooldown, 180, "cooldown for the same player")
    eq(LP.defaults.debug, false, "test mode is off")
    eq(LP.defaults.dev, false, "developer tab is hidden")
end)

-- 11) Statistics and thanks in REAL operation (not a dry run). Everything that would be sent is caught instead. ---------------------------------
local function Real(fn)
    -- real mode: no test mode, no dry run; whispers, invites, channel posts, leaving and timers are replaced, so nothing is ever sent
    local db = LP.db
    local sent = { invites = {}, whispers = {}, posts = 0, leaves = 0 }
    local keep = { Invite = LP.Invite, Whisper = LP.Whisper, SendChannel = LP.SendChannel, SendGuild = LP.SendGuild, Leave = LP.Leave, After = LP.After,
        debug = db.debug, dry = LP.forceDry, sim = LP.partnerSim }
    LP.Invite = function(n) sent.invites[#sent.invites + 1] = n end
    LP.Whisper = function(n, t) sent.whispers[#sent.whispers + 1] = { name = n, text = t } end
    LP.SendChannel = function() sent.posts = sent.posts + 1 return true end
    LP.SendGuild = function() sent.posts = sent.posts + 1 return true end
    LP.Leave = function() sent.leaves = sent.leaves + 1 end
    LP.After = function() end
    db.debug, LP.forceDry, LP.partnerSim = false, false, nil
    local ok, err = pcall(fn, sent)
    LP.Invite, LP.Whisper, LP.SendChannel, LP.SendGuild, LP.Leave, LP.After = keep.Invite, keep.Whisper, keep.SendChannel, keep.SendGuild, keep.Leave, keep.After
    db.debug, LP.forceDry, LP.partnerSim = keep.debug, keep.dry, keep.sim
    if not ok then error(err, 0) end
end
local function Request(name, status, extra)
    local r = { name = name, sender = name, status = status, msg = "x", time = GetTime() }
    if extra then for k, v in pairs(extra) do r[k] = v end end
    return r
end
T("statistics: an invite is counted in real operation, not in a dry run", function()
    Sandbox(nil, function(db)
        local r = Request("Kunde", "new", { req = 1 })
        LP.forceDry = true
        local before = db.stats.invited
        LP.TryInvite(r)
        eq(db.stats.invited, before, "dry run: not counted")
        LP.pending = nil
        Real(function(sent)
            local r2 = Request("Kunde2", "new", { req = 1 })
            LP.TryInvite(r2)
            eq(db.stats.invited, before + 1, "real: counted once")
            eq(#sent.invites, 1, "the invite was 'sent' (caught)")
            eq(sent.invites[1], "Kunde2", "to the right player")
            eq(r2.status, "invited", "status")
        end)
    end)
end)
T("statistics: a picked box is counted in real operation, not in a simulation", function()
    Sandbox(nil, function(db)
        Real(function()
            local before = db.stats.picked
            LP.OnPickSuccess(true)
            eq(db.stats.picked, before, "simulated: not counted")
            LP.OnPickSuccess(false)
            eq(db.stats.picked, before + 1, "real: counted once")
            LP.OnPickSuccess(false)
            eq(db.stats.picked, before + 2, "real: counted again")
        end)
    end)
end)
T("statistics: tips add up and are never counted for a simulation", function()
    Sandbox(nil, function(db)
        Real(function()
            local before = db.stats.tips
            LP.HandleTip("Geber", 2500, true)
            eq(db.stats.tips, before, "simulated: not counted")
            LP.HandleTip("Geber", 2500, false)
            LP.HandleTip("Geber", 100, false)
            eq(db.stats.tips, before + 2600, "real: summed")
        end)
    end)
end)
T("thanks: one thank-you per order, only with a tip, only when switched on; counted in the statistics", function()
    Sandbox(nil, function(db)
        Real(function(sent)
            db.finder.thanks = true
            local before = db.stats.thanked
            local r = Request("Dankbar", "done", { tipTotal = 500 })
            LP.SendThanks(r)
            eq(db.stats.thanked, before + 1, "counted")
            eq(#sent.whispers, 1, "one whisper")
            truthy(r.thanked, "marked as thanked")
            LP.SendThanks(r)
            eq(#sent.whispers, 1, "never twice")
            eq(db.stats.thanked, before + 1, "not counted twice")
            local noTip = Request("OhneTrinkgeld", "done", { tipTotal = 0 })
            LP.SendThanks(noTip)
            eq(#sent.whispers, 1, "no tip: no thanks")
            db.finder.thanks = false
            local off = Request("Aus", "done", { tipTotal = 900 })
            LP.SendThanks(off)
            eq(#sent.whispers, 1, "thanks switched off: no whisper")
            eq(db.stats.thanked, before + 1, "and not counted")
        end)
    end)
end)
T("thanks: a tip from someone outside the group is thanked at once and counted on the order", function()
    Sandbox(nil, function(db)
        Real(function(sent)
            db.finder.thanks = true
            local before = db.stats.thanked
            LP.requests[#LP.requests + 1] = Request("Passant", "done", { tipTotal = 0 })
            LP.HandleTip("Passant", 700, false)
            eq(#sent.whispers, 1, "thanked at once")
            eq(db.stats.thanked, before + 1, "counted")
            eq(LP.FindRequest("Passant").tipTotal, 700, "tip is on the order")
        end)
    end)
end)
T("thanks: with thanks switched off the tip still lands on the order and in the statistics", function()
    Sandbox(nil, function(db)
        Real(function(sent)
            db.finder.thanks = false
            local before = db.stats.tips
            LP.requests[#LP.requests + 1] = Request("Stumm", "done", { tipTotal = 100 })
            LP.HandleTip("Stumm", 400, false)
            eq(#sent.whispers, 0, "no whisper")
            eq(LP.FindRequest("Stumm").tipTotal, 500, "tip added to the order")
            eq(db.stats.tips, before + 400, "and to the statistics")
        end)
    end)
end)
T("state: only waiting requests can be invited, the oldest first", function()
    Sandbox(nil, function()
        LP.requests = {
            Request("neu2", "new"), Request("zuhoch", "toohigh"), Request("fertig", "done"), Request("eingeladen", "invited"),
            Request("zeit", "timeout"), Request("neu1", "manual"),
        }   -- newest first, like the real list
        eq(LP.NextInvitable().name, "neu1", "the oldest waiting request")
        LP.requests = { Request("zuhoch", "toohigh"), Request("fertig", "done"), Request("eingeladen", "invited"), Request("zeit", "timeout") }
        eq(LP.NextInvitable(), nil, "nobody who can be invited")
    end)
end)
