import * as B from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/bend.ts";
import * as Safe from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/safe.ts";
import * as fs from "node:fs";
import * as path from "node:path";
import * as crypto from "node:crypto";
import { fileURLToPath } from "node:url";

// Check the original complete book once. Export selects only its actual laws;
// all original declarations, types, source bodies and checked bodies remain.
const sourceRoot = fileURLToPath(new URL("../src/", import.meta.url));
const entry = path.join(sourceRoot, "entity_membership_codec_proof.bend");
const laws = path.join(sourceRoot, "entity_membership_codec_laws.bend");
const namespace = "entity_membership_codec_laws:";
const expectedRoots = Object.freeze([
  "box_words_preserve_every_endpoint",
  "uuid_words_preserve_complete_identity",
  "packed_key_words_are_lossless",
  "closed_visibility_projection_is_lossless",
  "inspect_save_retains_complete_manager_and_actual_encoding",
].map(name => namespace + name));
const requiredSources = [entry, laws, ...[
  "entity_membership_codec", "entity_section_membership_model", "entity_section_membership",
].map(name => path.join(sourceRoot, name + ".bend"))];
const checker = fileURLToPath(new URL("file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/bend.ts"));
const exporter = fileURLToPath(new URL("file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/safe.ts"));
const toolFiles = [fileURLToPath(import.meta.url), checker, exporter, fs.realpathSync(process.execPath)];
const sha = value => crypto.createHash("sha256").update(value).digest("hex");
const same = (left, right) => JSON.stringify(left) === JSON.stringify(right);
const pin = file => {
  const bytes = fs.readFileSync(file);
  return { path: file, bytes: bytes.length, sha256: sha(bytes) };
};
const pins = files => [...new Set(files)].sort().map(pin);
const write = (directory, name, value) => fs.writeFileSync(path.join(directory, name),
  JSON.stringify(value, null, 2) + "\n", { flag: "wx" });
const termPin = (name, term) => ({
  name,
  type_sha256: sha(B.term_key(B.term_lower(term.T))),
  source_body_sha256: sha(B.term_key(B.term_lower(term.v))),
  checked_body_sha256: sha(B.term_key(term.e)),
});
const scope = "Five actual laws for lossless raw AABB, UUID, packed-key and closed-visibility projections, " +
  "and complete M.State inspect-return encoding under arbitrary limits and Views. " +
  "Physical NBT roundtrip, structural admission, current loader authority, durable IO and scene atomicity are not asserted by these five laws.";

let directory, phase = "arguments", sourcePassed = false;
try {
  if (process.argv.length !== 3 || !process.argv[2]) throw Error("Fresh output directory required");
  directory = path.resolve(process.argv[2]);
  if (!fs.statSync(directory).isDirectory()) throw Error("Output directory does not exist");
  for (const name of ["loaded-source-pins.json", "source-proof.json", "source-proof.json.exported", "membership.bendtt",
    "export.json", "export-failure.json"])
    if (fs.existsSync(path.join(directory, name))) throw Error("Output already exists: " + name);

  const book = B.book_nil(), seen = new Map();
  phase = "load-original-complete-book";
  await B.book_load(book, entry, "", seen, undefined, sourceRoot);
  for (const file of requiredSources)
    if (!seen.has(fs.realpathSync(file))) throw Error("Actual production source not loaded: " + file);
  if (!seen.has(B.BASE_BEND)) throw Error("Actual compiler Base not loaded");
  const sourceFiles = [...seen.keys()].sort();
  const sourcesBefore = pins(sourceFiles), toolsBefore = pins(toolFiles);
  write(directory, "loaded-source-pins.json", {
    source_files: sourcesBefore, verification_tools: toolsBefore,
  });

  const declared = [...fs.readFileSync(laws, "utf8").matchAll(/^law\s+([A-Za-z_][\w.]*)\s*:/gm)]
    .map(match => namespace + match[1]);
  if (expectedRoots.length !== 5 || new Set(expectedRoots).size !== 5 ||
      declared.length !== 5 || new Set(declared).size !== 5 ||
      !same([...declared].sort(), [...expectedRoots].sort()))
    throw Error("Expected exactly the five original membership codec law declarations");
  for (const name of expectedRoots)
    if (book.tlds[name]?.$ !== "Def") throw Error("Actual law has no original declaration: " + name);

  phase = "check-original-complete-book";
  const checkStarted = performance.now();
  B.book_valid(book);
  const checkSeconds = (performance.now() - checkStarted) / 1000;
  if (book.hols !== 0) throw Error("Open source holes: " + book.hols);
  if (!same(sourcesBefore, pins(sourceFiles)) || !same(toolsBefore, pins(toolFiles)))
    throw Error("Original source or verification tools changed during checking");

  const originalOrder = [...book.order], maps = [book.tlds, book.ctrs, book.tmps];
  const declarations = Object.entries(book.tlds).map(([name, term]) =>
    [name, term, term.T, term.$ === "Def" ? term.v : null, term.$ === "Def" ? term.e : null]);
  const constructors = Object.entries(book.ctrs).map(([name, value]) => [name, value, value.T]);
  const templates = Object.entries(book.tmps).map(([name, value]) => [name, value, [...value.entries()]]);
  const roots = originalOrder.filter((name, index) =>
    expectedRoots.includes(name) && originalOrder.lastIndexOf(name) === index);
  if (roots.length !== 5 || !same([...roots].sort(), [...expectedRoots].sort()))
    throw Error("Not every actual law is an original checked root");
  const terms = roots.map(name => {
    const term = book.tlds[name];
    if (term?.$ !== "Def" || term.u || term.i || term.b || !term.v || !term.e)
      throw Error("Missing pure checked membership codec law: " + name);
    return termPin(name, term);
  });

  const assertUnchanged = () => {
    if (!same(book.order, roots) || book.hols !== 0)
      throw Error("Selection/export changed actual checked root order or proof holes");
    if (book.tlds !== maps[0] || book.ctrs !== maps[1] || book.tmps !== maps[2])
      throw Error("Selection/export changed original declaration map owners");
    if (Object.keys(book.tlds).length !== declarations.length ||
        Object.keys(book.ctrs).length !== constructors.length ||
        Object.keys(book.tmps).length !== templates.length)
      throw Error("Selection/export changed original declaration map contents");
    for (const [name, term, type, body, checked] of declarations)
      if (book.tlds[name] !== term || term.T !== type ||
          (term.$ === "Def" && (term.v !== body || term.e !== checked)))
        throw Error("Selection/export altered original declaration: " + name);
    for (const [name, value, type] of constructors)
      if (book.ctrs[name] !== value || value.T !== type)
        throw Error("Selection/export altered original constructor: " + name);
    for (const [name, value, entries] of templates)
      if (book.tmps[name] !== value || !same([...value.entries()], entries))
        throw Error("Selection/export altered original template: " + name);
    if (!same(terms, roots.map(name => termPin(name, book.tlds[name]))))
      throw Error("Selection/export changed a theorem's exact type or body");
    if (!same(sourcesBefore, pins(sourceFiles)) || !same(toolsBefore, pins(toolFiles)))
      throw Error("Original source or verification tools changed during selection/export");
  };

  phase = "select-five-actual-checked-roots";
  book.order = [...roots];
  assertUnchanged();
  // Record the complete source verdict before Safe. A successful export adds
  // its zero-exclusion result atomically; an export throw leaves this PASS.
  const sourceReceipt = {
    status: "source_checked", source_status: "PASS", entry, laws, roots,
    declared_law_roots: declared, selected_root_count: roots.length,
    original_root_count: originalOrder.length, declarations: declarations.length,
    constructor_count: constructors.length, template_count: templates.length,
    holes: book.hols, original_book_loads: 1, original_book_checks: 1,
    ordinary_source_api_check_passed: true, ordinary_seconds: checkSeconds,
    checked_types_and_bodies_unchanged: true, all_original_declaration_maps_retained: true,
    root_selection_only_changes_order: true, term_pins: terms,
    source_files: sourcesBefore, verification_tools: toolsBefore, base_source: B.BASE_BEND,
    required_production_sources: requiredSources.map(file => fs.realpathSync(file)),
    export_status: "PENDING", exclusions: null,
    export_receipt: path.join(directory, "export.json"), scope,
  };
  write(directory, "source-proof.json", sourceReceipt);
  sourcePassed = true;
  console.log(JSON.stringify({ phase: "original-complete-source-pass", roots: roots.length,
    holes: book.hols, ordinary_seconds: checkSeconds }));

  phase = "safe-export-complete-checked-root-closure";
  const exportStarted = performance.now();
  const artifact = path.join(directory, "membership.bendtt");
  const exclusions = Safe.safe_emit(book, artifact);
  const exportSeconds = (performance.now() - exportStarted) / 1000;
  phase = "verify-export-preserved-original-book";
  assertUnchanged();
  if (!Array.isArray(exclusions) || exclusions.length !== 0)
    throw Error("Membership codec law exclusions: " + JSON.stringify(exclusions));
  const artifactPin = pin(artifact);
  if (!artifactPin.bytes) throw Error("Empty membership codec Safe artifact");
  phase = "record-successful-zero-exclusion-export";
  write(directory, "source-proof.json.exported", {
    ...sourceReceipt, export_status: "PASS", exclusions, export_seconds: exportSeconds,
    safe_artifact: artifactPin,
  });
  fs.renameSync(path.join(directory, "source-proof.json.exported"), path.join(directory, "source-proof.json"));
  write(directory, "export.json", {
    status: "exported", export_status: "PASS", roots, exclusions,
    export_seconds: exportSeconds, artifact: artifactPin,
    source_proof: pin(path.join(directory, "source-proof.json")),
    checked_types_and_bodies_unchanged: true, all_original_declaration_maps_retained: true,
    source_files: sourcesBefore, verification_tools: toolsBefore,
    kernel_status: "NOT_RUN", scope,
  });
  console.log(JSON.stringify({ status: "source_checked", export_status: "PASS", roots: roots.length,
    holes: book.hols, exclusions: 0, artifact: artifactPin.path, bytes: artifactPin.bytes,
    export_seconds: exportSeconds }));
} catch (error) {
  let rendered;
  try { rendered = error?.$ === "Err" ? B.err_show(error) : error?.stack ?? String(error); }
  catch { rendered = String(error); }
  const compact = rendered.slice(0, 12000);
  if (directory && fs.existsSync(directory) && fs.statSync(directory).isDirectory() &&
      !fs.existsSync(path.join(directory, "export-failure.json"))) {
    const artifact = path.join(directory, "membership.bendtt");
    write(directory, "export-failure.json", {
      status: "failed", phase, source_status: sourcePassed ? "PASS" : "NOT_COMPLETED",
      source_proof_preserved: sourcePassed && fs.existsSync(path.join(directory, "source-proof.json")),
      source_proof: sourcePassed ? pin(path.join(directory, "source-proof.json")) : null,
      partial_export_exists: fs.existsSync(artifact),
      partial_export_bytes: fs.existsSync(artifact) ? fs.statSync(artifact).size : 0,
      error: compact, error_sha256: sha(rendered), error_truncated: compact.length !== rendered.length,
    });
  }
  console.error(compact);
  process.exitCode = 1;
}
