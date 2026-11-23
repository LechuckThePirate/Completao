local _, ns = ...

-- A "Filters" drop-down: a button that opens a list with a checkbox for each filter and, while any is on, "Clear
-- filters" at its top; the button counts the ones that are on ("Filters (2)"). Our own frames, not the game's menus
-- (they differ between the clients); a click anywhere else closes it. Used by the tree's toolbar and the search.
--
-- spec = { options = { { key =, label =, tip = (optional) }, ... }, get = function(key), set = function(key, on),
--          onChange = function() (after a change by the player),
--          footer = function(menu) (optional: makes a frame of its own, sized, shown under the checkboxes),
--          footerActive = function() (how many filters it has on), clearFooter = function() (Clear filters) }
-- Returns the button, with .menu, .clear, .checks[key] (the CheckButtons, with .label) and :Update() (call it when
-- the values change elsewhere).
function ns.FilterMenu(parent, spec)
    local T = ns.Theme
    local button = T.CreateGhostButton(parent, nil, 110, 22)
    local label = button:GetFontString()
    if label then
        label:ClearAllPoints()
        label:SetPoint("LEFT", 8, 0)
        label:SetPoint("RIGHT", -18, 0)
        label:SetJustifyH("LEFT")
    end
    T.SetGlyph(button, "chevronDown", "RIGHT", -9, 0)

    local menu = CreateFrame("Frame", nil, button, BackdropTemplateMixin and "BackdropTemplate" or nil)
    menu:SetFrameStrata("DIALOG")
    menu:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
    if menu.SetBackdrop then
        T.Style(menu, "slate", "brass")
    end
    menu:Hide()
    button.menu = menu
    button:SetScript("OnClick", function() menu:SetShown(not menu:IsShown()) end)
    if pcall(menu.RegisterEvent, menu, "GLOBAL_MOUSE_DOWN") then
        menu:SetScript("OnEvent", function(self)
            if self:IsShown() and not self:IsMouseOver() and not button:IsMouseOver()
                and not (ns.PopupMenu_IsMouseOver and ns.PopupMenu_IsMouseOver()) then -- a pick in a menu opened from it
                self:Hide()
            end
        end)
    end

    local clear = CreateFrame("Button", nil, menu)
    clear:SetHeight(20)
    clear:SetPoint("TOPLEFT", 8, -6)
    clear:SetPoint("RIGHT", -8, 0)
    clear:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
    clear:GetHighlightTexture():SetVertexColor(1, 1, 1, 0.06)
    clear.text = T.Text(clear, "small", "gold")
    clear.text:SetPoint("LEFT", 4, 0)
    clear.text:SetText(ns.L["Clear filters"])
    button.clear = clear

    local footer = spec.footer and spec.footer(menu)
    button.footer = footer
    button.checks = {}
    function button.Update()
        local active = 0
        for _, opt in ipairs(spec.options) do
            local on = spec.get(opt.key) and true or false
            button.checks[opt.key]:SetChecked(on)
            if on then active = active + 1 end
        end
        if spec.footerActive then active = active + spec.footerActive() end
        button:SetText(active > 0 and ns.L["Filters (%d)"]:format(active) or ns.L["Filters"])
        clear:SetShown(active > 0)
        local y, width = active > 0 and -28 or -6, 140
        for _, opt in ipairs(spec.options) do
            local cb = button.checks[opt.key]
            cb:ClearAllPoints()
            cb:SetPoint("TOPLEFT", 6, y)
            y = y - 24
            width = math.max(width, cb.width() + 16)
        end
        if footer then
            footer:ClearAllPoints()
            footer:SetPoint("TOPLEFT", 8, y - 4)
            y = y - 4 - footer:GetHeight()
            width = math.max(width, footer:GetWidth() + 16)
        end
        menu:SetSize(width, -y + 6)
    end

    clear:SetScript("OnClick", function()
        for _, opt in ipairs(spec.options) do spec.set(opt.key, false) end
        if spec.clearFooter then spec.clearFooter() end
        button.Update()
        spec.onChange()
    end)

    for _, opt in ipairs(spec.options) do
        local cb = CreateFrame("CheckButton", nil, menu, "UICheckButtonTemplate")
        cb:SetSize(24, 24)
        local text = cb.Text or cb.text
        if not text then
            text = cb:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            text:SetPoint("LEFT", cb, "RIGHT", 0, 1)
        end
        text:SetText(opt.label)
        cb.label = text
        cb.width = ns.CheckWidth(cb, text)
        button.checks[opt.key] = cb
        cb:SetScript("OnClick", function(self)
            spec.set(opt.key, self:GetChecked() and true or false)
            button.Update()
            spec.onChange()
        end)
        if opt.tip then
            cb:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(opt.label)
                GameTooltip:AddLine(opt.tip, 1, 1, 1, true)
                GameTooltip:Show()
            end)
            cb:SetScript("OnLeave", GameTooltip_Hide)
        end
    end
    button.Update()
    return button
end

-- A line of small text that says which filters are being applied ("Filters: Hide low level, Hide completed"), for under
-- the search box and the "Filters" button: the button only counts them, and some are on by default. A click on it opens
-- the drop-down. :Set(parts) takes the texts of the filters in force and returns whether there are any (hidden if not).
function ns.FilterSummary(parent, filtersButton)
    local T = ns.Theme
    local line = CreateFrame("Button", nil, parent)
    line:SetHeight(14)
    line.text = T.Text(line, "small", "muted")
    line.text:SetPoint("LEFT", 0, 0)
    line.text:SetPoint("RIGHT", 0, 0)
    line.text:SetJustifyH("LEFT")
    line.text:SetWordWrap(false)
    -- the filters in force now (Filters.lua): the line of every view says the same
    function line.Refresh() return line.Set(ns.FilterParts()) end
    function line.Set(parts)
        if #parts == 0 then
            line:Hide()
            return false
        end
        line.text:SetText(ns.L["Filters"] .. ": " .. table.concat(parts, "  |  "))
        line:Show()
        return true
    end
    line:SetScript("OnClick", function()
        local click = filtersButton:GetScript("OnClick")
        if click then click(filtersButton) end
    end)
    line:SetScript("OnEnter", function(self) self.text:SetTextColor(T.rgba("gold")) end)
    line:SetScript("OnLeave", function(self) self.text:SetTextColor(T.rgba("muted")) end)
    return line
end
