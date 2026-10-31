local _, ns = ...

-- The Classic clients don't all have the whole of C_QuestLog (TBC Anniversary has no GetInfo, for one): what is
-- missing is filled in from the old quest log API, which they do have. Nothing that exists is replaced.
_G.C_QuestLog = _G.C_QuestLog or {}
local Q = _G.C_QuestLog

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

local function define(name, f)
    if Q[name] == nil then Q[name] = f end
end

if GetQuestLogTitle and GetNumQuestLogEntries then
    define("GetNumQuestLogEntries", function() return (GetNumQuestLogEntries()) end)
    define("GetInfo", line)
    define("GetLogIndexForQuestID", function(questID) return (indexOf(questID)) end)
    define("IsOnQuest", function(questID) return indexOf(questID) ~= nil end)
    define("GetTitleForQuestID", function(questID)
        if Q.GetQuestInfo then return Q.GetQuestInfo(questID) end
        local _, info = indexOf(questID)
        return info and info.title or nil
    end)
    define("IsComplete", function(questID)
        local _, info = indexOf(questID)
        return info ~= nil and (info.isComplete == 1 or info.isComplete == true)
    end)
end
define("RequestLoadQuestByID", function() end)
if IsQuestFlaggedCompleted then
    define("IsQuestFlaggedCompleted", function(questID) return IsQuestFlaggedCompleted(questID) and true or false end)
end
if GetQuestLogSelection and SelectQuestLogEntry and GetQuestLogTitle then
    define("GetSelectedQuest", function()
        local info = line(GetQuestLogSelection())
        return info and info.questID or 0
    end)
    define("SetSelectedQuest", function(questID)
        local index = indexOf(questID)
        if index then SelectQuestLogEntry(index) end
    end)
end

ns.QuestLogCompat = true -- tests look for it
