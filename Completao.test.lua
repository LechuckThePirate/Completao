dofile("setupTests.lua")

describe("Completao (arranque)", function()
    local ns

    before_each(function()
        WowMock.Reset()
        ns = LoadAddon()
    end)

    it("carga todos los archivos del TOC y registra las secciones", function()
        assert.is_true(#ns.entryList > 100)
        assert.is_not_nil(ns.entries.vc)
        assert.is_not_nil(ns.FindQuestDef(166))
    end)

    it("al entrar prepara las variables guardadas y avisa en el chat", function()
        StartAddon(ns)
        assert.is_not_nil(CompletaoDB)
        assert.is_true(CompletaoCharDB.perCharacter)
        assert.matches("initializing", WowMock.printed[1])
        assert.matches("initialization complete %(%d+ quests%)", WowMock.printed[2])
    end)

    it("con los mensajes desactivados no escribe en el chat", function()
        StartAddon(ns, nil, { quiet = true })
        assert.are.equal(0, #WowMock.printed)
    end)

    it("define los atajos de teclado y sus nombres", function()
        assert.is_not_nil(BINDING_NAME_COMPLETAO_TOGGLE)
        assert.is_not_nil(BINDING_NAME_COMPLETAO_PREFS)
        assert.are.equal("function", type(Completao_Toggle))
        assert.are.equal("function", type(Completao_TogglePreferences))
    end)

    describe("/completao", function()
        before_each(function() StartAddon(ns) end)

        it("sin argumentos abre y cierra la ventana", function()
            SlashCmdList.COMPLETAO("")
            assert.is_true(ns.UI:IsShown())
            SlashCmdList.COMPLETAO("")
            assert.is_false(ns.UI:IsShown())
        end)

        it("fade guarda la opacidad al moverse", function()
            SlashCmdList.COMPLETAO("fade 30")
            assert.are.equal(0.3, ns.char.fadeAlpha)
            SlashCmdList.COMPLETAO("fade 500")
            assert.are.equal(1, ns.char.fadeAlpha)
        end)

        it("dump lista las quests del registro", function()
            WowMock.log = { { isHeader = true, title = "Westfall" }, { questID = 166, title = "The Defias Brotherhood", level = 22 } }
            SlashCmdList.COMPLETAO("dump")
            assert.matches("166 %- The Defias Brotherhood", WowMock.printed[#WowMock.printed])
        end)

        it("un comando desconocido muestra la ayuda", function()
            SlashCmdList.COMPLETAO("foo")
            assert.matches("Usage", WowMock.printed[#WowMock.printed])
        end)
    end)
end)
