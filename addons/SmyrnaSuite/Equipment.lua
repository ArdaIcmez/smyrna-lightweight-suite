local _,S=...
-- The single equipment-data service for every Suite consumer.
local G={cache={},order={},cursor=1};S.Equipment=G
function G.Ensure()
 if G.records then return true end
 if S.Config.useDB==false or S.Config.data.equipment==false or (InCombatLockdown and InCombatLockdown()) then return false end
 local load=(C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
 return load and load('SmyrnaEquipmentDB') and G.records~=nil or false
end
function G.Get(id,metadataOnly)
 if G.cache[id] then local r=G.cache[id];if not metadataOnly then G.Sources(r) end;return r end
 local raw=G.records and G.records[id];if not raw then return end
 local f={};for value in (raw..'\t'):gmatch('(.-)\t') do f[#f+1]=value end
 local r={id=id,level=tonumber(f[1]),inv=tonumber(f[2]),classMask=tonumber(f[3]),quality=tonumber(f[4]),name=f[5],class=f[6],subclass=f[7],estimated=f[8]=='1',unique=f[9]=='1',bind=f[10],stats={},sources={},provenance=f[13],faction=f[14],requiredProfession=f[15],unavailable=f[16]=='1'}
 for key,value in f[11]:gmatch('([^,:]+):([^,]+)') do r.stats[key]=tonumber(value) end
 r.sourceIDs=f[12]
 if not metadataOnly then G.Sources(r) end
 local previous=G.order[G.cursor];if previous then G.cache[previous]=nil end
 G.order[G.cursor]=id;G.cursor=G.cursor%256+1;G.cache[id]=r
 return r
end
local sourceCache,sourceOrder,sourceCursor={},{},1
function G.Sources(r)
 if not r or not r.sourceIDs then return r and r.sources or {} end
 for token in r.sourceIDs:gmatch(G.sourcePool and '[^,]+' or '[^;]+') do
  local text=G.sourcePool and G.sourcePool[tonumber(token)] or token
  local source=sourceCache[text]
  if not source then
  local a={};for value in (text..'|'):gmatch('(.-)|') do a[#a+1]=value end
  source={kind=a[1],name=a[2],zone=a[3],level=tonumber(a[4]) or 0,chance=tonumber(a[5]),id=tonumber(a[6]),skill=tonumber(a[7]) or 0,reference=a[11] and a[11]~='' and a[11] or (({Crafted='Recipe reference',Quest='Quest reference',AH='BoE; check listings'})[a[1]] or 'Classic source'),faction=a[8] or '',classes=a[9] or '',repeatable=a[10]=='1'}
  local old=sourceOrder[sourceCursor];if old then sourceCache[old]=nil end
  sourceOrder[sourceCursor]=text;sourceCursor=sourceCursor%512+1;sourceCache[text]=source
  end
  r.sources[#r.sources+1]=source
 end
 r.sourceIDs=nil;return r.sources
end
local candidateCache,candidateKey={},nil
local weaponSpells={['One-Handed Sword']=201,['Two-Handed Sword']=202,['One-Handed Axe']=196,['Two-Handed Axe']=197,['One-Handed Mace']=198,['Two-Handed Mace']=199,Dagger=1180,Polearm=200,Staff=227,['Fist Weapon']=15590,Bow=264,Gun=266,Crossbow=5011,Wand=5009,Thrown=2567}
local bodySlots={[1]=true,[3]=true,[5]=true,[6]=true,[7]=true,[8]=true,[9]=true,[10]=true}
local armorTiers={[1]={'Mail','Plate'},[2]={'Mail','Plate'},[3]={'Leather','Mail'},[7]={'Leather','Mail'},[4]={'Leather','Leather'},[11]={'Leather','Leather'},[5]={'Cloth','Cloth'},[8]={'Cloth','Cloth'},[9]={'Cloth','Cloth'}}
function G.ArmorGuide(class,level)
 local tiers=armorTiers[class];if not tiers then return '' end
 if tiers[1]==tiers[2] then return tiers[1]..' armor; no armor-tier change at level 40.' end
 return level<40 and (tiers[1]..' now; learn '..tiers[2]..' at level 40.') or (tiers[2]..' armor is available from level 40; training may be required.')
end
function G.Context(class,level,allArmor)
 local tier=armorTiers[class] and armorTiers[class][level<40 and 1 or 2]
 local known,parts,count={},{},0
 local ownClass=select(3,UnitClass('player'))
 local knownAPI=S.KnowsSpell or (C_SpellBook and C_SpellBook.IsSpellKnown) or IsSpellKnown
 if ownClass==class and (IsPlayerSpell or knownAPI) then
  for name,spell in pairs(weaponSpells) do
   local yes=(IsPlayerSpell and IsPlayerSpell(spell)) or (knownAPI and knownAPI(spell))
   if not (issecretvalue and issecretvalue(yes)) and yes==true then known[name]=true;count=count+1;parts[#parts+1]=spell end
  end
 end
 table.sort(parts)
 local dual=(IsPlayerSpell and IsPlayerSpell(674)) or (knownAPI and knownAPI(674))
 dual=not (issecretvalue and issecretvalue(dual)) and dual==true
 return {tier=not allArmor and tier or nil,weapons=count>0 and known or nil,dualWield=dual,key=class..':'..level..':'..tostring(allArmor)..':'..tostring(dual)..':'..table.concat(parts,','),trainingKnown=count>0}
end
function G.Candidates(slot,level,class,context)
 local key=context and context.key
 if key~=candidateKey then candidateCache={};candidateKey=key end
 if key and candidateCache[slot] then return candidateCache[slot] end
 local invs=({[1]={1},[2]={2},[3]={3},[5]={5,20},[6]={6},[7]={7},[8]={8},[9]={9},[10]={10},[11]={11},[12]={11},[13]={12},[14]={12},[15]={16},[16]={13,17,21},[17]={13,14,22,23},[18]={15,25,26,28}})[slot] or {}
 local ids={};for _,inv in ipairs(invs) do for _,id in ipairs((G.slots and G.slots[inv]) or {}) do
  local required=level and tonumber(G.records[id]:match('^(%d+)'))
  if not level or (required and required<=level) then
   local row=class and G.Get(id,true)
   if not class or G.Eligible(row,class,level,slot,nil,nil,context) then ids[#ids+1]=id end
  end
 end end
 if key then candidateCache[slot]=ids end
 return ids
end
local names={[1]='Warrior',[2]='Paladin',[3]='Hunter',[4]='Rogue',[5]='Priest',[7]='Shaman',[8]='Mage',[9]='Warlock',[11]='Druid'}
function G.ArmorUnlock(r,class)
 local rule=G.proficiency and G.proficiency[names[class]]
 return r.class=='Armor' and bodySlots[r.inv] and rule and rule.armor[r.subclass] or 1
end
function G.FutureCandidates(slot,level,class,allArmor)
 local out,seen={},{}
 for _,cap in ipairs(level<40 and {39,60} or {60}) do
  if cap>level then
   for _,id in ipairs(G.Candidates(slot,cap,class,G.Context(class,cap,allArmor))) do
    if not seen[id] then seen[id]=true;out[#out+1]=id end
   end
  end
 end
 return out
end
function G.Eligible(r,classID,level,slot,current,otherID,context)
 if not r or r.level>level or r.quality==0 then return false end
 if r.unavailable or (r.requiredProfession and r.requiredProfession~='') then return false end
 if r.faction and r.faction~='' and UnitFactionGroup and UnitFactionGroup('player')~=r.faction then return false end
 if r.classMask and r.classMask>0 and math.floor(r.classMask/2^(classID-1))%2==0 then return false end
 local rule=G.proficiency and G.proficiency[names[classID]]
 if not rule then return false end
 if r.class=='Armor' and context and context.tier and bodySlots[slot] and r.subclass~=context.tier then return false end
 if r.class=='Weapon' then
  if slot==17 and context and not context.dualWield then return false end
  if context and context.weapons and not context.weapons[r.subclass] then return false end
  local found=false;for _,name in ipairs(rule.weapons or {}) do if name==r.subclass then found=true;break end end
  if not found then return false end
 elseif r.subclass~='Miscellaneous' then
  local required=rule.armor and rule.armor[r.subclass];if not required then return false end
  local knows=S.KnowsSpell or IsPlayerSpell or (C_SpellBook and C_SpellBook.IsSpellKnown)
  if required>level and not (knows and ((r.subclass=='Plate' and knows(750)) or (r.subclass=='Mail' and knows(8737)))) then return false end
 end
 if r.unique and r.id==otherID then return false end
 -- Same weapon configuration only; a one-hand/two-hand swap needs a loadout comparison.
 if slot==16 and current and (r.inv==17)~=(current.inv==17) then return false end
 if slot==17 and current and current.blocked then return false end
 return true
end
