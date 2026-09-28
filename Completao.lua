local ADDON, ns = ...

-- Addon entry point: events, chat messages, /completao and key bindings. Loaded last, once the modules
-- (Modules/) and the data (Data/) are in.

function ns.Print(...)
    print("|cff33ff99Completao!!|r:", ...)
end

-- Redraws the window (if open) shortly after a change, batching changes that come together.
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

-- Chat notice, like Embolsao: "Completao!! vX -- initializing..." when the addon loads and
-- "... initialization complete" once the player is in the world with the data indexed.
local function announce(text)
    if ns.char and ns.char.quiet then return end -- Preferences: chat messages turned off
    print(("|cff33ff99Completao!!|r v%s -- %s"):format(ns.Version(), text))
end

local announcedReady, shownWelcome = false, false
local function announceReady()
    if announcedReady then return end
    announcedReady = true
    local quests = 0
    for _, d in ipairs(ns.entryList) do quests = quests + #d.quests end
    announce(ns.L["initialization complete (%d quests)"]:format(quests))
end

-- What the window shows depends on the quest log (taking, progressing, abandoning and turning in quests) and
-- on the character's level (low level / too high, locked by level), so those events redraw it. Some of
-- them may not exist in every client, and registering an unknown event is an error: they are optional.
local REFRESH_EVENTS = {
    "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "QUEST_DATA_LOAD_RESULT",
    "UNIT_QUEST_LOG_CHANGED", "PLAYER_LEVEL_UP", "PLAYER_LEVEL_CHANGED",
}
-- the level may not be updated yet when the event fires, so these redraw again a moment later
local LEVEL_EVENTS = { PLAYER_LEVEL_UP = true, PLAYER_LEVEL_CHANGED = true }

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
for _, name in ipairs(REFRESH_EVENTS) do pcall(events.RegisterEvent, events, name) end
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        ns.InitSettings()
        announce(ns.L["initializing..."])
        ns.Minimap_Init()
    elseif event == "PLAYER_ENTERING_WORLD" then
        -- also fires after /reload; announced (and the welcome window shown, if new) once per UI load
        C_Timer.After(1, announceReady)
        ns.RequestRefresh()
        if not shownWelcome then
            shownWelcome = true
            if ns.Welcome_ShowIfNew then ns.Welcome_ShowIfNew() end
        end
    else
        ns.RequestRefresh()
        if LEVEL_EVENTS[event] then C_Timer.After(1, ns.RequestRefresh) end
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

-- Key bindings (Bindings.xml): shown in Options -> Keybindings, in their own "Completao!!" section
-- (like Questie).
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
    elseif msg == "changelog" or msg == "whatsnew" then
        ns.Welcome_Show()
    elseif msg:match("^fade") then
        local percent = tonumber(msg:match("^fade%s+(%d+)"))
        if percent then ns.char.fadeAlpha = math.max(0.1, math.min(1, percent / 100)) end
        ns.Print(ns.L["Opacity while moving: %d%%"]:format(math.floor((ns.char.fadeAlpha or 0.5) * 100 + 0.5)))
    elseif msg == "" then
        ns.UI_Toggle()
    else
        ns.Print(ns.L["Usage: /completao (open) | prefs | minimap | fade <10-100> | changelog | dump"])
    end
end
