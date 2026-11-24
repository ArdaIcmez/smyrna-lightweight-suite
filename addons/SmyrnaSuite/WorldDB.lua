local _,Suite=...
-- Unified TOC-backed World Data Service (Items, NPCs, Quests, Objects, Dungeons, Zone Indexes).
-- Static records live in WoW's C++ TOC metadata store (zero Lua GC heap for cold entities)
-- and decode lazily via C_EncodingUtil into bounded O(1) ring-buffer LRU caches.
local W={loaded=false}
Suite.WorldDB=W

local ADDON="SmyrnaWorldDB"
local GetMeta=(C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
local LoadAddOnFn=(C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
local IsLoadedFn=(C_AddOns and C_AddOns.IsAddOnLoaded) or IsAddOnLoaded
local Enc=C_EncodingUtil

local chunkCounts={}
for i=1,64 do chunkCounts["~"..i.."~"]=i end

local function MakeLRU(cap)
    return {cap=cap,map={},ring={},used={},cursor=1,hits=0,misses=0}
end

local function LRUGet(lru,key)
    local v=lru.map[key]
    if v~=nil then
        lru.hits=lru.hits+1
        lru.used[key]=true
        return v
    end
    lru.misses=lru.misses+1
    return nil
end

local function LRUPut(lru,key,val)
    if lru.map[key]==nil then
        -- Second-chance clock eviction keeps hot entities alive during full scans
        local steps=0
        while steps<lru.cap do
            local old=lru.ring[lru.cursor]
            if old==nil then break end
            if lru.used[old] then
                lru.used[old]=nil
                lru.cursor=lru.cursor%lru.cap+1
                steps=steps+1
            else
                lru.map[old]=nil
                break
            end
        end
        local victim=lru.ring[lru.cursor]
        if victim~=nil then lru.map[victim]=nil; lru.used[victim]=nil end
        lru.ring[lru.cursor]=key
        lru.cursor=lru.cursor%lru.cap+1
    end
    lru.map[key]=val
    lru.used[key]=true
    return val
end

local function LRUClear(lru)
    wipe(lru.map); wipe(lru.ring); wipe(lru.used); lru.cursor=1
end

local caches={
    N=MakeLRU(384),
    Q=MakeLRU(384),
    I=MakeLRU(512),
    O=MakeLRU(192),
    D=MakeLRU(64),
    Z=MakeLRU(32),
}
local dlistCache,encCache,metaCache
local MISSING=false -- sentinel for cached misses

function W.Ensure()
    if W.loaded then W.lastError=nil; return true end
    if Suite.Config and Suite.Config.useDB==false then W.lastError='Built-in guides disabled'; return false end
    if IsLoadedFn and IsLoadedFn(ADDON) then W.loaded=true; W.lastError=nil; return true end
    if InCombatLockdown and InCombatLockdown() then W.lastError='cannot load during combat'; return false end
    if not LoadAddOnFn then W.lastError='LoadAddOn unavailable'; return false end
    local ok,reason=LoadAddOnFn(ADDON)
    if not ok then W.lastError='LoadAddOn("'..ADDON..'") failed: '..tostring(reason); return false end
    W.loaded=true; W.lastError=nil
    return true
end

local function ReadStored(key)
    if not GetMeta then return nil end
    local val=GetMeta(ADDON,key)
    if not val then return nil end
    if val:byte(1)==126 then
        local parts=chunkCounts[val] or tonumber(val:match("^~(%d+)~$"))
        if parts then
            chunkCounts[val]=parts
            local buf={}
            for i=1,parts do
                local part=GetMeta(ADDON,key.."-"..i)
                if not part then return nil end
                buf[i]=part
            end
            return table.concat(buf)
        end
    end
    return val
end

local function DecodeKey(key,compressed)
    if not Enc or not Enc.DecodeBase64 or not Enc.DeserializeCBOR then return nil end
    local raw=ReadStored(key)
    if not raw then return nil end
    local ok1,bytes=pcall(Enc.DecodeBase64,raw)
    if not ok1 or not bytes then return nil end
    if compressed then
        if not Enc.DecompressString then return nil end
        local ok2,unz=pcall(Enc.DecompressString,bytes,1)
        if not ok2 or not unz then return nil end
        bytes=unz
    end
    local ok3,val=pcall(Enc.DeserializeCBOR,bytes)
    if not ok3 then return nil end
    return val
end

local function GetEntity(kind,id,compressed)
    if id==nil or not Suite.Public(id) then return nil end
    -- Check live Personal / Guild discovery overlay first (Phase 4 hook)
    if W.Overlay then
        local ov=W.Overlay(kind,id)
        if ov then return ov end
    end
    local lru=caches[kind]
    local hit=LRUGet(lru,id)
    if hit~=nil then return hit~=MISSING and hit or nil end
    if not W.Ensure() then return nil end
    local val=DecodeKey("X-"..kind.."-"..tostring(id),compressed)
    LRUPut(lru,id,val~=nil and val or MISSING)
    return val
end

-- Check static SmyrnaWorldDB presence without decoding CBOR or consulting Overlay.
function W.HasStatic(kind,id)
    if id==nil or not Suite.Public(id) or not GetMeta then return false end
    if not W.loaded and not W.Ensure() then return false end
    return GetMeta(ADDON,"X-"..kind.."-"..tostring(id))~=nil
end

function W.Npc(id)     return GetEntity("N",id,false) end
function W.Quest(id)   return GetEntity("Q",id,false) end
function W.Item(id)    return GetEntity("I",id,false) end
function W.Object(id)  return GetEntity("O",id,false) end
function W.Dungeon(slug) return GetEntity("D",slug,true) end
function W.Zone(mapID) return GetEntity("Z",mapID,true) end

function W.Dungeons()
    if dlistCache then return dlistCache end
    if not W.Ensure() then return {} end
    dlistCache=DecodeKey("X-DLIST",true) or {}
    return dlistCache
end

function W.Encounters()
    if encCache then return encCache end
    if not W.Ensure() then return {} end
    encCache=DecodeKey("X-ENC",true) or {}
    return encCache
end

function W.Meta()
    if metaCache then return metaCache end
    if not W.Ensure() then return nil end
    metaCache=DecodeKey("X-META",false)
    return metaCache
end

function W.TrimCache()
    for _,lru in pairs(caches) do LRUClear(lru) end
    dlistCache=nil; encCache=nil; metaCache=nil
end

function W.CacheStats()
    local out={}
    for k,lru in pairs(caches) do
        local n=0; for _ in pairs(lru.map) do n=n+1 end
        out[k]={size=n,cap=lru.cap,hits=lru.hits,misses=lru.misses}
    end
    return out
end
