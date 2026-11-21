-- Picky / Data.lua : Kisten, Schlüsselwörter, Skill-Guide
-- Alle Werte sind aus dem Gedächtnis (Vanilla-Daten) und leicht anpassbar.
-- Falls WoW Forever etwas ändert: hier editieren. Texte stehen mit englischem Schlüssel in Locale.lua.
local ADDON, LP = ...
local L = LP.L

-- itemID = { benötigter Skill, englischer Name }
LP.BOXES = {
    [6712]  = { 1,   "Practice Lock" },
    [6354]  = { 1,   "Small Locked Chest" },
    [16882] = { 1,   "Battered Junkbox" },
    [4632]  = { 25,  "Ornate Bronze Lockbox" },
    [4633]  = { 50,  "Heavy Bronze Lockbox" },
    [4634]  = { 70,  "Iron Lockbox" },
    [6355]  = { 70,  "Sturdy Locked Chest" },
    [6356]  = { 70,  "Battered Chest" },
    [16883] = { 70,  "Worn Junkbox" },
    [4636]  = { 125, "Strong Iron Lockbox" },
    [4637]  = { 175, "Steel Lockbox" },
    [13875] = { 175, "Ironbound Locked Chest" },
    [16884] = { 175, "Sturdy Junkbox" },
    [4638]  = { 225, "Reinforced Steel Lockbox" },
    [5758]  = { 225, "Mithril Lockbox" },
    [13918] = { 225, "Reinforced Locked Chest" },
    [5759]  = { 250, "Thorium Lockbox" },
    [16885] = { 250, "Heavy Junkbox" },
    [5760]  = { 300, "Eternium Lockbox" },
}

-- Deutsche Namen (Ersatz). Maßgeblich ist immer der Name, den das Spiel selbst liefert (GetItemInfo): LP.BoxName.
-- Bestätigt (Wowhead de): 6354, 6355, 6356, 16882-16885 (6712 "Aufziehkiste" nur von der allgemeinen de-Seite). Der Rest (Schließkassetten, Eisenbeschlagene/Verstärkte Truhe) ist geraten,
-- bis das Spiel selbst die Namen liefert: Picky merkt sich sie beim Einloggen in PickyDB.itemNames (siehe unten).
local DE_NAMES = {
    [6712] = "Aufziehkiste", [6354] = "Kleine verschlossene Truhe", [16882] = "Ramponierte Plunderkiste",
    [4632] = "Verzierte Bronzeschließkassette", [4633] = "Schwere Bronzeschließkassette", [4634] = "Eisenschließkassette",
    [6355] = "Stabile verschlossene Truhe", [6356] = "Ramponierte Truhe", [16883] = "Abgenutzte Plunderkiste",
    [4636] = "Starke Eisenschließkassette", [4637] = "Stahlschließkassette", [13875] = "Eisenbeschlagene verschlossene Truhe",
    [16884] = "Stabile Plunderkiste", [4638] = "Verstärkte Stahlschließkassette", [5758] = "Mithrilschließkassette",
    [13918] = "Verstärkte verschlossene Truhe", [5759] = "Thoriumschließkassette", [16885] = "Schwere Plunderkiste",
    [5760] = "Eterniumschließkassette",
}
-- Name einer Kiste in der Sprache des Spiels: erst vom Spiel, sonst aus der Tabelle, sonst englisch
function LP.BoxName(id)
    local name = GetItemInfo and GetItemInfo(id)
    if name then return name end
    local cached = LP.db and LP.db.itemNames and LP.db.itemNames[id]   -- vom Spiel selbst gemerkt
    if cached then return cached end
    if C_Item and C_Item.RequestLoadItemDataByID then pcall(C_Item.RequestLoadItemDataByID, id) end   -- fürs nächste Mal vormerken
    local b = LP.BOXES[id]
    if LP.isGerman and DE_NAMES[id] then return DE_NAMES[id] end
    return b and b[2] or "?"
end
-- Beim Einloggen alle Kisten-Namen vom Spiel anfordern und in PickyDB.itemNames merken: das sind dann die ECHTEN Namen deiner Spielsprache
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
-- Wörter im Chat (Englisch + Deutsch) -> geschätzter Skill (bei Mehrdeutigkeit der höhere Wert, sicher ist sicher)
LP.BOXKEYS = {
    { "bronz", 50, L["Bronze box"] },        -- "bronze" / "bronze-kiste"
    { "iron", 125, L["Iron box"] },
    { "eisen", 125, L["Iron box"] },
    { "steel", 225, L["Steel box"] },
    { "stahl", 225, L["Steel box"] },
    { "mithril", 225, L["Mithril box"] },
    { "thorium", 250, L["Thorium box"] },
    { "eternium", 300, L["Eternium box"] },
    { "footlocker", 70, "Footlocker" },
}

-- Guide ----------------------------------------------------------------------
LP.GUIDE = {
    {
        from = 1, to = 100, title = "1 - 100",
        boxes = { L["guide1.box1"], L["guide1.box2"] },
        places = { L["guide1.place1"], L["guide1.place2"] },
        tip = L["guide1.tip"],
    },
    {
        from = 100, to = 150, title = "100 - 150",
        boxes = { L["guide2.box1"] },
        places = { L["guide2.place1"] },
        tip = L["guide2.tip"],
    },
    {
        from = 150, to = 225, title = "150 - 225",
        boxes = { L["guide3.box1"], L["guide3.box2"] },
        places = { L["guide3.place1"] },
        tip = L["guide3.tip"],
    },
    {
        from = 225, to = 300, title = "225 - 300",
        boxes = { L["guide4.box1"], L["guide4.box2"] },
        places = { L["guide4.place1"] },
        tip = L["guide4.tip"],
    },
}
function LP.StageForSkill(skill)
    for i, s in ipairs(LP.GUIDE) do
        if skill < s.to then return i end
    end
    return #LP.GUIDE
end
