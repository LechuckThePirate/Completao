local _, ns = ...

-- The Burning Crusade raids. Their quests and entrances are generated (Data/TBC/Generated/); the classic raids are
-- in Data/Classic/Raids.lua.
local raids = {
    { id = "kara",  name = "Karazhan", nameArea = 3457,             minLevel = 70, maxLevel = 70, size = 10 },
    { id = "za",    name = "Zul'Aman", nameArea = 3805,             minLevel = 70, maxLevel = 70, size = 10 },
    { id = "gruul", name = "Gruul's Lair", nameArea = 3923,         minLevel = 70, maxLevel = 70, size = 25 },
    { id = "mag",   name = "Magtheridon's Lair", nameArea = 3836,   minLevel = 70, maxLevel = 70, size = 25 },
    { id = "ssc",   name = "Serpentshrine Cavern", nameArea = 3607, minLevel = 70, maxLevel = 70, size = 25 },
    { id = "tk",    name = "Tempest Keep", nameArea = 3845,         minLevel = 70, maxLevel = 70, size = 25 },
    { id = "hyjal", name = "Hyjal Summit", nameArea = 3606,         minLevel = 70, maxLevel = 70, size = 25 },
    { id = "bt",    name = "Black Temple", nameArea = 3959,         minLevel = 70, maxLevel = 70, size = 25 },
    { id = "swp",   name = "Sunwell Plateau", nameArea = 4075,      minLevel = 70, maxLevel = 70, size = 25 },
}

-- The game's instance ids (GetInstanceInfo).
local instanceIds = { kara = 532, za = 568, gruul = 565, mag = 544, ssc = 548, tk = 550, hyjal = 534, bt = 564, swp = 580 }

for _, r in ipairs(raids) do
    r.category = "raids"
    r.instanceId = instanceIds[r.id]
    ns.RegisterEntry(r)
end
