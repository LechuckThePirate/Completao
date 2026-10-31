local _, ns = ...

-- The 9 new dungeons of Forever (new = true; levels from classicwow.gg/forever/dungeons, other sites disagree on some).
-- Quests are empty on purpose: no IDs are invented. They are filled with verified data. The names are translated in
-- Localization/ by their English name (the instances are new). The classic dungeons are in Data/Classic/Dungeons.lua.
local dungeons = {
    { id = "hot",  name = "The Hall of Thanes",       minLevel = 13, maxLevel = 18, new = true },
    { id = "rol",  name = "Ruins of Lordaeron",       minLevel = 15, maxLevel = 20, new = true },
    { id = "exw",  name = "Excavation Site: Wetlands", minLevel = 26, maxLevel = 31, new = true },
    { id = "dal",  name = "City of Dalaran",          minLevel = 28, maxLevel = 33, new = true },
    { id = "dc",   name = "The Drowned City",         minLevel = 35, maxLevel = 40, new = true },
    { id = "kds",  name = "Krol'dok Stronghold",      minLevel = 40, maxLevel = 45, new = true },
    { id = "alc",  name = "Alcaz Prison",             minLevel = 48, maxLevel = 53, new = true },
    { id = "bmh",  name = "Blackmaw Hold",            minLevel = 55, maxLevel = 60, new = true },
    { id = "sht",  name = "Shaper's Terrace",         minLevel = 58, maxLevel = 60, new = true },
}

for _, d in ipairs(dungeons) do
    ns.RegisterEntry(d)
end

-- Zone of the entrance of the new dungeons (no exact coordinates yet;
-- source: classicwow.gg/forever/dungeons). The classic ones are generated in Data/<Flavor>/Generated/Entrances.lua.
-- Area ids: Ironforge 1537, Tirisfal 85, Wetlands 11, Alterac 36, Stranglethorn 33,
-- Riverglades 16591 (a new Forever zone), Dustwallow 15, Azshara 16, Un'Goro 490.
for entry, area in pairs({ hot = 1537, rol = 85, exw = 11, dal = 36, dc = 33, kds = 16591, alc = 15, bmh = 16, sht = 490 }) do
    ns.SetEntrance(entry, { area = area })
end
