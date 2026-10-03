dofile("setupTests.lua")

describe("MinimapButton", function()
    local ns, button

    before_each(function()
        WowMock.Reset()
        ns = LoadAddon()
        StartAddon(ns)
        button = _G.CompletaoMinimapButton
    end)

    it("is created on entering, visible and at its default angle", function()
        assert.is_not_nil(button)
        assert.is_true(button:IsShown())
        assert.are.equal(225, ns.char.minimap.angle)
    end)

    it("a click opens and closes the window", function()
        button:Click()
        assert.is_true(ns.UI:IsShown())
        button:Click()
        assert.is_false(ns.UI:IsShown())
    end)

    it("a right click opens and closes the preferences, not the window", function()
        button:Click("RightButton")
        assert.is_true(_G.CompletaoPreferencesFrame:IsShown())
        assert.is_true(ns.UI == nil or not ns.UI:IsShown())
        button:Click("RightButton")
        assert.is_false(_G.CompletaoPreferencesFrame:IsShown())
    end)

    it("registers both buttons, and its tooltip explains the clicks and the drag", function()
        local lines = {}
        GameTooltip.AddLine = function(_, text) lines[#lines + 1] = text end
        button._scripts.OnEnter(button)
        assert.are.same({ "Left-click: open", "Right-click: preferences", "Drag: move" }, lines)
    end)

    it("dragging it changes its angle around the minimap", function()
        WowMock.cursor = { 200, 100 } -- right of the center (100, 100)
        button._scripts.OnDragStart(button)
        button._scripts.OnUpdate(button)
        button._scripts.OnDragStop(button)
        assert.near(0, ns.char.minimap.angle, 0.001)
    end)

    it("/completao minimap hides and shows it again, and it is remembered", function()
        SlashCmdList.COMPLETAO("minimap")
        assert.is_false(button:IsShown())
        assert.is_true(ns.char.minimap.hide)
        assert.matches("hidden", WowMock.printed[#WowMock.printed])
        SlashCmdList.COMPLETAO("minimap")
        assert.is_true(button:IsShown())
    end)
end)
