local _,Suite=...
local B=Suite.Modules.SmyrnaBestiary
if not B or not B.Matchups then return end
local M=B.Matchups
local classSchools={MAGE={'arcane','fire','frost'},PALADIN={'physical','holy'},PRIEST={'holy','shadow'},WARLOCK={'shadow','fire','physical'},SHAMAN={'physical','nature','fire','frost'},DRUID={'physical','nature','arcane'},ROGUE={'physical','nature'},WARRIOR={'physical'},HUNTER={'physical','arcane','nature','fire'}}
local function Public(v) return not issecretvalue or not issecretvalue(v) end
function M.UpdatePlayerProfile()
 M.PlayerProfile=nil
 if not UnitClass then return end
 local className,class=UnitClass('player')
 if not Public(class) or type(class)~='string' or not classSchools[class] then return end
 M.PlayerProfile={Public(className) and type(className)=='string' and className or class,classSchools[class]}
end
function M.PlayerHint(id)
 local row=M.Evidence(id);if not row then return end
 local profile=M.PlayerProfile;if not profile then return end
 local names={physical='Physical',holy='Holy',fire='Fire',frost='Frost',nature='Nature',shadow='Shadow',arcane='Arcane'}
 local parts={}
 for _,school in ipairs(profile[2]) do
  local e=row.schools and row.schools[school];local label=names[school]
  if e and e.immune then parts[#parts+1]='|cffff786b'..label..': immune|r'
  elseif e and e.extraDamage and e.extraDamage>0 then parts[#parts+1]='|cff78d49b'..label..': weak +'..e.extraDamage..'%|r'
  elseif e and e.resistance and e.resistance~=0 then
   local value=e.resistance
   parts[#parts+1]=(value>0 and '|cffffb56b' or '|cff78d49b')..label..': '..(value>0 and ('resists ('..value..')') or ('low resistance ('..value..')'))..'|r'
  end
 end
 if #parts==0 then return end
 return profile[1]..' - '..table.concat(parts,' / ')..(row.scope=='Classic' and ' |cffaaaaaa(Classic)|r' or '')
end
local events=CreateFrame('Frame')
for _,event in ipairs({'PLAYER_LOGIN','PLAYER_TALENT_UPDATE','ACTIVE_TALENT_GROUP_CHANGED','PLAYER_SPECIALIZATION_CHANGED','SPELLS_CHANGED'}) do pcall(events.RegisterEvent,events,event) end
events:SetScript('OnEvent',function() M.UpdatePlayerProfile() end)
M.UpdatePlayerProfile()
