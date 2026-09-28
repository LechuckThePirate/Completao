-- Carga del addon en los tests: los archivos en el orden del TOC (como el juego), cada uno con
-- ("Completao", ns). LoadAddon() carga todo; LoadAddon({ files = {...} }) solo esos archivos (con
-- Localization/Locale.lua delante si no esta). StartAddon(ns) simula la entrada al juego.

function TocFiles()
    local files = {}
    for line in io.lines("Completao.toc") do
        line = line:gsub("\r", ""):gsub("%s+$", "")
        if line ~= "" and not line:match("^##") and line:match("%.lua$") then
            files[#files + 1] = (line:gsub("\\", "/"))
        end
    end
    return files
end

function LoadAddon(opts)
    opts = opts or {}
    local ns = {}
    local files = opts.files
    if files then
        if files[1] ~= "Localization/Locale.lua" then
            local withLocale = { "Localization/Locale.lua" }
            for _, f in ipairs(files) do withLocale[#withLocale + 1] = f end
            files = withLocale
        end
    else
        files = TocFiles()
    end
    for _, f in ipairs(files) do
        local chunk = assert(loadfile(f))
        chunk("Completao", ns)
    end
    return ns
end

-- Todos los marcos con OnEvent reciben el evento (como si el juego lo disparara).
function FireEvent(event, ...)
    for _, f in ipairs(WowMock.frames) do
        local handler = f._scripts.OnEvent
        if handler then handler(f, event, ...) end
    end
end

-- Ayudantes para los tests de interfaz ----------------------------------------------------------

-- Carga el addon entero, lo arranca y abre la ventana (en la entrada `entryId`, si se da).
function OpenAddon(entryId, charDB)
    local ns = LoadAddon()
    StartAddon(ns, nil, charDB or { selected = entryId })
    ns.UI_Toggle()
    return ns
end

-- Cuadros del arbol visibles: { [questID] = boton }.
function ShownNodes()
    local byId, n = {}, 0
    for _, f in ipairs(WowMock.frames) do
        if f.status and f.quest and f._shown then byId[f.quest.id] = f; n = n + 1 end
    end
    return byId, n
end

-- Filas visibles de la tabla del buscador / registro, en orden.
function ShownRows()
    local rows = {}
    for _, f in ipairs(WowMock.frames) do
        if f.quest and f.whereText and f._shown then rows[#rows + 1] = f end
    end
    return rows
end

-- ADDON_LOADED + PLAYER_ENTERING_WORLD, con variables guardadas nuevas (o las que se pasen).
function StartAddon(ns, db, charDB)
    CompletaoDB, CompletaoCharDB = db, charDB
    FireEvent("ADDON_LOADED", "Completao")
    FireEvent("PLAYER_ENTERING_WORLD")
    return ns
end
