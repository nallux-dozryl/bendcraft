#!/usr/bin/env python3
"""Native exact comparisons with actual Player.travel outputs."""
from __future__ import annotations
import argparse, collections, copy, json, pathlib, re, time
from test_geometry import run, words, word_vector, verify_fixture_provenance, sha
from test_movement import shape_words
from reference_inventory import JAVA, fingerprint
from reference_block_probe import verified_classpath
ROOT=pathlib.Path(__file__).resolve().parents[1];BEND=pathlib.Path('/Users/chuah/.bend/bin/bend');BINARY=ROOT/'build/travel-tests';FIXTURE=ROOT/'reference/travel.json';TABLE=ROOT/'generated/reference_mth_sin.f32'

def request(c,op='travel'):
 v={**c['input'],**c['observation']['actual_input']}
 fields=[c['id'],op,*word_vector(v['position']),*word_vector(v['box']),*word_vector(v['velocity']),str(int(v['width_f32_bits'],16)),str(int(v['height_f32_bits'],16)),*[str(int(b)) for b in v['flags']],*word_vector(v['input']),*[str(p&0xffffffff) for p in c['observation']['below_position']],str(int(v['block_friction_f32_bits'],16)),*word_vector([v[k] for k in ['movement_speed','gravity','friction_modifier','air_drag_modifier']]),str(int(v['yaw_f32_bits'],16)),str(int(v['maximum_f32_bits'],16)),*[str(int(v[k])) for k in ['sprinting','no_gravity','discard_friction']],str(v.get('mode',0))]
 return ';'.join(['|'.join(fields),shape_words(v['initial']),shape_words(v['step'])])
def values(f):assert len(f)%2==0;return [f'{int(f[i]):08x}{int(f[i+1]):08x}' for i in range(0,len(f),2)]
def parse(line):
 id,kind,*f=line.split('|')
 if kind=='error':return id,{'error':'|'.join(f)}
 if kind=='prepared':assert len(f)==8;return id,{'requested':values(f[:6]),'friction_f32_bits':f'{int(f[6]):08x}','acceleration_f32_bits':f'{int(f[7]):08x}'}
 assert kind=='body' and len(f)==30,(kind,len(f))
 return id,{'position':values(f[:6]),'box':values(f[6:18]),'velocity':values(f[18:24]),'width_f32_bits':f'{int(f[24]):08x}','height_f32_bits':f'{int(f[25]):08x}','flags':[bool(int(x)) for x in f[26:]]}
def validation_cases(base):
 result=[]
 def add(label,change,error):
  c=copy.deepcopy(base);c['id']='validation:'+label;change(c['observation']['actual_input']);c['expected']={'error':error};result.append(c)
 for i in range(1,13):add('mode-'+str(i),lambda v,i=i:v.__setitem__('mode',i),'mode|'+str(i))
 for field,key in enumerate(['movement_speed','gravity','friction_modifier','air_drag_modifier']):
  for val in ['7ff0000000000000','fff0000000000000','7ff8000000000123','40f0000000000000']:
   add(key+'-'+val,lambda v,key=key,val=val:v.__setitem__(key,val),'attribute|'+str(field))
 for field,key in [(0,'yaw_f32_bits'),(1,'block_friction_f32_bits'),(2,'maximum_f32_bits')]:
  for val in ['7f800000','ff800000','7fc01234']:
   add(key+'-'+val,lambda v,key=key,val=val:v.__setitem__(key,val),'context|'+str(field))
 for val in ['bf800000','40000000']:add('friction-range-'+val,lambda v,val=val:v.__setitem__('block_friction_f32_bits',val),'context|1')
 add('negative-step',lambda v:v.__setitem__('maximum_f32_bits','bf800000'),'context|2')
 for axis in range(3):add('input-'+str(axis),lambda v,axis=axis:v.__setitem__('input',[('7ff0000000000000' if i==axis else '0000000000000000') for i in range(3)]),'input|'+str(axis))
 for component,key in [(0,'position'),(1,'box'),(2,'velocity')]:
  for axis in range(6 if component==1 else 3):
   add(key+'-'+str(axis),lambda v,key=key,axis=axis:v[key].__setitem__(axis,'7ff8000000000123'),'movement|body|'+str(component)+'|'+str(axis))
 for phase,key in enumerate(['initial','step']):
  add('bad-collider-'+str(phase),lambda v,key=key:v.__setitem__(key,[{'kind':'raw_array_box','box':['7ff0000000000000']+v['box'][1:]}]),f'movement|collider|{phase}|0|0')
 add('priority-mode',lambda v:(v.__setitem__('mode',1),v.__setitem__('yaw_f32_bits','7f800000'),v['position'].__setitem__(0,'7ff0000000000000')),'mode|1')
 return result
def main():
 p=argparse.ArgumentParser();p.add_argument('--skip-build',action='store_true');a=p.parse_args();fixture=json.loads(FIXTURE.read_text());provenance=verify_fixture_provenance(fixture)
 jars,_=verified_classpath();assert fixture['classpath_libraries']==[fingerprint(x) for x in jars[1:]];assert fixture['runtime_executable']==fingerprint(JAVA)
 checks=[]
 for src in ['src/travel.bend','tests/travel.bend']:
  checks.append(run([BEND,src,'--check-only']));checks.append(run([BEND,src,'--verdict']))
 builds=[]
 if not a.skip_build:
  builds.append(run([BEND,'tests/travel.bend','-o','build/travel-tests.c']));builds.append(run([BEND,'tests/travel.bend','-o',BINARY]))
 start=time.monotonic();native=[];names=set()
 for offset in range(0,len(fixture['cases']),100):
  chunk=fixture['cases'][offset:offset+100]
  for op in ['travel','prepare','movement']:
   r=run([BINARY,'--gpu','off',TABLE,*[request(c,op) for c in chunk]]);lines=r['stdout'].splitlines();assert len(lines)==len(chunk)
   native.append({'operation':op,'offset':offset,'cases':len(chunk),'seconds':r['seconds']})
   for c,line in zip(chunk,lines,strict=True):
    id,answer=parse(line);assert id==c['id']
    expected=c['expected'] if op=='travel' else c['observation']['post_move_body'] if op=='movement' else {k:c['observation'][k] for k in ['requested','friction_f32_bits','acceleration_f32_bits']}
    assert answer==expected,(id,op,expected,answer)
    if op=='travel':assert id not in names;names.add(id)
 validation=validation_cases(fixture['cases'][0])
 for offset in range(0,len(validation),50):
  chunk=validation[offset:offset+50];r=run([BINARY,'--gpu','off',TABLE,*[request(c) for c in chunk]])
  assert len(r['stdout'].splitlines())==len(chunk)
  for c,line in zip(chunk,r['stdout'].splitlines(),strict=True):
   id,answer=parse(line);assert id==c['id'] and answer==c['expected'],(id,c['expected'],answer)
 # A successful actual transition after each rejected context observes retained ownership.
 follow=[]
 for i,c in enumerate(validation):
  good=copy.deepcopy(fixture['cases'][0]);good['id']='retained-'+str(i);follow.extend([c,good])
 for offset in range(0,len(follow),100):
  chunk=follow[offset:offset+100];r=run([BINARY,'--gpu','off',TABLE,*[request(c) for c in chunk]])
  for c,line in zip(chunk,r['stdout'].splitlines(),strict=True):
   id,answer=parse(line);assert id==c['id'] and answer==c['expected'],(id,answer,c['expected'])
 malformed=[]
 for value in ['broken','broken;;','bad|travel|nope;;']:
  r=run([BINARY,'--gpu','off',TABLE,value],required=False);assert r['exit_code']==2 and 'invalid travel' in r['stderr'];malformed.append({'exit_code':r['exit_code'],'stderr':r['stderr']})
 source=(ROOT/'src/travel.bend').read_text();assert not re.search(r'@unsafe|\bimport\s+["\']|\w!\(',source)
 c_path=ROOT/'build/travel-tests.c';text=c_path.read_text();sources=['src/travel.bend','tests/travel.bend','tools/reference_travel_probe.py','tools/test_travel.py','docs/TRAVEL.md','src/locomotion.bend','src/movement.bend','src/f64.bend']
 e={'schema_version':1,'status':'passed','pin':'26.3','fixture_sha256':sha(FIXTURE),'fixture_provenance':provenance,'checks':checks,'builds':builds,'native_batches':native,'actual_player_travel_cases':len(names),'prepared_request_comparisons':len(names),'pre_gravity_post_move_body_comparisons':len(names),'explicit_rejection_cases':len(validation),'successful_owner_retention_followups':len(validation),'malformed_protocol':malformed,'kernel_pass':True,'laws':re.findall(r'^law (\w+):',source,re.M),'native_validation_seconds':round(time.monotonic()-start,6),'sources_sha256':{x:sha(ROOT/x) for x in sources if (ROOT/x).exists()},'binary_sha256':sha(BINARY),'emitted_c_sha256':sha(c_path),'emitted_c_bytes':len(text.encode()),'table':fingerprint(TABLE),'oracle_scope':fixture['scope'],'confidence':fixture['confidence'],'unsupported':['full Player.tick/aiStep','dynamic support/friction/attribute resolver','ServerPlayer and actual server world','liquid/swimming/flying/gliding/climbing','powder snow','mob effects','passenger controllers','nonneutral blocks/hazards','edge backoff','general bounce']}
 (ROOT/'evidence/travel-verification.json').write_text(json.dumps(e,indent=2,sort_keys=True)+'\n');print(json.dumps({k:e[k] for k in ['status','actual_player_travel_cases','prepared_request_comparisons','explicit_rejection_cases','successful_owner_retention_followups','kernel_pass','native_validation_seconds','confidence']},indent=2))
if __name__=='__main__':main()
