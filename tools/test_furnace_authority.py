#!/usr/bin/env python3
"""Narrow production furnace checks and independent Java comparison."""
from __future__ import annotations
import argparse,json,re
import reference_furnace_authority_probe as P
import test_crafting_recipe_components as C
from reference_inventory import ROOT,canonical,fingerprint,write_json

BINARY=ROOT/'build/furnace-authority-tests'
SOURCES=['src/furnace_authority.bend','src/furnace_authority_fuel.bend','src/furnace_authority_decoder.bend','src/furnace_authority_slots.bend','src/furnace_authority_xp.bend','src/furnace_authority_laws.bend','src/furnace_authority_proof.bend','tests/furnace_authority.bend','src/cooking_recipe.bend','src/cooking_recipe_decoder.bend','src/cooking_recipe_number.bend','src/crafting_recipe.bend','src/crafting_recipe_decoder.bend','src/crafting_recipe_components.bend','src/crafting_recipe_component_registry.bend','src/inventory.bend','src/json.bend','src/u32_decimal.bend','tools/furnace_authority_proof.mjs']
def identity():return {p:fingerprint(ROOT/p)['sha256'] for p in SOURCES}

def proof():
    folder=P.CACHE/'proof';folder.mkdir(parents=True,exist_ok=True)
    _,export=C.run([C.NODE,'--experimental-transform-types','--max-old-space-size=2048','--stack-size=4096',ROOT/'tools/furnace_authority_proof.mjs',ROOT],90)
    result,kernel=C.run(['/usr/bin/env','LEAN_STACK_SIZE=4194304',C.KERNEL,folder/'selected.bendtt'],60)
    assert result.stdout.strip()=='ALL PROOFS CHECK'
    selected=json.loads((folder/'selection.json').read_text());roots=['furnace_authority_laws:'+n for n in re.findall(r'^law (\w+):',(ROOT/'src/furnace_authority_laws.bend').read_text(),re.M)]
    assert selected['roots']==roots and not selected['exclusions']
    receipt={'status':'passed','export':export,'kernel':kernel,'selection':selected,'artifact':fingerprint(folder/'selected.bendtt'),'kernel_binary':fingerprint(C.KERNEL),'scope':'Actual affine owner rollback/admission, cache retention, fuel remainder routing and shared consumption boundary, provider fallback/arithmetic refusal, persisted field preservation and keyed XP structural laws. No theorem of complete IEEE timer arithmetic or whole Java server/world equivalence.'}
    write_json(ROOT/'evidence/furnace-authority-proof.json',receipt);return receipt

def request(observed):
    _,tags,_=P.P.resources()
    old=json.loads((ROOT/'reference/cooking_recipe.json').read_text())
    maps={r['id']:r['components'] for r in observed['defaults']}
    items=[{**r,'components':maps[r['id']]} for r in old['items']]
    data=P.inputs()
    return {'catalog':{'items':items,'tags':[{'id':k,'items':v} for k,v in tags.items()],'recipes':data['recipes']},'fuel_catalog':json.loads((P.CACHE/'fuel-catalog.json').read_text()),'cases':data['cases'],'xp_cases':data['xp_cases'],'values':[{k:r[k] for k in ['id','block']} for r in observed['values']]}

def effective(value,defaults):
    if value is None:return None
    payload=value['components']
    if payload=='':components=defaults[value['id']]
    else:
        marker,limit,profile=payload.split('\t');assert marker=='BendCraftComponents1';components=json.loads(profile);assert int(limit)==components.get('minecraft:max_stack_size',1)
    return {'id':value['id'],'count':value['count'],'components':components}
def java_stack(value):return None if value['empty'] else {k:value[k] for k in ['id','count','components']}
def compare(actual,observed):
    assert actual['values']==observed['values'],'fuel/context receiver mismatch'
    defaults={r['id']:r['components'] for r in observed['defaults']};steps=0
    assert len(actual['cases'])==len(observed['cases'])
    for a,j in zip(actual['cases'],observed['cases']):
        assert a['id']==j['id'] and len(a['steps'])==len(j['steps'])
        for x,y in zip(a['steps'],j['steps']):
            ax,jy=x['after'],y['after'];assert {k:v for k,v in ax.items() if k!='slots'}=={k:v for k,v in jy.items() if k!='slots'},(a['id'],ax,jy)
            assert [effective(s,defaults) for s in ax['slots']]==[java_stack(s) for s in jy['slots']],(a['id'],ax,jy)
            assert [effective(s,defaults) for s in x['drops']]==[java_stack(s) for s in y['drops']],(a['id'],x,y)
            assert x['dirty']==y['dirty'] and x['lit_change']==y['lit_change'],(a['id'],x,y)
            steps+=1
    assert len(actual['xp_cases'])==len(observed['xp_cases'])
    for a,j in zip(actual['xp_cases'],observed['xp_cases']):
        assert a['id']==j['id'] and a['status']==j['status'] and a['uses']==j['after']['uses'],(a,j)
        if a['status']=='accepted':assert a['requests']==j['requests'],(a,j)
        else:assert j['exception']=='java.lang.ClassCastException',(a,j)
    return {'initialized_fuel_items':sum('fuel' in r for r in observed['items']),'fuel_context_receivers':len(actual['values']),'owned_state_scenarios':len(actual['cases']),'owned_state_steps':steps,'initialized_component_defaults':len(defaults),'current_registry_xp_receivers':len(actual['xp_cases'])}

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--proof-only',action='store_true');parser.add_argument('--reuse-built',action='store_true');args=parser.parse_args()
    if args.proof_only:print(json.dumps({'laws':len(proof()['selection']['roots'])}));return
    observed=json.loads(P.OUTPUT.read_text());data=P.inputs();providers,_=P.resources();data['providers']=providers
    assert observed['pin']=='26.3' and observed['source_sha256']==P.P.sha(P.SOURCE.encode()) and observed['inputs_sha256']==P.P.sha(canonical(data))
    path=P.CACHE/'native-input.json';write_json(path,request(observed));pins=identity()
    _,checked=C.run([C.BEND,ROOT/'tests/furnace_authority.bend','--check-only'],60)
    cache=P.CACHE/'native-build.json'
    if args.reuse_built:
        saved=json.loads(cache.read_text());assert saved['sources']==pins and saved['binary_sha256']==fingerprint(BINARY)['sha256'];built=None
    else:
        _,built=C.run([C.BEND,ROOT/'tests/furnace_authority.bend','-o',BINARY],180)
        assert identity()==pins,'source changed during targeted furnace build'
        write_json(cache,{'sources':pins,'binary_sha256':fingerprint(BINARY)['sha256']})
    runs=[];outputs=[]
    for threads in [1,4]:
        result,receipt=C.run(['/usr/bin/env',f'BEND_THREADS={threads}','BEND_GPU=0',BINARY,path],90)
        actual=json.loads(result.stdout);counts=compare(actual,observed);outputs.append(canonical(actual));runs.append({'threads':threads,**receipt,'counts':counts})
    assert outputs[0]==outputs[1] and identity()==pins
    receipt={'status':'passed','source_check':checked,'build':built,'runs':runs,'output_sha256':P.P.sha(outputs[0]),'sources':pins,'reference':fingerprint(P.OUTPUT),'reference_tool':fingerprint(ROOT/'tools/reference_furnace_authority_probe.py'),'native_input':fingerprint(path),'binary':fingerprint(BINARY),'limitations':['Future world/block entity consumer must apply drops/LIT/dirty effects at 20 Hz and own block lifecycle, slot transfer permissions, recipe reload, RNG and XP orb/player awards.','Typed Persisted seam preserves vanilla fields; physical NBT/live durable-save integration is not implemented here.','Installed provider expression domain is constant/reference/div/conditional/match_block; other provider/predicate subclasses are preserved and explicitly refuse evaluation.','XP traversal order is supplied by caller: Java Reference2IntOpenHashMap iteration depends on process object identity and is not replaced by invented canonical ordering.']}
    write_json(ROOT/'evidence/furnace-authority.json',receipt);print(json.dumps(counts))
if __name__=='__main__':main()
