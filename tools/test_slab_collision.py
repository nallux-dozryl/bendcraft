#!/usr/bin/env python3
"""Pinned primitive catalog verification; Python is only an oracle/orchestrator."""
from __future__ import annotations
import argparse
import ast
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

import reference_slab_collision_probe as R
import test_player_record as P
import build_native as B
import test_player_look as L
from reference_inventory import canonical, fingerprint
from test_persistence import registry_identity

ROOT=R.ROOT
WORK=ROOT/'build/slab-collision'
ENTRY=ROOT/'tests/slab_collision.bend'
SOURCE=ROOT/'src/slab_collision.bend'
BEND=Path('/Users/chuah/.bend/bin/bend')
BINARY=WORK/'tests'
RECEIPT=WORK/'native-build.json'

def require(ok,message):
    if not ok:raise AssertionError(message)

def source_hashes():
    return P.P.imports([ENTRY])

def reference_selftests(info):
    original=json.loads((R.WORK/'receivers-0.json').read_text());matrix=R.rows(R.WORK/'actual-0.tsv');passed=[]
    names=('state-count','state-id','duplicate-state','state-owner','slab-type','waterlogged','nonboolean-waterlogged','raw-box','version','receiver-override','collision-guard','dynamic-guard','cache-guard','offset-guard','protocol-id','matrix-count','matrix-box','matrix-world-read','matrix-context-read','matrix-property','matrix-route','matrix-duplicate','context-owner','context-class','non-normal-entity')
    first=next(iter(original['receivers']))
    for name in names:
        meta=copy.deepcopy(original);observed=list(matrix)
        if name=='state-count':meta['states'].pop()
        elif name=='state-id':meta['states'][0]['state_id']=0
        elif name=='duplicate-state':meta['states'][1]['state_id']=meta['states'][0]['state_id']
        elif name=='state-owner':meta['states'][0]['identifier']='minecraft:stone'
        elif name=='slab-type':meta['states'][0]['slab_type']='bottom'
        elif name=='waterlogged':meta['states'][0]['waterlogged']=not meta['states'][0]['waterlogged']
        elif name=='nonboolean-waterlogged':meta['states'][0]['waterlogged']=1
        elif name=='raw-box':meta['states'][0]['aabbs_f64_bits'][0][1]='0000000000000000'
        elif name=='version':meta['version']='26.4'
        elif name=='receiver-override':meta['receivers'][first]['method_owners']['getCollisionShape']='unknown.Override'
        elif name=='collision-guard':meta['receivers'][first]['has_collision']=False
        elif name=='dynamic-guard':meta['receivers'][first]['dynamic_shape']=True
        elif name=='cache-guard':meta['states'][0]['cache_present']=False
        elif name=='offset-guard':meta['states'][0]['offset']=True
        elif name=='protocol-id':meta['receivers'][first]['protocol']=0
        elif name=='matrix-count':observed.pop()
        elif name.startswith('matrix-'):
            observed[0]=dict(observed[0])
            if name=='matrix-box':observed[0]['aabbs_f64_bits']='[]'
            elif name=='matrix-world-read':observed[0]['world_reads']='{"getBlockState":1}'
            elif name=='matrix-context-read':observed[0]['context_reads']='{"isDescending":1}'
            elif name=='matrix-property':observed[0]['waterlogged']='false'
            elif name=='matrix-route':observed[0]['route']='unknown'
            elif name=='matrix-duplicate':observed[0]=dict(observed[1])
        elif name=='context-owner':meta['context_receivers']['position-low']['shape_owner']='unknown.Override'
        elif name=='context-class':meta['context_receivers']['position-low']['class']='custom.Fake'
        elif name=='non-normal-entity':meta['normally_constructed_entities'][0]='custom.Fake'
        try:R.validate(meta,observed,info['registry_identity'])
        except (ValueError,KeyError):passed.append(name)
        else:raise AssertionError('Malformed independent receiver evidence admitted '+name)
    return {'status':'passed','count':len(passed),'rejected':passed,'shared_reference_or_artifact_files_changed':False}


def raw_expected(record):
    values=[]
    for raw in record['aabbs_f64_bits'][0]:values.extend((int(raw[:8],16),int(raw[8:],16)))
    return 'ok\t'+str(record['state_id'])+'\t'+record['slab_type']+'\t'+('1' if record['waterlogged'] else '0')+'\t'+'\t'.join(map(str,values))


def corpus(info):
    WORK.mkdir(parents=True,exist_ok=True);fixtures=WORK/'fixtures';fixtures.mkdir(exist_ok=True)
    actual=json.loads((R.WORK/'receivers-0.json').read_text());byid={r['state_id']:r for r in actual['states']};identity=info['registry_identity'];table=R.TABLE.read_bytes()
    commands=[];expected=[];categories=[];names=[]
    def add(name,category,args,answer):
        require(all('\t' not in str(v) and '\n' not in str(v) for v in args),'unsafe TSV fixture')
        commands.append('\t'.join(map(str,args)));expected.append(answer);categories.append(category);names.append(name)
    def query(index,name=None):
        answer=raw_expected(byid[index]) if index in byid else 'error\tUnsupportedState'
        add(name or 'state-'+str(index),'registered-slab' if index in byid else 'unsupported-registered-state',('state',index),answer)
    def recovery(index=15180):query(index,'same-process-owner-recovery-'+str(len(commands)))
    for index in range(35723):query(index)
    for index in reversed(range(35723)):query(index,'reverse-state-'+str(index))
    # Revisit every observed slab after traversing all unsupported states.
    for index in byid:query(index,'slab-repeat-'+str(index))
    rng=random.Random(263606)
    for i in range(512):query(rng.randrange(35723),'random-repeat-'+str(i))
    for bad in ('','wrong',identity.upper(),identity[:-1]+'0'):
        add('wrong-query-identity','identity',('query',15180,bad),'error\tIdentityMismatch');recovery()
    for sid in (35723,35724,65535,65536,2147483648,4294967295):
        add('invalid-state-'+str(sid),'state-bound',('query',sid,identity),'error\tInvalidState');recovery()
    firstline=table.split(b'\n')[2]
    mutations=[('empty',b''),('truncated',table[:-1]),('missing-header',table.split(b'\n',1)[1]),
               ('wrong-format',table.replace(b'Collision\t1\t',b'Collision\t2\t',1)),('wrong-version',table.replace(b'\t26.3\t',b'\t26.4\t',1)),
               ('wrong-header-identity',table.replace(identity.encode(),b'0'*64,1)),('wrong-header-count',table.replace(b'\t35723\t',b'\t35724\t',1)),
               ('wrong-slab-count',table.replace(b'\t606\n',b'\t607\n',1)),('wrong-column',table.replace(b'slab_type',b'collision_shape',1)),
               ('valid-type-corruption',table.replace(b'\ttop\t',b'\tbottom\t',1)),('valid-waterlogged-corruption',table.replace(b'\ttop\t1\n',b'\ttop\t0\n',1)),
               ('unknown-type',table.replace(b'\ttop\t',b'\tmiddle\t',1)),('invalid-waterlogged',table.replace(b'\ttop\t1\n',b'\ttop\ttrue\n',1)),
               ('state-outside-registry',table.replace(firstline,b'35723\ttop\t1',1)),('state-U32-overflow',table.replace(firstline,b'4294967296\ttop\t1',1)),
               ('signed-state',table.replace(firstline,b'-1\ttop\t1',1)),('fractional-state',table.replace(firstline,b'1.0\ttop\t1',1)),
               ('duplicate-state',table+firstline+b'\n'),('remove-state',table.replace(firstline+b'\n',b'',1)),
               ('reordered-states',b'\n'.join(table.split(b'\n')[:2]+[table.split(b'\n')[3],table.split(b'\n')[2]]+table.split(b'\n')[4:])),
               ('blank-row',table+b'\n'),('trailing-member',table+b'0\ttop\t0\n'),('crlf',table.replace(b'\n',b'\r\n')),('embedded-NUL',table+b'\x00'),
               ('UTF8-BOM',b'\xef\xbb\xbf'+table),('invalid-UTF8',table+b'\xff'),('overlong-UTF8',table+b'\xc0\x80'),('UTF8-surrogate',table+b'\xed\xa0\x80'),
               ('at-byte-limit',b'x'*16384),('over-byte-limit',b'x'*16385)]
    manifest=[]
    for name,data in mutations:
        path=fixtures/(name+'.tsv');path.write_bytes(data);manifest.append({'name':name,'bytes':len(data),'sha256':P.sha(data)})
        try:data.decode('utf-8');valid_unicode=True
        except UnicodeDecodeError:valid_unicode=False
        error='TextError' if not valid_unicode or len(data)>16384 else 'IntegrityMismatch'
        for mode in ('parse','replace','bind','load'):
            answer='ByteLimit' if mode=='load' and len(data)>16384 else error
            add(name+'-'+mode,'catalog-corruption',(mode,identity,35723,path) if mode=='parse' else (mode,path),'error\t'+answer);recovery()
    for ident,count in (('wrong',35723),(identity,0),(identity,35722),(identity,35724),(identity,4294967295)):
        add('parser-context-'+str(count),'parse-context',('parse',ident,count,R.TABLE),'error\t'+('IdentityMismatch' if ident!=identity else 'StateCountMismatch'));recovery()
    for words,name,error in (([256],'raw-byte-256','TextError'),([4294967295],'raw-byte-max','TextError'),([0xff],'raw-byte-invalid-UTF8','TextError'),([120]*16385,'decode-byte-limit','ByteLimit'),([120]*16384,'decode-at-limit','IntegrityMismatch'),(list(table),'decode-canonical',None)):
        path=fixtures/(name+'.u32');path.write_bytes(struct.pack('<'+'I'*len(words),*words))
        add(name,'decode',('decode',identity,35723,path),'error\t'+error if error else 'ok\tdecode');recovery()
    add('invalid-Unicode-scalar','encode',('invalid-scalar',),'error\tTextError');recovery()
    for path in (fixtures/'absent',fixtures):add('read-failure-'+path.name,'io',('load',path),'error\tReadError');recovery()
    corrupt=fixtures/'valid-type-corruption.tsv'
    for i in range(64):
        add('repeated-failed-load-'+str(i),'io-repeat',('load',corrupt),'error\tIntegrityMismatch');recovery()
    for mode in ('replace','parse','bind','load'):
        add('valid-'+mode,'valid-replacement',(mode,identity,35723,R.TABLE) if mode=='parse' else (mode,R.TABLE),'ok\t'+mode);recovery()
    for kind in ('zero-count','short-count','large-count','max-count','wrong-states','wrong-identity','short-array','outside-state'):
        add('forge-'+kind,'forged-owner',('forge',kind),'ok\tforge')
        for _ in range(2):add('retained-forged-'+kind,'forged-owner',('query',15180,identity),'error\tCatalogCorrupt')
        add('bound-before-forged-'+kind,'forged-owner',('query',4294967295,identity),'error\tInvalidState')
        add('recover-forged-'+kind,'forged-owner',('replace',R.TABLE),'ok\treplace');recovery()
    tiny=fixtures/'foreign-registry.tsv';tiny.write_text('block_protocol_id\tidentifier\tfirst_state_id\tstate_count\tdefault_state_id\tordered_properties_json\n0\tminecraft:air\t0\t1\t0\t[]\n')
    foreign_id,_,_=registry_identity(tiny)
    add('foreign-registry-owner','bind-ownership',('foreign',tiny,R.TABLE),'error\tIdentityMismatch\t'+foreign_id);recovery()
    add('registry-owner-retained','bind-ownership',('inspect',),'ok\tregistry\t'+identity+'\tminecraft:oak_slab\t15177')
    request_path=WORK/'requests.tsv';request_path.write_text('\n'.join(commands)+'\n');output_path=WORK/'expected.tsv';output_path.write_text('\n'.join(expected)+'\n')
    metadata={'cases':len(commands),'categories':dict(collections.Counter(categories)),'request_sha256':P.sha(request_path.read_bytes()),'expected_sha256':P.sha(output_path.read_bytes()),'requests':fingerprint(request_path),'expected':fingerprint(output_path),'corrupt_catalog_manifest_sha256':P.sha(canonical(manifest)),'corrupt_catalog_fixtures':len(manifest),'all_state_orders':['forward','reverse'],'complete_slab_revisit':606,'seeded_repeat_queries':512,'repeated_failed_actual_loads':64,'independent_expected_values':'Actual untouched Java receiver raw state/property/AABB observations, not catalog implementation arithmetic.'}
    P.write_json(WORK/'case-manifest.json',[{'name':n,'category':c,'request':q,'expected':e} for n,c,q,e in zip(names,categories,commands,expected)])
    return metadata

def generation_pin(sources,corpus_info):
    local_tools={}
    for module in list(sys.modules.values()):
        name=getattr(module,'__file__',None)
        if name and Path(name).resolve().is_relative_to(ROOT/'tools'):
            path=Path(name).resolve()
            if path.suffix=='.py':local_tools[str(path.relative_to(ROOT))]=P.sha(path.read_bytes())
    local_tools[str(Path(__file__).resolve().relative_to(ROOT))]=P.sha(Path(__file__).read_bytes())
    fixtures={str(p.relative_to(ROOT)):P.sha(p.read_bytes()) for p in sorted((WORK/'fixtures').iterdir()) if p.is_file()}
    return {'sources_sha256':sources,'python_tool_sha256':dict(sorted(local_tools.items())),'reference_sha256':P.sha(R.REFERENCE.read_bytes()),'derived_table_sha256':P.sha(R.TABLE.read_bytes()),'registry_sha256':P.sha(R.OFFICIAL.read_bytes()),'raw_java_run_pins':[{'table':fingerprint(R.WORK/f'actual-{i}.tsv'),'receivers':fingerprint(R.WORK/f'receivers-{i}.json')} for i in range(2)],'prepared_request_sha256':P.sha((WORK/'requests.tsv').read_bytes()),'prepared_expected_sha256':P.sha((WORK/'expected.tsv').read_bytes()),'prepared_case_manifest_sha256':P.sha((WORK/'case-manifest.json').read_bytes()),'fixture_manifest_sha256':P.sha(canonical(fixtures)),'compiler_executable':fingerprint(BEND)}


def assert_generation(sources,corpus_info,generation):
    require(sources==source_hashes(),'Frozen Bend source changed')
    require(generation==generation_pin(sources,corpus_info),'Frozen tool/reference/compiler/fixture generation changed')

def receipt_check(sources):
    receipt=json.loads(RECEIPT.read_text());artifact=P.check_receipt(sources,receipt)
    require(P.sha(BINARY.read_bytes())==receipt['build']['binary_sha256'],'convenience binary changed')
    return receipt,artifact

def receipt_selftests(sources,receipt):
    passed=[]
    for name in ('source','missing-source','cache-key','binary-sha','binary-size','C-sha','compiler','dependency-sha','missing-dependency','artifact-alias'):
        altered=copy.deepcopy(receipt);build=altered['build']
        if name=='source':altered['sources_sha256']['src/slab_collision.bend']='0'*64
        elif name=='missing-source':del altered['sources_sha256']['src/slab_collision.bend']
        elif name=='cache-key':build['cache_key']='0'*64
        elif name=='binary-sha':build['binary_sha256']='0'*64
        elif name=='binary-size':build['binary_bytes']+=1
        elif name=='C-sha':build['emitted_c_sha256']='0'*64
        elif name=='compiler':build['compiler']['path']='/invalid'
        elif name=='dependency-sha':build['dependencies'][0]['sha256']='0'*64
        elif name=='missing-dependency':build['dependencies'].pop()
        elif name=='artifact-alias':build['artifact']=str(BINARY)
        try:P.check_receipt(sources,altered)
        except (AssertionError,ValueError,OSError,KeyError):passed.append(name)
        else:raise AssertionError('Corrupt receipt admitted '+name)
    return {'status':'passed','count':len(passed),'rejected':passed,'shared_files_changed':False}

def build(sources,corpus_info,generation):
    report=WORK/'build.json';command=[sys.executable,ROOT/'tools/build_native.py',ENTRY,'-o',BINARY,'--bend',BEND,'--report',report]
    child=subprocess.Popen([str(x) for x in command],cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
    print(json.dumps({'status':'native-build-started','pid':child.pid,'entry':'tests/slab_collision.bend','sources_sha256':sources}),flush=True)
    try:stdout,stderr=child.communicate(timeout=600)
    except subprocess.TimeoutExpired:os.killpg(child.pid,signal.SIGKILL);child.communicate();raise AssertionError('600s native build timeout')
    require(child.returncode==0,'native build failed '+stderr.decode()[-2500:]);assert_generation(sources,corpus_info,generation)
    P.write_json(RECEIPT,{'sources_sha256':sources,'build':json.loads(report.read_text())})
    return receipt_check(sources)

def native(sources,receipt,artifact,corpus_info,generation):
    corruption=receipt_selftests(sources,receipt);runs=[]
    for i in range(2):
        output=WORK/f'observed-{i}.tsv';started=time.monotonic()
        with output.open('wb') as stream:
            process=subprocess.Popen([str(artifact),'--gpu','off','--threads','2','--',str(R.OFFICIAL),str(R.TABLE),str(WORK/'requests.tsv')],cwd=ROOT,stdout=stream,stderr=subprocess.PIPE,start_new_session=True)
            try:_,stderr=process.communicate(timeout=120)
            except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);process.communicate();raise AssertionError('native corpus120s timeout')
        require(process.returncode==0 and not stderr,'native run failed '+stderr.decode()[-2500:])
        actual=output.read_text().splitlines();expected=(WORK/'expected.tsv').read_text().splitlines()
        require(len(actual)==len(expected),'native response count mismatch')
        requests=(WORK/'requests.tsv').read_text().splitlines()
        for index,(a,b) in enumerate(zip(actual,expected)):
            if a != b:
                require(a==b,'case '+str(index)+' mismatch '+requests[index]+' observed='+a+' expected='+b)
        runs.append({'pid':process.pid,'seconds':round(time.monotonic()-started,6),'output_sha256':P.sha(output.read_bytes()),'responses':len(actual)})
        receipt_check(sources)
        assert_generation(sources,corpus_info,generation)
    require(runs[0]['output_sha256']==runs[1]['output_sha256']==corpus_info['expected_sha256'],'two-run native byte agreement failed')
    require(source_hashes()==sources,'source changed during runs')
    b=receipt['build'];summary={k:b[k] for k in ('artifact','cache_key','binary_sha256','binary_bytes','emitted_c_sha256','timings')}
    summary.update(compiler={k:v for k,v in b['compiler'].items() if k!='driver_probe'},compiler_driver_probe_sha256=P.sha(b['compiler']['driver_probe'].encode()),dependency_count=len(b['dependencies']),dependency_manifest_sha256=P.sha(canonical(b['dependencies'])),ignored_receipt_sha256=P.sha(RECEIPT.read_bytes()))
    return {'status':'passed','runs':runs,'corpus':corpus_info,'sources_sha256':sources,'build':summary,'receipt_corruption':corruption,'confidence':'high for pinned registered slab collision getters and tested admission/affine-owner behavior','scope':['Only all measured registered SlabBlock collision getter receivers and inspected stored guards/method bodies; no unrelated sampled shape or light output.','Only admitted Catalog parse/decode/bind/load/replace/query; raw constructors remain outside integrity admission.','No world adapter, fluid union, Entity application, step, support, travel, block updates or placement is established.']}

# Retained-output adoption is deliberately separate from native/build paths.
ARCHIVE=WORK/'lineage'
ORIGINAL_PINS={
    'original-runner.py':'a99203ea4e88e31c106d3f6e21a325b87f78c6a378cfedff3a70b0fb2392cc9b',
    'original-preflight.json':'0161a85d866223c9da3af68a319663aa38239499306fc182ca2cb377b1cdd29b',
    'original-interrupted.json':'61a1901832732d11590b2362d443e27ebe1d5aaa391e1a42609132fb9a3548f2',
    'original-native-build.json':'880a8dcc474e768d97527050780ba47d08181858e6973667b2a4870610504a28'}
LAZY_OLD="""        for index,(a,b) in enumerate(zip(actual,expected)):
            require(a==b,'case '+str(index)+' mismatch '+(WORK/'requests.tsv').read_text().splitlines()[index]+' observed='+a+' expected='+b)"""
LAZY_NEW="""        requests=(WORK/'requests.tsv').read_text().splitlines()
        for index,(a,b) in enumerate(zip(actual,expected)):
            if a != b:
                require(a==b,'case '+str(index)+' mismatch '+requests[index]+' observed='+a+' expected='+b)"""


def compare_lines(actual,expected,requests):
    require(len(actual)==len(expected),'native response count mismatch')
    require(len(requests)==len(expected),'native request count mismatch')
    for index,(a,b) in enumerate(zip(actual,expected)):
        if a != b:
            require(a==b,'case '+str(index)+' mismatch '+requests[index]+' observed='+a+' expected='+b)
    return len(actual)


def archive_check():
    for name,digest in ORIGINAL_PINS.items():
        require(P.sha((ARCHIVE/name).read_bytes())==digest,'Original archive corrupted '+name)
    for current,name in ((ROOT/'evidence/slab-collision-preflight.json','original-preflight.json'),(ROOT/'evidence/slab-collision-interrupted.json','original-interrupted.json'),(RECEIPT,'original-native-build.json')):
        require(current.read_bytes()==(ARCHIVE/name).read_bytes(),'Original receipt overwritten '+name)
    return json.loads((ARCHIVE/'original-preflight.json').read_text()),json.loads((ARCHIVE/'original-interrupted.json').read_text())


def ast_repair_audit():
    original=(ARCHIVE/'original-runner.py').read_text();current=Path(__file__).read_text()
    oldtree=ast.parse(original);newtree=ast.parse(current)
    olddefs={x.name:ast.dump(x,include_attributes=False) for x in oldtree.body if isinstance(x,(ast.FunctionDef,ast.AsyncFunctionDef,ast.ClassDef))}
    newdefs={x.name:ast.dump(x,include_attributes=False) for x in newtree.body if isinstance(x,(ast.FunctionDef,ast.AsyncFunctionDef,ast.ClassDef))}
    changed=[name for name in olddefs if olddefs[name]!=newdefs.get(name)]
    require(changed==['native','main'],'Unexpected change to original producer/oracle/receipt/generation definitions')
    require(original.count(LAZY_OLD)==1,'Original comparison loop differs from authorized baseline')
    expected=ast.parse(original.replace(LAZY_OLD,LAZY_NEW))
    expected_native=next(x for x in expected.body if isinstance(x,ast.FunctionDef) and x.name=='native')
    require(ast.dump(expected_native,include_attributes=False)==newdefs['native'],'Native producer changed beyond authorized preload/lazy diagnostic')
    return {'status':'passed','original_runner_sha256':ORIGINAL_PINS['original-runner.py'],'repaired_runner_sha256':P.sha(Path(__file__).read_bytes()),'changed_original_definitions':changed,'unchanged_original_definitions':len(olddefs)-len(changed),'native_loop_change':'one request preload; identical equality failure inside a != b branch; native subprocess/order/count/end-byte checks unchanged','adoption_entry':'main returns after adopt_main before any corpus generation/build/native path'}


def approved_generation(original):
    current=generation_pin(original['sources_sha256'],original['corpus'])
    allowed=copy.deepcopy(original['generation'])
    allowed['python_tool_sha256']['tools/test_slab_collision.py']=P.sha(Path(__file__).read_bytes())
    require(current==allowed,'Original source/reference/input/compiler/tool/fixture generation changed outside the authorized runner')
    require(source_hashes()==original['sources_sha256'],'Original Bend sources changed')
    return current


def interrupted_contract(original,interrupted,receipt):
    require(interrupted['status']=='native-two-retained-outputs-byte-pass-original-verifier-interrupted','Unknown retained-output producer status')
    require(interrupted['kernel']=='not started','Original kernel state differs')
    require(interrupted['generation']==original['generation'],'Original producer/preflight generation mismatch')
    require(interrupted['original_runner_sha256']==ORIGINAL_PINS['original-runner.py']==original['runner_sha256'],'Original producer tool mismatch')
    require(interrupted['request']==fingerprint(WORK/'requests.tsv') and interrupted['expected']==fingerprint(WORK/'expected.tsv'),'Original request/expected pin mismatch')
    require(original['corpus']['cases']==73039 and original['corpus']['request_sha256']==interrupted['request']['sha256'] and original['corpus']['expected_sha256']==interrupted['expected']['sha256'],'Original corpus count/hash mismatch')
    require(P.sha(RECEIPT.read_bytes())==interrupted['build_receipt_sha256'],'Original build receipt pin mismatch')
    built=receipt['build']
    require(interrupted['build']=={k:built[k] for k in interrupted['build']},'Original native artifact/compiler generation mismatch')
    require(interrupted['native_dependency_count']==len(built['dependencies']) and interrupted['native_dependency_manifest_sha256']==P.sha(canonical(built['dependencies'])),'Original dependency manifest mismatch')
    require(interrupted['compiler']=={k:v for k,v in built['compiler'].items() if k!='driver_probe'} and interrupted['compiler_driver_probe_sha256']==P.sha(built['compiler']['driver_probe'].encode()),'Original compiler/driver/flags mismatch')
    manifest=ROOT/'build/native-cache/entries'/built['cache_key']/'manifest.json'
    require(P.sha(manifest.read_bytes())==interrupted['build_cache_manifest_sha256'],'Original keyed native manifest changed')
    require(len(interrupted['outputs'])==2,'Retained output count mismatch')
    for index,record in enumerate(interrupted['outputs']):
        output=WORK/f'observed-{index}.tsv'
        require(record['path']==str(output.relative_to(ROOT)) and {k:record[k] for k in ('file','bytes','sha1','sha256')}==fingerprint(output),'Retained native output pin mismatch')
        require(record['responses']==73039 and record['exact_expected_bytes_equal'] is True,'Retained native response count/comparison state mismatch')
    require(all(interrupted['reap'][k] is True for k in ('build_group17065_absent','build_outer16874_absent','comparison_outer17308_absent')),'Original reaping receipt differs')


def diagnostic_selftests(actual,expected,requests):
    rejected=[]
    for index in (0,3705,15180,36519,73038):
        altered=list(actual);altered[index]='injected-mismatch'
        target='case '+str(index)+' mismatch '+requests[index]+' observed=injected-mismatch expected='+expected[index]
        try:compare_lines(altered,expected,requests)
        except AssertionError as error:
            require(str(error)==target,'Mismatch diagnostic changed request/index/observed/expected fields')
            rejected.append('row-'+str(index))
        else:raise AssertionError('Injected response mismatch admitted')
    for name,a,b,q,message in (('missing-row',actual[:-1],expected,requests,'native response count mismatch'),('extra-row',actual+[''],expected,requests,'native response count mismatch'),('short-requests',actual,expected,requests[:-1],'native request count mismatch')):
        try:compare_lines(a,b,q)
        except AssertionError as error:require(str(error)==message,'Count diagnostic mismatch');rejected.append(name)
        else:raise AssertionError('Injected count mismatch admitted')
    require(compare_lines(actual,expected,requests)==73039,'Valid comparison failed after malformed input')
    return {'status':'passed','rejected':rejected,'count':len(rejected),'diagnostic_fields_checked':['index','request','observed','expected'],'shared_outputs_or_input_files_changed':False}


def lineage_selftests(original,interrupted,receipt):
    names=('producer-status','kernel-state','producer-tool','producer-generation','requests','expected','count','build-receipt','binary','dependencies','compiler','manifest','output-count','output-pin','output-responses','reap')
    rejected=[]
    for name in names:
        before=copy.deepcopy(original);altered=copy.deepcopy(interrupted)
        if name=='producer-status':altered['status']='passed'
        elif name=='kernel-state':altered['kernel']='passed'
        elif name=='producer-tool':altered['original_runner_sha256']='0'*64
        elif name=='producer-generation':altered['generation']['sources_sha256']['src/slab_collision.bend']='0'*64
        elif name=='requests':altered['request']['sha256']='0'*64
        elif name=='expected':altered['expected']['sha256']='0'*64
        elif name=='count':before['corpus']['cases']=1
        elif name=='build-receipt':altered['build_receipt_sha256']='0'*64
        elif name=='binary':altered['build']['binary_sha256']='0'*64
        elif name=='dependencies':altered['native_dependency_manifest_sha256']='0'*64
        elif name=='compiler':altered['compiler']['path']='/invalid'
        elif name=='manifest':altered['build_cache_manifest_sha256']='0'*64
        elif name=='output-count':altered['outputs'].pop()
        elif name=='output-pin':altered['outputs'][0]['sha256']='0'*64
        elif name=='output-responses':altered['outputs'][0]['responses']=1
        elif name=='reap':altered['reap']['comparison_outer17308_absent']=False
        try:interrupted_contract(before,altered,receipt)
        except (AssertionError,KeyError,ValueError):rejected.append(name)
        else:raise AssertionError('Altered adoption lineage admitted '+name)
    return {'status':'passed','count':len(rejected),'rejected':rejected,'shared_lineage_files_changed':False}


def reference_artifact_check():
    info=json.loads(R.REFERENCE.read_text());jars,_=R.verified_classpath()
    require(info['java_runtime']==fingerprint(R.JAVA) and info['java_compiler']==fingerprint(R.JAVA.parent/'javac'),'Original Java runtime/compiler artifact changed')
    require(info['classpath_manifest_sha256']==P.sha(canonical([fingerprint(p) for p in jars])),'Original official Java classpath changed')
    require(info['source_sha256']==P.sha(R.SOURCE.encode()) and info['helper_sources']=={'ReferenceMovementProbe':P.sha(R.MOVE_SOURCE.encode()),'ReferenceDirectMovementProbe':P.sha(R.DIRECT_SOURCE.encode())},'Original Java source/helper generation changed')
    with R.zipfile.ZipFile(jars[0]) as archive:
        require(info['class_sha256']=={name:P.sha(archive.read(name.replace('.','/')+'.class')) for name in R.CLASS_NAMES},'Actual production class bytes changed')
    for name,digest in info['javap_text_sha256'].items():
        require(P.sha((R.WORK/(name.rsplit('.',1)[-1]+'.javap')).read_bytes())==digest,'Original production method inspection changed')
    meta=json.loads((R.WORK/'receivers-0.json').read_text());entries,table,routes=R.validate(meta,R.rows(R.WORK/'actual-0.tsv'),info['registry_identity'])
    require(entries==info['slab_entries'] and table==R.TABLE.read_bytes() and info['derived_table']==fingerprint(R.TABLE),'Original receiver-derived catalog changed')
    return {'status':'passed','official_classpath_artifacts':len(jars),'actual_production_classes':len(R.CLASS_NAMES),'complete_collision_receiver_rows':123624,'complete_baseline_states':606,'java_source_execution':'none; artifacts and retained actual observations only'}


def adopt_retained():
    started=time.monotonic();original,interrupted=archive_check();ast_audit=ast_repair_audit()
    generation=approved_generation(original);sources=original['sources_sha256']
    receipt,artifact=receipt_check(sources);interrupted_contract(original,interrupted,receipt)
    reference_artifacts=reference_artifact_check()
    defensive=receipt_selftests(sources,receipt);lineage_defensive=lineage_selftests(original,interrupted,receipt)
    request_bytes=(WORK/'requests.tsv').read_bytes();expected_bytes=(WORK/'expected.tsv').read_bytes()
    requests=request_bytes.decode('utf-8').splitlines();expected=expected_bytes.decode('utf-8').splitlines()
    require(len(requests)==len(expected)==73039,'Adoption input count mismatch')
    runs=[];first_actual=None
    for index in range(2):
        output=WORK/f'observed-{index}.tsv';data=output.read_bytes();actual=data.decode('utf-8').splitlines()
        require(compare_lines(actual,expected,requests)==73039,'Retained response comparison failed')
        require(data==expected_bytes,'Retained output bytes differ despite row comparisons')
        runs.append({'retained_run':index,'verification_mode':'adopted original completed native execution; no new process','responses':len(actual),'output_sha256':P.sha(data),'output_bytes':len(data),'original_native_pid':None,'original_native_seconds':None})
        if index==0:first_actual=actual
    diagnostics=diagnostic_selftests(first_actual,expected,requests)
    require(runs[0]['output_sha256']==runs[1]['output_sha256']==original['corpus']['expected_sha256'],'Retained two-run native byte agreement failed')
    approved_generation(original);receipt_check(sources);archive_check()
    result={'status':'passed','verification_mode':'adopted-retained-native-outputs','runs':runs,'new_native_executions':0,'new_builds':0,'corpus':original['corpus'],'sources_sha256':sources,'generation':generation,'original_generation':original['generation'],'runner_sha256':P.sha(Path(__file__).read_bytes()),'original_runner_sha256':ORIGINAL_PINS['original-runner.py'],'original_interrupted_receipt_sha256':ORIGINAL_PINS['original-interrupted.json'],'original_preflight_receipt_sha256':ORIGINAL_PINS['original-preflight.json'],'original_build_receipt_sha256':ORIGINAL_PINS['original-native-build.json'],'original_native_verifier_completion':'interrupted in second eager Python comparison; preserved without rewriting history','independent_kernel_status':'not attempted at adoption receipt publication','archive_pins':ORIGINAL_PINS,'ast_repair_audit':ast_audit,'mismatch_diagnostics':diagnostics,'lineage_corruption':lineage_defensive,'reference_artifact_audit':reference_artifacts,'receipt_corruption':defensive,'ordinary':original['ordinary'],'reference_corruption':original['reference_corruption'],'reference_file_sha256':original['reference_file_sha256'],'build':interrupted['build'],'compiler':interrupted['compiler'],'native_dependency_count':interrupted['native_dependency_count'],'native_dependency_manifest_sha256':interrupted['native_dependency_manifest_sha256'],'retained_preparation_C':interrupted['retained_preparation_C'],'missing_observations':interrupted['missing_observations'],'seconds':round(time.monotonic()-started,6),'confidence':'high for the two actual frozen native outputs and their independently pinned Java/corpus lineage; no independent proof claim','scope':['No source/harness/oracle/table/input edits and no additional native execution.','All 73039 rows compared twice plus exact byte equality; injected diagnostics and altered producer lineage rejected.','Only pinned registered slab collision catalog/admission/owner results; no world/Entity integration.']}
    # Publish comparison/adoption receipt before even considering a kernel call.
    P.write_json(ROOT/'evidence/slab-collision-native.json',result)
    P.write_json(ROOT/'evidence/slab-collision-adoption.json',result)
    return result,original


def adopt_main(kernel_requested):
    require(not (ROOT/'evidence/slab-collision-kernel.json').exists(),'A kernel receipt already exists; no repeated verdict allowed in adoption mode')
    result,original=adopt_retained()
    print(json.dumps({'status':'retained-native-adopted','responses_per_run':73039,'runs':2,'output_sha256':result['runs'][0]['output_sha256'],'new_builds':0,'new_native_executions':0,'adoption_seconds':result['seconds']}),flush=True)
    if kernel_requested:
        verdict=P.bounded_run([BEND,SOURCE,'--verdict'],timeout=60,allow_timeout=True)
        status='timeout' if verdict['timed_out'] else 'passed' if verdict['exit_code']==0 and 'ALL PROOFS CHECK' in verdict['stdout'] else 'failed'
        P.write_json(ROOT/'evidence/slab-collision-kernel.json',{'status':status,'commands':[verdict],'sources_sha256':original['sources_sha256'],'runner_sha256':result['runner_sha256'],'native_comparison_published_before_kernel':True,'adoption_receipt_sha256':P.sha((ROOT/'evidence/slab-collision-adoption.json').read_bytes()),'scope':'One full production source attempt only; no retry/projection. Three rejection/owner-retention laws; no Java/Entity/world theorem.'})
        print(json.dumps({'status':'kernel-'+status,'pid':verdict['pid'],'seconds':verdict['seconds'],'exit_code':verdict['exit_code']}),flush=True)
    approved_generation(original);receipt_check(original['sources_sha256']);archive_check()


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--preflight',action='store_true');parser.add_argument('--build-only',action='store_true');parser.add_argument('--skip-build',action='store_true');parser.add_argument('--kernel',action='store_true');parser.add_argument('--adopt-retained',action='store_true');args=parser.parse_args()
    if args.adopt_retained:
        require(not (args.preflight or args.build_only or args.skip_build),'Adoption cannot be combined with a producer/build path')
        adopt_main(args.kernel)
        return
    info=R.verify_existing();reference_defensive=reference_selftests(info);cases=corpus(info);sources=source_hashes()
    ordinary=[P.bounded_run([BEND,path,'--check-only']) for path in (SOURCE,ENTRY)]
    require(all(x['exit_code']==0 and 'ALL PROOFS CHECK' in x['stdout'] for x in ordinary),'ordinary source/harness checking failed')
    generation=generation_pin(sources,cases)
    preflight={'generation':generation,'status':'prepared-native-kernel-unverified','sources_sha256':sources,'ordinary':ordinary,'corpus':cases,'reference_file_sha256':P.sha(R.REFERENCE.read_bytes()),'reference_probe_tool_sha256':P.sha(Path(R.__file__).read_bytes()),'reference_corruption':reference_defensive,'runner_sha256':P.sha(Path(__file__).read_bytes()),'table':fingerprint(R.TABLE),'registry_identity':info['registry_identity']}
    P.write_json(ROOT/'evidence/slab-collision-preflight.json',preflight)
    if args.preflight:print(json.dumps({'status':'prepared','cases':cases['cases'],'corrupt_catalogs':cases['corrupt_catalog_fixtures'],'sources':len(sources),'table_bytes':info['derived_table']['bytes']}));return
    receipt,artifact=receipt_check(sources) if args.skip_build else build(sources,cases,generation)
    if args.build_only:print(json.dumps({'status':'built','binary_sha256':receipt['build']['binary_sha256']}));return
    result=native(sources,receipt,artifact,cases,generation);result.update(ordinary=ordinary,reference_corruption=reference_defensive,runner_sha256=preflight['runner_sha256'],reference_file_sha256=preflight['reference_file_sha256'])
    result['generation']=generation
    P.write_json(ROOT/'evidence/slab-collision-native.json',result)
    if args.kernel:
        kernel=P.bounded_run([BEND,SOURCE,'--verdict'],timeout=60,allow_timeout=True)
        status='timeout' if kernel['timed_out'] else 'passed' if kernel['exit_code']==0 and 'ALL PROOFS CHECK' in kernel['stdout'] else 'failed'
        P.write_json(ROOT/'evidence/slab-collision-kernel.json',{'status':status,'commands':[kernel],'sources_sha256':sources,'scope':'Production module with three rejection/owner-retention laws; no world collision iteration, movement or universal block behavior theorem.'})
    assert_generation(sources,cases,generation)
    print(json.dumps({'status':'passed','cases_per_run':cases['cases'],'runs':2,'output_sha256':result['runs'][0]['output_sha256']}))

if __name__=='__main__':main()
