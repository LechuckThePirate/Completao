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

    it("only with Account-wide on, the views count an alt's quests as done", function()
        StartAddon(ns, altDB({ [990001] = true }))
        local first = ns.FindQuestDef(990001)
        assert.are.equal("available", ns.QuestStatus(first))
        local done, total = ns.EntryProgress(ns.entries.zz)
        assert.are.equal(0, done)
        assert.are.equal(2, total)
        ns.char.filters.accountWide = true
        assert.are.equal("done", ns.QuestStatus(first))
        assert.is_false(ns.IsQuestAvailable(first))
        done, total = ns.EntryProgress(ns.entries.zz)
        assert.are.equal(1, done)
        assert.are.equal(2, total)
    end)

    it("what the character can take still goes by its own quests", function()
        StartAddon(ns, altDB({ [990001] = true }))
        ns.char.filters.accountWide = true
        local status, reasons = ns.QuestStatus(ns.FindQuestDef(990002))
        assert.are.equal("locked", status)
        assert.matches("First", reasons[1])
        WowMock.onQuest[990001] = true
        assert.are.equal("active", ns.QuestStatus(ns.FindQuestDef(990001))) -- in its own log, it is in progress
    end)

    it("the tooltip and the details say who did it", function()
        StartAddon(ns, altDB({ [990001] = true }), { selected = "zz" })
        ns.char.filters.accountWide = true
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
