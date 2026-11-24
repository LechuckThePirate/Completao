dofile("setupTests.lua")

describe("Theme fonts", function()
    -- T.fonts as Theme.lua builds it on a client with that locale and standard font
    local function fontsOn(locale, standard)
        WowMock.locale = locale
        _G.STANDARD_TEXT_FONT = standard
        local ns = {}
        assert(loadfile("Modules/UI/Theme.lua"))("Completao", ns)
        return ns.Theme.fonts
    end

    after_each(function()
        WowMock.locale = nil
        _G.STANDARD_TEXT_FONT = nil
    end)

    it("keeps Friz Quadrata, Morpheus and Arial Narrow on the Latin clients", function()
        local fonts = fontsOn("enUS", "Fonts\\FRIZQT__.TTF")
        assert.are.equal("Fonts\\FRIZQT__.TTF", fonts.quest[1])
        assert.are.equal("Fonts\\MORPHEUS.TTF", fonts.logo[1])
        assert.are.equal("Fonts\\ARIALN.TTF", fonts.data[1])
    end)

    it("writes the text in the client's Cyrillic font on ruRU", function()
        local fonts = fontsOn("ruRU", "Fonts\\FRIZQT___CYR.TTF")
        for _, kind in ipairs({ "title", "heading", "quest", "body", "small" }) do
            assert.are.equal("Fonts\\FRIZQT___CYR.TTF", fonts[kind][1])
        end
        assert.are.equal("Fonts\\ARIALN.TTF", fonts.data[1])
    end)

    it("uses only the client's own font on the Asian clients", function()
        local fonts = fontsOn("zhCN", "Fonts\\ARKai_T.ttf")
        for _, f in pairs(fonts) do assert.are.equal("Fonts\\ARKai_T.ttf", f[1]) end
    end)

    it("falls back to Friz Quadrata when the client has no standard font", function()
        assert.are.equal("Fonts\\FRIZQT__.TTF", fontsOn("enUS", nil).body[1])
    end)
end)
