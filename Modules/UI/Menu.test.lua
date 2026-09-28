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

    it("muestra una opcion por elemento y llama a onPick con la elegida", function()
        local picked
        ns.PopupMenu(anchor, { { name = "Uno" }, { name = "Dos" } }, function(opt, i) picked = { opt.name, i } end)
        local buttons = optionButtons()
        assert.are.equal(2, #buttons)
        buttons[2]:Click()
        assert.are.same({ "Dos", 2 }, picked)
    end)

    it("elegir una opcion cierra el menu; pulsar otra vez el mismo control tambien", function()
        ns.PopupMenu(anchor, { { name = "Uno" } }, function() end)
        local popup = optionButtons()[1]._parent
        assert.is_true(popup:IsShown())
        ns.PopupMenu(anchor, { { name = "Uno" } }, function() end)
        assert.is_false(popup:IsShown())
    end)

    it("se cierra si desaparece el control que lo abrio", function()
        ns.PopupMenu(anchor, { { name = "Uno" } }, function() end)
        local popup = optionButtons()[1]._parent
        anchor:Hide()
        assert.is_false(popup:IsShown())
    end)

    it("las opciones deshabilitadas no se pueden elegir", function()
        ns.PopupMenu(anchor, { { name = "Uno", disabled = true } }, function() end)
        assert.is_false(optionButtons()[1]:IsEnabled())
    end)
end)
