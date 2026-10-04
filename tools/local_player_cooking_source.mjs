import * as B from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/bend.ts";
import * as fs from "node:fs";
import * as crypto from "node:crypto";

const directory = process.argv[2];
if (!directory) throw Error("Fresh output directory required");
const diagnostic = process.argv.slice(3).includes("--diagnose");
const scene = process.argv.slice(3).includes("--scene");
const entry = new URL(scene ? "../src/local_player_scene.bend" : "../remote_resource_server.bend", import.meta.url).pathname;
const sha = bytes => crypto.createHash("sha256").update(bytes).digest("hex");
const book = B.book_nil(), seen = new Map();
try {
  await B.book_load(book, entry, "", seen);
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
    order_progress_observation: diagnostic,
    kernel_or_native_claim: false,
    scope: "Original compiler book_valid checks the complete actual " + (scene ? "Scene" : "Entry") + " and " +
      "its cooking/runtime/storage imports. Native/foreign IO boundaries are " +
      "typed here; this is neither an independent-kernel nor native execution verdict."};
  fs.writeFileSync(directory + "/source.json", JSON.stringify(result, null, 2) + "\n");
  console.log(JSON.stringify({status: result.status, declarations: result.declarations,
    holes: result.holes, source_files: sources.length}));
} catch (error) {
  console.error(error?.$ === "Err" ? B.err_show(error) : String(error));
  process.exitCode = 1;
}
