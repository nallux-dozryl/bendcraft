import * as B from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/bend.ts";
import * as Safe from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/safe.ts";
import * as fs from "node:fs";
import * as crypto from "node:crypto";

const directory = process.argv[2];
if (!directory) throw Error("Fresh output directory required");
const entry = new URL("../remote_resource_server.bend",import.meta.url).pathname;
const sourceRoot = new URL("../",import.meta.url).pathname;
const proofPaths = ["local_player_entity_scene_proof", "local_player_cooking_publication_proof",
  "local_player_cooking_entities_proof", "local_player_cooking_proof"];
const sha = value => crypto.createHash("sha256").update(value).digest("hex");
const book = B.book_nil(), seen = new Map();
try {
  await B.book_load(book,entry,"",seen);
  for (const name of proofPaths)
    await B.book_load(book,new URL("../src/" + name + ".bend",import.meta.url).pathname,
      "src/" + name,seen,undefined,sourceRoot);
  const sources = [...seen.keys()].sort().map(path => ({path,sha256:sha(fs.readFileSync(path))}));
  const checkStarted = performance.now();
  B.book_valid(book);
  const checkSeconds = (performance.now() - checkStarted)/1000;
  if (book.hols !== 0) throw Error("Open source holes");
  const names = [
    "invalid_frame_guard_retains_complete_session",
    "invalid_partial_guard_retains_complete_session",
    "unsupported_dimension_retains_complete_session",
    "sample_refusal_retains_returned_session_and_exact_error",
    "captured_bound_projection_retains_complete_returned_session",
    "captured_unbound_owner_remains_explicitly_unbound"
  ];
  const publicationNames = [
    "failed_save_retains_complete_publication_owner",
    "publisher_return_retains_complete_entity_owner",
    "failed_save_retains_complete_cooking_sidecar",
    "nondurable_receipt_retains_complete_session",
    "absent_save_snapshot_retains_complete_session",
    "noncanonical_publication_tail_retains_complete_owner"
  ];
  const roots = [...names.map(name => "src/local_player_entity_scene_laws:" + name),
    ...publicationNames.map(name => "src/local_player_cooking_publication_laws:" + name)];
  const order = [...book.order], maps = [book.tlds,book.ctrs,book.tmps];
  const declarations = Object.entries(book.tlds).map(([name,t]) => [name,t,t.T,t.$ === "Def" ? t.v : null,t.$ === "Def" ? t.e : null]);
  const pins = roots.map(name => {
    const t = book.tlds[name];
    if (t?.$ !== "Def" || t.u || t.i || !t.v || !t.e) throw Error("Missing pure checked owner law " + name);
    return {name,type_sha256:sha(B.term_key(B.term_lower(t.T))),
      source_body_sha256:sha(B.term_key(B.term_lower(t.v))),checked_body_sha256:sha(B.term_key(t.e))};
  });
  book.order = order.filter((name,index) => roots.includes(name) && order.lastIndexOf(name) === index);
  if (book.order.length !== roots.length || book.tlds !== maps[0] || book.ctrs !== maps[1] || book.tmps !== maps[2])
    throw Error("Export changed declaration owners");
  for (const [name,t,T,v,e] of declarations)
    if (book.tlds[name] !== t || t.T !== T || (t.$ === "Def" && (t.v !== v || t.e !== e)))
      throw Error("Export changed a checked declaration " + name);
  const sourceReceipt = {
    entry,additional_entries:proofPaths.map(name => "src/" + name + ".bend"),status:"source_checked",
    declarations:declarations.length,holes:book.hols,original_book_checked:true,
    original_book_checks:1,source_files:sources,ordinary_selected_roots:roots,
    check_seconds:checkSeconds,term_pins:pins,kernel_or_native_claim:false,
    scope:"One unchanged original book_valid checks the full actual Entry, DriverIO, atomic Frame capture, cooking publication/init/save and the added/changed owner law closures. Native/foreign boundaries are typed, not executed."
  };
  for (const source of sources)
    if (sha(fs.readFileSync(source.path)) !== source.sha256) throw Error("Source changed during original check: " + source.path);
  fs.writeFileSync(directory + "/source-checked.json",JSON.stringify(sourceReceipt,null,2) + "\n");
  console.log(JSON.stringify({status:"source_checked",declarations:declarations.length,holes:book.hols,
    source_files:sources.length,check_seconds:checkSeconds}));
  const exclusions = Safe.safe_emit(book,directory + "/entity-scene.bendtt");
  for (const source of sources)
    if (sha(fs.readFileSync(source.path)) !== source.sha256) throw Error("Source changed during check/export: " + source.path);
  fs.writeFileSync(directory + "/source-proof.json",JSON.stringify({
    entry,additional_entries:proofPaths.map(name => "src/" + name + ".bend"),status:"source_checked",declarations:declarations.length,holes:book.hols,original_book_checked:true,
    original_book_checks:1,source_files:sources,roots,term_pins:pins,exclusions,
    all_original_declaration_maps_retained:true,checked_types_and_bodies_unchanged:true,
    scope:"Complete actual Entry consumer graph plus six atomic Session frame laws, six publication/save-receipt owner laws, and the changed cooking/entity owner proof closures. This does not prove actor serialization, native rendering, entity simulation, world reads or socket behavior."},null,2) + "\n");
  if (exclusions.length) throw Error("Owner-law export exclusions: " + JSON.stringify(exclusions));
  console.log(JSON.stringify({status:"source_checked",declarations:declarations.length,holes:book.hols,roots:roots.length}));
} catch (error) {
  console.error(error?.$ === "Err" ? B.err_show(error) : String(error));
  process.exitCode = 1;
}
