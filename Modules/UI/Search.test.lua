dofile("setupTests.lua")

describe("Search", function()
    local ns, panel

    local function ids(rows)
        local set = {}
        for _, r in ipairs(rows) do set[r.quest.id] = true end
        return set
    end
    local function typeText(text)
        panel.box:SetText(text)
        for _, h in ipairs(panel.box._hooks.OnTextChanged or {}) do h(panel.box) end
    end

    before_each(function()
        WowMock.Reset()
        WowMock.items[2042] = { typeName = "Weapon", subName = "Staves", classID = 2, subclassID = 10 }
        WowMock.items[2041] = { typeName = "Armor", subName = "Leather", classID = 4, subclassID = 2 }
        ns = LoadAddon()
        ns.REWARDS = { [166] = { choice = { 2042, 2041 }, money = 500 }, [167] = { money = 9000 }, [168] = { items = { 2041 } } }
        StartAddon(ns, nil, { selected = "vc" })
        ns.UI_Toggle()
        ns.UI_SetSearchMode(true)
        panel = ns.UI.searchPanel
    end)

    it("with no criteria lists the quests of your level not done yet", function()
        assert.is_true(#ShownRows() > 50)
    end)

    it("quest names are colored by difficulty for the character, not by status", function()
        typeText("defias brother")
        local row = ShownRows()[1]
        assert.are.same({ ns.QuestLevelColorRGB(row.quest.level or row.quest.minLevel) }, { row.name:GetTextColor() })
    end)

    it("titles carry the level prefix", function()
        typeText("defias brother")
        local row = ShownRows()[1]
        assert.matches("^%[%d+D?%+?%] ", row.name:GetText())
    end)

    it("searches by title across all sections", function()
        typeText("defias brother")
        local rows = ShownRows()
        assert.is_true(ids(rows)[166])
        assert.is_true(#rows < 10)
    end)

    it("completed quests only show with Include: Done", function()
        typeText("defias brother")
        WowMock.done[166] = true
        ns.Search_Refresh()
        assert.is_nil(ids(ShownRows())[166])
        local doneCheck = WowMock.Find(function(f)
            return f._kind == "CheckButton" and f.Text == nil and f._parent and f._parent.checks and f == f._parent.checks[3].cb
        end)
        doneCheck:SetChecked(true); doneCheck:Click()
        assert.is_true(ids(ShownRows())[166])
    end)

    it("filters by reward type (Weapon) and disables 'only with items'", function()
        panel.typeButton:Click()
        local weapon = WowMock.Find(function(f) return f.text and f.text._text == "Weapon" and f._scripts.OnClick end)
        weapon:Click()
        local rows = ShownRows()
        assert.are.equal(1, #rows)
        assert.are.equal(166, rows[1].quest.id)
        assert.is_false(panel.itemsOnly:IsEnabled())
        assert.is_true(panel.subButton:IsEnabled())
    end)

    it("only with items drops the ones that only give money", function()
        panel.itemsOnly:SetChecked(true); panel.itemsOnly:Click()
        local found = ids(ShownRows())
        assert.is_nil(found[167])
    end)

    it("sorts by money (most first, and reversed) and shows it in its column", function()
        panel.head.money:Click()
        local rows = ShownRows()
        local function money(r) return (ns.REWARDS[r.quest.id] or {}).money or 0 end
        for i = 2, #rows do assert.is_true(money(rows[i - 1]) >= money(rows[i])) end
        assert.are.equal(money(rows[1]) .. "c", rows[1].money:GetText())
        panel.head.money:Click()
        rows = ShownRows()
        for i = 2, #rows do assert.is_true(money(rows[i - 1]) <= money(rows[i])) end
    end)

    it("sorts by zone (where), reversed on a second click", function()
        panel.head.where:Click()
        local rows = ShownRows()
        for i = 2, #rows do assert.is_true(rows[i - 1].whereText:lower() <= rows[i].whereText:lower()) end
        panel.head.where:Click()
        rows = ShownRows()
        for i = 2, #rows do assert.is_true(rows[i - 1].whereText:lower() >= rows[i].whereText:lower()) end
    end)

    it("sorts by the distance to the next step, nearest first, unknown ones last", function()
        local original = ns.DistanceTo
        ns.DistanceTo = function(loc) return loc and (loc.x or 0) * 10 or nil end
        panel.head.dist:Click()
        local rows = ShownRows()
        local seenUnknown
        for i = 1, #rows do
            local text = rows[i].dist:GetText()
            if text == "" then seenUnknown = true else assert.is_nil(seenUnknown) end
            if i > 1 and text ~= "" and rows[i - 1].dist:GetText() ~= "" then
                assert.is_true(ns.DistanceTo(ns.QuestSteps(rows[i - 1].quest)[1].loc) <= ns.DistanceTo(ns.QuestSteps(rows[i].quest)[1].loc))
            end
        end
        panel.head.dist:Click() -- reversed: the unknown ones still go last
        seenUnknown = nil
        for _, row in ipairs(ShownRows()) do
            if row.dist:GetText() == "" then seenUnknown = true else assert.is_nil(seenUnknown) end
        end
        ns.DistanceTo = original
    end)

    it("distances read in yards, or thousands of yards", function()
        local original = ns.DistanceTo
        ns.DistanceTo = function() return 350 end
        ns.Search_Refresh()
        panel.head.dist:Click()
        assert.are.equal("350 yd", ShownRows()[1].dist:GetText())
        ns.DistanceTo = function() return 1300 end
        panel.head.dist:Click()
        assert.are.equal("1.3k yd", ShownRows()[1].dist:GetText())
        ns.DistanceTo = original
    end)

    it("redraws the distances when the player moves, and not while standing still", function()
        local original, pos = ns.DistanceTo, 100
        local x = 0.5
        ns.DistanceTo = function() return pos end
        ns.PlayerPosition = function() return 1, x, 0.5 end
        panel.head.dist:Click()
        local onUpdate = panel._scripts.OnUpdate
        onUpdate(panel, 1) -- first look at the position
        assert.are.equal("100 yd", ShownRows()[1].dist:GetText())
        pos = 200
        onUpdate(panel, 1) -- same spot: nothing to redraw
        assert.are.equal("100 yd", ShownRows()[1].dist:GetText())
        x = 0.6
        onUpdate(panel, 1)
        assert.are.equal("200 yd", ShownRows()[1].dist:GetText())
        ns.DistanceTo = original
    end)

    it("remembers the table's order between sessions", function()
        panel.head.dist:Click()
        panel.head.dist:Click() -- distance, reversed
        assert.are.same({ key = "distance", desc = true }, ns.char.tableSort)
        WowMock.Reset()
        local reopened = LoadAddon()
        StartAddon(reopened, nil, { selected = "vc", tableSort = { key = "money", desc = false } })
        reopened.UI_Toggle()
        reopened.UI_SetSearchMode(true)
        assert.is_not_nil(WowMock.Find(function(f) return f._text == "Money ^" end))
    end)

    it("sorts by level and by title", function()
        panel.head.level:Click() -- already sorted by ascending level: one click reverses it
        local rows = ShownRows()
        assert.is_true((rows[1].quest.level or 0) >= (rows[#rows].quest.level or 0))
        panel.head.name:Click()
        rows = ShownRows()
        assert.is_true(rows[1].quest.name:lower() <= rows[#rows].quest.name:lower())
    end)

    local function chainButton()
        return WowMock.Find(function(f) return f._text == "View chain" and f._scripts.OnClick and f:IsShown() end)
    end

    it("clicking a result shows its details below the table, without leaving it", function()
        typeText("defias brother")
        local row = ShownRows()[1]
        row:Click()
        assert.is_true(panel:IsShown())
        assert.are.equal(row.quest.id, ns.Detail_Current().id)
        assert.are.equal("search", ns.Search_Mode())
    end)

    it("'View chain' is always there; it takes a quest that is part of a chain to its tree, and only those", function()
        local chained, alone
        for _, d in ipairs(ns.entryList) do
            for _, q in ipairs(d.quests) do
                if ns.IsInChain(q) then chained = chained or q else alone = alone or q end
            end
        end
        ns.Detail_Show(chained)
        assert.is_not_nil(chainButton())
        assert.is_true(chainButton():IsEnabled())
        chainButton():Click()
        assert.is_false(panel:IsShown())
        assert.are.equal(chained.id, ns.Detail_Current().id)
        ns.UI_SetSearchMode(true, "search")
        ns.Detail_Show(alone)
        assert.is_not_nil(chainButton())
        assert.is_false(chainButton():IsEnabled())
    end)

    describe("quest log view", function()
        before_each(function()
            WowMock.log = { { isHeader = true, title = "Westfall" }, { questID = 166, title = "The Defias Brotherhood", level = 22 },
                { isHeader = true, title = "Ashenvale" }, { questID = 999999, title = "Unknown Quest", level = 25 } }
            WowMock.onQuest[166], WowMock.onQuest[999999] = true, true
            ns.UI_SetSearchMode(true, "log")
        end)

        it("lists the quests in the log, without the form", function()
            local rows = ShownRows()
            assert.are.equal(2, #rows)
            assert.is_false(panel.box:IsShown())
        end)

        it("a quest missing from the addon's data shows its zone and its details, with no chain", function()
            local unknown
            for _, r in ipairs(ShownRows()) do if r.quest.id == 999999 then unknown = r end end
            assert.are.equal("Ashenvale", unknown.whereText)
            unknown:Click()
            assert.are.equal(999999, ns.Detail_Current().id)
            assert.is_false(chainButton():IsEnabled())
        end)
    end)

    describe("tracked quests view", function()
        local tracked, saved
        before_each(function()
            WowMock.log = { { isHeader = true, title = "Westfall" }, { questID = 166, title = "The Defias Brotherhood", level = 22 },
                { isHeader = true, title = "Ashenvale" }, { questID = 999999, title = "Unknown Quest", level = 25 } }
            WowMock.onQuest[166], WowMock.onQuest[999999] = true, true
            tracked, saved = { [999999] = true }, C_QuestLog.GetQuestWatchType
            C_QuestLog.GetQuestWatchType = function(id) return tracked[id] and 0 or nil end
            ns.UI_SetSearchMode(true, "tracked")
        end)
        after_each(function() C_QuestLog.GetQuestWatchType = saved end)

        it("the search table has no status icons", function()
            ns.UI_SetSearchMode(true, "search")
            assert.is_false(ShownRows()[1].status:IsShown())
        end)

        it("lists only the quests of the log that are being tracked, without the form", function()
            local rows = ShownRows()
            assert.are.equal(1, #rows)
            assert.are.equal(999999, rows[1].quest.id)
            assert.is_false(panel.box:IsShown())
            assert.are.equal("tracked", ns.Search_Mode())
        end)

        it("lists the steps under each quest, with a button to set the waypoint of each", function()
            local spot = { npc = "Boar", area = 12, x = 40, y = 50 }
            local realSteps, realCan, realWaypoint = ns.QuestSteps, ns.CanShowMap, ns.SetWaypoint
            ns.QuestSteps = function()
                return {
                    { kind = "start", label = "Start: X", done = true },
                    { kind = "obj", label = "Kill boars", progress = "3/10", loc = spot, current = true },
                    { kind = "obj", label = "Find the cave", done = true, area = 12 },
                    { kind = "finish", label = "Turn in: Y" },
                }, 2
            end
            ns.CanShowMap = function() return true end
            ns.IsReadyToTurnIn = function() return false end
            local setTo
            ns.SetWaypoint = function(loc, title) setTo = { loc, title } end
            ns.CanWaypoint = function(loc) return loc.x ~= nil end
            ns.Search_Refresh()
            local labels, buttons = {}, {}
            for _, f in ipairs(WowMock.frames) do
                if f:IsShown() and type(f._text) == "string" and f._text:find("Kill boars", 1, true) then labels[#labels + 1] = f._text end
                if f._kind == "Button" and f.loc and f:IsShown() then buttons[#buttons + 1] = f end
            end
            assert.are.equal(1, #labels)
            assert.matches("3/10", labels[1])
            assert.matches("ffd100", labels[1]) -- the current step is in gold
            assert.is_true(#buttons >= 1)
            local kill
            for _, b in ipairs(buttons) do if b.title == "Kill boars" then kill = b end end
            kill:Click()
            assert.are.same({ spot, "Kill boars" }, setTo)
            assert.is_nil(WowMock.Find(function(f) return f:IsShown() and type(f._text) == "string" and f._text:find("Turn in", 1, true) end))
            -- the clicked step and its quest are marked
            local focusTag = ShownRows()[1].quest.id .. ":2"
            assert.are.equal(focusTag, kill.tag)
            ns.FocusTag = function() return focusTag end
            ns.Search_Refresh()
            local marked = WowMock.Find(function(f) return f._kind == "Button" and f.tag == focusTag and f.mark:IsShown() end)
            assert.is_not_nil(marked)
            assert.are.same({ 1, 0.82, 0, 1 }, { ShownRows()[1]:GetBackdropBorderColor() })
            ns.FocusTag = function() return nil end
            ns.Search_Refresh()
            assert.is_false(marked.mark:IsShown())
            ns.QuestSteps, ns.CanShowMap, ns.SetWaypoint = realSteps, realCan, realWaypoint
        end)

        it("a quest ready to turn in shows only the turn-in, and its icon says so", function()
            local realSteps = ns.QuestSteps
            ns.QuestSteps = function()
                return {
                    { kind = "start", label = "Start: X", done = true },
                    { kind = "obj", label = "Kill boars", progress = "10/10", done = true },
                    { kind = "finish", label = "Turn in: Y", current = true, loc = { area = 12, x = 1, y = 2 } },
                }, 3
            end
            ns.IsReadyToTurnIn = function() return true end
            ns.Search_Refresh()
            local function shown(text)
                return WowMock.Find(function(f) return f:IsShown() and type(f._text) == "string" and f._text:find(text, 1, true) end)
            end
            assert.is_not_nil(shown("Turn in: Y"))
            assert.is_nil(shown("Kill boars"))
            local status = ShownRows()[1].status
            assert.is_true(status:IsShown())
            assert.matches("ActiveQuestIcon", status._set.SetTexture[1]) -- the "?" (no atlases in the mock)
            ns.IsReadyToTurnIn = function() return false end
            ns.Search_Refresh()
            assert.matches("IncompleteQuestIcon", ShownRows()[1].status._set.SetTexture[1])
            ns.QuestSteps = realSteps
        end)

        it("the tree stays hidden behind the table, also with a quest's details open and after redraws", function()
            local tree = ns.UI.treeScroll
            assert.is_false(tree:IsShown())
            ShownRows()[1]:Click()
            assert.is_false(tree:IsShown())
            ns.UI_Refresh()
            assert.is_false(tree:IsShown())
            FireEvent("QUEST_LOG_UPDATE")
            assert.is_false(tree:IsShown())
            ns.Detail_Hide()
            ns.UI_Refresh()
            assert.is_false(tree:IsShown())
            -- and it comes back in the tree view
            ns.UI_SetSearchMode(false)
            assert.is_true(tree:IsShown())
        end)

        it("follows the tracker and says so when nothing is tracked", function()
            tracked = { [166] = true, [999999] = true }
            ns.Search_Refresh()
            assert.are.equal(2, #ShownRows())
            tracked = {}
            ns.Search_Refresh()
            assert.are.equal(0, #ShownRows())
            assert.is_true(panel.empty:IsShown())
        end)
    end)
end)
