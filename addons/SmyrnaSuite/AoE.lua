local _,Suite=...
local A={};Suite.AoE=A
local specs={{26573,'Consecration',8,'PALADIN'},{1449,'Arcane Explosion',10,'MAGE'},{122,'Frost Nova',10,'MAGE'}}
local panel,bar,timer,rows
local seen,byRadius={},{}
local public=Suite.Public or function(v) return not issecretvalue or not issecretvalue(v) end
function A.Classify(lo,hi,r)
 if not public(lo) or not public(hi) or type(lo)~='number' or type(hi)~='number' then return 'unknown' end
 if hi>0 and hi>=lo and hi<=r then return 'inside' end
 if lo>=r and lo>0 then return 'outside' end
 return 'unknown'
end
local function UnitBracket(unit)
 local api=DBM and DBM.RangeCheck
 if api and api.GetUnitMinMaxRange then
  local ok,lo,hi=pcall(api.GetUnitMinMaxRange,api,unit)
  if ok and public(lo) and public(hi) and type(lo)=='number' and type(hi)=='number' and hi>=lo then return lo,hi end
 end
 local am=Suite.Modules and Suite.Modules.SmyrnaAggroMate
 if am and am.EstimateRange then
  local lo,hi=am.EstimateRange(unit)
  if lo and hi then return lo,hi end
 end
 -- Native Forever 16001 fallback: calibrated hostile item probes (8149 = 8yd, 17626 = 13yd)
 local isItem=(C_Item and C_Item.IsItemInRange) or IsItemInRange
 if isItem and UnitExists and UnitExists(unit) and not (UnitIsFriend and UnitIsFriend('player',unit)) then
  local lo,hi=0,60
  local ok8,r8=pcall(isItem,8149,unit)
  if ok8 and public(r8) then
   if r8==true or r8==1 then hi=8 elseif r8==false or r8==0 then lo=8 end
  end
  if hi>8 then
   local ok13,r13=pcall(isItem,17626,unit)
   if ok13 and public(r13) then
    if r13==true or r13==1 then hi=13 elseif r13==false or r13==0 then lo=13 end
   end
  end
  if hi<60 or lo>0 then return lo,hi end
 end
 return nil,nil
end
function A.Count(radius)
 local inside,unknown,total=0,0,0
 wipe(seen)
 local function visit(unit)
  local guid=UnitGUID(unit)
  if not public(guid) or not guid or seen[guid] then return end
  seen[guid]=true
  local hostile=UnitCanAttack('player',unit);local dead=UnitIsDeadOrGhost(unit)
  if not public(hostile) or not public(dead) or not hostile or dead then return end
  total=total+1
  local lo,hi=UnitBracket(unit)
  local state=(lo and hi) and A.Classify(lo,hi,radius) or 'unknown'
  if state=='inside' then inside=inside+1 elseif state=='unknown' then unknown=unknown+1 end
 end
 visit('target');visit('focus')
 for i=1,40 do visit('nameplate'..i) end
 return inside,unknown,total
end
local function stop() if timer then timer:Cancel();timer=nil end end
local function update()
 if not panel or not panel:IsShown() then stop();return end
 wipe(byRadius)
 for _,row in ipairs(rows or {}) do
  local cached=byRadius[row.radius]
  local n,u
  if cached then
   n,u=cached[1],cached[2]
  else
   n,u=A.Count(row.radius)
   byRadius[row.radius]={n,u}
  end
  row.label:SetText(string.format('%s (%dy): |cffff7777%d inside|r / %d uncertain',row.name,row.radius,n,u))
 end
end
local function preview()
 if not panel then return end
 panel:Show();update()
 if not timer then timer=C_Timer.NewTicker(.25,update) end
end
function A.Open()
 if InCombatLockdown and InCombatLockdown() then DEFAULT_CHAT_FRAME:AddMessage('|cffdfb66bSmyrna:|r Open AoE before combat.');return end
 local _,class=UnitClass('player')
 local supported=false
 for _,s in ipairs(specs) do if s[4]==class then supported=true;break end end
 if not supported then DEFAULT_CHAT_FRAME:AddMessage('|cffdfb66bSmyrna AoE:|r Currently supports Paladin and Mage.');return end
 if not panel then
  panel=CreateFrame('Frame','SmyrnaAoEPreview',UIParent,'BackdropTemplate');panel:SetSize(390,110);panel:SetPoint('CENTER',0,140)
  panel:SetClampedToScreen(true);Suite.StylePanel(panel,true)
  Suite.CloseButton(panel)
  panel:SetScript('OnHide',stop)
  local hint=panel:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');hint:SetPoint('BOTTOMLEFT',10,10);hint:SetText('Visible enemies only. Distance bands; hits not guaranteed.')
  bar=CreateFrame('Frame','SmyrnaAoEButtons',UIParent);bar:SetSize(390,32);bar:SetPoint('CENTER',0,65);bar:SetClampedToScreen(true)
  bar:SetScript('OnHide',function() if panel then panel:Hide() end;stop() end)
  rows={}
  for _,s in ipairs(specs) do if s[4]==class then
   local index=#rows+1
   local row={radius=s[3],name=s[2]};rows[index]=row
   row.label=panel:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');row.label:SetPoint('TOPLEFT',10,-12-(index-1)*22)
   local b=CreateFrame('Button','SmyrnaAoECast'..s[1],bar,'SecureActionButtonTemplate,UIPanelButtonTemplate');b:SetSize(180,28);b:SetPoint('LEFT',(index-1)*185,0);b:SetText(s[2]);Suite.StyleButton(b)
   local info=C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(s[1])
   local spell=(info and info.name) or (GetSpellInfo and GetSpellInfo(s[1])) or s[2]
   b:SetAttribute('type1','spell');b:SetAttribute('spell1',spell);b:SetAttribute('useOnKeyDown',false);b:RegisterForClicks('LeftButtonDown','LeftButtonUp')
   b:SetScript('PreClick',function(_,button,down) if button=='LeftButton' and down then preview() end end)
   b:SetScript('PostClick',function(_,button,down) if button=='LeftButton' and not down then panel:Hide() end end)
   b:SetScript('OnLeave',function() if panel and panel:IsShown() then panel:Hide() end end)
  end end
 end
 bar:Show();preview()
end
SLASH_SMYRNAAOE1='/saoe'
SlashCmdList.SMYRNAAOE=function(msg)
 local cmd=string.lower((msg or ''):match('^%s*(%S*)') or '')
 if cmd=='hide' then
  if panel then panel:Hide() end
  if bar and not (InCombatLockdown and InCombatLockdown()) then bar:Hide() end
 else A.Open() end
end
