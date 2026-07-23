local _, CBC = ...

local function Family(provider, singleNames, greaterNames, singleIDs, greaterIDs, options)
  local family = {
    provider = provider,
    singleNames = singleNames or {},
    greaterNames = greaterNames or {},
    singleIDs = singleIDs or {},
    greaterIDs = greaterIDs or {},
    enabled = true,
  }
  for key, value in pairs(options or {}) do family[key] = value end
  return family
end

CBC.CategoryOrder = {
  "strength", "stamina", "agility", "intellect", "spirit",
  "attackPower", "spellPower", "percentStats", "mana", "armorStats",
}

CBC.Categories = {
  strength = {
    label="Strength", short="Str",
    priority={{"GUARDIAN","REAPER"},{"FLESHWARDEN"}},
    variants={
      honor=Family("GUARDIAN",{"Honor"},{"Greater Honor"},{300856,301228,301229,301230,301231,301232},{680280}),
      riteOfPower=Family("REAPER",{"Rite of Power"},{"Greater Rite of Power"},{578126,578127,578128,578129},{578130}),
      markOfKorthazz=Family("FLESHWARDEN",{"Mark of Korth'azz"},{"Greater Mark of Korth'azz"},{706589,707341,707342,707343,707344,707345},{680300}),
    },
  },
  stamina = {
    label="Stamina", short="Stam",
    priority={{"BARBARIAN"},{"NECROMANCER","REAPER"},{"FLESHWARDEN"}},
    variants={
      enduringShout=Family("BARBARIAN",nil,{"Enduring Shout"},nil,{680302,681439,681440,681441},{groupOnly=true}),
      foulMandate=Family("NECROMANCER",{"Foul Mandate"},{"Greater Foul Mandate"},{800199,573295,573296,573297,573298},{680286}),
      riteOfResolve=Family("REAPER",{"Rite of Resolve"},{"Greater Rite of Resolve"},{800198,803310,803311,803312,803313,803314},{680298}),
      markOfRivendare=Family("FLESHWARDEN",{"Mark of Rivendare"},{"Greater Mark of Rivendare"},{803667,803668,803669,803670},{803730}),
      sanguinaryOffering=Family(nil,{"Sanguinary Offering"},{"Greater Sanguinary Offering"},{706630,707336,707337,707338,707339,707340},{680299},{enabled=false,diagnostic="Blood Mage is absent from the CoA class registry"}),
    },
  },
  agility = {
    label="Agility", short="Agi",
    priority={{"BARBARIAN","DEMONHUNTER","SPIRITMAGE","MONK","WITCHHUNTER","PROPHET"}},
    variants={
      brutalShout=Family("BARBARIAN",nil,{"Brutal Shout"},nil,{300857,300882,300883,300884,300885,300886,300887},{groupOnly=true}),
      illidariIntuition=Family("DEMONHUNTER",{"Illidari Intuition"},{"Greater Illidari Intuition"},{800212,501326,501327,501328,501329,501330,501331,501332,501333,501334,501335,501336},{680308}),
      etchingOfTheDextrous=Family("SPIRITMAGE",{"Etching of the Dextrous"},{"Greater Etching of the Dextrous"},{561237,561238,561239,561240},{561241}),
      giftOfZeal=Family("MONK",{"Gift of Zeal"},{"Greater Gift of Zeal"},{706634,300916,300917,300918,300919,300923,300924},{680306}),
      inquisitorsEdict=Family("WITCHHUNTER",{"Inquisitor's Edict"},{"Greater Inquisitor's Edict"},{706741,707351,707352,707353,707354,707355,707683,707678,707679,707680,707681,707682},{680303}),
      spiderPheromones=Family("PROPHET",{"Spider Pheromones"},{"Greater Spider Pheromones"},{803177,803306,803307,803308,803309,803650},nil,{singleOnly=true}),
    },
  },
  intellect = {
    label="Intellect", short="Int",
    priority={{"CHRONOMANCER","PYROMANCER","STARCALLER","STORMBRINGER"}},
    variants={
      nozdormusWisdom=Family("CHRONOMANCER",{"Nozdormu's Gaze"},{"Greater Nozdormu's Wisdom"},nil,{572396},{greaterPreferred=true}),
      sealOfAlysrazor=Family("PYROMANCER",{"Seal of Alysrazor"},{"Greater Seal of Alysrazor"},{800196,802819,802820,802821,802822},{570170}),
      celestialMind=Family("STARCALLER",{"Celestial Mind"},{"Greater Celestial Mind"},{300255,301222,301223,301224,301225},{680301}),
      callOfTheStorm=Family("STORMBRINGER",{"Call of the Storm"},{"Greater Call of the Storm"},{578311,578312,578313,578314,578315},{578316}),
    },
  },
  spirit = {
    label="Spirit", short="Spirit",
    priority={{"CHRONOMANCER"},{"WITCHDOCTOR"},{"PROPHET"}},
    variants={
      chromiesWisdom=Family("CHRONOMANCER",{"Chromie's Wisdom"},{"Greater Chromie's Wisdom"},{801523,802827,802828,802829,802830,802831,802832,802833,802834},{680307}),
      spiritWuju=Family("WITCHDOCTOR",{"Spirit Wuju"},{"Greater Spirit Wuju"},{560294,561140,561141,561142,561143},{680872}),
      toxicPheromones=Family("PROPHET",{"Toxic Pheromones"},{"Greater Toxic Pheromones"},{707689,707690,707691,707692},{712459},{sharedAuraKey="toxicPheromones"}),
      bloodsoakedOffering=Family(nil,{"Bloodsoaked Offering"},{"Greater Bloodsoaked Offering"},{572400,572401,572402,572403},{572404},{enabled=false,diagnostic="Blood Mage is absent from the CoA class registry"}),
    },
  },
  attackPower = {
    label="Attack Power", short="AP",
    priority={{"WILDWALKER","RANGER","SUNCLERIC","TINKER","WITCHDOCTOR"},{"PROPHET"}},
    variants={
      primalInstinct=Family("WILDWALKER",{"Primal Instinct"},{"Greater Primal Instinct"},{800197,803315,803316,803317,803318,803319,573349},{680310}),
      woodsmansAdaptation=Family("RANGER",{"Woodsman's Adaptation"},{"Greater Woodsman's Adaptation"},{800266,803320,803321,803322,803323,803324,803666},{680294}),
      devotionOfDawn=Family("SUNCLERIC",{"Devotion of Dawn"},{"Greater Devotion of Dawn"},{572384,572385,572386,572387,572388,572389},{572390}),
      powerModule=Family("TINKER",{"Power Module"},{"Greater Power Module"},{706742,707346,707347,707348,707349,707350,707688},{680315}),
      powerWuju=Family("WITCHDOCTOR",{"Power Wuju"},{"Greater Power Wuju"},{707671,707672,707673,707674,707675,707676,707677},{712458}),
      beetlePheromones=Family("PROPHET",{"Beetle Pheromones"},{"Greater Beetle Pheromones"},{803651,803652,803653,803654,803655,803656},{803657},{sharedAuraKey="beetlePheromones"}),
    },
  },
  spellPower = {
    label="Spell Power", short="SP",
    priority={{"CULTIST"},{"NECROMANCER","SUNCLERIC","WITCHHUNTER","PROPHET"},{"FLESHWARDEN"}},
    variants={
      whispersOfCthun=Family("CULTIST",{"Whispers of C'thun"},{"Greater Whispers of C'thun"},{572791,572819,572905},{573067}),
      grimMandate=Family("NECROMANCER",{"Grim Mandate"},{"Greater Grim Mandate"},{572787,572788,572789},{572790}),
      devotionOfRadiance=Family("SUNCLERIC",{"Devotion of Radiance"},{"Greater Devotion of Radiance"},{575040,575041,575042,575043,575044},{575045}),
      witchingEdict=Family("WITCHHUNTER",{"Witching Edict"},{"Greater Witching Edict"},{707684,707685,707686,707687},{681442}),
      toxicPheromones=Family("PROPHET",{"Toxic Pheromones"},{"Greater Toxic Pheromones"},{707689,707690,707691,707692},{712459},{sharedAuraKey="toxicPheromones"}),
      markOfBlaumeux=Family("FLESHWARDEN",{"Mark of Blaumeux"},{"Greater Mark of Blaumeux"},{707693,707694,707695,707696},{712460}),
    },
  },
  percentStats = {
    label="All Stats", short="All",
    priority={{"CULTIST"},{"SUNCLERIC"},{"MONK","SPIRITMAGE"}},
    variants={
      whispersOfNzoth=Family("CULTIST",{"Whispers of N'Zoth","Whispers of N'zoth"},{"Greater Whispers of N'Zoth","Greater Whispers of N'zoth"},{561386},{561387}),
      devotionOfEmperors=Family("SUNCLERIC",{"Devotion of Emperors"},{"Greater Devotion of Emperors"},{572552},{572553}),
      crusadersOath=Family("MONK",nil,{"Greater Crusader's Oath"},nil,{572630},{groupOnly=true}),
      etchingOfTheLeylines=Family("SPIRITMAGE",{"Etching of the Leylines"},{"Greater Etching of the Leylines"},{561236},{561242}),
    },
  },
  mana = {
    label="Mana Efficiency", short="Mana",
    priority={{"SUNCLERIC"},{"SPIRITMAGE","WITCHDOCTOR"},{"CULTIST","WILDWALKER","PYROMANCER","STORMBRINGER","FLESHWARDEN","TINKER"}},
    variants={
      devotionOfGrace=Family("SUNCLERIC",{"Devotion of Grace"},{"Greater Devotion of Grace"},{800852,300858,300859,300862,300863,300864,300865,300866},{681160}),
      etchingOfTheMagi=Family("SPIRITMAGE",{"Etching of the Magi"},{"Greater Etching of the Magi"},{560295},{561243}),
      resourcefulWuju=Family("WITCHDOCTOR",{"Resourceful Wuju"},{"Greater Resourceful Wuju"},{578344},{800195}),
      whispersOfYshaarj=Family("CULTIST",{"Whispers of Y'shaarj"},{"Greater Whispers of Y'shaarj"},{561389,561390,561391},{561392}),
      groveInstinct=Family("WILDWALKER",{"Grove Instinct"},{"Greater Grove Instinct"},{572810,572811,572812,572813,572814,572815,572816},{572817}),
      sealOfAlar=Family("PYROMANCER",{"Seal of Al'ar"},{"Greater Seal of Al'ar"},{803649,803729,807704,807770,808012},{808060}),
      callOfTheWind=Family("STORMBRINGER",{"Call of the Wind"},{"Greater Call of the Wind"},{804018,503319,503320,503321,503322,503323},{680291}),
      markOfZeliek=Family("FLESHWARDEN",{"Mark of Zeliek"},{"Greater Mark of Zeliek"},{803671},{803731}),
      manaModule=Family("TINKER",{"Mana Module"},{"Greater Mana Module"},{803658,803659,803660,803661,803662,803663,803664},{803665}),
    },
  },
  armorStats = {
    label="Armor / Stats", short="Armor",
    priority={{"DEMONHUNTER","WILDWALKER","RANGER","PROPHET","WITCHHUNTER"}},
    variants={
      manariIntuition=Family("DEMONHUNTER",{"Man'ari Intuition"},{"Greater Man'ari Intuition"},{523478,523479,523480,523481,523482,523483,523484},{523495}),
      earthenEndurance=Family("WILDWALKER",{"Earthen Endurance"},{"Greater Earthen Endurance"},{570752,570753,570754,570755},{570756}),
      footpadsAdaptation=Family("RANGER",{"Footpad's Adaptation"},{"Greater Footpad's Adaptation"},{523489,523490,523491,523492,523493,523494},{523513}),
      beetlePheromones=Family("PROPHET",{"Beetle Pheromones"},{"Greater Beetle Pheromones"},{803651,803652,803653,803654,803655,803656},{803657},{sharedAuraKey="beetlePheromones"}),
      knightsEdict=Family("WITCHHUNTER",{"Knight's Edict"},{"Greater Knight's Edict"},{523485,523486,523487,523488},{523510}),
    },
  },
}

function CBC:BuildCatalogIndexes()
  self.familyByProviderCategory = {}
  self.auraNameIndex = {}
  self.auraIDIndex = {}
  self.catalogIssues = {}
  for categoryIndex, categoryKey in ipairs(self.CategoryOrder) do
    local category = self.Categories[categoryKey]
    category.key, category.order = categoryKey, categoryIndex
    category.tierByProvider = {}
    for tier, providers in ipairs(category.priority or {}) do
      for _, provider in ipairs(providers) do category.tierByProvider[provider] = tier end
    end
    for familyKey, family in pairs(category.variants) do
      family.key, family.category = familyKey, categoryKey
      family.tier = family.provider and category.tierByProvider[family.provider] or 999
      if family.enabled and family.provider and self.Classes[family.provider] then
        self.familyByProviderCategory[family.provider] = self.familyByProviderCategory[family.provider] or {}
        self.familyByProviderCategory[family.provider][categoryKey] = family
        for _, name in ipairs(family.singleNames) do
          self.auraNameIndex[self:Normalize(name)] = self.auraNameIndex[self:Normalize(name)] or {}
          table.insert(self.auraNameIndex[self:Normalize(name)], {category=categoryKey,family=familyKey,tier=family.tier,provider=family.provider,form="single"})
        end
        for _, name in ipairs(family.greaterNames) do
          self.auraNameIndex[self:Normalize(name)] = self.auraNameIndex[self:Normalize(name)] or {}
          table.insert(self.auraNameIndex[self:Normalize(name)], {category=categoryKey,family=familyKey,tier=family.tier,provider=family.provider,form="greater"})
        end
        for rankIndex, id in ipairs(family.singleIDs) do
          self.auraIDIndex[id] = self.auraIDIndex[id] or {}
          table.insert(self.auraIDIndex[id], {category=categoryKey,family=familyKey,tier=family.tier,provider=family.provider,form="single",rankIndex=rankIndex})
        end
        for rankIndex, id in ipairs(family.greaterIDs) do
          self.auraIDIndex[id] = self.auraIDIndex[id] or {}
          table.insert(self.auraIDIndex[id], {category=categoryKey,family=familyKey,tier=family.tier,provider=family.provider,form="greater",rankIndex=rankIndex})
        end
      else
        self.catalogIssues[#self.catalogIssues+1] = categoryKey .. "/" .. familyKey .. ": " .. (family.diagnostic or "disabled or invalid provider")
      end
    end
  end
end

function CBC:GetFamily(providerToken, categoryKey)
  return self.familyByProviderCategory[providerToken] and self.familyByProviderCategory[providerToken][categoryKey]
end

function CBC:GetFamilyRankIndex(ids, spellID)
  if not spellID or spellID == 0 then return nil end
  for index, candidate in ipairs(ids or {}) do
    if candidate == spellID then return index end
  end
  return nil
end
