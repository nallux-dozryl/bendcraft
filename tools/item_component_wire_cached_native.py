#!/usr/bin/env python3
"""Compile the unchanged transport observer with the tested actor016 emitter.

This preserves the failed ordinary route and uses its exact frozen Bend/native
source graph. The original full checker and compiler installation stay intact.
"""
from __future__ import annotations
import argparse,hashlib,json,os,signal,subprocess,sys,time
from pathlib import Path
import build_native
from reference_inventory import ROOT,write_json
from test_player_block_inside_stuck import run as checked_run

ORIGIN=ROOT/'build/compiler-producer-diagnostic-016'
FROZEN=ROOT/'build/item_component_wire_transport/native-001'
WORK=ROOT/'build/item_component_wire_transport/private-native-001'
PINS={
    'comp_instrumented.ts':'d2e149a6c97c6f57af8bb8c2bc86b4203a933cf18e430916efe40f456e818f4a',
    'run.py':'3dc542c1e956b42ea1052344f40cdf94dd2b33a68ec7387113e16952a91e5fbd',
    'diagnose.mjs':'ec59feb190ac33644f818210c35f0dd299382766dec8f8a6f7153742bddd0ed6',
}
def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def pin(p):
    p=Path(p).resolve();return {'path':str(p),'sha256':sha(p),'bytes':p.stat().st_size}
def cleanup_emitter():
    # The retained run.py starts Node in its own group. A wrapper exception must
    # also close that exact private child rather than just its Python monitor.
    rows=subprocess.check_output(['/bin/ps','-axo','pid=,pgid=,command='],text=True).splitlines()
    suffix=' '+str(WORK/'diagnose.mjs')
    groups={int(fields[1]) for row in rows if len(fields:=row.strip().split(None,2))==3 and fields[2].endswith(suffix)}
    for group in groups:
        try:os.killpg(group,signal.SIGTERM)
        except ProcessLookupError:pass
    deadline=time.monotonic()+3
    alive=set(groups)
    while alive and time.monotonic()<deadline:
        present={int(row.strip()) for row in subprocess.check_output(['/bin/ps','-axo','pgid='],text=True).splitlines() if row.strip()}
        alive &= present
        if alive:time.sleep(.05)
    for group in alive:
        try:os.killpg(group,signal.SIGKILL)
        except ProcessLookupError:pass
    remaining=[]
    for poll in range(21):
        after=subprocess.check_output(['/bin/ps','-axo','pid=,pgid=,command='],text=True).splitlines()
        remaining=[row.strip() for row in after if row.strip().endswith(suffix)]
        if not remaining:break
        if poll<20:time.sleep(.05)
    write_json(WORK/'emission-wrapper-cleanup.json',{'owned_groups':sorted(groups),'remaining':remaining})
    assert not remaining,'Private emitter child remains after wrapper exit'
def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepare-only',action='store_true');args=parser.parse_args()
    snapshot=json.loads((FROZEN/'source-snapshot.json').read_text())
    entry=Path(snapshot['entry'])
    frozen={str(FROZEN/'source'/p):h for p,h in snapshot['original_source_sha256'].items()}
    assert all(sha(p)==h for p,h in frozen.items()),'Frozen observer source drift'
    prior=json.loads((ORIGIN/'manifest.json').read_text())
    original={p:h for p,h in prior['files'].items() if not Path(p).is_relative_to(ROOT)}
    assert all(sha(p)==h for p,h in original.items()),'Original compiler/tool drift'
    assert all(sha(ORIGIN/p)==h for p,h in PINS.items()),'Tested actor016 emitter drift'
    actor=json.loads((ORIGIN/'receipt.json').read_text())
    assert actor['returncode']==0 and actor['complete_C'] and actor['group_absent']
    WORK.mkdir(parents=True,exist_ok=True)
    manifest_path=WORK/'manifest.json'
    if not manifest_path.exists():
        for name in PINS:
            text=(ORIGIN/name).read_text()
            if name=='diagnose.mjs':
                old_entry='const entry='+json.dumps(prior['entry'])+';'
                assert text.count(old_entry)==1,'Actual entry boundary changed'
                text=text.replace(old_entry,'const entry='+json.dumps(str(entry))+';')
                text=text.replace(str(ORIGIN),str(WORK))
            with (WORK/name).open('x') as output:output.write(text)
        files={**original,**frozen,**{str(ORIGIN/p):h for p,h in PINS.items()},
               **{str(WORK/p):sha(WORK/p) for p in PINS},
               str(FROZEN/'source-snapshot.json'):sha(FROZEN/'source-snapshot.json'),
               str(ORIGIN/'receipt.json'):sha(ORIGIN/'receipt.json')}
        write_json(manifest_path,{'entry':str(entry),'files':files,'limits':prior['limits'],
            'scope':'Same unchanged complete observer graph as the preserved ordinary600s failure. Reuses actor016 tested private WeakMap telescope cache and completed-work progress. Original full source checker, declarations, order, holes and CPU flags retained. No original compiler edits, installed cache promotion, or compiler-wide certification.'})
    manifest=json.loads(manifest_path.read_text())
    assert all(sha(p)==h for p,h in manifest['files'].items()),'Producer input drift'
    if args.prepare_only:
        print(json.dumps({'status':'prepared','manifest':pin(manifest_path),'source_files':len(frozen)}));return
    if not (WORK/'receipt.json').exists():
        try:checked_run([sys.executable,WORK/'run.py'],WORK,'emission',605)
        finally:cleanup_emitter()
    receipt=json.loads((WORK/'receipt.json').read_text())
    assert receipt['returncode']==0 and receipt['termination_reason'] is None and receipt['complete_C'] and receipt['group_absent'],receipt
    assert receipt['source_before']==receipt['source_after']==manifest['files'],'Producer source changed'
    loaded=json.loads((WORK/'loaded-source-pins.json').read_text())
    assert loaded==json.loads((WORK/'final-source-pins.json').read_text())
    assert all(sha(p)==h for p,h in loaded.items()),'Loaded source drift'
    c=WORK/'diagnostic.c';cpin=pin(c);build_native.guard_route(c.read_text())
    assert cpin['sha256']==receipt['C']['sha256'] and cpin['bytes']==receipt['C']['bytes']
    binary=WORK/'observer';done_path=WORK/'native-build.json'
    if not done_path.exists():
        sdk=subprocess.check_output(['/usr/bin/xcrun','--show-sdk-path'],text=True).strip()
        command=['/usr/bin/env','SDKROOT='+sdk,'/usr/bin/clang','-std=c11','-O3',str(c),'-lpthread','-lm','-o',str(binary)]
        clangpin=pin('/usr/bin/clang')
        identity_path=WORK/'clang-input-identity.json'
        if identity_path.exists():
            identity=json.loads(identity_path.read_text())
            assert identity['path']==clangpin['path'] and identity['sha256']==clangpin['sha256'],'Native compiler changed'
        else:write_json(identity_path,clangpin)
        compiled_path=WORK/'clang.json'
        output_pin_path=WORK/'clang-output-identity.json'
        if compiled_path.exists():
            compiled=json.loads(compiled_path.read_text())
            assert compiled['argv']==command and compiled['exit_code']==0 and not compiled['timed_out'] and compiled['group_absent'],'Prior native compiler failed'
            output=json.loads(output_pin_path.read_text())
            assert output['binary']==pin(binary),'Retained native output changed'
        else:
            _,compiled=checked_run(command,WORK,'clang',600)
            write_json(output_pin_path,{'binary':pin(binary),'observed':'immediately after successful native compile'})
        assert (WORK/'clang.stderr').read_bytes()==b''
        assert pin('/usr/bin/clang')==clangpin and pin(c)==cpin
        assert all(sha(p)==h for p,h in manifest['files'].items())
        done={'status':'passed','binary':pin(binary),'C':cpin,'manifest':pin(manifest_path),
            'producer':pin(WORK/'receipt.json'),'emission_seconds':receipt['seconds'],
            'sampled_peak_RSS_bytes':receipt['sampled_peak_rss_bytes'],
            'clang':{'command':command,'SDKROOT':sdk,'compiler':clangpin,'seconds':compiled['seconds'],'group_absent':compiled['group_absent']},
            'native_output_identity':pin(output_pin_path),
            'scope':manifest['scope'],'behavior':'pending real transport and wire observer replay'}
        write_json(done_path,done)
    done=json.loads(done_path.read_text());assert done['binary']==pin(binary) and done['C']==pin(c)
    print(json.dumps({'status':'passed','binary':done['binary'],'emission_seconds':done['emission_seconds'],'clang_seconds':done['clang']['seconds']}),flush=True)
if __name__=='__main__':main()
