local _, ns = ...

-- Classic dungeons, shared by the clients that have them (approximate levels, not checked against every client).
-- Quests are empty on purpose: no IDs are invented. They are filled with verified data
-- (e.g. exported from Questie's database or captured with /completao dump).
-- `nameArea`: the instance's AreaTable id, so its name follows the client's language (the ones without it are
-- translated in Localization/ by their English name: the game's name differs or the instance is new).
local dungeons = {
    { id = "rfc",  name = "Ragefire Chasm", nameArea = 2437,       minLevel = 13, maxLevel = 18 },
    { id = "wc",   name = "Wailing Caverns", nameArea = 718,      minLevel = 15, maxLevel = 25 },
    { id = "vc",   name = "The Deadmines", nameArea = 1581,        minLevel = 15, maxLevel = 20 },
    { id = "sfk",  name = "Shadowfang Keep", nameArea = 209,      minLevel = 18, maxLevel = 25 },
    { id = "bfd",  name = "Blackfathom Deeps", nameArea = 719,    minLevel = 20, maxLevel = 30 },
    { id = "stk",  name = "The Stockade", nameArea = 717,         minLevel = 22, maxLevel = 30 },
    { id = "gnom", name = "Gnomeregan", nameArea = 721,           minLevel = 24, maxLevel = 33 },
    { id = "rfk",  name = "Razorfen Kraul", nameArea = 491,       minLevel = 25, maxLevel = 35 },
    { id = "sm",   name = "Scarlet Monastery", nameArea = 796,    minLevel = 28, maxLevel = 45 },
    { id = "rfd",  name = "Razorfen Downs", nameArea = 722,       minLevel = 35, maxLevel = 45 },
    { id = "ulda", name = "Uldaman", nameArea = 1337,              minLevel = 35, maxLevel = 47 },
    { id = "zf",   name = "Zul'Farrak", nameArea = 1176,           minLevel = 42, maxLevel = 50 },
    { id = "mara", name = "Maraudon", nameArea = 2100,             minLevel = 40, maxLevel = 52 },
    { id = "st",   name = "The Temple of Atal'Hakkar", minLevel = 45, maxLevel = 55 },
    { id = "brd",  name = "Blackrock Depths", nameArea = 1584,     minLevel = 52, maxLevel = 60 },
    { id = "lbrs", name = "Lower Blackrock Spire", minLevel = 55, maxLevel = 60 },
    { id = "dm",   name = "Dire Maul", nameArea = 2557,            minLevel = 55, maxLevel = 60 },
    { id = "scho", name = "Scholomance", nameArea = 2057,          minLevel = 58, maxLevel = 60 },
    { id = "strat", name = "Stratholme", nameArea = 2017,          minLevel = 58, maxLevel = 60 },
    { id = "dt",   name = "Deeprun Tram", nameArea = 2257,         minLevel = 1,  maxLevel = 60 },
}

-- The game's instance ids (GetInstanceInfo), to tell which instance the player is in; the entries without one
-- are matched by name.
local instanceIds = {
    rfc = 389, wc = 43, vc = 36, sfk = 33, bfd = 48, stk = 34, gnom = 90, rfk = 47, sm = 189, rfd = 129, ulda = 70,
    zf = 209, mara = 349, st = 109, brd = 230, lbrs = 229, dm = 429, scho = 289, strat = 329, dt = 369,
}

for _, d in ipairs(dungeons) do
    d.instanceId = instanceIds[d.id]
    ns.RegisterEntry(d)
end
