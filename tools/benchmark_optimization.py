"""Compare v0.9.31.1 with current code in fresh Lua 5.1 VMs."""
from pathlib import Path
import sys,subprocess,json,time
ROOT=Path(__file__).resolve().parents[1];sys.path.insert(0,str(ROOT/'tests'))
from lua_harness import runtime,load,upgrader_runtime
def source(path,old=False):
 return subprocess.check_output(['git','show','v0.9.31.1:'+path],cwd=ROOT).decode('utf-8-sig') if old else (ROOT/path).read_text(encoding='utf-8-sig')
def execute(l,text):l.execute('assert(loadstring(...))("SmyrnaSuite",Suite)',text)
def mem(l):l.execute('collectgarbage("collect")');return l.eval('collectgarbage("count")')
report={'scope':'Lua5.1 simulation, fresh VMs, retained heap after GC. Same machine/input. Not native WoW memory, rendering or FPS.','upgrader':[],'workshop':[],'activities':[],'references':[]}
for old in [True,False]:
 l=runtime();before=mem(l)
 for f in ['Database.lua','DatabaseReagents.lua','ReagentProfessions.lua','Equipment.lua']:
  execute(l,source('addons/SmyrnaSuite/'+f,old))
 costs={};start=mem(l)
 for pkg in ['SmyrnaBestiaryDB','SmyrnaWorkshopDB','SmyrnaRemembranceDB','SmyrnaEquipmentDB']:
  prior=mem(l)
  for line in source('addons/'+pkg+'/'+pkg+'.toc',old).splitlines():
   if line.endswith('.lua'):execute(l,source('addons/'+pkg+'/'+line,old))
  costs[pkg]=round(mem(l)-prior,2)
 report['references'].append({'version':'before' if old else 'after','package_retained_KiB':costs,'all_packed_plus_shared_core_KiB':round(mem(l)-before,2),'scope':'All reference packages loaded, before block decoding; excludes production feature indexes and personal data.'})
for old in [True,False]:
 l=runtime();before=mem(l)
 for f in ['Equipment.lua','PrivateScoring/PawnScore.lua']:
  execute(l,source('addons/SmyrnaSuite/'+f,old))
 execute(l,source('addons/SmyrnaEquipmentDB/Data.lua',old))
 for f in ['Modules/Upgrader.lua','AuctioneerQuotes.lua','Market.lua','UpgraderDetails.lua']:
  execute(l,source('addons/SmyrnaSuite/'+f,old))
 if not old:execute(l,source('addons/SmyrnaSuite/UpgraderSources.lua'))
 packed=mem(l)-before
 l.execute('scoreCalls=0;local u=Suite.Modules.SmyrnaUpgrader;local original=u.Score;u.Score=function(...) scoreCalls=scoreCalls+1;return original(...) end')
 start=time.perf_counter();l.execute('owner=CreateFrame("Button","CharacterChestSlot");GameTooltip:SetOwner(owner);Suite.Modules.SmyrnaUpgrader.Hover(owner,5);RunTimers()');elapsed=(time.perf_counter()-start)*1000
 after=mem(l)-before
 start=time.perf_counter();l.execute('for i=1,1000 do Suite.Modules.SmyrnaUpgrader.Hover(owner,5) end');cached=(time.perf_counter()-start)
 report['upgrader'].append({'version':'before' if old else 'after','loaded_KiB':round(packed,2),'after_recommendation_KiB':round(after,2),'cold_total_ms':round(elapsed,3),'score_calls_cold':l.eval('scoreCalls')-1000,'cached_hover_mean_ms':round(cached,5),'gear_count':l.eval('Suite.Equipment.count'),'top_count':l.eval('#Suite.Modules.SmyrnaUpgrader.LastResult.ranked')})
 # Learned recipes including the live ingredient index, not storage alone.
 l=runtime();l.execute('W={};function wipe(t) for k in pairs(t) do t[k]=nil end end')
 text=source('addons/SmyrnaSuite/Modules/Workshop.lua',old);a=text.index('local _,NS=...');b=text.index('end chunk(name,Module) end',a)
 l.execute('assert(loadstring(...))("test",W)',text[a:b]);before=mem(l)
 l.execute('SmyrnaWorkshopDB={recipes={}};for i=1,3000 do SmyrnaWorkshopDB.recipes["recipe:"..i]={profession="Cooking",name="Recipe "..i,spell=i,mats={{10000+i,2},{20000+i,1}},learned=true} end;W.Init()')
 report['workshop'].append({'version':'before' if old else 'after','recipes':3000,'including_index_KiB':round(mem(l)-before,2)})
for n in [10000,100000,1000000]:
 for old in ([True,False] if n==10000 else [False]):
  l=runtime();execute(l,source('addons/SmyrnaSuite/Storage.lua'));before=mem(l);start=time.perf_counter()
  body='log=(log or "")..entry' if old else 'log=Suite.EventLog.Append(log,entry)'
  l.execute('local n=...;for i=1,n do local entry="Q,"..i..",1800000000;";'+body+' end',n)
  elapsed=(time.perf_counter()-start)*1000
  report['activities'].append({'version':'before' if old else 'after','events':n,'append_ms':round(elapsed,2),'retained_KiB':round(mem(l)-before,2)})
import zipfile
with zipfile.ZipFile(ROOT/'.local/optimization-before.zip') as z:
 before=sum(i.file_size for i in z.infolist() if i.filename.startswith('addons/') and not i.is_dir())
after=sum(p.stat().st_size for p in (ROOT/'addons').rglob('*') if p.is_file())
report['installed_package_bytes']={'before':before,'after':after}
(ROOT/'reports/OPTIMIZATION-0.9.32.json').write_text(json.dumps(report,indent=2));print(json.dumps(report,indent=2))
