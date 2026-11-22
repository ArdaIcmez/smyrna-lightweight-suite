"""Validate and package checked source; optionally install code-only packages."""
from pathlib import Path
import argparse,sys,subprocess,zipfile,hashlib,json,difflib,shutil
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'tests'))
from lua_harness import LuaRuntime
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--output',type=Path,default=ROOT/'dist')
p.add_argument('--install',type=Path)
a=p.parse_args()
packages=['SmyrnaSuite','SmyrnaBestiaryDB','SmyrnaWorkshopDB','SmyrnaRemembranceDB','SmyrnaEquipmentDB']
subprocess.run([sys.executable,'-m','unittest','discover','-s','tests','-p','test_*.py'],cwd=ROOT,check=True)
l=LuaRuntime(unpack_returned_tuples=True)
check=l.eval('function(s) local f,e=loadstring(s);return f~=nil,e end')
files=[];versions=set()
for pkg in packages:
 folder=ROOT/'addons'/pkg
 toc=(folder/(pkg+'.toc')).read_text(encoding='utf-8-sig')
 for line in toc.splitlines():
  if line.startswith('## Version:'):versions.add(line.split(':',1)[1].strip())
  if line and not line.startswith('#'):assert (folder/line.replace('\\','/')).is_file(),line
 for f in sorted(folder.rglob('*')):
  if not f.is_file():continue
  assert not any(part in {'.git','WTF','SavedVariables','__pycache__'} for part in f.parts),f
  if f.suffix=='.lua':
   ok,error=check(f.read_text(encoding='utf-8-sig'));assert ok,(f,error)
  files.append(f)
assert len(versions)==1,versions
version=versions.pop();a.output.mkdir(parents=True,exist_ok=True)
archive=a.output/('Smyrna-Lightweight-Addon-Suite-'+version+'-private.zip')
manifest={str(f.relative_to(ROOT/'addons')).replace('\\','/'):hashlib.sha256(f.read_bytes()).hexdigest() for f in files}
with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as z:
 for f in files:z.write(f,f.relative_to(ROOT/'addons'))
with zipfile.ZipFile(archive) as z:assert z.testzip() is None
(a.output/(archive.stem+'.manifest.json')).write_text(json.dumps(manifest,indent=2))
if a.install:
 target=a.install.resolve()
 assert target.name=='AddOns' and target.parent.name=='Interface','Expected explicit Interface/AddOns target'
 diff=[]
 for f in files:
  rel=f.relative_to(ROOT/'addons');dest=target/rel
  if f.suffix in {'.lua','.toc'}:
   old=dest.read_text(encoding='utf-8-sig').splitlines(True) if dest.exists() else []
   diff.extend(difflib.unified_diff(old,f.read_text(encoding='utf-8-sig').splitlines(True),fromfile='a/'+rel.as_posix(),tofile='b/'+rel.as_posix()))
 (a.output/(archive.stem+'.patch')).write_text(''.join(diff),encoding='utf-8')
 for f in files:
  dest=target/f.relative_to(ROOT/'addons');dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(f,dest)
  assert hashlib.sha256(dest.read_bytes()).hexdigest()==manifest[f.relative_to(ROOT/'addons').as_posix()]
 print('Installed and verified',len(files),'files. Personal SavedVariables untouched.')
print(archive)
print('PASS: all unit tests, Lua 5.1 syntax, TOC references, consistent version, ZIP CRC and SHA256 manifest.')
