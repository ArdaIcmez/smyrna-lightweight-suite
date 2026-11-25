local _,S=...
local U=S.Modules.SmyrnaUpgrader;if not U then return end
local panel,rows,subtitle,footer,scan,request,status,profileButton
local function Label(parent,text,x,y,width,font)
 local f=parent:CreateFontString(nil,'OVERLAY',font or 'GameFontHighlightSmall');f:SetPoint('TOPLEFT',x,y);f:SetWidth(width);f:SetJustifyH('LEFT');f:SetText(text);return f
end
local function Money(value)
 local v=math.max(0,math.ceil(value))
 local g=math.floor(v/10000); local s=math.floor(v/100)%100; local c=v%100
 local parts={}
 if g>0 then parts[#parts+1]=g..'|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:1:0|t' end
 if s>0 or g>0 then parts[#parts+1]=s..'|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:1:0|t' end
 parts[#parts+1]=c..'|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:1:0|t'
 return table.concat(parts,' ')
end
local function EnsureRow(i)
 if rows[i] then return rows[i] end
 local b=CreateFrame('Button',nil,panel.canvas,'BackdropTemplate');b:SetSize(650,79);b:SetPoint('TOPLEFT',0,-(i-1)*83);b.smyrnaUpgradeRow=true;S.StyleCard(b)
 b.tile=S.CreateIconTile(b,40);b.tile:SetPoint('TOPLEFT',10,-10);b.icon=b.tile.icon
 b.name=Label(b,'',60,-8,425,'GameFontHighlight');b.name:SetMaxLines(1)
 b.source=Label(b,'',60,-30,580);b.source:SetTextColor(.82,.78,.65);b.source:SetMaxLines(2)
 b.meta=Label(b,'',60,-60,580);b.meta:SetTextColor(.65,.67,.72)
 b.ah=CreateFrame('Button',nil,b,'UIPanelButtonTemplate');b.ah:SetSize(150,23);b.ah:SetPoint('TOPRIGHT',-5,-3);S.StyleButton(b.ah)
 b.ah:SetScript('OnClick',function()
  if not b.candidate or not S.Market then return end
  S.Market.OpenItem(b.candidate.row.id)
 end)
 b.journal=CreateFrame('Button',nil,b,'UIPanelButtonTemplate');b.journal:SetSize(74,23);b.journal:SetPoint('TOPRIGHT',-5,-3);b.journal:SetText('Journal');S.StyleButton(b.journal)
 b.journal:SetScript('OnClick',function()
  if not b.candidate then return end
  local J=S.Modules and S.Modules.SmyrnaJournal
  if J and J.OpenForItem then
   panel:Hide()
   J.OpenForItem(b.candidate.row.id,b.candidate.source and b.candidate.source.zone)
  end
 end)
 S.AttachTooltip(b.journal,'Open in Dungeon Journal','Jump directly to this item\'s dungeon, boss loot table, and dungeon map in Smyrna Journal.')
 b:SetScript('OnEnter',function(self) if self.candidate and GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then GameTooltip:SetOwner(self,'ANCHOR_RIGHT');GameTooltip:SetHyperlink('item:'..self.candidate.row.id);GameTooltip:Show() end end)
 b:SetScript('OnLeave',function() if GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then GameTooltip:Hide() end end)
 b:SetScript('OnClick',function(self) if self.candidate and SetItemRef then SetItemRef('item:'..self.candidate.row.id,self.candidate.row.name,'LeftButton') end end)
 rows[i]=b
 return b
end
function U.RenderDetails(state)
 if not panel or not panel:IsShown() or not request or state.slot~=request.slot or state.baseID~=request.id then return end
 panel.result=state
 status:Hide();profileButton:Hide();U.LastStatus=nil
 if S.SetButtonSelected then S.SetButtonSelected(panel.allTab,not panel.onlyAH and not panel.sourceFilter);S.SetButtonSelected(panel.ahTab,not not panel.onlyAH and not panel.sourceFilter) end
 local ranked=panel.sourceFilter=='AH' and state.rankedAH or (panel.sourceFilter and state.groups[panel.sourceFilter] or (panel.onlyAH and state.rankedAH or state.ranked))
 local isAHView=(panel.sourceFilter=='AH' or panel.onlyAH) and #ranked>0
 local ahPrices
 if isAHView and S.Market and S.Market.Price then
  local sorted={}; ahPrices={}
  for idx=1,#ranked do sorted[idx]=ranked[idx]; ahPrices[ranked[idx].row.id]=S.Market.Price(ranked[idx].row.id) end
  table.sort(sorted,function(a,b)
   local pa,pb=ahPrices[a.row.id],ahPrices[b.row.id]
   local aa=(pa and type(pa.minimum)=='number' and pa.minimum>0) and true or false
   local bb=(pb and type(pb.minimum)=='number' and pb.minimum>0) and true or false
   if aa~=bb then return aa end
   return (a.score or 0)>(b.score or 0)
  end)
  ranked=sorted
 end
 subtitle:SetText(state.baseName..'  -  '..state.profile.label..(panel.sourceFilter and (' / '..({Dungeon='Dungeon',Quest='Quest',AH='Auction House',Other='Profession / world drop'})[panel.sourceFilter]) or ''))
 local count=math.min(#ranked,35)
 for i=1,math.max(count,#rows) do
  local c=i<=count and ranked[i] or nil
  local b=c and EnsureRow(i) or rows[i]
  if b then b.candidate=c end
  if c then
   local price=(ahPrices and ahPrices[c.row.id]) or (S.Market and S.Market.Price(c.row.id))
   local avail=(price and type(price.minimum)=='number' and price.minimum>0) and true or false
   local color=ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[c.row.quality]
   local r,g,bl=color and color.r or 1,color and color.g or 1,color and color.b or 1
   if isAHView and not avail then r,g,bl=.56,.60,.66 end
   b:SetAlpha((isAHView and not avail) and .52 or 1)
   if b.icon and b.icon.SetDesaturated then b.icon:SetDesaturated(isAHView and not avail) end
   b.name:SetText(i..'. '..c.row.name..(c.percent and string.format('  +%.1f%%',c.percent) or ''))
   b.name:SetTextColor(r,g,bl)
   local icon=C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(c.row.id)
   b.icon:SetTexture((S.Public(icon) and icon) or 'Interface\\Icons\\INV_Misc_QuestionMark')
   if b.tile then b.tile:SetBackdropBorderColor(r,g,bl,.9) end
   if S.SetCornerGlow then S.SetCornerGlow(b,r,g,bl,(not isAHView or avail) and ((c.row.quality or 1)>=2 and .14 or .06) or .02) end
   local src=c.source or {}
   local skillTag=(type(src.skill)=='number' and src.skill>0) and (' | skill '..src.skill) or ''
   b.source:SetText(U.SourceLabel(c)..' - '..((src.zone and src.zone~='') and (src.zone..' / ') or '')..(src.name or '')..skillTag)
   b.meta:SetText((c.future and ('Available around Lv '..c.availableLevel..(c.training and (' - '..c.training) or '')) or ('Lv '..c.row.level))..' | '..c.row.subclass..' | '..(src.reference or 'Source')..(c.row.estimated and ' | Classic stats' or ''))
   local isVend=(src.kind=='Vendor')
   if not isVend and c.row and type(c.row.sources)=='table' then
    for _,s in ipairs(c.row.sources) do if s.kind=='Vendor' then isVend=true; break end end
   end
   if price then b.meta:SetText(b.meta:GetText()..' | AH price '..math.max(0,math.floor((time()-price.at)/60))..'m ago')
   elseif isAHView then b.meta:SetText(b.meta:GetText()..' | '..(isVend and '|cffffd36aVendor|r' or '|cffff6b5aNo AH|r')) end
   local showAH=S.Market~=nil and (c.row.bind=='Binds when equipped')
   b.ah:SetShown(showAH)
   b.ah:SetText(price and (Money(price.minimum)..' | AH') or (isAHView and (isVend and 'Vendor' or 'No AH') or 'Search AH'))
   local J=S.Modules and S.Modules.SmyrnaJournal
   local canJournal=(J and J.HasItemOrZone and J.HasItemOrZone(c.row.id,src.zone)) and true or false
   if b.journal then
    b.journal:SetShown(canJournal)
    b.journal:ClearAllPoints()
    if showAH then b.journal:SetPoint('RIGHT',b.ah,'LEFT',-5,0) else b.journal:SetPoint('TOPRIGHT',-5,-3) end
   end
   local nameW=(showAH and canJournal) and 348 or showAH and 426 or canJournal and 502 or 580
   b.name:SetWidth(nameW)
   b:Show()
  else b:Hide() end
 end
 local n=#ranked
 local futureShown=0;for _,c in ipairs(ranked) do if c.future then futureShown=futureShown+1 end end
 local currentShown=n-futureShown
 local breakdown=futureShown>0 and (' ('..currentShown..' usable now, '..futureShown..' upcoming)') or ''
 footer:SetText((n>0 and ('Showing '..n..' upgrades'..breakdown..'. Sorted by earliest level, then highest stat upgrade.') or 'No upgrades found for this slot.')..'\n'..(state.context and not state.context.trainingKnown and 'Using your class weapon list. ' or '')..'Check item procs, quest prerequisites, and Auction House prices.')
 scan:SetEnabled(S.Market~=nil and n>0)
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
 panel:SetFrameStrata('FULLSCREEN_DIALOG');panel:SetFrameLevel(200);panel:SetClampedToScreen(true);S.StylePanel(panel,true);S.HeaderStrip(panel,38);S.CloseButton(panel)
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
 for i=1,10 do EnsureRow(i) end
 scan=CreateFrame('Button',nil,panel,'UIPanelButtonTemplate');scan:SetSize(185,25);scan:SetPoint('TOPLEFT',18,-492);scan:SetText('Scan AH for these upgrades');S.StyleButton(scan);scan:Hide()
 scan:SetScript('OnClick',function()
  if not S.Market or not panel.result then return end
  local ids={};for _,c in ipairs(panel.result.rankedAH or {}) do if c.row.bind=='Binds when equipped' then ids[#ids+1]=c.row.id end end
  S.Market.Scan(ids)
 end)
 footer=Label(panel,'',18,-530,680);footer:SetMaxLines(3)
 panel:SetScript('OnHide',function() request=nil;U.DetailRequest=nil;panel.result=nil;if GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then GameTooltip:Hide() end end)
 UISpecialFrames[#UISpecialFrames+1]='SmyrnaUpgraderDetails';U.Details=panel;U.DetailRows=rows
end
function U.OpenDetails(slot,id,owner,sourceFilter)
 if U.HideSources then U.HideSources() end
 OpenPanel()
 panel.sourceFilter=sourceFilter
 local invLink=GetInventoryItemLink('player',slot)
 local fallbackID=(S.Public(invLink) and type(invLink)=='string') and tonumber(invLink:match('item:(%d+)')) or nil
 request={slot=slot,id=id or fallbackID}
 U.DetailRequest=request
 subtitle:SetText('Checking upgrades...');footer:SetText('');scan:SetEnabled(false);status:Hide();profileButton:Hide()
 for _,b in ipairs(rows) do b:Hide() end
 panel.result=nil;panel:Show()
 local _,reason=U.Hover(owner or UIParent,slot,id,nil,true)
 if reason then U.RenderStatus(reason) end
end
function U.OpenForItem(itemID)
 if not S.Num(itemID,1,10000000,true) then return false end
 if S.Equipment and S.Equipment.Ensure then S.Equipment.Ensure() end
 local slot=U.SlotForItem and U.SlotForItem(itemID)
 if not slot then return false end
 U.OpenDetails(slot,itemID,UIParent)
 return true
end
function U.RefreshMarketPrices()
 if panel and panel.result then U.RenderDetails(panel.result) end
end
