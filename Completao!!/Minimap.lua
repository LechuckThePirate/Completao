local _, ns = ...
local L = ns.L

local ICON = "Interface\\AddOns\\Completao!!\\Icons\\Completao.png"
local button

local function updatePosition()
    local angle = math.rad(ns.char.minimap.angle)
    local radius = Minimap:GetWidth() / 2 + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * radius, math.sin(angle) * radius)
end

local function onDragUpdate()
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    local cx, cy = GetCursorPosition()
    ns.char.minimap.angle = math.deg((math.atan2 or math.atan)(cy / scale - my, cx / scale - mx))
    updatePosition()
end

local function create()
    button = CreateFrame("Button", "CompletaoMinimapButton", Minimap)
    button:SetSize(31, 31)
    button:SetFrameStrata("MEDIUM")
    button:SetFrameLevel(8)
    button:SetHighlightTexture(136477) -- Interface\Minimap\UI-Minimap-ZoomButton-Highlight

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetSize(20, 20)
    background:SetPoint("TOPLEFT", 6, -5)
    background:SetTexture(136467) -- Interface\Minimap\UI-Minimap-Background

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(21, 21)
    icon:SetPoint("TOPLEFT", 5, -4)
    icon:SetTexture(ICON)

    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetSize(50, 50)
    border:SetPoint("TOPLEFT")
    border:SetTexture(136430) -- Interface\Minimap\MiniMap-TrackingBorder

    button:RegisterForClicks("LeftButtonUp")
    button:RegisterForDrag("LeftButton")
    button:SetScript("OnClick", function() ns.UI_Toggle() end)
    button:SetScript("OnDragStart", function(self)
        self:LockHighlight()
        self:SetScript("OnUpdate", onDragUpdate)
    end)
    button:SetScript("OnDragStop", function(self)
        self:SetScript("OnUpdate", nil)
        self:UnlockHighlight()
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("Completao!!")
        GameTooltip:AddLine(L["Left-click: open"], 1, 1, 1)
        GameTooltip:AddLine(L["Drag: move"], 0.7, 0.7, 0.7)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
end

function ns.Minimap_Init()
    if not Minimap then return end
    ns.char.minimap = ns.char.minimap or { angle = 225, hide = false }
    if not button then create() end
    updatePosition()
    button:SetShown(not ns.char.minimap.hide)
end

function ns.Minimap_Toggle()
    if not button then return end
    ns.char.minimap.hide = not ns.char.minimap.hide
    button:SetShown(not ns.char.minimap.hide)
    ns.Print(ns.char.minimap.hide and L["Minimap button hidden."] or L["Minimap button shown."])
end
