local _, CBC = ...

local displayModes = {
  {value="HOVER", text="Hover"},
  {value="ALWAYS", text="Always expanded (default)"},
  {value="COLLAPSED", text="Always collapsed"},
}

local statWeightOrder = {
  "strength", "agility", "stamina", "intellect", "spirit",
  "attackPower", "rangedAttackPower", "spellPower", "spellDamage", "healingPower",
  "armor", "defense", "dodge", "parry", "block", "blockValue", "shieldBlockValue",
  "critRating", "hitRating", "hasteRating", "expertise",
  "armorPenetration", "spellPenetration", "weaponDps", "rangedDps",
}

local function FormatWeight(value)
  if value == math.floor(value) then return tostring(value) end
  local text = string.format("%.4f", value)
  text = string.gsub(text, "0+$", "")
  return string.gsub(text, "%.$", "")
end

local function AddCheck(panel, key, text, y)
  local name = "BestowOption" .. key
  local check = CreateFrame("CheckButton", name, panel, "InterfaceOptionsCheckButtonTemplate")
  check:SetPoint("TOPLEFT", 18, y)
  local label = _G[name .. "Text"]
  if label then CBC:ApplyFont(label, 11, ""); label:SetText(text) end
  check:SetScript("OnClick", function(self)
    CBC.db[key] = self:GetChecked() and true or false
    CBC:Rebuild("option " .. key)
  end)
  panel.checks[key] = check
  return check
end

function CBC:CreateOptions()
  if not InterfaceOptions_AddCategory then return end
  local panel = CreateFrame("Frame", "BestowOptions")
  panel.name = "Bestow"
  panel.checks = {}

  local title = panel:CreateFontString(nil, "ARTWORK")
  title:SetPoint("TOPLEFT", 16, -16)
  self:ApplyFont(title, 15, "")
  title:SetText("Bestow")

  local subtitle = panel:CreateFontString(nil, "ARTWORK")
  subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  subtitle:SetTextColor(0.78, 0.78, 0.78)
  self:ApplyFont(subtitle, 10, "")
  subtitle:SetText("Compact-panel presentation. Assignment changes remain disabled in combat.")

  local modeLabel = panel:CreateFontString(nil, "ARTWORK")
  modeLabel:SetPoint("TOPLEFT", 18, -72)
  self:ApplyFont(modeLabel, 11, "")
  modeLabel:SetText("Recipient stack")

  local mode = CreateFrame("Frame", "BestowDisplayMode", panel, "UIDropDownMenuTemplate")
  mode:SetPoint("TOPLEFT", 4, -88)
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
        CBC:Rebuild("display mode")
      end
      UIDropDownMenu_AddButton(info)
    end
  end)
  panel.mode = mode

  AddCheck(panel, "revealMissing", "Automatically reveal missing or weaker buffs", -138)
  AddCheck(panel, "revealExpiring", "Automatically reveal buffs nearing expiration", -166)
  AddCheck(panel, "showSpecs", "Show specialization names", -194)

  local threshold = CreateFrame("Slider", "BestowIndividualThreshold", panel, "OptionsSliderTemplate")
  threshold:SetPoint("TOPLEFT", 22, -236)
  threshold:SetWidth(220); threshold:SetHeight(16)
  threshold:SetMinMaxValues(0, 100); threshold:SetValueStep(5)
  _G[threshold:GetName().."Low"]:SetText("0")
  _G[threshold:GetName().."High"]:SetText("100")
  local thresholdText = _G[threshold:GetName().."Text"]
  self:ApplyFont(thresholdText, 10, "")
  threshold:SetScript("OnValueChanged", function(self, value)
    value = math.floor(value / 5 + 0.5) * 5
    thresholdText:SetText("Minimum individual gain: " .. value)
    if CBC.db and CBC.db.individualAssignmentThreshold ~= value then
      CBC.db.individualAssignmentThreshold = value
      CBC:Rebuild("individual threshold")
    end
  end)
  panel.threshold = threshold

  local fontLabel = panel:CreateFontString(nil, "ARTWORK")
  fontLabel:SetPoint("TOPLEFT", 18, -292)
  self:ApplyFont(fontLabel, 11, "")
  fontLabel:SetText("Global font (LibSharedMedia)")

  local font = CreateFrame("Frame", "BestowFontMenu", panel, "UIDropDownMenuTemplate")
  font:SetPoint("TOPLEFT", 4, -308)
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
        CBC:RefreshFonts()
        CBC:PixelRelayout()
      end
      UIDropDownMenu_AddButton(info)
    end
  end)
  panel.font = font

  local weightsButton = CreateFrame("Button", nil, panel)
  weightsButton:SetWidth(220); weightsButton:SetHeight(24)
  weightsButton:SetPoint("TOPLEFT", 18, -365)
  weightsButton:SetText("Edit Current Spec Stat Weights")
  weightsButton:SetNormalFontObject(GameFontNormalSmall)
  self.Pixel:Button(weightsButton, 0.50)
  weightsButton:SetScript("OnClick", function() CBC:OpenStatWeightOptions() end)

  panel:SetScript("OnShow", function(self)
    UIDropDownMenu_SetSelectedValue(self.mode, CBC.db.showMode)
    UIDropDownMenu_SetSelectedValue(self.font, CBC.db.font)
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
  hint:SetText("Enter a non-negative number. Orange rows differ from BisBeard. Unused item stats do not affect tracked buffs.")

  local resetAll = CreateFrame("Button", nil, panel)
  resetAll:SetWidth(96); resetAll:SetHeight(23); resetAll:SetPoint("TOPRIGHT", -24, -24)
  resetAll:SetText("Reset All")
  resetAll:SetNormalFontObject(GameFontNormalSmall)
  self.Pixel:Button(resetAll, 0.50)
  resetAll:SetScript("OnClick", function()
    local specID = CBC:GetLocalSpec()
    if specID and CBC:ResetStatWeightOverrides(specID) then
      CBC:Print("Restored "..tostring(select(2,CBC:GetLocalSpec())).." stat weights to BisBeard defaults.")
    end
    CBC:RefreshStatWeightOptions()
  end)
  panel.resetAll = resetAll

  for column=0,1 do
    local x = 18 + column*300
    local labels = {
      {text="Weight", x=x, width=112},
      {text="Your value", x=x+112, width=60},
      {text="BisBeard", x=x+178, width=61},
    }
    for _, entry in ipairs(labels) do
      local header = panel:CreateFontString(nil, "ARTWORK")
      header:SetPoint("TOPLEFT", entry.x, -92)
      header:SetWidth(entry.width); header:SetHeight(16)
      header:SetJustifyH("LEFT"); header:SetTextColor(0.55,0.55,0.55)
      self:ApplyFont(header, 8, ""); header:SetText(entry.text)
    end
  end

  for index=1,30 do
    local column = math.floor((index-1)/15)
    local rowIndex = (index-1)%15
    local x, y = 18 + column*300, -112 - rowIndex*28
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
      if not value or value < 0 then
        CBC:Print("Stat weights must be non-negative numbers.")
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

  panel:SetScript("OnShow", function() CBC:RefreshStatWeightOptions() end)
  InterfaceOptions_AddCategory(panel)
  self.statWeightOptionsPanel = panel
end

function CBC:RefreshStatWeightOptions()
  local panel = self.statWeightOptionsPanel
  if not panel then return end
  panel.refreshing = true
  local specID, specName = self:GetLocalSpec()
  panel.specID = specID
  local defaults, profile = self:GetBisBeardStatWeights(specID)
  local configured = self:GetSpecStatWeights(specID)
  if not defaults then
    panel.spec:SetText("Current specialization unavailable")
    panel.source:SetText("")
    panel.resetAll:Disable()
    for _, row in ipairs(panel.rows) do
      row.key=nil; row.label:Hide(); row.edit:Hide(); row.default:Hide(); row.reset:Hide()
    end
    panel.refreshing = false
    return
  end

  panel.spec:SetText(tostring(specName).." ("..specID..") - "..tostring(profile.sourceKey))
  local source = self.StatWeightSource or {}
  panel.source:SetText("BisBeard snapshot: "..tostring(source.retrievedUTC).."  SHA-256 "..string.sub(tostring(source.sha256 or ""),1,12))
  local overrides = self.db.statWeightOverrides and self.db.statWeightOverrides[specID]
  if overrides and next(overrides) then
    panel.resetAll:Enable(); panel.resetAll:SetAlpha(1)
  else
    panel.resetAll:Disable(); panel.resetAll:SetAlpha(0.45)
  end

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
    if key then
      local edited = overrides and overrides[key] ~= nil
      row.label:SetText(key..(edited and " *" or ""))
      row.label:SetTextColor(edited and 1 or 0.82, edited and 0.58 or 0.82, edited and 0.18 or 0.82)
      row.edit:SetText(FormatWeight(configured[key]))
      row.edit:SetTextColor(edited and 1 or 0.92, edited and 0.68 or 0.92, edited and 0.25 or 0.92)
      row.default:SetText("BB "..FormatWeight(defaults[key]))
      row.label:Show(); row.edit:Show(); row.default:Show()
      if edited then row.reset:Show() else row.reset:Hide() end
    else
      row.label:Hide(); row.edit:Hide(); row.default:Hide(); row.reset:Hide()
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
