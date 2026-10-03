#!/usr/bin/env python3
"""Compare owner-retaining exact Bend locomotion with direct Java observations."""
from __future__ import annotations
import argparse, collections, hashlib, json, pathlib, re, struct, time
from test_geometry import run, words, word_vector, verify_fixture_provenance, sha
from reference_inventory import JAVA, fingerprint
from reference_block_probe import verified_classpath

ROOT=pathlib.Path(__file__).resolve().parents[1]
BEND=pathlib.Path('/Users/chuah/.bend/bin/bend')
BINARY=ROOT/'build/locomotion-tests'
TABLE=ROOT/'generated/reference_mth_sin.f32'
FIXTURE=ROOT/'reference/locomotion.json'

def request(c,operation=None):
    v=c['input'];op=operation or c['operation']
    fields=[c['id'],op]
    if op in {'sin','cos','sin_index','cos_index'}:fields+=words(v['angle'])
    else:
        fields+=word_vector(v['vector'])
        if op=='input':fields += [str(int(v['acceleration_f32_bits'],16)),str(int(v['yaw_f32_bits'],16))]
    return '|'.join(fields)

def parse(line):
    id,kind,*fields=line.split('|')
    if kind=='f32':assert len(fields)==1;return id,{'f32_bits':f'{int(fields[0]):08x}'}
    if kind=='index':assert len(fields)==1;return id,{'index':int(fields[0])}
    assert kind=='vector' and len(fields)==6
    return id,{'vector':[f'{int(fields[i]):08x}{int(fields[i+1]):08x}' for i in range(0,6,2)]}

def main():
    p=argparse.ArgumentParser();p.add_argument('--skip-build',action='store_true');a=p.parse_args()
    fixture=json.loads(FIXTURE.read_text());provenance=verify_fixture_provenance(fixture)
    assert fingerprint(TABLE)==fixture['table']['file']
    jars,_=verified_classpath();assert [fingerprint(x) for x in jars[1:]]==fixture['classpath_libraries']
    assert fingerprint(JAVA)==fixture['runtime_executable']
    checks=[]
    for source in ['src/locomotion.bend','tests/locomotion.bend']:
        checks.append(run([BEND,source,'--check-only']));checks.append(run([BEND,source,'--verdict']))
    builds=[]
    if not a.skip_build:
        builds.append(run([BEND,'tests/locomotion.bend','-o','build/locomotion-tests.c']))
        builds.append(run([BEND,'tests/locomotion.bend','-o',BINARY]))
    counts=collections.Counter();tags=collections.Counter();native=[];start=time.monotonic();names=set()
    for offset in range(0,len(fixture['cases']),1000):
        chunk=fixture['cases'][offset:offset+1000];r=run([BINARY,'--gpu','off',TABLE,*map(request,chunk)])
        lines=r['stdout'].splitlines();assert len(lines)==len(chunk),(offset,lines,r['stderr'])
        native.append({'offset':offset,'cases':len(chunk),'seconds':r['seconds'],'exit_code':r['exit_code']})
        for c,line in zip(chunk,lines,strict=True):
            id,answer=parse(line);assert id==c['id'] and id not in names;names.add(id)
            assert answer==c['expected'],(id,c['expected'],answer)
            counts[c['operation']]+=1;tags.update(c['tags'])
    indices=[c for c in fixture['cases'] if c['operation'] in {'sin','cos'}]
    for offset in range(0,len(indices),1000):
        chunk=indices[offset:offset+1000]
        r=run([BINARY,'--gpu','off',TABLE,*[request(c,c['operation']+'_index') for c in chunk]])
        assert len(r['stdout'].splitlines())==len(chunk)
        for c,line in zip(chunk,r['stdout'].splitlines(),strict=True):
            id,answer=parse(line);assert id==c['id'] and answer=={'index':c['observation']['index']},(id,answer,c['observation'])
    # Complete array decoding and two owner-retaining traversals, not a sampled table check.
    r=run([BINARY,'--gpu','off',TABLE,'table_all','table_all'])
    lines=r['stdout'].splitlines();expected=struct.unpack('<65536I',TABLE.read_bytes());assert len(lines)==131072
    for i,line in enumerate(lines):
        label,index,word=line.split('|');assert label=='table' and int(index)==i%65536 and int(word)==expected[i%65536]
    hash_checks=[]
    r=run([BINARY,'--gpu','off',TABLE,'sha-zero|sha|0','sha-ones|sha|1','sha-cycle|sha|2'])
    messages=[bytes(262144),b'\xff'*262144,bytes(range(256))*1024]
    assert len(r['stdout'].splitlines())==3
    for message,line in zip(messages,r['stdout'].splitlines(),strict=True):
        id,kind,*fields=line.split('|');assert kind=='digest' and len(fields)==8
        digest=''.join(f'{int(word):08x}' for word in fields);assert digest==hashlib.sha256(message).hexdigest()
        hash_checks.append({'case':id,'bytes':len(message),'sha256':digest})
    invalid_bytes=[]
    inputs=[(0,256),(12345,4294967295),(262143,256),(17,255)]
    r=run([BINARY,'--gpu','off',TABLE,*[f'byte-{i}|invalid_byte|{index}|{value}' for i,(index,value) in enumerate(inputs)]])
    assert len(r['stdout'].splitlines())==len(inputs)
    for (index,value),line in zip(inputs,r['stdout'].splitlines(),strict=True):
        expected_error=f'byte|{index}|{value}' if value>255 else 'hash'
        assert line.endswith('|decode_error|'+expected_error),(line,expected_error)
        invalid_bytes.append({'index':index,'value':value,'rejected':True,'error':expected_error})
    errors=[];raw=TABLE.read_bytes();directory=ROOT/'build/locomotion-invalid';directory.mkdir(exist_ok=True)
    corrupt=bytearray(raw);corrupt[12345]^=1
    swapped=b''.join(raw[i:i+4][::-1] for i in range(0,len(raw),4))
    for label,data,message in [('empty',b'','length|0'),('truncated',raw[:-1],'length|262143'),('extra',raw+b'\0','length|262145'),('oversize',raw+b'\0'*64,'length|262145'),('corrupted',bytes(corrupt),'hash'),('wrong_endian',swapped,'hash')]:
        path=directory/(label+'.f32');path.write_bytes(data)
        r=run([BINARY,'--gpu','off',path],required=False);assert r['exit_code']==3 and 'invalid locomotion table|'+message in r['stderr'],(label,r)
        errors.append({'case':label,'exit_code':r['exit_code'],'stderr':r['stderr'],'seconds':r['seconds']})
    r=run([BINARY,'--gpu','off',directory/'missing.f32'],required=False);assert r['exit_code']==3 and 'table|read|' in r['stderr'];errors.append({'case':'missing','exit_code':r['exit_code'],'stderr':r['stderr']})
    malformed=[]
    for text in ['broken','broken|input|0','bad|sin|not-a-number|0','bad|unknown|0|0']:
        r=run([BINARY,'--gpu','off',TABLE,text],required=False);assert r['exit_code']==2 and 'invalid locomotion' in r['stderr'];malformed.append({'exit_code':r['exit_code'],'stderr':r['stderr']})
    source=(ROOT/'src/locomotion.bend').read_text();assert not re.search(r'@unsafe|\bimport\s+["\']|\w!\(',source)
    assert not re.search(r'F32\.(?:sin|cos|sqrt|div|add|sub)',source)
    assert source.count('F32.mul(')==1
    c_path=ROOT/'build/locomotion-tests.c';c_text=c_path.read_text();helpers=re.findall(r'INLINE Term spin_\d+\([^)]*\) \{.*?\n\}',c_text,re.S)
    host_float=[body for body in helpers if re.search(r'\b(?:double|float|f32|F32_BIN|F32_PRM)\b',body)]
    # The sole permitted numerical primitive is Java's explicit float yaw multiply.
    assert all('F32_BIN' in body and not re.search(r'\b(?:double|float)\b',body) for body in host_float)
    emitted_float_operations=[list(m) for m in re.findall(r'f32_rewrap\(f32_unbox\(([^)]+)\)\s*([+*/-])\s*f32_unbox\(([^)]+)\)\)',c_text) if m[0].startswith('_')]
    assert len(emitted_float_operations)==1 and emitted_float_operations[0][1:]==['*','1016003125ull'],emitted_float_operations
    sources=['src/locomotion.bend','tests/locomotion.bend','tools/reference_locomotion_probe.py','tools/test_locomotion.py','src/f64.bend','src/movement.bend','docs/LOCOMOTION.md']
    evidence={'schema_version':1,'status':'passed','pin':'26.3','fixture_sha256':sha(FIXTURE),'fixture_provenance':provenance,'table':fingerprint(TABLE),'checks':checks,'builds':builds,'native_batches':native,
              'java_case_count':len(names),'operation_counts':dict(counts),'tag_counts':dict(tags),'exact_index_comparisons':len(indices),'owned_table_entry_comparisons':len(lines),'table_traversals':2,
              'kernel_pass':True,'laws':re.findall(r'^law (\w+):',source,re.M),'strict_loader_failures':errors,'invalid_in_memory_bytes':invalid_bytes,'independent_fixed_length_sha256_checks':hash_checks,'malformed_protocol':malformed,'native_validation_seconds':round(time.monotonic()-start,6),
              'sources_sha256':{x:sha(ROOT/x) for x in sources if (ROOT/x).exists()},'binary_sha256':sha(BINARY),'emitted_c_bytes':len(c_text.encode()),'emitted_c_sha256':sha(c_path),'host_float_scalar_helpers':len(host_float),'emitted_simulation_float_operations':emitted_float_operations,'allowed_host_float_arithmetic':'one explicit binary32 yaw multiply; all binary64 arithmetic and table indexing are pure exact integers',
              'oracle_scope':fixture['scope'],'confidence':fixture['confidence'],'unsupported':['LivingEntity.travel','Player tick/aiStep','walking/gravity integration','attributes/effects','swimming/flight/climb','entity controllers']}
    (ROOT/'evidence/locomotion-verification.json').write_text(json.dumps(evidence,indent=2,sort_keys=True)+'\n')
    print(json.dumps({k:evidence[k] for k in ['status','java_case_count','operation_counts','exact_index_comparisons','owned_table_entry_comparisons','kernel_pass','native_validation_seconds','confidence']},indent=2))
if __name__=='__main__':main()
