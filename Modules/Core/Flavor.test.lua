dofile("setupTests.lua")

describe("Flavor", function()
    local function load(interface)
        _G.GetBuildInfo = interface and function() return "1.0.0", "1", "Jan 1 2026", interface end or nil
        return LoadAddon({ files = { "Modules/Core/Flavor.lua" } })
    end

    before_each(function() WowMock.Reset() end)
    after_each(function() _G.GetBuildInfo = nil end)

    it("tells the client from the interface number", function()
        local ns = load(nil)
        assert.are.equal("vanilla", ns.DetectFlavor(11508))
        assert.are.equal("forever", ns.DetectFlavor(16001))
        assert.are.equal("tbc", ns.DetectFlavor(20505))
        assert.are.equal("mainline", ns.DetectFlavor(120000))
    end)

    it("is nil for the clients it has no data for", function()
        local ns = load(nil)
        assert.is_nil(ns.DetectFlavor(30403)) -- Wrath
        assert.is_nil(ns.DetectFlavor(50503)) -- Mists
        assert.is_nil(ns.DetectFlavor(12000)) -- not a client of ours
        assert.is_nil(ns.DetectFlavor(nil))
    end)

    it("sets the flavor of the running client", function()
        local ns = load(16001)
        assert.are.equal("forever", ns.flavor)
        assert.is_true(ns.IsFlavor("forever"))
        assert.is_false(ns.IsFlavor("tbc"))
    end)

    it("has no flavor when the client can't tell its build", function()
        assert.is_nil(load(nil).flavor)
    end)
end)
