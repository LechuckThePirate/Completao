local _, ns = ...

-- The Classic clients don't all have the whole of C_QuestLog (TBC Anniversary has no GetInfo, for one): what is
-- missing is filled in from the old quest log API, which they do have.
-- The game's C_QuestLog is never written to, not even reassigned: a global or a field written by an addon taints
-- every Blizzard function that reads it, and with Forever's secret values that breaks the nameplates, the action
-- bars and the rest of the UI ("Completao has been blocked from an action"). The modules read ns.QuestLog instead
-- (`local C_QuestLog = ns.QuestLog or C_QuestLog` at the top of each file): the game's function when there is
-- one, else the one from here.
local shims = {}

-- Looked up on every read, so a client (or a test) that has the function always wins.
ns.QuestLog = setmetatable({}, {
    __index = function(_, name)
        local game = _G.C_QuestLog
        local f = game and game[name]
        if f ~= nil then return f end
        return shims[name]
    end,
    __newindex = function() error("ns.QuestLog is read-only", 2) end,
})
local Q = ns.QuestLog

-- A line of the old quest log, as C_QuestLog.GetInfo gives it.
local function line(index)
    local title, level, suggestedGroup, isHeader, isCollapsed, isComplete, frequency, questID = GetQuestLogTitle(index)
    if not title then return nil end
    return {
        title = title, level = level, suggestedGroup = suggestedGroup, frequency = frequency,
        isHeader = isHeader and true or false, isCollapsed = isCollapsed and true or false,
        isComplete = isComplete, questID = questID or 0,
    }
end

local function indexOf(questID)
    for i = 1, GetNumQuestLogEntries() do
        local info = line(i)
        if info and not info.isHeader and info.questID == questID then return i, info end
    end
end

if GetQuestLogTitle and GetNumQuestLogEntries then
    shims.GetNumQuestLogEntries = function() return (GetNumQuestLogEntries()) end
    shims.GetInfo = line
    shims.GetLogIndexForQuestID = function(questID) return (indexOf(questID)) end
    shims.IsOnQuest = function(questID) return indexOf(questID) ~= nil end
    shims.GetTitleForQuestID = function(questID)
        if Q.GetQuestInfo then return Q.GetQuestInfo(questID) end
        local _, info = indexOf(questID)
        return info and info.title or nil
    end
    shims.IsComplete = function(questID)
        local _, info = indexOf(questID)
        return info ~= nil and (info.isComplete == 1 or info.isComplete == true)
    end
end
shims.RequestLoadQuestByID = function() end
if IsQuestFlaggedCompleted then
    shims.IsQuestFlaggedCompleted = function(questID) return IsQuestFlaggedCompleted(questID) and true or false end
end
if GetQuestLogSelection and SelectQuestLogEntry and GetQuestLogTitle then
    shims.GetSelectedQuest = function()
        local info = line(GetQuestLogSelection())
        return info and info.questID or 0
    end
    shims.SetSelectedQuest = function(questID)
        local index = indexOf(questID)
        if index then SelectQuestLogEntry(index) end
    end
end

ns.QuestLogCompat = true -- tests look for it
