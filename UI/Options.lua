local _, CBC = ...

local displayModes = {
  {value="HOVER", text="Hover"},
  {value="ALWAYS", text="Always expanded (default)"},
  {value="COLLAPSED", text="Always collapsed"},
}

local statWeightOrder = CBC.StatWeightKeys

local function GetDisplayModeText(value)
  for _, entry in ipairs(displayModes) do
    if entry.value == value then return entry.text end
  end
  return displayModes[2].text
end

local function FormatWeight(value)
  if value == math.floor(value) then return tostring(value) end
  local text = string.format("%.4f", value)
  text = string.gsub(text, "0+$", "")
  return string.gsub(text, "%.$", "")
end

local function SetVisible(widget, visible)
  if visible then widget:Show() else widget:Hide() end
end

local function AddCheck(panel, key, text, y, x)
  local name = "BestowOption" .. key
  local check = CreateFrame("CheckButton", name, panel, "InterfaceOptionsCheckButtonTemplate")
  check:SetPoint("TOPLEFT", x or 18, y)
  local label = _G[name .. "Text"]
  if label then CBC:ApplyFont(label, 11, ""); label:SetText(text) end
  check:SetScript("OnClick", function(self)
    local enabled = self:GetChecked() and true or false
    if key == "debugEnabled" then
      CBC:SetDebugEnabled(enabled)
    elseif key == "profilingEnabled" then
      if enabled then CBC:EnableProfiler() else CBC:DisableProfiler() end
    else
      CBC.db[key] = enabled
      CBC:Rebuild("option " .. key)
    end
  end)
  panel.checks[key] = check
  return check
end

local function CreateSectionHeader(panel, titleText, y)
  local header = panel:CreateFontString(nil, "ARTWORK")
  header:SetPoint("TOPLEFT", 16, y)
  CBC:ApplyFont(header, 11, "")
  header:SetText("|cffffcc00" .. titleText .. "|r")

  local line = panel:CreateTexture(nil, "ARTWORK")
  line:SetPoint("TOPLEFT", 16, y - 16)
  line:SetPoint("TOPRIGHT", -24, y - 16)
  line:SetHeight(1)
  line:SetTexture(0.3, 0.3, 0.3, 0.6)
  return header, line
end

function CBC:CreateOptions()
  if not InterfaceOptions_AddCategory then return end
  local panel = CreateFrame("Frame", "BestowOptions")
  panel.name = "Bestow"
  panel.checks = {}

  local title = panel:CreateFontString(nil, "ARTWORK")
  title:SetPoint("TOPLEFT", 16, -16)
  self:ApplyFont(title, 15, "")
  title:SetText("Bestow Configuration")

  local subtitle = panel:CreateFontString(nil, "ARTWORK")
  subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
  subtitle:SetTextColor(0.78, 0.78, 0.78)
  self:ApplyFont(subtitle, 10, "")
  subtitle:SetText("Coordinates mutually exclusive class buffs for Conquest of Azeroth. (Assignment changes disabled in combat)")

  ---------------------------------------------------------
  -- Section 1: Display & Recipient Stack
  ---------------------------------------------------------
  CreateSectionHeader(panel, "Panel & Recipient Stack", -64)

  local modeLabel = panel:CreateFontString(nil, "ARTWORK")
  modeLabel:SetPoint("TOPLEFT", 18, -88)
  self:ApplyFont(modeLabel, 10, "")
  modeLabel:SetText("Recipient stack display mode:")

  local mode = CreateFrame("Frame", "BestowDisplayMode", panel, "UIDropDownMenuTemplate")
  mode:SetPoint("TOPLEFT", 4, -102)
  UIDropDownMenu_SetWidth(mode, 180)
  local modeText = _G[mode:GetName() .. "Text"]
  if modeText then self:ApplyFont(modeText, 10, "") end
  UIDropDownMenu_Initialize(mode, function()
    for _, entry in ipairs(displayModes) do
      local value, text = entry.value, entry.text
      local info = UIDropDownMenu_CreateInfo()
      info.text = text
      info.value = value
      info.checked = CBC.db.showMode == value
      info.func = function()
        CBC.db.showMode = value
        UIDropDownMenu_SetSelectedValue(mode, value)
        UIDropDownMenu_SetText(mode, text)
        CBC:Rebuild("display mode")
      end
      UIDropDownMenu_AddButton(info)
    end
  end)
  UIDropDownMenu_SetSelectedValue(mode, CBC.db and CBC.db.showMode)
  UIDropDownMenu_SetText(mode, GetDisplayModeText(CBC.db and CBC.db.showMode))
  panel.mode = mode

  AddCheck(panel, "showSpecs", "Show specialization names in recipient rows", -144)
  AddCheck(panel, "revealMissing", "Automatically reveal missing or weaker buffs", -170)
  AddCheck(panel, "revealExpiring", "Automatically reveal buffs nearing expiration", -196)

  ---------------------------------------------------------
  -- Section 2: Assignment Rules
  ---------------------------------------------------------
  CreateSectionHeader(panel, "Assignment Optimization", -234)

  local thresholdHint = panel:CreateFontString(nil, "ARTWORK")
  thresholdHint:SetPoint("TOPLEFT", 18, -258)
  thresholdHint:SetTextColor(0.68, 0.68, 0.68)
  self:ApplyFont(thresholdHint, 9, "")
  thresholdHint:SetText("Minimum score gain required before assigning a single-target override in party play:")

  local threshold = CreateFrame("Slider", "BestowIndividualThreshold", panel, "OptionsSliderTemplate")
  threshold:SetPoint("TOPLEFT", 22, -278)
  threshold:SetWidth(220); threshold:SetHeight(16)
  threshold:SetMinMaxValues(0, 100); threshold:SetValueStep(5)
  _G[threshold:GetName().."Low"]:SetText("0")
  _G[threshold:GetName().."High"]:SetText("100")
  local thresholdText = _G[threshold:GetName().."Text"]
  self:ApplyFont(thresholdText, 10, "")
  threshold:SetScript("OnValueChanged", function(self, value)
    value = math.floor(value / 5 + 0.5) * 5
    thresholdText:SetText("Minimum individual gain: " .. value .. " pts")
    if CBC.db and CBC.db.individualAssignmentThreshold ~= value then
      CBC.db.individualAssignmentThreshold = value
      CBC:Rebuild("individual threshold")
    end
  end)
  panel.threshold = threshold

  local diagnosticsLabel = panel:CreateFontString(nil, "ARTWORK")
  diagnosticsLabel:SetPoint("TOPLEFT", 300, -258)
  diagnosticsLabel:SetTextColor(0.68, 0.68, 0.68)
  self:ApplyFont(diagnosticsLabel, 9, "")
  diagnosticsLabel:SetText("Diagnostics (disabled by default):")
  AddCheck(panel, "debugEnabled", "Enable debug logging", -274, 300)
  AddCheck(panel, "profilingEnabled", "Enable performance profiling", -298, 300)

  ---------------------------------------------------------
  -- Section 3: Appearance & Scale
  ---------------------------------------------------------
  CreateSectionHeader(panel, "Appearance & Scale", -326)

  local fontLabel = panel:CreateFontString(nil, "ARTWORK")
  fontLabel:SetPoint("TOPLEFT", 18, -350)
  self:ApplyFont(fontLabel, 10, "")
  fontLabel:SetText("Global font family (LibSharedMedia):")

  local font = CreateFrame("Frame", "BestowFontMenu", panel, "UIDropDownMenuTemplate")
  font:SetPoint("TOPLEFT", 4, -364)
  UIDropDownMenu_SetWidth(font, 220)
  local fontText = _G[font:GetName() .. "Text"]
  if fontText then self:ApplyFont(fontText, 10, "") end
  UIDropDownMenu_Initialize(font, function()
    local lsm = LibStub and LibStub("LibSharedMedia-3.0", true)
    local fonts = lsm and lsm:List("font") or {"Friz Quadrata TT"}
    for _, fontName in ipairs(fonts) do
      local selectedFont = fontName
      local info = UIDropDownMenu_CreateInfo()
      info.text = selectedFont
      info.value = selectedFont
      info.checked = CBC.db.font == selectedFont
      info.func = function()
        CBC.db.font = selectedFont
        UIDropDownMenu_SetSelectedValue(font, selectedFont)
        UIDropDownMenu_SetText(font, selectedFont)
        CBC:RefreshFonts()
        CBC:PixelRelayout()
      end
      UIDropDownMenu_AddButton(info)
    end
  end)
  UIDropDownMenu_SetSelectedValue(font, CBC.db and CBC.db.font)
  UIDropDownMenu_SetText(font, CBC.db and CBC.db.font or "Friz Quadrata TT")
  panel.font = font

  local scaleSlider = CreateFrame("Slider", "BestowScaleSlider", panel, "OptionsSliderTemplate")
  scaleSlider:SetPoint("TOPLEFT", 22, -412)
  scaleSlider:SetWidth(200); scaleSlider:SetHeight(16)
  scaleSlider:SetMinMaxValues(0.50, 1.50); scaleSlider:SetValueStep(0.05)
  _G[scaleSlider:GetName().."Low"]:SetText("50%")
  _G[scaleSlider:GetName().."High"]:SetText("150%")
  local scaleText = _G[scaleSlider:GetName().."Text"]
  self:ApplyFont(scaleText, 10, "")
  scaleSlider:SetScript("OnValueChanged", function(_, value)
    value = math.floor(value / 0.05 + 0.5) * 0.05
    scaleText:SetText(string.format("Font & height scale: %d%%", math.floor(value * 100 + 0.5)))
    if CBC.db and CBC.db.scale ~= value then
      CBC.db.scale = value
      if CBC.UpdateCompactLayout then CBC:UpdateCompactLayout() end
      CBC:UpdateCompact()
    end
  end)
  panel.scaleSlider = scaleSlider

  local widthSlider = CreateFrame("Slider", "BestowWidthSlider", panel, "OptionsSliderTemplate")
  widthSlider:SetPoint("TOPLEFT", 244, -412)
  widthSlider:SetWidth(200); widthSlider:SetHeight(16)
  widthSlider:SetMinMaxValues(180, 400); widthSlider:SetValueStep(5)
  _G[widthSlider:GetName().."Low"]:SetText("180px")
  _G[widthSlider:GetName().."High"]:SetText("400px")
  local widthText = _G[widthSlider:GetName().."Text"]
  self:ApplyFont(widthText, 10, "")
  widthSlider:SetScript("OnValueChanged", function(_, value)
    value = math.floor(value / 5 + 0.5) * 5
    widthText:SetText(string.format("Panel width: %d px", value))
    if CBC.db and CBC.db.widthPx ~= value then
      CBC.db.widthPx = value
      if CBC.UpdateCompactLayout then CBC:UpdateCompactLayout() end
      CBC:UpdateCompact()
    end
  end)
  panel.widthSlider = widthSlider

  ---------------------------------------------------------
  -- Section 4: Stat Weights & Shortcuts
  ---------------------------------------------------------
  CreateSectionHeader(panel, "Stat Weights & Shortcuts", -454)

  local weightsHint = panel:CreateFontString(nil, "ARTWORK")
  weightsHint:SetPoint("TOPLEFT", 18, -478)
  weightsHint:SetTextColor(0.68, 0.68, 0.68)
  self:ApplyFont(weightsHint, 9, "")
  weightsHint:SetText("Bestow scores spell utility using BisBeard profiles for all 70 Conquest of Azeroth specs.")

  local weightsButton = CreateFrame("Button", nil, panel)
  weightsButton:SetWidth(180); weightsButton:SetHeight(22)
  weightsButton:SetPoint("TOPLEFT", 18, -498)
  weightsButton:SetText("Edit Current Spec Weights")
  weightsButton:SetNormalFontObject(GameFontNormalSmall)
  self.Pixel:Button(weightsButton, 0.50)
  weightsButton:SetScript("OnClick", function() CBC:OpenStatWeightOptions() end)

  local matrixButton = CreateFrame("Button", nil, panel)
  matrixButton:SetWidth(160); matrixButton:SetHeight(22)
  matrixButton:SetPoint("TOPLEFT", 206, -498)
  matrixButton:SetText("Assignment Matrix (A)")
  matrixButton:SetNormalFontObject(GameFontNormalSmall)
  self.Pixel:Button(matrixButton, 0.50)
  matrixButton:SetScript("OnClick", function() CBC:ToggleAssignmentPanel() end)

  local diagButton = CreateFrame("Button", nil, panel)
  diagButton:SetWidth(150); diagButton:SetHeight(22)
  diagButton:SetPoint("TOPLEFT", 374, -498)
  diagButton:SetText("Diagnostics Dump (D)")
  diagButton:SetNormalFontObject(GameFontNormalSmall)
  self.Pixel:Button(diagButton, 0.50)
  diagButton:SetScript("OnClick", function() CBC:ShowDiagnostics() end)

  panel:SetScript("OnShow", function(self)
    UIDropDownMenu_SetSelectedValue(self.mode, CBC.db.showMode)
    UIDropDownMenu_SetText(self.mode, GetDisplayModeText(CBC.db.showMode))
    UIDropDownMenu_SetSelectedValue(self.font, CBC.db.font)
    UIDropDownMenu_SetText(self.font, CBC.db.font or "Friz Quadrata TT")
    self.scaleSlider:SetValue(CBC.db and CBC.db.scale or 1.0)
    self.widthSlider:SetValue(CBC.db and CBC.db.widthPx or 252)
    self.threshold:SetValue(CBC.db.individualAssignmentThreshold)
    for key, check in pairs(self.checks) do check:SetChecked(CBC.db[key]) end
  end)

  InterfaceOptions_AddCategory(panel)
  self.optionsPanel = panel
  self:CreateStatWeightOptions()
end

function CBC:OpenOptions()
  if not self.optionsPanel or not InterfaceOptionsFrame_OpenToCategory then return end
  InterfaceOptionsFrame_OpenToCategory(self.optionsPanel)
  InterfaceOptionsFrame_OpenToCategory(self.optionsPanel)
end

function CBC:CreateStatWeightOptions()
  if not InterfaceOptions_AddCategory then return end
  local panel = CreateFrame("Frame", "BestowStatWeightOptions")
  panel.name = "Stat Weights"
  panel.parent = "Bestow"
  panel.rows = {}
  panel.scoreRows = {}
  panel.weightHeaders = {}
  panel.scoreFrames = {}
  panel.view = "weights"
  panel.scoreCategoryIndex = 1

  local title = panel:CreateFontString(nil, "ARTWORK")
  title:SetPoint("TOPLEFT", 16, -16)
  self:ApplyFont(title, 15, "")
  title:SetText("Bestow Stat Weights")

  local spec = panel:CreateFontString(nil, "ARTWORK")
  spec:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  self:ApplyFont(spec, 11, "")
  panel.spec = spec

  local source = panel:CreateFontString(nil, "ARTWORK")
  source:SetPoint("TOPLEFT", spec, "BOTTOMLEFT", 0, -5)
  source:SetTextColor(0.55, 0.55, 0.55)
  self:ApplyFont(source, 8, "")
  panel.source = source

  local hint = panel:CreateFontString(nil, "ARTWORK")
  hint:SetPoint("TOPLEFT", source, "BOTTOMLEFT", 0, -8)
  hint:SetTextColor(0.78, 0.78, 0.78)
  self:ApplyFont(hint, 9, "")
  panel.hint = hint

  local weightsTab = CreateFrame("Button", nil, panel)
  weightsTab:SetWidth(100); weightsTab:SetHeight(22); weightsTab:SetPoint("TOPLEFT", 18, -82)
  weightsTab:SetText("Stat Weights")
  weightsTab:SetNormalFontObject(GameFontNormalSmall)
  self.Pixel:Button(weightsTab, 0.50)
  weightsTab:SetScript("OnClick", function() CBC:SetStatWeightOptionsView("weights") end)
  panel.weightsTab = weightsTab

  local scoresTab = CreateFrame("Button", nil, panel)
  scoresTab:SetWidth(100); scoresTab:SetHeight(22); scoresTab:SetPoint("TOPLEFT", 124, -82)
  scoresTab:SetText("Buff Scores")
  scoresTab:SetNormalFontObject(GameFontNormalSmall)
  self.Pixel:Button(scoresTab, 0.50)
  scoresTab:SetScript("OnClick", function() CBC:SetStatWeightOptionsView("scores") end)
  panel.scoresTab = scoresTab

  local resetAll = CreateFrame("Button", nil, panel)
  resetAll:SetWidth(110); resetAll:SetHeight(23); resetAll:SetPoint("TOPRIGHT", -24, -24)
  resetAll:SetText("Reset Weights")
  resetAll:SetNormalFontObject(GameFontNormalSmall)
  self.Pixel:Button(resetAll, 0.50)
  resetAll:SetScript("OnClick", function()
    local specID = CBC:GetLocalSpec()
    if specID and CBC:ResetStatWeightOverrides(specID) then
      CBC:Print("Restored "..tostring(select(2,CBC:GetLocalSpec())).." stat weights to source defaults.")
    end
    CBC:RefreshStatWeightOptions()
  end)
  panel.resetAll = resetAll

  local resetBonuses = CreateFrame("Button", nil, panel)
  resetBonuses:SetWidth(110); resetBonuses:SetHeight(23); resetBonuses:SetPoint("TOPRIGHT", -24, -24)
  resetBonuses:SetText("Reset Bonuses")
  resetBonuses:SetNormalFontObject(GameFontNormalSmall)
  self.Pixel:Button(resetBonuses, 0.50)
  resetBonuses:SetScript("OnClick", function()
    local specID = CBC:GetLocalSpec()
    if specID and CBC:ResetBonusPointOverrides(specID) then
      CBC:Print("Restored "..tostring(select(2,CBC:GetLocalSpec())).." bonus points to stock values.")
    end
    CBC:RefreshStatWeightOptions()
  end)
  panel.resetBonuses = resetBonuses

  for column=0,1 do
    local x = 18 + column*300
    local labels = {
      {text="Weight", x=x, width=112},
      {text="Your value", x=x+112, width=60},
      {text="Default", x=x+178, width=61},
    }
    for _, entry in ipairs(labels) do
      local header = panel:CreateFontString(nil, "ARTWORK")
      header:SetPoint("TOPLEFT", entry.x, -118)
      header:SetWidth(entry.width); header:SetHeight(16)
      header:SetJustifyH("LEFT"); header:SetTextColor(0.55,0.55,0.55)
      self:ApplyFont(header, 8, ""); header:SetText(entry.text)
      panel.weightHeaders[#panel.weightHeaders+1] = header
    end
  end

  for index=1,30 do
    local column = math.floor((index-1)/15)
    local rowIndex = (index-1)%15
    local x, y = 18 + column*300, -138 - rowIndex*28
    local row = {}

    row.label = panel:CreateFontString(nil, "ARTWORK")
    row.label:SetPoint("TOPLEFT", x, y)
    row.label:SetWidth(112); row.label:SetHeight(22)
    row.label:SetJustifyH("LEFT"); self:ApplyFont(row.label, 9, "")

    row.edit = CreateFrame("EditBox", nil, panel)
    row.edit:SetPoint("TOPLEFT", x+112, y)
    row.edit:SetWidth(60); row.edit:SetHeight(22)
    row.edit:SetAutoFocus(false); row.edit:SetMaxLetters(14)
    row.edit:SetTextInsets(4,4,0,0)
    self:ApplyFont(row.edit, 9, "")
    self.Pixel:Backdrop(row.edit, 0.52)

    row.default = panel:CreateFontString(nil, "ARTWORK")
    row.default:SetPoint("TOPLEFT", x+178, y)
    row.default:SetWidth(61); row.default:SetHeight(22)
    row.default:SetJustifyH("LEFT"); row.default:SetTextColor(0.48,0.48,0.48)
    self:ApplyFont(row.default, 8, "")

    row.reset = CreateFrame("Button", nil, panel)
    row.reset:SetPoint("TOPLEFT", x+240, y)
    row.reset:SetWidth(44); row.reset:SetHeight(22)
    row.reset:SetText("Reset"); row.reset:SetNormalFontObject(GameFontNormalSmall)
    self.Pixel:Button(row.reset, 0.44)

    row.edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    row.edit:SetScript("OnEscapePressed", function(self)
      CBC:RefreshStatWeightOptions()
      self:ClearFocus()
    end)
    row.edit:SetScript("OnEditFocusLost", function(self)
      if panel.refreshing or not row.key then return end
      local value = tonumber(self:GetText())
      if not value or value < 0 or value > CBC.StatWeightMaximum then
        CBC:Print("Stat weights must be numbers between 0 and "..tostring(CBC.StatWeightMaximum)..".")
        CBC:RefreshStatWeightOptions()
        return
      end
      if not CBC:SetStatWeightOverride(panel.specID, row.key, value) then
        CBC:Print("Could not save that stat weight.")
      end
      CBC:RefreshStatWeightOptions()
    end)
    row.reset:SetScript("OnClick", function()
      if row.key then CBC:ResetStatWeightOverrides(panel.specID, row.key) end
      CBC:RefreshStatWeightOptions()
    end)
    panel.rows[index] = row
  end

  local previousCategory = CreateFrame("Button", nil, panel)
  previousCategory:SetWidth(26); previousCategory:SetHeight(22)
  previousCategory:SetPoint("TOPLEFT", 18, -118)
  previousCategory:SetText("<"); previousCategory:SetNormalFontObject(GameFontNormalSmall)
  self.Pixel:Button(previousCategory, 0.50)
  previousCategory:SetScript("OnClick", function()
    panel.scoreCategoryIndex = panel.scoreCategoryIndex - 1
    if panel.scoreCategoryIndex < 1 then panel.scoreCategoryIndex = #CBC.CategoryOrder end
    CBC:RefreshStatWeightOptions()
  end)
  panel.scoreFrames[#panel.scoreFrames+1] = previousCategory

  local nextCategory = CreateFrame("Button", nil, panel)
  nextCategory:SetWidth(26); nextCategory:SetHeight(22)
  nextCategory:SetPoint("TOPLEFT", 48, -118)
  nextCategory:SetText(">"); nextCategory:SetNormalFontObject(GameFontNormalSmall)
  self.Pixel:Button(nextCategory, 0.50)
  nextCategory:SetScript("OnClick", function()
    panel.scoreCategoryIndex = panel.scoreCategoryIndex + 1
    if panel.scoreCategoryIndex > #CBC.CategoryOrder then panel.scoreCategoryIndex = 1 end
    CBC:RefreshStatWeightOptions()
  end)
  panel.scoreFrames[#panel.scoreFrames+1] = nextCategory

  local scoreCategory = panel:CreateFontString(nil, "ARTWORK")
  scoreCategory:SetPoint("TOPLEFT", 84, -118)
  scoreCategory:SetWidth(300); scoreCategory:SetHeight(22)
  scoreCategory:SetJustifyH("LEFT"); self:ApplyFont(scoreCategory, 11, "")
  panel.scoreCategory = scoreCategory
  panel.scoreFrames[#panel.scoreFrames+1] = scoreCategory

  local scoreHeaders = {
    {text="Buff family", x=18, width=218},
    {text="Single: base+bonus=final", x=240, width=128},
    {text="Greater: base+bonus=final", x=370, width=128},
    {text="Bonus", x=502, width=50},
    {text="Stock", x=556, width=45},
  }
  for _, entry in ipairs(scoreHeaders) do
    local header = panel:CreateFontString(nil, "ARTWORK")
    header:SetPoint("TOPLEFT", entry.x, -150)
    header:SetWidth(entry.width); header:SetHeight(16)
    header:SetJustifyH("LEFT"); header:SetTextColor(0.55,0.55,0.55)
    self:ApplyFont(header, 8, ""); header:SetText(entry.text)
    panel.scoreFrames[#panel.scoreFrames+1] = header
  end

  for index=1,6 do
    local y = -172 - (index-1)*42
    local row = {}
    row.label = panel:CreateFontString(nil, "ARTWORK")
    row.label:SetPoint("TOPLEFT", 18, y)
    row.label:SetWidth(218); row.label:SetHeight(34)
    row.label:SetJustifyH("LEFT"); self:ApplyFont(row.label, 9, "")

    row.single = panel:CreateFontString(nil, "ARTWORK")
    row.single:SetPoint("TOPLEFT", 240, y)
    row.single:SetWidth(128); row.single:SetHeight(34)
    row.single:SetJustifyH("LEFT"); self:ApplyFont(row.single, 9, "")

    row.greater = panel:CreateFontString(nil, "ARTWORK")
    row.greater:SetPoint("TOPLEFT", 370, y)
    row.greater:SetWidth(128); row.greater:SetHeight(34)
    row.greater:SetJustifyH("LEFT"); self:ApplyFont(row.greater, 9, "")

    row.edit = CreateFrame("EditBox", nil, panel)
    row.edit:SetPoint("TOPLEFT", 502, y-2)
    row.edit:SetWidth(50); row.edit:SetHeight(22)
    row.edit:SetAutoFocus(false); row.edit:SetMaxLetters(9)
    row.edit:SetTextInsets(4,4,0,0); self:ApplyFont(row.edit, 9, "")
    self.Pixel:Backdrop(row.edit, 0.52)

    row.stock = panel:CreateFontString(nil, "ARTWORK")
    row.stock:SetPoint("TOPLEFT", 556, y)
    row.stock:SetWidth(42); row.stock:SetHeight(22)
    row.stock:SetJustifyH("LEFT"); row.stock:SetTextColor(0.48,0.48,0.48)
    self:ApplyFont(row.stock, 8, "")

    row.reset = CreateFrame("Button", nil, panel)
    row.reset:SetPoint("TOPLEFT", 598, y-2)
    row.reset:SetWidth(20); row.reset:SetHeight(22)
    row.reset:SetText("R"); row.reset:SetNormalFontObject(GameFontNormalSmall)
    self.Pixel:Button(row.reset, 0.44)

    row.hover = CreateFrame("Frame", nil, panel)
    row.hover:SetPoint("TOPLEFT", 18, y)
    row.hover:SetWidth(480); row.hover:SetHeight(34)
    row.hover:EnableMouse(true)
    row.hover:SetScript("OnEnter", function(owner)
      if not row.tooltipSpellID then return end
      GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
      GameTooltip:SetHyperlink("spell:"..row.tooltipSpellID)
      GameTooltip:Show()
    end)
    row.hover:SetScript("OnLeave", function() GameTooltip:Hide() end)

    row.edit:SetScript("OnEnterPressed", function(edit) edit:ClearFocus() end)
    row.edit:SetScript("OnEscapePressed", function(edit)
      CBC:RefreshStatWeightOptions()
      edit:ClearFocus()
    end)
    row.edit:SetScript("OnEditFocusLost", function(edit)
      if panel.refreshing or not row.familyKey then return end
      local value = tonumber(edit:GetText())
      if not value or value < CBC.BonusPointMinimum or value > CBC.BonusPointMaximum then
        CBC:Print("Bonus points must be between "..CBC.BonusPointMinimum.." and "..CBC.BonusPointMaximum..".")
      elseif not CBC:SetBonusPointOverride(panel.specID, row.familyKey, row.stockSpellID, value) then
        CBC:Print("Could not save those bonus points.")
      end
      CBC:RefreshStatWeightOptions()
    end)
    row.reset:SetScript("OnClick", function()
      if row.familyKey then CBC:ResetBonusPointOverrides(panel.specID, row.familyKey) end
      CBC:RefreshStatWeightOptions()
    end)
    panel.scoreRows[index] = row
    for _, widget in ipairs({
      row.label, row.single, row.greater, row.edit, row.stock, row.reset, row.hover,
    }) do
      panel.scoreFrames[#panel.scoreFrames+1] = widget
    end
  end

  panel:SetScript("OnShow", function() CBC:RefreshStatWeightOptions() end)
  panel:SetScript("OnHide", function() GameTooltip:Hide() end)
  InterfaceOptions_AddCategory(panel)
  self.statWeightOptionsPanel = panel
end

function CBC:SetStatWeightOptionsView(view)
  local panel = self.statWeightOptionsPanel
  if not panel then return end
  panel.view = view == "scores" and "scores" or "weights"
  self:RefreshStatWeightOptions()
end

local function ScoreFormula(base, bonus, score)
  if score == nil then return "-" end
  local sign = bonus and bonus >= 0 and "+" or ""
  return tostring(base or 0)..sign..FormatWeight(bonus or 0).."="..tostring(score)
end

function CBC:RefreshStatWeightOptions()
  local panel = self.statWeightOptionsPanel
  if not panel then return end
  panel.refreshing = true
  local specID, specName = self:GetLocalSpec()
  panel.specID = specID
  local defaults, profile = self:GetConfigurableStatWeightDefaults(specID)
  local configured = self:GetSpecStatWeights(specID)
  if not defaults then
    panel.spec:SetText("Current specialization unavailable")
    panel.source:SetText("")
    panel.resetAll:Disable()
    for _, row in ipairs(panel.rows) do
      row.key=nil; row.label:Hide(); row.edit:Hide(); row.default:Hide(); row.reset:Hide()
    end
    for _, widget in ipairs(panel.scoreFrames) do widget:Hide() end
    panel.refreshing = false
    return
  end

  panel.spec:SetText(tostring(specName).." ("..specID..") - "..tostring(profile.sourceKey))
  local source = self.StatWeightSource or {}
  panel.source:SetText("BisBeard snapshot: "..tostring(source.retrievedUTC).."  SHA-256 "..string.sub(tostring(source.sha256 or ""),1,12))
  local overrides = self.db.statWeightOverrides and self.db.statWeightOverrides[specID]
  local bonusOverrides = self.db.bonusPointOverrides and self.db.bonusPointOverrides[specID]
  local showScores = panel.view == "scores"
  panel.weightsTab:SetAlpha(showScores and 0.60 or 1)
  panel.scoresTab:SetAlpha(showScores and 1 or 0.60)
  SetVisible(panel.resetAll, not showScores)
  SetVisible(panel.resetBonuses, showScores)
  if not showScores and overrides and next(overrides) then
    panel.resetAll:Enable(); panel.resetAll:SetAlpha(1)
  else
    panel.resetAll:Disable(); panel.resetAll:SetAlpha(0.45)
  end
  if showScores and bonusOverrides and next(bonusOverrides) then
    panel.resetBonuses:Enable(); panel.resetBonuses:SetAlpha(1)
  else
    panel.resetBonuses:Disable(); panel.resetBonuses:SetAlpha(0.45)
  end
  panel.hint:SetText(showScores
    and "Scores update live. Hover a family for its highest-rank tooltip; edit its additive bonus."
    or "Orange rows differ from their source default and are shared with Bestow group members.")
  for _, header in ipairs(panel.weightHeaders) do SetVisible(header, not showScores) end
  for _, widget in ipairs(panel.scoreFrames) do SetVisible(widget, showScores) end

  local keys, included = {}, {}
  for _, key in ipairs(statWeightOrder) do
    if defaults[key] ~= nil then keys[#keys+1]=key; included[key]=true end
  end
  local extras = {}
  for key in pairs(defaults) do if not included[key] then extras[#extras+1]=key end end
  table.sort(extras)
  for _, key in ipairs(extras) do keys[#keys+1]=key end

  for index, row in ipairs(panel.rows) do
    local key = keys[index]
    row.key = key
    if key and not showScores then
      local edited = overrides and overrides[key] ~= nil
      row.label:SetText(key..(edited and " *" or ""))
      row.label:SetTextColor(edited and 1 or 0.82, edited and 0.58 or 0.82, edited and 0.18 or 0.82)
      row.edit:SetText(FormatWeight(configured[key]))
      row.edit:SetTextColor(edited and 1 or 0.92, edited and 0.68 or 0.92, edited and 0.25 or 0.92)
      row.default:SetText(FormatWeight(defaults[key]))
      row.label:Show(); row.edit:Show(); row.default:Show()
      if edited then row.reset:Show() else row.reset:Hide() end
    else
      row.label:Hide(); row.edit:Hide(); row.default:Hide(); row.reset:Hide()
    end
  end

  if showScores then
    panel.scoreCategoryIndex = math.max(1, math.min(panel.scoreCategoryIndex, #self.CategoryOrder))
    local categoryKey = self.CategoryOrder[panel.scoreCategoryIndex]
    local category = self.Categories[categoryKey]
    panel.scoreCategory:SetText(category.label.."  ("..panel.scoreCategoryIndex.."/"..#self.CategoryOrder..")")
    local familyKeys = {}
    for familyKey in pairs(category.variants or {}) do familyKeys[#familyKeys+1] = familyKey end
    table.sort(familyKeys)
    local localMember = self.rosterByGUID[UnitGUID("player")]
    local unit = localMember and localMember.unit or "player"
    for index, row in ipairs(panel.scoreRows) do
      local familyKey = familyKeys[index]
      local family = familyKey and category.variants[familyKey]
      row.familyKey = familyKey
      if family then
        local singleID = family.singleIDs and family.singleIDs[#family.singleIDs]
        local greaterID = family.greaterIDs and family.greaterIDs[#family.greaterIDs]
        local stockSpellID = greaterID or singleID
        local singleScore, singleBase, singleBonus
        local greaterScore, greaterBase, greaterBonus
        if singleID then
          local values = {self:GetNormalizedEffectScore(
            specID, self:GetSpellEffect(singleID), unit, familyKey, singleID
          )}
          singleScore, singleBase, singleBonus = values[1], values[2], values[4]
        end
        if greaterID then
          local values = {self:GetNormalizedEffectScore(
            specID, self:GetSpellEffect(greaterID), unit, familyKey, greaterID
          )}
          greaterScore, greaterBase, greaterBonus = values[1], values[2], values[4]
        end
        local name = family.singleNames and family.singleNames[#family.singleNames]
          or family.greaterNames and family.greaterNames[#family.greaterNames]
          or familyKey
        local effectiveBonus = self:GetEffectBonusPoints(specID, familyKey, stockSpellID, unit)
        local stockBonus = self:GetStockEffectBonusPoints(specID, familyKey, stockSpellID)
        local edited = bonusOverrides and bonusOverrides[familyKey] ~= nil
        row.stockSpellID = stockSpellID
        row.tooltipSpellID = stockSpellID
        row.label:SetText(name)
        row.single:SetText(ScoreFormula(singleBase, singleBonus, singleScore))
        row.greater:SetText(ScoreFormula(greaterBase, greaterBonus, greaterScore))
        row.edit:SetText(FormatWeight(effectiveBonus))
        row.edit:SetTextColor(edited and 1 or 0.92, edited and 0.68 or 0.92, edited and 0.25 or 0.92)
        row.stock:SetText(FormatWeight(stockBonus))
        row.label:Show(); row.single:Show(); row.greater:Show()
        row.edit:Show(); row.stock:Show()
        if edited then row.reset:Show() else row.reset:Hide() end
      else
        row.tooltipSpellID = nil
        row.label:Hide(); row.single:Hide(); row.greater:Hide()
        row.edit:Hide(); row.stock:Hide(); row.reset:Hide()
      end
    end
  end
  panel.refreshing = false
end

function CBC:OpenStatWeightOptions()
  local panel = self.statWeightOptionsPanel
  if not panel or not InterfaceOptionsFrame_OpenToCategory then return end
  InterfaceOptionsFrame_OpenToCategory(panel)
  InterfaceOptionsFrame_OpenToCategory(panel)
end
