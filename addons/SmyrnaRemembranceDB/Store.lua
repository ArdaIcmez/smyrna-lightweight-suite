local _,NS=...
_G.SmyrnaRemembranceStore=NS
-- Initialize after Suite legacy variables load, so old history can migrate.
function NS.Open(legacy)
 if type(SmyrnaRemembranceData)~="table" then SmyrnaRemembranceData=type(legacy)=="table" and legacy or {} end
 return SmyrnaRemembranceData
end
