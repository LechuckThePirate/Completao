dofile("setupTests.lua")

describe("Waypoints", function()
    local ns
    local elwynn = { npc = "Marshal", area = 12, x = 42.1, y = 65.9 }

    before_each(function()
        WowMock.Reset()
        WowMock.maps[1429] = { name = "Area12", mapType = Enum.UIMapType.Zone }
        ns = LoadAddon({ files = { "Modules/Map/Waypoints.lua" } })
        ns.Print = function(...) WowMock.lastPrint = table.concat({ ... }, " ") end
        _G.TomTom = nil
    end)

    it("turns a location's zone into the client's map by name", function()
        assert.are.equal(1429, ns.ResolveZone({ area = 12 }))
        assert.is_nil(ns.ResolveZone({ area = 999 }))
    end)

    it("a waypoint needs coordinates; showing the map only needs the zone", function()
        assert.is_true(ns.CanWaypoint(elwynn))
        assert.is_false(ns.CanWaypoint({ area = 12 }))
        assert.is_true(ns.CanShowMap({ area = 12 }))
        assert.is_false(ns.CanShowMap({ area = 999 }))
    end)

    it("with TomTom, sets the waypoint in TomTom", function()
        local got
        _G.TomTom = { AddWaypoint = function(_, map, x, y, opts) got = { map, x, y, opts.title } end }
        assert.is_true(ns.SetWaypoint(elwynn, "Marshal"))
        assert.are.equal(1429, got[1])
        assert.near(0.421, got[2], 1e-9)
        assert.near(0.659, got[3], 1e-9)
        assert.are.equal("Marshal", got[4])
    end)

    it("a new waypoint replaces the one set before in TomTom, so they don't pile up", function()
        local added, removed = 0, {}
        _G.TomTom = {
            AddWaypoint = function() added = added + 1 return "uid" .. added end,
            RemoveWaypoint = function(_, uid) removed[#removed + 1] = uid end,
        }
        ns.SetWaypoint(elwynn, "One")
        ns.SetWaypoint(elwynn, "Two")
        assert.are.same({ "uid1" }, removed)
    end)

    it("quiet: sets the waypoint without a word in chat", function()
        WowMock.lastPrint = nil
        assert.is_true(ns.SetWaypoint(elwynn, "Marshal", nil, true))
        assert.is_nil(WowMock.lastPrint)
        assert.is_true(ns.SetWaypoint(elwynn, "Marshal"))
        assert.matches("Waypoint set", WowMock.lastPrint)
    end)

    it("without TomTom, uses the game's waypoint", function()
        assert.is_true(ns.SetWaypoint(elwynn, "Marshal"))
        assert.are.equal(1429, WowMock.userWaypoint.mapID)
        assert.near(0.421, WowMock.userWaypoint.x, 1e-9)
    end)

    describe("focus", function()
        local current
        before_each(function()
            current = nil
            C_Map.GetUserWaypoint = function() return current end
            C_Map.SetUserWaypoint = function(p) current = { uiMapID = p.mapID, position = { x = p.x, y = p.y } } end
            ns.Search_Refresh = function() ns.refreshed = (ns.refreshed or 0) + 1 end
        end)
        after_each(function() C_Map.GetUserWaypoint = nil end)

        it("remembers what the waypoint was set for, and keeps it when the game reports the same spot", function()
            ns.SetWaypoint(elwynn, "Marshal", "166:2")
            assert.are.equal("166:2", ns.FocusTag())
            FireEvent("USER_WAYPOINT_UPDATED")
            assert.are.equal("166:2", ns.FocusTag())
        end)

        it("forgets it when the waypoint is moved or cleared, and asks for a redraw", function()
            ns.SetWaypoint(elwynn, "Marshal", "166:2")
            current = { uiMapID = 1429, position = { x = 0.9, y = 0.1 } }
            FireEvent("USER_WAYPOINT_UPDATED")
            assert.is_nil(ns.FocusTag())
            assert.are.equal(1, ns.refreshed)
            ns.SetWaypoint(elwynn, "Marshal", "166:2")
            current = nil
            FireEvent("USER_WAYPOINT_UPDATED")
            assert.is_nil(ns.FocusTag())
        end)
    end)

    it("with no place, warns and sets nothing", function()
        assert.is_false(ns.SetWaypoint({ area = 12 }, "x"))
        assert.matches("No map location", WowMock.lastPrint)
    end)

    describe("distance", function()
        local saved = {}
        before_each(function()
            for _, k in ipairs({ "GetBestMapForUnit", "GetPlayerMapPosition", "GetWorldPosFromMapPos" }) do saved[k] = C_Map[k] end
            _G.CreateVector2D = function(x, y) return { x = x, y = y } end
            C_Map.GetBestMapForUnit = function() return 1429 end
            C_Map.GetPlayerMapPosition = function() return { GetXY = function() return 0.5, 0.5 end } end
            -- 1 map unit = 1000 yards, on continent 0
            C_Map.GetWorldPosFromMapPos = function(_, v) return 0, { x = v.x * 1000, y = v.y * 1000 } end
        end)
        after_each(function()
            for k, v in pairs(saved) do C_Map[k] = v end
            _G.CreateVector2D = nil
        end)

        it("is the yards from the player to the location", function()
            assert.near(math.sqrt((0.5 - 0.421) ^ 2 + (0.5 - 0.659) ^ 2) * 1000, ns.DistanceTo(elwynn), 1e-6)
        end)

        it("reads in meters, except in the US and UK English locales (or as forced)", function()
            WowMock.locale = "esES"
            assert.are.equal("320 m", ns.FormatDistance(350))
            assert.are.equal("1.2 km", ns.FormatDistance(1300))
            assert.are.equal("", ns.FormatDistance(nil))
            WowMock.locale = "enUS"
            assert.are.equal("350 yd", ns.FormatDistance(350))
            assert.are.equal("1.3k yd", ns.FormatDistance(1300))
            ns.char = { distanceUnit = "m" }
            assert.are.equal("320 m", ns.FormatDistance(350))
            ns.char = nil
        end)

        it("is unknown without coordinates, without the player's position or across continents", function()
            assert.is_nil(ns.DistanceTo({ area = 12 }))
            C_Map.GetPlayerMapPosition = function() return nil end
            assert.is_nil(ns.DistanceTo(elwynn))
            C_Map.GetPlayerMapPosition = function() return { GetXY = function() return 0.5, 0.5 end } end
            local n = 0
            C_Map.GetWorldPosFromMapPos = function(_, v) n = n + 1; return n, { x = v.x, y = v.y } end
            assert.is_nil(ns.DistanceTo(elwynn))
        end)
    end)

    it("show on map opens the zone's map and marks the spot", function()
        local opened
        _G.OpenWorldMap = function(map) opened = map end
        ns.ShowOnMap(elwynn, "Marshal")
        assert.are.equal(1429, opened)
        assert.are.equal(1429, WowMock.userWaypoint.mapID)
        _G.OpenWorldMap = nil
    end)

    it("the map marker is a pin with the addon's icon in its head, on the map's canvas", function()
        _G.OpenWorldMap = function() end
        _G.WorldMapFrame = WowMock.NewFrame("Frame", "WorldMapFrame")
        local canvas = WowMock.NewFrame("Frame", nil, _G.WorldMapFrame)
        _G.WorldMapFrame.GetCanvas = function() return canvas end
        _G.WorldMapFrame.GetMapID = function() return 1429 end
        ns.ShowOnMap(elwynn, "Marshal")
        local function textureOf(path)
            return WowMock.Find(function(f) return f._kind == "Texture" and f._set.SetTexture and f._set.SetTexture[1] == path end)
        end
        local base = textureOf("Interface\\AddOns\\Completao\\Icons\\PinBase.png")
        local icon = textureOf("Interface\\AddOns\\Completao\\Icons\\Completao.png")
        assert.is_not_nil(base)
        assert.is_not_nil(icon)
        assert.are.equal(base._parent, icon._parent) -- the icon sits on the pin
        local holder = WowMock.Find(function(f) return f._scripts.OnUpdate ~= nil and f._parent == canvas end)
        holder._scripts.OnUpdate(holder)
        assert.are.equal(1, holder:GetAlpha())
        _G.WorldMapFrame.GetMapID = function() return 36 end -- another map is showing
        holder._scripts.OnUpdate(holder)
        assert.are.equal(0, holder:GetAlpha())
        _G.OpenWorldMap = nil
    end)
end)
