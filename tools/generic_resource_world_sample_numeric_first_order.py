#!/usr/bin/env python3
"""Prepare first-order production scanner copies and reuse focused producers.

Default is file-only. Each explicit build uses the previously verified private
producer, unchanged original request harness and cached Java corpus. This tool
does not supply a parser, compiler implementation or new expected result.
"""
from __future__ import annotations

import argparse
import difflib
import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OLD = ROOT/'build/generic-resource-world-sample-numeric-continuations-001/candidate-001'
WORK = ROOT/'build/generic-resource-world-sample-numeric-first-order-001'
CORPUS = ROOT/'build/generic-resource-world-sample-numeric-original-corpus-001'
PYTHON = Path.home()/'.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3'


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def pin(path):
    path = Path(path).resolve(strict=True)
    return {'path':str(path),'bytes':path.stat().st_size,'sha256':sha(path)}


def write(path, value):
    with Path(path).open('x') as handle:
        json.dump(value, handle, indent=2, sort_keys=True)
        handle.write('\n')


def candidate(original, name):
    model = name == 'block_model'
    public = 'int_scan' if model else 'scan_number'
    worker = public + '_admitted'
    start = original.index('def '+public+'(')
    end = original.index('\ndef digit_word(', start)
    old = original[start:end]
    body = old.replace(public+'(', worker+'(')
    if model:
        body = body.replace('def '+worker+'(text: String, +stage:',
                            'def '+worker+'(text: String, admitted: Bool, +stage:')
        body = body.replace('    case SNil{}: Done{IntToken{List.reverse(&2, U32, reversed), fraction, exponent, exponent_negative, negative}}',
            '    case SNil{}: int_scan_finished(admitted, reversed, fraction, exponent, exponent_negative, negative)')
        body = body.replace('      match c:\n', '      match c admitted:\n'
            '        case _ False{}: fail(IntToken, "UnsupportedIntegerExponent", "integer")\n')
        for pattern in ('45','43','46','101','69','_'):
            body = body.replace('\n        case '+pattern+':', '\n        case '+pattern+' True{}:')
        body = body.replace(worker+'(rest,', worker+'(rest, True{},')
        branch = '''              int_exponent_guard(next, U32.is_le(next, 100000),
                value => int_scan_admitted(rest, True{}, stage, reversed, fraction, value, exponent_negative, negative))'''
        direct = '''              int_scan_admitted(rest, U32.is_le(next, 100000), stage, reversed, fraction, next, exponent_negative, negative)'''
        wrapper = '''def int_scan(text: String, +stage: U32, reversed: List<&2, U32>, +fraction: U32, +exponent: U32,
  +exponent_negative: Bool, +negative: Bool) -> Result<&2, &2, Error, IntToken>:
  int_scan_admitted(text, True{}, stage, reversed, fraction, exponent, exponent_negative, negative)
'''
        finish = '''def int_scan_finished(admitted: Bool, reversed: List<&2, U32>, fraction: U32, exponent: U32,
  exponent_negative: Bool, negative: Bool) -> Result<&2, &2, Error, IntToken>:
  match admitted:
    case False{}: fail(IntToken, "UnsupportedIntegerExponent", "integer")
    case True{}: Done{IntToken{List.reverse(&2, U32, reversed), fraction, exponent, exponent_negative, negative}}

'''
    else:
        body = body.replace('def '+worker+'(+text:String,+stage:',
                            'def '+worker+'(+text:String,admitted:Bool,+stage:')
        body = body.replace('    case SNil{}: Done{NumberParts{List.reverse(&2,U32,digits),fraction,exponent,eneg,negative}}',
            '    case SNil{}: scan_number_finished(admitted,digits,fraction,exponent,eneg,negative,path)')
        body = body.replace('      match c:\n', '      match c admitted:\n'
            '        case _ False{}: fail(NumberParts,"IntegerExponentLimit",path,"Exponent magnitude exceeds 100000")\n')
        for pattern in ('45','43','46','101','69','_'):
            body = body.replace('\n        case '+pattern+':', '\n        case '+pattern+' True{}:')
        body = body.replace(worker+'(rest,', worker+'(rest,True{},')
        branch = '''              scan_number_exponent_guard(next,U32.is_le(next,100000),path,
                value => scan_number_admitted(rest,True{},stage,digits,fraction,value,eneg,negative,path))'''
        direct = '''              scan_number_admitted(rest,U32.is_le(next,100000),stage,digits,fraction,next,eneg,negative,path)'''
        wrapper = '''def scan_number(+text:String,+stage:U32,+digits:List<&2,U32>,+fraction:U32,+exponent:U32,+eneg:Bool,+negative:Bool,+path:String)
  -> Result<&2,&2,Error,NumberParts>:
  scan_number_admitted(text,True{},stage,digits,fraction,exponent,eneg,negative,path)
'''
        finish = '''def scan_number_finished(admitted:Bool,digits:List<&2,U32>,fraction:U32,exponent:U32,eneg:Bool,negative:Bool,path:String)
  -> Result<&2,&2,Error,NumberParts>:
  match admitted:
    case False{}: fail(NumberParts,"IntegerExponentLimit",path,"Exponent magnitude exceeds 100000")
    case True{}: Done{NumberParts{List.reverse(&2,U32,digits),fraction,exponent,eneg,negative}}

'''
    assert body.count(branch) == 1, 'Exact exponent branch mismatch'
    body = body.replace(branch, direct)
    assert '=>' not in body and body.count('case _ False{}:') == 1
    assert body.count('case _ True{}:') == 1, 'Character admission must not change stage patterns'
    return original[:start] + finish + body + '\n' + wrapper + original[end:]


def prepare():
    assert not WORK.exists(), 'Preserve each private attempt'
    WORK.mkdir()
    for name in ('source','source-api'):
        shutil.copytree(OLD/name, WORK/name)
    changes = []
    for name in ('block_model','blockstate_model'):
        cached = OLD/'source/src'/(name+'.bend')
        production = ROOT/'src'/(name+'.bend')
        assert cached.read_bytes() == production.read_bytes(), 'Cached baseline drift'
        original = cached.read_text()
        value = candidate(original, name)
        path = WORK/'source/src'/(name+'.bend')
        path.chmod(path.stat().st_mode | 0o200)
        path.write_text(value)
        (WORK/(name+'.diff')).write_text(''.join(difflib.unified_diff(
            original.splitlines(True), value.splitlines(True),
            fromfile='cached-production/'+name+'.bend',tofile='first-order/'+name+'.bend')))
        changes.append({'baseline':pin(cached),'working_production':pin(production),
                        'candidate':pin(path),'diff':pin(WORK/(name+'.diff'))})
    for name in ('block_model','blockstate_model'):
        basis = OLD/'focused-native-001'/('candidate-'+name)
        output = WORK/('candidate-'+name)
        output.mkdir()
        for filename in ('comp_instrumented.ts','diagnose.mjs','run.py'):
            value = (basis/filename).read_text()
            # Mechanical path relocation only; compiler bodies are unchanged.
            value = value.replace(str(basis), str(output)).replace(str(OLD), str(WORK))
            (output/filename).write_text(value)
        manifest = json.loads((basis/'manifest.json').read_text())
        files = {}
        for filename in manifest['files']:
            located = filename.replace(str(basis),str(output)).replace(str(OLD),str(WORK))
            files[located] = sha(located)
        manifest['files'] = files
        manifest['scope'] = ('Actual unchanged '+name+' request/serialization harness '
            'with first-order admitted scanner worker. Cached original Java expectations '
            'are separate from compilation; no whole-client timing claim.')
        write(output/'manifest.json', manifest)
    write(WORK/'preparation.json', {'status':'private_source_prepared',
        'changes':changes,'cached_baseline_native':[
            pin(OLD/'focused-native-001'/('candidate-'+name)/'native')
            for name in ('block_model','blockstate_model')],
        'scope':'Only scanner worker/wrapper sections differ. Existing guards remain '
            'available for prior laws but are absent from scanner calls. No build or native verdict.'})
    return {'status':'private_source_prepared','directory':str(WORK)}


def build(name):
    output = WORK/('candidate-'+name)
    assert not (output/'receipt.json').exists(), 'Preserve prior attempt'
    returncode = subprocess.run(['python3',str(output/'run.py')],cwd=ROOT).returncode
    assert returncode == 0
    receipt = json.loads((output/'receipt.json').read_text())
    assert receipt['returncode'] == 0 and receipt['termination_reason'] is None
    assert receipt['complete_C'] and receipt['group_absent']
    assert receipt['source_before'] == receipt['source_after']
    return {'status':'C_pass','harness':name,'seconds':receipt['seconds'],
            'C':receipt['C'],'receipt':pin(output/'receipt.json')}


def native_tools():
    # Existing native test orchestration imports the installed NumPy/Pillow.
    if Path(sys.executable).resolve() != PYTHON.resolve():
        import os
        os.execv(str(PYTHON), [str(PYTHON), __file__, *sys.argv[1:]])
    import test_remote_resource_client as remote
    remote.WORK = WORK/'native-runs'
    return remote


def clang(name):
    remote = native_tools()
    import build_native
    output = WORK/('candidate-'+name)
    receipt = json.loads((output/'receipt.json').read_text())
    assert receipt['returncode'] == 0 and receipt['termination_reason'] is None
    assert receipt['complete_C'] and receipt['group_absent']
    assert receipt['source_before'] == receipt['source_after']
    source = output/'diagnostic.c'
    assert sha(source) == receipt['C']['sha256']
    build_native.guard_route(source.read_text())
    binary = output/'native'
    assert not binary.exists(), 'Preserve native attempt'
    sdk_result = remote.bounded(['/usr/bin/xcrun','--sdk','macosx','--show-sdk-path'],
                                30,'sdk-'+name)
    remote.process_ok(sdk_result)
    sdk = (remote.WORK/('sdk-'+name)/'stdout').read_text().strip()
    assert Path(sdk).is_dir()
    result = remote.bounded(['/usr/bin/env','SDKROOT='+sdk,'/usr/bin/clang',
        '-std=c11','-O3',source,'-lpthread','-lm','-o',binary],300,'clang-'+name)
    remote.process_ok(result)
    assert not (remote.WORK/('clang-'+name)/'stderr').read_bytes()
    assert sha(source) == receipt['C']['sha256']
    value = {'status':'native_build_pass','harness':name,'C':pin(source),
             'binary':pin(binary),'seconds':result['seconds']}
    write(output/'clang-result.json',value)
    return value


def compare_native():
    remote = native_tools()
    assert not (WORK/'native-result.json').exists(), 'Preserve native comparison'
    expected_pins = {'cached-corpus.json':'96a3769487bb57897b3bd1dc7ad7baead828b586eed7260739565fb3e9fc293a',
                     'exponent-corpus.json':'ccfd19ce6afd53666679a3718a4bed9133d96af31348db96421ea873fb0d75ac'}
    for name, expected in expected_pins.items():
        assert sha(CORPUS/name) == expected
    rows = sum((json.loads((CORPUS/name).read_text())['cases'] for name in expected_pins),[])
    baseline_dir = OLD/'focused-native-001'
    baseline = json.loads((baseline_dir/'native-observations.json').read_text())['candidate']
    baseline_result = json.loads((baseline_dir/'native-result.json').read_text())
    assert baseline_result['status'] == 'PASS' and baseline_result['original_java_cases_per_variant'] == 45
    assert baseline_result['corpus_sha256'] == expected_pins
    assert sha(baseline_dir/'native-observations.json') == baseline_result['observations_sha256']
    assert sha(baseline_dir/'refusal-inputs.json') == baseline_result['refusal_inputs_sha256']
    refusals = json.loads((baseline_dir/'refusal-inputs.json').read_text())['cases']
    assert len(rows) == 45 and len(refusals) == 4
    canonical = lambda x: json.dumps(x,sort_keys=True,separators=(',',':'),allow_nan=False)
    observed = {'original_java':[],'bounded_refusals':[]}
    for kind, name in (('model','block_model'),('blockstate','blockstate_model')):
        binary = WORK/('candidate-'+name)/'native'
        before = pin(binary)
        assert before == json.loads((binary.parent/'clang-result.json').read_text())['binary']
        for label, cases in (('original_java',rows),('bounded_refusals',refusals)):
            selected = [row for row in cases if row['kind'] == kind]
            offset = 0
            while offset < len(selected):
                chunk = []
                args = []
                for row in selected[offset:]:
                    value = row['text'] if kind == 'model' else canonical(row['request'])
                    if args and ((kind == 'model' and len(args) >= 15) or
                                 (kind != 'model' and sum(map(len,args))+len(value)>65536)):
                        break
                    chunk.append(row)
                    args.append(value)
                stage = name+'-'+label+'-'+str(offset)
                result = remote.bounded([binary,'--threads','1',*args],180,stage)
                remote.process_ok(result)
                stdout = (remote.WORK/stage/'stdout').read_text().splitlines()
                assert len(stdout) == len(chunk)
                assert not (remote.WORK/stage/'stderr').read_bytes()
                for row, raw in zip(chunk,stdout,strict=True):
                    if kind == 'model':
                        prefix, separator, payload = raw.partition('\t')
                        assert separator and prefix in ('ok','error')
                        actual = ({'status':'ok','parsed':json.loads(payload)} if prefix == 'ok'
                                  else {'status':'error'})
                    else:
                        actual = json.loads(raw)
                    if label == 'original_java':
                        assert actual['status'] == row['expected']['status']
                        if actual['status'] == 'ok':
                            comparable = ({k:v for k,v in actual.items() if k != 'diagnostics'}
                                          if kind == 'blockstate' else actual)
                            assert canonical(comparable) == canonical(row['expected'])
                    else:
                        prior = next(old for old in baseline[label] if old['id'] == row['id'])
                        assert actual['status'] == 'error'
                        assert canonical(actual) == canonical(prior['actual'])
                        if kind == 'model':
                            assert raw == prior['raw']
                    observed[label].append({'id':row['id'],'kind':kind,'raw':raw,'actual':actual})
                offset += len(chunk)
        assert pin(binary) == before
    for name, expected in expected_pins.items():
        assert sha(CORPUS/name) == expected
    write(WORK/'native-observations.json',observed)
    result = {'status':'PASS','candidate_original_java_cases':45,'candidate_bounded_refusals':4,
        'complete_success_projection':True,'refusals_exact_cached_baseline':True,
        'baseline_not_reexecuted':True,'corpus_sha256':expected_pins,
        'observations':pin(WORK/'native-observations.json'),
        'cached_baseline_observations':pin(baseline_dir/'native-observations.json'),
        'scope':'Accepted outputs compare the complete existing original-Java projection; '
                'Java rejections compare status, separate bounded refusals compare exact '
                'cached baseline error records. No whole-parser theorem or client runtime claim.'}
    write(WORK/'native-result.json',result)
    return result


def report():
    native = json.loads((WORK/'native-result.json').read_text())
    assert native['status'] == 'PASS'
    rows = []
    for name, scanner in (('block_model','int_scan'),('blockstate_model','scan_number')):
        directory = WORK/('candidate-'+name)
        baseline = OLD/'focused-native-001'/('candidate-'+name)
        metrics = []
        for label, path in (('cached_production',baseline),('first_order',directory)):
            receipt = json.loads((path/'receipt.json').read_text())
            assert receipt['returncode'] == 0 and receipt['termination_reason'] is None
            assert receipt['group_absent'] and receipt['source_before'] == receipt['source_after']
            assert sha(path/'diagnostic.c') == receipt['C']['sha256']
            names = {scanner, scanner+'_admitted',scanner+'_finished'} if label == 'first_order' else {scanner,
                'int_exponent_guard' if name == 'block_model' else 'scan_number_exponent_guard'}
            bodies = [row for row in receipt['producer_rows'] if row.get('phase') == 'emit_end'
                      and row.get('name','').partition(':')[2] in names]
            last_pass = max(row['pass'] for row in bodies)
            metrics.append({'variant':label,'C':pin(path/'diagnostic.c'),
                'emission_seconds':receipt['seconds'],'receipt':pin(path/'receipt.json'),
                'scanner_plus_helper_final_lines':sum(row['lines'] for row in bodies
                                                     if row['pass'] == last_pass),
                'scanner_plus_helper_all_body_seconds':sum(row['elapsed_ms'] for row in bodies)/1000,
                'ownership_passes':last_pass,'group_absent':True})
        rows.append({'harness':name,'measurements':metrics,
            'whole_C_reduction_percent':100*(1-metrics[1]['C']['bytes']/metrics[0]['C']['bytes']),
            'candidate_binary':json.loads((directory/'clang-result.json').read_text())['binary']})
    result = {'status':'focused_C_and_native_PASS','preparation':pin(WORK/'preparation.json'),
        'native':native,'C_comparison':rows,
        'retained_full_client_failure':pin(ROOT/'evidence/generic_resource_world_sample_client_native_005.json'),
        'production_adopted':False,'ordinary_equivalence_proof':'unverified',
        'independent_kernel':'unrun','full_changed_client':'unrun',
        'scope':'Actual two unchanged production numeric decoder harnesses and cached original '
                'Java cases. C-size differences are measured; emission times are sequential '
                'historical observations under differing machine workloads, not a controlled '
                'speedup. No whole-parser theorem, heartbeat or client timing result.'}
    write(WORK/'focused-comparison.json',result)
    write(ROOT/'evidence/generic_resource_world_sample_numeric_first_order.json',result)
    return {k:v for k,v in result.items() if k != 'native'}


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--generation',type=int,default=1)
    phase = parser.add_mutually_exclusive_group()
    phase.add_argument('--build', choices=('block_model','blockstate_model'))
    phase.add_argument('--clang', choices=('block_model','blockstate_model'))
    phase.add_argument('--compare-native', action='store_true')
    phase.add_argument('--report', action='store_true')
    args = parser.parse_args()
    assert 1 <= args.generation <= 999
    WORK = ROOT/('build/generic-resource-world-sample-numeric-first-order-'+str(args.generation).zfill(3))
    value = (build(args.build) if args.build else clang(args.clang) if args.clang else
             compare_native() if args.compare_native else report() if args.report else prepare())
    print(json.dumps(value),flush=True)
