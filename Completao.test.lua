dofile("setupTests.lua")

describe("Completao (startup)", function()
    local ns

    before_each(function()
        WowMock.Reset()
        ns = LoadAddon()
    end)

    it("loads every TOC file and registers the sections", function()
        assert.is_true(#ns.entryList > 100)
        assert.is_not_nil(ns.entries.vc)
        assert.is_not_nil(ns.FindQuestDef(166))
    end)

    it("on entering, sets up the saved variables and announces in chat", function()
        StartAddon(ns)
        assert.is_not_nil(CompletaoDB)
        assert.is_true(CompletaoCharDB.perCharacter)
        assert.matches("initializing", WowMock.printed[1])
        assert.matches("initialization complete %(%d+ quests%)", WowMock.printed[2])
    end)

    it("with messages turned off, writes nothing to chat", function()
        StartAddon(ns, nil, { quiet = true })
        assert.are.equal(0, #WowMock.printed)
    end)

    it("defines the key bindings and their names", function()
        assert.is_not_nil(BINDING_NAME_COMPLETAO_TOGGLE)
        assert.is_not_nil(BINDING_NAME_COMPLETAO_PREFS)
        assert.are.equal("function", type(Completao_Toggle))
        assert.are.equal("function", type(Completao_TogglePreferences))
    end)

    describe("keeping the window up to date", function()
        local id

        before_each(function()
            ns = OpenAddon("vc")
            for _, q in ipairs(ns.entries.vc.quests) do
                if ns.QuestVisible(q, ns.entries.vc) then id = q.id break end
            end
        end)

        local function status() return (ShownNodes())[id].status end

        it("taking a quest redraws its box as in progress", function()
            assert.are_not.equal("active", status())
            WowMock.onQuest[id] = true
            FireEvent("QUEST_ACCEPTED", 1, id)
            assert.are.equal("active", status())
        end)

        it("progress and turning in redraw it too", function()
            WowMock.onQuest[id] = true
            FireEvent("QUEST_LOG_UPDATE")
            WowMock.readyForTurnIn[id] = true
            FireEvent("UNIT_QUEST_LOG_CHANGED", "player")
            assert.is_true((ShownNodes())[id].ready:IsShown())
            WowMock.done[id], WowMock.onQuest[id] = true, nil
            FireEvent("QUEST_TURNED_IN", id)
            assert.are.equal("done", status())
            assert.is_false((ShownNodes())[id].ready:IsShown())
        end)

        it("abandoning a quest redraws it as available again", function()
            WowMock.onQuest[id] = true
            FireEvent("QUEST_LOG_UPDATE")
            assert.are.equal("active", status())
            WowMock.onQuest[id] = nil
            FireEvent("QUEST_REMOVED", id)
            assert.are_not.equal("active", status())
        end)

        it("levelling up redraws the tree with the level filters", function()
            ns.char.filters.hideHigh = true
            WowMock.level = 5
            ns.UI_Refresh()
            assert.are.equal(0, select(2, ShownNodes()))
            WowMock.level = 20
            FireEvent("PLAYER_LEVEL_UP", 20)
            assert.is_true(select(2, ShownNodes()) > 0)
        end)

        it("a level event redraws again a moment later, when the client's level is up to date", function()
            local refreshes = 0
            local real = ns.UI_Refresh
            ns.UI_Refresh = function() refreshes = refreshes + 1; return real() end
            local timers = {}
            _G.C_Timer.After = function(_, f) timers[#timers + 1] = f end -- collect the timers, run them by hand
            FireEvent("PLAYER_LEVEL_UP", 21)
            assert.is_true(#timers >= 1)
            local i = 1
            while timers[i] do timers[i](); i = i + 1 end
            assert.is_true(refreshes >= 2)
            _G.C_Timer.After = function(_, f) f() end
        end)

        it("an event the client doesn't know doesn't stop the others from being registered", function()
            WowMock.Reset()
            WowMock.unknownEvents = { PLAYER_LEVEL_CHANGED = true }
            local fresh = LoadAddon()
            StartAddon(fresh)
            local registered = {}
            for _, f in ipairs(WowMock.frames) do
                for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "PLAYER_LEVEL_UP" }) do
                    if f._events and f._events[e] then registered[e] = true end
                end
            end
            for _, e in ipairs({ "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "QUEST_TURNED_IN", "PLAYER_LEVEL_UP" }) do
                assert.is_true(registered[e], e)
            end
        end)
    end)

    describe("/completao", function()
        before_each(function() StartAddon(ns) end)

        it("with no arguments opens and closes the window", function()
            SlashCmdList.COMPLETAO("")
            assert.is_true(ns.UI:IsShown())
            SlashCmdList.COMPLETAO("")
            assert.is_false(ns.UI:IsShown())
        end)

        it("fade saves the opacity while moving", function()
            SlashCmdList.COMPLETAO("fade 30")
            assert.are.equal(0.3, ns.char.fadeAlpha)
            SlashCmdList.COMPLETAO("fade 500")
            assert.are.equal(1, ns.char.fadeAlpha)
        end)

        it("dump lists the quests in the log", function()
            WowMock.log = { { isHeader = true, title = "Westfall" }, { questID = 166, title = "The Defias Brotherhood", level = 22 } }
            SlashCmdList.COMPLETAO("dump")
            assert.matches("166 %- The Defias Brotherhood", WowMock.printed[#WowMock.printed])
        end)

        it("an unknown command shows the help", function()
            SlashCmdList.COMPLETAO("foo")
            assert.matches("Usage", WowMock.printed[#WowMock.printed])
        end)
    end)
end)
