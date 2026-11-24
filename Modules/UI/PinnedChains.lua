local _, ns = ...
local C_QuestLog = ns.QuestLog or C_QuestLog -- never the game's table directly (QuestLogCompat.lua)
local T = ns.Theme
local L = ns.L

-- Pinned chains: the "Pin" button beside "Back to all quests" (MainWindow.lua, in the chain view) puts that chain
-- into its own small floating window, so it can be checked without leaving whatever else the player is doing (or
-- the main window closed). Up to MAX_PINS at once, stacked one under another; each window's bar folds it down to
-- just the bar (its quest's name) or back up to the tree, and only one is unfolded at a time (clicking a folded
-- one's bar unfolds it and folds whichever was up) -- an accordion, so the stack never grows past one tree's height.
-- Expanded, it pans and zooms (mouse wheel, drag) and resizes (the grip) like the main tree, each pin remembering
-- its own size and zoom. Saved (ns.char.pinnedChains), so they are still there after a /reload. A quest inside one
-- is focused (Focus window), the same click a tracked quest's row gives elsewhere.
local MAX_PINS = 5
local BAR_H, GAP = 22, 4
local DEFAULT_W, DEFAULT_TREE_H = 280, 190
local MIN_W, MIN_TREE_H = 180, 120
local MAX_W, MAX_TREE_H = 520, 420
local ZOOM_MIN, ZOOM_MAX, ZOOM_STEP = 0.35, 1.6, 1.15

local pins = {}  -- [questId] = { entryId, questId, frame, bar, scrollArea, holder, treeView, w, treeH, zoom, offX, offY }
local order = {} -- questId, in pin order (top to bottom; mirrors ns.char.pinnedChains)
local ready = false -- the quest log is loaded (see restore, at the end)

-- Dragging the grip: like panning (below), driven by OnUpdate rather than StartSizing/StopMovingOrSizing, which
-- some clients don't fire reliably for a frame anchored to another floating frame instead of UIParent. One grip is
-- ever visible at a time (only the expanded pin has one), so one dragger, shared, is enough. Widening or narrowing
-- (not the height) is applied to every pin, so the stack's bars stay the same width as its tree.
local resizer = CreateFrame("Frame", nil, UIParent)
resizer:Hide()

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

-- The pin's own zoom, and its window size (width, tree area height); used by tests and Pin_Refresh's callers.
function ns.Pin_Geometry(questId)
    local p = pins[questId]
    return p and p.zoom, p and p.w, p and p.treeH
end

-- The pin's own floating frame (its bar, scroll area, resize grip...); used by tests.
function ns.Pin_Frame(questId)
    return pins[questId] and pins[questId].frame
end

-- The grip's shared drag-driver (see createPinFrame); used by tests to tick a resize in progress.
function ns.Pin_Resizer()
    return resizer
end

-- Where the stack's top window sits; saved like the focus window's (ns.char.pinnedWindow).
-- A corner anchor (never "RIGHT"/"CENTER"/...): with only one point pinned, growing the frame (the resize grip)
-- would otherwise grow it from the middle outward on that axis, not from one edge like an ordinary window.
local CORNERS = { TOPLEFT = true, TOPRIGHT = true, BOTTOMLEFT = true, BOTTOMRIGHT = true }
local function applyPosition(frame)
    frame:ClearAllPoints()
    local saved = ns.char and ns.char.pinnedWindow
    if saved and CORNERS[saved.point] then
        frame:SetPoint(saved.point, UIParent, saved.relPoint, saved.x, saved.y)
    else
        frame:SetPoint("TOPLEFT", UIParent, "TOPRIGHT", -340, -200)
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

-- The saved list (ns.char.pinnedChains), rebuilt from the live pins, in their current order.
local function saveList()
    if not ns.char then return end
    local list = {}
    for _, id in ipairs(order) do
        local p = pins[id]
        list[#list + 1] = { entryId = p.entryId, questId = id, w = p.w, treeH = p.treeH, zoom = p.zoom }
    end
    ns.char.pinnedChains = list
end

-- Stacks the pins top to bottom under the first one's own position; each one's height depends on whether it (and
-- only it) is expanded, and (expanded) on its own saved size. Sizes are re-applied every time (live, while the
-- grip is dragged), but a pin's anchor is only touched when its place in the stack actually changes -- top pin, or
-- which pin it now follows -- never on every call, or a resize in progress would re-anchor the very pin being
-- resized back to its last saved position each tick, undoing a move that hasn't been dragged-and-dropped again.
local function layoutStack()
    local prev
    for _, id in ipairs(order) do
        local p = pins[id]
        local expanded = isExpanded(id)
        local h = BAR_H + (expanded and (GAP + p.treeH) or 0)
        p.frame:SetSize(p.w, h)
        p.scrollArea:SetShown(expanded)
        p.grip:SetShown(expanded)
        if prev == nil then
            if p.stackedUnder ~= nil then
                p.frame:ClearAllPoints()
                applyPosition(p.frame)
                p.stackedUnder = nil
            end
        elseif p.stackedUnder ~= prev then
            p.frame:ClearAllPoints()
            p.frame:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -GAP)
            p.stackedUnder = prev
        end
        prev = p.frame
    end
end

-- Resizes the holder to fit the canvas (bigger) or the view (smaller, so the tree centers in it); offX/offY are
-- where the canvas starts inside it, for the margin the centering leaves.
local function syncPinHolder(p)
    local scale = p.treeView.canvas:GetScale() or 1
    local cw, ch = p.treeView.canvas:GetWidth() * scale, p.treeView.canvas:GetHeight() * scale
    local w = math.max(cw, p.scrollArea:GetWidth() or 0)
    local h = math.max(ch, p.scrollArea:GetHeight() or 0)
    p.holder:SetSize(math.max(1, w), math.max(1, h))
    p.offX, p.offY = (w - cw) / 2, (h - ch) / 2
    p.treeView.canvas:ClearAllPoints()
    p.treeView.canvas:SetPoint("TOPLEFT", p.holder, "TOPLEFT", p.offX / scale, -p.offY / scale)
end

-- Live, while the grip is dragged (see createPinFrame): wider or narrower applies to the whole stack, taller or
-- shorter only to the pin being resized.
resizer:SetScript("OnUpdate", function(self)
    local p = self.pin
    local cx, cy = GetCursorPosition()
    local scale = p.frame:GetEffectiveScale()
    local w = math.max(MIN_W, math.min(MAX_W, self.startW + (cx - self.startX) / scale))
    local treeH = math.max(MIN_TREE_H, math.min(MAX_TREE_H, self.startTreeH + (self.startY - cy) / scale))
    for _, id in ipairs(order) do pins[id].w = w end
    p.treeH = treeH
    layoutStack()
    syncPinHolder(p)
end)

local function scrollTo(p, x, y)
    local maxX = math.max(0, p.holder:GetWidth() - p.scrollArea:GetWidth())
    local maxY = math.max(0, p.holder:GetHeight() - p.scrollArea:GetHeight())
    p.scrollArea:SetHorizontalScroll(math.max(0, math.min(x, maxX)))
    p.scrollArea:SetVerticalScroll(math.max(0, math.min(y, maxY)))
end

-- Zooms to `z`, keeping the point at (cx, cy) of the view (in its own coordinates) where it is; nil cx/cy: the
-- view's own center (the zoom buttons would use this; there are none here, only the wheel, which always gives one).
local function applyZoom(p, z, cx, cy)
    z = math.max(ZOOM_MIN, math.min(ZOOM_MAX, z))
    if z == p.zoom and cx then return end
    cx, cy = cx or (p.scrollArea:GetWidth() or 0) / 2, cy or (p.scrollArea:GetHeight() or 0) / 2
    local x, y = p.scrollArea:GetHorizontalScroll(), p.scrollArea:GetVerticalScroll()
    local contentX, contentY = (x + cx - (p.offX or 0)) / p.zoom, (y + cy - (p.offY or 0)) / p.zoom
    p.zoom = z
    p.treeView.canvas:SetScale(z)
    p.treeView:SetZoom(z)
    syncPinHolder(p)
    scrollTo(p, p.offX + contentX * z - cx, p.offY + contentY * z - cy)
end

-- Draws (or redraws) the pin's chain: the whole connected set (even a lone quest). The first time (no zoom saved
-- yet), it is scaled to fit the default tree area whole, so a small chain (most of them) needs no zooming at all;
-- after that, whatever zoom and scroll position the player left it at is kept across refreshes.
local function renderPin(p)
    local d = ns.entries[p.entryId]
    if not d then return end
    local set = ns.ChainMembers(d, p.questId)
    p.treeView:Render(d.quests, function(q) return set[q.id] == true end, nil)
    if not p.zoom then
        local w = math.max(1, p.treeView.canvas:GetWidth())
        local h = math.max(1, p.treeView.canvas:GetHeight())
        p.zoom = math.max(ZOOM_MIN, math.min(1, p.w / w, p.treeH / h))
        p.treeView.canvas:SetScale(p.zoom)
        p.treeView:SetZoom(p.zoom)
    end
    syncPinHolder(p)
end

local function refreshBar(p)
    local def = questDef(p.questId)
    p.bar.text:SetText(ns.QuestTitle(p.questId, def.name))
end

local function createPinFrame(p)
    p.w, p.treeH = p.w or DEFAULT_W, p.treeH or DEFAULT_TREE_H
    p.stackedUnder = "unset" -- forces layoutStack's first call to anchor it, whichever role it gets

    local frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    frame:SetBackdropColor(T.rgba("obsidian", 0.9))
    frame:SetBackdropBorderColor(T.rgba("brass", 0.9))
    frame:SetMovable(true)

    -- the bar: the quest's name and an unpin (x); clicking it (not the x) folds/unfolds the tree
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

    -- the tree: scrollable (wheel zoom, drag to pan), like the main window's, but its own per pin. A corner short
    -- of the grip (below): the main window's own grip sits clear of its treeScroll the same way, so the scroll
    -- area's mouse handling never competes with it for the click.
    local GRIP_SIZE = 16
    local scrollArea = CreateFrame("ScrollFrame", nil, frame)
    scrollArea:SetPoint("TOPLEFT", 0, -(BAR_H + GAP))
    scrollArea:SetPoint("BOTTOMRIGHT", -GRIP_SIZE, GRIP_SIZE)
    scrollArea:EnableMouse(true)
    scrollArea:RegisterForDrag("LeftButton")
    p.scrollArea = scrollArea
    local holder = CreateFrame("Frame", nil, scrollArea)
    holder:SetSize(1, 1)
    scrollArea:SetScrollChild(holder)
    p.holder = holder

    p.treeView = ns.NewTreeView(holder, {
        -- a click on a quest of a pinned chain focuses it (Focus window), as a tracked quest's row does elsewhere
        onClick = function(quest) ns.Focus_Toggle(quest.id) end,
        onDragStart = function() p.startPan() end,
        onDragStop = function() p.stopPan() end,
    })

    -- panning: a drag of the background, or of a quest (treeView's onDragStart/onDragStop, above)
    local dragger = CreateFrame("Frame", nil, scrollArea)
    dragger:Hide()
    dragger:SetScript("OnUpdate", function(self)
        local cx, cy = GetCursorPosition()
        local scale = scrollArea:GetEffectiveScale()
        scrollTo(p, self.startH - (cx - self.startX) / scale, self.startV + (cy - self.startY) / scale)
    end)
    function p.startPan()
        dragger.startX, dragger.startY = GetCursorPosition()
        dragger.startH, dragger.startV = scrollArea:GetHorizontalScroll(), scrollArea:GetVerticalScroll()
        dragger:Show()
    end
    function p.stopPan() dragger:Hide() end
    scrollArea:SetScript("OnDragStart", p.startPan)
    scrollArea:SetScript("OnDragStop", p.stopPan)
    scrollArea:SetScript("OnHide", function() dragger:Hide() end)

    -- wheel: zoom, centered on the cursor; shift/ctrl: scroll sideways/vertically (as the main tree)
    scrollArea:SetScript("OnMouseWheel", function(self, delta)
        local x, y = self:GetHorizontalScroll(), self:GetVerticalScroll()
        if IsShiftKeyDown() then
            scrollTo(p, x - delta * 60, y)
        elseif IsControlKeyDown() then
            scrollTo(p, x, y - delta * 60)
        else
            local px, py = GetCursorPosition()
            local scale = self:GetEffectiveScale()
            applyZoom(p, p.zoom * (delta > 0 and ZOOM_STEP or 1 / ZOOM_STEP),
                px / scale - (self:GetLeft() or 0), (self:GetTop() or 0) - py / scale)
        end
    end)
    scrollArea:HookScript("OnSizeChanged", function() syncPinHolder(p) end)

    -- the resize grip: the whole window grows or shrinks (the tree area, under the bar); saved once released.
    -- Clear of the scroll area (above) and raised well over it, so it always gets the click, never the tree
    -- scrolling underneath it.
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(GRIP_SIZE, GRIP_SIZE)
    grip:SetPoint("BOTTOMRIGHT", 0, 0)
    grip:SetFrameLevel(scrollArea:GetFrameLevel() + 10)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:RegisterForDrag("LeftButton")
    grip:SetScript("OnDragStart", function()
        resizer.pin = p
        resizer.startX, resizer.startY = GetCursorPosition()
        resizer.startW, resizer.startTreeH = p.w, p.treeH
        resizer:Show()
    end)
    grip:SetScript("OnDragStop", function()
        resizer:Hide()
        saveList()
    end)
    p.grip = grip

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
        if ns.char and ns.char.pinExpanded == questId then ns.char.pinExpanded = nil end
        saveList()
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
    saveList()
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
            local p = { entryId = saved.entryId, questId = saved.questId, w = saved.w, treeH = saved.treeH, zoom = saved.zoom }
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
