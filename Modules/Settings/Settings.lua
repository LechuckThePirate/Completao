local _, ns = ...

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

-- Al cargar el addon (ADDON_LOADED): prepara las variables guardadas y ns.db / ns.char.
function ns.InitSettings()
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
