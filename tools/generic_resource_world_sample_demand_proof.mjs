import * as B from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/bend.ts";
import * as Safe from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/safe.ts";
import * as fs from "node:fs";
import * as crypto from "node:crypto";

// Prepared export route; run only after actual heavy-job coordination.
const entry = new URL("../src/generic_resource_world_sample_demand_proof.bend",import.meta.url).pathname;
const lawFile = new URL("../src/generic_resource_world_sample_demand_laws.bend",import.meta.url).pathname;
const dir = process.argv[2];
if (!dir) throw Error("Fresh output directory required");
if (!fs.existsSync(dir)) fs.mkdirSync(dir,{recursive:true});
if (fs.readdirSync(dir).length) throw Error("Output directory must be empty; preserve previous attempts");
const roots = [...fs.readFileSync(lawFile,"utf8").matchAll(/^law ([A-Za-z_]\w*):/gm)]
  .map(match => "generic_resource_world_sample_demand_laws:"+match[1]);
if (roots.length !== 16 || new Set(roots).size !== 16) throw Error("Expected all 16 distinct declared demand laws");
const sha = value => crypto.createHash("sha256").update(value).digest("hex");
const book = B.book_nil(), seen = new Map();
try {
  await B.book_load(book,entry,"",seen);
  const before = Object.fromEntries([...seen.keys()].sort().map(p => [p,sha(fs.readFileSync(p))]));
  fs.writeFileSync(dir+"/loaded-source-pins.json",JSON.stringify(before,null,2)+"\n");
  B.book_valid(book);
  if (book.hols !== 0) throw Error("Open proof holes");
  const originalOrder = [...book.order], originalTlds = book.tlds, originalCtrs = book.ctrs, originalTmps = book.tmps;
  const originals = Object.entries(book.tlds).map(([k,t]) => [k,t,t.T,t.$ === "Def" ? t.v : null,t.$ === "Def" ? t.e : null]);
  const termPins = roots.map(name => {
    const t = book.tlds[name];
    if (t?.$ !== "Def" || !t.e || !t.v || t.u || t.i) throw Error("Missing checked pure proof "+name);
    return {name,type_sha256:sha(B.term_key(B.term_lower(t.T))),checked_proof_sha256:sha(B.term_key(t.e)),
      source_body_sha256:sha(B.term_key(B.term_lower(t.v)))};
  });
  book.order = originalOrder.filter((k,i) => roots.includes(k) && originalOrder.lastIndexOf(k) === i);
  if (book.order.length !== roots.length || roots.some(k => !book.order.includes(k)) ||
      book.tlds !== originalTlds || book.ctrs !== originalCtrs || book.tmps !== originalTmps)
    throw Error("Selection changed declaration ownership or omitted a required root");
  for (const [k,t,T,v,e] of originals)
    if (book.tlds[k] !== t || t.T !== T || (t.$ === "Def" && (t.v !== v || t.e !== e)))
      throw Error("Selection altered term "+k);
  fs.writeFileSync(dir+"/selection.json",JSON.stringify({entry,roots,original_root_count:originalOrder.length,
    selected_root_count:book.order.length,checked_types_and_bodies_unchanged:true,all_original_tlds_ctrs_tmps_retained:true,
    term_pins:termPins,source_files:[...seen.keys()],ordinary_source_api_check_passed:true,open_holes:book.hols},null,2)+"\n");
  console.log(JSON.stringify({phase:"checked-root-selection",roots,original_root_count:originalOrder.length,source_files:seen.size}));
  const exclusions = Safe.safe_emit(book,dir+"/selected.bendtt");
  fs.writeFileSync(dir+"/scope.json",JSON.stringify({exclusions},null,2)+"\n");
  const after = Object.fromEntries([...seen.keys()].sort().map(p => [p,sha(fs.readFileSync(p))]));
  if (JSON.stringify(before) !== JSON.stringify(after)) throw Error("Proof source changed during check/export");
  fs.writeFileSync(dir+"/source-pins.json",JSON.stringify(after,null,2)+"\n");
  console.log(JSON.stringify({phase:"export-complete",bytes:fs.statSync(dir+"/selected.bendtt").size,exclusions}));
  if (exclusions.length) process.exitCode = 2;
} catch(error) {
  console.error(error?.$ === "Err" ? B.err_show(error) : String(error));
  process.exitCode = 1;
}
