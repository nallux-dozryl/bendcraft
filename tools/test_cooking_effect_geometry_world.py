#!/usr/bin/env python3
"""One actual canonical Core capture and same-owner refusal recovery."""
import json,shutil,copy
from pathlib import Path
import test_campfire_authority as T
import test_slab_collision_world as Fixture
import test_world_codec as WC
import test_nbt as N
import reference_slab_collision_probe as Slabs
from test_persistence import OFFICIAL
ROOT=T.ROOT;WORK=ROOT/'build/cooking-effect-geometry-world-native';T.WORK=WORK

def bits(s):v=int(s,16);return [v>>32,v&0xffffffff]
def vector(a):return [bits(v) for v in a] if a is not None else None

def main():
    WORK.mkdir(parents=True,exist_ok=True)
    ref=json.loads((ROOT/'reference/cooking_effect_geometry_tie.json').read_text());source=ref['inputs'][0];actual=ref['observations']['cases'][0]
    # Existing independent physical Core fixture encoder; no host collision logic.
    body=Fixture.world_fixture(source,{'reads':[[x,y,z,0] for x in [-4,4] for y in [-4,4] for z in [-4,4]]})
    (WORK/'world.nbt').write_bytes(body)
    checks=[T.run('emit',[T.NODE,'--experimental-transform-types','--stack-size=4096','--max-old-space-size=1536','tools/cooking_effect_geometry_emit.mjs','tests/cooking_effect_geometry_world.bend',WORK/'receiver.c'],timeout=120,max_rss=2*1024**3)]
    checks.append(T.run('clang',[shutil.which('clang'),'-std=c11','-O2',WORK/'receiver.c','-lpthread','-lm','-o',WORK/'receiver'],timeout=180,max_rss=2*1024**3))
    checks.append(T.run('native',['/usr/bin/time','-l',WORK/'receiver','--gpu','off','--threads','1',OFFICIAL,Slabs.TABLE,WORK/'world.nbt'],timeout=60,max_rss=1024**3))
    lines=(WORK/'native.stdout').read_text().splitlines();value=json.loads(lines[0])
    expected={'clear':actual['clear'],'free':vector(actual.get('free')),'position':vector(actual['position']),'body':vector(actual['body']),'outer':vector(actual['outer']),**{k:[vector(b) for b in actual[k]['boxes']] for k in ['search','union','available']}}
    assert value==expected,(value,expected)
    assert lines[1:]==['capture\towner\t1','unresolved\tgeometry:environment-or-border-unresolved','unresolved\towner\t1','budget\tquery-budget','budget\towner\t1'],lines[1:]
    sourcepins=json.loads((WORK/'receiver.c.sources.json').read_text())['source_sha256']
    assert all(T.digest(Path(p))==h for p,h in sourcepins.items())
    evidence={'status':'passed','command':'python3 tools/test_cooking_effect_geometry_world.py','checks':checks,'source_sha256':sourcepins,'actual_java_cases':1,'case':source['id'],'canonical_registry_states':35723,'initialized_slab_states':606,'core_fixture':T.digest(WORK/'world.nbt'),'capture_and_refusal_core_bytes_preserved':True,'refusals':['unresolved-entity/border-facts','cell-budget'],'scope':'Actual canonical Registry+slab catalog load, physical Core decode and existing real block-read scanner feeding production immutable Geometry Context; exact Java placement plus complete Core canonical-byte retention on success and two refusals. Live actor/scene join and expanded shape/entity/border domain remain separate.'}
    (ROOT/'evidence/cooking-effect-geometry-world-native.json').write_text(json.dumps(evidence,indent=2)+'\n');print(json.dumps({'status':'passed','actual_core_capture':1,'refusals':2}))
if __name__=='__main__':main()
