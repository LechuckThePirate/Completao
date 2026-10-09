local ADDON, ns = ...

-- A location is { npc = "Name", area = <AreaTable id>, x = 44.4, y = 42.8 } (coordinates 0-100), or, when the game
-- itself gave the spot, { map = <uiMapID>, x, y }.
-- The area id is turned into the client's map by zone name, the first time it is needed.
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

-- Map of the location's zone (no coordinates needed: enough to open the map on the zone).
function ns.ResolveZone(loc)
    if not loc then return nil end
    if loc.map then return loc.map end
    if not loc.area then return nil end
    local name = C_Map.GetAreaInfo(loc.area)
    if not name then return nil end
    if not mapByName then buildMapIndex() end
    loc.map = mapByName[name]
    return loc.map
end

local function hasCoords(loc)
    return loc and loc.x and loc.x > 0
end

-- Map to put a point on: needs a zone and coordinates.
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

local function worldPos(map, x, y)
    if not (C_Map.GetWorldPosFromMapPos and CreateVector2D) then return nil end
    local continent, pos = C_Map.GetWorldPosFromMapPos(map, CreateVector2D(x, y))
    if continent and pos then return continent, pos.x, pos.y end
end

-- The player's map and position on it (0-1), or nil.
function ns.PlayerPosition()
    local map = C_Map.GetBestMapForUnit("player")
    local p = map and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map, "player")
    if not p then return nil end
    local x, y = p:GetXY()
    return map, x, y
end

-- Distance in yards from the player to a location, or nil when it can't be told (no coordinates, the
-- player's position unknown, or another continent).
function ns.DistanceTo(loc)
    local map = ns.ResolveMap(loc)
    if not map then return nil end
    local playerMap, px, py = ns.PlayerPosition()
    if not playerMap then return nil end
    local c1, x1, y1 = worldPos(playerMap, px, py)
    local c2, x2, y2 = worldPos(map, loc.x / 100, loc.y / 100)
    if not (c1 and c2 and c1 == c2) then return nil end
    local d = math.sqrt((x1 - x2) ^ 2 + (y1 - y2) ^ 2)
    if d ~= d or d == math.huge then return nil end -- the client gave no real position (e.g. a city map)
    return d
end

-- Distances read in meters unless the client is in a yards locale (US and UK English); the game gives
-- them in yards. ns.char.distanceUnit = "yd" | "m" forces one.
local YARD = 0.9144
function ns.FormatDistance(yards)
    if not yards then return "" end
    local unit = ns.char and ns.char.distanceUnit
    local metric
    if unit then
        metric = unit == "m"
    else
        local locale = GetLocale()
        metric = locale ~= "enUS" and locale ~= "enGB"
    end
    local d = metric and yards * YARD or yards
    local small, big = metric and "%d m" or "%d yd", metric and "%.1f km" or "%.1fk yd"
    return d < 1000 and small:format(math.floor(d)) or big:format(d / 1000)
end

-- Our own marker on the world map: a bouncing navigation-style pin with the addon's icon in its head. It
-- hangs from the map's canvas (moves and zooms with it) and is counter-scaled to keep its size. Shown only
-- while the visible map is the location's, and cleared when the map closes.
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
    -- a map pin with the addon's icon in its head: the point of the pin is on the spot
    pinFrame = CreateFrame("Frame", nil, pinHolder)
    pinFrame:SetSize(44, 44)
    pinFrame:SetPoint("BOTTOM", pinHolder, "CENTER", 0, 0)

    local base = pinFrame:CreateTexture(nil, "ARTWORK")
    base:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\Icons\\PinBase.png")
    base:SetAllPoints()

    local icon = pinFrame:CreateTexture(nil, "OVERLAY")
    icon:SetTexture("Interface\\AddOns\\" .. ADDON .. "\\Icons\\" .. ADDON .. ".png")
    icon:SetSize(22, 22)
    icon:SetPoint("CENTER", pinFrame, "TOP", 0, -18)

    local hop = pinFrame:CreateAnimationGroup()
    hop:SetLooping("BOUNCE")
    local move = hop:CreateAnimation("Translation")
    move:SetOffset(0, 8)
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

-- Opens the world map on the location's zone and, with coordinates, leaves the spot marked.
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

-- What the waypoint is for (the optional tag given to SetWaypoint, e.g. a quest step), so the tables can
-- mark it. It is forgotten when the game's waypoint is moved or cleared by something else.
local focus
function ns.FocusTag()
    return focus and focus.tag
end

local function focusChanged()
    if ns.Search_Refresh then ns.Search_Refresh() end
end

local function checkFocus()
    if not (focus and focus.blizzard) then return end
    local p = C_Map.GetUserWaypoint and C_Map.GetUserWaypoint()
    local pos = p and p.position
    if not (pos and p.uiMapID == focus.map and math.abs(pos.x - focus.x) < 1e-3 and math.abs(pos.y - focus.y) < 1e-3) then
        focus = nil
        focusChanged()
    end
end

local focusEvents = CreateFrame("Frame")
pcall(focusEvents.RegisterEvent, focusEvents, "USER_WAYPOINT_UPDATED")
focusEvents:SetScript("OnEvent", checkFocus)

-- `quiet`: no chat message (the focus window moves the waypoint on its own as objectives are done).
function ns.SetWaypoint(loc, title, tag, quiet)
    local map = ns.ResolveMap(loc)
    if not map then
        if not quiet then ns.Print(ns.L["No map location available for this quest giver."]) end
        return false
    end
    local x, y = loc.x / 100, loc.y / 100
    ns.SetMapPin(map, loc.x, loc.y)
    -- TomTom keeps every waypoint it is given: the one we set before goes away, so they don't pile up
    if focus and focus.uid and TomTom and TomTom.RemoveWaypoint then pcall(TomTom.RemoveWaypoint, TomTom, focus.uid) end
    -- set before the game's call: it fires the event that checks it
    focus = { tag = tag, map = map, x = x, y = y, blizzard = not (TomTom and TomTom.AddWaypoint) }
    if TomTom and TomTom.AddWaypoint then
        focus.uid = TomTom:AddWaypoint(map, x, y, { title = title, persistent = false, minimap = true, world = true, crazy = true })
    elseif C_Map.SetUserWaypoint and UiMapPoint then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x, y))
        if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
            C_SuperTrack.SetSuperTrackedUserWaypoint(true)
        end
    else
        focus = nil
        return false
    end
    if not quiet then ns.Print(ns.L["Waypoint set: %s"]:format(title)) end
    return true
end
