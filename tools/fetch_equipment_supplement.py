"""Download a pinned WoWSims candidate without replacing the active input cache."""
from pathlib import Path
import argparse,json,urllib.request,urllib.parse,tempfile,hashlib
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser(description=__doc__);p.add_argument('--ref',default='master');p.add_argument('--output',type=Path,default=ROOT/'.local/equipment-supplement-candidate');a=p.parse_args()
target=a.output.resolve();assert target.is_relative_to((ROOT/'.local').resolve()),'Candidate must stay in ignored .local'
assert not target.exists(),'Candidate already exists; preserve it or choose a new output name'
def fetch(url):
 req=urllib.request.Request(url,headers={'User-Agent':'Smyrna-equipment-import'})
 with urllib.request.urlopen(req,timeout=30) as response:
  data=response.read(50*1024*1024+1)
  assert len(data)<=50*1024*1024,'Unexpected response size'
  return data
meta=json.loads(fetch('https://api.github.com/repos/wowsims/forever/commits/'+urllib.parse.quote(a.ref,safe='')));commit=meta['sha']
paths=['assets/database/db.json','assets/database/leftover_db.json','proto/common.proto','proto/ui.proto','LICENSE']
target.parent.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(dir=target.parent) as tmp:
 stage=Path(tmp)/'candidate';stage.mkdir();hashes={}
 for path in paths:
  data=fetch('https://raw.githubusercontent.com/wowsims/forever/'+commit+'/'+path);name=path.replace('/','_');(stage/name).write_bytes(data);hashes[name]=hashlib.sha256(data).hexdigest()
 main=json.loads((stage/'assets_database_db.json').read_text());left=json.loads((stage/'assets_database_leftover_db.json').read_text())
 assert len(main['items'])>7000 and len(left['items'])>3000,'Incomplete export'
 assert any(i.get('id')==273042 and i.get('name')=='Manascale Treads' for i in main['items'])
 assert 'MIT License' in (stage/'LICENSE').read_text()
 (stage/'wowsims-tree.json').write_text(json.dumps({'sha':meta['commit']['tree']['sha'],'commit':commit,'input_sha256':hashes},indent=2))
 stage.rename(target)
print('Validated candidate',commit,'at',target,'; active inputs and installed addon unchanged.')
