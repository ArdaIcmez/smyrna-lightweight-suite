local _,S=...
local U=S.Modules.SmyrnaUpgrader;if not U then return end
local panel,rows,subtitle,footer,scan,request,status,profileButton
local function Label(parent,text,x,y,width,font)
 local f=parent:CreateFontString(nil,'OVERLAY',font or 'GameFontHighlightSmall');f:SetPoint('TOPLEFT',x,y);f:SetWidth(width);f:SetJustifyH('LEFT');f:SetText(text);return f
end
local function Money(value)
 return GetCoinTextureString and GetCoinTextureString(math.ceil(value)) or tostring(math.ceil(value))..' copper'
end
function U.RenderDetails(state)
 if not panel or not panel:IsShown() or not request or state.slot~=request.slot or state.baseID~=request.id then return end
 panel.result=state
 status:Hide();profileButton:Hide();U.LastStatus=nil
 if S.SetButtonSelected then S.SetButtonSelected(panel.allTab,not panel.onlyAH and not panel.sourceFilter);S.SetButtonSelected(panel.ahTab,not not panel.onlyAH and not panel.sourceFilter) end
 local ranked=panel.sourceFilter=='AH' and state.rankedAH or (panel.sourceFilter and state.groups[panel.sourceFilter] or (panel.onlyAH and state.rankedAH or state.ranked))
 subtitle:SetText(state.baseName..'  -  '..state.profile.label..(panel.sourceFilter and (' / '..({Dungeon='Dungeon',Quest='Quest',AH='Auction House',Other='Profession / world drop'})[panel.sourceFilter]) or ''))
 for i,b in ipairs(rows) do
  local c=ranked[i];b.candidate=c
  if c then
   local color=ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[c.row.quality]
   b.name:SetText(i..'. '..c.row.name..(c.percent and string.format('  +%.1f%%',c.percent) or ''))
   b.name:SetTextColor(color and color.r or 1,color and color.g or 1,color and color.b or 1)
   local icon=C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(c.row.id)
   b.icon:SetTexture(icon or 'Interface\\Icons\\INV_Misc_QuestionMark')
   local src=c.source
   b.source:SetText(U.SourceLabel(c)..' — '..(src.zone~='' and (src.zone..' / ') or '')..src.name..(src.skill>0 and (' · skill '..src.skill) or ''))
   b.meta:SetText((c.future and ('Next at Lv '..c.availableLevel..(c.training and (' - '..c.training) or ' - source-level estimate')) or ('Lv '..c.row.level))..' | '..c.row.subclass..' | '..src.reference..(c.row.estimated and ' | Classic-estimated stats' or ''))
   local price=S.Market and S.Market.Price(c.row.id)
   if price then b.meta:SetText(b.meta:GetText()..' · AH quote '..math.max(0,math.floor((time()-price.at)/60))..'m ago') end
   b.ah:SetShown(c.row.bind=='Binds when equipped')
   b.ah:SetText(price and (Money(price.minimum)..' · AH') or 'Find on AH')
   b:Show()
  else b:Hide() end
 end
 local n=#ranked
 footer:SetText((n>0 and ('Showing '..n..' upgrades. Earliest usable/source level first; ties use stat score.') or 'No upgrade found in eligible reference data.')..'\n'..(state.context and not state.context.trainingKnown and 'Weapon training not reported; class weapon rules used. ' or '')..'Check procs, quest access and AH variants.')
 scan:SetEnabled(n>0)
 panel.canvas:SetHeight(math.max(90,n*83));panel.scroll:UpdateScrollChildRect()
end
function U.RenderStatus(message,slot,id)
 if not panel or not panel:IsShown() or not request then return end
 if slot and (slot~=request.slot or id~=request.id) then return end
 U.LastStatus=message;panel.result=nil
 for _,row in ipairs(rows) do row:Hide() end
 subtitle:SetText('Upgrade recommendations');status:SetText(message);status:Show()
 profileButton:SetShown(message:find('profile',1,true)~=nil)
 footer:SetText('Ctrl while hovering character gear shows the source circles.');scan:SetEnabled(false)
 panel.canvas:SetHeight(180);panel.scroll:UpdateScrollChildRect()
end
local function OpenPanel()
 if panel then return end
 panel=CreateFrame('Frame','SmyrnaUpgraderDetails',UIParent,'BackdropTemplate');panel:SetSize(730,585);panel:SetPoint('CENTER')
 panel:SetFrameStrata('FULLSCREEN_DIALOG');panel:SetFrameLevel(200);panel:SetClampedToScreen(true);S.StylePanel(panel);S.CloseButton(panel)
 if S.HeaderStrip then S.HeaderStrip(panel) end
 Label(panel,'Nearest upgrades',18,-16,650,'GameFontNormalLarge')
 subtitle=Label(panel,'',18,-44,680,'GameFontHighlight')
 local all=CreateFrame('Button',nil,panel,'UIPanelButtonTemplate');all:SetSize(105,23);all:SetPoint('TOPLEFT',405,-12);all:SetText('All upgrades');S.StyleButton(all)
 local ah=CreateFrame('Button',nil,panel,'UIPanelButtonTemplate');ah:SetSize(105,23);ah:SetPoint('TOPLEFT',515,-12);ah:SetText('AH upgrades');S.StyleButton(ah)
 all:SetScript('OnClick',function() panel.onlyAH=false;panel.sourceFilter=nil;if panel.result then U.RenderDetails(panel.result) end end)
 ah:SetScript('OnClick',function() panel.onlyAH=true;panel.sourceFilter=nil;if panel.result then U.RenderDetails(panel.result) end end)
 panel.allTab=all;panel.ahTab=ah
 local scroll=CreateFrame('ScrollFrame' ,nil,panel,'UIPanelScrollFrameTemplate');scroll:SetPoint('TOPLEFT',18,-75);scroll:SetSize(672,405);panel.scroll=scroll
 local canvas=CreateFrame('Frame',nil,scroll);canvas:SetSize(650,830);scroll:SetScrollChild(canvas);panel.canvas=canvas
 rows={}
 status=Label(canvas,'',8,-8,620,'GameFontHighlight');status:Hide()
 profileButton=CreateFrame('Button',nil,canvas,'UIPanelButtonTemplate');profileButton:SetSize(180,25);profileButton:SetPoint('TOPLEFT',8,-100);profileButton:SetText('Choose scoring profile');S.StyleButton(profileButton);profileButton:Hide()
 profileButton:SetScript('OnClick',function() panel:Hide();U.Open() end)
 for i=1,10 do
  local b=CreateFrame('Button',nil,canvas,'BackdropTemplate');b:SetSize(650,79);b:SetPoint('TOPLEFT',0,-(i-1)*83);b.smyrnaUpgradeRow=true;S.StylePanel(b)
  b.icon=b:CreateTexture(nil,'ARTWORK');b.icon:SetSize(40,40);b.icon:SetPoint('TOPLEFT',9,-10)
  b.name=Label(b,'',60,-8,425,'GameFontHighlight');b.name:SetMaxLines(1)
  b.source=Label(b,'',60,-30,580);b.source:SetTextColor(.82,.78,.65);b.source:SetMaxLines(2)
  b.meta=Label(b,'',60,-60,580);b.meta:SetTextColor(.65,.67,.72)
  b.ah=CreateFrame('Button',nil,b,'UIPanelButtonTemplate');b.ah:SetSize(150,23);b.ah:SetPoint('TOPRIGHT',-5,-3);S.StyleButton(b.ah)
  b.ah:SetScript('OnClick',function()
   if not b.candidate or not S.Market then return end
   S.Market.OpenItem(b.candidate.row.id)
  end)
  b:SetScript('OnEnter',function(self) if self.candidate then GameTooltip:SetOwner(self,'ANCHOR_RIGHT');GameTooltip:SetHyperlink('item:'..self.candidate.row.id);GameTooltip:Show() end end)
  b:SetScript('OnLeave',function() GameTooltip:Hide() end)
  b:SetScript('OnClick',function(self) if self.candidate and SetItemRef then SetItemRef('item:'..self.candidate.row.id,self.candidate.row.name,'LeftButton') end end)
  rows[i]=b
 end
 scan=CreateFrame('Button',nil,panel,'UIPanelButtonTemplate');scan:SetSize(185,25);scan:SetPoint('TOPLEFT',18,-492);scan:SetText('Scan AH for these upgrades');S.StyleButton(scan)
 scan:SetScript('OnClick',function()
  if not S.Market or not panel.result then return end
  local ids={};for _,c in ipairs(panel.result.rankedAH or {}) do if c.row.bind=='Binds when equipped' then ids[#ids+1]=c.row.id end end
  S.Market.Scan(ids)
 end)
 footer=Label(panel,'',18,-530,680);footer:SetMaxLines(3)
 panel:SetScript('OnHide',function() request=nil;U.DetailRequest=nil;panel.result=nil;GameTooltip:Hide() end)
 UISpecialFrames[#UISpecialFrames+1]='SmyrnaUpgraderDetails';U.Details=panel;U.DetailRows=rows
end
function U.OpenDetails(slot,id,owner,sourceFilter)
 if U.HideSources then U.HideSources() end
 OpenPanel()
 panel.sourceFilter=sourceFilter
 request={slot=slot,id=id or tonumber((GetInventoryItemLink('player',slot) or ''):match('item:(%d+)'))}
 U.DetailRequest=request
 subtitle:SetText('Checking upgrades...');footer:SetText('');scan:SetEnabled(false);status:Hide();profileButton:Hide()
 for _,b in ipairs(rows) do b:Hide() end
 panel.result=nil;panel:Show()
 local _,reason=U.Hover(owner or UIParent,slot,id)
 if reason then U.RenderStatus(reason) end
end
function U.RefreshMarketPrices()
 if panel and panel.result then U.RenderDetails(panel.result) end
end
