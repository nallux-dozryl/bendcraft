#!/usr/bin/env python3
"""Actual renderer007/actor003 launch and close/save boundary checks."""
import argparse, copy, csv, json, os, re, shlex, shutil, signal, socket, stat, subprocess, sys, threading, time
from pathlib import Path
import test_playable_client_actor as A
import test_playable_client_session as P
import test_playable_resource_client as Pair
import test_remote_resource_client as R
import test_player_inventory as Inventory
import test_world_generation_settings as Generation
S=P.S
ROOT=Path(__file__).resolve().parents[1]
LAUNCH=ROOT/'tools/play_minecraft.sh'
CLOSE=ROOT/'tools/play_minecraft_close.py'
RENDERER=ROOT/'build/playable-renderer-current/007/renderer'
WORK=ROOT/'build/playable-renderer-current/007'
CANDIDATE_LAUNCH=WORK/'play-current.sh'


def full_authority(full, craft, carried, opened, revision):
    def slot(value):return [0] if value is None else [1,value['id'],value['components'],value['count']]
    main=full['main']
    return [[main['selected'],main['abilities']['instabuild'],main['abilities']['maybuild'],list(map(slot,main['slots']))],list(map(slot,full['equipment'])),[full['status'][key] for key in Inventory.STATUS_FIELDS],list(map(slot,craft)),slot(carried),[0],opened,revision]


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
        S.require(full['main']==P.playable_inventory() and full['equipment']==[None]*7 and full['status']=={'invulnerable':True,'mayfly':True,'flying':False,'walking_speed':1036831949,'flying_speed':1028443341} and full['generation']==Generation.stone_dirt_bytes(),'Fresh creative v3 defaults')
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


def close_fixture(directory, case):
    _,full=Inventory.parse_inventory_full((ROOT/'build/player-inventory-screen/full-codec-fixtures/full-status-equipment.nbt').read_bytes())
    full['main']['slots']=[None]*36;full['main']['selected']=7;full['equipment']=[None]*7
    full['generation']=Generation.stone_dirt_bytes()
    record=A.playable_spawn()
    identity,count,_=S.P.registry_identity(S.P.OFFICIAL)
    core=S.WC.empty_world(count,identity)
    root=S.bundle_root(core,40,record)
    payload=Inventory.inventory_full_bytes(S.local_bytes(record),full['main'],full['equipment'],full['status'],full['generation'])
    extension=S.WC.compound([('namespace',S.WC.txt(S.NAMESPACE)),('schema',S.WC.integer(1)),('payload',S.N.Value(7,payload))])
    initial=S.N.encode_root(S.N.RootTag(root.name,S.N.Value(10,tuple((name,extension if name==S.N.text('extension') else value) for name,value in root.value.payload))))
    path=directory/'world.nbt';path.write_bytes(initial)
    backend=P.PlayableBackend(directory/'actor',A.ACTOR,path,P.retained_bridge()[0])
    control=P.PlayablePrivate(backend)
    def command(value):
        reply=control.call(value,6);S.require(reply[4] is True,'Fixture actual menu command refused: '+str(value));return reply[6]
    command([9])
    if case=='return':
        for index,(item,amount) in enumerate([('minecraft:stone',2),('minecraft:stone',3),('minecraft:dirt',4),('minecraft:oak_planks',5)],1):
            command([7,8,[item,''],amount]);command([11,44,[0,0]]);command([11,index,[0,0]])
        command([7,8,['minecraft:dirt',''],1]);before=command([11,44,[0,0]])
        expected=copy.deepcopy(full)
        expected['main']['slots'][:3]=[Inventory.stack('minecraft:dirt',5),Inventory.stack('minecraft:stone',5),Inventory.stack('minecraft:oak_planks',5)]
        after=full_authority(expected,[None]*4,None,False,10)
    else:
        for index in range(36):command([7,index,['minecraft:dirt',''],64])
        command([11,44,[0,0]]);command([11,45,[0,0]])
        command([7,8,['minecraft:dirt',''],64])
        command([7,0,['minecraft:stone',''],3]);command([11,36,[0,0]]);command([11,1,[0,0]])
        command([7,0,['minecraft:dirt',''],64])
        command([7,0,['minecraft:stone',''],17]);command([11,36,[0,0]])
        before=command([7,0,['minecraft:dirt',''],64])
        full['main']['slots']=[Inventory.stack('minecraft:dirt',64) for _ in range(36)]
        full['equipment'][4]=Inventory.stack('minecraft:dirt',64)
        after=full_authority(full,[Inventory.stack('minecraft:stone',3),None,None,None],Inventory.stack('minecraft:stone',17),True,5)
        S.require(before==after,'Literal fullcapacity complete authority')
        expected=full
    control.call([2]);control.close();backend.private=None
    connection=directory/'connection.env'
    values={'MC_ACTOR_PID':backend.process.pid,'MC_LIVE_PORT':backend.port,'MC_RENDER_PORT':backend.private_port,'MC_RENDER_TOKEN':backend.token,'MC_RENDER_EPOCH':'playable-test-actor','MC_DEV_TOKEN':S.MCP.TOKEN,'MC_WORLD_PATH':path,'BEND_MINECRAFT_LAUNCH_MODE':'hidden'}
    connection.write_text(''.join('export '+name+'='+shlex.quote(str(value))+'\n' for name,value in values.items()));connection.chmod(0o600)
    S.exclusive_json(directory/'fixture.json',{'initial_bundle':R.pin(path),'record_sha256':S.sha(S.local_bytes(record)),'before_menu':before,'expected_after_menu':after,'temporary_slots':'actual authenticated private acquire/pickup; no durable temporary fixture fields'})
    return backend,path,record,expected,after,connection,initial


def signal_after_frame(stdout,connection,number,stop,result,launch):
    """Signal the actual launcher after its first real presented frame."""
    try:
        deadline=time.monotonic()+50
        marker=str(launch)+' --reconnect '+str(connection)
        while time.monotonic()<deadline and not stop.wait(.01):
            if not stdout.exists() or b'"event":"client.frame"' not in stdout.read_bytes():continue
            rows=subprocess.check_output(['/bin/ps','-axo','pid=,args='],text=True).splitlines()
            targets=[int(row.strip().split(None,1)[0]) for row in rows if marker in row]
            S.require(len(targets)==1,'Actual signal launcher identity')
            os.kill(targets[0],number)
            result.update(pid=targets[0],signal=number,after_real_frame=True)
            return
        if not stop.is_set():raise TimeoutError('No real frame before launcher signal')
    except BaseException as cause:result['error']=type(cause).__name__+': '+str(cause)


def run(case, *, candidate=False):
    launch=CANDIDATE_LAUNCH if candidate else LAUNCH
    number=1
    while (WORK/('pair-actor003-'+case+'-'+str(number).zfill(3))).exists():number+=1
    directory=WORK/('pair-actor003-'+case+'-'+str(number).zfill(3));directory.mkdir()
    shutil.copyfile(__file__,directory/'frozen-test_playable_client_pair.py')
    evidence=ROOT/('evidence/playable-client-pair007-actor003-'+case+'-'+str(number).zfill(3)+'.json')
    expected={A.ACTOR:'3c773cc1a70bf614724b880bed403e4dba6b2b8800515ae8b1cb040573055c38',RENDERER:'71d7763bc576509a8d8b43205eeb4bb07f4541c283a6bfd75f1ea15a6a7b0130'}
    for path,value in expected.items():S.require(R.pin(path)['sha256']==value,'Current pair binary changed')
    observer=Pair.observer()['observer']['artifact']
    inputs={str(path):R.pin(path) for path in [A.ACTOR,RENDERER,launch,CLOSE,Path(__file__),S.P.OFFICIAL,R.PC.JAR,ROOT/'generated/reference_item_metadata.tsv',Path(observer)]}
    os.environ['BEND_MINECRAFT_LAUNCH_MODE']='hidden';os.environ.pop('BEND_MINECRAFT_FRAME_DIR',None)
    backend=None;signal_thread=None;signal_stop=threading.Event();signal_result={};signal_number={'interrupt':signal.SIGINT,'terminate':signal.SIGTERM}.get(case)
    report={'status':'FAIL','case':case,'launcher_route':'candidate' if candidate else 'public','inputs':inputs,'foreground_launches':0,'scope':'Actualrenderer007/actor003 fresh or reconnect launcher, MenuClose and durable save. Physical keyboard/mouse and whole game parity are not asserted.'}
    try:
        if case=='fresh':
            path=directory/'world.nbt';S.require(not path.exists(),'Fresh file existed')
            public,private=S.MCP.free_port(),S.MCP.free_port()
            while public==private:private=S.MCP.free_port()
            os.environ.update(MC_WORLD_PATH=str(path),MC_LIVE_PORT=str(public),MC_RENDER_PORT=str(private))
            for key in ('MC_RENDER_TOKEN','MC_RENDER_EPOCH','MC_DEV_TOKEN','MC_ACTOR_PID'):os.environ.pop(key,None)
            arguments=['--frames','2','--width','1920','--height','1080','--hud-scale','0','--render-scale','100']
        else:
            journal=directory/'owned-groups.jsonl';journal.touch()
            with A.H.bindings(S,{'ROOT':A.SOURCE,'SERVER':A.ACTOR,'activation':lambda:None,'OWNED_GROUPS':journal}):
                backend,path,record,full,after,connection,initial=close_fixture(directory,'capacity' if case=='capacity' else 'return')
            public,private=backend.port,backend.private_port
            arguments=['--reconnect',str(connection),'--frames','1','--width','320','--height','180','--hud-scale','1','--render-scale','100']
            if signal_number is not None:arguments=arguments[:2]+arguments[4:]
        stdout,stderr=directory/'client.stdout',directory/'client.stderr'
        if signal_number is not None:
            signal_thread=threading.Thread(target=signal_after_frame,args=(stdout,connection,signal_number,signal_stop,signal_result,launch),daemon=True);signal_thread.start()
        with A.H.bindings(R,{'WORK':directory}):process=R.bounded([observer,launch,stdout,stderr,*arguments],90,'observed-launch')
        signal_stop.set()
        if signal_thread is not None:
            signal_thread.join(1);S.require(signal_result.get('signal')==signal_number and 'error' not in signal_result,'Actual launcher signal: '+str(signal_result));report['signal']=signal_result
        report['process']=process;R.process_ok(process)
        observed=[json.loads(line) for line in Path(process['stdout']['path']).read_text().splitlines() if line.strip()][-1]
        report['observer']=observed
        expected_status=2 if case=='capacity' else 128+signal_number if signal_number is not None else 0
        S.require(not observed['timed_out'] and observed['child_status']==expected_status,'Actual launcher exit: '+stderr.read_text())
        if case not in ('capacity','interrupt','terminate'):S.require(stderr.read_bytes().strip()==b'client closed','Unexpected successful renderer diagnostic')
        if signal_number is not None:S.require(('Renderer exited with status '+str(expected_status)+'; attempting close and durable save.') in stderr.read_text(),'Signal save path was bypassed')
        S.require(observed['before_frontmost_pid']>0 and observed['before_frontmost_pid']==observed['after_frontmost_pid'] and observed['sampled_frontmost_pids']==[observed['before_frontmost_pid']] and observed['space_change_notifications']==0 and observed['child_pid'] not in observed['activation_notification_pids'],'Focus or Spaces changed')
        events=R.PC.events(stdout);frames=[value for value in events if value.get('event')=='client.frame'];closes=[value for value in events if value.get('event')=='client.menu-close'];saves=[value for value in events if value.get('event')=='client.save']
        S.require((len(frames)>=1 if signal_number is not None else len(frames)==(2 if case=='fresh' else 1)) and all(value['renderer']=='remote-local-resource-instrument' for value in frames),'Actual resource/frame/MenuReply loop absent')
        S.require(len(closes)==1 and closes[0]['sequence']==1 and closes[0]['accepted']==(case!='capacity'),'Correlated launcher MenuClose absent')
        if case=='capacity':
            S.require(closes[0]['menu']==after and not saves and path.read_bytes()==initial,'Atomic close refusal or false save acknowledgement')
            S.require(backend.process.poll() is None and 'Actor remains running (PID '+str(backend.process.pid)+')' in stderr.read_text(),'Refusal did not retain actual actor')
            match=re.search(r"--reconnect '([^']+)'",stderr.read_text());S.require(match is not None,'Missing reconnect command')
            recovery=Path(match.group(1));S.require(stat.S_IMODE(recovery.stat().st_mode)==0o600,'Recovery details exposed')
            recovery_journal=directory/'recovery-private';recovery_journal.mkdir()
            with A.H.bindings(backend,{'directory':recovery_journal}):control=P.PlayablePrivate(backend)
            S.require(control.call([8],6)[6]==after,'Retained complete live authority')
            raw,_=backend.tcp(True);raw.call('world.save',{},fault='SaveEncodingFailed')
            S.require(path.read_bytes()==initial,'Refused temporary save changed physical bytes')
            report.update(retained_actor=True,refused_save_preserves_old_bytes=True,recovery_permissions='0600',complete_after_menu=after)
        else:
            S.require(len(saves)==1 and saves[0]['path']==str(path),'Missing durable acknowledgement')
            saved,restored=complete_saved(path,full if case!='fresh' else None,record if case!='fresh' else None,fresh=case=='fresh')
            S.require(saves[0]['result']=={'status':'durable','published':True,'durable':True,'bytes':path.stat().st_size,'peer_highwater':42 if case!='fresh' else 2},'Exact durable save response')
            if case!='fresh':S.require(closes[0]['menu']==after,'Actual full close return authority')
            for port in (public,private):
                with socket.socket() as probe:probe.settimeout(.5);S.require(probe.connect_ex(('127.0.0.1',port))!=0,'Acknowledged shutdown retained listener')
            report.update(saved=saved,save_ack=saves[0],complete_after_menu=closes[0]['menu'],listeners_absent=True)
        timings=[int(line.split('|')[2]) for line in stdout.read_text().splitlines() if line.startswith('client.timing|')]
        S.require((len(frames)-len(timings) in (0,1) if signal_number is not None else len(timings)==len(frames)),'Presented timing records missing')
        if signal_number is not None:report['signal_interrupted_timing_records']=len(frames)-len(timings)
        if case=='fresh':S.require(all((frame['logical_width'],frame['logical_height'],frame['presentation_width'],frame['presentation_height'],frame['hud_width'],frame['hud_height'])==(1920,1080,1920,1080,480,270) for frame in frames),'Human default output/scene/HUD dimensions')
        for path,value in inputs.items():S.require(R.pin(path)==value,'Input changed: '+path)
        report.update(status='PASS',frames=frames,frame_render_present_milliseconds=timings,trace=False,focus_and_Spaces_unchanged=True,stdout=R.pin(stdout),stderr=R.pin(stderr))
    except BaseException as cause:
        report['error']=type(cause).__name__+': '+str(cause)
        raise
    finally:
        signal_stop.set()
        if signal_thread is not None:signal_thread.join(1)
        if backend is not None:
            backend.stop(failed=True)
            report['fixture_process']=json.loads((backend.directory/'process.json').read_bytes())
        report['descendant_cleanup']=A.O.sweep_directory(directory,'descendant-cleanup')
        R.write(evidence,report,True)
    print(json.dumps({'status':report['status'],'case':case,'seconds':process['seconds'],'timings':timings,'evidence':R.pin(evidence)}),flush=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('case',choices=['fresh','return','capacity','interrupt','terminate']);parser.add_argument('--candidate',action='store_true',help='Test the new007 launcher before public adoption');args=parser.parse_args();run(args.case,candidate=args.candidate)
