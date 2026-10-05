#!/usr/bin/env python3
"""Compare real production tick/merge to retained actual installed Java receivers."""
import copy,json,shutil,uuid,hashlib
import test_campfire_authority as T
ROOT=T.ROOT;WORK=ROOT/'build/item-entity-tick-native';T.WORK=WORK

def words(value):
    if value is None:return None
    n=uuid.UUID(value).int;return [[(n>>96)&0xffffffff,(n>>64)&0xffffffff],[(n>>32)&0xffffffff,n&0xffffffff]]
def native_record(value):
    r=copy.deepcopy(value)
    for name in ['thrower','target']:r[name]=words(r[name])
    return r

def expanded_observations(ref):
    observed=copy.deepcopy(ref['observations'])
    metadata=observed.pop('cell_metadata');shapes=observed.pop('cell_shapes');sets=observed.pop('cell_sets')
    for case in observed['cases']:
        case['cells']=[dict(metadata[m],x=x,y=y,z=z,boxes=shapes[b]) for x,y,z,m,b in sets[case.pop('cell_set')]]
    assert hashlib.sha256(json.dumps(observed,sort_keys=True,separators=(',',':')).encode()).hexdigest()==ref['canonical_observations_sha256']
    return observed
def main():
    WORK.mkdir(parents=True,exist_ok=True);ref=json.loads((ROOT/'reference/item_entity_tick.json').read_text());assert ref['pin']=='26.3'
    ref['observations']=expanded_observations(ref)
    catalog=copy.deepcopy(json.loads((ROOT/'reference/campfire_authority.json').read_text())['inputs']['catalog']);catalog['recipes']=[];catalog['tags']=[]
    catalog['items']=[r for r in catalog['items'] if r['id']=='minecraft:stone'];catalog['campfire_features']=[dict(id='minecraft:stone',enabled=True)]
    defaults={r['id']:r['components'] for r in catalog['items']}
    cases=[]
    for obs,raw in zip(ref['observations']['cases'],ref['inputs']):
        c=copy.deepcopy(obs);c['before']=native_record(c['before']);c.update(no_gravity=raw['no_gravity'],silent=raw['silent'],common=raw['common'],merge='other' in raw,guard='',geometry_dimension='minecraft:overworld',neutral_portal=True,available_cells=True,server=True)
        c['cells']=[r for r in c['cells'] if -1 <= r['x']-(1<<32 if r['x']>=1<<31 else 0) <= 2 and -2 <= r['y']-(1<<32 if r['y']>=1<<31 else 0) <= 3 and -1 <= r['z']-(1<<32 if r['z']>=1<<31 else 0) <= 2]
        assert len(c['cells'])==96
        c['expected_before']=copy.deepcopy(c['before'])
        if c['before']['item'] is not None:c['before']['item']['components']=c['input_patch']
        if 'other_before' in c:
            c['other_before']=native_record(c['other_before'])
            if c['other_before']['item'] is not None:c['other_before']['item']['components']=c['other_input_patch']
        cases.append(c)
    guards=[]
    for name,changes in [('no-cells',dict(available_cells=False)),('dimension',dict(geometry_dimension='minecraft:the_nether')),('portal',dict(neutral_portal=False)),('missing-runtime',{}),('client-authority',dict(server=False))]:
        c=copy.deepcopy(cases[0]);c.update(id='guard-'+name,guard=name,**changes);guards.append(c)
    c=copy.deepcopy(next(c for c in cases if c['id']=='water-splash'));c.update(id='guard-missing-sound',guard='missing-sound');guards.append(c)
    c=copy.deepcopy(cases[0]);c.update(id='guard-removed',guard='removed');c['before']['common']['removed']=True;c['expected_before']['common']['removed']=True;guards.append(c)
    successful=[]
    for mode,case_id in [('scene-fall','fall'),('scene-splash','water-splash')]:
        c=copy.deepcopy(next(c for c in cases if c['id']==case_id));c.update(id=mode,guard=mode);successful.append(c)
    (WORK/'input.json').write_text(json.dumps(dict(catalog=catalog,cases=cases+guards+successful),separators=(',',':'))+'\n')
    checks=[]
    checks.append(T.run('emit',[T.NODE,'--experimental-transform-types','--stack-size=4096','--max-old-space-size=1536','tools/item_entity_tick_emit.mjs','tests/item_entity_tick.bend',WORK/'receiver.c'],timeout=70))
    checks.append(T.run('clang',[shutil.which('clang'),'-std=c11','-O0','-fomit-frame-pointer',WORK/'receiver.c','-lpthread','-lm','-o',WORK/'receiver'],timeout=120))
    checks.append(T.run('native',['/usr/bin/time','-l',WORK/'receiver','--gpu','off','--threads','1',WORK/'input.json'],timeout=60,max_rss=1024**3))
    got=json.loads((WORK/'native.stdout').read_text());assert len(got)==len(cases)+len(guards)+len(successful)
    for actual,expected in zip(got,ref['observations']['cases']):
        assert actual['id']==expected['id'] and 'error' not in actual and 'fixture_error' not in actual,actual
        for name in ['after','other_after']:
            if name not in expected:continue
            want=native_record(expected[name]);value=copy.deepcopy(actual[name]);value['item']=None if value['item'] is not None and (value['item']['count']==0 or value['item']['count']>=2147483648) else T.decoded_slot(value['item'],defaults)
            assert value==want,dict(case=expected['id'],field=name,actual=value,expected=want)
        if 'other_after' not in expected:
            assert [e for e in actual['events'] if e is not None]==expected['events'],dict(case=expected['id'],actual=actual['events'],expected=expected['events'])
            assert actual['sound_after']==expected['sound_after'],dict(case=expected['id'],actual=actual['sound_after'],expected=expected['sound_after'])
            assert actual['runtime_after']==expected['runtime_after'],dict(case=expected['id'],actual=actual['runtime_after'],expected=expected['runtime_after'])
    for actual,source in zip(got[len(cases):len(cases)+len(guards)],guards):
        assert actual['id']==source['id'] and 'error' in actual
        assert actual['sound']==(None if source['guard']=='missing-sound' else dict(kind='legacy',seed=[55,66]))
        assert actual['level']==dict(kind='legacy',seed=[11,22]) and actual['unique']==[33,44] and actual['cursor']==91 and actual['order']==9
        record=actual['records'][0];record['item']=T.decoded_slot(record['item'],defaults);assert record==source['expected_before']
        assert actual['runtimes']==([] if source['guard']=='missing-runtime' else [dict(id=71,runtime=source['runtime_before'])])
    for actual,source in zip(got[len(cases)+len(guards):],successful):
        expected=next(c for c in ref['observations']['cases'] if c['id']==('fall' if source['guard']=='scene-fall' else 'water-splash'))
        assert 'error' not in actual and 'fixture_error' not in actual,actual
        assert actual['level']==dict(kind='legacy',seed=[11,22]) and actual['unique']==[33,44] and actual['cursor']==91 and actual['order']==9
        record=copy.deepcopy(actual['records'][0]);record['item']=T.decoded_slot(record['item'],defaults);assert record==native_record(expected['after'])
        assert actual['runtimes']==[dict(id=71,runtime=expected['runtime_after'])]
        assert actual['sound']==expected['sound_after']
        assert [e for e in actual['events'] if e is not None]==expected['events']
    evidence=dict(status='passed',pin='26.3',checks=checks,actual_java_cases=len(cases),actual_java_tick_cases=16,actual_java_merge_cases=8,native_owner_guards=len(guards),native_owner_commits=len(successful),reference_sha256=T.digest(ROOT/'reference/item_entity_tick.json'),source=json.loads((WORK/'receiver.c.sources.json').read_text()),build_boundary={'optimization':'-O0 -fomit-frame-pointer correctness build','release_optimization':'unverified: earlier Apple clang -O2 backend attempt reported live register clobbered by inserted prologue instructions'},repaired_attempts=[{'kind':'fixture_decode','reason':'Full effective component maps supplied where actual codec patches were required; reference now exports actual Java DataComponentPatch.CODEC separately.'},{'kind':'fixture_bits','reason':'Legacy collision helper emitted hexadecimal double bits; reference now emits exact word pairs matching native fields.'},{'kind':'production_event','reason':'Two independently observed landing cases found missing HIT_GROUND. Production now emits exact position/supporting block-state context; final ordered event comparison passes.'}],boundary='Actual installed ItemEntity.tick/commonTick/tryToMerge; exact full effective item map, RNG, common fields, motion bits and runtime boundary compare. No unchanged recipe/default corpus replay; only initialized stone definition is loaded. Core capture and unavailable-service refusal have separate production laws/guards.')
    (ROOT/'evidence/item-entity-tick-native.json').write_text(json.dumps(evidence,indent=2)+'\n');print(json.dumps({k:evidence[k] for k in ['status','actual_java_cases']}))
if __name__=='__main__':main()
