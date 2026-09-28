dofile("setupTests.lua")

describe("Waypoints", function()
    local ns
    local elwynn = { npc = "Marshal", area = 12, x = 42.1, y = 65.9 }

    before_each(function()
        WowMock.Reset()
        WowMock.maps[1429] = { name = "Area12", mapType = Enum.UIMapType.Zone }
        ns = LoadAddon({ files = { "Modules/Map/Waypoints.lua" } })
        ns.Print = function(...) WowMock.lastPrint = table.concat({ ... }, " ") end
        TomTom = nil
    end)

    it("convierte la zona de una ubicacion en el mapa del cliente por su nombre", function()
        assert.are.equal(1429, ns.ResolveZone({ area = 12 }))
        assert.is_nil(ns.ResolveZone({ area = 999 }))
    end)

    it("hace falta coordenada para un waypoint; para ver el mapa basta la zona", function()
        assert.is_true(ns.CanWaypoint(elwynn))
        assert.is_false(ns.CanWaypoint({ area = 12 }))
        assert.is_true(ns.CanShowMap({ area = 12 }))
        assert.is_false(ns.CanShowMap({ area = 999 }))
    end)

    it("con TomTom, pone el waypoint en TomTom", function()
        local got
        TomTom = { AddWaypoint = function(_, map, x, y, opts) got = { map, x, y, opts.title } end }
        assert.is_true(ns.SetWaypoint(elwynn, "Marshal"))
        assert.are.equal(1429, got[1])
        assert.near(0.421, got[2], 1e-9)
        assert.near(0.659, got[3], 1e-9)
        assert.are.equal("Marshal", got[4])
    end)

    it("sin TomTom, usa el waypoint del juego", function()
        assert.is_true(ns.SetWaypoint(elwynn, "Marshal"))
        assert.are.equal(1429, WowMock.userWaypoint.mapID)
        assert.near(0.421, WowMock.userWaypoint.x, 1e-9)
    end)

    it("sin sitio avisa y no pone nada", function()
        assert.is_false(ns.SetWaypoint({ area = 12 }, "x"))
        assert.matches("No map location", WowMock.lastPrint)
    end)

    it("ver en el mapa abre el mapa de la zona y marca el punto", function()
        local opened
        OpenWorldMap = function(map) opened = map end
        ns.ShowOnMap(elwynn, "Marshal")
        assert.are.equal(1429, opened)
        assert.are.equal(1429, WowMock.userWaypoint.mapID)
        OpenWorldMap = nil
    end)
end)
