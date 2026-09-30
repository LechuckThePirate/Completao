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
