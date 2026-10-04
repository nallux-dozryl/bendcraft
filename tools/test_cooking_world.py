#!/usr/bin/env python3
"""One narrow real-Core cooking lifecycle receiver; no old parity corpus replay."""
from pathlib import Path
import hashlib,json,shutil
import test_campfire_authority as B
import reference_furnace_authority_probe as F
ROOT=Path(__file__).resolve().parents[1]
WORK=ROOT/'build/cooking-world-native'
def sha(path):return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def prepare():
    WORK.mkdir(parents=True,exist_ok=True)
    camp=json.loads((ROOT/'reference/campfire_authority.json').read_text())['inputs']['catalog']
    furnace=json.loads((ROOT/'reference/furnace_authority.json').read_text())
    fuel,resource_pins=F.resources();fuel.update(items=furnace['items'],defaults=furnace['defaults'])
    names={r['id'] for r in camp['recipes']};camp['recipes'] += [r for r in F.inputs()['recipes'] if r['id'] not in names]
    bindings=json.loads((ROOT/'reference/cooking_world.json').read_text());states=[]
    for name in ('minecraft:furnace','minecraft:blast_furnace','minecraft:smoker','minecraft:campfire','minecraft:soul_campfire'):
        states.append(next(r['state'] for r in bindings['bindings'] if r['block']==name and r['lit']==(r['family']=='campfire') and (r['family']!='campfire' or r['properties']['waterlogged']=='false')))
    light=json.loads((ROOT/'reference/block_light_registry.json').read_text());ids={0,1,*[r['state'] for r in bindings['bindings']]};props=[]
    for state in sorted(ids):
        r=next(r for r in light['ranges'] if r[0]<=state<r[0]+r[1]);props.append(dict(state=state,emission=r[2],dampening=r[3]))
    assert resource_pins==furnace['resources'],'installed provider JSON differs from retained pinned Java inputs'
    request=dict(catalog=camp,fuel_catalog=fuel,manifest=(ROOT/'reference/cooking_world_bindings.tsv').read_text(),registry_identity=bindings['registry_identity'],properties=props,states=states)
    (WORK/'input.json').write_text(json.dumps(request,separators=(',',':'))+'\n')
def main():
    prepare();B.WORK=WORK
    pins={str(p.relative_to(ROOT)):sha(p) for pattern in ('src/cooking_world*.bend','tests/cooking_world*.bend') for p in ROOT.glob(pattern)}
    checks=[B.run('ordinary',[B.BEND,'tests/cooking_world.bend','--check-only'])]
    checks.append(B.run('proof-export',[B.NODE,'--experimental-transform-types','--stack-size=4096','--max-old-space-size=1536','tools/cooking_world_proof.mjs',WORK]))
    selection=json.loads((WORK/'selection.json').read_text());scope=json.loads((WORK/'scope.json').read_text())
    assert scope['exclusions']==[] and selection['selected_root_count']==6 and selection['checked_types_and_bodies_unchanged'] and selection['all_original_tlds_ctrs_tmps_retained']
    checks.append(B.run('independent-kernel',['/usr/bin/env','LEAN_STACK_SIZE=4194304',B.KERNEL,WORK/'selected.bendtt']))
    assert (WORK/'independent-kernel.stdout').read_text().strip()=='ALL PROOFS CHECK'
    checks.append(B.run('emit',[B.BEND,'tests/cooking_world.bend','-o',WORK/'receiver.c'],timeout=120,max_rss=4*1024**3))
    checks.append(B.run('clang',[shutil.which('clang') or '/usr/bin/clang','-std=c11','-O1',WORK/'receiver.c','-lpthread','-lm','-o',WORK/'receiver'],max_rss=2*1024**3))
    native=B.run('native',['/usr/bin/time','-l',WORK/'receiver','--gpu','off','--threads','1',WORK/'input.json'],max_rss=1024**3)
    record(checks,native,pins)

def record(checks,native,pins):
    selection=json.loads((WORK/'selection.json').read_text())
    lines=(WORK/'native.stdout').read_text().splitlines();assert len(lines)==17 and all(s.startswith('ok ') for s in lines),lines
    assert all(sha(ROOT/p)==h for p,h in pins.items()),'owned source changed during targeted check'
    evidence={'status':'passed','command':'python3 tools/test_cooking_world.py','checks':checks,'native':native,'guards':lines,'production_source_sha256':pins,'native_emitted_c_sha256':sha(WORK/'receiver.c'),'native_binary_sha256':sha(WORK/'receiver'),'actual_registry_states':35723,'cooking_bindings':88,'light_provider_rows':90,'ordinary_laws':6,'kernel_laws':6,'scope_exclusions':[],'term_pins':selection['term_pins'],'kernel_sha256':sha(B.KERNEL),'selected_artifact_sha256':sha(WORK/'selected.bendtt'),'proof_source_sha256':json.loads((WORK/'source-pins.json').read_text()),'unchanged_cooking_corpus_replayed':False,'retained_java_ignite_frame':'reference/furnace_authority.json cases[ignite]','proof_boundary':'The six stated production laws cover failed whole-owner plans, array/property retention, campfire cache reset and exact LIT partners. Generic permission/cadence whole-state equations do not normalize in the current matcher; native guards establish their tested boundaries, not universal proof.','boundary':'Actual sole Core/BW owner, accepted scheduled creation/removal/replacement, actual loaded recipes/item defaults/fuel authority, pending whole-owner provider retry, campfire outputs, player/slot/unloaded refusal, physical body save/load all five families, malformed NBT and Player import refusal, empty drop calls and remove/recreate/remove ownership. Native entity/XP RNG spawning, menu inventory transaction and durable save actor adoption remain explicit consumers.'}
    (ROOT/'evidence/cooking-world-native.json').write_text(json.dumps(evidence,indent=2)+'\n');print(json.dumps({'status':'passed','guards':len(lines),'native_seconds':native['seconds']}))
if __name__=='__main__':main()
