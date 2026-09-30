local _, ns = ...
local L = ns.L

-- Focus window: a small floating window for the one quest being focused on (right click in Tracked Quests,
-- or the Focus button in a quest's details). It shows the quest's status icon ("?" ready to turn in, "..."
-- in progress) and title in its difficulty color, and under it the objectives with their progress
-- ("Boars 0/5"); done ones go grey and struck through. Once every objective is done they are replaced by
-- "Turn in <quest> (<npc>)". The waypoint goes to the step to do next (the nearest objective left, or the
-- turn-in) and moves by itself as objectives are completed. The window goes away when the quest is turned
-- in (or abandoned), can be dragged (its place is saved) and stops taking the mouse in combat.
local PAD, LINE_H, HEADER_H, ICON = 8, 16, 20, 16
local WIDTH_MIN, WIDTH_MAX = 200, 420
local CHECK_W = 16 -- room for the check before a done objective
local BACKDROP = {
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}
local COLORS = { done = "ff808080", target = "ffffd100", todo = "ffffffff" }

local frame, lines = nil, {}
local ready = false   -- the quest log is loaded (see Focus_Init): before, a quest not in it isn't gone yet
local lastSignature   -- what the waypoint was last worked out for

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

-- Click-through in combat: the window and its button stop taking the mouse, so clicks reach the game world.
local function applyMouse(combat)
    if not frame then return end
    local on = not combat
    frame:EnableMouse(on)
    frame.close:EnableMouse(on)
    if combat then
        frame:StopMovingOrSizing()
        if GameTooltip:IsOwned(frame) or GameTooltip:IsOwned(frame.close) then GameTooltip:Hide() end
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

function ns.Focus_ApplySettings()
    applyPosition()
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
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
    end)

    frame.icon = frame:CreateTexture(nil, "ARTWORK")
    frame.icon:SetSize(ICON, ICON)
    frame.icon:SetPoint("TOPLEFT", PAD, -PAD)
    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    frame.title:SetPoint("LEFT", frame.icon, "RIGHT", 4, 0)
    frame.title:SetJustifyH("LEFT")
    frame.title:SetWordWrap(false)

    local okClose, close = pcall(CreateFrame, "Button", nil, frame, "UIPanelCloseButton")
    if not okClose or not close then close = CreateFrame("Button", nil, frame) end
    close:SetSize(HEADER_H + 4, HEADER_H + 4)
    close:SetPoint("TOPRIGHT", 0, 0)
    close:SetScript("OnClick", function() ns.Focus_Clear() end)
    frame.close = close

    applyPosition()
    applyMouse(inCombat())
    frame:Hide()
end

-- A line of the list (created as needed): a check, the text and the strike-through line over it.
local function getLine(i)
    local line = lines[i]
    if line then return line end
    line = {}
    line.check = frame:CreateTexture(nil, "ARTWORK")
    line.check:SetSize(CHECK_W - 4, CHECK_W - 4)
    line.check:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    line.text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    line.text:SetJustifyH("LEFT")
    line.text:SetWordWrap(false)
    line.strike = frame:CreateTexture(nil, "OVERLAY")
    line.strike:SetHeight(1)
    line.strike:SetColorTexture(0.5, 0.5, 0.5, 1)
    lines[i] = line
    return line
end

local function setLine(i, text, kind, struck)
    local line = getLine(i)
    local y = -(PAD + HEADER_H + 4 + (i - 1) * LINE_H)
    line.check:ClearAllPoints()
    line.check:SetPoint("TOPLEFT", PAD, y - 1)
    line.check:SetShown(struck and true or false)
    line.text:ClearAllPoints()
    line.text:SetPoint("TOPLEFT", PAD + CHECK_W, y)
    line.text:SetText(("|c%s%s|r"):format(COLORS[kind], text))
    line.strike:ClearAllPoints()
    line.strike:SetPoint("LEFT", line.text, "LEFT", 0, 0)
    line.strike:SetShown(struck and true or false)
    return line
end

-- What the lines say: the objectives, or the turn-in once the quest is ready.
local function buildLines(q, steps, isReady, target)
    local out = {}
    if isReady then
        local finish = steps[#steps]
        local npc = finish.loc and finish.loc.npc
        local name = ns.QuestTitle(q.id, q.name)
        out[1] = { text = npc and L["Turn in %s (%s)"]:format(name, npc) or L["Turn in %s"]:format(name), kind = "target" }
        return out
    end
    for i, s in ipairs(steps) do
        if s.kind == "obj" then
            out[#out + 1] = {
                text = s.label .. (s.progress and (" " .. s.progress) or ""),
                kind = s.done and "done" or i == target and "target" or "todo", struck = s.done and true or false,
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

function ns.Focus_Refresh(force)
    local id = ns.Focus_Quest()
    if not id then
        if frame then frame:Hide() end
        return
    end
    if C_QuestLog.IsQuestFlaggedCompleted(id) then
        ns.Focus_Clear() -- turned in
        return
    end
    if not C_QuestLog.IsOnQuest(id) then
        if ready then ns.Focus_Clear() elseif frame then frame:Hide() end -- abandoned (or the log isn't loaded yet)
        return
    end
    if not frame then create() end

    local q = questDef(id)
    local steps = ns.QuestSteps(q)
    local isReady = ns.IsReadyToTurnIn(id)
    local target = ns.Focus_PickStep(steps, isReady)
    retarget(q, steps, target, force, isReady)

    ns.SetQuestStatusIcon(frame.icon, isReady and "ready" or "progress")
    local title = ns.QuestPrefix(q) .. ns.QuestTitle(id, q.name)
    frame.title:SetText(title)
    frame.title:SetTextColor(ns.QuestLevelColorRGB(q.level or q.minLevel))

    local content = buildLines(q, steps, isReady, target)
    local width = ICON + 4 + frame.title:GetStringWidth() + HEADER_H + 4
    for i, l in ipairs(content) do
        local line = setLine(i, l.text, l.kind, l.struck)
        width = math.max(width, CHECK_W + line.text:GetStringWidth())
    end
    for i = #content + 1, #lines do
        lines[i].check:Hide()
        lines[i].text:Hide()
        lines[i].strike:Hide()
    end
    width = math.max(WIDTH_MIN, math.min(WIDTH_MAX, math.ceil(width) + 2 * PAD))
    frame:SetSize(width, PAD * 2 + HEADER_H + 4 + #content * LINE_H)
    frame.title:SetWidth(width - 2 * PAD - ICON - 4 - HEADER_H)
    for i in ipairs(content) do
        local line = lines[i]
        line.text:SetWidth(width - 2 * PAD - CHECK_W)
        line.text:Show()
        line.strike:SetWidth(math.min(line.text:GetStringWidth(), width - 2 * PAD - CHECK_W))
    end
    frame:Show()
end

function ns.Focus_Set(id)
    if not (id and C_QuestLog.IsOnQuest(id)) then return false end
    ns.char.focusQuest = id
    lastSignature = nil
    ns.Focus_Refresh(true)
    return true
end

function ns.Focus_Clear()
    ns.char.focusQuest = nil
    lastSignature = nil
    if frame then frame:Hide() end
end

function ns.Focus_Toggle(id)
    if ns.Focus_Quest() == id then
        ns.Focus_Clear()
    else
        ns.Focus_Set(id)
    end
end

-- Events: entering the game (the quest being focused on comes back once the log is loaded) and combat.
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
pcall(events.RegisterEvent, events, "PLAYER_REGEN_DISABLED")
pcall(events.RegisterEvent, events, "PLAYER_REGEN_ENABLED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        applyMouse(true)
    elseif event == "PLAYER_REGEN_ENABLED" then
        applyMouse(false)
    else
        lastSignature = nil
        ns.Focus_Refresh(true)
        C_Timer.After(3, function()
            ready = true
            ns.Focus_Refresh()
        end)
    end
end)
