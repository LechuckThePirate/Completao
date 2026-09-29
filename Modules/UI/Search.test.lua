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

    it("sorts by level and by title", function()
        panel.head.level:Click() -- already sorted by ascending level: one click reverses it
        local rows = ShownRows()
        assert.is_true((rows[1].quest.level or 0) >= (rows[#rows].quest.level or 0))
        panel.head.name:Click()
        rows = ShownRows()
        assert.is_true(rows[1].quest.name:lower() <= rows[#rows].quest.name:lower())
    end)

    it("clicking a result opens its tree with the quest selected", function()
        typeText("defias brother")
        local row = ShownRows()[1]
        row:Click()
        assert.is_false(panel:IsShown())
        assert.are.equal(row.quest.id, ns.Detail_Current().id)
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

        it("a quest missing from the addon's data shows its zone and opens in the game's log", function()
            local unknown
            for _, r in ipairs(ShownRows()) do if r.quest.id == 999999 then unknown = r end end
            assert.are.equal("Ashenvale", unknown.whereText)
            local opened
            _G.QuestMapFrame_OpenToQuestDetails = function(id) opened = id end
            unknown:Click()
            _G.QuestMapFrame_OpenToQuestDetails = nil
            assert.are.equal(999999, opened)
        end)
    end)
end)
