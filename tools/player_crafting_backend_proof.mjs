import * as B from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/bend.ts";
import * as Safe from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/safe.ts";
import * as fs from "node:fs";
import * as crypto from "node:crypto";
const entry=process.argv[3]||new URL("../src/player_crafting_backend_proof.bend", import.meta.url).pathname;
const dir=process.argv[2];
if(!dir)throw Error("Fresh output directory required");
const roots=["player_crafting_backend_laws:denied_crafting_request_retains_complete_actor", "player_crafting_backend_laws:denied_menu_observation_retains_complete_actor", "player_crafting_backend_laws:denied_physical_packet_retains_complete_actor_before_release", "player_crafting_backend_laws:inadmissible_crafting_request_retains_complete_actor", "player_crafting_backend_laws:inadmissible_menu_open_retains_complete_actor", "player_crafting_backend_laws:inadmissible_menu_close_retains_complete_actor", "player_crafting_backend_laws:inadmissible_result_click_retains_complete_actor", "player_crafting_backend_laws:inadmissible_menu_inspect_retains_complete_actor", "player_crafting_backend_laws:public_dispatch_rejoins_complete_session_and_context", "player_crafting_backend_laws:committed_craft_with_failed_refresh_stays_accepted"];
const sha=x=>crypto.createHash("sha256").update(x).digest("hex");
const book=B.book_nil(),seen=new Map();
console.log(JSON.stringify({phase:"load-start",entry}));
try { await B.book_load(book,entry,"",seen); } catch(error) {
  if(error?.$==="Err")console.error(B.err_show(error)); else console.error(error);
  process.exit(1);
}
console.log(JSON.stringify({phase:"load-complete",sources:seen.size}));
const before=Object.fromEntries([...seen.keys()].sort().map(p=>[p,sha(fs.readFileSync(p))]));
console.log(JSON.stringify({phase:"ordinary-start"}));
const checkedOrder=book.order;
let orderReads=0;
const tracedOrder=new Proxy(checkedOrder,{get(target,key,receiver){
  const value=Reflect.get(target,key,receiver);
  if(typeof key==="string" && /^(0|[1-9][0-9]*)$/.test(key)) {
    const i=Number(key); const read=orderReads++;
    if(read>=checkedOrder.length) {
      if(process.env.CRAFT_BACKEND_GC==="1" && global.gc) global.gc();
      console.log(JSON.stringify({phase:"ordinary-entry",i,key:value,memory:process.memoryUsage()}));
    }
  }
  return value;
}});
book.order=tracedOrder;
try { B.book_valid(book); } catch(error) {
  if(error?.$==="Err")console.error(B.err_show(error)); else console.error(error);
  process.exitCode=1; throw Error("Original ordinary checker rejected source");
} finally { book.order=checkedOrder; }
if(book.order!==checkedOrder)throw Error("Original order identity not restored");
console.log(JSON.stringify({phase:"ordinary-complete"}));
if(book.hols!==0)throw Error("Open proof holes");
if(process.env.CRAFT_BACKEND_SOURCE_ONLY==="1") {
  const after=Object.fromEntries([...seen.keys()].sort().map(p=>[p,sha(fs.readFileSync(p))]));
  if(JSON.stringify(before)!==JSON.stringify(after))throw Error("Source changed during ordinary check");
  fs.writeFileSync(dir+"/source-check.json",JSON.stringify({entry,original_event_count:book.order.length,original_order_restored:true,ordinary_source_api_check_passed:true,source_pins:after},null,2)+"\n");
  process.exit(0);
}
const originalOrder=[...book.order],originalTlds=book.tlds,originalCtrs=book.ctrs,originalTmps=book.tmps;
const originals=Object.entries(book.tlds).map(([k,t])=>[k,t,t.T,t.$==="Def"?t.v:null,t.$==="Def"?t.e:null]);
const termPins=roots.map(k=>{const t=book.tlds[k];if(t?.$!=="Def"||!t.e||!t.v||t.u||t.i)throw Error("Missing checked pure proof "+k);return {name:k,type_sha256:sha(B.term_key(B.term_lower(t.T))),checked_proof_sha256:sha(B.term_key(t.e)),source_body_sha256:sha(B.term_key(B.term_lower(t.v)))};});
book.order=originalOrder.filter((k,i)=>roots.includes(k)&&originalOrder.lastIndexOf(k)===i);
if(book.order.length!==roots.length||book.tlds!==originalTlds||book.ctrs!==originalCtrs||book.tmps!==originalTmps)throw Error("Selection changed declaration ownership");
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
