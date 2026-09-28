local _, ns = ...

-- Steps of a quest, for the waypoints and the panel's list: the missing requirement (the start of the
-- previous quest not done yet), the start, one step per objective (q.steps: zone and spot from the data)
-- and the turn-in. With the quest in the log each objective carries its live progress (matched by name to
-- the game's objectives, else by order); the game's objectives with no step in the data are added without
-- a place. Returns the list and the index of the step that comes next. Step: { kind =
-- "req"|"start"|"obj"|"finish", label, loc = { npc, area, x, y } or nil, done, progress = "3/10", current }.
function ns.QuestSteps(q)
    local L = ns.L
    local list = {}
    local completed = C_QuestLog.IsQuestFlaggedCompleted(q.id)
    local onQuest = not completed and C_QuestLog.IsOnQuest(q.id)

    if not completed and not onQuest then
        for _, id in ipairs(q.requires or {}) do
            if not C_QuestLog.IsQuestFlaggedCompleted(id) then
                local def = ns.FindQuestDef(id)
                list[#list + 1] = { kind = "req", loc = def and def.start,
                    label = L["Requirement: %s"]:format(ns.QuestTitle(id, def and def.name)) }
                break
            end
        end
    end
    list[#list + 1] = { kind = "start", loc = q.start, done = completed or onQuest,
        label = L["Start: %s"]:format(q.start and q.start.npc or q.giver or "?") }

    local objectives = onQuest and C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(q.id) or {}
    local used = {}
    local function progressOf(o)
        if o.numRequired and o.numRequired > 0 then return ("%d/%d"):format(o.numFulfilled or 0, o.numRequired) end
    end
    for i, s in ipairs(q.steps or {}) do
        local step = { kind = "obj", label = s.name, loc = s.x and s or nil, area = s.area }
        local match
        for j, o in ipairs(objectives) do
            if not used[j] and o.text and o.text:lower():find(s.name:lower(), 1, true) then match = j break end
        end
        if not match and objectives[i] and not used[i] then match = i end
        if match then
            used[match] = true
            step.done = objectives[match].finished
            step.progress = progressOf(objectives[match])
        end
        list[#list + 1] = step
    end
    for j, o in ipairs(objectives) do
        if not used[j] and o.text and o.text ~= "" then
            list[#list + 1] = { kind = "obj", label = (o.text:gsub(":%s*%d+%s*/%s*%d+%s*$", "")), done = o.finished,
                progress = progressOf(o) }
        end
    end
    if completed then
        for _, s in ipairs(list) do if s.kind == "obj" then s.done = true end end
    end
    list[#list + 1] = { kind = "finish", loc = q.finish, done = completed,
        label = L["Turn in: %s"]:format(q.finish and q.finish.npc or "?") }

    -- the one that comes next: not taken yet, the missing requirement or the start; in progress, the first
    -- unfinished objective (preferably one with a place) or the turn-in once ready; done, the turn-in
    local current
    if completed then
        current = #list
    elseif onQuest then
        if ns.IsReadyToTurnIn(q.id) then
            current = #list
        else
            for i, s in ipairs(list) do
                if s.kind == "obj" and not s.done and (s.loc or s.area) then current = i break end
            end
            if not current then
                for i, s in ipairs(list) do
                    if s.kind == "obj" and not s.done then current = i break end
                end
            end
            current = current or #list
        end
    else
        current = 1
    end
    list[current].current = true
    return list, current
end
