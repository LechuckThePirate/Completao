local _, ns = ...

-- /completao shots [entry id]: takes the screenshots of the CurseForge page by itself. It goes through the views one by
-- one (the tree, a chain, the details, the search, the list, the quest log, the tracked quests, the focus window, each
-- tab of the preferences, the full-screen tree, the world map with the marker, TomTom's arrow and the minimap button),
-- takes a screenshot of each with the game's own Screenshot() and notes in the saved variables (ns.db.shots, lines of
-- "name|time|left|top|right|bottom") which part of the screen the view covers (as fractions of it). After a /reload,
-- tools/shots.mjs finds the screenshots, crops them to those parts and puts them in images/screencaps/.
-- The views it shows are the player's own data: the quests in the log, the entry given (or the one on show).

local STEP = 1.3   -- seconds for a view to settle before it is photographed
local AFTER = 1.0  -- and for the game to write the file before the next one
local PAD = 10     -- room around the part of the screen a view covers, in the interface's units

local running = false
local shotsNote = {}

local function say(text) ns.Print("[shots] " .. text) end

-- Which part of the screen the shown frames cover, as fractions from the top-left corner: { left, top, right, bottom };
-- nil if none of them is shown.
local function rectOf(frames, pad)
    local sw, sh = GetScreenWidth(), GetScreenHeight()
    local ui = UIParent:GetEffectiveScale()
    local l, r, b, t
    for _, f in ipairs(frames) do
        if f and f.IsShown and f:IsShown() and f:GetLeft() and f:GetRight() and f:GetBottom() and f:GetTop() then
            local s = f:GetEffectiveScale() / ui -- the frame's units in the interface's
            l = math.min(l or math.huge, f:GetLeft() * s)
            r = math.max(r or -math.huge, f:GetRight() * s)
            b = math.min(b or math.huge, f:GetBottom() * s)
            t = math.max(t or -math.huge, f:GetTop() * s)
        end
    end
    if not l then return nil end
    pad = pad or { PAD, PAD, PAD, PAD }
    local function clamp(v) return math.max(0, math.min(1, v)) end
    return {
        clamp((l - pad[1]) / sw), clamp(1 - (t + pad[2]) / sh),
        clamp((r + pad[3]) / sw), clamp(1 - (b - pad[4]) / sh),
    }
end
ns.Shots_RectOf = rectOf

local function ensureWindow()
    if not ns.UI then ns.UI_Toggle() end
    if not ns.UI:IsShown() then ns.UI_Toggle() end
    if ns.UI_IsTreeFullscreen and ns.UI_IsTreeFullscreen() then ns.UI_SetTreeFullscreen(false) end
    if ns.Prefs_IsShown and ns.Prefs_IsShown() then ns.Prefs_Toggle() end
end

-- A quest of the entry with a chain of its own (the one to show the chain view on), and one with a known start (for the
-- map).
local function questOf(entry, wanted)
    for _, q in ipairs(entry and entry.quests or {}) do
        if ns.QuestVisible(q, entry) and wanted(q) then return q end
    end
end

-- The scenes, in order: name (the file's), setup(ctx) (false to skip it), frames() (what to crop to; none: the whole
-- screen), pad (pixels around), cleanup().
local function scenes(ctx)
    local function window() return { ns.UI, ns.UI.medallion } end
    local list = {}
    local function add(scene) list[#list + 1] = scene end

    add({ name = "main_window", frames = window, setup = function()
        ensureWindow()
        ns.UI_SetEntryView("tree")
        return ns.UI_SelectEntry(ctx.entry)
    end })
    add({ name = "chain_view", frames = window, setup = function()
        ensureWindow()
        ns.UI_SetEntryView("tree")
        ns.UI_SelectEntry(ctx.entry)
        local q = questOf(ns.entries[ctx.entry], function(candidate) return ns.IsInChain(candidate) end)
        if not q then return false end
        ns.UI_OpenQuest(ctx.entry, q.id)
    end })
    add({ name = "quest_details", frames = function() return { ns.Detail_Frame() } end, setup = function()
        if not (ns.Detail_Current() and ns.Detail_Frame() and ns.Detail_Frame():IsShown()) then return false end
    end })
    add({ name = "tree_fullscreen", setup = function()
        ensureWindow()
        ns.UI_SelectEntry(ctx.entry)
        ns.UI_SetTreeFullscreen(true)
    end, cleanup = function() ns.UI_SetTreeFullscreen(false) end })
    add({ name = "list_view", frames = window, setup = function()
        ensureWindow()
        ns.UI_SelectEntry(ctx.entry)
        ns.UI_SetEntryView("list")
    end, cleanup = function() ns.UI_SetEntryView("tree") end })
    add({ name = "search", frames = window, setup = function()
        ensureWindow()
        ns.UI_SetSearchMode(true, "search")
    end })
    add({ name = "quest_log", frames = window, setup = function()
        ensureWindow()
        ns.char.tableGroup = ns.char.tableGroup or {}
        ctx.group = ns.char.tableGroup.log
        ns.char.tableGroup.log = "zone"
        ns.UI_SetSearchMode(true, "log")
    end, cleanup = function() ns.char.tableGroup.log = ctx.group end })
    add({ name = "tracked_quests", frames = window, setup = function()
        ensureWindow()
        ns.UI_SetSearchMode(true, "tracked")
    end })
    add({ name = "focus_window", frames = function() return { _G.CompletaoFocusFrame } end, pad = { 12, 34, 12, 12 }, setup = function()
        if not ns.Focus_Quest() then ns.Focus_Auto() end
        if not ns.Focus_Quest() then return false end
        ns.shotsChrome = true -- its title bar shows with the mouse over it only: for the picture, always
    end, cleanup = function() ns.shotsChrome = nil end })
    local tabs = { "general", "interface", "tracker", "profile" }
    for index, name in ipairs(tabs) do
        add({ name = "preferences_" .. name, frames = function() return { _G.CompletaoPreferencesFrame } end, setup = function()
            ensureWindow()
            ns.Prefs_Toggle()
            _G.CompletaoPreferencesFrame:Show()
            _G.CompletaoPreferencesFrame.ShowTab(index)
        end, cleanup = function()
            if index == #tabs and _G.CompletaoPreferencesFrame then _G.CompletaoPreferencesFrame:Hide() end
        end })
    end
    add({ name = "minimap_button", frames = function() return { _G.Minimap, _G.CompletaoMinimapButton } end, pad = { 16, 16, 16, 16 },
        setup = function()
            if not ns.Minimap_IsShown() then return false end
        end })
    add({ name = "tomtom_integration", frames = function() return { _G.TomTomCrazyArrow } end, pad = { 30, 30, 30, 30 }, setup = function()
        local q = questOf(ns.entries[ctx.entry], function(candidate) return candidate.start and candidate.start.x end)
        if not (q and _G.TomTom and ns.CanWaypoint(q.start)) then return false end
        ns.SetWaypoint(q.start, q.name)
    end })
    add({ name = "map_marker", setup = function()
        local q = questOf(ns.entries[ctx.entry], function(candidate) return candidate.start and candidate.start.x end)
        if not (q and ns.CanShowMap(q.start)) then return false end
        ns.ShowOnMap(q.start, q.name)
    end, cleanup = function()
        if _G.WorldMapFrame and _G.WorldMapFrame:IsShown() then pcall(_G.WorldMapFrame.Hide, _G.WorldMapFrame) end
    end })
    return list
end
ns.Shots_Scenes = scenes

-- Runs every scene. `entry`: the entry id to show the trees of (the one on show by default).
function ns.Shots_Run(entry)
    if running then
        say("already running")
        return false
    end
    if not ns.UI then ns.UI_Toggle() end
    entry = (entry and ns.entries[entry]) and entry or ns.char.selected or (ns.entryList[1] and ns.entryList[1].id)
    local ctx = { entry = entry }
    local list = scenes(ctx)
    local saved = { selected = ns.char.selected, view = ns.char.entryView, category = ns.char.category }
    local oldFormat = GetCVar and GetCVar("screenshotFormat")
    if SetCVar then pcall(SetCVar, "screenshotFormat", "png") end
    ns.db.shots = {}
    shotsNote = {}
    running = true
    say(("%d scenes on %s: don't touch anything until it says it is done"):format(#list, tostring(entry)))

    local index = 0
    local function finish()
        running = false
        if oldFormat and SetCVar then pcall(SetCVar, "screenshotFormat", oldFormat) end
        ns.char.selected, ns.char.entryView, ns.char.category = saved.selected, saved.view, saved.category
        if ns.UI and ns.UI:IsShown() then
            ns.UI_SetSearchMode(false)
            ns.UI_Refresh()
        end
        say(("done: %d screenshots%s. /reload to save the list, then run: node tools/shots.mjs"):format(
            #ns.db.shots, #shotsNote > 0 and (" (skipped: " .. table.concat(shotsNote, ", ") .. ")") or ""))
    end
    local function nextScene()
        index = index + 1
        local scene = list[index]
        if not scene then return finish() end
        local ok, result = pcall(scene.setup)
        if not ok or result == false then
            shotsNote[#shotsNote + 1] = scene.name
            return nextScene()
        end
        C_Timer.After(STEP, function()
            local rect = { 0, 0, 1, 1 }
            if scene.frames then rect = rectOf(scene.frames(), scene.pad) end
            if rect then
                ns.db.shots[#ns.db.shots + 1] = ("%s|%d|%.5f|%.5f|%.5f|%.5f"):format(scene.name, time(), rect[1], rect[2], rect[3], rect[4])
                Screenshot()
            else
                shotsNote[#shotsNote + 1] = scene.name
            end
            C_Timer.After(AFTER, function()
                if scene.cleanup then pcall(scene.cleanup) end
                nextScene()
            end)
        end)
    end
    nextScene()
    return true
end
