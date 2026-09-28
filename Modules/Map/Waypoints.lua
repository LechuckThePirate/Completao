local ADDON, ns = ...

-- Una ubicacion es { npc = "Nombre", area = <AreaTable id>, x = 44.4, y = 42.8 } (coordenadas 0-100).
-- El id de area se convierte a mapa del cliente por nombre de zona, la primera vez que hace falta.
local mapByName

local function buildMapIndex()
    mapByName = {}
    for id = 1, 2500 do
        local info = C_Map.GetMapInfo(id)
        if info and info.name and info.mapType == Enum.UIMapType.Zone and not mapByName[info.name] then
            mapByName[info.name] = id
        end
    end
end

-- Mapa de la zona de la ubicacion (no hacen falta coordenadas: sirve para abrir el mapa en la zona).
function ns.ResolveZone(loc)
    if not (loc and loc.area) then return nil end
    if loc.map then return loc.map end
    local name = C_Map.GetAreaInfo(loc.area)
    if not name then return nil end
    if not mapByName then buildMapIndex() end
    loc.map = mapByName[name]
    return loc.map
end

local function hasCoords(loc)
    return loc and loc.x and loc.x > 0
end

-- Mapa donde poner un punto: hace falta zona y coordenadas.
function ns.ResolveMap(loc)
    if not hasCoords(loc) then return nil end
    return ns.ResolveZone(loc)
end

function ns.CanWaypoint(loc)
    return ns.ResolveMap(loc) ~= nil
end

function ns.CanShowMap(loc)
    return ns.ResolveZone(loc) ~= nil
end

-- Marcador propio sobre el mapa del mundo: un "!" dorado que rebota con un resplandor que pulsa.
-- Cuelga del lienzo del mapa (se mueve y hace zoom con el) y se contra-escala para mantener su tamano.
-- Se muestra solo cuando el mapa visible es el de la ubicacion, y se borra al cerrar el mapa.
local pinState, pinHolder, pinFrame

local function mapCanvas()
    if not WorldMapFrame then return nil end
    return (WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas())
        or (WorldMapFrame.ScrollContainer and WorldMapFrame.ScrollContainer.Child)
end

local function ensurePin()
    if pinHolder then return true end
    local canvas = mapCanvas()
    if not canvas then return false end

    pinHolder = CreateFrame("Frame", nil, canvas)
    pinHolder:SetSize(1, 1)
    pinHolder:SetFrameStrata("DIALOG")
    pinFrame = CreateFrame("Frame", nil, pinHolder)
    pinFrame:SetSize(28, 28)
    pinFrame:SetPoint("CENTER", pinHolder, "CENTER", 0, 0)

    local glow = pinFrame:CreateTexture(nil, "BACKGROUND")
    glow:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\Icons\\Glow.png")
    glow:SetBlendMode("ADD")
    glow:SetSize(76, 76)
    glow:SetPoint("CENTER")
    glow:SetVertexColor(1, 0.85, 0.2)

    local icon = pinFrame:CreateTexture(nil, "ARTWORK")
    icon:SetTexture("Interface\\GossipFrame\\AvailableQuestIcon")
    icon:SetSize(30, 30)
    icon:SetPoint("CENTER")

    local pulse = glow:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local alpha = pulse:CreateAnimation("Alpha")
    alpha:SetFromAlpha(1)
    alpha:SetToAlpha(0.25)
    alpha:SetDuration(0.7)
    alpha:SetSmoothing("IN_OUT")
    pulse:Play()

    local hop = icon:CreateAnimationGroup()
    hop:SetLooping("BOUNCE")
    local move = hop:CreateAnimation("Translation")
    move:SetOffset(0, 7)
    move:SetDuration(0.45)
    move:SetSmoothing("IN_OUT")
    hop:Play()

    pinHolder:SetScript("OnUpdate", function(self)
        local st = pinState
        local canvasNow = mapCanvas()
        if not (st and canvasNow and WorldMapFrame:GetMapID() == st.map) then
            self:SetAlpha(0)
            return
        end
        self:SetAlpha(1)
        local w, h = canvasNow:GetWidth(), canvasNow:GetHeight()
        if w ~= self.w or h ~= self.h or st ~= self.st then
            self.w, self.h, self.st = w, h, st
            self:ClearAllPoints()
            self:SetPoint("CENTER", canvasNow, "TOPLEFT", st.x / 100 * w, -st.y / 100 * h)
        end
        local scale = WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale() or 1
        if scale and scale > 0 and scale ~= self.scale then
            self.scale = scale
            pinFrame:SetScale(1 / scale)
        end
    end)
    WorldMapFrame:HookScript("OnHide", function() pinState = nil end)
    return true
end

function ns.SetMapPin(map, x, y)
    pinState = { map = map, x = x, y = y }
    ensurePin()
end

function ns.ClearMapPin()
    pinState = nil
end

-- Abre el mapa del mundo en la zona de la ubicacion y, si hay coordenadas, deja el punto marcado.
function ns.ShowOnMap(loc, title)
    local map = ns.ResolveZone(loc)
    if not map then
        ns.Print(ns.L["No map location available for this quest giver."])
        return false
    end
    if hasCoords(loc) then ns.SetWaypoint(loc, title) else ns.ClearMapPin() end
    local opened = false
    if OpenWorldMap then
        opened = pcall(OpenWorldMap, map)
    end
    if not opened and WorldMapFrame then
        opened = pcall(function()
            if not WorldMapFrame:IsShown() then ShowUIPanel(WorldMapFrame) end
            WorldMapFrame:SetMapID(map)
        end)
    end
    ensurePin()
    return opened
end

function ns.SetWaypoint(loc, title)
    local map = ns.ResolveMap(loc)
    if not map then
        ns.Print(ns.L["No map location available for this quest giver."])
        return false
    end
    local x, y = loc.x / 100, loc.y / 100
    ns.SetMapPin(map, loc.x, loc.y)
    if TomTom and TomTom.AddWaypoint then
        TomTom:AddWaypoint(map, x, y, { title = title, persistent = false, minimap = true, world = true, crazy = true })
    elseif C_Map.SetUserWaypoint and UiMapPoint then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x, y))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end
    else
        return false
    end
    ns.Print(ns.L["Waypoint set: %s"]:format(title))
    return true
end
