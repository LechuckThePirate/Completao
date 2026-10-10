dofile("setupTests.lua")

describe("MainWindow", function()
    local ns

    before_each(function()
        WowMock.Reset()
        ns = OpenAddon("vc")
    end)

    it("is a top-level window, so it comes above the other addons' windows when shown or clicked", function()
        assert.is_true(ns.UI._set.SetToplevel[1])
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

    describe("hiding categories with nothing left to do", function()
        local function header(id)
            return WowMock.Find(function(f) return f.cat and f.cat.id == id end)
        end
        local function entryButton(id)
            return WowMock.Find(function(f) return f.entry and f.entry.id == id end)
        end
        -- the section's header if it is listed (a header button is reused for the next section when one goes)
        local function listed(id)
            return WowMock.Find(function(f) return f.cat and f.cat.id == id and f:IsShown() end)
        end
        local function finish(entry)
            for _, q in ipairs(entry.quests) do WowMock.done[q.id] = true end
        end
        local function withWork(category, skip)
            for _, d in ipairs(ns.entryList) do
                if d.category == category and d.id ~= skip and ns.EntryHasWork(d) then return d end
            end
        end
        local function look()
            ns.UI_SetSearchMode(true, "log") -- looking at none of them
            header("dungeons"):Click()        -- and dungeons opened
            ns.UI_Refresh()
        end

        it("off (the default): everything is listed, done or not", function()
            finish(ns.entries.vc)
            look()
            assert.is_true(entryButton("vc"):IsShown())
            assert.is_true(header("dungeons"):IsShown())
        end)

        it("on: an entry with everything done, or nothing available, is left out; the others stay", function()
            local other = withWork("dungeons", "vc")
            assert.is_not_nil(other)
            finish(ns.entries.vc)
            ns.char.hideDone = true
            look()
            assert.is_nil(entryButton("vc") and entryButton("vc"):IsShown() and true or nil)
            assert.is_true(entryButton(other.id):IsShown())
            assert.is_true(header("dungeons"):IsShown())
            ns.char.hideDone = nil
            ns.UI_Refresh()
            assert.is_true(entryButton("vc"):IsShown())
        end)

        it("the count of a category is of the entries that are listed", function()
            look()
            local all = tonumber(header("dungeons").text._text:match("%((%d+)%)"))
            finish(ns.entries.vc)
            ns.char.hideDone = true
            ns.UI_Refresh()
            local expected = 0
            for _, d in ipairs(ns.entryList) do
                if d.category == "dungeons" and ns.EntryHasWork(d) then expected = expected + 1 end
            end
            local shown = tonumber(header("dungeons").text._text:match("%((%d+)%)"))
            assert.are.equal(expected, shown)
            assert.is_true(shown < all)
        end)

        it("a category with no entry left goes away, and comes back when something is available", function()
            for _, d in ipairs(ns.entryList) do
                if d.category == "dungeons" then finish(d) end
            end
            ns.char.hideDone = true
            ns.UI_SetSearchMode(true, "log")
            assert.is_nil(listed("dungeons"))
            assert.is_not_nil(listed("zones"))
            for _, q in ipairs(ns.entries.vc.quests) do WowMock.done[q.id] = nil end
            ns.UI_Refresh()
            assert.is_not_nil(listed("dungeons"))
        end)

        it("the entry you are looking at stays until you leave it", function()
            finish(ns.entries.vc)
            ns.char.hideDone = true
            ns.UI_Refresh()
            assert.is_true(entryButton("vc"):IsShown())
            assert.is_true(header("dungeons"):IsShown())
            look() -- leaving it for the log, with dungeons opened
            local button = entryButton("vc")
            assert.is_false(button ~= nil and button:IsShown() and button.entry.id == "vc")
        end)
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
            assert.are.equal(64 + 26 - 22, lastTopLeftX(ns.UI.treeScroll)) -- the icons fit: no scroll bar, no gap for it
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
            assert.are.equal(210 + 26, lastTopLeftX(ns.UI.treeScroll))
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

        it("the toggle button collapses and expands, and it is remembered", function()
            local toggle = WowMock.Find(function(f) return f.tex and f._scripts.OnClick and f.text and f.text._text == "Collapse menu" end)
            toggle:Click()
            assert.is_true(ns.char.sideCollapsed)
            ns = OpenAddon("vc", { selected = "vc", sideCollapsed = true })
            assert.is_false(header("dungeons").text:IsShown())
            assert.are.equal(64 + 26 - 22, lastTopLeftX(ns.UI.treeScroll))
        end)
    end)

    describe("the room of the side list's scroll bar", function()
        local function treeX()
            local x
            for _, p in ipairs(ns.UI.treeScroll._points) do if p[1] == "TOPLEFT" then x = p[#p - 1] end end
            return x
        end
        local function headerX()
            local x
            for _, p in ipairs(ns.UI.header._points) do if p[1] == "TOPLEFT" then x = p[#p - 1] end end
            return x
        end

        it("is given back to the main area when the list fits, and taken when it doesn't", function()
            ns.UI_SetSideCollapsed(true) -- a short list of icons
            local fits = treeX()
            ns.UI_SetSideCollapsed(false) -- the full list, longer than the window
            assert.are.equal(210 + 26, treeX())
            assert.are.equal(210 + 30, headerX())
            ns.UI:SetHeight(4000) -- a window tall enough for all of it
            ns.UI_Refresh()
            assert.are.equal(210 + 26 - 22, treeX())
            assert.are.equal(210 + 30 - 22, headerX())
            ns.UI:SetHeight(580)
            ns.UI_Refresh()
            assert.are.equal(210 + 26, treeX())
            assert.is_true(fits < treeX())
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

    describe("a quest opened from elsewhere (a search result, another addon)", function()
        -- a quest of the entry with a prerequisite, and every quest connected to it by prerequisites
        local function chainOfQuestWithParent()
            local quest
            for _, q in ipairs(ns.entries.vc.quests) do
                if #ns.ParentsOf(q) > 0 then quest = q break end
            end
            assert.is_not_nil(quest)
            local near, set, changed = {}, { [quest.id] = true }, true
            for _, q in ipairs(ns.entries.vc.quests) do near[q.id] = q end
            while changed do
                changed = false
                for _, q in ipairs(ns.entries.vc.quests) do
                    for _, parent in ipairs(ns.ParentsOf(q)) do
                        if near[parent] and (set[q.id] ~= set[parent]) then
                            set[q.id], set[parent] = true, true
                            changed = true
                        end
                    end
                end
            end
            return quest, set
        end

        it("is shown with its whole chain, lit, even when the filters would hide it", function()
            local quest, chain = chainOfQuestWithParent()
            for _, q in ipairs(ns.entries.vc.quests) do WowMock.done[q.id] = true end
            ns.char.filters.hideDone = true
            ns.UI_Refresh()
            local _, hidden = ShownNodes()
            assert.are.equal(0, hidden)

            ns.UI_OpenQuest("vc", quest.id)
            local nodes = ShownNodes()
            assert.are.equal(quest.id, ns.Detail_Current().id)
            local count = 0
            for id in pairs(chain) do
                if ns.FindQuestDef(id) and ns.FindQuestDef(id).entryId == "vc" and ns.QuestVisible(ns.FindQuestDef(id), ns.entries.vc) then
                    count = count + 1
                    assert.is_not_nil(nodes[id], "quest " .. id .. " of the chain")
                    assert.is_true(nodes[id]:GetAlpha() >= 0.5, "quest " .. id .. " is lit")
                end
            end
            assert.is_true(count > 1)
        end)

        it("a filter changed afterwards applies again", function()
            local quest = chainOfQuestWithParent()
            for _, q in ipairs(ns.entries.vc.quests) do WowMock.done[q.id] = true end
            ns.char.filters.hideDone = true
            ns.UI_OpenQuest("vc", quest.id)
            assert.is_not_nil(ShownNodes()[quest.id])
            local check = WowMock.FindByText("Hide completed"):GetParent()
            check:SetChecked(true)
            check._scripts.OnClick(check) -- touching a filter ends the exception
            assert.is_nil(ShownNodes()[quest.id])
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

    describe("the tree's scroll bar", function()
        local scroll, canvas, holder
        -- where the tree ends on the right: -8 without the bar, -32 with it
        local function right()
            local x
            for _, p in ipairs(scroll._points) do if p[1] == "BOTTOMRIGHT" then x = p[#p - 1] end end
            return x
        end
        local function rangeChanged() for _, h in ipairs(scroll._hooks.OnScrollRangeChanged) do h(scroll) end end

        before_each(function()
            scroll = ns.UI.treeScroll
            holder = WowMock.Find(function(f) return f._parent == scroll and f._kind == "Frame" end)
            canvas = WowMock.Find(function(f) return f._parent == holder and f._kind == "Frame" end)
            scroll:SetHeight(300)
        end)

        it("the scroll child is as big as the scaled canvas, so the client lets the scroll reach the end", function()
            assert.are.equal(holder, scroll._scrollChild)
            canvas:SetSize(1000, 800)
            ns.UI_SetZoom(1.6)
            assert.are.equal(1600, holder:GetWidth())
            assert.are.equal(1280, holder:GetHeight())
            ns.UI_SetZoom(0.5)
            assert.are.equal(500, holder:GetWidth())
            assert.are.equal(400, holder:GetHeight())
        end)

        it("is not there when the tree fits, and the tree takes its room", function()
            canvas:SetHeight(200)
            rangeChanged()
            assert.are.equal(-8, right())
        end)

        it("shows when the tree is taller than the view, and the tree leaves room for it", function()
            canvas:SetHeight(900)
            rangeChanged()
            assert.are.equal(-32, right())
            canvas:SetHeight(200)
            rangeChanged()
            assert.are.equal(-8, right())
        end)

        it("counts the zoom: the client's own range ignores the canvas scale", function()
            canvas:SetHeight(900)
            ns.UI_SetZoom(0.35) -- 900 * 0.35 = 315: still taller than the 300 view
            assert.are.equal(-32, right())
            canvas:SetHeight(500)
            ns.UI_SetZoom(0.35) -- 175: fits
            assert.are.equal(-8, right())
            ns.UI_SetZoom(1.6) -- 800: does not
            assert.are.equal(-32, right())
        end)

        it("the quest details panel under it ends where the tree does", function()
            local detail = WowMock.Find(function(f) return f.layoutButtons end)
            local function detailRight()
                local x
                for _, p in ipairs(detail._points) do if p[1] == "BOTTOMRIGHT" then x = p[#p - 1] end end
                return x
            end
            canvas:SetHeight(200)
            ns.UI_OpenQuest("vc", ns.entries.vc.quests[1].id)
            rangeChanged()
            assert.are.equal(-8, detailRight())
            canvas:SetHeight(900)
            rangeChanged()
            assert.are.equal(-32, detailRight())
        end)
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

        it("on a flight path it stays opaque: the trip is for reading it", function()
            WowMock.speed, WowMock.onTaxi = 25, true
            tick()
            WowMock.onTaxi = false
            assert.near(1, ns.UI:GetAlpha(), 0.02)
            WowMock.speed = 7 -- and back on foot it fades again
            tick()
            assert.near(0.5, ns.UI:GetAlpha(), 0.02)
            WowMock.speed = 0
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

    it("a solid backing sits over the template's see-through background", function()
        local backing = WowMock.Find(function(f)
            return f._kind == "Texture" and f._parent == ns.UI and f._set.SetColorTexture and f._set.SetColorTexture[4] == 1
        end)
        assert.is_not_nil(backing)
    end)

    describe("opacity at rest", function()
        local function settle()
            for _ = 1, 60 do ns.UI._scripts.OnUpdate(ns.UI, 0.1) end
        end
        after_each(function()
            ns.char.windowAlpha, ns.char.fadeAlpha, WowMock.speed = nil, nil, 0
            settle()
        end)

        it("the window rests at its own opacity", function()
            ns.char.windowAlpha = 0.6
            settle()
            assert.near(0.6, ns.UI:GetAlpha(), 0.02)
        end)

        it("moving fades from it, never above it", function()
            ns.char.windowAlpha = 0.4
            WowMock.speed = 7
            settle()
            assert.near(0.4, ns.UI:GetAlpha(), 0.02) -- 50 % while moving would be above the resting 40 %
            ns.char.windowAlpha, ns.char.fadeAlpha = 0.9, 0.3
            settle()
            assert.near(0.3, ns.UI:GetAlpha(), 0.02)
        end)

        it("with the cursor over it, it goes back to its resting opacity", function()
            ns.char.windowAlpha, ns.char.fadeAlpha = 0.8, 0.3
            WowMock.speed = 7
            ns.UI._mouseOver = true
            settle()
            assert.near(0.8, ns.UI:GetAlpha(), 0.02)
            ns.UI._mouseOver = false
        end)
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

        it("click-through while moving doesn't apply on a flight path", function()
            ns.char.clickThroughMoving = true
            WowMock.speed, WowMock.onTaxi = 25, true
            tick()
            assert.is_true(ns.UI:IsMouseEnabled())
            WowMock.onTaxi = false
            tick()
            assert.is_false(ns.UI:IsMouseEnabled())
            WowMock.speed = 0
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

        it("selecting a quest does nothing when the option is off", function()
            ns.UI:Show()
            ns.UI_SetSearchMode(true, "log")
            ns.char.openWithQuestLog = nil
            ns.UI_QuestSelected(ns.entries.vc.quests[1].id)
            assert.are.equal("log", ns.char.view)
        end)
    end)
end)
