dofile("setupTests.lua")

describe("Preferences", function()
    local ns, prefs

    before_each(function()
        WowMock.Reset()
        ns = OpenAddon("vc")
        ns.Prefs_Toggle()
        prefs = _G.CompletaoPreferencesFrame
    end)

    it("el primer clic en el engranaje la abre (no hace falta un segundo)", function()
        assert.is_true(prefs:IsShown())
        ns.Prefs_Toggle()
        assert.is_false(prefs:IsShown())
    end)

    it("las casillas reflejan y cambian los ajustes", function()
        local checks = WowMock.FindAll(function(f) return f._kind == "CheckButton" and f._parent == prefs end)
        -- orden: por personaje, minimapa, mensajes, abrir con el registro
        assert.are.equal(4, #checks)
        assert.is_true(checks[1]:GetChecked())
        checks[3]:SetChecked(false); checks[3]:Click()
        assert.is_true(ns.char.quiet)
        checks[4]:SetChecked(true); checks[4]:Click()
        assert.is_true(ns.char.openWithQuestLog)
        checks[2]:SetChecked(false); checks[2]:Click()
        assert.is_false(ns.Minimap_IsShown())
    end)

    it("la opacidad al moverse sale del deslizador", function()
        local slider = WowMock.Find(function(f) return f._kind == "Slider" end)
        slider._scripts.OnValueChanged(slider, 0.3)
        assert.are.equal(0.3, ns.char.fadeAlpha)
    end)

    it("pasar a ajustes comunes cambia el texto de abajo", function()
        local checks = WowMock.FindAll(function(f) return f._kind == "CheckButton" and f._parent == prefs end)
        checks[1]:SetChecked(false); checks[1]:Click()
        assert.is_false(ns.IsPerCharacter())
        assert.is_not_nil(WowMock.FindByText("Settings are shared by all your characters."))
    end)

    it("restablecer zoom, filtros y ventana", function()
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
