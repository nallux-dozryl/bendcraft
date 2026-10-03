#!/usr/bin/env python3
"""Run the actual Bend RNG module against official Java26.3 observations."""
from __future__ import annotations
import argparse, collections, hashlib, json, pathlib, subprocess, time
from reference_inventory import ROOT, JAVA, canonical, fingerprint, write_json
from reference_block_probe import verified_classpath
from reference_random_probe import SOURCE, generate_inputs

BEND=pathlib.Path('/Users/chuah/.bend/bin/bend')


def main():
    parser=argparse.ArgumentParser();parser.add_argument('--refresh-reference',action='store_true');parser.add_argument('--random',type=int,default=1000);args=parser.parse_args()
    commands=[['python3','tools/test_random.py']+(['--refresh-reference','--random',str(args.random)] if args.refresh_reference else [])]
    def run(cmd,record=True,**kw):
        command=list(map(str,cmd))
        if record: commands.append(command)
        result=subprocess.run(command,cwd=ROOT,text=True,capture_output=True,check=True,**kw)
        if command[0]==str(BEND): assert 'SOME PROOFS FAIL' not in result.stdout,result.stdout+result.stderr
        return result
    if args.refresh_reference:
        run(['python3','tools/reference_random_probe.py','--random',args.random])
    reference=json.loads((ROOT/'reference/random.json').read_text()); cases=reference['cases']
    assert reference['pin']=='26.3' and reference['schema']==1
    assert hashlib.sha256(canonical(cases)).hexdigest()==reference['cases_sha256']
    assert hashlib.sha256(SOURCE.encode()).hexdigest()==reference['probe']['java_source_sha256']
    inputs=[{k:c[k] for k in ['id','protocol','tags']} for c in cases]
    assert inputs==generate_inputs(reference['random_input_cases'])
    _,release=verified_classpath()
    assert release['server_bundle']['nested_server_sha256']==reference['nested_server_sha256']
    assert fingerprint(JAVA)==reference['runtime_executable']
    verdict=run([BEND,'src/random.bend','--verdict'])
    assert 'ALL PROOFS CHECK' in verdict.stdout,verdict.stdout+verdict.stderr
    binary=ROOT/'build/random_test';run([BEND,'tests/random.bend','-o',binary])
    cfile=ROOT/'build/random_test.c';run([BEND,'tests/random.bend','-o',cfile])
    started=time.monotonic();observations=0;op_counts=collections.Counter();errors=collections.Counter();draws=collections.Counter()
    for offset in range(0,len(cases),25):
        batch=cases[offset:offset+25]
        actual=run([binary,'--gpu','off','--threads','1',*[c['protocol'] for c in batch]],record=False).stdout.splitlines()
        expected=[line for c in batch for line in c['expected']]
        if actual!=expected:
            for i,(a,e) in enumerate(zip(actual,expected)):
                if a!=e:
                    identity=e.split('|',1)[0];case=next(c for c in batch if c['id']==identity)
                    raise AssertionError(f'RNG mismatch at output{i}\nactual  {a}\nexpected{e}\ninput   {case["protocol"]}')
            raise AssertionError(f'RNG output count mismatch actual{len(actual)} expected{len(expected)}')
        observations+=len(actual)
        for c in batch:
            op_counts.update(op.split(':',1)[0] for op in c['protocol'].split('|')[6].split(';'))
            draws.update(c['bounded_primitive_draws'])
            errors.update(line.split('|')[2] for line in c['expected'] if line.split('|')[2] in ['invalid','fuel','unsupported'])
    evidence={'schema':1,'result':'pass','pin':'26.3','kernel_verdict':'ALL PROOFS CHECK','proof_scope':'Typing/termination and seven actual state-boundary/advancement laws; not complete RNG/bit-arithmetic equivalence theorem','reference_cases':len(cases),'native_observations':observations,'native_operations':sum(op_counts.values()),'direct_java_output_state_or_mapped_error_observations':observations-errors['fuel']-errors['unsupported'],'bend_extension_rollback_observations':errors['fuel']+errors['unsupported'],'operation_counts':dict(sorted(op_counts.items())),'checked_errors':dict(sorted(errors.items())),'java_bounded_draw_histogram':dict(sorted(draws.items())),'wall_seconds':time.monotonic()-started,'reference_cases_sha256':reference['cases_sha256'],'reference_nested_server_sha256':reference['nested_server_sha256'],'source_inventory':reference['source_inventory'],'source_sha256':{p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in ['src/random.bend','tests/random.bend','tools/test_random.py','tools/reference_random_probe.py']},'native_binary_sha256':fingerprint(binary)['sha256'],'emitted_c':fingerprint(cfile),'commands':commands,'unsupported':['Gaussian','Xoroshiro MD5 string hashing','nondeterministic unique/thread-local seeding','threading detector/concurrent mutation semantics','world generation parity'],'rejection_fuel':'Each candidate consumes one fuel unit; any error returns the original source. Successful results match official Java output and exact advancement.'}
    evidence['native_command_prefix']=['build/random_test','--gpu','off','--threads','1']
    evidence['fixture_batch_size']=25
    evidence['native_process_invocations']=(len(cases)+24)//25
    write_json(ROOT/'evidence/random-oracle.json',evidence)
    print(json.dumps({k:evidence[k] for k in ['result','reference_cases','native_observations','native_operations','operation_counts','checked_errors','java_bounded_draw_histogram','wall_seconds']},sort_keys=True))

if __name__=='__main__': main()
