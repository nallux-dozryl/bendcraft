#!/usr/bin/env python3
"""Prepare a hidden resource-backed Player client; native mode needs a lead slot.

Python orchestrates the unchanged normal entry and independent NBT/Java fixtures.
Default performs ordinary checking/provenance only, without C emission, client
launches, UI activation, screenshots, input posting or permission requests.
"""
from __future__ import annotations

import argparse
from collections import Counter
from contextlib import contextmanager
import json
import os
from pathlib import Path
import re
import shutil
import socket
import subprocess
import sys
import time
import zipfile

import test_player_client as PC
import test_player_session as Session

ROOT = PC.ROOT
WORK = ROOT / 'build/resource-player-client'
ENTRY = ROOT / 'resource_player_client.bend'
SCENE = ROOT / 'src/resource_player_scene.bend'
PREFLIGHT = ROOT / 'evidence/resource-player-client-preflight.json'
NATIVE = ROOT / 'evidence/resource-player-client-native.json'
BUILD = WORK / 'build.full.json'
SEAL = WORK / 'seal.full.json'
REFERENCE = WORK / 'reference.full.json'
BaseClient = PC.Client
OBSERVED = []
RENDERER = 'resource-visibility-instrument'
BOUNDARY = [
    'Normal resource entry, four-state static-white-light CPU domain and neutral plain Player .1d/.08d/.42d profile; not LocalPlayer.',
    'Hidden launches install no held OS input and establish no focused capture, visible presentation, UI, audio or full-game parity.',
    'client.frame is described before draw. Successful bounded exit establishes the source-defined frame loop, not independent pixels/presentation.',
    'Separate WRF native evidence covers its sealed quads/texels/pixels; this presenter entry has no readback and does not inherit a new pixel result.',
    'Resource selection is explicit zero-transform stone/dirt/oak-planks with normalized static textures, Solid layers and white tint/light; no general blockstate, lighting/AO, biome tint, animation, atlas or GPU claim.',
    'Frame/API queries do not define simulation time. Cadence uses the actual 50ms actor timer and no simulation.step; no gameplay performance claim.',
    'Native failure recovery observes exit/listener/lease/durable bytes, not deep serialization of every asset owner or a heap/FD leak theorem.',
    'Declared unsafe/foreign boundaries and prior full-import kernel limitations remain explicit; no whole-client theorem.',
]


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def sha(path):
    return PC.sha(path)


def write(path, value):
    Session.write_json(path, value)


@contextmanager
def borrowed():
    """Isolate helper paths in this process; no existing file is edited."""
    changes = {'ENTRY': ENTRY, 'WORK': WORK, 'PREFLIGHT': PREFLIGHT, 'NATIVE': NATIVE,
               'REFERENCE': REFERENCE, 'RECEIPT': BUILD, 'Client': ResourceClient}
    previous = {name: getattr(PC, name) for name in changes}
    for name, value in changes.items():
        setattr(PC, name, value)
    try:
        yield
    finally:
        for name, value in previous.items():
            setattr(PC, name, value)


def build_argv():
    return [sys.executable, str(ROOT / 'tools/platform_cache.py'), 'build', str(ENTRY),
            '-o', str(WORK / 'client'), '--report', str(BUILD)]


def snapshot():
    return {'runner_sha256': sha(__file__), 'borrowed_helper_sha256': sha(PC.__file__),
            'client_snapshot': PC.source_snapshot()}


def retained_helpers():
    observer = ROOT / 'build/player-client/observer'
    source = ROOT / 'build/player-client/observer.swift'
    pin = json.loads((ROOT / 'build/player-client/observer-pin.full.json').read_text())
    compile_report = ROOT / 'build/player-client/observer-build.full.json'
    actual = json.loads(compile_report.read_text())
    require(not actual['timed_out'] and actual['exit_code'] == 0
            and source.read_text() == PC.OBSERVER and sha(source) == pin['source_sha256']
            and sha(observer) == pin['binary_sha256'], 'verified read-only desktop observer changed')
    receipt = Session.verify_receipt(Session.source_hashes())
    mcp = receipt['builds'][1]
    bridge = Path(mcp['artifact'])
    require(sha(bridge) == mcp['binary_sha256'], 'frozen actual MCP binary changed')
    return {'observer': {'source': str(source), 'source_sha256': sha(source), 'artifact': str(observer),
                         'binary_sha256': sha(observer), 'build_receipt_sha256': sha(compile_report)},
            'mcp': {'artifact': str(bridge), 'binary_sha256': sha(bridge), 'cache_key': mcp['cache_key'],
                    'dependency_count': len(mcp['dependencies']),
                    'dependency_manifest_sha256': PC.Cache.native.digest(PC.Cache.native.encoded(mcp['dependencies']))}}


def wrf_receipt():
    path = ROOT / 'evidence/world-resource-frame-native.json'
    value = json.loads(path.read_text())
    require(value['status'] == 'passed_bounded_domain' and value['generation_unchanged']
            and value['generation_before'] == value['generation_after']
            and value['totals']['cases'] == 97, 'WRF independent evidence has not passed its stated domain')
    for name, digest in value['generation_after'].items():
        source = Path(name) if Path(name).is_absolute() else ROOT / name
        require(sha(source) == digest, 'WRF accepted generation changed: ' + name)
    require(sha(ROOT / value['binary']['path']) == value['binary']['sha256']
            == value['binary_sha256_after'], 'WRF accepted native artifact changed')
    require(sha(ROOT / value['binary_retained_c']['path']) == value['binary_retained_c']['sha256'],
            'WRF emitted C changed')
    return {'receipt': str(path.relative_to(ROOT)), 'sha256': sha(path),
            'status': value['status'], 'totals': value['totals'], 'scope': value['scope'],
            'whole_facade_kernel_verified': value['whole_facade_kernel_verified'],
            'integration_pixel_readback_claim': False}


def asset_fixtures():
    # These eight official assets are the explicit three-model/four-state domain,
    # including the exact parent chain. The oracle never manufactures geometry.
    names = ['assets/minecraft/models/block/' + name + '.json'
             for name in ('stone', 'dirt', 'oak_planks', 'cube_all', 'cube')]
    names += ['assets/minecraft/textures/block/' + name + '.png'
              for name in ('stone', 'dirt', 'oak_planks')]
    with zipfile.ZipFile(PC.JAR) as archive:
        official = {name: archive.read(name) for name in names}
    changed = 'assets/minecraft/textures/block/dirt.png'
    broken = WORK / 'broken-dirt-texture.jar'
    with zipfile.ZipFile(broken, 'w', compression=zipfile.ZIP_STORED) as output:
        for name in sorted(official):
            header = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            data = b'invalid independently supplied PNG bytes' if name == changed else official[name]
            output.writestr(header, data)
    with zipfile.ZipFile(broken) as archive:
        require(archive.testzip() is None and archive.read(changed) != official[changed],
                'bad PNG fixture failed ZIP integrity or was not changed')
        require(all(archive.read(name) == official[name] for name in official if name != changed),
                'bad PNG fixture changed another asset')
    invalid = WORK / 'invalid-zip.jar'
    invalid.write_bytes(b'invalid ZIP fixture')
    bad_sine = WORK / 'invalid-sine'
    bad_sine.write_bytes(b'invalid exact sine-table fixture')
    return {'official_selected_assets': {n: {'bytes': len(data), 'sha256': Session.sha(data)}
                                         for n, data in sorted(official.items())},
            'broken_png': {'path': str(broken), 'sha256': sha(broken), 'changed_entry': changed,
                           'zip_integrity_valid': True, 'other_selected_bytes_unchanged': True},
            'invalid_zip': {'path': str(invalid), 'sha256': sha(invalid)},
            'invalid_sine': {'path': str(bad_sine), 'sha256': sha(bad_sine)}}


def ordinary():
    rows = []
    for entry in (ENTRY, SCENE):
        value = PC.bounded([PC.BEND, entry, '--check-only'], timeout=90)
        text = value['stdout'] + value['stderr']
        matched = re.fullmatch(r'SOME PROOFS FAIL\nError: ([0-9]+) defs rely on unsafe or foreign code:\n((?:- [^\n]+\n)+)', text)
        require(not value['timed_out'] and value['exit_code'] == 1 and matched is not None,
                'ordinary check has an actual diagnostic beyond inherited boundaries: ' + str(entry))
        count = int(matched[1])
        require(count == len(matched[2].splitlines()), 'foreign-boundary names/count differ')
        full = WORK / (entry.stem + '-ordinary.full.json')
        write(full, value)
        rows.append({'entry': str(entry.relative_to(ROOT)), 'entry_sha256': sha(entry),
                     'declared_boundary_count': count, 'exit_code': 1, 'seconds': value['seconds'],
                     'output_sha256': Session.sha(text.encode()), 'full_report': str(full), 'full_report_sha256': sha(full)})
    require({row['declared_boundary_count'] for row in rows} == {79, 92}, 'ordinary counts differ from root source handoff')
    return rows


def scenario():
    return {'normal_entry': str(ENTRY.relative_to(ROOT)), 'gpu': 'off', 'launch_mode': 'hidden',
            'logical_image': [128, 128], 'native_window': [512, 512], 'renderer': RENDERER,
            'catalog': sorted(PC.EXPECTED_OPERATIONS), 'catalog_count': 18,
            'successful_lanes': ['paused actual palette/load/presenter/TCP/MCP; Java idle ticks and queued edit save',
                'paused reload; separately observe tick4/revision50/36blocks/216neighbor reads and tick5/revision53/39blocks/234reads',
                'nonzero raw degree saved look with exact rational F32 radians and durable record',
                '--unpaused real actor timer without simulation.step or held inputs', 'frames0 recovery'],
            'failure_lanes': ['exclusive lease contender', 'unknown argv', 'missing sine', 'missing jar',
                'invalid ZIP', 'valid ZIP with broken official dirt PNG', 'invalid custom bundle',
                'unsupported registry state causes actual frame query failure then valid bundle restart'],
            'frames': {'initial': 500, 'restart': 200, 'saved_look': 100, 'timer': 100,
                       'failure_readiness_maximum': 500, 'recovery': 0},
            'max_build_seconds': 600, 'max_launch_seconds': 60,
            'api_step_rule': 'only explicit paused fixture lane; forbidden throughout the cadence lane',
            'no_held_os_input_claim': True, 'no_pixel_or_visible_presentation_claim': True}


def preflight():
    WORK.mkdir(parents=True, exist_ok=True)
    before = snapshot()
    helpers = retained_helpers()
    prior = wrf_receipt()
    assets = asset_fixtures()
    reference = PC.observe_reference()
    # Raw classpath/runtime manifests stay ignored. Summary pins all their bytes.
    write(WORK / 'reference-summary.full.json', reference)
    reference_summary = {k: v for k, v in reference.items() if k != 'actual_classpath'}
    reference_summary['actual_classpath_manifest_sha256'] = Session.sha(Session.canonical(reference['actual_classpath']))
    checks = ordinary()
    env = dict(os.environ)
    env['CC'] = str(PC.Cache.native.resolve_executable(env.get('CC', 'clang'), env))
    deps, context, _ = PC.Cache._collect(ENTRY, PC.BEND.resolve(), env)
    build_context = WORK / 'preliminary-build-context.full.json'
    write(build_context, context)
    require(before == snapshot() and helpers == retained_helpers(), 'generation changed during preparation')
    model, _, registry = PC.official_scene()
    seal = {'snapshot': before, 'helpers': helpers, 'reference': reference, 'ordinary': checks,
            'asset_fixtures': assets, 'wrf': prior, 'scenario': scenario()}
    write(SEAL, seal)
    report = {'date': PC.timestamp(), 'status': 'prepared-native-unverified',
              'command': 'python3 tools/test_resource_player_client.py --prepare', 'tool_sha256': sha(__file__),
              'seal': str(SEAL), 'seal_sha256': sha(SEAL),
              'snapshot': {'sha256': Session.sha(Session.canonical(before)),
                  'source_dependency_count': before['client_snapshot']['bend_native_effect_dependency_count'],
                  'source_kind_counts': before['client_snapshot']['bend_native_effect_kind_counts'],
                  'project_source_sha256': {name: sha(ROOT / name) for name in (
                      'resource_player_client.bend', 'src/resource_player_scene.bend', 'src/player_scene.bend',
                      'src/player_runtime.bend', 'src/player_session.bend', 'src/world_resource_frame.bend',
                      'src/resource_frame.bend', 'src/world_visibility.bend')},
                  'resources_sha256': before['client_snapshot']['resource_sha256']},
              'ordinary_checks': checks, 'reference': reference_summary, 'retained_helpers': helpers,
              'prior_wrf_receipt': prior, 'scenario': scenario(), 'asset_fixtures': assets,
              'independent_initial': {'clock': Session.P.clock(model), 'blocks': 39, 'sections': len(model['sections']),
                  'core_sha256': Session.sha(Session.P.canonical_expected(model)),
                  'player_record_sha256': Session.sha(Session.initial_record()), 'registry': registry},
              'preliminary_build_context': {'path': str(build_context), 'sha256': sha(build_context),
                  'manifest_sha256': PC.Cache.native.digest(PC.Cache.native.encoded(deps.manifest())),
                  'dependency_count': len(deps.manifest()), 'kind_counts': dict(Counter(i['kind'] for i in deps.manifest())),
                  'environment_sha256': context['environment_sha256'], 'route': context['route'],
                  'compiler': context['compiler'], 'objc_flags': context['objc_flags'],
                  'boundary': 'no C emitted; complete SDK/header/module/framework/link closure is deferred to actual guarded cache build'},
              'requested_build_argv': build_argv(), 'build_process_group_timeout_seconds': 600,
              'build_and_launches_started': False, 'visible_launches': 0, 'screenshots': 0,
              'input_posts': 0, 'permission_requests': 0, 'boundary': BOUNDARY}
    write(PREFLIGHT, report)
    return report


def audit_preflight():
    prepared = json.loads(PREFLIGHT.read_text())
    require(prepared['tool_sha256'] == sha(__file__) and sha(SEAL) == prepared['seal_sha256'], 'preparation tool/seal changed')
    seal = json.loads(SEAL.read_text())
    require(snapshot() == seal['snapshot'] and retained_helpers() == seal['helpers'] and wrf_receipt() == seal['wrf'],
            'source/helper/resource generation changed')
    PC.reference_records({'reference': seal['reference']})
    for checked in seal['ordinary']:
        value = json.loads(Path(checked['full_report']).read_text())
        require(sha(checked['full_report']) == checked['full_report_sha256'] and
                Session.sha((value['stdout'] + value['stderr']).encode()) == checked['output_sha256'] and
                not value['timed_out'] and value['exit_code'] == 1, 'ordinary receipt changed')
    for name in ('broken_png', 'invalid_zip', 'invalid_sine'):
        require(sha(seal['asset_fixtures'][name]['path']) == seal['asset_fixtures'][name]['sha256'], 'failure asset changed')
    return prepared, seal


class ResourceClient(BaseClient):
    """Reuse startup/protocol/cleanup; retain all original focus and exit checks."""
    observed = OBSERVED

    def __init__(self, *args, mode='hidden', **kwargs):
        require(mode == 'hidden', 'this resource suite authorizes hidden launches only')
        super().__init__(*args, mode=mode, **kwargs)

    def finish(self, *, status=0, frame_count=None):
        for client in self.clients:
            client.finish()
            self.mcp_request_count += client.requests
        for client in self.raw_clients:
            self.raw_request_count += client.count
            client.close()
        self.clients, self.raw_clients = [], []
        stdout, stderr = self.process.communicate(timeout=65)
        require(self.process.returncode == 0 and not stderr, 'desktop observer failed: ' + stderr[-500:])
        report = json.loads(stdout.strip())
        require(not report['timed_out'] and report['child_status'] == status, 'native child exit differs: ' + str(report))
        before = report['before_frontmost_pid']
        require(before > 0 and before == report['after_frontmost_pid'] and report['sampled_frontmost_pids'] == [before],
                'frontmost app changed')
        require(report['space_change_notifications'] == 0 and self.pid not in report['activation_notification_pids'],
                'native child activation or Spaces change observed')
        data, errors = self.out.read_bytes(), self.err.read_bytes()
        require(Session.MCP.TOKEN.encode() not in data + errors, 'child disclosed fixture token')
        frames = [e for e in PC.events(self.out) if e.get('event') == 'client.frame']
        require(all(e['renderer'] == RENDERER and e['neighbor_reads'] == 6 * e['blocks'] for e in frames),
                'resource renderer/neighbor-read metadata differs')
        if frame_count is not None:
            require(len(frames) == frame_count, 'frame-loop description count differs')
        with socket.socket() as probe:
            probe.settimeout(1)
            require(probe.connect_ex(('127.0.0.1', self.port)) != 0, 'closed resource client left listener')
        report.update(scenario=self.label, argv=self.argv, launch_mode=self.mode, frame_descriptions=len(frames),
                      no_listener_after_exit=True, stdout_sha256=Session.sha(data), stderr_sha256=Session.sha(errors),
                      diagnostic=errors.decode().strip()[:400])
        self.report = report
        return frames


def wait_frame(client, tick, revision, blocks):
    deadline = time.monotonic() + 5
    while time.monotonic() < deadline:
        matches = [frame for frame in PC.events(client.out) if frame.get('event') == 'client.frame'
                   and (frame['tick'], frame['revision'], frame.get('blocks'), frame.get('neighbor_reads'))
                   == (tick, revision, blocks, 6 * blocks)]
        if matches:
            return matches[-1]
        require(client.process.poll() is None, 'resource client exited before expected frame description')
        time.sleep(.02)
    raise AssertionError('resource frame description missing: ' + str((tick, revision, blocks)))


def integration(binary, bridge, seal):
    model, palette, registry = PC.official_scene()
    java = PC.reference_records({'reference': seal['reference']})
    path = WORK / 'roundtrip.nbt'
    path.unlink(missing_ok=True)
    saves, refusals, frame_observations = [], [], []
    first = ResourceClient(binary, bridge, 'first', path, frames=500, create=True)
    try:
        actor, actor_ping = first.mcp()
        observer, observer_ping = first.mcp(False)
        raw = first.tcp()
        highwater = max(actor_ping['peer'], observer_ping['peer'], raw.call('ping')['peer'])
        names = [tool['name'] for tool in actor.request('tools/list')['result']['tools']]
        discover = raw.call('discover')
        require(len(names) == len(set(names)) == 18 and set(names) == PC.EXPECTED_OPERATIONS
                == {operation['name'] for operation in discover['operations']}, 'actual18 catalog differs')
        write(WORK / 'actual-catalog.full.json', {'mcp': names, 'tcp': discover})
        Session.inspect(observer, Session.initial_record())
        require(actor.call('world.clock') == Session.P.clock(model), 'initial Core differs')
        raw.call('world.clock', fault='PermissionDenied')
        raw.call('session.open', {'mode': 'developer', 'token': 'wrong'}, fault='AuthenticationFailed')
        raw.call('session.open', {'mode': 'developer', 'token': Session.MCP.TOKEN})
        observer.call('world.save', fault='PermissionDenied')
        observer.call('session.open', {'mode': 'player'}, fault='PlayerUnavailable')
        raw.call('simulation.step', {'ticks': 0}, fault='InvalidArguments')
        paused = []
        for _ in range(4):
            paused.append(actor.call('world.clock'))
            Session.inspect(observer, Session.initial_record())
            time.sleep(.075)
        require(all(value == Session.P.clock(model) for value in paused), 'resource snapshots/queries advanced paused Core')
        frame_observations.append(wait_frame(first, 1, 47, 39))
        require(raw.call('simulation.step', {'ticks': 2})['tick'] == 3, 'two neutral idle ticks differ')
        for _ in range(2):
            Session.apply_tick(model)
        Session.inspect(actor, java[1])
        frame_observations.append(wait_frame(first, 3, 47, 39))
        for target, name in ((4, 'minecraft:air'), (5, 'minecraft:stone')):
            for z in (-3, -2, -1):
                pos = {'dimension': 'minecraft:overworld', 'x': 0, 'y': 0, 'z': z}
                stamp = Session.P.stamp(raw.call('world.block.set', pos | {'state': palette[name]}, at=target))
                model['pending'].append({'stamp': stamp, 'mutation': {'kind': 1, 'dimension': 'minecraft:overworld',
                    'x': 0, 'y': 0, 'z': z & 0xffffffff, 'state': palette[name]}})
        model['pending'].sort(key=lambda value: value['stamp'])
        saved = Session.save(actor, path, model, highwater, java[1], saves, 'queued-resource-save')
        contender = ResourceClient(binary, bridge, 'lease-refusal', path, frames=0, ready=False)
        try:
            contender.finish(status=1, frame_count=0)
            require(not any(e.get('event') == 'server.ready' for e in PC.events(contender.out)), 'lease contender became ready')
            require(path.read_bytes() == saved, 'lease contender changed saved bundle')
            refusals.append(contender.report)
        finally:
            contender.cleanup()
        first.finish(frame_count=500)
        require(path.read_bytes() == saved, 'resource close/frame changed saved bundle')
    finally:
        first.cleanup()
    second = ResourceClient(binary, bridge, 'restart', path, frames=200)
    try:
        actor, ping = second.mcp()
        require(ping['peer'] == highwater + 1, 'saved peer highwater not restored')
        highwater = ping['peer']
        Session.inspect(actor, java[1])
        require(actor.call('world.clock') == Session.P.clock(model), 'paused reload changed Core/queue')
        for index, (tick, revision, blocks) in enumerate(((4, 50, 36), (5, 53, 39)), start=2):
            require(actor.call('simulation.step', {'ticks': 1})['tick'] == tick, 'consecutive queued deadline differs')
            Session.apply_tick(model)
            Session.inspect(actor, java[index])
            require(actor.call('world.clock') == Session.P.clock(model), 'applied Core header differs')
            frame_observations.append(wait_frame(second, tick, revision, blocks))
        saved = Session.save(actor, path, model, highwater, java[3], saves, 'resumed-resource-save')
        second.finish(frame_count=200)
        require(path.read_bytes() == saved, 'resource reload/close changed durable bytes')
    finally:
        second.cleanup()
    return {'registry': registry, 'final_model': model, 'final_bytes': saved, 'path': path,
            'saves': saves, 'refusals': refusals, 'frame_observations': frame_observations,
            'metrics': {'catalog_operations': 18, 'controlled_actual_java_idle_ticks': 4,
                        'queued_collider_edits': 6, 'paused_queries': 4}}


def failures(binary, bridge, roundtrip, seal):
    path = WORK / 'recovery.nbt'
    baseline = roundtrip['final_bytes']
    path.write_bytes(baseline)
    assets = seal['asset_fixtures']
    cases = [('unknown-option', ['--verification-fixture', '--unknown'], 'unknown/incomplete'),
        ('missing-sine', ['--verification-fixture', '--frames', '0', '--sine', str(WORK / 'absent-sine')], 'verified sine table'),
        ('missing-jar', ['--verification-fixture', '--frames', '0', '--jar', str(WORK / 'absent-jar')], 'resource scene:'),
        ('invalid-zip', ['--verification-fixture', '--frames', '0', '--jar', assets['invalid_zip']['path']], 'resource scene:'),
        ('broken-png', ['--verification-fixture', '--frames', '0', '--jar', assets['broken_png']['path']], 'resource scene:')]
    records = []
    for label, argv, diagnostic in cases:
        client = ResourceClient(binary, bridge, label, path, argv=argv, ready=False)
        try:
            client.finish(status=1, frame_count=0)
            require(diagnostic in client.report['diagnostic'], 'resource startup diagnostic differs: ' + label)
            require(not any(e.get('event') == 'server.ready' for e in PC.events(client.out)) and path.read_bytes() == baseline,
                    'failed resource startup changed durable owner or became ready')
            records.append(client.report)
        finally:
            client.cleanup()
    path.write_bytes(b'broken custom bundle fixture')
    rejected = ResourceClient(binary, bridge, 'corrupt-bundle', path, frames=0, ready=False)
    try:
        rejected.finish(status=1, frame_count=0)
        require(path.read_bytes() == b'broken custom bundle fixture', 'invalid bundle was overwritten')
        records.append(rejected.report)
    finally:
        rejected.cleanup()
    path.write_bytes(baseline)
    bad_frame = ResourceClient(binary, bridge, 'visibility-failure', path, frames=500)
    try:
        actor, _ = bad_frame.mcp()
        wait_frame(bad_frame, roundtrip['final_model']['tick'], roundtrip['final_model']['revision'], 39)
        palette = PC.official_scene()[1]
        actor.call('world.block.set', {'dimension': 'minecraft:overworld', 'x': 0, 'y': 2, 'z': 0,
                                      'state': palette['minecraft:water']})
        actor.call('simulation.step', {'ticks': 1})
        bad_frame.finish(status=1)
        require('frame query:' in bad_frame.report['diagnostic'] and path.read_bytes() == baseline,
                'actual visibility failure did not close/release and preserve durable bundle')
        records.append(bad_frame.report)
    finally:
        bad_frame.cleanup()
    recovery = ResourceClient(binary, bridge, 'frames-zero-recovery', path, frames=0, ready=False)
    try:
        recovery.finish(frame_count=0)
        require(sum(e.get('event') == 'server.ready' for e in PC.events(recovery.out)) == 1
                and path.read_bytes() == baseline, 'frames0 did not recover unchanged leased owner')
        return {'records': records, 'recovery': recovery.report, 'bundle_unchanged': True}
    finally:
        recovery.cleanup()


def native(args):
    require(args.lead_slot_granted, '--native requires the explicit later lead slot grant')
    prepared, seal = audit_preflight()
    if args.build_report is None:
        attempt = PC.bounded(build_argv(), timeout=600)
        write(WORK / 'build-attempt.full.json', attempt)
        require(not attempt['timed_out'] and attempt['exit_code'] == 0,
                'single bounded guarded build failed: ' + attempt['stderr'][-1500:])
        report = json.loads(BUILD.read_text())
    else:
        report = json.loads(args.build_report.read_text())
        write(BUILD, report)
    binary = PC.audit_build(report, seal['snapshot']['client_snapshot'])
    require(report.get('retries', 0) == 0, 'native generation changed during the supposedly stable build')
    helpers = retained_helpers()
    shutil.copy2(helpers['observer']['artifact'], WORK / 'observer')
    require(sha(WORK / 'observer') == helpers['observer']['binary_sha256'], 'copied observer changed')
    bridge = Path(helpers['mcp']['artifact'])
    started = time.monotonic()
    outcome = integration(binary, bridge, seal)
    look = PC.saved_look(binary, bridge, outcome)
    timer = PC.cadence(binary, bridge, outcome)
    rejected = failures(binary, bridge, outcome, seal)
    PC.audit_build(report, seal['snapshot']['client_snapshot'])
    require(helpers == retained_helpers() and snapshot() == seal['snapshot'], 'generation changed during native verification')
    all_rows = [client.report for client in OBSERVED]
    metrics = outcome['metrics'] | {'native_hidden_launches': len(all_rows),
        'successful_hidden_launches': sum(row['child_status'] == 0 for row in all_rows),
        'refusals': sum(row['child_status'] != 0 for row in all_rows),
        'frame_descriptions': sum(row['frame_descriptions'] for row in all_rows),
        'exact_saved_bundles': len(outcome['saves']) + len(look['saves']),
        'mcp_jsonrpc_requests': sum(client.mcp_request_count for client in OBSERVED),
        'raw_tcp_requests': sum(client.raw_request_count for client in OBSERVED)}
    full = {'status': 'passed', 'date': PC.timestamp(), 'tool_sha256': sha(__file__),
        'preflight_sha256': sha(PREFLIGHT), 'seal_sha256': sha(SEAL), 'build': PC.CacheTest.build_summary(report),
        'helpers': helpers, 'metrics': metrics, 'ordinary_checks': seal['ordinary'],
        'saves': outcome['saves'] + look['saves'], 'saved_look': look, 'cadence': timer,
        'frame_observations': outcome['frame_observations'], 'failure_lanes': rejected,
        'desktop_observations': all_rows, 'integration_seconds': time.monotonic() - started, 'boundary': BOUNDARY}
    full_path = WORK / 'native.full.json'
    write(full_path, full)
    summary = {key: full[key] for key in ('status', 'date', 'tool_sha256', 'preflight_sha256', 'seal_sha256',
        'build', 'helpers', 'metrics', 'ordinary_checks', 'saves', 'saved_look', 'cadence', 'frame_observations',
        'integration_seconds', 'boundary')}
    keys = ('scenario', 'launch_mode', 'child_pid', 'child_status', 'elapsed_seconds', 'frame_descriptions',
            'before_frontmost_pid', 'samples', 'no_listener_after_exit')
    summary.update(command='python3 tools/test_resource_player_client.py --native --lead-slot-granted',
        desktop_observations=[{key: row[key] for key in keys} for row in all_rows],
        failure_diagnostics=[{key: row[key] for key in ('scenario', 'child_status', 'diagnostic')}
                             for row in outcome['refusals'] + rejected['records']],
        full_report=str(full_path), full_report_sha256=sha(full_path),
        full_build_report=str(BUILD), full_build_report_sha256=sha(BUILD),
        audit={'dependency_aliases_bytes_content_c_transform_artifact_checked_before_after': True,
               'source_helpers_reference_resources_unchanged': True, 'all_native_launch_modes': ['hidden']})
    write(NATIVE, summary)
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--prepare', action='store_true')
    mode.add_argument('--audit', action='store_true')
    mode.add_argument('--native', action='store_true')
    parser.add_argument('--lead-slot-granted', action='store_true')
    parser.add_argument('--build-report', type=Path)
    args = parser.parse_args()
    try:
        with borrowed():
            report = native(args) if args.native else audit_preflight()[0] if args.audit else preflight()
        print(json.dumps({'status': report['status'], 'evidence': str(NATIVE if args.native else PREFLIGHT),
                          'native_execution_started': args.native}))
        return 0
    except (AssertionError, ValueError, OSError, KeyError, subprocess.SubprocessError) as error:
        print('resource player client verification refused: ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
