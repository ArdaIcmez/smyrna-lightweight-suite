local _,S=...
local J=S.Modules.SmyrnaJournal;if not J then return end
local public=S.Public or function(v) return not (issecretvalue and issecretvalue(v)) end
local function Text(parent,font,width)
    local t=parent:CreateFontString(nil,'OVERLAY',font or 'GameFontHighlightSmall')
    t:SetJustifyH('LEFT');t:SetWidth(width);return t
end
local function Button(parent,label,width,click)
    local b=CreateFrame('Button',nil,parent,'UIPanelButtonTemplate');b:SetSize(width,22);b:SetText(label);S.StyleButton(b);b:SetScript('OnClick',click);return b
end
local function Scroll(parent,x,y,w,h)
    local f=CreateFrame('ScrollFrame',nil,parent,'UIPanelScrollFrameTemplate');f:SetPoint('TOPLEFT',x,y);f:SetSize(w,h)
    local c=CreateFrame('Frame',nil,f);c:SetSize(w-6,h);f:SetScrollChild(c);f:EnableMouseWheel(true)
    f:SetScript('OnMouseWheel',function(self,delta)
        self:SetVerticalScroll(math.max(0,math.min(self:GetVerticalScrollRange(),self:GetVerticalScroll()-delta*36)))
    end)
    return f,c
end
local function Complete(id)
    if not id or not C_QuestLog or not C_QuestLog.IsQuestFlaggedCompleted then return false end
    local done=C_QuestLog.IsQuestFlaggedCompleted(id);return public(done) and done==true
end
local function LogIndex(id)
    if not id or not C_QuestLog or not C_QuestLog.GetLogIndexForQuestID then return end
    local idx=C_QuestLog.GetLogIndexForQuestID(id);if public(idx) and type(idx)=='number' and idx>0 then return idx end
end
local function CanShare(id)
    if not LogIndex(id) or not (IsInGroup and IsInGroup()) or not QuestLogPushQuest then return false end
    if not ((C_QuestLog and C_QuestLog.SetSelectedQuest) or SelectQuestLogEntry) then return false end
    if C_QuestLog and C_QuestLog.IsPushableQuest then
        local ok=C_QuestLog.IsPushableQuest(id);return public(ok) and ok==true
    end
    return false
end
local function Share(id)
    if not CanShare(id) then return end
    if C_QuestLog and C_QuestLog.SetSelectedQuest then
        C_QuestLog.SetSelectedQuest(id)
    elseif SelectQuestLogEntry then SelectQuestLogEntry(LogIndex(id)) end
    QuestLogPushQuest()
end
local function Faction(q,pf) return not pf or not q.f or q.f=='Both' or q.f==pf end
local function Location(m)
    return type(m)=='table' and public(m.mapID) and type(m.mapID)=='number' and m.mapID>0
        and public(m.x) and type(m.x)=='number' and m.x>=0 and m.x<=1
        and public(m.y) and type(m.y)=='number' and m.y>=0 and m.y<=1
end
local function ShowLocation(m)
    if not Location(m) then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if C_Map and C_Map.SetUserWaypoint and UiMapPoint and UiMapPoint.CreateFromCoordinates then
        C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(m.mapID,m.x,m.y))
    end
    if WorldMapFrame then WorldMapFrame:Show();if WorldMapFrame.SetMapID then WorldMapFrame:SetMapID(m.mapID) end end
end
local function Page(parent,kind)
    local v=CreateFrame('Frame',nil,parent);v:SetPoint('TOPLEFT',264,-134);v:SetSize(566,448);v.kind=kind;v.rowPool={};v.labels={};v.lootPool={}
    v.heading=Text(v,'GameFontNormal',548);v.heading:SetPoint('TOPLEFT',0,-3)
    v.left,v.list=Scroll(v,0,-30,178,408)
    v.paper=CreateFrame('Frame',nil,v,'BackdropTemplate');v.paper:SetPoint('TOPLEFT',198,-30);v.paper:SetSize(368,408)
    S.StyleCard(v.paper,.69,.58,.39);v.paper:SetBackdropColor(.69,.58,.39,1)
    if kind=='quests' then
        local art=v.paper:CreateTexture(nil,'BACKGROUND');art:SetAllPoints()
        if art:SetTexture('Interface\\QuestFrame\\QuestBG')~=false then art:SetAlpha(.25) else art:Hide() end
    else v.paper:SetBackdropColor(.055,.065,.085,1) end
    v.scroll,v.body=Scroll(v.paper,10,-8,326,362)
    v:SetScript('OnHide',function(self)
        if GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then
            local owner=GameTooltip.GetOwner and GameTooltip:GetOwner()
            for i=1,8 do
                if not owner then break end
                if owner==self then GameTooltip:Hide();break end
                owner=owner.GetParent and owner:GetParent()
            end
        end
    end)
    v:Hide();return v
end
local function ClearBody(v)
    for _,label in ipairs(v.labels) do label:Hide() end
    for _,row in ipairs(v.lootPool) do row:Hide() end
    v.labelIndex=0;v.y=4
end
local function Paragraph(v,title,body)
    if body==nil or body=='' then return end
    for i,value in ipairs({title,tostring(body)}) do
        v.labelIndex=v.labelIndex+1;local label=v.labels[v.labelIndex]
        if not label then label=Text(v.body,i==1 and 'GameFontNormal' or 'GameFontHighlight',316);v.labels[v.labelIndex]=label end
        label:SetFontObject(i==1 and 'GameFontNormal' or 'GameFontHighlight')
        label:ClearAllPoints();label:SetPoint('TOPLEFT',2,-v.y);label:SetText(value);label:SetWidth(316);label:SetWordWrap(true)
        if v.kind=='quests' then label:SetTextColor(i==1 and .30 or .12,i==1 and .17 or .075,.025)
        else label:SetTextColor(1,i==1 and .84 or .92,i==1 and .45 or .82) end
        label:Show();v.y=v.y+math.max(16,label:GetStringHeight())+5
    end
    v.y=v.y+8
end
local function Finish(v)
    v.body:SetHeight(math.max(362,v.y+8));v.scroll:UpdateScrollChildRect();v.scroll:SetVerticalScroll(0)
end
local function ItemRow(v,index,item,compact)
    local row=v.lootPool[index]
    if not row then
        row=CreateFrame('Button',nil,v.body,'BackdropTemplate');S.StyleCard(row,.055,.065,.085)
        row.tile=S.CreateIconTile(row,28);row.tile:SetPoint('LEFT',4,0)
        row.name=Text(row,'GameFontHighlightSmall',274);row.name:SetPoint('TOPLEFT',38,-5);row.name:SetMaxLines(1)
        row.sub=Text(row,'GameFontHighlightSmall',274);row.sub:SetPoint('TOPLEFT',38,-23);row.sub:SetMaxLines(1);row.sub:SetTextColor(.68,.74,.82)
        row:SetScript('OnEnter',function(self)
            if GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then
                GameTooltip:SetOwner(self,'ANCHOR_RIGHT');GameTooltip:SetHyperlink('item:'..self.itemID);GameTooltip:Show()
            end
        end)
        row:SetScript('OnLeave',function() if GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then GameTooltip:Hide() end end)
        row:SetScript('OnClick',function(self)
            if IsControlKeyDown and IsControlKeyDown() then
                local u=S.Modules.SmyrnaUpgrader;if u and u.OpenForItem then u.OpenForItem(self.itemID) end
            elseif IsShiftKeyDown and IsShiftKeyDown() and ChatEdit_InsertLink then
                local get=(C_Item and C_Item.GetItemInfo) or GetItemInfo
                if get then local _,link=get(self.itemID);if link then ChatEdit_InsertLink(link) end end
            elseif SetItemRef then SetItemRef('item:'..self.itemID,self.name:GetText(),'LeftButton') end
        end)
        v.lootPool[index]=row
    end
    local quality=item[4] or item[3] or 1;if type(quality)~='number' then quality=1 end
    local color=ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
    local r,g,b=color and color.r or 1,color and color.g or 1,color and color.b or 1
    row.itemID=item[1];row.name:SetText(item[2] or ('Item '..item[1]));row.name:SetTextColor(r,g,b)
    row.sub:SetText(type(item[3])=='string' and item[3] or 'Quest reward')
    local icon=C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(item[1])
    row.tile.icon:SetTexture((public(icon) and icon) or 'Interface\\Icons\\INV_Misc_QuestionMark');row.tile:SetBackdropBorderColor(r,g,b,.9)
    row:ClearAllPoints();row:SetSize(compact and 154 or 320,compact and 36 or 44)
    row.name:SetWidth(compact and 112 or 274);row.sub:SetWidth(274);row.sub:SetShown(not compact)
    row:Show();return row
end
local function ListRow(v,index,label,meta,selected,click)
    local row=v.rowPool[index]
    if not row then
        row=CreateFrame('Button',nil,v.list,'BackdropTemplate');row:SetSize(170,48);S.StyleCard(row)
        local inset=v.kind=='bosses' and 42 or 7
        if v.kind=='bosses' then row.portrait=S.CreateIconTile(row,30);row.portrait:SetPoint('LEFT',4,0) end
        row.title=Text(row,'GameFontHighlightSmall',170-inset-7);row.title:SetPoint('TOPLEFT',inset,-5);row.title:SetMaxLines(2)
        row.meta=Text(row,'GameFontHighlightSmall',156);row.meta:SetPoint('BOTTOMLEFT',v.kind=='bosses' and 42 or 7,4);row.meta:SetTextColor(.65,.72,.82)
        v.rowPool[index]=row
    end
    row.title:SetText(label);row.meta:SetText(meta);row:SetScript('OnClick',click);S.SetButtonSelected(row,selected)
    row:ClearAllPoints();row:SetPoint('TOPLEFT',0,-(index-1)*52);row:Show();return row
end
local function HideExtra(v,count)
    for i=count+1,#v.rowPool do v.rowPool[i]:Hide() end
    v.list:SetHeight(math.max(408,count*52));v.left:UpdateScrollChildRect()
end
local function RenderQuest(v)
    local q=v.selected;if not q then
        for _,button in ipairs({v.start,v.finish,v.track,v.share,v.prev,v.next}) do button:SetEnabled(false) end
        ClearBody(v);Paragraph(v,'Quests','No quests available for your faction.');Finish(v);return
    end
    ClearBody(v)
    Paragraph(v,q.n or q.name or 'Quest',(q.r or q.requires) and ('Available from level '..(q.r or q.requires)) or 'Quest guide')
    if Complete(q.id) then Paragraph(v,'Progress','Completed') elseif LogIndex(q.id) then Paragraph(v,'Progress','In your quest log') end
    Paragraph(v,'Objective',q.o or q.objective)
    Paragraph(v,'Starts at',q.p or q.pickup);Paragraph(v,'Turn in',q.t or q.turnin)
    Paragraph(v,'Important',q.warning);Paragraph(v,'Notes',q.note)
    local chain=v.root and v.root.chain
    if chain and #chain>0 then Paragraph(v,'Required before this dungeon quest',#chain..' steps. Select Show Chain to read each prerequisite.') end
    Paragraph(v,'Experience',q.xp and (q.xp..' XP') or nil)
    if q.rw and #q.rw>0 then
        Paragraph(v,q.choice and 'Choose one reward' or 'Rewards','Hover an item for details. Ctrl + left-click to check upgrades.')
        for i,item in ipairs(q.rw) do local row=ItemRow(v,i,item,false);row:SetPoint('TOPLEFT',0,-v.y);v.y=v.y+48 end
    end
    v.start:SetEnabled(Location(q.map) and true or false);v.finish:SetEnabled(Location(q.turninMap) and true or false)
    local logged=LogIndex(q.id)~=nil
    v.track:SetEnabled(not not (logged and C_QuestLog and C_QuestLog.AddQuestWatch))
    v.share:SetEnabled(CanShare(q.id))
    Finish(v)
end
local function QuestList(v)
    local count=0
    for _,q in ipairs(v.quests) do
        count=count+1;local root=q
        ListRow(v,count,(q.chain and #q.chain>0 and '+ ' or '')..(q.n or 'Quest'),Complete(q.id) and 'Completed' or ('Level '..(q.r or q.l or '?')),v.selected==q,function()
            v.root=root;v.selected=root;v.expanded=false;QuestList(v);RenderQuest(v)
        end)
        if v.expanded and v.root==q then
            for i,step in ipairs(q.chain or {}) do
                count=count+1;local selected=step
                ListRow(v,count,'  '..i..'. '..(step.name or 'Prerequisite'),Complete(step.id) and 'Completed' or 'Prerequisite',v.selected==step,function()
                    v.selected=selected;QuestList(v);RenderQuest(v)
                end)
            end
        end
    end
    v.chain:SetEnabled(v.root and v.root.chain and #v.root.chain>0 or false)
    v.chain:SetText(v.expanded and 'Hide Chain' or 'Show Chain');v.prev:SetEnabled(v.chain:IsEnabled());v.next:SetEnabled(v.chain:IsEnabled());HideExtra(v,count)
end
function J.RenderQuestPage(parent,d,pf)
    local v=J.QuestView
    if not v then
        v=Page(parent,'quests');J.QuestView=v
        v.chain=Button(v,'Show Chain',94,function() v.expanded=not v.expanded;QuestList(v) end);v.chain:SetPoint('TOPRIGHT',0,0)
        v.prev=Button(v,'<',24,function()
            local chain=v.root and v.root.chain or {};local index=0
            for i,q in ipairs(chain) do if q==v.selected then index=i end end
            v.selected=chain[math.max(1,index-1)] or v.root;v.expanded=true;QuestList(v);RenderQuest(v)
        end);v.prev:SetPoint('RIGHT',v.chain,'LEFT',-4,0)
        v.next=Button(v,'>',24,function()
            local chain=v.root and v.root.chain or {};local index=0
            for i,q in ipairs(chain) do if q==v.selected then index=i end end
            v.selected=chain[index+1] or v.root;v.expanded=true;QuestList(v);RenderQuest(v)
        end);v.next:SetPoint('RIGHT',v.prev,'LEFT',-4,0)
        v.start=Button(v.paper,'Start Map',80,function() if v.selected then ShowLocation(v.selected.map) end end);v.start:SetPoint('BOTTOMLEFT',6,5)
        v.finish=Button(v.paper,'Turn-in Map',88,function() if v.selected then ShowLocation(v.selected.turninMap) end end);v.finish:SetPoint('LEFT',v.start,'RIGHT',4,0)
        v.track=Button(v.paper,'Track',66,function() if v.selected and LogIndex(v.selected.id) and C_QuestLog.AddQuestWatch then C_QuestLog.AddQuestWatch(v.selected.id) end end);v.track:SetPoint('LEFT',v.finish,'RIGHT',4,0)
        v.share=Button(v.paper,'Share',66,function()
            if v.selected then Share(v.selected.id) end
        end);v.share:SetPoint('LEFT',v.track,'RIGHT',4,0)
        S.AttachTooltip(v.track,'Track quest','Track an accepted quest from your quest log.')
        S.AttachTooltip(v.share,'Share quest','Share an accepted quest with your party using the game. Some quests cannot be shared.')
        v:SetScript('OnShow',function(self) self:RegisterEvent('QUEST_LOG_UPDATE') end)
        v:HookScript('OnHide',function(self) self:UnregisterEvent('QUEST_LOG_UPDATE') end)
        v:SetScript('OnEvent',function() QuestList(v);RenderQuest(v) end)
    end
    if v.slug~=d.s or v.faction~=pf then
        v.slug=d.s;v.faction=pf;v.quests={};v.expanded=false
        local rows=(S.WorldDB.JournalQuests and S.WorldDB.JournalQuests(d.s)) or d.q or {}
        for _,q in ipairs(rows) do if Faction(q,pf) then v.quests[#v.quests+1]=q end end
        v.root=v.quests[1];v.selected=v.root;v.left:SetVerticalScroll(0)
    end
    v.heading:SetText('Quests ('..#v.quests..')');v.heading:SetWidth(210)
    v:Show();QuestList(v);RenderQuest(v)
end
local function BossBody(v)
    ClearBody(v);local boss=v.selected
    if not boss then Paragraph(v,'Bosses','No boss entries recorded.');Finish(v);return end
    Paragraph(v,boss.n or 'Boss',(boss.l and ('Level '..boss.l..'  |  ') or '')..#(boss.lt or {})..' drops')
    local items=boss.lt or {};local start=v.y;local compact=v.compact
    for i,item in ipairs(items) do
        local row=ItemRow(v,i,item,compact)
        row:SetPoint('TOPLEFT',compact and ((i-1)%2)*162 or 0,-(start+(compact and math.floor((i-1)/2)*40 or (i-1)*48)))
    end
    v.y=start+(compact and math.ceil(#items/2)*40 or #items*48)
    v.bestiary:SetEnabled(boss.id~=nil);Finish(v)
end
function J.RenderBossPage(parent,d,bossName,itemID)
    local v=J.BossView
    if not v then
        v=Page(parent,'bosses');J.BossView=v
        v.compactButton=Button(v,'Compact View',104,function() v.compact=not v.compact;v.compactButton:SetText(v.compact and 'Detailed View' or 'Compact View');BossBody(v) end)
        v.compactButton:SetPoint('TOPRIGHT',0,0)
        v.bestiary=Button(v.paper,'Loot & Resistances',150,function()
            local b=S.Modules.SmyrnaBestiary
            if b and b.OpenDrops and v.selected and v.selected.id then b.OpenDrops(v.selected.id) end
        end);v.bestiary:SetPoint('BOTTOMLEFT',8,5)
    end
    if v.slug~=d.s then v.slug=d.s;v.selected=(d.b or {})[1];v.left:SetVerticalScroll(0) end
    if bossName or itemID then
        for _,boss in ipairs(d.b or {}) do
            if boss.n==bossName then v.selected=boss;break end
            for _,item in ipairs(boss.lt or {}) do if item[1]==itemID then v.selected=boss;break end end
        end
    end
    v.heading:SetText('Bosses & loot');v:Show()
    for i,boss in ipairs(d.b or {}) do
        local picked=boss
        local row=ListRow(v,i,boss.n or 'Boss',(boss.r==1 and 'Rare  |  ' or '')..#(boss.lt or {})..' drops',v.selected==boss,function()
            v.selected=picked;J.RenderBossPage(parent,d)
        end)
        if row.portrait and J.ApplyBossPortrait then J.ApplyBossPortrait(row.portrait.icon,boss) end
    end
    HideExtra(v,#(d.b or {}));BossBody(v)
end
