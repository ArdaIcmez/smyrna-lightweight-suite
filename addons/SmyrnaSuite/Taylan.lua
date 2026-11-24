local _,Suite=...
local T={}; Suite.Taylan=T
local TEX="Interface\\AddOns\\SmyrnaSuite\\Media\\Taylan"
local TEX_FROWN="Interface\\AddOns\\SmyrnaSuite\\Media\\TaylanFrown"
local TEX_SMILE="Interface\\AddOns\\SmyrnaSuite\\Media\\TaylanSmile"
local SOUND_SCREAM="Interface\\AddOns\\SmyrnaSuite\\Media\\TaylanScream.mp3"
local SOUND_HORROR="Interface\\AddOns\\SmyrnaSuite\\Media\\TaylanHorror.mp3"
local WHITE="Interface\\Buttons\\WHITE8X8"
local BASE_DEG=10 -- Taylan's foreground hand naturally points ~10 deg up-right

local frame,menu,threatFrame,angleSlider,angleValText,soundBtn,syncing
local threatGen,lastThreatAt,activeSoundHandle=0,0,nil
local VALID_POINTS={TOPLEFT=true,TOP=true,TOPRIGHT=true,LEFT=true,CENTER=true,RIGHT=true,BOTTOMLEFT=true,BOTTOM=true,BOTTOMRIGHT=true}

local Public=Suite.Public or function(v) return not (issecretvalue and issecretvalue(v)) end

local function Cfg()
    local c=Suite.Config.taylan
    if type(c)~="table" then c={}; Suite.Config.taylan=c end
    if c.shown==nil then c.shown=false end
    if c.size==nil then
        c.size=112
    elseif not c.compactSizeV1 then
        local size=tonumber(c.size)
        if not size or size~=size or size==math.huge or size==-math.huge then size=160 end
        c.size=math.max(56,math.min(420,math.floor(size*.70+.5)))
    end
    c.compactSizeV1=true -- scale saved sizes only once, never on every alert
    if c.angle==nil then c.angle=0 end
    if c.flip==nil then c.flip=false end
    if c.threatAlert==nil then c.threatAlert=true end
    if c.soundMode==nil then c.soundMode="both" end -- "scream" | "horror" | "both" | "off"
    return c
end
T.Config=Cfg

local function StopAlertSound()
    if activeSoundHandle and StopSound then
        pcall(StopSound,activeSoundHandle)
    end
    activeSoundHandle=nil
end

local function PlayAlertSound()
    StopAlertSound()
    local mode=Cfg().soundMode or "both"
    if mode=="off" or not PlaySoundFile then return end
    local path
    if mode=="scream" then path=SOUND_SCREAM
    elseif mode=="horror" then path=SOUND_HORROR
    else path=(math.random(1,2)==1) and SOUND_SCREAM or SOUND_HORROR end
    local ok,_,handle=pcall(PlaySoundFile,path,"SFX")
    if ok and handle then activeSoundHandle=handle end
end

local soundLabels={scream="Sound: Scream",horror="Sound: Horror",both="Sound: Both",off="Sound: Off"}
function T.CycleSound()
    local c=Cfg()
    c.soundMode=(c.soundMode=="both" and "scream") or (c.soundMode=="scream" and "horror") or (c.soundMode=="horror" and "off") or "both"
    if soundBtn then soundBtn:SetText(soundLabels[c.soundMode] or "Sound: Both") end
    return soundLabels[c.soundMode]
end
T.SoundLabel=function() return soundLabels[Cfg().soundMode or "both"] or "Sound: Both" end

local function ApplyVisual()
    if not frame then return end
    local c=Cfg()
    local sz=math.max(56,math.min(420,tonumber(c.size) or 112))
    frame:SetSize(sz,sz)
    if c.flip then frame.tex:SetTexCoord(1,0,0,1) else frame.tex:SetTexCoord(0,1,0,1) end
    frame.tex:SetRotation(math.rad(c.angle or 0))
    if angleSlider and angleValText and menu and menu:IsShown() then
        local deg=math.floor(((c.angle or 0)%360)+.5)
        if angleSlider:GetValue()~=deg then
            syncing=true
            angleSlider:SetValue(deg)
            syncing=false
        end
        angleValText:SetText(deg.." deg"..(c.flip and " (flipped)" or ""))
    end
end

local function TargetCenter(targetKey)
    local target
    if targetKey=="health" then
        target=PlayerFrameHealthBar or PlayerFrame
    elseif targetKey=="exp" then
        target=(MainMenuExpBar and not (MainMenuExpBar.IsForbidden and MainMenuExpBar:IsForbidden()) and MainMenuExpBar:IsShown() and MainMenuExpBar)
            or (StatusTrackingBarManager and not (StatusTrackingBarManager.IsForbidden and StatusTrackingBarManager:IsForbidden()) and StatusTrackingBarManager:IsShown() and StatusTrackingBarManager)
            or MainMenuBar
    elseif targetKey=="minimap" then
        target=Minimap
    elseif targetKey=="chat" then
        target=DEFAULT_CHAT_FRAME or ChatFrame1
    end
    if target and not (target.IsForbidden and target:IsForbidden()) and target.GetCenter then
        local tx,ty=target:GetCenter()
        local ts=target.GetEffectiveScale and target:GetEffectiveScale() or 1
        if Public(tx) and Public(ty) and Public(ts) and type(tx)=="number" and type(ty)=="number" and type(ts)=="number" and ts>0 then return tx*ts,ty*ts end
    end
    local uw,uh=UIParent:GetWidth() or 1920,UIParent:GetHeight() or 1080
    local us=UIParent:GetEffectiveScale() or 1
    if not Public(uw) or type(uw)~="number" then uw=1920 end
    if not Public(uh) or type(uh)~="number" then uh=1080 end
    if not Public(us) or type(us)~="number" or us<=0 then us=1 end
    if targetKey=="health" then return uw*.12*us,uh*.88*us end
    if targetKey=="exp" then return uw*.50*us,uh*.04*us end
    if targetKey=="minimap" then return uw*.92*us,uh*.88*us end
    return uw*.15*us,uh*.18*us
end

function T.PointTo(targetKey)
    if not frame then T.Show() end
    local fx,fy=frame:GetCenter()
    local fs=frame:GetEffectiveScale() or 1
    if not fx or not fy then return end
    local gx,gy=TargetCenter(targetKey)
    local dx,dy=gx-(fx*fs),gy-(fy*fs)
    local c=Cfg()
    c.pointTarget=targetKey
    -- Flip horizontally when pointing left so Taylan stays upright while aiming right at the target!
    if dx<0 then
        c.flip=true
        local ang=math.deg(math.atan2 and math.atan2(dy,-dx) or math.atan(dy/(-dx)))
        -- Mirrored texture reverses rotation sign, so negate to point along (dx, dy)
        c.angle=math.floor((-(ang-BASE_DEG))%360+.5)
    else
        c.flip=false
        local ang=math.deg(math.atan2 and math.atan2(dy,dx) or (dx~=0 and math.atan(dy/dx) or (dy>=0 and math.pi/2 or -math.pi/2)))
        c.angle=math.floor((ang-BASE_DEG)%360+.5)
    end
    ApplyVisual()
end

local function SavePosition()
    if not frame then return end
    local p,_,rp,x,y=frame:GetPoint(1)
    if p and x and y then
        local c=Cfg()
        c.point=p; c.relPoint=rp or p; c.x=math.floor(x+.5); c.y=math.floor(y+.5)
    end
end

local function OpenContextMenu()
    if not menu then
        menu=CreateFrame("Frame","SmyrnaTaylanMenu",UIParent,"BackdropTemplate")
        menu:SetSize(218,296); menu:SetFrameStrata("FULLSCREEN_DIALOG"); menu:SetFrameLevel(260); menu:SetClampedToScreen(true)
        Suite.StylePanel(menu,true); Suite.HeaderStrip(menu,28); Suite.CloseButton(menu)
        local title=menu:CreateFontString(nil,"OVERLAY","GameFontNormal"); title:SetPoint("TOPLEFT",10,-7); title:SetText("Point it to:"); title:SetTextColor(1,.86,.48)

        local function AddBtn(label,y,fn)
            local b=CreateFrame("Button",nil,menu,"UIPanelButtonTemplate")
            b:SetSize(194,22); b:SetPoint("TOPLEFT",12,y); b:SetText(label); Suite.StyleButton(b)
            b:SetScript("OnClick",fn); return b
        end
        AddBtn("Health bar",-34,function() T.PointTo("health"); menu:Hide() end)
        AddBtn("Exp bar",-60,function() T.PointTo("exp"); menu:Hide() end)
        AddBtn("Minimap",-86,function() T.PointTo("minimap"); menu:Hide() end)
        AddBtn("Chat",-112,function() T.PointTo("chat"); menu:Hide() end)

        Suite.OptionSection(menu,"Angle",12,-142,194)
        angleValText=menu:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        angleValText:SetPoint("TOPRIGHT",-14,-142); angleValText:SetTextColor(.78,.84,.92)

        angleSlider=Suite.CreateSlider(menu,192,0,359)
        angleSlider:SetPoint("TOPLEFT",13,-164)
        angleSlider:SetScript("OnValueChanged",function(_,val)
            if syncing then return end
            local deg=math.floor((val or 0)+.5)%360
            local c=Cfg(); c.pointTarget=nil; c.angle=deg
            ApplyVisual()
        end)

        local bFlip=CreateFrame("Button",nil,menu,"UIPanelButtonTemplate"); bFlip:SetSize(60,22); bFlip:SetPoint("TOPLEFT",12,-196); bFlip:SetText("Flip"); Suite.StyleButton(bFlip)
        bFlip:SetScript("OnClick",function() local c=Cfg(); c.pointTarget=nil; c.flip=not c.flip; ApplyVisual() end)
        local bReset=CreateFrame("Button",nil,menu,"UIPanelButtonTemplate"); bReset:SetSize(62,22); bReset:SetPoint("LEFT",bFlip,"RIGHT",5,0); bReset:SetText("Reset"); Suite.StyleButton(bReset)
        bReset:SetScript("OnClick",function() local c=Cfg(); c.pointTarget=nil; c.angle=0; c.flip=false; c.size=112; ApplyVisual() end)
        local bHide=CreateFrame("Button",nil,menu,"UIPanelButtonTemplate"); bHide:SetSize(62,22); bHide:SetPoint("LEFT",bReset,"RIGHT",5,0); bHide:SetText("Hide"); Suite.StyleButton(bHide)
        bHide:SetScript("OnClick",function() menu:Hide(); T.Hide() end)

        soundBtn=CreateFrame("Button",nil,menu,"UIPanelButtonTemplate"); soundBtn:SetSize(112,22); soundBtn:SetPoint("TOPLEFT",12,-224); soundBtn:SetText(T.SoundLabel()); Suite.StyleButton(soundBtn)
        soundBtn:SetScript("OnClick",function() T.CycleSound() end)
        local bTest=CreateFrame("Button",nil,menu,"UIPanelButtonTemplate"); bTest:SetSize(76,22); bTest:SetPoint("LEFT",soundBtn,"RIGHT",6,0); bTest:SetText("Test Alert"); Suite.StyleButton(bTest)
        bTest:SetScript("OnClick",function() lastThreatAt=0; T.FlashThreat(true) end)

        local hint=menu:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        hint:SetPoint("TOPLEFT",12,-254); hint:SetWidth(194); hint:SetJustifyH("LEFT"); hint:SetTextColor(.65,.70,.78)
        hint:SetText("Left-drag to move. Lower-right handle resizes.")
        UISpecialFrames[#UISpecialFrames+1]="SmyrnaTaylanMenu"
    end
    if soundBtn then soundBtn:SetText(T.SoundLabel()) end
    local cx,cy=GetCursorPosition()
    local sc=UIParent:GetEffectiveScale()
    if not Public(sc) or type(sc)~="number" or sc<=0 then sc=1 end
    menu:ClearAllPoints()
    if Public(cx) and Public(cy) and type(cx)=="number" and type(cy)=="number" then
        menu:SetPoint("TOPLEFT",UIParent,"BOTTOMLEFT",cx/sc+6,cy/sc-6)
    else
        menu:SetPoint("CENTER",UIParent,"CENTER",0,0)
    end
    menu:Show()
    ApplyVisual()
end

local function EnsureFrame()
    if frame then return frame end
    local c=Cfg()
    frame=CreateFrame("Frame","SmyrnaTaylanFrame",UIParent,"BackdropTemplate")
    frame:SetSize(c.size or 112,c.size or 112)
    frame:SetFrameStrata("MEDIUM"); frame:SetFrameLevel(40); frame:SetClampedToScreen(true)
    local px,py=Suite.Num(c.x,-4000,4000),Suite.Num(c.y,-4000,4000)
    local pt=VALID_POINTS[c.point] and c.point or nil
    local rpt=VALID_POINTS[c.relPoint] and c.relPoint or pt
    if pt and px and py then
        frame:SetPoint(pt,UIParent,rpt,px,py)
    else
        frame:SetPoint("CENTER",UIParent,"CENTER",180,60)
    end
    frame:SetMovable(true); frame:SetResizable(true); frame:EnableMouse(true)
    if frame.SetResizeBounds then frame:SetResizeBounds(56,56,420,420) end
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart",function(self)
        if not (InCombatLockdown and InCombatLockdown()) then self:StartMoving() end
    end)
    frame:SetScript("OnDragStop",function(self)
        self:StopMovingOrSizing(); SavePosition()
        if Cfg().pointTarget then T.PointTo(Cfg().pointTarget) end
    end)
    frame:SetScript("OnMouseUp",function(_,btn)
        if btn=="RightButton" then OpenContextMenu() end
    end)

    -- Thin red threat border (hidden unless flashing threat)
    frame:SetBackdrop({edgeFile=WHITE,edgeSize=2})
    frame:SetBackdropBorderColor(1,.18,.18,0)

    local tex=frame:CreateTexture(nil,"ARTWORK")
    tex:SetAllPoints(); tex:SetTexture(TEX)
    frame.tex=tex

    -- Lower-right resize handle
    local resize=CreateFrame("Button",nil,frame)
    resize:SetSize(18,18); resize:SetPoint("BOTTOMRIGHT",0,0); resize:SetAlpha(.45)
    resize:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resize:RegisterForDrag("LeftButton")
    resize:SetScript("OnEnter",function(self) self:SetAlpha(1) end)
    resize:SetScript("OnLeave",function(self) self:SetAlpha(.45) end)
    resize:SetScript("OnDragStart",function()
        if not (InCombatLockdown and InCombatLockdown()) then frame:StartSizing("BOTTOMRIGHT") end
    end)
    resize:SetScript("OnDragStop",function()
        frame:StopMovingOrSizing()
        local side=math.max(56,math.min(420,math.floor((frame:GetWidth()+frame:GetHeight())/2+.5)))
        Cfg().size=side
        ApplyVisual(); SavePosition()
        if Cfg().pointTarget then T.PointTo(Cfg().pointTarget) end
    end)
    frame:SetScript("OnSizeChanged",function(self,w,h)
        local side=math.max(56,math.min(420,math.floor((w+h)/2+.5)))
        if math.abs(w-side)>1 or math.abs(h-side)>1 then self:SetSize(side,side) end
    end)
    frame.resize=resize

    ApplyVisual()
    return frame
end

function T.Show()
    EnsureFrame()
    Cfg().shown=true
    frame:Show()
    ApplyVisual()
end

function T.Hide()
    Cfg().shown=false
    threatGen=threatGen+1
    StopAlertSound()
    if threatFrame then
        if threatFrame.anim then threatFrame.anim:Stop() end
        threatFrame:Hide()
    end
    if frame then
        frame.tex:SetTexture(TEX)
        frame:SetBackdropBorderColor(1,.18,.18,0)
        frame:Hide()
    end
    if menu then menu:Hide() end
end

function T.Toggle()
    if frame and frame:IsShown() then T.Hide() else T.Show() end
end

-- Alert Flash:
--   kind="aggro" -> Frowny meme face in thin red frame + alert sound (~1s, cuts audio on hide)
--   kind="safe"  -> Smiley meme face in thin green frame (~1s, silent)
local function ShowFlash(kind,force)
    if not force and not Cfg().threatAlert then return end
    local isAggro=(kind~="safe")
    local now=GetTime()
    if isAggro and not force and now-lastThreatAt<1.5 then return end
    if isAggro then lastThreatAt=now end
    threatGen=threatGen+1
    local token=threatGen

    if isAggro then PlayAlertSound() else StopAlertSound() end

    local texPath=isAggro and TEX_FROWN or TEX_SMILE
    local br,bg,bb=isAggro and 1 or .20,isAggro and .16 or .92,isAggro and .16 or .42
    local bgR,bgG,bgB=isAggro and .10 or .02,isAggro and .02 or .10,isAggro and .02 or .04

    if frame and frame:IsShown() then
        frame.tex:SetTexture(texPath)
        frame:SetBackdropBorderColor(br,bg,bb,.95)
        C_Timer.After(1.0,function()
            if threatGen==token then
                if frame then
                    frame.tex:SetTexture(TEX)
                    frame:SetBackdropBorderColor(1,.18,.18,0)
                end
                StopAlertSound()
            end
        end)
        return
    end

    if not threatFrame then
        threatFrame=CreateFrame("Frame","SmyrnaTaylanThreatAlert",UIParent,"BackdropTemplate")
        threatFrame:SetSize(132,132); threatFrame:SetPoint("CENTER",UIParent,"CENTER",0,0)
        threatFrame:SetFrameStrata("HIGH"); threatFrame:SetFrameLevel(120)
        threatFrame:SetClampedToScreen(true)
        threatFrame:SetBackdrop({bgFile=WHITE,edgeFile=WHITE,edgeSize=2,insets={left=2,right=2,top=2,bottom=2}})
        local t=threatFrame:CreateTexture(nil,"ARTWORK")
        t:SetSize(109,109); t:SetPoint("CENTER",0,0)
        threatFrame.tex=t
        local ag=threatFrame:CreateAnimationGroup()
        local hold=ag:CreateAnimation("Alpha"); hold:SetFromAlpha(1); hold:SetToAlpha(1); hold:SetDuration(.85); hold:SetOrder(1)
        local fade=ag:CreateAnimation("Alpha"); fade:SetFromAlpha(1); fade:SetToAlpha(0); fade:SetDuration(.20); fade:SetOrder(2)
        ag:SetScript("OnFinished",function() threatFrame:Hide(); StopAlertSound() end)
        threatFrame.anim=ag
    end
    -- Random position within +/-34% of screen, strictly excluding the center 15% around the character.
    local sw=(UIParent and UIParent.GetWidth and UIParent:GetWidth()) or 1920
    local sh=(UIParent and UIParent.GetHeight and UIParent:GetHeight()) or 1080
    if not Public(sw) or type(sw)~="number" or sw<=0 then sw=1920 end
    if not Public(sh) or type(sh)~="number" or sh<=0 then sh=1080 end
    local maxX,maxY=math.floor(sw*.34),math.floor(sh*.34)
    local deadX,deadY=math.floor(sw*.075),math.floor(sh*.075)
    local ox,oy=0,0
    for _=1,12 do
        ox=math.random(-maxX,maxX)
        oy=math.random(-maxY,maxY)
        if math.abs(ox)>=deadX or math.abs(oy)>=deadY then break end
    end
    if math.abs(ox)<deadX and math.abs(oy)<deadY then
        ox=(math.random(0,1)==0 and -1 or 1)*math.random(deadX,maxX)
    end
    -- Random 15-30 deg tilt left or right + random horizontal mirror
    local tiltDeg=math.random(15,30)*(math.random(0,1)==0 and 1 or -1)
    local flipX=(math.random(0,1)==1)
    threatFrame:ClearAllPoints()
    threatFrame:SetPoint("CENTER",UIParent,"CENTER",ox,oy)
    threatFrame.tex:SetTexture(texPath)
    if flipX then threatFrame.tex:SetTexCoord(1,0,0,1) else threatFrame.tex:SetTexCoord(0,1,0,1) end
    if threatFrame.tex.SetRotation then threatFrame.tex:SetRotation(math.rad(tiltDeg)) end
    threatFrame:SetBackdropColor(bgR,bgG,bgB,.35)
    threatFrame:SetBackdropBorderColor(br,bg,bb,.95)
    threatFrame.anim:Stop()
    threatFrame:SetAlpha(1)
    threatFrame:Show()
    threatFrame.anim:Play()
end

function T.FlashThreat(force)
    ShowFlash("aggro",force)
    if force and C_Timer and C_Timer.After then
        local token=threatGen
        -- When clicking Test, preview the Lose-Aggro green smiley right after the red frown!
        C_Timer.After(1.25,function()
            if threatGen==token then ShowFlash("safe",true) end
        end)
    end
end

function T.FlashSafe(force)
    ShowFlash("safe",force)
end

local driver=CreateFrame("Frame")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("PLAYER_REGEN_DISABLED")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")
driver:SetScript("OnEvent",function(self,event)
    if event=="PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        if Cfg().shown then T.Show() end
    elseif event=="PLAYER_REGEN_DISABLED" then
        ShowFlash("aggro",false)
    elseif event=="PLAYER_REGEN_ENABLED" then
        ShowFlash("safe",false)
    end
end)

SLASH_SMYRNATAYLAN1="/taylan"
SlashCmdList.SMYRNATAYLAN=function() T.Toggle() end
