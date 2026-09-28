dofile("setupTests.lua")

describe("QuestSteps", function()
    local ns, q

    before_each(function()
        WowMock.Reset()
        ns = LoadAddon({ files = {
            "Modules/Database/Entries.lua", "Modules/Quest/QuestState.lua",
            "Modules/Quest/QuestSteps.lua",
        } })
        ns.RegisterEntry({ id = "z", name = "Zone", category = "zones" })
        ns.AddQuests("z", { { id = 900, name = "Before", start = { npc = "Old", area = 12, x = 1, y = 2 } } })
        q = { id = 901, name = "Test", requires = { 900 },
            start = { npc = "Giver", area = 12, x = 10, y = 11 }, finish = { npc = "Ender", area = 12, x = 20, y = 21 },
            steps = { { name = "Tough Wolf Meat", area = 12, x = 30, y = 31 }, { name = "Head of VanCleef", area = 1581 } } }
    end)

    local function kinds(list)
        local k = {}
        for i, s in ipairs(list) do k[i] = s.kind end
        return k
    end

    it("not started with a pending requirement: the requirement is next", function()
        local list, current = ns.QuestSteps(q)
        assert.are.same({ "req", "start", "obj", "obj", "finish" }, kinds(list))
        assert.are.equal(1, current)
        assert.are.equal("Old", list[1].loc.npc)
        assert.matches("Before", list[1].label)
    end)

    it("not started with requirements done: the start is next", function()
        WowMock.done[900] = true
        local list, current = ns.QuestSteps(q)
        assert.are.equal("start", list[current].kind)
        assert.is_true(list[current].current)
    end)

    it("in progress: the first unfinished objective, with its progress", function()
        WowMock.onQuest[901] = true
        WowMock.objectives[901] = {
            { text = "Tough Wolf Meat: 3/8", finished = false, numFulfilled = 3, numRequired = 8 },
            { text = "Head of VanCleef: 0/1", finished = false, numFulfilled = 0, numRequired = 1 },
        }
        local list, current = ns.QuestSteps(q)
        assert.are.equal("Tough Wolf Meat", list[current].label)
        assert.are.equal("3/8", list[current].progress)
        assert.is_true(list[1].done) -- the start
    end)

    it("matches objectives by name even when they come in another order", function()
        WowMock.onQuest[901] = true
        WowMock.objectives[901] = {
            { text = "Head of VanCleef: 1/1", finished = true, numFulfilled = 1, numRequired = 1 },
            { text = "Tough Wolf Meat: 2/8", finished = false, numFulfilled = 2, numRequired = 8 },
        }
        local list = ns.QuestSteps(q)
        assert.are.equal("2/8", list[2].progress)
        assert.is_true(list[3].done)
    end)

    it("the game's objectives with no step in the data are added without a location", function()
        WowMock.onQuest[901] = true
        q.steps = nil
        WowMock.objectives[901] = { { text = "Something: 0/2", finished = false, numFulfilled = 0, numRequired = 2 } }
        local list, current = ns.QuestSteps(q)
        assert.are.equal("Something", list[current].label)
        assert.is_nil(list[current].loc)
    end)

    it("ready to turn in: the turn-in is next", function()
        WowMock.onQuest[901] = true
        WowMock.readyForTurnIn[901] = true
        local list, current = ns.QuestSteps(q)
        assert.are.equal("finish", list[current].kind)
    end)

    it("done: everything ticked, and the turn-in", function()
        WowMock.done[901] = true
        local list, current = ns.QuestSteps(q)
        assert.are.equal(#list, current)
        for _, s in ipairs(list) do assert.is_true(s.done, s.label) end
    end)

    it("a step inside a dungeon has no coordinates but has a zone", function()
        local list = ns.QuestSteps(q)
        assert.is_nil(list[4].loc)
        assert.are.equal(1581, list[4].area)
    end)
end)
