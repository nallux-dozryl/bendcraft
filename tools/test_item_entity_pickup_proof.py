#!/usr/bin/env python3
"""Check the actual pickup implementation-connected laws, with explicit scope."""
from pathlib import Path
import json
import test_campfire_authority as T
ROOT=T.ROOT;WORK=ROOT/'build/item-entity-pickup-proof';T.WORK=WORK

def receipt(checks):
    selection=json.loads((WORK/'selection.json').read_text());scope=json.loads((WORK/'scope.json').read_text())
    assert len(selection['roots'])==12 and len(selection['ordinary_roots'])==15 and len(selection['ordinary_only_roots'])==3
    assert scope['exclusions']==[] and selection['checked_types_and_bodies_unchanged'] and selection['all_original_tlds_ctrs_tmps_retained']
    evidence={'status':'passed','ordinary_laws':15,'independent_kernel_laws':12,'ordinary_only_roots':selection['ordinary_only_roots'],'ordinary_only_reason':'The complete dispatch/admission/scene gates transitively reference actual initialized-key admission and shared json.encode_go. A full checked13-root export was accepted by the exporter with zero exclusions but independently rejected in json.encode_go for affine live code calls that descend. The12 selected roots retain the original checked terms; actual production inactive/scan-refusal branches and full M.committed rollback are independently checked, not replacement state models.','roots':selection['roots'],'scope_exclusions':scope['exclusions'],'checks':checks,'checked_types_and_bodies_unchanged':True,'all_original_declaration_maps_retained':True,'source_sha256':json.loads((WORK/'source-pins.json').read_text()),'term_pins':selection['term_pins'],'selected_artifact_sha256':T.digest(WORK/'selected.bendtt'),'kernel_sha256':T.digest(T.KERNEL),'boundary':'Actual E.Entity/E.State and P.State owners; connected refusal, count restoration/stat quantity, partial survival publications, creative residue and thrower branches. No proof of contact/world scheduling, complete component codecs, Java behavior, packet/stat execution or persistence.'}
    (ROOT/'evidence/item-entity-pickup-proof.json').write_text(json.dumps(evidence,indent=2)+'\n')
    print(json.dumps({k:evidence[k] for k in ['status','ordinary_laws','independent_kernel_laws']}))

def main():
    WORK.mkdir(parents=True,exist_ok=True)
    checks=[T.run('export',[T.NODE,'--experimental-transform-types','--stack-size=4096','--max-old-space-size=1536','tools/item_entity_pickup_proof.mjs',WORK],timeout=60)]
    checks.append(T.run('kernel',['/usr/bin/env','LEAN_STACK_SIZE=4194304',T.KERNEL,WORK/'selected.bendtt'],timeout=60))
    assert (WORK/'kernel.stdout').read_text().strip()=='ALL PROOFS CHECK'
    receipt(checks)
if __name__=='__main__':main()
