local _, CBC = ...

function CBC:BuildDiagnosticText()
  local lines={
    "Bestow diagnostics",
    "Version: "..self.version.." Protocol: "..self.protocol,
    "Client: "..(GetBuildInfo() or "unknown"),
    "Combat: "..tostring(InCombatLockdown and InCombatLockdown()),
    "",
    "Local class: "..tostring(self.playerClassToken),
  }
  local specID,specName=self:GetLocalSpec()
  lines[#lines+1]="Local spec: "..tostring(specID).." "..tostring(specName)
  lines[#lines+1]="Known local capabilities:"
  for _,category in ipairs(self.CategoryOrder) do
    local cap=self.mine and self.mine.categories[category]
    if cap then lines[#lines+1]=string.format("  %s family=%s single=%s greater=%s tier=%s",category,cap.family,tostring(cap.single),tostring(cap.greater),tostring(cap.tier)) end
  end
  lines[#lines+1]=""
  lines[#lines+1]="Roster/providers:"
  for _,member in ipairs(self.roster) do
    local provider=self.providers[member.guid]
    lines[#lines+1]=string.format("  %s %s spec=%s(%s) addon=%s provisional=%s",member.name,member.classToken,tostring(member.specName),tostring(member.specID),tostring(provider and provider.addon),tostring(provider and provider.provisional))
  end
  lines[#lines+1]=""
  lines[#lines+1]="Greater assignments:"
  for guid,category in pairs(self.assignment.greaterByProvider or {}) do
    local provider=self.providers[guid]
    lines[#lines+1]="  "..(provider and provider.name or guid).." -> "..category
  end
  lines[#lines+1]=""
  lines[#lines+1]="Pending actions:"
  for index,action in ipairs(self.actions) do
    lines[#lines+1]=string.format("  %d %s -> %s spell=%s state=%s",index,action.category,action.targetName,tostring(action.spellID),tostring(action.state))
  end
  lines[#lines+1]=""
  lines[#lines+1]="Catalog issues:"
  for _,issue in ipairs(self.catalogIssues or {}) do lines[#lines+1]="  "..issue end
  lines[#lines+1]=""
  lines[#lines+1]="Recent log:"
  for _,entry in ipairs(self.diagnostics or {}) do lines[#lines+1]="  "..entry end
  return table.concat(lines,"\n")
end

function CBC:CreateDiagnostics()
  local frame=CreateFrame("Frame","BestowDiagnostics",UIParent)
  self.diagnosticFrame=frame
  frame:SetWidth(760); frame:SetHeight(520); frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG"); frame:SetMovable(true); frame:EnableMouse(true); frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart",function(self) self:StartMoving() end)
  frame:SetScript("OnDragStop",function(self) self:StopMovingOrSizing() end)
  self.Pixel:Backdrop(frame,0.90); frame:Hide()
  local title=frame:CreateFontString(nil,"OVERLAY"); title:SetPoint("TOPLEFT",12,-10); self:ApplyFont(title,13,""); title:SetText("Bestow Diagnostics")
  self:CreateCloseButton(frame)
  local scroll=CreateFrame("ScrollFrame","BestowDiagnosticScroll",frame)
  scroll:SetPoint("TOPLEFT",12,-38); scroll:SetPoint("BOTTOMRIGHT",-12,12)
  scroll:EnableMouseWheel(true)
  scroll:SetScript("OnMouseWheel", function(self, delta)
    local nextValue = self:GetVerticalScroll() - delta * 45
    self:SetVerticalScroll(math.max(0, math.min(nextValue, self:GetVerticalScrollRange())))
  end)
  local edit=CreateFrame("EditBox",nil,scroll)
  edit:SetMultiLine(true); edit:SetAutoFocus(false); edit:SetWidth(720); edit:SetHeight(480)
  self:ApplyFont(edit,10,"")
  edit:SetScript("OnEscapePressed",function() frame:Hide() end)
  scroll:SetScrollChild(edit); frame.edit=edit
end

function CBC:ShowDiagnostics()
  local frame = self.diagnosticFrame
  local text = self:BuildDiagnosticText()
  frame.edit:SetText(text)
  local _, lines = string.gsub(text, "\n", "\n")
  frame.edit:SetHeight(math.max(480, (lines + 2) * 13))
  frame.edit:SetFocus(); frame.edit:HighlightText()
  frame:Show()
end
