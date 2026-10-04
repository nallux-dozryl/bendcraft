import * as B from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/bend.ts";
import * as Safe from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/safe.ts";
import * as fs from "node:fs";
import * as crypto from "node:crypto";

try {
const sourceRoot = new URL("../src/", import.meta.url).pathname;
const entry = new URL("../src/local_player_cooking_proof.bend", import.meta.url).pathname;
const joinEntry = new URL("../src/runtime_block_inside_join_proof.bend", import.meta.url).pathname;
const runtimeTest = new URL("../tests/local_player_runtime.bend", import.meta.url).pathname;
const dir = process.argv[2];
if (!dir) throw Error("Fresh output directory required");
const ordinaryRoots = [
  "local_player_cooking_laws:already_initialized_begin_retains_complete_cooking_owner",
  "local_player_cooking_laws:paused_idle_tick_retains_complete_cooking_owner",
  "local_player_cooking_laws:noncanonical_context_save_retains_complete_cooking_owner",
  "local_player_cooking_laws:cooking_query_publishes_supplied_owner_and_retains_complete_session",
  "local_player_cooking_laws:cooking_inventory_query_publishes_all_supplied_owners_and_retains_session",
  "local_player_cooking_laws:pending_delivery_installs_actual_suffix_and_preserves_complete_sidecar",
  "local_player_cooking_laws:noncanonical_tail_active_tick_retains_complete_cooking_owner",
];
// Their public gate statements retain Nat.show.fin/go through diagnostic
// branches in full-definition export. Keep them ordinary checked; do not
// replace their statements or claim these refused/unsupported roots were
// independently certified.
const roots = ordinaryRoots.slice(3,6);
const ordinaryOnlyRoots = ordinaryRoots.filter(name => !roots.includes(name));
const sha = x => crypto.createHash("sha256").update(x).digest("hex");
const filePins = seen => Object.fromEntries([...seen.keys()].sort().map(p => [p, sha(fs.readFileSync(p))]));
const book = B.book_nil(), seen = new Map();
// One original Book and one import map: shared production modules are loaded
// and checked once. The test entry receives its own real path namespace.
await B.book_load(book, entry, "", seen, undefined, sourceRoot);
await B.book_load(book, joinEntry, "runtime_block_inside_join_proof", seen, undefined, sourceRoot);
await B.book_load(book, runtimeTest, "../tests/local_player_runtime", seen, undefined, sourceRoot);
const before = filePins(seen);
const ordinaryStarted = performance.now();
B.book_valid(book);
const ordinarySeconds = (performance.now() - ordinaryStarted) / 1000;
if (book.hols !== 0) throw Error("Open proof holes");
const originalOrder = [...book.order], originalTlds = book.tlds, originalCtrs = book.ctrs, originalTmps = book.tmps;
const originals = Object.entries(book.tlds).map(([k,t]) => [k,t,t.T,t.$ === "Def" ? t.v : null,t.$ === "Def" ? t.e : null]);
const checkedPins = names => names.map(name => {
  const t = book.tlds[name];
  if (t?.$ !== "Def" || !t.e || !t.v) throw Error("Missing checked declaration " + name);
  return {name, type_sha256:sha(B.term_key(B.term_lower(t.T))),
    checked_body_sha256:sha(B.term_key(t.e)), source_body_sha256:sha(B.term_key(B.term_lower(t.v)))};
});
for (const name of ordinaryRoots) {
  const t = book.tlds[name];
  if (t?.$ !== "Def" || t.u || t.i) throw Error("Missing pure production proof " + name);
}
const termPins = checkedPins(roots);
const ordinaryLawPins = checkedPins(ordinaryRoots);
const ordinaryOnlyPins = checkedPins([
  "../tests/local_player_runtime:camera_case",
  "runtime_block_inside_join_laws:successful_startup_restore_resets_transient_receiver_and_preserves_affine_owners",
]);
book.order = originalOrder.filter((k,i) => roots.includes(k) && originalOrder.lastIndexOf(k) === i);
if (book.order.length !== roots.length || book.tlds !== originalTlds || book.ctrs !== originalCtrs || book.tmps !== originalTmps)
  throw Error("Selection changed declaration ownership");
for (const [k,t,T,v,e] of originals)
  if (book.tlds[k] !== t || t.T !== T || (t.$ === "Def" && (t.v !== v || t.e !== e)))
    throw Error("Selection altered original checked declaration " + k);
const manifest = {entry, roots, ordinary_roots:ordinaryRoots, ordinary_only_roots:ordinaryOnlyRoots,
  ordinary_only_reason:"Four public leaf gate laws retain the observed unsupported Nat.show.fin/go mutual recursion through real diagnostic branches. Their proof bodies pass ordinary checking; they receive no independent-kernel claim.",
  ordinary_entries:[entry,joinEntry,runtimeTest], original_book_checks:1,
  shared_imports_loaded_once:true, ordinary_seconds:ordinarySeconds, original_root_count:originalOrder.length,
  selected_root_count:book.order.length, checked_types_and_bodies_unchanged:true,
  all_original_tlds_ctrs_tmps_retained:true, term_pins:termPins, ordinary_law_term_pins:ordinaryLawPins,
  ordinary_only_term_pins:ordinaryOnlyPins,
  source_files:[...seen.keys()], ordinary_source_api_check_passed:true,
  kernel_scope:"Only three new supplier-splice/delivery cooking laws. Seven new laws, runtime test annotation and renamed Detached join declarations are ordinary checked in this same original Book; no old kernel or native corpus replay."};
fs.writeFileSync(dir + "/selection.json", JSON.stringify(manifest,null,2) + "\n");
console.log(JSON.stringify({phase:"original-book-checked", roots:roots.length,
  ordinary_entries:manifest.ordinary_entries, ordinary_seconds:ordinarySeconds, original_root_count:originalOrder.length}));
const exportStarted = performance.now();
const exclusions = Safe.safe_emit(book, dir + "/selected.bendtt");
const exportSeconds = (performance.now() - exportStarted) / 1000;
fs.writeFileSync(dir + "/scope.json", JSON.stringify({exclusions,export_seconds:exportSeconds},null,2) + "\n");
console.log(JSON.stringify({phase:"export-complete", bytes:fs.statSync(dir + "/selected.bendtt").size,
  export_seconds:exportSeconds, exclusions}));
const after = filePins(seen);
if (JSON.stringify(before) !== JSON.stringify(after)) throw Error("Source changed during original Book check/export");
fs.writeFileSync(dir + "/source-pins.json", JSON.stringify(after,null,2) + "\n");
if (exclusions.length) process.exitCode = 2;
} catch (error) {
  console.error(error?.$ === "Err" ? B.err_show(error) : String(error));
  process.exitCode = 1;
}
