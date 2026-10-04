#!/usr/bin/env python3
"""Build one immutable production-consumer closure and compare actual Java words."""
from __future__ import annotations
import argparse,hashlib,json,os,shutil,subprocess,sys,time
from pathlib import Path
from reference_inventory import ROOT,fingerprint,write_json
from reference_superflat_probe import WORK,run
import test_worldgen_density as D

ENTRY=ROOT/'tests/worldgen_density_integration.bend'
CURRENT=WORK/'density-integration-native-current.json'
REFERENCE=ROOT/'reference/worldgen_density_intervals.json'

def publish_pointer(pointer):
    write_json(CURRENT,pointer)
    for name,prefix in [('density-spline-native-current.json',[]),('density-router-native-current.json',['router'])]:write_json(WORK/name,{**pointer,'native_prefix':prefix})

def source_check():
    D.ENTRY=ENTRY
    return D.source_check()

def build():
    token=str(time.time_ns());directory=WORK/('density-integration-native-'+token);directory.mkdir();source=directory/'source';source.mkdir()
    pins=D.closure(ENTRY);mapping=[]
    for path,pin in pins.items():
        if path.is_relative_to(ROOT):
            target=source/path.relative_to(ROOT);target.parent.mkdir(parents=True,exist_ok=True);shutil.copyfile(path,target)
            if fingerprint(target)!=pin:raise RuntimeError('Source changed during immutable copy: '+str(path))
            mapping.append({'original':str(path),'snapshot':str(target),**pin})
        else:mapping.append({'original':str(path),'snapshot':str(path),**pin})
    for path,pin in pins.items():
        if fingerprint(path)!=pin:raise RuntimeError('Source changed before native build: '+str(path))
    map_path=directory/'source-map.json';write_json(map_path,mapping)
    binary=directory/'worldgen-density-integration';report=directory/'native-build.json'
    output,process=run('density-integration-native-build-'+token,[sys.executable,ROOT/'tools/build_native.py',source/'tests/worldgen_density_integration.bend','-o',binary,'--report',report],600)
    pointer={'binary':str(binary),'report':str(report),'process':process,'binary_sha256':fingerprint(binary)['sha256'],'frozen_sources':{'mapping':str(map_path),'mapping_pin':fingerprint(map_path)}}
    publish_pointer(pointer)
    return {'status':'passed','seconds':process['seconds'],'binary':str(binary),'report':str(report),'source_map':str(map_path)}

def build_private(map_path):
    """Reuse reviewed012 CPU producer on the retained failed ordinary closure."""
    import build_native as Builder
    import test_remote_resource_client as Receiver
    map_path=map_path.resolve();mapping=json.loads(map_path.read_text())
    for row in mapping:
        if fingerprint(Path(row['snapshot']))!={k:row[k] for k in ('file','bytes','sha1','sha256')}:
            raise RuntimeError('Retained ordinary compiler input changed: '+row['snapshot'])
    entry=next(Path(row['snapshot']) for row in mapping if row['original']==str(ENTRY))
    old=ROOT/'build/compiler-producer-diagnostic-012';prior=json.loads((old/'manifest.json').read_text())
    original={p:sha for p,sha in prior['files'].items() if not Path(p).is_relative_to(ROOT)}
    for path,expected in original.items():
        if fingerprint(Path(path))['sha256']!=expected:raise RuntimeError('Reviewed original compiler/tool changed: '+path)
    token=str(time.time_ns());directory=WORK/('density-integration-private-native-'+token);directory.mkdir()
    for name in ('comp_instrumented.ts','run.py','diagnose.mjs'):
        if fingerprint(old/name)['sha256']!=prior['files'][str(old/name)]:raise RuntimeError('Reviewed012 producer changed: '+name)
        body=(old/name).read_text().replace(str(old),str(directory))
        if name=='diagnose.mjs':body=body.replace(str(directory/'source/remote_resource_server.bend'),str(entry))
        if name=='run.py':
            # The ordinary receiver just exposed EPERM on killpg(0) after the
            # owned group exited. Keep that error and verify actual group rows.
            body=body.replace('except ProcessLookupError:absent=True',
                'except ProcessLookupError:absent=True\nexcept PermissionError as error:\n cleanup_probe_error={"type":type(error).__name__,"errno":error.errno,"message":str(error)}\n observed=subprocess.run(["/bin/ps","-axo","pid=,pgid=,stat="],capture_output=True,text=True,check=True).stdout.splitlines()\n absent=not any(len(parts:=row.split())==3 and int(parts[1])==p.pid and not parts[2].startswith("Z") for row in observed)')
            body=body.replace("'scope':manifest['scope']}","'scope':manifest['scope'],'cleanup_probe_error':locals().get('cleanup_probe_error')}")
        (directory/name).write_text(body)
    inputs={**original,**{str(Path(row['snapshot'])):row['sha256'] for row in mapping},str(map_path):fingerprint(map_path)['sha256'],
        **{str(directory/name):fingerprint(directory/name)['sha256'] for name in ('comp_instrumented.ts','run.py','diagnose.mjs')}}
    limits={'heap_mib':6144,'total_seconds':600,'producer_stall_seconds':90,'sampled_rss_bytes':8589934592}
    manifest=directory/'manifest.json';write_json(manifest,{'scope':'Actual immutable density Interval/Spline/Router/Biome/Column consumer through reviewed012 private CPU queue/zero-gap producer. Original compiler unchanged; no installed content-cache promotion or compiler-wide certification.','files':inputs,'limits':limits,'entry':str(entry),'ordinary_source_map':str(map_path)})
    before_work=Receiver.WORK;Receiver.WORK=directory
    try:
        emission=Receiver.bounded([sys.executable,str(directory/'run.py')],605,'emission-process');Receiver.process_ok(emission)
        receipt=json.loads((directory/'receipt.json').read_text())
        if receipt['returncode']!=0 or receipt['termination_reason'] is not None or not receipt['complete_C'] or not receipt['group_absent']:
            raise RuntimeError('Private density C producer failed; retained without retry: '+str(directory))
        loaded=json.loads((directory/'loaded-source-pins.json').read_text());after=json.loads((directory/'final-source-pins.json').read_text())
        if loaded!=after:raise RuntimeError('Private density loaded source drift')
        for path,sha in after.items():
            if fingerprint(Path(path))['sha256']!=sha:raise RuntimeError('Private density source changed after emission: '+path)
        c=directory/'diagnostic.c';cpin=fingerprint(c);Builder.guard_route(c.read_text())
        binary=directory/'worldgen-density-integration';sdk=subprocess.check_output(['/usr/bin/xcrun','--show-sdk-path'],text=True).strip()
        command=['/usr/bin/env','SDKROOT='+sdk,'/usr/bin/clang','-std=c11','-O3',str(c),'-lpthread','-lm','-o',str(binary)]
        native=Receiver.bounded(command,300,'native-process');Receiver.process_ok(native)
        if fingerprint(c)!=cpin:raise RuntimeError('Private density C changed while compiling')
    finally:Receiver.WORK=before_work
    retained=[{'path':str(path),**fingerprint(path)} for path in [manifest,directory/'receipt.json',directory/'comp_instrumented.ts',directory/'run.py',directory/'diagnose.mjs',directory/'loaded-source-pins.json',directory/'final-source-pins.json',directory/'emission-process/result.full.json',directory/'native-process/result.full.json']]+[{'path':path,**fingerprint(Path(path))} for path in original]
    report=directory/'native-build.json'
    write_json(report,{'schema':1,'binary_sha256':fingerprint(binary)['sha256'],'emitted_c_sha256':cpin['sha256'],'cache_key':None,'cache_hit':False,
      'dependencies':[{'kind':'base' if Path(row['snapshot']).name=='base.bend' else 'bend','lookup':row['snapshot'],'sha256':row['sha256']} for row in mapping],
      'timings':{'emission_seconds':receipt['seconds'],'native_seconds':native['seconds']},
      'private_build':{'manifest_path':str(manifest),'emitted_c_path':str(c),'retained_inputs':retained,'product_cache_promoted':False,'reviewed_recipe':str(old),'ordinary_attempt_source_map':str(map_path),'emission':emission,'native':native}})
    pointer={'binary':str(binary),'report':str(report),'binary_sha256':fingerprint(binary)['sha256'],'private_build':{'report_pin':fingerprint(report)},'frozen_sources':{'mapping':str(map_path),'mapping_pin':fingerprint(map_path)}}
    publish_pointer(pointer)
    summary={'schema':1,'pin':'26.3','status':'built','binary':fingerprint(binary),'C':cpin,'report':{'path':str(report.relative_to(ROOT)),**fingerprint(report)},'source_map':{'path':str(map_path.relative_to(ROOT)),**fingerprint(map_path)},'source_files':len(mapping),'timings':{'emission_seconds':receipt['seconds'],'native_seconds':native['seconds']},'sampled_peak_rss_bytes':receipt['sampled_peak_rss_bytes'],'limits':limits,'cleanup_probe_error':receipt.get('cleanup_probe_error'),'product_cache_promoted':False,'scope':'Actual frozen production density consumers; reviewed private CPU producer after one ordinary native attempt failed. Native numerical comparisons remain separate.'}
    write_json(ROOT/'evidence/worldgen-density-integration-private-build.json',summary)
    return summary

def interval_fixture(row):
    return '|'.join(['interval',row['op'],*(str(v) for key in ['a','b','c'] for v in row[key])])

def coordinate_fixture(row):
    return '|'.join(['coords',row['mode'],*(str(v&0xffffffff) for v in row['point']),*(str(v) for v in row['xz']),*(str(v) for v in row['y']),*(str(v) for v in row['shift'])])

def compare():
    reference=json.loads(REFERENCE.read_text());base=json.loads((ROOT/'reference/worldgen_density.json').read_text())
    if reference['pin']!='26.3' or reference['status']!='observed':raise RuntimeError('Pinned Java observations required')
    pointer,report,binary=D.checked_build(CURRENT);receipts=[];failures=[];counts={'interval_cases':0,'coordinate_cases':0,'raw_binary64_coordinates':0,'compiled_density_graphs':0,'graph_float_words':0,'range_words':0,'loaded_sloped_cheese_column_words':0}
    def invoke(label,arg):
        output,process=run('density-interval-compare-'+label+'-'+str(time.time_ns()),[binary,'--gpu','off','--threads','1',arg],30)
        receipts.append(process);lines=output.splitlines()
        if len(lines)!=1:raise AssertionError(('one output line required',label,lines[:3]))
        return lines[0]
    def check(label,actual,wanted):
        matched=actual.startswith('fail|') if wanted=='fail|' else actual==wanted
        if not matched:failures.append({'id':label,'expected':wanted,'actual':actual})
    observations=reference['observations'];intervals={row['id']:row['observed'] for row in observations['intervals']}
    for row in reference['inputs']['intervals']:
        expected=intervals[row['id']]
        wanted='fail|' if expected.get('refused') else ('float|'+str(expected['bits']) if 'bits' in expected else 'range|'+str(expected['nai']).lower().capitalize()+'|'+str(expected['min_bits'])+','+str(expected['max_bits']))
        check(row['id'],invoke(row['id'],interval_fixture(row)),wanted);counts['interval_cases']+=1
    coordinates={row['id']:row for row in observations['coordinates']}
    for row in reference['inputs']['coordinates']:
        wanted='coords|'+';'.join(','.join(map(str,p)) for p in coordinates[row['id']]['coordinates'])
        check(row['id'],invoke(row['id'],coordinate_fixture(row)),wanted);counts['coordinate_cases']+=1;counts['raw_binary64_coordinates']+=3
    graphs={row['id']:row for row in observations['graphs']}
    import test_worldgen_density_spline as Spline
    for row in reference['inputs']['graphs']:
        observed=graphs[row['id']];case={**row,'expression_json':json.dumps(row['expression'],separators=(',',':'))}
        wanted='density|'+';'.join(map(str,observed['bits']))+';'
        check(row['id'],invoke(row['id'],Spline.spline_fixture(case,base['settings'],base['registry'])),wanted)
        expected=observed['range'];wanted='range|'+str(expected['nai']).lower().capitalize()+'|'+str(expected['min_bits'])+','+str(expected['max_bits'])
        check(row['id']+'-range',invoke(row['id']+'-range',Spline.spline_fixture(case,base['settings'],base['registry'],range=True)),wanted)
        counts['compiled_density_graphs']+=1;counts['graph_float_words']+=len(observed['bits']);counts['range_words']+=2
        if 'column' in row:
            request=row['column'];seed=int(row['seed'])
            arg='|'.join(['column',str(seed>>32),str(seed&0xffffffff),json.dumps(base['settings'],separators=(',',':')),json.dumps(base['registry'],separators=(',',':')),case['expression_json'],*(str(request[key]&0xffffffff) for key in ['x','z','bottom','step','count']),'128','4096','256','64','128'])
            wanted='column|'+case['expression_json']+'|'+','.join(str(request[key]&0xffffffff) for key in ['x','z','bottom','step'])+'|'+';'.join(map(str,observed['column_bits']))+';'
            check(row['id']+'-column',invoke(row['id']+'-column',arg),wanted);counts['loaded_sloped_cheese_column_words']+=len(observed['column_bits'])
    result={'schema':1,'pin':'26.3','status':'passed' if not failures else 'failed','counts':counts,'failures':failures,'reference':fingerprint(REFERENCE),'native_build':report,'executions':receipts,'helper':fingerprint(Path(__file__).resolve()),'scope':'Actual Interval operations, production compiled MinMax/no-blending scalar DAG, and raw binary64 coordinates used by actual production NoiseFunction arithmetic. Numerical boundary comparison; no full normal chunk population or IEEE kernel theorem.'}
    write_json(ROOT/'evidence/worldgen-density-interval-native.json',result)
    if failures:raise AssertionError(failures[:10])
    return {'status':'passed',**counts}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);mode=parser.add_mutually_exclusive_group(required=True);mode.add_argument('--source-check',action='store_true');mode.add_argument('--build',action='store_true');mode.add_argument('--build-private',type=Path);mode.add_argument('--compare',action='store_true');args=parser.parse_args()
    print(json.dumps(source_check() if args.source_check else build() if args.build else build_private(args.build_private) if args.build_private else compare(),sort_keys=True))
