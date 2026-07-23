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
    for category, providerGUID in pairs(self.session.header or {}) do
      self:Send("A|" .. category .. "|" .. providerGUID)
    end
    for recipientGUID, categories in pairs(self.session.cells or {}) do
      for category, providerGUID in pairs(categories) do
        self:Send("X|" .. recipientGUID .. "|" .. category .. "|" .. providerGUID)
      end
    end
  end
end

function CBC:SendPreferences()
  local specID = self:GetLocalSpec()
  if not specID then return end
  local tokens = {}
  for index, category in ipairs(self.CategoryOrder) do
    tokens[#tokens+1] = index .. ":" .. self:GetPreference(self.rosterByGUID[UnitGUID("player")], category)
  end
  self:Send("P|" .. specID .. "|" .. table.concat(tokens,","))
end

function CBC:SendOverride(providerGUID, recipientGUID, category)
  self:Send("O|" .. providerGUID .. "|" .. recipientGUID .. "|" .. (category or "-"))
end

function CBC:SendCell(recipientGUID, category, providerGUID)
  self:Send("X|" .. recipientGUID .. "|" .. category .. "|" .. (providerGUID or "-"))
end

function CBC:SendHeader(category, providerGUID)
  self:Send("A|" .. category .. "|" .. (providerGUID or "-"))
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
    if tonumber(version) == self.protocol then
      provider.addon, provider.provisional = true, false
      specID = tonumber(specID)
      if self.specsByID[specID] then
        provider.specID, provider.specName = specID, self.specsByID[specID].name
      end
    end
  elseif kind == "C" then
    provider.addon, provider.provisional = true, false
    self:DecodeCapabilities(provider, payload)
  elseif kind == "P" then
    local specID, values = string.match(payload, "^(%d+)|(.+)$")
    specID = tonumber(specID)
    if self.specsByID[specID] then
      provider.specID, provider.specName, provider.preferences = specID, self.specsByID[specID].name, {}
      for token in string.gmatch(values or "", "[^,]+") do
        local index, weight = string.match(token, "^(%d+):(%d+)$")
        local category = index and self.CategoryOrder[tonumber(index)]
        if category then provider.preferences[category] = tonumber(weight) end
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
    local recipientGUID, category, providerGUID = string.match(payload, "^([^|]+)|([^|]+)|([^|]+)$")
    if recipientGUID and self:IsGlobalEditor(senderMember) and self.Categories[category] then
      self.session.cells[recipientGUID] = self.session.cells[recipientGUID] or {}
      self.session.cells[recipientGUID][category] = providerGUID ~= "-" and providerGUID or nil
      if providerGUID == UnitGUID("player") then
        local recipient = self.rosterByGUID[recipientGUID]
        self:Print(senderMember.shortName .. " assigned you " .. self.Categories[category].short .. " on " .. (recipient and recipient.shortName or "a player") .. ".")
      end
    end
  elseif kind == "A" then
    local category, providerGUID = string.match(payload, "^([^|]+)|([^|]+)$")
    if category and self:IsGlobalEditor(senderMember) and self.Categories[category] then
      self.session.header[category] = providerGUID ~= "-" and providerGUID or nil
      if providerGUID == UnitGUID("player") then
        self:Print(senderMember.shortName .. " assigned your Greater " .. self.Categories[category].label .. ".")
      end
    end
  end
  self:ScheduleRebuild("comms " .. tostring(kind), 0.05)
end
