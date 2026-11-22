local _,S=...
-- Bounded append copies; legacy strings migrate lazily without losing events.
local Log={};S.EventLog=Log
local LIMIT=1024
local function Push(log,entry)
 local i=#log;local tail=log[i]
 if tail and #tail+#entry<=LIMIT then log[i]=tail..entry else log[i+1]=entry end
end
function Log.Append(value,entry)
 local log=value
 if type(log)~='table' then
  log={}
  if type(value)=='string' then for old in value:gmatch('[^;]+;') do Push(log,old) end end
 end
 Push(log,entry);return log
end
function Log.Entries(value)
 if type(value)=='string' then return value:gmatch('([^;]+);') end
 local index,iter=0,nil
 return function()
  while true do
   if iter then local entry=iter();if entry then return entry end end
   index=index+1;local chunk=type(value)=='table' and value[index]
   if type(chunk)~='string' then return end
   iter=chunk:gmatch('([^;]+);')
  end
 end
end
