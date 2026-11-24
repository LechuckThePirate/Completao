local ADDON, ns = ...

-- The look of every window ("Cartographic Codex"): one palette, the fonts and the pieces the windows are built
-- from (panels, gold and ghost buttons, progress bars, the gold border, the status icons). The windows only ask
-- for them by name, so a color or a texture changes here for all of them.
local T = {}
ns.Theme = T

T.MEDIA = "Interface\\AddOns\\" .. ADDON .. "\\Media\\Textures\\"
local WHITE = "Interface\\Buttons\\WHITE8x8"

local function hex(s, a)
    return { tonumber(s:sub(1, 2), 16) / 255, tonumber(s:sub(3, 4), 16) / 255, tonumber(s:sub(5, 6), 16) / 255, a or 1 }
end

T.colors = {
    obsidian = hex("0D1017"),    -- the window's base and the tables
    slate = hex("161B26"),       -- side panel, header bar, table headers, the quest drawer
    card = hex("1E2533"),        -- alternate rows, chain nodes, settings cards
    cardHover = hex("262F40"),
    gold = hex("D4AF37"),        -- titles, active icons, the selected tab, focus borders, progress
    goldLight = hex("F0D27A"),
    brass = hex("5C4D2E"),       -- 1 px borders between panels, group dividers
    ready = hex("22C55E"),       -- ready to turn in, steps done, checks
    active = hex("F59E0B"),      -- in progress, partial objectives
    locked = hex("64748B"),      -- unmet requirements, locked quests
    muted = hex("94A3B8"),       -- secondary text, tabular data
    text = hex("E2E8F0"),
    danger = hex("D9534F"),
    dangerDim = hex("8C3B37"),
    -- ink, for what is written on parchment
    ink = hex("2B1A0B"),
    inkSoft = hex("5A3E22"),
    inkMuted = hex("7A5C38"),
    inkGreen = hex("1E6B1E"),
    sienna = hex("7A3510"), -- headings and marks on parchment
}

-- FRIZQT__.TTF has no Cyrillic, Korean or Chinese glyphs, and quest and zone names come in the client's language, so the
-- text takes the client's own standard font (FRIZQT__.TTF on the Latin clients, FRIZQT___CYR.TTF on ruRU, their own
-- file on koKR / zhCN / zhTW). The logo and the numbers are Latin text, but the Asian clients may lack those files.
local STANDARD = _G.STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF"
local ASIAN = { koKR = true, zhCN = true, zhTW = true }
local asian = GetLocale and ASIAN[GetLocale()]

T.fonts = {
    logo = { asian and STANDARD or "Fonts\\MORPHEUS.TTF", 17 },
    title = { STANDARD, 15 },
    heading = { STANDARD, 12 },
    quest = { STANDARD, 11 },
    body = { STANDARD, 11 },
    small = { STANDARD, 10 },
    data = { asian and STANDARD or "Fonts\\ARIALN.TTF", 11 },
}

-- r, g, b, a of a palette color (alpha overridden when given).
function T.rgba(name, alpha)
    local c = T.colors[name]
    return c[1], c[2], c[3], alpha or c[4]
end

-- "|cffrrggbb" for inline text.
function T.code(name)
    local c = T.colors[name]
    return ("|cff%02x%02x%02x"):format(math.floor(c[1] * 255 + 0.5), math.floor(c[2] * 255 + 0.5), math.floor(c[3] * 255 + 0.5))
end

-- A font from T.fonts on a font string (the template's font stays if the client can't load the file).
function T.Font(fs, kind, color, shadow)
    local f = T.fonts[kind] or T.fonts.body
    if fs.SetFont then fs:SetFont(f[1], f[2], "") end
    if color then fs:SetTextColor(T.rgba(color)) end
    -- ink (on parchment) goes without the drop shadow
    local ink = type(color) == "string" and color:find("^ink")
    if fs.SetShadowOffset then
        if shadow ~= false and not ink then
            fs:SetShadowOffset(1, -1)
            fs:SetShadowColor(0, 0, 0, 0.9)
        else
            fs:SetShadowOffset(0, 0)
        end
    end
    return fs
end

function T.Text(parent, kind, color, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY", "GameFontHighlight")
    return T.Font(fs, kind, color)
end

local BACKDROP = { bgFile = WHITE, edgeFile = WHITE, edgeSize = 1 }
T.BACKDROP = BACKDROP

-- A flat panel: palette background (slate by default) and a 1 px brass border. On a BackdropTemplate frame.
function T.Style(f, bg, border, bgAlpha)
    f:SetBackdrop(BACKDROP)
    f:SetBackdropColor(T.rgba(bg or "slate", bgAlpha))
    if border == false then
        f:SetBackdropBorderColor(0, 0, 0, 0)
    else
        f:SetBackdropBorderColor(T.rgba(border or "brass"))
    end
    return f
end

function T.CreateStyledFrame(parent, kind, bg, border, name)
    local f = CreateFrame(kind or "Frame", name, parent, "BackdropTemplate")
    return T.Style(f, bg, border)
end

-- A 9-slice texture drawn over `f` with nine (or eight, without `center`) textures: corners at `size`, edges and
-- middle stretched. texW x texH is the file's size and `margin` its corners' (in its pixels); `out` = how far outside
-- the frame it goes. Returns the pieces (pieces.center is the middle).
function T.NineSlice(f, file, texW, texH, margin, size, out, layer, sublevel, center)
    out = out or 0
    local mx, my = margin / texW, margin / texH
    local parts = {}
    local function piece(l, r, t, b)
        local tex = f:CreateTexture(nil, layer or "OVERLAY", nil, sublevel or 7)
        tex:SetTexture(file)
        tex:SetTexCoord(l, r, t, b)
        parts[#parts + 1] = tex
        return tex
    end
    local tl, tr = piece(0, mx, 0, my), piece(1 - mx, 1, 0, my)
    local bl, br = piece(0, mx, 1 - my, 1), piece(1 - mx, 1, 1 - my, 1)
    for _, c in ipairs({ tl, tr, bl, br }) do c:SetSize(size, size) end
    tl:SetPoint("TOPLEFT", -out, out)
    tr:SetPoint("TOPRIGHT", out, out)
    bl:SetPoint("BOTTOMLEFT", -out, -out)
    br:SetPoint("BOTTOMRIGHT", out, -out)
    local top, bottom = piece(mx, 1 - mx, 0, my), piece(mx, 1 - mx, 1 - my, 1)
    top:SetPoint("TOPLEFT", tl, "TOPRIGHT")
    top:SetPoint("BOTTOMRIGHT", tr, "BOTTOMLEFT")
    bottom:SetPoint("TOPLEFT", bl, "TOPRIGHT")
    bottom:SetPoint("BOTTOMRIGHT", br, "BOTTOMLEFT")
    local left, right = piece(0, mx, my, 1 - my), piece(1 - mx, 1, my, 1 - my)
    left:SetPoint("TOPLEFT", tl, "BOTTOMLEFT")
    left:SetPoint("BOTTOMRIGHT", bl, "TOPRIGHT")
    right:SetPoint("TOPLEFT", tr, "BOTTOMLEFT")
    right:SetPoint("BOTTOMRIGHT", br, "TOPRIGHT")
    if center then
        parts.center = piece(mx, 1 - mx, my, 1 - my)
        parts.center:SetPoint("TOPLEFT", tl, "BOTTOMRIGHT")
        parts.center:SetPoint("BOTTOMRIGHT", br, "TOPLEFT")
    end
    return parts
end

-- Sets the color (and alpha) of every piece of a 9-slice.
function T.SliceColor(parts, r, g, b, a)
    for _, tex in ipairs(parts) do tex:SetVertexColor(r, g, b, a or 1) end
end

-- Parchment (torn, burnt edges) filling `f`; `page`: the lighter sheet made for reading. `size`: the corner and rim's
-- on-screen size (default 40, as big panels use); a small window (the focus window) passes a smaller one, or the
-- burnt rim alone would swallow most of it, leaving too little of the light page for the text to sit on.
-- A 9-slice: the burnt corners and the rim's width stay as they are however big the sheet gets; only the middle
-- and the length of the edges stretch. The page (`page`) also has a wide version, used while the sheet is wider
-- than tall (a maximized quest drawer), so neither is ever stretched much.
function T.Parchment(f, layer, sublevel, page, size)
    size = size or 40
    local tall = T.NineSlice(f, T.MEDIA .. (page and "ParchmentPage" or "Parchment"), 256, 512, 44, size, 0,
        layer or "BACKGROUND", sublevel or 4, true)
    if not page then return tall end
    local wide = T.NineSlice(f, T.MEDIA .. "ParchmentPageWide", 1024, 512, 44, size, 0, layer or "BACKGROUND", sublevel or 4, true)
    local function pick()
        local w, h = f:GetWidth() or 0, f:GetHeight() or 0
        local isWide = h > 0 and w > h * 1.3
        for _, tex in ipairs(tall) do tex:SetShown(not isWide) end
        for _, tex in ipairs(wide) do tex:SetShown(isWide) end
        f.parchmentWide = isWide
    end
    f:HookScript("OnSizeChanged", pick)
    pick()
    return tall, wide
end

-- The background of the quest tree and of the tables: a faint runic sigil, added onto the stone, over a dark veil that
-- calms the window's cracked stone so what is on it stands out. Both stay as the content scrolls; the sigil follows the
-- size of `f` (its smaller side).
function T.SigilBackground(f)
    local shade = f:CreateTexture(nil, "BACKGROUND", nil, -2)
    shade:SetAllPoints()
    shade:SetColorTexture(T.rgba("obsidian", 0.6))
    local sigil = f:CreateTexture(nil, "BACKGROUND", nil, -1)
    sigil:SetTexture(T.MEDIA .. "TreeSigil")
    sigil:SetBlendMode("ADD")
    sigil:SetAlpha(0.2)
    sigil:SetPoint("CENTER")
    sigil:SetSize(400, 400)
    f:HookScript("OnSizeChanged", function(self)
        local side = math.min(self:GetWidth() or 0, self:GetHeight() or 0) * 0.95
        if side > 0 then sigil:SetSize(side, side) end
    end)
    return sigil, shade
end

-- The gold frame (BorderGold9Slice: 2 px burnished gold, rivets in the corners) drawn around `f` with eight
-- textures: corners at their size, edges stretched. `size` = how big a corner is drawn (16 by default),
-- `out` = how far outside the frame it goes.
function T.ApplyGoldBorder(f, size, out, layer)
    size, out = size or 16, out or 3
    local parts = T.NineSlice(f, T.MEDIA .. "BorderGold9Slice", 64, 64, 16, size, out, layer, 7)
    f.goldBorder = parts
    return parts
end

function T.SetGoldBorderShown(f, on)
    for _, tex in ipairs(f.goldBorder or {}) do tex:SetShown(on) end
end

-- Status icons (StatusIcons, four 64 x 64 in a row): "quest" (yellow !), "turnin" (green ?), "lock", "star".
local ICON_INDEX = { quest = 0, turnin = 1, lock = 2, star = 3 }
function T.SetStatusIcon(tex, kind)
    local i = ICON_INDEX[kind]
    if not i then tex:Hide() return end
    tex:SetTexture(T.MEDIA .. "StatusIcons")
    tex:SetTexCoord(i / 4, (i + 1) / 4, 0, 1)
    tex:Show()
end

-- The same as inline text, for menus and labels.
function T.StatusIconText(kind, size)
    local i = ICON_INDEX[kind]
    if not i then return "" end
    return ("|T%sStatusIcons:%d:%d:0:0:256:64:%d:%d:0:64|t"):format(T.MEDIA, size, size, i * 64, (i + 1) * 64)
end

---------------------------------------------------------------------------------------------------------- buttons

-- Paints a button for its state: normal, hover (the mouse over it) or disabled.
local function paintButton(b)
    local style = b.themeStyle
    local enabled = b:IsEnabled()
    local hover = enabled and b.hovered
    local fs = b:GetFontString()
    if style == "gold" then
        b.shade:SetShown(enabled)
        if enabled then
            b.fill:SetColorTexture(T.rgba(hover and "goldLight" or "gold"))
            b:SetBackdropBorderColor(T.rgba("goldLight"))
            if fs then fs:SetTextColor(0.08, 0.06, 0.02) end
        else
            b.fill:SetColorTexture(T.rgba("brass", 0.6))
            b:SetBackdropBorderColor(T.rgba("brass"))
            if fs then fs:SetTextColor(T.rgba("locked")) end
        end
    else
        local danger = style == "danger"
        b.fill:SetColorTexture(T.rgba(hover and "cardHover" or "card"))
        local border = not enabled and "brass" or hover and (danger and "danger" or "gold") or (danger and "dangerDim" or "brass")
        b:SetBackdropBorderColor(T.rgba(border))
        if fs then
            if not enabled then fs:SetTextColor(T.rgba("locked"))
            elseif danger then fs:SetTextColor(T.rgba("danger"))
            else fs:SetTextColor(T.rgba(hover and "goldLight" or "text")) end
        end
        if b.icon then b.icon:SetDesaturated(not enabled) end
    end
end
T.PaintButton = paintButton

-- style: "gold" (the primary action), "ghost" (secondary, dark) or "danger" (dark, soft red). icon: a texture
-- path shown before the text.
local function makeButton(parent, text, w, h, style, icon)
    local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
    b:SetSize(w or 120, h or 22)
    b:SetBackdrop(BACKDROP)
    b:SetBackdropColor(0, 0, 0, 0)
    b.themeStyle = style
    b.fill = b:CreateTexture(nil, "BACKGROUND")
    b.fill:SetPoint("TOPLEFT", 1, -1)
    b.fill:SetPoint("BOTTOMRIGHT", -1, 1)
    -- a gold button's lower half a little darker: a soft bevel
    b.shade = b:CreateTexture(nil, "BORDER")
    b.shade:SetPoint("BOTTOMLEFT", b.fill, "BOTTOMLEFT")
    b.shade:SetPoint("TOPRIGHT", b.fill, "RIGHT")
    b.shade:SetColorTexture(0, 0, 0, 0.18)
    b.shade:SetShown(style == "gold")
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    T.Font(fs, "body", nil, style ~= "gold")
    fs:SetWordWrap(false)
    b:SetFontString(fs)
    fs:ClearAllPoints()
    if icon then
        b.icon = b:CreateTexture(nil, "ARTWORK")
        b.icon:SetSize((h or 22) - 8, (h or 22) - 8)
        b.icon:SetPoint("LEFT", 6, 0)
        b.icon:SetTexture(icon)
        if icon:find("^Interface\\Icons\\") then b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92) end -- without the icon's frame
        fs:SetPoint("LEFT", b.icon, "RIGHT", 5, 0)
        fs:SetPoint("RIGHT", -6, 0)
        fs:SetJustifyH("LEFT")
    else
        fs:SetPoint("LEFT", 6, 0)
        fs:SetPoint("RIGHT", -6, 0)
        fs:SetJustifyH("CENTER")
    end
    if text then b:SetText(text) end
    b:HookScript("OnEnter", function(self) self.hovered = true; paintButton(self) end)
    b:HookScript("OnLeave", function(self) self.hovered = false; paintButton(self) end)
    b:HookScript("OnEnable", paintButton)
    b:HookScript("OnDisable", paintButton)
    b:HookScript("OnShow", paintButton)
    -- the state can change without the scripts firing (on a hidden button): painted again then
    for _, method in ipairs({ "SetEnabled", "Enable", "Disable" }) do
        local original = b[method]
        b[method] = function(self, ...)
            original(self, ...)
            paintButton(self)
        end
    end
    paintButton(b)
    return b
end

function T.CreateGoldButton(parent, text, w, h, icon) return makeButton(parent, text, w, h, "gold", icon) end
function T.CreateGhostButton(parent, text, w, h, icon) return makeButton(parent, text, w, h, "ghost", icon) end
function T.CreateDangerButton(parent, text, w, h, icon) return makeButton(parent, text, w, h, "danger", icon) end

-- Action icons (ActionIcons, five 64 x 64 glowing): "waypoint" (green pin), "chain" (green links), "open" (red
-- book), "map" (red magnifier), "abandon" (red cracked seal); "focus" is the compass medallion.
local ACTION_INDEX = { waypoint = 0, chain = 1, open = 2, map = 3, abandon = 4 }
function T.SetActionIcon(tex, kind)
    if kind == "focus" then
        tex:SetTexture(T.MEDIA .. "LogoMedallion")
        tex:SetTexCoord(0, 1, 0, 1)
        return
    end
    local i = ACTION_INDEX[kind] or 0
    tex:SetTexture(T.MEDIA .. "ActionIcons")
    tex:SetTexCoord(i / 5, (i + 1) / 5, 0, 1)
end

-- The same icons as inline text ("|T...|t"), for a line of text or a link in it.
function T.ActionIconText(kind, size)
    local i = ACTION_INDEX[kind] or 0
    return ("|T%sActionIcons:%d:%d:0:0:320:64:%d:%d:0:64|t"):format(T.MEDIA, size, size, i * 64, (i + 1) * 64)
end

-- A plate with rivets: "wood" (a wooden plate in bronze, the primary actions) or "stone" (dark stone in iron, the
-- rest); gold text with a shadow and the action's icon on the left (T.SetActionIcon). Lighter on hover; disabled,
-- grey and dim. The texture is a 3-slice: its ends keep their shape, the middle stretches.
local function paintPlate(b)
    local enabled = b:IsEnabled()
    for _, tex in ipairs(b.plate) do
        tex:SetDesaturated(not enabled)
        tex:SetVertexColor(1, 1, 1, enabled and 1 or 0.55)
    end
    b.glint:SetShown(enabled and b.hovered or false)
    if b.icon then
        b.icon:SetDesaturated(not enabled)
        b.icon:SetAlpha(enabled and 1 or 0.45)
    end
    local fs = b:GetFontString()
    if fs then fs:SetTextColor(T.rgba(not enabled and "locked" or b.hovered and "goldLight" or "gold")) end
end

function T.CreatePlateButton(parent, text, w, h, material, iconKind)
    h = h or 28
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w or 150, h)
    local file = T.MEDIA .. (material == "wood" and "ButtonWood" or "ButtonStone")
    local cap = h / 2 -- the 32 px end of a 64 px tall texture
    local function piece(l, r)
        local tex = b:CreateTexture(nil, "BACKGROUND")
        tex:SetTexture(file)
        tex:SetTexCoord(l, r, 0, 1)
        return tex
    end
    local left, mid, right = piece(0, 0.125), piece(0.125, 0.875), piece(0.875, 1)
    left:SetPoint("TOPLEFT")
    left:SetPoint("BOTTOMLEFT")
    left:SetWidth(cap)
    right:SetPoint("TOPRIGHT")
    right:SetPoint("BOTTOMRIGHT")
    right:SetWidth(cap)
    mid:SetPoint("TOPLEFT", left, "TOPRIGHT")
    mid:SetPoint("BOTTOMRIGHT", right, "BOTTOMLEFT")
    b.plate = { left, mid, right }
    b.glint = b:CreateTexture(nil, "ARTWORK")
    b.glint:SetPoint("TOPLEFT", 4, -4)
    b.glint:SetPoint("BOTTOMRIGHT", -4, 4)
    b.glint:SetColorTexture(1, 0.9, 0.6, 0.08)
    b.glint:Hide()
    local fs = b:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    T.Font(fs, "heading")
    fs:SetWordWrap(false)
    b:SetFontString(fs)
    fs:ClearAllPoints()
    if iconKind then
        b.icon = b:CreateTexture(nil, "OVERLAY")
        local size = iconKind == "focus" and h + 2 or h - 4
        b.icon:SetSize(size, size)
        b.icon:SetPoint("LEFT", iconKind == "focus" and -2 or 6, 0)
        T.SetActionIcon(b.icon, iconKind)
        fs:SetPoint("LEFT", b.icon, "RIGHT", 2, 0)
    else
        fs:SetPoint("LEFT", 10, 0)
    end
    fs:SetPoint("RIGHT", -10, 0)
    fs:SetJustifyH("CENTER")
    if text then b:SetText(text) end
    b:HookScript("OnEnter", function(self)
        self.hovered = true
        paintPlate(self)
        if self.tip then
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(type(self.tip) == "function" and self.tip() or self.tip)
            GameTooltip:Show()
        end
    end)
    b:HookScript("OnLeave", function(self)
        self.hovered = false
        paintPlate(self)
        if self.tip then GameTooltip_Hide() end
    end)
    b:HookScript("OnShow", paintPlate)
    for _, method in ipairs({ "SetEnabled", "Enable", "Disable" }) do
        local original = b[method]
        b[method] = function(self, ...)
            original(self, ...)
            paintPlate(self)
        end
    end
    b:SetMotionScriptsWhileDisabled(true) -- the tooltip says what it does even when it can't
    paintPlate(b)
    return b
end

-- A small square button with a picture drawn by lines (no texture needed): "close" (X), "minimize" (_),
-- "restore" (a box), "plus", "minus", "center" (a target). Gold on hover.
local GLYPHS = {
    close = { { -4, 4, 4, -4 }, { -4, -4, 4, 4 } },
    minimize = { { -4, -3, 4, -3 } },
    restore = { { -4, 4, 4, 4 }, { 4, 4, 4, -4 }, { 4, -4, -4, -4 }, { -4, -4, -4, 4 }, { -4, 2, 4, 2 } },
    plus = { { -4, 0, 4, 0 }, { 0, -4, 0, 4 } },
    minus = { { -4, 0, 4, 0 } },
    center = { { -5, 0, -2, 0 }, { 2, 0, 5, 0 }, { 0, -5, 0, -2 }, { 0, 2, 0, 5 }, { -1, -1, 1, 1 }, { -1, 1, 1, -1 } },
    chevronRight = { { -2, 4, 2, 0 }, { 2, 0, -2, -4 } },
    chevronLeft = { { 2, 4, -2, 0 }, { -2, 0, 2, -4 } },
    collapseLeft = { { -1, 6, -7, 0 }, { -7, 0, -1, -6 }, { 6, 6, 0, 0 }, { 0, 0, 6, -6 } },
    expandRight = { { 1, 6, 7, 0 }, { 7, 0, 1, -6 }, { -6, 6, 0, 0 }, { 0, 0, -6, -6 } },
    chevronDown = { { -4, 2, 0, -2 }, { 0, -2, 4, 2 } },
    expand = { { 1, 4, 4, 4 }, { 4, 4, 4, 1 }, { -1, -4, -4, -4 }, { -4, -4, -4, -1 }, { -4, -4, 4, 4 } },
    collapse = { { -1, 4, -1, 1 }, { -1, 1, -4, 1 }, { 1, -4, 1, -1 }, { 1, -1, 4, -1 }, { -4, 4, -1, 1 }, { 4, -4, 1, -1 } },
}
-- `anchor`/`ox`/`oy`: where the glyph's center goes on the button (its center by default); `color` a palette name
-- (muted, gold on hover, by default).
function T.SetGlyph(b, glyph, anchor, ox, oy, color)
    b.glyphLines = b.glyphLines or {}
    anchor, ox, oy = anchor or b.glyphAnchor or "CENTER", ox or b.glyphX or 0, oy or b.glyphY or 0
    b.glyphAnchor, b.glyphX, b.glyphY, b.glyphColor = anchor, ox, oy, color or b.glyphColor
    for i, s in ipairs(GLYPHS[glyph] or {}) do
        local l = b.glyphLines[i]
        if not l then
            l = b:CreateLine(nil, "OVERLAY")
            l:SetThickness(b.glyphThickness or 1.5)
            b.glyphLines[i] = l
        end
        l:SetStartPoint(anchor, b, s[1] + ox, s[2] + oy)
        l:SetEndPoint(anchor, b, s[3] + ox, s[4] + oy)
        l:SetColorTexture(T.rgba(b.hovered and (b.glyphHover or "goldLight") or b.glyphColor or "muted"))
        l:Show()
    end
    for i = #(GLYPHS[glyph] or {}) + 1, #b.glyphLines do b.glyphLines[i]:Hide() end
    b.glyph = glyph
end

function T.CreateIconButton(parent, glyph, size, tip)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size or 18, size or 18)
    b.hl = b:CreateTexture(nil, "BACKGROUND")
    b.hl:SetAllPoints()
    b.hl:SetColorTexture(1, 1, 1, 0)
    T.SetGlyph(b, glyph)
    b:SetScript("OnEnter", function(self)
        self.hovered = true
        self.hl:SetColorTexture(T.rgba("gold", 0.15))
        T.SetGlyph(self, self.glyph)
        if self.tip then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
            GameTooltip:SetText(type(self.tip) == "function" and self.tip() or self.tip)
            GameTooltip:Show()
        end
    end)
    b:SetScript("OnLeave", function(self)
        self.hovered = false
        self.hl:SetColorTexture(1, 1, 1, 0)
        T.SetGlyph(self, self.glyph)
        GameTooltip_Hide()
    end)
    b.tip = tip
    return b
end

---------------------------------------------------------------------------------------------------------- bars

-- A thin bar: a dark track and a fill. :SetProgress(done, total) or :SetValue(0-1); :SetFillColor(name).
-- With text = true, a centered label goes on it (:SetLabel).
function T.CreateProgressBar(parent, h, fillColor, withText)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(h or 4)
    bar.track = bar:CreateTexture(nil, "BACKGROUND")
    bar.track:SetAllPoints()
    bar.track:SetColorTexture(0, 0, 0, 0.45)
    bar.fill = bar:CreateTexture(nil, "ARTWORK")
    bar.fill:SetPoint("TOPLEFT")
    bar.fill:SetPoint("BOTTOMLEFT")
    bar.fill:SetWidth(0.001)
    bar.value = 0
    function bar:SetFillColor(name, alpha)
        self.fill:SetColorTexture(T.rgba(name, alpha))
    end
    function bar:SetValue(v)
        v = math.max(0, math.min(1, v or 0))
        self.value = v
        local w = (self:GetWidth() or 0) * v
        self.fill:SetWidth(math.max(0.001, w))
        self.fill:SetShown(v > 0)
    end
    function bar:SetProgress(done, total)
        self:SetValue(total and total > 0 and done / total or 0)
    end
    bar:SetScript("OnSizeChanged", function(self) self:SetValue(self.value) end)
    bar:SetFillColor(fillColor or "gold")
    if withText then
        bar.label = T.Text(bar, "small", "text")
        bar.label:SetPoint("CENTER", 0, 0)
        function bar:SetLabel(s) self.label:SetText(s) end
    end
    return bar
end

---------------------------------------------------------------------------------------------------------- inputs

-- A dark search box: magnifier, placeholder (box.Instructions, as the game's own) and a clear button.
function T.CreateSearchBox(parent, w, placeholder)
    local box = CreateFrame("EditBox", nil, parent, "BackdropTemplate")
    box:SetSize(w or 200, 22)
    T.Style(box, "obsidian", "brass")
    box:SetAutoFocus(false)
    box:SetFontObject("GameFontHighlightSmall")
    box:SetTextInsets(20, 18, 0, 0)
    local icon = box:CreateTexture(nil, "OVERLAY")
    icon:SetSize(12, 12)
    icon:SetPoint("LEFT", 5, 0)
    icon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    icon:SetVertexColor(T.rgba("muted"))
    local hint = T.Text(box, "small", "locked", "ARTWORK")
    hint:SetPoint("LEFT", 20, 0)
    hint:SetText(placeholder or "")
    box.Instructions = hint
    local clear = T.CreateIconButton(box, "close", 16)
    clear:SetPoint("RIGHT", -2, 0)
    clear:Hide()
    clear:SetScript("OnClick", function()
        box:SetText("")
        box:ClearFocus()
    end)
    box.clearButton = clear
    box:HookScript("OnTextChanged", function(self)
        local empty = (self:GetText() or "") == ""
        hint:SetShown(empty)
        clear:SetShown(not empty)
    end)
    box:HookScript("OnEditFocusGained", function(self) self:SetBackdropBorderColor(T.rgba("gold")) end)
    box:HookScript("OnEditFocusLost", function(self) self:SetBackdropBorderColor(T.rgba("brass")) end)
    box:HookScript("OnEscapePressed", function(self) self:ClearFocus() end)
    return box
end

-- A modern slider: a filled bar from the left up to the value and a round gold knob.
function T.StyleSlider(slider)
    local track = slider:CreateTexture(nil, "BACKGROUND")
    track:SetPoint("LEFT", 0, 0)
    track:SetPoint("RIGHT", 0, 0)
    track:SetHeight(4)
    track:SetColorTexture(T.rgba("card"))
    local fill = slider:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT", track, "LEFT")
    fill:SetHeight(4)
    fill:SetColorTexture(T.rgba("gold"))
    slider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local thumb = slider:GetThumbTexture()
    thumb:SetSize(18, 18)
    thumb:SetVertexColor(T.rgba("goldLight"))
    local function update()
        local lo, hi = slider:GetMinMaxValues()
        local v = slider:GetValue() or lo or 0
        local share = (hi and lo and hi > lo) and (v - lo) / (hi - lo) or 0
        fill:SetWidth(math.max(0.001, (slider:GetWidth() or 0) * share))
    end
    slider:HookScript("OnValueChanged", update)
    slider:HookScript("OnSizeChanged", update)
    slider.track, slider.fill = track, fill
    update()
end
