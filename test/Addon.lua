-- Loading the addon in tests: the files in TOC order (like the game), each with ("Completao", ns).
-- LoadAddon() loads everything; LoadAddon({ files = {...} }) only those files (with the Localization/
-- files in front if missing). StartAddon(ns) simulates entering the game.

-- The .xml files of the toc (Load_*.xml: <Script file> and <Include file>, paths relative to the xml) are
-- expanded in place, like the game does.
local function addFiles(path, files)
    path = path:gsub("\\", "/")
    if not path:match("%.xml$") then
        files[#files + 1] = path
        return
    end
    local dir = path:match("^(.*/)[^/]*$") or ""
    local handle = assert(io.open(path))
    local xml = handle:read("*a"):gsub("<!%-%-.-%-%->", "")
    handle:close()
    for tag, ref in xml:gmatch('<(%a+)%s+file="([^"]+)"') do
        if tag == "Script" or tag == "Include" then addFiles(dir .. ref, files) end
    end
end

-- The Lua files the toc loads, in order. `toc` picks another toc (default Completao.toc).
function TocFiles(toc)
    local files = {}
    for line in io.lines(toc or "Completao.toc") do
        line = line:gsub("%s+$", "") -- also drops the CR of CRLF files
        if line ~= "" and not line:match("^##") then addFiles(line, files) end
    end
    return files
end

function LoadAddon(opts)
    opts = opts or {}
    local ns = {}
    local files = opts.files
    if files then
        if files[1] ~= "Localization/Locale.lua" then
            local withLocale = {}
            for _, f in ipairs(TocFiles()) do
                if f:match("^Localization/") then withLocale[#withLocale + 1] = f end
            end
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

-- Every frame that registered the event and has an OnEvent receives it (as if the game fired it).
function FireEvent(event, ...)
    for _, f in ipairs(WowMock.frames) do
        local handler = f._scripts.OnEvent
        if handler and f._events and f._events[event] then handler(f, event, ...) end
    end
end

-- Helpers for the UI tests ----------------------------------------------------------------------

-- Loads the whole addon, starts it and opens the window (on entry `entryId`, if given).
function OpenAddon(entryId, charDB)
    local ns = LoadAddon()
    StartAddon(ns, nil, charDB or { selected = entryId })
    ns.UI_Toggle()
    return ns
end

-- Visible tree boxes: { [questID] = button }.
function ShownNodes()
    local byId, n = {}, 0
    for _, f in ipairs(WowMock.frames) do
        if f.status and f.quest and f._shown then byId[f.quest.id] = f; n = n + 1 end
    end
    return byId, n
end

-- Visible rows of the search / quest log table, in order.
function ShownRows()
    local rows = {}
    for _, f in ipairs(WowMock.frames) do
        if f.quest and f.whereText and f._shown then rows[#rows + 1] = f end
    end
    return rows
end

-- ADDON_LOADED + PLAYER_ENTERING_WORLD, with fresh saved variables (or the ones passed in).
function StartAddon(ns, db, charDB)
    CompletaoDB, CompletaoCharDB = db, charDB
    FireEvent("ADDON_LOADED", "Completao")
    FireEvent("PLAYER_ENTERING_WORLD")
    return ns
end
