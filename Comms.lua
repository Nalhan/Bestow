local _, CBC = ...

local floor = math.floor

local function Channel()
  if (GetNumRaidMembers and GetNumRaidMembers() or 0) > 0 then return "RAID" end
  if (GetNumPartyMembers and GetNumPartyMembers() or 0) > 0 then return "PARTY" end
end

local function SourceHash(self)
  local hash = self.StatWeightSource and self.StatWeightSource.sha256
  return hash and string.sub(hash, 1, 8) or "00000000"
end

local function Checksum(value)
  local a, b = 1, 0
  for index=1,#value do
    a = (a + string.byte(value, index)) % 65521
    b = (b + a) % 65521
  end
  return string.format("%04x%04x", b, a)
end

local function EncodeBase36(value)
  local digits = "0123456789abcdefghijklmnopqrstuvwxyz"
  value = floor(tonumber(value) or 0)
  if value == 0 then return "0" end
  local encoded = ""
  while value > 0 do
    local remainder = value % 36
    encoded = string.sub(digits, remainder + 1, remainder + 1) .. encoded
    value = floor(value / 36)
  end
  return encoded
end

local function DecodeBase36(value)
  if not value or value == "" then return nil end
  local decoded = 0
  for index=1,#value do
    local byte = string.byte(value, index)
    local digit
    if byte >= 48 and byte <= 57 then digit = byte - 48
    elseif byte >= 97 and byte <= 122 then digit = byte - 87
    else return nil end
    decoded = decoded * 36 + digit
    if decoded > CBC.StatWeightMaximum * CBC.StatWeightScale then return nil end
  end
  return decoded
end

local function CountMaskBits(mask)
  local count = 0
  while mask > 0 do
    if mask % 2 == 1 then count = count + 1 end
    mask = floor(mask / 2)
  end
  return count
end

function CBC:Send(message)
  local channel = Channel()
  if channel and message and #message <= 255 then SendAddonMessage(self.prefix, message, channel) end
end

function CBC:SenderMember(sender)
  return self.rosterByName[self:Normalize(sender)] or self.rosterByName[self:Normalize(self:ShortName(sender))]
end

function CBC:IsGlobalEditor(member)
  if not member then return false end
  if (GetNumRaidMembers and GetNumRaidMembers() or 0) == 0 then return true end
  local index = tonumber(string.match(member.unit or "", "^raid(%d+)$"))
  if not index then return false end
  local _, rank = GetRaidRosterInfo(index)
  return rank and rank > 0
end

function CBC:EncodeCapabilities()
  local tokens = {}
  for index, category in ipairs(self.CategoryOrder) do
    local cap = self.mine and self.mine.categories[category]
    if cap then
      tokens[#tokens+1] = table.concat({index,cap.single or 0,cap.greater or 0,cap.tier or 99},":")
    end
  end
  return table.concat(tokens, ",")
end

function CBC:DecodeCapabilities(provider, payload)
  provider.categories = {}
  for token in string.gmatch(payload or "", "[^,]+") do
    local index, single, greater, tier = string.match(token, "^(%d+):(%d+):(%d+):(%d+)$")
    local category = index and self.CategoryOrder[tonumber(index)]
    local family = category and self:GetFamily(provider.classToken, category)
    if category and family then
      provider.categories[category] = {
        category=category,family=family.key,provider=provider.classToken,
        single=tonumber(single) ~= 0 and tonumber(single) or nil,
        greater=tonumber(greater) ~= 0 and tonumber(greater) or nil,
        singleRank=self:GetFamilyRankIndex(family.singleIDs, tonumber(single)),
        greaterRank=self:GetFamilyRankIndex(family.greaterIDs, tonumber(greater)),
        singleEffect=self:GetSpellEffect(tonumber(single)),
        greaterEffect=self:GetSpellEffect(tonumber(greater)),
        independent=family.independent,sharedCastKey=family.sharedCastKey,
        tier=tonumber(tier) or family.tier,
      }
    end
  end
end

-- W|specID|sourceHash8|revision|checksum8|statMaskHex|scaledBase36Values
function CBC:EncodeStatWeights(specID)
  specID = tonumber(specID)
  local defaults = self:GetConfigurableStatWeightDefaults(specID)
  if not defaults then return nil end
  local overrides = self.db.statWeightOverrides and self.db.statWeightOverrides[specID]
  local mask, values = 0, {}
  for index, key in ipairs(self.StatWeightKeys or {}) do
    local value = tonumber(overrides and overrides[key])
    if value and value >= 0 and value <= self.StatWeightMaximum
      and value == value and defaults[key] ~= nil
    then
      mask = mask + 2 ^ (index - 1)
      values[#values+1] = EncodeBase36(value * self.StatWeightScale + 0.5)
    end
  end
  local maskText = string.format("%x", mask)
  local valuesText = #values > 0 and table.concat(values, ",") or "-"
  local canonical = table.concat({specID, SourceHash(self), maskText, valuesText}, "|")
  return maskText, valuesText, Checksum(canonical)
end

function CBC:SendStatWeights()
  local specID = self:GetLocalSpec()
  local mask, values, hash = self:EncodeStatWeights(specID)
  if not mask then return end
  local revision = tonumber(self.statWeightRevision) or 0
  self:Send(table.concat({
    "W", specID, SourceHash(self), revision, hash, mask, values,
  }, "|"))
end

function CBC:SendBonusPointOverride(familyKey)
  local specID = self:GetLocalSpec()
  local familyIndex = self.BonusFamilyIndex and self.BonusFamilyIndex[familyKey]
  if not specID or not familyIndex then return end
  local overrides = self.db.bonusPointOverrides and self.db.bonusPointOverrides[specID]
  local value = overrides and overrides[familyKey]
  local encoded = value ~= nil
    and tostring(floor(value * self.StatWeightScale + 0.5))
    or "-"
  self:Send(table.concat({
    "B", specID, tonumber(self.bonusPointRevision) or 0, familyIndex, encoded,
  }, "|"))
end

function CBC:SendBonusPoints()
  local specID = self:GetLocalSpec()
  local overrides = specID and self.db.bonusPointOverrides
    and self.db.bonusPointOverrides[specID]
  for _, familyKey in ipairs(self.BonusFamilyOrder or {}) do
    if overrides and overrides[familyKey] ~= nil then
      self:SendBonusPointOverride(familyKey)
    end
  end
end

function CBC:DecodeBonusPointOverride(provider, payload)
  local specText, revisionText, indexText, valueText =
    string.match(payload or "", "^(%d+)|(%d+)|(%d+)|([^|]+)$")
  local specID, revision, familyIndex =
    tonumber(specText), tonumber(revisionText), tonumber(indexText)
  local familyKey = familyIndex and self.BonusFamilyOrder
    and self.BonusFamilyOrder[familyIndex]
  if not specID or provider.specID ~= specID or not revision or not familyKey then return false end
  if provider.bonusPointRevision and revision < provider.bonusPointRevision then return false end
  local value
  if valueText ~= "-" then
    if not string.match(valueText, "^%-?%d+$") then return false end
    local scaled = tonumber(valueText)
    value = scaled and scaled / self.StatWeightScale
    if not value or value < self.BonusPointMinimum or value > self.BonusPointMaximum then
      return false
    end
  end
  provider.bonusPointOverrides = provider.bonusPointOverrides or {}
  provider.bonusPointOverrides[familyKey] = value
  if not next(provider.bonusPointOverrides) then provider.bonusPointOverrides = nil end
  provider.bonusPointRevision = revision
  provider.bonusPointsAdvertised = true
  return true
end

function CBC:DecodeStatWeights(provider, payload)
  local specText, sourceHash, revisionText, hash, maskText, valuesText =
    string.match(payload or "", "^(%d+)|([0-9a-f]+)|(%d+)|([0-9a-f]+)|([0-9a-f]+)|([^|]+)$")
  local specID, revision, mask =
    tonumber(specText), tonumber(revisionText), tonumber(maskText, 16)
  if not specID or not revision or not mask or not self.specsByID[specID] then return false end
  if #sourceHash ~= 8 or #hash ~= 8 or provider.specID ~= specID then return false end
  if provider.statWeightRevision and revision < provider.statWeightRevision then return false end
  if provider.statWeightRevision == revision and provider.statWeightHash
    and provider.statWeightHash ~= hash
  then
    return false
  end
  if mask >= 2 ^ #(self.StatWeightKeys or {}) then return false end

  local valueTokens = {}
  for token in string.gmatch(valuesText ~= "-" and valuesText or "", "[^,]+") do
    if not string.match(token, "^[0-9a-z]+$") then return false end
    valueTokens[#valueTokens+1] = token
  end
  if #valueTokens ~= CountMaskBits(mask) then return false end
  local canonical = table.concat({specID, sourceHash, maskText, valuesText}, "|")
  if hash ~= Checksum(canonical) then return false end
  if sourceHash ~= SourceHash(self) then
    provider.statWeightsAdvertised = true
    provider.statWeightSpecID = specID
    provider.statWeightSourceCompatible = false
    provider.statWeightSourceHash = sourceHash
    provider.statWeightRevision = revision
    provider.statWeightHash = hash
    provider.statWeightOverrides = nil
    provider.effectiveStatWeights = nil
    return false
  end

  local defaults = self:GetConfigurableStatWeightDefaults(specID)
  if not defaults then return false end
  local overrides, effective, tokenIndex = {}, {}, 1
  for key, value in pairs(defaults) do effective[key] = value end
  for index, key in ipairs(self.StatWeightKeys or {}) do
    if floor(mask / 2 ^ (index - 1)) % 2 == 1 then
      local scaled = DecodeBase36(valueTokens[tokenIndex])
      local value = scaled and scaled / self.StatWeightScale
      if not value or value < 0 or value > self.StatWeightMaximum or defaults[key] == nil then
        return false
      end
      overrides[key], effective[key] = value, value
      tokenIndex = tokenIndex + 1
    end
  end
  provider.statWeightsAdvertised = true
  provider.statWeightSpecID = specID
  provider.statWeightSourceCompatible = true
  provider.statWeightSourceHash = sourceHash
  provider.statWeightRevision = revision
  provider.statWeightHash = hash
  provider.statWeightOverrides = next(overrides) and overrides or nil
  provider.effectiveStatWeights = effective
  self.maxRawEffectCache = {}
  return true
end

function CBC:BroadcastState()
  if not Channel() then return end
  local specID = self:GetLocalSpec()
  self:Send("H|" .. self.protocol .. "|" .. (specID or 0))
  self:Send("C|" .. self:EncodeCapabilities())
  self:SendPreferences()
  self:SendStatWeights()
  self:SendBonusPoints()
  local playerGUID = UnitGUID("player")
  local overrides = self.session and self.session.providerOverrides and self.session.providerOverrides[playerGUID]
  for recipientGUID, category in pairs(overrides or {}) do
    self:Send("O|" .. playerGUID .. "|" .. recipientGUID .. "|" .. category)
  end
  local me = self.rosterByGUID[playerGUID]
  if self:IsGlobalEditor(me) and self.session then
    for category, version in pairs(self.session.headerVersions or {}) do
      self:SendHeader(
        category,
        self.session.header and self.session.header[category],
        version.revision,
        version.writer
      )
    end
    for recipientGUID, categories in pairs(self.session.cellVersions or {}) do
      for category, version in pairs(categories) do
        local providerGUID = self.session.cells[recipientGUID]
          and self.session.cells[recipientGUID][category]
        self:SendCell(
          recipientGUID, category, providerGUID,
          version.revision, version.writer
        )
      end
    end
  end
end

function CBC:SendPreferences()
  local specID = self:GetLocalSpec()
  if not specID then return end
  local tokens = {}
  local overrides = self.db.preferences and self.db.preferences[specID]
  for index, category in ipairs(self.CategoryOrder) do
    if overrides and overrides[category] ~= nil then
      tokens[#tokens+1] = index .. ":" .. overrides[category]
    end
  end
  self:Send("P|" .. specID .. "|" .. (#tokens > 0 and table.concat(tokens,",") or "-"))
end

function CBC:SendOverride(providerGUID, recipientGUID, category)
  self:Send("O|" .. providerGUID .. "|" .. recipientGUID .. "|" .. (category or "-"))
end

function CBC:SendCell(recipientGUID, category, providerGUID, revision, writerGUID)
  self:Send(table.concat({
    "X", tonumber(revision) or 0, writerGUID or UnitGUID("player") or "-",
    recipientGUID, category, providerGUID or "-",
  }, "|"))
end

function CBC:SendHeader(category, providerGUID, revision, writerGUID)
  self:Send(table.concat({
    "A", tonumber(revision) or 0, writerGUID or UnitGUID("player") or "-",
    category, providerGUID or "-",
  }, "|"))
end

function CBC:OnAddonMessage(prefix, message, channel, sender)
  if prefix ~= self.prefix or not message then return end
  local senderMember = self:SenderMember(sender)
  if not senderMember then
    self:ScheduleRebuild("unknown addon sender", 0.05)
    return
  end
  local kind, payload = string.match(message, "^([^|]+)|?(.*)$")
  local provider = self.providers[senderMember.guid] or {
    guid=senderMember.guid,name=senderMember.name,classToken=senderMember.classToken,
  }
  self.providers[senderMember.guid] = provider
  if kind == "H" then
    local version, specID = string.match(payload, "^(%d+)|(%d+)$")
    provider.protocol = tonumber(version)
    provider.protocolCompatible = provider.protocol == self.protocol
    if provider.protocolCompatible then
      provider.addon, provider.provisional = true, false
      provider.statWeightsAdvertised = nil
      provider.statWeightSpecID = nil
      provider.statWeightSourceCompatible = nil
      provider.statWeightSourceHash = nil
      provider.statWeightRevision = nil
      provider.statWeightHash = nil
      provider.statWeightOverrides = nil
      provider.effectiveStatWeights = nil
      provider.bonusPointOverrides = nil
      provider.bonusPointRevision = nil
      provider.bonusPointsAdvertised = nil
      specID = tonumber(specID)
      if self.specsByID[specID] then
        provider.specID, provider.specName = specID, self.specsByID[specID].name
      end
    end
  elseif kind == "C" then
    if not provider.protocolCompatible then return end
    provider.addon, provider.provisional = true, false
    self:DecodeCapabilities(provider, payload)
  elseif kind == "P" then
    if not provider.protocolCompatible then return end
    local specID, values = string.match(payload, "^(%d+)|(.+)$")
    specID = tonumber(specID)
    if self.specsByID[specID] then
      provider.specID, provider.specName, provider.preferenceOverrides = specID, self.specsByID[specID].name, {}
      for token in string.gmatch(values ~= "-" and values or "", "[^,]+") do
        local index, weight = string.match(token, "^(%d+):(%d+)$")
        local category = index and self.CategoryOrder[tonumber(index)]
        if category then provider.preferenceOverrides[category] = tonumber(weight) end
      end
    end
  elseif kind == "W" then
    if not provider.protocolCompatible then return end
    self:DecodeStatWeights(provider, payload)
  elseif kind == "B" then
    if not provider.protocolCompatible then return end
    self:DecodeBonusPointOverride(provider, payload)
  elseif kind == "R" then
    self.broadcastAt = GetTime() + 0.20
  elseif kind == "O" then
    local providerGUID, recipientGUID, category = string.match(payload, "^([^|]+)|([^|]+)|([^|]+)$")
    if providerGUID and senderMember.guid == providerGUID then
      self.session.providerOverrides[providerGUID] = self.session.providerOverrides[providerGUID] or {}
      self.session.providerOverrides[providerGUID][recipientGUID] = category ~= "-" and category or nil
      if providerGUID == UnitGUID("player") and senderMember.guid ~= UnitGUID("player") then
        self:Print(senderMember.shortName .. " changed one of your assignments.")
      end
    end
  elseif kind == "X" then
    if not provider.protocolCompatible then return end
    local revisionText, writerGUID, recipientGUID, category, providerGUID =
      string.match(payload, "^(%d+)|([^|]+)|([^|]+)|([^|]+)|([^|]+)$")
    local revision = tonumber(revisionText)
    if revision and recipientGUID and self:IsGlobalEditor(senderMember) and self.Categories[category] then
      self.session.cellVersions = self.session.cellVersions or {}
      self.session.cellVersions[recipientGUID] = self.session.cellVersions[recipientGUID] or {}
      local current = self.session.cellVersions[recipientGUID][category]
      if self:IsNewerMatrixVersion(current, revision, writerGUID) then
        self.session.cells[recipientGUID] = self.session.cells[recipientGUID] or {}
        local selectedProviderGUID = providerGUID ~= "-" and providerGUID or nil
        if selectedProviderGUID then
          self:ClearConflictingCellOverrides(
            recipientGUID, category, selectedProviderGUID, revision, writerGUID, false
          )
        end
        self.session.cells[recipientGUID][category] = selectedProviderGUID
        self:SetCellVersion(recipientGUID, category, revision, writerGUID)
        self.session.revision = math.max(tonumber(self.session.revision) or 0, revision)
        local tx = tostring(writerGUID) .. ":" .. revision
        self:DebugAssignment("RECEIVE", string.format(
          "tx=%s via=%s cell %s/%s -> %s",
          tx, tostring(senderMember.shortName), self:ProviderName(recipientGUID),
          category, self:ProviderName(selectedProviderGUID)
        ))
        self:QueueAssignmentAudit({
          tx=tx,kind="cell",revision=revision,writer=writerGUID,
          recipientGUID=recipientGUID,recipientName=self:ProviderName(recipientGUID),
          category=category,providerGUID=selectedProviderGUID,origin="remote",
        })
        if providerGUID == UnitGUID("player") then
          local recipient = self.rosterByGUID[recipientGUID]
          self:Print(senderMember.shortName .. " assigned you " .. self.Categories[category].short .. " on " .. (recipient and recipient.shortName or "a player") .. ".")
        end
      else
        self:DebugAssignment("STALE", string.format(
          "cell tx=%s:%s %s/%s current=%s/%s",
          tostring(writerGUID), revision, self:ProviderName(recipientGUID), tostring(category),
          tostring(current and current.revision), tostring(current and current.writer)
        ))
      end
    end
  elseif kind == "A" then
    if not provider.protocolCompatible then return end
    local revisionText, writerGUID, category, providerGUID =
      string.match(payload, "^(%d+)|([^|]+)|([^|]+)|([^|]+)$")
    local revision = tonumber(revisionText)
    if revision and category and self:IsGlobalEditor(senderMember) and self.Categories[category] then
      self.session.headerVersions = self.session.headerVersions or {}
      local current = self.session.headerVersions[category]
      if self:IsNewerMatrixVersion(current, revision, writerGUID) then
        local selectedProviderGUID = providerGUID ~= "-" and providerGUID or nil
        if selectedProviderGUID then
          self:ClearConflictingHeaderAssignments(
            category, selectedProviderGUID, revision, writerGUID, false
          )
        end
        self.session.header[category] = selectedProviderGUID
        self:SetHeaderVersion(category, revision, writerGUID)
        self.session.revision = math.max(tonumber(self.session.revision) or 0, revision)
        local tx = tostring(writerGUID) .. ":" .. revision
        self:DebugAssignment("RECEIVE", string.format(
          "tx=%s via=%s header %s -> %s",
          tx, tostring(senderMember.shortName), category,
          self:ProviderName(selectedProviderGUID)
        ))
        self:QueueAssignmentAudit({
          tx=tx,kind="header",revision=revision,writer=writerGUID,
          category=category,providerGUID=selectedProviderGUID,origin="remote",
        })
        if providerGUID == UnitGUID("player") then
          self:Print(senderMember.shortName .. " assigned your Greater " .. self.Categories[category].label .. ".")
        end
      else
        self:DebugAssignment("STALE", string.format(
          "header tx=%s:%s %s current=%s/%s",
          tostring(writerGUID), revision, tostring(category),
          tostring(current and current.revision), tostring(current and current.writer)
        ))
      end
    end
  end
  self:ScheduleRebuild("comms " .. tostring(kind), 0.05)
end
