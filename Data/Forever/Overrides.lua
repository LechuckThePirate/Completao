local _, ns = ...

-- Hand fixes over the generated data of Forever (Data/Forever/Generated/*); the ones shared with the other clients are
-- in Data/Classic/Overrides.lua. No generator overwrites this file. Examples:
--   ns.PatchQuest(92401, { requires = { 92422 } })   -- add/change a requirement
--   ns.PatchQuest(12345, { faction = false })         -- false removes the field

-- Some of Forever's new seasonal quests ("Sign Me Up!", "A Sealed Crate", "Shipping Label", "An Unfortunate End") are
-- holiday quests too, with the same problem as the classic ones (Data/Classic/Overrides.lua).
for _, id in ipairs({ 91899, 91900, 91904, 91905, 95816, 95819, 98247, 98248, 98372 }) do
    ns.PatchQuest(id, { holiday = true })
end
