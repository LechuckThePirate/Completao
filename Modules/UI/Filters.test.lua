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
        -- each view keeps its own: a change in the tree is not one in the search
        local check = toolbarMenu().checks.hideDone
        check:SetChecked(true); check:Click()
        assert.is_true(ns.char.filters.hideDone)
        ns.UI_SetSearchMode(true, "search")
        assert.is_false(searchMenu().checks.hideDone:GetChecked())
        assert.are.equal("Filters", searchMenu():GetText())
        searchMenu().checks.chainsOnly:SetChecked(true); searchMenu().checks.chainsOnly:Click()
        assert.is_true(ns.char.viewFilters.search.chainsOnly)
        assert.is_nil(ns.char.filters.chainsOnly)
        ns.UI_SetSearchMode(true, "log") -- nor in the quest log
        assert.is_false(searchMenu().checks.chainsOnly:GetChecked())
        ns.UI_SetSearchMode(true, "search")
        assert.is_true(searchMenu().checks.chainsOnly:GetChecked()) -- and the search kept it
        ns.UI_OpenQuest("vc", vc.quests[1].id) -- back in the tree: its own
        assert.is_false(toolbarMenu().checks.chainsOnly:GetChecked())
        assert.is_true(toolbarMenu().checks.hideDone:GetChecked())
    end)

    it("Show other faction is one for the whole addon, whatever the view", function()
        ns.UI_SetSearchMode(true, "log")
        searchMenu().checks.otherFaction:SetChecked(true); searchMenu().checks.otherFaction:Click()
        assert.is_true(ns.char.filters.otherFaction)
        ns.UI_SetSearchMode(true, "search")
        assert.is_true(searchMenu().checks.otherFaction:GetChecked())
        assert.is_nil((ns.char.viewFilters or {}).log and ns.char.viewFilters.log.otherFaction)
    end)

    it("with Same filters in every view they are one set, the tree's", function()
        ns.char.sharedFilters = true
        ns.UI_FiltersChanged()
        ns.UI_SetSearchMode(true, "search")
        searchMenu().checks.hideLow:SetChecked(true); searchMenu().checks.hideLow:Click()
        assert.is_true(ns.char.filters.hideLow)
        ns.UI_SetSearchMode(true, "log")
        assert.is_true(searchMenu().checks.hideLow:GetChecked())
        ns.UI_OpenQuest("vc", vc.quests[1].id)
        assert.is_true(toolbarMenu().checks.hideLow:GetChecked())
        ns.char.sharedFilters = nil
        ns.UI_FiltersChanged()
        ns.UI_SetSearchMode(true, "search")
        assert.is_false(searchMenu().checks.hideLow:GetChecked()) -- the search's own again, untouched
    end)

    it("the reward type is a filter like the rest, and says so in the line and the count", function()
        ns.UI_SetSearchMode(true, "search")
        ns.ViewFilters().rewardClass = 2
        ns.RefreshFilterMenus()
        assert.is_false(searchMenu().itemsOnly:IsEnabled())
        assert.matches("^Reward type:", ns.FilterParts()[1])
        assert.are.equal("Filters (1)", searchMenu():GetText())
    end)

    it("the line of every view names what is on, from the same words", function()
        ns.char.filters = { hideLow = true, chainsOnly = true }
        assert.are.same({ "Hide low level", "Chains only" }, ns.FilterParts())
        ns.UI_Refresh()
        assert.matches("Filters: Hide low level  |  Chains only", ns.UI.filterSummary.text._text, 1, true)
        ns.UI_SetSearchMode(true, "search")
        assert.are.same({}, ns.FilterParts()) -- the search's own are none
        ns.ViewFilters().hideDone = true
        assert.are.same({ "Hide completed" }, ns.FilterParts())
        ns.UI_FiltersChanged()
        assert.matches("Filters: Hide completed", ns.UI.searchPanel.summary.text._text, 1, true)
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

        it("Chains only keeps the chains and hides the loose quests, the ones in the log too", function()
            ns.char.filters.chainsOnly = true
            assert.is_true(pass(chained()))
            local q = loose()
            assert.is_false(pass(q))
            WowMock.onQuest[q.id] = true -- doing it doesn't make it part of a chain
            assert.is_false(pass(q))
            WowMock.onQuest[chained().id] = true
            assert.is_true(pass(chained()))
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
        ns.ViewFilters("log").itemsOnly = true -- its own, not the tree's
        ns.UI_FiltersChanged()
        assert.are.same({ [166] = true }, shown()) -- the same "only with item rewards" as everywhere
        ns.ViewFilters("log").itemsOnly = nil
        ns.UI_FiltersChanged()
        assert.are.same({ [166] = true, [167] = true }, shown())
    end)
end)
