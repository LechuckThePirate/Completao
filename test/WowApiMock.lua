-- Simulation of the game's API for the tests (busted or test/busted.lua). It doesn't try to be complete:
-- it covers what the addon uses. Frames are objects that accept any method: Set* stores its arguments
-- (in frame._set), Get*/Is* return what was stored or a sensible value, Create* creates children.
-- The "game" state lives in WowMock: level, faction, quests done and in the log, etc.
-- Compatible with Lua 5.1 (the game's version and CI's).

WowMock = {}
local unpackArgs = unpack or table.unpack -- luacheck: ignore 143 (Lua 5.1 lacks it; 5.2+ has it)

local function resetState()
    WowMock.level = 20
    WowMock.faction = "Alliance"
    WowMock.race = { "Human", "Human", 1 }
    WowMock.class = { "Mage", "MAGE", 8 }
    WowMock.done = {}          -- [questID] = true: completed
    WowMock.onQuest = {}       -- [questID] = true: in the log
    WowMock.titles = {}        -- [questID] = the client's title
    WowMock.objectives = {}    -- [questID] = { { text, finished, numFulfilled, numRequired } }
    WowMock.readyForTurnIn = {}
    WowMock.log = {}           -- quest log entries: { isHeader, title, questID, level }
    WowMock.items = {}         -- [itemID] = { name, link, quality, icon, classID, subclassID, typeName, subName }
    WowMock.cursor = { 0, 0 }
    WowMock.speed = 0
    WowMock.printed = {}
    WowMock.timers = {}
    WowMock.frames = {}
    WowMock.hooks = {}
    WowMock.selectedQuest = 0
    WowMock.maps = {}          -- [uiMapID] = { name, mapType }: the client's maps
end
resetState()
WowMock.Reset = resetState

-- Timers: run immediately by default (tests don't wait).
C_Timer = { After = function(_, f) f() end, NewTicker = function() return { Cancel = function() end } end }

---------------------------------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------------------------------
local frameMethods = {}

local function fire(self, name, ...)
    local s = self._scripts[name]
    if s then s(self, ...) end
    for _, h in ipairs(self._hooks[name] or {}) do h(self, ...) end
end
WowMock.Fire = fire

function frameMethods:SetScript(name, f) self._scripts[name] = f end
function frameMethods:GetScript(name) return self._scripts[name] end
function frameMethods:HookScript(name, f)
    self._hooks[name] = self._hooks[name] or {}
    table.insert(self._hooks[name], f)
end
function frameMethods:Show()
    local was = self._shown
    self._shown = true
    if not was then fire(self, "OnShow") end
end
function frameMethods:Hide()
    local was = self._shown
    self._shown = false
    if was then fire(self, "OnHide") end
end
function frameMethods:SetShown(v) if v then self:Show() else self:Hide() end end
function frameMethods:IsShown() return self._shown end
function frameMethods:IsVisible()
    local f = self
    while f do
        if not f._shown then return false end
        f = f._parent
    end
    return true
end
function frameMethods:GetParent() return self._parent end
function frameMethods:SetText(s) self._text = s end
function frameMethods:GetText() return self._text end
function frameMethods:SetFormattedText(fmt, ...) self._text = fmt:format(...) end
function frameMethods:GetStringWidth() return #(self._text or "") * 6 end
function frameMethods:GetStringHeight() return 14 end
function frameMethods:SetChecked(v) self._checked = v and true or false end
function frameMethods:GetChecked() return self._checked end
function frameMethods:SetEnabled(v) self._enabled = v and true or false end
function frameMethods:Enable() self._enabled = true end
function frameMethods:Disable() self._enabled = false end
function frameMethods:IsEnabled() return self._enabled ~= false end
function frameMethods:SetAlpha(a) self._alpha = a end
function frameMethods:GetAlpha() return self._alpha or 1 end
function frameMethods:SetSize(w, h) self._w, self._h = w, h end
function frameMethods:SetWidth(w) self._w = w end
function frameMethods:SetHeight(h) self._h = h end
function frameMethods:GetWidth() return self._w or 100 end
function frameMethods:GetHeight() return self._h or 20 end
function frameMethods:GetSize() return self:GetWidth(), self:GetHeight() end
function frameMethods:SetFrameLevel(l) self._level = l end
function frameMethods:GetFrameLevel() return self._level or 1 end
function frameMethods:SetScale(s) self._scale = s end
function frameMethods:GetScale() return self._scale or 1 end
function frameMethods:GetEffectiveScale() return 1 end
function frameMethods:SetPoint(...) self._points = self._points or {}; table.insert(self._points, { ... }); self._set.SetPoint = { ... } end
function frameMethods:ClearAllPoints() self._points = {} end
function frameMethods:GetPoint(i) local p = self._points and self._points[i or 1]; if p then return unpackArgs(p) end end
function frameMethods:GetNumPoints() return self._points and #self._points or 0 end
function frameMethods:GetLeft() return 0 end
function frameMethods:GetTop() return 0 end
function frameMethods:GetRight() return self:GetWidth() end
function frameMethods:GetBottom() return 0 end
function frameMethods:GetCenter() return 100, 100 end
function frameMethods:GetHorizontalScroll() return self._hs or 0 end
function frameMethods:GetVerticalScroll() return self._vs or 0 end
function frameMethods:SetHorizontalScroll(v) self._hs = v end
function frameMethods:SetVerticalScroll(v) self._vs = v end
function frameMethods:IsMouseOver() return self._mouseOver or false end
function frameMethods:GetFontString() self._fontString = self._fontString or WowMock.NewFrame("FontString", nil, self); return self._fontString end
function frameMethods:GetNormalTexture() self._normal = self._normal or WowMock.NewFrame("Texture", nil, self); return self._normal end
function frameMethods:GetHighlightTexture() self._highlight = self._highlight or WowMock.NewFrame("Texture", nil, self); return self._highlight end
function frameMethods:GetThumbTexture() self._thumb = self._thumb or WowMock.NewFrame("Texture", nil, self); return self._thumb end
function frameMethods:Click(...) fire(self, "OnClick", ...) end
function frameMethods:GetObjectType() return self._kind end

local function methodFor(self, k)
    if frameMethods[k] then return frameMethods[k] end
    -- only methods (they start with a verb); an undefined field or child (TitleContainer, CloseButton...)
    -- is nil, as in the game
    if type(k) ~= "string" then return nil end
    local verbs = { "Set", "Get", "Is", "Has", "Can", "Create", "Register", "Unregister", "Enable", "Disable",
        "Start", "Stop", "Lock", "Unlock", "Raise", "Lower", "Play", "Add", "Clear", "Hook", "Adjust", "Update" }
    local isMethod = false
    for _, v in ipairs(verbs) do
        if k:sub(1, #v) == v and (k:len() == #v or k:sub(#v + 1, #v + 1):match("%u")) then isMethod = true break end
    end
    if not isMethod then return nil end
    if k:match("^Create") then
        return function(owner, ...)
            local kind = k:sub(7)
            if kind == "Line" or kind == "Texture" or kind == "FontString" or kind == "MaskTexture" or kind == "AnimationGroup" then
                return WowMock.NewFrame(kind, nil, owner)
            end
            return WowMock.NewFrame(kind, nil, owner)
        end
    end
    if k:match("^Set") then
        return function(owner, ...) owner._set[k] = { ... } end
    end
    if k:match("^Get") then
        return function(owner) local v = owner._set["S" .. k:sub(2)]; if v then return unpackArgs(v) end end
    end
    if k:match("^Is") or k:match("^Has") or k:match("^Can") then return function() return false end end
    -- the rest (Register*, Enable*, Start*, Stop*, Play, Lock*, Raise...): do nothing
    return function() end
end

function WowMock.NewFrame(kind, name, parent, template)
    local f = { _kind = kind, _name = name, _parent = parent, _template = template, _scripts = {}, _hooks = {},
        _set = {}, _shown = true }
    setmetatable(f, { __index = function(t, k) return methodFor(t, k) end })
    table.insert(WowMock.frames, f)
    if name then _G[name] = f end
    return f
end

CreateFrame = function(kind, name, parent, template)
    if WowMock.missingTemplates and template and WowMock.missingTemplates[template] then
        error("template no disponible: " .. template)
    end
    return WowMock.NewFrame(kind, name, parent, template)
end

-- Finds created frames: by a predicate, or the first with that text.
function WowMock.Find(pred)
    for _, f in ipairs(WowMock.frames) do
        if pred(f) then return f end
    end
end
function WowMock.FindAll(pred)
    local list = {}
    for _, f in ipairs(WowMock.frames) do
        if pred(f) then list[#list + 1] = f end
    end
    return list
end
function WowMock.FindByText(text)
    return WowMock.Find(function(f) return f._text == text end)
end
function WowMock.FindButton(textPart)
    return WowMock.Find(function(f)
        return type(f._text) == "string" and f._text:find(textPart, 1, true) and f._scripts.OnClick ~= nil
    end)
end

UIParent = WowMock.NewFrame("Frame", "UIParent")
Minimap = WowMock.NewFrame("Frame", "Minimap")
WorldMapFrame = WowMock.NewFrame("Frame", "WorldMapFrame")
WorldMapFrame._shown = false
GameTooltip = WowMock.NewFrame("GameTooltip", "GameTooltip")
GameTooltip_Hide = function() end
UISpecialFrames = {}

---------------------------------------------------------------------------------------------------
-- The game's functions and tables
---------------------------------------------------------------------------------------------------
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
tinsert = table.insert
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
hooksecurefunc = function(name, f)
    WowMock.hooks[name] = WowMock.hooks[name] or {}
    table.insert(WowMock.hooks[name], f)
    local original = _G[name]
    _G[name] = function(...)
        local r = { original(...) }
        for _, h in ipairs(WowMock.hooks[name]) do h(...) end
        return unpackArgs(r)
    end
end
print = function(...)
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    table.insert(WowMock.printed, table.concat(parts, " "))
end
issecretvalue = nil

GetLocale = function() return WowMock.locale or "enUS" end
UnitLevel = function() return WowMock.level end
UnitFactionGroup = function() return WowMock.faction end
UnitRace = function() return unpackArgs(WowMock.race) end
UnitClass = function() return unpackArgs(WowMock.class) end
UnitName = function() return "Tester" end
GetUnitSpeed = function() return WowMock.speed end
GetCursorPosition = function() return WowMock.cursor[1], WowMock.cursor[2] end
IsShiftKeyDown = function() return WowMock.shift or false end
IsControlKeyDown = function() return WowMock.ctrl or false end
GetRealmName = function() return "Realm" end
BreakUpLargeNumbers = function(n) return tostring(n) end
GetCoinTextureString = function(c) return c .. "c" end
HandleModifiedItemClick = function(link) WowMock.linked = link end
GetQuestGreenRange = function() return 8 end

QuestDifficultyColors = {
    trivial = { r = 0.5, g = 0.5, b = 0.5 }, standard = { r = 0.25, g = 0.75, b = 0.25 },
    difficult = { r = 1, g = 1, b = 0 }, verydifficult = { r = 1, g = 0.5, b = 0.25 },
    impossible = { r = 1, g = 0.1, b = 0.1 },
}
-- like the game: grey when below the green range; red 5 or more levels above
GetQuestDifficultyColor = function(level)
    local d = level - WowMock.level
    if d >= 5 then return QuestDifficultyColors.impossible end
    if d >= 3 then return QuestDifficultyColors.verydifficult end
    if d >= -2 then return QuestDifficultyColors.difficult end
    if level <= WowMock.level - GetQuestGreenRange() then return QuestDifficultyColors.trivial end
    return QuestDifficultyColors.standard
end
ITEM_QUALITY_COLORS = { [0] = { r = 0.6, g = 0.6, b = 0.6 }, [1] = { r = 1, g = 1, b = 1 },
    [2] = { r = 0.1, g = 1, b = 0 }, [3] = { r = 0, g = 0.44, b = 0.87 }, [4] = { r = 0.64, g = 0.21, b = 0.93 } }
LOCALIZED_CLASS_NAMES_MALE = { MAGE = "Mage", WARRIOR = "Warrior", PALADIN = "Paladin" }

C_QuestLog = {
    IsQuestFlaggedCompleted = function(id) return WowMock.done[id] == true end,
    IsOnQuest = function(id) return WowMock.onQuest[id] == true end,
    GetTitleForQuestID = function(id) return WowMock.titles[id] end,
    RequestLoadQuestByID = function() end,
    GetQuestObjectives = function(id) return WowMock.objectives[id] or {} end,
    ReadyForTurnIn = function(id) return WowMock.readyForTurnIn[id] == true end,
    GetNumQuestLogEntries = function() return #WowMock.log end,
    GetInfo = function(i) return WowMock.log[i] end,
    GetLogIndexForQuestID = function(id)
        for i, e in ipairs(WowMock.log) do if e.questID == id then return i end end
    end,
    GetSelectedQuest = function() return WowMock.selectedQuest end,
    SetSelectedQuest = function(id) WowMock.selectedQuest = id end,
}
C_Map = {
    GetAreaInfo = function(id) return "Area" .. id end,
    GetMapInfo = function(id) return WowMock.maps[id] end,
    GetBestMapForUnit = function() return nil end,
    CanSetUserWaypointOnMap = function() return true end,
    SetUserWaypoint = function(p) WowMock.userWaypoint = p end,
}
UiMapPoint = { CreateFromCoordinates = function(m, x, y) return { mapID = m, x = x, y = y } end }
C_SuperTrack = { SetSuperTrackedUserWaypoint = function() end }
Enum = { UIMapType = { Zone = 3, Continent = 2, World = 1 } }
C_Item = {
    GetItemInfo = function(id)
        local i = WowMock.items[id]
        if i and i.name then return i.name, i.link or ("|Hitem:" .. id .. "|h"), i.quality or 1 end
    end,
    GetItemIconByID = function(id) return 1000 + id end,
    GetItemInfoInstant = function(id)
        local i = WowMock.items[id]
        if i then return id, i.typeName, i.subName, "", i.icon or 1000, i.classID, i.subclassID end
    end,
    RequestLoadItemDataByID = function(id) WowMock.requestedItems = (WowMock.requestedItems or 0) + 1 end,
}
C_AddOns = { GetAddOnMetadata = function(_, key) return key == "Version" and "0.0.0-test" or nil end }
C_Reputation = { GetFactionDataByID = function(id) return id == 72 and { name = "Stormwind" } or nil end }
C_CreatureInfo = { GetRaceInfo = function(id) return { raceName = "Race" .. id } end }
C_Texture = { GetAtlasInfo = function() return nil end }
SlashCmdList = {}
