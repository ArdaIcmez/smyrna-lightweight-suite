local _,Suite=...
local B=Suite.Modules.SmyrnaBestiary
if not B then return end
local M={};B.Matchups=M
M.Schools={
 {"fire","Fire","ff754d",1.00,.46,.30,"Interface\\Icons\\Spell_Fire_Fireball02"},
 {"frost","Frost","78cfff",.47,.81,1.00,"Interface\\Icons\\Spell_Frost_FrostBolt02"},
 {"nature","Nature","86df70",.53,.87,.44,"Interface\\Icons\\Spell_Nature_Lightning"},
 {"arcane","Arcane","668cff",.40,.55,1.00,"Interface\\Icons\\Spell_Nature_StarFall"},
 {"holy","Holy","ffe58b",1.00,.90,.55,"Interface\\Icons\\Spell_Holy_HolyBolt"},
 {"shadow","Shadow","d284e8",.82,.52,.91,"Interface\\Icons\\Spell_Shadow_ShadowBolt"},
}
-- Damage profiles, not simulated class DPS or healing/tanking rankings.
M.Specs={
 {"Fire Mage",{"fire"}},{"Frost Mage",{"frost"}},{"Arcane Mage",{"arcane"}},
 {"Shadow Priest",{"shadow"}},{"Retribution Paladin",{"physical","holy"}},
 {"Elemental Shaman",{"nature","fire"}},{"Enhancement Shaman",{"physical","nature","fire"}},
 {"Balance Druid",{"nature","arcane"}},{"Feral Druid",{"physical"}},
 {"Affliction Warlock",{"shadow"}},{"Demonology Warlock",{"shadow","fire","physical"}},{"Destruction Warlock",{"fire","shadow"}},
 {"Arms Warrior",{"physical"}},{"Fury Warrior",{"physical"}},
 {"Assassination Rogue",{"physical","nature"}},{"Combat Rogue",{"physical"}},{"Subtlety Rogue",{"physical"}},
 {"Beast Mastery Hunter",{"physical"}},{"Marksmanship Hunter",{"physical"}},{"Survival Hunter",{"physical","nature"}},
}
function M.Evidence(id)
 if not B.DB then return end
 local rows=Suite.BestiaryDefenses;local row=rows and rows[id]
 if not row and not Suite.BestiaryDefenseReference and B.EnsureIndex then B.EnsureIndex() end
 if not row and Suite.BestiaryDefenseReference then row=Suite.BestiaryDefenseReference.Get(id) end
 if not row or not row.source then return end
 if row.scope=="Forever" or (row.scope=="Classic" and B.DB.settings.classic) then return row end
end
function M.Classify(row,profile)
 if not row then return "unknown" end
 local bad,good,unknown=0,0,0
 local stronger=false
 for _,school in ipairs(M.Schools) do local e=row.schools and row.schools[school[1]];if e and (e.immune or (e.resistance and e.resistance>0)) then stronger=true end end
 for _,school in ipairs(profile[2]) do
  local e=row.schools and row.schools[school]
  if not e then unknown=unknown+1
  elseif e.immune or (e.resistance and e.resistance>0) then bad=bad+1
  elseif (e.extraDamage and e.extraDamage>0) or (e.resistance and e.resistance<0) or (school~="physical" and e.resistance==0 and stronger) then good=good+1
  elseif e.resistance==nil then unknown=unknown+1 end
 end
 if bad==#profile[2] then return "disadvantaged" end
 if bad>0 then return "mixed" end
 if unknown>0 then return "unknown" end
 if good>0 then return "favorable" end
 return "neutral"
end
local function SchoolText(e)
 if not e then return end
 if e.immune then return "Immune" end
 local parts={}
 if e.resistance~=nil then parts[#parts+1]="Base resistance: "..e.resistance end
 if e.extraDamage and e.extraDamage>0 then parts[#parts+1]="Takes "..e.extraDamage.."% extra damage" end
 return #parts>0 and table.concat(parts,"; ") or nil
end
function M.HasData(id) return M.Evidence(id)~=nil end

local function SchoolStatus(e)
 if not e then return "Unknown",0,.55,.60,.68,false end
 if e.immune then return "IMMUNE",1,1,.34,.34,true end
 if e.extraDamage and e.extraDamage>0 then return "Weak +"..e.extraDamage.."%",.2,.37,.91,.56,true end
 if e.resistance and e.resistance>0 then return "Resist "..e.resistance,math.min(1,e.resistance/250),1,.68,.35,true end
 if e.resistance and e.resistance<0 then return "Weak ("..e.resistance..")",.2,.37,.91,.56,true end
 return "0 resist",0,.62,.68,.76,false
end

function M.Text(id)
 local row=M.Evidence(id);if not row then return "" end
 local text={Suite.UIText("Elemental defenses","heading")}
 for _,school in ipairs(M.Schools) do
  local value=SchoolText(row.schools and row.schools[school[1]])
  if value then text[#text+1]="|cff"..school[3]..school[2].."|r  -  "..value end
 end
 local physical=SchoolText(row.schools and row.schools.physical)
 if row.armor or physical then
  text[#text+1]="";text[#text+1]=Suite.UIText("Physical defense","heading")
  if row.armor then text[#text+1]="Base armor: "..row.armor end
  if physical then text[#text+1]=physical end
 end
 local groups={favorable={},disadvantaged={},mixed={},neutral={},unknown={}}
 for _,profile in ipairs(M.Specs) do local group=M.Classify(row,profile);groups[group][#groups[group]+1]=profile[1] end
 for _,group in ipairs({{"favorable","Favorable damage profiles","good"},{"disadvantaged","Disadvantaged damage profiles","warning"},{"mixed","Mixed damage - adapt your spells","detail"}}) do
  if #groups[group[1]]>0 then text[#text+1]="";text[#text+1]=Suite.UIText(group[2],group[3]);text[#text+1]=table.concat(groups[group[1]],", ") end
 end
 text[#text+1]="";text[#text+1]=Suite.UIText(row.scope.." reference - "..row.source,"muted")
 return table.concat(text,"\n")
end

function M.Build(parent)
 local pane=CreateFrame("Frame",nil,parent);pane:SetPoint("TOPLEFT",16,-78);pane:SetSize(486,348)
 local scroll=CreateFrame("ScrollFrame",nil,pane,"UIPanelScrollFrameTemplate");scroll:SetPoint("TOPLEFT");scroll:SetSize(464,342)
 local canvas=CreateFrame("Frame",nil,scroll);canvas:SetSize(446,360);scroll:SetScrollChild(canvas)
 scroll:EnableMouseWheel(true)
 scroll:SetScript("OnMouseWheel",function(self,delta)
  local cur,max=self:GetVerticalScroll(),self:GetVerticalScrollRange()
  if type(cur)=="number" and type(max)=="number" then self:SetVerticalScroll(math.max(0,math.min(max,cur-delta*36))) end
 end)

 Suite.OptionSection(canvas,"Elemental Resistances",0,-2,442)
 local schoolCards={}
 for i,school in ipairs(M.Schools) do
  local col=(i-1)%2;local rowIdx=math.floor((i-1)/2)
  local card=CreateFrame("Frame",nil,canvas,"BackdropTemplate")
  card:SetSize(217,52);card:SetPoint("TOPLEFT",col*225,-22-rowIdx*58)
  Suite.StyleCard(card,.082,.094,.128)
  local tile=Suite.CreateIconTile(card,32);tile:SetPoint("LEFT",8,0);tile.icon:SetTexture(school[7])
  tile:SetBackdropBorderColor(school[4],school[5],school[6],.9)
  local nameText=card:CreateFontString(nil,"OVERLAY","GameFontNormal")
  nameText:SetPoint("TOPLEFT",48,-8);nameText:SetText(school[2]);nameText:SetTextColor(school[4],school[5],school[6])
  local tagText=card:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  tagText:SetPoint("LEFT",nameText,"RIGHT",5,0);tagText:SetTextColor(1,.86,.48)
  local statusText=card:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
  statusText:SetPoint("TOPRIGHT",-9,-9);statusText:SetJustifyH("RIGHT")
  local barBg=card:CreateTexture(nil,"BACKGROUND",nil,3)
  barBg:SetPoint("BOTTOMLEFT",48,9);barBg:SetPoint("BOTTOMRIGHT",-9,9);barBg:SetHeight(5);barBg:SetColorTexture(.04,.048,.07,1)
  local barFill=card:CreateTexture(nil,"ARTWORK",nil,2)
  barFill:SetPoint("TOPLEFT",barBg,"TOPLEFT",0,0);barFill:SetPoint("BOTTOMLEFT",barBg,"BOTTOMLEFT",0,0);barFill:SetWidth(1)
  schoolCards[i]={card=card,tile=tile,name=nameText,tag=tagText,status=statusText,barBg=barBg,barFill=barFill,school=school}
 end

 local physCard=CreateFrame("Frame",nil,canvas,"BackdropTemplate")
 physCard:SetSize(442,84);physCard:SetPoint("TOPLEFT",0,-204)
 Suite.StyleCard(physCard,.082,.094,.128)
 Suite.SetCornerGlow(physCard,1,.78,.42,.12)
 local physTile=Suite.CreateIconTile(physCard,34);physTile:SetPoint("TOPLEFT",10,-12);physTile.icon:SetTexture("Interface\\Icons\\INV_Sword_04");physTile:SetBackdropBorderColor(1,.78,.42,.9)
 local physTitle=physCard:CreateFontString(nil,"OVERLAY","GameFontNormal");physTitle:SetPoint("TOPLEFT",52,-10);physTitle:SetText("Physical & Weapon Impact");physTitle:SetTextColor(1,.84,.48)
 local physBody=physCard:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");physBody:SetPoint("TOPLEFT",52,-28);physBody:SetWidth(378);physBody:SetJustifyH("LEFT");physBody:SetTextColor(.86,.90,.96)

 local specCard=CreateFrame("Frame",nil,canvas,"BackdropTemplate")
 specCard:SetSize(442,80);specCard:SetPoint("TOPLEFT",0,-296)
 Suite.StyleCard(specCard,.076,.088,.120)
 Suite.SetCornerGlow(specCard,.48,.76,1,.10)
 local specTitle=specCard:CreateFontString(nil,"OVERLAY","GameFontNormal");specTitle:SetPoint("TOPLEFT",12,-10);specTitle:SetText("Class & Spec Matchups");specTitle:SetTextColor(.64,.86,1)
 local specBody=specCard:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");specBody:SetPoint("TOPLEFT",12,-28);specBody:SetWidth(418);specBody:SetJustifyH("LEFT")

 local foot=canvas:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
 foot:SetPoint("TOPLEFT",4,-384);foot:SetWidth(438);foot:SetJustifyH("LEFT");foot:SetTextColor(.60,.66,.75)

 function pane:Refresh(id)
  local row=M.Evidence(id)
  if not row then
   for _,item in ipairs(schoolCards) do item.card:Hide() end
   physCard:Hide();specCard:Hide()
   foot:ClearAllPoints();foot:SetPoint("TOPLEFT",4,-28);foot:SetText("No defense data recorded for this creature.")
   canvas:SetHeight(342);scroll:SetVerticalScroll(0);scroll:UpdateScrollChildRect();return
  end
  local _,class=UnitClass("player")
  local ownSet={}
  if B.Core and B.Core.Public(class) and type(class)=="string" then
   for _,s in ipairs((M.ClassSchools and M.ClassSchools[class]) or {}) do ownSet[s]=true end
  end
  for _,item in ipairs(schoolCards) do
   local sc=item.school
   local e=row.schools and row.schools[sc[1]]
   local label,fillPct,sr,sg,sb,notable=SchoolStatus(e)
   local isOwn=ownSet[sc[1]]
   item.card:Show()
   item.tag:SetText(isOwn and "[You]" or "")
   item.status:SetText(label);item.status:SetTextColor(sr,sg,sb)
   local glowA=(notable and .20) or (isOwn and .12) or .05
   Suite.SetCornerGlow(item.card,sc[4],sc[5],sc[6],glowA)
   if isOwn then item.card:SetBackdropBorderColor(sc[4],sc[5],sc[6],.65)
   else item.card:SetBackdropBorderColor(.22,.25,.33,.88) end
   local maxW=160
   if fillPct>0 then
    item.barFill:Show();item.barFill:SetWidth(math.max(4,maxW*fillPct))
    local br,bg,bb=sc[4],sc[5],sc[6]
    if e and (e.immune or (e.extraDamage and e.extraDamage>0) or (e.resistance and e.resistance<0)) then br,bg,bb=sr,sg,sb end
    Suite.ApplyGradient(item.barFill,"HORIZONTAL",br*.55,bg*.55,bb*.55,.95,br,bg,bb,1)
   else
    item.barFill:Hide()
   end
  end

  local top=202
  local physText=M.PhysicalSummary and M.PhysicalSummary(id)
  if physText then
   physBody:SetText(physText)
   local h=math.max(66,34+physBody:GetStringHeight()+12)
   physCard:SetHeight(h);physCard:ClearAllPoints();physCard:SetPoint("TOPLEFT",0,-top);physCard:Show()
   top=top+h+8
  else
   physCard:Hide()
  end

  local groups={favorable={},disadvantaged={},mixed={}}
  for _,profile in ipairs(M.Specs) do
   local g=M.Classify(row,profile)
   if groups[g] then groups[g][#groups[g]+1]=profile[1] end
  end
  local specLines={}
  if #groups.favorable>0 then specLines[#specLines+1]="|cff78d49bFavorable:|r "..table.concat(groups.favorable,", ") end
  if #groups.mixed>0 then specLines[#specLines+1]="|cff8ecfffMixed:|r "..table.concat(groups.mixed,", ") end
  if #groups.disadvantaged>0 then specLines[#specLines+1]="|cffff8870Disadvantaged:|r "..table.concat(groups.disadvantaged,", ") end
  if #specLines>0 then
   specBody:SetText(table.concat(specLines,"\n"))
   local sh=math.max(58,32+specBody:GetStringHeight()+12)
   specCard:SetHeight(sh);specCard:ClearAllPoints();specCard:SetPoint("TOPLEFT",0,-top);specCard:Show()
   top=top+sh+8
  else
   specCard:Hide()
  end

  foot:ClearAllPoints();foot:SetPoint("TOPLEFT",4,-top)
  foot:SetText(row.scope.." data ("..row.source.."). Base values before buffs, debuffs, or scripted phases.")
  canvas:SetHeight(math.max(342,top+foot:GetStringHeight()+16))
  scroll:SetVerticalScroll(0);scroll:UpdateScrollChildRect()
 end
 pane:Hide();return pane
end
