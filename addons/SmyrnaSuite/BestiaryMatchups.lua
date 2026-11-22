local _,Suite=...
local B=Suite.Modules.SmyrnaBestiary
if not B then return end
local M={};B.Matchups=M
M.Schools={{"fire","Fire","ff754d"},{"frost","Frost","78cfff"},{"nature","Nature","86df70"},{"arcane","Arcane","668cff"},{"holy","Holy","ffe58b"},{"shadow","Shadow","d284e8"}}
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
 local rows=Suite.BestiaryDefenses;local row=rows and rows[id]
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
 text[#text+1]="Base values; scripted phases and Forever changes may differ."
 text[#text+1]="Damage-school fit, not a DPS ranking."
 return table.concat(text,"\n")
end
function M.Build(parent)
 local pane=CreateFrame("Frame",nil,parent);pane:SetPoint("TOPLEFT",16,-78);pane:SetSize(486,330)
 local scroll=CreateFrame("ScrollFrame",nil,pane,"UIPanelScrollFrameTemplate");scroll:SetPoint("TOPLEFT");scroll:SetSize(464,318)
 local canvas=CreateFrame("Frame",nil,scroll);canvas:SetSize(444,318);scroll:SetScrollChild(canvas)
 local body=canvas:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");body:SetPoint("TOPLEFT");body:SetWidth(440);body:SetJustifyH("LEFT")
 pane.body=body
 function pane:Refresh(id) body:SetText(M.Text(id));canvas:SetHeight(math.max(318,body:GetStringHeight()+16));scroll:SetVerticalScroll(0);scroll:UpdateScrollChildRect() end
 pane:Hide();return pane
end
