#!/usr/bin/env python3
"""Independent physical-wire NBT fixtures against the compiled pure-Bend codec.

Python is a test oracle and reference extractor only. The tested codec executes
in the native Bend harness. Actual pinned Java 26.3 TagTypes and Java 25
DataInputStream/readUTF provide a second, semantic oracle; their transformations
of duplicate keys, list wrappers, empty lists and NaNs are recorded explicitly.
"""
from __future__ import annotations

import argparse
import collections
import dataclasses
import gzip
import hashlib
import json
import platform
import random
import re
import struct
import subprocess
import sys
import time
import zipfile
from pathlib import Path

from reference_inventory import JAVA, INSTALL
from reference_block_probe import verified_classpath

ROOT = Path(__file__).resolve().parents[1]
BEND = Path('/Users/chuah/.bend/bin/bend')
BUILD = ROOT / 'build/nbt-reference'
DEFAULT_BYTES = 16 * 1024 * 1024
DEFAULT_ELEMENTS = 1_048_576
DEFAULT_DEPTH = 512
sys.setrecursionlimit(max(sys.getrecursionlimit(), 4096))


@dataclasses.dataclass(frozen=True)
class Value:
    kind: int
    payload: object = None


@dataclasses.dataclass(frozen=True)
class RootTag:
    name: tuple[int, ...]
    value: Value


@dataclasses.dataclass(frozen=True)
class Case:
    name: str
    data: bytes
    expected: bytes | None
    category: str


def sha(data):
    return hashlib.sha256(data).hexdigest()


def mutf_encode(units):
    out = bytearray()
    for c in units:
        if not 0 <= c <= 0xffff:
            raise ValueError('UTF-16 code unit out of range')
        if 1 <= c <= 0x7f:
            out.append(c)
        elif c <= 0x7ff:
            out.extend((0xc0 | c >> 6, 0x80 | c & 63))
        else:
            out.extend((0xe0 | c >> 12, 0x80 | (c >> 6) & 63, 0x80 | c & 63))
    if len(out) > 0xffff:
        raise ValueError('modified UTF-8 byte length exceeds u16')
    return struct.pack('>H', len(out)) + out


def mutf_decode(data):
    """Java DataInput.readUTF's liberal 1/2/3-byte decoder, in UTF-16 units."""
    units, i = [], 0
    while i < len(data):
        c = data[i]
        if c < 0x80:
            units.append(c)
            i += 1
        elif 0xc0 <= c <= 0xdf:
            if i + 1 >= len(data) or data[i + 1] & 0xc0 != 0x80:
                raise ValueError('malformed modified UTF-8 two-byte sequence')
            units.append(((c & 31) << 6) | (data[i + 1] & 63))
            i += 2
        elif 0xe0 <= c <= 0xef:
            if i + 2 >= len(data) or any(data[j] & 0xc0 != 0x80 for j in (i + 1, i + 2)):
                raise ValueError('malformed modified UTF-8 three-byte sequence')
            units.append(((c & 15) << 12) | ((data[i + 1] & 63) << 6) | (data[i + 2] & 63))
            i += 3
        else:
            raise ValueError('invalid modified UTF-8 lead byte')
    return tuple(units)


def text(s):
    raw = s.encode('utf-16-be', errors='surrogatepass')
    return tuple(struct.unpack('>' + 'H' * (len(raw) // 2), raw))


class Reader:
    def __init__(self, data, *, max_bytes=DEFAULT_BYTES, max_elements=DEFAULT_ELEMENTS, max_depth=DEFAULT_DEPTH):
        if len(data) > max_bytes:
            raise ValueError('input byte limit')
        self.data, self.offset = data, 0
        self.max_elements, self.max_depth = max_elements, max_depth
        self.types = collections.Counter()

    def take(self, size):
        if size < 0 or self.offset + size > len(self.data):
            raise ValueError('truncated payload')
        chunk = self.data[self.offset:self.offset + size]
        self.offset += size
        return chunk

    def number(self, fmt):
        return struct.unpack('>' + fmt, self.take(struct.calcsize(fmt)))[0]

    def string(self):
        return mutf_decode(self.take(self.number('H')))

    def count(self):
        count = self.number('i')
        if not 0 <= count <= self.max_elements:
            raise ValueError('negative or excessive element count')
        return count

    def value(self, kind, depth=0):
        if not 1 <= kind <= 12:
            raise ValueError('unknown or misplaced payload tag')
        self.types[kind] += 1
        if kind in (1, 2, 3, 4, 5, 6):
            return Value(kind, self.number({1: 'B', 2: 'H', 3: 'I', 4: 'Q', 5: 'I', 6: 'Q'}[kind]))
        if kind == 7:
            return Value(kind, self.take(self.count()))
        if kind == 8:
            return Value(kind, self.string())
        if kind in (9, 10):
            if depth >= self.max_depth:
                raise ValueError('container depth limit')
            if kind == 9:
                element, count = self.number('B'), self.count()
                if element > 12 or element == 0 and count > 0:
                    raise ValueError('invalid list element tag')
                return Value(kind, (element, tuple(self.value(element, depth + 1) for _ in range(count))))
            members = []
            while True:
                child = self.number('B')
                if child == 0:
                    return Value(kind, tuple(members))
                if len(members) >= self.max_elements:
                    raise ValueError('compound element limit')
                if child > 12:
                    raise ValueError('invalid compound payload tag')
                name = self.string()
                members.append((name, self.value(child, depth + 1)))
        count = self.count()
        fmt = 'I' if kind == 11 else 'Q'
        return Value(kind, tuple(struct.unpack('>' + fmt * count, self.take(struct.calcsize(fmt) * count))))

    def root(self):
        kind = self.number('B')
        result = RootTag((), Value(0)) if kind == 0 else RootTag(self.string(), self.value(kind))
        if self.offset != len(self.data):
            raise ValueError('trailing bytes')
        return result


def encode_value(value):
    kind, p = value.kind, value.payload
    if kind in (1, 2, 3, 4, 5, 6):
        return struct.pack('>' + {1: 'B', 2: 'H', 3: 'I', 4: 'Q', 5: 'I', 6: 'Q'}[kind], p)
    if kind == 7:
        return struct.pack('>i', len(p)) + p
    if kind == 8:
        return mutf_encode(p)
    if kind == 9:
        element, values = p
        return bytes((element,)) + struct.pack('>i', len(values)) + b''.join(encode_value(v) for v in values)
    if kind == 10:
        return b''.join(bytes((v.kind,)) + mutf_encode(name) + encode_value(v) for name, v in p) + b'\0'
    if kind in (11, 12):
        return struct.pack('>i', len(p)) + struct.pack('>' + ('I' if kind == 11 else 'Q') * len(p), *p)
    raise ValueError('misplaced or unknown payload tag')


def encode_root(root):
    if root.value.kind == 0:
        return b'\0'
    return bytes((root.value.kind,)) + mutf_encode(root.name) + encode_value(root.value)


def parse(data):
    return Reader(data).root()


def java_semantics(value):
    """Normalize only Java's observed object-model/write transformations."""
    kind, p = value.kind, value.payload
    if kind == 5 and p == 0x80000000:
        return (5, 0)
    if kind == 6 and p == 0x8000000000000000:
        return (6, 0)
    if kind == 5 and p & 0x7f800000 == 0x7f800000 and p & 0x007fffff:
        return (5, 0x7fc00000)
    if kind == 6 and p & 0x7ff0000000000000 == 0x7ff0000000000000 and p & 0x000fffffffffffff:
        return (6, 0x7ff8000000000000)
    if kind == 10:
        last = {name: java_semantics(v) for name, v in p}
        return (10, tuple(sorted(last.items())))
    if kind == 9:
        _, items = p
        values = []
        for v in items:
            normalized = java_semantics(v)
            if normalized[0] == 10 and len(normalized[1]) == 1 and normalized[1][0][0] == ():
                normalized = normalized[1][0][1]
            values.append(normalized)
        return (9, tuple(values))
    return (kind, p)


def synthetic_corpus():
    cases = []
    def valid(name, root, category='constructed'):
        raw = encode_root(root)
        assert encode_root(parse(raw)) == raw
        cases.append(Case(name, raw, raw, category))
    def wire(name, raw, category='noncanonical-mutf'):
        canonical = encode_root(parse(raw))
        cases.append(Case(name, raw, canonical, category))
    def invalid(name, raw, category='malformed'):
        try:
            parse(raw)
        except ValueError:
            cases.append(Case(name, raw, None, category))
        else:
            raise AssertionError(('oracle accepted malformed fixture', name, raw[:80].hex()))
    valid('end-root', RootTag((), Value(0)))
    valid('compound-empty', RootTag((), Value(10, ())))
    for kind, bits in [(1, [0, 1, 127, 128, 255]), (2, [0, 1, 32767, 32768, 65535]),
                       (3, [0, 1, 0x7fffffff, 0x80000000, 0xffffffff]),
                       (4, [0, 1, 0x7fffffffffffffff, 0x8000000000000000, 0xffffffffffffffff]),
                       (5, [0, 0x80000000, 0x3f800000, 0x00000001, 0x007fffff, 0x00800000,
                            0x7f7fffff, 0x7f800000, 0xff800000, 0x7fc00000, 0x7fa12345, 0xffabcdef]),
                       (6, [0, 0x8000000000000000, 0x3ff0000000000000, 1, 0x000fffffffffffff,
                            0x0010000000000000, 0x7fefffffffffffff, 0x7ff0000000000000,
                            0xfff0000000000000, 0x7ff8000000000000, 0x7ff123456789abcd, 0xfffdeadbeef12345])]:
        for raw in bits:
            valid(f'raw-tag-{kind}-{raw:x}', RootTag(text('raw'), Value(kind, raw)), 'primitive-bits')
    for i, units in enumerate([(), text('ASCII'), (0,), (1, 0x7f, 0x80, 0x7ff, 0x800, 0xffff),
                               text('é€😀ไทย'), (0xd800,), (0xdc00,), (0xd83d, 0xde00),
                               (0xd800, 0x61, 0xdc00), tuple(range(256))]):
        valid(f'text-units-{i}', RootTag(units, Value(8, units)), 'utf16-code-units')
    for block in range(4):
        valid(f'all-utf16-unit-values-block-{block}', RootTag((), Value(8, tuple(range(block * 16384, (block + 1) * 16384)))), 'every-utf16-unit')
    valid('text-byte-length-65535', RootTag((), Value(8, (0xffff,) * 21845)), 'u16-byte-boundary')
    valid('text-ascii-length-65535', RootTag((), Value(8, (0x61,) * 65535)), 'u16-byte-boundary')
    for element in range(13):
        valid(f'empty-list-{element}', RootTag((), Value(9, (element, ()))), 'empty-list-header')
    for kind, p in [(7, b''), (7, bytes(range(256))), (11, ()), (11, (0, 0x7fffffff, 0x80000000, 0xffffffff)),
                    (12, ()), (12, (0, 0x7fffffffffffffff, 0x8000000000000000, 0xffffffffffffffff))]:
        valid(f'array-{kind}-{len(p)}', RootTag(text('array'), Value(kind, p)), 'array-bits')
    valid('duplicate-compound-keys', RootTag(text('root'), Value(10, ((text('a'), Value(1, 1)), (text('a'), Value(1, 2))))), 'physical-boundary')
    valid('compound-wire-order', RootTag((), Value(10, ((text('z'), Value(3, 7)), (text('a'), Value(3, 8))))), 'physical-boundary')
    wrapper = Value(10, (((), Value(1, 7)),))
    valid('java-list-wrapper-wire-preserved', RootTag((), Value(9, (10, (wrapper,)))), 'physical-boundary')
    valid('all-tags-compound', RootTag(text('all'), Value(10, tuple((text(f't{k}'), Value(k, p)) for k, p in
          [(1, 255), (2, 0x8000), (3, 0xffffffff), (4, 0x8000000000000000), (5, 0x7fa12345),
           (6, 0x8000000000000000), (7, b'\0\x7f\x80\xff'), (8, (0, 0xd800, 0xdc00)),
           (9, (3, (Value(3, 1), Value(3, 0xffffffff)))), (10, ()), (11, (0, 0xffffffff)),
           (12, (0, 0xffffffffffffffff))]))), 'mixed-tags')
    mutf_valid = ['00', 'c080', 'c181', 'c1bf', 'e08080', 'e08081', 'e09fbf', 'e0a080', 'eda080', 'edbfbf', 'eda0bdedb880']
    for i, h in enumerate(mutf_valid):
        b = bytes.fromhex(h)
        wire(f'liberal-mutf-value-{i}', b'\x08\0\0' + struct.pack('>H', len(b)) + b)
        wire(f'liberal-mutf-name-{i}', b'\x01' + struct.pack('>H', len(b)) + b + b'\x07')
    for i, h in enumerate(['80', 'bf', 'c0', 'c2', 'c241', 'e0', 'e080', 'e08041', 'e04180', 'f09f9880', 'ff', 'fe']):
        b = bytes.fromhex(h)
        invalid(f'malformed-mutf-value-{i}', b'\x08\0\0' + struct.pack('>H', len(b)) + b)
        invalid(f'malformed-mutf-name-{i}', b'\x01' + struct.pack('>H', len(b)) + b + b'\x07')
    for name, raw in [('mutf-value-canonical-byte-overflow', b'\x08\0\0\xff\xff' + b'\0' * 65535),
                      ('mutf-name-canonical-byte-overflow', b'\x01\xff\xff' + b'\0' * 65535 + b'\x07')]:
        decoded = parse(raw)
        try:
            encode_root(decoded)
        except ValueError:
            cases.append(Case(name, raw, None, 'encoder-u16-overflow'))
        else:
            raise AssertionError('oracle accepted oversized canonical modified UTF-8')
    invalid('empty-input', b'')
    for kind in (13, 127, 128, 255):
        invalid(f'unknown-root-{kind}', bytes((kind,)) + b'\0\0')
        invalid(f'unknown-compound-child-{kind}', b'\x0a\0\0' + bytes((kind,)) + b'\0\0\0')
        invalid(f'unknown-empty-list-{kind}', b'\x09\0\0' + bytes((kind,)) + b'\0\0\0\0', 'strict-policy')
    for kind in (7, 11, 12):
        for count in (-1, -0x80000000, DEFAULT_ELEMENTS + 1, 0x7fffffff):
            invalid(f'array-{kind}-count-{count}', bytes((kind,)) + b'\0\0' + struct.pack('>i', count), 'length-policy')
    for element in (0, 1, 10, 13, 255):
        invalid(f'negative-list-{element}', b'\x09\0\0' + bytes((element,)) + b'\xff\xff\xff\xff', 'length-policy')
    invalid('positive-end-list', b'\x09\0\0\0\0\0\0\x01')
    invalid('huge-list-count', b'\x09\0\0\x01' + struct.pack('>i', DEFAULT_ELEMENTS + 1), 'length-policy')
    for count in (0, 1, 17, 255, 2048):
        invalid(f'truncated-byte-array-{count}', b'\x07\0\0' + struct.pack('>i', count + 1) + b'\x61' * count)
    samples = list(cases[:46]) + [c for c in cases if c.name == 'all-tags-compound']
    seen = set()
    for case in samples:
        for n in range(len(case.data)):
            raw = case.data[:n]
            if raw not in seen:
                seen.add(raw)
                invalid(f'truncated-{case.name}-{n}', raw, 'every-prefix-truncation')
    for case in samples:
        invalid(f'trailing-{case.name}', case.data + b'\xff', 'strict-policy')
    rng = random.Random(0x26_03_4e42)
    alphabet = (0, 1, 0x61, 0x7f, 0x80, 0x7ff, 0x800, 0x20ac, 0xd800, 0xdc00, 0xffff)
    def generated(kind, depth):
        if kind < 7:
            return Value(kind, rng.getrandbits({1: 8, 2: 16, 3: 32, 4: 64, 5: 32, 6: 64}[kind]))
        if kind == 7:
            return Value(kind, bytes(rng.randrange(256) for _ in range(rng.randrange(12))))
        if kind == 8:
            return Value(kind, tuple(rng.choice(alphabet) for _ in range(rng.randrange(12))))
        if kind in (11, 12):
            return Value(kind, tuple(rng.getrandbits(32 if kind == 11 else 64) for _ in range(rng.randrange(12))))
        allowed = list(range(1, 13)) if depth else [1, 2, 3, 4, 5, 6, 7, 8, 11, 12]
        if kind == 9:
            child = rng.choice(allowed)
            return Value(9, (child, tuple(generated(child, depth - 1) for _ in range(rng.randrange(5)))))
        return Value(10, tuple((tuple(rng.choice(alphabet) for _ in range(rng.randrange(8))),
                               generated(rng.choice(allowed), depth - 1)) for _ in range(rng.randrange(5))))
    for i in range(300):
        valid(f'generated-{i}', RootTag(tuple(rng.choice(alphabet) for _ in range(rng.randrange(8))),
                                       generated(rng.randrange(1, 13), 4)), 'generated')
    for n in (1, 64, 128, 256, 512):
        v = Value(1, 7)
        for _ in range(n):
            v = Value(9, (v.kind, (v,)))
        valid(f'container-depth-{n}', RootTag((), v), 'depth-policy')
    v = Value(1, 7)
    for _ in range(513):
        v = Value(9, (v.kind, (v,)))
    invalid('container-depth-513', encode_root(RootTag((), v)), 'depth-policy')
    for topology in ('compound', 'alternating'):
        v = Value(1, 7)
        for level in range(512):
            v = Value(10, (((), v),)) if topology == 'compound' or level % 2 else Value(9, (v.kind, (v,)))
        valid(f'container-depth-512-{topology}', RootTag((), v), 'depth-policy')
    valid('byte-array-element-limit-1048576', RootTag((), Value(7, bytes(range(256)) * 4096)), 'element-policy')
    valid('wide-byte-array-65536', RootTag((), Value(7, bytes(range(256)) * 256)), 'wide')
    valid('wide-int-array-16384', RootTag((), Value(11, tuple((i * 0x9e3779b1) & 0xffffffff for i in range(16384)))), 'wide')
    valid('wide-long-array-8192', RootTag((), Value(12, tuple((i * 0x9e3779b97f4a7c15) & 0xffffffffffffffff for i in range(8192)))), 'wide')
    valid('wide-list-12000', RootTag((), Value(9, (1, (Value(1, 0xa5),) * 12000))), 'wide')
    valid('wide-compound-3000', RootTag((), Value(10, tuple((text(f'k{i}'), Value(3, i)) for i in range(3000)))), 'wide')
    return cases


def official_corpus(limit=0):
    client = INSTALL / 'versions/26.3/26.3.jar'
    release = json.loads((ROOT / 'reference/release.json').read_text())
    if sha(client.read_bytes()) != release['client']['sha256']:
        raise ValueError('Pinned installed 26.3 client SHA-256 mismatch')
    cases, manifest = [], []
    with zipfile.ZipFile(client) as jar:
        names = sorted(n for n in jar.namelist() if n.startswith('data/minecraft/structure/') and n.endswith('.nbt'))
        selected = names
        if limit and limit < len(names):
            # Even spacing visits each major directory; extremes add size variation.
            sizes = []
            for n in names:
                raw = jar.read(n)
                data = gzip.decompress(raw) if raw.startswith(b'\x1f\x8b') else raw
                sizes.append((len(data), n))
            picks = {max(sizes)[1]}
            if limit > 1:
                picks.add(min(sizes)[1])
            for i in range(limit):
                if len(picks) >= limit:
                    break
                picks.add(names[(i * (len(names) - 1)) // max(1, limit - 1)])
            for name in names:
                if len(picks) >= limit:
                    break
                picks.add(name)
            selected = sorted(picks)
        for name in selected:
            raw = jar.read(name)
            data = gzip.decompress(raw) if raw.startswith(b'\x1f\x8b') else raw
            reader = Reader(data)
            value = reader.root()
            canonical = encode_root(value)
            cases.append(Case(name, data, canonical, 'official-26.3-structure'))
            manifest.append({'path': name, 'compressed_bytes': len(raw), 'bytes': len(data),
                             'stored_sha256': sha(raw), 'decoded_sha256': sha(data),
                             'canonical_sha256': sha(canonical),
                             'tag_counts': dict(sorted(reader.types.items()))})
    aggregate_types = collections.Counter()
    for record in manifest:
        aggregate_types.update(record['tag_counts'])
    return cases, {'client_sha256': release['client']['sha256'], 'available_templates': len(names),
                   'selected_templates': len(cases), 'selection_limit': limit,
                   'decompressed_bytes': sum(len(c.data) for c in cases),
                   'manifest_sha256': sha(json.dumps(manifest, sort_keys=True, separators=(',', ':')).encode()),
                   'selected_path_tree_sha256': sha(''.join(c.name + '\n' for c in cases).encode()),
                   'aggregate_tag_counts': dict(sorted(aggregate_types.items())),
                   'largest_templates': sorted(manifest, key=lambda record: record['bytes'], reverse=True)[:5],
                   'selected_paths': [c.name for c in cases] if limit else 'All data/minecraft/structure/*.nbt entries in pinned jar'}


JAVA_SOURCE = r'''import java.io.*;
import java.nio.file.*;
import java.util.*;
import net.minecraft.nbt.*;
class ReferenceNbtProbe {
  static String units(String s) {
    StringBuilder b=new StringBuilder();
    for(int i=0;i<s.length();i++) b.append(String.format("%04x",(int)s.charAt(i)));
    return b.toString();
  }
  static String clean(String s) { return s==null?"":s.replace('\t',' ').replace('\n',' ').replace('\r',' '); }
  static void probe(PrintWriter writer, String label, String mode, String h) {
    try {
      DataInputStream in=new DataInputStream(new ByteArrayInputStream(HexFormat.of().parseHex(h)));
      ByteArrayOutputStream bytes=new ByteArrayOutputStream();
      DataOutputStream out=new DataOutputStream(bytes);
      String detail="";
      if(mode.equals("utf")) {String s=in.readUTF();out.writeUTF(s);detail="units="+units(s);}
      else if(mode.equals("unnamed")) {Tag t=NbtIo.readUnnamedTag(in,NbtAccounter.unlimitedHeap());NbtIo.writeUnnamedTag(t,out);detail="tag="+t.getId();}
      else if(mode.equals("root")) {
        int id=in.readUnsignedByte();out.writeByte(id);
        if(id!=0) {String name=in.readUTF();out.writeUTF(name);Tag t=TagTypes.getType(id).load(in,NbtAccounter.unlimitedHeap());t.write(out);}
      } else {
        int id=Integer.parseInt(mode);
        Tag t=TagTypes.getType(id).load(in,NbtAccounter.unlimitedHeap());t.write(out);
        detail="tag="+t.getId();
        if(t instanceof ListTag l) detail+=" count="+l.size()+" element="+(l.isEmpty()?"empty":l.get(0).getId());
      }
      writer.println(label+"\tok\t"+HexFormat.of().formatHex(bytes.toByteArray())+"\t"+detail+"\tremaining="+in.available());
    } catch(Throwable e) {writer.println(label+"\terror\t"+e.getClass().getName()+"\t"+clean(e.getMessage()));}
  }
  public static void main(String[] args) throws Exception {
    try(BufferedReader reader=Files.newBufferedReader(Path.of(args[0]));PrintWriter writer=new PrintWriter(Files.newBufferedWriter(Path.of(args[1])))) {
      String line;
      while((line=reader.readLine())!=null) {String[] p=line.split("\t",-1);probe(writer,p[0],p[1],p[2]);}
    }
  }
}
'''


def reference_probes():
    rows, expected = [], {}
    def probe(name, mode, h, canonical=None, detail=None, remaining=0, error=None):
        rows.append((name, mode, h))
        if error:
            expected[name] = {'status': 'error', 'error_class': error}
        else:
            expected[name] = {'status': 'ok', 'canonical_hex': canonical, 'detail': detail or '', 'remaining': remaining}
    utf = [('00', '0002c080', '0000'), ('c080', '0002c080', '0000'), ('c181', '000141', '0041'),
           ('e08080', '0002c080', '0000'), ('e08081', '000101', '0001'), ('eda080', '0003eda080', 'd800'),
           ('eda0bdedb880', '0006eda0bdedb880', 'd83dde00'), ('', '0000', ''), ('41', '000141', '0041')]
    for i, (h, canonical, units) in enumerate(utf):
        probe(f'utf-valid-{i}', 'utf', f'{len(bytes.fromhex(h)):04x}' + h, canonical, 'units=' + units)
    for i, h in enumerate(['f09f9880', '80', 'c241', 'e080', 'e04180']):
        probe(f'utf-invalid-{i}', 'utf', f'{len(bytes.fromhex(h)):04x}' + h, error='java.io.UTFDataFormatException')
    probe('utf-truncated-byte-length', 'utf', '000241', error='java.io.EOFException')
    probe('utf-write-canonical-byte-overflow', 'utf', 'ffff' + '00' * 65535, error='java.io.UTFDataFormatException')
    for element in [0, 1, 10, 12, 13, 127, 128, 255]:
        probe(f'empty-list-{element}', '9', f'{element:02x}00000000', '0000000000', 'tag=9 count=0 element=empty')
    for element in [0, 1, 10, 13]:
        probe(f'negative-list-{element}', '9', f'{element:02x}ffffffff', error='net.minecraft.nbt.NbtFormatException')
    probe('missing-list-type', '9', '0000000001', error='net.minecraft.nbt.NbtFormatException')
    probe('duplicate-compound-name', '10', '0100016101010001610200', '010001610200', 'tag=10')
    probe('list-wrapper-empty-name', '9', '0a000000010100000700', '010000000107', 'tag=9 count=1 element=1')
    probe('unnamed-root-name-discarded', 'unnamed', '0100016101', '01000001', 'tag=1')
    probe('unnamed-malformed-root-name-skipped', 'unnamed', '010001ff01', '01000001', 'tag=1')
    probe('unnamed-trailing-byte-left', 'unnamed', '0a000000ff', '0a000000', 'tag=10', remaining=1)
    probe('float-negative-zero-normalized', '5', '80000000', '00000000', 'tag=5')
    probe('double-negative-zero-normalized', '6', '8000000000000000', '0000000000000000', 'tag=6')
    probe('float-raw-nan-canonicalized', '5', '7fa12345', '7fc00000', 'tag=5')
    probe('double-raw-nan-canonicalized', '6', '7ff123456789abcd', '7ff8000000000000', 'tag=6')
    for kind in (7, 11, 12):
        probe(f'negative-array-{kind}', str(kind), 'ffffffff', error='java.lang.IllegalArgumentException')
    return rows, expected


def run(command, timeout=120):
    process = subprocess.run([str(x) for x in command], cwd=ROOT, text=True, capture_output=True, timeout=timeout)
    if process.returncode:
        raise RuntimeError(f'command failed ({process.returncode}): {command}\n{process.stdout}{process.stderr}')
    return process.stdout


def verify_nbt_classes(jars, release):
    rows = []
    client = INSTALL / 'versions/26.3/26.3.jar'
    if sha(client.read_bytes()) != release['client']['sha256']:
        raise ValueError('Pinned installed client checksum mismatch')
    with zipfile.ZipFile(client) as installed, zipfile.ZipFile(jars[0]) as server:
        names = sorted(n for n in installed.namelist() if n.startswith('net/minecraft/nbt/') and n.endswith('.class'))
        for name in names:
            original, probed = installed.read(name), server.read(name)
            if original != probed:
                raise AssertionError('Installed-client / probed-server NBT class mismatch: ' + name)
            rows.append((name, sha(original)))
    report = {
        'schema': 1, 'pin': '26.3', 'kind': 'installed_client_vs_pinned_server_nbt_classes',
        'client_sha256': release['client']['sha256'], 'server_sha256': release['server_bundle']['nested_server_sha256'],
        'matching_nbt_classes': len(rows),
        'nbt_class_tree_sha256': sha(''.join(name + '\t' + h + '\n' for name, h in rows).encode()),
        'all_nbt_class_bytes_equal': True, 'class_sha256': dict(rows),
        'commands': ['python3 tools/test_nbt.py --reference-only'],
        'qualification': 'Java probes run the hash-verified bundled server and library classpath. Every net/minecraft/nbt class byte is identical to the installed pinned 26.3 client.',
    }
    (ROOT / 'evidence/nbt-reference-classes.json').write_text(json.dumps(report, indent=2) + '\n')
    return {'matching_nbt_classes': len(rows), 'nbt_class_tree_sha256': report['nbt_class_tree_sha256']}


def run_java(cases):
    BUILD.mkdir(parents=True, exist_ok=True)
    jars, release = verified_classpath()
    class_identity = verify_nbt_classes(jars, release)
    source = BUILD / 'ReferenceNbtProbe.java'
    source.write_text(JAVA_SOURCE)
    rows, expected = reference_probes()
    rows += [(f'fixture-{i}', 'root', c.data.hex()) for i, c in enumerate(cases) if c.expected is not None]
    inputs, outputs = BUILD / 'probe-inputs.tsv', BUILD / 'probe-results.tsv'
    inputs.write_text(''.join(f'{name}\t{mode}\t{h}\n' for name, mode, h in rows))
    command = [JAVA, '--class-path', ':'.join(map(str, jars)), source, inputs, outputs]
    log = run(command, timeout=600)
    (BUILD / 'probe.log').write_text(log)
    parsed = {}
    for line in outputs.read_text().splitlines():
        fields = line.split('\t')
        name, status = fields[:2]
        if status == 'ok':
            observed = {'status': status, 'canonical_hex': fields[2], 'detail': fields[3], 'remaining': int(fields[4].removeprefix('remaining='))}
        else:
            observed = {'status': status, 'error_class': fields[2], 'message': fields[3]}
        if name in parsed:
            raise AssertionError('duplicate Java probe record: ' + name)
        parsed[name] = observed
    if len(parsed) != len(rows):
        raise AssertionError('Java probe output count mismatch')
    for name, exp in expected.items():
        got = parsed[name]
        if any(got.get(k) != v for k, v in exp.items()):
            raise AssertionError(f'Java observation changed: {name}: {exp!r} != {got!r}')
    comparisons = 0
    transformed = collections.Counter()
    for i, case in enumerate(cases):
        if case.expected is None:
            continue
        observed = parsed[f'fixture-{i}']
        if observed['status'] != 'ok' or observed['remaining']:
            raise AssertionError(f'Java decoder rejected independent valid fixture {case.name}: {observed}')
        java_output = bytes.fromhex(observed['canonical_hex'])
        actual, original = parse(java_output), parse(case.data)
        if actual.name != original.name or java_semantics(actual.value) != java_semantics(original.value):
            raise AssertionError(f'Java semantic mismatch for oracle fixture {case.name}')
        if java_output != case.expected:
            transformed[case.category] += 1
        comparisons += 1
    classes = ['net.minecraft.nbt.NbtIo', 'net.minecraft.nbt.StringTag$1', 'net.minecraft.nbt.ListTag$1',
               'net.minecraft.nbt.CompoundTag$1', 'net.minecraft.nbt.ListTag', 'net.minecraft.nbt.NbtAccounter',
               'net.minecraft.nbt.FloatTag', 'net.minecraft.nbt.DoubleTag',
               'java.io.DataInputStream', 'java.io.DataOutputStream']
    bytecode = run([JAVA.parent / 'javap', '-classpath', jars[0], '-c', '-p', *classes])
    (BUILD / 'nbt-bytecode.txt').write_text(bytecode)
    report = {
        'schema': 1, 'pin': '26.3', 'kind': 'actual_java_reference_observations',
        'java_version': subprocess.run([str(JAVA), '-version'], text=True, capture_output=True, check=True).stderr.strip(),
        'server_sha256': release['server_bundle']['nested_server_sha256'],
        'client_sha256': release['client']['sha256'], 'probed_nbt_class_identity': class_identity,
        'probe_source_sha256': sha(JAVA_SOURCE.encode()),
        'javap_sha256': sha(bytecode.encode()), 'javap_classes': classes,
        'exact_observation_probes': len(expected),
        'observations': {name: parsed[name] | {'mode': mode, 'input_bytes': len(bytes.fromhex(h)),
                        'input_sha256': sha(bytes.fromhex(h))} for name, mode, h in rows if name in expected},
        'fixture_category_counts': dict(sorted(collections.Counter(c.category for c in cases).items())),
        'fixture_input_tree_sha256': sha(''.join(c.name + '\t' + sha(c.data) + '\n' for c in cases).encode()),
        'valid_fixture_semantics_compared': comparisons,
        'java_serialization_transformed_fixture_counts': dict(sorted(transformed.items())),
        'oracle_comparison': 'Root name UTF-16 units equal; decoded Java object semantics equal after observed duplicate-key replacement, list empty-name-wrapper unwrapping, empty-header erasure and IEEE NaN write canonicalization and FloatTag/DoubleTag negative-zero normalization. Bend wire bytes compared independently without these Java object transformations.',
        'boundaries': [
            'Physical Bend codec preserves named roots; NbtIo.readUnnamedTag discards root names and skips their bytes without validating modified UTF-8.',
            'Physical Bend codec preserves compound order and duplicate names; CompoundTag Map.put retains the last duplicate.',
            'Physical Bend codec preserves wire compound wrappers in lists; ListTag.addAndUnwrap unwraps a one-member compound whose name is empty.',
            'Physical Bend codec preserves known declared empty-list element IDs 0..12 and rejects unknown IDs; Java accepts any empty-list ID and writes ID 0.',
            'Physical Bend codec preserves all float/double wire bits; Java FloatTag/DoubleTag.valueOf normalize negative zero and DataOutputStream.writeFloat/writeDouble canonicalize NaNs.',
            'Physical Bend codec rejects bytes following a root; NbtIo.readUnnamedTag leaves trailing input unread.',
            'Negative list counts are rejected by actual 26.3 ListTag.readListCount; older format folklore accepting negative lengths does not describe this pin.',
        ],
        'reproduce': 'python3 tools/test_nbt.py --reference-only',
        'commands': ['python3 tools/test_nbt.py --reference-only',
                     str(JAVA.parent / 'javap') + ' -classpath reference/cache/versions/26.3/server-26.3.jar -c -p ' + ' '.join(classes)],
    }
    (ROOT / 'evidence/nbt-reference-java.json').write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
    return {'exact_observation_probes': len(expected), 'valid_fixture_semantics_compared': comparisons,
            'java_serialization_transformed_fixture_counts': dict(sorted(transformed.items())),
            'probed_nbt_class_identity': class_identity,
            'probe_source_sha256': report['probe_source_sha256'], 'javap_sha256': report['javap_sha256']}


def execute(binary, cases, *, stage):
    results, group, size = [], [], 0
    def consume(batch):
        args = [binary, '--threads', '1', 'batch', *(c.data.hex() for c in batch)]
        lines = run(args, timeout=300).splitlines()
        if len(lines) != len(batch):
            raise AssertionError(f'{stage}: native returned {len(lines)} lines for {len(batch)} cases')
        for case, line in zip(batch, lines):
            expected = None if case.expected is None else 'ok\t' + case.expected.hex()
            if expected is None:
                passed = line.startswith('error\t')
            else:
                passed = line == expected
            if not passed:
                raise AssertionError(f'{stage}: {case.name}: expected {expected[:200] if expected else "error"}, observed {line[:200]}; input bytes={len(case.data)} sha256={sha(case.data)}')
            results.append((case, line))
    for index, case in enumerate(cases):
        if len(case.data) * 2 > 80_000:
            if group:
                consume(group); group, size = [], 0
            path = BUILD / 'native-input.hex'
            path.write_text(case.data.hex())
            line = run([binary, '--threads', '1', 'file', path], timeout=600).rstrip('\n')
            expected = None if case.expected is None else 'ok\t' + case.expected.hex()
            if not (line.startswith('error\t') if expected is None else line == expected):
                raise AssertionError(f'{stage}: {case.name}: file-mode mismatch; expected {expected[:200] if expected else "error"}, observed {line[:200]}; input sha256={sha(case.data)}')
            results.append((case, line))
        else:
            if group and (len(group) >= 25 or size + len(case.data) * 2 > 180_000):
                consume(group); group, size = [], 0
            group.append(case); size += len(case.data) * 2
        if index and index % 100 == 0:
            print(f'{stage}: {index}/{len(cases)} fixtures checked', flush=True)
    if group:
        consume(group)
    return results


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--skip-build', action='store_true')
    parser.add_argument('--reference-only', action='store_true')
    parser.add_argument('--synthetic-only', action='store_true')
    parser.add_argument('--official-limit', type=int, default=0, help='0 runs all pinned templates; positive selects a recorded bounded subset')
    parser.add_argument('--skip-java', action='store_true', help='Reuse no Java comparison; records this omission explicitly')
    options = parser.parse_args()
    if options.official_limit < 0:
        parser.error('--official-limit cannot be negative')
    started = time.monotonic()
    executed_oracle_sha256 = sha(Path(__file__).read_bytes())
    BUILD.mkdir(parents=True, exist_ok=True)
    cases = synthetic_corpus()
    official, official_report = ([], {'available_templates': None, 'selected_templates': 0, 'skipped': True}) if options.synthetic_only else official_corpus(options.official_limit)
    cases += official
    java_report = {'skipped': True} if options.skip_java else run_java(cases)
    if options.reference_only:
        print(json.dumps({'synthetic_cases': len(cases) - len(official), 'official_templates': len(official), 'java': java_report}, indent=2))
        return
    binary = ROOT / 'build/nbt-tests'
    checker = {}
    for source in ('src/nbt.bend', 'tests/nbt.bend'):
        output = run([BEND, source, '--check-only'])
        if 'ALL PROOFS CHECK' not in output:
            raise AssertionError(output)
        checker[source] = output.strip()
    if not options.skip_build:
        run([BEND, 'tests/nbt.bend', '-o', binary], timeout=300)
    builtin = run([binary, '--threads', '1']).strip()
    if builtin != 'regressions\tpass':
        raise AssertionError('native built-in regressions: ' + builtin)
    results = execute(binary, cases, stage='fixtures')
    roundtrips = [Case('roundtrip-' + c.name, c.expected, c.expected, c.category) for c in cases if c.expected is not None]
    execute(binary, roundtrips, stage='roundtrips')
    pure = (ROOT / 'src/nbt.bend').read_text()
    if '@unsafe' in pure or re.search(r'\bIO[.<(]|import\s+"', pure):
        raise AssertionError('NBT implementation contains unsafe or effect-backed logic')
    kernel = {}
    for source in ('src/nbt.bend', 'tests/nbt.bend'):
        process = subprocess.run([str(BEND), source, '--verdict'], cwd=ROOT, text=True, capture_output=True, timeout=90)
        kernel[source] = {'exit_code': process.returncode, 'output': (process.stdout + process.stderr).strip()}
    report = {
        'schema': 1, 'pin': '26.3', 'compiler': run([BEND, 'version']).strip(), 'platform': platform.platform(),
        'source_sha256': sha(pure.encode()), 'harness_sha256': sha((ROOT / 'tests/nbt.bend').read_bytes()),
        'oracle_sha256': executed_oracle_sha256, 'native_run_oracle_sha256': executed_oracle_sha256,
        'current_oracle_sha256': sha(Path(__file__).read_bytes()), 'native_binary_sha256': sha(binary.read_bytes()),
        'checker': checker, 'kernel_verdict': kernel, 'native_binary': 'build/nbt-tests',
        'native_builtin_regressions': 'pass', 'independent_cases': len(cases),
        'accepted_cases': len(roundtrips), 'rejected_cases': len(cases) - len(roundtrips),
        'successful_roundtrips': len(roundtrips), 'all_cases_passed': True,
        'category_counts': dict(sorted(collections.Counter(c.category for c in cases).items())),
        'input_tree_sha256': sha(''.join(c.name + '\t' + sha(c.data) + '\n' for c in cases).encode()),
        'output_tree_sha256': sha(''.join(c.name + '\t' + sha(line.encode()) + '\n' for c, line in results).encode()),
        'elapsed_seconds': round(time.monotonic() - started, 3), 'java_reference': java_report,
        'official_corpus': official_report,
        'policy': {'input_output_bytes': DEFAULT_BYTES, 'container_depth': DEFAULT_DEPTH,
                   'elements_per_container_or_array': DEFAULT_ELEMENTS, 'unknown_tag_ids': 'reject, including empty lists',
                   'modified_utf8': 'DataInput.readUTF liberal decoding; canonical UTF-16-unit encoder',
                   'root': 'named root or single TAG_End; consume all bytes',
                   'compound': 'preserve member order and duplicates', 'list': 'preserve known declared wire element ID',
                   'float_double': 'preserve raw IEEE bits including NaN payloads'},
        'limits': ['gzip extraction executes only in reference orchestration; src/nbt.bend accepts uncompressed wire bytes.',
                   'No save migration, region files, world persistence/recovery, SNBT, list-wrapper object semantics or Java compound-map semantics are established.',
                   'Synthetic rejection fixtures cover malformed/truncated payloads and depth/element boundaries; the full 16 MiB input/output ceiling is not exhaustively exercised.'],
        'commands': ['python3 tools/test_nbt.py' + (' --synthetic-only' if options.synthetic_only else '') +
                     (f' --official-limit {options.official_limit}' if options.official_limit else '') +
                     (' --skip-build' if options.skip_build else '') + (' --skip-java' if options.skip_java else ''),
                     '/Users/chuah/.bend/bin/bend src/nbt.bend --check-only',
                     '/Users/chuah/.bend/bin/bend tests/nbt.bend --check-only',
                     '/Users/chuah/.bend/bin/bend tests/nbt.bend -o build/nbt-tests',
                     './build/nbt-tests --threads 1', './build/nbt-tests --threads 1 batch HEX...',
                     './build/nbt-tests --threads 1 file build/nbt-reference/native-input.hex',
                     '/Users/chuah/.bend/bin/bend src/nbt.bend --verdict',
                     '/Users/chuah/.bend/bin/bend tests/nbt.bend --verdict'],
    }
    target = ROOT / 'evidence/nbt-reference-tests.json'
    target.write_text(json.dumps(report, indent=2, ensure_ascii=False) + '\n')
    print(json.dumps({k: report[k] for k in ['independent_cases', 'accepted_cases', 'rejected_cases', 'successful_roundtrips', 'all_cases_passed', 'elapsed_seconds']}, indent=2))


if __name__ == '__main__':
    main()
