#!/usr/bin/env python3
"""Compare actual Bend climate table/tree/search with actual pinned Java data.

No Python fitness, nearest lookup, tree building or result substitution exists.
"""
from __future__ import annotations
import argparse, hashlib, json, time
from pathlib import Path
from reference_inventory import ROOT, canonical, fingerprint, write_json
from reference_superflat_probe import WORK, run
REFERENCE=ROOT/'reference/worldgen_climate.json'

def fixture(case,queries,warm,key=None):
    router=json.loads((ROOT/'reference/normal_overworld_noise.json').read_text())['installed_entries']['data/minecraft/worldgen/noise_settings/overworld.json']['json']['noise_router']
    return {'key':key or case.get('key','minecraft:overworld'),'definition':case.get('definition',{'preset':'minecraft:overworld'}),
      'entries':case['entries'],'queries':[q['target'] for q in queries],'warm':warm,'router':router}

def cached_binary():
    pointer=json.loads((WORK/'worldgen-climate-native-current.json').read_text())
    report=json.loads(Path(pointer['report']).read_text());binary=Path(pointer['binary'])
    if hashlib.sha256(binary.read_bytes()).hexdigest()!=report['binary_sha256']:raise RuntimeError('Climate native bytes changed')
    for d in report['dependencies']:
        if d['kind'] in ('bend','base') and hashlib.sha256(Path(d['lookup']).read_bytes()).hexdigest()!=d['sha256']:
            raise RuntimeError('Climate build source changed: '+d['lookup'])
    return pointer,report,binary

def compare():
    reference=json.loads(REFERENCE.read_text());case=reference['observations']
    if reference['pin']!='26.3' or reference['status']!='observed':raise ValueError('Actual pinned Java climate observation required')
    pointer,report,binary=cached_binary();receipts=[];results=[];token=str(time.time_ns())
    directory=WORK/('worldgen-climate-native-compare-'+token);directory.mkdir()
    scenarios=[('overworld-warm',case,case['warm'],True,None),('overworld-cold',case,case['cold'],False,None),
      ('distinct-leaf-ties',case['custom'],case['custom']['queries'],True,'bendex:distinct-leaf-ties')]
    for extra in case.get('extra',[]):
        scenarios.extend([(extra['key']+'-warm',extra,extra['warm'],True,extra['key']),
          (extra['key']+'-cold',extra,extra['cold'],False,extra['key'])])
    for i,(label,values,queries,warm,key) in enumerate(scenarios):
        input_path=directory/(str(i)+'-input.json');input_path.write_bytes(canonical(fixture(values,queries,warm,key))+b'\n')
        stdout,receipt=run('worldgen-climate-native-'+str(i)+'-'+token,[str(binary),'--gpu','off','--threads','1',input_path],120)
        receipts.append(receipt);lines=stdout.splitlines()
        if len(lines)!=len(queries)+1 or not lines[0].startswith('TREE|'):raise AssertionError((label,'tree/results count',len(lines),len(queries)+1))
        actual_tree=json.loads(lines[0][len('TREE|'):])
        if actual_tree!=values['tree']:
            differences=[{'node':j,'actual':a,'expected':b} for j,(a,b) in enumerate(zip(actual_tree,values['tree'])) if a!=b]
            raise AssertionError((label,'constructed-tree',len(actual_tree),len(values['tree']),differences[:4]))
        for j,(line,expected) in enumerate(zip(lines[1:],queries)):
            if 'exception' in expected:
                wanted='FAIL|climate tree search produced no leaf'
            else:
                index=expected['index'];biome=values['entries'][index]['biome']
                wanted='RESULT|'+str(index)+'|'+biome+'|'+','.join(map(str,expected['fitness']))
            if line!=wanted:raise AssertionError((label,'query',j,'target',expected['target'],'actual',line,'expected',wanted))
        results.append({'label':label,'entries':len(values['entries']),'tree_nodes':len(actual_tree),'queries':len(queries),
          'input':fingerprint(input_path),'execution':receipt})
    result={'status':'passed','pin':'26.3','reference':fingerprint(REFERENCE),'helper':fingerprint(Path(__file__).resolve()),
      'build':{'binary':fingerprint(binary),'report':fingerprint(Path(pointer['report'])),'cache_key':report['cache_key'],
        'cache_hit':report['cache_hit'],'timings':report['timings'],'retries':report['retries'],
        'source_pins':[d for d in report['dependencies'] if d['kind']=='bend']},
      'comparisons':results,'actual_tree_nodes_compared':sum(r['tree_nodes'] for r in results),
      'actual_queries_compared':sum(r['queries'] for r in results),'native_seconds':sum(p['seconds'] for p in receipts),
      'all_groups_absent':all(p['leader_reaped'] and p['group_absent'] for p in receipts),
      'scope':'Actual decoded preset table, stable19-child tree bounds/order, exact selected leaf/biome/Java-long fitness through cold/warm history; six axis quantization composition retained; compiled climate graph and complete normal population remain dependencies'}
    raw=directory/'result.json';write_json(raw,result)
    compact={k:v for k,v in result.items() if k!='comparisons'}
    compact['comparisons']=[{k:v for k,v in r.items() if k not in ('execution','input')} for r in results]
    compact['raw_receipt']={'path':str(raw.relative_to(ROOT)),**fingerprint(raw)}
    write_json(ROOT/'evidence/worldgen-climate-native.json',compact)
    return {'status':'passed','tree_nodes':result['actual_tree_nodes_compared'],'queries':result['actual_queries_compared'],'native_seconds':result['native_seconds']}
if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--compare-cached',required=True,action='store_true');parser.parse_args();print(json.dumps(compare(),sort_keys=True))
