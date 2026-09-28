local ADDON, ns = ...
local L = ns.L

-- Ventana de preferencias (se abre con el engranaje de la ventana principal o con /completao prefs).
-- Ajustes basicos; todos se guardan por personaje (ns.char).
local WIDTH, HEIGHT = 340, 310
local prefs

local function makeSlider(parent, y, getValue, setValue, labelFor)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("TOPLEFT", 24, y)

    local slider = CreateFrame("Slider", nil, parent)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(280, 16)
    slider:SetPoint("TOPLEFT", 28, y - 24)
    slider:SetMinMaxValues(0.1, 1.0)
    slider:SetValueStep(0.05)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    local bar = slider:CreateTexture(nil, "BACKGROUND")
    bar:SetPoint("LEFT", 0, 0)
    bar:SetPoint("RIGHT", 0, 0)
    bar:SetHeight(4)
    bar:SetColorTexture(1, 1, 1, 0.25)
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    slider:GetThumbTexture():SetSize(20, 20)

    local refreshing = false
    slider:SetScript("OnValueChanged", function(_, value)
        value = math.floor(value * 20 + 0.5) / 20 -- de 5 en 5 %
        label:SetText(labelFor(value))
        if not refreshing then setValue(value) end
    end)
    function slider.Refresh()
        refreshing = true
        local value = getValue()
        slider:SetValue(value)
        label:SetText(labelFor(value))
        refreshing = false
    end
    return slider
end

local function makeCheck(parent, y, text, getValue, setValue)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("TOPLEFT", 20, y)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", check, "RIGHT", 4, 0)
    label:SetText(text)
    check:SetScript("OnClick", function(self) setValue(self:GetChecked() and true or false) end)
    function check.Refresh() check:SetChecked(getValue() and true or false) end
    return check
end

local function makeButton(parent, y, text, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(292, 24)
    button:SetPoint("TOPLEFT", 24, y)
    button:SetText(text)
    button:SetScript("OnClick", onClick)
    return button
end

local function create()
    prefs = CreateFrame("Frame", "CompletaoPreferencesFrame", UIParent, "BackdropTemplate")
    prefs:SetSize(WIDTH, HEIGHT)
    prefs:SetPoint("CENTER")
    prefs:SetFrameStrata("DIALOG")
    prefs:SetClampedToScreen(true)
    prefs:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    prefs:SetBackdropColor(0, 0, 0, 0.9)
    prefs:SetMovable(true)
    prefs:EnableMouse(true)
    prefs:RegisterForDrag("LeftButton")
    prefs:SetScript("OnDragStart", prefs.StartMoving)
    prefs:SetScript("OnDragStop", prefs.StopMovingOrSizing)
    tinsert(UISpecialFrames, "CompletaoPreferencesFrame")

    local okClose, close = pcall(CreateFrame, "Button", nil, prefs, "UIPanelCloseButtonDefaultAnchors")
    if not okClose or not close then
        close = CreateFrame("Button", nil, prefs, "UIPanelCloseButton")
    end
    close:SetPoint("TOPRIGHT", -2, -2)

    local title = prefs:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -16)
    title:SetText(L["Completao!! Preferences"])

    local widgets = {}

    widgets[#widgets + 1] = makeSlider(prefs, -52,
        function() return ns.char.fadeAlpha or 0.5 end,
        function(value) ns.char.fadeAlpha = value end,
        function(value) return L["Opacity while moving: %d%%"]:format(math.floor(value * 100 + 0.5)) end)

    widgets[#widgets + 1] = makeCheck(prefs, -104, L["Show the minimap button"],
        function() return ns.Minimap_IsShown() end,
        function(value) ns.Minimap_SetShown(value) end)

    widgets[#widgets + 1] = makeCheck(prefs, -132, L["Show chat messages at startup"],
        function() return not ns.char.quiet end,
        function(value) ns.char.quiet = (not value) or nil end)

    makeButton(prefs, -176, L["Reset window position"], function() ns.UI_ResetWindow() end)
    makeButton(prefs, -206, L["Reset zoom"], function() ns.UI_SetZoom(1) end)
    makeButton(prefs, -236, L["Reset filters"], function()
        ns.char.filters = {}
        ns.UI_SyncFilters()
    end)

    local note = prefs:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    note:SetPoint("BOTTOM", 0, 16)
    note:SetText(L["Settings are saved per character."])

    prefs:SetScript("OnShow", function()
        for _, widget in ipairs(widgets) do widget.Refresh() end
    end)
end

function ns.Prefs_Toggle()
    if not prefs then create() end
    prefs:SetShown(not prefs:IsShown())
end
