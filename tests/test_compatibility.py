import unittest
from lua_harness import runtime,load,ROOT

class CompatibilityTests(unittest.TestCase):
    def test_modern_spellbook_without_legacy_globals_and_guarded_values(self):
        l=runtime()
        l.execute('''
IsPlayerSpell=nil;IsSpellKnown=nil
C_SpellBook={IsSpellKnown=function(id) if id==42 then return true elseif id==43 then return 'SECRET' else return false end end}
assert(Suite.KnowsSpell(42)==true and Suite.KnowsSpell(44)==false and Suite.KnowsSpell(43)==nil)
W={};function wipe(t) for k in pairs(t) do t[k]=nil end end
''')
        text=(ROOT/'addons/SmyrnaSuite/Modules/Workshop.lua').read_text(encoding='utf-8')
        a=text.index('local _,NS=...');b=text.index('end chunk(name,Module) end',a)
        l.execute('assert(loadstring(...))("test",W)',text[a:b])
        l.execute('assert(W.Known({spell=42})==true and W.Known({spell=44})==false)')

    def test_three_and_four_part_versions(self):
        l=runtime();load(l,'addons/SmyrnaSuite/VersionCheck.lua')
        l.execute('''
local v=Suite.VersionCheck
assert(v.Newer('0.9.33','0.9.31.1'))
assert(v.Newer('0.9.32.1','0.9.32'))
assert(not v.Newer('0.9.32','0.9.32.0'))
assert(not v.Newer('bad','0.9.32') and not v.Newer('0.9.32','bad'))
''')

if __name__=='__main__':unittest.main()
