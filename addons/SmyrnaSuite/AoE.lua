local _,Suite=...
local A={};Suite.AoE=A
local specs={{26573,'Consecration',8,'PALADIN'},{1449,'Arcane Explosion',10,'MAGE'},{122,'Frost Nova',10,'MAGE'}}
local panel,bar,timer,rows
local function public(v) return not issecretvalue or not issecretvalue(v) end
function A.Classify(lo,hi,r)
 if not public(lo) or not public(hi) or type(lo)~='number' or type(hi)~='number' then return 'unknown' end
 if hi>lo and hi<=r then return 'inside' end
 if lo>=r and lo>0 then return 'outside' end
 return 'unknown'
end
function A.Count(radius)
 local inside,unknown,total=0,0,0
 local seen={}
 local function visit(unit)
  local guid=UnitGUID(unit)
  if not public(guid) or not guid or seen[guid] then return end
  seen[guid]=true
  local hostile=UnitCanAttack('player',unit);local dead=UnitIsDeadOrGhost(unit)
  if not public(hostile) or not public(dead) or not hostile or dead then return end
  total=total+1
  local state='unknown'
  local api=DBM and DBM.RangeCheck
  if api and api.GetUnitMinMaxRange then
   local ok,lo,hi=pcall(api.GetUnitMinMaxRange,api,unit)
   if ok then state=A.Classify(lo,hi,radius) end
  end
  if state=='inside' then inside=inside+1 elseif state=='unknown' then unknown=unknown+1 end
 end
 visit('target');visit('focus')
 for i=1,40 do visit('nameplate'..i) end
 return inside,unknown,total
end
local function stop() if timer then timer:Cancel();timer=nil end end
local function update()
 for _,row in ipairs(rows or {}) do
  local n,u=A.Count(row.radius)
  row.label:SetText(string.format('%s (%dy): |cffff7777%d inside|r / %d uncertain',row.name,row.radius,n,u))
 end
end
local function preview()
 panel:Show();update()
 if not timer then timer=C_Timer.NewTicker(.25,update) end
end
function A.Open()
 if InCombatLockdown() then DEFAULT_CHAT_FRAME:AddMessage('Smyrna: open AoE before combat.');return end
 if not panel then
  panel=CreateFrame('Frame','SmyrnaAoEPreview',UIParent,'BackdropTemplate');panel:SetSize(390,110);panel:SetPoint('CENTER',0,140)
  panel:SetBackdrop({bgFile='Interface\\Buttons\\WHITE8X8'});panel:SetBackdropColor(.025,.025,.03,.94)
  panel:SetScript('OnHide',stop)
  local hint=panel:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');hint:SetPoint('BOTTOMLEFT',10,10);hint:SetText('Visible enemies only. Distance bands; hits not guaranteed.')
  bar=CreateFrame('Frame','SmyrnaAoEButtons',UIParent);bar:SetSize(390,32);bar:SetPoint('CENTER',0,65)
  rows={}
  local _,class=UnitClass('player')
  for _,s in ipairs(specs) do if s[4]==class then
   local index=#rows+1
   local row={radius=s[3],name=s[2]};rows[index]=row
   row.label=panel:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');row.label:SetPoint('TOPLEFT',10,-12-(index-1)*22)
   local b=CreateFrame('Button','SmyrnaAoECast'..s[1],bar,'SecureActionButtonTemplate,UIPanelButtonTemplate');b:SetSize(180,28);b:SetPoint('LEFT',(index-1)*185,0);b:SetText(s[2])
   local info=C_Spell and C_Spell.GetSpellInfo(s[1]);local spell=info and info.name or s[2]
   b:SetAttribute('type1','spell');b:SetAttribute('spell1',spell);b:SetAttribute('useOnKeyDown',false);b:RegisterForClicks('LeftButtonDown','LeftButtonUp')
   b:SetScript('PreClick',function(_,button,down) if button=='LeftButton' and down then preview() end end)
   b:SetScript('PostClick',function(_,button,down) if button=='LeftButton' and not down then panel:Hide() end end)
  end end
 end
 if #rows==0 then DEFAULT_CHAT_FRAME:AddMessage('Smyrna AoE: currently supports Paladin and Mage.');return end
 bar:Show();preview()
end
SLASH_SMYRNAAOE1='/saoe'
SlashCmdList.SMYRNAAOE=function(msg)
 if msg=='hide' then if panel then panel:Hide() end;if bar and not InCombatLockdown() then bar:Hide() end else A.Open() end
end
