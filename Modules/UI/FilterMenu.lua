local _, ns = ...

-- A "Filters" drop-down: a button that opens a list with a checkbox for each filter and, while any is on, "Clear
-- filters" at its top; the button counts the ones that are on ("Filters (2)"). Our own frames, not the game's menus
-- (they differ between the clients); a click anywhere else closes it. Used by the tree's toolbar and the search.
--
-- spec = { options = { { key =, label =, tip = (optional) }, ... }, get = function(key), set = function(key, on),
--          onChange = function() (after a change by the player) }
-- Returns the button, with .menu, .clear, .checks[key] (the CheckButtons, with .label) and :Update() (call it when
-- the values change elsewhere).
function ns.FilterMenu(parent, spec)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(110, 22)
    local arrow = button:CreateTexture(nil, "OVERLAY")
    arrow:SetTexture("Interface\\Buttons\\Arrow-Down-Up")
    arrow:SetSize(10, 10)
    arrow:SetPoint("RIGHT", -8, -2)

    local menu = CreateFrame("Frame", nil, button, BackdropTemplateMixin and "BackdropTemplate" or nil)
    menu:SetFrameStrata("DIALOG")
    menu:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -2)
    if menu.SetBackdrop then
        menu:SetBackdrop({ bgFile = "Interface\\Tooltips\\UI-Tooltip-Background", edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 14, insets = { left = 4, right = 4, top = 4, bottom = 4 } })
        menu:SetBackdropColor(0.06, 0.06, 0.08, 0.97)
    end
    menu:Hide()
    button.menu = menu
    button:SetScript("OnClick", function() menu:SetShown(not menu:IsShown()) end)
    if pcall(menu.RegisterEvent, menu, "GLOBAL_MOUSE_DOWN") then
        menu:SetScript("OnEvent", function(self)
            if self:IsShown() and not self:IsMouseOver() and not button:IsMouseOver() then self:Hide() end
        end)
    end

    local clear = CreateFrame("Button", nil, menu)
    clear:SetHeight(20)
    clear:SetPoint("TOPLEFT", 8, -6)
    clear:SetPoint("RIGHT", -8, 0)
    clear:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    clear.text = clear:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    clear.text:SetPoint("LEFT", 4, 0)
    clear.text:SetText(ns.L["Clear filters"])
    button.clear = clear

    button.checks = {}
    function button.Update()
        local active = 0
        for _, opt in ipairs(spec.options) do
            local on = spec.get(opt.key) and true or false
            button.checks[opt.key]:SetChecked(on)
            if on then active = active + 1 end
        end
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
        menu:SetSize(width, -y + 6)
    end

    clear:SetScript("OnClick", function()
        for _, opt in ipairs(spec.options) do spec.set(opt.key, false) end
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
