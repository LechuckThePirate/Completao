local _, ns = ...

-- The Burning Crusade dungeons (approximate levels, not checked against the client). Quests are empty on purpose:
-- the generated ones are in Data/TBC/Generated/. `nameArea`: the instance's AreaTable id, so its name follows
-- the client's language. The classic dungeons are in Data/Classic/Dungeons.lua.
local dungeons = {
    { id = "hfr",  name = "Hellfire Ramparts", nameArea = 3562,        minLevel = 60, maxLevel = 62 },
    { id = "bf",   name = "The Blood Furnace", nameArea = 3713,        minLevel = 61, maxLevel = 63 },
    { id = "sp",   name = "The Slave Pens", nameArea = 3717,           minLevel = 62, maxLevel = 64 },
    { id = "ub",   name = "The Underbog", nameArea = 3716,             minLevel = 63, maxLevel = 65 },
    { id = "mt",   name = "Mana-Tombs", nameArea = 3792,               minLevel = 64, maxLevel = 66 },
    { id = "ac",   name = "Auchenai Crypts", nameArea = 3790,          minLevel = 65, maxLevel = 67 },
    { id = "oh",   name = "Old Hillsbrad Foothills", nameArea = 2367,  minLevel = 66, maxLevel = 68 },
    { id = "seth", name = "Sethekk Halls", nameArea = 3791,           minLevel = 67, maxLevel = 69 },
    { id = "sl",   name = "Shadow Labyrinth", nameArea = 3789,         minLevel = 70, maxLevel = 70 },
    { id = "bm",   name = "The Black Morass", nameArea = 2366,         minLevel = 69, maxLevel = 70 },
    { id = "mech", name = "The Mechanar", nameArea = 3849,             minLevel = 70, maxLevel = 70 },
    { id = "bot",  name = "The Botanica", nameArea = 3847,             minLevel = 70, maxLevel = 70 },
    { id = "arc",  name = "The Arcatraz", nameArea = 3848,             minLevel = 70, maxLevel = 70 },
    { id = "sh",   name = "The Shattered Halls", nameArea = 3714,      minLevel = 70, maxLevel = 70 },
    { id = "sv",   name = "The Steamvault", nameArea = 3715,           minLevel = 70, maxLevel = 70 },
    { id = "mgt",  name = "Magisters' Terrace", nameArea = 4131,       minLevel = 70, maxLevel = 70 },
}

-- The game's instance ids (GetInstanceInfo), to tell which instance the player is in.
local instanceIds = {
    hfr = 543, bf = 542, sp = 547, ub = 546, mt = 557, ac = 558, oh = 560, seth = 556, sl = 555, bm = 269,
    mech = 554, bot = 553, arc = 552, sh = 540, sv = 545, mgt = 585,
}

for _, d in ipairs(dungeons) do
    d.instanceId = instanceIds[d.id]
    ns.RegisterEntry(d)
end
