import * as B from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/bend.ts";
import * as Safe from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/safe.ts";
import * as fs from "node:fs";
import * as crypto from "node:crypto";
const entry=process.env.ITEM_COMPONENT_WIRE_PROOF_ENTRY||new URL("../src/item_component_wire_all_proof.bend", import.meta.url).pathname;
const dir=process.argv[2];
if(!dir)throw Error("Fresh output directory required");
const semanticRoots=["item_component_wire_laws:refused_component_validation_is_structurally_refused", "item_component_wire_laws:structurally_refused_key_cannot_enter_wire", "item_component_wire_laws:structurally_refused_slot_cannot_enter_wire", "item_component_wire_laws:missing_catalog_admission_retains_complete_player_owner", "item_component_wire_laws:creative_refusal_retains_complete_player_owner", "item_component_wire_laws:actual_catalog_refusal_retains_complete_player_owner", "item_component_wire_laws:modified_key_cannot_request_count_two", "item_component_wire_laws:failed_slot_install_retains_complete_player_owner"];
const candidateRoots=["item_component_wire_candidate_laws:clone_node_rejoins_complete_backings","item_component_wire_candidate_laws:actual_array_clone_preserves_every_raw_leaf_and_tree","item_component_wire_candidate_laws:clone_producer_retains_complete_profiles_and_lengths","item_component_wire_candidate_laws:prospective_encoding_refusal_retains_complete_original_owner","item_component_wire_candidate_laws:prospective_encoding_admission_publishes_complete_candidate"];
const transportRoots=["item_component_wire_transport_laws:rollback_inventory_reinstalls_complete_original_owner","item_component_wire_transport_laws:actual_actor_rollback_retains_world_shell_context_and_owner","item_component_wire_transport_laws:admitted_prospective_reply_publishes_exact_candidate_and_bytes"];
const allRoots=[...semanticRoots,...candidateRoots,...transportRoots];
const supported=[semanticRoots[0],semanticRoots[3],semanticRoots[6],semanticRoots[7]];
const rollbackRoots=transportRoots.slice(0,2);
const roots=process.argv.includes("--supported")?supported:process.argv.includes("--candidate")?candidateRoots:process.argv.includes("--rollback")?rollbackRoots:process.argv.includes("--transport")?transportRoots:allRoots;
const sha=x=>crypto.createHash("sha256").update(x).digest("hex");
const book=B.book_nil(),seen=new Map();
try { await B.book_load(book,entry,"",seen); } catch (error) { console.error(error?.$ === "Err" ? B.err_show(error) : String(error)); process.exit(1); }
const before=Object.fromEntries([...seen.keys()].sort().map(p=>[p,sha(fs.readFileSync(p))]));
try { B.book_valid(book); } catch (error) { console.error(error?.$ === "Err" ? B.err_show(error) : String(error)); process.exit(1); }
if(book.hols!==0)throw Error("Open proof holes");
const originalOrder=[...book.order],originalTlds=book.tlds,originalCtrs=book.ctrs,originalTmps=book.tmps;
const originals=Object.entries(book.tlds).map(([k,t])=>[k,t,t.T,t.$==="Def"?t.v:null,t.$==="Def"?t.e:null]);
const termPins=roots.map(k=>{const t=book.tlds[k];if(t?.$!=="Def"||!t.e||!t.v||t.u||t.i)throw Error("Missing checked pure proof "+k);return {name:k,type_sha256:sha(B.term_key(B.term_lower(t.T))),checked_proof_sha256:sha(B.term_key(t.e)),source_body_sha256:sha(B.term_key(B.term_lower(t.v)))};});
book.order=originalOrder.filter((k,i)=>roots.includes(k)&&originalOrder.lastIndexOf(k)===i);
if(book.order.length!==roots.length||book.tlds!==originalTlds||book.ctrs!==originalCtrs||book.tmps!==originalTmps)throw Error("Selection changed declaration ownership");
for(const [k,t,T,v,e] of originals)if(book.tlds[k]!==t||t.T!==T||(t.$==="Def"&&(t.v!==v||t.e!==e)))throw Error("Selection altered term "+k);
const manifest={entry,roots,ordinary_roots:allRoots,selected_scope:roots.length===allRoots.length?"all16":process.argv.includes("--candidate")?"five actual Array.clone backing/complete player candidate producer/refusal/admission roots":process.argv.includes("--rollback")?"two actual inventory and complete Session/Shell/context rollback roots; publication/encoder closure omitted explicitly":process.argv.includes("--transport")?"three actual inventory and complete Session/Shell/context rollback/publication roots":"four actual validation/complete player owner/count/installation producer roots; full profile/catalog closure roots omitted explicitly",original_root_count:originalOrder.length,selected_root_count:book.order.length,checked_types_and_bodies_unchanged:true,all_original_tlds_ctrs_tmps_retained:true,term_pins:termPins,source_files:[...seen.keys()],ordinary_source_api_check_passed:true};
fs.writeFileSync(dir+"/selection.json",JSON.stringify(manifest,null,2)+"\n");
console.log(JSON.stringify({phase:"checked-root-selection",roots,original_root_count:originalOrder.length}));
const exclusions=Safe.safe_emit(book,dir+"/selected.bendtt");
fs.writeFileSync(dir+"/scope.json",JSON.stringify({exclusions},null,2)+"\n");
console.log(JSON.stringify({phase:"export-complete",bytes:fs.statSync(dir+"/selected.bendtt").size,exclusions}));
if(exclusions.length)process.exitCode=2;

const after=Object.fromEntries([...seen.keys()].sort().map(p=>[p,sha(fs.readFileSync(p))]));
if(JSON.stringify(before)!==JSON.stringify(after))throw Error("Proof source changed during check/export");
fs.writeFileSync(dir+"/source-pins.json",JSON.stringify(after,null,2)+"\n");
