local _, ns = ...

-- Layout por columnas: la columna es la profundidad (camino mas largo desde una raiz dentro
-- de la mazmorra); la fila se ordena por la media de las filas de los padres.
local function parentsOf(q)
    if not q.requiresAny then return q.requires or {} end
    local all = {}
    for _, id in ipairs(q.requires or {}) do all[#all + 1] = id end
    for _, id in ipairs(q.requiresAny) do all[#all + 1] = id end
    return all
end

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
        if visiting[id] then return 0 end -- ciclo en los datos: se corta
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

    local nodes, edges, maxRows = {}, {}, 0
    for c = 0, maxCol do
        local col = columns[c] or {}
        local function key(q)
            local sum, n = 0, 0
            for _, reqId in ipairs(parentsOf(q)) do
                if nodes[reqId] then
                    sum = sum + nodes[reqId].row
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
        for row, q in ipairs(col) do
            nodes[q.id] = { quest = q, col = c, row = row - 1 }
            for _, reqId in ipairs(parentsOf(q)) do
                if set[reqId] then
                    edges[#edges + 1] = { from = reqId, to = q.id }
                end
            end
        end
        maxRows = math.max(maxRows, #col)
    end

    return { nodes = nodes, edges = edges, cols = maxCol + 1, rows = maxRows, count = #list }
end
