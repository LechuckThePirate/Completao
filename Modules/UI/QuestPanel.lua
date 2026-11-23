local _, ns = ...
local C_QuestLog = ns.QuestLog or C_QuestLog -- never the game's table directly (QuestLogCompat.lua)
local L = ns.L
local T = ns.Theme

local detail, parentFrame, treeScroll, current, leftOff, companion
-- the text's scroll bar only shows when the text doesn't fit; without it the text gets its room
local scrollBar, scrollBottom = false, 38
local PAGE_MARGIN = 30 -- the text keeps this far from the page's edges, clear of the burnt rim
local function anchorScroll()
    -- the parchment page ends above the action bar; the text keeps clear of its burnt edges
    detail.page:SetPoint("BOTTOMRIGHT", detail, "BOTTOMRIGHT", -6, scrollBottom)
    detail.scroll:SetPoint("BOTTOMRIGHT", detail.page, "BOTTOMRIGHT", -(scrollBar and PAGE_MARGIN + 16 or PAGE_MARGIN), PAGE_MARGIN - 4)
end
local maximized = false

-- Text on parchment: the colors meant for a dark background (gold, yellow, light green, greys...) become inks of
-- the same family, dark enough to read: whites in plain ink, greys in a soft brown ink, the section titles (gold) in
-- burnt sienna, and each hue in its deep ink.
local INKS = {
    heading = "7a3510", plain = "2b1a0b", soft = "5a3e22",
    red = "9b1c1c", orange = "8a4300", yellow = "6e5800", green = "1e6b1e", blue = "1f4e7a", purple = "6a2a80",
}
local HEADINGS = { d4af37 = true, ffd100 = true }
local function inkFor(hex)
    hex = hex:lower()
    if HEADINGS[hex] then return INKS.heading end
    local r, g, b = tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
    local hi, lo = math.max(r, g, b), math.min(r, g, b)
    if hi - lo < 0.16 then return hi > 0.75 and INKS.plain or INKS.soft end -- white or grey
    local h -- hue, in degrees
    if hi == r then h = ((g - b) / (hi - lo)) % 6
    elseif hi == g then h = (b - r) / (hi - lo) + 2
    else h = (r - g) / (hi - lo) + 4 end
    h = h * 60
    if h < 18 or h >= 335 then return INKS.red end
    if h < 42 then return INKS.orange end
    if h < 72 then return INKS.yellow end
    if h < 165 then return INKS.green end
    if h < 260 then return INKS.blue end
    return INKS.purple
end
local function inkify(s)
    return (s:gsub("|c(%x%x)(%x%x%x%x%x%x)", function(a, hex) return "|c" .. a .. inkFor(hex) end))
end
local function inkRGB(r, g, b)
    local hex = inkFor(("%02x%02x%02x"):format(math.floor(r * 255 + 0.5), math.floor(g * 255 + 0.5), math.floor(b * 255 + 0.5)))
    return tonumber(hex:sub(1, 2), 16) / 255, tonumber(hex:sub(3, 4), 16) / 255, tonumber(hex:sub(5, 6), 16) / 255
end

-- Where a quest starts or ends: who and in which zone, and, when the spot is known, a pin after it (a link in the
-- text: a click marks it on the map) instead of the coordinates. pinLinks holds the spots of the text on show.
local PIN = "|T" .. T.MEDIA .. "ActionIcons:16:16:0:-2:320:64:0:64:0:64|t"
local pinLinks = {}

local function pinLink(loc, label)
    if not (loc.x and loc.x > 0 and ns.CanShowMap(loc)) then return "" end
    pinLinks[#pinLinks + 1] = { loc = loc, label = label }
    return ("  |Hcompletao:pin:%d|h%s|h"):format(#pinLinks, PIN)
end

local function describeLocation(loc, label)
    local zone = loc.area and C_Map.GetAreaInfo(loc.area)
    local where = zone or (loc.x and loc.x > 0 and "?") or L["Inside the instance"]
    local text = loc.npc and (loc.npc .. " - " .. where) or where
    return text .. pinLink(loc, loc.npc or label)
end

-- The quest's steps (ns.QuestSteps, Modules/Quest) for the waypoint button, the map and the panel's list.
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
    pinLinks = {}
    local function section(title, body)
        parts[#parts + 1] = T.code("gold") .. title .. "|r\n" .. body
    end

    -- a quest the player must have done: its name is a link (with a chain icon) to its own chain, when the addon knows it
    local function questLink(id)
        local def = ns.FindQuestDef(id)
        local name = ns.QuestTitle(id, def and def.name)
        if not (def and def.entryId) then return name end
        return ("|Hcompletao:quest:%d|h%s %s|h"):format(id, name, T.ActionIconText("chain", 12))
    end

    local req = {}
    for _, id in ipairs(q.requires or {}) do
        local met = ns.IsQuestDone(id)
        -- not done: "Requires: <quest>" in red, so it is clear why the quest giver doesn't give it yet
        req[#req + 1] = met and ("|cff33cc33" .. questLink(id) .. "|r") or ("|cffff5555" .. L["Requires: "] .. questLink(id) .. "|r")
    end
    if q.requiresAny and #q.requiresAny > 0 then
        local names, met = {}, false
        for _, id in ipairs(q.requiresAny) do
            met = met or ns.IsQuestDone(id)
            names[#names + 1] = questLink(id)
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

    -- quests lost by doing another first: why this one was, or what to do first so none is
    local _, lost = ns.QuestStatus(q)
    local careful = ns.QuestLostTo(q) and lost or ns.QuestWarnings(q)
    if #careful > 0 then section(L["Careful"], "|cffff8c1a" .. table.concat(careful, "\n") .. "|r") end

    if q.objective then section(L["Objective"], q.objective) end
    if detail.steps and #detail.steps > 0 then section(L["Steps"], stepsText()) end
    if q.dungeon then
        local inside = ns.entries[q.dungeon]
        section(L["Instance"], (inside and ns.EntryName(inside) or "?") .. " -- " .. L["done inside the instance"])
    end
    if q.start then
        section(L["Starts"], describeLocation(q.start, L["Starts"]))
    else
        local body = L["Unknown location (it may start inside the instance, or it is not in the database yet)."]
        local entry = ns.entries[q.entryId]
        if entry and entry.entrance then
            body = body .. "\n" .. L["Instance entrance: %s"]:format(describeLocation(entry.entrance, L["Instance"]))
        end
        section(L["Starts"], body)
    end
    if q.finish then section(L["Ends"], describeLocation(q.finish, L["Ends"])) end
    if q.note then section(L["Notes"], q.note) end
    -- the long description, at the end: the story is read after the practical parts
    local desc = ns.QuestDescription(q)
    if desc then section(L["Description"], desc) end
    return table.concat(parts, "\n\n")
end

-- Rewards (Data/<Flavor>/Generated/Rewards.lua, ns.REWARDS): under the text, a block of text lines and item
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

-- The fixed rewards without the ones that are also among the choices: some quests come from the data with the
-- same items in both lists, and showing them twice ("choose one" and "you will also receive") makes no sense.
-- nil when nothing is left.
local function fixedItems(r)
    if not r.items then return nil end
    if not r.choice then return r.items end
    local choices = {}
    for _, entry in ipairs(r.choice) do choices[type(entry) == "table" and entry[1] or entry] = true end
    local list = {}
    for _, entry in ipairs(r.items) do
        if not choices[type(entry) == "table" and entry[1] or entry] then list[#list + 1] = entry end
    end
    return #list > 0 and list or nil
end

-- Rows of the block: { text = "..." } or { items = { id | { id, count } } }. nil when there are no rewards.
local function buildRewards(q)
    local r = ns.REWARDS and ns.REWARDS[q.id] or {}
    local rows = { { text = T.code("gold") .. (REWARDS or L["Rewards"]) .. "|r" } }
    if r.choice then
        rows[#rows + 1] = { text = REWARD_CHOICES or L["You will be able to choose one of these rewards:"] }
        rows[#rows + 1] = { items = r.choice }
    end
    local fixed = fixedItems(r)
    if fixed then
        rows[#rows + 1] = { text = r.choice and (REWARD_ITEMS or L["You will also receive:"])
            or (REWARD_ITEMS_ONLY or L["You will receive:"]) }
        rows[#rows + 1] = { items = fixed }
    end
    local lines = {}
    if r.money then lines[#lines + 1] = L["Money: %s"]:format(coinString(r.money)) end
    -- experience is always there, even when the quest gives none
    local xp = ns.QuestXP(q.id)
    lines[#lines + 1] = L["Experience: %s"]:format(BreakUpLargeNumbers and BreakUpLargeNumbers(xp) or xp)
    for _, rep in ipairs(r.rep or {}) do
        lines[#lines + 1] = L["Reputation: %s"]:format(("%+d %s"):format(rep[2], factionName(rep[1])))
    end
    rows[#rows + 1] = { text = table.concat(lines, "\n") }
    return rows
end

local function rewardText(i)
    local block = detail.rewards
    local fs = block.texts[i]
    if not fs then
        fs = T.Text(block, "body", "ink")
        fs:SetShadowOffset(0, 0)
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
        b.name = T.Text(b, "small")
        b.name:SetShadowOffset(0, 0)
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
    -- on parchment: the quality's color as ink (common and poor items in plain ink)
    if color and quality > 1 then b.name:SetTextColor(inkRGB(color.r, color.g, color.b)) else b.name:SetTextColor(T.rgba("ink")) end
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
            fs:SetText(inkify(row.text))
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
    -- a quest of a chain: a chain icon after its title, a link to that chain's tree
    local chained = q.entryId ~= nil and ns.IsInChain(q)
    detail.title:SetText(ns.QuestTitle(q.id, q.name) .. (chained and ("  |Hcompletao:chain|h" .. T.ActionIconText("chain", 18) .. "|h") or ""))
    detail.meta:SetTextColor(inkRGB(c[1], c[2], c[3])) -- the status says its color
    local meta = { ns.STATUS_LABELS[status] }
    local alt = status == "done" and not C_QuestLog.IsQuestFlaggedCompleted(q.id) and ns.DoneByAltsText(q.id)
    if alt then meta[1] = L["Completed by %s"]:format(alt) end
    if q.repeatable then meta[#meta + 1] = L["Repeatable"] end
    if q.level then meta[#meta + 1] = L["Level %d%s"]:format(q.level, q.minLevel and L[" (min %d)"]:format(q.minLevel) or "") end
    meta[#meta + 1] = "ID " .. q.id
    detail.meta:SetText(table.concat(meta, "   |   "))
    detail.steps, detail.currentStep = ns.QuestSteps(q)
    detail.rawText = buildText(q)
    detail.text:SetText(inkify(detail.rawText))
    rewardRows = buildRewards(q)
    relayout()
    local onQuest = C_QuestLog.IsOnQuest(q.id) and true or false
    -- every button is always there: the ones that don't apply to this quest are disabled, not hidden
    detail.btnOpen:SetEnabled(onQuest)
    detail.btnFocus:SetEnabled(onQuest)
    detail.btnAbandon:SetEnabled(onQuest)
    local focused = ns.Focus_Quest() == q.id
    detail.btnFocus:SetText(focused and L["Unfocus"] or L["Focus"])
    detail.btnFocus.tip = focused and L["Stop focus"] or L["Focus"]
    -- "View chain" goes to the quest's tree, when it is part of a chain
    detail.btnChain:SetEnabled(q.entryId ~= nil and ns.IsInChain(q))
    -- waypoint and map: the chosen step
    local step = selectedStep()
    local loc, isEntrance = nil, false
    if step then loc, isEntrance = stepTarget(q, step) end
    detail.btnWay.tip = step and L["Waypoint: %s"]:format(step.label) or L["Waypoint: start"]
    detail.btnWay:SetEnabled(loc ~= nil and ns.CanWaypoint(loc))
    detail.btnWayMenu:SetEnabled(detail.steps and #detail.steps > 0)
    detail.btnMap:SetEnabled(loc ~= nil and ns.CanShowMap(loc))
    detail.btnMap:SetText(isEntrance and L["Entrance"] or L["Map"])
    detail.btnMap.tip = isEntrance and L["Show entrance"] or L["Show on map"]
    detail.layoutButtons()
end

-- Maximize / restore: our own glyph button (arrows out, arrows in). Returns the function that shows the state.
local setMaxState

local function createMaxButton(parent, anchorTo, onToggle)
    local btn = T.CreateIconButton(parent, "expand", 18, function() return maximized and L["Restore"] or L["Maximize"] end)
    btn:SetPoint("RIGHT", anchorTo, "LEFT", -2, 0)
    btn:SetScript("OnClick", function() onToggle(not maximized) end)
    return function(isMax) T.SetGlyph(btn, isMax and "collapse" or "expand") end
end

-- The drawer: on the right of the main area, from under the header bar to the bottom, so the table or the tree
-- stays in sight beside it (they end at its left edge). Maximized, it takes the whole main area.
local DRAWER_W = 340
local function layout()
    local right = ns.TREE_RIGHT or 32 -- where the tree ends (its scroll bar takes room only when it shows)
    local shown = detail:IsShown()
    if not shown then maximized = false end
    local inset = shown and not maximized and (DRAWER_W + 8) or 0
    local top = ns.CONTENT_TOP or 56
    detail:ClearAllPoints()
    if maximized then
        detail:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", leftOff, -top)
        detail:SetPoint("BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT", -8, 8)
        treeScroll:Hide()
    else
        detail:SetPoint("TOPRIGHT", parentFrame, "TOPRIGHT", -8, -top)
        detail:SetPoint("BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT", -8, 8)
        detail:SetWidth(DRAWER_W)
        -- the tree only belongs to the tree view: under a table (search, log, tracked) it would show through it
        treeScroll:SetShown(not ns.UI_IsSearchMode() and not (ns.UI_IsListMode and ns.UI_IsListMode()))
        treeScroll:SetPoint("BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT", -(right + inset), 30)
    end
    -- the table (search, log, tracked) ends at the drawer too
    if companion then
        companion:SetPoint("BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT", -(8 + inset), 30)
    end
    if setMaxState then setMaxState(maximized) end
    if inset ~= (ns.DETAIL_INSET or 0) then
        ns.DETAIL_INSET = inset
        if ns.UI_DrawerChanged then ns.UI_DrawerChanged() end
    end
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
    T.Style(detail, "slate", "brass")
    detail:Hide()

    -- a dark strip on top: what the drawer is, maximize and close
    local heading = T.Text(detail, "heading", "gold")
    heading:SetPoint("TOPLEFT", 12, -9)
    heading:SetText(L["Quest details"])
    local close = T.CreateIconButton(detail, "close", 18, CLOSE or L["Close"])
    close:SetPoint("TOPRIGHT", -6, -6)
    close:SetScript("OnClick", function() ns.Detail_Hide(); ns.UI_Refresh() end)
    setMaxState = createMaxButton(detail, close, function(isMax)
        maximized = isMax
        layout()
    end)

    -- the page: parchment, written in ink
    detail.page = CreateFrame("Frame", nil, detail)
    detail.page:SetPoint("TOPLEFT", 6, -30)
    T.Parchment(detail.page, "BACKGROUND", 2, true)
    -- the chain icon after the title: a click opens the quest's chain
    detail.page:SetHyperlinksEnabled(true)
    detail.page:SetScript("OnHyperlinkClick", function(_, link)
        if link == "completao:chain" and current and current.entryId then ns.UI_OpenQuest(current.entryId, current.id) end
    end)
    detail.page:SetScript("OnHyperlinkEnter", function(self, link)
        if link ~= "completao:chain" then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetText(L["View chain"])
        GameTooltip:Show()
    end)
    detail.page:SetScript("OnHyperlinkLeave", GameTooltip_Hide)

    detail.title = T.Text(detail.page, "title", "ink")
    detail.title:SetShadowOffset(0, 0)
    detail.title:SetPoint("TOPLEFT", PAGE_MARGIN, -PAGE_MARGIN)
    detail.title:SetPoint("RIGHT", -PAGE_MARGIN, 0)
    detail.title:SetJustifyH("LEFT")
    detail.title:SetWordWrap(true)

    detail.meta = T.Text(detail.page, "small", "inkSoft")
    detail.meta:SetShadowOffset(0, 0)
    detail.meta:SetPoint("TOPLEFT", detail.title, "BOTTOMLEFT", 0, -4)
    detail.meta:SetPoint("RIGHT", -PAGE_MARGIN, 0)
    detail.meta:SetJustifyH("LEFT")

    local divider = detail.page:CreateTexture(nil, "ARTWORK")
    divider:SetHeight(1)
    divider:SetPoint("TOPLEFT", detail.meta, "BOTTOMLEFT", 0, -8)
    divider:SetPoint("RIGHT", -PAGE_MARGIN, 0)
    divider:SetColorTexture(T.rgba("inkMuted", 0.6))

    detail.scroll = CreateFrame("ScrollFrame", nil, detail.page, "UIPanelScrollFrameTemplate")
    detail.scroll:SetPoint("TOPLEFT", divider, "BOTTOMLEFT", 0, -8)
    anchorScroll()
    detail.content = CreateFrame("Frame", nil, detail.scroll)
    detail.content:SetSize(1, 1)
    detail.scroll:SetScrollChild(detail.content)
    detail.text = T.Text(detail.content, "body", "ink")
    detail.text:SetShadowOffset(0, 0)
    detail.text:SetPoint("TOPLEFT", 0, 0)
    detail.text:SetJustifyH("LEFT")
    detail.text:SetJustifyV("TOP")
    detail.text:SetWordWrap(true)
    if detail.text.SetSpacing then detail.text:SetSpacing(2) end
    -- the pins in the text (where it starts and ends): a click marks the spot on the map
    detail.content:SetHyperlinksEnabled(true)
    detail.content:SetScript("OnHyperlinkClick", function(_, link)
        local pin = pinLinks[tonumber(link:match("^completao:pin:(%d+)$") or 0)]
        if pin then ns.ShowOnMap(pin.loc, pin.label) return end
        -- a required quest: open it in its own tree, whichever zone or dungeon it is in
        local required = ns.FindQuestDef(tonumber(link:match("^completao:quest:(%d+)$") or 0))
        if required and required.entryId then ns.UI_OpenQuest(required.entryId, required.id) end
    end)
    detail.content:SetScript("OnHyperlinkEnter", function(self, link)
        local tip = link:find("^completao:pin:") and L["Show on map"] or link:find("^completao:quest:") and L["View chain"]
        if not tip then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:SetText(tip)
        GameTooltip:Show()
    end)
    detail.content:SetScript("OnHyperlinkLeave", GameTooltip_Hide)
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

    -- The action bar at the bottom, in two columns of plates with one word and an icon each (the whole action in the
    -- tooltip): on the left the wooden ones, what is done most (Focus, Waypoint, Chain); on the right the stone ones
    -- (Open, Map, Abandon). Waypoint is a split button: the plate goes to the chosen step (the next one by default),
    -- the arrow lists every step to pick another.
    local BTN_W, BTN_H = 159, 28
    detail.wayGroup = CreateFrame("Frame", nil, detail)
    detail.wayGroup:SetSize(BTN_W, BTN_H)
    detail.btnWay = T.CreatePlateButton(detail.wayGroup, L["Waypoint"], BTN_W - 28, BTN_H, "wood", "waypoint")
    detail.btnWay:SetPoint("LEFT", 0, 0)
    detail.btnWay:SetScript("OnClick", function()
        local step = selectedStep()
        if not step then return end
        local loc = stepTarget(current, step)
        if loc then ns.SetWaypoint(loc, step.label) end
    end)
    detail.btnWayMenu = T.CreatePlateButton(detail.wayGroup, nil, 26, BTN_H, "wood")
    detail.btnWayMenu.stepsMenu = true
    detail.btnWayMenu.tip = L["Choose the step"]
    detail.btnWayMenu:SetPoint("LEFT", detail.btnWay, "RIGHT", 2, 0)
    T.SetGlyph(detail.btnWayMenu, "chevronDown", "CENTER", 0, 0, "gold")
    detail.btnWayMenu:SetScript("OnClick", function(self)
        if not current then return end
        local options = {}
        for i, step in ipairs(detail.steps or {}) do
            local zone = stepZone(step)
            local target = stepTarget(current, step)
            options[i] = {
                name = (step.done and CHECK or "") .. step.label .. (step.progress and (" " .. step.progress) or "")
                    .. (zone and (" |cff999999(" .. zone .. ")|r") or ""),
                color = step.current and { T.rgba("gold") } or step.done and { T.rgba("ready") } or { T.rgba("text") },
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

    -- "Focus": the floating window for this quest (Modules/UI/FocusWindow.lua); again to stop focusing
    detail.btnFocus = T.CreatePlateButton(detail, L["Focus"], BTN_W, BTN_H, "wood", "focus")
    detail.btnFocus:SetScript("OnClick", function()
        if not current then return end
        ns.Focus_Toggle(current.id)
        render()
        ns.Search_Refresh()
    end)

    detail.btnChain = T.CreatePlateButton(detail, L["Chain"], BTN_W, BTN_H, "wood", "chain")
    detail.btnChain.tip = L["View chain"]
    detail.btnChain:SetScript("OnClick", function()
        if current and current.entryId then ns.UI_OpenQuest(current.entryId, current.id) end
    end)

    detail.btnOpen = T.CreatePlateButton(detail, L["Open"], BTN_W, BTN_H, "stone", "open")
    detail.btnOpen.tip = L["Open quest"]
    detail.btnOpen:SetScript("OnClick", function()
        if current then openQuest(current.id) end
    end)

    -- "Map": the chosen step (inside an instance, its entrance)
    detail.btnMap = T.CreatePlateButton(detail, L["Map"], BTN_W, BTN_H, "stone", "map")
    detail.btnMap:SetScript("OnClick", function()
        local step = current and selectedStep()
        if step then ns.ShowStepOnMap(current, step) end
    end)

    -- the game's own confirmation (QuestMenu.lua)
    detail.btnAbandon = T.CreatePlateButton(detail, L["Abandon"], BTN_W, BTN_H, "stone", "abandon")
    detail.btnAbandon.tip = L["Abandon quest"]
    detail.btnAbandon:SetScript("OnClick", function()
        if current then ns.AbandonQuest(current.id) end
    end)

    -- in rows of two (more if the drawer is maximized); the page ends right above them
    local buttons = {
        { frame = detail.btnFocus, w = BTN_W }, { frame = detail.btnOpen, w = BTN_W },
        { frame = detail.wayGroup, w = BTN_W }, { frame = detail.btnMap, w = BTN_W },
        { frame = detail.btnChain, w = BTN_W }, { frame = detail.btnAbandon, w = BTN_W },
    }
    function detail.layoutButtons()
        local width = detail:GetWidth() - 16
        if width <= 0 then return end
        local h = ns.FlowLayout(detail, buttons, 8, 8, width, 6, 5, true, true)
        scrollBottom = 8 + h + 6
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
