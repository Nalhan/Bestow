local _, CBC = ...

local floor, max, min = math.floor, math.max, math.min

CBC.ScoringReferenceStats = {
  strength=100, agility=100, stamina=100, intellect=100, spirit=100,
}

CBC.StatWeightKeys = {
  "strength", "agility", "stamina", "intellect", "spirit",
  "attackPower", "rangedAttackPower", "spellPower", "spellDamage", "healingPower",
  "armor", "defense", "dodge", "parry", "block", "blockValue", "shieldBlockValue",
  "critRating", "hitRating", "hasteRating", "expertise",
  "armorPenetration", "spellPenetration", "weaponDps", "rangedDps",
  "mp5",
}
CBC.SupplementalStatWeightDefaults = {mp5=0}
CBC.StatWeightScale = 10000
CBC.StatWeightMaximum = 100000

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

function CBC:GetConfigurableStatWeightDefaults(specID)
  local profile = self.StatWeightsBySpecID and self.StatWeightsBySpecID[tonumber(specID)]
  if not profile then return nil end
  self.configurableStatWeightDefaultCache = self.configurableStatWeightDefaultCache or {}
  local cached = self.configurableStatWeightDefaultCache[tonumber(specID)]
  if not cached then
    cached = {}
    for key, value in pairs(profile.weights) do cached[key] = value end
    for key, value in pairs(self.SupplementalStatWeightDefaults or {}) do
      if cached[key] == nil then cached[key] = value end
    end
    self.configurableStatWeightDefaultCache[tonumber(specID)] = cached
  end
  return cached, profile
end

function CBC:GetSpecStatWeights(specID)
  local defaults, profile = self:GetConfigurableStatWeightDefaults(specID)
  if not defaults then return nil end
  local overrides = self.db and self.db.statWeightOverrides and self.db.statWeightOverrides[tonumber(specID)]
  if not overrides or not next(overrides) then return defaults, profile end
  self.configuredStatWeightCache = self.configuredStatWeightCache or {}
  local cached = self.configuredStatWeightCache[tonumber(specID)]
  if not cached then
    cached = {}
    for key, value in pairs(defaults) do cached[key] = value end
    for key, value in pairs(overrides) do
      value = tonumber(value)
      if defaults[key] ~= nil and value and value >= 0
        and value <= self.StatWeightMaximum and value == value
      then
        cached[key] = Round(value * self.StatWeightScale) / self.StatWeightScale
      end
    end
    self.configuredStatWeightCache[tonumber(specID)] = cached
  end
  return cached, profile
end

function CBC:GetRecipientStatWeights(specID, unit)
  specID = tonumber(specID)
  local defaults, profile = self:GetConfigurableStatWeightDefaults(specID)
  if not defaults then return nil end
  local guid = unit and UnitGUID and UnitGUID(unit)
  if guid and guid == UnitGUID("player") then
    local weights = self:GetSpecStatWeights(specID)
    return weights, profile, "local:" .. tostring(specID)
  end
  local provider = guid and self.providers and self.providers[guid]
  if provider and provider.statWeightsAdvertised
    and provider.statWeightSpecID == specID
    and provider.statWeightSourceCompatible
    and provider.effectiveStatWeights
  then
    return provider.effectiveStatWeights, profile,
      table.concat({"remote", guid, provider.statWeightRevision or 0, provider.statWeightHash or "-"}, ":")
  end
  local sourceHash = self.StatWeightSource and self.StatWeightSource.sha256 or "-"
  return defaults, profile, "bundled:" .. tostring(specID) .. ":" .. sourceHash
end

function CBC:GetBisBeardStatWeights(specID)
  local profile = self.StatWeightsBySpecID and self.StatWeightsBySpecID[tonumber(specID)]
  return profile and profile.weights, profile
end

function CBC:InvalidateStatWeightScores(specID)
  self.configuredStatWeightCache = self.configuredStatWeightCache or {}
  self.configuredStatWeightCache[tonumber(specID)] = nil
  self.maxRawEffectCache = {}
end

function CBC:SetStatWeightOverride(specID, key, value)
  specID, value = tonumber(specID), tonumber(value)
  local defaults = self:GetConfigurableStatWeightDefaults(specID)
  if not defaults or defaults[key] == nil or not value or value < 0
    or value > self.StatWeightMaximum or value == math.huge or value ~= value
  then
    return false
  end
  value = Round(value * self.StatWeightScale) / self.StatWeightScale
  self.db.statWeightOverrides[specID] = self.db.statWeightOverrides[specID] or {}
  if math.abs(value - defaults[key]) < 0.0000001 then
    self.db.statWeightOverrides[specID][key] = nil
  else
    self.db.statWeightOverrides[specID][key] = value
  end
  if not next(self.db.statWeightOverrides[specID]) then
    self.db.statWeightOverrides[specID] = nil
  end
  self:InvalidateStatWeightScores(specID)
  self:Rebuild("stat weight override")
  self.statWeightRevision = (tonumber(self.statWeightRevision) or 0) + 1
  if self.SendStatWeights then self:SendStatWeights() end
  return true
end

function CBC:ResetStatWeightOverrides(specID, key)
  specID = tonumber(specID)
  local overrides = self.db.statWeightOverrides and self.db.statWeightOverrides[specID]
  if not overrides then return false end
  if key then
    overrides[key] = nil
    if not next(overrides) then self.db.statWeightOverrides[specID] = nil end
  else
    self.db.statWeightOverrides[specID] = nil
  end
  self:InvalidateStatWeightScores(specID)
  self:Rebuild("reset stat weights")
  self.statWeightRevision = (tonumber(self.statWeightRevision) or 0) + 1
  if self.SendStatWeights then self:SendStatWeights() end
  return true
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
  raw = raw + (tonumber(effect.manaPer5) or 0) * (tonumber(weights.mp5) or 0)

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
  local weights = self:GetRecipientStatWeights(specID, unit)
  if not weights or not effect then return nil end
  local stats, exact = self:GetScoringStats(unit)
  local raw = CalculateRaw(weights, effect, stats)
  return raw, exact
end

function CBC:GetMaxRawEffectUtility(specID, unit)
  local weights, _, weightSignature = self:GetRecipientStatWeights(specID, unit)
  if not weights then return 0, false end
  local stats, exact = self:GetScoringStats(unit)
  local signature = table.concat({
    weightSignature or tostring(specID), stats.strength, stats.agility, stats.stamina,
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
  local bonusPoints = self:GetEffectBonusPoints(specID, familyKey, spellID, unit)
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

function CBC:GetCategoryMaxPotentialWeightedScore(member, categoryKey)
  local category = self.Categories and self.Categories[categoryKey]
  if not member or not category then return nil end
  local bestScore, bestBase, bestRaw, bestBonus, bestExact, bestFamily, bestSpellID
  for familyKey, family in pairs(category.variants or {}) do
    for _, ids in ipairs({family.singleIDs, family.greaterIDs}) do
      local spellID = ids and ids[#ids]
      local effect = spellID and self:GetSpellEffect(spellID)
      if effect then
        local score, base, raw, bonus, exact = self:GetNormalizedEffectScore(
          member.specID, effect, member.unit, familyKey, spellID
        )
        if score and (
          not bestScore or score > bestScore
          or (score == bestScore and (not bestFamily or familyKey < bestFamily))
        ) then
          bestScore, bestBase, bestRaw, bestBonus, bestExact, bestFamily, bestSpellID =
            score, base, raw, bonus, exact, familyKey, spellID
        end
      end
    end
  end
  return bestScore, bestBase, bestRaw, bestBonus, bestExact, bestFamily, bestSpellID
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
