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
  local source=self.StatWeightSource or {}
  lines[#lines+1]=string.format(
    "Stat weights: %s profiles, SHA-256 %s",
    tostring(source.profileCount or "missing"),
    tostring(source.sha256 or "missing")
  )
  lines[#lines+1]="Stat source: "..tostring(source.moduleURL or "missing")
  lines[#lines+1]="Individual gain threshold: "..tostring(self.db.individualAssignmentThreshold)
  lines[#lines+1]="Known local capabilities:"
  local localMember=self.rosterByGUID[UnitGUID("player")]
  for _,category in ipairs(self.CategoryOrder) do
    local cap=self.mine and self.mine.categories[category]
    if cap then
      local score,scoreSource,baseScore,raw,bonus,exact=self:GetCapabilityScore(localMember,cap,false)
      lines[#lines+1]=string.format(
        "  %s family=%s single=%s greater=%s tier=%s score=%s source=%s base=%s raw=%s bonus=%s exact=%s",
        category,cap.family,tostring(cap.single),tostring(cap.greater),tostring(cap.tier),
        tostring(score),tostring(scoreSource),tostring(baseScore),tostring(raw),
        tostring(bonus),tostring(exact)
      )
    end
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
  local title=frame:CreateFontString(nil,"OVERLAY"); title:SetPoint("TOPLEFT",12,-10); self:ApplyFont(title,13,""); title:SetText("Bestow Diagnostics"); frame.title=title
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

function CBC:ShowDiagnosticText(title, text)
  local frame = self.diagnosticFrame
  frame.title:SetText(title)
  frame.edit:SetText(text)
  local _, lines = string.gsub(text, "\n", "\n")
  frame.edit:SetHeight(math.max(480, (lines + 2) * 13))
  frame.edit:SetFocus(); frame.edit:HighlightText()
  frame:Show()
end

function CBC:ShowDiagnostics()
  self:ShowDiagnosticText("Bestow Diagnostics", self:BuildDiagnosticText())
end

local function TSV(value)
  value = tostring(value or "")
  value = string.gsub(value, "[\r\n\t]+", " ")
  value = string.gsub(value, "%s+", " ")
  return value
end

function CBC:GetCatalogSpellTooltip(spellID)
  if not self.spellDumpTooltip then
    self.spellDumpTooltip = CreateFrame("GameTooltip", "BestowSpellDumpTooltip", UIParent, "GameTooltipTemplate")
    self.spellDumpTooltip:SetOwner(UIParent, "ANCHOR_NONE")
  end
  local tooltip = self.spellDumpTooltip
  tooltip:ClearLines()
  tooltip:SetOwner(UIParent, "ANCHOR_NONE")
  tooltip:SetHyperlink("spell:" .. spellID)
  local parts = {}
  for index = 1, tooltip:NumLines() do
    local left = _G["BestowSpellDumpTooltipTextLeft" .. index]
    local right = _G["BestowSpellDumpTooltipTextRight" .. index]
    local leftText = left and left:GetText()
    local rightText = right and right:GetText()
    if leftText and leftText ~= "" then parts[#parts+1] = leftText end
    if rightText and rightText ~= "" then parts[#parts+1] = rightText end
  end
  tooltip:Hide()
  return table.concat(parts, " / ")
end

function CBC:BuildSpellTooltipDump()
  local lines = {"spellID\tresolvedName\trank\ttooltip"}
  local seen = {}
  for _, categoryKey in ipairs(self.CategoryOrder) do
    local category = self.Categories[categoryKey]
    local familyKeys = {}
    for familyKey in pairs(category.variants) do familyKeys[#familyKeys+1] = familyKey end
    table.sort(familyKeys)
    for _, familyKey in ipairs(familyKeys) do
      local family = category.variants[familyKey]
      for _, form in ipairs({"single", "greater"}) do
        local ids = form == "single" and family.singleIDs or family.greaterIDs
        for _, spellID in ipairs(ids) do
          if not seen[spellID] then
            seen[spellID] = true
            local name, rank = GetSpellInfo(spellID)
            local tooltip = self:GetCatalogSpellTooltip(spellID)
            lines[#lines+1] = table.concat({
              TSV(spellID), TSV(name), TSV(rank), TSV(tooltip),
            }, "\t")
          end
        end
      end
    end
  end
  return table.concat(lines, "\n")
end

function CBC:ShowSpellTooltipDump()
  self:ShowDiagnosticText("Bestow Spell Tooltip Dump", self:BuildSpellTooltipDump())
end
