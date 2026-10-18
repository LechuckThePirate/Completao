local _, ns = ...
local L = ns.L

-- Preferences window (opened with the main window's gear or with /completao prefs).
-- Basic settings, in ns.char: per character or shared by the account, depending on the first checkbox.
-- Two columns, related options together under a heading: general and the main window on the left; the quest
-- log, the focus window and the buttons on the right.
local COL_W = 290
local LEFT_X, RIGHT_X = 20, 20 + COL_W + 20
local WIDTH, HEIGHT = RIGHT_X + COL_W + 20, 500
local LABEL_W = COL_W - 28 - 8 -- a checkbox's text: from after the box to the column's right edge
local prefs

local function makeHeading(parent, x, y, text)
    local heading = parent:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    heading:SetPoint("TOPLEFT", x + 4, y)
    heading:SetText(text)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(1, 0.82, 0, 0.35)
    line:SetSize(COL_W - 4, 1)
    line:SetPoint("TOPLEFT", x + 4, y - 18)
end

local function makeSlider(parent, x, y, getValue, setValue, labelFor)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("TOPLEFT", x + 4, y)

    local slider = CreateFrame("Slider", nil, parent)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(COL_W - 24, 16)
    slider:SetPoint("TOPLEFT", x + 8, y - 24)
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

local function makeCheck(parent, x, y, text, getValue, setValue)
    local check = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    check:SetSize(24, 24)
    check:SetPoint("TOPLEFT", x, y)
    local label = parent:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    label:SetPoint("LEFT", check, "RIGHT", 4, 0)
    -- a long text (or a longer translation) wraps to a second line instead of running out of the window
    label:SetWidth(LABEL_W)
    label:SetJustifyH("LEFT")
    label:SetWordWrap(true)
    label:SetText(text)
    check:SetScript("OnClick", function(self) setValue(self:GetChecked() and true or false) end)
    function check.Refresh() check:SetChecked(getValue() and true or false) end
    return check
end

local function makeButton(parent, x, y, text, onClick)
    local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    button:SetSize(COL_W - 8, 24)
    button:SetPoint("TOPLEFT", x + 4, y)
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

    -- The widgets are made in this order (the tests count on it); where each one sits is its own x and y.
    local LX, RX = LEFT_X, RIGHT_X
    local STEP = 32 -- between checkboxes: room for a text that wraps to a second line

    makeHeading(prefs, LX, -44, L["General"])
    makeHeading(prefs, LX, -200, L["Main window"])
    makeHeading(prefs, RX, -44, L["Quest Log"])
    makeHeading(prefs, RX, -140, L["Focus"])

    -- As in Embolsao: decides where everything below is kept (Modules/Settings, ns.SetPerCharacter).
    widgets[#widgets + 1] = makeCheck(prefs, LX, -70, L["Character specific preferences"],
        function() return ns.IsPerCharacter() end,
        function(value)
            ns.SetPerCharacter(value)
            refreshAll()
        end)

    widgets[#widgets + 1] = makeSlider(prefs, LX, -226,
        function() return ns.char.windowAlpha or 1 end,
        function(value) ns.char.windowAlpha = value end,
        function(value) return L["Opacity: %d%%"]:format(math.floor(value * 100 + 0.5)) end)

    widgets[#widgets + 1] = makeSlider(prefs, LX, -274,
        function() return ns.char.fadeAlpha or 0.5 end,
        function(value) ns.char.fadeAlpha = value end,
        function(value) return L["Opacity while moving: %d%%"]:format(math.floor(value * 100 + 0.5)) end)

    widgets[#widgets + 1] = makeSlider(prefs, LX, -322,
        function() return ns.char.fadeAlphaCombat or 1 end,
        function(value) ns.char.fadeAlphaCombat = value end,
        function(value) return L["Opacity in combat: %d%%"]:format(math.floor(value * 100 + 0.5)) end)

    widgets[#widgets + 1] = makeCheck(prefs, LX, -70 - STEP, L["Show the minimap button"],
        function() return ns.Minimap_IsShown() end,
        function(value) ns.Minimap_SetShown(value) end)

    widgets[#widgets + 1] = makeCheck(prefs, LX, -70 - 2 * STEP, L["Show chat messages at startup"],
        function() return not ns.char.quiet end,
        function(value) ns.char.quiet = (not value) or nil end)

    widgets[#widgets + 1] = makeCheck(prefs, RX, -70, L["Sync with Blizzard Quest Log"],
        function() return ns.char.openWithQuestLog end,
        function(value) ns.char.openWithQuestLog = value or nil end)

    widgets[#widgets + 1] = makeCheck(prefs, RX, -70 - STEP, L["Always open on the Quest Log"],
        function() return ns.char.openOnQuestLog end,
        function(value) ns.char.openOnQuestLog = value or nil end)

    widgets[#widgets + 1] = makeCheck(prefs, LX, -372, L["Click-through in combat"],
        function() return ns.char.clickThroughCombat end,
        function(value) ns.char.clickThroughCombat = value or nil end)

    widgets[#widgets + 1] = makeCheck(prefs, LX, -372 - STEP, L["Click-through while moving"],
        function() return ns.char.clickThroughMoving end,
        function(value) ns.char.clickThroughMoving = value or nil end)

    widgets[#widgets + 1] = makeCheck(prefs, RX, -166, L["Autofocus tracked quests"],
        function() return ns.char.focusAuto end,
        function(value) ns.Focus_SetAuto(value) end)

    -- on unless switched off: saved as false, since nil means "never chosen"
    widgets[#widgets + 1] = makeCheck(prefs, RX, -166 - STEP, L["Follow Blizzard's quest tracker"],
        function() return ns.char.followBlizzardFocus ~= false end,
        function(value)
            ns.char.followBlizzardFocus = value
            if value then ns.Focus_FollowBlizzard() end
        end)

    widgets[#widgets + 1] = makeCheck(prefs, RX, -166 - 2 * STEP, L["Focusing here also sets Blizzard's quest tracker"],
        function() return ns.char.setBlizzardFocus ~= false end,
        function(value) ns.char.setBlizzardFocus = value end)

    widgets[#widgets + 1] = makeCheck(prefs, LX, -70 - 3 * STEP, L["Hide empty or completed categories"],
        function() return ns.char.hideDone end,
        function(value)
            ns.char.hideDone = value or nil
            ns.UI_Refresh()
        end)

    -- off unless ticked: the game's own tracker stays as it is by default
    widgets[#widgets + 1] = makeCheck(prefs, RX, -166 - 3 * STEP, L["Hide Blizzard's objective tracker"],
        function() return ns.char.hideBlizzardTracker end,
        function(value)
            ns.char.hideBlizzardTracker = value or nil
            ns.Tracker_Apply()
        end)

    -- off unless ticked: Tab is the player's own key by default
    widgets[#widgets + 1] = makeCheck(prefs, RX, -166 - 4 * STEP, L["Tab targets quest creatures and turn-in NPCs first"],
        function() return ns.char.tabTarget end,
        function(value)
            ns.char.tabTarget = value or nil
            ns.Focus_UpdateTargeting()
        end)

    makeButton(prefs, RX, -346, L["Reset window position"], function() ns.UI_ResetWindow() end)
    makeButton(prefs, RX, -376, L["Reset zoom"], function() ns.UI_SetZoom(1) end)
    makeButton(prefs, RX, -406, L["Reset filters"], function()
        ns.char.filters = {}
        ns.UI_SyncFilters()
    end)
    makeButton(prefs, RX, -440, L["What's new"], function() ns.Welcome_Show() end)

    prefs:SetScript("OnShow", refreshAll)
    prefs:Hide() -- frames are born shown: hidden until the first Prefs_Toggle (which would close it otherwise)
end

function ns.Prefs_Toggle()
    if not prefs then create() end
    prefs:SetShown(not prefs:IsShown())
end
