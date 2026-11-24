local _,Suite=...
local name="SmyrnaBestiary"
Suite.Versions[name]="0.2.1"
if Suite.Config.features[name]==false then return end
local Module={}
Suite.Modules[name]=Module
-- Internal module source: Core.lua
do local function chunk(...)
local _,NS=...
local C={}
NS.Core=C
NS.Raw,NS.Items,NS.Loaded,NS.Missing={},{},{},{}
NS.Zones,NS.NPCPack={},{}
C.CAP=1000; C.ITEMCAP=64; C.CELLCAP=16; C.RECENT=1024
function C.Public(v) return not (issecretvalue and issecretvalue(v)) end
function C.Number(v,a,b) return C.Public(v) and type(v)=="number" and v==v and v%1==0 and v>=a and v<=b end
function C.Now() return GetServerTime and GetServerTime() or time() end
function C.NPC(guid)
    if not C.Public(guid) or type(guid)~="string" then return nil end
    return tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-") or guid:match("^Vehicle%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
end
function C.New(origin,build)
    return {version=1,origin=origin,build=build or "unknown",revision=0,records={},queue={},cursor=1,count=0,
        recent={},recentSlots={},recentQueue={},recentCursor=1,stats={unattributed=0,multi=0,restricted=0,incomplete=0,excluded=0},
        settings={enabled=true,strip=true,tooltip=true,record=true,classic=true,skin=false,quest=true,own=true}}
end
function NS.RegisterPack(id,rows,items)
    for npc,row in pairs(rows) do NS.Raw[npc]=row end
    for item,info in pairs(items) do if not NS.Items[item] then NS.Items[item]=info end end
    NS.Loaded[id]=true
end
function NS.LoadPack(id)
    if NS.Loaded[id] then return true end
    if NS.Missing[id] then return false end
    if InCombatLockdown and InCombatLockdown() then
        NS.Deferred=NS.Deferred or {}; NS.Deferred[id]=true
        if NS.WaitForCombat then NS.WaitForCombat() end
        return false
    end
    if not C_AddOns or not C_AddOns.LoadAddOn then return false end
    local loaded=Suite.LoadReference("loot",id)
    if not loaded then
        NS.Missing[id]=true
        if not NS.ReferenceWarning and NS.Say then NS.ReferenceWarning=true; NS.Say("Bestiary DB unavailable ("..(Suite.lastDBError or "unknown").."). Enable Smyrna Bestiary DB in WoW AddOns and Mob loot references in Suite settings.") end
    end
    return loaded and NS.Loaded[id] or false
end
function NS.EnsureIndex()
    if next(NS.NPCPack)~=nil then return true end
    if NS.IndexMissing then return false end
    if Suite.Config.useDB==false or Suite.Config.data.loot==false then return false end
    if InCombatLockdown and InCombatLockdown() then
        NS.DeferredIndex=true
        if NS.WaitForCombat then NS.WaitForCombat() end
        return false
    end
    local load=(C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if not load then NS.IndexMissing=true;return false end
    local ok=load("SmyrnaBestiaryDB")
    if not ok then NS.IndexMissing=true;return false end
    return next(NS.NPCPack)~=nil
end
local mobCache,mobRing,mobCursor,MOB_CAP={},{},1,64
local MOB_PAT="^([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t([^\t]*)$"
function C.Mob(id)
    local cached=mobCache[id]
    if cached then return cached end
    if not NS.Raw[id] then
        if next(NS.NPCPack)==nil then NS.EnsureIndex() end
        if NS.NPCPack[id] then NS.LoadPack(NS.NPCPack[id]) end
    end
    local raw=NS.Raw[id]
    if not raw then return nil end
    if type(raw)=="table" then return raw end
    local f1,f2,f3,f4,f5,f6,f7=raw:match(MOB_PAT)
    if not f1 then return nil end
    local row={f1,tonumber(f2),tonumber(f3),tonumber(f4),f5,f6,f7}
    local old=mobRing[mobCursor];if old then mobCache[old]=nil end
    mobRing[mobCursor]=id;mobCursor=mobCursor%MOB_CAP+1;mobCache[id]=row
    return row
end
function C.Name(id,context,difficulty)
    local key=C.Key(context,id,difficulty)
    local own=NS.DB.records[key]
    if own and not own[4]:match("^NPC %d+$") then return own[4] end
    local community=NS.CommunityCreatures and NS.CommunityCreatures[key]
    if community then return community[1] end
    if not NS.Raw[id] then
        if next(NS.NPCPack)==nil then NS.EnsureIndex() end
        if NS.NPCPack[id] then NS.LoadPack(NS.NPCPack[id]) end
    end
    local raw=NS.Raw[id]
    if type(raw)=="string" then local n=raw:match("^([^\t]*)");if n and n~="" then return n end
    elseif type(raw)=="table" and raw[1] then return raw[1] end
    return "Unknown creature "..id
end
function C.Key(context,npc,difficulty,build) return context..":"..difficulty..":"..npc..":"..(build or (NS.DB and NS.DB.build) or "unknown") end
function C.Once(db,key,now)
    local old=db.recent[key]
    if old and now-old<1800 then return false end
    local slot=db.recentCursor; local previous=db.recentQueue[slot]
    if previous and db.recentSlots[previous]==slot then db.recent[previous]=nil; db.recentSlots[previous]=nil end
    db.recentQueue[slot]=key; db.recent[key]=now; db.recentSlots[key]=slot
    db.recentCursor=slot%C.RECENT+1
    return true
end
-- Record arrays: context, NPC, difficulty, name, sightings, windows, revision,
-- lastSeen, item table, cell table, truncated flag, record epoch.
-- item tuple = {windows containing it, total quantity}; cell = {map,x,y,sightings}.
function C.Record(db,context,npc,difficulty,name,items,cell,seen,level,creatureType)
    if type(context)~="string" or not context:match("^[MI]%d+$") or not C.Number(npc,1,10000000) or not C.Number(difficulty,0,1000) then return false end
    local key=C.Key(context,npc,difficulty,db.build)
    local r=db.records[key]
    db.revision=db.revision+1
    if not r then
        local slot=db.cursor; local previous=db.queue[slot]
        if previous and db.records[previous] then db.records[previous]=nil; db.count=db.count-1 end
        r={context,npc,difficulty,"NPC "..npc,0,0,0,0,{}, {},false,db.revision,db.build}
        db.records[key]=r; db.queue[slot]=key; db.cursor=slot%C.CAP+1; db.count=db.count+1
    end
    if C.Public(name) and type(name)=="string" and #name<=120 then r[4]=name end
    r[7]=db.revision; r[8]=C.Now()
    if C.Number(level,1,1000) then r[14]=math.min(r[14] or level,level); r[15]=math.max(r[15] or level,level) end
    if C.Public(creatureType) and type(creatureType)=="string" and #creatureType<=60 then r[16]=creatureType end
    if seen then r[5]=r[5]+1 end
    if items then
        r[6]=r[6]+1
        local count=0; for _ in pairs(r[9]) do count=count+1 end
        for id,quantity in pairs(items) do
            if C.Number(id,1,10000000) and C.Number(quantity,1,100000) then
                local item=r[9][id]
                if not item and count<C.ITEMCAP then item={0,0}; r[9][id]=item; count=count+1 end
                if item then item[1]=item[1]+1; item[2]=item[2]+quantity else r[11]=true end
            end
        end
    end
    if cell then
        local cellKey=table.concat(cell,":")
        local old=r[10][cellKey]
        if old then old[4]=old[4]+1
        else
            local count=0; for _ in pairs(r[10]) do count=count+1 end
            if count<C.CELLCAP then r[10][cellKey]={cell[1],cell[2],cell[3],1} end
        end
    end
    return true,r
end
local cache,cacheRing,cacheCursor,CACHE_CAP={},{},1,32
function C.ClearCache() wipe(cache);wipe(cacheRing);cacheCursor=1;wipe(mobCache);wipe(mobRing);mobCursor=1 end
local function Parse(text,source,result,lookup,settings)
    for token in (text or ""):gmatch("[^,]+") do
        local id,pct,extra,windows=token:match("^(%d+):([%d%.]+):?([^:]*):?(%d*)$")
        id,pct=tonumber(id),tonumber(pct)
        if id and pct and pct>=0 and pct<=100 then
            local quest=extra=="q"
            if not quest or settings.quest then
                local key=id..(source=="S" and ":S" or "")
                local row=lookup[key]
                if not row then
                    row={id=id,pct=pct,source=source,quest=quest,skin=source=="S"}; result[#result+1]=row; lookup[key]=row
                    if source=="F" then row.hits=tonumber(extra); row.windows=tonumber(windows) end
                else row.quest=row.quest or quest end
            end
        end
    end
end
function C.Drops(id,context,difficulty,settings)
    local mobKey=C.Key(context,id,difficulty)
    local ownRecord=NS.DB.records[mobKey]
    local key=mobKey..":"..(NS.LootRevision or 0)..":"..(ownRecord and ownRecord[6] or 0)..":"..tostring(settings.classic)..tostring(settings.skin)..tostring(settings.quest)..tostring(settings.own)
    if cache[key] then return cache[key] end
    local result,lookup={},{}
    local group=NS.Community and NS.Community[mobKey]
    for item,values in pairs(group or {}) do
        if C.Number(item,1,10000000) and C.Number(values[1],0,10^12) and C.Number(values[2],1,10^12) and values[1]<=values[2] then
            local row={id=item,pct=100*values[1]/values[2],source="G",hits=values[1],windows=values[2],contributors=values[3]}
            result[#result+1]=row; lookup[tostring(item)]=row
        end
    end
    if NS.GuildRows then
        for _,row in ipairs(NS.GuildRows(context,id,difficulty)) do
            local key=tostring(row.id)
            if not lookup[key] then
                local copy={};for k,v in pairs(row) do copy[k]=v end
                result[#result+1]=copy;lookup[key]=copy
            end
        end
    end
    local mob=C.Mob(id)
    if mob then
        Parse(mob[7],"F",result,lookup,settings)
        if settings.classic then Parse(mob[5],"C",result,lookup,settings) end
        if settings.skin then Parse(mob[6],"S",result,lookup,settings) end
    end
    local own=settings.own and ownRecord
    if own and own[6]>0 then
        for item,data in pairs(own[9]) do
            local row=lookup[tostring(item)]
            if not row then row={id=item,pct=100*data[1]/own[6],source="Y"}; result[#result+1]=row; lookup[tostring(item)]=row end
            row.ownHits=data[1]; row.ownWindows=own[6]
        end
        for _,row in ipairs(result) do
            if not row.skin and not row.ownWindows then
                local data=own[9][row.id]
                if data then row.ownHits=data[1];row.ownWindows=own[6]
                elseif not own[11] then row.ownHits=0;row.ownWindows=own[6] end
            end
        end
    end
    table.sort(result,function(a,b) if a.pct==b.pct then if a.id==b.id then return a.source<b.source end return a.id<b.id end return a.pct>b.pct end)
    local evicted=cacheRing[cacheCursor]
    if evicted then cache[evicted]=nil end
    cacheRing[cacheCursor]=key;cacheCursor=cacheCursor%CACHE_CAP+1
    cache[key]=result
    return result
end
function C.Item(id)
    local get=C_Item and C_Item.GetItemInfo or GetItemInfo
    if get then
        local name,link,quality,_,_,_,_,_,_,icon,value,class,subclass=get(id)
        if C.Public(name) and type(name)=="string" then return name,C.Public(link) and link or nil,C.Number(quality,0,8) and quality or 1,C.Public(icon) and icon or nil,C.Public(class) and class or nil,C.Public(subclass) and subclass or nil,C.Number(value,0,10^12) and value or 0 end
    end
    local reference=NS.Items[id]
    local refQ,refName
    if type(reference)=="string" then
        local q,n=reference:match("^(%d+)\t(.*)$")
        refQ,refName=tonumber(q),n
    elseif type(reference)=="table" then
        refQ,refName=reference[1],reference[2]
    end
    -- Resolving a loot name must not load the entire equipment catalog.
    if not refName and Suite.Equipment and Suite.Equipment.records then
        local gear=Suite.Equipment.Get(id,true);if gear then refQ,refName=gear.quality,gear.name end
    end
    local icon=C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
    return refName or ("Item "..id),nil,refQ or 1,(C.Public(icon) and icon) or "Interface\\Icons\\INV_Misc_QuestionMark"
end
local randomStats={eagle=true,bear=true,beast=true,boar=true,falcon=true,gorilla=true,monkey=true,owl=true,tiger=true,whale=true,wolf=true,agility=true,strength=true,stamina=true,intellect=true,spirit=true,power=true,healing=true,defense=true}
function C.DisplayName(name)
    local base,suffix=name:match("^(.-) of the (.+)$")
    if not base then base,suffix=name:match("^(.-) of (.+)$") end
    if base and randomStats[suffix:lower()] then return base.." of <stat>",(base:match("(%S+)%s*$") or base).." of <stat>",true end
    return name,name:match("^Item %d+$") and name or (name:match("(%S+)%s*$") or name),false
end
local armorSubclasses={[1]="Cloth",[2]="Leather",[3]="Mail",[4]="Plate",[6]="Shield"}
local function Group(class,subclass,quest,material)
    if class==4 then return armorSubclasses[subclass] or "Armor" end
    if class==2 then return "Weapon" end
    return class==9 and "Recipes" or quest and "Quest" or material and "Material" or "Other"
end
local groupOrder={Cloth=1,Leather=2,Mail=3,Plate=4,Shield=5,Armor=6,Weapon=7,Quest=8,Material=9,Recipes=10,Other=11}
local displayed=setmetatable({},{__mode="k"})
local complete=setmetatable({},{__mode="k"})
local clear=C.ClearCache
function C.ClearCache() clear();displayed=setmetatable({},{__mode="k"});complete=setmetatable({},{__mode="k"}) end
function C.DisplayDrops(rows,allLoot)
    local prepared=allLoot and complete or displayed
    if prepared[rows] then return prepared[rows] end
    local result,variants={},{}
    local workshop=Suite.Modules.SmyrnaWorkshop
    local reagents=Suite.ReagentProfessions
    local itemSources=Suite.ItemSources
    for _,row in ipairs(rows) do
        local name,_,quality,icon,class,subclass,value=C.Item(row.id)
        if not class then
            local instant=C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
            if instant then local _,_,_,_,_,c,sc=instant(row.id);if C.Number(c,0,20) then class=c end;if C.Number(sc,0,30) then subclass=sc end end
        end
        local material=(itemSources and itemSources.Material(row.id)) or (reagents and reagents[row.id]~=nil) or (workshop and workshop.HasUses and workshop.HasUses(row.id)) or class==7
        local quest=row.quest or class==12
        if allLoot or (quality~=0 and (quality>=2 or quest or material)) then
            local full,short,random=C.DisplayName(name)
            local group=Group(class,subclass,quest,material)
            local key=random and (full:lower()..":"..quality..":"..group..":"..row.source)
            local view=key and variants[key]
            if view then
                view.pctMin=math.min(view.pctMin,row.pct);view.pctMax=math.max(view.pctMax,row.pct);view.variants=view.variants+1
            else
                view={};for k,v in pairs(row) do view[k]=v end
                view.quest=quest
                view.fullName=full;view.shortName=short;view.quality=quality;view.icon=icon;view.class=class;view.subclass=subclass;view.group=group;view.value=value or 0
                view.pctMin=row.pct;view.pctMax=row.pct;view.variants=1
                result[#result+1]=view;if key then variants[key]=view end
            end
        end
    end
    table.sort(result,function(a,b)
        if a.quality~=b.quality then return a.quality>b.quality end
        local aq,bq=not not a.quest,not not b.quest
        if aq~=bq then return aq end
        if a.group~=b.group then return groupOrder[a.group]<groupOrder[b.group] end
        if a.value~=b.value then return a.value>b.value end
        if a.pctMax~=b.pctMax then return a.pctMax>b.pctMax end
        return a.id<b.id
    end)
    prepared[rows]=result;return result
end
local function FormatPct(n) return string.format("%.2f",n):gsub("0+$",""):gsub("%.$","") end
function C.Percent(row)
    if row.pctMin and row.pctMin~=row.pctMax then return FormatPct(row.pctMin).."-"..FormatPct(row.pctMax) end
    return FormatPct(row.pct)
end
local rateSources={F="Forever observed",H="Guild samples",G="Community samples",C="Classic estimate",S="Classic skinning estimate"}
function C.Rate(row)
    local source=rateSources[row.source] or "Your sample"
    local text=string.format("%.2f%% - %s",row.pct,source)
    if row.windows then text=text.." ("..row.hits.."/"..row.windows.." windows)" end
    if row.contributors then text=text.." ["..row.contributors.." contributors]" end
    if row.ownWindows and row.source~="Y" then text=text..string.format(" | You %.2f%% (%d/%d)",100*row.ownHits/row.ownWindows,row.ownHits,row.ownWindows) end
    if row.source=="Y" then text=text.." ("..row.ownHits.."/"..row.ownWindows.." windows)" end
    if row.quest then text=text.." [quest reference]" end
    if (row.ownWindows and row.ownWindows<20) or (row.windows and row.windows<20) then text=text.." [low sample]" end
    return text
end
function C.Wilson(hits,n)
    if n<=0 then return nil end
    local z=1.96; local p=hits/n; local denom=1+z*z/n
    local center=(p+z*z/(2*n))/denom
    local half=z*math.sqrt(p*(1-p)/n+z*z/(4*n*n))/denom
    return math.max(0,center-half)*100,math.min(1,center+half)*100
end
local function CSV(value) return '"'..tostring(value):gsub('"','""')..'"' end
function C.Export(db)
    local lines={"type,origin,context,npc,difficulty,epoch,revision,name,seen,windows,last,truncated,item,hits,quantity,map,cell_x,cell_y,cell_seen,build,level_min,level_max,creature_type"}
    for _,r in pairs(db.records) do
        local prefix=table.concat({CSV(db.origin),r[1],r[2],r[3],r[12],r[7],CSV(r[4])},",")
        local meta=","..CSV(r[13] or db.build)..","..(r[14] or "")..","..(r[15] or "")..","..CSV(r[16] or "")
        lines[#lines+1]="record,"..prefix..","..r[5]..","..r[6]..","..r[8]..","..(r[11] and 1 or 0)..",,,,,,,"..meta
        for id,item in pairs(r[9]) do lines[#lines+1]="item,"..prefix..",,,,,"..id..","..item[1]..","..item[2]..",,,,"..meta end
        for _,cell in pairs(r[10]) do lines[#lines+1]="cell,"..prefix..",,,,,,,,"..cell[1]..","..cell[2]..","..cell[3]..","..cell[4]..meta end
    end
    return table.concat(lines,"\n")
end
end chunk(name,Module) end
-- Internal module source: Recorder.lua
do local function chunk(...)
local _,NS=...
local C=NS.Core
local frame=CreateFrame("Frame")
local active=false
local excludeUntil=0
local excluded={ [2575]=true,[2576]=true,[3564]=true,[10248]=true,[29354]=true,[2366]=true,[2368]=true,[3570]=true,[11993]=true,[8613]=true,[8617]=true,[8618]=true,[10768]=true,[1804]=true,[13262]=true }
local events={"UPDATE_MOUSEOVER_UNIT","PLAYER_TARGET_CHANGED","LOOT_READY"}
function NS.PlayerCell()
    if not C_Map or not C_Map.GetMapWorldSize then return nil end
    local map=C_Map.GetBestMapForUnit("player")
    if not C.Number(map,1,1000000) then return nil end
    local p=C_Map.GetPlayerMapPosition(map,"player")
    if not p then return nil end
    local x,y=p:GetXY(); local width,height=C_Map.GetMapWorldSize(map)
    if not C.Public(x) or not C.Public(y) or type(x)~="number" or type(y)~="number" or x<0 or x>1 or y<0 or y>1 then return nil end
    if not C.Public(width) or not C.Public(height) or type(width)~="number" or type(height)~="number" or width<=0 or height<=0 or width>200000 or height>200000 then return nil end
    return {map,math.floor(math.min(x*width,width-.001)/200),math.floor(math.min(y*height,height-.001)/200)}
end
local function Identity(unit)
    local guid=UnitGUID(unit)
    local id=C.NPC(guid)
    if not id then return nil end
    return id,guid
end
function NS.RecordSighting(unit)
    local id,guid=Identity(unit)
    if not id then return end
    local context,difficulty=NS.Context()
    if not context or not C.Once(NS.DB,"s:"..guid,C.Now()) then return end
    local name=UnitName(unit)
    local level=UnitLevel and UnitLevel(unit)
    local creatureType=UnitCreatureType and UnitCreatureType(unit)
    if C.Record(NS.DB,context,id,difficulty,name,nil,NS.PlayerCell(),true,level,creatureType) then NS.Changed(true) end
end
function NS.RecordLootWindow()
    local stats=NS.DB.stats
    if GetTime()<excludeUntil or (LootIsFromItem and LootIsFromItem()) or (IsFishingLoot and IsFishingLoot()) then stats.excluded=stats.excluded+1; return end
    local total=GetNumLootItems()
    if not C.Number(total,0,64) then stats.restricted=stats.restricted+1; return end
    if total==0 then stats.unattributed=stats.unattributed+1; return end
    local guid,npc
    local items={}
    for slot=1,total do
        local sources={GetLootSourceInfo(slot)}
        if #sources==0 then stats.unattributed=stats.unattributed+1; return end
        for i=1,#sources,2 do
            local source=sources[i]; local id=C.NPC(source)
            if not id then stats.restricted=stats.restricted+1; return end
            if guid and guid~=source then stats.multi=stats.multi+1; return end
            guid,npc=source,id
        end
        local kind=GetLootSlotType and GetLootSlotType(slot)
        if not C.Public(kind) then stats.restricted=stats.restricted+1; return end
        local link=GetLootSlotLink(slot)
        if not C.Public(link) then stats.restricted=stats.restricted+1; return end
        local id=type(link)=="string" and tonumber(link:match("item:(%d+)"))
        if id then
            local _,_,quantity=GetLootSlotInfo(slot)
            if not C.Number(quantity,1,100000) then stats.incomplete=stats.incomplete+1; return end
            items[id]=(items[id] or 0)+quantity
        elseif kind==(LOOT_SLOT_ITEM or 1) or kind==nil then stats.incomplete=stats.incomplete+1; return end
    end
    if not guid then return end
    local context,difficulty=NS.Context()
    if not context or not C.Once(NS.DB,"l:"..guid,C.Now()) then return end
    local name
    local targetGUID,mouseGUID=UnitGUID("target"),UnitGUID("mouseover")
    if C.Public(targetGUID) and targetGUID==guid then name=UnitName("target") end
    if not C.Public(name) then name=nil end
    if not name and C.Public(mouseGUID) and mouseGUID==guid then name=UnitName("mouseover") end
    if C.Record(NS.DB,context,npc,difficulty,name,items,NS.PlayerCell(),false) then NS.Changed();if NS.ShareLoot then NS.ShareLoot(guid,context,difficulty,items) end end
end
frame:SetScript("OnEvent",function(_,event,...)
    if event=="UPDATE_MOUSEOVER_UNIT" then NS.RecordSighting("mouseover")
    elseif event=="PLAYER_TARGET_CHANGED" then NS.RecordSighting("target")
    elseif event=="LOOT_READY" then NS.RecordLootWindow()
    elseif event=="UNIT_SPELLCAST_SUCCEEDED" then local unit,_,id=...; if C.Public(unit) and unit=="player" and C.Public(id) and excluded[id] then excludeUntil=GetTime()+5 end end
end)
function NS.ConfigureRecorder()
    local enabled=NS.DB.settings.enabled and NS.DB.settings.record
    if enabled==active then return end
    active=enabled
    for _,event in ipairs(events) do if enabled then frame:RegisterEvent(event) else frame:UnregisterEvent(event) end end
    if enabled then
        if frame.RegisterUnitEvent then frame:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED","player") else frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED") end
    else
        frame:UnregisterEvent("UNIT_SPELLCAST_SUCCEEDED")
    end
end
end chunk(name,Module) end
-- Internal module source: UI.lua
do local function chunk(...)
local _,NS=...
local C=NS.Core
local launcher,bar,dropdown,options,exportWindow,sources,lootCanvas,lootScroll,categoryButton,categoryMenu
local categoryFilter,filterChoices="all",{}
local matchupPane,lootTab,matchupTab,lootHelp,lootSources
local detailTab="loot"
local lootLabel="|TInterface\\Icons\\INV_Misc_Bag_10:14:14|t |cffffd166Loot|r"
local function FilterLabel(text) return "|cff9dceff"..text.."|r  |TInterface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up:14:14|t" end
local resistanceLabel="|TInterface\\Icons\\INV_Sword_04:12:12|t Resistances |TInterface\\Icons\\INV_Shield_04:12:12|t"
local mobButtons,lootRows,checks={},{},{}
local page,lootPage,selected=1,1,nil
local mobs,drops={},{}
local zoneLabel,dropTitle,dropFooter,statsLabel,searchBox
local refreshPending=false
local function Label(parent,text,x,y,font)
    local f=parent:CreateFontString(nil,"OVERLAY",font or "GameFontHighlightSmall")
    f:SetPoint("TOPLEFT",x,y); f:SetJustifyH("LEFT"); f:SetText(text); return f
end
local function Button(parent,text,x,y,width,fn)
    local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
    b:SetSize(width,23); b:SetPoint("TOPLEFT",x,y); b:SetText(text); b:SetScript("OnClick",fn);Suite.StyleButton(b); return b
end
local function Panel(name,width,height,x,y)
    local f=CreateFrame("Frame",name,UIParent,"BackdropTemplate")
    f:SetSize(width,height); f:SetPoint("TOP",UIParent,"TOP",x or 0,y or -90)
    f:SetFrameStrata("DIALOG"); f:SetClampedToScreen(true)
    Suite.StylePanel(f,true)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart",function(self) if not (InCombatLockdown and InCombatLockdown()) then self:StartMoving() end end); f:SetScript("OnDragStop",f.StopMovingOrSizing)
    local close=Suite.CloseButton(f);f.SuiteCloseButton=close
    UISpecialFrames[#UISpecialFrames+1]=name
    return f
end
local function MobName(id)
    local context,difficulty=NS.Context()
    return context and C.Name(id,context,difficulty) or "Unknown creature"
end
local function ShowItem(owner,row)
    if not GameTooltip or (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then return end
    GameTooltip:SetOwner(owner,"ANCHOR_RIGHT")
    GameTooltip:SetHyperlink("item:"..row.id)
    GameTooltip:AddLine(C.Rate(row),1,.8,.4,true)
    if row.ownWindows then
        local lo,hi=C.Wilson(row.ownHits,row.ownWindows)
        GameTooltip:AddLine(string.format("Your sample range: %.1f%%-%.1f%% (95%% interval)",lo,hi),.8,.8,.8,true)
    end
    GameTooltip:AddLine("Observed rates describe recorded loot windows, not guaranteed drops.",.7,.7,.7,true)
    GameTooltip:Show()
end
local rarities={[0]="Poor",[1]="Common",[2]="Uncommon",[3]="Rare",[4]="Epic",[5]="Legendary",[6]="Artifact",[7]="Heirloom"}
local groupToCategory={Weapon="Weapons",Cloth="Armor",Leather="Armor",Mail="Armor",Plate="Armor",Shield="Armor",Armor="Armor",Recipes="Recipes",Material="Crafting Materials",Quest="Quest Items"}
local function Category(row)
 return groupToCategory[row.group] or "Other Items"
end
NS.LootCategory=Category
local function MakeLootRow(i)
            local row=CreateFrame("Button",nil,lootCanvas,"BackdropTemplate")
            row:SetSize(442,44); row:SetPoint("TOPLEFT",16,-48-(i-1)*48)
            Suite.StyleCard(row,.082,.094,.128)
            row:SetHighlightTexture("Interface\\Buttons\\WHITE8X8");local hover=row:GetHighlightTexture();if hover then hover:SetVertexColor(.25,.45,.7,.16) end
            row.tile=Suite.CreateIconTile(row,32);row.tile:SetPoint("LEFT",6,0);row.icon=row.tile.icon
            row.name=Label(row,"",46,-5,"GameFontHighlight"); row.name:SetWidth(388)
            row.rate=Label(row,"",46,-23); row.rate:SetWidth(388); row.rate:SetTextColor(.70,.75,.83)
            row.name:SetMaxLines(1); row.rate:SetMaxLines(1)
            row:SetScript("OnEnter",function(self) if self.row then ShowItem(self,self.row) end end)
            row:SetScript("OnLeave",function() if GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then GameTooltip:Hide() end end)
            lootRows[i]=row
            return row
end
local collapsedRarities,rarityHeaders={},{}
local collapsedCategories,categoryHeaders={},{}
local RefreshDrops
local function MakeRarityHeader(i)
    local h=CreateFrame("Button",nil,lootCanvas)
    h:SetSize(444,24)
    local hl=h:CreateTexture(nil,"HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(.85,.68,.32,.12)
    h.title=h:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    h.title:SetPoint("LEFT",2,0)
    h.count=h:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    h.count:SetPoint("LEFT",h.title,"RIGHT",6,0); h.count:SetTextColor(.65,.70,.78)
    h.arrow=h:CreateTexture(nil,"OVERLAY")
    h.arrow:SetSize(16,16); h.arrow:SetPoint("RIGHT",-2,0)
    h.rule=h:CreateTexture(nil,"ARTWORK"); h.rule:SetHeight(1)
    h:SetScript("OnClick",function(self)
        if self.rarityKey==nil then return end
        collapsedRarities[self.rarityKey]=not collapsedRarities[self.rarityKey]
        RefreshDrops()
    end)
    h:SetScript("OnEnter",function(self)
        if not GameTooltip or (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then return end
        GameTooltip:SetOwner(self,"ANCHOR_TOPLEFT")
        GameTooltip:SetText(self.rarityLabel or "Rarity")
        GameTooltip:AddLine(collapsedRarities[self.rarityKey] and "Click to expand." or "Click to collapse.",.8,.8,.8)
        GameTooltip:Show()
    end)
    h:SetScript("OnLeave",function() if GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then GameTooltip:Hide() end end)
    rarityHeaders[i]=h
    return h
end
local function MakeCategoryHeader(i)
    local h=CreateFrame("Button",nil,lootCanvas)
    h:SetSize(436,20)
    local hl=h:CreateTexture(nil,"HIGHLIGHT")
    hl:SetAllPoints(); hl:SetColorTexture(.93,.77,.40,.11)
    h.title=h:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    h.title:SetPoint("LEFT",2,0); h.title:SetTextColor(.93,.77,.40)
    h.count=h:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    h.count:SetPoint("LEFT",h.title,"RIGHT",5,0); h.count:SetTextColor(.65,.70,.78)
    h.arrow=h:CreateTexture(nil,"OVERLAY")
    h.arrow:SetSize(13,13); h.arrow:SetPoint("RIGHT",-3,0)
    h.rule=h:CreateTexture(nil,"ARTWORK"); h.rule:SetHeight(1)
    h:SetScript("OnClick",function(self)
        if not self.catKey then return end
        collapsedCategories[self.catKey]=not collapsedCategories[self.catKey]
        RefreshDrops()
    end)
    h:SetScript("OnEnter",function(self)
        if not GameTooltip or (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then return end
        GameTooltip:SetOwner(self,"ANCHOR_TOPLEFT")
        GameTooltip:SetText(self.catLabel or "Category")
        if self.catCount then GameTooltip:AddLine(self.catCount..(self.catCount==1 and " item" or " items"),.93,.77,.40) end
        GameTooltip:AddLine(collapsedCategories[self.catKey] and "Click to expand." or "Click to collapse.",.8,.8,.8)
        GameTooltip:Show()
    end)
    h:SetScript("OnLeave",function() if GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then GameTooltip:Hide() end end)
    categoryHeaders[i]=h
    return h
end
local categoryOrder={Weapons=1,Armor=2,Recipes=3,["Quest Items"]=4,["Crafting Materials"]=5,["Other Items"]=6}
local sourceNames={F="Forever sample",G="Community samples",H="Guild samples",C="Classic estimate",S="Skinning estimate",Y="Your samples"}
RefreshDrops=function()
    if not selected or not dropdown then return end
    local context,difficulty=NS.Context()
    if not context then return end
    local cachedDrops=C.DisplayDrops(C.Drops(selected,context,difficulty,NS.DB.settings),true)
    drops={};for i=1,#cachedDrops do drops[i]=cachedDrops[i] end
    table.sort(drops,function(a,b)
        local aq,bq=a.quality or 1,b.quality or 1
        if aq~=bq then return aq>bq end
        local ac,bc=Category(a),Category(b);if ac~=bc then return (categoryOrder[ac] or 99)<(categoryOrder[bc] or 99) end
        if a.pctMax~=b.pctMax then return a.pctMax>b.pctMax end
        if a.id~=b.id then return a.id<b.id end
        return a.source<b.source
    end)
    filterChoices={{key="all",label="All loot"}};local available={};local filtered={}
    for _,row in ipairs(drops) do
        local category=Category(row);local key="type:"..category
        if not available[key] then available[key]=true;filterChoices[#filterChoices+1]={key=key,label=category} end
        local kind
        if row.group=="Recipes" then
            kind=(row.fullName or ""):match("^([^:]+):")
            if not kind and GetItemSubClassInfo and row.subclass then kind=GetItemSubClassInfo(9,row.subclass) end
            if kind then local subkey="recipe:"..kind;if not available[subkey] then available[subkey]=true;filterChoices[#filterChoices+1]={key=subkey,label="Recipes / "..kind} end end
        end
        if categoryFilter=="all" or categoryFilter==key or (kind and categoryFilter=="recipe:"..kind) then filtered[#filtered+1]=row end
    end
    drops=filtered
    local own=NS.DB.records[C.Key(context,selected,difficulty)]
    if detailTab=="loot" then dropTitle:SetText(MobName(selected).." - Your loot data: "..(own and own[6] or 0)) end
    local rarCounts,catCounts={},{}
    for _,row in ipairs(drops) do
        local q=row.quality or 1
        local cat=Category(row)
        local ckey=q..":"..cat
        rarCounts[q]=(rarCounts[q] or 0)+1
        catCounts[ckey]=(catCounts[ckey] or 0)+1
    end
    local top,previousQuality,previousCategory=0,nil,nil
    local headerIdx,catHeaderIdx,rowIdx=0,0,0
    for i=1,#drops do
        local row=drops[i]
        local q=row.quality or 1
        local category=Category(row)
        if q~=previousQuality then
            if top>0 then top=top+6 end
            headerIdx=headerIdx+1
            local header=rarityHeaders[headerIdx] or MakeRarityHeader(headerIdx)
            local collapsed=collapsedRarities[q] and true or false
            local label=rarities[q] or "Other rarity"
            local rc=ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
            local rr,rg,rb=rc and rc.r or .86,rc and rc.g or .90,rc and rc.b or .96
            header.rarityKey=q; header.rarityLabel=label
            header:ClearAllPoints(); header:SetPoint("TOPLEFT",lootCanvas,"TOPLEFT",0,-top)
            header.title:SetText(label); header.title:SetTextColor(rr,rg,rb)
            local cnt=rarCounts[q] or 0
            header.count:SetText("("..cnt..")")
            header.arrow:SetTexture(collapsed and "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up" or "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
            local titleW=header.title:GetStringWidth()
            local countW=header.count:GetStringWidth()
            local ruleX=2+(type(titleW)=="number" and titleW>0 and titleW or (#label*9))+6+(type(countW)=="number" and countW>0 and countW or 20)+10
            local ruleW=math.max(12,420-ruleX)
            header.rule:ClearAllPoints(); header.rule:SetPoint("LEFT",header,"LEFT",ruleX,0); header.rule:SetWidth(ruleW)
            Suite.ApplyGradient(header.rule,"HORIZONTAL",rr,rg,rb,.72,rr,rg,rb,.08)
            header:Show()
            top=top+26; previousQuality=q; previousCategory=nil
        end
        if not collapsedRarities[q] then
            local catKey=q..":"..category
            local catCollapsed=collapsedCategories[catKey] and true or false
            if category~=previousCategory then
                if previousCategory~=nil then top=top+2 end
                catHeaderIdx=catHeaderIdx+1
                local ch=categoryHeaders[catHeaderIdx] or MakeCategoryHeader(catHeaderIdx)
                local ccnt=catCounts[catKey] or 0
                ch.catKey=catKey
                ch.catLabel=(rarities[q] or "Other rarity").." - "..category
                ch.catCount=ccnt
                ch:ClearAllPoints(); ch:SetPoint("TOPLEFT",lootCanvas,"TOPLEFT",8,-top)
                ch.title:SetText(category)
                ch.count:SetText("("..ccnt..")")
                ch.arrow:SetTexture(catCollapsed and "Interface\\Buttons\\UI-ScrollBar-ScrollUpButton-Up" or "Interface\\Buttons\\UI-ScrollBar-ScrollDownButton-Up")
                local ctW=ch.title:GetStringWidth()
                local ccW=ch.count:GetStringWidth()
                local cRuleX=2+(type(ctW)=="number" and ctW>0 and ctW or (#category*7))+5+(type(ccW)=="number" and ccW>0 and ccW or 18)+8
                local cRuleW=math.max(12,414-cRuleX)
                ch.rule:ClearAllPoints(); ch.rule:SetPoint("LEFT",ch,"LEFT",cRuleX,0); ch.rule:SetWidth(cRuleW)
                Suite.ApplyGradient(ch.rule,"HORIZONTAL",.93,.77,.40,.42,.93,.77,.40,.05)
                ch:Show()
                top=top+22
                previousCategory=category
            end
            if not catCollapsed then
                rowIdx=rowIdx+1
                local control=lootRows[rowIdx] or MakeLootRow(rowIdx)
                control:ClearAllPoints();control:SetPoint("TOPLEFT",lootCanvas,"TOPLEFT",6,-top);top=top+50
                local quality,icon=row.quality,row.icon
                local displayName=row.fullName
                if not displayName or not icon then
                    local iName,_,iQuality,iIcon=C.Item(row.id)
                    displayName=displayName or iName
                    quality=quality or iQuality
                    icon=icon or iIcon
                end
                control.icon:SetTexture(icon or "Interface\\Icons\\INV_Misc_QuestionMark")
                control.name:SetText(displayName)
                local color=ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality]
                local qr,qg,qb=color and color.r or .9,color and color.g or .9,color and color.b or .94
                control.name:SetTextColor(qr,qg,qb)
                if control.tile then control.tile:SetBackdropBorderColor(qr,qg,qb,.9) end
                Suite.SetCornerGlow(control,qr,qg,qb,(quality or 1)>=2 and .14 or .05)
                local rate=C.Percent(row).."%  -  "..(sourceNames[row.source] or "Unknown")..(row.variants>1 and " (stat variants)" or "")
                if row.ownWindows and row.source~="Y" then rate=rate..string.format(" | You %.2f%%",100*row.ownHits/row.ownWindows) end
                if row.windows then rate=rate.." | Sample: "..row.windows end
                if row.ownWindows then rate=rate.." | Yours: "..row.ownWindows end
                control.rate:SetText(rate); control.row=row; control:Show()
            end
        end
    end
    for i=headerIdx+1,#rarityHeaders do rarityHeaders[i]:Hide() end
    for i=catHeaderIdx+1,#categoryHeaders do categoryHeaders[i]:Hide() end
    for i=rowIdx+1,#lootRows do local c=lootRows[i]; c.row=nil; c:Hide() end
    lootCanvas:SetHeight(math.max(300,top));lootScroll:UpdateScrollChildRect()
    local curScroll,maxScroll=lootScroll:GetVerticalScroll(),lootScroll:GetVerticalScrollRange()
    if type(curScroll)=="number" and type(maxScroll)=="number" and curScroll>maxScroll then
        lootScroll:SetVerticalScroll(math.max(0,maxScroll))
    end
    dropFooter:SetText(#drops==0 and "No loot data recorded or available from enabled sources." or (#drops.." items - click any rarity or category header to collapse"))
end
function NS.SelectDetailsTab(tab)
    if not dropdown or (tab~="loot" and tab~="matchups") then return end
    if tab=="matchups" and (not NS.Matchups or not NS.Matchups.HasData(selected)) then return end
    detailTab=tab;dropdown.activeTab=tab
    local loot=tab=="loot"
    lootScroll:SetShown(loot);categoryButton:SetShown(loot);dropFooter:SetShown(loot)
    lootHelp:SetShown(loot);lootSources:SetShown(loot)
    if categoryMenu then categoryMenu:Hide() end
    lootTab:SetText(lootLabel)
    matchupTab:SetText(resistanceLabel)
    Suite.SetButtonSelected(lootTab,loot);Suite.SetButtonSelected(matchupTab,not loot)
    if loot then
        if matchupPane then matchupPane:Hide() end
        RefreshDrops()
    elseif NS.Matchups then
        if not matchupPane then matchupPane=NS.Matchups.Build(dropdown) end
        matchupPane:Refresh(selected);matchupPane:Show();dropTitle:SetText(MobName(selected).." - resistances")
    end
end
local function OpenDrops(id)
    if not dropdown then
        dropdown=Panel("SmyrnaBestiaryLoot",520,445,0,-175)
        dropTitle=Label(dropdown,"",16,-16,"GameFontNormalLarge")
        dropTitle:SetWidth(440)
        dropTitle:SetMaxLines(1)
        dropdown:SetFrameStrata("FULLSCREEN_DIALOG");dropdown:SetFrameLevel(120)
        lootScroll=CreateFrame("ScrollFrame",nil,dropdown,"UIPanelScrollFrameTemplate");lootScroll:SetPoint("TOPLEFT",16,-78);lootScroll:SetSize(470,299)
        lootCanvas=CreateFrame("Frame",nil,lootScroll);lootCanvas:SetSize(452,325);lootScroll:SetScrollChild(lootCanvas)
        for i=1,8 do MakeLootRow(i) end
        categoryButton=Button(dropdown,FilterLabel("All loot"),102,-43,245,function()
            if not categoryMenu then
                categoryMenu=CreateFrame("Frame",nil,dropdown,"BackdropTemplate");categoryMenu:SetPoint("TOPLEFT",dropdown,"TOPLEFT",16,-69);categoryMenu:SetFrameLevel(dropdown:GetFrameLevel()+30);categoryMenu:EnableMouse(true);Suite.StylePanel(categoryMenu);categoryMenu.buttons={}
                categoryMenu:SetScript("OnHide",function() Suite.SetButtonSelected(categoryButton,false) end)
            end
            if categoryMenu:IsShown() and rawget(categoryMenu,"ready") then categoryMenu:Hide();return end
            categoryMenu.ready=true;categoryMenu:SetSize(450,math.ceil(#filterChoices/2)*25+8)
            for i,choice in ipairs(filterChoices) do
                local b=categoryMenu.buttons[i]
                if not b then b=Button(categoryMenu,"",0,0,218,function(self)
                    categoryFilter=self.choice.key
                    if categoryFilter~="all" then
                        local catName=categoryFilter:match("^type:(.+)$") or (categoryFilter:match("^recipe:") and "Recipes")
                        if catName then
                            for ck in pairs(collapsedCategories) do
                                if ck:sub(-#catName-1)==":"..catName then collapsedCategories[ck]=nil end
                            end
                        end
                    end
                    categoryButton:SetText(FilterLabel(self.choice.label));categoryMenu:Hide();lootScroll:SetVerticalScroll(0);RefreshDrops()
                end);categoryMenu.buttons[i]=b end
                b.choice=choice;b:ClearAllPoints();b:SetPoint("TOPLEFT",4+((i-1)%2)*223,-4-math.floor((i-1)/2)*25);b:SetText(choice.label);b:Show()
            end
            for i=#filterChoices+1,#categoryMenu.buttons do categoryMenu.buttons[i]:Hide() end
            categoryMenu:Show();Suite.SetButtonSelected(categoryButton,true)
        end)
        local menuTint=categoryButton:CreateTexture(nil,"BACKGROUND");menuTint:SetAllPoints();menuTint:SetColorTexture(.08,.22,.38,1)
        categoryButton:GetNormalTexture():SetVertexColor(.08,.22,.38,1)
        Suite.SetButtonAccent(categoryButton,.25,.58,.9)
        lootTab=Button(dropdown,lootLabel,16,-43,80,function() NS.SelectDetailsTab("loot") end)
        lootTab:GetNormalTexture():SetVertexColor(.32,.22,.06,1)
        Suite.SetButtonAccent(lootTab,.9,.65,.2)
        matchupTab=Button(dropdown,resistanceLabel,370,-43,125,function() NS.SelectDetailsTab("matchups") end)
        local attack=matchupTab:CreateTexture(nil,"ARTWORK");attack:SetPoint("TOPLEFT",1,-1);attack:SetPoint("BOTTOMLEFT",1,1);attack:SetWidth(61.5);attack:SetColorTexture(.5,.1,.12,.8)
        local defense=matchupTab:CreateTexture(nil,"ARTWORK");defense:SetPoint("TOPRIGHT",-1,-1);defense:SetPoint("BOTTOMRIGHT",-1,1);defense:SetWidth(61.5);defense:SetColorTexture(.1,.25,.55,.8)
        Suite.SetButtonAccent(matchupTab,.7,.16,.19,.2,.45,.85)
        dropFooter=Label(dropdown,"",110,-398); dropFooter:SetWidth(390)
        lootHelp=Label(dropdown,"Drop rates are estimates, not guarantees. Hover an item for details.",16,-428)
        lootSources=Button(dropdown,"Sources",420,-414,75,NS.OpenSources)
        local itemRefreshQueued,itemRefreshGen=false,0
        dropdown:SetScript("OnEvent",function(_,_,itemID,success)
            if not C.Public(success) or success==false or not C.Number(itemID,1,10000000) then return end
            for _,control in ipairs(lootRows) do
                if control.row and control.row.id==itemID then
                    if not itemRefreshQueued then
                        itemRefreshQueued=true
                        local tok=itemRefreshGen
                        C_Timer.After(.15,function()
                            itemRefreshQueued=false
                            if tok==itemRefreshGen and dropdown and dropdown:IsShown() then C.ClearCache(); RefreshDrops() end
                        end)
                    end
                    return
                end
            end
        end)
        dropdown:SetScript("OnHide",function(self) self:UnregisterEvent("GET_ITEM_INFO_RECEIVED");itemRefreshGen=itemRefreshGen+1;itemRefreshQueued=false;if categoryMenu then categoryMenu:Hide() end end)
    end
    selected=id;lootPage=1;categoryFilter="all";categoryButton:SetText(FilterLabel("All loot"));if categoryMenu then categoryMenu:Hide() end;lootScroll:SetVerticalScroll(0); dropdown:Show(); dropdown:RegisterEvent("GET_ITEM_INFO_RECEIVED"); NS.SelectDetailsTab("loot");matchupTab:SetShown(NS.Matchups and NS.Matchups.HasData(id))
end
NS.OpenDrops=OpenDrops
local function RefreshBar()
    if not bar or not bar:IsShown() then return end
    local name,context,difficulty
    mobs,name,context,difficulty=NS.CurrentMobs(searchBox and searchBox:GetText())
    local pages=math.max(1,math.ceil(#mobs/6)); page=math.min(page,pages)
    zoneLabel:SetText(#mobs==0 and ((name or "This area").." - no creatures recorded yet") or ((name or "This area").." - choose a creature ("..#mobs..")  "..page.."/"..pages))
    for i=1,6 do
        local id=mobs[(page-1)*6+i]; local button=mobButtons[i]
        if id then
            button.npc=id; button.label:SetText(MobName(id)); button:Show()
        else button.npc=nil; button:Hide() end
    end
end
function NS.OpenBrowser()
    if not bar then
        bar=Panel("SmyrnaBestiaryBar",720,105,0,-65)
        zoneLabel=Label(bar,"",14,-10,"GameFontNormal")
        zoneLabel:SetWidth(435); zoneLabel:SetMaxLines(1)
        for i=1,6 do
            local button=CreateFrame("Button",nil,bar)
            button:SetSize(88,58); button:SetPoint("TOPLEFT",45+(i-1)*94,-37)
            local icon=button:CreateTexture(nil,"ARTWORK"); icon:SetSize(27,27); icon:SetPoint("TOP")
            icon:SetTexture("Interface\\Icons\\INV_Misc_MonsterHead_02")
            button.label=button:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
            button.label:SetPoint("TOP",icon,"BOTTOM",0,-3); button.label:SetWidth(88)
            button.label:SetMaxLines(2)
            button:SetScript("OnClick",function(self) if self.npc then OpenDrops(self.npc) end end)
            mobButtons[i]=button
        end
        Button(bar,"<",8,-48,28,function() page=math.max(1,page-1); RefreshBar() end)
        Button(bar,">",620,-48,28,function() page=page+1; RefreshBar() end)
        Button(bar,"Options",623,-13,67,NS.OpenOptions)
        searchBox=CreateFrame("EditBox",nil,bar,"InputBoxTemplate")
        searchBox:SetSize(135,20); searchBox:SetPoint("TOPRIGHT",-110,-8); searchBox:SetAutoFocus(false); searchBox:SetMaxLetters(40)
        searchBox:SetScript("OnTextChanged",function() page=1; NS.RefreshVisible() end)
        searchBox:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
        bar:SetScript("OnHide",function() if dropdown then dropdown:Hide() end end)
    end
    bar:Show(); RefreshBar()
end
function NS.OpenExport()
    if not exportWindow then
        exportWindow=Panel("SmyrnaBestiaryExport",760,460,0,-110)
        Label(exportWindow,"Share your discoveries",18,-18,"GameFontNormalLarge")
        Label(exportWindow,"Ctrl+A, Ctrl+C. Save the text as a .csv file to combine it with other players' discoveries.",18,-45)
        local scroll=CreateFrame("ScrollFrame",nil,exportWindow,"UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT",18,-75); scroll:SetPoint("BOTTOMRIGHT",-36,18)
        local edit=CreateFrame("EditBox",nil,scroll); edit:SetMultiLine(true); edit:SetAutoFocus(false)
        edit:SetFontObject(ChatFontNormal); edit:SetWidth(695); edit:SetHeight(350); edit:SetMaxLetters(0)
        edit:SetScript("OnTextChanged",function() scroll:UpdateScrollChildRect() end)
        edit:SetScript("OnEscapePressed",function() exportWindow:Hide() end)
        edit:SetScript("OnCursorChanged",function(_,_,y,_,height)
            local offset=scroll:GetVerticalScroll()
            if -y<offset then scroll:SetVerticalScroll(-y) elseif -y+height>offset+scroll:GetHeight() then scroll:SetVerticalScroll(-y+height-scroll:GetHeight()) end
        end)
        scroll:SetScrollChild(edit); exportWindow.edit=edit
        exportWindow:SetScript("OnHide",function() edit:ClearFocus(); edit:SetText("") end)
    end
    exportWindow:Show(); exportWindow.edit:SetText(C.Export(NS.DB)); exportWindow.edit:SetFocus(); exportWindow.edit:HighlightText()
end
function NS.OpenSources(owner)
    if not sources then
        sources=Panel("SmyrnaBestiarySources",400,260,0,-130)
        sources:SetFrameStrata("FULLSCREEN_DIALOG");sources:SetFrameLevel(180)
        sources:SetBackdropColor(.055,.14,.21,.96);sources:SetBackdropBorderColor(.48,.78,1,.8)
        Label(sources,"About loot data",16,-16,"GameFontNormalLarge"):SetTextColor(.65,.86,1)
        local text=Label(sources,
            "|cff9bd9ffYour samples|r  Loot windows recorded locally.\n"..
            "|cff9bd9ffGuild samples|r  Received from consenting guildmates.\n"..
            "|cff9bd9ffCommunity samples|r  Imported shared observations.\n\n"..
            "|cff9bd9ffForever reference|r  Everloot contributors, CC BY-SA 4.0.\neverloot.app - snapshot: 17 Nov 2026.\n\n"..
            "|cff9bd9ffClassic estimates|r  CMaNGOS classic-db, GPL-3.0, via Tnny's Mob Loot.\n"..
            "|cff9bd9ffCreature / area reference|r  QuestieDB contributors.\nSee included notices for attribution.\n\n"..
            "Recorded samples and reference estimates do not guarantee your next drop.",16,-48)
        text:SetWidth(368);sources.infoText=text
    end
    sources:SetHeight(sources.infoText:GetStringHeight()+66)
    sources:ClearAllPoints()
    if (type(owner)=="table" or type(owner)=="userdata") and owner.GetObjectType then
        -- The popup grows upward from the invoking button; its X is well above
        -- the cursor instead of occupying the clicked button's position.
        sources:SetPoint("BOTTOMRIGHT",owner,"TOPRIGHT",0,16)
    else sources:SetPoint("CENTER",UIParent,"CENTER",0,40) end
    sources:Show();sources:Raise()
end

function NS.OpenOptions()
    if not options then
        options=Panel("SmyrnaBestiaryOptions",530,430,0,-120)
        Label(options,"Smyrna Bestiary",20,-18,"GameFontNormalLarge")
        Label(options,"See what enemies drop and build your personal loot guide as you play.",20,-45)
        Suite.OptionSection(options,'Basics',20,-65,490)
        Suite.OptionSection(options,'Drop sources',20,-163,490)
        Suite.OptionSection(options,'Guild sharing',20,-293,490)
        local labels={{"enabled","Enable Bestiary"},{"tooltip","Show loot summary on enemy tooltips"},{"record","Record loot from enemies I kill"},{"own","Show my personal drop data alongside the guide"},{"classic","Include Classic WoW drop rates (fallback)"},{"skin","Include skinning drops"},{"quest","Include quest item drops"},{"guildShare","Share and receive drop data with guildmates"}}
        for i,entry in ipairs(labels) do
            local key,text=entry[1],entry[2]
            local box=CreateFrame("CheckButton",nil,options,"UICheckButtonTemplate")
            local y=i<=3 and (-82-(i-1)*26) or i<=7 and (-180-(i-4)*26) or -310
            box:SetPoint("TOPLEFT",18,y)
            local label=box:CreateFontString(nil,"OVERLAY","GameFontHighlight")
            label:SetPoint("LEFT",box,"RIGHT",0,0); label:SetText(text)
            box:SetScript("OnClick",function(self) NS.Set(key,self:GetChecked()) end); checks[key]=box
        end
        Button(options,"Browse this zone",20,-350,145,NS.OpenBrowser)
        Button(options,"Export data",183,-350,145,NS.OpenExport)
        Button(options,"About & sources",346,-350,145,NS.OpenSources)
        statsLabel=Label(options,"",20,-390); statsLabel:SetWidth(490)
    end
    for key,box in pairs(checks) do box:SetChecked(NS.DB.settings[key]) end
    local windows=0; for _,record in pairs(NS.DB.records) do windows=windows+record[6] end
    local s=NS.DB.stats
    local unclear=s.unattributed+s.multi+s.restricted+s.incomplete
    statsLabel:SetText(Suite.UIText("Your guide: ","heading")..Suite.UIText(NS.DB.count.." creatures","good").."  /  "..Suite.UIText(windows.." loots recorded","detail").."\n"..Suite.UIText("Skipped unclear loots: "..unclear,"muted").."\nDrop rates are estimates from recorded kills, not guaranteed drops.")
    options:Show()
    return options
end
function NS.ConfigureUI()
    for key,box in pairs(checks) do box:SetChecked(NS.DB.settings[key]) end
    if dropdown and dropdown:IsShown() then RefreshDrops() end
end
function NS.RefreshVisible(zoneChanged)
    if not ((bar and bar:IsShown()) or (dropdown and dropdown:IsShown())) then return end
    if zoneChanged then page=1; if dropdown then dropdown:Hide() end end
    if refreshPending then return end
    refreshPending=true
    C_Timer.After(.2,function() refreshPending=false; RefreshBar(); if dropdown and dropdown:IsShown() then RefreshDrops() end end)
end
end chunk(name,Module) end
-- Internal module source: Main.lua
do local function chunk(...)
local addonName,NS=...
local C=NS.Core
local driver=CreateFrame("Frame")
local contextEvents={"PLAYER_ENTERING_WORLD","ZONE_CHANGED_NEW_AREA","ZONE_CHANGED_INDOORS","PLAYER_DIFFICULTY_CHANGED"}
local contextEventSet={}
for _,event in ipairs(contextEvents) do contextEventSet[event]=true end
function NS.Say(text) DEFAULT_CHAT_FRAME:AddMessage("|cffdfb66bSmyrna Bestiary:|r "..text) end
function NS.Context()
    local name,kind,difficulty,_,_,_,_,instance=GetInstanceInfo()
    if C.Number(instance,1,1000000) and C.Public(kind) and kind~="none" then return "I"..instance,C.Number(difficulty,0,1000) and difficulty or 0,C.Public(name) and type(name)=="string" and name or "This dungeon" end
    local map=C_Map.GetBestMapForUnit("player")
    if not C.Number(map,1,1000000) then return nil end
    if next(NS.Zones)==nil then NS.EnsureIndex() end
    local original=map
    for _=1,6 do
        local key="M"..map
        local info=C_Map.GetMapInfo(map)
        if NS.Zones[key] then return key,0,info and info.name or NS.Zones[key][1] end
        if not info or not info.parentMapID or info.parentMapID==0 then break end
        map=info.parentMapID
    end
    local info=C_Map.GetMapInfo(original)
    return "M"..original,0,info and info.name or "This area"
end
function NS.CurrentMobs(search)
    local context,difficulty,name=NS.Context()
    local list,seen={},{}
    if not context then return list,"This area",nil,0 end
    if next(NS.Zones)==nil then NS.EnsureIndex() end
    local zone=NS.Zones[context]
    if zone then for number in zone[2]:gmatch("%d+") do local id=tonumber(number); seen[id]=true; list[#list+1]=id end end
    local communityIDs=NS.CommunityZones and NS.CommunityZones[context..":"..difficulty..":"..NS.DB.build]
    for _,id in ipairs(communityIDs or {}) do if not seen[id] then seen[id]=true; list[#list+1]=id end end
    for _,record in pairs(NS.DB.records) do
        if record[1]==context and record[3]==difficulty and record[13]==NS.DB.build and not seen[record[2]] then seen[record[2]]=true; list[#list+1]=record[2] end
    end
    local labels={}
    for _,id in ipairs(list) do labels[id]=C.Name(id,context,difficulty) end
    if search and search~="" then
        local filtered={}; local needle=string.lower(search)
        for _,id in ipairs(list) do if string.lower(labels[id]):find(needle,1,true) then filtered[#filtered+1]=id end end
        list=filtered
    end
    table.sort(list,function(a,b)
        local an,bn=labels[a],labels[b]
        if an==bn then return a<b end
        return an<bn
    end)
    return list,name,context,difficulty
end
function NS.Changed(sightingOnly)
    if not sightingOnly then NS.LootRevision=(NS.LootRevision or 0)+1;C.ClearCache() end
    if NS.RefreshVisible then NS.RefreshVisible() end
end
function NS.Set(key,value)
    if type(NS.DB.settings[key])~="boolean" then return end
    NS.DB.settings[key]=not not value; NS.DB.revision=NS.DB.revision+1
    NS.ConfigureRecorder(); C.ClearCache()
    if NS.ConfigureUI then NS.ConfigureUI() end
end
function NS.WaitForCombat() driver:RegisterEvent("PLAYER_REGEN_ENABLED") end
function NS.TooltipUnitAllowed(unit)
    if UnitIsPlayer then local player=UnitIsPlayer(unit);if not C.Public(player) or player then return false end end
    if UnitIsFriend then local friendly=UnitIsFriend("player",unit);if not C.Public(friendly) or friendly then return false end end
    if UnitCanAttack then
        local attack=UnitCanAttack("player",unit)
        if not C.Public(attack) then return false end
        if not attack then
            local dead=UnitIsDead and UnitIsDead(unit)
            if not C.Public(dead) or not dead then return false end
            local reaction=UnitReaction and UnitReaction("player",unit)
            if not C.Number(reaction,1,4) then return false end
        end
    end
    return true
end
function NS.MobClick(unit,button)
    if button~="LeftButton" or not IsControlKeyDown or not IsControlKeyDown() then return end
    if not NS.DB or not NS.DB.settings.enabled or not NS.TooltipUnitAllowed(unit) then return end
    local guid=UnitGUID(unit);if not C.Public(guid) then return end
    local id=C.NPC(guid);if id then NS.OpenDrops(id) end
end
local tooltipQualityLabels={[5]="Legendary",[4]="Epic",[3]="Rare",[2]="Uncommon"}
local tooltipQualityColors={[5]="ff8000",[4]="a335ee",[3]="0070dd",[2]="1eff00"}
local shownNPC=setmetatable({},{__mode="k"})
local function AddTooltip(tooltip)
    if not tooltip or (tooltip.IsForbidden and tooltip:IsForbidden()) then return end
    if Suite.IsLootInteraction and Suite.IsLootInteraction(tooltip.GetOwner and tooltip:GetOwner()) then return end
    if not NS.DB or not NS.DB.settings.enabled or not NS.DB.settings.tooltip then return end
    if not (IsControlKeyDown and IsControlKeyDown()) then return end
    local _,unit=tooltip:GetUnit()
    if not C.Public(unit) or type(unit)~="string" then return end
    if not NS.TooltipUnitAllowed(unit) then return end
    local guid=UnitGUID(unit)
    if not C.Public(guid) then return end
    local id=C.NPC(guid)
    if not id then return end
    if shownNPC[tooltip]==id then return end
    local context,difficulty=NS.Context()
    if not context then return end
    shownNPC[tooltip]=id
    local rows=C.Drops(id,context,difficulty,NS.DB.settings)
    local counts,seen={},{}
    for _,row in ipairs(rows) do
        if not seen[row.id] then
            seen[row.id]=true
            local _,_,quality=C.Item(row.id)
            if quality and quality>=2 and quality<=5 then counts[quality]=(counts[quality] or 0)+1 end
        end
    end
    local parts={}
    for quality=5,2,-1 do
        if counts[quality] then parts[#parts+1]="|cff"..tooltipQualityColors[quality]..counts[quality].." "..tooltipQualityLabels[quality].."|r" end
    end
    local text=#parts>0 and table.concat(parts,"  /  ") or "No uncommon+ drops recorded"
    tooltip:AddLine(text,.9,.9,.9,true)
    if NS.Matchups then local hint=NS.Matchups.PlayerHint and NS.Matchups.PlayerHint(id);if hint then tooltip:AddLine(hint,.8,.9,1,true) end end
    Suite.OptionalHint(tooltip,"Ctrl + left-click to expand")
end
NS.AddTooltip=AddTooltip
function NS.Perf()
    if Suite.Memory then Suite.Memory() end
end
SLASH_SMYRNABESTIARY1="/sb"
SLASH_SMYRNABESTIARY2="/smyrnabestiary"
SlashCmdList.SMYRNABESTIARY=function(input)
    if not NS.DB then return end
    if input=="target" then
        if NS.TooltipUnitAllowed("target") then local id=C.NPC(UnitGUID("target"));if id then NS.OpenDrops(id) end end
    elseif input=="options" then NS.OpenOptions()
    elseif input=="export" then NS.OpenExport()
    elseif input=="perf" then NS.Perf()
    else NS.OpenBrowser() end
end
driver:RegisterEvent("ADDON_LOADED"); driver:RegisterEvent("PLAYER_LOGIN")
driver:SetScript("OnEvent",function(self,event,arg1)
    if event=="ADDON_LOADED" and C.Public(arg1) and arg1=="SmyrnaSuite" then
        self:UnregisterEvent("ADDON_LOADED")
        local _,build=GetBuildInfo()
        if type(SmyrnaBestiaryDB)~="table" or SmyrnaBestiaryDB.version~=1 then SmyrnaBestiaryDB=C.New(string.format("%x%06x",C.Now(),math.random(0,0xffffff)),tostring(build or "unknown")) end
        NS.DB=SmyrnaBestiaryDB; NS.DB.build=tostring(build or "unknown")
    elseif event=="PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        NS.ConfigureRecorder(); NS.ConfigureUI()
        pcall(driver.RegisterEvent,driver,"GLOBAL_MOUSE_DOWN");driver:RegisterEvent("PLAYER_TARGET_CHANGED");driver:RegisterEvent("MODIFIER_STATE_CHANGED")
        if TargetFrame then TargetFrame:HookScript("OnClick",function(_,button) NS.MobClick("target",button) end) end
        for _,e in ipairs(contextEvents) do driver:RegisterEvent(e) end
        if TooltipDataProcessor and Enum and Enum.TooltipDataType then
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit,function(tooltip) if tooltip==GameTooltip then AddTooltip(tooltip) end end)
        elseif GameTooltip:HasScript("OnTooltipSetUnit") then GameTooltip:HookScript("OnTooltipSetUnit",AddTooltip) end
        GameTooltip:HookScript("OnTooltipCleared",function(self) shownNPC[self]=nil end)
        GameTooltip:HookScript("OnHide",function(self) shownNPC[self]=nil end)
    elseif event=="MODIFIER_STATE_CHANGED" then
        if C.Public(arg1) and (arg1=="LCTRL" or arg1=="RCTRL") and GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) and GameTooltip:IsShown() then
            local _,unit=GameTooltip:GetUnit()
            if C.Public(unit) and type(unit)=="string" and UnitExists and UnitExists(unit) and NS.TooltipUnitAllowed(unit) then
                shownNPC[GameTooltip]=nil
                pcall(GameTooltip.SetUnit,GameTooltip,unit)
            end
        end
    elseif event=="PLAYER_TARGET_CHANGED" then
        if IsControlKeyDown and IsControlKeyDown() and IsMouseButtonDown and IsMouseButtonDown("LeftButton") then NS.MobClick("target","LeftButton") end
    elseif event=="GLOBAL_MOUSE_DOWN" then
        if not C.Public(arg1) or arg1~="LeftButton" or not IsControlKeyDown or not IsControlKeyDown() then return end
        local unit
        if GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) and GameTooltip:IsShown() then
            _,unit=GameTooltip:GetUnit()
        end
        if C.Public(unit) and type(unit)=="string" then
            NS.MobClick(unit,arg1)
        else
            NS.MobClick("mouseover",arg1)
        end
    elseif event=="PLAYER_REGEN_ENABLED" then
        driver:UnregisterEvent(event)
        if NS.DeferredIndex then NS.DeferredIndex=nil; NS.EnsureIndex() end
        local todo=NS.Deferred; NS.Deferred=nil
        for id in pairs(todo or {}) do NS.LoadPack(id) end
        NS.Changed()
    elseif contextEventSet[event] and NS.DB and NS.RefreshVisible then NS.RefreshVisible(true) end
end)
end chunk(name,Module) end
Suite.Loaded[name]=true
