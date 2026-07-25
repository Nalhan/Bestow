local _, CBC = ...

local function BetterAura(candidate, current)
  if not current then return true end
  if candidate.score and current.score and candidate.score ~= current.score then
    return candidate.score > current.score
  end
  if candidate.tier ~= current.tier then return candidate.tier < current.tier end
  local candidateLeft = candidate.expires == 0 and math.huge or candidate.expires
  local currentLeft = current.expires == 0 and math.huge or current.expires
  return candidateLeft > currentLeft
end

function CBC:ObserveProviderCapability(provider, match, spellID, reportedRank)
  if not provider or not provider.provisional or not spellID then return false end
  if provider.classToken ~= match.provider then return false end
  provider.observedCapabilities = provider.observedCapabilities or {}
  local observed = provider.observedCapabilities[match.category]
  local rankIndex = reportedRank or match.rankIndex
  if observed then
    if observed.family ~= match.family then return false end
    if observed.form == "greater" and match.form ~= "greater" then return false end
    if observed.form == match.form then
      local oldRank = tonumber(observed.rankIndex) or 0
      local newRank = tonumber(rankIndex) or 0
      if newRank <= oldRank then return false end
    end
  end
  provider.observedCapabilities[match.category] = {
    family=match.family,
    form=match.form,
    spellID=spellID,
    rankIndex=rankIndex,
  }
  local setPrimary = not provider.observedCategory
    or (match.form == "greater" and provider.observedForm ~= "greater")
    or (match.form == "greater" and provider.observedFamily ~= match.family)
  if setPrimary then
    provider.observedCategory = match.category
    provider.observedFamily = match.family
    provider.observedForm = match.form
  end
  return true
end

function CBC:ScanUnitAuras(member)
  self.coverage = self.coverage or {}
  local unitCoverage = {}
  self.coverage[member.guid] = unitCoverage
  local observedChanged = false
  for index=1,40 do
    local name, rank, icon, _, _, duration, expires, caster, _, _, spellID = UnitBuff(member.unit, index)
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
        local effect = spellID and self:GetSpellEffect(spellID)
        if effect then
          aura.score, aura.baseScore, aura.rawValue, aura.bonusPoints =
            self:GetNormalizedEffectScore(member.specID, effect, member.unit, match.family, spellID)
        end
        if BetterAura(aura, unitCoverage[match.category]) then
          unitCoverage[match.category] = aura
        end
        local observedProvider = casterGUID and self.providers[casterGUID]
        if self:ObserveProviderCapability(observedProvider, match, spellID, reportedRank) then
          observedChanged = true
        end
      end
    end
  end
  return observedChanged
end

function CBC:ScanAuras()
  self.coverage = self.coverage or {}
  wipe(self.coverage)
  local observedChanged = false
  for _, member in ipairs(self.roster) do
    if self:ScanUnitAuras(member) then observedChanged = true end
  end
  if observedChanged then self:ScheduleRebuild("observed provisional provider", 0.05) end
end

function CBC:ScanDirtyAuras()
  local dirty = self.auraDirtyUnits
  self.auraDirtyUnits = {}
  if not dirty or not next(dirty) then
    self:ScanAuras()
    return
  end
  local observedChanged = false
  for guid in pairs(dirty) do
    local member = self.rosterByGUID[guid]
    if member and UnitGUID(member.unit) == guid and self:ScanUnitAuras(member) then
      observedChanged = true
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
  local ours = aura.casterGUID == UnitGUID("player")
  local sameLocalFamily = capability and ours and aura.family == capability.family
  if capability and not sameLocalFamily then
    local spellID = greater and capability.greater or capability.single
    local effect = greater and capability.greaterEffect or capability.singleEffect
    local proposedScore = effect and self:GetNormalizedEffectScore(
      self.rosterByGUID[recipientGUID] and self.rosterByGUID[recipientGUID].specID,
      effect,
      self.rosterByGUID[recipientGUID] and self.rosterByGUID[recipientGUID].unit,
      capability.family,
      spellID
    )
    if proposedScore and aura.score and aura.score > proposedScore then return "stronger", aura end
    if proposedScore and aura.score and aura.score < proposedScore then return "weaker", aura end
  end
  if capability and aura.tier > capability.tier then return "weaker", aura end
  if capability and aura.tier < capability.tier then return "stronger", aura end
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
