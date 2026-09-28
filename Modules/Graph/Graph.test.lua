dofile("setupTests.lua")

describe("Graph.BuildLayout", function()
    local ns

    before_each(function()
        WowMock.Reset()
        ns = LoadAddon({ files = { "Modules/Graph/Graph.lua" } })
    end)

    it("puts each quest in the column of its depth in the chain", function()
        local layout = ns.BuildLayout({
            { id = 1 }, { id = 2, requires = { 1 } }, { id = 3, requires = { 2 } }, { id = 4 },
        })
        assert.are.equal(0, layout.nodes[1].col)
        assert.are.equal(1, layout.nodes[2].col)
        assert.are.equal(2, layout.nodes[3].col)
        assert.are.equal(0, layout.nodes[4].col)
        assert.are.equal(3, layout.cols)
        assert.are.equal(2, #layout.edges)
    end)

    it("a quest requiring several goes after the deepest one", function()
        local layout = ns.BuildLayout({ { id = 1 }, { id = 2, requires = { 1 } }, { id = 3, requires = { 1, 2 } } })
        assert.are.equal(2, layout.nodes[3].col)
    end)

    it("counts requiresAny as parents", function()
        assert.are.same({ 1, 2, 3 }, ns.ParentsOf({ requires = { 1 }, requiresAny = { 2, 3 } }))
        local layout = ns.BuildLayout({ { id = 1 }, { id = 2, requiresAny = { 1 } } })
        assert.are.equal(1, layout.nodes[2].col)
    end)

    it("only places the visible ones and draws no lines to hidden ones", function()
        local layout = ns.BuildLayout({ { id = 1 }, { id = 2, requires = { 1 } } }, function(q) return q.id ~= 1 end)
        assert.is_nil(layout.nodes[1])
        assert.are.equal(0, layout.nodes[2].col)
        assert.are.equal(0, #layout.edges)
        assert.are.equal(1, layout.count)
    end)

    it("splits long columns into columns of MAX_PER_COL rows", function()
        local quests = {}
        for i = 1, ns.MAX_PER_COL + 3 do quests[i] = { id = i } end
        local layout = ns.BuildLayout(quests)
        assert.are.equal(2, layout.cols)
        assert.are.equal(ns.MAX_PER_COL, layout.rows)
        assert.are.equal(1, layout.nodes[ns.MAX_PER_COL + 1].col)
    end)

    it("survives cycles in the data", function()
        assert.has_no.errors(function()
            ns.BuildLayout({ { id = 1, requires = { 2 } }, { id = 2, requires = { 1 } } })
        end)
    end)
end)
