import * as B from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/bend.ts";
import * as Safe from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/safe.ts";
import * as fs from "node:fs";
import * as path from "node:path";
import * as crypto from "node:crypto";

// Load and check the ordinary complete source API first. Only export roots
// change; original declarations, constructors, checked types and bodies stay.
const entry = new URL("../src/local_resource_world_sample.bend", import.meta.url).pathname;
const dir = process.argv[2];
if (!dir) throw Error("Fresh output directory required");
if (!fs.existsSync(dir)) fs.mkdirSync(dir, {recursive:true});
if (fs.readdirSync(dir).length) throw Error("Output directory must be empty; preserve previous attempts");
const roots = [
  "local_resource_world_sample:invalid_frame_retains_complete_local_session",
  "local_resource_world_sample:palette_refusal_retains_complete_world_owner",
  "local_resource_world_sample:alignment_refusal_retains_complete_world_owner",
  "local_resource_world_sample:absent_cache_retains_complete_world_owner",
  "local_resource_world_sample:lost_palette_binding_retains_complete_world_owner",
  "local_resource_world_sample:read_refusal_retains_returned_core_registry_and_complete_view",
];
const sha = value => crypto.createHash("sha256").update(value).digest("hex");
const book = B.book_nil(), seen = new Map();
try {
  await B.book_load(book, entry, "local_resource_world_sample", seen);
  const before = Object.fromEntries([...seen.keys()].sort().map(p => [p, sha(fs.readFileSync(p))]));
  fs.writeFileSync(path.join(dir,"loaded-source-pins.json"), JSON.stringify(before,null,2)+"\n");
  B.book_valid(book);
  if (book.hols !== 0) throw Error("Open proof holes");
  const originalOrder = [...book.order];
  const originalTlds = book.tlds, originalCtrs = book.ctrs, originalTmps = book.tmps;
  const originals = Object.entries(book.tlds).map(([k,t]) =>
    [k,t,t.T,t.$ === "Def" ? t.v : null,t.$ === "Def" ? t.e : null]);
  const termPins = roots.map(name => {
    const term = book.tlds[name];
    if (term?.$ !== "Def" || !term.e || !term.v || term.u || term.i)
      throw Error("Missing checked pure proof "+name);
    return {name,type_sha256:sha(B.term_key(B.term_lower(term.T))),
      checked_proof_sha256:sha(B.term_key(term.e)),
      source_body_sha256:sha(B.term_key(B.term_lower(term.v)))};
  });
  book.order = originalOrder.filter((k,i) => roots.includes(k) && originalOrder.lastIndexOf(k) === i);
  if (book.order.length !== roots.length || roots.some(k => !book.order.includes(k)) ||
      book.tlds !== originalTlds || book.ctrs !== originalCtrs || book.tmps !== originalTmps)
    throw Error("Selection changed declaration ownership or omitted a required root");
  for (const [k,t,T,v,e] of originals)
    if (book.tlds[k] !== t || t.T !== T || (t.$ === "Def" && (t.v !== v || t.e !== e)))
      throw Error("Selection altered term "+k);
  const manifest = {entry,roots,original_root_count:originalOrder.length,
    selected_root_count:book.order.length,checked_types_and_bodies_unchanged:true,
    all_original_tlds_ctrs_tmps_retained:true,term_pins:termPins,
    source_files:[...seen.keys()],ordinary_source_api_check_passed:true,open_holes:book.hols};
  fs.writeFileSync(path.join(dir,"selection.json"), JSON.stringify(manifest,null,2)+"\n");
  console.log(JSON.stringify({phase:"checked-root-selection",roots,original_root_count:originalOrder.length,
    source_files:seen.size}));
  const exclusions = Safe.safe_emit(book,path.join(dir,"selected.bendtt"));
  fs.writeFileSync(path.join(dir,"scope.json"),JSON.stringify({exclusions},null,2)+"\n");
  const after = Object.fromEntries([...seen.keys()].sort().map(p => [p,sha(fs.readFileSync(p))]));
  if (JSON.stringify(before) !== JSON.stringify(after)) throw Error("Proof source changed during check/export");
  fs.writeFileSync(path.join(dir,"source-pins.json"),JSON.stringify(after,null,2)+"\n");
  console.log(JSON.stringify({phase:"export-complete",bytes:fs.statSync(path.join(dir,"selected.bendtt")).size,exclusions}));
  if (exclusions.length) process.exitCode = 2;
} catch (error) {
  console.error(error?.$ === "Err" ? B.err_show(error) : String(error));
  process.exitCode = 1;
}
