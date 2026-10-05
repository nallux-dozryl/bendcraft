import * as B from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/bend.ts";
import * as Safe from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/safe.ts";
import * as fs from "node:fs";
import * as crypto from "node:crypto";

const directory = process.argv[2];
if (!directory) throw Error("Fresh output directory required");
const sourceRoot = new URL("../src/",import.meta.url).pathname;
const entry = sourceRoot + "local_player_effect_tick_recovery_proof.bend";
const sha = value => crypto.createHash("sha256").update(value).digest("hex");
const book = B.book_nil(), seen = new Map();
try {
  await B.book_load(book,entry,"",seen,undefined,sourceRoot);
  const sources = [...seen.keys()].sort().map(path=>({path,sha256:sha(fs.readFileSync(path))}));
  B.book_valid(book);
  if (book.hols) throw Error("Open source holes");
  const roots = ["records_install_inspect_is_lossless", "entity_install_inspect_is_lossless",
    "tick_inspect_retains_complete_owner", "restore_inspect_retains_complete_recovery",
    "unavailable_runtime_refuses_full_restore", "absent_sound_cannot_borrow_level_source"]
    .map(name=>"local_player_effect_tick_recovery_laws:"+name);
  const order = [...book.order], maps = [book.tlds,book.ctrs,book.tmps];
  const declarations = Object.entries(book.tlds).map(([name,t])=>
    [name,t,t.T,t.$==="Def"?t.v:null,t.$==="Def"?t.e:null]);
  const terms = roots.map(name=>{
    const t=book.tlds[name];
    if(t?.$!=="Def"||t.u||t.i||!t.v||!t.e)throw Error("Missing pure checked recovery law "+name);
    return {name,type_sha256:sha(B.term_key(B.term_lower(t.T))),
      source_body_sha256:sha(B.term_key(B.term_lower(t.v))),checked_body_sha256:sha(B.term_key(t.e))};
  });
  // Source checking used every original declaration. This selects only the
  // stated, checked proof obligations for the independent kernel export.
  book.order=order.filter((name,index)=>roots.includes(name)&&order.lastIndexOf(name)===index);
  if(book.order.length!==roots.length||maps.some((map,i)=>map!==[book.tlds,book.ctrs,book.tmps][i]))
    throw Error("Export changed declaration owners");
  for(const [name,t,T,v,e]of declarations)
    if(book.tlds[name]!==t||t.T!==T||(t.$==="Def"&&(t.v!==v||t.e!==e)))
      throw Error("Export changed checked declaration "+name);
  const exclusions=Safe.safe_emit(book,directory+"/recovery.bendtt");
  for(const row of sources)if(sha(fs.readFileSync(row.path))!==row.sha256)
    throw Error("Source changed during check/export: "+row.path);
  fs.writeFileSync(directory+"/source-proof.json",JSON.stringify({status:"source_checked",entry,
    declarations:declarations.length,holes:book.hols,original_book_checks:1,source_files:sources,
    roots,term_pins:terms,exclusions,checked_types_and_bodies_unchanged:true,
    all_original_declaration_maps_retained:true,
    scope:"Six full actual record/sole-owner inspect/install composition and missing-authority refusal laws. No NBT parsing, serialization limits, bootstrap, durable IO, live tick or Session theorem."},null,2)+"\n");
  if(exclusions.length)throw Error("Recovery-law exclusions: "+JSON.stringify(exclusions));
  console.log(JSON.stringify({status:"source_checked",roots:roots.length,holes:book.hols}));
}catch(error){
  console.error(error?.$==="Err"?B.err_show(error):String(error));
  process.exitCode=1;
}
