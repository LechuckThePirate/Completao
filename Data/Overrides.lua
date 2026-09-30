local _, ns = ...

-- Hand fixes over the generated data (Data/Generated/*). No generator overwrites this file. Examples:
--   ns.PatchQuest(92401, { requires = { 92422 } })   -- add/change a requirement
--   ns.PatchQuest(12345, { faction = false })         -- false removes the field

-- "Altered Beings" (880): the generator's step picks the densest spot in the Oasis Snapjaw's spawns,
-- but they spawn in two separate ponds in the Barrens and the bigger one (23 points around 46.8, 39.7)
-- isn't the Stagnant Oasis the quest chain is about -- the other one (14 points) is, matching the
-- previous step's "Test the Dried Seeds" at 55.6, 42.8.
ns.PatchQuest(880, { steps = { { name = "Altered Snapjaw Shell", area = 17, x = 55.6, y = 42.6 } } })
-- Holiday and event quests that are filed under zones, professions or reputation but are not in the events
-- section (they are level 60 and open from level 1, so "hide empty or completed categories" would count them as
-- work for anyone): Darkmoon Faire, the Gurubashi arena, the Ahn'Qiraj war effort, the Commendation Signets and
-- some of Forever's new seasonal quests ("Sign Me Up!", "A Sealed Crate", "Shipping Label", "An Unfortunate End").
for _, id in ipairs({
    7810, 7838, 7905, 7926, 8811, 8812, 8813, 8814, 8815, 8816, 8817, 8818, 8819, 8820, 8821, 8822, 8823,
    8824, 8825, 8826, 8830, 8831, 8832, 8833, 8834, 8835, 8836, 8837, 8838, 8839, 8840, 8841, 8842, 8843,
    8844, 8845, 9415, 9416, 9419, 9422, 91899, 91900, 91904, 91905, 95816, 95819, 98247, 98248, 98372,
}) do
    ns.PatchQuest(id, { holiday = true })
end
