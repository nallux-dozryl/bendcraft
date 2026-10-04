#!/usr/bin/env python3
"""Compare the actual Bend crafting API to pinned Java observations.

Python constructs requests and compares results. All decoding, matching and
plans execute in the native Bend module; no Python crafting implementation.
"""
from __future__ import annotations
import argparse, collections, copy, json, re, subprocess, time
from pathlib import Path
import reference_crafting_recipe_probe as P
from reference_inventory import ROOT, fingerprint, write_json

BEND=Path('/Users/chuah/.bend/bin/bend')
BINARY=ROOT/'build/crafting-recipe-tests'
EVIDENCE=ROOT/'evidence/crafting-recipe-native.json'
SOURCES=['src/crafting_recipe.bend','src/crafting_recipe_decoder.bend','src/crafting_recipe_laws.bend','src/crafting_recipe_proof.bend','tests/crafting_recipe.bend']

def source_identity():
    return {path:fingerprint(ROOT/path)['sha256'] for path in SOURCES+['src/inventory.bend','src/json.bend']}

def run(command,timeout=60):
    start=time.monotonic();result=subprocess.run(list(map(str,command)),capture_output=True,text=True,timeout=timeout,cwd=ROOT)
    receipt={'command':list(map(str,command)),'seconds':round(time.monotonic()-start,6),'status':result.returncode,'stdout':result.stdout[-6000:],'stderr':result.stderr[-6000:]}
    if result.returncode:raise AssertionError(receipt)
    return result,receipt

def extra_queries():
    base={'id':'admission','recipes':['bendcraft:padded'],'grid':{'width':2,'height':2,'slots':[P.stack('minecraft:oak_planks'),None,None,None]}}
    values=[]
    def add(label,grid,expected,after=None):
        row=copy.deepcopy(base);row['id']=label;row['grid']=grid
        if after is not None:row['after']=after
        values.append((row,expected))
    message='invalid crafting grid: dimensions, slot count, item definition or components'
    for label,change in [('zero_width',{'width':0}),('wide_grid',{'width':4}),('zero_height',{'height':0}),('wrong_slot_count',{'slots':[None]})]:
        grid=copy.deepcopy(base['grid']);grid.update(change);add(label,grid,{'error':message})
    for label,slot in [('unknown_item',P.stack('bendcraft:missing')),('air_stack',P.stack('minecraft:air')),('zero_count',P.stack('minecraft:oak_planks',0)),('overfull_stack',P.stack('minecraft:oak_planks',65)),('patched_stack',{**P.stack('minecraft:oak_planks'),'components':'{"minecraft:custom_name":"x"}'})]:
        grid=copy.deepcopy(base['grid']);grid['slots'][0]=slot;add(label,grid,{'error':message})
    for label,change in [('current_exact',{}),('stale_count',{'slots':[P.stack('minecraft:oak_planks',2),None,None,None]}),('stale_item',{'slots':[P.stack('minecraft:birch_planks'),None,None,None]}),('stale_components',{'slots':[{**P.stack('minecraft:oak_planks'),'components':'changed'},None,None,None]}),('stale_dimensions',{'width':1,'height':4})]:
        after=copy.deepcopy(base['grid']);after.update(change);add(label,copy.deepcopy(base['grid']),{'current':label=='current_exact'},after)
    return values

def check_native(reference,threads):
    catalog=json.loads((P.CACHE/'catalog.json').read_text());extra=extra_queries()
    request={'catalog':catalog,'queries':reference['queries']+[row for row,_ in extra],'decoder_queries':reference['decoder_queries']}
    input_path=P.CACHE/'native-input.json';write_json(input_path,request)
    result,receipt=run([BINARY,'--threads',threads,'--gpu','off',input_path],timeout=90)
    actual=json.loads(result.stdout);observed={row['id']:row for row in reference['observations']};expected={row['id']:wanted for row,wanted in extra}
    for row in actual['queries']:
        id=row['id']
        if id in observed:
            java=observed[id];wanted={'recipe':java['matches'][0] if java['matches'] else None,'output':java['output'],'consumption':java['consumption']}
        else:wanted=expected[id]
        assert row['result']==wanted,(id,row['result'],wanted)
    assert len(actual['queries'])==len(request['queries'])
    source={row['id']:row['source'] for row in catalog['recipes']};decoded={row['id']:row for row in actual['decoded']}
    assert len(decoded)==len(source)
    java={row['id']:row for row in reference['decoded']}
    for id,row in decoded.items():
        raw=source[id];kind=raw['type'];ordinary=kind in ('minecraft:crafting_shaped','minecraft:crafting_shapeless')
        if not ordinary or 'components' in raw['result']:
            assert row['status']=='unsupported',id
            continue
        assert row['status']==('shaped' if kind.endswith('shaped') else 'shapeless')
        assert row['output']=={'id':raw['result']['id'],'count':raw['result'].get('count',1)}
        if row['status']=='shaped':assert (row['width'],row['height'])==(java[id]['width'],java[id]['height'])
    codec={row['id']:row['accepted'] for row in reference['decoder_observations']}
    for row in actual['decoder_queries']:assert row['accepted']==codec[row['id']],row
    assert len(actual['decoder_queries'])==len(codec)
    receipt.pop('stdout');receipt['output_sha256']=P.sha(result.stdout.encode());receipt['queries']=len(actual['queries']);receipt['decoded']=len(actual['decoded']);receipt['decoder_queries']=len(codec)
    write_json(P.CACHE/f'native-output-{threads}.json',actual)
    return receipt

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--reuse-built',action='store_true');args=parser.parse_args()
    reference=P.verify();checks=[];identity=source_identity();cache=ROOT/'build/crafting-recipe-build.json'
    for target,flag in [('src/crafting_recipe_proof.bend','--verdict'),('src/crafting_recipe_decoder.bend','--check-only'),('tests/crafting_recipe.bend','--check-only')]:
        _,receipt=run([BEND,target,flag]);checks.append(receipt)
    build=None
    if not args.reuse_built:
        _,build=run([BEND,'tests/crafting_recipe.bend','-o',BINARY])
        assert source_identity()==identity,'production source changed during build/check'
        write_json(cache,{'sources':identity,'binary_sha256':fingerprint(BINARY)['sha256'],'build':build})
    else:
        saved=json.loads(cache.read_text());assert saved['sources']==identity and saved['binary_sha256']==fingerprint(BINARY)['sha256']
    assert BINARY.exists()
    native=[check_native(reference,1),check_native(reference,4)]
    assert source_identity()==identity,'production source changed during verification'
    assert native[0]['output_sha256']==native[1]['output_sha256']
    evidence={'schema_version':1,'pin':'26.3','status':'passed','confidence':'high for recorded ordinary crafting domain',
      'ordinary_recipes':reference['ordinary_recipe_count'],'plain_ordinary_recipes':reference['plain_ordinary_recipe_count'],'patched_outputs_explicitly_unsupported':17,
      'java_queries':len(reference['observations']),'java_codec_edge_queries':len(reference['decoder_observations']),'native_admission_and_stale_plan_queries':len(extra_queries()),
      'query_categories':dict(collections.Counter(row['category'] for row in reference['queries'])),'native':native,'checks':checks,'build':build,
      'sources':{path:fingerprint(ROOT/path) for path in SOURCES},'inventory_dependency':fingerprint(ROOT/'src/inventory.bend'),'json_dependency':fingerprint(ROOT/'src/json.bend'),
      'tool':fingerprint(Path(__file__)),'reference_tool':fingerprint(Path(P.__file__)),'reference':fingerprint(P.OUTPUT),'binary':fingerprint(BINARY),
      'kernel_laws':re.findall(r'^law (\w+):',(ROOT/'src/crafting_recipe_laws.bend').read_text(),re.M),
      'limitations':['Finite Java fixtures validate versioned specification, not universal Java equivalence.','Kernel certifies eleven exact production laws; no universal bijective-matcher completeness theorem.','Source-pack resolution/tag recursion precedes catalog boundary.','17 patched result recipes and all other recipe subclasses remain explicit Unsupported.','No menu take/quickmove, award, recipe-book/autofill, world crafting-table, or special recipe implementation.','No GPU workload: bounded crafting executes sequential CPU logic.']}
    write_json(EVIDENCE,evidence)
    print(json.dumps({'status':evidence['status'],'java_queries':evidence['java_queries'],'native':native,'kernel_laws':len(evidence['kernel_laws'])},sort_keys=True))

if __name__=='__main__':main()
