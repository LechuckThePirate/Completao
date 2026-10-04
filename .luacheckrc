-- luacheck (as in Questie): Lua 5.1, the game's version. Runs in CI; locally:
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

-- what the addon defines as globals
globals = {
    "CompletaoDB", "CompletaoCharDB",
    "SlashCmdList", "SLASH_COMPLETAO1", "SLASH_COMPLETAO2",
    "BINDING_NAME_COMPLETAO_TOGGLE", "BINDING_NAME_COMPLETAO_PREFS",
    "Completao_Toggle", "Completao_TogglePreferences",
    "UISpecialFrames",
}

-- the game's API and frames it uses
read_globals = {
    "C_AddOns", "C_CreatureInfo", "C_CurrencyInfo", "C_Item", "C_Map", "C_QuestLog", "C_Reputation", "C_SuperTrack",
    "C_Texture", "C_Timer", "C_TradeSkillUI",
    "CLOSE", "CreateFrame", "CreateVector2D", "Enum", "GameFontHighlightSmall", "GameTooltip", "GameTooltip_Hide", "GetAddOnMetadata",
    "GetCoinTextureString",
    "GetCursorPosition", "GetFactionInfoByID", "GetItemIcon", "GetItemInfo", "GetItemInfoInstant", "GetLocale",
    "IsMouseButtonDown", "GetQuestDifficultyColor", "GetQuestGreenRange", "GetQuestLogQuestText", "GetUnitSpeed", "InCombatLockdown", "UnitAffectingCombat", "UnitOnTaxi", "GetProfessions", "GetProfessionInfo", "GetNumSkillLines", "GetSkillLineInfo", "HandleModifiedItemClick",
    "BreakUpLargeNumbers", "IsControlKeyDown", "IsShiftKeyDown", "ITEM_QUALITY_COLORS", "LOCALIZED_CLASS_NAMES_MALE",
    "Minimap", "OpenQuestLog", "OpenWorldMap", "QuestDifficultyColors", "QuestLogFrame", "QuestLog_SetSelection",
    "QuestMapFrame", "QuestMapFrame_OpenToQuestDetails", "QuestMapFrame_ShowQuestDetails","REWARDS", "REWARD_CHOICES", "REWARD_ITEMS",
    "REWARD_ITEMS_ONLY", "ScrollFrame_OnScrollRangeChanged", "ShowUIPanel", "ToggleQuestLog", "TomTom", "UIParent", "UiMapPoint", "UnitClass",
    "UnitFactionGroup", "UnitLevel", "UnitName", "UnitRace", "WorldMapFrame",
    "hooksecurefunc", "issecretvalue", "strtrim", "tinsert", "wipe",
    "QuestMapQuestOptions_AbandonQuest", "SetAbandonQuest", "StaticPopup_Show",
}

-- tests (busted): they define and change the simulated game's globals on purpose
files["**/*.test.lua"] = { std = "+busted", globals = { "_G" }, allow_defined_top = true, ignore = { "111", "112", "113", "121", "122" } }
files["setupTests.lua"] = { std = "+busted", allow_defined_top = true, ignore = { "111", "112", "113", "121", "122" } }
files["test/"] = { std = "+busted", allow_defined_top = true, ignore = { "111", "112", "113", "121", "122", "131", "212" } }
