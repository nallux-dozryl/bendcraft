#!/usr/bin/env python3
"""Check actual loaded-router and biome-join laws, export exact checked roots, admit with BendTT.

Uses the existing unmodified compiler API and retained independent kernel. No
terms, annotations, declarations or runtime implementation are replaced.
"""
from __future__ import annotations
import argparse, hashlib, json, re, shutil, time
from pathlib import Path
from reference_inventory import ROOT, fingerprint, write_json
from reference_superflat_probe import WORK, run
BEND=ROOT.parent/'bend/bend2/bend.ts'
SAFE=ROOT.parent/'bend/bend2/safe.ts'
BASE=ROOT.parent/'bend/bend2/base.bend'
KERNEL=Path.home()/'.bend/bendtt/e15042434e73aab0/bendtt'
NODE='/opt/homebrew/Cellar/node/23.5.0/bin/node'

def closure(path,seen=None):
    seen={} if seen is None else seen
    path=path.resolve()
    if path in seen:return seen
    seen[path]=fingerprint(path)
    for name in re.findall(r'^import\s+(\S+)',path.read_text(),re.M):
        target=BASE if name=='Base' else path.parent/name
        closure(target,seen)
    return seen

def check(runtime_owned=False):
    entry=ROOT/'src/worldgen_biome_resolver_proof.bend'
    law_files=[ROOT/'src/worldgen_density_router_laws.bend',ROOT/'src/worldgen_biome_resolver_laws.bend']
    names={path.stem:re.findall(r'^law\s+([A-Za-z0-9_]+):',path.read_text(),re.M) for path in law_files}
    all_roots=[stem+':'+name for stem,items in names.items() for name in items]
    runtime_roots=['worldgen_density_router_laws:'+name for name in names['worldgen_density_router_laws'][7:]]+[
      'worldgen_biome_resolver_laws:'+name for name in names['worldgen_biome_resolver_laws'][3:]]
    if len(all_roots)!=34 or len(runtime_roots)!=24 or len(set(runtime_roots))!=24:
        raise RuntimeError('Router/join exact root selection changed')
    roots=runtime_roots if runtime_owned else all_roots
    skipped=[name for name in all_roots if name not in roots]
    prefix='worldgen-density-router-runtime-proof-' if runtime_owned else 'worldgen-density-router-proof-'
    token=str(time.time_ns());directory=WORK/(prefix+token);directory.mkdir();snapshots=directory/'source-snapshots';snapshots.mkdir()
    source_pins=closure(entry)
    for i,(path,pin) in enumerate(source_pins.items()):shutil.copyfile(path,snapshots/(str(i)+'-'+path.name))
    write_json(directory/'pre-load-pins.json',[{'path':str(p),**pin} for p,pin in source_pins.items()])
    # The exact-root export route is the already exercised production route.
    script=r'''import * as B from BEND_URL;
import * as Safe from SAFE_URL;
import * as fs from "node:fs";
import * as crypto from "node:crypto";
try {
const entry=ENTRY,dir=DIRECTORY,roots=ROOTS;
const sha=x=>crypto.createHash("sha256").update(x).digest("hex");
const pre=JSON.parse(fs.readFileSync(dir+"/pre-load-pins.json","utf8"));
for(const p of pre)if(sha(fs.readFileSync(p.path))!==p.sha256)throw Error("Source changed before load "+p.path);
const book=B.book_nil(),seen=new Map();await B.book_load(book,entry,"",seen);
if(seen.size!==pre.length||pre.some(p=>!seen.has(p.path)||sha(fs.readFileSync(p.path))!==p.sha256))throw Error("Loaded source closure changed");
B.book_valid(book);if(book.hols!==0)throw Error("Open proof holes");
const order=[...book.order],tlds=book.tlds,ctrs=book.ctrs,tmps=book.tmps;
const original=Object.entries(book.tlds).map(([k,t])=>[k,t,t.T,t.$==="Def"?t.v:null,t.$==="Def"?t.e:null]);
const termPins=roots.map(k=>{const t=book.tlds[k];if(t?.$!=="Def"||!t.e||!t.v||t.u||t.i)throw Error("Missing checked pure proof "+k);return {name:k,type_sha256:sha(B.term_key(B.term_lower(t.T))),checked_proof_sha256:sha(B.term_key(t.e)),source_body_sha256:sha(B.term_key(B.term_lower(t.v)))};});
book.order=order.filter((k,i)=>roots.includes(k)&&order.lastIndexOf(k)===i);
if(book.order.length!==roots.length||book.tlds!==tlds||book.ctrs!==ctrs||book.tmps!==tmps)throw Error("Declaration ownership changed");
for(const [k,t,T,v,e] of original)if(book.tlds[k]!==t||t.T!==T||(t.$==="Def"&&(t.v!==v||t.e!==e)))throw Error("Term changed "+k);
const selection={entry,roots,selected_root_count:book.order.length,original_root_count:order.length,
 checked_types_and_bodies_unchanged:true,all_original_tlds_ctrs_tmps_retained:true,term_pins:termPins,source_files:pre};
fs.writeFileSync(dir+"/selection.json",JSON.stringify(selection,null,2)+"\n");
const exclusions=Safe.safe_emit(book,dir+"/selected.bendtt");fs.writeFileSync(dir+"/scope.json",JSON.stringify({exclusions},null,2)+"\n");
for(const p of pre)if(sha(fs.readFileSync(p.path))!==p.sha256)throw Error("Source changed during export "+p.path);
console.log(JSON.stringify({checked_roots:roots.length,bytes:fs.statSync(dir+"/selected.bendtt").size,exclusions}));
if(exclusions.length)process.exitCode=2;
} catch (error) { console.error(error?.$ === "Err" ? B.err_show(error) : String(error?.stack ?? error)); process.exitCode=1; }
'''
    for key,value in [('BEND_URL',BEND.as_uri()),('SAFE_URL',SAFE.as_uri()),('ENTRY',str(entry)),('DIRECTORY',str(directory)),('ROOTS',roots)]:script=script.replace(key,json.dumps(value))
    executed=directory/'executed-inline-source.mjs';executed.write_text(script)
    stdout,api=run(prefix+'api-'+token,[NODE,'--stack-size=4096','--max-old-space-size=4096','--experimental-transform-types',executed],60)
    scope=json.loads((directory/'scope.json').read_text())
    if scope['exclusions']:raise RuntimeError('Exact router/join proof export excluded roots: '+repr(scope['exclusions']))
    for p,pin in source_pins.items():
        if fingerprint(p)!=pin:raise RuntimeError('Router/join source changed before kernel')
    artifact=directory/'selected.bendtt';artifact_pin=fingerprint(artifact)
    kernel_label=prefix+'kernel-'+token
    try:
        output,kernel=run(kernel_label,[KERNEL,artifact],60)
    except RuntimeError:
        receipt=WORK/kernel_label
        output=(receipt/'stdout').read_text()
        kernel=json.loads((receipt/'process.json').read_text())
        selection=json.loads((directory/'selection.json').read_text())
        rejection={'schema':1,'pin':'26.3','status':'ordinary_checked_kernel_rejected',
          'ordinary_checked_laws':all_roots,'selected_roots':roots,'selection_mode':'runtime-owned' if runtime_owned else 'all-laws',
          'safe_export_exclusions':scope['exclusions'],'checked_types_and_bodies_unchanged':True,
          'all_original_declaration_maps_retained':True,'term_pins':selection['term_pins'],
          'artifact':{'path':str(artifact.relative_to(ROOT)),**artifact_pin},
          'selection':str((directory/'selection.json').relative_to(ROOT)),
          'executed_script':{'path':str(executed.relative_to(ROOT)),**fingerprint(executed)},
          'ordinary_source_api':api,'kernel':kernel,'kernel_verdict':output.strip(),
          'scope':'Exact checked terms and complete original declaration maps. A rejected kernel attempt does not certify its selected roots; narrower independently admitted roots have a separate receipt.'}
        write_json(ROOT/('evidence/worldgen-density-router-runtime-proof-rejected.json' if runtime_owned else 'evidence/worldgen-density-router-proof-limitation.json'),rejection)
        raise
    if output.strip()!='ALL PROOFS CHECK':raise RuntimeError('Independent router/join admission failed: '+output[:4000])
    for p,pin in source_pins.items():
        if fingerprint(p)!=pin:raise RuntimeError('Router/join source changed after kernel')
    if fingerprint(artifact)!=artifact_pin:raise RuntimeError('Climate artifact changed during kernel')
    selection=json.loads((directory/'selection.json').read_text())
    result={'schema':1,'pin':'26.3','status':'kernel_certified','kernel_admitted_laws':roots,'exclusions':[],
      'checked_types_and_bodies_unchanged':True,'all_original_declaration_maps_retained':True,
      'ordinary_checked_laws':all_roots,'selection_mode':'runtime-owned' if runtime_owned else 'all-laws',
      'skipped_compiler_and_admission_obligations':skipped,
      'source_pins':[{'path':str(p.relative_to(ROOT)) if p.is_relative_to(ROOT) else str(p),**pin} for p,pin in source_pins.items()],
      'term_pins':selection['term_pins'],'checked_term_export':{'path':str(artifact.relative_to(ROOT)),**artifact_pin},
      'selection':str((directory/'selection.json').relative_to(ROOT)),
      'executed_script':fingerprint(executed),'helper':fingerprint(Path(__file__).resolve()),
      'compiler_api':fingerprint(BEND),'safe_exporter':fingerprint(SAFE),'independent_kernel':fingerprint(KERNEL),
      'ordinary_source_api':api,'kernel':kernel,'kernel_verdict':output.strip(),
      'scope':('Actual production runtime/factory-result contracts: complete affine density program and ordered noise-pool retention by induction over every selected root list; retained original Router metadata and roots; explicit absent-root refusal; six real axis bindings; actual density Column delegation; loaded-preset lookup ownership; fixed-biome bypass; and full cache/history rollback. All 34 router/join laws are ordinary-checked. Ten compiler/admission obligations are explicitly outside this 24-root independent-kernel selection because their transitive production size traversal is unsupported by the kernel. No checked types, proof bodies, declaration maps or runtime declarations are replaced. Does not prove IEEE arithmetic parity, RTree global nearest optimality or full normal population.' if runtime_owned else 'Actual shared root-list compilation/factory boundaries, complete affine density program and ordered noise-pool retention by induction, explicit missing-root refusal, six real router axis bindings, actual density Column facade, loaded-preset join and full cache/history rollback. Does not prove IEEE arithmetic parity, RTree global nearest optimality or full normal population; separate pinned Java/native observations establish their stated cases.')}
    write_json(ROOT/('evidence/worldgen-density-router-runtime-proof.json' if runtime_owned else 'evidence/worldgen-density-router-proof.json'),result)
    return {'status':'kernel_certified','laws':len(roots),'bytes':artifact_pin['bytes'],'api_seconds':api['seconds'],'kernel_seconds':kernel['seconds']}
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    mode=parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--check',action='store_true')
    mode.add_argument('--runtime-owned',action='store_true',help='Select the 24 actual runtime/factory-result/lookup ownership laws and retain the ten separate compiler/admission obligations')
    args=parser.parse_args();print(json.dumps(check(args.runtime_owned),sort_keys=True))
