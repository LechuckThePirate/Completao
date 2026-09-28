dofile("setupTests.lua")

describe("Locale", function()
    before_each(function() WowMock.Reset() end)

    it("en ingles devuelve la propia clave", function()
        local ns = LoadAddon({ files = { "Localization/Locale.lua" } })
        assert.are.equal("Dungeons", ns.L["Dungeons"])
        assert.are.equal("Any text", ns.L["Any text"])
    end)

    it("en esES y esMX usa el espanol", function()
        for _, locale in ipairs({ "esES", "esMX" }) do
            WowMock.locale = locale
            local ns = LoadAddon({ files = { "Localization/Locale.lua" } })
            assert.are.equal("Mazmorras", ns.L["Dungeons"])
            assert.are.equal("Texto sin traducir", ns.L["Texto sin traducir"])
        end
    end)

    it("todas las cadenas que usa el codigo tienen traduccion al espanol", function()
        -- claves de la tabla de espanol (una traduccion puede ser igual que el ingles: "Waypoint: %s")
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
        assert.are.same({}, missing, "sin traducir")
    end)
end)
