"""Merge missing Forever gear from a pinned WoWSims JSON snapshot; never overwrite existing facts."""
from pathlib import Path
import json,sys,os,math,hashlib
STATS={0:'Strength',1:'Agility',2:'Stamina',3:'Intellect',4:'Healing',5:'SpellDamage',6:'ArcaneSpellDamage',7:'FireSpellDamage',8:'FrostSpellDamage',9:'HolySpellDamage',10:'NatureSpellDamage',11:'ShadowSpellDamage',12:'SpellPenetration',13:'Spirit',14:'Ap',15:'Rap',16:'FeralAp',17:'HitRating',18:'CritRating',19:'HasteRating',20:'ArmorPenetration',21:'ExpertiseRating',22:'DefenseRating',23:'BlockRating',24:'BlockValue',25:'DodgeRating',26:'ParryRating',27:'Armor',28:'Armor',29:'Health',30:'Mana',31:'Mp5',32:'ArcaneResist',33:'FireResist',34:'FrostResist',35:'NatureResist',36:'ShadowResist',38:'Armor'}
SLOTS={1:1,2:2,3:3,4:16,5:5,6:9,7:10,8:6,9:7,10:8,11:11,12:12}
ARMOR={1:'Cloth',2:'Leather',3:'Mail',4:'Plate'}
PROF={1:'Alchemy',2:'Blacksmithing',3:'Enchanting',4:'Engineering',5:'Herbalism',8:'Leatherworking',9:'Mining',10:'Skinning',11:'Tailoring'}
FACTION={1:'Alliance',2:'Horde'}
def lua(v):
 if isinstance(v,str):return json.dumps(v,ensure_ascii=False)
 if isinstance(v,bool):return 'true' if v else 'false'
 if isinstance(v,(int,float)):return str(v)
 if isinstance(v,dict):return '{'+','.join('['+lua(k)+']='+lua(x) for k,x in sorted(v.items()))+'}'
 return '{'+','.join(map(lua,v))+'}'
def shape(i):
 t=i.get('type');w=i.get('weaponType');r=i.get('rangedWeaponType');hand=i.get('handType')
 if t in SLOTS:return SLOTS[t],'Armor',ARMOR.get(i.get('armorType'),'Miscellaneous')
 if t==13:
  if w==7:return 14,'Armor','Shield'
  if w==5:return 23,'Armor','Miscellaneous'
  name={1:'Axe',2:'Dagger',3:'Fist Weapon',4:'Mace',6:'Polearm',8:'Staff',9:'Sword'}.get(w)
  if not name or hand not in [1,2,3,4]:return
  if w in [1,4,9]:name=('Two-Handed ' if hand==4 else 'One-Handed ')+name
  return {1:21,2:13,3:22,4:17}[hand],'Weapon',name
 if t==14:
  if r in [6,7,8]:return 28,'Armor',{6:'Idol',7:'Libram',8:'Totem'}[r]
  if r in [1,2,3,4,5]:return {1:15,2:15,3:15,4:25,5:26}[r],'Weapon',{1:'Bow',2:'Crossbow',3:'Gun',4:'Thrown',5:'Wand'}[r]
def supplement(root,cache,LuaRuntime):
 files=['assets_database_db.json','assets_database_leftover_db.json','proto_common.proto','proto_ui.proto','LICENSE']
 for f in files:assert (cache/f).is_file(),f
 inputs=[json.loads((cache/f).read_text()) for f in files[:2]]
 assert len(inputs[0]['items'])>7000 and len(inputs[1]['items'])>3000,'Incomplete WoWSims snapshot'
 l=LuaRuntime(unpack_returned_tuples=True);l.execute('SmyrnaSuite={Equipment={}}')
 path=root/'addons/SmyrnaEquipmentDB/Data.lua';l.execute(path.read_text(encoding='utf-8-sig'));g=l.globals().SmyrnaSuite.Equipment
 records=dict(g.records.items());pool=[v for _,v in sorted(g.sourcePool.items())];poolids={s:n+1 for n,s in enumerate(pool)}
 zones={z['id']:z['name'] for db in inputs for z in db.get('zones',[])}
 npcs={n['id']:n['name'] for db in inputs for n in db.get('npcs',[])}
 raids=set(json.loads((root/'addons/SmyrnaEquipmentDB/MANIFEST.json').read_text()).get('raid_names_excluded',[]))
 previous_path=root/'addons/SmyrnaEquipmentDB/SUPPLEMENT.json'
 previous=json.loads(previous_path.read_text()) if previous_path.exists() else {}
 additions=list(previous.get('added_ids',[]));updated=list(previous.get('updated_estimated_ids',[]));skipped=[]
 for db in inputs:
  for i in db['items']:
   id=i['id']
   old=records.get(id);old_fields=old.split('\t') if old else None
   if old_fields and old_fields[7]!='1':continue
   sh=shape(i);base=i.get('scalingOptions',{}).get('0')
   if not sh or base is None:skipped.append(id);continue
   inv,kind,subclass=sh;stats={}
   for key,v in base.get('stats',{}).items():
    target=STATS.get(int(key))
    if target and isinstance(v,(int,float)) and math.isfinite(v):stats[target]=stats.get(target,0)+v
   speed=i.get('weaponSpeed',0);dps=base.get('unroundedDps')
   if kind=='Weapon' and speed>0 and dps is not None:
    ranged=inv in [15,25,26];stats.update({'Dps':dps,'Speed':speed,('RangedDps' if ranged else 'MeleeDps'):dps,('RangedSpeed' if ranged else 'MeleeSpeed'):speed})
    if not ranged:stats['TwoHandDps' if inv==17 else 'OneHandDps']=dps
    for k,label in [('weaponDamageMin','MinDamage'),('weaponDamageMax','MaxDamage')]:
     if k in base:stats[label]=base[k];stats[('Ranged' if ranged else 'Melee')+label]=base[k]
   allow=i.get('classAllowlist',[]);mask=sum(2**(c-1) for c in allow) if allow else -1
   req=i.get('reqLvl',0);source_rows=[]
   for src in i.get('sources',[]):
    category=name=zone='';sourceid=0;faction='';level=req or max(0,base.get('ilvl',5)-5)
    if 'drop' in src:
     d=src['drop'];sourceid=d.get('npcId',0);name=npcs.get(sourceid,d.get('otherName','Unresolved drop source'));zone=zones.get(d.get('zoneId'), '')
     category='Dungeon' if d.get('difficulty',0)>0 else 'World'
     if zone in raids:continue # the current source selector is Dungeon, not Raid
     if sourceid==246008:category='Dungeon';zone='City of Dalaran' # verified separately; zoneId is the parent outdoor region
    elif 'quest' in src:
     d=src['quest'];category='Quest';sourceid=d['id'];name=d['name'];faction=FACTION.get(d.get('faction'),'')
    elif 'crafted' in src:
     d=src['crafted'];category='Crafted';sourceid=d.get('spellId',0);name=PROF.get(d.get('profession'),'Crafting')+' recipe #'+str(sourceid);level=0
    elif 'soldBy' in src:
     d=src['soldBy'];category='Vendor';sourceid=d.get('npcId',0);name=d.get('npcName','Vendor');zone=zones.get(d.get('zoneId'),'');faction=FACTION.get(d.get('faction'),'')
    if category:
     fields=[category,name,zone,level,'',sourceid,0,faction,'',0,'WoWSims reference']
     text='|'.join(str(x).replace('|',' ').replace(';',' ').replace('\t',' ') for x in fields)
     if text not in poolids:pool.append(text);poolids[text]=len(pool)
     source_rows.append(poolids[text])
   # Binding is absent from this schema. Never infer BoE from a drop/craft source.
   bind=old_fields[9] if old_fields else ('Binds when picked up' if id==273042 else '')
   if old_fields:
    source_rows=list(dict.fromkeys([int(n) for n in old_fields[11].split(',') if n]+source_rows))
   fields=[req,inv,mask,i.get('quality',1),i['name'],kind,subclass,0,int(i.get('unique',False)),bind,','.join(k+':'+str(v) for k,v in sorted(stats.items())),','.join(map(str,dict.fromkeys(source_rows))),'WoWSims Forever',FACTION.get(i.get('factionRestriction'),''),PROF.get(i.get('requiredProfession'),''),int(i.get('phase',0)!=1)]
   records[id]='\t'.join(str(x).replace('\t',' ').replace('\n',' ') for x in fields)
   if old_fields:updated.append(id)
   else:additions.append(id)
 assert 273042 in records,'Manascale Treads must be covered'
 slots={}
 for id,raw in sorted(records.items()):slots.setdefault(int(raw.split('\t')[1]),[]).append(id)
 text=path.read_text(encoding='utf-8-sig');a=text.index('G.sourcePool=');b=text.index('\nG.proficiency=',a)
 text=text[:a]+'G.sourcePool='+lua(pool)+'\nG.records='+lua(records)+'\nG.slots='+lua(slots)+text[b:]
 import re
 text=re.sub(r'G.count=\d+', 'G.count='+str(len(records)),text)
 path.write_text(text,encoding='utf-8')
 snapshot=json.loads((cache/'wowsims-tree.json').read_text());commit=snapshot.get('commit',snapshot['sha'])
 additions=sorted(set(additions));updated=sorted(set(updated))
 manifest={'provider':'WoWSims Forever','repository':'https://github.com/wowsims/forever','commit':commit,'license':'MIT','input_sha256':{f:hashlib.sha256((cache/f).read_bytes()).hexdigest() for f in files},'added_ids':additions,'updated_estimated_ids':updated,'unmapped_ids':skipped,'total_equipment':len(records),'lua_bytes':path.stat().st_size,'limitations':'Base scaling option only; no inferred binding; procs/sets/conditional stats not fully scored. Unknown phases/profession requirements excluded from recommendations. Verified existing records preserved; Classic-estimated records may be upgraded from WoWSims; old sources retained.'}
 dest=root/'addons/SmyrnaEquipmentDB';(dest/'SUPPLEMENT.json').write_text(json.dumps(manifest,indent=2));(dest/'Notices/WOWSIMS-MIT.txt').write_bytes((cache/'LICENSE').read_bytes())
 print(json.dumps({k:manifest[k] for k in ['total_equipment','lua_bytes']},indent=2));print('Added',len(additions),'items; updated',len(updated),'Classic estimates; skipped',len(skipped))
 return manifest
if __name__=='__main__':
 root=Path(__file__).resolve().parents[1];sys.path.insert(0,str(root/'tests'))
 from lua_harness import LuaRuntime
 supplement(root,root/'.local/equipment-supplement',LuaRuntime)
