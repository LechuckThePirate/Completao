local _, ns = ...
local C_QuestLog = ns.QuestLog or C_QuestLog -- never the game's table directly (QuestLogCompat.lua)

-- A quest's state for the character: title, done / in progress / available / locked, low or too high
-- level, whether it is meant for them (class, race, faction) and its long description.

-- Asks the client for a quest's data (title, tags), once per session: every answer fires an event that
-- redraws the window, which would ask again for the quests the client never has an answer for (an endless
-- redraw loop: clicks lost, menus closing themselves).
local requested = {}
local function requestLoad(id)
    if requested[id] then return end
    requested[id] = true
    C_QuestLog.RequestLoadQuestByID(id)
end

ns.RequestQuestLoad = requestLoad

-- Title in the client's language. Chain steps that share a name are numbered in the data
-- ("Hidden Enemies (3/5)"): the number is kept with the game's title too, which lacks it. `getTitle` stands in for
-- the client's lookup (the search table's, which reads the log once for all its rows).
function ns.QuestTitle(id, fallback, getTitle)
    local title = (getTitle or C_QuestLog.GetTitleForQuestID)(id)
    if title and title ~= "" then
        local step = fallback and fallback:match(" %(%d+/%d+%)$")
        if step and not title:find(step, 1, true) then title = title .. step end
        return title
    end
    requestLoad(id)
    return fallback or ("Quest " .. id)
end

-- In the log with every objective done and not turned in yet. A quest with no objectives at all (deliver a
-- letter, speak to someone) is ready as soon as it is taken, though the client never marks it complete.
function ns.IsReadyToTurnIn(id)
    if not C_QuestLog.IsOnQuest(id) or C_QuestLog.IsQuestFlaggedCompleted(id) then return false end
    local objectives = C_QuestLog.GetQuestObjectives and C_QuestLog.GetQuestObjectives(id)
    if objectives and #objectives == 0 then return true end
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
        requestLoad(id)
        return false
    end
    return tagId == ELITE_TAG_ID
end

-- Prefix for a quest's name, as Questie's tracker: "[11] ", "[13D] " (dungeon quest) or "[15+] " (elite; it
-- takes priority over dungeon), with an R after it for a repeatable quest ("[30R] "). Empty when the level isn't known.
function ns.QuestPrefix(q)
    local level = q.level or q.minLevel
    if not level then return "" end
    return ("[%d%s%s] "):format(level, ns.IsEliteQuest(q.id) and "+" or q.dungeon and "D" or "", q.repeatable and "R" or "")
end

-- Done, as the views count it: by the character, or, with "Consolidate alts" on, by any character of the account
-- (AccountProgress.lua), also for the quests another one requires. The level is still the character's own.
function ns.IsQuestDone(id)
    if C_QuestLog.IsQuestFlaggedCompleted(id) then return true end
    return ns.Consolidated ~= nil and ns.Consolidated() and ns.DoneByAlt(id) ~= nil
end

local function takenOrDone(id)
    return C_QuestLog.IsQuestFlaggedCompleted(id) or C_QuestLog.IsOnQuest(id)
end

local function titleOf(id)
    local def = ns.FindQuestDef(id)
    return ns.QuestTitle(id, def and def.name)
end

-- The quest that took this one away, or nil: a breadcrumb (lead-in) can't be taken once the quest it leads to is
-- taken (Westbrook Garrison Needs Help! once Riverpaw Gnoll Bounty is), nor can a quest once one of those it is
-- exclusive to is. For a quest that isn't done: it is lost for good.
function ns.QuestLostTo(q)
    if q.breadcrumbFor and takenOrDone(q.breadcrumbFor) then return q.breadcrumbFor end
    for _, other in ipairs(q.exclusiveTo or {}) do
        if takenOrDone(other) then return other end
    end
    return nil
end

-- What to know before taking it, so no quest is lost by doing another first: lines of text, empty when there is
-- nothing. Only for a quest that is still to take.
function ns.QuestWarnings(q)
    local out = {}
    if takenOrDone(q.id) or ns.QuestLostTo(q) then return out end
    if q.breadcrumbFor then
        out[#out + 1] = ns.L["Lead-in to %s: take it before that one, or it can't be taken any more."]:format(titleOf(q.breadcrumbFor))
    end
    for _, id in ipairs(ns.BreadcrumbsTo(q.id)) do
        local def = ns.FindQuestDef(id)
        if not takenOrDone(id) and not (def and not ns.QuestVisible(def)) then
            out[#out + 1] = ns.L["Do %s first: taking this quest makes it unavailable."]:format(titleOf(id))
        end
    end
    if q.exclusiveTo and #q.exclusiveTo > 0 then
        local names = {}
        for _, id in ipairs(q.exclusiveTo) do names[#names + 1] = titleOf(id) end
        out[#out + 1] = ns.L["Only one can be done: taking it makes %s unavailable."]:format(table.concat(names, " / "))
    end
    return out
end

-- Returns "done" | "active" | "available" | "locked" | "missed", and a list of reasons when locked or missed
-- (missed: it can't be taken any more, see QuestLostTo).
function ns.QuestStatus(q)
    if C_QuestLog.IsQuestFlaggedCompleted(q.id) then
        return "done"
    end
    if C_QuestLog.IsOnQuest(q.id) then
        return "active"
    end
    if ns.IsQuestDone(q.id) then
        return "done" -- by another character, with "Consolidate alts" on
    end
    local lost = ns.QuestLostTo(q)
    if lost then
        return "missed", { ns.L["No longer available: you took %s"]:format(titleOf(lost)) }
    end

    local reasons = {}
    if q.minLevel and UnitLevel("player") < q.minLevel then
        reasons[#reasons + 1] = ns.L["Requires level %d (you are %d)"]:format(q.minLevel, UnitLevel("player"))
    end
    for _, reqId in ipairs(q.requires or {}) do
        if not ns.IsQuestDone(reqId) then
            local def = ns.FindQuestDef(reqId)
            reasons[#reasons + 1] = ns.L["Requires: "] .. ns.QuestTitle(reqId, def and def.name)
        end
    end
    if q.requiresAny and #q.requiresAny > 0 then
        local names, anyDone = {}, false
        for _, reqId in ipairs(q.requiresAny) do
            if ns.IsQuestDone(reqId) then anyDone = true break end
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

-- Something to do with it now: in the log, or not done and with nothing still in the way (its level, the quests
-- it requires). The light version of "available" in QuestStatus, for counting over thousands of quests.
function ns.IsQuestAvailable(q)
    if C_QuestLog.IsQuestFlaggedCompleted(q.id) then return false end
    if C_QuestLog.IsOnQuest(q.id) then return true end
    if ns.IsQuestDone(q.id) then return false end
    if q.minLevel and UnitLevel("player") < q.minLevel then return false end
    if ns.QuestLostTo(q) then return false end
    for _, reqId in ipairs(q.requires or {}) do
        if not ns.IsQuestDone(reqId) then return false end
    end
    if q.requiresAny and #q.requiresAny > 0 then
        local anyDone = false
        for _, reqId in ipairs(q.requiresAny) do
            if ns.IsQuestDone(reqId) then anyDone = true break end
        end
        if not anyDone then return false end
    end
    return true
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

-- "Too high": the character can't take it yet, its minimum level is above theirs. Only the minimum counts,
-- not the quest's own level: a level 60 quest that can be taken from level 10 (like "Master Angler") is a
-- quest the character can take, so it isn't hidden. A quest with no minimum in the data can't be told to be
-- out of reach, and isn't either.
function ns.IsTooHigh(q)
    return (q.minLevel or 0) > UnitLevel("player")
end

-- Race and class masks: one bit per race/class (races: 1 human, 2 orc, 4 dwarf, 8 night elf, 16 undead,
-- 32 tauren, 64 gnome, 128 troll, 512 blood elf, 1024 draenei; classes: 1 warrior, 2 paladin, 4 hunter, 8 rogue, 16 priest, 64 shaman,
-- 128 mage, 256 warlock, 1024 druid). The client's race or class id is the bit number + 1.
local function hasBit(mask, id)
    return math.floor(mask / 2 ^ (id - 1)) % 2 == 1
end

-- race ids: human, dwarf, night elf, gnome, draenei
local ALLIANCE_RACE_BITS = { [1] = true, [3] = true, [4] = true, [7] = true, [11] = true }

-- A quest's faction: the one set, or the one its races imply (all of one faction).
function ns.QuestFaction(q)
    if q.faction then return q.faction end
    if not q.races then return nil end
    local alliance, horde = false, false
    for id = 1, 11 do
        if hasBit(q.races, id) then
            if ALLIANCE_RACE_BITS[id] then alliance = true else horde = true end
        end
    end
    if alliance and not horde then return "Alliance" end
    if horde and not alliance then return "Horde" end
end

-- The character being played, as the visibility rules see it: class, race and faction. The class and race are read
-- once; the faction every time (a Pandaren picks one, and a mercenary's changes).
local player
function ns.PlayerProfile()
    if not player then
        local _, classFile, classId = UnitClass("player")
        player = { classFile = classFile, classId = classId, raceId = select(3, UnitRace("player")), me = true }
    end
    player.faction = UnitFactionGroup("player")
    return player
end

-- Whether one character (a profile: PlayerProfile, or an alt's in AccountProgress.lua) sees the quest.
local function visibleFor(q, category, who, otherFaction)
    -- the quests of a class entry carry no mask: the entry says whose they are (the search looks at them without an entry)
    local home = q.entryId and ns.entries and ns.entries[q.entryId]
    if home and home.classFile and category ~= "classes" then
        if who.classFile and who.classFile ~= home.classFile then return false end
    end

    if q.classes and category ~= "classes" then
        if who.classId and not hasBit(q.classes, who.classId) then return false end
    end

    local mine = ns.PlayerProfile().faction -- "other faction" is the one opposite to the character being played
    local faction = ns.QuestFaction(q)
    local lookingAtRace = category == "races"
    if faction and faction ~= who.faction and not (lookingAtRace or (otherFaction and faction ~= mine)) then return false end
    if q.races and not lookingAtRace then
        if who.raceId and not hasBit(q.races, who.raceId) then
            -- another race: only shown if it is of the opposite faction and that was asked for
            if not (otherFaction and faction and faction ~= mine) then return false end
        end
    end
    return true
end

-- What the character sees. Quests of another class, race or faction are hidden, unless that class or
-- race is being looked at (its entry in the panel; `d` is the entry being looked at) or the "other
-- faction" filter is on, which allows the opposite faction's. With "Consolidate alts" on, what any character of
-- the account sees (ns.Characters, AccountProgress.lua).
function ns.QuestVisible(q, d)
    if q.hidden then return false end
    local category = d and d.category
    local otherFaction = ns.char and ns.char.filters and ns.char.filters.otherFaction
    if visibleFor(q, category, ns.PlayerProfile(), otherFaction) then return true end
    if not (ns.Consolidated and ns.Consolidated()) then return false end
    for _, who in ipairs(ns.Characters()) do
        if not who.me and visibleFor(q, category, who, otherFaction) then return true end
    end
    return false
end

-- A quest's long description. The client doesn't give the text of any quest by its id, only of the
-- ones in your log: for those it is read live (in the client's language), for the rest the addon's
-- data text is used, if any. Nothing is saved in the saved variables.
-- The log's text is the selected quest's: it is selected, read, and the selection put back. It is kept
-- in memory only, once per quest and session, so the selection isn't touched on every window refresh.
local fromLog = {}

-- The game's log redraws itself a moment after its selection changes and selects the quest again on its own
-- (the window would follow that echo and jump to another quest): our own selection changes are muted for a
-- while, not only while they are being made. See onQuestSelected in MainWindow.
local MUTE_SECONDS = 1
local mutedUntil = 0
function ns.MuteQuestSelect()
    mutedUntil = GetTime() + MUTE_SECONDS
end

function ns.QuestSelectMuted()
    return ns.quietSelect or GetTime() < mutedUntil
end

local function readFromLog(id)
    if fromLog[id] ~= nil then return fromLog[id] end
    fromLog[id] = false
    local getSel, setSel = C_QuestLog.GetSelectedQuest, C_QuestLog.SetSelectedQuest
    if not (getSel and setSel and GetQuestLogQuestText) then return false end
    local previous = getSel()
    ns.quietSelect = true -- our own selection changes aren't the player's (see MainWindow)
    ns.MuteQuestSelect()
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

-- The experience a quest gives. Data/<Flavor>/Generated/Rewards.lua only lists it when it isn't zero, so a quest with none (or
-- with no row at all) gives 0.
function ns.QuestXP(id)
    local r = ns.REWARDS and ns.REWARDS[id]
    return r and r.xp or 0
end

-- The ids of the items a reward row gives: the ones to choose from, then the fixed ones (an entry is an id or { id, count }).
function ns.RewardItemIds(r)
    local ids = {}
    for _, list in ipairs({ r.choice or {}, r.items or {} }) do
        for _, e in ipairs(list) do ids[#ids + 1] = type(e) == "table" and e[1] or e end
    end
    return ids
end

-- Copper as the client writes it, with its coin icons ("4|TInterface...|t 50|T...|t").
function ns.CoinString(copper)
    local f = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
    return f and f(copper) or (copper .. "c")
end
