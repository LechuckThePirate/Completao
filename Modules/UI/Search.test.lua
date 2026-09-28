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

    it("sin criterios lista las quests de tu nivel sin hacer", function()
        assert.is_true(#ShownRows() > 50)
    end)

    it("busca por titulo en todas las secciones", function()
        typeText("defias brother")
        local rows = ShownRows()
        assert.is_true(ids(rows)[166])
        assert.is_true(#rows < 10)
    end)

    it("las completadas no salen salvo con Incluir: completadas", function()
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

    it("filtra por tipo de recompensa (Arma) y desactiva 'solo con objetos'", function()
        panel.typeButton:Click()
        local weapon = WowMock.Find(function(f) return f.text and f.text._text == "Weapon" and f._scripts.OnClick end)
        weapon:Click()
        local rows = ShownRows()
        assert.are.equal(1, #rows)
        assert.are.equal(166, rows[1].quest.id)
        assert.is_false(panel.itemsOnly:IsEnabled())
        assert.is_true(panel.subButton:IsEnabled())
    end)

    it("solo con objetos quita las que solo dan dinero", function()
        panel.itemsOnly:SetChecked(true); panel.itemsOnly:Click()
        local found = ids(ShownRows())
        assert.is_nil(found[167])
    end)

    it("ordena por dinero (de mas a menos, y al reves) y lo muestra en su columna", function()
        panel.head.money:Click()
        local rows = ShownRows()
        local function money(r) return (ns.REWARDS[r.quest.id] or {}).money or 0 end
        for i = 2, #rows do assert.is_true(money(rows[i - 1]) >= money(rows[i])) end
        assert.are.equal(money(rows[1]) .. "c", rows[1].money:GetText())
        panel.head.money:Click()
        rows = ShownRows()
        for i = 2, #rows do assert.is_true(money(rows[i - 1]) <= money(rows[i])) end
    end)

    it("ordena por nivel y por titulo", function()
        panel.head.level:Click() -- ya esta por nivel ascendente: un clic lo invierte
        local rows = ShownRows()
        assert.is_true((rows[1].quest.level or 0) >= (rows[#rows].quest.level or 0))
        panel.head.name:Click()
        rows = ShownRows()
        assert.is_true(rows[1].quest.name:lower() <= rows[#rows].quest.name:lower())
    end)

    it("pulsar un resultado abre su arbol con la quest elegida", function()
        typeText("defias brother")
        local row = ShownRows()[1]
        row:Click()
        assert.is_false(panel:IsShown())
        assert.are.equal(row.quest.id, ns.Detail_Current().id)
    end)

    describe("vista del registro", function()
        before_each(function()
            WowMock.log = { { isHeader = true, title = "Westfall" }, { questID = 166, title = "The Defias Brotherhood", level = 22 },
                { isHeader = true, title = "Ashenvale" }, { questID = 999999, title = "Unknown Quest", level = 25 } }
            WowMock.onQuest[166], WowMock.onQuest[999999] = true, true
            ns.UI_SetSearchMode(true, "log")
        end)

        it("lista las quests del registro, sin formulario", function()
            local rows = ShownRows()
            assert.are.equal(2, #rows)
            assert.is_false(panel.box:IsShown())
        end)

        it("una quest sin datos del addon sale con su zona y se abre en el registro del juego", function()
            local unknown
            for _, r in ipairs(ShownRows()) do if r.quest.id == 999999 then unknown = r end end
            assert.are.equal("Ashenvale", unknown.whereText)
            local opened
            QuestMapFrame_OpenToQuestDetails = function(id) opened = id end
            unknown:Click()
            QuestMapFrame_OpenToQuestDetails = nil
            assert.are.equal(999999, opened)
        end)
    end)
end)
