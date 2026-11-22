local _,S=...
local name='SmyrnaUpgrader';S.Versions[name]='0.1.0'
if S.Config.features[name]==false then return end
local U={};S.Modules[name]=U
local G=S.Equipment
local defaults={enabled=true,engine='standalone',profile='auto',classic=true}
S.Config.upgrader=S.Config.upgrader or {}
local cfg=S.Config.upgrader
cfg.engine='standalone'
if type(cfg.profile)=='string' and cfg.profile:match('^pawn:') then cfg.profile='auto' end
for k,v in pairs(defaults) do if cfg[k]==nil then cfg[k]=v end end
local classNames={[1]='Warrior',[2]='Paladin',[3]='Hunter',[4]='Rogue',[5]='Priest',[7]='Shaman',[8]='Mage',[9]='Warlock',[11]='Druid'}
local specs={[1]={'Arms','Fury','Protection'},[2]={'Holy','Protection','Retribution'},[3]={'Beast Mastery','Marksmanship','Survival'},[4]={'Assassination','Combat','Subtlety'},[5]={'Discipline','Holy','Shadow'},[7]={'Elemental','Enhancement','Restoration'},[8]={'Arcane','Fire','Frost'},[9]={'Affliction','Demonology','Destruction'},[11]={'Balance','Feral damage','Feral tank','Restoration'}}
local slots={Head=1,Neck=2,Shoulder=3,Chest=5,Waist=6,Legs=7,Feet=8,Wrist=9,Hands=10,Finger0=11,Finger1=12,Trinket0=13,Trinket1=14,Back=15,MainHand=16,SecondaryHand=17,Ranged=18}
local results,serial,busy={},0,nil
local function Safe(value) return not (issecretvalue and issecretvalue(value)) end
local function Number(value) return Safe(value) and type(value)=='number' and value==value end
function U.Invalidate() results={};serial=serial+1;busy=nil end
function U.Profile()
 local _,_,class=UnitClass('player');if not Number(class) then return end
 local spec=tonumber(cfg.profile:match('^local:(%d+)$'))
 if not spec and GetTalentTabInfo then
  local best,points,tied=nil,0,false
  for i=1,3 do local _,_,p=GetTalentTabInfo(i);if Number(p) then if p>points then best,points,tied=i,p,false elseif p==points and p>0 then tied=true end end end
  if not tied then spec=best;if class==11 and spec==3 then spec=4 end end
 end
 if not spec and GetSpecialization then local p=GetSpecialization();if Number(p) and p>0 then spec=p end end
 local weights=spec and S.PrivatePawn.Scales[class..':'..spec]
 if not weights then return nil,'Choose your profile in Upgrader settings.' end
 return {engine='Standalone Pawn '..S.PrivatePawn.Version,key=class..':'..spec,label=(classNames[class] or 'Class')..' / '..((specs[class] or {})[spec] or tostring(spec)),weights=weights,class=class}
end
local function Fingerprint(profile)
 local w=profile.weights or (PawnCommon and PawnCommon.Scales[profile.key] and PawnCommon.Scales[profile.key].Values) or {}
 local keys={};for k in pairs(w) do keys[#keys+1]=k end;table.sort(keys)
 local text={profile.engine,profile.key,G.build or ''}
 for _,k in ipairs(keys) do text[#text+1]=k..'='..tostring(w[k]) end
 return table.concat(text,';')
end
function U.Score(row,profile)
 return S.PrivatePawn.Score(row.stats,profile.weights)
end
function U.Better(a,b)
 if not b then return true end
 local al,bl=math.max(a.row.level,a.source.level),math.max(b.row.level,b.source.level)
 if al~=bl then return al<bl end
 if a.source.level~=b.source.level then return a.source.level<b.source.level end
 if a.score~=b.score then return a.score>b.score end
 return a.row.id<b.row.id
end
function U.SelectSource(row,level)
 local out={}
 for _,src in ipairs(row.sources) do
  local allowed=src.level<=level+3 and (cfg.classic or src.kind=='Crafted' or src.kind=='Quest' or src.kind=='AH')
  if src.kind=='Quest' then
   local faction=UnitFactionGroup and UnitFactionGroup('player')
   if src.faction~='' and src.faction~='Both' and faction and src.faction~=faction then allowed=false end
   local _,_,class=UnitClass('player')
   if src.classes~='' and not src.classes:find(classNames[class] or '?',1,true) then allowed=false end
   if src.repeatable~=true and C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(src.id) then allowed=false end
  end
  if allowed then
   if not out[src.kind] or src.level<out[src.kind].level then out[src.kind]=src end
  end
 end
 return out
end
local function ItemID(link) return Safe(link) and type(link)=='string' and tonumber(link:match('item:(%d+)')) end
function U.SourceLabel(c)
 local kind=({Dungeon='Dungeon',Quest='Quest',Crafted='Profession',World='World drop'})[c.source.kind] or c.source.kind
 if (c.source.kind=='Crafted' or c.source.kind=='World') and c.row.bind=='Binds when equipped' then kind=kind..' (AH)' end
 return kind
end
function U.Insert(top,c)
 for _,old in ipairs(top) do if old.row.id==c.row.id then return end end
 local at=#top+1
 for i,old in ipairs(top) do if U.Better(c,old) then at=i;break end end
 if at<=10 then table.insert(top,at,c);if #top>10 then table.remove(top) end end
end
local function Append(tip,state)
 local c=state.ranked[1]
 if c then
  tip:AddLine('Nearest upgrade: '..c.row.name..(c.percent and string.format(' (+%.1f%%)',c.percent) or ''),.47,.83,.61,true)
  local src=c.source;tip:AddLine(U.SourceLabel(c)..': '..(src.zone~='' and (src.zone..' / ') or '')..src.name..(src.reference=='Classic source' and ' [Classic]' or ''),.55,.76,.94,true)
 else tip:AddLine('Nearest upgrade: none found in eligible reference data.',.65,.65,.7,true) end
 tip:AddLine('Ctrl + left-click: ranked upgrades',.94,.77,.35)
 tip:Show()
end
local function Notice(tip,text) tip:AddLine('Upgrader: '..text,.6,.8,1,true);tip:Show() end
function U.Hover(owner,slot,hoveredID,tooltip)
 if S.IsLootInteraction and S.IsLootInteraction(owner) then return end
 if not cfg.enabled then return end
 local tip=tooltip or GameTooltip
 if not G.Ensure() then Notice(tip,'Enable Equipment DB; first load is deferred during combat.');return end
 local profile,reason=U.Profile();if not profile then Notice(tip,reason);return end
 local link=hoveredID and ('item:'..hoveredID) or GetInventoryItemLink('player',slot);local id=ItemID(link);local row=id and G.Get(id)
 if not link then tip:SetOwner(owner,'ANCHOR_RIGHT');tip:SetText('Empty equipment slot') end
 if id and not row then Notice(tip,'Equipped item is not in the reference DB yet.');return end
 local level=UnitLevel('player');if not Number(level) then return end
 local currentScore=id and U.Score(row,profile,link) or 0
 if not Number(currentScore) then Notice(tip,'Equipped item score is not available yet.');return end
 local signature={Fingerprint(profile),tostring(level),tostring(slot),tostring(id),tostring(currentScore),tostring(cfg.classic)}
 for i=1,18 do signature[#signature+1]=GetInventoryItemLink('player',i) or '' end
 local key=table.concat(signature,'|')
 if results[slot] and results[slot].key==key then Append(tip,results[slot]);if U.RenderDetails then U.RenderDetails(results[slot]) end;return end
 if busy==key then Notice(tip,'Checking upgrades…');return end
 serial=serial+1;local token=serial;busy=key
 local ids=G.Candidates(slot,level);local index=1;local best={};local ranked={};local rankedAH={};local pending=0
 local other=(slot==11 and 12) or (slot==12 and 11) or (slot==13 and 14) or (slot==14 and 13)
 local otherID=other and ItemID(GetInventoryItemLink('player',other))
 if slot==17 then local main=G.Get(ItemID(GetInventoryItemLink('player',16)));if main and main.inv==17 then Notice(tip,'Two-hand loadout occupies the off hand.');busy=nil;return end end
 Notice(tip,'Checking upgrades…')
 local function Finish()
  busy=nil
  results[slot]={key=key,profile=profile,rows=best,ranked=ranked,rankedAH=rankedAH,pending=pending,slot=slot,baseID=id,baseName=row and row.name or 'Empty slot'}
  U.LastResult=results[slot];if U.RenderDetails then U.RenderDetails(results[slot]) end
  if tip:IsShown() and tip:GetOwner()==owner then
   tip:ClearLines();tip:SetOwner(owner,'ANCHOR_RIGHT')
   U.Refreshing=true
   if hoveredID then tip:SetHyperlink(link) elseif link then tip:SetInventoryItem('player',slot) else tip:SetText('Empty equipment slot') end
   U.Refreshing=false
   Append(tip,results[slot])
  end
 end
 local function Batch()
  if token~=serial then return end
  if not hoveredID and CharacterFrame and not CharacterFrame:IsShown() and not (U.Details and U.Details:IsShown()) then busy=nil;return end
  -- Bounded standalone scoring batches, not a whole-catalog hover scan.
  for _=1,32 do
   local candidate=ids[index];index=index+1
   if not candidate then Finish();return end
   local r=G.Get(candidate)
   if candidate~=id and G.Eligible(r,profile.class,level,slot,row,otherID) and (cfg.classic or not r.estimated) then
    local sourceRows=U.SelectSource(r,level)
    if next(sourceRows) then
     local value,why=U.Score(r,profile)
     if Number(value) and value>currentScore and value>0 then
      local nearest
      for kind,source in pairs(sourceRows) do
       local c={row=r,source=source,score=value,percent=currentScore>0 and (value/currentScore-1)*100 or nil}
       if U.Better(c,best[kind]) then best[kind]=c end
       if not nearest or source.level<nearest.source.level then nearest=c end
      end
      if nearest then U.Insert(ranked,nearest);if r.bind=='Binds when equipped' then U.Insert(rankedAH,nearest) end end
     elseif why=='pending' then
      pending=pending+1
      if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(candidate) end
     end
    end
   end
  end
  C_Timer.After(.01,Batch)
 end
 C_Timer.After(0,Batch)
end
local function HookSlots()
 for label,slot in pairs(slots) do
  local b=_G['Character'..label..'Slot']
  if b and not b.smyrnaUpgrader then
   b.smyrnaUpgrader=true;b:HookScript('OnEnter',function(self) U.Hover(self,slot) end)
   b:HookScript('OnMouseUp',function(self,button) if button=='LeftButton' and IsControlKeyDown() then U.OpenDetails(slot,nil,self) end end)
  end
 end
end
local panel
function U.Open()
 if not panel then
  panel=CreateFrame('Frame','SmyrnaUpgraderOptions',UIParent,'BackdropTemplate');panel:SetSize(700,430);S.StylePanel(panel)
  panel.SuiteCloseButton=S.CloseButton(panel)
  local title=panel:CreateFontString(nil,'OVERLAY','GameFontNormalLarge');title:SetPoint('TOPLEFT',20,-20);title:SetText('Upgrader')
  local help=panel:CreateFontString(nil,'OVERLAY','GameFontHighlight');help:SetPoint('TOPLEFT',20,-55);help:SetWidth(655);help:SetJustifyH('LEFT')
  help:SetText('Press C and hover equipped gear. Find a next upgrade from a dungeon, quest, crafting, world source or BoE/AH reference.\n\nNo Pawn dependency. Embedded scoring uses the private Pawn snapshot and reference base stats. Select the profile you want; no spec is inferred from your spell usage.\n\nPercentages are stat-score changes, not DPS or healing predictions. Weapon recommendations keep the same one-hand/two-hand configuration.')
  local enabled=CreateFrame('CheckButton',nil,panel,'UICheckButtonTemplate');enabled:SetPoint('TOPLEFT',18,-210);enabled:SetChecked(cfg.enabled)
  local label=enabled:CreateFontString(nil,'OVERLAY','GameFontHighlight');label:SetPoint('LEFT',enabled,'RIGHT',0,0);label:SetText('Show upgrades on character-slot hover')
  enabled:SetScript('OnClick',function(self) cfg.enabled=not not self:GetChecked();U.Invalidate() end)
  local classic=CreateFrame('CheckButton',nil,panel,'UICheckButtonTemplate');classic:SetPoint('TOPLEFT',18,-242);classic:SetChecked(cfg.classic)
  local ct=classic:CreateFontString(nil,'OVERLAY','GameFontHighlight');ct:SetPoint('LEFT',classic,'RIGHT',0,0);ct:SetText('Include labelled Classic source / estimated item references')
  classic:SetScript('OnClick',function(self) cfg.classic=not not self:GetChecked();U.Invalidate() end)
  local button=CreateFrame('Button',nil,panel,'UIPanelButtonTemplate');button:SetPoint('TOPLEFT',20,-290);button:SetSize(650,27);S.StyleButton(button)
  local function Choices()
   local _,_,class=UnitClass('player');local options={{key='auto',label='Automatic talent profile'}}
   for i,label in ipairs(specs[class] or {}) do options[#options+1]={key='local:'..i,label='Standalone: '..label} end
   return options
  end
  local function Refresh() local p,err=U.Profile();button:SetText('Profile: '..(p and p.label or err or 'Select a profile')..'  — click to change') end
  button:SetScript('OnClick',function()
   local choices=Choices();local index=1;for i,p in ipairs(choices) do if p.key==cfg.profile then index=i;break end end
   cfg.profile=choices[index%#choices+1].key;U.Invalidate();Refresh()
  end)
  panel:SetScript('OnShow',Refresh)
  local status=panel:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');status:SetPoint('TOPLEFT',20,-338);status:SetWidth(655);status:SetJustifyH('LEFT');status:SetText('Shared data: Equipment DB (optional AddOns package). No separate gear catalogs per feature.\nSource coverage is incomplete; dungeon lockouts, keys and quest prerequisites are not verified.')
 end
 panel:Show();return panel
end
local driver=CreateFrame('Frame');driver:RegisterEvent('PLAYER_LOGIN');driver:RegisterEvent('ADDON_LOADED');driver:RegisterEvent('PLAYER_EQUIPMENT_CHANGED');driver:RegisterEvent('PLAYER_LEVEL_UP');pcall(driver.RegisterEvent,driver,'CHARACTER_POINTS_CHANGED');pcall(driver.RegisterEvent,driver,'PLAYER_TALENT_UPDATE')
driver:SetScript('OnEvent',function(_,event) if event=='PLAYER_LOGIN' or event=='ADDON_LOADED' then HookSlots() else U.Invalidate() end end)
SLASH_SMYRNAUPGRADER1='/su';SlashCmdList.SMYRNAUPGRADER=function() U.Open() end

S.Loaded[name]=true

local invToSlot={[1]=1,[2]=2,[3]=3,[5]=5,[6]=6,[7]=7,[8]=8,[9]=9,[10]=10,[11]=11,[12]=13,[13]=16,[14]=17,[15]=18,[16]=15,[17]=16,[20]=5,[21]=16,[22]=17,[23]=17,[25]=18,[26]=18,[28]=18}
function U.ItemTooltip(tip)
 if S.IsLootInteraction and S.IsLootInteraction(tip.GetOwner and tip:GetOwner()) then return end
 if U.Refreshing or not cfg.enabled or (tip~=GameTooltip and tip~=ItemRefTooltip) then return end
 local owner=tip:GetOwner();if not owner or owner.smyrnaUpgradeRow then return end
 local name=owner.GetName and owner:GetName()
 if name and name:match('^Character.*Slot$') then return end
 local _,link=tip:GetItem();local id=ItemID(link);if not id then return end
 local instant=C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
 local inv;if instant then local _,_,_,value=instant(id);inv=value end
 -- GetItemInfoInstant's equip-location string avoids loading a DB for non-gear.
 if not inv or inv=='' then return end
 if not G.Ensure() then return end
 local row=G.Get(id);local slot=row and invToSlot[row.inv]
 if slot then U.Hover(owner,slot,id,tip) end
end
if TooltipDataProcessor and Enum and Enum.TooltipDataType then
 TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item,function(tip) U.ItemTooltip(tip) end)
else
 for _,tip in ipairs({GameTooltip,ItemRefTooltip}) do if tip and tip.HookScript then tip:HookScript('OnTooltipSetItem',U.ItemTooltip) end end
end

if hooksecurefunc then
 hooksecurefunc('HandleModifiedItemClick',function(link)
  if S.IsLootInteraction and S.IsLootInteraction() then return end
  if not cfg.enabled or not IsControlKeyDown() or (IsShiftKeyDown and IsShiftKeyDown()) then return end
  local id=ItemID(link);if not id or not G.Ensure() then return end
  local row=G.Get(id);local slot=row and invToSlot[row.inv]
  if slot then U.OpenDetails(slot,id,(GameTooltip and GameTooltip:GetOwner()) or UIParent) end
 end)
end
