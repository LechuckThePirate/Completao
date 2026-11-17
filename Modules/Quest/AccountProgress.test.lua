dofile("setupTests.lua")

describe("AccountProgress", function()
    local ns

    -- an alt's record, as an earlier session of that character left it
    local function altDB(done)
        return { chars = { ["Altie-Realm"] = { name = "Altie", realm = "Realm", class = "MAGE", done = done } } }
    end

    before_each(function()
        WowMock.Reset()
        ns = LoadAddon()
        ns.RegisterEntry({ id = "zz", name = "Zone", category = "zones" })
        ns.AddQuests("zz", { { id = 990001, name = "First" }, { id = 990002, name = "Second", requires = { 990001 } },
            { id = 990003, name = "Daily", repeatable = true } })
    end)

    it("entering the world records the character's completed quests among the addon's", function()
        WowMock.done[990001], WowMock.done[990003] = true, true
        StartAddon(ns)
        local me = CompletaoDB.chars["Tester-Realm"]
        assert.are.same({ [990001] = true }, me.done) -- not the repeatable one
        assert.are.equal("Tester", me.name)
    end)

    it("a turned in quest is recorded at once", function()
        StartAddon(ns)
        FireEvent("QUEST_TURNED_IN", 990002)
        assert.is_true(CompletaoDB.chars["Tester-Realm"].done[990002])
    end)

    it("knows which other character has done a quest, never the character itself", function()
        local db = altDB({ [990001] = true })
        StartAddon(ns, db)
        assert.are.equal("Altie", ns.DoneByAlt(990001))
        assert.is_nil(ns.DoneByAlt(990002))
        WowMock.done[990002] = true
        FireEvent("QUEST_TURNED_IN", 990002)
        assert.is_nil(ns.DoneByAlt(990002))
    end)

    it("only with Consolidate alts on, the views count an alt's quests as done", function()
        StartAddon(ns, altDB({ [990001] = true }))
        local first = ns.FindQuestDef(990001)
        assert.are.equal("available", ns.QuestStatus(first))
        local done, total = ns.EntryProgress(ns.entries.zz)
        assert.are.equal(0, done)
        assert.are.equal(2, total)
        ns.char.consolidateAlts = true
        assert.are.equal("done", ns.QuestStatus(first))
        assert.is_false(ns.IsQuestAvailable(first))
        done, total = ns.EntryProgress(ns.entries.zz)
        assert.are.equal(1, done)
        assert.are.equal(2, total)
    end)

    it("an alt's quest also opens the ones that require it, but the level is still the played character's", function()
        ns.AddQuests("zz", { { id = 990004, name = "High", minLevel = 70, requires = { 990001 } } })
        StartAddon(ns, altDB({ [990001] = true }))
        assert.are.equal("locked", ns.QuestStatus(ns.FindQuestDef(990002)))
        ns.char.consolidateAlts = true
        assert.are.equal("available", ns.QuestStatus(ns.FindQuestDef(990002)))
        assert.is_true(ns.IsQuestAvailable(ns.FindQuestDef(990002)))
        local status, reasons = ns.QuestStatus(ns.FindQuestDef(990004))
        assert.are.equal("locked", status)
        assert.are.equal(1, #reasons) -- only the level
        assert.matches("70", reasons[1])
        WowMock.onQuest[990001] = true
        assert.are.equal("active", ns.QuestStatus(ns.FindQuestDef(990001))) -- in its own log, it is in progress
    end)

    it("each character records its class, race, faction and professions", function()
        WowMock.skills = { 171 }
        ns.RegisterEntry({ id = "alchemy", name = "Alchemy", category = "professions", skillLine = 171 })
        StartAddon(ns)
        local me = CompletaoDB.chars["Tester-Realm"]
        assert.are.equal("MAGE", me.class)
        assert.are.equal(8, me.classId)
        assert.are.equal(1, me.raceId)
        assert.are.equal("Alliance", me.faction)
        assert.are.same({ [171] = true }, me.skills)
    end)

    it("with the switch on, the quests of the alts' class, race and faction are shown", function()
        local db = { chars = { ["Orcy-Realm"] = { name = "Orcy", class = "WARRIOR", classId = 1, raceId = 2, faction = "Horde",
            done = {} } } }
        ns.AddQuests("zz", { { id = 990010, name = "Warrior only", classes = 1 }, { id = 990011, name = "Orc only", races = 2 },
            { id = 990012, name = "Horde", faction = "Horde" } })
        StartAddon(ns, db)
        for _, id in ipairs({ 990010, 990011, 990012 }) do assert.is_false(ns.QuestVisible(ns.FindQuestDef(id), ns.entries.zz)) end
        ns.char.consolidateAlts = true
        for _, id in ipairs({ 990010, 990011, 990012 }) do assert.is_true(ns.QuestVisible(ns.FindQuestDef(id), ns.entries.zz)) end
    end)

    it("with the switch on, the class, race and profession entries of the alts have something to do", function()
        local db = { chars = { ["Orcy-Realm"] = { name = "Orcy", class = "WARRIOR", classId = 1, raceId = 2, faction = "Horde",
            skills = { [171] = true }, done = {} } } }
        ns.RegisterEntry({ id = "warrior", name = "Warrior", category = "classes", classFile = "WARRIOR" })
        ns.AddQuests("warrior", { { id = 990020, name = "Warrior quest" } })
        ns.RegisterEntry({ id = "orc", name = "Orc", category = "races", raceId = 2 })
        ns.AddQuests("orc", { { id = 990021, name = "Orc quest", races = 2 } })
        ns.RegisterEntry({ id = "alchemy", name = "Alchemy", category = "professions", skillLine = 171 })
        ns.AddQuests("alchemy", { { id = 990022, name = "Alchemy quest" } })
        StartAddon(ns, db)
        for _, id in ipairs({ "warrior", "orc", "alchemy" }) do assert.is_false(ns.EntryHasWork(ns.entries[id]), id) end
        ns.char.consolidateAlts = true
        for _, id in ipairs({ "warrior", "orc", "alchemy" }) do assert.is_true(ns.EntryHasWork(ns.entries[id]), id) end
    end)

    it("the switch in the title bar turns it on and off", function()
        StartAddon(ns, altDB({ [990001] = true }), { selected = "zz" })
        ns.UI_Toggle()
        local switch = CompletaoFrame.consolidateSwitch
        assert.is_false(switch.on)
        switch._scripts.OnClick(switch)
        assert.is_true(ns.char.consolidateAlts)
        assert.is_true(switch.on)
        switch._scripts.OnClick(switch)
        assert.is_nil(ns.char.consolidateAlts)
        assert.is_false(switch.on)
    end)

    it("the Account-wide filter of 1.7.0 becomes the switch", function()
        StartAddon(ns, nil, { filters = { accountWide = true } })
        assert.is_true(ns.Consolidated())
        assert.is_nil(ns.char.filters.accountWide)
    end)

    it("the tooltip and the details say who did it", function()
        StartAddon(ns, altDB({ [990001] = true }), { selected = "zz" })
        ns.char.consolidateAlts = true
        ns.UI_Toggle()
        local node = ShownNodes()[990001]
        local lines = {}
        GameTooltip.AddLine = function(_, text) lines[#lines + 1] = text end
        node._scripts.OnEnter(node)
        assert.is_truthy(table.concat(lines, "\n"):find("Completed by Altie", 1, true))
        ns.Detail_Show(ns.FindQuestDef(990001))
        assert.is_not_nil(WowMock.Find(function(f) return type(f._text) == "string" and f._text:find("Completed by Altie", 1, true) end))
    end)
end)
