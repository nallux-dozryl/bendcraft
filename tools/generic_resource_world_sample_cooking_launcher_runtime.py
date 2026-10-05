#!/usr/bin/env python3
"""Exercise the real cooking demo shell, original binaries and saved world.

This reuses the existing bounded desktop observer, actor owner and independent
format4 reconstruction. It injects no callbacks and starts no compiler.
"""
from __future__ import annotations

import argparse
import copy
import dataclasses
import json
import os
import socket
import subprocess
import sys
import time
from pathlib import Path
from unittest import mock

PYTHON = Path.home()/'.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3'
if Path(sys.executable).resolve() != PYTHON.resolve():
    os.execv(str(PYTHON), [str(PYTHON), '-B', __file__, *sys.argv[1:]])
sys.dont_write_bytecode = True

import generic_resource_world_sample_cooking_runtime as C

G, R, S, Host, Pair, A = C.G, C.R, C.S, C.Host, C.Pair, C.A
ROOT, require, pin = C.ROOT, C.require, C.pin
ACTOR = ROOT/'build/compiler-producer-diagnostic-023/actor'
CLIENT = ROOT/'build/generic-resource-world-sample-client-native/012/renderer'
LAUNCH = ROOT/'tools/play_minecraft.sh'
DEMO = ROOT/'tools/play_minecraft_cooking_demo.sh'
ACTOR_SHA = '7fd7ee9269802a6e128716f53bf34030ec592728ef954f9b61bebecac36719d1'
CLIENT_SHA = '3bd945855c7526f713ed1df03ab89e136429fbc36132f6152ef16fc7a491a232'
PROTECTED_PID = 47566


def protected():
    result = subprocess.run(['/bin/ps', '-p', str(PROTECTED_PID), '-o', 'args='],
                            text=True, capture_output=True, check=True)
    argv = result.stdout.strip()
    require('build/compiler-producer-diagnostic-012/actor ' in argv,
            'Historical protected actor identity')
    listeners = []
    for port in (25565, 25566):
        result = subprocess.run(['/usr/sbin/lsof', '-nP', '-a', '-p', str(PROTECTED_PID),
                                 '-iTCP:'+str(port), '-sTCP:LISTEN'],
                                text=True, capture_output=True, check=True)
        require('127.0.0.1:'+str(port) in result.stdout, 'Protected conventional listener')
        listeners.append(port)
    return {'pid': PROTECTED_PID, 'argv': argv, 'listeners': listeners}


def parse_lines(path):
    return [json.loads(line) for line in path.read_bytes().splitlines()
            if line.startswith(b'{')]


def run(directory, runtime_generation, *, finish_retained=False):
    runtime = ROOT/'build/generic-resource-world-sample-cooking-runtime'/f'{runtime_generation:03d}'
    acceptance = json.loads((runtime/'native/summary.json').read_bytes())
    require(acceptance['status'] == 'PASS' and acceptance['clock_mode'] == 'ambient',
            'Actual normal cooking caller acceptance must precede public selection')
    finalization_path = runtime/'native/retained-finalization.json'
    finalization = json.loads(finalization_path.read_bytes())
    require(finalization['status'] == 'retained_behaviour_save_cold_PASS_cleanup_driver_FAIL_finalized'
            and finalization['all_own_groups_absent']
            and finalization['summary'] == pin(runtime/'native/summary.json')
            and all(value['absent'] for value in finalization['listeners']),
            'Retained native behaviour PASS has explicit completed teardown despite its driver failure')
    demo_seed = json.loads((runtime/'demo-seed.json').read_bytes())
    require(demo_seed['status'] == 'file_only_validated_demo_seed_actual_public_wrapper_acceptance_pending'
            and demo_seed['complete_format4_reconstruction'] and demo_seed['all_other_owners_identical']
            and demo_seed['exact_byte_differences'] == [[330, 1, 0]]
            and demo_seed['retained_cleanup_finalization'] == pin(finalization_path),
            'Validated unpaused demo seed; public execution remains pending')
    seed = runtime/'demo-seed.nbt'
    require(demo_seed['demo_seed'] == pin(seed), 'Exact reconstructed demo seed')
    require(pin(seed)['sha256'] in DEMO.read_text(), 'Demo wrapper pins the validated seed')
    require(pin(ACTOR)['sha256'] == ACTOR_SHA and pin(CLIENT)['sha256'] == CLIENT_SHA,
            'Exact original production binaries')
    require(acceptance['actor'] == pin(ACTOR)
            and acceptance['original_build'] == pin(CLIENT.parent/'build.json'),
            'The cooking caller PASS belongs to this exact production pair')
    launcher = LAUNCH.read_text()
    require('actor="$root/build/compiler-producer-diagnostic-023/actor"' in launcher
            and 'renderer="$root/build/generic-resource-world-sample-client-native/012/renderer"' in launcher
            and 'export MC_COOKING_PROTOCOL=1' in launcher,
            'Actual public023/012 cooking protocol selection')
    require('MC_COOKING_PROTOCOL MC_WORLD_PATH' in launcher,
            'Retained0600 reconnect metadata contains cooking protocol')
    if finish_retained:
        require(json.loads((directory/'first-failure.json').read_bytes())['message'] ==
                'Independent all104 sections and natural Core cadence',
                'Only the retained max_peer oracle failure may finish')
    else:
        directory.mkdir(parents=True, exist_ok=False)
    before = protected()
    old_world = ROOT/'build/playable-world.nbt'
    default_worlds = (old_world, ROOT/'build/playable-world-022.nbt')
    default_world_pins = {str(value): pin(value) if value.is_file() else None
                         for value in default_worlds}
    began_ns = C.Pub.Storage.monotonic_ns()
    original = C.publication_projection(seed.read_bytes(), C.fixture()['facts'])
    require(not original['world']['paused'] and len(original['world']['sections']) == 104,
            'Complete unpaused demo seed')
    before_logs = set(CLIENT.parent.glob('current-launch.*'))
    images = directory/'images'
    if not finish_retained:
        images.mkdir()
    out, err = directory/'stdout', directory/'stderr'
    observer = runtime/'observer'
    observer_build = json.loads((runtime/'observer-build.json').read_bytes())
    require(observer_build['status'] == 'PASS' and observer_build['binary'] == pin(observer)
            and observer_build['source'] == pin(runtime/'observer.swift'),
            'Exact retained120-second desktop observer')
    environment = dict(os.environ)
    for name in ('MC_LIVE_PORT', 'MC_RENDER_PORT', 'MC_RENDER_TOKEN', 'MC_RENDER_EPOCH',
                 'MC_DEV_TOKEN', 'MC_ACTOR_PID', 'MC_WORLD_PATH', 'MC_COOKING_PROTOCOL',
                 C.INPUT_ENV, C.ACK_ENV):
        environment.pop(name, None)
    environment.update(BEND_MINECRAFT_LAUNCH_MODE='hidden',
                       BEND_MINECRAFT_FRAME_DIR=str(images))
    if finish_retained:
        process = json.loads((directory/'observed-public-demo/result.full.json').read_bytes())
        began_ns = int(process['started_monotonic']*1_000_000_000)
        before_logs = set()
    else:
        G.exclusive(directory/'prepared.json', {'protected_actor': before,
                    'default_world_pins': default_world_pins, 'began_ns': began_ns,
                    'launcher': pin(LAUNCH), 'demo': pin(DEMO), 'seed': pin(seed)})
        with mock.patch.dict(os.environ, environment, clear=True), Host.bindings(R, {
                'WORK': directory, 'GROUPS': directory/'owned-groups.ndjson'}):
            try:
                process = R.bounded([str(observer), str(DEMO), str(out), str(err),
                                     '--frames', '2', '--width', '960', '--height', '540',
                                     '--render-scale', '100'], 140, 'observed-public-demo')
            finally:
                G.sweep_owned(directory)
    R.process_ok(process)
    report = json.loads(Path(process['stdout']['path']).read_text().splitlines()[-1])
    require(not report['timed_out'] and report['child_status'] == 0,
            'Actual public demo exited unsuccessfully: '+err.read_text())
    require(report['before_frontmost_pid'] > 0
            and report['after_frontmost_pid'] == report['before_frontmost_pid']
            and report['sampled_frontmost_pids'] == [report['before_frontmost_pid']]
            and report['space_change_notifications'] == 0
            and not report['activation_notification_pids'], 'Focus or Spaces changed')
    text = out.read_text()
    paths = [Path(line.removeprefix('Cooking demo world copy: '))
             for line in text.splitlines() if line.startswith('Cooking demo world copy: ')]
    require(len(paths) == 1 and paths[0].parent.name.startswith('cooking-demo.')
            and paths[0] != old_world, 'Dedicated unique demo saved world')
    path = paths[0]
    require('MC_WORLD_PATH=' in text and str(path) in text, 'Printed persistent reopen route')
    events = R.PC.events(out)
    closes = [value for value in events if value.get('event') == 'client.menu-close']
    inspections = [value for value in events if value.get('event') == 'client.cooking-inspect']
    saves = [value for value in events if value.get('event') == 'client.save']
    require(len(inspections) == len(closes) == len(saves) == 1
            and inspections[0]['accepted'] and closes[0]['accepted']
            and saves[0]['result']['durable'] and saves[0]['path'] == str(path),
            'Real cooking-aware shutdown and durable acknowledgement')
    frames = [line for line in text.splitlines() if line.startswith('catalog.frame|')]
    timings = [line for line in text.splitlines() if line.startswith('client.timing|')]
    require(len(frames) == len(timings) == 2, 'Actual original Generic two-frame loop')
    ppms = []
    for serial in range(2):
        image = images/f'{serial}.ppm'
        raw = image.read_bytes()
        header = b'P6\n960 540\n255\n'
        require(raw.startswith(header) and len(raw) == len(header)+960*540*3,
                'Complete returned CPU image, not an incomplete write')
        ppms.append(pin(image))
    logs = set(CLIENT.parent.glob('current-launch.*'))-before_logs
    require(len(logs) == 1, 'Exact public actor launch logs')
    log = next(iter(logs))
    ready = [value for value in parse_lines(log/'actor.stdout')
             if value.get('event') in ('server.ready', 'renderer.ready')]
    ports = [value['port'] for value in ready]
    require(len(ports) == 2 and len(set(ports)) == 2
            and not set(ports) & set(before['listeners']),
            'Actual automatic ports avoid the protected conventional pair')
    for port in ports:
        with socket.socket() as probe:
            probe.settimeout(.5)
            require(probe.connect_ex(('127.0.0.1', port)) != 0, 'Public shell listener remained')
    data = C.fixture()
    saved = C.publication_projection(path.read_bytes(), data['facts'])
    require(saved['full'] == original['full'] and saved['bodies'] == original['bodies']
            and saved['effects'] == original['effects'] and not saved['clock_inputs']
            and saved['publication'] == original['publication'] and saved['highwater'] == 42,
            'Complete untouched43/status/WG/Details/publication retention')
    expected = copy.deepcopy(original['world'])
    for _ in range(saved['world']['tick']-expected['tick']):
        S.BASE.apply_tick(expected)
    require(saved['world'] == expected, 'Independent all104 sections and natural Core cadence')
    fresh_entity = C.Pub.Entity.fresh_expected(saved['entities'], began_ns, C.Pub.Storage.monotonic_ns())
    require(saves[0]['result']['bytes'] == path.stat().st_size
            and saves[0]['result']['peer_highwater'] == 42, 'Exact public durable result')
    saved_pin = pin(path)
    cold = None
    cold_directory = directory/'cold'
    cold_directory.mkdir()
    actor_work = ACTOR.parent
    with Host.bindings(A, {'WORK': actor_work, 'SOURCE': actor_work/'source', 'ACTOR': ACTOR}), \
            Host.bindings(Pair, {'WORK': cold_directory}), Host.bindings(R, {
                'WORK': cold_directory, 'GROUPS': cold_directory/'owned-groups.ndjson'}):
        try:
            cold = G.backend(ACTOR, 'actor', path)
            raw, ping = cold.tcp(True)
            require(ping['peer'] == 44, 'Cold local43/public44 peer ownership')
            raw.call('simulation.pause', {'paused': True})
            previous = None
            stabilization_deadline = min(cold.deadline, time.monotonic()+10)
            while time.monotonic() < stabilization_deadline:
                clock = raw.call('world.clock')
                if clock == previous and clock['paused']:
                    break
                previous = clock
                time.sleep(.06)
            else:
                raise AssertionError('Cold paused clock did not stabilize within the declared10 seconds')
            actual_record = C.Menu.inspect_record(raw)
            old_record = S.decode_local(saved['player'])
            require(actual_record.count >= old_record.count
                    and dataclasses.replace(actual_record, count=old_record.count) == old_record,
                    'Actual cold complete player metadata retention apart from advancing count')
            control = C.Menu.connect(cold)
            reply = control.call([15, 0], 8)
            require(reply[4:6] == [True, '']
                    and reply[6] == [[0], [0], C.B.authority(saved['full'], C.B.empty_menu())],
                    'Actual cold complete43-slot authority and closed cooking handle')
            control.call([2])
            control.close()
            cold.private = None
            raw.call('world.save', {})
            restored = C.publication_projection(path.read_bytes(), data['facts'])
            require(restored['player'] == S.local_bytes(actual_record),
                    'Cold save retains the complete observed paused LocalPlayer record')
            for key in ('full', 'bodies', 'effects', 'entities', 'clock_inputs', 'publication'):
                require(restored[key] == saved[key], 'Cold complete retained owner: '+key)
            expected = copy.deepcopy(saved['world'])
            for _ in range(clock['tick']-expected['tick']):
                S.BASE.apply_tick(expected)
            expected['paused'] = True
            require(restored['world'] == expected and restored['highwater'] == 44,
                    'Cold complete104-section Core cadence, pause and durable highwater')
            cold_saved = pin(path)
        finally:
            actions = [('registered groups', lambda: G.sweep_owned(cold_directory))]
            if cold is not None:
                actions.insert(0, ('cold actor', lambda: R.finish_backend(cold)))
            G.finish_owned(actions, cold_directory/'final-cleanup-secondary.json')
    require(protected() == before, 'Historical actor identity/listeners changed')
    if not finish_retained:
        require({str(value): pin(value) if value.is_file() else None for value in default_worlds}
                == default_world_pins, 'A default saved world changed')
    result = {'status': 'PASS', 'actor': pin(ACTOR), 'renderer': pin(CLIENT),
              'launcher': pin(LAUNCH), 'demo': pin(DEMO), 'seed': pin(seed),
              'observer': report, 'process': process, 'world': str(path),
              'automatic_ports': ports, 'protected_actor': before,
              'default_worlds_before': None if finish_retained else default_world_pins,
              'default_world_hash_retention_checked': not finish_retained,
              'original_cpu_frames': ppms, 'frames': frames, 'timings': timings,
              'cooking_inspect': inspections[0], 'menu_close': closes[0], 'save': saves[0],
              'saved_before_cold': saved_pin, 'saved_after_cold': cold_saved,
              'independent_fresh_entity_constructor': fresh_entity,
              'full104_format4_reconstruction': True, 'full43_status_WG_bodies_publication': True,
              'complete_cold_retained_owners': True,
              'retained_public_shell_replayed': False if finish_retained else None,
              'retained_first_failure': pin(directory/'first-failure.json') if finish_retained else None,
              'final_verifier_repair': 'Preserve seeded max_peer=None until an actual developer Core command; only pending cold actor executed.' if finish_retained else None,
              'scope': 'Real public demo shell and original023/012 artifacts. Two returned960x540 CPU images, close/save and cold restore. No injected callbacks, foreground OS input/presentation, full RGB vanilla parity or whole game claim.'}
    G.exclusive(directory/'summary.json', result)
    return result


def finish_saved(directory, runtime_generation):
    """Finish only retained pure verification after both actual owners exited."""
    require(json.loads((directory/'first-failure.json').read_bytes())['message'] ==
            'Independent all104 sections and natural Core cadence', 'Exact retained first failure')
    cold_failure = {
        'message': 'Cold complete104-section Core cadence, pause and durable highwater',
        'expected_max_peer': 0, 'actual_max_peer': None,
        'scope': 'Retained host oracle failure after actual cold inspect/save; no product refusal.'}
    if (directory/'retained-cold-failure.json').exists():
        require(json.loads((directory/'retained-cold-failure.json').read_bytes()) == cold_failure,
                'Exact retained cold oracle failure')
    else:
        G.exclusive(directory/'retained-cold-failure.json', cold_failure)
    runtime = ROOT/'build/generic-resource-world-sample-cooking-runtime'/f'{runtime_generation:03d}'
    process = json.loads((directory/'observed-public-demo/result.full.json').read_bytes())
    R.process_ok(process)
    observer = json.loads(Path(process['stdout']['path']).read_text().splitlines()[-1])
    require(observer['child_status'] == 0 and not observer['timed_out']
            and observer['before_frontmost_pid'] == observer['after_frontmost_pid']
            and observer['sampled_frontmost_pids'] == [observer['before_frontmost_pid']]
            and not observer['activation_notification_pids']
            and observer['space_change_notifications'] == 0, 'Retained original shell/desktop outcome')
    out = directory/'stdout'
    text = out.read_text()
    path = next(Path(line.removeprefix('Cooking demo world copy: ')) for line in text.splitlines()
                if line.startswith('Cooking demo world copy: '))
    require(path.parent.name.startswith('cooking-demo.') and path.name == 'world.nbt', 'Unique demo path')
    events = R.PC.events(out)
    saves = [value for value in events if value.get('event') == 'client.save']
    require(len(saves) == 1 and saves[0]['path'] == str(path)
            and saves[0]['result']['durable'] and saves[0]['result']['peer_highwater'] == 42,
            'Retained real public durable save')
    data = C.fixture()
    actual = C.publication_projection(path.read_bytes(), data['facts'])
    initial = C.publication_projection((runtime/'demo-seed.nbt').read_bytes(), data['facts'])
    replies = parse_lines(directory/'cold/actor/tcp-0.responses')
    requests = parse_lines(directory/'cold/actor/tcp-0.requests')
    require(len(replies) == len(requests) == 7
            and all(reply['id'] == request['id'] and reply['ok']
                    for reply, request in zip(replies, requests)), 'Exact seven correlated cold requests')
    require([value['op'] for value in requests] ==
            ['ping', 'session.open', 'simulation.pause', 'world.clock', 'world.clock', 'player.inspect', 'world.save'],
            'Actual cold read/pause/inspect/save sequence')
    clock = replies[4]['result']
    require(replies[3]['result'] == clock and clock['paused'], 'Actual stable paused cold clock')
    expected = copy.deepcopy(initial['world'])
    for _ in range(clock['tick']-expected['tick']):
        S.BASE.apply_tick(expected)
    expected['paused'] = True
    require(actual['world'] == expected and actual['highwater'] == 44,
            'Complete104-section Core retention/cadence/paused flag and highwater44; max_peer staysNone')
    require(actual['player'] == bytes(replies[5]['result']['nbt_bytes']), 'Complete observed cold player bytes')
    for key in ('full', 'bodies', 'effects', 'clock_inputs', 'publication'):
        require(actual[key] == initial[key], 'Exact untouched owner: '+key)
    require(replies[6]['result'] == {'status': 'durable', 'published': True, 'durable': True,
            'bytes': path.stat().st_size, 'peer_highwater': 44}, 'Exact real cold save acknowledgement')
    private_requests = [json.loads(line) for line in
        (directory/'cold/actor/private-000/private.requests').read_bytes().splitlines() if line.strip()]
    private_replies = [json.loads(line) for line in
        (directory/'cold/actor/private-000/private.responses').read_bytes().splitlines() if line.strip()]
    require(len(private_requests) == len(private_replies) == 3
            and private_requests[1][-1] == [15, 0]
            and private_replies[1][4:6] == [True, '']
            and private_replies[1][6] == [[0], [0], C.B.authority(actual['full'], C.B.empty_menu())],
            'Actual complete cold43-slot cooking authority')
    image_pins = []
    for serial in range(2):
        image = directory/'images'/f'{serial}.ppm'
        raw = image.read_bytes()
        header = b'P6\n960 540\n255\n'
        require(raw.startswith(header) and len(raw) == len(header)+960*540*3, 'Complete retained original CPU P6')
        image_pins.append(pin(image))
    cold = json.loads((directory/'cold/actor/process.json').read_bytes())
    require(cold['exit_code'] == 0 and cold['group_absent'] and all(cold['listeners_absent'])
            and not cold['errors'], 'Actual cold owner exited completely')
    for subdir in (directory, directory/'cold'):
        with Host.bindings(R, {'WORK': subdir, 'GROUPS': subdir/'owned-groups.ndjson'}):
            # Existing cleanup files are immutable; the owner journal is only
            # re-probed and written to a new retained-finalization path.
            groups = R.registered_cleanup()
            require(all(not row['errors'] and not R.live(row['after']) for row in groups), 'Retained own groups absent')
            G.exclusive(subdir/'retained-group-finalization.json', groups)
    protected_owner = protected()
    constructor = C.Pub.Entity.fresh_expected(actual['entities'],
        int(process['started_monotonic']*1_000_000_000), C.Pub.Storage.monotonic_ns())
    logs = list(CLIENT.parent.glob('current-launch.*'))
    require(len(logs) == 1, 'Unambiguous retained first public actor log')
    ready = [value for value in parse_lines(logs[0]/'actor.stdout')
             if value.get('event') in ('server.ready', 'renderer.ready')]
    ports = [value['port'] for value in ready]
    require(len(ports) == len(set(ports)) == 2 and not set(ports) & {25565, 25566},
            'Actual automatic ports avoided the protected conventional listeners')
    for port in ports:
        with socket.socket() as probe:
            probe.settimeout(.5)
            require(probe.connect_ex(('127.0.0.1', port)) != 0, 'Retained public listener remained')
    require((directory/'stderr').read_text().strip() == 'client closed'
            and len([line for line in text.splitlines() if line.startswith('catalog.frame|')]) == 2
            and len([line for line in text.splitlines() if line.startswith('client.timing|')]) == 2,
            'Actual two-frame loop and normal close diagnostic')
    result = {'status': 'PASS', 'actor': pin(ACTOR), 'renderer': pin(CLIENT),
              'launcher': pin(LAUNCH), 'demo': pin(DEMO), 'seed': pin(runtime/'demo-seed.nbt'),
              'public_shell_process': process, 'observer': observer, 'original_CPU_images': image_pins,
              'world': str(path), 'saved': pin(path), 'cold_process': cold,
              'automatic_ports': ports, 'actor_log': pin(logs[0]/'actor.stdout'),
              'actual_full104_format4_reconstruction': True, 'actual_full43_status_WG_bodies_publication': True,
              'actual_complete_cold_player': True, 'independent_fresh_entity_constructor': constructor,
              'protected_actor': protected_owner, 'default_world_prelaunch_hashes_recorded': False,
              'retained_first_failure': pin(directory/'first-failure.json'),
              'retained_cold_failure': pin(directory/'retained-cold-failure.json'),
              'public_shell_gameplay_or_native_replayed': False,
              'scope': 'Original023/012 public demo shell, two complete960x540 CPU images and real durable save/cold restore. Both wrong max_peer=0 host expectations are retained and corrected to seededNone. Initial default-world hashes were not persisted; unique actual save path and protected actor identity/listeners are verified. No callbacks, foreground OS input/presentation or full vanilla image claim.'}
    G.exclusive(directory/'summary.json', result)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--generation', type=int, default=1)
    parser.add_argument('--runtime-generation', type=int, required=True)
    parser.add_argument('--finish-retained', action='store_true')
    parser.add_argument('--finish-saved', action='store_true')
    args = parser.parse_args()
    require(1 <= args.generation <= 999 and 1 <= args.runtime_generation <= 999,
            'Bounded explicit generations')
    directory = ROOT/'build/generic-resource-world-sample-cooking-launcher-runtime'/f'{args.generation:03d}'
    try:
        result = finish_saved(directory, args.runtime_generation) if args.finish_saved else \
            run(directory, args.runtime_generation, finish_retained=args.finish_retained)
    except BaseException as error:
        if directory.exists() and not (directory/'first-failure.json').exists():
            G.exclusive(directory/'first-failure.json', {'type': type(error).__name__, 'message': str(error)})
        raise
    print(json.dumps({'status': result['status'], 'directory': str(directory)}), flush=True)


if __name__ == '__main__':
    main()
