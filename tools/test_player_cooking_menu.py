#!/usr/bin/env python3
"""Focused production owner receiver compared with the retained Java furnace menu."""
from pathlib import Path
import argparse,copy,hashlib,json,shutil
import test_campfire_authority as B
import test_cooking_world as Context
ROOT=Path(__file__).resolve().parents[1]
WORK=ROOT/'build/player-cooking-menu-native/001'
TABLE=ROOT/'generated/reference_item_metadata.tsv'
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def wire(slot):return '_' if slot is None else slot['id']+'~'+str(slot['count'])
def plain(slot):return None if slot is None else dict(id=slot.get('id',slot.get('item')),count=slot['count'],components='')
def java_slot(slot):return None if slot['empty'] else dict(id=slot['visible_item'],count=slot['visible_count'],components='')
def player_slots(case):
 slots=[None]*64
 for key,value in case['main'].items():slots[int(key)]=plain(value)
 slots[40]=dict(id='minecraft:shield',count=1,components='');slots[41]=dict(id='minecraft:wolf_armor',count=1,components='');slots[42]=dict(id='minecraft:saddle',count=1,components='')
 slots[47]=plain(case['carried'])
 for index in range(48,64):slots[index]=dict(id='fixture:hidden-player-'+str(index),count=index,components='')
 return slots

def fixtures():
 ref=json.loads((ROOT/'reference/player_cooking_menu.json').read_text());rows=[]
 for case,obs in zip(ref['inputs'],ref['observations'],strict=True):
  rows.append(dict(case=copy.deepcopy(case),gate='',before=player_slots(case),after=obs['after'],java=True))
 base=copy.deepcopy(ref['inputs'][0])
 for gate in ('observer','zero','peer','permission','dimension','range','incarnation','menu','budget'):
  c=copy.deepcopy(base);c['id']='refusal-'+gate
  rows.append(dict(case=c,gate=gate,before=player_slots(c),after=None,java=False))
 camp=json.loads((ROOT/'reference/campfire_authority.json').read_text())
 retained={c['id']:c for c in camp['observations']['cases']}
 for offhand,creative,gate in ((False,False,''),(True,False,''),(False,True,''),(True,True,''),(False,False,'budget'),(False,False,'full'),(False,False,'permission'),(False,False,'empty')):
  c=dict(id='campfire-'+str(int(offhand))+'-'+str(int(creative))+'-'+(gate or 'place'),mode='CREATIVE' if creative else 'SURVIVAL',action='USE_OFFHAND' if offhand else 'USE_MAIN',index=0,button=0,furnace=[None,None,None],main={},carried=None)
  before=player_slots(c);before[0]=dict(id='minecraft:dirt',count=13,components='')
  before[7]=dict(id='minecraft:potato',count=5,components='');before[40]=dict(id='minecraft:potato',count=5,components='')
  if gate=='empty':before[40 if offhand else 7]=None
  obs=retained['vanilla_four_False']['observations'][0]
  rows.append(dict(case=c,gate=gate,before=before,after=None,java=False,campfire=True,java_placement=obs,java_case='vanilla_four_False',creative_boundary='Pinned ItemStack.consumeAndReturn and Entity.hasInfiniteMaterials bytecode; retained CA placeFood receiver used null entity, so creative hand retention is a separate production guard'))
 template=copy.deepcopy(next(r for r in rows if r.get('campfire') and not r['gate'] and r['case']['action']=='USE_MAIN' and r['case']['mode']=='SURVIVAL'))
 for name,main,offhand,accepted,index,gate in (
  ('main-pass-offhand',dict(id='minecraft:dirt',count=13,components=''),dict(id='minecraft:potato',count=5,components=''),True,40,''),
  ('empty-main-offhand',None,dict(id='minecraft:potato',count=5,components=''),True,40,''),
  ('main-priority',dict(id='minecraft:potato',count=5,components=''),None,True,7,''),
  ('both-pass',dict(id='minecraft:dirt',count=13,components=''),dict(id='minecraft:dirt',count=17,components=''),False,40,'pass'),
  ('invalid-main-no-fallback',dict(id='minecraft:potato',count=65,components=''),dict(id='minecraft:potato',count=5,components=''),False,7,'invalid'),
  ('full-main-no-fallback',dict(id='minecraft:potato',count=5,components=''),dict(id='minecraft:potato',count=5,components=''),False,7,'full')):
  r=copy.deepcopy(template);r['case']['id']='campfire-hands-'+name;r['case']['action']='USE_HANDS'
  r['before'][7]=main;r['before'][40]=offhand;r['gate']=gate;r['placement']=accepted;r['held_index']=index
  rows.append(r)
 for gate in ('budget','return-full'):
  c=copy.deepcopy(base);c['id']='open-retains-prior-'+gate;c['action']='OPEN'
  before=player_slots(c)
  if gate=='return-full':
   before[:36]=[dict(id='minecraft:dirt',count=64,components='') for _ in range(36)]
   before[47]=dict(id='minecraft:stone',count=17,components='')
  rows.append(dict(case=c,gate=gate,before=before,after=None,java=False,open_refusal=True))
 return rows

def argument(row):
 c=row['case'];mode=c['mode'];fields=[c['id'],c['action'],str(c['index']),str(c['button']),str(int(mode=='CREATIVE')),str(int(mode!='ADVENTURE')),row['gate']]
 fields += [wire(plain(s)) for s in c['furnace']]
 fields += [wire(s) for s in row['before']]
 return '|'.join(fields)
def prepare():
 WORK.mkdir(parents=True,exist_ok=True)
 Context.WORK=WORK/'context';Context.prepare()
 rows=fixtures();(WORK/'cases.json').write_text(json.dumps(rows,indent=2)+'\n')
 return rows

def brief(result):return {k:v for k,v in result.items() if k not in ('before_core','after_core')}
def compare(rows):
 source=WORK/'comparison.stdout' if (WORK/'comparison.stdout').exists() else WORK/'native.stdout'
 got=[json.loads(line) for line in source.read_text().splitlines() if line.startswith('{')]
 assert len(got)==len(rows),(len(got),len(rows))
 for row,result in zip(rows,got,strict=True):
  c=row['case'];assert result['id']==c['id'];assert result['before_core']==result['after_core'],'actual full Core changed'
  p=result['player'];expected=copy.deepcopy(row['before'])
  if row.get('open_refusal'):assert result['menu']==dict(id=5,furnace_available=False),result['menu']
  old_furnace=[plain(x) for x in c['furnace']]
  if row.get('campfire'):
   accepted=row.get('placement',not row['gate']);assert result['accepted']==accepted,brief(result)
   if row['gate']=='pass':assert result['message']=='cooking-menu:campfire-hand-pass',brief(result)
   if row['gate'] in ('invalid','full','permission','budget'):assert result['message']!='cooking-menu:campfire-hand-pass',brief(result)
   held_index=row.get('held_index',40 if c['action']=='USE_OFFHAND' else 7)
   if accepted and c['mode']!='CREATIVE':expected[held_index]['count']=row['java_placement']['held']['count']
   assert p['backing']==expected,dict(id=c['id'],actual=p['backing'],expected=expected)
   assert p['revision']==19+int(accepted and c['mode']!='CREATIVE') and not p['opened'] and p['selected']==7 and p['logical_length']==48 and p['catalog_count']==1658,c['id']
   assert p['abilities']==dict(instabuild=c['mode']=='CREATIVE',maybuild=True,invulnerable=True,mayfly=True,flying=False,walking_speed=2147483648,flying_speed=2143289345),c['id']
   assert len(result['entries'])==1
   e=result['entries'][0];assert e['block']=='minecraft:campfire' and e['lit']
   if row['gate']=='full':
    assert e['cache']=='minecraft:baked_potato_from_campfire_cooking'
    expected_cells=[dict(slot=dict(id='minecraft:potato',count=1,components=''),patch={},progress=19,total=600)]*4
   else:
    assert e['cache'] is None
    expected_cells=[dict(slot=None,patch={},progress=0,total=0) for _ in range(4)]
    if accepted:
     java=row['java_placement']['state'];expected_cells[0]['slot']=dict(id=java['items'][0]['id'],count=java['items'][0]['count'],components='')
     expected_cells[0]['total']=java['total'][0]
   assert e['cells']==expected_cells,dict(id=c['id'],actual=e['cells'],expected=expected_cells)
   assert bool(result['dirty'])==accepted,c['id']
   continue
  if row['java']:
   a=row['after'];expected[:36]=[plain(x) for x in a['player']['inventory']['main_slots']]
   expected[47]=java_slot(a['carried']);furnace=[java_slot(s) for s in a['furnace']]
   assert result['accepted'],brief(result)
  else:
   furnace=old_furnace;assert not result['accepted'],brief(result)
  assert p['backing']==expected,{'id':c['id'],'actual':p['backing'],'expected':expected}
  assert len(result['entries'])==1
  e=result['entries'][0];assert e['backing']==furnace+[dict(id='fixture:hidden-furnace',count=31,components='')],c['id']
  changed=expected!=row['before'] or furnace!=old_furnace
  assert p['revision']==19+int(changed) and p['opened'] and p['selected']==7 and p['logical_length']==48 and p['catalog_count']==1658,c['id']
  assert p['abilities']==dict(instabuild=c['mode']=='CREATIVE',maybuild=c['mode']!='ADVENTURE',invulnerable=True,mayfly=True,flying=False,walking_speed=2147483648,flying_speed=2143289345),c['id']
  frame=e['frame'];assert frame['uses']=={'minecraft:stone':7} and frame['cached']=='minecraft:stone' and frame['speed_bits']==1065353216,c['id']
  # GUI input replacement resets the actual furnace timer through FS.put_snapshot;
  # other slots retain the actual frame. These fields are beyond SimpleContainer's Java fixture.
  input_changed=furnace[0]!=old_furnace[0]
  assert frame['litTimeRemaining']==71 and frame['litTotalTime']==1600
  assert frame['cookingTimer']==(0 if input_changed and (furnace[0] is None or old_furnace[0] is None or furnace[0]['id']!=old_furnace[0]['id']) else 83),c['id']
 return got

def screen_compare():
 got={r['id']:r for r in (json.loads(line) for line in (WORK/'screen.stdout').read_text().splitlines() if line.startswith('{'))}
 expected={'left-pickup':['pickup: 0:0'],'right-pickup':['pickup: 0:1'],'shift-quick':['quick: 0'],
  'pending-suppresses':[],'hold-suppresses':[],'same-open-shift-kept':[],'second-held-shift':['quick: 0'],
  'focus-loss':['release','capture:0'],'close':['close'],'close-refused':[],'closed-capture':['capture:1'],'resize-invalidates-hover':[],
  'os-close':['close'],'os-close-ack':['quit'],'os-close-refused':[],'os-close-pending':[],
  'os-close-followup':['close'],'os-close-followup-ack':['quit'],
  'os-close-unfocused':['release','capture:0','close'],'closed-mouse-world':[],'closed-close-world':[],'too-small-suppresses':[],
  'progress-third':[],'progress-negative':[],'progress-both-negative':[],'progress-minimum':[],
  'progress-zero-duration':[],'progress-lit-fallback':[]}
 assert set(got)==set(expected)
 for name,intents in expected.items():assert got[name]['intents']==intents,got[name]
 assert got['same-open-shift-kept']['shift']==3 and not got['same-open-shift-kept']['pending']
 assert got['focus-loss']['shift']==0 and got['focus-loss']['buttons']==0 and got['focus-loss']['pending'] and not got['focus-loss']['focused']
 assert got['close-refused']['open'] and not got['closed-capture']['open']
 assert got['os-close']['pending'] and got['os-close']['quit']==2
 assert got['os-close-pending']['pending'] and got['os-close-pending']['quit']==1
 assert got['os-close-followup']['pending'] and got['os-close-followup']['quit']==2
 assert got['os-close-refused']['open'] and got['os-close-refused']['quit']==0
 assert not got['os-close-ack']['open'] and not got['os-close-followup-ack']['open']
 for name,value in {'progress-third':8,'progress-negative':0,'progress-both-negative':12,'progress-minimum':24,'progress-zero-duration':0,'progress-lit-fallback':3}.items():assert got[name]['progress']==value,got[name]
 assert not got['closed-mouse-world']['consumed'] and not got['closed-close-world']['consumed']
 return got

def run(phase,repair_case=None):
 rows=prepare();B.WORK=WORK;checks=[]
 pins={str(p.relative_to(ROOT)):sha(p) for pat in ('src/player_cooking_menu*.bend','tests/player_cooking_menu*.bend') for p in ROOT.glob(pat)}
 pins.update({p:sha(ROOT/p) for p in ('src/cooking_world_slots.bend','reference/player_cooking_menu.json','reference/campfire_authority.json','generated/reference_item_metadata.tsv','tools/test_player_cooking_menu.py','tools/player_cooking_menu_emit.mjs')})
 if phase=='prepare':print(json.dumps(dict(status='prepared',java_cases=26,refusal_cases=9,open_refusal_cases=2,campfire_hand_cases=sum(bool(r.get('campfire')) for r in rows))));return
 if phase in ('ordinary','all'):checks.append(B.run('ordinary',[B.BEND,'tests/player_cooking_menu.bend','--check-only'],60,8*1024**3))
 if phase=='ordinary':return
 if phase in ('build','all'):
  checks.append(B.run('emit',['/usr/bin/env','BEND_PRODUCER_LOG='+str(WORK/'emit-functions.jsonl'),'BEND_PRODUCER_GC=1',B.NODE,'--expose-gc','--max-old-space-size=8192','--stack-size=4096','--experimental-transform-types','tools/player_cooking_menu_emit.mjs','tests/player_cooking_menu.bend',WORK/'receiver.c'],600,8*1024**3))
  checks.append(B.run('clang',[shutil.which('clang') or '/usr/bin/clang','-std=c11','-O1',WORK/'receiver.c','-lpthread','-lm','-o',WORK/'receiver'],300,3*1024**3))
 if phase=='build':return
 if phase=='native':checks=[json.loads((WORK/(name+'.json')).read_text()) for name in ('ordinary','emit','clang') if (WORK/(name+'.json')).exists()]
 compiled=json.loads((WORK/'receiver.c.sources.json').read_text())
 assert all(sha(path)==value for path,value in compiled['source_sha256'].items()),'compiled source changed before native comparison'
 if repair_case:
  selected=[r for r in rows if r['case']['id']==repair_case];assert len(selected)==1
  repaired=B.run('native-repair-case',[WORK/'receiver','--gpu','off','--threads','1',TABLE,WORK/'context/input.json',argument(selected[0])],120,1024**3)
  original=[line for line in (WORK/'native.stdout').read_text().splitlines() if line.startswith('{')]
  replacement=[line for line in (WORK/'native-repair-case.stdout').read_text().splitlines() if line.startswith('{')];assert len(replacement)==1
  assert json.loads(replacement[0])['id']==repair_case
  combined=[replacement[0] if json.loads(line)['id']==repair_case else line for line in original]
  assert len(combined)==len(rows)
  (WORK/'comparison.stdout').write_text('\n'.join(combined)+'\n')
  native=json.loads((WORK/'native.json').read_text());native['corrected_input_process']=repaired;native['corrected_input_case']=repair_case
 else:
  native=B.run('native',[WORK/'receiver','--gpu','off','--threads','1',TABLE,WORK/'context/input.json',*[argument(r) for r in rows]],120,1024**3)
 got=compare(rows)
 screen=B.run('screen',[WORK/'receiver','--gpu','off','--threads','1','--screen'],60,1024**3)
 screen_rows=screen_compare()
 assert all(sha(ROOT/p)==h for p,h in pins.items()),'source changed during focused run'
 evidence=dict(status='passed',java_cases=26,whole_owner_refusals=9,open_refusal_cases=2,campfire_hand_cases=sum(bool(r.get('campfire')) for r in rows),checks=checks,native=native,screen=screen,screen_cases=len(screen_rows),source_sha256=pins,compiled_source_manifest_sha256=sha(WORK/'receiver.c.sources.json'),compiled_source_count=len(compiled['source_sha256']),producer_basis=compiled['producer_basis'],binary_sha256=sha(WORK/'receiver'),emitted_c_sha256=sha(WORK/'receiver.c'),raw_native_sha256=sha(WORK/'native.stdout'),comparison_sha256=sha(WORK/'comparison.stdout' if repair_case else WORK/'native.stdout'),corrected_input_case=repair_case,boundary='Actual production Menu.dispatch, same Store/Core, three logical/four furnace backing cells,48 logical/64 player backing cells, whole player profile and full encoded Core. Java SimpleContainer comparison covers pickup/quick-move counts and routing. Furnace timers/RecipesUsed retention are explicit additional production guards. No network/UI/ServerPlayer XP or RNG/entity consumer inferred.')
 (ROOT/'evidence/player-cooking-menu-native.json').write_text(json.dumps(evidence,indent=2)+'\n');print(json.dumps(dict(status='passed',java_cases=26,refusals=9,open_refusal_cases=2,campfire_hand_cases=sum(bool(r.get('campfire')) for r in rows),native_seconds=native['seconds'])))
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--generation',type=int,default=1);p.add_argument('--repair-case');p.add_argument('--phase',choices=('prepare','ordinary','build','native','all'),default='all');a=p.parse_args();
 global WORK
 assert 1<=a.generation<=999
 WORK=ROOT/'build/player-cooking-menu-native'/f'{a.generation:03d}'
 run(a.phase,a.repair_case)
if __name__=='__main__':main()
