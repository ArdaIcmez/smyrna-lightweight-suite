import unittest
from lua_harness import runtime, load, ROOT


class StorageTests(unittest.TestCase):
    def test_loot_identity_never_autoloads_equipment(self):
        l=runtime();l.execute('B={};Suite.Equipment={Ensure=function() error("Unexpected equipment load") end}')
        source=(ROOT/'addons/SmyrnaSuite/Modules/Bestiary.lua').read_text(encoding='utf-8')
        a=source.index('local _,NS=...');b=source.index('end chunk(name,Module) end',a)
        l.execute('assert(loadstring(...))("test",B)',source[a:b])
        l.execute('local name=B.Core.Item(2770);assert(type(name)=="string")')

    def test_activity_migration_and_all_events_preserved(self):
        l=runtime();load(l,'addons/SmyrnaSuite/Storage.lua')
        l.execute('''
local log='Q,42,1800000000;D,36,1800000001;'
for i=1,10000 do log=Suite.EventLog.Append(log,'Q,'..i..',1800000002;') end
local count=0;for entry in Suite.EventLog.Entries(log) do count=count+1;if count==1 then assert(entry=='Q,42,1800000000') end end
assert(count==10002 and type(log)=='table')
for _,chunk in ipairs(log) do assert(#chunk<=1024) end
Suite.Modules.SmyrnaRemembrance={DB={activities={player=log},activityNames={}},Public=function() return true end,Format=function(t) return tostring(t) end}
''')
        load(l,'addons/SmyrnaSuite/RemembranceActivities.lua')
        l.execute('local lines,count=Suite.Modules.SmyrnaRemembrance.Activities.Lines("player");assert(count==10002 and #lines>count)')

    def workshop(self):
        l=runtime();l.execute('W={};function wipe(t) for k in pairs(t) do t[k]=nil end end')
        source=(ROOT/'addons/SmyrnaSuite/Modules/Workshop.lua').read_text(encoding='utf-8')
        a=source.index('local _,NS=...');b=source.index('end chunk(name,Module) end',a)
        l.execute('assert(loadstring(...))("test",W)',source[a:b]);return l

    def test_workshop_migration_save_counts_and_disabled_reference_fallback(self):
        l=self.workshop()
        l.execute('''
SmyrnaWorkshopDB={recipes={old={name='Recipe',profession='Cooking',spell=42,mats={{769,2},{159,1}}}}}
W.Init();assert(type(W.DB.recipes.old)=='string' and W.Uses(769)[1].learned)
assert(W.Uses(769)[1].name=='Recipe' and W.Uses(769)[1].mats[1][2]==2)
assert(W.Save('old','Cooking','Recipe',{{769,2},{159,1}},42)==false)
assert(W.Save('new','Cooking','New recipe',{{769,3}},43))
W.Reindex();assert(#W.Uses(769)==2 and W.recipeCount==2)
''')

    def test_pooled_equipment_matches_previous_sources(self):
        # Compare the entire finite source catalog against the preceding release.
        import subprocess
        old=subprocess.check_output(['git','show','v0.9.31.1:addons/SmyrnaEquipmentDB/Data.lua'],cwd=ROOT).decode('utf-8-sig')
        l=runtime();load(l,'addons/SmyrnaSuite/Equipment.lua')
        l.execute(old);original=dict(l.globals().Suite.Equipment.records.items())
        load(l,'addons/SmyrnaEquipmentDB/Data.lua')
        g=l.globals().Suite.Equipment
        for id,raw in original.items():
            old_fields=raw.split('\t');new_fields=g.records[id].split('\t')
            self.assertEqual(old_fields[:-1],new_fields[:-1])
            rebuilt=';'.join(g.sourcePool[int(n)] for n in new_fields[-1].split(',') if n)
            self.assertEqual(old_fields[-1],rebuilt)
        l.execute('local r=Suite.Equipment.Get(2870,true);assert(r.sourceIDs and #r.sources==0);Suite.Equipment.Sources(r);assert(not r.sourceIDs and #r.sources>0)')

    def test_guild_cap_skips_whole_sample_without_deleting_old_data(self):
        l=runtime()
        l.execute('''
function GetGuildInfo() return 'Test guild' end
Suite.Modules.SmyrnaBestiary={DB={build='71037',settings={enabled=true,guildShare=true},revision=0},Core={Public=function() return true end,Number=function(v,a,b) return type(v)=='number' and v>=a and v<=b end,NPC=function() return 42 end},Changed=function() end}
''')
        load(l,'addons/SmyrnaSuite/BestiaryGuild.lua')
        l.execute('''
local b=Suite.Modules.SmyrnaBestiary
assert(b.ReceiveGuild('1|71037|M1|0|guid1|2589','GUILD','Friend'))
local d=b.DB.guildSamples.guilds['Test guild@Test realm'];local original=d.totals['71037:M1:0:42']
for i=1,4095 do d.totals['old'..i]='1|2589:1' end;d.keyCount=nil
assert(not b.ReceiveGuild('1|71037|M2|0|guid2|2589','GUILD','Friend'))
assert(d.totals['71037:M1:0:42']==original and not d.recent.guid2 and b.GuildCapacityReached)
assert(b.ReceiveGuild('1|71037|M1|0|guid3|2589','GUILD','Friend'))
''')

if __name__=='__main__':unittest.main()
