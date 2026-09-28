-- Uso: lua tools/questie_classic.lua [entryId ...]     (por defecto: vc wc)
-- Lee la base de datos de Classic que trae Questie y genera Data/Generated/Classic.lua
-- con las quests de cada mazmorra: las de su zona, las que dan/reciben/matan NPCs que solo aparecen
-- dentro, y las cadenas (prerrequisitos y continuaciones) que las conectan.
local ROOT = (arg[0]:match("^(.*)[/\\][^/\\]+$") or ".") .. "/.."
local Q = os.getenv("QUESTIE_DIR") or "D:/Games/World of Warcraft/_classic_beta_/Interface/AddOns/Questie/"
local OUT = ROOT .. "/Data/Generated/Classic.lua"

-- id de entrada del addon -> id de area de la mazmorra en Questie (Database/Zones/data/dungeons.lua)
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

-- areas de cada mazmorra (id principal + alternativos)
local areaOf, entranceOf = {}, {}
for line in read(Q .. "Database/Zones/data/dungeons.lua"):gmatch("[^\n]+") do
    local id, _, rest = line:match('^%s*%[(%d+)%] = {"([^"]+)",(.*)$')
    if id then
        id = tonumber(id)
        areaOf[id] = id
        local alts = rest:match("^(%b{})")
        if alts then for a in alts:gmatch("%d+") do areaOf[tonumber(a)] = id end end
        -- primera entrada: {zona padre, x, y}
        local zone, x, y = rest:match(",%s*%d+,%s*{%s*{%s*(%d+),%s*([%d%.]+),%s*([%d%.]+)")
        if zone then entranceOf[id] = { area = tonumber(zone), x = tonumber(x), y = tonumber(y) } end
    end
end

local Q_NAME, Q_START, Q_END, Q_MINLVL, Q_LVL, Q_RACES, Q_OBJ = 1, 2, 3, 4, 5, 6, 10
local Q_PREGROUP, Q_PRESINGLE, Q_ZONE, Q_NEXT = 12, 13, 17, 22
local N_NAME, N_SPAWNS, N_ZONE = 1, 7, 9
local Q_TEXT = 8

-- Un NPC "pertenece" a una mazmorra si todas sus zonas de spawn son de esa mazmorra.
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

-- indices: nucleo por mazmorra, hijos por prerrequisito
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

-- Prerrequisitos: hasta UP_HOPS pasos hacia atras. Continuaciones: solo DOWN_HOPS pasos hacia delante
-- (mas alla se cuelan cadenas de otras zonas, p.ej. Argent Dawn desde Stratholme). Nunca se cruza a
-- quests que son nucleo de otra mazmorra.
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

-- Quests con el mismo nombre y facción dentro de la mazmorra (cadenas tipo "The Defias Brotherhood")
-- se numeran por orden de la cadena: "Nombre (2/7)".
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

-- Ubicacion de un NPC: zona preferida (la mas comun del NPC) y primera coordenada. Los NPCs dentro
-- de una mazmorra tienen coordenadas -1 y se emiten sin posicion.
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

local ALLIANCE, HORDE = 77, 178

local wanted = { table.unpack(arg) }
if #wanted == 0 then wanted = { "vc", "wc" } end

local out = { "local _, ns = ...", "", "-- GENERADO por tools/questie_classic.lua a partir de la base de datos de Classic de Questie.",
    "-- No editar a mano: usar Data/Overrides.lua.", "" }

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
        local q = quests[id]
        local f = { "id = " .. id, "name = " .. lua(names[id]) }
        if q[Q_LVL] and q[Q_LVL] > 0 then f[#f + 1] = "level = " .. q[Q_LVL] end
        if q[Q_MINLVL] and q[Q_MINLVL] > 0 then f[#f + 1] = "minLevel = " .. q[Q_MINLVL] end
        local group, single = {}, {}
        for _, p in ipairs(q[Q_PREGROUP] or {}) do group[#group + 1] = p end
        for _, p in ipairs(q[Q_PRESINGLE] or {}) do single[#single + 1] = p end
        if #single == 1 then group[#group + 1] = single[1]; single = {} end
        if #group > 0 then f[#f + 1] = "requires = " .. ids(group) end
        if #single > 1 then f[#f + 1] = "requiresAny = " .. ids(single) end
        if q[Q_RACES] == ALLIANCE then f[#f + 1] = 'faction = "Alliance"'
        elseif q[Q_RACES] == HORDE then f[#f + 1] = 'faction = "Horde"' end
        local giver = q[Q_START] and q[Q_START][1] and q[Q_START][1][1]
        if giver and npcs[giver] then f[#f + 1] = "giver = " .. lua(npcs[giver][N_NAME]) end
        local finisher = q[Q_END] and q[Q_END][1] and q[Q_END][1][1]
        if giver and npcs[giver] then f[#f + 1] = "start = " .. location(giver) end
        if finisher and npcs[finisher] then f[#f + 1] = "finish = " .. location(finisher) end
        local text = q[Q_TEXT] and table.concat(q[Q_TEXT], " ")
        if text and text ~= "" then f[#f + 1] = "objective = " .. lua(text) end
        local isCore = core[area] and core[area][id]
        if isCore then nCore = nCore + 1 end
        out[#out + 1] = ("    { %s },%s"):format(table.concat(f, ", "), isCore and "" or " -- cadena")
    end
    out[#out + 1] = "})"
    out[#out + 1] = ""
    print(("%-5s %3d quests (%d por zona/NPC, %d de cadena)"):format(entry, #sorted, nCore, #sorted - nCore))
end

local f = assert(io.open(OUT, "wb")); f:write(table.concat(out, "\n")); f:close()
print("escrito " .. OUT)

-- Entradas de las mazmorras/raids (zona padre + coordenadas del portal), para todas las entradas conocidas.
local ent = { "local _, ns = ...", "", "-- GENERADO por tools/questie_classic.lua (dungeons.lua de Questie). No editar a mano.", "" }
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
print("escrito " .. ENTRANCES_OUT)
