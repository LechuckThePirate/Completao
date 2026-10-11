local _, ns = ...
local L = ns.L

-- Focus window: a small floating window for the one quest being focused on (right click on a quest in Tracked Quests,
-- or the Focus button in a quest's details). It shows the quest's status icon ("?" ready to turn in, "..."
-- in progress) and title in its difficulty color, and under it the objectives with their progress
-- ("Boars 0/5"); done ones go grey and struck through. Once every objective is done they are replaced by
-- "Turn in <quest> (<npc>)". The waypoint goes to the step to do next (the nearest objective left, or the
-- turn-in) and moves by itself as objectives are completed. When the quest is turned in (or abandoned) the
-- window stays, saying no quest is focused and how to choose another; its X closes it. It can be dragged
-- ("Focused Quest" title bar; the place is saved; a padlock there locks it in place). Clicking an objective sets the waypoint on it; clicking the
-- rest of the window (or the hint, when no quest is focused) opens the main window on the tracked quests; a
-- right click anywhere on it opens a menu to choose the quest to focus (Auto, or one of the tracked quests by
-- distance; inside a dungeon, only the quests done in it). In combat the window stops taking the mouse, so clicks reach the world.
local PAD, LINE_H, HEADER_H, ICON = 8, 16, 20, 16
local TITLE_H = 18 -- the title bar
local LOCK_SIZE = 16 -- the padlock in it
local TOP = TITLE_H + 6 -- where the quest's icon and title start
local WIDTH_MIN, WIDTH_MAX = 200, 420
local CHECK_W = 16 -- room for the check before a done objective
local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local COLORS = { done = "ff808080", target = "ffffd100", todo = "ffffffff", hint = "ff9d9d9d" }

local frame, lines = nil, {}
local ready = false   -- the quest log is loaded (see Focus_Init): before, a quest not in it isn't gone yet
local lastSignature   -- what the waypoint was last worked out for
local mouseOn = true  -- false in combat (click-through)
local idle = false    -- no quest focused but the window stays, saying so (the quest was turned in or abandoned)

function ns.Focus_Quest()
    return ns.char and ns.char.focusQuest
end

local function inCombat()
    if UnitAffectingCombat and UnitAffectingCombat("player") then return true end
    return InCombatLockdown and InCombatLockdown() and true or false
end

-- The quest as the addon knows it; one only in the game's log (not in the data) gets what the log says.
local function questDef(id)
    local def = ns.FindQuestDef(id)
    if def then return def end
    local q = { id = id, name = C_QuestLog.GetTitleForQuestID(id) or ("Quest " .. id) }
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        if info and not info.isHeader and info.questID == id then
            q.name, q.level = info.title or q.name, info.level
            break
        end
    end
    return q
end

-- The step to put the waypoint on: the turn-in once the quest is ready, else the nearest objective left
-- that has a spot (the first one when the distance can't be told). nil if none has a spot.
function ns.Focus_PickStep(steps, isReady)
    if isReady then
        local last = #steps
        return ns.CanWaypoint(steps[last].loc) and last or nil
    end
    local best, bestDist
    for i, s in ipairs(steps) do
        if s.kind == "obj" and not s.done and ns.CanWaypoint(s.loc) then
            local d = ns.DistanceTo(s.loc)
            if not best or (d and (not bestDist or d < bestDist)) then best, bestDist = i, d end
        end
    end
    return best
end

-- Click-through in combat: the window, its button and the objectives stop taking the mouse, so clicks reach
-- the game world.
local function applyMouse(combat)
    mouseOn = not combat
    if not frame then return end
    local targets = { frame, frame.close, frame.lock }
    for _, line in ipairs(lines) do targets[#targets + 1] = line.button end
    for _, f in ipairs(targets) do
        f:EnableMouse(mouseOn)
        if combat and GameTooltip:IsOwned(f) then GameTooltip:Hide() end
    end
    if combat then
        frame:StopMovingOrSizing()
        ns.PopupMenu_Hide()
    end
end

local function savePosition()
    local point, _, relPoint, x, y = frame:GetPoint()
    ns.char.focusWindow = { point = point, relPoint = relPoint, x = x, y = y }
end

local function applyPosition()
    if not frame then return end
    local saved = ns.char.focusWindow
    frame:ClearAllPoints()
    if saved then
        frame:SetPoint(saved.point, UIParent, saved.relPoint, saved.x, saved.y)
    else
        frame:SetPoint("RIGHT", UIParent, "RIGHT", -60, 120)
    end
end

-- The padlock's picture says whether the window is locked.
local function updateLock()
    if not (frame and frame.lock) then return end
    local texture = ns.char.focusLocked and "Interface\\Buttons\\LockButton-Locked-Up"
        or "Interface\\Buttons\\LockButton-Unlocked-Up"
    frame.lock:SetNormalTexture(texture)
    frame.lock:SetPushedTexture(texture)
end

function ns.Focus_ApplySettings()
    applyPosition()
    updateLock()
end

function ns.Focus_ResetPosition()
    ns.char.focusWindow = nil
    applyPosition()
end

local function create()
    frame = CreateFrame("Frame", "CompletaoFocusFrame", UIParent, "BackdropTemplate")
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetBackdrop(BACKDROP)
    frame:SetBackdropColor(0, 0, 0, 0.75)
    frame:SetBackdropBorderColor(0.6, 0.5, 0.1, 1)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    -- a click on the window (not a drag) opens the main window on the tracked quests; dragging also ends in a
    -- mouse-up, so that one doesn't count
    local dragged = false
    frame:SetScript("OnMouseDown", function() dragged = false end)
    frame:SetScript("OnDragStart", function(self)
        dragged = true -- (even locked: trying to drag it isn't a click)
        if not ns.char.focusLocked then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
    end)
    frame:SetScript("OnMouseUp", function(_, which)
        if which == "LeftButton" and not dragged then
            ns.PopupMenu_Hide()
            ns.UI_OpenTracked()
            -- with a quest focused, its details are open under the table, as after a click on its row
            local id = ns.Focus_Quest()
            if id then ns.Detail_Show(questDef(id)) end
        elseif which == "RightButton" then
            ns.Focus_ChooseQuest(frame)
        end
    end)
    frame:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:AddLine(L["Click to open the tracked quests."], 0.5, 0.8, 1)
        GameTooltip:AddLine(L["Right-click to choose the quest to focus."], 0.5, 0.8, 1)
        GameTooltip:Show()
    end)
    frame:SetScript("OnLeave", GameTooltip_Hide)

    -- title bar: what the window is, and the close button
    frame.bar = frame:CreateTexture(nil, "BACKGROUND")
    frame.bar:SetPoint("TOPLEFT", 3, -3)
    frame.bar:SetPoint("TOPRIGHT", -3, -3)
    frame.bar:SetHeight(TITLE_H)
    frame.bar:SetColorTexture(0.25, 0.2, 0.05, 0.9)
    frame.barText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.barText:SetPoint("CENTER", frame.bar, "CENTER", 0, 0)
    frame.barText:SetText(L["Focused Quest"])

    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetSize(ICON, ICON)
    frame.icon:SetPoint("TOPLEFT", PAD, -TOP)
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("LEFT", frame.icon, "RIGHT", 4, 0)
    frame.title:SetJustifyH("LEFT")
    frame.title:SetWordWrap(false)

    local okClose, close = pcall(CreateFrame, "Button", nil, frame, "UIPanelCloseButton")
    if not okClose or not close then close = CreateFrame("Button", nil, frame) end
    close:SetSize(TITLE_H + 6, TITLE_H + 6)
    close:SetPoint("TOPRIGHT", 1, 1)
    close:SetScript("OnClick", function() ns.Focus_Clear() end) -- closes the window for good
    frame.close = close

    -- padlock at the top left: locked, the window can't be moved (everything else works as always)
    local lock = CreateFrame("Button", nil, frame)
    lock:SetSize(LOCK_SIZE, LOCK_SIZE)
    lock:SetPoint("TOPLEFT", 5, -4)
    lock:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    lock:SetScript("OnClick", function()
        ns.char.focusLocked = (not ns.char.focusLocked) or nil
        updateLock()
        if GameTooltip:IsOwned(lock) then lock:GetScript("OnEnter")(lock) end
    end)
    lock:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine(ns.char.focusLocked and L["Unlock position"] or L["Lock position"], 1, 1, 1)
        GameTooltip:Show()
    end)
    lock:SetScript("OnLeave", GameTooltip_Hide)
    frame.lock = lock
    updateLock()

    applyPosition()
    applyMouse(inCombat())
    frame:Hide()
end

-- A line of the list (created as needed): a button with the check, the text and the strike-through line over
-- it. Clicking it sets the waypoint on its step (or opens the map on its zone when the spot isn't known).
local function getLine(i)
    local line = lines[i]
    if line then return line end
    line = {}
    local button = CreateFrame("Button", nil, frame)
    button:SetHeight(LINE_H)
    button:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
    button:EnableMouse(mouseOn)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:SetScript("OnClick", function(self, which)
        if which == "RightButton" then ns.Focus_ChooseQuest(frame) return end
        ns.PopupMenu_Hide()
        local step = self.step
        if step and step.opens then ns.UI_OpenTracked() return end -- the "no quest focused" hint
        if not (step and step.loc) then return end
        if ns.CanWaypoint(step.loc) then
            ns.SetWaypoint(step.loc, step.label, step.tag)
            ns.Focus_Refresh()
        else
            ns.ShowOnMap(step.loc, step.label)
        end
    end)
    button:SetScript("OnEnter", function(self)
        if not (self.step and self.step.loc) then return end
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        GameTooltip:AddLine(ns.CanWaypoint(self.step.loc) and L["Click to set the waypoint."]
            or L["Click to show it on the map."], 0.5, 0.8, 1)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", GameTooltip_Hide)
    line.button = button
    line.check = button:CreateTexture(nil, "ARTWORK")
    line.check:SetSize(CHECK_W - 4, CHECK_W - 4)
    line.check:SetPoint("LEFT", button, "LEFT", 0, 0)
    line.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    line.text = button:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line.text:SetPoint("LEFT", button, "LEFT", CHECK_W, 0)
    line.text:SetJustifyH("LEFT")
    line.text:SetWordWrap(false)
    line.strike = button:CreateTexture(nil, "OVERLAY")
    line.strike:SetHeight(1)
    line.strike:SetColorTexture(0.5, 0.5, 0.5, 1)
    line.strike:SetPoint("LEFT", line.text, "LEFT", 0, 0)
    lines[i] = line
    return line
end

local function setLine(i, l)
    local line = getLine(i)
    line.button:ClearAllPoints()
    line.button:SetPoint("TOPLEFT", frame, "TOPLEFT", PAD, -(TOP + HEADER_H + 4 + (i - 1) * LINE_H))
    line.button.step = l
    line.check:SetShown(l.struck)
    line.text:SetText(("|c%s%s|r"):format(COLORS[l.kind], l.text))
    line.strike:SetShown(l.struck)
    line.button:Show()
    return line
end

-- What the lines say: the objectives, or the turn-in once the quest is ready. Each carries its step, for the
-- click; the one the waypoint is on is in gold.
local function buildLines(q, steps, isReady)
    local out = {}
    local function place(step) return step.loc or (step.area and { area = step.area }) or nil end
    local function canShow(loc) return loc and ns.CanShowMap(loc) and loc or nil end
    if isReady then
        local finish = steps[#steps]
        local npc = finish.loc and finish.loc.npc
        local name = ns.QuestTitle(q.id, q.name)
        out[1] = { text = npc and L["Turn in %s (%s)"]:format(name, npc) or L["Turn in %s"]:format(name), kind = "target",
            struck = false, loc = canShow(place(finish)), label = finish.label, tag = q.id .. ":" .. #steps }
        return out
    end
    local focusTag = ns.FocusTag()
    for i, s in ipairs(steps) do
        if s.kind == "obj" then
            local tag = q.id .. ":" .. i
            out[#out + 1] = {
                text = s.label .. (s.progress and (" " .. s.progress) or ""),
                kind = s.done and "done" or tag == focusTag and "target" or "todo", struck = s.done and true or false,
                loc = canShow(place(s)), label = s.label, tag = tag,
            }
        end
    end
    return out
end

-- Signature of what the waypoint depends on: which objectives are done, and whether the quest is ready.
local function signatureOf(id, steps, isReady)
    local parts = { id, isReady and "R" or "-" }
    for _, s in ipairs(steps) do parts[#parts + 1] = s.done and "1" or "0" end
    return table.concat(parts)
end

-- Puts the waypoint on the step that comes next; only when it may have changed (an objective done, the quest
-- ready...) or when forced, not as the player moves: the waypoint isn't redone under their feet, and a
-- waypoint they set by hand stays until then.
local function retarget(q, steps, target, force, isReady)
    local signature = signatureOf(q.id, steps, isReady)
    if not force and signature == lastSignature then return end
    lastSignature = signature
    local s = target and steps[target]
    if s and s.loc then ns.SetWaypoint(s.loc, s.label, q.id .. ":" .. target, true) end
end

-- Draws the window: the header (status icon, or none, and the title in a color) and the lines under it.
local function draw(iconKind, title, r, g, b, content)
    if not frame then create() end
    frame.title:ClearAllPoints()
    local indent = 0
    if iconKind then
        indent = ICON + 4
        ns.SetQuestStatusIcon(frame.icon, iconKind)
        frame.title:SetPoint("LEFT", frame.icon, "RIGHT", 4, 0)
    else
        frame.icon:Hide()
        frame.title:SetPoint("LEFT", frame, "TOPLEFT", PAD, -(TOP + ICON / 2))
    end
    frame.title:SetText(title)
    frame.title:SetTextColor(r, g, b)

    local width = math.max(indent + frame.title:GetStringWidth(), frame.barText:GetStringWidth() + 2 * (TITLE_H + 6))
    for i, l in ipairs(content) do
        local line = setLine(i, l)
        width = math.max(width, CHECK_W + line.text:GetStringWidth())
    end
    for i = #content + 1, #lines do lines[i].button:Hide() end
    width = math.max(WIDTH_MIN, math.min(WIDTH_MAX, math.ceil(width) + 2 * PAD))
    frame:SetSize(width, TOP + HEADER_H + 4 + #content * LINE_H + PAD)
    frame.title:SetWidth(width - 2 * PAD - indent)
    for i in ipairs(content) do
        local line = lines[i]
        line.button:SetWidth(width - 2 * PAD)
        line.text:SetWidth(width - 2 * PAD - CHECK_W)
        line.strike:SetWidth(math.min(line.text:GetStringWidth(), width - 2 * PAD - CHECK_W))
    end
    frame:Show()
end

-- Nothing focused: the window says so, and how to choose another quest.
local function drawIdle()
    draw(nil, L["No quest focused"], 0.62, 0.62, 0.62, { { text = L["Click to choose another."], kind = "hint", struck = false, opens = true } })
end

-- Autofocus (Preferences): the focus picks its quest by itself, by how near each tracked quest's next step is
-- (its nearest objective left, or the turn-in once it is ready: the step the waypoint goes to). Only quests
-- whose distance can be told count.
--  * Nothing focused: the quest with the nearest objective; with no quest that has an objective to do, the
--    nearest turn-in.
--  * The focused quest is ready to turn in: the tracked quest with the nearest objective or turn-in (its own
--    turn-in too, so it stays when that is the nearest). A quest that was ready when the player focused it by
--    hand is left alone.
--  * The focused quest is still in progress: only a quest just accepted that is a direct turn-in (ready the
--    moment it is taken) and whose turn-in is nearer than what the focused quest needs next takes the focus.
-- Inside a dungeon or raid only its own quests (the ones done inside it) are candidates.
-- Looked at when the quest log changes and every few seconds. Closing the window or unfocusing by hand pauses
-- it until the player focuses a quest or switches the setting.
local AUTO_EVERY = 2
local sticky, suspended, picking = {}, false, false
local FRESH_SECONDS = 10 -- how long an accepted quest counts as new (its tracking and state can lag a moment)
local fresh = {}         -- [questId] = GetTime() until which it counts as just accepted

-- Every tracked quest in the log, in log order: { id, def, dist, ready }; `dist` (how far its next step is) is
-- nil when it can't be told. Inside a known dungeon or raid only the quests done in it are listed, for
-- autofocus and the menu alike.
local function trackedQuests()
    local list = {}
    local inside = ns.CurrentInstanceEntry()
    for i = 1, C_QuestLog.GetNumQuestLogEntries() do
        local info = C_QuestLog.GetInfo(i)
        local id = info and not info.isHeader and info.questID
        if id and id > 0 and ns.IsQuestTracked(id) and C_QuestLog.IsOnQuest(id)
            and not C_QuestLog.IsQuestFlaggedCompleted(id) and (not inside or ns.QuestDoneInside(id, inside)) then
            local q = questDef(id)
            local steps = ns.QuestSteps(q)
            local isReady = ns.IsReadyToTurnIn(id)
            local index = ns.Focus_PickStep(steps, isReady)
            local d = index and ns.DistanceTo(steps[index].loc)
            list[#list + 1] = { id = id, def = q, dist = d, ready = isReady }
        end
    end
    return list
end

-- The tracked quests whose distance can be told.
local function trackedCandidates()
    local list = {}
    for _, e in ipairs(trackedQuests()) do
        if e.dist then list[#list + 1] = e end
    end
    return list
end

-- The nearest of the list; `wantReady` true / false keeps only the ones ready to turn in / with objectives left.
local function nearest(list, wantReady)
    local best
    for _, e in ipairs(list) do
        if (wantReady == nil or e.ready == wantReady) and (not best or e.dist < best.dist) then best = e end
    end
    return best
end

-- A just accepted quest, tracked and ready to turn in, whose turn-in is nearer than what the focused quest
-- `cur` needs next (or than nothing, if that can't be told): the nearest such one, or nil.
local function freshTurnIn(cur)
    local now, list, best, bestDist = GetTime(), nil, nil, nil
    for id, untilTime in pairs(fresh) do
        if now > untilTime then
            fresh[id] = nil
        elseif id ~= cur and ns.IsQuestTracked(id) and C_QuestLog.IsOnQuest(id) and ns.IsReadyToTurnIn(id) then
            list = list or trackedCandidates()
            local mine, theirs
            for _, e in ipairs(list) do
                if e.id == cur then mine = e.dist elseif e.id == id then theirs = e.dist end
            end
            if theirs and (not mine or theirs < mine) and (not bestDist or theirs < bestDist) then best, bestDist = id, theirs end
        end
    end
    if best then fresh[best] = nil end
    return best
end

-- The quest autofocus would put the focus on now, or nil to leave it as it is.
function ns.Focus_AutoPick()
    local cur = ns.Focus_Quest()
    if cur then
        if not C_QuestLog.IsOnQuest(cur) then return nil end
        if not ns.IsReadyToTurnIn(cur) then return freshTurnIn(cur) end
        if sticky[cur] then return nil end
        local best = nearest(trackedCandidates())
        return best and best.id ~= cur and best.id or nil
    end
    local list = trackedCandidates()
    local best = nearest(list, false) or nearest(list, true)
    return best and best.id
end

-- "Auto" in the menu: the focus goes, once, to the tracked quest nearest to the character (by what each needs
-- next, as autofocus sees it). Done by hand, so autofocus leaves it be; the Autofocus setting isn't touched.
function ns.Focus_Auto()
    local best = nearest(trackedCandidates())
    if not best then
        ns.Print(L["No tracked quest to go to."])
        return false
    end
    return ns.Focus_Set(best.id)
end

-- Right click on the window: a menu with Auto and, under it, the tracked quests by distance (nearest first;
-- the ones whose distance can't be told last), as in the tracker: "[level]" in the difficulty color, with D
-- (dungeon) or + (elite). The focused one is ticked. Picking one focuses it by hand, so autofocus leaves it be.
local MENU_WIDTH = 280
local CHECK = " |TInterface\\Buttons\\UI-CheckBox-Check:14|t"
function ns.Focus_ChooseQuest(anchor)
    local list = trackedQuests()
    for i, e in ipairs(list) do e.order = i end
    table.sort(list, function(a, b)
        if (a.dist ~= nil) ~= (b.dist ~= nil) then return a.dist ~= nil end
        if a.dist and a.dist ~= b.dist then return a.dist < b.dist end
        return a.order < b.order
    end)
    local cur = ns.Focus_Quest()
    local options = { { name = L["Auto"], color = { 1, 0.82, 0 }, auto = true } }
    for _, e in ipairs(list) do
        local q = e.def
        local r, g, b = ns.QuestLevelColorRGB(q.level or q.minLevel)
        options[#options + 1] = {
            name = ns.QuestStatusIconText(ns.IsReadyToTurnIn(e.id) and "ready" or "progress", 14)
                .. ns.QuestPrefix(q) .. ns.QuestTitle(e.id, q.name) .. (e.id == cur and CHECK or ""),
            color = { r, g, b }, id = e.id,
        }
    end
    ns.PopupMenu(anchor, options, function(opt)
        if opt.auto then ns.Focus_Auto() else ns.Focus_Set(opt.id) end
    end, MENU_WIDTH)
end

local function autoFocus()
    if picking or not ready or suspended or not (ns.char and ns.char.focusAuto) or inCombat() then return false end
    local id = ns.Focus_AutoPick()
    if not id then return false end
    picking = true -- (Focus_Set refreshes, which comes back here)
    local ok = ns.Focus_Set(id, true)
    picking = false
    return ok
end

-- Preferences: the setting was switched.
function ns.Focus_SetAuto(on)
    ns.char.focusAuto = on and true or nil
    suspended = false
    ns.Focus_Refresh()
end

function ns.Focus_Refresh(force)
    if autoFocus() then return end
    local id = ns.Focus_Quest()
    if not id then
        -- nothing focused: the message stays up (after a turn-in, or with autofocus on and nothing it can pick,
        -- like quests with no known spot) for the player to click and choose
        local autoWaiting = ready and not suspended and ns.char and ns.char.focusAuto
        if idle or autoWaiting then drawIdle() elseif frame then frame:Hide() end
        return
    end
    if C_QuestLog.IsQuestFlaggedCompleted(id) then
        ns.Focus_Clear(true) -- turned in
        return
    end
    if not C_QuestLog.IsOnQuest(id) then
        -- abandoned, or the log isn't loaded yet
        if ready then ns.Focus_Clear(true) elseif frame then frame:Hide() end
        return
    end

    local q = questDef(id)
    local steps = ns.QuestSteps(q)
    local isReady = ns.IsReadyToTurnIn(id)
    local target = ns.Focus_PickStep(steps, isReady)
    retarget(q, steps, target, force, isReady)
    local r, g, b = ns.QuestLevelColorRGB(q.level or q.minLevel)
    draw(isReady and "ready" or "progress", ns.QuestPrefix(q) .. ns.QuestTitle(id, q.name), r, g, b,
        buildLines(q, steps, isReady))
end

-- "Focusing here sets Blizzard's tracker" (Preferences, on unless switched off): a quest focused here, by the
-- player or by autofocus, becomes the game's super tracked quest too. Called with the focus already changed
-- here, so the game's change event finds the same quest focused (Focus_FollowBlizzard) and goes no further.
local function tellBlizzard(id)
    if ns.char.setBlizzardFocus == false then return end
    if not (C_SuperTrack and C_SuperTrack.SetSuperTrackedQuestID) then return end
    if C_SuperTrack.GetSuperTrackedQuestID and C_SuperTrack.GetSuperTrackedQuestID() == id then return end
    C_SuperTrack.SetSuperTrackedQuestID(id)
end

-- `auto`: chosen by autofocus rather than by the player.
function ns.Focus_Set(id, auto)
    if not (id and C_QuestLog.IsOnQuest(id)) then return false end
    ns.char.focusQuest = id
    tellBlizzard(id)
    lastSignature = nil
    idle = false
    sticky = {}
    if not auto then
        suspended = false
        sticky[id] = ns.IsReadyToTurnIn(id) or nil
    end
    ns.Focus_Refresh(true)
    return true
end

-- Stops the focus. The window goes away, unless `keep` (the quest is gone, turned in or abandoned): then it
-- stays, saying there is no quest focused (or autofocus picks the next one).
function ns.Focus_Clear(keep)
    ns.char.focusQuest = nil
    lastSignature = nil
    sticky = {}
    idle = keep and true or false
    suspended = not keep
    ns.Focus_Refresh()
end

function ns.Focus_Toggle(id)
    if ns.Focus_Quest() == id then
        ns.Focus_Clear()
    else
        ns.Focus_Set(id)
    end
end

-- "Follow Blizzard's tracker" (Preferences, on unless switched off): focusing a quest in Blizzard's tracker or
-- quest log (the game's super tracked quest) focuses it here too, by hand, so autofocus leaves it be. The
-- other way is tellBlizzard. Nothing happens before the quest log is loaded (the game restores its own choice
-- while logging in) nor when the game clears its choice.
function ns.Focus_FollowBlizzard()
    if not ready or (ns.char and ns.char.followBlizzardFocus == false) then return end
    if not (C_SuperTrack and C_SuperTrack.GetSuperTrackedQuestID) then return end
    local id = C_SuperTrack.GetSuperTrackedQuestID()
    if not id or id == 0 or id == ns.Focus_Quest() then return end
    ns.Focus_Set(id)
end

-- Events: entering the game (the quest being focused on comes back once the log is loaded), combat, and the
-- autofocus's clock.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
pcall(events.RegisterEvent, events, "PLAYER_REGEN_DISABLED")
pcall(events.RegisterEvent, events, "PLAYER_REGEN_ENABLED")
pcall(events.RegisterEvent, events, "QUEST_ACCEPTED")
pcall(events.RegisterEvent, events, "SUPER_TRACKING_CHANGED")
events:SetScript("OnEvent", function(_, event, arg1, arg2)
    if event == "PLAYER_REGEN_DISABLED" then
        applyMouse(true)
    elseif event == "PLAYER_REGEN_ENABLED" then
        applyMouse(false)
    elseif event == "SUPER_TRACKING_CHANGED" then
        ns.Focus_FollowBlizzard()
    elseif event == "QUEST_ACCEPTED" then
        -- (log index, quest id) in this client's payload; just the id in others. The main refresh (Completao.lua)
        -- comes a moment after the event, and finds it marked
        local id = arg2 or arg1
        if id then fresh[id] = GetTime() + FRESH_SECONDS end
    else
        lastSignature = nil
        ns.Focus_Refresh(true)
        C_Timer.After(3, function()
            ready = true
            ns.Focus_Refresh()
        end)
    end
end)
local sinceAuto = 0
events:SetScript("OnUpdate", function(_, elapsed)
    sinceAuto = sinceAuto + elapsed
    if sinceAuto < AUTO_EVERY then return end
    sinceAuto = 0
    if ns.char and ns.char.focusAuto then autoFocus() end
end)
