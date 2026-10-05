#!/usr/bin/env python3
"""Targeted native recovery joins; no unchanged manager corpus replay."""
from __future__ import annotations
import copy,json,shutil,struct,sys
from pathlib import Path
import test_campfire_authority as T
import test_entity_membership_codec as Wire
import test_entity_section_membership as Inputs

ROOT=T.ROOT;WORK=ROOT/'build/entity-section-membership-recovery-native';T.WORK=WORK
DIM=Inputs.DIMENSION;N=Wire.N

def record(id,position=(1,1,1),order=0,accessible=True,dimension=DIM,uuid=None,removed=False,kind='orb'):
    return dict(id=id,dimension=dimension,position=Inputs.vector(position),uuid_most=[0,0],uuid_least=[0,id if uuid is None else uuid],order=order,accessible=accessible,removed=removed,kind=kind)
def member(row):
    p=row['position'];position=[struct.unpack('>d',struct.pack('>II',*v))[0] for v in p]
    x,y,z=position
    width,height=(.25,.25) if row['kind']=='item' else (.5,.5)
    return dict(dimension=row['dimension'],id=row['id'],key=[int(x//16)&4194303,int(y//16)&1048575,int(z//16)&4194303],order=row['order'],box=Inputs.vector([x-width/2,y,z-width/2,x+width/2,y+height,z+width/2]),uuid=[row['uuid_most'],row['uuid_least']])
def manager(records,visibility='TICKING'):
    members=[member(r) for r in reversed(records)]
    sections=[]
    for m in reversed(members):
        section=next((s for s in sections if s['dimension']==m['dimension'] and s['key']==m['key']),None)
        if section is None:
            section=dict(dimension=m['dimension'],key=m['key'],visibility=visibility,ids=[]);sections.append(section)
        section['ids'].append(m['id'])
    chunks=[]
    for s in sections:
        x,y,z=s['key']
        if not any(c['dimension']==s['dimension'] and c['x']==x and c['z']==z for c in chunks):
            chunks.append(Inputs.chunk(x,z,visibility,dimension=s['dimension']))
    regs=[dict(dimension=r['dimension'],id=r['id']) for r in records]
    return dict(members=members,sections=sections,chunks=chunks,tracked=regs if visibility!='HIDDEN' else [],ticked=regs if visibility=='TICKING' else [])
def encode(view):
    array=Wire.array;integer=Wire.integer;compound=Wire.compound;dimension=Wire.dimension
    members=[compound(dimension=dimension(m['dimension']),id=integer(m['id']),key=array(*m['key']),order=Wire.long(m['order']),box=array(*(word for v in m['box'] for word in v)),uuid=array(*(word for v in m['uuid'] for word in v))) for m in view['members']]
    visibility={'HIDDEN':0,'TRACKED':1,'TICKING':2}
    sections=[Wire.section(s['dimension'],s['key'],visibility[s['visibility']],*s['ids']) for s in view['sections']]
    chunks=[Wire.chunk(c['dimension'],c['x'],c['z'],int(c['loaded']),visibility[c['status']]) for c in view['chunks']]
    regs=lambda k:[Wire.registration(r['dimension'],r['id']) for r in view[k]]
    return list(N.encode_root(Wire.root(members=members,sections=sections,chunks=chunks,tracked=regs('tracked'),ticked=regs('ticked'))))
def observations(view,records,visibility=None):
    chunks=copy.deepcopy(view['chunks'])
    if visibility is not None:
        for c in chunks:c['status']=visibility
    return dict(chunks=chunks)
def fixture(id,records=None,cursor=2,saved=None,observed=None,runtimes=None,mode='restore',publish=True):
    records=[record(1),record(2,(2,1,1),1)] if records is None else records
    saved=manager(records) if saved is None else saved
    return dict(id=id,mode=mode,publish=publish,cursor=cursor,records=copy.deepcopy(records),runtimes=list(runtimes if runtimes is not None else [r['id'] for r in records]),saved=encode(saved),prior=encode(manager([record(99,(33,1,1),80)])),observations=copy.deepcopy(observed if observed is not None else observations(saved,records)),pre_constructor_cursor=0,fresh_id=0,constructor_delta=0,cursor_max=False,constructor_exhausted=False,constructor_prefix=[],fresh_record=record(3,order=2,kind="item"),codec=True,image_available=True,observations_available=True)
def cases(reference):
    output=[fixture('unchanged')]
    base=output[0]
    for name,mutate in [
        ('record-id',lambda c:c['records'][0].update(id=17)),
        ('record-uuid',lambda c:c['records'][0].update(uuid_least=[0,17])),
        ('record-order',lambda c:c['records'][0].update(order=17)),
        ('record-accessibility',lambda c:c['records'][0].update(accessible=False)),
        ('record-removed',lambda c:c['records'][0].update(removed=True)),
        ('cursor-not-after-orders',lambda c:c.update(cursor=1)),
        ('missing-runtime',lambda c:c.update(runtimes=[2])),
        ('duplicate-runtime',lambda c:c.update(runtimes=[1,1,2])),
        ('orphan-runtime',lambda c:c.update(runtimes=[1,2,17])),
        ('missing-image',lambda c:c.update(image_available=False)),
        ('missing-observations',lambda c:c.update(observations_available=False)),
        ('missing-chunk',lambda c:c['observations'].update(chunks=[])),
        ('unloaded-chunk',lambda c:c['observations']['chunks'][0].update(loaded=False)),
        ('duplicate-chunk',lambda c:c['observations']['chunks'].append(copy.deepcopy(c['observations']['chunks'][0]))),
        ('wrong-dimension-chunk',lambda c:c['observations']['chunks'][0].update(dimension='minecraft:the_nether')),
    ]:
        c=copy.deepcopy(base);c['id']='refused-'+name;mutate(c);output.append(c)
    saved=manager(base['records']);saved['members'][1]['box'][0][1]=9
    output.append(fixture('refused-saved-box',saved=saved))
    c=copy.deepcopy(base);c.update(id='refused-publication',publish=False);output.append(c)
    rows=[record(1),record(1,(2,1,1),1,dimension='minecraft:the_nether',uuid=17)]
    output.append(fixture('refused-global-duplicate-id',rows,saved=manager(rows),runtimes=[1]))
    c=copy.deepcopy(base);c.update(id='format5-component-restore',codec=True);output.append(c)
    c=copy.deepcopy(base);c.update(id='format5-structural-restore-missing-loader',codec=True,observations_available=False);output.append(c)
    rows=[record(1,kind='item'),record(2,(2,1,1),1)]
    output.append(fixture('item-and-orb-body-join',rows))
    for java in reference['cases']:
        if java['category']!='chunk_visibility':continue
        visibility=java['source_visibility'];accessible=visibility!='HIDDEN'
        records=[record(i,p,i-1,accessible) for i,p in enumerate([(1,-15,1),(2,1,1),(3,1,1),(4,17,1)],1)]
        saved=manager(records,visibility)
        output.append(fixture('recovery-'+java['id'],records,cursor=4,saved=saved,observed=observations(saved,records,java['destination_visibility'])))
    # Physical codec structure is intentionally weaker than live authority.
    saved=manager(base['records'])
    for m in saved['members']:m['key'][0]=1
    for section in saved['sections']:section['key'][0]=1
    saved['chunks']=[Inputs.chunk(1)]
    output.append(fixture('refused-stale-registered-key',saved=saved))
    saved=manager(base['records']);saved['members'][1]['box']=member(record(1,kind='item'))['box']
    output.append(fixture('refused-orb-item-sized-box',saved=saved))
    for name,mutate in [('nan',lambda box:box[0].__setitem__(0,0x7ff80000)),
                        ('inverted',lambda box:box.__setitem__(0,Inputs.words(100)))]:
        saved=manager(base['records']);mutate(saved['members'][1]['box'])
        output.append(fixture('refused-'+name+'-box',saved=saved))
    rows=[record(1),record(2,(2,1,1),0)]
    output.append(fixture('refused-duplicate-member-order',rows,cursor=1))
    saved=manager(base['records']);saved['members'].reverse();saved['sections'][0]['ids'].reverse()
    output.append(fixture('refused-insertion-list-chronology',saved=saved))
    c=copy.deepcopy(base);c.update(id='refused-publication-after-visibility-journal',publish=False);c['observations']['chunks'][0]['status']='HIDDEN';output.append(c)
    output.append(fixture('known-empty',[],cursor=0))
    c=fixture('refused-empty-missing-image',[],cursor=0);c['image_available']=False;output.append(c)
    c=fixture('refused-empty-missing-observations',[],cursor=0);c['observations_available']=False;output.append(c)
    rows=copy.deepcopy(base['records'])+[record(3,(3,1,1),2,removed=True)]
    output.append(fixture('retained-tombstone-runtime',rows,cursor=3,saved=manager(rows[:2])))
    output.append(fixture('refused-missing-tombstone-runtime',rows,cursor=3,saved=manager(rows[:2]),runtimes=[1,2]))
    rows=[record(1,accessible=False),record(2,(2,1,1),1,False)]
    saved=manager(rows,'HIDDEN');obs=observations(saved,rows);obs['chunks'][0]['loaded']=False
    output.append(fixture('current-unloaded-hidden',rows,saved=saved,observed=obs))
    obs=observations(manager(base['records']),base['records']);obs['chunks'].append(Inputs.chunk(7,status='HIDDEN'))
    output.append(fixture('extra-empty-current-chunk',observed=obs))
    saved=manager(base['records']);saved['chunks'].append(Inputs.chunk(7,status='HIDDEN'))
    output.append(fixture('refused-unused-saved-chunk-missing-current',saved=saved,observed=observations(manager(base['records']),base['records'])))
    rows=[record(1,(67108865,1,1)),record(2,(67108866,1,1),1)]
    output.append(fixture('registered-packed-wrap-alias',rows))
    for name,mutate in [('correct',lambda c:None),
                        ('poisoned-prefix',lambda c:c['constructor_prefix'][0].update(uuid_least=[17,19],position=Inputs.vector((41,43,47)),order=17,accessible=False)),
                        ('double-cursor',lambda c:c.update(constructor_delta=1)),
                        ('zero-cursor',lambda c:c.update(constructor_exhausted=True)),
                        ('wrong-record-order',lambda c:c['fresh_record'].update(order=3)),
                        ('publication',lambda c:c.update(publish=False)),
                        ('missing-current',lambda c:c.update(observations_available=False)),
                        ('duplicate-uuid',lambda c:c['fresh_record'].update(uuid_least=[0,1])),
                        ('copied-prefix-missing-id',lambda c:c['constructor_prefix'].pop()),
                        ('exhausted-cursor',lambda c:c.update(cursor_max=True,constructor_exhausted=True))]:
        c=fixture('fresh-'+name,mode='fresh');c['fresh_id']=3;c['constructor_prefix']=copy.deepcopy(c['records']);mutate(c);output.append(c)
    rows=[record(1),record(2,(17,1,1),1)];saved=manager(rows)
    obs=observations(saved,rows,'HIDDEN');obs['chunks'].reverse()
    c=fixture('current-observation-order',rows,saved=saved,observed=obs)
    source=next(j for j in reference['cases'] if j['category']=='chunk_visibility' and j['source_visibility']=='TICKING' and j['destination_visibility']=='HIDDEN')
    # Per-entity order is read from the recorded lone-member Java section, then
    # applied to the explicit supplied chunk order. No transition implementation.
    single=[e['event'] for e in source['steps'][1]['events'] if e['id']==1 and e['event'] in Inputs.CALLBACKS]
    c['expected_events']=[(name,id) for id in [2,1] for name in single];output.append(c)
    return output


def parse(raw):
    assert isinstance(raw,list) and all(isinstance(b,int) and 0<=b<=255 for b in raw),raw
    return N.parse(bytes(raw))
def field(value,key):return Wire.at(value,(key,))
def uint(value):return value.payload & 0xffffffff
def array(value):return [v&0xffffffff for v in value.payload]
def dimension(value):return ''.join(map(chr,array(value)))
def view_from_wire(raw):
    root=parse(raw);v=root.value;status=['HIDDEN','TRACKED','TICKING']
    def members():
        for row in field(v,'members').payload[1]:
            box=array(field(row,'box'));uuid=array(field(row,'uuid'))
            yield dict(dimension=dimension(field(row,'dimension')),id=uint(field(row,'id')),key=array(field(row,'key')),order=field(row,'order').payload,
                       box=[box[i:i+2] for i in range(0,12,2)],uuid=[uuid[:2],uuid[2:]])
    sections=[dict(dimension=dimension(field(row,'dimension')),key=array(field(row,'key')),status=status[uint(field(row,'visibility'))],members=array(field(row,'ids'))) for row in field(v,'sections').payload[1]]
    chunks=[dict(dimension=dimension(field(row,'dimension')),x=uint(field(row,'x')),z=uint(field(row,'z')),loaded=bool(uint(field(row,'loaded'))),status=status[uint(field(row,'visibility'))]) for row in field(v,'chunks').payload[1]]
    def registrations(key):return [dict(dimension=dimension(field(row,'dimension')),id=uint(field(row,'id'))) for row in field(v,key).payload[1]]
    return dict(members=list(members()),sections=sections,chunks=chunks,tracked=registrations('tracked'),ticked=registrations('ticked'))
def sections_key(view):return {(s['dimension'],*s['key']):(s['status'],s['members']) for s in view['sections']}
def chunks_key(values):return {(c['dimension'],c['x']&4194303,c['z']&4194303):(c['loaded'],c['status']) for c in values}
def ids(view,kind):return [r['id'] for r in view[kind] if r['dimension']==DIM]
def lifecycle(events):return [(e['event'],e['id']) for e in events if e['event'] in Inputs.CALLBACKS]
def q_records(document):return Wire.at(document.value,('entities','records')).payload[1]
def q_runtimes(document):return Wire.at(document.value,('runtimes','entries')).payload[1]
def patched_accessibility(document,records,visibility_by_chunk):
    result=document
    for index,row in enumerate(records):
        if row['removed']:continue
        m=member(row);key=(row['dimension'],m['key'][0],m['key'][2]);accessible=visibility_by_chunk[key]!='HIDDEN'
        result=Wire.changed(result,('entities','records',index,'common','accessible'),Wire.integer(int(accessible)))
    return result

def compare_restore(actual,provided,java):
    saved=view_from_wire(provided['saved']);prior=view_from_wire(provided['prior'])
    assert actual['prior_membership']==prior and actual['prior_membership_wire']==provided['prior'],provided['id']
    assert isinstance(actual['before'],list),dict(id=provided['id'],owner_snapshot=actual['before'])
    refused=provided['id'].startswith('refused-') or provided['id']=='format5-structural-restore-missing-loader'
    if refused:
        assert isinstance(actual['events'],dict) and isinstance(actual['events'].get('error'),str),dict(id=provided['id'],events=actual['events'])
        assert actual['before']==actual['after'],dict(id=provided['id'],failure='whole retained entity/runtime/RNG owner changed')
        assert actual['membership']==actual['prior_membership'] and actual['membership_wire']==actual['prior_membership_wire'],dict(id=provided['id'],failure='whole prior manager changed')
        return
    assert isinstance(actual['events'],list),dict(id=provided['id'],events=actual['events'])
    current=provided['observations']['chunks'];status={(c['dimension'],c['x']&4194303,c['z']&4194303):c['status'] for c in current}
    expected=patched_accessibility(parse(actual['before']),provided['records'],status)
    assert actual['after']==list(N.encode_root(expected)),dict(id=provided['id'],failure='complete retained scene differs beyond observed accessibility')
    view=actual['membership']
    assert view['members']==saved['members'],dict(id=provided['id'],failure='registered order/key/body/uuid/memberlist changed')
    expected_sections={(s['dimension'],*s['key']):(status[(s['dimension'],s['key'][0],s['key'][2])],s['members']) for s in saved['sections']}
    assert sections_key(view)==expected_sections,(provided['id'],sections_key(view),expected_sections)
    assert chunks_key(view['chunks'])==chunks_key(current),(provided['id'],view['chunks'],current)
    assert view_from_wire(actual['membership_wire'])==view,provided['id']
    if java is None:
        if 'expected_events' in provided:
            assert lifecycle(actual['events'])==[tuple(e) for e in provided['expected_events']],(provided['id'],actual['events'],provided['expected_events'])
            assert view['tracked']==[] and view['ticked']==[] and actual['query_ids']==[],provided['id']
        else:
            assert actual['events']==[],provided['id']
            assert view['tracked']==saved['tracked'] and view['ticked']==saved['ticked'],provided['id']
    else:
        projected=Inputs.expected_projection(java,java['steps'][1]);wanted=lifecycle(projected['events'])
        assert lifecycle(actual['events'])==wanted,(provided['id'],lifecycle(actual['events']),wanted)
        assert all(e['event'] in Inputs.CALLBACKS for e in actual['events']),provided['id']
        assert Inputs.normalized_sections(view)==[{k:s[k] for k in ['key','status','members']} for s in projected['state']['sections']],provided['id']
        assert actual['query_ids']==projected['state']['query_ids'],provided['id']
        assert ids(view,'tracked')==projected['state']['global_ids'],provided['id']
        scheduled=[]
        for step in java['steps']:
            for event,id in lifecycle(Inputs.expected_projection(java,step)['events']):
                if event=='ticking_start':scheduled.append(id)
                elif event=='ticking_end':scheduled.remove(id)
        assert ids(view,'ticked')==scheduled,(provided['id'],ids(view,'ticked'),scheduled)

def runtime_marker(value,identity):
    """Fixture translation: all supplied marker vectors vary only by ID."""
    old=tuple(word for pair in Inputs.vector((1,.125,-3)) for word in pair)
    new=tuple(word for pair in Inputs.vector((identity,.125,-3)) for word in pair)
    if value.kind==11 and value.payload==old:return N.Value(11,new)
    if value.kind==10:return N.Value(10,tuple((key,runtime_marker(v,identity)) for key,v in value.payload))
    if value.kind==9:
        kind,items=value.payload
        return N.Value(9,(kind,tuple(runtime_marker(v,identity) for v in items)))
    return value
def compare_fresh(actual,provided,registration):
    refused=provided['id'] not in ['fresh-correct','fresh-poisoned-prefix']
    assert actual['prior_membership_wire']==provided['saved'],provided['id']
    assert isinstance(actual['before'],list),actual['before']
    if refused:
        assert isinstance(actual['events'],dict) and actual['events'].get('error'),(provided['id'],actual['events'])
        assert actual['before']==actual['after'] and actual['membership_wire']==actual['prior_membership_wire'],provided['id']
        assert actual['membership']==actual['prior_membership'] and actual['remaining_times'] is None,provided['id']
        return
    before=parse(actual['before']);after=parse(actual['after']);old=q_records(before);new=q_records(after)
    assert len(new)==len(old)+1 and new[:-1]==old,provided['id']
    # Every existing runtime, optional sound, level source and entity field is exact.
    assert q_runtimes(after)[:-1]==q_runtimes(before) and len(q_runtimes(after))==len(q_runtimes(before))+1,provided['id']
    expected_runtime=Wire.H.replace_at(runtime_marker(q_runtimes(before)[0],3),('id',),Wire.integer(3))
    assert q_runtimes(after)[-1]==expected_runtime,dict(id=provided['id'],failure='fresh actual complete supplied runtime differs')
    for path in [('sound',),('entities','level_random')]:assert Wire.at(before.value,path)==Wire.at(after.value,path),provided['id']
    assert array(Wire.at(after.value,('entities','seed_uniquifier')))==[131,137]
    assert uint(Wire.at(after.value,('entities','last_id')))==3
    assert dimension(Wire.at(after.value,('entities','next_section_order')))=='3'
    fresh=new[-1];common=field(fresh,'common');payload=field(fresh,'payload')
    assert uint(field(fresh,'kind'))==0 and uint(field(common,'id'))==3
    assert array(field(common,'uuid_most'))==[0,0] and array(field(common,'uuid_least'))==[0,3]
    assert dimension(field(common,'section_order'))=='2' and uint(field(common,'accessible'))==1
    assert array(Wire.at(common,('fields','position')))==[word for pair in provided['fresh_record']['position'] for word in pair]
    assert (uint(field(payload,'age')),uint(field(payload,'pickup_delay')),uint(field(payload,'health')),uint(field(payload,'bob')))==(7,13,5,1069547520)
    assert array(field(payload,'thrower'))==[101,103,107,109] and array(field(payload,'target'))==[101,103,107,109]
    assert dimension(Wire.at(payload,('item','id')))=='minecraft:stone' and uint(Wire.at(payload,('item','count')))==3
    expected_common=field(old[0],'common')
    for path,value in [(('id',),Wire.integer(3)),(('uuid_most',),Wire.array(0,0)),(('uuid_least',),Wire.array(0,3)),
                       (('section_order',),Wire.dimension('2')),(('fields','position'),Wire.array(*(word for pair in provided['fresh_record']['position'] for word in pair)))]:
        expected_common=Wire.H.replace_at(expected_common,path,value)
    expected_payload=Wire.compound(item=Wire.compound(id=Wire.dimension('minecraft:stone'),components=Wire.dimension(''),count=Wire.integer(3)),
        age=Wire.integer(7),pickup_delay=Wire.integer(13),health=Wire.integer(5),thrower=Wire.array(101,103,107,109),target=Wire.array(101,103,107,109),bob=Wire.integer(1069547520))
    expected_new=Wire.compound(kind=Wire.integer(0),common=expected_common,payload=expected_payload)
    expected=before
    for path,value in [(('entities','records'),Wire.list_tag([*old,expected_new])),(('runtimes','entries'),Wire.list_tag([*q_runtimes(before),expected_runtime])),
                       (('entities','seed_uniquifier'),Wire.array(131,137)),(('entities','last_id'),Wire.integer(3)),(('entities','next_section_order'),Wire.dimension('3'))]:
        expected=Wire.changed(expected,path,value)
    assert actual['after']==list(N.encode_root(expected)),dict(id=provided['id'],failure='complete fresh scene differs from independent expected input join')
    assert actual['remaining_times']==[[211,223],[227,229]],provided['id']
    view=actual['membership'];saved=view_from_wire(provided['saved']);new_member=member(provided['fresh_record'])
    assert view['members']==[new_member]+saved['members'],provided['id']
    assert ids(view,'tracked')==[1,2,3] and ids(view,'ticked')==[1,2,3],provided['id']
    assert actual['query_ids']==[1,2,3],provided['id']
    wanted=[(name,3) for name,id in lifecycle(registration['steps'][0]['events'])]
    assert lifecycle(actual['events'])==wanted,(provided['id'],actual['events'],wanted)
    assert [(e['event'],e.get('id'),e.get('order')) for e in actual['events'] if e['event'] not in Inputs.CALLBACKS]==[('inserted',3,2)],provided['id']
    assert sections_key(view)=={(DIM,0,0,0):('TICKING',[1,2,3])},provided['id']


def main():
    WORK.mkdir(parents=True,exist_ok=True)
    ref=json.loads((ROOT/'reference/entity_section_membership.json').read_text());assert ref['pin']=='26.3'
    supplied=cases(ref);(WORK/'input.json').write_text(json.dumps(supplied,separators=(',',':'))+'\n')
    checks=[]
    try:
        if sys.argv[1:]==['--compare-only']:
            prior=json.loads((ROOT/'evidence/entity-section-membership-recovery-native.json').read_text())
            assert prior['status']=='passed'
            for name,key in [('input.json','input_sha256'),('native.stdout','native_output_sha256'),('receiver.c','native_C_sha256'),('receiver','native_binary_sha256')]:
                assert T.digest(WORK/name)==prior[key],('retained compiled input/output changed',name)
            checks=prior['checks']
        else:
            assert not sys.argv[1:],'supported optional argument: --compare-only'
            checks.append(T.run('emit',[T.NODE,'--experimental-transform-types','--expose-gc','--stack-size=4096','--max-old-space-size=1536','tools/entity_section_membership_recovery_emit.mjs','tests/entity_section_membership_recovery.bend',WORK/'receiver.c'],timeout=90))
            checks.append(T.run('clang',[shutil.which('clang'),'-std=c11','-O0','-fomit-frame-pointer',WORK/'receiver.c','-lpthread','-lm','-o',WORK/'receiver'],timeout=120))
            checks.append(T.run('native',['/usr/bin/time','-l',WORK/'receiver','--gpu','off','--threads','1',WORK/'input.json'],timeout=60,max_rss=1024**3))
        output=json.loads((WORK/'native.stdout').read_text());assert len(output)==len(supplied)
        indexed={c['id']:c for c in ref['cases']}
        registration=next(c for c in ref['cases'] if c['category']=='registration' and c['visibility']=='TICKING')
        for a,c in zip(output,supplied):
            assert a['id']==c['id'],(a['id'],c['id'])
            if c['mode']=='fresh':compare_fresh(a,c,registration)
            else:compare_restore(a,c,indexed.get(c['id'].removeprefix('recovery-')))
        source=json.loads((WORK/'receiver.c.sources.json').read_text())
        for path,sha in source['source_sha256'].items():assert T.digest(path)==sha,('compiled source drift',path)
        evidence=dict(status='passed',command='python3 tools/test_entity_section_membership_recovery.py',final_comparison_invocation=' '.join(['python3','tools/test_entity_section_membership_recovery.py',*sys.argv[1:]]),pin='26.3',checks=checks,source=source,
            reference_sha256=T.digest(ROOT/'reference/entity_section_membership.json'),native_test_sha256=T.digest(Path(__file__)),native_emitter_sha256=T.digest(ROOT/'tools/entity_section_membership_recovery_emit.mjs'),
            input_sha256=T.digest(WORK/'input.json'),native_output_sha256=T.digest(WORK/'native.stdout'),native_C_sha256=T.digest(WORK/'receiver.c'),native_binary_sha256=T.digest(WORK/'receiver'),native_cases=len(supplied),java_visibility_reconciliation_cases=9,fresh_constructor_cases=10,explicit_current_observation_order_cases=1,
            unchanged_manager_corpus_replayed=False,complete_entity_runtime_sound_owner_byte_preservation_on_refusal=True,complete_prior_manager_byte_preservation_on_refusal=True,
            compared=['actual installed membership structural decode followed by actual format5-component restore and live revalidation','exact independently recorded Java lifecycle order on nine visibility transitions','actual query and tracked insertion order; scheduled insertion order independently folded from Java callbacks',
                'unchanged registered key, body, UUID, order and member-list order after reconciliation','complete entity/RNG/runtime/sound fields preserved except current observed accessibility','saved insertion chronology validated; supplied current observation order drives exact journals','actual format5 component encode/decode/restore remains insufficient without live loader facts',
                'fresh actual item_created proposal cursor counted exactly once; poisoned copied prefix discarded; zero/double/max-exhausted cursors refused','callback publication refusal rolls back both actual owners','full fresh supplied runtime vectors/flags/fluids/support/pending/movements retained'],
            exclusions=['outer actor format5 storage transport and durable IO (owned by separate storage lane)','always-ticking entities and partial callback-state snapshots','live external world streaming, native client rendering and multiplayer'],
            build_boundary='Original complete ordinary source checking plus verified retained-closure emitter; actual production receivers in focused native CPU binary. No compiler/toolchain edits or proof claim.')
        (ROOT/'evidence/entity-section-membership-recovery-native.json').write_text(json.dumps(evidence,indent=2)+'\n')
        print(json.dumps({k:evidence[k] for k in ['status','native_cases','java_visibility_reconciliation_cases','fresh_constructor_cases']}))
    except BaseException as error:
        (WORK/'failure.json').write_text(json.dumps(dict(error=repr(error),checks=checks),indent=2)+'\n');raise

if __name__=='__main__':main()
