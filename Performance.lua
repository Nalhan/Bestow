local _, CBC = ...

local AURA_REFRESH_INTERVAL = 0.20
local MATRIX_AURA_REFRESH_INTERVAL = 1.00
local INSPECTION_BATCH_INTERVAL = 1.00
local OBSERVATION_BATCH_INTERVAL = 0.50

CBC.performanceFastPathVersion = 4

local function InCombat()
  return InCombatLockdown and InCombatLockdown()
end

function CBC:DeferCombatStructuralWork(reason)
  self.combatStructuralDirty = true
  self.combatDeferredReason = reason or self.combatDeferredReason
  self.inspectionRebuildAt = nil
  self.observationRebuildAt = nil
  self.rebuildAt = nil
  self.rebuildReason = nil
end

function CBC:UpdateAssignmentAuraState()
  local frame = self.assignmentFrame
  if not frame or not frame.ready or not frame:IsShown() then return end
  for index, row in ipairs(frame.rows) do
    local member = self.roster[index]
    if member then
      for column, category in ipairs(self.CategoryOrder) do
        local cell = row.cells[column]
        local assignment = self.assignment.cells[member.guid]
          and self.assignment.cells[member.guid][category]
        if assignment then
          local provider = self.providers[assignment.providerGUID]
          local cap = provider and provider.categories and provider.categories[category]
          local state = cap and self:CoverageState(
            member.guid,
            category,
            cap,
            assignment.delivery == "greater"
          )
          local aura = self:GetCoverage(member.guid, category)
          if not aura or state == "missing" or state == "weaker" then
            cell.cbcBorders[1]:SetTexture(0.95, 0.24, 0.20, 1)
          elseif state == "stronger" then
            cell.cbcBorders[1]:SetTexture(0.42, 0.68, 0.92, 1)
          else
            cell.cbcBorders[1]:SetTexture(0, 0, 0, 1)
          end
        else
          cell.cbcBorders[1]:SetTexture(0, 0, 0, 1)
        end
      end
    end
  end
end

function CBC:RefreshAuraState()
  if not self.db then return end
  self:ScanDirtyAuras()
  self:BuildActions(true)
  self:UpdateCompact()
  local now = GetTime()
  if not InCombat()
    and (not self.nextMatrixAuraRefresh or now >= self.nextMatrixAuraRefresh)
  then
    self.nextMatrixAuraRefresh = now + MATRIX_AURA_REFRESH_INTERVAL
    self:UpdateAssignmentAuraState()
  end
end

local originalScheduleRebuild = CBC.ScheduleRebuild
CBC.ScheduleRebuild = function(self, reason, delay)
  if reason == "aura" then
    local interval = InCombat() and 0.30 or AURA_REFRESH_INTERVAL
    local due = GetTime() + interval
    if not self.auraRefreshAt or due < self.auraRefreshAt then
      self.auraRefreshAt = due
    end
    return
  end
  if reason == "hover leave" then
    self.compactRefreshAt = GetTime() + (delay or 0.25)
    return
  end
  if InCombat() then
    self:DeferCombatStructuralWork(reason)
    if reason == "combat" then self.compactRefreshAt = GetTime() end
    return
  end
  if reason == "Character Advancement inspection"
    or reason == "Character Advancement target inspection"
  then
    self.inspectionRebuildAt = GetTime() + INSPECTION_BATCH_INTERVAL
    return
  end
  if reason == "observed provisional provider" then
    self.observationRebuildAt = GetTime() + OBSERVATION_BATCH_INTERVAL
    return
  end
  self.performancePendingReason = reason
  return originalScheduleRebuild(self, reason, delay)
end

local originalRebuild = CBC.Rebuild
CBC.Rebuild = function(self, ...)
  if InCombat() then
    self:DeferCombatStructuralWork((...))
    self.compactRefreshAt = GetTime()
    return
  end
  self.auraRefreshAt = nil
  self.auraDirtyUnits = {}
  self.inspectionRebuildAt = nil
  self.observationRebuildAt = nil
  self.combatStructuralDirty = nil
  self.combatDeferredReason = nil
  self.performancePendingReason = nil
  local results = {originalRebuild(self, ...)}
  if self.rebuildAt and not self.rebuildReason and self.performancePendingReason then
    self.rebuildReason = self.performancePendingReason
  end
  return unpack(results)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("UNIT_AURA")
frame:SetScript("OnEvent", function(_, _, unit)
  local guid = unit and UnitGUID(unit)
  if guid and CBC.rosterByGUID[guid] then
    CBC.auraDirtyUnits = CBC.auraDirtyUnits or {}
    CBC.auraDirtyUnits[guid] = true
  end
end)
frame:SetScript("OnUpdate", function()
  if CBC.inspectionRebuildAt and GetTime() >= CBC.inspectionRebuildAt then
    CBC.inspectionRebuildAt = nil
    CBC:Rebuild("Character Advancement batch")
    return
  end
  if CBC.observationRebuildAt and GetTime() >= CBC.observationRebuildAt then
    CBC.observationRebuildAt = nil
    CBC:Rebuild("observed provider batch")
    return
  end
  if CBC.compactRefreshAt and GetTime() >= CBC.compactRefreshAt then
    CBC.compactRefreshAt = nil
    if not CBC.rebuildAt then CBC:UpdateCompact() end
  end
  if CBC.auraRefreshAt and GetTime() >= CBC.auraRefreshAt then
    CBC.auraRefreshAt = nil
    if not CBC.rebuildAt then CBC:RefreshAuraState() end
  end
end)
CBC.performanceFrame = frame
