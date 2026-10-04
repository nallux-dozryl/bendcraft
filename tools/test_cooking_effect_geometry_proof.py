#!/usr/bin/env python3
"""Independent kernel verdict for unchanged implementation-connected geometry laws."""
import json
from pathlib import Path
import test_campfire_authority as T
ROOT=T.ROOT;WORK=ROOT/'build/cooking-effect-geometry-proof';T.WORK=WORK

def main():
    WORK.mkdir(parents=True,exist_ok=True)
    checks=[T.run('export',[T.NODE,'--experimental-transform-types','--stack-size=4096','--max-old-space-size=1536','tools/cooking_effect_geometry_proof.mjs',ROOT],timeout=150,max_rss=2*1024**3)]
    selection=json.loads((WORK/'selection.json').read_text());assert not selection['exclusions']
    checks.append(T.run('kernel',[T.KERNEL,WORK/'selected.bendtt'],timeout=120,max_rss=2*1024**3))
    text=(WORK/'kernel.stdout').read_text();assert 'ALL PROOFS CHECK' in text and 'SOME PROOFS FAIL' not in text,(len(selection['roots']),text[-2000:])
    evidence={'status':'passed','command':'python3 tools/test_cooking_effect_geometry_proof.py','kernel_roots':len(selection['roots']),'ordinary_only_roots':selection['ordinary_only_roots'],'ordinary_only_reason':'Full capture_gate references shared Q.error_text -> Nat.show.fin/go, whose mutual recursion is rejected by the independent exporter. Full root is ordinarily checked; the actual production refusal branch independently retains both complete owners.','roots':selection['roots'],'checks':checks,'export_sha256':T.digest(WORK/'selected.bendtt'),'checked_types_and_bodies_unchanged':selection['checked_types_and_bodies_unchanged'],'all_original_declaration_maps_retained':selection['all_original_declaration_maps_retained'],'source_sha256':selection['source_pins'],'scope':'Actual production placement/refusal, affine Core+catalog capture retention, strict closest-candidate choice, budget admission and free-search contracts. Java observes floating geometry specification; these laws do not prove every voxel boolean operator or live motion/world integration.'}
    (ROOT/'evidence/cooking-effect-geometry-proof.json').write_text(json.dumps(evidence,indent=2)+'\n');print(json.dumps({'status':'passed','kernel_laws':len(selection['roots'])}))
if __name__=='__main__':main()
