dofile("setupTests.lua")

describe("Layout.FlowLayout", function()
    local ns

    local function frame(h, shown)
        local f = WowMock.NewFrame("Frame")
        f:SetHeight(h)
        if shown == false then f:Hide() end
        return f
    end
    local function point(f) return f:GetPoint(1) end

    before_each(function()
        WowMock.Reset()
        ns = LoadAddon({ files = { "Modules/UI/Layout.lua" } })
    end)

    it("pone en una fila lo que cabe", function()
        local a, b, c = frame(24), frame(24), frame(24)
        local h = ns.FlowLayout(UIParent, { { frame = a, w = 200 }, { frame = b, w = 100 }, { frame = c, w = 100 } }, 10, 50, 600, 10, 2)
        assert.are.equal(24, h)
        local _, _, _, x, y = point(c)
        assert.are.equal(10 + 200 + 10 + 100 + 10, x)
        assert.are.equal(-50, y)
    end)

    it("pasa a la fila siguiente lo que no cabe", function()
        local a, b, c = frame(24), frame(24), frame(24)
        local h = ns.FlowLayout(UIParent, { { frame = a, w = 200 }, { frame = b, w = 100 }, { frame = c, w = 100 } }, 10, 50, 330, 10, 2)
        assert.are.equal(50, h)
        local _, _, _, x, y = point(c)
        assert.are.equal(10, x)
        assert.are.equal(-(50 + 26), y)
    end)

    it("desde abajo: la primera fila arriba; los ocultos no cuentan", function()
        local s1, s2, s3 = frame(22), frame(22), frame(22, false)
        local items = { { frame = s1, w = 170 }, { frame = s2, w = 170 }, { frame = s3, w = 130 } }
        assert.are.equal(22, ns.FlowLayout(UIParent, items, 8, 8, 360, 6, 4, true, true))
        s3:Show()
        assert.are.equal(48, ns.FlowLayout(UIParent, items, 8, 8, 360, 6, 4, true, true))
        local p1, _, _, _, y1 = point(s1)
        assert.are.equal("BOTTOMLEFT", p1)
        assert.are.equal(8 + 26, y1)
        assert.are.equal(8, select(5, point(s3)))
    end)

    it("el ancho puede ser una funcion (casillas con texto)", function()
        local cb, label = frame(24), WowMock.NewFrame("FontString")
        label:SetText("Hide low level")
        local w = ns.CheckWidth(cb, label)
        assert.are.equal(24 + #"Hide low level" * 6 + 4, w())
    end)
end)
