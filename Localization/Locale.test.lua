dofile("setupTests.lua")

-- Every translation: its file, the client locales that use it, and the translation of "Professions".
local TRANSLATIONS = {
    { file = "esES", locales = { "esES", "esMX" }, professions = "Profesiones" },
}

-- The table a locale file registers, read by running it with a stub namespace.
local function translationTable(file)
    local registered
    local ns = { AddLocale = function(_, strings) registered = strings end }
    assert(loadfile("Localization/" .. file .. ".lua"))("Completao", ns)
    return registered
end

-- The "%d" / "%s" / "%%" placeholders of a text, in order.
local function placeholders(text)
    local found = {}
    for p in text:gmatch("%%[%d%.]*[sd%%]") do found[#found + 1] = p end
    return table.concat(found, " ")
end

-- The code files (not the data nor the translations), as { file = text }.
local cachedCode
local function codeFiles()
    if not cachedCode then
        cachedCode = {}
        for _, file in ipairs(TocFiles()) do
            if not file:match("^Data/") and not file:match("^Localization/") then
                local handle = assert(io.open(file))
                cachedCode[file] = handle:read("*a")
                handle:close()
            end
        end
    end
    return cachedCode
end

-- Every English text the code looks up with L["..."]: { [key] = file where it is used }.
local function usedKeys()
    local used = {}
    for file, text in pairs(codeFiles()) do
        for key in text:gmatch('L%["(.-)"%]') do used[key] = used[key] or file end
    end
    return used
end

-- Some texts are looked up through a variable (L[EMPTY[mode]]): a translation is in use while its text is
-- still written somewhere in the code.
local function writtenInCode(key)
    for _, text in pairs(codeFiles()) do
        if text:find('"' .. key .. '"', 1, true) then return true end
    end
    return false
end

describe("Locale", function()
    before_each(function() WowMock.Reset() end)

    it("in English returns the key itself", function()
        local ns = LoadAddon({ files = { "Localization/Locale.lua" } })
        assert.are.equal("Dungeons", ns.L["Dungeons"])
        assert.are.equal("Any text", ns.L["Any text"])
    end)

    it("the TOC loads Locale.lua first and every translation file", function()
        local files = {}
        for _, file in ipairs(TocFiles()) do
            if file:match("^Localization/") then files[#files + 1] = file end
        end
        assert.are.equal("Localization/Locale.lua", files[1])
        local listed = {}
        for _, file in ipairs(files) do listed[file] = true end
        for _, t in ipairs(TRANSLATIONS) do
            assert.is_true(listed["Localization/" .. t.file .. ".lua"], t.file)
        end
        assert.are.equal(#TRANSLATIONS + 1, #files)
    end)

    for _, t in ipairs(TRANSLATIONS) do
        describe(t.file, function()
            it("is used by its client locales, and only by them", function()
                for _, locale in ipairs(t.locales) do
                    WowMock.locale = locale
                    local ns = LoadAddon()
                    assert.are.equal(t.professions, ns.L["Professions"], locale)
                    assert.are.equal("Untranslated text", ns.L["Untranslated text"], locale)
                end
                WowMock.locale = "enUS"
                assert.are.equal("Professions", LoadAddon().L["Professions"])
            end)

            it("translates every string the code uses, and every one the first translation has", function()
                local strings = translationTable(t.file)
                local used, missing = usedKeys(), {}
                for key, file in pairs(used) do
                    if not strings[key] then missing[#missing + 1] = key .. "  (" .. file .. ")" end
                end
                for key in pairs(translationTable(TRANSLATIONS[1].file)) do
                    if not strings[key] and not used[key] then missing[#missing + 1] = key end
                end
                table.sort(missing)
                assert.are.same({}, missing, "untranslated")
            end)

            it("has no string the code no longer uses", function()
                local stale = {}
                for key in pairs(translationTable(t.file)) do
                    if not writtenInCode(key) then stale[#stale + 1] = key end
                end
                table.sort(stale)
                assert.are.same({}, stale, "stale")
            end)

            it("keeps the placeholders of every text", function()
                local wrong = {}
                for key, value in pairs(translationTable(t.file)) do
                    if placeholders(key) ~= placeholders(value) then wrong[#wrong + 1] = key end
                end
                table.sort(wrong)
                assert.are.same({}, wrong, "placeholders differ")
            end)
        end)
    end
end)
