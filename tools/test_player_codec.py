#!/usr/bin/env python3
"""Independent physical NBT oracle for the native pure-Bend player snapshot codec.

This is a custom bendex:player record, not a vanilla Player save format. Python
constructs and validates test fixtures only; encode/decode execute in Bend.
"""
from __future__ import annotations

import argparse
import collections
import dataclasses
import hashlib
import json
import math
import platform
import random
import re
import struct
import subprocess
import time
from fractions import Fraction
from pathlib import Path

import test_nbt as N
from reference_inventory import fingerprint

ROOT = Path(__file__).resolve().parents[1]
BEND = Path('/Users/chuah/.bend/bin/bend')
BINARY = ROOT / 'build/player-codec-tests'
BUILD = ROOT / 'build/player-codec'
EVIDENCE = ROOT / 'evidence/player-codec-native.json'
DIMENSIONS = ('minecraft:overworld', 'minecraft:the_nether', 'minecraft:the_end')
PT_SHA = 'd583f3014011313097779b69ee0fd8d77bd3ed0e1e7895b629903eb64da9699f'
MAX_BYTES = 4096
WORD_COUNT = 46
PITCH = struct.unpack('>I', struct.pack('>f', 1.5707963268))[0]
ROOT_FIELDS = ('format', 'dimension', 'body', 'support', 'input', 'jumping', 'jump_delay', 'jump_trigger',
               'needs_sync', 'stored_speed', 'head_yaw', 'view_yaw', 'view_pitch')
BODY_FIELDS = ('position', 'box', 'velocity', 'width', 'height', 'on_ground', 'horizontal_collision',
               'vertical_collision', 'vertical_collision_below')
SUPPORT_FIELDS = ('main', 'on_ground_no_blocks')


@dataclasses.dataclass(frozen=True)
class Case:
    name: str
    mode: str
    data: bytes
    expected: bytes | None
    dimension: str = DIMENSIONS[0]
    max_bytes: int = MAX_BYTES
    category: str = 'constructed'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def f32(bits):
    return struct.unpack('>f', struct.pack('>I', bits))[0]


def f64(bits):
    return struct.unpack('>d', struct.pack('>Q', bits))[0]


def raw32(value):
    return struct.unpack('>I', struct.pack('>f', value))[0]


def raw64(value):
    return struct.unpack('>Q', struct.pack('>d', value))[0]


def half32(bits):
    """Exact integer RN-even division of finite binary32 by two."""
    sign, magnitude = bits & 0x80000000, bits & 0x7fffffff
    exponent = magnitude >> 23
    if exponent > 1:
        return sign | (magnitude - 0x800000)
    significand = (magnitude & 0x7fffff) | (0x800000 if exponent else 0)
    retained = significand >> 1
    return sign | (retained + int(bool(significand & 1) and bool(retained & 1)))


def words64(values):
    return tuple(word for bits in values for word in (bits >> 32, bits & 0xffffffff))


def bits64(words):
    return tuple((words[i] << 32) | words[i + 1] for i in range(0, len(words), 2))


def word_bytes(words):
    assert len(words) == WORD_COUNT and all(0 <= w <= 0xffffffff for w in words)
    return struct.pack('<' + 'I' * WORD_COUNT, *words)


def from_word_bytes(data):
    if len(data) != 4 * WORD_COUNT:
        raise ValueError('wrong native snapshot word count')
    return tuple(struct.unpack('<' + 'I' * WORD_COUNT, data))


def normalized_pair(a, b):
    if a == b == 0.0:
        negative = math.copysign(1.0, a) < 0 or math.copysign(1.0, b) < 0
        positive = math.copysign(1.0, a) > 0 or math.copysign(1.0, b) > 0
        return (-0.0 if negative else 0.0, 0.0 if positive else -0.0)
    return (a, b) if a <= b else (b, a)


def make_box(position, width, height):
    x, y, z = map(f64, position)
    half, h = f32(half32(width)), f32(height)
    pairs = [normalized_pair(x - half, x + half), normalized_pair(y, y + h), normalized_pair(z - half, z + half)]
    return tuple(raw64(p[side]) for side in (0, 1) for p in pairs)


def snapshot(position=None, velocity=None, width=0x3f19999a, height=0x3fe66666,
             flags=(1, 0, 0, 0), inputs=(0, 0, 0), jumping=0, delay=0, trigger=0,
             sync=0, speed=0x3dcccccd, head=0, yaw=0, pitch=0, support=None, support_flag=0):
    position = tuple(position if position is not None else map(raw64, (0.5, 64.0, -0.5)))
    velocity = tuple(velocity if velocity is not None else (0, 0, 0))
    box = make_box(position, width, height)
    return (*words64(position), *words64(box), *words64(velocity), width, height, *flags, *inputs,
            jumping, delay, trigger, sync, speed, head, yaw, pitch, int(support is not None),
            *(support if support is not None else (0, 0, 0)), support_flag)


def validate_words(words, dimension):
    if len(words) != WORD_COUNT or dimension not in DIMENSIONS:
        raise ValueError('invalid snapshot shape/dimension')
    position, box, velocity = (bits64(words[a:b]) for a, b in ((0, 6), (6, 18), (18, 24)))
    if not all(math.isfinite(f64(v)) for v in (*position, *box, *velocity)):
        raise ValueError('nonfinite body component')
    width, height = words[24:26]
    if any(not math.isfinite(f32(v)) or f32(v) < 0 for v in (width, height)):
        raise ValueError('nonfinite/negative body dimension')
    if any(words[i] not in (0, 1) for i in (26, 27, 28, 29, 33, 36, 41, 45)):
        raise ValueError('malformed host Bool fixture')
    if any(not math.isfinite(f32(words[i])) for i in (30, 31, 32, 37, 38, 39, 40)):
        raise ValueError('nonfinite player float')
    if abs(f32(words[40])) > f32(PITCH):
        raise ValueError('view pitch range')
    if any(f64(box[i]) > f64(box[i + 3]) for i in range(3)):
        raise ValueError('reversed player box')
    computed = make_box(position, width, height)
    if any(f64(a) != f64(b) for a, b in zip(box, computed, strict=True)):
        raise ValueError('inconsistent player box')
    return words


def txt(value):
    return N.Value(8, N.text(value))


def compound(fields):
    return N.Value(10, tuple((N.text(key), value) for key, value in fields))


def listing(kind, values):
    return N.Value(9, (kind, tuple(N.Value(kind, value) for value in values)))


def snapshot_root(words, dimension):
    body = compound([
        ('position', listing(6, bits64(words[:6]))), ('box', listing(6, bits64(words[6:18]))),
        ('velocity', listing(6, bits64(words[18:24]))), ('width', N.Value(5, words[24])),
        ('height', N.Value(5, words[25])),
        *[(name, N.Value(1, words[i])) for i, name in enumerate(BODY_FIELDS[5:], 26)],
    ])
    support = compound([('main', listing(3, words[42:45] if words[41] else ())),
                        ('on_ground_no_blocks', N.Value(1, words[45]))])
    root = compound([
        ('format', N.Value(3, 1)), ('dimension', txt(dimension)), ('body', body), ('support', support),
        ('input', listing(5, words[30:33])), ('jumping', N.Value(1, words[33])),
        ('jump_delay', N.Value(3, words[34])), ('jump_trigger', N.Value(3, words[35])),
        ('needs_sync', N.Value(1, words[36])), ('stored_speed', N.Value(5, words[37])),
        ('head_yaw', N.Value(5, words[38])), ('view_yaw', N.Value(5, words[39])), ('view_pitch', N.Value(5, words[40])),
    ])
    return N.RootTag(N.text('bendex:player'), root)


def text_value(value):
    if value.kind != 8:
        raise ValueError('expected String tag')
    return b''.join(c.to_bytes(2, 'big') for c in value.payload).decode('utf-16-be', errors='strict')


def fields(value, names):
    if value.kind != 10:
        raise ValueError('expected Compound tag')
    out = {}
    for name, item in value.payload:
        key = text_value(N.Value(8, name))
        if key in out:
            raise ValueError('duplicate field')
        out[key] = item
    if set(out) != set(names):
        raise ValueError('extra/missing field')
    return out


def scalar(value, kind):
    if value.kind != kind:
        raise ValueError('wrong scalar tag')
    return value.payload


def boolean(value):
    result = scalar(value, 1)
    if result not in (0, 1):
        raise ValueError('invalid Byte Bool')
    return result


def sequence(value, element, sizes):
    if value.kind != 9 or value.payload[0] != element or len(value.payload[1]) not in sizes:
        raise ValueError('wrong List element/length')
    return tuple(scalar(v, element) for v in value.payload[1])


def parse_snapshot(data, max_bytes=MAX_BYTES):
    if not 0 <= max_bytes <= 65536:
        raise ValueError('configured byte limit exceeds codec contract')
    root = N.Reader(data, max_bytes=max_bytes, max_elements=16, max_depth=3).root()
    if root.name != N.text('bendex:player'):
        raise ValueError('wrong named root')
    fs = fields(root.value, ROOT_FIELDS)
    if scalar(fs['format'], 3) != 1:
        raise ValueError('wrong format')
    dimension = text_value(fs['dimension'])
    b, s = fields(fs['body'], BODY_FIELDS), fields(fs['support'], SUPPORT_FIELDS)
    main = sequence(s['main'], 3, (0, 3))
    words = (*words64(sequence(b['position'], 6, (3,))), *words64(sequence(b['box'], 6, (6,))),
             *words64(sequence(b['velocity'], 6, (3,))), scalar(b['width'], 5), scalar(b['height'], 5),
             *(boolean(b[k]) for k in BODY_FIELDS[5:]), *sequence(fs['input'], 5, (3,)), boolean(fs['jumping']),
             scalar(fs['jump_delay'], 3), scalar(fs['jump_trigger'], 3), boolean(fs['needs_sync']),
             *(scalar(fs[k], 5) for k in ('stored_speed', 'head_yaw', 'view_yaw', 'view_pitch')),
             int(bool(main)), *(main or (0, 0, 0)), boolean(s['on_ground_no_blocks']))
    return validate_words(words, dimension), dimension


def replace_field(value, name, replacement):
    target = N.text(name)
    assert value.kind == 10 and sum(k == target for k, _ in value.payload) == 1
    return N.Value(10, tuple((k, replacement if k == target else v) for k, v in value.payload))


def corpus():
    cases, rng = [], random.Random(0x26_03_504c)

    def encode_case(name, words, dimension=DIMENSIONS[0], cap=MAX_BYTES, category='constructed', valid=True):
        try:
            validate_words(words, dimension)
            if not 0 <= cap <= 65536:
                raise ValueError('configured byte limit')
            expected = N.encode_root(snapshot_root(words, dimension))
            if len(expected) > cap:
                raise ValueError('output byte limit')
        except ValueError:
            expected = None
        assert (expected is not None) == valid, ('encode oracle expectation', name)
        cases.append(Case(name, 'encode', word_bytes(words), expected, dimension, cap, category))
        if valid:
            decode_case(name + '-readback', expected, cap=cap, category=category)

    def decode_case(name, data, cap=MAX_BYTES, category='constructed', valid=None):
        try:
            words, dimension = parse_snapshot(data, cap)
            expected = word_bytes(words)
        except (ValueError, UnicodeError, struct.error):
            expected, dimension = None, DIMENSIONS[0]
        if valid is not None:
            assert (expected is not None) == valid, ('decode oracle expectation', name)
        cases.append(Case(name, 'decode', data, expected, dimension, cap, category))

    def root_case(name, root, **options):
        decode_case(name, N.encode_root(root), **options)

    base = snapshot(support=(0x80000000, 0x7fffffff, 0xffffffff), support_flag=1)
    base_root = snapshot_root(base, DIMENSIONS[0])
    raw_base = N.encode_root(base_root)
    for dimension in DIMENSIONS:
        encode_case('dimension-' + dimension, base, dimension, category='dimensions')
    for mask in range(256):
        words = list(base)
        for bit, index in enumerate((26, 27, 28, 29, 33, 36, 41, 45)):
            words[index] = (mask >> bit) & 1
        if not words[41]:
            words[42:45] = (0, 0, 0)
        words[34:36] = (rng.choice((0, 1, 0x7fffffff, 0x80000000, 0xffffffff)), rng.getrandbits(32))
        encode_case(f'all-boolean-support-combinations-{mask}', tuple(words), category='all-flags-support-counters')
    widths = (0, 0x80000000, 1, 2, 3, 4, 0x7fffff, 0x800000, 0x800001,
              0x800003, 0x3f19999a, 0x3f800000, 0x7f7fffff)
    for width in widths:
        for height in (0, 0x80000000, 1, 0x3fe66666, 0x7f7fffff):
            words = snapshot(position=(0x8000000000000000, 0, 0x8000000000000000),
                             width=width, height=height, velocity=(1, 0x8000000000000001, 0),
                             inputs=(1, 0x80000000, 0x807fffff), speed=0x80000000,
                             head=0x7f7fffff, yaw=0xff7fffff, pitch=0xbfc90fdb)
            encode_case(f'dimension-bits-{width:08x}-{height:08x}', words, category='dimension-half-rounding-extremes')
    for mask in range(64):
        words = list(snapshot(position=(0x8000000000000000, 0x8000000000000000, 0),
                              velocity=(0x8000000000000000, 0, 0x8000000000000000),
                              width=0x80000000, height=0x80000000, inputs=(0x80000000, 0, 0x80000000),
                              speed=0x80000000, head=0x80000000, yaw=0x80000000, pitch=0x80000000))
        words[6:18] = words64(tuple((0x8000000000000000 if (mask >> i) & 1 else 0) for i in range(6)))
        encode_case(f'all-zero-box-signs-{mask}', tuple(words), category='signed-zero-numerical-box-admission')
    for coordinate in (1, 0x8000000000000001, 0xfffffffffffff, 0x10000000000000,
                       0x7fefffffffffffff, 0xffefffffffffffff, 0x4340000000000000, 0xc340000000000000):
        encode_case(f'coordinate-extreme-{coordinate:016x}', snapshot(position=(coordinate, coordinate, coordinate)), category='coordinate-extremes')
    for pitch in (0, 0x80000000, 1, 0x80000001, PITCH - 1, PITCH, 0x80000000 | (PITCH - 1), 0x80000000 | PITCH):
        encode_case(f'pitch-boundary-{pitch:08x}', snapshot(pitch=pitch), category='pitch-boundaries')
    for i in range(512):
        def finite64():
            while True:
                bits = rng.getrandbits(64)
                if bits & 0x7ff0000000000000 != 0x7ff0000000000000:
                    return bits
        def finite32(positive=False):
            while True:
                bits = rng.getrandbits(31 if positive else 32)
                if bits & 0x7f800000 != 0x7f800000:
                    return bits
        support = tuple(rng.getrandbits(32) for _ in range(3)) if rng.randrange(2) else None
        words = snapshot(position=tuple(finite64() for _ in range(3)), velocity=tuple(finite64() for _ in range(3)),
                         width=finite32(True), height=finite32(True), flags=tuple(rng.randrange(2) for _ in range(4)),
                         inputs=tuple(finite32() for _ in range(3)), jumping=rng.randrange(2),
                         delay=rng.getrandbits(32), trigger=rng.getrandbits(32), sync=rng.randrange(2),
                         speed=finite32(), head=finite32(), yaw=finite32(), pitch=raw32(rng.uniform(-1.57, 1.57)),
                         support=support, support_flag=rng.randrange(2))
        encode_case(f'random-raw-finite-{i}', words, rng.choice(DIMENSIONS), category='seeded-raw-bit-roundtrip')
    for field in range(12):
        root_members = list(base_root.value.payload)
        body = dict(root_members)[N.text('body')]
        support = dict(root_members)[N.text('support')]
        bm, sm = list(body.payload), list(support.payload)
        rng.shuffle(bm); rng.shuffle(sm); rng.shuffle(root_members)
        v = replace_field(N.Value(10, tuple(root_members)), 'body', N.Value(10, tuple(bm)))
        v = replace_field(v, 'support', N.Value(10, tuple(sm)))
        root_case(f'all-member-order-permutation-{field}', dataclasses.replace(base_root, value=v), category='reordered-fields', valid=True)
    for cap in (0, 1, len(raw_base) - 1, len(raw_base), len(raw_base) + 1, 4096, 65536, 65537, 0xffffffff):
        valid = len(raw_base) <= cap <= 65536
        encode_case(f'encode-byte-cap-{cap}', base, cap=cap, category='byte-cap-boundaries', valid=valid)
        decode_case(f'decode-byte-cap-{cap}', raw_base, cap=cap, category='byte-cap-boundaries', valid=valid)

    # Typed Bool cannot contain other words; corrupt physical Byte tags instead.
    for start, count in ((0, 3), (6, 6), (18, 3)):
        for component in range(count):
            for bits in (0x7ff0000000000000, 0xfff0000000000000, 0x7ff8000000000123, 0x7ff0000000000001):
                words = list(base); index = start + 2 * component
                words[index:index + 2] = words64((bits,))
                encode_case(f'bad-body-{start}-{component}-{bits:016x}', tuple(words), valid=False, category='nonfinite-state')
                root_case(f'decode-bad-body-{start}-{component}-{bits:016x}', snapshot_root(tuple(words), DIMENSIONS[0]), valid=False, category='nonfinite-state')
    for index in (24, 25, 30, 31, 32, 37, 38, 39, 40):
        for bits in (0x7f800000, 0xff800000, 0x7fc00123, 0x7f800001):
            words = list(base); words[index] = bits
            encode_case(f'bad-f32-{index}-{bits:08x}', tuple(words), valid=False, category='nonfinite-state')
            root_case(f'decode-bad-f32-{index}-{bits:08x}', snapshot_root(tuple(words), DIMENSIONS[0]), valid=False, category='nonfinite-state')
    for index in (24, 25):
        for bits in (0x80000001, 0xbf800000, 0xff7fffff):
            words = list(base); words[index] = bits
            encode_case(f'negative-dimension-{index}-{bits:08x}', tuple(words), valid=False, category='dimension-admission')
            root_case(f'decode-negative-dimension-{index}-{bits:08x}', snapshot_root(tuple(words), DIMENSIONS[0]), valid=False, category='dimension-admission')
    for bits in (PITCH + 1, 0x80000000 | (PITCH + 1), 0x40000000, 0xc0000000, 0x7f7fffff):
        words = list(base); words[40] = bits
        encode_case(f'outside-pitch-{bits:08x}', tuple(words), valid=False, category='pitch-admission')
        root_case(f'decode-outside-pitch-{bits:08x}', snapshot_root(tuple(words), DIMENSIONS[0]), valid=False, category='pitch-admission')
    for i in range(6):
        words = list(base); box = list(bits64(words[6:18])); box[i] = raw64(f64(box[i]) + 0.125)
        words[6:18] = words64(box)
        encode_case(f'inconsistent-box-{i}', tuple(words), valid=False, category='box-admission')
        root_case(f'decode-inconsistent-box-{i}', snapshot_root(tuple(words), DIMENSIONS[0]), valid=False, category='box-admission')
    words = list(base); box = list(bits64(words[6:18])); box[0], box[3] = box[3], box[0]; words[6:18] = words64(box)
    encode_case('reversed-box', tuple(words), valid=False, category='box-admission')
    root_case('decode-reversed-box', snapshot_root(tuple(words), DIMENSIONS[0]), valid=False, category='box-admission')
    for dimension in ('', 'minecraft:unknown', 'minecraft:Overworld', 'minecraft:overworld ', 'mod:é😀'):
        encode_case('invalid-dimension-' + repr(dimension), base, dimension, valid=False, category='dimension-admission')
        root_case('decode-invalid-dimension-' + repr(dimension), snapshot_root(base, dimension), valid=False, category='dimension-admission')
    for dimension in ('minecraft:overworld\0', '\ud800', '\udc00'):
        root_case('decode-invalid-dimension-' + repr(dimension), snapshot_root(base, dimension), valid=False, category='dimension-admission')

    def schema_corruptions(label, value, wrap):
        assert value.kind == 10
        for index, (name, item) in enumerate(value.payload):
            root_case(f'{label}-missing-{index}', wrap(N.Value(10, value.payload[:index] + value.payload[index + 1:])), valid=False, category='exact-schema')
            root_case(f'{label}-duplicate-{index}', wrap(N.Value(10, value.payload + ((name, item),))), valid=False, category='exact-schema')
            replacement = N.Value(8, N.text('wrong')) if item.kind != 8 else N.Value(3, 1)
            bad = N.Value(10, value.payload[:index] + ((name, replacement),) + value.payload[index + 1:])
            root_case(f'{label}-wrong-type-{index}', wrap(bad), valid=False, category='exact-schema')
        root_case(f'{label}-extra', wrap(N.Value(10, value.payload + ((N.text('extra'), N.Value(1, 0)),))), valid=False, category='exact-schema')
    schema_corruptions('root', base_root.value, lambda v: dataclasses.replace(base_root, value=v))
    for name in ('body', 'support'):
        value = dict(base_root.value.payload)[N.text(name)]
        schema_corruptions(name, value, lambda v, name=name: dataclasses.replace(base_root, value=replace_field(base_root.value, name, v)))
    for name in ('', 'bendex:world', 'bendex:player\0', 'BENDEX:player'):
        root_case('wrong-root-' + repr(name), dataclasses.replace(base_root, name=N.text(name)), valid=False, category='root-version')
    for kind in (0, 1, 3, 8, 9):
        value = {0: N.Value(0), 1: N.Value(1, 0), 3: N.Value(3, 1), 8: txt('x'), 9: listing(1, ())}[kind]
        root_case(f'wrong-root-tag-{kind}', dataclasses.replace(base_root, value=value), valid=False, category='root-version')
    for version in (0, 2, 0x7fffffff, 0x80000000, 0xffffffff):
        root_case(f'wrong-version-{version}', dataclasses.replace(base_root, value=replace_field(base_root.value, 'format', N.Value(3, version))), valid=False, category='root-version')
    for container, names in (('', ('jumping', 'needs_sync')), ('body', BODY_FIELDS[5:]), ('support', ('on_ground_no_blocks',))):
        original = dict(base_root.value.payload)[N.text(container)] if container else base_root.value
        for name in names:
            for bits in (2, 127, 128, 255):
                v = replace_field(original, name, N.Value(1, bits))
                root = dataclasses.replace(base_root, value=replace_field(base_root.value, container, v) if container else v)
                root_case(f'bad-byte-{container}-{name}-{bits}', root, valid=False, category='boolean-byte-domain')
    for container, name, element, count in (('body', 'position', 6, 3), ('body', 'box', 6, 6), ('body', 'velocity', 6, 3), ('', 'input', 5, 3), ('support', 'main', 3, 3)):
        original = dict(base_root.value.payload)[N.text(container)] if container else base_root.value
        for actual_count in sorted({0, 1, 2, count - 1, count + 1, 16, 17}):
            if actual_count == count or name == 'main' and actual_count == 0:
                continue
            v = replace_field(original, name, listing(element, (0,) * actual_count))
            root = dataclasses.replace(base_root, value=replace_field(base_root.value, container, v) if container else v)
            root_case(f'wrong-list-size-{container}-{name}-{actual_count}', root, valid=False, category='list-shape')
        for wrong_kind in (0, 1, 3, 5, 6, 10, 12):
            if wrong_kind == element:
                continue
            v = replace_field(original, name, listing(wrong_kind, ()))
            root = dataclasses.replace(base_root, value=replace_field(base_root.value, container, v) if container else v)
            root_case(f'wrong-list-kind-{container}-{name}-{wrong_kind}', root, valid=False, category='list-shape')
    for n in range(len(raw_base)):
        decode_case(f'truncated-{n}', raw_base[:n], valid=False, category='truncation')
    for suffix in (b'\0', b'\xff', b'\x0a\0\0\0', b'garbage'):
        decode_case('trailing-' + suffix.hex(), raw_base + suffix, valid=False, category='trailing-data')
    for count in (17, 65536, 0x7fffffff, 0x80000000, 0xffffffff):
        for kind in (7, 9, 11, 12):
            payload = (b'\x03' if kind == 9 else b'') + struct.pack('>I', count)
            raw = b'\x0a' + N.mutf_encode(N.text('bendex:player')) + bytes((kind,)) + N.mutf_encode(N.text('bomb')) + payload
            decode_case(f'array-list-count-bomb-{kind}-{count}', raw, valid=False, category='preallocation-count-bombs')
    for depth in (4, 16, 128):
        v = N.Value(1, 0)
        for _ in range(depth):
            v = N.Value(9, (v.kind, (v,)))
        root_case(f'container-depth-bomb-{depth}', dataclasses.replace(base_root, value=N.Value(10, base_root.value.payload + ((N.text('bomb'), v),))), valid=False, category='depth-bombs')
    for count in (16, 17, 64):
        v = N.Value(10, tuple((N.text(f'extra{i}'), N.Value(1, 0)) for i in range(count)))
        root_case(f'compound-count-boundary-{count}', dataclasses.replace(base_root, value=v), valid=False, category='compound-bombs')
    for size, cap in ((4097, 4096), (65537, 65536)):
        decode_case(f'input-byte-overflow-{size}-{cap}', raw_base + b'\0' * (size - len(raw_base)), cap=cap, valid=False, category='byte-cap-boundaries')
    # Existing NBT readUTF policy admits noncanonical encodings of the same units.
    assert raw_base[:4] == b'\x0a\x00\x0db'
    decode_case('noncanonical-mutf-root', b'\x0a\x00\x0e\xc1\xa2' + raw_base[4:], valid=True, category='physical-mutf-read-policy')
    for i in range(400):
        data = bytearray(raw_base)
        data[rng.randrange(len(data))] ^= 1 << rng.randrange(8)
        decode_case(f'seeded-single-bit-mutation-{i}', bytes(data), category='seeded-mutations')
    if len({x.name for x in cases}) != len(cases):
        raise AssertionError('duplicate case name')
    return cases, raw_base, word_bytes(base)


def run(command, timeout=120):
    started = time.monotonic()
    result = subprocess.run(list(map(str, command)), cwd=ROOT, capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f'command failed ({result.returncode}): {command}\n{result.stdout[-4000:]}\n{result.stderr[-4000:]}')
    return {'command': list(map(str, command)), 'exit_code': result.returncode, 'stdout': result.stdout,
            'stderr': result.stderr, 'seconds': round(time.monotonic() - started, 6)}


def imports(paths):
    todo, found = list(paths), set()
    while todo:
        path = todo.pop()
        if path in found:
            continue
        if not path.is_file():
            raise ValueError('missing source import: ' + str(path))
        found.add(path)
        for relative in re.findall(r'^import\s+(\.[^\s]+)', path.read_text(), re.M):
            todo.append((path.parent / relative).resolve())
    return {str(p.relative_to(ROOT)): sha(p.read_bytes()) for p in sorted(found)}


def oracle_selftest(cases):
    rng, halvings, sums = random.Random(0x32_16_26_03), 0, 0
    for _ in range(10000):
        bits = rng.getrandbits(32)
        if bits & 0x7f800000 == 0x7f800000:
            continue
        assert half32(bits) == raw32(f32(bits) / 2), ('F32 half oracle disagreement', bits)
        halvings += 1
    for case in cases:
        if case.mode != 'encode' or case.expected is None:
            continue
        words = from_word_bytes(case.data)
        x, y, z = map(f64, bits64(words[:6]))
        half, height = f32(half32(words[24])), f32(words[25])
        for a, b in ((x, -half), (x, half), (y, height), (z, -half), (z, half)):
            observed = a + b
            exact = float(Fraction.from_float(a) + Fraction.from_float(b))
            assert observed == exact and (observed == 0 or raw64(observed) == raw64(exact)), ('F64 sum oracle disagreement', a, b)
            sums += 1
    return {'integer_F32_half_vs_hardware': halvings, 'rational_F64_box_sum_checks': sums,
            'zero_sign': 'Exact rationals verify numerical zero; IEEE host operations and explicit min/max determine its sign'}


def native_cases(cases, binary=BINARY, batch_size=64):
    BUILD.mkdir(parents=True, exist_ok=True)
    reports, failures = [], []
    for offset in range(0, len(cases), batch_size):
        batch = cases[offset:offset + batch_size]
        args, outputs = [], []
        for i, case in enumerate(batch, offset):
            ip, op = BUILD / f'input-{i:05d}.bin', BUILD / f'output-{i:05d}.bin'
            ip.write_bytes(case.data)
            op.unlink(missing_ok=True)
            args += [case.mode, str(ip), str(op), case.dimension if case.mode == 'encode' else 'ignored', str(case.max_bytes)]
            outputs.append(op)
        result = run([binary, '--gpu', 'off', '--threads', '1', '--', *args], timeout=60)
        lines = result['stdout'].splitlines()
        assert len(lines) == len(batch), ('native response count', offset, len(lines), len(batch), result['stdout'][-2000:])
        for case, op, line in zip(batch, outputs, lines, strict=True):
            reply = json.loads(line)
            if case.expected is None:
                assert reply.get('ok') is False and isinstance(reply.get('error'), str) and reply['error'], (case.name, reply)
                assert not op.exists(), ('rejection left output file', case.name, op)
                failures.append({'case': case.name, 'mode': case.mode, 'category': case.category,
                                 'input_bytes': len(case.data), 'max_bytes': case.max_bytes, 'error': reply['error']})
            else:
                assert reply.get('ok') is True and op.is_file(), (case.name, reply, op.exists())
                actual = op.read_bytes()
                assert actual == case.expected, ('native bytes differ', case.name, len(actual), len(case.expected),
                                                 next((i for i, (a, b) in enumerate(zip(actual, case.expected)) if a != b), None))
                if case.mode == 'decode':
                    assert reply.get('dimension') == case.dimension, (case.name, reply, case.dimension)
                    validate_words(from_word_bytes(actual), case.dimension)
                else:
                    words, dimension = parse_snapshot(actual, case.max_bytes)
                    assert word_bytes(words) == case.data and dimension == case.dimension, ('physical readback', case.name)
        reports.append({'first_case': offset, 'cases': len(batch), 'seconds': result['seconds'],
                        'exit_code': result['exit_code'], 'stderr': result['stderr']})
    return reports, failures


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--skip-build', action='store_true')
    parser.add_argument('--fixture-only', action='store_true', help='validate independent corpus without a native executable')
    args = parser.parse_args()
    cases, canonical, base_words = corpus()
    selfchecks = oracle_selftest(cases)
    digest_records = [(c.name, c.mode, c.dimension, c.max_bytes, c.category, sha(c.data), None if c.expected is None else sha(c.expected)) for c in cases]
    fixture_hash = sha(json.dumps(digest_records, ensure_ascii=True, separators=(',', ':')).encode())
    if args.fixture_only:
        print(json.dumps({'status': 'oracle-corpus-valid', 'cases': len(cases), 'fixture_sha256': fixture_hash,
                          'categories': dict(collections.Counter(c.category for c in cases)), 'canonical_bytes': len(canonical)}, sort_keys=True))
        return
    builds = []
    binary = BINARY
    emitted = ROOT / 'build/player-codec-tests.c'
    if not args.skip_build:
        BUILD.mkdir(parents=True, exist_ok=True)
        binary, emitted = BUILD / 'player-codec-tests', BUILD / 'player-codec-tests.c'
        builds.append(run([BEND, 'tests/player_codec.bend', '-o', emitted], timeout=600))
        builds.append(run([BEND, 'tests/player_codec.bend', '-o', binary], timeout=600))
    source_hashes = imports([ROOT / 'src/player_codec.bend', ROOT / 'tests/player_codec.bend'])
    assert source_hashes.get('src/player_tick.bend') == PT_SHA, 'frozen player tick source changed'
    for path in source_hashes:
        if path.startswith('src/'):
            assert not re.search(r'@unsafe|^import\s+["\']|\w!\(', (ROOT / path).read_text(), re.M), ('unexpected host/unsafe dependency', path)
    started = time.monotonic()
    batches, failures = native_cases(cases, binary)
    # Each failure is followed by a known-good decode in the same native batch.
    followups = []
    for i, c in enumerate(c for c in cases if c.expected is None):
        followups += [c, Case(f'after-failure-{i}', 'decode', canonical, base_words, category='failure-followup')]
    follow_batches, follow_failures = native_cases(followups, binary, batch_size=64)
    assert len(follow_failures) == len(failures)
    assert source_hashes == imports([ROOT / 'src/player_codec.bend', ROOT / 'tests/player_codec.bend']), 'sources changed during verification'
    counts = {'cases': len(cases), 'encode': sum(c.mode == 'encode' for c in cases), 'decode': sum(c.mode == 'decode' for c in cases),
              'accepted': sum(c.expected is not None for c in cases), 'rejected': len(failures),
              'exact_canonical_encodes': sum(c.mode == 'encode' and c.expected is not None for c in cases),
              'exact_snapshot_decodes': sum(c.mode == 'decode' and c.expected is not None for c in cases),
              'successful_failure_followups': len(failures)}
    evidence = {'status': 'passed', 'schema': 1, 'pin': '26.3', 'confidence': 'high for recorded fixtures',
                'format': 'custom bendex:player NBT snapshot format1; not vanilla player.dat', 'counts': counts,
                'categories': dict(collections.Counter(c.category for c in cases)), 'fixture_sha256': fixture_hash,
                'oracle_selfchecks': selfchecks,
                'oracle': {'physical_nbt': 'Independent Python test_nbt.Reader and physical encode_root preserve raw Float/Double bits and compound order; no Java object-model zero/NaN normalization used',
                           'schema': 'Exact named root/version/types/field sets, all booleans0/1, strict three-dimension list, finite state/view floats, pitch bound, nonnegative dimensions, normalized and numerically recomputed box',
                           'make_box': 'Integer-exact RN-even F32 width/2; host IEEE binary64 additions/subtractions; explicit Java signed-zero min/max rules',
                           'support': 'Int-list length0/3 with raw U32 coordinates; all support presence/flag/body flag combinations admitted; absent coords decode as0',
                           'mutation_expectations': 'Each mutation independently parsed and validated before any native call; accepted mutations require exact raw-word readback',
                           'limits': {'default_bytes': MAX_BYTES, 'maximum_configured_bytes': 65536, 'nbt_depth': 3, 'nbt_elements': 16},
                           'kernel_boundary': 'This runner records native behavioral evidence; source/test kernel verification is performed separately by the source owner'},
                'platform': platform.platform(), 'python': platform.python_version(), 'compiler': fingerprint(BEND),
                'binary': fingerprint(binary), 'native_binary': str(binary.relative_to(ROOT)), 'builds': builds, 'sources_sha256': source_hashes,
                'test_oracle_sha256': {p: sha((ROOT / p).read_bytes()) for p in ('tools/test_player_codec.py', 'tools/test_nbt.py')},
                'canonical_fixture_bytes': len(canonical), 'canonical_fixture_sha256': sha(canonical),
                'native_batches': batches, 'failure_followup_batches': follow_batches, 'rejections': failures,
                'validation_seconds': round(time.monotonic() - started, 6),
                'commands': ['python3 tools/test_player_codec.py' + (' --skip-build' if args.skip_build else ''),
                             './' + str(binary.relative_to(ROOT)) + ' --gpu off --threads 1 -- MODE INPUT_PATH OUTPUT_PATH DIMENSION MAX_BYTES ...'],
                'scope': ['No disk persistence/atomic replacement/recovery or client snapshot integration is established by this codec test.',
                          'Count/depth bombs use tiny physical headers advertising huge counts, reject without an output file, and complete under a bounded process timeout; this runner does not instrument allocations.']}
    if emitted.exists():
        evidence['emitted_c'] = fingerprint(emitted)
    EVIDENCE.write_text(json.dumps(evidence, ensure_ascii=True, sort_keys=True, indent=2) + '\n')
    print(json.dumps({'status': evidence['status'], 'counts': counts, 'fixture_sha256': fixture_hash,
                      'validation_seconds': evidence['validation_seconds']}, sort_keys=True))


if __name__ == '__main__':
    main()
