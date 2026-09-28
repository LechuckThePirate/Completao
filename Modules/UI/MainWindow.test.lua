dofile("setupTests.lua")

describe("MainWindow", function()
    local ns

    before_each(function()
        WowMock.Reset()
        ns = OpenAddon("vc")
    end)

    it("opens on the saved entry and draws its tree", function()
        assert.is_true(ns.UI:IsShown())
        local _, n = ShownNodes()
        assert.is_true(n > 0)
    end)

    it("the side panel has the search, the log and the sections with their entry count", function()
        for _, label in ipairs({ "Search quests...", "Quest Log" }) do
            local text = WowMock.FindByText(label)
            assert.is_not_nil(text, label)
            assert.is_not_nil(text:GetParent()._scripts.OnClick, label)
        end
        assert.is_not_nil(WowMock.Find(function(f) return type(f._text) == "string" and f._text:match("Dungeons %(%d+%)") end))
    end)

    it("lists the sections, with battlegrounds, events and miscellaneous after the classic ones", function()
        local seen = {}
        for _, f in ipairs(WowMock.frames) do
            local name = type(f._text) == "string" and f._text:match("^[+-] (%a[%a ]+) %(%d+%)$")
            if name then seen[#seen + 1] = name end
        end
        assert.are.same({ "Dungeons", "Raids", "Battlegrounds", "Zones", "Class Quests", "Professions", "Races",
            "Events", "Miscellaneous" }, seen)
    end)

    describe("filters", function()
        local parent, child

        before_each(function()
            -- a two-step chain of the entry
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

        it("hide completed hides each done quest, even if its chain goes on", function()
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

        it("too high hides the chains you can't start yet", function()
            WowMock.level = 5
            ns.char.filters.hideHigh = true
            ns.UI_Refresh()
            local _, n = ShownNodes()
            assert.are.equal(0, n)
        end)

        it("other faction: hidden by default, visible with the checkbox", function()
            ns.UI_OpenQuest("rfc", 5722) -- Ragefire Chasm, a Horde one
            ns.Detail_Hide(); ns.UI_Refresh()
            local _, hidden = ShownNodes()
            ns.char.filters.otherFaction = true
            ns.UI_Refresh()
            local _, shown = ShownNodes()
            assert.are.equal(0, hidden)
            assert.is_true(shown > 0)
        end)
    end)

    it("selecting a quest highlights its chain and dims the rest", function()
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

    it("the search replaces the tree and picking an entry closes it", function()
        ns.UI_SetSearchMode(true)
        assert.is_false(ns.UI.treeScroll:IsShown())
        assert.is_true(ns.UI.searchPanel:IsShown())
        ns.UI_OpenQuest("vc", ns.entries.vc.quests[1].id)
        assert.is_true(ns.UI.treeScroll:IsShown())
        assert.is_false(ns.UI.searchPanel:IsShown())
    end)

    it("the wheel changes the zoom and it is saved; SetZoom clamps it", function()
        local scroll = ns.UI.treeScroll
        scroll._scripts.OnMouseWheel(scroll, 1)
        assert.is_true(ns.char.zoom > 1)
        ns.UI_SetZoom(10)
        assert.are.equal(1.6, ns.char.zoom)
        ns.UI_SetZoom(0)
        assert.are.equal(0.35, ns.char.zoom)
    end)

    describe("transparency while moving", function()
        local function tick() for _ = 1, 60 do ns.UI._scripts.OnUpdate(ns.UI, 0.1) end end

        it("turns translucent when walking and opaque when stopping", function()
            WowMock.speed = 7
            tick()
            assert.near(0.5, ns.UI:GetAlpha(), 0.02)
            WowMock.speed = 0
            tick()
            assert.near(1, ns.UI:GetAlpha(), 0.02)
        end)

        it("stays opaque with the cursor over it", function()
            WowMock.speed = 7
            ns.UI._mouseOver = true
            tick()
            assert.near(1, ns.UI:GetAlpha(), 0.02)
        end)

        it("with the speed hidden by the game (combat) it doesn't change", function()
            WowMock.speed = 7
            _G.issecretvalue = function() return true end
            tick()
            _G.issecretvalue = nil
            assert.near(1, ns.UI:GetAlpha(), 0.02)
        end)
    end)

    it("the gear sits above the window's border", function()
        local gear = WowMock.Find(function(f) return f._set.SetNormalTexture and tostring(f._set.SetNormalTexture[1]):find("Gear") end)
        assert.is_not_nil(gear)
        gear:Click()
        assert.is_true(_G.CompletaoPreferencesFrame:IsShown())
    end)

    describe("open with the quest log", function()
        before_each(function()
            ns.UI:Hide()
            ns.char.openWithQuestLog = true
            _G.QuestLogFrame = WowMock.NewFrame("Frame", "QuestLogFrame")
            QuestLogFrame:Hide()
        end)

        local function logShown(v)
            QuestLogFrame:SetShown(v)
            ns.UI_QuestLogChanged()
        end

        it("turned off does nothing", function()
            ns.char.openWithQuestLog = nil
            logShown(true)
            assert.is_false(ns.UI:IsShown())
        end)

        it("opening the log opens it and closing the log closes it", function()
            logShown(true)
            assert.is_true(ns.UI:IsShown())
            logShown(false)
            assert.is_false(ns.UI:IsShown())
        end)

        it("if it was already opened by hand, closing the log doesn't close it", function()
            ns.UI:Show()
            logShown(true)
            logShown(false)
            assert.is_true(ns.UI:IsShown())
        end)
    end)
end)
