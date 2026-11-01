local _, ns = ...

-- Which quests are tracked, on the clients that aren't Forever (Classic Era, TBC): their game has no usable
-- list (the tracker of Blizzard, when there is one, can't take a quest with no objectives, and Questie's has a list
-- of its own). The addon keeps the list itself: a quest in the log is tracked unless it was untracked on purpose
-- (so a quest is tracked as it is taken, as in those clients), and the list is the character's.
-- When Questie's tracker is on, Questie's list is the one that counts, and tracking or untracking here does it there
-- too, so the two trackers never disagree.
-- Forever has the game's own watch list, which is read as always (Search.lua).
function ns.UsesOwnTracking()
    return ns.flavor == "vanilla" or ns.flavor == "tbc"
end

-- Questie's modules, when its tracker is the one in use: { quest = QuestieQuest, tracker = QuestieTracker }.
local function questie()
    local q = _G.Questie
    if not (type(q) == "table" and type(q.db) == "table" and q.db.profile and q.db.profile.trackerEnabled and q.db.char
        and _G.QuestieLoader) then
        return nil
    end
    local ok, quest, tracker = pcall(function()
        return _G.QuestieLoader:ImportModule("QuestieQuest"), _G.QuestieLoader:ImportModule("QuestieTracker")
    end)
    if ok and type(quest) == "table" and type(tracker) == "table" then return { q = q, quest = quest, tracker = tracker } end
    return nil
end

local function untracked()
    ns.char.untrackedQuests = ns.char.untrackedQuests or {}
    return ns.char.untrackedQuests
end

-- Whether the quest is tracked (the addon's own answer; see Search.lua for the one of every client).
function ns.IsOwnTracked(id)
    if not C_QuestLog.IsOnQuest(id) then return false end
    local m = questie()
    if m and m.quest.IsQuestTracked then
        local ok, tracked = pcall(m.quest.IsQuestTracked, m.quest, id)
        if ok then return tracked and true or false end
    end
    return not untracked()[id]
end

-- Puts the quest back on the tracker.
function ns.TrackQuest(id)
    if ns.UsesOwnTracking() then
        untracked()[id] = nil
        local m = questie()
        if m then
            -- Questie keeps either the quests that were untracked (auto track) or the ones that are tracked
            if m.q.db.profile.autoTrackQuests then
                if m.q.db.char.AutoUntrackedQuests then m.q.db.char.AutoUntrackedQuests[id] = nil end
            else
                m.q.db.char.TrackedQuests = m.q.db.char.TrackedQuests or {}
                m.q.db.char.TrackedQuests[id] = true
            end
            if m.tracker.Update then pcall(m.tracker.Update, m.tracker) end
        end
    elseif C_QuestLog.AddQuestWatch then
        C_QuestLog.AddQuestWatch(id)
    elseif AddQuestWatch and C_QuestLog.GetLogIndexForQuestID then
        local index = C_QuestLog.GetLogIndexForQuestID(id)
        if index then AddQuestWatch(index) end
    end
end

-- Takes the quest off the tracker (it stays in the log). Retail style first; the Classic clients
-- only have the global one, which wants the log index.
function ns.UntrackQuest(id)
    if ns.UsesOwnTracking() then
        untracked()[id] = true
        local m = questie()
        if m and m.tracker.UntrackQuestId then pcall(m.tracker.UntrackQuestId, m.tracker, id) end
    elseif C_QuestLog.RemoveQuestWatch then
        C_QuestLog.RemoveQuestWatch(id)
    elseif RemoveQuestWatch and C_QuestLog.GetLogIndexForQuestID then
        local index = C_QuestLog.GetLogIndexForQuestID(id)
        if index then RemoveQuestWatch(index) end
    end
end

-- Track what is untracked and the other way round (shift-click on a quest, as in the game's log); returns whether
-- it is tracked now.
function ns.ToggleTrackedQuest(id)
    if ns.IsQuestTracked(id) then
        ns.UntrackQuest(id)
        return false
    end
    ns.TrackQuest(id)
    return true
end

-- The quest left the log (turned in or abandoned): its mark goes too, so taking it again tracks it.
function ns.ForgetTrackedQuest(id)
    if id and ns.char and ns.char.untrackedQuests then ns.char.untrackedQuests[id] = nil end
end
