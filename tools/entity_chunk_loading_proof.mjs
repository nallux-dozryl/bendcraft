import * as B from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/bend.ts";
import * as Safe from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/safe.ts";
import * as fs from "node:fs";
import * as path from "node:path";
import * as crypto from "node:crypto";
import { fileURLToPath } from "node:url";

// The original production book is loaded and checked once. Selecting kernel
// roots changes only order; no implementation, type, statement or proof is
// substituted, reduced to a test model, or removed from its declaration maps.
const entry = fileURLToPath(new URL("../src/entity_chunk_loading_proof.bend", import.meta.url));
const laws = fileURLToPath(new URL("../src/entity_chunk_loading_laws.bend", import.meta.url));
const sourceRoot = fileURLToPath(new URL("../src/", import.meta.url));
const namespace = "entity_chunk_loading_laws:";
const requiredSources = [entry, laws, ...["entity_chunk_loading", "entity_chunk_loading_model", "entity_chunk_loading_math", "entity_chunk_loading_tickets"]
  .map(name => path.join(sourceRoot, name + ".bend"))];
const sha = value => crypto.createHash("sha256").update(value).digest("hex");
const pins = seen => Object.fromEntries([...seen.keys()].sort().map(file => [file, sha(fs.readFileSync(file))]));
const same = (left, right) => JSON.stringify(left) === JSON.stringify(right);
const write = (directory, name, value) => fs.writeFileSync(path.join(directory, name),
  JSON.stringify(value, null, 2) + "\n", { flag: "wx" });
const termPin = (name, term) => ({
  name,
  type_sha256: sha(B.term_key(B.term_lower(term.T))),
  source_body_sha256: sha(B.term_key(B.term_lower(term.v))),
  checked_proof_sha256: sha(B.term_key(term.e)),
});

let directory, phase = "arguments";
try {
  if (process.argv.length !== 3 || !process.argv[2]) throw Error("Fresh output directory required");
  directory = path.resolve(process.argv[2]);
  if (!fs.statSync(directory).isDirectory()) throw Error("Output directory does not exist");
  for (const name of ["selection.json", "scope.json", "selected.bendtt", "source-pins.json",
    "loaded-source-pins.json", "export-failure.json"])
    if (fs.existsSync(path.join(directory, name))) throw Error("Output already exists: " + name);

  const book = B.book_nil(), seen = new Map();
  phase = "load-original-production-book";
  await B.book_load(book, entry, "", seen, undefined, sourceRoot);
  for (const file of requiredSources)
    if (!seen.has(fs.realpathSync(file))) throw Error("Actual production source not loaded: " + file);
  if (!seen.has(B.BASE_BEND)) throw Error("Actual compiler Base not loaded");
  const before = pins(seen);
  write(directory, "loaded-source-pins.json", before);
  console.log(JSON.stringify({ phase, source_files: seen.size, declarations: Object.keys(book.tlds).length }));

  // A laws module can also contain observation helpers. Only actual `law`
  // declarations become roots; their checked definitions may live in PROOF.
  const declared = [...fs.readFileSync(laws, "utf8").matchAll(/^law\s+([A-Za-z_][\w.]*)\s*:/gm)]
    .map(match => namespace + match[1]);
  if (!declared.length || new Set(declared).size !== declared.length)
    throw Error("Expected unique source law declarations");
  for (const name of declared)
    if (book.tlds[name]?.$ !== "Def") throw Error("Source law has no original declaration: " + name);

  phase = "check-original-production-book";
  const checkStarted = performance.now();
  B.book_valid(book);
  const ordinarySeconds = (performance.now() - checkStarted) / 1000;
  if (book.hols !== 0) throw Error("Open proof holes: " + book.hols);
  if (!same(before, pins(seen))) throw Error("Production source changed during original checking");

  const order = [...book.order], maps = [book.tlds, book.ctrs, book.tmps];
  const declarations = Object.entries(book.tlds).map(([name, term]) =>
    [name, term, term.T, term.$ === "Def" ? term.v : null, term.$ === "Def" ? term.e : null]);
  const constructorEntries = Object.entries(book.ctrs).map(([name, value]) => [name, value, value.T]);
  const templateEntries = Object.entries(book.tmps).map(([name, value]) => [name, value, [...value.entries()]]);
  const roots = order.filter((name, index) => declared.includes(name) && order.lastIndexOf(name) === index);
  if (roots.length !== declared.length) throw Error("Not every source law is an original checked root");
  const terms = roots.map(name => {
    const term = book.tlds[name];
    if (term?.$ !== "Def" || !term.v || !term.e || term.u || term.i || term.b)
      throw Error("Missing checked pure theorem root: " + name);
    return termPin(name, term);
  });

  const assertUnchanged = () => {
    if (!same(book.order, roots) || book.hols !== 0)
      throw Error("Selection/export changed checked root order or proof-hole count");
    if (book.tlds !== maps[0] || book.ctrs !== maps[1] || book.tmps !== maps[2])
      throw Error("Selection/export changed original declaration map ownership");
    if (Object.keys(book.tlds).length !== declarations.length ||
        Object.keys(book.ctrs).length !== constructorEntries.length ||
        Object.keys(book.tmps).length !== templateEntries.length)
      throw Error("Selection/export changed original declaration map contents");
    for (const [name, term, type, body, checked] of declarations)
      if (book.tlds[name] !== term || term.T !== type ||
          (term.$ === "Def" && (term.v !== body || term.e !== checked)))
        throw Error("Selection/export altered checked declaration: " + name);
    for (const [name, value, type] of constructorEntries)
      if (book.ctrs[name] !== value || value.T !== type)
        throw Error("Selection/export altered constructor: " + name);
    for (const [name, value, entries] of templateEntries)
      if (book.tmps[name] !== value || !same([...value.entries()], entries))
        throw Error("Selection/export altered template: " + name);
    if (!same(terms, roots.map(name => termPin(name, book.tlds[name]))))
      throw Error("Selection/export changed a theorem's exact type or body");
    if (!same(before, pins(seen))) throw Error("Production source changed during selection/export");
  };

  phase = "select-actual-checked-theorem-roots";
  book.order = [...roots];
  assertUnchanged();
  const selection = {
    entry, laws, roots, declared_law_roots: declared,
    selected_root_count: roots.length, original_root_count: order.length,
    original_declaration_count: declarations.length, holes: book.hols,
    original_book_loads: 1, original_book_checks: 1,
    ordinary_source_api_check_passed: true, ordinary_seconds: ordinarySeconds,
    checked_types_and_bodies_unchanged: true,
    all_original_tlds_ctrs_tmps_retained: true,
    root_selection_only_changes_order: true,
    term_pins: terms, source_files: [...seen.keys()].sort(), base_source: B.BASE_BEND,
    required_production_sources: requiredSources.map(file => fs.realpathSync(file)),
  };
  write(directory, "selection.json", selection);
  console.log(JSON.stringify({ phase: "original-book-checked", roots: roots.length,
    ordinary_seconds: ordinarySeconds, original_root_count: order.length }));

  phase = "export-complete-checked-root-closure";
  const exportStarted = performance.now();
  const exclusions = Safe.safe_emit(book, path.join(directory, "selected.bendtt"));
  const exportSeconds = (performance.now() - exportStarted) / 1000;
  write(directory, "scope.json", { exclusions, export_seconds: exportSeconds });
  assertUnchanged();
  write(directory, "source-pins.json", pins(seen));
  if (exclusions.length) throw Error("Actual theorem export has exclusions: " + JSON.stringify(exclusions));
  console.log(JSON.stringify({ phase: "export-complete", roots: roots.length,
    bytes: fs.statSync(path.join(directory, "selected.bendtt")).size, exclusions,
    export_seconds: exportSeconds }));
} catch (error) {
  const message = error?.$ === "Err" ? B.err_show(error) : error?.stack ?? String(error);
  if (directory && fs.existsSync(directory) && !fs.existsSync(path.join(directory, "export-failure.json")))
    write(directory, "export-failure.json", { status: "failed", phase, error: message });
  console.error(message);
  process.exitCode = 1;
}
