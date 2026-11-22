"""Read-only benchmark of installed reference data and actual Diary core."""
from pathlib import Path
import sys,time,json,hashlib
sys.path.insert(0,r'C:/Users/aicme/Documents/Codex/2026-11-17/pla/work/lua-runtime-map')
from lupa.lua51 import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]
BASE=Path(r'E:/World of Warcraft/_forever_/Interface/AddOns')
def vm():
 l=LuaRuntime(unpack_returned_tuples=True)
 l.execute('SmyrnaSuite={ReagentProfessions={}};Suite=SmyrnaSuite;time=os.time;GetServerTime=os.time')
 return l
def memory(l):
 l.execute('collectgarbage("collect")')
 return l.eval('collectgarbage("count")')
def load(l,p):
 l.execute('assert(loadstring(...))("benchmark",{})',p.read_text(encoding='utf-8-sig'))
r={'scope':'Installed 0.9.30.4; Lua 5.1 simulation, full GC; excludes native UI/engine and personal saved data. No gameplay FPS claim.','databases':[]}
l=vm();load(l,BASE/'SmyrnaSuite/Database.lua')
for pkg in ['SmyrnaBestiaryDB','SmyrnaWorkshopDB','SmyrnaRemembranceDB']:
 before=memory(l);start=time.perf_counter();size=0
 for name in (BASE/pkg/(pkg+'.toc')).read_text().splitlines():
  if name.endswith('.lua'):
   p=BASE/pkg/name;size+=p.stat().st_size;load(l,p)
 elapsed=(time.perf_counter()-start)*1000
 r['databases'].append({'package':pkg,'source_bytes':size,'load_ms':round(elapsed,3),'retained_KiB':round(memory(l)-before,2)})
r['packed_blocks']=l.eval('function() local n,b=0,0;for _,v in pairs(SmyrnaDB.raw) do n=n+1;b=b+#v end;return n,b end')()
l.execute('decodedLoot={};decodedRecipes={};SmyrnaBestiaryAPI={RegisterPack=function(id,rows,items) decodedLoot[id]={rows,items} end};SmyrnaWorkshop={RegisterReference=function(rows) decodedRecipes[#decodedRecipes+1]=rows end}')
for prefix in ['loot:','recipe:']:
 before=memory(l);start=time.perf_counter()
 count=l.eval('function(prefix) local keys={};for k in pairs(SmyrnaDB.raw) do if k:sub(1,#prefix)==prefix then keys[#keys+1]=k end end;for _,k in ipairs(keys) do assert(SmyrnaDB.LoadBlock(k)) end;return #keys end')(prefix)
 r.setdefault('decode_all',[]).append({'kind':prefix,'blocks':count,'total_ms':round((time.perf_counter()-start)*1000,3),'additional_KiB':round(memory(l)-before,2),'note':'Actual decoder; registration tables retained; excludes production feature indexes.'})
r['diary']=[]
l=vm();source=(BASE/'SmyrnaSuite/Modules/FieldDiary.lua').read_text(encoding='utf-8-sig');start=source.index('local _, NS = ...');end=source.index('end chunk(name,Module) end',start)
l.execute('Diary={};assert(loadstring(...))("benchmark",Diary)',source[start:end])
for n in [100,1000,4000,100000,1000000]:
 l.execute('db=Diary.Core.New("benchmark");collectgarbage("collect")');before=memory(l);start=time.perf_counter()
 l.execute('local n=...;local c=Diary.Core;for i=1,n do local s=i%2==0 and db.own or db.shared;local x=i%1000;local y=math.floor(i/1000);c.Insert(s,c.Key(1434,x,y,"mine"),{1434,x,y,"mine",1,1,0,1,1800000000,{[2770]={1,0}},1}) end',n)
 ms=(time.perf_counter()-start)*1000;after=memory(l)
 start=time.perf_counter();l.execute('areas=Diary.Core.Aggregate(db,1434,6000,6000)');cold=(time.perf_counter()-start)*1000
 start=time.perf_counter();l.execute('for i=1,100 do Diary.Core.Aggregate(db,1434,6000,6000) end');warm=(time.perf_counter()-start)*10
 r['diary'].append({'inputs':n,'retained_records':l.eval('db.own.count+db.shared.count'),'retained_KiB':round(after-before,2),'ingest_total_ms':round(ms,3),'aggregate_cold_ms':round(cold,3),'aggregate_repeated_ms':round(warm,4)})
 l.execute('areas=nil;db=nil;collectgarbage("collect")')
r['remembrance']=[]
l=vm();source=(BASE/'SmyrnaSuite/Modules/Remembrance.lua').read_text(encoding='utf-8-sig');start=source.index('local _,NS=...');end=source.index('end chunk(name,Module) end',start)
l.execute('R={};assert(loadstring(...))("benchmark",R)',source[start:end])
for n in [100000,1000000]:
 l.execute('records={};collectgarbage("collect")');before=memory(l);start=time.perf_counter()
 l.execute('local n=...;for i=1,n do records["P:Player-1-"..i]=R.PackRecord("Player"..i,1800000000000,1434,60,"Stranglethorn Vale",1790000000000) end',n)
 ms=(time.perf_counter()-start)*1000;after=memory(l)
 start=time.perf_counter();l.execute('for i=1,100000 do local v=records["P:Player-1-"..(i*97%...+1)] end',n);lookup=(time.perf_counter()-start)*1000
 r['remembrance'].append({'players':n,'retained_MiB':round((after-before)/1024,3),'bytes_per_player':round((after-before)*1024/n,1),'build_ms':round(ms,2),'lookup_100k_ms':round(lookup,2),'scope':'Actual PackRecord and unique keys; no activities, histories, UI or other indexes.'})
 l.execute('records=nil;collectgarbage("collect")')
out=ROOT/'reports/PERFORMANCE-2026-11-22.json';out.parent.mkdir(exist_ok=True);out.write_text(json.dumps(r,indent=2));print(json.dumps(r,indent=2))
