#!/usr/bin/env python3
"""Compare owned Bend world reads/backoff with direct actual Java observations.

Python serializes inputs and compares actual trace fields. It computes no
collision Boolean, backoff decrement, world scan order or shape intersection.
"""
from __future__ import annotations
import argparse, copy, hashlib, json, os, signal, struct, subprocess, sys, time
from pathlib import Path
from build_native import Snapshot, source_graph
from reference_inventory import fingerprint
from test_geometry import sha, word_vector

ROOT=Path(__file__).resolve().parents[1]
BEND=Path('/Users/chuah/.bend/bin/bend')
BINARY=ROOT/'build/local-collision-world-tests'
FIXTURE=ROOT/'reference/local_collision_world.json'
WORK=ROOT/'build/local-collision-world-verification'
NAMES=['minecraft:air','minecraft:stone','minecraft:dirt','minecraft:oak_planks']
INTERIOR=[-64.,-64.,-64.,64.,64.,64.]

def save(path,value):
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text(json.dumps(value,sort_keys=True,indent=2)+'\n')

def generation():
    s=Snapshot();source_graph(ROOT/'tests/local_collision_world.bend',
      (BEND.resolve().parent.parent/'bend2/base.bend').resolve(),dict(os.environ),s)
    return {p['path']:p['sha256'] for p in s.manifest()}

def tool_pins():
    return {p:fingerprint(ROOT/p) for p in ['tools/test_local_collision_world.py',
      'tools/reference_local_collision_world_probe.py','tools/reference_local_collision_probe.py',
      'tools/reference_local_input_probe.py','tools/reference_inventory.py','tools/build_native.py']}

def bounded(kind,timeout):
    before=generation();tools_before=tool_pins();reference=fingerprint(FIXTURE)
    native_receipt=ROOT/'evidence/local-collision-world-native-build.json'
    argv=([sys.executable,str(ROOT/'tools/build_native.py'),'tests/local_collision_world.bend',
      '-o',str(BINARY),'--cache-dir',str(ROOT/'build/local-collision-world-cache'),
      '--report',str(native_receipt)] if kind=='build'
      else [str(BEND),'tests/local_collision_world.bend','--check-only' if kind=='ordinary' else '--verdict'])
    started=time.monotonic();p=subprocess.Popen(argv,cwd=ROOT,stdout=subprocess.PIPE,
      stderr=subprocess.PIPE,text=True,start_new_session=True)
    print(json.dumps({'job':kind,'pid':p.pid,'timeout_seconds':timeout}),flush=True)
    timed_out=False;samples=[]
    while True:
        remaining=timeout-(time.monotonic()-started)
        if remaining<=0:
            timed_out=True
            try:os.killpg(p.pid,signal.SIGTERM)
            except ProcessLookupError:pass
            try:out,err=p.communicate(timeout=5)
            except subprocess.TimeoutExpired:os.killpg(p.pid,signal.SIGKILL);out,err=p.communicate()
            break
        try:out,err=p.communicate(timeout=min(5,remaining));break
        except subprocess.TimeoutExpired:
            rows=subprocess.run(['ps','-ax','-o','pid=,pgid=,rss=,vsz=,etime='],capture_output=True,text=True,check=True).stdout
            group=[]
            for line in rows.splitlines():
                f=line.split()
                if len(f)==5 and int(f[1])==p.pid:
                    group.append({'pid':int(f[0]),'rss_kib':int(f[2]),'virtual_kib':int(f[3]),'elapsed':f[4]})
            samples.append({'seconds':round(time.monotonic()-started,6),'processes':group})
    record={'schema_version':1,'status':'passed' if p.returncode==0 and not timed_out else 'inconclusive' if timed_out else 'failed',
      'command':argv,'pid':p.pid,'exit_code':p.returncode,'seconds':round(time.monotonic()-started,6),
      'timeout_seconds':timeout,'timed_out':timed_out,'stdout':out,'stderr':err,
      'memory_samples':samples,'memory_scope':'Process-group RSS/virtual sizes sampled each 5 s; not physical footprint or gameplay benchmark',
      'generation':before,'generation_unchanged':before==generation(),
      'tools':tools_before,'tools_unchanged':tools_before==tool_pins(),
      'reference':reference,'reference_unchanged':reference==fingerprint(FIXTURE),
      'compiler':fingerprint(BEND)}
    if kind=='build' and record['status']=='passed':
        record['native_build']=json.loads(native_receipt.read_text());record['binary']=fingerprint(BINARY)
        assert record['native_build']['binary_sha256']==record['binary']['sha256']
    save(ROOT/f'evidence/local-collision-world-{kind}-final.json',record)
    assert record['status']=='passed' and record['generation_unchanged'] and record['tools_unchanged'] and record['reference_unchanged'],record
    return record

def completed(kind):
    r=json.loads((ROOT/f'evidence/local-collision-world-{kind}-final.json').read_text())
    assert r['status']=='passed' and r['exit_code']==0 and r['generation_unchanged'] and r['tools_unchanged'] and r['reference_unchanged']
    assert r['generation']==generation() and r['tools']==tool_pins() and r['reference']==fingerprint(FIXTURE)
    if kind=='build':assert r['binary']==fingerprint(BINARY)
    return r

def bits(v):return struct.pack('>d',v).hex()
def words(raw):return [int(v) for v in word_vector(raw)]
def mask(keys):return sum(int(v)<<i for i,v in enumerate(keys))
def body_words(state):
    return words(state['position']+state['box']+state['velocity'])+[
      int(state['width_f32_bits'],16),int(state['height_f32_bits'],16),*map(int,state['body_flags'])]

def request(case,id=None,install=True,context_changes=None,environment_changes=None,interior=INTERIOR):
    s=case['before'];context=[int(s['maximum_f32_bits'],16),*words([s['fall_distance_f64_bits']]),
      int(s['flying']),mask(s['key_presses']),{'SELF':0,'PLAYER':1}.get(case['mover'],2),0,len(case['queries'])+1]
    environment=[0,0,*words([bits(v) for v in interior])]
    for i,v in (context_changes or {}).items():context[i]=v
    for i,v in (environment_changes or {}).items():environment[i]=v
    group=lambda vs:'|'.join(str(v&0xffffffff) for v in vs)
    return ';'.join([(id or case['id'])+'|backoff|'+str(int(install)),group(body_words(s)),
      group(context),group(words(case['movement'])),group(environment)])

def edits(case):
    kinds={'air':0,'stone':1,'dirt':2,'oak_planks':3}
    return ['|'.join(str(v&0xffffffff) if isinstance(v,int) else v for v in
      ['edit:'+str(i),'edit',*w['position'],kinds[w['block']]]) for i,w in enumerate(case['initial']['world_writes'])]

def lines(text):
    result={};queries={}
    for line in text.splitlines():
        f=line.split('|');assert len(f)>=2,line
        if f[1]=='query':queries.setdefault(f[0],[]).append(f)
        else:assert (f[0],f[1]) not in result;result[f[0],f[1]]=f[2:]
    return result,queries

def raw64(values):
    assert len(values)%2==0
    return [f'{int(values[i]):08x}{int(values[i+1]):08x}' for i in range(0,len(values),2)]

def retained(parsed,id):
    for kind in ['body','clock','view','queue']:assert parsed[id+'-before',kind]==parsed[id+'-after',kind],(id,kind)

def palette(parsed,id):
    p=list(map(int,parsed[id+'-before','view'][2].split(',')));assert len(p)==4
    return dict(zip(NAMES,p,strict=True))

def compare(case,parsed,queries,id=None):
    id=id or case['id'];retained(parsed,id)
    assert raw64(parsed[id,'corrected'])==case['expected']['movement'],id
    actual=queries.get(id,[]);assert len(actual)==len(case['queries']),(id,len(actual),len(case['queries']))
    ids=palette(parsed,id)
    for observed,expected in zip(actual,case['queries'],strict=True):
        assert int(observed[2])==expected['index'] and raw64(observed[3:15])==expected['box'],(id,expected['index'],'box')
        assert bool(int(observed[15]))==expected['no_collision'],(id,expected['index'],'bool')
        first=expected['first_yielded_shape_boxes']
        if first is None:assert observed[16]=='none'
        else:assert len(first)==1 and raw64(observed[16:28])==first[0]
        serialized=observed[17] if first is None else observed[28]
        reads=[list(map(int,r.split(','))) for r in serialized.split(';') if r]
        expected_reads=[[*[v&0xffffffff for v in r['position']],ids[r['block_id']]] for r in expected['reads']]
        assert reads==expected_reads,(id,expected['index'],'ordered Core reads',reads[:6],expected_reads[:6])
    return {'id':id,'queries':len(actual),'reads':sum(len(q['reads']) for q in case['queries']),
      'first_yields':sum(q['first_yielded_shape_boxes'] is not None for q in case['queries'])}

def native(commands,label,env=None):
    started=time.monotonic();p=subprocess.run([str(BINARY),'--gpu','off',*commands],cwd=ROOT,
      env=env,text=True,capture_output=True,timeout=120)
    WORK.mkdir(parents=True,exist_ok=True);raw=WORK/(label+'.stdout');raw.write_text(p.stdout)
    (WORK/(label+'.stderr')).write_text(p.stderr)
    receipt={'label':label,'exit_code':p.returncode,'seconds':round(time.monotonic()-started,6),
      'stdout_sha256':sha(raw),'stderr_sha256':hashlib.sha256(p.stderr.encode()).hexdigest(),
      'command_inputs_sha256':hashlib.sha256(json.dumps(commands,separators=(',',':')).encode()).hexdigest()}
    assert p.returncode==0,(receipt,p.stderr[-3000:])
    return *lines(p.stdout),receipt

def validate_cases(data):
    receipts=[];compared=[];rejected=[]
    for index,c in enumerate(data['cases']):
        parsed,queries,r=native([*edits(c),'warm|warm',request(c)],'case-'+str(index));receipts.append(r)
        retained(parsed,c['id'])
        if c['admission']['neutral_helper_context']:compared.append(compare(c,parsed,queries))
        else:
            assert parsed[c['id'],'error']==['edge-hook-rejected'] and not queries.get(c['id'])
            rejected.append({'id':c['id'],'error':'edge-hook-rejected','scope':'Measured actual guard context outside checked hook admission'})
    return receipts,compared,rejected

def validate_policy(data):
    base=next(c for c in data['cases'] if c['admission']['neutral_helper_context'] and c['queries'])
    cases=[];receipts=[]
    def test(label,commands,expected):
        parsed,queries,r=native([request(base,id='initial'),*commands,request(base,id='recovered')],label)
        retained(parsed,label);assert parsed[label,'error'][0].startswith(expected),(label,parsed.get((label,'error')))
        compare(base,parsed,queries,'recovered');receipts.append(r)
        cases.append({'id':label,'error':parsed[label,'error'][0],'same_owner_recovery':True})
    changed=copy.deepcopy(base);changed['before']['velocity'][0]='8000000000000000'
    test('signed-zero-body-mismatch',[request(changed,id='signed-zero-body-mismatch',install=False)],'edge-body-mismatch')
    for label,change,error in [('unknown-entities',{0:1},'edge-entities-unresolved'),('unknown-border',{1:1},'edge-border-unresolved')]:
        test(label,[request(base,id=label,environment_changes=change)],error)
    test('outside-interior',[request(base,id='outside-interior',interior=[0.,0.,0.,1.,1.,1.])],'edge-query-outside-interior')
    test('invalid-interior',[request(base,id='invalid-interior',environment_changes={2:0x7ff80000,3:0})],'edge-invalid-interior')
    test('budget',[request(base,id='budget',context_changes={7:0})],'edge-query-budget')
    for label,op,error in [('absent-palette','no-palette','edge-palette-unavailable'),('stale-palette','stale-palette','edge-palette-stale')]:
        test(label,[label+'-setup|'+op,request(base,id=label),'restore|palette-refresh'],error)
    point=base['queries'][0]['reads'][0]['position'];edit=lambda id,kind:'|'.join(map(str,[id,'edit',*[v&0xffffffff for v in point],kind]))
    original=base['queries'][0]['reads'][0]['block_id'];kind=NAMES.index(original)
    test('unknown-state',[edit('unknown-write',4),request(base,id='unknown-state'),edit('repair',kind)],'unsupported-block-state:')
    missing=copy.deepcopy(base);missing['before']['position'][0]=bits(32.5)
    missing['before']['box'][0]=bits(32.2);missing['before']['box'][3]=bits(32.8)
    test('missing-section',[request(missing,id='missing-section')],'missing-section:')
    for mode in range(1,7):test('mode-'+str(mode),[request(base,id='mode-'+str(mode),context_changes={6:mode})],'edge-hook-rejected')
    p,q,r=native(['clock|clock','running|running','pending|pending',request(base,id='running-pending')],'running-pending')
    compare(base,p,q,'running-pending');assert p['running-pending-before','clock'][2]=='0' and p['running-pending-before','clock'][5]=='1' and p['running-pending-before','clock'][1]=='777' and p['running-pending-before','clock'][3]=='0';assert p['running-pending-before','queue'][0]=='100,9,0,time,999;';receipts.append(r)
    return cases,receipts

def validate_remap(data):
    path=WORK/'remapped.tsv';path.parent.mkdir(parents=True,exist_ok=True)
    names=['minecraft:oak_planks','minecraft:stone','minecraft:air','minecraft:dirt']
    path.write_text('block_protocol_id\tidentifier\tfirst_state_id\tstate_count\tdefault_state_id\tordered_properties_json\n'+''.join(f'{i}\t{name}\t{i}\t1\t{i}\t[]\n' for i,name in enumerate(names)))
    env=dict(os.environ);env['MC_BLOCK_REGISTRY']=str(path);results=[]
    for id in ['world:all_stone','world:all_dirt','world:all_planks','world:mixed_edge']:
        c=next(c for c in data['cases'] if c['id']==id)
        p,q,r=native([*edits(c),'warm|warm',request(c)],'remapped-'+id.replace(':','-'),env)
        results.append({**compare(c,p,q),**r});assert palette(p,c['id'])==dict(zip(NAMES,[2,1,3,0],strict=True))
    return {'table':fingerprint(path),'cases':results,'comparison':'Actual returned Java state identifiers translated through dynamically read native palette; no fixed numeric IDs'}

def compact_existing():
    """Formatting only: preserve full receipts and audit compact projections."""
    import ast, re
    raw_dir=ROOT/'build/local-collision-world';raw_dir.mkdir(parents=True,exist_ok=True)
    def pin(path):return {'path':str(path.relative_to(ROOT)),**fingerprint(path)}
    def canonical_sha(value):return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':')).encode()).hexdigest()
    def text_summary(value):return {'bytes':len(value.encode()),'sha256':hashlib.sha256(value.encode()).hexdigest()}
    def original(suffix):
        tracked=ROOT/f'evidence/local-collision-world-{suffix}.json';raw=raw_dir/(tracked.stem+'.original.json')
        if not raw.exists():raw.write_bytes(tracked.read_bytes())
        else:
            current=json.loads(tracked.read_text())
            if 'full_original' in current:assert current['full_original']==pin(raw),suffix
            else:assert tracked.read_bytes()==raw.read_bytes(),suffix
        value=json.loads(raw.read_text());return tracked,raw,value
    originals={s:original(s) for s in ['build-final','native-build','native-verification','reporting-split','native-closure','verification','handoff']}
    old_build=originals['build-final'][2];old_native=originals['native-build'][2];old_results=originals['native-verification'][2]
    old_split=originals['reporting-split'][2];old_closure=originals['native-closure'][2]
    assert old_build['native_build']==old_native
    dependency_summary={'count':len(old_native['dependencies']),'canonical_sha256':canonical_sha(old_native['dependencies']),'original_field':'dependencies'}
    assert dependency_summary['count']==1650 and dependency_summary['canonical_sha256']==old_closure['native_manifest_sha256']
    def base(suffix):
        value=copy.deepcopy(originals[suffix][2]);value['evidence_format']='local-collision-world-compact-v1'
        value['full_original']=pin(originals[suffix][1]);value['canonical_original_json_sha256']=canonical_sha(originals[suffix][2]);return value
    compact_native=base('native-build');compact_native['dependencies']=dependency_summary
    compact_native['compiler']['driver_probe']=text_summary(old_native['compiler']['driver_probe'])
    save(originals['native-build'][0],compact_native)
    compact_build=base('build-final');compact_build['native_build']={'receipt':pin(originals['native-build'][0]),'full_original':pin(originals['native-build'][1]),'dependencies':dependency_summary}
    for stream in ['stdout','stderr']:compact_build[stream]=text_summary(old_build[stream])
    save(originals['build-final'][0],compact_build)
    raw_receipts=old_results['native_receipts']+[c for c in old_results['dynamic_remap']['cases']]
    assert len(raw_receipts)==127 and len({r['label'] for r in raw_receipts})==127
    for receipt in raw_receipts:
        stdout=ROOT/receipt['stdout'];stderr=stdout.with_suffix('.stderr')
        assert sha(stdout)==receipt['stdout_sha256'] and sha(stderr)==receipt['stderr_sha256']
    compact_results=base('native-verification')
    compact_results['native_receipts']={'count':127,'canonical_sha256':canonical_sha(raw_receipts),'full_original':pin(originals['native-verification'][1]),'original_fields':['native_receipts','dynamic_remap.cases'],'raw_stdout_stderr_pairs_rechecked':True}
    compact_results['ordinary']={'receipt':pin(ROOT/'evidence/local-collision-world-ordinary-final.json'),'status':old_results['ordinary']['status'],'seconds':old_results['ordinary']['seconds']}
    compact_results['dynamic_remap']['cases']=[{k:c[k] for k in ['id','queries','reads','first_yields']} for c in old_results['dynamic_remap']['cases']]
    compact_results['build_receipt']=pin(originals['build-final'][0])
    save(originals['native-verification'][0],compact_results)
    # Compare actual summary fields, not gameplay algorithms or inferred outputs.
    exact_summary_keys=['native_cases','measured_rejections','policy_rejections','native_query_count','native_read_count','native_first_yields','same_owner_recoveries','all_body_view_cache_clock_queue_fields_retained','retained_running_clock_pending_case','native_status','kernel_status','scope','generation','tools','reference','binary','receipt_recovery']
    assert all(compact_results[k]==old_results[k] for k in exact_summary_keys)
    remap_summary={'table':old_results['dynamic_remap']['table'],'comparison':old_results['dynamic_remap']['comparison'],'cases':[{k:c[k] for k in ['id','queries','reads','first_yields']} for c in old_results['dynamic_remap']['cases']]}
    assert compact_results['dynamic_remap']==remap_summary
    assert len(compact_results['native_cases'])==102 and len(compact_results['measured_rejections'])==4 and len(compact_results['policy_rejections'])==16
    expected_summary={k:old_results[k] for k in exact_summary_keys}
    current_path=ROOT/'tools/test_local_collision_world.py';executed_path=ROOT/old_split['executed_runner']['path']
    def functions(tree):return {n.name:ast.dump(n,include_attributes=False) for n in tree.body if isinstance(n,(ast.FunctionDef,ast.AsyncFunctionDef))}
    old_tree=ast.parse(executed_path.read_text());current_tree=ast.parse(current_path.read_text());old_fn=functions(old_tree);new_fn=functions(current_tree)
    assert {k:hashlib.sha256(v.encode()).hexdigest() for k,v in old_fn.items() if k!='main'}==old_split['unchanged_function_ast_sha256']
    assert all(old_fn[k]==new_fn[k] for k in old_fn if k!='main')
    nonfunctions=lambda tree:[ast.dump(v,include_attributes=False) for v in tree.body if not isinstance(v,(ast.FunctionDef,ast.AsyncFunctionDef))]
    assert nonfunctions(old_tree)==nonfunctions(current_tree)
    assert set(new_fn)-set(old_fn)=={'compact_existing'}
    split=copy.deepcopy(old_split);split['current_runner']=pin(current_path);split['full_original']=pin(originals['reporting-split'][1])
    split['new_reporting_only_helpers']=['compact_existing'];split['formatting_native_helpers_unchanged']=True
    split['sealed_original_receipts']=[]
    for sealed in old_split['sealed_original_receipts']:
        prior_path=ROOT/sealed['path'];suffix=prior_path.stem.removeprefix('local-collision-world-')
        actual=originals[suffix][1] if suffix in originals else prior_path
        got=pin(actual);assert got['bytes']==sealed['bytes'] and got['sha256']==sealed['sha256']
        split['sealed_original_receipts'].append({**got,'original_tracked_path':sealed['path']})
    save(originals['reporting-split'][0],split)
    closure=copy.deepcopy(old_closure);closure['full_original']=pin(originals['native-closure'][1])
    closure['build_receipt']=pin(originals['build-final'][0]);closure['native_verification']=pin(originals['native-verification'][0]);closure['reporting_split']=pin(originals['reporting-split'][0])
    closure['full_original_build_receipt']=pin(originals['build-final'][1]);closure['full_original_native_build_receipt']=pin(originals['native-build'][1]);closure['full_original_native_verification']=pin(originals['native-verification'][1])
    closure['report_formatting_only']='Full JSON originals preserved byte-for-byte; no source/oracle/native/helper/expected/build/kernel change or rerun.'
    save(originals['native-closure'][0],closure)
    docs=ROOT/'docs/LOCAL_COLLISION_WORLD.md';text=re.sub(r'(Current runner SHA-256 is\n`)[0-9a-f]{64}(`)',lambda m:m[1]+pin(current_path)['sha256']+m[2],docs.read_text())
    heading='## Receipt storage compaction'
    if heading not in text:
        text+='\n'+heading+'\n\nThe duplicated full build/native dependency manifests and repetitive per-run\nreceipt metadata are compact tracked summaries. Exact original JSON bytes stay\nunder ignored `build/local-collision-world/`, linked by size and SHA-256. The\n1,650-row native manifest retains its canonical digest/count. The 127 raw native\nstdout/stderr pairs remain unchanged, and all actual case/guard/recovery/remap\nsummary fields are equivalent to the full original native result.\n`evidence/local-collision-world-storage.json` records storage and equivalence.\n\nReproduce only formatting and its read-only audit with:\n\n```sh\nPYTHONDONTWRITEBYTECODE=1 python3 tools/test_local_collision_world.py --compact-existing\n```\n\nThis command performs no Java, Bend, native or kernel execution. The only new\nhelper is report formatting; all 20 executed helpers and nonfunction ASTs remain\nidentical. The original executed runner hash and kernel failure are retained.\nThe preflight C is still distinguished from the native CLI internal temporary C.\n'
    docs.write_text(text)
    final=copy.deepcopy(originals['verification'][2]);final['full_original']=pin(originals['verification'][1])
    for key,suffix in [('native_verification','native-verification'),('native_closure','native-closure'),('build_receipt','build-final'),('reporting_split','reporting-split')]:final[key]=pin(originals[suffix][0])
    final['docs']={'path':str(docs.relative_to(ROOT)),'sha256':sha(docs)}
    save(originals['verification'][0],final)
    storage={'schema_version':1,'status':'format-only-equivalence-passed','producer':pin(current_path),'executed_runner':old_split['executed_runner'],'full_originals':{s:pin(r) for s,(_,r,_) in originals.items()},'compact_receipts':{s:pin(originals[s][0]) for s in ['build-final','native-build','native-verification','reporting-split','native-closure','verification']},'dependency_manifest':dependency_summary,'original_native_summary_canonical_sha256':canonical_sha(expected_summary),'compact_native_summary_canonical_sha256':canonical_sha({k:compact_results[k] for k in exact_summary_keys}),'native_stdout_stderr_pairs':127,'raw_receipt_canonical_sha256':canonical_sha(raw_receipts),'twenty_original_helper_asts_unchanged':True,'nonfunction_ast_unchanged':True,'new_reporting_only_helpers':['compact_existing'],'original_kernel_diagnostic_retained':True,'no_java_bend_native_kernel_execution':True}
    storage['original_remap_summary_canonical_sha256']=canonical_sha(remap_summary)
    storage['compact_remap_summary_canonical_sha256']=canonical_sha(compact_results['dynamic_remap'])
    storage['three_report_bytes_before']=sum(len(originals[s][1].read_bytes()) for s in ['build-final','native-build','native-verification'])
    storage['three_report_bytes_after']=sum(len(originals[s][0].read_bytes()) for s in ['build-final','native-build','native-verification'])
    for suffix in ['build-final','native-build','native-verification']:
        value=json.loads(originals[suffix][0].read_text());raw=ROOT/value['full_original']['path'];assert pin(raw)==value['full_original'];assert canonical_sha(json.loads(raw.read_text()))==value['canonical_original_json_sha256']
    save(ROOT/'evidence/local-collision-world-storage.json',storage)
    handoff=copy.deepcopy(originals['handoff'][2]);handoff['full_original']=pin(originals['handoff'][1])
    paths=[ROOT/p for p in ['src/local_collision_world.bend','tests/local_collision_world.bend','tools/reference_local_collision_world_probe.py','tools/test_local_collision_world.py','reference/local_collision_world.json','docs/LOCAL_COLLISION_WORLD.md']]+sorted(p for p in (ROOT/'evidence').glob('local-collision-world*.json') if p!=originals['handoff'][0])
    handoff['owned_files']=[{'path':str(p.relative_to(ROOT)),'bytes':p.stat().st_size,'sha256':sha(p)} for p in paths];handoff['owned_file_count']=len(paths)
    save(originals['handoff'][0],handoff)
    return {k:storage[k] for k in ['status','three_report_bytes_before','three_report_bytes_after','dependency_manifest','original_native_summary_canonical_sha256','compact_native_summary_canonical_sha256']}

def main():
    p=argparse.ArgumentParser();p.add_argument('--compact-existing',action='store_true');p.add_argument('--prepare-only',action='store_true');p.add_argument('--ordinary-only',action='store_true');p.add_argument('--build-only',action='store_true');p.add_argument('--kernel-only',action='store_true');p.add_argument('--skip-build',action='store_true');p.add_argument('--skip-checks',action='store_true');a=p.parse_args()
    if a.compact_existing:print(json.dumps(compact_existing(),indent=2));return
    if a.ordinary_only:print(json.dumps(bounded('ordinary',60),indent=2));return
    if a.build_only:print(json.dumps(bounded('build',600),indent=2));return
    if a.kernel_only:print(json.dumps(bounded('kernel',60),indent=2));return
    from reference_local_collision_world_probe import verify
    provenance=verify(selftest=True);data=json.loads(FIXTURE.read_text());before=generation();tools=tool_pins()
    prepared={'counts':data['counts'],'native_parity_cases':sum(c['admission']['neutral_helper_context'] for c in data['cases']),
      'measured_admission_rejections':sum(not c['admission']['neutral_helper_context'] for c in data['cases']),
      'generation':before,'tools':tools,'reference':fingerprint(FIXTURE),'provenance':provenance,
      'ordinary_check':completed('ordinary'),'laws':['body_mismatch_retains_complete_world','query_outside_admission_retains_core','cursor_corner_skips_core_read','unresolved_environment_retains_complete_world','zero_query_budget_retains_core'],
      'maximum_body_parser_words':30,'boxed_phase_arity':'Request/Frame/Scan/Slot are recursive Data boxes; large body/context/environment captures stay boxed'}
    if a.prepare_only:
        save(ROOT/'evidence/local-collision-world-prepared.json',{'status':'prepared',**prepared});print(json.dumps({'status':'prepared','counts':data['counts']},indent=2));return
    builds=[completed('build')] if a.skip_build else [bounded('build',600)]
    native_receipts,compared,rejected=validate_cases(data);policy,policy_receipts=validate_policy(data);remap=validate_remap(data)
    assert generation()==before and tool_pins()==tools
    record={'schema_version':1,'status':'native-passed/kernel-pending',**prepared,'checks':[],'builds':builds,'binary':fingerprint(BINARY),
      'native_cases':compared,'measured_rejections':rejected,'policy_rejections':policy,'same_owner_recoveries':len(policy),
      'native_receipts':native_receipts+policy_receipts,'dynamic_remap':remap,'all_body_view_cache_clock_fields_retained':True,
      'native_query_count':sum(c['queries'] for c in compared),'native_read_count':sum(c['reads'] for c in compared),
      'native_first_yields':sum(c['first_yields'] for c in compared),'source_generation_unchanged':True,
      'scope':data['boundary'],'confidence':'High for admitted finite four-state world reads/backoff; actual airborne fallDistance updates, entity/border resolution and full LocalPlayer tick remain outside adapter'}
    # Retain native evidence before the independent proof attempt can fail.
    save(ROOT/'evidence/local-collision-world-native-verification.json',record)
    try:
        checks=[completed('kernel')] if a.skip_checks else [bounded('kernel',60)]
    except AssertionError:
        record['status']='native-passed/kernel-unverified'
        record['checks']=[json.loads((ROOT/'evidence/local-collision-world-kernel-final.json').read_text())]
        record['confidence']='Native comparisons passed within admitted finite scope; independent kernel verification unresolved'
        save(ROOT/'evidence/local-collision-world-verification.json',record)
        print(json.dumps({k:record[k] for k in ['status','native_query_count','native_read_count','native_first_yields','same_owner_recoveries','confidence']},indent=2))
        raise SystemExit('Native pass retained; independent kernel did not verify. See kernel receipt.')
    assert generation()==before and tool_pins()==tools
    record['status']='passed';record['checks']=checks
    save(ROOT/'evidence/local-collision-world-verification.json',record)
    print(json.dumps({k:record[k] for k in ['status','native_query_count','native_read_count','native_first_yields','same_owner_recoveries','confidence']},indent=2))

if __name__=='__main__':main()
