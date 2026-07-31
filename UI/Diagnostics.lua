local _, CBC = ...

local effectFieldOrder = {
  "strength", "agility", "stamina", "intellect", "spirit",
  "attackPower", "spellPower", "armor", "allStatsFlat", "allStatsPercent",
  "manaPer5", "resourceCostReductionPercent",
  "arcaneResistance", "fireResistance", "frostResistance",
  "natureResistance", "shadowResistance", "allResistances",
}

local function SortedKeys(source)
  local keys = {}
  for key in pairs(source or {}) do keys[#keys+1] = key end
  table.sort(keys)
  return keys
end

local function CountKeys(source)
  local count = 0
  for _ in pairs(source or {}) do count = count + 1 end
  return count
end

local function AppendTail(lines, values, maximum)
  local first = math.max(1, #(values or {}) - maximum + 1)
  for index=first,#(values or {}) do
    lines[#lines+1]="  "..values[index]
  end
end

local function FormatNumber(value)
  if value == nil then return "nil" end
  if type(value) ~= "number" then return tostring(value) end
  if value == math.floor(value) then return tostring(value) end
  local text = string.format("%.4f", value)
  text = string.gsub(text, "0+$", "")
  return string.gsub(text, "%.$", "")
end

local function FormatEffect(effect)
  if not effect then return "MISSING" end
  local parts, seen = {}, {}
  for _, key in ipairs(effectFieldOrder) do
    if effect[key] ~= nil then
      parts[#parts+1] = key.."="..FormatNumber(effect[key])
      seen[key] = true
    end
  end
  for _, key in ipairs(SortedKeys(effect)) do
    if not seen[key] then parts[#parts+1] = key.."="..FormatNumber(effect[key]) end
  end
  return #parts > 0 and table.concat(parts, ",") or "EMPTY"
end

function CBC:AppendCurrentSpecValuationDiagnostics(lines, specID, localMember)
  lines[#lines+1] = ""
  lines[#lines+1] = "Current-spec valuation:"
  local weights, profile = self:GetSpecStatWeights(specID)
  if not weights then
    lines[#lines+1] = "  No stat-weight profile is available."
    return
  end

  lines[#lines+1] = "  Profile: "..tostring(profile.sourceKey).." role="..tostring(profile.role)
  lines[#lines+1] = "  Configured stat weights:"
  local bundled = self:GetBisBeardStatWeights(specID)
  local defaults = self:GetConfigurableStatWeightDefaults(specID)
  local overrides = self.db.statWeightOverrides and self.db.statWeightOverrides[specID]
  for _, key in ipairs(SortedKeys(weights)) do
    local sourceName = bundled[key] ~= nil and "BisBeard" or "Default"
    local suffix = overrides and overrides[key] ~= nil
      and " EDITED ("..sourceName.."="..FormatNumber(defaults[key])..")" or ""
    lines[#lines+1] = "    "..key.."="..FormatNumber(weights[key])..suffix
  end

  local unit = localMember and localMember.unit or "player"
  local stats, exact = self:GetScoringStats(unit)
  lines[#lines+1] = string.format(
    "  Primary-stat inputs: strength=%s agility=%s stamina=%s intellect=%s spirit=%s exact=%s",
    FormatNumber(stats.strength), FormatNumber(stats.agility), FormatNumber(stats.stamina),
    FormatNumber(stats.intellect), FormatNumber(stats.spirit), tostring(exact)
  )
  local maximum = self:GetMaxRawEffectUtility(specID, unit)
  lines[#lines+1] = "  Normalization maximum raw utility: "..FormatNumber(maximum)
  lines[#lines+1] = "  Buff values (highest configured rank for each form):"
  lines[#lines+1] = "    category/family form spellID name | unweighted components | raw weighted | base 0-100 | bonus | final 0-100"

  for _, categoryKey in ipairs(self.CategoryOrder) do
    local category = self.Categories[categoryKey]
    for _, familyKey in ipairs(SortedKeys(category.variants)) do
      local family = category.variants[familyKey]
      for _, form in ipairs({"single", "greater"}) do
        local ids = form == "single" and family.singleIDs or family.greaterIDs
        local spellID = ids and ids[#ids]
        if spellID then
          local effect = self:GetSpellEffect(spellID)
          local score, baseScore, raw, bonus, valueExact =
            self:GetNormalizedEffectScore(specID, effect, unit, familyKey, spellID)
          local name = GetSpellInfo(spellID)
          if not name then
            local names = form == "single" and family.singleNames or family.greaterNames
            name = names and names[#names] or "unknown"
          end
          lines[#lines+1] = string.format(
            "    %s/%s %s %s %s | %s | raw=%s | base=%s | bonus=%s | final=%s exact=%s provider=%s tier=%s",
            categoryKey, familyKey, form, tostring(spellID), tostring(name),
            FormatEffect(effect), FormatNumber(raw), FormatNumber(baseScore),
            FormatNumber(bonus), FormatNumber(score), tostring(valueExact),
            tostring(family.provider), tostring(family.tier)
          )
        end
      end
    end
  end
end

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
  lines[#lines+1]="Character Advancement resolver: "..(self:GetCharacterAdvancementAPI() and "available" or "unavailable")
  local specLibrary,specLibrarySource=self:GetExternalSpecLibrary()
  lines[#lines+1]="External spec resolver: "..(specLibrary and tostring(specLibrarySource) or "unavailable")
  lines[#lines+1]="Individual gain threshold: "..tostring(self.db.individualAssignmentThreshold)
  lines[#lines+1]="Known local capabilities:"
  local localMember=self.rosterByGUID[UnitGUID("player")]
  for _,category in ipairs(self.CategoryOrder) do
    local cap=self.mine and self.mine.categories[category]
    if cap then
      local score,scoreSource,baseScore,raw,bonus,exact=self:GetCapabilityScore(localMember,cap,false)
      lines[#lines+1]=string.format(
        "  %s family=%s single=%s greater=%s tier=%s independent=%s score=%s source=%s base=%s raw=%s bonus=%s exact=%s",
        category,cap.family,tostring(cap.single),tostring(cap.greater),tostring(cap.tier),
        tostring(cap.independent),tostring(score),tostring(scoreSource),tostring(baseScore),tostring(raw),
        tostring(bonus),tostring(exact)
      )
    end
  end
  self:AppendCurrentSpecValuationDiagnostics(lines,specID,localMember)
  lines[#lines+1]=""
  lines[#lines+1]="Roster/providers:"
  for _,member in ipairs(self.roster) do
    local provider=self.providers[member.guid]
    local inspect=self.specInspectQueue[member.guid]
    local inspectState="none"
    if inspect then
      if inspect.unavailable then
        inspectState="waiting-range"
      elseif inspect.cooldownUntil and inspect.cooldownUntil > GetTime() then
        inspectState="cooldown/"..math.ceil(inspect.cooldownUntil-GetTime()).."s"
      else
        inspectState="queued/"..tostring(inspect.attempts)
      end
      inspectState=inspectState.."/total="..tostring(inspect.totalAttempts or 0)
      if inspect.lastFailure then inspectState=inspectState.."/last="..inspect.lastFailure end
    end
    local cached=self.externalSpecCache[member.guid]
    lines[#lines+1]=string.format(
      "  %s %s spec=%s(%s) source=%s addon=%s provisional=%s weights=%s/rev=%s/hash=%s bonuses=%s/rev=%s/count=%s inspect=%s caSlot=%s",
      member.name,member.classToken,tostring(member.specName),tostring(member.specID),
      tostring(member.specSource),tostring(provider and provider.addon),tostring(provider and provider.provisional),
      provider and provider.statWeightsAdvertised
        and (provider.statWeightSourceCompatible and "advertised" or "source-mismatch") or "bundled",
      tostring(provider and provider.statWeightRevision),tostring(provider and provider.statWeightHash),
      provider and provider.bonusPointsAdvertised and "advertised" or "stock",
      tostring(provider and provider.bonusPointRevision),
      tostring(CountKeys(provider and provider.bonusPointOverrides)),
      inspectState,tostring(cached and cached.slot)
    )
    for category,observed in pairs(provider and provider.observedCapabilities or {}) do
      lines[#lines+1]=string.format(
        "    observed %s family=%s form=%s spell=%s rank=%s",
        category,tostring(observed.family),tostring(observed.form),
        tostring(observed.spellID),tostring(observed.rankIndex)
      )
    end
  end
  lines[#lines+1]=""
  lines[#lines+1]="Greater assignments:"
  for category,guid in pairs(self.assignment.greaterByCategory or {}) do
    local provider=self.providers[guid]
    lines[#lines+1]="  "..(provider and provider.name or guid).." -> "..category
  end
  lines[#lines+1]=""
  lines[#lines+1]="Matrix synchronization:"
  lines[#lines+1]="  Local clock: "..tostring(self.session and self.session.revision or 0)
  for _,category in ipairs(SortedKeys(self.session and self.session.headerVersions or {})) do
    local version=self.session.headerVersions[category]
    local guid=self.session.header and self.session.header[category]
    local provider=guid and self.providers[guid]
    lines[#lines+1]=string.format(
      "  header %s=%s r%s by %s",
      category,provider and provider.name or guid or "AUTO",
      tostring(version.revision),self:ProviderName(version.writer)
    )
  end
  for _,recipientGUID in ipairs(SortedKeys(self.session and self.session.cellVersions or {})) do
    local recipient=self.rosterByGUID[recipientGUID]
    for _,category in ipairs(SortedKeys(self.session.cellVersions[recipientGUID])) do
      local version=self.session.cellVersions[recipientGUID][category]
      local guid=self.session.cells[recipientGUID] and self.session.cells[recipientGUID][category]
      local provider=guid and self.providers[guid]
      lines[#lines+1]=string.format(
        "  cell %s/%s=%s r%s by %s",
        recipient and recipient.shortName or recipientGUID,category,
        provider and provider.name or guid or "AUTO",
        tostring(version.revision),self:ProviderName(version.writer)
      )
    end
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
  lines[#lines+1]="Assignment update chain (latest 60):"
  AppendTail(lines,self.assignmentDiagnostics,60)
  lines[#lines+1]=""
  lines[#lines+1]="System log (latest 40):"
  AppendTail(lines,self.diagnostics,40)
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
