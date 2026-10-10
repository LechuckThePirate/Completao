local _, ns = ...

-- Public API for other addons (Fabrikao!! uses it for the "View Quest" button of a recipe that comes from a quest). A global
-- table so that an addon can use it without Completao's private namespace.
--
--   CompletaoAPI.version              the API's version (1)
--   CompletaoAPI.HasQuest(questID)    does Completao know the quest (is it in one of its trees)?
--   CompletaoAPI.ShowQuest(questID)   opens Completao's window on the quest, in its tree with its panel; false when unknown

local API = { version = 1 }

function API.HasQuest(questID)
    if type(questID) ~= "number" then return false end
    local def = ns.FindQuestDef(questID)
    return def ~= nil and ns.entries[def.entryId] ~= nil
end

function API.ShowQuest(questID)
    if not API.HasQuest(questID) then return false end
    return ns.UI_ShowQuest(questID)
end

CompletaoAPI = API
