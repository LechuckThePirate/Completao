local _, ns = ...

-- Classic battlegrounds. `area` is the battleground's AreaTable id, so the name follows the client's
-- language; the level range is the lowest level that can enter. Their quests (honor and mark turn-ins,
-- supplies) come from Questie's Forever database (Data/Generated/Classic.lua).
local battlegrounds = {
    { id = "av",  name = "Alterac Valley", area = 2597, minLevel = 51, maxLevel = 60, size = 40 },
    { id = "wsg", name = "Warsong Gulch",  area = 3277, minLevel = 10, maxLevel = 60, size = 10 },
    { id = "ab",  name = "Arathi Basin",   area = 3358, minLevel = 20, maxLevel = 60, size = 15 },
}

for _, b in ipairs(battlegrounds) do
    b.category = "battlegrounds"
    ns.RegisterEntry(b)
end
