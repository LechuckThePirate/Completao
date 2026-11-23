dofile("setupTests.lua")

describe("Filters (one set for every view)", function()
    local ns, vc

    before_each(function()
        WowMock.Reset()
        ns = OpenAddon("vc")
        vc = ns.entries.vc
        ns.char.filters = {}
    end)

    local function toolbarMenu()
        return ns.UI.filtersButton
    end
    local function searchMenu()
        return ns.UI.searchPanel.filters
    end

    it("every view's menu has the same options, in the same words, over the same store", function()
        local keys = {}
        for _, opt in ipairs(ns.FILTER_OPTIONS) do keys[#keys + 1] = opt.key end
        assert.are.same({ "hideLow", "hideHigh", "hideDone", "hideRepeatable", "otherFaction", "chainsOnly", "itemsOnly" }, keys)
        for _, key in ipairs(keys) do
            assert.is_not_nil(toolbarMenu().checks[key], key)
            assert.is_not_nil(searchMenu().checks[key], key)
            assert.are.equal(toolbarMenu().checks[key].label._text, searchMenu().checks[key].label._text)
        end
        -- a change in one is seen in the other
        local check = toolbarMenu().checks.hideDone
        check:SetChecked(true); check:Click()
        assert.is_true(ns.char.filters.hideDone)
        assert.is_true(searchMenu().checks.hideDone:GetChecked())
        searchMenu().checks.hideLow:SetChecked(true); searchMenu().checks.hideLow:Click()
        assert.is_true(toolbarMenu().checks.hideLow:GetChecked())
        assert.are.equal("Filters (2)", toolbarMenu():GetText())
        assert.are.equal("Filters (2)", searchMenu():GetText())
    end)

    it("the reward type is the same filter everywhere, and says so in both lines", function()
        ns.char.filters.rewardClass = 2
        ns.RefreshFilterMenus()
        assert.is_false(toolbarMenu().itemsOnly:IsEnabled())
        assert.is_false(searchMenu().itemsOnly:IsEnabled())
        assert.matches("^Reward type:", ns.FilterParts()[1])
        assert.are.equal("Filters (1)", searchMenu():GetText())
    end)

    it("the line of every view names what is on, from the same list", function()
        ns.char.filters = { hideLow = true, chainsOnly = true }
        assert.are.same({ "Hide low level", "Chains only" }, ns.FilterParts())
        ns.UI_Refresh()
        assert.matches("Filters: Hide low level  |  Chains only", ns.UI.filterSummary.text._text, 1, true)
        ns.UI_SetSearchMode(true, "search")
        assert.matches("Filters: Hide low level  |  Chains only", ns.UI.searchPanel.summary.text._text, 1, true)
    end)

    describe("the predicate", function()
        local function pass(q, opts) return ns.QuestFilter(vc, opts)(q) end
        local function chained()
            for _, q in ipairs(vc.quests) do
                if ns.IsInChain(q) and ns.QuestVisible(q, vc) then return q end
            end
        end
        local function loose()
            for _, q in ipairs(vc.quests) do
                if not ns.IsInChain(q) and ns.QuestVisible(q, vc) then return q end
            end
        end

        it("lets everything through with no filter", function()
            assert.is_true(pass(chained()))
            assert.is_true(pass(loose()))
        end)

        it("completed ones go with Hide completed, unless they are in the log", function()
            local q = loose()
            WowMock.done[q.id] = true
            ns.char.filters.hideDone = true
            assert.is_false(pass(q))
            WowMock.onQuest[q.id] = true
            assert.is_true(pass(q))
        end)

        it("Chains only keeps the chains and the quests in the log", function()
            ns.char.filters.chainsOnly = true
            assert.is_true(pass(chained()))
            local q = loose()
            assert.is_false(pass(q))
            WowMock.onQuest[q.id] = true
            assert.is_true(pass(q))
        end)

        it("by level a chain is hidden as a whole, never cut in half", function()
            WowMock.level = 60 -- every quest of the entry is grey
            ns.char.filters.hideLow = true
            assert.is_false(pass(chained()))
            local q = chained()
            WowMock.done[ns.ParentsOf(q)[1] or q.id] = true -- started: shown whatever its level
            WowMock.done[q.id] = true
            assert.is_true(pass(q))
        end)

        it("the title typed in is read by the view's own way, and the rewards filter applies", function()
            local q = chained()
            assert.is_true(pass(q, { text = q.name:lower():sub(1, 5) }))
            assert.is_false(pass(q, { text = "zzzzzz" }))
            assert.is_true(pass(q, { text = "zzzzzz", matchText = function() return true end }))
            ns.REWARDS = {}
            ns.char.filters.itemsOnly = true
            assert.is_false(pass(q))
            ns.REWARDS = { [q.id] = { items = { 1 } } }
            assert.is_true(pass(q))
        end)
    end)

    it("the tables of the quest log apply the same filters and their own title box", function()
        WowMock.log = { { isHeader = true, title = "Zone" }, { questID = 166, title = "The Defias Brotherhood", level = 22 },
            { questID = 167, title = "Other", level = 22 } }
        WowMock.onQuest[166], WowMock.onQuest[167] = true, true
        ns.REWARDS = { [166] = { money = 1, items = { 2041 } } }
        ns.UI_SetSearchMode(true, "log")
        local function shown()
            local list = {}
            for _, r in ipairs(ShownRows()) do list[r.quest.id] = true end
            return list
        end
        assert.are.same({ [166] = true, [167] = true }, shown())
        ns.char.filters.itemsOnly = true
        ns.UI_FiltersChanged()
        assert.are.same({ [166] = true }, shown()) -- the same "only with item rewards" as everywhere
        ns.char.filters = {}
        ns.UI_FiltersChanged()
        assert.are.same({ [166] = true, [167] = true }, shown())
    end)
end)
