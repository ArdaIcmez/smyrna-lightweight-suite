local _,NS=...
_G.SmyrnaRemembranceStore=NS
-- Initialize after Suite legacy variables load, so old history can migrate.
function NS.Open(legacy)
 if type(SmyrnaRemembranceData)~="table" or (next(SmyrnaRemembranceData)==nil and type(legacy)=="table" and next(legacy)~=nil) then
  SmyrnaRemembranceData=type(legacy)=="table" and legacy or {}
 end
 return SmyrnaRemembranceData
end
