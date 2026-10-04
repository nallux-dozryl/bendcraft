#!/usr/bin/env python3
"""Current actor build and actual TCP/MCP/menu/durable-save boundary checks.

Reuse the measured private source-API emitter and existing bounded process owners.
The product entry imports production only; tests drive it through real sockets.
"""
from __future__ import annotations
import argparse,copy,csv,dataclasses,hashlib,json,os,shutil,subprocess,sys
from pathlib import Path
import build_native as Builder
import test_playable_client_session as P
import test_remote_resource_client as R
import test_local_player_session as S
import test_local_player_session_continuation_r2 as O
import test_fall_reset_world_continuation_r2 as H
ROOT=Path(__file__).resolve().parents[1]
WORK=ROOT/'build/compiler-producer-diagnostic-012'
SOURCE=WORK/'source'
ACTOR=WORK/'actor'
OLD=ROOT/'build/compiler-producer-diagnostic-010'
PlayableBackend=P.PlayableBackend
PlayablePrivate=P.PlayablePrivate
playable_spawn=P.playable_spawn
playable_look=P.playable_look
pin=R.pin

def snapshot():
    if not (SOURCE/'source-map.json').exists():
        with H.bindings(P,{'SOURCE_ROOT':SOURCE}):P.map_current_sources(Builder)
    mapping=json.loads((SOURCE/'source-map.json').read_bytes())
    for row in mapping['files']:
        actual=pin(SOURCE/row['path'])
        R.require(actual['sha256']==row['original_sha256'],'Mapped source drift: '+row['path'])
    return mapping

def build():
    mapping=snapshot()
    result=WORK/'native-build.json'
    if result.exists():
        done=json.loads(result.read_bytes())
        R.require(done['status']=='PASS' and done['binary']==pin(ACTOR) and done['source_map']==pin(SOURCE/'source-map.json'),'Existing actor003 artifact mismatch')
        print(json.dumps({'status':'verified-build-reuse','binary':done['binary']}),flush=True)
        return
    R.require(not ACTOR.exists(),'Unrecorded existing actor binary')
    prior=json.loads((OLD/'manifest.json').read_bytes())
    original={p:expected for p,expected in prior['files'].items() if not Path(p).is_relative_to(ROOT)}
    for path,expected in original.items():R.require(pin(path)['sha256']==expected,'Original compiler/tool changed: '+path)
    if not (WORK/'receipt.json').exists():
        for name in ('comp_instrumented.ts','run.py','diagnose.mjs'):
            text=(OLD/name).read_text().replace(str(OLD),str(WORK))
            if name=='diagnose.mjs':text=text.replace(str(ROOT/'build/playable-client-current-source/002/remote_resource_server.bend'),str(SOURCE/'remote_resource_server.bend'))
            with (WORK/name).open('x') as output:output.write(text)
        inputs={**original,**{str(path):pin(path)['sha256'] for path in [WORK/name for name in ('comp_instrumented.ts','run.py','diagnose.mjs')]+[SOURCE/'remote_resource_server.bend',SOURCE/'source-map.json']}}
        limits={'heap_mib':6144,'total_seconds':600,'producer_stall_seconds':90,'sampled_rss_bytes':8589934592}
        R.write(WORK/'manifest.json',{'scope':'Actual current actor003 direct production graph with close-return and extracted AS selector; reviewed010 private queue/zero-gap emitter, original compiler unchanged. No installed cache promotion or compiler-wide certification.','files':inputs,'limits':limits,'entry':str(SOURCE/'remote_resource_server.bend')},True)
        with H.bindings(R,{'WORK':WORK}):
            emitted=R.bounded([sys.executable,str(WORK/'run.py')],605,'emission-process')
            R.process_ok(emitted)
    receipt=json.loads((WORK/'receipt.json').read_bytes())
    R.require(receipt['returncode']==0 and receipt['termination_reason'] is None and receipt['complete_C'] and receipt['group_absent'],'Current actor C producer failed; retain failure without retry')
    for path,expected in receipt['source_after'].items():
        R.require(pin(path)['sha256']==expected,'Retained C producer input changed: '+path)
    loaded=json.loads((WORK/'loaded-source-pins.json').read_bytes())
    R.require(loaded==json.loads((WORK/'final-source-pins.json').read_bytes()),'Retained C loaded source drift')
    for path,expected in loaded.items():R.require(pin(path)['sha256']==expected,'Retained C loaded source changed: '+path)
    with H.bindings(R,{'WORK':WORK}):
        c=WORK/'diagnostic.c';cpin=pin(c)
        R.require(cpin['bytes']==receipt['C']['bytes'] and cpin['sha256']==receipt['C']['sha256'],'Retained C changed')
        Builder.guard_route(c.read_text())
        sdk=subprocess.check_output(['/usr/bin/xcrun','--show-sdk-path'],text=True).strip()
        command=['/usr/bin/env','SDKROOT='+sdk,'/usr/bin/clang','-std=c11','-O3',str(c),'-lpthread','-lm','-o',str(ACTOR)]
        clangpin=pin('/usr/bin/clang')
        compiled=R.bounded(command,300,'native-build-process')
        R.process_ok(compiled)
        R.require(Path(compiled['stderr']['path']).read_bytes()==b'' and pin(c)==cpin and pin('/usr/bin/clang')==clangpin,'Unexpected native compiler diagnostic or input drift')
    R.require(pin(ACTOR)['sha256']!=pin(OLD/'actor')['sha256'],'New actor reused old binary')
    done={'status':'PASS','generation':'immutable-actor003/producer012','binary':pin(ACTOR),'source_map':pin(SOURCE/'source-map.json'),'entry':pin(SOURCE/'remote_resource_server.bend'),'C':cpin,'producer':pin(WORK/'receipt.json'),'source_API':pin(ROOT.parent/'bend/bend2/bend.ts'),'private_compiler':pin(WORK/'comp_instrumented.ts'),'original_compiler':pin(ROOT.parent/'bend/bend2/comp.ts'),'loaded_source_pins':pin(WORK/'loaded-source-pins.json'),'final_source_pins':pin(WORK/'final-source-pins.json'),'emission_seconds':receipt['seconds'],'sampled_peak_RSS_bytes':receipt['sampled_peak_rss_bytes'],'clang':{'command':command,'SDKROOT':sdk,'seconds':compiled['seconds'],'process':pin(WORK/'native-build-process/result.full.json')},'retries':0,'product_cache_promoted':False,'behavior':'pending actual native sockets/save/reload'}
    R.write(result,done,True);R.write(ROOT/'evidence/playable-client-actor003-build.json',done,True)
    print(json.dumps({'status':done['status'],'binary':done['binary'],'emission_seconds':done['emission_seconds'],'clang_seconds':compiled['seconds']}),flush=True)

def actor_boundary(directory, binary, bridge):
    """Current003 actor boundary: complete v3 authority and durable recovery.

    Drive the existing real sockets/process owner. Expected bytes come from the
    independent inventory/NBT fixture helpers and an explicit demand rectangle.
    The caller pins the actual producer; this does not promote its private
    compiler experiment into the installed builder's content cache.
    """
    import test_player_inventory as Inventory
    import test_world_generation_settings as Generation
    directory = Path(directory)
    directory.mkdir(exist_ok=False)
    identity, count, _ = S.P.registry_identity(S.P.OFFICIAL)
    with S.P.OFFICIAL.open(newline='') as source:
        palette = {row['identifier']: int(row['default_state_id'])
                   for row in csv.DictReader(source, delimiter='\t')
                   if row['identifier'] in ('minecraft:air', 'minecraft:stone',
                                            'minecraft:dirt', 'minecraft:oak_planks')}
    fixture = ROOT / 'build/player-inventory-screen/full-codec-fixtures/full-status-equipment.nbt'
    _, full = Inventory.parse_inventory_full(fixture.read_bytes())
    full['main']['slots']=[None]*36
    full['main']['selected']=7
    full['generation'] = Generation.stone_dirt_bytes(seed=0xffffffffffffffff)
    record = dataclasses.replace(playable_spawn(), count=7, invulnerable=9)
    empty = S.WC.empty_world(count, identity)
    world = copy.deepcopy(empty)
    # Default8-cube plus neighbor reads requests chunks[-1,0]^2 and the entire
    # Overworld[-64,319] with one16-block section halo on each vertical side.
    world['sections'] = [S.WC.section(S.BASE.section_key(x, y, z), palette['minecraft:air'])
        for x in (-16, 0) for y in range(-80, 336, 16) for z in (-16, 0)]
    for section in world['sections']:
        section['cells'] = list(section['cells'])
    by_key = {section['key']: section for section in world['sections']}
    for x in range(-16, 16):
        for z in range(-16, 16):
            for y, material in ((-64, 'minecraft:stone'), (-63, 'minecraft:dirt'),
                                (-62, 'minecraft:dirt'), (-61, 'minecraft:stone')):
                by_key[S.BASE.section_key(x, y, z)]['cells'][
                    (x & 15) + ((z & 15) << 4) + ((y & 15) << 8)] = palette[material]
    for section in world['sections']:
        section['cells'] = tuple(section['cells'])
    world['sections'].sort(key=lambda item: item['key'])
    world['revision'] = 1
    S.require(len(world['sections']) == 104, 'Current complete demand rectangle')
    S.P.canonical_expected(world)

    def bundle(core, highwater):
        root = S.bundle_root(core, highwater, record)
        payload = Inventory.inventory_full_bytes(S.local_bytes(record), full['main'],
            full['equipment'], full['status'], full['generation'])
        extension = S.WC.compound([('namespace', S.WC.txt(S.NAMESPACE)),
            ('schema', S.WC.integer(1)), ('payload', S.N.Value(7, payload))])
        return S.N.encode_root(S.N.RootTag(root.name, S.N.Value(10, tuple(
            (name, extension if name == S.N.text('extension') else value)
            for name, value in root.value.payload))))

    menu = {'craft': [None] * 4, 'carried': None, 'opened': False, 'revision': 0}
    def slot(value):
        return [0] if value is None else [1, value['id'], value['components'], value['count']]
    def authority():
        main, status = full['main'], full['status']
        return [[main['selected'], main['abilities']['instabuild'], main['abilities']['maybuild'],
                 [slot(value) for value in main['slots']]],
                [slot(value) for value in full['equipment']],
                [status[name] for name in Inventory.STATUS_FIELDS],
                [slot(value) for value in menu['craft']], slot(menu['carried']), [0],
                menu['opened'], menu['revision']]
    checks, saves = [], []
    def observed(control, command, label, accepted=True, message=''):
        reply = control.call(command, 6)
        S.require(reply[4:] == [accepted, message, authority()],
                  'Current complete MenuReply authority: ' + label + ': ' + str(reply[4:6]))
        checks.append({'label': label, 'command': command, 'accepted': accepted,
                       'snapshot_sha256': S.sha(S.canonical(reply[6]))})
    def saved(client, path, highwater, label):
        reply = client.call('world.save', {})
        actual, expected = path.read_bytes(), bundle(world, highwater)
        saves.append({'label': label, 'reply': reply, 'actual_sha256': S.sha(actual),
                      'expected_sha256': S.sha(expected), 'bytes': len(actual)})
        S.exclusive_json(directory / (label + '.json'), saves[-1])
        S.require(reply == {'status': 'durable', 'published': True, 'durable': True,
            'bytes': len(expected), 'peer_highwater': highwater} and actual == expected,
            'Current complete Core/v3/status/WG durable bytes: ' + label)
        root = S.N.Reader(actual, max_bytes=16846848, max_depth=6,
                          max_elements=16846848).root()
        fields = S.WC.fields(root.value, S.BUNDLE_FIELDS)
        parsed = S.WC.validate(S.N.parse(fields['core'].payload), count, identity)
        extra = S.WC.fields(fields['extension'], S.EXTENSION_FIELDS)
        nested, restored = Inventory.parse_inventory_full(bytes(extra['payload'].payload))
        S.require(S.P.canonical_expected(parsed) == S.P.canonical_expected(world)
                  and nested == S.local_bytes(record) and restored == full,
                  'Current independent complete durable projection: ' + label)
        return actual
    def frame(control):
        sample = control.call([0, 128, 128], 1)[4]
        S.require(len(sample) == 7, 'Current Frame cardinality')
        tick, revision, origin, camera, colors, reads, rows = sample
        words, _ = S.PC.parse_snapshot(S.PR.decode(record.motion)[0])
        eye = (.5, -60 + S.PC.f32(record.eye), .5)
        S.require((tick, revision) == (world['tick'], world['revision']) and
            origin == list(S.PC.words64(tuple(map(S.PC.raw64, eye)))) and
            camera == [0, 0, 0, *words[39:41]] and colors == [palette[name]
                for name in ('minecraft:air', 'minecraft:stone', 'minecraft:dirt', 'minecraft:oak_planks')],
            'Current Frame eye/camera/clock/palette')
        sections = {section['key']: section for section in world['sections']}
        def cell(x, y, z):
            return sections[S.BASE.section_key(x, y, z)]['cells'][
                (x & 15) + ((z & 15) << 4) + ((y & 15) << 8)]
        expected = []
        directions = ((0, -1, 0), (0, 1, 0), (0, 0, -1), (0, 0, 1), (-1, 0, 0), (1, 0, 0))
        materials = {palette['minecraft:stone']: 0, palette['minecraft:dirt']: 1,
                     palette['minecraft:oak_planks']: 2}
        for z in range(-4, 4):
            for y in range(-64, -56):
                for x in range(-4, 4):
                    state = cell(x, y, z)
                    if state != palette['minecraft:air']:
                        mask = sum(1 << i for i, (dx, dy, dz) in enumerate(directions)
                                   if cell(x + dx, y + dy, z + dz) == palette['minecraft:air'])
                        boundary = int(x in (-4, 3)) + int(y in (-64, -57)) + int(z in (-4, 3))
                        expected.append([S.unsigned(x), S.unsigned(y), S.unsigned(z), boundary,
                            state, materials[state], mask, *[S.PC.raw32(value - base)
                            for value, base in zip((x, y, z), eye)]])
        S.require(rows == expected and reads == 6 * len(expected),
                  'Current exact104-section terrain Frame rows')
        return S.sha(S.canonical(sample))

    path = directory / 'current.nbt'
    initial = bundle(empty, 40)
    path.write_bytes(initial)
    S.exclusive_json(directory / 'fixture.json', {'bundle': pin(path), 'fixture': pin(fixture),
        'generation_sha256': S.sha(full['generation']), 'seed': '18446744073709551615',
        'expected_sections': 104, 'raw_status': full['status'], 'equipment_slots': 7})
    actor = PlayableBackend(directory / 'loaded-v3', binary, path, bridge)
    frames = []
    try:
        raw, ping = actor.tcp(True)
        developer, dping = actor.mcp(); observer, oping = actor.mcp(False)
        highwater = max(ping['peer'], dping['peer'], oping['peer'])
        S.require(ping['peer'] == 42, 'Current reserved saved40 Player41/public42')
        control = PlayablePrivate(actor)
        S.inspect(raw, record)
        S.require(observer.call('inventory.inspect', {}) == full['main'] and
                  raw.call('world.clock') == S.P.clock(world), 'Current loaded v3 main/Core authority')
        observed(control, [8], 'inspect-all43-and-raw-status')
        frames.append(frame(control))
        S.require(path.read_bytes() == initial, 'Current demand read prematurely saved')
        for operation, arguments in [('inventory.select', {'slot': 0}),
            ('inventory.acquire', {'slot': 0, 'item': 'minecraft:dirt', 'count': 4}),
            ('inventory.transfer', {'source': 0, 'destination': 1, 'count': 1, 'mode': 'split'})]:
            observer.call(operation, arguments, fault='PermissionDenied')
        observer.call('world.save', {}, fault='PermissionDenied')
        developer.call('inventory.acquire', {'slot': 35, 'item': 'minecraft:ender_pearl', 'count': 17},
                       fault='InventoryAcquisitionRejected')
        observed(control,[12,7],'select7')
        menu['opened']=True;observed(control,[9],'open')
        for index,(item,amount) in enumerate([('minecraft:stone',2),('minecraft:stone',3),('minecraft:dirt',4),('minecraft:oak_planks',5)],1):
            full['main']['slots'][8]=Inventory.stack(item,amount)
            observed(control,[7,8,[item,''],amount],'acquire-craft-source'+str(index))
            menu['carried'],full['main']['slots'][8]=full['main']['slots'][8],None
            menu['revision']+=1;observed(control,[11,44,[0,0]],'pickup-craft-source'+str(index))
            menu['craft'][index-1],menu['carried']=menu['carried'],None
            menu['revision']+=1;observed(control,[11,index,[0,0]],'place-craft'+str(index))
        full['main']['slots'][8]=Inventory.stack('minecraft:dirt',1)
        observed(control,[7,8,['minecraft:dirt',''],1],'acquire-carried-source')
        menu['carried'],full['main']['slots'][8]=full['main']['slots'][8],None
        menu['revision']+=1;observed(control,[11,44,[0,0]],'pickup-final-carried')
        raw.call('world.save',{},fault='SaveEncodingFailed')
        S.require(path.read_bytes()==initial,'Temporary save changed physical bytes')
        full['main']['slots'][0]=Inventory.stack('minecraft:dirt',5)
        full['main']['slots'][1]=Inventory.stack('minecraft:stone',5)
        full['main']['slots'][2]=Inventory.stack('minecraft:oak_planks',5)
        menu.update(craft=[None]*4,carried=None,opened=False,revision=10)
        observed(control,[10],'close-returns-all-craft-and-carried')
        full['main']['selected']=0;observed(control,[12,0],'select-returned-dirt')
        # Retained private transfer consumer and full MenuReply correlation.
        full['main']['slots'][4],full['main']['slots'][1]=full['main']['slots'][1],None
        observed(control,[6,1,4,99,0],'private-transfer-after-close')
        control.aim_down(); record = playable_look(record, 90.0)
        S.inspect(raw, record)
        for button, state in ((0, 'minecraft:air'), (1, 'minecraft:dirt')):
            sequence = control.sequence
            S.require(control.call([3, button], 5)[4:] == [True, ''], 'Current actual break/place')
            S.BASE.set_block(world, 0, -61, 0, palette[state]); world['revision'] += 1
            world['events'].insert(0, {'stamp': (world['tick'], 41, sequence),
                                     'kind': 0, 'revision': world['revision']})
        S.require(raw.call('world.clock') == S.P.clock(world) and
                  observer.call('inventory.inspect') == full['main'], 'Current action/full authority')
        observed(control, [8], 'complete-after-actions'); frames.append(frame(control))
        acknowledged = saved(developer, path, highwater, 'acknowledged-save')
        full['main']['slots'][3] = Inventory.stack('minecraft:oak_planks', 1)
        observed(control, [7, 3, ['minecraft:oak_planks', ''], 1], 'unsaved-private-acquire')
        S.require(path.read_bytes() == acknowledged, 'Unsaved private acquisition changed durable bytes')
        full['main']['slots'][3] = None
    except BaseException:
        actor.stop(failed=True)
        raise
    finally:
        actor.stop(kill=not actor.stopped)

    actor = PlayableBackend(directory / 'cold-reload', binary, path, bridge)
    try:
        raw, ping = actor.tcp(True)
        S.require(ping['peer'] == highwater + 2, 'Current cold owner/public identities')
        control = PlayablePrivate(actor)
        # Temporary menu state is nondurable. All physical v3 fields and Core
        # come from the last acknowledged save, not the killed live owner.
        menu['revision'] = 0
        observed(control, [8], 'cold-exact-all43-raw-status')
        S.inspect(raw, record)
        S.require(raw.call('inventory.inspect') == full['main'] and
            raw.call('world.clock') == S.P.clock(world) and path.read_bytes() == acknowledged,
            'Current SIGKILL lost only unacknowledged state')
        frames.append(frame(control))
        acknowledged = saved(raw, path, ping['peer'], 'cold-reloaded-save')
        reloaded_highwater = ping['peer']
        retained_full = copy.deepcopy(full)
        # The actual menu owner must reject a close atomically when all main
        # destinations are full. The offhand shield cannot absorb stone.
        for index in range(36):
            full['main']['slots'][index] = Inventory.stack('minecraft:dirt', 64)
            observed(control, [7, index, ['minecraft:dirt', ''], 64],
                     'fill-capacity-main' + str(index))
        menu['opened'] = True
        observed(control, [9], 'open-full-capacity')
        for target, amount in ((1, 3), (None, 17)):
            full['main']['slots'][0] = Inventory.stack('minecraft:stone', amount)
            observed(control, [7, 0, ['minecraft:stone', ''], amount],
                     'acquire-capacity-source' + str(amount))
            menu['carried'], full['main']['slots'][0] = full['main']['slots'][0], None
            menu['revision'] += 1
            observed(control, [11, 36, [0, 0]], 'pickup-capacity-source' + str(amount))
            if target is not None:
                menu['craft'][0], menu['carried'] = menu['carried'], None
                menu['revision'] += 1
                observed(control, [11, target, [0, 0]], 'place-capacity-craft')
            full['main']['slots'][0] = Inventory.stack('minecraft:dirt', 64)
            observed(control, [7, 0, ['minecraft:dirt', ''], 64],
                     'refill-capacity-source' + str(amount))
        S.require(menu['revision'] == 3 and menu['craft'][0]['count'] == 3
                  and menu['carried']['count'] == 17, 'Literal capacity fixture')
        observed(control, [10], 'close-full-capacity-atomic-refusal', accepted=False,
                 message='menu retains carried or crafting items; return/drop authority is required before closing')
        raw.call('world.save', {}, fault='SaveEncodingFailed')
        S.require(path.read_bytes() == acknowledged,
                  'Refused full-capacity close/save changed last acknowledged bytes')
        full = retained_full
        menu.update(craft=[None] * 4, carried=None, opened=False, revision=0)
    except BaseException:
        actor.stop(failed=True)
        raise
    finally:
        actor.stop(kill=not actor.stopped)

    actor = PlayableBackend(directory / 'capacity-cold-reload', binary, path, bridge)
    try:
        raw, ping = actor.tcp(True)
        S.require(ping['peer'] == reloaded_highwater + 2,
                  'Capacity cold owner/public identities')
        control = PlayablePrivate(actor)
        observed(control, [8], 'capacity-cold-exact-all43-raw-status')
        S.inspect(raw, record)
        S.require(raw.call('inventory.inspect') == full['main'] and
                  raw.call('world.clock') == S.P.clock(world) and
                  path.read_bytes() == acknowledged,
                  'Capacity SIGKILL restored exact previous acknowledgement')
        frames.append(frame(control))
        saved(raw, path, ping['peer'], 'capacity-cold-reloaded-save')
    except BaseException:
        actor.stop(failed=True)
        raise
    finally:
        actor.stop()
    result = {'status': 'PASS', 'actor_generation': 'immutable-actor003/producer012',
        'backends': 3, 'public_TCP_MCP': True, 'private_menu_checks': checks,
        'complete_menu_authority': True, 'main_slots': 36, 'equipment_slots': 7,
        'successful_close_return': {'before_revision': 9, 'after_revision': 10,
            'returned_main': ['dirt5', 'stone5', 'oak_planks5']},
        'full_capacity_close_atomic_refusal': True,
        'raw_status': full['status'], 'generation_sha256': S.sha(full['generation']),
        'terrain_sections': 104, 'frames': frames, 'first_person_break_place': True,
        'save_comparisons': saves, 'actual_SIGKILL_cold_reload': True,
        'SIGKILL_cold_reloads': 2,
        'scope': 'Actual actor003 close-return/AS source join and transport/menu/v3/WG durability; synthetic private packets. Physical window input and whole numerical flight/world fidelity are separate.'}
    S.exclusive_json(directory / 'summary.json', result)
    return result

def native_child(directory):
    built=json.loads((WORK/'native-build.json').read_bytes())
    def identity():R.require(built['binary']==pin(ACTOR),'Actor003 binary changed')
    identity();journal=directory/'backend-owned-groups.jsonl';journal.touch(exist_ok=False)
    bridge,_=P.retained_bridge()
    with H.bindings(S,{'SERVER':ACTOR,'ROOT':SOURCE,'activation':identity,'OWNED_GROUPS':journal}):
        try:result=actor_boundary(directory/'backend',ACTOR,bridge)
        except BaseException as cause:
            R.write(directory/'first-failure.json',{'type':type(cause).__name__,'message':str(cause)},True)
            raise
    print(json.dumps({'status':result['status'],'backends':result['backends'],'menu_checks':len(result['private_menu_checks'])}),flush=True)

def native():
    number=1
    while (WORK/('native-'+str(number).zfill(3))).exists():number+=1
    directory=WORK/('native-'+str(number).zfill(3));directory.mkdir(exist_ok=False)
    before={str(p):pin(p) for p in S.tool_closure([Path(__file__),Path(P.__file__),Path(R.__file__)])}
    R.write(directory/'inputs.json',{'binary':pin(ACTOR),'build':pin(WORK/'native-build.json'),'source_map':pin(SOURCE/'source-map.json'),'helpers':before},True)
    with H.bindings(R,{'WORK':directory}):
        try:process=R.bounded([sys.executable,str(Path(__file__)),'--_native-child',str(directory)],120,'execution')
        finally:cleanup=O.sweep_directory(directory,'descendant-cleanup')
    R.process_ok(process);R.require(cleanup['status']=='PASS','Actor003 descendant cleanup')
    for path,value in before.items():R.require(pin(path)==value,'Native helper changed: '+path)
    summary=json.loads((directory/'backend/summary.json').read_bytes())
    R.write(ROOT/'evidence/playable-client-actor003-native.json',{'status':summary['status'],'generation':'immutable-actor003/producer012','binary':pin(ACTOR),'build':pin(WORK/'native-build.json'),'source_map':pin(SOURCE/'source-map.json'),'summary':pin(directory/'backend/summary.json'),'seconds':process['seconds'],'process':pin(directory/'execution/result.full.json'),'cleanup':pin(directory/'descendant-cleanup.json'),'boundary':summary},True)
    print(json.dumps({'status':summary['status'],'seconds':process['seconds'],'summary':pin(directory/'backend/summary.json')}),flush=True)

if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--build',action='store_true');parser.add_argument('--native',action='store_true');parser.add_argument('--_native-child',type=Path);args=parser.parse_args()
    if args._native_child:native_child(args._native_child)
    else:
        if args.build or not args.native:build()
        if args.native or not args.build:native()
