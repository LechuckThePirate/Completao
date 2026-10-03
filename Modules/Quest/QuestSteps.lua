local _, ns = ...

-- Where the game itself says a quest in the log is worked on (the spot of its quest POI): one point per quest,
-- the same one the minimap shows. It stands in for the places the data doesn't have (the new Forever quests have
-- no objective coordinates). Tries the player's map, then the maps of the quest's own start and turn-in.
-- Returns { map, x, y } (coordinates 0-100) or nil.
local function liveSpot(q)
    if not (C_QuestLog.GetQuestsOnMap and C_Map.GetBestMapForUnit) then return nil end
    local maps, seen = {}, {}
    local function add(map)
        if map and not seen[map] then seen[map] = true maps[#maps + 1] = map end
    end
    add(C_Map.GetBestMapForUnit("player"))
    if ns.ResolveZone then
        add(ns.ResolveZone(q.start))
        add(ns.ResolveZone(q.finish))
    end
    for _, map in ipairs(maps) do
        for _, p in ipairs(C_QuestLog.GetQuestsOnMap(map) or {}) do
            if p.questID == q.id and p.x and p.y then return { map = map, x = p.x * 100, y = p.y * 100 } end
        end
    end
end

-- Steps of a quest, for the waypoints and the panel's list: the missing requirement (the start of the
-- previous quest not done yet), the start, one step per objective (q.steps: zone and spot from the data)
-- and the turn-in. With the quest in the log each objective carries its live progress (matched by name to
-- the game's objectives, else by order); the game's objectives with no step in the data are added without
-- a place. Out of the log the client may still know a quest's objectives (once it has loaded it): their text,
-- in the client's language, replaces the data's English one, with no progress. Returns the list and the index of the step that comes next. Step: { kind =
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

    if not onQuest then ns.RequestQuestLoad(q.id) end
    local objectives = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(q.id) or {}
    local used = {}
    -- the objective's text without its count ("Boars slain: 3/5" -> "Boars slain")
    local function liveLabel(o)
        if o.text and o.text ~= "" then
            -- "Boars slain: 3/5" and "3/5 Boars slain" (items) both come
            return (o.text:gsub(":%s*%d+%s*/%s*%d+%s*$", ""):gsub("^%d+%s*/%s*%d+%s+", ""))
        end
    end
    local function progressOf(o)
        if o.numRequired and o.numRequired > 0 then return ("%d/%d"):format(o.numFulfilled or 0, o.numRequired) end
    end
    for i, s in ipairs(q.steps or {}) do
        local step = { kind = "obj", label = s.name, loc = s.x and s or nil, area = s.area }
        local match, byName
        for j, o in ipairs(objectives) do
            if not used[j] and o.text and o.text:lower():find(s.name:lower(), 1, true) then match, byName = j, true break end
        end
        -- out of the log, matching by order is only safe when the game lists as many objectives as the data
        if not match and objectives[i] and not used[i] and (onQuest or #objectives == #q.steps) then match = i end
        if match then
            used[match] = true
            -- no name match: the game's text is in another language than the data's
            if not byName then step.label = liveLabel(objectives[match]) or step.label end
            if onQuest then
                step.done = objectives[match].finished
                step.progress = progressOf(objectives[match])
            end
        end
        list[#list + 1] = step
    end
    for j, o in ipairs(objectives) do
        -- out of the log they only stand in for a quest the data lists no steps for
        if not used[j] and o.text and o.text ~= "" and (onQuest or #(q.steps or {}) == 0) then
            list[#list + 1] = { kind = "obj", label = liveLabel(o), done = onQuest and o.finished or nil,
                progress = onQuest and progressOf(o) or nil }
        end
    end
    -- the unfinished objectives with no place of their own take the one the game gives for the quest
    if onQuest then
        local spot
        for _, s in ipairs(list) do
            if s.kind == "obj" and not s.done and not s.loc then
                if spot == nil then spot = liveSpot(q) or false end
                if spot and (not s.area or (ns.ResolveZone and ns.ResolveZone({ area = s.area }) == spot.map)) then
                    s.loc = spot
                end
            end
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
