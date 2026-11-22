local _,Suite=...
local name="SmyrnaFieldDiary"
Suite.Versions[name]="0.3.0"
if Suite.Config.features[name]==false then return end
local Module={}
Suite.Modules[name]=Module

-- Internal module source: Core.lua
do local function chunk(...)
local _, NS = ...
local C = {}
NS.Core = C
C.CELL = 50
C.CAP = 2000
C.RETENTION = 30 * 86400
C.LootThresholds={{0,"Any value"},{100,"1 silver"},{500,"5 silver"},{1000,"10 silver"},{2500,"25 silver"},{5000,"50 silver"},{10000,"1 gold"},{50000,"5 gold"}}
function C.ThresholdLabel(value)
 for _,entry in ipairs(C.LootThresholds) do if entry[1]==value then return entry[2] end end
end
function C.Now() return GetServerTime and GetServerTime() or time() end
C.kinds = { mine = true, herb = true, skin = true, reagent = true }
C.colors = { mine = {1, .7, .2}, herb = {.2, 1, .4}, skin = {.8, .5, .25}, valuable = {.65, .6, 1}, reagent = {.3,.75,1} }
-- Compact persisted arrays: 1 map, 2 cellX, 3 cellY, 4 kind, 5 observations,
-- 6 units, 7 vendorCopper, 8 revision, 9 lastSeen, 10 itemTotals,
-- 11 namedItemCount, 12 lastSender (shared), 13 origin (shared).
-- An item-total array is {units, vendorCopper}. CSV exposes named columns.

function C.Public(v)
    return not (issecretvalue and issecretvalue(v))
end
function C.Number(v, low, high, integer)
    return C.Public(v) and type(v) == "number" and v == v and v >= low and v <= high and (not integer or v % 1 == 0)
end
function C.Key(map, x, y, kind)
    return map .. ":" .. x .. ":" .. y .. ":" .. kind
end
function C.NewStore()
    return { records = {}, queue = {}, slots = {}, cursor = 1, count = 0 }
end
function C.New(origin)
    return { version = 2, origin = origin, own = C.NewStore(), shared = C.NewStore(),
        settings = { tracking = true, worldmap = false, minimap = false, areaRings = false, launcher = true, receive = false,
            includeShared = true, mine = true, herb = true, skin = true, reagent = true,
            grayOnly = true, threshold = 1000, span = 4 }, revision = 0 }
end

function C.Insert(store, key, record)
    if store.records[key] then store.records[key] = record; return end
    local slot = store.cursor
    local previous = store.queue[slot]
    if previous and store.slots[previous]==slot and store.records[previous] then store.records[previous] = nil; store.slots[previous]=nil; store.count = store.count - 1 end
    store.queue[slot] = key
    store.cursor = slot % C.CAP + 1
    store.records[key] = record
    store.slots[key] = slot
    store.count = store.count + 1
end

function C.Prune(store, now)
    local removed = 0
    for key, record in pairs(store.records) do
        if not C.Number(record[9], 0, now + 300) or now - record[9] > C.RETENTION then
            store.records[key] = nil; store.slots[key]=nil; store.count = math.max(0, store.count - 1); removed = removed + 1
        end
    end
    return removed
end

-- All positions are quantized immediately. No raw node coordinates are saved.
function C.Record(db, obs)
    if not C.kinds[obs.kind] or not C.Number(obs.map, 1, 1000000, true) or
        not C.Number(obs.x, 0, 1) or not C.Number(obs.y, 0, 1) or
        not C.Number(obs.width, 1, 200000) or not C.Number(obs.height, 1, 200000) or
        not C.Number(obs.units, 1, 100000, true) or not C.Number(obs.value, 0, 1000000000, true) or
        not C.Number(obs.gathers, 0, 1, true) or not C.Number(obs.time, 1, 10000000000, true) then return false end
    local gx = math.floor(math.min(obs.x * obs.width, obs.width - .001) / C.CELL)
    local gy = math.floor(math.min(obs.y * obs.height, obs.height - .001) / C.CELL)
    local key = C.Key(obs.map, gx, gy, obs.kind)
    local r = db.own.records[key]
    if not r then
        r = { obs.map, gx, gy, obs.kind, 0, 0, 0, 0, obs.time, {}, 0 }
        C.Insert(db.own, key, r)
    end
    r[5] = r[5] + obs.gathers; r[6] = r[6] + obs.units; r[7] = r[7] + obs.value
    r[8] = r[8] + 1; r[9] = obs.time
    if C.Number(obs.item, 1, 10000000, true) then
        local itemKey = obs.item
        if not r[10][itemKey] and r[11] >= 8 then itemKey = 0 end
        if not r[10][itemKey] then r[10][itemKey] = { 0, 0 }; if itemKey ~= 0 then r[11] = r[11] + 1 end end
        local item = r[10][itemKey]
        item[1] = item[1] + obs.units; item[2] = item[2] + obs.value
    end
    db.revision = db.revision + 1
    return true, r
end

function C.Aggregate(db, map, width, height)
    local areas, output = {}, {}
    local span = db.settings.span
    local function Add(r, shared)
        if r[1] ~= map or not C.kinds[r[4]] or not db.settings[r[4]] then return end
        local ax, ay = math.floor(r[2] / span), math.floor(r[3] / span)
        local key = ax .. ":" .. ay .. ":" .. r[4]
        local area = areas[key]
        if not area then
            area = { key = key, kind = r[4], ax = ax, ay = ay, own = 0, shared = 0, units = 0, value = 0, last = 0, hot = {}, professions = {} }
            areas[key] = area; output[#output + 1] = area
        end
        if shared then area.shared = area.shared + r[5] else area.own = area.own + r[5] end
        area.units = area.units + r[6]; area.value = area.value + r[7]; area.last = math.max(area.last, r[9])
        for item in pairs(r[10] or {}) do for _,profession in ipairs(Suite.ReagentProfessions[item] or {}) do area.professions[profession]=true end end
        local hotKey = (r[2] % span) .. ":" .. (r[3] % span)
        area.hot[hotKey] = (area.hot[hotKey] or 0) + r[5]
    end
    for _, r in pairs(db.own.records) do Add(r, false) end
    if db.settings.includeShared then for _, r in pairs(db.shared.records) do Add(r, true) end end
    for _, a in ipairs(output) do
        local x0, y0 = a.ax * span * C.CELL, a.ay * span * C.CELL
        local x1, y1 = math.min(width, x0 + span * C.CELL), math.min(height, y0 + span * C.CELL)
        a.x = (x0 + x1) / (2 * width); a.y = (y0 + y1) / (2 * height)
        a.radius = math.sqrt((x1 - x0)^2 + (y1 - y0)^2) / 2
        a.rx = a.radius / width; a.ry = a.radius / height
        a.total = a.own + a.shared
        local best = -1
        for key, count in pairs(a.hot) do
            if count > best or (count == best and key < (a.hotKey or "~")) then best = count; a.hotKey = key end
        end
        a.hotCount = best
        local hx, hy = a.hotKey:match("^(%d+):(%d+)$")
        a.hx = math.min(1, (x0 + (tonumber(hx) + .5) * C.CELL) / width)
        a.hy = math.min(1, (y0 + (tonumber(hy) + .5) * C.CELL) / height)
    end
    table.sort(output, function(a,b) if a.total == b.total then return a.key < b.key end return a.total > b.total end)
    return output
end

function C.Encode(origin, r)
    return table.concat({ "1", origin, r[1], r[2], r[3], r[4], r[8], r[5], r[6], r[7], r[9] }, "|")
end

function C.Decode(message, now)
    if not C.Public(message) or type(message) ~= "string" or #message > 220 then return nil end
    local version, origin, map, gx, gy, kind, rev, n, units, value, last = message:match("^(%d+)|([%w]+)|(%d+)|(%d+)|(%d+)|(%a+)|(%d+)|(%d+)|(%d+)|(%d+)|(%d+)$")
    if version ~= "1" or #origin > 24 or #origin < 8 or not C.kinds[kind] then return nil end
    local r = { tonumber(map), tonumber(gx), tonumber(gy), kind, tonumber(n), tonumber(units), tonumber(value), tonumber(rev), tonumber(last) }
    if not C.Number(r[1],1,1000000,true) or not C.Number(r[2],0,3999,true) or not C.Number(r[3],0,3999,true)
        or not C.Number(r[8],1,100000000,true) or not C.Number(r[5],1,10000000,true)
        or not C.Number(r[6],r[5],100000000,true) or not C.Number(r[7],0,1000000000000,true)
        or not C.Number(r[9],now-C.RETENTION,now+300,true) then return nil end
    return origin, r
end

function C.Merge(db, sender, origin, r)
    if origin == db.origin then return false end
    local key = origin .. ":" .. C.Key(r[1],r[2],r[3],r[4])
    local old = db.shared.records[key]
    if old and (r[8] <= old[8] or r[5] < old[5] or r[6] < old[6] or r[7] < old[7]) then return false end
    r[12] = sender; r[13] = origin
    C.Insert(db.shared, key, r)
    db.revision = db.revision + 1
    return true
end

-- North-up normalized map coordinates; facing uses the game's counterclockwise angle.
function C.Project(x, y, px, py, width, height, radius, facing)
    local dx, dy = (x-px)*width, (py-y)*height
    if facing then
        local c,s = math.cos(facing),math.sin(facing)
        dx,dy = dx*c + dy*s, dy*c - dx*s
    end
    if dx*dx + dy*dy > (radius*.88)^2 then return nil end
    return dx/radius, dy/radius
end

function C.CSV(db, map)
    local lines = { "row_type,source,map,kind,cell_x,cell_y,observations,units,vendor_copper,last,item_id,item_units,item_vendor_copper" }
    local function Add(store, source)
        for _, r in pairs(store.records) do
            if not map or r[1] == map then
                local provenance=source=="shared" and ("shared:"..(r[12] or "unknown")..":"..(r[13] or "unknown")) or ("own:"..db.origin)
                provenance='"'..provenance:gsub('"','""')..'"'
                local prefix = table.concat({provenance,r[1],r[4],r[2],r[3],r[5],r[6],r[7],r[9]},",")
                lines[#lines+1]="bucket,"..prefix..",,,"
                if r[10] then
                    for id,item in pairs(r[10]) do
                        lines[#lines+1]=table.concat({"item",provenance,r[1],r[4],r[2],r[3],"","","",r[9],id,item[1],item[2]},",")
                    end
                end
            end
        end
    end
    Add(db.own,"own"); Add(db.shared,"shared")
    return table.concat(lines,"\n")
end

end chunk(name,Module) end

-- Internal module source: Collector.lua
do local function chunk(...)
local _, NS = ...
local C = NS.Core
local session, context
local waiting, waitingCount = {}, 0
local frame = CreateFrame("Frame")
local active = false
local spells = { [2575]="mine", [2576]="mine", [3564]="mine", [10248]="mine", [29354]="mine",
    [2366]="herb", [2368]="herb", [3570]="herb", [11993]="herb", [8613]="skin", [8617]="skin", [8618]="skin", [10768]="skin" }
local events = {"UNIT_SPELLCAST_START","UNIT_SPELLCAST_SUCCEEDED","UNIT_SPELLCAST_FAILED","UNIT_SPELLCAST_INTERRUPTED","LOOT_READY","LOOT_OPENED","LOOT_CLOSED","CHAT_MSG_LOOT","GET_ITEM_INFO_RECEIVED"}

local gatherNames={}
NS.Diagnostics={casts=0,windows=0,receipts=0,saved=0,positionFailures=0,lastSpell=0}
local diag=NS.Diagnostics
function NS.Diagnose()
 NS.Say(string.format("This session: %d gathering casts; %d loot windows; %d loot messages; %d saved items; %d missing positions. Last player spell: %s",diag.casts,diag.windows,diag.receipts,diag.saved,diag.positionFailures,tostring(diag.lastSpell)))
 NS.Say("Tracking: "..tostring(NS.DB.settings.tracking).."; world map: "..tostring(NS.DB.settings.worldmap).."; minimap: "..tostring(NS.DB.settings.minimap))
 if NS.DrawWorld then NS.AttachMap();NS.DrawWorld();local m=NS.MapDisplay;NS.Say("Map "..tostring(m.map)..": "..m.drawn.." markers drawn / "..m.areas.." groups. "..tostring(m.reason)) end
end
local function SpellName(id)
    local fn=(C_Spell and C_Spell.GetSpellName) or GetSpellInfo
    if fn then local ok,name=pcall(fn,id);if ok and C.Public(name) and type(name)=="string" then return name end end
end
local function SpellKind(id)
    if not C.Public(id) or type(id)~="number" then return end
    if spells[id] then return spells[id] end
    local name=SpellName(id)
    return name and gatherNames[name]
end
local function FormatPattern(format)
    if not format then return nil end
    local text = format:gsub("%%%d+%$s", "\001"):gsub("%%%d+%$d", "\002"):gsub("%%s", "\001"):gsub("%%d", "\002")
    text = text:gsub("([%^%$%(%)%%%.%[%]%*%+%-%?])", "%%%1")
    return "^" .. text:gsub("\001", "(.+)"):gsub("\002", "(%%d+)") .. "$"
end
NS.LootPattern = FormatPattern
local singlePattern, multiplePattern

function NS.Position()
    if not C_Map or not C_Map.GetMapWorldSize then return nil end
    local map = C_Map.GetBestMapForUnit("player")
    if not C.Number(map,1,1000000,true) then return nil end
    local pos = C_Map.GetPlayerMapPosition(map,"player")
    if not pos then return nil end
    local x,y = pos:GetXY()
    local width,height = C_Map.GetMapWorldSize(map)
    if not C.Number(x,0,1) or not C.Number(y,0,1) or not C.Number(width,1,200000) or not C.Number(height,1,200000) then return nil end
    return {map=map,x=x,y=y,width=width,height=height}
end

local function Info(id)
    local get = C_Item and C_Item.GetItemInfo or GetItemInfo
    if not get then return nil end
    local name,_,quality,_,_,_,_,_,_,_,price = get(id)
    if not C.Public(name) or not name or not C.Number(quality,0,8,true) or not C.Number(price,0,1000000000,true) then return nil end
    return quality,price
end

local function Commit(obs, ownerSession)
    local db = NS.DB
    if obs.kind=="valuable" and Suite.ReagentProfessions[obs.item] then obs.kind="reagent" end
    if not db.settings.tracking then return true end
    if not db.settings[obs.kind] then return true end
    local quality,price = Info(obs.item)
    if quality == nil then return false end
    if obs.kind == "valuable" and (price < db.settings.threshold or quality~=0) then return true end
    obs.value = price * obs.units
    obs.gathers = ownerSession.counted[obs.kind] and 0 or 1
    local ok = C.Record(db,obs)
    if ok then diag.saved=diag.saved+1;ownerSession.counted[obs.kind]=true; NS.Dirty() end
    return true
end

local function Queue(obs, ownerSession)
    if Commit(obs,ownerSession) then return end
    for i=#waiting,1,-1 do
        if C.Now()-waiting[i].obs.time>30 then table.remove(waiting,i); waitingCount=waitingCount-1 end
    end
    if waitingCount >= 64 then NS.skipped = (NS.skipped or 0) + 1; return end
    waiting[#waiting+1] = {obs=obs,session=ownerSession}
    waitingCount=waitingCount+1
    if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(obs.item) end
end

local function Retry(id)
    for i=#waiting,1,-1 do
        local entry=waiting[i]
        if C.Now()-entry.obs.time > 30 or (entry.obs.item==id and Commit(entry.obs,entry.session)) then
            table.remove(waiting,i); waitingCount=waitingCount-1
        end
    end
end

local function KindForSlot(slot, gathering)
    local source = GetLootSourceInfo and GetLootSourceInfo(slot)
    if not C.Public(source) then return nil end
    local creature = type(source)=="string" and source:match("^Creature%-") ~= nil
    local sourceKind=creature and "creature" or (type(source)=="string" and source:match("^GameObject%-") and "object")
    if gathering and ((gathering=="skin" and creature) or (gathering~="skin" and not creature)) then return gathering,sourceKind end
    if creature then return "valuable",sourceKind end
    return nil,sourceKind
end

local function Snapshot()
    if session and GetTime()-session.opened < .2 then return end
    local pos = NS.Position()
    if not pos then diag.positionFailures=diag.positionFailures+1;session=nil; return end
    diag.windows=diag.windows+1
    local s={pos=pos,opened=GetTime(),slots={},counted={}}
    local gathering = context and GetTime()-context.at <= 10 and context.kind
    s.gathering=gathering
    context=nil
    if IsFishingLoot and IsFishingLoot() then session=nil; return end
    if LootIsFromItem and LootIsFromItem() then session=nil; return end
    for slot=1,math.min(GetNumLootItems(),64) do
        local link=GetLootSlotLink(slot)
        if C.Public(link) and type(link)=="string" then
            local id=tonumber(link:match("item:(%d+)"))
            local _,_,quantity=GetLootSlotInfo(slot)
            local kind,sourceKind=KindForSlot(slot,gathering)
            if id and (kind or sourceKind=="object") and C.Number(quantity,1,100000,true) then
                local record=s.slots[id]
                if not record then record={remaining=0,kind=kind,source=sourceKind}; s.slots[id]=record end
                record.remaining=record.remaining+quantity
            end
        end
    end
    session=s
end

local function Receipt(message)
    diag.receipts=diag.receipts+1
    if not session or GetTime()-session.opened > 15 or not C.Public(message) or type(message)~="string" then return end
    local link,quantity
    if multiplePattern then link,quantity=message:match(multiplePattern) end
    if link and tonumber(link) and type(quantity)=="string" and quantity:find("item:",1,true) then link,quantity=quantity,link end
    if not link and singlePattern then link=message:match(singlePattern); quantity=1 end
    if not link then return end
    local id=tonumber(link:match("item:(%d+)")); quantity=tonumber(quantity)
    local slot=id and session.slots[id]
    if not slot or not C.Number(quantity,1,slot.remaining,true) then return end
    local kind=slot.kind
    if not kind and slot.source=="object" then
        local gathering=session.gathering or (context and GetTime()-context.at<=10 and context.kind)
        if gathering and gathering~="skin" then kind=gathering;session.gathering=gathering;context=nil end
    end
    if not kind then return end
    if kind~="valuable" then context=nil end
    slot.remaining=slot.remaining-quantity
    local pos=session.pos
    Queue({map=pos.map,x=pos.x,y=pos.y,width=pos.width,height=pos.height,
        kind=kind,item=id,units=quantity,time=C.Now()},session)
end
NS.HandleReceipt=Receipt

frame:SetScript("OnEvent",function(_,event,...)
    if event=="UNIT_SPELLCAST_START" or event=="UNIT_SPELLCAST_SUCCEEDED" then
        local unit,_,id=...
        if unit=="player" then if C.Public(id) then diag.lastSpell=id end;local kind=SpellKind(id);if kind then diag.casts=diag.casts+1;context={kind=kind,at=GetTime()} end end
    elseif event=="UNIT_SPELLCAST_FAILED" or event=="UNIT_SPELLCAST_INTERRUPTED" then
        local unit=...;if unit=="player" then context=nil end
    elseif event=="LOOT_READY" then Snapshot()
    elseif event=="LOOT_OPENED" then if not session then Snapshot() end
    elseif event=="CHAT_MSG_LOOT" then Receipt(...)
    elseif event=="GET_ITEM_INFO_RECEIVED" then Retry(...)
    elseif event=="LOOT_CLOSED" then
        context=nil
        local previous=session
        C_Timer.After(2,function() if session==previous then session=nil end end)
    end
end)

function NS.ConfigureCollector()
    local s=NS.DB.settings
    local enabled=s.tracking and (s.mine or s.herb or s.skin or s.valuable or s.reagent)
    if enabled==active then return end
    active=enabled
    if enabled then
        for id,kind in pairs({[2575]="mine",[2366]="herb",[8613]="skin"}) do local name=SpellName(id);if name then gatherNames[name]=kind end end
    end
    for _,event in ipairs(events) do if enabled then frame:RegisterEvent(event) else frame:UnregisterEvent(event) end end
    singlePattern=FormatPattern(LOOT_ITEM_SELF)
    multiplePattern=FormatPattern(LOOT_ITEM_SELF_MULTIPLE)
    if not enabled then session=nil; context=nil; wipe(waiting); waitingCount=0 end
end

end chunk(name,Module) end

-- Internal module source: Sharing.lua
do local function chunk(...)
local _,NS=...
local C=NS.Core
local PREFIX="SMYRNAFD1"
local frame=CreateFrame("Frame")
local ticker,queue,index
local rates,identities={},{}
local cursors={}
local globalSecond,globalCount=0,0

local function Stop()
    if ticker then ticker:Cancel(); ticker=nil end
    queue=nil; index=nil
end
NS.StopSharing=Stop

function NS.Share(channel)
    if ticker then NS.Say("A share is already in progress."); return end
    if not C_ChatInfo or not C_ChatInfo.SendAddonMessage then NS.Say("Addon sharing API unavailable."); return end
    if C_ChatInfo.AreOutgoingAddonChatMessagesRestricted and C_ChatInfo.AreOutgoingAddonChatMessagesRestricted() then NS.Say("Addon messages are restricted on this realm."); return end
    if channel=="GUILD" then
        if not IsInGuild() then NS.Say("Join a guild first."); return end
    elseif channel=="PARTY" then
        if not IsInGroup() then NS.Say("Join a party first."); return end
        if IsInRaid() then channel="RAID" end
    else return end
    local pos=NS.Position()
    if not pos then NS.Say("No supported zone position."); return end
    queue={}
    for _,r in pairs(NS.DB.own.records) do
        if C.kinds[r[4]] and r[1]==pos.map and r[5]>0 and C.Now()-r[9]<=C.RETENTION then queue[#queue+1]=r end
    end
    if #queue==0 then queue=nil; NS.Say("No own observations in this zone to share."); return end
    table.sort(queue,function(a,b) return C.Key(a[1],a[2],a[3],a[4])<C.Key(b[1],b[2],b[3],b[4]) end)
    local cursorKey=pos.map..":"..channel
    local first=cursors[cursorKey] or 1
    if first>#queue then first=1 end
    local total=#queue
    local last=math.min(total,first+119)
    local batch={}
    for i=first,last do batch[#batch+1]=queue[i] end
    queue=batch
    local nextCursor=last==total and 1 or last+1
    -- Serialize a fixed snapshot now; no imported data is relayed.
    for i,r in ipairs(queue) do queue[i]=C.Encode(NS.DB.origin,r) end
    index=1
    NS.Say("Sharing finds "..first.."-"..last.." of "..total.." with your "..(channel=="GUILD" and "guild" or "group")..". Click Share again for more.")
    ticker=C_Timer.NewTicker(.5,function()
        if (channel=="GUILD" and not IsInGuild()) or (channel~="GUILD" and not IsInGroup()) then Stop(); NS.Say("Share stopped: group/guild unavailable."); return end
        local message=queue and queue[index]
        if not message then Stop(); NS.Say("Share finished."); return end
        C_ChatInfo.SendAddonMessage(PREFIX,message,channel)
        index=index+1
        if index>#queue then cursors[cursorKey]=nextCursor; Stop(); NS.Say("Share finished.") end
    end)
end

function NS.Receive(prefix,message,channel,sender)
    if not NS.DB.settings.receive or prefix~=PREFIX or (channel~="GUILD" and channel~="PARTY" and channel~="RAID") then return false end
    if not C.Public(sender) or type(sender)~="string" or #sender>80 or not sender:match("^[^|,%c]+$") then return false end
    local second=math.floor(GetTime())
    if globalSecond~=second then globalSecond=second; globalCount=0 end
    if globalCount>=8 then return false end
    globalCount=globalCount+1
    local rate=rates[sender]
    if not rate then
        for peer,entry in pairs(rates) do
            if second-entry.second>60 then rates[peer]=nil; identities[peer]=nil end
        end
        local n=0; for _ in pairs(rates) do n=n+1 end
        if n>=16 then return false end
        rate={second=second,count=0}; rates[sender]=rate
    end
    if rate.second~=second then rate.second=second; rate.count=0 end
    if rate.count>=4 then return false end
    rate.count=rate.count+1
    local origin,r=C.Decode(message,C.Now())
    if not origin then return false end
    if identities[sender] and identities[sender]~=origin then return false end
    identities[sender]=origin
    local info=C_Map.GetMapInfo(r[1])
    local width,height=C_Map.GetMapWorldSize(r[1])
    if not info or not C.Number(width,1,200000) or not C.Number(height,1,200000) or r[2]*50>=width or r[3]*50>=height then return false end
    if C.Merge(NS.DB,sender,origin,r) then NS.Dirty(); return true end
    return false
end

frame:SetScript("OnEvent",function(_,_,...) NS.Receive(...) end)
function NS.ConfigureSharing()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
    if NS.DB.settings.receive then frame:RegisterEvent("CHAT_MSG_ADDON") else frame:UnregisterEvent("CHAT_MSG_ADDON"); wipe(rates); wipe(identities) end
end

end chunk(name,Module) end

-- Internal module source: Maps.lua
do local function chunk(...)
local _,NS=...
local C=NS.Core
local provider,miniTicker
local miniPins={}
local caches={}
local cacheClock=0
local mapPending=false

function NS.Areas(map)
    if not map then return {} end
    cacheClock=cacheClock+1
    for _,entry in ipairs(caches) do
        if entry.map==map and entry.revision==NS.DB.revision then entry.used=cacheClock; return entry.areas end
    end
    local width,height=C_Map.GetMapWorldSize(map)
    if not C.Number(width,1,200000) or not C.Number(height,1,200000) then return {} end
    local areas=C.Aggregate(NS.DB,map,width,height)
    local slot
    for i,entry in ipairs(caches) do if entry.map==map then slot=i; break end end
    if not slot then slot=#caches<2 and (#caches+1) or (caches[1].used<caches[2].used and 1 or 2) end
    caches[slot]={map=map,revision=NS.DB.revision,used=cacheClock,areas=areas}
    return areas
end

function NS.AreaTooltip(owner,area)
    GameTooltip:SetOwner(owner,"ANCHOR_RIGHT")
    local names={mine="Mining finds",herb="Herb finds",skin="Skinning finds",valuable="Valuable loot",reagent="Crafting reagents"}
    GameTooltip:SetText(names[area.kind])
    GameTooltip:AddLine("My visits: "..area.own,1,1,1)
    GameTooltip:AddLine("Shared visits: "..area.shared,.7,.8,1)
    GameTooltip:AddLine("Items found: "..area.units,1,1,1)
    local professions={};for name in pairs(area.professions or {}) do professions[#professions+1]=name=="FirstAid" and "First Aid" or name end;table.sort(professions)
    if #professions>0 then GameTooltip:AddLine("Used by: "..table.concat(professions,", "),.4,.8,1,true) end
    GameTooltip:AddLine("Shop value: "..NS.Money(area.value),1,.8,.3)
    GameTooltip:AddLine("Busiest spot: "..area.hotCount.." visits",.8,.8,.8,true)
    GameTooltip:AddLine("Past finds only. A node may not be available now.",.7,.7,.7,true)
    GameTooltip:Show()
end

local worldPins={}
local mapHooked
NS.MapDisplay={drawn=0,areas=0}
local function HideWorld()
    for _,pin in ipairs(worldPins) do pin:Hide() end
    NS.MapDisplay.drawn=0
end
function NS.DrawWorld()
    HideWorld()
    local state=NS.MapDisplay;state.areas=0
    if not NS.DB or not WorldMapFrame then state.reason="Map not loaded";return end
    if not NS.DB.settings.worldmap then state.reason="Map markers switched off";return end
    if not WorldMapFrame:IsShown() then state.reason="Map closed";return end
    local map=WorldMapFrame
    local canvas=map.GetCanvas and map:GetCanvas()
    local mapID=map.GetMapID and map:GetMapID()
    state.map=mapID
    if not canvas or not mapID then state.reason="Map canvas unavailable";return end
    local width,height=canvas:GetWidth(),canvas:GetHeight()
    if width<=0 or height<=0 then state.reason="Map canvas has no size";return end
    local areas=NS.Areas(mapID);state.areas=#areas
    local zoom=map.GetCanvasScale and map:GetCanvasScale() or 1
    if not C.Number(zoom,.01,100) then zoom=1 end
    local scale=1/zoom
    local level=canvas:GetFrameLevel()+30
    if map.GetPinFrameLevelsManager then
        local manager=map:GetPinFrameLevelsManager()
        if manager then level=manager:GetValidFrameLevel("PIN_FRAME_LEVEL_TOPMOST")+1 end
    end
    for i=1,math.min(#areas,64) do
        local area=areas[i];local pin=worldPins[i]
        if not pin then
            pin=CreateFrame("Frame",nil,canvas);pin:SetSize(16,16);pin:EnableMouse(true)
            pin.border=pin:CreateTexture(nil,"ARTWORK");pin.border:SetSize(12,12);pin.border:SetPoint("CENTER");pin.border:SetColorTexture(.04,.04,.04,1)
            pin.dot=pin:CreateTexture(nil,"OVERLAY");pin.dot:SetSize(8,8);pin.dot:SetPoint("CENTER")
            pin.count=pin:CreateFontString(nil,"OVERLAY","GameFontNormalSmall");pin.count:SetPoint("LEFT",pin,"RIGHT",0,0)
            pin.ring=pin:CreateTexture(nil,"BACKGROUND");pin.ring:SetTexture("Interface\\Minimap\\UI-Minimap-Ping")
            pin:SetScript("OnEnter",function(self) if self.area then NS.AreaTooltip(self,self.area) end end)
            pin:SetScript("OnLeave",function() GameTooltip:Hide() end)
            worldPins[i]=pin
        end
        pin.area=area;pin:SetParent(canvas);pin:SetFrameLevel(level);pin:SetScale(scale)
        pin:ClearAllPoints();pin:SetPoint("CENTER",canvas,"TOPLEFT",area.hx*width/scale,-area.hy*height/scale)
        local color=C.colors[area.kind];pin.dot:SetColorTexture(color[1],color[2],color[3],1)
        pin.count:SetText(area.total)
        pin.ring:SetShown(NS.DB.settings.areaRings)
        if NS.DB.settings.areaRings then
            pin.ring:SetVertexColor(color[1],color[2],color[3],.55)
            pin.ring:ClearAllPoints();pin.ring:SetPoint("CENTER",pin,"CENTER",(area.x-area.hx)*width/scale,-(area.y-area.hy)*height/scale)
            pin.ring:SetSize(area.rx*2*width/scale,area.ry*2*height/scale)
        end
        pin:Show();state.drawn=i
    end
    state.reason=#areas>0 and "Markers drawn" or "No enabled finds on this map"
end
function NS.AttachMap()
    if not NS.DB or not WorldMapFrame or not WorldMapFrame.GetCanvas then return end
    if not mapHooked then
        mapHooked=true
        WorldMapFrame:HookScript("OnShow",NS.DrawWorld)
        WorldMapFrame:HookScript("OnHide",HideWorld)
        if hooksecurefunc then
            if WorldMapFrame.SetMapID then hooksecurefunc(WorldMapFrame,"SetMapID",NS.DrawWorld) end
            if WorldMapFrame.OnCanvasScaleChanged then hooksecurefunc(WorldMapFrame,"OnCanvasScaleChanged",NS.DrawWorld) end
        end
        local canvas=WorldMapFrame:GetCanvas()
        if canvas then canvas:HookScript("OnSizeChanged",NS.DrawWorld) end
        -- Existing refresh callers keep using the same interface, without XML pin creation.
        provider={RefreshAllData=NS.DrawWorld}
    end
end

local function HideMini()
    for _,pin in ipairs(miniPins) do pin:Hide() end
end
local function MiniPin(index)
    if miniPins[index] then return miniPins[index] end
    local pin=CreateFrame("Frame",nil,Minimap)
    pin:SetSize(18,18)
    local texture=pin:CreateTexture(nil,"ARTWORK")
    texture:SetAllPoints()
    texture:SetTexture("Interface\\Minimap\\UI-Minimap-Ping")
    pin.texture=texture
    pin:EnableMouse(true)
    pin:SetScript("OnEnter",function(self) if self.area then NS.AreaTooltip(self,self.area) end end)
    pin:SetScript("OnLeave",function() GameTooltip:Hide() end)
    miniPins[index]=pin
    return pin
end

local lastState
local function UpdateMini()
    if not Minimap or not Minimap:IsShown() or not NS.DB.settings.minimap or not C_Minimap or not C_Minimap.GetViewRadius then HideMini(); return end
    local pos=NS.Position()
    local radius=C_Minimap.GetViewRadius()
    if not pos or not C.Number(radius,1,10000) then HideMini(); return end
    local rotated=GetCVar("rotateMinimap")=="1"
    if C_Minimap.IsRotateMinimapIgnored and C_Minimap.IsRotateMinimapIgnored() then rotated=false end
    local facing=rotated and GetPlayerFacing() or nil
    if facing and not C.Number(facing,-10,10) then HideMini(); return end
    local state=table.concat({pos.map,math.floor(pos.x*pos.width/2),math.floor(pos.y*pos.height/2),math.floor((facing or 0)*100),radius,NS.DB.revision,Minimap:GetWidth(),Minimap:GetHeight()},":")
    if state==lastState then return end
    lastState=state
    local shown=0
    for _,area in ipairs(NS.Areas(pos.map)) do
        local dx,dy=C.Project(area.hx,area.hy,pos.x,pos.y,pos.width,pos.height,radius,facing)
        if dx then
            shown=shown+1
            local pin=MiniPin(shown)
            pin.area=area
            local color=C.colors[area.kind]
            pin.texture:SetVertexColor(color[1],color[2],color[3],1)
            pin:ClearAllPoints()
            pin:SetPoint("CENTER",Minimap,"CENTER",dx*Minimap:GetWidth()/2,dy*Minimap:GetHeight()/2)
            pin:Show()
            if shown==32 then break end
        end
    end
    for i=shown+1,#miniPins do miniPins[i]:Hide() end
end
NS.UpdateMini=UpdateMini

function NS.ConfigureMaps()
    NS.AttachMap()
    lastState=nil
    if provider and WorldMapFrame:IsShown() then provider:RefreshAllData() end
    if miniTicker then miniTicker:Cancel(); miniTicker=nil end
    if NS.DB.settings.minimap and (not C_Minimap or not C_Minimap.GetViewRadius) and not NS.miniWarning then
        NS.miniWarning=true; NS.Say("Minimap markers are unavailable in this game build. You can use world-map markers instead.")
    end
    if NS.DB.settings.minimap and Minimap and Minimap:IsShown() and C_Minimap and C_Minimap.GetViewRadius then
        UpdateMini()
        miniTicker=C_Timer.NewTicker(.5,UpdateMini)
    else HideMini() end
end

function NS.MapDirty()
    for _,entry in ipairs(caches) do entry.revision=nil end
    lastState=nil
    local needsMap=provider and WorldMapFrame:IsShown() and NS.DB.settings.worldmap
    if not needsMap and not NS.DB.settings.minimap then return end
    if mapPending then return end
    mapPending=true
    C_Timer.After(.2,function()
        mapPending=false
        if provider and WorldMapFrame:IsShown() then provider:RefreshAllData() end
        if NS.DB.settings.minimap then UpdateMini() end
    end)
end

function NS.HookMinimap()
    if not Minimap or NS.minimapHooked then return end
    NS.minimapHooked=true
    Minimap:HookScript("OnShow",function() if NS.DB then NS.ConfigureMaps() end end)
    Minimap:HookScript("OnHide",function()
        if miniTicker then miniTicker:Cancel(); miniTicker=nil end
        lastState=nil; HideMini()
    end)
end

end chunk(name,Module) end

-- Internal module source: Options.lua
do local function chunk(...)
local _,NS=...
local C=NS.Core
local window,dataWindow,refresh
local demo

local function Panel(name,width,height)
    local f=CreateFrame("Frame",name,UIParent,"BackdropTemplate")
    f:SetSize(width,height); f:SetPoint("CENTER"); f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true); f:SetMovable(true); f:EnableMouse(true); f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart",f.StartMoving); f:SetScript("OnDragStop",f.StopMovingOrSizing)
    f:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8",edgeFile="Interface\\Tooltips\\UI-Tooltip-Border",edgeSize=12})
    f:SetBackdropColor(.04,.045,.04,.98)
    local close=CreateFrame("Button",nil,f,"UIPanelCloseButton"); close:SetPoint("TOPRIGHT",-2,-2);f.SuiteCloseButton=close
    UISpecialFrames[#UISpecialFrames+1]=name
    return f
end
local function Label(parent,text,x,y,font)
    local f=parent:CreateFontString(nil,"OVERLAY",font or "GameFontHighlightSmall")
    f:SetPoint("TOPLEFT",x,y); f:SetJustifyH("LEFT"); f:SetText(text)
    return f
end
local function Button(parent,text,x,y,width,fn)
    local b=CreateFrame("Button",nil,parent,"UIPanelButtonTemplate")
    b:SetSize(width,25); b:SetPoint("TOPLEFT",x,y); b:SetText(text); b:SetScript("OnClick",fn)
    return b
end

function NS.ProfessionsForItems(items)
    local known={}
    for id in pairs(items or {}) do for _,profession in ipairs(Suite.ReagentProfessions[id] or {}) do known[profession=="FirstAid" and "First Aid" or profession]=true end end
    local names={};for profession in pairs(known) do names[#names+1]=profession end;table.sort(names)
    return table.concat(names,", ")
end
local function ReadableFinds(map)
    local entries={}
    local labels={mine="Mining",herb="Herbs",skin="Skins",valuable="Valuable loot",reagent="Crafting reagents"}
    local names={}
    local function Add(store,source)
        for _,r in pairs(store.records) do
            if C.kinds[r[4]] and (not map or r[1]==map) then
                if not names[r[1]] then local info=C_Map.GetMapInfo(r[1]); names[r[1]]=info and info.name or "Unknown area" end
                local professions=NS.ProfessionsForItems(r[10]);local items={}
                for id,totals in pairs(r[10]) do if id~=0 then local get=C_Item and C_Item.GetItemInfo or GetItemInfo;local name=get and get(id);if not C.Public(name) then name=nil end;items[#items+1]=(name or ("Item #"..id)).." x"..totals[1] end end
                table.sort(items)
                local width,height=C_Map.GetMapWorldSize(r[1]);local coords=width and height and string.format(" (%.1f, %.1f)",100*(r[2]*50+25)/width,100*(r[3]*50+25)/height) or ""
                entries[#entries+1]={count=r[5],text=names[r[1]]..coords.." | "..labels[r[4]].." | "..source.." | "..r[5].." visits, "..r[6].." items | Shop value "..NS.Money(r[7])..(professions~="" and ("\n  Used by: "..professions) or "")..(#items>0 and ("\n  "..table.concat(items,", ")) or "")}
            end
        end
    end
    Add(NS.DB.own,"My discoveries"); Add(NS.DB.shared,"Shared discoveries")
    table.sort(entries,function(a,b) return a.count>b.count end)
    local lines={"YOUR DISCOVERIES","Place | Find | From | Visits and items | Shop value",""}
    for i=1,math.min(#entries,200) do lines[#lines+1]=entries[i].text end
    if #entries==0 then lines[#lines+1]="Your diary is empty here. Play normally with Remember my finds enabled." end
    if #entries>200 then lines[#lines+1]="Showing your top 200 entries. Export includes the full diary." end
    return table.concat(lines,"\n")
end
NS.ReadableFinds=ReadableFinds
function NS.OpenData(all,readable)
    local pos=NS.Position()
    if not all and not pos then NS.Say("No current zone position. Use /sfd data all."); return end
    if not dataWindow then
        dataWindow=Panel("SmyrnaFieldDiaryData",760,480)
        dataWindow:SetFrameStrata("FULLSCREEN_DIALOG");dataWindow:SetFrameLevel(160)
        dataWindow.title=Label(dataWindow,"My finds",18,-18,"GameFontNormalLarge")
        dataWindow.help=Label(dataWindow,"Your discoveries, grouped by place.",18,-45)
        Button(dataWindow,"Export",640,-40,75,function() NS.OpenData(true,false) end)
        local scroll=CreateFrame("ScrollFrame",nil,dataWindow,"UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT",18,-70); scroll:SetPoint("BOTTOMRIGHT",-34,18)
        local edit=CreateFrame("EditBox",nil,scroll)
        edit:SetMultiLine(true); edit:SetAutoFocus(false); edit:SetFontObject(ChatFontNormal)
        edit:SetWidth(700); edit:SetHeight(350); edit:SetMaxLetters(0)
        edit:SetScript("OnTextChanged",function() scroll:UpdateScrollChildRect() end)
        edit:SetScript("OnEscapePressed",function() dataWindow:Hide() end)
        edit:SetScript("OnCursorChanged",function(_,_,y,_,height)
            local offset=scroll:GetVerticalScroll()
            if -y<offset then scroll:SetVerticalScroll(-y)
            elseif -y+height>offset+scroll:GetHeight() then scroll:SetVerticalScroll(-y+height-scroll:GetHeight()) end
        end)
        scroll:SetScrollChild(edit); dataWindow.edit=edit
        dataWindow:SetScript("OnHide",function() edit:ClearFocus(); edit:SetText("") end)
    end
    dataWindow.title:SetText(readable and "My finds" or "Export diary")
    dataWindow.help:SetText(readable and "Your discoveries, grouped by place. Export is available when you need it." or "Ctrl+A, Ctrl+C to copy. Save as .csv for a spreadsheet or sharing.")
    dataWindow:Show(); dataWindow.edit:SetText(readable and ReadableFinds(not all and pos.map or nil) or C.CSV(NS.DB,not all and pos.map or nil))
    dataWindow.edit:SetFocus(); dataWindow.edit:HighlightText()
end

local function Demo()
    if demo then return demo end
    demo=C.New("demoonly0001")
    for _,seed in ipairs({{.27,.32,"mine",18},{.31,.35,"mine",9},{.64,.62,"herb",24},{.66,.64,"herb",12},{.47,.69,"skin",11},{.76,.31,"reagent",7}}) do
        for _=1,seed[4] do C.Record(demo,{map=1,x=seed[1],y=seed[2],width=1000,height=1000,kind=seed[3],units=2,value=1400,gathers=1,item=2770,time=C.Now()}) end
    end
    local r={1,5,6,"mine",10,20,12000,10,C.Now()}
    C.Merge(demo,"Demo-Guildmate","demoshared001",r)
    return demo
end

local previewStates=setmetatable({},{__mode="k"})
NS.PREVIEW_MAP=1434 -- Stranglethorn Vale; the options example never follows the player.
function NS.DrawPreviewMap(view)
    local state=previewStates[view]
    if not state then state={tiles={}};previewStates[view]=state end
    for _,tile in ipairs(state.tiles) do tile:Hide() end
    local layer,files
    if C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures then
        local ok,layers=pcall(C_Map.GetMapArtLayers,NS.PREVIEW_MAP)
        layer=ok and type(layers)=="table" and layers[1]
        if layer then local loaded,textures=pcall(C_Map.GetMapArtLayerTextures,NS.PREVIEW_MAP,1);files=loaded and textures end
    end
    local legacy=not (layer and type(files)=="table" and C.Number(layer.layerWidth,1,20000) and C.Number(layer.layerHeight,1,20000) and C.Number(layer.tileWidth,1,20000) and C.Number(layer.tileHeight,1,20000))
    if legacy then
        layer={layerWidth=1002,layerHeight=668,tileWidth=256,tileHeight=256};files={}
        for i=1,12 do files[i]="Interface\\WorldMap\\Stranglethorn\\Stranglethorn"..i end
    end
    local cols=math.ceil(layer.layerWidth/layer.tileWidth);local rows=math.ceil(layer.layerHeight/layer.tileHeight)
    local rect={x=0,y=0,w=350,h=280};local success=cols*rows<=64 and #files>=cols*rows
    if success then
        local scale=math.min(350/layer.layerWidth,280/layer.layerHeight)
        rect.w=layer.layerWidth*scale;rect.h=layer.layerHeight*scale;rect.x=(350-rect.w)/2;rect.y=(280-rect.h)/2
        for row=0,rows-1 do for col=0,cols-1 do
            local i=row*cols+col+1;local tile=state.tiles[i]
            if not tile then tile=view:CreateTexture(nil,"ARTWORK");state.tiles[i]=tile end
            tile:SetDrawLayer("ARTWORK",0)
            local width=math.min(layer.tileWidth,layer.layerWidth-col*layer.tileWidth)
            local height=math.min(layer.tileHeight,layer.layerHeight-row*layer.tileHeight)
            tile:ClearAllPoints();tile:SetPoint("TOPLEFT",rect.x+col*layer.tileWidth*scale,-rect.y-row*layer.tileHeight*scale)
            tile:SetSize(width*scale,height*scale);tile:SetTexCoord(0,width/layer.tileWidth,0,height/layer.tileHeight)
            local loaded=tile:SetTexture(files[i]);if loaded==false then success=false end;tile:Show()
        end end
    end
    if not state.message then state.message=view:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall");state.message:SetPoint("CENTER");state.message:SetWidth(300) end
    state.message:SetText("Stranglethorn Vale map art is unavailable on this client.\nExample markers are hidden.");state.message:SetShown(not success)
    if not success then for _,tile in ipairs(state.tiles) do tile:Hide() end end
    return rect,"Stranglethorn Vale",NS.PREVIEW_MAP,success
end

local function Build()
    local f=Panel("SmyrnaFieldDiaryOptions",800,650)
    Label(f,"Smyrna Field Diary",20,-20,"GameFontNormalLarge")
    Label(f,"Remembers mining, herbs, skinning and crafting reagents.",20,-46)
    local checks={}
    local function Check(key,text,x,y)
        local box=CreateFrame("CheckButton",nil,f,"UICheckButtonTemplate")
        box:SetPoint("TOPLEFT",x,y)
        local label=box:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        label:SetPoint("LEFT",box,"RIGHT",2,0); label:SetText(text)
        box:SetScript("OnClick",function(self) NS.Set(key,self:GetChecked()) end)
        checks[key]=box
    end
    Check("tracking","Remember my finds",18,-76); Check("worldmap","Show on map",210,-76)
    Check("minimap","Show on minimap",18,-114); Check("includeShared","Shared discoveries",210,-114)
    Check("receive","Accept shared finds",18,-152)
    Check("mine","Mining",18,-190); Check("herb","Herbalism",210,-190)
    Check("skin","Skinning",18,-228); Check("reagent","Crafting reagents",210,-228)
    local areaSize=Button(f,"",20,-318,350,function()
        local span=NS.DB.settings.span; NS.Set("span",span==2 and 4 or span==4 and 8 or 2)
    end)
    Button(f,"My finds here",20,-372,165,function() NS.OpenData(false,true) end)
    Button(f,"All my finds",205,-372,165,function() NS.OpenData(true,true) end)
    Button(f,"Share with guild",20,-412,165,function() NS.Share("GUILD") end)
    Button(f,"Share with party",205,-412,165,function() NS.Share("PARTY") end)
    Button(f,"Stop sharing",20,-452,165,function() NS.StopSharing(); NS.Say("Sharing cancelled.") end)
    Button(f,"Clear old places",205,-452,165,function() NS.Prune(); if refresh then refresh() end end)
    Button(f,"Report memory / CPU",20,-492,165,NS.Perf)
    Check("areaRings","Highlight areas",210,-492)
    local stats=Label(f,"",20,-540)
    stats:SetWidth(350)

    Label(f,"Area preview",420,-76,"GameFontNormalLarge")
    local previewCaption=Label(f,"Example finds on a real map. Your diary is not changed.",420,-106);previewCaption:SetWidth(350)
    local preview=CreateFrame("Frame",nil,f,"BackdropTemplate")
    preview:SetPoint("TOPLEFT",420,-138); preview:SetSize(350,280)
    preview:SetBackdrop({bgFile="Interface\\Buttons\\WHITE8X8"}); preview:SetBackdropColor(.035,.035,.035,1)
    local pins={}
    local previewInfo=Label(f,"",420,-432)
    previewInfo:SetWidth(350)
    if NS.BuildDataColors then NS.BuildDataColors(f,420,-490) end
    local info=Label(f,"Collection and map markers are separate options.",420,-552)
    info:SetWidth(350)
    refresh=function()
        local settings=NS.DB.settings
        for key,box in pairs(checks) do box:SetChecked(settings[key]) end
        checks.areaRings:SetEnabled(settings.worldmap)
        local edge=settings.span*50
        areaSize:SetText("Group nearby finds: "..(settings.span==2 and "Small" or settings.span==4 and "Medium" or "Large"))
        stats:SetText(Suite.UIText("Your finds: ","heading")..Suite.UIText(NS.DB.own.count,"good").."\n"..Suite.UIText("Shared finds: ","heading")..Suite.UIText(NS.DB.shared.count,"detail").."\nClear old places removes entries not visited for 30 days.\nMap and minimap displays are optional.")
        local rect,mapName,renderedMap,available=NS.DrawPreviewMap(preview)
        local sample=Demo();sample.settings=settings
        local areas=available and C.Aggregate(sample,1,1000,1000) or {}
        local example=true
        previewCaption:SetText("Stranglethorn Vale - example finds only, not saved locations")
        for i,a in ipairs(areas) do
            local pin=pins[i]
            if not pin then
                pin=CreateFrame("Frame",nil,preview)
                pin.texture=pin:CreateTexture(nil,"ARTWORK"); pin.texture:SetAllPoints(); pin.texture:SetTexture("Interface\\Minimap\\UI-Minimap-Ping")
                pin.text=pin:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); pin.text:SetPoint("CENTER")
                pin:EnableMouse(true)
                pin:SetScript("OnEnter",function(self) NS.AreaTooltip(self,self.area) end)
                pin:SetScript("OnLeave",function() GameTooltip:Hide() end)
                pins[i]=pin
            end
            pin.area=a
            pin:SetSize(math.max(22,a.rx*rect.w*2),math.max(22,a.ry*rect.h*2))
            pin:ClearAllPoints(); pin:SetPoint("CENTER",preview,"TOPLEFT",rect.x+a.x*rect.w,-rect.y-a.y*rect.h)
            local color=C.colors[a.kind]; pin.texture:SetVertexColor(color[1],color[2],color[3],.8)
            pin.text:SetText(a.kind.." "..a.total); pin:Show()
        end
        for i=#areas+1,#pins do pins[i]:Hide() end
        previewInfo:SetText(string.format("%d %s areas. Try Small, Medium or Large.\nGold: ore / Green: herbs / Brown: skins / Blue: reagents.\nHover a marker to see what was found.",#areas,example and "example" or "saved"))
    end
    f:SetScript("OnShow",refresh)
    return f
end
function NS.RefreshOptions() if window and window:IsShown() then refresh() end end
function NS.OpenOptions()
    if not window then window=Build() end
    if UIParent and UIParent.GetHeight then window:SetScale(math.min(1,(UIParent:GetHeight()-40)/650,(UIParent:GetWidth()-40)/800)) end
    window:Show(); refresh()
    return window
end

end chunk(name,Module) end


-- Internal module source: Launcher.lua
do local function chunk(...)
local _,NS=...
local launcher,popup
local checks={}
function NS.ConfigureLauncher()
end

end chunk(name,Module) end

-- Internal module source: Main.lua
do local function chunk(...)
local addonName,NS=...
local C=NS.Core
local frame=CreateFrame("Frame")
function NS.Say(text) DEFAULT_CHAT_FRAME:AddMessage("|cffdfb66bSmyrna Field Diary:|r "..text) end
function NS.Money(copper)
    return string.format("%dg %ds %dc",math.floor(copper/10000),math.floor(copper/100)%100,copper%100)
end
function NS.Dirty()
    if NS.DB then NS.MapDirty() end
end
function NS.Configure()
    NS.ConfigureCollector(); NS.ConfigureSharing(); NS.ConfigureMaps()
    NS.ConfigureLauncher()
    if NS.RefreshOptions then NS.RefreshOptions() end
end
function NS.Set(key,value)
    local settings=NS.DB.settings
    if key=="valuable" or key=="threshold" then return false end
    if type(settings[key])=="boolean" then settings[key]=not not value
    elseif key=="threshold" and C.ThresholdLabel(value) then settings.threshold=value
    elseif key=="span" and (value==2 or value==4 or value==8) then settings.span=value
    else return false end
    NS.DB.revision=NS.DB.revision+1
    NS.Configure()
    return true
end
function NS.Perf()
    local api=C_AddOns or {}
    local update=api.UpdateAddOnMemoryUsage or UpdateAddOnMemoryUsage
    local get=api.GetAddOnMemoryUsage or GetAddOnMemoryUsage
    if update and get then update(); NS.Say(string.format("WoW-attributed memory: %.1f KB",get(addonName))) end
    local cpuUpdate=api.UpdateAddOnCPUUsage or UpdateAddOnCPUUsage
    local cpuGet=api.GetAddOnCPUUsage or GetAddOnCPUUsage
    if GetCVar("scriptProfile")=="1" and cpuUpdate and cpuGet then cpuUpdate(); NS.Say(string.format("Cumulative CPU: %.2f ms",cpuGet(addonName)))
    else NS.Say("CPU profiling off; see PERFORMANCE.md for a controlled measurement.") end
end
function NS.Prune()
    local n=C.Prune(NS.DB.own,C.Now())+C.Prune(NS.DB.shared,C.Now())
    NS.DB.revision=NS.DB.revision+1; NS.Dirty()
    NS.Say("Cleared "..n.." old places.")
end

SLASH_SMYRNAFIELDDIARY1="/sfd"
SLASH_SMYRNAFIELDDIARY2="/smyrnadiary"
SlashCmdList.SMYRNAFIELDDIARY=function(input)
    if not NS.DB then return end
    local cmd,rest=input:match("^%s*(%S*)%s*(.-)%s*$")
    cmd=string.lower(cmd)
    if cmd=="" or cmd=="options" then NS.OpenOptions()
    elseif cmd=="share" then NS.Share(string.upper(rest=="" and "GUILD" or rest))
    elseif cmd=="stop" then NS.StopSharing(); NS.Say("Sharing cancelled.")
    elseif cmd=="data" then NS.OpenData(rest=="all",true)
    elseif cmd=="prune" then NS.Prune()
    elseif cmd=="diagnose" then NS.Diagnose()
    elseif cmd=="perf" then NS.Perf()
    elseif type(NS.DB.settings[cmd])=="boolean" then
        if rest=="on" then NS.Set(cmd,true) elseif rest=="off" then NS.Set(cmd,false) elseif rest=="" then NS.Set(cmd,not NS.DB.settings[cmd]) else NS.Say("Use on/off.") end
    else NS.Say("/sfd options | data [all] | share guild/party | stop | prune | perf") end
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent",function(_,event,name)
    if event=="ADDON_LOADED" and name=="SmyrnaSuite" then
        if type(SmyrnaFieldDiaryDB)~="table" or (SmyrnaFieldDiaryDB.version~=1 and SmyrnaFieldDiaryDB.version~=2) then
            SmyrnaFieldDiaryDB=C.New(string.format("%x%06x",C.Now(),math.random(0,0xffffff)))
        end
        if SmyrnaFieldDiaryDB.version==1 then
            SmyrnaFieldDiaryDB.version=2
            SmyrnaFieldDiaryDB.settings.worldmap=false
            SmyrnaFieldDiaryDB.settings.areaRings=false
        end
        NS.DB=SmyrnaFieldDiaryDB
        NS.DB.settings.grayOnly=true
        NS.DB.settings.valuable=false
        if NS.DB.settings.reagent==nil then NS.DB.settings.reagent=true end
        C.Prune(NS.DB.own,C.Now()); C.Prune(NS.DB.shared,C.Now())
    elseif event=="PLAYER_LOGIN" then
        NS.HookMinimap(); NS.Configure()
        NS.Say("Ready. Open the Smyrna Lightweight Addon Suite minimap button to see your finds. /sfd opens options.")
    elseif event=="ADDON_LOADED" and NS.DB then NS.AttachMap() end
end)

end chunk(name,Module) end

Suite.Loaded[name]=true
Module.Perf=function() if Suite.Memory then Suite.Memory() end end
