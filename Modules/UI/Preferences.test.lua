dofile("setupTests.lua")

describe("Preferences", function()
    local ns, prefs

    before_each(function()
        WowMock.Reset()
        ns = OpenAddon("vc")
        ns.Prefs_Toggle()
        prefs = _G.CompletaoPreferencesFrame
    end)

    it("the first click on the gear opens it (no second click needed)", function()
        assert.is_true(prefs:IsShown())
        ns.Prefs_Toggle()
        assert.is_false(prefs:IsShown())
    end)

    it("the checkboxes reflect and change the settings", function()
        local checks = WowMock.FindAll(function(f) return f._kind == "CheckButton" and f._parent == prefs end)
        -- order: per character, minimap, messages, sync with the quest log, always open on the quest log,
        -- click-through in combat, click-through while moving, focus the nearest tracked quest after a turn-in, switch to a nearer one when the focused is ready
        assert.are.equal(9, #checks)
        assert.is_true(checks[1]:GetChecked())
        checks[3]:SetChecked(false); checks[3]:Click()
        assert.is_true(ns.char.quiet)
        checks[4]:SetChecked(true); checks[4]:Click()
        assert.is_true(ns.char.openWithQuestLog)
        checks[5]:SetChecked(true); checks[5]:Click()
        assert.is_true(ns.char.openOnQuestLog)
        checks[5]:SetChecked(false); checks[5]:Click()
        assert.is_nil(ns.char.openOnQuestLog)
        checks[6]:SetChecked(true); checks[6]:Click()
        assert.is_true(ns.char.clickThroughCombat)
        checks[7]:SetChecked(true); checks[7]:Click()
        assert.is_true(ns.char.clickThroughMoving)
        checks[8]:SetChecked(true); checks[8]:Click()
        assert.is_true(ns.char.focusAuto)
        checks[8]:SetChecked(false); checks[8]:Click()
        assert.is_nil(ns.char.focusAuto)
        checks[9]:SetChecked(true); checks[9]:Click()
        assert.is_true(ns.char.focusNext)
        checks[2]:SetChecked(false); checks[2]:Click()
        assert.is_false(ns.Minimap_IsShown())
    end)

    it("the opacity while moving comes from the slider", function()
        local slider = WowMock.Find(function(f) return f._kind == "Slider" end)
        slider._scripts.OnValueChanged(slider, 0.3)
        assert.are.equal(0.3, ns.char.fadeAlpha)
    end)

    it("switching to shared settings changes the text at the bottom", function()
        local checks = WowMock.FindAll(function(f) return f._kind == "CheckButton" and f._parent == prefs end)
        checks[1]:SetChecked(false); checks[1]:Click()
        assert.is_false(ns.IsPerCharacter())
        assert.is_not_nil(WowMock.FindByText("Settings are shared by all your characters."))
    end)

    it("reset zoom, filters and window", function()
        ns.char.zoom = 1.4
        ns.char.filters.hideLow = true
        ns.char.window = { point = "CENTER", w = 700, h = 500 }
        WowMock.FindButton("Reset zoom"):Click()
        WowMock.FindButton("Reset filters"):Click()
        WowMock.FindButton("Reset window position"):Click()
        assert.are.equal(1, ns.char.zoom)
        assert.is_nil(ns.char.filters.hideLow)
        assert.is_nil(ns.char.window)
    end)
end)
