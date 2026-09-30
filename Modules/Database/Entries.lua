local ADDON, ns = ...

-- Entries (a dungeon, a zone, a class...) and their quests. The Data/ files register them while loading:
-- ns.RegisterEntry, ns.AddQuests, ns.SetEntrance; Data/Overrides.lua fixes them with ns.PatchQuest.
ns.entries = {}
ns.entryList = {}

-- Sections of the side panel, in order. To add one: add it here and register entries with
-- category = "<id>". The icon is what the side panel shows when it is collapsed.
local ICONS = "Interface\\Icons\\"
ns.categories = {
    { id = "dungeons", name = ns.L["Dungeons"], sortByLevel = true, icon = "Interface\\AddOns\\" .. ADDON .. "\\Icons\\Dungeon.png" },
    { id = "raids",    name = ns.L["Raids"], sortByLevel = true, icon = ICONS .. "INV_Misc_Head_Dragon_01" },
    { id = "battlegrounds", name = ns.L["Battlegrounds"], icon = ICONS .. "INV_BannerPVP_02" },
    { id = "zones",    name = ns.L["Zones"], icon = ICONS .. "INV_Misc_Map_01" },
    { id = "classes",  name = ns.L["Class Quests"], icon = ICONS .. "INV_Misc_Book_09" },
    { id = "professions", name = ns.L["Professions"], icon = ICONS .. "Trade_Blacksmithing" },
    { id = "races",    name = ns.L["Races"], icon = ICONS .. "INV_Misc_Head_Human_01" },
    { id = "events",   name = ns.L["Events"], icon = ICONS .. "INV_Misc_Gift_01" },
    { id = "misc",     name = ns.L["Miscellaneous"], icon = ICONS .. "INV_Misc_QuestionMark" },
}

-- Name shown for an entry: classes, zones, races and professions use the client's name (its language).
function ns.EntryName(d)
    if d.classFile and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[d.classFile] then
        return LOCALIZED_CLASS_NAMES_MALE[d.classFile]
    end
    if (d.category == "zones" or d.category == "battlegrounds") and d.area and C_Map and C_Map.GetAreaInfo then
        return C_Map.GetAreaInfo(d.area) or d.name
    end
    if d.skillLine and C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName then
        local ok, name = pcall(C_TradeSkillUI.GetTradeSkillDisplayName, d.skillLine)
        if ok and name and name ~= "" then return name end
    end
    if d.raceId and C_CreatureInfo and C_CreatureInfo.GetRaceInfo then
        local info = C_CreatureInfo.GetRaceInfo(d.raceId)
        if info and info.raceName then return info.raceName end
    end
    return d.name
end

-- Shape of an entry (dungeon, raid...):
-- { id = "deadmines", name = "...", category = "dungeons" (default), minLevel = 15, maxLevel = 20,
--   quests = { { id = 123, name = "fallback", level = 17, minLevel = 15,
--                requires = { 122 }, faction = "Alliance"|"Horde"|nil,
--                giver = "NPC (zone)", note = "free text" }, ... } }
function ns.RegisterEntry(d)
    d.quests = d.quests or {}
    d.category = d.category or "dungeons"
    ns.entries[d.id] = d
    ns.entryList[#ns.entryList + 1] = d
end

-- The same quest can be in several entries (e.g. its zone and the dungeon): every copy is kept by id
-- to find it fast and patch them all together.
local copies = {}

function ns.AddQuests(entryId, list)
    local e = ns.entries[entryId]
    if not e then return end
    for _, q in ipairs(list) do
        q.entryId = q.entryId or entryId
        e.quests[#e.quests + 1] = q
        local c = copies[q.id]
        if c then c[#c + 1] = q else copies[q.id] = { q } end
    end
end

-- Where the instance's door is: { area = <AreaTable id>, x = , y = } (x, y optional).
function ns.SetEntrance(entryId, loc)
    local e = ns.entries[entryId]
    if e then e.entrance = loc end
end

-- Hand fixes over generated data (Data/Overrides.lua): ns.PatchQuest(id, { requires = {...} }).
-- A false value removes the field.
function ns.PatchQuest(id, fields)
    for _, q in ipairs(copies[id] or {}) do
        for k, v in pairs(fields) do
            q[k] = (v ~= false) and v or nil
        end
    end
end

function ns.FindQuestDef(id)
    local c = copies[id]
    return c and c[1]
end

-- Whether the quest is also listed in an entry of that section (a quest can sit in several entries).
function ns.QuestIsIn(id, category)
    for _, q in ipairs(copies[id] or {}) do
        local e = ns.entries[q.entryId]
        if e and e.category == category then return true end
    end
    return false
end

-- Skill lines (the client's profession ids) that the character has learned, as a set; nil when the client can't
-- tell. The retail-style API gives the ids; the classic one only the names, compared with the skill's name.
local function knownSkillLines()
    if GetProfessions and GetProfessionInfo then
        local set, list = {}, { GetProfessions() }
        for i = 1, 6 do
            if list[i] then
                local skillLine = select(7, GetProfessionInfo(list[i]))
                if skillLine then set[skillLine] = true end
            end
        end
        return set
    end
end

-- true / false: the character has / lacks that profession; nil when it can't be told (then nothing is hidden).
function ns.HasProfession(skillLine)
    local set = knownSkillLines()
    if set then return set[skillLine] or false end
    if GetNumSkillLines and GetSkillLineInfo and C_TradeSkillUI and C_TradeSkillUI.GetTradeSkillDisplayName then
        local ok, name = pcall(C_TradeSkillUI.GetTradeSkillDisplayName, skillLine)
        if not (ok and name) then return nil end
        for i = 1, GetNumSkillLines() do
            local lineName, isHeader = GetSkillLineInfo(i)
            if not isHeader and lineName == name then return true end
        end
        return false
    end
    return nil
end

-- Professions whose items the crafting writs ask for (Forever's "Crafting" entry has no skill line of its own):
-- alchemy, blacksmithing, enchanting, engineering, leatherworking, tailoring, cooking.
local CRAFTING_SKILLS = { 171, 164, 333, 202, 165, 197, 185 }

-- A profession's quests are for those who have it: true / false, nil when it can't be told.
local function canDoProfession(d)
    if d.skillLine then return ns.HasProfession(d.skillLine) end
    local unknown = true
    for _, skillLine in ipairs(CRAFTING_SKILLS) do
        local has = ns.HasProfession(skillLine)
        if has then return true end
        if has ~= nil then unknown = false end
    end
    if unknown then return nil end
    return false
end

-- Instances are entered some levels before their own (a quest, or the pre-quest, can come earlier): a quest of a
-- dungeon, raid or battleground isn't "to do" for someone this many levels under the instance's minimum. It
-- catches the ones open from level 1 that can only be taken inside (Alterac Valley's "Launch the Attack!").
local INSTANCE_CATEGORIES = { dungeons = true, raids = true, battlegrounds = true }
local INSTANCE_SLACK = 10

-- Whether an entry has anything left to do for the character: a quest they can see that is in their log or
-- available now (not done, not locked by level or by quests they lack). Stops at the first one. Out of it:
--  * holiday quests outside the events section: the ones also listed there (the Lunar Festival elders stand in
--    instances: level 60, but from level 1) and the ones marked `holiday` in Data/Overrides.lua;
--  * the quests of an instance far above the character's level;
--  * a profession's quests, without that profession.
function ns.EntryHasWork(d)
    if d.category == "professions" and canDoProfession(d) == false then return false end
    if INSTANCE_CATEGORIES[d.category] and UnitLevel("player") < (d.minLevel or 0) - INSTANCE_SLACK then return false end
    local isEvents = d.category == "events"
    for _, q in ipairs(d.quests) do
        if ns.QuestVisible(q, d) and ns.IsQuestAvailable(q) and (isEvents or not (q.holiday or ns.QuestIsIn(q.id, "events"))) then
            return true
        end
    end
    return false
end

-- Progress of an entry: quests done / quests the character can see.
function ns.EntryProgress(d)
    local done, total = 0, 0
    for _, q in ipairs(d.quests) do
        if ns.QuestVisible(q, d) then
            total = total + 1
            if C_QuestLog.IsQuestFlaggedCompleted(q.id) then
                done = done + 1
            end
        end
    end
    return done, total
end
