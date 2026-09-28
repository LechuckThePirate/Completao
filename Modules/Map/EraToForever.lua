local _, ns = ...

-- Forever redrew the maps of a few zones, so map coordinates (0-100) changed there while the world
-- positions stayed the same. The addon's data is in Era (Classic) coordinates, so the points in those
-- zones are converted to Forever's when the data is registered (Modules/Database/Entries.lua).
-- The transform per AreaTable id is Questie's own (QuestieDB/src/support/eraToForever.lua, from the
-- difference between the two client builds' map bounds): x' = x * sx + ox, y' = y * sy + oy.
-- Questie's Forever database has the NPC spawns already converted; those match this to <0.6 points.
local TRANSFORMS = {
    [215]  = { 0.8348002068275978, 7.007453108736848, 0.8349418225477033, 13.15387327724201 },  -- Mulgore
    [139]  = { 0.8997577709204458, -1.6464926382438023, 0.9004358590984077, -3.7790494664060477 }, -- Eastern Plaguelands
    [44]   = { 0.9999996626080551, -5.086374584221827, 1.0, 0.0 },                              -- Redridge Mountains
    [1519] = { 0.7736792385183993, 19.680449646264936, 0.773826866980289, 24.433287807510073 }, -- Stormwind City
}

local function round1(v) return math.floor(v * 10 + 0.5) / 10 end

-- Converts one point; areas without a transform (and instance sentinels) pass through unchanged.
function ns.EraToForever(area, x, y)
    local t = TRANSFORMS[area]
    if not t or not x or not y or x < 0 or y < 0 then return x, y end
    return round1(x * t[1] + t[2]), round1(y * t[3] + t[4])
end

-- Converts a location table { area = , x = , y = } in place, once (marked so it isn't converted twice).
function ns.ConvertLocation(loc)
    if type(loc) ~= "table" or loc.forever or not loc.area or not loc.x then return loc end
    loc.x, loc.y = ns.EraToForever(loc.area, loc.x, loc.y)
    loc.forever = true
    return loc
end
