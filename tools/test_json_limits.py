#!/usr/bin/env python3
"""Native Bend configurable JSON limits with an independent Python JSON oracle.

Files/typed ASTs are test inputs, never a host-backed implementation path.
Default outputs include exact historical rejection messages, checked by a digest
measured before introducing Limits. The existing 536-case oracle also runs.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import platform
import random
import subprocess
import sys
import time
import zipfile
from pathlib import Path

import test_json as oracle

ROOT = oracle.ROOT
BEND = oracle.BEND
WORK = ROOT / 'build/json-limits'
BIN = ROOT / 'build/json-limits-tests'
DEFAULT_BIN = ROOT / 'build/json-tests'
JAR = Path('/Users/chuah/Library/Application Support/minecraft/versions/26.3/26.3.jar')
JAR_SHA256 = '4508d006323f24fa02876310c192d739af56516eb259000ac50f0909a68c9a2d'
PRE_LIMITS_SOURCE_SHA256 = 'a546726a2422382e388e3b0c9c2868034f25f5b1339c8b6b1dc167190a1b4099'
DEFAULT_OUTPUT_SHA256 = 'c2243160169acc26080c84ce30f0b79ba470ece5c4edd37302a2fe27283ff7c9'
SERIALIZER_ACCESSORS_SHA256 = 'ec117bb02a661735a49e97abcdabb154b5cfe992c8beb8062e72bacd68cacf93'
MAX_CAP = 0xFFFFFFFF
NAT48_MAX = (1 << 48) - 1
MIB = 1 << 20
sys.setrecursionlimit(20000)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def run(args, timeout=120):
    p = subprocess.run([str(x) for x in args], cwd=ROOT, capture_output=True,
                       timeout=timeout)
    if p.returncode:
        raise AssertionError(f'{args}: exit {p.returncode}: {p.stderr[:2000]!r}, {p.stdout[:2000]!r}')
    return p.stdout


def verdict(source):
    begin = time.monotonic()
    try:
        p = subprocess.run([str(BEND), source, '--verdict'], cwd=ROOT,
                           capture_output=True, text=True, timeout=60)
        return {'exit_code': p.returncode, 'output': (p.stdout + p.stderr).strip(),
                'elapsed_seconds': round(time.monotonic() - begin, 3)}
    except subprocess.TimeoutExpired as e:
        return {'timeout_seconds': 60,
                'output': ((e.stdout or b'') + (e.stderr or b'')).decode(errors='replace'),
                'elapsed_seconds': round(time.monotonic() - begin, 3)}


def nested(depth, style):
    prefixes = [('[' if style == 'array' or (style == 'mixed' and i % 2 == 0)
                 else '{"k":') for i in range(depth)]
    suffixes = [']' if p == '[' else '}' for p in prefixes]
    return ''.join(prefixes) + 'null' + ''.join(reversed(suffixes)), prefixes


def tree_depth(value):
    if isinstance(value, list):
        return 1 + max((tree_depth(x) for x in value), default=0)
    if isinstance(value, oracle.Object):
        return 1 + max((tree_depth(x) for _, x in value.pairs), default=0)
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--skip-build', action='store_true')
    opts = ap.parse_args()
    start = time.monotonic()
    WORK.mkdir(parents=True, exist_ok=True)
    checks = {}
    for source in ['src/json.bend', 'tests/json.bend', 'tests/json_limits.bend']:
        out = run([BEND, source, '--check-only']).decode().strip()
        assert 'ALL PROOFS CHECK' in out, out
        checks[source] = out
    if not opts.skip_build:
        run([BEND, 'tests/json.bend', '-o', DEFAULT_BIN])
        run([BEND, 'tests/json_limits.bend', '-o', BIN])
    assert run([DEFAULT_BIN, '--threads', '1']).strip() == b'regressions\tpass'
    assert run([BIN, '--threads', '1']).strip() == b'limits-fixtures\tpass'

    default_cases = oracle.corpus()
    defaults = oracle.execute(DEFAULT_BIN, default_cases)
    default_bytes = json.dumps([(c.name, out) for c, out in defaults],
                              ensure_ascii=False, separators=(',', ':')).encode()
    assert sha(default_bytes) == DEFAULT_OUTPUT_SHA256, 'default output/error bytes changed'
    roundtrips = [oracle.Case('roundtrip-' + c.name, 'parse', out[3:], out)
                  for c, out in defaults if out.startswith('ok\t')]
    oracle.execute(DEFAULT_BIN, roundtrips)

    rows = []
    def check(name, text, cap=4*MIB, depth=512, error=None, expected=None):
        raw = text.encode('utf-8')
        if expected is None:
            expected = ('error\t' + error if error is not None else
                        'ok\t' + oracle.dump(oracle.reference(text)))
        wanted = expected.encode('utf-8') + b'\n'
        t = time.monotonic()
        if len(raw) > 60000 or '\0' in text:
            path = WORK / (name + '.json')
            path.write_bytes(raw)
            observed = run([BIN, '--threads', '1', cap, depth, 'file', path])
            transport = 'file'
        else:
            observed = run([BIN, '--threads', '1', cap, depth, 'text', text])
            transport = 'argument'
        if observed != wanted:
            raise AssertionError((name, len(observed), len(wanted), observed[:250], wanted[:250]))
        rows.append({'name': name, 'input_codepoints': len(text), 'input_bytes': len(raw),
                     'max_codepoints': cap, 'max_depth': depth, 'transport': transport,
                     'expected': 'rejected' if error is not None else 'accepted',
                     'input_sha256': sha(raw), 'native_output_sha256': sha(observed),
                     'elapsed_seconds': round(time.monotonic()-t, 4)})

    # Explicit default configuration is identical to the preserved parse wrapper.
    for i in range(0, len(defaults), 25):
        group = [(c, out) for c, out in defaults[i:i+25] if c.mode == 'parse']
        if group:
            observed = run([BIN, '--threads', '1', 16384, 64, 'batch',
                            *[c.text for c, _ in group]]).decode().removesuffix('\n').split('\n')
            assert observed == [out for _, out in group], ('explicit default', i)
    explicit_default_count = sum(c.mode == 'parse' for c, _ in defaults)

    # Limit precedence, zero caps, U32 depth endpoints, and Nat48 upper input.
    for cap in [MAX_CAP+1, NAT48_MAX]:
        for text in ['', 'null', '[', '"\\q"']:
            check(f'unsupported-{cap}-{sha(text.encode())[:8]}', text, cap, MAX_CAP,
                  error='JSON max_codepoints exceeds supported limit 4294967295')
    for cap in [0, 1, 3]:
        check(f'length-null-{cap}', 'null', cap, 64,
              error=f'JSON input exceeds {cap} code points')
    check('zero-input-empty', '', 0, 0, error='expected JSON value at offset 0')
    check('zero-depth-scalar', 'null', 4, 0)
    check('zero-depth-array', '[]', 2, 0, error='nesting limit exceeded at offset 0')
    check('max-supported-input-cap', 'null', MAX_CAP, MAX_CAP)
    check('max-supported-depth-cap', '[{}]', 4, MAX_CAP)

    for depth in [1, 64, 512]:
        for style in ['array', 'object', 'mixed']:
            text, prefixes = nested(depth, style)
            check(f'depth-{style}-{depth}-exact', text, len(text), depth)
            over, prefixes = nested(depth+1, style)
            check(f'depth-{style}-{depth}-over', over, len(over), depth,
                  error=f'nesting limit exceeded at offset {sum(map(len,prefixes[:depth]))}')
            check(f'depth-{style}-{depth}-one-less', text, len(text), depth-1,
                  error=f'nesting limit exceeded at offset {sum(map(len,prefixes[:depth-1]))}')
    check('default-depth-rejects-512', nested(512, 'array')[0], 16384, 64,
          error='nesting limit exceeded at offset 64')
    check('siblings-do-not-accumulate-depth', '[' + ','.join(['{}']*20000) + ']', depth=2)

    # Exact sizes include syntax and whitespace. These also exercise late errors.
    for cap in [16384, MIB, 4*MIB]:
        for delta in [-1, 0, 1]:
            text = ' '*(cap+delta-4) + 'null'
            check(f'codepoint-bound-{cap}-{delta+1}', text, cap, 64,
                  error=f'JSON input exceeds {cap} code points' if delta > 0 else None)
    check('two-mib-plus-whitespace', ' '*(2*MIB+19)+'false')
    body = 'a'*(MIB+17)
    check('large-late-trailing-junk', '"'+body+'"x',
          error=f'trailing input at offset {len(body)+2}')
    check('large-late-invalid-escape', '"'+body+'\\q"',
          error=f'invalid string escape at offset {len(body)+2}')
    duplicate = '{"pad":"'+body+'","key":1,"key":2}'
    check('large-duplicate-decoded-key', duplicate,
          error=f'duplicate object member at offset {duplicate.rindex(chr(34)+"key"+chr(34))+4}')
    check('large-number-leading-zero', ' '*MIB+'01',
          error=f'trailing input at offset {MIB+1}')
    check('size-rejection-precedes-invalid-grammar', '"\\q' + body + '"', 16384, 64,
          error='JSON input exceeds 16384 code points')
    check('large-unpaired-high-surrogate', '"'+body+'\\ud800"',
          error=f'high surrogate requires low surrogate escape at offset {len(body)+7}')

    # The native executable itself constructs these ASTs. Python independently
    # computes their exact serialization, then sends the serialized files through
    # parse_with and verifies exact bytes again. No generated assets are committed.
    generated = [('ast-ascii', 4*MIB-2), ('ast-string', MIB+17),
                 ('ast-escaped', MIB//2+3), ('ast-array', 110000),
                 ('ast-object', 12000), ('ast-depth', 512)]
    ast_rows = []
    for mode, n in generated:
        if mode == 'ast-ascii': expected = oracle.dump('a'*n)
        elif mode == 'ast-string': expected = oracle.dump('😀'*n)
        elif mode == 'ast-escaped': expected = oracle.dump('\n'*n)
        elif mode == 'ast-array': expected = '['+','.join(['-0.00E+400']*n)+']'
        elif mode == 'ast-object':
            expected = oracle.dump(oracle.Object(tuple((f'key-{i}',oracle.Number('9007199254740993'))
                                                       for i in reversed(range(n)))))
        else: expected = '['*n+'null'+']'*n
        observed = run([BIN, '--threads', '1', 'generate', mode, n])
        assert observed == expected.encode()+b'\n', (mode, 'native generated AST serializer')
        ast_rows.append({'mode':mode,'count':n,'output_codepoints':len(expected),
                         'output_bytes':len(observed)-1,'native_output_sha256':sha(observed)})
        check('generated-'+mode, observed[:-1].decode(), expected='ok\t'+expected)
        if mode in ['ast-ascii','ast-string','ast-escaped','ast-array']:
            check('generated-'+mode+'-size-reject', expected, len(expected)-1, 512,
                  error=f'JSON input exceeds {len(expected)-1} code points')

    # Generated independent trees with independently calculated depth and strict
    # malformed-number/escape checks at larger caps.
    rng = random.Random(0x1A17)
    def tree(d):
        if not d or rng.randrange(4) == 0:
            return rng.choice([None,False,oracle.Number('-0.00E+400'),'é😀\n'])
        if rng.randrange(2): return [tree(d-1) for _ in range(rng.randrange(4))]
        return oracle.Object(tuple((f'k{i}',tree(d-1)) for i in range(rng.randrange(4))))
    for i in range(40):
        value = tree(7)
        text = oracle.dump(value)
        check(f'random-{i}', text, len(text), tree_depth(value))
    invalid = [('00','trailing input at offset 1'),
               ('1e+','incomplete number at offset 3'),
               ('[1,]','trailing array comma at offset 3'),
               ('{"a":0,"\\u0061":1}','duplicate object member at offset 14'),
               ('"\\uDC00"','unpaired low surrogate at offset 6'),
               ('"\\uD800\\u0041"','invalid low surrogate at offset 12')]
    for i, (text,error) in enumerate(invalid):
        try: oracle.reference(text)
        except ValueError: pass
        else: raise AssertionError(('invalid oracle accepted',text))
        check(f'large-cap-invalid-{i}',text,error=error)

    assert JAR.is_file(), f'installed pinned 26.3.jar missing: {JAR}'
    jar_bytes = JAR.read_bytes()
    assert sha(jar_bytes) == JAR_SHA256, 'installed jar pin changed'
    official = []
    with zipfile.ZipFile(JAR) as z:
        for category,prefix in [('blockstates','assets/minecraft/blockstates/'),
                                ('models','assets/minecraft/models/'),
                                ('resources','assets/'),('data','data/')]:
            candidates = sorted((i for i in z.infolist()
                                 if i.filename.startswith(prefix) and i.filename.endswith('.json')),
                                key=lambda i:(-i.file_size,i.filename))
            for rank, entry in enumerate(candidates[:3]):
                raw = z.read(entry)
                text = raw.decode('utf-8',errors='strict')
                value = oracle.reference(text)
                assert len(text) <= 4*MIB and tree_depth(value) <= 512
                check(f'official-{category}-{rank}',text)
                official.append({'category':category,'rank':rank+1,'entry':entry.filename,
                                 'bytes':len(raw),'codepoints':len(text),'depth':tree_depth(value),
                                 'sha256':sha(raw),'crc32':f'{entry.CRC:08x}'})

    source = (ROOT/'src/json.bend').read_bytes()
    assert b'@unsafe' not in source and b'import Base\n' in source
    assert b'import "' not in source and b'IO(' not in source and b'IO.' not in source
    unchanged = source[source.index(b'# Serialization is structural'):]
    assert sha(unchanged) == SERIALIZER_ACCESSORS_SHA256, 'serializer/accessor source changed'
    kernels = {s:verdict(s) for s in ['src/json.bend','tests/json_limits.bend']}
    kernel_bin = Path('/Users/chuah/.bend/bendtt/e15042434e73aab0/bendtt')
    direct_kernel = {'available':kernel_bin.is_file()}
    if kernel_bin.is_file():
        emitted = WORK/'json-limits-module.bendtt'
        run([BEND,'src/json.bend','-o',emitted])
        p = subprocess.run([str(kernel_bin),str(emitted)],cwd=ROOT,capture_output=True,
                           text=True,timeout=60)
        direct_kernel.update({'binary':str(kernel_bin),'binary_sha256':sha(kernel_bin.read_bytes()),
                              'input':str(emitted.relative_to(ROOT)),
                              'input_sha256':sha(emitted.read_bytes()),'exit_code':p.returncode,
                              'output':(p.stdout+p.stderr).strip()})
    report = {
        'schema':1,'compiler':run([BEND,'version']).decode().strip(),'platform':platform.platform(),
        'source_sha256':sha(source),'tests_sha256':sha((ROOT/'tests/json_limits.bend').read_bytes()),
        'runner_sha256':sha(Path(__file__).read_bytes()),'native_binary_sha256':sha(BIN.read_bytes()),
        'checker':checks,'kernel_verdict':kernels,'direct_kernel':direct_kernel,
        'default_compatibility':{'cases':len(defaults),'successful_roundtrips':len(roundtrips),
                               'pre_limits_source_sha256':PRE_LIMITS_SOURCE_SHA256,
                               'all_outputs_and_errors_sha256':sha(default_bytes),
                               'matches_pre_limits_digest':True,
                               'serializer_accessor_suffix_sha256':sha(unchanged),
                               'serializer_accessor_suffix_unchanged':True,
                               'explicit_default_equivalent_cases':explicit_default_count},
        'supported_caps':{'max_codepoints_min':0,'max_codepoints_max':MAX_CAP,
                          'max_depth_min':0,'max_depth_max':MAX_CAP,
                          'maximum_transition_fuel':4*MAX_CAP+16,'native_nat_max':NAT48_MAX,
                          'reason':'U32 offsets, with transition fuel strictly below Nat48; invalid caps rejected before counting/fuel'},
        'tested_envelope':{'max_accepted_input_codepoints':max(r['input_codepoints'] for r in rows if r['expected']=='accepted'),
                           'max_accepted_input_bytes':max(r['input_bytes'] for r in rows if r['expected']=='accepted'),
                           'max_successful_container_depth':512},
        'configured_cases':len(rows),'all_cases_passed':True,'native_generated_asts':ast_rows,
        'official_jar':{'path':str(JAR),'bytes':len(jar_bytes),'sha256':JAR_SHA256,'entries':official},
        'oracle':'Python json with exact number lexemes, duplicate rejection, scalar validation, independent recursive depth; exact UTF-8 output comparison',
        'file_harness':'Base File.size/read only on independently verified UTF-8 fixtures, bounded at 32 MiB; src/json remains pure String parser',
        'proof_scope':'Four finite small parser examples pass ordinary checker. Independent kernel remains rejected by unchanged encode_go; no general correctness or kernel-validation claim.',
        'cases':rows,'elapsed_seconds':round(time.monotonic()-start,3),
        'commands':['python3 tools/test_json.py','python3 tools/test_json_limits.py',
                    '/Users/chuah/.bend/bin/bend tests/json_limits.bend --check-only',
                    '/Users/chuah/.bend/bin/bend src/json.bend --verdict',
                    '/Users/chuah/.bend/bin/bend tests/json_limits.bend --verdict',
                    '/Users/chuah/.bend/bin/bend src/json.bend -o build/json-limits/json-limits-module.bendtt',
                    '/Users/chuah/.bend/bendtt/e15042434e73aab0/bendtt build/json-limits/json-limits-module.bendtt']}
    (ROOT/'evidence/json-limits.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({k:report[k] for k in ['configured_cases','tested_envelope','all_cases_passed','elapsed_seconds']},indent=2))


if __name__ == '__main__':
    main()
