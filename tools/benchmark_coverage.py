"""Compare equipment/reference loading and one recommendation against v0.9.34."""
from pathlib import Path
import sys,json,subprocess,time
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tests'))
from lua_harness import runtime
def source(path,old):return subprocess.check_output(['git','show','v0.9.34:'+path],cwd=ROOT).decode('utf-8-sig') if old else (ROOT/path).read_text(encoding='utf-8-sig')
def load(l,path,old):l.execute('assert(loadstring(...))("SmyrnaSuite",Suite)',source(path,old))
def mem(l):l.execute('collectgarbage("collect")');return l.eval('collectgarbage("count")')
r={'scope':'Fresh Lua5.1 VM simulation; v0.9.34 versus current. Not native UI/FPS or total Suite RAM.','upgrader':[],'references':[]}
for old in [True,False]:
 l=runtime();before=mem(l)
 for f in ['Equipment.lua','PrivateScoring/PawnScore.lua']:load(l,'addons/SmyrnaSuite/'+f,old)
 load(l,'addons/SmyrnaEquipmentDB/Data.lua',old)
 for f in ['Modules/Upgrader.lua','AuctioneerQuotes.lua','Market.lua','UpgraderDetails.lua','UpgraderSources.lua']:load(l,'addons/SmyrnaSuite/'+f,old)
 initial=mem(l)-before;start=time.perf_counter()
 l.execute('local owner=CreateFrame("Button","CharacterChestSlot");GameTooltip:SetOwner(owner);Suite.Modules.SmyrnaUpgrader.Hover(owner,5);RunTimers()')
 elapsed=(time.perf_counter()-start)*1000
 r['upgrader'].append({'version':'before' if old else 'after','loaded_KiB':round(initial,2),'after_recommendation_KiB':round(mem(l)-before,2),'cold_total_work_ms':round(elapsed,3),'equipment_records':l.eval('Suite.Equipment.count')})
 l=runtime();before=mem(l)
 for f in ['Database.lua','DatabaseReagents.lua','ReagentProfessions.lua','Equipment.lua']:load(l,'addons/SmyrnaSuite/'+f,old)
 for pkg in ['SmyrnaBestiaryDB','SmyrnaWorkshopDB','SmyrnaRemembranceDB','SmyrnaEquipmentDB']:
  for line in source('addons/'+pkg+'/'+pkg+'.toc',old).splitlines():
   if line.endswith('.lua'):load(l,'addons/'+pkg+'/'+line,old)
 r['references'].append({'version':'before' if old else 'after','all_packed_plus_shared_core_KiB':round(mem(l)-before,2)})
(ROOT/'reports/COVERAGE-0.9.35.json').write_text(json.dumps(r,indent=2));print(json.dumps(r,indent=2))
