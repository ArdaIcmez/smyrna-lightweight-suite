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
local cachedDayStamp,cachedDayNum=0,0
local function TodayCalendarDay(now)
    local stamp=math.floor(now/1000)
    if stamp-cachedDayStamp>=60 or cachedDayNum==0 then
        cachedDayStamp=stamp;cachedDayNum=CalendarDay(now)
    end
    return cachedDayNum
end
function NS.FirstSeenText(ms,now)
    if not Number(ms,0,10^15) then return "Unknown" end
    local today=now and CalendarDay(now) or TodayCalendarDay(NS.Now())
    local days=today-CalendarDay(ms)
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
local RECORD_CAP=3000
function NS.EnforceCap()
    if not NS.DB or (NS.Count or 0)<=RECORD_CAP then return end
    local acts=NS.DB.activities
    local oldestKey,oldestStamp,anyKey,anyStamp
    for k,rec in pairs(NS.DB.records) do
        if type(k)=="string" and k:sub(1,2)=="P:" then
            local _,stamp=UnpackRecord(rec)
            stamp=stamp or 0
            if not (acts and acts[k]) then
                if not oldestKey or stamp<oldestStamp then oldestKey,oldestStamp=k,stamp end
            end
            if not anyKey or stamp<anyStamp then anyKey,anyStamp=k,stamp end
        end
    end
    local victim=oldestKey or anyKey
    if victim then
        NS.DB.records[victim]=nil
        if NS.DB.histories then NS.DB.histories[victim]=nil end
        if acts then acts[victim]=nil end
        NS.Count=math.max(0,(NS.Count or 1)-1)
    end
end
function NS.PruneIdlePlayers(maxAgeDays)
    if not NS.DB then return 0 end
    local cutoff=NS.Now()-(maxAgeDays or 90)*86400*1000
    local acts=NS.DB.activities
    local removed=0
    for k,rec in pairs(NS.DB.records) do
        if type(k)=="string" and k:sub(1,2)=="P:" and not (acts and acts[k]) then
            local _,stamp=UnpackRecord(rec)
            if stamp and stamp<cutoff then
                NS.DB.records[k]=nil
                if NS.DB.histories then NS.DB.histories[k]=nil end
                NS.Count=math.max(0,(NS.Count or 1)-1)
                removed=removed+1
            end
        end
    end
    if removed>0 then NS.Revision=(NS.Revision or 0)+1 end
    return removed
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
    if not row and player then NS.EnforceCap() end
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
    if not NS.DB then return {},nil,false end
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
local panel,scroll,canvas,statusLabel,searchBox
local historyPanel,historyList,historySummary,historyMeasure,historyScroll
local cards,tagBtns,checks={},{},{}
local filter="recent"
local searchQuery=""
local searchGen=0
local summaryCache,summaryRev={},-1
local RECENT_LIMIT=15
local RANK_LIMIT=20

local EMPTY_SUMMARY={dgCount=0,bgCount=0,questCount=0,bossCount=0,total=0,dungeons={},bgs={}}
local function EmptySummary() return EMPTY_SUMMARY end

local function ActivitySummary(key)
    local rev=NS.Revision or 0
    if rev~=summaryRev then wipe(summaryCache); summaryRev=rev end
    local cached=summaryCache[key]
    if cached then return cached end
    local res=(NS.Activities and NS.Activities.Summary) and NS.Activities.Summary(key) or EMPTY_SUMMARY
    summaryCache[key]=res
    return res
end

local function NamedList(items,maxShow)
    if NS.Activities and NS.Activities.FormatNamedList then return NS.Activities.FormatNamedList(items,maxShow) end
    return ""
end

function NS.OpenHistory(key)
    local row=NS.DB and NS.ReadRecord(key,NS.DB.records[key])
    local entries,activityCount={},0
    if row and NS.Activities then entries,activityCount=NS.Activities.Lines(key) end
    activityCount=activityCount or 0
    if not row then if historyPanel then historyPanel:Hide() end;return end
    if not historyPanel then
        historyPanel=CreateFrame("Frame","SmyrnaRemembranceHistory",UIParent,"BackdropTemplate");historyPanel:SetSize(440,200);historyPanel:SetPoint("CENTER");historyPanel:SetFrameStrata("FULLSCREEN_DIALOG");historyPanel:SetFrameLevel(100);historyPanel:SetClampedToScreen(true);historyPanel:EnableMouse(true)
        Suite.StylePanel(historyPanel,true)
        local close=Suite.CloseButton(historyPanel);close:SetScript("OnClick",function() historyPanel:Hide() end)
        historySummary=historyPanel:CreateFontString(nil,"OVERLAY","GameFontHighlight");historySummary:SetPoint("TOPLEFT",18,-16);historySummary:SetWidth(460);historySummary:SetJustifyH("LEFT")
        historyPanel.rule=Suite.HorizontalRule(historyPanel,18,-76,404)
        historyScroll=CreateFrame("ScrollFrame",nil,historyPanel,"UIPanelScrollFrameTemplate");local s=historyScroll;s:SetPoint("TOPLEFT",18,-92);s:SetPoint("BOTTOMRIGHT",-36,18)
        s:EnableMouseWheel(true)
        s:SetScript("OnMouseWheel",function(self,delta)
            local cur,max=self:GetVerticalScroll(),self:GetVerticalScrollRange()
            if type(cur)=="number" and type(max)=="number" then self:SetVerticalScroll(math.max(0,math.min(max,cur-delta*36))) end
        end)
        historyList=CreateFrame("EditBox",nil,s);historyList:SetMultiLine(true);historyList:SetAutoFocus(false);historyList:SetFontObject(ChatFontNormal);historyList:SetWidth(460);historyList:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
        historyList:SetScript("OnTextChanged",function(self,userInput) if userInput and self.readonlyText then self:SetText(self.readonlyText) end end)
        s:SetScrollChild(historyList)
        historyMeasure=historyPanel:CreateFontString(nil,"BACKGROUND","ChatFontNormal");historyMeasure:SetWidth(460);historyMeasure:Hide()
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
    local width=math.max(340,math.min(560,widest+68))
    historySummary:SetWidth(width-62);historyList:SetWidth(width-58);historyMeasure:SetWidth(width-58)
    historyList.readonlyText=text
    historyList:SetText(text);historyMeasure:SetText(text)
    local bodyHeight=historyMeasure:GetStringHeight()+14
    local top=18+historySummary:GetStringHeight()+16
    if historyPanel.rule then
        historyPanel.rule:ClearAllPoints();historyPanel.rule:SetPoint("TOPLEFT",18,-(top-8));historyPanel.rule:SetWidth(math.max(120,width-36))
        historyPanel.rule:SetShown(#entries>0)
    end
    historyScroll:ClearAllPoints();historyScroll:SetPoint("TOPLEFT",18,-top);historyScroll:SetPoint("BOTTOMRIGHT",-36,18)
    local available=UIParent and UIParent.GetHeight and UIParent:GetHeight()
    local maximum=type(available)=="number" and available>300 and math.min(560,available-80) or 560
    historyScroll:SetShown(#entries>0)
    historyPanel:SetSize(width,#entries>0 and math.min(maximum,math.max(100,top+bodyHeight+20)) or (top+8))
    historyList:SetHeight(bodyHeight);historyMeasure:SetText("");historyScroll:SetVerticalScroll(0);historyScroll:UpdateScrollChildRect()
    historyPanel:Show();return historyPanel
end

local function MakePlayerCard(i)
    local card=CreateFrame("Button",nil,canvas,"BackdropTemplate")
    card:SetSize(748,58)
    Suite.StyleCard(card,.080,.092,.126)
    card:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    local hl=card:GetHighlightTexture(); if hl then hl:SetVertexColor(.95,.78,.36,.10) end
    card.rank=card:CreateFontString(nil,"OVERLAY","GameFontNormal")
    card.rank:SetPoint("TOPLEFT",10,-8); card.rank:SetWidth(30); card.rank:SetJustifyH("LEFT")
    card.name=card:CreateFontString(nil,"OVERLAY","GameFontNormal")
    card.name:SetPoint("TOPLEFT",42,-8); card.name:SetWidth(270); card.name:SetJustifyH("LEFT"); card.name:SetMaxLines(1)
    card.counts=card:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    card.counts:SetPoint("TOPLEFT",318,-9); card.counts:SetWidth(250); card.counts:SetJustifyH("LEFT"); card.counts:SetMaxLines(1)
    card.seen=card:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    card.seen:SetPoint("TOPRIGHT",-86,-9); card.seen:SetJustifyH("RIGHT"); card.seen:SetTextColor(.70,.76,.84)
    card.meta=card:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    card.meta:SetPoint("TOPLEFT",42,-25); card.meta:SetWidth(618); card.meta:SetJustifyH("LEFT"); card.meta:SetMaxLines(1); card.meta:SetTextColor(.68,.74,.82)
    card.detail=card:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    card.detail:SetPoint("TOPLEFT",42,-40); card.detail:SetWidth(618); card.detail:SetJustifyH("LEFT"); card.detail:SetMaxLines(2); card.detail:SetTextColor(.82,.88,.96)
    card.btn=CreateFrame("Button",nil,card,"UIPanelButtonTemplate")
    card.btn:SetSize(68,22); card.btn:SetPoint("TOPRIGHT",-10,-8); card.btn:SetText("History"); Suite.StyleButton(card.btn)
    card.btn:SetScript("OnClick",function(self)
        local key=self:GetParent().personKey
        if key then NS.OpenHistory(key) end
    end)
    card:SetScript("OnClick",function(self)
        if self.personKey then NS.OpenHistory(self.personKey) end
    end)
    cards[i]=card
    return card
end

local function CollectEntries()
    if not NS.DB then return {} end
    local q=string.lower((searchQuery or ""):gsub("^%s+",""):gsub("%s+$",""))
    local source=(filter=="npc") and NS.InnkeeperRecords or NS.DB.records
    local list={}
    for key,packed in pairs(source) do
        local isPlayer=type(key)=="string" and key:sub(1,2)=="P:"
        local want=(filter=="npc" and not isPlayer) or (filter~="npc" and isPlayer)
        if want then
            local row=NS.ReadRecord(key,packed)
            if row then
                local sum=isPlayer and ActivitySummary(key) or EmptySummary()
                local pass=true
                if filter=="dungeon" and sum.dgCount<=0 then pass=false
                elseif filter=="bg" and sum.bgCount<=0 then pass=false
                elseif filter=="quest" and sum.questCount<=0 then pass=false end
                if pass and q~="" then
                    local dgTxt=NamedList(sum.dungeons,12)
                    local bgTxt=NamedList(sum.bgs,12)
                    local hay=string.lower((row.name or "").." "..(row.location or "").." "..dgTxt.." "..bgTxt)
                    pass=hay:find(q,1,true)~=nil
                end
                if pass then
                    list[#list+1]={row=row,sum=sum}
                end
            end
        end
    end
    table.sort(list,function(a,b)
        if filter=="dungeon" then
            if a.sum.dgCount~=b.sum.dgCount then return a.sum.dgCount>b.sum.dgCount end
        elseif filter=="bg" then
            if a.sum.bgCount~=b.sum.bgCount then return a.sum.bgCount>b.sum.bgCount end
        elseif filter=="quest" then
            if a.sum.questCount~=b.sum.questCount then return a.sum.questCount>b.sum.questCount end
        end
        if (a.row.last or 0)~=(b.row.last or 0) then return (a.row.last or 0)>(b.row.last or 0) end
        return (a.row.name or "")<(b.row.name or "")
    end)
    local cap=(filter=="recent" and q=="") and RECENT_LIMIT or RANK_LIMIT
    while #list>cap do list[#list]=nil end
    return list
end

local function RefreshUI()
    if not panel or not panel:IsShown() or not NS.DB then return end
    for key,b in pairs(checks) do b:SetChecked(NS.DB[key] and true or false) end
    for k,b in pairs(tagBtns) do Suite.SetButtonSelected(b,filter==k) end

    local entries=CollectEntries()
    local isRanked=(filter=="dungeon" or filter=="bg" or filter=="quest")
    local modeTitle=(filter=="recent" and ("Last "..RECENT_LIMIT.." recently met players"))
        or (filter=="dungeon" and "Ranked by dungeons run together")
        or (filter=="bg" and "Ranked by battlegrounds fought together")
        or (filter=="quest" and "Ranked by quests completed together")
        or "Remembered innkeepers"
    statusLabel:SetText(Suite.UIText(NS.Count.." total remembered","heading")..Suite.UIText("  ·  "..modeTitle.."  ("..#entries.." shown)","muted"))

    local y=0
    for i=1,math.max(#entries,#cards) do
        local item=entries[i]
        local card=cards[i] or MakePlayerCard(i)
        if item then
            local row,sum=item.row,item.sum
            card.personKey=row.key
            card:ClearAllPoints(); card:SetPoint("TOPLEFT",0,-y)
            if isRanked then
                card.rank:SetText("#"..i)
                if i==1 then card.rank:SetTextColor(1,.84,.28)
                elseif i==2 then card.rank:SetTextColor(.82,.86,.92)
                elseif i==3 then card.rank:SetTextColor(.86,.56,.32)
                else card.rank:SetTextColor(.62,.68,.78) end
                card.name:ClearAllPoints(); card.name:SetPoint("TOPLEFT",42,-8)
            else
                card.rank:SetText("")
                card.name:ClearAllPoints(); card.name:SetPoint("TOPLEFT",12,-8)
            end
            card.name:SetText(row.name or "Unknown"); card.name:SetTextColor(1,.90,.62)
            card.seen:SetText(NS.Format(row.last))

            local pills={}
            if row.kind=="player" then
                if sum.dgCount>0 then pills[#pills+1]="|cff7cc4ffDG: "..sum.dgCount.."|r" end
                if sum.bgCount>0 then pills[#pills+1]="|cffff7b6bBG: "..sum.bgCount.."|r" end
                if sum.questCount>0 then pills[#pills+1]="|cff78d49bQuests: "..sum.questCount.."|r" end
                if #pills==0 then pills[1]="|cff6f7887No shared runs yet|r" end
            else
                pills[1]="|cff9aa4b2Innkeeper|r"
            end
            card.counts:SetText(table.concat(pills,"  ·  "))

            local desc=NS.Description(row)
            local xOff=isRanked and 42 or 12
            card.meta:ClearAllPoints(); card.meta:SetPoint("TOPLEFT",xOff,-25); card.meta:SetWidth(654-xOff)
            card.meta:SetText(desc~="" and desc or "First met: "..NS.FirstSeenText(row.first))

            -- List actual Dungeon & BG names; for Quests show count only (never quest names!)
            local detailLines={}
            local dgNames=NamedList(sum.dungeons,5)
            local bgNames=NamedList(sum.bgs,5)
            if dgNames~="" then detailLines[#detailLines+1]="|cff7cc4ffDungeons:|r "..dgNames end
            if bgNames~="" then detailLines[#detailLines+1]="|cffff8878BGs:|r "..bgNames end
            local hasDetail=#detailLines>0
            card.detail:ClearAllPoints(); card.detail:SetPoint("TOPLEFT",xOff,-40); card.detail:SetWidth(724-xOff)
            if hasDetail then
                card.detail:SetText(table.concat(detailLines,"\n"))
                card.detail:Show()
            else
                card.detail:SetText("")
                card.detail:Hide()
            end
            local cardH=hasDetail and (#detailLines==2 and 70 or 58) or 46
            card:SetHeight(cardH)
            card.btn:SetText(row.kind=="player" and "History" or "Details")

            if filter=="dungeon" then Suite.SetCornerGlow(card,.38,.74,1,i<=3 and .18 or .08)
            elseif filter=="bg" then Suite.SetCornerGlow(card,1,.42,.36,i<=3 and .18 or .08)
            elseif filter=="quest" then Suite.SetCornerGlow(card,.42,.86,.56,i<=3 and .18 or .08)
            elseif sum.total>0 then Suite.SetCornerGlow(card,.96,.78,.36,.12)
            else Suite.SetCornerGlow(card,.50,.56,.68,.04) end

            card:Show()
            y=y+cardH+6
        else
            card.personKey=nil; card:Hide()
        end
    end

    if #entries==0 then
        local emptyMsg=(filter=="dungeon" and "No shared dungeon runs recorded yet. Enter a dungeon in a party to track & rank players.")
            or (filter=="bg" and "No shared battlegrounds recorded yet. Enter a battleground to track & rank teammates.")
            or (filter=="quest" and "No shared quests recorded yet. Turn in quests with groupmates who use Smyrna Suite.")
            or (filter=="npc" and "No innkeepers remembered yet. Talk to an innkeeper to record them.")
            or "No recent encounters yet. Hover over players or group up to start remembering."
        statusLabel:SetText(emptyMsg)
    end
    canvas:SetHeight(math.max(290,y+8))
    scroll:UpdateScrollChildRect()
end

local disabledPanel
function NS.Open()
    if not NS.DB then
        if not disabledPanel then
            disabledPanel=CreateFrame("Frame","SmyrnaRemembranceDisabled",UIParent,"BackdropTemplate");disabledPanel:SetSize(620,180);disabledPanel:SetPoint("CENTER");disabledPanel:SetFrameStrata("DIALOG")
            Suite.StylePanel(disabledPanel,true)
            disabledPanel.SuiteCloseButton=Suite.CloseButton(disabledPanel)
            local text=disabledPanel:CreateFontString(nil,"OVERLAY","GameFontHighlight");text:SetPoint("TOPLEFT",22,-26);text:SetWidth(560);text:SetJustifyH("LEFT")
            text:SetText("Remembrance history storage is disabled.\n\nEnable Smyrna Remembrance DB in WoW AddOns and reload to use Remembrance.")
        end
        disabledPanel:Show();return disabledPanel
    end
    if not panel then
        cards={}; tagBtns={}; checks={}
        panel=CreateFrame("Frame","SmyrnaRemembrancePanel",UIParent,"BackdropTemplate");panel:SetSize(800,586);panel:SetPoint("CENTER");panel:SetFrameStrata("DIALOG");panel:SetClampedToScreen(true)
        Suite.StylePanel(panel,true)
        local close=Suite.CloseButton(panel);panel.SuiteCloseButton=close
        local title=panel:CreateFontString(nil,"OVERLAY","GameFontNormalLarge");title:SetPoint("TOPLEFT",16,-14);title:SetText("Smyrna Remembrance");title:SetTextColor(1,.86,.48)
        local sub=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");sub:SetPoint("TOPLEFT",16,-36);sub:SetText("Recent players met, plus Dungeon, Battleground & Quest rankings with players you've adventured with.");sub:SetTextColor(.70,.75,.84)

        local optCard=CreateFrame("Frame",nil,panel,"BackdropTemplate");optCard:SetSize(768,94);optCard:SetPoint("TOPLEFT",16,-58);Suite.StyleCard(optCard,.076,.088,.120)
        Suite.OptionSection(optCard,"Options",12,-10,744)
        local options={
            {"enabled","Encounters","Record players and innkeepers you meet across Azeroth.",10,-28},
            {"tooltip","Tooltips","Show First seen and Last seen dates when hovering remembered units.",198,-28},
            {"players","Players","Remember other players you hover, target, or group with.",386,-28},
            {"npcs","Innkeepers","Remember innkeepers you speak with when binding your hearthstone.",574,-28},
            {"showLevel","Level","Display each player's last seen level on their Remembrance card.",10,-58},
            {"showLocation","Location","Display the zone where you last crossed paths.",198,-58},
            {"activitiesEnabled","Dungeons & BGs","Automatically track shared dungeons, raids, and battlegrounds with party/raid members.",386,-58},
            {"questConfirm","Group quests","Increment a shared quest count when groupmates with Smyrna turn in the same quest within 10 minutes.",574,-58},
        }
        for _,entry in ipairs(options) do
            local key,label,tipBody,x,y=entry[1],entry[2],entry[3],entry[4],entry[5]
            local b=CreateFrame("CheckButton",nil,optCard,"UICheckButtonTemplate");b:SetPoint("TOPLEFT",x,y)
            local text=b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");text:SetPoint("LEFT",b,"RIGHT",2,0);text:SetText(label)
            b:SetScript("OnClick",function(self) NS.DB[key]=self:GetChecked() and true or false;NS.ClearHover();RefreshUI() end)
            Suite.AttachTooltip(b,label,tipBody,text)
            checks[key]=b
        end

        Suite.OptionSection(panel,"Recent & Activity Rankings",16,-162,768)
        local tx=16
        for _,entry in ipairs({{"recent","Recent (15)",92},{"dungeon","Dungeons",86},{"bg","Battlegrounds",104},{"quest","Quests",74},{"npc","Innkeepers",88}}) do
            local k,lbl,w=entry[1],entry[2],entry[3]
            local b=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate");b:SetSize(w,23);b:SetPoint("TOPLEFT",tx,-180);b:SetText(lbl);Suite.StyleButton(b)
            b:SetScript("OnClick",function() filter=k;RefreshUI() end)
            tagBtns[k]=b;tx=tx+w+6
        end

        searchBox=CreateFrame("EditBox",nil,panel,"InputBoxTemplate")
        searchBox:SetSize(188,22);searchBox:SetPoint("TOPRIGHT",-18,-180);searchBox:SetAutoFocus(false)
        searchBox:SetScript("OnTextChanged",function(self)
            searchQuery=self:GetText() or ""
            searchGen=searchGen+1; local tok=searchGen
            if C_Timer and C_Timer.After then
                C_Timer.After(.15,function() if tok==searchGen and panel and panel:IsShown() then RefreshUI() end end)
            else RefreshUI() end
        end)
        searchBox:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
        local sLbl=panel:CreateFontString(nil,"OVERLAY","GameFontNormalSmall");sLbl:SetPoint("RIGHT",searchBox,"LEFT",-8,0);sLbl:SetText("Search:");sLbl:SetTextColor(.93,.77,.40)
        local trimBtn=CreateFrame("Button",nil,panel,"UIPanelButtonTemplate");trimBtn:SetSize(108,22);trimBtn:SetPoint("TOPRIGHT",-46,-14);trimBtn:SetText("Prune 90d+ idle");Suite.StyleButton(trimBtn)
        local trimArmed=0
        trimBtn:SetScript("OnClick",function(self)
            local now=GetTime()
            if now<trimArmed then
                trimArmed=0; self:SetText("Prune 90d+ idle")
                local n=NS.PruneIdlePlayers(90)
                if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffdfb66bSmyrna Remembrance:|r Pruned "..n.." idle player records (shared-activity records kept).") end
                RefreshUI()
            else
                trimArmed=now+6; self:SetText("Confirm prune?")
                if C_Timer and C_Timer.After then C_Timer.After(6.1,function() if GetTime()>=trimArmed then trimBtn:SetText("Prune 90d+ idle") end end) end
            end
        end)
        Suite.AttachTooltip(trimBtn,"Prune 90d+ idle","Click twice to remove players not seen for 90+ days who have no shared dungeon, BG, or quest history.")

        statusLabel=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");statusLabel:SetPoint("TOPLEFT",18,-210);statusLabel:SetWidth(764);statusLabel:SetJustifyH("LEFT")

        scroll=CreateFrame("ScrollFrame",nil,panel,"UIPanelScrollFrameTemplate");scroll:SetPoint("TOPLEFT",16,-230);scroll:SetSize(754,340)
        canvas=CreateFrame("Frame",nil,scroll);canvas:SetSize(748,340);scroll:SetScrollChild(canvas)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel",function(self,delta)
            local cur,max=self:GetVerticalScroll(),self:GetVerticalScrollRange()
            if type(cur)=="number" and type(max)=="number" then self:SetVerticalScroll(math.max(0,math.min(max,cur-delta*48))) end
        end)

        panel:SetScript("OnShow",RefreshUI)
        UISpecialFrames[#UISpecialFrames+1]="SmyrnaRemembrancePanel"
    end
    panel:Show()
    RefreshUI()
    return panel
end
function NS.ConfigureIcon()
end
end chunk(name,Module) end

-- Internal module source: Main.lua
do local function chunk(...)
local addon,NS=...
local f=CreateFrame("Frame");f:RegisterEvent("PLAYER_LOGIN")
local modActive=true
local drawn
local function Tooltip(tip)
    if not modActive or tip~=GameTooltip or not NS.DB or not NS.DB.enabled or not NS.DB.tooltip then return end
    if tip.IsForbidden and tip:IsForbidden() then return end
    if Suite.IsLootInteraction and Suite.IsLootInteraction(tip.GetOwner and tip:GetOwner()) then return end
    local _,unit=tip:GetUnit()
    local previous,key,info=NS.Observe(unit)
    if not key or drawn==key then return end;drawn=key
    local row=NS.ReadRecord(key,NS.DB.records[key])
    if row then tip:AddLine("First seen: "..NS.FirstSeenText(row.first),1,.82,.42,true) end
    if previous and row and not NS.SameDay(row.first,previous) then tip:AddLine("Last seen: "..NS.Format(previous),.55,.8,1,true) end
    if row and row.kind=="player" then Suite.OptionalHint(tip,"Ctrl + left-click to expand") end
end
NS.AddTooltip=Tooltip
function NS.PlayerClick(unit,button)
    if not NS.Public(button) or button~="LeftButton" or not IsControlKeyDown or not IsControlKeyDown() then return false end
    if Suite.IsLootInteraction and Suite.IsLootInteraction() then return false end
    if not NS.DB or not NS.DB.enabled or not NS.DB.players or not NS.Public(unit) or type(unit)~="string" then return false end
    local player=UnitIsPlayer and UnitIsPlayer(unit)
    if not NS.Public(player) or not player then return false end
    if UnitIsUnit then local same=UnitIsUnit(unit,"player");if not NS.Public(same) or same then return false end end
    local guid=UnitGUID(unit)
    if not NS.Public(guid) or type(guid)~="string" or not guid:match("^Player%-%d+%-%x+$") then return false end
    local key="P:"..guid
    if not NS.DB.records[key] then NS.Observe(unit) end
    if not NS.DB.records[key] then return false end
    NS.OpenHistory(key);return true
end
SLASH_SMYRNAREMEMBRANCE1="/sr";SLASH_SMYRNAREMEMBRANCE2="/smyrnaremembrance"
SlashCmdList.SMYRNAREMEMBRANCE=function() if NS.DB then NS.Open() end end
local initialized=false
local function SyncRemembranceEvents(on)
    if on then
        pcall(f.RegisterEvent,f,"GLOBAL_MOUSE_DOWN")
        f:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
        f:RegisterEvent("PLAYER_LEAVING_WORLD")
        f:RegisterEvent("GOSSIP_SHOW")
    else
        f:UnregisterEvent("GLOBAL_MOUSE_DOWN")
        f:UnregisterEvent("UPDATE_MOUSEOVER_UNIT")
        f:UnregisterEvent("PLAYER_LEAVING_WORLD")
        f:UnregisterEvent("GOSSIP_SHOW")
        f:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
end
function NS.SetEnabled(on)
    modActive=on and true or false
    if NS.DB then NS.DB.enabled=modActive end
    if initialized then SyncRemembranceEvents(modActive) end
    if not modActive then
        if NS.ClearHover then NS.ClearHover() end
        drawn=nil
        for _,fn in ipairs({"SmyrnaRemembranceWindow","SmyrnaRemembranceHistory"}) do
            local w=_G[fn]; if w and w.Hide then w:Hide() end
        end
    end
end
local function TryInit(self)
    if initialized then return end
    if not SmyrnaRemembranceStore then
        if InCombatLockdown and InCombatLockdown() then self:RegisterEvent("PLAYER_REGEN_ENABLED"); return end
        local load=(C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
        if not load or not load("SmyrnaRemembranceDB") then return end
    end
    if not (SmyrnaRemembranceStore and SmyrnaRemembranceStore.Open) then return end
    initialized=true
    NS.Init();NS.ConfigureIcon();Suite.Loaded[addon]=true
    SyncRemembranceEvents(modActive)
    if TargetFrame then TargetFrame:HookScript("OnClick",function(_,button) if modActive then NS.PlayerClick("target",button) end end) end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit,Tooltip)
    elseif GameTooltip.HasScript and GameTooltip:HasScript("OnTooltipSetUnit") then GameTooltip:HookScript("OnTooltipSetUnit",Tooltip) end
    GameTooltip:HookScript("OnTooltipCleared",function() drawn=nil end)
    GameTooltip:HookScript("OnHide",function() drawn=nil end)
end
f:SetScript("OnEvent",function(self,event,arg1)
    if event=="PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        TryInit(self)
    elseif event=="PLAYER_REGEN_ENABLED" then
        self:UnregisterEvent("PLAYER_REGEN_ENABLED")
        TryInit(self)
    elseif not modActive then
        return
    elseif event=="GLOBAL_MOUSE_DOWN" then
        if NS.Public(arg1) and arg1=="LeftButton" and IsControlKeyDown and IsControlKeyDown() then
            local unit
            if GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) and GameTooltip:IsShown() then
                _,unit=GameTooltip:GetUnit()
            end
            if NS.Public(unit) and type(unit)=="string" then NS.PlayerClick(unit,arg1) else NS.PlayerClick("mouseover",arg1) end
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


