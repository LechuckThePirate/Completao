dofile("setupTests.lua")

-- Integridad de los datos (Data/ y Data/Generated/): lo generado por las herramientas tiene que tener la
-- forma que espera el addon.
describe("Data", function()
    local ns

    setup(function()
        WowMock.Reset()
        ns = LoadAddon()
    end)

    -- una ubicacion puede ser solo el NPC (dentro de una instancia no hay zona ni coordenadas)
    local function isLoc(loc)
        return type(loc) == "table" and (loc.area == nil or type(loc.area) == "number")
            and (loc.x == nil or (type(loc.area) == "number" and type(loc.x) == "number" and type(loc.y) == "number"))
    end

    it("cada entrada tiene id, nombre y una seccion conocida", function()
        local known = {}
        for _, c in ipairs(ns.categories) do known[c.id] = true end
        for _, d in ipairs(ns.entryList) do
            assert.is_truthy(type(d.id) == "string" and d.id ~= "", "id")
            assert.is_truthy(type(d.name) == "string" and d.name ~= "", d.id)
            assert.is_true(known[d.category] == true, d.id .. ": seccion " .. tostring(d.category))
        end
    end)

    it("cada quest tiene la forma esperada", function()
        for _, d in ipairs(ns.entryList) do
            local seen = {}
            for _, q in ipairs(d.quests) do
                local where = d.id .. "/" .. tostring(q.id)
                assert.is_truthy(type(q.id) == "number" and q.id > 0, where)
                assert.is_nil(seen[q.id], where .. ": repetida en la entrada")
                seen[q.id] = true
                assert.is_truthy(type(q.name) == "string" and q.name ~= "", where)
                for _, k in ipairs({ "level", "minLevel", "races", "classes" }) do
                    assert.is_truthy(q[k] == nil or type(q[k]) == "number", where .. ": " .. k)
                end
                for _, k in ipairs({ "requires", "requiresAny" }) do
                    for _, id in ipairs(q[k] or {}) do assert.are.equal("number", type(id), where .. ": " .. k) end
                end
                assert.is_truthy(q.faction == nil or q.faction == "Alliance" or q.faction == "Horde", where)
                if q.start then assert.is_true(isLoc(q.start), where .. ": start") end
                if q.finish then assert.is_true(isLoc(q.finish), where .. ": finish") end
                for _, s in ipairs(q.steps or {}) do
                    assert.is_true(isLoc(s) and type(s.name) == "string", where .. ": steps")
                end
                if q.dungeon then assert.is_not_nil(ns.entries[q.dungeon], where .. ": dungeon " .. q.dungeon) end
            end
        end
    end)

    it("las recompensas tienen la forma esperada y son de quests del addon", function()
        local function itemList(list, where)
            for _, e in ipairs(list or {}) do
                if type(e) == "table" then
                    assert.is_truthy(type(e[1]) == "number" and type(e[2]) == "number" and e[2] > 1, where)
                else
                    assert.are.equal("number", type(e), where)
                end
            end
        end
        local n = 0
        for id, r in pairs(ns.REWARDS) do
            n = n + 1
            local where = "rewards/" .. id
            assert.is_not_nil(ns.FindQuestDef(id), where .. ": quest desconocida")
            itemList(r.items, where); itemList(r.choice, where)
            assert.is_truthy(r.money == nil or (type(r.money) == "number" and r.money > 0), where)
            assert.is_truthy(r.xp == nil or (type(r.xp) == "number" and r.xp > 0), where)
            for _, rep in ipairs(r.rep or {}) do assert.is_truthy(type(rep[1]) == "number" and type(rep[2]) == "number", where) end
        end
        assert.is_true(n > 1000)
    end)

    it("las entradas de instancia tienen su puerta", function()
        for _, d in ipairs(ns.entryList) do
            if d.entrance then assert.is_true(isLoc(d.entrance), d.id) end
        end
        assert.is_not_nil(ns.entries.vc.entrance)
    end)

    it("las correcciones a mano apuntan a quests que existen", function()
        local code = io.open("Data/Overrides.lua"):read("*a"):gsub("%-%-[^\n]*", "") -- sin los ejemplos comentados
        for id in code:gmatch("PatchQuest%((%d+)") do
            assert.is_not_nil(ns.FindQuestDef(tonumber(id)), "Overrides: quest " .. id)
        end
    end)
end)
