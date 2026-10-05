// Focused receiver through the already verified memory-bounded retained-closure
// producer. The original ordinary checker still checks every loaded declaration.
import * as B from 'file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/bend.ts';
import * as Comp from 'file:///Users/chuah/Documents/ChatGPT/bendex/minecraft/build/actor-compiler-memory-001/comp_instrumented.ts';
import * as fs from 'node:fs';
import * as crypto from 'node:crypto';
const sha = path => crypto.createHash('sha256').update(fs.readFileSync(path)).digest('hex');
try {
  const [entry,out] = process.argv.slice(2);
  if (!entry || !out) throw Error('Expected focused entry and C output');
  const basis = '/Users/chuah/Documents/ChatGPT/bendex/minecraft/evidence/actor-compiler-memory-001.json';
  const proof = JSON.parse(fs.readFileSync(basis,'utf8'));
  if (proof.verification.status !== 'PASS' || proof.verification.exact_C_equal_graphs !== 9 ||
      proof.verification.native_independent_expected_outputs !== 9 || proof.verification.C_equal_under_GC !== true)
    throw Error('Verified producer basis changed');
  for (const row of [...proof.candidate_files,proof.private_compiler,proof.original_checker,proof.original_compiler])
    if (sha(row.path) !== row.sha256) throw Error('Producer basis changed: '+row.path);
  const book = B.book_nil(), seen = new Map();
  await B.book_load(book,entry,'',seen);
  const files = new Set(seen.keys());
  for (const d of Object.values(book.tlds)) for (const p of d.i ?? [])
    if (fs.existsSync(p)) files.add(fs.realpathSync(p));
  const pins = () => Object.fromEntries([...files].sort().map(p => [p,sha(p)]));
  const before = pins();
  fs.writeFileSync(out+'.loaded-sources.json',JSON.stringify(before,null,2)+'\n');
  console.log(JSON.stringify({phase:'loaded',files:files.size,declarations:Object.keys(book.tlds).length,memory:process.memoryUsage()}));
  B.book_valid(book);
  if (book.hols !== 0) throw Error('Open checked holes');
  console.log(JSON.stringify({phase:'checked-original-book',memory:process.memoryUsage()}));
  if (typeof globalThis.gc !== 'function') throw Error('Verified producer GC unavailable');
  globalThis.gc();
  const emitted = Comp.compile_book(book);
  const after = pins();
  if (JSON.stringify(before) !== JSON.stringify(after)) throw Error('Source changed during compile');
  fs.writeFileSync(out,emitted);
  fs.writeFileSync(out+'.sources.json',JSON.stringify({entry,source_sha256:after,complete_original_checker:true,
    producer_basis:{path:basis,sha256:sha(basis)},private_compiler:proof.private_compiler,
    original_checker:proof.original_checker,original_compiler:proof.original_compiler},null,2)+'\n');
  console.log(JSON.stringify({phase:'complete',bytes:Buffer.byteLength(emitted),memory:process.memoryUsage()}));
} catch (error) {
  console.error(error?.$ === 'Err' ? B.err_show(error) : error);
  process.exitCode = 1;
}
