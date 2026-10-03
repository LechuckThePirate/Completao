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

    describe("the spot the game gives for a quest in the log", function()
        before_each(function()
            WowMock.onQuest[901] = true
            WowMock.playerMap = 1411
            WowMock.questsOnMap[1411] = {
                { questID = 5, x = 0.1, y = 0.2 },
                { questID = 901, x = 0.565, y = 0.53 },
            }
            q.steps = nil
            WowMock.objectives[901] = {
                { text = "1/1 Raider's Bow", finished = true, numFulfilled = 1, numRequired = 1 },
                { text = "0/1 Raider's Shield", finished = false, numFulfilled = 0, numRequired = 1 },
            }
        end)

        it("is the place of the objectives the data has no place for", function()
            local list, current = ns.QuestSteps(q)
            assert.are.equal("Raider's Shield", list[current].label)
            local loc = list[current].loc
            assert.are.equal(1411, loc.map)
            assert.is_true(math.abs(loc.x - 56.5) < 1e-6 and math.abs(loc.y - 53) < 1e-6)
            assert.is_nil(list[2].loc) -- the done one needs none
        end)

        it("is not used out of the log, or when the quest isn't on the player's map", function()
            WowMock.questsOnMap[1411] = { { questID = 5, x = 0.1, y = 0.2 } }
            local list, current = ns.QuestSteps(q)
            assert.is_nil(list[current].loc)
            WowMock.questsOnMap[1411] = { { questID = 901, x = 0.565, y = 0.53 } }
            WowMock.onQuest[901] = nil
            list = ns.QuestSteps(q)
            for _, s in ipairs(list) do if s.kind == "obj" then assert.is_nil(s.loc) end end
        end)

        it("never replaces a place the data has", function()
            q.steps = { { name = "Raider's Shield", area = 12, x = 30, y = 31 } }
            local list, current = ns.QuestSteps(q)
            assert.are.equal(30, list[current].loc.x)
        end)
    end)
    it("the game's objectives with no step in the data are added without a location", function()
        WowMock.onQuest[901] = true
        q.steps = nil
        WowMock.objectives[901] = { { text = "Something: 0/2", finished = false, numFulfilled = 0, numRequired = 2 } }
        local list, current = ns.QuestSteps(q)
        assert.are.equal("Something", list[current].label)
        assert.is_nil(list[current].loc)
    end)

    describe("objectives in the client's language", function()
        local spanish = {
            { text = "Carne de lobo duro: 3/8", finished = false, numFulfilled = 3, numRequired = 8 },
            { text = "Cabeza de VanCleef: 0/1", finished = false, numFulfilled = 0, numRequired = 1 },
        }

        it("in the log: when no name matches, the game's text is the label and the order pairs the progress", function()
            WowMock.onQuest[901] = true
            WowMock.objectives[901] = spanish
            local list = ns.QuestSteps(q)
            assert.are.equal("Carne de lobo duro", list[2].label)
            assert.are.equal("3/8", list[2].progress)
            assert.are.equal("Cabeza de VanCleef", list[3].label)
        end)

        it("in the log: a name that matches keeps the data's label", function()
            WowMock.onQuest[901] = true
            WowMock.objectives[901] = { { text = "Tough Wolf Meat slain: 3/8" } }
            assert.are.equal("Tough Wolf Meat", ns.QuestSteps(q)[2].label)
        end)

        it("out of the log with as many objectives as steps: the game's labels, no progress", function()
            WowMock.objectives[901] = spanish
            local list = ns.QuestSteps(q)
            assert.are.equal("Carne de lobo duro", list[3].label)
            assert.are.equal("Cabeza de VanCleef", list[4].label)
            assert.is_nil(list[3].progress)
            assert.is_falsy(list[3].done)
            assert.are.equal(12, list[3].area) -- the place still comes from the data
        end)

        it("out of the log with another count: the data's steps, untouched", function()
            WowMock.objectives[901] = { spanish[1] }
            local list = ns.QuestSteps(q)
            assert.are.same({ "req", "start", "obj", "obj", "finish" }, kinds(list))
            assert.are.equal("Tough Wolf Meat", list[3].label)
            assert.are.equal("Head of VanCleef", list[4].label)
        end)

        it("out of the log for a quest with no steps in the data: the game's objectives, no progress", function()
            q.steps = nil
            WowMock.objectives[901] = spanish
            local list = ns.QuestSteps(q)
            assert.are.same({ "req", "start", "obj", "obj", "finish" }, kinds(list))
            assert.are.equal("Cabeza de VanCleef", list[4].label)
            assert.is_nil(list[4].progress)
        end)

        it("asks the client to load a quest out of the log, once", function()
            local calls = {}
            C_QuestLog.RequestLoadQuestByID = function(id) calls[id] = (calls[id] or 0) + 1 end
            ns.QuestSteps(q)
            ns.QuestSteps(q)
            assert.are.equal(1, calls[901])
        end)
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
