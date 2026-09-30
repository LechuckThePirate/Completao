local _, ns = ...

-- Settings per character or for the whole account, as in Embolsao ("Character specific preferences").
-- These keys are read from and written to the active store: the character's (CompletaoCharDB) or the
-- account's shared one (CompletaoDB.shared). The rest of ns.char (selected entry, open section) always
-- belongs to the character. The rest of the addon uses ns.char without knowing which one is behind it.
local SWITCHABLE = {
    fadeAlpha = true, fadeAlphaCombat = true, quiet = true, minimap = true, filters = true, zoom = true, window = true, openWithQuestLog = true,
    openOnQuestLog = true, clickThroughCombat = true, clickThroughMoving = true,
    sideCollapsed = true, focusWindow = true,
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

-- On load (ADDON_LOADED): prepares the saved variables and ns.db / ns.char.
function ns.InitSettings()
    CompletaoDB = CompletaoDB or {}
    CompletaoCharDB = CompletaoCharDB or {}
    ns.db = CompletaoDB
    ns.db.descriptions = nil -- texts saved by a development version; no longer saved
    -- version the welcome window's "Don't show this again" was ticked for; account-wide, like Embolsao's
    CompletaoDB.welcomeDismissedVersion = CompletaoDB.welcomeDismissedVersion or ""
    -- the first time, the shared settings come from the character that first uses them
    if not CompletaoDB.shared then
        CompletaoDB.shared = {}
        for key in pairs(SWITCHABLE) do CompletaoDB.shared[key] = deepCopy(CompletaoCharDB[key]) end
    end
    -- per character by default (as before); a new one starts with a copy of the shared ones
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

-- Switching to per character copies the shared settings, so the change isn't noticed; switching back to
-- shared leaves the character's copy saved, unused. Then whatever is in the new store is applied.
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
