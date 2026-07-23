local _, CBC = ...

local ESSENTIAL, USEFUL, MARGINAL, NONE = 100, 25, 5, 0
CBC.PreferenceWeights = {Essential=ESSENTIAL, Useful=USEFUL, Marginal=MARGINAL, None=NONE}

local statCategory = {
  Strength="strength", Agility="agility", Intellect="intellect",
  Spirit="spirit", Stamina="stamina",
}

local function HasStat(spec, wanted)
  for _, stat in ipairs(spec.stats or {}) do if stat == wanted then return true end end
end

function CBC:BuildPreferenceDefaults()
  self.defaultPreferences = {}
  for id, spec in pairs(self.specsByID) do
    local weights = {}
    for _, category in ipairs(self.CategoryOrder) do weights[category] = NONE end
    for _, stat in ipairs(spec.stats or {}) do
      local category = statCategory[stat]
      if category then weights[category] = ESSENTIAL end
    end
    local physical = spec.melee or HasStat(spec, "Strength") or HasStat(spec, "Agility")
    local magical = spec.role == "HEALER" or HasStat(spec, "Intellect") or HasStat(spec, "Spirit")
    if physical then weights.attackPower = ESSENTIAL end
    if magical then weights.spellPower = ESSENTIAL end
    if spec.role == "HEALER" then
      weights.mana = ESSENTIAL
      weights.spirit = math.max(weights.spirit or 0, USEFUL)
    elseif magical then
      weights.mana = USEFUL
    end
    if spec.role == "TANK" then
      weights.stamina = ESSENTIAL
      weights.armorStats = ESSENTIAL
    else
      weights.stamina = math.max(weights.stamina or 0, USEFUL)
      weights.armorStats = USEFUL
    end
    weights.percentStats = ESSENTIAL
    if HasStat(spec, "Spirit") then weights.intellect = math.max(weights.intellect or 0, USEFUL) end
    if HasStat(spec, "Intellect") and spec.role ~= "HEALER" then weights.spirit = math.max(weights.spirit or 0, MARGINAL) end
    self.defaultPreferences[id] = weights
  end
end

function CBC:GetPreference(member, category)
  local id = member and member.specID
  local advertised = member and self.providers[member.guid] and self.providers[member.guid].preferenceOverrides
  if advertised and advertised[category] ~= nil then return advertised[category] end
  local custom = id and self.db and self.db.preferences and self.db.preferences[id]
  if custom and custom[category] ~= nil then return custom[category] end
  local defaults = id and self.defaultPreferences[id]
  if defaults and defaults[category] ~= nil then return defaults[category] end
  return 5
end

function CBC:SetCurrentPreference(category, tierName)
  local specID = self:GetLocalSpec()
  local weight = self.PreferenceWeights[tierName]
  if not specID or not self.Categories[category] or weight == nil then return false end
  self.db.preferences[specID] = self.db.preferences[specID] or {}
  self.db.preferences[specID][category] = weight
  local provider = self.providers[UnitGUID("player")]
  if provider then
    provider.preferenceOverrides = provider.preferenceOverrides or {}
    provider.preferenceOverrides[category] = weight
  end
  if self.SendPreferences then self:SendPreferences() end
  self:Rebuild("preference")
  return true
end
