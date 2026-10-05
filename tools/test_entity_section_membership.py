#!/usr/bin/env python3
"""Compare actual Bend membership authority to pinned Java manager observations.

Python only recreates controlled EntityAccess inputs, translates value formats,
and compares independently observed output. It does not implement transitions.
"""
from __future__ import annotations
import copy,json,shutil,struct
from pathlib import Path
import test_campfire_authority as T

ROOT=T.ROOT
WORK=ROOT/'build/entity-section-membership-native'
T.WORK=WORK
DIMENSION='minecraft:overworld'
CALLBACKS={'created','tracking_start','tracking_end','ticking_start','ticking_end','section_change','destroyed'}
STRUCTURAL={'section_created','section_deleted','inserted','detached'}
QUERY=[-40,-40,-40,80,80,80]

def words(value):return list(struct.unpack('>II',struct.pack('>d',float(value))))
def vector(value):return [words(x) for x in value]
def bbox(point):
    x,y,z=point
    return [x-.125,y,z-.125,x+.125,y+.25,z+.125]
def chunk(x=0,z=0,status='TICKING',loaded=True,dimension=DIMENSION):
    return dict(dimension=dimension,x=x&0xffffffff,z=z&0xffffffff,status=status,loaded=loaded)
def operation(mode,id=1,point=(1,1,1),uuid=None,created=True,destroy=False,actual=None):
    return dict(mode=mode,id=id,point=vector(point),box=vector(bbox(point)),uuid_most=[0,0],
                uuid_least=[0,id if uuid is None else uuid],created=created,destroy=destroy,
                chunk=actual or chunk())
def step(action,operations=(),query_missing=False,query=QUERY):
    return dict(action=action,operations=list(operations),query_missing=query_missing,query=vector(query))

def recreate(case):
    """Inputs copied from the Java probe's controlled receiver scenarios."""
    c=case
    category=c['category']
    if category=='registration':
        chunks=[chunk(status=c['visibility'])]
        steps=[step('register',[operation('add')]),
               step('register_duplicate_uuid',[operation('add',2,(17,1,1),uuid=1)])]
    elif category=='move':
        chunks=[chunk(status=c['source_visibility']),chunk(1,status=c['destination_visibility'])]
        initial=[operation('add')]
        if c['occupied_sections']:
            initial += [operation('add',2,(2,1,1)),operation('add',3,(17,1,1)),operation('add',4,(18,1,1))]
        steps=[step('registered',initial),step('move',[operation('move',point=c['steps'][1]['to'])]),
               step('move_back',[operation('move',point=c['steps'][2]['to'])])]
    elif category=='same_packed_key':
        chunks=[chunk()]
        steps=[step('registered',[operation('add'),operation('add',2,(2,1,1))]),
               step('move',[operation('move',point=c['steps'][1]['to'])])]
    elif category=='chunk_visibility':
        # Java fixture also contains always-ticking entity 5. This is explicitly
        # a normal-member projection of that observation; entity 5 is omitted.
        chunks=[chunk(status=c['source_visibility'])]
        initial=[operation('add',i,p) for i,p in enumerate([(1,-15,1),(2,1,1),(3,1,1),(4,17,1)],1)]
        steps=[step('registered',initial),step('change_chunk_visibility',[
            operation('visibility',actual=chunk(status=c['destination_visibility']))])]
    elif category=='removal':
        chunks=[chunk(status=c['visibility']),chunk(1,status='HIDDEN')]
        steps=[step('registered',[operation('add')]),step('remove',[operation('remove',destroy=c['should_destroy'])]),
               # NULL Java callback is a no-op. Production has no registered
               # callback after removal; missing-registration refusal is probed
               # separately instead of inventing a callback invocation here.
               step('move_after_removed'),step('reregister_uuid',[operation('add',2,(17,1,1),uuid=1)])]
    elif category=='query_order':
        positions=[(1,0,0),(0,-1,0),(0,0,-1),(-1,0,0),(0,0,0),(0,1,0),(0,0,1),
                   (0,-2,-1),(0,1,-1),(-1,-1,-1),(1,-1,-1)]
        chunks=[chunk(x,z,'TRACKED') for x,z in dict.fromkeys((x,z) for x,y,z in positions)]
        initial=[operation('add',i,tuple(a*16+1 for a in p)) for i,p in enumerate(positions,1)]
        initial.append(operation('add',12,(2,1,1)))
        steps=[step('registered',initial),step('move_to_existing_section',[operation('move',point=(3,1,1))]),
               step('query_abort_after_three')]
    elif category=='registration_origin':
        chunks=[chunk()]
        steps=[step('register',[operation('add',created=c['id']=='worldgen-registration')])]
    else:raise AssertionError(category)
    return dict(id=c['id'],chunks=chunks,steps=steps)

def guard_cases():
    initial=step('registered',[operation('add')])
    move=step('refused',[operation('move',point=(19,1,1))])
    cases=[]
    for name,facts in [('missing',[]),('unloaded',[chunk(1,loaded=False)]),
                       ('duplicate',[chunk(1),chunk(1)]),('wrong-dimension',[chunk(1,dimension='minecraft:the_nether')])]:
        cases.append(dict(id='guard-destination-'+name,chunks=[chunk()]+facts,steps=[copy.deepcopy(initial),copy.deepcopy(move)]))
    cases.append(dict(id='guard-missing-registration',chunks=[chunk(),chunk(1)],steps=[copy.deepcopy(initial),
        step('registration-cleared',[operation('remove')]),step('refused',[operation('move',point=(19,1,1))])]))
    cases.append(dict(id='guard-removed-common',chunks=[chunk(),chunk(1)],steps=[copy.deepcopy(initial),step('refused',[operation('removed_move',point=(19,1,1))])]))
    cases.append(dict(id='guard-query-missing-record',chunks=[chunk()],steps=[copy.deepcopy(initial),step('query-refused',query_missing=True)]))
    for name,facts in [('missing',[]),('unloaded',[chunk(loaded=False)]),('duplicate',[chunk(),chunk()])]:
        cases.append(dict(id='guard-add-'+name,chunks=facts,steps=[step('refused',[operation('add')])]))
    return cases

def key_words(raw):
    """Representation conversion only: masked coordinate fields to Java Long."""
    x,y,z=raw
    n=(x<<42)|(z<<20)|y
    return [n>>32,n&0xffffffff]
def signed_key(raw):
    hi,lo=raw
    n=(hi<<32)|lo
    return n-(1<<64) if n>>63 else n
def normalized_sections(provider):
    return sorted([dict(key=key_words(s['key']),status=s['status'],members=s['members'])
                   for s in provider['sections']],key=lambda s:signed_key(s['key']))
def expected_projection(case,observed):
    result=copy.deepcopy(observed)
    if case['category']=='chunk_visibility':
        for s in result['state']['sections']:s['members']=[i for i in s['members'] if i!=5]
        for name in ['query_ids','global_ids','known_ids']:
            result['state'][name]=[i for i in result['state'][name] if i!=5]
        result['state']['callback_keys']=[r for r in result['state']['callback_keys'] if r['id']!=5]
        result['events']=[e for e in result['events'] if e['id']!=5]
    return result
def assert_identity(state):
    assert state['level']==dict(kind='legacy',seed=[11,22]) and state['unique']==[33,44] and state['cursor']==91,state
    for record in state['records']:
        assert record['kind']=='orb' and (record['value'],record['age'],record['health'],record['count'])==(1,7,5,2),record
        c=record['common']
        assert c['random']==dict(kind='legacy',seed=[77,88]) and c['uuid_most']==[0,0],c
        assert (c['tick_count'],c['first_tick'],c['removed'])==(23,False,False),c
        assert c['dimension'] in [DIMENSION,'minecraft:the_nether'] and c['velocity']==vector((0,0,0)) and c['position_o']==vector((0,0,0)),c
        assert (c['yaw'],c['pitch'],c['yaw_o'],c['pitch_o'],c['air'],c['fire'],c['portal_cooldown'])==(0,0,0,0,300,0,0),c
        assert not c['on_ground'] and not c['invulnerable'] and not c['needs_sync'],c
        assert c['position_old']==vector((0,0,0)) and c['head']==0 and c['body']==0 and c['fall_distance']==words(0),c

def compare_case(actual,reference,inputs):
    assert actual['id']==reference['id'] and len(actual['steps'])==len(reference['steps']),actual
    previous=None
    scheduled=[]
    positions={};boxes={}
    for native,java,provided in zip(actual['steps'],reference['steps'],inputs['steps']):
        expected=expected_projection(reference,java)
        state=native['state'];provider=state['provider']
        assert native['action']==expected['action']
        accepted=expected.get('accepted',True)
        assert (native['error'] is None)==accepted,dict(case=reference['id'],action=native['action'],error=native['error'],accepted=accepted)
        for op in provided['operations']:
            if op['mode']=='add' or (op['mode']=='move' and accepted):
                positions[op['id']]=op['point'];boxes[op['id']]=op['box']
        assert all(e['event'] in CALLBACKS|STRUCTURAL for e in native['events'])
        callbacks=[(e['event'],e['id']) for e in native['events'] if e['event'] in CALLBACKS]
        wanted=[(e['event'],e['id']) for e in expected['events'] if e['event'] in CALLBACKS]
        assert callbacks==wanted,dict(case=reference['id'],action=native['action'],actual=callbacks,expected=wanted)
        for name,id in wanted:
            if name=='ticking_start':
                assert id not in scheduled
                scheduled.append(id)
            elif name=='ticking_end':scheduled.remove(id)
        assert state['scheduled_ids']==scheduled,dict(case=reference['id'],action=native['action'],actual=state['scheduled_ids'],expected_from_java_callback_consumers=scheduled)
        want_sections=[{k:s[k] for k in ['key','status','members']} for s in expected['state']['sections']]
        assert normalized_sections(provider)==want_sections,dict(case=reference['id'],action=native['action'],actual=normalized_sections(provider),expected=want_sections)
        assert state['query_ids']==expected['state']['query_ids'],dict(case=reference['id'],action=native['action'],actual=state['query_ids'],expected=expected['state']['query_ids'])
        if 'abort_query_ids' in expected:
            # The current production query materializes a complete immutable
            # traversal; consumer truncation verifies ordering only.
            assert state['query_ids'][:3]==expected['abort_query_ids']
        registrations=sorted([(m['id'],key_words(m['key'])) for m in provider['members']])
        want_registrations=sorted([(m['id'],m['key']) for m in expected['state']['callback_keys'] if m['key'] is not None])
        assert registrations==want_registrations,(reference['id'],native['action'],registrations,want_registrations)
        current={r['common']['id']:r['common'] for r in state['records']}
        assert {id:c['position'] for id,c in current.items()}==positions
        accessible=sorted(m['id'] for m in provider['members'] if current[m['id']]['accessible'])
        assert accessible==sorted(expected['state']['global_ids'])
        assert state['global_ids']==expected['state']['global_ids'],dict(case=reference['id'],action=native['action'],actual=state['global_ids'],expected=expected['state']['global_ids'])
        assert_identity(state)
        for member in provider['members']:
            c=current[member['id']]
            assert member['order']==c['section_order']<state['next_order']
            assert member['uuid']==[c['uuid_most'],c['uuid_least']]
            assert member['box']==boxes[member['id']]
        if previous is not None:
            # Rejected UUID and same-key movements preserve registration order
            # and the complete provider; same-key movement only refreshes box.
            if not accepted:
                assert provider==previous['provider'] and state['next_order']==previous['next_order']
            if reference['category']=='same_packed_key':
                assert state['next_order']==previous['next_order'] and not native['events']
                assert sorted((m['id'],m['order']) for m in provider['members'])==sorted((m['id'],m['order']) for m in previous['provider']['members'])
            if reference['category']=='chunk_visibility':
                assert state['next_order']==previous['next_order']
                assert sorted((m['id'],m['order']) for m in provider['members'])==sorted((m['id'],m['order']) for m in previous['provider']['members'])
        previous=state

def compare_guards(actual):
    for case in actual:
        assert case['id'].startswith('guard-')
        for s in case['steps']:assert_identity(s['state'])
        final=case['steps'][-1]
        if case['id']=='guard-query-missing-record':
            assert isinstance(final['state']['query_ids'],dict) and 'error' in final['state']['query_ids']
            before=copy.deepcopy(case['steps'][0]['state']);after=copy.deepcopy(final['state'])
            before.pop('query_ids');after.pop('query_ids');assert before==after
        else:
            assert final['error'] is not None and final['events']==[],case
            if len(case['steps'])>=2:assert final['state']==case['steps'][-2]['state'],case
            else:
                assert final['state']['provider']['members']==[] and final['state']['provider']['sections']==[]
                assert final['state']['next_order']==0
def preservation_case():
    return dict(id='preservation-other-dimension',chunks=[chunk(),chunk(1)],steps=[
        step('registered',[operation('shadow',1,(101,103,107),uuid=999,actual=chunk(dimension='minecraft:the_nether')),operation('add')]),
        step('moved',[operation('move',point=(19,1,1))])])
def compare_preservation(actual):
    assert actual['id']=='preservation-other-dimension'
    a,b=actual['steps']
    assert a['error'] is None and b['error'] is None
    for s in actual['steps']:assert_identity(s['state'])
    def shadow(s):return next(r for r in s['state']['records'] if r['common']['dimension']=='minecraft:the_nether')
    assert shadow(a)==shadow(b)
    assert shadow(b)['common']['position']==vector((101,103,107)) and shadow(b)['common']['uuid_least']==[0,999]
    own=next(r for r in b['state']['records'] if r['common']['dimension']==DIMENSION)
    assert own['common']['position']==vector((19,1,1)) and b['state']['next_order']==2

def compare_core_captures(actual):
    assert [a['id'] for a in actual]==['loaded-ticking','loaded-hidden','missing-visibility','missing-destination','wrong-dimension']
    for row in actual:
        assert {k:v for k,v in row.items() if k not in ['id','capture']}==dict(retained_block=2,tick=0,day_time=0,paused=True,daylight=True,revision=0,pending=0),row
    for row,status in zip(actual[:2],['TICKING','HIDDEN']):
        assert row['capture']==dict(dimension=DIMENSION,x=0,z=0,loaded=True,status=status),row
    assert actual[2]['capture']==dict(error='actual entity chunk visibility observation is missing')
    for row in actual[3:]:assert row['capture']==dict(error='actual entity destination Core section is unavailable'),row

def main():
    WORK.mkdir(parents=True,exist_ok=True)
    ref=json.loads((ROOT/'reference/entity_section_membership.json').read_text());assert ref['pin']=='26.3'
    selected=[c for c in ref['cases'] if not c.get('always_ticking',False)]
    assert len(selected)==44 and sum(len(c['steps']) for c in selected)==127
    inputs=[recreate(c) for c in selected]
    guards=guard_cases();(WORK/'input.json').write_text(json.dumps(inputs+guards+[preservation_case()],separators=(',',':'))+'\n')
    checks=[]
    try:
        checks.append(T.run('emit',[T.NODE,'--experimental-transform-types','--expose-gc','--stack-size=4096',
            '--max-old-space-size=1536','tools/entity_section_membership_emit.mjs','tests/entity_section_membership.bend',WORK/'receiver.c'],timeout=90))
        checks.append(T.run('clang',[shutil.which('clang'),'-std=c11','-O0','-fomit-frame-pointer',WORK/'receiver.c','-lpthread','-lm','-o',WORK/'receiver'],timeout=120))
        checks.append(T.run('native',['/usr/bin/time','-l',WORK/'receiver','--gpu','off','--threads','1',WORK/'input.json'],timeout=60,max_rss=1024**3))
        output=json.loads((WORK/'native.stdout').read_text())
        actual=output['cases'];assert len(actual)==len(inputs)+len(guards)+1
        for a,b,c in zip(actual,selected,inputs):compare_case(a,b,c)
        compare_guards(actual[len(inputs):-1])
        compare_preservation(actual[-1])
        compare_core_captures(output['core_captures'])
        evidence=dict(status='passed',command='python3 tools/test_entity_section_membership.py',pin='26.3',checks=checks,
            reference_sha256=T.digest(ROOT/'reference/entity_section_membership.json'),source=json.loads((WORK/'receiver.c.sources.json').read_text()),
            native_comparison_test_sha256=T.digest(Path(__file__)),native_emitter_sha256=T.digest(ROOT/'tools/entity_section_membership_emit.mjs'),
            native_fixture_input_sha256=T.digest(WORK/'input.json'),native_output_sha256=T.digest(WORK/'native.stdout'),
            actual_java_cases=44,actual_java_steps=127,normal_java_cases=35,normal_member_projections_of_mixed_java_cases=9,
            native_refusal_cases=len(guards),actual_core_capture_cases=5,unrelated_dimension_preservation_cases=1,callback_names_compared=sorted(CALLBACKS),
            compared=['ordered LevelCallback lifecycle names and IDs','all final section keys/status/ordered member IDs',
                'exact AABB query order','callback registration keys','exact tracked lookup insertion order','scheduler insertion order independently folded from Java ticking callbacks',
                'UUID duplicate refusal and UUID reuse after removal','legacy/worldgen created callback distinction',
                'same packed-key preservation plus refreshed actual AABB','complete unrelated entity/common/RNG fields',
                'actual Core loaded section capture, missing visibility/section/dimension refusal and retained block/clock',
                'unavailable/unloaded/duplicate/wrong-dimension destination refusal retains owner and provider'],
            exclusions=['always-ticking entity semantics (items/orbs use ordinary membership)',
                'partial callback snapshots and callback installation/clearing event hooks',
                'abortable streaming query (consumer take-three checks traversal order only)',
                'removed NULL callback move is represented by no callback invocation',
                'removal save behavior, actual persistence/world streaming/physics/network/rendering'],
            adapter_assumptions=['Controlled Java fixture observes chunk visibility; loaded=true is the native adapter fact for admitted destinations.'],
            build_boundary='Complete original ordinary source checking and unchanged actual production receivers emitted by verified retained-closure producer; focused -O0 -fomit-frame-pointer CPU correctness binary. No broad actor compilation, compiler modification, or proof claim.')
        (ROOT/'evidence/entity-section-membership-native.json').write_text(json.dumps(evidence,indent=2)+'\n')
        print(json.dumps({k:evidence[k] for k in ['status','actual_java_cases','actual_java_steps','native_refusal_cases']}))
    except BaseException as error:
        (WORK/'failure.json').write_text(json.dumps(dict(error=repr(error),checks=checks),indent=2)+'\n');raise

if __name__=='__main__':main()
