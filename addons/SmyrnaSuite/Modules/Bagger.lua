local _,Suite=...
local name="SmyrnaBagger"
Suite.Versions[name]="0.1.0"
if Suite.Config.features[name]==false then return end
local Module={}
Suite.Modules[name]=Module

local Public=Suite.Public or function(v) return not (issecretvalue and issecretvalue(v)) end
local function Num(v,lo,hi) return Public(v) and type(v)=="number" and v==v and v>=lo and v<=hi end

local bagFrame,settingsWin,checks=nil,nil,{}
local bagParents={}   -- [bag] = Frame with SetID(bag)
local slotBtns={}     -- [bag] = { [slot] = Button }
local bagFilterBtns={} -- [bag] = Button
local hiddenBags={}   -- [bag] = true if user toggled bag off in filter bar
local searchText=""
local hooksInstalled=false
local pendingLayout=false
local syncControlsFn=nil
local equipSetLabel={} -- [itemID] = "Tank, DPS"

local function RebuildEquipmentSets()
    wipe(equipSetLabel)
    if not (C_EquipmentSet and C_EquipmentSet.GetEquipmentSetIDs and C_EquipmentSet.GetEquipmentSetInfo and C_EquipmentSet.GetItemIDs) then return end
    local ok,ids=pcall(C_EquipmentSet.GetEquipmentSetIDs)
    if not ok or type(ids)~="table" then return end
    local byItem={}
    for _,setID in ipairs(ids) do
        local sName=C_EquipmentSet.GetEquipmentSetInfo(setID)
        if Public(sName) and type(sName)=="string" and sName~="" then
            local iok,items=pcall(C_EquipmentSet.GetItemIDs,setID)
            if iok and type(items)=="table" then
                for _,itemID in pairs(items) do
                    if Public(itemID) and type(itemID)=="number" and itemID>0 then
                        local list=byItem[itemID]
                        if not list then list={}; byItem[itemID]=list end
                        local dup=false
                        for i=1,#list do if list[i]==sName then dup=true; break end end
                        if not dup then list[#list+1]=sName end
                    end
                end
            end
        end
    end
    for itemID,list in pairs(byItem) do
        table.sort(list)
        equipSetLabel[itemID]=table.concat(list,", ")
    end
end

local equipTipHooked=false
local function HookEquipSetTooltips()
    if equipTipHooked then return end
    equipTipHooked=true
    local function AddSetLine(tip,data)
        if not tip or (tip.IsForbidden and tip:IsForbidden()) then return end
        local id=data and Public(data.id) and type(data.id)=="number" and data.id
        if not id and TooltipUtil and TooltipUtil.GetDisplayedItem then
            local ok,_,_,tid=pcall(TooltipUtil.GetDisplayedItem,tip)
            if ok and Public(tid) and type(tid)=="number" then id=tid end
        end
        if not id and tip.GetItem then
            local _,link=tip:GetItem()
            if Public(link) and type(link)=="string" then id=tonumber(link:match("item:(%d+)")) end
        end
        local label=id and equipSetLabel[id]
        if label then
            tip:AddLine("Saved in: "..label,0.45,0.88,1.0)
        end
    end
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item,AddSetLine)
    elseif GameTooltip and GameTooltip:HasScript("OnTooltipSetItem") then
        GameTooltip:HookScript("OnTooltipSetItem",function(tip) AddSetLine(tip,nil) end)
    end
end

local function Cfg()
    local c=Suite.Config.bagger
    if type(c)~="table" then c={}; Suite.Config.bagger=c end
    if c.enabled==nil then c.enabled=true end
    if c.showBagBar==nil then c.showBagBar=true end
    if type(c.bgColor)~="string" or not c.bgColor:match("^%x%x%x%x%x%x$") then c.bgColor="0e1015" end
    if not Num(c.bgAlpha,.40,1.0) then c.bgAlpha=.94 end
    if not Num(c.columns,6,16) then c.columns=10 end
    if not Num(c.scale,.75,1.30) then c.scale=1.0 end
    return c
end
Module.Config=Cfg

local function BgRGB()
    local hex=Cfg().bgColor or "0e1015"
    return tonumber(hex:sub(1,2),16)/255, tonumber(hex:sub(3,4),16)/255, tonumber(hex:sub(5,6),16)/255
end

local function MaxBagID()
    return (type(NUM_TOTAL_BAG_FRAMES)=="number" and NUM_TOTAL_BAG_FRAMES>=4) and NUM_TOTAL_BAG_FRAMES or 5
end

local function NumSlots(bag)
    local fn=(C_Container and C_Container.GetContainerNumSlots) or GetContainerNumSlots
    local n=fn and fn(bag)
    return (Public(n) and type(n)=="number" and n>0) and n or 0
end

local function SlotInfo(bag,slot)
    if C_Container and C_Container.GetContainerItemInfo then
        local info=C_Container.GetContainerItemInfo(bag,slot)
        if type(info)=="table" then
            return info.iconFileID, info.stackCount or 1, info.isLocked, info.quality, info.hyperlink, info.itemID
        end
        return nil
    elseif GetContainerItemInfo then
        local tex,cnt,locked,qual,_,_,link,_,_,id=GetContainerItemInfo(bag,slot)
        return tex, cnt or 1, locked, qual, link, id
    end
end

local function SlotCooldown(bag,slot)
    if C_Container and C_Container.GetContainerItemCooldown then
        return C_Container.GetContainerItemCooldown(bag,slot)
    elseif GetContainerItemCooldown then
        return GetContainerItemCooldown(bag,slot)
    end
end

local hiddenParent=nil
local function SyncBlizzardBags()
    if InCombatLockdown and InCombatLockdown() then return end
    local enabled=Cfg().enabled
    local defaultParent=ContainerFrameContainer or UIParent
    if enabled and not hiddenParent then
        hiddenParent=CreateFrame("Frame",nil,defaultParent)
        hiddenParent:SetAllPoints()
        hiddenParent:Hide()
    end
    local targetParent=enabled and hiddenParent or defaultParent
    if ContainerFrameCombinedBags then
        if enabled and ContainerFrameCombinedBags:IsShown() then ContainerFrameCombinedBags:Hide() end
        ContainerFrameCombinedBags:SetParent(targetParent)
    end
    for i=1,6 do
        local cf=_G["ContainerFrame"..i]
        if cf then
            if enabled and cf:IsShown() then cf:Hide() end
            cf:SetParent(targetParent)
        end
    end
end

local function HideBlizzardBags()
    SyncBlizzardBags()
end

local function ApplyBagAppearance()
    if not bagFrame then return end
    local c=Cfg()
    local r,g,b=BgRGB()
    bagFrame:SetBackdropColor(r,g,b,c.bgAlpha or .94)
    bagFrame:SetBackdropBorderColor(.88,.71,.34,.95) -- Signature gilded gold outer frame
    if not (InCombatLockdown and InCombatLockdown()) then
        bagFrame:SetScale(c.scale or 1.0)
    end
end

local activeCatFilter,catBtns="all",{}

local function MatchesCatAndQuery(itemID,link,tex,quality,query)
    if activeCatFilter~="all" then
        if not itemID then return false end
        local infoInstFn=(C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
        local _,_,_,_,_,classID=infoInstFn and infoInstFn(itemID)
        if type(classID)~="number" then
            local getInfo=(C_Item and C_Item.GetItemInfo) or GetItemInfo
            if getInfo then classID=select(12,getInfo(link or itemID)) end
        end
        local qual=Public(quality) and quality or (C_Item and C_Item.GetItemQualityByID and C_Item.GetItemQualityByID(itemID))
        if not Public(qual) then qual=nil end
        if activeCatFilter=="gear" then
            if classID~=2 and classID~=4 then return false end
        elseif activeCatFilter=="use" then
            if classID~=0 then return false end
        elseif activeCatFilter=="trade" then
            if classID~=5 and classID~=7 and classID~=9 then return false end
        elseif activeCatFilter=="quest" then
            if classID~=12 then return false end
        elseif activeCatFilter=="junk" then
            if qual~=0 then return false end
        end
    end
    if query and query~="" then
        if not tex then return false end
        local iname
        if link and Public(link) and type(link)=="string" then iname=link:match("%[(.-)%]") end
        if not iname and itemID and C_Item and C_Item.GetItemNameByID then
            local n=C_Item.GetItemNameByID(itemID)
            if Public(n) and type(n)=="string" then iname=n end
        end
        if not (iname and string.lower(iname):find(query,1,true)) then return false end
    end
    return true
end

local function SafeResetCursor()
    if ResetCursor and not (CursorHasItem and CursorHasItem()) then pcall(ResetCursor) end
end

local function HideOwnedTooltip(owner)
    if not GameTooltip or (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then return false end
    if GameTooltip:IsShown() and GameTooltip.IsOwned and GameTooltip:IsOwned(owner) then
        GameTooltip:Hide()
        return true
    end
    return false
end

local function UpdateSlotVisual(btn,bag,slot,query)
    local tex,count,locked,quality,link,itemID=SlotInfo(bag,slot)
    local isLocked=(Public(locked) and locked) and true or false
    btn.hasItem=(tex and itemID) and true or nil
    if SetItemButtonTexture then SetItemButtonTexture(btn,tex)
    elseif btn.icon then btn.icon:SetTexture(tex or "") end
    local iconTex=btn.icon or (btn.GetName and _G[btn:GetName().."IconTexture"])
    if iconTex then
        iconTex:SetDesaturated(isLocked)
        iconTex:SetVertexColor(1,1,1,1)
        iconTex:SetAlpha(1)
    end
    if btn.searchOverlay then btn.searchOverlay:Hide() end
    if btn.SearchOverlay then btn.SearchOverlay:Hide() end
    if btn.ItemContextOverlay then btn.ItemContextOverlay:Hide() end
    if btn.ExtendedSlot then btn.ExtendedSlot:Hide() end
    if btn.NewItemTexture then btn.NewItemTexture:Hide() end
    if btn.BattlepayItemTexture then btn.BattlepayItemTexture:Hide() end
    if btn.SetMatchesSearch then pcall(btn.SetMatchesSearch,btn,true) end
    if SetItemButtonCount then SetItemButtonCount(btn,count or 0) end
    if SetItemButtonDesaturated then SetItemButtonDesaturated(btn,isLocked) end

    -- Quality border highlight
    if btn.smyrnaBorder then
        if tex and quality and quality>=2 and ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[quality] then
            local qc=ITEM_QUALITY_COLORS[quality]
            btn.smyrnaBorder:SetBackdropBorderColor(qc.r,qc.g,qc.b,.92)
            btn.smyrnaBorder:Show()
        else
            btn.smyrnaBorder:Hide()
        end
    end

    -- Cooldown sweep
    local cd=btn.Cooldown or (btn.GetName and _G[btn:GetName().."Cooldown"])
    if cd and CooldownFrame_Set then
        local start,dur,enable=SlotCooldown(bag,slot)
        if Public(start) and Public(dur) and start and dur and dur>0 then
            CooldownFrame_Set(cd,start,dur,enable)
        else
            CooldownFrame_Set(cd,0,0,0)
        end
    end

    -- Search + category dim/highlight
    local match=true
    if (query and query~="") or activeCatFilter~="all" then
        match=MatchesCatAndQuery(itemID,link,tex,quality,query)
        btn:SetAlpha(match and 1.0 or .20)
        if not match and btn.smyrnaBorder then btn.smyrnaBorder:Hide() end
    else
        btn:SetAlpha(1.0)
    end
    -- Junk coin badge for gray vendor trash (Baganator/Leatrix style)
    local qGray=(itemID and tex and Public(quality) and quality==0) and true or false
    if qGray then
        if not btn.smyrnaJunkCoin then
            local coin=btn:CreateTexture(nil,"OVERLAY",nil,6)
            coin:SetSize(13,13); coin:SetPoint("TOPLEFT",2,-2)
            coin:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon")
            btn.smyrnaJunkCoin=coin
        end
        btn.smyrnaJunkCoin:Show()
    elseif btn.smyrnaJunkCoin then
        btn.smyrnaJunkCoin:Hide()
    end
    -- Equipment Manager set protection glow along bottom edge of slot (distinct color per set)
    local setLbl=itemID and equipSetLabel[itemID]
    if setLbl then
        local SET_COLORS={
            {.35,.85,1.0},{1.0,.82,.28},{.42,.92,.58},{.82,.52,1.0},
            {1.0,.48,.42},{.38,.92,.88},{1.0,.56,.82},{.72,.92,.38},
        }
        local h=0
        for idx=1,#setLbl do h=(h*31+setLbl:byte(idx))%8 end
        local sc=SET_COLORS[h+1]
        if not btn.smyrnaSetGlow then
            local g=btn:CreateTexture(nil,"OVERLAY",nil,5)
            g:SetHeight(3)
            g:SetPoint("BOTTOMLEFT",btn,"BOTTOMLEFT",2,2)
            g:SetPoint("BOTTOMRIGHT",btn,"BOTTOMRIGHT",-2,2)
            btn.smyrnaSetGlow=g
        end
        btn.smyrnaSetGlow:SetColorTexture(sc[1],sc[2],sc[3],.95)
        btn.smyrnaSetGlow:Show()
    elseif btn.smyrnaSetGlow then
        btn.smyrnaSetGlow:Hide()
    end
    if not btn.hasItem then
        btn:SetScript("OnUpdate",nil)
    end
    if GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) and GameTooltip.IsOwned and GameTooltip:IsOwned(btn) then
        if btn.hasItem then
            local onEnter=btn:GetScript("OnEnter")
            if onEnter and btn.GetRight and btn:GetRight() then pcall(onEnter,btn) end
        else
            GameTooltip:Hide()
            SafeResetCursor()
        end
    end
end

local function FormatCoins(copper)
    copper=math.max(0,math.floor(tonumber(copper) or 0))
    local g=math.floor(copper/10000)
    local s=math.floor((copper%10000)/100)
    local c=copper%100
    local parts={}
    if g>0 then parts[#parts+1]="|cffffffff"..g.."|r|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t" end
    if s>0 or g>0 then parts[#parts+1]="|cffffffff"..s.."|r|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t" end
    parts[#parts+1]="|cffffffff"..c.."|r|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t"
    return table.concat(parts," ")
end

local function UpdateMoneyAndCounts()
    if not bagFrame then return end
    local regTotal,regFree,reagTotal,reagFree=0,0,0,0
    local freeFn=C_Container and C_Container.GetContainerNumFreeSlots or GetContainerNumFreeSlots
    for bag=0,MaxBagID() do
        local n=NumSlots(bag)
        if n>0 then
            local fCount,bagType
            if freeFn then
                local ok,fc,bt=pcall(freeFn,bag)
                if ok and Public(fc) and type(fc)=="number" then fCount=fc; bagType=Public(bt) and bt or nil end
            end
            if not fCount then
                fCount=0
                for s=1,n do if not SlotInfo(bag,s) then fCount=fCount+1 end end
            end
            -- Bag 5 (Forever reagent bag) or any non-zero specialty/reagent bagType
            local isReagent=(bag>=5) or (type(bagType)=="number" and bagType~=0)
            if isReagent then
                reagTotal=reagTotal+n; reagFree=reagFree+fCount
            else
                regTotal=regTotal+n; regFree=regFree+fCount
            end
        end
    end
    local txt=string.format("|cffffd36a%d|r|cff9aa4b2/%d free|r",regFree,regTotal)
    if reagTotal>0 then
        txt=txt..string.format("  |cff556070·|r  |cff7cc4ff%d|r|cff9aa4b2/%d reag|r",reagFree,reagTotal)
    end
    bagFrame.slotsText:SetText(txt)
    local money=GetMoney and GetMoney() or 0
    if Public(money) and type(money)=="number" then
        bagFrame.moneyText:SetText(FormatCoins(money))
    end
end

local function UpdateBagBar()
    if not bagFrame or not bagFrame.bagBar then return end
    local c=Cfg()
    bagFrame.bagBar:SetShown(c.showBagBar and true or false)
    if not c.showBagBar then return end
    local maxB=MaxBagID()
    local bx=0
    for bag=0,maxB do
        local n=NumSlots(bag)
        local b=bagFilterBtns[bag]
        if n>0 then
            if not b then
                b=CreateFrame("Button",nil,bagFrame.bagBar,"BackdropTemplate")
                b:SetSize(24,24)
                Suite.StyleCard(b,.07,.08,.11)
                b.icon=b:CreateTexture(nil,"ARTWORK")
                b.icon:SetPoint("TOPLEFT",2,-2); b.icon:SetPoint("BOTTOMRIGHT",-2,2)
                b.icon:SetTexCoord(.08,.92,.08,.92)
                b:SetScript("OnClick",function(self)
                    hiddenBags[self.bagID]=not hiddenBags[self.bagID] or nil
                    Module.RefreshBags(true)
                end)
                b:SetScript("OnEnter",function(self)
                    if not GameTooltip or (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then return end
                    GameTooltip:SetOwner(self,"ANCHOR_TOP")
                    local label=(self.bagID==0) and "Backpack" or ("Bag "..self.bagID)
                    GameTooltip:SetText(label,1,.86,.48)
                    GameTooltip:AddLine(hiddenBags[self.bagID] and "Hidden — click to show" or "Click to toggle this bag",.75,.80,.88)
                    GameTooltip:Show()
                end)
                b:SetScript("OnLeave",function()
                    if GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then GameTooltip:Hide() end
                end)
                bagFilterBtns[bag]=b
            end
            b.bagID=bag
            local tex="Interface\\Buttons\\Button-Backpack-Up"
            if bag>0 then
                local invID=(C_Container and C_Container.ContainerIDToInventoryID and C_Container.ContainerIDToInventoryID(bag))
                    or (ContainerIDToInventoryID and ContainerIDToInventoryID(bag))
                if invID and GetInventoryItemTexture then
                    local itex=GetInventoryItemTexture("player",invID)
                    if Public(itex) and itex then tex=itex end
                end
            end
            b.icon:SetTexture(tex)
            b.icon:SetDesaturated(hiddenBags[bag] and true or false)
            b:SetAlpha(hiddenBags[bag] and .45 or 1.0)
            b:SetBackdropBorderColor(hiddenBags[bag] and .28 or .88, hiddenBags[bag] and .30 or .71, hiddenBags[bag] and .36 or .34, .9)
            b:ClearAllPoints(); b:SetPoint("LEFT",bagFrame.bagBar,"LEFT",bx,0)
            b:Show()
            bx=bx+28
        elseif b then
            b:Hide()
        end
    end
end

local function EnsureSlotButton(bag,slot)
    local bp=bagParents[bag]
    if not bp then
        bp=CreateFrame("Frame",nil,bagFrame)
        bp:SetAllPoints(bagFrame)
        bp:SetFrameStrata(bagFrame:GetFrameStrata())
        bp:SetFrameLevel(bagFrame:GetFrameLevel()+5)
        bp:SetID(bag)
        bagParents[bag]=bp
    end
    slotBtns[bag]=slotBtns[bag] or {}
    local btn=slotBtns[bag][slot]
    if btn then return btn end
    local btnName="SmyrnaBaggerBag"..bag.."Slot"..slot
    local ok,created=pcall(CreateFrame,"ItemButton",btnName,bp,"ContainerFrameItemButtonTemplate")
    if not ok or not created then
        created=CreateFrame("Button",btnName,bp,"ContainerFrameItemButtonTemplate")
    end
    created:SetID(slot)
    created:SetSize(37,37)
    created:SetFrameStrata(bagFrame:GetFrameStrata())
    created:SetFrameLevel(bagFrame:GetFrameLevel()+6)
    created:EnableMouse(true)
    -- Prevent Blizzard's ContainerFrameItemButtonMixin OnShow/OnEvent from darkening slots with searchOverlay
    created:SetScript("OnEvent",nil)
    created:SetScript("OnShow",nil)
    local origEnter=created:GetScript("OnEnter")
    created:SetScript("OnEnter",function(self,...)
        if not self.hasItem or not (self.GetRight and self:GetRight()) then
            HideOwnedTooltip(self)
            SafeResetCursor()
            return
        end
        if origEnter then origEnter(self,...) end
    end)
    local origDrag=created:GetScript("OnDragStart")
    created:SetScript("OnDragStart",function(self,...)
        if not self.hasItem then return end
        if origDrag then origDrag(self,...) end
    end)
    created:HookScript("OnLeave",function(self)
        self:SetScript("OnUpdate",nil)
        HideOwnedTooltip(self)
        SafeResetCursor()
    end)
    created:HookScript("OnHide",function(self)
        self:SetScript("OnUpdate",nil)
        if self.UnlockHighlight then pcall(self.UnlockHighlight,self) end
        HideOwnedTooltip(self)
        SafeResetCursor()
    end)
    if created.searchOverlay then created.searchOverlay:Hide() end
    if created.SearchOverlay then created.SearchOverlay:Hide() end
    if created.ItemContextOverlay then created.ItemContextOverlay:Hide() end
    if created.NewItemTexture then created.NewItemTexture:Hide() end
    if created.BattlepayItemTexture then created.BattlepayItemTexture:Hide() end
    -- Clean subtle obsidian slot backing + rarity border overlay (strictly non-mouse-blocking)
    local bg=created:CreateTexture(nil,"BACKGROUND",nil,-1)
    bg:SetAllPoints(); bg:SetColorTexture(.04,.05,.07,.85)
    local bdr=CreateFrame("Frame",nil,created,"BackdropTemplate")
    bdr:SetPoint("TOPLEFT",-1,1); bdr:SetPoint("BOTTOMRIGHT",1,-1)
    bdr:SetFrameLevel(created:GetFrameLevel()+2)
    bdr:EnableMouse(false)
    bdr:SetBackdrop({edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1.5})
    bdr:Hide()
    created.smyrnaBorder=bdr
    slotBtns[bag][slot]=created
    return created
end

local function EnsureBagFrame()
    if bagFrame then return bagFrame end
    local f=CreateFrame("Frame","SmyrnaBaggerFrame",UIParent,"BackdropTemplate")
    f:SetSize(420,320)
    f:SetFrameStrata("MEDIUM"); f:SetFrameLevel(40)
    f:SetClampedToScreen(true); f:EnableMouse(true)
    Suite.StylePanel(f,true)
    Suite.HeaderStrip(f,36)
    f:SetPoint("BOTTOMRIGHT",UIParent,"BOTTOMRIGHT",-24,96)

    local title=f:CreateFontString(nil,"OVERLAY","GameFontNormal")
    title:SetPoint("TOPLEFT",12,-11); title:SetText("Smyrna Bagger"); title:SetTextColor(1,.86,.48)

    local closeBtn=Suite.CloseButton(f)
    closeBtn:ClearAllPoints(); closeBtn:SetPoint("TOPRIGHT",-6,-6)
    closeBtn:SetScript("OnClick",function() Module.CloseBags() end)

    local gearBtn=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    gearBtn:SetSize(56,20); gearBtn:SetPoint("RIGHT",closeBtn,"LEFT",-5,0); gearBtn:SetText("Style"); Suite.StyleButton(gearBtn)
    gearBtn:SetScript("OnClick",function() Module.Open() end)

    local junkBtn=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
    junkBtn:SetSize(66,20); junkBtn:SetPoint("RIGHT",gearBtn,"LEFT",-4,0); junkBtn:SetText("Sell Junk"); Suite.StyleButton(junkBtn)
    junkBtn:SetScript("OnClick",function()
        if not (MerchantFrame and MerchantFrame:IsShown()) then return end
        if CursorHasItem and CursorHasItem() then return end
        local sold=0
        for bag=0,4 do
            local n=C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bag) or 0
            for slot=1,n do
                local info=C_Container and C_Container.GetContainerItemInfo and C_Container.GetContainerItemInfo(bag,slot)
                if info and not info.isLocked and info.quality==0 and C_Container.UseContainerItem then
                    pcall(C_Container.UseContainerItem,bag,slot)
                    sold=sold+1
                end
            end
        end
        if sold>0 then
            SafeResetCursor()
            if DEFAULT_CHAT_FRAME then
                DEFAULT_CHAT_FRAME:AddMessage("|cffdfb66bSmyrna Bagger:|r Sold "..sold.." gray junk item(s).")
            end
        end
    end)
    junkBtn:Hide()
    f.junkBtn=junkBtn

    -- Search bar
    local search=CreateFrame("EditBox",nil,f,"InputBoxTemplate")
    search:SetHeight(20); search:SetPoint("TOPLEFT",14,-42); search:SetPoint("TOPRIGHT",-14,-42)
    search:SetAutoFocus(false)
    local ph=search:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
    ph:SetPoint("LEFT",6,0); ph:SetText("Search bags...")
    search:SetScript("OnTextChanged",function(self)
        searchText=string.lower((self:GetText() or ""):gsub("^%s+",""):gsub("%s+$",""))
        ph:SetShown(searchText=="")
        Module.RefreshBags(false)
    end)
    search:SetScript("OnEscapePressed",function(self) self:SetText(""); self:ClearFocus() end)
    f.search=search

    -- Baganator-style category filter pills
    local catSpec={{"all","All",30},{"gear","Gear",38},{"use","Use",34},{"trade","Trade",42},{"quest","Quest",42},{"junk","Junk",38}}
    local cx=12
    for idx,sp in ipairs(catSpec) do
        local key,lbl,w=sp[1],sp[2],sp[3]
        local b=CreateFrame("Button",nil,f,"UIPanelButtonTemplate")
        b:SetSize(w,18); b:SetPoint("TOPLEFT",cx,-66); b:SetText(lbl); Suite.StyleButton(b)
        b:SetScript("OnClick",function()
            activeCatFilter=key
            for k,btn in pairs(catBtns) do Suite.SetButtonSelected(btn,k==activeCatFilter) end
            Module.RefreshBags(false)
        end)
        Suite.SetButtonSelected(b,key==activeCatFilter)
        catBtns[key]=b
        cx=cx+w+3
    end

    -- Bag filter bar + iconic broom/sweeper Sort button right beside the bags (like Bagnon)
    local bagBar=CreateFrame("Frame",nil,f)
    bagBar:SetHeight(26); bagBar:SetPoint("TOPLEFT",12,-90); bagBar:SetPoint("TOPRIGHT",-12,-90)
    f.bagBar=bagBar

    local sortBtn=CreateFrame("Button",nil,bagBar,"BackdropTemplate")
    sortBtn:SetSize(24,24); sortBtn:SetPoint("RIGHT",bagBar,"RIGHT",0,0)
    Suite.StyleCard(sortBtn,.07,.08,.11)
    sortBtn:SetBackdropBorderColor(.88,.71,.34,.9)
    local broom=sortBtn:CreateTexture(nil,"ARTWORK")
    broom:SetPoint("TOPLEFT",2,-2); broom:SetPoint("BOTTOMRIGHT",-2,2)
    if broom.SetAtlas and pcall(broom.SetAtlas,broom,"bags-button-autosort-up") then
        -- Blizzard's native bag sweeper broom atlas
    else
        broom:SetTexture("Interface\\Icons\\INV_Misc_Broom_01")
        broom:SetTexCoord(.08,.92,.08,.92)
    end
    sortBtn:SetHighlightTexture("Interface\\Buttons\\WHITE8X8")
    local shl=sortBtn:GetHighlightTexture(); if shl then shl:SetVertexColor(.95,.78,.36,.24) end
    sortBtn:SetScript("OnClick",function()
        if InCombatLockdown and InCombatLockdown() then return end
        if C_Container and C_Container.SortBags then pcall(C_Container.SortBags)
        elseif SortBags then pcall(SortBags) end
    end)
    sortBtn:SetScript("OnEnter",function(self)
        if not GameTooltip or (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then return end
        GameTooltip:SetOwner(self,"ANCHOR_TOP")
        GameTooltip:SetText("Sort Bags",1,.86,.48)
        GameTooltip:AddLine("Click to clean up and sort your bags.",.75,.80,.88)
        GameTooltip:Show()
    end)
    sortBtn:SetScript("OnLeave",function()
        if GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then GameTooltip:Hide() end
    end)

    -- Footer: free slots + gold
    local footerDiv=f:CreateTexture(nil,"ARTWORK")
    footerDiv:SetPoint("BOTTOMLEFT",10,28); footerDiv:SetPoint("BOTTOMRIGHT",-10,28); footerDiv:SetHeight(1)
    Suite.ApplyGradient(footerDiv,"HORIZONTAL",.93,.77,.40,.35,.93,.77,.40,.08)

    local slotsText=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    slotsText:SetPoint("BOTTOMLEFT",12,9); slotsText:SetJustifyH("LEFT")
    f.slotsText=slotsText

    local moneyText=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
    moneyText:SetPoint("BOTTOMRIGHT",-12,9); moneyText:SetJustifyH("RIGHT")
    f.moneyText=moneyText

    f:SetScript("OnHide",function(self)
        if self.search and self.search.ClearFocus then self.search:ClearFocus() end
        if GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) and GameTooltip:IsShown() then
            local owner=GameTooltip.GetOwner and GameTooltip:GetOwner()
            if owner and (owner==self or (owner.GetParent and owner:GetParent() and owner:GetParent():GetParent()==self)) then
                GameTooltip:Hide()
            end
        end
        SafeResetCursor()
    end)
    f:Hide()
    bagFrame=f
    ApplyBagAppearance()
    return f
end

function Module.RefreshBags(relayout,allowHidden)
    if not bagFrame or (not allowHidden and not bagFrame:IsShown()) then return end
    ApplyBagAppearance()
    UpdateBagBar()
    local c=Cfg()
    local cols=math.max(6,math.min(16,math.floor(c.columns or 10)))
    local inCombat=InCombatLockdown and InCombatLockdown()
    if relayout and inCombat then pendingLayout=true; relayout=false end

    local PAD_X,SLOT,GAP=12,37,4
    local topY=c.showBagBar and 120 or 90
    if bagFrame.junkBtn then bagFrame.junkBtn:SetShown(MerchantFrame and MerchantFrame:IsShown() and true or false) end
    local idx=0
    local maxB=MaxBagID()
    for bag=0,maxB do
        local n=NumSlots(bag)
        local hideThis=hiddenBags[bag] and true or false
        local btns=slotBtns[bag]
        if n>0 and not hideThis then
            for slot=1,n do
                local btn=(btns and btns[slot]) or (not inCombat and EnsureSlotButton(bag,slot))
                if btn then
                    if relayout or not btn.placed then
                        local col=idx%cols
                        local row=math.floor(idx/cols)
                        if not btn.placed or btn.placedCol~=col or btn.placedRow~=row or btn.placedTopY~=topY then
                            btn:ClearAllPoints()
                            btn:SetPoint("TOPLEFT",bagFrame,"TOPLEFT",PAD_X+col*(SLOT+GAP),-(topY+row*(SLOT+GAP)))
                            btn.placed=true; btn.placedCol=col; btn.placedRow=row; btn.placedTopY=topY
                        end
                    end
                    if not inCombat then btn:Show() end
                    UpdateSlotVisual(btn,bag,slot,searchText)
                end
                idx=idx+1
            end
        end
        if btns and not inCombat then
            for slot,btn in pairs(btns) do
                if hideThis or slot>n then
                    btn:Hide(); btn:SetScript("OnUpdate",nil)
                    btn.placed=nil; btn.placedCol=nil; btn.placedRow=nil; btn.placedTopY=nil
                end
            end
        end
    end

    if (relayout or not bagFrame.sized) and not inCombat then
        local rows=math.max(1,math.ceil(math.max(1,idx)/cols))
        local w=PAD_X*2+cols*SLOT+(cols-1)*GAP
        local h=topY+rows*SLOT+(rows-1)*GAP+38
        if not bagFrame.sized or bagFrame.lastW~=w or bagFrame.lastH~=h then
            bagFrame:SetSize(w,h)
            bagFrame.sized=true; bagFrame.lastW=w; bagFrame.lastH=h
        end
    end
    UpdateMoneyAndCounts()
end

local function PrewarmBags()
    if not Cfg().enabled then return end
    if InCombatLockdown and InCombatLockdown() then return end
    EnsureBagFrame()
    Module.RefreshBags(true,true)
end

function Module.OpenBags()
    if not Cfg().enabled then return end
    if InCombatLockdown and InCombatLockdown() then
        -- Allow opening pre-allocated bags during combat without creating or moving frames under lockdown.
        if bagFrame and bagFrame.sized then
            bagFrame:Show()
            Module.RefreshBags(false)
        end
        return
    end
    EnsureBagFrame()
    HideBlizzardBags()
    bagFrame:Show()
    Module.RefreshBags(true)
end

function Module.CloseBags()
    if bagFrame and bagFrame:IsShown() then bagFrame:Hide() end
end

function Module.ToggleBags()
    if not Cfg().enabled then return end
    if bagFrame and bagFrame:IsShown() then Module.CloseBags() else Module.OpenBags() end
end

local lastToggleAt=0
local function InstallBagHooks()
    if hooksInstalled or not hooksecurefunc then return end
    hooksInstalled=true
    local function OnOpen()
        if not Cfg().enabled then return end
        lastToggleAt=GetTime()
        Module.OpenBags()
    end
    local function OnClose()
        if not Cfg().enabled then return end
        lastToggleAt=GetTime()
        Module.CloseBags()
    end
    local function OnToggle()
        if not Cfg().enabled then return end
        local now=GetTime()
        if now-lastToggleAt<0.08 then return end -- Prevent ToggleBackpack -> ToggleBag(0) double-toggle!
        lastToggleAt=now
        if bagFrame and bagFrame:IsShown() then Module.CloseBags() else Module.OpenBags() end
    end
    if ToggleAllBags then hooksecurefunc("ToggleAllBags",OnToggle) end
    if OpenAllBags then hooksecurefunc("OpenAllBags",OnOpen) end
    if CloseAllBags then hooksecurefunc("CloseAllBags",OnClose) end
    if ToggleBackpack then hooksecurefunc("ToggleBackpack",OnToggle) end
    if OpenBackpack then hooksecurefunc("OpenBackpack",OnOpen) end
    if CloseBackpack then hooksecurefunc("CloseBackpack",OnClose) end
    if ToggleBag then hooksecurefunc("ToggleBag",function(bag)
        if Cfg().enabled and type(bag)=="number" and bag>=0 and bag<=MaxBagID() then OnToggle() end
    end) end
    -- Keep world/player GameTooltips from overlapping the open Bagger window
    if GameTooltip_SetDefaultAnchor then
        hooksecurefunc("GameTooltip_SetDefaultAnchor",function(tooltip,parent)
            if tooltip==GameTooltip and bagFrame and bagFrame:IsShown() and not (tooltip.IsForbidden and tooltip:IsForbidden()) then
                tooltip:ClearAllPoints()
                tooltip:SetPoint("BOTTOMRIGHT",bagFrame,"BOTTOMLEFT",-8,0)
            end
        end)
    end
end

-- ============================================================
-- Settings UI in Smyrna Suite Hub (/bagger)
-- ============================================================
function Module.Open()
    if not settingsWin then
        checks={}
        settingsWin=CreateFrame("Frame","SmyrnaBaggerWindow",UIParent,"BackdropTemplate")
        settingsWin:SetSize(760,460); settingsWin:SetPoint("CENTER"); settingsWin:SetFrameStrata("DIALOG"); settingsWin:SetClampedToScreen(true)
        settingsWin:SetMovable(true); settingsWin:EnableMouse(true); settingsWin:RegisterForDrag("LeftButton")
        settingsWin:SetScript("OnDragStart",function(self) if not (InCombatLockdown and InCombatLockdown()) then self:StartMoving() end end)
        settingsWin:SetScript("OnDragStop",function(self) self:StopMovingOrSizing() end)
        Suite.StylePanel(settingsWin,true)
        local close=Suite.CloseButton(settingsWin); settingsWin.SuiteCloseButton=close
        local title=settingsWin:CreateFontString(nil,"OVERLAY","GameFontNormalLarge"); title:SetPoint("TOPLEFT",16,-14); title:SetText("Smyrna Bagger"); title:SetTextColor(1,.86,.48)
        local sub=settingsWin:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); sub:SetPoint("TOPLEFT",16,-36); sub:SetText("Unified gilded all-in-one bag window with live search, bag filters, sort, and customizable background color."); sub:SetTextColor(.70,.75,.84)

        local card=CreateFrame("Frame",nil,settingsWin,"BackdropTemplate"); card:SetSize(728,248); card:SetPoint("TOPLEFT",16,-62); Suite.StyleCard(card)
        Suite.OptionSection(card,"Bag Layout & Appearance",14,-12,700)

        local function AddCheck(key,text,tip,x,y)
            local cb=CreateFrame("CheckButton",nil,card,"UICheckButtonTemplate"); cb:SetPoint("TOPLEFT",x,y)
            local lbl=cb:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); lbl:SetPoint("LEFT",cb,"RIGHT",2,0); lbl:SetText(text)
            cb:SetScript("OnClick",function(self)
                Cfg()[key]=self:GetChecked() and true or false
                if key=="enabled" then SyncBlizzardBags(); if not Cfg().enabled then Module.CloseBags() end end
                Module.RefreshBags(true)
            end)
            Suite.AttachTooltip(cb,text,tip,lbl)
            checks[key]=cb
        end
        AddCheck("enabled","Enable Bagger","Replace Blizzard's default bags with Smyrna Bagger's unified gilded bag window.",12,-34)
        AddCheck("showBagBar","Show bag bar","Display individual bag icons at the top of Bagger so you can toggle each bag on or off.",180,-34)

        local openBtn=CreateFrame("Button",nil,card,"UIPanelButtonTemplate"); openBtn:SetSize(124,24); openBtn:SetPoint("TOPRIGHT",-16,-34); openBtn:SetText("Toggle Bags"); Suite.StyleButton(openBtn)
        openBtn:SetScript("OnClick",function() Module.ToggleBags() end)

        local colLbl=card:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); colLbl:SetPoint("TOPLEFT",16,-78); colLbl:SetTextColor(.93,.77,.40)
        local colSlider=Suite.CreateSlider(card,206,6,16); colSlider:SetPoint("TOPLEFT",16,-98)
        colSlider:SetScript("OnValueChanged",function(_,v)
            local n=math.floor((v or 10)+.5); Cfg().columns=n
            colLbl:SetText("Columns per row: "..n)
            Module.RefreshBags(true)
        end)

        local opLbl=card:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); opLbl:SetPoint("TOPLEFT",254,-78); opLbl:SetTextColor(.93,.77,.40)
        local opSlider=Suite.CreateSlider(card,206,40,100); opSlider:SetPoint("TOPLEFT",254,-98)
        opSlider:SetScript("OnValueChanged",function(_,v)
            local pct=math.floor((v or 94)+.5); Cfg().bgAlpha=pct/100
            opLbl:SetText("Background opacity: "..pct.."%")
            ApplyBagAppearance()
        end)

        local scLbl=card:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); scLbl:SetPoint("TOPLEFT",492,-78); scLbl:SetTextColor(.93,.77,.40)
        local scSlider=Suite.CreateSlider(card,206,75,130); scSlider:SetPoint("TOPLEFT",492,-98)
        scSlider:SetScript("OnValueChanged",function(_,v)
            local pct=math.floor((v or 100)+.5); Cfg().scale=pct/100
            scLbl:SetText("Bag scale: "..pct.."%")
            ApplyBagAppearance()
        end)

        local bgLbl=card:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall"); bgLbl:SetPoint("TOPLEFT",16,-146); bgLbl:SetTextColor(.93,.77,.40); bgLbl:SetText("Background color:")
        local bgBtn=CreateFrame("Button",nil,card,"UIPanelButtonTemplate"); bgBtn:SetSize(142,24); bgBtn:SetPoint("LEFT",bgLbl,"RIGHT",10,0); bgBtn:SetText("    Pick color"); Suite.StyleButton(bgBtn)
        local swatch=bgBtn:CreateTexture(nil,"OVERLAY",nil,2); swatch:SetSize(12,12); swatch:SetPoint("LEFT",8,0)
        local function SyncSwatch() swatch:SetColorTexture(BgRGB()) end
        local function SetBgRGB(r,g,b)
            if not Num(r,0,1) or not Num(g,0,1) or not Num(b,0,1) then return end
            Cfg().bgColor=string.format("%02x%02x%02x",math.floor(r*255+.5),math.floor(g*255+.5),math.floor(b*255+.5))
            SyncSwatch(); ApplyBagAppearance()
        end
        bgBtn:SetScript("OnClick",function()
            local picker=ColorPickerFrame; if not picker or not picker.GetColorRGB then return end
            local r,g,b=BgRGB()
            local function Apply() SetBgRGB(picker:GetColorRGB()) end
            local function Cancel() SetBgRGB(r,g,b) end
            if picker.SetFrameStrata then picker:SetFrameStrata("FULLSCREEN_DIALOG") end
            if picker.SetupColorPickerAndShow then
                picker:SetupColorPickerAndShow({r=r,g=g,b=b,hasOpacity=false,swatchFunc=Apply,cancelFunc=Cancel})
            elseif picker.SetColorRGB then
                picker:Hide(); picker.func=nil; picker.cancelFunc=nil
                picker:SetColorRGB(r,g,b); picker.hasOpacity=false; picker.func=Apply; picker.cancelFunc=Cancel
                picker:Show()
            end
            if picker.Raise then picker:Raise() end
        end)

        local resetBtn=CreateFrame("Button",nil,card,"UIPanelButtonTemplate"); resetBtn:SetSize(118,24); resetBtn:SetPoint("LEFT",bgBtn,"RIGHT",8,0); resetBtn:SetText("Reset defaults"); Suite.StyleButton(resetBtn)
        resetBtn:SetScript("OnClick",function()
            local c=Cfg(); c.bgColor="0e1015"; c.bgAlpha=.94; c.columns=10; c.scale=1.0; c.pos=nil
            if syncControlsFn then syncControlsFn() end
            ApplyBagAppearance(); Module.RefreshBags(true)
        end)

        local note=card:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        note:SetPoint("TOPLEFT",16,-192); note:SetWidth(696); note:SetJustifyH("LEFT"); note:SetTextColor(.74,.80,.88)
        note:SetText("Tip: You can disable third-party Bagnon / BagBrother once Smyrna Bagger is active. All right-click actions, Workshop & Market tooltips, Shift+click links, and Ctrl+click previews work natively.")

        syncControlsFn=function()
            local c=Cfg()
            for k,cb in pairs(checks) do cb:SetChecked(c[k] and true or false) end
            colSlider:SetValue(c.columns or 10); colLbl:SetText("Columns per row: "..(c.columns or 10))
            local opPct=math.floor(((c.bgAlpha or .94)*100)+.5)
            opSlider:SetValue(opPct); opLbl:SetText("Background opacity: "..opPct.."%")
            local scPct=math.floor(((c.scale or 1.0)*100)+.5)
            scSlider:SetValue(scPct); scLbl:SetText("Bag scale: "..scPct.."%")
            SyncSwatch()
        end
        settingsWin:SetScript("OnShow",syncControlsFn)
        UISpecialFrames[#UISpecialFrames+1]="SmyrnaBaggerWindow"
    end
    settingsWin:Show()
    if syncControlsFn then syncControlsFn() end
    return settingsWin
end

local driver=CreateFrame("Frame")
driver:RegisterEvent("PLAYER_LOGIN")
driver:RegisterEvent("BAG_UPDATE_DELAYED")
driver:RegisterEvent("BAG_UPDATE_COOLDOWN")
driver:RegisterEvent("ITEM_LOCK_CHANGED")
driver:RegisterEvent("PLAYER_MONEY")
driver:RegisterEvent("PLAYER_REGEN_ENABLED")
pcall(driver.RegisterEvent,driver,"MERCHANT_SHOW")
pcall(driver.RegisterEvent,driver,"MERCHANT_CLOSED")
pcall(driver.RegisterEvent,driver,"EQUIPMENT_SETS_CHANGED")
driver:SetScript("OnEvent",function(self,event)
    if event=="PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        RebuildEquipmentSets()
        HookEquipSetTooltips()
        InstallBagHooks()
        SyncBlizzardBags()
        PrewarmBags()
    elseif event=="MERCHANT_SHOW" or event=="MERCHANT_CLOSED" then
        if bagFrame and bagFrame.junkBtn then
            bagFrame.junkBtn:SetShown(event=="MERCHANT_SHOW" or (MerchantFrame and MerchantFrame:IsShown() and true or false))
        end
        if event=="MERCHANT_CLOSED" then SafeResetCursor() end
    elseif event=="EQUIPMENT_SETS_CHANGED" then
        RebuildEquipmentSets()
        if bagFrame and bagFrame:IsShown() then Module.RefreshBags(false) end
    elseif event=="PLAYER_REGEN_ENABLED" then
        if pendingLayout then pendingLayout=false; Module.RefreshBags(true) end
    elseif bagFrame and bagFrame:IsShown() then
        if event=="PLAYER_MONEY" then UpdateMoneyAndCounts()
        else Module.RefreshBags(event=="BAG_UPDATE_DELAYED") end
    end
end)

SLASH_SMYRNABAGGER1="/bagger"
SLASH_SMYRNABAGGER2="/sbags"
SlashCmdList.SMYRNABAGGER=function(arg)
    if arg and string.lower(arg)=="options" then Module.Open() else Module.ToggleBags() end
end

Suite.Loaded[name]=true
Module.Perf=function() if Suite.Memory then Suite.Memory() end end
