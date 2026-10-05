#!/usr/bin/env python3
"""Check actual scene ownership/composition laws with the independent kernel."""
import json
import test_campfire_authority as T
ROOT=T.ROOT;WORK=ROOT/'build/entity-scene-render-proof'
def receipt(checks):
 s=json.loads((WORK/'selection.json').read_text());scope=json.loads((WORK/'scope.json').read_text())
 assert len(s['roots'])==12 and s['ordinary_only_roots']==[] and scope['exclusions']==[]
 assert s['checked_types_and_bodies_unchanged'] and s['all_original_tlds_ctrs_tmps_retained']
 assert (WORK/'kernel.stdout').read_text().strip()=='ALL PROOFS CHECK'
 evidence={'status':'passed','ordinary_laws':12,'independent_kernel_laws':12,'roots':s['roots'],'checks':checks,'scope_exclusions':scope['exclusions'],'checked_types_and_bodies_unchanged':True,'all_original_declaration_maps_retained':True,'source_sha256':json.loads((WORK/'source-pins.json').read_text()),'term_pins':s['term_pins'],'selected_artifact_sha256':T.digest(WORK/'selected.bendtt'),'kernel_sha256':T.digest(T.KERNEL),'boundary':'Actual production shared physical texture owner has inductive exact prefix/suffix inverse and recovers both complete original CW/item owners; texture/admission/preparation/draw failure retains owners; rebasing preserves every vertex, UV, material field and culling while assigning global order; actual missing authority cannot become fullbright. Native resource IO, transcendental camera boundary, scene overlap/occlusion and actual authoritative live light publication remain separate.'}
 (ROOT/'evidence/entity-scene-render-proof.json').write_text(json.dumps(evidence,indent=2)+'\n');print(json.dumps({'status':'passed','independent_kernel_laws':12}))
def main():
 WORK.mkdir(parents=True,exist_ok=True);T.WORK=WORK
 checks=[T.run('export',[T.NODE,'--experimental-transform-types','--stack-size=4096','--max-old-space-size=2048','tools/entity_scene_render_proof.mjs',WORK],timeout=60,max_rss=2684354560)]
 checks.append(T.run('kernel',['/usr/bin/env','LEAN_STACK_SIZE=4194304',T.KERNEL,WORK/'selected.bendtt'],timeout=60));receipt(checks)
if __name__=='__main__':main()
