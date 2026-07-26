local _, CBC = ...

local function IsTrue(value)
  return value == true or value == 1
end

function CBC:GetRaidMemberZone(unit)
  local index = tonumber(string.match(unit or "", "^raid(%d+)$"))
  local getRaidRosterInfo = _G.GetRaidRosterInfo
  if not index or not getRaidRosterInfo then return nil end
  local zone = select(7, getRaidRosterInfo(index))
  if zone and zone ~= "" then return zone end
end

function CBC:GetIndividualDistanceState(member, spellName)
  if not member or not member.unit then return "remote", "Unknown unit" end
  if member.online == false or member.online == 0 then return "offline", "Offline" end
  if not UnitExists(member.unit) or UnitGUID(member.unit) ~= member.guid then
    return "remote", "Unit unavailable"
  end
  if UnitIsUnit(member.unit, "player") then return "in-range" end

  local memberZone = self:GetRaidMemberZone(member.unit)
  local getRealZoneText = _G.GetRealZoneText
  local getZoneText = _G.GetZoneText
  local playerZone = getRealZoneText and getRealZoneText()
    or (getZoneText and getZoneText())
  if memberZone and playerZone and memberZone ~= playerZone then
    return "remote", memberZone
  end

  local spellInRange = _G.IsSpellInRange
  local spellRange = spellName and spellInRange and spellInRange(spellName, member.unit)
  if IsTrue(spellRange) then return "in-range" end

  local unitInRange = _G.UnitInRange
  local groupRange = unitInRange and unitInRange(member.unit)
  if IsTrue(groupRange) then
    -- UnitInRange can be wider than a particular buff's cast range.
    if spellRange == 0 then return "out-of-range", "Outside spell range" end
    return "in-range"
  end

  local unitIsVisible = _G.UnitIsVisible
  local visible = unitIsVisible and unitIsVisible(member.unit)
  if unitIsVisible and not IsTrue(visible) then
    return "remote", memberZone or "Different zone or beyond visibility"
  end
  if spellRange == 0 or unitInRange then
    return "out-of-range", "Outside spell range"
  end
  return "in-range"
end
