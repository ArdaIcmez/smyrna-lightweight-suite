local _,Suite=...
local NS=Suite.Modules.SmyrnaFieldDiary
if not NS then return end
local C=NS.Core
local PREFIX="SMYRNAFD2"
local KINDS={"mine","herb","skin","fish","rare"}
local KIND_LABELS={mine="Mine",herb="Herb",skin="Skin",fish="Fish",rare="Rare"}
local KIND_FULL={mine="Mining",herb="Herbalism",skin="Skinning",fish="Fishing",rare="Rare"}
local KIND_HEX={mine="ffb333",herb="33ff66",skin="cc8040",fish="33bfff",rare="c8cdd6"}

local frame=CreateFrame("Frame")
local peers={}        -- [origin] = { origin, name, counts={mine,herb,skin,fish,rare}, spots={...}, total, seen, state, received }
local peerCount=0
local activeDownloads={} -- [origin] = { expires, sender, received, expected }
local reqCooldown={}  -- [sender] = lastTime
local peerOrigins={}  -- [sender] = origin (anti-spoofing)
local peerRates={}    -- [sender] = { second, count }
local globalSec,globalMsgCount=0,0
local sendTicker,sendQueue,sendIdx,sendOrigin
local window,peerRows,sampleRows,filterKind,filterPeer=nil,{},{},"all","all"
local peerCanvas,peerScroll,sampleCanvas,sampleScroll,statusLabel,summaryLabel,scanBtn,allowCheck,mapCheck,clearBtn,filterBarBtns

local function CleanSender(sender)
    if not C.Public(sender) or type(sender)~="string" then return nil end
    local short=sender:match("^([^-]+)") or sender
    short=(short:gsub("^%s+",""):gsub("%s+$",""))
    if short=="" or #short>64 or short:find("[%c|,]") then return nil end
    return short
end

local function IsSelf(sender)
    local first,last
    if UnitFullName then first,last=UnitFullName("player") elseif UnitName then first,last=UnitName("player") end
    local own=Suite.PlayerName and Suite.PlayerName(first,last)
    local short=sender:match("^([^-]+)")
    if own and (sender==own or short==own) then return true end
    if C.Public(first) and type(first)=="string" and (sender==first or short==first) then return true end
    return false
end

local function SafeLabel(text)
    if not C.Public(text) or type(text)~="string" then return "" end
    text=text:gsub("[%c|]"," "):gsub("%s+"," "):gsub("^%s+",""):gsub("%s+$","")
    return text:sub(1,48)
end

local function PrimaryItemAndLabel(r)
    local bestID,bestUnits=0,-1
    for id,totals in pairs(r[10] or {}) do
        if type(id)=="number" and id>0 and type(totals)=="table" and (totals[1] or 0)>bestUnits then
            bestID=id; bestUnits=totals[1] or 0
        end
    end
    local label=""
    if type(r[14])=="table" then
        for k,v in pairs(r[14]) do
            if type(v)=="string" and v~="" then
                label=SafeLabel(v)
                if r[4]=="rare" and type(k)=="number" and k>0 and bestID==0 then bestID=k end
                break
            end
        end
    end
    if label=="" and bestID>0 then
        local get=C_Item and C_Item.GetItemInfo or GetItemInfo
        if get then
            local iname=get(bestID)
            if C.Public(iname) and type(iname)=="string" then label=SafeLabel(iname) end
        end
    end
    return bestID,label
end

local function OwnCounts()
    local obs={mine=0,herb=0,skin=0,fish=0,rare=0}
    local spots={mine=0,herb=0,skin=0,fish=0,rare=0}
    local now=C.Now()
    if NS.DB and NS.DB.own and NS.DB.own.records then
        for _,r in pairs(NS.DB.own.records) do
            local k=r[4]
            if k and obs[k]~=nil and C.Number(r[5],1,10000000,true) and C.Number(r[9],0,now+300) and now-r[9]<=C.RETENTION then
                obs[k]=obs[k]+r[5]
                spots[k]=spots[k]+1
            end
        end
    end
    return obs,spots
end

local function SendAddon(payload)
    if not IsInGuild or not IsInGuild() then return false end
    if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then return false end
    if C_ChatInfo.AreOutgoingAddonChatMessagesRestricted and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted() then return false end
    if type(payload)~="string" or #payload>248 then return false end
    C_ChatInfo.SendAddonMessage(PREFIX,payload,"GUILD")
    return true
end

local function StopUpload()
    if sendTicker then sendTicker:Cancel(); sendTicker=nil end
    sendQueue=nil; sendIdx=nil; sendOrigin=nil
end

local function SendSummary()
    if not NS.DB or not NS.DB.origin then return end
    if NS.DB.settings.allowGuildDownload==false then return end
    local obs,spots=OwnCounts()
    local parts={"S",NS.DB.origin}
    for _,k in ipairs(KINDS) do parts[#parts+1]=spots[k]..":"..obs[k] end
    SendAddon(table.concat(parts,"|"))
end

local function StartUpload(targetFilter)
    if not NS.DB or not NS.DB.origin or NS.DB.settings.allowGuildDownload==false then return end
    if sendTicker then return end
    local now=C.Now()
    local list={}
    for _,r in pairs(NS.DB.own.records) do
        local k=r[4]
        if C.kinds[k] and (targetFilter=="all" or targetFilter==k) and C.Number(r[5],1,10000000,true) and C.Number(r[9],0,now+300) and now-r[9]<=C.RETENTION then
            list[#list+1]=r
        end
    end
    table.sort(list,function(a,b)
        if a[5]~=b[5] then return a[5]>b[5] end
        return (a[9] or 0)>(b[9] or 0)
    end)
    local cap=math.min(#list,250)
    local packets={}
    for i=1,cap do
        local r=list[i]
        local itemID,label=PrimaryItemAndLabel(r)
        local ex,ey=(C.Number(r[16],0,10000,true) and r[16] or ""),(C.Number(r[17],0,10000,true) and r[17] or "")
        local msg=table.concat({"D",NS.DB.origin,r[1],r[2],r[3],r[4],r[8] or 1,r[5],r[6] or r[5],r[7] or 0,r[9],itemID,label,ex,ey},"|")
        if #msg>245 then
            msg=table.concat({"D",NS.DB.origin,r[1],r[2],r[3],r[4],r[8] or 1,r[5],r[6] or r[5],r[7] or 0,r[9],itemID,label:sub(1,20),ex,ey},"|")
        end
        if #msg<=248 then packets[#packets+1]=msg end
    end
    if #packets==0 then
        SendAddon("E|"..NS.DB.origin.."|0")
        return
    end
    sendQueue=packets; sendIdx=1; sendOrigin=NS.DB.origin
    sendTicker=C_Timer.NewTicker(.5,function()
        if not IsInGuild or not IsInGuild() then StopUpload(); return end
        local pkt=sendQueue and sendQueue[sendIdx]
        if not pkt then
            local sent=sendQueue and #sendQueue or 0
            local orig=sendOrigin
            StopUpload()
            if orig then SendAddon("E|"..orig.."|"..sent) end
            return
        end
        SendAddon(pkt)
        sendIdx=sendIdx+1
        if sendIdx>#sendQueue then
            local sent=#sendQueue; local orig=sendOrigin
            StopUpload()
            if orig then C_Timer.After(.5,function() SendAddon("E|"..orig.."|"..sent) end) end
        end
    end)
end

local function RefreshUI()
    if NS.RefreshGuildWindow then NS.RefreshGuildWindow() end
end

local function HandleAddonMessage(prefix,message,channel,sender)
    if not NS.DB then return end
    if not C.Public(prefix) or not C.Public(channel) or not C.Public(message) or not C.Public(sender) then return end
    if prefix~=PREFIX or channel~="GUILD" or type(message)~="string" or #message>250 then return end
    if IsSelf(sender) then return end
    local cleanName=CleanSender(sender)
    if not cleanName then return end
    local sec=math.floor(GetTime())
    if globalSec~=sec then globalSec=sec; globalMsgCount=0 end
    if globalMsgCount>=16 then return end
    globalMsgCount=globalMsgCount+1
    local pr=peerRates[cleanName]
    if not pr then
        local count=0
        for who,entry in pairs(peerRates) do
            if sec-entry.sec>60 then peerRates[who]=nil; peerOrigins[who]=nil else count=count+1 end
        end
        if count>=64 then return end
        pr={sec=sec,count=0}; peerRates[cleanName]=pr
    end
    if pr.sec~=sec then pr.sec=sec; pr.count=0 end
    if pr.count>=6 then return end
    pr.count=pr.count+1
    local op=message:sub(1,1)
    if op=="P" then
        if NS.DB.settings.allowGuildDownload==false then return end
        local now=GetTime()
        if reqCooldown["ping:"..cleanName] and now-reqCooldown["ping:"..cleanName]<4 then return end
        reqCooldown["ping:"..cleanName]=now
        -- Small jitter so multiple guildies do not burst on the same frame.
        C_Timer.After(.1+math.random()*.45,SendSummary)
    elseif op=="S" then
        local orig,m1,m2,h1,h2,s1,s2,f1,f2,r1,r2=message:match("^S|([%w]+)|(%d+):(%d+)|(%d+):(%d+)|(%d+):(%d+)|(%d+):(%d+)|(%d+):(%d+)$")
        if not orig or #orig<8 or #orig>24 or orig==NS.DB.origin then return end
        if peerOrigins[cleanName] and peerOrigins[cleanName]~=orig then return end
        peerOrigins[cleanName]=orig
        if not peers[orig] then
            if peerCount>=64 then return end
            peerCount=peerCount+1
        end
        local counts={mine=tonumber(m2) or 0,herb=tonumber(h2) or 0,skin=tonumber(s2) or 0,fish=tonumber(f2) or 0,rare=tonumber(r2) or 0}
        local spots={mine=tonumber(m1) or 0,herb=tonumber(h1) or 0,skin=tonumber(s1) or 0,fish=tonumber(f1) or 0,rare=tonumber(r1) or 0}
        local total=counts.mine+counts.herb+counts.skin+counts.fish+counts.rare
        local prev=peers[orig]
        peers[orig]={origin=orig,name=cleanName,counts=counts,spots=spots,total=total,seen=GetTime(),state=prev and prev.state or nil,received=prev and prev.received or 0}
        RefreshUI()
    elseif op=="R" then
        if NS.DB.settings.allowGuildDownload==false then return end
        local targetOrig,kind=message:match("^R|([%w]+)|(%a+)$")
        if not targetOrig or targetOrig~=NS.DB.origin then return end
        if kind~="all" and not C.kinds[kind] then return end
        local now=GetTime()
        if reqCooldown["req:"..cleanName] and now-reqCooldown["req:"..cleanName]<12 then return end
        reqCooldown["req:"..cleanName]=now
        StartUpload(kind)
    elseif op=="D" then
        local orig,map,gx,gy,kind,rev,n,units,value,last,itemStr,tail=message:match("^D|([%w]+)|(%d+)|(%d+)|(%d+)|(%a+)|(%d+)|(%d+)|(%d+)|(%d+)|(%d+)|(%d+)|(.*)$")
        if not orig or #orig<8 or #orig>24 or orig==NS.DB.origin or not C.kinds[kind] then return end
        if peerOrigins[cleanName] and peerOrigins[cleanName]~=orig then return end
        peerOrigins[cleanName]=orig
        local dl=activeDownloads[orig]
        if dl and GetTime()>dl.expires then activeDownloads[orig]=nil; dl=nil end
        local allowed=(dl~=nil) or NS.DB.settings.receive
        if not allowed then return end
        local label,exStr,eyStr=tail:match("^([^|]*)|(%d*)|(%d*)$")
        if not label then label=tail end
        local now=C.Now()
        local r={tonumber(map),tonumber(gx),tonumber(gy),kind,tonumber(n),tonumber(units),tonumber(value),tonumber(rev),tonumber(last)}
        if not C.Number(r[1],1,1000000,true) or not C.Number(r[2],0,3999,true) or not C.Number(r[3],0,3999,true)
            or not C.Number(r[8],1,100000000,true) or not C.Number(r[5],1,10000000,true)
            or not C.Number(r[6],r[5],100000000,true) or not C.Number(r[7],0,1000000000000,true)
            or not C.Number(r[9],now-C.RETENTION,now+300,true) then return end
        local info=C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(r[1])
        local width,height=(NS.MapWorldSize and NS.MapWorldSize(r[1])) or (C_Map and C_Map.GetMapWorldSize and C_Map.GetMapWorldSize(r[1]))
        if not info or not C.Number(width,1,200000) or not C.Number(height,1,200000) or r[2]*50>=width or r[3]*50>=height then return end
        local ex,ey=tonumber(exStr),tonumber(eyStr)
        if C.Number(ex,0,10000,true) and C.Number(ey,0,10000,true) then r[16]=ex; r[17]=ey end
        local itemID=tonumber(itemStr) or 0
        if itemID>0 and C.Number(itemID,1,10000000,true) and kind~="rare" then
            r[10]={[itemID]={r[6],r[7]}}
            r[11]=1
        end
        local cleanLabel=SafeLabel(label)
        if cleanLabel~="" then
            local key=(kind=="rare" and itemID>0) and itemID or cleanLabel
            r[14]={[key]=cleanLabel}
            r[15]=1
        end
        if C.Merge(NS.DB,cleanName,orig,r) then NS.Dirty() end
        if dl then
            dl.received=dl.received+1
            dl.expires=GetTime()+25
            if peers[orig] then peers[orig].state="Downloading "..dl.received.."..."; peers[orig].received=dl.received end
            RefreshUI()
        end
    elseif op=="E" then
        local orig,sentStr=message:match("^E|([%w]+)|(%d+)$")
        if not orig then return end
        if peerOrigins[cleanName] and peerOrigins[cleanName]~=orig then return end
        local dl=activeDownloads[orig]
        if dl then
            local count=tonumber(sentStr) or dl.received
            activeDownloads[orig]=nil
            if peers[orig] then peers[orig].state="Downloaded ("..count..")"; peers[orig].received=count end
            NS.Say("Downloaded "..count.." field diary samples from "..(dl.sender or cleanName)..".")
            if NS.RefreshOptions then NS.RefreshOptions() end
            RefreshUI()
        end
    end
end

function NS.ScanGuildies()
    if not IsInGuild or not IsInGuild() then
        NS.Say("Join a guild first to see guildmates with Smyrna Suite.")
        return false
    end
    wipe(peers); peerCount=0
    if not SendAddon("P") then
        NS.Say("Guild addon messages are currently unavailable.")
        return false
    end
    RefreshUI()
    return true
end

function NS.RequestGuildSamples(origin,kind)
    if not IsInGuild or not IsInGuild() then NS.Say("Join a guild first."); return false end
    local peer=peers[origin]
    if not peer then return false end
    kind=kind or "all"
    activeDownloads[origin]={expires=GetTime()+35,sender=peer.name,received=0}
    peer.state="Requesting..."
    -- Ensure shared discoveries are shown on the map once the user chooses to download.
    if NS.DB and NS.DB.settings and not NS.DB.settings.includeShared then
        NS.Set("includeShared",true)
    end
    SendAddon("R|"..origin.."|"..kind)
    RefreshUI()
    return true
end

local function SampleNameForRecord(r)
    local names={}
    if type(r[14])=="table" then
        for _,v in pairs(r[14]) do if type(v)=="string" and v~="" then names[#names+1]=v end end
    end
    if #names==0 and type(r[10])=="table" then
        local get=C_Item and C_Item.GetItemInfo or GetItemInfo
        for id in pairs(r[10]) do
            if type(id)=="number" and id>0 then
                local iname=get and get(id)
                if C.Public(iname) and type(iname)=="string" and iname~="" then names[#names+1]=iname
                else names[#names+1]="Item #"..id end
            end
        end
    end
    table.sort(names)
    if #names>0 then return table.concat(names,", ") end
    return KIND_FULL[r[4]] or "Discovery"
end
NS.SampleNameForRecord=SampleNameForRecord

local function CollectDownloadedSamples()
    local list={}
    if not NS.DB or not NS.DB.shared or not NS.DB.shared.records then return list end
    local mapNames={}
    for _,r in pairs(NS.DB.shared.records) do
        local k=r[4]
        if C.kinds[k] and (filterKind=="all" or filterKind==k) then
            local who=CleanSender(r[12]) or "Guildmate"
            if filterPeer=="all" or filterPeer==who then
                if not mapNames[r[1]] then
                    local info=C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(r[1])
                    mapNames[r[1]]=(info and info.name) or ("Map "..tostring(r[1]))
                end
                local coords=""
                if C.Number(r[16],0,10000) and C.Number(r[17],0,10000) then
                    coords=string.format("%.1f, %.1f",r[16]/100,r[17]/100)
                else
                    local w,h=(NS.MapWorldSize and NS.MapWorldSize(r[1])) or (C_Map and C_Map.GetMapWorldSize and C_Map.GetMapWorldSize(r[1]))
                    coords=(C.Number(w,1,200000) and C.Number(h,1,200000)) and string.format("%.1f, %.1f",100*(r[2]*50+25)/w,100*(r[3]*50+25)/h) or ""
                end
                list[#list+1]={
                    kind=k,
                    name=SampleNameForRecord(r),
                    sender=who,
                    zone=mapNames[r[1]],
                    coords=coords,
                    samples=r[5] or 1,
                    last=r[9] or 0,
                }
            end
        end
    end
    table.sort(list,function(a,b)
        if a.last~=b.last then return a.last>b.last end
        if a.samples~=b.samples then return a.samples>b.samples end
        return a.name<b.name
    end)
    return list
end

local function MakePeerCard(i)
    local card=CreateFrame("Frame",nil,peerCanvas,"BackdropTemplate")
    card:SetSize(674,50)
    Suite.StyleCard(card,.082,.094,.128)
    Suite.SetCornerGlow(card,.48,.76,1,.10)
    card.name=card:CreateFontString(nil,"OVERLAY","GameFontNormal")
    card.name:SetPoint("TOPLEFT",10,-7); card.name:SetTextColor(1,.86,.48)
    card.status=card:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    card.status:SetPoint("LEFT",card.name,"RIGHT",10,0); card.status:SetTextColor(.58,.86,1)
    card.counts=card:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    card.counts:SetPoint("TOPLEFT",10,-26); card.counts:SetWidth(545); card.counts:SetJustifyH("LEFT")
    card.btn=CreateFrame("Button",nil,card,"UIPanelButtonTemplate")
    card.btn:SetSize(102,24); card.btn:SetPoint("RIGHT",-10,0); card.btn:SetText("Download")
    Suite.StyleButton(card.btn)
    card.btn:SetScript("OnClick",function(self)
        if self.origin then NS.RequestGuildSamples(self.origin,"all") end
    end)
    peerRows[i]=card
    return card
end

local function MakeSampleRow(i)
    local row=CreateFrame("Frame",nil,sampleCanvas,"BackdropTemplate")
    row:SetSize(674,26)
    Suite.StyleCard(row,.074,.085,.116)
    row.tag=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    row.tag:SetPoint("LEFT",8,0); row.tag:SetWidth(46); row.tag:SetJustifyH("LEFT")
    row.name=row:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    row.name:SetPoint("LEFT",58,0); row.name:SetWidth(220); row.name:SetJustifyH("LEFT"); row.name:SetMaxLines(1)
    row.sender=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    row.sender:SetPoint("LEFT",284,0); row.sender:SetWidth(120); row.sender:SetJustifyH("LEFT"); row.sender:SetMaxLines(1); row.sender:SetTextColor(.62,.86,1)
    row.place=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    row.place:SetPoint("LEFT",408,0); row.place:SetWidth(190); row.place:SetJustifyH("LEFT"); row.place:SetMaxLines(1); row.place:SetTextColor(.78,.82,.88)
    row.count=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    row.count:SetPoint("RIGHT",-10,0); row.count:SetWidth(68); row.count:SetJustifyH("RIGHT"); row.count:SetTextColor(1,.86,.48)
    sampleRows[i]=row
    return row
end

function NS.RefreshGuildWindow()
    if not window or not window:IsShown() then return end
    local nowT=GetTime()
    for orig,dl in pairs(activeDownloads) do
        if nowT>dl.expires then
            activeDownloads[orig]=nil
            if peers[orig] and (peers[orig].state=="Requesting..." or (peers[orig].state and peers[orig].state:match("^Downloading"))) then
                peers[orig].state="Timed out"
            end
        end
    end
    if allowCheck then allowCheck:SetChecked(NS.DB.settings.allowGuildDownload~=false) end
    if mapCheck then mapCheck:SetChecked(NS.DB.settings.includeShared and true or false) end

    -- Section 1: Online guildies
    local list={}
    for _,p in pairs(peers) do list[#list+1]=p end
    table.sort(list,function(a,b)
        if a.total~=b.total then return a.total>b.total end
        return a.name<b.name
    end)
    if not IsInGuild or not IsInGuild() then
        statusLabel:SetText("Join a guild to scan guildmates with Smyrna Suite.")
    elseif #list==0 then
        statusLabel:SetText("No responses yet. Click Scan Guildies to find online guildmates using Smyrna Suite.")
    else
        statusLabel:SetText("Online guildmates with Smyrna Suite: "..#list.."  (click Download to pull their samples)")
    end
    for i=1,math.max(#list,#peerRows) do
        local p=list[i]
        local card=peerRows[i] or MakePeerCard(i)
        if p then
            card:ClearAllPoints(); card:SetPoint("TOPLEFT",0,-(i-1)*56)
            card.name:SetText(p.name.."  |cff9aa4b2("..p.total.." samples)|r")
            card.status:SetText(p.state or "")
            local parts={}
            for _,k in ipairs(KINDS) do
                local n=p.counts[k] or 0
                local cHex=n>0 and KIND_HEX[k] or "6e7582"
                parts[#parts+1]="|cff"..cHex..KIND_LABELS[k]..": "..n.."|r"
            end
            card.counts:SetText(table.concat(parts,"   |cff4a5260/|r   "))
            card.btn.origin=p.origin
            card.btn:SetEnabled(p.total>0 and not activeDownloads[p.origin])
            card.btn:SetText(activeDownloads[p.origin] and "Loading..." or "Download")
            card:Show()
        else
            card:Hide()
        end
    end
    peerCanvas:SetHeight(math.max(150,#list*56))
    peerScroll:UpdateScrollChildRect()

    -- Section 2: Downloaded samples
    local samples=CollectDownloadedSamples()
    if filterBarBtns then
        for key,btn in pairs(filterBarBtns) do Suite.SetButtonSelected(btn,filterKind==key) end
    end
    summaryLabel:SetText("Downloaded guild samples ("..#samples.." shown, "..(NS.DB.shared and NS.DB.shared.count or 0).." total saved)  -  hover pins on your map to see guildmate & item names.")
    local shown=math.min(#samples,150)
    for i=1,math.max(shown,#sampleRows) do
        local s=i<=shown and samples[i] or nil
        local row=sampleRows[i] or MakeSampleRow(i)
        if s then
            row:ClearAllPoints(); row:SetPoint("TOPLEFT",0,-(i-1)*30)
            row.tag:SetText("|cff"..(KIND_HEX[s.kind] or "ffffff")..KIND_LABELS[s.kind].."|r")
            row.name:SetText(s.name)
            row.sender:SetText("by "..s.sender)
            row.place:SetText(s.zone..(s.coords~="" and (" ("..s.coords..")") or ""))
            row.count:SetText(s.samples..(s.samples==1 and " sample" or " samples"))
            row:Show()
        else
            row:Hide()
        end
    end
    sampleCanvas:SetHeight(math.max(180,shown*30))
    sampleScroll:UpdateScrollChildRect()
end

function NS.OpenGuildWindow()
    if not NS.DB then return end
    if not window then
        window=CreateFrame("Frame","SmyrnaFieldDiaryGuildWindow",UIParent,"BackdropTemplate")
        window:SetSize(740,560); window:SetPoint("CENTER"); window:SetFrameStrata("FULLSCREEN_DIALOG"); window:SetFrameLevel(185); window:SetClampedToScreen(true)
        window:SetMovable(true); window:EnableMouse(true); window:RegisterForDrag("LeftButton")
        window:SetScript("OnDragStart",function(self) if not (InCombatLockdown and InCombatLockdown()) then self:StartMoving() end end)
        window:SetScript("OnDragStop",window.StopMovingOrSizing)
        Suite.StylePanel(window,true); Suite.HeaderStrip(window,42); Suite.CloseButton(window)
        local title=window:CreateFontString(nil,"OVERLAY","GameFontNormalLarge"); title:SetPoint("TOPLEFT",16,-12); title:SetText("Field Diary - Guild Samples"); title:SetTextColor(1,.86,.48)
        scanBtn=CreateFrame("Button",nil,window,"UIPanelButtonTemplate"); scanBtn:SetSize(118,24); scanBtn:SetPoint("TOPRIGHT",-46,-10); scanBtn:SetText("Scan Guildies"); Suite.StyleButton(scanBtn)
        scanBtn:SetScript("OnClick",function() NS.ScanGuildies() end)

        allowCheck=CreateFrame("CheckButton",nil,window,"UICheckButtonTemplate"); allowCheck:SetPoint("TOPLEFT",14,-48)
        local allowText=allowCheck:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); allowText:SetPoint("LEFT",allowCheck,"RIGHT",2,0); allowText:SetText("Let guildmates see my sample counts & download them")
        allowCheck:SetScript("OnClick",function(self) NS.DB.settings.allowGuildDownload=self:GetChecked() and true or false end)

        mapCheck=CreateFrame("CheckButton",nil,window,"UICheckButtonTemplate"); mapCheck:SetPoint("TOPLEFT",380,-48)
        local mapText=mapCheck:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); mapText:SetPoint("LEFT",mapCheck,"RIGHT",2,0); mapText:SetText("Show downloaded guild samples on map")
        mapCheck:SetScript("OnClick",function(self) NS.Set("includeShared",self:GetChecked()) end)

        Suite.OptionSection(window,"Online Guildmates With Smyrna Suite",16,-80,708)
        statusLabel=window:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); statusLabel:SetPoint("TOPLEFT",18,-98); statusLabel:SetWidth(700); statusLabel:SetJustifyH("LEFT"); statusLabel:SetTextColor(.74,.80,.88)

        peerScroll=CreateFrame("ScrollFrame",nil,window,"UIPanelScrollFrameTemplate")
        peerScroll:SetPoint("TOPLEFT",16,-116); peerScroll:SetSize(692,162)
        peerCanvas=CreateFrame("Frame",nil,peerScroll); peerCanvas:SetSize(674,162); peerScroll:SetScrollChild(peerCanvas)
        peerScroll:EnableMouseWheel(true)
        peerScroll:SetScript("OnMouseWheel",function(self,delta)
            local cur,max=self:GetVerticalScroll(),self:GetVerticalScrollRange()
            if type(cur)=="number" and type(max)=="number" then self:SetVerticalScroll(math.max(0,math.min(max,cur-delta*36))) end
        end)

        Suite.OptionSection(window,"Downloaded Guild Samples (Name & Guildmate)",16,-288,708)
        summaryLabel=window:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); summaryLabel:SetPoint("TOPLEFT",18,-306); summaryLabel:SetWidth(580); summaryLabel:SetJustifyH("LEFT"); summaryLabel:SetTextColor(.74,.80,.88)
        clearBtn=CreateFrame("Button",nil,window,"UIPanelButtonTemplate"); clearBtn:SetSize(112,20); clearBtn:SetPoint("TOPRIGHT",-18,-302); clearBtn:SetText("Clear downloaded"); Suite.StyleButton(clearBtn)
        clearBtn:SetScript("OnClick",function()
            NS.DB.shared=C.NewStore()
            NS.DB.revision=NS.DB.revision+1
            NS.Dirty()
            if NS.RefreshOptions then NS.RefreshOptions() end
            RefreshUI()
            NS.Say("Cleared downloaded guild samples.")
        end)

        filterBarBtns={}
        local fx=18
        for _,entry in ipairs({{"all","All",48},{"mine","Mine",56},{"herb","Herb",56},{"skin","Skin",56},{"fish","Fish",56},{"rare","Rare",56}}) do
            local key,label,w=entry[1],entry[2],entry[3]
            local b=CreateFrame("Button",nil,window,"UIPanelButtonTemplate"); b:SetSize(w,20); b:SetPoint("TOPLEFT",fx,-326); b:SetText(label); Suite.StyleButton(b)
            b:SetScript("OnClick",function() filterKind=key; RefreshUI() end)
            filterBarBtns[key]=b; fx=fx+w+6
        end

        sampleScroll=CreateFrame("ScrollFrame",nil,window,"UIPanelScrollFrameTemplate")
        sampleScroll:SetPoint("TOPLEFT",16,-354); sampleScroll:SetSize(692,190)
        sampleCanvas=CreateFrame("Frame",nil,sampleScroll); sampleCanvas:SetSize(674,190); sampleScroll:SetScrollChild(sampleCanvas)
        sampleScroll:EnableMouseWheel(true)
        sampleScroll:SetScript("OnMouseWheel",function(self,delta)
            local cur,max=self:GetVerticalScroll(),self:GetVerticalScrollRange()
            if type(cur)=="number" and type(max)=="number" then self:SetVerticalScroll(math.max(0,math.min(max,cur-delta*36))) end
        end)

        UISpecialFrames[#UISpecialFrames+1]="SmyrnaFieldDiaryGuildWindow"
    end
    window:Show()
    RefreshUI()
    if IsInGuild and IsInGuild() then NS.ScanGuildies() end
end

frame:RegisterEvent("PLAYER_LOGIN")
frame:RegisterEvent("CHAT_MSG_ADDON")
frame:SetScript("OnEvent",function(self,event,...)
    if event=="PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        if NS.DB and NS.DB.settings and NS.DB.settings.allowGuildDownload==nil then
            NS.DB.settings.allowGuildDownload=true
        end
        if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
            C_ChatInfo.RegisterAddonMessagePrefix(PREFIX)
        end
    elseif event=="CHAT_MSG_ADDON" then
        HandleAddonMessage(...)
    end
end)
