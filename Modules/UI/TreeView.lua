local ADDON, ns = ...
local C_QuestLog = ns.QuestLog or C_QuestLog -- never the game's table directly (QuestLogCompat.lua)
local T = ns.Theme

-- The chain-tree renderer (nodes, their connectors, the status halo and pulse, the compact title at low zoom): one
-- instance per canvas that needs to show it. The main window owns one (its tree, search results aside); a pinned
-- chain window (PinnedChains.lua) owns a smaller one of its own. Each instance keeps its own node/rail/gem/arrow
-- pools and node positions, so several can be on screen at once without stepping on each other.
--
-- ns.NewTreeView(parent, opts) -> instance
--   opts.onClick(quest, button, instance)    -- a node's click (left: usually toggle its details; right: its menu)
--   opts.onDragStart(instance), opts.onDragStop(instance)   -- dragging a node (nil: dragging it does nothing)
--   opts.wholeChainLit() -> set or nil   -- when the selected quest is in this set, the whole set lights up (not
--     just the path to it); called on each Render, since what it returns can change between one and the next
-- instance:Render(quests, filterFn, selected) -> layout
--   quests: the entry's quest list; filterFn(q) -> shown or not; selected: the quest whose chain to highlight
--   (its path lit, the rest of what's shown dimmed), or nil for none. Returns BuildLayout's layout (row/col counts
--   included, for the caller to size its own scroll holder).
-- instance.canvas -- the frame everything is drawn onto; the caller places, scales and scrolls it
-- instance.nodePos -- { [questId] = {x, y} }, in canvas units, kept from the last Render
-- instance:SetZoom(z) -- for the compact low-zoom title (see COMPACT_ZOOM); purely cosmetic, does not scale canvas

local NODE_W, NODE_H, GAP_X, GAP_Y, PAD = 204, 80, 28, 46, 24
local NODE_ICON, NODE_ICONS = 14, 5
local NODE_CORNER, NODE_PAD_X, NODE_PAD_TOP, NODE_PAD_BOTTOM = 18, 25, 14, 13
ns.TREE_NODE_W, ns.TREE_NODE_H = NODE_W, NODE_H -- read by callers that must place things around the canvas

local function itemIcon(id)
    local f = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
    local icon = f and select(5, f(id))
    return icon or 134400
end

-- ns.STATUS_COLORS / ns.STATUS_LABELS: set by MainWindow.lua; read live below (load order between the two
-- files is not guaranteed), never snapshotted into a local at this top level.
local REPEATABLE_COLOR = { 0.45, 0.80, 1.00 }

local FRAMES = {
    iron = T.MEDIA .. "NodeIron", bronze = T.MEDIA .. "NodeBronze", locked = T.MEDIA .. "NodeLocked", gold = T.MEDIA .. "NodeGold",
}

local COMPACT_ZOOM, TITLE_SCREEN_SIZE, TITLE_MAX_SIZE = 0.75, 10, 22
function ns.UI_NodeTitleSize(zoom)
    local base = T.fonts.quest[2]
    if zoom >= COMPACT_ZOOM then return base end
    return math.min(TITLE_MAX_SIZE, math.max(base, TITLE_SCREEN_SIZE / zoom))
end

local HIGH_LEVEL_ALPHA, LOW_LEVEL_ALPHA = 0.75, 0.88
local OFF_CHAIN_ALPHA, OFF_CHAIN_LINE_ALPHA = 0.55, 0.35
local RAIL_W, RAIL_PERIOD = 7, 112
local RAIL_RUNES, RAIL_IRON = T.MEDIA .. "RailRunes", T.MEDIA .. "RailIron"

local function showNodeTooltip(btn)
    local q, status, reasons = btn.quest, btn.status, btn.reasons
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ns.QuestTitle(q.id, q.name), 1, 1, 1)
    local c = ns.STATUS_COLORS[status]
    local alt = status == "done" and not C_QuestLog.IsQuestFlaggedCompleted(q.id) and ns.DoneByAltsText(q.id)
    GameTooltip:AddLine(alt and ns.L["Completed by %s"]:format(alt) or ns.STATUS_LABELS[status], c[1], c[2], c[3])
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

-- What a node says under its title, and in which color (see MainWindow.lua's original comment).
local entryIds = {}
local function inEntry(entryId, id)
    local set = entryIds[entryId]
    if not set then
        set = {}
        local d = ns.entries[entryId]
        for _, other in ipairs(d and d.quests or {}) do set[other.id] = true end
        entryIds[entryId] = set
    end
    return set[id] == true
end

local function outsideRequirement(q)
    for _, id in ipairs(q.requires or {}) do
        if not ns.IsQuestDone(id) and not inEntry(q.entryId, id) then
            local def = ns.FindQuestDef(id)
            return ns.L["Requires: "] .. ns.QuestTitle(id, def and def.name)
        end
    end
end

local function nodeSubtitle(q, status, ready)
    if status == "done" then
        local alt = not C_QuestLog.IsQuestFlaggedCompleted(q.id) and ns.DoneByAltsText(q.id)
        return alt and ns.L["Completed by %s"]:format(alt) or ns.STATUS_LABELS.done, { T.rgba("gold") }
    elseif status == "locked" then
        local outside = outsideRequirement(q)
        if outside then return outside, { T.rgba("danger") } end
        if q.minLevel and UnitLevel("player") < q.minLevel then
            return ns.L["Level %d required"]:format(q.minLevel), { T.rgba("danger") }
        end
        return ns.STATUS_LABELS.locked, { T.rgba("danger") }
    elseif status == "missed" then
        return ns.STATUS_LABELS[status], { T.rgba("danger") }
    elseif ready then
        return ns.L["Ready to turn in"], { T.rgba("ready") }
    elseif status == "active" then
        return ns.STATUS_LABELS.active, { T.rgba("active") }
    end
    local level = q.level or q.minLevel
    local zone = q.start and q.start.area and C_Map.GetAreaInfo(q.start.area)
    local text = ((level and ("[" .. level .. "] ") or "") .. (zone or "")):gsub(" $", "")
    return text, level and { ns.QuestLevelColorRGB(level) } or { T.rgba("muted") }
end

local Instance = {}
Instance.__index = Instance

-- The node's text for the current zoom: the full plate, or the title alone (see COMPACT_ZOOM).
function Instance:fitNodeText(b)
    local compact = self.nodeZoom < COMPACT_ZOOM
    b.text:SetFont(T.fonts.quest[1], ns.UI_NodeTitleSize(self.nodeZoom), "")
    if b.compact ~= compact then
        b.compact = compact
        b.text:ClearAllPoints()
        if compact then
            b.text:SetPoint("LEFT", NODE_PAD_X - 6, 0)
            b.text:SetPoint("RIGHT", -(NODE_PAD_X - 6), 0)
        else
            b.text:SetPoint("TOPLEFT", NODE_PAD_X, -NODE_PAD_TOP)
            b.text:SetPoint("TOPRIGHT", -NODE_PAD_X, -NODE_PAD_TOP)
        end
        b.text:SetWordWrap(compact)
        if b.text.SetMaxLines then b.text:SetMaxLines(compact and 2 or 0) end
        b.veil:SetPoint("BOTTOMRIGHT", compact and b.text or b.sub, "BOTTOMRIGHT", 6, -2)
        b.sub:SetShown(not compact)
        b.xp:SetShown(not compact)
        b.money:SetShown(not compact)
    end
    for _, icon in ipairs(b.icons) do icon:SetShown(icon.wanted and not compact) end
end

-- Resizes the title for every node already drawn, for the zoom now in effect (see SetZoom).
function Instance:RefitNodes()
    for _, b in ipairs(self.nodeButtons) do self:fitNodeText(b) end
end

function Instance:SetZoom(z)
    self.nodeZoom = z
    self:RefitNodes()
end

local function onNodeClick(self, button)
    local view = self.view
    if self.dragged then
        self.dragged = false
        return
    end
    if button == "RightButton" then
        ns.QuestMenu(self, self.quest)
        return
    end
    if view.onClick then view.onClick(self.quest, button, view) end
end

function Instance:getNodeButton(i)
    local b = self.nodeButtons[i]
    if b then return b end
    local canvas = self.canvas
    b = CreateFrame("Button", nil, canvas)
    b.view = self
    b:SetSize(NODE_W, NODE_H)
    b.glowFrame = CreateFrame("Frame", nil, b)
    b.glowFrame:SetAllPoints()
    b.glowFrame:SetFrameLevel(math.max(0, b:GetFrameLevel() - 1))
    b.glow = T.NineSlice(b.glowFrame, T.MEDIA .. "NodeHalo", 512, 256, 64, 24, 11, "BACKGROUND", 0, true)
    for _, tex in ipairs(b.glow) do tex:SetBlendMode("ADD") end
    b.pulse = b.glowFrame:CreateAnimationGroup()
    local fade = b.pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.3)
    fade:SetDuration(0.9)
    fade:SetSmoothing("IN_OUT")
    b.pulse:SetLooping("BOUNCE")
    b.plate = T.NineSlice(b, FRAMES.iron, 256, 256, 56, NODE_CORNER, 0, "BACKGROUND", 1, true)
    b.frameFile = FRAMES.iron
    b.text = T.Text(b, "quest")
    b.text:SetPoint("TOPLEFT", NODE_PAD_X, -NODE_PAD_TOP)
    b.text:SetPoint("TOPRIGHT", -NODE_PAD_X, -NODE_PAD_TOP)
    b.text:SetJustifyH("CENTER")
    b.text:SetWordWrap(false)
    b.sub = T.Text(b, "small")
    b.sub:SetPoint("TOPLEFT", b.text, "BOTTOMLEFT", 0, -2)
    b.sub:SetPoint("TOPRIGHT", b.text, "BOTTOMRIGHT", 0, -2)
    b.sub:SetJustifyH("CENTER")
    b.sub:SetWordWrap(false)
    b.veil = b:CreateTexture(nil, "BACKGROUND", nil, 3)
    b.veil:SetPoint("TOPLEFT", b.text, "TOPLEFT", -6, 2)
    b.veil:SetPoint("BOTTOMRIGHT", b.sub, "BOTTOMRIGHT", 6, -2)
    b.veil:SetColorTexture(0, 0, 0, 0.45)
    b.xp = T.Text(b, "data", "muted")
    b.xp:SetPoint("BOTTOMRIGHT", -NODE_PAD_X, NODE_PAD_BOTTOM)
    b.xp:SetJustifyH("RIGHT")
    b.money = T.Text(b, "data", "muted")
    b.money:SetPoint("BOTTOMLEFT", NODE_PAD_X, NODE_PAD_BOTTOM)
    b.money:SetJustifyH("LEFT")
    b.icons = {}
    for k = 1, NODE_ICONS do
        local icon = CreateFrame("Button", nil, b)
        icon:SetSize(NODE_ICON, NODE_ICON)
        icon.tex = icon:CreateTexture(nil, "ARTWORK")
        icon.tex:SetAllPoints()
        icon.tex:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        icon:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        icon:SetScript("OnEnter", function(self2)
            GameTooltip:SetOwner(self2, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self2.itemID)
            GameTooltip:Show()
        end)
        icon:SetScript("OnLeave", GameTooltip_Hide)
        icon:SetScript("OnClick", function(self2, btn2) onNodeClick(self2:GetParent(), btn2) end)
        icon:RegisterForDrag("LeftButton")
        icon:SetScript("OnMouseDown", function(self2) self2:GetParent().dragged = false end)
        icon:SetScript("OnDragStart", function(self2) self2:GetParent():GetScript("OnDragStart")(self2:GetParent()) end)
        icon:SetScript("OnDragStop", function() if b.view.onDragStop then b.view.onDragStop(b.view) end end)
        icon:Hide()
        b.icons[k] = icon
    end
    b.badge = b:CreateTexture(nil, "OVERLAY")
    b.badge:SetSize(16, 16)
    b.badge:SetPoint("TOPLEFT", -6, 6)
    b.badge:Hide()
    b.ready = b:CreateTexture(nil, "OVERLAY")
    b.ready:SetSize(18, 18)
    b.ready:SetPoint("TOPRIGHT", 6, 6)
    b.ready:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    b.ready:Hide()
    b:SetScript("OnEnter", showNodeTooltip)
    b:SetScript("OnLeave", GameTooltip_Hide)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    b:SetScript("OnClick", onNodeClick)
    b:RegisterForDrag("LeftButton")
    b:SetScript("OnMouseDown", function(self2) self2.dragged = false end)
    b:SetScript("OnDragStart", function(self2)
        self2.dragged = true
        GameTooltip:Hide()
        if self.onDragStart then self.onDragStart(self) end
    end)
    b:SetScript("OnDragStop", function() if self.onDragStop then self.onDragStop(self) end end)
    self.nodeButtons[i] = b
    return b
end

local function pooled(instance, pool, i, layer, file)
    local t = pool[i]
    if t then return t end
    t = instance.canvas:CreateTexture(nil, layer)
    if file then t:SetTexture(file) end
    pool[i] = t
    return t
end

function Instance:Render(quests, filterFn, selected)
    local layout = ns.BuildLayout(quests, filterFn)
    local canvas = self.canvas

    canvas:SetSize(
        math.max(1, PAD * 2 + layout.rows * NODE_W + (layout.rows - 1) * GAP_X),
        math.max(1, PAD * 2 + layout.cols * NODE_H + (layout.cols - 1) * GAP_Y))
    local across = {}
    for _, n in pairs(layout.nodes) do
        across[n.col] = across[n.col] or {}
        table.insert(across[n.col], n.row)
    end
    local function posOf(n)
        return PAD + n.row * (NODE_W + GAP_X), PAD + n.col * (NODE_H + GAP_Y)
    end

    local chainSet
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
        -- in the chain view (opts.wholeChainLit(), if given) the whole chain is lit, branches included, not only
        -- the path through it; a function, since what it returns can change between one Render and the next
        local whole = self.wholeChainLit and self.wholeChainLit()
        if whole and whole[selected.id] then
            for id in pairs(whole) do
                if layout.nodes[id] then chainSet[id] = true end
            end
        end
    end

    local byId, i, nodePos = {}, 0, self.nodePos
    for k in pairs(nodePos) do nodePos[k] = nil end
    for id, n in pairs(layout.nodes) do
        local nx, ny = posOf(n)
        nodePos[id] = { x = nx, y = ny }
        i = i + 1
        local b = self:getNodeButton(i)
        local status, reasons = ns.QuestStatus(n.quest)
        b.quest, b.status, b.reasons = n.quest, status, reasons
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", canvas, "TOPLEFT", nx, -ny)
        local picked = ns.Detail_Current() and ns.Detail_Current().id == n.quest.id
        local file = picked and FRAMES.gold or status == "done" and FRAMES.bronze
            or (status == "locked" or status == "missed") and FRAMES.locked or FRAMES.iron
        if b.frameFile ~= file then
            for _, tex in ipairs(b.plate) do tex:SetTexture(file) end
            b.frameFile = file
        end
        local halo, haloAlpha
        if picked then halo, haloAlpha = "goldLight", 1
        elseif status == "done" then halo, haloAlpha = "gold", 0.5
        elseif status == "missed" then halo, haloAlpha = "danger", 0.45
        elseif status ~= "locked" then halo, haloAlpha = "ready", 0.8 end
        b.glowFrame:SetShown(halo ~= nil)
        if halo then T.SliceColor(b.glow, T.rgba(halo, haloAlpha)) end
        if status == "active" and not picked then
            if not b.pulse:IsPlaying() then b.pulse:Play() end
        else
            b.pulse:Stop()
            b.glowFrame:SetAlpha(1)
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
        local sub, subColor = nodeSubtitle(n.quest, status, b.readyToTurnIn)
        b.sub:SetText(sub)
        b.sub:SetTextColor(subColor[1], subColor[2], subColor[3])
        local xp = ns.QuestXP(n.quest.id)
        b.xp:SetText(xp > 0 and ("%s %s"):format(BreakUpLargeNumbers and BreakUpLargeNumbers(xp) or xp, ns.L["XP"]) or "")
        local reward = ns.REWARDS and ns.REWARDS[n.quest.id]
        b.money:SetText(reward and reward.money and ns.CoinString(reward.money) or "")
        local x = NODE_PAD_X + (reward and reward.money and b.money:GetStringWidth() + 4 or 0)
        local limit = NODE_W - NODE_PAD_X - (xp > 0 and b.xp:GetStringWidth() + 4 or 0)
        local ids = reward and ns.RewardItemIds(reward) or {}
        for k, icon in ipairs(b.icons) do
            local itemId = ids[k]
            icon.wanted = itemId and x + NODE_ICON <= limit
            if icon.wanted then
                icon:ClearAllPoints()
                icon:SetPoint("BOTTOMLEFT", b, "BOTTOMLEFT", x, NODE_PAD_BOTTOM - 2)
                icon.itemID = itemId
                icon.tex:SetTexture(itemIcon(itemId))
                x = x + NODE_ICON + 2
            end
        end
        self:fitNodeText(b)
        if status == "locked" or status == "missed" then
            b.text:SetTextColor(T.rgba("muted"))
        elseif n.quest.repeatable then
            b.text:SetTextColor(REPEATABLE_COLOR[1], REPEATABLE_COLOR[2], REPEATABLE_COLOR[3])
        else
            b.text:SetTextColor(T.rgba("text"))
        end
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

    local rails, gems, arrows = self.rails, self.gems, self.arrows
    local railCount, gemCount, arrowCount = 0, 0, 0
    local railFile, railAlpha = RAIL_IRON, 1
    local function rail(x1, y1, x2, y2)
        if x1 == x2 and y1 == y2 then return end
        railCount = railCount + 1
        local t = pooled(self, rails, railCount, "BORDER")
        t:SetTexture(railFile, "REPEAT", "REPEAT")
        t:SetAlpha(railAlpha)
        t:ClearAllPoints()
        local half = RAIL_W / 2
        if y1 == y2 then
            local len = math.abs(x2 - x1) + RAIL_W
            t:SetPoint("TOPLEFT", canvas, "TOPLEFT", math.min(x1, x2) - half, -(y1 - half))
            t:SetSize(len, RAIL_W)
            t:SetTexCoord(0, len / RAIL_PERIOD, 0, 1)
        else
            local len = math.abs(y2 - y1) + RAIL_W
            local k = len / RAIL_PERIOD
            t:SetPoint("TOPLEFT", canvas, "TOPLEFT", x1 - half, -(math.min(y1, y2) - half))
            t:SetSize(RAIL_W, len)
            t:SetTexCoord(0, 0, k, 0, 0, 1, k, 1)
        end
        t:Show()
    end
    local function gem(x, y)
        gemCount = gemCount + 1
        local t = pooled(self, gems, gemCount, "ARTWORK", T.MEDIA .. "RailGem")
        t:SetSize(14, 14)
        t:SetAlpha(railAlpha)
        t:ClearAllPoints()
        t:SetPoint("CENTER", canvas, "TOPLEFT", x, -y)
        t:Show()
    end
    local function arrow(x, y)
        arrowCount = arrowCount + 1
        local t = pooled(self, arrows, arrowCount, "ARTWORK", T.MEDIA .. "RailArrow")
        t:SetSize(16, 16)
        t:SetAlpha(railAlpha)
        t:ClearAllPoints()
        t:SetPoint("BOTTOM", canvas, "TOPLEFT", x, -y)
        t:Show()
    end
    local function lane(k) return ((k % 5) - 2) * 5 end
    local function depthY(depth) return PAD + depth * (NODE_H + GAP_Y) end
    local function corridorX(depth, x)
        local places = across[depth]
        if not places then return x end
        local best
        for _, place in ipairs(places) do
            local left = PAD + place * (NODE_W + GAP_X)
            for _, cx in ipairs({ left - GAP_X / 2, left + NODE_W + GAP_X / 2 }) do
                if not best or math.abs(cx - x) < math.abs(best - x) then best = cx end
            end
        end
        return best
    end
    local function drawEdge(e)
        local a, b = layout.nodes[e.from], layout.nodes[e.to]
        local ax, ay = posOf(a)
        local bx, by = posOf(b)
        local xA, yA = ax + NODE_W / 2, ay + NODE_H
        local xB, yB = bx + NODE_W / 2, by
        if b.col <= a.col then
            rail(xA, yA, xB, yA)
            rail(xB, yA, xB, yB)
        else
            local yGap = yA + GAP_Y / 2 + lane(a.row)
            if b.col == a.col + 1 then
                rail(xA, yA, xA, yGap)
                rail(xA, yGap, xB, yGap)
                rail(xB, yGap, xB, yB)
                if xA ~= xB then
                    gem(xA, yGap)
                    gem(xB, yGap)
                end
            else
                local x, y = xA, yGap
                rail(xA, yA, xA, yGap)
                for depth = a.col + 1, b.col - 1 do
                    local cx = corridorX(depth, x) + lane(a.row + a.col) / 2
                    if cx ~= x then
                        rail(x, y, cx, y)
                        gem(x, y)
                        gem(cx, y)
                        x = cx
                    end
                    local below = depthY(depth) + NODE_H + GAP_Y / 2 + lane(a.row)
                    rail(x, y, x, below)
                    y = below
                end
                if x ~= xB then
                    rail(x, y, xB, y)
                    gem(x, y)
                    gem(xB, y)
                end
                rail(xB, y, xB, yB)
            end
        end
        arrow(xB, yB + 3)
    end

    for _, e in ipairs(layout.edges) do
        local inChain = chainSet and chainSet[e.from] and chainSet[e.to]
        if not inChain and byId[e.from].status ~= "done" then
            railFile, railAlpha = RAIL_IRON, chainSet and OFF_CHAIN_LINE_ALPHA or 0.9
            drawEdge(e)
        end
    end
    for _, e in ipairs(layout.edges) do
        local inChain = chainSet and chainSet[e.from] and chainSet[e.to]
        if inChain or byId[e.from].status == "done" then
            railFile, railAlpha = RAIL_RUNES, (chainSet and not inChain) and OFF_CHAIN_LINE_ALPHA or 1
            drawEdge(e)
        end
    end
    for k = i + 1, #self.nodeButtons do self.nodeButtons[k]:Hide() end
    for k = railCount + 1, #rails do rails[k]:Hide() end
    for k = gemCount + 1, #gems do gems[k]:Hide() end
    for k = arrowCount + 1, #arrows do arrows[k]:Hide() end
    return layout
end

-- parent: the frame the canvas is created on (a ScrollFrame's scroll child, or any plain frame for a non-scrolling
-- pinned window). opts: see the file comment.
function ns.NewTreeView(parent, opts)
    opts = opts or {}
    local self = setmetatable({
        nodeButtons = {}, rails = {}, gems = {}, arrows = {}, nodePos = {},
        nodeZoom = 1, onClick = opts.onClick, onDragStart = opts.onDragStart, onDragStop = opts.onDragStop,
        wholeChainLit = opts.wholeChainLit,
    }, Instance)
    self.canvas = CreateFrame("Frame", nil, parent)
    return self
end
