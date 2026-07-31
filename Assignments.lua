local _, CBC = ...

local function IsRaid()
  return (GetNumRaidMembers and GetNumRaidMembers() or 0) > 0
end

local function ProviderSort(a, b)
  if a.score ~= b.score then return a.score > b.score end
  if a.cap.tier ~= b.cap.tier then return a.cap.tier < b.cap.tier end
  return (a.provider.name or a.provider.guid) < (b.provider.name or b.provider.guid)
end

local function SharedProviderAvailable(usedProviders, providerGUID, cap)
  if cap and cap.independent then return true end
  local used = usedProviders[providerGUID]
  if not used then return true end
  return cap and cap.sharedCastKey and used == cap.sharedCastKey
end

local function MarkProviderUsed(usedProviders, providerGUID, cap)
  if cap and not cap.independent then
    usedProviders[providerGUID] = cap.sharedCastKey or true
  end
end

local function AddSharedCastCells(self, cells, providerGUID, cap, source, occupiedCategories)
  if not cap or not cap.sharedCastKey then return end
  local provider = self.providers[providerGUID]
  for category, sibling in pairs(provider and provider.categories or {}) do
    if sibling.sharedCastKey == cap.sharedCastKey and sibling.single and not cells[category] then
      cells[category] = {providerGUID=providerGUID,source=source}
      if occupiedCategories then occupiedCategories[category] = true end
    end
  end
end

local function ExpandSharedCastCells(self, cells, occupiedCategories)
  local existing = {}
  for category, cell in pairs(cells) do
    existing[#existing+1] = {category=category,cell=cell}
  end
  for _, entry in ipairs(existing) do
    local provider = self.providers[entry.cell.providerGUID]
    local cap = provider and provider.categories and provider.categories[entry.category]
    AddSharedCastCells(self, cells, entry.cell.providerGUID, cap, entry.cell.source, occupiedCategories)
  end
end

function CBC:CategoryDemand(category)
  local demand = 0
  for _, recipient in ipairs(self.roster) do
    local best = 0
    for guid, provider in pairs(self.providers) do
      local member = self.rosterByGUID[guid]
      local cap = provider.categories and provider.categories[category]
      if member and member.online and cap and cap.greater then
        local score = self:GetCapabilityScore(recipient, cap, true) or 0
        if score > best then best = score end
      end
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

function CBC:BuildGreaterBaseline(demandByCategory)
  local greater, independent, usedProviders, usedCategories = {}, {}, {}, {}
  local function Assign(providerGUID, category, cap)
    if usedCategories[category] or not SharedProviderAvailable(usedProviders, providerGUID, cap) then return false end
    if cap.independent or usedProviders[providerGUID] then
      independent[category] = providerGUID
    else
      greater[providerGUID] = category
    end
    MarkProviderUsed(usedProviders, providerGUID, cap)
    usedCategories[category] = true
    return true
  end
  for category, providerGUID in pairs(self.session.header or {}) do
    local provider = self.providers[providerGUID]
    local cap = provider and provider.categories and provider.categories[category]
    if cap and cap.greater then Assign(providerGUID, category, cap) end
  end
  for providerGUID, provider in pairs(self.providers) do
    local category = provider.provisional and provider.observedCategory
    local cap = category and provider.categories and provider.categories[category]
    if cap and cap.greater then Assign(providerGUID, category, cap) end
  end
  local categories = {}
  for _, category in ipairs(self.CategoryOrder) do
    categories[#categories+1] = {
      key=category,
      demand=demandByCategory[category] or 0,
      order=self.Categories[category].order,
    }
  end
  table.sort(categories, function(a,b)
    if a.demand ~= b.demand then return a.demand > b.demand end
    return a.order < b.order
  end)
  for _, entry in ipairs(categories) do
    if not usedCategories[entry.key] and entry.demand > 0 then
      for _, choice in ipairs(self:GetProviderChoices(entry.key, true)) do
        if Assign(choice.guid, entry.key, choice.cap) then break end
      end
    end
  end
  return greater, independent
end

local function RemoveProviderFromCells(self, cells, providerGUID)
  local provider = self.providers[providerGUID]
  for category, cell in pairs(cells) do
    local cap = provider and provider.categories and provider.categories[category]
    if cell.providerGUID == providerGUID and not (cap and cap.independent) then cells[category] = nil end
  end
end

function CBC:FillAvailableAssignments(member, cells, baseline)
  local occupiedCategories, occupiedProviders = {}, {}
  for category, cell in pairs(cells) do
    occupiedCategories[category] = true
    local provider = self.providers[cell.providerGUID]
    local cap = provider and provider.categories and provider.categories[category]
    MarkProviderUsed(occupiedProviders, cell.providerGUID, cap)
  end
  local candidates = {}
  for guid, provider in pairs(self.providers) do
    local providerMember = self.rosterByGUID[guid]
    if providerMember and providerMember.online then
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
        local gain = cap.independent and score or (isBaseline and score or score - baselineScore)
        local threshold = tonumber(self.db.individualAssignmentThreshold) or 25
        local worthwhile = cap.independent or isBaseline or not baselineCategory or gain >= threshold
        if score > 0 and worthwhile and not occupiedCategories[category] and deliverable then
          candidates[#candidates+1] = {
            guid=guid,providerName=provider.name or guid,
            category=category,cap=cap,score=score,gain=gain,
            independent=cap.independent,
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
    if SharedProviderAvailable(occupiedProviders, candidate.guid, candidate.cap) and not occupiedCategories[candidate.category] then
      cells[candidate.category] = {providerGUID=candidate.guid,source="auto"}
      AddSharedCastCells(self, cells, candidate.guid, candidate.cap, "auto", occupiedCategories)
      MarkProviderUsed(occupiedProviders, candidate.guid, candidate.cap)
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
        if not cap.independent then RemoveProviderFromCells(self, cells, providerGUID) end
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
          if not cap.independent then RemoveProviderFromCells(self, cells, providerGUID) end
          cells[category] = {providerGUID=providerGUID,source="manual"}
        end
      end
    end
  end
end

function CBC:DeriveGreater(cellsByRecipient, baseline, independentBaseline, demandByCategory)
  local counts, result, usedProviders, usedCategories = {}, {}, {}, {}
  local function Assign(providerGUID, category, cap)
    if usedCategories[category] or not SharedProviderAvailable(usedProviders, providerGUID, cap) then return false end
    result[category] = providerGUID
    usedCategories[category] = true
    MarkProviderUsed(usedProviders, providerGUID, cap)
    return true
  end
  for _, cells in pairs(cellsByRecipient) do
    for category, cell in pairs(cells) do
      counts[cell.providerGUID] = counts[cell.providerGUID] or {}
      counts[cell.providerGUID][category] = (counts[cell.providerGUID][category] or 0) + 1
    end
  end
  for category, providerGUID in pairs(self.session.header or {}) do
    local provider = self.providers[providerGUID]
    local cap = provider and provider.categories and provider.categories[category]
    if cap and cap.greater then Assign(providerGUID, category, cap) end
  end
  local edges = {}
  for guid, provider in pairs(self.providers) do
    for category, count in pairs(counts[guid] or {}) do
      local cap = provider.categories and provider.categories[category]
      if cap and cap.greater then
        edges[#edges+1] = {
          guid=guid,providerName=provider.name or guid,category=category,count=count,
          demand=demandByCategory[category] or 0,
          tier=cap.tier,baseline=(baseline[guid] == category or independentBaseline[category] == guid) and 1 or 0,
          independent=cap.independent,
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
    local provider = self.providers[edge.guid]
    local cap = provider and provider.categories and provider.categories[edge.category]
    if cap then Assign(edge.guid, edge.category, cap) end
  end
  for guid, category in pairs(baseline) do
    local cap = self.providers[guid] and self.providers[guid].categories[category]
    if cap then Assign(guid, category, cap) end
  end
  for category, guid in pairs(independentBaseline) do
    local cap = self.providers[guid] and self.providers[guid].categories[category]
    if cap then Assign(guid, category, cap) end
  end
  return result
end

function CBC:BuildAssignments()
  local demandByCategory = {}
  for _, category in ipairs(self.CategoryOrder) do
    demandByCategory[category] = self:CategoryDemand(category)
  end
  local baseline, independentBaseline = self:BuildGreaterBaseline(demandByCategory)
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
      for category, providerGUID in pairs(independentBaseline) do
        if not occupied[category] then
          cells[category] = {providerGUID=providerGUID,source="greater"}
          occupied[category] = true
        end
      end
      ExpandSharedCastCells(self, cells, occupied)
    else
      self:FillAvailableAssignments(member, cells, baseline)
    end
  end
  self:ApplyOverrides(cellsByRecipient)
  for _, cells in pairs(cellsByRecipient) do
    ExpandSharedCastCells(self, cells)
  end
  if not raid then
    for _, member in ipairs(self.roster) do
      self:FillAvailableAssignments(member, cellsByRecipient[member.guid], baseline)
    end
  end
  local greaterByCategory = self:DeriveGreater(
    cellsByRecipient,
    baseline,
    independentBaseline,
    demandByCategory
  )
  local providerCategoriesByTarget, greaterCategoriesByProvider = {}, {}
  for recipientGUID, cells in pairs(cellsByRecipient) do
    for category, cell in pairs(cells) do
      providerCategoriesByTarget[cell.providerGUID] = providerCategoriesByTarget[cell.providerGUID] or {}
      providerCategoriesByTarget[cell.providerGUID][recipientGUID] =
        providerCategoriesByTarget[cell.providerGUID][recipientGUID] or {}
      providerCategoriesByTarget[cell.providerGUID][recipientGUID][category] = true
      cell.delivery = greaterByCategory[category] == cell.providerGUID and "greater" or "individual"
      if cell.delivery == "greater" then
        greaterCategoriesByProvider[cell.providerGUID] = greaterCategoriesByProvider[cell.providerGUID] or {}
        greaterCategoriesByProvider[cell.providerGUID][category] = true
      end
    end
  end
  self.assignment = {
    cells=cellsByRecipient,greaterByCategory=greaterByCategory,
    greaterCategoriesByProvider=greaterCategoriesByProvider,
    providerCategoriesByTarget=providerCategoriesByTarget,
    baseline=baseline,independentBaseline=independentBaseline,
  }
end

local function ActionSort(a,b)
  if a.priority ~= b.priority then return a.priority < b.priority end
  if a.targetName ~= b.targetName then return a.targetName < b.targetName end
  return a.category < b.category
end

function CBC:BuildActions(coverageReady)
  if not coverageReady then self:ScanAuras() end
  wipe(self.actions)
  local playerGUID = UnitGUID("player")
  local provider = self.providers[playerGUID]
  if not provider then return end
  local greaterCategories = self.assignment.greaterCategoriesByProvider[playerGUID] or {}
  local targets = self.assignment.providerCategoriesByTarget[playerGUID] or {}
  for greaterCategory in pairs(greaterCategories) do
    local cap = provider.categories and provider.categories[greaterCategory]
    if cap and cap.greater then
      local needed, expiring, firstState = false, false, nil
      for recipientGUID, categories in pairs(targets) do
        if categories[greaterCategory] then
          local state = self:CoverageState(recipientGUID, greaterCategory, cap, true)
          if state == "missing" or state == "weaker" then
            needed, firstState = true, state
            break
          elseif state == "expiring" then
            expiring = true
          end
        end
      end
      if needed or expiring then
        local id, name, rank, icon = self:GetCastSpell(cap, true)
        if id and name then
          self.actions[#self.actions+1] = {
            priority=needed and 1 or 5,mass=true,category=greaterCategory,cap=cap,
            spellID=id,spellName=name,rank=rank,icon=icon,
            unit="player",targetName="Raid",state=firstState or "expiring",
          }
        end
      end
    end
  end
  for recipientGUID, categories in pairs(targets) do
    for category in pairs(categories) do
      if not greaterCategories[category] then
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
  end
  local unique, byCast = {}, {}
  for _, action in ipairs(self.actions) do
    local castKey = table.concat({
      action.mass and "greater" or "single",
      tostring(action.spellID or action.spellName),
      tostring(action.targetGUID or action.unit or "player"),
    }, ":")
    local existing = byCast[castKey]
    if existing then
      existing.coveredCategories[action.category] = true
      if action.priority < existing.priority then
        existing.priority = action.priority
        existing.state = action.state
      end
    else
      action.coveredCategories = {[action.category]=true}
      byCast[castKey] = action
      unique[#unique+1] = action
    end
  end
  wipe(self.actions)
  for _, action in ipairs(unique) do self.actions[#self.actions+1] = action end
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
    if cap.single and not cap.independent then
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
  if not current then
    local assigned = self.assignment.providerCategoriesByTarget[playerGUID]
      and self.assignment.providerCategoriesByTarget[playerGUID][recipientGUID]
    for category in pairs(assigned or {}) do
      local cap = provider.categories[category]
      if cap and not cap.independent then current = category break end
    end
  end
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
