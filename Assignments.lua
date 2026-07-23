local _, CBC = ...

local function IsRaid()
  return (GetNumRaidMembers and GetNumRaidMembers() or 0) > 0
end

local function ProviderSort(a, b)
  if a.score ~= b.score then return a.score > b.score end
  if a.cap.tier ~= b.cap.tier then return a.cap.tier < b.cap.tier end
  return (a.provider.name or a.provider.guid) < (b.provider.name or b.provider.guid)
end

function CBC:CategoryDemand(category)
  local demand = 0
  for _, recipient in ipairs(self.roster) do
    local best = 0
    for _, choice in ipairs(self:GetProviderChoices(category, true, recipient)) do
      if choice.score > best then best = choice.score end
    end
    demand = demand + best
  end
  return demand
end

function CBC:GetProviderChoices(category, requireGreater, recipient)
  local choices = {}
  for guid, provider in pairs(self.providers) do
    local member = self.rosterByGUID[guid]
    local cap = provider.categories and provider.categories[category]
    if member and member.online and cap and (not requireGreater or cap.greater) then
      local score, source
      if recipient then
        score, source = self:GetCapabilityScore(recipient, cap, requireGreater)
      else
        score = 0
        for _, target in ipairs(self.roster) do
          score = score + (self:GetCapabilityScore(target, cap, requireGreater) or 0)
        end
        source = "group"
      end
      choices[#choices+1] = {
        guid=guid,provider=provider,member=member,cap=cap,
        score=score or 0,scoreSource=source,
      }
    end
  end
  table.sort(choices, ProviderSort)
  return choices
end

function CBC:BuildGreaterBaseline()
  local greater, usedProviders, usedCategories = {}, {}, {}
  for category, providerGUID in pairs(self.session.header or {}) do
    local provider = self.providers[providerGUID]
    local cap = provider and provider.categories and provider.categories[category]
    if cap and cap.greater and not usedProviders[providerGUID] and not usedCategories[category] then
      greater[providerGUID] = category
      usedProviders[providerGUID], usedCategories[category] = true, true
    end
  end
  for providerGUID, provider in pairs(self.providers) do
    local category = provider.provisional and provider.observedCategory
    local cap = category and provider.categories and provider.categories[category]
    if cap and cap.greater and not usedProviders[providerGUID] and not usedCategories[category] then
      greater[providerGUID] = category
      usedProviders[providerGUID], usedCategories[category] = true, true
    end
  end
  local categories = {}
  for _, category in ipairs(self.CategoryOrder) do
    categories[#categories+1] = {key=category,demand=self:CategoryDemand(category),order=self.Categories[category].order}
  end
  table.sort(categories, function(a,b)
    if a.demand ~= b.demand then return a.demand > b.demand end
    return a.order < b.order
  end)
  for _, entry in ipairs(categories) do
    if not usedCategories[entry.key] and entry.demand > 0 then
      for _, choice in ipairs(self:GetProviderChoices(entry.key, true)) do
        if not usedProviders[choice.guid] then
          greater[choice.guid] = entry.key
          usedProviders[choice.guid], usedCategories[entry.key] = true, true
          break
        end
      end
    end
  end
  return greater
end

local function RemoveProviderFromCells(cells, providerGUID)
  for category, cell in pairs(cells) do
    if cell.providerGUID == providerGUID then cells[category] = nil end
  end
end

function CBC:FillAvailableAssignments(member, cells, baseline)
  local occupiedCategories, occupiedProviders = {}, {}
  for category, cell in pairs(cells) do
    occupiedCategories[category] = true
    occupiedProviders[cell.providerGUID] = true
  end
  local candidates = {}
  for guid, provider in pairs(self.providers) do
    local providerMember = self.rosterByGUID[guid]
    if providerMember and providerMember.online and not occupiedProviders[guid] then
      for category, cap in pairs(provider.categories or {}) do
        local baselineCategory = baseline[guid]
        local deliverable = cap.single or (category == baselineCategory and cap.greater)
        local isBaseline = category == baselineCategory
        local score = self:GetCapabilityScore(member, cap, isBaseline and cap.greater ~= nil) or 0
        local baselineScore = 0
        if baselineCategory and provider.categories[baselineCategory] then
          local baselineCap = provider.categories[baselineCategory]
          baselineScore = self:GetCapabilityScore(member, baselineCap, baselineCap.greater ~= nil) or 0
        end
        local gain = isBaseline and score or score - baselineScore
        local threshold = tonumber(self.db.individualAssignmentThreshold) or 25
        local worthwhile = isBaseline or not baselineCategory or gain >= threshold
        if score > 0 and worthwhile and not occupiedCategories[category] and deliverable then
          candidates[#candidates+1] = {
            guid=guid,providerName=provider.name or guid,
            category=category,cap=cap,score=score,gain=gain,
            baseline=isBaseline and 1 or 0,
            order=self.Categories[category].order,
          }
        end
      end
    end
  end
  table.sort(candidates, function(a,b)
    if a.score ~= b.score then return a.score > b.score end
    if a.cap.tier ~= b.cap.tier then return a.cap.tier < b.cap.tier end
    if a.baseline ~= b.baseline then return a.baseline > b.baseline end
    if a.order ~= b.order then return a.order < b.order end
    return a.providerName < b.providerName
  end)
  for _, candidate in ipairs(candidates) do
    if not occupiedProviders[candidate.guid] and not occupiedCategories[candidate.category] then
      cells[candidate.category] = {providerGUID=candidate.guid,source="auto"}
      occupiedProviders[candidate.guid] = true
      occupiedCategories[candidate.category] = true
    end
  end
end

function CBC:ApplyOverrides(cellsByRecipient)
  for providerGUID, recipients in pairs(self.session.providerOverrides or {}) do
    local provider = self.providers[providerGUID]
    for recipientGUID, category in pairs(recipients) do
      local cells = cellsByRecipient[recipientGUID]
      local cap = category and provider and provider.categories and provider.categories[category]
      if cells and cap and cap.single then
        RemoveProviderFromCells(cells, providerGUID)
        cells[category] = {providerGUID=providerGUID,source="provider"}
      end
    end
  end
  for recipientGUID, categories in pairs(self.session.cells or {}) do
    local cells = cellsByRecipient[recipientGUID]
    if cells then
      for category, providerGUID in pairs(categories) do
        local provider = self.providers[providerGUID]
        local cap = provider and provider.categories and provider.categories[category]
        if cap and cap.single then
          RemoveProviderFromCells(cells, providerGUID)
          cells[category] = {providerGUID=providerGUID,source="manual"}
        end
      end
    end
  end
end

function CBC:DeriveGreater(cellsByRecipient, baseline)
  local counts, result, usedProviders, usedCategories = {}, {}, {}, {}
  for _, cells in pairs(cellsByRecipient) do
    for category, cell in pairs(cells) do
      counts[cell.providerGUID] = counts[cell.providerGUID] or {}
      counts[cell.providerGUID][category] = (counts[cell.providerGUID][category] or 0) + 1
    end
  end
  for category, providerGUID in pairs(self.session.header or {}) do
    local provider = self.providers[providerGUID]
    local cap = provider and provider.categories and provider.categories[category]
    if cap and cap.greater and not usedProviders[providerGUID] and not usedCategories[category] then
      result[providerGUID] = category
      usedProviders[providerGUID], usedCategories[category] = true, true
    end
  end
  local edges = {}
  for guid, provider in pairs(self.providers) do
    for category, count in pairs(counts[guid] or {}) do
      local cap = provider.categories and provider.categories[category]
      if cap and cap.greater then
        edges[#edges+1] = {
          guid=guid,providerName=provider.name or guid,category=category,count=count,demand=self:CategoryDemand(category),
          tier=cap.tier,baseline=(baseline[guid] == category) and 1 or 0,
          order=self.Categories[category].order,
        }
      end
    end
  end
  table.sort(edges, function(a,b)
    if a.count ~= b.count then return a.count > b.count end
    if a.demand ~= b.demand then return a.demand > b.demand end
    if a.tier ~= b.tier then return a.tier < b.tier end
    if a.baseline ~= b.baseline then return a.baseline > b.baseline end
    if a.providerName ~= b.providerName then return a.providerName < b.providerName end
    return a.order < b.order
  end)
  for _, edge in ipairs(edges) do
    if not usedProviders[edge.guid] and not usedCategories[edge.category] then
      result[edge.guid] = edge.category
      usedProviders[edge.guid], usedCategories[edge.category] = true, true
    end
  end
  for guid, category in pairs(baseline) do
    if not usedProviders[guid] and not usedCategories[category] then
      result[guid] = category
      usedProviders[guid], usedCategories[category] = true, true
    end
  end
  return result
end

function CBC:BuildAssignments()
  local baseline = self:BuildGreaterBaseline()
  local cellsByRecipient = {}
  local raid = IsRaid()
  for _, member in ipairs(self.roster) do
    local cells, occupied = {}, {}
    cellsByRecipient[member.guid] = cells
    if raid then
      for providerGUID, category in pairs(baseline) do
        if not occupied[category] then
          cells[category] = {providerGUID=providerGUID,source="greater"}
          occupied[category] = true
        end
      end
    else
      self:FillAvailableAssignments(member, cells, baseline)
    end
  end
  self:ApplyOverrides(cellsByRecipient)
  if not raid then
    for _, member in ipairs(self.roster) do
      self:FillAvailableAssignments(member, cellsByRecipient[member.guid], baseline)
    end
  end
  local greater = self:DeriveGreater(cellsByRecipient, baseline)
  local providerCategoryByTarget = {}
  for recipientGUID, cells in pairs(cellsByRecipient) do
    for category, cell in pairs(cells) do
      providerCategoryByTarget[cell.providerGUID] = providerCategoryByTarget[cell.providerGUID] or {}
      providerCategoryByTarget[cell.providerGUID][recipientGUID] = category
      cell.delivery = greater[cell.providerGUID] == category and "greater" or "individual"
    end
  end
  self.assignment = {
    cells=cellsByRecipient,greaterByProvider=greater,
    providerCategoryByTarget=providerCategoryByTarget,baseline=baseline,
  }
end

local function ActionSort(a,b)
  if a.priority ~= b.priority then return a.priority < b.priority end
  if a.targetName ~= b.targetName then return a.targetName < b.targetName end
  return a.category < b.category
end

function CBC:BuildActions()
  self:ScanAuras()
  wipe(self.actions)
  local playerGUID = UnitGUID("player")
  local provider = self.providers[playerGUID]
  if not provider then return end
  local greaterCategory = self.assignment.greaterByProvider[playerGUID]
  local greaterQueued = false
  local targets = self.assignment.providerCategoryByTarget[playerGUID] or {}
  if greaterCategory then
    local cap = provider.categories and provider.categories[greaterCategory]
    if cap and cap.greater then
      local needed, firstState = false, nil
      for recipientGUID, category in pairs(targets) do
        if category == greaterCategory then
          local state = self:CoverageState(recipientGUID, category, cap, true)
          if state == "missing" or state == "weaker" then needed, firstState = true, state break end
        end
      end
      if needed then
        local id, name, rank, icon = self:GetCastSpell(cap, true)
        if id and name then
          self.actions[#self.actions+1] = {
            priority=1,mass=true,category=greaterCategory,cap=cap,
            spellID=id,spellName=name,rank=rank,icon=icon,
            unit="player",targetName="Raid",state=firstState,
          }
          greaterQueued = true
        end
      end
    end
  end
  for recipientGUID, category in pairs(targets) do
    if category ~= greaterCategory then
      local member = self.rosterByGUID[recipientGUID]
      local cap = provider.categories and provider.categories[category]
      if member and cap and cap.single then
        local state, aura = self:CoverageState(recipientGUID, category, cap, false)
        if state == "missing" or state == "weaker" or state == "expiring" then
          local id, name, rank, icon = self:GetCastSpell(cap, false)
          if id and name then
            local source = self.assignment.cells[recipientGUID][category].source
            self.actions[#self.actions+1] = {
              priority=(state == "expiring" and 4 or (source == "manual" or source == "provider") and 2 or 3),
              mass=false,category=category,cap=cap,spellID=id,spellName=name,rank=rank,icon=icon,
              unit=member.unit,targetGUID=recipientGUID,targetName=member.name,state=state,
              dead=member.dead,online=member.online,source=source,aura=aura,
            }
          end
        end
      end
    end
  end
  if greaterCategory and not greaterQueued then
    local cap = provider.categories and provider.categories[greaterCategory]
    if cap and cap.greater then
      local expiring = false
      for recipientGUID, category in pairs(targets) do
        if category == greaterCategory then
          local state = self:CoverageState(recipientGUID, category, cap, true)
          if state == "expiring" then expiring = true break end
        end
      end
      if expiring then
        local id, name, rank, icon = self:GetCastSpell(cap, true)
        self.actions[#self.actions+1] = {
          priority=5,mass=true,category=greaterCategory,cap=cap,
          spellID=id,spellName=name,rank=rank,icon=icon,
          unit="player",targetName="Raid",state="expiring",
        }
      end
    end
  end
  table.sort(self.actions, ActionSort)
end

function CBC:SetProviderOverride(providerGUID, recipientGUID, category)
  if InCombatLockdown and InCombatLockdown() then self:Print("Assignments are locked in combat.") return false end
  if providerGUID ~= UnitGUID("player") then self:Print("Use the assignment matrix to edit another provider.") return false end
  self.session.providerOverrides[providerGUID] = self.session.providerOverrides[providerGUID] or {}
  if category then self.session.providerOverrides[providerGUID][recipientGUID] = category
  else self.session.providerOverrides[providerGUID][recipientGUID] = nil end
  self.session.revision = self.session.revision + 1
  if self.SendOverride then self:SendOverride(providerGUID, recipientGUID, category) end
  self:Rebuild("provider override")
  return true
end

function CBC:SetCellOverride(recipientGUID, category, providerGUID)
  if InCombatLockdown and InCombatLockdown() then self:Print("Assignments are locked in combat.") return false end
  if not self:IsGlobalEditor(self.rosterByGUID[UnitGUID("player")]) then self:Print("You cannot edit the shared matrix.") return false end
  local provider = self.providers[providerGUID]
  local cap = provider and provider.categories and provider.categories[category]
  if not self.rosterByGUID[recipientGUID] or not cap or not cap.single then
    self:Print("That provider cannot supply this individual buff.")
    return false
  end
  self.session.cells[recipientGUID] = self.session.cells[recipientGUID] or {}
  self.session.cells[recipientGUID][category] = providerGUID
  self.session.revision = self.session.revision + 1
  if self.SendCell then self:SendCell(recipientGUID, category, providerGUID) end
  self:Rebuild("cell override")
  local recipient = self.rosterByGUID[recipientGUID]
  self:Print(self:ShortName(provider.name) .. " assigned " .. self.Categories[category].label .. " to " .. recipient.shortName .. ".")
  return true
end

function CBC:ResetCellOverride(recipientGUID, category)
  if InCombatLockdown and InCombatLockdown() then self:Print("Assignments are locked in combat.") return false end
  if not self:IsGlobalEditor(self.rosterByGUID[UnitGUID("player")]) then self:Print("You cannot edit the shared matrix.") return false end
  if self.session.cells[recipientGUID] then self.session.cells[recipientGUID][category] = nil end
  self.session.revision = self.session.revision + 1
  if self.SendCell then self:SendCell(recipientGUID, category, nil) end
  self:Rebuild("cell reset")
  self:Print(self.Categories[category].label .. " reset to the optimal provider.")
  return true
end

function CBC:SetHeaderAssignment(category, providerGUID)
  if InCombatLockdown and InCombatLockdown() then self:Print("Assignments are locked in combat.") return false end
  if not self:IsGlobalEditor(self.rosterByGUID[UnitGUID("player")]) then self:Print("You cannot edit the shared matrix.") return false end
  if providerGUID then
    local provider = self.providers[providerGUID]
    local cap = provider and provider.categories and provider.categories[category]
    if not cap or not cap.greater then
      self:Print("That provider cannot supply this Greater buff.")
      return false
    end
  end
  self.session.header[category] = providerGUID
  self.session.revision = self.session.revision + 1
  if self.SendHeader then self:SendHeader(category, providerGUID) end
  self:Rebuild("header")
  if providerGUID then
    self:Print(self:ShortName(self.providers[providerGUID].name) .. " assigned Greater " .. self.Categories[category].label .. ".")
  else
    self:Print("Greater " .. self.Categories[category].label .. " reset to optimal.")
  end
  return true
end

function CBC:CycleLocalOverride(recipientGUID, delta)
  if InCombatLockdown and InCombatLockdown() then
    self:Print("Assignments are locked in combat.")
    return false
  end
  if not delta or delta == 0 then return false end
  local playerGUID = UnitGUID("player")
  local provider = self.providers[playerGUID]
  local member = self.rosterByGUID[recipientGUID]
  if not provider or not member then return false end
  local choices = {}
  for category, cap in pairs(provider.categories or {}) do
    if cap.single then
      choices[#choices+1] = {
        category=category,
        weight=self:GetCapabilityScore(member,cap,false) or 0,
        order=self.Categories[category].order,
      }
    end
  end
  table.sort(choices, function(a,b)
    if a.weight ~= b.weight then return a.weight > b.weight end
    return a.order < b.order
  end)
  if #choices == 0 then
    self:Print("You do not know any single-target provider buffs.")
    return false
  end
  if #choices == 1 then
    self:Print(member.shortName .. " has only one available buff: " .. self.Categories[choices[1].category].label .. ".")
    return false
  end
  local current = self.session.providerOverrides[playerGUID] and self.session.providerOverrides[playerGUID][recipientGUID]
  current = current or (self.assignment.providerCategoryByTarget[playerGUID] and self.assignment.providerCategoryByTarget[playerGUID][recipientGUID])
  local index = 1
  for i, choice in ipairs(choices) do if choice.category == current then index = i break end end
  index = ((index - 1 + (delta > 0 and -1 or 1)) % #choices) + 1
  local category = choices[index].category
  if self:SetProviderOverride(playerGUID, recipientGUID, category) then
    self:Print(member.shortName .. " assigned " .. self.Categories[category].label .. ".")
    return true, category
  end
  return false
end
