local _, ns = ...

-- A quest's state for the character: title, done / in progress / available / locked, low or too high
-- level, whether it is meant for them (class, race, faction) and its long description.

-- Title in the client's language. Chain steps that share a name are numbered in the data
-- ("Hidden Enemies (3/5)"): the number is kept with the game's title too, which lacks it.
function ns.QuestTitle(id, fallback)
    local title = C_QuestLog.GetTitleForQuestID(id)
    if title and title ~= "" then
        local step = fallback and fallback:match(" %(%d+/%d+%)$")
        if step and not title:find(step, 1, true) then title = title .. step end
        return title
    end
    C_QuestLog.RequestLoadQuestByID(id)
    return fallback or ("Quest " .. id)
end

-- In the log with every objective done and not turned in yet.
function ns.IsReadyToTurnIn(id)
    if not C_QuestLog.IsOnQuest(id) or C_QuestLog.IsQuestFlaggedCompleted(id) then return false end
    if C_QuestLog.ReadyForTurnIn then return C_QuestLog.ReadyForTurnIn(id) and true or false end
    if C_QuestLog.IsComplete then return C_QuestLog.IsComplete(id) and true or false end
    return false
end

-- Elite/group quest (the client tags it "(Elite)"): usually one whose objectives involve elite
-- monsters, so it's meant to be done with a group. Asked live to the client, like the title; nil
-- (not cached yet) counts as no, and a load is requested so a later redraw can pick it up.
local ELITE_TAG_ID = 1
function ns.IsEliteQuest(id)
    if not C_QuestLog.GetQuestTagInfo then return false end
    local tagId = C_QuestLog.GetQuestTagInfo(id)
    if tagId == nil then
        C_QuestLog.RequestLoadQuestByID(id)
        return false
    end
    return tagId == ELITE_TAG_ID
end

-- Returns "done" | "active" | "available" | "locked", and a list of reasons when locked.
function ns.QuestStatus(q)
    if C_QuestLog.IsQuestFlaggedCompleted(q.id) then
        return "done"
    end
    if C_QuestLog.IsOnQuest(q.id) then
        return "active"
    end

    local reasons = {}
    if q.minLevel and UnitLevel("player") < q.minLevel then
        reasons[#reasons + 1] = ns.L["Requires level %d (you are %d)"]:format(q.minLevel, UnitLevel("player"))
    end
    for _, reqId in ipairs(q.requires or {}) do
        if not C_QuestLog.IsQuestFlaggedCompleted(reqId) then
            local def = ns.FindQuestDef(reqId)
            reasons[#reasons + 1] = ns.L["Requires: "] .. ns.QuestTitle(reqId, def and def.name)
        end
    end
    if q.requiresAny and #q.requiresAny > 0 then
        local names, anyDone = {}, false
        for _, reqId in ipairs(q.requiresAny) do
            if C_QuestLog.IsQuestFlaggedCompleted(reqId) then anyDone = true break end
            local def = ns.FindQuestDef(reqId)
            names[#names + 1] = ns.QuestTitle(reqId, def and def.name)
        end
        if not anyDone then
            reasons[#reasons + 1] = ns.L["Requires one of: "] .. table.concat(names, " / ")
        end
    end
    if #reasons > 0 then
        return "locked", reasons
    end
    return "available"
end

-- Color escape (|cffRRGGBB) the game gives a quest of this level for this character (grey, green,
-- yellow, orange, red); plain grey if the client doesn't answer.
function ns.QuestLevelColorRGB(level)
    if GetQuestDifficultyColor then
        local ok, c = pcall(GetQuestDifficultyColor, level)
        if ok and type(c) == "table" and c.r then
            return c.r, c.g, c.b
        end
    end
    return 0.73, 0.73, 0.73
end

function ns.QuestLevelColor(level)
    local r, g, b = ns.QuestLevelColorRGB(level)
    return ("|cff%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5))
end

-- "Low level": the quest's title would be grey for this character (trivial). The game itself is asked
-- for the difficulty color; if it doesn't answer, the client's green range is used.
function ns.IsLowLevel(q)
    local questLevel = q.level or q.minLevel
    if not questLevel then return false end
    if GetQuestDifficultyColor then
        local ok, c = pcall(GetQuestDifficultyColor, questLevel)
        if ok and type(c) == "table" then
            local trivial = QuestDifficultyColors and QuestDifficultyColors["trivial"]
            return c == trivial or (c.r == 0.5 and c.g == 0.5 and c.b == 0.5)
        end
    end
    local player = UnitLevel("player")
    local green = (GetQuestGreenRange and GetQuestGreenRange()) or (3 + math.floor(player / 10))
    return questLevel <= player - green
end

-- "Too high": the character can't take it yet (its minimum level is above theirs) or the game colors it
-- red in the log (too hard for their level). The latter catches quests with a low minimum and a high
-- level, like "Master Angler" (level 60, can be taken from level 1). The game is asked for the color, as
-- in IsLowLevel; if it doesn't answer, red is 5 or more levels above.
function ns.IsTooHigh(q)
    local player = UnitLevel("player")
    if (q.minLevel or 0) > player then return true end
    if not q.level then return false end
    if GetQuestDifficultyColor then
        local ok, c = pcall(GetQuestDifficultyColor, q.level)
        if ok and type(c) == "table" then
            local red = QuestDifficultyColors and QuestDifficultyColors["impossible"]
            return c == red or (c.r == 1 and c.g < 0.2 and c.b < 0.2)
        end
    end
    return q.level >= player + 5
end

-- Race and class masks: one bit per race/class (races: 1 human, 2 orc, 4 dwarf, 8 night elf, 16 undead,
-- 32 tauren, 64 gnome, 128 troll; classes: 1 warrior, 2 paladin, 4 hunter, 8 rogue, 16 priest, 64 shaman,
-- 128 mage, 256 warlock, 1024 druid). The client's race or class id is the bit number + 1.
local function hasBit(mask, id)
    return math.floor(mask / 2 ^ (id - 1)) % 2 == 1
end

local ALLIANCE_RACE_BITS = { [1] = true, [3] = true, [4] = true, [7] = true } -- race ids: human, dwarf, night elf, gnome

-- A quest's faction: the one set, or the one its races imply (all of one faction).
function ns.QuestFaction(q)
    if q.faction then return q.faction end
    if not q.races then return nil end
    local alliance, horde = false, false
    for id = 1, 8 do
        if hasBit(q.races, id) then
            if ALLIANCE_RACE_BITS[id] then alliance = true else horde = true end
        end
    end
    if alliance and not horde then return "Alliance" end
    if horde and not alliance then return "Horde" end
end

-- What the character sees. Quests of another class, race or faction are hidden, unless that class or
-- race is being looked at (its entry in the panel; `d` is the entry being looked at) or the "other
-- faction" filter is on, which allows the opposite faction's.
local playerRaceId, playerClassId
function ns.QuestVisible(q, d)
    if q.hidden then return false end
    local category = d and d.category
    local otherFaction = ns.char and ns.char.filters and ns.char.filters.otherFaction

    if q.classes and category ~= "classes" then
        playerClassId = playerClassId or select(3, UnitClass("player"))
        if playerClassId and not hasBit(q.classes, playerClassId) then return false end
    end

    local mine = UnitFactionGroup("player")
    local faction = ns.QuestFaction(q)
    local lookingAtRace = category == "races"
    if faction and faction ~= mine and not (lookingAtRace or otherFaction) then return false end
    if q.races and not lookingAtRace then
        playerRaceId = playerRaceId or select(3, UnitRace("player"))
        if playerRaceId and not hasBit(q.races, playerRaceId) then
            -- another race: only shown if it is of the opposite faction and that was asked for
            if not (otherFaction and faction and faction ~= mine) then return false end
        end
    end
    return true
end

-- A quest's long description. The client doesn't give the text of any quest by its id, only of the
-- ones in your log: for those it is read live (in the client's language), for the rest the addon's
-- data text is used, if any. Nothing is saved in the saved variables.
-- The log's text is the selected quest's: it is selected, read, and the selection put back. It is kept
-- in memory only, once per quest and session, so the selection isn't touched on every window refresh.
local fromLog = {}
local function readFromLog(id)
    if fromLog[id] ~= nil then return fromLog[id] end
    fromLog[id] = false
    local getSel, setSel = C_QuestLog.GetSelectedQuest, C_QuestLog.SetSelectedQuest
    if not (getSel and setSel and GetQuestLogQuestText) then return false end
    local previous = getSel()
    ns.quietSelect = true -- our own selection changes aren't the player's (see MainWindow)
    local ok, text = pcall(function()
        setSel(id)
        if getSel() ~= id then return nil end
        local index = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(id)
        return (GetQuestLogQuestText(index))
    end)
    if previous ~= id then pcall(setSel, previous or 0) end
    ns.quietSelect = nil
    if ok and type(text) == "string" and strtrim(text) ~= "" then fromLog[id] = text end
    return fromLog[id]
end

function ns.QuestDescription(q)
    local text = C_QuestLog.IsOnQuest(q.id) and readFromLog(q.id) or nil
    text = text or q.desc or (ns.DESC and ns.DESC[q.id])
    if not text then return nil end
    local name = (UnitName("player") or ""):gsub("%%", "%%%%")
    return (text:gsub("%$[Nn]", name))
end
