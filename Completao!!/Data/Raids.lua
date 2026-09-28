local _, ns = ...

-- Raids confirmadas de Forever: primer desbloqueo el 9-dic-2026 (fuente: classicwow.gg/forever/raids).
-- Roadmap: primavera 2027 (1 raid de 10 + 1 de 20), verano 2027 (una raid iconica renovada + otra nueva);
-- aun sin nombres. Quests vacias a proposito: no se inventan IDs.
local raids = {
    { id = "bd",   name = "Barrow Deeps",     minLevel = 60, maxLevel = 60, size = 10, new = true },
    { id = "hs",   name = "Hyjal Summit",     minLevel = 60, maxLevel = 60, size = 20, new = true },
    { id = "ony",  name = "Onyxia's Lair",    minLevel = 60, maxLevel = 60, size = 40 },
}

for _, r in ipairs(raids) do
    r.category = "raids"
    ns.RegisterEntry(r)
end

-- Hyjal Summit: Mount Hyjal (area 616). Barrow Deeps tiene varias entradas y no se marca ninguna.
-- La de Onyxia's Lair se genera en Data/Generated/Entrances.lua.
ns.SetEntrance("hs", { area = 616 })
