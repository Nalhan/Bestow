local _, CBC = ...

local CELL_W, ROW_H, LABEL_W, GRID_LEFT = 80, 23, 122, 7

local function MenuTitle(text)
  return {text=text,isTitle=true,notCheckable=true,disabled=true}
end

function CBC:GetBestAvailableWeightedScore(member, category)
  local bestScore, bestBase, bestRaw, bestBonus, bestExact
  for guid, provider in pairs(self.providers) do
    local providerMember = self.rosterByGUID[guid]
    local capability = provider.categories and provider.categories[category]
    if providerMember and providerMember.online and capability then
      local greater = not capability.single and capability.greater ~= nil
      local score, base, raw, bonus, exact =
        self:GetCapabilityWeightedScore(member, capability, greater)
      if score and (not bestScore or score > bestScore) then
        bestScore, bestBase, bestRaw, bestBonus, bestExact =
          score, base, raw, bonus, exact
      end
    end
  end
  return bestScore, bestBase, bestRaw, bestBonus, bestExact
end

function CBC:OpenProviderMenu(anchor, category, recipientGUID, isHeader)
  local me = self.rosterByGUID[UnitGUID("player")]
  if not self:IsGlobalEditor(me) then
    self:Print("Only raid leaders/assistants may edit the shared matrix.")
    return
  end
  local recipient = recipientGUID and self.rosterByGUID[recipientGUID]
  local choices = self:GetProviderChoices(category, isHeader, recipient)
  local menu, lastScore = {}, nil
  for _, choice in ipairs(choices) do
    if isHeader or choice.cap.single then
    if choice.score ~= lastScore then
      lastScore = choice.score
      menu[#menu+1] = MenuTitle(
        isHeader and ("Group score " .. lastScore) or ("Effectiveness " .. lastScore .. "/100")
      )
    end
    local class = self.Classes[choice.member.classToken]
    local selectedGUID = choice.guid
    local selectedName = choice.member.shortName
    local selectedClassToken = choice.member.classToken
    menu[#menu+1] = {
      text=selectedName .. " - " .. (class and class.name or selectedClassToken)
        .. " (Tier " .. choice.cap.tier .. (choice.cap.independent and ", Independent" or "") .. ")",
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

function CBC:AnnounceGreaterAssignments()
  local channel
  if (GetNumRaidMembers and GetNumRaidMembers() or 0) > 0 then
    channel = "RAID"
  elseif (GetNumPartyMembers and GetNumPartyMembers() or 0) > 0 then
    channel = "PARTY"
  end
  if not channel then
    self:Print("Join a party or raid before announcing Greater assignments.")
    return
  end

  local providerByCategory = self.assignment.greaterByCategory or {}
  local entries = {}
  for _, category in ipairs(self.CategoryOrder) do
    local providerGUID = providerByCategory[category]
    local provider = providerGUID and self.providers[providerGUID]
    if provider then
      local capability = provider.categories and provider.categories[category]
      local spellID = capability and capability.greater
      local spell = spellID and GetSpellLink and GetSpellLink(spellID)
      if not spell and spellID then spell = GetSpellInfo(spellID) end
      entries[#entries+1] = {
        effect=self.Categories[category].label,
        provider=self:ShortName(provider.name),
        spell=spell,
      }
    end
  end
  if #entries == 0 then
    self:Print("There are no Greater assignments to announce.")
    return
  end

  local lines = {
    "[Bestow] Greater raid buffs - each listed player casts:",
  }
  for _, entry in ipairs(entries) do
    local line = "[Bestow] " .. entry.effect .. " - " .. entry.provider
    if entry.spell then line = line .. ": " .. entry.spell end
    lines[#lines+1] = line
  end

  self.announcementQueue = lines
  self.announcementChannel = channel
  self.announcementElapsed = 0.35
  if not self.announcementFrame then
    self.announcementFrame = CreateFrame("Frame")
  end
  self.announcementFrame:SetScript("OnUpdate", function(_, elapsed)
    CBC.announcementElapsed = CBC.announcementElapsed + elapsed
    if CBC.announcementElapsed < 0.35 then return end
    CBC.announcementElapsed = 0
    local nextLine = table.remove(CBC.announcementQueue, 1)
    if nextLine then SendChatMessage(nextLine, CBC.announcementChannel) end
    if #CBC.announcementQueue == 0 then
      CBC.announcementFrame:SetScript("OnUpdate", nil)
    end
  end)
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

  local announce=CreateFrame("Button",nil,frame)
  announce:SetWidth(118); announce:SetHeight(20); announce:SetPoint("TOPRIGHT",-28,-4)
  announce:SetText("Report Greaters"); announce:SetNormalFontObject(GameFontNormalSmall)
  self.Pixel:Button(announce,0.48)
  announce:SetScript("OnClick",function() CBC:AnnounceGreaterAssignments() end)
  announce:SetScript("OnEnter",function(self)
    GameTooltip:SetOwner(self,"ANCHOR_BOTTOM")
    GameTooltip:SetText("Report Greater assignments")
    GameTooltip:AddLine("Posts a readable cast list with each effect, assigned player, and Greater spell to party or raid chat.",1,1,1,true)
    GameTooltip:Show()
  end)
  announce:SetScript("OnLeave",function() GameTooltip:Hide() end)
  frame.announce=announce

  local hint=frame:CreateFontString(nil,"OVERLAY"); hint:SetPoint("RIGHT",announce,"LEFT",-8,0); self:ApplyFont(hint,9,""); hint:SetText("|cff777777Left-click assign | Right-click reset|r")

  for column,category in ipairs(self.CategoryOrder) do
    local button=CreateFrame("Button",nil,frame)
    button:SetWidth(CELL_W-2); button:SetHeight(38)
    button:SetPoint("TOPLEFT",GRID_LEFT+LABEL_W+(column-1)*CELL_W,-30)
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
  scroll:SetPoint("TOPLEFT",GRID_LEFT,-72); scroll:SetPoint("BOTTOMRIGHT",-8,8)
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
      cell.text=cell:CreateFontString(nil,"OVERLAY")
      cell.text:SetPoint("TOPLEFT",2,0); cell.text:SetPoint("BOTTOMRIGHT",-43,0)
      cell.text:SetJustifyH("CENTER"); self:ApplyFont(cell.text,8,"")
      cell.score=cell:CreateFontString(nil,"OVERLAY")
      cell.score:SetPoint("TOPRIGHT",-2,0); cell.score:SetPoint("BOTTOMRIGHT",-2,0)
      cell.score:SetWidth(40); cell.score:SetJustifyH("RIGHT"); self:ApplyFont(cell.score,10,"OUTLINE")
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
          local cap=provider and provider.categories and provider.categories[self.category]
          local recipient=CBC.rosterByGUID[self.recipientGUID]
          local score,base,raw,bonus,exact
          if cap then
            score,base,raw,bonus,exact=
              CBC:GetCapabilityWeightedScore(recipient,cap,assignment.delivery=="greater")
          end
          GameTooltip:AddLine("Assigned: "..(provider and provider.name or assignment.providerGUID).." ("..assignment.delivery..")",1,1,1)
          if score then
            GameTooltip:AddLine("Weighted value: "..score.."/100",0.65,0.8,1)
            GameTooltip:AddLine("Base: "..base.."  Bonus: "..bonus.."  Raw: "..string.format("%.4f",raw).."  Exact: "..tostring(exact),0.65,0.65,0.65)
          end
        else GameTooltip:AddLine("No coordinated provider",0.6,0.6,0.6) end
        local recipient=CBC.rosterByGUID[self.recipientGUID]
        if not assignment then
          local score,base,raw,bonus,exact=CBC:GetBestAvailableWeightedScore(recipient,self.category)
          if score then
            GameTooltip:AddLine("Best available weighted value: "..score.."/100",0.65,0.8,1)
            GameTooltip:AddLine("Base: "..base.."  Bonus: "..bonus.."  Raw: "..string.format("%.4f",raw).."  Exact: "..tostring(exact),0.65,0.65,0.65)
          end
        end
        local potential,base,raw,bonus,exact,family,spellID=
          CBC:GetCategoryMaxPotentialWeightedScore(recipient,self.category)
        if potential then
          GameTooltip:AddLine("Maximum potential: "..potential.."/100 ("..tostring(family)..")",0.55,0.55,0.55)
          GameTooltip:AddLine("Base: "..base.."  Bonus: "..bonus.."  Raw: "..string.format("%.4f",raw).."  Spell: "..tostring(spellID).."  Exact: "..tostring(exact),0.48,0.48,0.48)
        end
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
  local providerByGreater=self.assignment.greaterByCategory or {}
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
          local cap=provider and provider.categories and provider.categories[category]
          local state=cap and self:CoverageState(member.guid,category,cap,assignment.delivery=="greater")
          local score=cap and self:GetCapabilityWeightedScore(member,cap,assignment.delivery=="greater")
          local potential=self:GetCategoryMaxPotentialWeightedScore(member,category)
          if assignment.delivery=="greater" then
            cell.text:SetText("|cff4db8ff*|r")
            cell.cbcBackground:SetTexture(0.05,0.18,0.27,0.72)
          else
            cell.text:SetText(provider and ("|cff"..self:ClassHex(provider.classToken)..self:ShortName(provider.name).."|r") or "?")
            cell.cbcBackground:SetTexture(0.02,0.09,0.13,0.72)
          end
          if score and potential then
            cell.score:SetText("|cffffffff"..score.."|r|cff666666/"..potential.."|r")
          elseif score then
            cell.score:SetText("|cffffffff"..score.."|r")
          else
            cell.score:SetText(potential and ("|cff666666"..potential.."|r") or "|cff555555-|r")
          end
          if not aura or state=="missing" or state=="weaker" then cell.cbcBorders[1]:SetTexture(0.95,0.24,0.20,1)
          elseif state=="stronger" then cell.cbcBorders[1]:SetTexture(0.42,0.68,0.92,1)
          else cell.cbcBorders[1]:SetTexture(0,0,0,1) end
        else
          cell.text:SetText("")
          local potential=self:GetCategoryMaxPotentialWeightedScore(member,category)
          cell.score:SetText(potential and ("|cff666666"..potential.."|r") or "|cff444444-|r")
          cell.cbcBackground:SetTexture(0,0,0,0.28)
          cell.cbcBorders[1]:SetTexture(0,0,0,1)
        end
        cell:Show()
      end
    else
      row.label:SetText("")
      for _,cell in ipairs(row.cells) do cell.recipientGUID=nil; cell.score:SetText(""); cell:Hide() end
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
