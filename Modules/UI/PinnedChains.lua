local _, ns = ...
local C_QuestLog = ns.QuestLog or C_QuestLog -- never the game's table directly (QuestLogCompat.lua)
local T = ns.Theme
local L = ns.L

-- Pinned chains: the "Pin" button beside "Back to all quests" (MainWindow.lua, in the chain view) puts that chain
-- into its own small floating window, so it can be checked without leaving whatever else the player is doing (or
-- the main window closed). Up to MAX_PINS at once, stacked one under another; each window's bar folds it down to
-- just the bar (its quest's name) or back up to the tree, and only one is unfolded at a time (clicking a folded
-- one's bar unfolds it and folds whichever was up) -- an accordion, so the stack never grows past one tree's height.
-- Saved (ns.char.pinnedChains), so they are still there after a /reload. A quest inside one is focused (Focus
-- window), the same click a tracked quest's row gives elsewhere.
local MAX_PINS = 5
local BAR_H = 22
local WIN_W, TREE_W, TREE_H = 280, 260, 190
local GAP = 4

local pins = {}  -- [questId] = { entryId, questId, frame, treeView, bar, treeHolder }
local order = {} -- questId, in pin order (top to bottom; mirrors ns.char.pinnedChains)
local ready = false -- the quest log is loaded (see Pin_Init)

local function questDef(id)
    local def = ns.FindQuestDef(id)
    if def then return def end
    return { id = id, name = C_QuestLog.GetTitleForQuestID(id) or ("Quest " .. id) }
end

function ns.Pin_IsPinned(questId)
    return pins[questId] ~= nil
end

function ns.Pin_Count()
    return #order
end

-- The pin's own TreeView instance (its canvas, node pool...); used by tests, and by anything that needs to tell
-- a pinned chain's nodes from the main tree's (both can show the same quest at once).
function ns.Pin_TreeView(questId)
    return pins[questId] and pins[questId].treeView
end

-- Where the stack's top window sits; saved like the focus window's (ns.char.pinnedWindow).
local function applyPosition(frame)
    frame:ClearAllPoints()
    local saved = ns.char and ns.char.pinnedWindow
    if saved then
        frame:SetPoint(saved.point, UIParent, saved.relPoint, saved.x, saved.y)
    else
        frame:SetPoint("RIGHT", UIParent, "RIGHT", -60, -140)
    end
end

local function savePosition(frame)
    local point, _, relPoint, x, y = frame:GetPoint()
    ns.char.pinnedWindow = { point = point, relPoint = relPoint, x = x, y = y }
end

-- Expanded (the tree shows) or folded (just the bar); only one pin is expanded at a time.
local function isExpanded(questId)
    return ns.char and ns.char.pinExpanded == questId
end

-- Stacks the pins top to bottom under the first one's own position; each one's height depends on whether it (and
-- only it) is expanded.
local function layoutStack()
    local prev
    for _, id in ipairs(order) do
        local p = pins[id]
        local h = BAR_H + (isExpanded(id) and (GAP + TREE_H) or 0)
        p.frame:SetHeight(h)
        p.treeHolder:SetShown(isExpanded(id))
        p.frame:ClearAllPoints()
        if prev then
            p.frame:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -GAP)
            p.frame:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, -GAP)
        else
            applyPosition(p.frame)
            p.frame:SetWidth(WIN_W)
        end
        prev = p.frame
    end
end

-- Draws (or redraws) the pin's chain: the whole connected set (even a lone quest), auto-scaled to fit TREE_W x
-- TREE_H -- a pinned chain is meant for a glance, not panning and zooming a big tree.
local function renderPin(p)
    local d = ns.entries[p.entryId]
    if not d then return end
    local set = ns.ChainMembers(d, p.questId)
    p.treeView:Render(d.quests, function(q) return set[q.id] == true end, nil)
    local w = math.max(1, p.treeView.canvas:GetWidth())
    local h = math.max(1, p.treeView.canvas:GetHeight())
    local scale = math.min(1, TREE_W / w, TREE_H / h)
    p.treeView.canvas:SetScale(scale)
    p.treeView:SetZoom(scale)
    p.treeView.canvas:ClearAllPoints()
    p.treeView.canvas:SetPoint("TOP", p.treeHolder, "TOP", 0, 0)
end

local function refreshBar(p)
    local def = questDef(p.questId)
    p.bar.text:SetText(ns.QuestTitle(p.questId, def.name))
end

local function createPinFrame(p)
    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    frame:SetBackdropColor(T.rgba("obsidian", 0.9))
    frame:SetBackdropBorderColor(T.rgba("brass", 0.9))

    -- the bar: the quest's name, a fold/unfold chevron, and an unpin (x); clicking it (not the x) folds/unfolds
    local bar = CreateFrame("Button", nil, frame)
    bar:SetHeight(BAR_H)
    bar:SetPoint("TOPLEFT")
    bar:SetPoint("TOPRIGHT")
    bar.text = T.Text(bar, "small", "gold")
    bar.text:SetPoint("LEFT", 8, 0)
    bar.text:SetPoint("RIGHT", -(BAR_H + 4), 0)
    bar.text:SetJustifyH("LEFT")
    bar.text:SetWordWrap(false)
    local close = T.CreateIconButton(bar, "close", BAR_H - 4, CLOSE or L["Close"])
    close:SetPoint("RIGHT", -2, 0)
    close:SetScript("OnClick", function() ns.Pin_Toggle(p.entryId, p.questId) end)
    bar:SetScript("OnClick", function() ns.Pin_SetExpanded(p.questId, not isExpanded(p.questId)) end)
    bar:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:AddLine(isExpanded(p.questId) and L["Click to fold it"] or L["Click to show the chain"], 0.5, 0.8, 1)
        GameTooltip:Show()
    end)
    bar:SetScript("OnLeave", GameTooltip_Hide)
    frame.bar = bar
    p.bar = bar

    -- dragging the bar of the top pin moves the whole stack
    bar:RegisterForDrag("LeftButton")
    bar:SetScript("OnDragStart", function()
        if order[1] == p.questId then frame:StartMoving() end
    end)
    bar:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        if order[1] == p.questId then savePosition(frame) end
    end)
    frame:SetMovable(true)

    local treeHolder = CreateFrame("Frame", nil, frame)
    treeHolder:SetPoint("TOPLEFT", 0, -(BAR_H + GAP))
    treeHolder:SetSize(TREE_W, TREE_H)
    -- not every client has SetClipsChildren; renderPin's auto-fit scale keeps the tree inside it anyway
    if treeHolder.SetClipsChildren then treeHolder:SetClipsChildren(true) end
    p.treeHolder = treeHolder

    p.treeView = ns.NewTreeView(treeHolder, {
        -- a click on a quest of a pinned chain focuses it (Focus window), as a tracked quest's row does elsewhere
        onClick = function(quest) ns.Focus_Toggle(quest.id) end,
    })
    p.frame = frame
end

-- "Pin" (or "Unpin"): toggles whether the chain the quest `questId` (of entry `entryId`) is in is pinned.
function ns.Pin_Toggle(entryId, questId)
    if pins[questId] then
        pins[questId].frame:Hide()
        pins[questId] = nil
        for i, id in ipairs(order) do
            if id == questId then table.remove(order, i) break end
        end
        if ns.char.pinExpanded == questId then ns.char.pinExpanded = nil end
        if ns.char then
            local list = {}
            for _, id in ipairs(order) do list[#list + 1] = pins[id] and { entryId = pins[id].entryId, questId = id } end
            ns.char.pinnedChains = list
        end
        layoutStack()
        return
    end
    if #order >= MAX_PINS then
        ns.Print(L["Already %d chains pinned (the most at once)."]:format(MAX_PINS))
        return
    end
    local p = { entryId = entryId, questId = questId }
    pins[questId] = p
    order[#order + 1] = questId
    createPinFrame(p)
    refreshBar(p)
    if ns.char then
        ns.char.pinnedChains = ns.char.pinnedChains or {}
        ns.char.pinnedChains[#ns.char.pinnedChains + 1] = { entryId = entryId, questId = questId }
    end
    ns.Pin_SetExpanded(questId, true)
    p.frame:Show()
end

-- Only one pin is expanded at a time (the accordion): expanding one folds whatever else was up.
function ns.Pin_SetExpanded(questId, on)
    if not ns.char then return end
    if on then
        ns.char.pinExpanded = questId
        local p = pins[questId]
        if p then renderPin(p) end
    elseif ns.char.pinExpanded == questId then
        ns.char.pinExpanded = nil
    end
    layoutStack()
end

-- Quests changed (turned in, accepted...): the expanded pin's chain may have too.
function ns.Pin_Refresh()
    if not ready then return end
    for _, id in ipairs(order) do
        local p = pins[id]
        if isExpanded(id) then renderPin(p) end
        refreshBar(p)
    end
end

-- Restores the pins saved from last time (ns.char.pinnedChains), once the quest data and ns.char are both ready.
local function restore()
    if ready or not (ns.char and ns.entries) then return end
    ready = true
    for _, saved in ipairs(ns.char.pinnedChains or {}) do
        if ns.entries[saved.entryId] and not pins[saved.questId] and #order < MAX_PINS then
            local p = { entryId = saved.entryId, questId = saved.questId }
            pins[saved.questId] = p
            order[#order + 1] = saved.questId
            createPinFrame(p)
            refreshBar(p)
            renderPin(p)
            p.frame:Show()
        end
    end
    layoutStack()
end

local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:SetScript("OnEvent", restore)
