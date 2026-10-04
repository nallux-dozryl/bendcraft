#!/usr/bin/env python3
"""Own-world pose parity, exact query/read rows and complete rollback.

Python only serializes explicit worlds, actual Java raw observations and
defensive inputs. It does not decide fit, scan order, pose or eye arithmetic.
Ordinary preparation is the default explicit action. Native/proof actions need
the lead's bounded build slot. Retained binaries fail closed on changed pins.
"""
from __future__ import annotations
import argparse, ast, copy, hashlib, json, os, re, signal, struct, subprocess, sys, time
from pathlib import Path
from reference_inventory import ROOT, canonical, fingerprint, write_json

BEND=Path('/Users/chuah/.bend/bin/bend')
ENTRY=ROOT/'tests/player_pose_world.bend'
REFERENCE=ROOT/'reference/player_pose_world.json'
BINARY=ROOT/'build/player-pose-world-tests'
RAW=ROOT/'build/player-pose-world-tests-artifacts'
BUILD=RAW/'native-build.json'
POSES={'STANDING':0,'FALL_FLYING':1,'SLEEPING':2,'SWIMMING':3,'SPIN_ATTACK':4,'CROUCHING':5,'DYING':7}
FLAGS=['sleeping','swimming','fall_flying','auto_spin_attack','shift','flying','spectator','passenger']
NAMES=['minecraft:air','minecraft:stone','minecraft:dirt','minecraft:oak_planks']
REGISTRY=ROOT/'generated/reference_blocks.tsv'

def sha(value):return hashlib.sha256(canonical(value)).hexdigest()
def pin(path):return {'path':str(path.relative_to(ROOT)) if path.is_relative_to(ROOT) else str(path),**fingerprint(path)}
def words(raw):v=int(raw,16);return [v>>32,v&0xffffffff]
def wide(values):return [v for raw in values for v in words(raw)]
def text(values):return '|'.join(str(v&0xffffffff) for v in values)
def bits(value):return struct.pack('>d',value).hex()
def scalar(name):return 'scalar;'+name
def edit(position,kind):return 'edit;'+text([*position,kind])
def section(position):return 'section;'+text(position)

def body_words(state):
    return wide(state['position']+state['box']+state['velocity'])+[int(state['width_f32_bits'],16),int(state['height_f32_bits'],16),*map(int,state['body_flags'])]

def state_words(state):return [POSES[state['pose']],int(state['cached_eye_f32_bits'],16)]
def state_complete(state):return ','.join(map(str,state_words(state)))+'[]'

def environment(case,changes=None,interior=None):
    if interior is None:
        # Explicit fixture declaration; no reconstruction of border gameplay.
        point=[struct.unpack('>d',bytes.fromhex(v))[0] for v in case['before']['position']]
        interior=[point[0]-64.,-64.,point[2]-64.,point[0]+64.,64.,point[2]+64.]
    row=[0,0,*wide([bits(v) for v in interior])]
    for i,v in (changes or {}).items():row[i]=v
    return row

def request(case,id=None,alteration=0,fuel=None,context_changes=None,environment_changes=None,interior=None):
    state=case['before'];context=state['context']
    values=[sum(1<<i for i,n in enumerate(FLAGS) if context[n]),int(state['scale_f32_bits'],16),int(state['baby']),0]
    for i,v in (context_changes or {}).items():values[i]=v
    return ';'.join(['update',id or case['id'],str(alteration),str(len(case['queries']) if fuel is None else fuel),text(body_words(state)),text(state_words(state)),text(values),text(environment(case,environment_changes,interior))])

def scene(case):
    # Derive required loaded sections from actual observed positions. This
    # serializes independent receiver reads; it computes no collision cursor.
    sections={tuple((v//16)*16 for v in r['position']) for q in case['queries'] for r in q['reads']}
    writes=case['initial']['world_writes'];sections|={tuple((v//16)*16 for v in w['position']) for w in writes}
    kinds={'air':0,'stone':1,'dirt':2,'oak_planks':3}
    return [*[section(p) for p in sorted(sections)],*[edit(w['position'],kinds[w['block']]) for w in writes],scalar('invalidate'),scalar('warm')]

def records(case):return ''.join(text([POSES[q['pose']],*wide(q['box']),int(q['clear'])])+'/' for q in case['queries'])

def query_line(id,index,query,palette):
    # Every F64 word remains raw, including signed zero. Named Java state
    # identifiers are translated through the actual dynamically loaded palette.
    hit='none' if query['first_yielded'] is None else text(wide(query['first_yielded']))
    reads=''.join(','.join(map(str,[*[v&0xffffffff for v in r['position']],palette[r['identifier']]]))+';' for r in query['reads'])
    return id+'|query|'+text([index,POSES[query['pose']],*wide(query['box']),int(query['clear'])])+'|'+hit+'|'+reads

def lines(out):
    values={};queries={}
    for row in out.splitlines():
        id,kind,value=row.split('|',2)
        if kind=='query':queries.setdefault(id,[]).append(row)
        else:assert (id,kind) not in values,(id,kind);values[id,kind]=value
    return values,queries

def retained(values,id,failure=False):
    for kind in ['clock','queue','view','sections']:
        assert values[id+'-before',kind]==values[id+'-after',kind],(id,kind,'owner state changed')
    if failure:
        assert values[id+'-before','body']==values[id+'-after','body'],(id,'body rollback')
        assert values[id+'-before','pose']==values[id,'pose'],(id,'pose rollback')
    clock=values[id+'-before','clock'].split('|')
    if id=='event-owner':
        assert clock[0]=='1' and clock[1]=='777' and clock[3:7]==['0','1','1','1'],(id,clock)
        assert values[id+'-before','queue']=='100,9,0,time,999;|applied,1,8,1,1;',id
    else:
        assert clock[0]=='0' and clock[1]=='777' and clock[3:7]==['0','0','1','0'],(id,'fixture clock/event/queue',clock)
        assert values[id+'-before','queue']=='100,9,0,time,999;|',id

def compare(case,values,queries,id=None):
    id=id or case['id'];retained(values,id,not case['admitted'])
    if not case['admitted']:
        assert values[id,'error']=='pose:scale' and not queries.get(id),id
        return {'id':id,'refusal':'scale'}
    expected=case['expected'];before=case['before'];q=case['queries']
    desired='none' if not q[0]['clear'] else str(POSES[q[1]['pose'] if len(q)>1 else case['set_pose_requests'][0]])
    ok=desired+'|'+text([POSES[expected['pose']],int(expected['pose']!=before['pose']),case['refresh_count']])+'|'+records(case)
    assert values[id,'ok']==ok,(id,'transition',values[id,'ok'],ok)
    assert values[id,'pose']==state_complete(expected),(id,'pose/eye')
    assert values[id+'-after','body']==text(body_words(expected))==(values[id,'transition-body']),(id,'raw body')
    assert values[id,'eye']==text(wide(expected['eye_position'])),(id,'raw eye position')
    view=values[id+'-before','view'].split('|');palette=dict(zip(NAMES,map(int,view[2].split(',')),strict=True))
    expected_rows=[query_line(id,i,q,palette) for i,q in enumerate(case['queries'])]
    assert queries.get(id,[])==expected_rows,(id,'ordered boxes, Boolean, first cube or reads',queries.get(id,[])[:1],expected_rows[:1])
    return {'id':id,'queries':len(q),'reads':sum(len(v['reads']) for v in q),'first_yields':sum(v['first_yielded'] is not None for v in q)}

def fixtures(data):
    jobs=[{'id':c['id'],'commands':[*scene(c),request(c)],'actual':c['id']} for c in data['cases']]
    base=next(c for c in data['cases'] if c['id']=='initial:STANDING')
    table=REGISTRY.read_text().splitlines();delimiter='\\t' if '\\t' in table[0] else '\t'
    glass=int(next(row.split(delimiter)[4] for row in table[1:] if row.split(delimiter)[1]=='minecraft:glass'))
    # Every failure is followed by reference-matched use of the same Engine.
    guards=[]
    for alteration,error in [(1,'pose:eye'),(2,'pose:dimensions'),(3,'pose:box'),(4,'pose:pose|99'),(5,'pose:tail|0'),(6,'request-tail'),(10,'pose:body|body|0|0'),(11,'pose:body|body|2|0'),(27,'pose:eye'),(28,'pose:body|body|1|0'),(29,'pose:body|dimensions|0')]:
        guards.append((f'failure:{alteration}',[],[],{'alteration':alteration},error))
    guards += [
        ('failure:scale',[],[],{'context_changes':{1:0x3f000000}},'pose:scale'),
        ('failure:age',[],[],{'context_changes':{2:1}},'pose:age'),
        ('failure:mode',[],[],{'context_changes':{3:1}},'pose:context'),
        ('failure:entities',[],[],{'environment_changes':{0:1}},'world:edge-entities-unresolved'),
        ('failure:border',[],[],{'environment_changes':{1:1}},'world:edge-border-unresolved'),
        ('failure:nonfinite-interior',[],[],{'environment_changes':{2:0x7ff00000,3:0}},'world:edge-invalid-interior'),
        ('failure:reversed-interior',[],[],{'interior':[1.,-64.,-64.,-1.,64.,64.]},'world:edge-invalid-interior'),
        ('failure:body-outside',[],[],{'interior':[1.,-64.,-64.,64.,64.,64.]},'body-outside'),
        ('failure:query-outside',[],[],{'interior':[-64.,-64.,-64.,64.,1.7,64.]},'world:edge-query-outside-interior'),
        ('failure:fuel-zero',[],[],{'fuel':0},'fuel'),
        ('failure:fuel-one',[],[],{'fuel':1},'fuel'),
        ('failure:palette',[scalar('no-palette')],[scalar('palette-refresh')],{},'world:edge-palette-unavailable'),
        ('failure:stale-palette',[scalar('stale-palette')],[scalar('palette-refresh')],{},'world:edge-palette-stale'),
        ('failure:unsupported-shell',[edit([0,3,0],4)],[edit([0,3,0],0),scalar('invalidate')],{},'world:unsupported-block-state:'+str(glass)),
        ('failure:missing-section',[scalar('clear-sections')],[*[section([x,y,z]) for x in [-16,0] for y in [-16,0] for z in [-16,0]],*[edit([x,0,z],1) for x in range(-2,3) for z in range(-2,3)],scalar('invalidate')],{},'world:missing-section:minecraft:overworld/0/0/4294967295'),
        ('failure:positive-i32-margin',[],[],{'alteration':32,'interior':[2147483600.,-64.,-64.,2147483700.,64.,64.]},'world:collision-query-limit'),
        ('failure:negative-i32-margin',[],[],{'alteration':33,'interior':[-2147483700.,-64.,-64.,-2147483600.,64.,64.]},'world:collision-query-outside-i32')]
    for id,before,recovery,changes,error in guards:
        actual=next(c for c in data['cases'] if c['id']=='initial:SLEEPING') if id=='failure:query-outside' else base
        jobs.append({'id':id,'commands':[*scene(actual),*before,request(actual,id,**changes),*recovery,request(actual,id+'-recovery')],'failure':error,'recovery':actual['id']})
    jobs.append({'id':'running','commands':[*scene(base),scalar('running'),request(base,'running')],'actual':base['id']})
    jobs.append({'id':'event-owner','commands':[*scene(base),scalar('seed-event'),request(base,'event-owner')],'actual':base['id']})
    # Explicit low-level Core edits bypass revision; do not let them reuse a
    # cached render scene. Rebuild after invalidate and compare a fresh actual
    # ceiling receiver, then remove that ceiling and recover on the same owner.
    ceiling=next(c for c in data['cases'] if c['id']=='ceiling:2:None')
    jobs.append({'id':'edit-recovery','commands':[*scene(ceiling),request(ceiling,'edit-ceiling'),*[edit(w['position'],0) for w in ceiling['initial']['world_writes']],scalar('invalidate'),scalar('warm'),request(base,'edit-recovery')],'comparisons':{'edit-ceiling':ceiling['id'],'edit-recovery':base['id']}})
    return jobs

def closure():
    found={}
    def visit(path):
        path=path.resolve()
        if str(path) in found:return
        found[str(path)]=fingerprint(path)
        for name in re.findall(r'^import\s+(\S+)',path.read_text(),re.M):
            if name.startswith('.'):visit(path.parent/name)
    visit(ENTRY)
    for p in [ROOT/'tools/test_player_pose_world.py',ROOT/'tools/reference_player_pose_world_probe.py',ROOT/'tools/reference_player_pose_probe.py',ROOT/'tools/reference_local_input_probe.py',REFERENCE,REGISTRY,BEND]:found[str(p.resolve())]=fingerprint(p)
    return found

def bounded(command,seconds,label,env=None):
    RAW.mkdir(parents=True,exist_ok=True);start=time.monotonic()
    process=subprocess.Popen(command,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True,env=env)
    print(json.dumps({'phase':label,'pid':process.pid,'cap_seconds':seconds}),flush=True)
    timeout=False
    try:out,err=process.communicate(timeout=seconds)
    except subprocess.TimeoutExpired:
        timeout=True;os.killpg(process.pid,signal.SIGKILL);out,err=process.communicate()
    stdout=RAW/(label+'.stdout');stderr=RAW/(label+'.stderr');stdout.write_text(out);stderr.write_text(err)
    receipt={'command':command,'seconds':round(time.monotonic()-start,6),'returncode':process.returncode,'timed_out':timeout,'whole_process_group_cap':True,'stdout':pin(stdout),'stderr':pin(stderr)}
    return out,err,receipt

def prepare(data):
    jobs=fixtures(data);pins=closure();checks=[]
    for source in [ROOT/'src/player_pose_world.bend',ENTRY]:
        out,err,r=bounded([str(BEND),str(source),'--check-only'],30,source.parent.name+'-ordinary');checks.append(r)
        assert r['returncode']==0 and 'ALL PROOFS CHECK' in out,(r,err)
    assert pins==closure(),'Preparation sources changed'
    artifact=RAW/'prepared-fixtures.json';write_json(artifact,jobs)
    counts={'actual_contexts':len(data['cases']),'admitted':sum(c['admitted'] for c in data['cases']),'queries':sum(len(c['queries']) for c in data['cases']),'reads':sum(len(q['reads']) for c in data['cases'] for q in c['queries']),'first_yields':sum(q['first_yielded'] is not None for c in data['cases'] for q in c['queries']),'failure_recoveries':sum('failure' in j for j in jobs),'extra_running_event_and_edit_jobs':3}
    receipt={'status':'ordinary preparation passes; native/kernel not run','counts':counts,'checks':checks,'dependency_pins':pins,'reference':pin(REFERENCE),'fixtures':pin(artifact),'fixtures_ignored':True,'argument_sha256':sha([j['commands'] for j in jobs]),'expected_actual_fields_sha256':sha(data['cases'])}
    write_json(ROOT/'evidence/player-pose-world-preparation.json',receipt);print(json.dumps({'status':receipt['status'],'counts':counts},indent=2))

def native_capture():
    directory=RAW/'native-capture';directory.mkdir(parents=True,exist_ok=True);commands=directory/'commands.jsonl';commands.write_text('')
    wrapper=directory/'clang'
    source='#!'+sys.executable+'\n'+'''import json,os,pathlib,shutil,sys
directory=pathlib.Path(__DIRECTORY__)
args=sys.argv[1:]
with (directory/'commands.jsonl').open('a') as out:out.write(json.dumps(args,sort_keys=True,separators=(',',':'))+'\\n')
for i,arg in enumerate(args):
 p=pathlib.Path(arg)
 if p.suffix.lower()=='.c' and p.is_file():shutil.copyfile(p,directory/('source-'+str(i)+'.c'))
os.execv('/usr/bin/clang',['/usr/bin/clang',*args])
'''.replace('__DIRECTORY__',repr(str(directory)))
    wrapper.write_text(source);wrapper.chmod(0o700);return wrapper,commands

def native(data,skip):
    pins=closure();jobs=fixtures(data)
    if skip:
        build=json.loads(BUILD.read_text());assert build['dependency_pins']==pins,'Retained native generation changed';assert build['binary']==pin(BINARY),'Binary changed'
    else:
        wrapper,commands=native_capture();env=dict(os.environ);env['CC']=str(wrapper)
        _,err,r=bounded([str(BEND),str(ENTRY),'-o',str(BINARY)],600,'native',env)
        command_rows=[json.loads(row) for row in commands.read_text().splitlines()]
        copied=[pin(p) for p in sorted(wrapper.parent.glob('source-*.c'))]
        build={'status':'failed','execution':r,'dependency_pins':pins,'compiler':pin(BEND),'clang':pin(Path('/usr/bin/clang')),'wrapper':pin(wrapper),'clang_commands':pin(commands),'clang_commands_sha256':sha(command_rows),'clang_command_seal':'canonical UTF-8 JSON ensure_ascii=False sorted keys compact separators no newline','emitted_c':copied}
        if r['returncode']==0 and BINARY.exists():
            assert closure()==pins and copied,'Native sources changed or C capture missing';build.update(status='compiled',binary=pin(BINARY))
        write_json(BUILD,build);assert build['status']=='compiled',err[-8000:]
    byid={c['id']:c for c in data['cases']};results=[];executions=[]
    def run(job,env=None,label=None):
        actual_env=dict(os.environ);actual_env['MC_BLOCK_REGISTRY']=str(REGISTRY)
        if env:actual_env.update(env)
        out,err,r=bounded([str(BINARY),'--gpu','off',*job['commands']],60,label or 'case-'+str(len(executions)),actual_env)
        executions.append(r);assert r['returncode']==0,(r,err);values,queries=lines(out)
        if 'failure' in job:
            id=job['id'];retained(values,id,True);assert not queries.get(id),'Rejected operation leaked successful observation'
            error=values[id,'error'];want=job['failure']
            assert error==want,(id,error,want)
            results.append({'id':id,'error':error,'recovery':compare(byid[job['recovery']],values,queries,id+'-recovery')})
        elif 'comparisons' in job:
            for id,source in job['comparisons'].items():results.append(compare(byid[source],values,queries,id))
        else:results.append(compare(byid[job['actual']],values,queries,job['id']))
        return values
    for job in jobs:run(job)
    table=RAW/'remapped.tsv';names=['minecraft:oak_planks','minecraft:dirt','minecraft:air','minecraft:stone']
    table.write_text('block_protocol_id\tidentifier\tfirst_state_id\tstate_count\tdefault_state_id\tordered_properties_json\n'+''.join(f'{i}\t{name}\t{i}\t1\t{i}\t[]\n' for i,name in enumerate(names)))
    env=dict(os.environ);env['MC_BLOCK_REGISTRY']=str(table)
    for id in ['initial:STANDING','ceiling:2:None','signed_zero','far:30000000.125']:
        c=byid[id];job={'id':'remapped:'+id,'commands':[*scene(c),request(c,'remapped:'+id)],'actual':id}
        v=run(job,env);assert v[job['id']+'-before','view'].split('|')[2]=='2,3,1,0'
    assert closure()==pins,'Comparison inputs changed'
    artifact=RAW/'comparisons.json';write_json(artifact,{'results':results,'executions':executions})
    receipt={'status':'native exact parity and owner rollback pass; independent kernel not run','build_manifest':pin(BUILD),'binary':pin(BINARY),'dependency_pins':pins,'reference':pin(REFERENCE),'raw_artifact':pin(artifact),'raw_ignored':True,'counts':{'actual_contexts':len(data['cases']),'failure_recoveries':sum('failure' in j for j in jobs),'dynamic_palette_cases':4,'native_invocations':len(executions)},'argument_sha256':sha([j['commands'] for j in jobs]),'expected_actual_fields_sha256':sha(data['cases']),'comparison_policy':'Entire independently encoded raw query lines; every ordered read and first shape; exact body/eye/flags; exact section RLE, View/cache, clock, queue/event rows'}
    write_json(ROOT/'evidence/player-pose-world-native.json',receipt);print(json.dumps({'status':receipt['status'],'counts':receipt['counts']},indent=2))

def kernel():
    pins=closure();out,err,r=bounded([str(BEND),str(ENTRY),'--verdict'],60,'kernel')
    receipt={'status':'passed' if r['returncode']==0 and 'ALL PROOFS CHECK' in out else 'inconclusive' if r['timed_out'] else 'failed','execution':r,'dependency_pins':pins,'generation_unchanged':pins==closure(),'scope':'Complete test import closure including PPW laws; no projection or standalone repeat'}
    write_json(ROOT/'evidence/player-pose-world-kernel.json',receipt);print(json.dumps({'status':receipt['status'],'seconds':r['seconds']}));assert receipt['status']=='passed' and receipt['generation_unchanged'],err[-8000:]

def remaining_jobs(data):
    jobs=[{'index':i,'job':job,'registry':REGISTRY} for i,job in enumerate(fixtures(data)) if i>=73]
    assert [row['index'] for row in jobs]==[73,74,75,76]
    table=RAW/'remapped.tsv';names=['minecraft:oak_planks','minecraft:dirt','minecraft:air','minecraft:stone']
    expected='block_protocol_id\tidentifier\tfirst_state_id\tstate_count\tdefault_state_id\tordered_properties_json\n'+''.join(f'{i}\t{name}\t{i}\t1\t{i}\t[]\n' for i,name in enumerate(names))
    if table.exists():assert table.read_text()==expected,'Remapped fixture changed'
    else:table.write_text(expected)
    byid={c['id']:c for c in data['cases']}
    for id in ['initial:STANDING','ceiling:2:None','signed_zero','far:30000000.125']:
        c=byid[id];job={'id':'remapped:'+id,'commands':[*scene(c),request(c,'remapped:'+id)],'actual':id}
        jobs.append({'index':len(jobs)+73,'job':job,'registry':table})
    assert [row['index'] for row in jobs]==list(range(73,81))
    return jobs

def validate_job(data,job,values,queries):
    byid={c['id']:c for c in data['cases']};result=[]
    if 'failure' in job:
        id=job['id'];retained(values,id,True);assert not queries.get(id),'Rejected operation leaked successful observation'
        error=values[id,'error'];want=job['failure'];assert error==want,(id,error,want)
        result.append({'id':id,'error':error,'recovery':compare(byid[job['recovery']],values,queries,id+'-recovery')})
    elif 'comparisons' in job:
        for id,source in job['comparisons'].items():result.append(compare(byid[source],values,queries,id))
    else:result.append(compare(byid[job['actual']],values,queries,job['id']))
    return result

def resume_adoption(data):
    saved=RAW/'first-failure-generation'
    old_runner=saved/'tools/test_player_pose_world.py'
    old_preparation=saved/'evidence/player-pose-world-preparation.json'
    old_handoff=saved/'evidence/player-pose-world-handoff.json'
    old_build=saved/'build/player-pose-world-tests-artifacts/native-build.json'
    expected_pins={old_runner:'00ab95f7c53e802f984fb548da257f81b167e9861ac1f2db7d0245766b2e7467',old_preparation:'3cc4d4aac171df9529302e2a61dd84c961b95e85c979759fede0a355bb287ec8',old_handoff:'c929e610ac2271e10cd39ec76d4f1966ef19fe17f828f94d2068d090c2961cba',old_build:'bdcd2c297ed3386a8e1af29c55b587a106132ec292ad30a6a7005030957ebdbc'}
    for path,digest in expected_pins.items():assert fingerprint(path)['sha256']==digest,('Original generation changed',path)
    assert BUILD.read_bytes()==old_build.read_bytes(),'Original build manifest changed'
    build=json.loads(BUILD.read_text());old=json.loads(old_preparation.read_text())
    assert build['status']=='compiled' and build['binary']==pin(BINARY),'Original binary changed'
    for c in build['emitted_c']:assert pin(ROOT/c['path'])==c,'Original C changed'
    for name in ['compiler','clang','wrapper','clang_commands']:
        value=build[name];assert pin(Path(value['path']) if Path(value['path']).is_absolute() else ROOT/value['path'])==value,(name,'Native provenance changed')
    current=closure();expected=dict(build['dependency_pins']);tool=str((ROOT/'tools/test_player_pose_world.py').resolve())
    assert expected==old['dependency_pins'],'Original compilation/preparation closure differs'
    assert expected[tool]==fingerprint(old_runner)
    expected[tool]=current[tool]
    assert expected==current,'Compiled closure changed beyond the explicitly adopted runner'
    # Every original function stays AST-identical except this exact single
    # project-policy error literal in fixtures(). Existing native/proof paths
    # and every actual Java expectation/serializer stay unchanged.
    before=ast.parse(old_runner.read_text());after=ast.parse(Path(__file__).read_text())
    old_functions={n.name:n for n in before.body if isinstance(n,ast.FunctionDef)}
    new_functions={n.name:n for n in after.body if isinstance(n,ast.FunctionDef)}
    old_top=copy.deepcopy([n for n in before.body if not isinstance(n,(ast.FunctionDef,ast.If))])
    new_top=[n for n in after.body if not isinstance(n,(ast.FunctionDef,ast.If))]
    import_changes=0
    for node in old_top:
        if isinstance(node,ast.Import) and node.names and node.names[0].name=='argparse':
            node.names.insert(1,ast.alias(name='ast',asname=None));import_changes+=1
    assert import_changes==1
    assert ast.dump(ast.Module(body=old_top,type_ignores=[]),include_attributes=False)==ast.dump(ast.Module(body=new_top,type_ignores=[]),include_attributes=False),'Existing imports/global values changed'
    old_main=old_runner.read_text().rsplit("if __name__=='__main__':",1)[1]
    expected_main=old_main.replace("['prepare','native','skip-build','kernel']","['prepare','native','skip-build','kernel','prepare-resume','resume']",1).replace('    elif args.kernel:kernel()\n','    elif args.kernel:kernel()\n    elif args.prepare_resume:prepare_resume(data)\n    elif args.resume:resume(data)\n',1)
    actual_main=Path(__file__).read_text().rsplit("if __name__=='__main__':",1)[1]
    assert expected_main==actual_main,'Main dispatch changed beyond explicit resume actions'
    expected_fixture=copy.deepcopy(old_functions['fixtures']);changes=[]
    for node in ast.walk(expected_fixture):
        if isinstance(node,ast.Tuple) and node.elts and isinstance(node.elts[0],ast.Constant) and node.elts[0].value=='failure:positive-i32-margin':
            assert isinstance(node.elts[-1],ast.Constant) and node.elts[-1].value=='world:collision-query-outside-i32'
            node.elts[-1].value='world:collision-query-limit';changes.append(node)
    assert len(changes)==1
    dump=lambda n:ast.dump(n,include_attributes=False)
    for name,node in old_functions.items():
        wanted=expected_fixture if name=='fixtures' else node
        assert dump(new_functions[name])==dump(wanted),('Original function changed',name)
    added=sorted(set(new_functions)-set(old_functions))
    assert added==['prepare_resume','remaining_jobs','resume','resume_adoption','validate_job','validate_retained'],added
    fixture_pin=old['fixtures'];prepared=ROOT/fixture_pin['path'];assert pin(prepared)==fixture_pin,'Original prepared fixtures changed'
    prior_jobs=json.loads(prepared.read_text());jobs=fixtures(data);wanted=copy.deepcopy(prior_jobs)
    assert wanted[72]['id']=='failure:positive-i32-margin' and wanted[72]['failure']=='world:collision-query-outside-i32'
    wanted[72]['failure']='world:collision-query-limit';assert wanted==jobs,'Commands or other expected values changed'
    assert old['argument_sha256']==sha([j['commands'] for j in jobs]) and old['expected_actual_fields_sha256']==sha(data['cases'])
    index=RAW/'completed-original-output-index.json'
    assert fingerprint(index)['sha256']=='0219606773a3855eb95e19f1a68909b95a502f85a35e447af1a63cfe4cfb7d78'
    index_rows=json.loads(index.read_text());assert len(index_rows)==73
    for i,row in enumerate(index_rows):
        assert row['index']==i and row['id']==jobs[i]['id'] and row['command']==[str(BINARY),'--gpu','off',*jobs[i]['commands']]
        assert row['original_commands_sha256']==sha(jobs[i]['commands'])
        for key in ['stdout','stderr']:assert pin(ROOT/row[key]['path'])==row[key],(i,key,'Original output changed')
        assert row['original_generation_runner']==fingerprint(old_runner)
    return {'original_build':pin(BUILD),'original_runner':pin(old_runner),'original_preparation':pin(old_preparation),'original_handoff':pin(old_handoff),'current_runner':pin(Path(__file__)),'binary':pin(BINARY),'emitted_c':build['emitted_c'],'current_dependency_pins':current,'original_dependency_sha256':sha(build['dependency_pins']),'current_dependency_sha256':sha(current),'completed_output_index':pin(index),'argument_sha256':old['argument_sha256'],'expected_actual_fields_sha256':old['expected_actual_fields_sha256'],'original_functions_ast_unchanged_except_one_literal':True,'added_functions':added,'old_runner_ast_sha256':hashlib.sha256(dump(before).encode()).hexdigest(),'new_runner_ast_sha256':hashlib.sha256(dump(after).encode()).hexdigest(),'expected_change':{'fixture':'failure:positive-i32-margin','old':'world:collision-query-outside-i32','new':'world:collision-query-limit'},'original_73_duration_receipts':'absent; preserved raw streams and original sequential assertion path are the available evidence; no duration values fabricated'}

def validate_retained(data,adoption):
    rows=json.loads((ROOT/adoption['completed_output_index']['path']).read_text());jobs=fixtures(data);results=[]
    for i,row in enumerate(rows):
        out=(ROOT/row['stdout']['path']).read_text();err=(ROOT/row['stderr']['path']).read_text()
        assert not err,(i,'Original native stderr was not empty')
        values,queries=lines(out);result=validate_job(data,jobs[i],values,queries)
        results.append({'index':i,'id':row['id'],'result':result,'stdout':row['stdout'],'stderr':row['stderr'],'source_generation':'original compiled runner/artifact; corrected positive policy literal only','original_duration':None})
    assert len(results)==73 and results[-1]['result'][0]['recovery']['id']=='failure:positive-i32-margin-recovery'
    return results

def prepare_resume(data):
    adoption=resume_adoption(data);results=validate_retained(data,adoption);pending=remaining_jobs(data)
    prepared=RAW/'resume-preparation.json'
    write_json(prepared,{'adoption':adoption,'retained_validation':results,'remaining':[{'index':r['index'],'job':r['job'],'registry':pin(r['registry'])} for r in pending]})
    receipt={'status':'resume preparation and all73 retained output comparisons pass offline; no executable/build/Java/proof run','adoption':adoption,'offline_counts':{'retained_invocations':73,'actual_contexts':46,'admitted_actual_updates':44,'explicit_failure_recoveries_including_positive_guard':27},'remaining_counts':{'invocations':8,'negative_margin':1,'running':1,'nonempty_event':1,'edit_recovery':1,'dynamic_remaps':4},'remaining_indices':list(range(73,81)),'remaining_argument_sha256':sha([r['job']['commands'] for r in pending]),'remapped_registry':pin(RAW/'remapped.tsv'),'raw_preparation':pin(prepared),'raw_ignored':True,'caps':{'per_native_process':60,'full_import_kernel_if_later_authorized':60},'no_native_rebuild_or_reference_refresh':True}
    write_json(ROOT/'evidence/player-pose-world-artifact-adoption.json',receipt)
    print(json.dumps({'status':receipt['status'],'offline_counts':receipt['offline_counts'],'remaining_counts':receipt['remaining_counts'],'receipt':pin(ROOT/'evidence/player-pose-world-artifact-adoption.json')},indent=2))

def resume(data):
    sealed=json.loads((ROOT/'evidence/player-pose-world-artifact-adoption.json').read_text())
    adoption=resume_adoption(data);assert adoption==sealed['adoption'],'Reviewed adoption generation changed'
    results=validate_retained(data,adoption);pending=remaining_jobs(data)
    assert sealed['remaining_argument_sha256']==sha([r['job']['commands'] for r in pending])
    assert sealed['remapped_registry']==pin(RAW/'remapped.tsv')
    assert not any((RAW/f'resume-{i}-execution.json').exists() for i in range(73,81)),'Resume already attempted; explicit new review required'
    for row in pending:
        i=row['index'];job=row['job'];environment=dict(os.environ);environment['MC_BLOCK_REGISTRY']=str(row['registry'])
        out,err,execution=bounded([str(BINARY),'--gpu','off',*job['commands']],60,f'resume-{i}',environment)
        receipt={'status':'executed; comparison pending','index':i,'id':job['id'],'execution':execution,'registry':pin(row['registry']),'adoption_receipt':pin(ROOT/'evidence/player-pose-world-artifact-adoption.json'),'generation':adoption['current_dependency_pins']}
        target=RAW/f'resume-{i}-execution.json'
        # Persist before any status/parser/comparison assertions. Failure output
        # and exact command/cap/exit/duration remain even if the runner stops.
        write_json(target,receipt)
        try:
            assert execution['returncode']==0 and not execution['timed_out'],(execution,err)
            assert closure()==adoption['current_dependency_pins'],'Inputs changed during resumed native comparison'
            values,queries=lines(out);result=validate_job(data,job,values,queries)
            if i>=77:assert values[job['id']+'-before','view'].split('|')[2]=='2,3,1,0'
        except BaseException as error:
            receipt.update(status='first resumed failure; stop',failure=repr(error));write_json(target,receipt);raise
        receipt.update(status='passed',result=result);write_json(target,receipt)
        results.append({'index':i,'id':job['id'],'result':result,'execution_receipt':pin(target),'source_generation':'reviewed retained artifact adoption'})
    assert len(results)==81 and closure()==adoption['current_dependency_pins']
    artifact=RAW/'resumed-comparisons.json';write_json(artifact,results)
    summary={'status':'complete exact native pose/world/owner parity passes through retained-artifact adoption; independent kernel not run','original_build':adoption['original_build'],'binary':adoption['binary'],'emitted_c':adoption['emitted_c'],'adoption_receipt':pin(ROOT/'evidence/player-pose-world-artifact-adoption.json'),'original_first_failure':pin(ROOT/'evidence/player-pose-world-native-first-failure.json'),'current_dependency_pins':adoption['current_dependency_pins'],'original_dependency_sha256':adoption['original_dependency_sha256'],'reference':pin(REFERENCE),'raw_comparisons':pin(artifact),'raw_ignored':True,'counts':{'native_invocations':81,'retained_invocations_validated_without_rerun':73,'new_invocations':8,'actual_contexts':46,'admitted_updates':44,'failure_recoveries':28,'dynamic_remaps':4,'running_event_edit_jobs':3},'original_73_duration_receipts':adoption['original_73_duration_receipts'],'one_policy_expected_literal_corrected':adoption['expected_change'],'no_build_or_completed_native_rerun_or_reference_refresh':True}
    write_json(ROOT/'evidence/player-pose-world-native.json',summary)
    print(json.dumps({'status':summary['status'],'counts':summary['counts'],'receipt':pin(ROOT/'evidence/player-pose-world-native.json')},indent=2))

def generation2_paths():
    directory=ROOT/'build/player-pose-world-tests-generation2-artifacts'
    return directory,ROOT/'build/player-pose-world-tests-generation2',directory/'native-build.json'

def generation2_jobs(data):
    directory,_,_=generation2_paths();directory.mkdir(parents=True,exist_ok=True)
    jobs=[{'index':i,'job':job,'registry':REGISTRY} for i,job in enumerate(fixtures(data))]
    assert len(jobs)==77
    table=directory/'remapped.tsv';names=['minecraft:oak_planks','minecraft:dirt','minecraft:air','minecraft:stone']
    expected='block_protocol_id\tidentifier\tfirst_state_id\tstate_count\tdefault_state_id\tordered_properties_json\n'+''.join(f'{i}\t{name}\t{i}\t1\t{i}\t[]\n' for i,name in enumerate(names))
    if table.exists():assert table.read_text()==expected,'Generation2 remapped fixture changed'
    else:table.write_text(expected)
    for id in ['initial:STANDING','ceiling:2:None','signed_zero','far:30000000.125']:
        c=next(c for c in data['cases'] if c['id']==id)
        jobs.append({'index':len(jobs),'job':{'id':'remapped:'+id,'commands':[*scene(c),request(c,'remapped:'+id)],'actual':id},'registry':table})
    assert len(jobs)==81
    return jobs

def generation2_preflight(data):
    archive=ROOT/'build/player-pose-world-generation2-prior';manifest=archive/'archive-manifest.json'
    assert fingerprint(manifest)['sha256']=='040e66493f3a595fb102ecedab55f6c1ca4cf2c359f1edd5726cd1d6bc07ab6d'
    archived=json.loads(manifest.read_text());assert archived['file_count']==203
    mutable={'tests/player_pose_world.bend','tools/test_player_pose_world.py','docs/PLAYER_POSE_WORLD.md'}
    for row in archived['files']:
        original=row['original'];saved=row['archived']
        assert pin(ROOT/saved['path'])==saved,'Pre-correction archive changed'
        assert {k:v for k,v in saved.items() if k!='path'}=={k:v for k,v in original.items() if k!='path'}
        if original['path'] not in mutable:assert pin(ROOT/original['path'])==original,('Historical artifact changed',original['path'])
    old_harness=archive/'tests/player_pose_world.bend';old_runner=archive/'tools/test_player_pose_world.py'
    assert fingerprint(old_harness)['sha256']=='8f62a73204faab85e1202a32bb08bdb154f9bfab1424e20b47e284daad4768e9'
    assert fingerprint(old_runner)['sha256']=='48756716b5f5eb496cbc7032026319f46c9de0ed7ab9f1304dcc2b608728f51b'
    old_text=old_harness.read_text();old_stamp='C.admit(core,C.Developer{},Q.Stamp{0n,8,1n},C.TimeSet{333n}))'
    new_stamp='C.admit(core,C.Developer{},Q.Stamp{1n,8,1n},C.TimeSet{333n}))'
    assert old_text.count(old_stamp)==1 and ENTRY.read_text()==old_text.replace(old_stamp,new_stamp,1),'Harness changed beyond the one event stamp'
    before=ast.parse(old_runner.read_text());after=ast.parse(Path(__file__).read_text());dump=lambda n:ast.dump(n,include_attributes=False)
    old_functions={n.name:n for n in before.body if isinstance(n,ast.FunctionDef)}
    new_functions={n.name:n for n in after.body if isinstance(n,ast.FunctionDef)}
    expected_retained=copy.deepcopy(old_functions['retained']);literal_changes=0
    for node in ast.walk(expected_retained):
        if isinstance(node,ast.Constant) and node.value=='100,9,0,time,999;|applied,0,8,1,1;':
            node.value='100,9,0,time,999;|applied,1,8,1,1;';literal_changes+=1
    assert literal_changes==1
    for name,node in old_functions.items():
        assert dump(new_functions[name])==dump(expected_retained if name=='retained' else node),('Existing function changed',name)
    old_top=[n for n in before.body if not isinstance(n,(ast.FunctionDef,ast.If))]
    new_top=[n for n in after.body if not isinstance(n,(ast.FunctionDef,ast.If))]
    assert dump(ast.Module(body=old_top,type_ignores=[]))==dump(ast.Module(body=new_top,type_ignores=[])),'Original imports or globals changed'
    old_main=old_runner.read_text().rsplit("if __name__=='__main__':",1)[1]
    expected_main=old_main.replace('if args.prepare:prepare(data)','if args.prepare:prepare_generation2(data)',1).replace('elif args.kernel:kernel()','elif args.kernel:kernel_generation2()',1).replace('else:native(data,args.skip_build)','else:native_generation2(data,args.skip_build)',1)
    assert Path(__file__).read_text().rsplit("if __name__=='__main__':",1)[1]==expected_main,'Main changed beyond explicit fresh-generation routing'
    added=sorted(set(new_functions)-set(old_functions))
    assert added==['generation2_bounded','generation2_capture','generation2_jobs','generation2_paths','generation2_preflight','kernel_generation2','native_generation2','prepare_generation2'],added
    prior=json.loads((archive/'build/player-pose-world-tests-artifacts/native-build.json').read_text());pins=closure();wanted=dict(prior['dependency_pins'])
    for p in [ENTRY,Path(__file__).resolve()]:wanted[str(p.resolve())]=fingerprint(p)
    assert wanted==pins,'Compiled closure changed beyond harness and runner'
    prior_adoption=json.loads((archive/'evidence/player-pose-world-artifact-adoption.json').read_text())
    old_jobs=json.loads((archive/'build/player-pose-world-tests-artifacts/prepared-fixtures.json').read_text())
    assert old_jobs[72]['failure']=='world:collision-query-outside-i32';old_jobs[72]['failure']='world:collision-query-limit'
    jobs=generation2_jobs(data);assert [r['job'] for r in jobs[:77]]==old_jobs,'Commands or other expected fields changed'
    pending=json.loads((archive/'build/player-pose-world-tests-artifacts/resume-preparation.json').read_text())['remaining']
    assert [r['job'] for r in jobs[73:]]==[r['job'] for r in pending],'Pending commands or expectations changed'
    assert sha([r['job']['commands'] for r in jobs[:77]])==prior_adoption['adoption']['argument_sha256']
    assert sha(data['cases'])==prior_adoption['adoption']['expected_actual_fields_sha256']
    assert fingerprint(jobs[-1]['registry'])==fingerprint(ROOT/prior_adoption['remapped_registry']['path'])
    return {'archive_manifest':pin(manifest),'archived_file_count':203,'old_harness':pin(old_harness),'old_runner':pin(old_runner),'current_harness':pin(ENTRY),'current_runner':pin(Path(__file__)),'dependency_pins':pins,'prior_dependency_sha256':sha(prior['dependency_pins']),'dependency_sha256':sha(pins),'changed_compiled_paths':['tests/player_pose_world.bend','tools/test_player_pose_world.py'],'all_other31_compiled_pins_unchanged':True,'original_build':pin(BUILD),'original_binary':pin(BINARY),'original_emitted_c':prior['emitted_c'],'old_runner_ast_sha256':hashlib.sha256(dump(before).encode()).hexdigest(),'new_runner_ast_sha256':hashlib.sha256(dump(after).encode()).hexdigest(),'unchanged_existing_functions_except_retained_literal':True,'imports_and_globals_unchanged':True,'added_functions':added,'main_dispatch_change':'prepare/native/skip-build/kernel select separate generation2 paths; historical resume functions retained but generation checks fail closed','harness_change':{'function':'seed_event','old':'Q.Stamp{0n,8,1n}','new':'Q.Stamp{1n,8,1n}'},'expected_change':{'function':'retained','old':'applied,0,8,1,1;','new':'applied,1,8,1,1;'},'all81_command_arrays_and_other_expectations_unchanged':True,'argument_sha256':sha([r['job']['commands'] for r in jobs]),'first77_argument_sha256':sha([r['job']['commands'] for r in jobs[:77]]),'expected_actual_fields_sha256':sha(data['cases']),'remapped_registry':pin(jobs[-1]['registry']),'old73_duration_receipts':'absent; no values fabricated','prior_attempts':'Original native stopped at job72 comparison; retained resume jobs73/74 passed, job75 setup failed; jobs76..80 were never executed'}

def generation2_bounded(command,seconds,label,env=None):
    directory,_,_=generation2_paths();directory.mkdir(parents=True,exist_ok=True);start=time.monotonic()
    process=subprocess.Popen(command,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True,env=env)
    print(json.dumps({'phase':label,'pid':process.pid,'cap_seconds':seconds,'generation':2}),flush=True)
    timeout=False
    try:out,err=process.communicate(timeout=seconds)
    except subprocess.TimeoutExpired:
        timeout=True;os.killpg(process.pid,signal.SIGKILL);out,err=process.communicate()
    stdout=directory/(label+'.stdout');stderr=directory/(label+'.stderr');stdout.write_text(out);stderr.write_text(err)
    receipt={'command':command,'seconds':round(time.monotonic()-start,6),'returncode':process.returncode,'timed_out':timeout,'whole_process_group_cap':True,'stdout':pin(stdout),'stderr':pin(stderr)}
    write_json(directory/(label+'-execution.json'),{'status':'executed; assertion pending','execution':receipt})
    return out,err,receipt

def prepare_generation2(data):
    preflight=generation2_preflight(data);checks=[]
    for source in [ROOT/'src/player_pose_world.bend',ENTRY]:
        out,err,r=generation2_bounded([str(BEND),str(source),'--check-only'],30,source.parent.name+'-ordinary');checks.append(r)
        assert r['returncode']==0 and 'ALL PROOFS CHECK' in out,(r,err)
    assert preflight==generation2_preflight(data),'Preparation generation changed'
    directory,binary,build=generation2_paths();jobs=generation2_jobs(data)
    artifact=directory/'prepared-fixtures.json';write_json(artifact,[{'index':r['index'],'job':r['job'],'registry':pin(r['registry'])} for r in jobs])
    counts={'actual_contexts':len(data['cases']),'admitted':sum(c['admitted'] for c in data['cases']),'queries':sum(len(c['queries']) for c in data['cases']),'reads':sum(len(q['reads']) for c in data['cases'] for q in c['queries']),'first_yields':sum(q['first_yielded'] is not None for c in data['cases'] for q in c['queries']),'failure_recoveries':sum('failure' in r['job'] for r in jobs),'running_event_edit_jobs':3,'dynamic_remaps':4,'all_comparison_invocations':81}
    receipt={'status':'generation2 ordinary and archive/AST/data preflight pass; fresh native/kernel not run','preflight':preflight,'counts':counts,'checks':checks,'fixtures':pin(artifact),'raw_ignored':True,'fresh_binary_path':str(binary.relative_to(ROOT)),'fresh_build_path':str(build.relative_to(ROOT)),'original_binary_not_adopted_as_new':True,'planned_caps':{'one_installed_build_seconds':600,'each_native_comparison_seconds':60,'later_one_full_import_kernel_seconds':60},'each_execution_persisted_before_any_assertion':True,'first_failure_stops':True}
    write_json(ROOT/'evidence/player-pose-world-generation2-preparation.json',receipt)
    print(json.dumps({'status':receipt['status'],'counts':counts,'preparation':pin(ROOT/'evidence/player-pose-world-generation2-preparation.json')},indent=2))

def generation2_capture():
    directory,_,_=generation2_paths();directory=directory/'native-capture';directory.mkdir(parents=True,exist_ok=True);commands=directory/'commands.jsonl';commands.write_text('')
    wrapper=directory/'clang'
    source='#!'+sys.executable+'\n'+'''import json,os,pathlib,shutil,sys
directory=pathlib.Path(__DIRECTORY__)
args=sys.argv[1:]
with (directory/'commands.jsonl').open('a') as out:out.write(json.dumps(args,sort_keys=True,separators=(',',':'))+'\\n')
for i,arg in enumerate(args):
 p=pathlib.Path(arg)
 if p.suffix.lower()=='.c' and p.is_file():shutil.copyfile(p,directory/('source-'+str(i)+'.c'))
os.execv('/usr/bin/clang',['/usr/bin/clang',*args])
'''.replace('__DIRECTORY__',repr(str(directory)))
    wrapper.write_text(source);wrapper.chmod(0o700);return wrapper,commands

def native_generation2(data,skip):
    prepared_path=ROOT/'evidence/player-pose-world-generation2-preparation.json';prepared=json.loads(prepared_path.read_text())
    preflight=generation2_preflight(data);assert preflight==prepared['preflight'],'Reviewed generation2 preparation changed'
    pins=closure();directory,binary,build_path=generation2_paths();jobs=generation2_jobs(data)
    assert prepared['fixtures']==pin(directory/'prepared-fixtures.json'),'Prepared generation2 fixture file changed'
    assert not any((directory/f'case-{i}-execution.json').exists() for i in range(81)),'Generation2 comparisons already attempted; explicit review required'
    if skip:
        build=json.loads(build_path.read_text());assert build['dependency_pins']==pins and build['binary']==pin(binary),'Generation2 retained native changed'
    else:
        assert not build_path.exists() and not binary.exists(),'Generation2 emission already attempted; explicit review required'
        wrapper,commands=generation2_capture();env=dict(os.environ);env['CC']=str(wrapper)
        _,err,r=generation2_bounded([str(BEND),str(ENTRY),'-o',str(binary)],600,'native',env)
        command_rows=[json.loads(row) for row in commands.read_text().splitlines()]
        copied=[pin(p) for p in sorted(wrapper.parent.glob('source-*.c'))]
        build={'status':'failed','generation':2,'execution':r,'preparation':pin(prepared_path),'prior_lineage':{'archive_manifest':preflight['archive_manifest'],'original_build':preflight['original_build'],'original_binary':preflight['original_binary']},'dependency_pins':pins,'compiler':pin(BEND),'clang':pin(Path('/usr/bin/clang')),'wrapper':pin(wrapper),'clang_commands':pin(commands),'clang_commands_sha256':sha(command_rows),'clang_command_seal':'canonical UTF-8 JSON ensure_ascii=False sorted keys compact separators no newline','emitted_c':copied}
        if r['returncode']==0 and binary.exists():
            assert closure()==pins and copied,'Native sources changed or C capture missing';build.update(status='compiled',binary=pin(binary))
        write_json(build_path,build);assert build['status']=='compiled',err[-8000:]
    results=[];executions=[]
    for row in jobs:
        i=row['index'];job=row['job'];environment=dict(os.environ);environment['MC_BLOCK_REGISTRY']=str(row['registry'])
        out,err,execution=generation2_bounded([str(binary),'--gpu','off',*job['commands']],60,f'case-{i}',environment)
        target=directory/f'case-{i}-execution.json'
        receipt={'status':'executed; comparison pending','generation':2,'index':i,'id':job['id'],'execution':execution,'registry':pin(row['registry']),'preparation':pin(prepared_path),'build_manifest':pin(build_path),'dependency_pins_sha256':sha(pins)}
        write_json(target,receipt)
        try:
            assert execution['returncode']==0 and not execution['timed_out'],(execution,err)
            assert closure()==pins,'Inputs changed during generation2 comparison'
            values,queries=lines(out);result=validate_job(data,job,values,queries)
            if i>=77:assert values[job['id']+'-before','view'].split('|')[2]=='2,3,1,0'
        except BaseException as error:
            receipt.update(status='first generation2 failure; stop',failure=repr(error));write_json(target,receipt)
            write_json(ROOT/'evidence/player-pose-world-generation2-first-failure.json',{'status':receipt['status'],'index':i,'id':job['id'],'receipt':pin(target),'completed_indices':list(range(i)),'unexecuted_indices':list(range(i+1,81)),'build_manifest':pin(build_path),'binary':pin(binary),'preparation':pin(prepared_path),'no_automatic_retry_or_kernel':True});raise
        receipt.update(status='passed',result=result);write_json(target,receipt)
        results.append({'index':i,'id':job['id'],'result':result,'execution_receipt':pin(target)});executions.append(execution)
    assert len(results)==81 and closure()==pins
    artifact=directory/'comparisons.json';write_json(artifact,{'results':results,'executions':executions})
    summary={'status':'generation2 all81 exact native pose/world/owner comparisons pass; independent kernel not run','generation':2,'build_manifest':pin(build_path),'binary':pin(binary),'emitted_c':build['emitted_c'],'dependency_pins':pins,'preparation':pin(prepared_path),'original_failures_preserved':{'native':pin(ROOT/'evidence/player-pose-world-native-first-failure.json'),'resume':pin(ROOT/'evidence/player-pose-world-resume-first-failure.json')},'reference':pin(REFERENCE),'raw_comparisons':pin(artifact),'raw_ignored':True,'counts':{'native_invocations':81,'actual_contexts':46,'admitted_updates':44,'scale_refusals':2,'failure_recoveries':28,'dynamic_remaps':4,'running_event_edit_jobs':3},'argument_sha256':preflight['argument_sha256'],'expected_actual_fields_sha256':preflight['expected_actual_fields_sha256'],'comparison_policy':'Unchanged validate_job/raw-word comparators; event Applied tick1 corrected to match the admitted fixture; complete Body/pose/eye, View/cache, section trie RLE, clocks/pending/events, exact ordered query/read/first-shape rows','no_prior_output_adopted_as_new':True}
    write_json(ROOT/'evidence/player-pose-world-native.json',summary)
    print(json.dumps({'status':summary['status'],'counts':summary['counts'],'receipt':pin(ROOT/'evidence/player-pose-world-native.json')},indent=2))

def kernel_generation2():
    native=json.loads((ROOT/'evidence/player-pose-world-native.json').read_text());pins=closure();directory,binary,build=generation2_paths()
    assert native['generation']==2 and native['counts']['native_invocations']==81 and native['dependency_pins']==pins
    assert native['binary']==pin(binary) and native['build_manifest']==pin(build)
    assert not (directory/'kernel-execution.json').exists(),'Generation2 kernel already attempted; no retry'
    out,err,r=generation2_bounded([str(BEND),str(ENTRY),'--verdict'],60,'kernel')
    receipt={'status':'passed' if r['returncode']==0 and 'ALL PROOFS CHECK' in out else 'inconclusive' if r['timed_out'] else 'failed','generation':2,'execution':r,'dependency_pins':pins,'generation_unchanged':pins==closure(),'native_receipt':pin(ROOT/'evidence/player-pose-world-native.json'),'scope':'One full test import closure including PPW laws; no projection or standalone repeat'}
    write_json(ROOT/'evidence/player-pose-world-kernel.json',receipt);print(json.dumps({'status':receipt['status'],'seconds':r['seconds']}));assert receipt['status']=='passed' and receipt['generation_unchanged'],err[-8000:]

if __name__=='__main__':
    p=argparse.ArgumentParser();g=p.add_mutually_exclusive_group(required=True)
    for option in ['prepare','native','skip-build','kernel','prepare-resume','resume']:g.add_argument('--'+option,action='store_true')
    args=p.parse_args();data=json.loads(REFERENCE.read_text())
    if args.prepare:prepare_generation2(data)
    elif args.kernel:kernel_generation2()
    elif args.prepare_resume:prepare_resume(data)
    elif args.resume:resume(data)
    else:native_generation2(data,args.skip_build)
