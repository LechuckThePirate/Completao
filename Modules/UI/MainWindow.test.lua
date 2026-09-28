dofile("setupTests.lua")

describe("MainWindow", function()
    local ns

    before_each(function()
        WowMock.Reset()
        ns = OpenAddon("vc")
    end)

    it("se abre en la entrada guardada y dibuja su arbol", function()
        assert.is_true(ns.UI:IsShown())
        local _, n = ShownNodes()
        assert.is_true(n > 0)
    end)

    it("la barra lateral lleva el buscador, el registro y las secciones con su numero de entradas", function()
        for _, label in ipairs({ "Search quests...", "Quest Log" }) do
            local text = WowMock.FindByText(label)
            assert.is_not_nil(text, label)
            assert.is_not_nil(text:GetParent()._scripts.OnClick, label)
        end
        assert.is_not_nil(WowMock.Find(function(f) return type(f._text) == "string" and f._text:match("Dungeons %(%d+%)") end))
    end)

    describe("filtros", function()
        local parent, child

        before_each(function()
            -- una cadena de dos pasos de la entrada
            local inEntry = {}
            for _, q in ipairs(ns.entries.vc.quests) do inEntry[q.id] = q end
            for _, q in ipairs(ns.entries.vc.quests) do
                for _, p in ipairs(q.requires or {}) do
                    if inEntry[p] and not parent and ns.QuestVisible(q, ns.entries.vc) and ns.QuestVisible(inEntry[p], ns.entries.vc) then
                        parent, child = p, q.id
                    end
                end
            end
            for k in pairs(ns.char.filters) do ns.char.filters[k] = nil end
            WowMock.level = 20
        end)

        it("ocultar completadas oculta cada quest hecha, aunque su cadena siga", function()
            WowMock.done[parent] = true
            ns.char.filters.hideDone = true
            ns.UI_Refresh()
            local nodes = ShownNodes()
            assert.is_nil(nodes[parent])
            assert.is_not_nil(nodes[child])
            ns.char.filters.hideDone = false
            ns.UI_Refresh()
            assert.is_not_nil((ShownNodes())[parent])
        end)

        it("demasiado alto oculta las cadenas que aun no puedes empezar", function()
            WowMock.level = 5
            ns.char.filters.hideHigh = true
            ns.UI_Refresh()
            local _, n = ShownNodes()
            assert.are.equal(0, n)
        end)

        it("otra faccion: ocultas por defecto, visibles con la casilla", function()
            ns.UI_OpenQuest("rfc", 5722) -- Ragefire Chasm, de la Horda
            ns.Detail_Hide(); ns.UI_Refresh()
            local _, hidden = ShownNodes()
            ns.char.filters.otherFaction = true
            ns.UI_Refresh()
            local _, shown = ShownNodes()
            assert.are.equal(0, hidden)
            assert.is_true(shown > 0)
        end)
    end)

    it("al elegir una quest su cadena se resalta y el resto se atenua", function()
        local q = ns.entries.vc.quests[1]
        ns.UI_OpenQuest("vc", q.id)
        local nodes = ShownNodes()
        local dimmed = false
        for id, b in pairs(nodes) do
            if id ~= q.id and b:GetAlpha() < 0.5 then dimmed = true end
        end
        assert.are.equal(q.id, ns.Detail_Current().id)
        assert.is_true(dimmed)
    end)

    it("el buscador sustituye al arbol y elegir una entrada lo cierra", function()
        ns.UI_SetSearchMode(true)
        assert.is_false(ns.UI.treeScroll:IsShown())
        assert.is_true(ns.UI.searchPanel:IsShown())
        ns.UI_OpenQuest("vc", ns.entries.vc.quests[1].id)
        assert.is_true(ns.UI.treeScroll:IsShown())
        assert.is_false(ns.UI.searchPanel:IsShown())
    end)

    it("la rueda cambia el zoom y se guarda; SetZoom lo limita", function()
        local scroll = ns.UI.treeScroll
        scroll._scripts.OnMouseWheel(scroll, 1)
        assert.is_true(ns.char.zoom > 1)
        ns.UI_SetZoom(10)
        assert.are.equal(1.6, ns.char.zoom)
        ns.UI_SetZoom(0)
        assert.are.equal(0.35, ns.char.zoom)
    end)

    describe("transparencia al moverse", function()
        local function tick() for _ = 1, 60 do ns.UI._scripts.OnUpdate(ns.UI, 0.1) end end

        it("se vuelve translucida al andar y opaca al parar", function()
            WowMock.speed = 7
            tick()
            assert.near(0.5, ns.UI:GetAlpha(), 0.02)
            WowMock.speed = 0
            tick()
            assert.near(1, ns.UI:GetAlpha(), 0.02)
        end)

        it("con el cursor encima se queda opaca", function()
            WowMock.speed = 7
            ns.UI._mouseOver = true
            tick()
            assert.near(1, ns.UI:GetAlpha(), 0.02)
        end)

        it("con la velocidad oculta por el juego (combate) no cambia", function()
            WowMock.speed = 7
            issecretvalue = function() return true end
            tick()
            issecretvalue = nil
            assert.near(1, ns.UI:GetAlpha(), 0.02)
        end)
    end)

    it("el engranaje queda por encima del marco de la ventana", function()
        local gear = WowMock.Find(function(f) return f._set.SetNormalTexture and tostring(f._set.SetNormalTexture[1]):find("Gear") end)
        assert.is_not_nil(gear)
        gear:Click()
        assert.is_true(_G.CompletaoPreferencesFrame:IsShown())
    end)

    describe("abrir con el registro de misiones", function()
        before_each(function()
            ns.UI:Hide()
            ns.char.openWithQuestLog = true
            QuestLogFrame = WowMock.NewFrame("Frame", "QuestLogFrame")
            QuestLogFrame:Hide()
        end)

        local function logShown(v)
            QuestLogFrame:SetShown(v)
            ns.UI_QuestLogChanged()
        end

        it("desactivado no hace nada", function()
            ns.char.openWithQuestLog = nil
            logShown(true)
            assert.is_false(ns.UI:IsShown())
        end)

        it("abrir el registro la abre y cerrarlo la cierra", function()
            logShown(true)
            assert.is_true(ns.UI:IsShown())
            logShown(false)
            assert.is_false(ns.UI:IsShown())
        end)

        it("si ya estaba abierta a mano, cerrar el registro no la cierra", function()
            ns.UI:Show()
            logShown(true)
            logShown(false)
            assert.is_true(ns.UI:IsShown())
        end)
    end)
end)
