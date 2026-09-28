-- Common test setup (every *.test.lua starts with dofile("setupTests.lua")), as in Questie: the
-- simulated game API and the addon loader. Tests run from the repo root:
--   busted -p ".test.lua" .          (CI, Lua 5.1)
--   lua test/busted.lua              (locally, without installing busted)
dofile("test/WowApiMock.lua")
dofile("test/Addon.lua")
