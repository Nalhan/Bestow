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

function CBC:GetExternalSpecLibrary()
  if LibStub then
    local library = LibStub("LibGroupTalents-1.0", true)
    if library and library.GetUnitTalentSpec then
      return library, "LibGroupTalents"
    end
  end
end

function CBC:ResolveExternalSpecValue(value, unit)
  local spec
  if type(value) == "number" then
    spec = self.specsByID[value]
  elseif value then
    spec = self.specsByName[self:Normalize(value)]
  end
  if not spec then return nil end

  if unit then
    local _, unitClass = UnitClass(unit)
    unitClass = self:ResolveClassToken(unitClass)
    if unitClass and spec.classToken ~= unitClass then return nil end
  end
  return spec
end

function CBC:CacheExternalSpec(guid, unit, value, source)
  local spec = self:ResolveExternalSpecValue(value, unit)
  if not spec or not guid then return nil end
  local existing = self.externalSpecCache[guid]
  local priority = {
    ["LibGroupTalents"] = 1,
    ["Character Advancement"] = 2,
  }
  if existing and (priority[existing.source] or 0) > (priority[source] or 0) then
    return self.specsByID[existing.id]
  end
  self.externalSpecCache[guid] = {
    id=spec.id,
    name=spec.name,
    source=source or "LibGroupTalents",
  }
  return spec
end

function CBC:OnLibGroupTalentsUpdate(_, guid, unit, newSpec)
  local _, source = self:GetExternalSpecLibrary()
  self:CacheExternalSpec(guid, unit, newSpec, source)
  self:ScheduleRebuild("LibGroupTalents update", 0.05)
end

function CBC:OnLibGroupTalentsUpdateComplete()
  self:ScheduleRebuild("LibGroupTalents complete", 0.05)
end

function CBC:RegisterExternalSpecResolver()
  local library, source = self:GetExternalSpecLibrary()
  if not library or not library.RegisterCallback or self.externalSpecLibrary == library then return end
  self.externalSpecLibrary = library
  self.externalSpecSource = source
  library.RegisterCallback(self, "LibGroupTalents_Update", "OnLibGroupTalentsUpdate")
  library.RegisterCallback(self, "LibGroupTalents_UpdateComplete", "OnLibGroupTalentsUpdateComplete")
  self:Debug("External spec resolver attached: " .. source)
end

function CBC:GetCharacterAdvancementAPI()
  local api = _G.C_CharacterAdvancement
  if api and type(api.InspectUnit) == "function" and type(api.GetInspectInfo) == "function" then
    return api
  end
end

function CBC:QueueSpecInspection(unit, guid)
  if not unit or not guid or UnitIsUnit(unit, "player") then return end
  local queued = self.specInspectQueue[guid]
  if queued then
    queued.unit = unit
    if queued.failed and UnitGUID("target") == guid then
      queued.failed = nil
      queued.nextAttempt = GetTime()
    end
    return
  end
  self.specInspectQueue[guid] = {
    guid=guid,
    unit=unit,
    attempts=0,
    nextAttempt=GetTime(),
  }
end

function CBC:CanRequestSpecInspection(unit)
  if not unit or not UnitExists(unit) or not UnitIsPlayer(unit) then return nil end
  if not UnitIsConnected(unit) then return nil end
  if UnitCanAttack("player", unit) or UnitCanAttack(unit, "player") then return nil end
  return self:GetCharacterAdvancementAPI() ~= nil
end

function CBC:ProcessSpecInspectQueue()
  local api = self:GetCharacterAdvancementAPI()
  if not self.db or not api then return end
  if InCombatLockdown and InCombatLockdown() then return end
  local now = GetTime()
  local active = self.specInspectActive
  if active and now - active.requestedAt < 5 then return end
  if active then
    local queued = self.specInspectQueue[active.guid]
    if queued then
      queued.nextAttempt = now + math.min(30, queued.attempts * 5)
      if queued.attempts >= 3 then queued.failed = true end
    end
  end
  self.specInspectActive = nil

  local targetGUID = UnitGUID("target")
  local targetQueued = targetGUID and self.specInspectQueue[targetGUID]
  if targetQueued and not self.externalSpecCache[targetGUID]
    and self.rosterByGUID[targetGUID] and not targetQueued.failed
    and now >= targetQueued.nextAttempt and self:CanRequestSpecInspection("target")
  then
    targetQueued.unit = "target"
    targetQueued.attempts = targetQueued.attempts + 1
    self.specInspectActive = {guid=targetGUID,unit="target",requestedAt=now}
    api.InspectUnit("target")
    return
  end

  for guid, queued in pairs(self.specInspectQueue) do
    local cached = self.externalSpecCache[guid]
    if cached or not self.rosterByGUID[guid] then
      self.specInspectQueue[guid] = nil
    elseif not queued.failed and now >= queued.nextAttempt and self:CanRequestSpecInspection(queued.unit) then
      queued.attempts = queued.attempts + 1
      self.specInspectActive = {guid=guid,unit=queued.unit,requestedAt=now}
      api.InspectUnit(queued.unit)
      return
    end
  end
end

function CBC:ResolveCharacterAdvancementSlot(unit, slot)
  if type(slot) ~= "number" then return nil end
  local _, token = UnitClass(unit)
  token = self:ResolveClassToken(token)
  if not token then return nil end

  local direct = self.specsByID[slot]
  if direct and direct.classToken == token then return direct end

  local class = self.Classes[token]
  local raw = class and class.specs and class.specs[slot]
  local fallback = raw and self.specsByID[raw[1]]
  if fallback and fallback.classToken == token then return fallback end
end

function CBC:ReadCharacterAdvancementSpec(unit, guid)
  local api = self:GetCharacterAdvancementAPI()
  if not api or not unit or not guid or UnitGUID(unit) ~= guid then return nil end
  local slot, unlocked = api.GetInspectInfo(unit)
  local spec = self:ResolveCharacterAdvancementSlot(unit, slot)
  if not spec then return nil, slot, unlocked end
  self.externalSpecCache[guid] = {
    id=spec.id,
    name=spec.name,
    source="Character Advancement",
    slot=slot,
    unlocked=unlocked,
  }
  return spec, slot, unlocked
end

function CBC:OnCharacterAdvancementInspectResult()
  local active = self.specInspectActive
  local targetGUID = UnitGUID("target")
  if targetGUID and self.rosterByGUID[targetGUID] then
    local targetSpec, targetSlot = self:ReadCharacterAdvancementSpec("target", targetGUID)
    if targetSpec then
      self.specInspectQueue[targetGUID] = nil
      self:Debug(string.format(
        "Character Advancement spec: %s -> %s (%s), slot=%s",
        tostring(self:FullName("target")), targetSpec.name, tostring(targetSpec.id), tostring(targetSlot)
      ))
      self:ScheduleRebuild("Character Advancement target inspection", 0.05)
      if not active or active.guid == targetGUID then
        self.specInspectActive = nil
        return
      end
    end
  end
  if not active then return end
  if not active.unit or UnitGUID(active.unit) ~= active.guid then return end

  local spec, slot, unlocked = self:ReadCharacterAdvancementSpec(active.unit, active.guid)
  if not spec and active.unit ~= "target" and UnitGUID("target") == active.guid then
    spec, slot, unlocked = self:ReadCharacterAdvancementSpec("target", active.guid)
  end
  if spec then
    self.specInspectQueue[active.guid] = nil
    self:Debug(string.format(
      "Character Advancement spec: %s -> %s (%s), slot=%s",
      tostring(self:FullName(active.unit)), spec.name, tostring(spec.id), tostring(slot)
    ))
    self:ScheduleRebuild("Character Advancement inspection", 0.05)
  else
    local queued = self.specInspectQueue[active.guid]
    if queued then
      queued.nextAttempt = GetTime() + 5
      if queued.attempts >= 3 then queued.failed = true end
    end
    self:Debug(string.format(
      "Character Advancement spec unresolved: %s slot=%s unlocked=%s",
      tostring(self:FullName(active.unit)), tostring(slot), tostring(unlocked)
    ))
  end
  self.specInspectActive = nil
end

function CBC:ResolveSpec(unit, guid)
  local provider = guid and self.providers[guid]
  if provider and provider.addon and provider.specID and self.specsByID[provider.specID] then
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

  local cached = guid and self.externalSpecCache[guid]
  if cached and cached.source == "Character Advancement" then
    return cached.id, cached.name, cached.source .. " cache"
  end

  self:RegisterExternalSpecResolver()
  local library, source = self:GetExternalSpecLibrary()
  if library then
    local value = library:GetUnitTalentSpec(unit)
    local spec = self:CacheExternalSpec(guid, unit, value, source)
    if spec then return spec.id, spec.name, source end
  end

  cached = guid and self.externalSpecCache[guid]
  if cached then
    return cached.id, cached.name, cached.source .. " cache"
  end

  self:QueueSpecInspection(unit, guid)
  return nil, nil, "unknown"
end

function CBC:ResetSpecInspections()
  wipe(self.specInspectQueue)
  self.specInspectActive = nil
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
              local capability = {
                category=category,family=family.key,provider=token,tier=family.tier,
                independent=family.independent,
                single=family.singleIDs[#family.singleIDs],greater=family.greaterIDs[#family.greaterIDs],
                singleRank=#family.singleIDs,greaterRank=#family.greaterIDs,
                singleEffect=self:GetSpellEffect(family.singleIDs[#family.singleIDs]),
                greaterEffect=self:GetSpellEffect(family.greaterIDs[#family.greaterIDs]),
                provisional=true,
              }
              local observed = provider.observedCapabilities and provider.observedCapabilities[category]
              if observed and observed.family == family.key then
                if observed.form == "single" then
                  capability.single = observed.spellID
                  capability.singleRank = observed.rankIndex
                  capability.singleEffect = self:GetSpellEffect(observed.spellID)
                elseif observed.form == "greater" then
                  capability.greater = observed.spellID
                  capability.greaterRank = observed.rankIndex
                  capability.greaterEffect = self:GetSpellEffect(observed.spellID)
                end
              end
              provider.categories[category] = capability
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
      wipe(self.externalSpecCache)
      wipe(self.specInspectQueue)
      self.specInspectActive = nil
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
