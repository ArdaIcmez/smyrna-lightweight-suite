local _,NS=...
NS.Features={{"SmyrnaChat","Chat","SMYRNACHAT","options"},{"SmyrnaFieldDiary","Field Diary","SMYRNAFIELDDIARY","options"},{"SmyrnaBestiary","Bestiary","SMYRNABESTIARY","options"},{"SmyrnaWorkshop","Workshop","SMYRNAWORKSHOP",""},{"SmyrnaRemembrance","Remembrance","SMYRNAREMEMBRANCE",""}}
NS.Professions={"Cooking","Alchemy","Blacksmithing","Enchanting","Engineering","FirstAid","Leatherworking","Mining","Tailoring","Herbalism","Skinning","Fishing"}
local panel,checks,statuses,dataChecks,dbcheck
local function Say(text) DEFAULT_CHAT_FRAME:AddMessage("|cffdfb66bSmyrna:|r "..text) end
function NS.SetFeature(name,value)
    if not NS.Versions[name] then return end
    NS.Config.features[name]=not not value
end
function NS.SetAll(value)
    for _,entry in ipairs(NS.Features) do NS.SetFeature(entry[1],value) end
    if panel then NS.Open() end
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
    for _,package in ipairs({"SmyrnaSuite","SmyrnaBestiaryDB","SmyrnaWorkshopDB","SmyrnaRemembranceDB"}) do
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
    fn("SmyrnaSuite",UnitName("player"));ReloadUI()
end
local function Button(parent,text,width,x,y,callback)
    local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate");b:SetSize(width,25);b:SetPoint("TOPLEFT",x,y);b:SetText(text);b:SetScript("OnClick",callback);NS.StyleButton(b);return b
end
local function Check(parent,text,x,y,callback)
    local b=CreateFrame("CheckButton",nil,parent,"UICheckButtonTemplate");b:SetPoint("TOPLEFT",x,y)
    local label=b:CreateFontString(nil,"OVERLAY","GameFontHighlight");label:SetPoint("LEFT",b,"RIGHT",0,0);label:SetText(text)
    b:SetScript("OnClick",function(self) callback(self:GetChecked()) end);return b
end
function NS.OpenOverview()
    if not panel then
        panel=CreateFrame("Frame","SmyrnaSuitePanel",UIParent,"BackdropTemplate");panel:SetSize(520,650);panel:SetPoint("CENTER");panel:SetClampedToScreen(true);panel:SetFrameStrata("DIALOG")
        panel:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12});panel:SetBackdropColor(.04,.04,.04,.98)
        local title=panel:CreateFontString(nil,"OVERLAY","GameFontNormalLarge");title:SetPoint("TOPLEFT",22,-20);title:SetText("Smyrna Lightweight Addon Suite")
        local close=CreateFrame("Button",nil,panel,"UIPanelCloseButton");close:SetPoint("TOPRIGHT");panel.SuiteCloseButton=close
        checks={};statuses={};dataChecks={}
        for i,entry in ipairs(NS.Features) do
            local name,label,command,arg=entry[1],entry[2],entry[3],entry[4]
            checks[name]=Check(panel,label,18,-46-(i-1)*31,function(value) NS.SetFeature(name,value);statuses[name]:SetText("Apply to update") end)
            local status=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");status:SetPoint("TOPLEFT",185,-57-(i-1)*31);statuses[name]=status
            Button(panel,"Options",80,412,-49-(i-1)*31,function() if NS.Loaded[name] and SlashCmdList[command] then SlashCmdList[command](arg) else Say("Enable "..label.." and apply first.") end end)
        end
        Button(panel,"All features on",145,24,-246,function() NS.SetAll(true) end)
        Button(panel,"All features off",145,180,-246,function() NS.SetAll(false) end)
        Check(panel,"Update alerts",335,-243,function(value) NS.SetVersionChecks(value) end):SetChecked(NS.Config.versionChecks~=false)
        dbcheck=Check(panel,"Use optional reference databases",18,-282,function(value) NS.Config.useDB=value end)
        -- Keep reference choices clipped independently of the fixed action buttons.
        local references=CreateFrame("ScrollFrame",nil,panel,"UIPanelScrollFrameTemplate")
        references:SetPoint("TOPLEFT",20,-319);references:SetSize(450,168)
        local referenceContent=CreateFrame("Frame",nil,references);referenceContent:SetSize(450,202)
        references:SetScrollChild(referenceContent)
        for i,slug in ipairs(NS.Professions) do
            local key="recipe:"..slug
            dataChecks[key]=Check(referenceContent,slug=="FirstAid" and "First Aid" or slug,math.floor((i-1)/6)*230,-((i-1)%6)*28,function(value) NS.Config.data[key]=value end)
        end
        dataChecks.loot=Check(referenceContent,"Mob loot references",0,-168,function(value) NS.Config.data.loot=value end)
        Button(panel,"AoE range",100,24,-508,function() if NS.AoE then NS.AoE.Open() end end)
        Button(panel,"Memory",100,132,-508,NS.Memory)
        Button(panel,"Turn suite off & reload",205,268,-508,NS.Off)
        local note=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");note:SetPoint("TOPLEFT",24,-554);note:SetText("Feature/data changes apply after reload.\nOne Suite checkbox in WoW disables everything.")
        Button(panel,"Apply & reload",150,185,-608,NS.Apply)
        UISpecialFrames[#UISpecialFrames+1]="SmyrnaSuitePanel"
    end
    for _,entry in ipairs(NS.Features) do local name=entry[1];checks[name]:SetChecked(NS.Config.features[name]~=false);statuses[name]:SetText(NS.UIText(NS.Status(name),NS.Status(name)=="On" and "good" or NS.Status(name)=="Off" and "muted" or "warning")) end
    dbcheck:SetChecked(NS.Config.useDB)
    for key,b in pairs(dataChecks) do b:SetChecked(NS.Config.data[key]~=false) end
    panel:Show()
    return panel
end
SLASH_SMYRNASUITE1="/smyrna";SLASH_SMYRNASUITE2="/smyrnasuite"
SlashCmdList.SMYRNASUITE=function(input)
    if input=="off" then NS.Off() elseif input=="perf" then NS.Memory() elseif input=="status" then for _,entry in ipairs(NS.Features) do Say(entry[2]..": "..NS.Status(entry[1])) end else NS.Open() end
end
