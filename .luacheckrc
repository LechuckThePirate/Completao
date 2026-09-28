-- luacheck (como en Questie): Lua 5.1, la version del juego. Se ejecuta en la CI; en local:
--   luacheck Completao.lua Localization Modules Data/Dungeons.lua Data/Raids.lua Data/Overrides.lua test setupTests.lua
std = "lua51"
max_line_length = 160
codes = true

exclude_files = {
    "Data/Generated/",
    "tools/",
    ".github/",
    "images/",
}

-- lo que el addon define como global
globals = {
    "CompletaoDB", "CompletaoCharDB",
    "SlashCmdList", "SLASH_COMPLETAO1", "SLASH_COMPLETAO2",
    "BINDING_NAME_COMPLETAO_TOGGLE", "BINDING_NAME_COMPLETAO_PREFS",
    "Completao_Toggle", "Completao_TogglePreferences",
    "UISpecialFrames",
}

-- API y marcos del juego que usa
read_globals = {
    "C_AddOns", "C_CreatureInfo", "C_CurrencyInfo", "C_Item", "C_Map", "C_QuestLog", "C_Reputation", "C_SuperTrack",
    "C_Texture", "C_Timer", "C_TradeSkillUI",
    "CreateFrame", "Enum", "GameTooltip", "GameTooltip_Hide", "GetAddOnMetadata", "GetCoinTextureString",
    "GetCursorPosition", "GetFactionInfoByID", "GetItemIcon", "GetItemInfo", "GetItemInfoInstant", "GetLocale",
    "GetQuestDifficultyColor", "GetQuestGreenRange", "GetQuestLogQuestText", "GetUnitSpeed", "HandleModifiedItemClick",
    "BreakUpLargeNumbers", "IsControlKeyDown", "IsShiftKeyDown", "ITEM_QUALITY_COLORS", "LOCALIZED_CLASS_NAMES_MALE",
    "Minimap", "OpenQuestLog", "OpenWorldMap", "QuestDifficultyColors", "QuestLogFrame", "QuestLog_SetSelection",
    "QuestMapFrame", "QuestMapFrame_OpenToQuestDetails", "REWARDS", "REWARD_CHOICES", "REWARD_ITEMS",
    "REWARD_ITEMS_ONLY", "ShowUIPanel", "ToggleQuestLog", "TomTom", "UIParent", "UiMapPoint", "UnitClass",
    "UnitFactionGroup", "UnitLevel", "UnitName", "UnitRace", "WorldMapFrame",
    "hooksecurefunc", "issecretvalue", "strtrim", "tinsert", "wipe",
}

-- tests (busted): definen y cambian globales de la simulacion del juego a proposito
files["**/*.test.lua"] = { std = "+busted", globals = { "_G" }, allow_defined_top = true, ignore = { "111", "112", "113", "121", "122" } }
files["setupTests.lua"] = { std = "+busted", allow_defined_top = true, ignore = { "111", "112", "113", "121", "122" } }
files["test/"] = { std = "+busted", allow_defined_top = true, ignore = { "111", "112", "113", "121", "122", "131", "212" } }
