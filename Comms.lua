local _, CBC = ...

local function Channel()
  if (GetNumRaidMembers and GetNumRaidMembers() or 0) > 0 then return "RAID" end
  if (GetNumPartyMembers and GetNumPartyMembers() or 0) > 0 then return "PARTY" end
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

function CBC:BroadcastState()
  if not Channel() then return end
  local specID = self:GetLocalSpec()
  self:Send("H|" .. self.protocol .. "|" .. (specID or 0))
  self:Send("C|" .. self:EncodeCapabilities())
  self:SendPreferences()
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
        self.session.cells[recipientGUID][category] = providerGUID ~= "-" and providerGUID or nil
        self:SetCellVersion(recipientGUID, category, revision, writerGUID)
        self.session.revision = math.max(tonumber(self.session.revision) or 0, revision)
        self:Debug(string.format(
          "Matrix cell accepted r%d writer=%s via=%s recipient=%s category=%s provider=%s",
          revision, tostring(writerGUID), tostring(senderMember.guid), tostring(recipientGUID),
          tostring(category), tostring(providerGUID)
        ))
        if providerGUID == UnitGUID("player") then
          local recipient = self.rosterByGUID[recipientGUID]
          self:Print(senderMember.shortName .. " assigned you " .. self.Categories[category].short .. " on " .. (recipient and recipient.shortName or "a player") .. ".")
        end
      else
        self:Debug(string.format(
          "Matrix cell ignored stale r%d writer=%s recipient=%s category=%s current=%s/%s",
          revision, tostring(writerGUID), tostring(recipientGUID), tostring(category),
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
        self.session.header[category] = providerGUID ~= "-" and providerGUID or nil
        self:SetHeaderVersion(category, revision, writerGUID)
        self.session.revision = math.max(tonumber(self.session.revision) or 0, revision)
        self:Debug(string.format(
          "Matrix header accepted r%d writer=%s via=%s category=%s provider=%s",
          revision, tostring(writerGUID), tostring(senderMember.guid),
          tostring(category), tostring(providerGUID)
        ))
        if providerGUID == UnitGUID("player") then
          self:Print(senderMember.shortName .. " assigned your Greater " .. self.Categories[category].label .. ".")
        end
      else
        self:Debug(string.format(
          "Matrix header ignored stale r%d writer=%s category=%s current=%s/%s",
          revision, tostring(writerGUID), tostring(category),
          tostring(current and current.revision), tostring(current and current.writer)
        ))
      end
    end
  end
  self:ScheduleRebuild("comms " .. tostring(kind), 0.05)
end
