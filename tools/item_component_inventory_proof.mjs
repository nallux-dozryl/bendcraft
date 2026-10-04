import * as B from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/bend.ts";
import * as Safe from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/safe.ts";
import * as fs from "node:fs";
import * as crypto from "node:crypto";
const entry=new URL("../src/item_component_inventory_proof.bend", import.meta.url).pathname;
const dir=process.argv[2];
if(!dir)throw Error("Fresh output directory required");
const allRoots=["item_component_inventory_laws:missing_catalog_definition_refuses_component_defaults", "item_component_inventory_laws:disabled_catalog_definition_refuses_component_defaults", "item_component_inventory_laws:default_metadata_branch_preserves_existing_catalog_lookup", "item_component_inventory_laws:refused_slot_cannot_become_a_saved_tag", "item_component_inventory_laws:producer_completion_preserves_entire_save_owner_and_payload", "item_component_inventory_laws:failed_menu_encode_retains_entire_save_owner"];
const defaultsAndOwner=[allRoots[0],allRoots[1],allRoots[4]];
const roots=process.argv.includes("--defaults-owner")?defaultsAndOwner:process.argv.includes("--owner-core")?allRoots.filter(k=>!k.endsWith(":failed_menu_encode_retains_entire_save_owner")):allRoots;
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
const manifest={entry,roots,ordinary_roots:allRoots,selected_scope:roots.length===allRoots.length?"all6":roots.length===3?"missing/disabled defaults and complete Saved producer owner; metadata/slot/full menu encoder roots omitted explicitly":"five actual catalog/slot/complete Saved producer roots; conditional actual menu encoder root omitted explicitly",original_root_count:originalOrder.length,selected_root_count:book.order.length,checked_types_and_bodies_unchanged:true,all_original_tlds_ctrs_tmps_retained:true,term_pins:termPins,source_files:[...seen.keys()],ordinary_source_api_check_passed:true,cli_whole_import_verdict:"Existing 43 storage foreign/unsafe dependencies; selected pure closure independently exported"};
fs.writeFileSync(dir+"/selection.json",JSON.stringify(manifest,null,2)+"\n");
console.log(JSON.stringify({phase:"checked-root-selection",roots,original_root_count:originalOrder.length}));
const exclusions=Safe.safe_emit(book,dir+"/selected.bendtt");
fs.writeFileSync(dir+"/scope.json",JSON.stringify({exclusions},null,2)+"\n");
console.log(JSON.stringify({phase:"export-complete",bytes:fs.statSync(dir+"/selected.bendtt").size,exclusions}));
if(exclusions.length)process.exitCode=2;

const after=Object.fromEntries([...seen.keys()].sort().map(p=>[p,sha(fs.readFileSync(p))]));
if(JSON.stringify(before)!==JSON.stringify(after))throw Error("Proof source changed during check/export");
fs.writeFileSync(dir+"/source-pins.json",JSON.stringify(after,null,2)+"\n");
