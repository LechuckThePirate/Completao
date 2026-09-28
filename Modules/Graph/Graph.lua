local _, ns = ...

-- Column layout: the column is the depth (longest path from a root within the entry); rows are
-- ordered by the average row of the parents.
ns.MAX_PER_COL = 12

local function parentsOf(q)
    if not q.requiresAny then return q.requires or {} end
    local all = {}
    for _, id in ipairs(q.requires or {}) do all[#all + 1] = id end
    for _, id in ipairs(q.requiresAny) do all[#all + 1] = id end
    return all
end

ns.ParentsOf = parentsOf

function ns.BuildLayout(quests, visible)
    local set, list = {}, {}
    for _, q in ipairs(quests) do
        if not visible or visible(q) then
            set[q.id] = q
            list[#list + 1] = q
        end
    end

    local depth, visiting = {}, {}
    local function getDepth(id)
        if depth[id] then return depth[id] end
        if visiting[id] then return 0 end -- a cycle in the data: cut it
        visiting[id] = true
        local d = 0
        for _, reqId in ipairs(parentsOf(set[id])) do
            if set[reqId] then
                d = math.max(d, getDepth(reqId) + 1)
            end
        end
        visiting[id] = nil
        depth[id] = d
        return d
    end

    local columns, maxCol = {}, 0
    for _, q in ipairs(list) do
        local c = getDepth(q.id)
        columns[c] = columns[c] or {}
        table.insert(columns[c], q)
        maxCol = math.max(maxCol, c)
    end

    -- A column with more than MAX_PER_COL quests is spread over several visual columns, so a zone with a
    -- hundred loose quests isn't a tower of a hundred rows.
    local nodes, edges, maxRows, visualCols = {}, {}, 0, 0
    for c = 0, maxCol do
        local col = columns[c] or {}
        local function key(q)
            local sum, n = 0, 0
            for _, reqId in ipairs(parentsOf(q)) do
                if nodes[reqId] then
                    sum = sum + nodes[reqId].lrow
                    n = n + 1
                end
            end
            return n > 0 and sum / n or math.huge
        end
        local keys = {}
        for _, q in ipairs(col) do keys[q] = key(q) end
        table.sort(col, function(a, b)
            if keys[a] ~= keys[b] then return keys[a] < keys[b] end
            return a.id < b.id
        end)
        for i, q in ipairs(col) do
            local lrow = i - 1
            nodes[q.id] = {
                quest = q, lrow = lrow,
                col = visualCols + math.floor(lrow / ns.MAX_PER_COL), row = lrow % ns.MAX_PER_COL,
            }
            for _, reqId in ipairs(parentsOf(q)) do
                if set[reqId] then
                    edges[#edges + 1] = { from = reqId, to = q.id }
                end
            end
        end
        visualCols = visualCols + math.max(1, math.ceil(#col / ns.MAX_PER_COL))
        maxRows = math.max(maxRows, math.min(#col, ns.MAX_PER_COL))
    end

    return { nodes = nodes, edges = edges, cols = visualCols, rows = maxRows, count = #list }
end
