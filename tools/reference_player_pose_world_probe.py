#!/usr/bin/env python3
"""Fresh actual pose queries with ordered state-ID reads and first yields.

Private copy of frozen PlayerPose receiver code; official gameplay bytes and
normal constructors remain untouched. No world query order/result is computed
by Python. Full receiver traces remain under ignored build/.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import time
import zipfile

from reference_inventory import ROOT, JAVA, canonical, fingerprint, write_json
from reference_model_probe import CLIENT, verified_client_classpath
import reference_player_pose_probe as PP

RAW=ROOT/'build/player-pose-world-reference'
CLASS='net.minecraft.fixture.PlayerPoseWorldReceiverFixture'
FROZEN_PP_TOOL='24f1ea6e5812e028b2fbab8aa70b89b8a5997bd2a9dbbda4213c00cfa8295ca0'
FROZEN_PP_REFERENCE='9990b80a6d23a6a6463728bcb0ca9876cc9b8e7e90e374814f34aad78e8914a3'

def sha(value):return hashlib.sha256(canonical(value)).hexdigest()

def source():
    assert fingerprint(Path(PP.__file__))['sha256']==FROZEN_PP_TOOL,'Frozen PP producer changed'
    value=PP.SOURCE.replace('PlayerPoseReceiverFixture','PlayerPoseWorldReceiverFixture')
    old='if(capture&&events!=null)events.add(Map.of("method","block_read","query",query,"position",List.of(p.getX(),p.getY(),p.getZ()),"identifier",BuiltInRegistries.BLOCK.getKey(v.getBlock()).toString()));'
    new='if(capture&&events!=null&&query>=0){int ordinal=0;for(Map<String,Object> prior:events)if(prior.get("method").equals("block_read")&&prior.get("query").equals(query))ordinal++;Map<String,Object> row=new TreeMap<>();row.put("method","block_read");row.put("query",query);row.put("ordinal",ordinal);row.put("position",List.of(p.getX(),p.getY(),p.getZ()));row.put("identifier",BuiltInRegistries.BLOCK.getKey(v.getBlock()).toString());row.put("state_id",Block.getId(v));row.put("state_name",v.toString());events.add(row);}'
    assert value.count(old)==1;value=value.replace(old,new,1)
    return value.replace('PLAYER_POSE_JSON:','PLAYER_POSE_WORLD_JSON:')

SOURCE=source()

def run_java(values,label):
    classpath,provenance=verified_client_classpath()
    sources=dict(PP.LI.receiver_sources({'keyboard':[],'vectors':[],'receivers':[],'ai_step':[]}))
    sources[CLASS]=SOURCE.replace('__INPUT_BASE64__',json.dumps(base64.b64encode(canonical(values)).decode()))
    payload={'sources':sources,'client_jar':str(CLIENT),'mode':'poses'}
    encoded=base64.b64encode(canonical(payload)).decode()
    launcher=PP.LI.RECEIVER_LAUNCHER.replace('loader.loadClass("net.minecraft.fixture.LocalInputReceiverFixture")',f'loader.loadClass("{CLASS}")',1)
    launcher=launcher.replace('Base64.getDecoder().decode(args[0])','Base64.getDecoder().decode(String.join("",new String[]{'+','.join(json.dumps(encoded[i:i+6144]) for i in range(0,len(encoded),6144))+'}))',1)
    command=[str(JAVA),'--source','25','--class-path',':'.join(map(str,classpath)),'/dev/stdin']
    RAW.mkdir(parents=True,exist_ok=True)
    write_json(RAW/f'{label}-sources.json',sources);(RAW/f'{label}-launcher.java').write_text(launcher)
    start=time.monotonic();p=subprocess.Popen(command,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
    try:out,err=p.communicate(launcher,timeout=120)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid,signal.SIGKILL);out,err=p.communicate();raise RuntimeError('120s actual Java cap')
    (RAW/f'{label}-stdout.txt').write_text(out);(RAW/f'{label}-stderr.txt').write_text(err)
    assert p.returncode==0,err[-8000:]
    rows=[json.loads(line[len('PLAYER_POSE_WORLD_JSON:'):]) for line in out.splitlines() if line.startswith('PLAYER_POSE_WORLD_JSON:')]
    classes=[json.loads(line[len('LOCAL_INPUT_CLASSES:'):]) for line in out.splitlines() if line.startswith('LOCAL_INPUT_CLASSES:')]
    assert len(classes)==1
    with zipfile.ZipFile(CLIENT) as jar:
        for name,digest in classes[0].items():assert hashlib.sha256(jar.read(name.replace('.','/')+'.class')).hexdigest()==digest,name
    critical=['net.minecraft.client.player.LocalPlayer','net.minecraft.world.entity.player.Player','net.minecraft.world.entity.Avatar','net.minecraft.world.entity.LivingEntity','net.minecraft.world.entity.Entity','net.minecraft.world.entity.EntityDimensions','net.minecraft.client.multiplayer.ClientLevel','net.minecraft.world.level.BlockCollisions','net.minecraft.core.Cursor3D','net.minecraft.world.level.CollisionGetter']
    assert all(name in classes[0] for name in critical)
    write_json(RAW/f'{label}-raw.json',{'rows':rows,'loaded_official_classes':classes[0],'classpath':provenance})
    return rows,{'seconds':round(time.monotonic()-start,6),'returncode':p.returncode,'process_group_cap_seconds':120,'command':command,'loaded_official_class_count':len(classes[0]),'loaded_official_class_tree_sha256':sha(classes[0]),'critical_classes':{name:classes[0][name] for name in critical},'sources_sha256':sha(sources),'launcher_sha256':hashlib.sha256(launcher.encode()).hexdigest(),'raw_artifact':fingerprint(RAW/f'{label}-raw.json'),'stdout':fingerprint(RAW/f'{label}-stdout.txt'),'stderr':fingerprint(RAW/f'{label}-stderr.txt')}

def collect(values,rows):
    projected=PP.collect(values,rows)
    prior=json.loads((ROOT/'reference/player_pose.json').read_text())
    assert projected['metadata']==prior['metadata'] and projected['cases']==prior['cases'],'Observer-only derivation changed frozen pose expectations'
    result=[]
    for case in projected['cases']:
        actual=next(row for row in rows if row.get('id')==case['id'] and row['observed'])
        queries=[]
        for index,query in enumerate(case['queries']):
            events=[event for event in actual['query_events'] if event['query']==index]
            reads=[{key:event[key] for key in ['ordinal','position','identifier','state_id','state_name']} for event in events if event['method']=='block_read']
            assert [row['ordinal'] for row in reads]==list(range(len(reads)))
            yields=[event['boxes'] for event in events if event['method']=='block_yield']
            assert len(yields)<=1 and (not yields or len(yields[0])==1),'Actual noBlockCollision first fullcube yield contract'
            stages=query['actual_stages']
            assert query['clear']==stages['no_block_collision'],'Fixture empty actors/clear border admission must be measured'
            assert stages.get('no_entity_collision',True) and stages.get('no_border_collision',True)
            queries.append({**query,'reads':reads,'first_yielded':yields[0][0] if yields else None})
        result.append({**case,'queries':queries})
    return result

def extract():
    pure_reference=ROOT/'reference/player_pose.json'
    assert fingerprint(pure_reference)['sha256']==FROZEN_PP_REFERENCE
    pins={str(p):fingerprint(p) for p in [Path(__file__),Path(PP.__file__),pure_reference,ROOT/'tools/reference_local_input_probe.py',CLIENT]}
    values=PP.inputs();first,a=run_java(values,'first');second,b=run_java(values,'second')
    assert first==second,'Actual ordered world trace rerun changed'
    cases=collect(values,first)
    corpus={'version':'26.3','scope':'Actual updatePlayerPose with owned-adapter query expectations; explicit same stone/air finite map and seeded conditional context; no lifecycle/full tick claim.','inputs_sha256':sha(values),'frozen_pose_reference_sha256':FROZEN_PP_REFERENCE,'cases':cases}
    destination=ROOT/'reference/player_pose_world.json';destination.write_bytes(canonical(corpus)+b'\n')
    assert all(fingerprint(Path(p))==pin for p,pin in pins.items()),'Producer/JAR/frozen dependencies changed'
    counts={'actual_cases':len(cases),'unit_scale_admitted':sum(c['admitted'] for c in cases),'queries':sum(len(c['queries']) for c in cases),'ordered_reads':sum(len(q['reads']) for c in cases for q in c['queries']),'first_yields':sum(q['first_yielded'] is not None for c in cases for q in c['queries'])}
    evidence={'status':'actual Java reference passed; owned Bend bridge not executed','producer':fingerprint(Path(__file__)),'frozen_dependencies':pins,'source_sha256':hashlib.sha256(SOURCE.encode()).hexdigest(),'reference':fingerprint(destination),'input_sha256':sha(values),'case_projection_sha256':sha(cases),'frozen_pose_expectations_equal':True,'fresh_full_raw_rerun_exact':True,'plain_observer_final_exact':True,'counts':counts,'runs':[a,b],
              'boundary':'Private frozen PP source copy differs only class/output name and active-query read metadata adding actual state ID/name/ordinal. Normal constructors, four frozen external services, unchanged official methods/classes. Actual noCollision stages, block iterator/read order and first yield decide all expected results. No Python collision algorithm.'}
    write_json(ROOT/'evidence/player-pose-world-reference.json',evidence)
    print(json.dumps({'status':evidence['status'],'counts':counts,'reference':fingerprint(destination),'evidence':fingerprint(ROOT/'evidence/player-pose-world-reference.json')},indent=2))

if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--extract',action='store_true',required=True);p.parse_args();extract()
