#!/usr/bin/env python3
"""Exact native Player.aiStep projection versus direct actual Java calls."""
from __future__ import annotations
import argparse, copy, hashlib, json, pathlib, re, time
from test_geometry import run, word_vector, verify_fixture_provenance, sha
from test_movement import shape_words
from test_travel import parse as parse_travel, values
from reference_inventory import JAVA, fingerprint, canonical
from reference_block_probe import verified_classpath
ROOT=pathlib.Path(__file__).resolve().parents[1];BEND=pathlib.Path('/Users/chuah/.bend/bin/bend');BINARY=ROOT/'build/player-tick-tests';FIXTURE=ROOT/'reference/player_tick.json';TABLE=ROOT/'generated/reference_mth_sin.f32'

def request(c,t,i,op='tick'):
 v=c['input'];o=t['observation'];s=o['initial'];a=o['attributes'];update=v['ticks'][i]
 sprint=v['sprinting']
 for u in v['ticks'][:i+1]:sprint=u.get('sprinting',sprint)
 fields=[c['id']+':'+str(i),op,*word_vector(s['position']),*word_vector(s['box']),*word_vector(s['velocity']),str(int(s['width_f32_bits'],16)),str(int(s['height_f32_bits'],16)),*[str(int(b)) for b in s['flags']],*[str(int(b,16)) for b in s['input_f32_bits']],str(int(s['jumping'])),str(s['jump_delay']&0xffffffff),str(s['jump_trigger']&0xffffffff),str(int(s['needs_sync'])),str(int(s['stored_speed_f32_bits'],16)),str(int(s['head_yaw_f32_bits'],16)),*[str(p&0xffffffff) for p in o['below_position']],str(int(o['block_friction_f32_bits'],16)),*word_vector([a[k] for k in ['movement_speed','gravity','friction_modifier','air_drag_modifier']]),str(int(v['yaw_f32_bits'],16)),str(int(a['maximum_f32_bits'],16)),str(int(sprint)),str(int(v['no_gravity'])),str(int(v['discard_friction'])),str(v.get('travel_mode',0)),*word_vector([a['jump_strength']]),str(int(a['jump_factor_f32_bits'],16)),str(int(v.get('affected_by_fluids',True))),str(v.get('tick_mode',0)),str(int('input_f32_bits' in update)),str(int('jumping' in update))]
 return ';'.join(['|'.join(fields),shape_words(o['initial_shapes']),shape_words(o['step_shapes'])])

def signed(v):return int(v) if int(v)<2**31 else int(v)-2**32
def parse(line):
 id,kind,*f=line.split('|')
 if kind=='error':return id,{'error':'|'.join(f)}
 if kind=='jump':
  assert len(f)==32;_,body=parse_travel('|'.join([id,'body',*f[:30]]));return id,{'body':body,'needs_sync':bool(int(f[30])),'power_f32_bits':f'{int(f[31]):08x}'}
 assert kind in ['state','prepared'] and len(f)==(39 if kind=='state' else 45),(kind,len(f))
 _,body=parse_travel('|'.join([id,'body',*f[:30]]))
 state={**body,'input_f32_bits':[f'{int(x):08x}' for x in f[30:33]],'jumping':bool(int(f[33])),'jump_delay':signed(f[34]),'jump_trigger':signed(f[35]),'needs_sync':bool(int(f[36])),'stored_speed_f32_bits':f'{int(f[37]):08x}','head_yaw_f32_bits':f'{int(f[38]):08x}'}
 return id,{'state':state,'travel_input':values(f[39:])} if kind=='prepared' else state

def validation_cases(base):
 result=[]
 def add(label,change,error):
  c=copy.deepcopy(base);c['id']='rejected:'+label;change(c);result.append((c,{'error':error}))
 for i in range(1,8):add('tick-mode-'+str(i),lambda c,i=i:c['input'].__setitem__('tick_mode',i),'mode|'+str(i))
 for i in range(1,13):add('travel-mode-'+str(i),lambda c,i=i:c['input'].__setitem__('travel_mode',i),'travel|mode|'+str(i))
 for raw in ['7ff0000000000000','fff0000000000000','7ff8000000000123','bff0000000000000','4040800000000000']:
  add('jump-strength-'+raw,lambda c,raw=raw:c['ticks'][0]['observation']['attributes'].__setitem__('jump_strength',raw),'jump|0')
 for raw in ['7f800000','ff800000','7fc01234','bf800000','40000000']:
  add('jump-factor-'+raw,lambda c,raw=raw:c['ticks'][0]['observation']['attributes'].__setitem__('jump_factor_f32_bits',raw),'jump|1')
 for i in range(3):
  for raw in ['7f800000','ff800000','7fc01234']:
   add('float-input-'+str(i)+'-'+raw,lambda c,i=i,raw=raw:c['ticks'][0]['observation']['initial']['input_f32_bits'].__setitem__(i,raw),'state|'+str(i))
 for index,key in [(5,'stored_speed_f32_bits'),(6,'head_yaw_f32_bits')]:
  add(key,lambda c,key=key:c['ticks'][0]['observation']['initial'].__setitem__(key,'7fc01234'),'state|'+str(index))
 for index,key in enumerate(['movement_speed','gravity','friction_modifier','air_drag_modifier']):
  add(key,lambda c,key=key:c['ticks'][0]['observation']['attributes'].__setitem__(key,'7ff8000000000123'),'travel|attribute|'+str(index))
 for raw in ['7f800000','7fc01234']:
  add('yaw-'+raw,lambda c,raw=raw:c['input'].__setitem__('yaw_f32_bits',raw),'travel|context|0')
 for component,key in [(0,'position'),(1,'box'),(2,'velocity')]:
  for i in range(6 if component==1 else 3):
   add('body-'+key+'-'+str(i),lambda c,key=key,i=i:c['ticks'][0]['observation']['initial'][key].__setitem__(i,'7ff8000000000123'),f'travel|movement|body|{component}|{i}')
 for phase,key in enumerate(['initial_shapes','step_shapes']):
  add('collider-'+str(phase),lambda c,key=key:c['ticks'][0]['observation'].__setitem__(key,[{'kind':'raw_array_box','box':['7ff0000000000000']+c['ticks'][0]['observation']['initial']['box'][1:]}]),f'travel|movement|collider|{phase}|0|0')
 add('priority',lambda c:(c['input'].__setitem__('tick_mode',1),c['input'].__setitem__('yaw_f32_bits','7f800000'),c['ticks'][0]['observation']['initial']['position'].__setitem__(0,'7ff0000000000000')),'mode|1')
 return result

def main():
 p=argparse.ArgumentParser();p.add_argument('--skip-build',action='store_true');a=p.parse_args();fixture=json.loads(FIXTURE.read_text());provenance=verify_fixture_provenance(fixture);assert fixture['jump_cases_sha256']==hashlib.sha256(canonical(fixture['jump_cases'])).hexdigest();jars,_=verified_classpath();assert fixture['classpath_libraries']==[fingerprint(x) for x in jars[1:]];assert fixture['runtime_executable']==fingerprint(JAVA);checks=[]
 for src in ['src/player_tick.bend','tests/player_tick.bend']:
  checks.append(run([BEND,src,'--check-only']));checks.append(run([BEND,src,'--verdict']))
 builds=[]
 if not a.skip_build:builds=[run([BEND,'tests/player_tick.bend','-o','build/player-tick-tests.c']),run([BEND,'tests/player_tick.bend','-o',BINARY])]
 start=time.monotonic();batches=[];count=0;chains=0
 for c in fixture['cases']:
  for op in ['tick','prepare','chain']:
   args=[request(c,t,i,'tick' if op=='chain' and i==0 else op) for i,t in enumerate(c['ticks'])];r=run([BINARY,'--gpu','off',TABLE,*args]);lines=r['stdout'].splitlines();assert len(lines)==len(args)
   for i,(t,line) in enumerate(zip(c['ticks'],lines,strict=True)):
    id,result=parse(line);assert id==c['id']+':'+str(i)
    expected={'state':t['observation']['pre_travel'],'travel_input':t['observation']['travel_input']} if op=='prepare' else t['expected']
    assert result==expected,(id,op,expected,result)
   batches.append({'case':c['id'],'operation':op,'ticks':len(args),'seconds':r['seconds']})
   if op=='tick':count+=len(args)
   if op=='chain':chains+=len(args)
 validation=validation_cases(fixture['cases'][0]);rejections=[]
 for c,expected in validation:
  r=run([BINARY,'--gpu','off',TABLE,request(c,c['ticks'][0],0)]);id,result=parse(r['stdout'].strip());assert result==expected,(id,expected,result);rejections.append({'case':id,'error':expected['error']})
 # Failure leaves both the table and earlier native chain state usable.
 base=fixture['cases'][0]
 for c,expected in validation:
  args=[request(base,base['ticks'][0],0),request(c,c['ticks'][0],0),request(base,base['ticks'][1],1,'chain')]
  r=run([BINARY,'--gpu','off',TABLE,*args]);lines=r['stdout'].splitlines();assert len(lines)==3
  assert parse(lines[0])[1]==base['ticks'][0]['expected'];assert parse(lines[1])[1]==expected;assert parse(lines[2])[1]==base['ticks'][1]['expected']
 jump_requests=[]
 for c in fixture['jump_cases']:
  stub=copy.deepcopy(base);stub['id']=c['id'];stub['input'].update(c['input']);stub['input']['ticks']=[{}];t=stub['ticks'][0];o=t['observation'];o['initial'].update(c['observation']['initial']);o['initial']['needs_sync']=c['input']['needs_sync'];o['attributes']['jump_strength']=c['observation']['jump_strength'];o['attributes']['jump_factor_f32_bits']=c['observation']['jump_factor_f32_bits'];o['initial_shapes']=[];o['step_shapes']=[];jump_requests.append((request(stub,t,0,'jump'),c))
 for offset in range(0,len(jump_requests),60):
  chunk=jump_requests[offset:offset+60];r=run([BINARY,'--gpu','off',TABLE,*[arg for arg,c in chunk]]);lines=r['stdout'].splitlines();assert len(lines)==len(chunk)
  for (arg,c),line in zip(chunk,lines,strict=True):id,result=parse(line);assert id==c['id']+':0' and result==c['expected'],(id,c['expected'],result)
 malformed=[]
 for value in ['broken','broken;;','bad|tick|nope;;']:
  r=run([BINARY,'--gpu','off',TABLE,value],required=False);assert r['exit_code']==2 and 'invalid player tick' in r['stderr'];malformed.append({'exit_code':r['exit_code'],'stderr':r['stderr']})
 source=(ROOT/'src/player_tick.bend').read_text();assert not re.search(r'@unsafe|\bimport\s+["\']|\w!\(',source)
 sources=['src/player_tick.bend','tests/player_tick.bend','tools/reference_player_tick_probe.py','tools/test_player_tick.py','docs/PLAYER_TICK.md','src/f64.bend','src/locomotion.bend','src/movement.bend','src/travel.bend']
 e={'status':'passed','pin':'26.3','actual_player_ai_step_calls':count,'chained_native_ticks':chains,'pre_travel_comparisons':count,'direct_jump_factor_cases':len(jump_requests),'kernel_pass':True,'checks':checks,'builds':builds,'native_batches':batches,'native_validation_seconds':round(time.monotonic()-start,6),'reference':fingerprint(FIXTURE),'fixture_provenance':provenance,'binary':fingerprint(BINARY),'emitted_c':fingerprint(ROOT/'build/player-tick-tests.c'),'sources_sha256':{s:sha(ROOT/s) for s in sources if (ROOT/s).exists()},'laws':re.findall(r'^law (\w+):',source,re.M),'explicit_rejection_cases':len(validation),'successful_owner_and_prior_state_retention_followups':len(validation),'rejections':rejections,'malformed_protocol':malformed,'confidence':fixture['confidence'],'oracle_scope':fixture['scope']}
 (ROOT/'evidence/player-tick-verification.json').write_text(json.dumps(e,indent=2,sort_keys=True)+'\n');print(json.dumps({k:e[k] for k in ['status','actual_player_ai_step_calls','chained_native_ticks','pre_travel_comparisons','kernel_pass','native_validation_seconds']},indent=2))
if __name__=='__main__':main()
