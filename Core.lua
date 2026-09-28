local ADDON, ns = ...

ns.entries = {}
ns.entryList = {}

-- Secciones del panel izquierdo, en orden. Para anadir una: anadirla aqui y registrar
-- entradas con category = "<id>".
ns.categories = {
    { id = "dungeons", name = ns.L["Dungeons"] },
    { id = "raids",    name = ns.L["Raids"] },
    { id = "zones",    name = ns.L["Zones"] },
    { id = "classes",  name = ns.L["Class Quests"] },
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
    if d.raceId and C_CreatureInfo and C_CreatureInfo.GetRaceInfo then
        local info = C_CreatureInfo.GetRaceInfo(d.raceId)
        if info and info.raceName then return info.raceName end
    end
    return d.name
end

function ns.Print(...)
    print("|cff33ff99Completao!!|r:", ...)
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

function ns.QuestTitle(id, fallback)
    local title = C_QuestLog.GetTitleForQuestID(id)
    if title and title ~= "" then
        return title
    end
    C_QuestLog.RequestLoadQuestByID(id)
    return fallback or ("Quest " .. id)
end

-- Devuelve "done" | "active" | "available" | "locked", y una lista de razones si esta bloqueada.
function ns.QuestStatus(q)
    if C_QuestLog.IsQuestFlaggedCompleted(q.id) then
        return "done"
    end
    if C_QuestLog.IsOnQuest(q.id) then
        return "active"
    end

    local reasons = {}
    if q.minLevel and UnitLevel("player") < q.minLevel then
        reasons[#reasons + 1] = ns.L["Requires level %d (you are %d)"]:format(q.minLevel, UnitLevel("player"))
    end
    for _, reqId in ipairs(q.requires or {}) do
        if not C_QuestLog.IsQuestFlaggedCompleted(reqId) then
            local def = ns.FindQuestDef(reqId)
            reasons[#reasons + 1] = ns.L["Requires: "] .. ns.QuestTitle(reqId, def and def.name)
        end
    end
    if q.requiresAny and #q.requiresAny > 0 then
        local names, anyDone = {}, false
        for _, reqId in ipairs(q.requiresAny) do
            if C_QuestLog.IsQuestFlaggedCompleted(reqId) then anyDone = true break end
            local def = ns.FindQuestDef(reqId)
            names[#names + 1] = ns.QuestTitle(reqId, def and def.name)
        end
        if not anyDone then
            reasons[#reasons + 1] = ns.L["Requires one of: "] .. table.concat(names, " / ")
        end
    end
    if #reasons > 0 then
        return "locked", reasons
    end
    return "available"
end

function ns.FindQuestDef(id)
    local c = copies[id]
    return c and c[1]
end

-- "Bajo nivel": el titulo de la quest saldria en gris para este personaje (trivial). Se le pregunta al
-- propio juego por el color de dificultad; si no lo da, se usa el rango verde del cliente.
function ns.IsLowLevel(q)
    local questLevel = q.level or q.minLevel
    if not questLevel then return false end
    if GetQuestDifficultyColor then
        local ok, c = pcall(GetQuestDifficultyColor, questLevel)
        if ok and type(c) == "table" then
            local trivial = QuestDifficultyColors and QuestDifficultyColors["trivial"]
            return c == trivial or (c.r == 0.5 and c.g == 0.5 and c.b == 0.5)
        end
    end
    local player = UnitLevel("player")
    local green = (GetQuestGreenRange and GetQuestGreenRange()) or (3 + math.floor(player / 10))
    return questLevel <= player - green
end

-- "Demasiado alto": el nivel minimo de la quest supera el del jugador (aun no puede cogerla).
function ns.IsTooHigh(q)
    return (q.minLevel or 0) > UnitLevel("player")
end

-- Mascaras de razas y de clases: un bit por raza/clase (razas: 1 humano, 2 orco, 4 enano, 8 elfo de la
-- noche, 16 no-muerto, 32 tauren, 64 gnomo, 128 trol; clases: 1 guerrero, 2 paladin, 4 cazador, 8 picaro,
-- 16 sacerdote, 64 chaman, 128 mago, 256 brujo, 1024 druida). El id de raza o clase del cliente es el
-- numero de bit + 1.
local function hasBit(mask, id)
    return math.floor(mask / 2 ^ (id - 1)) % 2 == 1
end

local ALLIANCE_RACE_BITS = { [1] = true, [3] = true, [4] = true, [7] = true } -- ids de raza: humano, enano, elfo, gnomo

-- Faccion de una quest: la marcada, o la que se deduce de sus razas (todas de una misma faccion).
function ns.QuestFaction(q)
    if q.faction then return q.faction end
    if not q.races then return nil end
    local alliance, horde = false, false
    for id = 1, 8 do
        if hasBit(q.races, id) then
            if ALLIANCE_RACE_BITS[id] then alliance = true else horde = true end
        end
    end
    if alliance and not horde then return "Alliance" end
    if horde and not alliance then return "Horde" end
end

-- Lo que ve el personaje. Las quests de otra clase, raza o faccion no se ven, salvo que se mire esa clase o
-- esa raza en concreto (su entrada en el panel; `d` es la entrada que se esta mirando) o se active el filtro
-- "otra faccion", que lo permite para la faccion contraria.
local playerRaceId, playerClassId
function ns.QuestVisible(q, d)
    if q.hidden then return false end
    local category = d and d.category
    local otherFaction = ns.char and ns.char.filters and ns.char.filters.otherFaction

    if q.classes and category ~= "classes" then
        playerClassId = playerClassId or select(3, UnitClass("player"))
        if playerClassId and not hasBit(q.classes, playerClassId) then return false end
    end

    local mine = UnitFactionGroup("player")
    local faction = ns.QuestFaction(q)
    local lookingAtRace = category == "races"
    if faction and faction ~= mine and not (lookingAtRace or otherFaction) then return false end
    if q.races and not lookingAtRace then
        playerRaceId = playerRaceId or select(3, UnitRace("player"))
        if playerRaceId and not hasBit(q.races, playerRaceId) then
            -- otra raza: solo se ve si es de la faccion contraria y has pedido verla
            if not (otherFaction and faction and faction ~= mine) then return false end
        end
    end
    return true
end

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

local pending
function ns.RequestRefresh()
    if pending then return end
    pending = true
    C_Timer.After(0.2, function()
        pending = false
        if ns.UI and ns.UI:IsShown() then
            ns.UI_Refresh()
        end
    end)
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterEvent("QUEST_TURNED_IN")
events:RegisterEvent("QUEST_DATA_LOAD_RESULT")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        CompletaoDB = CompletaoDB or {}
        ns.db = CompletaoDB
        CompletaoCharDB = CompletaoCharDB or {}
        ns.char = CompletaoCharDB
        ns.char.filters = ns.char.filters or {}
        ns.Minimap_Init()
    else
        ns.RequestRefresh()
    end
end)

local function dumpQuestLog()
    ns.Print(ns.L["Quests in your log (id - title):"])
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader then
            print(ns.L["  %d - %s (level %d)"]:format(info.questID, info.title, info.level or 0))
        end
    end
end

SLASH_COMPLETAO1 = "/completao"
SLASH_COMPLETAO2 = "/cpl"
SlashCmdList.COMPLETAO = function(msg)
    msg = strtrim((msg or ""):lower())
    if msg == "dump" then
        dumpQuestLog()
    elseif msg == "minimap" then
        ns.Minimap_Toggle()
    elseif msg == "" then
        ns.UI_Toggle()
    else
        ns.Print(ns.L["Usage: /completao (open) | /completao minimap (toggle button) | /completao dump (quest log ids)"])
    end
end
