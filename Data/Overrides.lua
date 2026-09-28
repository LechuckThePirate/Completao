local _, ns = ...

-- Hand fixes over the generated data (Data/Generated/*). No generator overwrites this file. Examples:
--   ns.PatchQuest(92401, { requires = { 92422 } })   -- add/change a requirement
--   ns.PatchQuest(12345, { faction = false })         -- false removes the field

-- "Altered Beings" (880): the generator's step picks the densest spot in the Oasis Snapjaw's spawns,
-- but they spawn in two separate ponds in the Barrens and the bigger one (23 points around 46.8, 39.7)
-- isn't the Stagnant Oasis the quest chain is about -- the other one (14 points) is, matching the
-- previous step's "Test the Dried Seeds" at 55.6, 42.8.
ns.PatchQuest(880, { steps = { { name = "Altered Snapjaw Shell", area = 17, x = 55.6, y = 42.6 } } })
