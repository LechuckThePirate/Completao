-- Uso: lua tools/questie_classic.lua [entryId ...]     (mazmorras/raids; por defecto: vc wc)
--      lua tools/questie_classic.lua zones             (zonas y clases: Zones.lua y Classes.lua)
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

-- Las correcciones que Questie aplica encima de la base (prerrequisitos, niveles, razas, clases, zonas...)
do
    local nFixed, nFields = dofile(ROOT .. "/tools/questie_fixes.lua")(quests, Q)
    print(("correcciones de Questie aplicadas: %d quests, %d campos"):format(nFixed, nFields))
end

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

local ALLIANCE, HORDE, ALL_RACES = 77, 178, 255

-- Mascaras efectivas de clase (campo 7) y de raza (campo 6): la propia de la quest o, si no tiene, la que
-- hereda de sus prerrequisitos obligatorios (interseccion). Asi una quest que exige una quest solo de
-- Horda, o de una clase, es tambien solo de esa faccion o clase.
local function inheritedMask(field)
    local memo = {}
    local function mask(id, depth)
        if memo[id] ~= nil then return memo[id] end
        memo[id] = false -- corta ciclos
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

-- Quests que se hacen dentro de una mazmorra o raid de las nuestras (su zona, o algun NPC que da, recibe o
-- mata, solo existe dentro): se marcan con dungeon = "<id de la entrada>", tambien cuando salen en una zona.
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

-- Una linea de datos de quest (tabla Lua). Facciones exactas -> faction; otras restricciones de raza -> races;
-- restricciones de clase -> classes (salvo en las entradas de clase, donde son la razon de estar ahi).
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
    local text = q[Q_TEXT] and table.concat(q[Q_TEXT], " ")
    if text and text ~= "" then f[#f + 1] = "objective = " .. lua(text) end
    return ("    { %s },%s"):format(table.concat(f, ", "), comment or "")
end

-- Modo "zones": una entrada por zona y una por clase, cada quest en una sola entrada.
if arg[1] == "zones" then
    local OUT_Z, OUT_C = ROOT .. "/Data/Generated/Zones.lua", ROOT .. "/Data/Generated/Classes.lua"
    local OUT_R = ROOT .. "/Data/Generated/Races.lua"

    -- zonas con mapa en Classic (uiMapId 1411..1459) y su nombre, segun Questie
    local zoneName = {}
    for line in read(Q .. "Database/Zones/data/uiMapIdToAreaId.lua"):gmatch("[^\n]+") do
        local ui, area, name = line:match("^%s*%[(%d+)%]%s*=%s*(%d+),%s*%-%-%s*(.-)%s*$")
        ui, area = tonumber(ui), tonumber(area)
        if ui and ui >= 1411 and ui <= 1459 and area > 0 and area < 10000 then zoneName[area] = name end
    end
    zoneName[2597] = nil -- Alterac Valley: campo de batalla

    -- subzonas (sobre todo las de inicio) -> su zona
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

    -- nivel orientativo de una entrada: percentil 10 del nivel requerido y 90 del nivel de quest
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

    local zout = { "local _, ns = ...", "", "-- GENERADO por tools/questie_classic.lua zones a partir de la base de datos de Classic de Questie.",
        "-- No editar a mano: usar Data/Overrides.lua.", "" }
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
        print(("zona  %-24s nv %2d-%2d  %3d quests"):format(z.name, z.lo, z.hi, n))
    end
    local fz = assert(io.open(OUT_Z, "wb")); fz:write(table.concat(zout, "\n")); fz:close()

    local cout = { "local _, ns = ...", "", "-- GENERADO por tools/questie_classic.lua zones a partir de la base de datos de Classic de Questie.",
        "-- No editar a mano: usar Data/Overrides.lua.", "" }
    local order = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }
    local totalC = 0
    for _, class in ipairs(order) do
        if classSet[class] then
            local entryId = "c_" .. class
            local n = emitEntry(cout, entryId, ("ns.RegisterEntry({ id = %s, name = %s, category = \"classes\", classFile = %s })")
                :format(lua(entryId), lua(CLASS_NAME[class]), lua(class)), classSet[class], true)
            totalC = totalC + n
            print(("clase %-24s %3d quests"):format(CLASS_NAME[class], n))
        end
    end
    local fc = assert(io.open(OUT_C, "wb")); fc:write(table.concat(cout, "\n")); fc:close()

    -- Razas: las quests de una o pocas razas (no las de toda una faccion) aparecen tambien en la entrada de
    -- cada raza incluida; en las zonas solo las ve quien es de esa raza.
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
    local rout = { "local _, ns = ...", "", "-- GENERADO por tools/questie_classic.lua zones a partir de la base de datos de Classic de Questie.",
        "-- No editar a mano: usar Data/Overrides.lua.", "" }
    local totalR = 0
    for r, name in ipairs(RACES) do
        if raceSet[r] then
            local entryId = "r_" .. r
            local n = emitEntry(rout, entryId, ("ns.RegisterEntry({ id = %s, name = %s, category = \"races\", raceId = %d })")
                :format(lua(entryId), lua(name), r), raceSet[r])
            totalR = totalR + n
            print(("raza  %-24s %3d quests"):format(name, n))
        end
    end
    local fr = assert(io.open(OUT_R, "wb")); fr:write(table.concat(rout, "\n")); fr:close()
    print(("escrito %s (%d zonas, %d quests), %s (%d quests) y %s (%d quests)"):format(OUT_Z, #zones, totalZ, OUT_C, totalC, OUT_R, totalR))
    os.exit(0)
end

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
        local isCore = core[area] and core[area][id]
        if isCore then nCore = nCore + 1 end
        out[#out + 1] = questLine(id, names[id], isCore and "" or " -- cadena")
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
