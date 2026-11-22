local _,S=...
local B=S.Modules.SmyrnaBestiary;if not B or not B.Matchups then return end
local M=B.Matchups
local classes={MAGE={'arcane','fire','frost'},PALADIN={'physical','holy'},PRIEST={'holy','shadow'},WARLOCK={'shadow','fire'},SHAMAN={'physical','nature','fire','frost'},DRUID={'physical','nature','arcane'},ROGUE={'physical','nature'},WARRIOR={'physical'},HUNTER={'physical','arcane','nature','fire'}}
local names={physical='Weapon hits',holy='Holy',fire='Fire',frost='Frost',nature='Nature',shadow='Shadow',arcane='Arcane'}
local colors={physical='ffcb8c',holy='ffe58b',fire='ff754d',frost='78cfff',nature='86df70',shadow='d284e8',arcane='668cff'}
local function Number(v) return not (issecretvalue and issecretvalue(v)) and type(v)=='number' and v==v end
function M.ArmorFraction(armor,level)
 if not Number(armor) or not Number(level) or level<1 or level>60 then return end
 -- Classic reference model: armor/(armor + 400 + 85*attacker level), capped 75%.
 -- Source: CMaNGOS mangos-classic Unit::CalcArmorReducedDamage; no claim this
 -- is a measured Forever formula or the target's current debuffed armor.
 armor=math.max(0,armor)
 return math.min(.75,armor/(armor+400+85*level))
end
local function Context(id)
 local _,class=UnitClass('player');local schools=classes[class];if not schools then return end
 local mob=B.Core.Mob(id);local level=mob and mob[2];local rank=mob and mob[4] or 0
 for _,unit in ipairs({'mouseover','target'}) do
  local guid=UnitGUID and UnitGUID(unit)
  if guid and B.Core.NPC(guid)==id then local n=UnitLevel(unit);if Number(n) and n>0 then level=n;break end end
 end
 return class,schools,Number(level) and level or nil,rank
end
local function Status(e)
 if not e then return end
 if e.immune then return 'immune' end
 if e.extraDamage and e.extraDamage>0 then return 'weak (+'..e.extraDamage..'% damage)' end
 if e.resistance==0 then return 'no resistance' end
 if e.resistance and e.resistance>0 then return 'resistant' end
 if e.resistance and e.resistance<0 then return 'weak' end
end
function M.ArmorGrade(armor,level,rank)
 local band=S.BestiaryArmorBands and level and S.BestiaryArmorBands[level..':'..rank]
 if not band then return end
 return armor<band[1] and 'low' or armor>band[3] and 'high' or 'typical',band[4]
end
function M.PlayerHint(id)
 local row=M.Evidence(id);if not row then return end
 local _,schools=Context(id);if not schools then return end
 local parts={};local level=UnitLevel('player')
 for _,school in ipairs(schools) do
  local status=Status(row.schools and row.schools[school])
  if school=='physical' and not status and row.armor then
   local fraction=M.ArmorFraction(row.armor,level)
   if fraction then status=string.format('about %.0f%% less damage',fraction*100) end
  end
  if status then parts[#parts+1]='|cff'..colors[school]..names[school]..': '..status..'|r' end
 end
 if #parts>0 then return table.concat(parts,' / ')..(row.scope=='Classic' and ' |cffaaaaaa(Classic estimate)|r' or '') end
end
function M.Text(id)
 local row=M.Evidence(id);if not row then return '' end
 local class,schools,mobLevel,rank=Context(id);if not schools then return '' end
 local text={S.UIText('What your attacks do','heading')}
 for _,school in ipairs(schools) do
  if school=='physical' then
   local immune=row.schools and row.schools.physical and row.schools.physical.immune
   local fraction=M.ArmorFraction(row.armor,UnitLevel('player'))
   if immune then text[#text+1]=S.UIText('Your weapon hits: immune','warning')
   elseif fraction then
    text[#text+1]=S.UIText(string.format('Your weapon hits lose about %.1f%% damage.',fraction*100),'warning')
    local lo,hi
    if class=='HUNTER' and UnitRangedDamage then local _,a,b=UnitRangedDamage('player');lo,hi=a,b
    elseif UnitDamage then lo,hi=UnitDamage('player') end
    if Number(lo) and Number(hi) and lo>0 then
     text[#text+1]=string.format('Normal hit: %.0f-%.0f; after armor: about %.0f-%.0f.',lo,hi,lo*(1-fraction),hi*(1-fraction))
    end
    local grade=M.ArmorGrade(row.armor,mobLevel,rank)
    text[#text+1]='Armor '..row.armor..(grade and (' — '..grade..' for level '..mobLevel..' enemies.') or '.')
    local skillAPI=class=='HUNTER' and UnitRangedAttack or UnitAttackBothHands
    if skillAPI and mobLevel then
     local base,bonus,penalty=skillAPI('player')
     if class=='HUNTER' and Number(penalty) then bonus=(bonus or 0)+penalty end
     if Number(base) and base>0 and Number(bonus or 0) then
      local skill=base+(bonus or 0);local defense=mobLevel*5
      text[#text+1]=string.format('Weapon skill %.0f vs estimated defense %.0f.',skill,defense)
      text[#text+1]=S.UIText('Skill affects misses and avoidance; armor affects damage after a hit lands.','muted')
     end
    end
   end
  else
   local status=Status(row.schools and row.schools[school])
   if status then text[#text+1]='|cff'..colors[school]..names[school]..': '..status..'|r' end
  end
 end
 text[#text+1]='';text[#text+1]=S.UIText(row.scope..' reference: '..row.source,'muted')
 if classes[class][1]=='physical' then text[#text+1]=S.UIText('Estimates before crits, blocks, debuffs and special effects.','muted') end
 if row.scope=='Classic' then text[#text+1]=S.UIText('Forever values and combat rules may differ.','muted') end
 return table.concat(text,'\n')
end
