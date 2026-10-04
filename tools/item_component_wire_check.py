#!/usr/bin/env python3
"""Actual complete inventory owners and canonical component wire gate replay."""
from __future__ import annotations
import argparse,copy,hashlib,json,subprocess,time
from pathlib import Path
import build_native
import item_component_check as C
import item_component_inventory_check as Codec
from reference_inventory import ROOT,write_json,fingerprint,canonical

BUILD=ROOT/'build/item_component_wire';EVIDENCE=ROOT/'evidence/item_component_wire.json'
TABLE=Codec.TABLE;REFERENCE=ROOT/'reference/item_component.json';BEND=Codec.BEND
def pin(p):return {'path':str(Path(p).resolve()),**fingerprint(Path(p))}
def run(args,timeout=180):
    start=time.monotonic();p=subprocess.run(list(map(str,args)),cwd=ROOT,capture_output=True,text=True,timeout=timeout)
    return {'command':list(map(str,args)),'exit_code':p.returncode,'seconds':round(time.monotonic()-start,6),'stdout':p.stdout,'stderr':p.stderr}
def line(value):return json.dumps(value,separators=(',',':'),ensure_ascii=True)
def slot(value):return [0] if value is None else [1,value['id'],value['components'],value['count']]
def reply(case):
    main=[case['selected'],case['instabuild'],case['maybuild'],list(map(slot,case['backing'][:36]))]
    if case['mode']=='wire_main':return [1,4,case['epoch'],281474976710655,main]
    status=[case['invulnerable'],case['mayfly'],case['flying'],case['walking'],case['flying_speed']]
    body=[main,list(map(slot,case['backing'][36:43])),status,list(map(slot,case['backing'][43:47])),slot(case['backing'][47]),
        [0] if case['result'] is None else [1,slot(case['result'])],case['opened'],281474976710655 if case.get('maximum_header') else case['revision']]
    return [1,6,case['epoch'],281474976710655,False,case['diagnostic'],body]
def owner(name,mode='acquire',**changes):
    value=Codec.owner(name);value.update(mode=mode,result={'id':'minecraft:stone','components':'','count':3},index=2,button=0,
        id=C.ITEM,components='',count=1,epoch='typed-stew',diagnostic='',maximum_header=False)
    value.update(changes);return value
def owner_expected(case):
    value=Codec.expected_state(case);value['result']=case['result'];return value
def cases(reference):
    base=reference['default_components'];out=[]
    for row in reference['rows'][:17]:
        key=C.identity(row['components'],base);stack={'id':C.ITEM,'components':key,'count':1}
        for count in [0,1,2]:out.append({'name':row['id']+'/structural/'+str(count),'mode':'structural','id':C.ITEM,'components':key,'count':count,'expected':count==1})
        for count in [0,1,2]:
            dto=[1,1,'typed-stew',1,[7,2,[C.ITEM,key],count]]
            out.append({'name':row['id']+'/acquire-wire/'+str(count),'mode':'request','wire':line(dto),'dto':dto,'expected':count<=1})
        for count in [0,1,2]:
            x=owner(row['id']+'/acquire-owner/'+str(count),components=key,count=count,expected=count<=1)
            x['backing'][2]=copy.deepcopy(stack);out.append(x)
        x=owner(row['id']+'/pickup-owner','pickup',components=key,index=38,expected=True)
        x['backing'][2]=copy.deepcopy(stack);out.append(x)
        for mode in ['wire_main','wire_menu']:
            x=owner(row['id']+'/'+mode,mode,result=copy.deepcopy(stack),epoch='"'*64,diagnostic='\U00010000'*2048,maximum_header=True,instabuild=False,maybuild=False,invulnerable=False,mayfly=False,flying=False,walking=0xffffffff,flying_speed=0xffffffff,opened=False,expected=True)
            x['backing'][:48]=[copy.deepcopy(stack) for _ in range(48)];out.append(x)
            dto=reply(x);out.append({'name':row['id']+'/'+mode+'/independent-decode','mode':'reply','wire':line(dto),'dto':dto,'expected':True})
    first=C.identity(reference['rows'][0]['components'],base)
    for catalog in ['missing','disabled','wrong_digest','wrong_limit']:
        out.append(owner('catalog-owner/'+catalog,catalog=catalog,components=first,expected=False))
    out.append(owner('ability-owner',instabuild=False,components=first,expected=False))
    out.append(owner('bounds-owner',index=36,components=first,expected=False))
    component_cases=C.cases(reference)
    for bad in [x for x in component_cases if x['mode']=='validate' and not x['expected'] and x.get('defaults') is not False]:
        name='bad-profile/'+bad['name'];key=bad['components'];item=bad['id']
        out.append({'name':name+'/structural','mode':'structural','id':item,'components':key,'count':1,'expected':False})
        dto=[1,1,'typed-stew',1,[7,2,[item,key],1]];out.append({'name':name+'/request','mode':'request','wire':line(dto),'dto':dto,'expected':False})
        out.append(owner(name+'/acquire-owner',id=item,components=key,expected=False))
        x=owner(name+'/pickup-owner','pickup',index=38,expected=False);x['backing'][2]={'id':item,'components':key,'count':1};out.append(x)
        x=owner(name+'/carried-encode','wire_menu',expected=False);x['backing'][47]={'id':item,'components':key,'count':1};out.append(x)
        x=owner(name+'/result-encode','wire_menu',result={'id':item,'components':key,'count':1},expected=False);out.append(x)
        for target in ['carried','result']:
            x=owner(name+'/'+target+'-decode','wire_menu')
            if target=='carried':x['backing'][47]={'id':item,'components':key,'count':1}
            else:x['result']={'id':item,'components':key,'count':1}
            dto=reply(x);out.append({'name':name+'/'+target+'-decode','mode':'reply','wire':line(dto),'dto':dto,'expected':False})
    # A valid ordered typed profile can exceed a complete-menu transport bound.
    # The encoder must refuse the complete reply, without truncating identities.
    effective=copy.deepcopy(base);effective[C.EFFECTS]=[{'id':'minecraft:speed','duration':20}]*20
    long=C.identity(effective,base);stack={'id':C.ITEM,'components':long,'count':1}
    out.append({'name':'long-valid-structural','mode':'structural','id':C.ITEM,'components':long,'count':1,'expected':True})
    x=owner('valid-profile-menu-transport-refusal','wire_menu',result=stack,epoch='z'*64,diagnostic='x'*2048,maximum_header=True,expected=False)
    x['backing'][:48]=[copy.deepcopy(stack) for _ in range(48)];assert len(line(reply(x)))>65536;out.append(x)
    dto=reply(x);out.append({'name':'overbudget-valid-menu-decode','mode':'reply','wire':line(dto),'dto':dto,'expected':False})
    for mode in ['wire_main','wire_menu']:
        x=owner('default-profile/'+mode,mode,expected=True);out.append(x)
        dto=reply(x);out.append({'name':'default-profile/'+mode+'/decode','mode':'reply','wire':line(dto),'dto':dto,'expected':True})
    for count in [0,99,100]:
        dto=[1,1,'typed-stew',1,[7,2,['minecraft:stone',''],count]]
        out.append({'name':'default-count/'+str(count),'mode':'request','wire':line(dto),'dto':dto,'expected':count<=99})
    return out
def verify(case,actual):
    mode=case['mode']
    if mode in ['acquire','pickup']:
        before=owner_expected(case);assert actual['before']==before,(case['name'],'complete before owner',actual)
        assert actual['status']['accepted']==case['expected'],(case['name'],actual)
        after=copy.deepcopy(before)
        if case['expected']:
            if mode=='acquire':after['backing'][case['index']]=None if case['count']==0 else {'id':case['id'],'components':case['components'],'count':case['count']}
            else:
                after['backing'][47]=after['backing'][2];after['backing'][2]=None;after['revision']+=1;after['result']=None
        assert actual['after']==after,(case['name'],'complete after owner',actual)
    elif mode.startswith('wire_'):
        assert actual['encoded']['accepted']==case['expected'],(case['name'],actual)
        if case['expected']:
            dto=reply(case);assert actual['encoded']['text']==line(dto),(case['name'],'independent exact ASCII output')
            assert actual['decoded']['accepted'] and actual['decoded']['value']==dto
            assert actual['decoded']['encoded']['text']==line(dto)
    elif mode in ['request','reply']:
        assert actual['accepted']==case['expected'],(case['name'],actual)
        if case['expected']:assert actual['value']==case['dto'] and actual['encoded']['text']==line(case['dto']),case['name']
    else:assert actual['accepted']==case['expected'],(case['name'],actual)
def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--build',action='store_true');parser.add_argument('--binary',type=Path);args=parser.parse_args();BUILD.mkdir(exist_ok=True)
    paths=[ROOT/'src'/x for x in ['player_inventory.bend','resource_client_wire.bend','item_component.bend','player_item_definitions.bend','item_component_wire_laws.bend','item_component_wire_proof.bend','crafting_recipe_components.bend','json.bend']]+[ROOT/'tests/item_component_wire.bend',ROOT/'tests/resource_client_interaction_wire.bend',ROOT/'tests/resource_client_framing.bend',Path(__file__),REFERENCE,TABLE]
    before=[pin(p) for p in paths];receipt={'status':'running','source_pins':before};write_json(EVIDENCE,receipt)
    try:
        parent=json.loads((ROOT/'reference/crafting_recipe_components.json').read_text());maps=parent['defaults'];assert len(maps)==1658
        assert all(isinstance(x.get('components'),dict) and 'error' not in x['components'] for x in maps)
        stew=next(x['components'] for x in maps if x['id']==C.ITEM);assert hashlib.sha256(canonical(stew)).hexdigest()=='7f324fff5c212f399a85e4e3962f34f634fdedeeddff5f6bb3e39dbf229b5c25'
        receipt['parent_initialized_defaults']={'maps':1658,'error_maps':0,'reference':pin(ROOT/'reference/crafting_recipe_components.json'),'stew_sha256':hashlib.sha256(canonical(stew)).hexdigest()}
        binary=args.binary.resolve() if args.binary else BUILD/'observer';delegation=['gate'] if args.binary else []
        if args.build:
            built=build_native.ensure_native(ROOT/'tests/item_component_wire.bend',binary,bend=BEND);write_json(BUILD/'native-build.json',built)
            receipt['build']={k:built[k] for k in ['path','binary_sha256','cache_key','cache_hit','timings']}
        assert binary.is_file(),'Run --build with one coordinated compiler slot'
        corpus=cases(json.loads(REFERENCE.read_text()));counts={};maximum=0
        for start in range(0,len(corpus),4):
            batch=corpus[start:start+4];path=BUILD/'fixtures.json';write_json(path,[{k:v for k,v in x.items() if k not in ['name','expected','dto']} for x in batch])
            result=run([binary,'--gpu','off','--threads','1','--',*delegation,TABLE,path]);assert result['exit_code']==0,result
            rows=result['stdout'].splitlines();assert len(rows)==len(batch),(start,result)
            for case,text in zip(batch,rows,strict=True):
                actual=json.loads(text);verify(case,actual);key=case['mode']+('/accepted' if case['expected'] else '/refused');counts[key]=counts.get(key,0)+1
                if case['mode']=='wire_menu' and case['expected']:maximum=max(maximum,len(actual['encoded']['text']))
            receipt.update(checked=start+len(batch),counts=counts);write_json(EVIDENCE,receipt)
        receipt['existing_default_wire']=run([binary,'--gpu','off','--threads','1','--',*delegation,'legacy'])
        legacy=receipt['existing_default_wire']
        if legacy['exit_code']==1 and legacy['stderr']=='bend: a Nat past the largest immediate 2^48-1\n' and not legacy['stdout']:
            legacy['status']='native-Nat-constructor-refused'
            legacy['scope']='The aggregate includes overflow_menu() constructing1n+Wire.nat_max(). NativeNat48 refuses that owner before its intended wire assertion. The complete legacy dispatcher is not certified; the stated614 wire comparisons are separate.'
        else:
            assert legacy['exit_code']==0,legacy
            legacy['status']='dispatcher-passed'
        receipt['existing_framing']=run([binary,'--gpu','off','--threads','1','--',*delegation,'framing']);assert receipt['existing_framing']['exit_code']==0,receipt['existing_framing']
        assert before==[pin(p) for p in paths],'Source changed during actual gate/wire replay'
        receipt.update(status='passed',cases=len(corpus),native_binary=pin(binary),maximum_all49_recipe_profile_menu_bytes=maximum,maximum_header_scope='49 nonempty profile stacks, 64 quote epoch, 2048 supplementary diagnostic scalars, False booleans, U32max raw status, Nat48max sequence/revision',
            existing_limits={'transport_ascii_bytes':65536,'parser_codepoints':65536,'parser_depth':8,'wire_AST_values':16384,'changed':False},
            owner_scope='Actual complete I.State observation:64 backing cells including16 hidden inadmissible entries, logical48, selected,abilities,all raw status words,menu result/revision/opened,catalog count. Full-owner laws include complete catalog/profile values.',
            persistence_depth='E.outer_limits6 remains sufficient: IC version3 bytes are extension.payload ByteArray; inner IC decoder independently applies depth8.',
            limits=['Long admitted ordered-effect profiles can exceed whole-menu transport; entire encode/decode refuses atomically','No session/world/socket authority or physical OS acceptance claim'],
            reproduce='python3 tools/item_component_wire_check.py --build')
        write_json(EVIDENCE,receipt);print(json.dumps({'status':'passed','cases':len(corpus),'counts':counts,'maximum_menu_bytes':maximum}))
    except BaseException as e:
        receipt.update(status='failed',error=repr(e));write_json(EVIDENCE,receipt);raise
if __name__=='__main__':main()
