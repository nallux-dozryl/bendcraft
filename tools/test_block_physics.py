#!/usr/bin/env python3
"""Pinned primitive catalog verification; Python is only an oracle/orchestrator."""
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
import test_player_record as P
import build_native as B
import test_player_look as L
from reference_inventory import canonical, fingerprint
from test_persistence import registry_identity

ROOT=R.ROOT
WORK=ROOT/'build/block-physics'
ENTRY=ROOT/'tests/block_physics.bend'
SOURCE=ROOT/'src/block_physics.bend'
BEND=Path('/Users/chuah/.bend/bin/bend')
BINARY=WORK/'tests'
RECEIPT=WORK/'native-build.json'

def require(ok,message):
    if not ok:raise AssertionError(message)

def source_hashes():
    return P.P.imports([ENTRY])

def reference_selftests(info):
    observed=R.rows(R.WORK/'actual-0.tsv');receivers=json.loads((R.WORK/'receivers-0.json').read_text())
    prior=R.rows(ROOT/'generated/reference_block_physics.tsv');passed=[]
    for name in ('state-count','state-id','state-owner','F32-value','F64-widen','resealed-F32-F64-pair','version','registered-override','mutable-field','protocol-id'):
        altered=list(observed);meta=copy.deepcopy(receivers);altered[0]=dict(altered[0])
        if name=='state-count':altered.pop()
        elif name=='state-id':altered[0]['state_id']='1'
        elif name=='state-owner':altered[0]['block_identifier']='minecraft:stone'
        elif name=='F32-value':altered[0]['friction_f32_bits']='3f800000'
        elif name=='F64-widen':altered[0]['friction_promoted_f64_bits']='3fe3333333333333'
        elif name=='resealed-F32-F64-pair':
            altered[0]['friction_f32_bits']='3f800000';altered[0]['friction_promoted_f64_bits']='3ff0000000000000'
        elif name=='version':meta['version']='26.4'
        elif name=='registered-override':meta['blocks']['minecraft:air']['owners']['getFriction']='unknown.Override'
        elif name=='mutable-field':meta['blocks']['minecraft:air']['field_modifiers']['friction']='protected'
        elif name=='protocol-id':meta['blocks']['minecraft:air']['protocol']=1
        try:R.validate(altered,meta,prior,info['registry_identity'])
        except (ValueError,KeyError):passed.append(name)
        else:raise AssertionError('Malformed independent reference admitted '+name)
    return {'status':'passed','count':len(passed),'rejected':passed,'shared_reference_or_artifact_files_changed':False}

def raw_expected(row):
    values=[]
    for field in R.FIELDS:values.append(int(row[field+'_f32_bits'],16))
    for field in R.FIELDS:
        raw=row[field+'_promoted_f64_bits'];values.extend((int(raw[:8],16),int(raw[8:],16)))
    return 'ok\t'+'\t'.join(map(str,values))

def corpus(info):
    WORK.mkdir(parents=True,exist_ok=True);fixtures=WORK/'fixtures';fixtures.mkdir(exist_ok=True)
    observed=R.rows(R.WORK/'actual-0.tsv');identity=info['registry_identity'];table=R.TABLE.read_bytes()
    commands=[];expected=[];categories=[];names=[]
    def add(name,category,args,answer):
        require(all('\t' not in str(v) and '\n' not in str(v) for v in args),'unsafe TSV fixture')
        commands.append('\t'.join(map(str,args)));expected.append(answer);categories.append(category);names.append(name)
    def query(index,name=None):
        add(name or 'state-'+str(index),'state-getter',('state',index),raw_expected(observed[index]))
    def recovery(index=8597):
        query(index,'same-process-owner-recovery-'+str(len(commands)))
    for index in range(35723):query(index)
    for index in reversed(range(35723)):query(index,'reverse-state-'+str(index))
    rng=random.Random(263104)
    for i in range(1024):query(rng.randrange(35723),'random-repeat-'+str(i))
    for block in info['targeted'].values():query(int(block['state_id']),'targeted-repeat-'+block['state_id'])
    for identity_bad in ('','wrong','4F75FA335A12E34CF74BE71FF6A0EE530B13233212423F5463BB26A2FE4F3CFC','4f75fa335a12e34cf74be71ff6a0ee530b13233212423f5463bb26a2fe4f3cf0'):
        add('wrong-query-identity','identity',('query',8597,identity_bad),'error\tIdentityMismatch');recovery()
    for state in (35723,35724,65535,65536,2147483648,4294967295):
        add('invalid-state-'+str(state),'state-bound',('query',state,identity),'error\tInvalidState');recovery()
    # Exact all-state F32 widening is independently checked with rational arithmetic.
    for row in observed:
        for f in R.FIELDS:
            raw=int(row[f+'_f32_bits'],16);wide=int(row[f+'_promoted_f64_bits'],16)
            require(L.exact(raw,32)==L.exact(wide,64),'Independent exact widening mismatch')
    mutations=[('empty',b''),('truncated',table[:-1]),('missing-header',table.split(b'\n',1)[1]),
               ('wrong-format',table.replace(b'Primitives\t1\t',b'Primitives\t2\t',1)),
               ('wrong-version',table.replace(b'\t26.3\t',b'\t26.4\t',1)),
               ('wrong-header-identity',table.replace(identity.encode(),b'0'*64,1)),
               ('wrong-header-count',table.replace(b'\t35723\n',b'\t35724\n',1)),
               ('wrong-column',table.replace(b'friction_f32_bits',b'friction_f64_bits',1)),
               ('valid-factor-corruption',table.replace(b'1058642330',b'1065353216',1)),
               ('unsigned-overflow',table.replace(b'1058642330',b'4294967296',1)),
               ('nonfinite-factor',table.replace(b'1058642330',b'2139095040',1)),
               ('negative-raw-integer',table.replace(b'1058642330',b'-1',1)),
               ('fractional-raw-integer',table.replace(b'1058642330',b'1.0',1)),
               ('blank-row',table+b'\n'),('trailing-member',table+b'0\t1\t1\t1\t1\n'),
               ('crlf',table.replace(b'\n',b'\r\n')),('missing-final-newline',table[:-1]),
               ('embedded-NUL',table+b'\x00'),('gap',table.replace(b'0\t8597\t',b'1\t8597\t',1)),
               ('overlap',table.replace(b'8597\t1\t',b'8596\t1\t',1)),
               ('empty-interval',table.replace(b'8597\t1\t',b'8597\t0\t',1)),
               ('interval-overflow',table.replace(b'8597\t1\t',b'4294967295\t2\t',1)),
               ('capacity-overflow',table+table.split(b'\n',2)[2]),
               ('UTF8-BOM',b'\xef\xbb\xbf'+table),('invalid-UTF8',table+b'\xff'),
               ('overlong-UTF8',table+b'\xc0\x80'),('UTF8-surrogate',table+b'\xed\xa0\x80'),
               ('at-byte-limit',b'x'*8192),('over-byte-limit',b'x'*8193)]
    manifest=[]
    for name,data in mutations:
        path=fixtures/(name+'.tsv');path.write_bytes(data)
        manifest.append({'name':name,'bytes':len(data),'sha256':P.sha(data)})
        try:data.decode('utf-8');valid_unicode=True
        except UnicodeDecodeError:valid_unicode=False
        text_error='TextError' if not valid_unicode or len(data)>8192 else 'IntegrityMismatch'
        for mode in ('parse','replace','bind','load'):
            error='ByteLimit' if mode=='load' and len(data)>8192 else text_error
            args=(mode,identity,35723,path) if mode=='parse' else (mode,path)
            add(name+'-'+mode,'catalog-corruption',args,'error\t'+error);recovery()
    for ident,count in (('wrong',35723),(identity,0),(identity,35722),(identity,35724),(identity,4294967295)):
        error='IdentityMismatch' if ident!=identity else 'StateCountMismatch'
        add('parser-context-'+str(count),'parse-context',('parse',ident,count,R.TABLE),'error\t'+error);recovery()
    for words,name,error in (([256],'raw-byte-256','TextError'),([4294967295],'raw-byte-max','TextError'),([0xff],'raw-byte-invalid-UTF8','TextError'),([120]*8193,'decode-byte-limit','ByteLimit'),([120]*8192,'decode-at-limit','IntegrityMismatch'),(list(table),'decode-canonical',None)):
        path=fixtures/(name+'.u32');path.write_bytes(struct.pack('<'+'I'*len(words),*words))
        add(name,'decode',('decode',identity,35723,path),'error\t'+error if error else 'ok\tdecode');recovery()
    add('invalid-Unicode-scalar','encode',('invalid-scalar',),'error\tTextError');recovery()
    for path in (fixtures/'absent',fixtures):
        add('read-failure-'+path.name,'io',('load',path),'error\tReadError');recovery()
    # Enough real failed opens/reads to expose descriptor leaks in this process.
    corrupt=fixtures/'valid-factor-corruption.tsv'
    for i in range(1024):
        add('repeated-failed-load-'+str(i),'io-repeat',('load',corrupt),'error\tIntegrityMismatch');recovery()
    for mode in ('replace','parse','bind','load'):
        args=(mode,identity,35723,R.TABLE) if mode=='parse' else (mode,R.TABLE)
        add('valid-'+mode,'valid-replacement',args,'ok\t'+mode);recovery()
    for kind in ('zero-count','large-count','max-count','wrong-states','wrong-identity','short-array','empty-range','overflow-range'):
        add('forge-'+kind,'forged-owner',('forge',kind),'ok\tforge')
        for _ in range(2):add('retained-forged-'+kind,'forged-owner',('query',0,identity),'error\tCatalogCorrupt')
        add('bound-before-forged-'+kind,'forged-owner',('query',4294967295,identity),'error\tInvalidState')
        add('recover-forged-'+kind,'forged-owner',('replace',R.TABLE),'ok\treplace');recovery()
    tiny=fixtures/'foreign-registry.tsv';tiny.write_text('block_protocol_id\tidentifier\tfirst_state_id\tstate_count\tdefault_state_id\tordered_properties_json\n0\tminecraft:air\t0\t1\t0\t[]\n')
    foreign_id,_,_=registry_identity(tiny)
    add('foreign-registry-owner','bind-ownership',('foreign',tiny,R.TABLE),'error\tIdentityMismatch\t'+foreign_id);recovery()
    add('registry-owner-retained','bind-ownership',('inspect',),'ok\tregistry\t'+identity+'\tminecraft:ice\t8597')
    request_path=WORK/'requests.tsv';request_path.write_text('\n'.join(commands)+'\n')
    output_path=WORK/'expected.tsv';output_path.write_text('\n'.join(expected)+'\n')
    metadata={'cases':len(commands),'categories':dict(collections.Counter(categories)),'request_sha256':P.sha(request_path.read_bytes()),'expected_sha256':P.sha(output_path.read_bytes()),'requests':fingerprint(request_path),'expected':fingerprint(output_path),'corrupt_catalog_manifest_sha256':P.sha(canonical(manifest)),'corrupt_catalog_fixtures':len(manifest),'independent_exact_F32_widening_pairs':35723*3,'all_state_orders':['forward','reverse'],'seeded_repeat_queries':1024,'repeated_failed_actual_loads':1024}
    P.write_json(WORK/'case-manifest.json',[{'name':n,'category':c,'request':q,'expected':e} for n,c,q,e in zip(names,categories,commands,expected)])
    return metadata

def receipt_check(sources):
    receipt=json.loads(RECEIPT.read_text());artifact=P.check_receipt(sources,receipt)
    require(P.sha(BINARY.read_bytes())==receipt['build']['binary_sha256'],'convenience binary changed')
    return receipt,artifact

def receipt_selftests(sources,receipt):
    passed=[]
    for name in ('source','missing-source','cache-key','binary-sha','binary-size','C-sha','compiler','dependency-sha','missing-dependency','artifact-alias'):
        altered=copy.deepcopy(receipt);build=altered['build']
        if name=='source':altered['sources_sha256']['src/block_physics.bend']='0'*64
        elif name=='missing-source':del altered['sources_sha256']['src/block_physics.bend']
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

def build(sources):
    report=WORK/'build.json';command=[sys.executable,ROOT/'tools/build_native.py',ENTRY,'-o',BINARY,'--bend',BEND,'--report',report]
    child=subprocess.Popen([str(x) for x in command],cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE,start_new_session=True)
    print(json.dumps({'status':'native-build-started','pid':child.pid,'entry':'tests/block_physics.bend','sources_sha256':sources}),flush=True)
    try:stdout,stderr=child.communicate(timeout=600)
    except subprocess.TimeoutExpired:os.killpg(child.pid,signal.SIGKILL);child.communicate();raise AssertionError('600s native build timeout')
    require(child.returncode==0,'native build failed '+stderr.decode()[-2500:]);require(sources==source_hashes(),'source changed during build')
    P.write_json(RECEIPT,{'sources_sha256':sources,'build':json.loads(report.read_text())})
    return receipt_check(sources)

def native(sources,receipt,artifact,corpus_info):
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
        for index,(a,b) in enumerate(zip(actual,expected)):
            require(a==b,'case '+str(index)+' mismatch '+(WORK/'requests.tsv').read_text().splitlines()[index]+' observed='+a+' expected='+b)
        runs.append({'pid':process.pid,'seconds':round(time.monotonic()-started,6),'output_sha256':P.sha(output.read_bytes()),'responses':len(actual)})
        receipt_check(sources)
    require(runs[0]['output_sha256']==runs[1]['output_sha256']==corpus_info['expected_sha256'],'two-run native byte agreement failed')
    require(source_hashes()==sources,'source changed during runs')
    b=receipt['build'];summary={k:b[k] for k in ('artifact','cache_key','binary_sha256','binary_bytes','emitted_c_sha256','timings')}
    summary.update(compiler={k:v for k,v in b['compiler'].items() if k!='driver_probe'},compiler_driver_probe_sha256=P.sha(b['compiler']['driver_probe'].encode()),dependency_count=len(b['dependencies']),dependency_manifest_sha256=P.sha(canonical(b['dependencies'])),ignored_receipt_sha256=P.sha(RECEIPT.read_bytes()))
    return {'status':'passed','runs':runs,'corpus':corpus_info,'sources_sha256':sources,'build':summary,'receipt_corruption':corruption,'confidence':'high for pinned stored primitives, exact widening and tested admission/affine-owner behavior','scope':['No sampled collision/outline/shape/light output is included or generalized.','Only admitted Catalog parse/decode/bind/load/replace/query; raw constructors remain outside integrity admission.','No world-position-dependent application, travel equation, slip/block effects or current SupportWorld integration is established.']}

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--preflight',action='store_true');parser.add_argument('--build-only',action='store_true');parser.add_argument('--skip-build',action='store_true');parser.add_argument('--kernel',action='store_true');args=parser.parse_args()
    info=R.verify_existing();reference_defensive=reference_selftests(info);cases=corpus(info);sources=source_hashes()
    ordinary=[P.bounded_run([BEND,path,'--check-only']) for path in (SOURCE,ENTRY)]
    require(all(x['exit_code']==0 and 'ALL PROOFS CHECK' in x['stdout'] for x in ordinary),'ordinary source/harness checking failed')
    preflight={'status':'prepared-native-kernel-unverified','sources_sha256':sources,'ordinary':ordinary,'corpus':cases,'reference_file_sha256':P.sha(R.REFERENCE.read_bytes()),'reference_probe_tool_sha256':P.sha(Path(R.__file__).read_bytes()),'reference_corruption':reference_defensive,'runner_sha256':P.sha(Path(__file__).read_bytes()),'table':fingerprint(R.TABLE),'registry_identity':info['registry_identity']}
    P.write_json(ROOT/'evidence/block-physics-preflight.json',preflight)
    if args.preflight:print(json.dumps({'status':'prepared','cases':cases['cases'],'corrupt_catalogs':cases['corrupt_catalog_fixtures'],'sources':len(sources),'table_bytes':info['derived_table']['bytes']}));return
    receipt,artifact=receipt_check(sources) if args.skip_build else build(sources)
    if args.build_only:print(json.dumps({'status':'built','binary_sha256':receipt['build']['binary_sha256']}));return
    result=native(sources,receipt,artifact,cases);result.update(ordinary=ordinary,reference_corruption=reference_defensive,runner_sha256=preflight['runner_sha256'],reference_file_sha256=preflight['reference_file_sha256'])
    P.write_json(ROOT/'evidence/block-physics-native.json',result)
    if args.kernel:
        kernel=P.bounded_run([BEND,SOURCE,'--verdict'],timeout=60,allow_timeout=True)
        status='timeout' if kernel['timed_out'] else 'passed' if kernel['exit_code']==0 and 'ALL PROOFS CHECK' in kernel['stdout'] else 'failed'
        P.write_json(ROOT/'evidence/block-physics-kernel.json',{'status':status,'commands':[kernel],'sources_sha256':sources,'scope':'Production module with three rejection/owner-retention laws; no movement or universal block behavior theorem.'})
    print(json.dumps({'status':'passed','cases_per_run':cases['cases'],'runs':2,'output_sha256':result['runs'][0]['output_sha256']}))

if __name__=='__main__':main()
