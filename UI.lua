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
local MIN_W, MIN_H, DEFAULT_W, DEFAULT_H = 640, 380, 940, 580

local selectedId, expandedCat, listInitialized
local headerButtons, listButtons, nodeButtons, lines = {}, {}, {}, {}
local frame, canvas, emptyText

local function showNodeTooltip(btn)
    local q, status, reasons = btn.quest, btn.status, btn.reasons
    GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
    GameTooltip:AddLine(ns.QuestTitle(q.id, q.name), 1, 1, 1)
    local c = STATUS_COLORS[status]
    GameTooltip:AddLine(STATUS_LABELS[status], c[1], c[2], c[3])
    if q.level then
        GameTooltip:AddLine(ns.L["Level %d%s"]:format(q.level, q.minLevel and ns.L[" (min %d)"]:format(q.minLevel) or ""), 0.8, 0.8, 0.8)
    end
    if q.giver then
        GameTooltip:AddLine(ns.L["Starts at: "] .. q.giver, 0.8, 0.8, 0.8)
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

-- Filtros del arbol: opciones guardadas por personaje (ns.char.filters) + texto de busqueda.
local HIGH_LEVEL_ALPHA, LOW_LEVEL_ALPHA = 0.5, 0.72
local searchText = ""
local searchBox

-- Cadenas de una entrada: cada grupo de quests conectadas por prerrequisitos.
-- Devuelve dos conjuntos por id de quest: las que estan en una cadena de mas de una quest (inChain) y las
-- que estan en una cadena con todas sus quests hechas (done; incluye las sueltas hechas).
local function chainInfo(d)
    local set, parent = {}, {}
    for _, q in ipairs(d.quests) do
        if ns.QuestVisible(q) then set[q.id] = q; parent[q.id] = q.id end
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
    local allDone, size = {}, {}
    for id in pairs(set) do
        local root = find(id)
        size[root] = (size[root] or 0) + 1
        if allDone[root] == nil then allDone[root] = true end
        if not C_QuestLog.IsQuestFlaggedCompleted(id) then allDone[root] = false end
    end
    local inChain, done = {}, {}
    for id in pairs(set) do
        local root = find(id)
        if size[root] > 1 then inChain[id] = true end
        if allDone[root] then done[id] = true end
    end
    return inChain, done
end

-- Predicado de visibilidad para el arbol de una entrada: faccion/raza + filtros del usuario.
-- Las quests de nivel alto o bajo que forman parte de una cadena sin completar se muestran siempre
-- (para no romperla), igual que las que llevas en el registro; solo se ocultan las sueltas.
local function makeFilter(d)
    local f = ns.char.filters
    local inChain, doneChain
    if f.hideLow or f.hideHigh or f.hideDone then inChain, doneChain = chainInfo(d) end
    local needle = searchText ~= "" and searchText or nil
    return function(q)
        if not ns.QuestVisible(q) then return false end
        local keep = C_QuestLog.IsOnQuest(q.id) or (inChain and inChain[q.id] and not doneChain[q.id])
        if f.hideLow and not keep and ns.IsLowLevel(q) then return false end
        if f.hideHigh and not keep and ns.IsTooHigh(q) then return false end
        if f.hideDone and doneChain[q.id] then return false end
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

    for _, b in ipairs(nodeButtons) do b:Hide() end
    for _, l in ipairs(lines) do l:Hide() end

    emptyText:SetShown(layout.count == 0)
    if layout.count == 0 then
        local hasData = false
        for _, q in ipairs(d.quests) do
            if ns.QuestVisible(q) then hasData = true break end
        end
        emptyText:SetText(hasData and ns.L["No quests match the filters."] or ns.L["No quest data yet."])
    end
    canvas:SetSize(
        math.max(1, PAD * 2 + layout.cols * NODE_W + (layout.cols - 1) * GAP_X),
        math.max(1, PAD * 2 + layout.rows * NODE_H + (layout.rows - 1) * GAP_Y))

    local byId, i = {}, 0
    for id, n in pairs(layout.nodes) do
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
        b.text:SetText(ns.QuestTitle(n.quest.id, n.quest.name))
        b.text:SetTextColor(status == "locked" and 0.65 or 1, status == "locked" and 0.65 or 1, status == "locked" and 0.65 or 1)
        -- translucidas las que no encajan con tu nivel (mas las muy altas que las de bajo nivel);
        -- las hechas y las que llevas en el registro se ven siempre nitidas
        local alpha = 1
        if status ~= "done" and status ~= "active" then
            if ns.IsTooHigh(n.quest) then alpha = HIGH_LEVEL_ALPHA
            elseif ns.IsLowLevel(n.quest) then alpha = LOW_LEVEL_ALPHA end
        end
        b:SetAlpha(alpha)
        b:Show()
        byId[id] = b
    end

    -- Las conexiones van por los huecos entre cuadros, nunca por encima de ellos: salen del padre hacia el
    -- pasillo vertical de su derecha, suben o bajan hasta el hueco entre filas junto al hijo, cruzan por
    -- ese hueco hasta el pasillo de la izquierda del hijo y entran por su lado izquierdo. Cada fila usa su
    -- propio carril dentro del pasillo, asi las lineas de un mismo padre (o hacia un mismo hijo) comparten tronco.
    local segCount = 0
    local function segment(x1, y1, x2, y2, c)
        if x1 == x2 and y1 == y2 then return end
        segCount = segCount + 1
        local l = getLine(segCount)
        l:SetColorTexture(c[1], c[2], c[3], 0.85)
        l:SetStartPoint("TOPLEFT", canvas, x1, -y1)
        l:SetEndPoint("TOPLEFT", canvas, x2, -y2)
        l:Show()
    end
    local function colX(col) return PAD + col * (NODE_W + GAP_X) end
    local function rowY(row) return PAD + row * (NODE_H + GAP_Y) end
    local function gutterX(col, row) -- pasillo a la derecha de la columna `col`, en el carril de `row`
        return colX(col) + NODE_W + GAP_X / 2 + ((row % 8) - 3.5) * 5
    end
    for _, e in ipairs(layout.edges) do
        local a, b = layout.nodes[e.from], layout.nodes[e.to]
        local c = STATUS_COLORS[byId[e.from].status == "done" and "done" or "locked"]
        local yA, yB = rowY(a.row) + NODE_H / 2, rowY(b.row) + NODE_H / 2
        local xA, xB = colX(a.col) + NODE_W, colX(b.col)
        if b.col <= a.col then
            segment(xA, yA, xB, yB, c) -- no deberia pasar (hijo a la izquierda o en la misma columna)
        else
            local gA = gutterX(a.col, a.row)
            if b.col == a.col + 1 then
                segment(xA, yA, gA, yA, c)
                segment(gA, yA, gA, yB, c)
                segment(gA, yB, xB, yB, c)
            else
                local gB = gutterX(b.col - 1, b.row)
                local yCh = rowY(b.row) - GAP_Y / 2 + ((a.col % 3) - 1) * 3 -- hueco entre filas, sobre el hijo
                segment(xA, yA, gA, yA, c)
                segment(gA, yA, gA, yCh, c)
                segment(gA, yCh, gB, yCh, c)
                segment(gB, yCh, gB, yB, c)
                segment(gB, yB, xB, yB, c)
            end
        end
    end
end

-- En zonas y clases solo salen las entradas que tienen alguna quest para este personaje
-- (facción y raza); las mazmorras y raids se listan siempre, aunque aun no tengan datos.
local HIDE_WHEN_EMPTY = { zones = true, classes = true }

local function entriesOf(catId)
    local items = {}
    for _, d in ipairs(ns.entryList) do
        if d.category == catId and (not HIDE_WHEN_EMPTY[catId] or select(2, ns.EntryProgress(d)) > 0) then
            items[#items + 1] = d
        end
    end
    return items
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

local function onHeaderClick(self)
    local catId = self.cat.id
    if expandedCat == catId then
        expandedCat = nil
    else
        expandedCat = catId
        local cur = ns.entries[selectedId]
        if not (cur and cur.category == catId) then
            local items = entriesOf(catId)
            selectEntry(items[1] and items[1].id or nil)
        end
    end
    ns.char.category = expandedCat or false
    ns.UI_Refresh()
end

local function onEntryClick(self)
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
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    b.text:SetPoint("LEFT", 8, 0)
    b:SetScript("OnClick", onHeaderClick)
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

local function refreshList()
    for _, b in ipairs(headerButtons) do b:Hide() end
    for _, b in ipairs(listButtons) do b:Hide() end

    local listW = LIST_W - 26
    local y, hi, ei = 0, 0, 0
    for _, cat in ipairs(ns.categories) do
        local items = entriesOf(cat.id)
        local open = cat.id == expandedCat

        hi = hi + 1
        local h = getHeaderButton(hi)
        h.cat = cat
        h:ClearAllPoints()
        h:SetPoint("TOPLEFT", 0, -y)
        h:SetWidth(listW)
        h.text:SetText(("%s %s (%d)"):format(open and "-" or "+", cat.name, #items))
        h:Show()
        y = y + HEADER_H + 2

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
                local sel = d.id == selectedId
                b:SetBackdropColor(sel and 0.15 or 0.05, sel and 0.25 or 0.05, sel and 0.4 or 0.05, 0.9)
                b:SetBackdropBorderColor(sel and 0.35 or 0.2, sel and 0.65 or 0.2, sel and 1 or 0.2, 1)
                b:Show()
                y = y + ENTRY_H + 2
            end
            y = y + 4
        end
    end
    frame.listChild:SetSize(listW, math.max(1, y))
end

function ns.UI_Refresh()
    if not frame then return end
    refreshList()
    local d = ns.entries[selectedId]
    frame.header:SetText(d and ns.EntryName(d) or "")
    renderTree(d or { quests = {} })
    ns.Detail_Refresh()
end

local function saveGeometry()
    local point, _, relPoint, x, y = frame:GetPoint()
    ns.char.window = { point = point, relPoint = relPoint, x = x, y = y, w = frame:GetWidth(), h = frame:GetHeight() }
end

local function createFrame()
    -- por nivel; en las clases, la del jugador va primero
    local playerClass = select(2, UnitClass("player"))
    local function rank(d) return d.classFile and d.classFile == playerClass and 0 or 1 end
    table.sort(ns.entryList, function(a, b)
        if rank(a) ~= rank(b) then return rank(a) < rank(b) end
        if a.minLevel ~= b.minLevel then return (a.minLevel or 0) < (b.minLevel or 0) end
        if a.maxLevel ~= b.maxLevel then return (a.maxLevel or 0) < (b.maxLevel or 0) end
        return a.name < b.name
    end)
    -- Marco con retrato (como Embolsao); si el cliente no tuviera la plantilla, el marco basico de antes.
    local okPortrait, portraitFrame = pcall(CreateFrame, "Frame", "CompletaoFrame", UIParent, "PortraitFrameFlatTemplate")
    local hasPortrait = okPortrait and portraitFrame and portraitFrame.SetPortraitToAsset ~= nil
    frame = okPortrait and portraitFrame or CreateFrame("Frame", "CompletaoFrame", UIParent, "BasicFrameTemplateWithInset")
    -- el contenido empieza por debajo del retrato (que sobresale por arriba a la izquierda)
    local top = hasPortrait and 66 or 34
    ns.TREE_TOP = top + 80
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

    frame.header = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    frame.header:SetPoint("TOPLEFT", LIST_W + 30, -top)

    -- Barra de filtros bajo el titulo: buscador por titulo y tres casillas.
    local toolbarLeft = LIST_W + 30
    local okSearch, box = pcall(CreateFrame, "EditBox", nil, frame, "SearchBoxTemplate")
    if not okSearch or not box then
        box = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
        box:SetTextInsets(6, 6, 0, 0)
    end
    searchBox = box
    box:SetSize(200, 20)
    box:SetPoint("TOPLEFT", toolbarLeft + 4, -(top + 26))
    box:SetAutoFocus(false)
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

    local function makeCheck(key, label, tip, x)
        local cb = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("TOPLEFT", toolbarLeft + x, -(top + 48))
        local text = cb.Text or cb.text
        if not text then
            text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            text:SetPoint("LEFT", cb, "RIGHT", 0, 1)
        end
        text:SetText(label)
        cb:SetChecked(ns.char.filters[key] and true or false)
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
        return x + 24 + text:GetStringWidth() + 10
    end
    local x = 0
    x = makeCheck("hideLow", ns.L["Hide low level"], ns.L["Hides quests that are grey for your level (trivial)."], x)
    x = makeCheck("hideHigh", ns.L["Hide too high"], ns.L["Hides quests that require a higher level than yours."], x)
    makeCheck("hideDone", ns.L["Hide completed"], ns.L["Hides the chains whose quests are all done."], x)

    local hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("BOTTOMRIGHT", -26, 12)
    hint:SetText(ns.L["Drag the background to pan  |  Wheel: vertical  |  Shift+wheel: horizontal"])

    local listScroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    listScroll:SetPoint("TOPLEFT", 12, -top)
    listScroll:SetPoint("BOTTOMLEFT", 12, 14)
    listScroll:SetWidth(LIST_W - 22)
    frame.listChild = CreateFrame("Frame", nil, listScroll)
    frame.listChild:SetSize(LIST_W - 26, 1)
    listScroll:SetScrollChild(frame.listChild)

    local treeScroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    treeScroll:SetPoint("TOPLEFT", LIST_W + 26, -ns.TREE_TOP)
    treeScroll:SetPoint("BOTTOMRIGHT", -32, 30)
    canvas = CreateFrame("Frame", nil, treeScroll)
    canvas:SetSize(1, 1)
    treeScroll:SetScrollChild(canvas)
    frame.treeScroll = treeScroll
    ns.Detail_Create(frame, treeScroll, LIST_W + 26)

    local function maxScroll(self)
        return math.max(0, canvas:GetWidth() - self:GetWidth()), math.max(0, canvas:GetHeight() - self:GetHeight())
    end
    local function scrollTo(self, x, y)
        local maxX, maxY = maxScroll(self)
        self:SetHorizontalScroll(math.max(0, math.min(x, maxX)))
        self:SetVerticalScroll(math.max(0, math.min(y, maxY)))
    end

    -- Rueda: vertical; si no hay recorrido vertical (o con Shift), horizontal.
    treeScroll:SetScript("OnMouseWheel", function(self, delta)
        local _, maxY = maxScroll(self)
        local x, y = self:GetHorizontalScroll(), self:GetVerticalScroll()
        if IsShiftKeyDown() or maxY == 0 then
            scrollTo(self, x - delta * 60, y)
        else
            scrollTo(self, x, y - delta * 60)
        end
    end)

    -- Arrastrar el fondo con el boton izquierdo para mover la vista.
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
            selectedId = ns.entryList[1] and ns.entryList[1].id
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
        ns.UI_Refresh()
    end)
    ns.UI = frame
end

function ns.UI_Toggle()
    if not frame then createFrame() end
    frame:SetShown(not frame:IsShown())
end
