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

-- Scroll bars only when the content doesn't fit: without one, the space it took goes back to the scroll
-- frame. place(hasBar) re-anchors whatever depends on it, and is called only when that changes (and once
-- at the start, without a bar). needed() says whether the content overflows; by default, the frame's own
-- scroll range. Returns the function that checks it again, for when the content changes without the client
-- noticing.
function ns.AutoScrollBar(scroll, place, needed)
    local name = scroll.GetName and scroll:GetName()
    local bar = scroll.ScrollBar or (name and _G[name .. "ScrollBar"])
    local shown
    local function update()
        local need
        if needed then
            need = needed()
        else
            need = (scroll:GetVerticalScrollRange() or 0) > 0.5
        end
        need = need and true or false
        if bar then bar:SetShown(need) end
        if need ~= shown then
            shown = need
            place(need)
        end
    end
    scroll:HookScript("OnScrollRangeChanged", update)
    scroll:HookScript("OnSizeChanged", update)
    scroll:HookScript("OnShow", update)
    update()
    return update
end
