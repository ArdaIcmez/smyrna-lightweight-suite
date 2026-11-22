local _,S=...
-- The single equipment-data service for every Suite consumer.
local G={cache={},order={},cursor=1};S.Equipment=G
function G.Ensure()
 if G.records then return true end
 if S.Config.useDB==false or S.Config.data.equipment==false or (InCombatLockdown and InCombatLockdown()) then return false end
 local load=(C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
 return load and load('SmyrnaEquipmentDB') and G.records~=nil or false
end
function G.Get(id)
 if G.cache[id] then return G.cache[id] end
 local raw=G.records and G.records[id];if not raw then return end
 local f={};for value in (raw..'\t'):gmatch('(.-)\t') do f[#f+1]=value end
 local r={id=id,level=tonumber(f[1]),inv=tonumber(f[2]),classMask=tonumber(f[3]),quality=tonumber(f[4]),name=f[5],class=f[6],subclass=f[7],estimated=f[8]=='1',unique=f[9]=='1',bind=f[10],stats={},sources={}}
 for key,value in f[11]:gmatch('([^,:]+):([^,]+)') do r.stats[key]=tonumber(value) end
 for text in f[12]:gmatch('[^;]+') do
  local a={};for value in (text..'|'):gmatch('(.-)|') do a[#a+1]=value end
  r.sources[#r.sources+1]={kind=a[1],name=a[2],zone=a[3],level=tonumber(a[4]) or 0,chance=tonumber(a[5]),id=tonumber(a[6]),skill=tonumber(a[7]) or 0,reference=({Crafted='Recipe reference',Quest='Quest reference',AH='BoE; check listings'})[a[1]] or 'Classic source',faction=a[8] or '',classes=a[9] or '',repeatable=a[10]=='1'}
 end
 local previous=G.order[G.cursor];if previous then G.cache[previous]=nil end
 G.order[G.cursor]=id;G.cursor=G.cursor%256+1;G.cache[id]=r
 return r
end
function G.Candidates(slot,level)
 local invs=({[1]={1},[2]={2},[3]={3},[5]={5,20},[6]={6},[7]={7},[8]={8},[9]={9},[10]={10},[11]={11},[12]={11},[13]={12},[14]={12},[15]={16},[16]={13,17,21},[17]={13,14,22,23},[18]={15,25,26,28}})[slot] or {}
 local ids={};for _,inv in ipairs(invs) do for _,id in ipairs((G.slots and G.slots[inv]) or {}) do local required=level and tonumber(G.records[id]:match('^(%d+)'));if not level or (required and required<=level) then ids[#ids+1]=id end end end
 return ids
end
local names={[1]='Warrior',[2]='Paladin',[3]='Hunter',[4]='Rogue',[5]='Priest',[7]='Shaman',[8]='Mage',[9]='Warlock',[11]='Druid'}
function G.Eligible(r,classID,level,slot,current,otherID)
 if not r or r.level>level or r.quality==0 then return false end
 if r.classMask and r.classMask>0 and math.floor(r.classMask/2^(classID-1))%2==0 then return false end
 local rule=G.proficiency and G.proficiency[names[classID]]
 if not rule then return false end
 if r.class=='Weapon' then
  local found=false;for _,name in ipairs(rule.weapons or {}) do if name==r.subclass then found=true;break end end
  if not found then return false end
 elseif r.subclass~='Miscellaneous' then
  local required=rule.armor and rule.armor[r.subclass];if not required then return false end;if required>level and not (IsPlayerSpell and ((r.subclass=='Plate' and IsPlayerSpell(750)) or (r.subclass=='Mail' and IsPlayerSpell(8737)))) then return false end
 end
 if r.unique and r.id==otherID then return false end
 -- Same weapon configuration only; a one-hand/two-hand swap needs a loadout comparison.
 if slot==16 and current and (r.inv==17)~=(current.inv==17) then return false end
 if slot==17 and current and current.blocked then return false end
 return true
end
