local _, ns = ...

-- Raids confirmed for Forever: first unlock on 2026-12-09 (source: classicwow.gg/forever/raids).
-- Roadmap: spring 2027 (one 10-man + one 20-man raid), summer 2027 (one revamped iconic raid + a new one);
-- still unnamed. Quests are empty on purpose: no IDs are invented.
local raids = {
    { id = "bd",   name = "Barrow Deeps",     minLevel = 60, maxLevel = 60, size = 10, new = true },
    { id = "hs",   name = "Hyjal Summit",     minLevel = 60, maxLevel = 60, size = 20, new = true },
    { id = "ony",  name = "Onyxia's Lair", nameArea = 2159,    minLevel = 60, maxLevel = 60, size = 40 },
    -- Classic raids: their quests and entrances come from Questie's Forever database (Data/Generated/).
    { id = "zg",   name = "Zul'Gurub", nameArea = 1977,        minLevel = 60, maxLevel = 60, size = 20 },
    { id = "aq20", name = "Ruins of Ahn'Qiraj", nameArea = 3429, minLevel = 60, maxLevel = 60, size = 20 },
    { id = "mc",   name = "Molten Core", nameArea = 2717,      minLevel = 60, maxLevel = 60, size = 40 },
    { id = "bwl",  name = "Blackwing Lair", nameArea = 2677,   minLevel = 60, maxLevel = 60, size = 40 },
    { id = "aq40", name = "Temple of Ahn'Qiraj", minLevel = 60, maxLevel = 60, size = 40 },
    { id = "naxx", name = "Naxxramas", nameArea = 3456,        minLevel = 60, maxLevel = 60, size = 40 },
}

-- The game's instance ids (GetInstanceInfo); the entries without one are matched by name.
local instanceIds = { ony = 249, zg = 309, aq20 = 509, mc = 409, bwl = 469, aq40 = 531, naxx = 533 }

for _, r in ipairs(raids) do
    r.category = "raids"
    r.instanceId = instanceIds[r.id]
    ns.RegisterEntry(r)
end

-- Hyjal Summit: Mount Hyjal (area 616). Barrow Deeps has several entrances and none is marked.
-- Onyxia's Lair's is generated in Data/Generated/Entrances.lua.
ns.SetEntrance("hs", { area = 616 })
