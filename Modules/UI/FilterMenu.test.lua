dofile("setupTests.lua")

describe("FilterMenu", function()
    local ns, values, changes, button

    before_each(function()
        WowMock.Reset()
        ns = LoadAddon()
        values, changes = { b = true }, 0
        button = ns.FilterMenu(UIParent, {
            options = { { key = "a", label = "First", tip = "The first one." }, { key = "b", label = "Second" } },
            get = function(key) return values[key] end,
            set = function(key, on) values[key] = on end,
            onChange = function() changes = changes + 1 end,
        })
    end)

    it("starts closed, with the values ticked and the ones on counted on the button", function()
        assert.is_false(button.menu:IsShown())
        assert.is_false(button.checks.a:GetChecked())
        assert.is_true(button.checks.b:GetChecked())
        assert.are.equal("Filters (1)", button:GetText())
        assert.is_true(button.clear:IsShown())
    end)

    it("the button opens and closes the list", function()
        button._scripts.OnClick(button)
        assert.is_true(button.menu:IsShown())
        button._scripts.OnClick(button)
        assert.is_false(button.menu:IsShown())
    end)

    it("a checkbox sets its value and says so", function()
        button.checks.a:SetChecked(true)
        button.checks.a._scripts.OnClick(button.checks.a)
        assert.is_true(values.a)
        assert.are.equal(1, changes)
        assert.are.equal("Filters (2)", button:GetText())
    end)

    it("Clear filters turns them all off and goes away", function()
        button.clear._scripts.OnClick(button.clear)
        assert.is_false(values.a)
        assert.is_false(values.b)
        assert.is_false(button.checks.b:GetChecked())
        assert.are.equal("Filters", button:GetText())
        assert.is_false(button.clear:IsShown())
        assert.are.equal(1, changes)
    end)

    it("the checkboxes go under Clear filters while it shows", function()
        local _, _, under = button.checks.a:GetPoint()
        button.clear._scripts.OnClick(button.clear)
        local _, _, top = button.checks.a:GetPoint()
        assert.is_true(under < top)
    end)
end)
