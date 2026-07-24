local _, CBC = ...

local function UnitList()
  local units = {}
  local raid = GetNumRaidMembers and GetNumRaidMembers() or 0
  if raid > 0 then
    for i=1,raid do units[#units+1] = "raid" .. i end
  else
    units[#units+1] = "player"
    local party = GetNumPartyMembers and GetNumPartyMembers() or 0
    for i=1,party do units[#units+1] = "party" .. i end
  end
  return units
end

function CBC:ResolveSpec(unit, guid)
  local provider = guid and self.providers[guid]
  if provider and provider.specID and self.specsByID[provider.specID] then
    return provider.specID, self.specsByID[provider.specID].name, "addon"
  end
  if UnitIsUnit(unit, "player") then
    local raw = GetSpecialization and GetSpecialization()
    if raw and self.specsByID[raw] then return raw, self.specsByID[raw].name, "client" end
    if raw and GetSpecializationInfo then
      local id, name = GetSpecializationInfo(raw)
      if id and self.specsByID[id] then return id, self.specsByID[id].name, "client" end
      local spec = self.specsByName[self:Normalize(name)]
      if spec then return spec.id, spec.name, "client" end
    end
  end
  local lgt = WeakAuras and WeakAuras.LGT
  if lgt and lgt.GetUnitTalentSpec then
    local name = lgt:GetUnitTalentSpec(unit)
    local spec = self.specsByName[self:Normalize(name)]
    if spec then return spec.id, spec.name, "LibGroupTalents" end
  end
  return nil, nil, "unknown"
end

function CBC:RefreshRoster()
  wipe(self.roster)
  wipe(self.rosterByGUID)
  wipe(self.rosterByName)
  local seenProviders = {}
  for _, unit in ipairs(UnitList()) do
    if UnitExists(unit) and UnitIsPlayer(unit) then
      local className, token = UnitClass(unit)
      token = self:ResolveClassToken(token)
      if token and self:IsCoAClass(token) then
        local guid = UnitGUID(unit)
        local name = self:FullName(unit)
        if guid and name then
          local specID, specName, specSource = self:ResolveSpec(unit, guid)
          local spec = specID and self.specsByID[specID]
          local member = {
            unit=unit,guid=guid,name=name,shortName=self:ShortName(name),
            classToken=token,className=(self.Classes[token] and self.Classes[token].name) or className,
            specID=specID,specName=specName,specSource=specSource,
            role=spec and spec.role or "DAMAGER",
            online=UnitIsConnected(unit),dead=UnitIsDeadOrGhost(unit),
          }
          self.roster[#self.roster+1] = member
          self.rosterByGUID[guid] = member
          self.rosterByName[self:Normalize(name)] = member
          self.rosterByName[self:Normalize(member.shortName)] = member
          seenProviders[guid] = true

          local provider = self.providers[guid] or {}
          provider.guid, provider.name, provider.classToken = guid, name, token
          provider.specID, provider.specName = specID, specName
          if not provider.addon then
            provider.provisional = true
            provider.categories = {}
            for category, family in pairs(self.familyByProviderCategory[token] or {}) do
              provider.categories[category] = {
                category=category,family=family.key,provider=token,tier=family.tier,
                independent=family.independent,
                single=family.singleIDs[#family.singleIDs],greater=family.greaterIDs[#family.greaterIDs],
                singleRank=#family.singleIDs,greaterRank=#family.greaterIDs,
                singleEffect=self:GetSpellEffect(family.singleIDs[#family.singleIDs]),
                greaterEffect=self:GetSpellEffect(family.greaterIDs[#family.greaterIDs]),
                provisional=true,
              }
            end
          end
          self.providers[guid] = provider
        end
      end
    end
  end
  table.sort(self.roster, function(a,b) return a.name < b.name end)
  for guid in pairs(self.providers) do
    if not seenProviders[guid] then self.providers[guid] = nil end
  end
end

function CBC:GetGroupKey()
  local guids = {}
  for _, member in ipairs(self.roster) do guids[#guids+1] = member.guid end
  table.sort(guids)
  return table.concat(guids, ",")
end

function CBC:RefreshSession()
  local grouped = (GetNumRaidMembers and GetNumRaidMembers() or 0) > 0 or (GetNumPartyMembers and GetNumPartyMembers() or 0) > 0
  if not grouped then
    -- Preserve a solo session across ordinary rebuilds so assignment controls
    -- can be tested and used on the player. Only create a fresh solo session
    -- when first loading or after an actual group disbands.
    if self.groupSessionActive or not self.soloSession then
      self.db.session = nil
      self.soloSession = {
        key=UnitGUID("player") or "solo",
        header={},cells={},providerOverrides={},revision=0,
      }
    end
    self.session = self.soloSession
    self.groupSessionActive = false
    return
  end
  local key = self:GetGroupKey()
  if not self.groupSessionActive then
    if not self.db.session or self.db.session.key ~= key then
      self.db.session = {key=key,header={},cells={},providerOverrides={},revision=0}
    end
    self.groupSessionActive = true
  else
    -- Membership changes are part of the same group session. Update the
    -- reload key without discarding explicit assignments for members who stay.
    self.db.session.key = key
  end
  self.session = self.db.session
  self.session.header = self.session.header or {}
  self.session.cells = self.session.cells or {}
  self.session.providerOverrides = self.session.providerOverrides or {}
  self.session.revision = self.session.revision or 0
end

function CBC:GetLocalSpec()
  local member = self.rosterByGUID[UnitGUID("player")]
  return member and member.specID, member and member.specName
end
