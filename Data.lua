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
    -- Lost Rigger Cove and Tyr's Hand: coordinates of the place itself (warcraft.wiki.gg), the pin is a start point, not the exact box.
    -- A spot without x/y only opens the zone map. faction = "A" (Alliance) / "H" (Horde) / nil (both): the nearer place, anyone can go anywhere.
    -- Objects (footlockers, strongboxes) are no items: iconItem is only a lockbox whose icon stands in for them.
    local function Obj(name, iconItem, skill, hint)
        return { name = name, iconItem = iconItem, skill = skill, hint = hint }
    end
    local STRONGBOX   = Obj(L["Buccaneer's Strongbox"], 4632, nil, L["Good for skill points up to about 100."])
    local PRACTICE    = Obj(L["Practice Lockbox"], 4632, nil, L["Respawns very fast."])
    local BATTERED    = Obj(L["Battered Footlocker"], 4634, 150, L["Upstairs in Angor Fortress."])
    local BATTERED_LO = Obj(L["Battered Footlocker"], 4634, 70)
    local WATERLOGGED = Obj(L["Waterlogged Footlocker"], 4637, 110, L["The ones on the shore open from the start, the ones in the water from skill 110."])
    local DENTED_LOW  = Obj(L["Dented Footlocker (lower)"], 5758, 200, L["Gives points in the lower part until they stop coming, then move to the upper part."])
    local DENTED_175  = Obj(L["Dented Footlocker (175)"], 5758, 175, L["Downstairs in Angor Fortress. Gives a point every time until skill 215."])
    local DENTED_UP   = Obj(L["Dented Footlocker (upper)"], 5759, 225, L["Gives points up to skill 300."])
    local MOSSY       = Obj(L["Mossy Footlocker"], 5759, nil, L["Found in Desolace, Swamp of Sorrows, Tanaris and Azshara."])
    local SCARLET     = Obj(L["Scarlet Footlocker"], 5760, nil, L["Found in Tyr's Hand, which is full of level 55-60 elites."])
    local HEAVYJUNK   = { name = L["Heavy Junkbox"], item = 16885, skill = 250, hint = L["Comes from pickpocketing level 51-60 humanoids."] }

    -- Route and order follow the Warcraft Tavern WoW Forever lockpicking guide (warcrafttavern.com/forever/guides/lockpicking).
    -- Stage ends are skill / 5 = character level (levelReq). Stages 250-265 (Blackrock Depths) is a tip, not a map spot.
    LP.GUIDE = {
        {
            from = 1, to = 110, title = "1 - 110", levelReq = 22,
            spots = {
                { zone = 1413, x = 65.0, y = 45.5, faction = "H", best = true, where = L["Ship south of Ratchet"],
                  note = L["Inside the ship. Fast respawn, two rogues can skill up together."] .. " " .. L["Then go to Zoram Strand (Ashenvale) for the Waterlogged Footlockers: they take you to 110."], boxes = { STRONGBOX, WATERLOGGED } },
                { zone = 1433, x = 46.6, y = 45.0, faction = "A", best = true, where = L["Alther's Mill"],
                  note = L["Practice Lockboxes also stand north of Lake Everstill. They respawn very fast."] .. " " .. L["Then go inside Lake Everstill for the Waterlogged Footlockers: they take you to 110."], boxes = { PRACTICE, WATERLOGGED } },
            },
            tips = {
                { "info", L["Quests from level 16: Alliance 'Redridge Rendezvous' then 'Alther's Mill', Horde 'Wrenix of Ratchet' then 'Plundering the Plunders'. They give the Thieves' Tools."] },
                { "tip", L["Pick the Practice Lockboxes up to at least 80, then move on to the Waterlogged Footlockers."] },
                { "warn", L["Keep Thieves' Tools in your bags, or Pick Lock will not work."] },
            },
        },
        {
            from = 110, to = 150, title = "110 - 150", levelReq = 30,
            spots = {
                { zone = 1442, x = 67.5, y = 51.5, faction = "H", best = true, where = L["Windshear Crag"],
                  note = L["The higher boxes are further inside and higher up (Windshear Mine)."], boxes = { BATTERED_LO } },
                { zone = 1424, x = 78.8, y = 43.4, where = L["Durnholde Keep"],
                  note = L["The higher boxes are on the upper ring."], boxes = { BATTERED_LO } },
                { zone = 1437, x = 18.7, y = 35.6, faction = "A", best = true, where = L["Murloc camps"],
                  note = L["Northeast of Menethil Harbor."] .. " " .. L["The higher boxes are in the inner camps."], boxes = { BATTERED_LO } },
            },
        },
        {
            from = 150, to = 200, title = "150 - 200", levelReq = 40,
            spots = {
                { zone = 1424, x = 78.8, y = 43.4, best = true, where = L["Durnholde Keep"],
                  note = L["Very easy, tested from 160 to 170: only the upper Battered Footlockers still give points after 150, one point each. The lower ones are green and give nothing. The boxes respawn slowly. A good choice while your level holds you back."], boxes = { BATTERED_LO } },
                { zone = 1443, x = 36.7, y = 22.5, where = L["Sar'theris Strand"],
                  note = L["Deep below the water on the coast of the Veiled Sea. You can reach 200 here."] .. " " .. L["Underwater mobs and a short breath bar: bring Water Breathing."], boxes = { WATERLOGGED } },
                { zone = 1435, where = L["Temple of Atal'Hakkar"],
                  note = L["Swamp of Sorrows. From 175 you can open the Mossy Footlockers; they give points up to 200."], boxes = { MOSSY } },
                { zone = 1418, x = 41.5, y = 28.5, where = L["Angor Fortress"],
                  note = L["Battered upstairs from 150 to 175, then Dented downstairs up to 200."] .. " " .. L["Other rogues often camp at Angor Fortress."], boxes = { BATTERED, DENTED_175 } },
            },
        },
        {
            from = 200, to = 250, title = "200 - 250", levelReq = 50,
            spots = {
                { zone = 1427, x = 42.0, y = 38.0, best = true, where = L["The Slag Pit"],
                  note = L["The cave in the middle of Searing Gorge. Lower ones need 200, upper ones 225."] .. " " .. L["Circle the area until 225, then work the upper levels to reach 250."] .. " " .. L["You can also pickpocket mobs here for extra boxes."], boxes = { DENTED_LOW, DENTED_UP } },
                { zone = 1447, where = L["Bay of Storms"],
                  note = L["Azshara. Mossy Footlockers from 225 up to 250. Harder, but handy when Searing Gorge is crowded."], boxes = { MOSSY } },
                { zone = 1446, x = 72.2, y = 46.0, where = L["Lost Rigger Cove"],
                  note = L["Tanaris, east of the Caverns of Time. Dented Footlockers from 225, slower than the Slag Pit."], boxes = { DENTED_UP } },
            },
        },
        {
            from = 250, to = 300, title = "250 - 300", levelReq = 60,
            spots = {
                { zone = 1423, x = 79.0, y = 75.0, best = true, where = L["Tyr's Hand"],
                  note = L["Scarlet Footlockers from 265. You can spam them up to 300. The boxes respawn slowly."] .. " " .. L["Tyr's Hand is full of level 55-60 elites. Only go if you can handle them."], boxes = { SCARLET, HEAVYJUNK } },
            },
            tips = {
                { "tip", L["250 to 265: the Shadowforge Lock in Blackrock Depths. It only works until 265; reset the instance to get back to it."] },
            },
        },
    }
end)
-- Warning when the skill is held back by the character level (cap = 5 x level). nil when nothing is wrong.
function LP.GuideAdvice(skill, level)
    skill, level = tonumber(skill) or 0, tonumber(level) or 0
    if level < 1 or skill >= 300 then return nil end
    if skill >= level * 5 then
        return "warn", L["Your level limits your skill. Reach level %d to raise it further."]:format(math.ceil((skill + 1) / 5))
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
