#!/usr/bin/env python3
"""Independent custom motion/look NBT record oracle and native failure recovery.

Python constructs fixtures and compares bytes; production decoding, validation,
projection and encoding execute only in the immutable compiled Bend harness.
"""
from __future__ import annotations
import argparse
import collections
import copy
import dataclasses
import hashlib
import itertools
import json
import os
from pathlib import Path
import platform
import random
import signal
import struct
import subprocess
import sys
import time

import test_nbt as N
import build_native as B
import test_player_codec as P
import test_player_look as L

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / 'build/player-record'
RECEIPT = BUILD / 'native-build.json'
BINARY = BUILD / 'tests'
BEND = Path('/Users/chuah/.bend/bin/bend')
ENTRY = ROOT / 'tests/player_record.bend'
SOURCE = ROOT / 'src/player_record.bend'
NAME = N.text('bendex:player-record')
DEGREE_FACTOR = 1016003125
LIMITS = {'bytes': 8192, 'container_depth': 2, 'elements_per_container': 4096}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + '\n')


@dataclasses.dataclass(frozen=True)
class Case:
    name: str
    mode: str
    data: bytes
    look: bytes
    output: bytes | None
    output_look: bytes | None
    error: str | None
    category: str


def projection(bits):
    return L.round32(L.exact(bits, 32) * L.exact(DEGREE_FACTOR, 32), bool(bits >> 31))


def look_bytes(words):
    return struct.pack('<4I', *words)


def look_words(data):
    return struct.unpack('<4I', data)


def root(motion, look):
    return N.RootTag(NAME, P.compound([
        ('format', N.Value(3, 1)), ('motion', N.Value(7, motion)),
        ('look', P.listing(5, look)),
    ]))


def physical_motion(words, dimension):
    return N.encode_root(P.snapshot_root(words, dimension))


def validate_motion(motion):
    words, dimension = P.parse_snapshot(motion)
    return physical_motion(words, dimension), words


class Invalid(ValueError):
    pass


def reject(name):
    raise Invalid(name)


def ascii_name(units):
    if len(units) > 64 or any(c > 127 for c in units):
        reject('PlayerError')
    return ''.join(chr(c) for c in units)


def validate_pair(motion, look):
    try:
        canonical, words = validate_motion(motion)
    except (ValueError, UnicodeError, struct.error):
        reject('PlayerError')
    if any(not L.finite32(v) for v in look):
        reject('LookError')
    for axis in (0, 1):
        if words[39 + axis] != projection(look[axis]):
            reject('ViewMismatch' + str(axis))
    return canonical


def decode(data):
    try:
        value = N.Reader(data, max_bytes=8192, max_depth=2, max_elements=4096).root()
    except (ValueError, UnicodeError, struct.error):
        reject('NbtError')
    if ascii_name(value.name) != 'bendex:player-record':
        reject('SchemaError')
    if value.value.kind != 10:
        reject('PlayerError')
    fs = {}
    for name, child in value.value.payload:
        name = ascii_name(name)
        if name not in ('format', 'motion', 'look') or name in fs:
            reject('PlayerError')
        fs[name] = child
    if set(fs) != {'format', 'motion', 'look'} or fs['format'] != N.Value(3, 1):
        reject('PlayerError')
    if fs['motion'].kind != 7:
        reject('SchemaError')
    # Production validates the inner motion before the look container shape.
    try:
        canonical, _ = validate_motion(fs['motion'].payload)
    except (ValueError, UnicodeError, struct.error):
        reject('PlayerError')
    look = fs['look']
    if look.kind != 9 or look.payload[0] != 5 or len(look.payload[1]) != 4:
        reject('SchemaError')
    if any(v.kind != 5 for v in look.payload[1]):
        reject('SchemaError')
    angles = tuple(v.payload for v in look.payload[1])
    assert canonical == validate_pair(fs['motion'].payload, angles)
    return canonical, look_bytes(angles)


def encode(motion, raw_look):
    angles = look_words(raw_look)
    canonical = validate_pair(motion, angles)
    result = N.encode_root(root(canonical, angles))
    if len(result) > 8192:
        reject('NbtError')
    return result


def corpus():
    pc_cases, _, _ = P.corpus()
    selfchecks = P.oracle_selftest(pc_cases)
    rng, cases = random.Random(0x26_03_726563), []

    def finite():
        while True:
            value = rng.getrandbits(32)
            if L.finite32(value):
                return value

    def add(name, mode, data, look=(0, 0, 0, 0), category='constructed', valid=None, error=None):
        raw_look = look_bytes(look)
        try:
            if mode == 'encode':
                output, output_look = encode(data, raw_look), None
            else:
                output, output_look = decode(data)
            observed_error = None
        except Invalid as e:
            output, output_look, observed_error = None, None, str(e)
        if valid is not None:
            assert (output is not None) == valid, (name, observed_error)
        if error is not None:
            assert observed_error == error, (name, observed_error, error)
        cases.append(Case(name, mode, data, raw_look, output, output_look, observed_error, category))

    def pair(name, words, dimension, look, category):
        words = list(words)
        words[39:41] = tuple(projection(v) for v in look[:2])
        motion = physical_motion(tuple(words), dimension)
        add(name + '-encode', 'encode', motion, look, category, True)
        add(name + '-decode', 'decode', N.encode_root(root(motion, look)), category=category, valid=True)
        return motion

    base_words = P.snapshot(support=(0x80000000, 0x7fffffff, 0xffffffff), support_flag=1)
    base_motion = pair('baseline', base_words, P.DIMENSIONS[0], (0, 0, 0, 0), 'baseline')
    baseline = N.encode_root(root(base_motion, (0, 0, 0, 0)))
    base_root = root(base_motion, (0, 0, 0, 0))
    yaw_edges = (0, 0x80000000, 1, 2, 3, 0x80000001, 0x80000002, 0x007fffff,
                 0x00800000, P.raw32(180), P.raw32(-180), P.raw32(360), P.raw32(-360),
                 P.raw32(365), P.raw32(-365), P.raw32(720), P.raw32(-720), 0x7f7fffff, 0xff7fffff)
    pitch_edges = (0, 0x80000000, 1, 0x80000001, P.raw32(90)-1, P.raw32(90),
                   P.raw32(90)|0x80000000, (P.raw32(90)-1)|0x80000000)
    for i, pc in enumerate(c for c in pc_cases if c.mode == 'encode' and c.expected is not None):
        look = (yaw_edges[i % len(yaw_edges)] if i < 76 else finite(),
                pitch_edges[i % len(pitch_edges)], finite(), finite())
        pair('motion-' + pc.name, P.from_word_bytes(pc.data), pc.dimension, look, 'motion/' + pc.category)
    for yaw, pitch in itertools.product(yaw_edges, pitch_edges):
        pair(f'degrees-{yaw:08x}-{pitch:08x}', base_words, P.DIMENSIONS[0],
             (yaw, pitch, 0xff7fffff, 0x7f7fffff), 'raw-degree-edges-and-unwrapped-past')

    # Both levels admit reordered members and liberal physical modified UTF-8.
    for i, order in enumerate(itertools.permutations(base_root.value.payload)):
        add('outer-order-' + str(i), 'decode', N.encode_root(N.RootTag(NAME, N.Value(10, order))),
            category='noncanonical-input-canonical-output', valid=True)
    for pc in pc_cases:
        if pc.mode != 'decode' or pc.category not in ('reordered-fields', 'physical-mutf-read-policy'):
            continue
        try:
            _, words = validate_motion(pc.data)
        except ValueError:
            continue
        # These cases use baseline view fields; substitute exact degree projections.
        physical = N.Reader(pc.data).root()
        value = P.replace_field(P.replace_field(physical.value, 'view_yaw', N.Value(5, 0)), 'view_pitch', N.Value(5, 0))
        motion = N.encode_root(N.RootTag(physical.name, value))
        add('inner-' + pc.name, 'decode', N.encode_root(root(motion, (0, 0, 0, 0))),
            category='noncanonical-inner-canonical-output', valid=True)
    overlong_name = bytes((0xc0 | (NAME[0] >> 6), 0x80 | (NAME[0] & 63))) + N.mutf_encode(NAME[1:])[2:]
    overlong_root = b'\x0a' + struct.pack('>H', len(overlong_name)) + overlong_name + N.encode_value(base_root.value)
    add('outer-overlong-ascii-root', 'decode', overlong_root, category='physical-mutf-admission', valid=True)

    for pc in pc_cases:
        if pc.mode != 'decode' or len(pc.data) > 4096:
            continue
        try:
            P.parse_snapshot(pc.data)
        except (ValueError, UnicodeError, struct.error):
            add('inner-reject-' + pc.name, 'decode', N.encode_root(root(pc.data, (0, 0, 0, 0))),
                category='inner/' + pc.category, valid=False, error='PlayerError')
            add('encode-reject-' + pc.name, 'encode', pc.data,
                category='encode-inner/' + pc.category, valid=False, error='PlayerError')

    nonfinite = (0x7f800000, 0xff800000, 0x7fc00000, 0xffc00000, 0x7f800001, 0xff800001, 0x7fffffff, 0xffffffff)
    for field, bits in itertools.product(range(4), nonfinite):
        look = [0] * 4
        look[field] = bits
        add(f'nonfinite-{field}-{bits:08x}-encode', 'encode', base_motion, look, 'look-nonfinite', False, 'LookError')
        add(f'nonfinite-{field}-{bits:08x}-decode', 'decode', N.encode_root(root(base_motion, look)),
            category='look-nonfinite', valid=False, error='LookError')
    for axis in (0, 1):
        for actual in (0x80000000, 1, 0x80000001, P.raw32(0.1)):
            words = list(base_words)
            words[39:41] = (0, 0)
            words[39 + axis] = actual
            motion = physical_motion(tuple(words), P.DIMENSIONS[0])
            add(f'projection-{axis}-{actual:08x}-encode', 'encode', motion, category='raw-projection-mismatch', valid=False, error='ViewMismatch' + str(axis))
            add(f'projection-{axis}-{actual:08x}-decode', 'decode', N.encode_root(root(motion, (0, 0, 0, 0))),
                category='raw-projection-mismatch', valid=False, error='ViewMismatch' + str(axis))
    words = list(base_words)
    words[39:41] = (0x80000000, 0x80000000)
    add('projection-both-axis-priority', 'decode', N.encode_root(root(physical_motion(tuple(words), P.DIMENSIONS[0]), (0, 0, 0, 0))),
        category='validation-order', valid=False, error='ViewMismatch0')
    for pitch in (P.raw32(90) + 1, P.raw32(-90) + 1, P.raw32(365), 0x7f7fffff):
        words = list(base_words)
        words[40] = projection(pitch)
        add(f'current-pitch-invalid-{pitch:08x}', 'decode', N.encode_root(root(physical_motion(tuple(words), P.DIMENSIONS[0]), (0, pitch, 0, 0))),
            category='projected-current-pitch-bound', valid=False, error='PlayerError')
    for cut in range(len(baseline)):
        add('truncate-' + str(cut), 'decode', baseline[:cut], category='outer-truncation', valid=False, error='NbtError')
    for suffix in (b'\x00', b'\x01', b'garbage', baseline):
        add('trailing-' + sha(suffix)[:8], 'decode', baseline + suffix, category='outer-trailing-data', valid=False, error='NbtError')

    def modified(name, field, value, category='outer-schema', error=None):
        value = P.replace_field(base_root.value, field, value)
        add(name, 'decode', N.encode_root(N.RootTag(NAME, value)), category=category, valid=False, error=error)

    for field in ('format', 'motion', 'look'):
        for kind in range(1, 13):
            if kind == {'format':3, 'motion':7, 'look':9}[field]:
                continue
            value = (N.Value(kind, 0) if kind <= 6 else N.Value(kind, b'') if kind == 7 else
                     P.txt('') if kind == 8 else P.listing(5, ()) if kind == 9 else
                     P.compound(()) if kind == 10 else N.Value(kind, ()))
            modified(f'wrong-tag-{field}-{kind}', field, value)
        members = base_root.value.payload
        for shape in (tuple(m for m in members if m[0] != N.text(field)), members + tuple(m for m in members if m[0] == N.text(field))):
            add(f'field-set-{field}-{len(shape)}', 'decode', N.encode_root(N.RootTag(NAME, N.Value(10, shape))), category='outer-exact-field-set', valid=False, error='PlayerError')
    for bits in (0, 2, 0x7fffffff, 0x80000000, 0xffffffff):
        modified('format-' + str(bits), 'format', N.Value(3, bits), error='PlayerError')
    for name in ('', 'bendex:player', 'Bendex:player-record', 'x'*65, '\u0080', '\ud800'):
        add('root-name-' + repr(name), 'decode', N.encode_root(N.RootTag(N.text(name), base_root.value)), category='outer-root-name', valid=False)
    for value in (N.Value(0), N.Value(3, 1), P.listing(5, ()), P.txt('wrong')):
        add('root-type-' + str(value.kind), 'decode', N.encode_root(N.RootTag(NAME, value)), category='outer-root-type', valid=False)
    for size in (0, 1, 2, 3, 5, 16, 1024):
        modified('look-size-' + str(size), 'look', P.listing(5, (0,) * size), 'outer-look-list-shape')
    modified('look-byte-list-elements-at-limit', 'look', P.listing(1, (0,) * 4096), 'outer-element-bound', 'SchemaError')
    for kind in (0, 1, 2, 3, 4, 6, 7, 8, 9, 10, 11, 12):
        modified('look-empty-kind-' + str(kind), 'look', N.Value(9, (kind, ())), 'outer-look-list-shape', 'SchemaError')
    nested = P.compound([('inside', P.compound(()))])
    modified('container-depth-overflow', 'look', nested, 'outer-depth-bound', 'NbtError')
    prefix = b'\x0a' + N.mutf_encode(NAME)
    for field, kind, trailer in (('motion', 7, b''), ('look', 9, b'\x05')):
        for count in (0xffffffff, 0x80000000, 0x7fffffff, 4097):
            bomb = prefix + bytes((kind,)) + N.mutf_encode(N.text(field)) + trailer + struct.pack('>I', count) + b'\x00'
            add(f'count-bomb-{field}-{count}', 'decode', bomb, category='outer-preallocation-count-bomb', valid=False, error='NbtError')
    for count in (4096, 4097):
        modified('motion-bytearray-bound-' + str(count), 'motion', N.Value(7, b'\x00' * count), 'outer-element-bound', 'PlayerError' if count == 4096 else 'NbtError')
    # An 8192-byte structurally valid root passes the byte ceiling then fails schema.
    padding = P.compound([('padding', P.txt(''))])
    fixed = len(N.encode_root(N.RootTag(NAME, padding)))
    for size in (8191, 8192, 8193):
        value = P.compound([('padding', P.txt('x' * (size-fixed)))])
        data = N.encode_root(N.RootTag(NAME, value))
        assert len(data) == size
        add('outer-byte-cap-' + str(size), 'decode', data, category='outer-byte-bound', valid=False, error='NbtError' if size > 8192 else 'PlayerError')
    for name in ('unknown', '\u0080', 'x'*65):
        value = N.Value(10, base_root.value.payload + ((N.text(name), N.Value(1, 0)),))
        add('extra-field-' + repr(name), 'decode', N.encode_root(N.RootTag(NAME, value)), category='outer-exact-field-set', valid=False, error='PlayerError')
    for i in range(400):
        data = bytearray(baseline)
        data[rng.randrange(len(data))] ^= 1 << rng.randrange(8)
        add('seeded-mutation-' + str(i), 'decode', bytes(data), category='independently-classified-mutations')

    names = [c.name for c in cases]
    assert len(names) == len(set(names))
    assert all(len(c.data) <= 8193 for c in cases), 'harness fixture read ceiling'
    projections = 0
    for bits in (*yaw_edges, *pitch_edges, *(finite() for _ in range(10000))):
        # Binary64 holds the exact product of two binary32 significands (<=48 bits).
        hardware = P.raw32(P.f32(bits) * P.f32(DEGREE_FACTOR))
        assert projection(bits) == hardware, ('projection oracle disagreement', bits)
        projections += 1
    selfchecks['rational_F32_degree_projection_vs_exact_F64_product'] = projections
    selfchecks['factor_f32_bits'] = f'{DEGREE_FACTOR:08x}'
    return cases, baseline, base_motion, selfchecks


def dependency_audit():
    sources = P.imports([SOURCE, ENTRY])
    audits = {}
    for relative, evidence in (('src/player_codec.bend', 'player-codec-native.json'), ('src/player_look.bend', 'player-look-native.json')):
        closure = P.imports([ROOT / relative])
        expected = json.loads((ROOT / 'evidence' / evidence).read_text())['sources_sha256']
        differences = {p: {'expected': expected.get(p), 'actual': digest} for p, digest in closure.items() if expected.get(p) != digest}
        assert not differences, ('verified dependency closure changed', differences)
        audits[evidence] = {'evidence_sha256': sha((ROOT / 'evidence' / evidence).read_bytes()), 'unchanged_sources_sha256': closure}
    for name in sources:
        if name.startswith('src/'):
            import re
            assert not re.search(r'@unsafe|^import\s+["\']|\w!\(', (ROOT / name).read_text(), re.M), ('unexpected foreign/unsafe source', name)
    return sources, audits


def manifests(cases):
    return [{'name': c.name, 'mode': c.mode, 'category': c.category, 'input_bytes': len(c.data),
             'input_sha256': sha(c.data), 'look_sha256': sha(c.look),
             'output_sha256': None if c.output is None else sha(c.output),
             'output_look_sha256': None if c.output_look is None else sha(c.output_look), 'error': c.error} for c in cases]


def counts(cases):
    return {'cases': len(cases), 'accepted': sum(c.error is None for c in cases), 'rejected': sum(c.error is not None for c in cases),
            'exact_record_encodes': sum(c.mode == 'encode' and c.error is None for c in cases),
            'exact_motion_and_look_decodes': sum(c.mode == 'decode' and c.error is None for c in cases),
            'categories': dict(collections.Counter(c.category for c in cases)),
            'errors': dict(collections.Counter(c.error for c in cases if c.error is not None))}


def bounded_run(command, *, timeout=60, allow_timeout=False):
    started = time.monotonic()
    process = subprocess.Popen([str(s) for s in command], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
    timed_out = False
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        stdout, stderr = process.communicate()
        timed_out = True
        if not allow_timeout:
            raise AssertionError(('process timeout', process.pid, timeout, stdout[-1000:], stderr[-1000:]))
    return {'command': [str(s) for s in command], 'pid': process.pid, 'exit_code': process.returncode,
            'stdout': stdout.decode(), 'stderr': stderr.decode(), 'timed_out': timed_out, 'seconds': round(time.monotonic()-started, 6)}


def native_batches(cases, binary, lane, batch_size=64):
    reports, digest = [], hashlib.sha256()
    directory = BUILD / lane
    directory.mkdir(parents=True, exist_ok=True)
    for offset in range(0, len(cases), batch_size):
        batch, args, paths = cases[offset:offset+batch_size], [], []
        for i, c in enumerate(batch, offset):
            ip, lp, op = [directory / f'{i:05d}-{s}.bin' for s in ('input', 'look', 'output')]
            ip.write_bytes(c.data)
            lp.unlink(missing_ok=True)
            op.unlink(missing_ok=True)
            if c.mode == 'encode':
                lp.write_bytes(c.look)
            args.extend((c.mode, str(ip), str(lp), str(op)))
            paths.append((lp, op))
        result = bounded_run([binary, '--gpu', 'off', '--threads', '1', '--', *args])
        assert result['exit_code'] == 0, (lane, offset, result)
        lines = result['stdout'].splitlines()
        assert len(lines) == len(batch), ('response count', lane, offset, lines[-5:])
        for c, (lp, op), line in zip(batch, paths, lines, strict=True):
            assert line == ('error=' + c.error if c.error else 'ok=' + c.mode), (c.name, line, c.error)
            if c.error:
                assert not op.exists() and (c.mode == 'encode' or not lp.exists()), ('rejection wrote output', c.name)
            else:
                assert op.read_bytes() == c.output, ('native canonical bytes differ', c.name)
                if c.output_look is not None:
                    assert lp.read_bytes() == c.output_look, ('native raw look words differ', c.name)
                digest.update(op.read_bytes())
                if c.output_look is not None:
                    digest.update(lp.read_bytes())
            digest.update((c.name + '\0' + line + '\n').encode())
        reports.append({'offset': offset, 'cases': len(batch), 'exit_code': result['exit_code'],
                        'seconds': result['seconds'], 'stderr': result['stderr'], 'stdout_sha256': sha(result['stdout'].encode())})
    return {'batches': reports, 'response_and_output_sha256': digest.hexdigest()}


def check_receipt(sources, receipt):
    assert receipt['sources_sha256'] == sources, 'native sources do not match receipt'
    built = receipt['build']
    cache = ROOT / 'build/native-cache'
    record = B._verified(cache / 'entries' / built['cache_key'], built['cache_key'])
    assert record is not None, 'native cache generation failed content verification'
    assert built['dependencies'] == record['key_data']['dependencies'], 'receipt dependency closure differs from keyed generation'
    for name in ('binary_sha256', 'binary_bytes', 'emitted_c_sha256', 'compiler'):
        assert built[name] == record[name], 'receipt generation metadata differs: ' + name
    artifact = cache / 'artifacts' / record['binary_sha256'] / 'program'
    assert Path(built['artifact']) == artifact, 'receipt artifact path differs from immutable generation'
    emitted = cache / 'sources' / record['key_data']['prekey'] / 'generated.c'
    assert sha(emitted.read_bytes()) == record['emitted_c_sha256'], 'emitted C no longer matches native generation'
    return L.verify_build(built)


def verify_receipt(sources):
    receipt = json.loads(RECEIPT.read_text())
    return receipt, check_receipt(sources, receipt)


def receipt_selftests(sources, receipt):
    changes = []
    def test(name, edit):
        corrupted = copy.deepcopy(receipt)
        edit(corrupted)
        try:
            check_receipt(sources, corrupted)
        except (AssertionError, KeyError, ValueError, OSError):
            changes.append(name)
        else:
            raise AssertionError('corrupted native receipt accepted: ' + name)
    test('source-digest', lambda r: r['sources_sha256'].__setitem__('src/player_record.bend', '0'*64))
    test('missing-source', lambda r: r['sources_sha256'].pop('src/player_record.bend'))
    test('unexpected-source', lambda r: r['sources_sha256'].__setitem__('unexpected.bend', '0'*64))
    test('cache-key', lambda r: r['build'].__setitem__('cache_key', '0'*64))
    test('binary-digest', lambda r: r['build'].__setitem__('binary_sha256', '0'*64))
    test('binary-size', lambda r: r['build'].__setitem__('binary_bytes', 0))
    test('emitted-C-digest', lambda r: r['build'].__setitem__('emitted_c_sha256', '0'*64))
    test('compiler', lambda r: r['build'].__setitem__('compiler', {}))
    test('missing-dependency', lambda r: r['build']['dependencies'].pop())
    test('dependency-digest', lambda r: r['build']['dependencies'][0].__setitem__('sha256', '0'*64))
    test('dependency-lookup', lambda r: r['build']['dependencies'][0].__setitem__('lookup', '/missing/player-record-dependency'))
    test('artifact-alias', lambda r: r['build'].__setitem__('artifact', str(BINARY)))
    check_receipt(sources, receipt)
    return {'status':'passed', 'rejected_corruptions':changes, 'count':len(changes),
            'method':'Deep-copy receipt mutations only; no shared dependency/cache/source/artifact files are modified'}


def build(sources):
    BUILD.mkdir(parents=True, exist_ok=True)
    raw_report = BUILD / 'build-native-report.json'
    command = [sys.executable, ROOT / 'tools/build_native.py', ENTRY, '-o', BINARY, '--bend', BEND, '--report', raw_report]
    process = subprocess.Popen([str(s) for s in command], cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
    print(json.dumps({'status':'native-build-started', 'pid':process.pid, 'sources_sha256':sources}), flush=True)
    started = time.monotonic()
    try:
        stdout, stderr = process.communicate(timeout=600)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGKILL)
        stdout, stderr = process.communicate()
        write_json(BUILD / 'build-failure.json', {'status':'timeout', 'pid':process.pid, 'seconds':time.monotonic()-started,
                   'stdout':stdout.decode()[-4000:], 'stderr':stderr.decode()[-4000:], 'sources_sha256':sources})
        raise AssertionError('native build exceeded 600 seconds')
    assert process.returncode == 0, ('native build failed', process.returncode, stdout.decode()[-4000:], stderr.decode()[-4000:])
    assert sources == P.imports([SOURCE, ENTRY]), 'sources changed during native build'
    report = json.loads(raw_report.read_text())
    write_json(RECEIPT, {'sources_sha256': sources, 'build': report, 'runner_pid':process.pid,
                        'stdout':stdout.decode(), 'stderr':stderr.decode(), 'seconds':time.monotonic()-started})
    return verify_receipt(sources)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--preflight', action='store_true', help='independent fixtures and dependency audit only; no Bend process')
    parser.add_argument('--build-only', action='store_true', help='one bounded native build; requires lead heavy-job slot')
    parser.add_argument('--skip-build', action='store_true', help='require and verify immutable native receipt')
    parser.add_argument('--kernel', action='store_true', help='optional full-source independent kernel attempt, bounded to 60s')
    args = parser.parse_args()
    cases, baseline, base_motion, selfchecks = corpus()
    sources, audit = dependency_audit()
    records = manifests(cases)
    fixture_sha = sha(json.dumps(records, sort_keys=True, separators=(',', ':')).encode())
    oracles = {str(p.relative_to(ROOT)):sha(p.read_bytes()) for p in (Path(N.__file__),Path(P.__file__),Path(L.__file__),Path(__file__))}
    preflight = {'status':'oracle-corpus-valid-native-unverified', 'schema':1, 'format':'custom bendex:player-record formatInt1',
                 'counts':counts(cases), 'fixture_manifest_sha256':fixture_sha, 'canonical_fixture_bytes':len(baseline),
                 'canonical_fixture_sha256':sha(baseline), 'sources_sha256':sources, 'dependency_audit':audit,
                 'oracle_sources_sha256':oracles, 'oracle_selfchecks':selfchecks, 'limits':LIMITS}
    write_json(ROOT / 'evidence/player-record-preflight.json', preflight)
    BUILD.mkdir(parents=True, exist_ok=True)
    write_json(BUILD / 'fixtures.json', records)
    if args.preflight:
        print(json.dumps({k:preflight[k] for k in ('status','counts','fixture_manifest_sha256','canonical_fixture_bytes')}));return
    receipt, binary = verify_receipt(sources) if args.skip_build else build(sources)
    if args.build_only:
        print(json.dumps({'status':'built-and-receipt-verified', 'binary_sha256':receipt['build']['binary_sha256']}));return
    defensive = receipt_selftests(sources, receipt)
    checks = [bounded_run([BEND, path, '--check-only']) for path in (SOURCE,ENTRY)]
    assert all(r['exit_code'] == 0 for r in checks), checks
    started = time.monotonic()
    runs = [native_batches(cases, binary, 'run-' + str(i)) for i in range(2)]
    assert runs[0]['response_and_output_sha256'] == runs[1]['response_and_output_sha256'], 'two native runs differ'
    good = Case('recovery-good', 'decode', baseline, look_bytes((0,0,0,0)), base_motion, look_bytes((0,0,0,0)), None, 'same-process-recovery')
    followups = [c for bad in cases if bad.error for c in (bad,dataclasses.replace(good,name='after-' + bad.name))]
    assert len(followups) % 2 == 0
    recovery = native_batches(followups, binary, 'recovery', batch_size=64)
    kernel = []
    if args.kernel:
        kernel = [bounded_run([BEND,SOURCE,'--verdict'], timeout=60, allow_timeout=True)]
        write_json(ROOT / 'evidence/player-record-kernel.json', {'status':'timeout' if kernel[0]['timed_out'] else 'passed' if kernel[0]['exit_code']==0 and 'ALL PROOFS CHECK' in kernel[0]['stdout'] else 'failed',
                   'commands':kernel, 'sources_sha256':sources, 'scope':'Full imported production source and its two structural error-preservation laws; no atomic persistence or universal codec theorem'})
    assert sources == P.imports([SOURCE,ENTRY]), 'sources changed during verification'
    verify_receipt(sources)
    evidence = dict(preflight, status='passed', confidence='high for recorded finite fixtures', native_build=receipt,
                    ordinary_checks=checks, runs=runs, same_process_recovery=recovery, receipt_corruption_checks=defensive,
                    successful_failure_followups=len(followups)//2, kernel_this_run=kernel,
                    validation_seconds=round(time.monotonic()-started,6), platform={'system':platform.system(),'machine':platform.machine()},
                    oracle='Independent physical NBT encoder/reader and schema rules; integer Fraction IEEE32 RN-even projection. No native output supplies expected data.',
                    scope=['Custom project record, not vanilla player.dat or a Java player serialization contract.',
                           'Raw current/past degree fields roundtrip; no turn, clamp, wrapping or callbacks are invoked by the record.',
                           'Whole record validation and exact canonical bytes only; harness file writes are non-atomic. No interrupted write/save recovery claim.',
                           'Every rejected semantic/wire fixture is followed immediately by a valid decode in the same native process; count bombs are tiny headers, allocation instrumentation is absent.'],
                    commands=['python3 tools/test_player_record.py --preflight','python3 tools/test_player_record.py --build-only','python3 tools/test_player_record.py --skip-build'])
    write_json(ROOT / 'evidence/player-record-native.json', evidence)
    print(json.dumps({'status':'passed','counts':counts(cases),'successful_failure_followups':len(followups)//2,
                      'two_run_output_sha256':runs[0]['response_and_output_sha256'],'binary_sha256':receipt['build']['binary_sha256']}))


if __name__ == '__main__':
    main()
