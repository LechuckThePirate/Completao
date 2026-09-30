local _, ns = ...

-- Places controls in rows, left to right, within `width`: when one doesn't fit, it goes to the next row.
-- Called again on resize, so nothing overflows or gets covered. items: { frame = , w = width or a function
-- returning it, h = height (the frame's by default), dy = vertical nudge }. With skipHidden, hidden ones
-- don't count; with fromBottom, (x0, y0) is the bottom-left corner and rows stack upwards (the first one
-- on top). Returns the height used.
function ns.FlowLayout(parent, items, x0, y0, width, gapX, gapY, skipHidden, fromBottom)
    local placed, x, y, rowH = {}, 0, 0, 0
    for _, it in ipairs(items) do
        if not (skipHidden and not it.frame:IsShown()) then
            local w = type(it.w) == "function" and it.w() or it.w
            local h = it.h or it.frame:GetHeight()
            if x > 0 and x + w > width then
                x, y, rowH = 0, y + rowH + gapY, 0
            end
            placed[#placed + 1] = { it = it, x = x, y = y, h = h }
            x = x + w + gapX
            rowH = math.max(rowH, h)
        end
    end
    local total = #placed > 0 and (y + rowH) or 0
    for _, p in ipairs(placed) do
        local f = p.it.frame
        f:ClearAllPoints()
        if fromBottom then
            f:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x0 + p.x, y0 + total - p.y - p.h - (p.it.dy or 0))
        else
            f:SetPoint("TOPLEFT", parent, "TOPLEFT", x0 + p.x, -(y0 + p.y + (p.it.dy or 0)))
        end
    end
    return total
end

-- Width of a checkbox with its label (for FlowLayout).
function ns.CheckWidth(_, label)
    return function() return 24 + math.ceil(label:GetStringWidth()) + 4 end
end

-- A scroll frame (UIPanelScrollFrameTemplate) whose bar is only there when there is something to scroll:
-- the template keeps the bar, its arrows and thumb showing (greyed out) even when the content fits, which
-- is noise next to a short list. `scrollBarHideable` is the template's own switch for that; it acts when the
-- scroll range changes, so it is also run once now and whenever the frame is shown.
function ns.HideableScroll(scroll)
    scroll.scrollBarHideable = true
    local function sync()
        if ScrollFrame_OnScrollRangeChanged then ScrollFrame_OnScrollRangeChanged(scroll) end
    end
    scroll:HookScript("OnShow", sync)
    sync()
    return scroll
end
