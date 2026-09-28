-- Usage: lua tools/questie_classic.lua [entryId ...]     (dungeons/raids; default: vc wc)
--        lua tools/questie_classic.lua zones             (zones, classes, professions, races)
-- Reads the Classic database that ships with Questie and generates Data/Generated/Classic.lua with each
-- dungeon's quests: those of its zone, those given/received/killed by NPCs that only appear inside, and the
-- chains (prerequisites and continuations) that connect them.
local ROOT = (arg[0]:match("^(.*)[/\\][^/\\]+$") or ".") .. "/.."
local Q = os.getenv("QUESTIE_DIR") or "D:/Games/World of Warcraft/_classic_beta_/Interface/AddOns/Questie/"
local OUT = ROOT .. "/Data/Generated/Classic.lua"

-- addon entry id -> the dungeon's area id in Questie (Database/Zones/data/dungeons.lua)
local INSTANCE_AREA = {
    rfc = 2437, wc = 718, vc = 1581, sfk = 209, bfd = 719, stk = 717, gnom = 721, rfk = 491,
    sm = 796, rfd = 722, ulda = 1337, zf = 1176, mara = 2100, st = 1477, brd = 1584,
    lbrs = 1583, dm = 2557, scho = 2057, strat = 2017, ony = 2159,
}
local ENTRANCES_OUT = ROOT .. "/Data/Generated/Entrances.lua"

local function read(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end
local function loadData(path, field)
    local body = read(path):match("QuestieDB%." .. field .. " = %[%[(.-)%]%]")
    return assert(load(body))()
end

local quests = loadData(Q .. "Database/Classic/classicQuestDB.lua", "questData")
local npcs = loadData(Q .. "Database/Classic/classicNpcDB.lua", "npcData")

-- The corrections Questie applies on top of the base (prerequisites, levels, races, classes, zones...)
do
    local nFixed, nFields = dofile(ROOT .. "/tools/questie_fixes.lua")(quests, Q)
    print(("Questie corrections applied: %d quests, %d fields"):format(nFixed, nFields))
end

-- each dungeon's areas (main id + alternates)
local areaOf, entranceOf = {}, {}
for line in read(Q .. "Database/Zones/data/dungeons.lua"):gmatch("[^\n]+") do
    local id, _, rest = line:match('^%s*%[(%d+)%] = {"([^"]+)",(.*)$')
    if id then
        id = tonumber(id)
        areaOf[id] = id
        local alts = rest:match("^(%b{})")
        if alts then for a in alts:gmatch("%d+") do areaOf[tonumber(a)] = id end end
        -- first entrance: {parent zone, x, y}
        local zone, x, y = rest:match(",%s*%d+,%s*{%s*{%s*(%d+),%s*([%d%.]+),%s*([%d%.]+)")
        if zone then entranceOf[id] = { area = tonumber(zone), x = tonumber(x), y = tonumber(y) } end
    end
end

local Q_NAME, Q_START, Q_END, Q_MINLVL, Q_LVL, Q_RACES, Q_OBJ = 1, 2, 3, 4, 5, 6, 10
local Q_PREGROUP, Q_PRESINGLE, Q_ZONE, Q_NEXT = 12, 13, 17, 22
local N_NAME, N_SPAWNS, N_ZONE = 1, 7, 9
local Q_TEXT = 8

-- An NPC "belongs" to a dungeon if all its spawn zones are that dungeon's.
local function npcInstance(npcId)
    local n = npcs[npcId]
    local spawns = n and n[N_SPAWNS]
    if not spawns then return nil end
    local inst
    for zone in pairs(spawns) do
        local d = areaOf[zone]
        if not d or (inst and inst ~= d) then return nil end
        inst = d
    end
    return inst
end

local function instancesOf(q)
    local found = {}
    local function add(d) if d then found[d] = true end end
    add(q[Q_ZONE] and areaOf[q[Q_ZONE]])
    for _, list in ipairs({ q[Q_START] and q[Q_START][1] or {}, q[Q_END] and q[Q_END][1] or {} }) do
        for _, npc in ipairs(list) do add(npcInstance(npc)) end
    end
    local kills = q[Q_OBJ] and q[Q_OBJ][1]
    if kills then for _, o in ipairs(kills) do add(npcInstance(o[1])) end end
    return found
end

-- indexes: core per dungeon, children by prerequisite
local core, children = {}, {}
for id, q in pairs(quests) do
    for d in pairs(instancesOf(q)) do
        core[d] = core[d] or {}
        core[d][id] = true
    end
    local function link(list)
        for _, p in ipairs(list or {}) do
            children[p] = children[p] or {}
            children[p][#children[p] + 1] = id
        end
    end
    link(q[Q_PREGROUP]); link(q[Q_PRESINGLE])
end
for id, q in pairs(quests) do
    local nxt = q[Q_NEXT]
    if nxt and quests[nxt] then
        children[id] = children[id] or {}
        children[id][#children[id] + 1] = nxt
    end
end

-- Prerequisites: up to UP_HOPS steps back. Continuations: only DOWN_HOPS steps forward (further on,
-- chains from other zones creep in, e.g. Argent Dawn from Stratholme). It never crosses into quests that
-- are the core of another dungeon.
local UP_HOPS, DOWN_HOPS = 12, 3

local function collect(area)
    local set = {}
    for id in pairs(core[area] or {}) do set[id] = true end
    local function foreign(id)
        for d, ids in pairs(core) do if d ~= area and ids[id] then return true end end
    end
    local function parentsOf(id)
        local r = {}
        for _, p in ipairs(quests[id][Q_PREGROUP] or {}) do r[#r + 1] = p end
        for _, p in ipairs(quests[id][Q_PRESINGLE] or {}) do r[#r + 1] = p end
        return r
    end
    local function walk(neighboursOf, maxHops)
        local frontier = {}
        for id in pairs(core[area] or {}) do frontier[#frontier + 1] = id end
        for _ = 1, maxHops do
            local nextFrontier = {}
            for _, id in ipairs(frontier) do
                for _, n in ipairs(neighboursOf(id)) do
                    if quests[n] and not set[n] and not foreign(n) then
                        set[n] = true
                        nextFrontier[#nextFrontier + 1] = n
                    end
                end
            end
            if #nextFrontier == 0 then break end
            frontier = nextFrontier
        end
    end
    walk(parentsOf, UP_HOPS)
    walk(function(id) return children[id] or {} end, DOWN_HOPS)
    return set
end

-- Quests with the same name and faction inside the dungeon (chains like "The Defias Brotherhood") are
-- numbered in chain order: "Name (2/7)".
local function displayNames(set)
    local depth = {}
    local function depthOf(id)
        if depth[id] then return depth[id] end
        depth[id] = 0
        local m = 0
        for _, list in ipairs({ quests[id][Q_PREGROUP] or {}, quests[id][Q_PRESINGLE] or {} }) do
            for _, p in ipairs(list) do if set[p] then m = math.max(m, depthOf(p) + 1) end end
        end
        depth[id] = m
        return m
    end
    local groups = {}
    for id in pairs(set) do
        local q = quests[id]
        local key = q[Q_NAME] .. "|" .. tostring(q[Q_RACES])
        groups[key] = groups[key] or {}
        table.insert(groups[key], id)
    end
    local names = {}
    for _, g in pairs(groups) do
        table.sort(g, function(a, b)
            local da, db = depthOf(a), depthOf(b)
            if da ~= db then return da < db end
            return a < b
        end)
        for i, id in ipairs(g) do
            names[id] = #g > 1 and ("%s (%d/%d)"):format(quests[id][Q_NAME], i, #g) or quests[id][Q_NAME]
        end
    end
    return names
end

local function lua(s) return '"' .. tostring(s):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n") .. '"' end
local function ids(list) local t = {} for _, v in ipairs(list) do t[#t + 1] = tostring(v) end return "{ " .. table.concat(t, ", ") .. " }" end

-- An NPC's location: preferred zone (the NPC's most common) and first coordinate. NPCs inside a dungeon
-- have coordinates -1 and are emitted without a position.
local function location(npcId)
    local n = npcs[npcId]
    local spawns = n[N_SPAWNS]
    local parts = { "npc = " .. lua(n[N_NAME]) }
    if spawns then
        local zone = spawns[n[N_ZONE]] and n[N_ZONE]
        if not zone then
            for z in pairs(spawns) do if not zone or z < zone then zone = z end end
        end
        local c = zone and spawns[zone][1]
        if c and c[1] >= 0 then
            parts[#parts + 1] = ("area = %d, x = %.1f, y = %.1f"):format(zone, c[1], c[2])
        end
    end
    return "{ " .. table.concat(parts, ", ") .. " }"
end

local ALLIANCE, HORDE, ALL_RACES = 77, 178, 255

-- Effective class (field 7) and race (field 6) masks: the quest's own or, if it has none, the one inherited
-- from its mandatory prerequisites (intersection). So a quest that requires a Horde-only or class-only
-- quest is also Horde-only or class-only.
local function inheritedMask(field)
    local memo = {}
    local function mask(id, depth)
        if memo[id] ~= nil then return memo[id] end
        memo[id] = false -- cuts cycles
        local q = quests[id]
        if not q then return false end
        local m = q[field] and q[field] ~= 0 and q[field] or nil
        if m == ALL_RACES and field == 6 then m = nil end
        if not m and depth < 30 then
            local parents = {}
            for _, p in ipairs(q[Q_PREGROUP] or {}) do parents[#parents + 1] = p end
            if q[Q_PRESINGLE] and #q[Q_PRESINGLE] == 1 then parents[#parents + 1] = q[Q_PRESINGLE][1] end
            for _, p in ipairs(parents) do
                local pm = mask(p, depth + 1)
                if pm then m = m and (m & pm) or pm end
            end
            if m == 0 then m = nil end
        end
        memo[id] = m or false
        return memo[id]
    end
    return function(id) return mask(id, 0) end
end
local classMask, raceMask = inheritedMask(7), inheritedMask(6)

-- Quests done inside one of our dungeons or raids (their zone, or some NPC that gives, receives or is
-- killed only exists inside): they are marked dungeon = "<entry id>", also when they show up in a zone.
local ENTRY_OF_AREA = {}
for entry, area in pairs(INSTANCE_AREA) do ENTRY_OF_AREA[area] = entry end
local dungeonOf = {}
for area, questIds in pairs(core) do
    local entry = ENTRY_OF_AREA[area]
    if entry then
        for id in pairs(questIds) do
            if not dungeonOf[id] or entry < dungeonOf[id] then dungeonOf[id] = entry end
        end
    end
end

-- Intermediate steps: one per objective (kill, use a world object, collect an item, event/escort), with
-- the zone where what you look for is most common and the densest spot in it. For "collect X" the places
-- of the creatures and objects that drop it are pooled. Inside a dungeon there are no coordinates: the
-- step carries only the zone (the addon takes you to the entrance).
local items = loadData(Q .. "Database/Classic/classicItemDB.lua", "itemData")
local objects = loadData(Q .. "Database/Classic/classicObjectDB.lua", "objectData")
local I_NAME, I_NPCDROPS, I_OBJDROPS, O_NAME, O_SPAWNS = 1, 2, 3, 1, 4
local MAX_SOURCES, MAX_STEPS = 40, 6

local function addSpawns(acc, spawns)
    for zone, list in pairs(spawns or {}) do
        acc[zone] = acc[zone] or {}
        for _, c in ipairs(list) do acc[zone][#acc[zone] + 1] = c end
    end
end

-- same idea as densestPoint in the local tools: the 6x6 cell (with its neighbors) with the most points
local function densest(pts)
    local CELL, grid, cells = 6, {}, {}
    local function cell(v) return math.floor(v / CELL) end
    local function key(i, j) return i * 1000 + j end
    for _, c in ipairs(pts) do
        local i, j = cell(c[1]), cell(c[2])
        local k = key(i, j)
        if not grid[k] then grid[k] = 0; cells[#cells + 1] = { i, j } end
        grid[k] = grid[k] + 1
    end
    local best, bestN
    for _, ij in ipairs(cells) do -- in order of appearance: stable result
        local n = 0
        for di = -1, 1 do for dj = -1, 1 do n = n + (grid[key(ij[1] + di, ij[2] + dj)] or 0) end end
        if not bestN or n > bestN then best, bestN = ij, n end
    end
    local sx, sy, n = 0, 0, 0
    for _, c in ipairs(pts) do
        if math.abs(cell(c[1]) - best[1]) <= 1 and math.abs(cell(c[2]) - best[2]) <= 1 then
            sx, sy, n = sx + c[1], sy + c[2], n + 1
        end
    end
    return math.floor(sx / n * 10 + 0.5) / 10, math.floor(sy / n * 10 + 0.5) / 10
end

local function stepFrom(name, spawnsByZone)
    local bestZone, bestPts
    for zone, list in pairs(spawnsByZone) do
        if not bestPts or #list > #bestPts or (#list == #bestPts and zone < bestZone) then bestZone, bestPts = zone, list end
    end
    if not bestZone or not name then return nil end
    local valid = {}
    for _, c in ipairs(bestPts) do if c[1] and c[1] >= 0 then valid[#valid + 1] = c end end
    local zone = (areaOf[bestZone] and areaOf[bestZone]) or bestZone
    if #valid == 0 then return ("{ name = %s, area = %d }"):format(lua(name), zone) end
    local x, y = densest(valid)
    return ("{ name = %s, area = %d, x = %.1f, y = %.1f }"):format(lua(name), bestZone, x, y)
end

local function stepsOf(q)
    local steps = {}
    local function add(s) if s and #steps < MAX_STEPS then steps[#steps + 1] = s end end
    local obj = q[Q_OBJ] or {}
    for _, o in ipairs(obj[1] or {}) do
        local n = npcs[o[1]]
        if n then local acc = {}; addSpawns(acc, n[N_SPAWNS]); add(stepFrom(o[2] or n[N_NAME], acc)) end
    end
    for _, o in ipairs(obj[2] or {}) do
        local ob = objects[o[1]]
        if ob then local acc = {}; addSpawns(acc, ob[O_SPAWNS]); add(stepFrom(o[2] or ob[O_NAME], acc)) end
    end
    for _, o in ipairs(obj[3] or {}) do
        local it = items[o[1]]
        if it then
            local acc, used = {}, 0
            for _, npcId in ipairs(it[I_NPCDROPS] or {}) do
                if used < MAX_SOURCES and npcs[npcId] then addSpawns(acc, npcs[npcId][N_SPAWNS]); used = used + 1 end
            end
            for _, objId in ipairs(it[I_OBJDROPS] or {}) do
                if used < MAX_SOURCES and objects[objId] then addSpawns(acc, objects[objId][O_SPAWNS]); used = used + 1 end
            end
            add(stepFrom(it[I_NAME], acc))
        end
    end
    for _, o in ipairs(obj[5] or {}) do -- killCredit: { {npcs}, base npc, text }
        local acc = {}
        for _, npcId in ipairs(o[1] or {}) do if npcs[npcId] then addSpawns(acc, npcs[npcId][N_SPAWNS]) end end
        local base = npcs[o[2]]
        add(stepFrom(o[3] or (base and base[N_NAME]), acc))
    end
    local trigger = q[9]
    if type(trigger) == "table" and type(trigger[2]) == "table" then
        local acc = {}
        addSpawns(acc, trigger[2])
        add(stepFrom(trigger[1], acc))
    end
    return steps
end

-- A quest data line (Lua table). Exact factions -> faction; other race restrictions -> races; class
-- restrictions -> classes (except in class entries, where they are the reason for being there).
local function questLine(id, name, comment, noClasses)
    local q = quests[id]
    local f = { "id = " .. id, "name = " .. lua(name) }
    if q[Q_LVL] and q[Q_LVL] > 0 then f[#f + 1] = "level = " .. q[Q_LVL] end
    if q[Q_MINLVL] and q[Q_MINLVL] > 0 then f[#f + 1] = "minLevel = " .. q[Q_MINLVL] end
    local group, single = {}, {}
    for _, p in ipairs(q[Q_PREGROUP] or {}) do group[#group + 1] = p end
    for _, p in ipairs(q[Q_PRESINGLE] or {}) do single[#single + 1] = p end
    if #single == 1 then group[#group + 1] = single[1]; single = {} end
    if #group > 0 then f[#f + 1] = "requires = " .. ids(group) end
    if #single > 1 then f[#f + 1] = "requiresAny = " .. ids(single) end
    local races = raceMask(id)
    if races == ALLIANCE then f[#f + 1] = 'faction = "Alliance"'
    elseif races == HORDE then f[#f + 1] = 'faction = "Horde"'
    elseif races then f[#f + 1] = "races = " .. races end
    local classes = classMask(id)
    if classes and not noClasses then f[#f + 1] = "classes = " .. classes end
    if dungeonOf[id] then f[#f + 1] = "dungeon = " .. lua(dungeonOf[id]) end
    local giver = q[Q_START] and q[Q_START][1] and q[Q_START][1][1]
    if giver and npcs[giver] then f[#f + 1] = "giver = " .. lua(npcs[giver][N_NAME]) end
    local finisher = q[Q_END] and q[Q_END][1] and q[Q_END][1][1]
    if giver and npcs[giver] then f[#f + 1] = "start = " .. location(giver) end
    if finisher and npcs[finisher] then f[#f + 1] = "finish = " .. location(finisher) end
    local steps = stepsOf(q)
    if #steps > 0 then f[#f + 1] = "steps = { " .. table.concat(steps, ", ") .. " }" end
    local text = q[Q_TEXT] and table.concat(q[Q_TEXT], " ")
    if text and text ~= "" then f[#f + 1] = "objective = " .. lua(text) end
    return ("    { %s },%s"):format(table.concat(f, ", "), comment or "")
end

-- "zones" mode: one entry per zone, class, profession and race, each quest in a single entry.
if arg[1] == "zones" then
    local OUT_Z, OUT_C = ROOT .. "/Data/Generated/Zones.lua", ROOT .. "/Data/Generated/Classes.lua"
    local OUT_R = ROOT .. "/Data/Generated/Races.lua"

    -- zones with a map in Classic (uiMapId 1411..1459) and their name, according to Questie
    local zoneName = {}
    for line in read(Q .. "Database/Zones/data/uiMapIdToAreaId.lua"):gmatch("[^\n]+") do
        local ui, area, name = line:match("^%s*%[(%d+)%]%s*=%s*(%d+),%s*%-%-%s*(.-)%s*$")
        ui, area = tonumber(ui), tonumber(area)
        if ui and ui >= 1411 and ui <= 1459 and area > 0 and area < 10000 then zoneName[area] = name end
    end
    zoneName[2597] = nil -- Alterac Valley: a battleground

    -- subzones (mostly starting ones) -> their zone
    local parent = { [9] = 12, [132] = 1, [188] = 141, [154] = 85, [363] = 14, [220] = 215 }
    for line in read(Q .. "Database/Zones/data/subZoneToParentZone.lua"):gmatch("[^\n]+") do
        local s, p = line:match("^%s*%[(%d+)%]%s*=%s*(%d+),")
        if s and not parent[tonumber(s)] then parent[tonumber(s)] = tonumber(p) end
    end

    local CLASS_SORT = { [-61] = "WARLOCK", [-81] = "WARRIOR", [-82] = "SHAMAN", [-141] = "PALADIN", [-161] = "MAGE",
        [-162] = "ROGUE", [-261] = "HUNTER", [-262] = "PRIEST", [-263] = "DRUID" }
    local CLASS_MASK = { [1] = "WARRIOR", [2] = "PALADIN", [4] = "HUNTER", [8] = "ROGUE", [16] = "PRIEST",
        [64] = "SHAMAN", [128] = "MAGE", [256] = "WARLOCK", [1024] = "DRUID" }
    local CLASS_NAME = { WARRIOR = "Warrior", PALADIN = "Paladin", HUNTER = "Hunter", ROGUE = "Rogue", PRIEST = "Priest",
        SHAMAN = "Shaman", MAGE = "Mage", WARLOCK = "Warlock", DRUID = "Druid" }

    -- Professions: by Questie's category (negative QuestSort) or by the profession the quest requires
    -- (requiredSkill field, 18). Key: the game's skill line id.
    local PROF_SORT = { [-24] = 182, [-101] = 356, [-121] = 164, [-181] = 171, [-182] = 165, [-201] = 202,
        [-264] = 197, [-304] = 185, [-324] = 129 }
    local PROF_NAME = { [164] = "Blacksmithing", [165] = "Leatherworking", [171] = "Alchemy", [182] = "Herbalism",
        [185] = "Cooking", [186] = "Mining", [197] = "Tailoring", [202] = "Engineering", [333] = "Enchanting",
        [356] = "Fishing", [129] = "First Aid", [393] = "Skinning" }
    local profSet = {}
    for id, q in pairs(quests) do
        local skill = PROF_SORT[q[Q_ZONE] or 0] or (q[18] and PROF_NAME[q[18][1]] and q[18][1])
        if skill then
            profSet[skill] = profSet[skill] or {}
            profSet[skill][id] = true
        end
    end

    local zoneSet, classSet = {}, {}
    for id, q in pairs(quests) do
        local z = q[Q_ZONE]
        local class = CLASS_SORT[z or 0] or CLASS_MASK[classMask(id) or 0]
        if class then
            classSet[class] = classSet[class] or {}
            classSet[class][id] = true
        elseif z and z > 0 and not areaOf[z] then
            local area = zoneName[z] and z or parent[z]
            if area and zoneName[area] then
                zoneSet[area] = zoneSet[area] or {}
                zoneSet[area][id] = true
            end
        end
    end

    -- rough level of an entry: 10th percentile of the required level and 90th of the quest level
    local function levelRange(set)
        local req, lvl = {}, {}
        for id in pairs(set) do
            local q = quests[id]
            if q[Q_MINLVL] and q[Q_MINLVL] > 0 then req[#req + 1] = q[Q_MINLVL] end
            if q[Q_LVL] and q[Q_LVL] > 0 then lvl[#lvl + 1] = q[Q_LVL] end
        end
        table.sort(req); table.sort(lvl)
        local lo = req[math.max(1, math.ceil(#req * 0.1))] or 1
        local hi = lvl[math.max(1, math.ceil(#lvl * 0.9))] or lo
        return lo, math.max(lo, hi)
    end

    local function emitEntry(out, entryId, header, set, noClasses)
        local sorted = {}
        for id in pairs(set) do sorted[#sorted + 1] = id end
        table.sort(sorted)
        local names = displayNames(set)
        out[#out + 1] = header
        out[#out + 1] = ("ns.AddQuests(%s, {"):format(lua(entryId))
        for _, id in ipairs(sorted) do out[#out + 1] = questLine(id, names[id], nil, noClasses) end
        out[#out + 1] = "})"
        out[#out + 1] = ""
        return #sorted
    end

    local zout = { "local _, ns = ...", "", "-- GENERATED by tools/questie_classic.lua zones from Questie's Classic database.",
        "-- Do not edit by hand: use Data/Overrides.lua.", "" }
    local zones = {}
    for area, set in pairs(zoneSet) do
        local lo, hi = levelRange(set)
        zones[#zones + 1] = { area = area, name = zoneName[area], set = set, lo = lo, hi = hi }
    end
    table.sort(zones, function(a, b) if a.lo ~= b.lo then return a.lo < b.lo end return a.name < b.name end)
    local totalZ = 0
    for _, z in ipairs(zones) do
        local entryId = "z" .. z.area
        local n = emitEntry(zout, entryId, ("ns.RegisterEntry({ id = %s, name = %s, category = \"zones\", area = %d, minLevel = %d, maxLevel = %d })")
            :format(lua(entryId), lua(z.name), z.area, z.lo, z.hi), z.set)
        totalZ = totalZ + n
        print(("zone   %-24s lv %2d-%2d  %3d quests"):format(z.name, z.lo, z.hi, n))
    end
    local fz = assert(io.open(OUT_Z, "wb")); fz:write(table.concat(zout, "\n")); fz:close()

    local cout = { "local _, ns = ...", "", "-- GENERATED by tools/questie_classic.lua zones from Questie's Classic database.",
        "-- Do not edit by hand: use Data/Overrides.lua.", "" }
    local order = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
    local totalC = 0
    for _, class in ipairs(order) do
        if classSet[class] then
            local entryId = "c_" .. class
            local n = emitEntry(cout, entryId, ("ns.RegisterEntry({ id = %s, name = %s, category = \"classes\", classFile = %s })")
                :format(lua(entryId), lua(CLASS_NAME[class]), lua(class)), classSet[class], true)
            totalC = totalC + n
            print(("class  %-24s %3d quests"):format(CLASS_NAME[class], n))
        end
    end
    local fc = assert(io.open(OUT_C, "wb")); fc:write(table.concat(cout, "\n")); fc:close()

    local pout = { "local _, ns = ...", "", "-- GENERATED by tools/questie_classic.lua zones from Questie's Classic database.",
        "-- Do not edit by hand: use Data/Overrides.lua.", "" }
    local skills = {}
    for skill in pairs(profSet) do skills[#skills + 1] = skill end
    table.sort(skills, function(a, b) return PROF_NAME[a] < PROF_NAME[b] end)
    local totalP = 0
    for _, skill in ipairs(skills) do
        local entryId = "p_" .. skill
        local lo, hi = levelRange(profSet[skill])
        local n = emitEntry(pout, entryId, ("ns.RegisterEntry({ id = %s, name = %s, category = \"professions\", skillLine = %d, minLevel = %d, maxLevel = %d })")
            :format(lua(entryId), lua(PROF_NAME[skill]), skill, lo, hi), profSet[skill])
        totalP = totalP + n
        print(("prof.  %-24s %3d quests"):format(PROF_NAME[skill], n))
    end
    local OUT_P = ROOT .. "/Data/Generated/Professions.lua"
    local fp = assert(io.open(OUT_P, "wb")); fp:write(table.concat(pout, "\n")); fp:close()
    print(("written %s (%d quests)"):format(OUT_P, totalP))

    -- Races: quests of one or a few races (not of a whole faction) also appear in the entry of each race
    -- included; in the zones only members of that race see them.
    local RACES = { "Human", "Orc", "Dwarf", "Night Elf", "Undead", "Tauren", "Gnome", "Troll" }
    local raceSet = {}
    for _, set in pairs(zoneSet) do
        for id in pairs(set) do
            local m = raceMask(id)
            if m and m ~= ALLIANCE and m ~= HORDE then
                local bits = {}
                for bit = 0, 7 do
                    if (m >> bit) & 1 == 1 then bits[#bits + 1] = bit + 1 end
                end
                if #bits <= 3 then
                    for _, r in ipairs(bits) do
                        raceSet[r] = raceSet[r] or {}
                        raceSet[r][id] = true
                    end
                end
            end
        end
    end
    local rout = { "local _, ns = ...", "", "-- GENERATED by tools/questie_classic.lua zones from Questie's Classic database.",
        "-- Do not edit by hand: use Data/Overrides.lua.", "" }
    local totalR = 0
    for r, name in ipairs(RACES) do
        if raceSet[r] then
            local entryId = "r_" .. r
            local n = emitEntry(rout, entryId, ("ns.RegisterEntry({ id = %s, name = %s, category = \"races\", raceId = %d })")
                :format(lua(entryId), lua(name), r), raceSet[r])
            totalR = totalR + n
            print(("race   %-24s %3d quests"):format(name, n))
        end
    end
    local fr = assert(io.open(OUT_R, "wb")); fr:write(table.concat(rout, "\n")); fr:close()
    print(("written %s (%d zones, %d quests), %s (%d quests) and %s (%d quests)"):format(OUT_Z, #zones, totalZ, OUT_C, totalC, OUT_R, totalR))
    os.exit(0)
end

local wanted = { table.unpack(arg) }
if #wanted == 0 then wanted = { "vc", "wc" } end

local out = { "local _, ns = ...", "", "-- GENERATED by tools/questie_classic.lua from Questie's Classic database.",
    "-- Do not edit by hand: use Data/Overrides.lua.", "" }

for _, entry in ipairs(wanted) do
    local area = assert(INSTANCE_AREA[entry], "entrada desconocida: " .. entry)
    local set = collect(area)
    local sorted = {}
    for id in pairs(set) do sorted[#sorted + 1] = id end
    table.sort(sorted)
    local names = displayNames(set)
    out[#out + 1] = ("ns.AddQuests(%s, {"):format(lua(entry))
    local nCore = 0
    for _, id in ipairs(sorted) do
        local isCore = core[area] and core[area][id]
        if isCore then nCore = nCore + 1 end
        out[#out + 1] = questLine(id, names[id], isCore and "" or " -- chain")
    end
    out[#out + 1] = "})"
    out[#out + 1] = ""
    print(("%-5s %3d quests (%d by zone/NPC, %d from chains)"):format(entry, #sorted, nCore, #sorted - nCore))
end

local f = assert(io.open(OUT, "wb")); f:write(table.concat(out, "\n")); f:close()
print("written " .. OUT)

-- Dungeon/raid entrances (parent zone + the portal's coordinates), for every known entry.
local ent = { "local _, ns = ...", "", "-- GENERATED by tools/questie_classic.lua (Questie's dungeons.lua). Do not edit by hand.", "" }
local keys = {}
for entry in pairs(INSTANCE_AREA) do keys[#keys + 1] = entry end
table.sort(keys)
for _, entry in ipairs(keys) do
    local e = entranceOf[INSTANCE_AREA[entry]]
    if e then
        ent[#ent + 1] = ("ns.SetEntrance(%s, { area = %d, x = %.1f, y = %.1f })"):format(lua(entry), e.area, e.x, e.y)
    end
end
local g = assert(io.open(ENTRANCES_OUT, "wb")); g:write(table.concat(ent, "\n") .. "\n"); g:close()
print("written " .. ENTRANCES_OUT)
