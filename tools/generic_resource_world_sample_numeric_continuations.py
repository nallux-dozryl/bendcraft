#!/usr/bin/env python3
"""Freeze a private numeric-continuation candidate; start no toolchain or game.

The only production changes are two exponent branches and their scalar guards.
Original source/API copies, branch diffs, and candidate laws are retained beside
the candidate. This prepares source, not a checker/kernel/native verdict.
"""
from __future__ import annotations

import argparse
import difflib
import hashlib
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ORIGINAL = ROOT/'build/generic-resource-world-sample-client-native/002/private'
WORK = ROOT/'build/generic-resource-world-sample-numeric-continuations-001/candidate-001'
PREFIX = 'generic_resource_world_sample_numeric_continuations'
INPUT_SHA256 = {
    'source/src/block_model.bend': '08108bae9b89c6768de56bdddea158f3604b36c7de4ee0408815e2c7f48b97a1',
    'source/src/blockstate_model.bend': 'd084876d32e232c3869be84bc07535b491274695bd91529c5fae159b290cdc57',
    'source/src/json.bend': 'a1789e3b4f5bea158ec0d95a8bcb39aa5b7c7e7355a5254d3de1d52a93c719d1',
    'source-api/base.bend': 'c742fae9c49b14f0cc9128429a2c6109364c8a933a142f2c90b9f2e5fd976661',
}

MODEL_OLD = '''              do Result<&2, &2, Error, IntToken>:
                next : U32 <- J.choose(Result<&2, &2, Error, U32>,
                  Done{U32.add(U32.mul(exponent, 10), U32.sub(c, 48))},
                  fail(U32, "UnsupportedIntegerExponent", "integer"),
                  U32.is_le(U32.add(U32.mul(exponent, 10), U32.sub(c, 48)), 100000))
                int_scan(rest, stage, reversed, fraction, next, exponent_negative, negative)
'''
MODEL_NEW = '''              +next = U32.add(U32.mul(exponent, 10), U32.sub(c, 48))
              int_exponent_guard(next, U32.is_le(next, 100000),
                value => int_scan(rest, stage, reversed, fraction, value, exponent_negative, negative))
'''
MODEL_GUARD = '''def int_exponent_guard(next: U32, allowed: Bool,
  continuation: U32 -> Result<&2, &2, Error, IntToken>) -> Result<&2, &2, Error, IntToken>:
  match allowed:
    case True{}: continuation(next)
    case False{}: fail(IntToken, "UnsupportedIntegerExponent", "integer")

'''
STATE_OLD = '''              do Result<&2,&2,Error,NumberParts>:
                next:U32 <- choose_value(Result<&2,&2,Error,U32>,Done{U32.add(U32.mul(exponent,10),U32.sub(c,48))},
                  fail(U32,"IntegerExponentLimit",path,"Exponent magnitude exceeds 100000"),
                  U32.is_le(U32.add(U32.mul(exponent,10),U32.sub(c,48)),100000))
                scan_number(rest,stage,digits,fraction,next,eneg,negative,path)
'''
STATE_NEW = '''              +next = U32.add(U32.mul(exponent,10),U32.sub(c,48))
              scan_number_exponent_guard(next,U32.is_le(next,100000),path,
                value => scan_number(rest,stage,digits,fraction,value,eneg,negative,path))
'''
STATE_GUARD = '''def scan_number_exponent_guard(next:U32,allowed:Bool,path:String,
  continuation:U32 -> Result<&2,&2,Error,NumberParts>) -> Result<&2,&2,Error,NumberParts>:
  match allowed:
    case True{}: continuation(next)
    case False{}: fail(NumberParts,"IntegerExponentLimit",path,"Exponent magnitude exceeds 100000")

'''

LAWS = '''import Base
import ./json.bend as J
import ./block_model.bend as M
import ./blockstate_model.bend as S

# These laws state the actual guard substitution for any affine continuation.
# They do not equate the complete original and candidate recursive parsers.
law model_guard_matches_original_result_continuation:
  for +next:U32
  for +allowed:Bool
  for continuation:U32 -> Result<&2,&2,M.Error,M.IntToken>
  {M.int_exponent_guard(next,allowed,continuation) ==
    Result.bind(&2,&2,M.Error,U32,M.IntToken,
      J.choose(Result<&2,&2,M.Error,U32>,Done{next},
        M.fail(U32,"UnsupportedIntegerExponent","integer"),allowed),
      continuation) : Result<&2,&2,M.Error,M.IntToken>}

law blockstate_guard_matches_original_result_continuation:
  for +next:U32
  for +allowed:Bool
  for +path:String
  for continuation:U32 -> Result<&2,&2,S.Error,S.NumberParts>
  {S.scan_number_exponent_guard(next,allowed,path,continuation) ==
    Result.bind(&2,&2,S.Error,U32,S.NumberParts,
      S.choose_value(Result<&2,&2,S.Error,U32>,Done{next},
        S.fail(U32,"IntegerExponentLimit",path,"Exponent magnitude exceeds 100000"),allowed),
      continuation) : Result<&2,&2,S.Error,S.NumberParts>}

law model_wrapped_update_matches_original_expression:
  for +exponent:U32
  for +c:U32
  for continuation:U32 -> Result<&2,&2,M.Error,M.IntToken>
  {M.int_exponent_guard(U32.add(U32.mul(exponent,10),U32.sub(c,48)),
      U32.is_le(U32.add(U32.mul(exponent,10),U32.sub(c,48)),100000),continuation) ==
    Result.bind(&2,&2,M.Error,U32,M.IntToken,
      J.choose(Result<&2,&2,M.Error,U32>,
        Done{U32.add(U32.mul(exponent,10),U32.sub(c,48))},
        M.fail(U32,"UnsupportedIntegerExponent","integer"),
        U32.is_le(U32.add(U32.mul(exponent,10),U32.sub(c,48)),100000)),
      continuation) : Result<&2,&2,M.Error,M.IntToken>}

law blockstate_wrapped_update_matches_original_expression:
  for +exponent:U32
  for +c:U32
  for +path:String
  for continuation:U32 -> Result<&2,&2,S.Error,S.NumberParts>
  {S.scan_number_exponent_guard(U32.add(U32.mul(exponent,10),U32.sub(c,48)),
      U32.is_le(U32.add(U32.mul(exponent,10),U32.sub(c,48)),100000),path,continuation) ==
    Result.bind(&2,&2,S.Error,U32,S.NumberParts,
      S.choose_value(Result<&2,&2,S.Error,U32>,
        Done{U32.add(U32.mul(exponent,10),U32.sub(c,48))},
        S.fail(U32,"IntegerExponentLimit",path,"Exponent magnitude exceeds 100000"),
        U32.is_le(U32.add(U32.mul(exponent,10),U32.sub(c,48)),100000)),
      continuation) : Result<&2,&2,S.Error,S.NumberParts>}

law model_guard_uses_actual_recursive_continuation:
  for +rest:String
  for +stage:U32
  for +reversed:List<&2,U32>
  for +fraction:U32
  for +next:U32
  for +exponent_negative:Bool
  for +negative:Bool
  for +allowed:Bool
  {M.int_exponent_guard(next,allowed,
      value => M.int_scan(rest,stage,reversed,fraction,value,exponent_negative,negative)) ==
    Result.bind(&2,&2,M.Error,U32,M.IntToken,
      J.choose(Result<&2,&2,M.Error,U32>,Done{next},
        M.fail(U32,"UnsupportedIntegerExponent","integer"),allowed),
      value => M.int_scan(rest,stage,reversed,fraction,value,exponent_negative,negative))
      : Result<&2,&2,M.Error,M.IntToken>}

law blockstate_guard_uses_actual_recursive_continuation:
  for +rest:String
  for +stage:U32
  for +digits:List<&2,U32>
  for +fraction:U32
  for +next:U32
  for +eneg:Bool
  for +negative:Bool
  for +path:String
  for +allowed:Bool
  {S.scan_number_exponent_guard(next,allowed,path,
      value => S.scan_number(rest,stage,digits,fraction,value,eneg,negative,path)) ==
    Result.bind(&2,&2,S.Error,U32,S.NumberParts,
      S.choose_value(Result<&2,&2,S.Error,U32>,Done{next},
        S.fail(U32,"IntegerExponentLimit",path,"Exponent magnitude exceeds 100000"),allowed),
      value => S.scan_number(rest,stage,digits,fraction,value,eneg,negative,path))
      : Result<&2,&2,S.Error,S.NumberParts>}
'''

PROOF = '''import Base
import ./generic_resource_world_sample_numeric_continuations_laws.bend as Laws
import ./block_model.bend as M
import ./blockstate_model.bend as S

def Laws.model_guard_matches_original_result_continuation(next,allowed,continuation):
  match allowed:
    case True{}: {==}
    case False{}: {==}

def Laws.blockstate_guard_matches_original_result_continuation(next,allowed,path,continuation):
  match allowed:
    case True{}: {==}
    case False{}: {==}

def Laws.model_wrapped_update_matches_original_expression(exponent,c,continuation):
  Laws.model_guard_matches_original_result_continuation(
    U32.add(U32.mul(exponent,10),U32.sub(c,48)),
    U32.is_le(U32.add(U32.mul(exponent,10),U32.sub(c,48)),100000),continuation)

def Laws.blockstate_wrapped_update_matches_original_expression(exponent,c,path,continuation):
  Laws.blockstate_guard_matches_original_result_continuation(
    U32.add(U32.mul(exponent,10),U32.sub(c,48)),
    U32.is_le(U32.add(U32.mul(exponent,10),U32.sub(c,48)),100000),path,continuation)

def Laws.model_guard_uses_actual_recursive_continuation(rest,stage,reversed,fraction,next,exponent_negative,negative,allowed):
  Laws.model_guard_matches_original_result_continuation(next,allowed,
    value => M.int_scan(rest,stage,reversed,fraction,value,exponent_negative,negative))

def Laws.blockstate_guard_uses_actual_recursive_continuation(rest,stage,digits,fraction,next,eneg,negative,path,allowed):
  Laws.blockstate_guard_matches_original_result_continuation(next,allowed,path,
    value => S.scan_number(rest,stage,digits,fraction,value,eneg,negative,path))
'''


def pin(path):
    path = Path(path).resolve(strict=True)
    return {'path': str(path), 'bytes': path.stat().st_size,
            'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}


def tree(directory):
    return {str(path.relative_to(directory)): pin(path)['sha256']
            for path in sorted(directory.rglob('*')) if path.is_file()}


def write(path, value):
    with path.open('x') as handle:
        json.dump(value, handle, sort_keys=True, indent=2)
        handle.write('\n')


def prepare(directory):
    directory = directory.resolve()
    assert not directory.exists(), 'Use a fresh private candidate directory'
    for name, expected in INPUT_SHA256.items():
        assert pin(ORIGINAL/name)['sha256'] == expected, 'Frozen input drift: ' + name
    before = {name: tree(ORIGINAL/name) for name in ('source', 'source-api')}
    directory.mkdir(parents=True)
    (directory/'baseline').mkdir()
    for name in ('source', 'source-api'):
        shutil.copytree(ORIGINAL/name, directory/'baseline'/name)
        shutil.copytree(directory/'baseline'/name, directory/name)
        assert tree(directory/name) == before[name]
    changes = []
    diffs = []
    for name, old, new, guard, anchor in (
            ('block_model.bend', MODEL_OLD, MODEL_NEW, MODEL_GUARD, 'def int_scan('),
            ('blockstate_model.bend', STATE_OLD, STATE_NEW, STATE_GUARD, 'def scan_number(')):
        path = directory/'source/src'/name
        original = path.read_text()
        assert original.count(old) == original.count(anchor) == 1, 'Exact branch/anchor mismatch: ' + name
        candidate = original.replace(old, new).replace(anchor, guard + anchor)
        assert candidate.replace(guard, '').replace(new, old) == original, 'Outside-scope change: ' + name
        # copy2 retains immutable input modes; only this owned candidate may change.
        path.chmod(path.stat().st_mode | 0o200)
        path.write_text(candidate)
        changes.append({'path': 'src/' + name, 'original': pin(directory/'baseline/source/src'/name),
                        'candidate': pin(path)})
        diffs.extend(difflib.unified_diff(original.splitlines(True), candidate.splitlines(True),
            fromfile='baseline/source/src/' + name, tofile='source/src/' + name))
    (directory/'candidate.diff').write_text(''.join(diffs))
    laws = directory/'source/src'/(PREFIX + '_laws.bend')
    proof = directory/'source/src'/(PREFIX + '_proof.bend')
    laws.write_text(LAWS); proof.write_text(PROOF)
    harnesses = []
    # Reuse the actual unchanged native consumer serializers and request APIs.
    # Corpus preparation belongs to the separate original-corpus owner.
    for name in ('block_model.bend', 'blockstate_model.bend'):
        original = ROOT/'tests'/name
        for base in (directory/'baseline/source', directory/'source'):
            (base/'tests').mkdir(exist_ok=True)
            shutil.copy2(original, base/'tests'/name)
            assert pin(base/'tests'/name)['sha256'] == pin(original)['sha256']
        harnesses.append(pin(directory/'source/tests'/name))
    after = {name: tree(ORIGINAL/name) for name in ('source', 'source-api')}
    assert after == before, 'Immutable original changed during preparation'
    assert tree(directory/'source-api') == before['source-api'], 'Copied source API changed'
    changed = [name for name in before['source']
               if pin(directory/'source'/name)['sha256'] != before['source'][name]]
    assert changed == sorted(['src/block_model.bend', 'src/blockstate_model.bend'])
    write(directory/'baseline-inputs.json', before)
    write(directory/'candidate-inputs.json', {'source': tree(directory/'source'),
                                             'source-api': tree(directory/'source-api')})
    record = {'status': 'private_source_ready_verification_pending', 'tool': pin(__file__),
        'directory': str(directory), 'original_directory': str(ORIGINAL),
        'changes': changes, 'diff': pin(directory/'candidate.diff'),
        'baseline_inputs': pin(directory/'baseline-inputs.json'),
        'candidate_inputs': pin(directory/'candidate-inputs.json'),
        'laws': pin(laws), 'proof': pin(proof), 'law_count': LAWS.count('\nlaw '),
        'native_harnesses': harnesses, 'original_source_and_api_unchanged': True,
        'all_other_original_source_files_byte_identical': True,
        'copied_source_map_describes_baseline_not_candidate': True,
        'guard_scope': 'Arbitrary scalar next/Bool and affine continuation; exact original choice+Result.bind, wrapped update, and actual scanner continuation specialization. No whole-parser equivalence or performance claim.',
        'source_checker_run': False, 'kernel_run': False, 'compiler_or_export_run': False,
        'Java_or_native_run': False, 'product_processes_started': 0,
        'original_numeric_corpus': str(ROOT/'build/generic-resource-world-sample-numeric-original-corpus-001')}
    write(directory/'preparation.json', record)
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--directory', type=Path, default=WORK)
    args = parser.parse_args()
    record = prepare(args.directory)
    print(json.dumps({'status': record['status'], 'directory': record['directory'],
                      'production_files_changed': len(record['changes']), 'law_count': record['law_count'],
                      'product_processes_started': 0, 'diff': record['diff']}))


if __name__ == '__main__':
    main()
