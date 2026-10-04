#!/usr/bin/env python3
"""Check and build the actual loaded-router/biome consumer and compare Java words.

Uses the ordinary content-keyed native builder and existing bounded receiver.
The host has no density, noise, quantizer or biome-search implementation.
"""
from __future__ import annotations
import argparse, copy, json, sys, time
from pathlib import Path
from reference_inventory import ROOT, canonical, fingerprint, write_json
from reference_superflat_probe import WORK, run
import test_worldgen_density as D

ENTRY=ROOT/'tests/worldgen_density_router.bend'
REFERENCE=ROOT/'reference/worldgen_density_router.json'
CURRENT=WORK/'density-router-native-current.json'
NATIVE_PREFIX=[]

def source_check():
    # Reuse the already exercised read-only production closure check unchanged.
    D.ENTRY=ENTRY
    return D.source_check()

def build():
    token=str(time.time_ns());directory=WORK/('density-router-native-'+token);directory.mkdir()
    binary=directory/'worldgen-density-router';report=directory/'native-build.json'
    output,process=run('density-router-native-build-'+token,[sys.executable,ROOT/'tools/build_native.py',ENTRY,'-o',binary,'--report',report],600)
    write_json(CURRENT,{'binary':str(binary),'report':str(report),'process':process,'binary_sha256':fingerprint(binary)['sha256']})
    return {'status':'passed','seconds':process['seconds'],'binary':str(binary),'report':str(report)}

def fixture(case,settings,resources,mode,route,queries,**limits):
    selected=copy.deepcopy(settings);selected['noise_router']=case['router']
    value={'mode':mode,'route':route,'seed':[int(case['seed'])>>32,int(case['seed'])&0xffffffff],
      'settings':selected,'resources':resources,'queries':[[x&0xffffffff for x in q] for q in queries],
      'compile_depth':128,'nodes':8192,'entries':1024,'fuel':64,'depth':128}
    value.update(limits)
    return value

def compare():
    reference=json.loads(REFERENCE.read_text());base=json.loads((ROOT/'reference/worldgen_density.json').read_text());climate=json.loads((ROOT/'reference/worldgen_climate.json').read_text())
    for row in [reference,base,climate]:
        if row['pin']!='26.3' or row['status']!='observed':raise ValueError('Actual pinned26.3 reference required')
    pointer,report,binary=D.checked_build(CURRENT);observed={row['id']:row['results'] for row in reference['observations']['cases']}
    native_prefix=pointer.get('native_prefix',NATIVE_PREFIX)
    token=str(time.time_ns());directory=WORK/('density-router-compare-'+token);directory.mkdir();receipts=[];comparisons=[]
    counts={'eight_root_float_words':0,'six_axis_float_words':0,'six_axis_quantized_longs':0,'loaded_biome_queries':0,'column_float_words':0,'loaded_sloped_cheese_column_words':0,'shared_reference_scenarios':0,'refused_boundaries':0}
    def invoke(label,value):
        path=directory/(label+'.json');path.write_bytes(canonical(value)+b'\n')
        output,receipt=run('density-router-native-'+label+'-'+token,[binary,'--gpu','off','--threads','1',*native_prefix,path],120)
        receipts.append(receipt);comparisons.append({'label':label,'input':fingerprint(path),'execution':receipt});return output.splitlines()
    for case in reference['inputs']:
        rows=observed[case['id']]
        if case['kind'].startswith('eight'):
            route='full-unblended' if case['kind']=='eight-unblended' else 'full'
            lines=invoke(case['id'],fixture(case,base['settings'],base['registry'],'all',route,case['points']))
            expected=['VALUES|'+','.join(map(str,row['float_bits'])) for row in rows]
            if len(lines)!=len(expected)+1 or lines[1:]!=expected:raise AssertionError((case['id'],'eight roots',lines[:3],expected[:2]))
            if not lines[0].startswith('META|'):raise AssertionError((case['id'],'metadata missing'))
            if case['id']=='all-roots-share-loaded-reference':
                roots=lines[0].split('|')[1].split(',')
                if len(roots)!=8 or len(set(roots))!=1:raise AssertionError(('shared references were not interned',lines[0]))
                exact_nodes=int(lines[0].split('|')[3])
                bounded=invoke(case['id']+'-one-graph-budget',fixture(case,base['settings'],base['registry'],'all','full',case['points'],nodes=exact_nodes))
                if bounded!=lines:raise AssertionError(('shared root lowering exceeded one-graph node budget',exact_nodes,bounded[:2]))
                counts['shared_reference_scenarios']+=1
            counts['eight_root_float_words']+=len(rows)*8
            column=invoke(case['id']+'-column',fixture(case,base['settings'],base['registry'],'column',route,[[0,0,-64,64,2]]))
            wanted='COLUMN|'+json.dumps(case['router']['final_density'],separators=(',',':'))+'|'+','.join(str(row['float_bits'][4]) for row in rows[:2])
            if len(column)!=2 or column[1]!=wanted:raise AssertionError((case['id'],'actual Column facade',column,wanted))
            counts['column_float_words']+=2
            if case['id'].startswith('loaded-sloped-cheese-'):
                counts['loaded_sloped_cheese_column_words']+=2
        else:
            lines=invoke(case['id']+'-climate',fixture(case,base['settings'],base['registry'],'climate','unblended',[row['block'] for row in rows]))
            expected=['CLIMATE|'+','.join(map(str,row['float_bits']))+'|'+';'.join(','.join(map(str,word)) for word in row['quantized']) for row in rows]
            if len(lines)!=len(expected)+1 or lines[1:]!=expected:raise AssertionError((case['id'],'actual six climate',lines[:3],expected[:2]))
            if not lines[0].endswith('|no-blending'):raise AssertionError(('explicit policy not retained',lines[0]))
            counts['six_axis_float_words']+=len(rows)*6
            counts['six_axis_quantized_longs']+=len(rows)*6
            value=fixture(case,base['settings'],base['registry'],'biome','biome',case['quarts'])
            value.update({'preset_key':climate['observations']['key'],'preset_definition':climate['observations']['definition'],'preset_entries':climate['observations']['entries']})
            lines=invoke(case['id']+'-biome',value)
            expected=['BIOME|'+row['biome']+'|'+str(row['index'])+'|'+','.join(map(str,row['fitness'])) for row in rows]
            if len(lines)!=len(expected)+1 or lines[1:]!=expected:raise AssertionError((case['id'],'actual preset join',lines[:3],expected[:2]))
            counts['loaded_biome_queries']+=len(rows)
    all_case=reference['inputs'][0];climate_case=next(row for row in reference['inputs'] if row['kind']=='climate')
    refusals=[('zero-compile-depth',fixture(all_case,base['settings'],base['registry'],'all','full',[],compile_depth=0),'FAIL|density expression exceeds caller reference/depth budget'),
      ('small-shared-node-budget',fixture(all_case,base['settings'],base['registry'],'all','full',[],nodes=1),'FAIL|density DAG exceeds caller node budget'),
      ('zero-evaluation-depth',fixture(all_case,base['settings'],base['registry'],'all','full',[[0,0,0]],depth=0),'FAIL|density evaluation exceeds caller depth budget'),
      ('missing-final-climate-column',fixture(climate_case,base['settings'],base['registry'],'column','unblended',[[0,0,0,1,1]]),'FAIL|final-density column root was not compiled'),
      ('missing-eight-climate-outputs',fixture(climate_case,base['settings'],base['registry'],'all','unblended',[[0,0,0]]),'FAIL|full density router outputs were not compiled'),
      ('selected-shipped-full-router-refusal',fixture(climate_case,base['settings'],base['registry'],'all','full',[]),'FAIL|')]
    wrong_identity=fixture(climate_case,base['settings'],base['registry'],'biome','biome',[])
    wrong_identity.update({'preset_key':'bendex:wrong','preset_definition':climate['observations']['definition'],'preset_entries':climate['observations']['entries']})
    refusals.append(('loaded-preset-identity-mismatch',wrong_identity,'FAIL|multi-noise biome preset identity or loaded definition mismatch'))
    empty_table=fixture(climate_case,base['settings'],base['registry'],'biome','biome',[])
    empty_table.update({'preset_key':climate['observations']['key'],'preset_definition':climate['observations']['definition'],'preset_entries':[]})
    refusals.append(('empty-loaded-parameter-table',empty_table,'FAIL|climate parameter list must be nonempty'))
    for label,value,wanted in refusals:
        lines=invoke(label,value)
        if not lines or lines[-1]!=wanted and not (label=='selected-shipped-full-router-refusal' and lines[0].startswith(wanted)):
            raise AssertionError((label,lines,wanted))
        counts['refused_boundaries']+=1
    result={'schema':1,'status':'passed','pin':'26.3','counts':counts,'reference':fingerprint(REFERENCE),
      'density_reference':fingerprint(ROOT/'reference/worldgen_density.json'),'climate_reference':fingerprint(ROOT/'reference/worldgen_climate.json'),
      'build':{'binary':fingerprint(binary),'report':fingerprint(Path(pointer['report'])),'cache_key':report['cache_key'],'timings':report['timings'],
        'source_pins':[d for d in report['dependencies'] if d['kind'] in ('bend','base')],'source_generation':report['comparison_source_generation']},
      'comparisons':comparisons,'native_seconds':sum(r['seconds'] for r in receipts),
      'all_groups_absent':all(r['leader_reaped'] and r['group_absent'] for r in receipts),'helper':fingerprint(Path(__file__).resolve()),
      'scope':'Actual shared eight-root loaded DAG/seeded pool and Column facade for supported selected expressions; actual six shipped unblended Overworld climate outputs and loaded preset biome/index/fitness join. The shipped full router is explicitly refused; final normal chunk population remains unavailable.'}
    raw=directory/'result.json';write_json(raw,result);compact={k:v for k,v in result.items() if k!='comparisons'}
    compact['comparisons']=[{'label':r['label'],'seconds':r['execution']['seconds']} for r in comparisons]
    compact['raw_receipt']={'path':str(raw.relative_to(ROOT)),**fingerprint(raw)};write_json(ROOT/'evidence/worldgen-density-router-native.json',compact)
    return {'status':'passed','counts':counts,'native_seconds':result['native_seconds']}

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);mode=parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--source-check',action='store_true');mode.add_argument('--build',action='store_true');mode.add_argument('--compare-cached',action='store_true');args=parser.parse_args()
    print(json.dumps(source_check() if args.source_check else build() if args.build else compare(),sort_keys=True))
