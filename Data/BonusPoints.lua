local _, CBC = ...

-- Curated additive adjustments applied after a buff's stat-weight value is
-- normalized to 0-100. These intentionally stay separate from tooltip values.
--
-- Entries may define bonusPoints for every spec and/or a numeric spec-ID key:
--   devotionOfGrace = {bonusPoints=8, [48]=12}
-- SpellBonusPoints can override a family entry for one exact spell rank.
CBC.FamilyBonusPoints = {
  -- Resource-cost reduction, mana regeneration, and similar utility effects.
  devotionOfGrace = {bonusPoints=0},
  etchingOfTheMagi = {bonusPoints=0},
  resourcefulWuju = {bonusPoints=0},
  whispersOfYshaarj = {bonusPoints=0},
  groveInstinct = {bonusPoints=0},
  sealOfAlar = {bonusPoints=0},
  callOfTheWind = {bonusPoints=0},
  markOfZeliek = {bonusPoints=0},
  manaModule = {bonusPoints=0},
  spiritWuju = {bonusPoints=0},

  -- Armor/Stats families with additional resistance utility.
  earthenEndurance = {bonusPoints=0},
}

CBC.SpellBonusPoints = {}

local function ResolveBonus(entry, specID)
  if type(entry) == "number" then return entry end
  if type(entry) ~= "table" then return nil end
  if specID and entry[specID] ~= nil then return tonumber(entry[specID]) or 0 end
  return tonumber(entry.bonusPoints) or 0
end

function CBC:GetEffectBonusPoints(specID, familyKey, spellID)
  local spellBonus = ResolveBonus(spellID and self.SpellBonusPoints[spellID], specID)
  if spellBonus ~= nil then return spellBonus end
  return ResolveBonus(familyKey and self.FamilyBonusPoints[familyKey], specID) or 0
end
