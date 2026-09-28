dofile("setupTests.lua")

describe("Entries", function()
    local ns

    before_each(function()
        WowMock.Reset()
        ns = LoadAddon({ files = { "Modules/Database/Entries.lua", "Modules/Quest/QuestState.lua" } })
    end)

    it("registra entradas con seccion por defecto 'dungeons'", function()
        ns.RegisterEntry({ id = "dm", name = "The Deadmines" })
        assert.are.equal("dungeons", ns.entries.dm.category)
        assert.are.same({}, ns.entries.dm.quests)
        assert.are.equal(ns.entries.dm, ns.entryList[1])
    end)

    it("anade quests a una entrada y apunta su entrada", function()
        ns.RegisterEntry({ id = "dm", name = "The Deadmines" })
        ns.AddQuests("dm", { { id = 166, name = "The Defias Brotherhood" } })
        assert.are.equal(1, #ns.entries.dm.quests)
        assert.are.equal("dm", ns.entries.dm.quests[1].entryId)
    end)

    it("ignora quests de una entrada que no existe", function()
        assert.has_no.errors(function() ns.AddQuests("nope", { { id = 1, name = "x" } }) end)
        assert.is_nil(ns.FindQuestDef(1))
    end)

    it("PatchQuest corrige todas las copias de una quest y false borra el campo", function()
        ns.RegisterEntry({ id = "a", name = "A", category = "zones" })
        ns.RegisterEntry({ id = "b", name = "B" })
        ns.AddQuests("a", { { id = 5, name = "Q", requires = { 4 } } })
        ns.AddQuests("b", { { id = 5, name = "Q", requires = { 4 } } })
        ns.PatchQuest(5, { level = 10, requires = false })
        for _, e in ipairs({ "a", "b" }) do
            assert.are.equal(10, ns.entries[e].quests[1].level)
            assert.is_nil(ns.entries[e].quests[1].requires)
        end
    end)

    it("FindQuestDef devuelve la primera copia", function()
        ns.RegisterEntry({ id = "a", name = "A" })
        ns.AddQuests("a", { { id = 7, name = "Seven" } })
        assert.are.equal("Seven", ns.FindQuestDef(7).name)
    end)

    it("SetEntrance guarda la puerta de la instancia", function()
        ns.RegisterEntry({ id = "dm", name = "DM" })
        ns.SetEntrance("dm", { area = 40, x = 42.5, y = 71.7 })
        assert.are.equal(42.5, ns.entries.dm.entrance.x)
    end)

    describe("EntryName", function()
        it("zonas: el nombre del cliente", function()
            assert.are.equal("Area12", ns.EntryName({ category = "zones", area = 12, name = "Elwynn Forest" }))
        end)
        it("clases: el nombre localizado de la clase", function()
            assert.are.equal("Mage", ns.EntryName({ classFile = "MAGE", name = "x" }))
        end)
        it("razas: el nombre de la raza del cliente", function()
            assert.are.equal("Race2", ns.EntryName({ raceId = 2, name = "Orc" }))
        end)
        it("profesiones: el nombre del cliente si lo da; si no, el de los datos", function()
            assert.are.equal("Fishing", ns.EntryName({ skillLine = 356, name = "Fishing" }))
            C_TradeSkillUI = { GetTradeSkillDisplayName = function() return "Pesca" end }
            assert.are.equal("Pesca", ns.EntryName({ skillLine = 356, name = "Fishing" }))
            C_TradeSkillUI = nil
        end)
    end)

    it("EntryProgress cuenta hechas sobre las que ve el personaje", function()
        ns.RegisterEntry({ id = "a", name = "A", category = "zones" })
        ns.AddQuests("a", { { id = 1, name = "a" }, { id = 2, name = "b" }, { id = 3, name = "horde", faction = "Horde" } })
        WowMock.done[1] = true
        local done, total = ns.EntryProgress(ns.entries.a)
        assert.are.equal(1, done)
        assert.are.equal(2, total)
    end)
end)
