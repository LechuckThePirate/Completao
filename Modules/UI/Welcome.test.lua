dofile("setupTests.lua")

describe("Welcome", function()
    local ns, welcome

    before_each(function()
        WowMock.Reset()
        ns = OpenAddon("vc")
        welcome = _G.CompletaoWelcomeFrame
    end)

    it("shows once by itself, the first time (or after a version bump)", function()
        assert.is_not_nil(welcome)
        assert.is_true(welcome:IsShown())
    end)

    it("the changelog's scroll bar takes room only when the text doesn't fit", function()
        local scroll = welcome.changelogScroll
        local function right()
            local x
            for _, p in ipairs(scroll._points) do if p[1] == "BOTTOMRIGHT" then x = p[#p - 1] end end
            return x
        end
        local function rangeChanged() for _, h in ipairs(scroll._hooks.OnScrollRangeChanged) do h(scroll) end end
        scroll:SetVerticalScrollRange(0)
        rangeChanged()
        assert.are.equal(-24, right())
        scroll:SetVerticalScrollRange(100)
        rangeChanged()
        assert.are.equal(-48, right())
        scroll:SetVerticalScrollRange(0)
        rangeChanged()
        assert.are.equal(-24, right())
    end)

    it("the issue tracker URL is there to copy", function()
        assert.are.equal("https://github.com/LechuckThePirate/Completao/issues", welcome.urlBox:GetText())
    end)

    it("asks to report bugs on GitHub, above the changelog", function()
        assert.matches("GitHub", welcome.body:GetText())
        -- the changelog label hangs off the URL box, which hangs off the bug-report note: in that order
        local _, relTo = welcome.changelogLabel:GetPoint()
        assert.are.equal(welcome.urlBox, relTo)
        local _, relTo2 = welcome.urlBox:GetPoint()
        assert.are.equal(welcome.body, relTo2)
    end)

    it("Don't show this again remembers the version, and clearing it forgets", function()
        local check = WowMock.Find(function(f) return f._kind == "CheckButton" and f._parent == welcome end)
        check:SetChecked(true); check:Click()
        assert.are.equal("0.0.0-test", CompletaoDB.welcomeDismissedVersion)
        check:SetChecked(false); check:Click()
        assert.are.equal("", CompletaoDB.welcomeDismissedVersion)
    end)

    it("does not show again once dismissed for this version, but does after a version bump", function()
        welcome:Hide()
        CompletaoDB.welcomeDismissedVersion = "0.0.0-test"
        local savedDB = CompletaoDB

        local ns2 = LoadAddon()
        StartAddon(ns2, savedDB, { selected = "vc" })
        assert.is_false(_G.CompletaoWelcomeFrame:IsShown())

        savedDB.welcomeDismissedVersion = "0.0.0-old"
        local ns3 = LoadAddon()
        StartAddon(ns3, savedDB, { selected = "vc" })
        assert.is_true(_G.CompletaoWelcomeFrame:IsShown())
    end)

    it("/completao changelog and the Preferences button reopen it even if dismissed", function()
        welcome:Hide()
        CompletaoDB.welcomeDismissedVersion = "0.0.0-test"
        SlashCmdList.COMPLETAO("changelog")
        assert.is_true(welcome:IsShown())

        welcome:Hide()
        ns.Prefs_Toggle()
        WowMock.FindButton("What's new"):Click()
        assert.is_true(welcome:IsShown())
    end)
end)
