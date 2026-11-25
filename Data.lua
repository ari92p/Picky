-- Picky / Data.lua : boxes, keywords, skill guide
-- Box skill values (checked 2026-11-23): read from the item tooltips in the WoW Forever client by the author.
-- 6356 (Battered Chest, only from pickpocketing) shows no skill in its tooltip, so it is 1 (no requirement).
-- Also matches a Thorium report from a player on CurseForge. Wowhead's WoW Forever item pages do not show the requirement.
-- If WoW Forever changes something, edit here. Texts use an English key in Locale.lua.
local ADDON, LP = ...
local L = LP.L

-- itemID = { required skill, English name }
LP.BOXES = {
    [6712]  = { 1,   "Practice Lock" },
    [6354]  = { 1,   "Small Locked Chest" },
    [16882] = { 1,   "Battered Junkbox" },
    [4632]  = { 1,   "Ornate Bronze Lockbox" },
    [4633]  = { 25,  "Heavy Bronze Lockbox" },
    [4634]  = { 70,  "Iron Lockbox" },
    [6355]  = { 70,  "Sturdy Locked Chest" },
    [6356]  = { 1,   "Battered Chest" },   -- pickpocket only, no skill shown in the tooltip: 1 = any rogue
    [16883] = { 70,  "Worn Junkbox" },
    [4636]  = { 125, "Strong Iron Lockbox" },
    [4637]  = { 175, "Steel Lockbox" },
    [13875] = { 175, "Ironbound Locked Chest" },
    [16884] = { 175, "Sturdy Junkbox" },
    [4638]  = { 225, "Reinforced Steel Lockbox" },
    [5758]  = { 225, "Mithril Lockbox" },
    [13918] = { 250, "Reinforced Locked Chest" },
    [5759]  = { 225, "Thorium Lockbox" },
    [16885] = { 250, "Heavy Junkbox" },
    [5760]  = { 225, "Eternium Lockbox" },
}

-- German names (fallback). The name the game itself returns (GetItemInfo) always wins: LP.BoxName.
-- Confirmed (Wowhead de): 6354, 6355, 6356, 16882-16885 (6712 "Aufziehkiste" only from the general de page). The rest (Schließkassetten, Eisenbeschlagene/Verstärkte Truhe) is guessed,
-- until the game provides the names itself: Picky stores them at login in PickyDB.itemNames (see below).
local DE_NAMES = {
    [6712] = "Aufziehkiste", [6354] = "Kleine verschlossene Truhe", [16882] = "Ramponierte Plunderkiste",
    [4632] = "Verzierte Bronzeschließkassette", [4633] = "Schwere Bronzeschließkassette", [4634] = "Eisenschließkassette",
    [6355] = "Stabile verschlossene Truhe", [6356] = "Ramponierte Truhe", [16883] = "Abgenutzte Plunderkiste",
    [4636] = "Starke Eisenschließkassette", [4637] = "Stahlschließkassette", [13875] = "Eisenbeschlagene verschlossene Truhe",
    [16884] = "Stabile Plunderkiste", [4638] = "Verstärkte Stahlschließkassette", [5758] = "Mithrilschließkassette",
    [13918] = "Verstärkte verschlossene Truhe", [5759] = "Thoriumschließkassette", [16885] = "Schwere Plunderkiste",
    [5760] = "Eterniumschließkassette",
}
-- Name of a box in the game language: first from the game, otherwise from the table, otherwise English
function LP.BoxName(id)
    local name = GetItemInfo and GetItemInfo(id)
    if name then return name end
    local cached = LP.db and LP.db.itemNames and LP.db.itemNames[id]   -- remembered from the game itself
    if cached then return cached end
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end   -- queue it up for next time
    local b = LP.BOXES[id]
    if LP.isGerman and DE_NAMES[id] then return DE_NAMES[id] end
    return b and b[2] or "?"
end
-- At login, request all box names from the game and store them in PickyDB.itemNames: these are then the REAL names in your game language
local function LearnName(id)
    local name = GetItemInfo and GetItemInfo(id)
    if name and LP.db then
        LP.db.itemNames = LP.db.itemNames or {}
        LP.db.itemNames[id] = name
    end
end
LP.On("PLAYER_ENTERING_WORLD", function()
    for id in pairs(LP.BOXES) do
        if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end
        LearnName(id)
    end
end)
LP.On("GET_ITEM_INFO_RECEIVED", function(_, id)
    if id and LP.BOXES[id] then LearnName(id) end
end)
-- Words in chat (English + German) -> estimated skill (when ambiguous the higher value, better safe than sorry)
-- Fourth field true = the first field is a Lua pattern (whole word), otherwise a plain substring
LP.OnLanguage(function()
    LP.BOXKEYS = {
        { "bronz", 25, L["Bronze box"] },        -- "bronze" / "bronze-kiste"
        { "%f[%a]iron%f[%A]", 125, L["Iron box"], true },   -- whole word only: "ironforge" is a city, not a box
        { "eisen", 125, L["Iron box"] },
        { "steel", 225, L["Steel box"] },
        { "stahl", 225, L["Steel box"] },
        { "mithril", 225, L["Mithril box"] },
        { "thorium", 225, L["Thorium box"] },
        { "eternium", 225, L["Eternium box"] },
        { "footlocker", 70, "Footlocker" },
    }

    -- Guide ----------------------------------------------------------------------
    -- Sources: wow-professions.com and conquestcapped.com (Forever lockpicking guides) plus the author's own tests.
    -- COORDINATES (x, y in percent) and mapIDs come from those guides / from memory and are NOT yet checked in the game:
    -- the dev self test "guide: map ids resolve to zone names" logs what the client says; verify the pins by clicking "Map".
    -- A spot without x/y only opens the zone map. faction = "A" (Alliance) / "H" (Horde) / nil (both): the nearer place, anyone can go anywhere.
    -- Objects (footlockers, strongboxes) are no items: iconItem is only a lockbox whose icon stands in for them.
    local function Obj(name, iconItem, skill, hint)
        return { name = name, iconItem = iconItem, skill = skill, hint = hint }
    end
    local STRONGBOX   = Obj(L["Buccaneer's Strongbox"], 4632, nil, L["Opens up to about skill 100."])
    local PRACTICE    = Obj(L["Practice Lockbox"], 4632, nil, L["Respawns really fast."])
    local BATTERED    = Obj(L["Battered Footlocker"], 4634, 150, L["Upstairs at Angor Fortress."])
    local BATTERED_LO = Obj(L["Battered Footlocker"], 4634, nil, L["The lower ones, about skill 70 to 110."])
    local WATERLOGGED = Obj(L["Waterlogged Footlocker"], 4637, 110, L["On the shore from the start, the ones in the water open from 110."])
    local DENTED_LOW  = Obj(L["Dented Footlocker (lower)"], 5758, 200, L["The lower part gives points until you stop getting them, then switch to the upper part."])
    local DENTED_175  = Obj(L["Dented Footlocker (175)"], 5758, 175, L["Downstairs at Angor Fortress. A point every time until 215."])
    local DENTED_UP   = Obj(L["Dented Footlocker (upper)"], 5759, 225, L["Gives points all the way to 300."])
    local MOSSY       = Obj(L["Mossy Footlocker"], 5759, nil, L["Seen in Desolace, Swamp of Sorrows, Tanaris and Azshara."])
    local SCARLET     = Obj(L["Scarlet Footlocker"], 5760, nil, L["Tyr's Hand, full of level 55-60 elites."])
    local HEAVYJUNK   = { name = L["Heavy Junkbox"], item = 16885, skill = 250, hint = L["Pick Pocket level 51-60 humanoids."] }

    LP.GUIDE = {
        {
            from = 1, to = 100, title = "1 - 100", levelReq = 20,
            spots = {
                { zone = 1413, x = 65.0, y = 45.5, faction = "H", best = true, where = L["Ship south of Ratchet"],
                  note = L["Inside the ship. Fast respawn, two rogues can skill up together."], boxes = { STRONGBOX } },
                { zone = 1433, x = 46.6, y = 45.0, faction = "A", best = true, where = L["Alther's Mill"],
                  note = L["Also north of Lake Everstill. Really fast respawn."], boxes = { PRACTICE } },
            },
            tips = {
                { "warn", L["Do NOT open 'The Jewel of the Southsea' at the bottom of the ship at a low level: it spawns a mob that kills you."] },
                { "tip", L["Points get slow after about 65. Move on at 100 at the latest."] },
            },
        },
        {
            from = 100, to = 150, title = "100 - 150", levelReq = 30,
            spots = {
                { zone = 1440, x = 11.3, y = 21.7, faction = "H", best = true, where = L["Zoram Strand"],
                  note = L["Along the shore. Alone you get to about 150 if nobody competes."], boxes = { WATERLOGGED } },
                { zone = 1442, x = 67.5, y = 51.5, faction = "H", where = L["Windshear Crag"],
                  note = L["Inner and upper spots (Windshear Mine) for the higher boxes."], boxes = { BATTERED_LO, WATERLOGGED } },
                { zone = 1437, x = 18.7, y = 35.6, faction = "A", where = L["Murloc camps"],
                  note = L["The inner camps hold the higher boxes."], boxes = { BATTERED_LO, WATERLOGGED } },
                { zone = 1424, x = 78.8, y = 43.4, where = L["Durnholde Keep"],
                  note = L["The upper ring has the higher boxes."], boxes = { BATTERED_LO, WATERLOGGED } },
                { zone = 1433, x = 40.5, y = 60.0, faction = "A", where = L["Lake Everstill"],
                  note = L["The boxes are underwater."], boxes = { WATERLOGGED } },
            },
            tips = {
                { "tip", L["Bring Water Breathing for underwater boxes."] },
            },
        },
        {
            from = 150, to = 225, title = "150 - 225", levelReq = 45,
            spots = {
                { zone = 1418, x = 41.5, y = 28.5, best = true, where = L["Angor Fortress"],
                  note = L["Battered upstairs, Dented downstairs."], boxes = { BATTERED, DENTED_175 } },
                { zone = 1443, x = 36.7, y = 22.5, where = L["Sar'theris Strand"],
                  note = L["Underwater. A quiet alternative if Angor Fortress is crowded."], boxes = { WATERLOGGED } },
                { zone = 1443, x = 34.5, y = 12.8, where = L["North coast of Desolace"],
                  note = L["Many Mossy Footlockers."], boxes = { DENTED_175, MOSSY } },
                { zone = 1435, x = 65.3, y = 53.8, where = L["Pool of Tears"],
                  note = L["Underwater, only two Mossy Footlockers."], boxes = { DENTED_175, MOSSY } },
            },
            tips = {
                { "tip", L["The Dented Footlockers downstairs give a skill point every time until 215, so you can stay until 225."] },
                { "tip", L["Angor Fortress is often camped by other rogues."] },
                { "warn", L["Do not pickpocket here: their boxes are too low to give skill."] },
            },
        },
        {
            from = 225, to = 300, title = "225 - 300", levelReq = 60,
            spots = {
                { zone = 1427, x = 42.0, y = 38.0, best = true, where = L["The Slag Pit"],
                  note = L["The cave in the middle of Searing Gorge. Lower ones need 200, upper ones 225."], boxes = { DENTED_LOW, DENTED_UP } },
                { zone = 1446, where = L["Lost Rigger Cove"],
                  note = L["Pirate camp on the east coast of Tanaris. Same boxes as the Slag Pit upper part, go here when the Slag Pit is full."], boxes = { DENTED_UP, MOSSY } },
                { zone = 1423, where = L["Tyr's Hand"],
                  note = L["For the last points from 250. Boxes respawn slowly."], boxes = { SCARLET, HEAVYJUNK } },
            },
            tips = {
                { "tip", L["The upper ones are yellow until 290, so the last 10 points take longer."] },
                { "warn", L["Tyr's Hand is full of level 55-60 elites. Only go when you are ready."] },
                { "warn", L["Do not pickpocket at Angor Fortress or the Slag Pit, it is not worth it."] },
            },
        },
    }
    -- Tips that apply everywhere (the Tips tab)
    LP.GUIDE_TIPS = {
        { "info", L["Your skill cannot be higher than 5 x your level (level 20: 100, 30: 150, 45: 225, 60: 300)."] },
        { "warn", L["Keep Thieves' Tools in your bags, or Pick Lock does nothing."] },
        { "tip", L["A box that looks grey may still give a point. Try it once."] },
        { "tip", L["Stand where you can reach two boxes without moving."] },
        { "tip", L["Other rogues compete for the starter spots. Switch spot or try another layer."] },
        { "tip", L["Bring Water Breathing for underwater boxes."] },
        { "tip", L["Boxes can hide in grass and seaweed. Lower the ground clutter."] },
        { "tip", L["Spawn counts differ from Classic. If a spot is empty, move on."] },
    }
end)
-- Warning when the skill is held back by the character level (cap = 5 x level). nil when nothing is wrong.
function LP.GuideAdvice(skill, level)
    skill, level = tonumber(skill) or 0, tonumber(level) or 0
    if level < 1 or skill >= 300 then return nil end
    if skill >= level * 5 then
        return "warn", L["Your skill is capped by your level. Reach level %d to learn more."]:format(math.ceil((skill + 1) / 5))
    end
end
-- What you can reach right now: the lower of your rank limit and your level limit (5 x level), at most 300, never below what you have
function LP.SkillReach(rankMax, level, base)
    local rank = (tonumber(rankMax) and rankMax > 0) and math.min(300, rankMax) or 300
    local cap = math.min(300, (tonumber(level) or 1) * 5)
    return math.max(1, math.min(rank, cap), tonumber(base) or 0)
end
function LP.StageForSkill(skill)
    for i, s in ipairs(LP.GUIDE) do
        if skill < s.to then return i end
    end
    return #LP.GUIDE
end
