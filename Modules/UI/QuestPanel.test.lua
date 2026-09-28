dofile("setupTests.lua")

describe("QuestPanel", function()
    local ns, waypoints, maps

    local function panelText()
        local t = WowMock.Find(function(f) return type(f._text) == "string" and f._text:find("|cffffd100Requirements|r", 1, true) end)
        return t and t._text or ""
    end
    local function wayButton()
        return WowMock.Find(function(f) return type(f._text) == "string" and f._text:find("^Waypoint: ") and f._scripts.OnClick end)
    end

    before_each(function()
        WowMock.Reset()
        ns = OpenAddon("vc")
        waypoints, maps = {}, {}
        ns.SetWaypoint = function(loc, title) waypoints[#waypoints + 1] = title .. "@" .. tostring(loc.x) end
        ns.ShowOnMap = function(loc, title) maps[#maps + 1] = title .. "@" .. tostring(loc.x) end
        ns.CanWaypoint = function(loc) return loc ~= nil and loc.x ~= nil end
        ns.CanShowMap = ns.CanWaypoint
    end)

    describe("rewards", function()
        before_each(function()
            WowMock.items[159] = { name = "Refreshing Spring Water", quality = 1 }
            ns.REWARDS = { [166] = { choice = { { 4604, 5 }, 159, 2041 }, items = { 6087 }, money = 25, xp = 1050,
                rep = { { 72, 100 }, { 999, -25 } } } }
            ns.Detail_Show(ns.FindQuestDef(166))
        end)

        local function itemButtons()
            local list = {}
            for _, f in ipairs(WowMock.frames) do if f.itemID and f._shown and f.count then list[f.itemID] = f end end
            return list
        end

        it("one button per item, with count and the client's name", function()
            local items = itemButtons()
            assert.is_not_nil(items[4604]); assert.is_not_nil(items[159]); assert.is_not_nil(items[2041]); assert.is_not_nil(items[6087])
            assert.are.equal(5, items[4604].count:GetText())
            assert.are.equal("", items[159].count:GetText())
            assert.are.equal("Refreshing Spring Water", items[159].name:GetText())
        end)

        it("asks the client for the items it doesn't know yet", function()
            assert.are.equal("Item 4604", itemButtons()[4604].name:GetText())
            assert.is_true((WowMock.requestedItems or 0) >= 3)
        end)

        it("item tooltip and Shift-click to link it", function()
            local b = itemButtons()[159]
            local shown
            GameTooltip.SetItemByID = function(_, id) shown = id end
            b._scripts.OnEnter(b)
            b:Click()
            assert.are.equal(159, shown)
            assert.matches("item:159", WowMock.linked)
        end)

        it("money, experience and reputation (with an unknown faction)", function()
            local texts = {}
            for _, f in ipairs(WowMock.frames) do if type(f._text) == "string" then texts[#texts + 1] = f._text end end
            local all = table.concat(texts, "\n")
            assert.matches("Money: 25c", all)
            assert.matches("Experience: 1050", all)
            assert.matches("Reputation: %+100 Stormwind", all)
            assert.matches("Reputation: %-25 Faction 999", all)
        end)
    end)

    describe("steps and waypoint", function()
        local q

        before_each(function()
            ns.entries.vc.entrance = { area = 40, x = 42.5, y = 71.7 }
            q = { id = 900001, name = "Test Quest", entryId = "z12", dungeon = "vc", requires = { 900000 },
                start = { npc = "Giver", area = 12, x = 10, y = 11 }, finish = { npc = "Ender", area = 12, x = 20, y = 21 },
                steps = { { name = "Tough Wolf Meat", area = 12, x = 30, y = 31 }, { name = "Head of VanCleef", area = 1581 } } }
        end)

        it("the steps list goes after the objective", function()
            q.objective = "Do things."
            ns.Detail_Show(q)
            local text = panelText()
            assert.is_truthy(text:find("Objective", 1, true) < text:find("Steps", 1, true))
            assert.matches("Start: Giver", text)
        end)

        it("not started: the button goes to the missing requirement", function()
            ns.Detail_Show(q)
            assert.are.equal("Waypoint: Requirement: Quest 900000", wayButton():GetText())
        end)

        it("in progress: to the first unfinished objective, with progress in the list", function()
            WowMock.done[900000] = true
            WowMock.onQuest[900001] = true
            WowMock.objectives[900001] = { { text = "Tough Wolf Meat: 3/8", finished = false, numFulfilled = 3, numRequired = 8 } }
            ns.Detail_Show(q)
            assert.are.equal("Waypoint: Tough Wolf Meat", wayButton():GetText())
            assert.matches("Tough Wolf Meat  3/8", panelText())
            wayButton():Click()
            assert.are.equal("Tough Wolf Meat@30", waypoints[#waypoints])
        end)

        it("Show on map follows the step chosen for the waypoint, not the quest giver", function()
            WowMock.done[900000] = true
            WowMock.onQuest[900001] = true
            WowMock.objectives[900001] = { { text = "Tough Wolf Meat: 3/8", finished = false, numFulfilled = 3, numRequired = 8 } }
            ns.Detail_Show(q)
            WowMock.FindButton("Show on map"):Click()
            assert.are.equal("Tough Wolf Meat@30", maps[#maps])
            -- picking the start in the dropdown makes the map follow it
            local arrow = WowMock.Find(function(f) return f._text == "v" and f._scripts.OnClick end)
            arrow:Click()
            local option = WowMock.Find(function(f)
                return f.text and type(f.text._text) == "string" and f.text._text:find("Start: Giver", 1, true) and f._scripts.OnClick
            end)
            option:Click()
            WowMock.FindButton("Show on map"):Click()
            assert.are.equal("Start: Giver@10", maps[#maps])
        end)

        it("a step inside a dungeon goes to its entrance", function()
            WowMock.done[900000] = true
            WowMock.onQuest[900001] = true
            WowMock.objectives[900001] = {
                { text = "Tough Wolf Meat: 8/8", finished = true, numFulfilled = 8, numRequired = 8 },
                { text = "Head of VanCleef: 0/1", finished = false, numFulfilled = 0, numRequired = 1 },
            }
            ns.Detail_Show(q)
            wayButton():Click()
            assert.are.equal("Head of VanCleef@42.5", waypoints[#waypoints])
            assert.is_not_nil(WowMock.FindButton("Show entrance"))
        end)

        it("picking another step in the dropdown sets the waypoint and survives a refresh", function()
            ns.Detail_Show(q)
            local arrow = WowMock.Find(function(f) return f._text == "v" and f._scripts.OnClick end)
            arrow:Click()
            local option = WowMock.Find(function(f)
                return f.text and type(f.text._text) == "string" and f.text._text:find("Start: Giver", 1, true) and f._scripts.OnClick
            end)
            option:Click()
            assert.are.equal("Start: Giver@10", waypoints[#waypoints])
            ns.Detail_Refresh()
            assert.are.equal("Waypoint: Start: Giver", wayButton():GetText())
        end)
    end)

    it("the Open quest button only with the quest in the log", function()
        local q = ns.FindQuestDef(166)
        ns.Detail_Show(q)
        assert.is_false(WowMock.FindButton("Open quest"):IsShown())
        WowMock.onQuest[166] = true
        ns.Detail_Refresh()
        assert.is_true(WowMock.FindButton("Open quest"):IsShown())
    end)

    it("requirements show the required and the recommended level", function()
        ns.Detail_Show({ id = 2, name = "y", level = 22, minLevel = 11 })
        local text = panelText()
        assert.matches("Level 11 required", text)
        assert.matches("Level 22 recommended", text)
    end)

    it("the recommended level is colored like the game does for this character", function()
        WowMock.level = 19
        ns.Detail_Show({ id = 3, name = "z", level = 18 })
        assert.matches("|cffffff00Level 18 recommended|r", panelText())
        ns.Detail_Show({ id = 4, name = "w", level = 5 })
        assert.matches("|cff808080Level 5 recommended|r", panelText())
    end)

    it("the long description goes last, when there is one", function()
        ns.Detail_Show({ id = 1, name = "x", desc = "Long story" })
        local text = panelText()
        assert.is_truthy(text:find("Description", 1, true))
        assert.are.equal(#text - #"Long story" + 1, text:find("Long story", 1, true))
    end)
end)
