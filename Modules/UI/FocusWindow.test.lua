dofile("setupTests.lua")

describe("FocusWindow", function()
    local ns, frame
    local boars = { name = "Boars", area = 12, x = 10, y = 11 }
    local wolves = { name = "Wolves", area = 12, x = 60, y = 61 }

    -- lines of the window that are showing, in order (color codes and all)
    local function isLine(button)
        return button and button._parent == frame and button._kind == "Button" and button ~= frame.close
    end
    local function shownTexts()
        local out = {}
        for _, f in ipairs(WowMock.frames) do
            if f._kind == "FontString" and isLine(f._parent) and f:IsVisible() then out[#out + 1] = f._text end
        end
        return out
    end
    -- the clickable line showing that text
    local function lineWith(text)
        return WowMock.Find(function(f) return isLine(f) and f:IsVisible() and f.step and f.step.text:find(text, 1, true) end)
    end

    local function objectives(boarsDone, wolvesDone)
        WowMock.objectives[999001] = {
            { text = "Boars: " .. (boarsDone and 5 or 0) .. "/5", finished = boarsDone, numFulfilled = boarsDone and 5 or 0, numRequired = 5 },
            { text = "Wolves: " .. (wolvesDone and 3 or 1) .. "/3", finished = wolvesDone, numFulfilled = wolvesDone and 3 or 1, numRequired = 3 },
        }
    end

    before_each(function()
        WowMock.Reset()
        WowMock.maps[1429] = { name = "Area12", mapType = Enum.UIMapType.Zone }
        ns = LoadAddon()
        ns.RegisterEntry({ id = "z", name = "Zone", category = "zones" })
        ns.AddQuests("z", { { id = 999001, name = "Pest Control", level = 20,
            start = { npc = "Giver", area = 12, x = 5, y = 5 }, finish = { npc = "Farmer Bob", area = 12, x = 20, y = 21 },
            steps = { boars, wolves } },
            { id = 999002, name = "Cave", level = 20, steps = { { name = "Find the cave", area = 12 } } },
            { id = 999003, name = "Fox Hunt", level = 20, finish = { npc = "Hunter Ann", area = 12, x = 31, y = 32 },
                steps = { { name = "Foxes", area = 12, x = 30, y = 31 } } },
            { id = 999004, name = "Owl Watch", level = 20, finish = { npc = "Watcher Bo", area = 12, x = 81, y = 82 },
                steps = { { name = "Owls", area = 12, x = 80, y = 81 } } } })
        WowMock.titles[999001] = "Pest Control"
        WowMock.onQuest[999001] = true
        objectives(false, false)
        -- the player stands by the wolves: they are the nearest
        ns.DistanceTo = function(loc) return loc.x == wolves.x and 10 or 200 end
        WowMock.chatted = nil
        ns.Print = function() WowMock.chatted = true end
        StartAddon(ns, nil, {})
        frame = nil
    end)

    local function focus()
        assert.is_true(ns.Focus_Set(999001))
        frame = CompletaoFocusFrame
    end

    it("only quests in the log can be focused on", function()
        WowMock.onQuest[999001] = nil
        assert.is_false(ns.Focus_Set(999001))
        assert.is_nil(ns.Focus_Quest())
        assert.is_nil(CompletaoFocusFrame)
    end)

    it("shows the title in its difficulty color, the status icon and the objectives with their progress", function()
        focus()
        assert.is_true(frame:IsShown())
        assert.matches("Pest Control", frame.title._text)
        assert.are.same({ ns.QuestLevelColorRGB(20) }, { frame.title:GetTextColor() })
        assert.matches("IncompleteQuestIcon", frame.icon._set.SetTexture[1])
        local texts = shownTexts()
        assert.are.equal(2, #texts)
        assert.matches("Boars 0/5", texts[1])
        assert.matches("Wolves 1/3", texts[2])
    end)

    it("has a title bar saying what it is", function()
        focus()
        assert.are.equal("Focused Quest", frame.barText._text)
        assert.is_true(frame.barText:IsVisible())
    end)

    it("clicking an objective puts the waypoint on it, and the gold follows", function()
        focus()
        assert.are.equal("999001:3", ns.FocusTag()) -- the nearest: the wolves
        lineWith("Boars"):Click()
        assert.are.equal("999001:2", ns.FocusTag())
        assert.near(0.1, WowMock.userWaypoint.x, 1e-9)
        assert.is_true(WowMock.chatted) -- a click of the player's says so, unlike the automatic one
        assert.matches("ffd100", shownTexts()[1])
        assert.matches("ffffff", shownTexts()[2])
    end)

    it("a click on the window opens the main window on the tracked quests", function()
        focus()
        assert.is_nil(ns.UI)
        frame._scripts.OnMouseDown(frame, "LeftButton")
        frame._scripts.OnMouseUp(frame, "RightButton") -- only the normal click
        assert.is_nil(ns.UI)
        frame._scripts.OnMouseUp(frame, "LeftButton")
        assert.is_true(ns.UI:IsShown())
        assert.are.equal("tracked", ns.Search_Mode())
    end)

    it("the mouse-up that ends a drag doesn't open it", function()
        focus()
        frame._scripts.OnMouseDown(frame, "LeftButton")
        frame._scripts.OnDragStart(frame)
        frame._scripts.OnDragStop(frame)
        frame._scripts.OnMouseUp(frame, "LeftButton")
        assert.is_nil(ns.UI)
        frame._scripts.OnMouseDown(frame, "LeftButton") -- and the next plain click does
        frame._scripts.OnMouseUp(frame, "LeftButton")
        assert.is_true(ns.UI:IsShown())
    end)

    it("an objective only sets its waypoint, it doesn't open the main window", function()
        focus()
        lineWith("Boars"):Click()
        assert.is_nil(ns.UI)
        assert.are.equal("999001:2", ns.FocusTag())
    end)

    it("clicking the turn-in puts the waypoint on who takes it", function()
        focus()
        WowMock.readyForTurnIn[999001] = true
        FireEvent("QUEST_LOG_UPDATE")
        lineWith("Turn in"):Click()
        assert.near(0.2, WowMock.userWaypoint.x, 1e-9)
    end)

    it("an objective with only a zone opens the map on it", function()
        local opened
        ns.ShowOnMap = function(loc) opened = loc end
        WowMock.onQuest[999002] = true
        assert.is_true(ns.Focus_Set(999002))
        frame = CompletaoFocusFrame
        lineWith("Find the cave"):Click()
        assert.are.equal(12, opened.area)
    end)

    it("puts the waypoint on the nearest objective, quietly, and marks it in gold", function()
        focus()
        assert.are.equal(1429, WowMock.userWaypoint.mapID)
        assert.near(0.6, WowMock.userWaypoint.x, 1e-9)
        assert.are.equal("999001:3", ns.FocusTag())
        assert.is_nil(WowMock.chatted)
        assert.matches("ffd100", shownTexts()[2])
        assert.matches("ffffff", shownTexts()[1])
    end)

    it("a done objective goes grey and struck through, and the waypoint moves to the one left", function()
        -- the lines drawn over the text (the only textures of the window with a plain color)
        local function strikes()
            return #WowMock.FindAll(function(f)
                return f._kind == "Texture" and isLine(f._parent) and f._set.SetColorTexture ~= nil and f:IsVisible()
            end)
        end
        focus()
        assert.are.equal(0, strikes())
        objectives(false, true)
        FireEvent("QUEST_LOG_UPDATE")
        local texts = shownTexts()
        assert.matches("808080", texts[2])
        assert.matches("Wolves 3/3", texts[2])
        assert.are.equal(1, strikes())
        assert.are.equal("999001:2", ns.FocusTag())
        assert.near(0.1, WowMock.userWaypoint.x, 1e-9)
    end)

    it("the waypoint isn't redone while nothing changes (the player's own one stays)", function()
        focus()
        WowMock.userWaypoint = nil
        ns.DistanceTo = function(loc) return loc.x == boars.x and 10 or 200 end -- the player moved
        FireEvent("QUEST_LOG_UPDATE")
        assert.is_nil(WowMock.userWaypoint)
    end)

    it("with every objective done, the turn-in replaces them, with the waypoint on the one who takes it", function()
        focus()
        objectives(true, true)
        WowMock.readyForTurnIn[999001] = true
        FireEvent("QUEST_LOG_UPDATE")
        local texts = shownTexts()
        assert.are.equal(1, #texts)
        assert.matches("Turn in Pest Control %(Farmer Bob%)", texts[1])
        assert.matches("ActiveQuestIcon", frame.icon._set.SetTexture[1])
        assert.are.equal("999001:4", ns.FocusTag())
        assert.near(0.2, WowMock.userWaypoint.x, 1e-9)
    end)

    it("turning the quest in forgets the focus, and the window says no quest is focused", function()
        focus()
        WowMock.onQuest[999001], WowMock.done[999001] = nil, true
        FireEvent("QUEST_TURNED_IN", 999001)
        assert.is_nil(ns.Focus_Quest())
        assert.is_true(frame:IsShown())
        assert.are.equal("No quest focused", frame.title._text)
        assert.is_false(frame.icon:IsShown())
        local texts = shownTexts()
        assert.are.equal(1, #texts)
        assert.matches("Click to choose another", texts[1])
    end)

    it("abandoning it does the same", function()
        focus()
        WowMock.onQuest[999001] = nil
        FireEvent("QUEST_REMOVED", 999001)
        assert.is_nil(ns.Focus_Quest())
        assert.is_true(frame:IsShown())
        assert.are.equal("No quest focused", frame.title._text)
    end)

    it("the message window opens the tracked quests on a click, and a new focus takes its place", function()
        focus()
        WowMock.onQuest[999001], WowMock.done[999001] = nil, true
        FireEvent("QUEST_TURNED_IN", 999001)
        frame._scripts.OnMouseUp(frame, "LeftButton")
        assert.are.equal("tracked", ns.Search_Mode())
        ns.UI_SetSearchMode(true, "log")
        lineWith("Click to choose"):Click() -- and so does its hint
        assert.are.equal("tracked", ns.Search_Mode())
        assert.is_false(ns.Focus_Set(999002)) -- not in the log
        WowMock.onQuest[999002] = true
        assert.is_true(ns.Focus_Set(999002))
        assert.matches("Cave", frame.title._text)
        assert.is_true(frame.icon:IsShown())
        assert.matches("Find the cave", shownTexts()[1])
    end)

    it("the close button closes the window and stops the focus", function()
        focus()
        frame.close:Click()
        assert.is_false(frame:IsShown())
        assert.is_nil(ns.Focus_Quest())
        FireEvent("QUEST_LOG_UPDATE")
        assert.is_false(frame:IsShown())
    end)

    it("the X also closes the message window, and unfocusing by hand doesn't leave one", function()
        focus()
        ns.Focus_Toggle(999001) -- from the tracked list
        assert.is_false(frame:IsShown())
        focus()
        WowMock.done[999001], WowMock.onQuest[999001] = true, nil
        FireEvent("QUEST_TURNED_IN", 999001)
        assert.is_true(frame:IsShown())
        frame.close:Click()
        assert.is_false(frame:IsShown())
        FireEvent("QUEST_LOG_UPDATE")
        assert.is_false(frame:IsShown())
    end)

    it("can be dragged, and its place is saved", function()
        focus()
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 30, -40)
        frame._scripts.OnDragStop(frame)
        assert.are.same({ point = "TOPLEFT", relPoint = "TOPLEFT", x = 30, y = -40 }, ns.char.focusWindow)
        ns.Focus_ResetPosition()
        assert.is_nil(ns.char.focusWindow)
    end)

    describe("the padlock", function()
        local function moved()
            local started = false
            frame.StartMoving = function() started = true end
            frame._scripts.OnMouseDown(frame, "LeftButton")
            frame._scripts.OnDragStart(frame)
            frame._scripts.OnDragStop(frame)
            frame._scripts.OnMouseUp(frame, "LeftButton")
            return started
        end

        it("starts unlocked, and locks the window in place", function()
            focus()
            assert.matches("Unlocked", frame.lock._set.SetNormalTexture[1])
            assert.is_true(moved())
            frame.lock:Click()
            assert.is_true(ns.char.focusLocked)
            assert.matches("Locked", frame.lock._set.SetNormalTexture[1])
            assert.is_false(moved())
            frame.lock:Click()
            assert.is_nil(ns.char.focusLocked)
            assert.matches("Unlocked", frame.lock._set.SetNormalTexture[1])
            assert.is_true(moved())
        end)

        it("everything else works locked: a click opens the tracked quests, an objective sets its waypoint", function()
            focus()
            frame.lock:Click()
            moved() -- a failed drag isn't a click
            assert.is_nil(ns.UI)
            frame._scripts.OnMouseDown(frame, "LeftButton")
            frame._scripts.OnMouseUp(frame, "LeftButton")
            assert.is_true(ns.UI:IsShown())
            lineWith("Boars"):Click()
            assert.are.equal("999001:2", ns.FocusTag())
            frame.close:Click()
            assert.is_false(frame:IsShown())
        end)

        it("is remembered, and is click-through in combat like the rest", function()
            ns.char.focusLocked = true
            focus()
            assert.matches("Locked", frame.lock._set.SetNormalTexture[1])
            FireEvent("PLAYER_REGEN_DISABLED")
            assert.is_false(frame.lock:IsMouseEnabled())
            FireEvent("PLAYER_REGEN_ENABLED")
            assert.is_true(frame.lock:IsMouseEnabled())
        end)
    end)

    it("takes the mouse only out of combat", function()
        focus()
        assert.is_true(frame:IsMouseEnabled())
        FireEvent("PLAYER_REGEN_DISABLED")
        assert.is_false(frame:IsMouseEnabled())
        assert.is_false(frame.close:IsMouseEnabled())
        assert.is_false(lineWith("Boars"):IsMouseEnabled()) -- the objectives too: clicks go through
        FireEvent("PLAYER_REGEN_ENABLED")
        assert.is_true(frame:IsMouseEnabled())
        assert.is_true(frame.close:IsMouseEnabled())
        assert.is_true(lineWith("Boars"):IsMouseEnabled())
    end)

    it("objectives that appear during combat are click-through too", function()
        focus()
        FireEvent("PLAYER_REGEN_DISABLED")
        WowMock.objectives[999001][3] = { text = "Bears: 0/2", finished = false, numFulfilled = 0, numRequired = 2 }
        FireEvent("QUEST_LOG_UPDATE")
        local bears = lineWith("Bears")
        assert.is_not_nil(bears)
        assert.is_false(bears:IsMouseEnabled())
    end)

    it("a window made during combat is click-through from the start", function()
        WowMock.inCombat = true
        focus()
        assert.is_false(frame:IsMouseEnabled())
    end)

    it("comes back after a reload while the quest is still in the log", function()
        local ns2 = LoadAddon()
        ns2.RegisterEntry({ id = "z", name = "Zone", category = "zones" })
        ns2.AddQuests("z", { { id = 999001, name = "Pest Control", level = 20, steps = { boars } } })
        StartAddon(ns2, nil, { focusQuest = 999001 })
        assert.is_true(CompletaoFocusFrame:IsShown())
        assert.are.equal(999001, ns2.Focus_Quest())
    end)

    it("a focus on a quest that is gone is dropped when the game starts", function()
        WowMock.onQuest[999001] = nil
        local ns2 = LoadAddon()
        StartAddon(ns2, nil, { focusQuest = 999001 })
        assert.is_nil(ns2.Focus_Quest())
    end)

    describe("focusing the nearest tracked quest after a turn-in", function()
        local tracked, distance
        local function turnIn()
            WowMock.onQuest[999001], WowMock.done[999001] = nil, true
            FireEvent("QUEST_TURNED_IN", 999001)
        end
        local function track(ids)
            tracked = {}
            WowMock.log = { { isHeader = true, title = "Zone" } }
            for _, id in ipairs(ids) do
                tracked[id] = true
                WowMock.onQuest[id] = true
                WowMock.titles[id] = ({ [999001] = "Pest Control", [999003] = "Fox Hunt", [999004] = "Owl Watch" })[id]
                WowMock.log[#WowMock.log + 1] = { questID = id, title = "Quest " .. id, level = 20 }
            end
        end
        before_each(function()
            distance = { [boars.x] = 500, [wolves.x] = 10, [30] = 40, [80] = 900 }
            ns.DistanceTo = function(loc) return distance[loc.x] end
            C_QuestLog.GetQuestWatchType = function(id) return tracked[id] and 0 or nil end
            track({ 999001, 999003, 999004 })
            ns.char.focusAuto = true
            focus()
        end)
        after_each(function() C_QuestLog.GetQuestWatchType = nil end)

        it("moves the focus to the tracked quest that is nearest, by what it needs next", function()
            turnIn()
            assert.are.equal(999003, ns.Focus_Quest())
            assert.matches("Fox Hunt", frame.title._text)
            assert.is_true(frame:IsShown())
            assert.matches("Foxes", shownTexts()[1])
            assert.near(0.3, WowMock.userWaypoint.x, 1e-9) -- and the waypoint goes with it
        end)

        it("counts a quest that is ready by the distance to whoever takes it in", function()
            WowMock.readyForTurnIn[999004] = true
            distance[80], distance[81] = 900, 5 -- its turn-in is at x = 81
            turnIn()
            assert.are.equal(999004, ns.Focus_Quest())
            assert.matches("Turn in Owl Watch %(Watcher Bo%)", shownTexts()[1])
        end)

        it("ignores the quests that aren't tracked", function()
            tracked[999003] = nil
            turnIn()
            assert.are.equal(999004, ns.Focus_Quest())
        end)

        it("with none tracked left, the window says so", function()
            track({ 999001 })
            turnIn()
            assert.is_nil(ns.Focus_Quest())
            assert.are.equal("No quest focused", frame.title._text)
        end)

        it("with no distance known for any of them, it leaves the window for the player to choose", function()
            ns.DistanceTo = function() return nil end
            turnIn()
            assert.is_nil(ns.Focus_Quest())
            assert.are.equal("No quest focused", frame.title._text)
            assert.matches("Click to choose another", shownTexts()[1])
        end)

        it("one with a known distance is chosen even if the others have none", function()
            distance = { [80] = 900, [30] = nil }
            ns.DistanceTo = function(loc) return distance[loc.x] end
            turnIn()
            assert.are.equal(999004, ns.Focus_Quest())
        end)

        it("does nothing with the setting off", function()
            ns.char.focusAuto = nil
            turnIn()
            assert.is_nil(ns.Focus_Quest())
            assert.are.equal("No quest focused", frame.title._text)
        end)

        it("only when the focused quest is turned in: not when moving around, abandoning or turning in another", function()
            distance[30] = 1 -- the foxes are now by the player
            FireEvent("QUEST_LOG_UPDATE")
            assert.are.equal(999001, ns.Focus_Quest())
            WowMock.onQuest[999001] = nil -- abandoned
            FireEvent("QUEST_REMOVED", 999001)
            assert.is_nil(ns.Focus_Quest())
            assert.are.equal("No quest focused", frame.title._text)
        end)

        it("turning in a quest that wasn't the focused one leaves the focus alone", function()
            WowMock.onQuest[999003], WowMock.done[999003] = nil, true
            FireEvent("QUEST_TURNED_IN", 999003)
            assert.are.equal(999001, ns.Focus_Quest())
        end)
    end)

    describe("switching to a nearer tracked quest when the focused one is ready", function()
        local tracked, distance
        local function finish()
            objectives(true, true)
            WowMock.readyForTurnIn[999001] = true
            FireEvent("QUEST_LOG_UPDATE")
        end
        before_each(function()
            -- the pest control turn-in is at x = 20; the foxes at 30, the owls at 80
            distance = { [20] = 100, [30] = 40, [80] = 900 }
            ns.DistanceTo = function(loc) return distance[loc.x] end
            tracked = { [999001] = true, [999003] = true, [999004] = true }
            WowMock.log = { { isHeader = true, title = "Zone" } }
            for id in pairs(tracked) do
                WowMock.onQuest[id] = true
                WowMock.log[#WowMock.log + 1] = { questID = id, title = "Quest " .. id, level = 20 }
            end
            WowMock.titles[999003], WowMock.titles[999004] = "Fox Hunt", "Owl Watch"
            C_QuestLog.GetQuestWatchType = function(id) return tracked[id] and 0 or nil end
            ns.char.focusNext = true
            focus()
        end)
        after_each(function() C_QuestLog.GetQuestWatchType = nil end)

        it("goes to a tracked quest with something nearer than this one's turn-in", function()
            finish()
            assert.are.equal(999003, ns.Focus_Quest())
            assert.matches("Fox Hunt", frame.title._text)
            assert.near(0.3, WowMock.userWaypoint.x, 1e-9)
        end)

        it("also counts another quest's turn-in", function()
            WowMock.readyForTurnIn[999004] = true
            distance[81], distance[30] = 10, 500 -- the owls' turn-in is close now, the foxes far
            finish()
            assert.are.equal(999004, ns.Focus_Quest())
        end)

        it("stays when its own turn-in is the nearest", function()
            distance[20] = 5
            finish()
            assert.are.equal(999001, ns.Focus_Quest())
            assert.matches("Turn in Pest Control", shownTexts()[1])
        end)

        it("does nothing with the setting off", function()
            ns.char.focusNext = nil
            finish()
            assert.are.equal(999001, ns.Focus_Quest())
        end)

        it("stays when a distance can't be told: its own, or the others'", function()
            distance[20] = nil
            finish()
            assert.are.equal(999001, ns.Focus_Quest())
        end)

        it("stays when no other tracked quest has a known distance", function()
            distance[30], distance[80] = nil, nil
            finish()
            assert.are.equal(999001, ns.Focus_Quest())
        end)

        it("only at the moment the objectives are finished, not as you move afterwards", function()
            distance[30] = 500 -- the foxes are far
            finish()
            assert.are.equal(999001, ns.Focus_Quest())
            distance[30] = 1 -- and now you are by them
            FireEvent("QUEST_LOG_UPDATE")
            assert.are.equal(999001, ns.Focus_Quest())
        end)

        it("a quest that was already ready when it got the focus stays", function()
            ns.Focus_Clear()
            finish() -- ready while unfocused
            assert.is_true(ns.Focus_Set(999001))
            assert.are.equal(999001, ns.Focus_Quest())
            FireEvent("QUEST_LOG_UPDATE")
            assert.are.equal(999001, ns.Focus_Quest())
        end)
    end)

    describe("the step for the waypoint", function()
        local function steps(list) return list end
        before_each(function() ns.DistanceTo = function(loc) return loc.d end end)

        it("is the nearest objective left with a spot", function()
            local list = steps({
                { kind = "start" },
                { kind = "obj", loc = { area = 12, x = 1, y = 1, d = 50 } },
                { kind = "obj", loc = { area = 12, x = 2, y = 2, d = 20 } },
                { kind = "obj", loc = { area = 12, x = 3, y = 3, d = 5 }, done = true },
                { kind = "obj", area = 12 },
                { kind = "finish", loc = { area = 12, x = 9, y = 9, d = 1 } },
            })
            assert.are.equal(3, ns.Focus_PickStep(list, false))
        end)

        it("is the first one when the distance can't be told", function()
            ns.DistanceTo = function() return nil end
            local list = steps({
                { kind = "obj", loc = { area = 12, x = 1, y = 1 } },
                { kind = "obj", loc = { area = 12, x = 2, y = 2 } },
                { kind = "finish" },
            })
            assert.are.equal(1, ns.Focus_PickStep(list, false))
        end)

        it("is the turn-in when ready, or none if it has no spot", function()
            local list = steps({
                { kind = "obj", done = true, loc = { area = 12, x = 1, y = 1 } },
                { kind = "finish", loc = { area = 12, x = 9, y = 9 } },
            })
            assert.are.equal(2, ns.Focus_PickStep(list, true))
            list[2].loc = nil
            assert.is_nil(ns.Focus_PickStep(list, true))
        end)

        it("is none when no objective has a spot", function()
            assert.is_nil(ns.Focus_PickStep({ { kind = "obj", area = 12 }, { kind = "finish" } }, false))
        end)
    end)

    describe("from the tracked quests", function()
        local tracked
        before_each(function()
            WowMock.log = { { isHeader = true, title = "Zone" }, { questID = 999001, title = "Pest Control", level = 20 } }
            tracked = { [999001] = true }
            C_QuestLog.GetQuestWatchType = function(id) return tracked[id] and 0 or nil end
            ns.UI_Toggle()
            ns.UI_SetSearchMode(true, "tracked")
        end)
        after_each(function() C_QuestLog.GetQuestWatchType = nil end)

        it("right click on a quest focuses it, and again stops", function()
            local row = ShownRows()[1]
            row:Click("RightButton")
            assert.are.equal(999001, ns.Focus_Quest())
            assert.is_true(CompletaoFocusFrame:IsShown())
            row:Click("RightButton")
            assert.is_nil(ns.Focus_Quest())
        end)

        it("left click still opens the details, with a Focus button for it", function()
            ShownRows()[1]:Click("LeftButton")
            assert.are.equal(999001, ns.Detail_Current().id)
            local button = WowMock.FindButton("Focus")
            assert.is_not_nil(button)
            button:Click()
            assert.are.equal(999001, ns.Focus_Quest())
            assert.is_not_nil(WowMock.FindButton("Stop focus"))
        end)
    end)
end)
