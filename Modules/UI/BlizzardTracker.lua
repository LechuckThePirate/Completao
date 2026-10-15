local _, ns = ...

-- Option "Hide Blizzard's objective tracker" (Preferences). Off by default: the tracker is the game's own.
-- The game puts it back on every login and /reload, so with the option on it is hidden again when the world is
-- entered (Completao.lua) and whenever the game shows it later (OnShow hook).

-- the frame is named after the client: the Forever beta has ObjectiveTrackerFrame, older clients the quest watch frame
local FRAME_NAMES = { "ObjectiveTrackerFrame", "QuestWatchFrame", "WatchFrame" }

local hooked = {}       -- frames with our OnShow hook (it can't be removed, so it checks the option itself)
local hiddenByUs = {}   -- frames that were visible when the option hid them: the only ones shown again when it goes off

local function enabled()
    return ns.char and ns.char.hideBlizzardTracker and true or false
end

local function hide(frame)
    if frame:IsShown() then
        hiddenByUs[frame] = true
        pcall(frame.Hide, frame)
    end
end

local function hookShow(frame)
    if hooked[frame] then return end
    hooked[frame] = true
    frame:HookScript("OnShow", function(self)
        -- right away, before the frame is drawn: a later tick would show it for a frame (the tracker blinked on
        -- every craft). A hook runs after the game's own code, so it does not taint it.
        if enabled() then hide(self) end
    end)
end

-- Makes the tracker match the option: hidden when it is on, and shown again (only if we hid it) when it goes off.
function ns.Tracker_Apply()
    local on = enabled()
    for _, name in ipairs(FRAME_NAMES) do
        local frame = _G[name]
        if type(frame) == "table" and frame.IsShown then
            if on then
                hookShow(frame)
                hide(frame)
            elseif hiddenByUs[frame] then
                hiddenByUs[frame] = nil
                frame:Show()
            end
        end
    end
end
