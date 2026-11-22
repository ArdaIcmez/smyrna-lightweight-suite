"""Intern repeated equipment acquisition rows; preserve all source facts."""
from pathlib import Path
import json,sys,os
def pool(path,LuaRuntime):
 l=LuaRuntime(unpack_returned_tuples=True);l.execute('SmyrnaSuite={Equipment={}}')
 text=path.read_text(encoding='utf-8-sig');l.execute(text);g=l.globals().SmyrnaSuite.Equipment
 if g.sourcePool is not None:return
 records=dict(g.records.items());unique=set()
 for raw in records.values():unique.update(s for s in raw.split('\t')[-1].split(';') if s)
 sources=sorted(unique);ids={s:i+1 for i,s in enumerate(sources)}
 for id,raw in records.items():
  fields=raw.split('\t');fields[-1]=','.join(str(ids[s]) for s in fields[-1].split(';') if s);records[id]='\t'.join(fields)
 def lua(v):
  if isinstance(v,str):return json.dumps(v,ensure_ascii=False)
  if isinstance(v,(int,float)):return str(v)
  if isinstance(v,dict):return '{'+','.join('['+lua(k)+']='+lua(x) for k,x in sorted(v.items()))+'}'
  return '{'+','.join(map(lua,v))+'}'
 start=text.index('G.records=');end=text.index('\nG.slots=',start)
 replacement='G.sourcePool='+lua(sources)+'\nG.records='+lua(records)
 path.write_text(text[:start]+replacement+text[end:],encoding='utf-8')
 print('Pooled',len(sources),'unique sources;',len(text.encode()),'->',path.stat().st_size,'bytes')
if __name__=='__main__':
 if os.environ.get('SMYRNA_LUPA_PATH'):sys.path.insert(0,os.environ['SMYRNA_LUPA_PATH'])
 from lupa.lua51 import LuaRuntime
 pool(Path(__file__).resolve().parents[1]/'addons/SmyrnaEquipmentDB/Data.lua',LuaRuntime)
