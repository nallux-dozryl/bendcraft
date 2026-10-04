#!/usr/bin/env python3
"""Compare native Bend physical cooking codecs to actual pinned Java receivers."""
from __future__ import annotations
import argparse,base64,copy,json,re,time
import reference_cooking_block_entity_codec as P
import test_crafting_recipe_components as C
import test_nbt as N
from reference_inventory import ROOT,canonical,fingerprint,write_json

BINARY=P.CACHE/'native'
OWNED=['src/cooking_block_entity_codec.bend','src/cooking_block_entity_codec_nbt.bend','src/cooking_block_entity_codec_items.bend','src/cooking_block_entity_codec_components.bend','src/cooking_block_entity_codec_laws.bend','src/cooking_block_entity_codec_proof.bend','tests/cooking_block_entity_codec.bend','tools/cooking_block_entity_codec_proof.mjs','tools/test_cooking_block_entity_codec.py','tools/reference_cooking_block_entity_codec.py']
def pins():
    paths=set(OWNED)
    def visit(path):
        if path in paths and path not in OWNED:return
        paths.add(path)
        for file in re.findall(r'^import (\.[^\s]+)',(ROOT/path).read_text(),re.M):
            target=(ROOT/path).parent/file
            relative=str(target.resolve().relative_to(ROOT))
            if relative not in paths:visit(relative)
    for path in OWNED:
        if path.endswith('.bend'):visit(path)
    return {p:fingerprint(ROOT/p)['sha256'] for p in sorted(paths)}
def request():
    prior=json.loads((ROOT/'reference/furnace_authority.json').read_text())
    defaults={r['id']:r['components'] for r in prior['defaults']}
    ids={'minecraft:coal','minecraft:beef','minecraft:stone','minecraft:dirt','minecraft:suspicious_stew','minecraft:bowl'}
    items=[{**r,'components':defaults[r['id']]} for r in json.loads((ROOT/'reference/cooking_recipe.json').read_text())['items'] if r['id'] in ids]
    cases=[{**r,'bytes':list(base64.b64decode(r['bytes']))} for r in P.inputs()]
    cases.extend([{'id':'truncated_wire','kind':'smelting','bytes':[10,0,0]},{'id':'noncompound_root','kind':'campfire','bytes':[8,0,0,0,0]}])
    return {'items':items,'cases':cases}
def effective(value,defaults):
    if value is None:return None
    if value['components']=='':components=defaults[value['id']]
    else:
        marker,limit,body=value['components'].split('\t');assert marker=='BendCraftComponents1'
        components=json.loads(body);assert int(limit)==components.get('minecraft:max_stack_size',1)
    return {'id':value['id'],'count':value['count'],'components':components}
def state(value,defaults):
    value=copy.deepcopy(value);value['slots']=[effective(v,defaults) for v in value['slots']];return value
def java_state(value):
    value=copy.deepcopy(value)
    value['slots']=[None if v is None else {k:v[k] for k in ['id','count','components']} for v in value['slots']]
    for key in ['progress','total']:
        if key in value:value[key]=[v&0xffffffff for v in value[key]]
    return value
def normalized(value):
    if 'speed_bits' in value:
        bits=value['speed_bits']
        if bits&0x7f800000==0x7f800000 and bits&0x7fffff:value={**value,'speed_bits':0x7fc00000}
        if bits==0x80000000:value={**value,'speed_bits':0}
    return value
def physical(value):
    # Compare unordered compound objects while retaining all physical tag types,
    # list headers, numeric raw bits, array lengths and patch-list order.
    if value.kind==10:return (10,tuple(sorted((name,physical(v)) for name,v in value.payload)))
    if value.kind==9:return (9,value.payload[0],tuple(map(physical,value.payload[1])))
    return (value.kind,value.payload)
def cooking_body(value,campfire):
    keys={'Items','CookingTimes','CookingTotalTimes'} if campfire else {'Items','RecipesUsed','cooking_time_spent','cooking_total_time','lit_time_remaining','lit_total_time','speed_multiplier'}
    return N.Value(10,tuple((name,v) for name,v in value.payload if name in {N.text(k) for k in keys}))
def baseline(campfire):
    dirt={'id':'minecraft:dirt','count':1 if campfire else 2,'components':''}
    if campfire:return {'slots':[dirt,None,None,None],'progress':[11,22,33,44],'total':[101,202,303,404]}
    return {'slots':[dirt,None,None],'cookingTimer':51,'cookingTotalTime':61,'litTimeRemaining':31,'litTotalTime':41,'speed_bits':0x40000000,'uses':{'probe:previous':7}}
def compare(actual,observed,data):
    defaults={r['id']:r['components'] for r in data['items']}
    assert len(actual)==len(observed['observations'])+2
    refused=0;accepted=0;owner_refused=0
    for a,j,r in zip(actual,observed['observations'],data['cases']):
        assert a['id']==j['id']==r['id'];campfire=r['kind'] in ['campfire','soul_campfire']
        if r['id']=='unsupported_valid_patch':
            assert a['status']=='refused' and 'persistent component setter' in a['message'];refused+=1
        else:
            assert a['status']=='accepted',(a,j)
            expected=java_state(j['state']);got=state(a['state'],defaults)
            assert got==expected,(r['id'],'record',got,expected)
            assert state(a['roundtrip'],defaults)==normalized(expected),(r['id'],'roundtrip',a)
            encoded=N.parse(bytes(a['bytes']));saved=N.parse(base64.b64decode(j['saved']))
            assert encoded.name==(),r['id']
            assert physical(encoded.value)==physical(cooking_body(saved.value,campfire)),(r['id'],'physical body',physical(encoded.value),physical(cooking_body(saved.value,campfire)))
            accepted+=1
        load=a['load'];should_refuse=r['id'] in ['unsupported_valid_patch','overstack']
        assert load['status']==('refused' if should_refuse else 'accepted'),(r['id'],load)
        if campfire:
            got=state(load['owner'],defaults);assert load['kind']=='soul' and load['lit'] is True
            assert load['cache']==('probe:previous' if should_refuse else None)
        else:
            owner=load['owner'];got=state(owner['state'],defaults)
            assert owner['hidden']=={'id':'minecraft:stone','count':5,'components':''},(r['id'],'hidden owner')
            assert owner['cache']==('probe:previous' if should_refuse else None)
        wanted=state(baseline(campfire),defaults) if should_refuse else java_state(j['state'])
        assert got==wanted,(r['id'],'owner',got,wanted)
        if should_refuse:owner_refused+=1
    for a,r in zip(actual[-2:],data['cases'][-2:]):
        assert a['status']=='refused' and a['load']['status']=='refused'
        campfire=r['kind']=='campfire';load=a['load'];owner=load['owner'] if campfire else load['owner']['state']
        assert state(owner,defaults)==state(baseline(campfire),defaults)
        assert (load['cache'] if campfire else load['owner']['cache'])=='probe:previous'
    return {'java_physical_receivers':len(observed['observations']),'exact_physical_body_comparisons':accepted,'explicit_component_domain_refusals':refused,'admission_owner_refusals':owner_refused,'malformed_wire_owner_refusals':2,'selected_initialized_item_profiles':len(defaults)}
def proof():
    folder=P.CACHE/'proof';folder.mkdir(parents=True,exist_ok=True)
    _,export=C.run([C.NODE,'--experimental-transform-types','--max-old-space-size=2048','--stack-size=4096',ROOT/'tools/cooking_block_entity_codec_proof.mjs',ROOT],90)
    result,kernel=C.run(['/usr/bin/env','LEAN_STACK_SIZE=4194304',C.KERNEL,folder/'selected.bendtt'],60)
    assert result.stdout.strip()=='ALL PROOFS CHECK'
    selection=json.loads((folder/'selection.json').read_text());assert not selection['exclusions']
    receipt={'status':'passed','export':export,'kernel':kernel,'selection':selection,'artifact':fingerprint(folder/'selected.bendtt'),'kernel_binary':fingerprint(C.KERNEL),'scope':'Actual owner refusal/retention, missing-item clearing, physical signed integer preservation, campfire prefix/record composition, malformed component/effect sibling retention. The full encoding/JSON graph is ordinary checked and native compared; independent kernel rejects existing json.encode_go affine live descent.'}
    write_json(ROOT/'evidence/cooking-block-entity-codec-proof.json',receipt);return receipt

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--proof-only',action='store_true');parser.add_argument('--reuse-built',action='store_true');parser.add_argument('--cases',help='Comma-separated changed physical receiver IDs; malformed-wire owner refusals remain included.');args=parser.parse_args()
    if args.proof_only:print(json.dumps({'laws':len(proof()['selection']['roots'])}));return
    observed=json.loads(P.OUTPUT.read_text());assert observed['pin']=='26.3' and observed['source_sha256']==P.hashlib.sha256(P.SOURCE.encode()).hexdigest() and observed['inputs_sha256']==P.hashlib.sha256(canonical(P.inputs())).hexdigest()
    data=request()
    if args.cases:
        selected=set(args.cases.split(','));data['cases']=[r for r in data['cases'] if r['id'] in selected or r['id'] in {'truncated_wire','noncompound_root'}];observed={**observed,'observations':[r for r in observed['observations'] if r['id'] in selected]};assert len(observed['observations'])==len(selected)
    path=P.CACHE/('native-lists-input.json' if args.cases else 'native-input.json');write_json(path,data);before=pins()
    _,checked=C.run([C.BEND,ROOT/'tests/cooking_block_entity_codec.bend','--check-only'],60)
    if args.reuse_built:built={'status':0,'command':[str(C.BEND),str(ROOT/'tests/cooking_block_entity_codec.bend'),'-o',str(BINARY)],'reuse':'Successful targeted build from the current session; source unchanged since construction.'}
    else:_,built=C.run([C.BEND,ROOT/'tests/cooking_block_entity_codec.bend','-o',BINARY],180)
    assert pins()==before
    outputs=[];runs=[]
    for threads in [1,4]:
        result,receipt=C.run(['/usr/bin/env',f'BEND_THREADS={threads}','BEND_GPU=0',BINARY,path],90)
        actual=json.loads(result.stdout);counts=compare(actual,observed,data);outputs.append(canonical(actual));runs.append({'threads':threads,**receipt,'counts':counts})
    assert outputs[0]==outputs[1] and pins()==before
    receipt={'status':'passed','source_check':checked,'build':built,'runs':runs,'output_sha256':P.hashlib.sha256(outputs[0]).hexdigest(),'sources':before,'reference':fingerprint(P.OUTPUT),'binary':fingerprint(BINARY),'native_input':fingerprint(path),'limitations':['No full base BlockEntity CustomName/Lock/components interpretation: exact raw extras are retained in Details and known-body encoder omits them for the future base consumer.','Known persistent setters outside the shared seven-setter codec domain explicitly refuse the whole load; raw canonical envelope alone never authenticates metadata.','Actual physical ItemStack codec accepts count99 even for limit64. Typed records preserve this; live FA/CA owners refuse it atomically pending a coordinated raw-overstack authority extension.','Distinct physical names which normalize to the same recipe identifier refuse rather than invent Java map traversal order.','Durable region writer, physical compression/region framing and live world-save recovery remain the root integration seam.']}
    write_json(ROOT/('evidence/cooking-block-entity-codec-lists.json' if args.cases else 'evidence/cooking-block-entity-codec.json'),receipt);print(json.dumps(counts))
if __name__=='__main__':main()
