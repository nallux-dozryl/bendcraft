import * as B from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/bend.ts";
import * as Safe from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/safe.ts";
import * as fs from "node:fs";
import * as crypto from "node:crypto";
const clientOnly=process.argv.includes("--client-source-only");
const entry=new URL(clientOnly?"../remote_resource_catalog_client.bend":"../src/generic_resource_world_sample_composition_proof.bend", import.meta.url).pathname;
const dir=process.argv[2];
if(!dir)throw Error("Fresh output directory required");
const roots=["generic_resource_world_sample_laws:another_registry_is_refused_before_sample_or_state_validation", "generic_resource_world_sample_laws:prior_registry_refusal_retains_the_exact_diagnostic", "generic_resource_world_sample_laws:invalid_sample_is_refused_before_catalog_traversal", "generic_resource_world_sample_laws:invisible_cells_do_not_consume_visible_binding_slots", "generic_resource_world_sample_laws:a_single_model_choice_never_consumes_a_random_ticket", "generic_resource_world_sample_laws:a_zero_weight_total_is_refused_before_modulo", "generic_resource_world_sample_laws:an_absent_appearance_override_retains_the_complete_surface", "generic_resource_world_sample_laws:traversal_refusal_retains_the_original_state_error", "generic_resource_world_sample_laws:an_empty_state_suffix_never_accesses_catalog_models", "generic_resource_world_sample_read_laws:camera_uses_the_supplied_pose_eye_as_origin", "generic_resource_world_sample_read_laws:invalid_region_snapshot_preserves_the_complete_world_owner", "generic_resource_world_sample_read_laws:prior_read_refusal_stops_every_remaining_cell", "generic_resource_world_sample_read_laws:exhausted_traversal_returns_the_complete_prefix_in_cell_order", "generic_resource_world_sample_read_laws:read_refusal_retains_the_returned_core_and_exact_diagnostic", "generic_resource_world_sample_read_laws:every_observed_state_retains_point_seed_appearance_and_prefix", "generic_resource_world_sample_read_laws:single_actual_core_read_returns_its_owner_and_all_observed_data", "generic_resource_world_sample_read_laws:failed_sample_retains_registry_and_complete_original_view", "generic_resource_world_sample_read_laws:admitted_sample_retains_registry_view_and_clock_metadata", "generic_resource_world_sample_read_laws:invalid_sample_retains_registry_and_complete_original_view", "generic_resource_world_sample_consumer_laws:refused_dimensions_preserve_every_saved_session_owner", "generic_resource_world_sample_consumer_laws:refused_lease_preserves_every_actor_owner_and_context", "generic_resource_world_sample_consumer_laws:refused_binding_preserves_every_texture_owner"];
const sha=x=>crypto.createHash("sha256").update(x).digest("hex");
const book=B.book_nil(),seen=new Map();
try { await B.book_load(book,entry,"",seen); } catch(e) { console.error(e?.$==="Err"?B.err_show(e):String(e)); process.exit(1); }
const before=Object.fromEntries([...seen.keys()].sort().map(p=>[p,sha(fs.readFileSync(p))]));
try { B.book_valid(book); } catch(e) { console.error(e?.$==="Err"?B.err_show(e):String(e)); process.exit(1); }
if(book.hols!==0)throw Error("Open proof holes");
if(clientOnly) {
  const after=Object.fromEntries([...seen.keys()].sort().map(p=>[p,sha(fs.readFileSync(p))]));
  if(JSON.stringify(before)!==JSON.stringify(after))throw Error("Client source changed during check");
  fs.writeFileSync(dir+"/source-api.json",JSON.stringify({entry,ordinary_source_api_check_passed:true,source_pins:after,source_files:seen.size},null,2)+"\n");
  console.log(JSON.stringify({phase:"client-source-api-pass",source_files:seen.size}));
  process.exit(0);
}
const originalOrder=[...book.order],originalTlds=book.tlds,originalCtrs=book.ctrs,originalTmps=book.tmps;
const originals=Object.entries(book.tlds).map(([k,t])=>[k,t,t.T,t.$==="Def"?t.v:null,t.$==="Def"?t.e:null]);
const termPins=roots.map(k=>{const t=book.tlds[k];if(t?.$!=="Def"||!t.e||!t.v||t.u||t.i)throw Error("Missing checked pure proof "+k);return {name:k,type_sha256:sha(B.term_key(B.term_lower(t.T))),checked_proof_sha256:sha(B.term_key(t.e)),source_body_sha256:sha(B.term_key(B.term_lower(t.v)))};});
book.order=originalOrder.filter((k,i)=>roots.includes(k)&&originalOrder.lastIndexOf(k)===i);
if(book.order.length!==22||book.tlds!==originalTlds||book.ctrs!==originalCtrs||book.tmps!==originalTmps)throw Error("Selection changed declaration ownership");
for(const [k,t,T,v,e] of originals)if(book.tlds[k]!==t||t.T!==T||(t.$==="Def"&&(t.v!==v||t.e!==e)))throw Error("Selection altered term "+k);
const manifest={entry,roots,original_root_count:originalOrder.length,selected_root_count:book.order.length,checked_types_and_bodies_unchanged:true,all_original_tlds_ctrs_tmps_retained:true,term_pins:termPins,source_files:[...seen.keys()],ordinary_source_api_check_passed:true};
fs.writeFileSync(dir+"/selection.json",JSON.stringify(manifest,null,2)+"\n");
console.log(JSON.stringify({phase:"checked-root-selection",roots,original_root_count:originalOrder.length}));
const exclusions=Safe.safe_emit(book,dir+"/selected.bendtt");
fs.writeFileSync(dir+"/scope.json",JSON.stringify({exclusions},null,2)+"\n");
console.log(JSON.stringify({phase:"export-complete",bytes:fs.statSync(dir+"/selected.bendtt").size,exclusions}));
if(exclusions.length)process.exitCode=2;

const after=Object.fromEntries([...seen.keys()].sort().map(p=>[p,sha(fs.readFileSync(p))]));
if(JSON.stringify(before)!==JSON.stringify(after))throw Error("Proof source changed during check/export");
fs.writeFileSync(dir+"/source-pins.json",JSON.stringify(after,null,2)+"\n");
