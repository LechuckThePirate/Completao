local _, ns = ...

-- Menu desplegable propio (lista emergente de botones bajo un control): no depende de los menus de
-- Blizzard, que cambian entre versiones del cliente. options: { { name = , color = {r,g,b}, disabled = } }.
-- Pulsar otra vez el mismo control lo cierra; elegir una opcion lo cierra y llama a onPick(opcion, indice).
local BACKDROP = { bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 }
local ROW_H, PER_COL = 18, 18
local popup

function ns.PopupMenu(anchor, options, onPick, width)
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
    -- se cierra si el control que lo abrio desaparece (se cierra la ventana, cambia la vista...)
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
    popup:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    popup:Show()
end

function ns.PopupMenu_Hide()
    if popup then popup:Hide() end
end
