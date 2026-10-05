#!/usr/bin/env python3
"""Independent kernel for actual implementation-connected render laws."""
import json
import test_campfire_authority as T
ROOT=T.ROOT;WORK=ROOT/'build/item-entity-render-proof'
def receipt(checks):
    selection=json.loads((WORK/'selection.json').read_text());scope=json.loads((WORK/'scope.json').read_text())
    assert len(selection['roots'])==14 and selection['ordinary_only_roots']==[] and scope['exclusions']==[]
    assert selection['checked_types_and_bodies_unchanged'] and selection['all_original_tlds_ctrs_tmps_retained']
    assert (WORK/'kernel.stdout').read_text().strip()=='ALL PROOFS CHECK'
    evidence={'status':'passed','ordinary_laws':14,'independent_kernel_laws':14,'roots':selection['roots'],'checks':checks,'scope_exclusions':scope['exclusions'],'checked_types_and_bodies_unchanged':True,'all_original_declaration_maps_retained':True,'source_sha256':json.loads((WORK/'source-pins.json').read_text()),'term_pins':selection['term_pins'],'selected_artifact_sha256':T.digest(WORK/'selected.bendtt'),'kernel_sha256':T.digest(T.KERNEL),'boundary':'Actual E.Record/E.View and visual Snapshot production projection; source sequence, actual position_old versus position_o, complete item identity, simulation RNG/factory omission, affine Mth-table refusal retention, budget atomicity, UV and material preservation. Numeric transcendental parity, resource/PNG IO, GPU/world lightmap, atlas merge, actor wire capture and OS presentation are separate native/integration boundaries.'}
    (ROOT/'evidence/item-entity-render-proof.json').write_text(json.dumps(evidence,indent=2)+'\n');print(json.dumps({'status':'passed','independent_kernel_laws':14}))
def main():
    WORK.mkdir(parents=True,exist_ok=True);T.WORK=WORK
    checks=[T.run('export',[T.NODE,'--experimental-transform-types','--stack-size=4096','--max-old-space-size=1536','tools/item_entity_render_proof.mjs',WORK],timeout=60)]
    checks.append(T.run('kernel',['/usr/bin/env','LEAN_STACK_SIZE=4194304',T.KERNEL,WORK/'selected.bendtt'],timeout=60));receipt(checks)
if __name__=='__main__':main()
