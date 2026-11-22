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
function NS.LoadReference(kind,key)
    if kind~="recipe" and kind~="loot" then return false end
    if not NS.Config.useDB then return false end
    local group=kind=="recipe" and ("recipe:"..key) or kind
    if NS.Config.data[group]==false then return false end
    local load=(C_AddOns and C_AddOns.LoadAddOn) or LoadAddOn
    local package=kind=="recipe" and "SmyrnaWorkshopDB" or "SmyrnaBestiaryDB"
    if not NS.ReferencePackages then NS.ReferencePackages={} end
    if not NS.ReferencePackages[package] then
        if not load or not load(package) then return false end
        NS.ReferencePackages[package]=true
    end
    return SmyrnaDB.LoadBlock(kind=="loot" and ("loot:"..key) or group)
end

-- Forever returns given name and surname as separate fields, not name and realm.
function NS.PlayerName(first,last)
    if issecretvalue and (issecretvalue(first) or issecretvalue(last)) then return end
    if type(first)~="string" or first=="" then return end
    if last~=nil and type(last)~="string" then return end
    return first..(last and last~="" and (" "..last) or "")
end
