local _, ns = ...

-- Mazmorras de Classic (niveles orientativos, sin verificar contra Forever) + las 9 nuevas de
-- Forever (new = true; niveles de classicwow.gg/forever/dungeons, otras webs discrepan en algunas).
-- Las quests estan vacias a proposito: no se inventan IDs. Se rellenan con datos verificados
-- (p.ej. exportados de la base de datos de Questie o capturados con /completao dump).
local dungeons = {
    { id = "hot",  name = "The Hall of Thanes",       minLevel = 13, maxLevel = 18, new = true },
    { id = "rol",  name = "Ruins of Lordaeron",       minLevel = 15, maxLevel = 20, new = true },
    { id = "exw",  name = "Excavation Site: Wetlands", minLevel = 24, maxLevel = 29, new = true },
    { id = "dal",  name = "City of Dalaran",          minLevel = 28, maxLevel = 33, new = true },
    { id = "dc",   name = "The Drowned City",         minLevel = 35, maxLevel = 40, new = true },
    { id = "kds",  name = "Krol'dok Stronghold",      minLevel = 40, maxLevel = 45, new = true },
    { id = "alc",  name = "Alcaz Prison",             minLevel = 48, maxLevel = 53, new = true },
    { id = "bmh",  name = "Blackmaw Hold",            minLevel = 55, maxLevel = 60, new = true },
    { id = "sht",  name = "Shaper's Terrace",         minLevel = 58, maxLevel = 60, new = true },

    { id = "rfc",  name = "Ragefire Chasm",       minLevel = 13, maxLevel = 18 },
    { id = "wc",   name = "Wailing Caverns",      minLevel = 15, maxLevel = 25 },
    { id = "vc",   name = "The Deadmines",        minLevel = 15, maxLevel = 20 },
    { id = "sfk",  name = "Shadowfang Keep",      minLevel = 18, maxLevel = 25 },
    { id = "bfd",  name = "Blackfathom Deeps",    minLevel = 20, maxLevel = 30 },
    { id = "stk",  name = "The Stockade",         minLevel = 22, maxLevel = 30 },
    { id = "gnom", name = "Gnomeregan",           minLevel = 24, maxLevel = 33 },
    { id = "rfk",  name = "Razorfen Kraul",       minLevel = 25, maxLevel = 35 },
    { id = "sm",   name = "Scarlet Monastery",    minLevel = 28, maxLevel = 45 },
    { id = "rfd",  name = "Razorfen Downs",       minLevel = 35, maxLevel = 45 },
    { id = "ulda", name = "Uldaman",              minLevel = 35, maxLevel = 47 },
    { id = "zf",   name = "Zul'Farrak",           minLevel = 42, maxLevel = 50 },
    { id = "mara", name = "Maraudon",             minLevel = 40, maxLevel = 52 },
    { id = "st",   name = "The Temple of Atal'Hakkar", minLevel = 45, maxLevel = 55 },
    { id = "brd",  name = "Blackrock Depths",     minLevel = 52, maxLevel = 60 },
    { id = "lbrs", name = "Lower Blackrock Spire", minLevel = 55, maxLevel = 60 },
    { id = "dm",   name = "Dire Maul",            minLevel = 55, maxLevel = 60 },
    { id = "scho", name = "Scholomance",          minLevel = 58, maxLevel = 60 },
    { id = "strat", name = "Stratholme",          minLevel = 58, maxLevel = 60 },
}

for _, d in ipairs(dungeons) do
    ns.RegisterEntry(d)
end

-- Zona donde esta la entrada de las mazmorras nuevas de Forever (sin coordenadas exactas todavia;
-- fuente: classicwow.gg/forever/dungeons). Las de Classic se generan en Data/Generated/Entrances.lua.
-- Ids de area: Ironforge 1537, Tirisfal 85, Wetlands 11, Alterac 36, Stranglethorn 33,
-- Riverglades 16591 (zona nueva de Forever), Dustwallow 15, Azshara 16, Un'Goro 490.
for entry, area in pairs({ hot = 1537, rol = 85, exw = 11, dal = 36, dc = 33, kds = 16591, alc = 15, bmh = 16, sht = 490 }) do
    ns.SetEntrance(entry, { area = area })
end
