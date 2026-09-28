dofile("setupTests.lua")

describe("Settings", function()
    local ns, applied

    local function login(charDB, accountDB)
        _G.CompletaoDB, _G.CompletaoCharDB = accountDB, charDB
        ns = LoadAddon({ files = { "Modules/Settings/Settings.lua" } })
        applied = 0
        ns.Minimap_Init = function() ns.char.minimap = ns.char.minimap or { angle = 225 } end
        ns.UI_ApplySettings = function() applied = applied + 1 end
        ns.InitSettings()
        return ns
    end

    before_each(function() WowMock.Reset() end)

    it("per character by default, keeping what it already had", function()
        local char = { fadeAlpha = 0.3, zoom = 0.8 }
        login(char, {})
        assert.is_true(ns.IsPerCharacter())
        assert.are.equal(0.3, ns.char.fadeAlpha)
        assert.are.same({}, ns.char.filters)
    end)

    it("the shared settings start with the first character's", function()
        local account = {}
        login({ zoom = 0.8 }, account)
        assert.are.equal(0.8, account.shared.zoom)
    end)

    it("removes the descriptions saved by an earlier version", function()
        local account = { descriptions = { esES = { [1] = "x" } } }
        login({}, account)
        assert.is_nil(account.descriptions)
    end)

    it("per character, changes don't touch the shared ones", function()
        local char, account = { zoom = 0.8 }, {}
        login(char, account)
        ns.char.zoom = 1.2
        assert.are.equal(1.2, char.zoom)
        assert.are.equal(0.8, account.shared.zoom)
    end)

    it("switching to shared reads and writes the shared ones; the character's copy stays", function()
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

    it("the selected entry always belongs to the character", function()
        local char, account = {}, {}
        login(char, account)
        ns.SetPerCharacter(false)
        ns.char.selected = "wc"
        assert.are.equal("wc", char.selected)
        assert.is_nil(account.shared.selected)
    end)

    it("a new character starts with a copy of the shared ones", function()
        local account = { shared = { fadeAlpha = 0.6, filters = { hideLow = true } } }
        local char = {}
        login(char, account)
        assert.are.equal(0.6, char.fadeAlpha)
        char.filters.hideLow = false
        assert.is_true(account.shared.filters.hideLow)
    end)

    it("switching back to per character copies the shared ones (the change isn't noticed)", function()
        local char, account = { perCharacter = false }, { shared = { fadeAlpha = 0.6 } }
        login(char, account)
        ns.SetPerCharacter(true)
        assert.are.equal(0.6, char.fadeAlpha)
        ns.char.fadeAlpha = 0.9
        assert.are.equal(0.6, account.shared.fadeAlpha)
    end)

    it("with no change nothing is applied again", function()
        login({}, {})
        ns.SetPerCharacter(true)
        assert.are.equal(0, applied)
    end)
end)
