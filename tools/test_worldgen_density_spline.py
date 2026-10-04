#!/usr/bin/env python3
"""Exercise actual loaded Bend density graphs against actual Java observations.

Uses the existing bounded process receiver and ordinary content-keyed native
builder. Python does not evaluate a density expression or implement noise.
"""
from __future__ import annotations
import argparse, hashlib, json, re, shutil, sys, time
from pathlib import Path
from reference_inventory import ROOT, fingerprint, write_json
from reference_superflat_probe import WORK, run

REFERENCE=ROOT/'reference/worldgen_density_spline.json'
ENTRY=ROOT/'tests/worldgen_density_spline.bend'
CURRENT=WORK/'density-spline-native-current.json'
BASE=ROOT.parent/'bend/bend2/base.bend'
NODE='/opt/homebrew/Cellar/node/23.5.0/bin/node'

def closure(path,seen=None):
    seen={} if seen is None else seen;path=path.resolve()
    if path in seen:return seen
    seen[path]=fingerprint(path)
    for name in re.findall(r'^import\s+(\S+)',path.read_text(),re.M):
        closure(BASE if name=='Base' else path.parent/name,seen)
    return seen

def source_check():
    token=str(time.time_ns());directory=WORK/('density-spline-source-'+token);directory.mkdir()
    pins=closure(ENTRY);snapshots=directory/'snapshots';snapshots.mkdir()
    rows=[{'path':str(p),**pin} for p,pin in pins.items()]
    write_json(directory/'source-pins.json',rows)
    for i,p in enumerate(pins):shutil.copyfile(p,snapshots/(str(i)+'-'+p.name))
    script=r'''import * as B from BEND_URL;
import * as fs from "node:fs";import * as crypto from "node:crypto";
const entry=ENTRY,pins=PINS,sha=x=>crypto.createHash("sha256").update(x).digest("hex");
try{
for(const p of pins)if(sha(fs.readFileSync(p.path))!==p.sha256)throw Error("Source changed before load "+p.path);
const book=B.book_nil(),seen=new Map();await B.book_load(book,entry,"",seen);
if(seen.size!==pins.length||pins.some(p=>!seen.has(p.path)))throw Error("Import closure changed");
B.book_valid(book);if(book.hols)throw Error("Proof holes");
for(const p of pins)if(sha(fs.readFileSync(p.path))!==p.sha256)throw Error("Source changed while checking "+p.path);
console.log("SOURCE CHECK PASS");
}catch(e){console.error(e.$==="Err"?B.err_show(e):String(e));process.exitCode=1;}
'''
    for k,v in [('BEND_URL',(ROOT.parent/'bend/bend2/bend.ts').as_uri()),('ENTRY',str(ENTRY)),('PINS',rows)]:script=script.replace(k,json.dumps(v))
    executed=directory/'executed-source.mjs';executed.write_text(script)
    output,process=run('density-spline-source-process-'+token,[NODE,'--stack-size=4096','--max-old-space-size=4096','--experimental-transform-types',executed],60)
    result={'status':'passed','entry':str(ENTRY.relative_to(ROOT)),'source_pins':rows,'process':process,'script':fingerprint(executed),'verdict':output.strip()}
    write_json(directory/'result.json',result)
    return {'status':'passed','seconds':process['seconds'],'receipt':str(directory/'result.json')}

def build():
    token=str(time.time_ns());directory=WORK/('density-spline-native-'+token);directory.mkdir()
    binary=directory/'worldgen-density';report=directory/'native-build.json'
    output,process=run('density-spline-native-build-'+token,[sys.executable,ROOT/'tools/build_native.py',ENTRY,'-o',binary,'--report',report],600)
    result={'binary':str(binary),'report':str(report),'process':process,'binary_sha256':fingerprint(binary)['sha256']}
    write_json(CURRENT,result)
    return {'status':'passed','seconds':process['seconds'],'binary':str(binary),'report':str(report)}

def checked_build(pointer,retained_core=None):
    import test_worldgen_density as D
    return D.checked_build(pointer,retained_core)

def spline_fixture(case,settings,registry,range=False,**limits):
    seed=int(case['seed']);coords=';'.join(','.join(str(v&0xffffffff) for v in p) for p in case['points'])
    return '|'.join(['spline-range' if range else 'spline',str(seed>>32),str(seed&0xffffffff),
      json.dumps(settings,separators=(',',':')),json.dumps(registry,separators=(',',':')),case['expression_json'],coords,
      str(limits.get('compile_depth',128)),str(limits.get('nodes',4096)),str(limits.get('entries',256)),
      str(limits.get('sampler_fuel',64)),str(limits.get('depth',128))])

def retain_comparison(result,evidence_path=None):
    directory=WORK/('density-spline-compare-'+str(time.time_ns()));directory.mkdir()
    raw=directory/'result.json';write_json(raw,result)
    pointer=json.loads(CURRENT.read_text());build=result['native_build']
    compact={k:v for k,v in result.items() if k not in ('executions','native_build')}
    private=build.get('private_build',{})
    compact['native_build']={'report':{'path':pointer['report'],**fingerprint(Path(pointer['report']))},
      'binary':{'path':pointer['binary'],**fingerprint(Path(pointer['binary']))},
      'timings':build['timings'],'source_generation':build['comparison_source_generation'],
      'frozen_source_generation':build.get('frozen_source_generation'),
      'dependency_count':len(build['dependencies']),
      'reviewed_recipe':private.get('reviewed_recipe'),
      'product_cache_promoted':private.get('product_cache_promoted')}
    compact['executions']={'count':len(result['executions']),
      'native_seconds':sum(row['seconds'] for row in result['executions']),
      'all_groups_absent':all(row['leader_reaped'] and row['group_absent'] for row in result['executions'])}
    compact['raw_receipt']={'path':str(raw.relative_to(ROOT)),**fingerprint(raw)}
    compact['retention_helper']=fingerprint(Path(__file__).resolve())
    write_json(evidence_path or ROOT/'evidence/worldgen-density-spline-native.json',compact)
    return compact


def compare():
    reference=json.loads(REFERENCE.read_text());density=json.loads((ROOT/'reference/worldgen_density.json').read_text())
    if reference['pin']!='26.3' or reference['status']!='observed':raise ValueError('Actual pinned reference required')
    current,report,binary=checked_build(CURRENT);receipts=[];samples=0;failures=[];supported=0;unsupported=0;refusals=0
    def invoke(label,fixture):
        out,process=run('spline-compare-'+label+'-'+str(time.time_ns()),[binary,'--gpu','off','--threads','1',fixture],30)
        receipts.append(process);lines=out.splitlines()
        if len(lines)!=1:raise AssertionError((label,'one output line required',out))
        return lines[0]
    divide_refusal='fail|density divide requires the actual zero-short-circuit and constant-specialization implementation'
    unsupported_ids={'nan-coordinate-last-zero-derivative','nan-coordinate-last-nonzero-derivative',
      'infinite-coordinate-zero-derivative','infinite-coordinate-nonzero-derivative'}
    for index,case in enumerate(reference['observations']['cases']):
        if case['id'] in unsupported_ids:
            for range_mode in [False,True]:
                actual=invoke('unsupported-'+str(index)+'-'+str(range_mode),spline_fixture(case,density['settings'],density['registry'],range=range_mode))
                if actual!=divide_refusal:failures.append({'id':case['id'],'kind':'unsupported-node-refusal','expected':divide_refusal,'actual':actual})
            unsupported+=1
            continue
        supported+=1
        actual=invoke(str(index),spline_fixture(case,density['settings'],density['registry']))
        expected='density|'+''.join(str(v)+';' for v in case['bits'])
        if actual!=expected:failures.append({'id':case['id'],'seed':case['seed'],'kind':'sample','expected':expected,'actual':actual})
        samples+=len(case['bits'])
        actual_range=invoke('range-'+str(index),spline_fixture(case,density['settings'],density['registry'],range=True))
        observed=case['range'];expected_range='range|'+('True' if observed['nai'] else 'False')+'|'+str(observed['min_bits'])+','+str(observed['max_bits'])
        if actual_range!=expected_range:failures.append({'id':case['id'],'seed':case['seed'],'kind':'range','expected':expected_range,'actual':actual_range})
    from reference_worldgen_density_spline import refusal_cases
    expected_refusals={'empty-points':'density spline has no points',
      'missing-derivative':'missing density spline field: derivative',
      'missing-coordinate':'missing density spline field: coordinate',
      'invalid-value-kind':'density spline must be a float or coordinate/points object'}
    observed_refusals={r['id']:r for r in reference['observations']['refusals']}
    for case in refusal_cases():
        if observed_refusals[case['id']]['accepted']:raise AssertionError('Java reference unexpectedly accepted '+case['id'])
        case={**case,'seed':'0','points':[[0,0,0]]}
        actual=invoke('refusal-'+case['id'],spline_fixture(case,density['settings'],density['registry']))
        expected='fail|'+expected_refusals[case['id']]
        if actual!=expected:failures.append({'id':case['id'],'kind':'codec-refusal','expected':expected,'actual':actual})
        refusals+=1
    budget_case=next(case for case in reference['observations']['cases'] if case['id']=='nested-distinct-coordinate')
    for label,limits,message in [('compile-depth',{'compile_depth':1},'density spline compilation exceeds caller depth budget'),
      ('node-budget',{'nodes':1},'density DAG exceeds caller node budget'),
      ('runtime-depth',{'depth':1},'density evaluation exceeds caller depth budget')]:
        actual=invoke('budget-'+label,spline_fixture(budget_case,density['settings'],density['registry'],**limits))
        # Runtime failures are serialized per sampled point by H.samples;
        # compile/initialization failures use the harness's top-level refusal.
        expected=('density|'+''.join('fail:'+message+';' for _ in budget_case['points'])
          if label=='runtime-depth' else 'fail|'+message)
        if actual!=expected:failures.append({'id':label,'kind':'caller-budget-refusal','expected':expected,'actual':actual})
        refusals+=1
    long_token_case={'id':'long-FLOAT-lexeme','seed':'0','points':[[0,0,0]],
      'expression_json':'{"type":"minecraft:spline","spline":1.'+'0'*256+'1}'}
    long_actual=invoke('long-FLOAT-lexeme',spline_fixture(long_token_case,density['settings'],density['registry']))
    long_expected='density|1065353216;'
    if long_actual!=long_expected:failures.append({'id':'long-FLOAT-lexeme','kind':'codec-token-regression','expected':long_expected,'actual':long_actual})
    result={'schema':1,'pin':'26.3','status':'passed' if not failures else 'failed','samples':samples,
      'cases':supported,'range_cases':supported,'unsupported_node_cases':unsupported,'refusal_cases':refusals,'java_observed_cases':len(reference['observations']['cases']),'codec_token_regressions':1,
      'failures':failures,'native_build':report,'reference':fingerprint(REFERENCE),'executions':receipts,
      'helper':fingerprint(Path(__file__).resolve()),
      'scope':'Actual compiled unblended density DAG sampling and range analysis through the production loader/state/evaluator. Includes recursive spline/noise/registry coordinates, arbitrary accepted point ordering, FLOAT decode boundaries, and unconstrained infinite spline constants. Four NaI/Inf coordinates requiring unsupported Divide retain their Java observations and exercise the production explicit refusal. No full chunk population or interpolation volume claim.'}
    retain_comparison(result)
    if failures:raise AssertionError(failures[:8])
    return {'status':'passed','cases':result['cases'],'samples':samples,'range_cases':result['range_cases'],'unsupported_node_cases':unsupported,'refusal_cases':refusals}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);mode=parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--source-check',action='store_true');mode.add_argument('--build',action='store_true');mode.add_argument('--compare',action='store_true');args=parser.parse_args()
    print(json.dumps(source_check() if args.source_check else build() if args.build else compare(),sort_keys=True))
