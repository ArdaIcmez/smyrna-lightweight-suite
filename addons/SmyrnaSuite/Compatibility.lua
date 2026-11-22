local _,S=...
-- Modern Forever APIs first; legacy functions are optional, not prerequisites.
local function Query(fn,id)
 if type(fn)~='function' then return end
 local ok,value=pcall(fn,id)
 if ok and not (issecretvalue and issecretvalue(value)) and type(value)=='boolean' then return value end
end
function S.KnowsSpell(id)
 local modern=Query(C_SpellBook and C_SpellBook.IsSpellKnown,id)
 if modern==true then return true end
 local player=Query(IsPlayerSpell,id);if player==true then return true end
 local legacy=Query(IsSpellKnown,id);if legacy==true then return true end
 if modern==false or player==false or legacy==false then return false end
end
