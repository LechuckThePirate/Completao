local _, ns = ...
local L = ns.L

local DETAIL_H = 210
local BACKDROP = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }

local detail, parentFrame, treeScroll, current, leftOff
local maximized = false

local function hex(c)
    return ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255)
end

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
    section(L["Requirements"], #req > 0 and table.concat(req, "\n") or L["None"])

    if q.objective then section(L["Objective"], q.objective) end
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
    -- la descripcion larga, al final: la historia se lee despues de lo practico
    local desc = ns.QuestDescription(q)
    if desc then section(L["Description"], desc) end
    return table.concat(parts, "\n\n")
end

-- Recompensas (Data/Generated/Rewards.lua, ns.REWARDS): debajo del texto, un bloque con lineas de texto
-- y botones de objeto (icono, cantidad, nombre del color de su calidad y el tooltip del juego). Los nombres
-- y colores los da el cliente por el id del objeto; si aun no los tiene, se piden y se repinta al llegar.
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

-- Filas del bloque: { text = "..." } o { items = { id | { id, cantidad } } }. nil si no hay recompensas.
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
        -- Shift+clic enlaza el objeto en el chat, Ctrl+clic lo prueba en el probador (como en el registro)
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
    b.icon:SetTexture(getItemIcon(id) or 134400) -- interrogacion si no hay icono
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

-- Coloca las filas para un ancho dado (objetos en columnas de ITEM_W) y devuelve el alto del bloque.
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

-- Abre el registro de misiones en esa quest. El cliente de Forever usa la interfaz moderna (registro
-- dentro del mapa); se prueban varias formas por orden y se usa la primera que funcione.
local function openQuest(questID)
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
        if ok and done then return true end
    end
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
    detail.text:SetText(buildText(q))
    rewardRows = buildRewards(q)
    relayout()
    detail.btnStart:SetEnabled(q.start ~= nil and ns.CanWaypoint(q.start))
    detail.btnFinish:SetEnabled(q.finish ~= nil and ns.CanWaypoint(q.finish))
    local onQuest = C_QuestLog.IsOnQuest(q.id) and true or false
    detail.btnOpen:SetShown(onQuest)
    -- "Ver en el mapa": donde se coge; si no se sabe, la entrada de la instancia.
    local entry = ns.entries[q.entryId]
    local mapLoc, isEntrance
    if q.start and ns.CanShowMap(q.start) then
        mapLoc = q.start
    elseif entry and entry.entrance and ns.CanShowMap(entry.entrance) then
        mapLoc, isEntrance = entry.entrance, true
    end
    detail.mapLoc, detail.mapIsEntrance = mapLoc, isEntrance
    local canMap = not onQuest and status ~= "done"
    detail.btnMap:SetShown(canMap)
    detail.btnMap:SetEnabled(canMap and mapLoc ~= nil)
    detail.btnMap:SetText(isEntrance and L["Show entrance"] or L["Show on map"])
end

-- Icono dibujado con lineas (sin depender de texturas del cliente): un cuadro con una flecha
-- diagonal. Maximizar: flecha del centro hacia la esquina superior izquierda. Restaurar: al reves.
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

-- Widget maximizar/restaurar. Preferido: el oficial de Blizzard (el del mapa y el registro de
-- misiones, flecha dorada sobre boton rojo). Alternativas: botones con los mismos atlas, y por
-- ultimo el icono de lineas. Devuelve una funcion que sincroniza el estado mostrado.
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

-- Panel abajo (con el arbol encima) o maximizado ocupando todo el area del arbol.
local function layout()
    local shown = detail:IsShown()
    if not shown then maximized = false end
    detail:ClearAllPoints()
    if maximized then
        detail:SetPoint("TOPLEFT", parentFrame, "TOPLEFT", leftOff, -(ns.TREE_TOP or 62))
        detail:SetPoint("BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT", -32, 30)
        treeScroll:Hide()
    else
        detail:SetPoint("BOTTOMLEFT", parentFrame, "BOTTOMLEFT", leftOff, 30)
        detail:SetPoint("BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT", -32, 30)
        detail:SetHeight(DETAIL_H)
        treeScroll:Show()
        treeScroll:SetPoint("BOTTOMRIGHT", parentFrame, "BOTTOMRIGHT", -32, shown and (30 + DETAIL_H + 8) or 30)
    end
    if setMaxState then setMaxState(maximized) end
end

function ns.Detail_Create(parent, tree, leftOffset)
    parentFrame, treeScroll, leftOff = parent, tree, leftOffset
    detail = CreateFrame("Frame", nil, parent, "BackdropTemplate")
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
    detail.scroll:SetPoint("BOTTOMRIGHT", -28, 38)
    detail.content = CreateFrame("Frame", nil, detail.scroll)
    detail.content:SetSize(1, 1)
    detail.scroll:SetScrollChild(detail.content)
    detail.text = detail.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    detail.text:SetPoint("TOPLEFT", 0, 0)
    detail.text:SetJustifyH("LEFT")
    detail.text:SetJustifyV("TOP")
    detail.text:SetWordWrap(true)
    detail.scroll:SetScript("OnSizeChanged", function() if current then relayout() end end)

    detail.rewards = CreateFrame("Frame", nil, detail.content)
    detail.rewards:SetPoint("TOPLEFT", detail.text, "BOTTOMLEFT", 0, -16)
    detail.rewards:SetPoint("RIGHT", detail.content, "RIGHT", 0, 0)
    detail.rewards:SetHeight(1)
    detail.rewards.texts, detail.rewards.buttons = {}, {}

    -- nombres de objetos que el cliente aun no tenia: se repinta cuando llegan (agrupando las llegadas)
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

    detail.btnStart = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
    detail.btnStart:SetSize(170, 22)
    detail.btnStart:SetPoint("BOTTOMLEFT", 8, 8)
    detail.btnStart:SetText(L["Waypoint: start"])
    detail.btnStart:SetScript("OnClick", function()
        if current and current.start then ns.SetWaypoint(current.start, current.start.npc or ns.QuestTitle(current.id, current.name)) end
    end)

    detail.btnFinish = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
    detail.btnFinish:SetSize(170, 22)
    detail.btnFinish:SetPoint("LEFT", detail.btnStart, "RIGHT", 6, 0)
    detail.btnFinish:SetText(L["Waypoint: turn-in"])
    detail.btnFinish:SetScript("OnClick", function()
        if current and current.finish then ns.SetWaypoint(current.finish, current.finish.npc or ns.QuestTitle(current.id, current.name)) end
    end)

    detail.btnOpen = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
    detail.btnOpen:SetSize(130, 22)
    detail.btnOpen:SetPoint("LEFT", detail.btnFinish, "RIGHT", 6, 0)
    detail.btnOpen:SetText(L["Open quest"])
    detail.btnOpen:SetScript("OnClick", function()
        if current then openQuest(current.id) end
    end)

    detail.btnMap = CreateFrame("Button", nil, detail, "UIPanelButtonTemplate")
    detail.btnMap:SetSize(130, 22)
    detail.btnMap:SetPoint("LEFT", detail.btnFinish, "RIGHT", 6, 0)
    detail.btnMap:SetText(L["Show on map"])
    detail.btnMap:SetScript("OnClick", function()
        if not (current and detail.mapLoc) then return end
        local title
        if detail.mapIsEntrance then
            local e = ns.entries[current.entryId]
            title = (e and e.name or "") .. " - " .. L["Entrance"]
        else
            title = current.start.npc or ns.QuestTitle(current.id, current.name)
        end
        ns.ShowOnMap(detail.mapLoc, title)
    end)

    layout()
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
