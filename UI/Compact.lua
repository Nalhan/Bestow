local _, CBC = ...

local ROW_HEIGHT, WIDTH = 30, 252

local function SetTopAnchoredHeight(frame, height)
  if frame.cbcTopAnchored or frame.cbcDragging then
    frame:SetHeight(height)
    return
  end
  local left, top = frame:GetLeft(), frame:GetTop()
  frame:SetHeight(height)
  if left and top then
    left, top = CBC.Pixel:Snap(left), CBC.Pixel:Snap(top)
    frame:ClearAllPoints()
    frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left, top)
    CBC.db.position = {"TOPLEFT", "BOTTOMLEFT", left, top}
    frame.cbcTopAnchored = true
  end
end

local function ConfigureSecureAction(button, action)
  if InCombatLockdown and InCombatLockdown() then return end
  button._cbcAction = action
  local signature = action and table.concat({
    tostring(action.spellID or ""),
    action.spellName or "",
    action.category or "",
    action.targetGUID or "",
    action.mass and "mass" or (action.unit or "player"),
  }, "|") or false
  if button._cbcActionSignature == signature then return end
  button._cbcActionSignature = signature
  button:SetAttribute("type", nil)
  button:SetAttribute("macrotext", nil)
  button:SetAttribute("spell", nil)
  button:SetAttribute("unit", nil)
  local secureSpell = action and (action.spellID or action.spellName)
  if not secureSpell then return end
  button:SetAttribute("type", "spell")
  button:SetAttribute("spell", secureSpell)
  button:SetAttribute("unit", action.mass and "player" or (action.unit or "player"))
end

local function TraceSecureClick(button)
  local action = button._cbcAction
  if not action then return end
  local visualRow = button._cbcVisualRow
  local visualGUID = visualRow and visualRow.recipientGUID
  local visualMember = visualGUID and CBC.rosterByGUID and CBC.rosterByGUID[visualGUID]
  local currentGUID = not action.mass and action.unit and UnitGUID(action.unit)
  CBC.lastSecureClick = {
    time=GetTime(),spellID=action.spellID,spellName=action.spellName,
    unit=action.unit,targetGUID=action.targetGUID,currentGUID=currentGUID,
    visualGUID=visualGUID,visualCategory=visualRow and visualRow.category,
  }
  CBC:Debug(string.format(
    "Secure click: spell=%s/%s category=%s unit=%s expectedGUID=%s currentGUID=%s target=%s mass=%s visualGUID=%s visualTarget=%s visualCategory=%s",
    tostring(action.spellID), tostring(action.spellName), tostring(action.category),
    tostring(action.unit), tostring(action.targetGUID), tostring(currentGUID),
    tostring(action.targetName), tostring(action.mass), tostring(visualGUID),
    tostring(visualMember and visualMember.name), tostring(visualRow and visualRow.category)
  ))
end

local secureTraceFrame = CreateFrame("Frame")
secureTraceFrame:RegisterEvent("UNIT_SPELLCAST_SENT")
secureTraceFrame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
secureTraceFrame:SetScript("OnEvent", function(_, event, ...)
  local trace = CBC.lastSecureClick
  if not trace or GetTime()-trace.time > 2 then return end
  local values = {}
  for index=1,select("#", ...) do values[index] = tostring(select(index, ...)) end
  if values[1] ~= "player" then return end
  if values[2] ~= tostring(trace.spellName) then return end
  CBC:Debug(string.format(
    "%s after secure click spell=%s/%s unit=%s expectedGUID=%s clickGUID=%s args=[%s]",
    event, tostring(trace.spellID), tostring(trace.spellName), tostring(trace.unit),
    tostring(trace.targetGUID), tostring(trace.currentGUID), table.concat(values, ", ")
  ))
end)

local function LockSecureHover(owner)
  CBC.compactSecureHover = owner
end

local function UnlockSecureHover(owner)
  if CBC.compactSecureHover == owner then CBC.compactSecureHover = nil end
end

function CBC:SyncSmartOverlay(action)
  local overlay, smart = self.smartSecureOverlay, self.compactFrame and self.compactFrame.smart
  if not overlay or not smart or (InCombatLockdown and InCombatLockdown()) then return end
  ConfigureSecureAction(overlay, action)
  overlay._cbcHasAction = action ~= nil
  local left, bottom = smart:GetLeft(), smart:GetBottom()
  if left and bottom then
    overlay:ClearAllPoints()
    overlay:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", self.Pixel:Snap(left), self.Pixel:Snap(bottom))
    overlay:SetWidth(smart:GetWidth())
    overlay:SetHeight(smart:GetHeight())
  end
  if action and smart:IsVisible() then overlay:EnableMouse(true); overlay:Show()
  else overlay:EnableMouse(false); overlay:Hide() end
end

function CBC:SyncRowOverlay(row, action)
  local overlay = row and row.secureOverlay
  if not overlay or (InCombatLockdown and InCombatLockdown()) then return end
  ConfigureSecureAction(overlay, action)
  overlay._cbcHasAction = action ~= nil
  local left, bottom = row:GetLeft(), row:GetBottom()
  if left and bottom then
    overlay:ClearAllPoints()
    overlay:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", self.Pixel:Snap(left), self.Pixel:Snap(bottom))
    overlay:SetWidth(row:GetWidth())
    overlay:SetHeight(row:GetHeight())
  end
  if action and row:IsVisible() then overlay:EnableMouse(true); overlay:Show()
  else overlay:EnableMouse(false); overlay:Hide() end
end

function CBC:SyncCombatGreaterOverlay(action)
  local overlay, smart = self.combatGreaterOverlay, self.compactFrame and self.compactFrame.smart
  if not overlay or not smart or (InCombatLockdown and InCombatLockdown()) then return end
  ConfigureSecureAction(overlay, action)
  overlay._cbcHasAction = action ~= nil
  overlay:EnableMouse(action ~= nil)
  local left, bottom = smart:GetLeft(), smart:GetBottom()
  if left and bottom then
    overlay:ClearAllPoints()
    overlay:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", self.Pixel:Snap(left), self.Pixel:Snap(bottom))
    overlay:SetWidth(smart:GetWidth())
    overlay:SetHeight(smart:GetHeight())
  end
  self.combatPreparedGreaterAction = action
end

function CBC:SyncCombatRowOverlay(row, action)
  local overlay = row and row.combatSecureOverlay
  if not overlay or (InCombatLockdown and InCombatLockdown()) then return end
  ConfigureSecureAction(overlay, action)
  overlay._cbcHasAction = action ~= nil
  overlay:EnableMouse(action ~= nil)
  local left, bottom = row:GetLeft(), row:GetBottom()
  if left and bottom then
    overlay:ClearAllPoints()
    overlay:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", self.Pixel:Snap(left), self.Pixel:Snap(bottom))
    overlay:SetWidth(row:GetWidth())
    overlay:SetHeight(row:GetHeight())
    if row.combatBlocker then
      row.combatBlocker:ClearAllPoints()
      row.combatBlocker:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", self.Pixel:Snap(left), self.Pixel:Snap(bottom))
      row.combatBlocker:SetWidth(row:GetWidth())
      row.combatBlocker:SetHeight(row:GetHeight())
    end
  end
end

function CBC:GetNextAction()
  local deferred
  for _, action in ipairs(self.actions) do
    local usable = not action.dead and action.online ~= false
    if usable and not action.mass and (
      not action.targetGUID or not action.unit or UnitGUID(action.unit) ~= action.targetGUID
    ) then
      usable = false
    end
    if usable and not action.mass and IsSpellInRange then
      local range = IsSpellInRange(action.spellName, action.unit)
      if range == 0 then usable = false end
    end
    if usable then return action end
    deferred = deferred or action
  end
  return nil, deferred
end

local function SetStatusColor(text, state)
  if state == "missing" or state == "weaker" then text:SetTextColor(1,0.28,0.24)
  elseif state == "expiring" then text:SetTextColor(1,0.68,0.15)
  elseif state == "stronger" or state == "covered" then text:SetTextColor(0.42,0.68,0.92)
  else text:SetTextColor(0.78,0.78,0.78) end
end

local function CycleRowOverride(row, delta)
  if not row or not row.recipientGUID then return end
  local provider = CBC.providers[UnitGUID("player")]
  local capability = provider and provider.categories and provider.categories[row.category]
  if capability and capability.independent then
    CBC:Print(CBC.Categories[row.category].label.." is independent and does not replace your other assigned buff.")
    return
  end
  local changed = CBC:CycleLocalOverride(row.recipientGUID, delta)
  if changed and row.recipientGUID and row.category then
    CBC:ShowProviderTooltip(row, row.recipientGUID, row.category)
  end
end

function CBC:CreateCompact()
  local frame = CreateFrame("Frame", "BestowCompact", UIParent)
  frame:SetWidth(WIDTH); frame:SetHeight(58)
  -- Clamping a dynamically growing frame makes the client move its top edge
  -- when the expanded rows approach the screen boundary. Keep the header
  -- absolutely stationary and let the recipient stack extend downward.
  frame:SetClampedToScreen(false)
  local point, relativePoint, x, y
  if #self.db.position >= 4 then
    point, relativePoint, x, y = unpack(self.db.position)
  else
    point, x, y = unpack(self.db.position)
    relativePoint = point
  end
  frame:SetPoint(point, UIParent, relativePoint, x, y)
  frame:SetMovable(true); frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self)
    if not InCombatLockdown or not InCombatLockdown() then
      self.cbcDragging = true
      self.cbcTopAnchored = false
      self:StartMoving()
    end
  end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    self.cbcDragging = false
    SetTopAnchoredHeight(self, self:GetHeight())
    CBC:UpdateCompact()
  end)
  frame:SetScript("OnEnter", function() CBC.compactHover = true; CBC:UpdateCompact() end)
  frame:SetScript("OnLeave", function() CBC.compactHover = false; CBC:ScheduleRebuild("hover leave",0.25) end)
  self.Pixel:Backdrop(frame, 0.78)
  self.compactFrame = frame
  SetTopAnchoredHeight(frame, 58)

  local title = frame:CreateFontString(nil, "OVERLAY")
  title:SetPoint("TOPLEFT", 7, -6); title:SetPoint("TOPRIGHT", -50, -6)
  title:SetHeight(16); title:SetJustifyH("LEFT")
  self:ApplyFont(title, 11, "")
  title:SetText("Bestow")
  frame.title = title

  local matrix = CreateFrame("Button", nil, frame)
  matrix:SetWidth(20); matrix:SetHeight(18); matrix:SetPoint("TOPRIGHT",-28,-3)
  matrix:SetNormalFontObject(GameFontNormalSmall); matrix:SetText("A")
  matrix:SetScript("OnClick", function() CBC:ToggleAssignmentPanel() end)
  self.Pixel:Button(matrix,0.45)

  local diagnostics = CreateFrame("Button", nil, frame)
  diagnostics:SetWidth(20); diagnostics:SetHeight(18); diagnostics:SetPoint("TOPRIGHT",-5,-3)
  diagnostics:SetNormalFontObject(GameFontNormalSmall); diagnostics:SetText("D")
  diagnostics:SetScript("OnClick", function() CBC:ShowDiagnostics() end)
  self.Pixel:Button(diagnostics,0.45)

  local smart = CreateFrame("Button", nil, frame)
  smart:SetHeight(32); smart:SetPoint("TOPLEFT",5,-24); smart:SetPoint("TOPRIGHT",-5,-24)
  self.Pixel:Button(smart,0.64)
  smart.icon = smart:CreateTexture(nil,"ARTWORK"); smart.icon:SetWidth(24); smart.icon:SetHeight(24); smart.icon:SetPoint("LEFT",4,0)
  smart.text = smart:CreateFontString(nil,"OVERLAY"); smart.text:SetPoint("LEFT",smart.icon,"RIGHT",6,0); smart.text:SetPoint("RIGHT",-5,0); smart.text:SetJustifyH("LEFT")
  self:ApplyFont(smart.text,11,"")
  local function SmartEnter(owner)
    CBC.compactHover=true; CBC:UpdateCompact(); LockSecureHover(owner)
    if smart.action then
      GameTooltip:SetOwner(owner,"ANCHOR_RIGHT")
      GameTooltip:SetText(smart.action.spellName)
      GameTooltip:AddLine(CBC.Categories[smart.action.category].label .. " -> " .. smart.action.targetName,1,1,1)
      GameTooltip:Show()
    end
  end
  local function SmartLeave(owner)
    UnlockSecureHover(owner)
    GameTooltip:Hide(); CBC.compactHover=false; CBC:ScheduleRebuild("hover leave",0.25)
  end
  smart:SetScript("OnEnter", SmartEnter)
  smart:SetScript("OnLeave", SmartLeave)
  frame.smart = smart

  local overlay = CreateFrame("Button", "BestowSmartSecure", UIParent, "SecureActionButtonTemplate")
  overlay:RegisterForClicks("LeftButtonUp")
  overlay:SetFrameStrata("DIALOG")
  overlay:SetScript("PreClick", TraceSecureClick)
  overlay:SetScript("PostClick", function(self)
    -- The smart button is expected to advance in place after each successful
    -- buff. Keeping its hover lock until OnLeave prevents aura-driven compact
    -- updates while the cursor remains stationary, leaving the completed
    -- action bound to the button and repeatedly casting on the old target.
    if not (InCombatLockdown and InCombatLockdown()) then
      UnlockSecureHover(self)
      CBC:ScheduleRebuild("smart secure click", 0.05)
    end
  end)
  overlay:SetScript("OnEnter", SmartEnter)
  overlay:SetScript("OnLeave", SmartLeave)
  overlay:SetScript("OnShow", function(self)
    if not self._cbcHasAction or not smart:IsVisible() then self:Hide() end
  end)
  if RegisterStateDriver then RegisterStateDriver(overlay, "visibility", "[combat] hide; show") end
  overlay:EnableMouse(false)
  overlay:Hide()
  self.smartSecureOverlay = overlay

  local combatGreater = CreateFrame("Button", "BestowCombatGreaterSecure", UIParent, "SecureActionButtonTemplate")
  combatGreater:RegisterForClicks("LeftButtonUp")
  combatGreater:SetFrameStrata("DIALOG")
  combatGreater:SetScript("PreClick", TraceSecureClick)
  combatGreater:SetScript("OnEnter", function(self)
    local action = self._cbcAction
    if action then
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(action.spellName)
      GameTooltip:AddLine("Prepared combat Greater: " .. CBC.Categories[action.category].label, 1, 1, 1)
      GameTooltip:Show()
    end
  end)
  combatGreater:SetScript("OnLeave", function() GameTooltip:Hide() end)
  if RegisterStateDriver then RegisterStateDriver(combatGreater, "visibility", "[combat] show; hide") end
  combatGreater:EnableMouse(false)
  combatGreater:Hide()
  self.combatGreaterOverlay = combatGreater

  local stack = CreateFrame("Frame", nil, frame)
  stack:SetWidth(WIDTH); stack:SetHeight(1)
  stack:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, 0)
  stack:EnableMouse(true)
  stack:SetScript("OnEnter", function() CBC.compactHover = true; CBC:UpdateCompact() end)
  stack:SetScript("OnLeave", function() CBC.compactHover = false; CBC:ScheduleRebuild("hover leave",0.25) end)
  stack:Hide()
  frame.stack = stack

  frame.rows = {}
  for i=1,80 do
    local row = CreateFrame("Button", nil, stack)
    row:SetHeight(ROW_HEIGHT); row:SetPoint("TOPLEFT",5,-(i-1)*ROW_HEIGHT); row:SetPoint("TOPRIGHT",-5,-(i-1)*ROW_HEIGHT)
    self.Pixel:Button(row,0.52)
    row:EnableMouse(true)
    row:EnableMouseWheel(true)
    row.icon = row:CreateTexture(nil,"ARTWORK"); row.icon:SetWidth(22); row.icon:SetHeight(22); row.icon:SetPoint("LEFT",4,0)
    row.name = row:CreateFontString(nil,"OVERLAY"); row.name:SetPoint("LEFT",row.icon,"RIGHT",5,6); row.name:SetWidth(148); row.name:SetJustifyH("LEFT")
    self:ApplyFont(row.name,10,"")
    row.status = row:CreateFontString(nil,"OVERLAY"); row.status:SetPoint("LEFT",row.icon,"RIGHT",5,-7); row.status:SetPoint("RIGHT",-5,-7); row.status:SetJustifyH("LEFT")
    self:ApplyFont(row.status,9,"")
    row:SetScript("OnMouseWheel", function(self, delta)
      CycleRowOverride(self, delta)
    end)
    row:SetScript("OnEnter", function(self)
      CBC.compactHover=true
      if self.recipientGUID then CBC:ShowProviderTooltip(self, self.recipientGUID, self.category) end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide(); CBC.compactHover=false; CBC:ScheduleRebuild("hover leave",0.25) end)

    local overlay = CreateFrame("Button", "BestowRowSecure" .. i, UIParent, "SecureActionButtonTemplate")
    overlay:RegisterForClicks("LeftButtonUp")
    overlay:EnableMouseWheel(true)
    overlay:SetFrameStrata("DIALOG")
    overlay._cbcVisualRow = row
    overlay:SetScript("PreClick", TraceSecureClick)
    overlay:SetScript("PostClick", function(self)
      -- Aura observation must be allowed to refresh or remove this recipient
      -- row after a click even if the pointer never leaves the overlay.
      if not (InCombatLockdown and InCombatLockdown()) then
        UnlockSecureHover(self)
        CBC:ScheduleRebuild("row secure click", 0.05)
      end
    end)
    overlay:SetScript("OnMouseWheel", function(_, delta)
      UnlockSecureHover(overlay)
      CycleRowOverride(row, delta)
      CBC:UpdateCompact()
      LockSecureHover(overlay)
    end)
    overlay:SetScript("OnEnter", function(self)
      CBC.compactHover = true
      LockSecureHover(self)
      if row.recipientGUID then CBC:ShowProviderTooltip(self, row.recipientGUID, row.category) end
    end)
    overlay:SetScript("OnLeave", function()
      UnlockSecureHover(overlay)
      GameTooltip:Hide(); CBC.compactHover=false; CBC:ScheduleRebuild("hover leave",0.25)
    end)
    overlay:SetScript("OnShow", function(self)
      if not self._cbcHasAction or not row:IsVisible() then self:Hide() end
    end)
    if RegisterStateDriver then RegisterStateDriver(overlay, "visibility", "[combat] hide; show") end
    overlay:EnableMouse(false)
    overlay:Hide()
    row.secureOverlay = overlay

    local combatOverlay = CreateFrame("Button", "BestowRowCombatSecure" .. i, UIParent, "SecureActionButtonTemplate")
    combatOverlay:RegisterForClicks("LeftButtonUp")
    combatOverlay:SetFrameStrata("DIALOG")
    combatOverlay:SetScript("PreClick", TraceSecureClick)
    combatOverlay:SetScript("OnEnter", function(self)
      CBC.compactHover = true
      if row.recipientGUID then CBC:ShowProviderTooltip(self, row.recipientGUID, row.category) end
    end)
    combatOverlay:SetScript("OnLeave", function()
      GameTooltip:Hide()
      CBC.compactHover = false
    end)
    if RegisterStateDriver then RegisterStateDriver(combatOverlay, "visibility", "[combat] show; hide") end
    combatOverlay:EnableMouse(false)
    combatOverlay:Hide()
    row.combatSecureOverlay = combatOverlay

    local blocker = CreateFrame("Button", nil, UIParent)
    blocker:SetFrameStrata("TOOLTIP")
    blocker:EnableMouse(true)
    blocker:SetScript("OnEnter", function(self)
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:SetText(self._cbcTitle or "Individual buff unavailable")
      GameTooltip:AddLine(
        self._cbcDetail or "This protected row is temporarily disabled.",
        1, 0.35, 0.3, true
      )
      GameTooltip:Show()
    end)
    blocker:SetScript("OnLeave", function() GameTooltip:Hide() end)
    blocker:Hide()
    row.combatBlocker = blocker
    frame.rows[i] = row
  end
end

function CBC:ShowProviderTooltip(owner, recipientGUID, category)
  GameTooltip:SetOwner(owner,"ANCHOR_RIGHT")
  GameTooltip:SetText(self.Categories[category].label)
  local recipient = self.rosterByGUID[recipientGUID]
  local localProvider = self.providers[UnitGUID("player")]
  local localCapability = localProvider and localProvider.categories and localProvider.categories[category]
  local choices = self:GetProviderChoices(category, false, recipient)
  for _, choice in ipairs(choices) do
    local _, _, _, icon = self:GetCastSpell(choice.cap, false)
    local marker = choice.guid == UnitGUID("player") and "|cffffffff[YOU]|r " or ""
    local cell = self.assignment.cells[recipientGUID] and self.assignment.cells[recipientGUID][category]
    if cell and cell.providerGUID == choice.guid then marker = marker .. "|cff4db8ff[ASSIGNED]|r " end
    GameTooltip:AddLine((icon and ("|T"..icon..":16|t ") or "") .. marker .. choice.member.shortName .. "  " .. choice.score .. "/100 (Tier " .. choice.cap.tier .. ")",1,1,1)
  end
  if InCombatLockdown and InCombatLockdown() then
    GameTooltip:AddLine("Assignments locked in combat", 1, 0.35, 0.3)
  elseif localCapability and localCapability.independent then
    GameTooltip:AddLine("Independent provider buff; does not replace your other assignment", 0.65, 0.8, 1, true)
  else
    GameTooltip:AddLine("Mouse wheel: change your assigned buff", 0.65, 0.8, 1)
  end
  GameTooltip:Show()
end

function CBC:BuildCompactRows()
  local rows = {}
  local playerGUID = UnitGUID("player")
  local targets = self.assignment.providerCategoriesByTarget[playerGUID] or {}
  local greater = self.assignment.greaterCategoriesByProvider[playerGUID] or {}
  local provider = self.providers[playerGUID]
  local actionByTargetCategory = {}
  for _, action in ipairs(self.actions) do
    if action.targetGUID then actionByTargetCategory[action.targetGUID..":"..action.category] = action end
  end
  for recipientGUID, categories in pairs(targets) do
    for category in pairs(categories) do
    if not greater[category] then
    local member = self.rosterByGUID[recipientGUID]
    local cap = provider and provider.categories and provider.categories[category]
    if member and cap then
      local state, aura = self:CoverageState(recipientGUID,category,cap,false)
      local action = actionByTargetCategory[recipientGUID..":"..category]
      rows[#rows+1] = {
        member=member,category=category,cap=cap,state=state,aura=aura,
        action=action,delivery="individual",
      }
    end
    end
    end
  end
  table.sort(rows,function(a,b)
    if a.member.name ~= b.member.name then return a.member.name < b.member.name end
    return a.category < b.category
  end)
  return rows
end

function CBC:BuildPreparedCombatRows()
  local rows = {}
  local playerGUID = UnitGUID("player")
  local provider = self.providers[playerGUID]
  for index, prepared in ipairs(self.combatPreparedRows or {}) do
    local member = self.rosterByGUID[prepared.recipientGUID] or prepared.member
    local cap = provider and provider.categories and provider.categories[prepared.category] or prepared.cap
    if member and cap then
      local state, aura = self:CoverageState(prepared.recipientGUID, prepared.category, cap, prepared.delivery == "greater")
      rows[index] = {
        member=member,category=prepared.category,cap=cap,state=state,aura=aura,
        action=nil,delivery=prepared.delivery,
        stale=not prepared.unit or UnitGUID(prepared.unit) ~= prepared.recipientGUID,
      }
    end
  end
  return rows
end

function CBC:UpdateCompact()
  local frame = self.compactFrame
  if not frame or not self.db.enabled then
    self.compactSecureHover = nil
    if frame then frame:Hide() end
    if not (InCombatLockdown and InCombatLockdown()) then
      self:SyncSmartOverlay(nil)
      self:SyncCombatGreaterOverlay(nil)
      if frame and frame.rows then
        for _, row in ipairs(frame.rows) do
          self:SyncRowOverlay(row, nil)
          self:SyncCombatRowOverlay(row, nil)
          if row.combatBlocker then row.combatBlocker:Hide() end
        end
      end
    end
    return
  end
  local inCombat = InCombatLockdown and InCombatLockdown()
  if inCombat then
    self.compactSecureHover = nil
  elseif self.compactSecureHover then
    return
  end
  local nextAction, deferred = self:GetNextAction()
  frame.smart.action = inCombat and nil or nextAction
  if inCombat then
    if self.smartSecureOverlay then self.smartSecureOverlay._cbcHasAction = false end
  end
  if inCombat then
    local preparedGreater = self.combatPreparedGreaterAction
    if preparedGreater then
      frame.smart.icon:SetTexture(preparedGreater.icon)
      frame.smart.text:SetText("|cffffaa33Combat Greater:|r " .. self.Categories[preparedGreater.category].short)
    else
      frame.smart.icon:SetTexture("Interface\\Icons\\Ability_Warrior_DefensiveStance")
      frame.smart.text:SetText("|cffffaa33Combat: no Greater prepared|r")
    end
  elseif nextAction then
    frame.smart.icon:SetTexture(nextAction.icon)
    frame.smart.text:SetText(self.Categories[nextAction.category].short .. " -> " .. self:ShortName(nextAction.targetName) .. "  |cff888888(" .. #self.actions .. ")|r")
  elseif deferred then
    frame.smart.icon:SetTexture(deferred.icon)
    frame.smart.text:SetText("|cffaaaaaaDeferred:|r " .. self.Categories[deferred.category].short .. " -> " .. self:ShortName(deferred.targetName))
  else
    frame.smart.icon:SetTexture("Interface\\Icons\\Spell_Holy_GreaterBlessingofKings")
    frame.smart.text:SetText("|cff66cc88All assigned buffs covered|r")
  end
  local greater = self.assignment.greaterCategoriesByProvider[UnitGUID("player")] or {}
  local greaterLabels = {}
  for _, category in ipairs(self.CategoryOrder) do
    if greater[category] then greaterLabels[#greaterLabels+1] = self.Categories[category].short end
  end
  frame.title:SetText("Bestow" .. (#greaterLabels > 0 and ("  |cff888888Greater: " .. table.concat(greaterLabels,",") .. "|r") or ""))

  local views = inCombat and self:BuildPreparedCombatRows() or self:BuildCompactRows()
  if not inCombat then
    self.combatPreparedRows = {}
    for index, view in ipairs(views) do
      if index > #frame.rows then break end
      if frame.rows[index].combatBlocker then frame.rows[index].combatBlocker:Hide() end
      self.combatPreparedRows[index] = {
        recipientGUID=view.member.guid,unit=view.member.unit,
        category=view.category,delivery=view.delivery,
        member=view.member,cap=view.cap,
      }
      self:SyncCombatRowOverlay(frame.rows[index], view.action)
    end
    for index=#views+1,#frame.rows do self:SyncCombatRowOverlay(frame.rows[index], nil) end

    local greaterAction
    local playerGUID = UnitGUID("player")
    local greaterCategory
    local greaterSet = self.assignment.greaterCategoriesByProvider[playerGUID] or {}
    for _, category in ipairs(self.CategoryOrder) do
      if greaterSet[category] then greaterCategory = category break end
    end
    local provider = self.providers[playerGUID]
    local cap = greaterCategory and provider and provider.categories and provider.categories[greaterCategory]
    if cap and cap.greater then
      local id, name, rank, icon = self:GetCastSpell(cap, true)
      if id and name then
        greaterAction = {
          priority=1,mass=true,category=greaterCategory,cap=cap,
          spellID=id,spellName=name,rank=rank,icon=icon,
          unit="player",targetName="Raid",state="prepared",
        }
      end
    end
    self:SyncCombatGreaterOverlay(greaterAction)
  end
  local shown = 0
  frame.stack:Show()
  for _, view in ipairs(views) do
    local actionable = view.action ~= nil
    local hoverVisible = self.db.showMode == "HOVER" and self.compactHover
    local stateVisible = actionable and (
      ((view.state == "missing" or view.state == "weaker") and self.db.revealMissing)
      or (view.state == "expiring" and self.db.revealExpiring)
    )
    local visible = inCombat or self.db.showMode == "ALWAYS" or hoverVisible or stateVisible
    if visible then
      shown = shown + 1
      local row = frame.rows[shown]
      local _, spellName = self:GetCastSpell(view.cap, false)
      local distanceState, distanceDetail = self:GetIndividualDistanceState(view.member, spellName)
      local actionMatchesTarget = view.action
        and view.action.targetGUID == view.member.guid
        and view.action.unit
        and UnitGUID(view.action.unit) == view.member.guid
      local rowAction = not inCombat and distanceState == "in-range"
        and not view.member.dead and view.member.online ~= false
        and actionMatchesTarget and view.action or nil
      row.recipientGUID, row.category, row.action = view.member.guid, view.category, rowAction
      if inCombat then
        if row.secureOverlay then row.secureOverlay._cbcHasAction = false end
      end
      local _, _, _, icon = self:GetCastSpell(view.cap, false)
      row.icon:SetTexture(icon)
      row.name:SetText("|cff"..self:ClassHex(view.member.classToken)..view.member.shortName.."|r"..(self.db.showSpecs and view.member.specName and (" |cff777777"..view.member.specName.."|r") or ""))
      if row.combatBlocker then row.combatBlocker:Hide() end
      if inCombat and view.stale then
        if row.icon.SetDesaturated then row.icon:SetDesaturated(true) end
        row.status:SetText("STALE TARGET  " .. self.Categories[view.category].short)
        row.status:SetTextColor(1,0.15,0.15)
        if row.combatBlocker then
          row.combatBlocker._cbcTitle = "Combat target changed"
          row.combatBlocker._cbcDetail = "This protected row is disabled until combat ends so it cannot cast on the wrong unit."
          row.combatBlocker:Show()
        end
      elseif view.member.dead then
        if row.icon.SetDesaturated then row.icon:SetDesaturated(true) end
        row.status:SetText("DEAD  "..self.Categories[view.category].short); row.status:SetTextColor(1,0.15,0.15)
      elseif distanceState == "offline" then
        if row.icon.SetDesaturated then row.icon:SetDesaturated(true) end
        row.status:SetText("OFFLINE  "..self.Categories[view.category].short)
        row.status:SetTextColor(0.55,0.55,0.55)
        if inCombat and row.combatBlocker then
          row.combatBlocker._cbcTitle = "Player offline"
          row.combatBlocker._cbcDetail = "This individual buff cannot be cast while the player is offline."
          row.combatBlocker:Show()
        end
      elseif distanceState == "remote" then
        if row.icon.SetDesaturated then row.icon:SetDesaturated(true) end
        local remoteLabel = distanceDetail and distanceDetail ~= "" and distanceDetail or "VERY FAR"
        row.status:SetText("REMOTE  "..remoteLabel)
        row.status:SetTextColor(0.55,0.62,0.72)
        if inCombat and row.combatBlocker then
          row.combatBlocker._cbcTitle = "Player is very far away"
          row.combatBlocker._cbcDetail = distanceDetail or "The player may be in another zone."
          row.combatBlocker:Show()
        end
      elseif distanceState == "out-of-range" then
        if row.icon.SetDesaturated then row.icon:SetDesaturated(true) end
        row.status:SetText("OUT OF RANGE  "..self.Categories[view.category].short)
        row.status:SetTextColor(1,0.55,0.18)
        if inCombat and row.combatBlocker then
          row.combatBlocker._cbcTitle = "Player is out of range"
          row.combatBlocker._cbcDetail = "Move into buff range to enable this protected button."
          row.combatBlocker:Show()
        end
      else
        if row.icon.SetDesaturated then row.icon:SetDesaturated(false) end
        local duration = view.aura and self:FormatDuration(view.aura.expires) or ""
        local delivery = view.delivery == "greater" and "G" or "I"
        row.status:SetText(self.Categories[view.category].short .. "  " .. delivery .. "  " .. string.upper(view.state) .. (duration ~= "" and ("  "..duration) or ""))
        SetStatusColor(row.status,view.state)
      end
      row:Show()
      if not inCombat then self:SyncRowOverlay(row, rowAction) end
    end
  end
  for i=shown+1,#frame.rows do
    if inCombat then
      if frame.rows[i].secureOverlay then frame.rows[i].secureOverlay._cbcHasAction = false end
    else
      self:SyncRowOverlay(frame.rows[i], nil)
    end
    if frame.rows[i].combatBlocker then frame.rows[i].combatBlocker:Hide() end
    frame.rows[i]:Hide()
  end
  if shown > 0 then
    frame.stack:SetHeight(shown * ROW_HEIGHT)
    frame.stack:Show()
  else
    frame.stack:SetHeight(1)
    frame.stack:Hide()
  end
  frame:Show()
  if not inCombat then self:SyncSmartOverlay(nextAction) end
end

function CBC:UpdateDurations()
  if self.compactFrame and self.compactFrame:IsShown() then self:UpdateCompact() end
end

function CBC:CreateUI()
  self:CreateCompact()
  self:CreateAssignmentPanel()
  self:CreateDiagnostics()
  self:CreateOptions()
end
