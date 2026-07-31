-- .luacheckrc configuration for Bestow (WoW 3.3.5 / Conquest of Azeroth Addon)

std = "lua51"
max_line_length = false
unused_args = false

globals = {
  -- WoW 3.3.5 & Frame API
  "UIParent", "GameTooltip", "InterfaceOptionsFrame_OpenToCategory", "InterfaceOptions_AddCategory",
  "CreateFrame", "GetTime", "UnitGUID", "UnitName", "UnitClass", "UnitIsPlayer", "UnitIsUnit",
  "UnitCanAttack", "UnitStat", "UnitBuff", "GetRaidRosterInfo", "GetSpecialization",
  "UnitIsConnected", "UnitIsDeadOrGhost", "UnitCanCooperate", "UnitAura", "UnitExists",
  "GetNumGroupMembers", "GetNumSubgroupMembers", "GetNumRaidMembers", "GetNumPartyMembers",
  "IsInRaid", "IsInGroup", "InCombatLockdown", "RegisterAddonMessagePrefix", "SendAddonMessage",
  "IsSpellInRange", "RegisterStateDriver", "UnregisterStateDriver", "STANDARD_TEXT_FONT",
  "GameFontNormalSmall", "GameFontNormal", "UIDropDownMenu_CreateInfo",
  "UIDropDownMenu_AddButton", "UIDropDownMenu_SetWidth", "UIDropDownMenu_Initialize",
  "UIDropDownMenu_SetSelectedValue", "UIDropDownMenu_SetText", "CloseDropDownMenus", "EasyMenu",
  "OptionsSliderTemplate", "UIDropDownMenuTemplate", "InterfaceOptionsCheckButtonTemplate",
  "SecureActionButtonTemplate", "SlashCmdList", "LibStub", "CoABuffCoordinatorDB",
  "GetSpellInfo", "GetSpellLink", "GetSpellName", "IsPassiveSpell", "IsSpellKnown", "BOOKTYPE_SPELL",
  "GetSpecializationInfo", "GetBuildInfo", "SendChatMessage", "wipe", "date",
  "DEFAULT_CHAT_FRAME", "CUSTOM_CLASS_COLORS", "RAID_CLASS_COLORS",
  "SLASH_BESTOW1", "SLASH_BESTOW2", "SLASH_BESTOW3",

  -- Ascension specific APIs
  "INSPECT_CHARACTER_ADVANCEMENT_RESULT", "NotifyInspectCharacterAdvancement",
  "GetInspectCharacterAdvancement",

  -- SavedVariables
  "BestowDB",
}

exclude_files = {
  "Libs/**",
}
