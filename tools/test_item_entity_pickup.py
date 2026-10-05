#!/usr/bin/env python3
"""Check production affine pickup against retained independent Java receivers."""
from __future__ import annotations
import copy,hashlib,json,shutil,uuid
from pathlib import Path
import test_campfire_authority as T
ROOT=T.ROOT;WORK=ROOT/'build/item-entity-pickup-native';T.WORK=WORK

def words(value):
    if value is None:return None
    n=uuid.UUID(value).int
    return [[(n>>96)&0xffffffff,(n>>64)&0xffffffff],[(n>>32)&0xffffffff,n&0xffffffff]]
def native_case(value):
    r=copy.deepcopy(value);r['delay']&=0xffffffff;r['target']=words(r['target']);r['thrower']=words(r['thrower'])
    r.update(admitted=True,dimension='minecraft:overworld',server_player=False,budget=100,resolution='absent',resolved=None,scene=False,scan_budget=100)
    return r

def guard_cases(reference):
    ordinary=native_case(reference[0]);thrower=words('99992222-3333-4444-5555-666677778888')
    cases=[]
    for name,changes in [('not-admitted',{'admitted':False}),('wrong-dimension',{'dimension':'minecraft:the_nether'}),('exhausted-budget',{'budget':0}),('invalid-selected',{'selected':9}),('unknown-thrower',{'thrower':thrower,'resolution':'unknown'}),('mismatched-thrower',{'thrower':thrower,'resolution':'server','resolved':words('11112222-3333-4444-5555-666677778888')})]:
        row=copy.deepcopy(ordinary);row.update(changes,id='guard-'+name);cases.append(row)
    for mode in ['server','other']:
        row=copy.deepcopy(ordinary);row.update(id='guard-resolved-'+mode,thrower=thrower,resolved=thrower,resolution=mode,server_player=True);cases.append(row)
    for label,budget in [('success',100),('scan-refusal',1)]:
        row=copy.deepcopy(ordinary);row.update(id='guard-scene-'+label,scene=True,scan_budget=budget);cases.append(row)
    return cases

def decoded_slot(value,defaults):return T.decoded_slot(value,defaults)
def actual_common(value,removed):
    # All nonpickup Common fields are independently fixed by the actual native
    # test owner; its production laws quantify over the whole arbitrary record.
    assert value['dimension']=='minecraft:overworld' and value['id']==71
    assert value['uuid_most']==[1,2] and value['uuid_least']==[3,4]
    assert value['random']=={'kind':'legacy','seed':[11,12]}
    assert value['tick_count']==33 and value['first_tick'] is False and value['removed']==removed
    assert value['accessible'] is True and value['section_order']==19

def compare(cases,observations,defaults):
    assert len(cases)==len(observations)
    for got,want in zip(cases,observations):
        assert got['id']==want['id']
        source=next(c for c in REFERENCE['inputs'] if c['id']==got['id'])
        if want['id']=='damaged-whole-copy-oversize-boundary':
            assert got['error']=='damaged whole-copy exceeds current authoritative inventory stack domain'
            assert [decoded_slot(s,defaults) for s in got['slots'][:43]]==want['before']
            assert decoded_slot(got['entity_item'],defaults)=={'id':source['item']['id'],'count':source['item']['count'],'components':want['entity_item']['components']}
            assert got['removed'] is False
        else:
            assert 'error' not in got,(got,want)
            assert [decoded_slot(s,defaults) for s in got['slots'][:43]]==want['slots'],got['id']
            assert decoded_slot(got['entity_item'],defaults)==want['entity_item'],got['id']
            assert got['removed']==want['removed'],got['id']
            pops=[0]*43
            packet=[]
            for event in got['publications']:
                if event['kind']=='pop':pops[event['slot']]=event['duration']
                elif event['kind'] in ['take','stat']:packet.append(event)
                else:assert event['kind']=='discard'
            assert pops==want['pop_times'],got['id']
            expected=[e for e in want['events'] if e['kind'] in ['take','stat']]
            assert packet==expected,(got['id'],packet,expected)
            assert got['returned']==bool(want['events']),got['id']
            assert want['times_changed_delta']==0
        assert got['menu_revision']==17 and got['menu_result_present'] is True
        assert got['slots'][43:]==[None]*5
        actual_common(got['common'],got['removed'])

def main():
    global REFERENCE
    WORK.mkdir(parents=True,exist_ok=True)
    REFERENCE=json.loads((ROOT/'reference/item_entity_pickup.json').read_text());assert REFERENCE['pin']=='26.3'
    # Reuse unchanged initialized data, not unchanged cooking receiver corpus.
    catalog=copy.deepcopy(json.loads((ROOT/'reference/campfire_authority.json').read_text())['inputs']['catalog']);catalog['recipes']=[]
    defaults={r['id']:r['components'] for r in catalog['items']}
    cases=[native_case(c) for c in REFERENCE['inputs']];guards=guard_cases(REFERENCE['inputs'])
    payload={'catalog':catalog,'item_table':(ROOT/'generated/reference_item_metadata.tsv').read_text(),'cases':cases+guards}
    (WORK/'input.json').write_text(json.dumps(payload,separators=(',',':'))+'\n')
    checks=[]
    checks.append(T.run('emit',[T.NODE,'--experimental-transform-types','--stack-size=4096','--max-old-space-size=1536','tools/item_entity_pickup_emit.mjs','tests/item_entity_pickup.bend',WORK/'receiver.c'],timeout=60))
    checks.append(T.run('clang',[shutil.which('clang'),'-std=c11','-O2',WORK/'receiver.c','-lpthread','-lm','-o',WORK/'receiver'],timeout=120))
    outputs=[]
    for threads in [1,4]:
        checks.append(T.run('native-'+str(threads),['/usr/bin/time','-l',WORK/'receiver','--gpu','off','--threads',str(threads),WORK/'input.json'],timeout=60,max_rss=1024**3))
        got=json.loads((WORK/('native-'+str(threads)+'.stdout')).read_text());outputs.append(got)
        compare(got[:len(cases)],REFERENCE['observations']['cases'],defaults)
        for g,src in zip(got[len(cases):],guards):
            assert g['id']==src['id']
            if 'scene-' in g['id']:
                view=g['scene'];assert view['level_after']=={'kind':'legacy','seed':[50,60]} and view['unique_after']==[70,80] and view['cursor_after']==81
                records=view['records'];assert [r['common']['id'] for r in records]==[90,71,92]
                assert records[0]['value']==7 and records[2]['value']==7
                assert not records[0]['common']['removed'] and not records[2]['common']['removed']
                assert records[1]['common']['section_order']==19
                if src['scan_budget']==1:
                    assert g['error']=='operation budget' and g['slots']==[None]*48 and not g['removed']
                else:
                    assert 'error' not in g and g['returned'] and g['removed'] and g['slots'][0]==g['entity_item']
                continue
            if 'resolved-' in g['id']:
                assert 'error' not in g and g['removed'] and g['returned']
                kinds=[e['kind'] for e in g['publications']]
                expected=['pop','take','broadcast','discard','stat']+(['thrown_by_entity'] if src['resolution']=='server' else [])+['thrown_by_player']
                assert kinds==expected,(g,expected)
                for e in g['publications']:
                    if e['kind'].startswith('thrown_'):assert e['item']==g['entity_item']
            else:
                assert 'error' in g and not g['removed']
                assert g['slots']==[None]*48 and g['entity_item']['count']==1
                assert g['menu_revision']==17 and g['menu_result_present']
                actual_common(g['common'],False)
        assert len(got)==len(cases)+len(guards)
    assert outputs[0]==outputs[1]
    assert [e['slot'] for e in outputs[0][5]['publications'] if e['kind']=='pop']==[4,40,0,8]
    transitive=json.loads((WORK/'receiver.c.sources.json').read_text())
    # The compiler pins the complete original checked book. Concurrent unrelated
    # source edits after emission do not change the identity of this artifact.
    evidence={'status':'passed','pin':'26.3','command':'python3 tools/test_item_entity_pickup.py','checks':checks,'source':transitive,'actual_java_cases':len(cases),'exact_java_state_cases':len(cases)-1,'explicit_authoritative_domain_refusal':'Actual Java damaged count3 is copied whole; current affine inventory invariant admits count<=stack_limit, so this case is refused atomically with both owners intact. Ordinary valid damaged count1 and undamaged oversized resource splitting compare exactly.','native_guards':len(guards),'initialized_items':len(defaults),'threads':[1,4],'native_c_sha256':T.digest(WORK/'receiver.c'),'reference_sha256':T.digest(ROOT/'reference/item_entity_pickup.json'),'boundary':'Actual production E.Entity/P.State owners, original inventory Array writes and full initialized key admission. Java actual playerTouch/Inventory.add; overridden observation callbacks capture take/stat/onItemPickup call boundary. Installed ServerPlayer networking/menu/criteria separately specified by bytecode and typed publications, not live network/stat authority here. Collision/world scheduling/Session persistence remain actor consumer seams.'}
    (ROOT/'evidence/item-entity-pickup-native.json').write_text(json.dumps(evidence,indent=2)+'\n');print(json.dumps({k:evidence[k] for k in ['status','actual_java_cases','exact_java_state_cases','native_guards','initialized_items']}))
if __name__=='__main__':main()
