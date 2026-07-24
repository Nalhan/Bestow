local addonName, CBC = ...
if type(CBC) ~= "table" then CBC = {} end
_G.CoABuffCoordinator = CBC
_G.Bestow = CBC

CBC.name = addonName or "Bestow"
CBC.version = "0.2.0-alpha"
CBC.protocol = 3
CBC.prefix = "BESTOW1"
CBC.modules = {}
CBC.events = {}
CBC.diagnostics = {}
CBC.providers = {}
CBC.roster = {}
CBC.rosterByGUID = {}
CBC.rosterByName = {}
CBC.externalSpecCache = {}
CBC.actions = {}
CBC.assignment = {
  cells = {}, greaterByCategory = {}, greaterCategoriesByProvider = {},
  providerCategoriesByTarget = {},
}

local floor, max = math.floor, math.max

local defaults = {
  enabled = true,
  expireSoon = 300,
  showMode = "ALWAYS",
  revealMissing = true,
  revealExpiring = true,
  showSpecs = true,
  position = {"CENTER", 0, -180},
  assignmentPosition = {"CENTER", 0, 0},
  font = "Friz Quadrata TT",
  session = nil,
  preferences = {},
  statWeightOverrides = {},
  individualAssignmentThreshold = 25,
}

local function CopyDefaults(dst, src)
  for key, value in pairs(src) do
    if dst[key] == nil then
      if type(value) == "table" then
        dst[key] = {}
        CopyDefaults(dst[key], value)
      else
        dst[key] = value
      end
    elseif type(value) == "table" and type(dst[key]) == "table" then
      CopyDefaults(dst[key], value)
    end
  end
end

function CBC:Print(message)
  DEFAULT_CHAT_FRAME:AddMessage("|cff4db8ffBestow:|r " .. tostring(message))
end

function CBC:Debug(message)
  self.diagnostics[#self.diagnostics + 1] = date("%H:%M:%S") .. " " .. tostring(message)
  if #self.diagnostics > 200 then table.remove(self.diagnostics, 1) end
end

function CBC:Normalize(value)
  value = string.lower(tostring(value or ""))
  value = string.gsub(value, "[^%w]", "")
  return value
end

function CBC:FullName(unit)
  local name, realm = UnitName(unit)
  if not name then return nil end
  if realm and realm ~= "" then return name .. "-" .. realm end
  return name
end

function CBC:ShortName(name)
  return string.match(name or "", "^[^-]+") or name
end

function CBC:ClassColor(token)
  local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
  local color = colors and colors[token]
  if color then return color.r or 1, color.g or 1, color.b or 1 end
  return 0.85, 0.85, 0.85
end

function CBC:ClassHex(token)
  local r, g, b = self:ClassColor(token)
  return string.format("%02x%02x%02x", floor(r * 255 + 0.5), floor(g * 255 + 0.5), floor(b * 255 + 0.5))
end

function CBC:FormatDuration(expires)
  if not expires or expires <= 0 then return "active" end
  local left = max(0, expires - GetTime())
  if left >= 3600 then return string.format("%dh%02dm", floor(left / 3600), floor((left % 3600) / 60)) end
  return string.format("%d:%02d", floor(left / 60), floor(left % 60))
end

function CBC:RegisterModule(name, module)
  self.modules[name] = module
end

function CBC:ScheduleRebuild(reason, delay)
  self.rebuildReason = reason or self.rebuildReason
  self.rebuildAt = GetTime() + (delay or 0.10)
end

function CBC:Rebuild(reason)
  if not self.db then return end
  self:RefreshRoster()
  self:RefreshSession()
  self:BuildAssignments()
  self:BuildActions()
  self:UpdateCompact()
  self:UpdateAssignmentPanel()
  self.rebuildReason = nil
end

function CBC:Initialize()
  BestowDB = BestowDB or CoABuffCoordinatorDB or {}
  CopyDefaults(BestowDB, defaults)
  self.db = BestowDB
  self:BuildClassIndexes()
  self:BuildCatalogIndexes()
  self:BuildPreferenceDefaults()
  self:RegisterExternalSpecResolver()
  self:CreateUI()
  if RegisterAddonMessagePrefix then RegisterAddonMessagePrefix(self.prefix) end
  self:ScanSpellbook()
  self:Rebuild("initialize")
  if self.BroadcastState then self:BroadcastState() end
  self:Print("loaded. /bestow for commands.")
end

local eventFrame = CreateFrame("Frame")
CBC.eventFrame = eventFrame
local registered = {
  "ADDON_LOADED", "PLAYER_ENTERING_WORLD", "PARTY_MEMBERS_CHANGED",
  "RAID_ROSTER_UPDATE", "SPELLS_CHANGED", "LEARNED_SPELL_IN_TAB",
  "UNIT_AURA", "CHAT_MSG_ADDON", "PLAYER_TALENT_UPDATE",
  "ACTIVE_TALENT_GROUP_CHANGED", "PLAYER_REGEN_DISABLED",
  "PLAYER_REGEN_ENABLED", "UI_SCALE_CHANGED", "DISPLAY_SIZE_CHANGED",
}
for _, event in ipairs(registered) do eventFrame:RegisterEvent(event) end

eventFrame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... == CBC.name then
      CBC:Initialize()
    elseif CBC.db then
      CBC:RegisterExternalSpecResolver()
    end
    return
  end
  if not CBC.db then return end
  if event == "CHAT_MSG_ADDON" then
    CBC:OnAddonMessage(...)
  elseif event == "UNIT_AURA" then
    local unit = ...
    if unit and (unit == "player" or string.match(unit, "^party%d+$") or string.match(unit, "^raid%d+$")) then
      CBC:ScheduleRebuild("aura", 0.05)
    end
  elseif event == "SPELLS_CHANGED" or event == "LEARNED_SPELL_IN_TAB" then
    CBC:ScanSpellbook()
    if CBC.BroadcastState then CBC:BroadcastState() end
    CBC:ScheduleRebuild("spells", 0.05)
  elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
    CBC:ScheduleRebuild("combat", 0)
  elseif event == "UI_SCALE_CHANGED" or event == "DISPLAY_SIZE_CHANGED" then
    if CBC.PixelRelayout then CBC:PixelRelayout() end
  else
    if event == "PLAYER_TALENT_UPDATE" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
      if CBC.BroadcastState then CBC:BroadcastState() end
      if CBC.statWeightOptionsPanel and CBC.statWeightOptionsPanel:IsShown() then
        CBC:RefreshStatWeightOptions()
      end
    end
    if event == "PLAYER_ENTERING_WORLD" or event == "PARTY_MEMBERS_CHANGED" or event == "RAID_ROSTER_UPDATE" then
      CBC.broadcastAt = GetTime() + 0.75
    end
    CBC:ScheduleRebuild(event, 0.20)
  end
end)

eventFrame:SetScript("OnUpdate", function(_, elapsed)
  if CBC.rebuildAt and GetTime() >= CBC.rebuildAt then
    CBC.rebuildAt = nil
    CBC:Rebuild(CBC.rebuildReason)
  end
  CBC.durationElapsed = (CBC.durationElapsed or 0) + elapsed
  if CBC.durationElapsed >= 1 then
    CBC.durationElapsed = 0
    if CBC.UpdateDurations then CBC:UpdateDurations() end
  end
  if CBC.broadcastAt and GetTime() >= CBC.broadcastAt then
    CBC.broadcastAt = nil
    if CBC.BroadcastState then CBC:BroadcastState() end
  end
end)

SLASH_BESTOW1 = "/bestow"
SLASH_BESTOW2 = "/cbc"
SLASH_BESTOW3 = "/coabuffs"
SlashCmdList.BESTOW = function(message)
  local command, rest = string.match(message or "", "^(%S*)%s*(.-)$")
  command = string.lower(command or "")
  if command == "" or command == "help" then
    CBC:Print("/bestow assignments | config | dump | tooltips | rescan | reset | show | hide")
    CBC:Print("/bestow pref category essential|useful|marginal|none")
  elseif command == "assignments" or command == "matrix" then
    if CBC.ToggleAssignmentPanel then CBC:ToggleAssignmentPanel() end
  elseif command == "config" or command == "options" then
    if CBC.OpenOptions then CBC:OpenOptions() end
  elseif command == "dump" then
    if CBC.ShowDiagnostics then CBC:ShowDiagnostics() end
  elseif command == "tooltips" then
    if CBC.ShowSpellTooltipDump then CBC:ShowSpellTooltipDump() end
  elseif command == "rescan" then
    CBC:ScanSpellbook()
    CBC:BroadcastState()
    CBC:Rebuild("manual rescan")
  elseif command == "reset" then
    CBC.db.session = nil
    CBC:Rebuild("reset")
    CBC:BroadcastState()
  elseif command == "show" then
    CBC.db.enabled = true
    CBC:Rebuild("show")
  elseif command == "hide" then
    CBC.db.enabled = false
    if CBC.compactFrame then CBC.compactFrame:Hide() end
  elseif command == "debug" then
    CBC:Print("roster=" .. #CBC.roster .. " actions=" .. #CBC.actions)
  elseif command == "pref" then
    local category, tier = string.match(rest or "", "^(%S+)%s+(%S+)$")
    tier = tier and string.upper(string.sub(tier,1,1)) .. string.lower(string.sub(tier,2))
    if tier == "None" then tier = "None" end
    if CBC:SetCurrentPreference(category, tier) then CBC:Print(category.." set to "..tier)
    else CBC:Print("Usage: /bestow pref category essential|useful|marginal|none") end
  else
    CBC:Print("Unknown command. /bestow help")
  end
end
