dofile("setupTests.lua")

describe("QuestTracking", function()
    local ns
    local function questie(opts)
        opts = opts or {}
        local tracker = { updated = 0, untracked = {} }
        local db = { profile = { trackerEnabled = opts.enabled ~= false, autoTrackQuests = opts.auto ~= false },
            char = { AutoUntrackedQuests = {}, TrackedQuests = {} } }
        local quest = {}
        function quest.IsQuestTracked(_, id)
            if db.profile.autoTrackQuests then return not db.char.AutoUntrackedQuests[id] end
            return db.char.TrackedQuests[id] == true
        end
        function tracker:UntrackQuestId(id)
            self.untracked[#self.untracked + 1] = id
            if db.profile.autoTrackQuests then db.char.AutoUntrackedQuests[id] = true else db.char.TrackedQuests[id] = nil end
        end
        function tracker:Update() self.updated = self.updated + 1 end
        _G.Questie = { db = db }
        _G.QuestieLoader = { ImportModule = function(_, name) return name == "QuestieQuest" and quest or tracker end }
        return db, tracker
    end

    before_each(function()
        WowMock.Reset()
        ns = LoadAddon({ files = { "Modules/Quest/QuestTracking.lua" } })
        ns.char = {}
        ns.flavor = "tbc"
        WowMock.onQuest[166], WowMock.onQuest[167] = true, true
    end)
    after_each(function() _G.Questie, _G.QuestieLoader = nil, nil end)

    it("is for Classic Era and TBC only", function()
        for flavor, own in pairs({ vanilla = true, tbc = true, forever = false, mainline = false }) do
            ns.flavor = flavor
            assert.are.equal(own, ns.UsesOwnTracking(), flavor)
        end
        ns.flavor = nil
        assert.is_false(ns.UsesOwnTracking())
    end)

    describe("without Questie", function()
        it("tracks the quests of the log, as they are taken", function()
            assert.is_true(ns.IsOwnTracked(166))
            assert.is_false(ns.IsOwnTracked(999)) -- not in the log
        end)

        it("untracks and tracks them again", function()
            ns.UntrackQuest(166)
            assert.is_false(ns.IsOwnTracked(166))
            assert.is_true(ns.IsOwnTracked(167))
            ns.TrackQuest(166)
            assert.is_true(ns.IsOwnTracked(166))
        end)

        it("forgets an untracked quest once it leaves the log, so taking it again tracks it", function()
            ns.UntrackQuest(166)
            WowMock.onQuest[166] = nil
            ns.ForgetTrackedQuest(166)
            WowMock.onQuest[166] = true
            assert.is_true(ns.IsOwnTracked(166))
        end)

        it("keeps the list in the character's saved variables", function()
            ns.UntrackQuest(166)
            assert.is_true(ns.char.untrackedQuests[166])
        end)
    end)

    describe("with Questie's tracker", function()
        it("follows Questie's list", function()
            local db = questie()
            db.char.AutoUntrackedQuests[166] = true
            assert.is_false(ns.IsOwnTracked(166))
            assert.is_true(ns.IsOwnTracked(167))
            assert.is_false(ns.IsOwnTracked(999)) -- not in the log, whatever Questie says
        end)

        it("follows Questie's list of tracked quests when it doesn't track them all", function()
            local db = questie({ auto = false })
            db.char.TrackedQuests[167] = true
            assert.is_false(ns.IsOwnTracked(166))
            assert.is_true(ns.IsOwnTracked(167))
        end)

        it("untracks in Questie too", function()
            local db, tracker = questie()
            ns.UntrackQuest(166)
            assert.are.same({ 166 }, tracker.untracked)
            assert.is_true(db.char.AutoUntrackedQuests[166])
            assert.is_false(ns.IsOwnTracked(166))
        end)

        it("tracks in Questie too, in the form its option keeps the list", function()
            local db, tracker = questie()
            db.char.AutoUntrackedQuests[166] = true
            ns.TrackQuest(166)
            assert.is_nil(db.char.AutoUntrackedQuests[166])
            assert.is_true(tracker.updated > 0)
            local db2 = questie({ auto = false })
            ns.TrackQuest(167)
            assert.is_true(db2.char.TrackedQuests[167])
        end)

        it("is ignored when its tracker is off: the addon's own list is the one", function()
            local db = questie({ enabled = false })
            db.char.AutoUntrackedQuests[166] = true
            assert.is_true(ns.IsOwnTracked(166))
            ns.UntrackQuest(166)
            assert.is_false(ns.IsOwnTracked(166))
        end)

        it("survives a Questie whose modules fail", function()
            questie()
            _G.QuestieLoader = { ImportModule = function() error("boom") end }
            assert.is_true(ns.IsOwnTracked(166))
        end)
    end)

    describe("on Forever", function()
        before_each(function() ns.flavor = "forever" end)

        it("asks the game to track and untrack", function()
            local calls = {}
            C_QuestLog.AddQuestWatch = function(id) calls[#calls + 1] = "add" .. id end
            C_QuestLog.RemoveQuestWatch = function(id) calls[#calls + 1] = "remove" .. id end
            ns.TrackQuest(166)
            ns.UntrackQuest(166)
            C_QuestLog.AddQuestWatch, C_QuestLog.RemoveQuestWatch = nil, nil
            assert.are.same({ "add166", "remove166" }, calls)
            assert.is_nil(ns.char.untrackedQuests)
        end)
    end)
end)
