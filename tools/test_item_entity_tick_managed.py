#!/usr/bin/env python3
"""Compare actual managed Bend tick with independent pinned Java receiver I/O."""
import copy,json,shutil,struct,sys
import test_campfire_authority as T
from test_item_entity_tick import native_record
from test_entity_section_membership import normalized_sections,CALLBACKS
ROOT=T.ROOT;WORK=ROOT/'build/item-entity-tick-managed-native';T.WORK=WORK

def vector(values):return [list(struct.unpack('>II',struct.pack('>d',float(v)))) for v in values]
def expand(ref):
    out=copy.deepcopy(ref['observations']);meta=out.pop('cell_metadata');shapes=out.pop('cell_shapes');sets=out.pop('cell_sets')
    for row in out['cases']:row['cells']=[dict(meta[m],x=x,y=y,z=z,boxes=shapes[b]) for x,y,z,m,b in sets[row.pop('cell_set')]]
    return out['cases']
def case(obs,raw):
    c=dict(id=obs['id'],guard='',before=[native_record(r) for r in obs['before']],coverage=vector(raw['coverage']),cells=obs['cells'],sound_before=obs['sound_before'],chunks=[dict(dimension='minecraft:overworld',loaded=True,x=r['x']&0xffffffff,z=r['z']&0xffffffff,status=r['status']) for r in raw['chunks']])
    for r,patch in zip(c['before'],obs['patches']):
        if r['item'] is not None:r['item']['components']=patch
    return c

def records(rows,defaults):
    result=[]
    for row in rows:
        r=copy.deepcopy(row)
        s=r['item'];r['item']=None if s is not None and (s['count']==0 or s['count']>=2147483648) else T.decoded_slot(s,defaults)
        # A removed record retains its old accessibility until tombstone purge;
        # Java getAll instead excludes removed IDs. Manager registries are
        # compared separately and remain the scheduling/query authority.
        if r['common']['removed']:r['common'].pop('accessible')
        result.append(r)
    return result

def expected_records(rows):
    result=[native_record(r) for r in rows]
    for r in result:
        if r['common']['removed']:r['common'].pop('accessible')
    return result

def compare(actual,java,defaults):
    assert actual['id']==java['id'] and actual['error'] is None,actual
    before,after=actual['before'],actual['after']
    assert records(before['records'],defaults)==expected_records(java['before']),dict(case=java['id'],field='before records')
    assert records(after['records'],defaults)==expected_records(java['after']),dict(case=java['id'],field='after records',actual=records(after['records'],defaults),expected=expected_records(java['after']))
    for snapshot,name in [(before,'before'),(after,'after')]:
        assert snapshot['level']==dict(kind='legacy',seed=[11,22]) and snapshot['unique']==[33,44] and snapshot['cursor']==91
        assert snapshot['runtimes']==[dict(id=r['common']['id'],runtime=runtime) for r,runtime in zip(java[name],java['runtime_'+name])],dict(case=java['id'],field='runtime '+name,actual=snapshot['runtimes'],expected=java['runtime_'+name])
        assert snapshot['sound']==java['sound_'+name],dict(case=java['id'],field='sound '+name)
        assert normalized_sections(snapshot['manager'])==java['sections_'+name],dict(case=java['id'],field='sections '+name,actual=normalized_sections(snapshot['manager']),expected=java['sections_'+name])
        assert [r['id'] for r in snapshot['manager']['tracked']]==java['tracked_'+name]
        assert [r['id'] for r in snapshot['manager']['ticked']]==java['scheduled_'+name]
        assert snapshot['query']==java['query_'+name],dict(case=java['id'],field='query '+name,actual=snapshot['query'],expected=java['query_'+name])
        assert snapshot['order']==len(java['before'])+(int(java['section_key_changed']) if name=='after' else 0)
        indexed={r['common']['id']:r for r in snapshot['records']}
        for member in snapshot['manager']['members']:
            common=indexed[member['id']]['common']
            assert member['order']==common['section_order']<snapshot['order'] and member['uuid']==[common['uuid_most'],common['uuid_least']]
            assert not common['removed']
    callbacks=[dict(event=e['event'],id=e['id']) for e in actual['callbacks'] if e['event'] in CALLBACKS]
    assert callbacks==java['callbacks'],dict(case=java['id'],field='callbacks',actual=callbacks,expected=java['callbacks'])
    assert [e for e in actual['effects'] if e is not None]==java['effects'],dict(case=java['id'],field='effects',actual=actual['effects'],expected=java['effects'])

def main():
    WORK.mkdir(parents=True,exist_ok=True);ref=json.loads((ROOT/'reference/item_entity_tick_managed.json').read_text());assert ref['pin']=='26.3';observed=expand(ref)
    catalog=copy.deepcopy(json.loads((ROOT/'reference/campfire_authority.json').read_text())['inputs']['catalog']);catalog['recipes']=[];catalog['tags']=[];catalog['items']=[r for r in catalog['items'] if r['id']=='minecraft:stone'];catalog['campfire_features']=[dict(id='minecraft:stone',enabled=True)];defaults={r['id']:r['components'] for r in catalog['items']}
    cases=[case(obs,raw) for obs,raw in zip(observed,ref['inputs'])];by_id={c['id']:c for c in cases};guards=[]
    for mode,source in [('missing-registration','cross-empty-section'),('unscheduled','cross-empty-section'),('missing-neighbour','cross-destination-tie-order'),('missing-sound','cross-splash')]:
        c=copy.deepcopy(by_id[source]);c.update(id='guard-'+mode,guard=mode);guards.append(c)
    for mode in ['missing-destination','unloaded-destination','duplicate-destination']:
        c=copy.deepcopy(by_id['cross-empty-section']);c.update(id='guard-'+mode)
        if mode=='missing-destination':c['chunks']=[r for r in c['chunks'] if r['x']!=1]
        elif mode=='unloaded-destination':
            for r in c['chunks']:
                if r['x']==1:r['loaded']=False
        else:c['chunks'].append(copy.deepcopy(next(r for r in c['chunks'] if r['x']==1)))
        guards.append(c)
    (WORK/'input.json').write_text(json.dumps(dict(catalog=catalog,cases=cases+guards),separators=(',',':'))+'\n')
    if '--reuse-native' in sys.argv:
        pins=json.loads((WORK/'receiver.c.sources.json').read_text())['source_sha256']
        assert all(T.digest(path)==digest for path,digest in pins.items()),'cached native source changed'
        checks=[json.loads((WORK/(name+'.json')).read_text()) for name in ['emit','clang']]
    else:
        checks=[T.run('emit',[T.NODE,'--experimental-transform-types','--stack-size=4096','--max-old-space-size=1536','tools/item_entity_tick_emit.mjs','tests/item_entity_tick_managed.bend',WORK/'receiver.c'],timeout=70)]
        checks.append(T.run('clang',[shutil.which('clang'),'-std=c11','-O0','-fomit-frame-pointer',WORK/'receiver.c','-lpthread','-lm','-o',WORK/'receiver'],timeout=120))
    checks.append(T.run('native',[WORK/'receiver','--gpu','off','--threads','1',WORK/'input.json'],timeout=60,max_rss=1024**3))
    got=json.loads((WORK/'native.stdout').read_text());assert len(got)==len(cases)+len(guards)
    for actual,expected in zip(got,observed):compare(actual,expected,defaults)
    for actual in got[len(cases):]:
        assert actual['error'] is not None and actual['before']==actual['after'] and actual['callbacks']==[],actual
    evidence=dict(status='passed',pin='26.3',actual_java_cases=len(cases),complete_owner_refusals=len(guards),checks=checks,reference_sha256=T.digest(ROOT/'reference/item_entity_tick_managed.json'),source=json.loads((WORK/'receiver.c.sources.json').read_text()),repaired_fixture_boundary='Initial same-section/splash inputs lacked sufficient captured fluid/inside-block halo. Actual Java cell observations were expanded for these two cases; unchanged native source/executable pins were verified before reuse.',build_boundary='Correctness native build uses -O0 -fomit-frame-pointer; release optimization/performance not established.',boundary='Actual ItemEntity.commonTick/tick joined to actual PersistentEntitySectionManager, EntityTickList and getter queries. Crossings to new/existing hidden/tracked/ticking sections, actual insertion-order merges, source/neighbour/empty/despawn removal, nondefault full components and sound/RNG preservation. Complete native records/runtime/manager registries/cursors/effects compared. Removed accessibility is a retained tombstone projection; actual manager query/scheduler exclusion is independently compared. Seven failures retain all original scene+manager owners, including rollback after staged movement/merge and sound failure. No unchanged 24-case tick replay, full Core actor or durable callback writer claimed.')
    (ROOT/'evidence/item-entity-tick-managed-native.json').write_text(json.dumps(evidence,indent=2)+'\n');print(json.dumps(dict(status='passed',actual_java_cases=len(cases),complete_owner_refusals=len(guards))))
if __name__=='__main__':main()
