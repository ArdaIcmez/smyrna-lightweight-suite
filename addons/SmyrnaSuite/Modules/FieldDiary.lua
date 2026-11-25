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
C.kinds = { mine = true, herb = true, skin = true, fish = true, rare = true }
C.colors = { mine = {1, .72, .22}, herb = {.24, 1, .42}, skin = {.86, .55, .26}, fish = {.68, .93, 1}, rare = {.86, .89, .95} }
function C.IsRare(classification)
    if issecretvalue and issecretvalue(classification) then return false end
    return classification=='rare' or classification=='rareelite'
end
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
    return { version = 3, origin = origin, own = C.NewStore(), shared = C.NewStore(),
        settings = { tracking = true, worldmap = false, minimap = false, areaRings = false, launcher = true, receive = false,
            includeShared = true, mine = true, herb = true, skin = true, fish = true, rare = true,
            grayOnly = true, threshold = 1000, span = 4 }, revision = 0 }
end

local mapSizeCache={}
function NS.MapWorldSize(mapID)
    if not C.Number(mapID,1,1000000,true) then return nil,nil end
    local cached=mapSizeCache[mapID]
    if cached then return cached[1],cached[2] end
    local w,h=C_Map and C_Map.GetMapWorldSize and C_Map.GetMapWorldSize(mapID)
    if not (C.Number(w,1,200000) and C.Number(h,1,200000)) and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D then
        local ok1,_,p0=pcall(C_Map.GetWorldPosFromMapPos,mapID,CreateVector2D(0,0))
        local ok2,_,p1=pcall(C_Map.GetWorldPosFromMapPos,mapID,CreateVector2D(1,1))
        if ok1 and ok2 and p0 and p1 and p0.GetXY and p1.GetXY then
            local y0,x0=p0:GetXY(); local y1,x1=p1:GetXY()
            if C.Public(x0) and C.Public(y0) and C.Public(x1) and C.Public(y1) then
                local dw,dh=math.abs(x1-x0),math.abs(y1-y0)
                if C.Number(dw,1,200000) and C.Number(dh,1,200000) then w,h=dw,dh end
            end
        end
    end
    if C.Number(w,1,200000) and C.Number(h,1,200000) then
        mapSizeCache[mapID]={w,h}
        return w,h
    end
    return nil,nil
end

function C.SanitizeDB(db)
    if type(db.origin)~="string" or #db.origin<8 or #db.origin>24 then
        db.origin=string.format("%x%06x",C.Now(),math.random(0,0xffffff))
    end
    local function CheckStore(s)
        if type(s)~="table" or type(s.records)~="table" then return C.NewStore() end
        s.queue=type(s.queue)=="table" and s.queue or {}
        s.slots=type(s.slots)=="table" and s.slots or {}
        s.cursor=C.Number(s.cursor,1,C.CAP,true) and s.cursor or 1
        local n=0; for _ in pairs(s.records) do n=n+1 end
        s.count=n
        return s
    end
    db.own=CheckStore(db.own); db.shared=CheckStore(db.shared)
    db.settings=type(db.settings)=="table" and db.settings or {}
    local s=db.settings
    local defs={tracking=true,worldmap=false,minimap=false,areaRings=false,launcher=true,receive=false,includeShared=true,mine=true,herb=true,skin=true,fish=true,rare=true,grayOnly=true}
    for k,v in pairs(defs) do if type(s[k])~="boolean" then s[k]=v end end
    if s.span~=2 and s.span~=4 and s.span~=8 then s.span=4 end
    if not C.Number(db.revision,0,10^12,true) then db.revision=0 end
end

local storeByMap=setmetatable({},{__mode="k"})
local function MapIndex(store)
    local byMap=storeByMap[store]
    if not byMap then
        byMap={}
        for key,record in pairs(store.records) do
            local m=record[1]
            if m then
                local bucket=byMap[m];if not bucket then bucket={};byMap[m]=bucket end
                bucket[key]=record
            end
        end
        storeByMap[store]=byMap
    end
    return byMap
end
local function IndexPut(store,key,record)
    local byMap=storeByMap[store]
    if not byMap then return end
    local m=record[1];if not m then return end
    local bucket=byMap[m];if not bucket then bucket={};byMap[m]=bucket end
    bucket[key]=record
end
local function IndexDel(store,key,record)
    local byMap=storeByMap[store]
    if not byMap or not record then return end
    local bucket=byMap[record[1]]
    if bucket then bucket[key]=nil end
end

function C.Insert(store, key, record)
    if store.records[key] then store.records[key] = record; IndexPut(store, key, record); return end
    local slot = store.cursor
    if store.count < C.CAP then
        for _ = 1, C.CAP do
            local prev = store.queue[slot]
            if not (prev and store.slots[prev]==slot and store.records[prev]) then break end
            slot = slot % C.CAP + 1
        end
    end
    local previous = store.queue[slot]
    if previous and store.slots[previous]==slot and store.records[previous] then
        IndexDel(store, previous, store.records[previous])
        store.records[previous] = nil; store.slots[previous]=nil; store.count = store.count - 1
    end
    store.queue[slot] = key
    store.cursor = slot % C.CAP + 1
    store.records[key] = record
    store.slots[key] = slot
    store.count = store.count + 1
    IndexPut(store, key, record)
end

function C.Delete(store, key)
    if not store or not store.records then return false end
    local record = store.records[key]
    if not record then return false end
    IndexDel(store, key, record)
    local oldSlot = store.slots and store.slots[key]
    if oldSlot and store.queue and store.queue[oldSlot]==key then store.queue[oldSlot]=nil end
    store.records[key] = nil
    if store.slots then store.slots[key] = nil end
    store.count = math.max(0, (store.count or 1) - 1)
    return true
end

function C.Prune(store, now)
    local removed = 0
    for key, record in pairs(store.records) do
        if not C.kinds[record[4]] or not C.Number(record[9], 0, now + 300) or now - record[9] > C.RETENTION then
            IndexDel(store, key, record)
            local oldSlot = store.slots and store.slots[key]
            if oldSlot and store.queue and store.queue[oldSlot]==key then store.queue[oldSlot]=nil end
            store.records[key] = nil; if store.slots then store.slots[key]=nil end; store.count = math.max(0, store.count - 1); removed = removed + 1
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
    -- Store exact sub-cell coordinates (0..10000) so minimap pins never drift 25-35yd to cell center.
    if obs.gathers > 0 or not (r[16] and r[17]) then
        local ex = math.floor(obs.x * 10000 + .5)
        local ey = math.floor(obs.y * 10000 + .5)
        if r[16] and r[17] and r[5] > 1 then
            local w = math.min(r[5], 16)
            r[16] = math.floor((r[16] * (w - 1) + ex) / w + .5)
            r[17] = math.floor((r[17] * (w - 1) + ey) / w + .5)
        else
            r[16] = ex; r[17] = ey
        end
    end
    if (obs.kind=='rare' or obs.kind=='fish') and type(obs.name)=='string' and obs.name~='' then
        local nameKey = obs.kind=='rare' and (C.Number(obs.npc,1,10000000,true) and obs.npc or nil) or obs.name:sub(1,100)
        if nameKey then
            r[14]=r[14] or {};if r[14][nameKey] or (r[15] or 0)<8 then
                if not r[14][nameKey] then r[15]=(r[15] or 0)+1 end
                r[14][nameKey]=obs.name:sub(1,100)
            end
        end
    end
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

function C.Aggregate(db, map, width, height, spanOverride)
    local areas, output = {}, {}
    local span = spanOverride or db.settings.span
    local function Add(r, shared)
        if r[1] ~= map or not C.kinds[r[4]] or not db.settings[r[4]] then return end
        local ax, ay = math.floor(r[2] / span), math.floor(r[3] / span)
        local key = ax .. ":" .. ay .. ":" .. r[4]
        local area = areas[key]
        if not area then
            area = { key = key, kind = r[4], ax = ax, ay = ay, own = 0, shared = 0, units = 0, value = 0, last = 0, hot = {}, professions = {}, npcs = {}, items = {}, senders = {} }
            areas[key] = area; output[#output + 1] = area
        end
        if shared then
            area.shared = area.shared + r[5]
            if type(r[12]) == "string" and r[12] ~= "" then
                local who = r[12]:match("^([^-]+)") or r[12]
                area.senders[who] = (area.senders[who] or 0) + r[5]
            end
        else area.own = area.own + r[5] end
        area.units = area.units + r[6]; area.value = area.value + r[7]; area.last = math.max(area.last, r[9])
        for id,name in pairs(r[14] or {}) do area.npcs[id]=name end
        for item in pairs(r[10] or {}) do
            if type(item) == "number" and item > 0 then area.items[item] = true end
            for _,profession in ipairs(Suite.ReagentProfessions[item] or {}) do area.professions[profession]=true end
        end
        local hotKey = (r[2] % span) .. ":" .. (r[3] % span)
        area.hot[hotKey] = (area.hot[hotKey] or 0) + r[5]
        if C.Number(r[16], 0, 10000) and C.Number(r[17], 0, 10000) then
            area.hotExact = area.hotExact or {}
            local cur = area.hotExact[hotKey]
            -- Prefer personal exact coordinates over shared ones for the same cell.
            if not cur or (not shared and cur[3]) then
                area.hotExact[hotKey] = { r[16] / 10000, r[17] / 10000, shared and true or false }
            end
        end
    end
    local ownMap=MapIndex(db.own)[map]
    if ownMap then for _, r in pairs(ownMap) do Add(r, false) end end
    if db.settings.includeShared then
        local sharedMap=MapIndex(db.shared)[map]
        if sharedMap then for _, r in pairs(sharedMap) do Add(r, true) end end
    end
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
        local exact = a.hotExact and a.hotExact[a.hotKey]
        if exact then
            a.hx = exact[1]; a.hy = exact[2]
        else
            local hx, hy = a.hotKey:match("^(%d+):(%d+)$")
            a.hx = math.min(1, (x0 + (tonumber(hx) + .5) * C.CELL) / width)
            a.hy = math.min(1, (y0 + (tonumber(hy) + .5) * C.CELL) / height)
        end
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
    if kind=="rare" then return nil end -- v1 sharing cannot carry rare identity
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
    local addsMeta = old and ((r[14] and not old[14]) or (r[10] and not old[10]))
    if old and not addsMeta and (r[8] <= old[8] or r[5] < old[5] or r[6] < old[6] or r[7] < old[7]) then return false end
    if old then
        if not r[10] and old[10] then r[10] = old[10]; r[11] = old[11] end
        if not r[14] and old[14] then r[14] = old[14]; r[15] = old[15] end
        if not r[16] and old[16] then r[16] = old[16]; r[17] = old[17] end
        if r[8] < old[8] then r[8] = old[8] end
        if r[5] < old[5] then r[5] = old[5] end
        if r[6] < old[6] then r[6] = old[6] end
        if r[7] < old[7] then r[7] = old[7] end
        if (r[9] or 0) < (old[9] or 0) then r[9] = old[9] end
    end
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
    [2366]="herb", [2368]="herb", [3570]="herb", [11993]="herb",
    [8613]="skin", [8617]="skin", [8618]="skin", [10768]="skin",
    [7620]="fish", [7731]="fish", [7732]="fish", [18248]="fish", [33095]="fish", [131474]="fish" }
local events = {"UPDATE_MOUSEOVER_UNIT","PLAYER_TARGET_CHANGED","LOOT_READY","LOOT_OPENED","LOOT_CLOSED","CHAT_MSG_LOOT"}
local unitCastEvents = {"UNIT_SPELLCAST_START","UNIT_SPELLCAST_CHANNEL_START","UNIT_SPELLCAST_SUCCEEDED","UNIT_SPELLCAST_FAILED","UNIT_SPELLCAST_INTERRUPTED"}

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

-- Zero-allocation scalar position query for hot-path minimap updates
function NS.PositionXY()
    if not C_Map then return nil end
    local map = C_Map.GetBestMapForUnit("player")
    if not C.Number(map,1,1000000,true) then return nil end
    local pos = C_Map.GetPlayerMapPosition(map,"player")
    if not pos then return nil end
    local x,y = pos:GetXY()
    local width,height = NS.MapWorldSize(map)
    if not C.Number(x,0,1) or not C.Number(y,0,1) or not C.Number(width,1,200000) or not C.Number(height,1,200000) then return nil end
    return map,x,y,width,height
end

function NS.Position()
    local map,x,y,width,height = NS.PositionXY()
    if not map then return nil end
    return {map=map,x=x,y=y,width=width,height=height}
end

-- Project from player position forward along facing to estimate the actual found node/pool/corpse/rare spot.
-- WoW GetPlayerFacing() is radians CCW from North (0=N, pi/2=W, pi=S, 3pi/2=E); map +x=East, +y=South.
local OBJECT_DIST = { mine = 3.5, herb = 3.5, skin = 3.0, fish = 14.0, rare = 0 }
function NS.ObjectPosition(kind, unit, basePos, baseFacing, distOverride)
    local pos = basePos or NS.Position()
    if not pos then return nil end
    local dist = distOverride or OBJECT_DIST[kind] or 0
    if kind == "rare" and unit == "target" then
        -- Only project forward when explicitly targeting a nearby rare (avoid misplacing off-axis mouseovers).
        local am = Suite.Modules and Suite.Modules.SmyrnaAggroMate
        if am and am.EstimateRange then
            local ok, _, _, est = pcall(am.EstimateRange, unit)
            if ok and C.Number(est, 2, 20) then
                dist = math.min(15, est)
            end
        end
    end
    local facing = baseFacing
    if facing == nil and GetPlayerFacing then facing = GetPlayerFacing() end
    if dist > 0 and C.Number(facing, -10, 10) then
        local eastYards = -math.sin(facing) * dist
        local southYards = -math.cos(facing) * dist
        local ox = math.max(.0001, math.min(.9999, pos.x + eastYards / pos.width))
        local oy = math.max(.0001, math.min(.9999, pos.y + southYards / pos.height))
        return { map = pos.map, x = ox, y = oy, width = pos.width, height = pos.height }
    end
    return pos
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
    if not C.kinds[obs.kind] then return true end
    if not db.settings.tracking then return true end
    if not db.settings[obs.kind] then return true end
    local quality,price = Info(obs.item)
    if quality == nil then return false end
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
    if waitingCount==1 then frame:RegisterEvent("GET_ITEM_INFO_RECEIVED") end
    if C_Item and C_Item.RequestLoadItemDataByID then C_Item.RequestLoadItemDataByID(obs.item) end
end

local function Retry(id)
    if not C.Public(id) then return end
    for i=#waiting,1,-1 do
        local entry=waiting[i]
        if C.Now()-entry.obs.time > 30 or (entry.obs.item==id and Commit(entry.obs,entry.session)) then
            table.remove(waiting,i); waitingCount=waitingCount-1
        end
    end
    if waitingCount<=0 then waitingCount=0; frame:UnregisterEvent("GET_ITEM_INFO_RECEIVED") end
end

local function KindForSlot(slot, gathering)
    local source = GetLootSourceInfo and GetLootSourceInfo(slot)
    if not C.Public(source) then return nil end
    local creature = type(source)=="string" and source:match("^Creature%-") ~= nil
    local sourceKind=creature and "creature" or (type(source)=="string" and source:match("^GameObject%-") and "object")
    if gathering and ((gathering=="skin" and creature) or (gathering~="skin" and not creature)) then return gathering,sourceKind end
    return nil,sourceKind
end
NS.KindForSlot=KindForSlot

local recentPool
local schoolKeywords={"school","wreckage","swarm","debris","flotsam","elemental water","oil spill","churning waters","shoal","fishing hole","pool of "}
local function IsFishingSchoolName(text)
    if not C.Public(text) or type(text)~="string" or #text<5 or #text>100 then return false end
    local lower=string.lower(text)
    for _,word in ipairs(schoolKeywords) do if lower:find(word,1,true) then return true end end
    return false
end
-- Hovering a fishing school can happen from any angle/distance (or even as a ghost) while the
-- character body faces away from the water, so never record guessed coordinates on mouseover.
-- Only remember the pool name here and attach it when the player actually casts & loots the pool.
local function ObservePoolTooltip(tip)
    if not active or not NS.DB or not NS.DB.settings.tracking or not NS.DB.settings.fish then return end
    if not tip or tip~=GameTooltip or (tip.IsForbidden and tip:IsForbidden()) then return end
    if tip:GetOwner()~=UIParent then return end
    if (tip.GetUnit and tip:GetUnit()) or (tip.GetItem and tip:GetItem()) then return end
    if UnitExists and UnitExists("mouseover") then return end
    local left=GameTooltipTextLeft1
    local title=left and left.GetText and left:GetText()
    if not IsFishingSchoolName(title) then return end
    local map,px,py=NS.PositionXY()
    recentPool={name=title,at=GetTime(),map=map,px=px,py=py}
end
local poolHooked
local function HookPoolTooltip()
    if poolHooked or not GameTooltip then return end
    poolHooked=true
    GameTooltip:HookScript("OnShow",ObservePoolTooltip)
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Object then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Object,function(tip) ObservePoolTooltip(tip) end)
    end
end

local function Snapshot()
    if session and GetTime()-session.opened < .2 then return end
    local fishing=IsFishingLoot and IsFishingLoot()
    local ctx = context and GetTime()-context.at <= (fishing and 35 or 10) and context or nil
    local gathering = ctx and ctx.kind or nil
    local pool=recentPool and GetTime()-recentPool.at<=35 and recentPool or nil
    local pos
    if fishing then
        if ctx and ctx.kind=="fish" and ctx.pos then
            pos=NS.ObjectPosition("fish",nil,ctx.pos,ctx.facing)
        else
            pos=NS.ObjectPosition("fish")
        end
        -- Ignore stale pool tooltip hovered far away (>45 yd) or on a different map.
        if pool and pos and pool.map and pool.px and pool.py then
            if pool.map~=pos.map then
                pool=nil
            else
                local dpx,dpy=(pos.x-pool.px)*pos.width,(pos.y-pool.py)*pos.height
                if dpx*dpx+dpy*dpy>45*45 then pool=nil end
            end
        end
    elseif gathering then
        pos=NS.ObjectPosition(gathering,nil,ctx and ctx.pos,ctx and ctx.facing)
    else
        pos=NS.ObjectPosition("mine")
    end
    if not pos then diag.positionFailures=diag.positionFailures+1;session=nil; return end
    diag.windows=diag.windows+1
    local s={pos=pos,opened=GetTime(),slots={},counted={}}
    s.gathering=gathering
    context=nil
    if LootIsFromItem and LootIsFromItem() then session=nil; return end
    local numLoot=GetNumLootItems and GetNumLootItems()
    if not C.Number(numLoot,0,64,true) then session=nil; return end
    if fishing then
        if not NS.DB.settings.fish then session=nil; return end
        local fromObject=false
        for slot=1,numLoot do
            local source=GetLootSourceInfo and GetLootSourceInfo(slot)
            if C.Public(source) and type(source)=="string" and source:match("^GameObject%-") then fromObject=true;break end
        end
        if not fromObject and not pool then session=nil; return end
        s.gathering="fish"
        s.poolName=pool and pool.name or nil
        for slot=1,numLoot do
            local link=GetLootSlotLink(slot)
            if C.Public(link) and type(link)=="string" then
                local id=tonumber(link:match("item:(%d+)"))
                local _,_,quantity=GetLootSlotInfo(slot)
                if id and C.Number(quantity,1,100000,true) then
                    local record=s.slots[id]
                    if not record then record={remaining=0,kind="fish",source="object"}; s.slots[id]=record end
                    record.remaining=record.remaining+quantity
                end
            end
        end
        session=s
        return
    end
    for slot=1,numLoot do
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
    context=nil
    slot.remaining=slot.remaining-quantity
    local pos=session.pos
    Queue({map=pos.map,x=pos.x,y=pos.y,width=pos.width,height=pos.height,
        kind=kind,item=id,units=quantity,name=kind=="fish" and session.poolName or nil,time=C.Now()},session)
end
NS.HandleReceipt=Receipt

local seenRares,rareCount={},0
function NS.ObserveRare(unit)
    if not NS.DB.settings.tracking or not NS.DB.settings.rare then return end
    if not C.IsRare(UnitClassification(unit)) or (UnitIsPlayer and UnitIsPlayer(unit)) then return end
    local guid=UnitGUID(unit);local name=UnitName(unit)
    if not C.Public(guid) or type(guid)~='string' or not C.Public(name) or type(name)~='string' then return end
    local npc=tonumber(guid:match('^Creature%-%d+%-%d+%-%d+%-%d+%-(%d+)%-'))
    if not npc or (seenRares[guid] and GetTime()-seenRares[guid]<300) then return end
    local pos=NS.ObjectPosition("rare",unit);if not pos then return end
    if rareCount>=256 then wipe(seenRares);rareCount=0 end
    if not seenRares[guid] then rareCount=rareCount+1 end
    seenRares[guid]=GetTime()
    if C.Record(NS.DB,{map=pos.map,x=pos.x,y=pos.y,width=pos.width,height=pos.height,kind='rare',
        npc=npc,name=name,units=1,value=0,gathers=1,time=C.Now()}) then NS.Dirty() end
end
frame:SetScript("OnEvent",function(_,event,...)
    if event=="UPDATE_MOUSEOVER_UNIT" or event=="PLAYER_TARGET_CHANGED" then
        NS.ObserveRare(event=="UPDATE_MOUSEOVER_UNIT" and "mouseover" or "target")
    elseif event=="UNIT_SPELLCAST_START" or event=="UNIT_SPELLCAST_CHANNEL_START" or event=="UNIT_SPELLCAST_SUCCEEDED" then
        local unit,_,id=...
        if C.Public(unit) and unit=="player" then
            if C.Public(id) then diag.lastSpell=id end
            local kind=SpellKind(id)
            if kind then
                diag.casts=diag.casts+1
                -- Preserve cast-start facing & pos (character automatically faces the node/pool at cast start!)
                if not context or context.kind~=kind or event~="UNIT_SPELLCAST_SUCCEEDED" then
                    context={kind=kind,at=GetTime(),pos=NS.Position(),facing=GetPlayerFacing and GetPlayerFacing() or nil}
                else
                    context.at=GetTime()
                end
            end
        end
    elseif event=="UNIT_SPELLCAST_FAILED" or event=="UNIT_SPELLCAST_INTERRUPTED" then
        local unit=...;if C.Public(unit) and unit=="player" then context=nil end
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
    local enabled=(NS._enabled~=false) and s.tracking and (s.mine or s.herb or s.skin or s.fish or s.rare)
    if enabled==active then return end
    active=enabled
    if enabled then
        for id,kind in pairs({[2575]="mine",[2366]="herb",[8613]="skin",[7620]="fish"}) do local name=SpellName(id);if name then gatherNames[name]=kind end end
        HookPoolTooltip()
    end
    for _,event in ipairs(events) do if enabled then pcall(frame.RegisterEvent,frame,event) else frame:UnregisterEvent(event) end end
    for _,event in ipairs(unitCastEvents) do
        if enabled then
            if frame.RegisterUnitEvent then pcall(frame.RegisterUnitEvent,frame,event,"player") else pcall(frame.RegisterEvent,frame,event) end
        else
            frame:UnregisterEvent(event)
        end
    end
    singlePattern=FormatPattern(LOOT_ITEM_SELF)
    multiplePattern=FormatPattern(LOOT_ITEM_SELF_MULTIPLE)
    if not enabled then frame:UnregisterEvent("GET_ITEM_INFO_RECEIVED"); session=nil; context=nil; recentPool=nil; wipe(waiting); waitingCount=0 end
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
        if C.kinds[r[4]] and r[4]~="rare" and r[1]==pos.map and r[5]>0 and C.Now()-r[9]<=C.RETENTION then queue[#queue+1]=r end
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
    local encodedQueue={}
    for i=1,#queue do
        local encoded=C.Encode(NS.DB.origin,queue[i])
        if type(encoded)=="string" and #encoded<=248 then encodedQueue[#encodedQueue+1]=encoded end
    end
    queue=encodedQueue
    if #queue==0 then Stop(); NS.Say("No valid observations fit message limit."); return end
    index=1
    local retries=0
    NS.Say("Sharing finds "..first.."-"..last.." of "..total.." with your "..(channel=="GUILD" and "guild" or "group")..". Click Share again for more.")
    ticker=C_Timer.NewTicker(.5,function()
        if (channel=="GUILD" and not IsInGuild()) or (channel~="GUILD" and not IsInGroup()) then Stop(); NS.Say("Share stopped: group/guild unavailable."); return end
        local message=queue and queue[index]
        if not message then Stop(); NS.Say("Share finished."); return end
        local callOk,res=pcall(C_ChatInfo.SendAddonMessage,PREFIX,message,channel)
        local succ=Enum and Enum.SendAddonMessageResult and Enum.SendAddonMessageResult.Success or 0
        local sent=callOk and (res==nil or res==true or res==succ or res==0)
        if sent then
            retries=0; index=index+1
        elseif retries<6 then
            retries=retries+1; return
        else
            retries=0; index=index+1
        end
        if index>#queue then cursors[cursorKey]=nextCursor; Stop(); NS.Say("Share finished.") end
    end)
end

function NS.Receive(prefix,message,channel,sender)
    if not NS.DB or not NS.DB.settings.receive then return false end
    if not C.Public(prefix) or not C.Public(channel) or prefix~=PREFIX or (channel~="GUILD" and channel~="PARTY" and channel~="RAID") then return false end
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
    local width,height=NS.MapWorldSize(r[1])
    if not info or not C.Number(width,1,200000) or not C.Number(height,1,200000) or r[2]*50>=width or r[3]*50>=height then return false end
    if C.Merge(NS.DB,sender,origin,r) then NS.Dirty(); return true end
    return false
end

frame:SetScript("OnEvent",function(_,_,...) NS.Receive(...) end)
function NS.ConfigureSharing()
    if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then C_ChatInfo.RegisterAddonMessagePrefix(PREFIX) end
    if (NS._enabled~=false) and NS.DB.settings.receive then frame:RegisterEvent("CHAT_MSG_ADDON") else frame:UnregisterEvent("CHAT_MSG_ADDON"); wipe(rates); wipe(identities) end
end

end chunk(name,Module) end

-- Internal module source: Maps.lua
do local function chunk(...)
local _,NS=...
local C=NS.Core
local provider
local miniPins={}
local caches={}
local cacheClock=0
local mapPending=false

local miniCaches={}
local miniCacheClock=0

function NS.Areas(map)
    if not map then return {} end
    cacheClock=cacheClock+1
    for _,entry in ipairs(caches) do
        if entry.map==map and entry.revision==NS.DB.revision then entry.used=cacheClock; return entry.areas end
    end
    local width,height=NS.MapWorldSize(map)
    if not C.Number(width,1,200000) or not C.Number(height,1,200000) then return {} end
    local areas=C.Aggregate(NS.DB,map,width,height)
    local slot
    for i,entry in ipairs(caches) do if entry.map==map then slot=i; break end end
    if not slot then slot=#caches<2 and (#caches+1) or (caches[1].used<caches[2].used and 1 or 2) end
    caches[slot]={map=map,revision=NS.DB.revision,used=cacheClock,areas=areas}
    return areas
end

-- Per-cell (50 yd, span=1) aggregation for the Minimap so nearby fishing pools / veins / herbs
-- never collapse into a single 100-400 yd cluster pin when viewing the close-up minimap.
function NS.MiniAreas(map)
    if not map then return {} end
    miniCacheClock=miniCacheClock+1
    for _,entry in ipairs(miniCaches) do
        if entry.map==map and entry.revision==NS.DB.revision then entry.used=miniCacheClock; return entry.areas end
    end
    local width,height=NS.MapWorldSize(map)
    if not C.Number(width,1,200000) or not C.Number(height,1,200000) then return {} end
    local areas=C.Aggregate(NS.DB,map,width,height,1)
    local slot
    for i,entry in ipairs(miniCaches) do if entry.map==map then slot=i; break end end
    if not slot then slot=#miniCaches<2 and (#miniCaches+1) or (miniCaches[1].used<miniCaches[2].used and 1 or 2) end
    miniCaches[slot]={map=map,revision=NS.DB.revision,used=miniCacheClock,areas=areas}
    return areas
end

local areaKindNames={mine="Mining finds",herb="Herb finds",skin="Skinning finds",fish="Fishing schools",rare="Rare sightings"}
function NS.AreaTooltip(owner,area)
    if not GameTooltip or (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then return end
    GameTooltip:SetOwner(owner,"ANCHOR_RIGHT")
    GameTooltip:SetText(areaKindNames[area.kind] or "Field Diary")
    GameTooltip:AddLine("My visits: "..area.own,1,1,1)
    GameTooltip:AddLine("Shared visits: "..area.shared,.7,.8,1)
    if area.senders and next(area.senders) then
        local who={}
        for sender,n in pairs(area.senders) do who[#who+1]={sender,n} end
        table.sort(who,function(a,b) if a[2]~=b[2] then return a[2]>b[2] end return a[1]<b[1] end)
        local parts={}
        for i=1,math.min(#who,4) do parts[#parts+1]=who[i][1].." ("..who[i][2]..")" end
        GameTooltip:AddLine("Guildmates: "..table.concat(parts,", "),.55,.84,1,true)
    end
    if area.kind=='rare' then
        local names={};for _,name in pairs(area.npcs or {}) do names[#names+1]=name end;table.sort(names)
        for _,name in ipairs(names) do GameTooltip:AddLine(name,.78,.8,.84) end
        GameTooltip:AddLine("Estimated rare location from sighting direction & range.",.78,.8,.84,true)
        if not owner.isPreviewPin then Suite.OptionalHint(GameTooltip,"Ctrl + left-click to expand this map") end
        GameTooltip:Show();return
    end
    local seenNames,namedList={},{}
    for _,name in pairs(area.npcs or {}) do if type(name)=="string" and name~="" and not seenNames[name] then seenNames[name]=true; namedList[#namedList+1]=name end end
    local getItem=C_Item and C_Item.GetItemInfo or GetItemInfo
    if getItem then
        for id in pairs(area.items or {}) do
            local iname=getItem(id)
            if C.Public(iname) and type(iname)=="string" and iname~="" and not seenNames[iname] then seenNames[iname]=true; namedList[#namedList+1]=iname end
        end
    end
    table.sort(namedList)
    if #namedList>0 then
        local cap=math.min(#namedList,5)
        local line={}
        for i=1,cap do line[i]=namedList[i] end
        local color=area.kind=='fish' and {.4,.85,1} or {1,.88,.55}
        GameTooltip:AddLine("Finds: "..table.concat(line,", ")..(#namedList>cap and (" +"..(#namedList-cap).." more") or ""),color[1],color[2],color[3],true)
    end
    GameTooltip:AddLine("Items found: "..area.units,1,1,1)
    local professions={};for name in pairs(area.professions or {}) do professions[#professions+1]=name=="FirstAid" and "First Aid" or name end;table.sort(professions)
    if #professions>0 then GameTooltip:AddLine("Used by: "..table.concat(professions,", "),.4,.8,1,true) end
    GameTooltip:AddLine("Shop value: "..NS.Money(area.value),1,.8,.3)
    GameTooltip:AddLine("Busiest spot: "..area.hotCount.." visits",.8,.8,.8,true)
    GameTooltip:AddLine("Shows where nodes were found before; one may not be up right now.",.7,.7,.7,true)
    if not owner.isPreviewPin then Suite.OptionalHint(GameTooltip,"Ctrl + left-click to expand this map") end
    GameTooltip:Show()
end

local worldPins={}
local mapHooked
local RING_TEX="Interface\\AddOns\\SmyrnaSuite\\Media\\DiaryRing"
local RING_BORDER_TEX="Interface\\AddOns\\SmyrnaSuite\\Media\\DiaryRingBorder"
local RING_FALLBACK="Interface\\Minimap\\UI-Minimap-Ping"
local KIND_TEX={
    mine="Interface\\AddOns\\SmyrnaSuite\\Media\\DiaryMine",
    herb="Interface\\AddOns\\SmyrnaSuite\\Media\\DiaryHerb",
    skin="Interface\\AddOns\\SmyrnaSuite\\Media\\DiarySkin",
    fish="Interface\\AddOns\\SmyrnaSuite\\Media\\DiaryFish",
    rare="Interface\\AddOns\\SmyrnaSuite\\Media\\DiaryRare",
}
local KIND_OUT_TEX={
    mine="Interface\\AddOns\\SmyrnaSuite\\Media\\DiaryMineOut",
    herb="Interface\\AddOns\\SmyrnaSuite\\Media\\DiaryHerbOut",
    skin="Interface\\AddOns\\SmyrnaSuite\\Media\\DiarySkinOut",
    fish="Interface\\AddOns\\SmyrnaSuite\\Media\\DiaryFishOut",
    rare="Interface\\AddOns\\SmyrnaSuite\\Media\\DiaryRareOut",
}
local function ApplyRingTextures(borderTex,ringTex,kind)
    local iconPath=kind and KIND_TEX[kind]
    if iconPath then
        local okIcon=ringTex:SetTexture(iconPath)
        if okIcon~=false then
            if borderTex then
                local outPath=KIND_OUT_TEX[kind]
                local okOut=outPath and borderTex:SetTexture(outPath)
                borderTex:SetShown(okOut~=false)
            end
            return
        end
    end
    local okRing=ringTex:SetTexture(RING_TEX)
    if okRing==false then
        ringTex:SetTexture(RING_FALLBACK)
        if borderTex then borderTex:Hide() end
    elseif borderTex then
        local okBorder=borderTex:SetTexture(RING_BORDER_TEX)
        borderTex:SetShown(okBorder~=false)
    end
end
NS.ApplyRingTextures=ApplyRingTextures
NS.MapDisplay={drawn=0,areas=0}
local function HideWorld()
    for _,pin in ipairs(worldPins) do pin:Hide() end
    NS.MapDisplay.drawn=0
    Suite.DiaryWorldPts=nil
end
function NS.DrawWorld()
    HideWorld()
    local state=NS.MapDisplay;state.areas=0
    if NS._enabled==false then state.reason="Module disabled";return end
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
        local topLevel=manager and manager.GetValidFrameLevel and manager:GetValidFrameLevel("PIN_FRAME_LEVEL_TOPMOST")
        if type(topLevel)=="number" then level=topLevel+1 end
    end
    local pts={}
    for i=1,math.min(#areas,64) do
        local area=areas[i];local pin=worldPins[i]
        if not pin then
            pin=CreateFrame("Frame",nil,canvas);pin:SetSize(15,15);pin:EnableMouse(true)
            pin.border=pin:CreateTexture(nil,"ARTWORK");pin.border:SetAllPoints()
            pin.dot=pin:CreateTexture(nil,"OVERLAY");pin.dot:SetAllPoints()
            ApplyRingTextures(pin.border,pin.dot,area.kind)
            pin.iconKind=area.kind
            pin.count=pin:CreateFontString(nil,"OVERLAY","GameFontNormalSmall");pin.count:SetPoint("LEFT",pin,"RIGHT",2,0)
            pin.ring=pin:CreateTexture(nil,"BACKGROUND");pin.ring:SetTexture(RING_FALLBACK)
            pin:SetScript("OnEnter",function(self) if self.area then NS.AreaTooltip(self,self.area) end end)
            pin:SetScript("OnLeave",function() if GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then GameTooltip:Hide() end end)
            pin:SetScript("OnMouseUp",function(self,btn)
                if btn=="LeftButton" and IsControlKeyDown and IsControlKeyDown() and NS.OpenMapInspect then
                    NS.OpenMapInspect(self.mapID,self.area)
                end
            end)
            worldPins[i]=pin
        elseif pin.iconKind~=area.kind then
            ApplyRingTextures(pin.border,pin.dot,area.kind)
            pin.iconKind=area.kind
        end
        pin.area=area;pin.mapID=mapID;pin:SetParent(canvas);pin:SetFrameLevel(level);pin:SetScale(scale)
        local px,py=area.hx*width,-area.hy*height
        pts[#pts+1]={px,py}
        pin:ClearAllPoints();pin:SetPoint("CENTER",canvas,"TOPLEFT",px/scale,py/scale)
        local color=C.colors[area.kind]
        pin.dot:SetVertexColor(color[1],color[2],color[3],1)
        pin.count:SetText(area.total)
        pin.count:SetTextColor(color[1],color[2],color[3])
        if NS.SourceColor and pin.border then
            local sr,sg,sb=NS.SourceColor(area.own>0 and "personal" or "guild")
            pin.border:SetVertexColor(sr,sg,sb,1)
        end
        pin.ring:SetShown(NS.DB.settings.areaRings)
        if NS.DB.settings.areaRings then
            pin.ring:SetVertexColor(color[1],color[2],color[3],.55)
            pin.ring:ClearAllPoints();pin.ring:SetPoint("CENTER",pin,"CENTER",(area.x-area.hx)*width/scale,-(area.y-area.hy)*height/scale)
            pin.ring:SetSize(area.rx*2*width/scale,area.ry*2*height/scale)
        end
        pin:Show();state.drawn=i
    end
    Suite.DiaryWorldPts=pts
    if Suite.Modules.SmyrnaQuests and Suite.Modules.SmyrnaQuests.RepositionWorld then Suite.Modules.SmyrnaQuests.RepositionWorld() end
    state.reason=#areas>0 and "Markers drawn" or "No enabled finds on this map"
end
function NS.AttachMap()
    if not NS.DB or not WorldMapFrame or not WorldMapFrame.GetCanvas then return end
    if not mapHooked then
        mapHooked=true;NS.MapHooked=true
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
    Suite.DiaryMiniPts=nil
end
local function MiniPin(index)
    if miniPins[index] then return miniPins[index] end
    local pin=CreateFrame("Frame",nil,Minimap)
    pin:SetSize(14,14)
    local border=pin:CreateTexture(nil,"ARTWORK");border:SetAllPoints()
    local texture=pin:CreateTexture(nil,"OVERLAY");texture:SetAllPoints()
    ApplyRingTextures(border,texture)
    pin.border=border;pin.texture=texture
    pin:EnableMouse(true)
    pin:SetScript("OnEnter",function(self) if self.area then NS.AreaTooltip(self,self.area) end end)
    pin:SetScript("OnLeave",function() if GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then GameTooltip:Hide() end end)
    pin:SetScript("OnMouseUp",function(self,btn)
        if btn=="LeftButton" and IsControlKeyDown and IsControlKeyDown() and NS.OpenMapInspect then
            NS.OpenMapInspect(self.mapID,self.area)
        end
    end)
    miniPins[index]=pin
    return pin
end

local lastMiniMap,lastMiniRev,miniAreas,miniPtsBuf,miniPtsPool=nil,nil,nil,{},{}
local lastPX,lastPY,lastFacing,lastRadius,lastMW,lastMH=nil,nil,nil,nil,nil,nil
local miniDriver,miniMoving,miniHookedZoom

local function UpdateMini(force)
    if not Minimap or not Minimap:IsShown() or not NS.DB or not NS.DB.settings.minimap or not C_Minimap or not C_Minimap.GetViewRadius then
        HideMini(); lastPX=nil; return
    end
    local pmap,px,py,pwidth,pheight=NS.PositionXY()
    local radius=C_Minimap.GetViewRadius()
    if not pmap or not C.Number(radius,1,10000) then HideMini(); lastPX=nil; return end
    local rotated=GetCVar("rotateMinimap")=="1"
    if C_Minimap.IsRotateMinimapIgnored and C_Minimap.IsRotateMinimapIgnored() then rotated=false end
    local facing=rotated and GetPlayerFacing() or 0
    if not C.Number(facing,-10,10) then HideMini(); lastPX=nil; return end
    local mw,mh=Minimap:GetWidth(),Minimap:GetHeight()
    local rev=NS.DB.revision
    if not force and lastMiniMap==pmap and lastMiniRev==rev and lastRadius==radius and lastMW==mw and lastMH==mh
        and lastPX and math.abs(px-lastPX)<1e-6 and math.abs(py-lastPY)<1e-6 and math.abs(facing-lastFacing)<1e-4 then
        return
    end
    if lastMiniMap~=pmap or lastMiniRev~=rev or not miniAreas then
        miniAreas=NS.MiniAreas(pmap)
        lastMiniMap=pmap; lastMiniRev=rev
    end
    lastPX,lastPY,lastFacing,lastRadius,lastMW,lastMH=px,py,facing,radius,mw,mh
    local halfW,halfH=mw*.5,mh*.5
    local rotArg=rotated and facing or nil
    local shown=0
    wipe(miniPtsBuf)
    for i=1,#miniAreas do
        local area=miniAreas[i]
        local dx,dy=C.Project(area.hx,area.hy,px,py,pwidth,pheight,radius,rotArg)
        if dx then
            shown=shown+1
            local pin=MiniPin(shown)
            if pin.area~=area or pin.mapID~=pmap or force then
                pin.area=area; pin.mapID=pmap
                if pin.iconKind~=area.kind then
                    ApplyRingTextures(pin.border,pin.texture,area.kind)
                    pin.iconKind=area.kind
                end
                local color=C.colors[area.kind]
                pin.texture:SetVertexColor(color[1],color[2],color[3],1)
                if NS.SourceColor and pin.border then
                    local sr,sg,sb=NS.SourceColor(area.own>0 and "personal" or "guild")
                    pin.border:SetVertexColor(sr,sg,sb,1)
                end
            end
            local mx,my=dx*halfW,dy*halfH
            local pt=miniPtsPool[shown]
            if not pt then pt={0,0}; miniPtsPool[shown]=pt end
            pt[1]=mx; pt[2]=my; miniPtsBuf[shown]=pt
            if not pin.mx or math.abs(mx-pin.mx)>=.25 or math.abs(my-pin.my)>=.25 then
                pin.mx,pin.my=mx,my
                pin:ClearAllPoints()
                pin:SetPoint("CENTER",Minimap,"CENTER",mx,my)
            end
            if not pin:IsShown() then pin:Show() end
            if shown==32 then break end
        end
    end
    for i=shown+1,#miniPtsBuf do miniPtsBuf[i]=nil end
    Suite.DiaryMiniPts=miniPtsBuf
    for i=shown+1,#miniPins do
        local p=miniPins[i]
        if p:IsShown() then p:Hide(); p.mx=nil; p.my=nil end
    end
end
NS.UpdateMini=UpdateMini

local miniAccum=0
local function OnMiniUpdate(_,elapsed)
    miniAccum=miniAccum+(elapsed or 0)
    local step=miniMoving and .06 or .15
    if miniAccum>=step then miniAccum=0; UpdateMini(false) end
end

local MINI_EVENTS={"PLAYER_STARTED_MOVING","PLAYER_STOPPED_MOVING","MINIMAP_UPDATE_ZOOM","ZONE_CHANGED_NEW_AREA","PLAYER_ENTERING_WORLD","CVAR_UPDATE"}
local function SyncMiniEvents(on)
    if not miniDriver then return end
    for _,ev in ipairs(MINI_EVENTS) do
        if on then pcall(miniDriver.RegisterEvent,miniDriver,ev) else pcall(miniDriver.UnregisterEvent,miniDriver,ev) end
    end
end

local function SyncMiniMotion()
    if not miniDriver then return end
    local want=(NS._enabled~=false) and NS.DB and NS.DB.settings.minimap and Minimap and Minimap:IsShown() and C_Minimap and C_Minimap.GetViewRadius
    if not want then
        miniDriver:SetScript("OnUpdate",nil); HideMini(); return
    end
    local rotating=(GetCVar("rotateMinimap")=="1") and not (C_Minimap.IsRotateMinimapIgnored and C_Minimap.IsRotateMinimapIgnored())
    if miniMoving or rotating then
        miniAccum=0
        miniDriver:SetScript("OnUpdate",OnMiniUpdate)
    else
        miniDriver:SetScript("OnUpdate",nil)
        UpdateMini(false)
    end
end

local function EnsureMiniDriver()
    if miniDriver then return end
    miniDriver=CreateFrame("Frame")
    SyncMiniEvents(NS._enabled~=false)
    miniDriver:SetScript("OnEvent",function(_,ev,arg1)
        if NS._enabled==false then return end
        if ev=="PLAYER_STARTED_MOVING" then
            miniMoving=true; SyncMiniMotion()
        elseif ev=="PLAYER_STOPPED_MOVING" then
            miniMoving=false
            C_Timer.After(.12,function() if not miniMoving then SyncMiniMotion() end end)
        elseif ev=="CVAR_UPDATE" then
            if C.Public(arg1) and arg1=="rotateMinimap" then SyncMiniMotion() end
        else
            lastPX=nil; UpdateMini(true); SyncMiniMotion()
        end
    end)
    if not miniHookedZoom and Minimap then
        miniHookedZoom=true
        Minimap:HookScript("OnShow",function() if NS._enabled~=false and NS.DB then lastPX=nil; lastMiniRev=nil; UpdateMini(true); SyncMiniMotion() end end)
        Minimap:HookScript("OnHide",function() miniDriver:SetScript("OnUpdate",nil); lastPX=nil; lastMiniRev=nil; HideMini() end)
    end
end

function NS.ConfigureMaps()
    local modOn=(NS._enabled~=false)
    if not modOn then
        if miniDriver then miniDriver:SetScript("OnUpdate",nil); SyncMiniEvents(false) end
        HideMini(); HideWorld()
        return
    end
    NS.AttachMap()
    EnsureMiniDriver()
    SyncMiniEvents(true)
    lastPX=nil; lastMiniRev=nil
    if provider and WorldMapFrame:IsShown() then provider:RefreshAllData() end
    if NS.DB.settings.minimap and (not C_Minimap or not C_Minimap.GetViewRadius) and not NS.miniWarning then
        NS.miniWarning=true; NS.Say("Minimap markers are unavailable in this game build. You can use world-map markers instead.")
    end
    if NS.DB.settings.minimap and Minimap and Minimap:IsShown() and C_Minimap and C_Minimap.GetViewRadius then
        miniMoving=(IsPlayerMoving and IsPlayerMoving()) and true or false
        UpdateMini(true)
        SyncMiniMotion()
    else
        if miniDriver then miniDriver:SetScript("OnUpdate",nil) end
        HideMini()
    end
end

function NS.MapDirty()
    for _,entry in ipairs(caches) do entry.revision=nil end
    for _,entry in ipairs(miniCaches) do entry.revision=nil end
    lastPX=nil; lastMiniRev=nil
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
    f:SetScript("OnDragStart",function(self) if not (InCombatLockdown and InCombatLockdown()) then self:StartMoving() end end); f:SetScript("OnDragStop",f.StopMovingOrSizing)
    Suite.StylePanel(f,true)
    local close=Suite.CloseButton(f);f.SuiteCloseButton=close
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
    local labels={mine="Mining",herb="Herbs",skin="Skins",fish="Fishing schools",rare="Rare sightings"}
    local names={}
    local function Add(store,source)
        for _,r in pairs(store.records) do
            if C.kinds[r[4]] and (not map or r[1]==map) then
                if not names[r[1]] then local info=C_Map.GetMapInfo(r[1]); names[r[1]]=info and info.name or "Unknown area" end
                local professions=NS.ProfessionsForItems(r[10]);local items={}
                for _,name in pairs(r[14] or {}) do items[#items+1]=name end
                for id,totals in pairs(r[10] or {}) do if id~=0 then local get=C_Item and C_Item.GetItemInfo or GetItemInfo;local name=get and get(id);if not C.Public(name) then name=nil end;items[#items+1]=(name or ("Item #"..id)).." x"..totals[1] end end
                table.sort(items)
                local coords
                if C.Number(r[16],0,10000) and C.Number(r[17],0,10000) then
                    coords=string.format(" (%.1f, %.1f)",r[16]/100,r[17]/100)
                else
                    local width,height=NS.MapWorldSize(r[1])
                    coords=C.Number(width,1,200000) and C.Number(height,1,200000) and string.format(" (%.1f, %.1f)",100*(r[2]*50+25)/width,100*(r[3]*50+25)/height) or ""
                end
                local summary=r[4]=='rare' and (r[5]..' sightings (estimated mob spot)') or (r[5]..' visits, '..r[6]..' items | Shop value '..NS.Money(r[7]))
                local fromLabel=source=="shared" and ("Guild: "..((type(r[12])=="string" and r[12]~="") and (r[12]:match("^([^-]+)") or r[12]) or "Shared")) or source
                entries[#entries+1]={count=r[5],text=names[r[1]]..coords.." | "..labels[r[4]].." | "..fromLabel.." | "..summary..(professions~="" and ("\n  Used by: "..professions) or "")..(#items>0 and ("\n  "..table.concat(items,", ")) or "")}
            end
        end
    end
    Add(NS.DB.own,"My discoveries"); Add(NS.DB.shared,"shared")
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
    local targetMap=not all and (NS.InspectMapID or (pos and pos.map)) or nil
    if not all and not targetMap then NS.Say("No current zone position. Use /sfd data all."); return end
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
    dataWindow:Show(); dataWindow.edit:SetText(readable and ReadableFinds(targetMap) or C.CSV(NS.DB,targetMap))
    dataWindow.edit:SetFocus(); dataWindow.edit:HighlightText()
end

local function Demo()
    if demo then return demo end
    demo=C.New("demoonly0001")
    local width,height=NS.MapWorldSize(1434)
    if not C.Number(width,1,200000) or not C.Number(height,1,200000) then return demo end
    -- Illustrations near inland terrain; these are not spawn/reference claims.
    for _,seed in ipairs({{.51,.29,"mine",3,2772},{.37,.20,"herb",4,3356},{.34,.19,"skin",2,4234},{.27,.62,"fish",2,6358},{.43,.42,"rare",1}}) do
        for _=1,seed[4] do C.Record(demo,{map=1434,x=seed[1],y=seed[2],width=width,height=height,kind=seed[3],units=1,value=0,gathers=1,item=seed[5],npc=seed[3]=='rare' and 1 or nil,name=seed[3]=='rare' and 'Example rare sighting' or seed[3]=='fish' and 'Oily Blackmouth School' or nil,time=C.Now()}) end
    end
    return demo
end

local previewStates=setmetatable({},{__mode="k"})
NS.PREVIEW_MAP=1434 -- Stranglethorn Vale; the options example never follows the player.
function NS.DrawPreviewMap(view,mapID)
    mapID=mapID or NS.PREVIEW_MAP
    local state=previewStates[view]
    if not state then state={tiles={}};previewStates[view]=state end
    for _,tile in ipairs(state.tiles) do tile:Hide() end
    local layer,files
    if C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures then
        local ok,layers=pcall(C_Map.GetMapArtLayers,mapID)
        layer=ok and type(layers)=="table" and layers[1]
        if layer then local loaded,textures=pcall(C_Map.GetMapArtLayerTextures,mapID,1);files=loaded and textures end
    end
    local legacy=not (layer and type(files)=="table" and C.Number(layer.layerWidth,1,20000) and C.Number(layer.layerHeight,1,20000) and C.Number(layer.tileWidth,1,20000) and C.Number(layer.tileHeight,1,20000))
    if legacy and mapID==NS.PREVIEW_MAP then
        layer={layerWidth=1002,layerHeight=668,tileWidth=256,tileHeight=256};files={}
        for i=1,12 do files[i]="Interface\\WorldMap\\Stranglethorn\\Stranglethorn"..i end
    elseif legacy then
        layer=nil;files=nil
    end
    local info=C_Map.GetMapInfo and C_Map.GetMapInfo(mapID)
    local mapName=info and info.name or (mapID==NS.PREVIEW_MAP and 'Stranglethorn Vale' or 'This area')
    if not layer or not files then
        if not state.message then state.message=view:CreateFontString(nil,'OVERLAY','GameFontHighlightSmall');state.message:SetPoint('CENTER');state.message:SetWidth(300) end
        state.message:SetText('Map art is unavailable for '..mapName..'.\nUse My finds here to read your discoveries.');state.message:Show()
        return {x=0,y=0,w=350,h=280},mapName,mapID,false
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
    state.message:SetText(mapName.." map art is unavailable on this client.\nMarkers are hidden.");state.message:SetShown(not success)
    if not success then for _,tile in ipairs(state.tiles) do tile:Hide() end end
    return rect,mapName,mapID,success
end

local function Build()
    local f=Panel("SmyrnaFieldDiaryOptions",800,650)
    Label(f,"Smyrna Field Diary",20,-20,"GameFontNormalLarge")
    Label(f,"Remembers ore veins, herbs, skinning, fishing schools and rare sightings.",20,-46)
    local checks={}
    local function Check(key,text,tipBody,x,y)
        local box=CreateFrame("CheckButton",nil,f,"UICheckButtonTemplate")
        box:SetPoint("TOPLEFT",x,y)
        local label=box:CreateFontString(nil,"OVERLAY","GameFontHighlightSmall")
        label:SetPoint("LEFT",box,"RIGHT",2,0); label:SetText(text)
        box:SetScript("OnClick",function(self) NS.Set(key,self:GetChecked()) end)
        Suite.AttachTooltip(box,text,tipBody,label)
        checks[key]=box
    end
    Suite.OptionSection(f,'Collection',20,-70,350)
    Check("tracking","Auto-record","Automatically record ore veins, herbs, skinning, fishing schools, and rare sightings.",18,-90)
    Check("receive","Guild sync","Accept Field Diary finds shared by party or guildmates.",210,-90)
    Suite.OptionSection(f,'Find types',20,-126,350)
    Check("mine","Mining","Record and display mining veins and ore nodes.",18,-144)
    Check("herb","Herbalism","Record and display herbs and flowers.",210,-144)
    Check("skin","Skinning","Record and display skinnable creatures.",18,-174)
    Check("fish","Fishing","Record and display fishing schools and pools.",210,-174)
    Check("rare","Rares","Record and display rare mob sightings.",18,-204)
    Suite.OptionSection(f,'Map display',20,-240,350)
    Check("worldmap","World Map","Display Field Diary map icons (vein, herb, hide, hook, star) on the World Map (Ctrl+click to inspect).",18,-258)
    Check("minimap","Minimap","Display nearby Field Diary icons on your Minimap.",210,-258)
    Check("includeShared","Guild finds","Include downloaded guild and shared discoveries alongside your personal finds.",18,-288)
    Check("areaRings","Area rings","Group nearby finds into clean cluster rings on the World Map.",210,-288)
    local areaSize=Button(f,"",20,-324,350,function()
        local span=NS.DB.settings.span; NS.Set("span",span==2 and 4 or span==4 and 8 or 2)
    end)
    Button(f,"My finds here",20,-368,165,function() NS.OpenData(false,true) end)
    Button(f,"All my finds",205,-368,165,function() NS.OpenData(true,true) end)
    Button(f,"Share with guild",20,-404,165,function() NS.Share("GUILD") end)
    Button(f,"Share with party",205,-404,165,function() NS.Share("PARTY") end)
    Button(f,"Stop sharing",20,-440,165,function() NS.StopSharing(); NS.Say("Sharing cancelled.") end)
    Button(f,"Clear old places",205,-440,165,function() NS.Prune(); if refresh then refresh() end end)
    Button(f,"Memory usage",20,-476,165,NS.Perf)
    local guildBtn=Button(f,"Guildies & Download",205,-476,165,function() if NS.OpenGuildWindow then NS.OpenGuildWindow() end end)
    Suite.StyleButton(guildBtn)
    local manageBtn=Button(f,"Manage & Delete Data",20,-512,350,function() if NS.OpenManager then NS.OpenManager() end end)
    Suite.StyleButton(manageBtn)
    local stats=Label(f,"",20,-548)
    stats:SetWidth(350)

    Label(f,"Discoveries map",420,-76,"GameFontNormalLarge")
    local exampleMode=false
    local savedButton=Button(f,'My area',420,-104,164,function() end)
    local exampleButton=Button(f,'Example',600,-104,170,function() end)
    local previewCaption=Label(f,'',420,-425);previewCaption:SetWidth(350)
    local preview=CreateFrame("Frame",nil,f,"BackdropTemplate")
    preview:SetPoint("TOPLEFT",420,-138); preview:SetSize(350,280)
    Suite.StyleCard(preview,.055,.063,.082)
    local pins={}
    local previewInfo=Label(f,"",420,-450)
    previewInfo:SetWidth(350)
    if NS.BuildDataColors then NS.BuildDataColors(f,420,-490) end
    local info=Label(f,"Tracking and map icons can be toggled separately.",420,-552)
    info:SetWidth(350)
    refresh=function()
        local settings=NS.DB.settings
        for key,box in pairs(checks) do box:SetChecked(settings[key]) end
        checks.areaRings:SetEnabled(settings.worldmap)
        areaSize:SetText("Group nearby finds: "..(settings.span==2 and "Small" or settings.span==4 and "Medium" or "Large"))
        stats:SetText(Suite.UIText("Your finds: ","heading")..Suite.UIText(NS.DB.own.count,"good").."\n"..Suite.UIText("Shared finds: ","heading")..Suite.UIText(NS.DB.shared.count,"detail").."\nClear old places removes entries not visited for 30 days.\nMap and minimap displays are optional.")
        local pos=NS.Position()
        local selectedMap=exampleMode and NS.PREVIEW_MAP or (NS.InspectMapID or (pos and pos.map) or NS.PREVIEW_MAP)
        local rect,mapName,renderedMap,available=NS.DrawPreviewMap(preview,selectedMap)
        local sample=exampleMode and Demo() or NS.DB
        if exampleMode then sample.settings=settings end
        local width,height=NS.MapWorldSize(renderedMap)
        local areas=available and C.Number(width,1,200000) and C.Number(height,1,200000) and C.Aggregate(sample,renderedMap,width,height) or {}
        Suite.SetButtonSelected(savedButton,not exampleMode);Suite.SetButtonSelected(exampleButton,exampleMode)
        previewCaption:SetText(mapName..(exampleMode and ' - example preview (not real spawns)' or ' - saved finds'))
        local visible=math.min(#areas,64)
        for i=1,visible do
            local a=areas[i]
            local pin=pins[i]
            if not pin then
                pin=CreateFrame("Frame",nil,preview)
                pin.isPreviewPin=true
                pin.halo=pin:CreateTexture(nil,"BACKGROUND"); pin.halo:SetSize(24,24); pin.halo:SetPoint("CENTER"); pin.halo:SetTexture("Interface\\Minimap\\UI-Minimap-Ping"); pin.halo:SetVertexColor(1,.86,.35,.95); pin.halo:Hide()
                pin.border=pin:CreateTexture(nil,"ARTWORK"); pin.border:SetAllPoints()
                pin.texture=pin:CreateTexture(nil,"OVERLAY"); pin.texture:SetAllPoints()
                if NS.ApplyRingTextures then NS.ApplyRingTextures(pin.border,pin.texture) end
                pin.text=pin:CreateFontString(nil,"OVERLAY","GameFontNormalSmall"); pin.text:SetPoint("LEFT",pin,"RIGHT",1,0)
                pin:EnableMouse(true)
                pin:SetScript("OnEnter",function(self) NS.AreaTooltip(self,self.area) end)
                pin:SetScript("OnLeave",function() if GameTooltip and not (GameTooltip.IsForbidden and GameTooltip:IsForbidden()) then GameTooltip:Hide() end end)
                pin:SetScript("OnMouseUp",function(self,btn)
                    if btn=="LeftButton" and IsControlKeyDown and IsControlKeyDown() and NS.OpenManager then
                        NS.OpenManager(self.mapName,self.area and self.area.kind)
                    end
                end)
                pins[i]=pin
            end
            pin.area=a; pin.mapName=mapName
            if pin.iconKind~=a.kind and NS.ApplyRingTextures then
                NS.ApplyRingTextures(pin.border,pin.texture,a.kind)
                pin.iconKind=a.kind
            end
            pin:SetSize(15,15)
            pin:ClearAllPoints(); pin:SetPoint("CENTER",preview,"TOPLEFT",rect.x+(a.hx or a.x)*rect.w,-rect.y-(a.hy or a.y)*rect.h)
            local color=C.colors[a.kind]
            pin.texture:SetVertexColor(color[1],color[2],color[3],1)
            pin.halo:SetShown(not exampleMode and NS.InspectAreaKey~=nil and a.key==NS.InspectAreaKey)
            pin.text:SetText(tostring(a.total))
            pin.text:SetTextColor(color[1],color[2],color[3])
            if NS.SourceColor and pin.border then local sr,sg,sb=NS.SourceColor(a.own>0 and "personal" or "guild"); pin.border:SetVertexColor(sr,sg,sb,1) end
            pin:Show()
        end
        for i=visible+1,#pins do pins[i]:Hide() end
        previewInfo:SetText((#areas==0 and 'No saved finds here yet. Gather and loot, or view Example.' or ((#areas>visible and (visible..' of ') or '')..#areas..' areas. Hover for details; Ctrl+click to manage.'))..'\nIcons: ore vein / herb / leather hide / fish hook / rare star. Outline = data source.')
    end
    NS.ResetExampleMode=function() exampleMode=false end
    savedButton:SetScript('OnClick',function() exampleMode=false;NS.InspectMapID=nil;NS.InspectAreaKey=nil;refresh() end)
    exampleButton:SetScript('OnClick',function() exampleMode=true;refresh() end)
    f:SetScript("OnShow",refresh)
    return f
end
function NS.OpenMapInspect(mapID,area)
    if not NS.DB then return end
    NS.InspectMapID=C.Number(mapID,1,1000000,true) and mapID or nil
    NS.InspectAreaKey=area and area.key or nil
    if NS.ResetExampleMode then NS.ResetExampleMode() end
    NS.OpenOptions()
    if NS.RefreshOptions then NS.RefreshOptions() end
end
function NS.RefreshOptions() if window and window:IsShown() then refresh() end end
function NS.OpenOptions()
    if not window then window=Build() end
    if UIParent and UIParent.GetHeight and UIParent.GetWidth then
        local uw,uh=UIParent:GetWidth(),UIParent:GetHeight()
        if type(uw)=="number" and type(uh)=="number" and uw>100 and uh>100 then
            window:SetScale(math.max(.5,math.min(1,(uh-40)/650,(uw-40)/800)))
        end
    end
    window:Show(); refresh()
    return window
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
    if NS.RefreshOptions then NS.RefreshOptions() end
end
function NS.SetEnabled(on)
    NS._enabled=on and true or false
    if not NS._enabled and NS.StopSharing then NS.StopSharing() end
    if NS.DB then NS.Configure() end
    if not NS._enabled then
        for _,fn in ipairs({"SmyrnaFieldDiaryOptions","SmyrnaFieldDiaryData","SmyrnaFieldDiaryGuild","SmyrnaFieldDiaryManager"}) do
            local w=_G[fn]; if w and w.Hide then w:Hide() end
        end
    end
end
function NS.Set(key,value)
    local settings=NS.DB.settings
    if key=="valuable" or key=="reagent" or key=="threshold" then return false end
    if type(settings[key])=="boolean" then settings[key]=not not value
    elseif key=="span" and (value==2 or value==4 or value==8) then settings.span=value
    else return false end
    NS.DB.revision=NS.DB.revision+1
    NS.Configure()
    return true
end
function NS.Perf()
    if Suite.Memory then Suite.Memory() end
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
    elseif cmd=="guild" or cmd=="download" then if NS.OpenGuildWindow then NS.OpenGuildWindow() end
    elseif cmd=="manage" or cmd=="delete" then if NS.OpenManager then NS.OpenManager() end
    elseif cmd=="stop" then NS.StopSharing(); NS.Say("Sharing cancelled.")
    elseif cmd=="data" then NS.OpenData(rest=="all",true)
    elseif cmd=="prune" then NS.Prune()
    elseif cmd=="diagnose" then NS.Diagnose()
    elseif cmd=="perf" then NS.Perf()
    elseif type(NS.DB.settings[cmd])=="boolean" then
        if rest=="on" then NS.Set(cmd,true) elseif rest=="off" then NS.Set(cmd,false) elseif rest=="" then NS.Set(cmd,not NS.DB.settings[cmd]) else NS.Say("Use on/off.") end
    else NS.Say("/sfd options | data [all] | share guild/party | stop | prune | perf") end
end

local function MigrateStoreV2ToV3(store)
    if type(store)~="table" or type(store.records)~="table" then return end
    for key,r in pairs(store.records) do
        if type(r)=="table" and (r[4]=="fish" or r[4]=="rare") then C.Delete(store,key) end
    end
end

local function PruneHoverOnlyFish(store)
    if type(store)~="table" or type(store.records)~="table" then return end
    local drop={}
    for key,r in pairs(store.records) do
        if type(r)=="table" and r[4]=="fish" and (type(r[10])~="table" or next(r[10])==nil) then
            drop[#drop+1]=key
        end
    end
    for i=1,#drop do C.Delete(store,drop[i]) end
end

frame:RegisterEvent("ADDON_LOADED")
frame:RegisterEvent("PLAYER_LOGIN")
frame:SetScript("OnEvent",function(self,event,arg1)
    if event=="ADDON_LOADED" and C.Public(arg1) and arg1=="SmyrnaSuite" then
        if type(SmyrnaFieldDiaryDB)~="table" or (SmyrnaFieldDiaryDB.version~=1 and SmyrnaFieldDiaryDB.version~=2 and SmyrnaFieldDiaryDB.version~=3) then
            SmyrnaFieldDiaryDB=C.New(string.format("%x%06x",C.Now(),math.random(0,0xffffff)))
        end
        if SmyrnaFieldDiaryDB.version==1 then
            SmyrnaFieldDiaryDB.version=2
            if type(SmyrnaFieldDiaryDB.settings)=="table" then
                SmyrnaFieldDiaryDB.settings.worldmap=false
                SmyrnaFieldDiaryDB.settings.areaRings=false
            end
        end
        if SmyrnaFieldDiaryDB.version==2 then
            -- Selective v3 migration: clear old player-standing fish/rare records while preserving mine/herb/skin finds & settings.
            SmyrnaFieldDiaryDB.version=3
            MigrateStoreV2ToV3(SmyrnaFieldDiaryDB.own)
            MigrateStoreV2ToV3(SmyrnaFieldDiaryDB.shared)
            SmyrnaFieldDiaryDB.revision=(SmyrnaFieldDiaryDB.revision or 0)+1
        end
        C.SanitizeDB(SmyrnaFieldDiaryDB)
        if not SmyrnaFieldDiaryDB.v4FishHoverPruned then
            -- Remove old hover-guessed fishing pool pins (zero looted fish) that could land on dry land.
            SmyrnaFieldDiaryDB.v4FishHoverPruned=true
            PruneHoverOnlyFish(SmyrnaFieldDiaryDB.own)
            PruneHoverOnlyFish(SmyrnaFieldDiaryDB.shared)
            SmyrnaFieldDiaryDB.revision=(SmyrnaFieldDiaryDB.revision or 0)+1
        end
        NS.DB=SmyrnaFieldDiaryDB
        NS.DB.settings.grayOnly=true
        NS.DB.settings.valuable=false
        NS.DB.settings.reagent=false
        C.Prune(NS.DB.own,C.Now()); C.Prune(NS.DB.shared,C.Now())
    elseif event=="PLAYER_LOGIN" then
        self:UnregisterEvent("PLAYER_LOGIN")
        NS.Configure()
        if NS.MapHooked then self:UnregisterEvent("ADDON_LOADED") end
    elseif event=="ADDON_LOADED" and NS.DB then
        NS.AttachMap()
        if NS.MapHooked then self:UnregisterEvent("ADDON_LOADED") end
    end
end)

end chunk(name,Module) end

Suite.Loaded[name]=true
