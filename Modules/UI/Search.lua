local _, ns = ...
local L = ns.L

-- Global search ("Search quests..." in the side panel): a form in the window's main area and the results
-- in a table below. It searches every section at once, among the quests meant for this character (class,
-- race and faction, as the tree). Options: title, include low-level, too-high and completed quests (off by
-- default), only quests with item rewards, and the reward's item type (the game's class and subclass,
-- e.g. Weapon > Wand). Clicking a result opens its tree with the quest selected (MainWindow.lua).
local ROW_H, ICON = 22, 18
local LEVEL_W, MONEY_W, DIST_W, MAX_ICONS, MIN_NAME_W = 44, 84, 60, 6, 150
local MAX_ROWS = 300

-- Table columns by width: the title keeps at least MIN_NAME_W; if it doesn't fit, "Where" narrows first,
-- then fewer reward icons are shown and last "Where" is dropped.
local STATUS_W = 20 -- the quest's status icon before its title (quest log and tracked views)
local cols = { width = 0 }
local function computeColumns(width, status)
    if cols.width == width and cols.status == status then return false end
    local gap = 6
    local icons, where = MAX_ICONS, math.max(90, math.min(170, math.floor(width * 0.28)))
    local function nameW() return width - 6 - status - LEVEL_W - DIST_W - MONEY_W - where - icons * (ICON + 2) - 5 * gap end
    if nameW() < MIN_NAME_W then where = math.max(90, where - (MIN_NAME_W - nameW())) end
    if nameW() < MIN_NAME_W then icons = 3 end
    if nameW() < MIN_NAME_W then where = 0 end
    cols.width, cols.icons, cols.where, cols.status = width, icons, where, status
    cols.gen = (cols.gen or 0) + 1
    cols.name = math.max(40, nameW())
    cols.nameX = 6 + status
    cols.levelX = cols.nameX + cols.name + gap
    cols.whereX = cols.levelX + LEVEL_W + gap
    cols.distX = cols.whereX + (where > 0 and (where + gap) or 0)
    cols.moneyX = cols.distX + DIST_W + gap
    cols.iconsX = cols.moneyX + MONEY_W + gap
    return true
end
local BACKDROP = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }

local panel
-- room the table's scroll bar takes (it only shows when the rows don't fit)
local barInset = 0
local state = {
    text = "", low = false, high = false, done = false, itemsOnly = false, class = nil, subclass = nil,
    sort = "level", desc = false, -- table order: "name" | "level" | "where" | "distance" | "money", by the header
}
local rows = {}

local function coinString(copper)
    local f = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
    return f and f(copper) or (copper .. "c")
end

-- An item's class and subclass, with their names in the client's language. This is "instant" client
-- information (the item doesn't need to be cached).
local itemClassCache = {}
local function itemClass(id)
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

local function rewardIds(r)
    local ids = {}
    for _, list in ipairs({ r.choice or {}, r.items or {} }) do
        for _, e in ipairs(list) do ids[#ids + 1] = type(e) == "table" and e[1] or e end
    end
    return ids
end

-- Reward types present in the data: { {id, name, subs = { {id, name} }} }, by name.
local rewardTypes
local function getRewardTypes()
    if rewardTypes then return rewardTypes end
    local byClass = {}
    for _, r in pairs(ns.REWARDS or {}) do
        for _, id in ipairs(rewardIds(r)) do
            local c = itemClass(id)
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

local function matchesReward(q)
    if not state.class then return true end
    local r = ns.REWARDS and ns.REWARDS[q.id]
    if not r then return false end
    for _, id in ipairs(rewardIds(r)) do
        local c = itemClass(id)
        if c and c.class == state.class and (not state.subclass or c.sub == state.subclass) then return true end
    end
    return false
end

-- View: "search" (form + results), "log" (the quests in the log, in the same table) or "tracked" (the ones
-- of them in the objective tracker).
local mode = "search"

local function isTracked(id)
    if C_QuestLog.GetQuestWatchType then return C_QuestLog.GetQuestWatchType(id) ~= nil end
    if C_QuestLog.IsQuestWatched then return C_QuestLog.IsQuestWatched(id) and true or false end
    return false
end

-- Quests in the log, with the zone (header) they are listed under. The ones the addon knows open in their
-- tree; the rest are listed anyway, with the log's title and level.
local function logQuests(trackedOnly)
    local found = {}
    local zone
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and info.isHeader then
            zone = info.title
        elseif info and info.questID and info.questID > 0 and (not trackedOnly or isTracked(info.questID)) then
            local def = ns.FindQuestDef(info.questID)
            if def then
                found[#found + 1] = { quest = def, entry = ns.entries[def.entryId], zone = zone }
            else
                found[#found + 1] = { quest = { id = info.questID, name = info.title or "?", level = info.level }, zone = zone }
            end
        end
    end
    return found
end

-- Every quest (once each, in the first entry where it shows up: dungeons, raids, zones...).
local function search()
    local found, seen = {}, {}
    local needle = state.text ~= "" and state.text or nil
    for _, d in ipairs(ns.entryList) do
        for _, q in ipairs(d.quests) do
            if not seen[q.id] and ns.QuestVisible(q, nil) then
                seen[q.id] = true
                local ok = true
                local onQuest = C_QuestLog.IsOnQuest(q.id)
                if not state.done and C_QuestLog.IsQuestFlaggedCompleted(q.id) then ok = false end
                if ok and not onQuest then
                    if not state.low and ns.IsLowLevel(q) then ok = false end
                    if ok and not state.high and ns.IsTooHigh(q) then ok = false end
                end
                if ok and needle then
                    local cached = C_QuestLog.GetTitleForQuestID(q.id)
                    ok = (cached and cached:lower():find(needle, 1, true)) or q.name:lower():find(needle, 1, true)
                    ok = ok and true or false
                end
                if ok and not matchesReward(q) then ok = false end
                if ok and state.itemsOnly then
                    local r = ns.REWARDS and ns.REWARDS[q.id]
                    ok = r ~= nil and #rewardIds(r) > 0
                end
                if ok then found[#found + 1] = { quest = q, entry = d } end
            end
        end
    end
    return found
end

-- Yards from the player to the quest's next step (nil when unknown), worked out once per result.
local function distanceOf(f)
    if not f.distDone then
        f.distDone = true
        if f.quest.steps or f.quest.start or f.quest.finish then
            local steps, current = ns.QuestSteps(f.quest)
            f.dist = steps[current] and ns.DistanceTo(steps[current].loc)
        end
    end
    return f.dist
end

-- table order (headers): by title (the one shown), level, zone, distance or money; ties by level and title
local function sortFound(found)
    local key = {}
    for _, f in ipairs(found) do
        local q = f.quest
        local r = ns.REWARDS and ns.REWARDS[q.id]
        f.title = (C_QuestLog.GetTitleForQuestID(q.id) or q.name):lower()
        f.level = q.level or q.minLevel or 0
        f.money = r and r.money or 0
        f.whereText = f.entry and ns.EntryName(f.entry) or f.zone or ""
        if state.sort == "distance" then
            key[f] = distanceOf(f) or false
        else
            key[f] = state.sort == "name" and f.title or state.sort == "money" and f.money
                or state.sort == "where" and f.whereText:lower() or f.level
        end
    end
    table.sort(found, function(a, b)
        if key[a] ~= key[b] then
            -- no distance (false): always after the ones that have it, whichever way it is sorted
            if not key[a] then return false end
            if not key[b] then return true end
            if state.desc then return key[a] > key[b] end
            return key[a] < key[b]
        end
        if a.level ~= b.level then return a.level < b.level end
        if a.title ~= b.title then return a.title < b.title end
        return a.quest.id < b.quest.id
    end)
    return found
end

local function openMenu(anchor, options, onPick) ns.PopupMenu(anchor, options, onPick, 170) end

local function makeDropdown(parent, width)
    local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(width, 22)
    local text = b:GetFontString()
    if text then text:SetPoint("LEFT", 8, 0); text:SetPoint("RIGHT", -18, 0); text:SetJustifyH("LEFT") end
    local arrow = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    arrow:SetPoint("RIGHT", -6, 0)
    arrow:SetText("v")
    return b
end

local function getRow(i)
    local row = rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, panel.content, "BackdropTemplate")
    row:SetHeight(ROW_H)
    row:SetBackdrop(BACKDROP)
    row:SetBackdropBorderColor(0, 0, 0, 0)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.status = row:CreateTexture(nil, "ARTWORK")
    row.status:SetSize(STATUS_W - 4, STATUS_W - 4)
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.level = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.level:SetWidth(LEVEL_W)
    row.level:SetJustifyH("CENTER")
    row.where = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.where:SetJustifyH("LEFT")
    row.where:SetWordWrap(false)
    row.dist = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.dist:SetWidth(DIST_W)
    row.dist:SetJustifyH("RIGHT")
    row.money = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.money:SetJustifyH("RIGHT")
    row.money:SetWordWrap(false)
    row.icons = {}
    for k = 1, MAX_ICONS do
        local icon = CreateFrame("Button", nil, row)
        icon:SetSize(ICON, ICON)
        icon.tex = icon:CreateTexture(nil, "ARTWORK")
        icon.tex:SetAllPoints()
        icon:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetItemByID(self.itemID)
            GameTooltip:Show()
        end)
        icon:SetScript("OnLeave", GameTooltip_Hide)
        icon:SetScript("OnClick", function(self)
            local f = (C_Item and C_Item.GetItemInfo) or GetItemInfo
            local link = f and select(2, f(self.itemID))
            if link and HandleModifiedItemClick then HandleModifiedItemClick(link) end
        end)
        row.icons[k] = icon
    end
    row:SetScript("OnClick", function(self)
        -- the quest's details open below the table; "View chain" there goes to its tree
        ns.Detail_Show(self.quest)
    end)
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:AddLine(ns.QuestTitle(self.quest.id, self.quest.name), 1, 1, 1)
        GameTooltip:AddLine(self.whereText, 0.8, 0.8, 0.8)
        if not self.entry then GameTooltip:AddLine(L["Not in Completao!!'s data."], 0.6, 0.6, 0.6) end
        GameTooltip:AddLine(L["Click to see its details."], 0.5, 0.8, 1)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    rows[i] = row
    return row
end

-- Places the columns of a row (or of the header) according to `cols`.
local function placeRow(row)
    row.name:ClearAllPoints()
    row.name:SetPoint("LEFT", row, "LEFT", cols.nameX, 0)
    row.name:SetWidth(cols.name)
    if row.status then
        row.status:ClearAllPoints()
        row.status:SetPoint("LEFT", row, "LEFT", 4, 0)
    end
    row.level:ClearAllPoints()
    row.level:SetPoint("LEFT", row, "LEFT", cols.levelX, 0)
    row.where:ClearAllPoints()
    row.where:SetPoint("LEFT", row, "LEFT", cols.whereX, 0)
    row.where:SetWidth(math.max(1, cols.where))
    row.where:SetShown(cols.where > 0)
    row.dist:ClearAllPoints()
    row.dist:SetPoint("LEFT", row, "LEFT", cols.distX, 0)
    row.money:ClearAllPoints()
    row.money:SetPoint("LEFT", row, "LEFT", cols.moneyX, 0)
    row.money:SetWidth(MONEY_W)
    if row.icons then
        for k, icon in ipairs(row.icons) do
            icon:ClearAllPoints()
            icon:SetPoint("LEFT", row, "LEFT", cols.iconsX + (k - 1) * (ICON + 2), 0)
        end
    elseif row.rewards then
        row.rewards:ClearAllPoints()
        row.rewards:SetPoint("LEFT", row, "LEFT", cols.iconsX, 0)
    end
end

-- Tracked view: under each quest, its steps (objectives with their progress and the turn-in). Clicking one
-- sets the waypoint (or opens the map on its zone when the spot isn't known).
local STEP_H = 18
local stepRows, stepsUsed = {}, 0

local function getStepRow()
    stepsUsed = stepsUsed + 1
    local row = stepRows[stepsUsed]
    if row then return row end
    row = CreateFrame("Button", nil, panel.content)
    row:SetHeight(STEP_H)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row:SetScript("OnClick", function(self)
        if not self.loc then return end
        if ns.CanWaypoint(self.loc) then
            ns.SetWaypoint(self.loc, self.title, self.tag)
            ns.Search_Refresh()
        else
            ns.ShowOnMap(self.loc, self.title)
        end
    end)
    row:SetScript("OnEnter", function(self)
        if not self.loc then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:AddLine(ns.CanWaypoint(self.loc) and L["Click to set the waypoint."] or L["Click to show it on the map."],
            0.5, 0.8, 1)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    -- the step the waypoint is set on: a gold tint and a bar on the left
    row.mark = row:CreateTexture(nil, "BACKGROUND")
    row.mark:SetAllPoints()
    row.mark:SetColorTexture(1, 0.82, 0, 0.18)
    row.markBar = row:CreateTexture(nil, "ARTWORK")
    row.markBar:SetPoint("TOPLEFT")
    row.markBar:SetPoint("BOTTOMLEFT")
    row.markBar:SetWidth(3)
    row.markBar:SetColorTexture(1, 0.82, 0, 1)
    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", 16, 0)
    row.text:SetPoint("RIGHT", -6, 0)
    row.text:SetJustifyH("LEFT")
    row.text:SetWordWrap(false)
    stepRows[stepsUsed] = row
    return row
end

local STEP_COLORS = { done = "ff808080", current = "ffffd100", todo = "ffffffff" }
local CHECK = "|TInterface\\RaidFrame\\ReadyCheck-Ready:14|t "

local function readyToTurnIn(quest)
    return C_QuestLog.IsOnQuest(quest.id) and ns.IsReadyToTurnIn(quest.id) and true or false
end

-- Status icon before a quest's title (quest log and tracked views): ready to turn in ("?") or in progress
-- ("..."), round like the game's. The atlases are tried in order; the classic gossip icons are the fallback.
local STATUS_ICONS = {
    ready = { atlas = { "QuestTurnin", "quest-turnin" }, file = "Interface\\GossipFrame\\ActiveQuestIcon" },
    progress = { atlas = { "QuestIncomplete", "quest-incomplete" }, file = "Interface\\GossipFrame\\IncompleteQuestIcon" },
}

local function setStatusIcon(tex, kind)
    local spec = kind and STATUS_ICONS[kind]
    if not spec then tex:Hide() return end
    local set
    if tex.SetAtlas and C_Texture and C_Texture.GetAtlasInfo then
        for _, name in ipairs(spec.atlas) do
            if C_Texture.GetAtlasInfo(name) then tex:SetAtlas(name) set = true break end
        end
    end
    if not set then tex:SetTexture(spec.file) end
    tex:Show()
end

-- Lays the quest's steps out from y down; returns the height used. A quest ready to turn in shows only the
-- turn-in; one still in progress shows its objectives and not the turn-in.
local function layoutSteps(quest, y)
    local steps = ns.QuestSteps(quest)
    local ready = readyToTurnIn(quest)
    local used = 0
    for index, s in ipairs(steps) do
        local wanted = ready and s.kind == "finish" or not ready and s.kind == "obj"
        if wanted then
            local row = getStepRow()
            row:ClearAllPoints()
            row:SetPoint("TOPLEFT", 0, -(y + used))
            row:SetPoint("RIGHT", panel.content, "RIGHT", 0, 0)
            local color = STEP_COLORS[s.done and "done" or s.current and "current" or "todo"]
            row.text:SetText(("%s|c%s%s%s|r"):format(s.done and CHECK or "", color, s.label,
                s.progress and ("  " .. s.progress) or ""))
            local loc = s.loc or (s.area and { area = s.area }) or nil
            row.loc, row.title = loc and ns.CanShowMap(loc) and loc or nil, s.label
            row.tag = quest.id .. ":" .. index
            local focused = ns.FocusTag() == row.tag
            row.mark:SetShown(focused)
            row.markBar:SetShown(focused)
            row:Show()
            used = used + STEP_H
        end
    end
    return used
end

local function refresh()
    if not (panel and panel:IsShown()) then return end
    stepsUsed = 0
    local found = sortFound(mode == "search" and search() or logQuests(mode == "tracked"))
    local shown = math.min(#found, MAX_ROWS)
    panel.count:SetText(#found > MAX_ROWS and L["%d quests (showing the first %d)"]:format(#found, MAX_ROWS)
        or L["%d quests"]:format(#found))
    local width = panel.scroll:GetWidth()
    if width and width > 0 then
        panel.content:SetWidth(width)
        if computeColumns(width, mode == "search" and 0 or STATUS_W) then
            placeRow(panel.head)
            for _, row in ipairs(rows) do row.placedFor = nil end
        end
    end
    local y = 0
    for i = 1, shown do
        local f = found[i]
        local q, row = f.quest, getRow(i)
        row.quest, row.entry = q, f.entry
        if row.placedFor ~= cols.gen and cols.width > 0 then
            placeRow(row)
            row.placedFor = cols.gen
        end
        setStatusIcon(row.status, mode ~= "search" and (readyToTurnIn(q) and "ready" or "progress") or nil)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -y)
        row:SetPoint("RIGHT", panel.content, "RIGHT", 0, 0)
        local shade = (i % 2 == 0) and 0.08 or 0.04
        row:SetBackdropColor(shade, shade, shade + 0.02, 0.9)
        -- the quest whose step has the waypoint: gold border
        local focusTag = ns.FocusTag()
        if focusTag and focusTag:find("^" .. q.id .. ":") then
            row:SetBackdropBorderColor(1, 0.82, 0, 1)
        else
            row:SetBackdropBorderColor(0, 0, 0, 0)
        end
        row.name:SetText(ns.QuestPrefix(q) .. ns.QuestTitle(q.id, q.name))
        row.name:SetTextColor(ns.QuestLevelColorRGB(q.level or q.minLevel))
        row.level:SetText(q.level or q.minLevel or "?")
        row.whereText = f.whereText
        row.where:SetText(row.whereText)
        row.dist:SetText(ns.FormatDistance(distanceOf(f)))
        local r = ns.REWARDS and ns.REWARDS[q.id]
        row.money:SetText(r and r.money and coinString(r.money) or "")
        local ids = r and rewardIds(r) or {}
        for k, icon in ipairs(row.icons) do
            local id = k <= (cols.icons or MAX_ICONS) and ids[k]
            if id then
                local c = itemClass(id)
                icon.itemID = id
                icon.tex:SetTexture(c and c.icon or 134400)
                icon:Show()
            else
                icon:Hide()
            end
        end
        row:Show()
        y = y + ROW_H
        if mode == "tracked" then y = y + layoutSteps(q, y) end
    end
    for i = shown + 1, #rows do rows[i]:Hide() end
    for i = stepsUsed + 1, #stepRows do stepRows[i]:Hide() end
    panel.content:SetHeight(math.max(1, y))
    panel.empty:SetShown(#found == 0)
end

local pending
local function requestRefresh()
    if pending then return end
    pending = true
    C_Timer.After(0.15, function()
        pending = false
        refresh()
    end)
end

local function updateDropdowns()
    local typeName, subName = L["Any"], L["Any"]
    for _, t in ipairs(getRewardTypes()) do
        if t.id == state.class then
            typeName = t.name
            for _, s in ipairs(t.subs) do
                if s.id == state.subclass then subName = s.name end
            end
        end
    end
    panel.typeButton:SetText(typeName)
    panel.subButton:SetText(subName)
    panel.subButton:SetEnabled(state.class ~= nil)
    -- with a reward type picked every quest already gives an item: the checkbox would change nothing
    local byType = state.class ~= nil
    panel.itemsOnly:SetEnabled(not byType)
    panel.itemsOnly.label:SetTextColor(byType and 0.5 or 1, byType and 0.5 or 0.82, byType and 0.5 or 0)
end

function ns.Search_Create(parent)
    panel = CreateFrame("Frame", nil, parent)
    panel:Hide()

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", 4, 0)
    title:SetText(L["Search quests"])
    panel.title = title

    local okSearch, box = pcall(CreateFrame, "EditBox", nil, panel, "SearchBoxTemplate")
    if not okSearch or not box then
        box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
        box:SetTextInsets(6, 6, 0, 0)
    end
    box:SetSize(240, 20)
    box:SetAutoFocus(false)
    local placeholder = box.Instructions
    if not placeholder then
        placeholder = box:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
        placeholder:SetPoint("LEFT", 8, 0)
    end
    placeholder:SetText(L["Quest title"])
    box:HookScript("OnTextChanged", function(self)
        state.text = strtrim(self:GetText() or ""):lower()
        if not box.Instructions then placeholder:SetShown(state.text == "") end
        requestRefresh()
    end)
    box:HookScript("OnEscapePressed", function(self) self:ClearFocus() end)
    panel.box = box

    -- "Include:" and its three checkboxes go together, in a group placed as a whole
    local include = CreateFrame("Frame", nil, panel)
    include:SetHeight(24)
    include.label = include:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    include.label:SetPoint("LEFT", 0, 0)
    include.label:SetText(L["Include:"])
    include.checks = {}
    for _, opt in ipairs({ { "low", L["Low level"] }, { "high", L["Too high"] }, { "done", L["Done"] } }) do
        local cb = CreateFrame("CheckButton", nil, include, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        local text = cb.Text or cb.text
        if not text then
            text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            text:SetPoint("LEFT", cb, "RIGHT", 0, 1)
        end
        text:SetText(opt[2])
        cb:SetChecked(state[opt[1]])
        cb:SetScript("OnClick", function(self)
            state[opt[1]] = self:GetChecked() and true or false
            requestRefresh()
        end)
        include.checks[#include.checks + 1] = { cb = cb, text = text }
    end
    local function includeWidth()
        local x = math.ceil(include.label:GetStringWidth()) + 4
        for _, c in ipairs(include.checks) do
            c.cb:ClearAllPoints()
            c.cb:SetPoint("LEFT", include, "LEFT", x, 0)
            x = x + 24 + math.ceil(c.text:GetStringWidth()) + 8
        end
        include:SetWidth(x)
        return x
    end

    -- only quests that give some item (fixed or to choose)
    local itemsOnly = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    itemsOnly:SetSize(24, 24)
    local itemsOnlyText = itemsOnly.Text or itemsOnly.text
    if not itemsOnlyText then
        itemsOnlyText = itemsOnly:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        itemsOnlyText:SetPoint("LEFT", itemsOnly, "RIGHT", 0, 1)
    end
    itemsOnlyText:SetText(L["Only quests with item rewards"])
    itemsOnly:SetScript("OnClick", function(self)
        state.itemsOnly = self:GetChecked() and true or false
        requestRefresh()
    end)
    itemsOnly:SetMotionScriptsWhileDisabled(true)
    itemsOnly:SetScript("OnEnter", function(self)
        if self:IsEnabled() then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(L["A reward type is selected: every result already gives an item."], 1, 1, 1, true)
        GameTooltip:Show()
    end)
    itemsOnly:SetScript("OnLeave", GameTooltip_Hide)
    itemsOnly.label = itemsOnlyText
    panel.itemsOnly = itemsOnly

    local rewardLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rewardLabel:SetText(L["Reward type:"])
    panel.typeButton = makeDropdown(panel, 150)
    panel.subButton = makeDropdown(panel, 150)

    -- form in rows by width; the table header goes under the last row
    local formItems = {
        { frame = box, w = 244, h = 24, dy = 2 },
        { frame = include, w = includeWidth, h = 24 },
        { frame = itemsOnly, w = ns.CheckWidth(itemsOnly, itemsOnlyText), h = 24 },
        { frame = rewardLabel, w = function() return math.ceil(rewardLabel:GetStringWidth()) + 4 end, h = 24, dy = 6 },
        { frame = panel.typeButton, w = 150, h = 24 },
        { frame = panel.subButton, w = 150, h = 24 },
    }
    local function layoutForm()
        local width = panel:GetWidth() - 8
        if width <= 0 then return end
        -- the log view has no form: the table starts under the title
        for _, it in ipairs(formItems) do it.frame:SetShown(mode == "search") end
        local h = mode == "search" and ns.FlowLayout(panel, formItems, 8, 28, width, 12, 6) or -12
        panel.count:ClearAllPoints()
        panel.count:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -(2 + barInset), -(28 + h + 6))
        panel.head:ClearAllPoints()
        panel.head:SetPoint("TOPLEFT", panel, "TOPLEFT", 0, -(28 + h + 22))
        panel.head:SetPoint("RIGHT", panel, "RIGHT", -barInset, 0)
    end
    panel.typeButton:SetScript("OnClick", function(self)
        local options = { { name = L["Any"] } }
        for _, t in ipairs(getRewardTypes()) do options[#options + 1] = t end
        openMenu(self, options, function(opt)
            state.class, state.subclass = opt.id, nil
            updateDropdowns()
            requestRefresh()
        end)
    end)
    panel.subButton:SetScript("OnClick", function(self)
        local options = { { name = L["Any"] } }
        for _, t in ipairs(getRewardTypes()) do
            if t.id == state.class then
                for _, s in ipairs(t.subs) do options[#options + 1] = s end
            end
        end
        openMenu(self, options, function(opt)
            state.subclass = opt.id
            updateDropdowns()
            requestRefresh()
        end)
    end)
    panel.count = panel:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")

    -- table header, with the same columns as the rows (placeRow)
    local head = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    head:SetHeight(20)
    head:SetBackdrop(BACKDROP)
    head:SetBackdropColor(0.12, 0.10, 0.02, 0.95)
    head:SetBackdropBorderColor(0.6, 0.5, 0.1, 1)
    -- sortable columns: a click sorts by them; another click reverses the order (arrow next to the name)
    local sortable = {}
    local function updateSortLabels()
        for sortKey, c in pairs(sortable) do
            local arrow = state.sort == sortKey and (state.desc and " v" or " ^") or ""
            c.fs:SetText(c.label .. arrow)
        end
    end
    local function column(text, justify, sortKey)
        local fs
        if sortKey then
            local b = CreateFrame("Button", nil, head)
            b:SetHeight(20)
            fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            fs:SetAllPoints()
            b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            b:SetScript("OnClick", function()
                if state.sort == sortKey then
                    state.desc = not state.desc
                else
                    state.sort, state.desc = sortKey, sortKey == "money" -- money, most first
                end
                ns.char.tableSort = { key = state.sort, desc = state.desc }
                updateSortLabels()
                requestRefresh()
            end)
            sortable[sortKey] = { fs = fs, label = text }
            fs:SetJustifyH(justify or "LEFT")
            fs:SetWordWrap(false)
            fs:SetText(text)
            return b
        end
        fs = head:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        fs:SetJustifyH(justify or "LEFT")
        fs:SetWordWrap(false)
        fs:SetText(text)
        return fs
    end
    head.name = column(L["Quest"], "LEFT", "name")
    head.level = column(L["Level"], "CENTER", "level")
    head.level:SetWidth(LEVEL_W)
    head.where = column(L["Where"], "LEFT", "where")
    head.dist = column(L["Distance"], "RIGHT", "distance")
    head.dist:SetWidth(DIST_W)
    head.money = column(L["Money"], "RIGHT", "money")
    head.rewards = column(L["Rewards"])
    panel.head = head
    -- the order the table was left in (per character)
    local saved = ns.char.tableSort
    if saved and sortable[saved.key] then state.sort, state.desc = saved.key, saved.desc and true or false end
    updateSortLabels()
    panel.layoutForm = layoutForm
    layoutForm()
    panel:SetScript("OnSizeChanged", function()
        layoutForm()
        requestRefresh()
    end)

    panel.scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    panel.scroll:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -2)
    panel.scroll:SetPoint("BOTTOMRIGHT", -barInset, 0)
    panel.content = CreateFrame("Frame", nil, panel.scroll)
    panel.content:SetSize(1, 1)
    panel.scroll:SetScrollChild(panel.content)
    panel.scroll:SetScript("OnSizeChanged", function() requestRefresh() end)
    ns.AutoScrollBar(panel.scroll, function(has)
        barInset = has and 24 or 0
        panel.scroll:SetPoint("BOTTOMRIGHT", -barInset, 0)
        panel.layoutForm()
    end)

    panel.empty = panel.content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    panel.empty:SetPoint("TOPLEFT", 8, -8)
    panel.empty:SetText(L["No quests match the search."])

    panel:SetScript("OnShow", function()
        updateDropdowns()
        refresh()
    end)
    panel:SetScript("OnHide", ns.PopupMenu_Hide)

    -- Live distances: while the table is visible, it is redrawn (and re-sorted) when the player has moved.
    local sinceCheck, lastPos = 0, nil
    panel:SetScript("OnUpdate", function(_, elapsed)
        sinceCheck = sinceCheck + elapsed
        if sinceCheck < 1 then return end
        sinceCheck = 0
        local map, x, y = ns.PlayerPosition()
        local pos = map and ("%d:%.4f:%.4f"):format(map, x, y) or false
        if pos ~= lastPos then
            lastPos = pos
            refresh()
        end
    end)
    return panel
end

function ns.Search_Refresh()
    requestRefresh()
end

local TITLES = { search = "Search quests", log = "Quest Log", tracked = "Tracked Quests" }
local EMPTY = { search = "No quests match the search.", log = "Your quest log is empty.",
    tracked = "No quests are being tracked." }

-- "search": the search; "log": the quests you carry in your log; "tracked": the ones being tracked.
function ns.Search_SetMode(m)
    mode = TITLES[m] and m or "search"
    if not panel then return end
    ns.PopupMenu_Hide()
    panel.title:SetText(L[TITLES[mode]])
    panel.empty:SetText(L[EMPTY[mode]])
    panel.layoutForm()
    requestRefresh()
end

function ns.Search_Mode()
    return mode
end

function ns.Search_Focus()
    if panel and panel.box and mode == "search" then panel.box:SetFocus() end
end
