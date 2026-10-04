#!/usr/bin/env python3
"""Whole actual LocalPlayer.move projection comparison; no host gameplay math."""
from __future__ import annotations
import argparse,copy,hashlib,json,os,signal,struct,subprocess,sys,time
from pathlib import Path
from build_native import Snapshot,source_graph
from reference_inventory import fingerprint
from test_geometry import word_vector

ROOT=Path(__file__).resolve().parents[1]
BEND=Path('/Users/chuah/.bend/bin/bend')
BINARY=ROOT/'build/local-move-world-tests'
WORK=ROOT/'build/local-move-world-verification'
FIXTURE=ROOT/'reference/local_move_world.json'
TABLE=ROOT/'generated/reference_mth_sin.f32'
NAMES=['minecraft:air','minecraft:stone','minecraft:dirt','minecraft:oak_planks']
INTERIOR=[-64.,-64.,-64.,64.,64.,64.]

def canonical(v):return json.dumps(v,sort_keys=True,separators=(',',':')).encode()
def digest(v):return hashlib.sha256(canonical(v)).hexdigest()
def save(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,sort_keys=True,indent=2)+'\n')
def pin(p):return {'path':str(p.relative_to(ROOT)),**fingerprint(p)}
def generation():
    s=Snapshot();source_graph(ROOT/'tests/local_move_world.bend',(BEND.resolve().parent.parent/'bend2/base.bend').resolve(),dict(os.environ),s)
    return {p['path']:p['sha256'] for p in s.manifest()}
def tool_pins():return {s:pin(ROOT/s) for s in ['tools/test_local_move_world.py','tools/reference_local_move_world_probe.py','tools/reference_local_collision_world_probe.py','tools/reference_local_collision_probe.py','tools/reference_local_input_probe.py','tools/reference_inventory.py','tools/build_native.py']}

def bound(kind,timeout):
    WORK.mkdir(parents=True,exist_ok=True);before=generation();tp=tool_pins();ref=pin(FIXTURE);table=pin(TABLE)
    full_native=WORK/'native-build-full.json'
    argv=([sys.executable,str(ROOT/'tools/build_native.py'),'tests/local_move_world.bend','-o',str(BINARY),'--cache-dir',str(ROOT/'build/local-move-world-cache'),'--report',str(full_native)] if kind=='build' else [str(BEND),'tests/local_move_world.bend','--check-only' if kind=='ordinary' else '--verdict'])
    start=time.monotonic();p=subprocess.Popen(argv,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
    print(json.dumps({'phase':kind,'pid':p.pid,'cap_seconds':timeout}),flush=True);samples=[];timeout_hit=False
    while True:
        left=timeout-(time.monotonic()-start)
        if left<=0:
            timeout_hit=True
            try:os.killpg(p.pid,signal.SIGTERM)
            except ProcessLookupError:pass
            try:out,err=p.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(p.pid,signal.SIGKILL);out,err=p.communicate()
            break
        try:out,err=p.communicate(timeout=min(left,5));break
        except subprocess.TimeoutExpired:
            rows=subprocess.run(['ps','-ax','-o','pid=,pgid=,rss=,vsz=,etime='],capture_output=True,text=True,check=True).stdout
            group=[]
            for line in rows.splitlines():
                f=line.split()
                if len(f)==5 and int(f[1])==p.pid:group.append({'pid':int(f[0]),'rss_kib':int(f[2]),'virtual_kib':int(f[3]),'elapsed':f[4]})
            samples.append({'seconds':round(time.monotonic()-start,6),'processes':group})
    stdout=WORK/(kind+'.stdout');stderr=WORK/(kind+'.stderr');stdout.write_text(out);stderr.write_text(err)
    r={'status':'passed' if not timeout_hit and p.returncode==0 else 'inconclusive' if timeout_hit else 'failed','kind':kind,'command':argv,'pid':p.pid,'exit_code':p.returncode,'seconds':round(time.monotonic()-start,6),'cap_seconds':timeout,'timed_out':timeout_hit,'stdout':pin(stdout),'stderr':pin(stderr),'generation':before,'generation_unchanged':before==generation(),'tools':tp,'tools_unchanged':tp==tool_pins(),'reference':ref,'reference_unchanged':ref==pin(FIXTURE),'table':table,'table_unchanged':table==pin(TABLE),'compiler':fingerprint(BEND),'memory_samples':samples,'memory_scope':'5-second process-group RSS/virtual sampling; no physical-footprint or gameplay performance claim'}
    if kind=='build' and r['status']=='passed':
        n=json.loads(full_native.read_text());assert n['binary_sha256']==fingerprint(BINARY)['sha256']
        r['binary']=pin(BINARY);r['native_build']={'full_receipt':pin(full_native),'dependencies':{'count':len(n['dependencies']),'canonical_sha256':digest(n['dependencies'])},'artifact':n['artifact'],'cache_key':n['cache_key'],'cache_hit':n['cache_hit'],'timings':n['timings'],'identity':n['identity'],'compiler':{k:v for k,v in n['compiler'].items() if k!='driver_probe'},'associated_preflight_c_sha256':n['emitted_c_sha256'],'c_scope':'build_native content-keyed preflight C; installed CLI native-internal temporary C is not retained or asserted byte-identical'}
    save(ROOT/f'evidence/local-move-world-{kind}.json',r)
    assert r['generation_unchanged'] and r['tools_unchanged'] and r['reference_unchanged'] and r['table_unchanged'],r
    return r

def bits(v):return struct.pack('>d',v).hex()
def words(raw):return [int(v) for v in word_vector(raw)]
def mask(keys):return sum(int(v)<<i for i,v in enumerate(keys))
def body_words(s):return words(s['position']+s['box']+s['velocity'])+[int(s['width_f32_bits'],16),int(s['height_f32_bits'],16),*map(int,s['body_flags'])]
def body_fields(s):return list(map(str,body_words(s)))
def seed_words(s):return [int(s['main_support'] is not None),*(s['main_support'] or [0,0,0]),int(s['on_ground_no_blocks']),int(s['minor_horizontal_collision'])]
def support_fields(s):return ['none' if s['main_support'] is None else ','.join(str(v&0xffffffff) for v in s['main_support']),str(int(s['on_ground_no_blocks']))]

def request(step,id,install=False,context_changes=None,environment_changes=None,interior=INTERIOR):
    s=step['before'];c=step['context']
    context=[int(s['maximum_f32_bits'],16),*words([s['fall_distance_f64_bits']]),int(s['flying']),mask(s['key_presses']),{'SELF':0,'PLAYER':1}.get(step['mover'],2),0,len(step['queries'])+1,int(s['rotation_f32_bits'][0],16),int(s['input_f32_bits'][0],16),int(s['input_f32_bits'][2],16),int(c['can_simulate']),int(c['local_authoritative']),*words(s['stuck_speed_multiplier']),0,int(c['auto_jump_enabled']),int(c['block_speed_factor_f32_bits']=='3f800000'),int(c['suppressed_bounce'])]
    env=[0,0,*words([bits(v) for v in interior])]
    for k,v in (context_changes or {}).items():context[k]=v
    for k,v in (environment_changes or {}).items():env[k]=v
    group=lambda vs:'|'.join(str(v&0xffffffff) for v in vs)
    return ';'.join([id+'|move|'+str(int(install)),group(body_words(s)),group(context),group(words(step['requested'])),group(env),group(seed_words(s))])

def edits(writes,label):
    kinds={'air':0,'stone':1,'dirt':2,'oak_planks':3}
    return ['|'.join(str(v&0xffffffff) if isinstance(v,int) else v for v in [label+':'+str(i),'edit',*w['position'],kinds[w['block']]]) for i,w in enumerate(writes)]

def lines(text):
    p={};q={};coll={};support={}
    for line in text.splitlines():
        f=line.split('|');assert len(f)>=2,line
        target={'query':q,'collision-query':coll,'support-query':support}.get(f[1])
        if target is not None:target.setdefault(f[0],[]).append(f[2:])
        else:assert (f[0],f[1]) not in p,(f[0],f[1]);p[f[0],f[1]]=f[2:]
    return p,q,coll,support

def raw64(v):
    assert len(v)%2==0
    return [f'{int(v[i]):08x}{int(v[i+1]):08x}' for i in range(0,len(v),2)]
def same_owner(p,id,body=True):
    kinds=['clock','queue','view']+(['body','support','minor-state'] if body else [])
    for kind in kinds:assert p[id+'-before',kind]==p[id+'-after',kind],(id,'retention',kind)
def palette(p,id):return dict(zip(NAMES,map(int,p[id+'-before','view'][2].split(',')),strict=True))

def compare(step,id,p,q,coll,support):
    expected=step['expected'];assert p[id+'-before','body']==body_fields(step['before']),(id,'before body')
    assert p[id+'-before','support']==support_fields(step['before']),(id,'before support')
    assert p[id+'-after','body']==body_fields(expected),(id,'final body',p[id+'-after','body'],body_fields(expected))
    assert p[id+'-after','support']==support_fields(expected),(id,'final support')
    assert p[id+'-after','minor-state']==[str(int(expected['minor_horizontal_collision']))],(id,'final minor')
    same_owner(p,id,False)
    assert raw64(p[id,'corrected'])==step['corrected_requested'],(id,'backoff')
    assert raw64(p[id,'resolved'])==step['resolved'],(id,'collision resolved')
    assert bool(int(p[id,'transition'][1]))==step['position_application_gate_entered'],(id,'position gate')
    assert p[id,'pre-restitution']==body_fields(step['before_support']),(id,'before-support body/velocity')
    assert step['before_support']['velocity']==step['before']['velocity']
    if step['minor_called']:
        assert step['before_minor'] is not None and p[id,'pre-restitution']==body_fields(step['before_minor']),(id,'before-minor body/velocity')
        assert p[id,'minor-hook'][0]==str(int(expected['minor_horizontal_collision'])),(id,'minor call')
        assert step['before_minor']['velocity']==step['before']['velocity']
    else:assert p[id,'minor-hook']==['none'],(id,'minor bypass')
    ids=palette(p,id);actual=q.get(id,[])
    starts=[c['sequence'] for c in step['player_calls'] if c['method']=='maybeBackOffFromEdge_entry']
    ends=[c['sequence'] for c in step['player_calls'] if c['method']=='maybeBackOffFromEdge_exit']
    assert len(starts)==len(ends)==1 and starts[0]<ends[0],(id,'actual backoff phase markers')
    expected_q=[v for v in step['queries'] if v['method']=='noCollision' and starts[0]<v['entry_sequence']<v['exit_sequence']<ends[0]]
    excluded_q=[v for v in step['queries'] if v['method']=='noCollision' and v not in expected_q]
    record_starts=[c['sequence'] for c in step['player_calls'] if c['method']=='recordMovement_entry']
    record_ends=[c['sequence'] for c in step['player_calls'] if c['method']=='recordMovement_exit']
    for excluded in excluded_q:
        assert len(record_starts)==len(record_ends)==1 and record_starts[0]<excluded['entry_sequence']<excluded['exit_sequence']<record_ends[0],(id,'excluded query is outside declared recordMovement phase',excluded)
    excluded_reports=[{'method':v['method'],'query_index':v['index'],'entry_sequence':v['entry_sequence'],'exit_sequence':v['exit_sequence'],'reads':len(v['reads']),'yielded_shapes':len(v['yielded_shapes']),'scope':'recordMovement outside current movement/emission projection'} for v in excluded_q]
    assert len(actual)==len(expected_q),(id,'backoff query count')
    for index,(a,b) in enumerate(zip(actual,expected_q,strict=True)):
        assert int(a[0])==index and raw64(a[1:13])==b['box'],(id,index,'backoff box')
        assert bool(int(a[13]))==b['result'],(id,index,'noCollision')
        shapes=b['yielded_shapes']
        if not shapes:assert a[14]=='none';serialized=a[15]
        else:assert len(shapes)==1 and len(shapes[0])==1 and raw64(a[14:26])==shapes[0][0];serialized=a[26]
        actual_reads=[list(map(int,r.split(','))) for r in serialized.split(';') if r]
        expected_reads=[[*(v&0xffffffff for v in r['position']),ids[r['block_id']]] for r in b['reads']]
        assert actual_reads==expected_reads,(id,index,'ordered Core backoff reads')
    actual_coll=coll.get(id,[]);expected_coll=[v for v in step['queries'] if v['method']=='blockCollisions']
    assert len(actual_coll)==len(expected_coll),(id,'collision list count')
    for a,b in zip(actual_coll,expected_coll,strict=True):
        assert raw64(a[1:13])==b['box'],(id,a[0],'collision box')
        # Box serialization contains |, so collect the remainder before ; split.
        actual_boxes=[raw64(v.split('|')) for v in '|'.join(a[13:]).split(';') if v]
        assert actual_boxes==[v[0] for v in b['yielded_shapes']],(id,a[0],'ordered actual collision shapes')
    actual_support=support.get(id,[]);expected_support=[v for v in step['queries'] if v['method']=='support']
    assert len(actual_support)==len(expected_support),(id,'support query count')
    for a,b in zip(actual_support,expected_support,strict=True):
        assert raw64(a[1:13])==b['box'],(id,a[0],'support query')
        selected='none' if b['selected'] is None else ','.join(str(v&0xffffffff) for v in b['selected'])
        assert a[13]==selected,(id,a[0],'actual supporting selection')
    return {'id':id,'backoff_queries':len(actual),'backoff_ordered_reads':sum(len(v['reads']) for v in expected_q),'collision_queries':len(actual_coll),'collision_shape_yields':sum(len(v['yielded_shapes']) for v in expected_coll),'support_queries':len(actual_support),'position_gate':step['position_application_gate_entered'],'minor_called':step['minor_called'],'pre_restitution_velocity_raw_match':True,'actual_backoff_phase':[starts[0],ends[0]],'excluded_recordMovement_queries':excluded_reports}

def native(commands,label,env=None):
    start=time.monotonic();argv=[str(BINARY),'--gpu','off',str(TABLE),*commands];p=subprocess.run(argv,cwd=ROOT,env=env,text=True,capture_output=True,timeout=120)
    WORK.mkdir(parents=True,exist_ok=True);out=WORK/(label+'.stdout');err=WORK/(label+'.stderr');out.write_text(p.stdout);err.write_text(p.stderr)
    r={'label':label,'exit_code':p.returncode,'seconds':round(time.monotonic()-start,6),'stdout':pin(out),'stderr':pin(err),'command_inputs_sha256':digest(commands)}
    assert p.returncode==0,(r,p.stderr[-3000:]);return *lines(p.stdout),r

def corpus(data,env=None,prefix='case'):
    rows=[];guards=[];receipts=[]
    for ci,c in enumerate(data['cases']):
        commands=edits(c['initial']['world_writes'],'initial-edit')
        for si,s in enumerate(c['steps']):
            commands+=edits(s['world_writes'],'step-edit:'+str(si));commands.append(request(s,c['id']+':'+str(si),install=si==0))
        commands.append('final|table-probe');p,q,coll,support,r=native(commands,prefix+str(ci),env);receipts.append(r);assert p['final','table-owner']==['0']
        for si,s in enumerate(c['steps']):
            id=c['id']+':'+str(si)
            if s['admission']['neutral_context']:rows.append(compare(s,id,p,q,coll,support))
            else:
                same_owner(p,id);assert p[id,'error']==['local-move-context:6'];assert not q.get(id) and not coll.get(id) and not support.get(id);guards.append({'id':id,'error':p[id,'error'][0],'actual_context':'suppressedBounce false; explicit neutral projection denied'})
    return rows,guards,receipts

def policy(data):
    base=data['cases'][0]['steps'][0];results=[];receipts=[]
    def test(label,commands,error):
        p,q,c,s,r=native([request(base,'initial',True),*commands,request(base,'recovery',True),'final|table-probe'],label)
        same_owner(p,label);assert p[label,'error'][0].startswith(error),(label,p.get((label,'error')));assert not q.get(label) and not c.get(label) and not s.get(label)
        compare(base,'recovery',p,q,c,s);assert p['final','table-owner']==['0'];results.append({'id':label,'error':p[label,'error'][0],'full_body_view_support_minor_clock_queue_rollback':True,'same_world_tables_owner_recovery':True});receipts.append(r)
    changed=copy.deepcopy(base);changed['before']=copy.deepcopy(base['expected']);changed['before']['velocity'][1]='8000000000000000'
    test('body-mismatch',[request(changed,'body-mismatch',False)],'local-move-body-mismatch')
    for index,label,word in [(11,'cannot-simulate',0),(12,'nonlocal-authority',0),(13,'stuck-multiplier',0x3ff00000),(19,'removed',1),(20,'auto-jump',1),(21,'block-speed',0),(22,'bounce',0)]:
        test(label,[request(base,label,True,context_changes={index:word})],'local-move-context:')
    for index,label in [(0,'unknown-entities'),(1,'unknown-border')]:test(label,[request(base,label,True,environment_changes={index:1})],'edge-')
    test('fuel',[request(base,'fuel',True,context_changes={7:0})],'edge-query-budget')
    test('interior',[request(base,'interior',True,interior=[0.,0.,0.,1.,1.,1.])],'local-move-sweep-outside-interior')
    for label,op,error in [('absent-palette','no-palette','edge-palette-unavailable'),('stale-palette','stale-palette','edge-palette-stale')]:
        test(label,[label+'-setup|'+op,request(base,label,True),'restore|palette-refresh'],error)
    point=next(q['reads'][0]['position'] for q in base['queries'] if q['method']=='noCollision');edit=lambda id,k:'|'.join(map(str,[id,'edit',*(v&0xffffffff for v in point),k]))
    test('unknown-state',[edit('unknown',4),request(base,'unknown-state',True),edit('repair',0)],'unsupported-block-state:')
    # Select a real observed collision-only read: the failure occurs after backoff.
    prior_reads={tuple(r['position']) for q in base['queries'] if q['method']=='noCollision' for r in q['reads']}
    collision_read=next(r for q in base['queries'] if q['method']=='blockCollisions' for r in q['reads'] if tuple(r['position']) not in prior_reads)
    point2=collision_read['position'];edit2=lambda id,k:'|'.join(map(str,[id,'edit',*(v&0xffffffff for v in point2),k]))
    test('after-backoff-collision-failure',[edit2('late-unknown',4),request(base,'after-backoff-collision-failure',True),edit2('late-repair',NAMES.index(collision_read['block_id']))],'unsupported-block-state:')
    missing=copy.deepcopy(base);missing['before']['position'][0]=bits(32.5);missing['before']['box'][0]=bits(32.2);missing['before']['box'][3]=bits(32.8)
    test('missing-section',[request(missing,'missing-section',True)],'missing-section:')
    for mode in range(1,7):test('mode-'+str(mode),[request(base,'mode-'+str(mode),True,context_changes={6:mode})],'local-move-hook-admission')
    p,q,c,s,r=native(['clock|clock','running|running','pending|pending',request(base,'running-pending',True),'final|table-probe'],'running-pending')
    compare(base,'running-pending',p,q,c,s);assert p['running-pending-before','clock'][1]=='777' and p['running-pending-before','clock'][2]=='0' and p['running-pending-before','clock'][5]=='1';assert p['running-pending-before','queue'][0]=='100,9,0,time,999;';receipts.append(r)
    return results,receipts

def remap(data):
    path=WORK/'remapped.tsv';path.parent.mkdir(parents=True,exist_ok=True);order=['minecraft:oak_planks','minecraft:stone','minecraft:air','minecraft:dirt']
    path.write_text('block_protocol_id\tidentifier\tfirst_state_id\tstate_count\tdefault_state_id\tordered_properties_json\n'+''.join(f'{i}\t{name}\t{i}\t1\t{i}\t[]\n' for i,name in enumerate(order)))
    env=dict(os.environ);env['MC_BLOCK_REGISTRY']=str(path)
    selected=[c for c in data['cases'] if c['id'] in ['dynamic_floor','held_floor','held_wall','held_shift_edge']];assert len(selected)==4
    rows,guards,receipts=corpus({'cases':selected},env,'remap');return {'registry':pin(path),'case_ids':[c['id'] for c in selected],'native_moves':len(rows),'cases':rows,'guard_count':len(guards),'receipt_count':len(receipts)},receipts

def preparation(data):
    g=generation();p={'status':'ordinary-prepared-native-and-kernel-pending','generation':g,'generation_count':len(g),'generation_sha256':digest(g),'tools':tool_pins(),'reference':pin(FIXTURE),'table':pin(TABLE),'actual_counts':data['counts'],'planned_native_admitted_moves':sum(s['admission']['neutral_context'] for c in data['cases'] for s in c['steps']),'native_command':[sys.executable,'tools/test_local_move_world.py'],'native_build_cap_seconds':600,'independent_kernel_cap_seconds':60,'scope':'Neutral LocalPlayer.move projection; exact backoff→collision→support→minor→velocity commit. No fall-history/emission/autoJump/walkedDistance projection or whole tick claim.'}
    save(ROOT/'evidence/local-move-world-preparation.json',p);return p

def main():
    p=argparse.ArgumentParser();p.add_argument('--prepare',action='store_true');p.add_argument('--skip-build',action='store_true');p.add_argument('--skip-ordinary',action='store_true');p.add_argument('--skip-kernel',action='store_true');a=p.parse_args();data=json.loads(FIXTURE.read_text())
    if a.prepare:
        ordinary=bound('ordinary',60);assert ordinary['status']=='passed';r=preparation(data);print(json.dumps({'status':r['status'],'generation_count':r['generation_count'],'actual_counts':r['actual_counts']}));return
    initial=generation();tp=tool_pins();ref=pin(FIXTURE);table=pin(TABLE)
    ordinary=None if a.skip_ordinary else bound('ordinary',60)
    if ordinary:assert ordinary['status']=='passed'
    build=json.loads((ROOT/'evidence/local-move-world-build.json').read_text()) if a.skip_build else bound('build',600)
    assert build['status']=='passed' and build['generation']==initial and build['binary']==pin(BINARY)
    rows,guards,receipts=corpus(data);policies,more=policy(data);mapped,extra=remap(data);receipts+=more+extra
    raw=WORK/'native-results-full.json';save(raw,{'corpus':rows,'guards':guards,'policies':policies,'remap':mapped,'native_receipts':receipts})
    native_report={'status':'passed','generation':initial,'generation_unchanged':initial==generation(),'tools':tp,'tools_unchanged':tp==tool_pins(),'reference':ref,'reference_unchanged':ref==pin(FIXTURE),'table':table,'table_unchanged':table==pin(TABLE),'binary':pin(BINARY),'build':pin(ROOT/'evidence/local-move-world-build.json'),'ordinary':pin(ROOT/'evidence/local-move-world-ordinary.json'),'native_moves':len(rows),'measured_guard_count':len(guards),'policy_recovery_count':len(policies),'dynamic_remap':mapped,'position_gate_skips':sum(not r['position_gate'] for r in rows),'minor_calls':sum(r['minor_called'] for r in rows),'backoff_queries':sum(r['backoff_queries'] for r in rows),'backoff_ordered_reads':sum(r['backoff_ordered_reads'] for r in rows),'collision_queries':sum(r['collision_queries'] for r in rows),'collision_shape_yields':sum(r['collision_shape_yields'] for r in rows),'support_queries':sum(r['support_queries'] for r in rows),'full_native_results':pin(raw),'canonical_native_results_sha256':digest(json.loads(raw.read_text())),'raw_receipt_count':len(receipts),'raw_receipts_sha256':digest(receipts),'pre_restitution_callback_observations_raw_match':True,'excluded_recordMovement_queries':[{'native_case':r['id'],**q} for r in rows for q in r['excluded_recordMovement_queries']],'historical_build_runner':build['tools']['tools/test_local_move_world.py'],'immutable_native_build_reused':a.skip_build,'all_errors_return_full_prior_world_view_support_minor_and_same_owners':True,'scope':'Bounded body/support/minor projection only. Read-only query replays are labeled and do not claim production trace instrumentation. Actual fallDistance/emission/autoJump/walkedDistance execute in oracle and remain outside this projection.'}
    assert native_report['generation_unchanged'] and native_report['tools_unchanged'] and native_report['reference_unchanged'] and native_report['table_unchanged']
    # Seal decisive native pass before attempting independent proof.
    save(ROOT/'evidence/local-move-world-native.json',native_report)
    kernel=None if a.skip_kernel else bound('kernel',60)
    final={'native_status':'passed','kernel_status':'not-run' if kernel is None else kernel['status'],'native_receipt':pin(ROOT/'evidence/local-move-world-native.json'),'kernel_receipt':None if kernel is None else pin(ROOT/'evidence/local-move-world-kernel.json'),'generation':initial,'tools':tp,'reference':ref,'table':table,'binary':pin(BINARY)}
    save(ROOT/'evidence/local-move-world-verification.json',final);print(json.dumps({'native_status':'passed','kernel_status':final['kernel_status'],'native_moves':len(rows),'policies':len(policies),'remapped_moves':mapped['native_moves']}))
    if kernel and kernel['status']!='passed':raise SystemExit(1)
if __name__=='__main__':main()
