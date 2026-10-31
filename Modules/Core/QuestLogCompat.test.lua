dofile("setupTests.lua")

describe("QuestLogCompat", function()
    local saved = {}
    local log = {}
    local selected = 0

    before_each(function()
        WowMock.Reset()
        saved = { C_QuestLog = C_QuestLog }
        -- a client whose C_QuestLog only has what TBC Anniversary was seen to have: no GetInfo, nothing else
        _G.C_QuestLog = {}
        log = {
            { "Elwynn", nil, nil, 1, nil, nil, nil, nil },
            { "Fargodeep Mine", 3, 0, nil, nil, nil, nil, 62 },
            { "Wolves", 5, 0, nil, nil, 1, nil, 33 },
        }
        selected = 0
        for _, name in ipairs({ "GetQuestLogTitle", "GetNumQuestLogEntries", "GetQuestLogSelection", "SelectQuestLogEntry", "IsQuestFlaggedCompleted" }) do
            saved[name] = _G[name]
        end
        _G.GetNumQuestLogEntries = function() return #log end
        _G.GetQuestLogTitle = function(i) if log[i] then return (_G.unpack or _G.table.unpack)(log[i], 1, 8) end end
        _G.GetQuestLogSelection = function() return selected end
        _G.SelectQuestLogEntry = function(i) selected = i end
        _G.IsQuestFlaggedCompleted = function(id) return id == 7 end
    end)

    after_each(function()
        for name, value in pairs(saved) do _G[name] = value end
    end)

    it("fills in what C_QuestLog lacks from the old quest log", function()
        LoadAddon({ files = { "Modules/Core/QuestLogCompat.lua" } })
        local info = C_QuestLog.GetInfo(2)
        assert.are.equal(62, info.questID)
        assert.are.equal("Fargodeep Mine", info.title)
        assert.is_false(info.isHeader)
        assert.is_true(C_QuestLog.GetInfo(1).isHeader)
        assert.is_nil(C_QuestLog.GetInfo(9))
        assert.are.equal(3, C_QuestLog.GetNumQuestLogEntries())
        assert.is_true(C_QuestLog.IsOnQuest(33))
        assert.is_false(C_QuestLog.IsOnQuest(34))
        assert.are.equal(3, C_QuestLog.GetLogIndexForQuestID(33))
        assert.are.equal("Wolves", C_QuestLog.GetTitleForQuestID(33))
        assert.is_nil(C_QuestLog.GetTitleForQuestID(1))
        assert.is_true(C_QuestLog.IsComplete(33))
        assert.is_false(C_QuestLog.IsComplete(62))
        assert.is_true(C_QuestLog.IsQuestFlaggedCompleted(7))
        assert.is_false(C_QuestLog.IsQuestFlaggedCompleted(8))
        assert.has_no.errors(function() C_QuestLog.RequestLoadQuestByID(1) end)
    end)

    it("selects quests through the old selection", function()
        LoadAddon({ files = { "Modules/Core/QuestLogCompat.lua" } })
        C_QuestLog.SetSelectedQuest(33)
        assert.are.equal(3, selected)
        assert.are.equal(33, C_QuestLog.GetSelectedQuest())
        selected = 1 -- a header
        assert.are.equal(0, C_QuestLog.GetSelectedQuest())
    end)

    it("leaves alone what the client has", function()
        local mine = function() return "client" end
        _G.C_QuestLog = { GetInfo = mine, IsOnQuest = mine }
        LoadAddon({ files = { "Modules/Core/QuestLogCompat.lua" } })
        assert.are.equal(mine, C_QuestLog.GetInfo)
        assert.are.equal(mine, C_QuestLog.IsOnQuest)
        assert.are.equal("function", type(C_QuestLog.GetLogIndexForQuestID))
    end)
end)

describe("QuestLogCompat in the toc", function()
    it("is loaded by every client's toc, before the modules that use C_QuestLog", function()
        for _, toc in ipairs({ "Completao.toc", "Completao_Vanilla.toc", "Completao_TBC.toc" }) do
            local at, first
            for i, f in ipairs(TocFiles(toc)) do
                if f == "Modules/Core/QuestLogCompat.lua" then at = i end
                if not first and f:match("^Modules/") and f ~= "Modules/Core/Flavor.lua" and f ~= "Modules/Core/QuestLogCompat.lua" then first = i end
            end
            assert.is_not_nil(at, toc)
            assert.is_true(at < first, toc)
        end
    end)
end)
