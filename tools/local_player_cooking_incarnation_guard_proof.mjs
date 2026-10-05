import * as B from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/bend.ts";
import * as Safe from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/safe.ts";
import * as fs from "node:fs";
import * as crypto from "node:crypto";

// Check the original proof and narrow observer in one unmodified Book. Root
// selection changes order only; every original declaration map/body remains.
try {
  const dir = process.argv[2];
  if (!dir || process.argv.length !== 3) throw Error("Fresh output directory required");
  const sourceRoot = new URL("../src/", import.meta.url).pathname;
  const entry = new URL("../src/local_player_cooking_incarnation_guard_proof.bend", import.meta.url).pathname;
  const test = new URL("../tests/local_player_cooking_incarnation_guard.bend", import.meta.url).pathname;
  const names = [
    "every_actual_admission_path_retains_complete_trie",
    "created_key_overlay_retains_complete_world",
    "rejected_application_cannot_advance_lifecycle_scan",
    "same_block_change_has_no_owner_reset",
    "exhaustion_branch_refuses_before_increment",
    "acknowledged_reset_preserves_counter_map",
    "refused_scan_cancels_all_later_due_admission",
    "guard_refusal_retains_complete_cooking_world",
    "prepared_guard_failure_precedes_all_clock_and_due_publication",
  ];
  const roots = names.map(name => "local_player_cooking_incarnation_guard_laws:" + name);
  const sha = value => crypto.createHash("sha256").update(value).digest("hex");
  const pins = seen => Object.fromEntries([...seen.keys()].sort().map(path => [path,sha(fs.readFileSync(path))]));
  const book = B.book_nil(), seen = new Map();
  await B.book_load(book,entry,"",seen,undefined,sourceRoot);
  console.log(JSON.stringify({phase:"original-proof-loaded",declarations:book.order.length,source_files:seen.size}));
  await B.book_load(book,test,"../tests/local_player_cooking_incarnation_guard",seen,undefined,sourceRoot);
  console.log(JSON.stringify({phase:"original-observer-loaded",declarations:book.order.length,source_files:seen.size}));
  const before = pins(seen), started = performance.now();
  // Observe the second visit to each original order entry (book_valid's real
  // check pass, after its readonly last-occurrence scan). Values/order and all
  // declarations remain identical; this only names a normalization failure.
  const originalInputOrder = book.order;
  const orderReads = new Map();
  book.order = new Proxy(originalInputOrder, {get(target,key,receiver) {
    const value = Reflect.get(target,key,receiver);
    if (typeof key === "string" && /^\d+$/.test(key)) {
      const reads = (orderReads.get(key) ?? 0) + 1;
      orderReads.set(key,reads);
      if (reads === 2 && typeof value === "string" && value.includes("local_player_cooking_incarnation_guard"))
        console.log(JSON.stringify({phase:"checking-original-declaration",name:value}));
    }
    return value;
  }});
  B.book_valid(book);
  book.order = originalInputOrder;
  const ordinarySeconds = (performance.now() - started) / 1000;
  if (book.hols !== 0) throw Error("Open proof holes");
  const originalOrder = [...book.order], originalTlds = book.tlds, originalCtrs = book.ctrs, originalTmps = book.tmps;
  const originals = Object.entries(book.tlds).map(([name,t]) => [name,t,t.T,t.$ === "Def" ? t.v : null,t.$ === "Def" ? t.e : null]);
  const termPins = roots.map(name => {
    const term = book.tlds[name];
    if (term?.$ !== "Def" || !term.e || !term.v || term.u || term.i) throw Error("Missing checked pure original root " + name);
    return {name,type_sha256:sha(B.term_key(B.term_lower(term.T))),
      checked_proof_sha256:sha(B.term_key(term.e)),source_body_sha256:sha(B.term_key(B.term_lower(term.v)))};
  });
  book.order = originalOrder.filter((name,index) => roots.includes(name) && originalOrder.lastIndexOf(name) === index);
  if (book.order.length !== roots.length || book.tlds !== originalTlds || book.ctrs !== originalCtrs || book.tmps !== originalTmps)
    throw Error("Selection changed original declaration maps");
  for (const [name,t,T,v,e] of originals)
    if (book.tlds[name] !== t || t.T !== T || (t.$ === "Def" && (t.v !== v || t.e !== e)))
      throw Error("Selection altered original checked term " + name);
  const selection = {entry,test,roots,selected_root_count:roots.length,original_root_count:originalOrder.length,
    ordinary_source_api_check_passed:true,ordinary_seconds:ordinarySeconds,original_book_checks:1,
    checked_types_and_bodies_unchanged:true,all_original_tlds_ctrs_tmps_retained:true,term_pins:termPins};
  fs.writeFileSync(dir + "/selection.json",JSON.stringify(selection,null,2) + "\n");
  const checkedPins = pins(seen);
  if (JSON.stringify(before) !== JSON.stringify(checkedPins)) throw Error("Source changed during original check");
  fs.writeFileSync(dir + "/source-pins.json",JSON.stringify(checkedPins,null,2) + "\n");
  console.log(JSON.stringify({phase:"original-book-checked",roots:roots.length,ordinary_seconds:ordinarySeconds}));
  const exportStarted = performance.now();
  const exclusions = Safe.safe_emit(book,dir + "/selected.bendtt");
  fs.writeFileSync(dir + "/scope.json",JSON.stringify({exclusions,export_seconds:(performance.now()-exportStarted)/1000},null,2) + "\n");
  const after = pins(seen);
  if (JSON.stringify(before) !== JSON.stringify(after)) throw Error("Source changed during original check/export");
  fs.writeFileSync(dir + "/source-pins.json",JSON.stringify(after,null,2) + "\n");
  if (exclusions.length) throw Error("Selected pure roots were excluded from export");
  console.log(JSON.stringify({phase:"export-complete",bytes:fs.statSync(dir + "/selected.bendtt").size}));
} catch (error) {
  console.error(error?.$ === "Err" ? B.err_show(error) : error?.stack ?? String(error));
  process.exitCode = 1;
}
