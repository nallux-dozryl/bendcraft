#!/usr/bin/env python3
"""Prepare one read-only selected callback diagnostic of frozen actor021.

This reuses the retained Generic008 observer. It neither edits product/compiler
sources nor compiles the whole actor again. The actual complete Book is checked
in its original order before selected body emission; selection is diagnostic.
"""
from __future__ import annotations
import argparse, difflib, hashlib, json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OLD = ROOT / 'build/compiler-producer-diagnostic-020'
NEW = ROOT / 'build/compiler-producer-diagnostic-021'
PRIOR = ROOT / 'build/generic-client-arity-004'

def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()

def write(path, value):
    Path(path).write_text(json.dumps(value, indent=2) + '\n')

TARGETS = [
    'src/local_player_session:cooking_delegate_bundle',
    'src/local_player_session:cooking_save_prepared',
    'src/local_player_session:cooking_saved',
    'src/local_player_session:cooking_save_publication',
    'src/local_player_session:cooking_save_entities',
    'src/local_player_session:new_cooking_inventory',
    'profile_adopted', 'profile_loaded', 'cooking_actual',
    'src/remote_entity_scene_backend:checked',
    'src/local_player_entity_scene:captured',
    'src/local_player_entity_scene:sampled',
    'src/local_player_entity_scene:recorded',
    'src/resource_client_wire:scene_frame',
    'src/resource_client_wire:reply_value',
    'src/resource_client_wire:reply_encoded',
    'src/local_player_cooking_entity_owner:with_publisher',
    'src/local_player_cooking_publication_owner:prepare',
    'src/local_player_cooking:persistence_ready',
    'src/local_player_session:block_action_detached',
    'src/local_player_cooking:tick_activated',
    'src/player_cooking_menu:owner_matched',
    'src/player_cooking_menu_campfire:dispatch_captured',
]

ADDITION = r'''
const ACTOR021_ARITY_ROWS:any[]=[];
export function actor021_selected_probe(book:Bend.Book,names:string[],output:string) {
 const fl=file_book(book,['main',...RUNTIME_ADTS],false);
 const foreign=[...done_defs(fl,def_foreign)].map(([k])=>({name:k,words:fun_of(fl,k).lays.length}));
 const constructors=[...SRCS.keys()].flatMap(k=>((book.tlds[k] as Bend.ADT).c??[]).map(c=>({name:c.k,words:lay_node(book,c.k).ks.length})));
 const layoutNames=['src/core:World','src/local_player_session:State','src/local_player_session:Shell',
  'src/local_player_runtime:Transient','src/local_player_cooking:Sidecar',
  'src/local_player_cooking_entity_owner:Carrier','src/local_player_cooking_publication_owner:Carrier',
  'src/local_player_cooking_storage:Saved','src/remote_entity_frame:Frame',
  'src/resource_client_wire:Reply','src/generic_resource_world_sample:Sample'];
 const layouts=layoutNames.filter(k=>book.tlds[k]?.$==='ADT').map(k=>({name:k,words:lay_of(book,Bend.ADT(k,[])).ks.length}));
 const admitted=new Set(done_defs(fl).map(([k])=>k));
 const absent=names.filter(k=>!admitted.has(k));names=names.filter(k=>admitted.has(k));
 fs.writeFileSync(output+'/selection.json',JSON.stringify({names,absent,constructors,foreign,layouts},null,2)+'\n');
 console.log(JSON.stringify({phase:'selected_targets',count:names.length,absent,layouts}));
 const result:any[]=[];let lastgc=performance.now();
 for(const k of names) {
   const started=performance.now();console.log(JSON.stringify({phase:'selected_begin',name:k,time_ms:started}));
   ACTOR021_ARITY_ROWS.length=0;fl.segs=[];fl.spins=[];memo_gc();
   const [dl,vals]=emit_open({...fl,fresh:new Map(),brwl:new Map(),rest:[]},k);
   fl.segs.push(dl.seg);
   emit_body(dl,fun_of(fl,k).h!,book.tlds[k].T,[],vals,null);
   const all=[...fl.segs,...fl.spins];
   const edges=all.flatMap(s=>[...s.refs].map(r=>[s.fid,r]));
   const reachable=graph_close(new Set([seg_fid(k)]),edges);
   const row={name:k,input_formal_words:dl.seg.params.length,
     elapsed_ms:performance.now()-started,
     segments:all.map(s=>({name:s.def,fid:s.fid,params:s.params.length,lines:s.lines.length,
       reachable:reachable.has(s.fid),refs:[...s.refs],wide_body:s.params.length>247?s.lines:null})),
     captures:ACTOR021_ARITY_ROWS.slice(),facts:{own:fl.own.size,hot:fl.hot.size,stat:fl.stat.size}};
   fs.appendFileSync(output+'/bodies.jsonl',JSON.stringify(row)+'\n');
   result.push(row);
   console.log(JSON.stringify({phase:'selected_body',name:k,segments:all.length,
     maximum:Math.max(...all.map(s=>s.params.length)),elapsed_ms:row.elapsed_ms,
     wide:row.captures.filter(r=>r.params>247)}));
   memo_gc();
   if(process.memoryUsage().heapUsed>3221225472&&performance.now()-lastgc>1500){(globalThis as any).gc();lastgc=performance.now();}
 }
 return{scope:'Single selected-body diagnostic using original actor021 compiler semantics and whole-book checking/order on the selected frozen source generation. Initial ownership facts evolve only through selected bodies. No ownership fixpoint, final-live-main enumeration, C output, native run or final-pass suffix claim.',
   constructor_count:constructors.length,constructor_max:constructors.sort((a,b)=>b.words-a.words)[0],
   foreign_max:foreign.sort((a,b)=>b.words-a.words)[0],layouts,absent,result};
}
'''

def prepare(output):
    output = output.resolve(); output.mkdir(parents=True, exist_ok=False)
    maps = [json.loads((base/'source/source-map.json').read_text()) for base in (OLD, NEW)]
    records = [{r['path']:r for r in m['files']} for m in maps]
    delta = []; changes = []
    for name in sorted(records[0].keys() | records[1].keys()):
        a,b = (r.get(name) for r in records)
        if a and b and a['mapped']['sha256'] == b['mapped']['sha256']: continue
        delta.append({'path':name,'before':None if a is None else a['mapped'],
                      'after':None if b is None else b['mapped']})
        if name.endswith('.bend'):
            left=[] if a is None else Path(a['mapped']['resolved']).read_text().splitlines(True)
            right=[] if b is None else Path(b['mapped']['resolved']).read_text().splitlines(True)
            changes.extend(difflib.unified_diff(left,right,fromfile='actor020/'+name,tofile='actor021/'+name))
    (output/'delta.diff').write_text(''.join(changes)); write(output/'delta.json',delta)
    base = (NEW/'comp_instrumented.ts').read_text()
    anchor='  fl.segs.push(seg);\n  fl = { ...fl, seg, spares: [], uses: new Map() };'
    if base.count(anchor)!=1: raise RuntimeError('Unexpected original seg_open')
    observer=r'''  const arity_row={name,fid:seg.fid,params:seg.params.length,returned_words:res.ws.length,
    captures:live.map(([p,b])=>({name:p.k,words:b.val.ws.length,
      layout_words:b.val.lay.ks.length,word_expressions:b.val.ws,
      type:Bend.term_key(Bend.term_lower(b.A)).slice(0,1600)}))};
  ACTOR021_ARITY_ROWS.push(arity_row);
  if(seg.params.length>247)console.log(JSON.stringify({phase:'wide_capture',time_ms:performance.now(),...arity_row}));
'''
    (output/'probe_comp.ts').write_text(base.replace(anchor,observer+anchor)+ADDITION)
    entry=NEW/'source/remote_resource_server.bend'
    source=f'''import * as B from "file://{ROOT.parent/'bend/bend2/bend.ts'}";
import * as C from "./probe_comp.ts";
import fs from "node:fs";
import crypto from "node:crypto";
const output={json.dumps(str(output))},entry={json.dumps(str(entry))};
const sha=p=>crypto.createHash("sha256").update(fs.readFileSync(p)).digest("hex");
const book=B.book_nil(),seen=new Map(),started=performance.now();
console.log(JSON.stringify({{phase:"load",pid:process.pid}}));
await B.book_load(book,entry,"",seen);
const files=new Set(seen.keys());
for(const d of Object.values(book.tlds))for(const p of d.i??[])if(fs.existsSync(p))files.add(fs.realpathSync(p));
const pins=Object.fromEntries([...files].sort().map(p=>[p,sha(p)]));
fs.writeFileSync(output+"/loaded-source-pins.json",JSON.stringify(pins,null,2)+"\\n");
let lastgc=performance.now();const order=book.order,names=[...order];let reads=0,checked=new Set();
book.order=new Proxy(order,{{get(t,k,r){{if(typeof k==='string'&&/^\\d+$/.test(k)){{if(reads>=names.length){{checked.add(Number(k));if(process.memoryUsage().heapUsed>3221225472&&performance.now()-lastgc>1500){{globalThis.gc();lastgc=performance.now();}}}}reads++;}}return Reflect.get(t,k,r)}}}});
try{{B.book_valid(book)}}finally{{book.order=order}}
if(book.hols!==0||checked.size!==names.length||JSON.stringify(order)!==JSON.stringify(names))throw Error("Incomplete unchanged original checking");
globalThis.gc();console.log(JSON.stringify({{phase:"checked",declarations:Object.keys(book.tlds).length,source_holes:book.hols,order_entries:checked.size,seconds:(performance.now()-started)/1000,memory:process.memoryUsage()}}));
const observed=C.actor021_selected_probe(book,{json.dumps(TARGETS)},output);
const result={{entry,entry_sha256:sha(entry),checked_declarations:Object.keys(book.tlds).length,source_holes:book.hols,whole_original_check_order_entries:checked.size,seconds:(performance.now()-started)/1000,source_pins:pins,...observed}};
for(const [p,h]of Object.entries(pins))if(sha(p)!==h)throw Error("Frozen source changed: "+p);
fs.writeFileSync(output+"/final-source-pins.json",JSON.stringify(pins,null,2)+"\\n");
fs.writeFileSync(output+"/probe.json",JSON.stringify(result,null,2)+"\\n");
console.log(JSON.stringify({{phase:"selected_complete",seconds:result.seconds,constructors:result.constructor_max,foreign:result.foreign_max,targets:result.result.map(r=>({{name:r.name,input_formal_words:r.input_formal_words,segments:r.segments.length,wide:r.segments.filter(s=>s.params>247)}}))}}));
'''
    (output/'probe.mjs').write_text(source)
    runner=(PRIOR/'run.py').read_text().replace('GenericClient bodies','actor021 changed-consumer bodies')
    runner=runner.replace('Unchanged original full source elaboration,', 'Original whole-book checking algorithm/order on the selected frozen source generation,')
    runner=runner.replace('except ProcessLookupError:absent=True', '''except ProcessLookupError:absent=True
except PermissionError as error:
 cleanup_probe_error={"type":type(error).__name__,"errno":error.errno,"message":str(error)}
 rows=subprocess.run(['ps','-axo','pid=,pgid=,stat='],capture_output=True,text=True,check=True).stdout.splitlines()
 absent=not any(len(v:=r.split())==3 and int(v[1])==p.pid and not v[2].startswith('Z') for r in rows)''')
    runner=runner.replace("'limits':{'seconds':90,'rss_bytes':8589934592}","'limits':{'seconds':90,'rss_bytes':8589934592},'cleanup_probe_error':locals().get('cleanup_probe_error')")
    (output/'run.py').write_text(runner)
    frozen={str(NEW/'source'/r['path']):r['mapped']['sha256'] for r in maps[1]['files']}
    for p,h in frozen.items():
        if sha(p)!=h: raise RuntimeError('Frozen actor021 input changed: '+p)
    inputs=[NEW/'source/source-map.json',NEW/'comp_instrumented.ts',PRIOR/'probe.mjs',PRIOR/'probe_comp.ts',PRIOR/'run.py',ROOT.parent/'bend/bend2/bend.ts',ROOT.parent/'bend/bend2/comp.ts']
    files={str(p):sha(p) for p in inputs}; files.update(frozen)
    for name in ['probe_comp.ts','probe.mjs','run.py','delta.json','delta.diff']:files[str(output/name)]=sha(output/name)
    manifest={'schema':1,'status':'prepared_file_only','frozen_generation':'actor021',
              'entry':str(entry),'files':files,'targets':TARGETS,'changed_paths':len(delta),
              'limits':{'seconds':90,'rss_bytes':8589934592,'heap_mib':8192},
              'whole_original_source_check_required':True,'original_compiler_or_product_edited':False,
              'basis':str(PRIOR),'scope':'Selected actual body/capture/layout observation, not full emission or final guard attribution.'}
    write(output/'manifest.json',manifest)
    return {'status':'prepared_file_only','directory':str(output),'changed_paths':len(delta),'selected_targets':len(TARGETS),'manifest_sha256':sha(output/'manifest.json')}

if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('output',type=Path);args=parser.parse_args()
    print(json.dumps(prepare(args.output)))
