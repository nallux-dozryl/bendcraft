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

REFERENCE=ROOT/'reference/worldgen_density.json'
ENTRY=ROOT/'tests/worldgen_density.bend'
CURRENT=WORK/'density-native-current.json'
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
    token=str(time.time_ns());directory=WORK/('density-source-'+token);directory.mkdir()
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
    output,process=run('density-source-process-'+token,[NODE,'--stack-size=4096','--max-old-space-size=4096','--experimental-transform-types',executed],60)
    result={'status':'passed','entry':str(ENTRY.relative_to(ROOT)),'source_pins':rows,'process':process,'script':fingerprint(executed),'verdict':output.strip()}
    write_json(directory/'result.json',result)
    return {'status':'passed','seconds':process['seconds'],'receipt':str(directory/'result.json')}

def build():
    token=str(time.time_ns());directory=WORK/('density-native-'+token);directory.mkdir()
    binary=directory/'worldgen-density';report=directory/'native-build.json'
    output,process=run('density-native-build-'+token,[sys.executable,ROOT/'tools/build_native.py',ENTRY,'-o',binary,'--report',report],600)
    result={'binary':str(binary),'report':str(report),'process':process,'binary_sha256':fingerprint(binary)['sha256']}
    write_json(CURRENT,result)
    return {'status':'passed','seconds':process['seconds'],'binary':str(binary),'report':str(report)}

def checked_build(pointer,retained_core=None):
    current=json.loads(pointer.read_text());report_path=Path(current['report'])
    if not report_path.is_absolute():report_path=ROOT/report_path
    report=json.loads(report_path.read_text());binary=Path(current['binary'])
    if fingerprint(binary)['sha256']!=report['binary_sha256']:raise RuntimeError('Native binary changed')
    manifest_path=ROOT/'build/native-cache/entries'/report['cache_key']/'manifest.json'
    manifest=json.loads(manifest_path.read_text())
    if (manifest['binary_sha256']!=report['binary_sha256'] or
        manifest['key_data']['dependencies']!=report['dependencies'] or
        manifest['emitted_c_sha256']!=report['emitted_c_sha256']):
        raise RuntimeError('Native artifact manifest changed')
    emitted=ROOT/'build/native-cache/sources'/manifest['key_data']['prekey']/'generated.c'
    if fingerprint(emitted)['sha256']!=report['emitted_c_sha256']:raise RuntimeError('Emitted C changed')
    drift=[]
    for dependency in report['dependencies']:
        if dependency['kind'] in ('bend','base') and hashlib.sha256(Path(dependency['lookup']).read_bytes()).hexdigest()!=dependency['sha256']:
            if (retained_core is None or Path(dependency['lookup'])!=ROOT/'src/core.bend' or
                fingerprint(retained_core)['sha256']!=dependency['sha256']):
                raise RuntimeError('Native build input changed: '+dependency['lookup'])
            drift.append({'path':dependency['lookup'],'built_sha256':dependency['sha256'],
                'current':fingerprint(Path(dependency['lookup'])),'retained_source':fingerprint(retained_core)})
    report['comparison_source_generation']={'all_sources_current':not drift,'changed_sources':drift,
        'manifest':fingerprint(manifest_path),'emitted_c':fingerprint(emitted)}
    return current,report,binary

def fixture(case,settings,registry,**limits):
    seed=int(case['seed']);coords=';'.join(','.join(str(v&0xffffffff) for v in p) for p in case['points'])
    fields=['density',str(seed>>32),str(seed&0xffffffff),json.dumps(settings,separators=(',',':')),
        json.dumps(registry,separators=(',',':')),json.dumps(case['expression'],separators=(',',':')),coords,
        str(limits.get('compile_depth',128)),str(limits.get('nodes',4096)),str(limits.get('entries',256)),
        str(limits.get('sampler_fuel',64)),str(limits.get('depth',128))]
    return '|'.join(fields)

def compare(retained_core=None):
    reference=json.loads(REFERENCE.read_text())
    if reference['pin']!='26.3' or reference['status']!='observed':raise ValueError('Actual pinned reference required')
    current,report,binary=checked_build(CURRENT,retained_core);receipts=[]
    def invoke(label,arg):
        output,r=run('density-compare-'+label+'-'+str(time.time_ns()),[binary,'--gpu','off','--threads','1',arg],30)
        receipts.append(r);lines=output.splitlines()
        if len(lines)!=1:raise AssertionError((label,'one output line required'))
        return lines[0]
    counts={'decimal_binary64':0,'compiled_density_bits':0,'refused_boundaries':0}
    for i,case in enumerate(reference['observations']['numbers']):
        got=invoke('number-'+str(i),'number|'+case['token']);expected='double|'+','.join(map(str,case['bits']))
        if got!=expected:raise AssertionError(('number',case['token'],got,expected))
        counts['decimal_binary64']+=1
    for i,case in enumerate(reference['observations']['densities']):
        got=invoke('graph-'+str(i),fixture(case,reference['settings'],reference['registry']))
        expected='density|'+';'.join(map(str,case['bits']))+';'
        if got!=expected:
            actual=got.removeprefix('density|').rstrip(';').split(';')
            differences=[{'point':p,'actual':a,'expected':e} for p,a,e in zip(case['points'],actual,case['bits']) if a!=str(e)]
            raise AssertionError(('density',case['id'],case['seed'],differences[:20],got if not got.startswith('density|') else ''))
        counts['compiled_density_bits']+=len(case['bits'])
    for i,case in enumerate(reference['refusals']):
        got=invoke('refusal-'+str(i),fixture(case,reference['settings'],case.get('registry',reference['registry']),**case.get('limits',{})))
        if not got.startswith(case['prefix']):raise AssertionError(('refusal',case['id'],got,case['prefix']))
        counts['refused_boundaries']+=1
    import reference_worldgen_density_noise as DN
    dn_current,dn_report,dn_binary=checked_build(WORK/'density-noise-harness-native-current.json')
    dn_counts={'constructors':0,'scalars':0,'refusals':0,'public_api_scalar_bits':0,'permutation_words':0}
    dn_rows={row['id']:row for row in reference['observations']['density_noise']['cases']}
    for i,case in enumerate(reference['density_noise_input']):
        output,r=run('density-noise-compare-'+str(i)+'-'+str(time.time_ns()),[dn_binary,'--gpu','off','--threads','1',DN.fixture(case)],30)
        receipts.append(r);comparison=DN.check_native(case,dn_rows[case['id']],output)
        key='constructors' if case['kind']=='normal' else 'refusals'
        dn_counts[key]+=1;dn_counts['scalars']+=len(case.get('coordinates',[])) if key=='constructors' else 0
        dn_counts['permutation_words']+=comparison.get('permutation_words',0)
        if key=='constructors':
            output,r=run('density-noise-api-compare-'+str(i)+'-'+str(time.time_ns()),[dn_binary,'--gpu','off','--threads','1',DN.fixture(case,'api')],30)
            receipts.append(r);checked=DN.check_native(case,dn_rows[case['id']],output,mode='api')
            dn_counts['public_api_scalar_bits']+=checked['scalar_words']
    result={'status':'passed','pin':'26.3','comparisons':counts,'normal_noise':dn_counts,'reference':fingerprint(REFERENCE),
        'native':{'binary':fingerprint(binary),'report':fingerprint(Path(current['report'])),'cache_key':report['cache_key'],'timings':report['timings'],
            'source_pins':[d for d in report['dependencies'] if d['kind'] in ('bend','base')],
            'source_generation':report['comparison_source_generation']},
        'normal_noise_native':{'binary':fingerprint(dn_binary),'cache_key':dn_report['cache_key'],'source_generation':dn_report['comparison_source_generation']},
        'native_process_count':len(receipts),'native_seconds':sum(r['seconds'] for r in receipts),
        'all_groups_absent':all(r['group_absent'] and r['leader_reaped'] for r in receipts),
        'scope':'Actual loaded supported density DAGs, binary64 decoding, seeded NormalNoise owners and scalar values. No full final-density, interpolation, spline, aquifer, material, feature or chunk-population claim.'}
    raw=WORK/('density-native-comparisons-'+str(time.time_ns())+'.json');write_json(raw,{'result':result,'processes':receipts})
    result['raw_receipt']={'path':str(raw.relative_to(ROOT)),**fingerprint(raw)};write_json(ROOT/'evidence/worldgen-density-native.json',result)
    return {'status':'passed','comparisons':counts,'normal_noise':dn_counts,'seconds':result['native_seconds']}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);mode=parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--source-check',action='store_true');mode.add_argument('--build',action='store_true');mode.add_argument('--compare-cached',action='store_true')
    parser.add_argument('--retained-core',type=Path,help='Compare the built generation when only Core changed; require its exact retained original bytes and record the distinct source scope.')
    args=parser.parse_args()
    if args.retained_core and not args.compare_cached:parser.error('--retained-core requires --compare-cached')
    print(json.dumps(source_check() if args.source_check else build() if args.build else compare(args.retained_core),sort_keys=True))
