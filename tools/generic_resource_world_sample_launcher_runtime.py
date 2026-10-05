#!/usr/bin/env python3
"""Run the adopted public shell with existing native/desktop/actor owners.

No build, new simulation, substituted resource, or foreground input. Reuse the
existing independently authored Core/Local/inventory fixtures and exact save
encoder. The shell itself performs renderer launch, MenuClose and world.save.
"""
from __future__ import annotations
import argparse, copy, csv, json, os, re, shlex, socket, stat, sys
from pathlib import Path

PYTHON=Path.home()/'.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3'
if Path(sys.executable).resolve()!=PYTHON.resolve():
    os.execv(str(PYTHON),[str(PYTHON),'-B',__file__,*sys.argv[1:]])
sys.dont_write_bytecode=True
import generic_resource_world_sample_client_runtime as G
import test_world_generation_settings as Generation
Inventory=G.Boundary.Inventory

ROOT=G.ROOT
ACTOR=ROOT/'build/compiler-producer-diagnostic-017/actor'
CLIENT=ROOT/'build/generic-resource-world-sample-client-native/009/renderer'
LAUNCH=ROOT/'tools/play_minecraft.sh'
CLOSE=ROOT/'tools/play_minecraft_close.py'
ACTOR_SHA='66bbe97279f8ee268d891ad762d5da40337e1c318d09160e415823e25d4d8bd5'
CLIENT_SHA='17e93095938731a1df4f8d94de56b0524477d5bfa239ed845e829145ec9c2b0a'
require,pin,exclusive=G.require,G.pin,G.exclusive
S,R=G.S,G.R

def complete_saved(path, expected_full=None, record=None, *, fresh=False):
    data=path.read_bytes();identity,count,_=S.P.registry_identity(S.P.OFFICIAL)
    outer=S.N.Reader(data,max_bytes=16846848,max_depth=6,max_elements=16846848).root()
    S.require(outer.name==S.N.text('bendex:bundle'),'Saved bundle identity')
    fields=S.WC.fields(outer.value,S.BUNDLE_FIELDS)
    S.require(fields['format']==S.WC.integer(1) and S.WC.scalar_text(fields['minecraft'])=='26.3' and S.WC.scalar_text(fields['registry'])==identity and fields['peer_highwater']==S.WC.integer(2 if fresh else 42),'Complete saved bundle metadata')
    core=S.WC.validate(S.N.parse(fields['core'].payload),count,identity)
    S.require(S.P.canonical_expected(core)==fields['core'].payload,'Complete canonical Core bytes')
    extension=S.WC.fields(fields['extension'],S.EXTENSION_FIELDS)
    S.require(S.WC.scalar_text(extension['namespace'])==S.NAMESPACE and extension['schema']==S.WC.integer(1),'Complete saved extension metadata')
    local,full=Inventory.parse_inventory_full(bytes(extension['payload'].payload))
    actual_record=S.decode_local(local)
    S.require(S.local_bytes(actual_record)==local,'Complete canonical LocalPlayer bytes')
    if record is not None:S.require(actual_record==record,'Loaded complete LocalPlayer retention')
    if expected_full is not None:S.require(full==expected_full,'Complete43 slots/raw status/generation')
    if fresh:
        S.require(full['main']==G.Boundary.P.playable_inventory() and full['equipment']==[None]*7 and full['status']=={'invulnerable':True,'mayfly':True,'flying':False,'walking_speed':1036831949,'flying_speed':1028443341} and full['generation']==Generation.stone_dirt_bytes(),'Fresh creative v3 defaults')
        S.require(core['tick']>0 and actual_record.count==core['tick'] and core['paused'] is False and core['day_time']==core['tick'],'Fresh actual unpaused cadence')
    palette={}
    with S.P.OFFICIAL.open(newline='') as source:
        for row in csv.DictReader(source,delimiter='\t'):
            if row['identifier'] in ('minecraft:air','minecraft:stone','minecraft:dirt'):palette[row['identifier']]=int(row['default_state_id'])
    expected=[]
    for x in (-16,0):
        for y in range(-80,336,16):
            for z in (-16,0):
                cells=(palette['minecraft:air'],)*4096
                if y==-64:cells=tuple(palette['minecraft:'+name] for name in ('stone','dirt','dirt','stone') for _ in range(256))+(palette['minecraft:air'],)*3072
                expected.append({'key':S.BASE.section_key(x,y,z),'cells':cells})
    expected.sort(key=lambda section:section['key'])
    expected_events=[{'stamp':(0,0,0),'kind':0,'revision':1}] if fresh else []
    S.require(core['sections']==expected and core['revision']==1 and not core['pending'] and core['events']==expected_events,'Every cell of104 saved demand sections and retained event history')
    return {'bundle':R.pin(path),'sections':len(expected),'tick':core['tick'],'full43_and_status':True,'generation_sha256':S.sha(full['generation'])},full


def observed(directory, arguments, expected_status, expected_frames, *, expected_markers=None):
    out,err=directory/'stdout',directory/'stderr'
    images=directory/'images'; images.mkdir()
    observer=G.Pair.observer()['observer']['artifact']
    with G.mock.patch.dict(os.environ,{'BEND_MINECRAFT_LAUNCH_MODE':'hidden',
            'BEND_MINECRAFT_FRAME_DIR':str(images)}),G.Host.bindings(G.R,{'WORK':directory}):
        process=G.R.bounded([observer,str(LAUNCH),str(out),str(err),*arguments],90,'observed-launch')
    G.R.process_ok(process)
    rows=[json.loads(line) for line in Path(process['stdout']['path']).read_text().splitlines() if line.strip()]
    report=rows[-1]
    require(not report['timed_out'] and report['child_status']==expected_status,
            'Actual shell exit differs: '+err.read_text())
    require(report['before_frontmost_pid']>0 and report['before_frontmost_pid']==report['after_frontmost_pid']
            and report['sampled_frontmost_pids']==[report['before_frontmost_pid']]
            and report['space_change_notifications']==0 and not report['activation_notification_pids'],
            'Focus/Spaces changed')
    text=out.read_text();markers=[line for line in text.splitlines() if line.startswith('catalog.frame|')]
    timings=[line for line in text.splitlines() if line.startswith('client.timing|')]
    require(len(markers)==(expected_frames if expected_markers is None else expected_markers)
            and len(timings)==expected_frames,'Actual Generic frame/timing loop absent')
    events=G.R.PC.events(out)
    closes=[v for v in events if v.get('event')=='client.menu-close']
    saves=[v for v in events if v.get('event')=='client.save']
    require(len(closes)==1 and closes[0]['sequence']==1,'Actual public-shell correlated MenuClose')
    ppms=[]
    for serial in range(expected_frames):
        p=images/(str(serial)+'.ppm');raw=p.read_bytes();words=raw.split(b'\n',3)
        require(len(words)==4 and words[0]==b'P6' and words[2]==b'255','Actual returned CPU image PPM')
        width,height=map(int,words[1].split())
        require(len(words[3])==width*height*3,'Returned image cardinality')
        ppms.append({'serial':serial,'extent':[width,height],'PPM':pin(p)})
    return {'observer':report,'process':process,'frame_markers':markers,'timings':timings,
            'closes':closes,'saves':saves,'PPMs':ppms,'stdout':pin(out),'stderr':pin(err)},out,err


def connection_file(directory,actor,path):
    result=directory/'connection.env'
    values={'MC_ACTOR_PID':actor.process.pid,'MC_LIVE_PORT':actor.port,'MC_RENDER_PORT':actor.private_port,
        'MC_RENDER_TOKEN':actor.token,'MC_RENDER_EPOCH':'generic-launcher-test','MC_DEV_TOKEN':G.S.MCP.TOKEN,
        'MC_WORLD_PATH':path,'BEND_MINECRAFT_LAUNCH_MODE':'hidden'}
    result.write_text(''.join('export '+k+'='+shlex.quote(str(v))+'\n' for k,v in values.items()))
    result.chmod(0o600)
    return result


def command(control,value):
    reply=control.call(value,6)
    require(reply[4] is True,'Actual fixture/recovery command refused: '+str(value))
    return reply[6]


def capacity_fixture(control,full):
    command(control,[9])
    for index in range(36):command(control,[7,index,['minecraft:dirt',''],64])
    command(control,[11,44,[0,0]]);command(control,[11,45,[0,0]])
    command(control,[7,8,['minecraft:dirt',''],64])
    command(control,[7,0,['minecraft:stone',''],3]);command(control,[11,36,[0,0]])
    command(control,[11,1,[0,0]]);command(control,[7,0,['minecraft:dirt',''],64])
    command(control,[7,0,['minecraft:stone',''],17]);command(control,[11,36,[0,0]])
    before=command(control,[7,0,['minecraft:dirt',''],64])
    full['main']['slots']=[Inventory.stack('minecraft:dirt',64) for _ in range(36)]
    full['equipment'][4]=Inventory.stack('minecraft:dirt',64)
    expected=G.Boundary.authority(full,{'craft':[Inventory.stack('minecraft:stone',3),None,None,None],
            'carried':Inventory.stack('minecraft:stone',17),'result':None,'opened':True,'revision':5})
    expected[5]=[1,[1,'minecraft:stone_button','',1]]
    require(before==expected,'Independent complete capacity authority with original stone-button preview')
    return before


def fresh(directory):
    path=directory/'world.nbt';public,private=G.S.MCP.free_port(),G.S.MCP.free_port()
    while private==public:private=G.S.MCP.free_port()
    removed={k:os.environ.pop(k,None) for k in ('MC_RENDER_TOKEN','MC_RENDER_EPOCH','MC_DEV_TOKEN','MC_ACTOR_PID')}
    try:
      with G.mock.patch.dict(os.environ,{'MC_WORLD_PATH':str(path),'MC_LIVE_PORT':str(public),'MC_RENDER_PORT':str(private)}):
        report,out,err=observed(directory,['--frames','2','--width','1920','--height','1080',
                                         '--hud-scale','0','--render-scale','100'],0,2)
    finally:
      for k,v in removed.items():
        if v is not None:os.environ[k]=v
    require(err.read_text().strip()=='client closed','Unexpected successful renderer diagnostic')
    require(report['closes'][0]['accepted'] is True and len(report['saves'])==1,'Actual durable close/save absent')
    require(all(v['extent']==[1920,1080] for v in report['PPMs']),'Normal requested full output dimensions')
    saved,_=complete_saved(path,fresh=True)
    require(report['saves'][0]['result']=={'status':'durable','published':True,'durable':True,
            'bytes':path.stat().st_size,'peer_highwater':2},'Actual fresh durable acknowledgement')
    for port in (public,private):
        with socket.socket() as probe:
            probe.settimeout(.5);require(probe.connect_ex(('127.0.0.1',port))!=0,'Shell shutdown retained listener')
    return {'fresh':report,'saved':saved,'listeners_absent':True,
            'scope':'Two actual1920x1080 returned CPU images; full dimensions/cadence/save, not full1080 RGB or drawable parity.'}


def capacity(directory):
    data=G.fixture();full=copy.deepcopy(data['full'])
    full['main']['slots']=[None]*36;full['main']['selected']=7;full['equipment']=[None]*7
    path=directory/'world.nbt';initial=G.Boundary.bundle(data['world'],40,data['record'],full,'')
    path.write_bytes(initial)
    actor=G.backend(ACTOR,'backend-capacity',path);control=None
    try:
        control=G.Boundary.connect(actor);before=capacity_fixture(control,full)
        control.call([2],2);control.close();control=None
        connection=connection_file(directory,actor,path)
        first=directory/'refused';first.mkdir()
        refused,out,err=observed(first,['--reconnect',str(connection),'--frames','1',
                              '--width','320','--height','180','--hud-scale','1','--render-scale','100'],2,1)
        require(refused['closes'][0]['accepted'] is False and refused['closes'][0]['menu']==before
                and not refused['saves'] and path.read_bytes()==initial,'Refusal changed owner/durable bytes or claimed save')
        require(actor.process.poll() is None,'Refusal failed to retain actual actor')
        match=re.search(r"--reconnect '([^']+)'",err.read_text());require(match is not None,'Missing actual reconnect route')
        retained=Path(match.group(1));require(stat.S_IMODE(retained.stat().st_mode)==0o600,'Retained connection is not0600')
        prior_pid=actor.process.pid
        control=G.Boundary.connect(actor)
        require(control.call([8],6)[6]==before,'Retained whole menu authority')
        freed=command(control,[7,0,['minecraft:dirt',''],0])
        expected_freed=copy.deepcopy(before);expected_freed[0][3][0]=[0]
        require(freed==expected_freed,'Actual zero-count acquire must free one main slot without other changes')
        control.call([2],2);control.close();control=None
        second=directory/'recovered';second.mkdir()
        recovered,out,err=observed(second,['--reconnect',str(retained),'--frames','1',
                    '--width','320','--height','180','--hud-scale','1','--render-scale','100'],0,1)
        require(err.read_text().strip()=='client closed','Unexpected successful reconnect diagnostic')
        full['main']['slots'][0]=Inventory.stack('minecraft:stone',20)
        after=G.Boundary.authority(full,{'craft':[None]*4,'carried':None,'result':None,'opened':False,'revision':6})
        require(recovered['closes'][0]['accepted'] is True and recovered['closes'][0]['menu']==after
                and len(recovered['saves'])==1,'Same retained actor did not return all temporary items on close')
        expected=G.Boundary.bundle(data['world'],42,data['record'],full,'')
        require(path.read_bytes()==expected,'Complete independent104section/43slot/status/WG/clock save differs')
        require(recovered['saves'][0]['result']=={'status':'durable','published':True,'durable':True,
                'bytes':len(expected),'peer_highwater':42},'Exact reconnect durable acknowledgement')
        return {'refused':refused,'recovered':recovered,'retained_actor_pid':prior_pid,
                'same_retained_actor_reconnected':True,'recovery_permissions':'0600',
                'refusal_complete_owner_and_old_bytes_preserved':True,'complete_after_menu':after,
                'saved':pin(path),'independent_expected_sha256':G.digest(expected),
                'real_recovery_command':[7,0,['minecraft:dirt',''],0]}
    finally:
        if control is not None:control.close()
        if actor.process.poll() is None:
            G.R.finish_backend(actor)
        else:
            # The public shell deliberately sends TERM after durable save.
            # The reused stdin-stop owner must reap it without asserting its
            # own different successful stdin-stop status/diagnostic.
            actor.stop(failed=True)
            ended=json.loads((actor.directory/'process.json').read_text())
            require(ended['exit_code']==-15 and ended['group_absent']
                    and all(ended['listeners_absent']) and not ended['errors'],
                    'Actual public-shell TERM/reap/listener teardown')


def finish_retained_fresh(directory):
    require(json.loads((directory/'first-failure.json').read_text())['message']==
            "name 'csv' is not defined", 'Only the retained final verifier import failure may finish')
    process=json.loads((directory/'observed-launch/result.full.json').read_text())
    G.R.process_ok(process)
    rows=[json.loads(v) for v in Path(process['stdout']['path']).read_text().splitlines() if v.strip()]
    observer=rows[-1]
    require(observer['child_status']==0 and not observer['timed_out']
        and observer['before_frontmost_pid']>0
        and observer['before_frontmost_pid']==observer['after_frontmost_pid']
        and observer['sampled_frontmost_pids']==[observer['before_frontmost_pid']]
        and not observer['activation_notification_pids'] and observer['space_change_notifications']==0
        and process['cleanup']['live_group_absent'], 'Retained actual shell/OS/cleanup verdict differs')
    out,err=directory/'stdout',directory/'stderr';text=out.read_text()
    require(err.read_text().strip()=='client closed','Retained successful renderer diagnostic')
    markers=[v for v in text.splitlines() if v.startswith('catalog.frame|')]
    timings=[v for v in text.splitlines() if v.startswith('client.timing|')]
    require(len(markers)==len(timings)==2,'Retained actual two-frame loop')
    events=G.R.PC.events(out);closes=[v for v in events if v.get('event')=='client.menu-close']
    saves=[v for v in events if v.get('event')=='client.save'];path=directory/'world.nbt'
    require(len(closes)==len(saves)==1 and closes[0]['accepted'] is True and closes[0]['sequence']==1
            and saves[0]['path']==str(path), 'Retained public-shell close/save events')
    ppms=[]
    for serial in range(2):
        ppm=directory/'images'/f'{serial}.ppm';raw=ppm.read_bytes()
        require(raw.startswith(b'P6\n1920 1080\n255\n')
                and len(raw)==len(b'P6\n1920 1080\n255\n')+1920*1080*3, 'Retained returned CPU image extent')
        ppms.append({'serial':serial,'extent':[1920,1080],'PPM':pin(ppm)})
    saved,_=complete_saved(path,fresh=True)
    require(saves[0]['result']=={'status':'durable','published':True,'durable':True,
             'bytes':path.stat().st_size,'peer_highwater':2},'Retained fresh durable acknowledgement')
    logs=list(CLIENT.parent.glob('current-launch.*'))
    require(len(logs)==1,'Retained fresh listener logs must be unambiguous before another shell run')
    ready=[json.loads(v) for v in (logs[0]/'actor.stdout').read_text().splitlines() if v.strip()]
    ports=[v['port'] for v in ready if v.get('event') in ('server.ready','renderer.ready')]
    require(len(ports)==2, 'Retained actual listener identities')
    for port in ports:
        with socket.socket() as probe:
            probe.settimeout(.5);require(probe.connect_ex(('127.0.0.1',port))!=0,'Retained shell listener remains')
    return {'fresh':{'observer':observer,'process':process,'frame_markers':markers,'timings':timings,
        'closes':closes,'saves':saves,'PPMs':ppms,'stdout':pin(out),'stderr':pin(err)},
        'saved':saved,'listeners_absent':True,'listener_log':pin(logs[0]/'actor.stdout'),
        'retained_failure':pin(directory/'first-failure.json'),
        'native_launched_again':False,'final_verifier_repair':'Missing csv import only; retained native/OS/save records independently finished.',
        'scope':'Two actual1920x1080 returned CPU images; full dimensions/cadence/save, not full1080 RGB or drawable parity.'}


def finish_retained_capacity(directory):
    require(json.loads((directory/'first-failure.json').read_text())['message']=='Playable process teardown',
            'Only the retained shell TERM versus stdin-stop verifier mismatch may finish')
    data=G.fixture();full=copy.deepcopy(data['full'])
    full['main']['selected']=7;full['main']['slots']=[Inventory.stack('minecraft:dirt',64) for _ in range(36)]
    full['equipment']=[None]*7;full['equipment'][4]=Inventory.stack('minecraft:dirt',64)
    before=G.Boundary.authority(full,{'craft':[Inventory.stack('minecraft:stone',3),None,None,None],
        'carried':Inventory.stack('minecraft:stone',17),'result':Inventory.stack('minecraft:stone_button',1),'opened':True,'revision':5})
    results={}
    for name,status in [('refused',2),('recovered',0)]:
        d=directory/name;process=json.loads((d/'observed-launch/result.full.json').read_text());G.R.process_ok(process)
        observer=json.loads(Path(process['stdout']['path']).read_text().strip().splitlines()[-1])
        require(observer['child_status']==status and not observer['timed_out']
                and observer['before_frontmost_pid']>0
                and observer['before_frontmost_pid']==observer['after_frontmost_pid']
                and observer['sampled_frontmost_pids']==[observer['before_frontmost_pid']]
                and not observer['activation_notification_pids'] and observer['space_change_notifications']==0
                and process['cleanup']['live_group_absent'],'Retained native shell/OS verdict')
        out,err=d/'stdout',d/'stderr';text=out.read_text();events=G.R.PC.events(out)
        markers=[v for v in text.splitlines() if v.startswith('catalog.frame|')]
        timings=[v for v in text.splitlines() if v.startswith('client.timing|')]
        require(len(markers)==len(timings)==1,'Retained actual bounded Generic frame')
        closes=[v for v in events if v.get('event')=='client.menu-close'];saves=[v for v in events if v.get('event')=='client.save']
        require(len(closes)==1 and closes[0]['sequence']==1,'Retained correlated shell close')
        results[name]={'observer':observer,'process':process,'frame_markers':markers,'timings':timings,
                'closes':closes,'saves':saves,'stdout':pin(out),'stderr':pin(err)}
    require(results['refused']['closes'][0]['accepted'] is False
            and results['refused']['closes'][0]['menu']==before and not results['refused']['saves'],
            'Retained complete capacity refusal')
    recovery=Path(re.search(r"--reconnect '([^']+)'",(directory/'refused/stderr').read_text()).group(1))
    require(stat.S_IMODE(recovery.stat().st_mode)==0o600,'Actual retained connection permissions')
    # Read only the PID line; never retain capability contents or their digest.
    pid=lambda p:int(re.search(r'^export MC_ACTOR_PID=(\d+)$',p.read_text(),re.M).group(1))
    actor=json.loads((directory/'backend-capacity/process.json').read_text())
    require(pid(recovery)==pid(directory/'connection.env')==actor['pid']
            and actor['exit_code']==-15 and actor['group_absent'] and all(actor['listeners_absent'])
            and not actor['errors'],'Same actual actor retained/reconnected then intentionally TERM/reaped')
    full['main']['slots'][0]=Inventory.stack('minecraft:stone',20)
    after=G.Boundary.authority(full,{'craft':[None]*4,'carried':None,'result':None,'opened':False,'revision':6})
    require(results['recovered']['closes'][0]['accepted'] is True
            and results['recovered']['closes'][0]['menu']==after and len(results['recovered']['saves'])==1,
            'Retained exact same-owner temporary-item return')
    path=directory/'world.nbt';expected=G.Boundary.bundle(data['world'],42,data['record'],full,'')
    require(path.read_bytes()==expected and results['recovered']['saves'][0]['result']==
            {'status':'durable','published':True,'durable':True,'bytes':len(expected),'peer_highwater':42},
            'Retained exact104section/43slot/status/WG/clock durable save')
    return {**results,'retained_actor_pid':actor['pid'],'same_retained_actor_reconnected':True,
        'recovery_permissions':'0600','complete_after_menu':after,'saved':pin(path),
        'independent_expected_sha256':G.digest(expected),'retained_failure':pin(directory/'first-failure.json'),
        'real_recovery_command':[7,0,['minecraft:dirt',''],0],'native_launched_again':False,
        'scope':'Actual close refusal and same-PID reconnect/save; retained native transactions independently verified after host teardown-contract correction.'}


def grass_refusal(directory):
    data=G.fixture()
    G.S.BASE.set_block(data['world'],-1,-60,0,9)
    data['world']['revision']+=1
    path=directory/'world.nbt';path.write_bytes(G.Boundary.bundle(data['world'],40,data['record'],data['full'],''))
    actor=G.backend(ACTOR,'backend-grass',path)
    try:
        connection=connection_file(directory,actor,path)
        case=directory/'refused';case.mkdir()
        report,out,err=observed(case,['--reconnect',str(connection),'--frames','1',
                '--width','128','--height','128','--hud-scale','0','--render-scale','100'],1,0,expected_markers=1)
        require(err.read_text().splitlines()[0]=='render: WorldMesh:MissingTint:world:9'
                and 'Renderer exited with status 1; attempting close and durable save.' in err.read_text(),
                'Actual loaded grass must refuse absent tint and shell must still close/save')
        require(report['closes'][0]['accepted'] is True and len(report['saves'])==1
                and not list((case/'images').iterdir()),'Resource refusal must not present or bypass durable close')
        expected=G.Boundary.bundle(data['world'],42,data['record'],data['full'],'')
        require(path.read_bytes()==expected and report['saves'][0]['result']==
                {'status':'durable','published':True,'durable':True,'bytes':len(expected),'peer_highwater':42},
                'Resource refusal changed complete104section/43slot/status/WG/clock saved owner')
        return {'refused':report,'diagnostic':'render: WorldMesh:MissingTint:world:9',
                'saved':pin(path),'independent_expected_sha256':G.digest(expected),
                'presented_frames':0,'loaded_grass_missing_tint_is_named_refusal':True}
    finally:
        if actor.process.poll() is None:
            G.R.finish_backend(actor)
        else:
            actor.stop(failed=True)
            ended=json.loads((actor.directory/'process.json').read_text())
            require(ended['exit_code']==-15 and ended['group_absent'] and all(ended['listeners_absent'])
                    and not ended['errors'],'Actual refusal-shell TERM/reap/listener teardown')


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('case',choices=['fresh','capacity','grass']);parser.add_argument('--generation',type=int,default=1)
    parser.add_argument('--finish-retained-fresh',action='store_true',help='Finish only the retained final csv-import verifier failure; no native relaunch')
    args=parser.parse_args()
    require(pin(ACTOR)['sha256']==ACTOR_SHA and pin(CLIENT)['sha256']==CLIENT_SHA,'Admitted actual binaries changed')
    G.client_artifact(CLIENT)
    directory=ROOT/'build/generic-resource-world-sample-launcher-runtime'/f'{args.case}-{args.generation:03d}'
    if args.finish_retained_fresh:
        require(args.case=='fresh' and directory.exists(),'Retained finish only applies to existing fresh case')
    else:
        directory.mkdir(parents=True,exist_ok=False)
        (directory/'frozen-helper.py').write_bytes(Path(__file__).read_bytes())
    inputs={str(p):pin(p) for p in [ACTOR,CLIENT,LAUNCH,CLOSE,Path(__file__),G.JAR,G.REGISTRY]}
    actor_work=ACTOR.parent
    with G.Host.bindings(G.Boundary.A,{'WORK':actor_work,'SOURCE':actor_work/'source','ACTOR':ACTOR}), \
         G.Host.bindings(G.Pair,{'WORK':directory}),G.Host.bindings(G.R,{'WORK':directory,'GROUPS':directory/'owned-groups.ndjson'}):
      try:
        result=finish_retained_fresh(directory) if args.finish_retained_fresh else {'fresh':fresh,'capacity':capacity,'grass':grass_refusal}[args.case](directory)
        require(all(pin(p)==v for p,v in inputs.items()),'Runtime inputs changed')
        record={'status':'PASS','case':args.case,'native_consumer_run':True,'inputs':inputs,'result':result,
            'scope':'Actual public shell Actor017/Generic009 hidden route; no visible-input, cooking GUI, drawable or whole-game claim.'}
        exclusive(directory/'result.json',record)
        print(json.dumps({'status':'PASS','case':args.case,'result':str(directory/'result.json')}))
      except BaseException as error:
        exclusive(directory/('finish-failure.json' if args.finish_retained_fresh else 'first-failure.json'),{'status':'failed','type':type(error).__name__,'message':str(error),
                                              'notes':getattr(error,'__notes__',[])})
        raise
      finally:
        if not args.finish_retained_fresh:
            G.sweep_owned(directory)

if __name__=='__main__':main()
