dofile("setupTests.lua")

describe("EraToForever", function()
    local ns

    before_each(function()
        WowMock.Reset()
        ns = LoadAddon({ files = { "Modules/Map/EraToForever.lua" } })
    end)

    it("converts the points of the zones Forever redrew", function()
        -- Questie's own Forever dungeon entrances, converted from the Era ones
        local x, y = ns.EraToForever(1519, 42.3, 58.9) -- The Stockade, Stormwind City
        assert.near(52.4, x, 0.06)
        assert.near(70.0, y, 0.06)
        x, y = ns.EraToForever(139, 31.3, 15.7)        -- Stratholme, Eastern Plaguelands
        assert.near(26.5, x, 0.06)
        assert.near(10.4, y, 0.06)
    end)

    it("covers Mulgore and Redridge Mountains too", function()
        local x = ns.EraToForever(215, 44.9, 77.1)
        assert.near(44.5, x, 0.06)
        x = ns.EraToForever(44, 26.6, 44.7)
        assert.near(21.5, x, 0.06)
    end)

    it("leaves every other zone, instance sentinels and empty points alone", function()
        assert.are.same({ 12.5, 40.1 }, { ns.EraToForever(12, 12.5, 40.1) })
        assert.are.same({ -1, -1 }, { ns.EraToForever(1519, -1, -1) })
        assert.are.same({ nil, nil }, { ns.EraToForever(1519, nil, nil) })
    end)

    it("rounds to one decimal, like the data", function()
        local x, y = ns.EraToForever(1519, 42.3, 58.9)
        assert.are.equal(math.floor(x * 10 + 0.5) / 10, x)
        assert.are.equal(math.floor(y * 10 + 0.5) / 10, y)
    end)

    it("converts a location in place only once", function()
        local loc = { npc = "X", area = 1519, x = 42.3, y = 58.9 }
        ns.ConvertLocation(loc)
        local x = loc.x
        ns.ConvertLocation(loc)
        assert.are.equal(x, loc.x)
        assert.is_true(loc.forever)
    end)

    it("ignores locations with no coordinates", function()
        local loc = { npc = "X", area = 1519 }
        ns.ConvertLocation(loc)
        assert.is_nil(loc.x)
        assert.has_no.errors(function() ns.ConvertLocation(nil) end)
    end)
end)
