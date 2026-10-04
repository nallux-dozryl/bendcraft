#!/usr/bin/env python3
"""Exact retained Java flight preparation compared with actual production LI/P."""
from __future__ import annotations
import argparse,json,sys
from pathlib import Path
import test_local_input as Old
import test_local_player_session as S
from reference_inventory import ROOT,canonical
from build_native import Snapshot,source_graph
BEND=Path('/Users/chuah/.bend/bin/bend')
ENTRY=ROOT/'tests/local_player_abilities.bend'
TABLE=ROOT/'generated/reference_mth_sin.f32'

def generation():
    snapshot=Snapshot();source_graph(ENTRY,BEND.resolve().parent.parent/'bend2/base.bend',{},snapshot)
    return snapshot.manifest()

def prepare(reference,directory,supplement=None):
    data=json.loads(reference.read_text());assert data['status']=='PASS'
    if supplement is not None:
        extra=json.loads(supplement.read_text());assert extra['status']=='PASS'
        replaced={r['id'] for r in extra['rows']}
        data['rows']=[r for r in data['rows'] if r['id'] not in replaced]+extra['rows']
    pairs=[]
    for case in data['rows']:
        if not case['observed']:continue
        for index,step in enumerate(case['steps']):
            calls=step['observer_calls'];apply=next(i for i,c in enumerate(calls) if c['method']=='applyInput_entry')
            control=next(c for c in reversed(calls[:apply]) if c['method']=='jumpableVehicle_return_before_super_ai_step')['state']
            travel=next(c for c in calls if c['method']=='travel_entry')
            takeoff=any(c['method']=='jumpFromGround' for c in calls[:apply])
            keys=control['key_presses']
            before=step['before']
            profile=[int(before['mayfly']),int(before['flying_speed_f32_bits'],16)]
            selector=[int(before['mayfly']),int(before['flying']),before['jump_trigger'],int(before['body_flags'][0]),int(before['key_presses'][4]),int(keys[4]),int(keys[5])]
            selection={'flying':control['flying'],'trigger':control['jump_trigger'],'takeoff':takeoff,'jump':keys[4],'sneak':keys[5]}
            ident=case['id']+':'+str(index)
            packet=';'.join([ident,
              '|'.join(str(w&0xffffffff) for w in Old.local_words(Old.project_local(control),control['sprinting'])),
              '|'.join(str(w&0xffffffff) for w in Old.player_words(Old.project_player(step['before']))),
              '|'.join(str(w&0xffffffff) for w in Old.apply_words(control,step['context'])),
              '|'.join(str(w&0xffffffff) for w in profile),
              '|'.join(str(w&0xffffffff) for w in selector)])
            pairs.append({'id':ident,'packet':packet,'selector_input':selector,'expected':{'selection':selection,'local':Old.project_local(travel['state']),'player':Old.project_player(travel['state']),'travel_input':travel['input']}})
    assert len(pairs)==data['counts']['ticks_per_receiver']
    directory.mkdir(parents=True,exist_ok=True)
    value={'schema':1,'reference':S.pin(reference),'supplement':S.pin(supplement) if supplement is not None else None,'source_generation':generation(),'entry':S.pin(ENTRY),'table':S.pin(TABLE),'pairs':pairs,
      'scope':'Actual shared production flight selector from real Java before/control fields, feeding its own returned flying/trigger/takeoff/jump/sneak into LI/P inherited pre-travel preparation: complete Body and Player metadata, sampled local input/bob and selection. Full world travel/OS/native actor excluded.'}
    S.exclusive_json(directory/'preparation.json',value)
    return value

def build(directory):
    prep=json.loads((directory/'preparation.json').read_text());assert prep['source_generation']==generation()
    argv=[sys.executable,str(ROOT/'tools/build_native.py'),str(ENTRY),'-o',str(directory/'tests'),'--report',str(directory/'native-build.json')]
    process,out,err=S.bounded(argv,60,directory,'native-build')
    S.exclusive_json(directory/'build-result.json',{'process':process,'unchanged':prep['source_generation']==generation()})
    assert process['exit_code']==0 and process['group_absent'] and not process['timed_out'],err.decode()[-4000:]

def run(directory):
    prep=json.loads((directory/'preparation.json').read_text());assert prep['source_generation']==generation()
    argv=[str(directory/'tests'),'--gpu','off','--threads','1',str(TABLE),*[p['packet'] for p in prep['pairs']]]
    process,out,err=S.bounded(argv,30,directory,'native-run')
    results=[]
    if process['exit_code']==0:
        lines=out.decode().splitlines();assert len(lines)==2*len(prep['pairs'])
        for pair,selection_line,line in zip(prep['pairs'],lines[::2],lines[1::2]):
            selection_id,kind,*words=selection_line.split('|')
            assert kind=='selection' and len(words)==5
            selected=dict(zip(['flying','trigger','takeoff','jump','sneak'],[bool(int(words[0])),int(words[1]),*[bool(int(w)) for w in words[2:]]]))
            ident,actual=Old.parse(line)
            actual['selection']=selected
            passed=selection_id==ident==pair['id'] and all(actual.get(k)==v for k,v in pair['expected'].items())
            results.append({'id':pair['id'],'passed':passed,'expected':pair['expected'],'actual':actual})
    ok=process['exit_code']==0 and process['group_absent'] and not process['timed_out'] and len(results)==len(prep['pairs']) and all(x['passed'] for x in results)
    S.exclusive_json(directory/'result.json',{'schema':1,'status':'PASS' if ok else 'FAIL','process':process,'preparation':prep,'results':results,'binary':S.pin(directory/'tests'),'unchanged':prep['source_generation']==generation()})
    print(json.dumps({'status':'PASS' if ok else 'FAIL','cases':len(results),'receipt':str(directory/'result.json')}));assert ok

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('mode',choices=['prepare','build','run']);parser.add_argument('directory',type=Path);parser.add_argument('--reference',type=Path);parser.add_argument('--supplement',type=Path)
    args=parser.parse_args()
    if args.mode=='prepare':print(json.dumps({'cases':len(prepare(args.reference,args.directory,args.supplement)['pairs'])}))
    elif args.mode=='build':build(args.directory)
    else:run(args.directory)
