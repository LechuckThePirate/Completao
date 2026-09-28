dofile("setupTests.lua")

describe("Graph.BuildLayout", function()
    local ns

    before_each(function()
        WowMock.Reset()
        ns = LoadAddon({ files = { "Modules/Graph/Graph.lua" } })
    end)

    it("coloca cada quest en la columna de su profundidad en la cadena", function()
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

    it("una quest que requiere varias va despues de la mas profunda", function()
        local layout = ns.BuildLayout({ { id = 1 }, { id = 2, requires = { 1 } }, { id = 3, requires = { 1, 2 } } })
        assert.are.equal(2, layout.nodes[3].col)
    end)

    it("cuenta requiresAny como padres", function()
        assert.are.same({ 1, 2, 3 }, ns.ParentsOf({ requires = { 1 }, requiresAny = { 2, 3 } }))
        local layout = ns.BuildLayout({ { id = 1 }, { id = 2, requiresAny = { 1 } } })
        assert.are.equal(1, layout.nodes[2].col)
    end)

    it("solo coloca las visibles y no dibuja lineas hacia las ocultas", function()
        local layout = ns.BuildLayout({ { id = 1 }, { id = 2, requires = { 1 } } }, function(q) return q.id ~= 1 end)
        assert.is_nil(layout.nodes[1])
        assert.are.equal(0, layout.nodes[2].col)
        assert.are.equal(0, #layout.edges)
        assert.are.equal(1, layout.count)
    end)

    it("reparte columnas largas en columnas de MAX_PER_COL filas", function()
        local quests = {}
        for i = 1, ns.MAX_PER_COL + 3 do quests[i] = { id = i } end
        local layout = ns.BuildLayout(quests)
        assert.are.equal(2, layout.cols)
        assert.are.equal(ns.MAX_PER_COL, layout.rows)
        assert.are.equal(1, layout.nodes[ns.MAX_PER_COL + 1].col)
    end)

    it("aguanta ciclos en los datos", function()
        assert.has_no.errors(function()
            ns.BuildLayout({ { id = 1, requires = { 2 } }, { id = 2, requires = { 1 } } })
        end)
    end)
end)
