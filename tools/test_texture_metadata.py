#!/usr/bin/env python3
"""Pure Bend metadata vs actual pinned official codec/receiver; no window."""
from __future__ import annotations
import argparse,datetime,hashlib,json,os,re,subprocess,time
from pathlib import Path
import reference_texture_metadata_probe as REF
ROOT=Path(__file__).resolve().parents[1]
BEND=Path.home()/'.bend/bin/bend'
BUILD=ROOT/'build/texture-metadata'
BIN=ROOT/'build/texture-metadata-tests'
ENV={**os.environ,'BEND_MINECRAFT_LAUNCH_MODE':'hidden'}
def sha(b):return hashlib.sha256(b).hexdigest()
def write(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_text(json.dumps(v,indent=2,sort_keys=True)+'\n')
def fingerprint():
    pending=[ROOT/'tests/texture_metadata.bend'];seen={}
    while pending:
        path=pending.pop().resolve()
        if str(path)in seen:continue
        data=path.read_bytes();seen[str(path)]=sha(data)
        for name in re.findall(r'^import\s+(\.\.?/\S+\.bend)',data.decode(),re.M):pending.append(path.parent/name)
    return {**{str(Path(p).relative_to(ROOT)):v for p,v in seen.items()},'pinned_compiler_sha256':sha(BEND.read_bytes())}
def run(args,timeout=600):
    p=subprocess.run(list(map(str,args)),cwd=ROOT,env=ENV,capture_output=True,text=True,timeout=timeout)
    if p.returncode:raise RuntimeError((args,p.returncode,p.stdout[-5000:],p.stderr[-5000:]))
    return p

def native(cases):
    rows=[]
    for i in range(0,len(cases),16):
        p=run([BIN,'--threads','1',*[json.dumps(c,separators=(',',':'))for c in cases[i:i+16]]],timeout=60)
        lines=p.stdout.splitlines()
        if len(lines)!=len(cases[i:i+16]):raise AssertionError(('line count',p.stdout[:2000]))
        rows.extend(json.loads(x)for x in lines)
    return rows

def extras():
    # Explicit engineering bounds, separate from unbounded Java codec behavior.
    document='{"texture":{}}'
    return [
      ({'id':'numeric-digit-budget','mode':'number','json':'1'*1025},'NumericLimitOrSyntax'),
      ({'id':'numeric-token-budget','mode':'number','json':'1e'+('9'*4096)},'NumericLimitOrSyntax'),
      ({'id':'json-depth-budget','mode':'limited','json':document,'max_depth':0},'InvalidJson'),
      ({'id':'json-input-budget','mode':'limited','json':document,'max_codepoints':len(document)-1},'InvalidJson'),
      ({'id':'json-exact-boundaries','mode':'limited','json':document,'max_codepoints':len(document),'max_depth':2},None),
      ({'id':'json-trailing-input-budget','mode':'limited','json':document+' '*64,'max_codepoints':len(document)},'InvalidJson')]

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--prepare-only',action='store_true');ap.add_argument('--reuse-build',action='store_true');ap.add_argument('--skip-kernel',action='store_true');args=ap.parse_args()
    reference=json.loads(REF.OUT.read_text());summary=REF.validate(reference);cases=reference['inputs']['cases'];limits=extras();all_cases=cases+[x[0]for x in limits]
    BUILD.mkdir(parents=True,exist_ok=True);generation=fingerprint()
    if args.prepare_only:
        write(BUILD/'cases.json',all_cases);write(ROOT/'evidence/texture-metadata-preflight.json',{'status':'prepared-native-unverified','native_source_fingerprint':generation,'oracle_summary':summary,'limit_cases':len(limits),'reference_sha256':sha(REF.OUT.read_bytes()),'command':'python3 tools/test_texture_metadata.py --prepare-only'});print({'cases':len(all_cases),'status':'prepared-native-unverified'});return
    start=time.monotonic();check=run([BEND,'tests/texture_metadata.bend','--check-only'],60);ordinary_seconds=time.monotonic()-start
    assert 'ALL PROOFS CHECK'in check.stdout
    kernel={'status':'not-run','reason':'explicit --skip-kernel; native does not establish a mathematical kernel verdict'}
    if not args.skip_kernel:
        start=time.monotonic()
        try:
            p=subprocess.run([str(BEND),'src/texture_metadata.bend','--verdict'],cwd=ROOT,env=ENV,capture_output=True,text=True,timeout=60);output=p.stdout+p.stderr;status='passed'if p.returncode==0 and 'ALL PROOFS CHECK'in output else 'compiler-kernel-mismatch'if 'mismatch between the TypeScript implementation'in output else 'failed';kernel={'status':status,'exit_code':p.returncode,'output':output.strip(),'seconds':time.monotonic()-start};assert status!='failed',kernel
        except subprocess.TimeoutExpired:kernel={'status':'inconclusive-timeout','timeout_seconds':60}
    stamp=BUILD/'native-build.json';build_seconds=None
    if args.reuse_build:
        cached=json.loads(stamp.read_text());assert cached['sources']==generation;assert cached['binary_sha256']==sha(BIN.read_bytes());build_seconds=cached['build_seconds']
    else:
        start=time.monotonic();run([BEND,'tests/texture_metadata.bend','-o',BIN],600);build_seconds=time.monotonic()-start
        assert fingerprint()==generation,'Sources changed during native build';write(stamp,{'sources':generation,'binary_sha256':sha(BIN.read_bytes()),'build_seconds':build_seconds})
    results=native(all_cases);second=native(all_cases);assert results==second,'Two native runs differ';assert fingerprint()==generation,'Sources changed during validation'
    successes=absent=errors=0;details=[]
    for c,expected,actual in zip(cases,reference['observations']['cases'],results):
        e=expected['result'];assert actual['status']==e['status'],(c,actual,e)
        if e['status']=='ok':
            assert {k:actual[k]for k in ['blur','clamp','strategy']}=={k:e[k]for k in ['blur','clamp','strategy']},(c,actual,e)
            assert actual['alpha_cutoff_bias_u32']==int(e['alpha_cutoff_bias_f32'],16),(c,actual,e);successes+=1
        elif e['status']=='absent':absent+=1
        else:errors+=1
        details.append({'id':c['id'],'status':actual['status'],**({'code':actual['code'],'field':actual['field']}if actual['status']=='error'else {})})
    for (case,code),actual in zip(limits,results[len(cases):]):
        if code is None:assert actual['status']=='ok'
        else:assert actual['status']=='error'and actual['code']==code,(case,actual,code)
    report_sha=sha(REF.canonical(results))
    evidence={'schema':1,'status':'passed_bounded_domain','time_utc':datetime.datetime.now(datetime.timezone.utc).isoformat(),'official_cases':len(cases),'successful_metadata':successes,'absent_sections':absent,'rejections':errors,'limit_cases':len(limits),'two_native_runs_equal':True,'canonical_report_sha256':report_sha,'reference_sha256':sha(REF.OUT.read_bytes()),'native_binary_sha256':sha(BIN.read_bytes()),'native_binary_bytes':BIN.stat().st_size,'native_source_fingerprint':generation,'ordinary':{'output':check.stdout.strip(),'seconds':ordinary_seconds},'kernel':kernel,'build_seconds':build_seconds,'sources':{p:sha((ROOT/p).read_bytes())for p in ['src/texture_metadata.bend','tests/texture_metadata.bend','tools/test_texture_metadata.py','tools/reference_texture_metadata_probe.py']},'command':'python3 tools/test_texture_metadata.py '+(' --reuse-build'if args.reuse_build else '')+(' --skip-kernel'if args.skip_kernel else ''),'boundary':'Exact four field values and raw F32 bits vs actual CODEC and ResourceMetadata. Structured Bend error codes, not Java diagnostics/partial values. Bounded ResourceJson/FloatParse input policies. No sampler/mipmap pixels/atlas/render integration; frozen StaticNormalized still rejects nonempty metadata.','cases':details}
    write(ROOT/'evidence/texture-metadata-native.json',evidence);print({'status':evidence['status'],'cases':len(all_cases),'report_sha256':report_sha,'build_seconds':build_seconds})
if __name__=='__main__':main()
