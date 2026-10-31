local _, ns = ...

-- The Burning Crusade battleground. `area` is its AreaTable id, so the name follows the client's language. Its
-- quests come from Questie's database (Data/TBC/Generated/Classic.lua).
ns.RegisterEntry({ id = "eots", name = "Eye of the Storm", category = "battlegrounds", area = 3820, minLevel = 61, maxLevel = 70, size = 15 })
