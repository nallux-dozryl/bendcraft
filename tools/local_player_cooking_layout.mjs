// Read-only use of the original native compiler's layout functions. This does
// not check, emit, optimize, or claim the generated callback segment arities.
import * as B from 'file:///Users/chuah/Documents/ChatGPT/bendex/bend/bend2/bend.ts';
import * as fs from 'node:fs';
import * as crypto from 'node:crypto';
import * as path from 'node:path';
const output = process.argv[2];
if (!output) throw Error('Fresh diagnostic directory required');
process.on('uncaughtException', error => {
  const message = error?.$ === 'Err' ? B.err_show(error) : String(error);
  fs.writeFileSync(path.join(output,'failure.json'),JSON.stringify({status:'failed',message,scope:'Read-only layout observation, no checker or emitter.'},null,2)+'\n');
  console.error(message);
  process.exit(1);
});
const root = path.resolve(new URL('..', import.meta.url).pathname);
const compiler = path.resolve(root, '../bend/bend2/comp.ts');
const sha = value => crypto.createHash('sha256').update(value).digest('hex');
const original = fs.readFileSync(compiler, 'utf8');
const body = original.replace('import * as Bend from "./bend.ts";',
  'import * as Bend from "file://' + path.resolve(root, '../bend/bend2/bend.ts') + '";');
if (body === original) throw Error('Expected original compiler import');
const addition = `
export function owner_layout_probe(book: Bend.Book) {
  [TELES, LAYS, FUNS].forEach(m => m.clear());
  const names = Object.keys(book.tlds).filter(k => /:(Sidecar|Shell|State|Transient)$/.test(k)
    && /src\\/(local_player_cooking|local_player_session|local_player_runtime):/.test(k));
  const layouts = names.map(k => ({name:k, words:lay_of(book,Bend.ADT(k,[])).ks.length,
    kinds:lay_of(book,Bend.ADT(k,[])).ks}));
  const functions = Object.keys(book.tlds).filter(k => book.tlds[k].$ === "Def"
    && /src\\/local_player_session:(cooking_query|cooking_returned|cooking_detached|cooking_inventory_query|to_bundle|from_bundle|cooking_step)$/.test(k)).map(k => {
      const f = fun_of({book} as File,k);
      return {name:k, live_parameters:f.live.length,
        original_parameter_words:f.live.map(d => lay_of(book,d[2]).ks.length).reduce((a,b)=>a+b,0),
        compiler_function_parameter_words:f.lays.map(l => l.ks.length).reduce((a,b)=>a+b,0)};
    }).sort((a,b)=>b.original_parameter_words-a.original_parameter_words || a.name.localeCompare(b.name));
  return {layouts, widest_declared_functions:functions.slice(0,20)};
}
`;
const privatePath = path.join(output,'layout_comp.ts');
fs.writeFileSync(privatePath,body + addition);
const C = await import('file://' + privatePath);
const variants = [
  {generation:18,entry:path.join(root,'build/compiler-producer-diagnostic-018/source/remote_resource_server.bend')},
  {generation:19,entry:path.join(root,'remote_resource_server.bend')}
];
for (const variant of variants) {
  const book = B.book_nil(), seen = new Map();
  await B.book_load(book,variant.entry,'',seen);
  variant.source_files = [...seen.keys()].sort().map(p=>({path:p,sha256:sha(fs.readFileSync(p))}));
  variant.declarations = Object.keys(book.tlds).length;
  Object.assign(variant,C.owner_layout_probe(book));
  fs.writeFileSync(path.join(output,'layout-'+variant.generation+'.json'),JSON.stringify(variant,null,2)+'\n');
  for (const row of variant.source_files)
    if (sha(fs.readFileSync(row.path)) !== row.sha256) throw Error('Source changed: '+row.path);
}
if (sha(fs.readFileSync(compiler)) !== sha(original)) throw Error('Original compiler changed');
const result = {status:'read_only_native_layout_observed', compiler:{path:compiler,sha256:sha(original)},
  checker_called:false,emitter_called:false,original_compiler_modified:false,
  private_copy:{path:privatePath,sha256:sha(fs.readFileSync(privatePath))}, variants,
  scope:'Original lay_of and fun_of only. The failure guard checks emitted segments and raised captures too; this observation is not a native build verdict or an identification of the failed 018 segment.'};
fs.writeFileSync(path.join(output,'layout.json'),JSON.stringify(result,null,2)+'\n');
fs.writeFileSync(path.join(root,'evidence/local-player-cooking-layout-019.json'),JSON.stringify(result,null,2)+'\n');
console.log(JSON.stringify({status:result.status,variants:variants.map(v=>({generation:v.generation,layouts:v.layouts,widest:v.widest_declared_functions[0]}))}));
