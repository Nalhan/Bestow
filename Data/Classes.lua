local _, CBC = ...

CBC.Classes = {
  BARBARIAN = {name = "Barbarian", specs = {{1,"Headhunting","D",{"Agility"}},{2,"Brutality","M",{"Agility"}},{3,"Ancestry","M",{"Agility"}}}},
  WITCHDOCTOR = {name = "Witch Doctor", specs = {{4,"Shadowhunting","D",{"Agility"}},{5,"Voodoo","D",{"Intellect","Spirit"}},{6,"Brewing","H",{"Spirit"}}}},
  DEMONHUNTER = {name = "Felsworn", specs = {{7,"Infernal","D",{"Intellect","Spirit"}},{8,"Slayer","M",{"Agility"}},{9,"Tyrant","T",{"Agility","Stamina"}}}},
  WITCHHUNTER = {name = "Witch Hunter", specs = {{10,"Boltslinger","D",{"Agility","Intellect"}},{11,"Houndmaster","D",{"Agility","Intellect"}},{12,"Inquisition","M",{"Agility","Intellect"}},{97,"Black Knight","T",{"Agility","Stamina"}}}},
  STORMBRINGER = {name = "Stormbringer", specs = {{13,"Wind","D",{"Intellect"}},{14,"Maelstrom","D",{"Intellect"}},{15,"Lightning","D",{"Intellect"}}}},
  FLESHWARDEN = {name = "Knight of Xoroth", specs = {{16,"Hellfire","M",{"Strength","Intellect"}},{17,"Defiance","T",{"Strength","Stamina"}},{18,"War","M",{"Strength"}}}},
  GUARDIAN = {name = "Guardian", specs = {{19,"Gladiator","M",{"Strength"}},{20,"Inspiration","M",{"Strength"}},{21,"Vanguard","T",{"Strength","Stamina"}}}},
  MONK = {name = "Templar", specs = {{22,"Oathkeeper","T",{"Agility","Stamina"}},{23,"Zealot","M",{"Agility"}},{24,"Crusader","M",{"Agility"}}}},
  SONOFARUGAL = {name = "Blood Mage", aliases = {"Son of Arugal", "Bloodmage"}, specs = {{25,"Fleshweaver","D",{"Spirit"}},{26,"Sanguine","D",{"Spirit","Stamina"}},{27,"Accursed","M",{"Agility"}},{99,"Eternal","T",{"Agility","Stamina"}}}},
  RANGER = {name = "Ranger", specs = {{28,"Archery","D",{"Agility"}},{29,"Farstrider","D",{"Agility"}},{30,"Brigand","M",{"Agility"}}}},
  CHRONOMANCER = {name = "Chronomancer", specs = {{31,"Time","H",{"Spirit"}},{32,"Infinite","D",{"Spirit"}},{33,"Artificer","D",{"Spirit"}}}},
  NECROMANCER = {name = "Necromancer", specs = {{34,"Death","D",{"Intellect"}},{35,"Animation","D",{"Intellect"}},{36,"Rime","D",{"Intellect"}}}},
  PYROMANCER = {name = "Pyromancer", specs = {{37,"Flameweaving","H",{"Spirit"}},{38,"Incineration","D",{"Intellect"}},{39,"Draconic","D",{"Intellect"}}}},
  CULTIST = {name = "Cultist", specs = {{40,"Heretic","H",{"Intellect","Strength"}},{41,"Corruption","D",{"Intellect"}},{42,"Godblade","M",{"Strength"}},{96,"Dreadnought","T",{"Strength","Stamina"}}}},
  STARCALLER = {name = "Starcaller", specs = {{43,"Moon Priest","H",{"Intellect"}},{44,"Sentinel","D",{"Intellect"}},{45,"Warden","M",{"Intellect"}},{100,"Moon Guard","T",{"Intellect","Stamina"}}}},
  SUNCLERIC = {name = "Sun Cleric", specs = {{46,"Piety","D",{"Intellect"}},{47,"Valkyrie","M",{"Strength"}},{48,"Seraphim","T",{"Strength","Stamina"}},{98,"Blessings","H",{"Intellect"}}}},
  TINKER = {name = "Tinkerer", specs = {{49,"Demolition","D",{"Agility","Intellect"}},{50,"Mechanics","D",{"Agility","Intellect"}},{51,"Invention","H",{"Intellect"}}}},
  PROPHET = {name = "Venomancer", specs = {{52,"Fortitude","T",{"Intellect","Stamina"}},{53,"Stalking","M",{"Intellect"}},{54,"Rot","D",{"Intellect"}},{101,"Vizier","H",{"Intellect"}}}},
  REAPER = {name = "Reaper", specs = {{55,"Soul","M",{"Strength"}},{56,"Harvest","M",{"Strength"}},{57,"Domination","T",{"Strength","Stamina"}}}},
  WILDWALKER = {name = "Primalist", specs = {{58,"Grovekeeper","D",{"Strength","Intellect"}},{59,"Wildwalker","M",{"Strength"}},{60,"Mountain King","T",{"Strength","Stamina"}},{95,"Geomancy","D",{"Intellect"}}}},
  SPIRITMAGE = {name = "Runemaster", specs = {{61,"Engravement","M",{"Agility"}},{62,"Glyphic","D",{"Intellect","Spirit"}},{63,"Riftblade","M",{"Agility"}}}},
}

function CBC:BuildClassIndexes()
  self.specsByID, self.specsByName, self.classNameToToken = {}, {}, {}
  for token, class in pairs(self.Classes) do
    self.classNameToToken[self:Normalize(token)] = token
    self.classNameToToken[self:Normalize(class.name)] = token
    for _, alias in ipairs(class.aliases or {}) do
      self.classNameToToken[self:Normalize(alias)] = token
    end
    for _, raw in ipairs(class.specs) do
      local spec = {id=raw[1], name=raw[2], roleFlag=raw[3], stats=raw[4], classToken=token}
      spec.role = raw[3] == "T" and "TANK" or (raw[3] == "H" and "HEALER" or "DAMAGER")
      spec.melee = raw[3] == "M"
      self.specsByID[spec.id] = spec
      self.specsByName[self:Normalize(spec.name)] = spec
    end
  end
end

function CBC:IsCoAClass(token)
  return token and self.Classes[token] ~= nil
end

function CBC:ResolveClassToken(tokenOrName)
  if self.Classes[tokenOrName] then return tokenOrName end
  return self.classNameToToken and self.classNameToToken[self:Normalize(tokenOrName)] or nil
end
