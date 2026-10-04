#!/usr/bin/env python3
"""Freeze and build actor004; actual TCP/MCP acceptance is a separate runner.

Reuse the measured private source-API emitter and existing bounded process owners.
The product entry imports production only; tests drive it through real sockets.
"""
from __future__ import annotations
import argparse,copy,csv,dataclasses,hashlib,json,os,shutil,subprocess,sys
from pathlib import Path
import build_native as Builder
import test_playable_client_session as P
import test_remote_resource_client as R
import test_local_player_session as S
import test_fall_reset_world_continuation_r2 as H
ROOT=Path(__file__).resolve().parents[1]
WORK=ROOT/'build/compiler-producer-diagnostic-019'
SOURCE=WORK/'source'
ACTOR=WORK/'actor'
OLD=ROOT/'build/compiler-producer-diagnostic-012'
PRIVATE=ROOT/'build/actor-compiler-memory-001'
PRIVATE_PINS={
    'comp_instrumented.ts':'d2e149a6c97c6f57af8bb8c2bc86b4203a933cf18e430916efe40f456e818f4a',
    'run.py':'3dc542c1e956b42ea1052344f40cdf94dd2b33a68ec7387113e16952a91e5fbd',
}
RUNTIME_FACTS=(
    'generated/reference_item_metadata.tsv',
    'generated/reference_crafting_authority_metadata.json',
    'reference/block_light_registry.tsv',
    'reference/cooking_world_bindings.tsv',
)
class PlayableBackend(P.PlayableBackend):
    """Current full crafting startup; historical P callers keep their budgets."""
    def __init__(self, directory, binary, path, bridge, *, create=False, mode='creative',
                 startup_seconds=150, lifetime_seconds=180):
        # Entry consumes these relative files from the working directory.
        # Check the frozen inputs once when launching this generation.
        runtime=WORK/'runtime-inputs.json'
        if Path(binary).resolve()==ACTOR.resolve() and runtime.exists():
            for row in json.loads(runtime.read_bytes())['files']:
                R.require(R.pin(row['original']['path'])==row['original'],
                          'Actor runtime input differs from built generation: '+row['original']['path'])
        super().__init__(directory, binary, path, bridge, create=create, mode=mode,
                         startup_seconds=startup_seconds, lifetime_seconds=lifetime_seconds)

PlayablePrivate=P.PlayablePrivate
playable_spawn=P.playable_spawn
playable_look=P.playable_look
pin=R.pin

def snapshot():
    """Copy the real graph once; later working-source edits cannot alter it."""
    if not (SOURCE/'source-map.json').exists():
        with H.bindings(P,{'SOURCE_ROOT':SOURCE}):P.map_current_sources(Builder)
    mapping=json.loads((SOURCE/'source-map.json').read_bytes())
    for row in mapping['files']:
        actual=pin(SOURCE/row['path'])
        R.require(actual['sha256']==row['original_sha256'],'Mapped source drift: '+row['path'])
    runtime_path=WORK/'runtime-inputs.json'
    if not runtime_path.exists():
        rows=[]
        for name in RUNTIME_FACTS:
            original=ROOT/name
            target=SOURCE/name
            before=pin(original)
            target.parent.mkdir(parents=True,exist_ok=True)
            # The production mapper already carries item metadata. Admit that
            # exact existing copy; create only the additional runtime facts.
            if not target.exists():
                with target.open('xb') as output:output.write(original.read_bytes())
            mapped=pin(target)
            R.require(pin(original)==before and mapped['sha256']==before['sha256'],'Runtime facts changed while copying: '+name)
            rows.append({'original':before,'mapped':mapped})
        R.write(runtime_path,{'scope':'Pinned initialized item facts and authenticated light/cooking manifests. Original recipe and fuel-provider JSON are read from the installed26.3 JAR at startup, not copied into product sources.',
            'files':rows},True)
    else:
        for row in json.loads(runtime_path.read_bytes())['files']:
            R.require(pin(row['mapped']['path'])==row['mapped'],'Mapped runtime input changed')
    return mapping


def checked_progress(text):
    """Observe original checker order and collect garbage; no checker edits."""
    previous='B.book_valid(book);if(book.hols!==0)throw Error("Open holes");'
    R.require(text.count(previous)==1,'Tested012 checker boundary changed')
    replacement='''const original_order=book.order, names=[...original_order], checked=new Set();
let reads=0,last_gc=performance.now();
book.order=new Proxy(original_order,{get(target,key,receiver){
  if(typeof key==='string'&&/^\\d+$/.test(key)){
    const index=Number(key);
    if(reads>=names.length){
      checked.add(index);
      if(index%128===0)console.log(JSON.stringify({phase:"check_progress",index,name:target[index],memory:process.memoryUsage()}));
      if(process.memoryUsage().heapUsed>3221225472&&performance.now()-last_gc>1500){globalThis.gc();last_gc=performance.now();}
    }
    reads++;
  }
  return Reflect.get(target,key,receiver);
}});
try{B.book_valid(book);}finally{book.order=original_order;}
if(book.hols!==0)throw Error("Open holes");
if(checked.size!==names.length||JSON.stringify(book.order)!==JSON.stringify(names))throw Error("Checker order incomplete or changed");'''
    text=text.replace(previous,replacement)
    R.require(text.count('const entry=')==1,'Tested012 entry boundary changed')
    return text.replace('const entry=','try {\nconst entry=',1)+'''
} catch(error) {
  console.error(error?.$==="Err" ? B.err_show(error) : error);
  process.exitCode=1;
}
'''

def build():
    mapping=snapshot()
    runtime=json.loads((WORK/'runtime-inputs.json').read_bytes())
    for row in runtime['files']:
        R.require(pin(row['mapped']['path'])==row['mapped'],'Mapped runtime input changed')
    result=WORK/'native-build.json'
    if result.exists():
        done=json.loads(result.read_bytes())
        R.require(done['status']=='PASS' and done['binary']==pin(ACTOR) and done['source_map']==pin(SOURCE/'source-map.json'),'Existing actor004 artifact mismatch')
        print(json.dumps({'status':'verified-build-reuse','binary':done['binary']}),flush=True)
        return
    R.require(not ACTOR.exists(),'Unrecorded existing actor binary')
    prior=json.loads((OLD/'manifest.json').read_bytes())
    original={p:expected for p,expected in prior['files'].items() if not Path(p).is_relative_to(ROOT)}
    for path,expected in original.items():R.require(pin(path)['sha256']==expected,'Original compiler/tool changed: '+path)
    if not (WORK/'receipt.json').exists():
        for name,expected in PRIVATE_PINS.items():
            R.require(pin(PRIVATE/name)['sha256']==expected,'Narrow-tested private emitter changed: '+name)
        for name in ('comp_instrumented.ts','run.py','diagnose.mjs'):
            origin=OLD if name=='diagnose.mjs' else PRIVATE
            text=(origin/name).read_text().replace(str(OLD),str(WORK))
            if name=='diagnose.mjs':
                text=checked_progress(text)
            with (WORK/name).open('x') as output:output.write(text)
        inputs={**original,**{str(path):pin(path)['sha256'] for path in [WORK/name for name in ('comp_instrumented.ts','run.py','diagnose.mjs')]+[PRIVATE/name for name in PRIVATE_PINS]+[SOURCE/'remote_resource_server.bend',SOURCE/'source-map.json',WORK/'runtime-inputs.json']+[Path(row['mapped']['path']) for row in runtime['files']]}}
        limits={'heap_mib':8192,'total_seconds':600,'silence_only_termination':False,'sampled_rss_bytes':8589934592}
        R.write(WORK/'manifest.json',{'scope':'Actor004/producer019 boxes the sole live cooking owner and joins strict pending-effect recovery to original-JAR cooking/fuel startup, authenticated light/cooking discovery and physical bodies in the atomic world save. This changed source addresses the retained018 native argument-limit failure; successful source typing and layout reduction do not establish native completion. Includes the native-verified numeric continuation fix. Retains private65536-byte framing, crafting, prospective menu publication, generic samples and moving receiver. Tested private WeakMap/per-function producer; original checker/compiler unchanged. Native cooking consumer is separate; no cache promotion or compiler-wide certification.','files':inputs,'limits':limits,'entry':str(SOURCE/'remote_resource_server.bend')},True)
        with H.bindings(R,{'WORK':WORK}):
            emitted=R.bounded([sys.executable,str(WORK/'run.py')],605,'emission-process')
            R.process_ok(emitted)
    receipt=json.loads((WORK/'receipt.json').read_bytes())
    R.require(receipt['returncode']==0 and receipt['termination_reason'] is None and receipt['complete_C'] and receipt['group_absent'],'Current actor C producer failed; retain failure without retry')
    for path,expected in receipt['source_after'].items():
        R.require(pin(path)['sha256']==expected,'Retained C producer input changed: '+path)
    loaded=json.loads((WORK/'loaded-source-pins.json').read_bytes())
    R.require(loaded==json.loads((WORK/'final-source-pins.json').read_bytes()),'Retained C loaded source drift')
    for path,expected in loaded.items():R.require(pin(path)['sha256']==expected,'Retained C loaded source changed: '+path)
    with H.bindings(R,{'WORK':WORK}):
        c=WORK/'diagnostic.c';cpin=pin(c)
        R.require(cpin['bytes']==receipt['C']['bytes'] and cpin['sha256']==receipt['C']['sha256'],'Retained C changed')
        Builder.guard_route(c.read_text())
        sdk=subprocess.check_output(['/usr/bin/xcrun','--show-sdk-path'],text=True).strip()
        command=['/usr/bin/env','SDKROOT='+sdk,'/usr/bin/clang','-std=c11','-O3',str(c),'-lpthread','-lm','-o',str(ACTOR)]
        clangpin=pin('/usr/bin/clang')
        compiled=R.bounded(command,300,'native-build-process')
        R.process_ok(compiled)
        R.require(Path(compiled['stderr']['path']).read_bytes()==b'' and pin(c)==cpin and pin('/usr/bin/clang')==clangpin,'Unexpected native compiler diagnostic or input drift')
    R.require(pin(ACTOR)['sha256']!=pin(OLD/'actor')['sha256'],'New actor reused old binary')
    done={'status':'PASS','generation':'immutable-actor004/producer019','binary':pin(ACTOR),'source_map':pin(SOURCE/'source-map.json'),'runtime_inputs':pin(WORK/'runtime-inputs.json'),'entry':pin(SOURCE/'remote_resource_server.bend'),'C':cpin,'producer':pin(WORK/'receipt.json'),'source_API':pin(ROOT.parent/'bend/bend2/bend.ts'),'private_compiler':pin(WORK/'comp_instrumented.ts'),'original_compiler':pin(ROOT.parent/'bend/bend2/comp.ts'),'loaded_source_pins':pin(WORK/'loaded-source-pins.json'),'final_source_pins':pin(WORK/'final-source-pins.json'),'emission_seconds':receipt['seconds'],'sampled_peak_RSS_bytes':receipt['sampled_peak_rss_bytes'],'clang':{'command':command,'SDKROOT':sdk,'seconds':compiled['seconds'],'process':pin(WORK/'native-build-process/result.full.json')},'retries':0,'product_cache_promoted':False,'behavior':'pending actual native cooking/socket/save/reload consumer'}
    R.write(result,done,True);R.write(ROOT/'evidence/playable-client-actor004-build-019.json',done,True)
    print(json.dumps({'status':done['status'],'binary':done['binary'],'emission_seconds':done['emission_seconds'],'clang_seconds':compiled['seconds']}),flush=True)


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--snapshot-only',action='store_true')
    args=parser.parse_args()
    if args.snapshot_only:
        mapping=snapshot()
        print(json.dumps({'status':'frozen-production-source','generation':'immutable-actor004/producer019',
            'source_map':pin(SOURCE/'source-map.json'),'runtime_inputs':pin(WORK/'runtime-inputs.json'),
            'project_files':len(mapping['files'])}),flush=True)
    else:build()


if __name__=='__main__':main()
