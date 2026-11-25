local _,Suite=...
local name="SmyrnaJournal"
Suite.Versions[name]="0.2.0"
if Suite.Config.features[name]==false then return end
local Module={}
Suite.Modules[name]=Module

local window,listScroll,listCanvas,detailScroll,detailCanvas
local listBtns,detailCards,filterBtns,subTabBtns={},{},{},{}
local searchBox,headerTitle,headerMeta,entranceBtn,trackerBtn,autoChk
local filterMode,searchQuery,selectedSlug,detailTab="all","",nil,"bosses"
local mapView,mapCanvas,mapTiles,mapFloorBtns,mapPins,mapEntrancePin,mapSingleTex,mapEmptyLbl=nil,nil,{},{},{},nil,nil,nil
local selectedFloor,highlightItemID,highlightBossName=1,nil,nil
local itemToDungeon,itemIndexBuilt=nil,false

-- Live in-dungeon run state
local runKills,runRareSeen,runDungeon,runStarted,inDungeon={},{},nil,nil,false
local trackerFrame,trackerTiles,trackerTicker,trackerManual,trackerSlug=nil,{},nil,false,nil
local lootPop,lootRows,lootHideGen,lootOwnerTile=nil,{},0,nil

local INSTANCE_ID_TO_NAME={
    [389]="Ragefire Chasm",[36]="The Deadmines",[43]="Wailing Caverns",[33]="Shadowfang Keep",
    [34]="The Stockade",[48]="Blackfathom Deeps",[90]="Gnomeregan",[47]="Razorfen Kraul",
    [189]="Scarlet Monastery",[129]="Razorfen Downs",[70]="Uldaman",[209]="Zul'Farrak",
    [349]="Maraudon",[109]="Sunken Temple",[230]="Blackrock Depths",[229]="Lower Blackrock Spire",
    [429]="Dire Maul: East",[329]="Stratholme: Living",[289]="Scholomance",
    -- WoW Forever custom dungeons
    [3065]="Hall of Thanes",[2999]="Ruins of Lordaeron",[2959]="City of Dalaran",
    [2998]="Excavation Site: Wetlands",[3001]="Shaper's Terrace",[2970]="The Drowned City",
    [3039]="Krol'dok Stronghold",[2994]="Alcaz Prison",[2974]="Blackmaw Hold",
}
local SCARLET_WING_MAPS={
    [302]="Scarlet Monastery: Graveyard",[303]="Scarlet Monastery: Library",
    [304]="Scarlet Monastery: Armory",[305]="Scarlet Monastery: Cathedral",
}

local function Public(v) return not (issecretvalue and issecretvalue(v)) end

local function Cfg()
    local c=Suite.Config.journal
    if type(c)~="table" then c={}; Suite.Config.journal=c end
    if c.autoTracker==nil then c.autoTracker=true end
    if c.locked==nil then c.locked=false end
    return c
end
Module.Config=Cfg

local function ItemIcon(id)
    local icon=C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(id)
    return (Public(icon) and icon) or "Interface\\Icons\\INV_Misc_QuestionMark"
end

local function BareName(s)
    if type(s)~="string" then return "" end
    return (s:lower():gsub("^the%s+",""):gsub("[%s%p]+",""))
end

local function SafeHideTip()
    if GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then GameTooltip:Hide() end
end

local function PlayerFaction()
    local f=UnitFactionGroup and UnitFactionGroup("player")
    return (Public(f) and (f=="Alliance" or f=="Horde")) and f or nil
end

local function QuestMatchesFaction(q,pf)
    if not q then return false end
    if not pf then return true end
    local qf=q.f
    if not qf or qf=="" or qf=="Both" then return true end
    return qf==pf
end

-- Hoisted per-render Upgrader context so EquipmentDB loads once & class-ineligible drops are filtered cleanly!
local function MakeUpgradeContext()
    local ok,res=pcall(function()
        local eq=Suite.Equipment
        local upg=Suite.Modules.SmyrnaUpgrader
        if not eq or not upg or not upg.Profile or not upg.Score then return nil end
        if not eq.records and eq.Ensure and not (InCombatLockdown and InCombatLockdown()) then eq.Ensure() end
        if not eq.records then return nil end
        local profile=upg.Profile()
        if not profile then return nil end
        local _,_,classID=UnitClass and UnitClass("player")
        local level=(UnitLevel and UnitLevel("player")) or 1
        if not Public(classID) or type(classID)~="number" then classID=nil end
        if not Public(level) or type(level)~="number" then level=1 end
        local ctx=(classID and eq.Context) and eq.Context(classID,level,false) or nil
        local equippedScore={}
        local equippedIDs={}
        for slot=1,18 do
            local eid=GetInventoryItemID and GetInventoryItemID("player",slot)
            if Public(eid) and type(eid)=="number" then
                equippedIDs[slot]=eid
                local er=eq.Get(eid,true)
                equippedScore[slot]=(er and upg.Score(er,profile)) or 0
            else
                equippedScore[slot]=0
            end
        end
        return {eq=eq,upg=upg,profile=profile,classID=classID,level=level,ctx=ctx,equippedScore=equippedScore,equippedIDs=equippedIDs}
    end)
    return ok and res or nil
end

-- Live Upgrader badge on any boss drop or quest reward (reuses EquipmentDB + Upgrader!)
local function UpgradeBadge(itemID,uCtx)
    uCtx=uCtx or MakeUpgradeContext()
    if not uCtx then return nil,false end
    local ok,badge,isUpg=pcall(function()
        local eq,upg,profile=uCtx.eq,uCtx.upg,uCtx.profile
        local row=eq.Get(itemID,true)
        if not row or not row.inv or row.inv==0 then return nil,false end
        local slots=eq.SlotsForInv and eq.SlotsForInv(row.inv)
        if not slots or #slots==0 then return nil,false end
        if uCtx.ctx and uCtx.classID and eq.Eligible then
            local anyOk=false
            for _,slot in ipairs(slots) do
                if eq.Eligible(row,uCtx.classID,uCtx.level,slot,nil,nil,uCtx.ctx) then anyOk=true; break end
            end
            if not anyOk then return nil,false end
        end
        local score=upg.Score(row,profile)
        if not score or score<=0 then return nil,false end
        local bestCur=math.huge
        for _,slot in ipairs(slots) do
            if uCtx.equippedIDs[slot]==itemID then return "|cff8ecfffEquipped|r",false end
            local curScore=uCtx.equippedScore[slot] or 0
            if curScore<bestCur then bestCur=curScore end
        end
        if bestCur==math.huge then bestCur=0 end
        if bestCur<=0 then return "|cff78d49bUpgrade|r",true end
        local pct=math.floor(((score-bestCur)/bestCur)*100+.5)
        if pct>=3 then return "|cff78d49b+"..pct.."%|r",true end
        if pct>=-3 then return "|cff8ecfff~0%|r",false end
        return nil,false
    end)
    if not ok then return nil,false end
    return badge,isUpg
end

-- Resistance summary badge from BestiaryDB
local function ResistanceHint(npcID)
    if not npcID then return nil end
    local B=Suite.Modules.SmyrnaBestiary
    if B and B.Matchups and B.Matchups.PlayerHint then
        return B.Matchups.PlayerHint(npcID)
    end
end

local function BossTileIcon(boss)
    if boss and boss.ic and boss.ic~="" then return boss.ic end
    if boss and boss.r==1 then return "Interface\\Icons\\INV_Misc_Head_Dragon_01" end
    return "Interface\\TargetingFrame\\UI-TargetingFrame-Skull"
end

-- Live 2D boss portrait resolver using Blizzard's native SetPortraitTextureFromCreatureDisplayID
-- + a single offscreen PlayerModel (zero extra disk art, works for all Classic & Forever bosses!)
local bossDisplayCache={}
local bossResolveQueue,bossResolveQueued,bossResolveActive={}, {}, false
local bossModelFrame,bossResolveCurrent=nil,nil

local function StartNextBossResolve()
    if bossResolveActive or #bossResolveQueue==0 then return end
    if not SetPortraitTextureFromCreatureDisplayID then wipe(bossResolveQueue); wipe(bossResolveQueued); return end
    if not bossModelFrame then
        bossModelFrame=CreateFrame("PlayerModel",nil,UIParent)
        bossModelFrame:SetSize(1,1); bossModelFrame:SetPoint("TOPLEFT",-10,-10); bossModelFrame:SetAlpha(0)
        bossModelFrame:SetScript("OnModelLoaded",function(self)
            local id=bossResolveCurrent
            bossResolveCurrent=nil; bossResolveActive=false
            if id then
                local did=self.GetDisplayInfo and self:GetDisplayInfo()
                if Public(did) and type(did)=="number" and did>0 then
                    bossDisplayCache[id]=did
                    if window and window:IsShown() then Module.RefreshDetail() end
                    if trackerFrame and trackerFrame:IsShown() and trackerSlug then Module.RefreshTracker(trackerSlug) end
                else
                    bossDisplayCache[id]=0
                end
            end
            C_Timer.After(.03,StartNextBossResolve)
        end)
    end
    local npcID=table.remove(bossResolveQueue,1)
    bossResolveQueued[npcID]=nil
    bossResolveCurrent=npcID; bossResolveActive=true
    local ok=pcall(bossModelFrame.SetCreature,bossModelFrame,npcID)
    if not ok then
        bossDisplayCache[npcID]=0; bossResolveCurrent=nil; bossResolveActive=false
        C_Timer.After(.03,StartNextBossResolve)
    else
        -- Safety timeout in case a creature model never fires OnModelLoaded
        local expect=npcID
        C_Timer.After(1.5,function()
            if bossResolveActive and bossResolveCurrent==expect then
                bossDisplayCache[expect]=0; bossResolveCurrent=nil; bossResolveActive=false
                StartNextBossResolve()
            end
        end)
    end
end

local function ApplyBossPortrait(tex,boss)
    if not tex then return end
    local npcID=boss and boss.id
    if npcID and SetPortraitTextureFromCreatureDisplayID then
        local cached=bossDisplayCache[npcID]
        if cached and cached>0 then
            tex:SetTexCoord(0,1,0,1)
            local ok=pcall(SetPortraitTextureFromCreatureDisplayID,tex,cached)
            if ok then return end
        elseif cached==nil and not bossResolveQueued[npcID] then
            bossResolveQueued[npcID]=true
            bossResolveQueue[#bossResolveQueue+1]=npcID
            StartNextBossResolve()
        end
    end
    tex:SetTexCoord(.08,.92,.08,.92)
    tex:SetTexture(BossTileIcon(boss))
end

local function BossHasUpgrade(boss,uCtx)
    if not boss or not boss.lt then return false end
    for _,it in ipairs(boss.lt) do
        local _,isUpg=UpgradeBadge(it[1],uCtx)
        if isUpg then return true end
    end
    return false
end

local function FindSlugByName(targetName)
    if not targetName or targetName=="" then return nil end
    local all=Suite.WorldDB and Suite.WorldDB.Dungeons and Suite.WorldDB.Dungeons()
    if not all then return nil end
    for _,d in ipairs(all) do
        if d.n==targetName then return d.s end
    end
    local want=BareName(targetName)
    for _,d in ipairs(all) do
        if BareName(d.n)==want then return d.s end
    end
    return nil
end

local function DetectCurrentDungeon()
    if not IsInInstance then return nil end
    local inInst,instType=IsInInstance()
    if not inInst or (instType~="party" and instType~="raid") then return nil end
    local instName,_,_,_,_,_,_,instID=GetInstanceInfo()
    local subZone=(GetSubZoneText and GetSubZoneText()) or ""
    if not Public(instName) then instName="" end
    if not Public(subZone) then subZone="" end
    local subLo=string.lower(subZone)
    local byID=Public(instID) and INSTANCE_ID_TO_NAME[tonumber(instID) or -1]
    if byID=="Scarlet Monastery" then
        local mapID=C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
        local wing=(Public(mapID) and SCARLET_WING_MAPS[mapID]) or nil
        if not wing then
            if subLo:find("graveyard",1,true) then wing="Scarlet Monastery: Graveyard"
            elseif subLo:find("library",1,true) then wing="Scarlet Monastery: Library"
            elseif subLo:find("armory",1,true) then wing="Scarlet Monastery: Armory"
            elseif subLo:find("cathedral",1,true) then wing="Scarlet Monastery: Cathedral" end
        end
        byID=wing or "Scarlet Monastery: Graveyard"
    elseif tonumber(instID)==229 then
        if subLo:find("rookery",1,true) or subLo:find("binding",1,true) or subLo:find("blackhand",1,true) or subLo:find("upper",1,true) then
            byID="Upper Blackrock Spire"
        elseif runDungeon=="upper_blackrock_spire" then
            byID="Upper Blackrock Spire"
        end
    elseif tonumber(instID)==429 then
        if subLo:find("capital",1,true) or subLo:find("west",1,true) or subLo:find("imprisoned",1,true) then
            byID="Dire Maul: West"
        elseif subLo:find("gordok",1,true) or subLo:find("north",1,true) or subLo:find("commons",1,true) then
            byID="Dire Maul: North"
        elseif runDungeon=="dire_maul_west" then
            byID="Dire Maul: West"
        elseif runDungeon=="dire_maul_north" then
            byID="Dire Maul: North"
        end
    elseif tonumber(instID)==329 then
        if subLo:find("gauntlet",1,true) or subLo:find("slaughter",1,true) or subLo:find("baron",1,true) or subLo:find("service",1,true) or subLo:find("elders",1,true) then
            byID="Stratholme: Undead"
        elseif runDungeon=="stratholme_undead" then
            byID="Stratholme: Undead"
        end
    end
    local slug=byID and FindSlugByName(byID)
    if slug then return slug end
    return FindSlugByName(instName)
end

-- ============================================================
-- In-Dungeon Lined-Up Boss & Rares Tracker HUD + Hover Loot
-- ============================================================

local function CancelLootHide()
    lootHideGen=lootHideGen+1
end

local function ScheduleLootHide()
    lootHideGen=lootHideGen+1
    local gen=lootHideGen
    C_Timer.After(.40,function()
        if gen~=lootHideGen or not lootPop or not lootPop:IsShown() then return end
        if lootPop:IsMouseOver() or (lootOwnerTile and lootOwnerTile:IsMouseOver()) then return end
        lootPop:Hide()
        lootOwnerTile=nil
        if GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) and GameTooltip:IsOwned(lootPop) then GameTooltip:Hide() end
    end)
end

local function EnsureLootPopover()
    if lootPop then return lootPop end
    lootPop=CreateFrame("Frame","SmyrnaJournalLootPopover",UIParent,"BackdropTemplate")
    lootPop:SetSize(286,90)
    lootPop:SetFrameStrata("TOOLTIP")
    lootPop:SetFrameLevel(40)
    lootPop:SetClampedToScreen(true)
    lootPop:EnableMouse(true)
    Suite.StylePanel(lootPop,true)
    lootPop.title=lootPop:CreateFontString(nil,"OVERLAY","GameFontNormal")
    lootPop.title:SetPoint("TOPLEFT",10,-8); lootPop.title:SetWidth(266); lootPop.title:SetJustifyH("LEFT"); lootPop.title:SetMaxLines(1)
    lootPop.meta=lootPop:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    lootPop.meta:SetPoint("TOPLEFT",10,-24); lootPop.meta:SetWidth(266); lootPop.meta:SetJustifyH("LEFT"); lootPop.meta:SetMaxLines(2); lootPop.meta:SetTextColor(.74,.80,.88)
    lootPop.hint=lootPop:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    lootPop.hint:SetPoint("BOTTOMLEFT",10,7); lootPop.hint:SetWidth(266); lootPop.hint:SetJustifyH("LEFT"); lootPop.hint:SetTextColor(.58,.64,.74)
    lootPop:SetScript("OnEnter",CancelLootHide)
    lootPop:SetScript("OnLeave",ScheduleLootHide)
    lootPop:Hide()
    return lootPop
end

local function GetLootRow(i)
    local r=lootRows[i]
    if r then return r end
    EnsureLootPopover()
    r=CreateFrame("Button",nil,lootPop,"BackdropTemplate")
    r:SetSize(266,26)
    Suite.StyleCard(r,.074,.086,.118)
    r:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    local hl=r:GetHighlightTexture(); if hl then hl:SetVertexColor(.95,.78,.36,.14) end
    r.tile=Suite.CreateIconTile(r,20); r.tile:SetPoint("LEFT",4,0)
    r.name=r:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    r.name:SetPoint("LEFT",29,0); r.name:SetWidth(166); r.name:SetJustifyH("LEFT"); r.name:SetMaxLines(1)
    r.right=r:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    r.right:SetPoint("RIGHT",-6,0); r.right:SetJustifyH("RIGHT")
    r:SetScript("OnEnter",function(self)
        CancelLootHide()
        if self.itemID and GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then
            local leftSpace=(lootPop:GetLeft() or 0)
            local rightSpace=(UIParent:GetWidth() or 1920)-(lootPop:GetRight() or 0)
            GameTooltip:SetOwner(self,rightSpace>=320 and "ANCHOR_RIGHT" or (leftSpace>=320 and "ANCHOR_LEFT" or "ANCHOR_RIGHT"))
            GameTooltip:SetHyperlink("item:"..self.itemID)
            GameTooltip:Show()
        end
    end)
    r:SetScript("OnLeave",function()
        SafeHideTip()
        ScheduleLootHide()
    end)
    r:SetScript("OnClick",function(self)
        if not self.itemID then return end
        if IsControlKeyDown and IsControlKeyDown() then
            local U=Suite.Modules.SmyrnaUpgrader
            if U and U.OpenForItem then U.OpenForItem(self.itemID) end
        elseif IsShiftKeyDown and IsShiftKeyDown() and ChatEdit_InsertLink then
            local _,link=GetItemInfo and GetItemInfo(self.itemID)
            if link then ChatEdit_InsertLink(link) end
        end
    end)
    lootRows[i]=r
    return r
end

local function ShowBossLootPopover(tile,boss,killed,seen)
    if not tile or not boss then return end
    CancelLootHide()
    EnsureLootPopover()
    lootOwnerTile=tile
    local isRare=boss.r==1
    local statusTxt=killed and " |cff78d49b[Defeated]|r" or (isRare and (seen and " |cffffd670[Spotted!]|r" or " |cff8a95a8[Rare]|r") or "")
    local lvlTxt=boss.l and ("  |cff9aa4b2Lv "..boss.l.."|r") or ""
    lootPop.title:SetText((boss.n or "Boss")..lvlTxt..statusTxt)
    if isRare then lootPop.title:SetTextColor(.70,.86,1) else lootPop.title:SetTextColor(1,.86,.48) end

    local resHint=ResistanceHint(boss.id)
    local items=boss.lt or {}
    local metaY=26
    if resHint and resHint~="" then
        lootPop.meta:SetText(resHint); lootPop.meta:Show()
        metaY=48
    else
        lootPop.meta:SetText(#items>0 and (#items.." recorded drops · hover item for tooltip") or "No loot table recorded.")
        lootPop.meta:Show()
        metaY=40
    end

    local uCtx=MakeUpgradeContext()
    local shownRows=0
    local maxRows=math.min(#items,12)
    for i=1,maxRows do
        local it=items[i]
        local itemID,itemName,slot,qual=it[1],it[2],it[3],it[4] or 2
        local row=GetLootRow(i)
        row.itemID=itemID
        row:ClearAllPoints(); row:SetPoint("TOPLEFT",10,-(metaY+(i-1)*28))
        row.tile.icon:SetTexture(ItemIcon(itemID))
        local qc=ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[qual]
        local qr,qg,qb=qc and qc.r or .9,qc and qc.g or .9,qc and qc.b or .94
        row.tile:SetBackdropBorderColor(qr,qg,qb,.92)
        row.name:SetText(itemName or ("Item #"..itemID)); row.name:SetTextColor(qr,qg,qb)
        local upg=UpgradeBadge(itemID,uCtx)
        row.right:SetText(upg or ("|cff8a95a8"..(slot or "").."|r"))
        row:Show()
        shownRows=i
    end
    for i=shownRows+1,#lootRows do lootRows[i]:Hide(); lootRows[i].itemID=nil end

    local extra=#items-maxRows
    local extraNote=extra>0 and (" (+"..extra.." more in Journal)") or ""
    lootPop.hint:SetText((boss.id and "Click boss: Bestiary\nCtrl + left-click item to expand upgrades" or "Hover item for tooltip\nCtrl + left-click to expand upgrades")..extraNote)
    local h=metaY+shownRows*28+math.max(24,lootPop.hint:GetStringHeight()+14)
    lootPop:SetSize(286,math.max(76,h))

    -- Anchor cleanly beside the tracker or hovered map pin on whichever side has more room
    lootPop:ClearAllPoints()
    local anchor=(trackerFrame and trackerFrame:IsShown() and tile:GetParent()==trackerFrame) and trackerFrame or tile
    local tx=(anchor and anchor:GetCenter()) or ((UIParent:GetWidth() or 1920)/2)
    local sw=UIParent:GetWidth() or 1920
    if tx>sw*.55 then
        lootPop:SetPoint("TOPRIGHT",anchor,"TOPLEFT",-6,0)
    else
        lootPop:SetPoint("TOPLEFT",anchor,"TOPRIGHT",6,0)
    end
    lootPop:Show()
end

local function FormatDuration(secs)
    secs=math.max(0,math.floor(secs or 0))
    local m=math.floor(secs/60); local s=secs%60
    return string.format("%d:%02d",m,s)
end

local function UpdateTrackerTimer()
    if not trackerFrame or not trackerFrame:IsShown() then return end
    if runDungeon and runDungeon==trackerSlug and runStarted then
        trackerFrame.timer:SetText(FormatDuration(time()-runStarted))
    else
        trackerFrame.timer:SetText(trackerManual and "Preview" or "0:00")
    end
end

local function EnsureTracker()
    if trackerFrame then return trackerFrame end
    trackerFrame=CreateFrame("Frame","SmyrnaJournalTracker",UIParent,"BackdropTemplate")
    trackerFrame:SetSize(224,116)
    trackerFrame:SetFrameStrata("MEDIUM"); trackerFrame:SetFrameLevel(20)
    trackerFrame:SetClampedToScreen(true); trackerFrame:SetMovable(true); trackerFrame:EnableMouse(true)
    Suite.StylePanel(trackerFrame,true)
    local pos=Cfg().pos
    if type(pos)=="table" and type(pos[1])=="number" and type(pos[2])=="number" then
        trackerFrame:SetPoint("CENTER",UIParent,"BOTTOMLEFT",pos[1],pos[2])
    else
        trackerFrame:SetPoint("TOPRIGHT",UIParent,"TOPRIGHT",-24,-190)
    end
    trackerFrame:RegisterForDrag("LeftButton")
    trackerFrame:SetScript("OnDragStart",function(self)
        if Cfg().locked or (InCombatLockdown and InCombatLockdown()) then return end
        self:StartMoving()
    end)
    trackerFrame:SetScript("OnDragStop",function(self)
        self:StopMovingOrSizing()
        local cx,cy=self:GetCenter()
        if cx and cy then Cfg().pos={math.floor(cx+.5),math.floor(cy+.5)} end
    end)

    trackerFrame.title=trackerFrame:CreateFontString(nil,"OVERLAY","GameFontNormal")
    trackerFrame.title:SetPoint("TOPLEFT",10,-8); trackerFrame.title:SetWidth(158); trackerFrame.title:SetJustifyH("LEFT"); trackerFrame.title:SetMaxLines(1); trackerFrame.title:SetTextColor(1,.86,.48)

    trackerFrame.sub=trackerFrame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    trackerFrame.sub:SetPoint("TOPLEFT",10,-24); trackerFrame.sub:SetWidth(120); trackerFrame.sub:SetJustifyH("LEFT"); trackerFrame.sub:SetTextColor(.72,.78,.86)

    trackerFrame.timer=trackerFrame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    trackerFrame.timer:SetPoint("TOPRIGHT",-10,-24); trackerFrame.timer:SetJustifyH("RIGHT"); trackerFrame.timer:SetTextColor(.95,.82,.44)

    -- Mini Open Journal button
    local jb=CreateFrame("Button",nil,trackerFrame,"UIPanelButtonTemplate")
    jb:SetSize(20,18); jb:SetPoint("TOPRIGHT",-28,-6); jb:SetText("J"); Suite.StyleButton(jb)
    jb:SetScript("OnClick",function()
        if trackerSlug then selectedSlug=trackerSlug end
        Module.Open()
    end)
    jb:SetScript("OnEnter",function(self)
        if not GameTooltip or (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then return end
        GameTooltip:SetOwner(self,"ANCHOR_TOP"); GameTooltip:SetText("Open full Dungeon Journal (/sj)"); GameTooltip:Show()
    end)
    jb:SetScript("OnLeave",SafeHideTip)

    -- Close button
    local cb=CreateFrame("Button",nil,trackerFrame,"UIPanelButtonTemplate")
    cb:SetSize(20,18); cb:SetPoint("TOPRIGHT",-6,-6); cb:SetText("x"); Suite.StyleButton(cb)
    cb:SetScript("OnClick",function() trackerManual=false; trackerFrame:Hide() end)

    local div=Suite.HorizontalRule(trackerFrame,8,-40,208)
    div:SetPoint("TOPRIGHT",-8,-40)

    trackerFrame.rareHeader=trackerFrame:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    trackerFrame.rareHeader:SetText("RARES"); trackerFrame.rareHeader:SetTextColor(.64,.82,1)
    trackerFrame.rareHeader:Hide()

    trackerFrame:SetScript("OnShow",function()
        UpdateTrackerTimer()
        if not trackerTicker and inDungeon then
            trackerTicker=C_Timer.NewTicker(1,UpdateTrackerTimer)
        end
    end)
    trackerFrame:SetScript("OnHide",function()
        if trackerTicker then trackerTicker:Cancel(); trackerTicker=nil end
        if lootPop then lootPop:Hide() end
        lootOwnerTile=nil
    end)
    return trackerFrame
end

local function GetTrackerTile(i)
    local t=trackerTiles[i]
    if t then return t end
    EnsureTracker()
    t=CreateFrame("Button",nil,trackerFrame,"BackdropTemplate")
    t:SetSize(38,38); t:RegisterForClicks("LeftButtonUp","RightButtonUp")
    Suite.StyleCard(t,.08,.09,.13)
    t.icon=t:CreateTexture(nil,"ARTWORK")
    t.icon:SetPoint("TOPLEFT",3,-3); t.icon:SetPoint("BOTTOMRIGHT",-3,3)
    t.icon:SetTexCoord(.08,.92,.08,.92)
    t.check=t:CreateFontString(nil,"OVERLAY","GameFontNormal")
    t.check:SetPoint("CENTER",0,0); t.check:SetText("|cff4cff7aOK|r"); t.check:Hide()
    t.upgDot=t:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    t.upgDot:SetPoint("TOPRIGHT",-2,-1); t.upgDot:SetText("|cff4cff7a+|r"); t.upgDot:Hide()
    t.tag=t:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    t.tag:SetPoint("BOTTOMRIGHT",-2,2); t.tag:SetTextColor(.92,.88,.76)
    t:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    local hl=t:GetHighlightTexture(); if hl then hl:SetVertexColor(1,.84,.40,.18) end
    t:SetScript("OnEnter",function(self)
        if self.boss then ShowBossLootPopover(self,self.boss,self.killed,self.seen) end
    end)
    t:SetScript("OnLeave",ScheduleLootHide)
    t:SetScript("OnClick",function(self,btn)
        if not self.boss then return end
        if btn=="LeftButton" and self.boss.id then
            local B=Suite.Modules.SmyrnaBestiary
            if B and B.OpenDrops then B.OpenDrops(self.boss.id) end
        elseif btn=="RightButton" then
            if trackerSlug then selectedSlug=trackerSlug end
            Module.Open()
        end
    end)
    trackerTiles[i]=t
    return t
end

function Module.RefreshTracker(slug,manualShow)
    if slug then trackerSlug=slug end
    if manualShow~=nil then trackerManual=manualShow end
    if not trackerSlug then
        if trackerFrame then trackerFrame:Hide() end
        return
    end
    if not inDungeon and not trackerManual then
        if trackerFrame then trackerFrame:Hide() end
        return
    end
    local d=Suite.WorldDB and Suite.WorldDB.Dungeon and Suite.WorldDB.Dungeon(trackerSlug)
    if not d then
        if trackerFrame then trackerFrame:Hide() end
        return
    end
    EnsureTracker()
    trackerFrame.title:SetText(d.n or trackerSlug)
    if d.fv then trackerFrame.title:SetTextColor(.52,.86,1) else trackerFrame.title:SetTextColor(1,.86,.48) end

    local bosses,rares={},{}
    for _,b in ipairs(d.b or {}) do
        if b.r==1 then rares[#rares+1]=b else bosses[#bosses+1]=b end
    end

    local killedBosses=0
    local isCurrentRun=(runDungeon==trackerSlug)
    for _,b in ipairs(bosses) do
        if isCurrentRun and runKills[b.n] then killedBosses=killedBosses+1 end
    end
    trackerFrame.sub:SetText(string.format("Bosses %d/%d%s",killedBosses,#bosses,#rares>0 and (" · "..#rares.."R") or ""))

    local PER_ROW,TILE,GAP=5,38,5
    local rowW=PER_ROW*TILE+(PER_ROW-1)*GAP
    local width=rowW+20
    local n,y=0,48

    local uCtx=MakeUpgradeContext()
    local function LayoutGroup(list,isRare)
        for i,b in ipairs(list) do
            n=n+1
            local t=GetTrackerTile(n)
            local col=(i-1)%PER_ROW
            local row=math.floor((i-1)/PER_ROW)
            t:ClearAllPoints(); t:SetPoint("TOPLEFT",10+col*(TILE+GAP),-(y+row*(TILE+GAP)))
            local killed=isCurrentRun and runKills[b.n] and true or false
            local seen=isCurrentRun and runRareSeen[b.n] and true or false
            t.boss=b; t.killed=killed; t.seen=seen
            ApplyBossPortrait(t.icon,b)
            t.icon:SetDesaturated(killed or (isRare and not seen))
            t:SetAlpha((isRare and not seen and not killed) and .58 or 1)
            t.check:SetShown(killed)
            t.upgDot:SetShown((not killed) and BossHasUpgrade(b,uCtx))
            t.tag:SetText(isRare and "R" or tostring(i))
            if killed then
                t:SetBackdropBorderColor(.28,.82,.45,.95)
            elseif isRare and seen then
                t:SetBackdropBorderColor(1,.82,.26,1)
            elseif isRare then
                t:SetBackdropBorderColor(.48,.66,.92,.85)
            else
                t:SetBackdropBorderColor(.82,.68,.36,.85)
            end
            t:Show()
        end
        if #list>0 then y=y+math.ceil(#list/PER_ROW)*(TILE+GAP) end
    end

    LayoutGroup(bosses,false)
    if #rares>0 then
        y=y+2
        trackerFrame.rareHeader:ClearAllPoints()
        trackerFrame.rareHeader:SetPoint("TOPLEFT",10,-y)
        trackerFrame.rareHeader:Show()
        y=y+14
        LayoutGroup(rares,true)
    else
        trackerFrame.rareHeader:Hide()
    end

    for i=n+1,#trackerTiles do trackerTiles[i]:Hide(); trackerTiles[i].boss=nil end
    trackerFrame:SetSize(width,math.max(96,y+6))
    trackerFrame:Show()
    UpdateTrackerTimer()
    if inDungeon and not trackerTicker then
        trackerTicker=C_Timer.NewTicker(1,UpdateTrackerTimer)
    end
end

function Module.ToggleTracker(slug)
    if trackerFrame and trackerFrame:IsShown() and not slug then
        trackerManual=false
        trackerFrame:Hide()
        return
    end
    local target=slug or (inDungeon and runDungeon) or selectedSlug
    if not target then
        local all=Suite.WorldDB and Suite.WorldDB.Dungeons and Suite.WorldDB.Dungeons()
        target=all and all[1] and all[1].s
    end
    if target then Module.RefreshTracker(target,true) end
end

-- ============================================================
-- Full Dungeon Journal Hub Window (/sj)
-- ============================================================

local function MakeListButton(i)
    local b=CreateFrame("Button",nil,listCanvas,"BackdropTemplate")
    b:SetSize(218,38)
    Suite.StyleCard(b,.074,.086,.118)
    b:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    local hl=b:GetHighlightTexture(); if hl then hl:SetVertexColor(.85,.68,.32,.12) end
    b.tile=Suite.CreateIconTile(b,26); b.tile:SetPoint("LEFT",6,0)
    b.name=b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    b.name:SetPoint("TOPLEFT",38,-5); b.name:SetWidth(174); b.name:SetJustifyH("LEFT"); b.name:SetMaxLines(1)
    b.meta=b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    b.meta:SetPoint("TOPLEFT",38,-20); b.meta:SetWidth(174); b.meta:SetJustifyH("LEFT"); b.meta:SetMaxLines(1); b.meta:SetTextColor(.68,.74,.82)
    b:SetScript("OnClick",function(self)
        if self.slug then selectedSlug=self.slug; selectedFloor=1; highlightItemID=nil; highlightBossName=nil; Module.RefreshDetail(); Module.RefreshList() end
    end)
    listBtns[i]=b
    return b
end

local function MakeDetailCard(i)
    local c=CreateFrame("Button",nil,detailCanvas,"BackdropTemplate")
    c:SetSize(566,40)
    Suite.StyleCard(c,.078,.090,.124)
    c:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    local hl=c:GetHighlightTexture(); if hl then hl:SetVertexColor(.85,.68,.32,.10) end
    c.tile=Suite.CreateIconTile(c,28); c.tile:SetPoint("LEFT",6,0)
    c.title=c:CreateFontString(nil,"OVERLAY","GameFontHighlight")
    c.title:SetPoint("TOPLEFT",42,-5); c.title:SetWidth(380); c.title:SetJustifyH("LEFT"); c.title:SetMaxLines(1)
    c.sub=c:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    c.sub:SetPoint("TOPLEFT",42,-21); c.sub:SetWidth(514); c.sub:SetJustifyH("LEFT"); c.sub:SetMaxLines(2); c.sub:SetTextColor(.74,.80,.88)
    c.right=c:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    c.right:SetPoint("TOPRIGHT",-10,-6); c.right:SetJustifyH("RIGHT")
    c:SetScript("OnEnter",function(self)
        if self.itemID and GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then
            GameTooltip:SetOwner(self,"ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:"..self.itemID)
            GameTooltip:Show()
        end
    end)
    c:SetScript("OnLeave",SafeHideTip)
    c:SetScript("OnClick",function(self)
        if self.npcID then
            local B=Suite.Modules.SmyrnaBestiary
            if B and B.OpenDrops then B.OpenDrops(self.npcID) end
        elseif self.itemID and IsControlKeyDown and IsControlKeyDown() then
            local U=Suite.Modules.SmyrnaUpgrader
            if U and U.OpenForItem then U.OpenForItem(self.itemID) end
        end
    end)
    detailCards[i]=c
    return c
end

function Module.RefreshList()
    if not window or not window:IsShown() then return end
    for k,b in pairs(filterBtns) do Suite.SetButtonSelected(b,filterMode==k) end
    local all=Suite.WorldDB and Suite.WorldDB.Dungeons and Suite.WorldDB.Dungeons() or {}
    local q=string.lower((searchQuery or ""):gsub("^%s+",""):gsub("%s+$",""))
    local filtered={}
    for _,d in ipairs(all) do
        local ok=true
        if filterMode=="forever" and not d.fv then ok=false
        elseif filterMode=="classic" and d.fv then ok=false end
        if ok and q~="" then
            local hay=string.lower((d.n or "").." "..(d.loc or "").." "..(d.l or ""))
            ok=hay:find(q,1,true)~=nil
        end
        if ok then filtered[#filtered+1]=d end
    end
    if not selectedSlug and filtered[1] then selectedSlug=filtered[1].s end
    for i=1,math.max(#filtered,#listBtns) do
        local d=filtered[i]; local b=listBtns[i] or MakeListButton(i)
        if d then
            b.slug=d.s
            b:ClearAllPoints(); b:SetPoint("TOPLEFT",0,-(i-1)*42)
            b.tile.icon:SetTexture(d.ic or "Interface\\Icons\\INV_Misc_Map_01")
            b.name:SetText(d.n or d.s)
            b.name:SetTextColor(d.fv and .52 or 1,d.fv and .86 or .92,d.fv and 1 or .70)
            local tag=d.fv and "|cff55ccffForever|r · " or ""
            b.meta:SetText(tag.."Lv "..(d.l or "?").." · "..(d.bc or 0).." bosses")
            local sel=(d.s==selectedSlug)
            if sel then b:SetBackdropBorderColor(.96,.80,.38,.95) else b:SetBackdropBorderColor(.22,.25,.33,.88) end
            Suite.SetCornerGlow(b,d.fv and .35 or .96,d.fv and .78 or .78,d.fv and 1 or .36,sel and .20 or .05)
            b:Show()
        else
            b.slug=nil; b:Hide()
        end
    end
    listCanvas:SetHeight(math.max(440,#filtered*42))
    listScroll:UpdateScrollChildRect()
end

function Module.RefreshDetail()
    if not window or not window:IsShown() then return end
    for k,b in pairs(subTabBtns) do Suite.SetButtonSelected(b,detailTab==k) end
    local d=selectedSlug and Suite.WorldDB and Suite.WorldDB.Dungeon(selectedSlug)
    if not d then
        headerTitle:SetText("Smyrna Dungeon Journal")
        headerMeta:SetText("Select a dungeon on the left (ensure SmyrnaWorldDB is enabled).")
        entranceBtn:Hide()
        for _,c in ipairs(detailCards) do c:Hide() end
        return
    end
    local pf=PlayerFaction()
    local visQuests=0
    for _,q in ipairs(d.q or {}) do if QuestMatchesFaction(q,pf) then visQuests=visQuests+1 end end
    local fvTag=d.fv and "  |cff55ccff[WoW Forever]|r" or ""
    headerTitle:SetText((d.n or "")..fvTag)
    headerMeta:SetText("Levels "..(d.l or "?").."  ·  "..(d.loc or "Azeroth").."  ·  "..#(d.b or {}).." bosses  ·  "..visQuests.." quests")
    entranceBtn:SetShown(d.e and d.e.m and true or false)
    entranceBtn.entrance=d.e

    local scrollTargetY=0
    local y,idx=0,0
    if mapView then mapView:SetShown(detailTab=="map") end
    if detailScroll then detailScroll:SetShown(detailTab~="map") end

    if detailTab=="map" then
        if Module.RefreshDungeonMap then Module.RefreshDungeonMap(d) end
        return
    elseif detailTab=="bosses" then
        local uCtx=MakeUpgradeContext()
        for _,boss in ipairs(d.b or {}) do
            idx=idx+1
            local bc=detailCards[idx] or MakeDetailCard(idx)
            bc:ClearAllPoints(); bc:SetPoint("TOPLEFT",0,-y); bc:SetSize(566,42)
            bc.itemID=nil; bc.npcID=boss.id
            ApplyBossPortrait(bc.tile.icon,boss)
            local isRare=boss.r==1
            local isMatchBoss=(highlightBossName and boss.n==highlightBossName)
            if isMatchBoss and scrollTargetY==0 then scrollTargetY=y end
            if isMatchBoss then
                bc:SetBackdropBorderColor(1,.84,.34,1)
            else
                bc:SetBackdropBorderColor(.22,.25,.33,.88)
            end
            if isRare then
                bc.tile:SetBackdropBorderColor(.55,.78,1,.95)
                Suite.SetCornerGlow(bc,.55,.78,1,.16)
            else
                bc.tile:SetBackdropBorderColor(.96,.78,.36,.95)
                Suite.SetCornerGlow(bc,1,.78,.36,.16)
            end
            local killed=runDungeon==d.s and runKills[boss.n]
            bc.title:SetText((boss.n or "Boss")..(isRare and "  |cff7cc4ff[Rare]|r" or "")..(boss.l and ("  |cff9aa4b2(Lv "..boss.l..")|r") or "")..(killed and "  |cff78d49b[Defeated]|r" or ""))
            if isRare then bc.title:SetTextColor(.72,.88,1) else bc.title:SetTextColor(1,.86,.48) end
            local hint=ResistanceHint(boss.id)
            bc.sub:SetText(hint or (boss.id and "Click boss to open Bestiary loot & resistances" or (#(boss.lt or {}).." recorded drops")))
            bc.right:SetText(boss.lt and (#boss.lt.." drops") or "")
            bc:Show(); y=y+46

            for _,item in ipairs(boss.lt or {}) do
                local itemID,itemName,slot,qual=item[1],item[2],item[3],item[4] or 2
                idx=idx+1
                local ic=detailCards[idx] or MakeDetailCard(idx)
                ic:ClearAllPoints(); ic:SetPoint("TOPLEFT",14,-y); ic:SetSize(552,36)
                ic.itemID=itemID; ic.npcID=nil
                ic.tile.icon:SetTexture(ItemIcon(itemID))
                local qc=ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[qual]
                local qr,qg,qb=qc and qc.r or .9,qc and qc.g or .9,qc and qc.b or .94
                ic.tile:SetBackdropBorderColor(qr,qg,qb,.9)
                local isHi=(highlightItemID and itemID==highlightItemID)
                if isHi then
                    if scrollTargetY==0 then scrollTargetY=math.max(0,y-46) end
                    ic:SetBackdropBorderColor(1,.84,.32,1)
                    Suite.SetCornerGlow(ic,1,.84,.32,.24)
                else
                    ic:SetBackdropBorderColor(.22,.25,.33,.88)
                    Suite.SetCornerGlow(ic,qr,qg,qb,qual>=3 and .12 or .04)
                end
                ic.title:SetText((isHi and "|cffffd670> |r" or "")..(itemName or ("Item #"..itemID))); ic.title:SetTextColor(qr,qg,qb)
                ic.sub:SetText(slot or "")
                local badge=UpgradeBadge(itemID,uCtx)
                ic.right:SetText(badge or "")
                ic:Show(); y=y+40
            end
            y=y+6
        end
    elseif detailTab=="quests" then
        for _,q in ipairs(d.q or {}) do
            if QuestMatchesFaction(q,pf) then
                idx=idx+1
                local qc=detailCards[idx] or MakeDetailCard(idx)
                qc:ClearAllPoints(); qc:SetPoint("TOPLEFT",0,-y); qc:SetSize(566,58)
                qc.itemID=(q.rw and q.rw[1] and q.rw[1][1]) or nil; qc.npcID=nil
                qc.tile.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
                local done=q.id and q.id>0 and C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted and C_QuestLog.IsQuestFlaggedCompleted(q.id)
                local fColor=q.f=="Alliance" and "55aaff" or q.f=="Horde" and "ff6655" or "ffd670"
                qc.tile:SetBackdropBorderColor(done and .37 or .92,done and .91 or .76,done and .56 or .34,.9)
                Suite.SetCornerGlow(qc,done and .37 or .92,done and .91 or .76,done and .56 or .34,.10)
                qc.title:SetText("["..(q.l or "?").."] "..(q.n or "Quest")..(done and "  |cff78d49b[Completed]|r" or ""))
                qc.title:SetTextColor(1,.92,.72)
                local detailLine=(q.p and ("Pickup: "..q.p) or (q.o or ""))
                if q.rw and #q.rw>0 then
                    local rwNames={}
                    for _,ri in ipairs(q.rw) do rwNames[#rwNames+1]=ri[2] or ("Item #"..ri[1]) end
                    detailLine=detailLine.."\nRewards: "..table.concat(rwNames,", ")
                end
                qc.sub:SetText(detailLine)
                qc.right:SetText("|cff"..fColor..(q.f or "Both").."|r"..(q.xp and ("\n|cff9aa4b2"..q.xp.." XP|r") or ""))
                qc:Show(); y=y+64
            end
        end
        if idx==0 then
            idx=1
            local ec=detailCards[1] or MakeDetailCard(1)
            ec:ClearAllPoints(); ec:SetPoint("TOPLEFT",0,0); ec:SetSize(566,46)
            ec.itemID=nil; ec.npcID=nil
            ec.tile.icon:SetTexture("Interface\\Icons\\INV_Misc_Book_09")
            ec.tile:SetBackdropBorderColor(.4,.45,.55,.8)
            Suite.SetCornerGlow(ec,.4,.45,.55,.06)
            ec.title:SetText("No quests available for your faction"); ec.title:SetTextColor(.82,.86,.92)
            ec.sub:SetText(pf and ("Showing "..pf.." and neutral quests only.") or "No quests recorded for this dungeon.")
            ec.right:SetText("")
            ec:Show(); y=52
        end
    elseif detailTab=="info" then
        idx=idx+1
        local ic=detailCards[idx] or MakeDetailCard(idx)
        ic:ClearAllPoints(); ic:SetPoint("TOPLEFT",0,-y); ic:SetSize(566,86)
        ic.itemID=nil; ic.npcID=nil
        ic.tile.icon:SetTexture("Interface\\Icons\\INV_Misc_Map_01")
        ic.tile:SetBackdropBorderColor(.48,.76,1,.95)
        Suite.SetCornerGlow(ic,.48,.76,1,.14)
        ic.title:SetText("Entrance & Location"); ic.title:SetTextColor(.64,.86,1)
        local entText=(d.loc or "Unknown location")
        if d.e and d.e.m then
            entText=entText..string.format("  (%.1f, %.1f)",(d.e.x or 0)/10,(d.e.y or 0)/10)
            if d.e.d then entText=entText.."\n"..d.e.d end
        end
        ic.sub:SetText(entText)
        ic.right:SetText("")
        ic:Show(); y=y+92

        -- Live Run Tracker summary
        idx=idx+1
        local rc=detailCards[idx] or MakeDetailCard(idx)
        rc:ClearAllPoints(); rc:SetPoint("TOPLEFT",0,-y); rc:SetSize(566,72)
        rc.itemID=nil; rc.npcID=nil
        rc.tile.icon:SetTexture("Interface\\Icons\\INV_Misc_PocketWatch_01")
        rc.tile:SetBackdropBorderColor(.96,.78,.36,.95)
        Suite.SetCornerGlow(rc,.96,.78,.36,.12)
        rc.title:SetText("In-Dungeon Boss & Rares Tracker"); rc.title:SetTextColor(1,.86,.48)
        local killedCount=0
        if runDungeon==d.s then for _ in pairs(runKills) do killedCount=killedCount+1 end end
        rc.sub:SetText(killedCount>0 and (killedCount.." of "..#(d.b or {}).." bosses defeated this run. Hover any tile in the popup HUD to inspect drops & upgrades.") or "Pops up automatically on entering a dungeon with bosses & rares lined up. Hover any boss to see loot, upgrades & resistances.")
        rc.right:SetText("")
        rc:Show(); y=y+78
    end

    for i=idx+1,#detailCards do detailCards[i]:Hide() end
    detailCanvas:SetHeight(math.max(410,y+12))
    detailScroll:UpdateScrollChildRect()
    local maxScroll=detailScroll:GetVerticalScrollRange() or 0
    detailScroll:SetVerticalScroll(math.max(0,math.min(maxScroll,scrollTargetY)))
end

-- ============================================================
-- Interactive Blizzard + Forever Dungeon Map Renderer
-- ============================================================

local function RenderDungeonMapFloor(d,floorIdx)
    if not mapView then return end
    local mp=d and d.mp
    local floors=(mp and mp.fl) or {}
    if #floors==0 then
        if mapSingleTex then mapSingleTex:Hide() end
        for _,t in ipairs(mapTiles) do t:Hide() end
        for _,b in ipairs(mapFloorBtns) do b:Hide() end
        for _,p in ipairs(mapPins) do p:Hide() end
        if mapEntrancePin then mapEntrancePin:Hide() end
        mapEmptyLbl:SetText("No interior map layout recorded for "..(d and d.n or "this dungeon").."."); mapEmptyLbl:Show()
        return
    end
    mapEmptyLbl:Hide()
    floorIdx=math.max(1,math.min(#floors,floorIdx or 1))
    selectedFloor=floorIdx

    -- Floor selector buttons (auto-wraps onto a second row for 5-6 floor dungeons like Blackmaw Hold)
    local fx,fy,maxW=0,0,558
    for i=1,math.max(#floors,#mapFloorBtns) do
        local fl=floors[i]
        local fb=mapFloorBtns[i]
        if fl then
            if not fb then
                fb=CreateFrame("Button",nil,mapView,"UIPanelButtonTemplate")
                fb:SetHeight(22); Suite.StyleButton(fb)
                mapFloorBtns[i]=fb
            end
            local lbl=(fl.lb and fl.lb~="") and fl.lb or ("Floor "..i)
            if #lbl>18 then lbl=lbl:sub(1,17).."." end
            local w=math.max(66,math.min(132,#lbl*6+18))
            if fx>0 and fx+w>maxW then fx=0; fy=fy-26 end
            fb:SetSize(w,22); fb:ClearAllPoints(); fb:SetPoint("TOPLEFT",fx,fy); fb:SetText(lbl)
            fb:SetScript("OnClick",function() RenderDungeonMapFloor(d,i) end)
            Suite.SetButtonSelected(fb,i==floorIdx)
            fb:SetShown(#floors>1)
            fx=fx+w+4
        elseif fb then
            fb:Hide()
        end
    end

    local mapTop=(#floors>1) and (fy-28) or 0
    local availH=math.max(300,420+mapTop)
    local mapH=math.min(372,availH)
    local mapW=math.floor(mapH*1.5+.5)
    mapCanvas:ClearAllPoints(); mapCanvas:SetPoint("TOPLEFT",math.floor((558-mapW)/2),mapTop); mapCanvas:SetSize(mapW,mapH)

    -- Hide previous art
    if mapSingleTex then mapSingleTex:Hide() end
    for _,t in ipairs(mapTiles) do t:Hide() end

    local fl=floors[floorIdx]
    local drawn=false

    -- 1. Imported Forever / custom full-sheet map texture (SmyrnaWorldDB\Maps\*)
    if fl.tx and fl.tx~="" then
        if not mapSingleTex then
            mapSingleTex=mapCanvas:CreateTexture(nil,"ARTWORK")
            mapSingleTex:SetAllPoints()
        end
        local tb
        if fl.tb and fl.tb>0 and fl.tb<=10000 then tb=fl.tb/10000
        elseif fl.tb and fl.tb>10000 then local px=fl.tb/10000; tb=px/(px>1024 and 2048 or 1024)
        else tb=683/1024 end
        local tr=(fl.tr and fl.tr>0 and fl.tr<=10000) and (fl.tr/10000) or 1
        mapSingleTex:SetTexCoord(0,tr,0,tb)
        if mapSingleTex:SetTexture(fl.tx)~=false then
            mapSingleTex:Show(); drawn=true
        end
    end

    -- 2. Native Blizzard C_Map tiles (zero disk footprint for Classic dungeons!)
    if not drawn and fl.u and C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures then
        local okL,layers=pcall(C_Map.GetMapArtLayers,fl.u)
        local layer=okL and type(layers)=="table" and layers[1]
        local okT,files=layer and pcall(C_Map.GetMapArtLayerTextures,fl.u,1)
        if okT and type(files)=="table" and #files>0 and layer.tileWidth and layer.tileHeight and layer.layerWidth and layer.layerHeight then
            local cols=math.ceil(layer.layerWidth/layer.tileWidth)
            local rows=math.ceil(layer.layerHeight/layer.tileHeight)
            if cols*rows<=24 and #files>=cols*rows then
                local sx,sy=mapW/layer.layerWidth,mapH/layer.layerHeight
                local okAll=true
                for r=0,rows-1 do
                    for c=0,cols-1 do
                        local ti=r*cols+c+1
                        local tile=mapTiles[ti]
                        if not tile then tile=mapCanvas:CreateTexture(nil,"ARTWORK"); mapTiles[ti]=tile end
                        local tw=math.min(layer.tileWidth,layer.layerWidth-c*layer.tileWidth)
                        local th=math.min(layer.tileHeight,layer.layerHeight-r*layer.tileHeight)
                        tile:ClearAllPoints(); tile:SetPoint("TOPLEFT",c*layer.tileWidth*sx,-r*layer.tileHeight*sy)
                        tile:SetSize(tw*sx,th*sy); tile:SetTexCoord(0,tw/layer.tileWidth,0,th/layer.tileHeight)
                        if tile:SetTexture(files[ti])==false then okAll=false end
                        tile:Show()
                    end
                end
                if okAll then drawn=true end
            end
        end
    end

    -- 3. Classic Blizzard 4x3 WorldMap tile fallback (Interface\WorldMap\<Name>\<Name><floor>_1..12)
    if not drawn and fl.t and fl.t~="" then
        local lw,lh,tw0,th0=1002,668,256,256
        local sx,sy=mapW/lw,mapH/lh
        for r=0,2 do
            for c=0,3 do
                local ti=r*4+c+1
                local tile=mapTiles[ti]
                if not tile then tile=mapCanvas:CreateTexture(nil,"ARTWORK"); mapTiles[ti]=tile end
                local tw=math.min(tw0,lw-c*tw0)
                local th=math.min(th0,lh-r*th0)
                tile:ClearAllPoints(); tile:SetPoint("TOPLEFT",c*tw0*sx,-r*th0*sy)
                tile:SetSize(tw*sx,th*sy); tile:SetTexCoord(0,tw/tw0,0,th/th0)
                tile:SetTexture(fl.t..ti)
                tile:Show()
            end
        end
        drawn=true
    end

    -- Entrance portal pin
    if mp.en and mp.en[1]==floorIdx then
        if not mapEntrancePin then
            mapEntrancePin=CreateFrame("Frame",nil,mapCanvas)
            mapEntrancePin:SetSize(22,22); mapEntrancePin:SetFrameLevel(mapCanvas:GetFrameLevel()+8); mapEntrancePin:EnableMouse(true)
            local tex=mapEntrancePin:CreateTexture(nil,"OVERLAY"); tex:SetAllPoints()
            tex:SetTexture("Interface\\MINIMAP\\Dungeon_Icon")
            mapEntrancePin:SetScript("OnEnter",function(self)
                if not GameTooltip or (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then return end
                GameTooltip:SetOwner(self,"ANCHOR_TOP"); GameTooltip:SetText("Dungeon Entrance",.48,.86,1); GameTooltip:Show()
            end)
            mapEntrancePin:SetScript("OnLeave",SafeHideTip)
        end
        mapEntrancePin:ClearAllPoints()
        mapEntrancePin:SetPoint("CENTER",mapCanvas,"TOPLEFT",(mp.en[2]/1000)*mapW,-(mp.en[3]/1000)*mapH)
        mapEntrancePin:Show()
    elseif mapEntrancePin then
        mapEntrancePin:Hide()
    end

    -- Build boss lookup table for this dungeon (exact + BareName fuzzy match)
    local bossByName,bossByBare={},{}
    for _,b in ipairs(d.b or {}) do bossByName[b.n]=b; bossByBare[BareName(b.n)]=b end
    local uCtx=MakeUpgradeContext()

    -- Boss & Rare interactive map pins
    local pinIdx=0
    local isCurrentRun=(runDungeon==d.s)
    for _,bp in ipairs(mp.bp or {}) do
        if bp[2]==floorIdx then
            pinIdx=pinIdx+1
            local p=mapPins[pinIdx]
            if not p then
                p=CreateFrame("Button",nil,mapCanvas,"BackdropTemplate")
                p:SetSize(26,26); p:SetFrameLevel(mapCanvas:GetFrameLevel()+10)
                Suite.StyleCard(p,.08,.09,.13)
                p.icon=p:CreateTexture(nil,"ARTWORK"); p.icon:SetPoint("TOPLEFT",2,-2); p.icon:SetPoint("BOTTOMRIGHT",-2,2); p.icon:SetTexCoord(.08,.92,.08,.92)
                p.ok=p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); p.ok:SetPoint("CENTER",0,0); p.ok:SetText("|cff4cff7aOK|r"); p.ok:Hide()
                p.upg=p:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); p.upg:SetPoint("TOPRIGHT",-1,0); p.upg:SetText("|cff4cff7a+|r"); p.upg:Hide()
                p:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
                local hl=p:GetHighlightTexture(); if hl then hl:SetVertexColor(1,.84,.40,.22) end
                p:SetScript("OnEnter",function(self)
                    if self.boss then
                        ShowBossLootPopover(self,self.boss,self.killed,self.seen)
                    elseif GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then
                        GameTooltip:SetOwner(self,"ANCHOR_TOP"); GameTooltip:SetText(self.bossName or "Encounter",1,.86,.48)
                        GameTooltip:AddLine("Bonus / Event Encounter",.70,.78,.88); GameTooltip:Show()
                    end
                end)
                p:SetScript("OnLeave",function() SafeHideTip(); ScheduleLootHide() end)
                p:SetScript("OnClick",function(self)
                    if not self.boss then return end
                    if IsControlKeyDown and IsControlKeyDown() and self.boss.id then
                        local B=Suite.Modules.SmyrnaBestiary
                        if B and B.OpenDrops then B.OpenDrops(self.boss.id) end
                    else
                        highlightBossName=self.boss.n; highlightItemID=nil
                        detailTab="bosses"; Module.RefreshDetail()
                    end
                end)
                mapPins[pinIdx]=p
            end
            local boss=bossByName[bp[1]] or bossByBare[BareName(bp[1])]
            local killed=isCurrentRun and runKills[boss and boss.n or bp[1]] and true or false
            local seen=isCurrentRun and runRareSeen[boss and boss.n or bp[1]] and true or false
            local isRare=boss and boss.r==1
            p.boss=boss; p.bossName=bp[1]; p.killed=killed; p.seen=seen
            p:ClearAllPoints()
            p:SetPoint("CENTER",mapCanvas,"TOPLEFT",(bp[3]/1000)*mapW,-(bp[4]/1000)*mapH)
            ApplyBossPortrait(p.icon,boss)
            p.icon:SetDesaturated(killed)
            p.ok:SetShown(killed)
            p.upg:SetShown((not killed) and boss and BossHasUpgrade(boss,uCtx))
            if killed then p:SetBackdropBorderColor(.28,.82,.45,1)
            elseif isRare then p:SetBackdropBorderColor(.48,.76,1,1)
            else p:SetBackdropBorderColor(.96,.78,.36,1) end
            p:Show()
        end
    end
    for i=pinIdx+1,#mapPins do mapPins[i]:Hide(); mapPins[i].boss=nil end
end

function Module.RefreshDungeonMap(d)
    if not mapView then return end
    RenderDungeonMapFloor(d,selectedFloor)
end

-- ============================================================
-- Upgrader -> Dungeon Journal Deep-Link API (Lazy Shared Index)
-- ============================================================

local itemIndexCursor,itemIndexScheduled=0,false

local function IndexDungeonMeta(meta)
    local d=meta and Suite.WorldDB.Dungeon(meta.s)
    if not d then return end
    for _,boss in ipairs(d.b or {}) do
        for _,it in ipairs(boss.lt or {}) do
            if it[1] and not itemToDungeon[it[1]] then
                itemToDungeon[it[1]]={slug=d.s,boss=boss.n}
            end
        end
    end
    for _,q in ipairs(d.q or {}) do
        for _,ri in ipairs(q.rw or {}) do
            if ri[1] and not itemToDungeon[ri[1]] then
                itemToDungeon[ri[1]]={slug=d.s,quest=q.n}
            end
        end
    end
end

local function ScheduleItemIndexStep()
    if itemIndexBuilt or itemIndexScheduled then return end
    if not C_Timer or not C_Timer.After then return end
    if not Suite.WorldDB or not Suite.WorldDB.Dungeons then return end
    local all=Suite.WorldDB.Dungeons()
    if not all or #all==0 then return end
    itemToDungeon=itemToDungeon or {}
    itemIndexScheduled=true
    local function Step()
        itemIndexScheduled=false
        if itemIndexBuilt then return end
        itemIndexCursor=itemIndexCursor+1
        local meta=all[itemIndexCursor]
        if meta then
            IndexDungeonMeta(meta)
            if itemIndexCursor<#all then
                itemIndexScheduled=true
                C_Timer.After(.02,Step)
            else
                itemIndexBuilt=true
            end
        else
            itemIndexBuilt=true
        end
    end
    C_Timer.After(.02,Step)
end

local function EnsureItemIndex()
    if itemIndexBuilt then return itemToDungeon end
    if not Suite.WorldDB or not Suite.WorldDB.Dungeons then return nil end
    local all=Suite.WorldDB.Dungeons()
    if not all or #all==0 then return nil end
    itemToDungeon=itemToDungeon or {}
    for i=itemIndexCursor+1,#all do
        IndexDungeonMeta(all[i])
        itemIndexCursor=i
    end
    itemIndexBuilt=true
    return itemToDungeon
end

function Module.HasItemOrZone(itemID,zoneHint)
    -- Never synchronously decompress all 35 dungeons during row/tooltip hover.
    if itemID and itemToDungeon and itemToDungeon[itemID] then return true end
    if zoneHint and zoneHint~="" then
        if FindSlugByName(zoneHint) then return true end
    end
    if itemID and not itemIndexBuilt then ScheduleItemIndexStep() end
    return false
end

function Module.OpenForItem(itemID,zoneHint)
    local match
    if itemID then
        local idx=EnsureItemIndex()
        match=idx and idx[itemID]
    end
    local slug=match and match.slug or (zoneHint and FindSlugByName(zoneHint))
    if not slug then return false end
    selectedSlug=slug
    selectedFloor=1
    highlightItemID=itemID
    highlightBossName=match and match.boss or nil
    detailTab=(match and match.quest and not match.boss) and "quests" or "bosses"
    Module.Open()
    return true
end

function Module.Open()
    if not window then
        listBtns={}; detailCards={}; filterBtns={}; subTabBtns={}
        window=CreateFrame("Frame","SmyrnaJournalWindow",UIParent,"BackdropTemplate")
        window:SetSize(860,600); window:SetPoint("CENTER"); window:SetFrameStrata("DIALOG"); window:SetClampedToScreen(true)
        Suite.StylePanel(window,true)
        local close=Suite.CloseButton(window); window.SuiteCloseButton=close
        local title=window:CreateFontString(nil,"OVERLAY","GameFontNormalLarge"); title:SetPoint("TOPLEFT",16,-14); title:SetText("Smyrna Dungeon Journal"); title:SetTextColor(1,.86,.48)
        local sub=window:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); sub:SetPoint("TOPLEFT",16,-36); sub:SetText("Classic & WoW Forever dungeons with auto-popup boss/rare HUD, Bestiary resistances, and live Upgrader badges."); sub:SetTextColor(.70,.75,.84)

        -- Left sidebar filters & search
        local fx=16
        for _,entry in ipairs({{"all","All",52},{"forever","Forever",74},{"classic","Classic",72}}) do
            local k,lbl,w=entry[1],entry[2],entry[3]
            local b=CreateFrame("Button",nil,window,"UIPanelButtonTemplate"); b:SetSize(w,22); b:SetPoint("TOPLEFT",fx,-60); b:SetText(lbl); Suite.StyleButton(b)
            b:SetScript("OnClick",function() filterMode=k; Module.RefreshList() end)
            filterBtns[k]=b; fx=fx+w+5
        end
        searchBox=CreateFrame("EditBox",nil,window,"InputBoxTemplate")
        searchBox:SetSize(218,22); searchBox:SetPoint("TOPLEFT",20,-88); searchBox:SetAutoFocus(false)
        searchBox:SetScript("OnTextChanged",function(self) searchQuery=self:GetText() or ""; Module.RefreshList() end)
        searchBox:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)

        listScroll=CreateFrame("ScrollFrame",nil,window,"UIPanelScrollFrameTemplate")
        listScroll:SetPoint("TOPLEFT",16,-118); listScroll:SetSize(222,464)
        listCanvas=CreateFrame("Frame",nil,listScroll); listCanvas:SetSize(218,464); listScroll:SetScrollChild(listCanvas)
        listScroll:EnableMouseWheel(true)
        listScroll:SetScript("OnMouseWheel",function(self,delta)
            local cur,max=self:GetVerticalScroll(),self:GetVerticalScrollRange()
            if type(cur)=="number" and type(max)=="number" then self:SetVerticalScroll(math.max(0,math.min(max,cur-delta*42))) end
        end)

        -- Right detail pane header
        headerTitle=window:CreateFontString(nil,"OVERLAY","GameFontNormalLarge"); headerTitle:SetPoint("TOPLEFT",264,-60); headerTitle:SetWidth(340); headerTitle:SetJustifyH("LEFT"); headerTitle:SetTextColor(1,.86,.48)
        headerMeta=window:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); headerMeta:SetPoint("TOPLEFT",264,-82); headerMeta:SetWidth(570); headerMeta:SetJustifyH("LEFT"); headerMeta:SetTextColor(.74,.80,.88)

        entranceBtn=CreateFrame("Button",nil,window,"UIPanelButtonTemplate"); entranceBtn:SetSize(96,22); entranceBtn:SetPoint("TOPRIGHT",-18,-58); entranceBtn:SetText("Show on Map"); Suite.StyleButton(entranceBtn)
        entranceBtn:SetScript("OnClick",function(self)
            local e=self.entrance
            if e and e.m and OpenWorldMap then OpenWorldMap(e.m)
            elseif e and e.m and WorldMapFrame and WorldMapFrame.SetMapID then WorldMapFrame:Show(); WorldMapFrame:SetMapID(e.m) end
        end)

        trackerBtn=CreateFrame("Button",nil,window,"UIPanelButtonTemplate"); trackerBtn:SetSize(102,22); trackerBtn:SetPoint("RIGHT",entranceBtn,"LEFT",-6,0); trackerBtn:SetText("Popup Tracker"); Suite.StyleButton(trackerBtn)
        trackerBtn:SetScript("OnClick",function() Module.ToggleTracker(selectedSlug) end)

        local tx=264
        for _,entry in ipairs({{"bosses","Bosses & Loot",110},{"map","Map",58},{"quests","Quests",72},{"info","Entrance & Run",108}}) do
            local k,lbl,w=entry[1],entry[2],entry[3]
            local b=CreateFrame("Button",nil,window,"UIPanelButtonTemplate"); b:SetSize(w,22); b:SetPoint("TOPLEFT",tx,-104); b:SetText(lbl); Suite.StyleButton(b)
            b:SetScript("OnClick",function()
                detailTab=k
                if k=="map" then selectedFloor=1 end
                Module.RefreshDetail()
            end)
            subTabBtns[k]=b; tx=tx+w+5
        end

        autoChk=CreateFrame("CheckButton",nil,window,"UICheckButtonTemplate")
        autoChk:SetPoint("TOPLEFT",tx+6,-102)
        local autoLbl=autoChk:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        autoLbl:SetPoint("LEFT",autoChk,"RIGHT",2,0); autoLbl:SetText("Auto HUD")
        autoChk:SetScript("OnClick",function(self) Cfg().autoTracker=self:GetChecked() and true or false end)
        Suite.AttachTooltip(autoChk,"Auto HUD","Automatically pop up the lined-up Boss & Rares tracker when entering a dungeon.",autoLbl)

        -- Embedded Dungeon Map container (shares detail pane slot with detailScroll)
        mapView=CreateFrame("Frame",nil,window)
        mapView:SetPoint("TOPLEFT",264,-134); mapView:SetSize(566,448)
        mapCanvas=CreateFrame("Frame",nil,mapView,"BackdropTemplate")
        mapCanvas:SetPoint("TOPLEFT",0,0); mapCanvas:SetSize(558,372)
        Suite.StyleCard(mapCanvas,.045,.052,.070)
        mapEmptyLbl=mapCanvas:CreateFontString(nil,"OVERLAY","GameFontHighlight")
        mapEmptyLbl:SetPoint("CENTER"); mapEmptyLbl:SetWidth(420); mapEmptyLbl:SetTextColor(.70,.75,.84); mapEmptyLbl:Hide()
        local mapHint=mapView:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        mapHint:SetPoint("BOTTOMLEFT",2,4); mapHint:SetText("Hover any boss pin for drops, upgrades & resistances  ·  Click pin to view loot\nCtrl + left-click to expand Bestiary")
        mapHint:SetTextColor(.68,.74,.84)
        mapView:Hide()

        detailScroll=CreateFrame("ScrollFrame",nil,window,"UIPanelScrollFrameTemplate")
        detailScroll:SetPoint("TOPLEFT",264,-134); detailScroll:SetSize(572,448)
        detailCanvas=CreateFrame("Frame",nil,detailScroll); detailCanvas:SetSize(566,448); detailScroll:SetScrollChild(detailCanvas)
        detailScroll:EnableMouseWheel(true)
        detailScroll:SetScript("OnMouseWheel",function(self,delta)
            local cur,max=self:GetVerticalScroll(),self:GetVerticalScrollRange()
            if type(cur)=="number" and type(max)=="number" then self:SetVerticalScroll(math.max(0,math.min(max,cur-delta*44))) end
        end)

        window:SetScript("OnShow",function()
            if inDungeon and runDungeon and not highlightItemID then selectedSlug=runDungeon end
            autoChk:SetChecked(Cfg().autoTracker~=false)
            Module.RefreshList(); Module.RefreshDetail()
        end)
        window:SetScript("OnHide",function() highlightItemID=nil; highlightBossName=nil end)
        UISpecialFrames[#UISpecialFrames+1]="SmyrnaJournalWindow"
    end
    window:Show()
    Module.RefreshList(); Module.RefreshDetail()
    return window
end

-- ============================================================
-- Event Driver (Auto-Popup on Dungeon Entry + Boss/Rare Sync)
-- ============================================================

local driver=CreateFrame("Frame")
local LIVE_EVENTS={"UPDATE_MOUSEOVER_UNIT","PLAYER_TARGET_CHANGED","NAME_PLATE_UNIT_ADDED","LOOT_OPENED","PLAYER_REGEN_ENABLED"}
local function SetDungeonLiveEvents(on)
    for _,ev in ipairs(LIVE_EVENTS) do
        if on then pcall(driver.RegisterEvent,driver,ev) else pcall(driver.UnregisterEvent,driver,ev) end
    end
end

local function CheckUnitForBossOrRare(unit)
    if not inDungeon or not runDungeon or not unit or not UnitExists or not UnitExists(unit) then return end
    local d=Suite.WorldDB and Suite.WorldDB.Dungeon and Suite.WorldDB.Dungeon(runDungeon)
    if not d or not d.b then return end
    local guid=UnitGUID and UnitGUID(unit)
    local npcID=(Public(guid) and type(guid)=="string") and tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-")) or nil
    local uName=UnitName and UnitName(unit)
    if not Public(uName) then uName=nil end
    local isDead=UnitIsDeadOrGhost and UnitIsDeadOrGhost(unit)
    if not Public(isDead) then isDead=false end
    for _,b in ipairs(d.b) do
        if (npcID and b.id==npcID) or (uName and uName==b.n) then
            if isDead then
                if not runKills[b.n] then
                    runKills[b.n]=true
                    if trackerFrame and trackerFrame:IsShown() and trackerSlug==runDungeon then Module.RefreshTracker(runDungeon) end
                    if window and window:IsShown() and selectedSlug==runDungeon then Module.RefreshDetail() end
                end
            elseif b.r==1 and not runRareSeen[b.n] and not runKills[b.n] then
                runRareSeen[b.n]=true
                Module.RefreshTracker(runDungeon)
            end
            return
        end
    end
end

local function SyncDungeonZone()
    local slug=DetectCurrentDungeon()
    if slug then
        inDungeon=true
        SetDungeonLiveEvents(true)
        if runDungeon~=slug then
            wipe(runKills); wipe(runRareSeen)
            runDungeon=slug; runStarted=time()
        end
        selectedSlug=slug
        if Cfg().autoTracker~=false then
            Module.RefreshTracker(slug,false)
        end
    else
        inDungeon=false
        SetDungeonLiveEvents(false)
        if trackerTicker then trackerTicker:Cancel(); trackerTicker=nil end
        if trackerFrame and not trackerManual then trackerFrame:Hide() end
    end
end

driver:RegisterEvent("PLAYER_ENTERING_WORLD")
driver:RegisterEvent("ZONE_CHANGED_NEW_AREA")
driver:RegisterEvent("ZONE_CHANGED")
pcall(driver.RegisterEvent,driver,"ENCOUNTER_END")
driver:SetScript("OnEvent",function(_,event,a1,a2,_,_,a5)
    if event=="PLAYER_ENTERING_WORLD" or event=="ZONE_CHANGED_NEW_AREA" or event=="ZONE_CHANGED" then
        SyncDungeonZone()
    elseif event=="ENCOUNTER_END" then
        if not Public(a1) or not Public(a5) or a5~=1 then return end
        local encs=Suite.WorldDB and Suite.WorldDB.Encounters and Suite.WorldDB.Encounters()
        local match=encs and encs[a1]
        if not match then return end
        local slug,bossName=match[1],match[2]
        if runDungeon~=slug then wipe(runKills); wipe(runRareSeen); runDungeon=slug; runStarted=time() end
        runKills[bossName]=true
        if trackerFrame and trackerFrame:IsShown() and trackerSlug==slug then Module.RefreshTracker(slug) end
        if window and window:IsShown() and selectedSlug==slug then Module.RefreshDetail() end
    elseif event=="LOOT_OPENED" or event=="PLAYER_REGEN_ENABLED" then
        CheckUnitForBossOrRare("target")
        CheckUnitForBossOrRare("mouseover")
        for i=1,40 do
            local u="nameplate"..i
            if UnitExists and UnitExists(u) then CheckUnitForBossOrRare(u) end
        end
    elseif event=="UPDATE_MOUSEOVER_UNIT" then
        CheckUnitForBossOrRare("mouseover")
    elseif event=="PLAYER_TARGET_CHANGED" then
        CheckUnitForBossOrRare("target")
    elseif event=="NAME_PLATE_UNIT_ADDED" then
        if Public(a1) and type(a1)=="string" then CheckUnitForBossOrRare(a1) end
    end
end)

SLASH_SMYRNAJOURNAL1="/sj"
SLASH_SMYRNAJOURNAL2="/smyrnajournal"
SlashCmdList.SMYRNAJOURNAL=function(msg)
    local cmd=string.lower((msg or ""):gsub("^%s+",""):gsub("%s+$",""))
    if cmd=="tracker" or cmd=="hud" then
        Module.ToggleTracker()
    elseif cmd=="lock" then
        Cfg().locked=not Cfg().locked
        print("|cffffd670Smyrna Journal:|r Dungeon tracker "..(Cfg().locked and "locked" or "unlocked")..".")
    else
        Module.Open()
    end
end

Suite.Loaded[name]=true
Module.Perf=function() if Suite.Memory then Suite.Memory() end end
