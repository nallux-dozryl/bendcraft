#!/usr/bin/env python3
"""Pure support cache/raw helper comparisons against direct pinned Java observations."""
from __future__ import annotations
import argparse,copy,hashlib,json,pathlib,re,time
from test_geometry import run,word_vector,sha
from reference_inventory import fingerprint
from reference_support_probe import validate,verify,MOVE_GATE_SOURCE,move_gate_launcher_source
ROOT=pathlib.Path(__file__).resolve().parents[1]
BEND=pathlib.Path('/Users/chuah/.bend/bin/bend');BINARY=ROOT/'build/support-tests';FIXTURE=ROOT/'reference/support.json'
ZERO=['0000000000000000']*3

def coords(p):return [str(v&0xffffffff) for v in p]
def cache_words(c):return [str(int(c['main'] is not None)),*coords(c['main'] or [0,0,0]),str(int(c['on_ground_no_blocks']))]
def movement_words(v):return [str(int(v is not None)),*word_vector(v or ZERO)]
def candidate_words(candidates):return '|'.join(v for c in candidates for v in coords(c['position']))
def request(id,op,fields,primary=(),fallback=()):return ';'.join(['|'.join([id,op,*map(str,fields)]),candidate_words(primary),candidate_words(fallback)])
def signed(v):v=int(v);return v if v<2**31 else v-2**32
def optional(f):assert len(f)==4;return [signed(v) for v in f[1:]] if int(f[0]) else None
def values(f):assert len(f)%2==0;return [f'{int(f[i]):08x}{int(f[i+1]):08x}' for i in range(0,len(f),2)]
def parse(line):
 id,kind,*f=line.split('|')
 if kind=='error':return id,{'error':'|'.join(f)}
 if kind=='state':assert len(f)==5;return id,{'main':optional(f[:4]),'on_ground_no_blocks':bool(int(f[4]))}
 if kind=='selection':return id,optional(f)
 if kind=='block':assert len(f)==3;return id,[signed(v) for v in f]
 if kind=='word':assert len(f)==1;return id,f'{int(f[0]):08x}'
 if kind=='f64':assert len(f)==2;return id,values(f)[0]
 assert kind=='queries' and len(f) in [13,25],(kind,len(f))
 return id,{'primary':values(f[:12]),'fallback':values(f[13:]) if int(f[12]) else None}

def update_request(c,i,op):
 o=c['steps'][i]['observation'];u=c['input']['steps'][i];queries=o['queries']
 return request(c['id']+':'+str(i),op,[*word_vector(o['position']),*word_vector(o['box']),*cache_words(o['initial_cache']),str(int(u['grounded'])),*movement_words(u['movement'])],queries[0]['candidates'] if queries else [],queries[1]['candidates'] if len(queries)>1 else [])

def sample_request(id,o,cache,offset,op='on_pos'):
 return request(id,op,[*word_vector(o['position']),*cache_words(cache),int(offset,16)])

def run_pairs(pairs,batches,batch_size=70):
 for start in range(0,len(pairs),batch_size):
  chunk=pairs[start:start+batch_size];r=run([BINARY,'--gpu','off',*[x[0] for x in chunk]]);lines=r['stdout'].splitlines();assert len(lines)==len(chunk),(len(lines),len(chunk),r)
  for (arg,expected),line in zip(chunk,lines,strict=True):
   id,actual=parse(line)
   compared={'primary':actual['primary']} if isinstance(expected,dict) and set(expected)=={'primary'} and isinstance(actual,dict) and 'primary' in actual else actual
   assert id==arg.split('|')[0] and compared==expected,(id,expected,actual)
  batches.append({'requests':len(chunk),'seconds':r['seconds']})

def validation_requests(c):
 result=[];o=c['steps'][0]['observation'];u=c['input']['steps'][0]
 pos=o['position'];box=o['box'];cache=o['initial_cache'];movement=u['movement'] or ZERO
 for i in range(3):
  p=pos.copy();p[i]='7ff8000000000123';result.append((request('rejected:position:'+str(i),'update',[*word_vector(p),*word_vector(box),*cache_words(cache),1,*movement_words(movement)]),{'error':'position|'+str(i)}))
 for i in range(6):
  b=box.copy();b[i]='7ff0000000000000';result.append((request('rejected:box:'+str(i),'update',[*word_vector(pos),*word_vector(b),*cache_words(cache),1,*movement_words(movement)]),{'error':'box|'+str(i)}))
 for i in range(3):
  v=movement.copy();v[i]='fff0000000000000';result.append((request('rejected:movement:'+str(i),'update',[*word_vector(pos),*word_vector(box),*cache_words(cache),1,*movement_words(v)]),{'error':'movement|'+str(i)}))
 for i in range(3):
  b=box.copy();b[i],b[i+3]=b[i+3],b[i];result.append((request('rejected:order:'+str(i),'update',[*word_vector(pos),*word_vector(b),*cache_words(cache),1,*movement_words(movement)]),{'error':'order|'+str(i)}))
 for raw in ['7f800000','ff800000','7fc01234']:
  result.append((sample_request('rejected:offset:'+raw,o,cache,raw),{'error':'offset'}))
 b=box.copy();b[0]=b[3]='7fefffffffffffff'
 result.append((request('rejected:computed-query-overflow','queries',[*word_vector(b),*movement_words(['ffefffffffffffff',ZERO[1],ZERO[2]])]),{'error':'box|0'}))
 return result

def completed_record(name):
 record=json.loads((ROOT/'evidence'/name).read_text())
 assert record['status']=='passed' and record['exit_code']==0 and record['source_hashes_unchanged'],name
 assert all(sha(ROOT/path)==expected for path,expected in record['source_sha256'].items()),name
 return record

def main():
 p=argparse.ArgumentParser();p.add_argument('--skip-build',action='store_true');p.add_argument('--skip-checks',action='store_true',help='Native-only follow-up; evidence remains explicit that checks were skipped');p.add_argument('--reuse-checked',action='store_true',help='Reuse completed bounded build/kernel records only when every recorded source hash still matches');a=p.parse_args();data=json.loads(FIXTURE.read_text());validate(data);provenance=verify();checks=[]
 if not a.skip_checks:
  for src in ['src/support.bend','tests/support.bend']:
   checks.append(run([BEND,src,'--check-only']));checks.append(run([BEND,src,'--verdict']))
 builds=[]
 if not a.skip_build:builds=[run([BEND,'tests/support.bend','-o','build/support-tests.c']),run([BEND,'tests/support.bend','-o',BINARY])]
 if a.reuse_checked:
  assert a.skip_build and a.skip_checks,'Reuse requires both skip flags; it never silently disables checks'
  checks=[completed_record('support-kernel-final.json')];builds=[completed_record('support-build-final.json')]
 start=time.monotonic();batches=[];transitions=0;histories=0;queries=[];helpers=[];samples=[];jump=[];move_pairs=[]
 for c in data['cases']:
  for chain in [False,True]:
   pairs=[(update_request(c,i,'chain' if chain and i else 'update'),s['expected']['cache']) for i,s in enumerate(c['steps'])]
   # Histories execute in one process and carry prior cache on each chained call.
   run_pairs(pairs,batches,batch_size=len(pairs));transitions+=len(pairs) if not chain else 0
  histories+=1
  for i,s in enumerate(c['steps']):
   o=s['observation'];u=c['input']['steps'][i];expected=s['expected'];qs=o['queries']
   if qs:
    q=request(c['id']+':query:'+str(i),'queries',[*word_vector(o['box']),*movement_words(u['movement'])]);want={'primary':qs[0]['box']}
    # Compare both raw boxes when Java queried a fallback; otherwise only the observed primary.
    if len(qs)>1 or u['movement'] is None:want['fallback']=qs[1]['box'] if len(qs)>1 else None
    queries.append((q,want))
   for j,q in enumerate(qs):
    queries.append((request(c['id']+':selection:'+str(i)+':'+str(j),'select',[*word_vector(q['entity_position']),*word_vector(q['box'])],q['candidates']),q['selected']))
    # Far signed-int boundary cubes must be filtered before distance selection.
    extra=q['candidates']+[{'position':[2147483647,2147483647,2147483647]},{'position':[-2147483648,-2147483648,-2147483648]}]
    queries.append((request(c['id']+':selection-extra:'+str(i)+':'+str(j),'select',[*word_vector(q['entity_position']),*word_vector(q['box'])],extra),q['selected']))
    for k,v in enumerate(q['candidates']):
     helpers.append((request(c['id']+':candidate:'+str(i)+':'+str(j)+':'+str(k),'distance',[*coords(v['position']),*word_vector(q['entity_position'])]),v['distance']))
   for label,offset in [('on_pos','3727c5ac'),('legacy','3e4ccccd'),('below','3f000011')]:
    samples.append((sample_request(c['id']+':'+label+':'+str(i),o,expected['cache'],offset),expected['samples'][label]))
   for j,x in enumerate(expected['samples']['offsets']):samples.append((sample_request(c['id']+':offset:'+str(i)+':'+str(j),o,expected['cache'],x['offset_f32_bits']),x['position']))
   if 'current_jump_factor_f32_bits' in o:
    jump.append((request(c['id']+':factor:'+str(i),'jump',[int(o['current_jump_factor_f32_bits'],16),int(o['below_jump_factor_f32_bits'],16)]),expected['samples']['jump_factor_f32_bits']))
 for c in data['comparisons']:helpers.append((request(c['id'],'compare',[*coords(c['input']['left']),*coords(c['input']['right'])]),c['expected']['compare_i32_bits']))
 for c in data['distances']:helpers.append((request(c['id'],'distance',[*coords(c['input']['block']),*word_vector(c['input']['position'])]),c['expected']['distance']))
 for c in data['on_pos']:
  v=c['input'];samples.append((sample_request(c['id'],v,v['cache'],v['offset_f32_bits'],'on_pos' if c['observation']['finite_offset'] else 'on_pos_raw'),c['expected']['position']))
 for c in data['jump_factors']:
  o=c['observation'];jump.append((request(c['id'],'jump',[int(o['current_jump_factor_f32_bits'],16),int(o['below_jump_factor_f32_bits'],16)]),c['expected']['jump_factor_f32_bits']))
 gate_path=ROOT/'evidence/support-move-gate-reference.json'
 if gate_path.exists():
  gate=json.loads(gate_path.read_text());assert gate['status']=='passed' and gate['pin']=='26.3'
  assert hashlib.sha256(json.dumps(gate['cases'],sort_keys=True,separators=(',',':'),ensure_ascii=False).encode()).hexdigest()==gate['cases_sha256']
  assert gate['frozen_reference']==fingerprint(FIXTURE)
  assert all(gate[k]==data[k] for k in ['server_bundle_sha256','server_class_jar_sha256','runtime_executable','classpath_libraries','source'])
  assert gate['fixture_source_sha256']['move_gate']==hashlib.sha256(MOVE_GATE_SOURCE.encode()).hexdigest()
  assert gate['fixture_source_sha256']['move_gate_compilation_unit']==hashlib.sha256(move_gate_launcher_source().encode()).hexdigest()
  for c in gate['cases']:
   o=c['observation'];body=c['expected']['body'];calls=o['support_calls'];qs=o['support_queries']
   assert o['actual_player_move'] and len(calls)==1;call=calls[0]
   move_pairs.append((request(c['id'],'update',[*word_vector(body['position']),*word_vector(body['box']),*cache_words(c['before']['cache']),int(call['grounded']),*movement_words(call['movement'])],qs[0]['candidates'] if qs else [],qs[1]['candidates'] if len(qs)>1 else []),c['expected']['cache']))
  assert any(not c['observation']['movement_recorded'] and c['observation']['support_calls'] for c in gate['cases'])
 run_pairs(queries+helpers+samples+jump,batches)
 run_pairs(move_pairs,batches)
 rejected=validation_requests(data['cases'][0]);run_pairs(rejected,batches)
 # Every rejection is followed by a successful continuation of prior native cache.
 base=next(c for c in data['cases'] if len(c['steps'])>1)
 for arg,expected in rejected:
  run_pairs([(update_request(base,0,'update'),base['steps'][0]['expected']['cache']),(arg,expected),(update_request(base,1,'chain'),base['steps'][1]['expected']['cache'])],batches)
 malformed=[]
 for arg in ['broken','bad;;','bad|compare|abc;;','bad|compare|0|0|0|0|0|0;1;']:
  r=run([BINARY,'--gpu','off',arg],required=False);assert r['exit_code']==2 and 'invalid support' in r['stderr'];malformed.append({'exit_code':r['exit_code'],'stderr':r['stderr']})
 source=(ROOT/'src/support.bend').read_text();assert not re.search(r'@unsafe|\bimport\s+["\']|\w!\(',source)
 sources=['src/support.bend','tests/support.bend','tools/reference_support_probe.py','tools/test_support.py','docs/SUPPORT.md','src/f64.bend','src/geometry.bend','src/movement.bend','src/travel.bend']
 e={'status':'native_passed_checks_skipped' if a.skip_checks and not a.reuse_checked else 'passed','pin':'26.3','kernel_pass':not a.skip_checks or a.reuse_checked,'checks_reused_with_exact_source_hashes':a.reuse_checked,'actual_support_histories':histories,'actual_cache_transitions':transitions,'chained_native_cache_transitions':transitions,'query_and_selection_comparisons':len(queries),'raw_distance_and_signed_compare_comparisons':len(helpers),'sample_position_comparisons':len(samples),'jump_factor_comparisons':len(jump),'explicit_rejection_cases':len(rejected),'prior_cache_retention_followups':len(rejected),'malformed_protocol':malformed,'checks':checks,'builds':builds,'native_batches':batches,'native_validation_seconds':round(time.monotonic()-start,6),'fixture':fingerprint(FIXTURE),'fixture_observations_sha256':data['observations_sha256'],'fixture_provenance':provenance,'binary':fingerprint(BINARY),'emitted_c':fingerprint(ROOT/'build/support-tests.c') if (ROOT/'build/support-tests.c').exists() else None,'sources_sha256':{s:sha(ROOT/s) for s in sources if (ROOT/s).exists()},'laws':re.findall(r'^law (\w+):',source,re.M),'scope':data['scope'],'confidence':data['confidence']}
 e['actual_move_support_comparisons']=len(move_pairs);e['actual_move_reference']=fingerprint(gate_path) if gate_path.exists() else None
 (ROOT/'evidence/support-verification.json').write_text(json.dumps(e,indent=2,sort_keys=True)+'\n');print(json.dumps({k:e[k] for k in ['status','actual_support_histories','actual_cache_transitions','chained_native_cache_transitions','query_and_selection_comparisons','sample_position_comparisons','explicit_rejection_cases','kernel_pass','native_validation_seconds']},indent=2))
if __name__=='__main__':main()
