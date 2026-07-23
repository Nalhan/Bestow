local _, CBC = ...

local CELL_W, ROW_H, LABEL_W = 76, 23, 122

local function MenuTitle(text)
  return {text=text,isTitle=true,notCheckable=true,disabled=true}
end

function CBC:OpenProviderMenu(anchor, category, recipientGUID, isHeader)
  local me = self.rosterByGUID[UnitGUID("player")]
  if not self:IsGlobalEditor(me) then
    self:Print("Only raid leaders/assistants may edit the shared matrix.")
    return
  end
  local choices = self:GetProviderChoices(category, isHeader)
  local menu, lastTier = {}, nil
  for _, choice in ipairs(choices) do
    if isHeader or choice.cap.single then
    if choice.cap.tier ~= lastTier then
      lastTier = choice.cap.tier
      menu[#menu+1] = MenuTitle("Effectiveness tier " .. lastTier)
    end
    local class = self.Classes[choice.member.classToken]
    local selectedGUID = choice.guid
    local selectedName = choice.member.shortName
    local selectedClassToken = choice.member.classToken
    menu[#menu+1] = {
      text=selectedName .. " - " .. (class and class.name or selectedClassToken),
      colorCode="|cff"..self:ClassHex(selectedClassToken),
      notCheckable=true,
      func=function()
        CloseDropDownMenus()
        if isHeader then CBC:SetHeaderAssignment(category, selectedGUID)
        else CBC:SetCellOverride(recipientGUID, category, selectedGUID) end
      end,
    }
    end
  end
  if #menu == 0 then menu[1] = MenuTitle("No capable providers") end
  EasyMenu(menu, self.assignmentDropdown, anchor, 0, 0, "MENU")
end

function CBC:CreateAssignmentPanel()
  local frame = CreateFrame("Frame","BestowAssignments",UIParent)
  frame:SetWidth(LABEL_W + #self.CategoryOrder * CELL_W + 34)
  frame:SetHeight(570)
  local point, x, y = unpack(self.db.assignmentPosition)
  frame:SetPoint(point, UIParent, point, x, y)
  frame:SetFrameStrata("DIALOG"); frame:SetClampedToScreen(true)
  frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart",function(self) if not InCombatLockdown or not InCombatLockdown() then self:StartMoving() end end)
  frame:SetScript("OnDragStop",function(self)
    self:StopMovingOrSizing()
    local point,_,_,x,y=self:GetPoint(); CBC.db.assignmentPosition={point,x,y}
  end)
  self.Pixel:Backdrop(frame,0.84)
  frame:Hide()
  self.assignmentFrame = frame
  frame.headers = {}
  frame.rows = {}

  local title=frame:CreateFontString(nil,"OVERLAY"); title:SetPoint("TOPLEFT",8,-7); self:ApplyFont(title,13,""); title:SetText("Bestow Group Assignments")
  self:CreateCloseButton(frame)

  local hint=frame:CreateFontString(nil,"OVERLAY"); hint:SetPoint("TOPRIGHT",-28,-9); self:ApplyFont(hint,9,""); hint:SetText("|cff777777Left-click assign | Right-click reset|r")

  for column,category in ipairs(self.CategoryOrder) do
    local button=CreateFrame("Button",nil,frame)
    button:SetWidth(CELL_W-2); button:SetHeight(38)
    button:SetPoint("TOPLEFT",LABEL_W+(column-1)*CELL_W,-30)
    self.Pixel:Button(button,0.58)
    button.category=category
    button.label=button:CreateFontString(nil,"OVERLAY"); button.label:SetPoint("TOPLEFT",2,-3); button.label:SetPoint("TOPRIGHT",-2,-3); button.label:SetJustifyH("CENTER"); self:ApplyFont(button.label,9,"")
    button.provider=button:CreateFontString(nil,"OVERLAY"); button.provider:SetPoint("BOTTOMLEFT",2,3); button.provider:SetPoint("BOTTOMRIGHT",-2,3); button.provider:SetJustifyH("CENTER"); self:ApplyFont(button.provider,8,"")
    button:SetScript("OnClick",function(self,mouse)
      if mouse=="RightButton" then CBC:SetHeaderAssignment(self.category,nil)
      else CBC:OpenProviderMenu(self,self.category,nil,true) end
    end)
    button:RegisterForClicks("LeftButtonUp","RightButtonUp")
    frame.headers[column]=button
  end

  local scroll=CreateFrame("ScrollFrame","BestowAssignmentScroll",frame)
  scroll:SetPoint("TOPLEFT",7,-72); scroll:SetPoint("BOTTOMRIGHT",-8,8)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local nextValue = self:GetVerticalScroll() - delta * ROW_H * 3
    self:SetVerticalScroll(math.max(0, math.min(nextValue, self:GetVerticalScrollRange())))
  end)
  local content=CreateFrame("Frame",nil,scroll)
  content:SetWidth(LABEL_W + #self.CategoryOrder*CELL_W)
  content:SetHeight(40*ROW_H)
  scroll:SetScrollChild(content)
  frame.content,frame.rows=content,{}

  for rowIndex=1,40 do
    local row={cells={}}
    row.label=content:CreateFontString(nil,"OVERLAY")
    row.label:SetPoint("TOPLEFT",4,-(rowIndex-1)*ROW_H-5)
    row.label:SetWidth(LABEL_W-8); row.label:SetHeight(ROW_H)
    row.label:SetJustifyH("LEFT"); self:ApplyFont(row.label,9,"")
    for column,category in ipairs(self.CategoryOrder) do
      local cell=CreateFrame("Button",nil,content)
      cell:SetWidth(CELL_W-2); cell:SetHeight(ROW_H-1)
      cell:SetPoint("TOPLEFT",LABEL_W+(column-1)*CELL_W,-(rowIndex-1)*ROW_H)
      self.Pixel:Button(cell,0.43)
      cell.category=category
      cell.text=cell:CreateFontString(nil,"OVERLAY"); cell.text:SetAllPoints(); cell.text:SetJustifyH("CENTER"); self:ApplyFont(cell.text,8,"")
      cell:RegisterForClicks("LeftButtonUp","RightButtonUp")
      cell:SetScript("OnClick",function(self,mouse)
        if not self.recipientGUID then return end
        if mouse=="RightButton" then CBC:ResetCellOverride(self.recipientGUID,self.category)
        else CBC:OpenProviderMenu(self,self.category,self.recipientGUID,false) end
      end)
      cell:SetScript("OnEnter",function(self)
        if not self.recipientGUID then return end
        local assignment=CBC.assignment.cells[self.recipientGUID] and CBC.assignment.cells[self.recipientGUID][self.category]
        local aura=CBC:GetCoverage(self.recipientGUID,self.category)
        GameTooltip:SetOwner(self,"ANCHOR_RIGHT"); GameTooltip:SetText(CBC.Categories[self.category].label)
        if assignment then
          local provider=CBC.providers[assignment.providerGUID]
          GameTooltip:AddLine("Assigned: "..(provider and provider.name or assignment.providerGUID).." ("..assignment.delivery..")",1,1,1)
        else GameTooltip:AddLine("No coordinated provider",0.6,0.6,0.6) end
        if aura then GameTooltip:AddLine("Aura: "..aura.name.." | "..CBC:FormatDuration(aura.expires),0.42,0.68,0.92) end
        GameTooltip:Show()
      end)
      cell:SetScript("OnLeave",function() GameTooltip:Hide() end)
      row.cells[column]=cell
    end
    frame.rows[rowIndex]=row
  end

  self.assignmentDropdown=CreateFrame("Frame","BestowProviderMenu",UIParent,"UIDropDownMenuTemplate")
  frame.ready = true
end

function CBC:UpdateAssignmentPanel()
  local frame=self.assignmentFrame
  if not frame or not frame.ready or not frame:IsShown() then return end
  local providerByGreater={}
  for guid,category in pairs(self.assignment.greaterByProvider or {}) do providerByGreater[category]=guid end
  for column,category in ipairs(self.CategoryOrder) do
    local header=frame.headers[column]
    local guid=providerByGreater[category]
    local provider=guid and self.providers[guid]
    header.label:SetText(self.Categories[category].short)
    header.provider:SetText(provider and ("|cff"..self:ClassHex(provider.classToken)..self:ShortName(provider.name).."|r") or "|cff666666-|r")
  end
  for index,row in ipairs(frame.rows) do
    local member=self.roster[index]
    if member then
      row.label:SetText("|cff"..self:ClassHex(member.classToken)..member.shortName.."|r"..(member.specName and (" |cff666666"..member.specName.."|r") or ""))
      row.label:Show()
      for column,category in ipairs(self.CategoryOrder) do
        local cell=row.cells[column]
        cell.recipientGUID=member.guid
        local assignment=self.assignment.cells[member.guid] and self.assignment.cells[member.guid][category]
        local aura=self:GetCoverage(member.guid,category)
        if assignment then
          local provider=self.providers[assignment.providerGUID]
          if assignment.delivery=="greater" then
            cell.text:SetText("|cff4db8ff*|r")
            cell.cbcBackground:SetTexture(0.05,0.18,0.27,0.72)
          else
            cell.text:SetText(provider and ("|cff"..self:ClassHex(provider.classToken)..self:ShortName(provider.name).."|r") or "?")
            cell.cbcBackground:SetTexture(0.02,0.09,0.13,0.72)
          end
          if not aura then cell.cbcBorders[1]:SetTexture(0.95,0.24,0.20,1)
          elseif aura.tier < ((provider and provider.categories[category] and provider.categories[category].tier) or 999) then cell.cbcBorders[1]:SetTexture(0.42,0.68,0.92,1)
          else cell.cbcBorders[1]:SetTexture(0,0,0,1) end
        else
          cell.text:SetText("")
          cell.cbcBackground:SetTexture(0,0,0,0.28)
          cell.cbcBorders[1]:SetTexture(0,0,0,1)
        end
        cell:Show()
      end
    else
      row.label:SetText("")
      for _,cell in ipairs(row.cells) do cell.recipientGUID=nil; cell:Hide() end
    end
  end
  frame.content:SetHeight(math.max(#self.roster,1)*ROW_H)
end

function CBC:ToggleAssignmentPanel()
  if not self.assignmentFrame or not self.assignmentFrame.ready then
    self:Print("The assignment panel did not initialize.")
    return
  end
  if self.assignmentFrame:IsShown() then self.assignmentFrame:Hide()
  else self.assignmentFrame:Show(); self:UpdateAssignmentPanel() end
end
