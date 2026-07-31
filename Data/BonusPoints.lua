local _, CBC = ...

-- Curated additive adjustments applied after a buff's stat-weight value is
-- normalized to 0-100. These intentionally stay separate from tooltip values.
--
-- Entries may define bonusPoints for every spec and/or a numeric spec-ID key:
--   devotionOfGrace = {bonusPoints=8, [48]=12}
-- manaUserBonusPoints applies to every spec belonging to ManaUserClasses.
-- SpellBonusPoints can override a family entry for one exact spell rank.
CBC.ManaUserClasses = {
  NECROMANCER=true,
  PYROMANCER=true,
  CULTIST=true,
  STARCALLER=true,
  SUNCLERIC=true,
  TINKER=true,
  SPIRITMAGE=true, -- Runemaster
  WILDWALKER=true, -- Primalist
  PROPHET=true, -- Venomancer
  CHRONOMANCER=true,
  STORMBRINGER=true,
  WITCHDOCTOR=true,
  WITCHHUNTER=true,
}

CBC.FamilyBonusPoints = {
  -- Stamina buffs receive a stock survivability adjustment.
  enduringShout = {bonusPoints=10},
  foulMandate = {bonusPoints=10},
  riteOfResolve = {bonusPoints=10},
  markOfRivendare = {bonusPoints=10},
  sanguinaryOffering = {bonusPoints=10},

  -- Resource-cost reduction, nonlinear synergy, and similar utility effects.
  -- Linear MP5 value comes from the recipient's configurable mp5 weight.
  devotionOfGrace = {bonusPoints=20, manaUserBonusPoints=30},
  etchingOfTheMagi = {bonusPoints=20},
  resourcefulWuju = {bonusPoints=20},
  whispersOfYshaarj = {bonusPoints=0, manaUserBonusPoints=10},
  groveInstinct = {bonusPoints=0, manaUserBonusPoints=10},
  sealOfAlar = {bonusPoints=0, manaUserBonusPoints=10},
  callOfTheWind = {bonusPoints=0, manaUserBonusPoints=10},
  markOfZeliek = {bonusPoints=20},
  manaModule = {bonusPoints=0, manaUserBonusPoints=10},
  spiritWuju = {bonusPoints=0},

  -- Armor/Stats families with additional resistance utility.
  earthenEndurance = {bonusPoints=0},
}

CBC.SpellBonusPoints = {}
CBC.ResistanceEffectBonusPoints = 2
CBC.BonusPointMinimum = -100
CBC.BonusPointMaximum = 100

local resistanceFields = {
  "arcaneResistance",
  "fireResistance",
  "frostResistance",
  "natureResistance",
  "shadowResistance",
  "allResistances",
}

local function ResolveBonus(self, entry, specID)
  if type(entry) == "number" then return entry end
  if type(entry) ~= "table" then return nil end
  if specID and entry[specID] ~= nil then return tonumber(entry[specID]) or 0 end
  local spec = specID and self.specsByID and self.specsByID[specID]
  if spec and entry.manaUserBonusPoints ~= nil
    and self.ManaUserClasses and self.ManaUserClasses[spec.classToken]
  then
    return tonumber(entry.manaUserBonusPoints) or 0
  end
  return tonumber(entry.bonusPoints) or 0
end

function CBC:GetStockEffectBonusPoints(specID, familyKey, spellID)
  local spellBonus = ResolveBonus(self, spellID and self.SpellBonusPoints[spellID], specID)
  local bonus = spellBonus
  if bonus == nil then
    bonus = ResolveBonus(self, familyKey and self.FamilyBonusPoints[familyKey], specID) or 0
  end
  local effect = spellID and self:GetSpellEffect(spellID)
  for _, field in ipairs(resistanceFields) do
    if effect and (tonumber(effect[field]) or 0) > 0 then
      return bonus + self.ResistanceEffectBonusPoints
    end
  end
  return bonus
end

function CBC:GetBonusPointOverride(specID, familyKey, unit)
  specID = tonumber(specID)
  local guid = unit and UnitGUID and UnitGUID(unit)
  if guid and guid ~= UnitGUID("player") then
    local provider = self.providers and self.providers[guid]
    local overrides = provider and provider.bonusPointOverrides
    if provider and provider.specID == specID and overrides and overrides[familyKey] ~= nil then
      return overrides[familyKey]
    end
    return nil
  end
  local overrides = self.db and self.db.bonusPointOverrides
    and self.db.bonusPointOverrides[specID]
  return overrides and overrides[familyKey]
end

function CBC:GetEffectBonusPoints(specID, familyKey, spellID, unit)
  local override = self:GetBonusPointOverride(specID, familyKey, unit)
  if override ~= nil then return override end
  return self:GetStockEffectBonusPoints(specID, familyKey, spellID)
end

function CBC:SetBonusPointOverride(specID, familyKey, spellID, value)
  specID, value = tonumber(specID), tonumber(value)
  if not specID or not self.specsByID[specID] or not self.BonusFamilyIndex[familyKey]
    or not value or value < self.BonusPointMinimum or value > self.BonusPointMaximum
    or value == math.huge or value ~= value
  then
    return false
  end
  value = math.floor(value * self.StatWeightScale + 0.5) / self.StatWeightScale
  local stock = self:GetStockEffectBonusPoints(specID, familyKey, spellID)
  self.db.bonusPointOverrides[specID] = self.db.bonusPointOverrides[specID] or {}
  if math.abs(value - stock) < 0.0000001 then
    self.db.bonusPointOverrides[specID][familyKey] = nil
  else
    self.db.bonusPointOverrides[specID][familyKey] = value
  end
  if not next(self.db.bonusPointOverrides[specID]) then
    self.db.bonusPointOverrides[specID] = nil
  end
  self.bonusPointRevision = (tonumber(self.bonusPointRevision) or 0) + 1
  if self.SendBonusPointOverride then self:SendBonusPointOverride(familyKey) end
  self:Rebuild("bonus point override")
  return true
end

function CBC:ResetBonusPointOverrides(specID, familyKey)
  specID = tonumber(specID)
  local overrides = self.db.bonusPointOverrides and self.db.bonusPointOverrides[specID]
  if not overrides then return false end
  local resetKeys = {}
  if familyKey then
    if overrides[familyKey] == nil then return false end
    resetKeys[1] = familyKey
    overrides[familyKey] = nil
    if not next(overrides) then self.db.bonusPointOverrides[specID] = nil end
  else
    for key in pairs(overrides) do resetKeys[#resetKeys+1] = key end
    self.db.bonusPointOverrides[specID] = nil
  end
  self.bonusPointRevision = (tonumber(self.bonusPointRevision) or 0) + 1
  if self.SendBonusPointOverride then
    for _, key in ipairs(resetKeys) do self:SendBonusPointOverride(key) end
  end
  self:Rebuild("reset bonus points")
  return true
end
