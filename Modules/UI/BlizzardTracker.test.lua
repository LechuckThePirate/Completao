dofile("setupTests.lua")

describe("BlizzardTracker", function()
    local tracker

    before_each(function()
        WowMock.Reset()
        -- the game's tracker: visible when the world is entered, as after a login or a /reload
        tracker = WowMock.NewFrame("Frame", "ObjectiveTrackerFrame")
    end)

    after_each(function()
        _G.ObjectiveTrackerFrame = nil
    end)

    it("leaves the tracker alone by default", function()
        StartAddon(LoadAddon(), nil, {})
        assert.is_true(tracker:IsShown())
    end)

    it("hides it on login when the option is on", function()
        StartAddon(LoadAddon(), nil, { hideBlizzardTracker = true })
        assert.is_false(tracker:IsShown())
    end)

    it("hides it again when the game shows it (a reload does)", function()
        StartAddon(LoadAddon(), nil, { hideBlizzardTracker = true })
        tracker:Show()
        assert.is_false(tracker:IsShown())
    end)

    it("hides it within the show itself, with no timer tick in between (no blink)", function()
        local original, queued = C_Timer.After, {}
        C_Timer.After = function(_, f) queued[#queued + 1] = f end
        StartAddon(LoadAddon(), nil, { hideBlizzardTracker = true })
        C_Timer.After = original
        assert.is_false(tracker:IsShown())
        tracker:Show()
        assert.is_false(tracker:IsShown())
    end)

    it("turning the option on and off hides it and gives it back", function()
        local ns = StartAddon(LoadAddon(), nil, {})
        ns.char.hideBlizzardTracker = true
        ns.Tracker_Apply()
        assert.is_false(tracker:IsShown())
        ns.char.hideBlizzardTracker = nil
        ns.Tracker_Apply()
        assert.is_true(tracker:IsShown())
        -- and the game's later shows are no longer undone
        tracker:Hide()
        tracker:Show()
        assert.is_true(tracker:IsShown())
    end)

    it("does not show a tracker it did not hide", function()
        local ns = StartAddon(LoadAddon(), nil, {})
        tracker:Hide() -- hidden by the player
        ns.char.hideBlizzardTracker = true
        ns.Tracker_Apply()
        ns.char.hideBlizzardTracker = nil
        ns.Tracker_Apply()
        assert.is_false(tracker:IsShown())
    end)

    it("copes with a client that has no such frame", function()
        _G.ObjectiveTrackerFrame = nil
        local ns = StartAddon(LoadAddon(), nil, { hideBlizzardTracker = true })
        assert.has_no.errors(function() ns.Tracker_Apply() end)
    end)

    it("is kept per character, or shared, like the other settings", function()
        local ns = StartAddon(LoadAddon(), nil, { hideBlizzardTracker = true })
        assert.is_false(tracker:IsShown())
        ns.SetPerCharacter(false) -- the shared store was seeded from this character's settings
        assert.is_true(ns.char.hideBlizzardTracker)
        assert.is_false(tracker:IsShown())
    end)
end)
