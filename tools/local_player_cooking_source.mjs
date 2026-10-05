import * as B from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/bend.ts";
import * as Safe from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/safe.ts";
import * as fs from "node:fs";
import * as crypto from "node:crypto";

const directory = process.argv[2];
if (!directory) throw Error("Fresh output directory required");
const diagnostic = process.argv.slice(3).includes("--diagnose");
const scene = process.argv.slice(3).includes("--scene");
const editProof = process.argv.slice(3).includes("--edit-proof");
if (editProof && (scene || diagnostic)) throw Error("Edit proof checks the complete actual Entry");
const entry = new URL(scene ? "../src/local_player_scene.bend" : "../remote_resource_server.bend", import.meta.url).pathname;
const proofEntry = new URL("../src/local_player_cooking_session_edit_proof.bend", import.meta.url).pathname;
const sourceRoot = new URL("../", import.meta.url).pathname;
const sha = bytes => crypto.createHash("sha256").update(bytes).digest("hex");
const book = B.book_nil(), seen = new Map();
try {
  await B.book_load(book, entry, "", seen);
  if (editProof)
    await B.book_load(book, proofEntry, "src/local_player_cooking_session_edit_proof", seen, undefined, sourceRoot);
  const sources = [...seen.keys()].sort().map(path => ({path,
    bytes: fs.statSync(path).size, sha256: sha(fs.readFileSync(path))}));
  if (diagnostic) {
    // Observe the original check's second order pass. The proxy returns each
    // original value unchanged; no declaration, type, body or order is edited.
    let pass = 0;
    const started = performance.now();
    book.order = new Proxy(book.order, {get(target, key, receiver) {
      const value = Reflect.get(target, key, receiver);
      if (key === "0") pass++;
      if (pass === 2 && typeof key === "string" && /^\d+$/.test(key))
        fs.appendFileSync(directory + "/progress.jsonl", JSON.stringify({
          index: Number(key), name: value, ms: performance.now() - started,
          heap: process.memoryUsage().heapUsed}) + "\n");
      return value;
    }});
  }
  B.book_valid(book);
  if (book.hols !== 0) throw Error("Open source holes");
  for (const source of sources)
    if (sha(fs.readFileSync(source.path)) !== source.sha256)
      throw Error("Source changed during check: " + source.path);
  const result = {status: "source_checked", entry, source_files: sources,
    declarations: Object.keys(book.tlds).length, holes: book.hols,
    original_book_checked: true, declaration_selection: false,
    additional_entries: editProof ? [proofEntry] : [],
    order_progress_observation: diagnostic,
    kernel_or_native_claim: false,
    scope: "Original compiler book_valid checks the complete actual " + (scene ? "Scene" : "Entry") + " and " +
      "its cooking/runtime/storage imports. Native/foreign IO boundaries are " +
      "typed here; this is neither an independent-kernel nor native execution verdict."};
  fs.writeFileSync(directory + "/source.json", JSON.stringify(result, null, 2) + "\n");
  console.log(JSON.stringify({status: result.status, declarations: result.declarations,
    holes: result.holes, source_files: sources.length}));
  if (editProof) {
    const root = "src/local_player_cooking_session_edit_laws:block_action_result_installs_returned_owners_and_retains_complete_session";
    const publicRoot = "src/local_player_cooking_session_edit_laws:block_action_publishes_actual_returned_owners_and_retains_complete_session";
    const originalOrder = [...book.order], maps = [book.tlds,book.ctrs,book.tmps];
    const declarations = Object.entries(book.tlds).map(([name,t]) => [name,t,t.T,t.$ === "Def" ? t.v : null,t.$ === "Def" ? t.e : null]);
    const pins = [root,publicRoot].map(name => {
      const t = book.tlds[name];
      if (t?.$ !== "Def" || t.u || t.i || !t.e || !t.v) throw Error("Missing checked pure owner law " + name);
      return {name,type_sha256:sha(B.term_key(B.term_lower(t.T))),
        source_body_sha256:sha(B.term_key(B.term_lower(t.v))),checked_body_sha256:sha(B.term_key(t.e))};
    });
    book.order = originalOrder.filter((name,index) => name === root && originalOrder.lastIndexOf(name) === index);
    if (book.order.length !== 1 || book.tlds !== maps[0] || book.ctrs !== maps[1] || book.tmps !== maps[2])
      throw Error("Export selection changed declaration owners");
    for (const [name,t,T,v,e] of declarations)
      if (book.tlds[name] !== t || t.T !== T || (t.$ === "Def" && (t.v !== v || t.e !== e)))
        throw Error("Export selection changed checked declaration " + name);
    const started = performance.now();
    const exclusions = Safe.safe_emit(book,directory + "/edit-session.bendtt");
    for (const source of sources)
      if (sha(fs.readFileSync(source.path)) !== source.sha256)
        throw Error("Source changed during proof export: " + source.path);
    fs.writeFileSync(directory + "/edit-proof.json",JSON.stringify({
      roots:[root],ordinary_roots:[root,publicRoot],exclusions,
      original_book_checks:1,checked_types_and_bodies_unchanged:true,
      all_original_declaration_maps_retained:true,term_pins:pins,
      export_seconds:(performance.now() - started)/1000,
      scope:"The independent export selects the actual Session block-action return continuation, preserving arbitrary returned Engine, Sidecar and Tables, inventory/player/lease/header/receiver/tails and either Outcome. The actual detached BI consumer law is ordinary checked with its complete live supplier premise; no BI ray, placement, edit admission, lifecycle, native or IO behavior theorem is claimed."},null,2) + "\n");
    if (exclusions.length) throw Error("Edit owner-law export exclusions: " + JSON.stringify(exclusions));
  }
} catch (error) {
  console.error(error?.$ === "Err" ? B.err_show(error) : String(error));
  process.exitCode = 1;
}
