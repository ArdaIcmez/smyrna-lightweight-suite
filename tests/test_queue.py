import unittest
from lua_harness import runtime, load, ROOT


class QueueRegressionTests(unittest.TestCase):
    def test_loot_frame_and_owner_guards(self):
        l = runtime()
        load(l, 'addons/SmyrnaSuite/LootInteraction.lua')
        l.execute('''
local owner=CreateFrame('Button','LootButton1')
assert(Suite.IsLootInteraction(owner))
local child=CreateFrame('Frame',nil,owner);assert(Suite.IsLootInteraction(child))
assert(not Suite.IsLootInteraction(UIParent))
LootFrame=CreateFrame('Frame','LootFrame');assert(Suite.IsLootInteraction())
LootFrame:Hide();assert(not Suite.IsLootInteraction())
''')

    def test_diary_map_wrapper_reuses_cache_and_invalidates(self):
        l = runtime()
        source = (ROOT/'addons/SmyrnaSuite/Modules/FieldDiary.lua').read_text(encoding='utf-8')
        a = source.index('local _,NS=...', source.index('-- Internal module source: Maps.lua'))
        b = source.index('function NS.AreaTooltip', a)
        l.execute('''calls=0;Diary={DB={revision=1},Core={Number=function(v) return type(v)=='number' end,
Aggregate=function() calls=calls+1;return {calls} end}};C_Map={GetMapWorldSize=function() return 6000,6000 end}''')
        l.execute('assert(loadstring(...))("test",Diary)', source[a:b])
        l.execute('''
local a=Diary.Areas(1434);assert(Diary.Areas(1434)==a and calls==1)
Diary.Areas(1);assert(Diary.Areas(1434)==a and calls==2)
Diary.DB.revision=2;assert(Diary.Areas(1434)~=a and calls==3)
Diary.Areas(2);Diary.Areas(3);assert(calls==5)
''')

    def test_defenses_are_class_specific_and_hunter_uses_ranged_skill(self):
        l=runtime()
        l.execute('''
class='HUNTER';function UnitClass() return class,class end
function UnitGUID() return '681' end
function UnitLevel(unit) return unit=='player' and 37 or 31 end
function UnitAttackBothHands() error('Hunter must not read melee skill') end
function UnitRangedAttack() return 180,10,-5 end
function UnitRangedDamage() return 2.8,60,90 end
Suite.Modules.SmyrnaBestiary={Core={Mob=function() return {'Tiger',31,31,0} end,NPC=tonumber},Matchups={}}
row={armor=1234,scope='Classic',source='test',schools={arcane={resistance=0},fire={resistance=0},frost={resistance=100}}}
Suite.Modules.SmyrnaBestiary.Matchups.Evidence=function() return row end
''')
        load(l,'addons/SmyrnaSuite/BestiaryDefenseImpact.lua')
        l.execute('''
local m=Suite.Modules.SmyrnaBestiary.Matchups
assert(math.abs(m.ArmorFraction(1234,37)-1234/4779)<1e-12)
local text=m.Text(681);assert(text:find('185 vs estimated defense 155',1,true))
class='MAGE';text=m.Text(681)
assert(text:find('Frost: resistant',1,true) and not text:find('Weapon') and not text:find('Armor'))
''')


if __name__=='__main__':
    unittest.main()
