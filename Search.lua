local _, ns = ...
local L = ns.L

-- Buscador global ("Buscar quests..." en la barra lateral): un formulario en el area principal de la ventana
-- y los resultados en una tabla debajo. Busca en todas las secciones a la vez, entre las quests que son para
-- este personaje (clase, raza y faccion, como el arbol). Opciones: titulo, incluir las de bajo nivel, las
-- demasiado altas y las completadas (por defecto no), y el tipo de objeto de recompensa (clase y subclase
-- del juego, p. ej. Arma > Varita). Pulsar un resultado abre su arbol con la quest elegida (UI.lua).
local ROW_H, ICON = 22, 18
local LEVEL_W, WHERE_W, ICONS_W = 44, 170, 6 * (ICON + 2)
local MAX_ROWS = 300
local BACKDROP = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }

local panel
local state = { text = "", low = false, high = false, done = false, class = nil, subclass = nil }
local rows = {}

-- Clase y subclase de un objeto, con sus nombres en el idioma del cliente. Es informacion "instantanea"
-- del cliente (no hace falta tener el objeto en cache).
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

-- Tipos de recompensa que existen en los datos: { {id, name, subs = { {id, name} }} }, por nombre.
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

-- Todas las quests (una vez cada una, en la primera entrada donde se ven: mazmorras, bandas, zonas...).
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
                if ok then found[#found + 1] = { quest = q, entry = d } end
            end
        end
    end
    table.sort(found, function(a, b)
        local la, lb = a.quest.level or a.quest.minLevel or 0, b.quest.level or b.quest.minLevel or 0
        if la ~= lb then return la < lb end
        return a.quest.name < b.quest.name
    end)
    return found
end

-- Desplegable propio (lista emergente de botones): no depende de los menus de Blizzard, que cambian
-- entre versiones del cliente.
local popup
local function openMenu(anchor, options, onPick)
    if not popup then
        popup = CreateFrame("Frame", nil, panel, "BackdropTemplate")
        popup:SetBackdrop(BACKDROP)
        popup:SetBackdropColor(0.05, 0.05, 0.08, 0.98)
        popup:SetBackdropBorderColor(0.6, 0.5, 0.1, 1)
        popup:SetFrameStrata("DIALOG")
        popup:EnableMouse(true)
        popup.buttons = {}
    end
    if popup:IsShown() and popup.anchor == anchor then popup:Hide() return end
    popup.anchor = anchor
    local perCol = 18
    local cols = math.max(1, math.ceil(#options / perCol))
    local colW = 170
    for i, opt in ipairs(options) do
        local b = popup.buttons[i]
        if not b then
            b = CreateFrame("Button", nil, popup)
            b:SetSize(colW - 8, 18)
            b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            b.text:SetPoint("LEFT", 4, 0)
            b.text:SetPoint("RIGHT", -4, 0)
            b.text:SetJustifyH("LEFT")
            b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            popup.buttons[i] = b
        end
        b.text:SetText(opt.name)
        b:SetScript("OnClick", function()
            popup:Hide()
            onPick(opt)
        end)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 4 + math.floor((i - 1) / perCol) * colW, -4 - ((i - 1) % perCol) * 18)
        b:Show()
    end
    for i = #options + 1, #popup.buttons do popup.buttons[i]:Hide() end
    popup:SetSize(cols * colW, 8 + math.min(#options, perCol) * 18)
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    popup:Show()
end

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

local function statusColor(q)
    local c = ns.STATUS_COLORS[ns.QuestStatus(q)]
    return c[1], c[2], c[3]
end

local function getRow(i)
    local row = rows[i]
    if row then return row end
    row = CreateFrame("Button", nil, panel.content, "BackdropTemplate")
    row:SetHeight(ROW_H)
    row:SetBackdrop(BACKDROP)
    row:SetBackdropBorderColor(0, 0, 0, 0)
    row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    row.name = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    row.name:SetPoint("LEFT", 6, 0)
    row.name:SetPoint("RIGHT", row, "RIGHT", -(ICONS_W + WHERE_W + LEVEL_W + 18), 0)
    row.name:SetJustifyH("LEFT")
    row.name:SetWordWrap(false)
    row.level = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.level:SetPoint("LEFT", row, "RIGHT", -(ICONS_W + WHERE_W + LEVEL_W + 12), 0)
    row.level:SetWidth(LEVEL_W)
    row.level:SetJustifyH("CENTER")
    row.where = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.where:SetPoint("LEFT", row, "RIGHT", -(ICONS_W + WHERE_W + 6), 0)
    row.where:SetWidth(WHERE_W)
    row.where:SetJustifyH("LEFT")
    row.where:SetWordWrap(false)
    row.icons = {}
    for k = 1, 6 do
        local icon = CreateFrame("Button", nil, row)
        icon:SetSize(ICON, ICON)
        icon:SetPoint("LEFT", row, "RIGHT", -ICONS_W + (k - 1) * (ICON + 2), 0)
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
        ns.UI_OpenQuest(self.entry.id, self.quest.id)
    end)
    row:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:AddLine(ns.QuestTitle(self.quest.id, self.quest.name), 1, 1, 1)
        GameTooltip:AddLine(ns.EntryName(self.entry), 0.8, 0.8, 0.8)
        GameTooltip:AddLine(L["Click to open it in its tree."], 0.5, 0.8, 1)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", GameTooltip_Hide)
    rows[i] = row
    return row
end

local function refresh()
    if not (panel and panel:IsShown()) then return end
    local found = search()
    local shown = math.min(#found, MAX_ROWS)
    panel.count:SetText(#found > MAX_ROWS and L["%d quests (showing the first %d)"]:format(#found, MAX_ROWS)
        or L["%d quests"]:format(#found))
    local width = panel.scroll:GetWidth()
    if width and width > 0 then panel.content:SetWidth(width) end
    for i = 1, shown do
        local f = found[i]
        local q, row = f.quest, getRow(i)
        row.quest, row.entry = q, f.entry
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", 0, -(i - 1) * ROW_H)
        row:SetPoint("RIGHT", panel.content, "RIGHT", 0, 0)
        local shade = (i % 2 == 0) and 0.08 or 0.04
        row:SetBackdropColor(shade, shade, shade + 0.02, 0.9)
        row.name:SetText(ns.QuestTitle(q.id, q.name))
        row.name:SetTextColor(statusColor(q))
        row.level:SetText(q.level or q.minLevel or "?")
        row.where:SetText(ns.EntryName(f.entry))
        local r = ns.REWARDS and ns.REWARDS[q.id]
        local ids = r and rewardIds(r) or {}
        for k, icon in ipairs(row.icons) do
            local id = ids[k]
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
    end
    for i = shown + 1, #rows do rows[i]:Hide() end
    panel.content:SetHeight(math.max(1, shown * ROW_H))
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
end

function ns.Search_Create(parent)
    panel = CreateFrame("Frame", nil, parent)
    panel:Hide()

    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    title:SetPoint("TOPLEFT", 4, 0)
    title:SetText(L["Search quests"])

    local okSearch, box = pcall(CreateFrame, "EditBox", nil, panel, "SearchBoxTemplate")
    if not okSearch or not box then
        box = CreateFrame("EditBox", nil, panel, "InputBoxTemplate")
        box:SetTextInsets(6, 6, 0, 0)
    end
    box:SetSize(240, 20)
    box:SetPoint("TOPLEFT", 8, -28)
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

    local include = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    include:SetPoint("LEFT", box, "RIGHT", 16, 0)
    include:SetText(L["Include:"])
    local x = include
    for _, opt in ipairs({ { "low", L["Low level"] }, { "high", L["Too high"] }, { "done", L["Done"] } }) do
        local cb = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        cb:SetPoint("LEFT", x, "RIGHT", x == include and 4 or 2, 0)
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
        x = text
    end

    local rewardLabel = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rewardLabel:SetPoint("TOPLEFT", 8, -62)
    rewardLabel:SetText(L["Reward type:"])
    panel.typeButton = makeDropdown(panel, 160)
    panel.typeButton:SetPoint("LEFT", rewardLabel, "RIGHT", 8, 0)
    panel.subButton = makeDropdown(panel, 160)
    panel.subButton:SetPoint("LEFT", panel.typeButton, "RIGHT", 6, 0)
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
    panel.count:SetPoint("TOPRIGHT", -4, -66)

    -- cabecera de la tabla, con las mismas columnas que las filas
    local head = CreateFrame("Frame", nil, panel, "BackdropTemplate")
    head:SetPoint("TOPLEFT", 0, -92)
    head:SetPoint("RIGHT", panel, "RIGHT", -24, 0)
    head:SetHeight(20)
    head:SetBackdrop(BACKDROP)
    head:SetBackdropColor(0.12, 0.10, 0.02, 0.95)
    head:SetBackdropBorderColor(0.6, 0.5, 0.1, 1)
    local function column(text, anchorX, width, justify)
        local fs = head:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        if anchorX then
            fs:SetPoint("LEFT", head, "RIGHT", anchorX, 0)
        else
            fs:SetPoint("LEFT", 6, 0)
        end
        if width then fs:SetWidth(width) end
        fs:SetJustifyH(justify or "LEFT")
        fs:SetText(text)
    end
    column(L["Quest"])
    column(L["Level"], -(ICONS_W + WHERE_W + LEVEL_W + 12), LEVEL_W, "CENTER")
    column(L["Where"], -(ICONS_W + WHERE_W + 6), WHERE_W)
    column(L["Rewards"], -ICONS_W, ICONS_W)

    panel.scroll = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
    panel.scroll:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -2)
    panel.scroll:SetPoint("BOTTOMRIGHT", -24, 0)
    panel.content = CreateFrame("Frame", nil, panel.scroll)
    panel.content:SetSize(1, 1)
    panel.scroll:SetScrollChild(panel.content)
    panel.scroll:SetScript("OnSizeChanged", function() requestRefresh() end)

    panel.empty = panel.content:CreateFontString(nil, "OVERLAY", "GameFontDisable")
    panel.empty:SetPoint("TOPLEFT", 8, -8)
    panel.empty:SetText(L["No quests match the search."])

    panel:SetScript("OnShow", function()
        updateDropdowns()
        refresh()
    end)
    panel:SetScript("OnHide", function() if popup then popup:Hide() end end)
    return panel
end

function ns.Search_Refresh()
    requestRefresh()
end

function ns.Search_Focus()
    if panel and panel.box then panel.box:SetFocus() end
end
