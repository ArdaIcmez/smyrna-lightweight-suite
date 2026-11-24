local _,S=...
local B=S.Modules.SmyrnaBestiary;if not B or not B.Matchups then return end
local M=B.Matchups
local classes={
 MAGE={'arcane','fire','frost'},
 PALADIN={'holy'},
 PRIEST={'holy','shadow'},
 WARLOCK={'shadow','fire'},
 SHAMAN={'nature','fire','frost'},
 DRUID={'nature','arcane'},
 ROGUE={'nature'},
 WARRIOR={},
 HUNTER={'arcane','nature','fire'},
}
local physicalClasses={PALADIN=true,SHAMAN=true,DRUID=true,ROGUE=true,WARRIOR=true,HUNTER=true}
local names={physical='Weapon hits',holy='Holy',fire='Fire',frost='Frost',nature='Nature',shadow='Shadow',arcane='Arcane'}
local colors={physical='ffcb8c',holy='ffe58b',fire='ff754d',frost='78cfff',nature='86df70',shadow='d284e8',arcane='668cff'}
M.ClassSchools=classes
M.PhysicalClasses=physicalClasses

local function Number(v) return not (issecretvalue and issecretvalue(v)) and type(v)=='number' and v==v end
function M.ArmorFraction(armor,level)
 if not Number(armor) or not Number(level) or level<1 or level>70 then return end
 -- Classic reference model: armor/(armor + 400 + 85*attacker level), capped 75%.
 armor=math.max(0,armor)
 return math.min(.75,armor/(armor+400+85*level))
end
local function Context(id)
 local _,class=UnitClass('player')
 if (issecretvalue and issecretvalue(class)) or type(class)~='string' then return end
 local schools=classes[class];if not schools then return end
 local mob=B.Core.Mob(id);local level=mob and mob[2];local rank=mob and mob[4] or 0
 for _,unit in ipairs({'mouseover','target'}) do
  local guid=UnitGUID and UnitGUID(unit)
  if guid and not (issecretvalue and issecretvalue(guid)) and B.Core.NPC(guid)==id then local n=UnitLevel(unit);if Number(n) and n>0 then level=n;break end end
 end
 return class,schools,Number(level) and level or nil,rank
end
M.Context=Context

local function Status(e,zeroLabel)
 if not e then return end
 if e.immune then return 'immune',true end
 if e.extraDamage and e.extraDamage>0 then return 'weak (+'..e.extraDamage..'%)',true end
 if e.resistance and e.resistance>0 then return 'resist '..e.resistance,true end
 if e.resistance and e.resistance<0 then return 'weak ('..e.resistance..')',true end
 if zeroLabel and e.resistance==0 then return zeroLabel,false end
end

function M.ArmorGrade(armor,level,rank)
 local band=S.BestiaryArmorBands and level and S.BestiaryArmorBands[level..':'..rank]
 if not band then return end
 return armor<band[1] and 'low' or armor>band[3] and 'high' or 'typical',band[4]
end

-- Hover tooltip shows only elemental resistances relevant to the player's class
-- (plus physical immunity if any). Full armor/weapon math lives in Ctrl+click details.
function M.PlayerHint(id)
 local row=M.Evidence(id);if not row then return end
 local class,schools=Context(id);if not schools then return end
 local parts={}
 local anyNotable,anyKnown=false,false
 if physicalClasses[class] and row.schools and row.schools.physical and row.schools.physical.immune then
  parts[#parts+1]='|cffff6666Physical: immune|r'
  anyNotable=true; anyKnown=true
 end
 for _,school in ipairs(schools) do
  local status,notable=Status(row.schools and row.schools[school],'none')
  if status then
   anyKnown=true
   if notable then anyNotable=true end
   local valColor=notable and colors[school] or '9aa4b2'
   parts[#parts+1]='|cff'..colors[school]..names[school]..':|r |cff'..valColor..status..'|r'
  end
 end
 if not anyKnown then return end
 if not anyNotable then return '|cff9aa4b2No resistances|r' end
 return table.concat(parts,'  /  ')
end

function M.PhysicalSummary(id)
 local row=M.Evidence(id);if not row then return nil end
 local class,_,mobLevel,rank=Context(id)
 local immune=row.schools and row.schools.physical and row.schools.physical.immune
 local lines={}
 if immune then
  lines[#lines+1]='|cffff5c5cImmune to physical weapon attacks.|r'
 end
 if row.armor then
  local grade=M.ArmorGrade(row.armor,mobLevel,rank)
  local gradeColor=grade=='high' and 'ff9b6a' or grade=='low' and '78d49b' or '8ecfff'
  local gradeTag=(grade and Number(mobLevel)) and ('  (|cff'..gradeColor..grade..' for Lv '..mobLevel..'|r)') or ''
  lines[#lines+1]='Armor: |cffffffff'..row.armor..'|r'..gradeTag
  local pLevel=UnitLevel and UnitLevel('player')
  local fraction=M.ArmorFraction(row.armor,pLevel)
  if fraction and physicalClasses[class] then
   local pct=string.format('%.1f%%',fraction*100)
   local hitLine='Est. weapon reduction: |cffffc478~'..pct..'|r'
   local lo,hi
   if class=='HUNTER' and UnitRangedDamage then local _,a,b=UnitRangedDamage('player');lo,hi=a,b
   elseif UnitDamage then lo,hi=UnitDamage('player') end
   if Number(lo) and Number(hi) and lo>0 then
    hitLine=hitLine..string.format('  (hit %.0f-%.0f -> ~%.0f-%.0f)',lo,hi,lo*(1-fraction),hi*(1-fraction))
   end
   lines[#lines+1]=hitLine
   local skillAPI=class=='HUNTER' and UnitRangedAttack or UnitAttackBothHands
   if skillAPI and mobLevel then
    local base,bonus,penalty=skillAPI('player')
    if class=='HUNTER' and Number(penalty) then bonus=(bonus or 0)+penalty end
    if Number(base) and base>0 and Number(bonus or 0) then
     local skill=base+(bonus or 0);local defense=mobLevel*5
     lines[#lines+1]=string.format('Weapon skill |cffffffff%.0f|r vs est. defense |cffffffff%.0f|r',skill,defense)
    end
   end
  end
 end
 if #lines==0 then return nil end
 return table.concat(lines,'\n')
end

function M.Text(id)
 local row=M.Evidence(id);if not row then return '' end
 local _,schools=Context(id);if not schools then return '' end
 local text={S.UIText('Elemental resistances','heading')}
 for _,school in ipairs(schools) do
  local status=Status(row.schools and row.schools[school],'no resistance')
  if status then text[#text+1]='|cff'..colors[school]..names[school]..': '..status..'|r' end
 end
 local phys=M.PhysicalSummary(id)
 if phys then text[#text+1]='';text[#text+1]=S.UIText('Physical & armor','heading');text[#text+1]=phys end
 text[#text+1]='';text[#text+1]=S.UIText(row.scope..' data: '..row.source,'muted')
 return table.concat(text,'\n')
end
