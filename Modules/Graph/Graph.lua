local _, ns = ...

-- How many quests go across a shelf of the tree (BuildLayout) before the next one starts below.
ns.MAX_PER_COL = 6

local function parentsOf(q)
    if not q.requiresAny then return q.requires or {} end
    local all = {}
    for _, id in ipairs(q.requires or {}) do all[#all + 1] = id end
    for _, id in ipairs(q.requiresAny) do all[#all + 1] = id end
    return all
end

ns.ParentsOf = parentsOf

-- Whether the quest is part of a chain: it follows another quest of its entry, or another one follows it.
local chained = {}
function ns.IsInChain(q)
    local d = ns.entries[q.entryId]
    if not d then return false end
    local set = chained[d]
    if not set then
        set = {}
        local ids = {}
        for _, other in ipairs(d.quests) do ids[other.id] = true end
        for _, other in ipairs(d.quests) do
            for _, parent in ipairs(parentsOf(other)) do
                if ids[parent] then set[parent], set[other.id] = true, true end
            end
        end
        chained[d] = set
    end
    return set[q.id] == true
end

-- Whether the quest is part of a chain anywhere, not just its own entry: a questline can run from one zone into
-- the next, or out into a dungeon, so a quest at one end of such a chain can have no same-entry chain-mate at all
-- (ns.IsInChain would then say "no", even though "View chain" has a real, cross-entry chain to show). Built once
-- (entries don't change at runtime) and reused; `seen` dedupes a quest registered in more than one entry.
local globalChained
function ns.IsInChainGlobal(q)
    if not globalChained then
        globalChained = {}
        local seen = {}
        for _, e in ipairs(ns.entryList) do
            for _, other in ipairs(e.quests) do
                if not seen[other.id] then
                    seen[other.id] = true
                    for _, parent in ipairs(parentsOf(other)) do
                        globalChained[parent], globalChained[other.id] = true, true
                    end
                end
            end
        end
    end
    return globalChained[q.id] == true
end

-- The layout, read top to bottom: each chain (quests joined by prerequisites) in a band of its own, so a chain's
-- quests are always together and its connections never cross another chain. Inside a band, a quest's row is its depth
-- (the longest path from the chain's start) and the quests of one depth are side by side, centered in the band, in
-- the order of their parents (so lines cross as little as can be). Bands go side by side in shelves at most
-- MAX_PER_COL quests wide; the loose quests (chains of one) come after the chains, filling shelves the same way.
-- Returns nodes[id] = { quest, col = row on screen, row = place across (in quest widths, may be a half) }, the edges,
-- cols (rows on screen), rows (widest line, in quest widths) and count.
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

    -- the chains: groups of quests joined by prerequisites (among the visible ones)
    local root = {}
    local function find(x)
        while root[x] ~= x do root[x] = root[root[x]]; x = root[x] end
        return x
    end
    for _, q in ipairs(list) do root[q.id] = q.id end
    local edges = {}
    for _, q in ipairs(list) do
        for _, reqId in ipairs(parentsOf(q)) do
            if set[reqId] then
                edges[#edges + 1] = { from = reqId, to = q.id }
                local a, b = find(q.id), find(reqId)
                if a ~= b then root[a] = b end
            end
        end
    end
    local groups, byRoot = {}, {}
    for _, q in ipairs(list) do
        local r = find(q.id)
        local g = byRoot[r]
        if not g then
            g = { quests = {}, level = math.huge, first = q.id }
            byRoot[r] = g
            groups[#groups + 1] = g
        end
        g.quests[#g.quests + 1] = q
        g.level = math.min(g.level, q.level or q.minLevel or math.huge)
        g.first = math.min(g.first, q.id)
    end
    -- chains first, then the loose quests; each by level, then by the lowest id
    table.sort(groups, function(a, b)
        local ca, cb = #a.quests > 1, #b.quests > 1
        if ca ~= cb then return ca end
        if a.level ~= b.level then return a.level < b.level end
        return a.first < b.first
    end)

    -- each chain laid out in its band: its depths, each one ordered by where its parents are, then centered
    local nodes = {}
    for _, g in ipairs(groups) do
        local byDepth, height, width = {}, 0, 0
        for _, q in ipairs(g.quests) do
            local d = getDepth(q.id)
            byDepth[d] = byDepth[d] or {}
            table.insert(byDepth[d], q)
            height = math.max(height, d + 1)
        end
        for d = 0, height - 1 do width = math.max(width, #(byDepth[d] or {})) end
        g.height, g.width, g.places = height, width, {}
        for d = 0, height - 1 do
            local row = byDepth[d] or {}
            local key = {}
            for _, q in ipairs(row) do
                local sum, n = 0, 0
                for _, reqId in ipairs(parentsOf(q)) do
                    if g.places[reqId] then
                        sum, n = sum + g.places[reqId], n + 1
                    end
                end
                key[q] = n > 0 and sum / n or math.huge
            end
            table.sort(row, function(a, b)
                if key[a] ~= key[b] then return key[a] < key[b] end
                return a.id < b.id
            end)
            local shift = (width - #row) / 2
            for i, q in ipairs(row) do g.places[q.id] = shift + i - 1 end
        end
    end

    -- the bands, side by side in shelves at most MAX_PER_COL wide (a wider chain takes a shelf of its own)
    local shelfTop, shelfHeight, x, widest = 0, 0, 0, 0
    for _, g in ipairs(groups) do
        if x > 0 and x + g.width > ns.MAX_PER_COL then
            shelfTop, shelfHeight, x = shelfTop + shelfHeight, 0, 0
        end
        for _, q in ipairs(g.quests) do
            nodes[q.id] = { quest = q, col = shelfTop + getDepth(q.id), row = x + g.places[q.id] }
        end
        x = x + g.width
        widest = math.max(widest, x)
        shelfHeight = math.max(shelfHeight, g.height)
    end

    return { nodes = nodes, edges = edges, cols = shelfTop + shelfHeight, rows = widest, count = #list }
end
