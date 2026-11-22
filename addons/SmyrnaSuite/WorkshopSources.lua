local _,Suite=...
local W=Suite.Modules.SmyrnaWorkshop
if not W then return end
local function Public(v) return W.Public(v) end
local function Number(v,min,max) return Public(v) and type(v)=="number" and v==v and v>=min and v<=max end
local function Text(v) return Public(v) and type(v)=="string" and #v>0 and #v<=200 and not v:find("[%c|]") and v or nil end
local function DB()
    local db=W.DB
    db.sources=db.sources or {prices={},vendors={}}
    db.sources.prices=db.sources.prices or {};db.sources.vendors=db.sources.vendors or {}
    return db.sources
end
function W.SourceEntries(id)
    local Data=Suite.ItemSources
    local label=Data and Data.Label(id) or "Source unknown"
    local entries,seen={},{}
    local function Add(value)
        if value~="Source unknown" and not seen[value] then entries[#entries+1]=value;seen[value]=true end
    end
    local crafted=Data and Data.crafted and Data.crafted[id]
    if crafted then Add("Crafted - "..crafted) end
    if W.DB and DB().prices[id] then Add("Merchant supply") end
    for part in (label.." / "):gmatch("(.-) / ") do Add(part) end
    if #entries==0 then entries[1]="Source unknown" end
    return entries
end
function W.SourceLabel(id,full)
    local entries=W.SourceEntries(id)
    if full or #entries<=3 then return table.concat(entries," / ") end
    return table.concat(entries," / ",1,3).." / ..."
end
local observedCount
function W.RecordMerchant()
    local Data=Suite.ItemSources
    local modern=C_MerchantFrame and C_MerchantFrame.GetItemInfo
    if not W.DB or not W.DB.settings.enabled or not GetMerchantNumItems or not (modern or GetMerchantItemInfo) or not (GetMerchantItemID or GetMerchantItemLink) then return end
    local guid=UnitGUID and UnitGUID("npc")
    local npc=Public(guid) and type(guid)=="string" and tonumber(guid:match("^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-"))
    local name=UnitName and Text(UnitName("npc"))
    if not npc or not name then return end
    local db=DB()
    if not observedCount then observedCount=0;for _,prices in pairs(db.prices) do for _ in pairs(prices) do observedCount=observedCount+1 end end end
    local map=C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    map=Number(map,1,1000000) and map or 0
    local x,y
    local pos=map>0 and C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(map,"player")
    if pos then x,y=pos:GetXY();if not Number(x,0,1) or not Number(y,0,1) then x,y=nil,nil end end
    local zone=GetRealZoneText and Text(GetRealZoneText()) or "Location unknown"
    local count=GetMerchantNumItems()
    if not Number(count,0,10000) then return end
    for i=1,math.min(count,200) do
        local id=GetMerchantItemID and GetMerchantItemID(i) or (GetMerchantItemLink and W.ID(GetMerchantItemLink(i)))
        if id and ((Data and Data.Material(id)) or (W.ReferenceManifest and W.ReferenceManifest[id]) or W.Uses(id)) then
            local price,quantity,special
            if modern then
                local info=modern(i)
                if info then price,quantity,special=info.price,info.stackCount,info.hasExtendedCost end
            else
                local _,_,p,q,_,_,seventh,eighth=GetMerchantItemInfo(i)
                price,quantity=p,q
                if eighth~=nil then special=eighth else special=seventh end
            end
            if Number(price,0,10^12) and Number(quantity,1,10000) and Public(special) then
                local prices=db.prices[id]
                if not prices then prices={};db.prices[id]=prices end
                if prices[npc] or observedCount<4096 then
                    if not prices[npc] then observedCount=observedCount+1 end
                    prices[npc]={price,quantity,not not special,time()}
                    db.vendors[npc]={name,zone,map,x and math.floor(x*1000+.5)/10,y and math.floor(y*1000+.5)/10}
                end
            end
        end
    end
end
function W.PriceLabel(price)
    if not price then return "Price unknown - visit merchant" end
    if price[3] then return "Special currency - check merchant" end
    local copper,quantity=price[1],price[2]
    local unit=copper%quantity==0
    if unit then copper=copper/quantity end
    local parts={};local gold=math.floor(copper/10000);local silver=math.floor(copper/100)%100;local c=copper%100
    if gold>0 then parts[#parts+1]=gold.."g" end
    if silver>0 then parts[#parts+1]=silver.."s" end
    if c>0 or #parts==0 then parts[#parts+1]=c.."c" end
    return "Last seen: "..table.concat(parts," ")..(unit and " each" or (" per "..quantity))
end
function W.VendorRows(id)
    local Data=Suite.ItemSources
    local db=DB();local rows,seen={},{}
    local function Add(npc)
        if seen[npc] then return end;seen[npc]=true
        local ref=Data and Data.Vendor(npc);local own=db.vendors[npc]
        if not ref and not own then return end
        rows[#rows+1]={id=npc,name=own and own[1] or ref.name,zone=own and own[2] or ref.zone,map=own and own[3] or ref.map,x=own and own[4] or ref.x,y=own and own[5] or ref.y,faction=ref and ref.faction,price=db.prices[id] and db.prices[id][npc]}
    end
    local source=Data and Data.items[id]
    for number in (source and source[2] or ""):gmatch("%d+") do Add(tonumber(number)) end
    for npc in pairs(db.prices[id] or {}) do Add(npc) end
    local map=C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    local side=UnitFactionGroup and UnitFactionGroup("player")
    local faction=side=="Horde" and "H" or side=="Alliance" and "A"
    local function Rank(row)
        local opposing=faction and row.faction and row.faction~="AH" and row.faction~=faction
        return (opposing and 10 or 0)+(row.map==map and 0 or 1)
    end
    table.sort(rows,function(a,b) local x,y=Rank(a),Rank(b);if x~=y then return x<y end;if a.name~=b.name then return a.name<b.name end;return a.id<b.id end)
    return rows
end
local header,body,previous,nextButton
local page,item=1
function W.RenderVendors(canvas,top,id,measure)
    if item~=id then item=id;page=1 end
    local rows=id and W.VendorRows(id) or {}
    if #rows==0 then if header then header:Hide();body:Hide();previous:Hide();nextButton:Hide() end;return top end
    if not header then
        header=CreateFrame("Button",nil,canvas,"UIPanelButtonTemplate");header:SetSize(515,25)
        header:SetScript("OnClick",function() DB().expanded=not DB().expanded;W.Open() end)
        body=CreateFrame("EditBox",nil,canvas);body:SetMultiLine(true);body:SetAutoFocus(false);body:SetFontObject(ChatFontNormal);body:SetWidth(505);body:SetScript("OnEscapePressed",function(self) self:ClearFocus() end)
        previous=CreateFrame("Button",nil,canvas,"UIPanelButtonTemplate");previous:SetSize(60,23);previous:SetText("Back");previous:SetScript("OnClick",function() page=math.max(1,page-1);W.Open() end)
        nextButton=CreateFrame("Button",nil,canvas,"UIPanelButtonTemplate");nextButton:SetSize(60,23);nextButton:SetText("Next");nextButton:SetScript("OnClick",function() page=page+1;W.Open() end)
    end
    header:ClearAllPoints();header:SetPoint("TOPLEFT",0,-top);header:SetText(Suite.UIText((DB().expanded and "[-] " or "[+] ").."Merchants ("..#rows..")","detail"));header:Show();top=top+31
    if not DB().expanded then body:Hide();previous:Hide();nextButton:Hide();return top end
    local pages=math.max(1,math.ceil(#rows/10));page=math.min(page,pages)
    local lines={Suite.UIText("Reference locations. Prices update when you visit a merchant.","muted")}
    for i=(page-1)*10+1,math.min(page*10,#rows) do
        local row=rows[i];local where=row.zone or "Location unknown"
        if row.x and row.y then where=where..string.format(" (%.1f, %.1f)",row.x,row.y) end
        local side=row.faction=="A" and " [Alliance]" or row.faction=="H" and " [Horde]" or ""
        lines[#lines+1]=Suite.UIText(row.name,"heading")..Suite.UIText(side,"muted")
        lines[#lines+1]="  "..where.."  /  "..Suite.UIText(W.PriceLabel(row.price),row.price and "good" or "muted")
        lines[#lines+1]=""
    end
    lines[#lines+1]="Page "..page.." / "..pages
    local text=table.concat(lines,"\n");measure:SetWidth(505);measure:SetText(text);local height=measure:GetStringHeight()+12;measure:SetWidth(515)
    body:ClearAllPoints();body:SetPoint("TOPLEFT",10,-top);body:SetText(text);body:SetHeight(height);body:Show();top=top+height
    previous:ClearAllPoints();previous:SetPoint("TOPLEFT",10,-top);previous:SetEnabled(page>1);previous:Show()
    nextButton:ClearAllPoints();nextButton:SetPoint("TOPLEFT",76,-top);nextButton:SetEnabled(page<pages);nextButton:Show()
    return top+35
end
local driver=CreateFrame("Frame");driver:RegisterEvent("MERCHANT_SHOW");driver:RegisterEvent("MERCHANT_UPDATE")
driver:SetScript("OnEvent",function() W.RecordMerchant() end)
