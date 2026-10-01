dofile("setupTests.lua")

describe("Entries", function()
    local ns

    before_each(function()
        WowMock.Reset()
        ns = LoadAddon({ files = { "Modules/Database/Entries.lua", "Modules/Quest/QuestState.lua" } })
    end)

    it("registers entries with 'dungeons' as the default section", function()
        ns.RegisterEntry({ id = "dm", name = "The Deadmines" })
        assert.are.equal("dungeons", ns.entries.dm.category)
        assert.are.same({}, ns.entries.dm.quests)
        assert.are.equal(ns.entries.dm, ns.entryList[1])
    end)

    it("adds quests to an entry and records their entry", function()
        ns.RegisterEntry({ id = "dm", name = "The Deadmines" })
        ns.AddQuests("dm", { { id = 166, name = "The Defias Brotherhood" } })
        assert.are.equal(1, #ns.entries.dm.quests)
        assert.are.equal("dm", ns.entries.dm.quests[1].entryId)
    end)

    it("an entry has work while a quest you can see is in your log or available", function()
        ns.RegisterEntry({ id = "dm", name = "The Deadmines" })
        ns.AddQuests("dm", {
            { id = 1, name = "First", minLevel = 10 },
            { id = 2, name = "Second", requires = { 1 } },
            { id = 3, name = "Hordish", faction = "Horde" },
            { id = 4, name = "Too high", minLevel = 40 },
        })
        assert.is_true(ns.EntryHasWork(ns.entries.dm))   -- the first one
        WowMock.done[1] = true
        assert.is_true(ns.EntryHasWork(ns.entries.dm))   -- the second is open now
        WowMock.done[2] = true
        assert.is_false(ns.EntryHasWork(ns.entries.dm))  -- the other two: not for you, not yet
        WowMock.level = 40
        assert.is_true(ns.EntryHasWork(ns.entries.dm))
        WowMock.onQuest[4] = nil
        WowMock.done[4] = true
        assert.is_false(ns.EntryHasWork(ns.entries.dm))  -- all done (the Horde one isn't yours)
    end)

    it("a holiday quest that is also in a dungeon counts as work only in the events section", function()
        ns.RegisterEntry({ id = "brd", name = "Blackrock Depths" })
        ns.RegisterEntry({ id = "lunar", name = "Lunar Festival", category = "events" })
        local elder = { id = 8619, name = "Morndeep the Elder", level = 60, minLevel = 1 }
        ns.AddQuests("brd", { elder, { id = 4001, name = "A dungeon quest", minLevel = 52 } })
        ns.AddQuests("lunar", { { id = 8619, name = "Morndeep the Elder", level = 60, minLevel = 1 } })
        assert.is_true(ns.QuestIsIn(8619, "events"))
        assert.is_false(ns.QuestIsIn(4001, "events"))
        assert.is_false(ns.EntryHasWork(ns.entries.brd))  -- only the elder is open to a level 20, and it is the festival's
        assert.is_true(ns.EntryHasWork(ns.entries.lunar))
        WowMock.level = 52
        assert.is_true(ns.EntryHasWork(ns.entries.brd))   -- a quest of its own is
    end)

    it("the quests of an instance far above the character's level aren't work", function()
        ns.RegisterEntry({ id = "av", name = "Alterac Valley", category = "battlegrounds", minLevel = 51, maxLevel = 60 })
        ns.AddQuests("av", { { id = 6901, name = "Launch the Attack!", level = 60, minLevel = 1 } })
        ns.RegisterEntry({ id = "sfk", name = "Shadowfang Keep", minLevel = 18, maxLevel = 25 })
        ns.AddQuests("sfk", { { id = 1098, name = "Deathstalkers in Shadowfang", level = 25, minLevel = 1 } })
        WowMock.level = 40
        assert.is_false(ns.EntryHasWork(ns.entries.av))  -- open from level 1, but inside an instance of 51
        assert.is_true(ns.EntryHasWork(ns.entries.sfk))
        WowMock.level = 41
        assert.is_true(ns.EntryHasWork(ns.entries.av))   -- 10 levels before its minimum
        WowMock.level = 5
        assert.is_false(ns.EntryHasWork(ns.entries.sfk)) -- 13 levels under
    end)

    it("a quest marked as a holiday one counts as work only in the events section", function()
        ns.RegisterEntry({ id = "z", name = "Zone", category = "zones" })
        ns.RegisterEntry({ id = "e", name = "Some event", category = "events" })
        ns.AddQuests("z", { { id = 1, name = "Darkmoon Faire", level = 60, minLevel = 1 } })
        ns.AddQuests("e", { { id = 2, name = "Event quest", level = 60, minLevel = 1 } })
        assert.is_true(ns.EntryHasWork(ns.entries.z))
        ns.PatchQuest(1, { holiday = true })
        assert.is_false(ns.EntryHasWork(ns.entries.z))
        ns.PatchQuest(2, { holiday = true })
        assert.is_true(ns.EntryHasWork(ns.entries.e))
    end)

    describe("classes and races", function()
        before_each(function()
            for _, c in ipairs({ { "MAGE", "Mage" }, { "WARRIOR", "Warrior" } }) do
                ns.RegisterEntry({ id = "c_" .. c[1], name = c[2], category = "classes", classFile = c[1] })
                ns.AddQuests("c_" .. c[1], { { id = c[1] == "MAGE" and 1501 or 1502, name = c[2] .. " quest", level = 10, minLevel = 10 } })
            end
            for _, r in ipairs({ { 1, "Human" }, { 2, "Orc" }, { 3, "Dwarf" } }) do
                ns.RegisterEntry({ id = "r_" .. r[1], name = r[2], category = "races", raceId = r[1] })
                ns.AddQuests("r_" .. r[1], { { id = 1600 + r[1], name = r[2] .. " quest", level = 10, minLevel = 10 } })
            end
            WowMock.level = 20
        end)

        it("only your own class has work", function()  -- the character is a Mage
            assert.is_true(ns.EntryHasWork(ns.entries.c_MAGE))
            assert.is_false(ns.EntryHasWork(ns.entries.c_WARRIOR))
            WowMock.class = { "Warrior", "WARRIOR", 1 }
            assert.is_true(ns.EntryHasWork(ns.entries.c_WARRIOR))
            assert.is_false(ns.EntryHasWork(ns.entries.c_MAGE))
        end)

        it("only your own race has work", function()  -- a Human
            assert.is_true(ns.EntryHasWork(ns.entries.r_1))
            assert.is_false(ns.EntryHasWork(ns.entries.r_2))
            assert.is_false(ns.EntryHasWork(ns.entries.r_3))
        end)

        it("with 'Show other faction', the races of the other faction too, not the ones of your own", function()
            ns.char = { filters = { otherFaction = true } }
            assert.is_true(ns.EntryHasWork(ns.entries.r_2))   -- Orc: Horde
            assert.is_false(ns.EntryHasWork(ns.entries.r_3))  -- Dwarf: Alliance, like you
            assert.is_true(ns.EntryHasWork(ns.entries.r_1))
        end)
    end)

    describe("professions", function()
        before_each(function()
            ns.RegisterEntry({ id = "p_356", name = "Fishing", category = "professions", skillLine = 356 })
            ns.AddQuests("p_356", { { id = 8193, name = "Master Angler", level = 60, minLevel = 1 } })
            ns.RegisterEntry({ id = "p_crafting", name = "Crafting", category = "professions" })
            ns.AddQuests("p_crafting", { { id = 94004, name = "Craftsman's Writ: Elixir", level = 60, minLevel = 1 } })
        end)

        it("their quests are work only with the profession", function()
            assert.is_false(ns.EntryHasWork(ns.entries.p_356))
            WowMock.skills = { 356 }
            assert.is_true(ns.EntryHasWork(ns.entries.p_356))
            assert.is_true(ns.HasProfession(356))
            assert.is_false(ns.HasProfession(171))
        end)

        it("the crafting writs, with any crafting profession", function()
            assert.is_false(ns.EntryHasWork(ns.entries.p_crafting))
            WowMock.skills = { 356 }          -- fishing doesn't craft
            assert.is_false(ns.EntryHasWork(ns.entries.p_crafting))
            WowMock.skills = { 356, 171 }     -- alchemy does
            assert.is_true(ns.EntryHasWork(ns.entries.p_crafting))
        end)

        it("when the client can't tell what professions you have, nothing is hidden", function()
            local savedList, savedInfo = _G.GetProfessions, _G.GetProfessionInfo
            _G.GetProfessions, _G.GetProfessionInfo = nil, nil
            assert.is_nil(ns.HasProfession(356))
            assert.is_true(ns.EntryHasWork(ns.entries.p_356))
            assert.is_true(ns.EntryHasWork(ns.entries.p_crafting))
            _G.GetProfessions, _G.GetProfessionInfo = savedList, savedInfo
        end)

        it("with the classic skill list, by the skill's name", function()
            local savedList, savedInfo = _G.GetProfessions, _G.GetProfessionInfo
            _G.GetProfessions, _G.GetProfessionInfo = nil, nil
            _G.C_TradeSkillUI = { GetTradeSkillDisplayName = function(id) return id == 356 and "Fishing" or "Other" end }
            local lines = { { "Weapon Skills", true }, { "Fishing", false } }
            _G.GetNumSkillLines = function() return #lines end
            _G.GetSkillLineInfo = function(i) return lines[i][1], lines[i][2] end
            assert.is_true(ns.HasProfession(356))
            lines[2] = { "Cooking", false }
            assert.is_false(ns.HasProfession(356))
            _G.GetNumSkillLines, _G.GetSkillLineInfo, _G.C_TradeSkillUI = nil, nil, nil
            _G.GetProfessions, _G.GetProfessionInfo = savedList, savedInfo
        end)
    end)

    it("an entry with no quests has no work", function()
        ns.RegisterEntry({ id = "dm", name = "The Deadmines" })
        assert.is_false(ns.EntryHasWork(ns.entries.dm))
    end)

    it("ignores quests of an entry that doesn't exist", function()
        assert.has_no.errors(function() ns.AddQuests("nope", { { id = 1, name = "x" } }) end)
        assert.is_nil(ns.FindQuestDef(1))
    end)

    it("PatchQuest fixes every copy of a quest and false removes the field", function()
        ns.RegisterEntry({ id = "a", name = "A", category = "zones" })
        ns.RegisterEntry({ id = "b", name = "B" })
        ns.AddQuests("a", { { id = 5, name = "Q", requires = { 4 } } })
        ns.AddQuests("b", { { id = 5, name = "Q", requires = { 4 } } })
        ns.PatchQuest(5, { level = 10, requires = false })
        for _, e in ipairs({ "a", "b" }) do
            assert.are.equal(10, ns.entries[e].quests[1].level)
            assert.is_nil(ns.entries[e].quests[1].requires)
        end
    end)

    it("FindQuestDef returns the first copy", function()
        ns.RegisterEntry({ id = "a", name = "A" })
        ns.AddQuests("a", { { id = 7, name = "Seven" } })
        assert.are.equal("Seven", ns.FindQuestDef(7).name)
    end)

    it("SetEntrance stores the instance's door", function()
        ns.RegisterEntry({ id = "dm", name = "DM" })
        ns.SetEntrance("dm", { area = 40, x = 42.5, y = 71.7 })
        assert.are.equal(42.5, ns.entries.dm.entrance.x)
    end)

    describe("EntryName", function()
        it("zones: the client's name", function()
            assert.are.equal("Area12", ns.EntryName({ category = "zones", area = 12, name = "Elwynn Forest" }))
        end)
        it("classes: the class's localized name", function()
            assert.are.equal("Mage", ns.EntryName({ classFile = "MAGE", name = "x" }))
        end)
        it("races: the client's race name", function()
            assert.are.equal("Race2", ns.EntryName({ raceId = 2, name = "Orc" }))
        end)
        it("professions: the client's name when it gives one; otherwise the data's", function()
            assert.are.equal("Fishing", ns.EntryName({ skillLine = 356, name = "Fishing" }))
            _G.C_TradeSkillUI = { GetTradeSkillDisplayName = function() return "Client Fishing" end }
            assert.are.equal("Client Fishing", ns.EntryName({ skillLine = 356, name = "Fishing" }))
            _G.C_TradeSkillUI = nil
        end)
        it("instances with a nameArea: the client's name, the data's if it gives none", function()
            assert.are.equal("Area2437", ns.EntryName({ name = "Ragefire Chasm", nameArea = 2437 }))
            local getAreaInfo = C_Map.GetAreaInfo
            C_Map.GetAreaInfo = function() return nil end
            assert.are.equal("Ragefire Chasm", ns.EntryName({ name = "Ragefire Chasm", nameArea = 2437 }))
            C_Map.GetAreaInfo = getAreaInfo
        end)
        it("instances without one: the translation by their English name", function()
            assert.are.equal("Lower Blackrock Spire", ns.EntryName({ name = "Lower Blackrock Spire" }))
            ns.L["Lower Blackrock Spire"] = "Cumbre inferior de Roca Negra"
            assert.are.equal("Cumbre inferior de Roca Negra", ns.EntryName({ name = "Lower Blackrock Spire" }))
            ns.L["Lower Blackrock Spire"] = nil
        end)
    end)

    it("EntryProgress counts done over the ones the character sees", function()
        ns.RegisterEntry({ id = "a", name = "A", category = "zones" })
        ns.AddQuests("a", { { id = 1, name = "a" }, { id = 2, name = "b" }, { id = 3, name = "horde", faction = "Horde" } })
        WowMock.done[1] = true
        local done, total = ns.EntryProgress(ns.entries.a)
        assert.are.equal(1, done)
        assert.are.equal(2, total)
    end)
end)
