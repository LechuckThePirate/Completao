local ADDON, ns = ...
local L = ns.L

-- Welcome / "what's new" window, as in Embolsao: shown once per version (PLAYER_ENTERING_WORLD, see
-- Completao.lua), with the addon's icon, a beta warning pointing at the GitHub issue tracker, and the
-- latest changelog entry. Reopens from the Preferences window or `/completao changelog`.
local WIDTH, HEIGHT = 380, 480

local ICON = "Interface\\AddOns\\" .. ADDON .. "\\Icons\\Completao.png"
local ISSUES_URL = "https://github.com/LechuckThePirate/Completao/issues"

-- Mirrors the latest entry in CHANGELOG.md -- update this alongside it (and the version bump) on every
-- release; shown as-is, scrollable, in the window below.
local LATEST_CHANGELOG_TEXT = table.concat({
    "- New: Tracked Quests view, with your tracked quests and their objectives; click an objective to set",
    "  the waypoint on it.",
    "- New: clicking a quest in a table opens its details below it, with a View chain button.",
    "- New: a live Distance column to each quest's next step (sortable).",
    "- New: [level] prefix on titles (D dungeon, + elite) and ready / in progress icons.",
    "- New: Sync with Blizzard Quest Log -- selecting a quest in it opens it here.",
    "- New: click-through in combat / while moving, and a separate opacity in combat.",
    "- New: the table's sort order is remembered.",
}, "\n")

local welcomeFrame

local function create()
    welcomeFrame = CreateFrame("Frame", "CompletaoWelcomeFrame", UIParent, "BackdropTemplate")
    welcomeFrame:SetSize(WIDTH, HEIGHT)
    welcomeFrame:SetPoint("CENTER")
    welcomeFrame:SetFrameStrata("DIALOG")
    welcomeFrame:SetClampedToScreen(true)
    welcomeFrame:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })
    welcomeFrame:SetBackdropColor(0, 0, 0, 0.9)
    welcomeFrame:SetMovable(true)
    welcomeFrame:EnableMouse(true)
    welcomeFrame:RegisterForDrag("LeftButton")
    welcomeFrame:SetScript("OnDragStart", welcomeFrame.StartMoving)
    welcomeFrame:SetScript("OnDragStop", welcomeFrame.StopMovingOrSizing)
    tinsert(UISpecialFrames, "CompletaoWelcomeFrame")

    local okClose, close = pcall(CreateFrame, "Button", nil, welcomeFrame, "UIPanelCloseButtonDefaultAnchors")
    if not okClose or not close then
        close = CreateFrame("Button", nil, welcomeFrame, "UIPanelCloseButton")
    end
    close:SetPoint("TOPRIGHT", -2, -2)

    welcomeFrame.icon = welcomeFrame:CreateTexture(nil, "ARTWORK")
    welcomeFrame.icon:SetSize(48, 48)
    welcomeFrame.icon:SetPoint("TOP", 0, -16)
    welcomeFrame.icon:SetTexture(ICON)

    welcomeFrame.title = welcomeFrame:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    welcomeFrame.title:SetPoint("TOP", 0, -70)
    welcomeFrame.title:SetText(L["Welcome to Completao!!"])

    -- The beta warning: always shown (the addon is beta for as long as it says so in its version), with
    -- the GitHub issue tracker just below it.
    welcomeFrame.body = welcomeFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    welcomeFrame.body:SetPoint("TOP", 0, -96)
    welcomeFrame.body:SetWidth(340)
    welcomeFrame.body:SetJustifyH("CENTER")
    welcomeFrame.body:SetText(L["This is a beta version: you may run into bugs. Please report them on GitHub (click to select, then Ctrl+C):"])

    -- Read-only, auto-selects its full text on click/focus so the player can Ctrl+C it -- WoW addons have
    -- no API to write to the system clipboard directly. No template/backdrop on purpose: styled to read as
    -- a plain link (blue, no border/box) rather than an obvious input field.
    welcomeFrame.urlBox = CreateFrame("EditBox", nil, welcomeFrame)
    welcomeFrame.urlBox:SetSize(340, 20)
    welcomeFrame.urlBox:SetPoint("TOP", welcomeFrame.body, "BOTTOM", 0, -10)
    welcomeFrame.urlBox:SetAutoFocus(false)
    welcomeFrame.urlBox:SetJustifyH("CENTER")
    welcomeFrame.urlBox:SetFontObject(GameFontHighlightSmall)
    welcomeFrame.urlBox:SetTextColor(0.4, 0.7, 1, 1)
    welcomeFrame.urlBox:SetText(ISSUES_URL)
    welcomeFrame.urlBox:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    welcomeFrame.urlBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    welcomeFrame.urlBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    welcomeFrame.urlBox:SetScript("OnMouseUp", function(self) self:HighlightText() end)
    welcomeFrame.urlBox:SetScript("OnEnter", function(self) self:SetTextColor(0.6, 0.85, 1, 1) end)
    welcomeFrame.urlBox:SetScript("OnLeave", function(self) self:SetTextColor(0.4, 0.7, 1, 1) end)

    welcomeFrame.changelogLabel = welcomeFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
    welcomeFrame.changelogLabel:SetPoint("TOPLEFT", welcomeFrame.urlBox, "BOTTOMLEFT", -6, -18)

    welcomeFrame.changelogScroll = CreateFrame("ScrollFrame", nil, welcomeFrame, "UIPanelScrollFrameTemplate")
    welcomeFrame.changelogScroll:SetPoint("TOPLEFT", welcomeFrame.changelogLabel, "BOTTOMLEFT", 0, -8)
    welcomeFrame.changelogScroll:SetPoint("BOTTOMRIGHT", -24, 56) -- -48 while its scroll bar shows

    welcomeFrame.changelogContent = CreateFrame("Frame", nil, welcomeFrame.changelogScroll)
    welcomeFrame.changelogContent:SetPoint("TOPLEFT")
    welcomeFrame.changelogContent:SetSize(1, 1)
    welcomeFrame.changelogScroll:SetScrollChild(welcomeFrame.changelogContent)

    welcomeFrame.changelogText = welcomeFrame.changelogContent:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    welcomeFrame.changelogText:SetPoint("TOPLEFT")
    welcomeFrame.changelogText:SetJustifyH("LEFT")
    welcomeFrame.changelogText:SetText(LATEST_CHANGELOG_TEXT)

    local function layoutChangelog()
        local width = welcomeFrame.changelogScroll:GetWidth()
        welcomeFrame.changelogText:SetWidth(width)
        welcomeFrame.changelogContent:SetSize(width, welcomeFrame.changelogText:GetStringHeight())
    end
    welcomeFrame.changelogScroll:SetScript("OnSizeChanged", layoutChangelog)
    -- the scroll bar only when the text doesn't fit
    ns.AutoScrollBar(welcomeFrame.changelogScroll, function(has)
        welcomeFrame.changelogScroll:SetPoint("BOTTOMRIGHT", has and -48 or -24, 56)
    end)

    welcomeFrame.dontShowAgainCheck = CreateFrame("CheckButton", nil, welcomeFrame, "UICheckButtonTemplate")
    welcomeFrame.dontShowAgainCheck:SetSize(22, 22)
    welcomeFrame.dontShowAgainCheck:SetPoint("BOTTOMLEFT", 16, 16)
    -- Stores the version it was dismissed FOR, not just a bare true/false -- ticking it only silences the
    -- window until the next release, so whatever's new (and whoever's still hitting bugs) gets seen again.
    -- Account-wide (CompletaoDB directly, not ns.char): dismissing it on one character dismisses it for all.
    welcomeFrame.dontShowAgainCheck:SetScript("OnClick", function(self)
        CompletaoDB.welcomeDismissedVersion = self:GetChecked() and ns.Version() or ""
    end)

    welcomeFrame.dontShowAgainLabel = welcomeFrame:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    welcomeFrame.dontShowAgainLabel:SetPoint("LEFT", welcomeFrame.dontShowAgainCheck, "RIGHT", 2, 0)
    welcomeFrame.dontShowAgainLabel:SetText(L["Don't show this message again"])

    local closeButton = CreateFrame("Button", nil, welcomeFrame, "UIPanelButtonTemplate")
    closeButton:SetSize(90, 22)
    closeButton:SetPoint("BOTTOMRIGHT", -16, 14)
    closeButton:SetText(CLOSE)
    closeButton:SetScript("OnClick", function() welcomeFrame:Hide() end)

    welcomeFrame:SetScript("OnShow", function()
        local version = ns.Version()
        welcomeFrame.changelogLabel:SetText(L["What's new in v%s:"]:format(version))
        layoutChangelog()
        welcomeFrame.dontShowAgainCheck:SetChecked(CompletaoDB.welcomeDismissedVersion == version)
    end)
    welcomeFrame:Hide() -- frames are born shown: hidden until the first show (which would close it otherwise)
end

-- Always shows the window, dismissed or not (Preferences' "What's new" button, /completao changelog).
function ns.Welcome_Show()
    if not welcomeFrame then create() end
    welcomeFrame:Show()
end

-- Shown once per login/reload (Completao.lua's PLAYER_ENTERING_WORLD), unless already dismissed for this
-- exact version.
function ns.Welcome_ShowIfNew()
    if CompletaoDB.welcomeDismissedVersion == ns.Version() then return end
    ns.Welcome_Show()
end
