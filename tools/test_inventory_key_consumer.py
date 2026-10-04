#!/usr/bin/env python3
"""Observe the production AppKit channel and execute the real Bend menu join.

Host code supplies literal expectations and translates captured Base event words;
profile semantics, coordinate mapping, authority retention and requests are Bend.
"""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import build_native as B
import test_fall_reset_world_continuation_r2 as R
import test_player_inventory_screen as Screen

ROOT = Path(__file__).resolve().parents[1]
BASE = Path.home()/'.bend/bend2/effs/window.c'
BEND = Path.home()/'.bend/bin/bend'
BASE_SHA = '617611d994fb7f4c57467f8d1a7e644ba19d4fce35770613dea2711e6cafd65c'
sha = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()

def sources():
    snapshot = B.Snapshot()
    B.source_graph(ROOT/'tests/inventory_key_consumer.bend',BEND.parent.parent/'bend2/base.bend',os.environ,snapshot)
    paths = [Path(row['path']) for row in snapshot.files.values()]
    paths += [BASE,ROOT/'src/native/player_presentation.c',ROOT/'src/native/player_presentation.js',
        ROOT/'src/player_presentation_native.bend',ROOT/'src/remote_resource_presenter.bend',
        ROOT/'tests/inventory_key_consumer.m',Path(__file__),ROOT/'tools/inventory_key_consumer_proof.mjs',
        ROOT/'src/inventory_key_consumer_laws.bend',ROOT/'src/inventory_key_consumer_proof.bend',
        ROOT/'reference/player_inventory_click_gui.json']
    return {str(p):sha(p) for p in dict.fromkeys(paths)}

def compile_boundary(work,execute):
    assert sha(BASE)==BASE_SHA,'Base Window dependency changed'
    base = BASE.read_text()
    view = base[base.index('@interface BendView'):base.index('static id<MTLDevice> window_dev;')]
    translate = lambda text: re.sub(r'CID\(([A-Za-z0-9_.]+)\)',lambda m:'CID_'+m[1].replace('.','_').upper(),text)
    text = (ROOT/'tests/inventory_key_consumer.m').read_text().replace('// MC_BASE_SOURCE',translate(view)).replace(
        '// MC_ADAPTER_SOURCE',translate((ROOT/'src/native/player_presentation.c').read_text()))
    source = work/'boundary.m';source.write_text(text)
    binary = work/'boundary'
    execute('native-adapter-build',['/usr/bin/clang','-x','objective-c','-fobjc-arc','-fmodules','-O1',
        '-framework','AppKit','-framework','QuartzCore',str(source),'-o',str(binary)],60)
    out,receipt = execute('hidden-native-adapter',[str(binary)],60,{**os.environ,'BEND_MINECRAFT_LAUNCH_MODE':'hidden'})
    rows = [json.loads(line) for line in out.splitlines() if line.strip()]
    status=rows[-1];assert status['status']=='passed' and status['space_changes']==0
    assert status['window_visible'] is False and status['window_key'] is False and status['app_active'] is False
    observed=rows[:-1]
    def flatten(events):return [word for event in events for word in event]
    def key_words(key,char,down):return [5,2147549184+key,down,0,0],[5,char,down,0,0]
    expected={}
    expected['physical-f-alternate-character']=flatten([[7,105,97,0,0],*key_words(3,113,1),*key_words(3,113,0)])
    for i,key in enumerate([18,19,20,21,23,22,26,28,25]):
        expected[f'physical-digit-{i}']=flatten([[7,105,97,0,0],*key_words(key,119,1),*key_words(key,119,0)])
    expected['rebound-q-character-f']=flatten([[7,105,97,0,0],*key_words(12,102,1),*key_words(12,102,0)])
    expected['duplicate-logical-holds']=flatten([[5,2147549187,1,0,0],[5,113,1,0,0],[5,2147483666,1,0,0],
        [5,2147483651,0,0,0],[5,2147549202,0,0,0],[5,113,0,0,0]])
    expected['focus-loss-release']=flatten([[5,2147483651,0,0,0],[5,2147483666,0,0,0],[5,113,0,0,0],[5,119,0,0,0]])
    expected['escape-empty-character']=flatten([*key_words(53,65589,1),*key_words(53,65589,0)])
    assert {r['case']:r['words'] for r in observed}==expected,('physical channel differs from literal expected event words',observed)
    return observed,{'status':status,'process':receipt,'binary_sha256':sha(binary),'source_sha256':sha(source)}

def native_events(words):
    assert len(words)%5==0
    result=[]
    for i in range(0,len(words),5):
        kind,a,b,c,d=words[i:i+5]
        if kind==5: result.append([0,a,b])
        elif kind==7: result.append([1,a,b])
        else: raise AssertionError(('unhandled captured event',kind))
    return result

def cases(observed):
    result=[]
    hovered={'hover':{'slot':10},'hover_viewport':[320,180,640,360]}
    def add(label,events,*,mode=0,opened=1,tab=0,focused=1,captured=0,carried=0,physical=1,swap=None,
            intents=None,world=None,query=None,controller=None):
        ident=len(result)
        expected=Screen.authority(bool(opened));expected[4]=Screen.stack('minecraft:dirt',3) if carried else [0]
        args=[ident,mode,opened,tab,focused,captured,carried,physical,*[v for event in events for v in event]]
        expected_controller={'open':bool(opened and focused),'keys':0,'buttons':0,
            'captured':bool(captured and focused),'focused':bool(focused),'pending':0,'tab':tab,
            'row':0,'query':query or '', 'hover':'outside','hover_viewport':None,
            'source':None,'offer':None,'notice':'ready'}
        if swap is not None:expected_controller.update(hovered,pending=3,notice='waiting')
        if controller:expected_controller.update(controller)
        result.append({'label':label,'id':ident,'argument':'|'.join(map(str,args)),
            'authority':expected,'physical':physical,'swap':swap,'intents':intents,'world':world,
            'query':query,'controller':expected_controller})
    for row in observed:
        label=row['case'];events=native_events(row['words'])
        swap=40 if label=='physical-f-alternate-character' else (
            int(label.rsplit('-',1)[1]) if label.startswith('physical-digit-') else None)
        mode=1 if label=='rebound-q-character-f' else 0
        if mode:swap=40
        expected_intents=['release',{'capture':False},'close'] if label=='escape-empty-character' else (
            [{'swap':[10,swap]}] if swap is not None else [])
        add('captured/'+label,events,mode=mode,swap=swap,intents=expected_intents,world=[],
            controller={'pending':2,'notice':'waiting'} if label=='escape-empty-character' else None)
        add('actual-hidden-focus/'+label,events,mode=mode,focused=0,
            intents=['release',{'capture':False}],world=[])
    move=[1,105,97]
    pair=lambda key,char,down=1:[[0,2147549184+key,down],[0,char,down]]
    for i,key in enumerate([18,19,20,21,23,22,26,28,25]):
        add(f'world-digit-{i}',[move,*pair(key,119),*pair(key,119,0)],opened=0,tab=3,
            intents=[],world=[[1,210,194],[0,49+i,True],[0,49+i,False]])
    add('world-f-not-invented-menu',[move,*pair(3,119),*pair(3,119,0)],opened=0,intents=[],
        world=[[1,210,194],[0,70,True],[0,70,False]])
    add('search-character-f-position',pair(3,113),tab=3,intents=[],world=[],query='q')
    # The existing search is an item-identifier filter: punctuation outside
    # [A-Za-z0-9_./:-] is deliberately refused after physical-text routing.
    add('search-rejects-nonidentifier-punctuation',pair(18,33),tab=3,intents=[],world=[],query='')
    add('search-logical-f',[[0,102,1]],tab=3,intents=[],world=[],query='f',controller={'keys':2048})
    add('default-offhand-unbound-after-rebind',[move,*pair(3,102)],mode=1,intents=[],world=[],controller=hovered)
    add('unbound-profile',[move,*pair(3,102)],mode=2,intents=[],world=[],controller=hovered)
    add('duplicate-binding-offhand-priority',[move,*pair(3,102)],mode=3,swap=40,
        intents=[{'swap':[10,40]}],world=[],controller={'keys':2048})
    add('carried-prevents-gui-swap',[move,*pair(3,102)],carried=1,intents=[],world=[],controller={**hovered,'keys':2048})
    # The packet and each of its two admitted events observe the same actual
    # captured status. Every open-menu observation requires release; consuming
    # the paired character leaves Move and the physical F event.
    add('capture-prevents-gui-swap',[move,*pair(3,102)],captured=1,
        intents=['release',{'capture':False}]*3,world=[],controller={'keys':2048})
    add('legacy-character-channel',[move,[0,102,1]],physical=0,swap=40,
        intents=[{'swap':[10,40]}],world=[],controller={'keys':2048})
    add('paired-tag-does-not-delete-move',[[0,2147549187,1],[1,13,17]],opened=0,intents=[],
        world=[[0,70,True],[1,26,34]],controller={'keys':2048})
    add('no-hover-prevents-swap',pair(3,102),intents=[],world=[],controller={'keys':2048})
    add('synthetic-accepted-reply-keeps-held-key',[move,*pair(3,113)],physical=2,intents=[],world=[],
        controller={**hovered,'keys':2048})
    result[-1]['authority'][-1]=12
    add('synthetic-refused-reply-keeps-held-key',[move,*pair(3,113)],physical=3,intents=[],world=[],
        controller={**hovered,'keys':2048,'notice':'rejected'})
    add('logical-shortcut-does-not-double-dispatch',[move,*pair(3,102),[0,102,1]],swap=40,
        intents=[{'swap':[10,40]}],world=[],controller={'keys':2048})
    return result

def compare(output,corpus):
    rows=[json.loads(line) for line in output.splitlines() if line.strip()]
    assert len(rows)==len(corpus),(len(rows),len(corpus))
    for row,case in zip(rows,corpus):
        label=case['label'];assert row['id']==case['id'],label
        assert row['authority']==case['authority'],('full authority drift',label,row)
        assert row['controller']==case['controller'],('complete controller',label,row)
        assert row['catalog_count']==3,('catalog retention',label,row)
        if case['intents'] is not None:assert row['intents']==case['intents'],('intents',label,row)
        if case['world'] is not None:assert row['world']==case['world'],('world',label,row)
        if case['query'] is not None:assert row['controller']['query']==case['query'],('query',label,row)
        if case['swap'] is not None:
            assert row['wire']==[[11,10,[2,case['swap']]]],('actual typed wire command',label,row)
            assert row['controller']['pending']==3 and row['controller']['notice']=='waiting',label
            assert row['controller']['source'] is None and row['controller']['offer'] is None,label
    return {'cases':len(rows),'full_received_authority_comparisons':len(rows),
        'complete_controller_comparisons':len(rows),'catalog_count_comparisons':len(rows),
        'captured_native_rows':sum(c['label'].startswith('captured/') for c in corpus),
        'actual_hidden_focus_refusals':sum(c['label'].startswith('actual-hidden-focus/') for c in corpus),
        'scope':'actual native event buffer → production coordinate mapping → physical bindings → full menu controller → typed wire command',
        'pending':['actor013 accepted correlated Swap reply','visible OS input/capture/presentation','user-facing binding settings UI']}

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--mode',choices=['source','proof','boundary','native','cached-native','build-child'],required=True)
    parser.add_argument('--work',type=Path,required=True);parser.add_argument('--c-source',type=Path);args=parser.parse_args();work=args.work.resolve()
    if args.mode=='build-child':
        with R.retry_scope(B):report=B.ensure_native(ROOT/'tests/inventory_key_consumer.bend',work/'consumer-native',bend=str(BEND),cache_dir=work/'native-cache',force=False)
        assert report['retries']==0
        (work/'native-build.json').write_text(json.dumps(report,indent=2)+'\n');return
    work.mkdir(parents=True,exist_ok=False)
    pins=({str(p):sha(p) for p in [BASE,ROOT/'src/native/player_presentation.c',ROOT/'tests/inventory_key_consumer.m',Path(__file__)]}
        if args.mode=='boundary' else sources())
    def stable(label):
        assert all(sha(p)==digest for p,digest in pins.items()),'input changed: '+label
        return True
    (work/'initial-source-pins.json').write_text(json.dumps(pins,indent=2)+'\n')
    journal=work/'owned-groups.jsonl';journal.touch(exist_ok=False)
    with R.bindings(R,{'JOURNAL':journal,'GROUPS':[],'LAST_EXECUTION':None}),R.bindings(R.F,{'ATTEMPT':work,'LAST_EXECUTION':None}),R.parent_cleanup(work):
        def execute(label,argv,cap,env=None,foreign=False):
            out,err,receipt,pin=R.execute_process(list(map(str,argv)),label,cap,env=env,_admit=stable)
            if foreign:
                assert receipt['status']=='failed' and re.fullmatch(r'SOME PROOFS FAIL\nError: \d+ defs rely on unsafe or foreign code:\n(?:- [^\n]+\n)+\n?',err)
            else:assert receipt['status']=='passed',(label,receipt,err)
            return out,{'receipt':pin,'seconds':receipt['seconds'],'stderr_sha256':hashlib.sha256(err.encode()).hexdigest()}
        result={'status':'passed','mode':args.mode,'source_pins':pins,'sources_unchanged':True,
            'ownership':'local controller and received immutable authority only; actor013/visible OS acceptance pending'}
        if args.mode=='source':
            receipts=[]
            for entry in ['tests/inventory_key_consumer.bend','src/inventory_key_consumer_proof.bend','src/remote_resource_presenter.bend']:
                _,r=execute(Path(entry).stem,[BEND,ROOT/entry,'--check-only'],60,foreign=entry.endswith('remote_resource_presenter.bend'));receipts.append(r)
            result['checks']=receipts
        elif args.mode=='boundary':
            observed,boundary=compile_boundary(work,execute)
            result.update(boundary=boundary,captured_native_events=observed)
        elif args.mode=='proof':
            _,export=execute('export',['/opt/homebrew/bin/node','--stack-size=4096','--max-old-space-size=4096',
                '--experimental-transform-types',ROOT/'tools/inventory_key_consumer_proof.mjs',work],120)
            _,kernel=execute('kernel',[Path.home()/'.bend/bendtt/e15042434e73aab0/bendtt',work/'selected.bendtt'],60,
                {**os.environ,'LEAN_STACK_SIZE_KB':'4194304'})
            result.update(export=export,kernel=kernel,selection=json.loads((work/'selection.json').read_text()),
                emitted_sha256=sha(work/'selected.bendtt'),scope=json.loads((work/'scope.json').read_text()))
        else:
            if args.mode=='cached-native':
                assert args.c_source is not None
                source=args.c_source.resolve();manifest=json.loads(source.with_name('manifest.json').read_text())
                assert sha(source)==manifest['sha256']
                snapshot,context,effective_env=B._collect(ROOT/'tests/inventory_key_consumer.bend',BEND,dict(os.environ))
                assert B.digest(B.encoded(context))==manifest['prekey'],'cached C does not match current exact production/compiler/environment'
                B.guard_route(source.read_text())
                boundary_record=json.loads((ROOT/'build/inventory-key-consumer/boundary-001/receipt.json').read_text())
                for p in [BASE,ROOT/'src/native/player_presentation.c',ROOT/'tests/inventory_key_consumer.m']:
                    assert sha(p)==boundary_record['source_pins'][str(p)]
                observed,boundary=boundary_record['captured_native_events'],boundary_record['boundary']
                artifact=work/'consumer-native';compiler=Path(context['compiler']['path'])
                main_source=ROOT.parent/'bend/bend2/main.ts'
                (work/'cached-source-verification.json').write_text(json.dumps({'prekey':manifest['prekey'],
                    'C_sha256':sha(source),'C_bytes':source.stat().st_size,'C_path':str(source),'context':context,
                    'source_manifest':snapshot.manifest(),'cli_build_source':str(main_source),'cli_build_sha256':sha(main_source)},indent=2)+'\n')
                _,compiled=execute('cached-C-clang',[compiler,'-std=c11','-O3',source,'-lpthread','-lm','-o',artifact],120,effective_env)
                after,after_context,_=B._collect(ROOT/'tests/inventory_key_consumer.bend',BEND,dict(os.environ))
                assert B.digest(B.encoded(after_context))==manifest['prekey'] and snapshot.stamps==after.stamps
                assert sha(source)==manifest['sha256']
                build={'artifact':str(artifact),'binary_sha256':sha(artifact),'binary_bytes':artifact.stat().st_size,
                    'route':'exact cached ordinary C, original cli_build CPU clang arguments; no re-emission',
                    'compile':compiled,'retries':0,'C_sha256':sha(source),'matching_prekey':manifest['prekey']}
            else:
                observed,boundary=compile_boundary(work,execute)
                execute('consumer-native-build',[sys.executable,Path(__file__),'--mode','build-child','--work',work],600)
                build=json.loads((work/'native-build.json').read_text());artifact=Path(build['artifact'])
            corpus=cases(observed)
            (work/'cases.json').write_text(json.dumps(corpus,indent=2)+'\n')
            output,run=execute('consumer-cases',[artifact,'--gpu','off','--threads','1',*[row['argument'] for row in corpus]],60)
            result.update(boundary=boundary,comparison=compare(output,corpus),run=run,build=build,
                captured_native_events=observed,binary_sha256=sha(artifact))
        stable('after')
        (work/'receipt.json').write_text(json.dumps(result,indent=2)+'\n')
        print(json.dumps({'status':result['status'],'mode':args.mode,'work':str(work),'comparison':result.get('comparison')}))

if __name__=='__main__':
    try:main()
    except BaseException as error:
        print(json.dumps({'status':'failed','error_type':type(error).__name__,'detail':str(error)[:900]}),file=sys.stderr)
        raise SystemExit(1)
