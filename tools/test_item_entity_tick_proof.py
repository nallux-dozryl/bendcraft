#!/usr/bin/env python3
"""Independently check unchanged selected roots of the actual tick implementation."""
import json
import test_campfire_authority as T
ROOT=T.ROOT;WORK=ROOT/'build/item-entity-tick-proof';T.WORK=WORK

def main():
    WORK.mkdir(parents=True,exist_ok=True)
    checks=[T.run('export',[T.NODE,'--experimental-transform-types','--stack-size=4096','--max-old-space-size=1536','tools/item_entity_tick_proof.mjs',ROOT],timeout=60)]
    checks.append(T.run('kernel',['/usr/bin/env','LEAN_STACK_SIZE=4194304',T.KERNEL,WORK/'selected.bendtt'],timeout=60))
    assert (WORK/'kernel.stdout').read_text().strip()=='ALL PROOFS CHECK'
    selection=json.loads((WORK/'selection.json').read_text())
    assert len(selection['roots'])==11 and len(selection['ordinary_only_roots'])==1
    assert selection['exclusions']==[] and selection['checked_types_and_bodies_unchanged'] and selection['all_original_declaration_maps_retained']
    evidence=dict(status='passed',ordinary_laws=12,independent_kernel_laws=11,checks=checks,selection=selection,artifact_sha256=T.digest(WORK/'selected.bendtt'),kernel_sha256=T.digest(T.KERNEL),ordinary_only_reason='Actual World.guarded full affine Core owner law checks in the source compiler. Its independent export traverses existing shared Nat.show mutual recursion and is excluded explicitly; no substitute owner/proof is used.',boundary='Actual complete E.Entity/E.State plus Runtime/sound ownership on refusal; empty early discard, signed sentinels/wrap, full record merge conservation/identity, ungrounded support-query branch. These laws do not prove Java specification, arbitrary world service completeness, actor scheduling, save codec or performance.')
    (ROOT/'evidence/item-entity-tick-proof.json').write_text(json.dumps(evidence,indent=2)+'\n')
    print(json.dumps({k:evidence[k] for k in ['status','ordinary_laws','independent_kernel_laws']}))
if __name__=='__main__':main()
