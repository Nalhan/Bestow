local _, CBC = ...

local ROW_HEIGHT, WIDTH = 30, 292

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
  local signature = action and table.concat({
    action.spellName or "", action.mass and "mass" or (action.unit or "player")
  }, "|") or false
  if button._cbcActionSignature == signature then return end
  button._cbcActionSignature = signature
  button._cbcAction = action
  button:SetAttribute("type", nil)
  button:SetAttribute("macrotext", nil)
  button:SetAttribute("spell", nil)
  button:SetAttribute("unit", nil)
  if not action or not action.spellName then return end
  button:SetAttribute("type", "spell")
  button:SetAttribute("spell", action.spellName)
  button:SetAttribute("unit", action.mass and "player" or (action.unit or "player"))
end

local function SecurePreClick(button)
  local action = button._cbcAction
  if not action or action.mass or not IsSpellInRange then return end
  if IsSpellInRange(action.spellName, action.unit) == 0 then
    button._cbcRangeBlocked = true
    button:SetAttribute("type", nil)
  end
end

local function SecurePostClick(button)
  if not button._cbcRangeBlocked then return end
  button._cbcRangeBlocked = nil
  button._cbcActionSignature = nil
  ConfigureSecureAction(button, button._cbcAction)
  CBC:Print("Target is out of range.")
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

function CBC:GetNextAction()
  local deferred
  for _, action in ipairs(self.actions) do
    local usable = not action.dead and action.online ~= false
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
    CBC.compactHover=true; CBC:UpdateCompact()
    if smart.action then
      GameTooltip:SetOwner(owner,"ANCHOR_RIGHT")
      GameTooltip:SetText(smart.action.spellName)
      GameTooltip:AddLine(CBC.Categories[smart.action.category].label .. " -> " .. smart.action.targetName,1,1,1)
      GameTooltip:Show()
    end
  end
  local function SmartLeave()
    GameTooltip:Hide(); CBC.compactHover=false; CBC:ScheduleRebuild("hover leave",0.25)
  end
  smart:SetScript("OnEnter", SmartEnter)
  smart:SetScript("OnLeave", SmartLeave)
  frame.smart = smart

  local overlay = CreateFrame("Button", "BestowSmartSecure", UIParent, "SecureActionButtonTemplate")
  overlay:RegisterForClicks("AnyUp")
  overlay:SetFrameStrata("DIALOG")
  overlay:SetScript("PreClick", SecurePreClick)
  overlay:SetScript("PostClick", SecurePostClick)
  overlay:SetScript("OnEnter", SmartEnter)
  overlay:SetScript("OnLeave", SmartLeave)
  overlay:SetScript("OnShow", function(self)
    if not self._cbcHasAction or not smart:IsVisible() then self:Hide() end
  end)
  if RegisterStateDriver then RegisterStateDriver(overlay, "visibility", "[combat] hide; show") end
  overlay:EnableMouse(false)
  overlay:Hide()
  self.smartSecureOverlay = overlay

  local stack = CreateFrame("Frame", nil, frame)
  stack:SetWidth(WIDTH); stack:SetHeight(1)
  stack:SetPoint("TOPLEFT", frame, "BOTTOMLEFT", 0, 0)
  stack:EnableMouse(true)
  stack:SetScript("OnEnter", function() CBC.compactHover = true; CBC:UpdateCompact() end)
  stack:SetScript("OnLeave", function() CBC.compactHover = false; CBC:ScheduleRebuild("hover leave",0.25) end)
  stack:Hide()
  frame.stack = stack

  frame.rows = {}
  for i=1,40 do
    local row = CreateFrame("Button", nil, stack)
    row:SetHeight(ROW_HEIGHT); row:SetPoint("TOPLEFT",5,-(i-1)*ROW_HEIGHT); row:SetPoint("TOPRIGHT",-5,-(i-1)*ROW_HEIGHT)
    self.Pixel:Button(row,0.52)
    row:EnableMouseWheel(true)
    row.icon = row:CreateTexture(nil,"ARTWORK"); row.icon:SetWidth(22); row.icon:SetHeight(22); row.icon:SetPoint("LEFT",4,0)
    row.name = row:CreateFontString(nil,"OVERLAY"); row.name:SetPoint("LEFT",row.icon,"RIGHT",5,6); row.name:SetWidth(148); row.name:SetJustifyH("LEFT")
    self:ApplyFont(row.name,10,"")
    row.status = row:CreateFontString(nil,"OVERLAY"); row.status:SetPoint("LEFT",row.icon,"RIGHT",5,-7); row.status:SetPoint("RIGHT",-5,-7); row.status:SetJustifyH("LEFT")
    self:ApplyFont(row.status,9,"")
    row:SetScript("OnMouseWheel", function(self, delta)
      if self.recipientGUID then CBC:CycleLocalOverride(self.recipientGUID, delta) end
    end)
    row:SetScript("OnEnter", function(self)
      CBC.compactHover=true
      if self.recipientGUID then CBC:ShowProviderTooltip(self, self.recipientGUID, self.category) end
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide(); CBC.compactHover=false; CBC:ScheduleRebuild("hover leave",0.25) end)

    local overlay = CreateFrame("Button", "BestowRowSecure" .. i, UIParent, "SecureActionButtonTemplate")
    overlay:RegisterForClicks("AnyUp")
    overlay:EnableMouseWheel(true)
    overlay:SetFrameStrata("DIALOG")
    overlay:SetScript("PreClick", SecurePreClick)
    overlay:SetScript("PostClick", SecurePostClick)
    overlay:SetScript("OnMouseWheel", function(_, delta)
      if row.recipientGUID then CBC:CycleLocalOverride(row.recipientGUID, delta) end
    end)
    overlay:SetScript("OnEnter", function(self)
      CBC.compactHover = true
      CBC:UpdateCompact()
      if row.recipientGUID then CBC:ShowProviderTooltip(self, row.recipientGUID, row.category) end
    end)
    overlay:SetScript("OnLeave", function()
      GameTooltip:Hide(); CBC.compactHover=false; CBC:ScheduleRebuild("hover leave",0.25)
    end)
    overlay:SetScript("OnShow", function(self)
      if not self._cbcHasAction or not row:IsVisible() then self:Hide() end
    end)
    if RegisterStateDriver then RegisterStateDriver(overlay, "visibility", "[combat] hide; show") end
    overlay:EnableMouse(false)
    overlay:Hide()
    row.secureOverlay = overlay
    frame.rows[i] = row
  end
end

function CBC:ShowProviderTooltip(owner, recipientGUID, category)
  GameTooltip:SetOwner(owner,"ANCHOR_RIGHT")
  GameTooltip:SetText(self.Categories[category].label)
  local choices = self:GetProviderChoices(category, false)
  for _, choice in ipairs(choices) do
    local _, _, _, icon = self:GetCastSpell(choice.cap, false)
    local marker = choice.guid == UnitGUID("player") and "|cffffffff[YOU]|r " or ""
    local cell = self.assignment.cells[recipientGUID] and self.assignment.cells[recipientGUID][category]
    if cell and cell.providerGUID == choice.guid then marker = marker .. "|cff4db8ff[ASSIGNED]|r " end
    GameTooltip:AddLine((icon and ("|T"..icon..":16|t ") or "") .. marker .. choice.member.shortName .. "  Tier " .. choice.cap.tier,1,1,1)
  end
  GameTooltip:Show()
end

function CBC:BuildCompactRows()
  local rows = {}
  local playerGUID = UnitGUID("player")
  local targets = self.assignment.providerCategoryByTarget[playerGUID] or {}
  local greater = self.assignment.greaterByProvider[playerGUID]
  local actionByRecipient = {}
  for _, action in ipairs(self.actions) do if action.targetGUID then actionByRecipient[action.targetGUID] = action end end
  for recipientGUID, category in pairs(targets) do
    if category ~= greater then
      local member = self.rosterByGUID[recipientGUID]
      local provider = self.providers[playerGUID]
      local cap = provider and provider.categories and provider.categories[category]
      if member and cap then
        local state, aura = self:CoverageState(recipientGUID,category,cap,false)
        rows[#rows+1] = {member=member,category=category,cap=cap,state=state,aura=aura,action=actionByRecipient[recipientGUID]}
      end
    end
  end
  table.sort(rows,function(a,b)
    local ap = a.action and a.action.priority or 99
    local bp = b.action and b.action.priority or 99
    if ap ~= bp then return ap < bp end
    return a.member.name < b.member.name
  end)
  return rows
end

function CBC:UpdateCompact()
  local frame = self.compactFrame
  if not frame or not self.db.enabled then
    if frame then frame:Hide() end
    if not (InCombatLockdown and InCombatLockdown()) then
      self:SyncSmartOverlay(nil)
      if frame and frame.rows then
        for _, row in ipairs(frame.rows) do self:SyncRowOverlay(row, nil) end
      end
    end
    return
  end
  local inCombat = InCombatLockdown and InCombatLockdown()
  local nextAction, deferred = self:GetNextAction()
  frame.smart.action = inCombat and nil or nextAction
  if inCombat then
    if self.smartSecureOverlay then self.smartSecureOverlay._cbcHasAction = false end
  end
  if inCombat then
    frame.smart.icon:SetTexture("Interface\\Icons\\Ability_Warrior_DefensiveStance")
    frame.smart.text:SetText("|cffffaa33Combat: monitoring only|r")
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
  local greater = self.assignment.greaterByProvider[UnitGUID("player")]
  frame.title:SetText("Bestow" .. (greater and ("  |cff888888Greater: " .. self.Categories[greater].short .. "|r") or ""))

  local views = self:BuildCompactRows()
  local shown = 0
  frame.stack:Show()
  for _, view in ipairs(views) do
    local actionable = view.action ~= nil
    local hoverVisible = self.db.showMode == "HOVER" and self.compactHover
    local stateVisible = actionable and (
      ((view.state == "missing" or view.state == "weaker") and self.db.revealMissing)
      or (view.state == "expiring" and self.db.revealExpiring)
    )
    local visible = self.db.showMode == "ALWAYS" or hoverVisible or stateVisible
    if visible then
      shown = shown + 1
      local row = frame.rows[shown]
      local rowAction = not inCombat and not view.member.dead and view.member.online ~= false and view.action or nil
      row.recipientGUID, row.category, row.action = view.member.guid, view.category, rowAction
      if inCombat then
        if row.secureOverlay then row.secureOverlay._cbcHasAction = false end
      end
      local _, _, _, icon = self:GetCastSpell(view.cap, false)
      row.icon:SetTexture(icon)
      row.name:SetText("|cff"..self:ClassHex(view.member.classToken)..view.member.shortName.."|r"..(self.db.showSpecs and view.member.specName and (" |cff777777"..view.member.specName.."|r") or ""))
      if view.member.dead then
        if row.icon.SetDesaturated then row.icon:SetDesaturated(true) end
        row.status:SetText("DEAD  "..self.Categories[view.category].short); row.status:SetTextColor(1,0.15,0.15)
      else
        if row.icon.SetDesaturated then row.icon:SetDesaturated(false) end
        local duration = view.aura and self:FormatDuration(view.aura.expires) or ""
        row.status:SetText(self.Categories[view.category].short .. "  " .. string.upper(view.state) .. (duration ~= "" and ("  "..duration) or ""))
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
