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
