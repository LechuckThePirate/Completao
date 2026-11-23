local _, ns = ...
local L = ns.L
local C_QuestLog = ns.QuestLog or C_QuestLog -- never the game's table directly (QuestLogCompat.lua)

-- One set of filters for every view that lists quests (the tree and the list of an entry, the search, the quest log, the
-- tracked quests and the ones to turn in): the same options, the same words ("Hide ..."), the same meaning, one store
-- (ns.char.filters, saved with the settings) and one menu. A view only adds what it needs on top: its own title box
-- (the text typed in is that view's alone) and, for the tables, which quests it lists to begin with.
--   hideLow, hideHigh, hideDone, hideRepeatable, otherFaction, chainsOnly, itemsOnly, rewardClass, rewardSub

ns.FILTER_OPTIONS = {
    { key = "hideLow", label = L["Hide low level"], tip = L["Hides quests that are grey for your level (trivial)."] },
    { key = "hideHigh", label = L["Hide too high"], tip = L["Hides quests you cannot take yet, because of your level."] },
    { key = "hideDone", label = L["Hide completed"],
        tip = L["Hides the quests you have completed, also inside unfinished chains."] },
    { key = "hideRepeatable", label = L["Hide repeatable done"],
        tip = L["Hides the repeatable quests you have already turned in once; the ones you have never done still show."] },
    { key = "otherFaction", label = L["Show other faction"],
        tip = L["Shows the quests and zones of the opposite faction, hidden by default."] },
    { key = "chainsOnly", label = L["Chains only"],
        tip = L["Hides the loose quests, the ones that no quest of the zone leads to or follows; the ones in your log stay."] },
    { key = "itemsOnly", label = L["Only quests with item rewards"] },
}

---------------------------------------------------------------------------------------------------------- rewards

-- An item's class and subclass, with their names in the client's language. This is "instant" client information (the
-- item doesn't need to be cached).
local itemClassCache = {}
function ns.RewardItemClass(id)
    local c = itemClassCache[id]
    if c == nil then
        c = false
        local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
        if f then
            local _, typeName, subName, _, icon, classID, subclassID = f(id)
            if classID then
                c = { class = classID, sub = subclassID, typeName = typeName, subName = subName, icon = icon }
            end
        end
        itemClassCache[id] = c
    end
    return c or nil
end

-- Reward types present in the data: { {id, name, subs = { {id, name} }} }, by name.
local rewardTypes
function ns.RewardTypes()
    if rewardTypes then return rewardTypes end
    local byClass = {}
    for _, r in pairs(ns.REWARDS or {}) do
        for _, id in ipairs(ns.RewardItemIds(r)) do
            local c = ns.RewardItemClass(id)
            if c and c.typeName then
                local t = byClass[c.class]
                if not t then
                    t = { id = c.class, name = c.typeName, subs = {}, seen = {} }
                    byClass[c.class] = t
                end
                if c.sub and c.subName and not t.seen[c.sub] then
                    t.seen[c.sub] = true
                    t.subs[#t.subs + 1] = { id = c.sub, name = c.subName }
                end
            end
        end
    end
    rewardTypes = {}
    for _, t in pairs(byClass) do
        table.sort(t.subs, function(a, b) return a.name < b.name end)
        rewardTypes[#rewardTypes + 1] = t
    end
    table.sort(rewardTypes, function(a, b) return a.name < b.name end)
    return rewardTypes
end

local function matchesReward(q, f)
    local r = ns.REWARDS and ns.REWARDS[q.id]
    if f.itemsOnly and not (r and #ns.RewardItemIds(r) > 0) then return false end
    if not f.rewardClass then return true end
    if not r then return false end
    for _, id in ipairs(ns.RewardItemIds(r)) do
        local c = ns.RewardItemClass(id)
        if c and c.class == f.rewardClass and (not f.rewardSub or c.sub == f.rewardSub) then return true end
    end
    return false
end

------------------------------------------------------------------------------------------------------------ chains

-- Chains of an entry: each group of quests connected by prerequisites. Returns, by quest id, its chain's data: size (number of
-- quests), allDone (all done; loose done quests included), started (some done or in the log), allLow (all low level) and
-- headsTooHigh (every quest the chain starts with -- those with no prerequisite inside it -- is above your level).
function ns.ChainInfo(d, isOnQuest)
    isOnQuest = isOnQuest or C_QuestLog.IsOnQuest
    local set, parent = {}, {}
    for _, q in ipairs(d.quests) do
        if ns.QuestVisible(q, d) then set[q.id] = q; parent[q.id] = q.id end
    end
    local function find(x)
        while parent[x] ~= x do parent[x] = parent[parent[x]]; x = parent[x] end
        return x
    end
    for id, q in pairs(set) do
        for _, p in ipairs(ns.ParentsOf(q)) do
            if set[p] then
                local a, b = find(id), find(p)
                if a ~= b then parent[a] = b end
            end
        end
    end
    local chains = {}
    local lowByLevel = {} -- IsLowLevel only depends on the level, and asks the client
    local function isLow(q)
        local level = q.level or q.minLevel
        local low = level and lowByLevel[level]
        if low == nil then
            low = ns.IsLowLevel(q)
            if level then lowByLevel[level] = low end
        end
        return low
    end
    for id, q in pairs(set) do
        local root = find(id)
        local c = chains[root]
        if not c then
            c = { size = 0, allDone = true, started = false, allLow = true, heads = 0, headsHigh = 0 }
            chains[root] = c
        end
        c.size = c.size + 1
        local isDone = ns.IsQuestDone(id)
        if not isDone then c.allDone = false end
        if isDone or isOnQuest(id) then c.started = true end
        if not isLow(q) then c.allLow = false end
        local isHead = true
        for _, p in ipairs(ns.ParentsOf(q)) do
            if set[p] then isHead = false break end
        end
        if isHead then
            c.heads = c.heads + 1
            if ns.IsTooHigh(q) then c.headsHigh = c.headsHigh + 1 end
        end
    end
    local info = {}
    for id, q in pairs(set) do
        local c = chains[find(id)]
        info[id] = {
            size = c.size, allDone = c.allDone, started = c.started, allLow = c.allLow,
            headsTooHigh = c.heads > 0 and c.headsHigh == c.heads, low = isLow(q),
        }
    end
    return info
end

---------------------------------------------------------------------------------------------------------- the filter

local function defaultMatchText(q, needle)
    local cached = C_QuestLog.GetTitleForQuestID(q.id)
    return ((cached and cached:lower():find(needle, 1, true)) or q.name:lower():find(needle, 1, true)) and true or false
end

-- The predicate every view uses to ask whether a quest of entry `d` (nil for one the data doesn't have) shows, from the
-- filters in ns.char.filters and the title typed in the view's box.
--  * By level, chains are shown or hidden as a whole, so they are never cut in half: "too high" hides a chain when every
--    quest it starts with is above your level, "low level" one whose quests are all grey; a chain you have started (some
--    quest done or in the log) is never hidden by level, and loose quests are hidden by their own level unless they are
--    in your log. "Completed" hides each completed quest on its own.
--  * The quests in your log are never hidden by completed, repeatable, level or chains only.
-- opts: text (what is typed in), isOnQuest (for a client with no IsOnQuest of its own: the view reads the log once),
-- matchText(q, needle) (the view's cached way of reading titles), assumeVisible (the view already left out what the
-- character can't see: the search).
function ns.QuestFilter(d, opts)
    opts = opts or {}
    local f = ns.char.filters
    local isOnQuest = opts.isOnQuest or C_QuestLog.IsOnQuest
    local chains
    if d and (f.hideLow or f.hideHigh) then chains = ns.ChainInfo(d, isOnQuest) end
    local needle = opts.text and opts.text ~= "" and opts.text or nil
    local matchText = opts.matchText or defaultMatchText
    local lowByLevel = {}
    return function(q)
        if not opts.assumeVisible and not ns.QuestVisible(q, d) then return false end
        local onQuest = isOnQuest(q.id)
        if f.chainsOnly and not onQuest and not ns.IsInChain(q) then return false end
        if f.hideDone and ns.IsQuestDone(q.id) and not onQuest then return false end
        -- repeatable: the game never marks them done, so this is how they are put aside (the one in the log stays)
        if f.hideRepeatable and q.repeatable and not onQuest and ns.RepeatableDone(q.id) then return false end
        local c = chains and chains[q.id]
        if c and c.size > 1 then
            if not c.started then
                if f.hideHigh and c.headsTooHigh then return false end
                if f.hideLow and c.allLow then return false end
            end
        elseif not onQuest then
            if f.hideLow then
                local low = c and c.low
                if low == nil then
                    local level = q.level or q.minLevel
                    low = level and lowByLevel[level]
                    if low == nil then
                        low = ns.IsLowLevel(q)
                        if level then lowByLevel[level] = low end
                    end
                end
                if low then return false end
            end
            if f.hideHigh and ns.IsTooHigh(q) then return false end
        end
        if (f.itemsOnly or f.rewardClass) and not matchesReward(q, f) then return false end
        if needle and not matchText(q, needle) then return false end
        return true
    end
end

------------------------------------------------------------------------------------------------------------- the menu

-- The texts of the filters in force, for the line under the toolbar: "Hide low level", "Reward type: Armor > Leather"...
function ns.FilterParts()
    local f = ns.char.filters
    local parts = {}
    for _, opt in ipairs(ns.FILTER_OPTIONS) do
        if f[opt.key] then parts[#parts + 1] = opt.label end
    end
    if f.rewardClass then
        local name = L["Reward type:"]
        for _, t in ipairs(ns.RewardTypes()) do
            if t.id == f.rewardClass then
                name = name .. " " .. t.name
                for _, s in ipairs(t.subs) do
                    if s.id == f.rewardSub then name = name .. " > " .. s.name end
                end
            end
        end
        parts[#parts + 1] = name
    end
    return parts
end

local menus = {}

local function makeDropdown(parent, width)
    local T = ns.Theme
    local b = T.CreateGhostButton(parent, nil, width, 22)
    local text = b:GetFontString()
    if text then text:ClearAllPoints(); text:SetPoint("LEFT", 8, 0); text:SetPoint("RIGHT", -18, 0); text:SetJustifyH("LEFT") end
    T.SetGlyph(b, "chevronDown", "RIGHT", -9, 0)
    return b
end

-- Every filter menu made (each view has its own button): their checks and reward pickers show the same store.
function ns.RefreshFilterMenus()
    local f = ns.char.filters
    for _, button in ipairs(menus) do
        local typeName, subName = L["Any"], L["Any"]
        for _, t in ipairs(ns.RewardTypes()) do
            if t.id == f.rewardClass then
                typeName = t.name
                for _, s in ipairs(t.subs) do
                    if s.id == f.rewardSub then subName = s.name end
                end
            end
        end
        button.typeButton:SetText(typeName)
        button.subButton:SetText(subName)
        button.subButton:SetEnabled(f.rewardClass ~= nil)
        -- with a reward type picked every quest already gives an item: the checkbox would change nothing
        local byType = f.rewardClass ~= nil
        button.itemsOnly:SetEnabled(not byType)
        button.itemsOnly.label:SetTextColor(byType and 0.5 or 1, byType and 0.5 or 0.82, byType and 0.5 or 0)
        button.Update()
    end
end

-- A "Filters" drop-down with the shared options and the reward type pickers (a type and its subtype, under the checks).
-- `onChange` is called after the player changes something (the view redraws).
function ns.CreateFilterMenu(parent, onChange)
    local button
    local function changed()
        ns.RefreshFilterMenus()
        onChange()
    end
    button = ns.FilterMenu(parent, {
        options = ns.FILTER_OPTIONS,
        get = function(key) return ns.char.filters[key] end,
        set = function(key, on) ns.char.filters[key] = on end,
        onChange = changed,
        footer = function(menu)
            local footer = CreateFrame("Frame", nil, menu)
            footer:SetSize(158, 76)
            local line = footer:CreateTexture(nil, "ARTWORK")
            line:SetColorTexture(1, 1, 1, 0.15)
            line:SetHeight(1)
            line:SetPoint("TOPLEFT", 0, 0)
            line:SetPoint("TOPRIGHT", 0, 0)
            local label = footer:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            label:SetPoint("TOPLEFT", 2, -8)
            label:SetText(L["Reward type:"])
            footer.typeButton = makeDropdown(footer, 150)
            footer.typeButton:SetPoint("TOPLEFT", 0, -24)
            footer.subButton = makeDropdown(footer, 150)
            footer.subButton:SetPoint("TOPLEFT", 0, -50)
            return footer
        end,
        footerActive = function() return ns.char.filters.rewardClass and 1 or 0 end,
        clearFooter = function()
            ns.char.filters.rewardClass, ns.char.filters.rewardSub = nil, nil
            ns.PopupMenu_Hide()
        end,
    })
    local footer = button.footer
    button.typeButton, button.subButton = footer.typeButton, footer.subButton
    local function pick(anchor, options, onPick)
        ns.PopupMenu(anchor, options, onPick, 170)
    end
    button.typeButton:SetScript("OnClick", function(self)
        local options = { { name = L["Any"] } }
        for _, t in ipairs(ns.RewardTypes()) do options[#options + 1] = t end
        pick(self, options, function(opt)
            ns.char.filters.rewardClass, ns.char.filters.rewardSub = opt.id, nil
            changed()
        end)
    end)
    button.subButton:SetScript("OnClick", function(self)
        local options = { { name = L["Any"] } }
        for _, t in ipairs(ns.RewardTypes()) do
            if t.id == ns.char.filters.rewardClass then
                for _, s in ipairs(t.subs) do options[#options + 1] = s end
            end
        end
        pick(self, options, function(opt)
            ns.char.filters.rewardSub = opt.id
            changed()
        end)
    end)
    -- only quests that give some item (fixed or to choose): off while a reward type is chosen
    local itemsOnly = button.checks.itemsOnly
    itemsOnly:SetMotionScriptsWhileDisabled(true)
    local tip = L["Hides the quests that give no item (fixed or to choose)."]
    itemsOnly:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self:IsEnabled() then
            GameTooltip:SetText(L["Only quests with item rewards"])
            GameTooltip:AddLine(tip, 1, 1, 1, true)
        else
            GameTooltip:AddLine(L["A reward type is selected: every result already gives an item."], 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    itemsOnly:SetScript("OnLeave", GameTooltip_Hide)
    button.itemsOnly = itemsOnly
    menus[#menus + 1] = button
    ns.RefreshFilterMenus()
    return button
end
