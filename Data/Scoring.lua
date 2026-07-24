local _, CBC = ...

local floor, max, min = math.floor, math.max, math.min

CBC.ScoringReferenceStats = {
  strength=100, agility=100, stamina=100, intellect=100, spirit=100,
}

local primaryStats = {
  {"strength", 1}, {"agility", 2}, {"stamina", 3},
  {"intellect", 4}, {"spirit", 5},
}

local function Round(value)
  return floor(value + 0.5)
end

local function Weight(weights, ...)
  local result = 0
  for index=1,select("#", ...) do
    result = max(result, tonumber(weights[select(index, ...)]) or 0)
  end
  return result
end

function CBC:GetSpecStatWeights(specID)
  local profile = self.StatWeightsBySpecID and self.StatWeightsBySpecID[tonumber(specID)]
  return profile and profile.weights, profile
end

function CBC:GetScoringStats(unit)
  local values, exact = {}, not not (unit and UnitExists and UnitExists(unit))
  for _, entry in ipairs(primaryStats) do
    local key, statIndex = entry[1], entry[2]
    local value
    if exact and UnitStat then
      local base, effective = UnitStat(unit, statIndex)
      value = tonumber(base) or tonumber(effective)
    end
    if not value or value <= 0 then
      value = self.ScoringReferenceStats[key]
      exact = false
    end
    values[key] = value
  end
  return values, exact
end

local function CalculateRaw(weights, effect, stats)
  local raw = 0
  for _, entry in ipairs(primaryStats) do
    local key = entry[1]
    raw = raw + (tonumber(effect[key]) or 0) * (tonumber(weights[key]) or 0)
  end
  raw = raw + (tonumber(effect.attackPower) or 0) *
    Weight(weights, "attackPower", "rangedAttackPower")
  raw = raw + (tonumber(effect.spellPower) or 0) *
    Weight(weights, "spellPower", "spellDamage", "healingPower")
  raw = raw + (tonumber(effect.armor) or 0) * (tonumber(weights.armor) or 0)

  local allStatsFlat = tonumber(effect.allStatsFlat) or 0
  local allStatsPercent = tonumber(effect.allStatsPercent) or 0
  if allStatsFlat ~= 0 or allStatsPercent ~= 0 then
    for _, entry in ipairs(primaryStats) do
      local key = entry[1]
      local amount = allStatsFlat + stats[key] * allStatsPercent / 100
      raw = raw + amount * (tonumber(weights[key]) or 0)
    end
  end
  return raw
end

function CBC:GetRawEffectUtility(specID, effect, unit)
  local weights = self:GetSpecStatWeights(specID)
  if not weights or not effect then return nil end
  local stats, exact = self:GetScoringStats(unit)
  local raw = CalculateRaw(weights, effect, stats)
  return raw, exact
end

function CBC:GetMaxRawEffectUtility(specID, unit)
  local weights = self:GetSpecStatWeights(specID)
  if not weights then return 0, false end
  local stats, exact = self:GetScoringStats(unit)
  local signature = table.concat({
    tostring(specID), stats.strength, stats.agility, stats.stamina,
    stats.intellect, stats.spirit,
  }, ":")
  self.maxRawEffectCache = self.maxRawEffectCache or {}
  local cached = self.maxRawEffectCache[signature]
  if cached then return cached, exact end
  local highest = 0
  for _, effect in pairs(self.EffectsBySpellID or {}) do
    local raw = CalculateRaw(weights, effect, stats)
    if raw and raw > highest then highest = raw end
  end
  self.maxRawEffectCache[signature] = highest
  return highest, exact
end

function CBC:GetNormalizedEffectScore(specID, effect, unit, familyKey, spellID)
  local raw, exact = self:GetRawEffectUtility(specID, effect, unit)
  if raw == nil then return nil end
  local highest = self:GetMaxRawEffectUtility(specID, unit)
  local baseScore = highest > 0 and Round(100 * raw / highest) or 0
  local bonusPoints = self:GetEffectBonusPoints(specID, familyKey, spellID)
  local score = min(100, max(0, baseScore + bonusPoints))
  return score, baseScore, raw, bonusPoints, exact
end

function CBC:GetPreferenceOverride(member, category)
  local provider = member and self.providers[member.guid]
  local advertised = provider and provider.preferenceOverrides
  if advertised and advertised[category] ~= nil then return advertised[category] end
  local specID = member and member.specID
  local custom = specID and self.db and self.db.preferences and self.db.preferences[specID]
  if custom and custom[category] ~= nil then return custom[category] end
end

function CBC:GetCapabilityWeightedScore(member, capability, greater)
  if not member or not capability then return nil end
  local spellID = greater and capability.greater or capability.single
  local effect = greater and capability.greaterEffect or capability.singleEffect
  if not spellID or not effect then return nil end
  return self:GetNormalizedEffectScore(
    member.specID, effect, member.unit, capability.family, spellID
  )
end

function CBC:GetCapabilityScore(member, capability, greater)
  if not member or not capability then return nil end
  local override = self:GetPreferenceOverride(member, capability.category)
  if override ~= nil then return override, "override" end
  local score, baseScore, raw, bonus, exact =
    self:GetCapabilityWeightedScore(member, capability, greater)
  if score == nil then return self:GetPreference(member, capability.category), "fallback" end
  if score == 0 and raw == 0 and bonus == 0 then
    return self:GetPreference(member, capability.category), "fallback"
  end
  return score, "statweights", baseScore, raw, bonus, exact
end
