dofile("setupTests.lua")

describe("QuestMenu", function()
    local ns

    local function menuOptions()
        local list = WowMock.FindAll(function(f)
            return f.text and f._scripts.OnClick and f._shown and f._parent and f._parent.buttons
        end)
        table.sort(list, function(a, b) return a:GetTop() > b:GetTop() end)
        return list
    end
    local function labels()
        local names = {}
        for _, b in ipairs(menuOptions()) do names[#names + 1] = b.text._text end
        return names
    end
    local function choose(label)
        for _, b in ipairs(menuOptions()) do
            if b.text._text == label then b:Click() return end
        end
        error("no option " .. label .. " in: " .. table.concat(labels(), ", "))
    end
    local function treeNode(id)
        return WowMock.Find(function(f) return f.quest and f.badge and f._shown and f.quest.id == id end)
    end

    before_each(function()
        WowMock.Reset()
        ns = LoadAddon()
        StartAddon(ns, nil, { selected = "vc" })
        ns.UI_Toggle()
    end)

    it("right click on a node of the tree opens the menu instead of the details", function()
        local node = treeNode(166)
        node._scripts.OnClick(node, "RightButton")
        assert.is_true(#menuOptions() > 0)
        assert.is_nil(ns.Detail_Current())
    end)

    it("left click on a node still opens the details", function()
        local node = treeNode(166)
        node._scripts.OnClick(node, "LeftButton")
        assert.are.equal(166, ns.Detail_Current().id)
    end)

    it("a quest not in the log leaves out focus, log and abandon", function()
        ns.QuestMenu(WowMock.NewFrame("Button"), ns.FindQuestDef(166))
        assert.is_true(#menuOptions() > 0)
        for _, name in ipairs(labels()) do
            assert.is_not.equal("Focus", name)
            assert.is_not.equal("Open quest", name)
            assert.is_not.equal("Abandon quest", name)
        end
    end)

    it("lists the options of the quest details that apply to the quest", function()
        local q = ns.FindQuestDef(166) -- inside an instance: its entrance instead of the map
        WowMock.onQuest[166] = true
        ns.CanWaypoint = function(loc) return loc ~= nil end
        ns.CanShowMap = ns.CanWaypoint
        ns.QuestMenu(WowMock.NewFrame("Button"), q)
        local names = labels()
        table.sort(names)
        assert.are.same({ "Abandon quest", "Focus", "Open quest", "Set waypoint", "Show entrance", "View chain" }, names)
        ns.Detail_Show(q)
        for _, text in ipairs({ "Focus", "Open quest", "Show entrance", "View chain", "Abandon quest", "Waypoint" }) do
            assert.is_not_nil(WowMock.FindButton(text), text)
        end
    end)

    describe("with the quest in the log", function()
        local q
        before_each(function()
            q = ns.FindQuestDef(166)
            WowMock.onQuest[166] = true
        end)

        it("focuses it and then offers to stop", function()
            ns.QuestMenu(WowMock.NewFrame("Button"), q)
            choose("Focus")
            assert.are.equal(166, ns.Focus_Quest())
            ns.QuestMenu(WowMock.NewFrame("Button"), q)
            choose("Stop focus")
            assert.is_nil(ns.Focus_Quest())
        end)

        it("opens it in the quest log", function()
            WowMock.log = { { questID = 166 } }
            ns.QuestMenu(WowMock.NewFrame("Button"), q)
            choose("Open quest")
            assert.are.equal(166, WowMock.selectedQuest)
        end)

        it("abandons it through the game's own confirmation", function()
            local asked
            _G.QuestMapQuestOptions_AbandonQuest = function(id) asked = id end
            ns.QuestMenu(WowMock.NewFrame("Button"), q)
            choose("Abandon quest")
            _G.QuestMapQuestOptions_AbandonQuest = nil
            assert.are.equal(166, asked)
        end)
    end)

    it("sets the waypoint and shows the map on the quest's next step", function()
        local q = { id = 999001, name = "Pest Control", level = 20, entryId = "vc",
            start = { npc = "Giver", area = 12, x = 5, y = 5 }, finish = { npc = "Bob", area = 12, x = 20, y = 21 } }
        local shown
        WowMock.maps[1429] = { name = "Area12", mapType = Enum.UIMapType.Zone }
        ns.ShowOnMap = function(loc) shown = loc end
        ns.QuestMenu(WowMock.NewFrame("Button"), q)
        choose("Set waypoint")
        assert.is_not_nil(WowMock.userWaypoint)
        ns.QuestMenu(WowMock.NewFrame("Button"), q)
        choose("Show on map")
        assert.are.same(q.start, shown)
    end)

    it("a quest with no place, no chain and not in the log has no menu", function()
        ns.QuestMenu(WowMock.NewFrame("Button"), { id = 999002, name = "Nowhere" })
        assert.are.equal(0, #menuOptions())
    end)

    it("right click on a table row opens the menu", function()
        ns.UI_SetSearchMode(true)
        local row = ShownRows()[1]
        WowMock.onQuest[row.quest.id] = true
        row._scripts.OnClick(row, "RightButton")
        assert.is_true(#menuOptions() > 0)
    end)
end)
