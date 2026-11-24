local _,Suite=...
local NS={}
_G.SmyrnaDB=NS
NS.raw={};NS.loaded={}
function NS.LoadBlock(key)
    if type(key)~="string" then return false end
    if NS.loaded[key] then return true end
    local text=NS.raw[key];if not text then return false end
    if key:sub(1,5)=="loot:" then
        local bestiary=(Suite and Suite.Modules and Suite.Modules.SmyrnaBestiary) or SmyrnaBestiaryAPI
        local packID=tonumber(key:sub(6))
        if not bestiary or not bestiary.RegisterPack or not packID then return false end
        local rows,items={},{}
        local existingItems=bestiary.Items
        for line in text:gmatch("[^\r\n]+") do
            local kind,idStr,rest=line:match("^([NI])\t(%d+)\t(.*)$")
            local id=idStr and tonumber(idStr)
            if id then
                if kind=="N" then rows[id]=rest
                elseif not (existingItems and existingItems[id]) then items[id]=rest end
            end
        end
        bestiary.RegisterPack(packID,rows,items)
    elseif key:sub(1,7)=="recipe:" then
        local workshop=(Suite and Suite.Modules and Suite.Modules.SmyrnaWorkshop) or SmyrnaWorkshop
        if not workshop or not workshop.RegisterReference then return false end
        local rows={}
        for line in text:gmatch("[^\r\n]+") do
            if line~="" then rows[#rows+1]=line end
        end
        workshop.RegisterReference(rows)
    elseif key~="community" then return false end
    NS.raw[key]=nil;NS.loaded[key]=true;return true
end
