local _, ns = ...

-- Estado de una quest para el personaje: titulo, hecha / en curso / disponible / bloqueada, bajo o
-- demasiado alto nivel, si es para el (clase, raza, faccion) y su descripcion larga.

-- Titulo en el idioma del cliente. Los pasos de una cadena que se llaman igual van numerados en los datos
-- ("Hidden Enemies (3/5)"): el numero se conserva tambien con el titulo del juego, que no lo lleva.
function ns.QuestTitle(id, fallback)
    local title = C_QuestLog.GetTitleForQuestID(id)
    if title and title ~= "" then
        local step = fallback and fallback:match(" %(%d+/%d+%)$")
        if step and not title:find(step, 1, true) then title = title .. step end
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

-- "Demasiado alto": aun no puede cogerla (el nivel minimo supera el del jugador) o el juego la pinta en rojo
-- en el registro (demasiado dificil para su nivel). Lo segundo pilla las de nivel minimo bajo y nivel alto,
-- como "Master Angler" (nivel 60, se coge desde el 1). Se le pregunta al juego por el color, como en
-- IsLowLevel; si no lo da, rojo es 5 niveles o mas por encima.
function ns.IsTooHigh(q)
    local player = UnitLevel("player")
    if (q.minLevel or 0) > player then return true end
    if not q.level then return false end
    if GetQuestDifficultyColor then
        local ok, c = pcall(GetQuestDifficultyColor, q.level)
        if ok and type(c) == "table" then
            local red = QuestDifficultyColors and QuestDifficultyColors["impossible"]
            return c == red or (c.r == 1 and c.g < 0.2 and c.b < 0.2)
        end
    end
    return q.level >= player + 5
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

-- Descripcion larga de una quest. El cliente no da el texto de una quest cualquiera por su id, solo el de
-- las que llevas en el registro: para esas se lee en vivo (en el idioma del cliente) y para las demas se usa
-- el texto de los datos del addon, si lo hay. No se guarda nada en las variables guardadas.
-- El texto del registro es el de la quest seleccionada: se selecciona, se lee y se deja la seleccion como
-- estaba. Se recuerda solo en memoria y una vez por quest y sesion, para no tocar la seleccion en cada
-- refresco de la ventana.
local fromLog = {}
local function readFromLog(id)
    if fromLog[id] ~= nil then return fromLog[id] end
    fromLog[id] = false
    local getSel, setSel = C_QuestLog.GetSelectedQuest, C_QuestLog.SetSelectedQuest
    if not (getSel and setSel and GetQuestLogQuestText) then return false end
    local previous = getSel()
    local ok, text = pcall(function()
        setSel(id)
        if getSel() ~= id then return nil end
        local index = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id)
        return (GetQuestLogQuestText(index))
    end)
    if previous ~= id then pcall(setSel, previous or 0) end
    if ok and type(text) == "string" and strtrim(text) ~= "" then fromLog[id] = text end
    return fromLog[id]
end

function ns.QuestDescription(q)
    local text = C_QuestLog.IsOnQuest(q.id) and readFromLog(q.id) or nil
    text = text or q.desc or (ns.DESC and ns.DESC[q.id])
    if not text then return nil end
    local name = (UnitName("player") or ""):gsub("%%", "%%%%")
    return (text:gsub("%$[Nn]", name))
end
