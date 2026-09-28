local _, ns = ... -- luacheck: ignore 211 (no fixes for now)

-- Hand fixes over the generated data (Data/Generated/*). No generator overwrites this file. Examples:
--   ns.PatchQuest(92401, { requires = { 92422 } })   -- add/change a requirement
--   ns.PatchQuest(12345, { faction = false })         -- false removes the field
