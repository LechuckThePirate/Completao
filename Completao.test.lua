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
