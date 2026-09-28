dofile("setupTests.lua")

describe("Locale", function()
    before_each(function() WowMock.Reset() end)

    it("in English returns the key itself", function()
        local ns = LoadAddon({ files = { "Localization/Locale.lua" } })
        assert.are.equal("Dungeons", ns.L["Dungeons"])
        assert.are.equal("Any text", ns.L["Any text"])
    end)

    it("on esES and esMX uses Spanish", function()
        for _, locale in ipairs({ "esES", "esMX" }) do
            WowMock.locale = locale
            local ns = LoadAddon({ files = { "Localization/Locale.lua" } })
            assert.are.equal("Mazmorras", ns.L["Dungeons"])
            assert.are.equal("Untranslated text", ns.L["Untranslated text"])
        end
    end)

    it("every string the code uses has a Spanish translation", function()
        -- keys of the Spanish table (a translation can equal the English one: "Waypoint: %s")
        local translated = {}
        for key in io.open("Localization/Locale.lua"):read("*a"):gmatch('%["(.-)"%]%s*=') do translated[key] = true end
        local missing, seen = {}, {}
        for _, file in ipairs(TocFiles()) do
            if not file:match("^Data/") and file ~= "Localization/Locale.lua" then
                local text = io.open(file):read("*a")
                for key in text:gmatch('L%["(.-)"%]') do
                    if not translated[key] and not seen[key] then
                        seen[key] = true
                        missing[#missing + 1] = key .. "  (" .. file .. ")"
                    end
                end
            end
        end
        assert.are.same({}, missing, "untranslated")
    end)
end)
