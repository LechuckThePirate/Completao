local _, ns = ...
local C_QuestLog = ns.QuestLog or C_QuestLog -- never the game's table directly (QuestLogCompat.lua)

-- "Consolidate alts", for alt players: the whole addon looks at the account as one. Each character keeps in the
-- account's saved variables (CompletaoDB.chars) its class, race, faction, professions and completed quests (only
-- the ids of the addon's own quests), and with the switch on a quest any of them has done counts as done
-- everywhere (trees, progress, search, the quests it unlocks), and the quests, classes, races and professions of
-- any of them are shown. The level that hides quests as too low or too high is still the played character's, and
-- what is in its own quest log is its own.

local function charKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
end

-- The other characters, as profiles for the visibility rules (QuestState.lua): rebuilt when one is recorded.
local alts

local function store()
    if not ns.db then return nil end
    ns.db.chars = ns.db.chars or {}
    local key = charKey()
    local me = ns.db.chars[key]
    if not me then
        me = { done = {} }
        ns.db.chars[key] = me
    end
    local _, classFile, classId = UnitClass("player")
    me.name = UnitName("player")
    me.realm = GetRealmName and GetRealmName() or nil
    me.class, me.classId = classFile, classId
    me.raceId = select(3, UnitRace("player"))
    me.faction = UnitFactionGroup("player")
    alts = nil
    return me
end

-- The professions the character has, among the addon's profession entries (nil when the client can't tell).
local function recordSkills(me)
    local skills, known = {}, false
    for _, d in ipairs(ns.entryList) do
        if d.skillLine then
            local has = ns.HasProfession(d.skillLine)
            if has ~= nil then known = true end
            if has then skills[d.skillLine] = true end
        end
    end
    if known then me.skills = skills end
end

-- Reads the character's completed quests, among the addon's: done when entering the world, after the game's
-- own list is in.
function ns.Account_Record()
    local me = store()
    if not me then return end
    local done = {}
    for _, d in ipairs(ns.entryList) do
        for _, q in ipairs(d.quests) do
            if not q.repeatable and not done[q.id] and C_QuestLog.IsQuestFlaggedCompleted(q.id) then done[q.id] = true end
        end
    end
    me.done = done
    recordSkills(me)
end

-- A quest the character just turned in (the game's list may not say so yet).
function ns.Account_MarkDone(id)
    local def = id and ns.FindQuestDef(id)
    if not def or def.repeatable then return end
    local me = store()
    if me then me.done[id] = true end
end

-- The "Consolidate alts" switch is on.
function ns.Consolidated()
    return ns.char and ns.char.consolidateAlts and true or false
end

function ns.SetConsolidated(on)
    if not ns.char then return end
    ns.char.consolidateAlts = on and true or nil
    if ns.UI_Refresh then ns.UI_Refresh() end
end

-- The characters whose quests are shown: the one being played first, then, with the switch on, the others.
function ns.Characters()
    local list = { ns.PlayerProfile() }
    if not ns.Consolidated() then return list end
    if not alts then
        alts = {}
        local mine = charKey()
        for key, c in pairs(ns.db and ns.db.chars or {}) do
            if key ~= mine then
                alts[#alts + 1] = { name = c.name or key, classFile = c.class, classId = c.classId, raceId = c.raceId,
                    faction = c.faction, skills = c.skills }
            end
        end
        table.sort(alts, function(a, b) return a.name < b.name end)
    end
    for _, a in ipairs(alts) do list[#list + 1] = a end
    return list
end

-- Whether another character of the account has the profession (with the switch on).
function ns.AltHasProfession(skillLine)
    if not ns.Consolidated() then return false end
    for _, c in ipairs(ns.Characters()) do
        if not c.me and c.skills and c.skills[skillLine] then return true end
    end
    return false
end

-- The name of another character of the account who has done the quest, or nil (the first one by name).
function ns.DoneByAlt(id)
    if not (ns.db and ns.db.chars) then return nil end
    local mine, best = charKey(), nil
    for key, c in pairs(ns.db.chars) do
        if key ~= mine and c.done and c.done[id] then
            local name = c.name or key
            if not best or name < best then best = name end
        end
    end
    return best
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
pcall(events.RegisterEvent, events, "QUEST_TURNED_IN")
pcall(events.RegisterEvent, events, "SKILL_LINES_CHANGED")
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "QUEST_TURNED_IN" then
        ns.Account_MarkDone(arg1)
    elseif event == "SKILL_LINES_CHANGED" then
        local me = store()
        if me then recordSkills(me) end
    else
        -- 1.7.0 had it as a filter, "Account-wide"
        local filters = ns.char and ns.char.filters
        if filters and filters.accountWide then
            ns.char.consolidateAlts, filters.accountWide = true, nil
        end
        ns.Account_Record()
        -- the game may still be loading the list right after logging in
        C_Timer.After(5, ns.Account_Record)
    end
end)
