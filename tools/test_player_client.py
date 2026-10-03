#!/usr/bin/env python3
"""Verify the unchanged finite player client; default is preparation only.

--prepare observes actual pinned Java and performs ordinary Bend checks. It never
emits C, builds a Window artifact, compiles the observer, or launches a client.
--native is a separate, explicitly granted lane. Python specifies protocol/NBT
expectations; all player ticks, rendering, live mutation and saves run in Bend.
"""
from __future__ import annotations

import argparse
import ast
from collections import Counter
import copy
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import re
import select
import signal
import socket
import subprocess
import sys
import time

import platform_cache as Cache
import test_player_session as Session
import test_persistent_client_cache as CacheTest

ROOT = Session.ROOT
WORK = ROOT / 'build/player-client'
ENTRY = ROOT / 'player_client.bend'
BEND = Path('/Users/chuah/.bend/bin/bend')
TABLE = Session.TABLE
JAR = Path.home() / 'Library/Application Support/minecraft/versions/26.3/26.3.jar'
PREFLIGHT = ROOT / 'evidence/player-client-preflight.json'
NATIVE = ROOT / 'evidence/player-client-native.json'
REFERENCE = WORK / 'reference.full.json'
RECEIPT = WORK / 'build.full.json'
EXPECTED_OPERATIONS = {'discover', 'ping', 'session.open', 'world.clock', 'simulation.pause',
                       'simulation.step', 'world.section.create', 'world.block.get', 'world.block.set',
                       'world.time.set', 'world.daylight.set', 'action.cancel', 'world.events',
                       'registry.block', 'registry.state.decode', 'registry.state.resolve',
                       'world.save', 'player.inspect'}
HELPERS = ('tools/test_player_session.py', 'tools/test_player_record.py',
           'tools/test_player_codec.py', 'tools/test_nbt.py', 'tools/test_world_codec.py',
           'tools/test_persistence.py', 'tools/test_mcp.py', 'tools/test_support_world.py',
           'tools/test_travel_world.py', 'tools/reference_inventory.py',
           'tools/reference_block_probe.py', 'tools/reference_movement_probe.py',
           'tools/reference_travel_probe.py', 'tools/reference_player_tick_probe.py',
           'tools/reference_support_probe.py', 'tools/platform_cache.py',
           'tools/build_native.py', 'tools/platform_build.py',
           'tools/test_persistent_client_cache.py')
BOUNDARY = [
    'The normal finite entry executes plain Player.aiStep with the declared neutral .1d/.08d/.42d test profile; it is not LocalPlayer.',
    'Hidden runs install no held OS keys and establish no focused capture, visible presentation, inventory/UI, audio or full-game parity.',
    'client.frame is printed before draw. Successful bounded exit verifies the source-defined CPU frame loop, not independent pixels or drawable presentation.',
    'The entry renders 128x128 logical images into a 512x512 native Window; it has no pixel dump/readback option.',
    'AppKit polling and notifications observe this run; they are not a proof about every transient desktop change.',
    'Foreign IO and runtime lifetime loops remain declared proof boundaries. No whole-client kernel theorem is claimed.',
    'Timer cadence is an observation of this instrument, not a gameplay-performance or Minecraft-speed benchmark.',
]

# Read-only desktop observer. Child output goes directly to files, avoiding a
# full stdout pipe deadlocking a long sequence of frame descriptions. It neither
# activates an application nor orders, captures, clicks or moves a Window.
OBSERVER = r'''
import AppKit
import Foundation
let workspace = NSWorkspace.shared
func frontmost() -> Int32 { workspace.frontmostApplication?.processIdentifier ?? -1 }
let before = frontmost()
var pids = Set<Int32>([before]), activations = [Int32](), spaces = 0, samples = 0
let center = workspace.notificationCenter
let activated = center.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
 object: nil, queue: .main) { note in
 if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
   activations.append(app.processIdentifier)
 }
}
let changed = center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification,
 object: nil, queue: .main) { _ in spaces += 1 }
let process = Process()
process.executableURL = URL(fileURLWithPath: CommandLine.arguments[1])
process.arguments = Array(CommandLine.arguments.dropFirst(4))
FileManager.default.createFile(atPath: CommandLine.arguments[2], contents: nil)
FileManager.default.createFile(atPath: CommandLine.arguments[3], contents: nil)
let output = try FileHandle(forWritingTo: URL(fileURLWithPath: CommandLine.arguments[2]))
let errors = try FileHandle(forWritingTo: URL(fileURLWithPath: CommandLine.arguments[3]))
process.standardOutput = output; process.standardError = errors
try process.run()
print("{\"event\":\"observer.child\",\"pid\":\(process.processIdentifier)}")
fflush(stdout)
let start = Date()
while process.isRunning && Date().timeIntervalSince(start) < 60 {
 pids.insert(frontmost()); samples += 1
 RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
}
let timedOut = process.isRunning
if timedOut { process.terminate() }
let stopping = Date()
while process.isRunning && Date().timeIntervalSince(stopping) < 3 {
 RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
}
if process.isRunning { kill(process.processIdentifier, SIGKILL) }
process.waitUntilExit()
try output.close(); try errors.close()
for _ in 0..<10 {
 pids.insert(frontmost()); samples += 1
 RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
}
let report: [String: Any] = [
 "before_frontmost_pid":before, "after_frontmost_pid":frontmost(),
 "sampled_frontmost_pids":pids.sorted(), "samples":samples,
 "activation_notification_pids":activations, "space_change_notifications":spaces,
 "child_pid":process.processIdentifier, "child_status":process.terminationStatus,
 "timed_out":timedOut, "elapsed_seconds":Date().timeIntervalSince(start)]
center.removeObserver(activated); center.removeObserver(changed)
let data = try JSONSerialization.data(withJSONObject:report, options:[.sortedKeys])
print(String(data:data, encoding:.utf8)!)
'''


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def sha(path):
    return Cache.native.file_digest(Path(path))


def write(path, value):
    Session.write_json(path, value)


def timestamp():
    return datetime.now(timezone.utc).isoformat()


def bounded(command, timeout=90):
    started = time.monotonic()
    process = subprocess.Popen(list(map(str, command)), cwd=ROOT, text=True,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               start_new_session=True)
    print(json.dumps({'process_group': process.pid, 'command': list(map(str, command)),
                      'timeout_seconds': timeout}), flush=True)
    timed_out = False
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        os.killpg(process.pid, signal.SIGTERM)
        try:
            stdout, stderr = process.communicate(timeout=3)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            stdout, stderr = process.communicate()
    return {'command': list(map(str, command)), 'pid': process.pid,
            'exit_code': process.returncode, 'timed_out': timed_out,
            'seconds': round(time.monotonic() - started, 6),
            'stdout': stdout, 'stderr': stderr}


def source_snapshot():
    base = (BEND.resolve().parent.parent / 'bend2/base.bend').resolve()
    snapshot = Cache.native.Snapshot()
    Cache.native.source_graph(ENTRY, base, os.environ, snapshot)
    sources = snapshot.manifest()
    todo, found = [ROOT / name for name in HELPERS], set()
    while todo:
        path = todo.pop().resolve()
        if path in found:
            continue
        found.add(path)
        for node in ast.walk(ast.parse(path.read_text(), filename=str(path))):
            names = [a.name for a in node.names] if isinstance(node, ast.Import) else (
                [node.module] if isinstance(node, ast.ImportFrom) and node.module else [])
            for name in names:
                local = ROOT / 'tools' / (name.split('.')[0] + '.py')
                if local.is_file():
                    todo.append(local)
    helpers = {str(path.relative_to(ROOT)): sha(path) for path in sorted(found)}
    return {'runner_sha256': sha(__file__),
            'bend_native_effect_manifest_sha256': Cache.native.digest(Cache.native.encoded(sources)),
            'bend_native_effect_dependency_count': len(sources),
            'bend_native_effect_kind_counts': dict(sorted(Counter(i['kind'] for i in sources).items())),
            'source_sha256': {str(Path(i['path']).relative_to(ROOT)) if Path(i['path']).is_relative_to(ROOT)
                              else i['path']: i['sha256'] for i in sources},
            'helper_sha256': helpers,
            'compiler': {'path': str(BEND), 'sha256': sha(BEND)},
            'resource_sha256': {'jar': sha(JAR), 'sine': sha(TABLE), 'registry': sha(Session.P.OFFICIAL)}}


def official_scene():
    identity, count, info = Session.P.registry_identity(Session.P.OFFICIAL)
    palette = {row.split('\t')[1]: int(row.split('\t')[4])
               for row in Session.P.OFFICIAL.read_text().splitlines()[1:] if row}
    model = Session.scene_world(count, identity)
    # Session's scene constructor uses the independently specified four-state
    # test registry. Substitute actual parsed default IDs for this normal entry.
    ids = [palette[n] for n in ('minecraft:air', 'minecraft:stone', 'minecraft:dirt', 'minecraft:oak_planks')]
    for section in model['sections']:
        section['cells'] = tuple(ids[cell] for cell in section['cells'])
    Session.P.canonical_expected(model)
    return model, palette, info


def observe_reference():
    case = Session.java_input('normal-entry-idle-four', ticks=4, held=False)
    positions = [[0, 0, z] for z in (-3, -2, -1)]
    for index, name in ((2, 'minecraft:air'), (3, 'minecraft:stone')):
        case['input']['ticks'][index]['writes'] = [{'position': p, 'identifier': name} for p in positions]
    saved_work = Session.WORK
    Session.WORK = WORK / 'reference/initial'
    try:
        observed, provenance = Session.observe_java([case])
        record = Session.java_record(observed[0]['ticks'][1])
        words, _ = Session.PC.parse_snapshot(Session.PR.decode(record)[0])
        restart = Session.java_input('normal-entry-idle-restart-two', words=words,
                                    cache=observed[0]['ticks'][1]['observation']['support_cache'],
                                    ticks=2, held=False)
        restart['input']['ticks'] = copy.deepcopy(case['input']['ticks'][2:])
        Session.WORK = WORK / 'reference/restart'
        restarted, restart_provenance = Session.observe_java([restart])
    finally:
        Session.WORK = saved_work
    records = [Session.java_record(t) for t in observed[0]['ticks']]
    require([Session.java_record(t) for t in restarted[0]['ticks']] == records[2:],
            'fresh Java restore and uninterrupted idle traces differ')
    full = {'inputs': [case, restart], 'observations': [observed[0], restarted[0]],
            'provenance': [provenance, restart_provenance],
            'record_sha256': [Session.sha(v) for v in records]}
    write(REFERENCE, full)
    return {'actual_java_unique_steps': 6, 'actual_java_fresh_repeated_steps': 12,
            'two_independent_runs_equal': True, 'saved_restart_matches_uninterrupted': True,
            'record_sha256': full['record_sha256'],
            'input_sha256': [p['input_sha256'] for p in full['provenance']],
            'output_sha256': [p['output_sha256'] for p in full['provenance']],
            'actual_classpath': provenance['classpath'], 'runtime': provenance['runtime'],
            'observer_source_sha256': provenance['sources_sha256'],
            'ignored_full_reference': str(REFERENCE), 'full_reference_sha256': sha(REFERENCE)}


def ordinary():
    reports = []
    for entry in (ENTRY, ROOT / 'src/player_scene.bend'):
        report = bounded([BEND, entry, '--check-only'])
        output = report['stdout'] + report['stderr']
        matched = re.fullmatch(r'SOME PROOFS FAIL\nError: ([0-9]+) defs rely on unsafe or foreign code:\n((?:- [^\n]+\n)+)', output)
        require(not report['timed_out'] and report['exit_code'] == 1 and
                matched is not None,
                'ordinary source check did not reach only declared effect boundaries: ' + str(entry))
        require(int(matched[1]) == len(matched[2].splitlines()), 'ordinary boundary count does not match named defs')
        log = WORK / (entry.stem + '-ordinary.full.json')
        write(log, report)
        reports.append({'entry': str(entry.relative_to(ROOT)), 'exit_code': report['exit_code'],
                        'seconds': report['seconds'], 'declared_boundary_count': int(matched[1]),
                        'output_sha256': Session.sha(output.encode()), 'ignored_report': str(log)})
    return reports


def preflight():
    WORK.mkdir(parents=True, exist_ok=True)
    before = source_snapshot()
    reference = observe_reference()
    checks = ordinary()
    require(before == source_snapshot(), 'source/helper/resource generation changed during preparation')
    model, _, registry = official_scene()
    observer = WORK / 'observer.swift'
    observer.write_text(OBSERVER)
    initial = Session.initial_record()
    report = {'date': timestamp(), 'status': 'prepared-native-unverified',
              'command': 'python3 tools/test_player_client.py --prepare',
              'scope': 'unchanged player_client.bend finite plain Player integration instrument',
              'tool_sha256': sha(__file__), 'snapshot': before, 'ordinary_checks': checks,
              'reference': reference, 'registry': registry,
              'independent_initial': {'clock': Session.P.clock(model), 'sections': len(model['sections']),
                                      'scene_blocks': 39, 'scene_mutations': 47,
                                      'core_sha256': Session.sha(Session.P.canonical_expected(model)),
                                      'player_record_sha256': Session.sha(initial), 'player_record_bytes': len(initial)},
              'observer_source_sha256': sha(observer),
              'planned_native_lanes': ['actual platform-cache immutable artifact/dependency audit',
                  'hidden bounded 128x128 CPU frame loop with read-only AppKit focus/Spaces observer',
                  'actual external TCP and stdio MCP discovery/auth/refusals',
                  'paused clock/Record retention during frames and queries',
                  'two idle ticks then six queued collider edits at distinct tick deadlines',
                  'exact independent Core+PlayerRecord durable save/restart/peer highwater',
                  'unpaused timer cadence and loaded pause preservation',
                  'frames0, invalid argv/startup/window modes and lease recovery'],
              'native_build': 'not started; explicit lead build slot required', 'boundary': BOUNDARY}
    write(PREFLIGHT, report)
    return report


def audit_build(report, expected):
    require(report['route'] == 'guarded-macos-cpu-window', 'ordinary executable cannot replace guarded Window entry')
    require(Path(report['identity']['entry']).resolve() == ENTRY, 'build receipt is for another entry')
    artifact = Path(report['artifact'])
    cache = artifact.parents[2]
    record = Cache.native._verified(cache / 'entries' / report['cache_key'], report['cache_key'])
    require(record is not None, 'cache generation failed immutable artifact verification')
    require(record['key_data']['dependencies'] == report['dependencies'], 'receipt dependency closure differs')
    require(record['binary_sha256'] == report['binary_sha256'] == sha(artifact) == sha(report['path']),
            'executable digest differs from keyed build')
    require(record['binary_bytes'] == report['binary_bytes'] == artifact.stat().st_size, 'executable size mismatch')
    directory = cache / 'sources' / record['key_data']['prekey']
    require(sha(directory / 'original.c') == report['original_c_sha256'] == record['key_data']['original_c_sha256'],
            'original C is not the keyed source')
    raw = (directory / 'original.c').read_text()
    transformed = Cache._route(raw)
    require(sha(directory / 'transformed.c') == Session.sha(transformed.encode()) == report['transformed_c_sha256']
            == record['key_data']['transformed_c_sha256'], 'guarded C transform/content mismatch')
    for item in report['dependencies']:
        lookup = Path(item['lookup'])
        require(str(lookup.resolve(strict=True)) == item['path'], 'dependency alias retargeted: ' + str(lookup))
        require(lookup.stat().st_size == item['bytes'] and sha(lookup) == item['sha256'],
                'dependency content changed: ' + str(lookup))
    require(source_snapshot() == expected, 'native sources/helper/reference resources changed')
    sources = CacheTest.source_dependencies(report)
    for name, digest in expected['source_sha256'].items():
        path = str((ROOT / name).resolve()) if not Path(name).is_absolute() else name
        require(sources.get(path) == digest, 'build omitted or changed source/effect: ' + path)
    return artifact


def refresh_preflight(reason):
    """Re-pin only this runner after an orchestration correction, without builds."""
    prepared = json.loads(PREFLIGHT.read_text())
    snapshot = source_snapshot()
    prior = copy.deepcopy(prepared['snapshot'])
    prior['runner_sha256'] = snapshot['runner_sha256']
    require(prior == snapshot, 'refresh refuses changed production/helper/compiler/resource inputs')
    reference_records(prepared)
    require((WORK / 'observer.swift').read_text() == OBSERVER, 'refresh refuses changed desktop observer')
    for checked in prepared['ordinary_checks']:
        full = json.loads(Path(checked['ignored_report']).read_text())
        require(Session.sha((full['stdout'] + full['stderr']).encode()) == checked['output_sha256'],
                'refresh refuses changed ordinary-check receipts')
    revision = {'date': timestamp(), 'reason': reason, 'old_runner_sha256': prepared['tool_sha256'],
                'new_runner_sha256': snapshot['runner_sha256'], 'prior_preflight_sha256': sha(PREFLIGHT),
                'unchanged_sources_helpers_resources_reference_and_check_receipts_revalidated': True,
                'new_compiler_or_java_processes': 0}
    prepared.setdefault('runner_revisions', []).append(revision)
    prepared.update(date=timestamp(), tool_sha256=snapshot['runner_sha256'], snapshot=snapshot)
    write(PREFLIGHT, prepared)
    return prepared


def cached_build(expected, args):
    if args.build_report:
        report = json.loads(args.build_report.read_text())
    else:
        result = bounded([sys.executable, ROOT / 'tools/platform_cache.py', 'build', ENTRY,
                          '-o', WORK / 'client', '--report', RECEIPT], timeout=600)
        write(WORK / 'build-attempt.full.json', result)
        require(not result['timed_out'] and result['exit_code'] == 0,
                'guarded client build failed: ' + result['stderr'][-1500:])
        report = json.loads(RECEIPT.read_text())
    binary = audit_build(report, expected)
    # Use already independently verified MCP generation; never start a second
    # unexpected compiler job to satisfy this test's protocol helper.
    session_receipt = Session.verify_receipt(Session.source_hashes())
    bridge = Path(session_receipt['builds'][1]['artifact'])
    require(sha(bridge) == session_receipt['builds'][1]['binary_sha256'], 'MCP immutable artifact changed')
    observer_source = WORK / 'observer.swift'
    require(observer_source.read_text() == OBSERVER, 'desktop observer source changed')
    observer_command = ['/usr/bin/swiftc', '-O', str(observer_source), '-o', str(WORK / 'observer')]
    if args.build_report and (WORK / 'observer').is_file() and (WORK / 'observer-build.full.json').is_file():
        result = json.loads((WORK / 'observer-build.full.json').read_text())
        require(result['command'] == observer_command, 'existing observer was built with another command')
        result = {**result, 'reused': True}
    else:
        result = bounded(observer_command, timeout=90)
        write(WORK / 'observer-build.full.json', result)
    require(not result['timed_out'] and result['exit_code'] == 0, 'read-only observer compilation failed')
    observer_pin = {'source_sha256': sha(observer_source), 'binary_sha256': sha(WORK / 'observer')}
    pin_path = WORK / 'observer-pin.full.json'
    if result.get('reused') and pin_path.is_file():
        require(json.loads(pin_path.read_text()) == observer_pin, 'retained observer source/executable changed')
    write(pin_path, observer_pin)
    return binary, bridge, report, session_receipt['builds'][1], result


def events(path):
    if not path.exists():
        return []
    values = []
    for line in path.read_text().splitlines():
        if line.startswith('{'):
            try:
                values.append(json.loads(line))
            except json.JSONDecodeError:
                pass  # the final physical line may still be in flight
    return values


class Client:
    observed = []

    def __init__(self, binary, bridge, label, path, *, frames=500, create=False,
                 unpaused=False, argv=None, mode='hidden', registry=None, ready=True):
        require(mode in ('hidden', 'invalid', ''), 'automated human/default Window launch is forbidden')
        self.label, self.path, self.port, self.bridge = label, path, Session.MCP.free_port(), bridge
        self.mode = mode
        self.clients, self.raw_clients = [], []
        self.raw_request_count, self.mcp_request_count = 0, 0
        self.out, self.err = WORK / (label + '.stdout'), WORK / (label + '.stderr')
        environment = Session.environment(path, self.port, registry or Session.P.OFFICIAL, 'create' if create else None)
        environment['BEND_MINECRAFT_LAUNCH_MODE'] = mode
        child_args = ['--verification-fixture', '--frames', str(frames)] if argv is None else argv
        if unpaused:
            child_args = [*child_args, '--unpaused']
        self.argv = ['--threads', '2', '--gpu', 'off', '--', *child_args]
        self.process = subprocess.Popen([str(WORK / 'observer'), str(binary), str(self.out), str(self.err), *self.argv],
                                        cwd=ROOT, env=environment, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                        text=True, start_new_session=True)
        try:
            require(bool(select.select([self.process.stdout], [], [], 10)[0]), 'observer child-start timeout')
            first = json.loads(self.process.stdout.readline())
            require(first['event'] == 'observer.child', 'desktop observer did not announce child')
            self.pid = first['pid']
            if ready:
                deadline = time.monotonic() + 20
                while time.monotonic() < deadline:
                    records = events(self.out)
                    found = [e for e in records if e.get('event') == 'server.ready']
                    if found:
                        self.ready = found[0]
                        require(self.ready['host'] == '127.0.0.1' and self.ready['port'] == self.port and
                                self.ready['target'] == '26.3', 'entry listener identity changed')
                        break
                    require(self.process.poll() is None, 'client startup refused: ' + self.err.read_text()[-1000:])
                    time.sleep(.02)
                else:
                    raise AssertionError('normal entry readiness timeout')
        except BaseException:
            self.cleanup()
            raise
        Client.observed.append(self)

    def tcp(self):
        client = Session.RawTCP(self.port)
        self.raw_clients.append(client)
        return client

    def mcp(self, developer=True):
        client = Session.MCP.MCP(self.bridge, self.port, Session.MCP.TOKEN if developer else None)
        self.clients.append(client)
        client.initialize()
        ping = client.call('ping')
        require(ping['mode'] == ('developer' if developer else 'observer'), 'actual MCP capability differs')
        return client, ping

    def finish(self, *, status=0, frame_count=None):
        for c in self.clients:
            c.finish()
            self.mcp_request_count += c.requests
        for c in self.raw_clients:
            self.raw_request_count += c.count
            c.close()
        self.clients, self.raw_clients = [], []
        stdout, stderr = self.process.communicate(timeout=65)
        require(self.process.returncode == 0 and not stderr, 'desktop observer failed: ' + stderr[-500:])
        report = json.loads(stdout.strip())
        require(not report['timed_out'] and report['child_status'] == status, 'native child exit differs: ' + str(report))
        before = report['before_frontmost_pid']
        require(before > 0 and before == report['after_frontmost_pid'] and
                report['sampled_frontmost_pids'] == [before], 'frontmost app changed')
        require(report['space_change_notifications'] == 0 and self.pid not in report['activation_notification_pids'],
                'native child activation or Spaces change observed')
        data, errors = self.out.read_bytes(), self.err.read_bytes()
        require(Session.MCP.TOKEN.encode() not in data + errors, 'child disclosed developer token')
        records = events(self.out)
        frames = [e for e in records if e.get('event') == 'client.frame']
        require(all(e['renderer'] == 'cube-instrument' for e in frames), 'renderer identity differs')
        if frame_count is not None:
            require(len(frames) == frame_count, 'frame-loop description count differs: ' + str((len(frames), frame_count)))
        with socket.socket() as probe:
            probe.settimeout(1)
            require(probe.connect_ex(('127.0.0.1', self.port)) != 0, 'closed client left live listener')
        report.update({'scenario': self.label, 'argv': self.argv, 'launch_mode': self.mode,
                       'frame_descriptions': len(frames), 'no_listener_after_exit': True,
                       'stdout_sha256': Session.sha(data), 'stderr_sha256': Session.sha(errors),
                       'diagnostic': errors.decode().strip()[:400]})
        self.report = report
        return frames

    def cleanup(self):
        for c in self.clients:
            self.mcp_request_count += c.requests
            c.cleanup()
        for c in self.raw_clients:
            try:
                self.raw_request_count += c.count
                c.close()
            except OSError:
                pass
        self.clients, self.raw_clients = [], []
        if self.process.poll() is None:
            if hasattr(self, 'pid'):
                try:
                    os.kill(self.pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
            try:
                stdout, stderr = self.process.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                os.killpg(self.process.pid, signal.SIGKILL)
                stdout, stderr = self.process.communicate(timeout=3)
            write(WORK / (self.label + '-cleanup.full.json'),
                  {'observer_stdout': stdout, 'observer_stderr': stderr, 'exit_code': self.process.returncode})


def reference_records(expected):
    require(sha(REFERENCE) == expected['reference']['full_reference_sha256'], 'prepared Java evidence changed')
    full = json.loads(REFERENCE.read_text())
    records = [Session.java_record(t) for t in full['observations'][0]['ticks']]
    require([Session.sha(v) for v in records] == expected['reference']['record_sha256'], 'Java record projection differs')
    return records


def integration(binary, bridge, expected):
    model, palette, registry = official_scene()
    java = reference_records(expected)
    path = WORK / 'roundtrip.nbt'
    path.unlink(missing_ok=True)
    saves, refusals, metrics = [], [], {}
    first = Client(binary, bridge, 'first', path, frames=500, create=True)
    try:
        actor, actor_ping = first.mcp()
        observer, observer_ping = first.mcp(False)
        raw = first.tcp()
        raw_ping = raw.call('ping')
        highwater = max(actor_ping['peer'], observer_ping['peer'], raw_ping['peer'])
        tools = actor.request('tools/list')['result']['tools']
        names = [v['name'] for v in tools]
        discover = raw.call('discover')
        write(WORK / 'actual-catalog.full.json', {'mcp_tools': tools, 'tcp_discovery': discover})
        require(len(names) == len(set(names)) == len(EXPECTED_OPERATIONS) and set(names) == EXPECTED_OPERATIONS
                == {o['name'] for o in discover['operations']},
                'actual TCP/MCP catalog differs')
        require({'player.inspect', 'world.save', 'simulation.step'} <= set(names) and 'fixture.transient' not in names,
                'normal entry advertised test-harness operations')
        Session.inspect(observer, Session.initial_record())
        require(actor.call('world.clock') == Session.P.clock(model), 'initial normal scene Core differs')
        raw.call('world.clock', fault='PermissionDenied')
        raw.call('session.open', {'mode': 'developer', 'token': 'wrong'}, fault='AuthenticationFailed')
        raw.call('session.open', {'mode': 'developer', 'token': Session.MCP.TOKEN})
        observer.call('simulation.step', {'ticks': 1}, fault='PermissionDenied')
        observer.call('world.save', {}, fault='PermissionDenied')
        observer.call('session.open', {'mode': 'player'}, fault='PlayerUnavailable')
        for args in ({'ticks': 0}, {'ticks': 1.0}, {'ticks': 1, 'extra': 0}):
            raw.call('simulation.step', args, fault='InvalidArguments')
        Session.inspect(raw, Session.initial_record())
        require(actor.call('world.clock') == Session.P.clock(model), 'rejected request changed whole owner')
        # Real renderer snapshots and API polling continue while the owner is paused.
        observed = []
        for _ in range(4):
            observed.append(actor.call('world.clock'))
            Session.inspect(observer, Session.initial_record())
            time.sleep(.075)
        require(all(v == Session.P.clock(model) for v in observed), 'paused query/render advanced simulation')
        require(raw.call('simulation.step', {'ticks': 2})['tick'] == 3, 'explicit idle advance differs')
        for _ in range(2):
            Session.apply_tick(model)
        Session.inspect(actor, java[1])
        require(actor.call('world.clock') == Session.P.clock(model), 'two idle Core ticks differ')
        for target, name in ((4, 'minecraft:air'), (5, 'minecraft:stone')):
            for z in (-3, -2, -1):
                pos = {'dimension': 'minecraft:overworld', 'x': 0, 'y': 0, 'z': z}
                stamp = Session.P.stamp(raw.call('world.block.set', pos | {'state': palette[name]}, at=target))
                model['pending'].append({'stamp': stamp, 'mutation': {'kind': 1, 'dimension': 'minecraft:overworld',
                    'x': 0, 'y': 0, 'z': z & 0xffffffff, 'state': palette[name]}})
        model['pending'].sort(key=lambda v: v['stamp'])
        raw_bytes = Session.save(actor, path, model, highwater, java[1], saves, 'queued-idle-save')
        contender = Client(binary, bridge, 'lease-refusal', path, frames=0, ready=False)
        try:
            contender.finish(status=1, frame_count=0)
            require(not any(e.get('event') == 'server.ready' for e in events(contender.out)), 'lease contender became ready')
            require(path.read_bytes() == raw_bytes, 'lease contender altered valid saved bundle')
            refusals.append(contender.report)
        finally:
            contender.cleanup()
        first_frames = first.finish(frame_count=500)
        require(any(f['tick'] == 1 and f['revision'] == 47 for f in first_frames), 'initial paused frame absent')
        require(any(f['tick'] == 3 and f['revision'] == 47 for f in first_frames), 'post-step paused frame absent')
        require(all(f['tick'] in (1, 2, 3) for f in first_frames), 'paused owner advanced outside explicit step')
        require(path.read_bytes() == raw_bytes, 'frame/close mutated published save')
    finally:
        first.cleanup()
    second = Client(binary, bridge, 'restart', path, frames=150)
    try:
        actor, ping = second.mcp()
        require(ping['peer'] == highwater + 1, 'saved peer highwater was not restored')
        highwater = ping['peer']
        Session.inspect(actor, java[1])
        require(actor.call('world.clock') == Session.P.clock(model), 'restart changed loaded pause/Core queue')
        require(path.read_bytes() == raw_bytes, 'restart republished saved bytes')
        require(actor.call('simulation.step', {'ticks': 2})['tick'] == 5, 'resumed idle advance differs')
        for _ in range(2):
            Session.apply_tick(model)
        Session.inspect(actor, java[3])
        require(actor.call('world.clock') == Session.P.clock(model), 'due edits did not precede each individual tick')
        for z in (-3, -2, -1):
            require(actor.call('world.block.get', {'dimension': 'minecraft:overworld', 'x': 0, 'y': 0, 'z': z})['state']
                    == palette['minecraft:stone'], 'restored collider edit differs')
        final_bytes = Session.save(actor, path, model, highwater, java[3], saves, 'resumed-idle-edit-save')
        second_frames = second.finish(frame_count=150)
        require(any(f['tick'] == 3 for f in second_frames) and any(f['tick'] == 5 for f in second_frames),
                'restart/resumed frame descriptions absent')
        require(path.read_bytes() == final_bytes, 'restart close changed saved bytes')
    finally:
        second.cleanup()
    metrics.update({'catalog_operations': len(names), 'controlled_actual_java_idle_ticks': 4,
                    'queued_collider_edits': 6, 'initial_frames': len(first_frames), 'restart_frames': len(second_frames),
                    'paused_queries': len(observed), 'exact_saved_bundles': len(saves),
                    'raw_tcp_requests': sum(r.raw_request_count for r in Client.observed),
                    'source_defined_cpu_logical_image': [128, 128], 'native_window_size': [512, 512]})
    return {'registry': registry, 'metrics': metrics, 'saves': saves, 'refusals': refusals,
            'final_model': model, 'final_bytes': final_bytes, 'path': path}


def cadence(binary, bridge, roundtrip):
    path = WORK / 'unpaused.nbt'
    path.write_bytes(roundtrip['final_bytes'])
    before = path.read_bytes()
    client = Client(binary, bridge, 'unpaused', path, frames=100, unpaused=True)
    try:
        actor, _ = client.mcp()
        samples = []
        for _ in range(7):
            samples.append({'monotonic_seconds': time.monotonic(), 'clock': actor.call('world.clock')})
            time.sleep(.1)
        require(all(not s['clock']['paused'] for s in samples), '--unpaused did not override loaded pause')
        ticks = [s['clock']['tick'] for s in samples]
        require(all(a <= b for a, b in zip(ticks, ticks[1:])) and ticks[-1] > ticks[0], 'unpaused timer did not advance')
        require(all(s['clock']['revision'] == 53 for s in samples), 'unpaused no-edit clock changed revision')
        inspected = actor.call('player.inspect')
        Session.PR.decode(bytes(inspected['nbt_bytes']))
        frames = client.finish(frame_count=100)
        require(path.read_bytes() == before, 'unsaved timer/render/close changed durable bundle')
        elapsed = samples[-1]['monotonic_seconds'] - samples[0]['monotonic_seconds']
        origin = samples[0]['monotonic_seconds']
        for sample in samples:
            sample['monotonic_seconds'] = round(sample['monotonic_seconds'] - origin, 6)
        return {'samples': samples, 'elapsed_seconds': elapsed, 'tick_delta': ticks[-1] - ticks[0],
                'observed_ticks_per_second': (ticks[-1] - ticks[0]) / elapsed, 'frame_descriptions': len(frames),
                'unsaved_bundle_unchanged': True, 'not_a_performance_claim': True}
    finally:
        client.cleanup()


def saved_look(binary, bridge, roundtrip):
    model = roundtrip['final_model']
    _, record, first_peer = Session.parse_bundle(roundtrip['final_bytes'], model['state_count'], model['registry'])
    words, _ = Session.PC.parse_snapshot(Session.PR.decode(record)[0])
    words = list(words)
    # Raw degrees and exact finite-F32 radians are independently computed by
    # PlayerRecord's rational rounding oracle; no native gameplay runs in Python.
    look = tuple(Session.PC.raw32(v) for v in (37.25, -12.5, 31.75, -7.25))
    words[39:41] = [Session.PR.projection(v) for v in look[:2]]
    player = Session.record_bytes(words, look)
    path = WORK / 'saved-look.nbt'
    path.write_bytes(Session.bundle_bytes(model, first_peer - 1, player))
    client = Client(binary, bridge, 'saved-nonzero-look', path, frames=100)
    saves = []
    try:
        actor, ping = client.mcp()
        require(ping['peer'] == first_peer, 'saved-look peer highwater differs')
        Session.inspect(actor, player)
        require(actor.call('world.clock') == Session.P.clock(model), 'saved-look load altered paused Core')
        published = Session.save(actor, path, model, ping['peer'], player, saves, 'loaded-nonzero-look-preserved')
        frames = client.finish(frame_count=100)
        require(all((f['yaw_f32'], f['pitch_f32']) == tuple(words[39:41]) for f in frames),
                'saved raw degree look did not project to loaded renderer radians')
        require(path.read_bytes() == published, 'saved-look frame/close changed bundle')
        return {'raw_degree_f32_words': list(look), 'renderer_radian_f32_words': words[39:41],
                'unchanged_saved_record_sha256': Session.sha(player), 'frames': len(frames), 'saves': saves,
                'expected_projection': 'independent exact rational F32 conversion oracle'}
    finally:
        client.cleanup()


def failures(binary, bridge, roundtrip):
    path = WORK / 'recovery.nbt'
    baseline = roundtrip['final_bytes']
    path.write_bytes(baseline)
    bad_sine, bad_jar = WORK / 'invalid-sine', WORK / 'invalid-jar'
    bad_sine.write_bytes(b'invalid exact sine table')
    bad_jar.write_bytes(b'invalid ZIP archive')
    cases = [
        ('fixture-required', [], 1, 'requires --verification-fixture', False),
        ('unknown-option', ['--verification-fixture', '--unknown'], 1, 'unknown/incomplete', False),
        ('missing-frame-count', ['--verification-fixture', '--frames'], 1, 'unknown/incomplete', False),
        ('negative-frame-count', ['--verification-fixture', '--frames', '-1'], 1, 'unsigned integer', False),
        ('overflow-frame-count', ['--verification-fixture', '--frames', '4294967296'], 1, 'unsigned integer', False),
        ('fraction-frame-count', ['--verification-fixture', '--frames', '1.5'], 1, 'unsigned integer', False),
        ('missing-sine', ['--verification-fixture', '--frames', '0', '--sine', str(WORK / 'absent-sine')], 1, 'verified sine table', False),
        ('invalid-sine', ['--verification-fixture', '--frames', '0', '--sine', str(bad_sine)], 1, 'verified sine table', False),
        ('missing-jar', ['--verification-fixture', '--frames', '0', '--jar', str(WORK / 'absent-jar')], 1, '', False),
        ('invalid-jar', ['--verification-fixture', '--frames', '0', '--jar', str(bad_jar)], 1, '', False),
        ('invalid-mode', ['--verification-fixture', '--frames', '0'], 22, 'must be human or hidden', True),
        ('empty-mode', ['--verification-fixture', '--frames', '0'], 22, 'must be human or hidden', True),
    ]
    records = []
    for label, argv, status, diagnostic, may_ready in cases:
        mode = 'invalid' if label == 'invalid-mode' else '' if label == 'empty-mode' else 'hidden'
        client = Client(binary, bridge, label, path, argv=argv, mode=mode, ready=False)
        try:
            client.finish(status=status, frame_count=0)
            ready = any(e.get('event') == 'server.ready' for e in events(client.out))
            require(ready is may_ready, 'startup progressed across its declared failure boundary: ' + label)
            require(diagnostic in client.report['diagnostic'] and client.report['diagnostic'], 'missing refusal diagnostic: ' + label)
            require(path.read_bytes() == baseline, 'failed startup changed saved bundle: ' + label)
            records.append(client.report)
        finally:
            client.cleanup()
    absent = WORK / 'absent-bundle.nbt'
    absent.unlink(missing_ok=True)
    for label, failed_path, registry in [('missing-bundle', absent, Session.P.OFFICIAL),
                                         ('missing-registry', path, WORK / 'absent-registry.tsv')]:
        client = Client(binary, bridge, label, failed_path, frames=0, ready=False, registry=registry)
        try:
            client.finish(status=1, frame_count=0)
            require(not any(e.get('event') == 'server.ready' for e in events(client.out)), 'missing startup input admitted')
            require(not absent.exists() and path.read_bytes() == baseline, 'missing startup input replaced durable data')
            records.append(client.report)
        finally:
            client.cleanup()
    for label, bad in [('corrupt-bundle', b'broken custom bundle'),
                       ('core-only-migration', Session.P.canonical_expected(roundtrip['final_model']))]:
        path.write_bytes(bad)
        client = Client(binary, bridge, label, path, frames=0, ready=False)
        try:
            client.finish(status=1, frame_count=0)
            require(not any(e.get('event') == 'server.ready' for e in events(client.out)), 'malformed save admitted')
            require(path.read_bytes() == bad, 'malformed save replaced before admission')
            records.append(client.report)
        finally:
            client.cleanup()
        path.write_bytes(baseline)
    recovery = Client(binary, bridge, 'frames-zero-recovery', path, frames=0, ready=False)
    try:
        recovery.finish(frame_count=0)
        require(sum(e.get('event') == 'server.ready' for e in events(recovery.out)) == 1, 'frames0 did not start normal owner')
        require(path.read_bytes() == baseline, 'frames0/recovered lease changed saved bundle')
        return {'rejected_cases': records, 'recovery': recovery.report, 'saved_bundle_unchanged': True,
                'frames_zero_no_snapshot_draw_or_frame_by_source_contract': True}
    finally:
        recovery.cleanup()


def native(args):
    expected = json.loads(PREFLIGHT.read_text())
    require(expected['tool_sha256'] == sha(__file__), 'prepared runner changed; rerun --prepare')
    require(expected['snapshot'] == source_snapshot(), 'prepared source/helper/resource pins changed')
    binary, bridge, build, mcp, observer_build = cached_build(expected['snapshot'], args)
    # Preparation already checked this identical source generation. Native
    # receipt continuation adopts those checks without another compiler process.
    ordinary_checks = expected['ordinary_checks']
    for checked in ordinary_checks:
        full = json.loads(Path(checked['ignored_report']).read_text())
        require(Session.sha((full['stdout'] + full['stderr']).encode()) == checked['output_sha256']
                and full['exit_code'] == checked['exit_code'] and not full['timed_out'],
                'prepared ordinary-check receipt changed')
    started = time.monotonic()
    roundtrip = integration(binary, bridge, expected)
    restored_look = saved_look(binary, bridge, roundtrip)
    timer = cadence(binary, bridge, roundtrip)
    rejected = failures(binary, bridge, roundtrip)
    audit_build(build, expected['snapshot'])
    require(sha(bridge) == mcp['binary_sha256'], 'MCP artifact changed during integration')
    observations = [r.report for r in Client.observed]
    metrics = roundtrip['metrics']
    metrics['native_entry_launches'] = len(observations)
    metrics['hidden_environment_launches'] = sum(o['launch_mode'] == 'hidden' for o in observations)
    metrics['successful_hidden_launches'] = sum(o['launch_mode'] == 'hidden' and o['child_status'] == 0 for o in observations)
    metrics['guarded_invalid_mode_refusals'] = sum(o['launch_mode'] != 'hidden' for o in observations)
    metrics['frame_descriptions'] = sum(o['frame_descriptions'] for o in observations)
    metrics['raw_tcp_requests'] = sum(getattr(r, 'raw_request_count', 0) for r in Client.observed)
    metrics['mcp_jsonrpc_requests'] = sum(r.mcp_request_count for r in Client.observed)
    metrics['exact_saved_bundles'] += len(restored_look['saves'])
    report = {'date': timestamp(), 'status': 'passed',
              'command': 'python3 tools/test_player_client.py --native', 'tool_sha256': sha(__file__),
              'preflight_sha256': sha(PREFLIGHT), 'snapshot': expected['snapshot'],
              'build': CacheTest.build_summary(build),
              'mcp': {'artifact': str(bridge), 'cache_key': mcp['cache_key'], 'binary_sha256': sha(bridge),
                      'dependency_count': len(mcp['dependencies']),
                      'dependency_manifest_sha256': Cache.native.digest(Cache.native.encoded(mcp['dependencies']))},
              'observer': {'source_sha256': sha(WORK / 'observer.swift'), 'binary_sha256': sha(WORK / 'observer'),
                           'compiler_seconds': observer_build['seconds'], 'poll_interval_seconds': .02},
              'ordinary_checks': ordinary_checks, 'metrics': metrics,
              'saves': roundtrip['saves'] + restored_look['saves'], 'saved_nonzero_look': restored_look,
              'cadence': timer, 'failure_cases': rejected,
              'desktop_observations': observations, 'integration_seconds': time.monotonic() - started,
              'audit': {'all_dependency_aliases_sizes_and_contents_checked_before_and_after': True,
                        'original_and_guarded_c_and_immutable_binary_checked': True,
                        'source_and_reference_resource_pins_unchanged': True}, 'boundary': BOUNDARY}
    write(WORK / 'native.full.json', report)
    return compact_native()


def compact_native():
    """Finalize an existing successful receipt; no compiler, Java or launch."""
    full_path = WORK / 'native.full.json'
    full = json.loads(full_path.read_text())
    require(full['status'] == 'passed' and sha(PREFLIGHT) == full['preflight_sha256'],
            'compact requires the successful execution and original preflight')
    prior = copy.deepcopy(full['snapshot'])
    prior['runner_sha256'] = sha(__file__)
    require(source_snapshot() == prior, 'receipt compaction refuses changed production/helper/resource generation')
    build = json.loads(RECEIPT.read_text())
    audit_build(build, prior)
    require(sha(full['mcp']['artifact']) == full['mcp']['binary_sha256'], 'MCP artifact changed after execution')
    observations = full['desktop_observations']
    for row in observations:
        require(not row['timed_out'] and row['before_frontmost_pid'] == row['after_frontmost_pid'] > 0
                and row['sampled_frontmost_pids'] == [row['before_frontmost_pid']]
                and row['space_change_notifications'] == 0 and row['child_pid'] not in row['activation_notification_pids']
                and row['no_listener_after_exit'], 'desktop/teardown receipt does not satisfy executed assertions')
    metrics = dict(full['metrics'])
    metrics.pop('hidden_launches', None)
    metrics.update(native_entry_launches=len(observations),
                   hidden_environment_launches=sum(o['launch_mode'] == 'hidden' for o in observations),
                   successful_hidden_launches=sum(o['launch_mode'] == 'hidden' and o['child_status'] == 0 for o in observations),
                   guarded_invalid_mode_refusals=sum(o['launch_mode'] != 'hidden' for o in observations),
                   startup_and_lease_refusals=sum(o['child_status'] != 0 for o in observations))
    kept = {k: full[k] for k in ('date', 'status', 'preflight_sha256', 'mcp', 'observer', 'ordinary_checks',
                                 'saves', 'saved_nonzero_look', 'cadence', 'integration_seconds', 'audit', 'boundary')}
    keys = ('scenario', 'launch_mode', 'child_pid', 'child_status', 'elapsed_seconds', 'frame_descriptions',
            'before_frontmost_pid', 'samples')
    kept.update(command='python3 tools/test_player_client.py --native --build-report build/player-client/build.full.json',
                execution_tool_sha256=full['tool_sha256'], summary_tool_sha256=sha(__file__), metrics=metrics,
                full_execution_report=str(full_path), full_execution_report_sha256=sha(full_path),
                full_build_report=str(RECEIPT), full_build_report_sha256=sha(RECEIPT),
                snapshot={'canonical_sha256': Cache.native.digest(Cache.native.encoded(full['snapshot'])),
                          'source_manifest_sha256': full['snapshot']['bend_native_effect_manifest_sha256'],
                          'dependency_count': full['snapshot']['bend_native_effect_dependency_count'],
                          'kind_counts': full['snapshot']['bend_native_effect_kind_counts'],
                          'transitive_python_helper_count': len(full['snapshot']['helper_sha256']),
                          'resource_sha256': full['snapshot']['resource_sha256'],
                          'project_source_sha256': {k:v for k,v in full['snapshot']['source_sha256'].items()
                                                   if k in ('player_client.bend', 'src/player_scene.bend',
                                                            'src/player_session.bend', 'src/player_runtime.bend')},
                          'complete_source_and_helper_hashes': 'pinned preflight and ignored full execution report'},
                build=CacheTest.build_summary(build, include_sources=False),
                desktop={'all_before_after_and_sampled_frontmost_pids_equal_within_each_run': True,
                         'all_listener_ports_refused_after_exit': True,
                         'space_change_notifications_total': sum(o['space_change_notifications'] for o in observations),
                         'activation_notification_pid_union': sorted({p for o in observations for p in o['activation_notification_pids']}),
                         'runs': [{k:row[k] for k in keys} for row in observations]},
                failures={'cases': [{'scenario': o['scenario'], 'exit_code': o['child_status'], 'mode': o['launch_mode'],
                                     'diagnostic': o['diagnostic']} for o in observations if o['child_status'] != 0],
                          'input_and_saved_bytes_preserved': full['failure_cases']['saved_bundle_unchanged'],
                          'frames_zero_recovery_completed_without_frame': True})
    attempts = []
    for name in ('native-catalog-count-attempt.full.json', 'native-max-peer-attempt.full.json'):
        path = WORK / name
        if path.is_file():
            attempt = json.loads(path.read_text())
            attempts.append({'path': str(path), 'sha256': sha(path), 'status': attempt['status'],
                             'diagnosis': attempt['diagnosis'], 'production_source_changes': False})
    kept['prior_runner_attempts'] = attempts
    executed_source = WORK / 'executed-test_player_client.py'
    if executed_source.is_file() and sha(executed_source) == full['tool_sha256']:
        kept['execution_runner_source'] = str(executed_source)
        kept['receipt_finalization'] = 'Later runner edits only compact reporting and distinguish hidden launches from invalid-mode refusals; executed test assertions remain in the retained source.'
    write(NATIVE, kept)
    return kept


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--prepare', action='store_true')
    mode.add_argument('--native', action='store_true', help='requires an explicit lead build/launch grant')
    mode.add_argument('--refresh-preflight', metavar='REASON', help='revalidate unchanged prepared inputs after a runner correction; no compiler/Java process')
    mode.add_argument('--compact-only', action='store_true', help='audit and compact an existing successful full execution receipt; no build or launch')
    parser.add_argument('--build-report', type=Path, help='reuse a completed full platform cache receipt')
    args = parser.parse_args()
    try:
        report = compact_native() if args.compact_only else native(args) if args.native else refresh_preflight(args.refresh_preflight) if args.refresh_preflight else preflight()
        print(json.dumps({'status': report['status'], 'evidence': str(NATIVE if args.native or args.compact_only else PREFLIGHT)}))
        return 0
    except (AssertionError, ValueError, OSError, KeyError, subprocess.SubprocessError) as error:
        print('player client verification failed: ' + str(error), file=sys.stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
