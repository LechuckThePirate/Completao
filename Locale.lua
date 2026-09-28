local _, ns = ...

-- Las claves son el texto en ingles; en clientes esES/esMX se sustituyen por el espanol.
local es = {
    ["initializing..."] = "inicializando...",
    ["initialization complete (%d quests)"] = "inicialización completa (%d quests)",
    ["Races"] = "Razas",
    ["Show other faction"] = "Ver otra facción",
    ["Shows the quests and zones of the opposite faction, hidden by default."] =
        "Muestra las quests y zonas de la facción contraria, ocultas por defecto.",
    ["Search by title"] = "Buscar por título",
    ["Hide low level"] = "Ocultar bajo nivel",
    ["Hide too high"] = "Ocultar muy alto",
    ["Hide completed"] = "Ocultar completadas",
    ["Hides quests that are grey for your level (trivial)."] = "Oculta las quests en gris para tu nivel (triviales).",
    ["Hides quests that require a higher level than yours."] = "Oculta las quests que exigen más nivel del que tienes.",
    ["Hides the chains whose quests are all done."] = "Oculta las cadenas cuyas quests están todas hechas.",
    ["No quests match the filters."] = "Ninguna quest coincide con los filtros.",
    ["Dungeons"] = "Mazmorras",
    ["Raids"] = "Bandas",
    ["Zones"] = "Zonas",
    ["Class Quests"] = "Misiones de clase",
    ["Completed"] = "Completada",
    ["In progress"] = "En curso",
    ["Available"] = "Disponible",
    ["Locked"] = "Bloqueada",
    ["Level %d%s"] = "Nivel %d%s",
    [" (min %d)"] = " (mínimo %d)",
    ["Starts at: "] = "Se recoge en: ",
    ["Requires: "] = "Requiere: ",
    ["Requires one of: "] = "Requiere una de: ",
    ["Requires level %d (you are %d)"] = "Requiere nivel %d (tienes %d)",
    ["No quest data yet."] = "Sin datos de quests todavía.",
    ["Drag: pan  |  Wheel: zoom  |  Shift+wheel: sideways  |  Ctrl+wheel: vertical"] =
        "Arrastrar: mover  |  Rueda: zoom  |  Shift+rueda: lados  |  Ctrl+rueda: vertical",
    ["NEW"] = "NUEVA",
    ["Lv"] = "Nv",
    ["One of: "] = "Una de: ",
    ["Level %d required"] = "Nivel %d requerido",
    ["Requirements"] = "Requisitos",
    ["None"] = "Ninguno",
    ["Objective"] = "Objetivo",
    ["Description"] = "Descripción",
    ["Starts"] = "Empieza",
    ["Ends"] = "Termina",
    ["Notes"] = "Notas",
    ["Open quest"] = "Abrir misión",
    ["Show on map"] = "Ver en el mapa",
    ["Show entrance"] = "Ver entrada",
    ["Entrance"] = "Entrada",
    ["Instance entrance: %s"] = "Entrada de la instancia: %s",
    ["Unknown location (it may start inside the instance, or it is not in the database yet)."] =
        "Ubicación desconocida (puede empezar dentro de la instancia o no estar aún en la base de datos).",
    ["Could not open the quest log."] = "No se pudo abrir el registro de misiones.",
    ["Maximize"] = "Maximizar",
    ["Restore"] = "Restaurar",
    ["Inside the instance"] = "Dentro de la instancia",
    ["Waypoint: start"] = "Waypoint: inicio",
    ["Waypoint: turn-in"] = "Waypoint: entrega",
    ["No map location available for this quest giver."] = "No hay ubicación en el mapa para este NPC.",
    ["Waypoint set: %s"] = "Waypoint puesto: %s",
    ["%d-man"] = "%d jug.",
    ["Quests in your log (id - title):"] = "Quests en tu registro (id - título):",
    ["  %d - %s (level %d)"] = "  %d - %s (nivel %d)",
    ["Usage: /completao (open) | /completao minimap (toggle button) | /completao fade <10-100> (opacity while moving) | /completao dump (quest log ids)"] =
        "Uso: /completao (abrir) | /completao minimap (mostrar/ocultar botón) | /completao fade <10-100> (opacidad al moverte) | /completao dump (ids del registro de quests)",
    ["Opacity while moving: %d%%"] = "Opacidad al moverte: %d%%",
    ["Left-click: open"] = "Clic izquierdo: abrir",
    ["Drag: move"] = "Arrastrar: mover",
    ["Minimap button hidden."] = "Botón del minimapa oculto.",
    ["Minimap button shown."] = "Botón del minimapa visible.",
}

ns.L = setmetatable({}, { __index = function(_, k) return k end })

local locale = GetLocale()
if locale == "esES" or locale == "esMX" then
    for k, v in pairs(es) do ns.L[k] = v end
end
