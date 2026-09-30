local _, ns = ...
local L = ns.L

-- Preferences window (opened with the main window's gear or with /completao prefs).
-- Basic settings, in ns.char: per character or shared by the account, depending on the first checkbox.
local WIDTH, HEIGHT = 340, 604
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
        value = math.floor(value * 20 + 0.5) / 20 -- in 5 % steps
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
    local note = prefs:CreateFontString(nil, "ARTWORK", "GameFontDisableSmall")
    note:SetPoint("BOTTOM", 0, 16)
    local function refreshAll()
        for _, widget in ipairs(widgets) do widget.Refresh() end
        note:SetText(ns.IsPerCharacter() and L["Settings are saved for this character only."]
            or L["Settings are shared by all your characters."])
    end

    -- As in Embolsao: decides where everything below is kept (Modules/Settings, ns.SetPerCharacter).
    widgets[#widgets + 1] = makeCheck(prefs, -48, L["Character specific preferences"],
        function() return ns.IsPerCharacter() end,
        function(value)
            ns.SetPerCharacter(value)
            refreshAll()
        end)

    widgets[#widgets + 1] = makeSlider(prefs, -84,
        function() return ns.char.fadeAlpha or 0.5 end,
        function(value) ns.char.fadeAlpha = value end,
        function(value) return L["Opacity while moving: %d%%"]:format(math.floor(value * 100 + 0.5)) end)

    widgets[#widgets + 1] = makeSlider(prefs, -136,
        function() return ns.char.fadeAlphaCombat or 1 end,
        function(value) ns.char.fadeAlphaCombat = value end,
        function(value) return L["Opacity in combat: %d%%"]:format(math.floor(value * 100 + 0.5)) end)

    widgets[#widgets + 1] = makeCheck(prefs, -188, L["Show the minimap button"],
        function() return ns.Minimap_IsShown() end,
        function(value) ns.Minimap_SetShown(value) end)

    widgets[#widgets + 1] = makeCheck(prefs, -216, L["Show chat messages at startup"],
        function() return not ns.char.quiet end,
        function(value) ns.char.quiet = (not value) or nil end)

    widgets[#widgets + 1] = makeCheck(prefs, -244, L["Sync with Blizzard Quest Log"],
        function() return ns.char.openWithQuestLog end,
        function(value) ns.char.openWithQuestLog = value or nil end)

    widgets[#widgets + 1] = makeCheck(prefs, -272, L["Always open on the Quest Log"],
        function() return ns.char.openOnQuestLog end,
        function(value) ns.char.openOnQuestLog = value or nil end)

    widgets[#widgets + 1] = makeCheck(prefs, -300, L["Click-through in combat"],
        function() return ns.char.clickThroughCombat end,
        function(value) ns.char.clickThroughCombat = value or nil end)

    widgets[#widgets + 1] = makeCheck(prefs, -328, L["Click-through while moving"],
        function() return ns.char.clickThroughMoving end,
        function(value) ns.char.clickThroughMoving = value or nil end)

    widgets[#widgets + 1] = makeCheck(prefs, -356, L["Focus the nearest tracked quest after a turn-in"],
        function() return ns.char.focusAuto end,
        function(value) ns.char.focusAuto = value or nil end)

    widgets[#widgets + 1] = makeCheck(prefs, -384, L["Switch to a nearer tracked quest when the focused one is ready"],
        function() return ns.char.focusNext end,
        function(value) ns.char.focusNext = value or nil end)

    makeButton(prefs, -436, L["Reset window position"], function() ns.UI_ResetWindow() end)
    makeButton(prefs, -466, L["Reset zoom"], function() ns.UI_SetZoom(1) end)
    makeButton(prefs, -496, L["Reset filters"], function()
        ns.char.filters = {}
        ns.UI_SyncFilters()
    end)
    makeButton(prefs, -530, L["What's new"], function() ns.Welcome_Show() end)

    prefs:SetScript("OnShow", refreshAll)
    prefs:Hide() -- frames are born shown: hidden until the first Prefs_Toggle (which would close it otherwise)
end

function ns.Prefs_Toggle()
    if not prefs then create() end
    prefs:SetShown(not prefs:IsShown())
end
