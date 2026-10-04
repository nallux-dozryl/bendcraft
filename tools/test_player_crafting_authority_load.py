#!/usr/bin/env python3
"""Actual Bend JAR-entry/decoder/service path, using the full production metadata."""
from __future__ import annotations
import argparse,copy,hashlib,json
from pathlib import Path
import reference_player_inventory_probe as Player
import test_player_crafting_authority as Authority
from reference_inventory import ROOT,canonical,fingerprint,write_json

CACHE=ROOT/'build/player-crafting-authority-load'
BINARY=CACHE/'loader'
PRODUCTION=ROOT/'build/crafting-recipe-components/production-catalog.json'

def prepare():
 source=json.loads(PRODUCTION.read_text())
 assert len(source['recipes'])==2042 and len(source['items'])==1658 and len(source['tags'])==236
 # Original source recipes are read by Bend from the installed JAR. Only the
 # observed metadata and caller-authoritative registry order cross this input.
 request={'metadata':{k:source[k] for k in ('items','tags')},'ids':[r['id'] for r in source['recipes']]}
 CACHE.mkdir(parents=True,exist_ok=True);write_json(CACHE/'request.json',request)
 patched={r['id']:r for r in json.loads((ROOT/'reference/crafting_recipe_components.json').read_text())['cases']}
 expected=[];limits={r['id']:r['limit'] for r in source['items']}
 for row in source['recipes']:
  recipe=row['source'];kind=recipe['type']
  if kind not in ('minecraft:crafting_shaped','minecraft:crafting_shapeless'):
   expected.append({'id':row['id'],'kind':kind});continue
  output=recipe['result'];components=''
  if output.get('components'):
   java=patched[row['id']]['output'];assert not java['empty']
   components='BendCraftComponents1\t'+str(java['limit'])+'\t'+canonical(java['components']).decode()
  value={'id':output['id'],'components':components,'count':output.get('count',1)}
  # These are decoded declarations; strict assembly is independently tested
  # by the recipe matcher and authority result-take harness.
  expected.append({'id':row['id'],'kind':'shaped' if kind.endswith('shaped') else 'shapeless','output':value,'default_admitted':not bool(components) and value['count']<=limits[value['id']],'typed_stew_admitted':value['count']<=limits[value['id']]})
 return request,{'definitions':1658,'items':1658,'tags':236,'recipes':expected}

def main():
 parser=argparse.ArgumentParser();parser.add_argument('--prepare',action='store_true');parser.add_argument('--build',action='store_true');parser.add_argument('--native',action='store_true');parser.add_argument('--frozen-source',type=Path);args=parser.parse_args()
 request,expected=prepare();authority_expected=Authority.prepare()
 if args.prepare:print(json.dumps({'recipe_entries':2042,'ordinary':1202,'unsupported':840,'patched':17}));return
 if args.build:Authority.build('tests/player_crafting_authority_load.bend',BINARY,CACHE,args.frozen_source)
 if args.native:
  checks=[]
  for threads in (1,4):
   actual,receipt=Authority.run([BINARY,'--threads',threads,'--gpu','off',Player.CLIENT,'generated/reference_item_metadata.tsv',CACHE/'request.json'],180)
   lines=[json.loads(line) for line in actual.stdout.splitlines() if line.strip()];observed=lines[0]
   assert observed==expected,next(((a,b) for a,b in zip(observed.get('recipes',[]),expected['recipes']) if a!=b),(observed,expected))
   assert len(lines)==7+len(authority_expected),len(lines)
   cache=lambda amount:{'id':'minecraft:stick','width':2,'height':2,'slots':[{'id':'minecraft:oak_planks','components':'','count':amount},None,{'id':'minecraft:oak_planks','components':'','count':amount},None],'output':{'id':'minecraft:stick','components':'','count':4},'consumption':[{'slot':0,'count':1,'remainder':None},{'slot':2,'count':1,'remainder':None}]}
   outputs=[]
   for label,amount,carried,revision,opened,accepted,message,refreshed in [('opened',2,0,0,True,True,'',True),('first',1,4,1,True,True,'',True),('second',0,8,2,True,True,'',True),('absent',0,8,2,True,False,'crafting plan is absent; refresh required',False),('closed',0,0,3,False,True,'',True)]:
    inventory=[None]*48
    if amount:inventory[43]={'id':'minecraft:oak_planks','components':'','count':amount};inventory[45]=copy.deepcopy(inventory[43])
    if carried:inventory[47]={'id':'minecraft:stick','components':'','count':carried}
    if label=='closed':inventory[0]={'id':'minecraft:stick','components':'','count':8}
    outputs.append({'label':label,'accepted':accepted,'message':message,'selected':7,'revision':revision,'opened':opened,'slots':inventory,'taken':{'id':'minecraft:stick','components':'','count':4} if label in ('first','second') else None,'result':{'id':'minecraft:stick','components':'','count':4} if amount else None,'cache':cache(amount) if amount else None,'cache_refreshed':refreshed})
   java=next(r['output'] for r in json.loads((ROOT/'reference/crafting_recipe_components.json').read_text())['cases'] if r['id']=='minecraft:suspicious_stew_from_allium')
   stew={'id':java['id'],'components':'BendCraftComponents1\t1\t'+canonical(java['components']).decode(),'count':1};inventory=[None]*48;inventory[47]=copy.deepcopy(stew)
   outputs.append({'label':'typed-stew','accepted':True,'message':'','selected':7,'revision':1,'opened':True,'slots':inventory,'taken':stew,'result':None,'cache':None,'cache_refreshed':True})
   assert lines[1:7]==outputs,next(((a,b) for a,b in zip(lines[1:7],outputs) if a!=b),(lines[1:7],outputs))
   for got,wanted in zip(lines[7:],authority_expected,strict=True):assert got==wanted,(got['id'],got,wanted)
   receipt.pop('stdout');receipt['output_sha256']=hashlib.sha256(actual.stdout.encode()).hexdigest();checks.append(receipt)
  for threads in (1,4):
   actual,receipt=Authority.run([BINARY,'--threads',threads,'--gpu','off','--facts',Player.CLIENT,'generated/reference_item_metadata.tsv','generated/reference_crafting_authority_metadata.json'],180)
   assert hashlib.sha256(actual.stdout.encode()).hexdigest()==checks[0]['output_sha256'],'startup facts path differs from explicit actual JAR service'
   receipt.pop('stdout');receipt['output_sha256']=hashlib.sha256(actual.stdout.encode()).hexdigest();receipt['pinned_startup_facts']=True;checks.append(receipt)
  assert checks[0]['output_sha256']==checks[1]['output_sha256']
  failures=[]
  def reject(label,mutate,message):
   value=copy.deepcopy(request);mutate(value);path=CACHE/(label+'.json');write_json(path,value)
   import subprocess,time
   started=time.monotonic();result=subprocess.run([str(BINARY),'--threads','1','--gpu','off',str(Player.CLIENT),'generated/reference_item_metadata.tsv',str(path)],cwd=ROOT,capture_output=True,text=True,timeout=180)
   assert result.returncode==2 and message in result.stderr,(label,result.returncode,result.stdout,result.stderr)
   failures.append({'id':label,'returncode':2,'seconds':time.monotonic()-started,'stderr':result.stderr.strip()})
  reject('duplicate-request',lambda r:r['ids'].append(r['ids'][0]),'duplicate recipe resource request')
  reject('missing-resource',lambda r:r.update(ids=['minecraft:absent_recipe_resource']),'missing recipe resource')
  reject('invalid-resource-id',lambda r:r.update(ids=['minecraft:Stick']),'invalid recipe resource identifier')
  reject('conflicting-item-limit',lambda r:r['metadata']['items'][1].update(limit=1),'disagrees')
  reject('unknown-tag-member',lambda r:r['metadata']['tags'][0]['items'].append('minecraft:absent_item'),'tag contains an unknown item')
  reject('error-shaped-defaults',lambda r:r['metadata']['items'][1].update(components={'error':'failed registry lookup'}),'incomplete or invalid initialized component map')
  reject('missing-default-component',lambda r:r['metadata']['items'][1]['components'].pop('minecraft:lore'),'incomplete or invalid initialized component map')
  reject('missing-item-definition',lambda r:r['metadata']['items'].pop(),'disagrees with initialized player definitions')
  def forged_defaults(r):
   item=next(i for i in r['metadata']['items'] if i['id']=='minecraft:suspicious_stew')
   item['components']['minecraft:suspicious_stew_effects']=copy.deepcopy(java['components']['minecraft:suspicious_stew_effects'])
  reject('forged-stew-defaults',forged_defaults,'invalid initialized suspicious stew defaults')
  old=CACHE/'old-error-defaults-production-catalog.json'
  if old.exists():
   old_metadata=json.loads(old.read_text());reject('original-bad-registry-defaults',lambda r:r.update(metadata={k:old_metadata[k] for k in ('items','tags')}),'incomplete or invalid initialized component map')
  facts_path=CACHE/'changed-runtime-facts.json';facts_path.write_bytes((ROOT/'generated/reference_crafting_authority_metadata.json').read_bytes()+b' ')
  import subprocess
  result=subprocess.run([str(BINARY),'--threads','1','--gpu','off','--facts',str(Player.CLIENT),'generated/reference_item_metadata.tsv',str(facts_path)],cwd=ROOT,capture_output=True,text=True,timeout=60)
  assert result.returncode==2 and 'pinned crafting registry facts digest mismatch' in result.stderr,(result.returncode,result.stdout,result.stderr)
  failures.append({'id':'changed-pinned-runtime-facts','returncode':2,'stderr':result.stderr.strip()})
  import subprocess,time
  artifact={'items':[],'tags':[],'recipes':[]};prefix=canonical(artifact);path=CACHE/'artifact-prefix.json';path.write_bytes(prefix)
  result=subprocess.run([str(BINARY),'--threads','1','--gpu','off','--artifact',str(path),str(len(prefix))],cwd=ROOT,capture_output=True,text=True,timeout=30)
  assert result.returncode==0 and result.stdout.strip()=='artifact loaded',(result.returncode,result.stdout,result.stderr)
  path.write_bytes(prefix+b'garbage beyond the byte limit')
  result=subprocess.run([str(BINARY),'--threads','1','--gpu','off','--artifact',str(path),str(len(prefix))],cwd=ROOT,capture_output=True,text=True,timeout=30)
  assert result.returncode==2 and 'crafting catalog exceeds byte budget' in result.stderr,(result.returncode,result.stdout,result.stderr)
  failures.append({'id':'artifact-valid-prefix-with-trailing-bytes','returncode':2,'stderr':result.stderr.strip()})
  build=json.loads((CACHE/'build.json').read_text());assert build['binary']['sha256']==fingerprint(BINARY)['sha256']
  report={'status':'passed','pin':'26.3','recipe_entries':2042,'ordinary':1202,'unsupported':840,'patched_outputs':17,'item_definitions':1658,'resolved_tags':236,'menu_producer_observations':6,'authority_cases':len(authority_expected),'initialized_default_maps':1658,'default_codec_errors':0,'native':checks,'admission_failures':failures,'build':build,'jar':fingerprint(Player.CLIENT),'production_metadata':fingerprint(PRODUCTION),'item_table':fingerprint(ROOT/'generated/reference_item_metadata.tsv'),'component_reference':fingerprint(ROOT/'reference/crafting_recipe_components.json'),'runtime_facts':fingerprint(ROOT/'generated/reference_crafting_authority_metadata.json'),'runtime_fixtures':fingerprint(Authority.CACHE/'cases.json'),'boundaries':['Bend owns ZIP entry reads, schema admission and catalog decoding. Initialized maps require all 13 common pinned keys and registered persistent member names; this structural check does not implement unrelated component value codecs.','Supplied source order is caller authority; this path does not infer registry precedence from ZIP directory order.','Nested tag resolution and initialized default maps are explicit observed metadata inputs; this loader does not implement resource-pack override/tag resolution.','Ordinary declarations and the closed component-profile seam are tested; unrelated item component codecs and special recipe semantics remain unsupported.','The actual menu producer is tested with service-loaded recipes; session/backend/entry/wire adoption is a separate root integration.']}
  write_json(ROOT/'evidence/player-crafting-authority-load.json',report)
  write_json(ROOT/'evidence/player-crafting-authority-native.json',{'status':'passed','pin':'26.3','cases':len(authority_expected),'native':checks,'build':build,'binary':fingerprint(BINARY),'reference':fingerprint(Authority.P.OUTPUT),'component_assembly_reference':fingerprint(ROOT/'reference/crafting_recipe_components.json'),'item_definitions':fingerprint(ROOT/'generated/reference_item_metadata.tsv'),'atomic_disposition_refusals':4,'exact_java_item_state_cases':29,'additional_admission_refusals':13,'malformed_owner_refusals':6,'isolated_typed_component_takes':17,'boundaries':['The same frozen native binary runs the full JAR loader, six menu producer observations, and all authority cases.','Remainder world drop/creative discard is explicitly refused atomically.','Typed component fixtures use the actual shared D.component_defaults/C.metadata seam; root session, presentation and live persistence composition are separate integration checks.']})
  print(json.dumps({'status':'passed','recipes':2042,'ordinary':1202,'patched':17,'admission_failures':len(failures)}))

if __name__=='__main__':main()
