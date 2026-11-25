local _,Suite=...
local name="SmyrnaWorkshop"
Suite.Versions[name]="0.3.0"
if Suite.Config.features[name]==false then return end
local Module={}
Suite.Modules[name]=Module

-- Internal module source: Core.lua
do local function chunk(...)
local _,NS=...
local index,counts={},{}
local decodedRecipes={}
local usesCache,usesRing,usesCursor,USES_CAP={},{},1,64
local visualCache,visualRing,visualCursor,VISUAL_CAP={},{},1,512
local references={}
NS.References=references;NS.Index=index
NS.ReferenceLoaded={}
local unavailable={}
local loadingReferences,referenceDirty=false,false
local function PackRecipe(r)
 local mats={};for _,m in ipairs(r.mats) do mats[#mats+1]=m[1]..':'..m[2] end
 return table.concat({r.spell or '',r.profession,r.name,table.concat(mats,',')},'\t')
end
local function ReadRecipe(value,cacheKey)
 if type(value)=='table' then return value end
 if type(value)~='string' then return end
 if cacheKey and decodedRecipes[cacheKey] then return decodedRecipes[cacheKey] end
 local spell,profession,name,body=value:match('^(%d*)\t([^\t]*)\t([^\t]*)\t(.*)$')
 if not profession then return end
 local mats={};for id,n in body:gmatch('(%d+):(%d+)') do mats[#mats+1]={tonumber(id),tonumber(n)} end
 local row={spell=tonumber(spell),profession=profession,name=name,mats=mats,learned=true}
 if cacheKey then decodedRecipes[cacheKey]=row end
 return row
end
local function ReadRef(value)
 if type(value)=='table' then return value end
 if type(value)~='string' then return end
 local spell,profession,name,skill,body=value:match('^(%d*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$')
 if not profession then return end
 local mats={};for id,n in body:gmatch('(%d+):(%d+)') do mats[#mats+1]={tonumber(id),tonumber(n)} end
 return {spell=tonumber(spell),profession=profession,name=name,skill=tonumber(skill),mats=mats}
end
NS.PackRecipe,NS.ReadRecipe=PackRecipe,ReadRecipe
function NS.Init()
    if type(SmyrnaWorkshopDB)~="table" then SmyrnaWorkshopDB={} end
    NS.DB=SmyrnaWorkshopDB
    NS.DB.recipes=NS.DB.recipes or {}
    NS.DB.settings=NS.DB.settings or {}
    for key,value in pairs({enabled=true,ingredients=true,readyOnly=false,icon=true}) do
        if type(NS.DB.settings[key])~="boolean" then NS.DB.settings[key]=value end
    end
    NS.Reindex()
end
function NS.Public(v) return not issecretvalue or not issecretvalue(v) end
function NS.ID(link)
    if not NS.Public(link) or type(link)~="string" then return end
    return tonumber(link:match("item:(%d+)"))
end
function NS.Reindex()
    wipe(index)
    wipe(decodedRecipes)
    wipe(usesCache);wipe(usesRing);usesCursor=1
    local keys,seen={},{}
    for key,value in pairs(NS.DB.recipes) do
        if type(value)=='table' then NS.DB.recipes[key]=PackRecipe(value) end
        keys[#keys+1]=key
    end;table.sort(keys)
    NS.recipeCount=#keys
    local function Add(r,key)
        for _,v in ipairs(r.mats) do
            local list=index[v[1]];if not list then list={};index[v[1]]=list end
            list[#list+1]=key or r
        end
    end
    for _,key in ipairs(keys) do
        local r=ReadRecipe(NS.DB.recipes[key],key)
        if r then
            seen[r.spell or (r.profession..":"..r.name)]=true;seen[r.profession..":"..r.name]=true;Add(r,key)
        end
    end
    for _,r in ipairs(references) do
        if type(r)=="string" then
            local spell,profession,rname,_,matStr=r:match("^(%d*)\t([^\t]*)\t([^\t]*)\t([^\t]*)\t(.*)$")
            local spellNum=spell and tonumber(spell)
            if profession and not (spellNum and seen[spellNum]) and not seen[profession..":"..rname] then
                for matID in matStr:gmatch("(%d+):%d+") do
                    local id=tonumber(matID)
                    if id then
                        local list=index[id];if not list then list={};index[id]=list end
                        if list[#list]~=r then list[#list+1]=r end
                    end
                end
            end
        elseif not seen[r.spell] and not seen[r.profession..":"..r.name] then
            Add(r)
        end
    end
    wipe(counts)
end
function NS.Save(key,profession,name,mats,spell)
    if type(name)~="string" or #mats==0 or #mats>16 then return end
    if not NS.DB.recipes[key] then
        if NS.recipeCount>=3000 then return end
        NS.recipeCount=NS.recipeCount+1
    end
    local old=ReadRecipe(NS.DB.recipes[key],key)
    local same=old and old.profession==profession and old.name==name and old.spell==spell and #old.mats==#mats
    if same then for i,v in ipairs(mats) do if old.mats[i][1]~=v[1] or old.mats[i][2]~=v[2] then same=false;break end end end
    if same then return false end
    NS.DB.recipes[key]=PackRecipe({profession=profession,name=name,mats=mats,spell=spell})
    decodedRecipes[key]=nil
    NS.ScanDirty=true;return true
end
function NS.Invalidate() wipe(counts) end
function NS.Count(id)
    if counts[id]==nil then
        local fn=C_Item and C_Item.GetItemCount or GetItemCount
        local value=fn and fn(id,false,false) or 0
        counts[id]=NS.Public(value) and type(value)=="number" and value or 0
    end
    return counts[id]
end
function NS.RegisterReference(rows)
    for _,r in ipairs(rows) do references[#references+1]=r end
    if loadingReferences then referenceDirty=true else NS.Reindex() end
end
function NS.EnsureReference(id)
    local packs=NS.ReferenceManifest and NS.ReferenceManifest[id]
    if not packs then return end
    local load=(C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    if not load then return end
    if InCombatLockdown and InCombatLockdown() then
        for _,slug in ipairs(packs) do if not NS.ReferenceLoaded[slug] and not unavailable[slug] then return "Reference available after combat" end end
    end
    local notice
    loadingReferences=true
    for _,slug in ipairs(packs) do
        if unavailable[slug] then notice="Some recipe references are disabled or unavailable"
        elseif not NS.ReferenceLoaded[slug] then
            local ok=Suite.LoadReference("recipe",slug)
            if ok then NS.ReferenceLoaded[slug]=true else unavailable[slug]=true;notice="Some recipe references are disabled or unavailable" end
        end
    end
    loadingReferences=false
    if referenceDirty then referenceDirty=false;NS.Reindex() end
    return notice
end
function NS.HasUses(id) return index[id]~=nil end
function NS.Uses(id)
 if usesCache[id] then return usesCache[id] end
 if not index[id] then return end
 local rows={}
 for _,value in ipairs(index[id]) do
  local row
  if type(value)=='table' then row=value
  elseif NS.DB.recipes[value] then row=ReadRecipe(NS.DB.recipes[value],value)
  else row=ReadRef(value) end
  if row then rows[#rows+1]=row end
 end
 local evicted=usesRing[usesCursor]
 if evicted then usesCache[evicted]=nil end
 usesRing[usesCursor]=id;usesCursor=usesCursor%USES_CAP+1
 usesCache[id]=rows
 return rows
end
function NS.ClearCaches()
 wipe(usesCache);wipe(usesRing);usesCursor=1
 wipe(decodedRecipes);wipe(counts)
 wipe(visualCache);wipe(visualRing);visualCursor=1
end
function NS.Known(r)
    if r.learned then return true end
    if r.spell then
        local fn=Suite.KnowsSpell or (C_SpellBook and C_SpellBook.IsSpellKnown) or IsPlayerSpell or IsSpellKnown
        if fn then return fn(r.spell) end
    end
end
function NS.Ready(r)
    local times=math.huge
    for _,v in ipairs(r.mats) do if v[2] and v[2]>0 then times=math.min(times,math.floor(NS.Count(v[1])/v[2])) end end
    return times==math.huge and 0 or times
end
local function SortRecipes(rows)
    local rank={}
    -- Resolve native learned state once per recipe, never inside the comparator.
    for _,r in ipairs(rows) do local known=NS.Known(r);rank[r]=known==true and 0 or known==false and 1 or 2 end
    table.sort(rows,function(a,b)
        if a.profession~=b.profession then return a.profession<b.profession end
        if rank[a]~=rank[b] then return rank[a]<rank[b] end
        return a.name<b.name
    end)
end
function NS.ItemRecipes(id)
    local rows,seen={},{}
    for _,recipe in ipairs(NS.Uses(id) or {}) do if not seen[recipe] then rows[#rows+1]=recipe;seen[recipe]=true end end
    SortRecipes(rows)
    return rows
end
function NS.ItemName(id)
    local fn=C_Item and C_Item.GetItemInfo or GetItemInfo
    local name=fn and fn(id)
    if NS.Public(name) and type(name)=="string" then return name end
    local gear=Suite.Equipment and Suite.Equipment.records and Suite.Equipment.Get(id,true)
    return gear and gear.name or ("Item #"..id)
end
function NS.ItemVisual(id)
    if not NS.Public(id) or type(id)~="number" then return nil,nil end
    local get=C_Item and C_Item.GetItemInfo or GetItemInfo
    local quality,icon
    if get then
        local name,_,q,_,_,_,_,_,_,tex=get(id)
        if NS.Public(name) and type(name)=="string" then
            if NS.Public(q) and type(q)=="number" then quality=q end
            if NS.Public(tex) and tex then icon=tex end
        end
    end
    if not icon and C_Item and C_Item.GetItemIconByID then
        local tex=C_Item.GetItemIconByID(id)
        if NS.Public(tex) and tex then icon=tex end
    end
    if quality==nil and Suite.Equipment and Suite.Equipment.records then
        local gear=Suite.Equipment.Get(id,true)
        if gear and type(gear.quality)=="number" then quality=gear.quality end
    end
    return icon,quality
end
function NS.RecipeVisual(r,pendingItems)
    local key=r.spell or (r.profession..":"..r.name)
    local cached=visualCache[key]
    if cached and (cached.resolved or (cached.quality~=nil and cached.icon)) then return cached.icon,cached.quality,cached.itemID end
    local icon,quality,itemID=cached and cached.icon,cached and cached.quality,cached and cached.itemID
    local waiting=false
    if r.spell and not itemID and C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic then
        local ok,schema=pcall(C_TradeSkillUI.GetRecipeSchematic,r.spell,false)
        if ok and type(schema)=="table" then
            if NS.Public(schema.outputItemID) and type(schema.outputItemID)=="number" and schema.outputItemID>0 then itemID=schema.outputItemID end
            if not icon and NS.Public(schema.icon) and schema.icon then icon=schema.icon end
        end
    end
    if itemID then
        local iIcon,iQuality=NS.ItemVisual(itemID)
        if iIcon then icon=iIcon end
        if iQuality~=nil then quality=iQuality
        elseif pendingItems then
            waiting=true
            pendingItems[itemID]=true
            if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(itemID) end
        end
    elseif type(r.name)=="string" and r.name~="" then
        local get=C_Item and C_Item.GetItemInfo or GetItemInfo
        if get then
            local iname,_,q,_,_,_,_,_,_,tex=get(r.name)
            if NS.Public(iname) and type(iname)=="string" then
                if NS.Public(q) and type(q)=="number" then quality=q end
                if not icon and NS.Public(tex) and tex then icon=tex end
            end
        end
    end
    if not icon and r.spell then
        local spTex=(C_Spell and C_Spell.GetSpellTexture) or GetSpellTexture
        if spTex then local ok,tex=pcall(spTex,r.spell);if ok and NS.Public(tex) and tex then icon=tex end end
    end
    local entry={icon=icon or "Interface\\Icons\\INV_Misc_QuestionMark",quality=quality,itemID=itemID,resolved=not waiting}
    if not visualCache[key] then
        local evicted=visualRing[visualCursor]
        if evicted then visualCache[evicted]=nil end
        visualRing[visualCursor]=key;visualCursor=visualCursor%VISUAL_CAP+1
    end
    visualCache[key]=entry
    return entry.icon,entry.quality,entry.itemID
end
function NS.ClearVisualCache() wipe(visualCache);wipe(visualRing);visualCursor=1 end
function NS.Tooltip(tip,id)
    if not NS.DB or not NS.DB.settings.enabled then return end
    local notice=NS.EnsureReference(id)
    local list=NS.Uses(id)
    if not list then return end
    if notice then tip:AddLine("Smyrna Workshop: "..notice,1,.8,.3) end
    local seen,known,total={},0,0
    for _,recipe in ipairs(list) do
        if not seen[recipe] then
            seen[recipe]=true;total=total+1
            if NS.Known(recipe)==true then known=known+1 end
        end
    end
    if total==0 then return end
    tip:AddLine(NS.SourceLabel and NS.SourceLabel(id) or "Source unknown",.72,.46,.95,true)
    tip:AddLine("Known in "..known..(known==1 and " recipe" or " recipes"),.47,.83,.61)
    tip:AddLine("Used in "..total..(total==1 and " recipe" or " recipes"),.55,.8,1)
    Suite.OptionalHint(tip,"Ctrl + left-click to expand")
end

end chunk(name,Module) end

-- Internal module source: ReferenceManifest.lua
do local function chunk(...)
local _,NS=...
NS.ReferenceManifest=Suite.ReagentProfessions

end chunk(name,Module) end

-- Internal module source: Scanner.lua
do local function chunk(...)
local _,NS=...
-- Only inspect the profession the player opened. Never expand/filter their UI.
local pending={}
-- Session-only: legacy APIs expose difficulty when the profession is open.
local difficulties={}
local difficultyKinds={[0]="optimal",[1]="medium",[2]="easy",[3]="trivial"}
function NS.RecipeDifficulty(r)
    if r.spell and C_TradeSkillUI and C_TradeSkillUI.GetRecipeInfo then
        local ok,info=pcall(C_TradeSkillUI.GetRecipeInfo,r.spell)
        if ok and info and not (issecretvalue and issecretvalue(info.relativeDifficulty)) then
            local kind=difficultyKinds[info.relativeDifficulty]
            if kind then return kind end
        end
    end
    return difficulties[r.profession..":"..r.name]
end
local function Legacy(craft)
    if not craft and IsTradeSkillLinked and IsTradeSkillLinked() then return end
    local num=craft and GetNumCrafts or GetNumTradeSkills
    local info=craft and GetCraftInfo or GetTradeSkillInfo
    local nmat=craft and GetCraftNumReagents or GetTradeSkillNumReagents
    local matinfo=craft and GetCraftReagentInfo or GetTradeSkillReagentInfo
    local matlink=craft and GetCraftReagentItemLink or GetTradeSkillReagentItemLink
    if not (num and info and nmat and matinfo and matlink) then return end
    local profession=(craft and GetCraftDisplaySkillLine and GetCraftDisplaySkillLine()) or (GetTradeSkillLine and GetTradeSkillLine()) or "Profession"
    for i=1,math.min(num() or 0,3000) do
        local name,kind,third=info(i)
        if craft then kind=third end
        if name and kind~="header" then
            difficulties[profession..":"..name]=kind
            local mats={};local valid=true
            for j=1,math.min(nmat(i) or 0,17) do
                local id=NS.ID(matlink(i,j));local _,_,need=matinfo(i,j)
                if not id or type(need)~="number" or need<=0 then valid=false;break end
                mats[#mats+1]={id,need}
            end
            if valid then NS.Save(profession..":"..name,profession,name,mats) end
        end
    end
end
local function Modern()
    local api=C_TradeSkillUI
    if not (api and api.GetAllRecipeIDs and api.GetRecipeInfo and api.GetRecipeSchematic) then return end
    if api.IsTradeSkillLinked and api.IsTradeSkillLinked() then return end
    if api.IsTradeSkillGuild and api.IsTradeSkillGuild() then return end
    local line=api.GetBaseProfessionInfo and api.GetBaseProfessionInfo()
    local profession=line and line.professionName or "Profession"
    local ids=api.GetAllRecipeIDs() or {}
    for i=1,math.min(#ids,3000) do
        local id=ids[i];local info=api.GetRecipeInfo(id)
        if info and info.learned then
            local schema=api.GetRecipeSchematic(id,false)
            if schema then
                local mats,valid={},true
                for _,slot in ipairs(schema.reagentSlotSchematics or {}) do
                    if slot.required~=false and (slot.quantityRequired or 0)>0 then
                        -- Alternative qualities/currencies need allocation-aware math: skip.
                        local choices=slot.reagents or {}
                        if #choices~=1 or not choices[1].itemID then valid=false;break end
                        mats[#mats+1]={choices[1].itemID,slot.quantityRequired}
                    end
                end
                if valid then NS.Save(profession..":"..id,profession,info.name,mats,id) end
            end
        end
    end
end
function NS.Scan(craft)
    if not NS.DB or not NS.DB.settings.enabled then return end
    if not craft and C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic then Modern() else Legacy(craft) end
    if NS.ScanDirty then NS.ScanDirty=false;NS.Reindex() end
    if NS.Refresh then NS.Refresh(true) end
end
function NS.QueueScan(craft)
    local key=craft and "craft" or "trade"
    if pending[key] then return end
    pending[key]=true;C_Timer.After(.25,function() pending[key]=nil;NS.Scan(craft) end)
end

end chunk(name,Module) end


-- Internal module source: UI.lua
do local function chunk(...)
local _,NS=...
local panel,scroll,canvas,measure,heroCard
local sections,cardPool={},{}
local pendingItems,refreshGeneration,refreshQueued={},0,false
local CONTENT_W=694
local CARD_W=686

local professionIcons={
 Alchemy="Interface\\Icons\\Trade_Alchemy",
 Blacksmithing="Interface\\Icons\\Trade_BlackSmithing",
 Cooking="Interface\\Icons\\INV_Misc_Food_15",
 Enchanting="Interface\\Icons\\Trade_Engraving",
 Engineering="Interface\\Icons\\Trade_Engineering",
 ["First Aid"]="Interface\\Icons\\Spell_Holy_SealOfSacrifice",
 FirstAid="Interface\\Icons\\Spell_Holy_SealOfSacrifice",
 Fishing="Interface\\Icons\\Trade_Fishing",
 Herbalism="Interface\\Icons\\Trade_Herbalism",
 Leatherworking="Interface\\Icons\\Trade_LeatherWorking",
 Mining="Interface\\Icons\\Trade_Mining",
 Skinning="Interface\\Icons\\INV_Misc_Pelt_Wolf_01",
 Tailoring="Interface\\Icons\\Trade_Tailoring",
}
local fallbackQualityRGB={
 [0]={.62,.62,.62},
 [1]={.92,.92,.95},
 [2]={.12,1.0,.00},
 [3]={.00,.44,.87},
 [4]={.64,.21,.93},
 [5]={1.0,.50,.00},
}
local function QualityRGB(q)
 if type(q)=="number" then
  local c=ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
  if c then return c.r,c.g,c.b end
  local f=fallbackQualityRGB[q]
  if f then return f[1],f[2],f[3] end
 end
 return .84,.67,.31 -- Subtle brushed-gold default for spells without item rarity
end
local function GlowIntensity(q)
 if type(q)=="number" then
  if q>=4 then return .20 end
  if q==3 then return .18 end
  if q==2 then return .15 end
  if q==1 then return .08 end
  return .06
 end
 return .08
end

local function FormatCoins(copper)
 if type(copper)~="number" or copper~=copper then return "-" end
 local neg=copper<0
 copper=math.floor(math.abs(copper)+.5)
 local g=math.floor(copper/10000)
 local s=math.floor(copper/100)%100
 local c=copper%100
 local parts={}
 if g>0 then parts[#parts+1]=g.."|TInterface\\MoneyFrame\\UI-GoldIcon:11:11:1:0|t" end
 if s>0 or g>0 then parts[#parts+1]=s.."|TInterface\\MoneyFrame\\UI-SilverIcon:11:11:1:0|t" end
 parts[#parts+1]=c.."|TInterface\\MoneyFrame\\UI-CopperIcon:11:11:1:0|t"
 return (neg and "-" or "")..table.concat(parts," ")
end

local function MatUnitCost(matID)
 local ahP,venP=nil,nil
 if Suite.Market and Suite.Market.Price then
  local q=Suite.Market.Price(matID)
  if q and type(q.minimum)=="number" and q.minimum>0 then ahP=q.minimum end
 end
 local vList=Suite.ItemVendors and Suite.ItemVendors[matID]
 if vList and #vList>0 then
  local getInfo=(C_Item and C_Item.GetItemInfo) or GetItemInfo
  local sp=getInfo and select(11,getInfo(matID))
  if NS.Public(sp) and type(sp)=="number" and sp>0 then venP=sp*4 end -- Classic vendor buy = 4x sell
 end
 if venP and ahP then
  if venP<=ahP then return venP,"V" else return ahP,"AH" end
 elseif venP then return venP,"V"
 elseif ahP then return ahP,"AH"
 end
 return nil,nil
end
NS.FormatCoins=FormatCoins

-- Shared profession-card/strip estimate; quote prices are listings, not completed sales.
function NS.NetCraftProfit(listing,cost)
 local market=Suite.Modules and Suite.Modules.SmyrnaMarket
 local sale=market and market.UndercutPrice and market.UndercutPrice(listing) or listing
 return math.floor(sale*.95+.5)-cost
end

NS.MatUnitCost=MatUnitCost

local function CreateRecipeCard()
 local card=CreateFrame("Button",nil,canvas,"BackdropTemplate")
 card:SetSize(CARD_W,84)
 Suite.StyleCard(card,.082,.094,.128)
 local hl=card:CreateTexture(nil,"HIGHLIGHT")
 hl:SetPoint("TOPLEFT",1,-1);hl:SetPoint("BOTTOMRIGHT",-1,1)
 hl:SetColorTexture(.40,.58,.86,.10)
 card.tile=Suite.CreateIconTile(card,40)
 card.tile:SetPoint("TOPLEFT",11,-11)
 card.name=card:CreateFontString(nil,"OVERLAY","GameFontNormal")
 card.name:SetPoint("TOPLEFT",60,-10);card.name:SetWidth(415);card.name:SetJustifyH("LEFT");card.name:SetMaxLines(1)
 card.badges=card:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
 card.badges:SetPoint("TOPRIGHT",-12,-11);card.badges:SetJustifyH("RIGHT")
 card.learn=card:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
 card.learn:SetPoint("TOPLEFT",60,-28);card.learn:SetWidth(CARD_W-74);card.learn:SetJustifyH("LEFT");card.learn:SetMaxLines(1)
 card.learn:SetTextColor(.68,.76,.88)
 card.econ=card:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
 card.econ:SetPoint("TOPLEFT",60,-44);card.econ:SetWidth(CARD_W-74);card.econ:SetJustifyH("LEFT");card.econ:SetMaxLines(1)
 card.econ:SetTextColor(.88,.90,.94)
 card.tray=CreateFrame("Frame",nil,card,"BackdropTemplate")
 card.tray:SetPoint("TOPLEFT",60,-62);card.tray:SetPoint("TOPRIGHT",-10,-62)
 card.tray:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Buttons\\WHITE8X8",edgeSize=1,insets={left=1,right=1,top=1,bottom=1}})
 card.tray:SetBackdropColor(.048,.055,.076,.92);card.tray:SetBackdropBorderColor(.17,.20,.27,.85)
 card.mats=card.tray:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
 card.mats:SetPoint("TOPLEFT",8,-5);card.mats:SetPoint("TOPRIGHT",-8,-5);card.mats:SetJustifyH("LEFT")
 card:SetScript("OnEnter",function(self)
  if self.qr then self:SetBackdropBorderColor(self.qr,self.qg,self.qb,.72) end
  if not GameTooltip or (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then return end
  if self.itemID then
   GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetHyperlink("item:"..self.itemID);GameTooltip:Show()
  elseif self.spell then
   GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetSpellByID(self.spell);GameTooltip:Show()
  end
 end)
 card:SetScript("OnLeave",function(self)
  self:SetBackdropBorderColor(.22,.25,.33,.88)
  if GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then GameTooltip:Hide() end
 end)
 card:SetScript("OnClick",function(self)
  if not SetItemRef then return end
  if self.itemID then SetItemRef("item:"..self.itemID,self.recipeName or "","LeftButton")
  elseif self.spell then SetItemRef("spell:"..self.spell,self.recipeName or "","LeftButton") end
 end)
 return card
end

local function CreateSectionHeader()
 local h=CreateFrame("Button",nil,canvas,"UIPanelButtonTemplate")
 h:SetSize(CONTENT_W,30)
 Suite.StyleButton(h)
 h.profTile=Suite.CreateIconTile(h,20)
 h.profTile:SetPoint("LEFT",8,0)
 h.titleText=h:CreateFontString(nil,"OVERLAY","GameFontNormal")
 h.titleText:SetPoint("LEFT",h.profTile,"RIGHT",8,0);h.titleText:SetJustifyH("LEFT")
 h.countText=h:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
 h.countText:SetPoint("RIGHT",-12,0);h.countText:SetJustifyH("RIGHT")
 h:SetText("")
 h:SetScript("OnClick",function(self)
  NS.DB.collapsedProfessions[self.profession]=not NS.DB.collapsedProfessions[self.profession] or nil
  local offset=scroll:GetVerticalScroll()
  NS.Refresh(true)
  scroll:SetVerticalScroll(math.min(offset,scroll:GetVerticalScrollRange()))
 end)
 return h
end

function NS.Refresh(preserveScroll)
    if not panel or not NS.DB then return end
    local prevScroll=preserveScroll and scroll:GetVerticalScroll() or 0
    refreshGeneration=refreshGeneration+1;refreshQueued=false;wipe(pendingItems)
    local id=NS.FilterItem
    local rows=id and NS.ItemRecipes(id) or {}
    NS.DB.collapsedProfessions=NS.DB.collapsedProfessions or {}

    -- Populate Hero Card
    if id then
        local hIcon,hQuality=NS.ItemVisual(id)
        local qr,qg,qb=QualityRGB(hQuality)
        heroCard.tile.icon:SetTexture(hIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
        heroCard.tile:SetBackdropBorderColor(qr,qg,qb,.92)
        Suite.SetCornerGlow(heroCard,qr,qg,qb,GlowIntensity(hQuality))
        heroCard.title:SetText(NS.ItemName(id));heroCard.title:SetTextColor(qr,qg,qb)
        heroCard.count:SetText(Suite.UIText(#rows..(#rows==1 and " recipe" or " recipes"),"heading"))
        local detailLines={}
        local hPrice,hSrc=MatUnitCost(id)
        if hPrice then
            detailLines[#detailLines+1]=Suite.UIText("Market: ","detail")..FormatCoins(hPrice).." ("..(hSrc=="V" and "Vendor" or "AH")..")"
        end
        if NS.SourceEntries then
            detailLines[#detailLines+1]=Suite.UIText("Sources: ","detail")..table.concat(NS.SourceEntries(id),"  /  ")
        end
        if NS.FilterNotice then detailLines[#detailLines+1]=Suite.UIText(NS.FilterNotice,"warning") end
        if #rows==0 then detailLines[#detailLines+1]=Suite.UIText("No recipes found using this item.","muted")
        else detailLines[#detailLines+1]=Suite.UIText("Counts items in your bags. Open a profession window to update learned recipes.","muted") end
        local dText=table.concat(detailLines,"\n")
        heroCard.detail:SetText(dText)
        measure:SetWidth(CONTENT_W-76);measure:SetText(dText)
        heroCard:SetHeight(math.max(68,42+measure:GetStringHeight()+10))
    else
        heroCard.tile.icon:SetTexture("Interface\\Icons\\INV_Hammer_20")
        heroCard.tile:SetBackdropBorderColor(.74,.58,.29,.9)
        Suite.SetCornerGlow(heroCard,.84,.67,.31,.10)
        heroCard.title:SetText("Choose an item to inspect");heroCard.title:SetTextColor(1,.86,.48)
        heroCard.count:SetText(Suite.UIText(NS.recipeCount.." learned","good"))
        heroCard.detail:SetText(Suite.UIText("Ctrl + left-click any crafting material in your bags, chat, or profession window to see every recipe that uses it.","detail").."\n"..Suite.UIText("Open your profession windows once so Workshop knows what you can craft.","muted"))
        heroCard:SetHeight(76)
    end

    local top=heroCard:GetHeight()+12
    if NS.RenderVendors then top=NS.RenderVendors(canvas,top,id,measure,CONTENT_W) end

    -- Quests section (linked to SmyrnaWorldDB & SmyrnaQuests parchment viewer)
    NS.questSectionRows=NS.questSectionRows or {}
    for _,qr in ipairs(NS.questSectionRows) do qr:Hide() end
    if id and Suite.WorldDB and Suite.WorldDB.Item and Suite.WorldDB.Quest then
        local it=Suite.WorldDB.Item(id)
        local qids={}
        if it then
            for _,k in ipairs({"q","qs","qi","nq","rq"}) do
                if type(it[k])=="table" then
                    for _,qid in ipairs(it[k]) do if type(qid)=="number" then qids[#qids+1]=qid end end
                elseif type(it[k])=="number" then
                    qids[#qids+1]=it[k]
                end
            end
        end
        if #qids>0 then
            local qIdx=0
            for _,qid in ipairs(qids) do
                local q=Suite.WorldDB.Quest(qid)
                if q and q.n then
                    qIdx=qIdx+1
                    local qr=NS.questSectionRows[qIdx]
                    if not qr then
                        qr=CreateFrame("Button",nil,canvas,"BackdropTemplate")
                        qr:SetSize(CONTENT_W,26); Suite.StyleCard(qr,.065,.078,.11)
                        qr.txt=qr:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
                        qr.txt:SetPoint("LEFT",10,0); qr.txt:SetWidth(CONTENT_W-90); qr.txt:SetJustifyH("LEFT"); qr.txt:SetMaxLines(1)
                        qr.tag=qr:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
                        qr.tag:SetPoint("RIGHT",-10,0); qr.tag:SetText("|cff78d49bQuest|r")
                        qr:SetScript("OnClick",function(self)
                            local Q=Suite.Modules and Suite.Modules.SmyrnaQuests
                            if Q and Q.OpenParchment and self.qid then Q.OpenParchment(self.qid) end
                        end)
                        NS.questSectionRows[qIdx]=qr
                    end
                    qr.qid=qid
                    qr:ClearAllPoints(); qr:SetPoint("TOPLEFT",0,-top)
                    local ql=q.ql or q.rl or 0
                    qr.txt:SetText((ql>0 and ("|cffffd670["..ql.."]|r ") or "")..q.n)
                    qr:Show()
                    top=top+30
                    if qIdx>=10 then break end
                end
            end
            if qIdx>0 then top=top+6 end
        end
    end

    local groups={}
    for _,r in ipairs(rows) do
        local group=groups[#groups]
        if not group or group.profession~=r.profession then group={profession=r.profession,recipes={},learned=0};groups[#groups+1]=group end
        group.recipes[#group.recipes+1]=r
        if NS.Known(r)==true then group.learned=group.learned+1 end
    end

    local cardIndex=0
    for i,group in ipairs(groups) do
        local section=sections[i]
        if not section then
            section={header=CreateSectionHeader()};sections[i]=section
        end
        local profession=group.profession
        if NS.ExpandFiltered then NS.DB.collapsedProfessions[profession]=nil end
        local collapsed=NS.DB.collapsedProfessions[profession]
        local h=section.header
        h.profession=profession;h:ClearAllPoints();h:SetPoint("TOPLEFT",0,-top)
        h.profTile.icon:SetTexture(professionIcons[profession] or "Interface\\Icons\\INV_Misc_Gear_01")
        h.profTile:SetBackdropBorderColor(.74,.58,.29,.88)
        h.titleText:SetText(Suite.UIText((collapsed and "+  " or "-  ")..profession,"heading"))
        h.countText:SetText(Suite.UIText(#group.recipes..(#group.recipes==1 and " recipe" or " recipes"),"detail").."   "..Suite.UIText(group.learned.." learned",group.learned>0 and "good" or "muted"))
        Suite.SetButtonSelected(h,not collapsed)
        h:Show()
        top=top+36

        if not collapsed then
            for _,r in ipairs(group.recipes) do
                cardIndex=cardIndex+1
                local card=cardPool[cardIndex]
                if not card then card=CreateRecipeCard();cardPool[cardIndex]=card end
                local rIcon,rQuality,rItemID=NS.RecipeVisual(r,pendingItems)
                local qr,qg,qb=QualityRGB(rQuality)
                card.qr,card.qg,card.qb=qr,qg,qb
                card.spell,card.itemID,card.recipeName=r.spell,rItemID,r.name
                card.tile.icon:SetTexture(rIcon)
                card.tile:SetBackdropBorderColor(qr,qg,qb,.92)
                local difficulty=NS.RecipeDifficulty(r)
                local colors=TradeSkillTypeColor or CraftTypeColor
                local color=difficulty and colors and colors[difficulty]
                if color then
                    Suite.SetCornerGlow(card,color.r,color.g,color.b,difficulty=="trivial" and .05 or .16)
                else
                    -- No skill-up claim for unlearned/unavailable recipe data.
                    Suite.SetCornerGlow(card,.50,.56,.68,.04)
                end

                local skillTag=r.skill and Suite.UIText("  (Skill "..r.skill..")","muted") or ""
                card.name:SetText(r.name..skillTag)
                card.name:SetTextColor(qr,qg,qb)

                local known=NS.Known(r)
                local ready=NS.Ready(r)
                local knownPill=known==true and Suite.UIText("Learned","good") or known==false and Suite.UIText("Not learned","muted") or Suite.UIText("Status unknown","muted")
                local readyPill=ready>0 and Suite.UIText("Craft x"..ready,"good") or Suite.UIText("Missing mats","warning")
                card.badges:SetText(knownPill.."   |cff444c5e/|r   "..readyPill)

                local matParts={}
                local totalCost,costComplete=0,true
                for _,v in ipairs(r.mats) do
                    local have=NS.Count(v[1])
                    local uCost,uSrc=MatUnitCost(v[1])
                    local priceTag=""
                    if uCost then
                        totalCost=totalCost+(uCost*v[2])
                        priceTag=" |cff98a4b8("..FormatCoins(uCost).." "..uSrc..")|r"
                    else
                        costComplete=false
                    end
                    matParts[#matParts+1]=NS.ItemName(v[1]).." "..Suite.UIText(have.."/"..v[2],have>=v[2] and "good" or "warning")..priceTag
                end
                local outQ=rItemID and Suite.Market and Suite.Market.Price and Suite.Market.Price(rItemID)
                local outAH=outQ and type(outQ.minimum)=="number" and outQ.minimum>0 and outQ.minimum or nil
                local econ=""
                if totalCost>0 or outAH then
                    local parts={}
                    if outAH then parts[#parts+1]="|cffdfb66bSell (AH):|r "..FormatCoins(outAH) end
                    if totalCost>0 then parts[#parts+1]="|cff9aa6b8Mats:|r "..FormatCoins(totalCost)..(costComplete and "" or "+") end
                    if outAH and totalCost>0 and costComplete then
                        local prof=NS.NetCraftProfit(outAH,totalCost)
                        local pCol=prof>=0 and "|cff78d49b+" or "|cffff7a66"
                        parts[#parts+1]="|cffdfb66bNet (5% AH cut):|r "..pCol..FormatCoins(prof).."|r"
                    end
                    econ=table.concat(parts,"   |cff444c5e / |r   ")
                end
                local acq=(Suite.RecipeAcquisition and r.spell and Suite.RecipeAcquisition[r.spell]) or "Source unknown"
                card.learn:SetText("Learn: "..acq)
                card.econ:SetText(econ)
                local trayTop=econ~="" and -62 or -46
                card.tray:ClearAllPoints()
                card.tray:SetPoint("TOPLEFT",60,trayTop);card.tray:SetPoint("TOPRIGHT",-10,trayTop)
                local matText=table.concat(matParts,"   |cff444c5e/|r   ")
                card.mats:SetText(matText)
                measure:SetWidth(CARD_W-86);measure:SetText(matText)
                local trayH=math.max(24,measure:GetStringHeight()+10)
                card.tray:SetHeight(trayH)
                local cardH=math.max(76,(-trayTop)+trayH+8)
                card:SetHeight(cardH)
                card:ClearAllPoints();card:SetPoint("TOPLEFT",4,-top)
                card:Show()
                top=top+cardH+6
            end
            top=top+6
        end
    end
    NS.ExpandFiltered=nil
    for i=#groups+1,#sections do sections[i].header:Hide() end
    for i=cardIndex+1,#cardPool do cardPool[i]:Hide() end
    NS.Sections=sections
    NS.RecipeCards=cardPool
    canvas:SetHeight(math.max(410,top+10));measure:SetText("")
    scroll:UpdateScrollChildRect()
    scroll:SetVerticalScroll(preserveScroll and math.min(prevScroll,scroll:GetVerticalScrollRange()) or 0)
end

function NS.Open(preserveScroll)
    if not panel then
        panel=CreateFrame("Frame","SmyrnaWorkshopPanel",UIParent,"BackdropTemplate")
        panel:SetSize(760,540);panel:SetPoint("CENTER");panel:SetFrameStrata("DIALOG");panel:SetClampedToScreen(true)
        Suite.StylePanel(panel,true)
        local title=panel:CreateFontString(nil,"OVERLAY","GameFontNormalLarge");title:SetPoint("TOPLEFT",20,-16);title:SetText("Workshop");title:SetTextColor(1,.86,.48)
        local sub=panel:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");sub:SetPoint("TOPLEFT",112,-20);sub:SetText("Ctrl + left-click any reagent to explore its recipes and sources.");sub:SetTextColor(.68,.73,.82)
        local close=Suite.CloseButton(panel);panel.SuiteCloseButton=close
        local b=CreateFrame("CheckButton",nil,panel,"UICheckButtonTemplate");b:SetPoint("TOPLEFT",18,-42);b:SetChecked(NS.DB.settings.enabled)
        local t=b:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");t:SetPoint("LEFT",b,"RIGHT",2,0);t:SetText("Show recipe summary in bag tooltips")
        b:SetScript("OnClick",function(self) NS.DB.settings.enabled=self:GetChecked();NS.Configure() end)
        Suite.OptionSection(panel,"Recipes & Sources",20,-74,720)
        scroll=CreateFrame("ScrollFrame",nil,panel,"UIPanelScrollFrameTemplate");scroll:SetPoint("TOPLEFT",20,-94);scroll:SetPoint("BOTTOMRIGHT",-38,16)
        canvas=CreateFrame("Frame",nil,scroll);canvas:SetSize(CONTENT_W,420);scroll:SetScrollChild(canvas)
        scroll:EnableMouseWheel(true)
        scroll:SetScript("OnMouseWheel",function(self,delta)
            local cur,max=self:GetVerticalScroll(),self:GetVerticalScrollRange()
            if type(cur)=="number" and type(max)=="number" then self:SetVerticalScroll(math.max(0,math.min(max,cur-delta*48))) end
        end)
        heroCard=CreateFrame("Frame",nil,canvas,"BackdropTemplate")
        heroCard:SetSize(CONTENT_W,76);heroCard:SetPoint("TOPLEFT",0,0);Suite.StyleCard(heroCard,.072,.084,.114)
        heroCard.tile=Suite.CreateIconTile(heroCard,40);heroCard.tile:SetPoint("TOPLEFT",12,-14)
        heroCard.title=heroCard:CreateFontString(nil,"OVERLAY","GameFontNormalLarge");heroCard.title:SetPoint("TOPLEFT",62,-12);heroCard.title:SetWidth(460);heroCard.title:SetJustifyH("LEFT");heroCard.title:SetMaxLines(1)
        heroCard.count=heroCard:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");heroCard.count:SetPoint("TOPRIGHT",-12,-14);heroCard.count:SetJustifyH("RIGHT")
        heroCard.detail=heroCard:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");heroCard.detail:SetPoint("TOPLEFT",62,-34);heroCard.detail:SetWidth(CONTENT_W-76);heroCard.detail:SetJustifyH("LEFT")
        measure=panel:CreateFontString(nil,"BACKGROUND","GameFontHighlightSmall");measure:SetWidth(CARD_W-86);measure:Hide()
        panel:SetScript("OnEvent",function(_,_,itemID,success)
            if not NS.Public(itemID) or not NS.Public(success) or success==false or not pendingItems[itemID] then return end
            pendingItems[itemID]=nil
            if refreshQueued then return end
            refreshQueued=true
            local token=refreshGeneration
            C_Timer.After(.15,function()
                refreshQueued=false
                if token==refreshGeneration and panel and panel:IsShown() then NS.Refresh(true) end
            end)
        end)
        panel:SetScript("OnShow",function(self) self:RegisterEvent("GET_ITEM_INFO_RECEIVED") end)
        panel:SetScript("OnHide",function(self)
            self:UnregisterEvent("GET_ITEM_INFO_RECEIVED")
            refreshGeneration=refreshGeneration+1;refreshQueued=false;wipe(pendingItems)
        end)
        UISpecialFrames[#UISpecialFrames+1]="SmyrnaWorkshopPanel"
    end
    NS.Refresh(preserveScroll)
    panel:Show()
    return panel
end
function NS.OpenUses(id)
    if not NS.DB or not NS.DB.settings.enabled or not NS.Public(id) or type(id)~="number" or id<=0 or id%1~=0 then return false end
    NS.FilterNotice=NS.EnsureReference(id);NS.FilterItem=id;NS.ExpandFiltered=true
    NS.Open()
    return true
end
function NS.Configure()
end

end chunk(name,Module) end

-- Internal module source: Main.lua
do local function chunk(...)
local addon,NS=...
local f=CreateFrame("Frame")
local modActive=true
local WORKSHOP_EVENTS={"BAG_UPDATE_DELAYED","TRADE_SKILL_SHOW","TRADE_SKILL_LIST_UPDATE","TRADE_SKILL_DATA_SOURCE_CHANGED","TRADE_SKILL_DETAILS_UPDATE","CRAFT_SHOW","CRAFT_UPDATE"}
NS.Events={}
local function Register(event)
    if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then return end
    local ok=pcall(f.RegisterEvent,f,event)
    if ok then NS.Events[event]=true end
end
local function SyncWorkshopEvents(on)
    for _,e in ipairs(WORKSHOP_EVENTS) do
        if on then Register(e) else pcall(f.UnregisterEvent,f,e) end
    end
end
local shownIDs=setmetatable({},{__mode="k"})
-- Reagent widgets may bypass HandleModifiedItemClick. Hook only the actual
-- item-tooltip owner, once, and resolve its current hover item on each click.
local owners=setmetatable({},{__mode="k"})
function NS.HookItemOwner(tip,id)
    if not tip.GetOwner then return end
    local owner=tip:GetOwner()
    if Suite.IsLootInteraction and Suite.IsLootInteraction(owner) then return end
    if not owner or not owner.HookScript or not owner.HasScript then return end
    if owner.IsForbidden and owner:IsForbidden() then return end
    local entry=owners[owner]
    if not entry then
        local script=owner:HasScript("OnClick") and "OnClick" or (owner:HasScript("OnMouseUp") and "OnMouseUp")
        if not script then return end
        entry={};owners[owner]=entry
        owner:HookScript(script,function(self,button)
            if button~="LeftButton" or not tip:IsShown() or tip:GetOwner()~=self then return end
            local current=owners[self]
            if current and current.id and shownIDs[tip]==current.id then NS.ModifiedItemClick("item:"..current.id) end
        end)
    end
    entry.id=id
end
local function ItemTip(tip,id)
    if (tip~=GameTooltip and tip~=ItemRefTooltip) or not NS.DB or not NS.DB.settings.enabled then return end
    if tip.IsForbidden and tip:IsForbidden() then return end
    if not NS.Public(id) or type(id)~="number" or id<=0 then return end
    if shownIDs[tip]==id then if tip==GameTooltip then NS.HookItemOwner(tip,id) end;return end
    shownIDs[tip]=id;NS.Tooltip(tip,id)
    if tip==GameTooltip then NS.HookItemOwner(tip,id) end
end
NS.ItemTip=ItemTip
function NS.Status()
    local packs=0;for _ in pairs(NS.ReferenceLoaded) do packs=packs+1 end
    DEFAULT_CHAT_FRAME:AddMessage("Smyrna Workshop: "..(NS.DB.settings.enabled and "on" or "off").."; tooltips: "..(NS.hookMode or "not installed").."; "..NS.recipeCount.." learned recipes; "..packs.." reference packs loaded.")
end
local function CarriedBag(bag)
    -- Forever includes its reagent bag after the four regular bag slots.
    return NS.Public(bag) and type(bag)=="number" and bag%1==0 and bag>=0 and bag<=(NUM_TOTAL_BAG_FRAMES or 5)
end
function NS.ModifiedItemClick(link,location)
    -- Native modified-click posthook also handles loot reagents; never hook loot buttons.
    if not NS.DB or not NS.DB.settings.enabled or not IsControlKeyDown or not IsControlKeyDown() then return false end
    if (IsShiftKeyDown and IsShiftKeyDown()) or (IsAltKeyDown and IsAltKeyDown()) then return false end
    local id=NS.ID(link)
    if not id or (not NS.Uses(id) and not (NS.ReferenceManifest and NS.ReferenceManifest[id])) then return false end
    if (type(location)=="table" or type(location)=="userdata") and type(location.IsBagAndSlot)=="function" then
        if not location:IsBagAndSlot() then return false end
        local bag=location:GetBagAndSlot()
        if not CarriedBag(bag) then return false end
    end
    return NS.OpenUses(id)
end
function NS.ChatItemClick(link,button)
    if button~="LeftButton" or not NS.Public(link) or type(link)~="string" or not link:match("^item:") then return false end
    if not NS.DB or not NS.DB.settings.enabled then return false end
    if (IsShiftKeyDown and IsShiftKeyDown()) or (IsAltKeyDown and IsAltKeyDown()) then return false end
    local id=NS.ID(link)
    if not id or (not NS.Uses(id) and not (NS.ReferenceManifest and NS.ReferenceManifest[id])) then return false end
    if IsControlKeyDown and IsControlKeyDown() then return NS.ModifiedItemClick(link) end
    if ItemRefTooltip then ItemTip(ItemRefTooltip,id);ItemRefTooltip:Show() end
    return true
end
f:RegisterEvent("ADDON_LOADED")
local function BagTip(tip,bag,slot)
    if not NS.DB or not NS.DB.settings.enabled then return end
    local fn=C_Container and C_Container.GetContainerItemLink or GetContainerItemLink
    local id=fn and NS.ID(fn(bag,slot))
    if id then ItemTip(tip,id);tip:Show() end
end
f:SetScript("OnEvent",function(self,event,name)
    if event=="ADDON_LOADED" then
        if not NS.Public(name) or name~="SmyrnaSuite" then return end
        self:UnregisterEvent("ADDON_LOADED")
        NS.Init();NS.Configure()
        if ItemRefTooltip then
            ItemRefTooltip:HookScript("OnTooltipCleared",function(tip) shownIDs[tip]=nil end)
            ItemRefTooltip:HookScript("OnHide",function(tip) shownIDs[tip]=nil end)
        end
        if SetItemRef then hooksecurefunc("SetItemRef",function(link,text,button) NS.ChatItemClick(link,button) end) end
        SyncWorkshopEvents(modActive)
        GameTooltip:HookScript("OnTooltipCleared",function(tip) shownIDs[tip or GameTooltip]=nil end)
        GameTooltip:HookScript("OnHide",function(tip) shownIDs[tip or GameTooltip]=nil end)
        if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
            -- Forever's data-driven tooltip can rebuild lines after SetBagItem hooks.
            -- Append after item processing so native rendering cannot erase our lines.
            NS.hookMode="item post-processing"
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item,function(tip,data)
                if not tip or (tip.IsForbidden and tip:IsForbidden()) then return end
                if (tip~=GameTooltip and tip~=ItemRefTooltip) or not NS.DB or not NS.DB.settings.enabled then return end
                local id=data and data.id
                if not NS.Public(id) or id==nil then
                    if TooltipUtil and TooltipUtil.GetDisplayedItem then
                        local _,link,displayed=TooltipUtil.GetDisplayedItem(tip)
                        id=(NS.Public(displayed) and displayed) or NS.ID(link)
                    elseif tip.GetItem then local _,link=tip:GetItem();id=NS.ID(link) end
                end
                ItemTip(tip,id)
            end)
        else
            NS.hookMode="legacy bag hook"
            hooksecurefunc(GameTooltip,"SetBagItem",BagTip)
        end
        if HandleModifiedItemClick then
            hooksecurefunc("HandleModifiedItemClick",NS.ModifiedItemClick)
        elseif ContainerFrameItemButton_OnModifiedClick then
            hooksecurefunc("ContainerFrameItemButton_OnModifiedClick",function(button,mouse)
                if mouse~="LeftButton" then return end
                local bag=button.GetBagID and button:GetBagID() or (button:GetParent() and button:GetParent():GetID())
                local slot=button:GetID();local link=(C_Container and C_Container.GetContainerItemLink) or GetContainerItemLink
                if link and CarriedBag(bag) then NS.ModifiedItemClick(link(bag,slot)) end
            end)
        end
        SLASH_SMYRNAWORKSHOP1="/sw";SLASH_SMYRNAWORKSHOP2="/smyrnaworkshop";SlashCmdList.SMYRNAWORKSHOP=function(input) if input=="status" then NS.Status() else NS.Open() end end
    elseif event=="BAG_UPDATE_DELAYED" then NS.Invalidate()
    else
        NS.QueueScan(event=="CRAFT_SHOW" or event=="CRAFT_UPDATE")
        if NS.HookProfessionProfit then NS.HookProfessionProfit() end
    end
end)

-- ============================================================
-- Live Craft Cost & Profit Strip on Blizzard Professions / TradeSkill UI
-- ============================================================
local profStrip,profHooked=nil,false
local function EnsureProfStrip(parent)
    if not parent then return nil end
    if not profStrip then
        local f=CreateFrame("Frame",nil,parent)
        f:SetSize(170,60);f:SetFrameLevel(parent:GetFrameLevel()+6);f:EnableMouse(false)
        f.txt=f:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        f.txt:SetPoint("TOPLEFT",0,0);f.txt:SetPoint("TOPRIGHT",0,0)
        f.txt:SetJustifyH("LEFT");f.txt:SetJustifyV("TOP");f.txt:SetMaxLines(3)
        local note=f:CreateFontString(nil,"OVERLAY","GameFontDisableSmall")
        note:SetPoint("TOPLEFT",0,-46);note:SetText("*After undercut + 5% AH cut")
        profStrip=f
    end
    profStrip:SetParent(parent)
    profStrip:ClearAllPoints()
    local label=parent.ReagentsLabel or (parent.Reagents and parent.Reagents.Label)
    if not label and TradeSkillFrame and (parent==TradeSkillFrame or parent==TradeSkillDetailScrollChildFrame) then label=TradeSkillReagentLabel end
    if not label and CraftFrame and (parent==CraftFrame or parent==CraftDetailScrollChildFrame) then label=CraftReagentLabel end
    if label then profStrip:SetPoint("TOPLEFT",label,"BOTTOMLEFT",170,-10)
    else profStrip:SetPoint("TOPRIGHT",parent,"TOPRIGHT",-12,-120) end
    return profStrip
end

local function RenderProfitStrip(parent,outItemID,mats)
    if not modActive or (NS.DB and not NS.DB.settings.enabled) then if profStrip then profStrip:Hide() end; return end
    local f=EnsureProfStrip(parent)
    if not f then return end
    if not mats or #mats==0 then f:Hide(); return end
    local cost,complete=0,true
    for i=1,#mats do
        local u=NS.MatUnitCost and NS.MatUnitCost(mats[i][1])
        if u then cost=cost+(u*mats[i][2]) else complete=false end
    end
    local q=outItemID and Suite.Market and Suite.Market.Price and Suite.Market.Price(outItemID)
    local ah=q and type(q.minimum)=="number" and q.minimum>0 and q.minimum or nil
    if cost<=0 and not ah then f:Hide(); return end
    local parts={}
    if cost>0 then parts[#parts+1]="|cffc8d2e2Cost:|r "..NS.FormatCoins(cost)..(complete and "" or "+") end
    if ah then parts[#parts+1]="|cffc8d2e2AH:|r "..NS.FormatCoins(ah) end
    if ah and cost>0 and complete then
        local p=NS.NetCraftProfit(ah,cost)
        local col=p>=0 and "|cff78d49b+" or "|cffff7a66"
        parts[#parts+1]="|cffdfb66bProfit*:|r "..col..NS.FormatCoins(p).."|r"
    end
    f.txt:SetText(table.concat(parts,"\n"))
    f:Show()
end

function NS.HookProfessionProfit()
    if profHooked then return end
    local form=ProfessionsFrame and ProfessionsFrame.CraftingPage and ProfessionsFrame.CraftingPage.SchematicForm
    if form and form.Init then
        profHooked=true
        hooksecurefunc(form,"Init",function(self,recipeInfo)
            if not recipeInfo or not recipeInfo.recipeID or not (C_TradeSkillUI and C_TradeSkillUI.GetRecipeSchematic) then
                if profStrip then profStrip:Hide() end; return
            end
            local ok,sch=pcall(C_TradeSkillUI.GetRecipeSchematic,recipeInfo.recipeID,false)
            if not ok or type(sch)~="table" then if profStrip then profStrip:Hide() end; return end
            local mats={}
            for _,slot in ipairs(sch.reagentSlotSchematics or {}) do
                if slot.required and slot.quantityRequired and slot.reagents and #slot.reagents==1 and slot.reagents[1].itemID then
                    mats[#mats+1]={slot.reagents[1].itemID,slot.quantityRequired}
                end
            end
            RenderProfitStrip(self,sch.outputItemID,mats)
        end)
        return
    end
    if TradeSkillFrame and TradeSkillFrame_SetSelection then
        profHooked=true
        hooksecurefunc("TradeSkillFrame_SetSelection",function(idx)
            if not idx or not GetTradeSkillItemLink or not GetTradeSkillNumReagents then return end
            local link=GetTradeSkillItemLink(idx)
            local outID=NS.ID(link)
            local mats={}
            for i=1,(GetTradeSkillNumReagents(idx) or 0) do
                local rLink=GetTradeSkillReagentItemLink and GetTradeSkillReagentItemLink(idx,i)
                local _,_,cnt=GetTradeSkillReagentInfo(idx,i)
                local rid=NS.ID(rLink)
                if rid and cnt and cnt>0 then mats[#mats+1]={rid,cnt} end
            end
            RenderProfitStrip(TradeSkillDetailScrollChildFrame or TradeSkillFrame,outID,mats)
        end)
    end
end

function NS.SetEnabled(on)
    modActive=on and true or false
    if NS.DB and NS.DB.settings then NS.DB.settings.enabled=modActive end
    SyncWorkshopEvents(modActive)
    if not modActive then
        if profStrip then profStrip:Hide() end
        for _,fn in ipairs({"SmyrnaWorkshopWindow","SmyrnaWorkshopUses"}) do
            local w=_G[fn]; if w and w.Hide then w:Hide() end
        end
    end
end

end chunk(name,Module) end

Suite.Loaded[name]=true
Module.Perf=function() if Suite.Memory then Suite.Memory() end end
