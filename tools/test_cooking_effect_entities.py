#!/usr/bin/env python3
"""Compare actual production Bend spawn owner with installed-Java observations."""
import copy,json,hashlib,shutil
from pathlib import Path
import test_campfire_authority as T
ROOT=T.ROOT;WORK=ROOT/'build/cooking-effect-entities-native';T.WORK=WORK

def normalized(values,defaults):
    values=copy.deepcopy(values)
    for row in values:
        for r in row['records']:
            if r['kind']=='item':r['item']=T.decoded_slot(r['item'],defaults)
    return values

def main():
    WORK.mkdir(parents=True,exist_ok=True)
    ref=json.loads((ROOT/'reference/cooking_effect_entities.json').read_text());assert ref['pin']=='26.3'
    catalog=json.loads((ROOT/'reference/campfire_authority.json').read_text())['inputs']['catalog']
    defaults={r['id']:r['components'] for r in catalog['items']}
    cases=[]
    for source,observed in zip(ref['inputs'],ref['observations']['cases']):
        assert source['id']==observed['id'];case={**copy.deepcopy(source),**observed}
        for name in ['x','y','z']:case[name]&=0xffffffff
        for a in case['actions']:
            if a['op']=='xp':a['uses']&=0xffffffff
        cases.append(case)
    (WORK/'input.json').write_text(json.dumps({'catalog':catalog,'cases':cases},separators=(',',':'))+'\n')
    paths=[p for pattern in ['src/cooking_effect_entities*','tests/cooking_effect_entities*','tools/*cooking_effect_entities*'] for p in ROOT.glob(pattern)]
    paths += [ROOT/'src/random.bend',ROOT/'src/f64.bend',ROOT/'src/vanilla_entity_fields.bend',ROOT/'reference/cooking_effect_entities.json']
    pins={str(p.relative_to(ROOT)):T.digest(p) for p in paths};checks=[]
    checks.append(T.run('check',[T.BEND,'tests/cooking_effect_entities.bend','--check-only']))
    assert 'ALL PROOFS CHECK' in (WORK/'check.stdout').read_text()
    checks.append(T.run('emit',[T.NODE,'--experimental-transform-types','--stack-size=4096','--max-old-space-size=1536','tools/cooking_effect_entities_emit.mjs','tests/cooking_effect_entities.bend',WORK/'receiver.c'],timeout=120,max_rss=2*1024**3))
    checks.append(T.run('clang',[shutil.which('clang'),'-std=c11','-O2',WORK/'receiver.c','-lpthread','-lm','-o',WORK/'receiver'],timeout=180,max_rss=2*1024**3))
    native=T.run('native',['/usr/bin/time','-l',WORK/'receiver','--gpu','off','--threads','1',WORK/'input.json'],timeout=60,max_rss=1024**3);checks.append(native)
    actual=normalized(json.loads((WORK/'native.stdout').read_text()),defaults)
    expected=[{key:row[key] for key in ['level_after','unique_after','cursor_after','records']} for row in ref['observations']['cases']]
    (WORK/'actual.json').write_text(json.dumps(actual,indent=2)+'\n');(WORK/'expected.json').write_text(json.dumps(expected,indent=2)+'\n')
    for a,b,c in zip(actual,expected,ref['inputs']):
        assert a==b,{'case':c['id'],'actual':a,'expected':b}
    assert len(actual)==len(expected)
    assert all(T.digest(ROOT/p)==h for p,h in pins.items()),'source changed during checks'
    evidence={'status':'passed','command':'python3 tools/test_cooking_effect_entities.py','source_sha256':pins,'checks':checks,'cases':len(expected),'actual_java_spawn_records_compared':sum(len(r['records']) for r in expected),'full_identity_and_bitwise_position_velocity_uuid_rotation_rng':True,'boundary':'Pure production affine owner and ordered per-effect prefix consumer; actual Java Containers.dropItemStack and ExperienceOrb.award/constructors, real section query ordering and declared geometry I/O. Clock FFI, live Sidecar/storage/world tick/pickup/render require their named integration checks.'}
    (ROOT/'evidence/cooking-effect-entities-native.json').write_text(json.dumps(evidence,indent=2)+'\n');print(json.dumps({'status':'passed','cases':len(expected),'records':evidence['actual_java_spawn_records_compared']}))
if __name__=='__main__':main()
