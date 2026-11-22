local NS={}
_G.SmyrnaDB=NS
NS.raw={};NS.loaded={}
local function Fields(line)
    local fields={};for field in (line.."\t"):gmatch("(.-)\t") do fields[#fields+1]=field end;return fields
end
function NS.LoadBlock(key)
    if NS.loaded[key] then return true end
    local text=NS.raw[key];if not text then return false end
    if key:sub(1,5)=="loot:" then
        if not SmyrnaBestiaryAPI then return false end
        local rows,items={},{}
        for line in text:gmatch("[^\n]+") do
            local f=Fields(line);local id=tonumber(f[2])
            if f[1]=="N" then rows[id]={f[3],tonumber(f[4]),tonumber(f[5]),tonumber(f[6]),f[7],f[8],f[9]}
            else items[id]={tonumber(f[3]),f[4]} end
        end
        SmyrnaBestiaryAPI.RegisterPack(tonumber(key:sub(6)),rows,items)
    elseif key:sub(1,7)=="recipe:" then
        if not SmyrnaWorkshop then return false end
        local rows={}
        for line in text:gmatch("[^\n]+") do
            local f=Fields(line);local mats={}
            for id,count in f[5]:gmatch("(%d+):(%d+)") do mats[#mats+1]={tonumber(id),tonumber(count)} end
            rows[#rows+1]={spell=tonumber(f[1]),profession=f[2],name=f[3],skill=tonumber(f[4]),mats=mats}
        end
        SmyrnaWorkshop.RegisterReference(rows)
    elseif key~="community" then return false end
    NS.raw[key]=nil;NS.loaded[key]=true;return true
end
