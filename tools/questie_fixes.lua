-- Applies to the Classic database the "corrections" Questie applies on top of it (levels, prerequisites,
-- races, classes, zones...), by running its Database/Corrections/classicQuestFixes.lua outside the game with
-- Questie's constants simulated. The file returns a different table per faction: both are applied.
-- Usage: local apply = dofile("tools/questie_fixes.lua"); apply(quests, questieDir)
return function(quests, Q)
    local function read(p) local f = assert(io.open(p, "rb")); local s = f:read("a"); f:close(); return s end

    -- simple "NAME = number" enumerations inside a `header ... }` block
    local function enum(path, header)
        local src = read(path)
        local s = assert(src:find(header, 1, true), "no se encuentra " .. header)
        local body = src:sub(s + #header):match("^(.-)\n}") or ""
        local t = {}
        for name, num in body:gmatch("([%w_]+)%s*=%s*(%-?%d+)") do t[name] = tonumber(num) end
        return t
    end

    -- a quest's field keys (questKeys.name = 1, ...)
    local questKeys = {}
    do
        local src = read(Q .. "Database/Classic/classicQuestDB.lua")
        local body = src:match("QuestieDB%.questKeys = {(.-)\n}")
        for name, idx in body:gmatch("%['(%w+)'%]%s*=%s*(%d+)") do questKeys[name] = tonumber(idx) end
    end

    local function anything() return setmetatable({}, { __index = function() return 0 end }) end
    local modules = {}
    QuestieLoader = {
        CreateModule = function(_, name) modules[name] = modules[name] or {}; return modules[name] end,
        ImportModule = function(_, name) return modules[name] end,
    }
    modules.QuestieDB = {
        questKeys = questKeys,
        sortKeys = enum(Q .. "Database/Constants.lua", "QuestieDB.sortKeys = {"),
        factionIDs = enum(Q .. "Database/questDB.lua", "QuestieDB.factionIDs = {"),
        specialFlags = { NONE = 0, REPEATABLE = 1, MONTHLY = 65536 },
        raceKeys = { ALL_ALLIANCE = 77, ALL_HORDE = 178, NONE = 0, HUMAN = 1, ORC = 2, DWARF = 4, NIGHT_ELF = 8,
            UNDEAD = 16, TAUREN = 32, GNOME = 64, TROLL = 128 },
        classKeys = { ALL_CLASSES = 1503, NONE = 0, WARRIOR = 1, PALADIN = 2, HUNTER = 4, ROGUE = 8, PRIEST = 16,
            DEATH_KNIGHT = 32, SHAMAN = 64, MAGE = 128, WARLOCK = 256, MONK = 512, DRUID = 1024 },
    }
    modules.ZoneDB = { zoneIDs = enum(Q .. "Database/Zones/data/zoneIds.lua", "ZoneDB.zoneIDs = {") }
    modules.QuestieProfessions = { professionKeys = anything(), specializationKeys = anything(), rankNames = anything() }
    modules.QuestieCorrections = { itemObjectiveFirst = {} }
    modules.l10n = setmetatable({}, { __call = function(_, s) return s end, __index = function() return function(_, s) return s end end })
    Questie = { IsClassic = true }
    UnitClass = function() return "Mage", "MAGE", 8 end

    local faction = "Alliance"
    UnitFactionGroup = function() return faction end
    assert(loadfile(Q .. "Database/Corrections/classicQuestFixes.lua"))()
    local fixes = modules.QuestieQuestFixes

    local changed, fields = {}, 0
    for _, f in ipairs({ "Alliance", "Horde" }) do
        faction = f
        for id, fix in pairs(fixes:Load()) do
            local q = quests[id]
            if q then
                for k, v in pairs(fix) do
                    if type(k) == "number" then q[k] = v; fields = fields + 1; changed[id] = true end
                end
            end
        end
    end
    local n = 0
    for _ in pairs(changed) do n = n + 1 end
    return n, fields
end
