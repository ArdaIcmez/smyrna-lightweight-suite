local addon,NS=...
_G.SmyrnaSuite=NS
if type(SmyrnaSuiteDB)~="table" then SmyrnaSuiteDB={} end
NS.Config=SmyrnaSuiteDB
NS.Config.features=NS.Config.features or {};NS.Config.data=NS.Config.data or {}
NS.Config.data.culture=nil
if type(NS.Config.useDB)~="boolean" then NS.Config.useDB=true end
NS.Modules={};NS.Loaded={};NS.Versions={}
local uiColors={heading="ffd36a",text="e8e8ee",muted="9aa4b2",good="78d49b",warning="ffad78",detail="8ecfff"}
function NS.UIText(text,tone) return "|cff"..(uiColors[tone] or uiColors.text)..tostring(text).."|r" end
function NS.Public(value)
    return not (issecretvalue and issecretvalue(value))
end
function NS.Num(v,lo,hi,integer)
    if not NS.Public(v) or type(v)~="number" or v~=v or v==math.huge or v==-math.huge then return end
    if integer and v%1~=0 then return end
    if lo and v<lo then return end
    if hi and v>hi then return end
    return v
end
function NS.LoadReference(kind,key)
    if kind=="community" then return false end
    if kind~="recipe" and kind~="loot" then NS.lastDBError="invalid kind";return false end
    if key==nil or (type(key)~="string" and type(key)~="number") or not NS.Public(key) then NS.lastDBError="invalid key";return false end
    if not NS.Config.useDB then NS.lastDBError='Suite setting "Use optional reference databases" is off';return false end
    local keyStr=tostring(key)
    local group=kind=="recipe" and ("recipe:"..keyStr) or "loot"
    if NS.Config.data[group]==false then NS.lastDBError='Suite setting "'..group..'" is off';return false end
    local load=(C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    local package=kind=="recipe" and "SmyrnaWorkshopDB" or "SmyrnaBestiaryDB"
    if not NS.ReferencePackages then NS.ReferencePackages={} end
    if not NS.ReferencePackages[package] then
        if InCombatLockdown and InCombatLockdown() then NS.lastDBError="cannot load "..package.." during combat";return false end
        if not load then NS.lastDBError="LoadAddOn API unavailable";return false end
        local ok,reason=load(package)
        if not ok then NS.lastDBError="LoadAddOn("..package..") failed: "..tostring(reason);return false end
        NS.ReferencePackages[package]=true
    end
    if not SmyrnaDB or not SmyrnaDB.LoadBlock then NS.lastDBError="SmyrnaDB unavailable";return false end
    local block=kind=="loot" and ("loot:"..keyStr) or group
    local loaded=SmyrnaDB.LoadBlock(block)
    if not loaded then NS.lastDBError="block "..tostring(block).." missing in "..package;return false end
    NS.lastDBError=nil
    return true
end

-- Forever returns given name and surname as separate fields, not name and realm.
function NS.PlayerName(first,last)
    if issecretvalue and (issecretvalue(first) or issecretvalue(last)) then return end
    if type(first)~="string" or first=="" then return end
    if last~=nil and type(last)~="string" then return end
    return first..(last and last~="" and (" "..last) or "")
end
