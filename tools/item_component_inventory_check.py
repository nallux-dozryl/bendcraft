#!/usr/bin/env python3
"""Exercise actual catalog admission and version3 Saved codec on complete owners."""
from __future__ import annotations
import argparse, copy, hashlib, json, subprocess, time
from pathlib import Path
import build_native
import item_component_check as C
import test_nbt as N
import test_player_codec as P
import test_player_inventory as I
from reference_inventory import ROOT, write_json, fingerprint

BUILD=ROOT/'build/item_component_inventory'
EVIDENCE=ROOT/'evidence/item_component_inventory.json'
TABLE=ROOT/'generated/reference_item_metadata.tsv'
BEND=Path.home()/'.bend/bin/bend'
REFERENCE=ROOT/'reference/item_component.json'

def pin(p): return {'path':str(Path(p).resolve()),**fingerprint(Path(p))}
def run(args,timeout=180):
    start=time.monotonic();p=subprocess.run(list(map(str,args)),cwd=ROOT,capture_output=True,text=True,timeout=timeout)
    return {'command':list(map(str,args)),'exit_code':p.returncode,'seconds':round(time.monotonic()-start,6),'stdout':p.stdout,'stderr':p.stderr}

def owner(name,*,plain=False,legacy=False,**changes):
    backing=[None]*64
    if not legacy:backing[0]={'id':'minecraft:stone','components':'','count':7}
    # Hidden cells are deliberately inadmissible, opaque, and outside logical48.
    for n in range(48,64):backing[n]={'id':'hidden:'+str(n),'components':'opaque\t'+str(n),'count':0xffffffff if n%2 else 0}
    value={'name':name,'mode':'encode','catalog':'full','backing':backing,'length':48,'selected':0 if legacy else 8,
        'instabuild':not legacy,'maybuild':True,'invulnerable':not plain and not legacy,'mayfly':not plain and not legacy,'flying':not plain and not legacy,
        'walking':1036831949 if plain or legacy else 0x7fc01234,'flying_speed':1028443341 if plain or legacy else 0x80000000,'revision':0xffffffff,'opened':True,'expected':True}
    value.update(changes);return value

def expected_state(case,*,reloaded=False):
    backing=copy.deepcopy(case['backing'])
    if reloaded:backing=backing[:43]+[None]*21
    return {'backing':backing,'length':48,'selected':case['selected'],'instabuild':case['instabuild'],'maybuild':case['maybuild'],
        'status':[case['invulnerable'],case['mayfly'],case['flying'],case['walking'],case['flying_speed']],
        'opened':False if reloaded else case['opened'],'revision':0 if reloaded else case['revision'],'catalog_count':3 if case['catalog']=='missing' else 1658}

def tag_value(tag):
    kind=tag['type']
    if kind in (1,3,5):return N.Value(kind,tag['bits'])
    if kind==8:return N.Value(8,N.text(tag['value']))
    if kind==9:
        values=tag['items'];return N.Value(9,(tag.get('element_type',values[0]['type'] if values else 0),tuple(map(tag_value,values))))
    if kind==10:
        fields=tag['entries'].items() if isinstance(tag['entries'],dict) else tag['entries']
        return P.compound([(k,tag_value(v)) for k,v in fields])
    raise AssertionError(kind)

def root_fields(data):
    root=N.Reader(data,max_depth=8,max_bytes=65536,max_elements=16384).root();assert root.value.kind==10
    fields=dict(root.value.payload);assert len(fields)==len(root.value.payload)
    return root,fields

def slot_tag(slot,rows,base):
    if slot is None:return P.compound([])
    if not slot['components']:return P.compound([('id',N.Value(8,N.text(slot['id']))),('count',N.Value(3,slot['count']))])
    row=rows[slot['components']];fields=row['tag']['entries'];effects=fields['components']['entries'][C.EFFECTS]['items']
    # Java Compound is unordered. Fixture physical ordering follows the
    # existing deterministic slot schema, with typed values sourced from Java.
    values=[]
    for effect in effects:
        parts=effect['entries'];values.append(P.compound([('id',tag_value(parts['id'])),('duration',tag_value(parts.get('duration',{'type':3,'bits':160})))]))
    return P.compound([('id',tag_value(fields['id'])),('count',tag_value(fields['count'])),('components',P.compound([(C.EFFECTS,N.Value(9,(10,tuple(values))))]))])

def physical_expected(case,record,generation,rows,base):
    state={'selected':case['selected'],'slots':case['backing'][:36],'abilities':{'instabuild':case['instabuild'],'maybuild':case['maybuild']}}
    if case.get('legacy'):return I.inventory_bytes(record,state)
    if case.get('version2'):return I.inventory_bytes(record,state)
    status=dict(zip(I.STATUS_FIELDS,expected_state(case)['status'],strict=True))
    root=I.inventory_full_root(record,state,case['backing'][36:43],status,generation)
    fields=list(root.value.payload)
    fields[5]=(fields[5][0],N.Value(9,(10,tuple(slot_tag(s,rows,base) for s in case['backing'][:36]))))
    fields[6]=(fields[6][0],N.Value(9,(10,tuple(slot_tag(s,rows,base) for s in case['backing'][36:43]))))
    return N.encode_root(N.RootTag(root.name,N.Value(10,tuple(fields))))

def cases(reference):
    base=reference['default_components'];out=[]
    first=C.identity(reference['rows'][0]['components'],base)
    for row in reference['rows'][:17]:
        x=owner(row['id']);x['backing'][2]={'id':C.ITEM,'components':C.identity(row['components'],base),'count':1};out.append(x)
        x=owner(row['id']+'/equipment');x['backing'][40]={'id':C.ITEM,'components':C.identity(row['components'],base),'count':1};out.append(x)
    x=owner('default-empty-legacy',legacy=True);x['legacy']=True;out.append(x)
    x=owner('plain-version2',plain=True);x['version2']=True;out.append(x)
    out.append(owner('plain-version3'))
    for walking,flying in [(0,0xffffffff),(0x7f800000,0xff800000),(0x7fa01234,0xffc05678),(0x80000000,0)]:
        x=owner('raw-status/'+str(walking),walking=walking,flying_speed=flying);x['backing'][2]={'id':C.ITEM,'components':first,'count':1};out.append(x)
    for kind in ['full','missing','disabled','wrong_digest','wrong_limit']:
        out.append({'name':'catalog/'+kind,'mode':'metadata','catalog':kind,'id':C.ITEM,'components':first,'expected':kind=='full'})
        x=owner('save-catalog/'+kind,catalog=kind,expected=kind=='full');x['backing'][2]={'id':C.ITEM,'components':first,'count':1};out.append(x)
    profile=json.loads(first[len(C.HEADER):])
    invalid=[('opaque','opaque'),('prefix',C.HEADER+'{}'),('truncated',first[:-1]),('whitespace',C.HEADER+' '+first[len(C.HEADER):]),('wrong_limit',first.replace('\t1\t','\t64\t',1))]
    for field in base:
        bad=copy.deepcopy(profile);del bad[field];invalid.append(('missing/'+field,C.identity(bad,base)))
    bad=copy.deepcopy(profile);bad[C.EFFECTS]=[{'id':'minecraft:unknown','duration':1}];invalid.append(('unknown_effect',C.identity(bad,base)))
    bad=copy.deepcopy(profile);bad[C.EFFECTS]=[{'id':'minecraft:speed','duration':2147483648}];invalid.append(('duration_overflow',C.identity(bad,base)))
    for name,key in invalid:
        x=owner('save-refuse/'+name,expected=False);x['backing'][2]={'id':C.ITEM,'components':key,'count':1};out.append(x)
    for count in [0,2,0xffffffff]:
        x=owner('count-refuse/'+str(count),expected=False);x['backing'][2]={'id':C.ITEM,'components':first,'count':count};out.append(x)
    for index in [43,46,47]:
        x=owner('temporary-refuse/'+str(index),expected=False);x['backing'][index]={'id':'minecraft:stone','components':'','count':1};out.append(x)
    x=owner('selected-refuse',selected=9,expected=False);x['backing'][2]={'id':C.ITEM,'components':first,'count':1};out.append(x)
    return out

def replay(binary,corpus,receipt,*,batch=8):
    output=[]
    for start in range(0,len(corpus),batch):
        values=corpus[start:start+batch];path=BUILD/'fixtures.json';write_json(path,[{k:v for k,v in x.items() if k not in {'name','expected','legacy','version2'}} for x in values])
        r=run([binary,'--gpu','off','--threads','1','--',TABLE,path]);assert r['exit_code']==0,r
        lines=r['stdout'].splitlines();assert len(lines)==len(values),(start,r)
        output.extend(json.loads(line) for line in lines)
        receipt.setdefault('batches',[]).append({'cases':len(values),'seconds':r['seconds'],'stdout_sha256':hashlib.sha256(r['stdout'].encode()).hexdigest()})
    return output

def verify_encode(case,actual,rows,base):
    if case['mode']=='metadata':
        assert actual['accepted']==case['expected'],(case['name'],actual)
        if case['expected']:assert actual['slot']=={'id':C.ITEM,'components':case['components'],'count':1}
        return None
    assert actual['owner']['state']==expected_state(case),(case['name'],'complete-owner',actual['owner']['state'])
    assert actual['owner']['fresh'] is False
    assert actual['owner']['record_before']==actual['owner']['record_after'],case['name']
    assert actual['encoded']['accepted']==case['expected'],(case['name'],actual['encoded'])
    if not case['expected']:assert not actual['reload']['accepted'];return None
    restored=actual['reload'];assert restored['state']==expected_state(case,reloaded=True),(case['name'],'reload',restored)
    assert restored['record_before']==restored['record_after']==actual['owner']['record_before'];assert restored['fresh'] is False
    record=bytes(actual['owner']['record_before']['bytes']);data=bytes(actual['encoded']['bytes'])
    generation=b''
    if not case.get('legacy') and not case.get('version2'):
        _,fields=root_fields(data);assert fields[N.text('format')]==N.Value(3,3);generation=fields[N.text('generation')].payload
    assert data==physical_expected(case,record,generation,rows,base),(case['name'],'physical saved bytes')
    return data

def decode_cases(data):
    root,fields=root_fields(data);out=[]
    def add(name,root_value):out.append({'name':'decode-refuse/'+name,'mode':'decode','catalog':'full','bytes':list(N.encode_root(root_value)),'expected':False})
    for catalog in ['missing','disabled','wrong_digest','wrong_limit']:
        out.append({'name':'decode-catalog/'+catalog,'mode':'decode','catalog':catalog,'bytes':list(data),'expected':False})
    slots=list(fields[N.text('slots')].payload[1]);original=slots[2]
    def changed_slot(name,slot):
        values=list(slots);values[2]=slot;members=[(k,N.Value(9,(10,tuple(values))) if k==N.text('slots') else v) for k,v in root.value.payload]
        add(name,N.RootTag(root.name,N.Value(10,tuple(members))))
    parts=dict(original.payload);component=parts[N.text('components')];effects=dict(component.payload)[N.text(C.EFFECTS)]
    changed_slot('count2',P.compound([('id',parts[N.text('id')]),('count',N.Value(3,2)),('components',component)]))
    changed_slot('unknown_component',P.compound([('id',parts[N.text('id')]),('count',N.Value(3,1)),('components',P.compound([(C.EFFECTS,effects),('minecraft:unknown',N.Value(3,1))]))]))
    changed_slot('duplicate_component',P.compound([('id',parts[N.text('id')]),('count',N.Value(3,1)),('components',P.compound([(C.EFFECTS,effects),(C.EFFECTS,effects)]))]))
    changed_slot('removed_component',P.compound([('id',parts[N.text('id')]),('count',N.Value(3,1)),('components',P.compound([('!minecraft:food',N.Value(3,1))]))]))
    changed_slot('unknown_stack_field',N.Value(10,original.payload+((N.text('unknown'),N.Value(3,1)),)))
    changed_slot('duplicate_stack_id',N.Value(10,original.payload+((N.text('id'),parts[N.text('id')]),)))
    changed_slot('duration_wrong_tag',P.compound([('id',parts[N.text('id')]),('count',N.Value(3,1)),('components',P.compound([(C.EFFECTS,N.Value(9,(10,(P.compound([('id',N.Value(8,N.text('minecraft:speed'))),('duration',N.Value(8,N.text('20')))]),))))]))]))
    for size in [0,1,3,len(data)-1]:out.append({'name':'decode-truncated/'+str(size),'mode':'decode','catalog':'full','bytes':list(data[:size]),'expected':False})
    out.append({'name':'decode-trailing','mode':'decode','catalog':'full','bytes':list(data+b'\0'),'expected':False})
    return out

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--build',action='store_true');args=parser.parse_args();BUILD.mkdir(exist_ok=True)
    paths=[ROOT/'src'/n for n in ['item_component.bend','item_component_effects.bend','item_component_inventory_codec.bend','item_component_inventory_laws.bend','item_component_inventory_proof.bend','player_item_definitions.bend','player_inventory_codec.bend','player_inventory.bend','crafting_recipe_components.bend','json.bend','u32_decimal.bend']]+[ROOT/'tests/item_component_inventory.bend',Path(__file__),REFERENCE,TABLE]
    before=[pin(p) for p in paths];receipt={'status':'running','source_pins':before};write_json(EVIDENCE,receipt)
    try:
        assert fingerprint(TABLE)['sha256']==I.TABLE_SHA256
        receipt['ordinary']=run([BEND,ROOT/'tests/item_component_inventory.bend','--check-only'])
        message=receipt['ordinary']['stdout']+receipt['ordinary']['stderr'];assert receipt['ordinary']['exit_code']==1 and 'Error: 43 defs rely on unsafe or foreign code:' in message and 'expected :' not in message,receipt['ordinary']
        reference=json.loads(REFERENCE.read_text());base=reference['default_components'];rows={C.identity(row['components'],base):row for row in reference['rows'][:17]}
        binary=BUILD/'observer'
        if args.build:
            built=build_native.ensure_native(ROOT/'tests/item_component_inventory.bend',binary,bend=BEND);write_json(BUILD/'native-build.json',built)
            receipt['build']={k:built[k] for k in ['path','binary_sha256','cache_key','cache_hit','timings']}
        assert binary.is_file(),'Run with --build using a coordinated compiler slot'
        corpus=cases(reference);actual=replay(binary,corpus,receipt);saved={}
        for case,value in zip(corpus,actual,strict=True):
            data=verify_encode(case,value,rows,base)
            if data is not None:saved[case['name']]=data
        bad=decode_cases(saved[reference['rows'][0]['id']]);decoded=replay(binary,bad,receipt)
        for case,value in zip(bad,decoded,strict=True):assert value['accepted'] is False,(case['name'],value)
        # Separate process decodes persisted bytes; this is a cold codec reload,
        # not a filesystem atomic publication or complete live session claim.
        cold=[]
        for row in reference['rows'][:17]:
            path=BUILD/(row['id'].replace('/','_')+'.nbt');path.write_bytes(saved[row['id']])
            case={'name':'cold/'+row['id'],'mode':'decode','catalog':'full','bytes':list(path.read_bytes()),'expected':True}
            result=replay(binary,[case],receipt)[0];original=next(c for c in corpus if c['name']==row['id'])
            assert result['state']==expected_state(original,reloaded=True),row['id'];cold.append({'case':row['id'],'file':pin(path)})
        assert before==[pin(p) for p in paths],'Source changed during actual D/IC replay'
        receipt.update(status='passed',cases=len(corpus)+len(bad)+len(cold),catalog_cases=5,save_cases=len(corpus)-5,whole_load_refusals=len(bad),cold_codec_reloads=cold,
            binary=pin(binary),reference=pin(REFERENCE),complete_owner_fields=['all64 backing cells including16 inadmissible hidden cells','logical48','selected','abilities','all five raw status fields','menu opened/revision','catalog count','complete record bytes','fresh flag'],
            physical_compare='All17 modified output patches are compared with the primary Java typed NBT inside independently assembled full version3 bytes. Plain v3, v2, and bare legacy bytes compare with existing independent constructors.',
            limitations=['43 pre-existing storage foreign/unsafe declarations remain outside proof claims','No world/session filesystem atomic publication exercised','I structural/menu/wire gates and actual gameplay component use remain separately owned'],reproduce='python3 tools/item_component_inventory_check.py --build')
        write_json(EVIDENCE,receipt);print(json.dumps({'status':'passed','cases':receipt['cases'],'evidence':str(EVIDENCE)}))
    except BaseException as error:
        receipt.update(status='failed',error=repr(error));write_json(EVIDENCE,receipt);raise

if __name__=='__main__':main()
