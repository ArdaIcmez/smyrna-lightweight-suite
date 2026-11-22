local _,Suite=...
local name="SmyrnaRemembrance"
Suite.Versions[name]="0.6.0"
if Suite.Config.features[name]==false then return end
local Module={}
Suite.Modules[name]=Module

-- Internal module source: Core.lua
do local function chunk(...)
local _,NS=...
local base,clockBase,currentGUID,currentKey,previous,previousInfo,clockLast
function NS.Public(v) return not issecretvalue or not issecretvalue(v) end
local function Number(v,min,max) return NS.Public(v) and type(v)=="number" and v==v and v%1==0 and v>=min and v<=max end
local function Text(v) return NS.Public(v) and type(v)=="string" and #v>0 and #v<=200 and not v:find("[%c|]") and v or nil end
local function Clock() return GetTimePreciseSec and GetTimePreciseSec() or GetTime() end
function NS.Init()
    NS.DB=SmyrnaRemembranceStore.Open(SmyrnaRemembranceDB)
    -- Clear only after the enabled destination has adopted the legacy table.
    SmyrnaRemembranceDB=nil
    NS.DB.records=type(NS.DB.records)=="table" and NS.DB.records or {}
    NS.DB.histories=type(NS.DB.histories)=="table" and NS.DB.histories or {}
    for key,value in pairs({enabled=true,tooltip=true,icon=true,npcs=true,players=true,showLevel=true,showLocation=true,history=true}) do
        if type(NS.DB[key])~="boolean" then NS.DB[key]=value end
    end
    NS.DB.limit=nil -- History is retained until explicitly cleared.
    NS.DB.history=false -- Meaningful activities replace new daily location snapshots.
    NS.DB.innkeepers=type(NS.DB.innkeepers)=="table" and NS.DB.innkeepers or {}
    base=GetServerTime and GetServerTime() or time();clockBase=Clock();clockLast=base*1000
    NS.InitLocations()
    NS.ValidateRecords()
    if NS.InitActivities then NS.InitActivities() end
end
function NS.Now()
    local ms=math.floor((base+Clock()-clockBase)*1000)
    if ms<clockLast then ms=clockLast end;clockLast=ms;return ms
end
function NS.Format(ms)
    if type(ms)~="number" then return "First seen" end
    return date("%d %b %Y %H:%M",math.floor(ms/1000))
end
local function CalendarDay(ms)
    local stamp=math.floor(ms/1000)
    local year=tonumber(date("%Y",stamp));local day=tonumber(date("%j",stamp));local prior=year-1
    return prior*365+math.floor(prior/4)-math.floor(prior/100)+math.floor(prior/400)+day
end
function NS.FirstSeenText(ms,now)
    if not Number(ms,0,10^15) then return "Unknown" end
    local days=CalendarDay(now or NS.Now())-CalendarDay(ms)
    if days==0 then return "Today" end
    if days>0 then return NS.Format(ms).." ("..days..(days==1 and " day ago)" or " days ago)") end
    return NS.Format(ms)
end
function NS.SameDay(first,last)
    if type(first)~="number" or type(last)~="number" then return false end
    return date("%Y%m%d",math.floor(first/1000))==date("%Y%m%d",math.floor(last/1000))
end
-- Saved record v4: name|last ms|map|level|location|first ms.
-- Daily strings live in one separate GUID-keyed history map. This keeps
-- ordinary hover/page lookups independent of the size of daily histories.
-- A ~ prefix on first marks the earliest surviving pre-history timestamp.
-- Observed names/locations exclude pipes and controls, so separators need no
-- escaping. Keeping GUID -> string avoids a separate Lua table per person.
local function UnpackRecord(record)
    if type(record)=="table" then return record.name,record.last,record.map,record.level,record.location end
    if type(record)~="string" then return end
    local name,stamp,map,level,location,first=record:match("^([^|]+)|(%d+)|(%d+)|(%d*)|([^|]*)|(~?%d+)$")
    local history
    if not name then name,stamp,map,level,location,first,history=record:match("^([^|]+)|(%d+)|(%d+)|(%d*)|([^|]*)|(~?%d+)|([^|]*)$") end
    if not name then name,stamp,map,level,location=record:match("^([^|]+)|(%d+)|(%d+)|(%d*)|([^|]*)$") end
    if not name then return end
    return name,tonumber(stamp),tonumber(map),tonumber(level),location~="" and location or nil,first,history
end
local function SavedLocation(value)
    return NS.Public(value) and type(value)=="string" and #value>0 and #value<=402 and not value:find("[%c|]") and value or nil
end
local locationIndex={}
function NS.InitLocations()
    NS.DB.locations=type(NS.DB.locations)=="table" and NS.DB.locations or {}
    wipe(locationIndex)
    for id,value in ipairs(NS.DB.locations) do if type(value)=="string" then locationIndex[value]=id end end
end
local function LocationID(map,location)
    local value=map.."|"..(location or "")
    local id=locationIndex[value]
    if not id then id=#NS.DB.locations+1;NS.DB.locations[id]=value;locationIndex[value]=id end
    return id
end
local function Day(stamp) return date("%Y%m%d",math.floor(stamp/1000)) end
function NS.PackRecord(name,stamp,map,level,location,first,history)
    return name.."|"..string.format("%.0f",stamp).."|"..map.."|"..(level or "").."|"..(location or "").."|"..(first or string.format("%.0f",stamp))
end
function NS.ReadRecord(key,record)
    local name,stamp,map,level,location,first,history=UnpackRecord(record)
    if not name then return end
    local player=key:sub(1,2)=="P:"
    return {key=key,name=name,last=stamp,map=map,level=level,location=location,first=first and tonumber((first:gsub("~",""))) or stamp,firstApprox=not first or first:sub(1,1)=="~",firstToken=first,history=NS.DB.histories[key] or history or "",kind=player and "player" or "npc",id=not player and tonumber(key:match("^(%d+):")) or nil}
end
local function DailySnapshot(history,stamp,level,map,location)
    local last=history:match("(%d+),%d*,%d+$")
    if last and Number(tonumber(last),0,stamp/60000) and Day(tonumber(last)*60000)==Day(stamp) then return history end
    local entries={}
    for entry in history:gmatch("[^;]+") do entries[#entries+1]=entry end
    -- Keep the first day permanently and rotate the 10 recent-day slots.
    while #entries>=11 do table.remove(entries,2) end
    entries[#entries+1]=math.floor(stamp/60000)..","..(level or "")..","..LocationID(map,location)
    return table.concat(entries,";")
end
function NS.History(key)
    local row=NS.ReadRecord(key,NS.DB.records[key]);local rows={}
    if not row then return rows end
    for stamp,level,id in row.history:gmatch("(%d+),(%d*),(%d+)") do
        local place=NS.DB.locations[tonumber(id)]
        local map,location
        if type(place)=="string" then map,location=place:match("^(%d+)|([^|]*)$") end
        local minute=tonumber(stamp);local savedLevel=tonumber(level)
        if Number(minute,0,row.last/60000) and type(place)=="string" and (level=="" or Number(savedLevel,1,1000)) then table.insert(rows,1,{last=minute*60000,level=savedLevel,map=tonumber(map),location=location~="" and location or nil}) end
        if #rows>=11 then break end
    end
    return rows
end
function NS.ValidateRecords()
    local records=NS.DB.records
    local histories={}
    NS.Count=0;NS.InnkeeperRecords={};NS.Revision=(NS.Revision or 0)+1
    -- One linear validation/migration pass on login; no sort or eviction.
    for key,record in pairs(records) do
        local player=type(key)=="string" and key:sub(1,2)=="P:"
        local id=type(key)=="string" and tonumber(key:match("^(%d+):%d+$"))
        local innkeeper=id and NS.DB.innkeepers[id]==true
        local name,stamp,map,level,location,first,history=UnpackRecord(record)
        if not Number(stamp,0,10^15) or not Text(name) or not (player or innkeeper) then records[key]=nil
        else
            map=Number(map,0,10000000) and map or 0
            level=Number(level,1,1000) and level or nil
            location=SavedLocation(location)
            if not first or not Number(tonumber((first:gsub("~",""))),0,stamp) then first="~"..string.format("%.0f",stamp) end
            history=NS.DB.histories[key] or history
            if type(history)~="string" or #history>4000 then history="" end
            if NS.DB.recordVersion~=5 then
                -- Deep validation only during schema migration. Native reloads
                -- retain the already-produced bounded string without decoding
                -- every daily snapshot for every saved player.
                local entries={}
                for entry in history:gmatch("[^;]+") do
                    local minute,savedLevel,id=entry:match("^(%d+),(%d*),(%d+)$")
                    if minute and tonumber(minute)<=stamp/60000 and (savedLevel=="" or Number(tonumber(savedLevel),1,1000)) and NS.DB.locations[tonumber(id)] then entries[#entries+1]=entry end
                    if #entries>11 then table.remove(entries,2) end
                end
                history=table.concat(entries,";")
            end
            if player and NS.DB.history and history=="" then history=DailySnapshot(history,stamp,level,map,location) end
            if not player then history="" end
            local packed=NS.PackRecord(name,stamp,map,level,location,first,history)
            records[key]=packed;NS.Count=NS.Count+1
            if player and history~="" then histories[key]=history end
            if not player then NS.InnkeeperRecords[key]=packed end
        end
    end
    NS.DB.histories=histories
    NS.DB.recordVersion=5
end
function NS.LearnInnkeeper()
    if not NS.DB or not NS.DB.enabled or not NS.DB.npcs or not C_GossipInfo or not C_GossipInfo.GetOptions then return end
    local options=C_GossipInfo.GetOptions()
    if not NS.Public(options) or type(options)~="table" then return end
    local binder=false
    for _,option in ipairs(options) do
        if NS.Public(option) and type(option)=="table" then
            local icon,kind=option.icon,option.type
            -- Forever's home-binding gossip icon; no localized text guessing.
            if (NS.Public(icon) and icon==132052) or (NS.Public(kind) and kind=="binder") then binder=true;break end
        end
    end
    if not binder then return end
    local guid=UnitGUID("npc")
    if not NS.Public(guid) or type(guid)~="string" then return end
    local id=tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
    if not id then return end
    NS.DB.innkeepers[id]=true
    NS.ClearHover();NS.Observe("npc")
end
function NS.ClearHover() currentGUID=nil;currentKey=nil;previous=nil;previousInfo=nil end
local function Location(map)
    local value=GetRealZoneText and GetRealZoneText()
    if not NS.Public(value) then return nil end
    local zone=Text(value)
    if not zone and map>0 and C_Map and C_Map.GetMapInfo then local info=C_Map.GetMapInfo(map);if NS.Public(info) and type(info)=="table" then zone=Text(info.name) end end
    local sub=GetSubZoneText and Text(GetSubZoneText())
    if zone and sub and sub~=zone then return sub..", "..zone end
    return zone or sub
end
function NS.Observe(unit)
    if not NS.DB or not NS.DB.enabled or not NS.Public(unit) or type(unit)~="string" then return end
    local guid=UnitGUID(unit)
    if not NS.Public(guid) or type(guid)~="string" then NS.ClearHover();return end
    local player=guid:match("^Player%-%d+%-%x+$")~=nil
    if UnitIsPlayer then local flag=UnitIsPlayer(unit);if not NS.Public(flag) or (not not flag)~=player then NS.ClearHover();return end end
    if player then
        if not NS.DB.players then NS.ClearHover();return end
        if UnitIsUnit then local same=UnitIsUnit(unit,"player");if not NS.Public(same) or same then NS.ClearHover();return end end
        if UnitIsVisible then local visible=UnitIsVisible(unit);if not NS.Public(visible) or not visible then NS.ClearHover();return end end
    elseif not NS.DB.npcs then NS.ClearHover();return end
    local id=not player and tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-") or guid:match("^Vehicle%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
    if not player and (not id or NS.DB.innkeepers[id]~=true) then NS.ClearHover();return end
    if guid==currentGUID then return previous,currentKey,previousInfo end
    local name,realm
    if player and UnitFullName then name,realm=UnitFullName(unit) else name,realm=UnitName(unit) end
    name=Text(name);if not name then NS.ClearHover();return end
    realm=Text(realm)
    if player then name=Suite.PlayerName(name,realm) end
    local map=C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or 0
    if not Number(map,0,10000000) then map=0 end
    local key=player and ("P:"..guid) or (id..":"..map)
    local row=NS.ReadRecord(key,NS.DB.records[key]);local now=NS.Now()
    previous=row and row.last or nil
    previousInfo=row
    currentGUID=guid;currentKey=key
    if not row then NS.Count=NS.Count+1 end
    local level=UnitLevel and UnitLevel(unit)
    level=Number(level,1,1000) and level or nil
    local location=Location(map)
    local first=row and (row.firstToken or ("~"..string.format("%.0f",row.last))) or string.format("%.0f",now)
    local history=player and row and row.history or ""
    if player and NS.DB.history then history=DailySnapshot(history,now,level,map,location) end
    local packed=NS.PackRecord(name,now,map,level,location,first,history)
    NS.DB.records[key]=packed
    if player then NS.DB.histories[key]=history~="" and history or nil end
    if not player then NS.InnkeeperRecords[key]=packed end
    NS.Revision=(NS.Revision or 0)+1
    return previous,key,previousInfo
end
function NS.Description(row)
    local parts={}
    if NS.DB.showLevel then parts[#parts+1]=row.level and ("Level "..row.level) or "Level unknown" end
    if NS.DB.showLocation then parts[#parts+1]=row.location or "Location unknown" end
    return table.concat(parts," - ")
end
NS.PAGE_SIZE=25
NS.PAGE_SCAN=500
function NS.Page(filter,cursor)
    local records,rows=filter=="npc" and NS.InnkeeperRecords or NS.DB.records,{}
    if cursor and not records[cursor] then cursor=nil end
    local key=cursor
    for i=1,NS.PAGE_SCAN do
        local row
        key,row=next(records,key)
        if not key then return rows,nil,false end
        local kind=key:sub(1,2)=="P:" and "player" or "npc"
        if not filter or filter=="all" or kind==filter then rows[#rows+1]=NS.ReadRecord(key,row) end
        if #rows==NS.PAGE_SIZE then break end
    end
    return rows,key,next(records,key)~=nil
end
end chunk(name,Module) end


-- Internal module source: UI.lua
do local function chunk(...)
local _,NS=...
local panel,list,icon,limitText,backButton,nextButton,measure
local historyPanel,historyList,historySummary,historyMeasure,historyScroll
local historyButtons={}
local cursor,following,hasMore,revision
local pages={}
local filter="all"
local checks={}
function NS.OpenHistory(key)
    local row=NS.DB and NS.ReadRecord(key,NS.DB.records[key])
    local entries,activityCount={},0
    if row and NS.Activities then entries,activityCount=NS.Activities.Lines(key) end
    activityCount=activityCount or 0
    if not row then if historyPanel then historyPanel:Hide() end;return end
    if not historyPanel then
        historyPanel=CreateFrame("Frame","SmyrnaRemembranceHistory",UIParent,"BackdropTemplate");historyPanel:SetSize(420,180);historyPanel:SetPoint("CENTER");historyPanel:SetFrameStrata("FULLSCREEN_DIALOG");historyPanel:SetFrameLevel(100);historyPanel:SetClampedToScreen(true);historyPanel:EnableMouse(true)
        historyPanel:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12});historyPanel:SetBackdropColor(.035,.035,.04,1)
        local close=CreateFrame("Button",nil,historyPanel,"UIPanelCloseButton");close:SetPoint("TOPRIGHT");close:SetScript("OnClick",function() historyPanel:Hide() end)
        historySummary=historyPanel:CreateFontString(nil,"OVERLAY","GameFontHighlight");historySummary:SetPoint("TOPLEFT",20,-20);historySummary:SetWidth(500);historySummary:SetJustifyH("LEFT")
        historyScroll=CreateFrame("ScrollFrame",nil,historyPanel,"UIPanelScrollFrameTemplate");local scroll=historyScroll;scroll:SetPoint("TOPLEFT",20,-125);scroll:SetPoint("BOTTOMRIGHT",-38,20)
        historyList=CreateFrame("EditBox",nil,scroll);historyList:SetMultiLine(true);historyList:SetAutoFocus(false);historyList:SetFontObject(ChatFontNormal);historyList:SetWidth(495);historyList:SetScript("OnEscapePressed",function(self) self:ClearFocus() end);scroll:SetScrollChild(historyList)
        historyMeasure=historyPanel:CreateFontString(nil,"BACKGROUND","ChatFontNormal");historyMeasure:SetWidth(495);historyMeasure:Hide()
        UISpecialFrames[#UISpecialFrames+1]="SmyrnaRemembranceHistory"
    end
    local lastLine=NS.SameDay(row.first,row.last) and "" or ("\n"..Suite.UIText("Last seen: ","muted")..NS.Format(row.last))
    historySummary:SetText(Suite.UIText(row.name,"heading").."\n"..Suite.UIText("First seen: ","muted")..NS.Format(row.first)..lastLine..(activityCount>0 and ("\n"..Suite.UIText(activityCount.." shared activities","detail")) or ""))
    local lines=entries
    local text=table.concat(lines,"\n")
    local widest=0
    historyMeasure:SetWidth(0)
    for _,line in ipairs(lines) do
        historyMeasure:SetText(line)
        local width=historyMeasure.GetStringWidth and historyMeasure:GetStringWidth()
        if type(width)=="number" then widest=math.max(widest,width) end
    end
    historyMeasure:SetText(row.name)
    local nameWidth=historyMeasure.GetStringWidth and historyMeasure:GetStringWidth()
    if type(nameWidth)=="number" then widest=math.max(widest,nameWidth) end
    local width=math.max(320,math.min(560,widest+65))
    historySummary:SetWidth(width-60);historyList:SetWidth(width-58);historyMeasure:SetWidth(width-58)
    historyList:SetText(text);historyMeasure:SetText(text)
    local bodyHeight=historyMeasure:GetStringHeight()+12
    local top=20+historySummary:GetStringHeight()+16
    historyScroll:ClearAllPoints();historyScroll:SetPoint("TOPLEFT",20,-top);historyScroll:SetPoint("BOTTOMRIGHT",-38,20)
    local available=UIParent and UIParent.GetHeight and UIParent:GetHeight()
    local maximum=type(available)=="number" and available>300 and math.min(560,available-80) or 560
    historyScroll:SetShown(#entries>0)
    historyPanel:SetSize(width,#entries>0 and math.min(maximum,math.max(90,top+bodyHeight+20)) or (top+4))
    historyList:SetHeight(bodyHeight);historyMeasure:SetText("");historyScroll:SetVerticalScroll(0);historyScroll:UpdateScrollChildRect()
    historyPanel:Show();return historyPanel
end
function NS.Open()
    if revision~=NS.Revision then cursor=nil;pages={};revision=NS.Revision end
    if not panel then
        panel=CreateFrame("Frame","SmyrnaRemembrancePanel",UIParent,"BackdropTemplate");panel:SetSize(620,490);panel:SetPoint("CENTER");panel:SetFrameStrata("DIALOG");panel:SetClampedToScreen(true)
        panel:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12});panel:SetBackdropColor(.04,.04,.04,.98)
        local title=panel:CreateFontString(nil,"OVERLAY","GameFontNormalLarge");title:SetPoint("TOPLEFT",20,-20);title:SetText("Smyrna Remembrance")
        local close=CreateFrame("Button",nil,panel,"UIPanelCloseButton");close:SetPoint("TOPRIGHT");panel.SuiteCloseButton=close
        local options={{"enabled","Remember encounters"},{"tooltip","Show previous sighting"},{"players","Remember players"},{"npcs","Remember innkeepers"},{"showLevel","Show saved level"},{"showLocation","Show saved location"}}
        for i,entry in ipairs(options) do
            local key,label=entry[1],entry[2];local b=CreateFrame("CheckButton",nil,panel,"UICheckButtonTemplate");b:SetPoint("TOPLEFT",18+((i-1)%2)*294,-45-math.floor((i-1)/2)*30)
            local text=b:CreateFontString(nil,"OVERLAY","GameFontHighlight");text:SetPoint("LEFT",b,"RIGHT",0,0);text:SetText(label)
            b:SetScript("OnClick",function(self) NS.DB[key]=self:GetChecked();NS.ClearHover();NS.Open() end);checks[key]=b
        end
        for i,entry in ipairs({{"all","All"},{"player","Players"},{"npc","Innkeepers"}}) do
            local value,label=entry[1],entry[2];local b=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate");b:SetSize(82,23);b:SetPoint("TOPLEFT",22+(i-1)*90,-148);b:SetText(label);b:SetScript("OnClick",function() filter=value;cursor=nil;pages={};NS.Open() end)
        end
        local daily=CreateFrame("CheckButton",nil,panel,"UICheckButtonTemplate");daily:SetPoint("TOPLEFT",310,-145)
        local dailyLabel=daily:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");dailyLabel:SetPoint("LEFT",daily,"RIGHT",0,0);dailyLabel:SetText("Remember shared activities")
        daily:SetScript("OnClick",function(self) NS.DB.activitiesEnabled=self:GetChecked();NS.ClearHover();NS.Open() end);checks.activitiesEnabled=daily
        local quests=CreateFrame("CheckButton",nil,panel,"UICheckButtonTemplate");quests:SetPoint("TOPLEFT",306,-175)
        local qlabel=quests:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");qlabel:SetPoint("LEFT",quests,"RIGHT",0,0);qlabel:SetText("Confirm quests")
        quests:SetScript("OnClick",function(self) NS.DB.questConfirm=self:GetChecked() end);checks.questConfirm=quests
        quests:SetScript("OnEnter",function(self) GameTooltip:SetOwner(self,"ANCHOR_TOP");GameTooltip:SetText("Confirm quests together");GameTooltip:AddLine("Exchange quest IDs with group members using Smyrna. Records a shared completion only when both turn in the same quest within 10 minutes.",1,1,1,true);GameTooltip:Show() end)
        quests:SetScript("OnLeave",function() GameTooltip:Hide() end)
        limitText=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");limitText:SetPoint("TOPLEFT",24,-191)
        backButton=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate");backButton:SetSize(64,23);backButton:SetPoint("TOPLEFT",430,-182);backButton:SetText("Back")
        backButton:SetScript("OnClick",function() if #pages>0 then cursor=table.remove(pages);if cursor==false then cursor=nil end;NS.Open() end end)
        nextButton=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate");nextButton:SetSize(64,23);nextButton:SetPoint("TOPLEFT",500,-182);nextButton:SetText("Next")
        nextButton:SetScript("OnClick",function() if hasMore then pages[#pages+1]=cursor or false;cursor=following;NS.Open() end end)
        local scroll=CreateFrame("ScrollFrame",nil,panel,"UIPanelScrollFrameTemplate");scroll:SetPoint("TOPLEFT",22,-225);scroll:SetPoint("BOTTOMRIGHT",-42,40)
        list=CreateFrame("EditBox",nil,scroll);list:SetMultiLine(true);list:SetAutoFocus(false);list:SetFontObject(ChatFontNormal);list:SetWidth(448);list:SetHeight(220);list:SetScript("OnEscapePressed",function(self) self:ClearFocus() end);scroll:SetScrollChild(list)
        measure=panel:CreateFontString(nil,"BACKGROUND","ChatFontNormal");measure:SetWidth(448);measure:Hide()
        local note=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");note:SetPoint("BOTTOMLEFT",22,16);note:SetText("First seen is always kept. Shared activities include their dates.")
        UISpecialFrames[#UISpecialFrames+1]="SmyrnaRemembrancePanel"
    end
    for key,b in pairs(checks) do b:SetChecked(NS.DB[key]) end
    local rows;rows,following,hasMore=NS.Page(filter,cursor)
    backButton:SetEnabled(#pages>0);nextButton:SetEnabled(hasMore)
    limitText:SetText(Suite.UIText(NS.Count.." remembered","heading")..Suite.UIText("  /  Page "..(#pages+1),"muted"))
    local text={};local offset=0
    local _,lineHeight=list:GetFont();lineHeight=type(lineHeight)=="number" and lineHeight or 12
    for i,row in ipairs(rows) do
        local heading=Suite.UIText(row.name,"heading")..Suite.UIText(" - "..NS.Format(row.last),"detail")
        local detail=NS.Description(row)
        local block=heading.."\n  "..Suite.UIText(detail,"muted")
        text[#text+1]=block
        local button=historyButtons[i]
        if not button then
            button=CreateFrame("Button",nil,list,"UIPanelButtonTemplate");button:SetSize(70,22);historyButtons[i]=button
            button:SetScript("OnClick",function(self) if self.personKey then NS.OpenHistory(self.personKey) end end)
        end
        button.personKey=row.key;button:SetText(row.kind=="player" and "History" or "Details");button:ClearAllPoints();button:SetPoint("TOPLEFT",list,"TOPLEFT",458,-offset);button:Show()
        measure:SetText(block);offset=offset+measure:GetStringHeight()+lineHeight
    end
    for i=#rows+1,#historyButtons do historyButtons[i]:Hide() end
    if #text==0 then text[1]=hasMore and "No matches on this page. Choose Next to continue." or "No encounters here. Hover players or talk to an innkeeper to get started." end
    local body=table.concat(text,"\n\n");list:SetText(body);measure:SetText(body);list:SetHeight(math.max(200,measure:GetStringHeight()+16));measure:SetText("");panel:Show()
    return panel
end
function NS.ConfigureIcon()
end
end chunk(name,Module) end

-- Internal module source: Main.lua
do local function chunk(...)
local addon,NS=...
local f=CreateFrame("Frame");f:RegisterEvent("PLAYER_LOGIN")
local drawn
local function Tooltip(tip)
    if tip~=GameTooltip or not NS.DB.enabled or not NS.DB.tooltip then return end
    if tip.IsForbidden and tip:IsForbidden() then return end
    local _,unit=tip:GetUnit()
    local previous,key,info=NS.Observe(unit)
    if not key or drawn==key then return end;drawn=key
    local row=NS.ReadRecord(key,NS.DB.records[key])
    if row then tip:AddLine("First seen: "..NS.FirstSeenText(row.first),1,.82,.42,true) end
    if previous and row and not NS.SameDay(row.first,previous) then tip:AddLine("Last seen: "..NS.Format(previous),.55,.8,1,true) end
    if row and row.kind=="player" then tip:AddLine("Ctrl + left-click to expand",.65,.75,.85,true) end
end
NS.AddTooltip=Tooltip
function NS.PlayerClick(unit,button)
    if button~="LeftButton" or not IsControlKeyDown or not IsControlKeyDown() then return false end
    if not NS.DB or not NS.DB.enabled or not NS.DB.players or not NS.Public(unit) or type(unit)~="string" then return false end
    local player=UnitIsPlayer and UnitIsPlayer(unit)
    if not NS.Public(player) or not player then return false end
    if UnitIsUnit and UnitIsUnit(unit,"player") then return false end
    local guid=UnitGUID(unit)
    if not NS.Public(guid) or type(guid)~="string" or not guid:match("^Player%-%d+%-%x+$") then return false end
    local key="P:"..guid
    if not NS.DB.records[key] then NS.Observe(unit) end
    if not NS.DB.records[key] then return false end
    NS.OpenHistory(key);return true
end
SLASH_SMYRNAREMEMBRANCE1="/sr";SLASH_SMYRNAREMEMBRANCE2="/smyrnaremembrance"
SlashCmdList.SMYRNAREMEMBRANCE=function() if NS.DB then NS.Open() end end
f:SetScript("OnEvent",function(self,event,name)
    if event=="PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        local load=(C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
        if not SmyrnaRemembranceStore and (not load or not load("SmyrnaRemembranceDB")) then return end
        NS.Init();NS.ConfigureIcon();Suite.Loaded[addon]=true
        pcall(self.RegisterEvent,self,"GLOBAL_MOUSE_DOWN")
        if TargetFrame then TargetFrame:HookScript("OnClick",function(_,button) NS.PlayerClick("target",button) end) end
        self:RegisterEvent("UPDATE_MOUSEOVER_UNIT");self:RegisterEvent("PLAYER_LEAVING_WORLD");self:RegisterEvent("GOSSIP_SHOW")
        if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit,Tooltip)
        elseif GameTooltip.HasScript and GameTooltip:HasScript("OnTooltipSetUnit") then GameTooltip:HookScript("OnTooltipSetUnit",Tooltip) end
        GameTooltip:HookScript("OnTooltipCleared",function() drawn=nil end)
    elseif event=="GLOBAL_MOUSE_DOWN" then
        if name=="LeftButton" and IsControlKeyDown and IsControlKeyDown() then
            local _,unit=GameTooltip:GetUnit()
            if NS.Public(unit) and type(unit)=="string" and GameTooltip:IsShown() then NS.PlayerClick(unit,name) else NS.PlayerClick("mouseover",name) end
        end
    elseif event=="GOSSIP_SHOW" then NS.LearnInnkeeper()
    elseif event=="PLAYER_LEAVING_WORLD" then NS.ClearHover();drawn=nil
    elseif event=="UPDATE_MOUSEOVER_UNIT" then
        local guid=UnitGUID("mouseover")
        if not NS.Public(guid) or not guid then NS.ClearHover();drawn=nil else NS.Observe("mouseover") end
    end
end)

end chunk(name,Module) end

-- Set loaded only after the optional history store is available.
Module.Perf=function() if Suite.Memory then Suite.Memory() end end


