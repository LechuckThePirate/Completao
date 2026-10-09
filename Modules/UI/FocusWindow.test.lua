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
        WowMock.inCombat = false
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

    describe("autofocus", function()
        local tracked, distance
        -- distances by the x of the spot: Pest Control's boars 10 (200 yd), wolves 60 (10 yd) and turn-in 20;
        -- Fox Hunt's foxes 30 and turn-in 31; Owl Watch's owls 80 and turn-in 81
        local function ready(id) WowMock.readyForTurnIn[id] = true end
        local events
        local function tick() events._scripts.OnUpdate(events, 2) end
        local function turnIn(id)
            WowMock.onQuest[id], WowMock.done[id] = nil, true
            FireEvent("QUEST_TURNED_IN", id)
        end
        before_each(function()
            distance = { [boars.x] = 200, [wolves.x] = 10, [20] = 300, [30] = 40, [31] = 60, [80] = 900, [81] = 950 }
            ns.DistanceTo = function(loc) return distance[loc.x] end
            tracked = { [999001] = true, [999003] = true, [999004] = true }
            WowMock.log = { { isHeader = true, title = "Zone" } }
            for _, id in ipairs({ 999001, 999003, 999004 }) do
                WowMock.onQuest[id] = true
                WowMock.log[#WowMock.log + 1] = { questID = id, title = "Quest " .. id, level = 20 }
            end
            WowMock.titles[999003], WowMock.titles[999004] = "Fox Hunt", "Owl Watch"
            C_QuestLog.GetQuestWatchType = function(id) return tracked[id] and 0 or nil end
            events = WowMock.Find(function(f) return f._scripts.OnUpdate and f._events and f._events.PLAYER_ENTERING_WORLD end)
            ns.char.focusAuto = true
            frame = nil
        end)
        after_each(function() C_QuestLog.GetQuestWatchType = nil end)

        local function update() FireEvent("QUEST_LOG_UPDATE") frame = CompletaoFocusFrame end

        describe("inside a dungeon", function()
            -- only Fox Hunt is done inside it (the nearest objective in the log is still Pest Control's wolves)
            before_each(function()
                ns.RegisterEntry({ id = "dng", name = "Test Dungeon", instanceId = 777 })
                ns.FindQuestDef(999003).dungeon = "dng"
            end)
            after_each(function() _G.GetInstanceInfo = nil end)
            local function enter(instanceType) _G.GetInstanceInfo = function() return "Test Dungeon", instanceType or "party", 1, "", 5, 0, false, 777 end end

            it("only picks a quest that is done in it", function()
                enter()
                update()
                assert.are.equal(999003, ns.Focus_Quest())
            end)

            it("with none of them tracked, picks nothing", function()
                enter()
                tracked[999003] = nil
                update()
                assert.is_nil(ns.Focus_Quest())
            end)

            it("outside it, or in another instance, all the tracked quests count", function()
                update()
                assert.are.equal(999001, ns.Focus_Quest())
                ns.Focus_Clear()
                _G.GetInstanceInfo = function() return "Elsewhere", "party", 1, "", 5, 0, false, 1 end
                ns.Focus_SetAuto(true)
                assert.are.equal(999001, ns.Focus_Quest())
            end)

            it("Auto in the menu goes by the same quests", function()
                enter()
                ns.Focus_Auto()
                assert.are.equal(999003, ns.Focus_Quest())
            end)
        end)

        describe("with nothing focused", function()
            it("focuses the quest with the nearest objective", function()
                update()
                assert.are.equal(999001, ns.Focus_Quest()) -- the wolves, 10 yd
                assert.is_true(frame:IsShown())
                assert.near(0.6, WowMock.userWaypoint.x, 1e-9)
            end)

            it("sets Blizzard's tracker to the quest it picks, unless that is switched off", function()
                update()
                assert.are.equal(999001, ns.Focus_Quest())
                assert.are.equal(999001, WowMock.superTrackedQuest)
                assert.are.equal(1, WowMock.superTrackCalls)
                ns.Focus_Clear()
                WowMock.superTrackedQuest, WowMock.superTrackCalls = 0, 0
                ns.char.setBlizzardFocus = false
                ns.Focus_SetAuto(true)
                assert.are.equal(999001, ns.Focus_Quest())
                assert.are.equal(0, WowMock.superTrackCalls)
            end)

            it("prefers objectives to turn-ins, even nearer ones", function()
                ready(999003)
                distance[31] = 1
                update()
                assert.are.equal(999001, ns.Focus_Quest())
            end)

            it("with no objectives left anywhere, the nearest turn-in", function()
                objectives(true, true)
                ready(999001); ready(999003); ready(999004)
                update()
                assert.are.equal(999003, ns.Focus_Quest()) -- the foxes' turn-in, 60 yd (the others: 300, 950)
                distance[20] = 30
                ns.Focus_Clear(true) -- (turned in, say)
                assert.are.equal(999001, ns.Focus_Quest())
                assert.matches("Turn in Pest Control", shownTexts()[1])
            end)

            it("skips the quests whose distance isn't known, and leaves the window empty if none is", function()
                distance = {}
                update()
                assert.is_nil(ns.Focus_Quest())
                assert.is_true(frame:IsShown()) -- it says so, for the player to choose
                assert.are.equal("No quest focused", frame.title._text)
                assert.matches("Click to choose another", shownTexts()[1])
                ns.DistanceTo = function(loc) return loc.x == 80 and 900 or nil end
                update()
                assert.are.equal(999004, ns.Focus_Quest())
            end)

            it("only looks at the tracked quests", function()
                tracked = { [999004] = true }
                update()
                assert.are.equal(999004, ns.Focus_Quest())
            end)

            it("does nothing with the setting off", function()
                ns.char.focusAuto = nil
                update()
                assert.is_nil(ns.Focus_Quest())
            end)

            it("picks up again when the focused quest is turned in or abandoned", function()
                assert.is_true(ns.Focus_Set(999004))
                turnIn(999004)
                assert.are.equal(999001, ns.Focus_Quest())
                WowMock.onQuest[999001] = nil
                FireEvent("QUEST_REMOVED", 999001)
                assert.are.equal(999003, ns.Focus_Quest())
            end)

            it("catches up as the clock ticks, when the distances become known", function()
                local real = ns.DistanceTo
                ns.DistanceTo = function() return nil end
                update()
                assert.is_nil(ns.Focus_Quest())
                ns.DistanceTo = real
                tick()
                assert.are.equal(999001, ns.Focus_Quest())
            end)

            it("closing the window, or unfocusing by hand, pauses it until a quest is focused or the setting is switched", function()
                update()
                frame.close:Click()
                assert.is_nil(ns.Focus_Quest())
                tick(); update()
                assert.is_nil(ns.Focus_Quest())
                assert.is_false(frame:IsShown())
                ns.Focus_SetAuto(true)
                assert.are.equal(999001, ns.Focus_Quest())
                ns.Focus_Toggle(999001) -- unfocused from the list
                tick()
                assert.is_nil(ns.Focus_Quest())
                assert.is_true(ns.Focus_Set(999003)) -- by hand: it is back on
                assert.are.equal(999003, ns.Focus_Quest())
            end)

            it("is quiet in combat", function()
                WowMock.inCombat = true
                update()
                assert.is_nil(ns.Focus_Quest())
                WowMock.inCombat = false
                tick()
                assert.are.equal(999001, ns.Focus_Quest())
            end)
        end)

        describe("with the focused quest ready to turn in", function()
            local function finish()
                objectives(true, true)
                ready(999001)
                update()
            end
            before_each(function()
                assert.is_true(ns.Focus_Set(999001, true))
                frame = CompletaoFocusFrame
            end)

            it("goes to the quest with the nearest objective or turn-in", function()
                finish() -- its turn-in: 300 yd; the foxes are at 40
                assert.are.equal(999003, ns.Focus_Quest())
                assert.near(0.3, WowMock.userWaypoint.x, 1e-9)
            end)

            it("a turn-in counts too", function()
                ready(999004)
                distance[81] = 5
                finish()
                assert.are.equal(999004, ns.Focus_Quest())
            end)

            it("stays when its own turn-in is the nearest", function()
                distance[20] = 5
                finish()
                assert.are.equal(999001, ns.Focus_Quest())
                assert.matches("Turn in Pest Control", shownTexts()[1])
            end)

            it("goes on when its own distance isn't known", function()
                distance[20] = nil
                finish()
                assert.are.equal(999003, ns.Focus_Quest())
            end)

            it("stays when no other quest has a known distance", function()
                distance[30], distance[80], distance[10], distance[60] = nil, nil, nil, nil
                finish()
                assert.are.equal(999001, ns.Focus_Quest())
            end)

            it("keeps following the nearest while it is ready", function()
                distance[30] = 500
                distance[20] = 100
                finish()
                assert.are.equal(999001, ns.Focus_Quest())
                distance[30] = 1 -- now the foxes are by the player
                tick()
                assert.are.equal(999003, ns.Focus_Quest())
            end)

            it("does nothing with the setting off", function()
                ns.char.focusAuto = nil
                finish()
                assert.are.equal(999001, ns.Focus_Quest())
            end)
        end)

        describe("when a quest is accepted", function()
            local function accept(id, x)
                distance[x] = 1 -- its objective is right here
                tracked[id] = true
                WowMock.onQuest[id] = true
                WowMock.log[#WowMock.log + 1] = { questID = id, title = "New " .. id, level = 20 }
                FireEvent("QUEST_ACCEPTED", 1, id)
                frame = CompletaoFocusFrame
            end

            it("is looked at, but the focus stays on a quest still in progress", function()
                assert.is_true(ns.Focus_Set(999001, true))
                accept(999004, 80)
                assert.are.equal(999001, ns.Focus_Quest())
            end)

            it("the focus goes to it when the focused quest is ready and the new one has objectives nearer", function()
                assert.is_true(ns.Focus_Set(999001, true))
                objectives(true, true)
                ready(999001)
                distance[20] = 5 -- its own turn-in is 5 yd away: it stays
                FireEvent("QUEST_LOG_UPDATE")
                assert.are.equal(999001, ns.Focus_Quest())
                accept(999004, 80) -- the new one's objective: 1 yd
                assert.are.equal(999004, ns.Focus_Quest())
            end)

            it("not when the new one is farther than the ready quest's turn-in", function()
                assert.is_true(ns.Focus_Set(999001, true))
                objectives(true, true)
                ready(999001)
                distance[20] = 0.5
                FireEvent("QUEST_LOG_UPDATE")
                accept(999004, 80) -- 1 yd, against a turn-in 0.5 yd away
                assert.are.equal(999001, ns.Focus_Quest())
            end)

            describe("a direct turn-in", function()
                -- Owl Watch (999004) is the one just accepted; Pest Control (999001) is focused, its wolves 10 yd away
                local function acceptTurnIn(turnInX, turnInDist)
                    tracked = { [999001] = true }
                    WowMock.log = { { isHeader = true, title = "Zone" }, { questID = 999001, title = "Pest", level = 20 } }
                    WowMock.onQuest[999004] = nil
                    assert.is_true(ns.Focus_Set(999001))
                    distance[turnInX] = turnInDist
                    tracked[999004] = true
                    WowMock.onQuest[999004] = true
                    WowMock.log[#WowMock.log + 1] = { questID = 999004, title = "Owl Watch", level = 20 }
                    ready(999004) -- ready the moment it is taken
                    FireEvent("QUEST_ACCEPTED", 2, 999004)
                    frame = CompletaoFocusFrame
                end

                it("takes the focus from a quest in progress when its turn-in is nearer", function()
                    acceptTurnIn(81, 3) -- 3 yd, against the wolves at 10
                    assert.are.equal(999004, ns.Focus_Quest())
                    assert.matches("Turn in Owl Watch", shownTexts()[1])
                end)

                it("not when its turn-in is farther than what the focused quest needs next", function()
                    acceptTurnIn(81, 50)
                    assert.are.equal(999001, ns.Focus_Quest())
                end)

                it("takes it when the focused quest has no known spot to go to", function()
                    distance[wolves.x], distance[boars.x] = nil, nil
                    acceptTurnIn(81, 50)
                    assert.are.equal(999004, ns.Focus_Quest())
                end)

                it("only counts in the moments after it is accepted, not when it becomes ready much later", function()
                    tracked = { [999001] = true, [999004] = true }
                    WowMock.log = { { isHeader = true, title = "Zone" }, { questID = 999001, title = "Pest", level = 20 },
                        { questID = 999004, title = "Owl Watch", level = 20 } }
                    assert.is_true(ns.Focus_Set(999001))
                    FireEvent("QUEST_ACCEPTED", 2, 999004) -- accepted with objectives to do
                    WowMock.time = 100
                    distance[81] = 1
                    ready(999004) -- and finished ages later
                    FireEvent("QUEST_LOG_UPDATE")
                    assert.are.equal(999001, ns.Focus_Quest())
                    WowMock.time = 0
                end)

                it("does nothing with autofocus off, or when the new quest isn't tracked", function()
                    ns.char.focusAuto = nil
                    acceptTurnIn(81, 3)
                    assert.are.equal(999001, ns.Focus_Quest())
                    ns.char.focusAuto = true
                    ns.Focus_Set(999001)
                    tracked[999004] = nil
                    FireEvent("QUEST_ACCEPTED", 2, 999004)
                    assert.are.equal(999001, ns.Focus_Quest())
                end)
            end)

            it("is chosen when nothing is focused, if it is the nearest", function()
                tracked = {}
                WowMock.log = { { isHeader = true, title = "Zone" } }
                ns.Focus_Clear(true)
                assert.is_nil(ns.Focus_Quest()) -- "No quest focused": nothing tracked
                accept(999004, 80)
                assert.are.equal(999004, ns.Focus_Quest())
            end)

            it("when nothing is focused and another tracked quest is nearer, that one stays the pick", function()
                ns.Focus_Clear(true)
                assert.are.equal(999001, ns.Focus_Quest()) -- the wolves, 10 yd
                ns.Focus_Clear(true)
                distance[60] = 0.5
                ns.Focus_Clear(true)
                accept(999004, 80) -- 1 yd: farther than the wolves now
                assert.are.equal(999001, ns.Focus_Quest())
            end)
        end)

        describe("with the focused quest still in progress", function()
            it("stays, however near the other quests are", function()
                assert.is_true(ns.Focus_Set(999001))
                distance[30] = 1
                update(); tick()
                assert.are.equal(999001, ns.Focus_Quest())
            end)

            it("a quest that was ready when focused by hand is left alone", function()
                objectives(true, true)
                ready(999001)
                assert.is_true(ns.Focus_Set(999001))
                update(); tick()
                assert.are.equal(999001, ns.Focus_Quest())
                assert.is_true(ns.Focus_Set(999001, true)) -- but one chosen by autofocus is not
                update()
                assert.are.equal(999003, ns.Focus_Quest())
            end)
        end)
    end)

    describe("following Blizzard's quest tracker", function()
        -- the player focuses `id` in Blizzard's tracker (or its quest log)
        local function blizzardFocuses(id)
            WowMock.superTrackedQuest = id
            FireEvent("SUPER_TRACKING_CHANGED")
        end

        before_each(function()
            WowMock.onQuest[999003] = true
        end)

        it("focuses here the quest the player focuses there, on by default", function()
            blizzardFocuses(999003)
            assert.are.equal(999003, ns.Focus_Quest())
            blizzardFocuses(999001)
            assert.are.equal(999001, ns.Focus_Quest())
        end)

        it("is by hand: autofocus leaves the quest be", function()
            ns.char.focusAuto = true
            blizzardFocuses(999003)
            ns.DistanceTo = function(loc) return loc.x == wolves.x and 1 or 200 end
            FireEvent("QUEST_LOG_UPDATE")
            assert.are.equal(999003, ns.Focus_Quest())
        end)

        it("ignores what isn't a quest in the log, and the game clearing its choice", function()
            blizzardFocuses(999001)
            blizzardFocuses(999004) -- not in the log
            assert.are.equal(999001, ns.Focus_Quest())
            blizzardFocuses(0)
            assert.are.equal(999001, ns.Focus_Quest())
        end)

        it("does nothing when switched off", function()
            ns.char.followBlizzardFocus = false
            blizzardFocuses(999003)
            assert.is_nil(ns.Focus_Quest())
        end)

        describe("and the other way: focusing here sets Blizzard's tracker", function()
            it("a quest focused by hand becomes Blizzard's focused quest, once", function()
                WowMock.superTrackedQuest = 999001
                assert.is_true(ns.Focus_Set(999003))
                assert.are.equal(999003, WowMock.superTrackedQuest)
                assert.are.equal(999003, ns.Focus_Quest()) -- the game's change event doesn't bounce back
                assert.are.equal(1, WowMock.superTrackCalls)
                assert.is_true(ns.Focus_Set(999003))
                assert.are.equal(1, WowMock.superTrackCalls) -- already there
            end)

            it("so does one chosen by autofocus", function()
                assert.is_true(ns.Focus_Set(999003, true))
                assert.are.equal(999003, WowMock.superTrackedQuest)
                assert.are.equal(1, WowMock.superTrackCalls)
            end)

            it("toggling the focus on does it", function()
                ns.Focus_Toggle(999003)
                assert.are.equal(999003, WowMock.superTrackedQuest)
            end)

            it("a quest Blizzard focused is not told back to Blizzard", function()
                blizzardFocuses(999003)
                assert.are.equal(0, WowMock.superTrackCalls)
            end)

            it("does nothing when switched off", function()
                ns.char.setBlizzardFocus = false
                assert.is_true(ns.Focus_Set(999003))
                assert.is_true(ns.Focus_Set(999001, true))
                assert.are.equal(0, WowMock.superTrackCalls)
                assert.are.equal(999001, ns.Focus_Quest())
            end)
        end)

        it("switching it on in the Preferences takes the quest Blizzard has focused now", function()
            ns.char.followBlizzardFocus = false
            WowMock.superTrackedQuest = 999003
            ns.Prefs_Toggle()
            local checks = WowMock.FindAll(function(f)
                return f._kind == "CheckButton" and f._parent == CompletaoPreferencesFrame
            end)
            local check = checks[9] -- (see Preferences.test.lua for the order)
            assert.is_false(check:GetChecked())
            check:SetChecked(true); check:Click()
            assert.are.equal(999003, ns.Focus_Quest())
        end)
    end)

    describe("right click: the menu to choose the quest", function()
        local tracked, distance
        local function ready(id) WowMock.readyForTurnIn[id] = true end
        local function rightClick() frame._scripts.OnMouseUp(frame, "RightButton") end
        -- the options of the menu that is showing, in order
        local function menu()
            return WowMock.FindAll(function(f)
                return f.text and f._scripts.OnClick and f._parent and f._parent.buttons and f:IsVisible()
            end)
        end
        local function names()
            local out = {}
            for i, b in ipairs(menu()) do out[i] = b.text._text end
            return out
        end
        local function pick(text)
            for _, b in ipairs(menu()) do
                if b.text._text:find(text, 1, true) then b:Click() return end
            end
            error("no option " .. text)
        end
        before_each(function()
            -- Pest Control's wolves 10 yd (boars 200); Fox Hunt's foxes 40; Owl Watch's owls 900
            distance = { [boars.x] = 200, [wolves.x] = 10, [30] = 40, [80] = 900, [81] = 950, [31] = 60 }
            ns.DistanceTo = function(loc) return distance[loc.x] end
            tracked = { [999001] = true, [999003] = true, [999004] = true }
            WowMock.log = { { isHeader = true, title = "Zone" } }
            for _, id in ipairs({ 999001, 999003, 999004 }) do
                WowMock.onQuest[id] = true
                WowMock.log[#WowMock.log + 1] = { questID = id, title = "Quest " .. id, level = 20 }
            end
            WowMock.titles[999003], WowMock.titles[999004] = "Fox Hunt", "Owl Watch"
            C_QuestLog.GetQuestWatchType = function(id) return tracked[id] and 0 or nil end
            focus()
        end)
        after_each(function() C_QuestLog.GetQuestWatchType = nil end)

        it("opens Auto and the tracked quests by distance, with level and the focused one ticked", function()
            rightClick()
            local list = names()
            assert.are.equal(4, #list)
            assert.are.equal("Auto", list[1])
            assert.matches("|t %[20%] Pest Control", list[2])
            assert.matches("UI%-CheckBox%-Check", list[2]) -- the focused one
            assert.matches("|t %[20%] Fox Hunt$", list[3])
            assert.matches("|t %[20%] Owl Watch$", list[4])
        end)

        it("shows the quest's status icon: ? when ready to turn in, ... while in progress", function()
            ready(999004)
            rightClick()
            local list = names()
            assert.are.equal("Auto", list[1]) -- no icon
            assert.matches("IncompleteQuestIcon", list[2])
            assert.matches("IncompleteQuestIcon", list[3])
            assert.matches("ActiveQuestIcon", list[4])
        end)

        it("colors each quest by its difficulty", function()
            rightClick()
            assert.are.same({ ns.QuestLevelColorRGB(20) }, { menu()[3].text:GetTextColor() })
        end)

        it("marks dungeon and elite quests with D and +", function()
            ns.FindQuestDef(999003).dungeon = true
            C_QuestLog.GetQuestTagInfo = function(id) return id == 999004 and 1 or 0 end
            rightClick()
            C_QuestLog.GetQuestTagInfo = nil
            local list = names()
            assert.matches("|t %[20D%] Fox Hunt$", list[3])
            assert.matches("|t %[20%+%] Owl Watch$", list[4])
        end)

        it("puts the quests whose distance can't be told last", function()
            distance[30] = nil -- the foxes
            rightClick()
            local list = names()
            assert.matches("Pest Control", list[2])
            assert.matches("Owl Watch", list[3])
            assert.matches("Fox Hunt", list[4])
        end)

        it("a turn-in counts by the distance to whoever takes it in", function()
            ready(999004)
            distance[81] = 5
            rightClick()
            assert.matches("Owl Watch", names()[2])
        end)

        it("only the tracked quests are in it", function()
            tracked[999003] = nil
            rightClick()
            assert.are.equal(3, #names())
        end)

        it("inside a dungeon, only the quests done in it", function()
            ns.RegisterEntry({ id = "dng", name = "Test Dungeon", instanceId = 777 })
            ns.FindQuestDef(999003).dungeon = "dng"
            _G.GetInstanceInfo = function() return "Test Dungeon", "party", 1, "", 5, 0, false, 777 end
            rightClick()
            _G.GetInstanceInfo = nil
            local list = names()
            assert.are.equal(2, #list)
            assert.are.equal("Auto", list[1])
            assert.matches("Fox Hunt", list[2])
        end)

        it("picking a quest focuses it, with its waypoint", function()
            rightClick()
            pick("Fox Hunt")
            assert.are.equal(999003, ns.Focus_Quest())
            assert.matches("Fox Hunt", frame.title._text)
            assert.near(0.3, WowMock.userWaypoint.x, 1e-9)
        end)

        it("also from an objective line", function()
            lineWith("Boars"):Click("RightButton")
            assert.are.equal(4, #names())
            pick("Owl Watch")
            assert.are.equal(999004, ns.Focus_Quest())
        end)

        it("with nothing focused it still lists the quests", function()
            ns.Focus_Clear()
            rightClick()
            assert.are.equal(4, #names())
            pick("Fox Hunt")
            assert.are.equal(999003, ns.Focus_Quest())
        end)

        it("is by hand: a quest ready to turn in stays under autofocus", function()
            ns.char.focusAuto = true
            distance[31], distance[30] = 1, 1000 -- the foxes' turn-in is very near
            ready(999003)
            rightClick()
            pick("Fox Hunt")
            assert.are.equal(999003, ns.Focus_Quest())
            distance[81], distance[31] = 0.1, 500
            ready(999004)
            FireEvent("QUEST_LOG_UPDATE")
            assert.are.equal(999003, ns.Focus_Quest())
        end)

        describe("Auto", function()
            it("focuses the nearest tracked quest, and leaves the Autofocus setting as it was", function()
                for _, setting in ipairs({ true, false }) do
                    ns.char.focusAuto = setting or nil
                    ns.Focus_Set(999004)
                    rightClick()
                    pick("Auto")
                    assert.are.equal(999001, ns.Focus_Quest()) -- the wolves, 10 yd
                    assert.are.equal(setting or nil, ns.char.focusAuto)
                end
            end)

            it("counts a turn-in by the distance to whoever takes it in", function()
                ready(999004)
                distance[81] = 5
                rightClick()
                pick("Auto")
                assert.are.equal(999004, ns.Focus_Quest())
            end)

            it("is by hand: a quest ready to turn in stays under autofocus", function()
                ns.char.focusAuto = true
                distance[31], distance[30] = 1, 1000 -- the foxes' turn-in is very near
                ready(999003)
                rightClick()
                pick("Auto")
                assert.are.equal(999003, ns.Focus_Quest())
                distance[81], distance[31] = 0.1, 500
                ready(999004)
                FireEvent("QUEST_LOG_UPDATE")
                assert.are.equal(999003, ns.Focus_Quest())
            end)

            it("with no quest it can go to, says so", function()
                for id in pairs(tracked) do tracked[id] = nil end
                rightClick()
                pick("Auto")
                assert.is_true(WowMock.chatted)
            end)
        end)

        it("the same click again closes the menu", function()
            rightClick()
            rightClick()
            assert.are.equal(0, #menu())
        end)

        it("a left click on the window closes it", function()
            rightClick()
            frame._scripts.OnMouseDown(frame, "LeftButton")
            frame._scripts.OnMouseUp(frame, "LeftButton")
            assert.are.equal(0, #menu())
        end)

        it("does nothing in combat, where the window takes no clicks", function()
            rightClick()
            FireEvent("PLAYER_REGEN_DISABLED")
            assert.is_false(frame:IsMouseEnabled())
            assert.are.equal(0, #menu())
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

        it("right click on a quest opens its menu, where Focus focuses it and then stops", function()
            local function choose(label)
                local option = WowMock.Find(function(f)
                    return f.text and f.text._text == label and f._scripts.OnClick and f._shown and f._parent and f._parent.buttons
                end)
                option:Click()
            end
            local row = ShownRows()[1]
            row:Click("RightButton")
            choose("Focus")
            assert.are.equal(999001, ns.Focus_Quest())
            assert.is_true(CompletaoFocusFrame:IsShown())
            row:Click("RightButton")
            choose("Stop focus")
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
