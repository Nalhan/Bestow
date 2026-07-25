local _, CBC = ...

local AURA_REFRESH_INTERVAL = 0.20
local MATRIX_AURA_REFRESH_INTERVAL = 1.00
local INSPECTION_BATCH_INTERVAL = 1.00

CBC.performanceFastPathVersion = 1

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
  self:BuildActions()
  self:UpdateCompact()
  local now = GetTime()
  if not self.nextMatrixAuraRefresh or now >= self.nextMatrixAuraRefresh then
    self.nextMatrixAuraRefresh = now + MATRIX_AURA_REFRESH_INTERVAL
    self:UpdateAssignmentAuraState()
  end
end

local originalScheduleRebuild = CBC.ScheduleRebuild
CBC.ScheduleRebuild = function(self, reason, delay)
  if reason == "aura" then
    local due = GetTime() + AURA_REFRESH_INTERVAL
    if not self.auraRefreshAt or due < self.auraRefreshAt then
      self.auraRefreshAt = due
    end
    return
  end
  if reason == "Character Advancement inspection"
    or reason == "Character Advancement target inspection"
  then
    self.inspectionRebuildAt = GetTime() + INSPECTION_BATCH_INTERVAL
    return
  end
  return originalScheduleRebuild(self, reason, delay)
end

local originalRebuild = CBC.Rebuild
CBC.Rebuild = function(self, ...)
  self.auraRefreshAt = nil
  self.inspectionRebuildAt = nil
  return originalRebuild(self, ...)
end

local frame = CreateFrame("Frame")
frame:SetScript("OnUpdate", function()
  if CBC.inspectionRebuildAt and GetTime() >= CBC.inspectionRebuildAt then
    CBC.inspectionRebuildAt = nil
    CBC:Rebuild("Character Advancement batch")
    return
  end
  if CBC.auraRefreshAt and GetTime() >= CBC.auraRefreshAt then
    CBC.auraRefreshAt = nil
    if not CBC.rebuildAt then CBC:RefreshAuraState() end
  end
end)
CBC.performanceFrame = frame
