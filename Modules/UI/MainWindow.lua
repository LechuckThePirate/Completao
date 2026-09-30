local ADDON, ns = ...

local LIST_W, NODE_W, NODE_H, GAP_X, GAP_Y, PAD = 210, 170, 40, 60, 20, 20

local STATUS_COLORS = {
    done      = { 0.20, 0.80, 0.20 },
    active    = { 1.00, 0.82, 0.00 },
    available = { 0.35, 0.65, 1.00 },
    locked    = { 0.45, 0.45, 0.45 },
}
local STATUS_LABELS = {
    done = ns.L["Completed"], active = ns.L["In progress"], available = ns.L["Available"], locked = ns.L["Locked"],
}
ns.STATUS_COLORS, ns.STATUS_LABELS = STATUS_COLORS, STATUS_LABELS
local BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
}

local HEADER_H, ENTRY_H, ENTRY_INDENT = 28, 34, 12
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
local MIN_W, MIN_H, DEFAULT_W, DEFAULT_H = 640, 380, 940, 580

local selectedId, expandedCat, listInitialized, viewRestored
local headerButtons, listButtons, nodeButtons, lines = {}, {}, {}, {}
local frame, canvas, emptyText
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
    GameTooltip:AddLine(STATUS_LABELS[status], c[1], c[2], c[3])
    if btn.readyToTurnIn then GameTooltip:AddLine(ns.L["Ready to turn in"], 0.35, 1, 0.35) end
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

local function getNodeButton(i)
    local b = nodeButtons[i]
    if b then return b end
    b = CreateFrame("Button", nil, canvas, "BackdropTemplate")
    b:SetSize(NODE_W, NODE_H)
    b:SetBackdrop(BACKDROP)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("TOPLEFT", 6, -4)
    b.text:SetPoint("BOTTOMRIGHT", -6, 4)
    b.text:SetJustifyH("LEFT")
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
    b:SetScript("OnClick", function(self)
        ns.Detail_Toggle(self.quest)
        ns.UI_Refresh()
    end)
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
local CHAIN_COLOR = { 0.35, 1, 0.35 }
local searchText = ""
local searchBox
local filterChecks = {}

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
        local isDone = C_QuestLog.IsQuestFlaggedCompleted(id)
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
        local c = chains and chains[q.id]
        local onQuest = C_QuestLog.IsOnQuest(q.id)
        -- completed: each one on its own, even if its chain goes on (untick the filter to see them)
        if f.hideDone and C_QuestLog.IsQuestFlaggedCompleted(q.id) then return false end
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
        b:SetBackdropColor(c[1] * 0.2, c[2] * 0.2, c[3] * 0.2, 0.9)
        local picked = ns.Detail_Current() and ns.Detail_Current().id == n.quest.id
        if picked then
            b:SetBackdropBorderColor(1, 1, 1, 1)
        else
            b:SetBackdropBorderColor(c[1], c[2], c[3], 1)
        end
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
        b.text:SetTextColor(status == "locked" and 0.65 or 1, status == "locked" and 0.65 or 1, status == "locked" and 0.65 or 1)
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
    end
    -- first the normal connections (fainter with a quest selected) and on top the path's, in green
    for _, e in ipairs(layout.edges) do
        if not (chainSet and chainSet[e.from] and chainSet[e.to]) then
            lineAlpha, lineThickness = chainSet and OFF_CHAIN_LINE_ALPHA or 0.85, 2
            drawEdge(e, STATUS_COLORS[byId[e.from].status == "done" and "done" or "locked"])
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
local function sortKey(d)
    return (ns.EntryName(d):lower():gsub("[\195][\128-\191]", ACCENTS))
end

local function entriesOf(catId)
    local items = {}
    -- Preferences "hide categories with no quests available or all done": an entry with nothing left to do is
    -- left out -- except the one being looked at, so it doesn't vanish under the player as they finish it
    local hideDone = ns.char and ns.char.hideDone
    for _, d in ipairs(ns.entryList) do
        if d.category == catId and (not HIDE_WHEN_EMPTY[catId] or select(2, ns.EntryProgress(d)) > 0)
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
    b:SetBackdrop(BACKDROP)
    b:SetBackdropColor(0.12, 0.10, 0.02, 0.95)
    b:SetBackdropBorderColor(0.6, 0.5, 0.1, 1)
    b.icon = b:CreateTexture(nil, "ARTWORK")
    b.icon:SetSize(18, 18)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
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
    b:SetBackdrop(BACKDROP)
    b.name = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.name:SetPoint("TOPLEFT", 6, -4)
    b.name:SetPoint("RIGHT", -6, 0)
    b.name:SetJustifyH("LEFT")
    b.sub = b:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    b.sub:SetPoint("BOTTOMLEFT", 6, 4)
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
        if #items > 0 or not (ns.char and ns.char.hideDone) then list[#list + 1] = { cat = cat, items = items } end
    end
    return list
end

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

    -- first entries: the global search and the quest log (same table, Search.lua)
    for _, b in ipairs(searchButtons) do
        local on = searchMode and ns.Search_Mode() == b.kind
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 0, -y)
        b:SetWidth(listW)
        b:SetHeight(narrow and ICON_BTN_H or 26)
        b.tex:ClearAllPoints()
        b.tex:SetPoint(narrow and "CENTER" or "LEFT", narrow and 0 or 8, 0)
        b.text:SetShown(not narrow)
        b.label = narrow and b.title or nil
        b:SetBackdropColor(on and 0.15 or 0.05, on and 0.25 or 0.05, on and 0.4 or 0.05, 0.9)
        b:SetBackdropBorderColor(on and 0.35 or 0.4, on and 0.65 or 0.4, on and 1 or 0.4, 1)
        y = y + b:GetHeight() + 2
    end
    y = y + 4

    local current = ns.entries[selectedId]
    for _, shown in ipairs(visibleCategories()) do
        local cat, items = shown.cat, shown.items
        local open = cat.id == expandedCat and not narrow

        hi = hi + 1
        local h = getHeaderButton(hi)
        h.cat = cat
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
            h:SetBackdropColor(on and 0.15 or 0.12, on and 0.25 or 0.10, on and 0.4 or 0.02, 0.95)
            h:SetBackdropBorderColor(on and 0.35 or 0.6, on and 0.65 or 0.5, on and 1 or 0.1, 1)
        else
            h.icon:SetPoint("LEFT", 8, 0)
            h.text:SetPoint("LEFT", 32, 0)
            h:SetBackdropColor(0.12, 0.10, 0.02, 0.95)
            h:SetBackdropBorderColor(0.6, 0.5, 0.1, 1)
        end
        h.text:SetShown(not narrow)
        h.text:SetText(("%s %s (%d)"):format(open and "-" or "+", cat.name, #items))
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
                    d.new and ("|cff33ff99" .. ns.L["NEW"] .. "|r  ") or "", level,
                    d.size and (ns.L["%d-man"]:format(d.size) .. "   ") or "", done, total))
                local sel = d.id == selectedId and not searchMode
                b:SetBackdropColor(sel and 0.15 or 0.05, sel and 0.25 or 0.05, sel and 0.4 or 0.05, 0.9)
                b:SetBackdropBorderColor(sel and 0.35 or 0.2, sel and 0.65 or 0.2, sel and 1 or 0.2, 1)
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
    -- remember where you are, to come back to it (the view, "tree" | "search" | "log" | "tracked"; the entry is
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
    ns.UI_Refresh()
    for _, q in ipairs(d.quests) do
        if q.id == questId then ns.Detail_Show(q) break end
    end
    ns.UI_Refresh()
    if frame.scrollToQuest then frame.scrollToQuest(questId) end
end

local function saveGeometry()
    local point, _, relPoint, x, y = frame:GetPoint()
    ns.char.window = { point = point, relPoint = relPoint, x = x, y = y, w = frame:GetWidth(), h = frame:GetHeight() }
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
    for key, cb in pairs(filterChecks) do cb:SetChecked(ns.char.filters[key] and true or false) end
    if frame then ns.UI_Refresh() end
end

-- After switching between character and shared settings (Settings.lua): the new store's window, zoom and
-- filters.
function ns.UI_ApplySettings()
    ns.Focus_ApplySettings()
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

local function fadeOnUpdate(self, elapsed)
    local target = 1
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

local function createFrame()
    -- Portrait frame (like Embolsao); if the client lacked the template, the older basic frame.
    local okPortrait, portraitFrame = pcall(CreateFrame, "Frame", "CompletaoFrame", UIParent, "PortraitFrameFlatTemplate")
    local hasPortrait = okPortrait and portraitFrame and portraitFrame.SetPortraitToAsset ~= nil
    frame = okPortrait and portraitFrame or CreateFrame("Frame", "CompletaoFrame", UIParent, "BasicFrameTemplateWithInset")
    -- the content starts below the portrait (which sticks out at the top left)
    local top = hasPortrait and 66 or 34
    ns.TREE_TOP = top + 104
    local saved = ns.char.window
    frame:SetSize(saved and math.max(MIN_W, saved.w) or DEFAULT_W, saved and math.max(MIN_H, saved.h) or DEFAULT_H)
    if saved then
        frame:SetPoint(saved.point, UIParent, saved.relPoint, saved.x, saved.y)
    else
        frame:SetPoint("CENTER")
    end
    frame:SetFrameStrata("HIGH")
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
        self:SetAlpha(1) -- opens opaque next time
        if clickThrough then setClickThrough(false) end
        openedWithLog = false
    end)
    frame:Hide()

    local grip = CreateFrame("Button", nil, frame)
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

    if hasPortrait then
        frame:SetPortraitToAsset("Interface\\AddOns\\" .. ADDON .. "\\Icons\\Completao.png")
    end
    local getMeta = C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata
    local version = getMeta and getMeta(ADDON, "Version") or "?"
    local title = (frame.TitleContainer and frame.TitleContainer.TitleText) or frame.TitleText
    if title then title:SetText(("Completao!! v%s"):format(version)) end

    -- Gear next to the X: opens the preferences. Our own icon (Icons/Gear.png) tinted gold.
    local gear = CreateFrame("Button", nil, frame)
    gear:SetSize(20, 20)
    -- Blizzard's frame border (NineSlice) sits far above its window and would cover the gear: it takes the
    -- close button's level, or goes above the border
    local closeButton = frame.CloseButton
    local level = frame:GetFrameLevel() + 10
    if frame.NineSlice then level = math.max(level, frame.NineSlice:GetFrameLevel() + 10) end
    if closeButton then level = math.max(level, closeButton:GetFrameLevel()) end
    gear:SetFrameLevel(level)
    if closeButton then
        gear:SetPoint("RIGHT", closeButton, "LEFT", -2, 0)
    else
        gear:SetPoint("TOPRIGHT", -32, -5)
    end
    local gearTexture = "Interface\\AddOns\\" .. ADDON .. "\\Icons\\Gear.png"
    gear:SetNormalTexture(gearTexture)
    gear:GetNormalTexture():SetVertexColor(0.95, 0.82, 0.3)
    gear:SetHighlightTexture(gearTexture, "ADD")
    gear:SetScript("OnClick", function() ns.Prefs_Toggle() end)
    gear:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText(ns.L["Preferences"])
        GameTooltip:Show()
    end)
    gear:SetScript("OnLeave", GameTooltip_Hide)

    frame.header = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    frame.header:SetPoint("TOPLEFT", mainLeft(), -top)
    frame.header:SetPoint("RIGHT", frame, "RIGHT", -32, 0)
    frame.header:SetJustifyH("LEFT")
    frame.header:SetWordWrap(false)

    -- Filter bar under the title: search by title and checkboxes, placed in rows that rearrange with the
    -- window's width (layoutToolbar, below).
    local toolbarLeft = mainLeft()
    local toolbarItems = {}
    local okSearch, box = pcall(CreateFrame, "EditBox", nil, frame, "SearchBoxTemplate")
    if not okSearch or not box then
        box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
        box:SetTextInsets(6, 6, 0, 0)
    end
    searchBox = box
    box:SetSize(200, 20)
    box:SetAutoFocus(false)
    toolbarItems[#toolbarItems + 1] = { frame = box, w = 204, h = 24, dy = 2 }
    local placeholder = box.Instructions
    if placeholder then
        placeholder:SetText(ns.L["Search by title"])
    else
        placeholder = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        placeholder:SetPoint("LEFT", 8, 0)
        placeholder:SetText(ns.L["Search by title"])
    end
    box:HookScript("OnTextChanged", function(self)
        searchText = strtrim(self:GetText() or ""):lower()
        if placeholder and not box.Instructions then placeholder:SetShown(searchText == "") end
        ns.RequestRefresh()
    end)
    box:HookScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local function makeCheck(key, label, tip)
        local cb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        local text = cb.Text or cb.text
        if not text then
            text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            text:SetPoint("LEFT", cb, "RIGHT", 0, 1)
        end
        text:SetText(label)
        cb:SetChecked(ns.char.filters[key] and true or false)
        filterChecks[key] = cb
        cb:SetScript("OnClick", function(self)
            ns.char.filters[key] = self:GetChecked() and true or false
            ns.UI_Refresh()
        end)
        cb:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(label)
            GameTooltip:AddLine(tip, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        cb:SetScript("OnLeave", GameTooltip_Hide)
        toolbarItems[#toolbarItems + 1] = { frame = cb, w = ns.CheckWidth(cb, text), h = 24 }
    end
    makeCheck("hideLow", ns.L["Hide low level"], ns.L["Hides quests that are grey for your level (trivial)."])
    makeCheck("hideHigh", ns.L["Hide too high"], ns.L["Hides quests you cannot take yet, because of your level."])
    makeCheck("hideDone", ns.L["Hide completed"], ns.L["Hides the quests you have completed, also inside unfinished chains."])
    makeCheck("otherFaction", ns.L["Show other faction"],
        ns.L["Shows the quests and zones of the opposite faction, hidden by default."])

    -- hint at the bottom: takes the tree area's width and is cut ("...") if it doesn't fit
    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMLEFT", mainLeft(), 12)
    hint:SetPoint("BOTTOMRIGHT", -26, 12)
    hint:SetJustifyH("RIGHT")
    hint:SetWordWrap(false)
    hint:SetText(ns.L["Drag: pan  |  Wheel: zoom  |  Shift+wheel: sideways  |  Ctrl+wheel: vertical"])

    local listScroll = ns.HideableScroll(CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate"))
    listScroll:SetPoint("TOPLEFT", 12, -top)
    listScroll:SetPoint("BOTTOMLEFT", 12, 14)
    frame.listTop = top
    listScroll:SetWidth(sideW() - 22)
    frame.listChild = CreateFrame("Frame", nil, listScroll)
    frame.listChild:SetSize(sideW() - 26, 1)
    listScroll:SetScrollChild(frame.listChild)

    -- "Search quests..." and "Quest Log": first entries of the side panel; they open the table in the main
    -- area (the search with its form, or the quests you carry in your log)
    local function sideButton(kind, icon, label)
        local b = CreateFrame("Button", nil, frame.listChild, "BackdropTemplate")
        b.kind, b.title = kind, label
        b:SetHeight(26)
        b:SetBackdrop(BACKDROP)
        local tex = b:CreateTexture(nil, "ARTWORK")
        tex:SetSize(14, 14)
        tex:SetTexture(icon)
        local text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        text:SetPoint("LEFT", tex, "RIGHT", 6, 0)
        text:SetText(label)
        b.tex, b.text = tex, text
        b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
        b:SetScript("OnClick", function() ns.UI_SetSearchMode(true, kind) end)
        b:SetScript("OnEnter", showSideTooltip)
        b:SetScript("OnLeave", GameTooltip_Hide)
        searchButtons[#searchButtons + 1] = b
    end
    sideButton("search", "Interface\\Common\\UI-Searchbox-Icon", ns.L["Search quests..."])
    sideButton("log", "Interface\\GossipFrame\\ActiveQuestIcon", ns.L["Quest Log"])
    sideButton("tracked", "Interface\\GossipFrame\\AvailableQuestIcon", ns.L["Tracked Quests"])

    -- first row of the side panel: collapses it to the icons, or expands it back
    sideToggle = CreateFrame("Button", nil, frame.listChild)
    sideToggle:SetHeight(TOGGLE_H)
    sideToggle.tex = sideToggle:CreateTexture(nil, "ARTWORK")
    sideToggle.tex:SetSize(16, 16)
    sideToggle.text = sideToggle:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    sideToggle.text:SetPoint("LEFT", sideToggle.tex, "RIGHT", 4, 0)
    sideToggle.text:SetText(ns.L["Collapse menu"])
    sideToggle:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    sideToggle:SetScript("OnClick", function() ns.UI_SetSideCollapsed(not collapsed()) end)
    sideToggle:SetScript("OnEnter", showSideTooltip)
    sideToggle:SetScript("OnLeave", GameTooltip_Hide)

    frame.searchPanel = ns.Search_Create(frame)
    frame.searchPanel:SetPoint("TOPLEFT", mainLeft(), -top)
    frame.searchPanel:SetPoint("BOTTOMRIGHT", -8, 30)

    local treeScroll = ns.HideableScroll(CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate"))
    treeScroll:SetPoint("TOPLEFT", treeLeft(), -ns.TREE_TOP)
    treeScroll:SetPoint("BOTTOMRIGHT", -32, 30)
    canvas = CreateFrame("Frame", nil, treeScroll)
    canvas:SetSize(1, 1)
    treeScroll:SetScrollChild(canvas)
    frame.treeScroll = treeScroll
    ns.Detail_Create(frame, treeScroll, treeLeft(), frame.searchPanel)

    -- filters in rows by width; the tree starts under the last row
    local function layoutToolbar()
        local width = frame:GetWidth() - toolbarLeft - 32
        local h = ns.FlowLayout(frame, toolbarItems, toolbarLeft, top + 26, width, 10, 2)
        ns.TREE_TOP = top + 26 + h + 8
        treeScroll:SetPoint("TOPLEFT", treeLeft(), -ns.TREE_TOP)
        ns.Detail_Layout()
    end
    layoutToolbar()
    frame:HookScript("OnSizeChanged", layoutToolbar)

    -- everything that starts where the side panel ends moves with it when it collapses or expands
    function ns.UI_ApplySideWidth()
        local w = sideW()
        toolbarLeft = mainLeft()
        frame.header:ClearAllPoints()
        frame.header:SetPoint("TOPLEFT", mainLeft(), -top)
        frame.header:SetPoint("RIGHT", frame, "RIGHT", -32, 0)
        hint:ClearAllPoints()
        hint:SetPoint("BOTTOMLEFT", mainLeft(), 12)
        hint:SetPoint("BOTTOMRIGHT", -26, 12)
        listScroll:SetWidth(w - 22)
        listScroll:SetVerticalScroll(0)
        frame.listChild:SetWidth(w - 26)
        frame.searchPanel:ClearAllPoints()
        frame.searchPanel:SetPoint("TOPLEFT", mainLeft(), -top)
        frame.searchPanel:SetPoint("BOTTOMRIGHT", -8, 30)
        ns.Detail_SetOffset(treeLeft())
        layoutToolbar()
    end

    -- what is hidden while the search is open
    treeWidgets = { frame.header, searchBox, hint, treeScroll }
    for _, cb in pairs(filterChecks) do treeWidgets[#treeWidgets + 1] = cb end

    -- Tree zoom: the canvas is scaled; saved with the settings.
    local zoom = math.max(ZOOM_MIN, math.min(ZOOM_MAX, ns.char.zoom or 1))
    canvas:SetScale(zoom)

    local function maxScroll(self)
        return math.max(0, canvas:GetWidth() * zoom - self:GetWidth()), math.max(0, canvas:GetHeight() * zoom - self:GetHeight())
    end
    local function scrollTo(self, x, y)
        local maxX, maxY = maxScroll(self)
        self:SetHorizontalScroll(math.max(0, math.min(x, maxX)))
        self:SetVerticalScroll(math.max(0, math.min(y, maxY)))
    end

    function ns.UI_SetZoom(z)
        zoom = math.max(ZOOM_MIN, math.min(ZOOM_MAX, z))
        ns.char.zoom = zoom
        canvas:SetScale(zoom)
        scrollTo(treeScroll, 0, 0)
    end

    -- centers a tree quest in the view (search results)
    function frame.scrollToQuest(id)
        local p = nodePos[id]
        if not p then return end
        local cx, cy = (p.x + NODE_W / 2) * zoom, (p.y + NODE_H / 2) * zoom
        scrollTo(treeScroll, cx - treeScroll:GetWidth() / 2, cy - treeScroll:GetHeight() / 2)
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
            local newZoom = math.max(ZOOM_MIN, math.min(ZOOM_MAX, zoom * (delta > 0 and ZOOM_STEP or 1 / ZOOM_STEP)))
            if newZoom == zoom then return end
            local px, py = GetCursorPosition()
            local scale = self:GetEffectiveScale()
            local cx = px / scale - (self:GetLeft() or 0)
            local cy = (self:GetTop() or 0) - py / scale
            local contentX, contentY = (x + cx) / zoom, (y + cy) / zoom
            zoom = newZoom
            ns.char.zoom = zoom
            canvas:SetScale(zoom)
            scrollTo(self, contentX * zoom - cx, contentY * zoom - cy)
        end
    end)

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
        elseif not viewRestored and (ns.char.view == "log" or ns.char.view == "search" or ns.char.view == "tracked") then
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
if C_QuestLog.SetSelectedQuest then
    hooksecurefunc(C_QuestLog, "SetSelectedQuest", function(questID)
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
