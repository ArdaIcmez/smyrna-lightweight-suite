local _,Suite=...
local name="SmyrnaWorkshop"
Suite.Versions[name]="0.2.0"
if Suite.Config.features[name]==false then return end
local Module={}
Suite.Modules[name]=Module

-- Internal module source: Core.lua
do local function chunk(...)
local _,NS=...
_G.SmyrnaWorkshop=NS
local index,counts={},{}
local references={}
NS.ReferenceLoaded={}
local unavailable={}
local loadingReferences,referenceDirty=false,false
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
    local keys,seen={},{}
    for key in pairs(NS.DB.recipes) do keys[#keys+1]=key end;table.sort(keys)
    NS.recipeCount=#keys
    local function Add(r)
        for _,v in ipairs(r.mats) do
            local list=index[v[1]];if not list then list={};index[v[1]]=list end
            list[#list+1]=r
        end
    end
    for _,key in ipairs(keys) do
        local r=NS.DB.recipes[key];r.learned=true
        seen[r.spell or (r.profession..":"..r.name)]=true;seen[r.profession..":"..r.name]=true;Add(r)
    end
    for _,r in ipairs(references) do
        if not seen[r.spell] and not seen[r.profession..":"..r.name] then Add(r) end
    end
    wipe(counts)
end
function NS.Save(key,profession,name,mats,spell)
    if type(name)~="string" or #mats==0 or #mats>16 then return end
    if not NS.DB.recipes[key] then
        if NS.recipeCount>=3000 then return end
        NS.recipeCount=NS.recipeCount+1
    end
    local old=NS.DB.recipes[key]
    local same=old and old.profession==profession and old.name==name and old.spell==spell and #old.mats==#mats
    if same then for i,v in ipairs(mats) do if old.mats[i][1]~=v[1] or old.mats[i][2]~=v[2] then same=false;break end end end
    if same then return false end
    NS.DB.recipes[key]={profession=profession,name=name,mats=mats,spell=spell,learned=true}
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
function NS.Uses(id) return index[id] end
function NS.Known(r)
    if r.learned then return true end
    if r.spell then
        local fn=IsPlayerSpell or IsSpellKnown
        if fn then return fn(r.spell) end
    end
end
function NS.Ready(r)
    local times=math.huge
    for _,v in ipairs(r.mats) do times=math.min(times,math.floor(NS.Count(v[1])/v[2])) end
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
    for _,recipe in ipairs(index[id] or {}) do if not seen[recipe] then rows[#rows+1]=recipe;seen[recipe]=true end end
    SortRecipes(rows)
    return rows
end
function NS.ItemName(id)
    local fn=C_Item and C_Item.GetItemInfo or GetItemInfo
    local name=fn and fn(id)
    if NS.Public(name) and type(name)=="string" then return name end
    local gear=Suite.Equipment and Suite.Equipment.Get(id)
    return gear and gear.name or ("Item #"..id)
end
function NS.Tooltip(tip,id)
    if not NS.DB or not NS.DB.settings.enabled then return end
    local notice=NS.EnsureReference(id)
    local list=index[id]
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
    tip:AddLine("Ctrl + left-click to expand",.7,.7,.7,true)
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
local panel,listing,measure,scroll,icon,canvas
local sections={}
function NS.Open()
    if not panel then
        panel=CreateFrame("Frame","SmyrnaWorkshopPanel",UIParent,"BackdropTemplate")
        panel:SetSize(600,450);panel:SetPoint("CENTER");panel:SetFrameStrata("DIALOG")
        panel:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12});panel:SetBackdropColor(.04,.04,.04,.98)
        local title=panel:CreateFontString(nil,"OVERLAY","GameFontNormalLarge");title:SetPoint("TOPLEFT",20,-18);title:SetText("Smyrna Workshop")
        local close=CreateFrame("Button",nil,panel,"UIPanelCloseButton");close:SetPoint("TOPRIGHT");panel.SuiteCloseButton=close
        for i,entry in ipairs({{"enabled","Show recipe summary in bag tooltips"}}) do
            local key,label=entry[1],entry[2]
            local b=CreateFrame("CheckButton",nil,panel,"UICheckButtonTemplate");b:SetPoint("TOPLEFT",18,-44-i*28);b:SetChecked(NS.DB.settings[key])
            local t=b:CreateFontString(nil,"OVERLAY","GameFontHighlight");t:SetPoint("LEFT",b,"RIGHT",0,0);t:SetText(label)
            b:SetScript("OnClick",function(self) NS.DB.settings[key]=self:GetChecked();NS.Configure() end)
        end
        scroll=CreateFrame("ScrollFrame",nil,panel,"UIPanelScrollFrameTemplate");scroll:SetPoint("TOPLEFT",20,-125);scroll:SetPoint("BOTTOMRIGHT",-42,20)
        canvas=CreateFrame("Frame",nil,scroll);canvas:SetSize(515,235);scroll:SetScrollChild(canvas)
        listing=CreateFrame("EditBox",nil,canvas);listing:SetPoint("TOPLEFT",0,0);listing:SetMultiLine(true);listing:SetAutoFocus(false);listing:SetFontObject(ChatFontNormal);listing:SetWidth(515);listing:SetHeight(235);listing:SetScript("OnEscapePressed",function(self) self:ClearFocus() end);
        measure=panel:CreateFontString(nil,"BACKGROUND","ChatFontNormal");measure:SetWidth(515);measure:Hide()
        UISpecialFrames[#UISpecialFrames+1]="SmyrnaWorkshopPanel"
    end
    local id=NS.FilterItem
    local rows=id and NS.ItemRecipes(id) or {}
    NS.DB.collapsedProfessions=NS.DB.collapsedProfessions or {}
    local lines={Suite.UIText(id and ("Uses for "..NS.ItemName(id).." - "..#rows.." recipes") or "Choose an item to see its recipe uses","heading"),Suite.UIText("Ctrl + left-click an item or profession reagent to see its recipes.","detail"),Suite.UIText("Bag counts only. Open a profession to confirm learned recipes.","muted"),Suite.UIText("Tools, skill requirements and cooldowns are not checked.","muted")}
    if id and NS.SourceEntries then
        lines[#lines+1]=Suite.UIText("Sources","heading")
        for _,source in ipairs(NS.SourceEntries(id)) do lines[#lines+1]="  "..Suite.UIText(source,"detail") end
    end
    if NS.FilterNotice then lines[#lines+1]=Suite.UIText(NS.FilterNotice,"warning") end
    if #rows==0 then lines[#lines+1]=id and "No uses found in learned recipes or enabled reference data." or "Open a profession to add your learned recipes." end
    local text=table.concat(lines,"\n");listing:SetText(text);measure:SetText(text)
    local top=measure:GetStringHeight()+16;listing:SetHeight(top)
    if NS.RenderVendors then top=NS.RenderVendors(canvas,top,id,measure) end
    local groups={}
    for _,r in ipairs(rows) do
        local group=groups[#groups]
        if not group or group.profession~=r.profession then group={profession=r.profession,recipes={},learned=0};groups[#groups+1]=group end
        group.recipes[#group.recipes+1]=r
        if NS.Known(r)==true then group.learned=group.learned+1 end
    end
    for i,group in ipairs(groups) do
        local section=sections[i]
        if not section then
            section={recipeButtons={}};sections[i]=section
            section.header=CreateFrame("Button",nil,canvas,"UIPanelButtonTemplate");section.header:SetSize(515,25)
            section.header:SetScript("OnClick",function(self)
                NS.DB.collapsedProfessions[self.profession]=not NS.DB.collapsedProfessions[self.profession] or nil
                local offset=scroll:GetVerticalScroll();NS.Open();scroll:SetVerticalScroll(offset)
            end)
            section.body=CreateFrame("EditBox",nil,canvas);section.body:SetMultiLine(true);section.body:SetAutoFocus(false);section.body:SetFontObject(ChatFontNormal);section.body:SetWidth(505);section.body:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
        end
        for _,button in ipairs(section.recipeButtons) do button:Hide() end
        local profession=group.profession
        if NS.ExpandFiltered then NS.DB.collapsedProfessions[profession]=nil end
        local collapsed=NS.DB.collapsedProfessions[profession]
        section.header.profession=profession;section.header:ClearAllPoints();section.header:SetPoint("TOPLEFT",0,-top)
        section.header:SetText(Suite.UIText((collapsed and "[+] " or "[-] ")..profession,"heading").."  "..Suite.UIText(#group.recipes.." recipes  /  "..group.learned.." learned","muted"));section.header:Show();top=top+31
        if collapsed then section.body:SetText("");section.body:Hide()
        else
            local body={};local offset=0
            for recipeIndex,r in ipairs(group.recipes) do
                local blockStart=#body+1
                if r.spell then
                    local button=section.recipeButtons[recipeIndex]
                    if not button then
                        button=CreateFrame("Button",nil,canvas);button:SetSize(505,17)
                        button:SetScript("OnEnter",function(self) GameTooltip:SetOwner(self,"ANCHOR_RIGHT");GameTooltip:SetSpellByID(self.spell);GameTooltip:Show() end)
                        button:SetScript("OnLeave",function() GameTooltip:Hide() end)
                        button:SetScript("OnClick",function(self) if SetItemRef then SetItemRef("spell:"..self.spell,self.recipeName,"LeftButton") end end)
                        section.recipeButtons[recipeIndex]=button
                    end
                    button.spell=r.spell;button.recipeName=r.name;button:ClearAllPoints();button:SetPoint("TOPLEFT",10,-top-offset);button:Show()
                end
                local known=NS.Known(r);local state=known==true and "Learned" or known==false and "Not learned" or "Learning status unknown"
                body[#body+1]=Suite.UIText(r.name,"heading")..Suite.UIText(r.skill and (" (skill "..r.skill..")") or "","detail")
                body[#body+1]="  "..Suite.UIText("Learn via: "..((Suite.RecipeAcquisition and Suite.RecipeAcquisition[r.spell]) or "Source unknown"),"detail")
                local ready=NS.Ready(r)
                body[#body+1]="  "..Suite.UIText(state,known==true and "good" or "muted").."  "..Suite.UIText(ready>0 and ("Materials for "..ready) or "Missing materials",ready>0 and "good" or "warning")
                for _,v in ipairs(r.mats) do local have=NS.Count(v[1]);body[#body+1]="    "..NS.ItemName(v[1]).."  "..Suite.UIText(have.." / "..v[2],have>=v[2] and "good" or "warning") end
                body[#body+1]=""
                measure:SetWidth(505);measure:SetText(table.concat(body,"\n",blockStart,#body))
                offset=offset+measure:GetStringHeight()
            end
            local value=table.concat(body,"\n");section.body:SetText(value);section.body:ClearAllPoints();section.body:SetPoint("TOPLEFT",10,-top)
            measure:SetWidth(505);measure:SetText(value);local height=measure:GetStringHeight()+12;measure:SetWidth(515)
            section.body:SetHeight(height);section.body:Show();top=top+height+6
        end
    end
    NS.ExpandFiltered=nil
    for i=#groups+1,#sections do sections[i].header:Hide();sections[i].body:Hide();for _,button in ipairs(sections[i].recipeButtons) do button:Hide() end end
    NS.Sections=sections
    canvas:SetHeight(math.max(235,top));measure:SetText("")
    scroll:UpdateScrollChildRect();scroll:SetVerticalScroll(0);panel:Show()
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
NS.Events={}
local function Register(event)
    if C_EventUtils and C_EventUtils.IsEventValid and not C_EventUtils.IsEventValid(event) then return end
    local ok=pcall(f.RegisterEvent,f,event)
    if ok then NS.Events[event]=true end
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
    if Suite.IsLootInteraction and Suite.IsLootInteraction(tip.GetOwner and tip:GetOwner()) then return end
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
    if Suite.IsLootInteraction and Suite.IsLootInteraction() then return false end
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
f:SetScript("OnEvent",function(_,event,name)
    if event=="ADDON_LOADED" then
        if name~="SmyrnaSuite" then return end
        NS.Init();NS.Configure()
        if ItemRefTooltip then
            ItemRefTooltip:HookScript("OnTooltipCleared",function(tip) shownIDs[tip]=nil end)
            ItemRefTooltip:HookScript("OnHide",function(tip) shownIDs[tip]=nil end)
        end
        if SetItemRef then hooksecurefunc("SetItemRef",function(link,text,button) NS.ChatItemClick(link,button) end) end
        for _,e in ipairs({"BAG_UPDATE_DELAYED","TRADE_SKILL_SHOW","TRADE_SKILL_LIST_UPDATE","TRADE_SKILL_DATA_SOURCE_CHANGED","TRADE_SKILL_DETAILS_UPDATE","CRAFT_SHOW","CRAFT_UPDATE"}) do Register(e) end
        GameTooltip:HookScript("OnTooltipCleared",function(tip) shownIDs[tip or GameTooltip]=nil end)
        GameTooltip:HookScript("OnHide",function(tip) shownIDs[tip or GameTooltip]=nil end)
        if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Item then
            -- Forever's data-driven tooltip can rebuild lines after SetBagItem hooks.
            -- Append after item processing so native rendering cannot erase our lines.
            NS.hookMode="item post-processing"
            TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item,function(tip,data)
                if (tip~=GameTooltip and tip~=ItemRefTooltip) or not NS.DB.settings.enabled then return end
                local id=data and data.id
                if id==nil then
                    if TooltipUtil and TooltipUtil.GetDisplayedItem then
                        local _,link,displayed=TooltipUtil.GetDisplayedItem(tip)
                        id=displayed or NS.ID(link)
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
    else NS.QueueScan(event=="CRAFT_SHOW" or event=="CRAFT_UPDATE") end
end)

end chunk(name,Module) end

Suite.Loaded[name]=true
Module.Perf=function() if Suite.Memory then Suite.Memory() end end
