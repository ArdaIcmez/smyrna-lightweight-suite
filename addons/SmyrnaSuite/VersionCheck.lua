local addon,Suite=...
local Check={};Suite.VersionCheck=Check
local PREFIX="SmyrnaVer1"
local frame=CreateFrame("Frame")
local channels={GUILD=true,PARTY=true,RAID=true,INSTANCE_CHAT=true}
local sent,waiting,notified={},{},{}
local queued=false
local epoch=0
local ownSuite,ownDB
local function Public(value) return not issecretvalue or not issecretvalue(value) end
local function Parse(value)
    if not Public(value) or type(value)~="string" or #value>17 then return end
    local a,b,c=value:match("^(%d+)%.(%d+)%.(%d+)$")
    a,b,c=tonumber(a),tonumber(b),tonumber(c)
    if a and a<=9999 and b<=9999 and c<=9999 then return a,b,c end
end
function Check.Newer(candidate,current)
    local a,b,c=Parse(candidate);local x,y,z=Parse(current)
    if not a or not x then return false end
    if a~=x then return a>x end
    if b~=y then return b>y end
    return c>z
end
local function Metadata(name)
    local fn=(C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if not fn then return end
    local ok,value=pcall(fn,name,"Version")
    if ok and Parse(value) then return value end
end
local function Allowed(channel)
    if channel=="GUILD" then return IsInGuild and IsInGuild() end
    if channel=="INSTANCE_CHAT" then return IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) end
    if channel=="RAID" then return IsInRaid and IsInRaid() end
    return channel=="PARTY" and IsInGroup and IsInGroup() and not (IsInRaid and IsInRaid())
end
local function Send(kind,channel)
    if Suite.Config.versionChecks==false or not ownSuite or not Allowed(channel) then return end
    local api=C_ChatInfo
    local fn=(api and api.SendAddonMessage) or SendAddonMessage
    if not fn then return end
    if api and api.AreOutgoingAddonChatMessagesRestricted and api.AreOutgoingAddonChatMessagesRestricted() then return end
    local key=kind..channel;local now=GetTime()
    if sent[key] and now-sent[key]<60 then return end
    sent[key]=now
    pcall(fn,PREFIX,kind.."|"..ownSuite.."|"..ownDB,channel)
end
local function Queue()
    if queued or Suite.Config.versionChecks==false or not ownSuite then return end
    queued=true;local token=epoch
    C_Timer.After(3,function()
        if token~=epoch then return end;queued=false
        Send("Q","GUILD")
        if LE_PARTY_CATEGORY_INSTANCE and IsInGroup and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then Send("Q","INSTANCE_CHAT")
        elseif IsInRaid and IsInRaid() then Send("Q","RAID")
        else Send("Q","PARTY") end
    end)
end
local function Notice(package,version,current)
    if notified[package] or not Check.Newer(version,current) then return end
    notified[package]=true
    DEFAULT_CHAT_FRAME:AddMessage("|cffdfb66bSmyrna:|r A newer "..package.." ("..version..") was detected in your guild or group. You have "..current..". Update your addon files.")
end
function Check.Receive(prefix,message,channel,sender)
    if not Public(prefix) or not Public(channel) then return end
    if Suite.Config.versionChecks==false or prefix~=PREFIX or not channels[channel] or not Allowed(channel) then return end
    if not Public(message) or type(message)~="string" or #message>64 or not Public(sender) or type(sender)~="string" then return end
    local kind,suite,db=message:match("^([QV])|([^|]+)|([^|]+)$")
    if not kind or not Parse(suite) or (db~="-" and not Parse(db)) then return end
    local first,last
    if UnitFullName then first,last=UnitFullName("player") elseif UnitName then first,last=UnitName("player") end
    local ownName=Suite.PlayerName(first,last)
    if sender==ownName then return end
    Notice("Smyrna Lightweight Addon Suite",suite,ownSuite)
    if ownDB and ownDB~="-" then Notice("Smyrna DB",db,ownDB) end
    if kind=="Q" and not waiting[channel] then
        local key="V"..channel
        if sent[key] and GetTime()-sent[key]<60 then return end
        waiting[channel]=true;local token=epoch
        C_Timer.After(1+math.random(),function()
            if token~=epoch then return end
            waiting[channel]=nil;Send("V",channel)
        end)
    end
end
function Suite.SetVersionChecks(enabled)
    Suite.Config.versionChecks=not not enabled
    epoch=epoch+1;queued=false;wipe(waiting)
    for _,event in ipairs({"PLAYER_ENTERING_WORLD","GROUP_ROSTER_UPDATE","GUILD_ROSTER_UPDATE","CHAT_MSG_ADDON"}) do frame:UnregisterEvent(event) end
    if not enabled then return end
    ownSuite=Metadata(addon);ownDB="-" -- Core is bundled with Suite; retain legacy wire field.
    local register=(C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix) or RegisterAddonMessagePrefix
    if not ownSuite or not register then return end
    local ok,result=pcall(register,PREFIX)
    if not ok or result==false then return end
    for _,event in ipairs({"PLAYER_ENTERING_WORLD","GROUP_ROSTER_UPDATE","GUILD_ROSTER_UPDATE","CHAT_MSG_ADDON"}) do frame:RegisterEvent(event) end
    Queue()
end
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent",function(self,event,...)
    if event=="ADDON_LOADED" then
        if (...)~=addon then return end
        self:UnregisterEvent(event);Suite.SetVersionChecks(Suite.Config.versionChecks~=false)
    elseif event=="CHAT_MSG_ADDON" then Check.Receive(...)
    else Queue() end
end)
