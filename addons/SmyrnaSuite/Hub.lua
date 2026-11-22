local _,NS=...
local hub,content,active,opening,preview
local pages={}
local texture="Interface\\AddOns\\SmyrnaSuite\\Media\\Smyrna35"
local openers={"OpenSettings","OpenOptions","OpenOptions","Open","Open","Open"}
local original={}
-- Keep stable feature IDs for existing module callers; sort only navigation.
local tabOrder={}
for i in ipairs(NS.Features) do tabOrder[#tabOrder+1]=i end
table.sort(tabOrder,function(a,b) return NS.Features[a][2]<NS.Features[b][2] end)
NS.TabOrder=tabOrder
for i,entry in ipairs(NS.Features) do
    local module=NS.Modules[entry[1]]
    if module then
        local method=openers[i];original[i]=module[method]
        module[method]=function(...) if opening then return original[i](...) end;return NS.OpenTab(i) end
    end
end
function NS.OpenTab(index)
    index=index or 0
    if not hub then
        hub=CreateFrame("Frame","SmyrnaSuiteHub",UIParent,"BackdropTemplate")
        hub:SetSize(960,850);hub:SetPoint("CENTER");hub:SetClampedToScreen(true);hub:SetFrameStrata("DIALOG")
        hub:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12});hub:SetBackdropColor(.035,.035,.04,.98)
        local title=hub:CreateFontString(nil,"OVERLAY","GameFontNormalLarge");title:SetPoint("TOP",0,-16);title:SetText("Smyrna Lightweight Addon Suite")
        NS.StylePanel(hub)
        NS.HeaderStrip(hub);title:SetTextColor(1,.83,.43)
        local close=NS.CloseButton(hub)
        content=CreateFrame("Frame",nil,hub);content:SetPoint("TOPLEFT",10,-116);content:SetSize(940,740)
        hub.tabs={}
        local settings=CreateFrame("Button",nil,hub);settings:SetSize(92,22);settings:SetPoint("TOP",0,-42)
        local gear=settings:CreateTexture(nil,"OVERLAY",nil,1);gear:SetSize(18,18);gear:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
        local caption=settings:CreateFontString(nil,"OVERLAY","GameFontNormal");caption:SetText("Settings")
        local captionWidth=caption:GetStringWidth();if type(captionWidth)~="number" then captionWidth=49 end
        local groupWidth=18+6+captionWidth
        gear:SetPoint("LEFT",settings,"CENTER",-groupWidth/2,0)
        caption:SetPoint("LEFT",gear,"RIGHT",6,0)
        NS.StyleButton(settings);settings:SetScript("OnClick",function() NS.OpenTab(0) end);hub.tabs[0]=settings;hub.settingsButton=settings
        for position,tabIndex in ipairs(tabOrder) do
            local b=CreateFrame("Button",nil,hub,"UIPanelButtonTemplate");b:SetSize(90,24);b:SetPoint("TOPLEFT",16+(position-1)*132,-77)
            NS.StyleButton(b);b:SetText(NS.Features[tabIndex][2]);b:SetScript("OnClick",function() NS.OpenTab(tabIndex) end);hub.tabs[tabIndex]=b
        end
        UISpecialFrames[#UISpecialFrames+1]="SmyrnaSuiteHub"
    end
    if active then active:Hide() end
    opening=true
    local ok,page
    if index==0 then ok,page=pcall(NS.OpenOverview)
    elseif original[index] then ok,page=pcall(original[index])
    else
        page=pages[index]
        if not page then
            page=CreateFrame("Frame",nil,content);page:SetSize(700,200)
            local label=page:CreateFontString(nil,"OVERLAY","GameFontHighlight");label:SetPoint("TOPLEFT",25,-30);label:SetText("This feature is disabled. Enable it in Settings, then Apply & reload.")
        end
        ok=true
    end
    opening=false
    if not ok then error(page) end
    if page then
        local width=math.max(800,page:GetWidth()+20)
        local height=page:GetHeight()+130
        hub:SetSize(width,height);content:SetSize(width-20,page:GetHeight())
        local widths,total={},0
        for position,index in ipairs(tabOrder) do
            local label=hub.tabs[index]:GetFontString()
            local measured=label and label:GetStringWidth()
            if type(measured)~="number" then measured=#NS.Features[index][2]*7 end
            local w=math.max(66,math.min(126,measured+24));widths[position]=w;total=total+w
        end
        total=total+(#tabOrder-1)*5
        local left=(width-total)/2
        for position,index in ipairs(tabOrder) do
            local b=hub.tabs[index];b:SetSize(widths[position],24);b:ClearAllPoints();b:SetPoint("TOPLEFT",left,-77);left=left+widths[position]+5
        end
        if UIParent and UIParent.GetHeight then hub:SetScale(math.min(1,(UIParent:GetWidth()-30)/width,(UIParent:GetHeight()-30)/height)) end
        if page.SetBackdrop then page:SetBackdrop(nil) end
        local close=page.SuiteCloseButton
        if type(close)=="table" or type(close)=="userdata" then close:Hide() end
        NS.StyleTree(page)
        pages[index]=page;page:SetParent(content);page:SetScale(1);page:ClearAllPoints();page:SetPoint("TOP",content,"TOP",0,0)
        page:SetMovable(false);page:SetScript("OnDragStart",nil);page:SetScript("OnDragStop",nil);page:Show();active=page
    end
    for n,b in pairs(hub.tabs) do NS.SetButtonSelected(b,n==index);b:SetEnabled(n~=index) end
    hub:Show()
    return page
end
function NS.Open() return NS.OpenTab(1) end

local function Launcher()
    if not Minimap then return end
    local config=NS.Config.minimap or {};NS.Config.minimap=config
    config.angle=tonumber(config.angle) or 225
    local b=CreateFrame("Button","SmyrnaSuiteMinimapButton",Minimap);b:SetSize(32,32);b:SetFrameLevel(Minimap:GetFrameLevel()+8)
    b:RegisterForClicks("LeftButtonUp","RightButtonUp");b:RegisterForDrag("LeftButton")
    local icon=b:CreateTexture(nil,"ARTWORK");icon:SetSize(23,23);icon:SetPoint("CENTER")
    if not icon:SetTexture(texture) then icon:SetTexture("Interface\\Icons\\INV_Misc_Archaeology_Highborne_Scroll") end
    local border=b:CreateTexture(nil,"OVERLAY");border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder");border:SetSize(53,53);border:SetPoint("TOPLEFT")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight","ADD")
    local function Place()
        local angle=math.rad(config.angle);b:ClearAllPoints();b:SetPoint("CENTER",Minimap,"CENTER",math.cos(angle)*(Minimap:GetWidth()/2+8),math.sin(angle)*(Minimap:GetHeight()/2+8))
    end
    local dragging,suppress
    local function Drag()
        local x,y=GetCursorPosition();local mx,my=Minimap:GetCenter();local scale=Minimap:GetEffectiveScale()
        if not mx or not my or not scale or scale<=0 then return end
        local dx,dy=x/scale-mx,y/scale-my
        local a
        if math.atan2 then a=math.atan2(dy,dx) elseif dx~=0 then a=math.atan(dy/dx)+(dx<0 and math.pi or 0) else a=dy>=0 and math.pi/2 or -math.pi/2 end
        config.angle=math.deg(a)%360;Place()
    end
    b:SetScript("OnDragStart",function() dragging=true;suppress=true;if preview then preview:Hide() end;GameTooltip:Hide();b:SetScript("OnUpdate",Drag) end)
    b:SetScript("OnDragStop",function() Drag();dragging=false;b:SetScript("OnUpdate",nil);C_Timer.After(0,function() suppress=false end) end)
    b:SetScript("OnClick",function() if not dragging and not suppress then if hub and hub:IsShown() then hub:Hide() else NS.Open() end end end)
    b:SetScript("OnEnter",function()
        if dragging then return end
        if not preview then
            preview=CreateFrame("Frame",nil,b,"BackdropTemplate");preview:SetSize(112,112);preview:SetFrameStrata("TOOLTIP");preview:SetClampedToScreen(true)
            preview:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12});preview:SetBackdropColor(.03,.03,.03,.98)
            local photo=preview:CreateTexture(nil,"ARTWORK");photo:SetPoint("TOP",0,-8);photo:SetSize(45,45);photo:SetTexture(texture)
            local label=preview:CreateFontString(nil,"OVERLAY","GameFontNormal");label:SetPoint("TOPLEFT",10,-60);label:SetText("Smyrna Lightweight Addon Suite")
            local hint=preview:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");hint:SetPoint("TOPLEFT",10,-80);hint:SetText("Click to open\nDrag to move")
        end
        preview:ClearAllPoints();preview:SetPoint("TOPRIGHT",b,"BOTTOMLEFT",0,-3);preview:Show()
    end)
    b:SetScript("OnLeave",function() if preview then preview:Hide() end end)
    Minimap:HookScript("OnSizeChanged",Place);Place()
end
local driver=CreateFrame("Frame");driver:RegisterEvent("PLAYER_LOGIN");driver:SetScript("OnEvent",function(self) self:UnregisterEvent("PLAYER_LOGIN");Launcher() end)

