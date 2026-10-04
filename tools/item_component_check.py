#!/usr/bin/env python3
"""Replay typed stew admission and physical stack NBT against pinned Java."""
from __future__ import annotations
import argparse, base64, copy, hashlib, json, re, struct, subprocess, time
from pathlib import Path
import build_native
from reference_inventory import ROOT, canonical, fingerprint, write_json

BUILD=ROOT/'build/item_component'
EVIDENCE=ROOT/'evidence/item_component.json'
BEND=Path.home()/'.bend/bin/bend'
REFERENCE=ROOT/'reference/item_component.json'
EFFECTS='minecraft:suspicious_stew_effects'
ITEM='minecraft:suspicious_stew'
HEADER='BendCraftComponents1\t1\t'
NODE='/opt/homebrew/Cellar/node/23.5.0/bin/node'
KERNEL=Path.home()/'.bend/bendtt/e15042434e73aab0/bendtt'

def pin(path):return {'path':str(Path(path).resolve()),**fingerprint(Path(path))}

def run(command, timeout=60):
    start=time.monotonic()
    try:
        p=subprocess.run(list(map(str,command)),cwd=ROOT,capture_output=True,text=True,timeout=timeout)
        result={'command':list(map(str,command)),'exit_code':p.returncode,'seconds':round(time.monotonic()-start,6),'stdout':p.stdout,'stderr':p.stderr}
    except subprocess.TimeoutExpired as e:
        result={'command':list(map(str,command)),'timeout_seconds':timeout,'seconds':round(time.monotonic()-start,6),'stdout':(e.stdout or b'').decode() if isinstance(e.stdout,bytes) else e.stdout,'stderr':(e.stderr or b'').decode() if isinstance(e.stderr,bytes) else e.stderr}
    return result

def identity(effective, base):return '' if effective==base else HEADER+canonical(effective).decode()

def fixture(name, mode, expected=True, **fields):return {'name':name,'mode':mode,'expected':expected,**fields}

def unsigned_effects(values):return [[e['id'],e.get('duration',160)&0xffffffff] for e in values]

# Independent tag reader/writer used only by the test runner. Product codecs
# remain in Bend. Compound ordering is physical; equality compares typed trees.
def payload(tag):
    kind=tag['type']
    if kind==1:return bytes([tag['bits']&255])
    if kind==3:return struct.pack('>I',tag['bits'])
    if kind==8:
        data=tag['value'].encode();return struct.pack('>H',len(data))+data
    if kind==9:
        values=tag['items']; element=tag.get('element_type',values[0]['type'] if values else 0)
        assert all(v['type']==element for v in values)
        return bytes([element])+struct.pack('>i',len(values))+b''.join(payload(v) for v in values)
    if kind==10:
        entries=tag['entries'].items() if isinstance(tag['entries'],dict) else tag['entries']
        return b''.join(bytes([v['type']])+struct.pack('>H',len(k.encode()))+k.encode()+payload(v) for k,v in entries)+b'\0'
    raise AssertionError(kind)

def wire(tag, name=''):return bytes([tag['type']])+struct.pack('>H',len(name.encode()))+name.encode()+payload(tag)

def parse_wire(data):
    offset=0
    def read(n):
        nonlocal offset
        result=data[offset:offset+n];assert len(result)==n;offset+=n;return result
    def text():return read(struct.unpack('>H',read(2))[0]).decode()
    def value(kind):
        if kind==1:return {'type':1,'bits':read(1)[0]}
        if kind==3:return {'type':3,'bits':struct.unpack('>I',read(4))[0]}
        if kind==8:return {'type':8,'value':text()}
        if kind==9:
            element=read(1)[0];size=struct.unpack('>i',read(4))[0];assert size>=0
            return {'type':9,'items':[value(element) for _ in range(size)]}
        if kind==10:
            entries={}
            while (child:=read(1)[0]):
                name=text();assert name not in entries;entries[name]=value(child)
            return {'type':10,'entries':entries}
        raise AssertionError(kind)
    kind=read(1)[0];name=text();result=value(kind);assert offset==len(data);return name,result

def normalized_tag(tag):
    result=copy.deepcopy(tag)
    for effect in result['entries']['components']['entries'][EFFECTS]['items']:
        effect['entries'].setdefault('duration',{'type':3,'bits':160})
    return result

def cases(reference):
    base=reference['default_components'];out=[]
    for row in reference['rows']:
        key=identity(row['components'],base); effects=unsigned_effects(row['components'][EFFECTS])
        out.append(fixture(row['id']+'/key','validate',id=ITEM,components=key,count=1,defaults=True,effects=effects,java_tag=row['tag']))
        out.append(fixture(row['id']+'/nbt','nbt',bytes=list(base64.b64decode(row['nbt_base64'])),defaults=True,effects=effects,key=key))
    primary=json.loads((ROOT/'reference/crafting_recipe_components.json').read_text())
    registry=primary['effects']
    names=[r['id'] if isinstance(r,dict) else r for r in registry]
    assert len(names)==40
    for name in names:
        for ticks in [0,1,159,160,161,-1,-2147483648,2147483647]:
            effective=copy.deepcopy(base);effect={'id':name}
            if ticks!=160:effect['duration']=ticks
            effective[EFFECTS]=[effect]
            out.append(fixture(f'{name}/{ticks}','validate',id=ITEM,components=identity(effective,base),count=1,defaults=True,effects=[[name,ticks&0xffffffff]]))
    key=out[0]['components']
    out += [fixture('initialized_complete','initialize',default_map=base),fixture('initialized_reordered','initialize',default_map=dict(reversed(list(base.items()))))]
    for name in base:
        changed=copy.deepcopy(base);del changed[name]
        out.append(fixture('missing_default/'+name,'initialize',False,default_map=changed))
    for name,value in [('unknown',{'minecraft:unknown':{}}),('changed',{'minecraft:max_stack_size':64}),('numeric_type',{'minecraft:repair_cost':'0'})]:
        changed=copy.deepcopy(base);changed.update(value);out.append(fixture('initialize_'+name,'initialize',False,default_map=changed))
    encoded=canonical(base).decode()
    # Without numeric AST checking this raw-number construction serialized to
    # the exact complete default map despite containing only one AST member.
    raw=encoded[len('{"minecraft:attack_animation":'):-1]
    out.append(fixture('numeric_AST_injection','initialize_ast_injection',False,raw_number=raw))
    negatives=[]
    def bad(name, components=key, id=ITEM, defaults=True):
        negatives.append(fixture(name,'validate',False,id=id,components=components,count=1,defaults=defaults))
    for name,value in [('marker','BendCraftComponents2'+key[len('BendCraftComponents1'):]),('limit',key.replace('\t1\t','\t64\t',1)),('opaque','{"minecraft:suspicious_stew_effects":[]}'),('patch','BendCraftPatch1\t{}'),('suffix',key+'\textra'),('truncated',key[:-1]),('whitespace',HEADER+' '+key[len(HEADER):]),('reordered',HEADER+json.dumps(dict(reversed(list(json.loads(key[len(HEADER):]).items()))),separators=(',',':')))]:bad(name,value)
    bad('unknown_item',id='minecraft:stone');bad('missing_initialized_defaults',defaults=False)
    good=json.loads(key[len(HEADER):])
    for name in base:
        effective=copy.deepcopy(good);del effective[name];bad('missing_effective/'+name,identity(effective,base))
    for name,value in [('unknown_component',{'minecraft:unknown':{}}),('changed_food',{'minecraft:food':{'nutrition':7,'saturation':7.2000003,'can_always_eat':True}}),('removed_component',{'!minecraft:food':{}}),('wrong_effect_type',{EFFECTS:{}}),('wrong_limit',{'minecraft:max_stack_size':2})]:
        effective=copy.deepcopy(good);effective.update(value);bad(name,identity(effective,base))
    malformed_effects=[{}, {'id':'minecraft:unknown'}, {'id':1}, {'id':'speed'}, {'id':'minecraft:speed','unknown':True}, {'id':'minecraft:speed','duration':'20'}, {'id':'minecraft:speed','duration':True}, {'id':'minecraft:speed','duration':None}, {'id':'minecraft:speed','duration':1.5}, {'id':'minecraft:speed','duration':2147483648}, {'id':'minecraft:speed','duration':-2147483649}, {'id':'minecraft:speed','duration':160}]
    for index,effect in enumerate(malformed_effects):
        effective=copy.deepcopy(good);effective[EFFECTS]=[effect];bad('malformed_effect/'+str(index),identity(effective,base))
    bad('duplicate_effect_field',key.replace('"duration":60','"duration":60,"duration":60',1))
    bad('duplicate_component',key[:-1]+',"minecraft:repair_cost":0}')
    out.extend(negatives)
    for entry in negatives:
        out.append({**entry,'name':entry['name']+'/owner','mode':'owner','index':2})
    for count in [0,2,99,0xffffffff]:out.append(fixture('count_refusal/'+str(count),'owner',False,id=ITEM,components=key,count=count,defaults=True,index=2))
    for index in [5,8,0xffffffff]:out.append(fixture('bounds_refusal/'+str(index),'owner',False,id=ITEM,components=key,count=1,defaults=True,index=index))
    for row in reference['rows'][:17]:out.append(fixture(row['id']+'/owner','owner',id=ITEM,components=identity(row['components'],base),count=1,defaults=True,index=2))
    tag=copy.deepcopy(reference['rows'][0]['tag']);physical=base64.b64decode(reference['rows'][0]['nbt_base64'])
    empty=copy.deepcopy(tag);empty['entries']['components']['entries'][EFFECTS]={'type':9,'items':[]}
    out.append(fixture('empty_effect_patch_becomes_default','nbt',bytes=list(wire(empty)),defaults=True,effects=[],key=''))
    malformed=[]
    def bad_tag(name,changed):malformed.append((name,wire(changed)))
    for name in ['id','count','components']:
        changed=copy.deepcopy(tag);del changed['entries'][name];bad_tag('missing_stack_'+name,changed)
    changed=copy.deepcopy(tag);changed['entries']['unknown']={'type':3,'bits':1};bad_tag('unknown_stack_field',changed)
    changed=copy.deepcopy(tag);changed['entries']['count']={'type':1,'bits':1};bad_tag('wrong_count_tag',changed)
    changed=copy.deepcopy(tag);changed['entries']['components']['entries']['minecraft:unknown']={'type':3,'bits':1};bad_tag('unknown_NBT_component',changed)
    for name,value in [('unknown_id',{'type':8,'value':'minecraft:unknown'}),('wrong_id_type',{'type':3,'bits':1})]:
        changed=copy.deepcopy(tag);changed['entries']['components']['entries'][EFFECTS]['items'][0]['entries']['id']=value;bad_tag(name,changed)
    changed=copy.deepcopy(tag);changed['entries']['components']['entries'][EFFECTS]['items'][0]['entries']['duration']={'type':8,'value':'60'};bad_tag('wrong_duration_tag',changed)
    changed=copy.deepcopy(tag);changed['entries']['components']['entries'][EFFECTS]['items'][0]['entries']['unknown']={'type':3,'bits':1};bad_tag('unknown_effect_field',changed)
    for length in [0,1,2,3,len(physical)-1]:malformed.append(('truncated_NBT/'+str(length),physical[:length]))
    malformed += [('trailing_byte',physical+b'\0'),('named_root',wire(tag,'named'))]
    # Valid small NBT must refuse when its canonical effective map would exceed
    # the shared bounded identity admission. This is the reviewed decoder bug.
    changed=copy.deepcopy(tag);changed['entries']['components']['entries'][EFFECTS]['items']=[{'type':10,'entries':{'id':{'type':8,'value':'minecraft:speed'}}} for _ in range(2600)]
    large=wire(changed);assert len(large)<65536;malformed.append(('oversized_effective_identity',large))
    for name,data in malformed:
        out.append(fixture(name,'nbt',False,bytes=list(data),defaults=True))
        out.append(fixture(name+'/owner','owner_nbt',False,bytes=list(data),defaults=True,index=2))
    for row in reference['rows'][:17]:out.append(fixture(row['id']+'/owner_nbt','owner_nbt',bytes=list(base64.b64decode(row['nbt_base64'])),defaults=True,index=2,key=identity(row['components'],base)))
    out.append(fixture('NBT_missing_defaults/owner','owner_nbt',False,bytes=list(physical),defaults=False,index=2))
    return out

def verify(case, actual):
    mode=case['mode']; accepted=actual.get('status',actual)['accepted']
    assert accepted==case['expected'],(case['name'],actual)
    if mode.startswith('owner'):
        assert actual['logical_length']==5 and len(actual['before'])==len(actual['after'])==8,case['name']
        if not accepted:assert actual['before']==actual['after'],(case['name'],actual)
        else:
            expected=copy.deepcopy(actual['before']);expected[case['index']]={'id':ITEM,'components':case.get('key',case.get('components')),'count':1}
            assert actual['after']==expected,(case['name'],actual)
    if accepted and mode=='validate':
        assert actual['effects']==case['effects'] and actual['rebuilt']['components']==case['components'],(case['name'],actual)
        assert actual['encoded']['accepted'],(case['name'],actual)
        name,tag=parse_wire(bytes(actual['encoded']['bytes']));assert name==''
        if 'java_tag' in case:assert normalized_tag(tag)==normalized_tag(case['java_tag']),case['name']
    if accepted and mode=='nbt':
        assert actual['slot']=={'id':ITEM,'components':case['key'],'count':1},(case['name'],actual)
        assert actual['profile']['accepted'] and actual['profile']['effects']==case['effects'],(case['name'],actual)

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--build',action='store_true');parser.add_argument('--native-only',action='store_true');args=parser.parse_args();BUILD.mkdir(exist_ok=True)
    sources=[ROOT/'src'/name for name in ['item_component.bend','item_component_effects.bend','u32_decimal.bend','item_component_laws.bend','item_component_proof.bend']]+[ROOT/'tests/item_component.bend',Path(__file__),ROOT/'tools/item_component_proof.mjs',REFERENCE,ROOT/'src/crafting_recipe_components.bend',ROOT/'src/json.bend']
    before=[pin(p) for p in sources];receipt={'status':'running','sources':before};write_json(EVIDENCE,receipt)
    try:
        reference=json.loads(REFERENCE.read_text());assert reference['pin']=='26.3';assert hashlib.sha256(canonical(reference['default_components'])).hexdigest()==reference['default_components_sha256']
        assert reference['default_components_sha256'] in (ROOT/'src/item_component.bend').read_text()
        receipt['ordinary']=run([BEND,ROOT/'src/item_component_proof.bend','--check-only']);assert receipt['ordinary']['exit_code']==0,receipt['ordinary']
        if not args.native_only:
            folder=BUILD/('kernel-'+str(time.time_ns()));folder.mkdir()
            receipt['export']=run([NODE,'--stack-size=4096','--experimental-transform-types',ROOT/'tools/item_component_proof.mjs',folder,'--full']);assert receipt['export']['exit_code']==0,receipt['export']
            selection=json.loads((folder/'selection.json').read_text());scope=json.loads((folder/'scope.json').read_text());assert scope['exclusions']==[]
            receipt['kernel']=run(['/usr/bin/env','LEAN_STACK_SIZE=4194304',KERNEL,folder/'selected.bendtt']);assert receipt['kernel']['exit_code']==0 and receipt['kernel']['stdout'].strip()=='ALL PROOFS CHECK',receipt['kernel']
            receipt['proof_scope']={'ordinary_laws':13,'kernel_roots':selection['roots'],'kernel_roots_count':len(selection['roots']),'historical_unsupported_full_validator_roots':selection['historical_unsupported_full_validator_roots'],'exclusions':scope['exclusions'],'artifact':pin(folder/'selected.bendtt'),'term_pins':selection['term_pins'],'unchanged_terms':selection['checked_types_and_bodies_unchanged'],'kernel_executable':pin(KERNEL)}
        binary=BUILD/'observer'
        if args.build:
            built=build_native.ensure_native(ROOT/'tests/item_component.bend',binary,bend=BEND)
            write_json(BUILD/'native-build.json',built)
            receipt['build']={k:built[k] for k in ['path','binary_sha256','cache_key','cache_hit','timings']}
            receipt['build']['full_receipt']=str(BUILD/'native-build.json')
        assert binary.is_file(),'Run --build with one coordinated CPU compiler slot'
        corpus=cases(reference);counts={};batches=[]
        for start in range(0,len(corpus),32):
            batch=corpus[start:start+32];path=BUILD/'fixtures.json';write_json(path,[{k:v for k,v in x.items() if k not in {'name','expected','effects','java_tag','key'}} for x in batch])
            result=run([binary,'--gpu','off','--threads','1','--',path]);assert result['exit_code']==0,result
            lines=result['stdout'].splitlines();assert len(lines)==len(batch),(start,len(lines),len(batch),result)
            for case,line in zip(batch,lines,strict=True):verify(case,json.loads(line));key=case['mode']+('/accepted' if case['expected'] else '/refused');counts[key]=counts.get(key,0)+1
            batches.append({'cases':len(batch),'seconds':result['seconds'],'stdout_sha256':hashlib.sha256(result['stdout'].encode()).hexdigest()})
            receipt.update(checked=start+len(batch),counts=counts);write_json(EVIDENCE,receipt)
        assert before==[pin(p) for p in sources],'Source changed during proof/replay; retain attempt and use stable closure'
        receipt.update(status='passed',confidence='high for stated typed profile and observed codec/owner contracts',native={'cases':len(corpus),'counts':counts,'batches':batches,'binary':pin(binary)},reference=pin(REFERENCE),scope='Actual 17 modified suspicious stew recipe outputs, ordered known-effect lists and full signed duration words. Foundation Inventory owner includes all eight backing entries and logical length. Actual catalog and Saved codec integration has separate evidence/item_component_inventory.json. Full session/world/transport integration and gameplay use remain outside this foundation adapter replay.',unverified=['full session/world/wire consumer integration','full13 independent kernel: json.encode_go affine descent rejection','physical-byte decoder theorem: compiler stack overflow','actual effect consumption gameplay'],reproduce='python3 tools/item_component_check.py --build --native-only (full13 proof attempt retained separately in evidence/item_component_proof_limit.json)')
        write_json(EVIDENCE,receipt);print(json.dumps({'status':'passed','cases':len(corpus),'counts':counts,'evidence':str(EVIDENCE)}))
    except BaseException as error:
        receipt.update(status='failed',error=repr(error));write_json(EVIDENCE,receipt);raise

if __name__=='__main__':main()
