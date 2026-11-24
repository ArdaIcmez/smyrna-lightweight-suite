local _,S=...
-- The single equipment-data service for every Suite consumer.
local CACHE_CAP=1024
local SOURCE_CAP=512
local CAND_CAP=4
local G={cache={},order={},cursor=1};S.Equipment=G
local defaultSourceRef={Crafted='Recipe reference',Quest='Quest reference',AH='BoE; check listings'}
local loadFailedReason

function G.Ensure()
 if G.records then G.lastError=nil;loadFailedReason=nil;return true end
 if S.Config.useDB==false then G.lastError='Suite setting "Use optional reference databases" is off';return false end
 if S.Config.data.equipment==false then G.lastError='Suite setting "Equipment references" is off';return false end
 if loadFailedReason then G.lastError=loadFailedReason;return false end
 if InCombatLockdown and InCombatLockdown() then G.lastError='cannot load during combat';return false end
 local load=(C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
 if not load then loadFailedReason='LoadAddOn API unavailable';G.lastError=loadFailedReason;return false end
 local ok,reason=load('SmyrnaEquipmentDB')
 if not ok then loadFailedReason='LoadAddOn("SmyrnaEquipmentDB") failed: '..tostring(reason);G.lastError=loadFailedReason;return false end
 if G.records==nil then loadFailedReason='SmyrnaEquipmentDB loaded but Data.lua did not populate records';G.lastError=loadFailedReason;return false end
 G.lastError=nil;loadFailedReason=nil
 return true
end

local RECORD_PAT='^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t?(.*)$'
local TAIL_PAT='^([^\t]*)\t?([^\t]*)\t?([^\t]*)\t?([^\t]*)$'
function G.Get(id,metadataOnly)
 local cached=G.cache[id]
 if cached then if not metadataOnly then G.Sources(cached) end;return cached end
 local raw=G.records and G.records[id];if not raw then return end
 local f1,f2,f3,f4,f5,f6,f7,f8,f9,f10,f11,f12,rest=raw:match(RECORD_PAT)
 local f13,f14,f15,f16
 if f1 then
  if rest and rest~='' then f13,f14,f15,f16=rest:match(TAIL_PAT) end
 else
  local f={};for value in (raw..'\t'):gmatch('(.-)\t') do f[#f+1]=value end
  f1,f2,f3,f4,f5,f6,f7,f8,f9,f10,f11,f12,f13,f14,f15,f16=f[1],f[2],f[3],f[4],f[5],f[6],f[7],f[8],f[9],f[10],f[11],f[12],f[13],f[14],f[15],f[16]
 end
 local stats={}
 if f11 and f11~='' then
  for key,value in f11:gmatch('([^,:]+):([^,]+)') do stats[key]=tonumber(value) end
 end
 local r={id=id,level=tonumber(f1),inv=tonumber(f2),classMask=tonumber(f3),quality=tonumber(f4),name=f5,class=f6,subclass=f7,estimated=f8=='1',unique=f9=='1',bind=f10,stats=stats,provenance=f13,faction=f14,requiredProfession=f15,unavailable=f16=='1',sourceIDs=f12}
 if not metadataOnly then G.Sources(r) end
 local previous=G.order[G.cursor];if previous then G.cache[previous]=nil end
 G.order[G.cursor]=id;G.cursor=G.cursor%CACHE_CAP+1;G.cache[id]=r
 return r
end

local sourceCache,sourceOrder,sourceCursor={},{},1
local SOURCE_PAT='^([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|([^|]*)|?(.*)$'
function G.Sources(r)
 if not r or not r.sourceIDs then return r and r.sources or {} end
 r.sources=r.sources or {}
 local pool=G.sourcePool
 for token in r.sourceIDs:gmatch(pool and '[^,]+' or '[^;]+') do
  local text=pool and pool[tonumber(token)] or token
  local source=sourceCache[text]
  if not source then
   local a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11=text:match(SOURCE_PAT)
   if not a1 then
    local a={};for value in (text..'|'):gmatch('(.-)|') do a[#a+1]=value end
    a1,a2,a3,a4,a5,a6,a7,a8,a9,a10,a11=a[1],a[2],a[3],a[4],a[5],a[6],a[7],a[8],a[9],a[10],a[11]
   end
   source={kind=a1,name=a2,zone=a3,level=tonumber(a4) or 0,chance=tonumber(a5),id=tonumber(a6),skill=tonumber(a7) or 0,reference=(a11 and a11~='') and a11 or (defaultSourceRef[a1] or 'Classic source'),faction=a8 or '',classes=a9 or '',repeatable=a10=='1'}
   local old=sourceOrder[sourceCursor];if old then sourceCache[old]=nil end
   sourceOrder[sourceCursor]=text;sourceCursor=sourceCursor%SOURCE_CAP+1;sourceCache[text]=source
  end
  r.sources[#r.sources+1]=source
 end
 r.sourceIDs=nil;return r.sources
end

local candidateCache,candidateOrder,candidateCursor={},{},1
function G.TrimCache()
 wipe(G.cache);wipe(G.order);G.cursor=1
 wipe(sourceCache);wipe(sourceOrder);sourceCursor=1
 wipe(candidateCache);wipe(candidateOrder);candidateCursor=1
 loadFailedReason=nil
end
local weaponSpells={['One-Handed Sword']=201,['Two-Handed Sword']=202,['One-Handed Axe']=196,['Two-Handed Axe']=197,['One-Handed Mace']=198,['Two-Handed Mace']=199,Dagger=1180,Polearm=200,Staff=227,['Fist Weapon']=15590,Bow=264,Gun=266,Crossbow=5011,Wand=5009,Thrown=2567}
local bodySlots={[1]=true,[3]=true,[5]=true,[6]=true,[7]=true,[8]=true,[9]=true,[10]=true,[20]=true}
local noFrillClasses={[1]=true,[3]=true,[4]=true}
local classNamesByID={[1]='Warrior',[2]='Paladin',[3]='Hunter',[4]='Rogue',[5]='Priest',[7]='Shaman',[8]='Mage',[9]='Warlock',[11]='Druid'}
local armorTiers={[1]={'Mail','Plate'},[2]={'Mail','Plate'},[3]={'Leather','Mail'},[7]={'Leather','Mail'},[4]={'Leather','Leather'},[11]={'Leather','Leather'},[5]={'Cloth','Cloth'},[8]={'Cloth','Cloth'},[9]={'Cloth','Cloth'}}
local lighterArmor={Plate={'Cloth','Leather','Mail','Plate'},Mail={'Cloth','Leather','Mail'},Leather={'Cloth','Leather'},Cloth={'Cloth'}}
local classDefaultWeapons={
 [1]={'One-Handed Sword','Two-Handed Sword','One-Handed Axe','Two-Handed Axe','One-Handed Mace','Two-Handed Mace','Polearm','Staff','Dagger','Fist Weapon','Bow','Gun','Crossbow','Thrown'},
 [2]={'One-Handed Sword','Two-Handed Sword','One-Handed Axe','Two-Handed Axe','One-Handed Mace','Two-Handed Mace','Polearm'},
 [3]={'One-Handed Axe','Two-Handed Axe','One-Handed Sword','Two-Handed Sword','Polearm','Staff','Dagger','Fist Weapon','Bow','Gun','Crossbow'},
 [4]={'Dagger','One-Handed Sword','One-Handed Mace','Fist Weapon','Bow','Gun','Crossbow','Thrown'},
 [5]={'One-Handed Mace','Dagger','Staff','Wand'},
 [7]={'One-Handed Axe','Two-Handed Axe','One-Handed Mace','Two-Handed Mace','Staff','Dagger','Fist Weapon'},
 [8]={'One-Handed Sword','Dagger','Staff','Wand'},
 [9]={'One-Handed Sword','Dagger','Staff','Wand'},
 [11]={'One-Handed Mace','Two-Handed Mace','Polearm','Staff','Dagger','Fist Weapon'},
}
function G.ArmorGuide(class,level)
 local tiers=armorTiers[class];if not tiers then return '' end
 if tiers[1]==tiers[2] then return tiers[1]..' armor (no armor upgrade at level 40).' end
 return level<40 and (tiers[1]..' now; '..tiers[2]..' unlocks at level 40.') or (tiers[2]..' armor (available from level 40 once trained).')
end
function G.GearGuide(class,level,allArmor)
 local tiers=armorTiers[class]
 if not tiers then return 'Armor: unknown','Weapons: unknown' end
 local currentTier=tiers[level<40 and 1 or 2]
 local armorList=allArmor and (lighterArmor[currentTier] or {currentTier}) or {currentTier}
 local armorNote=''
 if tiers[1]~=tiers[2] then
  armorNote=level<40 and ('  ('..tiers[2]..' unlocks at Lv 40)') or ('  (requires '..tiers[2]..' training)')
 end
 local armorLine='Armor included: '..table.concat(armorList,', ')..armorNote
 local ctx=G.Context(class,level,allArmor)
 local weaponList={}
 if ctx.weapons then
  for w in pairs(ctx.weapons) do weaponList[#weaponList+1]=w end
  table.sort(weaponList)
 else
  local rule=G.proficiency and G.proficiency[classNamesByID[class]]
  local src=(rule and rule.weapons) or classDefaultWeapons[class] or {}
  for _,w in ipairs(src) do weaponList[#weaponList+1]=w end
  table.sort(weaponList)
 end
 local dwText=ctx.trainingKnown and (ctx.dualWield and '  |  Dual Wield: Yes' or '  |  Dual Wield: No') or ''
 local prefix=ctx.trainingKnown and 'Weapons included (trained): ' or 'Weapons included (class): '
 local weaponLine=prefix..(#weaponList>0 and table.concat(weaponList,', ') or 'None')..dwText
 return armorLine,weaponLine
end
local slotInvs={[1]={1},[2]={2},[3]={3},[5]={5,20},[6]={6},[7]={7},[8]={8},[9]={9},[10]={10},[11]={11},[12]={11},[13]={12},[14]={12},[15]={16},[16]={13,17,21},[17]={13,14,22,23},[18]={15,25,26,28}}
local invSlots={}
for slot,invs in pairs(slotInvs) do
 for _,inv in ipairs(invs) do
  local list=invSlots[inv];if not list then list={};invSlots[inv]=list end
  list[#list+1]=slot
 end
end
function G.SlotsForInv(inv) return invSlots[inv] end
local function KnowsSpellSafe(fn,spell)
 if not fn then return false end
 local v=fn(spell)
 return S.Public(v) and v==true
end
function G.Context(class,level,allArmor)
 local tier=armorTiers[class] and armorTiers[class][level<40 and 1 or 2]
 local known,parts,count={},{},0
 local ownClass=select(3,UnitClass('player'))
 local knownAPI=S.KnowsSpell or (C_SpellBook and C_SpellBook.IsSpellKnown) or IsSpellKnown
 local dual=false
 if S.Public(ownClass) and ownClass==class and (IsPlayerSpell or knownAPI) then
  for name,spell in pairs(weaponSpells) do
   if KnowsSpellSafe(IsPlayerSpell,spell) or KnowsSpellSafe(knownAPI,spell) then known[name]=true;count=count+1;parts[#parts+1]=spell end
  end
  dual=KnowsSpellSafe(IsPlayerSpell,674) or KnowsSpellSafe(knownAPI,674)
 end
 local fac=UnitFactionGroup and UnitFactionGroup('player')
 fac=(S.Public(fac) and type(fac)=='string' and fac~='') and fac or nil
 table.sort(parts)
 return {tier=not allArmor and tier or nil,weapons=count>0 and known or nil,dualWield=dual,faction=fac,key=class..':'..level..':'..tostring(allArmor)..':'..tostring(dual)..':'..(fac or '')..':'..table.concat(parts,','),trainingKnown=count>0}
end
function G.Candidates(slot,level,class,context)
 local key=context and context.key
 local bucket=key and candidateCache[key]
 if bucket and bucket[slot] then return bucket[slot] end
 local invs=slotInvs[slot] or {}
 local ids={}
 local records=G.records
 local slotsTable=G.slots
 for _,inv in ipairs(invs) do
  local list=slotsTable and slotsTable[inv]
  if list then
   for _,id in ipairs(list) do
    local raw=records and records[id]
    local required=level and raw and tonumber(raw:match('^(%d+)'))
    if not level or (required and required<=level) then
     local row=class and G.Get(id,true)
     if not class or G.Eligible(row,class,level,slot,nil,nil,context) then ids[#ids+1]=id end
    end
   end
  end
 end
 if key then
  if not bucket then
   local old=candidateOrder[candidateCursor];if old then candidateCache[old]=nil end
   candidateOrder[candidateCursor]=key;candidateCursor=candidateCursor%CAND_CAP+1
   bucket={};candidateCache[key]=bucket
  end
  bucket[slot]=ids
 end
 return ids
end
function G.ArmorUnlock(r,class)
 local rule=G.proficiency and G.proficiency[classNamesByID[class]]
 return r.class=='Armor' and bodySlots[r.inv] and rule and rule.armor[r.subclass] or 1
end
function G.FutureCandidates(slot,level,class,allArmor)
 local out,seen={},{}
 local tiers=armorTiers[class]
 local caps=(level<40 and tiers and tiers[1]~=tiers[2]) and {39,60} or {60}
 for _,cap in ipairs(caps) do
  if cap>level then
   for _,id in ipairs(G.Candidates(slot,cap,class,G.Context(class,cap,allArmor))) do
    if not seen[id] then seen[id]=true;out[#out+1]=id end
   end
  end
 end
 return out
end
local function WeaponSet(rule)
 local set=rule.weaponSet
 if not set then
  set={}
  for _,w in ipairs(rule.weapons or {}) do set[w]=true end
  rule.weaponSet=set
 end
 return set
end
function G.Eligible(r,classID,level,slot,current,otherID,context)
 if not r or not r.level or r.level>level or r.quality==0 then return false end
 if r.unavailable or (r.requiredProfession and r.requiredProfession~='') then return false end
 if r.faction and r.faction~='' then
  local fac=(context and context.faction) or (UnitFactionGroup and UnitFactionGroup('player'))
  if S.Public(fac) and type(fac)=='string' and fac~='' and fac~=r.faction then return false end
 end
 if r.classMask and r.classMask>0 and math.floor(r.classMask/2^(classID-1))%2==0 then return false end
 local rule=G.proficiency and G.proficiency[classNamesByID[classID]]
 if not rule then return false end
 if r.inv==23 and noFrillClasses[classID] then return false end
 if r.class=='Armor' and context and context.tier and bodySlots[slot] and r.subclass~=context.tier then return false end
 if r.class=='Weapon' then
  if slot==17 and context and not context.dualWield then return false end
  if context and context.weapons and not context.weapons[r.subclass] then return false end
  if not WeaponSet(rule)[r.subclass] then return false end
 elseif r.subclass~='Miscellaneous' then
  local required=rule.armor and rule.armor[r.subclass];if not required then return false end
  local knows=S.KnowsSpell or IsPlayerSpell or (C_SpellBook and C_SpellBook.IsSpellKnown)
  if required>level and not ((r.subclass=='Plate' and KnowsSpellSafe(knows,750)) or (r.subclass=='Mail' and KnowsSpellSafe(knows,8737))) then return false end
 end
 if r.unique and r.id==otherID then return false end
 -- Same weapon configuration only; a one-hand/two-hand swap needs a loadout comparison.
 if slot==16 and current and (r.inv==17)~=(current.inv==17) then return false end
 if slot==17 and current and current.blocked then return false end
 return true
end
