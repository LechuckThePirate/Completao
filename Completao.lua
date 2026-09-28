local ADDON, ns = ...

-- Arranque del addon: eventos, avisos en el chat, /completao y atajos de teclado. Se carga el ultimo; los
-- modulos (Modules/) y los datos (Data/) ya estan cargados.

function ns.Print(...)
    print("|cff33ff99Completao!!|r:", ...)
end

-- Repinta la ventana (si esta abierta) poco despues de un cambio, agrupando cambios seguidos.
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

local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("QUEST_LOG_UPDATE")
events:RegisterEvent("QUEST_TURNED_IN")
events:RegisterEvent("QUEST_DATA_LOAD_RESULT")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then return end
        ns.InitSettings()
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
