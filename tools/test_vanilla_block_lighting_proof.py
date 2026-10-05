#!/usr/bin/env python3
"""Independently check unchanged selected roots of the actual tick implementation."""
import json
import test_campfire_authority as T
ROOT=T.ROOT;WORK=ROOT/'build/vanilla-block-lighting-proof';T.WORK=WORK

def main():
    WORK.mkdir(parents=True,exist_ok=True)
    checks=[T.run('export',[T.NODE,'--experimental-transform-types','--stack-size=4096','--max-old-space-size=1536','tools/vanilla_block_lighting_proof.mjs',ROOT],timeout=60)]
    checks.append(T.run('kernel',['/usr/bin/env','LEAN_STACK_SIZE=4194304',T.KERNEL,WORK/'selected.bendtt'],timeout=60))
    assert (WORK/'kernel.stdout').read_text().strip()=='ALL PROOFS CHECK'
    selection=json.loads((WORK/'selection.json').read_text())
    assert len(selection['roots'])==7 and len(selection['ordinary_only_roots'])==0
    assert selection['exclusions']==[] and selection['checked_types_and_bodies_unchanged'] and selection['all_original_declaration_maps_retained']
    evidence=dict(status='passed',ordinary_laws=7,independent_kernel_laws=7,checks=checks,selection=selection,artifact_sha256=T.digest(WORK/'selected.bendtt'),kernel_sha256=T.digest(T.KERNEL),boundary='Actual pervertex lighting paths: zero emission retains fractional coordinates, emissive bypass, opaque diagonal fallback, unweighted corner preservation, arbitrary known flat quad light uniformity, missing state and brightness refusal. These laws do not claim Java specification, actual Core capture or renderer/GPU integration.')
    (ROOT/'evidence/vanilla-block-lighting-proof.json').write_text(json.dumps(evidence,indent=2)+'\n')
    print(json.dumps({k:evidence[k] for k in ['status','ordinary_laws','independent_kernel_laws']}))
if __name__=='__main__':main()
