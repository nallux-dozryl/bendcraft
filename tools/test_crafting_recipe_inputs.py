#!/usr/bin/env python3
"""Exercise real find_with_metadata with validated closed-profile authority."""
from __future__ import annotations
import argparse,json
import reference_crafting_recipe_inputs_probe as P
import test_crafting_recipe_components as C
from reference_inventory import ROOT,canonical,fingerprint,write_json

BINARY=ROOT/'build/crafting-recipe-input-tests'
EVIDENCE=ROOT/'evidence/crafting-recipe-inputs.json'
SOURCES=C.SOURCES+['tests/crafting_recipe_inputs.bend']

def identity():return {p:fingerprint(ROOT/p)['sha256'] for p in SOURCES}

def request(rows):
    data,templates=C.reference();req,_=C.request(data,templates)
    wanted={r['template_id'] for r in rows}|{r['other'] for r in rows if r['other'] is not None}
    selected=[r for r in templates if r['id'] in wanted]
    catalog=req['catalog'];catalog['recipes']=[r for r in catalog['recipes'] if r['id'] in wanted]
    for r in rows:
        record={'id':r['recipe_id'],'source':r['recipe_source']}
        if not any(old['id']==record['id'] for old in catalog['recipes']):catalog['recipes'].append(record)
    return {'catalog':catalog,'templates':selected,'queries':rows,'stew_defaults':req['stew_defaults']}

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--reuse-built',action='store_true');args=parser.parse_args()
    rows=P.inputs();data=json.loads(P.OUTPUT.read_text())
    assert data['pin']=='26.3' and data['source_sha256']==P.C.P.sha(P.SOURCE.encode()) and data['inputs_sha256']==P.C.P.sha(canonical(rows))
    req=request(rows);pins=identity();checks=[C.check_proof()]
    _,checked=C.run([C.BEND,'tests/crafting_recipe_inputs.bend','--check-only']);checks.append(checked)
    path=P.CACHE/'native-input.json';write_json(path,req);cache=P.CACHE/'native-build.json';build=None
    if args.reuse_built:
        saved=json.loads(cache.read_text());assert saved['sources']==pins and saved['binary_sha256']==fingerprint(BINARY)['sha256']
    else:
        _,build=C.run([C.BEND,'tests/crafting_recipe_inputs.bend','-o',BINARY],180)
        assert identity()==pins,'source changed during component-input build'
        write_json(cache,{'sources':pins,'binary_sha256':fingerprint(BINARY)['sha256'],'build':build})
    java={r['id']:r for r in data['cases']};native=[]
    refusal={'absent_authority','different_component_authority','overfull_stew','zero_stew','zero_metadata_limit','overlarge_metadata_limit','removed_effects_profile','non_stew_profile'}
    for threads in [1,4]:
        result,receipt=C.run([BINARY,'--threads',threads,'--gpu','off',path],60);actual=json.loads(result.stdout)
        assert len(actual)==len(rows)
        for observed in actual:
            id=observed['id']
            if id in refusal:wanted={'error':'invalid crafting grid: dimensions, slot count, item definition or components'}
            else:
                assert java[id]['matches'] and not java[id]['empty'],(id,java[id])
                assert len(java[id]['remainders'])==1
                wanted={'recipe':next(r['recipe_id'] for r in rows if r['id']==id),'output':java[id]['output'],'consumption':[{'slot':0,'count':1,'remainder':java[id]['remainders'][0]}]}
            assert observed['result']==wanted,(id,observed,wanted)
        receipt.pop('stdout');receipt.update(queries=len(actual),output_sha256=P.C.P.sha(result.stdout.encode()));native.append(receipt);write_json(P.CACHE/f'native-output-{threads}.json',actual)
    assert identity()==pins and native[0]['output_sha256']==native[1]['output_sha256']
    write_json(EVIDENCE,{'status':'passed','pin':'26.3','java_input_match_cases':len(data['cases']),'closed_profile_positive_cases':8,'admission_refusals':sorted(refusal),'native':native,'checks':checks,'build':build,'sources':pins,'binary':fingerprint(BINARY),'reference':fingerprint(P.OUTPUT),'reference_tool':fingerprint(ROOT/'tools/reference_crafting_recipe_inputs_probe.py'),'test_tool':fingerprint(ROOT/'tools/test_crafting_recipe_inputs.py'),'confidence':'high within the validated closed suspicious-stew profile and stated authority boundary','limitations':['Java ingredient matching ignores component changes; validated inventory admission deliberately refuses absent/incorrect authority and invalid stack counts before matching.','No arbitrary component prefix is accepted as input authority.','Finite cases do not prove whole Java equivalence or metadata authenticity from a public wire format.']})
    print(json.dumps({'status':'passed','native':native,'laws':len(checks[0]['selection']['roots'])},sort_keys=True))

if __name__=='__main__':main()
