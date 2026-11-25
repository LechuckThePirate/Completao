dofile("setupTests.lua")

describe("PinnedChains", function()
    local ns

    -- high, made-up ids: LoadAddon() here loads the real quest database too (chains now cross entries, so
    -- Pin_Refresh and the chain view search every one of them), and low ids like 1 or 2 collide with real quests
    before_each(function()
        WowMock.Reset()
        ns = LoadAddon()
        ns.RegisterEntry({ id = "z", name = "Zone", category = "zones" })
        -- two small chains in the same entry: 900001->900002 and 900010->900011->900012
        ns.AddQuests("z", {
            { id = 900001, name = "First" }, { id = 900002, name = "Second", requires = { 900001 } },
            { id = 900010, name = "Alpha" }, { id = 900011, name = "Beta", requires = { 900010 } },
            { id = 900012, name = "Gamma", requires = { 900011 } },
        })
        StartAddon(ns, nil, { selected = "z" })
        ns.UI_Toggle()
    end)

    -- opens the chain view on quest `id` and returns the Pin button
    local function enterChain(id)
        ns.UI_OpenQuest("z", id)
        return ns.UI.pinButton
    end

    it("the Pin button only shows in the chain view", function()
        assert.is_false(ns.UI.pinButton:IsShown())
        enterChain(900002)
        assert.is_true(ns.UI.pinButton:IsShown())
        ns.UI.chainBack:Click()
        assert.is_false(ns.UI.pinButton:IsShown())
    end)

    it("pins the whole chain, shown in its own window; the button turns to Unpin", function()
        local pin = enterChain(900002)
        assert.are.equal("Pin", pin:GetText())
        pin:Click()
        assert.is_true(ns.Pin_IsPinned(900002))
        assert.are.equal("Unpin", pin:GetText())
        assert.are.equal(1, ns.char.pinnedChains and #ns.char.pinnedChains)
        assert.are.equal(900002, ns.char.pinnedChains[1].questId)
    end)

    it("clicking it again unpins it", function()
        local pin = enterChain(900002)
        pin:Click()
        pin:Click()
        assert.is_false(ns.Pin_IsPinned(900002))
        assert.are.equal(0, #ns.char.pinnedChains)
    end)

    it("up to 5 at once; a 6th is refused", function()
        local ids = { 900001, 900002, 900010, 900011, 900012 }
        for _, id in ipairs(ids) do
            ns.UI.chainBack:Click()
            enterChain(id):Click()
        end
        assert.are.equal(5, ns.Pin_Count())
        WowMock.chatted = nil
        ns.Print = function() WowMock.chatted = true end
        ns.Pin_Toggle("z", 99) -- a 6th, were it pinnable
        assert.is_true(WowMock.chatted)
        assert.are.equal(5, ns.Pin_Count())
    end)

    it("only one pin is expanded at a time (the accordion)", function()
        enterChain(900002):Click()
        ns.UI.chainBack:Click()
        enterChain(900010):Click()
        assert.are.equal(900010, ns.char.pinExpanded)
        ns.Pin_SetExpanded(900002, true)
        assert.are.equal(900002, ns.char.pinExpanded)
    end)

    it("a click on a quest inside a pinned chain focuses it", function()
        WowMock.onQuest[900011] = true -- Focus_Set only focuses a quest actually in the log
        enterChain(900010):Click()
        local canvas = ns.Pin_TreeView(900010).canvas
        local node = WowMock.Find(function(f) return f.quest and f.quest.id == 900011 and f._parent == canvas end)
        assert.is_not_nil(node)
        node._scripts.OnClick(node, "LeftButton")
        assert.are.equal(900011, ns.Focus_Quest())
        node._scripts.OnClick(node, "LeftButton") -- a second click unfocuses it (Focus_Toggle)
        assert.is_nil(ns.Focus_Quest())
    end)

    -- the pin's ScrollFrame (wheel zoom, drag to pan): the one scrolling the pin's own holder
    local function pinScrollArea(id)
        local holder = ns.Pin_TreeView(id).canvas:GetParent()
        return WowMock.Find(function(f) return f._kind == "ScrollFrame" and f._scrollChild == holder end)
    end

    -- the pin's own resize grip: a Button, child of its frame, with the size-grabber texture (its bar is also a
    -- draggable Button there, so OnDragStart alone would match that instead)
    local function pinGrip(id)
        local pinFrame = ns.Pin_Frame(id)
        return WowMock.Find(function(f)
            return f._kind == "Button" and f._parent == pinFrame and f._set.SetNormalTexture
                and tostring(f._set.SetNormalTexture[1]):find("SizeGrabber") ~= nil
        end)
    end

    -- drags the grip by (dx, dy) screen pixels (WoW's own axes: x right, y up)
    local function dragGrip(grip, dx, dy)
        WowMock.cursor = { 0, 0 }
        grip._scripts.OnDragStart(grip)
        WowMock.cursor = { dx, dy }
        local resizer = ns.Pin_Resizer()
        resizer._scripts.OnUpdate(resizer, 0.05)
        grip._scripts.OnDragStop(grip)
    end

    it("the wheel zooms the pinned tree, centered where it is", function()
        enterChain(900010):Click()
        local zoom = ns.Pin_Geometry(900010)
        local scrollArea = pinScrollArea(900010)
        assert.is_not_nil(scrollArea)
        scrollArea._scripts.OnMouseWheel(scrollArea, 1) -- zoom in
        assert.is_true(ns.Pin_Geometry(900010) > zoom)
        scrollArea._scripts.OnMouseWheel(scrollArea, -1)
        scrollArea._scripts.OnMouseWheel(scrollArea, -1)
        assert.is_true(ns.Pin_Geometry(900010) < zoom)
    end)

    it("dragging the tree pans it (the scroll position changes)", function()
        enterChain(900010):Click()
        local scrollArea = pinScrollArea(900010)
        -- zoom in first, so the canvas is bigger than the view and there is room to pan
        for _ = 1, 3 do scrollArea._scripts.OnMouseWheel(scrollArea, 1) end
        local before = scrollArea:GetHorizontalScroll()
        WowMock.cursor = { 80, 0 }
        scrollArea._scripts.OnDragStart(scrollArea)
        WowMock.cursor = { 0, 0 } -- dragging left pans the (already left-most) view right, into new room
        for _, f in ipairs(WowMock.frames) do
            if f._parent == scrollArea and f._kind == "Frame" and f._scripts.OnUpdate then f._scripts.OnUpdate(f, 0.05) end
        end
        scrollArea._scripts.OnDragStop(scrollArea)
        assert.are_not.equal(before, scrollArea:GetHorizontalScroll())
    end)

    it("the grip resizes the window (wider and taller); the new size is kept and saved", function()
        enterChain(900010):Click()
        local _, w, treeH = ns.Pin_Geometry(900010)
        local grip = pinGrip(900010)
        assert.is_not_nil(grip)
        dragGrip(grip, 60, -60) -- right (wider) and down (WoW's y is up, so negative = down = taller)
        local _, newW, newTreeH = ns.Pin_Geometry(900010)
        assert.are.equal(w + 60, newW)
        assert.are.equal(treeH + 60, newTreeH)
        assert.are.equal(newW, ns.char.pinnedChains[1].w)
        assert.are.equal(newTreeH, ns.char.pinnedChains[1].treeH)
    end)

    it("resizing never moves the window back to wherever it was last saved", function()
        enterChain(900010):Click()
        local frame = ns.Pin_Frame(900010)
        frame:ClearAllPoints()
        frame:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 400, -300) -- as if freshly dragged, not yet saved again
        local grip = pinGrip(900010)
        dragGrip(grip, 40, 0)
        local point, _, relPoint, x, y = frame:GetPoint(1)
        assert.are.same({ "TOPLEFT", "TOPLEFT", 400, -300 }, { point, relPoint, x, y })
    end)

    it("widening one pin widens the whole stack (so the bars line up); its height is its own", function()
        enterChain(900010):Click()
        local _, _, treeH10Before = ns.Pin_Geometry(900010)
        ns.UI.chainBack:Click()
        enterChain(900002):Click() -- the accordion: 900002 is now expanded, 900010 folded
        local grip = pinGrip(900002)
        dragGrip(grip, 60, 0)
        local _, w2 = ns.Pin_Geometry(900002)
        local _, w10, treeH10 = ns.Pin_Geometry(900010)
        assert.are.equal(w2, w10) -- the folded pin widened too
        assert.are.equal(treeH10Before, treeH10) -- but its own tree height is untouched
    end)

    it("survives a /reload: saved pins are restored", function()
        enterChain(900002):Click()
        local saved = ns.char.pinnedChains
        WowMock.Reset()
        ns = LoadAddon()
        ns.RegisterEntry({ id = "z", name = "Zone", category = "zones" })
        ns.AddQuests("z", {
            { id = 900001, name = "First" }, { id = 900002, name = "Second", requires = { 900001 } },
        })
        StartAddon(ns, nil, { selected = "z", pinnedChains = saved })
        assert.is_true(ns.Pin_IsPinned(900002))
    end)
end)
