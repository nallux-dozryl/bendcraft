import * as B from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/bend.ts";
import * as Safe from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/safe.ts";
import * as fs from "node:fs";
import * as crypto from "node:crypto";

const directory=process.argv[2];
if(!directory)throw Error("Fresh output directory required");
const sourceRoot=new URL("../",import.meta.url).pathname;
const entry=sourceRoot+"src/local_player_cooking_save_box_proof.bend";
const consumers=["local_player_entity_scene","local_player_cooking_bootstrap"];
const names=["boxed_nondurable_save_retains_complete_session",
  "boxed_durable_without_snapshot_retains_complete_session",
  "boxed_durable_save_uses_exact_captured_acknowledgement"];
const roots=names.map(name=>"src/local_player_cooking_save_box_laws:"+name);
const book=B.book_nil(),seen=new Map();
const sha=value=>crypto.createHash("sha256").update(value).digest("hex");
try{
  await B.book_load(book,entry,"src/local_player_cooking_save_box_proof",seen,undefined,sourceRoot);
  for(const name of consumers)
    await B.book_load(book,sourceRoot+"src/"+name+".bend","src/"+name,seen,undefined,sourceRoot);
  const sources=[...seen.keys()].sort().map(path=>({path,sha256:sha(fs.readFileSync(path))}));
  const started=performance.now();
  B.book_valid(book);
  if(book.hols!==0)throw Error("Open source holes");
  const order=[...book.order],maps=[book.tlds,book.ctrs,book.tmps];
  const declarations=Object.entries(book.tlds).map(([name,t])=>[name,t,t.T,t.$==="Def"?t.v:null,t.$==="Def"?t.e:null]);
  const pins=roots.map(name=>{
    const t=book.tlds[name];
    if(t?.$!=="Def"||t.u||t.i||!t.v||!t.e)throw Error("Missing checked pure law "+name);
    return {name,type_sha256:sha(B.term_key(B.term_lower(t.T))),source_body_sha256:sha(B.term_key(B.term_lower(t.v))),checked_body_sha256:sha(B.term_key(t.e))};
  });
  const source={status:"source_checked",entry,consumers,declarations:declarations.length,holes:book.hols,
    original_book_checks:1,check_seconds:(performance.now()-started)/1000,source_files:sources,roots,term_pins:pins,
    scope:"Original whole loaded Book checks the changed actual Session save boxes and current recovery/Frame/bootstrap consumers. Pure laws cover returned owner and typed receipt retention; no writer IO, native arity, Entry startup or gameplay claim."};
  for(const item of sources)if(sha(fs.readFileSync(item.path))!==item.sha256)throw Error("Source changed: "+item.path);
  fs.writeFileSync(directory+"/source-checked.json",JSON.stringify(source,null,2)+"\n");
  console.log(JSON.stringify({phase:"source_checked",declarations:declarations.length,holes:book.hols,roots:roots.length,seconds:source.check_seconds}));
  book.order=order.filter((name,index)=>roots.includes(name)&&order.lastIndexOf(name)===index);
  if(book.order.length!==roots.length||book.tlds!==maps[0]||book.ctrs!==maps[1]||book.tmps!==maps[2])throw Error("Changed declaration maps");
  for(const [name,t,T,v,e]of declarations)
    if(book.tlds[name]!==t||t.T!==T||(t.$==="Def"&&(t.v!==v||t.e!==e)))throw Error("Changed checked term "+name);
  const exclusions=Safe.safe_emit(book,directory+"/save-box.bendtt");
  fs.writeFileSync(directory+"/scope.json",JSON.stringify({roots,exclusions,checked_types_and_bodies_unchanged:true,all_original_declaration_maps_retained:true},null,2)+"\n");
  if(exclusions.length)throw Error("Export exclusions: "+JSON.stringify(exclusions));
  for(const item of sources)if(sha(fs.readFileSync(item.path))!==item.sha256)throw Error("Source changed during export: "+item.path);
}catch(error){
  console.error(error?.$==="Err"?B.err_show(error):error?.stack??String(error));
  process.exitCode=1;
}
