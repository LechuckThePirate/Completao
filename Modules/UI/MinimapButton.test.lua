dofile("setupTests.lua")

describe("MinimapButton", function()
    local ns, button

    before_each(function()
        WowMock.Reset()
        ns = LoadAddon()
        StartAddon(ns)
        button = _G.CompletaoMinimapButton
    end)

    it("se crea al entrar, visible y en su angulo por defecto", function()
        assert.is_not_nil(button)
        assert.is_true(button:IsShown())
        assert.are.equal(225, ns.char.minimap.angle)
    end)

    it("clic abre y cierra la ventana", function()
        button:Click()
        assert.is_true(ns.UI:IsShown())
        button:Click()
        assert.is_false(ns.UI:IsShown())
    end)

    it("arrastrarlo cambia su angulo alrededor del minimapa", function()
        WowMock.cursor = { 200, 100 } -- a la derecha del centro (100, 100)
        button._scripts.OnDragStart(button)
        button._scripts.OnUpdate(button)
        button._scripts.OnDragStop(button)
        assert.near(0, ns.char.minimap.angle, 0.001)
    end)

    it("/completao minimap lo oculta y lo vuelve a mostrar, y se recuerda", function()
        SlashCmdList.COMPLETAO("minimap")
        assert.is_false(button:IsShown())
        assert.is_true(ns.char.minimap.hide)
        assert.matches("hidden", WowMock.printed[#WowMock.printed])
        SlashCmdList.COMPLETAO("minimap")
        assert.is_true(button:IsShown())
    end)
end)
