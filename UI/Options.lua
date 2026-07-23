local _, CBC = ...

local displayModes = {
  {value="HOVER", text="Hover"},
  {value="ALWAYS", text="Always expanded (default)"},
  {value="COLLAPSED", text="Always collapsed"},
}

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

  local fontLabel = panel:CreateFontString(nil, "ARTWORK")
  fontLabel:SetPoint("TOPLEFT", 18, -238)
  self:ApplyFont(fontLabel, 11, "")
  fontLabel:SetText("Global font (LibSharedMedia)")

  local font = CreateFrame("Frame", "BestowFontMenu", panel, "UIDropDownMenuTemplate")
  font:SetPoint("TOPLEFT", 4, -254)
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

  panel:SetScript("OnShow", function(self)
    UIDropDownMenu_SetSelectedValue(self.mode, CBC.db.showMode)
    UIDropDownMenu_SetSelectedValue(self.font, CBC.db.font)
    for key, check in pairs(self.checks) do check:SetChecked(CBC.db[key]) end
  end)

  InterfaceOptions_AddCategory(panel)
  self.optionsPanel = panel
end

function CBC:OpenOptions()
  if not self.optionsPanel or not InterfaceOptionsFrame_OpenToCategory then return end
  InterfaceOptionsFrame_OpenToCategory(self.optionsPanel)
  InterfaceOptionsFrame_OpenToCategory(self.optionsPanel)
end
