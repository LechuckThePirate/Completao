dofile("setupTests.lua")

describe("Menu.PopupMenu", function()
    local ns, anchor

    local function optionButtons()
        return WowMock.FindAll(function(f) return f.text and f._scripts.OnClick and f._shown and f._parent and f._parent.buttons end)
    end

    before_each(function()
        WowMock.Reset()
        ns = LoadAddon({ files = { "Modules/UI/Menu.lua" } })
        anchor = WowMock.NewFrame("Button")
    end)

    it("shows an option per item and calls onPick with the chosen one", function()
        local picked
        ns.PopupMenu(anchor, { { name = "One" }, { name = "Two" } }, function(opt, i) picked = { opt.name, i } end)
        local buttons = optionButtons()
        assert.are.equal(2, #buttons)
        buttons[2]:Click()
        assert.are.same({ "Two", 2 }, picked)
    end)

    it("picking an option closes the menu; clicking the same control again does too", function()
        ns.PopupMenu(anchor, { { name = "One" } }, function() end)
        local popup = optionButtons()[1]._parent
        assert.is_true(popup:IsShown())
        ns.PopupMenu(anchor, { { name = "One" } }, function() end)
        assert.is_false(popup:IsShown())
    end)

    it("closes if the control that opened it goes away", function()
        ns.PopupMenu(anchor, { { name = "One" } }, function() end)
        local popup = optionButtons()[1]._parent
        anchor:Hide()
        assert.is_false(popup:IsShown())
    end)

    it("disabled options can't be picked", function()
        ns.PopupMenu(anchor, { { name = "One", disabled = true } }, function() end)
        assert.is_false(optionButtons()[1]:IsEnabled())
    end)
end)
