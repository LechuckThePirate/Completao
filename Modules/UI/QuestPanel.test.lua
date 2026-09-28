dofile("setupTests.lua")

describe("QuestPanel", function()
    local ns, waypoints, maps

    local function panelText()
        local t = WowMock.Find(function(f) return type(f._text) == "string" and f._text:find("|cffffd100Requirements|r", 1, true) end)
        return t and t._text or ""
    end
    local function wayButton()
        return WowMock.Find(function(f) return type(f._text) == "string" and f._text:find("^Waypoint: ") and f._scripts.OnClick end)
    end

    before_each(function()
        WowMock.Reset()
        ns = OpenAddon("vc")
        waypoints, maps = {}, {}
        ns.SetWaypoint = function(loc, title) waypoints[#waypoints + 1] = title .. "@" .. tostring(loc.x) end
        ns.ShowOnMap = function(loc, title) maps[#maps + 1] = title .. "@" .. tostring(loc.x) end
        ns.CanWaypoint = function(loc) return loc ~= nil and loc.x ~= nil end
        ns.CanShowMap = ns.CanWaypoint
    end)

    describe("recompensas", function()
        before_each(function()
            WowMock.items[159] = { name = "Refreshing Spring Water", quality = 1 }
            ns.REWARDS = { [166] = { choice = { { 4604, 5 }, 159, 2041 }, items = { 6087 }, money = 25, xp = 1050,
                rep = { { 72, 100 }, { 999, -25 } } } }
            ns.Detail_Show(ns.FindQuestDef(166))
        end)

        local function itemButtons()
            local list = {}
            for _, f in ipairs(WowMock.frames) do if f.itemID and f._shown and f.count then list[f.itemID] = f end end
            return list
        end

        it("un boton por objeto, con cantidad y nombre del cliente", function()
            local items = itemButtons()
            assert.is_not_nil(items[4604]); assert.is_not_nil(items[159]); assert.is_not_nil(items[2041]); assert.is_not_nil(items[6087])
            assert.are.equal(5, items[4604].count:GetText())
            assert.are.equal("", items[159].count:GetText())
            assert.are.equal("Refreshing Spring Water", items[159].name:GetText())
        end)

        it("pide al cliente los objetos que aun no conoce", function()
            assert.are.equal("Item 4604", itemButtons()[4604].name:GetText())
            assert.is_true((WowMock.requestedItems or 0) >= 3)
        end)

        it("tooltip del objeto y Shift+clic para enlazarlo", function()
            local b = itemButtons()[159]
            local shown
            GameTooltip.SetItemByID = function(_, id) shown = id end
            b._scripts.OnEnter(b)
            b:Click()
            assert.are.equal(159, shown)
            assert.matches("item:159", WowMock.linked)
        end)

        it("dinero, experiencia y reputacion (con faccion desconocida)", function()
            local texts = {}
            for _, f in ipairs(WowMock.frames) do if type(f._text) == "string" then texts[#texts + 1] = f._text end end
            local all = table.concat(texts, "\n")
            assert.matches("Money: 25c", all)
            assert.matches("Experience: 1050", all)
            assert.matches("Reputation: %+100 Stormwind", all)
            assert.matches("Reputation: %-25 Faction 999", all)
        end)
    end)

    describe("pasos y waypoint", function()
        local q

        before_each(function()
            ns.entries.vc.entrance = { area = 40, x = 42.5, y = 71.7 }
            q = { id = 900001, name = "Test Quest", entryId = "z12", dungeon = "vc", requires = { 900000 },
                start = { npc = "Giver", area = 12, x = 10, y = 11 }, finish = { npc = "Ender", area = 12, x = 20, y = 21 },
                steps = { { name = "Tough Wolf Meat", area = 12, x = 30, y = 31 }, { name = "Head of VanCleef", area = 1581 } } }
        end)

        it("la lista de pasos va detras del objetivo", function()
            q.objective = "Do things."
            ns.Detail_Show(q)
            local text = panelText()
            assert.is_truthy(text:find("Objective", 1, true) < text:find("Steps", 1, true))
            assert.matches("Start: Giver", text)
        end)

        it("sin empezar: el boton lleva al requisito que falta", function()
            ns.Detail_Show(q)
            assert.are.equal("Waypoint: Requirement: Quest 900000", wayButton():GetText())
        end)

        it("en curso: al primer objetivo sin terminar, con el progreso en la lista", function()
            WowMock.done[900000] = true
            WowMock.onQuest[900001] = true
            WowMock.objectives[900001] = { { text = "Tough Wolf Meat: 3/8", finished = false, numFulfilled = 3, numRequired = 8 } }
            ns.Detail_Show(q)
            assert.are.equal("Waypoint: Tough Wolf Meat", wayButton():GetText())
            assert.matches("Tough Wolf Meat  3/8", panelText())
            wayButton():Click()
            assert.are.equal("Tough Wolf Meat@30", waypoints[#waypoints])
        end)

        it("un paso dentro de una mazmorra lleva a su entrada", function()
            WowMock.done[900000] = true
            WowMock.onQuest[900001] = true
            WowMock.objectives[900001] = {
                { text = "Tough Wolf Meat: 8/8", finished = true, numFulfilled = 8, numRequired = 8 },
                { text = "Head of VanCleef: 0/1", finished = false, numFulfilled = 0, numRequired = 1 },
            }
            ns.Detail_Show(q)
            wayButton():Click()
            assert.are.equal("Head of VanCleef@42.5", waypoints[#waypoints])
            assert.is_not_nil(WowMock.FindButton("Show entrance"))
        end)

        it("elegir otro paso en el desplegable pone el waypoint y se mantiene al refrescar", function()
            ns.Detail_Show(q)
            local arrow = WowMock.Find(function(f) return f._text == "v" and f._scripts.OnClick end)
            arrow:Click()
            local option = WowMock.Find(function(f)
                return f.text and type(f.text._text) == "string" and f.text._text:find("Start: Giver", 1, true) and f._scripts.OnClick
            end)
            option:Click()
            assert.are.equal("Start: Giver@10", waypoints[#waypoints])
            ns.Detail_Refresh()
            assert.are.equal("Waypoint: Start: Giver", wayButton():GetText())
        end)
    end)

    it("el boton Abrir mision solo con la quest en el registro", function()
        local q = ns.FindQuestDef(166)
        ns.Detail_Show(q)
        assert.is_false(WowMock.FindButton("Open quest"):IsShown())
        WowMock.onQuest[166] = true
        ns.Detail_Refresh()
        assert.is_true(WowMock.FindButton("Open quest"):IsShown())
    end)

    it("la descripcion larga va al final, si la hay", function()
        ns.Detail_Show({ id = 1, name = "x", desc = "Long story" })
        local text = panelText()
        assert.is_truthy(text:find("Description", 1, true))
        assert.are.equal(#text - #"Long story" + 1, text:find("Long story", 1, true))
    end)
end)
