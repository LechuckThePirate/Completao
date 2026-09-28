local ADDON, ns = ...

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

-- Coloca controles en filas, de izquierda a derecha, dentro de `width`: cuando uno no cabe, pasa a la fila
-- siguiente. Se vuelve a llamar al cambiar el tamaño, asi nada se sale ni queda tapado. items: { frame = ,
-- w = ancho o funcion que lo da, h = alto (por defecto el del frame), dy = ajuste vertical }. Con
-- skipHidden no cuenta los ocultos; con fromBottom, (x0, y0) es la esquina inferior izquierda y las filas
-- se apilan hacia arriba (la primera, arriba del todo). Devuelve el alto ocupado.
function ns.FlowLayout(parent, items, x0, y0, width, gapX, gapY, skipHidden, fromBottom)
    local placed, x, y, rowH = {}, 0, 0, 0
    for _, it in ipairs(items) do
        if not (skipHidden and not it.frame:IsShown()) then
            local w = type(it.w) == "function" and it.w() or it.w
            local h = it.h or it.frame:GetHeight()
            if x > 0 and x + w > width then
                x, y, rowH = 0, y + rowH + gapY, 0
            end
            placed[#placed + 1] = { it = it, x = x, y = y, h = h }
            x = x + w + gapX
            rowH = math.max(rowH, h)
        end
    end
    local total = #placed > 0 and (y + rowH) or 0
    for _, p in ipairs(placed) do
        local f = p.it.frame
        f:ClearAllPoints()
        if fromBottom then
            f:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x0 + p.x, y0 + total - p.y - p.h - (p.it.dy or 0))
        else
            f:SetPoint("TOPLEFT", parent, "TOPLEFT", x0 + p.x, -(y0 + p.y + (p.it.dy or 0)))
        end
    end
    return total
end

-- Ancho de una casilla con su texto (para FlowLayout).
function ns.CheckWidth(cb, label)
    return function() return 24 + math.ceil(label:GetStringWidth()) + 4 end
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

-- Pasos de una quest, para los waypoints y la lista del panel: el requisito que falte (el inicio de la quest
-- previa sin hacer), el inicio, un paso por objetivo (q.steps: zona y punto de los datos) y la entrega.
-- Con la quest en el registro, cada objetivo lleva su progreso en directo (se casa por nombre con los
-- objetivos del juego y, si no, por orden); los objetivos del juego sin paso en los datos se anaden sin sitio.
-- Devuelve la lista y el indice del paso que toca ahora. Paso: { kind = "req"|"start"|"obj"|"finish",
-- label, loc = { npc, area, x, y } o nil, done, progress = "3/10", current }.
local function readyForTurnIn(id)
    if C_QuestLog.ReadyForTurnIn then return C_QuestLog.ReadyForTurnIn(id) end
    if C_QuestLog.IsComplete then return C_QuestLog.IsComplete(id) end
    return false
end

function ns.QuestSteps(q)
    local L = ns.L
    local list = {}
    local completed = C_QuestLog.IsQuestFlaggedCompleted(q.id)
    local onQuest = not completed and C_QuestLog.IsOnQuest(q.id)

    if not completed and not onQuest then
        for _, id in ipairs(q.requires or {}) do
            if not C_QuestLog.IsQuestFlaggedCompleted(id) then
                local def = ns.FindQuestDef(id)
                list[#list + 1] = { kind = "req", loc = def and def.start,
                    label = L["Requirement: %s"]:format(ns.QuestTitle(id, def and def.name)) }
                break
            end
        end
    end
    list[#list + 1] = { kind = "start", loc = q.start, done = completed or onQuest,
        label = L["Start: %s"]:format(q.start and q.start.npc or q.giver or "?") }

    local objectives = onQuest and C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(q.id) or {}
    local used = {}
    local function progressOf(o)
        if o.numRequired and o.numRequired > 0 then return ("%d/%d"):format(o.numFulfilled or 0, o.numRequired) end
    end
    for i, s in ipairs(q.steps or {}) do
        local step = { kind = "obj", label = s.name, loc = s.x and s or nil, area = s.area }
        local match
        for j, o in ipairs(objectives) do
            if not used[j] and o.text and o.text:lower():find(s.name:lower(), 1, true) then match = j break end
        end
        if not match and objectives[i] and not used[i] then match = i end
        if match then
            used[match] = true
            step.done = objectives[match].finished
            step.progress = progressOf(objectives[match])
        end
        list[#list + 1] = step
    end
    for j, o in ipairs(objectives) do
        if not used[j] and o.text and o.text ~= "" then
            list[#list + 1] = { kind = "obj", label = (o.text:gsub(":%s*%d+%s*/%s*%d+%s*$", "")), done = o.finished,
                progress = progressOf(o) }
        end
    end
    if completed then
        for _, s in ipairs(list) do if s.kind == "obj" then s.done = true end end
    end
    list[#list + 1] = { kind = "finish", loc = q.finish, done = completed,
        label = L["Turn in: %s"]:format(q.finish and q.finish.npc or "?") }

    -- el que toca: sin empezar, el requisito que falte o el inicio; en curso, el primer objetivo sin
    -- terminar (mejor si tiene sitio) o la entrega si ya esta lista; hecha, la entrega
    local current
    if completed then
        current = #list
    elseif onQuest then
        if readyForTurnIn(q.id) then
            current = #list
        else
            for i, s in ipairs(list) do
                if s.kind == "obj" and not s.done and (s.loc or s.area) then current = i break end
            end
            if not current then
                for i, s in ipairs(list) do
                    if s.kind == "obj" and not s.done then current = i break end
                end
            end
            current = current or #list
        end
    else
        current = 1
    end
    list[current].current = true
    return list, current
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

function ns.Version()
    local getMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    return getMeta and getMeta(ADDON, "Version") or "?"
end

-- Aviso en el chat, como Embolsao: "Completao!! vX -- initializing..." al cargar el addon y
-- "... initialization complete" cuando el jugador ya esta en el mundo con los datos indexados.
local function announce(text)
    if ns.char and ns.char.quiet then return end -- Preferencias: mensajes del chat desactivados
    print(("|cff33ff99Completao!!|r v%s -- %s"):format(ns.Version(), text))
end

local announcedReady = false
local function announceReady()
    if announcedReady then return end
    announcedReady = true
    local quests = 0
    for _, d in ipairs(ns.entryList) do quests = quests + #d.quests end
    announce(ns.L["initialization complete (%d quests)"]:format(quests))
end

-- Preferencias por personaje o para toda la cuenta, como en Embolsao ("Preferencias de este personaje").
-- Estas claves se leen y escriben en el almacen activo: el del personaje (CompletaoCharDB) o el comun de
-- la cuenta (CompletaoDB.shared). Lo demas de ns.char (entrada seleccionada, seccion abierta) es siempre
-- del personaje. El resto del addon usa ns.char sin saber cual de los dos hay detras.
local SWITCHABLE = {
    fadeAlpha = true, quiet = true, minimap = true, filters = true, zoom = true, window = true, openWithQuestLog = true,
}

local function deepCopy(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do copy[k] = deepCopy(v) end
    return copy
end

local function activeStore()
    return CompletaoCharDB.perCharacter and CompletaoCharDB or CompletaoDB.shared
end

local function initSettings()
    CompletaoDB = CompletaoDB or {}
    CompletaoCharDB = CompletaoCharDB or {}
    ns.db = CompletaoDB
    ns.db.descriptions = nil -- textos guardados por una version de desarrollo; ya no se guardan
    -- la primera vez, los ajustes comunes salen del personaje que los estrena
    if not CompletaoDB.shared then
        CompletaoDB.shared = {}
        for key in pairs(SWITCHABLE) do CompletaoDB.shared[key] = deepCopy(CompletaoCharDB[key]) end
    end
    -- por defecto, por personaje (como hasta ahora); uno nuevo empieza con una copia de los comunes
    if CompletaoCharDB.perCharacter == nil then
        for key in pairs(SWITCHABLE) do
            if CompletaoCharDB[key] == nil then CompletaoCharDB[key] = deepCopy(CompletaoDB.shared[key]) end
        end
        CompletaoCharDB.perCharacter = true
    end
    ns.char = setmetatable({}, {
        __index = function(_, key)
            if SWITCHABLE[key] then return activeStore()[key] end
            return CompletaoCharDB[key]
        end,
        __newindex = function(_, key, value)
            if SWITCHABLE[key] then activeStore()[key] = value else CompletaoCharDB[key] = value end
        end,
    })
    ns.char.filters = ns.char.filters or {}
end

function ns.IsPerCharacter()
    return CompletaoCharDB.perCharacter and true or false
end

-- Al pasar a "por personaje" se copia lo comun, para que el cambio no se note; al volver a lo comun, la
-- copia del personaje se queda guardada sin usar. Despues se aplica lo que haya en el almacen nuevo.
function ns.SetPerCharacter(enabled)
    enabled = enabled and true or false
    if enabled == ns.IsPerCharacter() then return end
    if enabled then
        for key in pairs(SWITCHABLE) do CompletaoCharDB[key] = deepCopy(CompletaoDB.shared[key]) end
    end
    CompletaoCharDB.perCharacter = enabled
    ns.char.filters = ns.char.filters or {}
    ns.Minimap_Init()
    ns.UI_ApplySettings()
end

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterEvent("QUEST_TURNED_IN")
events:RegisterEvent("QUEST_DATA_LOAD_RESULT")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        initSettings()
        announce(ns.L["initializing..."])
        ns.Minimap_Init()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- tambien salta tras /reload; se avisa una sola vez por carga de la interfaz
        C_Timer.After(1, announceReady)
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

-- Atajos de teclado (Bindings.xml): salen en Opciones -> Atajos de teclado, en su propia seccion
-- "Completao!!" (como Questie).
BINDING_NAME_COMPLETAO_TOGGLE = ns.L["Open / close the window"]
BINDING_NAME_COMPLETAO_PREFS = ns.L["Open / close the preferences"]
function Completao_Toggle() ns.UI_Toggle() end
function Completao_TogglePreferences() ns.Prefs_Toggle() end

SLASH_COMPLETAO1 = "/completao"
SLASH_COMPLETAO2 = "/cpl"
SlashCmdList.COMPLETAO = function(msg)
    msg = strtrim((msg or ""):lower())
    if msg == "dump" then
        dumpQuestLog()
    elseif msg == "prefs" or msg == "options" or msg == "config" then
        ns.Prefs_Toggle()
    elseif msg == "minimap" then
        ns.Minimap_Toggle()
    elseif msg:match("^fade") then
        local percent = tonumber(msg:match("^fade%s+(%d+)"))
        if percent then ns.char.fadeAlpha = math.max(0.1, math.min(1, percent / 100)) end
        ns.Print(ns.L["Opacity while moving: %d%%"]:format(math.floor((ns.char.fadeAlpha or 0.5) * 100 + 0.5)))
    elseif msg == "" then
        ns.UI_Toggle()
    else
        ns.Print(ns.L["Usage: /completao (open) | prefs | minimap | fade <10-100> | dump"])
    end
end
