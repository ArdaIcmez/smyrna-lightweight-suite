from pathlib import Path
import json,re,sys,hashlib,shutil,os,argparse
ROOT=Path(__file__).resolve().parents[1]
args=argparse.ArgumentParser(description='Build private Upgrader scoring and shared equipment references from pinned local inputs.')
args.add_argument('--input',type=Path,default=ROOT/'.local/equipment-input')
args.add_argument('--lua-runtime',default=os.environ.get('SMYRNA_LUPA_PATH'))
options=args.parse_args()
if options.lua_runtime:sys.path.insert(0,options.lua_runtime)
from lupa.lua51 import LuaRuntime
cache=options.input
items=json.loads((cache/'items.json').read_text());sources=json.loads((cache/'item_sources.json').read_text());meta=json.loads((cache/'meta.json').read_text())
assert len(items)==meta['counts']['items'], 'Incomplete item export'
assert len(sources)==meta['counts']['item_sources'], 'Incomplete source export'
state=json.loads((ROOT/'.local/addon-sources/Pawn/current.json').read_text());pawn=ROOT/'.local/addon-sources/Pawn/snapshots'/state['active']/'source'
version=json.loads((pawn.parent/'snapshot.json').read_text())['version']
l=LuaRuntime(unpack_returned_tuples=True,register_eval=False,register_builtins=False,max_memory=32*1024*1024)
l.execute('local d=debug;d.sethook(function() error("Weight import exceeded instruction budget") end,"",1000000);os=nil;io=nil;package=nil;require=nil;dofile=nil;loadfile=nil;debug=nil;python=nil')
l.execute('''VgerCore=setmetatable({IsForever=true},{__index=function() return false end}); PawnIgnoreStatValue=-1000000; SECONDARYHANDSLOT='Off Hand'; function PawnGetClassInfo() return 'Rogue' end; PawnLocal={UI={StarterProvider='Classic'}}; captured={}; function PawnAddPluginScaleFromTemplate(provider,class,spec,values) captured[class..':'..(spec or 'offhand')]=values; return {} end; function PawnAddPluginScaleProvider(name,label,fn) fn() end; function UnitClass() return 'Paladin','PALADIN' end; function PawnSetAllScaleProviderScalesVisible() end; function PawnGetVisibleScaleCount() return 1 end''')
l.execute((pawn/'ClassicHawsJon.lua').read_text(encoding='utf-8-sig'))
print('captured scales',len(list(l.globals().captured)))
def lua(v):
 if isinstance(v,str): return json.dumps(v,ensure_ascii=False)
 if v is True:return 'true'
 if v is False:return 'false'
 if v is None:return 'nil'
 if isinstance(v,dict):return '{'+','.join('['+lua(k)+']='+lua(x) for k,x in sorted(v.items(),key=lambda kv:str(kv[0])))+'}'
 if isinstance(v,list):return '{'+','.join(map(lua,v))+'}'
 return str(v)
scales={k:dict(v.items()) for k,v in l.globals().captured.items()}
original=(pawn/'Pawn.lua').read_text(encoding='utf-8-sig');start=original.index('function PawnGetItemValue(');end=original.index('-- Returns a friendly description of the best gems',start)
engine=original[start:end].replace('function PawnGetItemValue(','local function Score(',1)
head='''-- PRIVATE NONCOMMERCIAL RESEARCH ADAPTATION. Pawn @VERSION@, Travis Spomer / VgerMods.
-- Original CC BY-NC-ND 3.0 notice and README retained in this directory.
-- Scoring function retained; local scope isolates it from installed Pawn.
-- This adapter deliberately excludes sockets/reforging: not applicable to this
-- Forever base-item reference scorer. No claims of complete Pawn UI/parser parity.
local _,S=...
local E={};S.PrivatePawn=E
local PawnCommon={Scales={active={}}}
local PawnIgnoreStatValue=-1000000
local PawnScaleBestGems={}
local PawnScaleTotals={}
local VgerCore={IsBattleOrLater=false,ReforgingExists=false,Assert=assert}
'''
footer='''
local socketKeys={'PrismaticSocket','RedSocket','YellowSocket','BlueSocket','MetaSocket','CogwheelSocket','ShaTouchedSocket'}
function E.Score(stats,weights)
 if not stats or not weights then return end
 for _,key in ipairs(socketKeys) do if (stats[key] or 0)>0 then return nil,'Unsupported sockets' end end
 PawnCommon.Scales.active.Values=weights
 return Score(stats,0,nil,'active',false,true,true)
end
E.Version='@VERSION@'
E.Scales='''+lua(scales)+'\n'
private=ROOT/'addons/SmyrnaSuite/PrivateScoring';(private/'PawnScore.lua').write_text(head.replace('@VERSION@',version)+engine+footer.replace('@VERSION@',version),encoding='utf-8');shutil.copy2(pawn/'Readme.md',private/'PAWN-README.md')
(private/'SOURCE.json').write_text(json.dumps({'version':version,'snapshot':state['active'],'function_sha256':hashlib.sha256(original[start:end].encode()).hexdigest(),'weights_sha256':hashlib.sha256((pawn/'ClassicHawsJon.lua').read_bytes()).hexdigest(),'purpose':'private research; NOT for public redistribution'},indent=2),encoding='utf-8')
dungeons=set('Ragefire Chasm|Wailing Caverns|Deadmines|The Deadmines|Shadowfang Keep|Blackfathom Deeps|The Stockade|Stockade|Gnomeregan|Razorfen Kraul|Scarlet Monastery|Razorfen Downs|Uldaman|Zul\'Farrak|Maraudon|The Temple of Atal\'Hakkar|Sunken Temple|Blackrock Depths|Lower Blackrock Spire|Upper Blackrock Spire|Blackrock Spire|Dire Maul|Scholomance|Stratholme'.split('|'))
raids=set('Molten Core|Blackwing Lair|Onyxia\'s Lair|Zul\'Gurub|Ruins of Ahn\'Qiraj|Ahn\'Qiraj|Temple of Ahn\'Qiraj|Naxxramas'.split('|'))
gear={int(i['id']):i for i in items if i.get('inventory_type',0) in [1,2,3,5,6,7,8,9,10,11,12,13,14,15,16,17,20,21,22,23,25,26,28] and i.get('item_class') in ['Armor','Weapon']}
quests={q['id']:q for q in json.loads((cache/'quests.json').read_text())}
byitem={}
for s in sources:
 if s['item_id'] not in gear:continue
 zone=s.get('zone','');kind=s['kind'];category=None
 if kind=='container' and not s.get('min_level') and not gear[s['item_id']].get('required_level'):continue
 if zone in raids:continue
 if kind=='crafted':category='Crafted'
 elif kind in ['drop','object','container'] and any(zone==z or zone.startswith(z+' (') for z in dungeons):category='Dungeon'
 elif kind in ['drop','object','container']:category='World'
 if kind=='quest':category='Quest'
 if category:byitem.setdefault(s['item_id'],[]).append((category,s.get('name',''),zone,s.get('max_level',s.get('min_level',0)) if category!='Crafted' else 0,s.get('chance',0) or 0,s.get('source_id',0),s.get('min_level',0) if category=='Crafted' else 0,quests.get(s.get('source_id'),{}).get('faction','') if category=='Quest' else '',quests.get(s.get('source_id'),{}).get('classes','') if category=='Quest' else '',quests.get(s.get('source_id'),{}).get('repeatable',0) if category=='Quest' else 0))
 if category=='Quest':
  q=quests.get(s.get('source_id'),{});r=byitem[s['item_id']][-1];byitem[s['item_id']][-1]=r[:3]+(q.get('required_level',s.get('min_level',0)),)+r[4:]
statmap={'strength':'Strength','agility':'Agility','stamina':'Stamina','intellect':'Intellect','spirit':'Spirit','armor':'Armor','bonus_armor':'Armor','attack_power':'Ap','ranged_attack_power':'Rap','spell_power':'SpellPower','spell_damage':'SpellDamage','healing':'Healing','mp5':'Mp5','crit':'CritRating','hit':'HitRating','haste':'HasteRating','dodge':'DodgeRating','parry':'ParryRating','block':'BlockRating','block_value':'BlockValue','defense':'DefenseRating','fire_res':'FireResist','frost_res':'FrostResist','nature_res':'NatureResist','shadow_res':'ShadowResist','arcane_res':'ArcaneResist'}
slots={};records={}
for id,i in sorted(gear.items()):
 stats={}
 for key,target in statmap.items():
  if i.get(key):stats[target]=stats.get(target,0)+i[key]
 if i.get('dps'):
  stats['Dps']=i['dps'];stats['RangedDps' if i['inventory_type'] in [15,25,26] else 'MeleeDps']=i['dps']
  stats['TwoHandDps' if i['inventory_type']==17 else 'OneHandDps']=i['dps']
 if i.get('speed'):stats['Speed']=i['speed'];stats['RangedSpeed' if i['inventory_type'] in [15,25,26] else 'MeleeSpeed']=i['speed']
 inv=i['inventory_type'];effects=i.get('effects','')
 for pattern,key in [(r'Equip: \+(\d+) Attack Power','Ap'),(r'Equip: \+(\d+) Ranged Attack Power','Rap')]:
  m=re.search(pattern,effects)
  if m and key not in stats:stats[key]=int(m[1])
 if i.get('min_damage'):stats['MinDamage']=i['min_damage'];stats['MeleeMinDamage' if inv not in [15,25,26] else 'RangedMinDamage']=i['min_damage']
 if i.get('max_damage'):stats['MaxDamage']=i['max_damage'];stats['MeleeMaxDamage' if inv not in [15,25,26] else 'RangedMaxDamage']=i['max_damage']
 inv=i['inventory_type'];slots.setdefault(inv,[]).append(id)
 # Tab-delimited one owner: level,inv,class-mask,quality,name,class,subclass,estimated,unique,bind,stats,sources.
 fields=[i.get('required_level',0),inv,i.get('class_mask',-1),i.get('quality',1),i['name'],i['item_class'],i.get('subclass',''),i.get('estimated',0),i.get('is_unique',0),i.get('bonding',''),','.join(k+':'+str(v) for k,v in sorted(stats.items())), ';'.join('|'.join(str(x).replace('|',' ').replace(';',' ') for x in s) for s in sorted(set(byitem.get(id,[]))))]
 records[id]='\t'.join(str(x).replace('\t',' ').replace('\n',' ') for x in fields)
text='''-- Shared equipment facts. See NOTICE.md and MANIFEST.json for origin/limitations.
local S=SmyrnaSuite;if not S then return end
local G=S.Equipment
G.records='''+lua(records)+'\nG.slots='+lua(slots)+'\nG.proficiency='+lua(json.loads((cache/'proficiency.json').read_text()))+'\nG.build='+lua(meta['client_build'])+'\nG.count='+str(len(records))+'\n'
dest=ROOT/'addons/SmyrnaEquipmentDB';(dest/'Data.lua').write_text(text,encoding='utf-8')
(dest/'SmyrnaEquipmentDB.toc').write_text('''## Interface: 16000, 16001
## Title: Smyrna Equipment DB
## Group: SmyrnaSuite
## Category: Smyrna
## Notes: Shared armor, weapon, jewelry, trinket and equipment acquisition references.
## Version: 0.9.34
## Dependencies: SmyrnaSuite
## LoadOnDemand: 1
Data.lua
''',encoding='utf-8')
(dest/'NOTICE.md').write_text('''# Equipment reference sources

Facts repacked from https://gblaku.github.io/wow-forever-kb/api/ (source https://github.com/gBlaku/wow-forever-kb).
Forever client item facts: Blizzard Entertainment, exported through wago.tools. Client build and input hashes in MANIFEST.json. Estimated item records use Classic VMaNGOS values, not verified Forever stats.
Creature/container loot: VMaNGOS Classic world database, GPLv2. These are Classic references, not Forever observations. Quest/vendor/crafting relations: QuestieDB/Forever, subject to its file-level licences and historical contributor caveat. See bundled QuestieDB licence/provenance.
No website implementation code was copied. No drop probability was invented. Hidden/junk entries are excluded by the upstream export. Coverage is incomplete and source availability/lockouts are not fully verified. World-drop labels do not prove BoE; bind type is kept separately. Required item level does not prove dungeon access.
''',encoding='utf-8')
notice=dest/'Notices';notice.mkdir(exist_ok=True)
for name in ['QUESTIEDB-LICENSE.md','QUESTIEDB-PROVENANCE.md']:
 shutil.copy2(ROOT/'addons/SmyrnaBestiaryDB/Notices/SmyrnaBestiary'/name,notice/name)
import urllib.request
(notice/'VMANGOS-GPL-2.0.txt').write_bytes(urllib.request.urlopen('https://raw.githubusercontent.com/vmangos/core/development/LICENSE').read())
from pool_equipment import pool
pool(dest/'Data.lua',LuaRuntime)
manifest={'source':meta,'files':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in cache.glob('*.json')},'equipment':len(records),'with_sources':len(byitem),'source_rows':sum(map(len,byitem.values())),'lua_bytes':(dest/'Data.lua').stat().st_size,'dungeon_names':sorted(dungeons),'raid_names_excluded':sorted(raids)}
(dest/'MANIFEST.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8');print(json.dumps({k:manifest[k] for k in ['equipment','with_sources','source_rows','lua_bytes']}))
