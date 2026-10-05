import * as B from "file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/bend.ts";
import * as fs from "node:fs";
import * as crypto from "node:crypto";
import * as path from "node:path";

const directory = process.argv[2];
if (!directory) throw Error("Fresh output directory required");
const entry = path.resolve(process.argv[3] || "src/remote_resource_transport.bend");
const sha = value => crypto.createHash("sha256").update(value).digest("hex");
const book = B.book_nil(), seen = new Map();
const started = performance.now();
try {
  await B.book_load(book,entry,"",seen);
  const sources = [...seen.keys()].sort().map(file => ({path:file,
    bytes:fs.statSync(file).size,sha256:sha(fs.readFileSync(file))}));
  const original_order = book.order, order = [...original_order];
  const declarations = Object.keys(book.tlds), checked = new Set();
  let reads = 0, last_gc = performance.now();
  // The original checker makes one indexing pass to declare every event, then
  // checks that complete original order. Observe it without skipping entries.
  book.order = new Proxy(original_order,{get(target,key,receiver) {
    if (typeof key === "string" && /^\d+$/.test(key)) {
      const index = Number(key);
      if (reads >= order.length) {
        checked.add(index);
        if (index % 32 === 0 || String(target[index]).includes("remote_entity"))
          console.log(JSON.stringify({phase:"check_progress",index,name:target[index],memory:process.memoryUsage()}));
        if (globalThis.gc && process.memoryUsage().heapUsed > 3221225472 &&
            performance.now() - last_gc > 1500) {
          globalThis.gc(); last_gc = performance.now();
        }
      }
      reads++;
    }
    return Reflect.get(target,key,receiver);
  }});
  try { B.book_valid(book); } finally { book.order = original_order; }
  if (book.hols !== 0) throw Error("Open source holes");
  if (checked.size !== order.length || book.order.length !== order.length ||
      book.order.some((value,i)=>value!==order[i]) || declarations.some(name=>!book.tlds[name]))
    throw Error("Original declarations/order incomplete or changed");
  for (const source of sources)
    if (sha(fs.readFileSync(source.path))!==source.sha256)
      throw Error("Source changed during check: "+source.path);
  const receipt = {status:"source_checked",entry,seconds:(performance.now()-started)/1000,
    declarations:Object.keys(book.tlds).length,events_checked:checked.size,holes:book.hols,source_files:sources,
    original_book_checked:true,declaration_selection:false,kernel_or_native_claim:false,
    scope:"Complete original transport/capture graph checked by original compiler book_valid; foreign IO boundaries are typed, not independently proved or executed."};
  fs.writeFileSync(path.join(directory,"source.json"),JSON.stringify(receipt,null,2)+"\n");
  console.log(JSON.stringify({status:receipt.status,seconds:receipt.seconds,
    declarations:receipt.declarations,holes:receipt.holes,source_files:sources.length}));
} catch (error) {
  console.error(error?.$ === "Err" ? B.err_show(error) : String(error));
  process.exitCode = 1;
}
