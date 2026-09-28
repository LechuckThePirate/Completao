-- Preparacion comun de los tests (cada *.test.lua empieza con dofile("setupTests.lua")), como en Questie:
-- la simulacion de la API del juego y el cargador del addon. Los tests se ejecutan desde la raiz del repo:
--   busted -p ".test.lua" .          (CI, Lua 5.1)
--   lua test/busted.lua              (en local, sin instalar busted)
dofile("test/WowApiMock.lua")
dofile("test/Addon.lua")
