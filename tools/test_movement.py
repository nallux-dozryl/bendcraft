#!/usr/bin/env python3
"""Compare pure Bend movement outputs with pinned Java observations."""
from __future__ import annotations
import argparse, collections, copy, hashlib, json, pathlib, re, subprocess, time
from test_geometry import run, words, word_vector, verify_fixture_provenance, sha

ROOT=pathlib.Path(__file__).resolve().parents[1]
BEND=pathlib.Path('/Users/chuah/.bend/bin/bend')
BINARY=ROOT/'build/movement-tests'
FIXTURES=ROOT/'reference/movement.json'

def shape_words(shapes):
    fields=[]
    for s in shapes:
        if s['kind']=='empty':fields.append('empty')
        else:
            assert s['kind']=='raw_array_box'
            fields.extend(['box',*word_vector(s['box'])])
    return '|'.join(fields)

def request(c):
    v={**c['input'],**c.get('observation',{}).get('actual_input',{})}
    operation='move' if c['operation']=='entity_move' else c['operation']
    header=[c['id'],operation,*word_vector(v['box']),*word_vector(v['requested']),str(int(v['grounded'])),
            str(int(v['maximum_f32_bits'],16)),str(int(v['previous_f32_bits'],16)),*word_vector(v['position']),*word_vector(v['velocity']),
            str(int(v['width_f32_bits'],16)),str(int(v['height_f32_bits'],16))]
    return ';'.join(['|'.join(header),shape_words(v['initial']),shape_words(v['step'])])

def values(fields):
    assert len(fields)%2==0
    return [f'{int(fields[i]):08x}{int(fields[i+1]):08x}' for i in range(0,len(fields),2)]

def parse(line):
    id,operation,*fields=line.split('|')
    if operation=='box':return id,{'box':values(fields)}
    if operation=='error':return id,{'error':'|'.join(fields)}
    if operation=='heights':return id,{'heights':values(fields)}
    expected={'displacement':values(fields[:6])}
    if operation=='collide':assert len(fields)==6;return id,expected
    expected['stepped']=bool(int(fields[6]))
    if operation=='resolve':assert len(fields)==7;return id,expected
    assert operation=='move' and len(fields)==36,(operation,len(fields))
    expected.update(position=values(fields[7:13]),box=values(fields[13:25]),velocity=values(fields[25:31]),flags=[bool(int(v)) for v in fields[31:36]])
    return id,expected

def validation_cases(base):
    cases=[]
    def add(label,change,error):
        c=copy.deepcopy(base);c.update(id='validation-'+label,operation='checked_move');change(c['input']);c['expected']={'error':error};cases.append(c)
    nonfinite=['7ff0000000000000','fff0000000000000','7ff8000000000123']
    for component,key in [(0,'position'),(1,'box'),(2,'velocity')]:
        for field in range(6 if key=='box' else 3):
            for value in nonfinite:
                add(f'{key}-{field}-{value}',lambda v,key=key,field=field,value=value:v[key].__setitem__(field,value),f'body|{component}|{field}')
    for field in range(3):
        for value in nonfinite:
            add(f'request-{field}-{value}',lambda v,field=field,value=value:v['requested'].__setitem__(field,value),f'request|{field}')
    for field,key in [(0,'width_f32_bits'),(1,'height_f32_bits')]:
        for value in ['7f800000','ff800000','7fc01234','bf800000']:
            add(f'{key}-{value}',lambda v,key=key,value=value:v.__setitem__(key,value),f'dimensions|{field}')
    for value in ['7f800000','ff800000','7fc01234','bf800000']:
        add('maximum-'+value,lambda v,value=value:v.__setitem__('maximum_f32_bits',value),'maximum')
    for phase,key in enumerate(['initial','step']):
        for field in range(6):
            for index in [0,1,2]:
                def change(v,key=key,field=field,index=index):
                    s={'kind':'raw_array_box','box':v['box'].copy()};v[key]=[copy.deepcopy(s) for _ in range(3)];v[key][index]['box'][field]=nonfinite[2]
                add(f'collider-{phase}-{index}-{field}',change,f'collider|{phase}|{index}|{field}')
        for axis in range(3):
            def change(v,key=key,axis=axis):
                b=v['box'].copy();b[axis],b[axis+3]=b[axis+3],b[axis];v[key]=[{'kind':'raw_array_box','box':b}]
            add(f'reversed-{phase}-{axis}',change,f'reversed|{phase}|0|{axis}')
    # All obstacle input is validated before stationary/empty/early collision paths.
    def priority(v):
        v['position'][1]=nonfinite[0];v['requested'][0]=nonfinite[1];v['maximum_f32_bits']='7f800000'
    add('body-before-request-and-maximum',priority,'body|0|1')
    def overflow(v):
        v['position'][0]='7fefffffffffffff';v['requested'][0]='7fefffffffffffff'
    add('finite-input-position-overflow',overflow,'result|0|0')
    return cases

def direct_query_cases(fixtures):
    cases=[]
    for c in fixtures:
        if c['operation']!='entity_move':continue
        for index,q in enumerate(c['observation']['collision_queries']):
            operation='entity_query' if q['kind']=='entity' else 'block_query' if q['purpose']=='initial' else 'step_query'
            value={**c['input'],**c['observation']['actual_input']}
            if operation=='step_query':value['velocity']=c['observation']['baseline']
            cases.append({'id':c['id']+'-query-'+str(index),'operation':operation,'input':value,'expected':{'box':q['box']}})
    return cases

def main():
    p=argparse.ArgumentParser();p.add_argument('--skip-build',action='store_true');a=p.parse_args()
    fixture=json.loads(FIXTURES.read_text());provenance=verify_fixture_provenance(fixture)
    checks=[]
    for source in ['src/movement.bend','tests/movement.bend']:
        checks.append(run([BEND,source,'--check-only']))
        checks.append(run([BEND,source,'--verdict']))
    builds=[]
    if not a.skip_build:
        builds.append(run([BEND,'tests/movement.bend','-o','build/movement-tests.c']))
        builds.append(run([BEND,'tests/movement.bend','-o',BINARY]))
    native=[];counts=collections.Counter();tags=collections.Counter();stepped=0;names=set();start=time.monotonic()
    for offset in range(0,len(fixture['cases']),50):
        chunk=fixture['cases'][offset:offset+50]
        r=run([BINARY,'--gpu','off',*[request(c) for c in chunk]])
        lines=r['stdout'].splitlines();assert len(lines)==len(chunk),(offset,lines,r['stderr'])
        native.append({'offset':offset,'cases':len(chunk),'seconds':r['seconds'],'exit_code':r['exit_code']})
        for c,line in zip(chunk,lines,strict=True):
            id,observed=parse(line);assert id==c['id'] and id not in names;names.add(id)
            assert observed==c['expected'],(id,c['expected'],observed)
            counts[c['operation']]+=1;tags.update(c['tags']);stepped+=int(observed.get('stepped',False))
    validation=validation_cases(fixture['cases'][0])
    for offset in range(0,len(validation),50):
        chunk=validation[offset:offset+50];r=run([BINARY,'--gpu','off',*[request(c) for c in chunk]])
        for c,line in zip(chunk,r['stdout'].splitlines(),strict=True):
            id,observed=parse(line);assert id==c['id'] and observed==c['expected'],(id,c['expected'],observed)
    # The checked path reproduces successful raw transitions as well.
    success=[dict(c,id=c['id']+'-checked',operation='checked_move') for c in fixture['cases'] if c['operation'] in {'move','entity_move'}]
    for offset in range(0,len(success),50):
        chunk=success[offset:offset+50];r=run([BINARY,'--gpu','off',*[request(c) for c in chunk]])
        for c,line in zip(chunk,r['stdout'].splitlines(),strict=True):
            id,observed=parse(line);assert id==c['id'] and observed==c['expected'],(id,c['expected'],observed)
    queries=direct_query_cases(fixture['cases'])
    for offset in range(0,len(queries),50):
        chunk=queries[offset:offset+50];r=run([BINARY,'--gpu','off',*[request(c) for c in chunk]])
        for c,line in zip(chunk,r['stdout'].splitlines(),strict=True):
            id,observed=parse(line);assert id==c['id'] and observed==c['expected'],(id,c['expected'],observed)
    malformed=[]
    for value in ['broken','broken;;',request(fixture['cases'][0]).replace('|collide|','|bad|')]:
        r=run([BINARY,'--gpu','off',value],required=False);assert r['exit_code']==2 and 'invalid movement' in r['stderr'];malformed.append({'exit_code':r['exit_code'],'stderr':r['stderr']})
    c=ROOT/'build/movement-tests.c';text=c.read_text() if c.exists() else ''
    helpers=re.findall(r'INLINE Term spin_\d+\([^)]*\) \{.*?\n\}',text,re.S)
    host_float=[body for body in helpers if re.search(r'\b(?:double|float|f32|F32_BIN|F32_PRM)\b',body)]
    assert not host_float,'simulation scalar helper uses host floating arithmetic'
    sources=['src/movement.bend','tests/movement.bend','tools/test_movement.py','tools/reference_movement_probe.py','src/f64.bend','src/geometry.bend','docs/MOVEMENT.md']
    evidence={'schema_version':1,'status':'passed','pin':'26.3','fixture_sha256':sha(FIXTURES),'fixture_provenance':provenance,
              'checks':checks,'builds':builds,'native_batches':native,'java_case_count':len(names),'operation_counts':dict(counts),'tag_counts':dict(tags),
              'stepped_outcomes':stepped,'native_validation_seconds':round(time.monotonic()-start,6),'kernel_pass':True,
              'sources_sha256':{p:sha(ROOT/p) for p in sources if (ROOT/p).exists()},'binary_sha256':sha(BINARY),
              'emitted_c_bytes':len(text.encode()),'emitted_c_sha256':sha(c) if c.exists() else None,'host_float_simulation_helpers':len(host_float),
              'laws':re.findall(r'^law (\w+):',(ROOT/'src/movement.bend').read_text(),re.M),'malformed_protocol':malformed,
              'explicit_validation_cases':len(validation),'checked_success_oracle_cases':len(success),
              'actual_entity_move_cases':counts['entity_move'],'actual_entity_query_comparisons':len(queries),
              'oracle_scope':fixture['scope'],'confidence':fixture['confidence'],
              'full_entity_move_runtime_observed':counts['entity_move']>0,
              'unsupported':['collision/world border query collection','multi-cell voxel shapes','context-dependent block shapes','locomotion inputs, acceleration and drag','attributes','pose transitions','swimming and flight','piston and edge backoff','bounce/slime/honey restitution','fall damage and movement emission']}
    (ROOT/'evidence/movement-verification.json').write_text(json.dumps(evidence,indent=2,sort_keys=True)+'\n')
    print(json.dumps({k:evidence[k] for k in ['status','java_case_count','operation_counts','stepped_outcomes','kernel_pass','host_float_simulation_helpers','confidence']},indent=2))

if __name__=='__main__':main()
