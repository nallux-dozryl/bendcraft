#!/usr/bin/env python3
"""Compare actual Bend cooking to pinned Java receiver observations."""
from __future__ import annotations
import argparse,json,re
import reference_cooking_recipe_probe as P
import test_crafting_recipe_components as C
from reference_inventory import ROOT,canonical,fingerprint,write_json

BINARY=ROOT/'build/cooking-recipe-tests'
EVIDENCE=ROOT/'evidence/cooking-recipe.json'
SOURCES=['src/cooking_recipe.bend','src/cooking_recipe_decoder.bend','src/cooking_recipe_number.bend','src/cooking_recipe_laws.bend','src/cooking_recipe_proof.bend','tests/cooking_recipe.bend','src/crafting_recipe.bend','src/crafting_recipe_decoder.bend','src/crafting_recipe_components.bend','src/crafting_recipe_component_registry.bend','src/inventory.bend','src/json.bend','src/u32_decimal.bend','tools/cooking_recipe_proof.mjs']
def identity():return {p:fingerprint(ROOT/p)['sha256'] for p in SOURCES}

def proof():
    folder=P.CACHE/'proof';folder.mkdir(parents=True,exist_ok=True)
    roots=['cooking_recipe_laws:'+name for name in re.findall(r'^law (\w+):',(ROOT/'src/cooking_recipe_laws.bend').read_text(),re.M)]
    # Reuse the established read-only checked-root export workflow; source
    # bodies/types and all original declaration maps are retained verbatim.
    path=ROOT/'tools/cooking_recipe_proof.mjs'
    _,exported=C.run([C.NODE,'--experimental-transform-types','--max-old-space-size=2048','--stack-size=4096',path,ROOT],120)
    result,checked=C.run(['/usr/bin/env','LEAN_STACK_SIZE=4194304',C.KERNEL,folder/'selected.bendtt'],60)
    assert result.stdout.strip()=='ALL PROOFS CHECK'
    selected=json.loads((folder/'selection.json').read_text());assert selected['roots']==roots and not selected['exclusions']
    receipt={'status':'passed','export':exported,'kernel':checked,'selection':selected,'artifact':fingerprint(folder/'selected.bendtt'),'compiler_api':[fingerprint(ROOT.parent/'bend/bend2'/p) for p in ['bend.ts','safe.ts']],'kernel_binary':fingerprint(C.KERNEL),'scope':'Seventeen production structural/authority/consumption/snapshot laws. No theorem of IEEE arithmetic, JSON codec equivalence, block ticking or world XP behavior.'}
    write_json(ROOT/'evidence/cooking-recipe-proof.json',receipt);return receipt

def effective(slot,defaults):
    if slot is None:return None
    component=slot['components']
    if component=='':profile=defaults[slot['id']]
    else:
        fields=component.split('\t');assert len(fields)==3 and fields[0]=='BendCraftComponents1',component
        profile=json.loads(fields[2]);assert int(fields[1])==profile.get('minecraft:max_stack_size',1)
    return {'id':slot['id'],'count':slot['count'],'components':profile}

def java_stack(slot):
    if slot['empty']:return None
    return {k:slot[k] for k in ['id','count','components']}

def request(inputs):
    catalog=json.loads((P.CACHE/'production-catalog.json').read_text());catalog['recipes']=[]
    return {'catalog':catalog,**inputs}

def compare(actual,java,inputs):
    defaults={r['id']:r['components'] for r in json.loads((ROOT/'reference/crafting_recipe_components.json').read_text())['defaults']}
    defaults.update({r['id']:r['components'] for r in java['defaults']})
    observed={r['id']:r for r in java['recipes']};unsupported={'bendcraft:time_fractional','bendcraft:time_overflow','bendcraft:unimplemented_setter','bendcraft:other_subclass'}
    assert len(actual['recipes'])==len(java['recipes'])
    accepted=errors=unsupported_count=matches=0
    for r in actual['recipes']:
        j=observed[r['id']]
        if r['id'] in unsupported:
            assert r['status']=='unsupported' and j['accepted'],(r,j);unsupported_count+=1;continue
        if not j['accepted']:
            assert r['status']=='error',(r,j);errors+=1;continue
        assert r['status']=='accepted',(r,j)
        assert r['cooking_time']==j['cooking_time'] and r['experience_bits']==j['experience_bits'],(r,j)
        assert effective(r['output'],defaults)==java_stack(j['output']),(r,j)
        assert r['matches']==[s['matches'] for s in j['matches']],(r,j)
        accepted+=1;matches+=len(r['matches'])
    queries={r['id']:r for r in java['queries']};query_inputs={r['id']:r for r in inputs['queries']};query_refusals=0
    for r in actual['queries']:
        j=queries[r['id']];source=query_inputs[r['id']]
        if source['boundary']:
            assert 'error' in r,(r,j);query_refusals+=1;continue
        assert r['recipe']==j['recipe'] and effective(r['output'],defaults)==(java_stack(j['output']) if j['output'] else None),(r,j)
    transitions={r['id']:r for r in java['transitions']};sources={r['id']:r for r in inputs['transitions']};accepts=refusals=0
    for r in actual['transitions']:
        j=transitions[r['id']];source=sources[r['id']];boundary=source['boundary'];result=r['completion']
        # Stale/forged/campfire/admission refusals belong to the safe production
        # boundary, beyond the raw private Java canBurn/burn receiver.
        if boundary:
            assert not result['accepted'],(r,j);refusals+=1;continue
        assert r['can_burn']==j['can_burn'] and result['accepted']==j['accepted'],(r,j)
        if result['accepted']:
            assert result['snapshot_current'] and [effective(s,defaults) for s in result['after']]==[java_stack(s) for s in j['after']],(r,j)
            accepts+=1
        else:refusals+=1
    assert actual['times']==java['times'],[(a,b) for a,b in zip(actual['times'],java['times']) if a!=b]
    assert len(actual['xp'])==len(java['xp'])
    for a,b in zip(actual['xp'],java['xp']):
        # NaN payload/sign propagation is not an observable XP amount or RNG
        # threshold. Preserve it in observations, compare IEEE NaN as NaN.
        def nan(bits):return bits&0x7f800000==0x7f800000 and bits&0x007fffff!=0
        same_fraction=a['fraction_bits']==b['fraction_bits'] or nan(a['fraction_bits']) and nan(b['fraction_bits'])
        assert a['id']==b['id'] and a['award']==b['award'] and a['advances_rng']==b['advances_rng'] and same_fraction,(a,b)
    return {'decoded_accepted':accepted,'decoded_rejected':errors,'explicitly_unsupported':unsupported_count,'ingredient_matches':matches,'registry_selection_queries':len(actual['queries']),'input_authority_refusals':query_refusals,'accepted_completions':accepts,'completion_refusals':refusals,'timing_receivers':len(actual['times']),'xp_arithmetic_receivers':len(actual['xp'])}

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--reuse-built',action='store_true');parser.add_argument('--proof-only',action='store_true');args=parser.parse_args()
    if args.proof_only:print(json.dumps({'laws':len(proof()['selection']['roots'])}));return
    inputs,_=P.inputs();java=json.loads(P.OUTPUT.read_text())
    assert java['pin']=='26.3' and java['source_sha256']==P.P.sha(P.SOURCE.encode()) and java['inputs_sha256']==P.P.sha(canonical(inputs))
    path=P.CACHE/'native-input.json';write_json(path,request(inputs));pins=identity();cache=P.CACHE/'native-build.json';build=None
    _,checked=C.run([C.BEND,'tests/cooking_recipe.bend','--check-only'],60)
    if args.reuse_built:
        saved=json.loads(cache.read_text());assert saved['sources']==pins and saved['binary_sha256']==fingerprint(BINARY)['sha256']
    else:
        _,build=C.run([C.BEND,'tests/cooking_recipe.bend','-o',BINARY],180)
        assert identity()==pins,'source changed during cooking build'
        write_json(cache,{'sources':pins,'binary_sha256':fingerprint(BINARY)['sha256'],'build':build})
    receipts=[];counts=None
    for threads in [1,4]:
        result,receipt=C.run([BINARY,'--threads',threads,'--gpu','off',path],90);actual=json.loads(result.stdout);counts=compare(actual,java,inputs)
        write_json(P.CACHE/f'native-output-{threads}.json',actual);receipt.pop('stdout');receipt['output_sha256']=P.P.sha(result.stdout.encode());receipts.append(receipt)
    assert identity()==pins and receipts[0]['output_sha256']==receipts[1]['output_sha256']
    write_json(EVIDENCE,{'status':'passed','pin':'26.3','installed_recipes':java['installed_types'],'counts':counts,'native':receipts,'ordinary_check':checked,'build':build,'sources':pins,'binary':fingerprint(BINARY),'reference':fingerprint(P.OUTPUT),'reference_tool':fingerprint(ROOT/'tools/reference_cooking_recipe_probe.py'),'test_tool':fingerprint(ROOT/'tools/test_cooking_recipe.py'),'limitations':['Fuel resolution, timer progression, slot arrays/atomic application, RecipeManager caching, recipesUsed persistence, XP orb spawning, campfire block ticking/drop integration and UI are consumer work.','Ingredient membership and output component identity reuse the committed shared crafting contracts. Metadata in fixtures is explicitly derived from trusted decoded templates, not generic inventory wire input.','Duration numeric coercions outside signed integer lexemes and unsupported component setters are retained as Unsupported.','XP tests invoke actual Mth arithmetic; world createExperience bytecode grounds the ticket threshold, but the whole receiver is not invoked. NaN payload/sign is recorded and compared semantically as NaN.','Finite native fixtures establish observed parity, separately from seventeen structural kernel laws.']})
    print(json.dumps({'status':'passed',**counts,'native':receipts},sort_keys=True))

if __name__=='__main__':main()
