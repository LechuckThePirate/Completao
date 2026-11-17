local _, ns = ...
local C_QuestLog = ns.QuestLog or C_QuestLog -- never the game's table directly (QuestLogCompat.lua)

-- Account-wide completion, for alt players: each character's completed quests are kept in the account's saved
-- variables (CompletaoDB.chars, only the ids of the addon's own quests), and with the "Account-wide" filter on a
-- quest done by any of them shows as done, in the trees, the progress and the search. Only what is shown changes:
-- what the character itself can take (requirements, the quest log, the focus window, turn-ins) is still its own.

local function charKey()
    return (UnitName("player") or "?") .. "-" .. (GetRealmName and GetRealmName() or "?")
end

local function store()
    if not ns.db then return nil end
    ns.db.chars = ns.db.chars or {}
    local key = charKey()
    local me = ns.db.chars[key]
    if not me then
        me = { done = {} }
        ns.db.chars[key] = me
    end
    me.name = UnitName("player")
    me.realm = GetRealmName and GetRealmName() or nil
    me.class = select(2, UnitClass("player"))
    return me
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
end

-- A quest the character just turned in (the game's list may not say so yet).
function ns.Account_MarkDone(id)
    local def = id and ns.FindQuestDef(id)
    if not def or def.repeatable then return end
    local me = store()
    if me then me.done[id] = true end
end

-- The "Account-wide" filter is on.
function ns.AccountWide()
    return ns.char and ns.char.filters and ns.char.filters.accountWide and true or false
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
events:SetScript("OnEvent", function(_, event, arg1)
    if event == "QUEST_TURNED_IN" then
        ns.Account_MarkDone(arg1)
    else
        ns.Account_Record()
        -- the game may still be loading the list right after logging in
        C_Timer.After(5, ns.Account_Record)
    end
end)
