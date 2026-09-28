dofile("setupTests.lua")

-- Data integrity (Data/ and Data/Generated/): what the tools generate must have the shape the addon expects.
describe("Data", function()
    local ns

    setup(function()
        WowMock.Reset()
        ns = LoadAddon()
    end)

    -- a location can be just the NPC (inside an instance there is no zone or coordinates)
    local function isLoc(loc)
        return type(loc) == "table" and (loc.area == nil or type(loc.area) == "number")
            and (loc.x == nil or (type(loc.area) == "number" and type(loc.x) == "number" and type(loc.y) == "number"))
    end

    it("every entry has an id, a name and a known section", function()
        local known = {}
        for _, c in ipairs(ns.categories) do known[c.id] = true end
        for _, d in ipairs(ns.entryList) do
            assert.is_truthy(type(d.id) == "string" and d.id ~= "", "id")
            assert.is_truthy(type(d.name) == "string" and d.name ~= "", d.id)
            assert.is_true(known[d.category] == true, d.id .. ": section " .. tostring(d.category))
        end
    end)

    it("every quest has the expected shape", function()
        for _, d in ipairs(ns.entryList) do
            local seen = {}
            for _, q in ipairs(d.quests) do
                local where = d.id .. "/" .. tostring(q.id)
                assert.is_truthy(type(q.id) == "number" and q.id > 0, where)
                assert.is_nil(seen[q.id], where .. ": repeated in the entry")
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

    it("rewards have the expected shape and belong to the addon's quests", function()
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
            assert.is_not_nil(ns.FindQuestDef(id), where .. ": unknown quest")
            itemList(r.items, where); itemList(r.choice, where)
            assert.is_truthy(r.money == nil or (type(r.money) == "number" and r.money > 0), where)
            assert.is_truthy(r.xp == nil or (type(r.xp) == "number" and r.xp > 0), where)
            for _, rep in ipairs(r.rep or {}) do assert.is_truthy(type(rep[1]) == "number" and type(rep[2]) == "number", where) end
        end
        assert.is_true(n > 1000)
    end)

    it("the Classic raids, Deeprun Tram and the battlegrounds have quests and a known section", function()
        for _, id in ipairs({ "zg", "aq20", "mc", "bwl", "aq40", "naxx" }) do
            assert.are.equal("raids", ns.entries[id].category, id)
            assert.is_true(#ns.entries[id].quests > 0, id)
        end
        for _, id in ipairs({ "av", "wsg", "ab" }) do
            assert.are.equal("battlegrounds", ns.entries[id].category, id)
            assert.is_true(#ns.entries[id].quests > 0, id)
        end
        assert.is_true(#ns.entries.dt.quests > 0)
    end)

    it("the events and miscellaneous entries exist and have quests", function()
        for _, id in ipairs({ "lunar", "darkmoon", "seasonal", "aq_war", "invasion" }) do
            assert.are.equal("events", ns.entries[id].category, id)
            assert.is_true(#ns.entries[id].quests > 0, id)
        end
        assert.are.equal("misc", ns.entries.reputation.category)
    end)

    it("raid quests are marked as done inside their raid", function()
        local inside = 0
        for _, q in ipairs(ns.entries.naxx.quests) do if q.dungeon == "naxx" then inside = inside + 1 end end
        assert.is_true(inside > 10)
    end)

    it("points are in Forever's map coordinates in the zones it redrew", function()
        -- Stormwind (1519): Era 74.3/37.2 became 77.1/53.3 in Forever; no point of ours may still be in Era's
        for _, d in ipairs(ns.entryList) do
            for _, q in ipairs(d.quests) do
                if q.start and q.start.area == 1519 and q.start.npc == "Harry Burlguard" then
                    assert.near(77.2, q.start.x, 0.3)
                    assert.near(53.2, q.start.y, 0.3)
                end
            end
        end
    end)

    it("instance entries have their door", function()
        for _, d in ipairs(ns.entryList) do
            if d.entrance then assert.is_true(isLoc(d.entrance), d.id) end
        end
        assert.is_not_nil(ns.entries.vc.entrance)
    end)

    it("hand fixes point at quests that exist", function()
        local code = io.open("Data/Overrides.lua"):read("*a"):gsub("%-%-[^\n]*", "") -- without the commented examples
        for id in code:gmatch("PatchQuest%((%d+)") do
            assert.is_not_nil(ns.FindQuestDef(tonumber(id)), "Overrides: quest " .. id)
        end
    end)
end)
