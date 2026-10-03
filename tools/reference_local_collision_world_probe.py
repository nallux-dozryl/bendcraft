#!/usr/bin/env python3
"""Direct pinned sneak-edge world reads under untouched actual BlockCollisions.

Frozen LC/LI receiver sources are copied in memory. Only observer metadata and
declared finite-world state choices differ; Java production methods determine
every movement, noCollision result and ordered read/shape trace.
"""
from __future__ import annotations
import argparse, base64, copy, hashlib, json, math, re, struct, subprocess, time, zipfile
from collections import Counter
from pathlib import Path
from reference_inventory import ROOT,JAVA,canonical,fingerprint
from reference_model_probe import CLIENT,verified_client_classpath
import reference_local_collision_probe as LC

OUTPUT=ROOT/'reference/local_collision_world.json'
CLASS='net.minecraft.fixture.LocalCollisionWorldReceiverFixture'
RAW=ROOT/'build/local-collision-world-reference'
FROZEN_LC_REFERENCE='549a49a0e1b8cfb8e9790023cabb718e1d8f8c2e9ebdd2bb6be57603a93eb1da'
FROZEN_LC_SOURCE='6f2fc332d15358118488b715de467a1ebd53739574488f8de8efb17a1dcbfbce'
SUPPORTED={'air','stone','dirt','oak_planks'}

def sha(v):return hashlib.sha256(canonical(v)).hexdigest()
def save(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(canonical(v)+b'\n')

def derive_source():
    assert hashlib.sha256(LC.SOURCE.encode()).hexdigest()==FROZEN_LC_SOURCE,'Frozen LC receiver source changed'
    s=LC.SOURCE.replace('LocalCollisionReceiverFixture','LocalCollisionWorldReceiverFixture')
    old='public BlockState getBlockState(BlockPos p){BlockState b=super.getBlockState(p);if(capture&&events!=null)events.add(Map.of("method","getBlockState","query",query,"position",List.of(p.getX(),p.getY(),p.getZ()),"block_id",BuiltInRegistries.BLOCK.getKey(b.getBlock()).toString()));return b;}'
    new='public BlockState getBlockState(BlockPos p){BlockState b=super.getBlockState(p);if(capture&&events!=null&&query>=0){int ordinal=0;for(Map<String,Object> prior:events)if(prior.get("method").equals("getBlockState")&&prior.get("query").equals(query))ordinal++;Map<String,Object> e=new TreeMap<>();e.put("method","getBlockState");e.put("query",query);e.put("ordinal",ordinal);e.put("position",List.of(p.getX(),p.getY(),p.getZ()));e.put("block_id",BuiltInRegistries.BLOCK.getKey(b.getBlock()).toString());e.put("state_id",Block.getId(b));e.put("state_name",b.toString());events.add(e);}return b;}'
    assert s.count(old)==1;s=s.replace(old,new,1)
    old='if(capture){List<List<String>> raw=new ArrayList<>()'
    assert s.count(old)==1;s=s.replace(old,'if(capture&&q>=0){List<List<String>> raw=new ArrayList<>()',1)
    old='case "stone"->Blocks.STONE.defaultBlockState();'
    assert s.count(old)==1;s=s.replace(old,old+'case "dirt"->Blocks.DIRT.defaultBlockState();case "oak_planks"->Blocks.OAK_PLANKS.defaultBlockState();',1)
    return s.replace('LOCAL_COLLISION_JSON:','LOCAL_COLLISION_WORLD_JSON:').replace('LOCAL_COLLISION_RUNTIME:','LOCAL_COLLISION_WORLD_RUNTIME:')

SOURCE=derive_source()

def is_finite(raw):
    return math.isfinite(struct.unpack('>f' if len(raw)==8 else '>d',bytes.fromhex(raw))[0])

def admission(case):
    i=case['initial'];finite=all(is_finite(r) for r in case['movement']+i['position']+i['input_f32_bits']+[i['yaw_f32_bits'],i['fall_distance_f64_bits'],i['step_attribute_f64_bits']])
    fullcube=all(w['block'] in SUPPORTED for w in i['world_writes'])
    neutral=finite and fullcube and not i['flying'] and case['mover'] in ('SELF','PLAYER')
    return {'finite_input':finite,'fullcube_states':fullcube,'neutral_helper_context':neutral,
            'scope':'Input admission classification only; never supplies production movement/query expectations'}

def inputs():
    backoff=[];excluded=[]
    for c in LC.inputs()['backoff']:
        a=admission(c)
        if not a['finite_input'] or not a['fullcube_states']:
            excluded.append({'id':c['id'],'reason':'nonfinite movement or slab shape outside finite fullcube world admission','admission':a});continue
        c=copy.deepcopy(c);c['admission']=a;backoff.append(c)
    base=next(c for c in backoff if c['id']=='backoff:edge:6:3')
    writes=[
        ('all_stone',[{'position':[x,0,z],'block':'stone'} for x in range(-2,3) for z in range(-2,3)]),
        ('all_dirt',[{'position':[x,0,z],'block':'dirt'} for x in range(-2,3) for z in range(-2,3)]),
        ('all_planks',[{'position':[x,0,z],'block':'oak_planks'} for x in range(-2,3) for z in range(-2,3)]),
        ('all_air',[{'position':[x,0,z],'block':'air'} for x in range(-2,3) for z in range(-2,3)]),
        ('corner_hole',[{'position':[2,0,2],'block':'air'}]),
        ('mixed_edge',[{'position':[2,0,2],'block':'dirt'},{'position':[2,0,1],'block':'oak_planks'},{'position':[1,0,2],'block':'air'}]),
        ('sequential_replace',[{'position':[2,0,2],'block':'air'},{'position':[2,0,2],'block':'dirt'},{'position':[2,0,2],'block':'oak_planks'},{'position':[2,0,2],'block':'stone'}]),
    ]
    for name,world in writes:
        c=copy.deepcopy(base);c['id']='world:'+name;c['initial']['world_writes']=world;c['admission']=admission(c);backoff.append(c)
    for x,name in [(3.299999999,'near_positive_edge'),(3.3,'positive_edge'),(-2.3,'negative_edge')]:
        c=copy.deepcopy(base);c['id']='world:'+name;c['initial']['position']=[LC.db(x),LC.db(1),LC.db(.5)];c['movement']=[LC.db(1 if x>0 else -1),LC.db(0),LC.db(0)];c['admission']=admission(c);backoff.append(c)
    return {'acos':[],'minor':[],'backoff':backoff},excluded

def dependencies():
    assert fingerprint(LC.OUTPUT)['sha256']==FROZEN_LC_REFERENCE,'Frozen LC reference bytes changed'
    return {'lc_producer':fingerprint(Path(LC.__file__)),'lc_reference':fingerprint(LC.OUTPUT),
            'lc_source_sha256':hashlib.sha256(LC.SOURCE.encode()).hexdigest(),'li_dependency':LC.dependency_pin(),
            'li_receiver_templates':{n:hashlib.sha256(s.encode()).hexdigest() for n,s in LC.LI.RECEIVER_SOURCES.items()},
            'li_launcher_sha256':hashlib.sha256(LC.LI.RECEIVER_LAUNCHER.encode()).hexdigest()}

def sources(cases):
    s=LC.LI.receiver_sources();encoded=base64.b64encode(canonical(cases)).decode()
    s[CLASS]=SOURCE.replace('__INPUT_BASE64__',LC.LI.java_string(encoded));return s

def source_inventory():
    result=LC.source_inventory()
    wanted={'Cursor3D','advance','getNextType','nextX','nextY','nextZ','intersects','floor','hasLargeCollisionShape','getCollisionShape','getId'}
    with zipfile.ZipFile(CLIENT) as jar:
        for owner in ['net.minecraft.core.Cursor3D','net.minecraft.world.phys.AABB','net.minecraft.util.Mth','net.minecraft.world.level.block.state.BlockBehaviour$BlockStateBase','net.minecraft.world.level.block.Block']:
            s=subprocess.run([str(JAVA.parent/'javap'),'-classpath',str(CLIENT),'-c','-p',owner],capture_output=True,text=True,check=True).stdout
            methods=[]
            for sig,body in re.findall(r'^  ((?:public|protected|private|static)[^\n]*?\([^\n]*\);)\n(.*?)(?=^  (?:public|protected|private|static)|\Z)',s,re.M|re.S):
                name=re.search(r'([\w$<>]+)\([^\n]*\);$',sig)
                if name and name[1] in wanted:methods.append({'signature':sig,'bytecode_text_sha256':hashlib.sha256(body.encode()).hexdigest(),'direct_call_references':sorted(set(re.findall(r'// (?:InterfaceMethod|Method) (.+)',body))),'field_references':sorted(set(re.findall(r'// Field (.+)',body)))})
            entry=owner.replace('.','/')+'.class';prior=result.get(owner,{}).get('methods',[])
            existing={m['signature'] for m in methods};methods+= [m for m in prior if m['signature'] not in existing]
            result[owner]={'class_entry':entry,'class_sha256':hashlib.sha256(jar.read(entry)).hexdigest(),'complete_bytecode_text_sha256':hashlib.sha256(s.encode()).hexdigest(),'methods':methods}
    return result

def collect(cases,rows):
    projected=LC.collect(cases,rows)['backoff']
    for case in projected:
        queries=[]
        for entry in [e for e in case['query_events'] if e['method']=='noCollision_entry']:
            q=entry['query'];events=[e for e in case['query_events'] if e['query']==q]
            exits=[e for e in events if e['method']=='noCollision_exit'];assert len(exits)==1
            reads=[{k:e[k] for k in ('ordinal','position','block_id','state_id','state_name')} for e in events if e['method']=='getBlockState']
            assert [e['ordinal'] for e in reads]==list(range(len(reads)))
            shapes=[e['boxes'] for e in events if e['method']=='actual_block_collision_shape_yield']
            assert len(shapes)<=1,'Actual noBlockCollision must stop at first yielded nonempty shape'
            queries.append({'index':q,'box':entry['box'],'no_collision':exits[0]['result'],'reads':reads,
                            'first_yielded_shape_boxes':shapes[0] if shapes else None,'actual_yielded_shapes':shapes})
        case['queries']=queries;case.pop('no_collision_queries')
        assert all(e['query']>=0 for e in case['query_events']),'Read outside active noCollision leaked'
        case.pop('query_events')
    return projected

def boundary():
    return {'decisive':'Untouched actual Player.maybeBackOffFromEdge on normal LocalPlayer; actual Level.noCollision calls super and actual BlockCollisions performs ordered reads/cursor guards/fullcube intersection/first-yield short circuit.',
            'derivation':'In-memory frozen LC SOURCE copy: fixture-class/prefix rename, only-active-query read metadata (ordinal/state ID/name), iterator metadata guard, finite dirt/oak_planks world-state choices. No production classes, cursor, predicate or arithmetic transformed.',
            'reads':'Actual getBlockState return positions/state IDs/names are recorded in event order while query>=0. No read order, state result, shape or Boolean is inferred from boxes or a host algorithm.',
            'fixture':'Exactly frozen four LI external service substitutes; normal actual ClientLevel and LocalPlayer constructors; 25 stone floor blocks, otherwise air, with explicit sequential air/stone/dirt/oak_planks writes. Actual actor storage empty and real border default.',
            'observer':'Plain frozen finite Level/LocalPlayer results and projected fields match observer subclasses; helper and noCollision observers call super; wrapped original iterator hasNext/next order retained.',
            'admission':'Finite fullcube cases only; unsupported flight/mover guard contexts retained with explicit neutral_helper_context flags; actual slab and nonfinite-Y source cases explicitly excluded.',
            'scope':'Ordered finite fullcube world-read and sneak-edge helper observations; no full Entity.move/tick/other collision-shape/world-effect parity claim.'}

def counts(cases):
    return {'cases':len(cases),'neutral_cases':sum(c['admission']['neutral_helper_context'] for c in cases),
            'queries':sum(len(c['queries']) for c in cases),'reads':sum(len(q['reads']) for c in cases for q in c['queries']),
            'first_yields':sum(q['first_yielded_shape_boxes'] is not None for c in cases for q in c['queries'])}

def compact_report(path,e):
    assert sha(e['observations'])==e['observations_sha256']
    raw=RAW/f'{path.stem}.full.json';save(raw,e)
    report={k:v for k,v in e.items() if k not in ('observations','raw_execution','source','provenance','execution','substituted_external_types')}
    report.update(evidence_format='local-collision-world-summary-v1',raw_report={'path':str(raw.relative_to(ROOT)),**fingerprint(raw)},storage_writer=fingerprint(Path(__file__)),observation_count=len(e['observations']))
    report['source_inventory']={'canonical_sha256':sha(e['source']),'classes':{n:v['class_sha256'] for n,v in e['source'].items()},'methods_sha256':{n:sha(v['methods']) for n,v in e['source'].items()}}
    p=e['provenance'];report['provenance']={k:v for k,v in p.items() if k not in ('libraries','missing_other_platform_natives')};report['provenance_sha256']=sha(p)
    for key in ('libraries','missing_other_platform_natives'):report['provenance'][key+'_count']=len(p[key]);report['provenance'][key+'_sha256']=sha(p[key])
    report['substituted_external_types']={n:{'source_sha256':v['source_sha256']} for n,v in e['substituted_external_types'].items()}
    execution=copy.deepcopy(e['execution']);execution['command_sha256']=sha(execution['command']);i=execution['command'].index('--class-path')+1;execution['classpath_sha256']=hashlib.sha256(execution['command'][i].encode()).hexdigest();execution['command'][i]='<verified pinned classpath; complete command in raw_report>'
    if execution['returncode']==0:execution.pop('failure',None);execution.pop('stderr_tail',None)
    report['execution']=execution;save(path,report);verify_report(path);return report

def verify_report(path):
    s=json.loads(path.read_text());raw=ROOT/s['raw_report']['path'];assert fingerprint(raw)=={k:v for k,v in s['raw_report'].items() if k!='path'};e=json.loads(raw.read_text())
    assert sha(e['observations'])==e['observations_sha256']==s['observations_sha256'];assert len(e['observations'])==s['observation_count'];assert sha(e['source'])==s['source_inventory']['canonical_sha256'];assert sha(e['provenance'])==s['provenance_sha256']
    actual=e['raw_execution']['loaded_official_classes'];assert sha(actual)==s['loaded_official_class_tree_sha256'];assert len(actual)==s['loaded_official_class_count']
    for stream in ('stdout','stderr'):assert hashlib.sha256(e['raw_execution'][stream].encode()).hexdigest()==s['execution'][stream+'_sha256']
    assert sha(e['execution']['command'])==s['execution']['command_sha256'];return s

def run(cases,label):
    dep=dependencies();classpath,prov=verified_client_classpath();ss=sources(cases);payload={'sources':ss,'client_jar':str(CLIENT),'mode':'world'};encoded=base64.b64encode(canonical(payload)).decode()
    launcher=LC.LI.RECEIVER_LAUNCHER.replace('net.minecraft.fixture.LocalInputReceiverFixture',CLASS).replace('Base64.getDecoder().decode(args[0])','Base64.getDecoder().decode('+LC.LI.java_string(encoded)+')',1)
    command=[str(JAVA),'--source','25','--class-path',':'.join(map(str,classpath)),'/dev/stdin'];start=time.monotonic();p=subprocess.run(command,input=launcher,capture_output=True,text=True)
    def parse(prefix):return [json.loads(s[len(prefix):]) for s in p.stdout.splitlines() if s.startswith(prefix)]
    rows=parse('LOCAL_COLLISION_WORLD_JSON:');loaded=parse('LOCAL_INPUT_CLASSES:');runtime=parse('LOCAL_COLLISION_WORLD_RUNTIME:');inventory=source_inventory()
    assert p.returncode==0,'Actual fixture failure: '+'\n'.join(x for x in p.stdout.splitlines() if not x.startswith('LOCAL_INPUT_CLASSES:'))[-7000:]+p.stderr[-2000:]
    assert len(loaded)==len(runtime)==1
    for n,h in loaded[0].items():
        if n in inventory and not n.startswith('java.'):assert h==inventory[n]['class_sha256']
    for n,h in runtime[0].items():inventory[n]['class_sha256']=h
    projected=collect(cases,rows)
    e={'schema_version':1,'pin':'26.3','status':'passed','producer_at_execution':fingerprint(Path(__file__)),'dependency':dep,'provenance':prov,'source':inventory,'boundary':boundary(),
       'source_sha256':hashlib.sha256(SOURCE.encode()).hexdigest(),'expanded_source_sha256':{n:hashlib.sha256(s.encode()).hexdigest() for n,s in ss.items()},'launcher_sha256':hashlib.sha256(LC.LI.RECEIVER_LAUNCHER.encode()).hexdigest(),
       'substituted_external_types':{n:{'source':s,'source_sha256':hashlib.sha256(s.encode()).hexdigest()} for n,s in LC.LI.RECEIVER_SOURCES.items() if n!='net.minecraft.fixture.LocalInputReceiverFixture'},
       'loaded_official_classes':{n:h for n,h in loaded[0].items() if n in inventory},'loaded_official_class_count':len(loaded[0]),'loaded_official_class_tree_sha256':sha(loaded[0]),'runtime_classes':runtime[0],
       'observations':rows,'observations_sha256':sha(rows),'counts':counts(projected),'plain_observer_projected_parity':True,'projected_helper_state_unchanged':True,
       'execution':{'command':command,'reproduce':'PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_local_collision_world_probe.py --'+('rerun' if label=='independent' else 'extract'),'seconds':round(time.monotonic()-start,6),'returncode':p.returncode,'input_sha256':sha(payload),'compiled_launcher_sha256':hashlib.sha256(launcher.encode()).hexdigest(),'stdout_sha256':hashlib.sha256(p.stdout.encode()).hexdigest(),'stderr_sha256':hashlib.sha256(p.stderr.encode()).hexdigest(),'stderr_tail':p.stderr[-3000:]},
       'raw_execution':{'stdout':p.stdout,'stderr':p.stderr,'loaded_official_classes':loaded[0]}}
    path=ROOT/f'evidence/local-collision-world-reference-{label}.json';compact_report(path,e);return projected,e,path

def extract(debug=False):
    cases,excluded=inputs()
    if debug:cases['backoff']=cases['backoff'][:2]
    projected,e,path=run(cases,'debug' if debug else 'actual')
    if debug:return {'status':'passed','evidence':fingerprint(path),'counts':e['counts']}
    d={k:e[k] for k in ('schema_version','pin','dependency','provenance','source','boundary','source_sha256','expanded_source_sha256','launcher_sha256','loaded_official_classes','loaded_official_class_count','loaded_official_class_tree_sha256','runtime_classes')}
    d.update(inputs_sha256=sha(cases),cases=projected,excluded_cases=excluded,counts=e['counts'],observations_sha256=sha(projected));save(OUTPUT,d)
    return {'status':'passed','reference':fingerprint(OUTPUT),'counts':e['counts'],'excluded_cases':excluded,'evidence':fingerprint(path)}

def verify_data(d,prov,inventory):
    cases,excluded=inputs();assert d['pin']=='26.3' and d['schema_version']==1;assert d['inputs_sha256']==sha(cases);assert d['excluded_cases']==excluded;assert d['source_sha256']==hashlib.sha256(SOURCE.encode()).hexdigest();assert d['expanded_source_sha256']=={n:hashlib.sha256(s.encode()).hexdigest() for n,s in sources(cases).items()};assert d['launcher_sha256']==hashlib.sha256(LC.LI.RECEIVER_LAUNCHER.encode()).hexdigest();assert d['dependency']==dependencies();assert d['provenance']==prov
    r=LC.runtime_inventory();assert d['runtime_classes']==r
    for n,h in r.items():inventory[n]['class_sha256']=h
    assert d['source']==inventory;assert d['boundary']==boundary();assert d['observations_sha256']==sha(d['cases']);assert d['counts']==counts(d['cases'])
    for n,h in d['loaded_official_classes'].items():assert inventory[n]['class_sha256']==h

def verify(selftest=False):
    d=json.loads(OUTPUT.read_text());_,prov=verified_client_classpath();inv=source_inventory();verify_data(d,prov,inv);result={'status':'passed','producer':fingerprint(Path(__file__)),'reference':fingerprint(OUTPUT),'counts':d['counts'],'scope':'Integrity/provenance only; no new actual edge helper run'}
    if selftest:
        checks=[]
        for label,path in [('client',['provenance','client','sha256']),('runtime',['provenance','java','sha256']),('library',['provenance','libraries',0,'sha256']),('source',['source_sha256']),('read',['cases',0,'queries',0,'reads',0,'state_id'])]:
            v=copy.deepcopy(d);o=v
            for k in path[:-1]:o=o[k]
            o[path[-1]]='injected-mismatch'
            try:verify_data(v,prov,inv)
            except AssertionError:checks.append({'injection':label,'rejected':True})
            else:raise AssertionError('Injection accepted: '+label)
        result['failure_injections']=checks
    save(ROOT/'evidence/local-collision-world-reference-integrity.json',result);return result

def rerun():
    d=json.loads(OUTPUT.read_text());_,p=verified_client_classpath();verify_data(d,p,source_inventory());cases,_=inputs();projected,e,path=run(cases,'independent');assert projected==d['cases'];assert e['loaded_official_class_tree_sha256']==d['loaded_official_class_tree_sha256'];assert e['runtime_classes']==d['runtime_classes'];e['independent_actual_observation_parity']=True;e['reference_compared']=fingerprint(OUTPUT);compact_report(path,e);return {'status':'passed','reference':fingerprint(OUTPUT),'evidence':fingerprint(path),'independent_actual_observation_parity':True}

def main():
    p=argparse.ArgumentParser();p.add_argument('--extract',action='store_true');p.add_argument('--debug',action='store_true');p.add_argument('--verify-existing',action='store_true');p.add_argument('--selftest',action='store_true');p.add_argument('--rerun',action='store_true');a=p.parse_args()
    if a.verify_existing or a.selftest:r=verify(a.selftest)
    elif a.rerun:r=rerun()
    elif a.extract or a.debug:r=extract(a.debug)
    else:p.error('Select --extract, --verify-existing, --selftest or --rerun')
    print(json.dumps(r,indent=2))
if __name__=='__main__':main()
