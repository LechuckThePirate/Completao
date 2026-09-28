local _, ns = ...

-- Entradas (una mazmorra, una zona, una clase...) y sus quests. Los archivos de Data/ las registran al
-- cargar: ns.RegisterEntry, ns.AddQuests, ns.SetEntrance; Data/Overrides.lua corrige con ns.PatchQuest.
ns.entries = {}
ns.entryList = {}

-- Secciones del panel izquierdo, en orden. Para anadir una: anadirla aqui y registrar
-- entradas con category = "<id>".
ns.categories = {
    { id = "dungeons", name = ns.L["Dungeons"], sortByLevel = true },
    { id = "raids",    name = ns.L["Raids"], sortByLevel = true },
    { id = "zones",    name = ns.L["Zones"] },
    { id = "classes",  name = ns.L["Class Quests"] },
    { id = "professions", name = ns.L["Professions"] },
    { id = "races",    name = ns.L["Races"] },
}

-- Nombre a mostrar de una entrada: las clases y zonas usan el nombre que da el cliente (su idioma).
function ns.EntryName(d)
    if d.classFile and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[d.classFile] then
        return LOCALIZED_CLASS_NAMES_MALE[d.classFile]
    end
    if d.category == "zones" and d.area and C_Map and C_Map.GetAreaInfo then
        return C_Map.GetAreaInfo(d.area) or d.name
    end
    if d.skillLine and C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName then
        local ok, name = pcall(C_TradeSkillUI.GetTradeSkillDisplayName, d.skillLine)
        if ok and name and name ~= "" then return name end
    end
    if d.raceId and C_CreatureInfo and C_CreatureInfo.GetRaceInfo then
        local info = C_CreatureInfo.GetRaceInfo(d.raceId)
        if info and info.raceName then return info.raceName end
    end
    return d.name
end

-- Esquema de una entrada (mazmorra, raid...):
-- { id = "deadmines", name = "...", category = "dungeons" (por defecto), minLevel = 15, maxLevel = 20,
--   quests = { { id = 123, name = "fallback", level = 17, minLevel = 15,
--                requires = { 122 }, faction = "Alliance"|"Horde"|nil,
--                giver = "NPC (zona)", note = "texto libre" }, ... } }
function ns.RegisterEntry(d)
    d.quests = d.quests or {}
    d.category = d.category or "dungeons"
    ns.entries[d.id] = d
    ns.entryList[#ns.entryList + 1] = d
end

-- Una misma quest puede estar en varias entradas (p.ej. en su zona y en la mazmorra): se guardan
-- todas las copias por id para poder buscarla rapido y corregirlas juntas.
local copies = {}

function ns.AddQuests(entryId, list)
    local e = ns.entries[entryId]
    if not e then return end
    for _, q in ipairs(list) do
        q.entryId = q.entryId or entryId
        e.quests[#e.quests + 1] = q
        local c = copies[q.id]
        if c then c[#c + 1] = q else copies[q.id] = { q } end
    end
end

-- Donde esta la puerta de la instancia: { area = <AreaTable id>, x = , y = } (x, y opcionales).
function ns.SetEntrance(entryId, loc)
    local e = ns.entries[entryId]
    if e then e.entrance = loc end
end

-- Correcciones a mano sobre datos generados (Data/Overrides.lua): ns.PatchQuest(id, { requires = {...} }).
-- Un valor false borra el campo.
function ns.PatchQuest(id, fields)
    for _, q in ipairs(copies[id] or {}) do
        for k, v in pairs(fields) do
            q[k] = (v ~= false) and v or nil
        end
    end
end

function ns.FindQuestDef(id)
    local c = copies[id]
    return c and c[1]
end

-- Progreso de una entrada: quests hechas / quests que ve el personaje.
function ns.EntryProgress(d)
    local done, total = 0, 0
    for _, q in ipairs(d.quests) do
        if ns.QuestVisible(q, d) then
            total = total + 1
            if C_QuestLog.IsQuestFlaggedCompleted(q.id) then
                done = done + 1
            end
        end
    end
    return done, total
end
