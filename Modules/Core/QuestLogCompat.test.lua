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
        local Q = LoadAddon({ files = { "Modules/Core/QuestLogCompat.lua" } }).QuestLog
        local info = Q.GetInfo(2)
        assert.are.equal(62, info.questID)
        assert.are.equal("Fargodeep Mine", info.title)
        assert.is_false(info.isHeader)
        assert.is_true(Q.GetInfo(1).isHeader)
        assert.is_nil(Q.GetInfo(9))
        assert.are.equal(3, Q.GetNumQuestLogEntries())
        assert.is_true(Q.IsOnQuest(33))
        assert.is_false(Q.IsOnQuest(34))
        assert.are.equal(3, Q.GetLogIndexForQuestID(33))
        assert.are.equal("Wolves", Q.GetTitleForQuestID(33))
        assert.is_nil(Q.GetTitleForQuestID(1))
        assert.is_true(Q.IsComplete(33))
        assert.is_false(Q.IsComplete(62))
        assert.is_true(Q.IsQuestFlaggedCompleted(7))
        assert.is_false(Q.IsQuestFlaggedCompleted(8))
        assert.has_no.errors(function() Q.RequestLoadQuestByID(1) end)
    end)

    it("selects quests through the old selection", function()
        local Q = LoadAddon({ files = { "Modules/Core/QuestLogCompat.lua" } }).QuestLog
        Q.SetSelectedQuest(33)
        assert.are.equal(3, selected)
        assert.are.equal(33, Q.GetSelectedQuest())
        selected = 1 -- a header
        assert.are.equal(0, Q.GetSelectedQuest())
    end)

    it("leaves alone what the client has", function()
        local mine = function() return "client" end
        _G.C_QuestLog = { GetInfo = mine, IsOnQuest = mine }
        local Q = LoadAddon({ files = { "Modules/Core/QuestLogCompat.lua" } }).QuestLog
        assert.are.equal(mine, Q.GetInfo)
        assert.are.equal(mine, Q.IsOnQuest)
        assert.are.equal("function", type(Q.GetLogIndexForQuestID))
    end)

    -- A field or global written by an addon taints the Blizzard code that reads it (on Forever, with its secret
    -- values, the whole UI breaks: "Completao has been blocked from an action").
    it("never writes to the game's C_QuestLog", function()
        local game = {}
        _G.C_QuestLog = game
        local Q = LoadAddon({ files = { "Modules/Core/QuestLogCompat.lua" } }).QuestLog
        assert.are.equal(game, _G.C_QuestLog)
        assert.is_nil(next(game))
        assert.is_not_nil(Q.GetInfo)
        assert.has_error(function() Q.GetInfo = function() end end)
    end)

    it("follows the game's table when it changes after loading", function()
        local Q = LoadAddon({ files = { "Modules/Core/QuestLogCompat.lua" } }).QuestLog
        local mine = function() return "client" end
        _G.C_QuestLog = { GetInfo = mine }
        assert.are.equal(mine, Q.GetInfo)
    end)
end)

describe("C_QuestLog in the addon's code", function()
    it("is never assigned, nor any of its fields", function()
        local offenders = {}
        for _, toc in ipairs({ "Completao.toc", "Completao_Vanilla.toc", "Completao_TBC.toc" }) do
            for _, f in ipairs(TocFiles(toc)) do
                local n = 0
                for l in io.lines(f) do
                    n = n + 1
                    local code = l:gsub("%-%-.*$", "")
                    if not code:match("^%s*local%s+C_QuestLog%s*=") and (code:match("C_QuestLog%s*=[^=]")
                        or code:match("C_QuestLog%.[%w_]+%s*=[^=]") or code:match("C_QuestLog%[[^%]]+%]%s*=[^=]")) then
                        offenders[#offenders + 1] = f .. ":" .. n
                    end
                end
            end
        end
        assert.are.same({}, offenders)
    end)

    it("is read through ns.QuestLog in every file that uses it", function()
        for _, f in ipairs(TocFiles()) do
            local src = assert(io.open(f)):read("*a")
            if f ~= "Modules/Core/QuestLogCompat.lua" and src:find("C_QuestLog", 1, true) then
                assert.is_truthy(src:find("local C_QuestLog = ns.QuestLog or C_QuestLog", 1, true), f)
            end
        end
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
