dofile("setupTests.lua")

describe("QuestState", function()
    local ns

    before_each(function()
        WowMock.Reset()
        ns = LoadAddon({ files = { "Modules/Database/Entries.lua", "Modules/Quest/QuestState.lua" } })
        ns.RegisterEntry({ id = "z", name = "Zone", category = "zones" })
        ns.AddQuests("z", { { id = 10, name = "First" }, { id = 11, name = "Second (2/3)" } })
    end)

    describe("QuestTitle", function()
        it("uses the client's title when it has one", function()
            WowMock.titles[10] = "Client title"
            assert.are.equal("Client title", ns.QuestTitle(10, "First"))
        end)
        it("otherwise the name in the data", function()
            assert.are.equal("First", ns.QuestTitle(10, "First"))
            assert.are.equal("Quest 99", ns.QuestTitle(99))
        end)
        it("asks the client to load a quest only once, or every answer would redraw the window again", function()
            local calls = 0
            C_QuestLog.RequestLoadQuestByID = function() calls = calls + 1 end
            ns.QuestTitle(99, "x"); ns.QuestTitle(99, "x"); ns.IsEliteQuest(99); ns.IsEliteQuest(99)
            assert.are.equal(1, calls)
        end)
        it("keeps the step number of chains with repeated names", function()
            WowMock.titles[11] = "Second"
            assert.are.equal("Second (2/3)", ns.QuestTitle(11, "Second (2/3)"))
        end)
    end)

    describe("QuestStatus", function()
        it("done, in progress, available", function()
            WowMock.done[10] = true
            assert.are.equal("done", ns.QuestStatus({ id = 10 }))
            WowMock.onQuest[12] = true
            assert.are.equal("active", ns.QuestStatus({ id = 12 }))
            assert.are.equal("available", ns.QuestStatus({ id = 13 }))
        end)
        it("locked by level and by requirements, with the reasons", function()
            local status, reasons = ns.QuestStatus({ id = 20, minLevel = 30, requires = { 10 } })
            assert.are.equal("locked", status)
            assert.are.equal(2, #reasons)
            assert.matches("30", reasons[1])
            assert.matches("First", reasons[2])
        end)
        it("requiresAny: one done is enough", function()
            assert.are.equal("locked", (ns.QuestStatus({ id = 21, requiresAny = { 10, 11 } })))
            WowMock.done[11] = true
            assert.are.equal("available", (ns.QuestStatus({ id = 21, requiresAny = { 10, 11 } })))
        end)
    end)

    describe("IsReadyToTurnIn", function()
        it("only for a quest in the log with every objective done", function()
            assert.is_false(ns.IsReadyToTurnIn(10))
            WowMock.onQuest[10] = true
            assert.is_false(ns.IsReadyToTurnIn(10))
            WowMock.readyForTurnIn[10] = true
            assert.is_true(ns.IsReadyToTurnIn(10))
            WowMock.done[10] = true
            assert.is_false(ns.IsReadyToTurnIn(10))
        end)
    end)

    describe("IsEliteQuest", function()
        it("true only when the client tags it Elite, false while unknown", function()
            assert.is_false(ns.IsEliteQuest(10))
            WowMock.tagInfo[10] = { 41, "PvP" }
            assert.is_false(ns.IsEliteQuest(10))
            WowMock.tagInfo[10] = { 1, "Elite" }
            assert.is_true(ns.IsEliteQuest(10))
        end)
    end)

    describe("QuestPrefix", function()
        it("is [level], with D for dungeon quests and + for elite ones (elite first)", function()
            assert.are.equal("[11] ", ns.QuestPrefix({ id = 10, level = 11 }))
            assert.are.equal("[13D] ", ns.QuestPrefix({ id = 10, level = 13, dungeon = true }))
            assert.are.equal("[9] ", ns.QuestPrefix({ id = 10, minLevel = 9 }))
            WowMock.tagInfo[10] = { 1, "Elite" }
            assert.are.equal("[15+] ", ns.QuestPrefix({ id = 10, level = 15 }))
            assert.are.equal("[15+] ", ns.QuestPrefix({ id = 10, level = 15, dungeon = true }))
            assert.are.equal("", ns.QuestPrefix({ id = 10 }))
        end)
    end)

    describe("IsQuestAvailable", function()
        it("a quest to do now: not done, your level, nothing missing", function()
            assert.is_true(ns.IsQuestAvailable({ id = 10, minLevel = 20 }))
            assert.is_true(ns.IsQuestAvailable({ id = 10 }))
        end)
        it("done is not", function()
            WowMock.done[10] = true
            assert.is_false(ns.IsQuestAvailable({ id = 10 }))
        end)
        it("in the log is", function()
            WowMock.onQuest[10] = true
            assert.is_true(ns.IsQuestAvailable({ id = 10, minLevel = 40, requires = { 99 } }))
        end)
        it("not with the level still to reach", function()
            assert.is_false(ns.IsQuestAvailable({ id = 10, minLevel = 21 }))
        end)
        it("not with a required quest still to do; with the last one done it is", function()
            local q = { id = 10, requires = { 98, 99 } }
            WowMock.done[98] = true
            assert.is_false(ns.IsQuestAvailable(q))
            WowMock.done[99] = true
            assert.is_true(ns.IsQuestAvailable(q))
        end)
        it("with 'one of': any of them done", function()
            local q = { id = 10, requiresAny = { 97, 98 } }
            assert.is_false(ns.IsQuestAvailable(q))
            WowMock.done[98] = true
            assert.is_true(ns.IsQuestAvailable(q))
        end)
    end)

    describe("level", function()
        it("low level: grey for the game", function()
            assert.is_true(ns.IsLowLevel({ level = 10 }))
            assert.is_false(ns.IsLowLevel({ level = 18 }))
            assert.is_false(ns.IsLowLevel({}))
        end)
        it("too high: can't be taken yet", function()
            assert.is_true(ns.IsTooHigh({ level = 21, minLevel = 21 }))
        end)
        it("not too high: a quest you can take is shown, however high its own level (Master Angler)", function()
            assert.is_false(ns.IsTooHigh({ level = 60, minLevel = 1 }))
            assert.is_false(ns.IsTooHigh({ level = 60, minLevel = 20 })) -- you are 20
            assert.is_true(ns.IsTooHigh({ level = 60, minLevel = 21 }))
            assert.is_false(ns.IsTooHigh({ level = 60 })) -- no minimum in the data: can't tell
        end)
    end)

    describe("QuestVisible", function()
        before_each(function() ns.char = { filters = {} } end)

        it("hides other-faction quests unless the filter is on", function()
            assert.is_false(ns.QuestVisible({ faction = "Horde" }))
            ns.char.filters.otherFaction = true
            assert.is_true(ns.QuestVisible({ faction = "Horde" }))
        end)
        it("infers the faction from the races", function()
            assert.are.equal("Horde", ns.QuestFaction({ races = 2 + 16 }))
            assert.are.equal("Alliance", ns.QuestFaction({ races = 1 + 4 }))
            assert.is_nil(ns.QuestFaction({ races = 1 + 2 }))
        end)
        it("hides other-class quests unless looking at the classes section", function()
            assert.is_false(ns.QuestVisible({ classes = 1 }))          -- warrior (the player is a mage)
            assert.is_true(ns.QuestVisible({ classes = 128 }))         -- mage
            assert.is_true(ns.QuestVisible({ classes = 1 }, { category = "classes" }))
        end)
        it("hides other-race quests of your faction unless looking at the races section", function()
            assert.is_false(ns.QuestVisible({ races = 4 }))            -- dwarf (the player is human)
            assert.is_true(ns.QuestVisible({ races = 4 }, { category = "races" }))
        end)
        it("the ones marked hidden are never seen", function()
            assert.is_false(ns.QuestVisible({ hidden = true }))
        end)
    end)

    describe("QuestDescription", function()
        it("uses the data's text and puts in the character's name", function()
            assert.are.equal("Hello Tester", ns.QuestDescription({ id = 30, desc = "Hello $N" }))
            assert.is_nil(ns.QuestDescription({ id = 31 }))
        end)
        it("with the quest in the log reads the game's text and leaves the selection as it was", function()
            WowMock.onQuest[32] = true
            WowMock.selectedQuest = 5
            _G.GetQuestLogQuestText = function() return WowMock.selectedQuest == 32 and "Game text" or "" end
            assert.are.equal("Game text", ns.QuestDescription({ id = 32, desc = "english" }))
            assert.are.equal(5, WowMock.selectedQuest)
        end)
    end)

    describe("QuestXP", function()
        it("is the data's experience, and 0 when the quest has none or no row", function()
            local saved = ns.REWARDS
            ns.REWARDS = { [40] = { xp = 1200, money = 5 }, [41] = { money = 5 } }
            assert.are.equal(1200, ns.QuestXP(40))
            assert.are.equal(0, ns.QuestXP(41))
            assert.are.equal(0, ns.QuestXP(42))
            ns.REWARDS = saved
        end)
    end)
end)
