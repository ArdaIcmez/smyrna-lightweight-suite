import unittest
from lua_harness import upgrader_runtime

class EquipmentCoverageTests(unittest.TestCase):
    def test_manascale_treads_has_forever_stats_and_real_source(self):
        l=upgrader_runtime()
        l.execute('''
local g=Suite.Equipment;local row=g.Get(273042)
assert(row.name=='Manascale Treads' and row.level==28 and row.inv==8 and row.subclass=='Mail')
assert(row.stats.Strength==7 and row.stats.Intellect==7 and row.stats.Armor==157 and row.stats.CritRating==7)
assert(row.bind=='Binds when picked up' and row.provenance=='WoWSims Forever')
assert(row.sources[1].name=='Mana Devourer' and row.sources[1].kind=='Dungeon' and row.sources[1].zone=='City of Dalaran')
''')

    def test_algae_fists_current_dungeon_and_quest_upgrades(self):
        l=upgrader_runtime()
        l.execute('''
local u=Suite.Modules.SmyrnaUpgrader;local g=Suite.Equipment
assert(g.Get(6906,true).stats.Strength==8 and not g.Get(6906,true).estimated)
UnitLevel=function() return 37 end;equipment[10]=6906
local owner=CreateFrame('Button','CharacterHandsSlot');GameTooltip:SetOwner(owner)
u.Hover(owner,10);RunTimers()
assert(#u.LastResult.groups.Dungeon>0 and #u.LastResult.groups.Quest>0)
for _,key in ipairs({'Dungeon','Quest'}) do for _,c in ipairs(u.LastResult.groups[key]) do assert(not c.future and c.row.level<=37) end end
''')

    def test_next_available_fallback_includes_armor_training(self):
        l=upgrader_runtime()
        l.execute('''
local u=Suite.Modules.SmyrnaUpgrader
assert(Suite.Equipment.ArmorGuide(2,37):find('learn Plate at level 40',1,true))
assert(Suite.Equipment.ArmorGuide(7,37):find('learn Mail at level 40',1,true))
assert(Suite.Equipment.ArmorGuide(8,37):find('no armor-tier change',1,true))
UnitLevel=function() return 37 end;equipment[10]=6906
-- Force current source categories empty to exercise the separate fallback pass.
local original=u.SelectSource
u.SelectSource=function(row,level)
 if level<40 then return {} end
 if row.subclass=='Plate' then return {Dungeon={kind='Dungeon',name='Test dungeon',zone='',level=40,skill=0,reference='Fixture'}} end
 return {}
end
local owner=CreateFrame('Button','CharacterHandsSlot');GameTooltip:SetOwner(owner)
u.Hover(owner,10);RunTimers()
local list=u.LastResult.groups.Dungeon;assert(#list>0)
assert(list[1].future and list[1].availableLevel>=40 and list[1].training=='Plate training at level 40')
assert(list[1].row.subclass=='Plate')
''')

if __name__=='__main__':unittest.main()
