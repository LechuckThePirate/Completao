dofile("setupTests.lua")

local function has(list, value)
    for _, v in ipairs(list) do if v == value then return true end end
    return false
end

describe("Shots (/completao shots)", function()
    local ns, taken

    before_each(function()
        WowMock.Reset()
        ns = OpenAddon("vc")
        ns.db.shots = nil
        taken = 0
        _G.Screenshot = function() taken = taken + 1 end
        _G.GetScreenWidth = function() return 1000 end
        _G.GetScreenHeight = function() return 500 end
        ns.Print = function() end
        ns.char.sideCollapsed = nil
    end)
    after_each(function()
        _G.Screenshot, _G.GetScreenWidth, _G.GetScreenHeight = nil, nil, nil
    end)

    it("works out which part of the screen a frame covers, as fractions from the top-left, with some room around", function()
        local f = CreateFrame("Frame")
        f.GetLeft = function() return 100 end
        f.GetRight = function() return 300 end
        f.GetBottom = function() return 50 end
        f.GetTop = function() return 250 end
        local rect = ns.Shots_RectOf({ f }, { 0, 0, 0, 0 })
        assert.are.same({ 0.1, 0.5, 0.3, 0.9 }, rect)
        rect = ns.Shots_RectOf({ f }, { 10, 10, 10, 10 })
        assert.near(0.09, rect[1], 1e-9)
        assert.near(0.48, rect[2], 1e-9)
        f:Hide()
        assert.is_nil(ns.Shots_RectOf({ f })) -- not shown: nothing to photograph
    end)

    it("goes through the views, photographs each and notes what part of the screen it covers", function()
        assert.is_true(ns.Shots_Run("vc"))
        assert.is_true(taken >= 8)
        local names = {}
        for _, line in ipairs(ns.db.shots) do
            local name, when, l, t, r, b = line:match("^([%w_]+)|(%d+)|([%d.]+)|([%d.]+)|([%d.]+)|([%d.]+)$")
            assert.is_not_nil(name, line)
            assert.is_true(tonumber(when) > 0)
            assert.is_true(tonumber(l) <= tonumber(r) and tonumber(t) <= tonumber(b), line)
            names[#names + 1] = name
        end
        assert.are.equal(taken, #names)
        for _, wanted in ipairs({ "main_window", "chain_view", "search", "quest_log", "tracked_quests", "preferences_general",
            "preferences_profile", "tree_fullscreen" }) do
            assert.is_true(has(names, wanted), wanted)
        end
    end)

    it("leaves the addon as it found it: the entry, the tree view, no full screen, no preferences window", function()
        ns.char.selected = "vc"
        ns.char.entryView = nil
        ns.Shots_Run("vc")
        assert.are.equal("vc", ns.char.selected)
        assert.is_nil(ns.char.entryView)
        assert.is_false(ns.UI_IsTreeFullscreen())
        assert.is_false(ns.Prefs_IsShown())
        assert.is_nil(ns.shotsChrome)
    end)

    it("skips a view that has nothing to show (no focused quest, no TomTom) and says which", function()
        local said = {}
        ns.Print = function(text) said[#said + 1] = text end
        ns.Shots_Run("vc")
        local all = table.concat(said, "\n")
        assert.matches("skipped:", all)
        assert.matches("tools/shots.mjs", all)
    end)

    it("is started by /completao shots, with an optional entry", function()
        SlashCmdList.COMPLETAO("shots vc")
        assert.is_true(taken > 0)
    end)
end)

