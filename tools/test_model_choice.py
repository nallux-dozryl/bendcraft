#!/usr/bin/env python3
"""Verify pure Bend selection against independent actual Java receiver fixtures."""
from __future__ import annotations
import argparse, collections, copy, hashlib, json, pathlib, re, subprocess, time, zipfile
from reference_inventory import ROOT, canonical, fingerprint, write_json
import reference_model_choice_probe as P
from reference_model_probe import verified_client_classpath

BEND=pathlib.Path('/Users/chuah/.bend/bin/bend');BIN=ROOT/'build/model-choice-tests'
OWN=['src/model_choice.bend','tests/model_choice.bend','tools/test_model_choice.py','tools/reference_model_choice_probe.py']

def vtext(v):return ','.join(map(str,[v['model'],v['x'],v['y'],v['z'],int(v['uvlock'])]))
def ctext(c):
    if c['kind']=='single':return 's,'+vtext(c['variant'])
    return 'w,'+str(c['total'])+','+','.join(str(w['weight'])+','+vtext(w['variant'])for w in c['entries'])
def protocol(c):
    r=c['root'];kind='v'if r['kind']=='variant'else'm'
    root=ctext(r['choice'])if kind=='v'else';'.join(str(p['index'])+','+ctext(p['choice'])for p in r['parts'])
    return '|'.join(map(str,[c['id'],c['kind'],*c['seed'],*c['high'],c['advance'],c['repeats'],c['fuel'],'s'if'reseed'in c else'n',*c.get('reseed',[0,0]),kind,root]))
def stext(s):return ','.join(map(str,[s[0],*s[1],*s[2]]))
def otext(label,index,o):
    seeds=[c['value']for c in o['calls']if c['method']=='nextLong'];seed=','.join(map(str,seeds[0]))if seeds else'-'
    selected=';'.join(('v'if s['part_index']is None else str(s['part_index']))+','+vtext(s['variant'])for s in o['selected'])
    return f'{label}|{index}|{stext(o["after"])}|ok|{seed}|{selected}'
def expected(c):return [otext(c['input']['id'],i+1,o)for i,o in enumerate(c['observed']['outcomes'])]

def require(test,message):
    if not test:raise ValueError(message)
def word(value):return type(value)is int and 0<=value<=0xffffffff
def state_valid(s):
    return type(s)is list and len(s)==3 and s[0]in ['l','x']and all(type(p)is list and len(p)==2 and all(word(x)for x in p)for p in s[1:])and(s[0]!='l'or s[1][0]<65536 and s[2]==[0,0])
def validate_reference(ref,cp,release):
    require(ref['schema']==1 and ref['pin']=='26.3','Version/schema mismatch')
    require(ref['source_sha256']==hashlib.sha256(P.SOURCE.encode()).hexdigest(),'Java harness mismatch')
    require(ref['release']==release,'Pinned artifact/runtime inventory mismatch')
    require(ref['cases_sha256']==hashlib.sha256(canonical(ref['cases'])).hexdigest(),'Fixture digest mismatch')
    with zipfile.ZipFile(P.CLIENT)as z:
        for name,rec in ref['class_inventory'].items():require(rec['class_sha256']==hashlib.sha256(z.read(name.replace('.','/')+'.class')).hexdigest(),'Class mismatch: '+name)
    require(set(ref['class_inventory'])==set(P.CLASSES),'Incomplete production class inventory')
    regenerated=P.inputs(ref['random_cases']);base=regenerated['cases'];observed_inputs=[c['input']for c in ref['cases']]
    require(observed_inputs[:len(base)]==base,'Deterministic input corpus mismatch')
    require(ref['resources']==regenerated['resources'],'Resource hash mismatch')
    suffix=[]
    for block in ref['official']:
        for s in block['states']:
            if'root'in s:suffix.append({'id':f'official_{block["block"]}_{s["id"]}','root':s['root'],'kind':'t','seed':P.bits(42),'high':P.bits(0),'advance':0,'repeats':3,'fuel':64,'tags':['official_instantiated_root']})
    require(observed_inputs[len(base):]==suffix,'Official instantiated roots mismatch')
    require(len(ref['receiver_errors'])==len(regenerated['errors']),'Receiver error count mismatch')
    for expected,error in zip(regenerated['errors'],ref['receiver_errors']):
        require(error['id']==expected['id']and error['status']=='error'and error['phase']in ['construction','collectParts'],'Malformed receiver error')
        require(state_valid(error['before'])and error['after']==error['before'],'Receiver error changed RNG state')
    require(len({c['id']for c in observed_inputs})==len(observed_inputs),'Duplicate case IDs')
    for case in ref['cases']:
        c,o=case['input'],case['observed'];require(c['id']==o['id'],'Observation ID mismatch');require(state_valid(o['initial_state']),'Invalid initial raw RNG state');require(len(o['outcomes'])==c['repeats'],'Outcome count mismatch')
        before=o['initial_state'];multipart=c['root']['kind']=='multipart'
        for outcome in o['outcomes']:
            require(outcome['before']==before,'Unchained caller state');require(state_valid(outcome['after']),'Invalid after raw state');cursor=before;names=[]
            for call in outcome['calls']:
                require(call['method']in ['setSeed','nextLong','nextInt'],'Unknown production RNG method');require(call['before']==cursor and state_valid(call['after']),'Unchained method state');cursor=call['after'];names.append(call['method'])
                if call['method']=='nextInt':require(len(call['args'])==1 and 1<=call['args'][0]<=2147483647 and 0<=call['value']<call['args'][0]and 1<=call['primitive_draws']<=16384,'Malformed bounded RNG observation')
                if call['method']=='nextLong':require(call['args']==[]and len(call['value'])==2 and all(word(x)for x in call['value']),'Malformed nextLong observation')
                if call['method']=='setSeed':require(len(call['args'])==1 and len(call['args'][0])==2 and all(word(x)for x in call['args'][0])and call['value']is None,'Malformed reseed observation')
            require(cursor==outcome['after'],'Final state differs from last method state')
            root=c['root'];choices=[p['choice']for p in root['parts']]if multipart else[root['choice']]
            ordered=(['setSeed']if'reseed'in c else[])+(['nextLong']if multipart else[])
            for ch in choices:ordered+=(['setSeed']if multipart else[])+(['nextInt']if ch['kind']=='weighted'else[])
            require(names==ordered,'Production call-order mismatch')
            require(len(outcome['selected'])==len(choices),'Selected part count mismatch')
            for n,(selected,ch)in enumerate(zip(outcome['selected'],choices)):
                require(selected['part_index']==(root['parts'][n]['index']if multipart else None),'Selected source-part index mismatch')
                variants=[ch['variant']]if ch['kind']=='single'else[w['variant']for w in ch['entries']]
                require(selected['variant']in variants,'Selected unknown variant')
            before=outcome['after']
    return regenerated

def defensive_cases(ref):
    cases=[]
    single={'kind':'variant','choice':P.choice()}
    weighted={'kind':'variant','choice':P.choice([1,2])}
    multi={'kind':'multipart','parts':[{'index':0,'choice':P.choice()},{'index':5,'choice':P.choice([1,2])}]}
    for kind in ['l','x']:
        for root,code,fuel in [(single,'ok',0),(weighted,'rng:RejectionFuelExhausted',0),(multi,'rng:RejectionFuelExhausted',0)]:
            for seeded in [False,True]:
                c={'id':f'defensive{len(cases)}','kind':kind,'seed':P.bits(42),'high':P.bits(0),'advance':3,'repeats':1,'fuel':fuel,'root':root,'tags':['rollback']}
                if seeded:c['reseed']=P.bits(-1)
                # Successful single+reseed is handled by fresh production Java.
                if code=='ok':continue
                # Initial state comes independently from an existing actual Java
                # fixture with exactly this source/advance, not Python RNG math.
                candidates=[x for x in ref['cases']if x['input']['kind']==kind and x['input']['advance']==3]
                if candidates:c['seed']=candidates[0]['input']['seed'];c['high']=candidates[0]['input']['high'];initial=candidates[0]['observed']['initial_state']
                else:continue
                line=f'{c["id"]}|1|{stext(initial)}|{code}|-|';cases.append((c,[line]))
    anchor=next(x for x in ref['cases']if x['input']['kind']=='t'and x['input']['seed']==[0,0]and x['input']['advance']==0)
    for ch,code in [({'kind':'weighted','total':0,'entries':[]},'InvalidWeightedChoice'),({'kind':'weighted','total':2,'entries':[{'variant':P.variant(0),'weight':0},{'variant':P.variant(1),'weight':2}]},'NonPositiveWeight'),({'kind':'weighted','total':3,'entries':[{'variant':P.variant(0),'weight':2}]},'InvalidWeightedChoice'),({'kind':'weighted','total':2147483648,'entries':[{'variant':P.variant(0),'weight':2147483647},{'variant':P.variant(1),'weight':1}]},'WeightSumOverflow')]:
        for multipart in [False,True]:
            c=copy.deepcopy(anchor['input']);c.update(id=f'defensive{len(cases)}',repeats=1,root={'kind':'multipart','parts':[{'index':0,'choice':P.choice()},{'index':5,'choice':ch}]}if multipart else{'kind':'variant','choice':ch});c['reseed']=P.bits(-1)
            cases.append((c,[f'{c["id"]}|1|{stext(anchor["observed"]["initial_state"])}|choice:{code}|-|']))
    # Measured rejection counts determine success vs whole-source rollback;
    # preserve successful prefix parts/seed in Java only, not in Bend failures.
    measured=0
    for case in ref['cases']:
        outcome=case['observed']['outcomes'][0];draws=[c['primitive_draws']for c in outcome['calls']if c['method']=='nextInt']
        if draws and max(draws)>1:
            c=copy.deepcopy(case['input']);c.update(id=f'defensive{len(cases)}',repeats=1,fuel=max(draws)-1)
            cases.append((c,[f'{c["id"]}|1|{stext(case["observed"]["initial_state"])}|rng:RejectionFuelExhausted|-|']))
            measured+=1
            if measured>=12:break
    # Empty multipart and non-weighted choices need no bounded rejection fuel.
    for case in ref['cases']:
        c=case['input'];root=c['root']
        direct=root['kind']=='variant'and root['choice']['kind']=='single'
        empty=root['kind']=='multipart'and not root['parts']
        if c['kind']in ['t','x']and c['seed']==[0,0]and(direct or empty):
            q=copy.deepcopy(c);q.update(id=f'defensive{len(cases)}',repeats=1,fuel=0)
            cases.append((q,[otext(q['id'],1,case['observed']['outcomes'][0])]))
    return cases

def transitive_hashes():
    seen={}
    def visit(path):
        path=path.resolve();name=str(path.relative_to(ROOT))
        if name in seen:return
        raw=path.read_bytes();seen[name]=hashlib.sha256(raw).hexdigest()
        for target in re.findall(r'^import\s+(\S+)',raw.decode(),re.M):
            if target.startswith('.')and target.endswith('.bend'):visit(path.parent/target)
    visit(ROOT/'tests/model_choice.bend');return dict(sorted(seen.items()))

def selftest_reference(ref,cp,release):
    changes=[('pin',lambda x:x.update(pin='26.4')),('class_hash',lambda x:x['class_inventory'][P.CLASSES[0]].update(class_sha256='0'*64)),('fixture_hash',lambda x:x.update(cases_sha256='0'*64)),('source_hash',lambda x:x.update(source_sha256='0'*64)),('resource_hash',lambda x:next(iter(x['resources'].values())).update(sha256='0'*64)),('broken_state_chain',lambda x:x['cases'][1]['observed']['outcomes'][0]['calls'][0].update(before=['l',[0,0],[0,0]])),('receiver_error_state',lambda x:x['receiver_errors'][0].update(after=['l',[0,0],[0,0]]))]
    rejected=[]
    for name,mutate in changes:
        bad=copy.deepcopy(ref);mutate(bad)
        if name=='broken_state_chain':bad['cases_sha256']=hashlib.sha256(canonical(bad['cases'])).hexdigest()
        try:validate_reference(bad,cp,release)
        except(ValueError,KeyError,TypeError,IndexError)as e:rejected.append({'id':name,'result':'rejected','detail':str(e)})
        else:raise AssertionError('Malformed reference accepted: '+name)
    write_json(ROOT/'evidence/model-choice-reference-validation.json',{'schema':1,'pin':'26.3','result':'passed','valid_cases':len(ref['cases']),'malformed_cases':rejected,'source_sha256':{p:fingerprint(ROOT/p)['sha256']for p in OWN},'command':['python3','tools/test_model_choice.py','--prepare-only','--selftest'],'scope':'Pinned metadata/class/resource/source checks; deterministic input regeneration and independent method/state consistency checks. Broken-chain fixture digest is recomputed to test validation beyond checksum.'})
    return [x['id']for x in rejected]

def run_native(cases):
    output=[]
    for start in range(0,len(cases),20):
        batch=cases[start:start+20];r=subprocess.run([str(BIN),'--gpu','off','--threads','1',*[protocol(c)for c,_ in batch]],cwd=ROOT,capture_output=True,text=True,check=True,timeout=60);output+=r.stdout.splitlines()
    return output
def compare(actual,expected):
    require(actual==expected,next((f'Native mismatch at {n}: {a!r} != {e!r}'for n,(a,e)in enumerate(zip(actual,expected))if a!=e),f'Native count mismatch {len(actual)} != {len(expected)}'))

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--no-build',action='store_true');ap.add_argument('--selftest',action='store_true');ap.add_argument('--prepare-only',action='store_true');ap.add_argument('--build-timeout',type=int,default=600);args=ap.parse_args()
    ref=json.loads((ROOT/'reference/model_choice.json').read_text());cp,release=verified_client_classpath();data=validate_reference(ref,cp,release)
    data['cases']=[c['input']for c in ref['cases']];one,j1=P.run_java(data,cp,'verify1');two,j2=P.run_java(data,cp,'verify2')
    require(one==two,'Fresh Java reproduction mismatch');require(one['cases']==[c['observed']for c in ref['cases']]and one['official']==ref['official']and one['positions']==ref['positions']and one['errors']==ref['receiver_errors'],'Reference differs from fresh actual Java')
    rejected=selftest_reference(ref,cp,release)if args.selftest else[]
    commands=[];checks={}
    if not args.no_build:
        for path in ['src/model_choice.bend','tests/model_choice.bend']:
            cmd=[str(BEND),path,'--check-only'];commands.append(cmd);r=subprocess.run(cmd,cwd=ROOT,capture_output=True,text=True,check=True,timeout=60);require('ALL PROOFS CHECK'in r.stdout,'Ordinary check failed');checks[path]=r.stdout.strip()
    source_hashes={p:fingerprint(ROOT/p)['sha256']for p in OWN};transitive=transitive_hashes()
    compiler={'executable':fingerprint(BEND),'version':subprocess.run([str(BEND),'version'],capture_output=True,text=True,check=True).stdout.strip(),'c_compiler':fingerprint(pathlib.Path('/usr/bin/clang')),'c_compiler_version':subprocess.run(['/usr/bin/clang','--version'],capture_output=True,text=True,check=True).stdout.strip()}
    (P.DIR/'source-manifest.json').write_bytes(canonical(source_hashes))
    prepared={'schema':1,'pin':'26.3','result':'prepared_native_pending','source_sha256':source_hashes,'transitive_bend_source_sha256':transitive,'compiler_generation':compiler,'ordinary_checks':checks,'java_runs':[j1,j2],'summary':ref['summary'],'reference_cases_sha256':ref['cases_sha256']}
    write_json(ROOT/'evidence/model-choice-tests.json',prepared)
    if args.prepare_only:print(json.dumps({'result':'prepared_native_pending','summary':ref['summary']}));return
    if not args.no_build:
        cmd=[str(BEND),'tests/model_choice.bend','-o',str(BIN)];commands.append(cmd);started=time.monotonic()
        with(P.DIR/'native-build.log').open('w')as log:
            child=subprocess.Popen(cmd,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
            print(json.dumps({'native_build_pid':child.pid,'timeout_seconds':args.build_timeout,'source_sha256':source_hashes,'transitive_count':len(transitive)}),flush=True)
            try:status=child.wait(timeout=args.build_timeout)
            except subprocess.TimeoutExpired:
                child.kill();child.wait();status='timeout'
        checks['native_build_seconds']=time.monotonic()-started
        receipt={'command':cmd,'pid':child.pid,'timeout_seconds':args.build_timeout,'status':status,'wall_seconds':checks['native_build_seconds'],'source_sha256':source_hashes,'transitive_bend_source_sha256':transitive,'compiler_generation':compiler,'log':fingerprint(P.DIR/'native-build.log')}
        if status==0:receipt['binary']=fingerprint(BIN)
        write_json(P.DIR/'native-build-receipt.json',receipt)
        if status!=0:
            write_json(ROOT/'evidence/model-choice-tests.json',prepared|{'result':'native_build_failed','native_build_receipt':receipt});raise RuntimeError('Native build failed: '+str(status))
    receipt=json.loads((P.DIR/'native-build-receipt.json').read_text())
    require(receipt['status']==0 and receipt['source_sha256']==source_hashes and receipt['transitive_bend_source_sha256']==transitive and receipt['compiler_generation']==compiler and receipt['binary']==fingerprint(BIN),'Stale native build receipt')
    require(source_hashes=={p:fingerprint(ROOT/p)['sha256']for p in OWN}and transitive==transitive_hashes(),'Source changed during build/test')
    cases=[(c['input'],expected(c))for c in ref['cases']]+defensive_cases(ref)
    want=[line for c,lines in cases for line in lines];actual=run_native(cases);again=run_native(cases);compare(actual,want);compare(again,want)
    positions=[f'{p["id"]}|position|{p["x"]&0xffffffff}|{p["y"]&0xffffffff}|{p["z"]&0xffffffff}'for p in ref['positions']]
    run=subprocess.run([str(BIN),'--gpu','off','--threads','1',*positions],capture_output=True,text=True,check=True,timeout=60);compare(run.stdout.splitlines(),[p['id']+'|'+','.join(map(str,p['default_seed']))for p in ref['positions']])
    if args.selftest:
        for name,needle,replacement in [('raw_state',stext(ref['cases'][0]['observed']['outcomes'][0]['after']),'l,0,0,0,0'),('chosen_variant','test:m0','test:other'),('multipart_seed','|ok|','|ok|0,0'),('missing_selection',',0,0,0,0','')]:
            bad=want.copy();idx=next(i for i,line in enumerate(bad)if needle in line);bad[idx]=bad[idx].replace(needle,replacement,1)
            try:compare(actual,bad)
            except ValueError:rejected.append('observation_'+name)
            else:raise AssertionError('Altered observation accepted: '+name)
    evidence=prepared|{'result':'passed_selection_boundary','native_cases':len(cases),'native_observations':len(actual),'defensive_cases':len(cases)-len(ref['cases']),'position_observations':len(positions),'native_binary':fingerprint(BIN),'native_build_receipt':receipt,'native_reproduced':True,'corruption_rejections':rejected,'commands':commands,'checks':checks,'kernel':'Not yet attempted; queued separately under lead build policy','scope':'Production selection/seed/random-consumption boundary given already-instantiated typed roots; marker parts are identity metadata, not Java geometry baking; whole-source rollback/fuel/error validation are explicit Bend extensions.'}
    write_json(ROOT/'evidence/model-choice-tests.json',evidence);print(json.dumps({k:evidence[k]for k in ['result','native_cases','native_observations','defensive_cases','position_observations','corruption_rejections']},sort_keys=True))

if __name__=='__main__':main()
