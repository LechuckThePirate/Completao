local _, ns = ...

-- Classic raids, shared by the clients that have them. Their quests and entrances are generated per client
-- (Data/<Flavor>/Generated/).
local raids = {
    { id = "ony",  name = "Onyxia's Lair", nameArea = 2159,    minLevel = 60, maxLevel = 60, size = 40 },
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

