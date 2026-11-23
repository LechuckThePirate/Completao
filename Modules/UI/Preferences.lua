local _, ns = ...
local L = ns.L
local T = ns.Theme

-- Preferences window (opened with the main window's gear or with /completao prefs).
-- Basic settings, in ns.char: per character or shared by the account, as "Profile / Data" says.
-- Four tabs: General, Interface & Opacity, Tracker & Waypoints and Profile / Data; the maintenance buttons (reset the
-- window, the zoom, the filters; what's new) are grouped at the foot, under every tab.
local WIDTH, HEIGHT = 600, 452
local PANEL_TOP, PANEL_H = 82, 268 -- where the tabs' pages start, and how tall they are
local X = 20                       -- the pages' left margin
local CONTENT_W = WIDTH - 2 * X
local LABEL_W = CONTENT_W - 28 - 8 -- a checkbox's text: from after the box to the page's right edge
local STEP = 32                    -- between checkboxes: room for a text that wraps to a second line
local prefs

local function makeHeading(parent, y, text)
    local heading = T.Text(parent, "heading", "gold", "ARTWORK")
    heading:SetPoint("TOPLEFT", X + 4, y)
    heading:SetText(text)
    local line = parent:CreateTexture(nil, "ARTWORK")
    line:SetColorTexture(T.rgba("brass"))
    line:SetSize(CONTENT_W - 4, 1)
    line:SetPoint("TOPLEFT", X + 4, y - 18)
end

-- A modern slider: a bar filled up to the value, a gold knob, its label (with the value) above.
local function makeSlider(parent, y, getValue, setValue, labelFor)
    local label = T.Text(parent, "body", "text", "ARTWORK")
    label:SetPoint("TOPLEFT", X + 4, y)

    local slider = CreateFrame("Slider", nil, parent)
    slider:SetOrientation("HORIZONTAL")
    slider:SetSize(CONTENT_W - 24, 16)
    slider:SetPoint("TOPLEFT", X + 8, y - 22)
    slider:SetMinMaxValues(0.1, 1.0)
    slider:SetValueStep(0.05)
    if slider.SetObeyStepOnDrag then slider:SetObeyStepOnDrag(true) end
    T.StyleSlider(slider)

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
    check:SetPoint("TOPLEFT", X, y)
    local label = T.Text(parent, "body", "text", "ARTWORK")
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

local function create()
    prefs = CreateFrame("Frame", "CompletaoPreferencesFrame", UIParent, "BackdropTemplate")
    prefs:SetSize(WIDTH, HEIGHT)
    prefs:SetPoint("CENTER")
    prefs:SetFrameStrata("DIALOG")
    prefs:SetClampedToScreen(true)
    T.Style(prefs, "slate", "brass")
    local art = prefs:CreateTexture(nil, "BACKGROUND", nil, 1)
    art:SetTexture(T.MEDIA .. "BgMain")
    art:SetAllPoints()
    art:SetAlpha(0.35)
    T.ApplyGoldBorder(prefs, 16, 3)
    prefs:SetMovable(true)
    prefs:EnableMouse(true)
    prefs:RegisterForDrag("LeftButton")
    prefs:SetScript("OnDragStart", prefs.StartMoving)
    prefs:SetScript("OnDragStop", prefs.StopMovingOrSizing)
    tinsert(UISpecialFrames, "CompletaoPreferencesFrame")

    local close = T.CreateIconButton(prefs, "close", 20, CLOSE or L["Close"])
    close:SetPoint("TOPRIGHT", -10, -10)
    close:SetScript("OnClick", function() prefs:Hide() end)

    local title = T.Text(prefs, "title", "gold", "ARTWORK")
    title:SetPoint("TOP", 0, -14)
    title:SetText(L["Completao!! Preferences"])

    -- the tabs, and a page under them for each
    local TABS = { L["General"], L["Interface & Opacity"], L["Tracker & Waypoints"], L["Profile / Data"] }
    local pages, tabs = {}, {}
    local tabW = (CONTENT_W - (#TABS - 1) * 4) / #TABS
    local function showTab(index)
        for i, page in ipairs(pages) do
            page:SetShown(i == index)
            local on = i == index
            T.Style(tabs[i], on and "card" or "obsidian", on and "gold" or "brass")
            tabs[i].text:SetTextColor(T.rgba(on and "gold" or "muted"))
            tabs[i].mark:SetShown(on)
        end
        prefs.tab = index
    end
    for i, name in ipairs(TABS) do
        local tab = CreateFrame("Button", nil, prefs, "BackdropTemplate")
        tab:SetSize(tabW, 26)
        tab:SetPoint("TOPLEFT", X + (i - 1) * (tabW + 4), -46)
        tab.text = T.Text(tab, "body")
        tab.text:SetPoint("CENTER")
        tab.text:SetText(name)
        tab.mark = tab:CreateTexture(nil, "ARTWORK")
        tab.mark:SetPoint("BOTTOMLEFT", 1, 1)
        tab.mark:SetPoint("BOTTOMRIGHT", -1, 1)
        tab.mark:SetHeight(2)
        tab.mark:SetColorTexture(T.rgba("gold"))
        tab:SetScript("OnClick", function() showTab(i) end)
        tabs[i] = tab
        local page = CreateFrame("Frame", nil, prefs)
        page:SetPoint("TOPLEFT", 0, -PANEL_TOP)
        page:SetSize(WIDTH, PANEL_H)
        pages[i] = page
    end
    local general, interface, tracker, profile = pages[1], pages[2], pages[3], pages[4]
    prefs.pages, prefs.tabs, prefs.ShowTab = pages, tabs, showTab

    local widgets = {}
    local note = T.Text(prefs, "small", "muted", "ARTWORK")
    note:SetPoint("BOTTOM", 0, 48)
    local function refreshAll()
        for _, widget in ipairs(widgets) do widget.Refresh() end
        note:SetText(ns.IsPerCharacter() and L["Settings are saved for this character only."]
            or L["Settings are shared by all your characters."])
    end

    -- The widgets are made in this order (the tests count on it); each goes on its tab's page, at its own y.
    makeHeading(general, -8, L["General"])
    makeHeading(general, -142, L["Quest Log"])
    makeHeading(interface, -8, L["Main window"])
    makeHeading(tracker, -8, L["Focus"])
    makeHeading(profile, -8, L["Profile / Data"])

    -- As in Embolsao: decides where everything below is kept (Modules/Settings, ns.SetPerCharacter).
    widgets[#widgets + 1] = makeCheck(profile, -34, L["Character specific preferences"],
        function() return ns.IsPerCharacter() end,
        function(value)
            ns.SetPerCharacter(value)
            refreshAll()
        end)

    widgets[#widgets + 1] = makeSlider(interface, -34,
        function() return ns.char.windowAlpha or 1 end,
        function(value) ns.char.windowAlpha = value end,
        function(value) return L["Opacity: %d%%"]:format(math.floor(value * 100 + 0.5)) end)

    widgets[#widgets + 1] = makeSlider(interface, -82,
        function() return ns.char.fadeAlpha or 0.5 end,
        function(value) ns.char.fadeAlpha = value end,
        function(value) return L["Opacity while moving: %d%%"]:format(math.floor(value * 100 + 0.5)) end)

    widgets[#widgets + 1] = makeSlider(interface, -130,
        function() return ns.char.fadeAlphaCombat or 1 end,
        function(value) ns.char.fadeAlphaCombat = value end,
        function(value) return L["Opacity in combat: %d%%"]:format(math.floor(value * 100 + 0.5)) end)

    widgets[#widgets + 1] = makeCheck(general, -34, L["Show the minimap button"],
        function() return ns.Minimap_IsShown() end,
        function(value) ns.Minimap_SetShown(value) end)

    widgets[#widgets + 1] = makeCheck(general, -34 - STEP, L["Show chat messages at startup"],
        function() return not ns.char.quiet end,
        function(value) ns.char.quiet = (not value) or nil end)

    widgets[#widgets + 1] = makeCheck(general, -168, L["Sync with Blizzard Quest Log"],
        function() return ns.char.openWithQuestLog end,
        function(value) ns.char.openWithQuestLog = value or nil end)

    widgets[#widgets + 1] = makeCheck(general, -168 - STEP, L["Always open on the Quest Log"],
        function() return ns.char.openOnQuestLog end,
        function(value) ns.char.openOnQuestLog = value or nil end)

    widgets[#widgets + 1] = makeCheck(interface, -186, L["Click-through in combat"],
        function() return ns.char.clickThroughCombat end,
        function(value) ns.char.clickThroughCombat = value or nil end)

    widgets[#widgets + 1] = makeCheck(interface, -186 - STEP, L["Click-through while moving"],
        function() return ns.char.clickThroughMoving end,
        function(value) ns.char.clickThroughMoving = value or nil end)

    widgets[#widgets + 1] = makeCheck(tracker, -34 - STEP, L["Autofocus tracked quests"],
        function() return ns.char.focusAuto end,
        function(value) ns.Focus_SetAuto(value) end)

    -- off unless ticked: the focus follows the player, switching quests by distance as they go
    widgets[#widgets + 1] = makeCheck(tracker, -34 - 2 * STEP, L["Live focus: switch to the nearest quest as you go"],
        function() return ns.char.focusLive end,
        function(value) ns.Focus_SetLive(value) end)

    -- on unless switched off: saved as false, since nil means "never chosen"
    widgets[#widgets + 1] = makeCheck(tracker, -34 - 3 * STEP, L["Follow Blizzard's quest tracker"],
        function() return ns.char.followBlizzardFocus ~= false end,
        function(value)
            ns.char.followBlizzardFocus = value
            if value then ns.Focus_FollowBlizzard() end
        end)

    widgets[#widgets + 1] = makeCheck(tracker, -34 - 4 * STEP, L["Focusing here also sets Blizzard's quest tracker"],
        function() return ns.char.setBlizzardFocus ~= false end,
        function(value) ns.char.setBlizzardFocus = value end)

    widgets[#widgets + 1] = makeCheck(general, -34 - 2 * STEP, L["Hide empty or completed categories"],
        function() return ns.char.hideDone end,
        function(value)
            ns.char.hideDone = value or nil
            ns.UI_Refresh()
        end)

    -- off unless ticked: the game's own tracker stays as it is by default
    widgets[#widgets + 1] = makeCheck(tracker, -34 - 5 * STEP, L["Hide Blizzard's objective tracker"],
        function() return ns.char.hideBlizzardTracker end,
        function(value)
            ns.char.hideBlizzardTracker = value or nil
            ns.Tracker_Apply()
        end)

    -- off unless ticked: Tab is the player's own key by default
    widgets[#widgets + 1] = makeCheck(tracker, -34 - 6 * STEP, L["Tab targets quest creatures and turn-in NPCs first"],
        function() return ns.char.tabTarget end,
        function(value)
            ns.char.tabTarget = value or nil
            ns.Focus_UpdateTargeting()
        end)

    -- on unless switched off: off, nothing pops up while questing (the focus window, waypoints, map markers)
    widgets[#widgets + 1] = makeCheck(tracker, -34, L["Quest helpers: focus window, waypoints and map markers"],
        function() return not ns.HelpersOff() end,
        function(value) ns.Focus_SetHelpers(value) end)

    -- Distance units: automatic by the server's region (meters outside the US, yards in it), or one forced. A drop-down at
    -- the foot of the General page; its text says the choice.
    do
        local UNITS = { { value = nil, name = L["Automatic"] }, { value = "m", name = L["Meters"] }, { value = "yd", name = L["Yards"] } }
        local unitButton = T.CreateGhostButton(general, nil, 260, 22)
        unitButton:SetPoint("TOPLEFT", X + 4, -236)
        local unitText = unitButton:GetFontString()
        if unitText then unitText:ClearAllPoints(); unitText:SetPoint("LEFT", 8, 0); unitText:SetPoint("RIGHT", -18, 0); unitText:SetJustifyH("LEFT") end
        T.SetGlyph(unitButton, "chevronDown", "RIGHT", -9, 0)
        local function label()
            local shown = L["Automatic"]
            for _, u in ipairs(UNITS) do
                if u.value == ns.char.distanceUnit then shown = u.name end
            end
            if not ns.char.distanceUnit then shown = shown .. " (" .. (ns.UseMetric() and L["Meters"] or L["Yards"]) .. ")" end
            return L["Distance units: %s"]:format(shown)
        end
        unitButton:SetScript("OnClick", function(self)
            local options = {}
            for i, u in ipairs(UNITS) do options[i] = { name = u.name } end
            ns.PopupMenu(self, options, function(_, i)
                ns.char.distanceUnit = UNITS[i].value
                self:SetText(label())
                ns.Focus_Refresh()
                ns.Search_Refresh()
            end, 260)
        end)
        widgets[#widgets + 1] = { Refresh = function() unitButton:SetText(label()) end }
        prefs.unitButton = unitButton
    end

    -- each view (the tree, the search, the quest log, the tracked quests, the ones to turn in) keeps its own filters; on,
    -- they are one for all of them. Off unless ticked.
    widgets[#widgets + 1] = makeCheck(profile, -34 - STEP, L["Same filters in every view"],
        function() return ns.char.sharedFilters end,
        function(value)
            ns.char.sharedFilters = value or nil
            ns.UI_FiltersChanged()
        end)

    -- the maintenance buttons, at the foot under every tab
    local footer = prefs:CreateTexture(nil, "ARTWORK")
    footer:SetColorTexture(T.rgba("brass"))
    footer:SetSize(CONTENT_W, 1)
    footer:SetPoint("BOTTOMLEFT", X, 70)
    local buttons = {
        { L["Reset window position"], function() ns.UI_ResetWindow() end },
        { L["Reset zoom"], function() ns.UI_SetZoom(1) end },
        { L["Reset filters"], function()
            ns.char.filters = {} -- every view's
            ns.char.viewFilters = nil
            ns.UI_SyncFilters()
        end },
        { L["What's new"], function() ns.Welcome_Show() end },
    }
    local buttonW = (CONTENT_W - (#buttons - 1) * 6) / #buttons
    for i, spec in ipairs(buttons) do
        local button = T.CreateGhostButton(prefs, spec[1], buttonW, 24)
        button:SetPoint("BOTTOMLEFT", X + (i - 1) * (buttonW + 6), 16)
        button:SetScript("OnClick", spec[2])
    end

    prefs:SetScript("OnShow", refreshAll)
    showTab(1)
    prefs:Hide() -- frames are born shown: hidden until the first Prefs_Toggle (which would close it otherwise)
end

function ns.Prefs_IsShown()
    return prefs ~= nil and prefs:IsShown()
end

function ns.Prefs_Toggle()
    if not prefs then create() end
    prefs:SetShown(not prefs:IsShown())
end
