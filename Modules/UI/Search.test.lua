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
        panel.scroll._h = 100000 -- tall enough for every row to be in view
        ns.Search_Refresh()
    end)

    it("only makes rows for the results in view, and fills them again on scrolling", function()
        panel.scroll._h = 10 * 22
        ns.Search_Refresh()
        local rows = ShownRows()
        assert.is_true(#rows <= 12)
        assert.is_true(panel.content:GetHeight() > 50 * 22) -- the table is as tall as all the results
        local firstQuest = rows[1].quest.id
        panel.scroll:SetVerticalScroll(30 * 22)
        for _, h in ipairs(panel.scroll._hooks.OnVerticalScroll or {}) do h(panel.scroll, 30 * 22) end
        rows = ShownRows()
        assert.is_true(#rows <= 12)
        assert.are_not.equal(firstQuest, rows[1].quest.id)
        assert.are.equal(-30 * 22, select(3, rows[1]:GetPoint(1))) -- placed where the result sits in the table
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

    it("completed quests only show with Include completed", function()
        typeText("defias brother")
        WowMock.done[166] = true
        ns.Search_Refresh()
        assert.is_nil(ids(ShownRows())[166])
        local doneCheck = panel.filters.checks.done
        doneCheck:SetChecked(true); doneCheck:Click()
        assert.is_true(ids(ShownRows())[166])
    end)

    it("the reward type is picked inside the Filters drop-down, counts as a filter and Clear filters takes it off", function()
        assert.are.equal(panel.filters.menu, panel.typeButton:GetParent():GetParent())
        panel.typeButton:Click()
        WowMock.Find(function(f) return f.text and f.text._text == "Weapon" and f._scripts.OnClick end):Click()
        assert.are.equal("Weapon", panel.typeButton:GetText())
        assert.are.equal("Filters (1)", panel.filters:GetText())
        assert.is_true(panel.filters.clear:IsShown())
        panel.filters.clear._scripts.OnClick(panel.filters.clear)
        assert.are.equal("Any", panel.typeButton:GetText())
        assert.are.equal("Filters", panel.filters:GetText())
        assert.is_true(panel.itemsOnly:IsEnabled())
    end)

    it("a pick in the reward type's list doesn't close the Filters drop-down", function()
        local menu = panel.filters.menu
        panel.filters._scripts.OnClick(panel.filters)
        assert.is_true(menu:IsShown())
        local onPopup = ns.PopupMenu_IsMouseOver
        ns.PopupMenu_IsMouseOver = function() return true end
        menu._scripts.OnEvent(menu, "GLOBAL_MOUSE_DOWN")
        assert.is_true(menu:IsShown())
        ns.PopupMenu_IsMouseOver = function() return false end
        menu._scripts.OnEvent(menu, "GLOBAL_MOUSE_DOWN")
        assert.is_false(menu:IsShown()) -- a click anywhere else does
        ns.PopupMenu_IsMouseOver = onPopup
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

    it("has an XP column, sorts by it (most first, and reversed) and shows 0 for a quest with none", function()
        ns.REWARDS[166].xp = 12345
        ns.REWARDS[167].xp = 20
        panel.head.xp:Click()
        local rows = ShownRows()
        local function xp(r) return ns.QuestXP(r.quest.id) end
        for i = 2, #rows do assert.is_true(xp(rows[i - 1]) >= xp(rows[i])) end
        assert.are.equal(166, rows[1].quest.id)
        assert.are.equal("12345", rows[1].xp:GetText())
        assert.are.equal("0", rows[#rows].xp:GetText())
        panel.head.xp:Click()
        rows = ShownRows()
        for i = 2, #rows do assert.is_true(xp(rows[i - 1]) <= xp(rows[i])) end
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

    it("walking only redraws the distances: the search isn't done again", function()
        local x, calls = 0.5, 0
        ns.PlayerPosition = function() return 1, x, 0.5 end
        local onUpdate = panel._scripts.OnUpdate
        onUpdate(panel, 1)
        local original = ns.QuestVisible
        ns.QuestVisible = function(...) calls = calls + 1 return original(...) end
        local done = C_QuestLog.IsQuestFlaggedCompleted
        local asked = 0
        C_QuestLog.IsQuestFlaggedCompleted = function(id) asked = asked + 1 return done(id) end
        for step = 1, 5 do
            x = 0.5 + step / 100
            onUpdate(panel, 1)
        end
        C_QuestLog.IsQuestFlaggedCompleted = done
        ns.QuestVisible = original
        assert.are.equal(0, calls)
        assert.is_true(asked < #ShownRows()) -- a search asks it of every quest
    end)

    it("sorting by distance doesn't work out the steps of the quests that aren't in the log", function()
        local original, stepped = ns.QuestSteps, {}
        ns.QuestSteps = function(q) stepped[#stepped + 1] = q.id return original(q) end
        panel.head.dist:Click()
        ns.QuestSteps = original
        assert.are.equal(0, #stepped)
    end)

    it("on a client with no IsOnQuest of its own, reads the log once per search, not once per quest", function()
        ns.UI_Toggle() -- this test's own copy of the addon is loaded below; the one from before_each stays closed
        -- the old quest log API, which QuestLogCompat fills C_QuestLog's gaps from (as on TBC Anniversary)
        local game, savedTitle, savedNum = _G.C_QuestLog, _G.GetQuestLogTitle, _G.GetNumQuestLogEntries
        local log = { { "Zone", nil, nil, 1 }, { "A quest", 18, 0, nil, nil, nil, nil, 166 } }
        local reads = 0
        _G.GetNumQuestLogEntries = function() return #log end
        _G.GetQuestLogTitle = function(i)
            reads = reads + 1
            if log[i] then return (_G.unpack or _G.table.unpack)(log[i], 1, 8) end
        end
        local stripped = {}
        for k, v in pairs(game) do stripped[k] = v end
        for _, k in ipairs({ "IsOnQuest", "GetTitleForQuestID", "GetInfo", "GetNumQuestLogEntries", "GetLogIndexForQuestID" }) do
            stripped[k] = nil
        end
        _G.C_QuestLog = stripped
        local rowsShown
        local ok, err = pcall(function()
            ns = LoadAddon()
            StartAddon(ns, nil, { selected = "vc" })
            ns.UI_Toggle()
            ns.UI_SetSearchMode(true)
            panel = ns.UI.searchPanel
            panel.scroll._h = 100000 -- tall enough for every row to be in view
            reads = 0
            typeText("a")
            rowsShown = #ShownRows()
        end)
        _G.C_QuestLog, _G.GetQuestLogTitle, _G.GetNumQuestLogEntries = game, savedTitle, savedNum
        assert(ok, err)
        assert.is_true(rowsShown > 20)
        assert.is_true(reads > 0)
        assert.is_true(reads < 20) -- a scan per quest would be thousands
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
        return WowMock.Find(function(f) return f.tip == "View chain" and f._scripts.OnClick and f:IsShown() end)
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

        it("is the played character's own, whatever Consolidate alts says", function()
            CompletaoDB.chars["Altie-Realm"] = { name = "Altie", realm = "Realm", done = { [166] = true, [167] = true } }
            ns.SetConsolidated(true)
            ns.Search_Refresh()
            local rows = ShownRows()
            assert.are.same({ [166] = true, [999999] = true }, ids(rows))
            for _, r in ipairs(rows) do assert.is_true(r.status:IsShown()) end -- in progress, not done by the alt
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

    describe("group by", function()
        -- what the table shows from top to bottom: group names ("# Westfall") and quest ids
        local function layout()
            local items = {}
            for _, f in ipairs(WowMock.frames) do
                if f._shown and (f.fold or (f.quest and f.whereText)) then items[#items + 1] = f end
            end
            table.sort(items, function(a, b) return select(3, a:GetPoint(1)) > select(3, b:GetPoint(1)) end)
            local out = {}
            for _, f in ipairs(items) do
                out[#out + 1] = f.fold and ("# " .. f.text:GetText():match("^(.-)  ")) or f.quest.id
            end
            return out
        end
        local function groupBy(label)
            panel.groupButton:Click()
            WowMock.Find(function(f) return f:IsShown() and f.text and f.text._text == label and f._scripts.OnClick end):Click()
        end
        local real
        before_each(function()
            real = ns.IsReadyToTurnIn
            WowMock.log = { { isHeader = true, title = "Westfall" }, { questID = 166, title = "The Defias Brotherhood", level = 22 },
                { questID = 999998, title = "Zeta", level = 30 },
                { isHeader = true, title = "Ashenvale" }, { questID = 999999, title = "Unknown Quest", level = 25 },
                { questID = 999997, title = "Alpha", level = 20 } }
            for _, id in ipairs({ 166, 999997, 999998, 999999 }) do WowMock.onQuest[id] = true end
            ns.UI_SetSearchMode(true, "log")
        end)
        after_each(function() ns.IsReadyToTurnIn = real end)

        it("is off by default, and only in the log views", function()
            assert.are.same({ 999997, 166, 999999, 999998 }, layout())
            assert.is_true(panel.groupButton:IsShown())
            assert.are.equal("None", panel.groupButton:GetText())
            ns.UI_SetSearchMode(true, "search")
            assert.is_false(panel.groupButton:IsShown())
        end)

        it("by zone keeps the header's order inside each group, also reversed", function()
            groupBy("Zone")
            assert.are.equal("Zone", panel.groupButton:GetText())
            assert.are.same({ "# Ashenvale", 999997, 999999, "# Westfall", 166, 999998 }, layout())
            panel.head.level:Click() -- level, highest first: the zones stay in their order
            assert.are.same({ "# Ashenvale", 999999, 999997, "# Westfall", 999998, 166 }, layout())
            panel.head.where:Click()
            panel.head.where:Click() -- by zone, reversed: so are the groups
            assert.are.equal("# Westfall", layout()[1])
        end)

        it("by level goes the way the Level header does", function()
            groupBy("Level")
            assert.are.same({ "# Level 20", 999997, "# Level 22", 166, "# Level 25", 999999, "# Level 30", 999998 }, layout())
            panel.head.level:Click()
            assert.are.equal("# Level 30", layout()[1])
        end)

        it("by status puts the quests ready to turn in first", function()
            ns.IsReadyToTurnIn = function(id) return id == 999998 end
            groupBy("Status")
            assert.are.same({ "# Ready to turn in", 999998, "# In progress", 999997, 166, 999999 }, layout())
        end)

        it("by section puts the quests the addon doesn't know last", function()
            groupBy("Section")
            local shown = layout()
            assert.are.equal(166, shown[2])
            assert.are.same({ "# Other", 999997, 999999, 999998 }, { shown[3], shown[4], shown[5], shown[6] })
        end)

        it("a click on a group folds it and another unfolds it", function()
            groupBy("Zone")
            local row = WowMock.Find(function(f) return f:IsShown() and f.fold and f.group == "Ashenvale" end)
            row:Click()
            assert.are.same({ "# Ashenvale", "# Westfall", 166, 999998 }, layout())
            row:Click()
            assert.are.equal(6, #layout())
        end)

        it("is saved per view: the tracked quests have their own", function()
            groupBy("Zone")
            assert.are.same({ log = "zone" }, ns.char.tableGroup)
            ns.UI_SetSearchMode(true, "tracked")
            assert.are.equal("None", panel.groupButton:GetText())
            ns.UI_SetSearchMode(true, "log")
            assert.are.equal("Zone", panel.groupButton:GetText())
            groupBy("None")
            assert.are.same({}, ns.char.tableGroup)
        end)

        it("in the tracked view the steps stay under their quest", function()
            local realSteps = ns.QuestSteps
            ns.QuestSteps = function(q) return { { kind = "obj", label = "Step of " .. q.id, current = true } }, 1 end
            ns.UI_SetSearchMode(true, "tracked")
            groupBy("Zone")
            ns.QuestSteps = realSteps
            local step = WowMock.Find(function(f) return f:IsShown() and f.text and f.text._text
                and f.text._text:find("Step of 999997", 1, true) end)
            local quest = WowMock.Find(function(f) return f._shown and f.quest and f.whereText and f.quest.id == 999997 end)
            assert.are.equal(select(3, quest:GetPoint(1)) - 22, select(3, step:GetPoint(1)))
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

        it("on a client with no way to ask what is tracked, counts the quests in the log (they are tracked as taken)", function()
            C_QuestLog.GetQuestWatchType = nil
            WowMock.onQuest[166] = nil
            assert.is_true(ns.IsQuestTracked(999999))
            assert.is_false(ns.IsQuestTracked(166)) -- not in the log
        end)

        it("on the clients that keep their own list, follows it", function()
            C_QuestLog.GetQuestWatchType = nil
            WowMock.onQuest[166] = true
            ns.flavor = "tbc"
            assert.is_true(ns.IsQuestTracked(166))
            ns.UntrackQuest(166)
            assert.is_false(ns.IsQuestTracked(166))
            assert.is_true(ns.IsQuestTracked(999999))
            ns.flavor = nil
        end)

        it("shift-click on a quest of the log tracks or untracks it, without opening its details", function()
            C_QuestLog.GetQuestWatchType = nil
            ns.flavor = "tbc"
            ns.UI_SetSearchMode(true, "log")
            local function rowOf(id)
                for _, r in ipairs(ShownRows()) do if r.quest.id == id then return r end end
            end
            WowMock.shift = true
            rowOf(999999):GetScript("OnClick")(rowOf(999999), "LeftButton")
            assert.is_false(ns.IsQuestTracked(999999))
            rowOf(999999):GetScript("OnClick")(rowOf(999999), "LeftButton")
            assert.is_true(ns.IsQuestTracked(999999))
            WowMock.shift = false
            ns.flavor = nil
        end)

        it("the search table shows each result's status too", function()
            ns.UI_SetSearchMode(true, "search")
            assert.is_true(ShownRows()[1].status:IsShown())
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
            assert.matches("d4af37", labels[1]) -- the current step is in gold
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
            assert.are.same({ ns.Theme.rgba("gold") }, { ShownRows()[1]:GetBackdropBorderColor() })
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

    describe("quests to turn in view", function()
        local real
        before_each(function()
            real = { ns.QuestSteps, ns.IsReadyToTurnIn, ns.DistanceTo, C_QuestLog.GetQuestWatchType }
            WowMock.log = { { isHeader = true, title = "Westfall" }, { questID = 166, title = "A", level = 22 },
                { questID = 167, title = "B", level = 22 }, { questID = 168, title = "C", level = 22 } }
            WowMock.onQuest[166], WowMock.onQuest[167], WowMock.onQuest[168] = true, true, true
            local far = { [166] = 300, [167] = 5, [168] = 40 }
            ns.QuestSteps = function(q)
                return { { kind = "finish", label = "Turn in: " .. q.id, current = true, loc = { area = 12, x = far[q.id], y = 1 } } }, 1
            end
            ns.IsReadyToTurnIn = function(id) return id ~= 167 end
            ns.DistanceTo = function(loc) return loc and loc.x end
            C_QuestLog.GetQuestWatchType = function() return nil end -- none of them tracked
        end)
        after_each(function()
            ns.QuestSteps, ns.IsReadyToTurnIn, ns.DistanceTo, C_QuestLog.GetQuestWatchType = real[1], real[2], real[3], real[4]
        end)

        it("has its own entry in the side panel", function()
            local text = WowMock.FindByText("Quests to Turn In")
            assert.is_not_nil(text)
            text:GetParent():Click()
            assert.are.equal("turnin", ns.Search_Mode())
        end)

        it("lists every quest ready to turn in, tracked or not, nearest first, whatever order the other tables use", function()
            panel.head.name:Click() -- the search table by name
            local saved = ns.char.tableSort
            ns.UI_SetSearchMode(true, "turnin")
            local rows = ShownRows()
            assert.are.equal(2, #rows)
            assert.are.equal(168, rows[1].quest.id)
            assert.are.equal(166, rows[2].quest.id)
            assert.is_false(panel.box:IsShown())
            assert.is_not_nil(WowMock.Find(function(f) return f:IsShown() and type(f._text) == "string" and f._text:find("Turn in: 168", 1, true) end))
            -- its own order changes with the headers but is not saved over the other tables'
            panel.head.dist:Click()
            assert.are.equal(166, ShownRows()[1].quest.id)
            assert.are.same(saved, ns.char.tableSort)
            ns.UI_SetSearchMode(true, "log")
            assert.are.equal(3, #ShownRows())
        end)

        it("says so when nothing is ready to turn in", function()
            ns.IsReadyToTurnIn = function() return false end
            ns.UI_SetSearchMode(true, "turnin")
            assert.are.equal(0, #ShownRows())
            assert.is_true(panel.empty:IsShown())
        end)
    end)

    -- nothing here sets ns.REWARDS: the types, the filter and the icons work with what the client's toc loads
    for _, toc in ipairs({ "Completao_TBC.toc", "Completao_Vanilla.toc" }) do describe("with the data of " .. toc, function()
        before_each(function()
            WowMock.Reset()
            WowMock.items[2042] = { typeName = "Weapon", subName = "Staves", classID = 2, subclassID = 10 }
            WowMock.items[2041] = { typeName = "Armor", subName = "Leather", classID = 4, subclassID = 2 }
            ns = LoadAddon({ toc = toc })
            StartAddon(ns, nil, { selected = "vc" })
            ns.UI_Toggle()
            ns.UI_SetSearchMode(true)
            panel = ns.UI.searchPanel
            panel.scroll._h = 100000 -- tall enough for every row to be in view
        end)

        local function pick(button, name)
            button:Click()
            WowMock.Find(function(f) return f.text and f.text._text == name and f._scripts.OnClick end):Click()
        end

        it("lists the reward types and finds a quest by type and subtype", function()
            pick(panel.typeButton, "Armor")
            assert.is_true(ids(ShownRows())[166])
            pick(panel.subButton, "Leather")
            assert.is_true(ids(ShownRows())[166])
        end)

        it("shows the quest's reward items in its row", function()
            typeText("defias brother")
            local row
            for _, r in ipairs(ShownRows()) do if r.quest.id == 166 then row = r end end
            assert.are.equal(6087, row.icons[1].itemID)
            assert.are.equal(2041, row.icons[2].itemID)
            assert.are.equal(2042, row.icons[3].itemID)
        end)

        it("only with items keeps the quests that give one", function()
            panel.itemsOnly:SetChecked(true); panel.itemsOnly:Click()
            local rows = ShownRows()
            assert.is_true(#rows > 0)
            for _, r in ipairs(rows) do assert.is_true(#ns.RewardItemIds(ns.REWARDS[r.quest.id]) > 0) end
        end)
    end) end
end)
