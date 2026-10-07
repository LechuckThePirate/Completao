local _, ns = ...
local L = ns.L

-- Right click on a quest (a node of a tree, a row of a table): a menu with what is usually done with a quest.
-- Every option is always listed, as the buttons of the quest details are: the ones that don't apply are
-- greyed out (focus, log, abandon need the quest in the log; waypoint and map a place to go to; chain a chain).
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

    -- the same options, in the same order, as the buttons of the quest details (QuestPanel.lua)
    local focused = ns.Focus_Quest() == q.id
    add(focused and L["Stop focus"] or L["Focus"], function()
        ns.Focus_Toggle(q.id)
        refresh()
    end, { disabled = not onQuest })
    add(L["Open quest"], function() ns.OpenQuestInLog(q.id) end, { disabled = not onQuest })
    add(L["Set waypoint"], function() ns.SetWaypoint(loc, step.label) end,
        { disabled = not (loc and ns.CanWaypoint(loc)) })
    add(isEntrance and L["Show entrance"] or L["Show on map"], function() ns.ShowStepOnMap(q, step) end,
        { disabled = not (loc and ns.CanShowMap(loc)) })
    add(L["View chain"], function() ns.UI_OpenQuest(q.entryId, q.id) end,
        { disabled = not (q.entryId and ns.IsInChain(q)) })
    add(L["Abandon quest"], function() ns.AbandonQuest(q.id) end,
        { color = { 1, 0.35, 0.35 }, disabled = not onQuest })

    ns.PopupMenu(anchor, options, function(opt) opt.action() end, WIDTH)
end
