local _, ns = ...

-- Raids confirmed for Forever: first unlock on 2026-12-09 (source: classicwow.gg/forever/raids).
-- Roadmap: spring 2027 (one 10-man + one 20-man raid), summer 2027 (one revamped iconic raid + a new one);
-- still unnamed. Quests are empty on purpose: no IDs are invented.
local raids = {
    { id = "bd",   name = "Barrow Deeps",     minLevel = 60, maxLevel = 60, size = 10, new = true },
    { id = "hs",   name = "Hyjal Summit",     minLevel = 60, maxLevel = 60, size = 20, new = true },
    { id = "ony",  name = "Onyxia's Lair",    minLevel = 60, maxLevel = 60, size = 40 },
}

for _, r in ipairs(raids) do
    r.category = "raids"
    ns.RegisterEntry(r)
end

-- Hyjal Summit: Mount Hyjal (area 616). Barrow Deeps has several entrances and none is marked.
-- Onyxia's Lair's is generated in Data/Generated/Entrances.lua.
ns.SetEntrance("hs", { area = 616 })
