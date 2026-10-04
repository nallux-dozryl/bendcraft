#!/usr/bin/env python3
"""Actual Bend crafting authority against independently recorded Java outcomes."""
from __future__ import annotations
import argparse,copy,hashlib,json,os,shutil,subprocess,time
from pathlib import Path
import reference_player_crafting_authority_probe as P
from reference_inventory import ROOT,canonical,fingerprint,write_json
CACHE=ROOT/'build/player-crafting-authority-tests'
BINARY=CACHE/'authority'

def q(s):return json.dumps(s,ensure_ascii=False)
def seq(values):return '['+','.join(values)+']'
def slot(s):
 if s is None:return 'Inv.InvEmpty{}'
 return 'Inv.InvStack{Inv.ItemKey{'+q(s.get('item',s.get('id')))+','+q(s.get('components',''))+'},'+str(s['count'])+'}'
def ingredient(s):
 if s is None:return 'R.Empty{}'
 if isinstance(s,list):values=s
 else:values=[s]
 return 'R.AnyOf{'+seq(('R.TagRef{'+q(v[1:])+'}' if v.startswith('#') else 'R.Item{'+q(v)+'}') for v in values)+'}'
def recipe(source,name,components=''):
 output=slot({'item':source['result']['id'],'count':source['result'].get('count',1),'components':components})
 if source['type'].endswith('shaped'):
  pattern=source['pattern'];cells=[ingredient(source['key'].get(c)) for row in pattern for c in row]
  return 'R.Shaped{'+q(name)+','+str(len(pattern[0]))+','+str(len(pattern))+','+seq(cells)+','+output+'}'
 return 'R.Shapeless{'+q(name)+','+seq(ingredient(v) for v in source['ingredients'])+','+output+'}'
def actual(s):
 if s is None or s.get('empty',False):return None
 return {'id':s.get('item',s.get('visible_item')),'components':'','count':s.get('count',s.get('visible_count'))}
def slots(s):return [actual(x) for x in s]
def profile(state):
 v=state['inventory']['abilities'];return {**{k:v[k] for k in ('instabuild','maybuild','invulnerable','mayfly','flying')},'walking_speed':int(v['walking_speed_f32_bits'],16),'flying_speed':int(v['flying_speed_f32_bits'],16)}
def prepare():
 data=json.loads(P.OUTPUT.read_text());catalog=json.loads((ROOT/'build/crafting-recipe-reference/catalog.json').read_text());items={r['id']:r for r in catalog['items']};tags={t['id']:t for t in catalog['tags']}
 types='''import Base
import ../src/inventory.bend as Inv
import ../src/player_inventory.bend as I
import ../src/crafting_recipe.bend as R

type Case is Data:
  Case{id:String,recipe:R.Catalog,grid:R.Grid,player:List<&2,Inv.Slot>,selected:U32,abilities:I.Abilities,status:I.Status,revision:Nat,opened:Bool,button:U32,operation:U32}
'''
 source=types;cases=[];expected=[];runtime=[];production=json.loads((ROOT/'build/crafting-recipe-components/production-catalog.json').read_text());full_items={r['id']:r for r in production['items']};full_tags={r['id']:r for r in production['tags']};tail=[{'item':'minecraft:stone','count':n+1} for n in range(16)];bench_tail=[{'item':'minecraft:dirt','count':n+1} for n in range(7)]
 def runtime_case(label,source_recipe,recipe_id,grid,player,ability,button=0,operation=0):
  names={source_recipe['result']['id']};tag_names=set()
  for v in list(source_recipe.get('key',{}).values())+source_recipe.get('ingredients',[]):
   for name in v if isinstance(v,list) else [v]:
    if name.startswith('#'):tag_names.add(name[1:]);names.update(full_tags[name[1:]]['items'])
    else:names.add(name)
  names.update((slot.get('id',slot.get('item')) for slot in grid['slots'] if slot))
  names.update(r['remainder']['id'] for r in full_items.values() if r['id'] in names and r['remainder'])
  normalize=lambda slot:None if slot is None else {'id':slot.get('id',slot.get('item')),'components':slot.get('components',''),'count':slot['count']}
  return {'id':label,'catalog':{'items':[full_items[name] for name in sorted(names)],'tags':[full_tags[name] for name in sorted(tag_names)],'recipes':[{'id':recipe_id,'source':source_recipe}]},'grid':{**grid,'slots':[normalize(s) for s in grid['slots']]},'player':[normalize(s) for s in player],'selected':7,'profile':ability,'revision':23,'opened':True,'button':button,'operation':operation}
 inputs={case['id']:case for case in P.inputs()}
 for n,row in enumerate(data['observations']):
  case=copy.deepcopy(inputs[row['id']]);assert P.compact_input(case)==row['input'];before=row['before'];after=row['after'];ability=profile(before)
  source_recipe=case['source'];key=f'fixture:case_{n}'
  names={source_recipe['result']['id']};tag_names=set()
  for v in list(source_recipe.get('key',{}).values())+source_recipe.get('ingredients',[]):
   for value in v if isinstance(v,list) else [v]:
    if value.startswith('#'):tag_names.add(value[1:])
    else:names.add(value)
  for s in case['craft']:
   if s:names.add(s['item'])
  names|={r['remainder']['id'] for id,r in items.items() if id in names and r['remainder']}
  item_values=['R.ItemDefinition{'+q(id)+','+str(items[id]['limit'])+','+slot(items[id]['remainder'])+'}' for id in sorted(names)]
  tag_values=['R.Tag{'+q(id)+','+seq(q(v) for v in tags[id]['items'])+'}' for id in sorted(tag_names)]
  source+='\ndef recipe_'+str(n)+'() -> R.Catalog:\n  R.Catalog{['+recipe(source_recipe,key)+'],'+seq(tag_values)+','+seq(item_values)+'}\n'
  logical=slots(before['inventory']['main_slots'])+slots(before['equipment'])+(slots(before['craft']) if case['width']==2 else [None]*4)+[actual(before['carried'])]
  native_before=logical+[{'id':s['item'],'components':'','count':s['count']} for s in tail]
  taken=actual(after['carried']);previous=actual(before['carried']);moved=(taken['count'] if taken else 0)-(previous['count'] if previous else 0)
  overflow='full:' in row['id'] and 'honey-' in row['id'] and case['craft'][0] and case['craft'][0]['count']>1
  accepted=bool(moved) and not overflow
  message='' if accepted else ('crafting remainder requires capacity or owned world-drop disposition' if overflow else 'crafting result is empty' if row['id']=='strict-empty-99' else 'carried stack cannot take the complete crafting result')
  wanted=after if accepted else before
  all_backing=slots(wanted['inventory']['main_slots'])+slots(wanted['equipment'])+(slots(wanted['craft']) if case['width']==2 else [None]*4)+[actual(wanted['carried'])]+[{'id':s['item'],'components':'','count':s['count']} for s in tail]
  result=actual(before['result']) if not accepted else None
  cache={'id':key,'width':case['width'],'height':case['height'],'slots':slots(before['craft']),'output':actual(before['result']),'consumption':[{'slot':i,'count':1,'remainder':({'id':r['id'],'components':'','count':r['count']} if (r:=items[s['item']]['remainder']) else None)} for i,s in enumerate(case['craft']) if s]}
  expected.append({'id':row['id'],'accepted':accepted,'message':message,'selected':7,'abilities':ability,'opened':True,'revision':23+int(accepted),'result':result,'logical_length':48,'catalog_count':1658,'all_backing_slots':all_backing,'grid':{'width':case['width'],'height':case['height'],'slots':slots(wanted['craft'])},'bench_backing_slots':None if case['width']==2 else slots(wanted['craft'])+[{'id':s['item'],'components':'','count':s['count']} for s in bench_tail],'bench_revision':None if case['width']==2 else 5+int(accepted),'cache':None if accepted else cache,'taken':{'id':taken['id'],'components':'','count':moved} if accepted else None})
  if n==0:
   retained=copy.deepcopy(expected[-1]);retained.update(cache=copy.deepcopy(cache),all_backing_slots=copy.deepcopy(native_before),grid={'width':2,'height':2,'slots':slots(before['craft'])},result=copy.deepcopy(cache['output']))
  ab='I.Abilities{'+','.join('True{}' if ability[k] else 'False{}' for k in ('instabuild','maybuild'))+'}'
  st='I.Status{'+','.join(['True{}' if ability[k] else 'False{}' for k in ('invulnerable','mayfly','flying')]+[str(ability[k]) for k in ('walking_speed','flying_speed')])+'}'
  cases.append('Case{'+q(row['id'])+',recipe_'+str(n)+'(),R.Grid{'+str(case['width'])+','+str(case['height'])+','+seq(slot(s) for s in case['craft'])+'},'+seq(slot(s) for s in native_before)+',7,'+ab+','+st+',23n,True{},'+str(case['button'])+',0}')
  runtime.append(runtime_case(row['id'],source_recipe,key,{'width':case['width'],'height':case['height'],'slots':case['craft']},native_before,ability,case['button']))
 base=copy.deepcopy(retained);base.update(accepted=False,message='',revision=23,taken=None)
 base['all_backing_slots'][43:47]=copy.deepcopy(base['cache']['slots']);base['all_backing_slots'][47]=None
 base['grid']['slots']=copy.deepcopy(base['cache']['slots']);base['result']=copy.deepcopy(base['cache']['output'])
 first=inputs[data['observations'][0]['id']]
 for operation,label in enumerate(('stale-dimensions','stale-count','stale-item','stale-components','forged-recipe','forged-output','forged-consumption','forged-remainder','absent-plan','closed-menu','invalid-button'),1):
  wanted=copy.deepcopy(base);wanted['id']=label
  wanted['abilities']['walking_speed']=0x7fc01234;wanted['abilities']['flying_speed']=0x80000000
  if operation==1:wanted['cache']['width']=3
  if operation==2:wanted['cache']['slots'][0]['count']+=1
  if operation==3:wanted['cache']['slots'][0]['id']='minecraft:birch_planks'
  if operation==4:wanted['cache']['slots'][0]['components']='unvalidated component identity'
  if operation==5:wanted['cache']['id']='fixture:forged_selection'
  if operation==6:wanted['cache']['output']['count']+=1
  if operation==7:wanted['cache']['consumption'][0]['count']=2
  if operation==8:wanted['cache']['consumption'][0]['remainder']={'id':'minecraft:bucket','components':'','count':1}
  if operation==9:wanted['cache']=None
  if operation==10:wanted['opened']=False
  wanted['message']='stale crafting plan; refresh required' if operation<=4 else 'cached crafting recipe changed; refresh required' if operation<=8 else 'crafting plan is absent; refresh required' if operation==9 else 'player inventory menu is closed or pickup button invalid'
  expected.append(wanted)
  raw_status='I.Status{False{},False{},False{},2143294004,2147483648}'
  cases.append('Case{'+q(label)+',recipe_0(),R.Grid{2,2,'+seq(slot(s) for s in first['craft'])+'},'+seq(slot(s) for s in base['all_backing_slots'])+',7,I.Abilities{False{},True{}},'+raw_status+',23n,True{},'+('2' if operation==11 else '0')+','+str(operation)+'}')
  raw_ability={**base['abilities'],'walking_speed':0x7fc01234,'flying_speed':0x80000000}
  runtime.append(runtime_case(label,first['source'],'fixture:case_0',{'width':2,'height':2,'slots':first['craft']},base['all_backing_slots'],raw_ability,2 if operation==11 else 0,operation))
 # Source-model geometry fixtures include arbitrary public Array trees. The
 # ordinary CPU runtime represents only equal-class Array nodes, so operations
 # 32/35 are constructor-boundary checks rather than authority observations.
 for operation,label in [(30,'player-logical-47'),(31,'player-backing-32'),(32,'player-unbalanced-backing')]:
  wanted=copy.deepcopy(base);wanted.update(id=label,message='invalid crafting inventory owner geometry')
  if operation==30:wanted['logical_length']=47
  if operation==31:wanted['all_backing_slots']=[None]*32;wanted['grid']['slots']=[]
  if operation==32:wanted['all_backing_slots']=[None]+wanted['all_backing_slots'];wanted['grid']['slots']=copy.deepcopy(wanted['all_backing_slots'][43:47])
  expected.append(wanted)
  cases.append('Case{'+q(label)+',recipe_0(),R.Grid{2,2,'+seq(slot(s) for s in first['craft'])+'},'+seq(slot(s) for s in base['all_backing_slots'])+',7,I.Abilities{False{},True{}},I.Status{False{},False{},False{},1036831949,1028443341},23n,True{},0,'+str(operation)+'}')
  runtime.append(runtime_case(label,first['source'],'fixture:case_0',{'width':2,'height':2,'slots':first['craft']},base['all_backing_slots'],base['abilities'],0,operation))
 table_index=next(i for i,row in enumerate(data['observations']) if row['input']['width']==3)
 table_input=copy.deepcopy(inputs[data['observations'][table_index]['id']]); table_wanted=copy.deepcopy(expected[table_index])
 before=data['observations'][table_index]['before'];ability=profile(before)
 original_slots=slots(before['inventory']['main_slots'])+slots(before['equipment'])+[None]*4+[actual(before['carried'])]+[{'id':s['item'],'components':'','count':s['count']} for s in tail]
 table_wanted.update(accepted=False,message='invalid crafting inventory owner geometry',revision=23,result=actual(before['result']),taken=None,all_backing_slots=original_slots,grid={'width':3,'height':3,'slots':slots(before['craft'])},bench_backing_slots=slots(before['craft'])+[{'id':s['item'],'components':'','count':s['count']} for s in bench_tail],bench_revision=5)
 source_recipe=table_input['source'];table_key=f'fixture:case_{table_index}'
 table_wanted['cache']={'id':table_key,'width':3,'height':3,'slots':slots(before['craft']),'output':actual(before['result']),'consumption':[{'slot':i,'count':1,'remainder':({'id':r['id'],'components':'','count':r['count']} if (r:=items[s['item']]['remainder']) else None)} for i,s in enumerate(table_input['craft']) if s]}
 for operation,label in [(33,'bench-logical-8'),(34,'bench-backing-8'),(35,'bench-unbalanced-backing')]:
  wanted=copy.deepcopy(table_wanted);wanted['id']=label
  if operation==33:wanted['grid']['slots']=wanted['grid']['slots'][:8]
  if operation==34:wanted['bench_backing_slots']=[None]*8;wanted['grid']['slots']=[None]*8
  if operation==35:wanted['bench_backing_slots']=[None]+wanted['bench_backing_slots'];wanted['grid']['slots']=copy.deepcopy(wanted['bench_backing_slots'][:9])
  expected.append(wanted)
  cases.append('Case{'+q(label)+',recipe_'+str(table_index)+'(),R.Grid{3,3,'+seq(slot(s) for s in table_input['craft'])+'},'+seq(slot(s) for s in original_slots)+',7,I.Abilities{False{},True{}},I.Status{False{},False{},False{},1036831949,1028443341},23n,True{},0,'+str(operation)+'}')
  runtime.append(runtime_case(label,table_input['source'],table_key,{'width':3,'height':3,'slots':table_input['craft']},original_slots,ability,0,operation))
 bad=copy.deepcopy(base);bad.update(id='unvalidated-component-input',cache=None,result=None,message='invalid crafting grid: dimensions, slot count, item definition or components')
 bad['all_backing_slots'][43]['components']='BendCraftComponents1\t64\t{}';bad['grid']['slots'][0]['components']='BendCraftComponents1\t64\t{}'
 expected.append(bad)
 cases.append('Case{'+q(bad['id'])+',recipe_0(),R.Grid{2,2,'+seq(slot(s) for s in bad['grid']['slots'])+'},'+seq(slot(s) for s in bad['all_backing_slots'])+',7,I.Abilities{False{},True{}},I.Status{False{},False{},False{},1036831949,1028443341},23n,True{},0,0}')
 runtime.append(runtime_case(bad['id'],first['source'],'fixture:case_0',bad['grid'],bad['all_backing_slots'],base['abilities']))
 production=json.loads((ROOT/'build/crafting-recipe-components/production-catalog.json').read_text())
 patched=[r for r in production['recipes'] if r['source']['type'] in ('minecraft:crafting_shaped','minecraft:crafting_shapeless') and r['source']['result'].get('components')]
 observed={r['id']:r for r in json.loads((ROOT/'reference/crafting_recipe_components.json').read_text())['cases']}
 grids={r['id']:r['grid'] for r in json.loads((ROOT/'build/crafting-recipe-components/native-input.json').read_text())['cases']}
 assert len(patched)==17
 item_map={r['id']:r for r in production['items']};tag_map={t['id']:t for t in production['tags']}
 for n,row in enumerate(patched):
  native_grid=grids[row['id']];java=observed[row['id']]['output'];assert not java['empty'] and java['id']=='minecraft:suspicious_stew' and java['count']==1
  identity='BendCraftComponents1\t1\t'+canonical(java['components']).decode()
  result={'id':java['id'],'components':identity,'count':1};inputs_for_case=[{**s,'components':''} if s else None for s in native_grid['slots']]
  names={s['id'] for s in inputs_for_case if s}|{java['id']};tag_names={v[1:] for v in row['source']['ingredients'] if isinstance(v,str) and v.startswith('#')}
  definitions=['R.ItemDefinition{'+q(id)+','+str(item_map[id]['limit'])+','+slot(item_map[id]['remainder'])+'}' for id in sorted(names)]
  fixture_tags=['R.Tag{'+q(id)+','+seq(q(v) for v in tag_map[id]['items'])+'}' for id in sorted(tag_names)]
  function='recipe_component_'+str(n)
  source+='\ndef '+function+'() -> R.Catalog:\n  R.Catalog{['+recipe(row['source'],row['id'],identity)+'],'+seq(fixture_tags)+','+seq(definitions)+'}\n'
  initial=[None]*43+copy.deepcopy(inputs_for_case)+[None]+copy.deepcopy(base['all_backing_slots'][48:]);after=copy.deepcopy(initial);after[43:47]=[None]*4;after[47]=copy.deepcopy(result)
  wanted=copy.deepcopy(base);wanted.update(id=row['id']+'-typed-take',accepted=True,message='',revision=24,result=None,cache=None,taken=copy.deepcopy(result),all_backing_slots=after,grid={'width':2,'height':2,'slots':[None]*4})
  expected.append(wanted)
  cases.append('Case{'+q(wanted['id'])+','+function+'(),R.Grid{2,2,'+seq(slot(s) for s in inputs_for_case)+'},'+seq(slot(s) for s in initial)+',7,I.Abilities{False{},True{}},I.Status{False{},False{},False{},1036831949,1028443341},23n,True{},0,20}')
  runtime.append(runtime_case(wanted['id'],row['source'],row['id'],native_grid,initial,base['abilities'],0,20))
  if n==0:
   refused=copy.deepcopy(wanted);refused.update(id=row['id']+'-default-only-refusal',accepted=False,message='crafting result lacks inventory component admission',revision=23,result=copy.deepcopy(result),taken=None,all_backing_slots=initial,grid=copy.deepcopy(native_grid))
   refused['grid']['slots']=copy.deepcopy(inputs_for_case)
   refused['cache']={'id':row['id'],'width':2,'height':2,'slots':copy.deepcopy(inputs_for_case),'output':copy.deepcopy(result),'consumption':[{'slot':i,'count':1,'remainder':None} for i in range(4)]}
   expected.append(refused)
   cases.append('Case{'+q(refused['id'])+','+function+'(),R.Grid{2,2,'+seq(slot(s) for s in inputs_for_case)+'},'+seq(slot(s) for s in initial)+',7,I.Abilities{False{},True{}},I.Status{False{},False{},False{},1036831949,1028443341},23n,True{},0,0}')
   runtime.append(runtime_case(refused['id'],row['source'],row['id'],native_grid,initial,base['abilities']))
 for wanted in expected:
  wanted['context_retained']=True
  wanted['bench_logical_length']=None if wanted['bench_backing_slots'] is None else (8 if wanted['id']=='bench-logical-8' else 9)
 source+='\ndef cases() -> List<&2,Case>:\n  '+seq(cases)+'\n'
 CACHE.mkdir(parents=True,exist_ok=True);(CACHE/'legacy-literal-cases.bend').write_text(source)
 assert len(runtime)==len(expected)==69
 CACHE.mkdir(parents=True,exist_ok=True)
 write_json(CACHE/'source-model-expected.json',expected)
 write_json(CACHE/'source-model-cases.json',{'cases':runtime})
 constructors=[case for case in runtime if case['operation'] in (32,35)]
 paired=[(case,wanted) for case,wanted in zip(runtime,expected,strict=True) if case['operation'] not in (32,35)]
 native_cases=[case for case,_ in paired];native_expected=[wanted for _,wanted in paired]
 assert len(native_cases)==len(native_expected)==67 and len(constructors)==2
 write_json(CACHE/'expected.json',native_expected)
 write_json(CACHE/'cases.json',{'cases':native_cases})
 write_json(CACHE/'constructor-cases.json',{'cases':constructors})
 return native_expected

def run(args,timeout,expected_returncode=0):
 start=time.monotonic();r=subprocess.run(list(map(str,args)),cwd=ROOT,capture_output=True,text=True,timeout=timeout)
 logs=CACHE/'runs';logs.mkdir(parents=True,exist_ok=True);stem=logs/str(time.time_ns())
 stdout=stem.with_suffix('.stdout');stderr=stem.with_suffix('.stderr');stdout.write_text(r.stdout);stderr.write_text(r.stderr)
 receipt={'command':list(map(str,args)),'seconds':time.monotonic()-start,'returncode':r.returncode,'stdout':r.stdout[-6000:],'stderr':r.stderr[-6000:],'stdout_file':str(stdout),'stderr_file':str(stderr)}
 if r.returncode!=expected_returncode:raise AssertionError(receipt)
 return r,receipt

def constructor_boundaries(command,timeout,prefix_rows=()):
 path=CACHE/'cases.json';retained=path.read_bytes();checks=[]
 constructors=json.loads((CACHE/'constructor-cases.json').read_text())['cases']
 try:
  for case in constructors:
   write_json(path,{'cases':[case]})
   actual,receipt=run(command,timeout,expected_returncode=1)
   assert actual.stderr=='bend: runtime fail-stop\n',(case['id'],actual.stderr)
   rows=[json.loads(line) for line in actual.stdout.splitlines() if line.strip()]
   assert rows==list(prefix_rows),(case['id'],len(rows),len(prefix_rows))
   receipt.pop('stdout');receipt.update(id=case['id'],output_sha256=hashlib.sha256(actual.stdout.encode()).hexdigest(),observed_authority_cases=0,constructor='Array.ANode',child_physical_classes=[0,6 if case['operation']==32 else 4])
   checks.append(receipt)
 finally:path.write_bytes(retained)
 return checks

def build(entry_relative='tests/player_crafting_authority.bend',binary=BINARY,cache=CACHE,resume_snapshot=None):
 # Freeze the actual source graph once. The verified modular native cache
 # separately retains exact C emission and compiler/library closure, so a
 # bounded link failure cannot discard a completed expensive emission.
 import build_native as B
 import test_remote_resource_client as Owned
 import sys
 work=cache/('build-'+str(time.time_ns()));work.mkdir(parents=True)
 base=Path('/Users/chuah/Documents/ChatGPT/bendex/bend/bend2/base.bend')
 if resume_snapshot is None:
  snapshot=B.Snapshot();B.source_graph(ROOT/entry_relative,base,os.environ,snapshot)
  manifest=snapshot.manifest();frozen=work/'source';frozen.mkdir()
  for record in manifest:
   path=Path(record['path']);content=path.read_bytes()
   assert hashlib.sha256(content).hexdigest()==record['sha256'],('source changed during freeze',path)
   if path.is_relative_to(ROOT):
    target=frozen/path.relative_to(ROOT);target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(content)
 else:
  frozen=Path(resume_snapshot).resolve();pins=json.loads((frozen.parent/'source-pins.json').read_text())
  manifest=pins['original']
 entry=frozen/entry_relative;compiled=B.Snapshot();B.source_graph(entry,base,os.environ,compiled)
 compiled_manifest=compiled.manifest()
 if resume_snapshot is not None:assert compiled_manifest==pins['compiled'],'resumed frozen graph changed'
 write_json(work/'source-pins.json',{'original':manifest,'compiled':compiled_manifest})
 Owned.WORK=work
 cache_report=work/'native-cache.json'
 prepare_command=[sys.executable,ROOT/'tools/player_crafting_authority_native.py',entry,'--report',cache_report]
 emitted=Owned.bounded(prepare_command,600,'c-emission');Owned.process_ok(emitted)
 native=json.loads(cache_report.read_text());temporary=work/'program'
 command=[native['context']['compiler']['path']]+[native['emitted_file'] if arg=='<emitted.c>' else str(temporary) if arg=='<native>' else arg for arg in native['context']['compiler']['flags']]
 linked=Owned.bounded(command,600,'native-compile');Owned.process_ok(linked)
 checked_report=work/'native-cache-after.json'
 checked=Owned.bounded([sys.executable,ROOT/'tools/player_crafting_authority_native.py',entry,'--report',checked_report],60,'closure-check');Owned.process_ok(checked)
 after_native=json.loads(checked_report.read_text())
 assert native['cache_key']==after_native['cache_key'] and native['key_data']==after_native['key_data'],'native source/compiler/header/library closure changed'
 after=B.Snapshot();B.source_graph(entry,base,os.environ,after)
 assert compiled_manifest==after.manifest(),'frozen compiler graph changed'
 binary.parent.mkdir(parents=True,exist_ok=True);os.replace(temporary,binary)
 receipt={'seconds':sum(r['seconds'] for r in (emitted,linked,checked)),'exit_code':0,'stages':{'emission':emitted,'native_compile':linked,'closure':checked}}
 report={'result':receipt,'binary':fingerprint(binary),'sources':manifest,'compiled_sources':compiled_manifest,'compiler':fingerprint(Path('/Users/chuah/.bend/bin/bend')),'snapshot_directory':str(frozen),'native_cache':{'cache_key':native['cache_key'],'c_emission_cache_hit':native['emitted_seconds']==0,'emitted_c_sha256':native['emitted_c_sha256'],'compiler':native['context']['compiler'],'environment_sha256':native['context']['environment_sha256']},'native_cache_report':fingerprint(cache_report),'route':'actual Bend C emission + installed CLI ordinary CPU compiler flags; immutable input/header/library closure revalidated before publication'}
 write_json(work/'success.json',report);write_json(cache/'build.json',report)
 return report

def main():
 p=argparse.ArgumentParser();p.add_argument('--prepare',action='store_true');p.add_argument('--native',action='store_true');p.add_argument('--build',action='store_true');p.add_argument('--frozen-source',type=Path);a=p.parse_args();expected=prepare()
 if a.prepare:print(json.dumps({'prepared_cases':len(expected)}));return
 if a.build:
  build(resume_snapshot=a.frozen_source)
 if a.native:
  checks=[]
  for threads in (1,4):
   r,pin=run([BINARY,'--threads',threads,'--gpu','off','generated/reference_item_metadata.tsv',CACHE/'cases.json'],60);observed=[json.loads(l) for l in r.stdout.splitlines() if l.strip()];assert len(observed)==len(expected),(len(observed),len(expected))
   for got,wanted in zip(observed,expected,strict=True):assert got==wanted,(got['id'],got,wanted)
   pin.pop('stdout');pin['output_sha256']=hashlib.sha256(r.stdout.encode()).hexdigest();checks.append(pin)
  assert checks[0]['output_sha256']==checks[1]['output_sha256']
  constructors=constructor_boundaries([BINARY,'--threads','1','--gpu','off','generated/reference_item_metadata.tsv',CACHE/'cases.json'],60)
  build_record=json.loads((CACHE/'build.json').read_text());assert build_record['binary']['sha256']==fingerprint(BINARY)['sha256']
  write_json(ROOT/'evidence/player-crafting-authority-native.json',{'status':'passed','pin':'26.3','cases':len(expected),'source_model_cases':69,'native_constructor_rejection_count':2,'native':checks,'native_constructor_rejections':constructors,'build':build_record,'binary':fingerprint(BINARY),'reference':fingerprint(P.OUTPUT),'component_assembly_reference':fingerprint(ROOT/'reference/crafting_recipe_components.json'),'item_definitions':fingerprint(ROOT/'generated/reference_item_metadata.tsv'),'atomic_disposition_refusals':4,'exact_java_item_state_cases':29,'additional_admission_refusals':13,'malformed_owner_refusals':4,'isolated_typed_component_takes':17,'boundaries':['Client prediction result synchronization is not a server RecipeManager lifecycle.','Remainder world drop/creative discard is explicitly refused atomically.','Seventeen isolated typed component takes compare to actual Java assembled components, not a whole component-bearing Java menu/save lifecycle.','The two unbalanced source Array fixtures fail the native equal-child-class constructor guard before any authority observation; they are not authority refusal cases.','DefaultOnly refuses all nonempty component identities; the real inventory, codec and persistence consumer join must precede live TypedStew enablement.']})
  print(json.dumps({'status':'passed','cases':len(expected),'native':checks}))
if __name__=='__main__':main()
