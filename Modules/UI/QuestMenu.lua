local _, ns = ...
local L = ns.L

-- Right click on a quest (a node of a tree, a row of a table): a menu with what is usually done with a quest.
-- Entries that don't apply to it are left out (focus, log, abandon only for a quest being done; waypoint and
-- map only when the quest has a place to go to).
local WIDTH = 190

-- The game's own "Abandon quest" confirmation, as the quest log asks it.
function ns.AbandonQuest(id)
    if QuestMapQuestOptions_AbandonQuest then
        pcall(QuestMapQuestOptions_AbandonQuest, id)
        return
    end
    local last = C_QuestLog.GetSelectedQuest and C_QuestLog.GetSelectedQuest()
    C_QuestLog.SetSelectedQuest(id)
    if C_QuestLog.SetAbandonQuest then C_QuestLog.SetAbandonQuest() elseif SetAbandonQuest then SetAbandonQuest() end
    if StaticPopup_Show then StaticPopup_Show("ABANDON_QUEST", ns.QuestTitle(id)) end
    if last then C_QuestLog.SetSelectedQuest(last) end
end

local function refresh()
    if ns.UI_Refresh then ns.UI_Refresh() end
end

function ns.QuestMenu(anchor, q)
    local onQuest = C_QuestLog.IsOnQuest(q.id) and true or false
    local steps, current = ns.QuestSteps(q)
    local step = steps[current]
    local loc, isEntrance = ns.StepTarget(q, step)
    local options = {}
    local function add(name, action, opts)
        opts = opts or {}
        options[#options + 1] = { name = name, action = action, color = opts.color, disabled = opts.disabled }
    end

    if onQuest then
        local focused = ns.Focus_Quest() == q.id
        add(focused and L["Stop focus"] or L["Focus"], function()
            ns.Focus_Toggle(q.id)
            refresh()
        end)
        add(L["Open quest"], function() ns.OpenQuestInLog(q.id) end)
    end
    if loc then
        add(L["Set waypoint"], function() ns.SetWaypoint(loc, step.label) end, { disabled = not ns.CanWaypoint(loc) })
        add(isEntrance and L["Show entrance"] or L["Show on map"], function() ns.ShowStepOnMap(q, step) end,
            { disabled = not ns.CanShowMap(loc) })
    end
    -- from a table: the quest's tree
    if q.entryId and ns.UI_IsSearchMode() and ns.IsInChain(q) then
        add(L["View chain"], function() ns.UI_OpenQuest(q.entryId, q.id) end)
    end
    if onQuest then
        add(L["Abandon quest"], function() ns.AbandonQuest(q.id) end, { color = { 1, 0.35, 0.35 } })
    end
    if #options == 0 then return end

    ns.PopupMenu(anchor, options, function(opt) opt.action() end, WIDTH)
end
