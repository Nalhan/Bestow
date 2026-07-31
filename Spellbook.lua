local _, CBC = ...

local function SpellIDFromBook(index)
  local link = GetSpellLink(index, BOOKTYPE_SPELL)
  return link and tonumber(string.match(link, "spell:(%d+)")) or nil
end

local function RankPosition(ids, id)
  for index, candidate in ipairs(ids or {}) do
    if candidate == id then return index end
  end
  return 0
end

function CBC:ScanSpellbook()
  local byID, byName = {}, {}
  local index = 1
  while true do
    local name = GetSpellName(index, BOOKTYPE_SPELL)
    if not name then break end
    local passive = IsPassiveSpell and IsPassiveSpell(index, BOOKTYPE_SPELL)
    if not passive then
      local id = SpellIDFromBook(index)
      if id then byID[id] = {id=id,index=index,name=name} end
      local normalized = self:Normalize(name)
      byName[normalized] = byName[normalized] or {}
      byName[normalized][#byName[normalized]+1] = {id=id,index=index,name=name}
    end
    index = index + 1
  end
  self.spellbookByID, self.spellbookByName = byID, byName

  local _, classToken = UnitClass("player")
  classToken = self:ResolveClassToken(classToken)
  self.playerClassToken = classToken
  self.mine = {classToken=classToken,categories={}}
  if not classToken then
    self:Debug("Local player is not a registered CoA class; capabilities disabled.")
    return
  end

  local classFamilies = self.familyByProviderCategory[classToken] or {}
  for categoryKey, family in pairs(classFamilies) do
    local function Discover(names, ids)
      local best, bestPosition
      for _, id in ipairs(ids or {}) do
        local known = byID[id]
        if not known and IsSpellKnown and IsSpellKnown(id) and GetSpellInfo(id) then
          known = {id=id,name=GetSpellInfo(id)}
        end
        if known then
          local position = RankPosition(ids, id)
          if not best or position >= bestPosition then best, bestPosition = known, position end
        end
      end
      for _, name in ipairs(names or {}) do
        for _, known in ipairs(byName[self:Normalize(name)] or {}) do
          local position = RankPosition(ids, known.id)
          if not best or position >= (bestPosition or 0) then best, bestPosition = known, position end
        end
      end
      return best and best.id or nil, bestPosition
    end
    local single, singleRank = Discover(family.singleNames, family.singleIDs)
    local greater, greaterRank = Discover(family.greaterNames, family.greaterIDs)
    if single or greater then
      self.mine.categories[categoryKey] = {
        category=categoryKey, family=family.key, provider=classToken,
        tier=family.tier, single=single, greater=greater,
        independent=family.independent,sharedCastKey=family.sharedCastKey,
        singleRank=singleRank, greaterRank=greaterRank,
        singleEffect=self:GetSpellEffect(single),
        greaterEffect=self:GetSpellEffect(greater),
      }
    else
      self.unknownSpellIssues = self.unknownSpellIssues or {}
      local issue = categoryKey .. "/" .. family.key
      if not self.unknownSpellIssues[issue] then
        self.unknownSpellIssues[issue] = true
        self:Debug("Not known: " .. issue)
      end
    end
  end

  local guid = UnitGUID("player")
  if guid then
    self.providers[guid] = self.providers[guid] or {}
    self.providers[guid].guid = guid
    self.providers[guid].name = self:FullName("player")
    self.providers[guid].classToken = classToken
    self.providers[guid].categories = self.mine.categories
    self.providers[guid].addon = true
    self.providers[guid].localPlayer = true
  end
end

function CBC:GetCastSpell(capability, greater)
  if not capability then return nil end
  local id = greater and capability.greater or capability.single
  if not id and greater then id = capability.single end
  if not id and not greater then id = capability.greater end
  if not id then return nil end
  local name, rank, icon = GetSpellInfo(id)
  return id, name, rank, icon
end
