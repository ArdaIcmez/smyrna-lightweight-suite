local _,Suite=...
local name="SmyrnaAggroMate"
Suite.Versions[name]="0.1.0"
if Suite.Config.features[name]==false then return end
local Module={}
Suite.Modules[name]=Module

local HALO_TEX="Interface\\AddOns\\SmyrnaSuite\\Media\\AggroHalo"
local HALO_MASK_TEX="Interface\\AddOns\\SmyrnaSuite\\Media\\AggroHaloMask"
local HALO_CREST_TEX="Interface\\AddOns\\SmyrnaSuite\\Media\\AggroArc"
local RAY_GRAD_TEX="Interface\\AddOns\\SmyrnaSuite\\Media\\AggroRayGrad"
local INDENT_MASK_TEX="Interface\\AddOns\\SmyrnaSuite\\Media\\AggroIndentMask"
local TARGET_ICON_TEX="Interface\\AddOns\\SmyrnaSuite\\Media\\AggroTarget"
local TARGET_ICON_FALLBACK="Interface\\Minimap\\Tracking\\Target"
local FALLBACK_TEX="Interface\\Minimap\\UI-Minimap-Ping"
local FACTION_TEX={
    Alliance="Interface\\TargetingFrame\\UI-PVP-Alliance",
    Horde="Interface\\TargetingFrame\\UI-PVP-Horde",
}
local FACTION_COLORS={
    Alliance={.22,.60,1.00}, -- vivid Alliance royal blue
    Horde={.96,.16,.24},     -- vivid Horde crimson
}

-- Forever 16001 calibrated hostile item range probes (+/-0.5 yd accuracy, combat-safe on hostile units)
local ITEM_PROBES={
    {8,8149},
    {13,17626},
    {23,17757},
    {28,13289},
    {33,17202},
    {38,18904},
    {48,221316},
}

local spellProbes={}
local activePlates={}  -- [unit] = isHostile (bool)
local plateCount,hostilePlateCount=0,0
local aggroMobs={}     -- [guid] = { guid, id, name, level, px, py, map, w, h, pullAt, lastHitAt, leashSec, leashYards }
local aggroCount=0
local lastMoveMode,lastMoveMap,lastMoveX,lastMoveY,lastMoveAt=nil,nil,nil,nil,0
local LEASH_MIN_YARDS=10
local LEASH_STILL_GRACE=0.6
local haloFrame,leashPanel,leashRows,ticker,window,checks=nil,nil,{},nil,nil,{}
local editOverlay,editModeActive,editFromMenu,sliderDragging,syncSlidersFn=nil,false,false,false,nil
local hubHooked=false

local function Public(v) return not (issecretvalue and issecretvalue(v)) end
local function Num(v,lo,hi) return Public(v) and type(v)=="number" and v==v and v>=lo and v<=hi end

local function Cfg()
    local c=Suite.Config.aggromate
    if type(c)~="table" then c={}; Suite.Config.aggromate=c end
    if c.enabled==nil then c.enabled=true end
    if c.showHalo==nil then c.showHalo=true end
    if c.showTargetBtn==nil then c.showTargetBtn=true end
    if c.showLeash==nil then c.showLeash=true end
    if c.tankMate==nil then c.tankMate=true end
    if c.dpsThreat==nil then c.dpsThreat=true end
    if not Num(c.haloSize,120,460) then c.haloSize=260 end
    if not Num(c.haloX,-400,400) then c.haloX=0 end
    if not Num(c.haloY,-300,300) then c.haloY=0 end
    if not c.v2NoIdleRing then c.v2NoIdleRing=true; c.haloAlpha=0 end
    if not Num(c.haloAlpha,0,0.6) then c.haloAlpha=0 end
    if type(c.haloColor)~="string" or not c.haloColor:match("^%x%x%x%x%x%x$") then c.haloColor="ffffff" end
    if not Num(c.warnMargin,6,25) then c.warnMargin=14 end -- start showing on halo when within aggro + 14 yd
    return c
end
Module.Config=Cfg

local haloHexCache,haloRCache,haloGCache,haloBCache=nil,1,1,1
local function HaloColor()
    local hex=Cfg().haloColor or "ffffff"
    if hex~=haloHexCache then
        haloHexCache=hex
        haloRCache=tonumber(hex:sub(1,2),16)/255
        haloGCache=tonumber(hex:sub(3,4),16)/255
        haloBCache=tonumber(hex:sub(5,6),16)/255
    end
    return haloRCache,haloGCache,haloBCache
end

-- Precomputed unit-target tokens to eliminate per-tick string concatenation in hot loop
local UNIT_TARGET={target="targettarget"}
for i=1,40 do UNIT_TARGET["nameplate"..i]="nameplate"..i.."target" end
local playerFaction=nil

-- Scan player's known harmful 0-minRange spells to use as combat-safe range proxies
local function IsHarmfulSpellID(spellID,spellName)
    if C_Spell and C_Spell.IsSpellHarmful then
        local ok,v=pcall(C_Spell.IsSpellHarmful,spellID)
        if ok and Public(v) and v~=nil then return v==true end
    end
    if IsHarmfulSpell then
        local ok,v=pcall(IsHarmfulSpell,spellName or spellID)
        if ok and Public(v) and v~=nil then return v==true or v==1 end
    end
    return false
end

local function BuildSpellProbes()
    wipe(spellProbes)
    local seen={}
    local function TryAdd(spellID)
        if not Num(spellID,1,2000000) then return end
        local info=C_Spell and C_Spell.GetSpellInfo and C_Spell.GetSpellInfo(spellID)
        local r=info and info.maxRange
        local minR=info and info.minRange or 0
        if Num(r,5,45) and (not Num(minR,1,100)) and not seen[r] then
            if IsHarmfulSpellID(spellID,info.name) then
                seen[r]=true
                spellProbes[#spellProbes+1]={r,spellID}
            end
        end
    end
    if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo and C_SpellBook.GetSpellBookItemInfo then
        local lines=C_SpellBook.GetNumSpellBookSkillLines()
        for l=1,math.min(lines or 0,12) do
            local line=C_SpellBook.GetSpellBookSkillLineInfo(l)
            if line and line.itemIndexOffset and line.numSpellBookItems then
                for i=line.itemIndexOffset+1,line.itemIndexOffset+line.numSpellBookItems do
                    local item=C_SpellBook.GetSpellBookItemInfo(i,Enum.SpellBookSpellBank.Player)
                    if item and item.spellID and item.itemType==Enum.SpellBookItemType.Spell then
                        TryAdd(item.spellID)
                    end
                end
            end
        end
    end
    table.sort(spellProbes,function(a,b) return a[1]<b[1] end)
end

-- Classic / Forever aggro radius formula based on mob vs player level (green/yellow/orange/red/gray)
function Module.AggroRadius(mobLevel,playerLevel)
    playerLevel=Num(playerLevel,1,200) and playerLevel or (UnitLevel("player") or 1)
    local diff
    if not Num(mobLevel,-1,200) or mobLevel==-1 then
        diff=12 -- skull / ?? boss
    else
        diff=mobLevel-playerLevel
    end
    local base=20+diff
    if IsStealthed and IsStealthed() then base=base-10 end
    return math.max(5,math.min(45,base))
end

-- Classic / Forever leash estimate (time + yards from pull if player stops attacking and runs)
function Module.LeashSpec(mobLevel,playerLevel)
    local ml=(Num(mobLevel,1,200) and mobLevel) or (playerLevel+10)
    local pl=Num(playerLevel,1,200) and playerLevel or 1
    local leashSec=math.max(10,math.min(20,10+math.floor(ml*.14)))
    local leashYards=math.max(40,math.min(65,44+math.floor((ml-pl)*1.0)))
    return leashYards,leashSec
end

local function ConColor(mobLevel,playerLevel)
    if not Num(mobLevel,-1,200) or mobLevel==-1 then return 1,.20,.20,"Skull","ff3333" end
    local d=mobLevel-playerLevel
    if d>=5 then return 1,.25,.25,"Red","ff4040" end
    if d>=3 then return 1,.55,.22,"Orange","ff8c38" end
    if d>=-2 then return 1,.88,.28,"Yellow","ffe047" end
    local grayDelta=(playerLevel<=5 and 5) or (playerLevel<=39 and (math.floor(playerLevel/10)+5)) or (math.floor(playerLevel/5)+1)
    if d<=-grayDelta then return .62,.65,.70,"Gray","9ea6b3" end
    return .30,.92,.45,"Green","4deb73"
end

-- Estimate distance bracket [minYd, maxYd] to a visible hostile unit using sanctioned APIs
function Module.EstimateRange(unit)
    local minYd,maxYd=0,60
    -- 1. Optional DBM.RangeCheck if installed
    local dbm=DBM and DBM.RangeCheck
    if dbm and dbm.GetUnitMinMaxRange then
        local ok,lo,hi=pcall(dbm.GetUnitMinMaxRange,dbm,unit)
        if ok and Num(lo,0,100) and Num(hi,1,100) and hi>=lo then
            local est=(lo==0 and hi>13) and (hi-3) or ((lo+hi)/2)
            return lo,hi,est
        end
    end
    -- 2. Spell proxies (work both out-of-combat and in-combat!)
    local isSpell=C_Spell and C_Spell.IsSpellInRange or IsSpellInRange
    if isSpell and #spellProbes>0 then
        for i=1,#spellProbes do
            local r,sid=spellProbes[i][1],spellProbes[i][2]
            local ok,res=pcall(isSpell,sid,unit)
            if ok and Public(res) then
                if res==true or res==1 then
                    if r<maxYd then maxYd=r end
                elseif res==false or res==0 then
                    if r>minYd then minYd=r end
                end
            end
        end
    end
    -- 3. Forever-calibrated hostile item range probes (never call on friendly units)
    local isItem=C_Item and C_Item.IsItemInRange or IsItemInRange
    if isItem and UnitExists and UnitExists(unit) and not (UnitIsFriend and UnitIsFriend("player",unit)) then
        for i=1,#ITEM_PROBES do
            local r,iid=ITEM_PROBES[i][1],ITEM_PROBES[i][2]
            local ok,res=pcall(isItem,iid,unit)
            if ok and Public(res) and res~=nil then
                if res==true or res==1 then
                    if r<maxYd then maxYd=r end
                elseif res==false or res==0 then
                    if r>minYd then minYd=r end
                end
            end
        end
    end
    if maxYd<minYd then minYd,maxYd=maxYd,minYd end
    if maxYd>=60 and minYd==0 then return nil,nil,nil end
    -- If closer probes returned nil (uncached), avoid dragging the estimate down to maxYd/2.
    local est=(minYd==0 and maxYd>13) and (maxYd-3) or ((minYd+maxYd)/2)
    return minYd,maxYd,est
end

local function DangerColor(margin)
    -- margin = estimated distance minus aggro radius (yards)
    if margin<=0 then return 1,.18,.18 end      -- Red: at / inside aggro edge
    if margin<=3 then return 1,.52,.16 end      -- Orange: razor thin (1-3 yd)
    if margin<=6 then return 1,.86,.24 end      -- Yellow: getting close (3-6 yd)
    return .26,.92,.46                          -- Green: safe squeeze space (6+ yd)
end

local function PlayerWorldPos()
    -- 1. Primary: UnitPosition("player") returns exact world yards directly (works reliably in combat on Forever 16001)
    if UnitPosition then
        local ok,py,px,_,inst=pcall(UnitPosition,"player")
        if ok and Num(px,-1000000,1000000) and Num(py,-1000000,1000000) then
            return "world",(Num(inst,0,1000000) and inst or 0),px,py,1,1
        end
    end
    if not C_Map or not C_Map.GetBestMapForUnit then return nil end
    local m=C_Map.GetBestMapForUnit("player")
    if not Num(m,1,1000000) then return nil end
    local pos=C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(m,"player")
    if not pos or not pos.GetXY then return nil end
    -- 2. Fallback: C_Map.GetWorldPosFromMapPos returns exact world yards
    if C_Map.GetWorldPosFromMapPos then
        local ok,cont,wpos=pcall(C_Map.GetWorldPosFromMapPos,m,pos)
        if ok and wpos and Num(wpos.x,-1000000,1000000) and Num(wpos.y,-1000000,1000000) then
            return "world",(Num(cont,0,1000000) and cont or m),wpos.x,wpos.y,1,1
        end
    end
    -- 3. Fallback: normalized map coords * map world size
    local x,y=pos:GetXY()
    local w,h=C_Map.GetMapWorldSize and C_Map.GetMapWorldSize(m)
    if not Num(x,0,1) or not Num(y,0,1) or not Num(w,1,200000) or not Num(h,1,200000) then return nil end
    return "map",m,x,y,w,h
end

local function IsUnitThreatening(unit)
    if not unit or not UnitExists or not UnitExists(unit) then return false end
    local ca=UnitCanAttack and UnitCanAttack("player",unit)
    if Public(ca) and ca then return true end
    local isPl=UnitIsPlayer and UnitIsPlayer(unit)
    if Public(isPl) and isPl and UnitFactionGroup then
        if not playerFaction then
            local mf=UnitFactionGroup("player")
            if Public(mf) and (mf=="Alliance" or mf=="Horde") then playerFaction=mf end
        end
        local tf=UnitFactionGroup(unit)
        if playerFaction and Public(tf) and (tf=="Alliance" or tf=="Horde") and tf~=playerFaction then return true end
    end
    return false
end

local function UnitTargetsPlayer(unit)
    if not unit or not UnitExists or not UnitExists(unit) then return false end
    local utok=UNIT_TARGET[unit] or (unit.."target")
    local targeting=UnitIsUnit and UnitIsUnit(utok,"player")
    if Public(targeting) and targeting then return true end
    if UnitThreatSituation then
        local ok,sit=pcall(UnitThreatSituation,"player",unit)
        if ok and Public(sit) and type(sit)=="number" and sit>=2 then return true end
    end
    return false
end

local function RegisterAggroUnit(unit)
    if not unit or not UnitExists or not UnitExists(unit) then return end
    local dead=UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)
    if not Public(dead) or dead then return end
    local hostile=UnitCanAttack and UnitCanAttack("player",unit)
    if not Public(hostile) or not hostile then return end
    local guid=UnitGUID and UnitGUID(unit)
    if not Public(guid) or type(guid)~="string" then return end
    if aggroMobs[guid] then return end
    local npcID=tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
    if not npcID then return end
    local mobName=UnitName and UnitName(unit)
    mobName=(Public(mobName) and type(mobName)=="string") and mobName or ("NPC #"..npcID)
    local ml=UnitLevel and UnitLevel(unit)
    local pl=UnitLevel and UnitLevel("player") or 1
    local ly,ls=Module.LeashSpec(ml,pl)
    local mode,m,px,py,w,h=PlayerWorldPos()
    local now=GetTime()
    aggroMobs[guid]={
        guid=guid,id=npcID,name=mobName,level=Num(ml,-1,200) and ml or 0,
        posMode=mode,map=m,px=px,py=py,w=w,h=h,
        pullAt=now,lastHitAt=now,leashYards=ly,leashSec=ls,
    }
    aggroCount=aggroCount+1
end

local function PruneDeadAggro(unit)
    if aggroCount<=0 or not unit or not UnitExists or not UnitExists(unit) then return end
    local dead=UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)
    if not Public(dead) or not dead then return end
    local guid=UnitGUID and UnitGUID(unit)
    if Public(guid) and type(guid)=="string" and aggroMobs[guid] then
        aggroMobs[guid]=nil
        aggroCount=math.max(0,aggroCount-1)
    end
end

-- Pooled GPU-masked directional halo arcs:
-- Each arc is a fixed ring Texture on haloFrame masked by a radial bell-curve MaskTexture
-- anchored directly to the mob's NamePlate via SetPoint (same pattern EverAuras uses on 12.x;
-- zero CreateLine, zero restricted FrameMeasurement, smooth 0%->100%->0% FPS threat fade!).
local arcEntries={}
local arcMargin=math.huge

local function PositionLeash(size,x,y)
    if not leashPanel then return end
    leashPanel:ClearAllPoints()
    leashPanel:SetPoint("TOPLEFT",UIParent,"CENTER",x+math.floor(size*.50)+16,y-math.floor(size*.20))
end

local function EnsureHalo()
    if haloFrame then return haloFrame end
    local c=Cfg()
    local sz=c.haloSize or 260
    haloFrame=CreateFrame("Frame","SmyrnaAggroMateHalo",UIParent)
    haloFrame:SetSize(sz,sz)
    haloFrame:SetPoint("CENTER",UIParent,"CENTER",c.haloX or 0,c.haloY or 0)
    haloFrame:SetFrameStrata("LOW"); haloFrame:SetFrameLevel(10)
    haloFrame:EnableMouse(false) -- strictly click-through; move & resize only from /am menu!
    local base=haloFrame:CreateTexture(nil,"BACKGROUND")
    base:SetAllPoints()
    if base:SetTexture(HALO_MASK_TEX)==false then
        if base:SetTexture(HALO_TEX)==false then base:SetTexture(FALLBACK_TEX) end
    end
    local hr,hg,hb=HaloColor()
    base:SetVertexColor(hr,hg,hb,c.haloAlpha or 0)
    base:Hide() -- full circle is an editing guide, never a gameplay warning
    haloFrame.base=base

    -- Subtle, semi-transparent clickable enemy frame tucked below the player near their feet (toggleable in /am).
    -- Rests at 48% alpha so it never blocks gameplay; brightens to 96% on hover. Left-click targets via /targetexact.
    -- Anchored strictly to UIParent (NEVER haloFrame!) inside a SecureHandlerStateTemplate wrapper
    -- so combat lockdown NEVER triggers ADDON_ACTION_BLOCKED on haloFrame:Show()/Hide()!
    local statusWrap=CreateFrame("Frame","SmyrnaAggroMateStatusWrap",UIParent,"SecureHandlerStateTemplate")
    statusWrap:SetAllPoints(UIParent)
    statusWrap:SetFrameStrata("MEDIUM"); statusWrap:SetFrameLevel(25)
    if RegisterStateDriver then
        pcall(RegisterStateDriver,statusWrap,"visibility","[combat] hide; show")
    end
    local statusBg=CreateFrame("Button","SmyrnaAggroMateTargetBtn",statusWrap,"SecureActionButtonTemplate,BackdropTemplate")
    statusBg:SetSize(124,18)
    statusBg:SetPoint("CENTER",UIParent,"CENTER",c.haloX or 0,(c.haloY or 0)-math.floor(sz*.34))
    statusBg:SetFrameStrata("MEDIUM"); statusBg:SetFrameLevel(30)
    statusBg:EnableMouse(true)
    statusBg:RegisterForClicks("LeftButtonUp","LeftButtonDown")
    statusBg:SetAttribute("type","macro")
    statusBg:SetAttribute("type1","macro")
    statusBg:SetAttribute("macrotext","")
    statusBg:SetAttribute("macrotext1","")
    statusBg:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1,insets={left=1,right=1,top=1,bottom=1}})
    statusBg:SetBackdropColor(.05,.06,.09,.52)
    statusBg:SetBackdropBorderColor(.4,.45,.52,.70)
    statusBg:SetAlpha(.48)
    statusBg:SetScript("OnEnter",function(self)
        self:SetAlpha(.96)
        self:SetBackdropColor(.08,.10,.15,.88)
        if GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then
            GameTooltip:SetOwner(self,"ANCHOR_TOP")
            local fac=self.targetFaction
            local extra=(self.targetExtra and self.targetExtra>0) and (" (+"..self.targetExtra.." nearby)") or ""
            if fac=="Alliance" then
                GameTooltip:SetText((self.targetName or "Alliance")..extra,0.35,0.72,1.0)
                GameTooltip:AddLine((self.targetIsPlayer and "Alliance Player" or "Alliance Enemy").." - Left-click to target.",.75,.86,1)
            elseif fac=="Horde" then
                GameTooltip:SetText((self.targetName or "Horde")..extra,1.0,0.32,0.36)
                GameTooltip:AddLine((self.targetIsPlayer and "Horde Player" or "Horde Enemy").." - Left-click to target.",1,.78,.78)
            else
                GameTooltip:SetText((self.targetName or "Hostile Mob")..extra,1,.86,.48)
                GameTooltip:AddLine("Left-click to target closest threat.",.75,.84,.96)
            end
            GameTooltip:Show()
        end
    end)
    statusBg:SetScript("OnLeave",function(self)
        self:SetAlpha(.48)
        self:SetBackdropColor(self.bgR or .05,self.bgG or .06,self.bgB or .09,.62)
        if GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then GameTooltip:Hide() end
    end)
    local icon=statusBg:CreateTexture(nil,"OVERLAY")
    icon:SetSize(13,13); icon:SetPoint("LEFT",statusBg,"LEFT",4,0)
    if icon:SetTexture(TARGET_ICON_TEX)==false then icon:SetTexture(TARGET_ICON_FALLBACK) end
    local st=statusBg:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    st:SetPoint("LEFT",icon,"RIGHT",4,0)
    st:SetJustifyH("LEFT")
    st:SetShadowOffset(1,-1)
    statusBg:Hide()
    haloFrame.statusWrap=statusWrap
    haloFrame.statusBg=statusBg
    haloFrame.statusIcon=icon
    haloFrame.status=st

    -- Sleek, compact Obsidian & Gold Leash Tracker HUD card (auto-sized tightly to content)
    leashPanel=CreateFrame("Frame","SmyrnaAggroMateLeash",UIParent,"BackdropTemplate")
    leashPanel:SetSize(172,52)
    PositionLeash(sz,c.haloX or 0,c.haloY or 0)
    leashPanel:SetFrameStrata("LOW"); leashPanel:SetFrameLevel(14)
    leashPanel:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1,insets={left=1,right=1,top=1,bottom=1}})
    leashPanel:SetBackdropColor(.055,.065,.092,.88)
    leashPanel:SetBackdropBorderColor(.78,.64,.34,.62)
    local accent=leashPanel:CreateTexture(nil,"ARTWORK")
    accent:SetPoint("TOPLEFT",1,-1); accent:SetPoint("BOTTOMLEFT",1,1); accent:SetWidth(2)
    accent:SetColorTexture(.92,.68,.26,.95)
    leashPanel.accent=accent
    local lt=leashPanel:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    lt:SetPoint("TOPLEFT",9,-5); lt:SetText("LEASH"); lt:SetTextColor(.93,.77,.40)
    local lsub=leashPanel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    lsub:SetPoint("TOPRIGHT",-8,-5); lsub:SetTextColor(.62,.68,.78)
    leashPanel.sub=lsub
    local ldiv=leashPanel:CreateTexture(nil,"ARTWORK")
    ldiv:SetPoint("TOPLEFT",8,-19); ldiv:SetPoint("TOPRIGHT",-8,-19); ldiv:SetHeight(1)
    Suite.ApplyGradient(ldiv,"HORIZONTAL",.93,.77,.40,.45,.93,.77,.40,.05)
    leashPanel:Hide()
    return haloFrame
end

local function AcquireArc(idx)
    local e=arcEntries[idx]
    if e then return e end
    if not haloFrame or not haloFrame.CreateMaskTexture then return nil end
    -- Layer 1: focused ~55-70 deg colored rim arc
    local tex=haloFrame:CreateTexture(nil,"ARTWORK",nil,2)
    tex:SetAllPoints(haloFrame)
    if tex:SetTexture(HALO_MASK_TEX)==false then tex:SetTexture(HALO_TEX) end
    if tex.SetBlendMode then tex:SetBlendMode("BLEND") end
    if tex.SetTexelSnappingBias then tex:SetTexelSnappingBias(0) end
    if tex.SetSnapToPixelGrid then tex:SetSnapToPixelGrid(false) end
    local mask=haloFrame:CreateMaskTexture()
    mask:SetTexture(RAY_GRAD_TEX,"CLAMPTOBLACKADDITIVE","CLAMPTOBLACKADDITIVE")
    if mask.SetTexelSnappingBias then mask:SetTexelSnappingBias(0) end
    if mask.SetSnapToPixelGrid then mask:SetSnapToPixelGrid(false) end
    if tex.AddMaskTexture then tex:AddMaskTexture(mask) end
    tex:Hide()

    -- Layer 2: crisp inward directional indent right in the middle of the arc pointing toward the mob
    local crest=haloFrame:CreateTexture(nil,"ARTWORK",nil,3)
    crest:SetAllPoints(haloFrame)
    if crest:SetTexture(HALO_CREST_TEX)==false then crest:SetTexture(HALO_MASK_TEX) end
    if crest.SetBlendMode then crest:SetBlendMode("BLEND") end
    if crest.SetTexelSnappingBias then crest:SetTexelSnappingBias(0) end
    if crest.SetSnapToPixelGrid then crest:SetSnapToPixelGrid(false) end
    local crestMask=haloFrame:CreateMaskTexture()
    if crestMask:SetTexture(INDENT_MASK_TEX,"CLAMPTOBLACKADDITIVE","CLAMPTOBLACKADDITIVE")==false then
        crestMask:SetTexture(RAY_GRAD_TEX,"CLAMPTOBLACKADDITIVE","CLAMPTOBLACKADDITIVE")
    end
    if crestMask.SetTexelSnappingBias then crestMask:SetTexelSnappingBias(0) end
    if crestMask.SetSnapToPixelGrid then crestMask:SetSnapToPixelGrid(false) end
    if crest.AddMaskTexture then crest:AddMaskTexture(crestMask) end
    crest:Hide()

    e={tex=tex,mask=mask,crest=crest,crestMask=crestMask,anchorNP=nil}
    arcEntries[idx]=e
    return e
end

local function HideAllArcs()
    for i=1,#arcEntries do
        local e=arcEntries[i]
        e.anchorNP=nil
        e.tex:Hide()
        if e.crest then e.crest:Hide() end
    end
end

-- ============================================================
-- TankMate: Combat-safe Nameplate Threat Coloring & Oversized Loose-Mob Alert Frame
-- Green = attacking you (tank) | Amber = losing aggro | Big Red Frame = attacking someone else
-- ============================================================
local tankOverlays={} -- [unit] = Frame
local tankHooked=false

local function TankThreatState(unit)
    if not unit or not UnitExists or not UnitExists(unit) then return nil end
    local dead=UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)
    if not Public(dead) or dead then return nil end
    local canAtk=UnitCanAttack and UnitCanAttack("player",unit)
    if not Public(canAtk) or not canAtk then return nil end
    local mobCombat=UnitAffectingCombat and UnitAffectingCombat(unit)
    if not Public(mobCombat) or not mobCombat then return nil end
    local utok=UNIT_TARGET[unit] or (unit.."target")
    local targetsMe=UnitIsUnit and UnitIsUnit(utok,"player")
    if Public(targetsMe) and targetsMe then
        if UnitThreatSituation then
            local ok,sit=pcall(UnitThreatSituation,"player",unit)
            if ok and Public(sit) and sit==2 then return "losing" end
        end
        return "tanked"
    end
    if UnitThreatSituation then
        local ok,sit=pcall(UnitThreatSituation,"player",unit)
        if ok and Public(sit) and type(sit)=="number" then
            if sit==3 then return "tanked"
            elseif sit==2 then return "losing" end
        end
    end
    return "loose"
end

local function AcquireTankOverlay(unit)
    local f=tankOverlays[unit]
    if f then return f end
    f=CreateFrame("Frame",nil,UIParent,"BackdropTemplate")
    f:SetFrameStrata("LOW"); f:SetFrameLevel(8)
    f:EnableMouse(false)
    f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=2,insets={left=2,right=2,top=2,bottom=2}})
    f:SetBackdropColor(.85,.08,.08,.22)
    f:SetBackdropBorderColor(1,.18,.18,.95)
    local tag=f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    tag:SetPoint("BOTTOM",f,"TOP",0,1)
    tag:SetText("|cffff3838NO AGGRO|r")
    f.tag=tag
    f:Hide()
    tankOverlays[unit]=f
    return f
end

local function HideTankOverlay(unit)
    local f=tankOverlays[unit]
    if f and f:IsShown() then f:Hide(); f.anchorNP=nil end
end

local function HideAllTankOverlays()
    for _,f in pairs(tankOverlays) do
        if f:IsShown() then f:Hide(); f.anchorNP=nil end
    end
end

local function ApplyTankPlateVisual(unit)
    local c=Cfg()
    if not c.enabled or not c.tankMate then HideTankOverlay(unit); return end
    local np=C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit,false)
    if not np or (np.IsForbidden and np:IsForbidden()) then HideTankOverlay(unit); return end
    local state=TankThreatState(unit)
    local uf=np.UnitFrame
    local hb=uf and not (uf.IsForbidden and uf:IsForbidden()) and uf.healthBar
    if hb and not (hb.IsForbidden and hb:IsForbidden()) and hb.SetStatusBarColor then
        if state=="tanked" then
            hb:SetStatusBarColor(.18,.86,.38,1)
        elseif state=="losing" then
            hb:SetStatusBarColor(1,.78,.20,1)
        elseif state=="loose" then
            hb:SetStatusBarColor(1,.16,.16,1)
        end
    end
    if state=="loose" then
        local ov=AcquireTankOverlay(unit)
        local anchor=(hb and not (hb.IsForbidden and hb:IsForbidden())) and hb or np
        if ov.anchorNP~=anchor then
            ov.anchorNP=anchor
            ov:ClearAllPoints()
            ov:SetPoint("TOPLEFT",anchor,"TOPLEFT",-7,7)
            ov:SetPoint("BOTTOMRIGHT",anchor,"BOTTOMRIGHT",7,-7)
        end
        local strata=np.GetFrameStrata and np:GetFrameStrata()
        if strata and ov:GetFrameStrata()~=strata then ov:SetFrameStrata(strata) end
        local lvl=np.GetFrameLevel and np:GetFrameLevel()
        if type(lvl)=="number" then ov:SetFrameLevel(math.max(1,lvl-1)) end
        if not ov:IsShown() then ov:Show() end
    else
        HideTankOverlay(unit)
    end
end

-- ============================================================
-- DPS Threat Pill: Tiny, non-intrusive live aggro % on current hostile target
-- ============================================================
local threatPill=nil

local function EnsureThreatPill()
    if threatPill then return threatPill end
    local f=CreateFrame("Frame","SmyrnaAggroMateThreatPill",UIParent,"BackdropTemplate")
    f:SetSize(124,20); f:SetFrameStrata("MEDIUM"); f:SetFrameLevel(22)
    f:SetClampedToScreen(true); f:SetMovable(true); f:EnableMouse(true)
    f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1,insets={left=1,right=1,top=1,bottom=1}})
    f:SetBackdropColor(.055,.065,.092,.88)
    f:SetBackdropBorderColor(.82,.67,.33,.72)
    local c=Cfg()
    if type(c.threatPos)=="table" and Num(c.threatPos[1],0,5000) and Num(c.threatPos[2],0,5000) then
        f:SetPoint("CENTER",UIParent,"BOTTOMLEFT",c.threatPos[1],c.threatPos[2])
    else
        f:SetPoint("CENTER",UIParent,"CENTER",c.haloX or 0,(c.haloY or 0)-math.floor((c.haloSize or 260)*.38))
    end
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart",function(self)
        if not (InCombatLockdown and InCombatLockdown()) then self:StartMoving() end
    end)
    f:SetScript("OnDragStop",function(self)
        self:StopMovingOrSizing()
        local cx,cy=self:GetCenter()
        if cx and cy then Cfg().threatPos={math.floor(cx+.5),math.floor(cy+.5)} end
    end)
    f.lbl=f:CreateFontString(nil,"OVERLAY","GameFontNormalSmall")
    f.lbl:SetPoint("LEFT",7,1); f.lbl:SetText("THREAT"); f.lbl:SetTextColor(.82,.72,.46)
    f.pct=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    f.pct:SetPoint("RIGHT",-7,1); f.pct:SetJustifyH("RIGHT")
    f.barBg=f:CreateTexture(nil,"BACKGROUND",nil,2)
    f.barBg:SetPoint("BOTTOMLEFT",2,2); f.barBg:SetPoint("BOTTOMRIGHT",-2,2); f.barBg:SetHeight(2)
    f.barBg:SetColorTexture(.03,.04,.06,.95)
    f.bar=f:CreateTexture(nil,"ARTWORK",nil,2)
    f.bar:SetPoint("TOPLEFT",f.barBg,"TOPLEFT",0,0); f.bar:SetPoint("BOTTOMLEFT",f.barBg,"BOTTOMLEFT",0,0)
    f.bar:SetWidth(1)
    f:Hide()
    threatPill=f
    return f
end

local function UpdateDPSThreatPill(inCombat)
    local c=Cfg()
    if c.enabled and c.dpsThreat and editModeActive and not inCombat then
        local f=EnsureThreatPill()
        f.pct:SetText("|cffffd64774%|r")
        f:SetBackdropBorderColor(1,.84,.28,.85)
        f.bar:SetWidth(88)
        Suite.ApplyGradient(f.bar,"HORIZONTAL",.55,.46,.15,.95,1,.84,.28,1)
        if not f:IsShown() then f:Show() end
        return
    end
    if not c.enabled or not c.dpsThreat or not inCombat or not UnitDetailedThreatSituation then
        if threatPill and threatPill:IsShown() then threatPill:Hide() end
        return
    end
    if not UnitExists or not UnitExists("target") then
        if threatPill and threatPill:IsShown() then threatPill:Hide() end
        return
    end
    local dead=UnitIsDeadOrGhost and UnitIsDeadOrGhost("target")
    local canAtk=UnitCanAttack and UnitCanAttack("player","target")
    if not Public(dead) or dead or not Public(canAtk) or not canAtk then
        if threatPill and threatPill:IsShown() then threatPill:Hide() end
        return
    end
    local ok,isTanking,status,pct=pcall(UnitDetailedThreatSituation,"player","target")
    if not ok or not Public(pct) or type(pct)~="number" then
        if threatPill and threatPill:IsShown() then threatPill:Hide() end
        return
    end
    local f=EnsureThreatPill()
    local p=math.max(0,math.min(100,math.floor(pct+.5)))
    local r,g,b,hex
    if (Public(isTanking) and isTanking) or p>=100 then
        r,g,b,hex=1,.24,.24,"ff3d3d"
        f.pct:SetText("|cff"..hex.."AGGRO|r")
    elseif p>=90 then
        r,g,b,hex=1,.48,.18,"ff7a2e"
        f.pct:SetText("|cff"..hex..p.."%|r")
    elseif p>=70 then
        r,g,b,hex=1,.84,.28,"ffd647"
        f.pct:SetText("|cff"..hex..p.."%|r")
    else
        r,g,b,hex=.30,.88,.48,"4ce07a"
        f.pct:SetText("|cff"..hex..p.."%|r")
    end
    f:SetBackdropBorderColor(r,g,b,.80)
    f.bar:SetWidth(math.max(2,math.floor(120*(p/100))))
    Suite.ApplyGradient(f.bar,"HORIZONTAL",r*.55,g*.55,b*.55,.95,r,g,b,1)
    if not f:IsShown() then f:Show() end
end

local function EnsureTankHook()
    if tankHooked then return end
    tankHooked=true
    if hooksecurefunc and CompactUnitFrame_UpdateHealthColor then
        hooksecurefunc("CompactUnitFrame_UpdateHealthColor",function(frame)
            if not frame or (frame.IsForbidden and frame:IsForbidden()) then return end
            local unit=frame.unit
            if not Public(unit) or type(unit)~="string" or not unit:match("^nameplate%d+$") then return end
            local c=Cfg()
            if not c.enabled or not c.tankMate then return end
            local state=TankThreatState(unit)
            if not state then return end
            local hb=frame.healthBar
            if hb and not (hb.IsForbidden and hb:IsForbidden()) and hb.SetStatusBarColor then
                if state=="tanked" then hb:SetStatusBarColor(.18,.86,.38,1)
                elseif state=="losing" then hb:SetStatusBarColor(1,.78,.20,1)
                else hb:SetStatusBarColor(1,.16,.16,1) end
            end
        end)
    end
end

-- Hoisted zero-allocation HUD scan state & inspector (zero closures/tables allocated per 0.15s tick!)
local uCfg,uSz,uPlayerLvl,uWarnMargin
local uWarnCount,uArcCount=0,0
local uWorstMargin,uWorstEst,uWorstAggro,uWorstName,uWorstUnit,uWorstInCombat=999,nil,nil,nil,nil,false
local uWorstFaction,uWorstIsPlayer,uWorstLvl=nil,false,nil
local uSeenTarget=false

local function InspectUnit(unit,allowVisuals)
    if not UnitExists(unit) then return end
    local dead=UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)
    if not Public(dead) or dead then
        if aggroCount>0 then PruneDeadAggro(unit) end
        return
    end
    if allowVisuals and not uSeenTarget and UnitExists("target") then
        local same=UnitIsUnit(unit,"target")
        if Public(same) and same then uSeenTarget=true end
    end
    local isPlayer=UnitIsPlayer and UnitIsPlayer(unit)
    isPlayer=(Public(isPlayer) and isPlayer) and true or false
    local uFac=UnitFactionGroup and UnitFactionGroup(unit)
    local oppFac=(playerFaction and Public(uFac) and (uFac=="Alliance" or uFac=="Horde") and uFac~=playerFaction) and uFac or nil
    local isOppPlayer=isPlayer and (oppFac~=nil)
    local canAtk=UnitCanAttack("player",unit)
    local react=UnitReaction("player",unit)
    local utok=UNIT_TARGET[unit] or (unit.."target")
    local rawTargetMe=UnitIsUnit(utok,"player")
    local inCombatWithMe=(Public(rawTargetMe) and rawTargetMe) and true or false
    if inCombatWithMe and not isPlayer then RegisterAggroUnit(unit) end
    local hostile=(Public(canAtk) and canAtk and Public(react) and (react<=3 or inCombatWithMe))
    if not (hostile or isOppPlayer) then return end
    local _,_,est=Module.EstimateRange(unit)
    if not est then
        if isOppPlayer then est=45 else return end
    end
    local ml=UnitLevel(unit)
    local aggroR=Module.AggroRadius(ml,uPlayerLvl)
    local margin=est-aggroR
    if not (isOppPlayer or inCombatWithMe or margin<=uWarnMargin) then return end
    uWarnCount=uWarnCount+1
    local effMargin
    if isOppPlayer then
        effMargin=inCombatWithMe and -8 or (-3+(est/100))
    else
        effMargin=inCombatWithMe and -5 or margin
    end
    if effMargin<uWorstMargin then
        uWorstMargin=effMargin; uWorstEst=est; uWorstAggro=aggroR; uWorstInCombat=inCombatWithMe; uWorstUnit=unit
        uWorstFaction=oppFac; uWorstIsPlayer=isOppPlayer; uWorstLvl=Num(ml,-1,200) and ml or nil
        local un1,un2=UnitName(unit)
        if isPlayer and Suite.PlayerName then
            local pn=Suite.PlayerName(Public(un1) and un1 or nil,Public(un2) and un2 or nil)
            uWorstName=(type(pn)=="string" and pn~="") and pn or (oppFac or "Player")
        else
            uWorstName=(Public(un1) and type(un1)=="string") and un1 or "Mob"
        end
    end
    if not allowVisuals then return end
    local np=C_NamePlate and C_NamePlate.GetNamePlateForUnit and C_NamePlate.GetNamePlateForUnit(unit,false)
    if np and not (np.IsForbidden and np:IsForbidden()) then
        local r,g,b
        if oppFac and FACTION_COLORS[oppFac] then
            local fc=FACTION_COLORS[oppFac]
            r,g,b=fc[1],fc[2],fc[3]
        else
            r,g,b=DangerColor(effMargin,uWarnMargin)
        end
        local wm=uWarnMargin>1 and uWarnMargin or 1
        local alpha=(isOppPlayer or inCombatWithMe) and .96 or math.min(.94,math.max(.68,.94-(margin/wm)*.26))
        if effMargin<arcMargin then
            arcMargin=effMargin
            uArcCount=1
            local e=AcquireArc(uArcCount)
            if e then
                -- Strictly quarter-ish arc (< halo diameter) so it NEVER completes a 360° circle;
                -- moves smoothly around the rim following the closest visible enemy's nameplate.
                local maskW=math.floor(uSz*.72)
                local maskH=math.floor(uSz*.66)
                if e.lastMW~=maskW or e.lastMH~=maskH then
                    e.lastMW=maskW; e.lastMH=maskH
                    e.mask:SetSize(maskW,maskH)
                    e.crestMask:SetSize(math.floor(maskW*.68),math.floor(maskH*.68))
                end
                if e.anchorNP~=np then
                    e.anchorNP=np
                    e.mask:ClearAllPoints()
                    e.mask:SetPoint("CENTER",np,"CENTER",0,0)
                    e.crestMask:ClearAllPoints()
                    e.crestMask:SetPoint("CENTER",np,"CENTER",0,0)
                end
                e.tex:SetVertexColor(r,g,b,alpha)
                e.tex:Show()
                e.crest:SetVertexColor(math.min(1,r*.78+.24),math.min(1,g*.78+.24),math.min(1,b*.78+.24),math.min(1,alpha))
                e.crest:Show()
            end
        end
    end
end

local function ScanCombatAggroUnit(unit)
    if not UnitExists(unit) then return end
    local dead=UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)
    if not Public(dead) or dead then
        if aggroCount>0 then PruneDeadAggro(unit) end
        return
    end
    local isPlayer=UnitIsPlayer and UnitIsPlayer(unit)
    if Public(isPlayer) and isPlayer then return end
    if UnitTargetsPlayer(unit) then RegisterAggroUnit(unit) end
end

local function UpdateHUD()
    local c=Cfg()
    local lockdown=InCombatLockdown and InCombatLockdown()
    if not c.enabled then
        if haloFrame then
            haloFrame:Hide()
            if not lockdown and haloFrame.statusBg then haloFrame.statusBg:Hide() end
        end
        if leashPanel then leashPanel:Hide() end
        HideAllArcs()
        HideAllTankOverlays()
        return
    end
    EnsureHalo()
    local sz=c.haloSize or 260
    local hx,hy=c.haloX or 0,c.haloY or 0
    if haloFrame.lastSz~=sz then
        haloFrame.lastSz=sz; haloFrame:SetSize(sz,sz)
        PositionLeash(sz,hx,hy)
    end
    if haloFrame.lastX~=hx or haloFrame.lastY~=hy then
        haloFrame.lastX=hx; haloFrame.lastY=hy
        haloFrame:ClearAllPoints()
        haloFrame:SetPoint("CENTER",UIParent,"CENTER",hx,hy)
        PositionLeash(sz,hx,hy)
    end
    if not lockdown and haloFrame.statusBg then
        local btnY=hy-math.floor(sz*.34)
        if haloFrame.statusBg.lastX~=hx or haloFrame.statusBg.lastY~=btnY then
            haloFrame.statusBg.lastX=hx; haloFrame.statusBg.lastY=btnY
            haloFrame.statusBg:ClearAllPoints()
            haloFrame.statusBg:SetPoint("CENTER",UIParent,"CENTER",hx,btnY)
        end
    end
    local playerLvl=UnitLevel("player") or 1
    local inCombat=(UnitAffectingCombat and UnitAffectingCombat("player")) or lockdown
    if not playerFaction and UnitFactionGroup then
        local mf=UnitFactionGroup("player")
        if Public(mf) and (mf=="Alliance" or mf=="Horde") then playerFaction=mf end
    end

    -- 1. Transparent center halo + GPU-masked directional danger arcs + optional target frame
    -- Automatically hides during combat so the combat screen stays clean (still tracks aggro for leash).
    uCfg=c; uSz=sz; uPlayerLvl=playerLvl; uWarnMargin=c.warnMargin or 14
    uWarnCount=0; uArcCount=0; uSeenTarget=false; arcMargin=math.huge
    uWorstMargin=999; uWorstEst=nil; uWorstAggro=nil; uWorstName=nil; uWorstUnit=nil; uWorstInCombat=false
    uWorstFaction=nil; uWorstIsPlayer=false; uWorstLvl=nil
    local showHaloNow=c.showHalo and not inCombat
    if showHaloNow then
        if not haloFrame:IsShown() then haloFrame:Show() end
        for unit,isHostile in pairs(activePlates) do
            if isHostile then InspectUnit(unit,true) end
        end
        if not uSeenTarget and UnitExists("target") then InspectUnit("target",false) end
        for i=uArcCount+1,#arcEntries do
            local e=arcEntries[i]
            if e.anchorNP or e.tex:IsShown() then
                e.anchorNP=nil; e.tex:Hide()
                if e.crest then e.crest:Hide() end
            end
        end
        local hr,hg,hb=HaloColor()
        local baseAlpha=c.haloAlpha or 0
        -- Never show a full circle during normal gameplay — directional arcs only.
        if editModeActive or sliderDragging then
            haloFrame.base:SetVertexColor(hr,hg,hb,math.max(.35,baseAlpha))
            haloFrame.base:Show()
        else
            haloFrame.base:Hide()
        end
        if uWarnCount>0 then
            local r,g,b
            if uWorstFaction and FACTION_COLORS[uWorstFaction] then
                local fc=FACTION_COLORS[uWorstFaction]
                r,g,b=fc[1],fc[2],fc[3]
            else
                r,g,b=DangerColor(uWorstMargin,uWarnMargin)
            end
            if not lockdown then
                local sbg=haloFrame.statusBg
                if inCombat or not c.showTargetBtn then
                    if sbg:IsShown() then sbg:Hide() end
                else
                    local iconKey=uWorstFaction or "mob"
                    if sbg.lastIconKey~=iconKey then
                        sbg.lastIconKey=iconKey
                        local icon=haloFrame.statusIcon
                        if uWorstFaction and FACTION_TEX[uWorstFaction] and icon:SetTexture(FACTION_TEX[uWorstFaction])~=false then
                            icon:SetTexCoord(.06,.60,.04,.60)
                            icon:SetVertexColor(1,1,1,1)
                        else
                            if icon:SetTexture(TARGET_ICON_TEX)==false then icon:SetTexture(TARGET_ICON_FALLBACK) end
                            icon:SetTexCoord(0,1,0,1)
                        end
                    end
                    if not uWorstFaction then
                        haloFrame.statusIcon:SetVertexColor(r,g,b,1)
                    end
                    local extra=uWarnCount-1
                    local extraStr=(extra>0) and (" |cff9aa4b2(+"..extra..")|r") or ""
                    local statusTxt
                    if uWorstIsPlayer then
                        local lvlStr=(uWorstLvl and uWorstLvl>0) and ("Lv "..uWorstLvl) or "Lv ??"
                        statusTxt=string.format("%s |cffb8c4d4(%s)|r%s",uWorstName or uWorstFaction or "Enemy",lvlStr,extraStr)
                    else
                        statusTxt=(uWorstName or "Mob")..extraStr
                    end
                    if sbg.lastTxt~=statusTxt then
                        sbg.lastTxt=statusTxt
                        haloFrame.status:SetText(statusTxt)
                        local sw=haloFrame.status:GetStringWidth() or 80
                        sbg:SetSize(math.max(82,math.floor(sw+26)),18)
                    end
                    haloFrame.status:SetTextColor(r,g,b)
                    sbg.bgR,sbg.bgG,sbg.bgB=r*.16,g*.16,b*.16
                    if not sbg:IsMouseOver() then sbg:SetBackdropColor(sbg.bgR,sbg.bgG,sbg.bgB,.62) end
                    sbg:SetBackdropBorderColor(r,g,b,.85)
                    sbg.targetName=uWorstName; sbg.targetFaction=uWorstFaction; sbg.targetIsPlayer=uWorstIsPlayer; sbg.targetExtra=extra
                    local safeName=(type(uWorstName)=="string" and uWorstName~="") and uWorstName:gsub("[\r\n]",""):sub(1,80) or nil
                    local macro=safeName and ("/targetexact "..safeName) or ""
                    if macro~=sbg.lastMacro then
                        sbg.lastMacro=macro
                        sbg:SetAttribute("type","macro")
                        sbg:SetAttribute("type1","macro")
                        sbg:SetAttribute("macrotext",macro)
                        sbg:SetAttribute("macrotext1",macro)
                    end
                    if not sbg:IsShown() then sbg:Show() end
                end
            end
        else
            if not lockdown and haloFrame.statusBg:IsShown() then haloFrame.statusBg:Hide() end
        end
    else
        if haloFrame:IsShown() then haloFrame:Hide() end
        if not lockdown and haloFrame.statusBg and haloFrame.statusBg:IsShown() then haloFrame.statusBg:Hide() end
        HideAllArcs()
        if inCombat and c.showLeash then
            for unit,isHostile in pairs(activePlates) do
                if isHostile then ScanCombatAggroUnit(unit) end
            end
            if UnitExists("target") then ScanCombatAggroUnit("target") end
        end
    end

    -- 1b. TankMate nameplate threat coloring & oversized loose-mob alert frame
    if c.tankMate and inCombat then
        for unit in pairs(activePlates) do
            ApplyTankPlateVisual(unit)
        end
    else
        HideAllTankOverlays()
    end

    -- 1c. Tiny live DPS Threat % pill on current hostile target
    UpdateDPSThreatPill(inCombat)

    -- 2. Compact Aggro & Leash Tracker Card
    -- Only shown during combat when actively moving > 5 yd away from pull; closes when standing still.
    if not inCombat then
        if aggroCount>0 then wipe(aggroMobs); aggroCount=0 end
        lastMoveMode,lastMoveMap,lastMoveX,lastMoveY,lastMoveAt=nil,nil,nil,nil,0
    end
    if c.showLeash and inCombat and aggroCount>0 then
        local mode,m,px,py,w,h=PlayerWorldPos()
        local now=GetTime()
        -- Prune expired/dead mobs whose nameplate vanished before PruneDeadAggro saw them.
        for guid,info in pairs(aggroMobs) do
            if now-(info.lastHitAt or info.pullAt)>(info.leashSec+5) then
                aggroMobs[guid]=nil
                aggroCount=math.max(0,aggroCount-1)
            end
        end
        if aggroCount<=0 then
            if leashPanel and leashPanel:IsShown() then leashPanel:Hide() end
            return
        end
        local stepYards=0
        if mode and px and py then
            if lastMoveMode==mode and lastMoveMap==m and lastMoveX and lastMoveY then
                if mode=="world" then
                    local dx,dy=px-lastMoveX,py-lastMoveY
                    stepYards=math.sqrt(dx*dx+dy*dy)
                elseif w and h then
                    local dx,dy=(px-lastMoveX)*w,(py-lastMoveY)*h
                    stepYards=math.sqrt(dx*dx+dy*dy)
                end
                if stepYards>=0.8 then lastMoveX,lastMoveY=px,py end
            else
                lastMoveMode,lastMoveMap,lastMoveX,lastMoveY=mode,m,px,py
            end
        end
        local movingNow=((IsPlayerMoving and IsPlayerMoving()) and true or false) or (stepYards>=0.8)
        if movingNow then lastMoveAt=now end
        local isMovingRecently=movingNow or (lastMoveAt>0 and (now-lastMoveAt)<=LEASH_STILL_GRACE)

        local maxRanYards=0
        if isMovingRecently then
            for _,info in pairs(aggroMobs) do
                if mode and info.posMode==mode and info.map==m and info.px and info.py and px and py then
                    local ryd
                    if mode=="world" then
                        local dx=px-info.px; local dy=py-info.py
                        ryd=math.sqrt(dx*dx+dy*dy)
                    elseif w and h then
                        local dx=(px-info.px)*w; local dy=(py-info.py)*h
                        ryd=math.sqrt(dx*dx+dy*dy)
                    end
                    if ryd and ryd>maxRanYards then maxRanYards=ryd end
                end
            end
        end

        if isMovingRecently and maxRanYards>LEASH_MIN_YARDS then
            local idx=0
            local maxW=148
            local anyNearReset=false
            for _,info in pairs(aggroMobs) do
                idx=idx+1
                local row=leashRows[idx]
                if not row then
                    row=CreateFrame("Frame",nil,leashPanel)
                    row:SetHeight(22)
                    row.name=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
                    row.name:SetPoint("TOPLEFT",0,0); row.name:SetJustifyH("LEFT"); row.name:SetMaxLines(1)
                    row.stat=row:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
                    row.stat:SetPoint("TOPRIGHT",0,0); row.stat:SetJustifyH("RIGHT"); row.stat:SetMaxLines(1)
                    row.barBg=row:CreateTexture(nil,"BACKGROUND")
                    row.barBg:SetPoint("BOTTOMLEFT",0,1); row.barBg:SetPoint("BOTTOMRIGHT",0,1); row.barBg:SetHeight(3)
                    row.barBg:SetColorTexture(.03,.04,.06,.95)
                    row.barFill=row:CreateTexture(nil,"ARTWORK")
                    row.barFill:SetPoint("TOPLEFT",row.barBg,"TOPLEFT",0,0)
                    row.barFill:SetPoint("BOTTOMLEFT",row.barBg,"BOTTOMLEFT",0,0)
                    row.barFill:SetWidth(1)
                    leashRows[idx]=row
                end
                local ranYards=0
                if mode and info.posMode==mode and info.map==m and info.px and info.py and px and py then
                    if mode=="world" then
                        local dx=px-info.px; local dy=py-info.py
                        ranYards=math.sqrt(dx*dx+dy*dy)
                    elseif w and h then
                        local dx=(px-info.px)*w; local dy=(py-info.py)*h
                        ranYards=math.sqrt(dx*dx+dy*dy)
                    end
                end
                local remYards=math.max(0,math.floor(info.leashYards-ranYards+.5))
                local remSec=math.max(0,info.leashSec-(now-(info.lastHitAt or info.pullAt)))
                local nearReset=(remYards<=10 or remSec<=3)
                if nearReset then anyNearReset=true end
                local _,_,_,_,hex=ConColor(info.level,playerLvl)
                local shortName=(#info.name>18) and (info.name:sub(1,17)..".") or info.name
                row.name:SetText("|cff"..hex..shortName.."|r")
                row.stat:SetText(string.format("|cff%s%dy · %.1fs|r",nearReset and "78d49b" or "ffd670",remYards,remSec))
                local nw=row.name:GetStringWidth() or 70
                local sw=row.stat:GetStringWidth() or 58
                local needW=math.floor(nw+sw+28)
                if needW>maxW then maxW=needW end
                row.pct=math.max(0.03,math.min(1,ranYards/math.max(1,info.leashYards)))
                row.nearReset=nearReset
                row:ClearAllPoints()
                row:SetPoint("TOPLEFT",leashPanel,"TOPLEFT",10,-23-(idx-1)*24)
                row:SetPoint("TOPRIGHT",leashPanel,"TOPRIGHT",-9,-23-(idx-1)*24)
                row:Show()
                if idx>=4 then break end
            end
            for i=idx+1,#leashRows do leashRows[i]:Hide() end
            local panelW=math.max(152,math.min(232,maxW))
            local barW=panelW-19
            for i=1,idx do
                local row=leashRows[i]
                row.barFill:SetWidth(math.max(2,math.floor(barW*row.pct)))
                if row.nearReset then
                    Suite.ApplyGradient(row.barFill,"HORIZONTAL",.22,.68,.42,.95,.47,.85,.61,1)
                else
                    Suite.ApplyGradient(row.barFill,"HORIZONTAL",.72,.44,.16,.95,.96,.78,.36,1)
                end
            end
            if leashPanel.sub then leashPanel.sub:SetText(math.floor(maxRanYards+.5).."y run") end
            if leashPanel.accent then
                if anyNearReset then leashPanel.accent:SetColorTexture(.42,.86,.58,.95)
                else leashPanel.accent:SetColorTexture(.92,.68,.26,.95) end
            end
            leashPanel:SetSize(panelW,25+idx*24+4)
            leashPanel:Show()
        elseif leashPanel and leashPanel:IsShown() then
            leashPanel:Hide()
        end
    elseif leashPanel and leashPanel:IsShown() then
        leashPanel:Hide()
    end
end

local function SyncTicker()
    local c=Cfg()
    local hasHostileTarget=IsUnitThreatening("target")
    local need=c.enabled and (hostilePlateCount>0 or aggroCount>0 or hasHostileTarget or (UnitAffectingCombat and UnitAffectingCombat("player")))
    if need then
        UpdateHUD()
        if not ticker then ticker=C_Timer.NewTicker(.15,UpdateHUD) end
    else
        if ticker then ticker:Cancel(); ticker=nil end
        UpdateHUD()
    end
end

-- Live on-screen drag & resize overlay (activates automatically in WoW Edit Mode OR via /am button;
-- completely hidden and 0% clickable during normal gameplay!)
local function UpdateEditLabel()
    if not editOverlay or not editOverlay.lbl then return end
    local c=Cfg()
    editOverlay.lbl:SetText(string.format("AggroMate Halo (%d px)  ·  X:%d  Y:%d\n|cffb8c4d4Drag to move  ·  Corner to resize|r",
        c.haloSize or 260,c.haloX or 0,c.haloY or 0))
end

local function SaveEditOverlayPos()
    if not editOverlay or not UIParent then return end
    local cx,cy=editOverlay:GetCenter()
    local ux,uy=UIParent:GetCenter()
    if not (cx and cy and ux and uy) then return end
    local ox=math.max(-400,math.min(400,math.floor((cx-ux)+.5)))
    local oy=math.max(-300,math.min(300,math.floor((cy-uy)+.5)))
    local c=Cfg()
    c.haloX=ox; c.haloY=oy
    editOverlay:ClearAllPoints()
    editOverlay:SetPoint("CENTER",UIParent,"CENTER",ox,oy)
    UpdateEditLabel()
    if syncSlidersFn then syncSlidersFn() end
    UpdateHUD()
end

local SetEditMode
local function EnsureEditOverlay()
    if editOverlay then return editOverlay end
    local f=CreateFrame("Frame","SmyrnaAggroMateEditOverlay",UIParent,"BackdropTemplate")
    f:SetFrameStrata("FULLSCREEN_DIALOG"); f:SetFrameLevel(90); f:SetClampedToScreen(true)
    f:SetMovable(true); f:SetResizable(true); f:EnableMouse(true)
    if f.SetResizeBounds then f:SetResizeBounds(120,120,460,460) end
    f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=2,insets={left=2,right=2,top=2,bottom=2}})
    f:SetBackdropColor(.05,.06,.09,.16)
    f:SetBackdropBorderColor(.92,.76,.36,.92)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart",function(self)
        if not (InCombatLockdown and InCombatLockdown()) then self:StartMoving() end
    end)
    f:SetScript("OnDragStop",function(self)
        self:StopMovingOrSizing()
        SaveEditOverlayPos()
    end)
    f:SetScript("OnSizeChanged",function(self,w,h)
        if not self.resizing then return end
        local side=math.max(120,math.min(460,math.floor((w+h)/2+.5)))
        if math.abs(w-side)>1 or math.abs(h-side)>1 then self:SetSize(side,side) end
        Cfg().haloSize=side
        UpdateEditLabel()
        if syncSlidersFn then syncSlidersFn() end
        UpdateHUD()
    end)

    local lblBg=CreateFrame("Frame",nil,f,"BackdropTemplate")
    lblBg:SetSize(244,32); lblBg:SetPoint("BOTTOM",f,"TOP",0,6)
    lblBg:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1,insets={left=1,right=1,top=1,bottom=1}})
    lblBg:SetBackdropColor(.05,.06,.09,.88); lblBg:SetBackdropBorderColor(.92,.76,.36,.90)
    local lbl=lblBg:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    lbl:SetPoint("CENTER",0,0); lbl:SetJustifyH("CENTER"); lbl:SetTextColor(1,.88,.52)
    f.lbl=lbl

    local resize=CreateFrame("Button",nil,f)
    resize:SetSize(22,22); resize:SetPoint("BOTTOMRIGHT",-2,2)
    resize:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resize:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resize:RegisterForDrag("LeftButton")
    resize:SetScript("OnDragStart",function()
        if not (InCombatLockdown and InCombatLockdown()) then f.resizing=true; f:StartSizing("BOTTOMRIGHT") end
    end)
    resize:SetScript("OnDragStop",function()
        f.resizing=false; f:StopMovingOrSizing()
        local side=math.max(120,math.min(460,math.floor((f:GetWidth()+f:GetHeight())/2+.5)))
        f:SetSize(side,side); Cfg().haloSize=side
        SaveEditOverlayPos()
    end)

    local btnCenter=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    btnCenter:SetSize(82,22); btnCenter:SetPoint("TOP",f,"BOTTOM",-46,-6); btnCenter:SetText("Center"); Suite.StyleButton(btnCenter)
    btnCenter:SetScript("OnClick",function()
        local c=Cfg(); c.haloX=0; c.haloY=0
        f:ClearAllPoints(); f:SetPoint("CENTER",UIParent,"CENTER",0,0)
        UpdateEditLabel()
        if syncSlidersFn then syncSlidersFn() end
        UpdateHUD()
    end)
    local btnDone=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    btnDone:SetSize(82,22); btnDone:SetPoint("TOP",f,"BOTTOM",46,-6); btnDone:SetText("Done"); Suite.StyleButton(btnDone)
    btnDone:SetScript("OnClick",function() SetEditMode(false,false) end)
    f.btnCenter=btnCenter; f.btnDone=btnDone
    f:Hide()
    editOverlay=f
    return f
end

SetEditMode=function(on,fromMenu)
    if on and InCombatLockdown and InCombatLockdown() then return end
    if on then
        EnsureHalo()
        EnsureEditOverlay()
        editModeActive=true
        if fromMenu then
            editFromMenu=true
            if window and window:IsShown() then window:Hide() end
            local hub=_G.SmyrnaSuiteHub
            if hub and hub:IsShown() then hub:Hide(); editOverlay.reopenHub=true else editOverlay.reopenHub=false end
        end
        local c=Cfg()
        local sz=c.haloSize or 260
        editOverlay:SetSize(sz,sz)
        editOverlay:ClearAllPoints()
        editOverlay:SetPoint("CENTER",UIParent,"CENTER",c.haloX or 0,c.haloY or 0)
        editOverlay.btnDone:SetShown(editFromMenu)
        editOverlay.btnCenter:ClearAllPoints()
        if editFromMenu then editOverlay.btnCenter:SetPoint("TOP",editOverlay,"BOTTOM",-46,-6)
        else editOverlay.btnCenter:SetPoint("TOP",editOverlay,"BOTTOM",0,-6) end
        UpdateEditLabel()
        editOverlay:Show()
        UpdateHUD()
    else
        local wasFromMenu=editFromMenu
        editModeActive=false; editFromMenu=false
        local reopenHub=editOverlay and editOverlay.reopenHub
        if editOverlay then editOverlay.reopenHub=false; editOverlay:Hide() end
        local lockdown=InCombatLockdown and InCombatLockdown()
        if wasFromMenu and not lockdown and not fromMenu then
            if reopenHub and _G.SmyrnaSuiteHub then _G.SmyrnaSuiteHub:Show()
            elseif window then window:Show() end
        end
        UpdateHUD()
    end
end

local function SetMenuGhost(ghost)
    sliderDragging=ghost and true or false
    local a=sliderDragging and .14 or 1
    if window then window:SetAlpha(a) end
    local hub=_G.SmyrnaSuiteHub
    if hub then
        if not hubHooked then
            hubHooked=true
            hub:HookScript("OnHide",function()
                if sliderDragging then sliderDragging=false; hub:SetAlpha(1); if window then window:SetAlpha(1) end end
            end)
        end
        if hub:IsShown() or a==1 then hub:SetAlpha(a) end
    end
    UpdateHUD()
end

-- Settings UI in Hub
function Module.Open()
    if not window then
        checks={}
        window=CreateFrame("Frame","SmyrnaAggroMateWindow",UIParent,"BackdropTemplate")
        window:SetSize(760,544); window:SetPoint("CENTER"); window:SetFrameStrata("DIALOG"); window:SetClampedToScreen(true)
        window:SetMovable(true); window:EnableMouse(true); window:RegisterForDrag("LeftButton")
        window:SetScript("OnDragStart",function(self) if not (InCombatLockdown and InCombatLockdown()) then self:StartMoving() end end)
        window:SetScript("OnDragStop",function(self) self:StopMovingOrSizing() end)
        Suite.StylePanel(window,true)
        local close=Suite.CloseButton(window); window.SuiteCloseButton=close
        local title=window:CreateFontString(nil,"OVERLAY","GameFontNormalLarge"); title:SetPoint("TOPLEFT",16,-14); title:SetText("Smyrna AggroMate"); title:SetTextColor(1,.86,.48)
        local sub=window:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); sub:SetPoint("TOPLEFT",16,-36); sub:SetText("Click-through directional threat arcs with WoW Edit Mode placement, clickable target pill, and leash tracker."); sub:SetTextColor(.70,.75,.84)

        local card=CreateFrame("Frame",nil,window,"BackdropTemplate"); card:SetSize(728,258); card:SetPoint("TOPLEFT",16,-62); Suite.StyleCard(card)
        Suite.OptionSection(card,"Display, Position & Thresholds",14,-12,700)
        local function AddCheck(key,text,tipBody,x,y)
            local cb=CreateFrame("CheckButton",nil,card,"UICheckButtonTemplate"); cb:SetPoint("TOPLEFT",x,y)
            local lbl=cb:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); lbl:SetPoint("LEFT",cb,"RIGHT",2,0); lbl:SetText(text)
            cb:SetScript("OnClick",function(self) Cfg()[key]=self:GetChecked() and true or false; SyncTicker() end)
            Suite.AttachTooltip(cb,text,tipBody,lbl)
            checks[key]=cb
        end
        AddCheck("enabled","Enabled","Turn AggroMate directional threat arcs and leash tracking on or off.",12,-34)
        AddCheck("showHalo","Threat arcs","Sleek click-through directional outer arcs pointing toward nearby hostile mobs (automatically hidden during combat).",120,-34)
        AddCheck("showTargetBtn","Target frame","Low-opacity clickable enemy frame near your feet — left-click out of combat to target the closest threat.",244,-34)
        AddCheck("showLeash","Leash tracker","Compact card that appears only while running >10 yd away from aggroed mobs and closes automatically when standing still.",382,-34)
        AddCheck("tankMate","TankMate","Color in-combat nameplates Green when attacking you (tank), Amber when losing aggro, or oversized Red + NO AGGRO border when attacking someone else.",524,-34)

        local function HookGhost(slider)
            slider:HookScript("OnMouseDown",function() SetMenuGhost(true) end)
            slider:HookScript("OnMouseUp",function() SetMenuGhost(false) end)
        end

        local szLbl=card:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); szLbl:SetPoint("TOPLEFT",16,-74); szLbl:SetTextColor(.93,.77,.40)
        local szSlider=Suite.CreateSlider(card,206,120,460)
        szSlider:SetPoint("TOPLEFT",16,-94)
        HookGhost(szSlider)
        szSlider:SetScript("OnValueChanged",function(_,v)
            local n=math.floor((v or 260)+.5); Cfg().haloSize=n
            szLbl:SetText("Halo diameter: "..n.." px")
            UpdateHUD()
        end)

        local mgLbl=card:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); mgLbl:SetPoint("TOPLEFT",254,-74); mgLbl:SetTextColor(.93,.77,.40)
        local mgSlider=Suite.CreateSlider(card,206,6,25)
        mgSlider:SetPoint("TOPLEFT",254,-94)
        mgSlider:SetScript("OnValueChanged",function(_,v)
            local n=math.floor((v or 14)+.5); Cfg().warnMargin=n
            mgLbl:SetText("Warn within aggro + "..n.." yd")
            UpdateHUD()
        end)

        local opLbl=card:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); opLbl:SetPoint("TOPLEFT",492,-74); opLbl:SetTextColor(.93,.77,.40)
        local opSlider=Suite.CreateSlider(card,206,0,60)
        opSlider:SetPoint("TOPLEFT",492,-94)
        HookGhost(opSlider)
        opSlider:SetScript("OnValueChanged",function(_,v)
            local pct=math.floor((v or 0)+.5); Cfg().haloAlpha=pct/100
            opLbl:SetText("Placement guide opacity: "..pct.."%")
            UpdateHUD()
        end)

        local xLbl=card:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); xLbl:SetPoint("TOPLEFT",16,-134); xLbl:SetTextColor(.93,.77,.40)
        local xSlider=Suite.CreateSlider(card,206,-400,400)
        xSlider:SetPoint("TOPLEFT",16,-154)
        HookGhost(xSlider)
        xSlider:SetScript("OnValueChanged",function(_,v)
            local n=math.floor((v or 0)+.5); Cfg().haloX=n
            xLbl:SetText("Horizontal offset (X): "..n.." px")
            UpdateHUD()
        end)

        local yLbl=card:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); yLbl:SetPoint("TOPLEFT",254,-134); yLbl:SetTextColor(.93,.77,.40)
        local ySlider=Suite.CreateSlider(card,206,-300,300)
        ySlider:SetPoint("TOPLEFT",254,-154)
        HookGhost(ySlider)
        ySlider:SetScript("OnValueChanged",function(_,v)
            local n=math.floor((v or 0)+.5); Cfg().haloY=n
            yLbl:SetText("Vertical offset (Y): "..n.." px")
            UpdateHUD()
        end)

        local editBtn=CreateFrame("Button",nil,card,"UIPanelButtonTemplate"); editBtn:SetSize(206,24); editBtn:SetPoint("TOPLEFT",492,-148); editBtn:SetText("Move / Resize on Screen"); Suite.StyleButton(editBtn)
        editBtn:SetScript("OnClick",function() SetEditMode(true,true) end)
        Suite.AttachTooltip(editBtn,"Move / Resize on Screen","Hides the menu so you can drag & resize the halo directly over your live game screen (also works automatically inside WoW's built-in Edit Mode!).")

        local colLbl=card:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); colLbl:SetPoint("TOPLEFT",16,-202); colLbl:SetTextColor(.93,.77,.40); colLbl:SetText("Default circle color:")
        local colBtn=CreateFrame("Button",nil,card,"UIPanelButtonTemplate"); colBtn:SetSize(134,24); colBtn:SetPoint("LEFT",colLbl,"RIGHT",10,0); colBtn:SetText("    Pick color"); Suite.StyleButton(colBtn)
        local colSwatch=colBtn:CreateTexture(nil,"OVERLAY",nil,2); colSwatch:SetSize(12,12); colSwatch:SetPoint("LEFT",8,0)
        local function SyncColorSwatch()
            colSwatch:SetColorTexture(HaloColor())
        end
        window.syncColorSwatch=SyncColorSwatch
        local function SetHaloRGB(r,g,b)
            if not Num(r,0,1) or not Num(g,0,1) or not Num(b,0,1) then return end
            Cfg().haloColor=string.format("%02x%02x%02x",math.floor(r*255+.5),math.floor(g*255+.5),math.floor(b*255+.5))
            SyncColorSwatch(); UpdateHUD()
        end
        colBtn:SetScript("OnClick",function()
            local picker=ColorPickerFrame; if not picker or not picker.GetColorRGB then return end
            local r,g,b=HaloColor()
            local function Apply() SetHaloRGB(picker:GetColorRGB()) end
            local function Cancel() SetHaloRGB(r,g,b) end
            if picker.SetupColorPickerAndShow then
                picker:SetupColorPickerAndShow({r=r,g=g,b=b,hasOpacity=false,swatchFunc=Apply,cancelFunc=Cancel})
            elseif picker.SetColorRGB then
                picker:Hide(); picker.func=nil; picker.cancelFunc=nil
                picker:SetColorRGB(r,g,b); picker.hasOpacity=false; picker.func=Apply; picker.cancelFunc=Cancel
                picker:Show()
            end
        end)
        local colReset=CreateFrame("Button",nil,card,"UIPanelButtonTemplate"); colReset:SetSize(92,24); colReset:SetPoint("LEFT",colBtn,"RIGHT",8,0); colReset:SetText("Reset"); Suite.StyleButton(colReset)
        colReset:SetScript("OnClick",function()
            local c=Cfg(); c.haloColor="ffffff"; c.haloAlpha=0; c.haloX=0; c.haloY=0; c.haloSize=260
            if syncSlidersFn then syncSlidersFn() end
            SyncColorSwatch(); UpdateHUD()
        end)
        Suite.AttachTooltip(colBtn,"Default circle color","Sets the base color of the halo ring (visible when Circle opacity > 0%). Directional mob arcs still light up green, yellow, orange, red, or faction color.")

        local ref=CreateFrame("Frame",nil,window,"BackdropTemplate"); ref:SetSize(728,176); ref:SetPoint("TOPLEFT",16,-332); Suite.StyleCard(ref,.074,.086,.118)
        Suite.OptionSection(ref,"How Smyrna AggroMate Works",14,-12,700)
        local body=ref:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        body:SetPoint("TOPLEFT",14,-34); body:SetWidth(700); body:SetJustifyH("LEFT"); body:SetSpacing(3); body:SetTextColor(.84,.88,.94)
        body:SetText(
            "|cffffd6701. Threat Direction & Color:|r Enable enemy Nameplates (|cffffffffV|r) to light up a sleek quarter-arc pointing toward the closest visible threat (auto-hides in combat).\n"..
            "    |cff30eb73Green|r Safe squeeze space   ·   |cffffe047Yellow|r Approaching aggro   ·   |cffff8c38Orange|r Razor-thin edge   ·   |cffff4040Red|r Imminent aggro\n"..
            "    |cff3899ffAlliance|r & |cfff5293dHorde|r opposite-faction enemies glow in their faction color with their faction crest.\n"..
            "|cffffd6702. Quick Target Frame:|r Optional subtle low-opacity enemy frame near your feet — brightens on hover, left-click out of combat to target.\n"..
            "|cffffd6703. Placement & Sizing:|r Hold any slider to see through the menu, click |cffffd670Move / Resize on Screen|r, or position directly in WoW |cffffd670Edit Mode|r.\n"..
            "|cffffd6704. Leash Tracker:|r Appears only while moving >5 yd away from aggroed mobs and closes automatically when standing still in combat."
        )

        syncSlidersFn=function()
            local c=Cfg()
            szSlider:SetValue(c.haloSize or 260); szLbl:SetText("Halo diameter: "..(c.haloSize or 260).." px")
            mgSlider:SetValue(c.warnMargin or 14); mgLbl:SetText("Warn within aggro + "..(c.warnMargin or 14).." yd")
            local pct=math.floor(((c.haloAlpha or 0)*100)+.5)
            opSlider:SetValue(pct); opLbl:SetText("Placement guide opacity: "..pct.."%")
            xSlider:SetValue(c.haloX or 0); xLbl:SetText("Horizontal offset (X): "..(c.haloX or 0).." px")
            ySlider:SetValue(c.haloY or 0); yLbl:SetText("Vertical offset (Y): "..(c.haloY or 0).." px")
        end

        window:SetScript("OnShow",function()
            local c=Cfg()
            for k,cb in pairs(checks) do cb:SetChecked(c[k] and true or false) end
            syncSlidersFn()
            SyncColorSwatch()
            UpdateHUD()
        end)
        window:SetScript("OnHide",function() SetMenuGhost(false) end)
        UISpecialFrames[#UISpecialFrames+1]="SmyrnaAggroMateWindow"
    end
    window:Show()
    -- Hub may reuse an already-shown frame, so OnShow alone is insufficient.
    local c=Cfg()
    for key,cb in pairs(checks) do cb:SetChecked(c[key] and true or false) end
    if syncSlidersFn then syncSlidersFn() end
    if window.syncColorSwatch then window.syncColorSwatch() end
    UpdateHUD()
    return window
end

local driver=CreateFrame("Frame")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("SPELLS_CHANGED")
driver:RegisterEvent("NAME_PLATE_UNIT_ADDED")
driver:RegisterEvent("NAME_PLATE_UNIT_REMOVED")
driver:RegisterEvent("PLAYER_REGEN_DISABLED")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")
driver:RegisterEvent("PLAYER_TARGET_CHANGED")
driver:RegisterEvent("UNIT_THREAT_SITUATION_UPDATE")
pcall(driver.RegisterEvent,driver,"UNIT_THREAT_LIST_UPDATE")
if driver.RegisterUnitEvent then
    driver:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED","player")
else
    driver:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
end
driver:SetScript("OnEvent",function(self,event,arg1,_,arg3)
    if event=="PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        BuildSpellProbes()
        EnsureTankHook()
        if C_Item and C_Item.RequestLoadItemDataByID then
            for i=1,#ITEM_PROBES do pcall(C_Item.RequestLoadItemDataByID,ITEM_PROBES[i][2]) end
        end
        -- Seed any already-visible nameplates using UnitExists only (never touch forbidden NamePlate frames!)
        for i=1,40 do
            local u="nameplate"..i
            if UnitExists and UnitExists(u) and activePlates[u]==nil then
                local h=IsUnitThreatening(u)
                activePlates[u]=h; plateCount=plateCount+1
                if h then hostilePlateCount=hostilePlateCount+1 end
            end
        end
        -- Hook Blizzard Edit Mode so halo can be moved & resized natively when Edit Mode is open
        if EventRegistry and EventRegistry.RegisterCallback then
            pcall(EventRegistry.RegisterCallback,EventRegistry,"EditMode.Enter",function() SetEditMode(true,false) end,Module)
            pcall(EventRegistry.RegisterCallback,EventRegistry,"EditMode.Exit",function() SetEditMode(false,false) end,Module)
        end
        if EditModeManagerFrame and EditModeManagerFrame.HookScript then
            EditModeManagerFrame:HookScript("OnShow",function() SetEditMode(true,false) end)
            EditModeManagerFrame:HookScript("OnHide",function() SetEditMode(false,false) end)
        end
        SyncTicker()
    elseif event=="SPELLS_CHANGED" then
        BuildSpellProbes()
    elseif event=="NAME_PLATE_UNIT_ADDED" then
        if Public(arg1) and type(arg1)=="string" and activePlates[arg1]==nil then
            local h=IsUnitThreatening(arg1)
            activePlates[arg1]=h; plateCount=plateCount+1
            if h then hostilePlateCount=hostilePlateCount+1; SyncTicker() end
        end
    elseif event=="NAME_PLATE_UNIT_REMOVED" then
        if Public(arg1) and type(arg1)=="string" then
            HideTankOverlay(arg1)
            local prev=activePlates[arg1]
            if prev~=nil then
                activePlates[arg1]=nil; plateCount=math.max(0,plateCount-1)
                if prev then hostilePlateCount=math.max(0,hostilePlateCount-1); SyncTicker() end
            end
        end
    elseif event=="PLAYER_TARGET_CHANGED" or event=="UNIT_THREAT_LIST_UPDATE" then
        SyncTicker()
    elseif event=="PLAYER_REGEN_DISABLED" or event=="UNIT_THREAT_SITUATION_UPDATE" then
        if event=="PLAYER_REGEN_DISABLED" then
            if editModeActive then SetEditMode(false,true) end
            if sliderDragging then SetMenuGhost(false) end
        end
        if UnitTargetsPlayer("target") then RegisterAggroUnit("target") end
        for u,isH in pairs(activePlates) do
            if UnitTargetsPlayer(u) then
                if not isH then activePlates[u]=true; hostilePlateCount=hostilePlateCount+1 end
                RegisterAggroUnit(u)
            end
        end
        SyncTicker()
    elseif event=="PLAYER_REGEN_ENABLED" then
        wipe(aggroMobs); aggroCount=0
        lastMoveMode,lastMoveMap,lastMoveX,lastMoveY,lastMoveAt=nil,nil,nil,nil,0
        SyncTicker()
    elseif event=="UNIT_SPELLCAST_SUCCEEDED" then
        -- Reset leash timer only when player casts a harmful spell on an aggroed mob
        if Public(arg1) and arg1=="player" and aggroCount>0 and Public(arg3) and Num(arg3,1,2000000) then
            if IsHarmfulSpellID(arg3) then
                local tguid=UnitGUID and UnitGUID("target")
                if Public(tguid) and aggroMobs[tguid] then aggroMobs[tguid].lastHitAt=GetTime() end
            end
        end
    end
end)

SLASH_SMYRNAAGGROMATE1="/aggromate"
SLASH_SMYRNAAGGROMATE2="/am"
SlashCmdList.SMYRNAAGGROMATE=function() Module.Open() end

Suite.Loaded[name]=true
Module.Perf=function() if Suite.Memory then Suite.Memory() end end
