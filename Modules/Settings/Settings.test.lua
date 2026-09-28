dofile("setupTests.lua")

describe("Settings", function()
    local ns, applied

    local function login(charDB, accountDB)
        CompletaoDB, CompletaoCharDB = accountDB, charDB
        ns = LoadAddon({ files = { "Modules/Settings/Settings.lua" } })
        applied = 0
        ns.Minimap_Init = function() ns.char.minimap = ns.char.minimap or { angle = 225 } end
        ns.UI_ApplySettings = function() applied = applied + 1 end
        ns.InitSettings()
        return ns
    end

    before_each(function() WowMock.Reset() end)

    it("por defecto, por personaje, conservando lo que ya tenia", function()
        local char = { fadeAlpha = 0.3, zoom = 0.8 }
        login(char, {})
        assert.is_true(ns.IsPerCharacter())
        assert.are.equal(0.3, ns.char.fadeAlpha)
        assert.are.same({}, ns.char.filters)
    end)

    it("los ajustes comunes se estrenan con los del primer personaje", function()
        local account = {}
        login({ zoom = 0.8 }, account)
        assert.are.equal(0.8, account.shared.zoom)
    end)

    it("borra las descripciones guardadas por una version anterior", function()
        local account = { descriptions = { esES = { [1] = "x" } } }
        login({}, account)
        assert.is_nil(account.descriptions)
    end)

    it("por personaje, los cambios no tocan lo comun", function()
        local char, account = { zoom = 0.8 }, {}
        login(char, account)
        ns.char.zoom = 1.2
        assert.are.equal(1.2, char.zoom)
        assert.are.equal(0.8, account.shared.zoom)
    end)

    it("al pasar a comunes se leen y escriben los comunes; la copia del personaje se queda", function()
        local char, account = { fadeAlpha = 0.3, selected = "vc" }, {}
        login(char, account)
        account.shared.zoom = 0.9
        ns.SetPerCharacter(false)
        assert.are.equal(1, applied)
        assert.are.equal(0.9, ns.char.zoom)
        ns.char.fadeAlpha = 0.6
        assert.are.equal(0.6, account.shared.fadeAlpha)
        assert.are.equal(0.3, char.fadeAlpha)
    end)

    it("la entrada seleccionada es siempre del personaje", function()
        local char, account = {}, {}
        login(char, account)
        ns.SetPerCharacter(false)
        ns.char.selected = "wc"
        assert.are.equal("wc", char.selected)
        assert.is_nil(account.shared.selected)
    end)

    it("un personaje nuevo empieza con una copia de los comunes", function()
        local account = { shared = { fadeAlpha = 0.6, filters = { hideLow = true } } }
        local char = {}
        login(char, account)
        assert.are.equal(0.6, char.fadeAlpha)
        char.filters.hideLow = false
        assert.is_true(account.shared.filters.hideLow)
    end)

    it("al volver a por personaje copia lo comun (el cambio no se nota)", function()
        local char, account = { perCharacter = false }, { shared = { fadeAlpha = 0.6 } }
        login(char, account)
        ns.SetPerCharacter(true)
        assert.are.equal(0.6, char.fadeAlpha)
        ns.char.fadeAlpha = 0.9
        assert.are.equal(0.6, account.shared.fadeAlpha)
    end)

    it("sin cambio no vuelve a aplicar nada", function()
        login({}, {})
        ns.SetPerCharacter(true)
        assert.are.equal(0, applied)
    end)
end)
