#!/usr/bin/env python3
"""Prepare and compare raw Bend pose observations against actual Java rows.

Default --prepare does ordinary checks only. --native is an explicit bounded
installed-compiler action; it must be authorized by the shared heavy-build queue.
No reference extraction or Java/native refresh occurs during --skip-build.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import sys
import time

from reference_inventory import ROOT, canonical, fingerprint, write_json

BEND=Path('/Users/chuah/.bend/bin/bend')
REFERENCE=ROOT/'reference/player_pose.json'
ENTRY=ROOT/'tests/player_pose.bend'
BINARY=ROOT/'build/player-pose-tests'
BUILD=ROOT/'build/player-pose-native-build.json'
RAW=ROOT/'build/player-pose-tests-artifacts'
POSES={'STANDING':0,'FALL_FLYING':1,'SLEEPING':2,'SWIMMING':3,'SPIN_ATTACK':4,'CROUCHING':5,'DYING':7}
FLAGS=['sleeping','swimming','fall_flying','auto_spin_attack','shift','flying','spectator','passenger']
ERRORS={1:'eye',2:'dimensions',3:'box',4:'pose|99',5:'tail|0',6:'tail|1',7:'scale',8:'age',9:'context',10:'body|body|0|0',11:'body|body|2|0',12:'missing',13:'extra',14:'query_pose',15:'query_box',16:'query|0',17:'denied|fixture-refusal',18:'query_box',19:'tail|2',20:'progress',21:'progress',22:'progress',23:'tail|2',24:'unexpected',25:'dimensions',26:'progress',27:'eye',28:'body|body|1|0',29:'body|dimensions|0'}

def sha(value):return hashlib.sha256(canonical(value)).hexdigest()

def words(raw):
    value=int(raw,16)
    return [value>>32,value&0xffffffff]

def wide(values):return [word for value in values for word in words(value)]

def text(words):return '|'.join(map(str,words))

def body_words(state):
    return wide(state['position'])+wide(state['box'])+wide(state['velocity'])+[int(state['width_f32_bits'],16),int(state['height_f32_bits'],16)]+list(map(int,state['body_flags']))

def state_words(state):return [POSES[state['pose']],int(state['cached_eye_f32_bits'],16)]

def request_args(case):
    state=case['before'];context=state['context']
    return [text(body_words(state)),text(state_words(state)),text([sum(1<<i for i,name in enumerate(FLAGS) if context[name]),int(state['scale_f32_bits'],16),int(state['baby']),0])]

def answer_args(case):
    return '/'.join(text([POSES[q['pose']]]+wide(q['box'])+[0,int(q['clear'])]) for q in case['queries'])

def records(case):
    return ''.join(text([POSES[q['pose']]]+wide(q['box'])+[int(q['clear'])])+'/' for q in case['queries'])

def expected(case):
    if not case['admitted']:return 'error;scale'
    after=case['expected'];queries=case['queries']
    # Desired is observed in the actual second fit query, or in actual setPose
    # for the spectator/passenger exemption. Initial failure never calls it.
    desired='none' if not queries[0]['clear'] else str(POSES[queries[1]['pose'] if len(queries)>1 else case['set_pose_requests'][0]])
    return ';'.join(['ok',text(state_words(after)),text(body_words(after)),desired,str(POSES[after['pose']]),str(int(after['pose']!=case['before']['pose'])),str(case['refresh_count']),records(case),text(wide(after['eye_position']))])

def fixtures(data):
    rows=[];arguments=[]
    def add(case,id,alteration=0):
        argument=';'.join([id,str(alteration),*request_args(case),answer_args(case)])
        outcome='error;'+ERRORS[alteration] if alteration else expected(case)
        output=[id+';'+outcome,id+';original;'+text(state_words(case['before']))+';'+text(body_words(case['before'])),id+';recovery;'+expected(case)]
        rows.append({'id':id,'kind':'rejection_recovery' if alteration else 'actual_update','alteration':alteration,'actual_case':case['id'],'argument':argument,'expected_lines':output})
        arguments.append(argument)
    for c in data['cases']:add(c,c['id'])
    baseline=next(c for c in data['cases'] if c['id']=='initial:STANDING')
    zero=next(c for c in data['cases'] if c['id']=='deflated_positive_zero')
    assert zero['queries'][0]['box'][1]=='0000000000000000','Signed-zero mismatch fixture must start at observed +0 query boundary'
    for alteration in ERRORS:add(zero if alteration==18 else baseline,'failure:'+str(alteration),alteration)
    for m in data['metadata']:
        if m['scale_input']!='3ff0000000000000':continue
        id='metadata:'+m['pose'];ordinal=m['ordinal']
        if m['pose'] in POSES:
            v=m['dimensions'];output=id+';meta;'+text([int(v['width'],16),int(v['height'],16),int(v['eye'],16),int(v['fixed'])])
        else:output=id+';error;pose|'+str(ordinal)
        argument=';'.join(['meta',id,str(ordinal)])
        rows.append({'id':id,'kind':'metadata','argument':argument,'expected_lines':[output]});arguments.append(argument)
    return rows,arguments

def closure():
    found={}
    def visit(path):
        path=path.resolve()
        if str(path) in found:return
        found[str(path)]=fingerprint(path)
        for name in re.findall(r'^import\s+(\S+)',path.read_text(),re.M):
            if name.startswith('.'):visit(path.parent/name)
    visit(ENTRY)
    for path in [ROOT/'tools/test_player_pose.py',ROOT/'tools/reference_player_pose_probe.py',ROOT/'tools/reference_local_input_probe.py',REFERENCE,BEND]:found[str(path.resolve())]=fingerprint(path)
    return found

def bounded(command,seconds,label,env=None):
    RAW.mkdir(parents=True,exist_ok=True)
    start=time.monotonic()
    process=subprocess.Popen(command,cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True,env=env)
    print(json.dumps({'phase':label,'pid':process.pid,'cap_seconds':seconds}),flush=True)
    timed_out=False
    try:out,err=process.communicate(timeout=seconds)
    except subprocess.TimeoutExpired:
        timed_out=True;os.killpg(process.pid,signal.SIGKILL);out,err=process.communicate()
    (RAW/f'{label}-stdout.txt').write_text(out);(RAW/f'{label}-stderr.txt').write_text(err)
    receipt={'command':command,'seconds':round(time.monotonic()-start,6),'returncode':process.returncode,'timed_out':timed_out,'process_group_cap':True,'stdout':fingerprint(RAW/f'{label}-stdout.txt'),'stderr':fingerprint(RAW/f'{label}-stderr.txt')}
    return out,err,receipt

def prepare(data):
    rows,args=fixtures(data);before=closure();checks=[]
    for source in [ROOT/'src/player_pose.bend',ENTRY]:
        out,err,receipt=bounded([str(BEND),str(source),'--check-only'],30,source.parent.name+'-'+source.stem+'-ordinary')
        checks.append(receipt)
        assert receipt['returncode']==0 and 'ALL PROOFS CHECK' in out,(source,err,out)
    assert before==closure(),'Inputs changed during ordinary preparation'
    write_json(RAW/'prepared-fixtures.json',rows)
    result={'status':'ordinary preparation passes; native and independent kernel not executed','ordinary_checks':checks,'dependency_pins':before,'reference':fingerprint(REFERENCE),'fixture_argument_sha256':sha(args),'expected_lines_sha256':sha([line for row in rows for line in row['expected_lines']]),
            'counts':{'actual_updates':sum(r['kind']=='actual_update' for r in rows),'explicit_rejection_recoveries':sum(r['kind']=='rejection_recovery' for r in rows),'metadata':sum(r['kind']=='metadata' for r in rows),'expected_output_lines':sum(len(r['expected_lines']) for r in rows)},
            'raw_artifact':fingerprint(RAW/'prepared-fixtures.json'),'raw_artifact_ignored':True}
    write_json(ROOT/'evidence/player-pose-preparation.json',result)
    print(json.dumps({'status':result['status'],'counts':result['counts'],'evidence':fingerprint(ROOT/'evidence/player-pose-preparation.json')},indent=2))
    return result

def native_capture():
    directory=RAW/'native-capture';directory.mkdir(parents=True,exist_ok=True)
    commands=directory/'commands.jsonl';commands.write_text('')
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
    wrapper.write_text(source);wrapper.chmod(0o700)
    return wrapper,commands

def native(data,skip):
    rows,args=fixtures(data);pins=closure()
    if skip:
        build=json.loads(BUILD.read_text());assert build['dependency_pins']==pins,'Retained native source generation changed';assert build['binary']==fingerprint(BINARY),'Retained binary changed'
    else:
        wrapper,commands=native_capture();environment=dict(os.environ);environment['CC']=str(wrapper)
        _,err,receipt=bounded([str(BEND),str(ENTRY),'-o',str(BINARY)],600,'native',env=environment)
        command_rows=[json.loads(row) for row in commands.read_text().splitlines()]
        copied_c=[fingerprint(p) for p in sorted(wrapper.parent.glob('source-*.c'))]
        build={'status':'failed','execution':receipt,'dependency_pins':pins,'compiler':fingerprint(BEND),'c_compiler':fingerprint(Path('/usr/bin/clang')),'capture_python':fingerprint(Path(sys.executable)),
               'read_only_c_capture_wrapper':fingerprint(wrapper),'cc_override':str(wrapper),'clang_commands':fingerprint(commands),'clang_commands_sha256':sha(command_rows),'clang_command_seal':'canonical JSON UTF-8, ensure_ascii=False, sorted keys, comma/colon separators, no trailing newline','emitted_c':copied_c}
        if receipt['returncode']==0 and BINARY.exists():
            assert pins==closure(),'Native sources changed';assert copied_c,'Actual emitted C was not captured';build.update(status='compiled',binary=fingerprint(BINARY))
        write_json(BUILD,build)
        assert build['status']=='compiled',err[-8000:]
    expected_lines=[line for r in rows for line in r['expected_lines']]
    out,err,receipt=bounded([str(BINARY),*args],30,'comparison')
    actual=out.splitlines()
    assert receipt['returncode']==0,err
    # Whole rows compare every raw word, query order and group boundary. No
    # decimal floating conversion, approximate geometry, or token dropping.
    assert len(actual)==len(expected_lines),(len(actual),len(expected_lines))
    for i,(a,e) in enumerate(zip(actual,expected_lines)):assert a==e,(i,a,e)
    assert closure()==pins,'Comparison source generation changed'
    result={'status':'native raw parity passes; independent kernel not executed','execution':receipt,'build_manifest':fingerprint(BUILD),'binary':fingerprint(BINARY),'dependency_pins':pins,'reference':fingerprint(REFERENCE),'fixture_argument_sha256':sha(args),'expected_lines_sha256':sha(expected_lines),'actual_lines_sha256':sha(actual),'exact_whole_rows':True,'counts':{'actual_updates':len(data['cases']),'rejection_recoveries':len(ERRORS),'metadata':18,'output_lines':len(actual)}}
    write_json(ROOT/'evidence/player-pose-native.json',result)
    print(json.dumps({'status':result['status'],'counts':result['counts']},indent=2))

if __name__=='__main__':
    p=argparse.ArgumentParser();g=p.add_mutually_exclusive_group(required=True);g.add_argument('--prepare',action='store_true');g.add_argument('--native',action='store_true');g.add_argument('--skip-build',action='store_true');a=p.parse_args();data=json.loads(REFERENCE.read_text())
    if a.prepare:prepare(data)
    else:native(data,a.skip_build)
