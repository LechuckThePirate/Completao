local _, ns = ...

-- Correcciones a mano sobre los datos generados (Data/Generated/*). Este archivo no lo pisa ningun
-- generador. Ejemplos:
--   ns.PatchQuest(92401, { requires = { 92422 } })   -- anadir/cambiar un requisito
--   ns.PatchQuest(12345, { faction = false })         -- false borra el campo
