#!/usr/bin/env python3
"""Compare native pure Bend typed model data with executed pinned Java fixtures."""
from __future__ import annotations
import argparse
import copy
import hashlib
import json
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BEND = Path('/Users/chuah/.bend/bin/bend')
BIN = ROOT/'build/block-model-tests'
REFERENCE = ROOT/'reference/model_semantics.json'
CONTEXTS = {
    'thirdperson_righthand':'thirdPersonRightHand',
    'thirdperson_lefthand':'thirdPersonLeftHand',
    'firstperson_righthand':'firstPersonRightHand',
    'firstperson_lefthand':'firstPersonLeftHand',
    'head':'head','gui':'gui','ground':'ground','fixed':'fixed','on_shelf':'fixedFromBottom',
}

def display(value):
    if value is None: return None
    return {k:{f:value[java][f] for f in ['rotation','translation','scale']}
            for k,java in CONTEXTS.items()}

def element(value):
    rot = value['rotation']
    if rot is not None:
        v = rot['value']
        v = ({'kind':'axis','axis':v['axis'],'angle':v['angle']} if 'axis' in v else
             {'kind':'euler','angles':[v[k] for k in ['x','y','z']]})
        rot = {'origin':rot['origin'],'rescale':rot['rescale'],'value':v}
    faces = {}
    for name,face in value['faces'].items():
        uv = face['uvs']
        faces[name] = {'cull':face['cullForDirection'],
                       'uv':None if uv is None else [uv[k] for k in ['minU','minV','maxU','maxV']],
                       'rotation':int(face['rotation'][1:]),'texture':face['texture'],
                       'tint_index':face['tintIndex'] & 0xffffffff}
    return {'from':value['from'],'to':value['to'],'rotation':rot,'faces':faces,
            'light_emission':value['lightEmission'],'shade_direction_override':value['shadeDirectionOverride']}

def parsed(value):
    textures = {}
    for key, texture in value['textureSlots']['values'].items():
        if 'material' in texture:
            m = texture['material']
            textures[key] = {'kind':'sprite','sprite':m['sprite'],'force_translucent':m['forceTranslucent']}
        else:
            textures[key] = {'kind':'alias','slot':texture['target']}
    return {'parent':value['parent'],
            'elements':None if value['geometry'] is None else [element(v) for v in value['geometry']['elements']],
            'ambient_occlusion':value['ambientOcclusion'],
            'gui_light':None if value['guiLight'] is None else value['guiLight'].lower(),
            'display':display(value['transforms']),'textures':textures}

def resolved(value):
    geometry=value['geometry']
    return {'id':value['debug_name'],'parent':value['parent'],
            'elements':[] if not isinstance(geometry,dict) else [element(v) for v in geometry['elements']],
            'geometry_present':isinstance(geometry,dict),
            'ambient_occlusion':value['ambient_occlusion'],'gui_light':value['gui_light'].lower(),
            'display':display(value['transforms']),
            'materials':{slot:(None if material is None else
                              {'sprite':material['sprite'],'force_translucent':material['forceTranslucent']})
                         for slot,material in value['materials'].items()}}

def graph_text(models,roots,observations):
    # Embed original model text, retaining every original decimal lexeme.
    return ('{"models":{'+','.join(json.dumps(k)+':'+v for k,v in models.items())+
            '},"roots":'+json.dumps(roots)+',"queries":'+
            json.dumps({k:list(v['materials']) for k,v in observations.items()})+'}')

def run(args, timeout=180, allow_error=False):
    p = subprocess.run([str(x) for x in args],cwd=ROOT,capture_output=True,text=True,timeout=timeout)
    if p.returncode and not allow_error:
        raise AssertionError(f'{args}: exit {p.returncode}\n{p.stdout}\n{p.stderr}')
    return p

def native(inputs):
    lines = []
    for start in range(0,len(inputs),15):
        p = run([BIN,'--threads','1',*[v for _,v in inputs[start:start+15]]])
        part = p.stdout.removesuffix('\n').split('\n')
        assert len(part)==len(inputs[start:start+15]), ('native line count',start,p.stdout[:500])
        lines.extend(part)
    return lines

def edge_inputs():
    """Small field-boundary inputs; expected semantics come only from actual Java."""
    cases=[]
    cube={'from':[0,0,0],'to':[16,16,16],'faces':{'north':{'texture':'#all'}}}
    def add(name,value):
        cases.append({'id':name,'json':json.dumps(value,separators=(',',':')),'bake':False})
    for i,value in enumerate(['0.1','+0.1',' .5f ','-0.0','0x1p-1','NaN','Infinity',True,None]):
        v=copy.deepcopy(cube);v['from'][0]=value;add(f'float-from-{i}',{'elements':[v]})
    for i,value in enumerate(['NaN','Infinity','-Infinity','0x1p-1',' .5f ']):
        v=copy.deepcopy(cube);v['faces']['north']['uv']=[value,0,16,16];add(f'float-uv-{i}',{'elements':[v]})
    for i,value in enumerate([1.9,-0.9,4294967296,4294967311,18446744073709551631,
                             9007199254740993,1e40,1e-40,-1.9,'+1','0001','1.9','1e1',
                             '2147483648','-2147483648','false',' 1 ']):
        v=copy.deepcopy(cube);v['light_emission']=value;add(f'integer-light-{i}',{'elements':[v]})
    for i,value in enumerate(['TRUE','TrUe',1,-1,[],None]):add(f'ambient-{i}',{'ambientocclusion':value})
    for i,value in enumerate([None,True,1.5,[],{}]):add(f'parent-{i}',{'parent':value})
    for i,rotation in enumerate([{'origin':[8,8,8],'angle':12,'x':0},
                                 {'origin':[8,8,8],'axis':'y','x':0},
                                 {'origin':[8,8,8],'axis':'Y','angle':12}]):
        v=copy.deepcopy(cube);v['rotation']=rotation;add(f'rotation-precedence-{i}',{'elements':[v]})
    v=copy.deepcopy(cube);v['faces']={'up':{'texture':'first'},'UP':{'texture':'last'}}
    add('face-direction-alias',{'elements':[v]})
    v=copy.deepcopy(cube);v['shade_direction_override']='UP';add('shade-uppercase',{'elements':[v]})
    add('display-nan',{'display':{'gui':{'translation':['NaN','Infinity','-Infinity'],
                                      'scale':['NaN','Infinity','-Infinity']}}})
    for i,value in enumerate(['UP','Up',True,1]):
        v=copy.deepcopy(cube);v['faces']['north']['cullface']=value;add(f'cull-case-{i}',{'elements':[v]})
    graphs=[{'id':'display-inheritance','models':{
        'test:p':'{"display":{"gui":{"rotation":[30,0,0]},"ground":{"scale":[2,2,2]}}}',
        'test:c':'{"parent":"test:p","display":{}}',
        'test:e':'{"parent":"test:p","display":{"gui":{}}}'},'roots':['test:c','test:e']},
        {'id':'cycle-descendant','models':{'test:a':'{"parent":"test:b"}',
            'test:b':'{"parent":"test:a"}','test:c':'{"parent":"test:a"}'},'roots':['test:c']}]
    return {'models':{},'blockstates':{},'variants':[],'parse_cases':cases,'graph_cases':graphs,
            'selector_cases':[],'condition_cases':[],'dispatcher_cases':[]}

def java_edges():
    # This calls the pinned official model classes in an isolated ignored directory.
    # The reference module is read-only: do not call its cache-writing execute().
    import reference_model_probe as probe
    directory=ROOT/'build/block-model-edges';directory.mkdir(parents=True,exist_ok=True)
    fixture=edge_inputs()
    source=directory/'ReferenceModelProbe.java';inputs=directory/'inputs.json';output=directory/'observations.json'
    source.write_text(probe.JAVA_SOURCE);inputs.write_text(json.dumps(fixture,separators=(',',':'))+'\n')
    cp,provenance=probe.verified_client_classpath()
    command=[str(probe.JAVA),'--enable-native-access=ALL-UNNAMED','-cp',':'.join(map(str,cp)),
             str(source),str(inputs),str(probe.CLIENT),str(output)]
    p=subprocess.run(command,cwd=directory,capture_output=True,text=True,timeout=180)
    (directory/'stdout.log').write_text(p.stdout);(directory/'stderr.log').write_text(p.stderr)
    assert p.returncode==0,('extra Java model harness',p.returncode,p.stdout,p.stderr)
    metadata={'command':command,'harness_sha256':hashlib.sha256(probe.JAVA_SOURCE.encode()).hexdigest(),
              'input_sha256':hashlib.sha256(inputs.read_bytes()).hexdigest(),
              'observation_sha256':hashlib.sha256(output.read_bytes()).hexdigest(),
              'client':provenance['client'],'java':provenance['java'],'java_version':provenance['java_version'],
              'library_count':len(provenance['libraries']),
              'library_provenance_sha256':hashlib.sha256(json.dumps(provenance['libraries'],sort_keys=True).encode()).hexdigest()}
    (directory/'metadata.json').write_text(json.dumps(metadata,indent=2)+'\n')
    return fixture,json.loads(output.read_text()),metadata

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--skip-build',action='store_true')
    options = ap.parse_args()
    begin=time.monotonic()
    ref=json.loads(REFERENCE.read_text())
    tracked=['src/block_model.bend','tests/block_model.bend','src/json.bend','src/float_parse.bend','src/big_uint.bend',
             'tools/test_block_model.py','tools/reference_model_probe.py']
    hashes={p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in tracked}
    checks={}
    phases={}
    phase_start=time.monotonic()
    edges,edge_observations,edge_oracle=java_edges()
    phases['extra_java_oracle']=round(time.monotonic()-phase_start,3)
    for path in ['src/block_model.bend','tests/block_model.bend']:
        phase_start=time.monotonic()
        p=run([BEND,path,'--check-only'])
        assert 'ALL PROOFS CHECK' in p.stdout,p.stdout
        checks[path]=p.stdout.strip()
        phases['check:'+path]=round(time.monotonic()-phase_start,3)
    if not options.skip_build:
        phase_start=time.monotonic()
        run([BEND,'tests/block_model.bend','-o',BIN],timeout=600)
        phases['native_build']=round(time.monotonic()-phase_start,3)
    assert run([BIN,'--threads','1']).stdout.strip()=='model-fixtures\tpass'
    results=[]
    excluded=[]
    observations={v['id']:v for v in ref['observations']['parse_cases']}
    inputs=[]
    for value in ref['inputs']['parse_cases']:
        if value['id'] in ['raw_json_100','raw_json_101']:
            excluded.append({'id':value['id'],'reason':'duplicate/invalid textual JSON is outside the strict unique-member J.Value decoder API'})
        else:
            inputs.append((value['id'],value['json']))
    for (name,source),out in zip(inputs,native(inputs)):
        expected=observations[name]
        if expected['status']=='error':
            assert out.startswith('error\t'),(name,'expected Java rejection',out)
        else:
            assert out.startswith('ok\t'),(name,'expected Java acceptance',out)
            got=json.loads(out[3:]);want=parsed(expected['parsed'])
            assert got==want,(name,'parsed mismatch',got,want)
        results.append({'id':name,'java_status':expected['status'],'passed':True,
                        'native_sha256':hashlib.sha256(out.encode()).hexdigest()})
    official=list(ref['inputs']['models'].items())
    for (name,source),out in zip(official,native(official)):
        assert out.startswith('ok\t'),(name,out)
        got=json.loads(out[3:]);want=parsed(ref['observations']['parsed_official_models'][name])
        assert got==want,(name,'official parsed mismatch',got,want)
        results.append({'id':name,'java_status':'ok','passed':True,
                        'native_sha256':hashlib.sha256(out.encode()).hexdigest()})
    edge_results=[]
    edge_expected={v['id']:v for v in edge_observations['parse_cases']}
    extra_inputs=[(v['id'],v['json']) for v in edges['parse_cases']]
    for (name,source),out in zip(extra_inputs,native(extra_inputs)):
        expected=edge_expected[name]
        if expected['status']=='error':
            assert out.startswith('error\t'),(name,'expected Java rejection',out)
        else:
            assert out.startswith('ok\t'),(name,'expected Java acceptance',out)
            assert json.loads(out[3:])==parsed(expected['parsed']),(name,'extra parsed mismatch',out,expected)
        edge_results.append({'id':name,'json':source,'java_status':expected['status'],
                             'java_error':expected.get('error'),'passed':True,
                             'native_sha256':hashlib.sha256(out.encode()).hexdigest()})
    graph_results=[]
    graph_obs={v['id']:v for v in ref['observations']['graph_cases']}
    for case in ref['inputs']['graph_cases']:
        name=case['id'];expect=graph_obs[name]['resolved']
        source=graph_text(case['models'],case['roots'],expect)
        out=run([BIN,'--threads','1','graph',source]).stdout.strip()
        assert out.startswith('ok\t'),(name,out)
        got=json.loads(out[3:]);want={k:resolved(v) for k,v in expect.items()}
        assert got==want,(name,'graph mismatch',got,want)
        graph_results.append({'id':name,'models':len(got),'passed':True,
                              'native_sha256':hashlib.sha256(out.encode()).hexdigest()})
    edge_graph_results=[]
    edge_graph_expected={v['id']:v for v in edge_observations['graph_cases']}
    for case in edges['graph_cases']:
        name=case['id'];expect=edge_graph_expected[name]['resolved']
        source=graph_text(case['models'],case['roots'],expect)
        out=run([BIN,'--threads','1','graph',source]).stdout.strip()
        assert out.startswith('ok\t'),(name,out)
        got=json.loads(out[3:]);want={k:resolved(v) for k,v in expect.items()}
        assert got==want,(name,'extra graph mismatch',got,want)
        edge_graph_results.append({'id':name,'models':len(got),'passed':True,
                                   'native_sha256':hashlib.sha256(out.encode()).hexdigest()})
    official_resolved=ref['observations']['resolved_official_models']
    source=graph_text(ref['inputs']['models'],list(official_resolved),official_resolved)
    out=run([BIN,'--threads','1','graph',source]).stdout.strip()
    assert out.startswith('ok\t'),('official graph',out[:500])
    got=json.loads(out[3:])
    assert set(got)==set(official_resolved)|{'minecraft:builtin/missing'},set(got)
    for name,value in official_resolved.items():
        assert got[name]==resolved(value),(name,'official resolved mismatch',got[name],resolved(value))
    kernel={}
    for path in ['src/block_model.bend','tests/block_model.bend']:
        try:
            p=run([BEND,path,'--verdict'],allow_error=True,timeout=60)
            kernel[path]={'exit_code':p.returncode,'output':(p.stdout+p.stderr).strip(),'timeout_seconds':60}
        except subprocess.TimeoutExpired as error:
            def decoded(value):return value.decode(errors='replace') if isinstance(value,bytes) else (value or '')
            kernel[path]={'exit_code':None,'timed_out':True,'timeout_seconds':60,
                          'output':(decoded(error.stdout)+decoded(error.stderr)).strip()}
    for path,digest in hashes.items():
        assert hashlib.sha256((ROOT/path).read_bytes()).hexdigest()==digest,('source changed during run',path)
    report={'schema':1,'all_cases_passed':True,'checker':checks,'kernel_verdict':kernel,'phase_seconds':phases,
            'reference_sha256':hashlib.sha256(REFERENCE.read_bytes()).hexdigest(),
            'reference_oracle_version':ref['oracle_version'],
            'source_sha256':hashlib.sha256((ROOT/'src/block_model.bend').read_bytes()).hexdigest(),
            'float_source_sha256':hashlib.sha256((ROOT/'src/float_parse.bend').read_bytes()).hexdigest(),
            'json_source_sha256':hashlib.sha256((ROOT/'src/json.bend').read_bytes()).hexdigest(),
            'parsed_reference_cases':len(inputs),'official_models':len(official),'excluded_textual_cases':excluded,
            'extra_java_cases':len(edge_results),'extra_java_graphs':edge_graph_results,
            'graph_cases':graph_results,'official_resolved_models':len(official_resolved),
            'transitive_source_sha256':hashes,'native_binary_sha256':hashlib.sha256(BIN.read_bytes()).hexdigest(),
            'native_build_skipped':options.skip_build,
            'proof_scope':'Three finite ordinary-checker examples. Full independent-kernel commands are separately bounded and reported; known transitive JSON encode_go mismatch is not attributed as the cause of a timeout. No general correctness or bake theorem.',
            'compared_fields':'all nullable/default typed model fields, geometry, face metadata, UV and vector raw F32 bits, rotation inputs/normalized origin, display F32 bits, texture slots; derived rotation matrix excluded',
            'baking_implemented':False,'cases':results,'elapsed_seconds':round(time.monotonic()-begin,3),
            'commands':['python3 tools/test_block_model.py','/Users/chuah/.bend/bin/bend src/block_model.bend --check-only',
                        '/Users/chuah/.bend/bin/bend tests/block_model.bend --check-only',
                        '/Users/chuah/.bend/bin/bend tests/block_model.bend -o build/block-model-tests',
                        '/Users/chuah/.bend/bin/bend src/block_model.bend --verdict',
                        '/Users/chuah/.bend/bin/bend tests/block_model.bend --verdict']}
    (ROOT/'evidence/block-model-native.json').write_text(json.dumps(report,indent=2)+'\n')
    (ROOT/'evidence/block-model-edges.json').write_text(json.dumps({'schema':1,'all_cases_passed':True,
        'oracle':edge_oracle,'transitive_source_sha256':hashes,'cases':edge_results,'graphs':edge_graph_results},indent=2)+'\n')
    print(json.dumps({k:report[k] for k in ['parsed_reference_cases','official_models','graph_cases','official_resolved_models','all_cases_passed','elapsed_seconds']},indent=2))

if __name__=='__main__': main()
