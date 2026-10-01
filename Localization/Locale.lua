local _, ns = ...

-- Keys are the English text. Each Localization/<locale>.lua registers its translations through
-- ns.AddLocale; only the one for the client's locale is applied, and what it doesn't translate stays English.
ns.L = setmetatable({}, { __index = function(_, k) return k end })

local clientLocale = GetLocale()

function ns.AddLocale(locales, strings)
    for _, locale in ipairs(locales) do
        if locale == clientLocale then
            for k, v in pairs(strings) do ns.L[k] = v end
            return
        end
    end
end
