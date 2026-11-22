local _,S=...
local U=S.Modules.SmyrnaUpgrader;if not U then return end
-- One reusable source dock, three buttons and one pooled dropdown. No polling.
local dock,menu,owner,slot,revision
local kinds={{'Dungeon','Dungeon','Interface\\Icons\\INV_Misc_Key_03'},{'Quest','Quest','Interface\\GossipFrame\\AvailableQuestIcon'},{'AH','Auction House','Interface\\Icons\\INV_Misc_Coin_01'}}
local function Leave()
 local token=revision
 C_Timer.After(.2,function()
  if token~=revision then return end
  if MouseIsOver and (MouseIsOver(dock) or MouseIsOver(menu) or (owner and MouseIsOver(owner))) then return end
  if dock then dock:Hide() end
 end)
end
local function Ensure()
 if dock then return end
 dock=CreateFrame('Frame','SmyrnaUpgradeSources',UIParent);dock:SetSize(96,30);dock:SetFrameStrata('TOOLTIP');dock:SetFrameLevel(210)
 menu=CreateFrame('Frame',nil,dock,'BackdropTemplate');menu:SetSize(334,240);menu:SetPoint('TOPLEFT',dock,'BOTTOMLEFT',0,-2);S.StylePanel(menu);menu:Hide()
 menu.title=menu:CreateFontString(nil,'OVERLAY','GameFontNormal');menu.title:SetPoint('TOPLEFT',8,-8)
 local scroll=CreateFrame('ScrollFrame',nil,menu,'UIPanelScrollFrameTemplate');scroll:SetPoint('TOPLEFT',8,-29);scroll:SetSize(298,200)
 local canvas=CreateFrame('Frame',nil,scroll);canvas:SetSize(294,280);scroll:SetScrollChild(canvas);menu.scroll,menu.canvas=scroll,canvas
 scroll:EnableMouseWheel(true);scroll:SetScript('OnMouseWheel',function(_,delta) scroll:SetVerticalScroll(math.max(0,math.min(scroll:GetVerticalScrollRange(),scroll:GetVerticalScroll()-delta*28))) end)
 menu.rows={}
 dock.buttons={}
 for i=1,10 do
  local b=CreateFrame('Button',nil,canvas,'UIPanelButtonTemplate');b:SetSize(294,25);b:SetPoint('TOPLEFT',0,-(i-1)*28);S.StyleButton(b);b.smyrnaUpgradeRow=true
  b:SetScript('OnClick',function() local filter=menu.filter;U.OpenDetails(slot,nil,owner,filter);dock:Hide() end)
  b:SetScript('OnEnter',function(self) if self.candidate then GameTooltip:SetOwner(self,'ANCHOR_RIGHT');GameTooltip:SetHyperlink('item:'..self.candidate.row.id);GameTooltip:Show() end end)
  b:SetScript('OnLeave',function() GameTooltip:Hide();Leave() end)
  menu.rows[i]=b
 end
 for i,entry in ipairs(kinds) do
  local key,title,icon=unpack(entry)
  local b=CreateFrame('Button',nil,dock);b:SetSize(28,28);b:SetPoint('LEFT',(i-1)*32,0)
  dock.buttons[i]=b
  local t=b:CreateTexture(nil,'ARTWORK');t:SetSize(23,23);t:SetPoint('CENTER');t:SetTexture(icon)
  if b.CreateMaskTexture and t.AddMaskTexture then local mask=b:CreateMaskTexture();mask:SetAllPoints(t);mask:SetTexture('Interface\\CHARACTERFRAME\\TempPortraitAlphaMask');t:AddMaskTexture(mask) end
  local border=b:CreateTexture(nil,'OVERLAY');border:SetAllPoints();border:SetTexture('Interface\\Minimap\\MiniMap-TrackingBorder')
  b:SetScript('OnClick',function() U.OpenDetails(slot,nil,owner,key);dock:Hide() end)
  b:SetScript('OnEnter',function()
   revision=revision+1;menu.filter=key;menu.title:SetText(title)
   local state=dock.state;local rows=state and (key=='AH' and state.rankedAH or state.groups[key]) or {}
   for j,row in ipairs(menu.rows) do row.candidate=rows[j];row:SetText(rows[j] and (j..'. '..rows[j].row.name) or 'No eligible upgrade found');row:SetEnabled(#rows>0);row:SetShown(rows[j]~=nil or j==1) end
   menu.canvas:SetHeight(math.max(28,#rows*28));menu.scroll:SetVerticalScroll(0);menu.scroll:UpdateScrollChildRect()
   menu:Show()
  end)
  b:SetScript('OnLeave',Leave)
 end
 menu:SetScript('OnLeave',Leave);dock:SetScript('OnLeave',Leave)
 dock:SetScript('OnHide',function() revision=revision+1;menu:Hide();dock.state=nil end)
 U.SourceDock,U.SourceMenu=dock,menu
 if CharacterFrame and CharacterFrame.HookScript then CharacterFrame:HookScript('OnHide',function() dock:Hide() end) end
end
function U.ShowSources(frame,equipmentSlot,state)
 if not state or (S.IsLootInteraction and S.IsLootInteraction(frame)) then return end
 if U.Details and U.Details:IsShown() then return end
 Ensure();revision=(revision or 0)+1;owner,slot=frame,equipmentSlot;dock.state=state
 dock:ClearAllPoints();dock:SetPoint('TOPLEFT',frame,'BOTTOMLEFT',0,-2);dock:Show()
end
function U.HideSourcesSoon() if dock then Leave() end end
function U.HideSources() if dock then dock:Hide() end end
local driver=CreateFrame('Frame');driver:RegisterEvent('LOOT_OPENED');driver:RegisterEvent('PLAYER_EQUIPMENT_CHANGED')
driver:SetScript('OnEvent',function() if dock then dock:Hide() end end)
