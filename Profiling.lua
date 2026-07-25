local addonName, CBC = ...

local unpack = unpack
local format = string.format
local sort = table.sort

local PROFILE_TARGETS = {
  "Rebuild",
  "RefreshRoster",
  "RefreshSession",
  "BuildAssignments",
  "BuildActions",
  "ScanAuras",
  "ScanDirtyAuras",
  "UpdateCompact",
  "UpdateAssignmentPanel",
  "UpdateAssignmentAuraState",
  "RefreshAuraState",
  "UpdateDurations",
  "ProcessSpecInspectQueue",
  "OnCharacterAdvancementInspectResult",
  "OnAddonMessage",
  "BroadcastState",
  "ScanSpellbook",
  "RefreshFonts",
  "PixelRelayout",
  "ScheduleRebuild",
}

local function NowMilliseconds()
  if _G.debugprofilestop then return _G.debugprofilestop() end
  return GetTime() * 1000
end

local function NewProfileData()
  return {
    startedAt=GetTime(),
    metrics={},
    rebuildReasons={},
    scheduleReasons={},
    spikes={},
  }
end

function CBC:ResetProfiler(silent)
  self.profileData = NewProfileData()
  if not silent then self:Print("Profiling counters reset.") end
end

function CBC:RecordProfile(name, elapsed, detail)
  local data = self.profileData
  if not data then return end
  local metric = data.metrics[name]
  if not metric then
    metric = {count=0,total=0,last=0,max=0}
    data.metrics[name] = metric
  end
  metric.count = metric.count + 1
  metric.total = metric.total + elapsed
  metric.last = elapsed
  if elapsed > metric.max then metric.max = elapsed end

  if elapsed >= 2 then
    local spikes = data.spikes
    spikes[#spikes+1] = {
      at=date("%H:%M:%S"),
      name=name,
      elapsed=elapsed,
      detail=detail,
    }
    if #spikes > 20 then table.remove(spikes, 1) end
  end
end

function CBC:WrapProfileTarget(name)
  self.profileOriginals = self.profileOriginals or {}
  if self.profileOriginals[name] then return end
  local original = self[name]
  if type(original) ~= "function" then return end
  self.profileOriginals[name] = original
  self[name] = function(owner, ...)
    local detail
    if name == "Rebuild" then
      detail = tostring((...))
      local reasons = owner.profileData and owner.profileData.rebuildReasons
      if reasons then reasons[detail] = (reasons[detail] or 0) + 1 end
    elseif name == "ScheduleRebuild" then
      detail = tostring((...))
      local reasons = owner.profileData and owner.profileData.scheduleReasons
      if reasons then reasons[detail] = (reasons[detail] or 0) + 1 end
    end
    local started = NowMilliseconds()
    local results = {original(owner, ...)}
    owner:RecordProfile(name, NowMilliseconds() - started, detail)
    return unpack(results)
  end
end

function CBC:EnableProfiler(silent)
  if self.profilerEnabled then return end
  self.profilerEnabled = true
  if self.db then self.db.profilingEnabled = true end
  self:ResetProfiler(true)
  for _, name in ipairs(PROFILE_TARGETS) do
    self:WrapProfileTarget(name)
  end
  if not silent then
    self:Print("Profiling enabled. Use /bestow profile report after reproducing the slowdown.")
  end
end

function CBC:DisableProfiler(silent)
  if self.profileOriginals then
    for name, original in pairs(self.profileOriginals) do
      self[name] = original
    end
  end
  self.profileOriginals = {}
  self.profilerEnabled = nil
  if self.db then self.db.profilingEnabled = false end
  if not silent then self:Print("Profiling disabled.") end
end

local function AppendReasonCounts(lines, title, counts)
  local rows = {}
  for reason, count in pairs(counts or {}) do
    rows[#rows+1] = {reason=reason,count=count}
  end
  sort(rows, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.reason < b.reason
  end)
  lines[#lines+1] = title
  if #rows == 0 then
    lines[#lines+1] = "  none"
    return
  end
  for index=1,math.min(#rows, 15) do
    local row = rows[index]
    lines[#lines+1] = format("  %s: %d", row.reason, row.count)
  end
end

function CBC:BuildProfilerText()
  local enabled = self.profilerEnabled and "enabled" or "disabled"
  local data = self.profileData
  local lines = {
    "Performance profiling: " .. enabled,
    "Performance fast path: " .. (
      self.performanceFastPathVersion
      and ("active v" .. tostring(self.performanceFastPathVersion))
      or "NOT LOADED"
    ),
    "Combat structural work deferred: " .. tostring(self.combatStructuralDirty == true),
    "Last deferred reason: " .. tostring(self.combatDeferredReason),
  }

  local scriptProfile = _G.GetCVar and _G.GetCVar("scriptProfile") or "unavailable"
  lines[#lines+1] = "WoW scriptProfile: " .. tostring(scriptProfile)
  if scriptProfile == "1" and _G.UpdateAddOnCPUUsage and _G.GetAddOnCPUUsage then
    _G.UpdateAddOnCPUUsage()
    lines[#lines+1] = format("Native Bestow CPU: %.3f ms", _G.GetAddOnCPUUsage(addonName) or 0)
  else
    lines[#lines+1] = "Native Bestow CPU: unavailable (requires /console scriptProfile 1 and reload)"
  end

  if _G.UpdateAddOnMemoryUsage and _G.GetAddOnMemoryUsage then
    _G.UpdateAddOnMemoryUsage()
    lines[#lines+1] = format("Bestow memory: %.1f KiB", _G.GetAddOnMemoryUsage(addonName) or 0)
  end
  if collectgarbage then
    lines[#lines+1] = format("Total Lua memory: %.1f KiB", collectgarbage("count") or 0)
  end

  if not data then
    lines[#lines+1] = "No session samples. Use /bestow profile on."
    return table.concat(lines, "\n")
  end

  local elapsed = math.max(0.001, GetTime() - data.startedAt)
  lines[#lines+1] = format("Sample window: %.1f sec", elapsed)
  lines[#lines+1] = "Timed path                      calls   /sec   total ms    avg ms    max ms   last ms"
  local rows = {}
  for name, metric in pairs(data.metrics) do
    rows[#rows+1] = {name=name,metric=metric}
  end
  sort(rows, function(a, b)
    if a.metric.total ~= b.metric.total then return a.metric.total > b.metric.total end
    return a.name < b.name
  end)
  if #rows == 0 then
    lines[#lines+1] = "  no calls recorded"
  else
    for _, row in ipairs(rows) do
      local metric = row.metric
      lines[#lines+1] = format(
        "  %-28s %5d %6.2f %10.3f %9.3f %9.3f %9.3f",
        row.name,
        metric.count,
        metric.count / elapsed,
        metric.total,
        metric.total / math.max(1, metric.count),
        metric.max,
        metric.last
      )
    end
  end

  AppendReasonCounts(lines, "Rebuild executions by reason:", data.rebuildReasons)
  AppendReasonCounts(lines, "Rebuild requests by reason:", data.scheduleReasons)
  lines[#lines+1] = "Recent calls >= 2 ms:"
  if #data.spikes == 0 then
    lines[#lines+1] = "  none"
  else
    for _, spike in ipairs(data.spikes) do
      lines[#lines+1] = format(
        "  %s %-24s %8.3f ms%s",
        spike.at,
        spike.name,
        spike.elapsed,
        spike.detail and (" reason=" .. spike.detail) or ""
      )
    end
  end
  return table.concat(lines, "\n")
end

local originalInitialize = CBC.Initialize
CBC.Initialize = function(self, ...)
  local results = {originalInitialize(self, ...)}
  if self.db and self.db.profilingEnabled then self:EnableProfiler(true) end
  return unpack(results)
end

local originalDiagnostics = CBC.BuildDiagnosticText
CBC.BuildDiagnosticText = function(self, ...)
  return originalDiagnostics(self, ...) .. "\n\n" .. self:BuildProfilerText()
end

local originalSlashHandler = SlashCmdList.BESTOW
SlashCmdList.BESTOW = function(message)
  local command, rest = string.match(message or "", "^(%S*)%s*(.-)$")
  command = string.lower(command or "")
  rest = string.lower(rest or "")
  if command == "profile" then
    if rest == "on" or rest == "start" then
      CBC:EnableProfiler()
    elseif rest == "off" or rest == "stop" then
      CBC:DisableProfiler()
    elseif rest == "reset" then
      CBC:ResetProfiler()
    elseif rest == "report" or rest == "dump" then
      if CBC.ShowDiagnostics then CBC:ShowDiagnostics() end
    else
      CBC:Print("Profiling is " .. (CBC.profilerEnabled and "enabled" or "disabled")
        .. ". /bestow profile on|off|reset|report")
    end
    return
  end
  originalSlashHandler(message)
  if command == "" or command == "help" then
    CBC:Print("/bestow profile on|off|reset|report")
  end
end
