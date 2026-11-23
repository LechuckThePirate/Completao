local ADDON, ns = ...
local C_QuestLog = ns.QuestLog or C_QuestLog -- never the game's table directly (QuestLogCompat.lua)
local T = ns.Theme

local LIST_W, NODE_W, NODE_H, GAP_X, GAP_Y, PAD = 210, 175, 54, 56, 20, 20
local NODE_ICON, NODE_ICONS = 14, 5 -- size and most of the reward item icons in a node
local NODE_PAD = 9 -- room the metal frame of a node takes

-- The icon of an item, from what the client knows of it without loading it (a question mark when it knows nothing).
local function itemIcon(id)
    local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local icon = f and select(5, f(id))
    return icon or 134400
end

-- by status: done green, in the log gold (it pulses in the tree), available to take now amber, locked slate
local STATUS_COLORS = {
    done      = { T.rgba("ready") },
    active    = { T.rgba("gold") },
    available = { T.rgba("active") },
    locked    = { T.rgba("locked") },
    missed    = { T.rgba("danger") },
}
local STATUS_LABELS = {
    done = ns.L["Completed"], active = ns.L["In progress"], available = ns.L["Available"], locked = ns.L["Locked"],
    missed = ns.L["No longer available"],
}
-- a repeatable quest's title, in the tree: the blue the game gives them
local REPEATABLE_COLOR = { 0.45, 0.80, 1.00 }
ns.STATUS_COLORS, ns.STATUS_LABELS = STATUS_COLORS, STATUS_LABELS

local HEADER_H, ENTRY_H, ENTRY_INDENT = 26, 36, 10
local NAV_H = 26 -- the four views at the top of the side panel
local BAR_H = 46 -- the window's header bar
local MEDALLION = 96 -- the compass in the top-left corner
local LIST_TOP = 90 -- the side panel's list starts under the medallion
-- The side panel collapses to a strip of icons (a tooltip gives each one's name)
local COLLAPSED_W, ICON_BTN_H, TOGGLE_H = 64, 30, 20
local function collapsed() return ns.char and ns.char.sideCollapsed and true or false end
local function sideW() return collapsed() and COLLAPSED_W or LIST_W end
-- The side list's scroll bar sits between the list and the main area; when the list fits, there is no bar and
-- the main area takes its room (SCROLL_W) instead of leaving a gap. Set by refreshList, which knows the list's
-- height.
local SCROLL_W = 22
local sideScrolls = false
local function mainLeft() return sideW() + 30 - (sideScrolls and 0 or SCROLL_W) end
local function treeLeft() return mainLeft() - 4 end
local treeBarUpdate -- re-checks whether the tree needs its scroll bar (see createFrame)
-- wide enough by default for the side panel, the tree and the quest drawer side by side
local MIN_W, MIN_H, DEFAULT_W, DEFAULT_H = 700, 380, 1120, 620

local selectedId, expandedCat, listInitialized, viewRestored
local headerButtons, listButtons, nodeButtons, lines = {}, {}, {}, {}
local frame, canvas, emptyText
-- The scroll child. The canvas inside it is scaled by the zoom, but the client limits the scroll to the
-- child's own size (it ignores the scale), so the holder is kept at the size the canvas has on screen.
local holder
local function syncHolder()
    if not holder then return end
    local scale = canvas:GetScale() or 1
    holder:SetSize(math.max(1, canvas:GetWidth() * scale), math.max(1, canvas:GetHeight() * scale))
end
local openedWithLog = false -- the quest log opened the window (see the end)
-- Global search (Search.lua): with searchMode, the main area shows the form and the results table
-- instead of the tree; treeWidgets is what gets hidden then.
local searchMode = false
local treeWidgets = {}
local searchButtons, nodePos = {}, {}
local sideToggle

local function showNodeTooltip(btn)
    local q, status, reasons = btn.quest, btn.status, btn.reasons
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ns.QuestTitle(q.id, q.name), 1, 1, 1)
    local c = STATUS_COLORS[status]
    -- done by other characters: who, in place of the plain "Completed"
    local alt = status == "done" and not C_QuestLog.IsQuestFlaggedCompleted(q.id) and ns.DoneByAltsText(q.id)
    GameTooltip:AddLine(alt and ns.L["Completed by %s"]:format(alt) or STATUS_LABELS[status], c[1], c[2], c[3])
    if btn.readyToTurnIn then GameTooltip:AddLine(ns.L["Ready to turn in"], 0.35, 1, 0.35) end
    if q.repeatable then GameTooltip:AddLine(ns.L["Repeatable"], REPEATABLE_COLOR[1], REPEATABLE_COLOR[2], REPEATABLE_COLOR[3]) end
    for _, w in ipairs(ns.QuestWarnings(q)) do GameTooltip:AddLine(w, 1, 0.55, 0.1, true) end
    if q.level then
        GameTooltip:AddLine(ns.L["Level %d%s"]:format(q.level, q.minLevel and ns.L[" (min %d)"]:format(q.minLevel) or ""), 0.8, 0.8, 0.8)
    end
    if q.giver then
        GameTooltip:AddLine(ns.L["Starts at: "] .. q.giver, 0.8, 0.8, 0.8)
    end
    if btn.elite then
        GameTooltip:AddLine(ns.L["Elite: recommended with a group"], 1, 0.4, 0.4)
    end
    if q.dungeon then
        local e = ns.entries[q.dungeon]
        GameTooltip:AddLine(ns.L["Done inside the instance: %s"]:format(e and ns.EntryName(e) or "?"), 1, 0.82, 0.2)
    end
    for _, r in ipairs(reasons or {}) do
        GameTooltip:AddLine(r, 1, 0.3, 0.3)
    end
    if q.note then
        GameTooltip:AddLine(q.note, 1, 0.82, 0, true)
    end
    GameTooltip:AddLine("ID " .. q.id, 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

local function onNodeClick(self, button)
    if button == "RightButton" then
        ns.QuestMenu(self, self.quest)
        return
    end
    ns.Detail_Toggle(self.quest)
    ns.UI_Refresh()
end

local function getNodeButton(i)
    local b = nodeButtons[i]
    if b then return b end
    b = CreateFrame("Button", nil, canvas)
    b:SetSize(NODE_W, NODE_H)
    -- a stone plate in a metal frame; around it a halo in the status's color (none when locked), which pulses
    -- on the quest in the log. The halo is a frame of its own under the plate, so it can fade by itself.
    b.glowFrame = CreateFrame("Frame", nil, b)
    b.glowFrame:SetAllPoints()
    b.glowFrame:SetFrameLevel(math.max(0, b:GetFrameLevel() - 1))
    b.glow = T.NineSlice(b.glowFrame, T.MEDIA .. "NodeGlow", 128, 64, 24, 22, 11, "BACKGROUND", 0, true)
    b.plate = T.NineSlice(b, T.MEDIA .. "NodeFrame", 128, 64, 16, 14, 0, "BACKGROUND", 1, true)
    b.pulse = b.glowFrame:CreateAnimationGroup()
    local fade = b.pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.3)
    fade:SetDuration(0.9)
    fade:SetSmoothing("IN_OUT")
    b.pulse:SetLooping("BOUNCE")
    -- locked: a padlock before the title
    b.lock = b:CreateTexture(nil, "OVERLAY")
    b.lock:SetSize(12, 12)
    b.lock:SetPoint("TOPLEFT", NODE_PAD, -NODE_PAD + 1)
    T.SetStatusIcon(b.lock, "lock")
    b.lock:Hide()
    b.text = T.Text(b, "quest")
    b.text:SetPoint("TOPLEFT", NODE_PAD, -NODE_PAD + 2)
    b.text:SetPoint("BOTTOMRIGHT", -NODE_PAD, 18) -- (the XP line takes the bottom of the box)
    b.text:SetJustifyH("LEFT")
    b.text:SetJustifyV("TOP")
    b.xp = T.Text(b, "data", "muted")
    b.xp:SetPoint("BOTTOMRIGHT", -NODE_PAD, 7)
    b.xp:SetJustifyH("RIGHT")
    -- the bottom-left of the box: the money, then small icons of the items the quest gives (textures, so a click still reaches the box)
    b.money = T.Text(b, "data", "muted")
    b.money:SetPoint("BOTTOMLEFT", NODE_PAD, 7)
    b.money:SetJustifyH("LEFT")
    b.icons = {}
    for k = 1, NODE_ICONS do
        -- buttons, for the item's tooltip on hover; a click goes on to the box
        local icon = CreateFrame("Button", nil, b)
        icon:SetSize(NODE_ICON, NODE_ICON)
        icon.tex = icon:CreateTexture(nil, "ARTWORK")
        icon.tex:SetAllPoints()
        icon.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        icon:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        icon:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.itemID)
            GameTooltip:Show()
        end)
        icon:SetScript("OnLeave", GameTooltip_Hide)
        icon:SetScript("OnClick", function(self, button) onNodeClick(self:GetParent(), button) end)
        icon:Hide()
        b.icons[k] = icon
    end
    -- top-left corner badge, over the border: a dragon head for elite quests, or a dungeon door for
    -- quests done inside an instance (elite takes priority; texture and color are set on each redraw)
    b.badge = b:CreateTexture(nil, "OVERLAY")
    b.badge:SetSize(16, 16)
    b.badge:SetPoint("TOPLEFT", -6, 6)
    b.badge:Hide()
    -- "ready to turn in" check: on the top-right corner, over the border
    b.ready = b:CreateTexture(nil, "OVERLAY")
    b.ready:SetSize(18, 18)
    b.ready:SetPoint("TOPRIGHT", 6, 6)
    b.ready:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    b.ready:Hide()
    b:SetScript("OnEnter", showNodeTooltip)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", onNodeClick)
    nodeButtons[i] = b
    return b
end

local function getLine(i)
    local l = lines[i]
    if l then return l end
    l = canvas:CreateLine(nil, "BACKGROUND")
    l:SetThickness(2)
    lines[i] = l
    return l
end

-- Tree filters: options saved in ns.char.filters + the search text.
local HIGH_LEVEL_ALPHA, LOW_LEVEL_ALPHA = 0.5, 0.72
-- with a quest selected: whatever isn't part of its chain is dimmed; its path goes green
local OFF_CHAIN_ALPHA, OFF_CHAIN_LINE_ALPHA = 0.3, 0.2
local ZOOM_MIN, ZOOM_MAX, ZOOM_STEP = 0.35, 1.6, 1.15
local CHAIN_COLOR = { T.rgba("ready") }
local GOLD_LINE, FUTURE_LINE = { T.rgba("gold") }, { T.rgba("muted") }
local searchText = ""
local searchBox
-- A quest opened from elsewhere (a search result, "View chain", another addon): its whole chain is shown whatever the filters
-- say, as a set of quest ids, until the selection or a filter changes.
local pinned

-- Chains of an entry: each group of quests connected by prerequisites. Returns, by quest id, its chain's
-- data: size (number of quests), allDone (all done; loose done quests included), started (some done or in
-- the log), allLow (all low level) and headsTooHigh (every quest the chain starts with -- those with no
-- prerequisite inside it -- is above your level).
local function chainInfo(d)
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
    local function chainOf(root)
        local c = chains[root]
        if not c then
            c = { size = 0, allDone = true, started = false, allLow = true, heads = 0, headsHigh = 0 }
            chains[root] = c
        end
        return c
    end
    for id, q in pairs(set) do
        local c = chainOf(find(id))
        c.size = c.size + 1
        local isDone = ns.IsQuestDone(id)
        if not isDone then c.allDone = false end
        if isDone or C_QuestLog.IsOnQuest(id) then c.started = true end
        if not ns.IsLowLevel(q) then c.allLow = false end
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
    for id in pairs(set) do
        local c = chains[find(id)]
        info[id] = {
            size = c.size, allDone = c.allDone, started = c.started, allLow = c.allLow,
            headsTooHigh = c.heads > 0 and c.headsHigh == c.heads,
        }
    end
    return info
end

-- The quests connected to `id` by prerequisites (itself included) among the visible ones of the entry, as a set.
local function chainMembers(d, id)
    local byId, kids = {}, {}
    for _, q in ipairs(d.quests) do
        if ns.QuestVisible(q, d) then
            byId[q.id] = q
            for _, parent in ipairs(ns.ParentsOf(q)) do
                kids[parent] = kids[parent] or {}
                table.insert(kids[parent], q.id)
            end
        end
    end
    local set, queue = {}, {}
    if byId[id] then
        set[id] = true
        queue[1] = id
    end
    local i = 1
    while queue[i] do
        local q = byId[queue[i]]
        i = i + 1
        local near = {}
        for _, parent in ipairs(ns.ParentsOf(q)) do near[#near + 1] = parent end
        for _, child in ipairs(kids[q.id] or {}) do near[#near + 1] = child end
        for _, other in ipairs(near) do
            if byId[other] and not set[other] then
                set[other] = true
                queue[#queue + 1] = other
            end
        end
    end
    return set
end

-- Visibility predicate for an entry's tree: faction/race + the user's filters.
-- By level, chains are shown or hidden as a whole, so they are never cut in half:
--  * "too high" hides a chain when every quest it starts with is above your level; if you can start it,
--    all its steps show, even higher ones.
--  * "low level" hides a chain only when all its quests are grey.
-- A chain you have started (some quest done or in the log) is never hidden by level, and loose quests are
-- hidden by their own level unless they are in your log. "Completed" hides each completed quest.
local function makeFilter(d)
    local f = ns.char.filters
    local chains
    if f.hideLow or f.hideHigh then chains = chainInfo(d) end
    local needle = searchText ~= "" and searchText or nil
    return function(q)
        if not ns.QuestVisible(q, d) then return false end
        if pinned and pinned[q.id] then return true end
        local c = chains and chains[q.id]
        local onQuest = C_QuestLog.IsOnQuest(q.id)
        -- completed: each one on its own, even if its chain goes on (untick the filter to see them)
        if f.hideDone and ns.IsQuestDone(q.id) and not onQuest then return false end
        -- repeatable: the game never marks them done, so this is how they are put aside (the one in the log stays)
        if f.hideRepeatable and q.repeatable and not onQuest and ns.RepeatableDone(q.id) then return false end
        if c and c.size > 1 then
            if not c.started then
                if f.hideHigh and c.headsTooHigh then return false end
                if f.hideLow and c.allLow then return false end
            end
        elseif not onQuest then
            if f.hideLow and ns.IsLowLevel(q) then return false end
            if f.hideHigh and ns.IsTooHigh(q) then return false end
        end
        if needle then
            local cached = C_QuestLog.GetTitleForQuestID(q.id)
            local hit = (cached and cached:lower():find(needle, 1, true)) or q.name:lower():find(needle, 1, true)
            if not hit then return false end
        end
        return true
    end
end

local function renderTree(d)
    local layout = ns.BuildLayout(d.quests, makeFilter(d))

    -- what is not used is hidden at the end, not everything up front: a frame hidden and shown again during a
    -- redraw loses the click that was in progress on it
    emptyText:SetShown(layout.count == 0)
    if layout.count == 0 then
        local hasData = false
        for _, q in ipairs(d.quests) do
            if ns.QuestVisible(q, d) then hasData = true break end
        end
        emptyText:SetText(hasData and ns.L["No quests match the filters."] or ns.L["No quest data yet."])
    end
    canvas:SetSize(
        math.max(1, PAD * 2 + layout.cols * NODE_W + (layout.cols - 1) * GAP_X),
        math.max(1, PAD * 2 + layout.rows * NODE_H + (layout.rows - 1) * GAP_Y))
    syncHolder()

    -- With a quest selected: its path (what comes before and after, along the chain) is highlighted in
    -- green and the rest of the visible quests are dimmed.
    local chainSet
    local selected = ns.Detail_Current()
    if selected and layout.nodes[selected.id] then
        local kids, parents = {}, {}
        for _, e in ipairs(layout.edges) do
            kids[e.from] = kids[e.from] or {}
            table.insert(kids[e.from], e.to)
            parents[e.to] = parents[e.to] or {}
            table.insert(parents[e.to], e.from)
        end
        chainSet = { [selected.id] = true }
        local function walk(adjacent, id)
            for _, n in ipairs(adjacent[id] or {}) do
                if not chainSet[n] then
                    chainSet[n] = true
                    walk(adjacent, n)
                end
            end
        end
        walk(parents, selected.id)
        walk(kids, selected.id)
        -- opened from elsewhere: the whole chain it belongs to is lit, branches included, not only the path through it
        if pinned and pinned[selected.id] then
            for id in pairs(pinned) do
                if layout.nodes[id] then chainSet[id] = true end
            end
        end
    end

    local byId, i = {}, 0
    for k in pairs(nodePos) do nodePos[k] = nil end
    for id, n in pairs(layout.nodes) do
        nodePos[id] = { x = PAD + n.col * (NODE_W + GAP_X), y = PAD + n.row * (NODE_H + GAP_Y) }
        i = i + 1
        local b = getNodeButton(i)
        local status, reasons = ns.QuestStatus(n.quest)
        local c = STATUS_COLORS[status]
        b.quest, b.status, b.reasons = n.quest, status, reasons
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", canvas, "TOPLEFT",
            PAD + n.col * (NODE_W + GAP_X), -(PAD + n.row * (NODE_H + GAP_Y)))
        T.SliceColor(b.glow, c[1], c[2], c[3], 0.85)
        b.glowFrame:SetShown(status ~= "locked")
        if status == "active" then
            if not b.pulse:IsPlaying() then b.pulse:Play() end
        else
            b.pulse:Stop()
            b.glowFrame:SetAlpha(1)
        end
        -- the quest whose details are open: the gold frame
        local picked = ns.Detail_Current() and ns.Detail_Current().id == n.quest.id
        if picked and not b.goldBorder then T.ApplyGoldBorder(b, 12, 2) end
        if b.goldBorder then T.SetGoldBorderShown(b, picked) end
        local locked = status == "locked"
        b.lock:SetShown(locked)
        b.text:SetPoint("TOPLEFT", locked and NODE_PAD + 14 or NODE_PAD, -NODE_PAD + 2)
        local elite = ns.IsEliteQuest(n.quest.id)
        b.elite = elite
        if elite then
            b.badge:SetTexture("Interface\\Icons\\INV_Misc_Head_Dragon_01")
            b.badge:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            b.badge:SetVertexColor(1, 1, 1)
            b.badge:Show()
        elseif n.quest.dungeon then
            b.badge:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\Icons\\Dungeon.png")
            b.badge:SetTexCoord(0, 1, 0, 1)
            b.badge:SetVertexColor(1, 0.82, 0.2)
            b.badge:Show()
        else
            b.badge:Hide()
        end
        b.readyToTurnIn = status == "active" and ns.IsReadyToTurnIn(n.quest.id)
        b.ready:SetShown(b.readyToTurnIn)
        b.text:SetText(ns.QuestTitle(n.quest.id, n.quest.name))
        local xp = ns.QuestXP(n.quest.id)
        b.xp:SetText(xp > 0 and ("%s %s"):format(BreakUpLargeNumbers and BreakUpLargeNumbers(xp) or xp, ns.L["XP"]) or "")
        local reward = ns.REWARDS and ns.REWARDS[n.quest.id]
        b.money:SetText(reward and reward.money and ns.CoinString(reward.money) or "")
        -- the item icons go after the money while they fit before the XP
        local x = NODE_PAD + (reward and reward.money and b.money:GetStringWidth() + 4 or 0)
        local limit = NODE_W - NODE_PAD - (xp > 0 and b.xp:GetStringWidth() + 4 or 0)
        local ids = reward and ns.RewardItemIds(reward) or {}
        for k, icon in ipairs(b.icons) do
            local itemId = ids[k]
            if itemId and x + NODE_ICON <= limit then
                icon:ClearAllPoints()
                icon:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", x, 6)
                icon.itemID = itemId
                icon.tex:SetTexture(itemIcon(itemId))
                icon:Show()
                x = x + NODE_ICON + 2
            else
                icon:Hide()
            end
        end
        -- locked ones stay readable: muted slate, not dark grey on black
        if status == "locked" or status == "missed" then
            b.text:SetTextColor(T.rgba("muted"))
        elseif n.quest.repeatable then
            b.text:SetTextColor(REPEATABLE_COLOR[1], REPEATABLE_COLOR[2], REPEATABLE_COLOR[3])
        else
            b.text:SetTextColor(T.rgba("text"))
        end
        -- translucent when they don't fit your level (too high ones more than low level ones);
        -- done ones and the ones in your log are always shown sharp
        local alpha = 1
        if status ~= "done" and status ~= "active" then
            if ns.IsTooHigh(n.quest) then alpha = HIGH_LEVEL_ALPHA
            elseif ns.IsLowLevel(n.quest) then alpha = LOW_LEVEL_ALPHA end
        end
        if chainSet and not chainSet[id] then alpha = alpha * OFF_CHAIN_ALPHA end
        b:SetAlpha(alpha)
        b:Show()
        byId[id] = b
    end

    -- Connections run through the gaps between boxes, never over them: they leave the parent towards the
    -- vertical corridor on its right, go up or down to the gap between rows next to the child, cross along
    -- that gap to the corridor on the child's left and enter from its left side. Each row uses its own lane
    -- in the corridor, so lines from the same parent (or into the same child) share a trunk.
    local segCount = 0
    local lineAlpha, lineThickness = 0.85, 2
    local function segment(x1, y1, x2, y2, c)
        if x1 == x2 and y1 == y2 then return end
        segCount = segCount + 1
        local l = getLine(segCount)
        l:SetThickness(lineThickness)
        l:SetColorTexture(c[1], c[2], c[3], lineAlpha)
        l:SetStartPoint("TOPLEFT", canvas, x1, -y1)
        l:SetEndPoint("TOPLEFT", canvas, x2, -y2)
        l:Show()
    end
    local function colX(col) return PAD + col * (NODE_W + GAP_X) end
    local function rowY(row) return PAD + row * (NODE_H + GAP_Y) end
    local function gutterX(col, row) -- corridor right of column `col`, in `row`'s lane
        return colX(col) + NODE_W + GAP_X / 2 + ((row % 8) - 3.5) * 5
    end
    local function drawEdge(e, c)
        local a, b = layout.nodes[e.from], layout.nodes[e.to]
        local yA, yB = rowY(a.row) + NODE_H / 2, rowY(b.row) + NODE_H / 2
        local xA, xB = colX(a.col) + NODE_W, colX(b.col)
        if b.col <= a.col then
            segment(xA, yA, xB, yB, c) -- shouldn't happen (child to the left or in the same column)
        else
            local gA = gutterX(a.col, a.row)
            if b.col == a.col + 1 then
                segment(xA, yA, gA, yA, c)
                segment(gA, yA, gA, yB, c)
                segment(gA, yB, xB, yB, c)
            else
                local gB = gutterX(b.col - 1, b.row)
                local yCh = rowY(b.row) - GAP_Y / 2 + ((a.col % 3) - 1) * 3 -- gap between rows, above the child
                segment(xA, yA, gA, yA, c)
                segment(gA, yA, gA, yCh, c)
                segment(gA, yCh, gB, yCh, c)
                segment(gB, yCh, gB, yB, c)
                segment(gB, yB, xB, yB, c)
            end
        end
        -- an arrowhead where it enters the child: which way the chain goes
        segment(xB - 6, yB - 4, xB, yB, c)
        segment(xB - 6, yB + 4, xB, yB, c)
    end
    -- first the normal connections (fainter with a quest selected): gold where the player has been (out of a done
    -- quest), translucent slate towards what is still ahead; on top the selected path's, in green
    for _, e in ipairs(layout.edges) do
        if not (chainSet and chainSet[e.from] and chainSet[e.to]) then
            local walked = byId[e.from].status == "done"
            lineAlpha, lineThickness = chainSet and OFF_CHAIN_LINE_ALPHA or (walked and 0.9 or 0.45), 2
            drawEdge(e, walked and GOLD_LINE or FUTURE_LINE)
        end
    end
    if chainSet then
        lineAlpha, lineThickness = 1, 3
        for _, e in ipairs(layout.edges) do
            if chainSet[e.from] and chainSet[e.to] then drawEdge(e, CHAIN_COLOR) end
        end
    end
    for k = i + 1, #nodeButtons do nodeButtons[k]:Hide() end
    for k = segCount + 1, #lines do lines[k]:Hide() end
    if treeBarUpdate then treeBarUpdate() end
end

-- In zones, classes and professions only entries with some quest for this character (faction and race)
-- are listed; dungeons and raids always are, even with no data yet.
local HIDE_WHEN_EMPTY = {
    zones = true, classes = true, professions = true, battlegrounds = true, events = true, misc = true,
}

-- Alphabetical order by the shown name (in the client's language), ignoring case and accents.
local ACCENTS = {
    ["á"] = "a", ["é"] = "e", ["í"] = "i", ["ó"] = "o", ["ú"] = "u", ["ü"] = "u", ["ñ"] = "n", ["à"] = "a",
    ["è"] = "e", ["ì"] = "i", ["ò"] = "o", ["ù"] = "u", ["â"] = "a", ["ê"] = "e", ["î"] = "i", ["ô"] = "o",
    ["û"] = "u", ["ç"] = "c", ["ä"] = "a", ["ë"] = "e", ["ï"] = "i", ["ö"] = "o",
    ["Á"] = "a", ["É"] = "e", ["Í"] = "i", ["Ó"] = "o", ["Ú"] = "u", ["Ü"] = "u", ["Ñ"] = "n", ["À"] = "a",
    ["È"] = "e", ["Ì"] = "i", ["Ò"] = "o", ["Ù"] = "u", ["Â"] = "a", ["Ê"] = "e", ["Î"] = "i", ["Ô"] = "o",
    ["Û"] = "u", ["Ç"] = "c", ["Ä"] = "a", ["Ë"] = "e", ["Ï"] = "i", ["Ö"] = "o",
}
local function fold(s)
    return (s:lower():gsub("[\195][\128-\191]", ACCENTS))
end
local function sortKey(d)
    return fold(ns.EntryName(d))
end

-- The side panel's mini filter ("Filter zone..."): only the entries whose name has the text, in every section.
local zoneFilter = ""

local function entriesOf(catId)
    local items = {}
    -- Preferences "hide categories with no quests available or all done": an entry with nothing left to do is
    -- left out -- except the one being looked at, so it doesn't vanish under the player as they finish it
    local hideDone = ns.char and ns.char.hideDone
    for _, d in ipairs(ns.entryList) do
        if d.category == catId and (zoneFilter == "" or sortKey(d):find(zoneFilter, 1, true))
            and (not HIDE_WHEN_EMPTY[catId] or select(2, ns.EntryProgress(d)) > 0)
            and not (hideDone and not (d.id == selectedId and not searchMode) and not ns.EntryHasWork(d)) then
            items[#items + 1] = d
        end
    end
    -- dungeons and raids by level (minimum, maximum); the rest alphabetically; ties by name
    local byLevel = false
    for _, c in ipairs(ns.categories) do
        if c.id == catId then byLevel = c.sortByLevel end
    end
    local keys = {}
    for _, d in ipairs(items) do keys[d] = sortKey(d) end
    table.sort(items, function(a, b)
        if byLevel then
            if a.minLevel ~= b.minLevel then return (a.minLevel or 0) < (b.minLevel or 0) end
            if a.maxLevel ~= b.maxLevel then return (a.maxLevel or 0) < (b.maxLevel or 0) end
        end
        if keys[a] ~= keys[b] then return keys[a] < keys[b] end
        return a.id < b.id
    end)
    return items
end

-- Collapsed: the side panel's buttons only show an icon, so their name is in the tooltip.
local function showSideTooltip(self)
    if not (collapsed() and self.label) then return end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText(self.label)
    GameTooltip:Show()
end

local function selectEntry(id)
    pinned = nil
    ns.Detail_Hide()
    searchText = ""
    if searchBox then searchBox:SetText("") end
    selectedId = id
    ns.char.selected = id
    frame.treeScroll:SetHorizontalScroll(0)
    frame.treeScroll:SetVerticalScroll(0)
end

-- Collapsed side panel: a section's icon opens a menu with its entries, next to the strip.
local function openEntryMenu(self)
    local items = entriesOf(self.cat.id)
    local options = {}
    for i, d in ipairs(items) do
        local done, total = ns.EntryProgress(d)
        local sel = d.id == selectedId and not searchMode
        options[i] = { name = ("%s  %d/%d"):format(ns.EntryName(d), done, total), color = sel and { 1, 0.82, 0 } or nil }
    end
    ns.PopupMenu(self, options, function(_, i)
        searchMode = false
        expandedCat = self.cat.id
        ns.char.category = expandedCat
        selectEntry(items[i].id)
        ns.UI_Refresh()
    end, 230, "right")
end

local function onHeaderClick(self)
    if collapsed() then
        openEntryMenu(self)
        return
    end
    local catId = self.cat.id
    if expandedCat == catId then
        expandedCat = nil
    else
        expandedCat = catId
        local cur = ns.entries[selectedId]
        -- with the search open, opening a section only expands it (the search stays in view)
        if not searchMode and not (cur and cur.category == catId) then
            local items = entriesOf(catId)
            selectEntry(items[1] and items[1].id or nil)
        end
    end
    ns.char.category = expandedCat or false
    ns.UI_Refresh()
end

local function onEntryClick(self)
    searchMode = false
    selectEntry(self.entry.id)
    ns.UI_Refresh()
end

local function getHeaderButton(i)
    local b = headerButtons[i]
    if b then return b end
    b = CreateFrame("Button", nil, frame.listChild, "BackdropTemplate")
    b:SetHeight(HEADER_H)
    T.Style(b, "slate", false)
    -- a brass divider under each section
    b.divider = b:CreateTexture(nil, "BORDER")
    b.divider:SetPoint("BOTTOMLEFT", 0, 0)
    b.divider:SetPoint("BOTTOMRIGHT", 0, 0)
    b.divider:SetHeight(1)
    b.divider:SetColorTexture(T.rgba("inkMuted", 0.45))
    b:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
    b:GetHighlightTexture():SetVertexColor(0, 0, 0, 0.06)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(16, 16)
    b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    b.text = T.Text(b, "heading", "ink")
    b:SetScript("OnClick", onHeaderClick)
    b:SetScript("OnEnter", showSideTooltip)
    b:SetScript("OnLeave", GameTooltip_Hide)
    headerButtons[i] = b
    return b
end

local function getEntryButton(i)
    local b = listButtons[i]
    if b then return b end
    b = CreateFrame("Button", nil, frame.listChild, "BackdropTemplate")
    b:SetHeight(ENTRY_H)
    T.Style(b, "slate", false)
    b:SetBackdropColor(0, 0, 0, 0)
    b:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
    b:GetHighlightTexture():SetVertexColor(0, 0, 0, 0.06)
    -- the selected entry: a dark bar on its left
    b.mark = b:CreateTexture(nil, "ARTWORK")
    b.mark:SetPoint("TOPLEFT")
    b.mark:SetPoint("BOTTOMLEFT")
    b.mark:SetWidth(3)
    b.mark:SetColorTexture(T.rgba("inkSoft"))
    b.name = T.Text(b, "body", "ink")
    b.name:SetPoint("TOPLEFT", 9, -5)
    b.name:SetPoint("RIGHT", -6, 0)
    b.name:SetJustifyH("LEFT")
    b.name:SetWordWrap(false)
    b.sub = T.Text(b, "small", "inkMuted")
    b.sub:SetPoint("BOTTOMLEFT", 9, 7)
    -- how much of it is done: a 2 px bar along its bottom edge
    b.bar = T.CreateProgressBar(b, 2, "gold")
    b.bar.track:SetColorTexture(0, 0, 0, 0.18)
    b.bar:SetPoint("BOTTOMLEFT", 9, 2)
    b.bar:SetPoint("BOTTOMRIGHT", -6, 2)
    b:SetScript("OnClick", onEntryClick)
    listButtons[i] = b
    return b
end

-- The sections to list, each with its entries; with "hide categories with no quests available or all done" on,
-- the ones left without any entry are not.
local function visibleCategories()
    local list = {}
    for _, cat in ipairs(ns.categories) do
        local items = entriesOf(cat.id)
        if #items > 0 or not ((ns.char and ns.char.hideDone) or zoneFilter ~= "") then list[#list + 1] = { cat = cat, items = items } end
    end
    return list
end

-- The badges of the views at the top of the side panel: how many quests the log, the tracked ones and the ones ready
-- to turn in hold (the search has none).
local function navCounts()
    local counts = { log = 0, tracked = 0, turnin = 0 }
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        local id = info and not info.isHeader and info.questID
        if id and id > 0 then
            counts.log = counts.log + 1
            if ns.IsQuestTracked and ns.IsQuestTracked(id) then counts.tracked = counts.tracked + 1 end
            if ns.IsReadyToTurnIn(id) then counts.turnin = counts.turnin + 1 end
        end
    end
    return counts
end

local zoneBox -- the mini filter's box (createFrame)

local function refreshList()
    local narrow = collapsed()
    local listW = sideW() - 26
    local y, hi, ei = 0, 0, 0

    -- collapse / expand the panel
    sideToggle:ClearAllPoints()
    sideToggle:SetPoint("TOPLEFT", 0, -y)
    sideToggle:SetWidth(listW)
    sideToggle.tex:SetTexture(narrow and "Interface\\Buttons\\UI-SpellbookIcon-NextPage-Up"
        or "Interface\\Buttons\\UI-SpellbookIcon-PrevPage-Up")
    sideToggle.tex:ClearAllPoints()
    sideToggle.tex:SetPoint(narrow and "CENTER" or "LEFT", narrow and 0 or 4, 0)
    sideToggle.text:SetShown(not narrow)
    sideToggle.label = narrow and ns.L["Expand menu"] or nil
    y = y + TOGGLE_H + 4

    -- first block: the four views (the global search, the quest log, the tracked quests and the ones to turn in, all in
    -- the same table, Search.lua), the one open marked with a gold bar, each with its count
    local counts = navCounts()
    for _, b in ipairs(searchButtons) do
        local on = searchMode and ns.Search_Mode() == b.kind
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 0, -y)
        b:SetWidth(listW)
        b:SetHeight(narrow and ICON_BTN_H or NAV_H)
        b.tex:ClearAllPoints()
        b.tex:SetPoint(narrow and "CENTER" or "LEFT", narrow and 0 or 10, 0)
        b.text:SetShown(not narrow)
        b.label = narrow and b.title or nil
        b:SetBackdropColor(0, 0, 0, on and 0.14 or 0)
        b.mark:SetShown(on)
        b.text:SetTextColor(T.rgba(on and "ink" or "inkSoft"))
        local n = counts[b.kind]
        b.badge:SetShown(not narrow and n ~= nil and n > 0)
        if n then
            b.badge.text:SetText(tostring(n))
            b.badge:SetWidth(math.max(20, b.badge.text:GetStringWidth() + 10))
            b.badge.text:SetTextColor(T.rgba(b.kind == "turnin" and "ready" or "gold"))
        end
        y = y + b:GetHeight() + 2
    end
    y = y + 6

    -- second block: the catalogue, with the mini filter on top (not on the strip of icons)
    zoneBox:ClearAllPoints()
    zoneBox:SetShown(not narrow)
    if not narrow then
        zoneBox:SetPoint("TOPLEFT", 0, -y)
        zoneBox:SetWidth(listW)
        y = y + zoneBox:GetHeight() + 6
    end

    local filtering = zoneFilter ~= "" and not narrow
    local current = ns.entries[selectedId]
    for _, shown in ipairs(visibleCategories()) do
        local cat, items = shown.cat, shown.items
        -- filtering, every section with a match is open
        local open = (cat.id == expandedCat or filtering) and not narrow

        hi = hi + 1
        local h = getHeaderButton(hi)
        h.cat, h.open = cat, open
        h.label = narrow and ("%s (%d)"):format(cat.name, #items) or nil
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", 0, -y)
        h:SetWidth(listW)
        h:SetHeight(narrow and ICON_BTN_H or HEADER_H)
        h.icon:SetTexture(cat.icon)
        h.icon:ClearAllPoints()
        h.text:ClearAllPoints()
        if narrow then
            h.icon:SetPoint("CENTER", 0, 0)
            -- the section of the entry you are on
            local on = current and current.category == cat.id and not searchMode
            h:SetBackdropColor(T.rgba(on and "card" or "slate"))
            h:SetBackdropBorderColor(T.rgba(on and "gold" or "brass"))
            h.divider:Hide()
            T.SetGlyph(h, nil)
        else
            h.icon:SetPoint("LEFT", 6, 0)
            h.text:SetPoint("LEFT", 28, 0)
            h:SetBackdropColor(T.rgba("slate", 0))
            h:SetBackdropBorderColor(0, 0, 0, 0)
            h.divider:Show()
            T.SetGlyph(h, open and "chevronDown" or "chevronRight", "RIGHT", -10, 0, "inkSoft")
        end
        h.text:SetShown(not narrow)
        h.text:SetText(("%s (%d)"):format(cat.name, #items))
        h:Show()
        y = y + h:GetHeight() + 2

        if open then
            for _, d in ipairs(items) do
                ei = ei + 1
                local b = getEntryButton(ei)
                b.entry = d
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", ENTRY_INDENT, -y)
                b:SetWidth(listW - ENTRY_INDENT)
                local done, total = ns.EntryProgress(d)
                b.name:SetText(ns.EntryName(d))
                local level = ""
                if d.minLevel then
                    local lv = (d.minLevel == d.maxLevel) and tostring(d.minLevel) or ("%s-%s"):format(d.minLevel, d.maxLevel or "?")
                    level = ns.L["Lv"] .. " " .. lv .. "   "
                end
                b.sub:SetText(("%s%s%s%d/%d"):format(
                    d.new and (T.code("ready") .. ns.L["NEW"] .. "|r  ") or "", level,
                    d.size and (ns.L["%d-man"]:format(d.size) .. "   ") or "", done, total))
                b.bar:SetProgress(done, total)
                b.bar:SetFillColor(total > 0 and done >= total and "ready" or "gold")
                local sel = d.id == selectedId and not searchMode
                b:SetBackdropColor(0, 0, 0, sel and 0.14 or 0)
                b.mark:SetShown(sel)
                b.name:SetTextColor(T.rgba(sel and "ink" or "inkSoft"))
                b:Show()
                y = y + ENTRY_H + 2
            end
            y = y + 4
        end
    end
    for k = hi + 1, #headerButtons do headerButtons[k]:Hide() end
    for k = ei + 1, #listButtons do listButtons[k]:Hide() end
    frame.listChild:SetSize(listW, math.max(1, y))
    local needed = y > frame:GetHeight() - (frame.listTop or 0) - 14
    if needed ~= sideScrolls then
        sideScrolls = needed
        if ns.UI_ApplySideWidth then ns.UI_ApplySideWidth() end
    end
end

function ns.UI_Refresh()
    if not frame then return end
    if frame.consolidateSwitch then frame.consolidateSwitch.Update() end
    if frame.updateProgress then frame.updateProgress() end
    -- remember where you are, to come back to it (the view, "tree" | "search" | "log" | "tracked" | "turnin"; the entry is
    -- ns.char.selected)
    ns.char.view = searchMode and ns.Search_Mode() or "tree"
    refreshList()
    if searchMode then
        for _, w in ipairs(treeWidgets) do w:Hide() end
        frame.searchPanel:Show()
        ns.Search_Refresh()
        ns.Detail_Layout() -- with a quest's panel open, the table ends above it
        return
    end
    frame.searchPanel:Hide()
    for _, w in ipairs(treeWidgets) do w:Show() end
    local d = ns.entries[selectedId]
    frame.header:SetText(d and ns.EntryName(d) or "")
    renderTree(d or { quests = {} })
    ns.Detail_Refresh()
end

-- Collapses the side panel to its icons (or expands it back); remembered with the settings.
function ns.UI_SetSideCollapsed(on)
    ns.char.sideCollapsed = on and true or false
    ns.PopupMenu_Hide()
    GameTooltip:Hide()
    if frame then
        ns.UI_ApplySideWidth()
        frame.listScroll:SetVerticalScroll(0)
        ns.UI_Refresh()
    end
end

function ns.UI_IsSearchMode()
    return searchMode
end

-- Entering the search (side panel entry): the quest panel closes and the tree is hidden.
function ns.UI_SetSearchMode(on, kind)
    searchMode = on and true or false
    if searchMode then
        expandedCat = nil -- going to the search or the log collapses the sections
        ns.char.category = false
        ns.Detail_Hide()
        ns.Search_SetMode(kind or "search")
    end
    ns.UI_Refresh()
    if searchMode then ns.Search_Focus() end
end

-- A search result: opens its entry's tree with the quest selected (green path, panel open) and centers it
-- in the view.
function ns.UI_OpenQuest(entryId, questId)
    local d = ns.entries[entryId]
    if not d then return end
    searchMode = false
    expandedCat = d.category
    ns.char.category = expandedCat
    selectEntry(entryId)
    pinned = chainMembers(d, questId)
    ns.UI_Refresh()
    for _, q in ipairs(d.quests) do
        if q.id == questId then ns.Detail_Show(q) break end
    end
    ns.UI_Refresh()
    if frame.scrollToQuest then frame.scrollToQuest(questId) end
end

local function saveGeometry()
    local point, _, relPoint, x, y = frame:GetPoint()
    -- minimized, the height to keep is the one it comes back to
    local h = frame.minimized and frame.restoreH or frame:GetHeight()
    ns.char.window = { point = point, relPoint = relPoint, x = x, y = y, w = frame:GetWidth(), h = h }
end

-- Hooks for the preferences (Preferences.lua): reset window, zoom and filters.
function ns.UI_ResetWindow()
    ns.Focus_ResetPosition()
    ns.char.window = nil
    if frame then
        frame:ClearAllPoints()
        frame:SetPoint("CENTER")
        frame:SetSize(DEFAULT_W, DEFAULT_H)
    end
end

-- Redefined when the window is created, once there is a canvas to scale.
function ns.UI_SetZoom(z)
    ns.char.zoom = z
end

function ns.UI_SyncFilters()
    if frame and frame.updateFilters then frame.updateFilters() end
    if frame then ns.UI_Refresh() end
end

-- After switching between character and shared settings (Settings.lua): the new store's window, zoom and
-- filters.
function ns.UI_ApplySettings()
    ns.Focus_ApplySettings()
    ns.Tracker_Apply()
    if frame then
        local saved = ns.char.window
        frame:ClearAllPoints()
        if saved then
            frame:SetSize(math.max(MIN_W, saved.w), math.max(MIN_H, saved.h))
            frame:SetPoint(saved.point, UIParent, saved.relPoint, saved.x, saved.y)
        else
            frame:SetSize(DEFAULT_W, DEFAULT_H)
            frame:SetPoint("CENTER")
        end
        ns.UI_SetZoom(ns.char.zoom or 1)
        ns.UI_ApplySideWidth()
    end
    ns.UI_SyncFilters()
end

-- Like the world map: while the character moves (not on a flight path), the window turns semi-transparent so it doesn't hide
-- what's ahead (50 % by default; `/completao fade <10-100>` changes it, 100 = no effect), and turns opaque
-- again when you stop or while the cursor is over it, so it can be used on the move. The change is smooth.
-- Only the transparency changes, which the game allows even in combat.
local DEFAULT_FADE_ALPHA = 0.5

-- Click-through (Preferences: in combat / while moving): the window and everything in it stops taking the
-- mouse, so clicks reach the game world. Mouse and wheel are switched off on the window and on every frame
-- inside it (a child takes clicks even when its parent doesn't), and put back as they were afterwards.
local mouseOrig, clickThrough, sinceWalk = {}, false, 0
local function walk(f, fn)
    fn(f)
    for _, child in ipairs({ f:GetChildren() }) do walk(child, fn) end
end

local function setClickThrough(on)
    if on then
        walk(frame, function(f)
            if not mouseOrig[f] then mouseOrig[f] = { mouse = f:IsMouseEnabled(), wheel = f:IsMouseWheelEnabled() } end
            f:EnableMouse(false)
            f:EnableMouseWheel(false)
        end)
    else
        for f, o in pairs(mouseOrig) do
            f:EnableMouse(o.mouse)
            f:EnableMouseWheel(o.wheel)
        end
        mouseOrig = {}
    end
    clickThrough = on
end

local function inCombat()
    if UnitAffectingCombat and UnitAffectingCombat("player") then return true end
    return InCombatLockdown and InCombatLockdown() and true or false
end

-- The window's resting opacity (Preferences: Opacity); moving and combat fade it from there, never above it.
local function baseAlpha()
    return ns.char.windowAlpha or 1
end

local function fadeOnUpdate(self, elapsed)
    local target = baseAlpha()
    -- the client hides some values in combat ("secret" values): comparing them errors, so in that case the
    -- window stays opaque
    local speed = GetUnitSpeed("player")
    local known = speed ~= nil and not (issecretvalue and issecretvalue(speed))
    -- on a flight path the character "moves" but isn't steering: the window stays as it is, to read on the trip
    local onTaxi = UnitOnTaxi and UnitOnTaxi("player")
    local moving = known and speed > 0 and not onTaxi
    local combat = inCombat()
    local wantClickThrough = (ns.char.clickThroughCombat and combat) or (ns.char.clickThroughMoving and moving) or false
    if wantClickThrough ~= clickThrough then
        setClickThrough(wantClickThrough)
        sinceWalk = 0
    elseif clickThrough then
        -- frames made while it is on (table rows...) are caught too
        sinceWalk = sinceWalk + elapsed
        if sinceWalk > 1 then
            sinceWalk = 0
            setClickThrough(true)
        end
    end
    -- the cursor over it brings it back to opaque so it can be used -- unless it is click-through: it can't
    -- be used then, and stays as transparent as set
    if clickThrough or not self:IsMouseOver() then
        if moving then target = math.min(target, ns.char.fadeAlpha or DEFAULT_FADE_ALPHA) end
        if combat then target = math.min(target, ns.char.fadeAlphaCombat or 1) end
    end
    local current = self:GetAlpha()
    if math.abs(current - target) < 0.01 then
        if current ~= target then self:SetAlpha(target) end
        return
    end
    self:SetAlpha(current + (target - current) * math.min(1, elapsed * 8))
end

-- The character's progress over everything (each quest once, however many entries it is in), for the header's bar.
-- Worked out again at most once a second: every quest of the data is looked at.
local progressCache, progressAt
local function globalProgress()
    local now = GetTime()
    if progressCache and progressAt and now - progressAt < 1 then return progressCache[1], progressCache[2] end
    local seen, done, total = {}, 0, 0
    for _, d in ipairs(ns.entryList) do
        for _, q in ipairs(d.quests) do
            if not seen[q.id] and not q.repeatable and ns.QuestVisible(q, d) then
                local isDone = ns.IsQuestDone(q.id)
                if isDone or not ns.QuestLostTo(q) then
                    seen[q.id] = true
                    total = total + 1
                    if isDone then done = done + 1 end
                end
            end
        end
    end
    progressCache, progressAt = { done, total }, now
    return done, total
end

local function number(n)
    return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

local function createFrame()
    -- Our own frame ("Cartographic Codex"): obsidian, a fine gold frame, a header bar with the compass medallion
    frame = CreateFrame("Frame", "CompletaoFrame", UIParent, "BackdropTemplate")
    -- the content starts below the header bar
    local top = BAR_H + 10
    ns.CONTENT_TOP = top
    ns.TREE_TOP = top + 104
    local saved = ns.char.window
    frame:SetSize(saved and math.max(MIN_W, saved.w) or DEFAULT_W, saved and math.max(MIN_H, saved.h) or DEFAULT_H)
    if saved then
        frame:SetPoint(saved.point, UIParent, saved.relPoint, saved.x, saved.y)
    else
        frame:SetPoint("CENTER")
    end
    frame:SetFrameStrata("HIGH")
    -- raised above the other addons' windows when shown or clicked, with all its children: otherwise another
    -- window of the same strata draws its contents over this one's background
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(MIN_W, MIN_H)
    else
        frame:SetMinResize(MIN_W, MIN_H)
    end
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        saveGeometry()
    end)
    tinsert(UISpecialFrames, "CompletaoFrame")
    frame:SetScript("OnUpdate", fadeOnUpdate)
    frame:HookScript("OnHide", function(self)
        self:SetAlpha(baseAlpha()) -- opens at its resting opacity next time
        if clickThrough then setClickThrough(false) end
        openedWithLog = false
        if self.minimized then ns.UI_SetMinimized(false) end -- opens whole next time
    end)
    frame:Hide()

    -- Everything under the header bar lives in `body`, which minimizing hides (the window shrinks to its bar).
    local body = CreateFrame("Frame", nil, frame)
    body:SetAllPoints()
    frame.body = body
    function ns.UI_SetMinimized(on)
        on = on and true or false
        if on == (frame.minimized or false) then return end
        if on then
            frame.restoreH = frame:GetHeight()
            frame.minimized = true
            body:Hide()
            frame:SetHeight(BAR_H + 4)
        else
            frame.minimized = false
            frame:SetHeight(frame.restoreH or DEFAULT_H)
            body:Show()
            ns.UI_Refresh()
        end
        T.SetGlyph(frame.minimizeButton, on and "restore" or "minimize")
    end

    local grip = CreateFrame("Button", nil, body)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -3, 3)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        saveGeometry()
        ns.UI_Refresh()
    end)

    local getMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local version = getMeta and getMeta(ADDON, "Version") or "?"

    -- Background: a solid obsidian backing (so 100 % is really opaque; the window's alpha still fades it all together)
    -- and, over it, the cartographic stone with its vignette.
    local backing = frame:CreateTexture(nil, "BACKGROUND", nil, 1)
    backing:SetColorTexture(T.rgba("obsidian", 1))
    backing:SetAllPoints()
    local art = frame:CreateTexture(nil, "BACKGROUND", nil, 2)
    art:SetTexture(T.MEDIA .. "BgMain")
    art:SetAllPoints()
    art:SetAlpha(0.55)
    T.ApplyGoldBorder(frame, 16, 3)

    -- Header bar: the banner (its ends kept at their shape, the middle stretched), the medallion sticking out of the
    -- top-left corner, the title plate and the version, the progress bar, and the controls on the right.
    local bar = CreateFrame("Frame", nil, frame)
    bar:SetPoint("TOPLEFT", 0, 0)
    bar:SetPoint("TOPRIGHT", 0, 0)
    bar:SetHeight(BAR_H)
    frame.headerBar = bar
    local function banner(l, r)
        local tex = bar:CreateTexture(nil, "BACKGROUND")
        tex:SetTexture(T.MEDIA .. "HeaderBanner")
        tex:SetTexCoord(l, r, 0, 1)
        return tex
    end
    local bannerLeft, bannerMid, bannerRight = banner(0, 0.0625), banner(0.0625, 0.875), banner(0.875, 1)
    bannerLeft:SetPoint("TOPLEFT")
    bannerLeft:SetSize(64 * BAR_H / 64, BAR_H)
    bannerRight:SetPoint("TOPRIGHT")
    bannerRight:SetSize(128 * BAR_H / 64, BAR_H)
    bannerMid:SetPoint("TOPLEFT", bannerLeft, "TOPRIGHT")
    bannerMid:SetPoint("BOTTOMRIGHT", bannerRight, "BOTTOMLEFT")

    -- the medallion: over the top-left corner, out of the gold frame, its lower half over the side panel's parchment
    local medallion = CreateFrame("Frame", nil, frame)
    medallion:SetSize(MEDALLION, MEDALLION)
    medallion:SetPoint("TOPLEFT", -12, 12)
    medallion:SetFrameLevel(frame:GetFrameLevel() + 20)
    medallion.tex = medallion:CreateTexture(nil, "ARTWORK")
    medallion.tex:SetAllPoints()
    medallion.tex:SetTexture(T.MEDIA .. "LogoMedallion")
    frame.medallion = medallion

    -- the title plate, centered and standing a little out of the bar: the name and, in slate, the version
    local PLATE_H = 52
    local plate = bar:CreateTexture(nil, "ARTWORK")
    plate:SetTexture(T.MEDIA .. "TitlePlate")
    plate:SetTexCoord(0, 1, 0, 106 / 128)
    plate:SetSize(PLATE_H * 512 / 106, PLATE_H)
    plate:SetPoint("TOP", bar, "TOP", 0, 5)
    local title = T.Text(bar, "title", "gold")
    title:SetPoint("CENTER", plate, "CENTER", 0, 1)
    title:SetText("Completao!! " .. T.code("muted") .. "v" .. version .. "|r")
    frame.titleText = title

    -- controls, from the right edge: close, minimize, preferences and "Consolidate alts"
    local close = T.CreateIconButton(bar, "close", 20, CLOSE or ns.L["Close"])
    close:SetPoint("RIGHT", bar, "RIGHT", -10, 0)
    close:SetScript("OnClick", function() frame:Hide() end)
    frame.closeButton = close

    local minimize = T.CreateIconButton(bar, "minimize", 20, function()
        return frame.minimized and ns.L["Restore"] or ns.L["Minimize"]
    end)
    minimize:SetPoint("RIGHT", close, "LEFT", -4, 0)
    minimize:SetScript("OnClick", function() ns.UI_SetMinimized(not frame.minimized) end)
    frame.minimizeButton = minimize

    -- Preferences: our own gear (Icons/Gear.png), slate, gold on hover
    local gear = CreateFrame("Button", nil, bar)
    gear:SetSize(18, 18)
    gear:SetPoint("RIGHT", minimize, "LEFT", -6, 0)
    local gearTexture = "Interface\\AddOns\\" .. ADDON .. "\\Icons\\Gear.png"
    gear:SetNormalTexture(gearTexture)
    gear:GetNormalTexture():SetVertexColor(T.rgba("muted"))
    gear:SetHighlightTexture(gearTexture, "ADD")
    gear:SetScript("OnClick", function() ns.Prefs_Toggle() end)
    gear:SetScript("OnEnter", function(self)
        self:GetNormalTexture():SetVertexColor(T.rgba("gold"))
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText(ns.L["Preferences"])
        GameTooltip:Show()
    end)
    gear:SetScript("OnLeave", function(self)
        self:GetNormalTexture():SetVertexColor(T.rgba("muted"))
        GameTooltip_Hide()
    end)

    -- "Consolidate alts": a pill with the account's icon, for the whole addon (so in the header and not with the
    -- tree's filters). On: green border and text, and a check.
    local switch = CreateFrame("Button", nil, bar, "BackdropTemplate")
    switch:SetHeight(22)
    switch:SetPoint("RIGHT", gear, "LEFT", -10, 0)
    T.Style(switch, "obsidian", "brass")
    local pillIcon = switch:CreateTexture(nil, "ARTWORK")
    pillIcon:SetSize(16, 16)
    pillIcon:SetPoint("LEFT", 4, 0)
    pillIcon:SetTexture("Interface\\Icons\\Achievement_GuildPerk_EverybodysFriend")
    pillIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local switchLabel = T.Text(switch, "small")
    switchLabel:SetPoint("LEFT", pillIcon, "RIGHT", 5, 0)
    switchLabel:SetText(ns.L["Consolidate alts"])
    local pillCheck = switch:CreateTexture(nil, "OVERLAY")
    pillCheck:SetSize(14, 14)
    pillCheck:SetPoint("LEFT", switchLabel, "RIGHT", 4, 0)
    pillCheck:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    function switch.Update()
        local on = ns.Consolidated()
        switch.on = on
        switch:SetBackdropBorderColor(T.rgba(on and "ready" or "brass"))
        switchLabel:SetTextColor(T.rgba(on and "ready" or "muted"))
        pillIcon:SetDesaturated(not on)
        pillCheck:SetShown(on)
        switch:SetWidth(4 + 16 + 5 + switchLabel:GetStringWidth() + (on and 22 or 8))
    end
    switch:SetScript("OnClick", function()
        ns.SetConsolidated(not ns.Consolidated())
        switch.Update()
    end)
    switch:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
        GameTooltip:SetText(ns.L["Consolidate alts"])
        for _, line in ipairs({
            ns.L["Looks at all your characters as one: what any of them has done counts as completed, also for the quests it unlocks."],
            ns.L["The classes, races, professions and factions of all of them are shown; too low or too high goes by the character you play."],
            ns.L["Only the characters of your realm go together (never another ruleset's); each one is remembered once it logs in."],
        }) do
            GameTooltip:AddLine(line, 1, 1, 1, true)
        end
        GameTooltip:Show()
    end)
    switch:SetScript("OnLeave", GameTooltip_Hide)
    switch.Update()
    frame.consolidateSwitch = switch

    -- Global progress, between the medallion and the title plate: the character's quests done over all of them.
    local progress = T.CreateProgressBar(bar, 14, "gold", true)
    progress:SetPoint("LEFT", bar, "LEFT", MEDALLION - 4, 0)
    progress:SetPoint("RIGHT", plate, "LEFT", -6, 0)
    progress.track:SetColorTexture(T.rgba("obsidian", 0.85))
    frame.progress = progress
    function frame.updateProgress()
        local done, total = globalProgress()
        progress:SetProgress(done, total)
        progress:SetLabel(ns.L["Completed: %s / %s quests (%.1f%%)"]:format(number(done), number(total),
            total > 0 and done * 100 / total or 0))
        -- too narrow to say anything: no bar (only transparent, so its size keeps being followed)
        progress:SetAlpha((progress:GetWidth() or 0) >= 120 and 1 or 0)
    end
    progress:HookScript("OnSizeChanged", function() frame.updateProgress() end)

    -- the room the quest drawer takes on the right while it is open (QuestPanel.lua sets it)
    local function drawerInset() return ns.DETAIL_INSET or 0 end

    -- the side panel is a sheet of parchment with burnt edges (written in ink), from under the header bar; a brass
    -- line where the main area starts
    local sideBg = body:CreateTexture(nil, "BACKGROUND", nil, 3)
    sideBg:SetTexture(T.MEDIA .. "Parchment")
    local sideLine = body:CreateTexture(nil, "BORDER")
    sideLine:SetColorTexture(T.rgba("brass"))
    sideLine:SetWidth(1)
    local function placeSide()
        local right = mainLeft() - 10
        sideBg:ClearAllPoints()
        sideBg:SetPoint("TOPLEFT", body, "TOPLEFT", 2, -(BAR_H - 2))
        sideBg:SetPoint("BOTTOMRIGHT", body, "BOTTOMLEFT", right - 2, 4)
        sideLine:ClearAllPoints()
        sideLine:SetPoint("TOPLEFT", body, "TOPLEFT", right, -BAR_H)
        sideLine:SetPoint("BOTTOMLEFT", body, "BOTTOMLEFT", right, 0)
    end
    placeSide()

    frame.header = T.Text(body, "title", "gold")
    frame.header:SetPoint("TOPLEFT", mainLeft(), -top)
    frame.header:SetPoint("RIGHT", body, "RIGHT", -(16 + drawerInset()), 0)
    frame.header:SetJustifyH("LEFT")
    frame.header:SetWordWrap(false)

    -- Filter bar under the title: search by title and the filters, placed in rows that rearrange with the
    -- window's width (layoutToolbar, below).
    local toolbarLeft = mainLeft()
    local toolbarItems = {}
    local box = T.CreateSearchBox(body, 200, ns.L["Search by title"])
    searchBox = box
    toolbarItems[#toolbarItems + 1] = { frame = box, w = 204, h = 24, dy = 1 }
    box:HookScript("OnTextChanged", function(self)
        searchText = strtrim(self:GetText() or ""):lower()
        pinned = nil
        ns.RequestRefresh()
    end)

    -- The filters live in a "Filters" drop-down next to the search box (FilterMenu.lua).
    local filtersButton = ns.FilterMenu(body, {
        options = {
            { key = "hideLow", label = ns.L["Hide low level"], tip = ns.L["Hides quests that are grey for your level (trivial)."] },
            { key = "hideHigh", label = ns.L["Hide too high"], tip = ns.L["Hides quests you cannot take yet, because of your level."] },
            { key = "hideDone", label = ns.L["Hide completed"],
                tip = ns.L["Hides the quests you have completed, also inside unfinished chains."] },
            { key = "hideRepeatable", label = ns.L["Hide repeatable done"],
                tip = ns.L["Hides the repeatable quests you have already turned in once; the ones you have never done still show."] },
            { key = "otherFaction", label = ns.L["Show other faction"],
                tip = ns.L["Shows the quests and zones of the opposite faction, hidden by default."] },
        },
        get = function(key) return ns.char.filters[key] end,
        set = function(key, on) ns.char.filters[key] = on end,
        onChange = function()
            pinned = nil
            ns.UI_Refresh()
        end,
    })
    toolbarItems[#toolbarItems + 1] = { frame = filtersButton, w = 110, h = 24, dy = 1 }
    frame.filtersButton, frame.filtersMenu, frame.clearFilters = filtersButton, filtersButton.menu, filtersButton.clear
    frame.updateFilters = filtersButton.Update

    -- hint at the bottom: takes the tree area's width and is cut ("...") if it doesn't fit
    local hint = T.Text(body, "small", "locked")
    hint:SetPoint("BOTTOMLEFT", mainLeft(), 12)
    hint:SetPoint("BOTTOMRIGHT", -(26 + drawerInset()), 12)
    hint:SetJustifyH("LEFT")
    hint:SetWordWrap(false)
    hint:SetText(ns.L["Drag: pan  |  Wheel: zoom  |  Shift+wheel: sideways  |  Ctrl+wheel: vertical"])

    local listScroll = CreateFrame("ScrollFrame", nil, body, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 14, -LIST_TOP)
    listScroll:SetPoint("BOTTOMLEFT", 14, 18)
    frame.listTop = LIST_TOP
    listScroll:SetWidth(sideW() - 22)
    frame.listChild = CreateFrame("Frame", nil, listScroll)
    frame.listChild:SetSize(sideW() - 26, 1)
    listScroll:SetScrollChild(frame.listChild)
    frame.listScroll = listScroll
    -- the bar hides by itself; the room it leaves goes to the main area through refreshList (sideScrolls)
    ns.AutoScrollBar(listScroll, function() end)

    -- The four views, first in the side panel; they open the table in the main area (the search with its form, or
    -- the quests you carry in your log). The open one gets a gold bar on its left; each counts its quests.
    local function sideButton(kind, icon, label)
        local b = CreateFrame("Button", nil, frame.listChild, "BackdropTemplate")
        b.kind, b.title = kind, label
        b:SetHeight(NAV_H)
        T.Style(b, "slate", false)
        b:SetBackdropColor(0, 0, 0, 0)
        b:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
        b:GetHighlightTexture():SetVertexColor(0, 0, 0, 0.06)
        b.mark = b:CreateTexture(nil, "ARTWORK")
        b.mark:SetPoint("TOPLEFT")
        b.mark:SetPoint("BOTTOMLEFT")
        b.mark:SetWidth(3)
        b.mark:SetColorTexture(T.rgba("inkSoft"))
        local tex = b:CreateTexture(nil, "ARTWORK")
        tex:SetSize(14, 14)
        tex:SetTexture(icon)
        local text = T.Text(b, "heading", "inkSoft")
        text:SetPoint("LEFT", tex, "RIGHT", 7, 0)
        text:SetText(label)
        b.tex, b.text = tex, text
        b.badge = T.CreateStyledFrame(b, "Frame", "obsidian", "brass")
        b.badge:SetSize(20, 15)
        b.badge:SetPoint("RIGHT", -6, 0)
        b.badge.text = T.Text(b.badge, "small", "gold")
        b.badge.text:SetPoint("CENTER", 0, 0)
        b.badge:Hide()
        b:SetScript("OnClick", function() ns.UI_SetSearchMode(true, kind) end)
        b:SetScript("OnEnter", showSideTooltip)
        b:SetScript("OnLeave", GameTooltip_Hide)
        searchButtons[#searchButtons + 1] = b
    end
    sideButton("search", "Interface\\Common\\UI-Searchbox-Icon", ns.L["Search quests..."])
    sideButton("log", "Interface\\GossipFrame\\ActiveQuestIcon", ns.L["Quest Log"])
    sideButton("tracked", "Interface\\GossipFrame\\AvailableQuestIcon", ns.L["Tracked Quests"])
    sideButton("turnin", "Interface\\RaidFrame\\ReadyCheck-Ready", ns.L["Quests to Turn In"])

    -- the catalogue's mini filter: by name, in every section at once (34 zones are a long scroll)
    zoneBox = T.CreateSearchBox(frame.listChild, 180, ns.L["Filter zone..."])
    zoneBox:HookScript("OnTextChanged", function(self)
        local text = fold(strtrim(self:GetText() or ""))
        if text == zoneFilter then return end
        zoneFilter = text
        frame.listScroll:SetVerticalScroll(0)
        refreshList()
    end)
    frame.zoneFilter = zoneBox

    -- first row of the side panel: collapses it to the icons, or expands it back
    sideToggle = CreateFrame("Button", nil, frame.listChild)
    sideToggle:SetHeight(TOGGLE_H)
    sideToggle.tex = sideToggle:CreateTexture(nil, "ARTWORK")
    sideToggle.tex:SetSize(16, 16)
    sideToggle.tex:SetVertexColor(T.rgba("inkSoft"))
    sideToggle.text = T.Text(sideToggle, "small", "inkMuted")
    sideToggle.text:SetPoint("LEFT", sideToggle.tex, "RIGHT", 4, 0)
    sideToggle.text:SetText(ns.L["Collapse menu"])
    sideToggle:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
    sideToggle:GetHighlightTexture():SetVertexColor(0, 0, 0, 0.06)
    sideToggle:SetScript("OnClick", function() ns.UI_SetSideCollapsed(not collapsed()) end)
    sideToggle:SetScript("OnEnter", showSideTooltip)
    sideToggle:SetScript("OnLeave", GameTooltip_Hide)

    frame.searchPanel = ns.Search_Create(body)
    frame.searchPanel:SetPoint("TOPLEFT", mainLeft(), -top)
    frame.searchPanel:SetPoint("BOTTOMRIGHT", -(8 + drawerInset()), 30)

    local treeScroll = CreateFrame("ScrollFrame", nil, body, "UIPanelScrollFrameTemplate")
    treeScroll:SetPoint("TOPLEFT", treeLeft(), -ns.TREE_TOP)
    treeScroll:SetPoint("BOTTOMRIGHT", -32, 30)
    holder = CreateFrame("Frame", nil, treeScroll)
    holder:SetSize(1, 1)
    canvas = CreateFrame("Frame", nil, holder)
    canvas:SetPoint("TOPLEFT")
    canvas:SetSize(1, 1)
    treeScroll:SetScrollChild(holder)
    frame.treeScroll = treeScroll
    ns.Detail_Create(body, treeScroll, treeLeft(), frame.searchPanel)
    -- the tree's scroll bar only when it is taller than the view (the canvas is scaled by the zoom, which the
    -- client's own scroll range ignores)
    treeBarUpdate = ns.AutoScrollBar(treeScroll, function(has)
        ns.TREE_RIGHT = has and 32 or 8
        treeScroll:SetPoint("BOTTOMRIGHT", -(ns.TREE_RIGHT + drawerInset()), 30)
        ns.Detail_Layout()
    end, function()
        return (canvas:GetHeight() or 0) * (canvas:GetScale() or 1) - (treeScroll:GetHeight() or 0) > 1
    end)

    -- filters in rows by width; the tree starts under the last row
    local function layoutToolbar()
        local width = frame:GetWidth() - toolbarLeft - 32 - drawerInset()
        local h = ns.FlowLayout(body, toolbarItems, toolbarLeft, top + 28, width, 10, 2)
        ns.TREE_TOP = top + 28 + h + 8
        treeScroll:SetPoint("TOPLEFT", treeLeft(), -ns.TREE_TOP)
        ns.Detail_Layout()
    end
    layoutToolbar()
    frame:HookScript("OnSizeChanged", layoutToolbar)

    -- what ends at the right edge of the main area: the title, the hint and the toolbar's rows
    local function placeRight()
        frame.header:ClearAllPoints()
        frame.header:SetPoint("TOPLEFT", mainLeft(), -top)
        frame.header:SetPoint("RIGHT", body, "RIGHT", -(16 + drawerInset()), 0)
        hint:ClearAllPoints()
        hint:SetPoint("BOTTOMLEFT", mainLeft(), 12)
        hint:SetPoint("BOTTOMRIGHT", -(26 + drawerInset()), 12)
    end

    -- everything that starts where the side panel ends moves with it when it collapses or expands
    function ns.UI_ApplySideWidth()
        toolbarLeft = mainLeft()
        placeSide()
        placeRight()
        listScroll:SetWidth(sideW() - 22)
        frame.listChild:SetWidth(sideW() - 26)
        frame.searchPanel:ClearAllPoints()
        frame.searchPanel:SetPoint("TOPLEFT", mainLeft(), -top)
        frame.searchPanel:SetPoint("BOTTOMRIGHT", -(8 + drawerInset()), 30)
        ns.Detail_SetOffset(treeLeft())
        layoutToolbar()
    end

    -- the quest drawer opened or closed (or was maximized): the main area ends where it starts
    function ns.UI_DrawerChanged()
        placeRight()
        layoutToolbar()
    end

    -- what is hidden while the search is open
    treeWidgets = { frame.header, searchBox, hint, treeScroll }
    treeWidgets[#treeWidgets + 1] = frame.filtersButton

    -- Tree zoom: the canvas is scaled; saved with the settings.
    local zoom = math.max(ZOOM_MIN, math.min(ZOOM_MAX, ns.char.zoom or 1))
    canvas:SetScale(zoom)
    syncHolder()

    local function maxScroll(self)
        return math.max(0, canvas:GetWidth() * zoom - self:GetWidth()), math.max(0, canvas:GetHeight() * zoom - self:GetHeight())
    end
    local function scrollTo(self, x, y)
        local maxX, maxY = maxScroll(self)
        self:SetHorizontalScroll(math.max(0, math.min(x, maxX)))
        self:SetVerticalScroll(math.max(0, math.min(y, maxY)))
    end

    local zoomLabel -- the zoom controls' "100%" (below)
    local function showZoom()
        if zoomLabel then zoomLabel:SetText(("%d%%"):format(math.floor(zoom * 100 + 0.5))) end
    end

    function ns.UI_SetZoom(z)
        zoom = math.max(ZOOM_MIN, math.min(ZOOM_MAX, z))
        ns.char.zoom = zoom
        canvas:SetScale(zoom)
        syncHolder()
        treeBarUpdate()
        scrollTo(treeScroll, 0, 0)
        showZoom()
    end

    -- centers a tree quest in the view (search results)
    function frame.scrollToQuest(id)
        local p = nodePos[id]
        if not p then return end
        local cx, cy = (p.x + NODE_W / 2) * zoom, (p.y + NODE_H / 2) * zoom
        scrollTo(treeScroll, cx - treeScroll:GetWidth() / 2, cy - treeScroll:GetHeight() / 2)
    end

    -- Zooms to `newZoom` keeping the point at (cx, cy) of the view where it is.
    local function zoomAt(newZoom, cx, cy)
        newZoom = math.max(ZOOM_MIN, math.min(ZOOM_MAX, newZoom))
        if newZoom == zoom then return end
        local x, y = treeScroll:GetHorizontalScroll(), treeScroll:GetVerticalScroll()
        local contentX, contentY = (x + cx) / zoom, (y + cy) / zoom
        zoom = newZoom
        ns.char.zoom = zoom
        canvas:SetScale(zoom)
        syncHolder()
        treeBarUpdate()
        scrollTo(treeScroll, contentX * zoom - cx, contentY * zoom - cy)
        showZoom()
    end
    local function zoomAtCenter(newZoom)
        zoomAt(newZoom, (treeScroll:GetWidth() or 0) / 2, (treeScroll:GetHeight() or 0) / 2)
    end

    -- Wheel: zoom, centered on the cursor (the point under the cursor doesn't move). Shift+wheel: scrolls
    -- sideways; Ctrl+wheel: scrolls vertically. Drag the background to move the view.
    treeScroll:SetScript("OnMouseWheel", function(self, delta)
        local x, y = self:GetHorizontalScroll(), self:GetVerticalScroll()
        if IsShiftKeyDown() then
            scrollTo(self, x - delta * 60, y)
        elseif IsControlKeyDown() then
            scrollTo(self, x, y - delta * 60)
        else
            local px, py = GetCursorPosition()
            local scale = self:GetEffectiveScale()
            zoomAt(zoom * (delta > 0 and ZOOM_STEP or 1 / ZOOM_STEP),
                px / scale - (self:GetLeft() or 0), (self:GetTop() or 0) - py / scale)
        end
    end)

    -- "Center on my current quest": the focused quest (opening its tree if it is another one), else a quest of this
    -- tree that is in the log, else the one whose details are open.
    local function centerOnCurrent()
        local id = ns.Focus_Quest()
        if id and nodePos[id] then frame.scrollToQuest(id) return end
        local def = id and ns.FindQuestDef(id)
        if def and ns.entries[def.entryId] then
            ns.UI_OpenQuest(def.entryId, def.id)
            return
        end
        local ids = {}
        for qid in pairs(nodePos) do
            if C_QuestLog.IsOnQuest(qid) then ids[#ids + 1] = qid end
        end
        table.sort(ids)
        if ids[1] then frame.scrollToQuest(ids[1]) return end
        local cur = ns.Detail_Current()
        if cur and nodePos[cur.id] then frame.scrollToQuest(cur.id) end
    end

    -- Zoom controls in the tree's bottom-right corner: center, -, the zoom (a click goes back to 100 %), +.
    local zoomBar = T.CreateStyledFrame(body, "Frame", "slate", "brass")
    zoomBar:SetSize(4 * 22 + 18, 24)
    zoomBar:SetPoint("BOTTOMRIGHT", treeScroll, "BOTTOMRIGHT", -6, 6)
    zoomBar:SetFrameLevel(treeScroll:GetFrameLevel() + 20)
    local centerButton = T.CreateIconButton(zoomBar, "center", 20, ns.L["Center on my current quest"])
    centerButton:SetPoint("LEFT", 2, 0)
    centerButton:SetScript("OnClick", centerOnCurrent)
    local zoomOut = T.CreateIconButton(zoomBar, "minus", 20, ns.L["Zoom out"])
    zoomOut:SetPoint("LEFT", centerButton, "RIGHT", 2, 0)
    zoomOut:SetScript("OnClick", function() zoomAtCenter(zoom / ZOOM_STEP) end)
    local zoomReset = CreateFrame("Button", nil, zoomBar)
    zoomReset:SetSize(38, 20)
    zoomReset:SetPoint("LEFT", zoomOut, "RIGHT", 2, 0)
    zoomLabel = T.Text(zoomReset, "data", "muted")
    zoomLabel:SetPoint("CENTER")
    zoomReset:SetScript("OnClick", function() zoomAtCenter(1) end)
    zoomReset:SetScript("OnEnter", function(self)
        zoomLabel:SetTextColor(T.rgba("goldLight"))
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(ns.L["Reset zoom"])
        GameTooltip:Show()
    end)
    zoomReset:SetScript("OnLeave", function()
        zoomLabel:SetTextColor(T.rgba("muted"))
        GameTooltip_Hide()
    end)
    local zoomIn = T.CreateIconButton(zoomBar, "plus", 20, ns.L["Zoom in"])
    zoomIn:SetPoint("LEFT", zoomReset, "RIGHT", 2, 0)
    zoomIn:SetScript("OnClick", function() zoomAtCenter(zoom * ZOOM_STEP) end)
    frame.zoomBar, frame.centerOnCurrent = zoomBar, centerOnCurrent
    treeWidgets[#treeWidgets + 1] = zoomBar
    showZoom()

    -- Drag the background with the left button to move the view.
    local dragger = CreateFrame("Frame", nil, treeScroll)
    dragger:Hide()
    dragger:SetScript("OnUpdate", function(self)
        local cx, cy = GetCursorPosition()
        local scale = treeScroll:GetEffectiveScale()
        scrollTo(treeScroll,
            self.startH - (cx - self.startX) / scale,
            self.startV + (cy - self.startY) / scale)
    end)
    treeScroll:EnableMouse(true)
    treeScroll:RegisterForDrag("LeftButton")
    treeScroll:SetScript("OnDragStart", function(self)
        dragger.startX, dragger.startY = GetCursorPosition()
        dragger.startH, dragger.startV = self:GetHorizontalScroll(), self:GetVerticalScroll()
        dragger:Show()
    end)
    treeScroll:SetScript("OnDragStop", function() dragger:Hide() end)
    treeScroll:SetScript("OnHide", function() dragger:Hide() end)

    emptyText = canvas:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    emptyText:SetPoint("TOPLEFT", 20, -20)
    emptyText:SetText(ns.L["No quest data yet."])

    frame:SetScript("OnShow", function()
        selectedId = selectedId or ns.char.selected
        if not ns.entries[selectedId] then
            local first = entriesOf(ns.categories[1].id)[1] or ns.entryList[1]
            selectedId = first and first.id
        end
        if not listInitialized then
            listInitialized = true
            local cur = ns.entries[selectedId]
            local savedCat = ns.char.category
            if savedCat ~= nil then
                expandedCat = savedCat or nil
            else
                expandedCat = (cur and cur.category) or ns.categories[1].id
            end
        end
        -- Preferences -> "Always open on the Quest Log": every time it opens. Otherwise, the first time in
        -- a session it comes back to the view it was left on (later, the window is just as it was hidden).
        if ns.char.openOnQuestLog then
            ns.Detail_Hide()
            searchMode = true
            ns.Search_SetMode("log")
        elseif not viewRestored and (ns.char.view == "log" or ns.char.view == "search" or ns.char.view == "tracked"
            or ns.char.view == "turnin") then
            searchMode = true
            ns.Search_SetMode(ns.char.view)
        end
        viewRestored = true
        ns.UI_Refresh()
    end)
    ns.UI = frame
end

function ns.UI_Toggle()
    if not frame then createFrame() end
    frame:SetShown(not frame:IsShown())
end

-- Opens the window (if it isn't) on a quest: its tree, with the quest selected and its panel open (CompletaoAPI.ShowQuest).
-- Returns false when the addon doesn't know the quest.
function ns.UI_ShowQuest(questID)
    local def = ns.FindQuestDef(questID)
    if not (def and ns.entries[def.entryId]) then return false end
    if not frame then createFrame() end
    frame:Show()
    ns.UI_OpenQuest(def.entryId, def.id)
    return true
end

-- Opens the window (if it isn't) on the Tracked Quests view (the focus window's right click).
function ns.UI_OpenTracked()
    if not frame then createFrame() end
    frame:Show()
    ns.UI_SetSearchMode(true, "tracked")
end

-- Preferences -> "Sync with Blizzard Quest Log": opening the log (the L key or its button, both through
-- ToggleQuestLog) also opens this window, and if it was opened that way it closes with it. The log can be
-- the classic one (QuestLogFrame) or the map's (QuestMapFrame); checked after the game shows it.
local function questLogShown()
    if QuestLogFrame and QuestLogFrame:IsShown() then return true end
    return QuestMapFrame ~= nil and QuestMapFrame:IsVisible() and true or false
end

local function onQuestLogToggled()
    C_Timer.After(0, function()
        if not (ns.char and ns.char.openWithQuestLog) then return end
        if questLogShown() then
            if not (frame and frame:IsShown()) then
                if not frame then createFrame() end
                frame:Show()
                openedWithLog = true
            end
        elseif openedWithLog and frame then
            frame:Hide()
        end
    end)
end

-- Preferences -> "Sync with Blizzard Quest Log": selecting a quest in the game's log opens it (and its
-- chain) in the tree, when the addon knows it. Only while this window is open.
local function onQuestSelected(questID)
    if not (ns.char and ns.char.openWithQuestLog and frame and frame:IsShown()) then return end
    if ns.QuestSelectMuted() then return end
    local def = questID and ns.FindQuestDef(questID)
    if def and ns.entries[def.entryId] then ns.UI_OpenQuest(def.entryId, def.id) end
end

ns.UI_QuestSelected = onQuestSelected
if QuestMapFrame_ShowQuestDetails then hooksecurefunc("QuestMapFrame_ShowQuestDetails", onQuestSelected) end
-- Whatever the log's UI is, clicking a quest ends up selecting it here (our own selections are flagged).
-- The game's own table: a hook on ns.QuestLog would only see the addon's calls.
if _G.C_QuestLog and _G.C_QuestLog.SetSelectedQuest then
    hooksecurefunc(_G.C_QuestLog, "SetSelectedQuest", function(questID)
        if not ns.quietSelect and questID and questID > 0 then onQuestSelected(questID) end
    end)
end
if QuestLog_SetSelection then
    hooksecurefunc("QuestLog_SetSelection", function(index)
        local info = index and index > 0 and C_QuestLog.GetInfo(index)
        if info and not info.isHeader then onQuestSelected(info.questID) end
    end)
end

ns.UI_QuestLogChanged = onQuestLogToggled
if ToggleQuestLog then hooksecurefunc("ToggleQuestLog", onQuestLogToggled) end
local logFrame = QuestLogFrame or WorldMapFrame
if logFrame then logFrame:HookScript("OnHide", onQuestLogToggled) end
