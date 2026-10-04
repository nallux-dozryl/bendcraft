#!/usr/bin/env python3
"""Check actual density laws, export exact checked roots, admit with BendTT.

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
    entry=ROOT/'src/worldgen_density_interval_proof.bend';laws=ROOT/'src/worldgen_density_interval_laws.bend'
    roots=['worldgen_density_interval_laws:'+s for s in re.findall(r'^law\s+([A-Za-z0-9_]+):',laws.read_text(),re.M)]
    pending=[]
    if runtime_owned:
        pending=['worldgen_density_interval_laws:empty_range_analysis_retains_complete_existing_table']
        roots=[root for root in roots if root not in pending]
    token=str(time.time_ns());directory=WORK/('worldgen-density-interval-proof-'+token);directory.mkdir();snapshots=directory/'source-snapshots';snapshots.mkdir()
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
    stdout,api=run('worldgen-density-interval-proof-api-'+token,[NODE,'--stack-size=4096','--max-old-space-size=4096','--experimental-transform-types',executed],60)
    scope=json.loads((directory/'scope.json').read_text())
    if scope['exclusions']:raise RuntimeError('Exact density proof export excluded roots: '+repr(scope['exclusions']))
    for p,pin in source_pins.items():
        if fingerprint(p)!=pin:raise RuntimeError('Density source changed before kernel')
    artifact=directory/'selected.bendtt';artifact_pin=fingerprint(artifact)
    output,kernel=run('worldgen-density-interval-proof-kernel-'+token,[KERNEL,artifact],60)
    if output.strip()!='ALL PROOFS CHECK':raise RuntimeError('Independent density admission failed: '+output[:4000])
    for p,pin in source_pins.items():
        if fingerprint(p)!=pin:raise RuntimeError('Density source changed after kernel')
    if fingerprint(artifact)!=artifact_pin:raise RuntimeError('Density artifact changed during kernel')
    selection=json.loads((directory/'selection.json').read_text())
    result={'schema':1,'pin':'26.3','status':'kernel_certified','kernel_admitted_laws':roots,'exclusions':[],
      'checked_types_and_bodies_unchanged':True,'all_original_declaration_maps_retained':True,
      'source_pins':[{'path':str(p.relative_to(ROOT)) if p.is_relative_to(ROOT) else str(p),**pin} for p,pin in source_pins.items()],
      'term_pins':selection['term_pins'],'checked_term_export':{'path':str(artifact.relative_to(ROOT)),**artifact_pin},
      'selection':str((directory/'selection.json').relative_to(ROOT)),
      'executed_script':fingerprint(executed),'helper':fingerprint(Path(__file__).resolve()),
      'compiler_api':fingerprint(BEND),'safe_exporter':fingerprint(SAFE),'independent_kernel':fingerprint(KERNEL),
      'ordinary_source_api':api,'kernel':kernel,'kernel_verdict':output.strip(),
      'pending_kernel_roots':pending,
      'scope':'Actual interval NaI propagation and missing analysis refusals, plus real MinMax selected-branch/short-circuit/failure cancellation over arbitrary complete owners and callbacks. Complete empty Range.analyze retention is separately pending when the runtime-owned selection is used. No IEEE arithmetic theorem, complete normal generation, or successful full-router claim.'}
    write_json(ROOT/('evidence/worldgen-density-interval-runtime-proof.json' if runtime_owned else 'evidence/worldgen-density-interval-proof.json'),result)
    return {'status':'kernel_certified','laws':len(roots),'bytes':artifact_pin['bytes'],'api_seconds':api['seconds'],'kernel_seconds':kernel['seconds']}
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);mode=parser.add_mutually_exclusive_group(required=True);mode.add_argument('--check',action='store_true');mode.add_argument('--runtime-owned',action='store_true');args=parser.parse_args();print(json.dumps(check(args.runtime_owned),sort_keys=True))
