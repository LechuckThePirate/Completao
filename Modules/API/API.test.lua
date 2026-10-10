dofile("setupTests.lua")

describe("CompletaoAPI", function()
    local ns, questID

    before_each(function()
        WowMock.Reset()
        ns = OpenAddon("vc")
        ns.UI_Toggle() -- closed: the API has to open it
        questID = ns.entries.vc.quests[1].id
    end)

    it("is a global with a version", function()
        assert.are.equal(1, CompletaoAPI.version)
    end)

    it("knows the quests of its trees, and only those", function()
        assert.is_true(CompletaoAPI.HasQuest(questID))
        assert.is_false(CompletaoAPI.HasQuest(99999999))
        assert.is_false(CompletaoAPI.HasQuest(nil))
        assert.is_false(CompletaoAPI.HasQuest("Linen Cloth"))
    end)

    it("opens the window on a quest, with its panel", function()
        assert.is_false(ns.UI:IsShown())
        assert.is_true(CompletaoAPI.ShowQuest(questID))
        assert.is_true(ns.UI:IsShown())
        assert.are.equal(questID, ns.Detail_Current().id)
    end)

    it("an unknown quest opens nothing", function()
        assert.is_false(CompletaoAPI.ShowQuest(99999999))
        assert.is_false(ns.UI:IsShown())
    end)
end)
