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
        for _, label in ipairs({ "Search quests...", "Quest Log", "Tracked Quests" }) do
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

    it("going to the search or the quest log collapses every section", function()
        local function openSections()
            local n = 0
            for _, f in ipairs(WowMock.frames) do
                if f:IsShown() and type(f._text) == "string" and f._text:match("^%- %a[%a ]+ %(%d+%)$") then n = n + 1 end
            end
            return n
        end
        assert.are.equal(1, openSections())
        ns.UI_SetSearchMode(true, "log")
        assert.are.equal(0, openSections())
        assert.is_false(ns.char.category)
    end)

    describe("the collapsed side panel", function()
        local function header(id)
            return WowMock.Find(function(f) return f.cat and f.cat.id == id end)
        end
        local function lastTopLeftX(f)
            local x
            for _, p in ipairs(f._points) do if p[1] == "TOPLEFT" then x = p[#p - 1] end end
            return x
        end

        it("shows the icons of the sections, without their names, and the tree moves to the left", function()
            local wide = lastTopLeftX(ns.UI.treeScroll)
            ns.UI_SetSideCollapsed(true)
            assert.is_true(ns.char.sideCollapsed)
            for _, cat in ipairs(ns.categories) do
                local h = header(cat.id)
                assert.is_true(h:IsShown())
                assert.is_false(h.text:IsShown())
                assert.are.equal(cat.icon, h.icon._set.SetTexture[1])
                assert.is_not_nil(h.label:find(cat.name, 1, true))
            end
            assert.is_true(lastTopLeftX(ns.UI.treeScroll) < wide)
            assert.are.equal(64 - 22 + 26, lastTopLeftX(ns.UI.treeScroll)) -- no scroll bar
        end)

        it("no entry is listed, and expanding brings back the names and the width", function()
            ns.UI_SetSideCollapsed(true)
            assert.is_nil(WowMock.FindByText("Dungeons (%d+)"))
            for _, f in ipairs(WowMock.frames) do
                if f.entry then assert.is_false(f:IsShown()) end
            end
            ns.UI_SetSideCollapsed(false)
            assert.is_false(ns.char.sideCollapsed)
            assert.is_true(header("dungeons").text:IsShown())
            assert.is_nil(header("dungeons").label)
            assert.are.equal(210 - 22 + 26, lastTopLeftX(ns.UI.treeScroll))
        end)

        it("a section's icon opens a menu with its entries; picking one goes to it", function()
            ns.UI_SetSideCollapsed(true)
            header("raids"):Click()
            local options = WowMock.FindAll(function(f) return f.text and f._scripts.OnClick and f._shown and f._parent and f._parent.buttons end)
            assert.is_true(#options > 0)
            options[1]:Click()
            assert.are.equal("raids", ns.entries[ns.char.selected].category)
            assert.are.equal("raids", ns.char.category)
        end)

        it("the side panel's scroll bar only shows when its content doesn't fit, and then the main area moves over", function()
            local scroll = ns.UI.listScroll
            assert.are.equal(210 - 22 + 26, lastTopLeftX(ns.UI.treeScroll))
            scroll:SetVerticalScrollRange(300)
            for _, h in ipairs(scroll._hooks.OnScrollRangeChanged) do h(scroll) end
            assert.are.equal(210 + 26, lastTopLeftX(ns.UI.treeScroll))
            scroll:SetVerticalScrollRange(0)
            for _, h in ipairs(scroll._hooks.OnScrollRangeChanged) do h(scroll) end
            assert.are.equal(210 - 22 + 26, lastTopLeftX(ns.UI.treeScroll))
        end)

        it("the toggle button collapses and expands, and it is remembered", function()
            local toggle = WowMock.Find(function(f) return f.tex and f._scripts.OnClick and f.text and f.text._text == "Collapse menu" end)
            toggle:Click()
            assert.is_true(ns.char.sideCollapsed)
            ns = OpenAddon("vc", { selected = "vc", sideCollapsed = true })
            assert.is_false(header("dungeons").text:IsShown())
            assert.are.equal(64 - 22 + 26, lastTopLeftX(ns.UI.treeScroll)) -- no scroll bar
        end)
    end)

    describe("the view it opens on", function()
        local function reopen(charDB)
            WowMock.Reset()
            return OpenAddon("vc", charDB)
        end

        it("remembers the view it was left on and saves it as you move around", function()
            ns.UI_SetSearchMode(true, "log")
            assert.are.equal("log", ns.char.view)
            ns.UI_SetSearchMode(true, "search")
            assert.are.equal("search", ns.char.view)
            ns.UI_OpenQuest("vc", ns.entries.vc.quests[1].id)
            assert.are.equal("tree", ns.char.view)
        end)

        it("comes back to the quest log in the next session if it was left there", function()
            ns = reopen({ selected = "vc", view = "log" })
            assert.is_true(ns.UI.searchPanel:IsShown())
            assert.are.equal("log", ns.Search_Mode())
        end)

        it("comes back to the search too, and to the tree of the entry otherwise", function()
            ns = reopen({ selected = "vc", view = "search" })
            assert.are.equal("search", ns.Search_Mode())
            assert.is_true(ns.UI.searchPanel:IsShown())
            ns = reopen({ selected = "vc", view = "tree" })
            assert.is_false(ns.UI.searchPanel:IsShown())
            assert.is_true(ns.UI.treeScroll:IsShown())
        end)

        it("restores it once: later the window is as it was when hidden", function()
            ns = reopen({ selected = "vc", view = "log" })
            ns.UI_OpenQuest("vc", ns.entries.vc.quests[1].id)
            ns.UI:Hide(); ns.UI:Show()
            assert.is_false(ns.UI.searchPanel:IsShown())
        end)

        it("always on the quest log, when asked to, every time it opens", function()
            ns = reopen({ selected = "vc", openOnQuestLog = true })
            assert.are.equal("log", ns.Search_Mode())
            assert.is_true(ns.UI.searchPanel:IsShown())
            ns.UI_OpenQuest("vc", ns.entries.vc.quests[1].id)
            assert.is_false(ns.UI.searchPanel:IsShown())
            ns.UI:Hide(); ns.UI:Show()
            assert.is_true(ns.UI.searchPanel:IsShown())
            assert.are.equal("log", ns.Search_Mode())
            assert.is_nil(ns.Detail_Current())
        end)
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

    it("a quest in the log with every objective done gets a check in the top-right corner", function()
        local id
        for _, q in ipairs(ns.entries.vc.quests) do
            if ns.QuestVisible(q, ns.entries.vc) then id = q.id break end
        end
        local function check() return (ShownNodes())[id].ready:IsShown() end
        ns.UI_Refresh()
        assert.is_false(check())                 -- not taken
        WowMock.onQuest[id] = true
        ns.UI_Refresh()
        assert.is_false(check())                 -- in the log, objectives pending
        WowMock.readyForTurnIn[id] = true
        ns.UI_Refresh()
        assert.is_true(check())                  -- ready to turn in
        WowMock.done[id], WowMock.onQuest[id] = true, nil
        ns.UI_Refresh()
        assert.is_false(check())                 -- turned in
    end)

    it("a dragon badge marks elite quests, in place of the dungeon door", function()
        local id
        for _, q in ipairs(ns.entries.vc.quests) do
            if q.dungeon == "vc" then id = q.id break end
        end
        local function badge() return (ShownNodes())[id].badge end
        ns.UI_Refresh()
        assert.is_true(badge():IsShown())
        assert.matches("Dungeon%.png$", badge():GetTexture())
        WowMock.tagInfo[id] = { 1, "Elite" }
        ns.UI_Refresh()
        assert.is_true(badge():IsShown())
        assert.are.equal("Interface\\Icons\\INV_Misc_Head_Dragon_01", badge():GetTexture())
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

    describe("opacity in combat", function()
        local function settle()
            for _ = 1, 60 do ns.UI._scripts.OnUpdate(ns.UI, 0.1) end
        end
        after_each(function() WowMock.inCombat, WowMock.speed = false, 0 end)

        it("fades to its own setting in combat, and is opaque by default", function()
            WowMock.inCombat = true
            settle()
            assert.near(1, ns.UI:GetAlpha(), 0.02)
            ns.char.fadeAlphaCombat = 0.4
            settle()
            assert.near(0.4, ns.UI:GetAlpha(), 0.02)
            WowMock.inCombat = false
            settle()
            assert.near(1, ns.UI:GetAlpha(), 0.02)
            ns.char.fadeAlphaCombat = nil
        end)

        it("with the mouse over it stays opaque, and moving in combat takes the lower of the two", function()
            ns.char.fadeAlphaCombat, ns.char.fadeAlpha = 0.4, 0.7
            WowMock.inCombat, WowMock.speed = true, 7
            settle()
            assert.near(0.4, ns.UI:GetAlpha(), 0.02)
            ns.UI._mouseOver = true
            settle()
            assert.near(1, ns.UI:GetAlpha(), 0.02)
            ns.UI._mouseOver = false
            ns.char.fadeAlphaCombat, ns.char.fadeAlpha = nil, nil
        end)
    end)

    describe("click-through", function()
        local function tick() ns.UI._scripts.OnUpdate(ns.UI, 0.1) end
        local function anyChild()
            return WowMock.Find(function(f) return f._kind == "Button" and f._parent == ns.UI and f._scripts.OnClick end)
        end
        before_each(function()
            ns.UI:EnableMouse(true)
            ns.char.clickThroughCombat, ns.char.clickThroughMoving = nil, nil
            WowMock.inCombat, WowMock.speed = false, 0
        end)
        after_each(function() WowMock.inCombat, WowMock.speed = false, 0 end)

        it("does nothing unless the preference is on", function()
            WowMock.inCombat = true
            tick()
            assert.is_true(ns.UI:IsMouseEnabled())
        end)

        it("in combat, when asked to: the window and what is in it stop taking the mouse, and get it back after", function()
            ns.char.clickThroughCombat = true
            local child = anyChild()
            child:EnableMouse(true)
            WowMock.inCombat = true
            tick()
            assert.is_false(ns.UI:IsMouseEnabled())
            assert.is_false(child:IsMouseEnabled())
            WowMock.inCombat = false
            tick()
            assert.is_true(ns.UI:IsMouseEnabled())
            assert.is_true(child:IsMouseEnabled())
        end)

        it("while moving is a separate setting", function()
            ns.char.clickThroughCombat = true
            WowMock.speed = 7
            tick()
            assert.is_true(ns.UI:IsMouseEnabled())
            ns.char.clickThroughMoving = true
            tick()
            assert.is_false(ns.UI:IsMouseEnabled())
            WowMock.speed = 0
            tick()
            assert.is_true(ns.UI:IsMouseEnabled())
        end)

        it("while click-through the mouse over it doesn't make it opaque", function()
            ns.char.clickThroughCombat, ns.char.fadeAlphaCombat = true, 0.4
            WowMock.inCombat = true
            ns.UI._mouseOver = true
            for _ = 1, 60 do tick() end
            assert.near(0.4, ns.UI:GetAlpha(), 0.02)
            ns.UI._mouseOver = false
            ns.char.fadeAlphaCombat = nil
        end)

        it("closing the window gives the mouse back", function()
            ns.char.clickThroughCombat = true
            WowMock.inCombat = true
            tick()
            ns.UI:Hide()
            assert.is_true(ns.UI:IsMouseEnabled())
        end)
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

        it("selecting a known quest in the log opens it in its tree", function()
            ns.UI:Show()
            ns.UI_SetSearchMode(true, "log")
            ns.UI_QuestSelected(ns.entries.vc.quests[1].id)
            assert.are.equal("tree", ns.char.view)
        end)

        it("ignores the game's log echoing our own selection changes, for a while", function()
            ns.UI:Show()
            ns.UI_SetSearchMode(true, "log")
            WowMock.time = 100
            ns.MuteQuestSelect() -- e.g. reading a quest's text from the log
            ns.UI_QuestSelected(ns.entries.vc.quests[1].id)
            assert.are.equal("log", ns.char.view)
            WowMock.time = 102
            ns.UI_QuestSelected(ns.entries.vc.quests[1].id)
            assert.are.equal("tree", ns.char.view)
        end)

        it("a quest's details below a table don't bring the tree back behind it", function()
            ns.UI:Show()
            ns.UI_SetSearchMode(true, "tracked")
            ns.Detail_Show(ns.entries.vc.quests[1])
            assert.is_false(ns.UI.treeScroll:IsShown())
            ns.Detail_Hide()
            assert.is_false(ns.UI.treeScroll:IsShown())
        end)

        it("selecting a quest does nothing when the option is off", function()
            ns.UI:Show()
            ns.UI_SetSearchMode(true, "log")
            ns.char.openWithQuestLog = nil
            ns.UI_QuestSelected(ns.entries.vc.quests[1].id)
            assert.are.equal("log", ns.char.view)
        end)
    end)
end)
