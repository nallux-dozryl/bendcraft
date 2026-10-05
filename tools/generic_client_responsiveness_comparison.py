#!/usr/bin/env python3
"""Matched hidden native drawing envelopes; never builds or activates a client.

The real actor, unchanged-byte relay, native observer and cleanup owners are
reused. Python defines a paused test scene and compares observations only.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import platform
from pathlib import Path
import statistics
import subprocess
import sys
import threading
import time
from unittest import mock

import generic_resource_world_sample_client_runtime as G

R, Pair, Boundary, S, Host = G.R, G.Pair, G.Boundary, G.S, G.Host
ROOT = G.ROOT
WIDTH, HEIGHT, FRAMES, WARMUP = 1920, 1080, 8, 2
PROTECTED = 47566
KNOWN = {
    'actor017': '66bbe97279f8ee268d891ad762d5da40337e1c318d09160e415823e25d4d8bd5',
    'actor022': '1ba545e7ccd84e5011f51199c2ee9562e4063c24b98c64148323551039357712',
    'actor023': '7fd7ee9269802a6e128716f53bf34030ec592728ef954f9b61bebecac36719d1',
    '008': '3134689e2905e3b3a3ca3790f854996f9da49d8ca33b19677890cc4b10c91d04',
    '010': 'c6a861ae04a4de8f918912149ff8ead4e92dfe16d581a7ca2f97983ff9cf3f94',
    '012': '3bd945855c7526f713ed1df03ab89e136429fbc36132f6152ef16fc7a491a232',
}


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def utc():
    return dt.datetime.now(dt.timezone.utc).isoformat()


def write(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open('x') as out:
        json.dump(value, out, indent=2, sort_keys=True)
        out.write('\n')


def processes():
    raw = subprocess.check_output(['ps', '-axo', 'pid,ppid,pgid,pcpu,rss,command'], text=True)
    rows = []
    for line in raw.splitlines()[1:]:
        fields = line.strip().split(None, 5)
        if len(fields) == 6:
            rows.append(dict(zip(('pid', 'ppid', 'pgid', 'cpu_percent', 'rss_kib', 'command'),
                [int(fields[0]), int(fields[1]), int(fields[2]), float(fields[3]), int(fields[4]), fields[5]])))
    return rows


class Loads:
    """Observe foreign work; never signal it or hide a contaminated run."""
    def __init__(self, path):
        self.path, self.stop_event = path, threading.Event()
        self.rows, self.failure = [], None
        original = next((row for row in processes() if row['pid'] == PROTECTED), None)
        R.require(original is not None and '/compiler-producer-diagnostic-012/actor' in original['command'],
                  'Required protected actor012 identity is absent')
        self.protected_command = original['command']
        self.sample('admission')
        if self.rows[-1]['foreign_work']:
            write(self.path, {'samples': self.rows, 'native_launches': 0, 'admission': 'QUEUED'})
        R.require(not self.rows[-1]['foreign_work'], 'Comparison is queued until foreign native/compiler work is quiet')
        self.thread = threading.Thread(target=self.loop, name='comparison-loads', daemon=True)
        self.thread.start()

    def sample(self, phase):
        rows = processes()
        own = {os.getpid()}
        while True:
            extended = own | {row['pid'] for row in rows if row['ppid'] in own}
            if extended == own:
                break
            own = extended
        # Native actor/observer owners use separate groups but remain actual
        # descendants. Their IDs are never classified as foreign producers.
        protected = next((row for row in rows if row['pid'] == PROTECTED), None)
        R.require(protected is not None and protected['command'] == self.protected_command,
                  'Protected012 disappeared or changed identity')
        foreign = []
        for row in rows:
            if row['pid'] in own or row['pid'] == PROTECTED:
                continue
            command = row['command']
            compiler = any(token in command for token in
                ('/.bend/bin/bend ', '--max-old-space-size', '/bin/java ', '/bin/javac ', 'clang -cc1', '/clang '))
            repository_native = '/bendex/' in command and any(token in command for token in
                ('/actor', '/renderer', '/receiver', '/observer', 'test_', 'native.py', 'emit.mjs', 'proof.mjs'))
            if (compiler or repository_native) and (row['cpu_percent'] >= 2 or row['rss_kib'] >= 65536):
                foreign.append(row)
        # Keep broad CPU/RSS evidence without retaining unrelated browser/app
        # arguments. Only project/native producer commands need full identity.
        observed = [dict(row, command=row['command'].split(' --', 1)[0]) for row in rows]
        self.rows.append({'utc': utc(), 'monotonic_ns': time.monotonic_ns(), 'phase': phase,
            'load_average': list(os.getloadavg()), 'protected012': protected,
            'foreign_work': foreign, 'processes': observed})

    def loop(self):
        while not self.stop_event.wait(.25):
            try:
                self.sample('during')
            except BaseException as error:
                self.failure = str(error)
                return

    def finish(self):
        self.stop_event.set()
        self.thread.join(3)
        self.sample('after')
        write(self.path, {'samples': self.rows, 'interval_seconds': .25, 'failure': self.failure})
        R.require(not self.thread.is_alive() and self.failure is None, 'Background observation failed')
        return {'receipt': R.pin(self.path), 'samples': len(self.rows),
            'protected012_cpu_percent': [min(row['protected012']['cpu_percent'] for row in self.rows),
                                        max(row['protected012']['cpu_percent'] for row in self.rows)],
            'protected012_rss_kib': [min(row['protected012']['rss_kib'] for row in self.rows),
                                    max(row['protected012']['rss_kib'] for row in self.rows)],
            'foreign_work_observed': any(row['foreign_work'] for row in self.rows)}


def fixture():
    palette, identity, count = Boundary.palette_and_registry()
    world = Boundary.terrain(count, identity, palette, fresh=True)
    record = Boundary.A.playable_look(Boundary.A.playable_spawn((.5, -60., .5)), 15.)
    main = Boundary.P.playable_inventory()
    main['selected'] = 4
    for index, name, count in ((0, 'dirt', 4), (4, 'stone', 17), (8, 'oak_planks', 6)):
        main['slots'][index] = Boundary.stack('minecraft:' + name, count)
    full = {'main': main, 'equipment': [None] * 7,
        'status': {'invulnerable': True, 'mayfly': True, 'flying': False,
                   'walking_speed': 1036831949, 'flying_speed': 1028443341},
        'generation': Boundary.Generation.stone_dirt_bytes(seed=0)}
    visibility = json.loads(R.Pixels.VISIBILITY_REFERENCE.read_bytes())
    return {'world': world, 'record': record, 'full': full,
        'payload': Boundary.bundle(world, 40, record, full, ''), 'highwater': 40,
        'catalog': G.expected_sample(world, record),
        'legacy': Pair.expected_sample(world, record, visibility),
        'authority': Boundary.authority(full, Boundary.empty_menu())}


class Renderer(R.Renderer):
    def __init__(self, binary, relay, label, helpers, frames, trace):
        original = R.subprocess.Popen
        def launch(argv, *args, **kwargs):
            argv = list(argv)
            if argv and argv[0] == helpers['observer']['artifact']:
                argv += ['--width', str(WIDTH), '--height', str(HEIGHT), '--render-scale', '100',
                         '--hud-scale', '0', '--item-table', str(Boundary.TABLE)]
                kwargs['env'] = dict(kwargs['env'], BEND_MINECRAFT_REGISTRY=str(R.Plain.P.OFFICIAL))
            return original(argv, *args, **kwargs)
        with mock.patch.object(R.subprocess, 'Popen', launch):
            super().__init__(binary, relay, label, helpers, frames=frames, trace=trace, jar=G.JAR)
        write(self.directory/'actual-argv.json', {'argv': list(self.proc.args), 'hidden': True,
            'trace': trace, 'scene': [WIDTH, HEIGHT], 'render_scale': 100, 'hud_scale': 0})


def exchanges(value, data, generation, frame_count):
    epoch, sequence, samples, menus, pending = None, 1, [], [], None
    for exchange in value['exchanges']:
        request, reply = exchange['request'], exchange['reply']
        R.require(exchange['forwarded_unchanged'], 'Comparison relay substituted actual bytes')
        if request[:2] == [1, 0]:
            R.require(epoch is None and reply[:2] == [1, 0] and len(reply) == 4 and reply[3] == 0,
                      'Actual Hello correlation')
            epoch = reply[2]
            continue
        R.require(request[:4] == [1, 1, epoch, sequence] and reply[0] == 1
                  and reply[2:4] == [epoch, sequence], 'Actual epoch/sequence correlation')
        command = request[4]
        sequence += 1
        if command[0] in (0, 13):
            wanted_tag = 0 if generation == '008' else 13
            R.require(command[0] == wanted_tag and command[1:] in ([128, 128], [WIDTH, HEIGHT])
                      and reply[1] == (1 if wanted_tag == 0 else 7) and len(reply) == 5
                      and pending is None, 'Actual sample extent/tag/pair')
            actual = R.decode_sample(reply[4]) if wanted_tag == 0 else reply[4]
            expected = data['legacy'] if wanted_tag == 0 else data['catalog']
            R.require(actual == expected, 'Full actual sample differs from paused fixture')
            samples.append(digest(R.canonical(actual)))
            pending = request[3]
        elif command[0] in (8, 15):
            cooking = generation not in ('008', '010')
            R.require(command == ([15, 0] if cooking else [8])
                      and reply[1] == (8 if cooking else 6) and len(reply) == 7
                      and reply[4:6] == [True, ''] and pending is not None,
                      'Actual complete menu reply differs')
            snapshot = reply[6]
            if cooking:
                R.require(snapshot[:2] == [[0], [0]] and len(snapshot) == 3,
                          'Comparison unexpectedly opened cooking menu')
                snapshot = snapshot[2]
            R.require(snapshot == data['authority'], 'Complete actual inventory/equipment/status/menu differs')
            menus.append(digest(R.canonical(snapshot)))
            pending = None
        elif command[0] == 1:
            R.require(reply == [1, 2, epoch, request[3]] and len(command) == 2
                      and command[1][:2] == [False, False]
                      and all(action == [0] for action in command[1][2]), 'Unexpected gameplay input')
        else:
            R.require(command == [2] and reply == [1, 2, epoch, request[3]], 'Unexpected command')
    R.require(pending is None and len(samples) == len(menus) == frame_count, 'Incomplete real frame/menu pairs')
    return {'pairs': frame_count, 'sample_sha256': sorted(set(samples)),
            'MenuSnapshot_sha256': sorted(set(menus)), 'all_correlated_actual_bytes': True}


def trial(directory, actor_binary, binary, generation, data, helpers, trace):
    directory.mkdir()
    path = directory/'world.nbt'
    path.write_bytes(data['payload'])
    actors = renderer = relay = None
    load = Loads(directory/'loads.json')
    report = {'status': 'FAIL', 'utc_started': utc(), 'generation': generation, 'trace': trace}
    try:
        with Host.bindings(R, {'WORK': directory, 'GROUPS': directory/'owned-groups.ndjson'}), \
                Host.bindings(Pair, {'WORK': directory}):
            actors = G.backend(actor_binary, 'backend', path)
            client, ping = actors.tcp(True)
            R.require(ping['peer'] == data['highwater']+2, 'Actual saved/player/public peer identity')
            before = {'player': client.call('player.inspect'), 'inventory': client.call('inventory.inspect'),
                      'clock': client.call('world.clock')}
            S.inspect(client, data['record'])
            R.require(before['inventory'] == data['full']['main'], 'Actual initial main inventory differs')
            client.call('world.save', {})
            saved_before = path.read_bytes()
            relay = Pair.Relay(actors, 'relay')
            count = 2 if trace else FRAMES
            renderer = Renderer(binary, relay, 'renderer', helpers, count, trace)
            report['observer'] = renderer.finish(frames=count if generation == '008' else None)
            relay_value, relay_pin = relay.finish()
            report['correlation'] = exchanges(relay_value, data, generation, count)
            report['relay'] = relay_pin
            after = {'player': client.call('player.inspect'), 'inventory': client.call('inventory.inspect'),
                     'clock': client.call('world.clock')}
            S.inspect(client, data['record'])
            R.require(before == after, 'Actual complete player/main/clock changed during hidden rendering')
            save = client.call('world.save', {})
            saved_after = path.read_bytes()
            R.require(saved_before == saved_after and save['durable'] is True and save['bytes'] == len(saved_after),
                      'Actual acknowledged full saved owner changed during rendering')
            report['state'] = {'before': before, 'after': after, 'whole_saved_bytes': len(saved_after),
                'whole_saved_sha256': digest(saved_after), 'unchanged_whole_owner': True, 'acknowledgement': save}
            lines = renderer.out.read_text().splitlines()
            timings = [line.split('|') for line in lines if line.startswith('client.timing|')]
            R.require(len(timings) == count and [int(row[1]) for row in timings] == list(range(count)),
                      'Actual timing serials missing')
            report['timings_ms'] = [int(row[2]) for row in timings]
            if generation != '008':
                markers = [line.split('|') for line in lines if line.startswith('catalog.frame|')]
                R.require(len(markers) == count and all(len(row) == 6 for row in markers)
                    and [int(row[1]) for row in markers] == list(range(count))
                    and all(row[2] == data['world']['registry'] and int(row[3]) == data['world']['tick']
                            and int(row[4]) == data['world']['revision'] and int(row[5]) == 512 for row in markers),
                    'Actual catalog descriptions differ')
            if trace:
                header = f'P6\n{WIDTH} {HEIGHT}\n255\n'.encode()
                images = [renderer.images/(str(i)+'.ppm') for i in range(count)]
                raw = [image.read_bytes() for image in images]
                R.require(all(value.startswith(header) and len(value) == len(header)+WIDTH*HEIGHT*3
                              for value in raw) and raw[0] == raw[1], 'Actual full1080 image extent/stability')
                report['images'] = [R.pin(image) for image in images]
                report['rgb_sha256'] = digest(raw[0][len(header):])
            else:
                R.require(not renderer.images.exists() and not any(line.startswith('resource.image|') for line in lines),
                          'Timed trace-off run wrote images')
            report.update(status='PASS', utc_finished=utc())
    except BaseException as error:
        report['error'] = {'type': type(error).__name__, 'message': str(error)}
        raise
    finally:
        G.finish_owned([('renderer', lambda: renderer.cleanup() if renderer else None),
                        ('relay', lambda: relay.finish(failed=True) if relay and relay.thread.is_alive() else None),
                        ('actor', lambda: R.finish_backend(actors) if actors else None)], directory/'cleanup-secondary.json')
        with Host.bindings(R, {'WORK': directory, 'GROUPS': directory/'owned-groups.ndjson'}):
            G.sweep_owned(directory)
        report['loads'] = load.finish()
        if report['loads']['foreign_work_observed']:
            report['status'] = 'FAIL_CONTAMINATED'
            report['error'] = {'type': 'ForeignWorkObserved',
                'message': 'Retained native observations have no quiet comparative claim'}
        write(directory/'report.json', report)
    R.require(not report['loads']['foreign_work_observed'], 'Competing workload observed; retained run has no clean comparison claim')
    return report


def initialized_baseline(directory, actor_binary, data):
    """Persist genuine factory entropy once; every common-actor arm restores it."""
    directory.mkdir()
    path = directory/'world.nbt'
    path.write_bytes(data['payload'])
    actor = None
    loads = Loads(directory/'loads.json')
    value = {'status': 'FAIL'}
    try:
        with Host.bindings(R, {'WORK': directory, 'GROUPS': directory/'owned-groups.ndjson'}), \
                Host.bindings(Pair, {'WORK': directory}):
            actor = G.backend(actor_binary, 'backend', path)
            client, ping = actor.tcp(True)
            R.require(ping['peer'] == data['highwater']+2, 'Baseline real peer identity')
            S.inspect(client, data['record'])
            acknowledgement = client.call('world.save', {})
            raw = path.read_bytes()
            R.require(acknowledgement['durable'] is True and acknowledgement['bytes'] == len(raw),
                      'Baseline actual complete durable publication')
            data['payload'] = raw
            data['highwater'] = acknowledgement['peer_highwater']
            value.update(status='PASS', actual_unchanged_Record=True, baseline=R.pin(path),
                acknowledgement=acknowledgement, purpose='Single real factory initialization, persisted before any comparison arm; restored with exact RNG/clock/publication bytes, never fabricated by host.')
    finally:
        if actor:
            R.finish_backend(actor)
        with Host.bindings(R, {'WORK': directory, 'GROUPS': directory/'owned-groups.ndjson'}):
            G.sweep_owned(directory)
        value['loads'] = loads.finish()
        if value['loads']['foreign_work_observed']:
            value['status'] = 'FAIL_CONTAMINATED'
            value['error'] = {'type': 'ForeignWorkObserved',
                'message': 'Actual initialization was not quiet; comparison cannot proceed'}
        write(directory/'report.json', value)
    R.require(not value['loads']['foreign_work_observed'], 'Baseline initialization was not quiet')
    return value


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--native', action='store_true', help='Run existing hidden native owners; default prepares only')
    parser.add_argument('--actor-generation', choices=(17, 22, 23), type=int, default=17)
    parser.add_argument('--clients', default='008,010', help='Historical008,010 on017/022; fixed-quality010,012 on023')
    args = parser.parse_args()
    clients = args.clients.split(',')
    cooking = len(clients) == 3 and clients[:2] == ['008', '010'] and clients[2].isdigit() and int(clients[2]) >= 11
    fixed_quality = clients == ['010', '012']
    R.require(clients == ['008', '010'] or cooking or fixed_quality, 'Predeclared supported comparison arms')
    R.require((fixed_quality and args.actor_generation == 23)
              or (not fixed_quality and args.actor_generation in (17, 22)), 'Comparison cohort cannot mix actor generations')
    R.require(not cooking or args.actor_generation == 22, 'Historical three-arm preparation requires Actor022')
    parent = ROOT/'build/generic-client-responsiveness-comparison'
    parent.mkdir(exist_ok=True)
    number = max([int(p.name) for p in parent.iterdir() if p.is_dir() and p.name.isdigit()] or [0])+1
    work = parent/f'{number:03}'
    work.mkdir()
    binaries = {key: ROOT/(f'build/playable-renderer-current/{key}/renderer' if key == '008'
                else f'build/generic-resource-world-sample-client-native/{key}/renderer') for key in clients}
    actor = ROOT/f'build/compiler-producer-diagnostic-{args.actor_generation:03}/actor'
    helpers = Pair.observer()
    helper_paths = [Path(module.__file__) for module in (G, R, Pair, Boundary, S, Host,
        Boundary.Generation, Boundary.Inventory)]
    inputs = {str(path): R.pin(path) for path in [Path(__file__), actor, *binaries.values(), G.JAR,
        Boundary.TABLE, R.Plain.P.OFFICIAL, R.Pixels.VISIBILITY_REFERENCE, *helper_paths,
        Path(helpers['observer']['artifact'])]}
    builds = {}
    for key, binary in binaries.items():
        if key in KNOWN:
            R.require(inputs[str(binary)]['sha256'] == KNOWN[key], 'Retained renderer identity differs')
        if key != '008':
            value = G.client_artifact(binary)
            paths = [binary.parent/'build.json', Path(value['source_map']['path']), Path(value['manifest']['path'])]
            inputs.update({str(path): R.pin(path) for path in paths})
            builds[key] = {'build_receipt': R.pin(paths[0]), 'source_map': value['source_map'],
                'manifest': value['manifest'], 'native_command': value['native']['command'],
                'source_deltas_from_declared_baseline': value['generation_basis']['only_project_source_deltas']}
            R.require('-O3' in value['native']['command'], 'Retained renderer optimization flags differ')
            if key == '012':
                R.require('-fno-stack-check' in value['native']['command'], '012 accepted native stack-check flag missing')
    R.require(inputs[str(actor)]['sha256'] == KNOWN[f'actor{args.actor_generation:03}'], 'Retained actor identity differs')
    if fixed_quality:
        receipt = actor.parent/'native-build.json'
        value = json.loads(receipt.read_bytes())
        R.require(value['status'] == 'PASS' and value['binary'] == inputs[str(actor)]
                  and value['generation_basis']['baseline_generation'] == 22
                  and value['generation_basis']['only_project_source_deltas'] == ['src/remote_resource_backend.bend'],
                  'Actor023 genuine completed native receipt/cohort mismatch')
        inputs[str(receipt)] = R.pin(receipt)
    data = fixture()
    (work/'fixture.nbt').write_bytes(data['payload'])
    # ABBA for two arms; balanced positions ABC/BCA/CAB for three arms.
    order = [clients[0], clients[1], clients[1], clients[0]] if len(clients) == 2 else \
            clients + clients[1:]+clients[:1] + clients[2:]+clients[:2]
    preparation = {'status': 'PREPARED', 'utc': utc(), 'actor_generation': args.actor_generation,
        'hardware': {'platform': platform.platform(), 'machine': platform.machine(),
            'logical_cpus': os.cpu_count(), 'sysctl': subprocess.check_output(
                ['sysctl', 'hw.model', 'hw.physicalcpu', 'hw.logicalcpu', 'hw.memsize'], text=True).splitlines()},
        'clients': clients, 'settings': {'scene': [WIDTH, HEIGHT], 'output': [WIDTH, HEIGHT],
        'render_percent': 100, 'hud_scale': 'automatic4/480x270', 'workers': 2, 'gpu': 'off',
        'paused': True, 'seed': 0, 'eye_body': [.5, -60., .5], 'pitch_degrees': 15., 'menu': 'closed'},
        'frames_per_timed_trial': FRAMES, 'predeclared_warmup_frames': WARMUP, 'order': order,
        'fixture': R.pin(work/'fixture.nbt'), 'catalog_sample_sha256': digest(R.canonical(data['catalog'])),
        'legacy_sample_sha256': digest(R.canonical(data['legacy'])), 'menu_sha256': digest(R.canonical(data['authority'])),
        'inputs': inputs, 'renderer_builds': builds, 'protected012_pid': PROTECTED,
        'cohort': 'Fixed-quality010/012 commonActor023' if fixed_quality else 'Historical017/022 preparation;006 image mismatch remains retained',
        'scope': 'Paused render/composition/Window.frame envelope only; excludes query/resource/menu preparation. Returned CPU images; no drawable readback, OS-input, FPS, active server20TPS, cooking throughput or whole-game claim.'}
    write(work/'preparation.json', preparation)
    if not args.native:
        print(json.dumps({'status': 'PREPARED', 'work': str(work), 'native_launches': 0}))
        return
    report = {'status': 'FAIL', 'preparation': R.pin(work/'preparation.json'), 'prechecks': [], 'trials': []}
    try:
        if args.actor_generation in (22, 23):
            report['initialized_baseline'] = initialized_baseline(work/'initialized-baseline', actor, data)
        for key in clients:
            row = trial(work/('precheck-'+key), actor, binaries[key], key, data, helpers, True)
            report['prechecks'].append({'client': key, 'report': R.pin(work/('precheck-'+key)/'report.json'),
                'rgb_sha256': row['rgb_sha256'], 'whole_saved_sha256': row['state']['whole_saved_sha256']})
        expected_ppm = (work/('precheck-'+clients[0])/'renderer/images/0.ppm').read_bytes()
        expected_saved = (work/('precheck-'+clients[0])/'world.nbt').read_bytes()
        for key in clients[1:]:
            R.require((work/('precheck-'+key)/'world.nbt').read_bytes() == expected_saved,
                      'Whole actual saved state differs between comparison arms')
            actual = (work/('precheck-'+key)/'renderer/images/0.ppm').read_bytes()
            if actual != expected_ppm:
                header_size = len(f'P6\n{WIDTH} {HEIGHT}\n255\n'.encode())
                a, b = actual[header_size:], expected_ppm[header_size:]
                first = [index for index in range(WIDTH*HEIGHT)
                         if a[index*3:index*3+3] != b[index*3:index*3+3]][:16]
                report['pixel_mismatch'] = {'client': key, 'expected_client': clients[0],
                    'first_differences': [{'xy': [i % WIDTH, i // WIDTH],
                        'actual': list(a[i*3:i*3+3]), 'expected': list(b[i*3:i*3+3])} for i in first]}
            R.require(actual == expected_ppm, 'Actual full1080 RGB pixels differ; no timing comparison')
        for index, key in enumerate(order):
            label = f'timed-{index+1:02}-{key}'
            row = trial(work/label, actor, binaries[key], key, data, helpers, False)
            R.require((work/label/'world.nbt').read_bytes() == expected_saved,
                      'Timed workload differs from image precheck state')
            report['trials'].append({'client': key, 'utc_started': row['utc_started'],
                'utc_finished': row['utc_finished'], 'all_frames_ms': row['timings_ms'],
                'warm_frames_ms': row['timings_ms'][WARMUP:], 'loads': row['loads'],
                'report': R.pin(work/label/'report.json')})
        for path, expected in inputs.items():
            R.require(R.pin(Path(path)) == expected, 'Comparison input changed: '+path)
        for key, binary in binaries.items():
            if key != '008':
                G.client_artifact(binary)
        report['summary'] = {}
        for key in clients:
            rows = [row for row in report['trials'] if row['client'] == key]
            values = [value for row in rows for value in row['warm_frames_ms']]
            report['summary'][key] = {'warm_frames': len(values), 'warm_median_ms': statistics.median(values),
                'warm_mean_ms': statistics.mean(values), 'warm_min_ms': min(values), 'warm_max_ms': max(values)}
        report.update(status='PASS_NARROW', confidence='high for observed matched drawing envelopes',
            image_pixels_exact=WIDTH*HEIGHT, whole_saved_state_exact=True, protected012_present_every_sample=True,
            scope=preparation['scope'], warmup=preparation['predeclared_warmup_frames'], order=order)
    except BaseException as error:
        report['error'] = {'type': type(error).__name__, 'message': str(error)}
        raise
    finally:
        write(work/'result.json', report)
        evidence = ROOT/'evidence'/f'generic-client-responsiveness-comparison-{number:03}.json'
        write(evidence, report)
    print(json.dumps({'status': report['status'], 'summary': report['summary'], 'evidence': str(evidence)}))


if __name__ == '__main__':
    main()
