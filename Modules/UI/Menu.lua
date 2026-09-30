local _, ns = ...

-- Our own dropdown menu (a popup list of buttons under a control): it doesn't depend on Blizzard's menus,
-- which change between client versions. options: { { name = , color = {r,g,b}, disabled = } }.
-- Clicking the same control again closes it; picking an option closes it and calls onPick(option, index).
-- It opens under the control, or to its right with side = "right".
local BACKDROP = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }
local ROW_H, PER_COL = 18, 18
local popup

function ns.PopupMenu(anchor, options, onPick, width, side)
    if not popup then
        popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
        popup:SetBackdrop(BACKDROP)
        popup:SetBackdropColor(0.05, 0.05, 0.08, 0.98)
        popup:SetBackdropBorderColor(0.6, 0.5, 0.1, 1)
        popup:SetFrameStrata("FULLSCREEN_DIALOG")
        popup:SetClampedToScreen(true)
        popup:EnableMouse(true)
        popup.buttons = {}
        popup:Hide()
    end
    if popup:IsShown() and popup.anchor == anchor then popup:Hide() return end
    popup.anchor = anchor
    -- closes if the control that opened it goes away (the window closes, the view changes...)
    if not anchor.menuHooked then
        anchor.menuHooked = true
        anchor:HookScript("OnHide", function(self) if popup and popup.anchor == self then popup:Hide() end end)
    end
    local colW = width or 200
    local cols = math.max(1, math.ceil(#options / PER_COL))
    for i, opt in ipairs(options) do
        local b = popup.buttons[i]
        if not b then
            b = CreateFrame("Button", nil, popup)
            b.text = b:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            b.text:SetPoint("LEFT", 4, 0)
            b.text:SetPoint("RIGHT", -4, 0)
            b.text:SetJustifyH("LEFT")
            b.text:SetWordWrap(false)
            b:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
            popup.buttons[i] = b
        end
        b:SetSize(colW - 8, ROW_H)
        b.text:SetText(opt.name)
        local c = opt.color or { 1, 1, 1 }
        b.text:SetTextColor(c[1], c[2], c[3])
        b:SetEnabled(not opt.disabled)
        b:SetScript("OnClick", function()
            popup:Hide()
            onPick(opt, i)
        end)
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 4 + math.floor((i - 1) / PER_COL) * colW, -4 - ((i - 1) % PER_COL) * ROW_H)
        b:Show()
    end
    for i = #options + 1, #popup.buttons do popup.buttons[i]:Hide() end
    popup:SetSize(cols * colW, 8 + math.min(#options, PER_COL) * ROW_H)
    popup:ClearAllPoints()
    if side == "right" then
        popup:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 2, 0)
    else
        popup:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    end
    popup:Show()
end

function ns.PopupMenu_Hide()
    if popup then popup:Hide() end
end
