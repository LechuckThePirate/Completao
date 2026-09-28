local _, ns = ...

-- Coloca controles en filas, de izquierda a derecha, dentro de `width`: cuando uno no cabe, pasa a la fila
-- siguiente. Se vuelve a llamar al cambiar el tamaño, asi nada se sale ni queda tapado. items: { frame = ,
-- w = ancho o funcion que lo da, h = alto (por defecto el del frame), dy = ajuste vertical }. Con
-- skipHidden no cuenta los ocultos; con fromBottom, (x0, y0) es la esquina inferior izquierda y las filas
-- se apilan hacia arriba (la primera, arriba del todo). Devuelve el alto ocupado.
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

-- Ancho de una casilla con su texto (para FlowLayout).
function ns.CheckWidth(_, label)
    return function() return 24 + math.ceil(label:GetStringWidth()) + 4 end
end
