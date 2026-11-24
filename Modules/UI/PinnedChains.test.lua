dofile("setupTests.lua")

describe("PinnedChains", function()
    local ns

    before_each(function()
        WowMock.Reset()
        ns = LoadAddon()
        ns.RegisterEntry({ id = "z", name = "Zone", category = "zones" })
        -- two small chains in the same entry: 1->2 and 10->11->12
        ns.AddQuests("z", {
            { id = 1, name = "First" }, { id = 2, name = "Second", requires = { 1 } },
            { id = 10, name = "Alpha" }, { id = 11, name = "Beta", requires = { 10 } },
            { id = 12, name = "Gamma", requires = { 11 } },
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
        enterChain(2)
        assert.is_true(ns.UI.pinButton:IsShown())
        ns.UI.chainBack:Click()
        assert.is_false(ns.UI.pinButton:IsShown())
    end)

    it("pins the whole chain, shown in its own window; the button turns to Unpin", function()
        local pin = enterChain(2)
        assert.are.equal("Pin", pin:GetText())
        pin:Click()
        assert.is_true(ns.Pin_IsPinned(2))
        assert.are.equal("Unpin", pin:GetText())
        assert.are.equal(1, ns.char.pinnedChains and #ns.char.pinnedChains)
        assert.are.equal(2, ns.char.pinnedChains[1].questId)
    end)

    it("clicking it again unpins it", function()
        local pin = enterChain(2)
        pin:Click()
        pin:Click()
        assert.is_false(ns.Pin_IsPinned(2))
        assert.are.equal(0, #ns.char.pinnedChains)
    end)

    it("up to 5 at once; a 6th is refused", function()
        local ids = { 1, 2, 10, 11, 12 }
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
        enterChain(2):Click()
        ns.UI.chainBack:Click()
        enterChain(10):Click()
        assert.are.equal(10, ns.char.pinExpanded)
        ns.Pin_SetExpanded(2, true)
        assert.are.equal(2, ns.char.pinExpanded)
    end)

    it("a click on a quest inside a pinned chain focuses it", function()
        WowMock.onQuest[11] = true -- Focus_Set only focuses a quest actually in the log
        enterChain(10):Click()
        local canvas = ns.Pin_TreeView(10).canvas
        local node = WowMock.Find(function(f) return f.quest and f.quest.id == 11 and f._parent == canvas end)
        assert.is_not_nil(node)
        node._scripts.OnClick(node, "LeftButton")
        assert.are.equal(11, ns.Focus_Quest())
        node._scripts.OnClick(node, "LeftButton") -- a second click unfocuses it (Focus_Toggle)
        assert.is_nil(ns.Focus_Quest())
    end)

    -- the pin's ScrollFrame (wheel zoom, drag to pan): the one scrolling the pin's own holder
    local function pinScrollArea(id)
        local holder = ns.Pin_TreeView(id).canvas:GetParent()
        return WowMock.Find(function(f) return f._kind == "ScrollFrame" and f._scrollChild == holder end)
    end

    -- the pin's own resize grip (not the main window's, which looks the same)
    local function pinGrip(id)
        local pinFrame = ns.Pin_Frame(id)
        return WowMock.Find(function(f)
            return f._kind == "Button" and f._parent == pinFrame and f._scripts.OnMouseDown and f._scripts.OnMouseUp
        end)
    end

    it("the wheel zooms the pinned tree, centered where it is", function()
        enterChain(10):Click()
        local zoom = ns.Pin_Geometry(10)
        local scrollArea = pinScrollArea(10)
        assert.is_not_nil(scrollArea)
        scrollArea._scripts.OnMouseWheel(scrollArea, 1) -- zoom in
        assert.is_true(ns.Pin_Geometry(10) > zoom)
        scrollArea._scripts.OnMouseWheel(scrollArea, -1)
        scrollArea._scripts.OnMouseWheel(scrollArea, -1)
        assert.is_true(ns.Pin_Geometry(10) < zoom)
    end)

    it("dragging the tree pans it (the scroll position changes)", function()
        enterChain(10):Click()
        local scrollArea = pinScrollArea(10)
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

    it("the grip resizes the window; the new size is kept and saved", function()
        enterChain(10):Click()
        local _, w, treeH = ns.Pin_Geometry(10)
        local grip = pinGrip(10)
        assert.is_not_nil(grip)
        grip:GetParent():SetSize(w + 60, treeH + 22 + 4 + 60)
        grip._scripts.OnMouseUp(grip)
        local _, newW, newTreeH = ns.Pin_Geometry(10)
        assert.are.equal(w + 60, newW)
        assert.are.equal(treeH + 60, newTreeH)
        assert.are.equal(newW, ns.char.pinnedChains[1].w)
        assert.are.equal(newTreeH, ns.char.pinnedChains[1].treeH)
    end)

    it("survives a /reload: saved pins are restored", function()
        enterChain(2):Click()
        local saved = ns.char.pinnedChains
        WowMock.Reset()
        ns = LoadAddon()
        ns.RegisterEntry({ id = "z", name = "Zone", category = "zones" })
        ns.AddQuests("z", {
            { id = 1, name = "First" }, { id = 2, name = "Second", requires = { 1 } },
        })
        StartAddon(ns, nil, { selected = "z", pinnedChains = saved })
        assert.is_true(ns.Pin_IsPinned(2))
    end)
end)
