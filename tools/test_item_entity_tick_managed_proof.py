#!/usr/bin/env python3
"""Independently check unchanged selected roots of the actual tick implementation."""
import json
import test_campfire_authority as T
ROOT=T.ROOT;WORK=ROOT/'build/item-entity-tick-managed-proof';T.WORK=WORK

def main():
    WORK.mkdir(parents=True,exist_ok=True)
    checks=[T.run('export',[T.NODE,'--experimental-transform-types','--stack-size=4096','--max-old-space-size=1536','tools/item_entity_tick_managed_proof.mjs',ROOT],timeout=60)]
    checks.append(T.run('kernel',['/usr/bin/env','LEAN_STACK_SIZE=4194304',T.KERNEL,WORK/'selected.bendtt'],timeout=60))
    assert (WORK/'kernel.stdout').read_text().strip()=='ALL PROOFS CHECK'
    selection=json.loads((WORK/'selection.json').read_text())
    assert len(selection['roots'])==5 and len(selection['ordinary_only_roots'])==0
    assert selection['exclusions']==[] and selection['checked_types_and_bodies_unchanged'] and selection['all_original_declaration_maps_retained']
    evidence=dict(status='passed',ordinary_laws=5,independent_kernel_laws=5,checks=checks,selection=selection,artifact_sha256=T.digest(WORK/'selected.bendtt'),kernel_sha256=T.digest(T.KERNEL),boundary='Actual managed Scene complete two-owner failure and sound rollback, atomic accepted membership/entity/runtime/sound installation, settled discard-plan preservation and staged removal dedup. These laws do not claim Java specification or external publication/durable writer integration.')
    (ROOT/'evidence/item-entity-tick-managed-proof.json').write_text(json.dumps(evidence,indent=2)+'\n')
    print(json.dumps({k:evidence[k] for k in ['status','ordinary_laws','independent_kernel_laws']}))
if __name__=='__main__':main()
