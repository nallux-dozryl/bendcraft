#!/usr/bin/env python3
"""Native hook comparisons against untouched actual 26.3 receivers.

Python serializes observations. Decisive minor/backoff expectations are direct
actual calls; a separately labelled integer/Fraction audit checks numeric nodes.
"""
from __future__ import annotations
import argparse, copy, json, math, os, re, signal, struct, subprocess, time
from fractions import Fraction
from pathlib import Path
from reference_inventory import fingerprint
from test_geometry import run, sha, word_vector

ROOT=Path(__file__).resolve().parents[1]
BEND=Path('/Users/chuah/.bend/bin/bend')
BINARY=ROOT/'build/local-collision-tests'
TABLE=ROOT/'generated/reference_mth_sin.f32'
FIXTURE=ROOT/'reference/local_collision.json'
SOURCES=['src/local_collision.bend','tests/local_collision.bend','src/f64.bend',
         'src/geometry.bend','src/movement.bend','src/locomotion.bend','src/player_input.bend']

def source_hashes(): return {p:sha(ROOT/p) for p in SOURCES}

def bounded_check(kind, timeout):
    before = source_hashes()
    argv = ([str(BEND), 'tests/local_collision.bend', '-o', str(BINARY)] if kind == 'build'
            else [str(BEND), 'tests/local_collision.bend', '--verdict'])
    started = time.monotonic()
    process = subprocess.Popen(argv, cwd=ROOT, text=True, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, start_new_session=True)
    print(json.dumps({'job': kind, 'pid': process.pid, 'timeout_seconds': timeout}), flush=True)
    timed_out = False
    samples = []
    while True:
        remaining = timeout - (time.monotonic() - started)
        if remaining <= 0:
            timed_out = True
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                stdout, stderr = process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                stdout, stderr = process.communicate()
            break
        try:
            stdout, stderr = process.communicate(timeout=min(5, remaining))
            break
        except subprocess.TimeoutExpired:
            sample = subprocess.run(['ps', '-ax', '-o', 'pid=,pgid=,rss=,vsz=,etime='],
                                    capture_output=True, text=True, check=True)
            rows = []
            for line in sample.stdout.splitlines():
                fields = line.split()
                if len(fields) == 5 and int(fields[1]) == process.pid:
                    rows.append({'pid': int(fields[0]), 'rss_kib': int(fields[2]),
                                 'virtual_kib': int(fields[3]), 'elapsed': fields[4]})
            samples.append({'seconds': round(time.monotonic()-started, 6), 'processes': rows})
    record = {'status': 'passed' if process.returncode == 0 and not timed_out else 'inconclusive' if timed_out else 'failed',
              'command': argv, 'pid': process.pid, 'exit_code': process.returncode,
              'seconds': round(time.monotonic()-started, 6), 'timeout_seconds': timeout,
              'timed_out': timed_out, 'stdout': stdout, 'stderr': stderr,
              'memory_samples': samples,
              'memory_sample_scope': 'Process-group RSS/virtual sizes sampled every 5 seconds only while unexpectedly slow; RSS is not physical footprint or a game benchmark',
              'source_sha256': before, 'source_hashes_unchanged': source_hashes() == before,
              'compiler': fingerprint(BEND),
              'version_probe': run([BEND, 'version'])}
    if kind == 'build' and record['status'] == 'passed':
        record['binary'] = fingerprint(BINARY)
    (ROOT / f'evidence/local-collision-{kind}-final.json').write_text(json.dumps(record, sort_keys=True, indent=2)+'\n')
    assert record['status'] == 'passed' and record['source_hashes_unchanged'], record
    return record


def completed(kind):
    record = json.loads((ROOT / f'evidence/local-collision-{kind}-final.json').read_text())
    assert record['status'] == 'passed' and record['exit_code'] == 0 and record['source_hashes_unchanged']
    assert source_hashes() == record['source_sha256'], kind
    if kind == 'build':
        assert record['binary'] == fingerprint(BINARY)
    return record


def words(values):
    return [int(v) for v in word_vector(values)]


def body_words(value):
    return words(value['position']+value['box']+value['velocity'])+[
        int(value['width_f32_bits'],16),int(value['height_f32_bits'],16),
        *map(int,value['body_flags'])]


def mask(keys): return sum(int(v)<<i for i,v in enumerate(keys))


def request(id, op, body, context, movement, observations):
    group=lambda vs:'|'.join(str(v & 0xffffffff) for v in vs)
    return ';'.join([id+'|'+op,group(body),group(context),group(words(movement)),
                     '/'.join(group(v) for v in observations)])


def minor_request(case, id=None, mode=0):
    state=case['before']
    return request(id or case['id'],'minor',body_words(state),[
        int(state['rotation_f32_bits'][0],16),int(state['input_f32_bits'][0],16),
        int(state['input_f32_bits'][2],16),mode],case['movement'],[])


def backoff_request(case,id=None,changes=None,observations=None):
    state=case['before']
    context=[int(state['maximum_f32_bits'],16),*words([state['fall_distance_f64_bits']]),
             int(state['flying']),mask(state['key_presses']),
             {'SELF':0,'PLAYER':1}.get(case['mover'],2),0,
             len(case['no_collision_queries'])+1]
    if changes:
        for index,value in changes.items():context[index]=value
    samples=observations if observations is not None else [
        words(q['box'])+[0,int(q['no_collision'])] for q in case['no_collision_queries']]
    return request(id or case['id'],'backoff',body_words(state),context,case['movement'],samples)


def finite64(raw): return int(raw,16)&0x7ff0000000000000!=0x7ff0000000000000
def finite32(raw): return int(raw,16)&0x7f800000!=0x7f800000


def raw64(values):
    assert len(values)%2==0
    return [f'{int(values[i]):08x}{int(values[i+1]):08x}' for i in range(0,len(values),2)]


def parse(line):
    id,kind,*values=line.split('|')
    if kind=='error':return id,{'error':'|'.join(values)}
    if kind=='acos':return id,{'value':raw64(values)[0]}
    if kind=='backoff':
        assert len(values)==7
        return id,{'movement':raw64(values[:6]),'queries':int(values[6])}
    assert kind=='minor' and len(values) in (10,16),(kind,len(values))
    value={'minor':bool(int(values[0])),'rotated':raw64(values[1:5]),
           'input_squared':raw64(values[5:7])[0],
           'movement_squared':raw64(values[7:9])[0],'angle':None}
    if int(values[9]):
        assert len(values)==16
        dot,ratio,angle=raw64(values[10:])
        value['angle']={'dot':dot,'ratio':ratio,'value':angle}
    return id,value


def compare(actual,expected):
    if isinstance(expected,dict):
        return isinstance(actual,dict) and all(k in actual and compare(actual[k],v) for k,v in expected.items())
    if isinstance(expected,list):
        return isinstance(actual,list) and len(actual)==len(expected) and all(compare(a,e) for a,e in zip(actual,expected,strict=True))
    if isinstance(expected,str) and re.fullmatch('[0-9a-f]{16}',expected):
        value=int(expected,16)
        if value&0x7ff0000000000000==0x7ff0000000000000 and value&0xfffffffffffff:
            return isinstance(actual,str) and bool(re.fullmatch('[0-9a-f]{16}',actual)) and int(actual,16)&0x7ff0000000000000==0x7ff0000000000000 and bool(int(actual,16)&0xfffffffffffff)
    return actual==expected


def fixture_pairs(data):
    pairs={g:[] for g in ['acos','minor','backoff','admission']}
    for c in data['acos']:
        expect=c['expected'];assert expect['math_f64_bits']==expect['strict_math_f64_bits']
        pairs['acos'].append(('|'.join([c['id'],'acos',*map(str,words([c['input_f64_bits']]))]),{'value':expect['math_f64_bits']}))
    for c in data['minor']:
        state=c['before'];assert c['plain_observer_parity'] and state==c['after']
        floats=[state['rotation_f32_bits'][0],state['input_f32_bits'][0],state['input_f32_bits'][2]]
        invalid=next((i for i,v in enumerate(floats) if not finite32(v)),None)
        if invalid is not None:
            pairs['admission'].append((minor_request(c),{'error':'input|'+str(invalid)}));continue
        instrumentation=c['independent_numeric_instrumentation']
        expected={**c['expected'],'rotated':instrumentation['rotated_f64_bits'],
                  'input_squared':instrumentation['input_squared_f64_bits'],
                  'movement_squared':instrumentation['movement_squared_f64_bits'],'angle':None}
        threshold=struct.unpack('>d',struct.pack('>Q',0x3ee4f8b580000000))[0]
        small=any(struct.unpack('>d',bytes.fromhex(expected[k]))[0]<threshold for k in ['input_squared','movement_squared'])
        if not small:
            expected['angle']={'dot':instrumentation['dot_f64_bits'],
                               'ratio':instrumentation['ratio_f64_bits'],
                               'value':instrumentation['direct_acos']['math_f64_bits']}
        pairs['minor'].append((minor_request(c),expected))
    for c in data['backoff']:
        state=c['before'];assert c['plain_observer_parity'] and state==c['after']
        if c['mover'] not in ['SELF','PLAYER']:error='mover'
        elif state['flying']:error='flying'
        elif not all(finite64(v) for v in c['movement']):
            error='input|'+str(next(i for i,v in enumerate(c['movement']) if not finite64(v)))
        else:error=None
        if error:pairs['admission'].append((backoff_request(c),{'error':error}));continue
        pairs['backoff'].append((backoff_request(c),{'movement':c['expected']['movement'],'queries':len(c['no_collision_queries'])}))
    return pairs


def validation_pairs(data):
    cases=[];minor=data['minor'][0];edge=next(c for c in data['backoff'] if len(c['no_collision_queries'])>3)
    samples=[words(q['box'])+[0,int(q['no_collision'])] for q in edge['no_collision_queries']]
    for mode in range(1,7):
        cases.append((minor_request(minor,'reject:minor:mode:'+str(mode),mode),{'error':'mode'}))
        cases.append((backoff_request(edge,'reject:edge:mode:'+str(mode),{6:mode}),{'error':'mode'}))
    for bits in [0xbf800000,0x7f800000,0x7fc00123]:
        cases.append((backoff_request(edge,'reject:step:'+str(bits),{0:bits}),{'error':'step'}))
    for high,low in [(0x7ff00000,0),(0xfff00000,0),(0x7ff80000,17)]:
        cases.append((backoff_request(edge,'reject:fall:'+str(high),{1:high,2:low}),{'error':'fall'}))
    cases.append((backoff_request(edge,'reject:flying',{3:1}),{'error':'flying'}))
    cases.append((backoff_request(edge,'reject:mover',{5:2}),{'error':'mover'}))
    cases.append((backoff_request(edge,'reject:budget',{7:0}),{'error':'budget'}))
    cases.append((backoff_request(edge,'reject:missing',observations=[]),{'error':'missing'}))
    denied=copy.deepcopy(samples);denied[0][-2]=1
    cases.append((backoff_request(edge,'reject:denied',observations=denied),{'error':'denied'}))
    mismatch=copy.deepcopy(samples);mismatch[0][1]^=1
    cases.append((backoff_request(edge,'reject:mismatch',observations=mismatch),{'error':'mismatch'}))
    extra=copy.deepcopy(samples)+[samples[-1]]
    cases.append((backoff_request(edge,'reject:extra',observations=extra),{'error':'extra'}))
    return cases


def run_pairs(pairs,batches,size=48):
    for offset in range(0,len(pairs),size):
        chunk=pairs[offset:offset+size]
        result=run([BINARY,'--gpu','off',TABLE,*[p[0] for p in chunk]])
        lines=result['stdout'].splitlines();assert len(lines)==len(chunk),result
        for (arg,expected),line in zip(chunk,lines,strict=True):
            id,actual=parse(line)
            assert id==arg.split('|')[0] and compare(actual,expected),(id,expected,actual)
        batches.append({'requests':len(chunk),'seconds':result['seconds']})


def dyadic(bits,precision=52,bias=1023):
    fracmask=(1<<precision)-1;exponent=(bits>>precision)&(bias*2+1)
    mantissa=bits&fracmask;power=1-bias-precision if exponent==0 else exponent-bias-precision
    if exponent:mantissa|=1<<precision
    value=Fraction(mantissa<<power,1) if power>=0 else Fraction(mantissa,1<<-power)
    return -value if bits>>(precision+1+bias.bit_length()) else value


def rn(value,precision=52,bias=1023,negative_zero=False):
    sign=int(value<0 or (not value and negative_zero))<<(precision+1+bias.bit_length())
    value=abs(value)
    if not value:return sign
    n,d=value.numerator,value.denominator;e=n.bit_length()-d.bit_length()
    if (n<d<<e if e>=0 else n<<-e<d):e-=1
    power=precision-max(e,1-bias)
    if power>=0:n<<=power
    else:d<<=-power
    q,r=divmod(n,d)
    if 2*r>d or (2*r==d and q&1):q+=1
    if q==1<<(precision+1):q>>=1;e+=1
    if e>bias:return sign|((bias*2+1)<<precision)
    if e<1-bias:return sign|q
    return sign|((e+bias)<<precision)|(q&((1<<precision)-1))


def rational_audit(data):
    from test_f64 import sqrt_integer_expected
    counts={'f32_multiply':0,'f64_add_sub_mul':0,'f64_div':0,'integer_sqrt':0}
    def op(a,b,operation,precision=52,bias=1023):
        av,bv=dyadic(a,precision,bias),dyadic(b,precision,bias)
        if operation=='mul':value=av*bv;negative=(a^b)>>(precision+1+bias.bit_length())!=0
        elif operation=='div':value=av/bv;negative=(a^b)>>(precision+1+bias.bit_length())!=0
        elif operation=='sub':value=av-bv;negative=av==bv==0 and a>>(precision+1+bias.bit_length()) and not b>>(precision+1+bias.bit_length())
        else:value=av+bv;negative=av==bv==0 and a>>(precision+1+bias.bit_length()) and b>>(precision+1+bias.bit_length())
        counts['f32_multiply' if precision==23 else 'f64_div' if operation=='div' else 'f64_add_sub_mul']+=1
        return rn(value,precision,bias,negative)
    checked=0
    for c in data['minor']:
        state=c['before'];i=c['independent_numeric_instrumentation']
        inputs=[state['rotation_f32_bits'][0],state['input_f32_bits'][0],state['input_f32_bits'][2]]
        if not all(finite32(v) for v in inputs) or not all(finite64(v) for v in c['movement']):continue
        # RN-even F32 degree multiplication is independently computed with integers.
        assert op(int(inputs[0],16),0x3c8efa35,'mul',23,127)==int(i['radians_f32_bits'],16)
        widen=lambda h:struct.unpack('>Q',struct.pack('>d',struct.unpack('>f',bytes.fromhex(h))[0]))[0]
        a,b=map(widen,inputs[1:]);s,co=int(i['sin_f64_bits'],16),int(i['cos_f64_bits'],16)
        x=op(op(a,co,'mul'),op(b,s,'mul'),'sub');z=op(op(b,co,'mul'),op(a,s,'mul'),'add')
        assert [f'{x:016x}',f'{z:016x}']==i['rotated_f64_bits']
        length=op(op(x,x,'mul'),op(z,z,'mul'),'add');dx,dz=int(c['movement'][0],16),int(c['movement'][2],16)
        x2,z2=op(dx,dx,'mul'),op(dz,dz,'mul')
        if x2&0x7ff0000000000000==0x7ff0000000000000 or z2&0x7ff0000000000000==0x7ff0000000000000:continue
        movement=op(x2,z2,'add');dot=op(op(x,dx,'mul'),op(z,dz,'mul'),'add')
        assert f'{length:016x}'==i['input_squared_f64_bits'] and f'{movement:016x}'==i['movement_squared_f64_bits'] and f'{dot:016x}'==i['dot_f64_bits']
        product=op(length,movement,'mul')
        if product and product&0x7ff0000000000000!=0x7ff0000000000000:
            root=sqrt_integer_expected(product);counts['integer_sqrt']+=1
            ratio=op(dot,root,'div');assert f'{ratio:016x}'==i['ratio_f64_bits']
        checked+=1
    return {'status':'passed','receiver_numeric_cases':checked,'operations':counts,
            'scope':'Integer-decoded exact dyadic Fraction arithmetic and explicit RN-even packing; arbitrary-integer square-root oracle. Supplemental numeric instrumentation only, never decisive gameplay Bool/vector expectations.'}


def main():
    p=argparse.ArgumentParser();p.add_argument('--build-only',action='store_true');p.add_argument('--kernel-only',action='store_true');p.add_argument('--skip-build',action='store_true');p.add_argument('--skip-checks',action='store_true');p.add_argument('--reuse-checked',action='store_true');p.add_argument('--prepare-only',action='store_true');a=p.parse_args()
    if a.build_only:print(json.dumps(bounded_check('build',600),indent=2));return
    if a.kernel_only:print(json.dumps(bounded_check('kernel',60),indent=2));return
    from reference_local_collision_probe import verify
    data=json.loads(FIXTURE.read_text());provenance=verify(selftest=True);pairs=fixture_pairs(data);rejected=validation_pairs(data);rational=rational_audit(data)
    if a.prepare_only:
        print(json.dumps({'status':'prepared','counts':{g:len(v) for g,v in pairs.items()},'rejections':len(rejected),'rational_audit':rational,'source_sha256':source_hashes()},indent=2));return
    checks=[] if a.skip_checks else [bounded_check('kernel',60)]
    builds=[] if a.skip_build else [bounded_check('build',600)]
    if a.reuse_checked:
        assert a.skip_build and a.skip_checks
        checks,builds=[completed('kernel')],[completed('build')]
    started=time.monotonic();batches=[]
    for group in pairs.values():run_pairs(group,batches)
    run_pairs(rejected,batches)
    valid=pairs['minor'][0]
    for failure in pairs['admission']+rejected:run_pairs([failure,valid],batches,size=2)
    malformed=[]
    for text in ['broken','bad|acos|abc','bad|acos|0','bad|unknown|0','bad|backoff;;;;']:
        result=run([BINARY,'--gpu','off',TABLE,text],required=False)
        assert result['exit_code']==2 and 'invalid local collision' in result['stderr'],result
        malformed.append({'exit_code':result['exit_code'],'stderr':result['stderr']})
    source=(ROOT/'src/local_collision.bend').read_text();assert not re.search(r'@unsafe|\bimport\s+["\']|\w!\(',source)
    record={'status':'passed' if not a.skip_checks or a.reuse_checked else 'native_passed_checks_skipped','pin':'26.3','kernel_pass':not a.skip_checks or a.reuse_checked,'checks_reused_with_exact_source_hashes':a.reuse_checked,'counts':{g:len(v) for g,v in pairs.items()},'actual_query_count':data['counts']['no_collision_queries'],'native_backoff_query_count':sum(expected['queries'] for argument,expected in pairs['backoff']),'explicit_rejection_cases':len(rejected),'owner_retention_followups':len(rejected)+len(pairs['admission']),'native_validation_seconds':round(time.monotonic()-started,6),'native_batches':batches,'rational_audit':rational,'checks':checks,'builds':builds,'fixture':fingerprint(FIXTURE),'fixture_provenance':provenance,'observations_sha256':data['observations_sha256'],'binary':fingerprint(BINARY),'sources_sha256':source_hashes(),'tool_sha256':sha(Path(__file__)),'laws':re.findall(r'^law (\w+):',source,re.M),'malformed_protocol':malformed,'scope':data['boundary'],'nan_policy':'Finite/infinite/signed-zero raw exact comparisons; NaN class only, no payload portability claim. Acos implements actual pinned fdlibm operation sequence, not a universal correctly-rounded transcendental claim.'}
    (ROOT/'evidence/local-collision-verification.json').write_text(json.dumps(record,sort_keys=True,indent=2)+'\n')
    print(json.dumps({k:record[k] for k in ['status','counts','kernel_pass','actual_query_count','native_backoff_query_count','explicit_rejection_cases','native_validation_seconds']},indent=2))


if __name__=='__main__':main()

