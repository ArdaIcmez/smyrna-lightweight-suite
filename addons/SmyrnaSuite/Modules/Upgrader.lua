local _,S=...
local name='SmyrnaUpgrader';S.Versions[name]='0.2.0'
if S.Config.features[name]==false then return end
local U={};S.Modules[name]=U
local G=S.Equipment
local defaults={enabled=true,engine='standalone',profile='auto',classic=true,allArmor=false,futureCount=5}
S.Config.upgrader=S.Config.upgrader or {}
local cfg=S.Config.upgrader
cfg.engine='standalone'
if type(cfg.profile)=='string' and cfg.profile:match('^pawn:') then cfg.profile='auto' end
for k,v in pairs(defaults) do if cfg[k]==nil then cfg[k]=v end end
if type(cfg.futureCount)~='number' or cfg.futureCount~=cfg.futureCount or cfg.futureCount%1~=0 or cfg.futureCount<1 or cfg.futureCount>25 then cfg.futureCount=5 end
function U.FutureLimit()
 local n=cfg.futureCount
 if type(n)~='number' or n~=n then return 5 end
 return math.max(1,math.min(25,math.floor(n+.5)))
end
local classNames={[1]='Warrior',[2]='Paladin',[3]='Hunter',[4]='Rogue',[5]='Priest',[7]='Shaman',[8]='Mage',[9]='Warlock',[11]='Druid'}
local specs={[1]={'Arms','Fury','Protection'},[2]={'Holy','Protection','Retribution'},[3]={'Beast Mastery','Marksmanship','Survival'},[4]={'Assassination','Combat','Subtlety'},[5]={'Discipline','Holy','Shadow'},[7]={'Elemental','Enhancement','Restoration'},[8]={'Arcane','Fire','Frost'},[9]={'Affliction','Demonology','Destruction'},[11]={'Balance','Feral damage','Feral tank','Restoration'}}
local slots={Head=1,Neck=2,Shoulder=3,Chest=5,Waist=6,Legs=7,Feet=8,Wrist=9,Hands=10,Finger0=11,Finger1=12,Trinket0=13,Trinket1=14,Back=15,MainHand=16,SecondaryHand=17,Ranged=18}
local results,serial,busy={},0,nil
local hoverOwner,hoverSlot
local slotButtons=setmetatable({},{__mode='k'})
local function Safe(value) return not (issecretvalue and issecretvalue(value)) end
local function Number(value) return Safe(value) and type(value)=='number' and value==value end
local function TipAllowed(tip) return tip and not (tip.IsForbidden and tip:IsForbidden()) end
function U.Invalidate() results={};serial=serial+1;busy=nil;if U.HideSources then U.HideSources() end;if U.RenderStatus then U.RenderStatus('Character data changed. Ctrl + left-click the slot again to refresh.') end end
function U.ActivationDown() return IsControlKeyDown and IsControlKeyDown() end
local function Reveal(frame,slot)
 if not cfg.enabled then return end
 if U.BeginSources then U.BeginSources(frame,slot) end
 local _,reason=U.Hover(frame,slot)
 if reason and U.SourceStatus then U.SourceStatus(reason) end
end
function U.Profile()
 local _,_,class=UnitClass('player');if not Number(class) then return nil,'Your class is not available yet.' end
 local spec=U.PreviewSpec or (type(cfg.profile)=='string' and tonumber(cfg.profile:match('^local:(%d+)$')))
 if not spec then
  local best,points,tied=nil,0,false
  for i=1,3 do
   local p
   if C_SpecializationInfo and C_SpecializationInfo.GetSpecializationInfo then
    local values={pcall(C_SpecializationInfo.GetSpecializationInfo,i)}
    if values[1] then p=values[8] end -- seventh native return: pointsSpent
   elseif GetTalentTabInfo then
    local values={pcall(GetTalentTabInfo,i)}
    if values[1] then p=type(values[2])=='number' and values[6] or values[4] end
   end
   if Number(p) then if p>points then best,points,tied=i,p,false elseif p==points and p>0 then tied=true end end
  end
  if not tied then
   spec=best
   if not spec then
    local api=C_SpecializationInfo and C_SpecializationInfo.GetSpecialization or GetSpecialization
    if api then local ok,p=pcall(api);if ok and Number(p) and p>0 then spec=p end end
   end
   if class==11 and spec==3 then spec=4 end -- third Classic talent tree: Restoration
  end
 end
 local weights=spec and S.PrivatePawn.Scales[class..':'..spec]
 if not weights then return nil,'Choose your profile in Upgrader settings.' end
 return {engine='Standalone Pawn '..S.PrivatePawn.Version,key=class..':'..spec,label=(classNames[class] or 'Class')..' / '..((specs[class] or {})[spec] or tostring(spec)),weights=weights,class=class}
end
function U.SpecChoices()
 local _,_,class=UnitClass('player');return specs[class] or {}
end
function U.SelectPreviewSpec(spec,owner,slot)
 if not U.SpecChoices()[spec] then return end
 U.PreviewSpec=spec;U.Invalidate()
 if U.BeginSources then U.BeginSources(owner,slot) end
 local _,reason=U.Hover(owner,slot)
 if reason and U.SourceStatus then U.SourceStatus(reason) end
end
local function Fingerprint(profile)
 local w=profile.weights or {}
 local keys={};for k in pairs(w) do keys[#keys+1]=k end;table.sort(keys)
 local text={profile.engine,profile.key,G.build or ''}
 for _,k in ipairs(keys) do text[#text+1]=k..'='..tostring(w[k]) end
 return table.concat(text,';')
end
local ratingPer={CritRating=14,HitRating=10,HasteRating=10,DodgeRating=12,ParryRating=15,BlockRating=5}
function U.Score(row,profile)
 -- WoWSims stores combat ratings; Pawn's Forever tooltip scales consume
 -- percentage points. Adjust weights once per profile, not every item table.
 -- Preserve the shared catalog's original units and existing Classic inputs.
 if row.provenance=='WoWSims Forever' then
  if not profile.ratingWeights then
   local weights={};for key,value in pairs(profile.weights) do weights[key]=value/(ratingPer[key] or 1) end
   profile.ratingWeights=weights
  end
  return S.PrivatePawn.Score(row.stats,profile.ratingWeights)
 end
 return S.PrivatePawn.Score(row.stats,profile.weights)
end
function U.Better(a,b)
 if not b then return true end
 local al,bl=a.availableLevel or math.max(a.row.level,a.source.level),b.availableLevel or math.max(b.row.level,b.source.level)
 if al~=bl then return al<bl end
 if a.source.level~=b.source.level then return a.source.level<b.source.level end
 if a.score~=b.score then return a.score>b.score end
 return a.row.id<b.row.id
end
function U.SelectSource(row,level)
 local out={}
 for _,src in ipairs(G.Sources(row)) do
  local allowed=src.level<=level+3 and (cfg.classic or src.reference~='Classic source')
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
local sourceKindLabels={Dungeon='Dungeon',Quest='Quest',Crafted='Profession',World='World drop'}
function U.SourceLabel(c)
 local kind=sourceKindLabels[c.source.kind] or c.source.kind
 if (c.source.kind=='Crafted' or c.source.kind=='World') and c.row.bind=='Binds when equipped' then kind=kind..' (AH)' end
 return kind
end
function U.Insert(top,c,limit)
 limit=limit or 10
 if limit<=0 then return end
 for _,old in ipairs(top) do if old.row.id==c.row.id then return end end
 local at=#top+1
 for i,old in ipairs(top) do if U.Better(c,old) then at=i;break end end
 if at<=limit then table.insert(top,at,c);if #top>limit then table.remove(top) end end
end
local function Append(tip,state)
 if not TipAllowed(tip) then return end
 local c=state.ranked[1]
 if c then
  tip:AddLine((c.future and ('Next upgrade (Lv '..c.availableLevel..'): ') or 'Nearest upgrade: ')..c.row.name..(c.percent and string.format(' (+%.1f%%)',c.percent) or ''),.47,.83,.61,true)
  local src=c.source;tip:AddLine(U.SourceLabel(c)..': '..(src.zone~='' and (src.zone..' / ') or '')..src.name..(src.reference=='Classic source' and ' [Classic]' or ''),.55,.76,.94,true)
 else tip:AddLine('Nearest upgrade: none found in eligible reference data.',.65,.65,.7,true) end
 S.OptionalHint(tip,'Ctrl + left-click to expand upgrades')
 tip:Show()
end
local function Notice(tip,text) if not TipAllowed(tip) then return end;tip:AddLine('Upgrader: '..text,.6,.8,1,true);tip:Show() end
local function Scan(owner,slot,hoveredID,tooltip,silent)
 if S.IsLootInteraction and S.IsLootInteraction(owner) then return nil,'Close the loot window before checking upgrades.' end
 if not cfg.enabled then return nil,'Upgrader is disabled in Suite settings.' end
 local tip=(not silent) and (tooltip or GameTooltip) or nil
 local function Stop(message) if tip then Notice(tip,message) end;return nil,message end
 if not G.Ensure() then return Stop('Smyrna Equipment DB unavailable ('..(G.lastError or 'unknown')..'). Enable it in WoW AddOns and Suite settings outside combat.') end
 local profile,reason=U.Profile();if not profile then return Stop(reason) end
 local rawLink=hoveredID and ('item:'..hoveredID) or GetInventoryItemLink('player',slot)
 local link=(Safe(rawLink) and type(rawLink)=='string') and rawLink or nil
 local id=ItemID(link);local row=id and G.Get(id,true)
 if U.DetailRequest and (slot~=U.DetailRequest.slot or id~=U.DetailRequest.id) then return nil,'Close the current upgrade details before hovering another item.' end
 if not link and tip and TipAllowed(tip) then tip:SetOwner(owner,'ANCHOR_RIGHT');tip:SetText('Empty equipment slot') end
 if id and not row then return Stop('This item is not in the equipment reference DB yet.') end
 local level=UnitLevel('player');if not Number(level) then return Stop('Your level is not available yet.') end
 local currentScore=id and U.Score(row,profile,link) or 0
 if not Number(currentScore) then return Stop('This item cannot be scored with the selected profile.') end
 local context=G.Context(profile.class,level,cfg.allArmor)
 local levelContexts={[level]=context}
 local function ContextAt(n)
  if not levelContexts[n] then levelContexts[n]=G.Context(profile.class,n,cfg.allArmor) end
  return levelContexts[n]
 end
 local futureLimit=U.FutureLimit()
 local signature={Fingerprint(profile),context.key,tostring(slot),tostring(id),tostring(currentScore),tostring(cfg.classic),tostring(futureLimit)}
 for i=1,18 do local l=GetInventoryItemLink('player',i);signature[#signature+1]=(Safe(l) and type(l)=='string') and l or '' end
 local key=table.concat(signature,'|')
 if results[slot] and results[slot].key==key then if tip then Append(tip,results[slot]) end;if U.RenderDetails then U.RenderDetails(results[slot]) end;if not hoveredID and not silent and U.ShowSources then U.ShowSources(owner,slot,results[slot]) end;return end
 if busy==key then if tip then Notice(tip,'Checking upgrades...') end;return end
 serial=serial+1;local token=serial;busy=key
 local ids=G.Candidates(slot,level,profile.class,context);local index=1;local best={};local ranked={};local rankedAH={};local groups={Dungeon={},Quest={},Other={}};local pending=0
 local futurePhase=false
 local future={Dungeon={},Quest={},Other={},AH={}}
 local other=(slot==11 and 12) or (slot==12 and 11) or (slot==13 and 14) or (slot==14 and 13)
 local otherID=other and ItemID(GetInventoryItemLink('player',other))
 if slot==17 and not hoveredID then local main=G.Get(ItemID(GetInventoryItemLink('player',16)),true);if main and main.inv==17 then busy=nil;return Stop('Your two-handed weapon occupies the off-hand slot.') end end
 if tip then Notice(tip,'Checking upgrades...') end
 local function AppendFuture(dest,src,cap)
  if cap<=0 then return end
  local seen={};for _,c in ipairs(dest) do seen[c.row.id]=true end
  local added=0
  for _,c in ipairs(src) do
   if not seen[c.row.id] then
    seen[c.row.id]=true;dest[#dest+1]=c;added=added+1
    if added>=cap then break end
   end
  end
 end
 local function Finish()
  busy=nil
  for _,groupKey in ipairs({'Dungeon','Quest','Other'}) do AppendFuture(groups[groupKey],future[groupKey],futureLimit) end
  AppendFuture(rankedAH,future.AH,futureLimit)
  if futureLimit>0 then
   local futureAll={}
   for _,groupKey in ipairs({'Dungeon','Quest','Other'}) do
    for _,c in ipairs(future[groupKey]) do U.Insert(futureAll,c,futureLimit) end
   end
   AppendFuture(ranked,futureAll,futureLimit)
  end
  results[slot]={key=key,profile=profile,context=context,rows=best,ranked=ranked,rankedAH=rankedAH,groups=groups,pending=pending,slot=slot,baseID=id,baseName=row and row.name or 'Empty slot',futureLimit=futureLimit}
  U.LastResult=results[slot];if U.RenderDetails then U.RenderDetails(results[slot]) end
  if not hoveredID and not silent and U.ShowSources and ((hoverOwner==owner and hoverSlot==slot) or (U.SourceMatches and U.SourceMatches(owner,slot)) or (tip and TipAllowed(tip) and tip:IsShown() and tip:GetOwner()==owner)) then U.ShowSources(owner,slot,results[slot]) end
  if tip and TipAllowed(tip) and tip:IsShown() and tip:GetOwner()==owner then
   if hoveredID then
    Append(tip,results[slot])
   else
    tip:ClearLines();tip:SetOwner(owner,'ANCHOR_RIGHT')
    U.Refreshing=true
    pcall(function()
     if link then tip:SetInventoryItem('player',slot) else tip:SetText('Empty equipment slot') end
    end)
    U.Refreshing=false
    Append(tip,results[slot])
   end
  end
 end
 local Schedule
 local function Batch()
  if token~=serial then return end
  if not hoveredID and CharacterFrame and not CharacterFrame:IsShown() and not (U.Details and U.Details:IsShown()) then busy=nil;return end
  -- Bounded standalone scoring batches, not a whole-catalog hover scan.
  for _=1,32 do
   local candidate=ids[index];index=index+1
   if not candidate then
    if not futurePhase and level<60 and futureLimit>0 then
     futurePhase=true;ids=G.FutureCandidates(slot,level,profile.class,cfg.allArmor);index=1
     C_Timer.After(.01,Schedule);return
    end
    Finish();return
   end
   local r=G.Get(candidate,true)
   if candidate~=id and r and (futurePhase or G.Eligible(r,profile.class,level,slot,row,otherID,context)) and (cfg.classic or not r.estimated) then
     local value,why=U.Score(r,profile)
     if Number(value) and value>currentScore and value>0 then
      local sourceRows=U.SelectSource(r,futurePhase and 60 or level)
      local nearest
      for kind,source in pairs(sourceRows) do
       local group=kind=='Dungeon' and 'Dungeon' or kind=='Quest' and 'Quest' or 'Other'
       local c={row=r,source=source,score=value,percent=currentScore>0 and (value/currentScore-1)*100 or nil}
       if futurePhase then
        local unlock=G.ArmorUnlock(r,profile.class);local needed=math.max(r.level,unlock,source.level-3)
        if needed>level and needed<=60 and G.Eligible(r,profile.class,needed,slot,row,otherID,ContextAt(needed)) then
         c.future=true;c.availableLevel=needed;c.training=unlock>level and (r.subclass..' training at level '..unlock) or nil
         U.Insert(future[group],c,futureLimit)
        end
       else
        if U.Better(c,best[kind]) then best[kind]=c end
        U.Insert(groups[group],c)
        if not nearest or source.level<nearest.source.level then nearest=c end
       end
      end
      if nearest then U.Insert(ranked,nearest) end
      -- Buying a BoE does not require reaching its original mob/quest source.
      if r.bind=='Binds when equipped' then
       local c={row=r,source={kind='AH',name='Tradable item; check listings',zone='',level=r.level,skill=0,reference='BoE reference'},score=value,percent=currentScore>0 and (value/currentScore-1)*100 or nil}
       if futurePhase then
        local unlock=G.ArmorUnlock(r,profile.class);local needed=math.max(r.level,unlock)
        if needed>level and needed<=60 and G.Eligible(r,profile.class,needed,slot,row,otherID,ContextAt(needed)) then c.future=true;c.availableLevel=needed;c.training=unlock>level and (r.subclass..' training at level '..unlock) or nil;U.Insert(future.AH,c,futureLimit) end
       else U.Insert(rankedAH,c) end
      end
     elseif why=='pending' then
      pending=pending+1
      if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(candidate) end
     end
   end
  end
  C_Timer.After(.01,Schedule)
 end
 Schedule=function()
  local ok,err=pcall(Batch)
  if not ok and token==serial then
   busy=nil;serial=serial+1;U.LastError=tostring(err)
   if U.RenderStatus then U.RenderStatus('Upgrade scan stopped: '..U.LastError,slot,id) end
   if U.SourceStatus then U.SourceStatus('Upgrade scan stopped. Click a circle for details.') end
   if tip then Notice(tip,'Upgrade scan stopped. Open ranked upgrades for the error details.') end
  end
 end
 C_Timer.After(0,Schedule)
 return true
end
function U.Hover(owner,slot,id,tooltip,silent)
 local ok,result,reason=pcall(Scan,owner,slot,id,tooltip,silent)
 if not ok then busy=nil;serial=serial+1;U.LastError=tostring(result);reason='Upgrade scan stopped: '..U.LastError;result=nil;if not silent then Notice(tooltip or GameTooltip,reason) end end
 return result,reason
end
local lastOpenSlot,lastOpenID,lastOpenAt
local function OpenForSlot(slot,id,owner)
 if not cfg.enabled or not slot then return false end
 if S.IsLootInteraction and S.IsLootInteraction(owner) then return false end
 local now=GetTime and GetTime() or 0
 if lastOpenSlot==slot and lastOpenID==id and now-(lastOpenAt or 0)<.2 then return true end
 lastOpenSlot,lastOpenID,lastOpenAt=slot,id,now
 if U.OpenDetails then U.OpenDetails(slot,id,owner);return true end
 return false
end
local function HookSlots()
 local allHooked=true
 for label,slot in pairs(slots) do
  local b=_G['Character'..label..'Slot']
  if not b then allHooked=false
  elseif not slotButtons[b] then
   slotButtons[b]=slot
   b:HookScript('OnEnter',function(self)
    if U.SourcesOwnMouse and U.SourcesOwnMouse() then return end
    hoverOwner,hoverSlot=self,slot;if U.ActivationDown() then Reveal(self,slot) end
   end)
   b:HookScript('OnLeave',function(self) if hoverOwner==self then hoverOwner,hoverSlot=nil,nil end;if U.HideSourcesSoon then U.HideSourcesSoon() end end)
   b:HookScript('OnClick',function(self,button)
    if Safe(button) and button=='LeftButton' and IsControlKeyDown and IsControlKeyDown() and not (IsShiftKeyDown and IsShiftKeyDown()) and not (IsAltKeyDown and IsAltKeyDown()) then
     OpenForSlot(slot,nil,self)
    end
   end)
  end
 end
 return allHooked
end
local panel
function U.Open()
 if not panel then
  panel=CreateFrame('Frame','SmyrnaUpgraderOptions',UIParent,'BackdropTemplate');panel:SetSize(700,540);S.StylePanel(panel)
  panel.SuiteCloseButton=S.CloseButton(panel)
  local title=panel:CreateFontString(nil,'OVERLAY','GameFontNormalLarge');title:SetPoint('TOPLEFT',20,-16);title:SetText('Upgrader');title:SetTextColor(1,.86,.48)
  local help=panel:CreateFontString(nil,'OVERLAY','GameFontHighlight');help:SetPoint('TOPLEFT',20,-44);help:SetWidth(655);help:SetJustifyH('LEFT')
  help:SetText('Hold Ctrl while hovering equipped gear (press C) to see Dungeon, Quest, and Auction House circles. Ctrl + left-click any gear to open the full ranked upgrade list.\n\nChoose a stat profile below, or leave it on Automatic to match your talents. One-hand weapons compare with one-handers, and two-handers with two-handers.')

  -- Clear breakdown of exactly which Armor & Weapon types are included
  local gearCard=CreateFrame('Frame',nil,panel,'BackdropTemplate');gearCard:SetSize(656,88);gearCard:SetPoint('TOPLEFT',20,-138);S.StyleCard(gearCard,.074,.086,.116)
  S.OptionSection(gearCard,'Included Gear For Your Character',12,-10,632)
  local armorGuide=gearCard:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');armorGuide:SetPoint('TOPLEFT',12,-30);armorGuide:SetWidth(632);armorGuide:SetJustifyH('LEFT');armorGuide:SetTextColor(1,.86,.48)
  local weaponGuide=gearCard:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');weaponGuide:SetPoint('TOPLEFT',12,-48);weaponGuide:SetWidth(632);weaponGuide:SetJustifyH('LEFT');weaponGuide:SetTextColor(.78,.86,.95);weaponGuide:SetMaxLines(2)

  local function UpdateGearGuide()
   local _,_,class=UnitClass('player');local level=UnitLevel('player')
   local aLine,wLine=G.GearGuide(class,Number(level) and level or 1,cfg.allArmor)
   armorGuide:SetText(aLine);weaponGuide:SetText(wLine)
  end

  S.OptionSection(panel,'Options',20,-240,655)
  local enabled=CreateFrame('CheckButton',nil,panel,'UICheckButtonTemplate');enabled:SetPoint('TOPLEFT',18,-260);enabled:SetChecked(cfg.enabled)
  local label=enabled:CreateFontString(nil,'OVERLAY','GameFontHighlight');label:SetPoint('LEFT',enabled,'RIGHT',2,0);label:SetText('Ctrl upgrades')
  enabled:SetScript('OnClick',function(self) cfg.enabled=not not self:GetChecked();U.Invalidate() end)
  S.AttachTooltip(enabled,'Ctrl upgrades','Hold Ctrl while hovering equipped gear to see source circles, or Ctrl + left-click to open ranked upgrades.',label)

  local classic=CreateFrame('CheckButton',nil,panel,'UICheckButtonTemplate');classic:SetPoint('TOPLEFT',220,-260);classic:SetChecked(cfg.classic)
  local ct=classic:CreateFontString(nil,'OVERLAY','GameFontHighlight');ct:SetPoint('LEFT',classic,'RIGHT',2,0);ct:SetText('Classic fallback')
  classic:SetScript('OnClick',function(self) cfg.classic=not not self:GetChecked();U.Invalidate() end)
  S.AttachTooltip(classic,'Classic fallback','Include Classic WoW items and drop sources marked [Classic] when Forever-specific data is missing.',ct)

  local armor=CreateFrame('CheckButton',nil,panel,'UICheckButtonTemplate');armor:SetPoint('TOPLEFT',430,-260);armor:SetChecked(cfg.allArmor)
  local at=armor:CreateFontString(nil,'OVERLAY','GameFontHighlight');at:SetPoint('LEFT',armor,'RIGHT',2,0);at:SetText('Lighter armor')
  armor:SetScript('OnClick',function(self) cfg.allArmor=not not self:GetChecked();U.Invalidate();UpdateGearGuide() end)
  S.AttachTooltip(armor,'Lighter armor','Also include lighter armor types you can equip (e.g. Leather on Mail/Plate characters).',at)

  local futureLabel=panel:CreateFontString(nil,'OVERLAY','GameFontHighlight');futureLabel:SetPoint('TOPLEFT',20,-358)
  local futureMinus=CreateFrame('Button',nil,panel,'UIPanelButtonTemplate');futureMinus:SetSize(24,22);futureMinus:SetPoint('TOPLEFT',255,-354);futureMinus:SetText('-');S.StyleButton(futureMinus)
  local futureSlider=S.CreateSlider(panel,210,1,25);futureSlider:SetPoint('TOPLEFT',285,-356)
  local futurePlus=CreateFrame('Button',nil,panel,'UIPanelButtonTemplate');futurePlus:SetSize(24,22);futurePlus:SetPoint('TOPLEFT',501,-354);futurePlus:SetText('+');S.StyleButton(futurePlus)
  local futureHint=panel:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');futureHint:SetPoint('TOPLEFT',535,-359);futureHint:SetTextColor(.7,.75,.82);futureHint:SetText('per category')
  local function UpdateFutureLabel(n)
   futureLabel:SetText('Future upgrades to preview: |cff78d49b'..n..'|r')
  end
  local function SetFutureCount(n)
   n=math.max(1,math.min(25,math.floor(n+.5)))
   if cfg.futureCount~=n then cfg.futureCount=n;U.Invalidate() end
   if futureSlider:GetValue()~=n then futureSlider:SetValue(n) end
   UpdateFutureLabel(n)
  end
  futureSlider:SetScript('OnValueChanged',function(_,value) SetFutureCount(value or 1) end)
  futureMinus:SetScript('OnClick',function() SetFutureCount(U.FutureLimit()-1) end)
  futurePlus:SetScript('OnClick',function() SetFutureCount(U.FutureLimit()+1) end)

  S.OptionSection(panel,'Stat Profile',20,-394,655)
  local button=CreateFrame('Button',nil,panel,'UIPanelButtonTemplate');button:SetPoint('TOPLEFT',20,-414);button:SetSize(656,28);S.StyleButton(button)
  local function Choices()
   local _,_,class=UnitClass('player');local options={{key='auto',label='Automatic (matches your talents)'}}
   for i,label in ipairs(specs[class] or {}) do options[#options+1]={key='local:'..i,label=label} end
   return options
  end
  local function Refresh()
   local p,err=U.Profile();button:SetText('Stat profile: '..(p and p.label or err or 'Choose a profile')..'  (click to switch)')
   local n=U.FutureLimit();if futureSlider:GetValue()~=n then futureSlider:SetValue(n) end;UpdateFutureLabel(n)
   UpdateGearGuide()
  end
  button:SetScript('OnClick',function()
   local choices=Choices();local index=1;for i,p in ipairs(choices) do if p.key==cfg.profile then index=i;break end end
   cfg.profile=choices[index%#choices+1].key;U.PreviewSpec=nil;U.Invalidate();Refresh()
  end)
  panel:SetScript('OnShow',Refresh)
  local status=panel:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');status:SetPoint('TOPLEFT',20,-456);status:SetWidth(656);status:SetJustifyH('LEFT');status:SetTextColor(.70,.74,.82)
  status:SetText('Future upgrades show the level or armor training needed. Percentages compare item stats only - special effects and procs are not scored.\nGear stat data supplement: https://wowsims.com/forever/ (MIT).')
  Refresh()
 end
 panel:Show();return panel
end
local driver=CreateFrame('Frame')
local UPGRADER_EVENTS={'MODIFIER_STATE_CHANGED','PLAYER_EQUIPMENT_CHANGED','PLAYER_LEVEL_UP','CHARACTER_POINTS_CHANGED','PLAYER_TALENT_UPDATE','SKILL_LINES_CHANGED','SPELLS_CHANGED'}
local function SyncUpgraderEvents(on)
 for _,ev in ipairs(UPGRADER_EVENTS) do
  if on then pcall(driver.RegisterEvent,driver,ev) else pcall(driver.UnregisterEvent,driver,ev) end
 end
end
driver:RegisterEvent('PLAYER_LOGIN');driver:RegisterEvent('ADDON_LOADED')
SyncUpgraderEvents(cfg.enabled~=false)
driver:SetScript('OnEvent',function(self,event,key,state)
 if event=='PLAYER_LOGIN' or event=='ADDON_LOADED' then
  if event=='PLAYER_LOGIN' then self:UnregisterEvent('PLAYER_LOGIN') end
  if HookSlots() then self:UnregisterEvent('ADDON_LOADED') end
 elseif not cfg.enabled then return
 elseif event=='MODIFIER_STATE_CHANGED' then
  if (not key or (Safe(key) and Safe(state) and (key=='LCTRL' or key=='RCTRL') and (state==1 or state==true))) and hoverOwner and U.ActivationDown() then Reveal(hoverOwner,hoverSlot) end
 else U.Invalidate() end
end)
U.Driver=driver
SLASH_SMYRNAUPGRADER1='/su';SlashCmdList.SMYRNAUPGRADER=function() U.Open() end

S.Loaded[name]=true

local invToSlot={[1]=1,[2]=2,[3]=3,[5]=5,[6]=6,[7]=7,[8]=8,[9]=9,[10]=10,[11]=11,[12]=13,[13]=16,[14]=17,[15]=18,[16]=15,[17]=16,[20]=5,[21]=16,[22]=17,[23]=17,[25]=18,[26]=18,[28]=18}
local equipLocToSlot={
 INVTYPE_HEAD=1,INVTYPE_NECK=2,INVTYPE_SHOULDER=3,INVTYPE_CHEST=5,INVTYPE_ROBE=5,
 INVTYPE_WAIST=6,INVTYPE_LEGS=7,INVTYPE_FEET=8,INVTYPE_WRIST=9,INVTYPE_HAND=10,
 INVTYPE_FINGER=11,INVTYPE_TRINKET=13,INVTYPE_CLOAK=15,
 INVTYPE_WEAPON=16,INVTYPE_2HWEAPON=16,INVTYPE_WEAPONMAINHAND=16,
 INVTYPE_WEAPONOFFHAND=17,INVTYPE_SHIELD=17,INVTYPE_HOLDABLE=17,
 INVTYPE_RANGED=18,INVTYPE_RANGEDRIGHT=18,INVTYPE_THROWN=18,INVTYPE_RELIC=18,
}
local function SlotForItem(id)
 if not Number(id) then return nil end
 local instant=C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
 local inv
 if instant then local _,_,_,value=instant(id);if Safe(value) then inv=value end end
 local slot=inv and equipLocToSlot[inv]
 if slot then return slot end
 if G.records then local row=G.Get(id,true);return row and invToSlot[row.inv] end
end
U.SlotForItem=SlotForItem
local function TooltipItemID(tip,data)
 local id=data and data.id
 if Number(id) then return id end
 if TooltipUtil and TooltipUtil.GetDisplayedItem then
  local _,link,displayed=TooltipUtil.GetDisplayedItem(tip)
  return (Number(displayed) and displayed) or ItemID(link)
 elseif tip.GetItem then
  local _,link=tip:GetItem();return ItemID(link)
 end
end
function U.ItemTooltip(tip,data)
 if not TipAllowed(tip) then return end
 if S.IsLootInteraction and S.IsLootInteraction(tip.GetOwner and tip:GetOwner()) then return end
 if U.Refreshing or not cfg.enabled or not U.ActivationDown() or (tip~=GameTooltip and tip~=ItemRefTooltip) then return end
 local owner=tip:GetOwner();if not owner or owner.smyrnaUpgradeRow then return end
 local name=owner.GetName and owner:GetName()
 if slotButtons[owner] or (Safe(name) and type(name)=='string' and name:match('^Character.*Slot$')) then return end
 local id=TooltipItemID(tip,data);if not id then return end
 local slot=SlotForItem(id);if not slot then return end
 if not G.Ensure() then return end
 U.Hover(owner,slot,id,tip)
end
if TooltipDataProcessor and Enum and Enum.TooltipDataType then
 TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item,function(tip,data) U.ItemTooltip(tip,data) end)
else
 for _,tip in ipairs({GameTooltip,ItemRefTooltip}) do if tip and tip.HookScript then tip:HookScript('OnTooltipSetItem',U.ItemTooltip) end end
end

local function CtrlOnly()
 return IsControlKeyDown and IsControlKeyDown() and not (IsShiftKeyDown and IsShiftKeyDown()) and not (IsAltKeyDown and IsAltKeyDown())
end
local function HandleGearLink(link,owner)
 if not cfg.enabled or not CtrlOnly() then return false end
 if S.IsLootInteraction and S.IsLootInteraction(owner) then return false end
 if owner and owner.smyrnaUpgradeRow then return false end
 if owner and slotButtons[owner] then return OpenForSlot(slotButtons[owner],nil,owner) end
 local id=ItemID(link);if not id then return false end
 local slot=SlotForItem(id);if not slot then return false end
 return OpenForSlot(slot,id,owner or UIParent)
end

-- Catch Ctrl + left-click on any hovered gear (Character slots, Blizzard bags,
-- Bagnon bags, bank, merchant, quest rewards, Bestiary loot) even if the widget
-- bypasses HandleModifiedItemClick.
local clickDriver=CreateFrame('Frame')
pcall(clickDriver.RegisterEvent,clickDriver,'GLOBAL_MOUSE_DOWN')
clickDriver:SetScript('OnEvent',function(_,_,button)
 if not cfg.enabled or not Safe(button) or button~='LeftButton' or not CtrlOnly() then return end
 if S.IsLootInteraction and S.IsLootInteraction() then return end
 if U.SourcesOwnMouse and U.SourcesOwnMouse() then return end
 if not TipAllowed(GameTooltip) or not GameTooltip:IsShown() then return end
 local owner=GameTooltip:GetOwner()
 if not owner or owner.smyrnaUpgradeRow then return end
 if slotButtons[owner] then
  OpenForSlot(slotButtons[owner],nil,owner);return
 end
 local id=TooltipItemID(GameTooltip)
 local slot=id and SlotForItem(id)
 if slot then OpenForSlot(slot,id,owner) end
end)

if hooksecurefunc then
 hooksecurefunc('HandleModifiedItemClick',function(link)
  if not cfg.enabled then return end
  local id=Safe(link) and type(link)=='string' and tonumber(link:match('item:(%d+)'))
  local WS=S.Modules and S.Modules.SmyrnaWorkshop
  if id and WS and WS.Uses then
   local u=WS.Uses(id)
   if type(u)=='table' and #u>0 then return end
  end
  local owner=TipAllowed(GameTooltip) and GameTooltip:GetOwner() or nil
  HandleGearLink(link,owner)
 end)
 if SetItemRef then
  hooksecurefunc('SetItemRef',function(link,_,button)
   if not cfg.enabled then return end
   if Safe(button) and button=='LeftButton' and Safe(link) and type(link)=='string' and link:match('^item:') then
    HandleGearLink(link,UIParent)
   end
  end)
 end
 if PaperDollItemSlotButton_OnModifiedClick then
  hooksecurefunc('PaperDollItemSlotButton_OnModifiedClick',function(self,button)
   if not cfg.enabled then return end
   local sl=self and slotButtons[self]
   if Safe(button) and button=='LeftButton' and sl and CtrlOnly() then OpenForSlot(sl,nil,self) end
  end)
 end
end

function U.SetEnabled(on)
 local en=on and true or false
 cfg.enabled=en
 SyncUpgraderEvents(en)
 if en then
  pcall(clickDriver.RegisterEvent,clickDriver,'GLOBAL_MOUSE_DOWN')
 else
  pcall(clickDriver.UnregisterEvent,clickDriver,'GLOBAL_MOUSE_DOWN')
  hoverOwner,hoverSlot=nil,nil
  if panel and panel.Hide then panel:Hide() end
  if U.HideSources then U.HideSources() end
 end
end

-- ============================================================
-- Pawn-style Hover Upgrade % Tooltip (works on all gear including random-enchant greens)
-- ============================================================
local STAT_MAP={
 ITEM_MOD_STRENGTH_SHORT='Strength',
 ITEM_MOD_AGILITY_SHORT='Agility',
 ITEM_MOD_STAMINA_SHORT='Stamina',
 ITEM_MOD_INTELLECT_SHORT='Intellect',
 ITEM_MOD_SPIRIT_SHORT='Spirit',
 ITEM_MOD_ATTACK_POWER_SHORT='Ap',
 ITEM_MOD_RANGED_ATTACK_POWER_SHORT='Rap',
 ITEM_MOD_SPELL_POWER_SHORT='SpellPower',
 ITEM_MOD_SPELL_DAMAGE_DONE_SHORT='SpellPower',
 ITEM_MOD_SPELL_HEALING_DONE_SHORT='Healing',
 ITEM_MOD_CRIT_RATING_SHORT='CritRating',
 ITEM_MOD_HIT_RATING_SHORT='HitRating',
 ITEM_MOD_HASTE_RATING_SHORT='HasteRating',
 ITEM_MOD_DEFENSE_SKILL_RATING_SHORT='DefenseRating',
 ITEM_MOD_DODGE_RATING_SHORT='DodgeRating',
 ITEM_MOD_PARRY_RATING_SHORT='ParryRating',
 ITEM_MOD_BLOCK_RATING_SHORT='BlockRating',
 ITEM_MOD_BLOCK_VALUE_SHORT='BlockValue',
 ITEM_MOD_POWER_REGEN0_SHORT='Mp5',
 ITEM_MOD_DAMAGE_PER_SECOND_SHORT='Dps',
 RESISTANCE0_NAME='Armor',
}
local EQUIP_SLOTS={
 INVTYPE_HEAD={1},INVTYPE_NECK={2},INVTYPE_SHOULDER={3},INVTYPE_CHEST={5},INVTYPE_ROBE={5},
 INVTYPE_WAIST={6},INVTYPE_LEGS={7},INVTYPE_FEET={8},INVTYPE_WRIST={9},INVTYPE_HAND={10},
 INVTYPE_FINGER={11,12},INVTYPE_TRINKET={13,14},INVTYPE_CLOAK={15},
 INVTYPE_WEAPON={16,17},INVTYPE_2HWEAPON={16},INVTYPE_WEAPONMAINHAND={16},
 INVTYPE_WEAPONOFFHAND={17},INVTYPE_SHIELD={17},INVTYPE_HOLDABLE={17},
 INVTYPE_RANGED={18},INVTYPE_RANGEDRIGHT={18},INVTYPE_THROWN={18},INVTYPE_RELIC={18},
}

local function ScoreItemLink(link,id,profile)
 if id and G and G.records then
  local row=G.Get(id,true)
  if row and row.stats then
   local sc=U.Score(row,profile)
   if Number(sc) and sc>0 then return sc end
  end
 end
 if not link or not S.PrivatePawn or not S.PrivatePawn.Score then return nil end
 local getStats=(C_Item and C_Item.GetItemStats) or GetItemStats
 if not getStats then return nil end
 local ok,raw=pcall(getStats,link)
 if not ok or type(raw)~='table' then return nil end
 local mapped={}
 local any=false
 for k,v in pairs(raw) do
  local mk=STAT_MAP[k]
  if mk and Number(v) and v~=0 then mapped[mk]=(mapped[mk] or 0)+v; any=true end
 end
 if not any then return nil end
 local sc=S.PrivatePawn.Score(mapped,profile.weights)
 return (Number(sc) and sc>0) and sc or nil
end

local function OnUpgradeTooltip(tip,data)
 if not cfg.enabled or U.Refreshing or not TipAllowed(tip) then return end
 if S.IsLootInteraction and tip.GetOwner and S.IsLootInteraction(tip:GetOwner()) then return end
 local link,id
 if tip.GetItem then
  local _,l=tip:GetItem()
  if Safe(l) and type(l)=='string' then link=l; id=ItemID(l) end
 end
 if not id and data and Safe(data.id) and type(data.id)=='number' then id=data.id end
 if not id then return end
 local getInfo=(C_Item and C_Item.GetItemInfo) or GetItemInfo
 local _,_,_,_,_,_,_,_,equipLoc=getInfo and getInfo(link or id)
 if not Safe(equipLoc) or type(equipLoc)~='string' or equipLoc=='' then return end
 local slots=EQUIP_SLOTS[equipLoc]
 if not slots then return end
 for _,sl in ipairs(slots) do
  local eid=GetInventoryItemID and GetInventoryItemID('player',sl)
  if Safe(eid) and eid==id then
   local elink=GetInventoryItemLink and GetInventoryItemLink('player',sl)
   if not link or (Safe(elink) and elink==link) then return end
  end
 end
 local profile=U.Profile and U.Profile()
 if not profile then return end
 local newScore=ScoreItemLink(link,id,profile)
 if not newScore or newScore<=0 then return end
 local bestCur=math.huge
 for _,sl in ipairs(slots) do
  local elink=GetInventoryItemLink and GetInventoryItemLink('player',sl)
  local eid=GetInventoryItemID and GetInventoryItemID('player',sl)
  local cur=0
  if Safe(eid) and type(eid)=='number' then
   cur=ScoreItemLink(Safe(elink) and elink or nil,eid,profile) or 0
  end
  if cur<bestCur then bestCur=cur end
 end
 if bestCur==math.huge then bestCur=0 end
 local specLabel=profile.label or 'Spec'
 if bestCur<=0 then
  tip:AddDoubleLine('|cffdfb66bSmyrna Upgrader:|r |cff4cff7a+Upgrade|r','|cff9aa4b2'..specLabel..'|r',1,1,1,1,1,1)
 else
  local pct=math.floor(((newScore-bestCur)/bestCur)*100+.5)
  if pct>=1 then
   tip:AddDoubleLine('|cffdfb66bSmyrna Upgrader:|r |cff4cff7a+'..pct..'% upgrade|r','|cff9aa4b2'..specLabel..'|r',1,1,1,1,1,1)
  elseif pct<=-1 then
   tip:AddDoubleLine('|cffdfb66bSmyrna Upgrader:|r |cffff7a66'..pct..'%|r','|cff9aa4b2'..specLabel..'|r',1,1,1,1,1,1)
  else
   tip:AddDoubleLine('|cffdfb66bSmyrna Upgrader:|r |cff8ecfff~0%|r','|cff9aa4b2'..specLabel..'|r',1,1,1,1,1,1)
  end
 end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
 TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item,OnUpgradeTooltip)
elseif GameTooltip and GameTooltip:HasScript('OnTooltipSetItem') then
 GameTooltip:HookScript('OnTooltipSetItem',function(tip) OnUpgradeTooltip(tip,nil) end)
end
