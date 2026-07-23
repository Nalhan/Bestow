local _, CBC = ...

local function BetterAura(candidate, current)
  if not current then return true end
  if candidate.tier ~= current.tier then return candidate.tier < current.tier end
  local candidateLeft = candidate.expires == 0 and math.huge or candidate.expires
  local currentLeft = current.expires == 0 and math.huge or current.expires
  return candidateLeft > currentLeft
end

function CBC:ScanAuras()
  self.coverage = self.coverage or {}
  wipe(self.coverage)
  local observedChanged = false
  for _, member in ipairs(self.roster) do
    local unitCoverage = {}
    self.coverage[member.guid] = unitCoverage
    for index=1,40 do
      local name, rank, icon, count, dispelType, duration, expires, caster, _, _, spellID = UnitBuff(member.unit, index)
      if not name then break end
      local matches = (spellID and self.auraIDIndex[spellID]) or self.auraNameIndex[self:Normalize(name)]
      if matches then
        local casterGUID = caster and UnitGUID(caster)
        local casterName = caster and self:FullName(caster)
        local reportedRank = tonumber(string.match(rank or "", "(%d+)"))
        for _, match in ipairs(matches) do
          local aura = {
            category=match.category,family=match.family,tier=match.tier,
            form=match.form,rankIndex=reportedRank or match.rankIndex,
            rankReported=reportedRank ~= nil,
            providerToken=match.provider,name=name,rank=rank,icon=icon,
            duration=duration or 0,expires=expires or 0,caster=caster,
            casterGUID=casterGUID,casterName=casterName,spellID=spellID,
          }
          if BetterAura(aura, unitCoverage[match.category]) then
            unitCoverage[match.category] = aura
          end
          local observedProvider = casterGUID and self.providers[casterGUID]
          local shouldObserve = observedProvider and observedProvider.provisional and (
            not observedProvider.observedCategory
            or (match.form == "greater" and observedProvider.observedForm ~= "greater")
            or (match.form == "greater" and observedProvider.observedFamily ~= match.family)
          )
          if shouldObserve then
            observedProvider.observedCategory = match.category
            observedProvider.observedFamily = match.family
            observedProvider.observedForm = match.form
            observedChanged = true
          end
        end
      end
    end
  end
  if observedChanged then self:ScheduleRebuild("observed provisional provider", 0.05) end
end

function CBC:GetCoverage(recipientGUID, category)
  return self.coverage and self.coverage[recipientGUID] and self.coverage[recipientGUID][category]
end

function CBC:CoverageState(recipientGUID, category, capability, greater)
  local aura = self:GetCoverage(recipientGUID, category)
  if not aura then return "missing", nil end
  if capability and aura.tier > capability.tier then return "weaker", aura end
  if capability and aura.tier < capability.tier then return "stronger", aura end
  local ours = aura.casterGUID == UnitGUID("player")
  -- CoA sometimes applies a base aura ID for a higher-rank cast. Never turn a
  -- freshly observed local cast back into an upgrade reminder on ID alone.
  if capability and aura.family == capability.family and not ours and aura.casterGUID then
    local requestedForm = greater and "greater" or "single"
    local knownRank = greater and capability.greaterRank or capability.singleRank
    if aura.form == requestedForm and aura.rankIndex and knownRank then
      if aura.rankIndex < knownRank then return "weaker", aura end
      if aura.rankIndex > knownRank then return "stronger", aura end
    end
  end
  if aura.expires and aura.expires > 0 and aura.expires - GetTime() <= self.db.expireSoon then return "expiring", aura end
  return ours and "ours" or "covered", aura
end
