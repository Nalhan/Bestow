local _, CBC = ...

local DEFAULT_WINDOW = 1.25
local MAX_RECENT_CHANGES = 20

local function IsGroupUnit(unit)
  return unit == "player"
    or string.match(unit or "", "^party%d+$")
    or string.match(unit or "", "^raid%d+$")
end

local function SortedSet(set)
  local values = {}
  for value in pairs(set or {}) do values[#values+1] = value end
  table.sort(values)
  return values
end

local function JoinSet(set)
  return table.concat(SortedSet(set), ",")
end

local function TSV(value)
  value = tostring(value or "")
  value = string.gsub(value, "[\r\n\t]+", " ")
  return string.gsub(value, "%s+", " ")
end

local function SameFamily(left, right)
  for family in pairs(left.families or {}) do
    if right.families and right.families[family] then return true end
  end
  return false
end

function CBC:GetOverwriteTestingState()
  self.db.overwriteTesting = self.db.overwriteTesting or {}
  local state = self.db.overwriteTesting
  if state.enabled == nil then state.enabled = false end
  state.window = tonumber(state.window) or DEFAULT_WINDOW
  state.records = state.records or {}
  return state
end

function CBC:CaptureCuratedBuffs(unit)
  local found = {}
  for index=1,40 do
    local name, rank, icon, _, _, duration, expires, caster, _, _, spellID = UnitBuff(unit, index)
    if not name then break end
    local matches = (spellID and self.auraIDIndex[spellID])
      or self.auraNameIndex[self:Normalize(name)]
    if matches then
      local identity = spellID and ("spell:"..spellID) or ("name:"..self:Normalize(name))
      local aura = found[identity]
      if not aura then
        aura = {
          identity=identity,spellID=spellID,name=name,rank=rank,icon=icon,
          duration=duration or 0,expires=expires or 0,
          casterGUID=caster and UnitGUID(caster),
          casterName=caster and self:FullName(caster),
          categories={},families={},providers={},forms={},
        }
        found[identity] = aura
      end
      for _, match in ipairs(matches) do
        aura.categories[match.category] = true
        aura.families[match.family] = true
        aura.providers[match.provider] = true
        aura.forms[match.form] = true
      end
    end
  end
  return found
end

function CBC:SeedOverwriteSnapshot(unit)
  if not unit or not UnitExists(unit) then return end
  local guid = UnitGUID(unit)
  if not guid then return end
  self.overwriteSnapshots = self.overwriteSnapshots or {}
  self.overwriteSnapshots[guid] = self:CaptureCuratedBuffs(unit)
end

function CBC:SeedOverwriteSnapshots()
  self.overwriteSnapshots = {}
  self.overwriteRecent = {}
  self.overwriteTransitionTimes = {}
  for _, member in ipairs(self.roster or {}) do
    if member.unit and UnitGUID(member.unit) == member.guid then
      self:SeedOverwriteSnapshot(member.unit)
    end
  end
end

function CBC:RecordOverwriteCandidate(targetGUID, targetName, removed, applied, timing)
  if not removed or not applied or removed.identity == applied.identity then return end
  if SameFamily(removed, applied) then return end

  local state = self:GetOverwriteTestingState()
  local key = removed.identity..">"..applied.identity
  local now = GetTime()
  self.overwriteTransitionTimes = self.overwriteTransitionTimes or {}
  self.overwriteTransitionTimes[targetGUID] = self.overwriteTransitionTimes[targetGUID] or {}
  local lastTransition = self.overwriteTransitionTimes[targetGUID][key]
  if lastTransition and now-lastTransition <= state.window then return end
  self.overwriteTransitionTimes[targetGUID][key] = now

  local record = state.records[key]
  local firstObservation = record == nil
  if not record then
    record = {
      removedSpellID=removed.spellID,
      removedName=removed.name,
      removedFamilies=JoinSet(removed.families),
      removedCategories=JoinSet(removed.categories),
      removedProviders=JoinSet(removed.providers),
      appliedSpellID=applied.spellID,
      appliedName=applied.name,
      appliedFamilies=JoinSet(applied.families),
      appliedCategories=JoinSet(applied.categories),
      appliedProviders=JoinSet(applied.providers),
      observations=0,
      sameUpdate=0,
      nearbyUpdate=0,
      targets={},
      firstSeen=date("%Y-%m-%d %H:%M:%S"),
    }
    state.records[key] = record
  end

  record.observations = (record.observations or 0) + 1
  if timing == "same-update" then
    record.sameUpdate = (record.sameUpdate or 0) + 1
  else
    record.nearbyUpdate = (record.nearbyUpdate or 0) + 1
  end
  record.lastSeen = date("%Y-%m-%d %H:%M:%S")
  record.targets = record.targets or {}
  record.targets[targetName or targetGUID or "unknown"] = true
  record.lastTarget = targetName
  record.lastRemovedCaster = removed.casterName or removed.casterGUID
  record.lastAppliedCaster = applied.casterName or applied.casterGUID

  self:Print(string.format(
    "%sPossible overwrite: %s (%s) replaced %s (%s) on %s [%s, observed %d].",
    firstObservation and "NEW: " or "",
    tostring(applied.name), tostring(applied.spellID or "?"),
    tostring(removed.name), tostring(removed.spellID or "?"),
    tostring(targetName or "unknown"), tostring(timing), record.observations
  ))
end

local function PruneRecent(changes, now, window)
  local kept = {}
  for _, change in ipairs(changes or {}) do
    if now-change.time <= window then kept[#kept+1] = change end
  end
  while #kept > MAX_RECENT_CHANGES do table.remove(kept, 1) end
  return kept
end

function CBC:ObserveOverwriteAuras(unit)
  local state = self:GetOverwriteTestingState()
  if not state.enabled or not IsGroupUnit(unit) or not UnitExists(unit) then return end
  local guid = UnitGUID(unit)
  if not guid then return end

  self.overwriteSnapshots = self.overwriteSnapshots or {}
  local previous = self.overwriteSnapshots[guid]
  local current = self:CaptureCuratedBuffs(unit)
  self.overwriteSnapshots[guid] = current
  if not previous then return end

  local appeared, removed = {}, {}
  for identity, aura in pairs(current) do
    if not previous[identity] then appeared[#appeared+1] = aura end
  end
  for identity, aura in pairs(previous) do
    if not current[identity] then removed[#removed+1] = aura end
  end
  if #appeared == 0 and #removed == 0 then return end

  local now = GetTime()
  local targetName = self:FullName(unit) or guid
  self.overwriteRecent = self.overwriteRecent or {}
  local recent = self.overwriteRecent[guid] or {appeared={},removed={}}
  recent.appeared = PruneRecent(recent.appeared, now, state.window)
  recent.removed = PruneRecent(recent.removed, now, state.window)

  for _, oldAura in ipairs(removed) do
    for _, newAura in ipairs(appeared) do
      self:RecordOverwriteCandidate(guid, targetName, oldAura, newAura, "same-update")
    end
    for _, change in ipairs(recent.appeared) do
      self:RecordOverwriteCandidate(guid, targetName, oldAura, change.aura, "nearby-update")
    end
  end
  for _, newAura in ipairs(appeared) do
    for _, change in ipairs(recent.removed) do
      self:RecordOverwriteCandidate(guid, targetName, change.aura, newAura, "nearby-update")
    end
  end

  for _, aura in ipairs(appeared) do
    recent.appeared[#recent.appeared+1] = {time=now,aura=aura}
  end
  for _, aura in ipairs(removed) do
    recent.removed[#recent.removed+1] = {time=now,aura=aura}
  end
  self.overwriteRecent[guid] = recent
end

function CBC:BuildOverwriteTestingReport()
  local state = self:GetOverwriteTestingState()
  local records = {}
  for _, record in pairs(state.records) do records[#records+1] = record end
  table.sort(records, function(left, right)
    if left.observations ~= right.observations then return left.observations > right.observations end
    if left.appliedName ~= right.appliedName then return left.appliedName < right.appliedName end
    return left.removedName < right.removedName
  end)

  local lines = {
    "Bestow curated-buff overwrite candidates",
    "Recorder enabled: "..tostring(state.enabled),
    "Correlation window: "..tostring(state.window).." seconds",
    "Candidates: "..tostring(#records),
    "",
    "Interpretation: applied aura appeared while removed aura disappeared on the same target.",
    "sameUpdate is strongest evidence; nearbyUpdate occurred within the correlation window.",
    "Same-family rank and Greater/individual transitions are excluded.",
    "",
    "removedSpellID\tremovedName\tremovedFamilies\tremovedCategories\tremovedProviders\tappliedSpellID\tappliedName\tappliedFamilies\tappliedCategories\tappliedProviders\tobservations\tsameUpdate\tnearbyUpdate\ttargets\tlastRemovedCaster\tlastAppliedCaster\tfirstSeen\tlastSeen",
  }
  for _, record in ipairs(records) do
    lines[#lines+1] = table.concat({
      TSV(record.removedSpellID), TSV(record.removedName),
      TSV(record.removedFamilies), TSV(record.removedCategories), TSV(record.removedProviders),
      TSV(record.appliedSpellID), TSV(record.appliedName),
      TSV(record.appliedFamilies), TSV(record.appliedCategories), TSV(record.appliedProviders),
      TSV(record.observations), TSV(record.sameUpdate), TSV(record.nearbyUpdate),
      TSV(table.concat(SortedSet(record.targets), ",")),
      TSV(record.lastRemovedCaster), TSV(record.lastAppliedCaster),
      TSV(record.firstSeen), TSV(record.lastSeen),
    }, "\t")
  end
  return table.concat(lines, "\n")
end

function CBC:SetOverwriteTestingEnabled(enabled, silent)
  local state = self:GetOverwriteTestingState()
  state.enabled = enabled == true
  local check = self.optionsPanel and self.optionsPanel.checks
    and self.optionsPanel.checks.overwriteTestingEnabled
  if check then check:SetChecked(state.enabled) end
  if self.overwriteEventFrame then
    if state.enabled then self.overwriteEventFrame:RegisterEvent("UNIT_AURA")
    else self.overwriteEventFrame:UnregisterEvent("UNIT_AURA") end
  end
  if state.enabled then
    self:SeedOverwriteSnapshots()
  else
    self.overwriteSnapshots = nil
    self.overwriteRecent = nil
    self.overwriteTransitionTimes = nil
  end
  if not silent then
    self:Print("Buff overwrite recorder "..(state.enabled and "enabled" or "disabled")..".")
  end
end

function CBC:ClearOverwriteTesting()
  local state = self:GetOverwriteTestingState()
  state.records = {}
  self:SeedOverwriteSnapshots()
  self:Print("Buff overwrite observations cleared.")
end

function CBC:HandleOverwriteTestingCommand(message)
  local command = string.lower(string.match(message or "", "^%s*(%S*)") or "")
  if command == "on" or command == "start" then
    self:SetOverwriteTestingEnabled(true)
  elseif command == "off" or command == "stop" then
    self:SetOverwriteTestingEnabled(false)
  elseif command == "clear" then
    self:ClearOverwriteTesting()
  elseif command == "report" or command == "dump" then
    self:ShowDiagnosticText("Bestow Buff Overwrite Report", self:BuildOverwriteTestingReport())
  else
    local state = self:GetOverwriteTestingState()
    local count = 0
    for _ in pairs(state.records) do count = count + 1 end
    self:Print(string.format(
      "Overwrite recorder: %s, %d candidates. /bestow overwrites on|off|report|clear",
      state.enabled and "ON" or "OFF", count
    ))
  end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
CBC.overwriteEventFrame = eventFrame
eventFrame:SetScript("OnEvent", function(_, event, ...)
  if event == "ADDON_LOADED" then
    if ... == CBC.name and CBC.db then
      CBC:SetOverwriteTestingEnabled(CBC:GetOverwriteTestingState().enabled, true)
    end
  elseif event == "UNIT_AURA" then
    if CBC.db then CBC:ObserveOverwriteAuras(...) end
  elseif CBC.db and CBC:GetOverwriteTestingState().enabled then
    CBC:SeedOverwriteSnapshots()
  end
end)

_G.SLASH_BESTOWOVERWRITES1 = "/bestowtest"
SlashCmdList.BESTOWOVERWRITES = function(message)
  CBC:HandleOverwriteTestingCommand(message)
end

local originalBestowCommand = SlashCmdList.BESTOW
if originalBestowCommand then
  SlashCmdList.BESTOW = function(message)
    local command, rest = string.match(message or "", "^(%S*)%s*(.-)$")
    command = string.lower(command or "")
    if command == "overwrites" or command == "overwrite" or command == "test" then
      CBC:HandleOverwriteTestingCommand(rest)
      return
    end
    originalBestowCommand(message)
    if command == "" or command == "help" then
      CBC:Print("/bestow overwrites on | off | report | clear")
    end
  end
end
