local _,Suite=...
local name="SmyrnaQuests"
Suite.Versions[name]="0.1.0"
if Suite.Config.features[name]==false then return end
local Module={}
Suite.Modules[name]=Module

local W=Suite.WorldDB
local worldPins,miniPins={},{}
local mapHooked,tipHooked
local window,tracker,questRows,scroll,canvas,statusLabel,checks,trackerLines=nil,nil,{},nil,nil,nil,{},{}
local activeQuests,activeCount={},0
local activeQuestNPCs,activeQuestNPCsBuilt={},false -- O(1) npcID -> { qid, ... } index for instant unit tooltips
local RACE_BITS={Human=1,Orc=2,Dwarf=4,NightElf=8,Scourge=16,Tauren=32,Gnome=64,Troll=128,Goblin=256,BloodElf=512,Draenei=1024}
local CLASS_BITS={WARRIOR=1,PALADIN=2,HUNTER=4,ROGUE=8,PRIEST=16,DEATHKNIGHT=32,SHAMAN=64,MAGE=128,WARLOCK=256,DRUID=1024}

local Public=Suite.Public or function(v) return not (issecretvalue and issecretvalue(v)) end
local function Num(v,lo,hi) return Public(v) and type(v)=="number" and v==v and v>=lo and v<=hi end

local function Cfg()
    local c=Suite.Config.quests
    if type(c)~="table" then c={}; Suite.Config.quests=c end
    if c.enabled==nil then c.enabled=true end
    if c.worldMap==nil then c.worldMap=true end
    if c.minimap==nil then c.minimap=true end
    if c.lowLevel==nil then c.lowLevel=false end
    if c.tooltips==nil then c.tooltips=true end
    if c.tracker==nil then c.tracker=false end
    if type(c.notes)~="table" then c.notes={} end
    return c
end
Module.Config=Cfg

local function GetNoteEntry(qid,create)
    if not Num(qid,1,10000000) then return nil end
    local notes=Cfg().notes
    local e=notes[qid]
    if not e and create then
        e={text="",pins={}}
        notes[qid]=e
    end
    if e and type(e.pins)~="table" then e.pins={} end
    return e
end

local function PruneNoteEntry(qid)
    local notes=Cfg().notes
    local e=notes[qid]
    if not e then return end
    local txt=type(e.text)=="string" and e.text:gsub("^%s+",""):gsub("%s+$","") or ""
    local pins=type(e.pins)=="table" and e.pins or {}
    if txt=="" and #pins==0 then
        notes[qid]=nil
    else
        e.text=txt; e.pins=pins
    end
end

local function TrimText(s,maxLen)
    if type(s)~="string" then return "" end
    s=s:gsub("[\r\n]+"," "):gsub("^%s+",""):gsub("%s+$","")
    if maxLen and #s>maxLen then s=s:sub(1,maxLen) end
    return s
end

function Module.GetQuestNote(qid)
    return GetNoteEntry(qid,false)
end

local ApplyQuestRefresh

function Module.SetQuestNote(qid,text)
    if not Num(qid,1,10000000) then return false end
    local clean=TrimText(text or "",240)
    local e=GetNoteEntry(qid,clean~="")
    if e then
        e.text=clean
        PruneNoteEntry(qid)
    end
    if ApplyQuestRefresh then ApplyQuestRefresh() end
    return true
end

function Module.AddQuestPin(qid,kind,label,mapID,x10,y10)
    if not Num(qid,1,10000000) then return false,"Invalid quest" end
    kind=(kind=="entrance") and "entrance" or "note"
    if not Num(mapID,1,1000000) or not Num(x10,0,1000) or not Num(y10,0,1000) then
        mapID=C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        local pos=mapID and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID,"player")
        if not pos or not pos.GetXY then return false,"Player map position unavailable here" end
        local px,py=pos:GetXY()
        if not Num(px,0,1) or not Num(py,0,1) then return false,"Player map position unavailable here" end
        x10=math.floor(px*1000+.5)
        y10=math.floor(py*1000+.5)
    end
    local e=GetNoteEntry(qid,true)
    if #e.pins>=16 then table.remove(e.pins,1) end
    local lbl=TrimText(label or "",80)
    if lbl=="" then lbl=(kind=="entrance") and "Entrance" or "Note" end
    e.pins[#e.pins+1]={map=mapID,x=x10,y=y10,kind=kind,label=lbl}
    if ApplyQuestRefresh then ApplyQuestRefresh() end
    return true,e.pins[#e.pins]
end

function Module.RemoveQuestPin(qid,idx)
    local e=GetNoteEntry(qid,false)
    if not e or not Num(idx,1,#e.pins) then return false end
    table.remove(e.pins,idx)
    PruneNoteEntry(qid)
    if ApplyQuestRefresh then ApplyQuestRefresh() end
    return true
end

function Module.ClearQuestPins(qid)
    local e=GetNoteEntry(qid,false)
    if not e then return false end
    wipe(e.pins)
    PruneNoteEntry(qid)
    if ApplyQuestRefresh then ApplyQuestRefresh() end
    return true
end

local function IsCompleted(qid)
    if C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        local ok,v=pcall(C_QuestLog.IsQuestFlaggedCompleted,qid)
        if ok and Public(v) then return v==true end
    end
    if IsQuestFlaggedCompleted then
        local ok,v=pcall(IsQuestFlaggedCompleted,qid)
        if ok and Public(v) then return v==true end
    end
    return false
end

local function PlayerMasks()
    local _,race=UnitRace("player")
    local _,class=UnitClass("player")
    local lvl=UnitLevel("player")
    local r=(Public(race) and race and RACE_BITS[race]) or 0
    local c=(Public(class) and class and CLASS_BITS[class]) or 0
    return (Num(lvl,1,200) and lvl or 1),r,c
end

-- Use double-precision arithmetic so >32-bit Forever race masks (e.g. 8589934770) never overflow bit.band!
local function MaskAllows(mask,playerBit)
    if not mask or mask==0 or playerBit==0 then return true end
    if type(mask)~="number" or mask~=mask then return true end
    return (math.floor(mask/playerBit)%2)==1
end

local function RebuildActiveQuestNPCIndex()
    wipe(activeQuestNPCs)
    if activeCount<=0 or not W or not W.loaded then activeQuestNPCsBuilt=false; return end
    activeQuestNPCsBuilt=true
    local function IndexNPC(nid,qid)
        if not nid then return end
        local list=activeQuestNPCs[nid]
        if not list then activeQuestNPCs[nid]={qid}; return end
        for i=1,#list do if list[i]==qid then return end end
        list[#list+1]=qid
    end
    for qid,aq in pairs(activeQuests) do
        if not aq.complete then
            local q=W.Quest(qid)
            if q then
                local ob=q.ob
                if type(ob)=="table" then
                    if type(ob[1])=="table" then
                        for _,e in ipairs(ob[1]) do IndexNPC(type(e)=="table" and e[1] or e,qid) end
                    end
                    if type(ob[3])=="table" then
                        for _,e in ipairs(ob[3]) do
                            local it=W.Item(type(e)=="table" and e[1] or e)
                            if it and type(it.nd)=="table" then
                                for _,dn in ipairs(it.nd) do IndexNPC(dn,qid) end
                            end
                        end
                    end
                    if type(ob[5])=="table" then
                        for _,e in ipairs(ob[5]) do
                            if type(e)=="table" and type(e[1])=="table" then
                                for _,dn in ipairs(e[1]) do IndexNPC(dn,qid) end
                            end
                        end
                    end
                end
                if type(q.rs)=="table" then
                    for _,iid in ipairs(q.rs) do
                        local it=W.Item(iid)
                        if it and type(it.nd)=="table" then
                            for _,dn in ipairs(it.nd) do IndexNPC(dn,qid) end
                        end
                    end
                end
            end
        end
    end
end

local function RefreshActiveQuests()
    wipe(activeQuests); activeCount=0
    if C_QuestLog and C_QuestLog.GetNumQuestLogEntries and C_QuestLog.GetInfo then
        local n=C_QuestLog.GetNumQuestLogEntries()
        for i=1,math.min(n or 0,120) do
            local info=C_QuestLog.GetInfo(i)
            if info and not info.isHeader and Num(info.questID,1,10000000) then
                local objs={}
                if C_QuestLog.GetQuestObjectives then
                    local raw=C_QuestLog.GetQuestObjectives(info.questID)
                    for _,o in ipairs(raw or {}) do
                        if Public(o.text) and type(o.text)=="string" then
                            objs[#objs+1]={text=o.text,done=o.finished==true,type=o.type}
                        end
                    end
                end
                local done=C_QuestLog.IsComplete and C_QuestLog.IsComplete(info.questID)
                activeQuests[info.questID]={id=info.questID,title=info.title or ("Quest #"..info.questID),level=info.level or 0,complete=done==true,objs=objs,logIndex=i}
                activeCount=activeCount+1
            end
        end
    elseif GetNumQuestLogEntries and GetQuestLogTitle then
        local n=GetNumQuestLogEntries()
        for i=1,math.min(n or 0,120) do
            local title,level,_,_,isHeader,_,isComplete,_,qid=GetQuestLogTitle(i)
            if not isHeader and Num(qid,1,10000000) then
                local objs={}
                local numObj=GetNumQuestLeaderBoards and GetNumQuestLeaderBoards(i) or 0
                for j=1,numObj do
                    local txt,otype,fin=GetQuestLogLeaderBoard(j,i)
                    if Public(txt) and type(txt)=="string" then objs[#objs+1]={text=txt,done=fin==true,type=otype} end
                end
                activeQuests[qid]={id=qid,title=title or ("Quest #"..qid),level=level or 0,complete=(isComplete==1 or isComplete==true),objs=objs,logIndex=i}
                activeCount=activeCount+1
            end
        end
    end
    RebuildActiveQuestNPCIndex()
end

local function QuestGreenRange(lvl)
    if GetQuestGreenRange then
        local ok,r=pcall(GetQuestGreenRange)
        if ok and Public(r) and type(r)=="number" and r>0 then return r end
    end
    if lvl<=5 then return 4
    elseif lvl<=39 then return math.floor(lvl/10)+4
    else return math.min(12,math.floor(lvl/5)+1) end
end

local function QuestDifficultyHex(qLvl,pLvl)
    if not qLvl or qLvl<=0 or not pLvl or pLvl<=0 then return "ffd670" end
    local diff=qLvl-pLvl
    if diff>=5 then return "ff4a4a"
    elseif diff>=3 then return "ff9933"
    elseif diff>=-2 then return "ffd670"
    elseif qLvl>=(pLvl-QuestGreenRange(pLvl)) then return "55d86e"
    else return "9a9ea8" end
end

local function IsSeasonalQuest(q)
    if not q or not q.sp or q.sp==0 then return false end
    if bit and bit.band then
        return bit.band(q.sp,1)==0
    end
    return true
end

local function IsQuestAvailable(qid,q,playerLvl,raceBit,classBit,showLow,showSeasonal)
    if not q or not q.n then return false end
    if activeQuests[qid] or IsCompleted(qid) then return false end
    if (q.rl or 0)>playerLvl then return false end
    if q.ml and q.ml>0 and playerLvl>q.ml then return false end
    if not showLow and (q.ql or playerLvl)>0 and (q.ql or playerLvl)<(playerLvl-QuestGreenRange(playerLvl)) then return false end
    if not MaskAllows(q.rc,raceBit) then return false end
    if not MaskAllows(q.cl,classBit) then return false end
    if IsSeasonalQuest(q) and not showSeasonal then return false end
    if q.pg then
        for _,pre in ipairs(q.pg) do
            if pre>0 and not IsCompleted(pre) then return false end
            if pre<0 and IsCompleted(-pre) then return false end
        end
    end
    if q.ps and #q.ps>0 then
        local any=false
        for _,pre in ipairs(q.ps) do if IsCompleted(pre) then any=true; break end end
        if not any then return false end
    end
    if q.ex then
        for _,ex in ipairs(q.ex) do if activeQuests[ex] or IsCompleted(ex) then return false end end
    end
    if q.nx and q.nx>0 and (activeQuests[q.nx] or IsCompleted(q.nx)) then return false end
    if q.pq and q.pq>0 and not activeQuests[q.pq] then return false end
    return true
end

-- Questie extraObjectives iconType -> Smyrna pin kind
local EO_ICON_MAP={[1]="slay",[2]="loot",[3]="event",[4]="object",[5]="talk",[6]="event",[7]="object"}

-- Kinds that represent multi-spawn quest objective fields (clustered into area rings)
local FIELD_KINDS={slay=true,loot=true,object=true,event=true,obj=true}
local FIELD_COLORS={
    slay={.95,.32,.28,.34},
    loot={.96,.78,.28,.34},
    object={.36,.82,.98,.34},
    event={.76,.52,.98,.34},
    obj={.96,.78,.28,.34},
}
local PIN_DRAW_ORDER={
    turnin=8, avail=5, ["repeat"]=6, entrance=4, note=4,
    talk=3, slay=2, loot=2, object=2, event=2, obj=2,
}
local FIELD_RING_TEX="Interface\\AddOns\\SmyrnaSuite\\Media\\DiaryRing"
local FIELD_RING_FALLBACK="Interface\\Minimap\\Ping\\ping2"

-- Collect pins for a specific uiMapID using O(1) X-Z-<mapID> + full QuestieDB marker data + user pins!
local function CollectZonePins(mapID)
    local pins,clusters={},{}
    local cfg=Cfg()
    local hasWorld=(W and W.Ensure and W.Ensure()) and true or false
    local playerLvl,raceBit,classBit=PlayerMasks()
    local function AddPin(kind,x10,y10,qid,title,level,who,detail,userPin)
        if not x10 or not y10 or x10<0 or x10>1000 or y10<0 or y10>1000 then return end
        local cell=FIELD_KINDS[kind] and 45 or 18
        local cx,cy=math.floor(x10/cell),math.floor(y10/cell)
        local ckey=kind..":"..cx..":"..cy
        local nx,ny=x10/1000,y10/1000
        local c=clusters[ckey]
        if not c then
            c={kind=kind,x=nx,y=ny,minX=nx,maxX=nx,minY=ny,maxY=ny,sumX=nx,sumY=ny,ptCount=1,items={}}
            clusters[ckey]=c; pins[#pins+1]=c
        else
            if nx<c.minX then c.minX=nx end
            if nx>c.maxX then c.maxX=nx end
            if ny<c.minY then c.minY=ny end
            if ny>c.maxY then c.maxY=ny end
            c.sumX=c.sumX+nx; c.sumY=c.sumY+ny; c.ptCount=c.ptCount+1
            c.x=c.sumX/c.ptCount; c.y=c.sumY/c.ptCount
        end
        for i=1,#c.items do
            local it=c.items[i]
            if it.id==qid and it.who==who and it.detail==detail and not userPin then return end
        end
        if #c.items<8 then
            c.items[#c.items+1]={id=qid,title=title,level=level,who=who,detail=detail,userPin=userPin}
        end
    end

    local function PlotNpc(nid,kind,qid,title,level,detail)
        if not hasWorld or not nid then return end
        local npc=W.Npc(nid)
        if not npc then return end
        local pts=npc.sp and npc.sp[mapID]
        if type(pts)=="table" then
            for k=1,math.min(#pts,24) do
                AddPin(kind,pts[k][1],pts[k][2],qid,title,level,npc.n,detail)
            end
        end
        local wpts=npc.wp and npc.wp[mapID]
        if type(wpts)=="table" then
            for k=1,math.min(#wpts,12) do
                AddPin(kind,wpts[k][1],wpts[k][2],qid,title,level,npc.n,(detail and (detail.." (Patrol)") or "Patrol"))
            end
        end
    end

    local function PlotObject(oid,kind,qid,title,level,detail)
        if not hasWorld or not oid then return end
        local obj=W.Object(oid)
        if not obj then return end
        local pts=obj.sp and obj.sp[mapID]
        if type(pts)=="table" then
            for k=1,math.min(#pts,24) do
                AddPin(kind,pts[k][1],pts[k][2],qid,title,level,obj.n,detail)
            end
        end
    end

    local function PlotItemSources(iid,kind,qid,title,level,prefix)
        if not hasWorld or not iid then return end
        local it=W.Item(iid)
        if not it then return end
        local lbl=it.n and ((prefix or "Drops: ")..it.n) or "Quest item"
        if type(it.nd)=="table" then
            for k=1,math.min(#it.nd,12) do
                PlotNpc(it.nd[k],kind,qid,title,level,lbl)
            end
        end
        if type(it.od)=="table" then
            local oLbl=it.n and ((prefix or "Loot: ")..it.n) or "Quest object"
            for k=1,math.min(#it.od,12) do
                PlotObject(it.od[k],"object",qid,title,level,oLbl)
            end
        end
        if type(it.vd)=="table" then
            local vLbl=it.n and ("Sold by vendor: "..it.n) or "Quest vendor"
            for k=1,math.min(#it.vd,6) do
                PlotNpc(it.vd[k],"talk",qid,title,level,vLbl)
            end
        end
    end

    local function PlaceEntityGroup(group,kind,qid,title,level,detail)
        if type(group)~="table" then return end
        local npcs=group[1]
        if type(npcs)=="table" then
            for _,nid in ipairs(npcs) do PlotNpc(nid,kind,qid,title,level,detail) end
        end
        local objs=group[2]
        if type(objs)=="table" then
            for _,oid in ipairs(objs) do PlotObject(oid,kind,qid,title,level,detail) end
        end
        local items=group[3]
        if type(items)=="table" then
            for _,iid in ipairs(items) do PlotItemSources(iid,kind,qid,title,level,"Starts quest: ") end
        end
    end

    local dentMap=hasWorld and W.DungeonEntrances and W.DungeonEntrances() or nil
    local function PlotDungeonEntrance(q,qid,title,level,detail)
        if not dentMap or not q or not q.zn then return end
        local dent=dentMap[q.zn]
        if not dent or type(dent.e)~="table" then return end
        for _,ent in ipairs(dent.e) do
            if ent[1]==mapID then
                AddPin("entrance",ent[2],ent[3],qid,title,level,(dent.n or "Dungeon").." Entrance",detail or "Instance entrance")
            end
        end
    end

    local function AllObjsOfTypeDone(aq,otype)
        if not aq or type(aq.objs)~="table" or #aq.objs==0 then return false end
        local found=false
        for _,o in ipairs(aq.objs) do
            if o.type==otype then
                found=true
                if not o.done then return false end
            end
        end
        return found
    end

    -- 1. Active quests: turn-ins (if complete) or full QuestieDB objective markers (if in progress)
    if hasWorld then
        for qid,aq in pairs(activeQuests) do
            local q=W.Quest(qid)
            if q then
                if aq.complete then
                    PlaceEntityGroup(q.fb,"turnin",qid,aq.title,aq.level,"Ready to turn in")
                    PlotDungeonEntrance(q,qid,aq.title,aq.level,"Turn-in inside instance")
                else
                    local ob=q.ob
                    if type(ob)=="table" then
                        if type(ob[1])=="table" and not AllObjsOfTypeDone(aq,"monster") then
                            for _,entry in ipairs(ob[1]) do
                                local nid=type(entry)=="table" and entry[1] or entry
                                local txt=type(entry)=="table" and type(entry[2])=="string" and entry[2] or "Slay"
                                PlotNpc(nid,"slay",qid,aq.title,aq.level,txt)
                            end
                        end
                        if type(ob[2])=="table" and not AllObjsOfTypeDone(aq,"object") then
                            for _,entry in ipairs(ob[2]) do
                                local oid=type(entry)=="table" and entry[1] or entry
                                local txt=type(entry)=="table" and type(entry[2])=="string" and entry[2] or "Interact"
                                PlotObject(oid,"object",qid,aq.title,aq.level,txt)
                            end
                        end
                        if type(ob[3])=="table" and not AllObjsOfTypeDone(aq,"item") then
                            for _,entry in ipairs(ob[3]) do
                                local iid=type(entry)=="table" and entry[1] or entry
                                PlotItemSources(iid,"loot",qid,aq.title,aq.level,"Drops: ")
                            end
                        end
                        -- Group 5: Kill-credit lists ({{npcID1, npcID2, ...}, rootNpc, text, ...})
                        if type(ob[5])=="table" and not AllObjsOfTypeDone(aq,"monster") then
                            for _,entry in ipairs(ob[5]) do
                                if type(entry)=="table" and type(entry[1])=="table" then
                                    local txt=type(entry[3])=="string" and entry[3] or "Kill credit"
                                    for _,nid in ipairs(entry[1]) do
                                        PlotNpc(nid,"slay",qid,aq.title,aq.level,txt)
                                    end
                                end
                            end
                        end
                        -- Group 6: Spell objectives
                        if type(ob[6])=="table" then
                            for _,entry in ipairs(ob[6]) do
                                local sid=type(entry)=="table" and entry[1] or entry
                                local txt=type(entry)=="table" and type(entry[2])=="string" and entry[2] or "Spell objective"
                                if type(sid)=="number" and W.Npc(sid) then
                                    PlotNpc(sid,"event",qid,aq.title,aq.level,txt)
                                end
                            end
                        end
                    end
                    -- Trigger-end / exploration / escort coordinates (q.tr = {text, {mapID: [[x10,y10], ...]}})
                    if type(q.tr)=="table" and type(q.tr[2])=="table" then
                        local tpts=q.tr[2][mapID]
                        if type(tpts)=="table" then
                            local tTxt=type(q.tr[1])=="string" and q.tr[1]~="" and q.tr[1] or "Quest location"
                            for _,pt in ipairs(tpts) do
                                AddPin("event",pt[1],pt[2],qid,aq.title,aq.level,tTxt,"Objective location")
                            end
                        end
                    end
                    -- Questie extraObjectives (cave entrances, summon spots, special clickables)
                    if type(q.eo)=="table" then
                        for _,row in ipairs(q.eo) do
                            local objIdx=type(row[4])=="number" and row[4] or 0
                            local skip=(objIdx>0 and aq.objs and aq.objs[objIdx] and aq.objs[objIdx].done) and true or false
                            if not skip then
                                local kind=EO_ICON_MAP[row[2]] or "event"
                                local txt=type(row[3])=="string" and row[3]~="" and row[3] or "Special objective"
                                if type(row[1])=="table" and type(row[1][mapID])=="table" then
                                    for _,pt in ipairs(row[1][mapID]) do
                                        AddPin(kind,pt[1],pt[2],qid,aq.title,aq.level,txt,"Quest marker")
                                    end
                                end
                                if type(row[5])=="table" then
                                    for _,ref in ipairs(row[5]) do
                                        if ref[1]=="m" then PlotNpc(ref[2],kind,qid,aq.title,aq.level,txt)
                                        elseif ref[1]=="o" then PlotObject(ref[2],kind,qid,aq.title,aq.level,txt)
                                        elseif ref[1]=="i" then PlotItemSources(ref[2],kind,qid,aq.title,aq.level,txt..": ") end
                                    end
                                end
                            end
                        end
                    end
                    -- Required source items (keys, torches, quest tools not listed as formal objectives)
                    if type(q.rs)=="table" then
                        for _,iid in ipairs(q.rs) do
                            PlotItemSources(iid,"loot",qid,aq.title,aq.level,"Required item: ")
                        end
                    end
                    PlotDungeonEntrance(q,qid,aq.title,aq.level,"Objective inside instance")
                end
            end
        end

        -- 2. Available quests in this zone (O(1) lookup via X-Z-<mapID>!)
        if cfg.visibility~="active" then
            local showLow=(cfg.visibility=="all") or cfg.lowLevel
            local z=W.Zone(mapID)
            if z and z.q then
                for _,qid in ipairs(z.q) do
                    local q=W.Quest(qid)
                    if IsQuestAvailable(qid,q,playerLvl,raceBit,classBit,showLow,cfg.seasonal) then
                        local kind=(q.sp and bit and bit.band and bit.band(q.sp,1)~=0) and "repeat" or "avail"
                        PlaceEntityGroup(q.sb,kind,qid,q.n,q.ql or q.rl or 0,q.xp and (q.xp.." XP") or nil)
                        PlotDungeonEntrance(q,qid,q.n,q.ql or q.rl or 0,"Available inside instance")
                    end
                end
            end
        end
    end

    -- 3. Custom user-dropped quest pins (entrances & notes)
    local notes=cfg.notes
    if type(notes)=="table" then
        for qid,entry in pairs(notes) do
            if type(entry)=="table" and type(entry.pins)=="table" and #entry.pins>0 and not IsCompleted(qid) then
                local aq=activeQuests[qid]
                local q=hasWorld and W.Quest(qid) or nil
                local title=(aq and aq.title) or (q and q.n) or ("Quest #"..qid)
                local level=(aq and aq.level) or (q and (q.ql or q.rl)) or 0
                for idx,up in ipairs(entry.pins) do
                    if up.map==mapID then
                        local det=(up.kind=="entrance" and "Custom Entrance") or "Custom Note"
                        AddPin(up.kind=="entrance" and "entrance" or "note",up.x,up.y,qid,title,level,up.label or det,det,{qid=qid,idx=idx})
                    end
                end
            end
        end
    end
    return pins
end

local PIN_ICONS={
    avail="Interface\\GossipFrame\\AvailableQuestIcon",
    ["repeat"]="Interface\\GossipFrame\\DailyQuestIcon",
    turnin="Interface\\GossipFrame\\ActiveQuestIcon",
    obj="Interface\\GossipFrame\\BattleMasterGossipIcon",
    slay="Interface\\GossipFrame\\BattleMasterGossipIcon",
    loot="Interface\\Icons\\INV_Misc_Bag_08",
    object="Interface\\GossipFrame\\BinderGossipIcon",
    event="Interface\\Icons\\INV_Misc_Map_01",
    talk="Interface\\GossipFrame\\GossipGossipIcon",
    entrance="Interface\\Icons\\Spell_Arcane_PortalStormwind",
    note="Interface\\Icons\\INV_Misc_Note_01",
}

local PIN_HEADINGS={
    avail="Available Quest",
    ["repeat"]="Repeatable Quest",
    turnin="Quest Turn-In",
    obj="Quest Objective",
    slay="Quest Target",
    loot="Quest Loot",
    object="Quest Object",
    event="Quest Location",
    talk="Quest NPC",
    entrance="Quest Entrance",
    note="Quest Note",
}

local function ShowPinTooltip(owner,cluster)
    if not GameTooltip or (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then return end
    GameTooltip:SetOwner(owner,"ANCHOR_RIGHT")
    local head=PIN_HEADINGS[cluster.kind] or "Quest Marker"
    local pLvl=UnitLevel and UnitLevel("player")
    if not Num(pLvl,1,200) then pLvl=60 end
    GameTooltip:SetText(head,1,.86,.48)
    local notes=Cfg().notes
    local shownNote={}
    local hasUserPin=false
    for _,it in ipairs(cluster.items) do
        local hex=QuestDifficultyHex(it.level,pLvl)
        local lvl=it.level and it.level>0 and ("|cff"..hex.."["..it.level.."]|r ") or ""
        GameTooltip:AddLine(lvl..(it.title or "Quest"),1,1,1)
        if it.who then GameTooltip:AddLine("  "..it.who..(it.detail and (" - "..it.detail) or ""),.64,.84,1) end
        if it.userPin then hasUserPin=true end
        local ne=it.id and notes and notes[it.id]
        if ne and type(ne.text)=="string" and ne.text~="" and not shownNote[it.id] then
            shownNote[it.id]=true
            GameTooltip:AddLine("  Note: "..ne.text,1,.92,.55,true)
        end
    end
    GameTooltip:AddLine("Left-click: Open Quest Scroll & Notes",.68,.76,.86)
    if hasUserPin then
        GameTooltip:AddLine("Ctrl+Right-Click: Remove custom pin",1,.58,.52)
    end
    GameTooltip:Show()
end

local function HideSafeTip()
    if GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then GameTooltip:Hide() end
end

local function AvoidDiaryCollision(px,py,pts,thresh,ox,oy)
    if type(pts)~="table" then return px,py end
    local r2=thresh*thresh
    for i=1,#pts do
        local dx=px-pts[i][1]; local dy=py-pts[i][2]
        if dx*dx+dy*dy<r2 then return px+ox,py+oy end
    end
    return px,py
end

local function LayoutWorldPin(pin,c,canvasF,width,height,scale,baseLevel)
    pin:SetScale(scale)
    local lvl=baseLevel+(PIN_DRAW_ORDER[c.kind] or 2)
    if pin.SetFixedFrameLevel then pin:SetFixedFrameLevel(false) end
    pin:SetFrameLevel(lvl)
    if pin.SetFixedFrameLevel then pin:SetFixedFrameLevel(true) end
    local px,py=AvoidDiaryCollision(c.x*width,-c.y*height,Suite.DiaryWorldPts,16*scale,15*scale,7*scale)
    pin:ClearAllPoints(); pin:SetPoint("CENTER",canvasF,"TOPLEFT",px/scale,py/scale)
    if pin.fieldRing then
        local fc=FIELD_COLORS[c.kind]
        if fc and (c.ptCount or 1)>=2 then
            local rw=math.max(26,math.min(140,((c.maxX-c.minX)*width+20)/scale))
            local rh=math.max(26,math.min(140,((c.maxY-c.minY)*height+20)/scale))
            local diam=math.max(rw,rh)
            pin.fieldRing:SetSize(diam,diam)
            pin.fieldRing:SetVertexColor(fc[1],fc[2],fc[3],fc[4])
            pin.fieldRing:Show()
        else
            pin.fieldRing:Hide()
        end
    end
end

local function HideWorld() for _,p in ipairs(worldPins) do p:Hide() end end
function Module.RepositionWorld()
    if not WorldMapFrame or not WorldMapFrame:IsShown() then return end
    local canvasF=WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
    if not canvasF then return end
    local width,height=canvasF:GetWidth(),canvasF:GetHeight()
    if width<=0 or height<=0 then return end
    local zoom=WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale() or 1
    if not Num(zoom,.01,100) then zoom=1 end
    local scale=1/zoom
    local baseLevel=math.max((canvasF:GetFrameLevel() or 1)+27,2020)
    for _,pin in ipairs(worldPins) do
        if pin:IsShown() and pin.cluster then
            LayoutWorldPin(pin,pin.cluster,canvasF,width,height,scale,baseLevel)
        end
    end
end
function Module.DrawWorld()
    HideWorld()
    local cfg=Cfg()
    if not cfg.enabled or not cfg.worldMap or not WorldMapFrame or not WorldMapFrame:IsShown() then return end
    local canvasF=WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
    local mapID=WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    if not canvasF or not mapID then return end
    local width,height=canvasF:GetWidth(),canvasF:GetHeight()
    if width<=0 or height<=0 then return end
    local zoom=WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale() or 1
    if not Num(zoom,.01,100) then zoom=1 end
    local scale=1/zoom
    -- Match Questie: WorldMapFrame.ScrollContainer / POI overlays start around FrameLevel 2000-2015
    local baseLevel=math.max((canvasF:GetFrameLevel() or 1)+27,2020)
    local list=CollectZonePins(mapID)
    for i=1,math.min(#list,160) do
        local c=list[i]; local pin=worldPins[i]
        if not pin then
            pin=CreateFrame("Button",nil,canvasF); pin:SetSize(18,18); pin:EnableMouse(true)
            pin:RegisterForClicks("LeftButtonUp","RightButtonUp")
            local ring=pin:CreateTexture(nil,"BACKGROUND")
            ring:SetPoint("CENTER",pin,"CENTER",0,0)
            if ring:SetTexture(FIELD_RING_TEX)==false then ring:SetTexture(FIELD_RING_FALLBACK) end
            ring:Hide()
            pin.fieldRing=ring
            pin.tex=pin:CreateTexture(nil,"OVERLAY"); pin.tex:SetAllPoints()
            pin:SetScript("OnEnter",function(self) if self.cluster then ShowPinTooltip(self,self.cluster) end end)
            pin:SetScript("OnLeave",HideSafeTip)
            pin:SetScript("OnClick",function(self,btn)
                local cl=self.cluster
                if not cl or not cl.items or not cl.items[1] then return end
                if btn=="RightButton" and IsControlKeyDown and IsControlKeyDown() then
                    for _,it in ipairs(cl.items) do
                        if it.userPin then
                            Module.RemoveQuestPin(it.userPin.qid,it.userPin.idx)
                            HideSafeTip()
                            return
                        end
                    end
                elseif btn=="LeftButton" and cl.items[1].id then
                    Module.OpenParchment(cl.items[1].id)
                end
            end)
            worldPins[i]=pin
        end
        pin.cluster=c; pin:SetParent(canvasF)
        local texPath=PIN_ICONS[c.kind] or PIN_ICONS.avail
        pin.tex:SetTexture(texPath)
        if texPath:find("\\Icons\\",1,true) then pin.tex:SetTexCoord(.08,.92,.08,.92) else pin.tex:SetTexCoord(0,1,0,1) end
        LayoutWorldPin(pin,c,canvasF,width,height,scale,baseLevel)
        pin:Show()
    end
end

local function HideMini() for _,p in ipairs(miniPins) do p:Hide(); p.mx=nil; p.my=nil end end
local qMiniMap,qMiniActive,qMiniLow,qMiniList,qLastPX,qLastPY,qLastFace,qLastRad=nil,nil,nil,nil,nil,nil,nil,nil
local qMiniDriver,qMiniMoving,qMiniHookedZoom
local qRotAcc=0

local function UpdateMini(force)
    local cfg=Cfg()
    if not cfg.enabled or not cfg.minimap or not Minimap or not Minimap:IsShown() or not C_Minimap or not C_Minimap.GetViewRadius then
        HideMini(); qLastPX=nil; return
    end
    local mapID=C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not Num(mapID,1,1000000) then HideMini(); qLastPX=nil; return end
    local pos=C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(mapID,"player")
    if not pos or not pos.GetXY then HideMini(); qLastPX=nil; return end
    local px,py=pos:GetXY()
    local width,height=C_Map.GetMapWorldSize and C_Map.GetMapWorldSize(mapID)
    local radius=C_Minimap.GetViewRadius()
    if not Num(px,0,1) or not Num(py,0,1) or not Num(width,1,200000) or not Num(height,1,200000) or not Num(radius,1,10000) then HideMini(); qLastPX=nil; return end
    local rotated=GetCVar("rotateMinimap")=="1"
    if C_Minimap.IsRotateMinimapIgnored and C_Minimap.IsRotateMinimapIgnored() then rotated=false end
    local facing=rotated and GetPlayerFacing() or 0
    if not Num(facing,-10,10) then facing=0 end
    local lowFlag=cfg.lowLevel and true or false
    local sameQuery=(qMiniMap==mapID and qMiniActive==activeCount and qMiniLow==lowFlag)
    if not force and sameQuery and qLastRad==radius and qLastPX and math.abs(px-qLastPX)<1e-6 and math.abs(py-qLastPY)<1e-6 and math.abs(facing-qLastFace)<1e-4 then
        return
    end
    if not sameQuery or not qMiniList then
        qMiniList=CollectZonePins(mapID)
        qMiniMap=mapID; qMiniActive=activeCount; qMiniLow=lowFlag
    end
    qLastPX,qLastPY,qLastFace,qLastRad=px,py,facing,radius
    local cosF,sinF=rotated and math.cos(facing) or 1,rotated and math.sin(facing) or 0
    local halfW,halfH=Minimap:GetWidth()/2,Minimap:GetHeight()/2
    local maxSq=(radius*.88)*(radius*.88)
    local shown=0
    for i=1,#qMiniList do
        local c=qMiniList[i]
        local dx,dy=(c.x-px)*width,(py-c.y)*height
        if rotated then dx,dy=dx*cosF+dy*sinF,dy*cosF-dx*sinF end
        if dx*dx+dy*dy<=maxSq then
            shown=shown+1
            local pin=miniPins[shown]
            if not pin then
                pin=CreateFrame("Frame",nil,Minimap); pin:SetSize(14,14); pin:EnableMouse(true)
                pin:SetFrameLevel(Minimap:GetFrameLevel()+5)
                pin.tex=pin:CreateTexture(nil,"OVERLAY"); pin.tex:SetAllPoints()
                pin:SetScript("OnEnter",function(self) if self.cluster then ShowPinTooltip(self,self.cluster) end end)
                pin:SetScript("OnLeave",HideSafeTip)
                miniPins[shown]=pin
            end
            if pin.cluster~=c or force then
                pin.cluster=c
                pin.tex:SetTexture(PIN_ICONS[c.kind] or PIN_ICONS.avail)
            end
            local mx,my=AvoidDiaryCollision((dx/radius)*halfW,(dy/radius)*halfH,Suite.DiaryMiniPts,14,13,6)
            if not pin.mx or math.abs(mx-pin.mx)>=.25 or math.abs(my-pin.my)>=.25 then
                pin.mx,pin.my=mx,my
                pin:ClearAllPoints(); pin:SetPoint("CENTER",Minimap,"CENTER",mx,my)
            end
            if not pin:IsShown() then pin:Show() end
            if shown>=48 then break end
        end
    end
    for i=shown+1,#miniPins do
        local p=miniPins[i]
        if p:IsShown() then p:Hide(); p.mx=nil; p.my=nil end
    end
end

local function OnQMiniUpdate(_,elapsed)
    qRotAcc=qRotAcc+(elapsed or 0)
    local step=qMiniMoving and .06 or .15
    if qRotAcc>=step then qRotAcc=0; UpdateMini(false) end
end

local function SyncQMiniMotion()
    if not qMiniDriver then return end
    local cfg=Cfg()
    local want=cfg.enabled and cfg.minimap and Minimap and Minimap:IsShown() and C_Minimap and C_Minimap.GetViewRadius
    if not want then qMiniDriver:SetScript("OnUpdate",nil); HideMini(); return end
    local rotating=(GetCVar("rotateMinimap")=="1") and not (C_Minimap.IsRotateMinimapIgnored and C_Minimap.IsRotateMinimapIgnored())
    if qMiniMoving or rotating then
        qRotAcc=0
        qMiniDriver:SetScript("OnUpdate",OnQMiniUpdate)
    else
        qMiniDriver:SetScript("OnUpdate",nil)
        UpdateMini(false)
    end
end

local QMINI_EVENTS={"PLAYER_STARTED_MOVING","PLAYER_STOPPED_MOVING","MINIMAP_UPDATE_ZOOM","CVAR_UPDATE"}
local function SyncQMiniEvents(on)
    if not qMiniDriver then return end
    for _,ev in ipairs(QMINI_EVENTS) do
        if on then pcall(qMiniDriver.RegisterEvent,qMiniDriver,ev) else pcall(qMiniDriver.UnregisterEvent,qMiniDriver,ev) end
    end
end

local function EnsureQMiniDriver()
    if qMiniDriver then return end
    qMiniDriver=CreateFrame("Frame")
    SyncQMiniEvents(Cfg().enabled==true)
    qMiniDriver:SetScript("OnEvent",function(_,ev,arg1)
        if not Cfg().enabled then return end
        if ev=="PLAYER_STARTED_MOVING" then
            qMiniMoving=true; SyncQMiniMotion()
        elseif ev=="PLAYER_STOPPED_MOVING" then
            qMiniMoving=false
            C_Timer.After(.12,function() if not qMiniMoving then SyncQMiniMotion() end end)
        elseif ev=="CVAR_UPDATE" then
            if Public(arg1) and arg1=="rotateMinimap" then SyncQMiniMotion() end
        else
            qLastPX=nil; UpdateMini(true); SyncQMiniMotion()
        end
    end)
    if not qMiniHookedZoom and Minimap then
        qMiniHookedZoom=true
        Minimap:HookScript("OnShow",function() if Cfg().enabled then qLastPX=nil; UpdateMini(true); SyncQMiniMotion() end end)
        Minimap:HookScript("OnHide",function() qMiniDriver:SetScript("OnUpdate",nil); HideMini() end)
        Minimap:HookScript("OnSizeChanged",function() if Cfg().enabled then qLastPX=nil; UpdateMini(true) end end)
    end
end

local function ConfigureMaps()
    local cfg=Cfg()
    if not cfg.enabled then
        if qMiniDriver then qMiniDriver:SetScript("OnUpdate",nil); SyncQMiniEvents(false) end
        HideMini(); HideWorld()
        return
    end
    EnsureQMiniDriver()
    SyncQMiniEvents(true)
    qLastPX=nil; qMiniMap=nil
    if WorldMapFrame and WorldMapFrame:IsShown() then Module.DrawWorld() end
    if cfg.enabled and cfg.minimap and Minimap and Minimap:IsShown() then
        qMiniMoving=(IsPlayerMoving and IsPlayerMoving()) and true or false
        UpdateMini(true)
        SyncQMiniMotion()
    else
        if qMiniDriver then qMiniDriver:SetScript("OnUpdate",nil) end
        HideMini()
    end
end

-- Unit & Item Tooltip Quest Objectives
-- Preserve native quest rows; append only quests not already represented.
local function TooltipHasQuest(tip,title)
    if not Public(title) or type(title)~="string" then return false end
    local name=tip.GetName and tip:GetName()
    if not Public(name) or type(name)~="string" or not tip.NumLines then return false end
    for i=1,tip:NumLines() do
        local line=_G[name.."TextLeft"..i]
        local text=line and line.GetText and line:GetText()
        if Public(text) and type(text)=="string" then
            text=text:gsub("|c%x%x%x%x%x%x%x%x",""):gsub("|r","")
            if text==title or text:find(title,1,true) then return true end
        end
    end
    return false
end

local function OnUnitTooltip(tip)
    if not tip or (tip.IsForbidden and tip:IsForbidden()) or not Cfg().enabled or not Cfg().tooltips then return end
    if activeCount<=0 or not W or not W.loaded then return end
    if not activeQuestNPCsBuilt then RebuildActiveQuestNPCIndex() end
    local _,unit=tip:GetUnit()
    if not Public(unit) or type(unit)~="string" then return end
    local guid=UnitGUID and UnitGUID(unit)
    if not Public(guid) or type(guid)~="string" then return end
    local npcID=tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
    if not npcID then return end
    local qids=activeQuestNPCs[npcID]
    if not qids then return end
    for i=1,#qids do
        local qid=qids[i]
        local aq=activeQuests[qid]
        if aq and not aq.complete and not TooltipHasQuest(tip,aq.title) then
            tip:AddLine("|cffffd670Quester:|r "..aq.title,1,.92,.72)
            for _,o in ipairs(aq.objs) do
                if not o.done then tip:AddLine("  - "..o.text,.85,.88,.94) end
            end
            local ne=GetNoteEntry(qid,false)
            if ne and type(ne.text)=="string" and ne.text~="" then
                tip:AddLine("  Note: "..ne.text,1,.90,.52,true)
            end
        end
    end
end

-- Minimalist collapsible floating Quest Tracker
local function RefreshTracker()
    local cfg=Cfg()
    if not cfg.enabled or not cfg.tracker then if tracker then tracker:Hide() end; return end
    if not tracker then
        tracker=CreateFrame("Frame","SmyrnaQuestTracker",UIParent,"BackdropTemplate")
        tracker:SetSize(250,260); tracker:SetPoint("TOPRIGHT",UIParent,"TOPRIGHT",-36,-220)
        tracker:SetMovable(true); tracker:EnableMouse(true); tracker:RegisterForDrag("LeftButton"); tracker:SetClampedToScreen(true)
        tracker:SetScript("OnDragStart",function(self) if not (InCombatLockdown and InCombatLockdown()) then self:StartMoving() end end)
        tracker:SetScript("OnDragStop",tracker.StopMovingOrSizing)
        Suite.StylePanel(tracker,true); Suite.HeaderStrip(tracker,28)
        local t=tracker:CreateFontString(nil,"OVERLAY","GameFontNormal"); t:SetPoint("TOPLEFT",10,-7); t:SetText("Smyrna Quests"); t:SetTextColor(1,.86,.48)
    end
    local pLvl=UnitLevel and UnitLevel("player")
    if not Num(pLvl,1,200) then pLvl=60 end
    local sorted={}
    for _,aq in pairs(activeQuests) do sorted[#sorted+1]=aq end
    table.sort(sorted,function(a,b) if a.level~=b.level then return a.level<b.level end return a.title<b.title end)
    local y,idx=34,0
    for _,aq in ipairs(sorted) do
        idx=idx+1
        local btn=trackerLines[idx]
        if not btn then
            btn=CreateFrame("Button",nil,tracker)
            btn:SetWidth(230); btn:RegisterForClicks("LeftButtonUp","RightButtonUp")
            btn:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
            local hl=btn:GetHighlightTexture(); if hl then hl:SetVertexColor(.92,.76,.36,.12) end
            btn.fs=btn:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
            btn.fs:SetPoint("TOPLEFT",0,0); btn.fs:SetWidth(228); btn.fs:SetJustifyH("LEFT")
            btn:SetScript("OnClick",function(self,mouseBtn)
                if not self.qid then return end
                if mouseBtn=="RightButton" then
                    Module.OpenParchment(self.qid)
                elseif SelectQuestLogEntry and self.logIndex then
                    pcall(SelectQuestLogEntry,self.logIndex)
                    if ToggleQuestLog and not (QuestLogFrame and QuestLogFrame:IsShown()) then pcall(ToggleQuestLog) end
                else
                    Module.OpenParchment(self.qid)
                end
            end)
            btn:SetScript("OnEnter",function(self)
                if not GameTooltip or (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then return end
                GameTooltip:SetOwner(self,"ANCHOR_LEFT")
                GameTooltip:SetText(self.qtitle or "Quest",1,.86,.48)
                GameTooltip:AddLine("Left-click: Open Quest Log  ·  Right-click: Quest Scroll & Chain",.75,.82,.92)
                GameTooltip:Show()
            end)
            btn:SetScript("OnLeave",HideSafeTip)
            trackerLines[idx]=btn
        end
        local hex=QuestDifficultyHex(aq.level,pLvl)
        local lines={"|cff"..hex.."["..aq.level.."]|r |cffffffff"..aq.title..(aq.complete and " |cff78d49b(Ready)|r" or "").."|r"}
        for _,o in ipairs(aq.objs) do
            lines[#lines+1]=(o.done and "|cff78d49b  [x] " or "|cffc8d0dc  - ")..o.text.."|r"
        end
        btn.qid=aq.id; btn.logIndex=aq.logIndex; btn.qtitle=aq.title
        btn.fs:SetText(table.concat(lines,"\n"))
        local h=math.max(14,(btn.fs:GetStringHeight() or 14)+2)
        btn:SetHeight(h); btn:ClearAllPoints(); btn:SetPoint("TOPLEFT",10,-y); btn:Show()
        y=y+h+6
        if idx>=12 then break end
    end
    for i=idx+1,#trackerLines do trackerLines[i]:Hide() end
    tracker:SetHeight(math.max(64,math.min(440,y+8)))
    tracker:Show()
end

-- ============================================================
-- Parchment Quest Chain & Details Viewer (Authentic WoW Parchment in Gilded Smyrna Frame)
-- ============================================================
local parchmentFrame,chainRows=nil,{}

local function BuildQuestChain(qid)
    local chain={}
    if not W or not W.Quest then return chain end
    local seen={}
    -- Walk backward along prerequisites (q.pg / q.ps) up to 8 steps
    local back={}
    local curID=qid
    for _=1,8 do
        local q=W.Quest(curID)
        if not q then break end
        local pre
        if q.pg and q.pg[1] and q.pg[1]>0 then pre=q.pg[1]
        elseif q.ps and q.ps[1] and q.ps[1]>0 then pre=q.ps[1] end
        if not pre or seen[pre] or pre==curID then break end
        seen[pre]=true
        table.insert(back,1,pre)
        curID=pre
    end
    for _,id in ipairs(back) do chain[#chain+1]=id end
    chain[#chain+1]=qid; seen[qid]=true
    -- Walk forward along next-quest pointers (q.nq) up to 8 steps
    curID=qid
    for _=1,8 do
        local q=W.Quest(curID)
        local nq=q and q.nq
        if not nq or nq<=0 or seen[nq] then break end
        seen[nq]=true
        chain[#chain+1]=nq
        curID=nq
    end
    return chain
end

local function EnsureParchment()
    if parchmentFrame then return parchmentFrame end
    local f=CreateFrame("Frame","SmyrnaQuestsParchment",UIParent,"BackdropTemplate")
    f:SetSize(400,520); f:SetPoint("CENTER"); f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetFrameLevel(165); f:SetClampedToScreen(true)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart",function(self) if not (InCombatLockdown and InCombatLockdown()) then self:StartMoving() end end)
    f:SetScript("OnDragStop",function(self) self:StopMovingOrSizing() end)
    Suite.StylePanel(f,true); Suite.HeaderStrip(f,36); Suite.CloseButton(f)
    local hTitle=f:CreateFontString(nil,"OVERLAY","GameFontNormal")
    hTitle:SetPoint("TOPLEFT",14,-11); hTitle:SetText("Smyrna Quest Details"); hTitle:SetTextColor(1,.86,.48)

    -- Obsidian & Gold container matching Smyrna Suite aesthetic
    local sheet=CreateFrame("Frame",nil,f,"BackdropTemplate")
    sheet:SetPoint("TOPLEFT",10,-42); sheet:SetPoint("BOTTOMRIGHT",-10,10)
    Suite.StyleCard(sheet,.055,.064,.090)
    f.sheet=sheet

    -- Top quest header card
    local headCard=CreateFrame("Frame",nil,sheet,"BackdropTemplate")
    headCard:SetPoint("TOPLEFT",10,-10); headCard:SetPoint("TOPRIGHT",-10,-10); headCard:SetHeight(144)
    Suite.StyleCard(headCard,.082,.094,.130)
    headCard:SetBackdropBorderColor(.82,.67,.34,.62)

    f.qTitle=headCard:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
    f.qTitle:SetPoint("TOPLEFT",12,-10); f.qTitle:SetPoint("TOPRIGHT",-12,-10); f.qTitle:SetJustifyH("LEFT"); f.qTitle:SetMaxLines(1); f.qTitle:SetTextColor(1,.86,.48)

    f.qMeta=headCard:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    f.qMeta:SetPoint("TOPLEFT",12,-32); f.qMeta:SetPoint("TOPRIGHT",-12,-32); f.qMeta:SetJustifyH("LEFT"); f.qMeta:SetTextColor(.74,.80,.88)

    local div1=headCard:CreateTexture(nil,"ARTWORK")
    div1:SetPoint("TOPLEFT",10,-50); div1:SetPoint("TOPRIGHT",-10,-50); div1:SetHeight(1)
    Suite.ApplyGradient(div1,"HORIZONTAL",.92,.76,.36,.65,.92,.76,.36,.06)

    f.qNPCs=headCard:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    f.qNPCs:SetPoint("TOPLEFT",12,-58); f.qNPCs:SetPoint("TOPRIGHT",-12,-58); f.qNPCs:SetJustifyH("LEFT"); f.qNPCs:SetSpacing(3); f.qNPCs:SetTextColor(.88,.91,.96)

    f.qObjText=headCard:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    f.qObjText:SetPoint("TOPLEFT",12,-94); f.qObjText:SetPoint("BOTTOMRIGHT",-12,8); f.qObjText:SetJustifyH("LEFT"); f.qObjText:SetJustifyV("TOP"); f.qObjText:SetSpacing(2); f.qObjText:SetTextColor(.82,.78,.68)

    f.chainHeader=sheet:CreateFontString(nil,"OVERLAY","GameFontNormal")
    f.chainHeader:SetPoint("TOPLEFT",12,-164); f.chainHeader:SetText("Quest Chain"); f.chainHeader:SetTextColor(.95,.80,.42)

    local div2=sheet:CreateTexture(nil,"ARTWORK")
    div2:SetPoint("TOPLEFT",12,-182); div2:SetPoint("TOPRIGHT",-12,-182); div2:SetHeight(1)
    Suite.ApplyGradient(div2,"HORIZONTAL",.92,.76,.36,.55,.92,.76,.36,.05)

    f.scroll=CreateFrame("ScrollFrame",nil,sheet,"UIPanelScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT",10,-188); f.scroll:SetPoint("BOTTOMRIGHT",-30,136)
    f.canvas=CreateFrame("Frame",nil,f.scroll); f.canvas:SetSize(336,140); f.scroll:SetScrollChild(f.canvas)
    f.scroll:EnableMouseWheel(true)
    f.scroll:SetScript("OnMouseWheel",function(self,delta)
        local cur,max=self:GetVerticalScroll(),self:GetVerticalScrollRange()
        if type(cur)=="number" and type(max)=="number" then self:SetVerticalScroll(math.max(0,math.min(max,cur-delta*32))) end
    end)

    -- Personal Quest Note & Custom Map Pins card (obsidian & gold)
    local noteCard=CreateFrame("Frame",nil,sheet,"BackdropTemplate")
    noteCard:SetPoint("BOTTOMLEFT",10,10); noteCard:SetPoint("BOTTOMRIGHT",-10,10); noteCard:SetHeight(118)
    Suite.StyleCard(noteCard,.074,.085,.118)
    noteCard:SetBackdropBorderColor(.82,.67,.34,.58)

    f.noteHeader=noteCard:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    f.noteHeader:SetPoint("TOPLEFT",10,-8); f.noteHeader:SetText("My Quest Note & Map Pins"); f.noteHeader:SetTextColor(1,.86,.48)

    local noteBox=CreateFrame("EditBox",nil,noteCard,"BackdropTemplate")
    noteBox:SetPoint("TOPLEFT",10,-26); noteBox:SetPoint("TOPRIGHT",-10,-26); noteBox:SetHeight(24)
    noteBox:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1,insets={left=2,right=2,top=2,bottom=2}})
    noteBox:SetBackdropColor(.035,.042,.062,.96); noteBox:SetBackdropBorderColor(.74,.60,.30,.72)
    noteBox:SetFontObject(ChatFontNormal); noteBox:SetTextColor(.95,.92,.84); noteBox:SetAutoFocus(false); noteBox:SetMaxLetters(240)
    noteBox:SetTextInsets(6,6,2,2)
    noteBox:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
    noteBox:SetScript("OnEnterPressed",function(self)
        if f.activeQID then
            Module.SetQuestNote(f.activeQID,self:GetText())
            Module.OpenParchment(f.activeQID)
        end
        self:ClearFocus()
    end)
    f.noteEdit=noteBox

    local function SayNote(msg)
        if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
            DEFAULT_CHAT_FRAME:AddMessage("|cffdfb66bSmyrna Quests:|r "..msg)
        end
    end

    local saveBtn=CreateFrame("Button",nil,noteCard,"UIPanelButtonTemplate")
    saveBtn:SetSize(78,22); saveBtn:SetPoint("TOPLEFT",10,-56); saveBtn:SetText("Save Note"); Suite.StyleButton(saveBtn)
    saveBtn:SetScript("OnClick",function()
        if not f.activeQID then return end
        noteBox:ClearFocus()
        Module.SetQuestNote(f.activeQID,noteBox:GetText())
        Module.OpenParchment(f.activeQID)
        SayNote("Saved note for quest #"..f.activeQID..".")
    end)

    local entBtn=CreateFrame("Button",nil,noteCard,"UIPanelButtonTemplate")
    entBtn:SetSize(86,22); entBtn:SetPoint("LEFT",saveBtn,"RIGHT",6,0); entBtn:SetText("+ Entrance"); Suite.StyleButton(entBtn)
    entBtn:SetScript("OnClick",function()
        if not f.activeQID then return end
        noteBox:ClearFocus()
        local lbl=TrimText(noteBox:GetText(),80)
        local ok,res=Module.AddQuestPin(f.activeQID,"entrance",lbl~="" and lbl or "Entrance")
        if ok then
            Module.OpenParchment(f.activeQID)
            SayNote(string.format("Marked entrance (%.1f, %.1f) for quest #%d.",res.x/10,res.y/10,f.activeQID))
        else
            SayNote(tostring(res or "Could not mark entrance here."))
        end
    end)
    Suite.AttachTooltip(entBtn,"Mark Entrance Here","Drop a custom Entrance pin on the World Map & Minimap at your current location for this quest.")

    local pinBtn=CreateFrame("Button",nil,noteCard,"UIPanelButtonTemplate")
    pinBtn:SetSize(84,22); pinBtn:SetPoint("LEFT",entBtn,"RIGHT",6,0); pinBtn:SetText("+ Note Pin"); Suite.StyleButton(pinBtn)
    pinBtn:SetScript("OnClick",function()
        if not f.activeQID then return end
        noteBox:ClearFocus()
        local lbl=TrimText(noteBox:GetText(),80)
        local ok,res=Module.AddQuestPin(f.activeQID,"note",lbl~="" and lbl or "Note")
        if ok then
            Module.OpenParchment(f.activeQID)
            SayNote(string.format("Dropped note pin (%.1f, %.1f) for quest #%d.",res.x/10,res.y/10,f.activeQID))
        else
            SayNote(tostring(res or "Could not drop pin here."))
        end
    end)
    Suite.AttachTooltip(pinBtn,"Drop Note Pin Here","Drop a custom Note marker on the World Map & Minimap at your current position.")

    local clrBtn=CreateFrame("Button",nil,noteCard,"UIPanelButtonTemplate")
    clrBtn:SetSize(74,22); clrBtn:SetPoint("LEFT",pinBtn,"RIGHT",6,0); clrBtn:SetText("Clear Pins"); Suite.StyleButton(clrBtn)
    clrBtn:SetScript("OnClick",function()
        if not f.activeQID then return end
        Module.ClearQuestPins(f.activeQID)
        Module.OpenParchment(f.activeQID)
    end)
    f.clearPinsBtn=clrBtn

    f.pinSummary=noteCard:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    f.pinSummary:SetPoint("TOPLEFT",10,-84); f.pinSummary:SetPoint("BOTTOMRIGHT",-10,6)
    f.pinSummary:SetJustifyH("LEFT"); f.pinSummary:SetJustifyV("TOP"); f.pinSummary:SetTextColor(.70,.76,.86)

    UISpecialFrames[#UISpecialFrames+1]="SmyrnaQuestsParchment"
    f:Hide()
    parchmentFrame=f
    return f
end

local function ResolveEntityGroupName(group)
    if type(group)~="table" or not W then return "Unknown" end
    if type(group[1])=="table" and group[1][1] then
        local n=W.Npc and W.Npc(group[1][1])
        if n and n.n then return n.n end
    end
    if type(group[2])=="table" and group[2][1] then
        local o=W.Object and W.Object(group[2][1])
        if o and o.n then return o.n.." (Object)" end
    end
    if type(group[3])=="table" and group[3][1] then
        local it=W.Item and W.Item(group[3][1])
        if it and it.n then return it.n.." (Item)" end
    end
    return "Unknown"
end

function Module.OpenParchment(qid)
    if not qid then return end
    local q=W and W.Quest and W.Quest(qid) or nil
    local aq=activeQuests[qid]
    if not q and not aq then return end
    q=q or {n=aq.title,ql=aq.level,rl=aq.level}
    local f=EnsureParchment()
    f.activeQID=qid
    local done=IsCompleted(qid)
    local active=activeQuests[qid]~=nil
    local statusTxt=done and "|cff55d86e[Completed]|r" or (active and "|cff7cc4ff[In Quest Log]|r" or "|cffffd670[Available]|r")
    f.qTitle:SetText((q.n or ("Quest #"..qid)))
    f.qMeta:SetText(string.format("Level %d  ·  Req %d%s  ·  %s",q.ql or 0,q.rl or 0,q.xp and ("  ·  "..q.xp.." XP") or "",statusTxt))

    local startName=ResolveEntityGroupName(q.sb)
    local endName=ResolveEntityGroupName(q.fb)
    f.qNPCs:SetText("|cffdfb66bStarts at:|r "..startName.."\n|cffdfb66bTurns in at:|r "..endName)

    local objTxt=(type(q.ot)=="table" and type(q.ot[1])=="string" and q.ot[1]~="") and q.ot[1] or ""
    if objTxt=="" and aq and type(aq.objs)=="table" and #aq.objs>0 then
        local lines={}
        for i=1,math.min(#aq.objs,2) do lines[#lines+1]=aq.objs[i].text end
        objTxt=table.concat(lines,"  ·  ")
    end
    f.qObjText:SetText(objTxt)

    local chain=BuildQuestChain(qid)
    f.chainHeader:SetText(#chain>1 and ("Quest Chain ("..#chain.." steps — click any step)") or "Standalone Quest")
    for i,cid in ipairs(chain) do
        local row=chainRows[i]
        if not row then
            row=CreateFrame("Button",nil,f.canvas,"BackdropTemplate")
            row:SetSize(332,28)
            row:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1,insets={left=1,right=1,top=1,bottom=1}})
            row:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
            local hl=row:GetHighlightTexture(); if hl then hl:SetVertexColor(.92,.76,.36,.16) end
            row.txt=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
            row.txt:SetPoint("LEFT",8,0); row.txt:SetWidth(252); row.txt:SetJustifyH("LEFT"); row.txt:SetMaxLines(1)
            row.tag=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
            row.tag:SetPoint("RIGHT",-8,0); row.tag:SetJustifyH("RIGHT")
            row:SetScript("OnClick",function(self) if self.qid then Module.OpenParchment(self.qid) end end)
            chainRows[i]=row
        end
        local cq=W.Quest(cid)
        local cDone=IsCompleted(cid)
        local cAct=activeQuests[cid]~=nil
        local isSel=(cid==qid)
        row.qid=cid
        row:ClearAllPoints(); row:SetPoint("TOPLEFT",0,-(i-1)*32)
        if isSel then
            row:SetBackdropColor(.16,.13,.08,.96); row:SetBackdropBorderColor(.92,.76,.36,.95)
            row.txt:SetTextColor(1,.90,.62)
        else
            row:SetBackdropColor(.078,.090,.124,.92); row:SetBackdropBorderColor(.28,.32,.40,.65)
            row.txt:SetTextColor(.86,.89,.94)
        end
        row.txt:SetText(string.format("%d. [%d] %s",i,(cq and (cq.ql or cq.rl) or 0),(cq and cq.n) or ("Quest #"..cid)))
        if cDone then row.tag:SetText("|cff55d86eDone|r")
        elseif cAct then row.tag:SetText("|cff7cc4ffActive|r")
        else row.tag:SetText("|cffffd670Next|r") end
        row:Show()
    end
    for i=#chain+1,#chainRows do chainRows[i]:Hide() end
    f.canvas:SetHeight(math.max(120,#chain*32+8))
    f.scroll:UpdateScrollChildRect()

    local ne=GetNoteEntry(qid,false)
    f.noteEdit:SetText(ne and ne.text or "")
    f.noteEdit:SetCursorPosition(0)
    local pList=ne and ne.pins or {}
    f.noteHeader:SetText(#pList>0 and ("My Quest Note & Map Pins ("..#pList.." saved)") or "My Quest Note & Map Pins")
    f.clearPinsBtn:SetShown(#pList>0)
    if #pList>0 then
        local parts={}
        for i=1,math.min(#pList,3) do
            local p=pList[i]
            parts[#parts+1]=string.format("|cffffd670%s|r (%.1f, %.1f)",p.label or p.kind,(p.x or 0)/10,(p.y or 0)/10)
        end
        if #pList>3 then parts[#parts+1]="+"..(#pList-3).." more" end
        f.pinSummary:SetText("Pins: "..table.concat(parts,"  ·  "))
    else
        f.pinSummary:SetText("Write a note or mark a cave/dungeon entrance at your current spot.")
    end
    f:Show()
end

-- Hub Quests Tab UI
local function MakeQuestRow(i)
    local r=CreateFrame("Button",nil,canvas,"BackdropTemplate")
    r:SetSize(786,38)
    Suite.StyleCard(r,.078,.090,.124)
    r:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    local hl=r:GetHighlightTexture(); if hl then hl:SetVertexColor(.92,.76,.36,.14) end
    r.title=r:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    r.title:SetPoint("TOPLEFT",10,-5); r.title:SetWidth(480); r.title:SetJustifyH("LEFT"); r.title:SetMaxLines(1)
    r.sub=r:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    r.sub:SetPoint("TOPLEFT",10,-21); r.sub:SetWidth(640); r.sub:SetJustifyH("LEFT"); r.sub:SetMaxLines(1); r.sub:SetTextColor(.70,.76,.86)
    r.xp=r:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    r.xp:SetPoint("RIGHT",-12,0); r.xp:SetJustifyH("RIGHT"); r.xp:SetTextColor(1,.86,.48)
    r:SetScript("OnClick",function(self) if self.qid then Module.OpenParchment(self.qid) end end)
    questRows[i]=r
    return r
end

function Module.RefreshUI()
    if not window or not window:IsShown() then return end
    local cfg=Cfg()
    for k,cb in pairs(checks) do cb:SetChecked(cfg[k] and true or false) end
    local mapID=C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local info=mapID and C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    local zoneName=info and info.name or "Current zone"
    local list={}
    local completedZone=0
    local pLvl,rBit,cBit=PlayerMasks()
    local showLow=(cfg.visibility=="all") or cfg.lowLevel
    if mapID and W and W.Ensure and W.Ensure() then
        local z=W.Zone(mapID)
        for _,qid in ipairs((z and z.q) or {}) do
            if IsCompleted(qid) then
                completedZone=completedZone+1
            elseif cfg.visibility~="active" then
                local q=W.Quest(qid)
                if IsQuestAvailable(qid,q,pLvl,rBit,cBit,showLow,cfg.seasonal) then
                    local giver=""
                    if q.sb and q.sb[1] and q.sb[1][1] then
                        local npc=W.Npc(q.sb[1][1]); giver=npc and npc.n or ""
                    end
                    local isChain=((q.pg and #q.pg>0) or (q.ps and #q.ps>0) or (q.nq and q.nq>0)) and true or false
                    local isSeasonal=IsSeasonalQuest(q)
                    local hasNote=GetNoteEntry(qid,false)~=nil
                    list[#list+1]={id=qid,name=q.n,level=q.ql or q.rl or 0,xp=q.xp,giver=giver,isChain=isChain,isSeasonal=isSeasonal,hasNote=hasNote}
                end
            end
        end
        table.sort(list,function(a,b)
            if (a.isSeasonal and true or false)~=(b.isSeasonal and true or false) then return not a.isSeasonal end
            if a.level~=b.level then return a.level<b.level end
            return a.name<b.name
        end)
    end
    statusLabel:SetText(string.format("%s: %d available  ·  %d completed  ·  %d active in log  (click any quest to view its parchment chain)",zoneName,#list,completedZone,activeCount))
    local shown=math.min(#list,100)
    for i=1,math.max(shown,#questRows) do
        local e=i<=shown and list[i] or nil
        local row=questRows[i] or MakeQuestRow(i)
        if e then
            local hex=QuestDifficultyHex(e.level,pLvl)
            row.qid=e.id
            row:ClearAllPoints(); row:SetPoint("TOPLEFT",0,-(i-1)*42)
            local chainTag=e.isChain and "  |cff8ecfff[Chain]|r" or ""
            local seasTag=e.isSeasonal and "  |cffffa64d[Seasonal]|r" or ""
            local noteTag=e.hasNote and "  |cff7cd4ff[Note]|r" or ""
            row.title:SetText("|cff"..hex.."["..e.level.."]|r "..e.name..chainTag..seasTag..noteTag); row.title:SetTextColor(1,.90,.62)
            row.sub:SetText(e.giver~="" and ("Quest giver: "..e.giver) or ("Quest #"..e.id))
            row.xp:SetText(e.xp and (e.xp.." XP") or "")
            row:Show()
        else
            row:Hide()
        end
    end
    canvas:SetHeight(math.max(330,shown*42))
    scroll:UpdateScrollChildRect()
end

function Module.Open()
    if not window then
        questRows={}; checks={}
        window=CreateFrame("Frame","SmyrnaQuestsWindow",UIParent,"BackdropTemplate")
        window:SetSize(840,590); window:SetPoint("CENTER"); window:SetFrameStrata("DIALOG"); window:SetClampedToScreen(true)
        Suite.StylePanel(window,true)
        local close=Suite.CloseButton(window); window.SuiteCloseButton=close
        local title=window:CreateFontString(nil,"OVERLAY","GameFontNormalLarge"); title:SetPoint("TOPLEFT",16,-14); title:SetText("Smyrna Quests"); title:SetTextColor(1,.86,.48)
        local sub=window:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); sub:SetPoint("TOPLEFT",16,-36); sub:SetText("Zone-indexed map & minimap quest pins, objective tooltips, and optional compact tracker backed by SmyrnaWorldDB."); sub:SetTextColor(.70,.75,.84)

        local function AddCheck(key,text,tipBody,x,y)
            local cb=CreateFrame("CheckButton",nil,window,"UICheckButtonTemplate"); cb:SetPoint("TOPLEFT",x,y)
            local lbl=cb:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); lbl:SetPoint("LEFT",cb,"RIGHT",2,0); lbl:SetText(text)
            cb:SetScript("OnClick",function(self)
                Cfg()[key]=self:GetChecked() and true or false
                ConfigureMaps(); RefreshTracker(); Module.RefreshUI()
            end)
            Suite.AttachTooltip(cb,text,tipBody,lbl)
            checks[key]=cb
        end
        AddCheck("enabled","Enabled","Turn Smyrna Quests on or off immediately without reloading.",16,-58)
        AddCheck("worldMap","World Map","Show available, active, and turn-in quest pins on the World Map (auto-offset from Field Diary nodes).",116,-58)
        AddCheck("minimap","Minimap","Show nearby quest pins around your Minimap.",236,-58)
        AddCheck("lowLevel","Low-level","Include trivial (gray) quests below your green-quest range cutoff.",344,-58)
        AddCheck("tooltips","Tooltips","Append active quest objective progress when hovering quest creatures.",458,-58)
        AddCheck("tracker","Tracker","Show a compact, draggable floating tracker for your active quests.",564,-58)
        AddCheck("autoQuest","Auto accept/turn-in","Automatically accept quests and turn in single-reward quests (hold Shift to bypass).",668,-58)
        AddCheck("seasonal","Seasonal","Show seasonal / holiday event quests (e.g. Lunar Festival) in their own section and on the map.",16,-78)

        local visBtn=CreateFrame("Button",nil,window,"UIPanelButtonTemplate")
        visBtn:SetSize(164,22); visBtn:SetPoint("TOPRIGHT",-46,-14); Suite.StyleButton(visBtn)
        local function UpdateVisBtn()
            local v=Cfg().visibility or (Cfg().lowLevel and "all" or "range")
            local lbl=(v=="active" and "Active Only") or (v=="all" and "All (+Low)") or "In Range"
            visBtn:SetText("Quests: "..lbl)
        end
        visBtn:SetScript("OnClick",function()
            local c=Cfg()
            local v=c.visibility or (c.lowLevel and "all" or "range")
            if v=="range" then c.visibility="all"; c.lowLevel=true
            elseif v=="all" then c.visibility="active"; c.lowLevel=false
            else c.visibility="range"; c.lowLevel=false end
            UpdateVisBtn(); ConfigureMaps(); RefreshTracker(); Module.RefreshUI()
        end)
        Suite.AttachTooltip(visBtn,"Quest Visibility","Cycle quest visibility across the list, World Map, and Minimap: In Range / All (+Low) / Active Only.")
        UpdateVisBtn()

        Suite.OptionSection(window,"Available Quests in Your Current Zone",16,-96,808)
        statusLabel=window:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); statusLabel:SetPoint("TOPLEFT",18,-114); statusLabel:SetWidth(800); statusLabel:SetJustifyH("LEFT"); statusLabel:SetTextColor(.74,.80,.88)

        scroll=CreateFrame("ScrollFrame",nil,window,"UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT",16,-136); scroll:SetSize(792,438)
        canvas=CreateFrame("Frame",nil,scroll); canvas:SetSize(786,412); scroll:SetScrollChild(canvas)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel",function(self,delta)
            local cur,max=self:GetVerticalScroll(),self:GetVerticalScrollRange()
            if type(cur)=="number" and type(max)=="number" then self:SetVerticalScroll(math.max(0,math.min(max,cur-delta*42))) end
        end)

        window:SetScript("OnShow",function() RefreshActiveQuests(); Module.RefreshUI() end)
        UISpecialFrames[#UISpecialFrames+1]="SmyrnaQuestsWindow"
    end
    RefreshActiveQuests()
    window:Show(); Module.RefreshUI()
    return window
end

local autoDriver=CreateFrame("Frame")
local AUTO_EVENTS={"QUEST_DETAIL","QUEST_PROGRESS","QUEST_COMPLETE"}
local function SyncAutoEvents(on)
    for _,ev in ipairs(AUTO_EVENTS) do
        if on then pcall(autoDriver.RegisterEvent,autoDriver,ev) else pcall(autoDriver.UnregisterEvent,autoDriver,ev) end
    end
end
SyncAutoEvents(Cfg().enabled==true)
autoDriver:SetScript("OnEvent",function(_,event)
    local cfg=Cfg()
    if not cfg.enabled or not cfg.autoQuest then return end
    if IsShiftKeyDown and IsShiftKeyDown() then return end
    if event=="QUEST_DETAIL" then
        if AcceptQuest then AcceptQuest() end
    elseif event=="QUEST_PROGRESS" then
        if IsQuestCompletable and IsQuestCompletable() and CompleteQuest then CompleteQuest() end
    elseif event=="QUEST_COMPLETE" then
        local choices=GetNumQuestChoices and GetNumQuestChoices() or 0
        if choices<=1 and GetQuestReward then GetQuestReward(1) end
    end
end)

local function HookAll()
    if not mapHooked and WorldMapFrame and WorldMapFrame.GetCanvas then
        mapHooked=true
        WorldMapFrame:HookScript("OnShow",Module.DrawWorld)
        WorldMapFrame:HookScript("OnHide",HideWorld)
        if hooksecurefunc then
            if WorldMapFrame.SetMapID then hooksecurefunc(WorldMapFrame,"SetMapID",Module.DrawWorld) end
            if WorldMapFrame.OnCanvasScaleChanged then
                hooksecurefunc(WorldMapFrame,"OnCanvasScaleChanged",function()
                    if Module.RepositionWorld then Module.RepositionWorld() else Module.DrawWorld() end
                end)
            end
        end
        local canvasF=WorldMapFrame:GetCanvas()
        if canvasF then canvasF:HookScript("OnSizeChanged",Module.DrawWorld) end
        -- Quick Questie-style World Map toggle pill matching Smyrna's gold/dark palette
        local mapBtn=CreateFrame("Button","SmyrnaQuestsMapToggle",WorldMapFrame,"UIPanelButtonTemplate")
        mapBtn:SetSize(76,20); mapBtn:SetPoint("TOPRIGHT",WorldMapFrame,"TOPRIGHT",-38,-4)
        mapBtn:SetFrameLevel((WorldMapFrame:GetFrameLevel() or 1)+25)
        mapBtn:RegisterForClicks("LeftButtonUp","RightButtonUp")
        Suite.StyleButton(mapBtn)
        local function UpdateMapBtn()
            local cfg=Cfg()
            mapBtn:SetText(cfg.worldMap and "Quests: On" or "Quests: Off")
            Suite.SetButtonSelected(mapBtn,cfg.worldMap==true)
        end
        mapBtn:SetScript("OnClick",function(_,btn)
            local cfg=Cfg()
            if btn=="RightButton" then cfg.lowLevel=not cfg.lowLevel else cfg.worldMap=not cfg.worldMap end
            UpdateMapBtn(); ConfigureMaps(); Module.RefreshUI()
        end)
        mapBtn:SetScript("OnEnter",function(self)
            if not GameTooltip or (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then return end
            local cfg=Cfg()
            GameTooltip:SetOwner(self,"ANCHOR_BOTTOMLEFT")
            GameTooltip:SetText("Smyrna Quests Map Filter",1,.86,.48)
            GameTooltip:AddLine("Left-click: Toggle World Map pins ("..(cfg.worldMap and "On" or "Off")..")",.85,.90,.96)
            GameTooltip:AddLine("Right-click: Toggle trivial Low-Level quests ("..(cfg.lowLevel and "Shown" or "Hidden")..")",.85,.90,.96)
            GameTooltip:Show()
        end)
        mapBtn:SetScript("OnLeave",HideSafeTip)
        UpdateMapBtn()
    end
    if not tipHooked then
        tipHooked=true
        if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit,function(tip) if tip==GameTooltip then OnUnitTooltip(tip) end end)
        elseif GameTooltip and GameTooltip:HasScript("OnTooltipSetUnit") then
            GameTooltip:HookScript("OnTooltipSetUnit",OnUnitTooltip)
        end
    end
end

local logPending,logGen=false,0
ApplyQuestRefresh=function()
    if not Cfg().enabled then return end
    RefreshActiveQuests(); qLastPX=nil; qMiniMap=nil; UpdateMini(true)
    if WorldMapFrame and WorldMapFrame:IsShown() then Module.DrawWorld() end
    RefreshTracker()
    if window and window:IsShown() then Module.RefreshUI() end
end

local driver=CreateFrame("Frame")
local DRIVER_EVENTS={"QUEST_LOG_UPDATE","ZONE_CHANGED_NEW_AREA","PLAYER_LEVEL_UP"}
local function SyncQuestDriverEvents(on)
    for _,ev in ipairs(DRIVER_EVENTS) do
        if on then pcall(driver.RegisterEvent,driver,ev) else pcall(driver.UnregisterEvent,driver,ev) end
    end
end

function Module.SetEnabled(on)
    local en=on and true or false
    Cfg().enabled=en
    SyncQuestDriverEvents(en)
    SyncAutoEvents(en)
    ConfigureMaps()
    RefreshTracker()
    if en then
        RefreshActiveQuests()
        Module.RefreshUI()
        local mb=_G.SmyrnaQuestsMapToggle; if mb and mb.Show then mb:Show() end
    else
        logPending=false
        if window and window.Hide then window:Hide() end
        if parchmentFrame and parchmentFrame.Hide then parchmentFrame:Hide() end
        local mb=_G.SmyrnaQuestsMapToggle; if mb and mb.Hide then mb:Hide() end
    end
end

driver:RegisterEvent("PLAYER_LOGIN")
SyncQuestDriverEvents(Cfg().enabled==true)
driver:SetScript("OnEvent",function(self,event)
    if event=="PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        HookAll(); RefreshActiveQuests(); ConfigureMaps(); RefreshTracker()
    elseif not Cfg().enabled then
        return
    elseif event=="QUEST_LOG_UPDATE" then
        -- Coalesce bursty QUEST_LOG_UPDATE events before rebuilding zone/city pins.
        logGen=logGen+1
        if C_Timer and C_Timer.After then
            if not logPending then
                logPending=true
                C_Timer.After(.2,function()
                    logPending=false
                    ApplyQuestRefresh()
                end)
            end
        else
            ApplyQuestRefresh()
        end
    else
        logGen=logGen+1; logPending=false
        ApplyQuestRefresh()
    end
end)

SLASH_SMYRNAQUESTS1="/sq"
SLASH_SMYRNAQUESTS2="/smyrnaquests"
SlashCmdList.SMYRNAQUESTS=function() Module.Open() end

Suite.Loaded[name]=true
Module.Perf=function() if Suite.Memory then Suite.Memory() end end
