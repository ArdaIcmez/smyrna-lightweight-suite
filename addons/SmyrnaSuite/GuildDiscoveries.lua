local _,Suite=...
-- Crowdsourced Forever Discovery Engine (Phase 4):
-- Passively captures new/unknown Forever Quests & NPCs missing from SmyrnaWorldDB,
-- overlays them live onto WorldDB lookups, syncs deltas across guildmates with quorum
-- verification (2+ guildmates = Guild-Verified), and exports clean Lua for future builds.
local D={}; Suite.Discoveries=D
local PREFIX="SMYRNADISC1"
local MAX_QUESTS,MAX_NPCS=500,500
local driver=CreateFrame("Frame")
local sendTicker,sendQueue,sendIdx
local exportWindow,reqCooldown,reqCount=nil,{},0
local overlayQ,overlayN={},{}
local lastStreamSeen=0

local function Public(v) return not (issecretvalue and issecretvalue(v)) end
local function Num(v,lo,hi) return Public(v) and type(v)=="number" and v==v and v>=lo and v<=hi end

local function CountTable(t) local n=0; for _ in pairs(t or {}) do n=n+1 end; return n end

local function Store()
    local root=Suite.Config.discoveries
    if type(root)~="table" then
        root={version=1,origin=string.format("%x%05x",time(),math.random(0,0xfffff)),quests={},npcs={},qCount=0,nCount=0}
        Suite.Config.discoveries=root
    end
    root.quests=root.quests or {}; root.npcs=root.npcs or {}
    if type(root.origin)~="string" or root.origin=="" then root.origin=string.format("%x%05x",time(),math.random(0,0xfffff)) end
    if type(root.qCount)~="number" then root.qCount=CountTable(root.quests) end
    if type(root.nCount)~="number" then root.nCount=CountTable(root.npcs) end
    return root
end
D.Store=Store

local function CleanStr(s,maxLen)
    if not Public(s) or type(s)~="string" then return "" end
    return (s:gsub("[%c|]"," "):gsub("%s+"," "):gsub("^%s+",""):gsub("%s+$","")):sub(1,maxLen or 64)
end

local function PlayerPos()
    if not C_Map or not C_Map.GetBestMapForUnit then return nil end
    local m=C_Map.GetBestMapForUnit("player")
    if not Num(m,1,1000000) then return nil end
    local pos=C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(m,"player")
    local x,y=pos and pos.GetXY and pos:GetXY()
    return m,Num(x,0,1) and math.floor(x*1000+.5) or 0,Num(y,0,1) and math.floor(y*1000+.5) or 0
end

local function AddReporter(rep,origin)
    if type(origin)~="string" or #origin<1 or #origin>24 or rep[origin] then return end
    if CountTable(rep)<16 then rep[origin]=true end
end

local function MergeQuest(qid,title,lvl,mapID,x10,y10,giverID,reporterOrigin)
    if not Num(qid,1,10000000) or qid%1~=0 or title=="" then return false end
    lvl=Num(lvl,0,200) and math.floor(lvl) or 0
    mapID=Num(mapID,0,1000000) and math.floor(mapID) or 0
    x10=Num(x10,0,1000) and math.floor(x10) or 0
    y10=Num(y10,0,1000) and math.floor(y10) or 0
    giverID=Num(giverID,0,10000000) and math.floor(giverID) or 0
    local st=Store()
    local existing=st.quests[qid]
    if not existing then
        if st.qCount>=MAX_QUESTS then return false end
        st.qCount=st.qCount+1
        existing={id=qid,n=title,ql=lvl,zn=mapID>0 and mapID or nil,x=x10,y=y10,g=giverID>0 and giverID or nil,at=time(),rep={}}
        st.quests[qid]=existing
    else
        existing.at=time()
        if lvl>0 then existing.ql=lvl end
        if giverID>0 and not existing.g then existing.g=giverID end
        existing.rep=existing.rep or {}
    end
    AddReporter(existing.rep,reporterOrigin)
    overlayQ[qid]=nil
    return true
end

local function MergeNpc(nid,nname,lvl,rank,mapID,x10,y10,reporterOrigin)
    if not Num(nid,1,10000000) or nid%1~=0 or nname=="" then return false end
    lvl=Num(lvl,0,200) and math.floor(lvl) or 0
    rank=Num(rank,0,4) and math.floor(rank) or 0
    mapID=Num(mapID,0,1000000) and math.floor(mapID) or 0
    x10=Num(x10,0,1000) and math.floor(x10) or 0
    y10=Num(y10,0,1000) and math.floor(y10) or 0
    local st=Store()
    local existing=st.npcs[nid]
    if not existing then
        if st.nCount>=MAX_NPCS then return false end
        st.nCount=st.nCount+1
        existing={id=nid,n=nname,l=lvl,h=lvl,r=rank,sp={},at=time(),rep={}}
        st.npcs[nid]=existing
    else
        existing.at=time()
        if lvl>0 then
            if not existing.l or existing.l==0 or lvl<existing.l then existing.l=lvl end
            if not existing.h or lvl>existing.h then existing.h=lvl end
        end
        existing.sp=existing.sp or {}
        existing.rep=existing.rep or {}
    end
    if mapID>0 then
        local pts=existing.sp[mapID]; if not pts then pts={}; existing.sp[mapID]=pts end
        if #pts<8 then
            local dup=false
            for _,p in ipairs(pts) do if math.abs(p[1]-x10)<15 and math.abs(p[2]-y10)<15 then dup=true; break end end
            if not dup then pts[#pts+1]={x10,y10} end
        end
    end
    AddReporter(existing.rep,reporterOrigin)
    overlayN[nid]=nil
    return true
end

-- Live overlay into Suite.WorldDB (cached wrappers to avoid per-lookup table allocations)
if Suite.WorldDB then
    Suite.WorldDB.Overlay=function(kind,id)
        local st=Suite.Config.discoveries
        if not st then return nil end
        if kind=="Q" then
            local cached=overlayQ[id]
            if cached then return cached end
            local q=st.quests and st.quests[id]
            if q then
                local w={n=q.n,ql=q.ql,rl=q.ql,zn=q.zn,sb=q.g and {{q.g}} or nil,fb=q.g and {{q.g}} or nil}
                overlayQ[id]=w; return w
            end
        elseif kind=="N" then
            local cached=overlayN[id]
            if cached then return cached end
            local n=st.npcs and st.npcs[id]
            if n then
                local w={n=n.n,l=n.l,h=n.h,r=n.r,sp=n.sp}
                overlayN[id]=w; return w
            end
        end
        return nil
    end
end

-- Passive local capture of unknown Forever quests & NPCs (checks static WorldDB, allows quorum confirmations!)
local function CaptureQuest()
    local qid=GetQuestID and GetQuestID()
    if not Num(qid,1,10000000) then return end
    if Suite.WorldDB and Suite.WorldDB.HasStatic and Suite.WorldDB.HasStatic("Q",qid) then return end
    if not (Suite.WorldDB and Suite.WorldDB.loaded) then return end
    local title=CleanStr(GetTitleText and GetTitleText() or "",80)
    if title=="" then return end
    local m,x10,y10=PlayerPos()
    local tguid=UnitGUID and UnitGUID("npc")
    local gid=(Public(tguid) and type(tguid)=="string") and tonumber(tguid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")) or nil
    local lvl=UnitLevel and UnitLevel("player")
    MergeQuest(qid,title,Num(lvl,1,200) and lvl or 0,m,x10,y10,gid,Store().origin)
end

local function CaptureUnit(unit)
    if not UnitExists or not UnitExists(unit) then return end
    local isPl=UnitIsPlayer and UnitIsPlayer(unit)
    if not Public(isPl) or isPl then return end
    local guid=UnitGUID and UnitGUID(unit)
    if not Public(guid) or type(guid)~="string" then return end
    local nid=tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
    if not nid then return end
    if Suite.WorldDB and Suite.WorldDB.HasStatic and Suite.WorldDB.HasStatic("N",nid) then return end
    if not (Suite.WorldDB and Suite.WorldDB.loaded) then return end
    local nname=CleanStr(UnitName and UnitName(unit) or "",64)
    if nname=="" then return end
    local lvl=UnitLevel and UnitLevel(unit)
    local cls=UnitClassification and UnitClassification(unit)
    local rank=0
    if Public(cls) then rank=(cls=="worldboss" and 3) or (cls=="rareelite" and 2) or (cls=="rare" and 4) or (cls=="elite" and 1) or 0 end
    local m,x10,y10=PlayerPos()
    MergeNpc(nid,nname,Num(lvl,1,200) and lvl or 0,rank,m,x10,y10,Store().origin)
end

-- Delta-only Guild Sync over SMYRNADISC1
local function Send(payload)
    if not IsInGuild or not IsInGuild() or not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return false end
    if C_ChatInfo.AreOutgoingAddonChatMessagesRestricted and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted() then return false end
    if type(payload)~="string" or #payload>245 then return false end
    C_ChatInfo.SendAddonMessage(PREFIX,payload,"GUILD")
    return true
end

function D.SyncWithGuild()
    if not IsInGuild or not IsInGuild() then
        if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffdfb66bSmyrna Discoveries:|r Join a guild to sync Forever discoveries.") end
        return false
    end
    Send("R|"..Store().origin)
    if DEFAULT_CHAT_FRAME then DEFAULT_CHAT_FRAME:AddMessage("|cffdfb66bSmyrna Discoveries:|r Requested new Forever discoveries from online guildmates.") end
    return true
end

local function StreamDeltas()
    if sendTicker then return end
    local st=Store()
    local pkts={}
    for _,q in pairs(st.quests) do
        pkts[#pkts+1]=table.concat({"Q",st.origin,q.id,q.ql or 0,q.zn or 0,q.x or 0,q.y or 0,q.g or 0,q.n or ""},"|")
        if #pkts>=80 then break end
    end
    for _,n in pairs(st.npcs) do
        local m,pt=next(n.sp or {})
        local x10,y10=(pt and pt[1] and pt[1][1]) or 0,(pt and pt[1] and pt[1][2]) or 0
        pkts[#pkts+1]=table.concat({"N",st.origin,n.id,n.l or 0,n.r or 0,m or 0,x10,y10,n.n or ""},"|")
        if #pkts>=160 then break end
    end
    if #pkts==0 then return end
    sendQueue=pkts; sendIdx=1
    sendTicker=C_Timer.NewTicker(.25,function()
        if not IsInGuild or not IsInGuild() or not sendQueue or sendIdx>#sendQueue then
            if sendTicker then sendTicker:Cancel(); sendTicker=nil end
            sendQueue=nil; sendIdx=nil; return
        end
        Send(sendQueue[sendIdx]); sendIdx=sendIdx+1
    end)
end

function D.Counts()
    local st=Store()
    local qv,nv=0,0
    for _,q in pairs(st.quests) do if CountTable(q.rep)>=2 then qv=qv+1 end end
    for _,n in pairs(st.npcs) do if CountTable(n.rep)>=2 then nv=nv+1 end end
    return st.qCount or 0,qv,st.nCount or 0,nv
end

function D.OpenExport()
    local st=Store()
    local lines={"-- Smyrna Guild Forever Discoveries Export (Ctrl+A, Ctrl+C)","SmyrnaDiscoveriesExport = {","  quests = {"}
    for id,q in pairs(st.quests) do
        local reps=CountTable(q.rep)
        lines[#lines+1]=string.format("    [%d] = { name=%q, level=%d, map=%d, x=%.1f, y=%.1f, giver=%d, reporters=%d },",id,q.n or "",q.ql or 0,q.zn or 0,(q.x or 0)/10,(q.y or 0)/10,q.g or 0,reps)
    end
    lines[#lines+1]="  },"; lines[#lines+1]="  npcs = {"
    for id,n in pairs(st.npcs) do
        local reps=CountTable(n.rep)
        local m,pt=next(n.sp or {})
        local x10,y10=(pt and pt[1] and pt[1][1]) or 0,(pt and pt[1] and pt[1][2]) or 0
        lines[#lines+1]=string.format("    [%d] = { name=%q, minLvl=%d, maxLvl=%d, rank=%d, map=%d, x=%.1f, y=%.1f, reporters=%d },",id,n.n or "",n.l or 0,n.h or 0,n.r or 0,m or 0,x10/10,y10/10,reps)
    end
    lines[#lines+1]="  },"; lines[#lines+1]="}"
    if not exportWindow then
        exportWindow=CreateFrame("Frame","SmyrnaDiscoveryExportWindow",UIParent,"BackdropTemplate")
        exportWindow:SetSize(640,420); exportWindow:SetPoint("CENTER"); exportWindow:SetFrameStrata("FULLSCREEN_DIALOG"); exportWindow:SetFrameLevel(220); exportWindow:SetClampedToScreen(true)
        Suite.StylePanel(exportWindow,true); Suite.HeaderStrip(exportWindow,40); Suite.CloseButton(exportWindow)
        local t=exportWindow:CreateFontString(nil,"OVERLAY","GameFontNormalLarge"); t:SetPoint("TOPLEFT",16,-12); t:SetText("Guild Discoveries Export"); t:SetTextColor(1,.86,.48)
        local scroll=CreateFrame("ScrollFrame",nil,exportWindow,"UIPanelScrollFrameTemplate"); scroll:SetPoint("TOPLEFT",16,-54); scroll:SetPoint("BOTTOMRIGHT",-34,16)
        local edit=CreateFrame("EditBox",nil,scroll); edit:SetMultiLine(true); edit:SetAutoFocus(false); edit:SetFontObject(ChatFontNormal); edit:SetWidth(580); edit:SetHeight(340); edit:SetMaxLetters(0)
        edit:SetScript("OnEscapePressed",function() exportWindow:Hide() end)
        scroll:SetScrollChild(edit); exportWindow.edit=edit; exportWindow.scroll=scroll
        UISpecialFrames[#UISpecialFrames+1]="SmyrnaDiscoveryExportWindow"
    end
    exportWindow:Show(); exportWindow.edit:SetText(table.concat(lines,"\n")); exportWindow.edit:SetFocus(); exportWindow.edit:HighlightText()
end

driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("QUEST_DETAIL")
driver:RegisterEvent("UPDATE_MOUSEOVER_UNIT")
driver:RegisterEvent("PLAYER_TARGET_CHANGED")
driver:RegisterEvent("CHAT_MSG_ADDON")
driver:SetScript("OnEvent",function(self,event,...)
    if event=="PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
    elseif event=="QUEST_DETAIL" then
        CaptureQuest()
    elseif event=="UPDATE_MOUSEOVER_UNIT" then
        CaptureUnit("mouseover")
    elseif event=="PLAYER_TARGET_CHANGED" then
        CaptureUnit("target")
    elseif event=="CHAT_MSG_ADDON" then
        local prefix,msg,channel,sender=...
        if not Public(prefix) or not Public(channel) or not Public(msg) or not Public(sender) then return end
        if prefix~=PREFIX or channel~="GUILD" or type(msg)~="string" or #msg>248 then return end
        local op=msg:sub(1,1)
        if op=="R" then
            local orig=msg:match("^R|([%w]+)$")
            if not orig or #orig>24 or orig==Store().origin then return end
            local now=GetTime()
            if reqCooldown[orig] and now-reqCooldown[orig]<20 then return end
            if not reqCooldown[orig] then
                if reqCount>=64 then wipe(reqCooldown); reqCount=0 end
                reqCount=reqCount+1
            end
            reqCooldown[orig]=now
            local reqAt=now
            C_Timer.After(.5+math.random()*2.5,function()
                if lastStreamSeen<reqAt then StreamDeltas() end
            end)
        elseif op=="Q" then
            local orig,id,lvl,m,x10,y10,g,title=msg:match("^Q|([%w]+)|(%d+)|(%d+)|(%d+)|(%d+)|(%d+)|(%d+)|(.*)$")
            if orig and #orig<=24 and orig~=Store().origin then
                lastStreamSeen=GetTime()
                MergeQuest(tonumber(id),CleanStr(title,80),tonumber(lvl),tonumber(m),tonumber(x10),tonumber(y10),tonumber(g),orig)
            end
        elseif op=="N" then
            local orig,id,lvl,rank,m,x10,y10,nname=msg:match("^N|([%w]+)|(%d+)|(%d+)|(%d+)|(%d+)|(%d+)|(%d+)|(.*)$")
            if orig and #orig<=24 and orig~=Store().origin then
                lastStreamSeen=GetTime()
                MergeNpc(tonumber(id),CleanStr(nname,64),tonumber(lvl),tonumber(rank),tonumber(m),tonumber(x10),tonumber(y10),orig)
            end
        end
    end
end)
