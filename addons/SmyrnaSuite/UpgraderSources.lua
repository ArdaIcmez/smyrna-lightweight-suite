local _,S=...
local U=S.Modules.SmyrnaUpgrader;if not U then return end
local dock,menu,owner,slot,revision= nil,nil,nil,nil,0
local ticker,lastInside
local media='Interface\\AddOns\\SmyrnaSuite\\Media\\'
local kinds={{'Dungeon','Dungeon','Interface\\Icons\\INV_Misc_Key_03'},{'Quest','Quest','Interface\\GossipFrame\\AvailableQuestIcon'},{'AH','AH','Interface\\Icons\\INV_Misc_Coin_01'}}
local function Now() return GetTime and GetTime() or time() end
local function Over(frame) return frame and frame:IsShown() and MouseIsOver and MouseIsOver(frame) end
function U.SourcesOwnMouse() return dock and dock:IsShown() and (Over(dock) or Over(menu)) end
function U.SourceMatches(frame,equipmentSlot) return dock and dock:IsShown() and owner==frame and slot==equipmentSlot end
local function Inside() return U.SourcesOwnMouse() or Over(owner) end
local function Stay() revision=revision+1;lastInside=Now() end
local function Leave()
 if ticker then return end
 local token=revision
 C_Timer.After(.65,function()
  if token==revision and dock and dock:IsShown() and not Inside() then dock:Hide() end
 end)
end
local function Track()
 if ticker or not MouseIsOver or not C_Timer.NewTicker then return end
 -- Ten cheap geometry checks/second only while this popup is visible. This
 -- covers scrollbar descendants and the travel gap, which have their own mouse focus.
 ticker=C_Timer.NewTicker(.1,function()
  if not dock or not dock:IsShown() then if ticker then ticker:Cancel();ticker=nil end;return end
  if Inside() then lastInside=Now()
  elseif Now()-(lastInside or 0)>=.65 then dock:Hide() end
 end)
end
local function EnsureMenuRow(i)
 if menu.rows[i] then return menu.rows[i] end
 local b=CreateFrame('Button',nil,menu.canvas,'UIPanelButtonTemplate');b:SetSize(294,35);b:SetPoint('TOPLEFT',0,-(i-1)*38);S.StyleButton(b);b.smyrnaUpgradeRow=true
 b.icon=b:CreateTexture(nil,'ARTWORK');b.icon:SetSize(26,26);b.icon:SetPoint('LEFT',4,0)
 local font=b.GetFontString and b:GetFontString();if font then font:ClearAllPoints();font:SetPoint('TOPLEFT',35,-3);font:SetWidth(252);font:SetJustifyH('LEFT');font:SetMaxLines(1) end
 b.meta=b:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');b.meta:SetPoint('TOPLEFT',35,-20);b.meta:SetWidth(252);b.meta:SetJustifyH('LEFT');b.meta:SetTextColor(.65,.67,.72)
 b:RegisterForClicks('LeftButtonUp','RightButtonUp')
 b:SetScript('OnClick',function(self,mouseBtn)
  if mouseBtn=='RightButton' and self.candidate then
   local J=S.Modules and S.Modules.SmyrnaJournal
   if J and J.OpenForItem and J.HasItemOrZone and J.HasItemOrZone(self.candidate.row.id,self.candidate.source and self.candidate.source.zone) then
    dock:Hide()
    J.OpenForItem(self.candidate.row.id,self.candidate.source and self.candidate.source.zone)
    return
   end
  end
  U.OpenDetails(slot,nil,owner,menu.filter);dock:Hide()
 end)
 b:SetScript('OnEnter',function(self)
  Stay()
  if self.candidate and GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then
   GameTooltip:SetOwner(self,'ANCHOR_RIGHT')
   GameTooltip:SetHyperlink('item:'..self.candidate.row.id)
   local J=S.Modules and S.Modules.SmyrnaJournal
   if J and J.HasItemOrZone and J.HasItemOrZone(self.candidate.row.id,self.candidate.source and self.candidate.source.zone) then
    GameTooltip:AddLine('Right-click: Open in Smyrna Dungeon Journal',.55,.86,1)
   end
   GameTooltip:Show()
  end
 end)
 b:SetScript('OnLeave',function() if GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then GameTooltip:Hide() end;Leave() end);menu.rows[i]=b
 return b
end
local function Populate(reset)
 local state=dock.state;local filter=menu.filter
 local rows=state and (filter=='AH' and state.rankedAH or state.groups[filter]) or {}
 local count=math.min(#rows,35)
 local total=math.max(1,count,#menu.rows)
 for i=1,total do
  local c=i<=count and rows[i] or nil
  local b=(c or i==1) and EnsureMenuRow(i) or menu.rows[i]
  if b then
   b.candidate=c
   local label=c and (i..'. '..c.row.name) or (dock.status or 'No eligible upgrade found')
   b:SetText(label)
   b.meta:SetText(c and ((c.future and ('Next: Lv '..c.availableLevel..(c.training and ' / armor training' or '')) or ('Lv '..c.row.level))..' - '..c.row.subclass) or '')
   local icon=c and C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(c.row.id)
   b.icon:SetTexture(icon or 'Interface\\Icons\\INV_Misc_QuestionMark')
   local color=c and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[c.row.quality]
   local font=b.GetFontString and b:GetFontString();if font then font:SetTextColor(color and color.r or 1,color and color.g or .83,color and color.b or .43) end
   b:SetEnabled(c~=nil);b:SetShown(c~=nil or i==1)
  end
 end
 menu.canvas:SetHeight(math.max(38,count*38));menu.scroll:UpdateScrollChildRect()
 menu.scroll:SetVerticalScroll(reset and 0 or math.min(menu.scroll:GetVerticalScroll(),menu.scroll:GetVerticalScrollRange()))
end
local function Ensure()
 if dock then return end
 dock=CreateFrame('Frame','SmyrnaUpgradeSources',UIParent,'BackdropTemplate');dock:SetSize(278,96);dock:SetFrameStrata('TOOLTIP');dock:SetFrameLevel(210);dock:SetClampedToScreen(true);dock:EnableMouse(true)
 S.StylePanel(dock,true)
 dock.specTabs={}
 local choices=U.SpecChoices();local width=264/math.max(1,#choices)
 for i,label in ipairs(choices) do
  local spec=i
  local b=CreateFrame('Button',nil,dock,'UIPanelButtonTemplate');b:SetSize(width-3,23);b:SetPoint('TOPLEFT',7+(i-1)*width,-6);b:SetText(label);S.StyleButton(b)
  b:SetScript('OnClick',function() Stay();U.SelectPreviewSpec(spec,owner,slot) end)
  b:SetScript('OnEnter',Stay);b:HookScript('OnLeave',Leave)
  dock.specTabs[i]=b
 end
 menu=CreateFrame('Frame',nil,dock,'BackdropTemplate');menu:SetSize(334,252);menu:SetPoint('TOPLEFT',dock,'BOTTOMLEFT',0,0);menu:SetClampedToScreen(true);menu:EnableMouse(true);S.StylePanel(menu);menu:Hide()
 menu.title=menu:CreateFontString(nil,'OVERLAY','GameFontNormal');menu.title:SetPoint('TOPLEFT',8,-9)
 local scroll=CreateFrame('ScrollFrame',nil,menu,'UIPanelScrollFrameTemplate');scroll:SetPoint('TOPLEFT',8,-32);scroll:SetSize(298,210);scroll:EnableMouse(true)
 local canvas=CreateFrame('Frame',nil,scroll);canvas:SetSize(294,280);canvas:EnableMouse(true);scroll:SetScrollChild(canvas);menu.scroll,menu.canvas=scroll,canvas
 scroll:EnableMouseWheel(true);scroll:SetScript('OnMouseWheel',function(_,delta) Stay();scroll:SetVerticalScroll(math.max(0,math.min(scroll:GetVerticalScrollRange(),scroll:GetVerticalScroll()-delta*38))) end)
 menu.rows={};dock.buttons={}
 for i=1,10 do EnsureMenuRow(i) end
 for i,entry in ipairs(kinds) do
  local key,title,icon=unpack(entry)
  local b=CreateFrame('Button',nil,dock);b:SetSize(44,44);b:SetPoint('TOPLEFT',69+(i-1)*48,-35);dock.buttons[i]=b
  local bg=b:CreateTexture(nil,'BACKGROUND');bg:SetAllPoints();bg:SetTexture(media..'UpgradeCircle')
  local t=b:CreateTexture(nil,'ARTWORK');t:SetSize(32,32);t:SetPoint('CENTER');t:SetTexture(icon)
  if b.CreateMaskTexture and t.AddMaskTexture then local mask=b:CreateMaskTexture();mask:SetAllPoints(t);mask:SetTexture(media..'UpgradeMask');t:AddMaskTexture(mask) end
  local caption=b:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');caption:SetPoint('TOP',b,'BOTTOM',0,-2);caption:SetText(title)
  b:SetScript('OnClick',function() U.OpenDetails(slot,nil,owner,key);dock:Hide() end)
  b:SetScript('OnEnter',function()
   Stay();local changed=menu.filter~=key;menu.filter=key;menu.title:SetText(title=='AH' and 'Auction House' or title);Populate(changed);menu:Show()
  end)
  b:SetScript('OnLeave',Leave)
 end
 for _,f in ipairs({dock,menu,scroll,canvas}) do f:SetScript('OnEnter',Stay);f:SetScript('OnLeave',Leave) end
 dock:SetScript('OnHide',function()
  revision=revision+1;if ticker then ticker:Cancel();ticker=nil end
  menu:Hide();dock.state=nil;dock.status=nil
  if GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) and GameTooltip:IsShown() then
   local own=GameTooltip:GetOwner()
   if own==dock or own==menu or (own and own.smyrnaUpgradeRow) then GameTooltip:Hide() end
  end
 end)
 U.SourceDock,U.SourceMenu=dock,menu
 if CharacterFrame and CharacterFrame.HookScript then CharacterFrame:HookScript('OnHide',function() dock:Hide() end) end
end
local function UpdateSpecs(profile)
 profile=profile or U.Profile()
 for i,b in ipairs(dock.specTabs) do S.SetButtonSelected(b,profile and profile.key:match(':(%d+)$')==tostring(i)) end
end
local function Position(frame)
 dock:ClearAllPoints()
 if frame.GetEffectiveScale and UIParent.GetEffectiveScale then
  local fs,us=frame:GetEffectiveScale(),UIParent:GetEffectiveScale()
  if type(fs)=='number' and type(us)=='number' and us>0 and fs>0 then dock:SetScale(fs/us) end
 end
 local x=frame.GetCenter and frame:GetCenter();local center=CharacterFrame and CharacterFrame.GetCenter and CharacterFrame:GetCenter()
 local name=frame.GetName and frame:GetName()
 local right=x and center and x>center
 if not x or not center then right=name and (name:find('Finger') or name:find('Trinket') or name:find('Waist') or name:find('Legs') or name:find('Feet') or name:find('Hands')) end
 -- Place into the model side of the column, not on the next equipment button.
 dock:SetPoint(right and 'TOPRIGHT' or 'TOPLEFT',frame,right and 'BOTTOMLEFT' or 'BOTTOMRIGHT',right and -4 or 4,0)
end
function U.BeginSources(frame,equipmentSlot)
 if (U.Details and U.Details:IsShown()) or (S.IsLootInteraction and S.IsLootInteraction(frame)) then return end
 Ensure()
 if owner~=frame then menu:Hide();dock.state=nil end
 owner,slot=frame,equipmentSlot;dock.status='Checking upgrades...';UpdateSpecs();Position(frame);Stay();dock:Show();Track()
end
function U.SourceStatus(message)
 if dock and dock:IsShown() then dock.status=message;if menu:IsShown() then Populate(false) end end
end
function U.ShowSources(frame,equipmentSlot,state)
 if not state or (S.IsLootInteraction and S.IsLootInteraction(frame)) or (U.Details and U.Details:IsShown()) then return end
 Ensure()
 if owner~=frame then menu:Hide() end
 owner,slot=frame,equipmentSlot;dock.state=state;dock.status=nil;UpdateSpecs(state.profile);Position(frame);Stay();dock:Show();Track()
 if menu:IsShown() then Populate(false) end
end
function U.HideSourcesSoon() if dock then Leave() end end
function U.HideSources() if dock then dock:Hide() end end
local driver=CreateFrame('Frame');driver:RegisterEvent('LOOT_OPENED');driver:RegisterEvent('PLAYER_EQUIPMENT_CHANGED')
driver:SetScript('OnEvent',function() U.HideSources() end)
