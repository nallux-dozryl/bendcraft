import * as B from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/bend.ts";
import * as Safe from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/safe.ts";
import * as fs from "node:fs";
import * as path from "node:path";
import * as crypto from "node:crypto";

// Select already checked actual WM/M composition roots without changing any
// source term, declaration ownership, arithmetic implementation, or compiler.
const root = path.resolve(new URL("..", import.meta.url).pathname);
const prepared = path.resolve(process.argv[2] ?? "");
const output = path.resolve(process.argv[3] ?? "");
if (path.dirname(prepared) !== root + "/build" ||
    !path.basename(prepared).startsWith("mesh-layer-order-") ||
    !process.argv[3] || path.dirname(output) !== root + "/build" ||
    !path.basename(output).startsWith("mesh-layer-order-") || fs.existsSync(output)) {
  throw Error("Prepared private source directory and fresh proof output directory required");
}
const sha = value => crypto.createHash("sha256").update(value).digest("hex");
const manifest = JSON.parse(fs.readFileSync(prepared + "/manifest.json", "utf8"));
for (const [name, expected] of Object.entries(manifest.sources)) {
  if (sha(fs.readFileSync(root + "/" + name)) !== expected) throw Error("Preparation source changed: " + name);
}
for (const [name, expected] of Object.entries(manifest.outputs)) {
  if (sha(fs.readFileSync(prepared + "/" + name)) !== expected.sha256) throw Error("Prepared source changed: " + name);
}
const roots = manifest.law_roots.map(name => "mesh_layer_order_laws:" + name);
if (!roots.length || new Set(roots).size !== roots.length) throw Error("Missing or repeated actual composition roots");
const entry = prepared + "/mesh_layer_order_proof.bend";
const book = B.book_nil(), seen = new Map();
await B.book_load(book, entry, "", seen);
const pins = () => Object.fromEntries([...seen.keys()].sort().map(file => [file, sha(fs.readFileSync(file))]));
const before = pins();
B.book_valid(book);
if (book.hols !== 0) throw Error("Open proof holes");
const originalOrder = [...book.order], originalTlds = book.tlds,
  originalCtrs = book.ctrs, originalTmps = book.tmps;
const originals = Object.entries(book.tlds).map(([name, term]) =>
  [name, term, term.T, term.$ === "Def" ? term.v : null, term.$ === "Def" ? term.e : null]);
const termPins = roots.map(name => {
  const term = book.tlds[name];
  if (term?.$ !== "Def" || !term.e || !term.v || term.u || term.i) throw Error("Missing checked pure proof " + name);
  return {name, type_sha256: sha(B.term_key(B.term_lower(term.T))),
    checked_proof_sha256: sha(B.term_key(term.e)), source_body_sha256: sha(B.term_key(B.term_lower(term.v)))};
});
book.order = originalOrder.filter((name, index) => roots.includes(name) && originalOrder.lastIndexOf(name) === index);
if (book.order.length !== roots.length || book.tlds !== originalTlds ||
    book.ctrs !== originalCtrs || book.tmps !== originalTmps) throw Error("Selection changed declaration ownership");
for (const [name, term, T, v, e] of originals) {
  if (book.tlds[name] !== term || term.T !== T || (term.$ === "Def" && (term.v !== v || term.e !== e))) {
    throw Error("Selection altered term " + name);
  }
}
fs.mkdirSync(output, {recursive: false});
fs.writeFileSync(output + "/selection.json", JSON.stringify({entry, roots,
  original_root_count: originalOrder.length, selected_root_count: book.order.length,
  checked_types_and_bodies_unchanged: true, all_original_tlds_ctrs_tmps_retained: true,
  term_pins: termPins, source_files: [...seen.keys()], ordinary_source_api_check_passed: true}, null, 2) + "\n");
const exclusions = Safe.safe_emit(book, output + "/selected.bendtt");
fs.writeFileSync(output + "/scope.json", JSON.stringify({exclusions}, null, 2) + "\n");
const after = pins();
if (JSON.stringify(before) !== JSON.stringify(after)) throw Error("Proof source changed during check/export");
fs.writeFileSync(output + "/source-pins.json", JSON.stringify(after, null, 2) + "\n");
console.log(JSON.stringify({phase: "export-complete", roots: roots.length,
  bytes: fs.statSync(output + "/selected.bendtt").size, exclusions}));
if (exclusions.length) process.exitCode = 2;
