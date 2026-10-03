#!/usr/bin/env python3
"""Independent ZIP fixtures, actual native Bend reads, and Java ZipFile oracle."""
from __future__ import annotations
import argparse
import base64
import copy
import hashlib
import json
import random
import struct
import subprocess
import time
import zipfile
import zlib
from dataclasses import dataclass
from pathlib import Path
from reference_inventory import INSTALL, JAVA

ROOT = Path(__file__).resolve().parents[1]
BEND = Path.home() / '.bend/bin/bend'
BUILD = ROOT / 'build/archive-reference'

JAVA_SOURCE = r'''
import java.nio.file.*;
import java.nio.charset.*;
import java.util.*;
import java.util.zip.*;
public class ArchiveProbe {
  static String units(String s) {
    StringBuilder b = new StringBuilder();
    s.codePoints().forEach(c -> b.append(c).append(','));
    return b.toString();
  }
  static String bytes(ZipFile z, ZipEntry e) throws Exception {
    try(var in = z.getInputStream(e)) {
      byte[] b = in.readNBytes(33554433);
      if(b.length > 33554432) throw new Exception("oracle output limit");
      return HexFormat.of().formatHex(b);
    }
  }
  public static void main(String[] args) throws Exception {
    try(var out = Files.newBufferedWriter(Path.of(args[1]), StandardCharsets.UTF_8)) {
      for(String row : Files.readAllLines(Path.of(args[0]), StandardCharsets.UTF_8)) {
        String[] f = row.split("\t", -1);
        String id=f[0];
        try(var z = new ZipFile(f[2], Charset.forName(f[1].equals("cp437") ? "IBM437" : "UTF-8"))) {
          out.write("H\t"+id+"\t"+z.size()+"\n");
          var entries = z.entries();
          int ordinal=0;
          while(entries.hasMoreElements()) {
            ZipEntry e = entries.nextElement();
            out.write("N\t"+id+"\t"+ordinal+"\t"+units(e.getName())+"\t"+e.getMethod()+"\t"+e.getCrc()+"\t"+e.getCompressedSize()+"\t"+e.getSize()+"\n");
            if(z.size() <= 16 && f[4].equals("entries"))
              out.write("P\t"+id+"\t"+ordinal+"\t"+bytes(z,e)+"\n");
            ordinal++;
          }
          String name = new String(Base64.getDecoder().decode(f[3]), StandardCharsets.UTF_8);
          ZipEntry e = z.getEntry(name);
          if(e==null) out.write("R\t"+id+"\tMISSING\n");
          else out.write("R\t"+id+"\t"+units(e.getName())+"\t"+bytes(z,e)+"\n");
        } catch(Exception e) {
          out.write("E\t"+id+"\t"+e.getClass().getName()+"\t"+Base64.getEncoder().encodeToString(String.valueOf(e.getMessage()).getBytes(StandardCharsets.UTF_8))+"\n");
        }
      }
    }
  }
}
'''


def run(command, timeout=120):
    result = subprocess.run(list(map(str, command)), cwd=ROOT, capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        raise AssertionError((command, result.returncode, result.stdout[-5000:], result.stderr[-5000:]))
    assert not result.stderr.strip(), result.stderr
    return result.stdout


def units(text):
    return ''.join(f'{ord(c)},' for c in text)


def decode_units(text):
    return ''.join(chr(int(x)) for x in text.split(',') if x)


def raw_deflate(data, level=6, strategy=zlib.Z_DEFAULT_STRATEGY):
    compressor = zlib.compressobj(level, zlib.DEFLATED, -15, strategy=strategy)
    return compressor.compress(data) + compressor.flush()


@dataclass
class Built:
    data: bytes
    records: list
    local: list
    central: list
    eocd: int


def build(specs, comment=b'', order=None, prefix=b''):
    local, records = [], []
    data = bytearray(prefix)
    for i, original in enumerate(specs):
        spec = copy.deepcopy(original)
        name = spec['name']
        payload = spec.get('payload', b'')
        method = spec.get('method', 0)
        flags = spec.get('flags', 0)
        needed = spec.get('needed', 20)
        packed = spec.get('packed', payload if method != 8 else raw_deflate(payload, spec.get('level', 6), spec.get('strategy', zlib.Z_DEFAULT_STRATEGY)))
        crc = spec.get('crc', zlib.crc32(payload))
        size = spec.get('size', len(payload))
        csize = spec.get('csize', len(packed))
        offset = len(data)
        local.append(offset)
        local_name = spec.get('local_name', name)
        local_extra = spec.get('local_extra', spec.get('extra', b''))
        local_crc = spec.get('local_crc', 0 if flags & 8 else crc)
        local_csize = spec.get('local_csize', 0 if flags & 8 else csize)
        local_size = spec.get('local_size', 0 if flags & 8 else size)
        data.extend(struct.pack('<IHHHHHIIIHH', 0x04034b50, spec.get('local_needed', needed), spec.get('local_flags', flags),
                                spec.get('local_method', method), 0, 0, local_crc, local_csize, local_size, len(local_name), len(local_extra)))
        data.extend(local_name + local_extra + packed)
        if flags & 8:
            if spec.get('descriptor', 'signed') == 'signed': data.extend(b'PK\x07\x08')
            data.extend(struct.pack('<III', spec.get('descriptor_crc', crc), spec.get('descriptor_csize', csize), spec.get('descriptor_size', size)))
        data.extend(spec.get('gap', b''))
        records.append({'spec': spec, 'offset': offset, 'needed': needed, 'flags': flags, 'method': method, 'crc': crc,
                        'compressed': csize, 'size': size, 'name': name, 'payload': payload})
    central_offset = len(data)
    central = []
    chosen = list(range(len(specs))) if order is None else order
    ordered_records = []
    for ordinal, i in enumerate(chosen):
        record = records[i]
        spec = record['spec']
        extra = spec.get('extra', b'')
        entry_comment = spec.get('comment', b'')
        central.append(len(data))
        data.extend(struct.pack('<IHHHHHHIIIHHHHHII', 0x02014b50, 20, record['needed'], record['flags'], record['method'], 0, 0,
                                record['crc'], record['compressed'], record['size'], len(record['name']), len(extra), len(entry_comment),
                                spec.get('disk', 0), 0, spec.get('external', 0), spec.get('central_local', record['offset'])))
        data.extend(record['name'] + extra + entry_comment)
        copy_record = dict(record)
        copy_record.update(ordinal=ordinal, ceiling=local[i+1] if i+1 < len(local) else central_offset)
        ordered_records.append(copy_record)
    eocd = len(data)
    data.extend(struct.pack('<IHHHHIIH', 0x06054b50, 0, 0, len(specs), len(specs), eocd-central_offset, central_offset, len(comment)))
    data.extend(comment)
    return Built(bytes(data), ordered_records, local, central, eocd)


def patch(built, offset, fmt, value):
    data = bytearray(built.data)
    struct.pack_into(fmt, data, offset, value)
    return bytes(data)


@dataclass
class Case:
    name: str
    path: Path
    mode: str = 'read'
    charset: str = 'utf8'
    profile: str = 'default'
    query: str = 'a'
    expected: object = b''


def expected_index(built, charset='utf8'):
    result = []
    for record in built.records:
        codec = 'utf8' if record['flags'] & 2048 or charset == 'utf8' else 'cp437'
        name = record['name'].decode(codec)
        result.append(['N', str(record['ordinal']), units(name), str(record['method']), str(record['crc']),
                       str(record['compressed']), str(record['size']), str(record['offset']), str(record['ceiling']), str(record['flags'])])
    return result


def corpus():
    cases, probes = [], []
    def file(name, data):
        path = BUILD / (name + '.zip')
        path.write_bytes(data)
        return path
    def good(name, built, query='a', charset='utf8', enumerate=True):
        path = file(name, built.data)
        cases.append(Case(name+'-index', path, 'index', charset, query='' if '\x00' in query else query, expected=expected_index(built, charset)))
        decoded = [record['name'].decode('utf8' if record['flags'] & 2048 or charset=='utf8' else 'cp437') for record in built.records]
        hits = [record for record, text in zip(built.records, decoded) if text == query]
        if not hits and not query.endswith('/'):
            hits = [record for record, text in zip(built.records, decoded) if text == query+'/']
        expected = hits[-1]['payload'] if hits else 'MissingEntry'
        if '\x00' not in query:
            cases.append(Case(name+'-read', path, charset=charset, query=query, expected=expected))
        probes.append((name, charset, path, query, 'entries' if enumerate else 'names', built, expected))
        return path
    def bad(name, data, code, mode='read', profile='default', charset='utf8', query='a'):
        cases.append(Case(name, file(name, data), mode, charset, profile, query, code))

    good('empty', build([]), query='missing')
    good('stored', build([{'name': b'a', 'payload': b'hello\x00\xff'}]))
    good('deflate-dynamic', build([{'name': b'a', 'payload': b'resource/data'*400, 'method': 8}]))
    good('deflate-fixed', build([{'name': b'a', 'payload': bytes(range(256))*4, 'method': 8, 'strategy': zlib.Z_FIXED}]))
    good('deflate-stored-blocks', build([{'name': b'a', 'payload': bytes(range(256))*4, 'method': 8, 'level': 0}]))
    good('descriptor-signed', build([{'name': b'a', 'payload': b'desc'*99, 'method': 8, 'flags': 2056}]))
    good('descriptor-unsigned', build([{'name': b'a', 'payload': b'desc'*99, 'method': 8, 'flags': 8, 'descriptor': 'unsigned'}]))
    good('descriptor-stored', build([{'name': b'a', 'payload': b'stored descriptor', 'flags': 8}]))
    good('descriptor-patched-local', build([{'name': b'a', 'payload': b'x'*80, 'method': 8, 'flags': 8,
                                          'local_crc': zlib.crc32(b'x'*80), 'local_csize': len(raw_deflate(b'x'*80)), 'local_size': 80}]))
    good('unicode-flag', build([{'name': '资源/é😀.json'.encode(), 'payload': b'utf8', 'flags': 2048}]), query='资源/é😀.json')
    good('utf8-default-without-flag', build([{'name': 'é.txt'.encode(), 'payload': b'java fallback'}]), query='é.txt')
    good('cp437-explicit', build([{'name': b'\x82.txt', 'payload': b'cp437'}]), charset='cp437', query='é.txt')
    good('cp437-bit11-overrides', build([{'name': '资源/é😀.json'.encode(), 'payload': b'flag overrides fallback', 'flags': 2048}]), charset='cp437', query='资源/é😀.json')
    good('cp437-every-high-byte', build([{'name': bytes(range(128,256)), 'payload': b'all high codepoints'}]), charset='cp437', query=bytes(range(128,256)).decode('cp437'))
    good('virtual-names', build([{'name': name, 'payload': name} for name in [b'../a', b'/absolute', b'A', b'a', b'x\\y', b'x/./y', b'x//y', b'dir/']]), query='../a')
    good('directory-fallback', build([{'name': b'dir/', 'payload': b''}]), query='dir')
    duplicate = build([{'name': b'a', 'payload': b'first'}, {'name': b'a', 'payload': b'last'}])
    dup_path = good('duplicate-last-wins', duplicate)
    cases.extend([Case('duplicate-ordinal-first', dup_path, 'ordinal', query='0', expected=b'first'),
                  Case('duplicate-ordinal-last', dup_path, 'ordinal', query='1', expected=b'last')])
    reordered = build([{'name': b'z', 'payload': b'z'}, {'name': b'a', 'payload': b'a'}, {'name': b'm', 'payload': b'm'}], order=[2,0,1])
    good('central-order', reordered, query='m')
    good('prefix-absolute-offsets', build([{'name': b'a', 'payload': b'prefix'}], prefix=b'arbitrary-prefix-PK\x03\x04'))
    comments = b'zero\x00\xffPK\x05\x06' + b'\x00'*30 + b'PK\x03\x04PK\x01\x02PK\x06\x06' + b'\x07'*40
    good('comment-signatures', build([{'name': b'a', 'payload': b'comments', 'comment': comments.replace(b'\xff', b'?')}], comment=comments))
    good('maximum-comment', build([{'name': b'a', 'payload': b'max comment'}], comment=(b'PK\x05\x06'+bytes(range(256)))*252 + b'x'*(65535-260*252)))
    extra = struct.pack('<HH', 0xcafe, 8) + b'PK\x03\x04PK\x05\x06'
    good('unknown-extra', build([{'name': b'a', 'payload': b'extra', 'extra': extra}]))
    unicode_extra = struct.pack('<HHBI', 0x7075, 1+4+len(b'other'), 1, zlib.crc32(b'a')) + b'other'
    good('unicode-path-extra-java-ignored', build([{'name': b'a', 'payload': b'central raw name', 'extra': unicode_extra}]))
    good('maximum-entry-comment', build([{'name': b'a', 'payload': b'max entry comment', 'comment': b'x'*65488}]))
    good('cp437-entry-comment', build([{'name': b'a', 'payload': b'cp437 comment', 'comment': b'\x82'}]), charset='cp437')
    good('empty-name', build([{'name': b'', 'payload': b'empty name'}]), query='')
    good('nul-name', build([{'name': b'a\x00b', 'payload': b'nul'}]), query='a\x00b')

    rng = random.Random(8259)
    for i in range(100):
        specs = []
        for j in range(rng.randrange(1, 7)):
            method = rng.choice([0,8])
            flags = rng.choice([0,2048,8,2056])
            data = rng.randbytes(rng.randrange(0, 500)) if i%2 else bytes([j])*rng.randrange(0, 1600)
            specs.append({'name': f'ns:resource/{i}/{j}.bin'.encode(), 'payload': data, 'method': method, 'flags': flags,
                          'descriptor': rng.choice(['signed','unsigned']), 'gap': rng.randbytes(rng.randrange(0,4))})
        order = list(range(len(specs)))
        rng.shuffle(order)
        good(f'generated-{i}', build(specs, order=order), query=specs[rng.randrange(len(specs))]['name'].decode(), enumerate=False)

    base = build([{'name': b'a', 'payload': b'abcdef'}, {'name': b'b', 'payload': b'ghijkl'}])
    c, e = base.central[0], base.eocd
    for length in [0,1,3,10,21]: bad(f'truncated-eocd-{length}', base.data[:-22]+base.data[-22:][:length], 'MissingEOCD')
    bad('trailing-file-bytes', base.data+b'junk', 'MissingEOCD')
    for field in [4,6]: bad('multidisk-'+str(field), patch(base,e+field,'<H',1), 'UnsupportedMultiDisk')
    bad('split-entry-count', patch(base,e+8,'<H',1), 'UnsupportedMultiDisk')
    for field, fmt, value in [(10,'<H',65535),(12,'<I',0xffffffff),(16,'<I',0xffffffff)]:
        bad('zip64-sentinel-'+str(field), patch(base,e+field,fmt,value), 'UnsupportedZIP64')
    locator = struct.pack('<IIQI', 0x07064b50, 0, base.eocd, 1)
    bad('zip64-locator-without-sentinel', base.data[:e]+locator+base.data[e:], 'UnsupportedZIP64')
    bad('central-signature', patch(base,c,'<I',0), 'CentralSignature')
    bad('central-too-many-entries', patch(base,e+8,'<I',0x00030003), 'Truncated')
    bad('central-too-few-entries', patch(base,e+8,'<I',0x00010001), 'CentralSize')
    bad('entry-on-other-disk', patch(base,c+34,'<H',1), 'UnsupportedMultiDisk')
    for field in [20,24,42]: bad('entry-zip64-sentinel-'+str(field), patch(base,c+field,'<I',0xffffffff), 'UnsupportedZIP64')
    bad('entry-overlaps-next', patch(base,c+42,'<I',base.local[1]), 'LocalOverlap')
    bad('entry-outside-file', patch(base,c+42,'<I',0xffffff00), 'LocalOverlap')
    bad('entry-overflows-ceiling', patch(base,c+20,'<I',999), 'StoredSizeMismatch')
    for flag in [1,64,8192]: bad('encrypted-'+str(flag), build([{'name':b'a','payload':b'x','flags':flag}]).data, 'UnsupportedEncryption')
    for flag in [16,32,128,256,512,1024,4096,16384,32768]:
        bad('unsupported-flags-'+str(flag), build([{'name':b'a','payload':b'x','flags':flag}]).data, 'UnsupportedFlags')
    bad('stored-speed-flags', build([{'name':b'a','payload':b'x','flags':2}]).data, 'UnsupportedFlags')
    for method in [1,9,12,99]: bad('unsupported-method-'+str(method), build([{'name':b'a','payload':b'x','method':method}]).data, 'UnsupportedMethod')
    bad('unsupported-needed-version', build([{'name':b'a','payload':b'x','needed':45}]).data, 'UnsupportedVersion')
    bad('zip64-extra', build([{'name':b'a','payload':b'x','extra':b'\x01\x00\x00\x00'}]).data, 'UnsupportedZIP64')
    bad('central-extra-truncated-header', build([{'name':b'a','payload':b'x','extra':b'\xff\xca'}]).data, 'TruncatedExtra')
    bad('central-extra-truncated-body', build([{'name':b'a','payload':b'x','extra':b'\xff\xca\x08\x00x'}]).data, 'Truncated')
    for name, raw in [('continuation',b'\x80'),('overlong',b'\xc0\xba'),('surrogate',b'\xed\xa0\x80'),('range',b'\xf4\x90\x80\x80'),('truncated',b'\xe2')]:
        bad('name-utf8-'+name, build([{'name':raw,'payload':b'x','flags':2048}]).data, 'InvalidNameUTF8', charset='cp437')
    bad('cp437-default-is-not-java', build([{'name':b'\x82.txt','payload':b'x'}]).data, 'InvalidNameUTF8')
    bad('comment-header-size-boundary', build([{'name':b'a','payload':b'x','comment':b'x'*65489}]).data, 'CentralRecordLimit')
    bad('comment-invalid-utf8-default', build([{'name':b'a','payload':b'x','comment':b'\x82'}]).data, 'InvalidCommentUTF8')
    bad('comment-bit11-overrides-cp437', build([{'name':b'a','payload':b'x','comment':b'\x82','flags':2048}]).data, 'InvalidCommentUTF8', charset='cp437')
    bad('comment-truncated-utf8', build([{'name':b'a','payload':b'x','comment':b'\xe2'}]).data, 'InvalidCommentUTF8')
    bad('stored-size-mismatch', build([{'name':b'a','payload':b'x','size':2}]).data, 'StoredSizeMismatch')
    bad('local-signature', patch(base,0,'<I',0), 'LocalSignature')
    for field in [4,6,8]: bad('local-metadata-'+str(field), patch(base,field,'<H',999), 'LocalMetadataMismatch')
    for field in [14,18,22]: bad('local-crc-size-'+str(field), patch(base,field,'<I',0), 'LocalSizeMismatch')
    bad('local-name-mismatch', build([{'name':b'a','local_name':b'z','payload':b'x'}]).data, 'LocalNameMismatch')
    bad('local-extra-overlap', patch(base,28,'<H',65535), 'LocalOverlap')
    bad('local-name-overlap', patch(base,26,'<H',4097), 'EntryLimit')
    bad('local-zip64-extra', build([{'name':b'a','payload':b'x','local_extra':b'\x01\x00\x00\x00'}]).data, 'UnsupportedZIP64')
    bad('local-extra-truncated', build([{'name':b'a','payload':b'x','local_extra':b'\x34\x12'}]).data, 'TruncatedExtra')
    bad('stored-wrong-crc', build([{'name':b'a','payload':b'x','crc':0}]).data, 'CRCMismatch')
    bad('deflate-wrong-crc', build([{'name':b'a','payload':b'x','method':8,'crc':0}]).data, 'CRCMismatch')
    bad('deflate-invalid-block', build([{'name':b'a','payload':b'x','method':8,'packed':b'\x07'}]).data, 'DeflateError')
    bad('deflate-extra-compressed-byte', build([{'name':b'a','payload':b'x','method':8,'packed':raw_deflate(b'x')+b'\x00'}]).data, 'DeflateError')
    bad('deflate-output-longer-declared', build([{'name':b'a','payload':b'x'*1000,'method':8,'size':0}]).data, 'DeflateError')
    bad('deflate-output-shorter-declared', build([{'name':b'a','payload':b'x'*1000,'method':8,'size':1001}]).data, 'OutputSizeMismatch')
    for field in ['crc','csize','size']:
        bad('descriptor-wrong-'+field, build([{'name':b'a','payload':b'x','method':8,'flags':8,'descriptor_'+field:999}]).data, 'DescriptorMismatch')
    bad('descriptor-local-contradiction', build([{'name':b'a','payload':b'x','method':8,'flags':8,'local_crc':999}]).data, 'LocalSizeMismatch')
    for profile, code in [('tiny-file','FileLimit'),('tiny-index','IndexLimit'),('tiny-entries','IndexLimit'),('tiny-name','EntryLimit'),
                          ('tiny-compressed','EntryLimit'),('tiny-output','EntryLimit'),('bad-limits','InvalidLimits')]:
        bad('limit-'+profile, base.data if profile!='tiny-name' else build([{'name':b'long-name','payload':b'x'}]).data, code, profile=profile)
    cases.append(Case('missing-file', BUILD/'does-not-exist.zip', expected='FileIO'))
    return cases, probes


def native_cases(binary, cases):
    for index in range(0, len(cases), 12):
        group = cases[index:index+12]
        command = [binary, '--threads', '1', '--gpu', 'off', 'batch']
        for case in group: command.extend([case.mode, case.charset, case.profile, case.path, case.query])
        blocks = run(command).split('END\n')
        assert len(blocks) == len(group)+1 and blocks[-1]=='', (index,len(blocks),len(group))
        for case, block in zip(group, blocks):
            rows = [line.split('\t') for line in block.splitlines()]
            if isinstance(case.expected, bytes):
                assert len(rows)==1 and rows[0][0]=='D', (case.name,rows)
                assert bytes.fromhex(rows[0][1]) == case.expected, case.name
            elif isinstance(case.expected, list):
                assert rows==case.expected, (case.name,rows,case.expected)
            else:
                assert len(rows)==1 and rows[0][0]=='E' and rows[0][1]==case.expected, (case.name,rows,case.expected)


def java_oracle(probes, pinned):
    source = BUILD/'ArchiveProbe.java'
    source.write_text(JAVA_SOURCE)
    inputs, outputs = BUILD/'java-input.tsv', BUILD/'java-output.tsv'
    rows = [(name, charset, path, query, mode) for name,charset,path,query,mode,built,expected in probes]
    rows.append(('pinned-26.3', 'utf8', pinned, 'version.json', 'names'))
    inputs.write_text(''.join('\t'.join([name,charset,str(path),base64.b64encode(query.encode()).decode(),mode])+'\n'
                              for name,charset,path,query,mode in rows))
    run([JAVA, source, inputs, outputs], timeout=300)
    parsed = {}
    for line in outputs.read_text().splitlines():
        f=line.split('\t'); item=parsed.setdefault(f[1],{'entries':[], 'payloads':{}})
        if f[0]=='H': item['count']=int(f[2])
        elif f[0]=='N': item['entries'].append(f[2:])
        elif f[0]=='P': item['payloads'][int(f[2])]=bytes.fromhex(f[3])
        elif f[0]=='R': item['lookup']=None if f[2]=='MISSING' else (decode_units(f[2]),bytes.fromhex(f[3]))
        elif f[0]=='E': item['error']={'class':f[2],'message':base64.b64decode(f[3]).decode()}
    for name,charset,path,query,mode,built,expected in probes:
        got=parsed[name]
        assert 'error' not in got, (name,got.get('error'))
        wanted=[row[1:7] for row in expected_index(built,charset)]
        assert got['entries']==wanted and got['count']==len(wanted), (name,got,wanted)
        if isinstance(expected,bytes): assert got['lookup'][1]==expected, (name,got['lookup'],expected)
        else: assert got['lookup'] is None, (name,got)
    return parsed


def main():
    parser=argparse.ArgumentParser(); parser.add_argument('--skip-build',action='store_true'); options=parser.parse_args()
    start=time.monotonic(); BUILD.mkdir(parents=True,exist_ok=True)
    binary=ROOT/'build/archive-tests'
    checker={}
    for source in ['src/archive.bend','tests/archive.bend']:
        checker[source]=run([BEND,source,'--check-only']).strip()
        assert 'ALL PROOFS CHECK' in checker[source]
    if not options.skip_build: run([BEND,'tests/archive.bend','-o',binary],timeout=180)
    assert run([binary,'--threads','1']).strip()=='fixtures pass'
    cases,probes=corpus()
    native_cases(binary,cases)
    pinned=INSTALL/'versions/26.3/26.3.jar'
    raw=pinned.read_bytes(); sha1=hashlib.sha1(raw).hexdigest(); sha256=hashlib.sha256(raw).hexdigest()
    assert len(raw)==41483720 and sha1=='e877b6a07acd633fb3bb475002175cec036e7b87' and sha256=='4508d006323f24fa02876310c192d739af56516eb259000ac50f0909a68c9a2d'
    java=java_oracle(probes,pinned)
    assert java['duplicate-last-wins']['payloads']=={0:b'first',1:b'last'}
    jar_rows=[line.split('\t') for line in run([binary,'--threads','1','--gpu','off','index','utf8','default',pinned,''],timeout=300).splitlines()]
    assert len(jar_rows)==34227 and [row[1:7] for row in jar_rows]==java['pinned-26.3']['entries']
    queries=['version.json','assets/minecraft/lang/en_us.json','pack.png','data/minecraft/tags/block/mineable/axe.json','not/an/entry','version.json']
    with zipfile.ZipFile(pinned) as z:
        wanted=[z.read(name) if name in z.namelist() else None for name in queries]
        infos=z.infolist()
        for row,info in zip(jar_rows,infos):
            assert decode_units(row[2])==info.filename and list(map(int,row[3:8]))==[info.compress_type,info.CRC,info.compress_size,info.file_size,info.header_offset]
    output=run([binary,'--threads','1','--gpu','off','read-many','utf8','default',pinned,*queries],timeout=300).splitlines()
    assert len(output)==len(queries)
    reads=[]
    for name,expected,line in zip(queries,wanted,output):
        f=line.split('\t')
        if expected is None: assert f[0:2]==['E','MissingEntry'],f
        else:
            assert f[0]=='D' and bytes.fromhex(f[1])==expected,name
            reads.append({'name':name,'bytes':len(expected),'sha256':hashlib.sha256(expected).hexdigest()})
    assert java['pinned-26.3']['lookup'][1]==wanted[0]
    verdict={}
    for source in ['src/archive.bend','tests/archive.bend']:
        try:
            result=subprocess.run([str(BEND),source,'--verdict'],cwd=ROOT,capture_output=True,text=True,timeout=120)
            verdict[source]={'status':'completed','exit_code':result.returncode,'output':(result.stdout+result.stderr).strip()}
        except subprocess.TimeoutExpired as error:
            partial=(error.stdout or b'')+(error.stderr or b'')
            verdict[source]={'status':'timed-out','timeout_seconds':120,'exit_code':None,'output':partial.decode(errors='replace') if isinstance(partial,bytes) else partial}

    files=['src/archive.bend','tests/archive.bend','tools/test_archive.py','docs/ARCHIVE.md','src/compression.bend','src/framing.bend']
    invocation='python3 tools/test_archive.py'+(' --skip-build' if options.skip_build else '')
    report={'schema':1,'status':'passed','verification_scope':'native and independent Java/Python comparisons; kernel outcomes recorded separately',
            'command':invocation,'build_command':f'{BEND} tests/archive.bend -o build/archive-tests','build_reused':options.skip_build,
            'compiler':run([BEND,'version']).strip(),
            'commands':[invocation, f'{BEND} tests/archive.bend -o build/archive-tests',
                        f'{BEND} src/archive.bend --check-only', f'{BEND} tests/archive.bend --check-only',
                        f'{BEND} src/archive.bend --verdict', f'{BEND} tests/archive.bend --verdict (120-second limit)',
                        f'{JAVA} build/archive-reference/ArchiveProbe.java build/archive-reference/java-input.tsv build/archive-reference/java-output.tsv'],
            'native_cases':len(cases),'generated_archives':100,
            'java_valid_archives':len(probes),'java_runtime':subprocess.run([str(JAVA),'-version'],capture_output=True,text=True).stderr.strip(),
            'java_observations':{name:{key:java[name][key] for key in ['count','lookup'] if key in java[name]} for name in ['duplicate-last-wins','directory-fallback','unicode-path-extra-java-ignored','nul-name']},
            'pinned_jar':{'path':str(pinned),'bytes':len(raw),'sha1':sha1,'sha256':sha256,'entries':len(jar_rows),'all_central_entries_match_java_and_python':True},
            'entry_reads':reads,'missing_entry_preserves_handle':True,'duplicate_enumerated_payloads':['first','last'],'checker':checker,'kernel_verdicts':verdict,
            'finite_laws':2,'general_laws':['empty byte list equality agrees with list emptiness'],
            'source_sha256':{name:hashlib.sha256((ROOT/name).read_bytes()).hexdigest() for name in files},
            'native_binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),
            'elapsed_seconds':round(time.monotonic()-start,3),
            'limits':'Classic single-disk stored/deflate ZIP only. Index validates central/minimum spans; each requested entry validates actual local span/descriptor/output/CRC. No filesystem extraction, pack stack or resource semantic processing.'}
    # Byte data is compared exactly above; evidence keeps only small summaries.
    for item in report['java_observations'].values():
        if item.get('lookup'):
            name,data=item['lookup']; item['lookup']={'name':name,'bytes':len(data),'sha256':hashlib.sha256(data).hexdigest()}
    (ROOT/'evidence/archive-tests.json').write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n')
    print(json.dumps({key:report[key] for key in ['status','native_cases','java_valid_archives','elapsed_seconds']}))


if __name__=='__main__': main()
