local _,Suite=...
local G={}; Suite.Guild=G
local PREFIX="SMYRNAGLD1"
local DOT_TEX="Interface\\AddOns\\SmyrnaSuite\\Media\\GuildDot"
local DOT_FALLBACK="Interface\\Minimap\\UI-Minimap-Ping"
local KNOWN_PROFS={
    Alchemy=true,Blacksmithing=true,Enchanting=true,Engineering=true,
    Herbalism=true,Leatherworking=true,Mining=true,Skinning=true,
    Tailoring=true,Cooking=true,["First Aid"]=true,Fishing=true,
    Jewelcrafting=true,Inscription=true,Archaeology=true,
}
local SECONDARY_PROFS={
    Cooking=true,["First Aid"]=true,Fishing=true,Archaeology=true,
}
local PROF_ICONS={
    Alchemy="Interface\\Icons\\Trade_Alchemy",
    Blacksmithing="Interface\\Icons\\Trade_BlackSmithing",
    Enchanting="Interface\\Icons\\Trade_Engraving",
    Engineering="Interface\\Icons\\Trade_Engineering",
    Herbalism="Interface\\Icons\\Trade_Herbalism",
    Leatherworking="Interface\\Icons\\Trade_LeatherWorking",
    Mining="Interface\\Icons\\Trade_Mining",
    Skinning="Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
    Tailoring="Interface\\Icons\\Trade_Tailoring",
    Cooking="Interface\\Icons\\INV_Misc_Food_15",
    ["First Aid"]="Interface\\Icons\\Spell_Holy_SealOfSacrifice",
    Fishing="Interface\\Icons\\Trade_Fishing",
    Jewelcrafting="Interface\\Icons\\INV_Misc_Gem_01",
    Inscription="Interface\\Icons\\INV_Inscription_Tradeskill01",
    Archaeology="Interface\\Icons\\Trade_Archaeology",
}

local driver=CreateFrame("Frame")
local peers={}       -- [cleanName] = { name, class, level, map, x, y, locAt, profs, profAt, seen, recipes }
local peerCount=0
local worldTicker,miniTicker
local lastSentMap,lastSentX,lastSentY,lastSentAt=nil,nil,nil,0
local lastProfSentAt,lastHelloAt,lastRosterScanAt,lastTabScanAt=0,0,0,0
local lastRecipeReqAt,lastRecipeReplyAt={},0
local worldPins,miniPins={},{}
local mapHooked,miniHooked,communitiesHooked,legacyGuildHooked
local page,rows,scroll,canvas,statusLabel,searchBox,sameZoneOnly,searchQuery
local filterAllBtn,filterZoneBtn,checks
local profDialog,profCards,recipeRows,profScroll,profCanvas,profSearchBox
local profTargetName,profFilterProf,profSearchQuery,profStatusText=nil,nil,"",nil
local groupCache,groupDirty={},true
local ownRecipesCache,ownRecipesAt=nil,0
local pageRefreshPending=false
local locMoving,locPending=false,false

local function Public(v) return not (issecretvalue and issecretvalue(v)) end
local function Num(v,lo,hi) return Public(v) and type(v)=="number" and v==v and v>=lo and v<=hi end

local function Config()
    local cfg=Suite.Config.guild
    if type(cfg)~="table" then cfg={}; Suite.Config.guild=cfg end
    if cfg.shareLocation==nil then cfg.shareLocation=true end
    if cfg.showMapPins==nil then cfg.showMapPins=true end
    if cfg.showMinimapPins==nil then cfg.showMinimapPins=true end
    if cfg.shareProfessions==nil then cfg.shareProfessions=true end
    return cfg
end
G.Config=Config

local function RosterCache()
    local c=Suite.Config.guildRoster
    if type(c)~="table" then c={}; Suite.Config.guildRoster=c end
    return c
end

local function SaveRosterProf(who,profs,classFile,level)
    if type(who)~="string" or who=="" or type(profs)~="string" or profs=="" then return end
    local cache=RosterCache()
    local count=0
    local oldestKey,oldestAt=nil,math.huge
    for k,v in pairs(cache) do
        count=count+1
        local at=(type(v)=="table" and type(v.at)=="number") and v.at or 0
        if at<oldestAt then oldestAt=at; oldestKey=k end
    end
    if not cache[who] and count>=200 and oldestKey then cache[oldestKey]=nil end
    cache[who]={
        profs=profs:sub(1,220),
        class=classFile or (cache[who] and cache[who].class),
        level=(Num(level,1,200) and math.floor(level)) or (cache[who] and cache[who].level) or 0,
        at=time(),
    }
end

local function CleanName(sender)
    if not Public(sender) or type(sender)~="string" then return nil end
    local short=sender:match("^([^-]+)") or sender
    short=(short:gsub("^%s+",""):gsub("%s+$",""))
    if short=="" or #short>64 or short:find("[%c|]") then return nil end
    return short
end

local function SelfCleanName()
    local first,last
    if UnitFullName then first,last=UnitFullName("player") elseif UnitName then first,last=UnitName("player") end
    local own=Suite.PlayerName and Suite.PlayerName(first,last)
    return CleanName(own or (Public(first) and first) or "")
end

local function IsSelf(sender)
    local first,last
    if UnitFullName then first,last=UnitFullName("player") elseif UnitName then first,last=UnitName("player") end
    local own=Suite.PlayerName and Suite.PlayerName(first,last)
    local short=sender:match("^([^-]+)")
    if own and (sender==own or short==own) then return true end
    if Public(first) and type(first)=="string" and (sender==first or short==first) then return true end
    return false
end

local function ClassColor(classFile)
    if classFile and C_ClassColor and C_ClassColor.GetClassColor then
        local ok,c=pcall(C_ClassColor.GetClassColor,classFile)
        if ok and c and c.r then return c.r,c.g,c.b end
    end
    local c=classFile and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classFile]
    if c then return c.r,c.g,c.b end
    return .40,.85,1
end

local function GroupMembersSet()
    if not groupDirty then return groupCache end
    groupDirty=false
    wipe(groupCache)
    if not IsInGroup or not IsInGroup() then return groupCache end
    local isRaid=IsInRaid and IsInRaid()
    local n=GetNumGroupMembers and GetNumGroupMembers() or 0
    local prefix=isRaid and "raid" or "party"
    for i=1,math.min(n,40) do
        local unit=prefix..i
        if UnitExists and UnitExists(unit) then
            local first,last
            if UnitFullName then first,last=UnitFullName(unit) elseif UnitName then first,last=UnitName(unit) end
            local full=Suite.PlayerName and Suite.PlayerName(first,last)
            if full then groupCache[full]=true; local s=full:match("^([^-]+)"); if s then groupCache[s]=true end end
            if Public(first) and type(first)=="string" then groupCache[first]=true end
        end
    end
    return groupCache
end

local function PlayerPosition()
    if not C_Map or not C_Map.GetBestMapForUnit or not C_Map.GetPlayerMapPosition then return nil end
    local map=C_Map.GetBestMapForUnit("player")
    if not Num(map,1,1000000) or map%1~=0 then return nil end
    local pos=C_Map.GetPlayerMapPosition(map,"player")
    if not pos or not pos.GetXY then return nil end
    local x,y=pos:GetXY()
    if not Num(x,0,1) or not Num(y,0,1) then return nil end
    return map,x,y
end

local function ReadOwnProfessions()
    local list,seen={},{}
    local function Add(name,rank,maxRank)
        if not Public(name) or type(name)~="string" or name=="" or seen[name] then return end
        local clean=name:gsub("[%c|:,;]"," "):gsub("%s+"," "):gsub("^%s+",""):gsub("%s+$",""):sub(1,24)
        if clean=="" or seen[clean] then return end
        seen[clean]=true
        local r=Num(rank,0,9999) and math.floor(rank) or 0
        local m=Num(maxRank,0,9999) and math.floor(maxRank) or 0
        list[#list+1]=clean..":"..r.."/"..m
    end
    if GetProfessions and GetProfessionInfo then
        local idx={GetProfessions()}
        for i=1,6 do
            local slot=idx[i]
            if Num(slot,1,1000) then
                local ok,name,_,rank,maxRank=pcall(GetProfessionInfo,slot)
                if ok then Add(name,rank,maxRank) end
            end
        end
    end
    if #list==0 and GetNumSkillLines and GetSkillLineInfo then
        local n=GetNumSkillLines()
        if Num(n,1,200) then
            for i=1,n do
                local name,isHeader,_,rank,_,_,maxRank=GetSkillLineInfo(i)
                if not isHeader and Public(name) and KNOWN_PROFS[name] then Add(name,rank,maxRank) end
            end
        end
    end
    return table.concat(list,",")
end

local function SendAddon(payload)
    if not IsInGuild or not IsInGuild() then return false end
    if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return false end
    if C_ChatInfo.AreOutgoingAddonChatMessagesRestricted and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted() then return false end
    if type(payload)~="string" or #payload>245 then return false end
    C_ChatInfo.SendAddonMessage(PREFIX,payload,"GUILD")
    return true
end

local function GuildHasOtherOnline()
    if not IsInGuild or not IsInGuild() then return false end
    if GetNumGuildMembers then
        local ok,_,online=pcall(GetNumGuildMembers)
        if ok and Num(online,0,2000) and online<=1 and peerCount==0 then return false end
    end
    return true
end

local function BroadcastLocation(force)
    if not IsInGuild or not IsInGuild() then return end
    if not force and not GuildHasOtherOnline() then return end
    local cfg=Config()
    if not cfg.shareLocation then return end
    local map,x,y=PlayerPosition()
    if not map then return end
    local xi=math.floor(x*10000+.5)
    local yi=math.floor(y*10000+.5)
    local now=GetTime()
    if not force and lastSentMap==map and lastSentX and lastSentY and math.abs(xi-lastSentX)<12 and math.abs(yi-lastSentY)<12 and (now-lastSentAt)<15 then
        return
    end
    local _,classFile=UnitClass("player")
    local level=UnitLevel("player")
    classFile=(Public(classFile) and type(classFile)=="string") and classFile or "WARRIOR"
    level=Num(level,1,200) and math.floor(level) or 0
    if SendAddon(table.concat({"L",map,xi,yi,classFile,level},"|")) then
        lastSentMap=map; lastSentX=xi; lastSentY=yi; lastSentAt=now
    end
end

local function BroadcastProfessions(force)
    local _,classFile=UnitClass("player")
    local level=UnitLevel("player")
    classFile=(Public(classFile) and type(classFile)=="string") and classFile or "WARRIOR"
    level=Num(level,1,200) and math.floor(level) or 0
    local profs=ReadOwnProfessions()
    if #profs>190 then profs=profs:sub(1,190) end
    local me=SelfCleanName()
    if me and profs~="" then SaveRosterProf(me,profs,classFile,level) end
    if not IsInGuild or not IsInGuild() then return end
    local cfg=Config()
    if not cfg.shareProfessions then return end
    local now=GetTime()
    if not force and (now-lastProfSentAt)<8 then return end
    if SendAddon(table.concat({"F",classFile,level,profs},"|")) then
        lastProfSentAt=now
    end
end

local function EnsurePeer(name)
    local p=peers[name]
    if not p then
        if peerCount>=120 then
            -- Evict oldest stale peer
            local oldestKey,oldestTime=nil,math.huge
            for k,v in pairs(peers) do if (v.seen or 0)<oldestTime then oldestKey=k; oldestTime=v.seen or 0 end end
            if oldestKey then peers[oldestKey]=nil; peerCount=peerCount-1 end
        end
        p={name=name,seen=GetTime()}
        peers[name]=p; peerCount=peerCount+1
    end
    p.seen=GetTime()
    return p
end

local function ParseProfessions(raw)
    local out={}
    if type(raw)~="string" or raw=="" then return out end
    for entry in raw:gmatch("[^,]+") do
        local pname,r,m=entry:match("^([^:]+):(%d+)/(%d+)$")
        if pname then
            out[#out+1]={
                name=pname,
                rank=tonumber(r) or 0,
                maxRank=tonumber(m) or 0,
                secondary=SECONDARY_PROFS[pname] and true or false,
            }
        end
    end
    table.sort(out,function(a,b)
        if a.secondary~=b.secondary then return not a.secondary end
        return a.name<b.name
    end)
    return out
end

local function FormatProfessions(raw)
    local parsed=ParseProfessions(raw)
    local parts={}
    for _,p in ipairs(parsed) do
        parts[#parts+1]=p.name.." "..p.rank..(p.maxRank>0 and ("/"..p.maxRank) or "")
    end
    return table.concat(parts,"  -  ")
end

local function ReadOwnRecipesByProf(force)
    local now=GetTime()
    if not force and ownRecipesCache and (now-ownRecipesAt)<10 then return ownRecipesCache end
    local out={}
    local owned={}
    for _,p in ipairs(ParseProfessions(ReadOwnProfessions())) do owned[p.name]=true end
    local ws=Suite.Modules.SmyrnaWorkshop
    if not ws or not ws.DB or type(ws.DB.recipes)~="table" or not ws.ReadRecipe then return out end
    for k,v in pairs(ws.DB.recipes) do
        local r=ws.ReadRecipe(v,k)
        if r and r.profession and r.name and owned[r.profession] then
            local known=ws.Known and ws.Known(r)
            if known~=false then
                local bucket=out[r.profession]
                if not bucket then bucket={}; out[r.profession]=bucket end
                bucket[#bucket+1]={name=r.name,spell=r.spell or 0}
            end
        end
    end
    for _,list in pairs(out) do
        table.sort(list,function(a,b) return a.name<b.name end)
    end
    ownRecipesCache=out; ownRecipesAt=now
    return out
end

local function GetMemberData(rawName,withRecipes)
    local clean=CleanName(rawName)
    if not clean then return nil end
    if IsSelf(rawName) or IsSelf(clean) then
        local _,cls=UnitClass("player")
        local lvl=UnitLevel("player")
        local map,x,y=PlayerPosition()
        local profs=ReadOwnProfessions()
        cls=(Public(cls) and type(cls)=="string") and cls or "WARRIOR"
        lvl=Num(lvl,1,200) and math.floor(lvl) or 0
        if profs~="" then SaveRosterProf(clean,profs,cls,lvl) end
        return {
            name=clean,class=cls,level=lvl,map=map,x=x,y=y,locAt=map and GetTime() or nil,
            profs=profs,profAt=GetTime(),recipes=withRecipes and ReadOwnRecipesByProf() or nil,isOnline=true,isSelf=true,
        }
    end
    local p=peers[clean]
    local cached=RosterCache()[clean]
    if not p and not cached then return nil end
    local now=GetTime()
    return {
        name=clean,
        class=(p and p.class) or (cached and cached.class),
        level=(p and p.level) or (cached and cached.level) or 0,
        map=p and p.map,x=p and p.x,y=p and p.y,locAt=p and p.locAt,
        profs=(p and p.profs and p.profs~="" and p.profs) or (cached and cached.profs) or "",
        profAt=p and p.profAt,
        cachedAt=cached and cached.at,
        recipes=p and p.recipes,
        isOnline=p and p.seen and (now-p.seen)<=300 or false,
        isSelf=false,
    }
end
G.GetMemberData=GetMemberData

local function SendOwnRecipesToGuild()
    if not IsInGuild or not IsInGuild() or not Config().shareProfessions then return end
    local now=GetTime()
    if now-lastRecipeReplyAt<4 then return end
    lastRecipeReplyAt=now
    BroadcastProfessions(true)
    local byProf=ReadOwnRecipesByProf()
    local chunks={}
    for pname,list in pairs(byProf) do
        local safeProf=pname:gsub("[|;~]",""):sub(1,24)
        local cur="R|"..safeProf.."|"
        local itemsInChunk=0
        for _,r in ipairs(list) do
            local entry=(r.name:gsub("[|;~\r\n]",""):sub(1,40)).."~"..tostring(r.spell or 0)
            local sep=itemsInChunk>0 and ";" or ""
            if #cur+#sep+#entry>235 then
                if itemsInChunk>0 then chunks[#chunks+1]=cur end
                cur="R|"..safeProf.."|"..entry
                itemsInChunk=1
                if #chunks>=14 then break end
            else
                cur=cur..sep..entry
                itemsInChunk=itemsInChunk+1
            end
        end
        if itemsInChunk>0 and #chunks<14 then chunks[#chunks+1]=cur end
        if #chunks>=14 then break end
    end
    for i,msg in ipairs(chunks) do
        C_Timer.After((i-1)*.18,function()
            if IsInGuild and IsInGuild() and Config().shareProfessions then SendAddon(msg) end
        end)
    end
end

local function RequestMemberRecipes(cleanName)
    if not cleanName or IsSelf(cleanName) or not IsInGuild or not IsInGuild() then return end
    local now=GetTime()
    if (now-(lastRecipeReqAt[cleanName] or 0))<5 then return end
    lastRecipeReqAt[cleanName]=now
    SendAddon("Q|"..cleanName:sub(1,64))
end

local function ShowPeerTooltip(owner,p)
    if not GameTooltip or (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then return end
    GameTooltip:SetOwner(owner,"ANCHOR_RIGHT")
    local r,g,b=ClassColor(p.class)
    GameTooltip:SetText(p.name,r,g,b)
    local info=p.map and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(p.map)
    local zone=info and info.name or (p.map and ("Map "..p.map) or "Unknown zone")
    local meta=(p.level and p.level>0) and ("Lv "..p.level.." ") or ""
    local classLabel=p.class and (p.class:sub(1,1)..p.class:sub(2):lower()) or ""
    if meta~="" or classLabel~="" then GameTooltip:AddLine(meta..classLabel,.85,.88,.94) end
    if p.x and p.y then
        GameTooltip:AddLine(string.format("%s (%.1f, %.1f)",zone,p.x*100,p.y*100),1,.88,.48)
    end
    local profText=FormatProfessions(p.profs)
    if profText~="" then GameTooltip:AddLine("Professions: "..profText,.55,.84,1,true) end
    GameTooltip:AddLine("Guild location (Smyrna Suite)",.62,.68,.76)
    GameTooltip:Show()
end

local function HideSafeTooltip()
    if GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then GameTooltip:Hide() end
end

-- World Map pins
local function HideWorldPins()
    for _,pin in ipairs(worldPins) do pin:Hide() end
end

local function DrawWorldPins()
    HideWorldPins()
    local cfg=Config()
    if not cfg.showMapPins or not WorldMapFrame or not WorldMapFrame:IsShown() then return end
    local canvas=WorldMapFrame.GetCanvas and WorldMapFrame:GetCanvas()
    local mapID=WorldMapFrame.GetMapID and WorldMapFrame:GetMapID()
    if not canvas or not mapID then return end
    local width,height=canvas:GetWidth(),canvas:GetHeight()
    if width<=0 or height<=0 then return end
    local zoom=WorldMapFrame.GetCanvasScale and WorldMapFrame:GetCanvasScale() or 1
    if not Num(zoom,.01,100) then zoom=1 end
    local scale=1/zoom
    local level=canvas:GetFrameLevel()+35
    if WorldMapFrame.GetPinFrameLevelsManager then
        local mgr=WorldMapFrame:GetPinFrameLevelsManager()
        local top=mgr and mgr.GetValidFrameLevel and mgr:GetValidFrameLevel("PIN_FRAME_LEVEL_TOPMOST")
        if type(top)=="number" then level=top+2 end
    end
    local inGroup=GroupMembersSet()
    local now=GetTime()
    local idx=0
    for _,p in pairs(peers) do
        if p.map==mapID and p.x and p.y and p.locAt and (now-p.locAt)<=35 and not inGroup[p.name] then
            idx=idx+1
            local pin=worldPins[idx]
            if not pin then
                pin=CreateFrame("Frame",nil,canvas); pin:SetSize(15,15); pin:EnableMouse(true)
                pin.dot=pin:CreateTexture(nil,"OVERLAY"); pin.dot:SetAllPoints()
                if pin.dot:SetTexture(DOT_TEX)==false then pin.dot:SetTexture(DOT_FALLBACK) end
                pin.label=pin:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
                pin.label:SetPoint("LEFT",pin,"RIGHT",2,0)
                pin:SetScript("OnEnter",function(self) if self.peer then ShowPeerTooltip(self,self.peer) end end)
                pin:SetScript("OnLeave",HideSafeTooltip)
                worldPins[idx]=pin
            end
            local r,g,b=ClassColor(p.class)
            pin.peer=p; pin:SetParent(canvas); pin:SetFrameLevel(level); pin:SetScale(scale)
            pin:ClearAllPoints(); pin:SetPoint("CENTER",canvas,"TOPLEFT",p.x*width/scale,-p.y*height/scale)
            pin.dot:SetVertexColor(r,g,b,1)
            pin.label:SetText(p.name); pin.label:SetTextColor(r,g,b)
            pin:Show()
            if idx>=40 then break end
        end
    end
end
G.DrawWorldPins=DrawWorldPins

local function SyncWorldTicker()
    if WorldMapFrame and WorldMapFrame:IsShown() and Config().showMapPins and peerCount>0 then
        if not worldTicker then worldTicker=C_Timer.NewTicker(5,DrawWorldPins) end
    elseif worldTicker then
        worldTicker:Cancel(); worldTicker=nil
    end
end

local function HookWorldMap()
    if mapHooked or not WorldMapFrame or not WorldMapFrame.GetCanvas then return end
    mapHooked=true
    WorldMapFrame:HookScript("OnShow",function()
        DrawWorldPins()
        SyncWorldTicker()
    end)
    WorldMapFrame:HookScript("OnHide",function()
        if worldTicker then worldTicker:Cancel(); worldTicker=nil end
        HideWorldPins()
    end)
    if hooksecurefunc then
        if WorldMapFrame.SetMapID then hooksecurefunc(WorldMapFrame,"SetMapID",DrawWorldPins) end
        if WorldMapFrame.OnCanvasScaleChanged then hooksecurefunc(WorldMapFrame,"OnCanvasScaleChanged",DrawWorldPins) end
    end
    local canvas=WorldMapFrame:GetCanvas()
    if canvas then canvas:HookScript("OnSizeChanged",DrawWorldPins) end
end

-- Minimap pins
local function HideMiniPins()
    for _,pin in ipairs(miniPins) do pin:Hide() end
end

local function UpdateMiniPins()
    local cfg=Config()
    if not cfg.showMinimapPins or not Minimap or not Minimap:IsShown() or not C_Minimap or not C_Minimap.GetViewRadius then
        HideMiniPins(); return
    end
    local pMap,px,py=PlayerPosition()
    if not pMap then HideMiniPins(); return end
    local width,height=C_Map.GetMapWorldSize and C_Map.GetMapWorldSize(pMap)
    local radius=C_Minimap.GetViewRadius()
    if not Num(width,1,200000) or not Num(height,1,200000) or not Num(radius,1,10000) then HideMiniPins(); return end
    local rotated=GetCVar("rotateMinimap")=="1"
    if C_Minimap.IsRotateMinimapIgnored and C_Minimap.IsRotateMinimapIgnored() then rotated=false end
    local facing=rotated and GetPlayerFacing() or nil
    if facing and not Num(facing,-10,10) then facing=nil end
    local cosF,sinF=facing and math.cos(facing) or 1,facing and math.sin(facing) or 0
    local halfW,halfH=Minimap:GetWidth()/2,Minimap:GetHeight()/2
    local inGroup=GroupMembersSet()
    local now=GetTime()
    local idx=0
    for _,p in pairs(peers) do
        if p.map==pMap and p.x and p.y and p.locAt and (now-p.locAt)<=35 and not inGroup[p.name] then
            local dx,dy=(p.x-px)*width,(py-p.y)*height
            if facing then dx,dy=dx*cosF+dy*sinF,dy*cosF-dx*sinF end
            local dist=math.sqrt(dx*dx+dy*dy)
            local maxR=radius*.90
            local alpha=1
            local nx,ny
            if dist<=maxR then
                nx,ny=dx/radius,dy/radius
            else
                -- Clamp same-zone guildmates neatly onto the minimap rim like group dots.
                nx,ny=(dx/dist)*.90,(dy/dist)*.90
                alpha=.62
            end
            idx=idx+1
            local pin=miniPins[idx]
            if not pin then
                pin=CreateFrame("Frame",nil,Minimap); pin:SetSize(13,13); pin:EnableMouse(true)
                pin:SetFrameLevel(Minimap:GetFrameLevel()+6)
                pin.dot=pin:CreateTexture(nil,"OVERLAY"); pin.dot:SetAllPoints()
                if pin.dot:SetTexture(DOT_TEX)==false then pin.dot:SetTexture(DOT_FALLBACK) end
                pin:SetScript("OnEnter",function(self) if self.peer then ShowPeerTooltip(self,self.peer) end end)
                pin:SetScript("OnLeave",HideSafeTooltip)
                miniPins[idx]=pin
            end
            local r,g,b=ClassColor(p.class)
            pin.peer=p
            pin.dot:SetVertexColor(r,g,b,alpha)
            pin:ClearAllPoints(); pin:SetPoint("CENTER",Minimap,"CENTER",nx*halfW,ny*halfH)
            pin:Show()
            if idx>=32 then break end
        end
    end
    for i=idx+1,#miniPins do miniPins[i]:Hide() end
    -- Stop polling when no live guildmates remain on the current map.
    if idx==0 and miniTicker then miniTicker:Cancel(); miniTicker=nil end
end

local function EnsureMiniTicker()
    local cfg=Config()
    if not cfg.showMinimapPins or not Minimap or not Minimap:IsShown() then
        if miniTicker then miniTicker:Cancel(); miniTicker=nil end
        HideMiniPins(); return
    end
    local pMap=PlayerPosition()
    local inGroup=GroupMembersSet()
    local hasAny=false
    local now=GetTime()
    if pMap then
        for _,p in pairs(peers) do
            if p.map==pMap and p.locAt and (now-p.locAt)<=35 and not inGroup[p.name] then hasAny=true; break end
        end
    end
    if hasAny then
        UpdateMiniPins()
        if not miniTicker then
            local rotating=(GetCVar("rotateMinimap")=="1") and not (C_Minimap.IsRotateMinimapIgnored and C_Minimap.IsRotateMinimapIgnored())
            if locMoving or rotating then miniTicker=C_Timer.NewTicker(.5,UpdateMiniPins) end
        end
    else
        if miniTicker then miniTicker:Cancel(); miniTicker=nil end
        HideMiniPins()
    end
end

local function HookMinimap()
    if miniHooked or not Minimap then return end
    miniHooked=true
    Minimap:HookScript("OnShow",EnsureMiniTicker)
    Minimap:HookScript("OnHide",function()
        if miniTicker then miniTicker:Cancel(); miniTicker=nil end
        HideMiniPins()
    end)
end

-- Event/movement-driven location broadcast (zero idle ticker when standing still or solo online!)
local function ScheduleLocationStep()
    if locPending or not locMoving then return end
    if not IsInGuild or not IsInGuild() or not Config().shareLocation then return end
    locPending=true
    C_Timer.After(3,function()
        locPending=false
        if not IsInGuild or not IsInGuild() or not Config().shareLocation then return end
        BroadcastLocation(false)
        if locMoving then ScheduleLocationStep() end
    end)
end

local function ConfigureLocationTicker()
    if locMoving and IsInGuild and IsInGuild() and Config().shareLocation then
        ScheduleLocationStep()
    end
    EnsureMiniTicker()
end

local function QueuePageRefresh()
    if pageRefreshPending or not page or not page:IsShown() then return end
    pageRefreshPending=true
    C_Timer.After(.5,function()
        pageRefreshPending=false
        if G.RefreshPage then G.RefreshPage() end
    end)
end

function G.Scan()
    if not IsInGuild or not IsInGuild() then
        if G.RefreshPage then G.RefreshPage() end
        return false
    end
    SendAddon("H")
    BroadcastLocation(true)
    BroadcastProfessions(true)
    local diary=Suite.Modules.SmyrnaFieldDiary
    if diary and diary.ScanGuildies then diary.ScanGuildies() end
    if G.RefreshPage then G.RefreshPage() end
    return true
end

local function HandleMessage(prefix,message,channel,sender)
    if not Public(prefix) or not Public(channel) or not Public(message) or not Public(sender) then return end
    if prefix~=PREFIX or channel~="GUILD" or type(message)~="string" or #message>250 then return end
    if IsSelf(sender) then return end
    local who=CleanName(sender); if not who then return end
    local op=message:sub(1,1)
    if op=="H" then
        local now=GetTime()
        if now-lastHelloAt<3 then return end
        lastHelloAt=now
        C_Timer.After(.1+math.random()*.4,function()
            BroadcastLocation(true)
            BroadcastProfessions(true)
        end)
    elseif op=="L" then
        local mStr,xStr,yStr,cls,lvlStr=message:match("^L|(%d+)|(%d+)|(%d+)|([%u_]+)|(%d+)$")
        local m,xi,yi,lvl=tonumber(mStr),tonumber(xStr),tonumber(yStr),tonumber(lvlStr)
        if not m or m<1 or m>1000000 or not xi or not yi or xi>10000 or yi>10000 or not lvl or lvl>200 or #cls>16 then return end
        local p=EnsurePeer(who)
        p.map=m; p.x=xi/10000; p.y=yi/10000; p.class=cls; p.level=lvl; p.locAt=GetTime()
        if WorldMapFrame and WorldMapFrame:IsShown() then DrawWorldPins(); SyncWorldTicker() end
        EnsureMiniTicker()
        QueuePageRefresh()
    elseif op=="F" then
        local cls,lvlStr,profs=message:match("^F|([%u_]+)|(%d+)|(.*)$")
        local lvl=tonumber(lvlStr)
        if not cls or #cls>16 or not lvl or lvl>200 or #profs>220 then return end
        local p=EnsurePeer(who)
        p.class=cls; p.level=lvl; p.profs=profs; p.profAt=GetTime()
        if profs~="" then SaveRosterProf(who,profs,cls,lvl) end
        QueuePageRefresh()
        if profDialog and profDialog:IsShown() and profTargetName==who and G.RefreshProfDialog then G.RefreshProfDialog() end
    elseif op=="Q" then
        local target=message:match("^Q|(.+)$")
        if target and IsSelf(target) then SendOwnRecipesToGuild() end
    elseif op=="R" then
        local pname,body=message:match("^R|([^|]+)|(.*)$")
        if not pname or not KNOWN_PROFS[pname] or not body or #body>235 then return end
        local p=EnsurePeer(who)
        p.recipes=p.recipes or {}
        local bucket=p.recipes[pname]
        if not bucket then bucket={}; p.recipes[pname]=bucket end
        local seen={}
        for _,ex in ipairs(bucket) do seen[ex.name]=true end
        for entry in body:gmatch("[^;]+") do
            local rname,spStr=entry:match("^([^~]+)~(%d+)$")
            local sp=tonumber(spStr)
            if rname and rname~="" and #rname<=48 and sp and sp<=2000000 and not seen[rname] and #bucket<250 then
                seen[rname]=true
                bucket[#bucket+1]={name=rname,spell=sp}
            end
        end
        table.sort(bucket,function(a,b) return a.name<b.name end)
        if profDialog and profDialog:IsShown() and profTargetName==who and G.RefreshProfDialog then G.RefreshProfDialog() end
    elseif op=="X" then
        local p=peers[who]
        if p then p.map=nil; p.x=nil; p.y=nil; p.locAt=nil end
        if WorldMapFrame and WorldMapFrame:IsShown() then DrawWorldPins(); SyncWorldTicker() end
        EnsureMiniTicker()
        QueuePageRefresh()
    end
end

-- ============================================================
-- Guildmate Professions & Recipes Popup (Ctrl + Left-Click)
-- ============================================================

local function MakeProfCard(i)
    local c=CreateFrame("Button",nil,profDialog,"BackdropTemplate")
    c:SetSize(210,44)
    Suite.StyleCard(c,.076,.088,.122)
    c:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    local hl=c:GetHighlightTexture(); if hl then hl:SetVertexColor(.95,.78,.36,.12) end
    c.tile=Suite.CreateIconTile(c,28); c.tile:SetPoint("LEFT",8,0)
    c.name=c:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    c.name:SetPoint("TOPLEFT",42,-6); c.name:SetWidth(112); c.name:SetJustifyH("LEFT"); c.name:SetMaxLines(1)
    c.skill=c:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    c.skill:SetPoint("TOPRIGHT",-8,-7); c.skill:SetJustifyH("RIGHT")
    c.barBg=c:CreateTexture(nil,"ARTWORK")
    c.barBg:SetSize(156,6); c.barBg:SetPoint("BOTTOMLEFT",42,8); c.barBg:SetColorTexture(.06,.07,.10,.95)
    c.barFill=c:CreateTexture(nil,"OVERLAY")
    c.barFill:SetSize(1,6); c.barFill:SetPoint("LEFT",c.barBg,"LEFT",0,0)
    c:SetScript("OnClick",function(self)
        if not self.profName then return end
        profFilterProf=(profFilterProf==self.profName) and nil or self.profName
        if G.RefreshProfDialog then G.RefreshProfDialog() end
    end)
    profCards[i]=c
    return c
end

local function MakeRecipeRow(i)
    local r=CreateFrame("Button",nil,profCanvas,"BackdropTemplate")
    r:SetSize(412,24)
    Suite.StyleCard(r,.072,.084,.116)
    r:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    local hl=r:GetHighlightTexture(); if hl then hl:SetVertexColor(.95,.78,.36,.12) end
    r.name=r:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    r.name:SetPoint("LEFT",8,0); r.name:SetWidth(272); r.name:SetJustifyH("LEFT"); r.name:SetMaxLines(1)
    r.prof=r:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    r.prof:SetPoint("RIGHT",-8,0); r.prof:SetJustifyH("RIGHT"); r.prof:SetTextColor(.58,.82,1)
    r:SetScript("OnEnter",function(self)
        if self.spellID and self.spellID>0 and GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) and GameTooltip.SetSpellByID then
            GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
            pcall(GameTooltip.SetSpellByID,GameTooltip,self.spellID)
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave",HideSafeTooltip)
    recipeRows[i]=r
    return r
end

function G.RefreshProfDialog()
    if not profDialog or not profDialog:IsShown() or not profTargetName then return end
    local data=GetMemberData(profTargetName,true)
    local r,g,b=ClassColor(data and data.class)
    local lvlTxt=(data and data.level and data.level>0) and ("  |cff9aa4b2Lv "..data.level.."|r") or ""
    profDialog.title:SetText(profTargetName..lvlTxt)
    profDialog.title:SetTextColor(r,g,b)

    local subParts={}
    if data and data.map and data.x and data.y and data.locAt and (GetTime()-data.locAt)<=35 then
        local info=C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(data.map)
        subParts[#subParts+1]=string.format("%s (%.1f, %.1f)",(info and info.name) or ("Map "..data.map),data.x*100,data.y*100)
    end
    if data and data.isSelf then
        subParts[#subParts+1]="Your character (live)"
    elseif data and data.profs and data.profs~="" then
        subParts[#subParts+1]=data.isOnline and "Reported live by Smyrna Suite" or "Cached from Smyrna Suite"
    else
        subParts[#subParts+1]="No Smyrna Suite data yet"
    end
    profDialog.sub:SetText(table.concat(subParts,"  ·  "))

    local profs=ParseProfessions(data and data.profs or "")
    for i=1,math.max(#profs,#profCards) do
        local p=profs[i]
        local c=profCards[i] or MakeProfCard(i)
        if p then
            local col=(i-1)%2; local row=math.floor((i-1)/2)
            c.profName=p.name
            c:ClearAllPoints(); c:SetPoint("TOPLEFT",16+col*218,-(62+row*50))
            c.tile.icon:SetTexture(PROF_ICONS[p.name] or "Interface\\Icons\\INV_Misc_QuestionMark")
            local sel=(profFilterProf==p.name)
            if sel then
                c:SetBackdropBorderColor(.96,.80,.38,1)
                c.tile:SetBackdropBorderColor(.96,.80,.38,1)
            elseif p.secondary then
                c:SetBackdropBorderColor(.28,.34,.46,.90)
                c.tile:SetBackdropBorderColor(.48,.62,.82,.90)
            else
                c:SetBackdropBorderColor(.36,.52,.66,.92)
                c.tile:SetBackdropBorderColor(.42,.80,1,.92)
            end
            c.name:SetText(p.name)
            c.name:SetTextColor(p.secondary and .76 or .98,p.secondary and .84 or .94,p.secondary and .94 or .72)
            c.skill:SetText(p.rank..(p.maxRank>0 and ("/"..p.maxRank) or ""))
            c.skill:SetTextColor(p.secondary and .68 or .48,p.secondary and .78 or .88,1)
            local frac=(p.maxRank>0) and math.max(.02,math.min(1,p.rank/p.maxRank)) or 1
            c.barFill:SetWidth(math.max(2,math.floor(156*frac+.5)))
            if p.secondary then c.barFill:SetColorTexture(.46,.68,.92,.88) else c.barFill:SetColorTexture(.92,.76,.34,.92) end
            c:Show()
        else
            c.profName=nil; c:Hide()
        end
    end

    local profRowsCount=math.max(1,math.ceil(#profs/2))
    local listTop=62+profRowsCount*50+10
    profDialog.recHeader:ClearAllPoints(); profDialog.recHeader:SetPoint("TOPLEFT",16,-listTop)
    profDialog.recHeader:SetText(profFilterProf and ("Known Recipes — "..profFilterProf.." (click card to clear)") or "Known Recipes (click a profession above to filter)")
    profSearchBox:ClearAllPoints(); profSearchBox:SetPoint("TOPLEFT",20,-(listTop+18))
    profStatusText:ClearAllPoints(); profStatusText:SetPoint("LEFT",profSearchBox,"RIGHT",10,0)
    profScroll:ClearAllPoints(); profScroll:SetPoint("TOPLEFT",16,-(listTop+46))
    local scrollH=math.max(110,432-(listTop+46)-14)
    profScroll:SetSize(418,scrollH)

    local flat={}
    local q=string.lower((profSearchQuery or ""):gsub("^%s+",""):gsub("%s+$",""))
    if data and type(data.recipes)=="table" then
        for pname,list in pairs(data.recipes) do
            if not profFilterProf or profFilterProf==pname then
                for _,rec in ipairs(list) do
                    if q=="" or string.lower(rec.name.." "..pname):find(q,1,true) then
                        flat[#flat+1]={name=rec.name,spell=rec.spell,prof=pname}
                    end
                end
            end
        end
    end
    table.sort(flat,function(a,b)
        if a.prof~=b.prof then return a.prof<b.prof end
        return a.name<b.name
    end)

    if #profs==0 then
        profStatusText:SetText("Guildmate needs Smyrna Suite installed")
    elseif #flat>0 then
        profStatusText:SetText(#flat.." known recipes")
    elseif data and data.isSelf then
        profStatusText:SetText("Open your profession window once to scan")
    elseif data and data.isOnline then
        profStatusText:SetText("Syncing recipes if shared...")
    else
        profStatusText:SetText("Recipes sync when online")
    end

    for i=1,math.max(#flat,#recipeRows) do
        local item=flat[i]
        local row=recipeRows[i] or MakeRecipeRow(i)
        if item then
            row.spellID=item.spell
            row:ClearAllPoints(); row:SetPoint("TOPLEFT",0,-(i-1)*26)
            row.name:SetText(item.name); row.name:SetTextColor(.92,.94,.98)
            row.prof:SetText(item.prof)
            row:Show()
        else
            row.spellID=nil; row:Hide()
        end
    end
    profCanvas:SetHeight(math.max(scrollH,#flat*26+6))
    profScroll:UpdateScrollChildRect()
end

function G.OpenMemberProfessions(rawName)
    local clean=CleanName(rawName)
    if not clean then return end
    profTargetName=clean
    profFilterProf=nil
    profSearchQuery=""
    if not profDialog then
        profCards={}; recipeRows={}
        profDialog=CreateFrame("Frame","SmyrnaGuildProfFrame",UIParent,"BackdropTemplate")
        profDialog:SetSize(460,440); profDialog:SetPoint("CENTER"); profDialog:SetFrameStrata("DIALOG")
        profDialog:SetClampedToScreen(true); profDialog:SetMovable(true); profDialog:EnableMouse(true)
        Suite.StylePanel(profDialog,true)
        profDialog:RegisterForDrag("LeftButton")
        profDialog:SetScript("OnDragStart",function(self)
            if not (InCombatLockdown and InCombatLockdown()) then self:StartMoving() end
        end)
        profDialog:SetScript("OnDragStop",function(self) self:StopMovingOrSizing() end)
        Suite.CloseButton(profDialog)

        profDialog.title=profDialog:CreateFontString(nil,"OVERLAY","GameFontNormalLarge")
        profDialog.title:SetPoint("TOPLEFT",16,-14); profDialog.title:SetWidth(270); profDialog.title:SetJustifyH("LEFT"); profDialog.title:SetMaxLines(1)
        profDialog.sub=profDialog:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        profDialog.sub:SetPoint("TOPLEFT",16,-36); profDialog.sub:SetWidth(428); profDialog.sub:SetJustifyH("LEFT"); profDialog.sub:SetMaxLines(1); profDialog.sub:SetTextColor(.72,.78,.86)

        local wb=CreateFrame("Button",nil,profDialog,"UIPanelButtonTemplate")
        wb:SetSize(68,20); wb:SetPoint("TOPRIGHT",-44,-14); wb:SetText("Whisper"); Suite.StyleButton(wb)
        wb:SetScript("OnClick",function()
            if not profTargetName then return end
            if ChatFrame_SendTell then ChatFrame_SendTell(profTargetName)
            elseif ChatFrame_OpenChat then ChatFrame_OpenChat("/w "..profTargetName.." ") end
        end)

        local rb=CreateFrame("Button",nil,profDialog,"UIPanelButtonTemplate")
        rb:SetSize(62,20); rb:SetPoint("RIGHT",wb,"LEFT",-5,0); rb:SetText("Sync"); Suite.StyleButton(rb)
        rb:SetScript("OnClick",function()
            if profTargetName then
                lastRecipeReqAt[profTargetName]=0
                RequestMemberRecipes(profTargetName)
                G.RefreshProfDialog()
            end
        end)

        profDialog.recHeader=profDialog:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
        profDialog.recHeader:SetTextColor(.93,.77,.40)

        profSearchBox=CreateFrame("EditBox",nil,profDialog,"InputBoxTemplate")
        profSearchBox:SetSize(185,20); profSearchBox:SetAutoFocus(false)
        profSearchBox:SetScript("OnTextChanged",function(self) profSearchQuery=self:GetText() or ""; G.RefreshProfDialog() end)
        profSearchBox:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)

        profStatusText=profDialog:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        profStatusText:SetWidth(220); profStatusText:SetJustifyH("LEFT"); profStatusText:SetTextColor(.68,.75,.84)

        profScroll=CreateFrame("ScrollFrame",nil,profDialog,"UIPanelScrollFrameTemplate")
        profCanvas=CreateFrame("Frame",nil,profScroll); profCanvas:SetSize(412,180); profScroll:SetScrollChild(profCanvas)
        profScroll:EnableMouseWheel(true)
        profScroll:SetScript("OnMouseWheel",function(self,delta)
            local cur,max=self:GetVerticalScroll(),self:GetVerticalScrollRange()
            if type(cur)=="number" and type(max)=="number" then self:SetVerticalScroll(math.max(0,math.min(max,cur-delta*36))) end
        end)
        UISpecialFrames[#UISpecialFrames+1]="SmyrnaGuildProfFrame"
    end
    profSearchBox:SetText("")
    profDialog:Show()
    G.RefreshProfDialog()
    RequestMemberRecipes(clean)
end

-- ============================================================
-- Guild & Communities Roster Hover Tooltip + Ctrl+Left-Click
-- ============================================================

local function AppendRosterTooltip(owner,rawName)
    if not GameTooltip or (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then return end
    local data=GetMemberData(rawName)
    if not data then return end
    local profs=ParseProfessions(data.profs)
    local hasLoc=data.map and data.x and data.y and data.locAt and (GetTime()-data.locAt)<=35
    if #profs==0 and not hasLoc then return end
    if not GameTooltip:IsShown() then
        GameTooltip:SetOwner(owner,"ANCHOR_RIGHT")
        local r,g,b=ClassColor(data.class)
        GameTooltip:SetText(data.name,r,g,b)
    end
    GameTooltip:AddLine(" ")
    if hasLoc then
        local info=C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(data.map)
        local zname=(info and info.name) or ("Map "..data.map)
        GameTooltip:AddDoubleLine("Live Position:",string.format("%s (%.1f, %.1f)",zname,data.x*100,data.y*100),.93,.77,.40,1,.88,.48)
    end
    if #profs>0 then
        GameTooltip:AddLine("Professions (Smyrna Suite):",.93,.77,.40)
        for _,p in ipairs(profs) do
            local skillTxt=p.rank..(p.maxRank>0 and ("/"..p.maxRank) or "")
            if p.secondary then
                GameTooltip:AddDoubleLine("  "..p.name,skillTxt,.68,.78,.90,.64,.74,.86)
            else
                GameTooltip:AddDoubleLine("  "..p.name,skillTxt,.48,.86,1,.95,.90,.72)
            end
        end
        Suite.OptionalHint(GameTooltip,"Ctrl + left-click to expand professions & recipes")
    end
    GameTooltip:Show()
end

local function EntryMemberName(btn)
    if not btn then return nil end
    if btn.GetMemberInfo then
        local ok,info=pcall(btn.GetMemberInfo,btn)
        if ok and type(info)=="table" and Public(info.name) and type(info.name)=="string" and info.name~="" then
            return info.name
        end
    end
    if type(btn.memberInfo)=="table" and Public(btn.memberInfo.name) and type(btn.memberInfo.name)=="string" and btn.memberInfo.name~="" then
        return btn.memberInfo.name
    end
    if btn.NameFrame and btn.NameFrame.Name and btn.NameFrame.Name.GetText then
        local t=btn.NameFrame.Name:GetText()
        if Public(t) and type(t)=="string" and t~="" then return t end
    end
    return nil
end

local hookedRosterBtns=setmetatable({},{__mode="k"})

local function HookCommunitiesEntry(btn)
    if not btn or hookedRosterBtns[btn] then return end
    if btn.IsForbidden and btn:IsForbidden() then return end
    hookedRosterBtns[btn]=true
    btn:HookScript("OnEnter",function(self)
        local nm=EntryMemberName(self)
        if nm then AppendRosterTooltip(self,nm) end
    end)
    btn:HookScript("OnLeave",function(self)
        if GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) and GameTooltip:IsOwned(self) then
            GameTooltip:Hide()
        end
    end)
    btn:HookScript("OnClick",function(self,mouseBtn)
        if mouseBtn=="LeftButton" and IsControlKeyDown and IsControlKeyDown() then
            local nm=EntryMemberName(self)
            if nm then G.OpenMemberProfessions(nm) end
        end
    end)
end

local function HookVisibleCommunitiesEntries()
    local ml=CommunitiesFrame and CommunitiesFrame.MemberList
    if not ml then return end
    if ml.ScrollBox and ml.ScrollBox.ForEachFrame then
        ml.ScrollBox:ForEachFrame(HookCommunitiesEntry)
    elseif ml.ListScrollFrame and ml.ListScrollFrame.buttons then
        for _,btn in ipairs(ml.ListScrollFrame.buttons) do HookCommunitiesEntry(btn) end
    end
end

local communitiesHookPending=false
local function QueueHookCommunitiesEntries()
    if communitiesHookPending then return end
    communitiesHookPending=true
    C_Timer.After(0,function()
        communitiesHookPending=false
        HookVisibleCommunitiesEntries()
    end)
end

local function HookCommunities()
    if communitiesHooked then return end
    local ml=CommunitiesFrame and CommunitiesFrame.MemberList
    if not ml then return end
    communitiesHooked=true
    QueueHookCommunitiesEntries()
    if ml.ScrollBox and ml.ScrollBox.RegisterCallback and ScrollBoxListMixin and ScrollBoxListMixin.Event and ScrollBoxListMixin.Event.OnUpdate then
        ml.ScrollBox:RegisterCallback(ScrollBoxListMixin.Event.OnUpdate,QueueHookCommunitiesEntries,G)
    end
    if hooksecurefunc and ml.RefreshListDisplay then
        hooksecurefunc(ml,"RefreshListDisplay",QueueHookCommunitiesEntries)
    end
    ml:HookScript("OnShow",function()
        QueueHookCommunitiesEntries()
        local now=GetTime()
        if IsInGuild and IsInGuild() and (now-lastRosterScanAt)>=30 then
            lastRosterScanAt=now
            SendAddon("H")
            BroadcastProfessions(false)
        end
    end)
end

local function HookLegacyGuild()
    if legacyGuildHooked or not GuildFrame then return end
    legacyGuildHooked=true
    for i=1,13 do
        local btn=_G["GuildStatusButton"..i]
        if btn and not hookedRosterBtns[btn] then
            hookedRosterBtns[btn]=true
            btn:HookScript("OnEnter",function(self)
                local idx=self.guildIndex
                if idx and GetGuildRosterInfo then
                    local nm=GetGuildRosterInfo(idx)
                    if Public(nm) and type(nm)=="string" then AppendRosterTooltip(self,nm) end
                end
            end)
            btn:HookScript("OnLeave",function(self)
                if GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) and GameTooltip:IsOwned(self) then
                    GameTooltip:Hide()
                end
            end)
            btn:HookScript("OnClick",function(self,mouseBtn)
                if mouseBtn=="LeftButton" and IsControlKeyDown and IsControlKeyDown() then
                    local idx=self.guildIndex
                    if idx and GetGuildRosterInfo then
                        local nm=GetGuildRosterInfo(idx)
                        if Public(nm) and type(nm)=="string" then G.OpenMemberProfessions(nm) end
                    end
                end
            end)
        end
    end
end

-- Hub Guild Tab Page
local function MakePeerRow(i)
    local card=CreateFrame("Button",nil,canvas,"BackdropTemplate")
    card:SetSize(786,52)
    Suite.StyleCard(card,.080,.092,.126)
    card:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    local hl=card:GetHighlightTexture(); if hl then hl:SetVertexColor(.95,.78,.36,.10) end
    card.dot=card:CreateTexture(nil,"OVERLAY"); card.dot:SetSize(12,12); card.dot:SetPoint("TOPLEFT",10,-10)
    if card.dot:SetTexture(DOT_TEX)==false then card.dot:SetTexture(DOT_FALLBACK) end
    card.name=card:CreateFontString(nil,"OVERLAY","GameFontNormal")
    card.name:SetPoint("LEFT",card.dot,"RIGHT",7,0)
    card.loc=card:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    card.loc:SetPoint("TOPRIGHT",-12,-9); card.loc:SetJustifyH("RIGHT")
    card.profs=card:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    card.profs:SetPoint("TOPLEFT",29,-28); card.profs:SetWidth(745); card.profs:SetJustifyH("LEFT"); card.profs:SetMaxLines(1); card.profs:SetTextColor(.58,.86,1)
    card:SetScript("OnClick",function(self)
        if self.peerName then G.OpenMemberProfessions(self.peerName) end
    end)
    rows[i]=card
    return card
end

function G.RefreshPage()
    if not page or not page:IsShown() then return end
    local cfg=Config()
    local diary=Suite.Modules.SmyrnaFieldDiary
    local bestiary=Suite.Modules.SmyrnaBestiary
    checks.shareLocation:SetChecked(cfg.shareLocation)
    checks.showMapPins:SetChecked(cfg.showMapPins)
    checks.showMinimapPins:SetChecked(cfg.showMinimapPins)
    checks.shareProfessions:SetChecked(cfg.shareProfessions)
    if diary and diary.DB then
        checks.diaryDownload:SetEnabled(true); checks.diaryDownload:SetChecked(diary.DB.settings.allowGuildDownload~=false)
        checks.diaryMap:SetEnabled(true); checks.diaryMap:SetChecked(diary.DB.settings.includeShared and true or false)
    else
        checks.diaryDownload:SetEnabled(false); checks.diaryDownload:SetChecked(false)
        checks.diaryMap:SetEnabled(false); checks.diaryMap:SetChecked(false)
    end
    if bestiary and bestiary.DB then
        checks.bestiaryShare:SetEnabled(true); checks.bestiaryShare:SetChecked(bestiary.DB.settings.guildShare and true or false)
    else
        checks.bestiaryShare:SetEnabled(false); checks.bestiaryShare:SetChecked(false)
    end

    Suite.SetButtonSelected(filterAllBtn,not sameZoneOnly)
    Suite.SetButtonSelected(filterZoneBtn,sameZoneOnly and true or false)

    local pMap=PlayerPosition()
    local now=GetTime()
    local q=string.lower((searchQuery or ""):gsub("^%s+",""):gsub("%s+$",""))
    local list={}
    for _,p in pairs(peers) do
        if (now-(p.seen or 0))<=300 then
            local liveLoc=p.map and p.x and p.y and p.locAt and (now-p.locAt)<=35
            local inSameZone=liveLoc and pMap and p.map==pMap
            if not sameZoneOnly or inSameZone then
                local info=p.map and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(p.map)
                local zone=(info and info.name) or (p.map and ("Map "..p.map) or "")
                local profText=FormatProfessions(p.profs)
                local ok=true
                if q~="" then
                    local hay=string.lower(p.name.." "..zone.." "..profText.." "..(p.class or ""))
                    ok=hay:find(q,1,true)~=nil
                end
                if ok then
                    list[#list+1]={peer=p,liveLoc=liveLoc,inSameZone=inSameZone,zone=zone,profText=profText}
                end
            end
        end
    end
    table.sort(list,function(a,b)
        if a.inSameZone~=b.inSameZone then return a.inSameZone end
        if a.liveLoc~=b.liveLoc then return a.liveLoc end
        return a.peer.name<b.peer.name
    end)

    if not IsInGuild or not IsInGuild() then
        statusLabel:SetText("Join a guild to share map locations, professions, and Field Diary finds with guildmates.")
    elseif #list==0 then
        statusLabel:SetText("No online guildmates responding yet. Click Scan Guild (guildmates also need Smyrna Suite).")
    else
        statusLabel:SetText("Online guildmates with Smyrna Suite: "..#list.."  (shown on World Map & Minimap even outside a group)")
    end

    for i=1,math.max(#list,#rows) do
        local item=list[i]
        local card=rows[i] or MakePeerRow(i)
        if item then
            local p=item.peer
            local r,g,b=ClassColor(p.class)
            card.peerName=p.name
            card:ClearAllPoints(); card:SetPoint("TOPLEFT",0,-(i-1)*58)
            Suite.SetCornerGlow(card,r,g,b,item.inSameZone and .18 or .08)
            card.dot:SetVertexColor(r,g,b,item.liveLoc and 1 or .35)
            local meta=(p.level and p.level>0) and ("  |cff9aa4b2Lv "..p.level.."|r") or ""
            card.name:SetText(p.name..meta); card.name:SetTextColor(r,g,b)
            if item.liveLoc then
                local coords=string.format("(%.1f, %.1f)",p.x*100,p.y*100)
                if item.inSameZone then
                    card.loc:SetText("|cff78d49bSame zone|r  -  "..item.zone.." "..coords)
                else
                    card.loc:SetText("|cffffd670"..item.zone.."|r "..coords)
                end
            else
                card.loc:SetText("|cff7c8694Location hidden or stale|r")
            end
            card.profs:SetText(item.profText~="" and ("Professions: "..item.profText) or "|cff7c8694Professions not shared yet|r")
            card:Show()
        else
            card:Hide()
        end
    end
    canvas:SetHeight(math.max(250,#list*58))
    scroll:UpdateScrollChildRect()
end

function Suite.OpenGuildTab()
    if not page then
        rows={}; checks={}
        page=CreateFrame("Frame","SmyrnaSuiteGuildTab",UIParent,"BackdropTemplate")
        page:SetSize(840,600)
        local title=page:CreateFontString(nil,"OVERLAY","GameFontNormalLarge"); title:SetPoint("TOPLEFT",16,-14); title:SetText("Guild Sharing & Live Map"); title:SetTextColor(1,.86,.48)
        local sub=page:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); sub:SetPoint("TOPLEFT",16,-36); sub:SetText("See guildmates on your World Map and Minimap without being in a group, share professions, and sync discoveries."); sub:SetTextColor(.70,.75,.84)
        local scanBtn=CreateFrame("Button",nil,page,"UIPanelButtonTemplate"); scanBtn:SetSize(112,24); scanBtn:SetPoint("TOPRIGHT",-16,-14); scanBtn:SetText("Scan Guild"); Suite.StyleButton(scanBtn)
        scanBtn:SetScript("OnClick",function() G.Scan() end)

        local function AddCheck(parent,key,text,tipBody,x,y,onClick)
            local cb=CreateFrame("CheckButton",nil,parent,"UICheckButtonTemplate"); cb:SetPoint("TOPLEFT",x,y)
            local lbl=cb:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); lbl:SetPoint("LEFT",cb,"RIGHT",2,0); lbl:SetText(text)
            cb:SetScript("OnClick",function(self) onClick(self:GetChecked() and true or false) end)
            Suite.AttachTooltip(cb,text,tipBody,lbl)
            checks[key]=cb
            return cb
        end

        -- Settings & Cross-Module Guild Controls card
        local card=CreateFrame("Frame",nil,page,"BackdropTemplate"); card:SetSize(808,136); card:SetPoint("TOPLEFT",16,-58); Suite.StyleCard(card,.076,.088,.120); Suite.SetCornerGlow(card,1,.80,.36,.10)
        Suite.OptionSection(card,"Live Map & Professions",12,-10,382)
        AddCheck(card,"shareLocation","Share location","Broadcast your live zone coordinates to guildmates using Smyrna Suite.",10,-28,function(v)
            Config().shareLocation=v; ConfigureLocationTicker()
            if v then BroadcastLocation(true) else SendAddon("X") end
        end)
        AddCheck(card,"showMapPins","World Map pins","Show class-colored guildmate dots on the World Map even outside a group.",204,-28,function(v)
            Config().showMapPins=v; DrawWorldPins()
        end)
        AddCheck(card,"showMinimapPins","Minimap pins","Show same-zone guildmates on your Minimap and edge rim.",10,-58,function(v)
            Config().showMinimapPins=v; EnsureMiniTicker()
        end)
        AddCheck(card,"shareProfessions","Share professions","Share your professions, skill ranks, and Workshop recipes with guildmates.",204,-58,function(v)
            Config().shareProfessions=v; if v then BroadcastProfessions(true) end
        end)

        Suite.OptionSection(card,"Module Guild Sharing",414,-10,382)
        AddCheck(card,"diaryDownload","Share Diary","Allow guildmates to download your Field Diary node & rare samples on demand.",412,-28,function(v)
            local d=Suite.Modules.SmyrnaFieldDiary; if d and d.DB then d.DB.settings.allowGuildDownload=v end
        end)
        AddCheck(card,"diaryMap","Guild Diary pins","Overlay downloaded guild Field Diary finds on your World Map and Minimap.",606,-28,function(v)
            local d=Suite.Modules.SmyrnaFieldDiary; if d and d.Set then d.Set("includeShared",v) end
        end)
        AddCheck(card,"bestiaryShare","Share Bestiary","Sync creature drop samples with guildmates to improve drop rates.",412,-58,function(v)
            local b=Suite.Modules.SmyrnaBestiary; if b and b.Set then b.Set("guildShare",v) end
        end)

        local function QuickBtn(text,x,w,fn)
            local b=CreateFrame("Button",nil,page,"UIPanelButtonTemplate"); b:SetSize(w,24); b:SetPoint("TOPLEFT",x,-204); b:SetText(text); Suite.StyleButton(b)
            b:SetScript("OnClick",fn); return b
        end
        QuickBtn("Diary Samples",16,154,function() local d=Suite.Modules.SmyrnaFieldDiary; if d and d.OpenGuildWindow then d.OpenGuildWindow() end end)
        QuickBtn("Manage Diary",176,154,function() local d=Suite.Modules.SmyrnaFieldDiary; if d and d.OpenManager then d.OpenManager() end end)
        QuickBtn("Sync Discoveries",336,156,function() if Suite.Discoveries then Suite.Discoveries.SyncWithGuild() end end)
        QuickBtn("Export Finds",498,156,function() if Suite.Discoveries then Suite.Discoveries.OpenExport() end end)
        QuickBtn("Guild Crafts",660,164,function() local w=Suite.Modules.SmyrnaWorkshop; if w and w.OpenGuildProfessions then w.OpenGuildProfessions() end end)

        Suite.OptionSection(page,"Online Guildmates (Click any row for Professions & Recipes)",16,-240,808)
        filterAllBtn=CreateFrame("Button",nil,page,"UIPanelButtonTemplate"); filterAllBtn:SetSize(64,22); filterAllBtn:SetPoint("TOPLEFT",16,-258); filterAllBtn:SetText("All"); Suite.StyleButton(filterAllBtn)
        filterAllBtn:SetScript("OnClick",function() sameZoneOnly=false; G.RefreshPage() end)
        filterZoneBtn=CreateFrame("Button",nil,page,"UIPanelButtonTemplate"); filterZoneBtn:SetSize(96,22); filterZoneBtn:SetPoint("LEFT",filterAllBtn,"RIGHT",6,0); filterZoneBtn:SetText("Same Zone"); Suite.StyleButton(filterZoneBtn)
        filterZoneBtn:SetScript("OnClick",function() sameZoneOnly=true; G.RefreshPage() end)

        local qLbl=page:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); qLbl:SetPoint("LEFT",filterZoneBtn,"RIGHT",18,0); qLbl:SetText("Search:"); qLbl:SetTextColor(.93,.77,.40)
        searchBox=CreateFrame("EditBox",nil,page,"InputBoxTemplate"); searchBox:SetSize(230,22); searchBox:SetPoint("LEFT",qLbl,"RIGHT",8,0); searchBox:SetAutoFocus(false)
        searchBox:SetScript("OnTextChanged",function(self) searchQuery=self:GetText() or ""; G.RefreshPage() end)
        searchBox:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)

        statusLabel=page:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); statusLabel:SetPoint("TOPLEFT",18,-286); statusLabel:SetWidth(800); statusLabel:SetJustifyH("LEFT"); statusLabel:SetTextColor(.74,.80,.88)

        scroll=CreateFrame("ScrollFrame",nil,page,"UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT",16,-306); scroll:SetSize(792,280)
        canvas=CreateFrame("Frame",nil,scroll); canvas:SetSize(786,280); scroll:SetScrollChild(canvas)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel",function(self,delta)
            local cur,max=self:GetVerticalScroll(),self:GetVerticalScrollRange()
            if type(cur)=="number" and type(max)=="number" then self:SetVerticalScroll(math.max(0,math.min(max,cur-delta*40))) end
        end)

        page:SetScript("OnShow",function() G.RefreshPage() end)
    end
    page:Show()
    G.RefreshPage()
    local now=GetTime()
    if IsInGuild and IsInGuild() and (now-lastTabScanAt)>=15 then
        lastTabScanAt=now
        G.Scan()
    end
    return page
end

driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("ADDON_LOADED")
driver:RegisterEvent("CHAT_MSG_ADDON")
driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("PLAYER_GUILD_UPDATE")
driver:RegisterEvent("SKILL_LINES_CHANGED")
driver:RegisterEvent("GROUP_ROSTER_UPDATE")
driver:RegisterEvent("PLAYER_STARTED_MOVING")
driver:RegisterEvent("PLAYER_STOPPED_MOVING")
driver:RegisterEvent("ZONE_CHANGED_NEW_AREA")
driver:SetScript("OnEvent",function(self,event,...)
    if event=="PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
        HookWorldMap(); HookMinimap(); HookCommunities(); HookLegacyGuild()
        locMoving=(IsPlayerMoving and IsPlayerMoving()) and true or false
        ConfigureLocationTicker()
        if mapHooked and (communitiesHooked or legacyGuildHooked) then self:UnregisterEvent("ADDON_LOADED") end
        if IsInGuild and IsInGuild() then
            C_Timer.After(2,function()
                if IsInGuild and IsInGuild() then SendAddon("H"); BroadcastLocation(true); BroadcastProfessions(true) end
            end)
        else
            BroadcastProfessions(false)
        end
    elseif event=="ADDON_LOADED" then
        HookWorldMap(); HookCommunities(); HookLegacyGuild()
        if mapHooked and (communitiesHooked or legacyGuildHooked) then self:UnregisterEvent("ADDON_LOADED") end
    elseif event=="CHAT_MSG_ADDON" then
        HandleMessage(...)
    elseif event=="GROUP_ROSTER_UPDATE" then
        groupDirty=true
        if WorldMapFrame and WorldMapFrame:IsShown() then DrawWorldPins() end
        EnsureMiniTicker()
    elseif event=="PLAYER_STARTED_MOVING" then
        locMoving=true
        ScheduleLocationStep()
        EnsureMiniTicker()
    elseif event=="PLAYER_STOPPED_MOVING" then
        locMoving=false
        BroadcastLocation(false)
        EnsureMiniTicker()
    elseif event=="ZONE_CHANGED_NEW_AREA" then
        BroadcastLocation(false)
        EnsureMiniTicker()
    elseif event=="PLAYER_ENTERING_WORLD" then
        groupDirty=true
        locMoving=(IsPlayerMoving and IsPlayerMoving()) and true or false
        ConfigureLocationTicker()
        if IsInGuild and IsInGuild() then
            C_Timer.After(1.5,function() BroadcastLocation(true); EnsureMiniTicker() end)
        end
    elseif event=="PLAYER_GUILD_UPDATE" then
        ConfigureLocationTicker()
        if not IsInGuild or not IsInGuild() then wipe(peers); peerCount=0; HideWorldPins(); HideMiniPins(); SyncWorldTicker() end
        if G.RefreshPage then G.RefreshPage() end
    elseif event=="SKILL_LINES_CHANGED" then
        ownRecipesCache=nil
        BroadcastProfessions(false)
    end
end)
