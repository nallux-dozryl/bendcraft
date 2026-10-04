import * as B from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/bend.ts";
import * as Safe from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/safe.ts";
import * as fs from "node:fs";
import * as crypto from "node:crypto";
const entry=new URL("../src/item_component_proof.bend", import.meta.url).pathname;
const dir=process.argv[2];
if(!dir)throw Error("Fresh output directory required");
const allRoots=["item_component_laws:effect_identifier_roundtrip", "item_component_laws:nbt_duration_retains_all_signed_words", "item_component_laws:typed_nbt_effect_roundtrip", "item_component_laws:ordered_nbt_effects_roundtrip", "item_component_laws:complete_typed_patch_roundtrip", "item_component_laws:missing_defaults_refuse_complete_key", "item_component_laws:missing_defaults_refuse_metadata", "item_component_laws:admitted_metadata_retains_complete_key", "item_component_laws:disabled_catalog_definition_refuses_components", "item_component_laws:admission_refusal_retains_complete_inventory_owner", "item_component_laws:load_refusal_retains_complete_inventory_owner", "item_component_laws:missing_defaults_load_retains_complete_inventory_owner", "item_component_laws:nbt_refusal_retains_complete_inventory_owner"];
// Historical8-root selection from the retained Nat.show exporter failure.
// Current full13 export has no exclusions but encounters json.encode_go at the
// independent kernel. Keep this selection explicit; it never certifies all13.
const unsupported=["missing_defaults_refuse_complete_key","missing_defaults_refuse_metadata","load_refusal_retains_complete_inventory_owner","missing_defaults_load_retains_complete_inventory_owner","nbt_refusal_retains_complete_inventory_owner"].map(k=>"item_component_laws:"+k);
const roots=process.argv.includes("--supported")?allRoots.filter(k=>!unsupported.includes(k)):allRoots;
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
const manifest={entry,roots,ordinary_roots:allRoots,historical_unsupported_full_validator_roots:unsupported,original_root_count:originalOrder.length,selected_root_count:book.order.length,checked_types_and_bodies_unchanged:true,all_original_tlds_ctrs_tmps_retained:true,term_pins:termPins,source_files:[...seen.keys()],ordinary_source_api_check_passed:true};
fs.writeFileSync(dir+"/selection.json",JSON.stringify(manifest,null,2)+"\n");
console.log(JSON.stringify({phase:"checked-root-selection",roots,original_root_count:originalOrder.length}));
const exclusions=Safe.safe_emit(book,dir+"/selected.bendtt");
fs.writeFileSync(dir+"/scope.json",JSON.stringify({exclusions},null,2)+"\n");
console.log(JSON.stringify({phase:"export-complete",bytes:fs.statSync(dir+"/selected.bendtt").size,exclusions}));
if(exclusions.length)process.exitCode=2;

const after=Object.fromEntries([...seen.keys()].sort().map(p=>[p,sha(fs.readFileSync(p))]));
if(JSON.stringify(before)!==JSON.stringify(after))throw Error("Proof source changed during check/export");
fs.writeFileSync(dir+"/source-pins.json",JSON.stringify(after,null,2)+"\n");
