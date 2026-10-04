#!/usr/bin/env python3
"""Independent stored-getter expectations for actual Core-backed Bend lookup.

--preflight performs no emission/native/kernel work. Heavy phases require the
lead's grant. Python constructs fixtures/oracles, never implements game lookup.
"""
from __future__ import annotations
import argparse
import collections
import copy
import json
import os
from pathlib import Path
import random
import signal
import struct
import subprocess
import sys
import time

import reference_block_primitives_probe as R
import test_block_physics as BP
import test_player_record as P
import test_player_look as L
import test_world_codec as WC
import test_nbt as N
from reference_inventory import canonical, fingerprint
from test_persistence import registry_identity

ROOT=R.ROOT
WORK=ROOT/'build/block-physics-world'
ENTRY=ROOT/'tests/block_physics_world.bend'
SOURCE=ROOT/'src/block_physics_world.bend'
BEND=Path('/Users/chuah/.bend/bin/bend')
BINARY=WORK/'tests'
RECEIPT=WORK/'native-build.json'
U32_MAX=(1<<32)-1

def require(ok,message):
    if not ok: raise AssertionError(message)

def sha(data): return P.sha(data)
def sources(): return L.imports([ENTRY])
def word(value): return value & U32_MAX
def double_bits(value): return struct.unpack('>Q',struct.pack('>d',value))[0]
def wide_words(value):
    raw=double_bits(value)
    return [raw>>32,raw & U32_MAX]

def initial_view(with_cache=True):
    body=[]
    for v in [-0.,3.5,-2.5,-.5,3.5,-3.,.5,5.5,-2.,.25,-0.,.125]: body+=wide_words(v)
    body += [0x3f800000,0x40000000,0,1,1,0]
    region=','.join(map(str,[word(-32),word(-16),16,7,8,9]))
    palette='0,1,10,15'
    cache='987:'+region+':'+palette+':'+','.join(map(str,[word(-1),word(-2),word(-3),4,257,9]))+';'
    return ','.join(map(str,body))+'|2147483648,1048576000|'+(palette if with_cache else 'none')+'|'+region+'|'+(cache if with_cache else 'none')

def catalog_signature(info,mode=None,value=None):
    count,states,identity,capacity=15,35723,info['registry_identity'],16
    rows=[','.join(map(str,[r['first'],r['count'],*r['factors']])) for r in info['ranges']]+['0,0,0,0,0']
    if mode=='count': count=value
    elif mode=='states': states=value
    elif mode=='identity': identity='wrong'
    elif mode=='short': capacity=1;rows=['0,1,1058642330,1065353216,1065353216']
    return ','.join(map(str,[count,states,capacity]))+':'+identity+':'+''.join(r+';' for r in rows)

def grid_cell(index):
    section,local=divmod(index,4096)
    return ('minecraft:overworld',section*16+(local & 15),local>>8,(local>>4)&15)

def key_of(cell):
    dim,*xyz=cell
    return dim+'/'+ '/'.join(str(word(v>>4)) for v in xyz)

def initial_world(identity):
    world=WC.empty_world(35723,identity)
    world.update(tick=42,day_time=1000,paused=False,daylight=False,revision=13)
    for section in range(9):
        cells=tuple(i if i<35723 else 0 for i in range(section*4096,(section+1)*4096))
        world['sections'].append({'key':f'minecraft:overworld/{section}/0/0','cells':cells})
    signed=[(('minecraft:overworld',-1,-1,-1),8597),
            (('minecraft:overworld',-17,-17,-17),25173),
            (('minecraft:overworld',-(1<<31),0,0),18632),
            (('minecraft:overworld',(1<<31)-1,(1<<31)-1,(1<<31)-1),14379),
            (('minecraft:overworld',-(1<<31),(1<<31)-1,-17),8668),
            (('minecraft:the_nether',0,0,0),14761),
            (('minecraft:the_end',0,0,0),16822)]
    world['sections'] += [WC.section(key_of(cell),state) for cell,state in signed]
    world['sections'] += [WC.section(key,8597 if i==0 else 25173) for i,key in enumerate(WC.COLLISION_KEYS)]
    require(WC.fnv(WC.COLLISION_KEYS[0])==WC.fnv(WC.COLLISION_KEYS[1]),'independent trie collision fixture')
    world['sections'].sort(key=lambda s:s['key'])
    world['pending']=[
        {'stamp':(1000,7,1),'mutation':{'kind':0,'dimension':'minecraft:overworld','x':160,'y':0,'z':0,'state':8597}},
        {'stamp':(1000,8,2),'mutation':{'kind':1,'dimension':'minecraft:the_nether','x':0,'y':0,'z':0,'state':25173}},
        {'stamp':(1001,3,100),'mutation':{'kind':2,'day_time':999}},
        {'stamp':(1001,3,101),'mutation':{'kind':3,'enabled':True}}]
    world['events']=[{'stamp':(41,9,5),'kind':1,'error':{'kind':3,'key':'minecraft:overworld/10/0/0'}},
                     {'stamp':(40,1,3),'kind':0,'revision':12}]
    raw=N.encode_root(WC.snapshot_root(world))
    parsed=WC.validate(N.parse(raw),35723,identity)
    require(raw==N.encode_root(WC.snapshot_root(parsed)),'independent fixture canonical bytes')
    return world,raw,signed

def oracle_cell(cell,world,actual):
    if cell[0] not in WC.DIMENSIONS:return 'error\tUnknownDimension'
    key=key_of(cell)
    record=next((s for s in world['sections'] if s['key']==key),None)
    if record is None:return 'error\tMissingSection'
    _,x,y,z=cell;index=(x & 15)+((z & 15)<<4)+((y & 15)<<8)
    state=record['cells'][index]
    if state>=35723:return 'error\tInvalidState'
    return 'ok\t'+str(state)+'\t'+BP.raw_expected(actual[state]).split('\t',1)[1]

def oracle_exact(dim,raws,world,actual):
    coords=[]
    for axis,raw in enumerate(raws):
        if not L.finite64(raw):return 'error\tInvalidCoordinate:'+str(axis)
        v=L.exact(raw,64)
        if v.denominator!=1 or v<-(1<<31) or v>(1<<31)-1:return 'error\tInvalidCoordinate:'+str(axis)
        coords.append(int(v))
    return oracle_cell((dim,*coords),world,actual)

def corpus(info):
    WORK.mkdir(parents=True,exist_ok=True)
    actual=R.rows(R.WORK/'actual-0.tsv');world,raw,signed=initial_world(info['registry_identity'])
    (WORK/'world.nbt').write_bytes(raw)
    expected=[];requests=[];manifest=[];checkpoints=[]
    signature=catalog_signature(info);view=initial_view()
    def add(name,category,args,lines):
        id='c'+str(len(requests))
        requests.append('\t'.join(map(str,[id,*args])))
        expected.extend(id+'\t'+v for v in lines)
        manifest.append({'id':id,'name':name,'category':category,'responses':len(lines)})
        return id
    def cell(position,name='cell',category='cell'):
        add(name,category,('cell',position[0],*(word(v) for v in position[1:])),[oracle_cell(position,world,actual)])
    def checkpoint(name):
        path=WORK/(name+'.nbt')
        add(name,'canonical-world',('checkpoint',path),['ok\tcheckpoint'])
        checkpoints.append({'path':str(path),'expected_sha256':sha(N.encode_root(WC.snapshot_root(world)))})
    def inspect(name,cat=signature,current_view=view):
        add(name,'full-owners',('inspect',),['ok\tcatalog\t'+cat,'ok\tview\t'+current_view])
    def counts(name,core=35723,registry=35723,blocks=1286):
        add(name,'metadata-retention',('counts',),['ok\tcounts\t'+','.join(map(str,[core,registry,blocks]))])
    def batch(name,cells):
        path=WORK/(name+'.tsv')
        path.write_text(''.join('\t'.join(map(str,[p[0],*(word(v) for v in p[1:])]))+'\n' for p in cells))
        id=add(name,'batch',('batch',path),['ok\tbatch\t'+str(len(cells))])
        expected.extend(id+':'+str(i)+'\t'+oracle_cell(p,world,actual) for i,p in enumerate(cells))
        manifest[-1]['responses']+=len(cells)
    checkpoint('before');inspect('initial-owners')
    batch('all-states-forward',[grid_cell(i) for i in range(35723)])
    batch('all-states-reverse',[grid_cell(i) for i in reversed(range(35723))])
    rng=random.Random(263105)
    batch('random-signed-and-state',[grid_cell(rng.randrange(35723)) for _ in range(1024)]+[p for p,_ in signed])
    boundary_cells=[p for p,_ in signed]+[('minecraft:overworld',-16,-16,-16),('minecraft:overworld',-32,-32,-32)]
    for key in WC.COLLISION_KEYS:
        dim,*coords=key.split('/');boundary_cells.append((dim,*(int(v)*16 for v in coords)))
    for p in boundary_cells:cell(p,'signed-boundary-or-collision')
    missing=('minecraft:overworld',256,256,256)
    batch('mixed-errors',[grid_cell(1),missing,('custom:void',0,0,0),grid_cell(25173),('minecraft:the_end',256,0,0),grid_cell(8597)])
    batch('empty',[])
    add('exact-limit-65536','batch-limit',('repeat',65536,*grid_cell(8597)),['ok\tbatch\t65536'])
    id=manifest[-1]['id'];expected.extend(id+':'+str(i)+'\t'+oracle_cell(grid_cell(8597),world,actual) for i in range(65536));manifest[-1]['responses']+=65536
    add('over-limit-65537','batch-limit',('repeat',65537,*grid_cell(8597)),['error\tBatchLimit']);cell(grid_cell(8597),'post-limit-recovery')
    for p in [missing,('custom:void',0,0,0),('MINECRAFT:OVERWORLD',0,0,0),('',0,0,0)]:cell(p,'single-missing-or-unknown');cell(grid_cell(25173),'recovery')
    exact_cases=[(double_bits(v),double_bits(0),double_bits(0)) for v in [-0.,0.,1.,15.,16.,-(1<<31),(1<<31)-1,.5,-.5,1e100,-1e100]]
    bad=[1,0x8000000000000001,0x7ff0000000000000,0xfff0000000000000,0x7ff8000000000001,0xfff8000000000001,0x7ff0000000000001,double_bits(2147483648.),double_bits(-2147483649.),double_bits(2147483647.5),double_bits(-2147483648.5),double_bits(1.0000000000000002),double_bits(-1.0000000000000002)]
    for axis in range(3):
        for raw_bits in bad:
            values=[0,0,0];values[axis]=raw_bits;exact_cases.append(tuple(values))
    for i,raws in enumerate(exact_cases):
        values=[n for bits in raws for n in (bits>>32,bits & U32_MAX)]
        add('exact-coordinate-'+str(i),'exact-coordinate',('exact','minecraft:overworld',*values),[oracle_exact('minecraft:overworld',raws,world,actual)])
        cell(grid_cell(8597),'post-exact-recovery')
    for raws in [(0,0,0),(0x7ff8000000000001,0,0)]:
        values=[n for bits in raws for n in (bits>>32,bits & U32_MAX)]
        add('coordinate-dimension-error-order','exact-coordinate',('exact','custom:void',*values),[oracle_exact('custom:void',raws,world,actual)])
    checkpoint('after-primary');inspect('after-primary-owners')
    for kind,value in [('count',0),('count',17),('count',U32_MAX),('states',0),('states',35722),('identity',0),('short',0)]:
        add('forged-catalog','forged-catalog',('forge-catalog',kind,value),['ok\tforge-catalog'])
        bad_signature=catalog_signature(info,kind,value)
        inspect('forged-before',bad_signature)
        add('bad-catalog-single','forged-catalog',('cell',*grid_cell(8597)),['error\tCatalogCorrupt'])
        id=add('bad-catalog-batch','forged-catalog',('repeat',2,*grid_cell(8597)),['ok\tbatch\t2']);expected.extend(id+':'+str(i)+'\terror\tCatalogCorrupt' for i in range(2));manifest[-1]['responses']+=2
        inspect('forged-after',bad_signature)
        add('restore-catalog','forged-catalog',('restore-catalog',R.TABLE),['ok\trestore-catalog']);cell(grid_cell(8597),'post-catalog-recovery');inspect('restored')
    for field,good,error in [('core-count',35723,'CoreStateCount'),('registry-count',35723,'RegistryStateCount'),('block-count',1286,'RegistryIdentityError')]:
        for value in [0,35722 if field!='block-count' else 4097,U32_MAX]:
            add('forge-'+field,'world-metadata',(field,value),['ok\t'+field])
            raw_counts={'core':35723,'registry':35723,'blocks':1286}
            raw_counts[{'core-count':'core','registry-count':'registry','block-count':'blocks'}[field]]=value
            counts('counts-before-rejection',**raw_counts)
            add('reject-'+field,'world-metadata',('cell',*grid_cell(8597)),['error\t'+error])
            counts('counts-after-rejection',**raw_counts)
            add('restore-'+field,'world-metadata',(field,good),['ok\t'+field]);cell(grid_cell(8597),'metadata-owner-recovery')
    foreign=WORK/'foreign-registry.tsv'
    text=R.OFFICIAL.read_text();text=text.replace('minecraft:stone\t','minecraft:temporary_swap\t',1).replace('minecraft:dirt\t','minecraft:stone\t',1).replace('minecraft:temporary_swap\t','minecraft:dirt\t',1);foreign.write_text(text)
    foreign_identity,foreign_count,_=registry_identity(foreign)
    require(foreign_count==35723 and foreign_identity!=info['registry_identity'],'foreign remap does not preserve official identity')
    add('load-foreign','foreign-registry',('registry',foreign),['ok\tregistry'])
    add('reject-foreign','foreign-registry',('cell',*grid_cell(8597)),['error\tForeignRegistry'])
    id=add('reject-foreign-batch','foreign-registry',('repeat',2,*grid_cell(8597)),['error\tForeignRegistry'])
    add('unknown-dimension-before-foreign-registry','error-order',('cell','custom:void',0,0,0),['error\tUnknownDimension'])
    add('nonfinite-before-foreign-registry','error-order',('exact','minecraft:overworld',0x7ff80000,1,0,0,0,0),['error\tInvalidCoordinate:0'])
    add('batch-limit-before-foreign-registry','error-order',('repeat',65537,*grid_cell(8597)),['error\tBatchLimit'])
    add('restore-official','foreign-registry',('registry',R.OFFICIAL),['ok\tregistry']);cell(grid_cell(8597),'foreign-owner-recovery')
    checkpoint('after-defensive');inspect('after-defensive-owners')
    key=key_of(('minecraft:overworld',-17,-17,-17))
    for bad_state in [35723,U32_MAX]:
        add('forge-invalid-cell','invalid-state',('section',key,bad_state),['ok\tsection'])
        add('reject-invalid-cell','invalid-state',('cell','minecraft:overworld',word(-17),word(-17),word(-17)),['error\tInvalidState'])
        cell(grid_cell(8597),'invalid-cell-owner-recovery')
        add('restore-cell','invalid-state',('section',key,25173),['ok\tsection']);cell(('minecraft:overworld',-17,-17,-17),'valid-cell-restored')
    checkpoint('after-invalid-cell')
    add('view-without-palette-cache','view-absence',('view-mode','none'),['ok\tview-mode']);view=initial_view(False)
    for p in [grid_cell(8597),grid_cell(25173),missing]:cell(p,'no-palette-needed')
    inspect('no-palette-cache-owners',current_view=view)
    checkpoint('before-edit')
    add('actual-Core-admit-and-advance','actual-core-edit',('edit',25173),['ok\tcore-edit'])
    world['tick']=43;world['revision']=14;world['events'].insert(0,{'stamp':(43,7,9),'kind':0,'revision':14})
    first=world['sections'][next(i for i,s in enumerate(world['sections']) if s['key']=='minecraft:overworld/0/0/0')]
    first['cells']=(25173,*first['cells'][1:])
    cell(grid_cell(0),'observe-edited-state');checkpoint('after-edit-before-query');cell(grid_cell(0),'repeat-edited-state');checkpoint('after-edit-query');inspect('post-edit-view',current_view=view)
    add('forge-unknown-loaded-section','dimension-gate',('section','custom:void/0/0/0',8597),['ok\tsection'])
    add('reject-loaded-unknown-dimension','dimension-gate',('cell','custom:void',0,0,0),['error\tUnknownDimension']);cell(grid_cell(8597),'unknown-section-recovery')
    expected.append('final\tok\tview-retained\t1')
    (WORK/'requests.tsv').write_text('\n'.join(requests)+'\n')
    (WORK/'expected.tsv').write_text('\n'.join(expected)+'\n')
    P.write_json(WORK/'case-manifest.json',manifest)
    P.write_json(WORK/'checkpoints.json',checkpoints)
    return {'operations':len(requests),'responses':len(expected),'all_states':35723,'complete_state_orders':['forward','reverse'],'categories':dict(collections.Counter(c['category'] for c in manifest)),'exact_coordinate_cases':len(exact_cases)+2,'catalog_forged_owners':7,'checkpoints':len(checkpoints),'section_count_initial':18,'collision_keys':list(WC.COLLISION_KEYS),'foreign_registry_identity':foreign_identity,'world_input':fingerprint(WORK/'world.nbt'),'requests':fingerprint(WORK/'requests.tsv'),'expected':fingerprint(WORK/'expected.tsv'),'case_manifest_sha256':sha((WORK/'case-manifest.json').read_bytes()),'checkpoints_manifest_sha256':sha((WORK/'checkpoints.json').read_bytes()),'batch_inputs':{p.name:fingerprint(p) for p in sorted(WORK.glob('*.tsv')) if p.name in ['all-states-forward.tsv','all-states-reverse.tsv','random-signed-and-state.tsv','mixed-errors.tsv','empty.tsv','foreign-registry.tsv']},'oracle':'Actual pinned Java getter words by observed current Core state; independent signed decomposition/Fraction exact-coordinate and canonical NBT expectations.'}

def tool_closure():
    paths={Path(m.__file__).resolve() for m in list(sys.modules.values()) if getattr(m,'__file__',None) and Path(m.__file__).resolve().parent==ROOT/'tools'}
    return {str(p.relative_to(ROOT)):sha(p.read_bytes()) for p in sorted(paths)}

def receipt_check(source_hashes):
    receipt=json.loads(RECEIPT.read_text());artifact=P.check_receipt(source_hashes,receipt)
    require(sha(BINARY.read_bytes())==receipt['build']['binary_sha256'],'convenience executable changed')
    return receipt,artifact

def build(source_hashes):
    report=WORK/'build.json';cmd=[sys.executable,ROOT/'tools/build_native.py',ENTRY,'-o',BINARY,'--bend',BEND,'--report',report]
    child=subprocess.Popen(list(map(str,cmd)),cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
    print(json.dumps({'phase':'native-build','process_group':child.pid,'limit_seconds':600,'sources_sha256':source_hashes}),flush=True)
    try:out,err=child.communicate(timeout=600)
    except subprocess.TimeoutExpired:os.killpg(child.pid,signal.SIGKILL);child.communicate();raise AssertionError('600s processgroup build timeout')
    require(child.returncode==0,'native build failed '+err.decode()[-2500:]);require(sources()==source_hashes,'source changed during build')
    P.write_json(RECEIPT,{'sources_sha256':source_hashes,'build':json.loads(report.read_text())})
    return receipt_check(source_hashes)

def native(source_hashes,receipt,artifact,prepared):
    expected=(WORK/'expected.tsv').read_bytes();expected_lines=expected.decode().splitlines();checkpoints=json.loads((WORK/'checkpoints.json').read_text());runs=[]
    receipt_faults=BP.receipt_selftests(source_hashes,receipt)
    for i in range(2):
        observed=WORK/f'observed-{i}.tsv';start=time.monotonic()
        with observed.open('wb') as output:
            child=subprocess.Popen([str(artifact),'--gpu','off','--threads','2','--',str(R.OFFICIAL),str(R.TABLE),str(WORK/'world.nbt'),str(WORK/'requests.tsv')],cwd=ROOT,stdout=output,stderr=subprocess.PIPE,start_new_session=True)
            print(json.dumps({'phase':'native-comparison','run':i,'process_group':child.pid,'limit_seconds':120}),flush=True)
            try:_,err=child.communicate(timeout=120)
            except subprocess.TimeoutExpired:os.killpg(child.pid,signal.SIGKILL);child.communicate();raise AssertionError('120s native child timeout')
        execution_seconds=round(time.monotonic()-start,6)
        require(child.returncode==0 and not err,'native failed '+err.decode()[-2500:])
        output=observed.read_bytes();actual_lines=output.decode().splitlines()
        require(len(actual_lines)==len(expected_lines),'response count mismatch')
        for index,(a,b) in enumerate(zip(actual_lines,expected_lines)):
            if a!=b:raise AssertionError(f'response{index} observed={a[:1000]} expected={b[:1000]}')
        require(output==expected,'exact response bytes mismatch')
        checkpoint_observed=[]
        for item in checkpoints:
            p=Path(item['path']);data=p.read_bytes()
            require(sha(data)==item['expected_sha256'],'complete canonical Core checkpoint mismatch '+p.name)
            model=WC.validate(N.parse(data),35723,R.verify_existing()['registry_identity'])
            require(data==N.encode_root(WC.snapshot_root(model)),'independent canonical checkpoint bytes')
            checkpoint_observed.append({'file':p.name,'bytes':len(data),'sha256':sha(data)})
        runs.append({'pid':child.pid,'native_child_seconds':execution_seconds,'comparison_total_seconds':round(time.monotonic()-start,6),'responses':len(actual_lines),'output_sha256':sha(output),'checkpoints':checkpoint_observed})
        receipt_check(source_hashes);require(sources()==source_hashes,'source changed during native runs')
    b=receipt['build'];summary={k:b[k] for k in ('artifact','cache_key','binary_sha256','binary_bytes','emitted_c_sha256','timings')}
    summary.update(compiler={k:v for k,v in b['compiler'].items() if k!='driver_probe'},compiler_driver_probe_sha256=sha(b['compiler']['driver_probe'].encode()),dependency_count=len(b['dependencies']),dependency_manifest_sha256=sha(canonical(b['dependencies'])),ignored_receipt_sha256=sha(RECEIPT.read_bytes()))
    return {'status':'passed','sources_sha256':source_hashes,'build':summary,'runs':runs,'corpus':prepared,'receipt_corruption':receipt_faults,'confidence':'high for measured stored factors and tested owned Core lookup boundaries; no contextual physics claims'}

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    for flag in ['preflight','build-only','skip-build','kernel']:parser.add_argument('--'+flag,action='store_true')
    args=parser.parse_args();reference=R.verify_existing();reference_faults=BP.reference_selftests(reference);prepared=corpus(reference);generation=sources()
    ordinary=[P.bounded_run([BEND,path,'--check-only']) for path in [SOURCE,ENTRY]]
    require(all(r['exit_code']==0 and 'ALL PROOFS CHECK' in r['stdout'] for r in ordinary),'ordinary source/harness failure')
    python_generation=tool_closure()
    preflight={'status':'prepared-native-kernel-unverified','ordinary':ordinary,'sources_sha256':generation,'python_tool_sources_sha256':python_generation,'runner_sha256':sha(Path(__file__).read_bytes()),'reference_file_sha256':sha(R.REFERENCE.read_bytes()),'catalog_table':fingerprint(R.TABLE),'registry':fingerprint(R.OFFICIAL),'corpus':prepared,'reference_corruption':reference_faults,'scope':['Stored friction/speed/jump only; no contextual shapes/light/collision/entity application.','Registry canonical identity and Core/Registry state count checked each public call; no caller-copyable admission cache.','Complete canonical Core bytes/full raw W.View/Catalog metadata and arrays are prepared for native verification; no execution is implied by preflight.']}
    P.write_json(ROOT/'evidence/block-physics-world-preflight.json',preflight)
    if args.preflight:print(json.dumps({'status':'prepared','operations':prepared['operations'],'responses':prepared['responses'],'source_files':len(generation),'checkpoints':prepared['checkpoints']}));return
    receipt,artifact=receipt_check(generation) if args.skip_build else build(generation)
    if args.build_only:print(json.dumps({'status':'built','binary_sha256':receipt['build']['binary_sha256']}));return
    result=native(generation,receipt,artifact,prepared);result.update(ordinary=ordinary,runner_sha256=preflight['runner_sha256'],reference_file_sha256=preflight['reference_file_sha256'],reference_corruption=reference_faults)
    require(tool_closure()==python_generation,'Python oracle/orchestration source changed during native runs')
    result['python_tool_sources_sha256']=python_generation
    P.write_json(ROOT/'evidence/block-physics-world-native.json',result)
    if args.kernel:
        verdict=P.bounded_run([BEND,SOURCE,'--verdict'],timeout=60,allow_timeout=True)
        status='timeout' if verdict['timed_out'] else 'passed' if verdict['exit_code']==0 and 'ALL PROOFS CHECK' in verdict['stdout'] else 'failed'
        P.write_json(ROOT/'evidence/block-physics-world-kernel.json',{'status':status,'commands':[verdict],'sources_sha256':generation,'scope':'Full production imports with three early rejection/owner-retention laws; no mathematical Java parity or contextual physics theorem.'})
    print(json.dumps({'status':'native-passed','responses_per_run':prepared['responses'],'runs':2,'output_sha256':result['runs'][0]['output_sha256']}))

if __name__=='__main__':main()
