local _, ns = ...

-- Datos sinteticos para probar el layout del arbol. Se activan con /completao demo + /reload.
-- Los IDs son inventados a proposito (900001+) y nunca aparecen como completados.
local function q(id, name, requires, extra)
    local t = { id = id, name = name, requires = requires, level = 20, minLevel = 15 }
    for k, v in pairs(extra or {}) do t[k] = v end
    return t
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, _, addon)
    if addon ~= "Completao!!" then return end
    self:UnregisterAllEvents()
    if not (CompletaoDB and CompletaoDB.demo) then return end

    local L = ns.L
    ns.RegisterEntry({
        id = "_demo", name = L["[Demo] Test chain"], minLevel = 15, maxLevel = 25,
        quests = {
            q(900001, L["Chain start"], nil, { giver = L["Test NPC"] }),
            q(900002, L["Second part"], { 900001 }),
            q(900003, L["Branch A"], { 900002 }),
            q(900004, L["Branch B"], { 900002 }),
            q(900005, L["Alliance-only branch"], { 900002 }, { faction = "Alliance" }),
            q(900006, L["Final (needs A and B)"], { 900003, 900004 }, { note = L["Turn in inside the dungeon."] }),
            q(900010, L["Loose quest"], nil, { minLevel = 60 }),
        },
    })
end)
