local _,NS=...
NS.Features={
    {"SmyrnaChat","Chat","SMYRNACHAT","options"},
    {"SmyrnaFieldDiary","Field Diary","SMYRNAFIELDDIARY","options"},
    {"SmyrnaBestiary","Bestiary","SMYRNABESTIARY","options"},
    {"SmyrnaWorkshop","Workshop","SMYRNAWORKSHOP",""},
    {"SmyrnaRemembrance","Remembrance","SMYRNAREMEMBRANCE",""},
    {"SmyrnaUpgrader","Upgrader","SMYRNAUPGRADER",""},
    {"SmyrnaMarket","Market","SMYRNAMARKETUI",""},
    {"SmyrnaJournal","Journal","SMYRNAJOURNAL",""},
    {"SmyrnaQuests","Quests","SMYRNAQUESTS",""},
    {"SmyrnaAggroMate","AggroMate","SMYRNAAGGROMATE",""},
    {"SmyrnaBagger","Bagger","SMYRNABAGGER","options"},
}
local MODULE_FOOTPRINT={
    SmyrnaChat={"~35 KB","good","Light · Session chat history, copy & time zones"},
    SmyrnaFieldDiary={"~65 KB","good","Light · Gathering/rare records & minimap pins"},
    SmyrnaBestiary={"~95 KB","detail","Medium · Loot & resistance tables (loads BestiaryDB on demand)"},
    SmyrnaWorkshop={"~80 KB","detail","Medium · Reagent/recipe index (loads WorkshopDB on demand)"},
    SmyrnaRemembrance={"~50 KB","good","Light · Player encounter history (uses RemembranceDB)"},
    SmyrnaUpgrader={"~110 KB","detail","Medium · Live hover upgrade % & slot finder (loads EquipmentDB on demand)"},
    SmyrnaMarket={"~140 KB","warning","Higher · Local AH price cache & 14-day history DB"},
    SmyrnaJournal={"~90 KB","detail","Medium · Bosses, loot, maps & portraits (uses WorldDB on demand)"},
    SmyrnaQuests={"~120 KB","warning","Higher · Map/minimap quest pins, parchment chains & tracker (uses WorldDB)"},
    SmyrnaAggroMate={"~45 KB","good","Light · Threat arc, TankMate, DPS Threat Pill & Leash Tracker"},
    SmyrnaBagger={"~55 KB","good","Light · Unified gilded bag window (replaces Bagnon)"},
}
NS.Professions={"Cooking","Alchemy","Blacksmithing","Enchanting","Engineering","FirstAid","Leatherworking","Mining","Tailoring","Herbalism","Skinning","Fishing"}
local panel,checks,statuses,dataChecks,dbcheck,alertsCheck,taylanSoundBtn,taylanThreatCheck
local function Say(text) DEFAULT_CHAT_FRAME:AddMessage("|cffdfb66bSmyrna:|r "..text) end
local function RefreshOverview()
    if not panel then return end
    for _,entry in ipairs(NS.Features) do
        local name=entry[1];local state=NS.Status(name)
        checks[name]:SetChecked(NS.Config.features[name]~=false)
        statuses[name]:SetText(NS.UIText(state,state=="On" and "good" or state=="Off" and "muted" or "warning"))
    end
    dbcheck:SetChecked(NS.Config.useDB)
    for key,b in pairs(dataChecks) do b:SetChecked(NS.Config.data[key]~=false) end
    if alertsCheck then alertsCheck:SetChecked(NS.Config.versionChecks~=false) end
    if taylanSoundBtn and NS.Taylan then taylanSoundBtn:SetText(NS.Taylan.SoundLabel()) end
    if taylanThreatCheck then taylanThreatCheck:SetChecked(not NS.Taylan or NS.Taylan.Config().threatAlert~=false) end
end
function NS.SetFeature(name,value)
    if not NS.Versions[name] then return end
    NS.Config.features[name]=not not value
end
function NS.SetAll(value)
    for _,entry in ipairs(NS.Features) do NS.SetFeature(entry[1],value) end
    if panel and panel:IsShown() then RefreshOverview() end
end
function NS.Status(name)
    if name=="SmyrnaRemembrance" and not SmyrnaRemembranceStore then return "DB disabled" end
    local enabled=NS.Config.features[name]~=false
    if NS.Loaded[name] then return enabled and "On" or "Off after reload" end
    return enabled and "On after reload" or "Off"
end
function NS.Memory()
    local api=C_AddOns or {};local update=api.UpdateAddOnMemoryUsage or UpdateAddOnMemoryUsage;local get=api.GetAddOnMemoryUsage or GetAddOnMemoryUsage
    if not update or not get then Say("Memory information is unavailable.");return end
    update()
    for _,package in ipairs({"SmyrnaSuite","SmyrnaWorldDB","SmyrnaBestiaryDB","SmyrnaWorkshopDB","SmyrnaRemembranceDB","SmyrnaEquipmentDB"}) do
        Say(string.format("%s: %.1f KiB",package,get(package) or 0))
    end
end
function NS.Apply()
    if InCombatLockdown and InCombatLockdown() then Say("Finish combat, then apply.");return end
    ReloadUI()
end
function NS.Off()
    if InCombatLockdown and InCombatLockdown() then Say("Finish combat, then turn the suite off.");return end
    local fn=(C_AddOns and C_AddOns.DisableAddOn) or DisableAddOn
    if not fn then return end
    local guid=UnitGUID and UnitGUID("player")
    if not NS.Public(guid) then guid=nil end
    local ok=pcall(fn,"SmyrnaSuite",guid)
    if ok then ReloadUI() else Say("Could not disable SmyrnaSuite automatically. Disable it in WoW AddOns.") end
end
local function Button(parent,text,width,x,y,callback,height)
    local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate");b:SetSize(width,height or 25);b:SetPoint("TOPLEFT",x,y);b:SetText(text);b:SetScript("OnClick",callback);NS.StyleButton(b);return b
end
local function Check(parent,text,x,y,callback,font)
    local b=CreateFrame("CheckButton",nil,parent,"UICheckButtonTemplate");b:SetPoint("TOPLEFT",x,y)
    local label=b:CreateFontString(nil,"OVERLAY",font or "GameFontHighlight");label:SetPoint("LEFT",b,"RIGHT",2,0);label:SetText(text)
    local w=label:GetStringWidth();if type(w)=="number" and w>0 then b:SetHitRectInsets(0,-(w+8),0,0) end
    b:SetScript("OnClick",function(self) callback(self:GetChecked()) end);return b
end
function NS.OpenOverview()
    if not panel then
        panel=CreateFrame("Frame","SmyrnaSuitePanel",UIParent,"BackdropTemplate");panel:SetSize(780,594);panel:SetPoint("CENTER");panel:SetClampedToScreen(true);panel:SetFrameStrata("DIALOG")
        NS.StylePanel(panel,true)
        local title=panel:CreateFontString(nil,"OVERLAY","GameFontNormalLarge");title:SetPoint("TOPLEFT",20,-16);title:SetText("Suite Settings");title:SetTextColor(1,.86,.48)
        local sub=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");sub:SetPoint("TOPLEFT",20,-38);sub:SetText("Turn features and built-in data guides on or off, then click Apply & reload.");sub:SetTextColor(.70,.74,.82)
        local close=NS.CloseButton(panel);panel.SuiteCloseButton=close
        checks={};statuses={};dataChecks={}

        -- Left card: Features (scrollable Modules list so any number of modules never overlap Quick actions)
        local featCard=CreateFrame("Frame",nil,panel,"BackdropTemplate");featCard:SetSize(356,452);featCard:SetPoint("TOPLEFT",20,-64);NS.StyleCard(featCard)
        NS.OptionSection(featCard,"Modules",14,-12,328)
        local modScroll=CreateFrame("ScrollFrame",nil,featCard,"UIPanelScrollFrameTemplate")
        modScroll:SetPoint("TOPLEFT",6,-32); modScroll:SetSize(322,324)
        local modCanvas=CreateFrame("Frame",nil,modScroll)
        modCanvas:SetSize(316,math.max(324,#NS.Features*30+6))
        modScroll:SetScrollChild(modCanvas)
        modScroll:EnableMouseWheel(true)
        modScroll:SetScript("OnMouseWheel",function(self,delta)
            local cur,max=self:GetVerticalScroll(),self:GetVerticalScrollRange()
            if type(cur)=="number" and type(max)=="number" then self:SetVerticalScroll(math.max(0,math.min(max,cur-delta*30))) end
        end)
        for i,entry in ipairs(NS.Features) do
            local name,label,command,arg=entry[1],entry[2],entry[3],entry[4]
            local y=-(i-1)*30
            local fp=MODULE_FOOTPRINT[name]
            checks[name]=Check(modCanvas,label,4,y,function(value) NS.SetFeature(name,value);statuses[name]:SetText(NS.UIText("Pending reload","warning")) end,"GameFontHighlightSmall")
            if fp then NS.AttachTooltip(checks[name],label.." ("..fp[1]..")",fp[3]) end
            local status=modCanvas:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");status:SetPoint("TOPLEFT",128,y-9);statuses[name]=status
            if fp then
                local est=modCanvas:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
                est:SetPoint("TOPLEFT",182,y-9); est:SetText(NS.UIText(fp[1],fp[2]))
            end
            Button(modCanvas,"Open",62,250,y-3,function() if NS.Loaded[name] and SlashCmdList[command] then SlashCmdList[command](arg) else Say("Enable "..label.." and apply first.") end end,22)
        end
        NS.OptionSection(featCard,"Quick actions",14,-366,328)
        Button(featCard,"All on",98,14,-386,function() NS.SetAll(true) end,24)
        Button(featCard,"All off",98,118,-386,function() NS.SetAll(false) end,24)
        alertsCheck=Check(featCard,"Update alerts",222,-384,function(value) NS.SetVersionChecks(value) end,"GameFontHighlightSmall")
        alertsCheck:SetChecked(NS.Config.versionChecks~=false)
        NS.AttachTooltip(alertsCheck,"Update alerts","Notify you in chat when a guildmate has a newer Smyrna Suite version.")
        Button(featCard,"AoE range",98,14,-416,function() if NS.AoE then NS.AoE.Open() end end,24)
        Button(featCard,"Memory",98,118,-416,NS.Memory,24)
        Button(featCard,"Benchmark",116,222,-416,function() if NS.RunBenchmark then NS.RunBenchmark() else NS.Memory() end end,24)

        -- Right card: Optional Reference Databases
        local dbCard=CreateFrame("Frame",nil,panel,"BackdropTemplate");dbCard:SetSize(372,452);dbCard:SetPoint("TOPLEFT",388,-64);NS.StyleCard(dbCard)
        NS.OptionSection(dbCard,"Built-in Data Guides",14,-12,344)
        dbcheck=Check(dbCard,"Built-in guides",10,-32,function(value) NS.Config.useDB=value end)
        NS.AttachTooltip(dbcheck,"Built-in guides","Enable bundled SmyrnaWorldDB, BestiaryDB, WorkshopDB, and EquipmentDB data packages.")
        NS.OptionSection(dbCard,"Profession Recipes",14,-66,344)
        for i,slug in ipairs(NS.Professions) do
            local key="recipe:"..slug
            local col=math.floor((i-1)/6);local row=(i-1)%6
            dataChecks[key]=Check(dbCard,slug=="FirstAid" and "First Aid" or slug,10+col*176,-84-row*29,function(value) NS.Config.data[key]=value end,"GameFontHighlightSmall")
        end
        NS.OptionSection(dbCard,"World & Gear Guides",14,-264,344)
        dataChecks.loot=Check(dbCard,"Creature loot",10,-284,function(value) NS.Config.data.loot=value end,"GameFontHighlightSmall")
        NS.AttachTooltip(dataChecks.loot,"Creature loot","Enable Bestiary drop tables and resistance matchup guides.")
        dataChecks.equipment=Check(dbCard,"Gear catalog",186,-284,function(value) NS.Config.data.equipment=value end,"GameFontHighlightSmall")
        NS.AttachTooltip(dataChecks.equipment,"Gear catalog","Enable EquipmentDB item stats and drop sources for Upgrader & Journal.")
        NS.OptionSection(dbCard,"Taylan",14,-324,344)
        Button(dbCard,"Taylan",110,14,-344,function() if NS.Taylan then NS.Taylan.Toggle() end end,24)
        taylanSoundBtn=Button(dbCard,(NS.Taylan and NS.Taylan.SoundLabel()) or "Sound: Both",116,130,-344,function()
            if NS.Taylan and taylanSoundBtn then taylanSoundBtn:SetText(NS.Taylan.CycleSound()) end
        end,24)
        Button(dbCard,"Test",96,252,-344,function() if NS.Taylan then NS.Taylan.FlashThreat(true) end end,24)
        taylanThreatCheck=Check(dbCard,"Threat alert",10,-374,function(value)
            if NS.Taylan then NS.Taylan.Config().threatAlert=value and true or false end
        end,"GameFontHighlightSmall")
        taylanThreatCheck:SetChecked(not NS.Taylan or NS.Taylan.Config().threatAlert~=false)
        NS.AttachTooltip(taylanThreatCheck,"Threat alert","Flash Taylan in a thin red threat frame with alert sound for 1 second whenever a mob aggros you.")

        -- Bottom footer bar
        local foot=CreateFrame("Frame",nil,panel,"BackdropTemplate");foot:SetSize(740,54);foot:SetPoint("TOPLEFT",20,-526);NS.StyleCard(foot,.07,.08,.11)
        local note=foot:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");note:SetPoint("LEFT",14,0);note:SetWidth(390);note:SetJustifyH("LEFT");note:SetTextColor(.70,.74,.82)
        note:SetText("Changes take effect after clicking Apply & reload.\nDisabling Smyrna Suite in WoW AddOns turns off all modules.")
        Button(foot,"Disable suite",132,424,-14,NS.Off,26)
        local applyBtn=Button(foot,"Apply & reload",162,564,-14,NS.Apply,26)
        NS.SetButtonSelected(applyBtn,true)
        UISpecialFrames[#UISpecialFrames+1]="SmyrnaSuitePanel"
    end
    RefreshOverview()
    panel:Show()
    return panel
end
local debugDriver,debugActive,lastBlockLog,blockLogCount
local function ToggleDebugTaint()
    debugActive=not debugActive
    if debugActive then
        if not debugDriver then debugDriver=CreateFrame("Frame") end
        lastBlockLog={};blockLogCount=0
        pcall(debugDriver.RegisterEvent,debugDriver,"ADDON_ACTION_BLOCKED")
        pcall(debugDriver.RegisterEvent,debugDriver,"ADDON_ACTION_FORBIDDEN")
        debugDriver:SetScript("OnEvent",function(_,event,addon,func)
            if not NS.Public(addon) or addon~="SmyrnaSuite" then return end
            local fname=NS.Public(func) and tostring(func or "?") or "<secret>"
            local key=event..":"..fname
            if not lastBlockLog[key] then
                if blockLogCount>=64 then wipe(lastBlockLog);blockLogCount=0 end
                lastBlockLog[key]=true;blockLogCount=blockLogCount+1
                local st=debugstack and debugstack(2,6,0) or ""
                st=st:gsub("\n"," | "):sub(1,220)
                Say("|cffff6655"..event..":|r "..fname..(st~="" and (" -> "..st) or ""))
            end
        end)
        Say("Taint debug logging ON (session only).")
    else
        if debugDriver then
            debugDriver:UnregisterEvent("ADDON_ACTION_BLOCKED")
            debugDriver:UnregisterEvent("ADDON_ACTION_FORBIDDEN")
            debugDriver:SetScript("OnEvent",nil)
        end
        Say("Taint debug logging OFF.")
    end
end
SLASH_SMYRNASUITE1="/smyrna";SLASH_SMYRNASUITE2="/smyrnasuite"
SlashCmdList.SMYRNASUITE=function(input)
    local cmd=string.lower((input or ""):match("^%s*(%S*)") or "")
    if cmd=="off" then NS.Off()
    elseif cmd=="debug" then ToggleDebugTaint()
    elseif cmd=="guild" then if NS.OpenTab then NS.OpenTab(-2) end
    elseif cmd=="perf" or cmd=="mem" then if NS.RunBenchmark then NS.RunBenchmark(true) else NS.Memory() end
    elseif cmd=="bench" or cmd=="benchmark" then if NS.RunBenchmark then NS.RunBenchmark(false) else NS.Memory() end
    elseif cmd=="status" then
        for _,entry in ipairs(NS.Features) do Say(entry[2]..": "..NS.Status(entry[1])) end
        local api=C_AddOns or {}
        local isLoaded=api.IsAddOnLoaded or IsAddOnLoaded
        local loadable=api.IsAddOnLoadable or IsAddOnLoadable
        for _,pkg in ipairs({"SmyrnaWorldDB","SmyrnaBestiaryDB","SmyrnaWorkshopDB","SmyrnaEquipmentDB","SmyrnaRemembranceDB"}) do
            local loaded=isLoaded and isLoaded(pkg) and "loaded" or "not loaded"
            local can,why=nil,nil
            if loadable then can,why=loadable(pkg) end
            Say(pkg..": "..loaded..(can~=nil and (" (loadable="..tostring(can)..(why and (","..tostring(why)) or "")..")") or ""))
        end
        if NS.Equipment and NS.Equipment.lastError then Say("Equipment DB: "..NS.Equipment.lastError) end
        if NS.lastDBError then Say("Reference DB: "..NS.lastDBError) end
    else NS.Open() end
end

local loginDriver=CreateFrame("Frame")
loginDriver:RegisterEvent("PLAYER_LOGIN")
loginDriver:SetScript("OnEvent",function(self)
    self:UnregisterEvent("PLAYER_LOGIN")
    self:SetScript("OnEvent",nil)
    local function Announce()
        local ready={}
        for _,entry in ipairs(NS.Features) do
            if NS.Loaded[entry[1]] then ready[#ready+1]=entry[2] end
        end
        if _G.SmyrnaEmoty then ready[#ready+1]="Emoty" end
        table.sort(ready)
        if #ready>0 then
            Say("Ready ("..table.concat(ready,", ").."). /smyrna opens menu.")
        else
            Say("Ready (no modules enabled). /smyrna opens settings.")
        end
    end
    if C_Timer and C_Timer.After then C_Timer.After(0,Announce) else Announce() end
end)
