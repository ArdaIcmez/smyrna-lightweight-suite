local _,NS=...
local hub,content,active,opening,preview,tabWidths,tabTotal
local pages={}
local texture="Interface\\AddOns\\SmyrnaSuite\\Media\\Smyrna35"
local openers={"OpenSettings","OpenOptions","OpenOptions","Open","Open","Open","Open","Open","Open","Open","Open"}
local original={}
-- Keep stable feature IDs for existing module callers; sort only navigation.
local tabOrder={}
for i in ipairs(NS.Features) do tabOrder[#tabOrder+1]=i end
table.sort(tabOrder,function(a,b) return NS.Features[a][2]<NS.Features[b][2] end)
tabOrder[#tabOrder+1]=-2 -- Dedicated Guild sharing & live map tab
NS.TabOrder=tabOrder
local function TabLabel(tabIndex)
    return tabIndex==-2 and "Guild" or NS.Features[tabIndex][2]
end
local function RemoveSpecialFrame(frameName)
    if type(frameName)~="string" or type(UISpecialFrames)~="table" then return end
    for i=#UISpecialFrames,1,-1 do
        if UISpecialFrames[i]==frameName then table.remove(UISpecialFrames,i) end
    end
end
local function HideEmbeddedChrome(page)
    if page.SetBackdrop then page:SetBackdrop(nil) end
    if page.smyrnaInnerLine then page.smyrnaInnerLine:Hide() end
    local gf=page.smyrnaGildedFrame
    if type(gf)=="table" then
        if type(gf.silver)=="table" then
            for i=1,#gf.silver do if gf.silver[i] and gf.silver[i].Hide then gf.silver[i]:Hide() end end
        end
        if type(gf.corners)=="table" then
            for i=1,#gf.corners do if gf.corners[i] and gf.corners[i].Hide then gf.corners[i]:Hide() end end
        end
    end
    local close=page.SuiteCloseButton
    if type(close)=="table" or type(close)=="userdata" then close:Hide() end
end
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
        hub:SetMovable(true);hub:EnableMouse(true);hub:RegisterForDrag("LeftButton")
        hub:SetScript("OnDragStart",function(self) if not (InCombatLockdown and InCombatLockdown()) then self:StartMoving() end end)
        hub:SetScript("OnDragStop",function(self) self:StopMovingOrSizing() end)
        NS.StylePanel(hub,true)
        NS.HeaderStrip(hub,44)
        local emblem=NS.CreateIconTile(hub,26);emblem:SetPoint("TOPLEFT",14,-10);emblem.icon:SetTexture(texture);emblem:SetBackdropBorderColor(.78,.63,.32,.95)
        local title=hub:CreateFontString(nil,"OVERLAY","GameFontNormalLarge");title:SetPoint("LEFT",emblem,"RIGHT",10,1);title:SetText("Smyrna Suite");title:SetTextColor(1,.86,.48)
        local ver=hub:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");ver:SetPoint("LEFT",title,"RIGHT",8,-1);ver:SetText("Lightweight Addon Suite");ver:SetTextColor(.58,.62,.70)
        local close=NS.CloseButton(hub);close:ClearAllPoints();close:SetPoint("TOPRIGHT",-10,-10)
        local navStrip=hub:CreateTexture(nil,"BACKGROUND",nil,1)
        navStrip:SetPoint("TOPLEFT",2,-46);navStrip:SetPoint("TOPRIGHT",-2,-46);navStrip:SetHeight(38);navStrip:SetColorTexture(.042,.048,.065,1)
        local navRule=hub:CreateTexture(nil,"BORDER",nil,2)
        navRule:SetPoint("TOPLEFT",navStrip,"BOTTOMLEFT",0,0);navRule:SetPoint("TOPRIGHT",navStrip,"BOTTOMRIGHT",0,0);navRule:SetHeight(1);navRule:SetColorTexture(.25,.28,.36,.75)
        content=CreateFrame("Frame",nil,hub);content:SetPoint("TOPLEFT",10,-90);content:SetSize(940,740)
        if content.SetClipsChildren then content:SetClipsChildren(true) end
        NS.HubFrame=hub
        hub.tabs={}
        local tutorial=CreateFrame("Button",nil,hub,"UIPanelButtonTemplate");tutorial:SetSize(88,24);tutorial:SetPoint("RIGHT",close,"LEFT",-8,0);tutorial:SetText("|TInterface\\GossipFrame\\AvailableQuestIcon:14:14|t Guide");NS.StyleButton(tutorial)
        tutorial:SetScript("OnClick",function() NS.OpenTab(-1) end);hub.tabs[-1]=tutorial;hub.tutorialButton=tutorial
        local settings=CreateFrame("Button",nil,hub);settings:SetSize(92,24);settings:SetPoint("RIGHT",tutorial,"LEFT",-6,0)
        local gear=settings:CreateTexture(nil,"OVERLAY",nil,2);gear:SetSize(15,15);gear:SetTexture("Interface\\Icons\\INV_Misc_Gear_01");gear:SetTexCoord(.08,.92,.08,.92)
        local caption=settings:CreateFontString(nil,"OVERLAY","GameFontNormal");caption:SetText("Settings")
        if settings.SetFontString then settings:SetFontString(caption) end
        local captionWidth=caption:GetStringWidth();if type(captionWidth)~="number" then captionWidth=49 end
        local groupWidth=15+6+captionWidth
        gear:SetPoint("LEFT",settings,"CENTER",-groupWidth/2,0)
        caption:ClearAllPoints();caption:SetPoint("LEFT",gear,"RIGHT",6,0)
        NS.StyleButton(settings);settings:SetScript("OnClick",function() NS.OpenTab(0) end);hub.tabs[0]=settings;hub.settingsButton=settings
        for position,tabIndex in ipairs(tabOrder) do
            local b=CreateFrame("Button",nil,hub,"UIPanelButtonTemplate");b:SetSize(96,26);b:SetPoint("TOPLEFT",16+(position-1)*104,-52)
            NS.StyleButton(b);b:SetText(TabLabel(tabIndex));b:SetScript("OnClick",function() NS.OpenTab(tabIndex) end)
            local indicator=b:CreateTexture(nil,"OVERLAY",nil,2);indicator:SetPoint("BOTTOMLEFT",2,0);indicator:SetPoint("BOTTOMRIGHT",-2,0);indicator:SetHeight(2);indicator:SetColorTexture(.96,.80,.38,1);indicator:Hide()
            b.smyrnaTabIndicator=indicator
            hub.tabs[tabIndex]=b
        end
        UISpecialFrames[#UISpecialFrames+1]="SmyrnaSuiteHub"
    end
    if active then active:Hide() end
    opening=true
    local ok,page
    if index==-2 then ok,page=pcall(NS.OpenGuildTab)
    elseif index==-1 then ok,page=pcall(NS.OpenTutorial)
    elseif index==0 then ok,page=pcall(NS.OpenOverview)
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
        if not tabWidths then
            tabWidths={};tabTotal=0
            for position,tabIndex in ipairs(tabOrder) do
                local label=hub.tabs[tabIndex]:GetFontString()
                local measured=label and label:GetStringWidth()
                if type(measured)~="number" then measured=#TabLabel(tabIndex)*7 end
                local w=math.max(58,math.min(104,measured+16));tabWidths[position]=w;tabTotal=tabTotal+w
            end
            tabTotal=tabTotal+(#tabOrder-1)*4
        end
        local pw,ph=page:GetWidth() or 920,page:GetHeight() or 600
        local width=math.max(940,tabTotal+24,pw+20)
        local height=ph+104
        hub:SetSize(width,height);content:SetSize(width-20,ph)
        local left=(width-tabTotal)/2
        for position,tabIndex in ipairs(tabOrder) do
            local b=hub.tabs[tabIndex];b:SetSize(tabWidths[position],26);b:ClearAllPoints();b:SetPoint("TOPLEFT",left,-52);left=left+tabWidths[position]+4
        end
        if UIParent and UIParent.GetHeight then
            local uw,uh=UIParent:GetWidth(),UIParent:GetHeight()
            if NS.Public(uw) and NS.Public(uh) and type(uw)=="number" and type(uh)=="number" and uw>60 and uh>60 then
                hub:SetScale(math.min(1,(uw-30)/width,(uh-30)/height))
            end
        end
        HideEmbeddedChrome(page)
        if page.GetName then RemoveSpecialFrame(page:GetName()) end
        if not page.smyrnaTreeStyled then NS.StyleTree(page);page.smyrnaTreeStyled=true end
        pages[index]=page;page:SetParent(content)
        if page.SetFrameStrata and content.GetFrameStrata then page:SetFrameStrata(content:GetFrameStrata()) end
        if page.SetFrameLevel and content.GetFrameLevel then page:SetFrameLevel((content:GetFrameLevel() or 1)+1) end
        page:SetScale(1);page:ClearAllPoints();page:SetPoint("TOP",content,"TOP",0,0)
        page:SetMovable(false);page:SetScript("OnDragStart",nil);page:SetScript("OnDragStop",nil);page:Show();active=page
    end
    for n,b in pairs(hub.tabs) do
        local isCurrent=(n==index)
        NS.SetButtonSelected(b,isCurrent);b:SetEnabled(not isCurrent)
        if b.smyrnaTabIndicator then b.smyrnaTabIndicator:SetShown(isCurrent) end
    end
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
    b:SetScript("OnDragStart",function()
        dragging=true;suppress=true;if preview then preview:Hide() end
        if GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then GameTooltip:Hide() end
        b:SetScript("OnUpdate",Drag)
    end)
    b:SetScript("OnDragStop",function() Drag();dragging=false;b:SetScript("OnUpdate",nil);C_Timer.After(0,function() suppress=false end) end)
    b:SetScript("OnHide",function() dragging=false;b:SetScript("OnUpdate",nil) end)
    b:SetScript("OnClick",function() if not dragging and not suppress then if hub and hub:IsShown() then hub:Hide() else NS.Open() end end end)
    b:SetScript("OnEnter",function()
        if dragging then return end
        if not preview then
            preview=CreateFrame("Frame",nil,b,"BackdropTemplate");preview:SetSize(166,104);preview:SetFrameStrata("TOOLTIP");preview:SetClampedToScreen(true)
            NS.StylePanel(preview,true)
            local tile=NS.CreateIconTile(preview,38);tile:SetPoint("TOP",0,-10);tile.icon:SetTexture(texture);tile:SetBackdropBorderColor(.78,.63,.32,.95)
            local label=preview:CreateFontString(nil,"OVERLAY","GameFontNormal");label:SetPoint("TOP",tile,"BOTTOM",0,-6);label:SetText("Smyrna Suite");label:SetTextColor(1,.86,.48)
            local hint=preview:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");hint:SetPoint("TOP",label,"BOTTOM",0,-4);hint:SetText("Click to open  -  Drag to move");hint:SetTextColor(.72,.76,.84)
        end
        preview:ClearAllPoints();preview:SetPoint("TOPRIGHT",b,"BOTTOMLEFT",0,-3);preview:Show()
    end)
    b:SetScript("OnLeave",function() if preview then preview:Hide() end end)
    Minimap:HookScript("OnSizeChanged",Place);Place()
end
local driver=CreateFrame("Frame");driver:RegisterEvent("PLAYER_LOGIN");driver:SetScript("OnEvent",function(self) self:UnregisterEvent("PLAYER_LOGIN");Launcher() end)
