#!/usr/bin/env python3
"""Compare actual Bend producers with retained official Java observations.

This helper has no noise, climate or terrain implementation. It dispatches the
production Bend harnesses and compares complete returned scalar/owner fields.
"""
from __future__ import annotations
import argparse, hashlib, json, time
from pathlib import Path
from reference_inventory import ROOT, canonical, fingerprint, write_json
from reference_superflat_probe import WORK, run

REFERENCE=ROOT/'reference/normal_overworld_noise.json'

def seed_words(seed):
    value=int(seed)
    return [value>>32,value&0xffffffff]

def random_text(record):
    words=record['words']
    if record['kind']=='xoroshiro': words=[v for pair in words for v in pair]
    return record['kind']+','+','.join(map(str,words))

def swap(word):
    return int.from_bytes(int(word).to_bytes(4,'big'),'little')

def read_words(text,separator=','):
    parts=text.split(separator)
    if parts[-1]=='': parts.pop()
    return [int(v) for v in parts]

def suite(executor):
    reference=json.loads(REFERENCE.read_text()); observations=reference['observations']
    if reference['pin']!='26.3' or reference['status']!='observed': raise ValueError('Pinned actual observation required')
    processes=[]; comparisons={'md5':0,'named_streams':0,'perlin_constructors':0,'perlin_scalar_bits':0,
        'column_samples':0,'climate_quantized_words':0,'refused_boundaries':0}
    def invoke(label,role,args):
        stdout,receipt=executor(label,role,args)
        processes.append(receipt)
        lines=stdout.splitlines()
        if len(lines)!=1: raise AssertionError((label,'one complete output line required',lines))
        return lines[0]
    for index,case in enumerate(observations['hashes']):
        words=[v for pair in case['words'] for v in pair]
        expected='digest,'+','.join(str(swap(v)) for v in words)
        actual=invoke('md5-'+str(index),'seed',['md5',case['name']])
        if actual!=expected: raise AssertionError(('md5',index,actual,expected))
        comparisons['md5']+=1
    for index,case in enumerate(observations['named']):
        args=['root',*map(str,seed_words(case['seed'])),str(int(case['legacy'])),case['name']]
        actual=invoke('named-'+str(index),'seed',args)
        expected=random_text(case['random'])
        if actual!=expected: raise AssertionError(('named',index,actual,expected))
        comparisons['named_streams']+=1
    for index,case in enumerate(observations['perlin']):
        coordinates=';'.join(','.join(str(v) for pair in sample['coordinate_bits'] for v in pair) for sample in case['samples'])
        mode='plain' if case['mode']=='perlin' else 'perlin'
        fields=[mode,*map(str,seed_words(case['seed'])),'0']
        if mode=='perlin': fields+=list(map(str,case['fudge_bits']))
        fields+=['64',coordinates]
        actual=invoke('perlin-'+str(index),'noise',['|'.join(fields)]).split('|')
        expected=['perlin',random_text(case['after']),
            *(','.join(map(str,v)) for v in case['offset_bits']),
            ','.join(map(str,case['permutation']))+',',
            ';'.join(str(v['bits']) for v in case['samples'])+';']
        if actual!=expected: raise AssertionError(('perlin',index,actual,expected))
        comparisons['perlin_constructors']+=1
        comparisons['perlin_scalar_bits']+=len(case['samples'])
        denied=fields.copy(); denied[-2]='0'
        actual=invoke('perlin-fuel-'+str(index),'noise',['|'.join(denied)])
        expected='fail|noise permutation random rejection fuel exhausted|'+random_text(case['before'])
        if actual!=expected: raise AssertionError(('perlin-fuel',index,actual,expected))
        comparisons['refused_boundaries']+=1
    settings=reference['installed_entries']['data/minecraft/worldgen/noise_settings/overworld.json']['json']
    metadata=json.dumps(settings,separators=(',',':'))
    for index,case in enumerate(observations['columns']):
        fields=['column',*map(str,seed_words(case['seed'])),str(case['x']&0xffffffff),str(case['z']&0xffffffff),
            str(case['min_y']&0xffffffff),str(case['step']),str(case['count']),str(case['count']),metadata]
        actual=invoke('column-'+str(index),'noise',['|'.join(fields)]).split('|')
        expected=['column','minecraft:overworld/base_3d_noise',str(case['x']&0xffffffff),str(case['z']&0xffffffff),
            str(case['min_y']&0xffffffff),str(case['step']),','.join(map(str,case['bits']))+',']
        if actual!=expected:
            if len(actual)==7 and actual[:6]==expected[:6]:
                got=read_words(actual[-1]); wanted=case['bits']
                differing=[{'sample':i,'y':case['min_y']+i*case['step'],'actual':a,'expected':b} for i,(a,b) in enumerate(zip(got,wanted)) if a!=b]
                raise AssertionError(('column',index,'actual_count',len(got),'expected_count',len(wanted),'differences',differing))
            raise AssertionError(('column',index,actual,expected))
        comparisons['column_samples']+=len(case['bits'])
    for index,case in enumerate(observations['climate']):
        actual=invoke('climate-'+str(index),'noise',['climate|'+'|'.join(map(str,case['float_bits']))]).split('|')
        expected=['climate',*(','.join(map(str,pair)) for pair in case['quantized'])]
        if actual!=expected: raise AssertionError(('climate',index,actual,expected))
        comparisons['climate_quantized_words']+=len(case['quantized'])
    for index,(limit,text,message) in enumerate([(0,'a','worldgen seed name exceeds byte budget'),
            (3,'abcd','worldgen seed name exceeds byte budget'),(64,'é','worldgen seed name must be ASCII')]):
        actual=invoke('name-boundary-'+str(index),'seed',['budget',str(limit),'0','0','0','0',text])
        if actual!='fail,'+message: raise AssertionError(('name-boundary',actual,message))
        comparisons['refused_boundaries']+=1
        actual=invoke('legacy-name-boundary-'+str(index),'seed',['legacy-budget',str(limit),'0','0',text])
        if actual!='fail,'+message: raise AssertionError(('legacy-name-boundary',actual,message))
        comparisons['refused_boundaries']+=1
    return {'status':'passed','comparisons':comparisons,'processes':processes,
        'reference':fingerprint(REFERENCE),'helper':fingerprint(Path(__file__).resolve()),
        'scope':'Exact returned bits/constructors for retained official Java seed, Perlin and real base_3d_noise column observations; climate quantization only, not compiled climate or biome-search parity; no final terrain generation claim'}

def cached_executor():
    builds={}
    for role in ('seed','noise'):
        current=json.loads((WORK/('normal-'+role+'-native-current.json')).read_text())
        report=json.loads(Path(current['report']).read_text()); binary=Path(current['binary'])
        if hashlib.sha256(binary.read_bytes()).hexdigest()!=report['binary_sha256']:
            raise RuntimeError('Native artifact bytes changed')
        for dependency in report['dependencies']:
            if dependency['kind'] in ('bend','base'):
                if hashlib.sha256(Path(dependency['lookup']).read_bytes()).hexdigest()!=dependency['sha256']:
                    raise RuntimeError('Actual Bend build input changed: '+dependency['lookup'])
        builds[role]={'current':current,'report':report,'binary':binary}
    def execute(label,role,args):
        stdout,receipt=run('normal-native-compare-'+label+'-'+str(time.time_ns()),
            [str(builds[role]['binary']),'--gpu','off','--threads','1',*args],30)
        return stdout,receipt
    return execute,builds

def compare_cached():
    execute,builds=cached_executor()
    try: result=suite(execute)
    except Exception as error:
        write_json(WORK/('normal-native-comparison-failure-'+str(time.time_ns())+'.json'),
            {'status':'failed','error':repr(error),'reference':fingerprint(REFERENCE),
             'builds':{k:{'binary':str(v['binary']),'report':v['current']['report']} for k,v in builds.items()}})
        raise
    result['builds']={role:{'binary':fingerprint(value['binary']),
        'report':fingerprint(Path(value['current']['report'])),
        'cache_key':value['report']['cache_key'],'cache_hit':value['report']['cache_hit'],
        'retries':value['report']['retries'],'timings':value['report']['timings'],
        'source_pins':[d for d in value['report']['dependencies'] if d['kind']=='bend']}
        for role,value in builds.items()}
    raw=WORK/('normal-native-comparison-'+str(time.time_ns())+'.json'); write_json(raw,result)
    compact={key:value for key,value in result.items() if key!='processes'}
    compact['raw_receipt']={'path':str(raw.relative_to(ROOT)),**fingerprint(raw)}
    compact['native_process_count']=len(result['processes'])
    compact['native_seconds']=sum(p['seconds'] for p in result['processes'])
    compact['all_groups_absent']=all(p['group_absent'] and p['leader_reaped'] for p in result['processes'])
    write_json(ROOT/'evidence/normal-overworld-noise-native.json',compact)
    return {'status':result['status'],'comparisons':result['comparisons'],'native_process_count':compact['native_process_count'],'seconds':compact['native_seconds']}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compare-cached',action='store_true',required=True)
    parser.parse_args()
    print(json.dumps(compare_cached(),sort_keys=True))
