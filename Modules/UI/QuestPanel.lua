local _, ns = ...
local L = ns.L

local DETAIL_H = 210
local BACKDROP = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }

local detail, parentFrame, treeScroll, current, leftOff, companion
-- the text's scroll bar only shows when the text doesn't fit; without it the text gets its room
local scrollBar, scrollBottom = false, 38
local function anchorScroll()
    detail.scroll:SetPoint("BOTTOMRIGHT", -(scrollBar and 28 or 4), scrollBottom)
end
local maximized = false

local function describeLocation(loc)
    local zone = loc.area and C_Map.GetAreaInfo(loc.area)
    local where
    if loc.x and loc.x > 0 then
        where = ("%s (%.1f, %.1f)"):format(zone or "?", loc.x, loc.y)
    elseif zone then
        where = zone
    else
        where = L["Inside the instance"]
    end
    return loc.npc and (loc.npc .. " - " .. where) or where
end

-- The quest's steps (ns.QuestSteps, Modules/Quest) for the waypoint button, the map and the panel's list.
local WAY_W = 230
local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12|t "
local ARROW = "|TInterface\\RaidFrame\\ReadyCheck-Waiting:12:12|t "
local picked -- { id = quest, index = step } picked in the dropdown; otherwise the step that comes next

local function selectedStep()
    local steps = detail.steps
    if not (current and steps and #steps > 0) then return nil end
    if picked and picked.id == current.id and steps[picked.index] then return steps[picked.index] end
    return steps[detail.currentStep or 1]
end

local stepTarget = ns.StepTarget

local function stepZone(step)
    local area = (step.loc and step.loc.area) or step.area
    if area then return C_Map.GetAreaInfo(area) end
    local map = step.loc and step.loc.map -- a spot the game gave
    local info = map and C_Map.GetMapInfo(map)
    return info and info.name or nil
end

-- List of steps (goes after the objective): done ones with a green tick, the next one in yellow with an
-- arrow, each objective's progress while you carry the quest, and the zone where it is done.
local function stepsText()
    local lines = {}
    for _, step in ipairs(detail.steps or {}) do
        local mark = step.done and CHECK or step.current and ARROW or "    "
        local color = step.done and "|cff88bb88" or step.current and "|cffffd100" or "|cffffffff"
        local zone = stepZone(step)
        local where = zone and (" |cff999999- " .. zone .. "|r") or (step.kind == "obj" and not step.loc
            and (" |cff777777(" .. L["no location"] .. ")|r") or "")
        lines[#lines + 1] = mark .. color .. step.label .. (step.progress and ("  " .. step.progress) or "") .. "|r" .. where
    end
    return table.concat(lines, "\n")
end

local function buildText(q)
    local parts = {}
    local function section(title, body)
        parts[#parts + 1] = "|cffffd100" .. title .. "|r\n" .. body
    end

    local req = {}
    for _, id in ipairs(q.requires or {}) do
        local def = ns.FindQuestDef(id)
        local met = C_QuestLog.IsQuestFlaggedCompleted(id)
        req[#req + 1] = (met and "|cff33cc33" or "|cffff5555") .. ns.QuestTitle(id, def and def.name) .. "|r"
    end
    if q.requiresAny and #q.requiresAny > 0 then
        local names, met = {}, false
        for _, id in ipairs(q.requiresAny) do
            met = met or C_QuestLog.IsQuestFlaggedCompleted(id)
            local def = ns.FindQuestDef(id)
            names[#names + 1] = ns.QuestTitle(id, def and def.name)
        end
        req[#req + 1] = (met and "|cff33cc33" or "|cffff5555") .. L["One of: "] .. table.concat(names, " / ") .. "|r"
    end
    if q.minLevel then
        local met = UnitLevel("player") >= q.minLevel
        req[#req + 1] = (met and "|cff33cc33" or "|cffff5555") .. L["Level %d required"]:format(q.minLevel) .. "|r"
    end
    if ns.IsEliteQuest(q.id) then
        req[#req + 1] = "|cffff6666" .. L["Elite: recommended with a group"] .. "|r"
    end
    local requirements = #req > 0 and table.concat(req, "\n") or L["None"]
    if q.level then requirements = requirements .. "\n" .. ns.QuestLevelColor(q.level) .. L["Level %d recommended"]:format(q.level) .. "|r" end
    section(L["Requirements"], requirements)

    if q.objective then section(L["Objective"], q.objective) end
    if detail.steps and #detail.steps > 0 then section(L["Steps"], stepsText()) end
    if q.dungeon then
        local inside = ns.entries[q.dungeon]
        section(L["Instance"], (inside and ns.EntryName(inside) or "?") .. " -- " .. L["done inside the instance"])
    end
    if q.start then
        section(L["Starts"], describeLocation(q.start))
    else
        local body = L["Unknown location (it may start inside the instance, or it is not in the database yet)."]
        local entry = ns.entries[q.entryId]
        if entry and entry.entrance then
            body = body .. "\n" .. L["Instance entrance: %s"]:format(describeLocation(entry.entrance))
        end
        section(L["Starts"], body)
    end
    if q.finish then section(L["Ends"], describeLocation(q.finish)) end
    if q.note then section(L["Notes"], q.note) end
    -- the long description, at the end: the story is read after the practical parts
    local desc = ns.QuestDescription(q)
    if desc then section(L["Description"], desc) end
    return table.concat(parts, "\n\n")
end

-- Rewards (Data/Generated/Rewards.lua, ns.REWARDS): under the text, a block of text lines and item
-- buttons (icon, count, name in its quality color and the game's tooltip). Names and colors come from the
-- client by item id; if it doesn't have them yet, they are requested and redrawn when they arrive.
local ITEM_W, ITEM_H = 210, 30
local rewardRows
local waitingItems = false

local function getItemInfo(id)
    local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
    if f then return f(id) end
end
local function getItemIcon(id)
    local f = (C_Item and C_Item.GetItemIconByID) or GetItemIcon
    return f and f(id)
end
local function coinString(copper)
    local f = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
    return f and f(copper) or (copper .. "c")
end

local function factionName(id)
    if C_Reputation and C_Reputation.GetFactionDataByID then
        local data = C_Reputation.GetFactionDataByID(id)
        if data and data.name then return data.name end
    end
    if GetFactionInfoByID then
        local name = GetFactionInfoByID(id)
        if name then return name end
    end
    return L["Faction %d"]:format(id)
end

-- Rows of the block: { text = "..." } or { items = { id | { id, count } } }. nil when there are no rewards.
local function buildRewards(q)
    local r = ns.REWARDS and ns.REWARDS[q.id]
    if not r then return nil end
    local rows = { { text = "|cffffd100" .. (REWARDS or L["Rewards"]) .. "|r" } }
    if r.choice then
        rows[#rows + 1] = { text = REWARD_CHOICES or L["You will be able to choose one of these rewards:"] }
        rows[#rows + 1] = { items = r.choice }
    end
    if r.items then
        rows[#rows + 1] = { text = r.choice and (REWARD_ITEMS or L["You will also receive:"])
            or (REWARD_ITEMS_ONLY or L["You will receive:"]) }
        rows[#rows + 1] = { items = r.items }
    end
    local lines = {}
    if r.money then lines[#lines + 1] = L["Money: %s"]:format(coinString(r.money)) end
    if r.xp then
        lines[#lines + 1] = L["Experience: %s"]:format(BreakUpLargeNumbers and BreakUpLargeNumbers(r.xp) or r.xp)
    end
    for _, rep in ipairs(r.rep or {}) do
        lines[#lines + 1] = L["Reputation: %s"]:format(("%+d %s"):format(rep[2], factionName(rep[1])))
    end
    if #lines > 0 then rows[#rows + 1] = { text = table.concat(lines, "\n") } end
    if #rows == 1 then return nil end
    return rows
end

local function rewardText(i)
    local block = detail.rewards
    local fs = block.texts[i]
    if not fs then
        fs = block:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetJustifyH("LEFT")
        fs:SetWordWrap(true)
        block.texts[i] = fs
    end
    return fs
end

local function rewardButton(i)
    local block = detail.rewards
    local b = block.buttons[i]
    if not b then
        b = CreateFrame("Button", nil, block)
        b:SetSize(ITEM_W - 6, ITEM_H)
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize(ITEM_H - 2, ITEM_H - 2)
        b.icon:SetPoint("LEFT", 0, 0)
        b.count = b:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
        b.count:SetPoint("BOTTOMRIGHT", b.icon, "BOTTOMRIGHT", -1, 1)
        b.name = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        b.name:SetPoint("LEFT", b.icon, "RIGHT", 6, 0)
        b.name:SetPoint("RIGHT", 0, 0)
        b.name:SetJustifyH("LEFT")
        b:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        b:GetHighlightTexture():SetAllPoints(b.icon)
        b:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.itemID)
            GameTooltip:Show()
        end)
        b:SetScript("OnLeave", GameTooltip_Hide)
        -- Shift-click links the item in chat, Ctrl-click tries it on in the dressing room (as in the quest log)
        b:SetScript("OnClick", function(self)
            local link = select(2, getItemInfo(self.itemID))
            if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
        end)
        block.buttons[i] = b
    end
    return b
end

local function setRewardItem(b, entry)
    local id, count = entry, 1
    if type(entry) == "table" then id, count = entry[1], entry[2] end
    b.itemID = id
    b.icon:SetTexture(getItemIcon(id) or 134400) -- question mark when there's no icon
    b.count:SetText(count > 1 and count or "")
    local name, _, quality = getItemInfo(id)
    if not name then
        waitingItems = true
        if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(id) end
        name = L["Item %d"]:format(id)
    end
    local color = quality and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    b.name:SetText(name)
    if color then b.name:SetTextColor(color.r, color.g, color.b) else b.name:SetTextColor(1, 1, 1) end
end

-- Lays the rows out for a given width (items in ITEM_W columns) and returns the block's height.
local function layoutRewards(width)
    local block = detail.rewards
    local y, nText, nButton = 0, 0, 0
    waitingItems = false
    for _, row in ipairs(rewardRows) do
        if row.text then
            nText = nText + 1
            local fs = rewardText(nText)
            fs:SetWidth(width)
            fs:SetText(row.text)
            fs:ClearAllPoints()
            fs:SetPoint("TOPLEFT", 0, -y)
            fs:Show()
            y = y + fs:GetStringHeight() + 6
        else
            local cols = math.max(1, math.floor(width / ITEM_W))
            for k, entry in ipairs(row.items) do
                nButton = nButton + 1
                local b = rewardButton(nButton)
                setRewardItem(b, entry)
                b:ClearAllPoints()
                b:SetPoint("TOPLEFT", ((k - 1) % cols) * ITEM_W, -(y + math.floor((k - 1) / cols) * (ITEM_H + 4)))
                b:Show()
            end
            y = y + math.ceil(#row.items / cols) * (ITEM_H + 4) + 4
        end
    end
    for i = nText + 1, #block.texts do block.texts[i]:Hide() end
    for i = nButton + 1, #block.buttons do block.buttons[i]:Hide() end
    block:SetHeight(math.max(1, y))
    return y
end

local function relayout()
    local w = detail.scroll:GetWidth()
    if w and w > 0 then
        detail.content:SetWidth(w)
        detail.text:SetWidth(w)
    end
    local rewardsH = 0
    if rewardRows then
        detail.rewards:Show()
        rewardsH = layoutRewards(detail.text:GetWidth()) + 16
    else
        detail.rewards:Hide()
    end
    detail.content:SetHeight(math.max(1, detail.text:GetStringHeight() + rewardsH + 6))
end

-- Opens the quest log on that quest. The Forever client uses the modern UI (log inside the map); several
-- ways are tried in order and the first that works is used.
local function openQuest(questID)
    ns.quietSelect = true -- opening it in the log from here must not open it back in the tree
    ns.MuteQuestSelect()
    if C_QuestLog.SetSelectedQuest then pcall(C_QuestLog.SetSelectedQuest, questID) end
    local attempts = {
        function()
            if not QuestMapFrame_OpenToQuestDetails then return false end
            QuestMapFrame_OpenToQuestDetails(questID)
            return true
        end,
        function()
            if not (OpenQuestLog or ToggleQuestLog) then return false end
            (OpenQuestLog or ToggleQuestLog)()
            return true
        end,
        function()
            local index = C_QuestLog.GetLogIndexForQuestID and C_QuestLog.GetLogIndexForQuestID(questID)
            if index and QuestLog_SetSelection and QuestLogFrame then
                QuestLog_SetSelection(index)
                ShowUIPanel(QuestLogFrame)
                return true
            end
            return false
        end,
    }
    for _, attempt in ipairs(attempts) do
        local ok, done = pcall(attempt)
        if ok and done then
            ns.quietSelect = nil
            return true
        end
    end
    ns.quietSelect = nil
    ns.Print(L["Could not open the quest log."])
    return false
end

local function render()
    local q = current
    local status = ns.QuestStatus(q)
    local c = ns.STATUS_COLORS[status]
    detail.title:SetText(ns.QuestTitle(q.id, q.name))
    detail.title:SetTextColor(c[1], c[2], c[3])
    local meta = { ns.STATUS_LABELS[status] }
    if q.level then meta[#meta + 1] = L["Level %d%s"]:format(q.level, q.minLevel and L[" (min %d)"]:format(q.minLevel) or "") end
    meta[#meta + 1] = "ID " .. q.id
    detail.meta:SetText(table.concat(meta, "   |   "))
    detail.steps, detail.currentStep = ns.QuestSteps(q)
    detail.text:SetText(buildText(q))
    rewardRows = buildRewards(q)
    relayout()
    local onQuest = C_QuestLog.IsOnQuest(q.id) and true or false
    -- every button is always there: the ones that don't apply to this quest are disabled, not hidden
    detail.btnOpen:SetEnabled(onQuest)
    detail.btnFocus:SetEnabled(onQuest)
    detail.btnAbandon:SetEnabled(onQuest)
    detail.btnFocus:SetText(ns.Focus_Quest() == q.id and L["Stop focus"] or L["Focus"])
    -- "View chain" goes to the quest's tree, when it is part of a chain
    detail.btnChain:SetEnabled(q.entryId ~= nil and ns.IsInChain(q))
    -- waypoint and map: the chosen step
    local step = selectedStep()
    local loc, isEntrance = nil, false
    if step then loc, isEntrance = stepTarget(q, step) end
    detail.btnWay:SetText(step and L["Waypoint: %s"]:format(step.label) or L["Waypoint: start"])
    detail.btnWay:SetEnabled(loc ~= nil and ns.CanWaypoint(loc))
    detail.btnWayMenu:SetEnabled(detail.steps and #detail.steps > 0)
    detail.btnMap:SetEnabled(loc ~= nil and ns.CanShowMap(loc))
    detail.btnMap:SetText(isEntrance and L["Show entrance"] or L["Show on map"])
    detail.layoutButtons()
end

-- Icon drawn with lines (no client textures needed): a box with a diagonal arrow. Maximize: arrow from
-- the center to the top-left corner. Restore: the other way round.
local function drawMaxIcon(btn, isMaximized)
    local h, a = 6, 4.5
    local segs = {
        { -h, h, h, h }, { h, h, h, -h }, { h, -h, -h, -h }, { -h, -h, -h, h },
    }
    local arrow
    if isMaximized then
        arrow = { { -h, h, 0, 0 }, { 0, 0, -a, 0 }, { 0, 0, 0, a } }
    else
        arrow = { { 0, 0, -h, h }, { -h, h, -h, h - a }, { -h, h, -h + a, h } }
    end
    for _, s in ipairs(arrow) do segs[#segs + 1] = s end

    btn.iconLines = btn.iconLines or {}
    for i, s in ipairs(segs) do
        local line = btn.iconLines[i]
        if not line then
            line = btn:CreateLine(nil, "OVERLAY")
            line:SetThickness(1.5)
            line:SetColorTexture(0.95, 0.95, 0.95, 1)
            btn.iconLines[i] = line
        end
        line:SetStartPoint("CENTER", btn, s[1], s[2])
        line:SetEndPoint("CENTER", btn, s[3], s[4])
    end
end

-- Maximize/restore widget. Preferred: Blizzard's own (the one on the map and the quest log, a gold arrow
-- on a red button). Fallbacks: buttons with the same atlases, and last the line icon. Returns a function
-- that syncs the shown state.
local setMaxState
local syncing = false

local function atlasExists(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local function createMaxWidget(parent, anchorTo, onToggle)
    local ok, f = pcall(CreateFrame, "Frame", nil, parent, "MaximizeMinimizeButtonFrameTemplate")
    if ok and f and f.SetOnMaximizedCallback and f.SetOnMinimizedCallback and f.Maximize and f.Minimize then
        f:SetPoint("RIGHT", anchorTo, "LEFT", 0, 0)
        f:SetOnMaximizedCallback(function() if not syncing then onToggle(true) end end)
        f:SetOnMinimizedCallback(function() if not syncing then onToggle(false) end end)
        return function(isMax)
            syncing = true
            if isMax then f:Maximize() else f:Minimize() end
            syncing = false
        end
    end

    local btn, set
    if atlasExists("RedButton-Expand") and atlasExists("RedButton-Condense") then
        btn = CreateFrame("Button", nil, parent)
        btn:SetSize(26, 26)
        if atlasExists("RedButton-Highlight") then btn:SetHighlightAtlas("RedButton-Highlight") end
        set = function(isMax)
            local name = isMax and "RedButton-Condense" or "RedButton-Expand"
            btn:SetNormalAtlas(name)
            if atlasExists(name .. "-Pressed") then btn:SetPushedAtlas(name .. "-Pressed") end
        end
    else
        btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
        btn:SetSize(28, 22)
        set = function(isMax) drawMaxIcon(btn, isMax) end
    end
    btn:SetPoint("RIGHT", anchorTo, "LEFT", 0, 0)
    btn:SetScript("OnClick", function() onToggle(not maximized) end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(maximized and L["Restore"] or L["Maximize"])
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)
    return set
end

-- Panel at the bottom (with the tree above) or maximized over the whole tree area.
local function layout()
    local right = ns.TREE_RIGHT or 32 -- where the tree ends (its scroll bar takes room only when it shows)
    local shown = detail:IsShown()
    if not shown then maximized = false end
    detail:ClearAllPoints()
    if maximized then
        detail:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", leftOff, -(ns.TREE_TOP or 62))
        detail:SetPoint("BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT", -right, 30)
        treeScroll:Hide()
    else
        detail:SetPoint("BOTTOMLEFT", parentFrame, "BOTTOMLEFT", leftOff, 30)
        detail:SetPoint("BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT", -right, 30)
        detail:SetHeight(DETAIL_H)
        -- the tree only belongs to the tree view: under a table (search, log, tracked) it would show through it
        treeScroll:SetShown(not ns.UI_IsSearchMode())
        treeScroll:SetPoint("BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT", -right, shown and (30 + DETAIL_H + 8) or 30)
    end
    -- the table (search, log, tracked) shares the space too: it ends above the panel
    if companion then
        companion:SetPoint("BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT", -8, shown and not maximized and (30 + DETAIL_H + 8) or 30)
    end
    detail:SetBackdropColor(0.05, 0.05, 0.08, maximized and 1 or 0.95)
    if setMaxState then setMaxState(maximized) end
end

-- The side panel changed width (collapsed / expanded): the panel starts where the main area does.
function ns.Detail_SetOffset(leftOffset)
    leftOff = leftOffset
end

function ns.Detail_Create(parent, tree, leftOffset, companionPanel)
    parentFrame, treeScroll, leftOff, companion = parent, tree, leftOffset, companionPanel
    detail = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    -- above the tables' rows (children of their own frames, so at higher levels than a plain sibling): when
    -- the panel is maximized over a table, the table must not show through
    detail:SetFrameLevel(parent:GetFrameLevel() + 60)
    detail:EnableMouse(true) -- and it takes the clicks, so nothing under it gets them
    detail:SetBackdrop(BACKDROP)
    detail:SetBackdropColor(0.05, 0.05, 0.08, 0.95)
    detail:SetBackdropBorderColor(0.4, 0.4, 0.4, 1)
    detail:Hide()

    detail.title = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    detail.title:SetPoint("TOPLEFT", 10, -8)
    detail.title:SetPoint("RIGHT", -76, 0)
    detail.title:SetJustifyH("LEFT")

    detail.meta = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    detail.meta:SetPoint("TOPLEFT", detail.title, "BOTTOMLEFT", 0, -3)

    local close = CreateFrame("Button", nil, detail, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)
    close:SetScript("OnClick", function() ns.Detail_Hide(); ns.UI_Refresh() end)

    setMaxState = createMaxWidget(detail, close, function(isMax)
        maximized = isMax
        layout()
    end)

    detail.scroll = CreateFrame("ScrollFrame", nil, detail, "UIPanelScrollFrameTemplate")
    detail.scroll:SetPoint("TOPLEFT", 8, -46)
    anchorScroll()
    detail.content = CreateFrame("Frame", nil, detail.scroll)
    detail.content:SetSize(1, 1)
    detail.scroll:SetScrollChild(detail.content)
    detail.text = detail.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    detail.text:SetPoint("TOPLEFT", 0, 0)
    detail.text:SetJustifyH("LEFT")
    detail.text:SetJustifyV("TOP")
    detail.text:SetWordWrap(true)
    detail.scroll:SetScript("OnSizeChanged", function() if current then relayout() end end)
    ns.AutoScrollBar(detail.scroll, function(has)
        scrollBar = has
        anchorScroll()
    end)

    detail.rewards = CreateFrame("Frame", nil, detail.content)
    detail.rewards:SetPoint("TOPLEFT", detail.text, "BOTTOMLEFT", 0, -16)
    detail.rewards:SetPoint("RIGHT", detail.content, "RIGHT", 0, 0)
    detail.rewards:SetHeight(1)
    detail.rewards.texts, detail.rewards.buttons = {}, {}

    -- item names the client didn't have yet: redraw when they arrive (batching the arrivals)
    local itemEvents = CreateFrame("Frame")
    itemEvents:RegisterEvent("GET_ITEM_INFO_RECEIVED")
    local pendingRepaint = false
    itemEvents:SetScript("OnEvent", function()
        if not (waitingItems and current and detail:IsShown()) or pendingRepaint then return end
        pendingRepaint = true
        C_Timer.After(0.2, function()
            pendingRepaint = false
            if current and detail:IsShown() then relayout() end
        end)
    end)

    -- Waypoint: a split button. The main part goes to the chosen step (the next one by default); the arrow
    -- opens the list of every step to pick another.
    detail.wayGroup = CreateFrame("Frame", nil, detail)
    detail.wayGroup:SetSize(WAY_W + 26, 22)
    detail.btnWay = CreateFrame("Button", nil, detail.wayGroup, "UIPanelButtonTemplate")
    detail.btnWay:SetSize(WAY_W, 22)
    detail.btnWay:SetPoint("LEFT", 0, 0)
    local wayText = detail.btnWay:GetFontString()
    if wayText then
        wayText:ClearAllPoints()
        wayText:SetPoint("LEFT", 8, 0)
        wayText:SetPoint("RIGHT", -8, 0)
        wayText:SetWordWrap(false)
    end
    detail.btnWay:SetScript("OnClick", function()
        local step = selectedStep()
        if not step then return end
        local loc = stepTarget(current, step)
        if loc then ns.SetWaypoint(loc, step.label) end
    end)
    detail.btnWayMenu = CreateFrame("Button", nil, detail.wayGroup, "UIPanelButtonTemplate")
    detail.btnWayMenu:SetSize(24, 22)
    detail.btnWayMenu:SetPoint("LEFT", detail.btnWay, "RIGHT", 2, 0)
    detail.btnWayMenu:SetText("v")
    detail.btnWayMenu:SetScript("OnClick", function(self)
        if not current then return end
        local options = {}
        for i, step in ipairs(detail.steps or {}) do
            local zone = stepZone(step)
            local target = stepTarget(current, step)
            options[i] = {
                name = (step.done and CHECK or "") .. step.label .. (step.progress and (" " .. step.progress) or "")
                    .. (zone and (" |cff999999(" .. zone .. ")|r") or ""),
                color = step.current and { 1, 0.82, 0 } or step.done and { 0.6, 0.8, 0.6 } or { 1, 1, 1 },
                disabled = target == nil,
            }
        end
        ns.PopupMenu(self, options, function(_, i)
            picked = { id = current.id, index = i }
            local step = detail.steps[i]
            local loc = stepTarget(current, step)
            if loc then ns.SetWaypoint(loc, step.label) end
            render()
        end, 300)
    end)

    detail.btnOpen = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
    detail.btnOpen:SetSize(130, 22)
    detail.btnOpen:SetText(L["Open quest"])
    detail.btnOpen:SetScript("OnClick", function()
        if current then openQuest(current.id) end
    end)

    -- "Focus": the floating window for this quest (Modules/UI/FocusWindow.lua); again to stop focusing
    detail.btnFocus = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
    detail.btnFocus:SetSize(130, 22)
    detail.btnFocus:SetScript("OnClick", function()
        if not current then return end
        ns.Focus_Toggle(current.id)
        render()
        ns.Search_Refresh()
    end)

    detail.btnChain = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
    detail.btnChain:SetSize(130, 22)
    detail.btnChain:SetText(L["View chain"])
    detail.btnChain:SetScript("OnClick", function()
        if current and current.entryId then ns.UI_OpenQuest(current.entryId, current.id) end
    end)

    -- "Show on map": the chosen step (inside an instance, its entrance)
    detail.btnMap = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
    detail.btnMap:SetSize(130, 22)
    detail.btnMap:SetText(L["Show on map"])
    detail.btnMap:SetScript("OnClick", function()
        local step = current and selectedStep()
        if step then ns.ShowStepOnMap(current, step) end
    end)

    -- the game's own confirmation (QuestMenu.lua)
    detail.btnAbandon = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
    detail.btnAbandon:SetSize(130, 22)
    detail.btnAbandon:SetText(L["Abandon quest"])
    detail.btnAbandon:SetScript("OnClick", function()
        if current then ns.AbandonQuest(current.id) end
    end)

    -- buttons at the bottom, in rows if they don't fit in one; the text ends right above them. The same
    -- options, in the same order, as the menu of a right click (QuestMenu.lua).
    local buttons = {
        { frame = detail.btnFocus, w = 130 }, { frame = detail.btnOpen, w = 130 },
        { frame = detail.wayGroup, w = WAY_W + 26 }, { frame = detail.btnMap, w = 130 },
        { frame = detail.btnChain, w = 130 }, { frame = detail.btnAbandon, w = 130 },
    }
    function detail.layoutButtons()
        local width = detail:GetWidth() - 16
        if width <= 0 then return end
        local h = ns.FlowLayout(detail, buttons, 8, 8, width, 6, 4, true, true)
        scrollBottom = 8 + h + 8
        anchorScroll()
    end
    detail:HookScript("OnSizeChanged", detail.layoutButtons)

    layout()
end

-- Opens the game's quest log on that quest (for quests the addon doesn't have in its data).
function ns.OpenQuestInLog(questID)
    return openQuest(questID)
end

function ns.Detail_Layout()
    -- only with the panel open: when closed, layout() would show the tree again (wrong with the search open)
    if detail and detail:IsShown() then layout() end
end

function ns.Detail_Show(q)
    current = q
    render()
    detail.scroll:SetVerticalScroll(0)
    detail:Show()
    layout()
end

function ns.Detail_Hide()
    current = nil
    if detail then
        detail:Hide()
        layout()
    end
end

function ns.Detail_Toggle(q)
    if current and current.id == q.id then
        ns.Detail_Hide()
    else
        ns.Detail_Show(q)
    end
end

function ns.Detail_Refresh()
    if current and detail and detail:IsShown() then render() end
end

function ns.Detail_Current()
    return current
end
