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
    return c
end
Module.Config=Cfg

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
end

local function IsQuestAvailable(qid,q,playerLvl,raceBit,classBit,showLow)
    if not q or not q.n then return false end
    if activeQuests[qid] or IsCompleted(qid) then return false end
    if (q.rl or 0)>playerLvl then return false end
    if q.ml and q.ml>0 and playerLvl>q.ml then return false end
    if not showLow and (q.ql or playerLvl)>0 and (q.ql or playerLvl)<(playerLvl-8) then return false end
    if not MaskAllows(q.rc,raceBit) then return false end
    if not MaskAllows(q.cl,classBit) then return false end
    -- Skip event/monthly special flags (bit 4/64) unless normal
    if q.sp and bit and bit.band and bit.band(q.sp,64)~=0 then return false end
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

-- Collect pins for a specific uiMapID using the O(1) precomputed X-Z-<mapID> reverse index!
local function CollectZonePins(mapID)
    local pins,clusters={},{}
    if not W or not W.Ensure or not W.Ensure() then return pins end
    local cfg=Cfg()
    local playerLvl,raceBit,classBit=PlayerMasks()
    local function AddPin(kind,x10,y10,qid,title,level,who,detail)
        if not x10 or not y10 or x10<0 or x10>1000 or y10<0 or y10>1000 then return end
        local cx,cy=math.floor(x10/18),math.floor(y10/18)
        local ckey=kind..":"..cx..":"..cy
        local c=clusters[ckey]
        if not c then
            c={kind=kind,x=x10/1000,y=y10/1000,items={}}
            clusters[ckey]=c; pins[#pins+1]=c
        end
        if #c.items<8 then
            c.items[#c.items+1]={id=qid,title=title,level=level,who=who,detail=detail}
        end
    end

    local function PlaceEntityGroup(group,kind,qid,title,level,detail)
        if type(group)~="table" then return end
        local npcs=group[1]
        if type(npcs)=="table" then
            for _,nid in ipairs(npcs) do
                local npc=W.Npc(nid)
                local pts=npc and npc.sp and npc.sp[mapID]
                if pts and pts[1] then
                    AddPin(kind,pts[1][1],pts[1][2],qid,title,level,npc.n,detail)
                end
            end
        end
        local objs=group[2]
        if type(objs)=="table" then
            for _,oid in ipairs(objs) do
                local obj=W.Object(oid)
                local pts=obj and obj.sp and obj.sp[mapID]
                if pts and pts[1] then
                    AddPin(kind,pts[1][1],pts[1][2],qid,title,level,obj.n,detail)
                end
            end
        end
    end

    -- 1. Active quests: turn-ins (if complete) or objective targets (if in progress)
    for qid,aq in pairs(activeQuests) do
        local q=W.Quest(qid)
        if q then
            if aq.complete then
                PlaceEntityGroup(q.fb,"turnin",qid,aq.title,aq.level,"Ready to turn in")
            else
                -- Plot incomplete creature/object/item objective targets on this map
                local ob=q.ob
                if type(ob)=="table" then
                    if type(ob[1])=="table" then
                        for _,entry in ipairs(ob[1]) do
                            local nid=type(entry)=="table" and entry[1] or entry
                            local npc=W.Npc(nid); local pts=npc and npc.sp and npc.sp[mapID]
                            if pts then for k=1,math.min(#pts,3) do AddPin("obj",pts[k][1],pts[k][2],qid,aq.title,aq.level,npc.n,"Objective") end end
                        end
                    end
                    if type(ob[2])=="table" then
                        for _,entry in ipairs(ob[2]) do
                            local oid=type(entry)=="table" and entry[1] or entry
                            local obj=W.Object(oid); local pts=obj and obj.sp and obj.sp[mapID]
                            if pts then for k=1,math.min(#pts,3) do AddPin("obj",pts[k][1],pts[k][2],qid,aq.title,aq.level,obj.n,"Objective") end end
                        end
                    end
                    if type(ob[3])=="table" then
                        for _,entry in ipairs(ob[3]) do
                            local iid=type(entry)=="table" and entry[1] or entry
                            local it=W.Item(iid)
                            if it and it.nd then
                                for k=1,math.min(#it.nd,3) do
                                    local npc=W.Npc(it.nd[k]); local pts=npc and npc.sp and npc.sp[mapID]
                                    if pts and pts[1] then AddPin("obj",pts[1][1],pts[1][2],qid,aq.title,aq.level,npc.n,it.n and ("Drops: "..it.n) or "Quest item") end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    -- 2. Available quests in this zone (O(1) lookup via X-Z-<mapID>!)
    local z=W.Zone(mapID)
    if z and z.q then
        for _,qid in ipairs(z.q) do
            local q=W.Quest(qid)
            if IsQuestAvailable(qid,q,playerLvl,raceBit,classBit,cfg.lowLevel) then
                local kind=(q.sp and bit and bit.band and bit.band(q.sp,1)~=0) and "repeat" or "avail"
                PlaceEntityGroup(q.sb,kind,qid,q.n,q.ql or q.rl or 0,q.xp and (q.xp.." XP") or nil)
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
}

local function ShowPinTooltip(owner,cluster)
    if not GameTooltip or (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then return end
    GameTooltip:SetOwner(owner,"ANCHOR_RIGHT")
    local head=cluster.kind=="turnin" and "Quest Turn-In" or cluster.kind=="obj" and "Quest Objective" or "Available Quest"
    GameTooltip:SetText(head,1,.86,.48)
    for _,it in ipairs(cluster.items) do
        local lvl=it.level and it.level>0 and ("["..it.level.."] ") or ""
        GameTooltip:AddLine(lvl..(it.title or "Quest"),1,1,1)
        if it.who then GameTooltip:AddLine("  "..it.who..(it.detail and (" - "..it.detail) or ""),.64,.84,1) end
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

local function HideWorld() for _,p in ipairs(worldPins) do p:Hide() end end
function Module.RepositionWorld()
    if not WorldMapFrame or not WorldMapFrame:IsShown() then return end
    local canvasF=WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
    if not canvasF then return end
    local width,height=canvasF:GetWidth(),canvasF:GetHeight()
    local zoom=WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale() or 1
    if not Num(zoom,.01,100) then zoom=1 end
    local scale=1/zoom
    for _,pin in ipairs(worldPins) do
        if pin:IsShown() and pin.cluster then
            local px,py=AvoidDiaryCollision(pin.cluster.x*width,-pin.cluster.y*height,Suite.DiaryWorldPts,16*scale,15*scale,7*scale)
            pin:ClearAllPoints(); pin:SetPoint("CENTER",canvasF,"TOPLEFT",px/scale,py/scale)
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
    local level=canvasF:GetFrameLevel()+27
    local list=CollectZonePins(mapID)
    for i=1,math.min(#list,80) do
        local c=list[i]; local pin=worldPins[i]
        if not pin then
            pin=CreateFrame("Frame",nil,canvasF); pin:SetSize(16,16); pin:EnableMouse(true)
            pin.tex=pin:CreateTexture(nil,"OVERLAY"); pin.tex:SetAllPoints()
            pin:SetScript("OnEnter",function(self) if self.cluster then ShowPinTooltip(self,self.cluster) end end)
            pin:SetScript("OnLeave",HideSafeTip)
            worldPins[i]=pin
        end
        pin.cluster=c; pin:SetParent(canvasF); pin:SetFrameLevel(level); pin:SetScale(scale)
        pin.tex:SetTexture(PIN_ICONS[c.kind] or PIN_ICONS.avail)
        local px,py=AvoidDiaryCollision(c.x*width,-c.y*height,Suite.DiaryWorldPts,16*scale,15*scale,7*scale)
        pin:ClearAllPoints(); pin:SetPoint("CENTER",canvasF,"TOPLEFT",px/scale,py/scale)
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
            if shown>=28 then break end
        end
    end
    for i=shown+1,#miniPins do
        local p=miniPins[i]
        if p:IsShown() then p:Hide(); p.mx=nil; p.my=nil end
    end
end

local function OnQMiniUpdate(_,elapsed)
    if qMiniMoving then
        UpdateMini(false)
    else
        qRotAcc=qRotAcc+(elapsed or 0)
        if qRotAcc>=.12 then qRotAcc=0; UpdateMini(false) end
    end
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

local function EnsureQMiniDriver()
    if qMiniDriver then return end
    qMiniDriver=CreateFrame("Frame")
    qMiniDriver:RegisterEvent("PLAYER_STARTED_MOVING")
    qMiniDriver:RegisterEvent("PLAYER_STOPPED_MOVING")
    qMiniDriver:RegisterEvent("MINIMAP_UPDATE_ZOOM")
    qMiniDriver:RegisterEvent("CVAR_UPDATE")
    qMiniDriver:SetScript("OnEvent",function(_,ev,arg1)
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
        Minimap:HookScript("OnShow",function() qLastPX=nil; UpdateMini(true); SyncQMiniMotion() end)
        Minimap:HookScript("OnHide",function() qMiniDriver:SetScript("OnUpdate",nil); HideMini() end)
        Minimap:HookScript("OnSizeChanged",function() qLastPX=nil; UpdateMini(true) end)
    end
end

local function ConfigureMaps()
    local cfg=Cfg()
    EnsureQMiniDriver()
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
local function OnUnitTooltip(tip)
    if not tip or (tip.IsForbidden and tip:IsForbidden()) or not Cfg().enabled or not Cfg().tooltips then return end
    local _,unit=tip:GetUnit()
    if not Public(unit) or type(unit)~="string" then return end
    local guid=UnitGUID and UnitGUID(unit)
    if not Public(guid) or type(guid)~="string" then return end
    local npcID=tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
    if not npcID or not W or not W.loaded then return end
    for qid,aq in pairs(activeQuests) do
        if not aq.complete then
            local q=W.Quest(qid)
            local matched=false
            if q and type(q.ob)=="table" then
                if type(q.ob[1])=="table" then
                    for _,e in ipairs(q.ob[1]) do if (type(e)=="table" and e[1] or e)==npcID then matched=true; break end end
                end
                if not matched and type(q.ob[3])=="table" then
                    for _,e in ipairs(q.ob[3]) do
                        local it=W.Item(type(e)=="table" and e[1] or e)
                        if it and it.nd then for _,dn in ipairs(it.nd) do if dn==npcID then matched=true; break end end end
                        if matched then break end
                    end
                end
            end
            if matched then
                tip:AddLine("|cffffd670Quest:|r "..aq.title,1,.92,.72)
                for _,o in ipairs(aq.objs) do
                    if not o.done then tip:AddLine("  - "..o.text,.85,.88,.94) end
                end
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
    local sorted={}
    for _,aq in pairs(activeQuests) do sorted[#sorted+1]=aq end
    table.sort(sorted,function(a,b) if a.level~=b.level then return a.level<b.level end return a.title<b.title end)
    local y,idx=34,0
    for _,aq in ipairs(sorted) do
        idx=idx+1
        local fs=trackerLines[idx]
        if not fs then
            fs=tracker:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
            fs:SetWidth(228); fs:SetJustifyH("LEFT"); trackerLines[idx]=fs
        end
        local lines={"|cffffd670["..aq.level.."] "..aq.title..(aq.complete and " |cff78d49b(Ready)|r" or "").."|r"}
        for _,o in ipairs(aq.objs) do
            lines[#lines+1]=(o.done and "|cff78d49b  [x] " or "|cffc8d0dc  - ")..o.text.."|r"
        end
        fs:ClearAllPoints(); fs:SetPoint("TOPLEFT",10,-y); fs:SetText(table.concat(lines,"\n")); fs:Show()
        y=y+(fs:GetStringHeight() or 14)+8
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
    f:SetSize(430,450); f:SetPoint("CENTER"); f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetFrameLevel(165); f:SetClampedToScreen(true)
    f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart",function(self) if not (InCombatLockdown and InCombatLockdown()) then self:StartMoving() end end)
    f:SetScript("OnDragStop",function(self) self:StopMovingOrSizing() end)
    Suite.StylePanel(f,true); Suite.HeaderStrip(f,38); Suite.CloseButton(f)
    local hTitle=f:CreateFontString(nil,"OVERLAY","GameFontNormal")
    hTitle:SetPoint("TOPLEFT",14,-12); hTitle:SetText("Smyrna Quest Scroll"); hTitle:SetTextColor(1,.86,.48)

    -- Aged WoW parchment sheet inside the gilded frame
    local sheet=CreateFrame("Frame",nil,f,"BackdropTemplate")
    sheet:SetPoint("TOPLEFT",10,-42); sheet:SetPoint("BOTTOMRIGHT",-10,10)
    sheet:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1,insets={left=1,right=1,top=1,bottom=1}})
    sheet:SetBackdropColor(.93,.87,.72,1)
    sheet:SetBackdropBorderColor(.58,.44,.24,.92)
    local pTex=sheet:CreateTexture(nil,"BACKGROUND",nil,1)
    pTex:SetAllPoints()
    if pTex:SetTexture("Interface\\QuestFrame\\UI-QuestLog-BookBg")==false then
        pTex:SetColorTexture(.93,.87,.72,1)
    else
        pTex:SetTexCoord(0,.62,0,.78); pTex:SetAlpha(.45)
    end
    f.sheet=sheet

    f.qTitle=sheet:CreateFontString(nil,"OVERLAY","QuestTitleFont")
    if not f.qTitle then f.qTitle=sheet:CreateFontString(nil,"OVERLAY","GameFontNormalLarge") end
    f.qTitle:SetPoint("TOPLEFT",16,-14); f.qTitle:SetWidth(378); f.qTitle:SetJustifyH("LEFT"); f.qTitle:SetTextColor(.18,.10,.04)

    f.qMeta=sheet:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    f.qMeta:SetPoint("TOPLEFT",16,-38); f.qMeta:SetWidth(378); f.qMeta:SetJustifyH("LEFT"); f.qMeta:SetTextColor(.36,.24,.12)

    local div1=sheet:CreateTexture(nil,"ARTWORK")
    div1:SetPoint("TOPLEFT",14,-60); div1:SetPoint("TOPRIGHT",-14,-60); div1:SetHeight(1); div1:SetColorTexture(.48,.34,.18,.55)

    f.qNPCs=sheet:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    f.qNPCs:SetPoint("TOPLEFT",16,-68); f.qNPCs:SetWidth(378); f.qNPCs:SetJustifyH("LEFT"); f.qNPCs:SetSpacing(3); f.qNPCs:SetTextColor(.22,.14,.06)

    f.chainHeader=sheet:CreateFontString(nil,"OVERLAY","GameFontNormal")
    f.chainHeader:SetPoint("TOPLEFT",16,-116); f.chainHeader:SetText("Quest Chain Flow"); f.chainHeader:SetTextColor(.28,.16,.06)

    local div2=sheet:CreateTexture(nil,"ARTWORK")
    div2:SetPoint("TOPLEFT",14,-134); div2:SetPoint("TOPRIGHT",-14,-134); div2:SetHeight(1); div2:SetColorTexture(.48,.34,.18,.55)

    f.scroll=CreateFrame("ScrollFrame",nil,sheet,"UIPanelScrollFrameTemplate")
    f.scroll:SetPoint("TOPLEFT",12,-142); f.scroll:SetPoint("BOTTOMRIGHT",-30,12)
    f.canvas=CreateFrame("Frame",nil,f.scroll); f.canvas:SetSize(360,240); f.scroll:SetScrollChild(f.canvas)
    f.scroll:EnableMouseWheel(true)
    f.scroll:SetScript("OnMouseWheel",function(self,delta)
        local cur,max=self:GetVerticalScroll(),self:GetVerticalScrollRange()
        if type(cur)=="number" and type(max)=="number" then self:SetVerticalScroll(math.max(0,math.min(max,cur-delta*32))) end
    end)

    UISpecialFrames[#UISpecialFrames+1]="SmyrnaQuestsParchment"
    f:Hide()
    parchmentFrame=f
    return f
end

function Module.OpenParchment(qid)
    if not qid or not W or not W.Quest then return end
    local q=W.Quest(qid)
    if not q then return end
    local f=EnsureParchment()
    local done=IsCompleted(qid)
    local active=activeQuests[qid]~=nil
    local statusTxt=done and "|cff1b6e2e[Completed]|r" or (active and "|cff1b4e8c[In Quest Log]|r" or "|cff7a4b00[Available]|r")
    f.qTitle:SetText((q.n or ("Quest #"..qid)))
    f.qMeta:SetText(string.format("Level %d  ·  Req %d%s  ·  %s",q.ql or 0,q.rl or 0,q.xp and ("  ·  "..q.xp.." XP") or "",statusTxt))

    local startName,endName="Unknown","Unknown"
    if q.sb and q.sb[1] and q.sb[1][1] then local n=W.Npc(q.sb[1][1]); if n and n.n then startName=n.n end end
    if q.fb and q.fb[1] and q.fb[1][1] then local n=W.Npc(q.fb[1][1]); if n and n.n then endName=n.n end end
    f.qNPCs:SetText("Starts at: "..startName.."\nTurns in at: "..endName)

    local chain=BuildQuestChain(qid)
    f.chainHeader:SetText(#chain>1 and ("Quest Chain ("..#chain.." steps — click any step)") or "Standalone Quest")
    for i,cid in ipairs(chain) do
        local row=chainRows[i]
        if not row then
            row=CreateFrame("Button",nil,f.canvas,"BackdropTemplate")
            row:SetSize(356,28)
            row:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1,insets={left=1,right=1,top=1,bottom=1}})
            row:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
            local hl=row:GetHighlightTexture(); if hl then hl:SetVertexColor(.55,.38,.12,.18) end
            row.txt=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
            row.txt:SetPoint("LEFT",8,0); row.txt:SetWidth(272); row.txt:SetJustifyH("LEFT"); row.txt:SetMaxLines(1)
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
            row:SetBackdropColor(.84,.74,.52,.95); row:SetBackdropBorderColor(.62,.42,.12,1)
        else
            row:SetBackdropColor(.89,.82,.65,.78); row:SetBackdropBorderColor(.66,.54,.34,.65)
        end
        row.txt:SetText(string.format("%d. [%d] %s",i,(cq and (cq.ql or cq.rl) or 0),(cq and cq.n) or ("Quest #"..cid)))
        row.txt:SetTextColor(.18,.10,.04)
        if cDone then row.tag:SetText("|cff1b6e2eDone|r")
        elseif cAct then row.tag:SetText("|cff1b4e8cActive|r")
        else row.tag:SetText("|cff7a4b00Next|r") end
        row:Show()
    end
    for i=#chain+1,#chainRows do chainRows[i]:Hide() end
    f.canvas:SetHeight(math.max(220,#chain*32+8))
    f.scroll:UpdateScrollChildRect()
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
    if mapID and W and W.Ensure and W.Ensure() then
        local z=W.Zone(mapID)
        local pLvl,rBit,cBit=PlayerMasks()
        for _,qid in ipairs((z and z.q) or {}) do
            if IsCompleted(qid) then
                completedZone=completedZone+1
            else
                local q=W.Quest(qid)
                if IsQuestAvailable(qid,q,pLvl,rBit,cBit,cfg.lowLevel) then
                    local giver=""
                    if q.sb and q.sb[1] and q.sb[1][1] then
                        local npc=W.Npc(q.sb[1][1]); giver=npc and npc.n or ""
                    end
                    list[#list+1]={id=qid,name=q.n,level=q.ql or q.rl or 0,xp=q.xp,giver=giver}
                end
            end
        end
        table.sort(list,function(a,b) if a.level~=b.level then return a.level<b.level end return a.name<b.name end)
    end
    statusLabel:SetText(string.format("%s: %d available  ·  %d completed  ·  %d active in log  (click any quest to view its parchment chain)",zoneName,#list,completedZone,activeCount))
    local shown=math.min(#list,100)
    for i=1,math.max(shown,#questRows) do
        local e=i<=shown and list[i] or nil
        local row=questRows[i] or MakeQuestRow(i)
        if e then
            row.qid=e.id
            row:ClearAllPoints(); row:SetPoint("TOPLEFT",0,-(i-1)*42)
            row.title:SetText("["..e.level.."] "..e.name); row.title:SetTextColor(1,.90,.62)
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
        AddCheck("lowLevel","Low-level","Include trivial quests more than 8 levels below your character.",344,-58)
        AddCheck("tooltips","Tooltips","Append active quest objective progress when hovering quest creatures.",458,-58)
        AddCheck("tracker","Tracker","Show a compact, draggable floating tracker for your active quests.",564,-58)
        AddCheck("autoQuest","Auto accept/turn-in","Automatically accept quests and turn in single-reward quests (hold Shift to bypass).",668,-58)

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
autoDriver:RegisterEvent("QUEST_DETAIL")
autoDriver:RegisterEvent("QUEST_PROGRESS")
autoDriver:RegisterEvent("QUEST_COMPLETE")
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
            if WorldMapFrame.OnCanvasScaleChanged then hooksecurefunc(WorldMapFrame,"OnCanvasScaleChanged",Module.DrawWorld) end
        end
        local canvasF=WorldMapFrame:GetCanvas()
        if canvasF then canvasF:HookScript("OnSizeChanged",Module.DrawWorld) end
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

local driver=CreateFrame("Frame")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("QUEST_LOG_UPDATE")
driver:RegisterEvent("ZONE_CHANGED_NEW_AREA")
driver:RegisterEvent("PLAYER_LEVEL_UP")
driver:SetScript("OnEvent",function(self,event)
    if event=="PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        HookAll(); RefreshActiveQuests(); ConfigureMaps(); RefreshTracker()
    else
        RefreshActiveQuests(); qLastPX=nil; qMiniMap=nil; UpdateMini(true)
        if WorldMapFrame and WorldMapFrame:IsShown() then Module.DrawWorld() end
        RefreshTracker()
        if window and window:IsShown() then Module.RefreshUI() end
    end
end)

SLASH_SMYRNAQUESTS1="/sq"
SLASH_SMYRNAQUESTS2="/smyrnaquests"
SlashCmdList.SMYRNAQUESTS=function() Module.Open() end

Suite.Loaded[name]=true
Module.Perf=function() if Suite.Memory then Suite.Memory() end end
