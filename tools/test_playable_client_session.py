#!/usr/bin/env python3
"""Production backend boundary checks with exact source/cache identity.

Compile one retained C emission with the selected CPU compiler, reuse verified
content-keyed artifacts, and drive actual TCP/MCP/durable-save boundaries. FRR2
owns bounded capture and cleanup. Pure laws and reference lanes remain separate.
"""
from __future__ import annotations

import argparse
import contextlib
import copy
import csv
import dataclasses
import json
import importlib
import os
from pathlib import Path
import re
import sys
import select
import signal
import socket
import subprocess
import tempfile
import time

import test_fall_reset_world_continuation_r2 as Host
import test_local_player_session as Session
import test_local_player_session_continuation_r2 as OldConsumer

S = Session

ROOT = Path(__file__).resolve().parents[1]
ROLE = 'backend'
RUN_ROOT = ROOT / 'build/playable-client-backend-session'
ATTEMPT = '001'
WORK = RUN_ROOT / ATTEMPT
FAILED_WORK = ROOT / 'build/playable-client-session'
SOURCE_ROOT = ROOT / 'build/playable-client-live-source'
ENTRY = SOURCE_ROOT / 'remote_resource_server.bend'
CLI_RECIPE = ROOT.parent / 'bend/bend2/main.ts'
DOC = ROOT / 'docs/PLAYABLE_CLIENT_ACCEPTANCE.md'
READY = WORK / 'prepared.json'
BINARY = WORK / 'backend-native'
CACHE = ROOT / 'build/playable-client-content-cache'
BUILD = WORK / 'native-build.json'
CONSUMER = WORK / 'consumer-manifest.json'
BUILD_RESULT = ROOT / ('evidence/playable-client-backend-build-' + ATTEMPT + '.json')
NATIVE_RESULT = ROOT / ('evidence/playable-client-backend-native-' + ATTEMPT + '.json')
IMPORT_PIN = Host.pin(__file__)
LAST_EXECUTION = None
RUN_CONTEXT = None
ARTIFACT_CONTEXT = None
HISTORICAL = ROOT / 'evidence/local-player-session-continuation-r2-native.json'
FROZEN = {
    'tools/test_local_player_session.py': 'ffa2d9d7105b2fd1eb0b1e3bbace195f3dceed75bdbe80e8814349df3545b2c1',
    'tests/local_player_session.bend': '2081023f80df39c92ebbe11a2b19083b73bfe234cc193866521b1a13a0f198d6',
    'tools/test_fall_reset_world_continuation_r2.py': 'c2580703b97e4f698153e6dbbd3d9d48ae1c50f3d6b3fbc5e727d0bc39cdfa14',
}
require = Host.require
pin = Host.pin
exclusive = Host.exclusive


def fixed_helpers():
    rows = {}
    for name, expected in FROZEN.items():
        observed = pin(ROOT / name)
        require(observed['sha256'] == expected, 'Retained helper changed: ' + name)
        rows[name] = observed
    return rows



def historical_contract():
    """Retain prior corpus results without treating them as this new binary."""
    value = json.loads(HISTORICAL.read_bytes())
    require(value['status'] == 'PASS' and value['codec_executions'] == 1510,
            'Historical 755-case twice-run codec acceptance changed')
    phases = [row for row in value['fixture_lanes']
              if row['process']['argv'][-2] == 'phase-cases']
    require(len(phases) == 2 and all(len(row['comparison']['actual']) == 15
            and len(row['comparison']['policies']) == 28
            and row['comparison']['status'] == 'passed' for row in phases),
            'Historical complete phase43 twice-run acceptance changed')
    require(len(value['primary']) == 2
            and all(row['summary']['status'] == 'PASS' for row in value['primary']),
            'Historical primary transport acceptance changed')
    # Small receipt/evidence identities are retained. Historical generation files
    # intentionally differ from the additive playable generation and are not
    # rehashed or silently substituted into its current source closure.
    return {'evidence': pin(HISTORICAL), 'codec_cases': 755, 'codec_runs': 2,
            'phase_actual_cases': 15, 'phase_policy_cases': 28, 'phase_runs': 2,
            'historical_binary': value['binary'],
            'historical_consumer': value['consumer_manifest'],
            'scope': 'Prior artifact results only; no claim that historical corpora were rerun in the playable artifact.'}


def retained_bridge():
    receipt = json.loads(Session.BASE.RECEIPT.read_bytes())
    built = receipt['builds'][1]
    bridge = Session.BASE.BRIDGE
    require(built.get('retries', 0) == 0
            and pin(bridge)['sha256'] == built['binary_sha256'],
            'Retained actual MCP bridge identity/retry history changed')
    return bridge, {'binary': pin(bridge), 'receipt': pin(Session.BASE.RECEIPT),
                    'historical_source_generation': receipt['sources_sha256'],
                    'scope': 'Previously accepted actual MCP transport artifact, explicitly retained by byte identity.'}


def retained_atomic():
    """Admit the retained executable only for the unchanged Atomic effect path."""
    import build_native as builder
    old = json.loads(HISTORICAL.read_bytes())
    binary = Path(old['binary']['path'])
    consumer = Path(old['consumer_manifest']['path'])
    require(pin(binary)['sha256'] == old['binary']['sha256']
            and pin(consumer)['sha256'] == old['consumer_manifest']['sha256'],
            'Retained Atomic artifact identity differs')
    manifest = json.loads(consumer.read_bytes())
    built = json.loads(Path(manifest['native_build_receipt']['path']).read_bytes())['build']
    snapshot = builder.Snapshot()
    base = (Session.BEND.resolve().parent.parent / 'bend2/base.bend').resolve()
    builder.source_graph(SOURCE_ROOT / 'src/atomic_file.bend', base, dict(os.environ), snapshot)
    prior = {row['lookup']: row for row in built['dependencies']}
    closure = snapshot.manifest()
    for row in closure:
        lookup = row['lookup']
        if Path(lookup).is_relative_to(SOURCE_ROOT):
            lookup = str(ROOT / Path(lookup).relative_to(SOURCE_ROOT))
        require(lookup in prior and row['sha256'] == prior[lookup]['sha256'],
                'Retained Atomic dependency differs: ' + lookup)
    require(manifest['source_generation']['tests/local_player_session.bend'] ==
            FROZEN['tests/local_player_session.bend'], 'Retained Atomic fixture body differs')
    return {'binary': old['binary'], 'consumer': old['consumer_manifest'],
            'dependency_closure': closure,
            'scope': 'Exact unchanged Atomic.publish_with effects and retained fixture; no claim about newer reset/gameplay implementation.'}


def atomic_child(directory):
    value, _, _ = verify_build()
    require(directory == WORK / 'native-attempt/atomic', 'Unknown Atomic directory')
    directory.mkdir(exist_ok=False)
    journal = directory / 'owned-groups.jsonl'
    journal.touch(exist_ok=False)
    retained = retained_atomic()
    target = Path(retained['binary']['path'])
    def atomic_activation():
        audit()
        require(pin(target)['sha256'] == retained['binary']['sha256'], 'Retained Atomic executable changed')
        for row in retained['dependency_closure']:
            require(pin(row['lookup'])['sha256'] == row['sha256'], 'Atomic input changed')
    bridge, _ = retained_bridge()
    identity, count, _ = Session.P.registry_identity(Session.P.OFFICIAL)
    cases, _, _ = Session.reference_cases()
    record = cases[0]['steps'][0]['before']
    saves, rejections, checks = [], [], []
    with Host.bindings(Session, {'SERVER': target, 'activation': atomic_activation,
                                'OWNED_GROUPS': journal}), source_scope():
        Session.atomic_tests(Session.P.OFFICIAL, count, identity, bridge,
                             directory, record, saves, rejections, checks)
    require(len(checks) == 5 and all(row['actual_SIGKILL'] for row in checks), 'Five Atomic stages incomplete')
    exclusive(directory / 'acceptance.json', {'status': 'passed', 'checks': checks,
              'saves': saves, 'rejections': rejections, 'retained': retained})


def host_controls(directory):
    """Exercise reused routing/failure receipts using inert Python objects only."""
    directory.mkdir(exist_ok=False)
    journal = directory / 'inert-owned-groups.jsonl'
    journal.touch(exist_ok=False)
    before = (Host.JOURNAL, Host.GROUPS, Host.admission, Host.F.ATTEMPT)
    cases = []
    class Process:
        pid = 900001
        returncode = None
        def wait(self, timeout):
            require(json.loads(journal.read_bytes().splitlines()[-1])['pid'] == self.pid,
                    'Inert process waited before durable journal')
            self.returncode = 0
            return 0
    class Ops:
        def __init__(self, denied=False):
            self.denied = denied
        def probe(self, pgid):
            if self.denied:
                raise PermissionError('inert cleanup probe denied')
            return True
        def term(self, pgid):
            pass
        def kill(self, pgid):
            pass
        def wait(self, pgid, deadline):
            pass
    def factory(argv, **kwargs):
        kwargs['stdout'].write(b'inert-stdout\n')
        kwargs['stderr'].write(b'inert-stderr\n')
        return Process()
    with Host.bindings(Host, {'JOURNAL': journal, 'GROUPS': [], 'LAST_EXECUTION': None}), \
         Host.bindings(Host.F, {'ATTEMPT': directory, 'LAST_EXECUTION': None}):
        for denied in (False, True):
            name = 'capture' if not denied else 'cleanup-denied'
            out, err, result, receipt = Host.execute_process(['inert-not-executed'],
                name, 120, _popen=factory, _snapshot=lambda pid, known: [],
                _ops=Ops(denied), _admit=lambda label: None)
            require(out == 'inert-stdout\n' and err == 'inert-stderr\n',
                    'Reused supervisor failed to retain exact raw streams')
            require(result['status'] == ('failed' if denied else 'passed'),
                    'Unknown cleanup observation admitted as success')
            if denied:
                require(result['cleanup']['unknown_groups'] == [900001]
                        and result['cleanup']['verified'] is False,
                        'Denied cleanup discarded unknown group')
            cases.append({'case': name, 'receipt': receipt, 'passed': True})
    require((Host.JOURNAL, Host.GROUPS, Host.admission, Host.F.ATTEMPT) == before,
            'Host inert bindings failed restoration')
    class Sentinel(RuntimeError):
        pass
    original = Session.SERVER, Session.activation, Session.OWNED_GROUPS
    try:
        with session_scope(journal):
            require(Session.SERVER == BINARY and Session.activation is activation,
                    'Session shared-artifact routing not installed')
            raise Sentinel('inert scoped failure')
    except Sentinel:
        pass
    require((Session.SERVER, Session.activation, Session.OWNED_GROUPS) == original,
            'Session exception routing failed restoration')
    cases.append({'case': 'Session-routing-exception-restored', 'passed': True})
    return {'status': 'passed', 'cases': cases, 'compiler_executions': 0,
            'native_executions': 0, 'Java_executions': 0, 'UI_executions': 0}


def prepare():
    if ROLE == 'block-reference':
        return prepare_reference_lane()
    Host.unused(WORK, ROOT / ('evidence/playable-client-backend-prepared-' + ATTEMPT + '.json'))
    import build_native as builder
    if ATTEMPT != '001':
        map_current_sources(builder)
    fixed = fixed_helpers()
    snapshot = builder.Snapshot()
    snapshot.add(Session.BEND, 'bend-compiler')
    base = (Session.BEND.resolve().parent.parent / 'bend2/base.bend').resolve()
    builder.source_graph(ENTRY, base, dict(os.environ), snapshot)
    closure = snapshot.manifest()
    paths = {Path(row[key]) for row in closure for key in ('lookup', 'path')}
    mapping = Host.load_seal(SOURCE_ROOT / 'source-map.json')
    Host.check_files({row['mapped']['lookup']: row['mapped'] for row in mapping['files']})
    paths.add(SOURCE_ROOT / 'source-map.json')
    paths.update(Session.tool_closure([Path(__file__), ROOT / 'tools/build_native.py']))
    paths.update([Session.TABLE, Session.P.OFFICIAL, Session.REFERENCE,
                  HISTORICAL, CLI_RECIPE,
                  ROOT / 'evidence/playable-client-backend-footprint.json',
                  ROOT / 'evidence/playable-client-live-build-failure.json'])
    bridge, bridge_info = retained_bridge()
    atomic = retained_atomic()
    paths.update([bridge, Session.BASE.RECEIPT, Path(sys.executable),
                  Path(atomic['binary']['path']), Path(atomic['consumer']['path'])])
    paths.update(Path(row['lookup']) for row in atomic['dependency_closure'])
    WORK.mkdir(parents=True, exist_ok=False)
    controls = host_controls(WORK / 'host-controls')
    exclusive(WORK / 'host-controls.json', controls)
    paths.add(WORK / 'host-controls.json')
    files = {str(path.absolute()): pin(path) for path in sorted(paths, key=str)}
    sources = {str(Path(row['path']).relative_to(SOURCE_ROOT)): row['sha256']
               for row in closure if Path(row['path']).is_relative_to(SOURCE_ROOT)}
    value = Host.sealed({'schema': 3, 'status': 'prepared-boundary-unverified',
        'files': files, 'source_pins': sources, 'Bend_imports': closure,
        'source_dependencies': Host.dependency_admission(closure),
        'environment_sha256': Session.environment_pin(),
        'fixed_helpers': fixed, 'historical': historical_contract(),
        'retained_atomic': atomic, 'retained_MCP': bridge_info,
        'entry': pin(ENTRY), 'runner': IMPORT_PIN,
        'documentation': {'pin': pin(DOC), 'role': 'Informational; not consumed by build or native checks.'},
        'mapped_source': pin(SOURCE_ROOT / 'source-map.json'),
        'contract_generation': ('retained-v2-finite' if ATTEMPT == '001' else
                                'current-v3-menu-status-demand-generation'),
        'sequence': ['actual-production-backend-TCP-MCP-save-coldreload',
                     'retained-exact-Atomic-five-SIGKILL-boundaries'],
        'excluded_active_routes': ['old-full-Session-primary', 'pure-codec-phase-travel-inventory-terrain-HUD-corpora', 'block-Java-reference-replay'],
        'build_route': 'Backend only, one guarded content-keyed C emission and selected CPU clang; verified artifact reuse; zero retries.',
        'caps_seconds': {'single_build': 600, 'native_lane': 120},
        'compiler_executions': 0, 'native_executions': 0,
        'Java_executions': 0, 'UI_executions': 0})
    exclusive(READY, value)
    audit()
    summary = {'status': value['status'], 'ready': pin(READY),
               'seal_sha256': value['seal_sha256'], 'Bend_imports': len(closure),
               'files': len(files), 'sequence': value['sequence'],
               'compiler_executions': 0, 'native_executions': 0}
    exclusive(ROOT / ('evidence/playable-client-backend-prepared-' + ATTEMPT + '.json'), summary)
    print(json.dumps(summary), flush=True)


def map_current_sources(builder):
    """Freeze the actual production graph with the existing source scanner."""
    Host.unused(SOURCE_ROOT)
    snapshot = builder.Snapshot()
    base = (Session.BEND.resolve().parent.parent / 'bend2/base.bend').resolve()
    builder.source_graph(ROOT / 'remote_resource_server.bend', base,
                         dict(os.environ), snapshot)
    for name in ('generated/reference_item_metadata.tsv',
                 'generated/reference_mth_sin.f32'):
        snapshot.add(ROOT / name, 'runtime-input')
    dependencies = snapshot.manifest()
    SOURCE_ROOT.mkdir(parents=True, exist_ok=False)
    files = []
    for row in dependencies:
        original = Path(row['path'])
        if not original.is_relative_to(ROOT):
            continue
        relative = original.relative_to(ROOT)
        mapped = SOURCE_ROOT / relative
        mapped.parent.mkdir(parents=True, exist_ok=True)
        data = original.read_bytes()
        require(builder.digest(data) == row['sha256'],
                'Production source changed during mapping: ' + str(original))
        with mapped.open('xb') as output:
            output.write(data)
        files.append({'path': str(relative), 'role': row['kind'],
                      'original_sha256': row['sha256'],
                      'original_bytes': row['bytes'], 'mapped': pin(mapped)})
    for lookup, expected in snapshot.stamps.items():
        require(builder.stamp(Path(lookup).resolve()) == expected,
                'Production dependency changed while freezing: ' + lookup)
    exclusive(SOURCE_ROOT / 'source-map.json', Host.sealed({
        'schema': 1, 'status': 'frozen-production-source',
        'scope': 'Exact current remote_resource_server production graph; saved v3 equipment/status/WG, reserved actor, complete menu wire and demand frame joins. No test dispatcher or pure fixture imports.',
        'entry': pin(SOURCE_ROOT / 'remote_resource_server.bend'),
        'files': files, 'original_dependencies': dependencies}))


def audit(full=True):
    global RUN_CONTEXT
    require(sys.flags.optimize == 0, 'Assertions disabled')
    require(pin(__file__) == IMPORT_PIN, 'Imported boundary supervisor changed')
    if RUN_CONTEXT is None:
        value = Host.load_seal(READY)
        Host.check_files(value['files'])
        require(value['environment_sha256'] == Session.environment_pin(), 'Build environment changed')
        require(value['fixed_helpers'] == fixed_helpers(), 'Retained helper drift')
        RUN_CONTEXT = value
    return RUN_CONTEXT


def activation():
    value = audit()
    manifest = Host.load_seal(CONSUMER)
    require(manifest['ready_seal'] == value['seal_sha256'], 'Artifact source seal differs')
    # These inputs are consumed at each launch. Immutable compiled source/cache
    # dependencies are admitted once at run start and at actual build changes.
    paths = (BINARY, Path(__file__)) if ROLE == 'block-reference' else (
        BINARY, Session.TABLE, Session.P.OFFICIAL, ROOT / 'tools/test_local_player_session.py')
    for path in paths:
        require(pin(path) == manifest['files'][str(path)], 'Launch input changed: ' + str(path))
    return value


def admission(label, full=False):
    value = audit()
    if Host.F.ATTEMPT == WORK / 'native-attempt':
        activation()
    path = Host.F.ATTEMPT / 'admission' / (label + '.json')
    exclusive(path, {'status': 'passed', 'ready_seal': value['seal_sha256'],
                     'scope': 'Validated run-start context; launch artifact/inputs checked when consumed.'})
    return Host.F.pin(path)


@contextlib.contextmanager
def execution_scope(directory):
    directory.mkdir(parents=True, exist_ok=True)
    journal = directory / 'supervisor-owned-groups.jsonl'
    journal.touch(exist_ok=False)
    with Host.bindings(Host, {'JOURNAL': journal, 'GROUPS': [],
                              'admission': admission, 'LAST_EXECUTION': None}), \
         Host.bindings(Host.F, {'ATTEMPT': directory, 'LAST_EXECUTION': None}):
        with Host.parent_cleanup(directory):
            yield


@contextlib.contextmanager
def source_scope():
    with Host.bindings(Session, {'ROOT': SOURCE_ROOT}):
        yield


@contextlib.contextmanager
def session_scope(journal):
    with Host.bindings(Session, {'SERVER': BINARY, 'OWNED_GROUPS': journal,
                                'activation': activation}), source_scope():
        yield


def execute(argv, label, cap=120, env=None):
    global LAST_EXECUTION
    if Path(argv[0]) == BINARY:
        configured = dict(os.environ)
        configured['MC_BLOCK_REGISTRY'] = str(Session.P.OFFICIAL)
        if env:
            configured.update(env)
        env = configured
    try:
        out, err, receipt, receipt_pin = Host.execute_process(argv, label, cap, env)
    finally:
        LAST_EXECUTION = Host.LAST_EXECUTION
    Host.F.require_execution(receipt)
    require(not err, 'Unexpected native/supervisor stderr: ' + label)
    return out, receipt_pin


def build_child(report_path):
    value = audit()
    expected = WORK / 'build-attempt/builder.json'
    require(report_path == expected, 'Unrecognized child build report')
    pending = json.loads((WORK / 'build-attempt/request.json').read_bytes())
    argv = child_command('--_build-child', str(report_path))
    require(pending['argv'] == argv and pending['cap_seconds'] == 600,
            'No bounded parent compiler reservation')
    Host.unused(report_path, WORK / 'build-attempt/child-claim.json')
    exclusive(WORK / 'build-attempt/child-claim.json', {
        'pid': os.getpid(), 'pgid': os.getpgrp(),
        'ready_seal': value['seal_sha256'], 'retries_allowed': 0})
    import build_native as builder
    with Host.retry_scope(builder):
        started = time.perf_counter()
        environment = dict(os.environ)
        require(not any(environment.get(name) for name in builder.UNSUPPORTED_ENV)
                and not any(environment.get(name) for name in environment
                            if name.startswith('DYLD_')), 'Unresolved compiler injection')
        for name in ('', 'sources', 'entries', 'artifacts', 'locks'):
            (CACHE / name).mkdir(parents=True, exist_ok=True, mode=0o700)
        recipe = CLI_RECIPE.read_text()
        require(recipe.count('const cpu = [...objc, "-std=c11", "-O3", file, "-lpthread", "-lm",\n    ...libs, "-o", path.resolve(bin)];') == 1,
                'Pinned CLI CPU recipe changed')
        print(json.dumps({'phase': 'single-C-emission', 'entry': str(ENTRY)}), flush=True)
        prepared = builder._prepare(ENTRY.resolve(), Session.BEND.resolve(), environment, CACHE)
        key = prepared['cache_key']
        directory = CACHE / 'entries' / key
        emitted = CACHE / 'sources' / prepared['key_data']['prekey'] / 'generated.c'
        emitted_pin = pin(emitted)
        builder.guard_route(emitted.read_text())
        compiler = prepared['context']['compiler']
        require(compiler['flags'] == ['-std=c11', '-O3', '<emitted.c>', '-lpthread', '-lm', '-o', '<native>'],
                'Selected compiler recipe differs')
        print(json.dumps({'phase': 'compile-guarded-C', 'emitted': emitted_pin,
                          'emission_seconds': prepared['emitted_seconds']}), flush=True)
        compile_seconds = 0.0
        with builder.lock(CACHE / 'locks' / ('native-' + key + '.lock')):
            record = builder._verified(directory, key)
            cache_hit = record is not None
            if not cache_hit:
                require(not directory.exists(), 'Invalid content-keyed cache entry; preserve and diagnose')
                with tempfile.TemporaryDirectory(prefix='.native-', dir=CACHE / 'entries') as temporary:
                    temporary = Path(temporary)
                    binary = temporary / 'program'
                    command = [compiler['path'], '-std=c11', '-O3', str(emitted), '-lpthread', '-lm', '-o', str(binary)]
                    compiling = time.perf_counter()
                    compiled = builder.run(command, prepared['env'])
                    compile_seconds = time.perf_counter() - compiling
                    require(binary.is_file() and os.access(binary, os.X_OK), 'Selected CPU clang produced no executable')
                    require(pin(emitted) == emitted_pin, 'Retained C changed during compilation')
                    checked = builder._prepare(ENTRY.resolve(), Session.BEND.resolve(), environment, CACHE)
                    require(checked['cache_key'] == key
                            and checked['snapshot'].stamps == prepared['snapshot'].stamps,
                            'Native dependency identity changed; no retry')
                    record = {'schema': builder.SCHEMA, 'cache_key': key, 'key_data': prepared['key_data'],
                              'binary_sha256': builder.file_digest(binary), 'binary_bytes': binary.stat().st_size,
                              'emitted_c_sha256': prepared['emitted_c_sha256'],
                              'build_command': command, 'build_stdout': compiled.stdout[-4000:],
                              'build_stderr': compiled.stderr[-4000:], 'route': 'guarded-retained-CPU-C'}
                    builder._freeze(binary, CACHE, record['binary_sha256'])
                    (temporary / 'manifest.json').write_bytes(builder.encoded(record))
                    os.replace(temporary, directory)
            require(builder._verified(directory, key) is not None, 'Retained-C native cache verification failed')
        artifact = CACHE / 'artifacts' / record['binary_sha256'] / 'program'
        published = builder._publish(artifact, BINARY, record['binary_sha256'], CACHE)
        built = {'path': str(BINARY), 'artifact': str(artifact), 'cache_key': key, 'cache_hit': cache_hit,
                 'output_replaced': published, 'binary_sha256': record['binary_sha256'],
                 'binary_bytes': record['binary_bytes'], 'emitted_c_sha256': prepared['emitted_c_sha256'],
                 'dependencies': prepared['snapshot'].manifest(), 'compiler': compiler,
                 'identity': {k: v for k, v in prepared['context'].items() if k not in ('files', 'compiler')},
                 'retries': 0, 'route': 'guarded-retained-CPU-C', 'CLI_recipe': pin(CLI_RECIPE),
                 'timings': {'total_seconds': time.perf_counter() - started,
                             'emission_seconds': prepared['emitted_seconds'],
                             'native_compile_seconds': compile_seconds}, 'Bend_emissions': int(prepared['emitted_seconds'] > 0),
                 'cache_reuse': 'verified-hit' if cache_hit else 'miss'}
    require(built['retries'] == 0 and isinstance(built['cache_hit'], bool),
            'Unexpected compiler retry/cache disposition')
    audit()
    exclusive(report_path, built)
    print(json.dumps({'status': 'built-behavior-unverified',
                      'binary_sha256': built['binary_sha256'], 'retries': 0}), flush=True)


def verify_build(require_completion=True):
    global ARTIFACT_CONTEXT
    value = audit()
    manifest = Host.load_seal(CONSUMER)
    if ARTIFACT_CONTEXT is None:
        additional = {name: row for name, row in manifest['files'].items() if name not in value['files']}
        observed = dict(value['files'])
        observed.update(Host.check_files(additional))
        ARTIFACT_CONTEXT = (manifest, observed)
    else:
        require(manifest == ARTIFACT_CONTEXT[0], 'Artifact manifest changed')
        observed = ARTIFACT_CONTEXT[1]
    receipt = json.loads(BUILD.read_bytes())
    built = receipt['build']
    require(manifest['ready_seal'] == receipt['ready_seal'] == value['seal_sha256'],
            'Playable build generation differs')
    require(built['retries'] == 0 and isinstance(built['cache_hit'], bool)
            and pin(BINARY)['sha256'] == built['binary_sha256'],
            'Playable native artifact/retry history differs')
    require(manifest['native_dependencies'] ==
            Host.dependency_admission(built['dependencies'], observed=observed),
            'Playable native dependency alias/target admission differs')
    if require_completion:
        require(not (WORK / 'build-attempt/first-failure.json').exists(),
                'Failed build cannot admit native execution')
        completed = json.loads(BUILD_RESULT.read_bytes())
        cleanup = json.loads((WORK / 'build-attempt/final-cleanup.json').read_bytes())
        require(cleanup['status'] == 'passed'
                and completed['status'] == 'built-behavior-unverified'
                and completed['binary'] == pin(BINARY)
                and completed['consumer'] == pin(CONSUMER),
                'Playable build completion/cleanup not admitted')
    return value, receipt, manifest


def build():
    value = audit()
    directory = WORK / 'build-attempt'
    Host.unused(directory, BUILD, CONSUMER, BUILD_RESULT)
    directory.mkdir()
    argv = child_command('--_build-child', str(directory / 'builder.json'))
    exclusive(directory / 'request.json', {'argv': argv, 'cap_seconds': 600,
                                          'ready_seal': value['seal_sha256']})
    try:
        with execution_scope(directory):
            _, process = execute(argv, 'build', 600)
            built = json.loads((directory / 'builder.json').read_bytes())
            require(pin(BINARY)['sha256'] == built['binary_sha256'], 'Build bytes differ')
            exclusive(BUILD, {'status': 'built-behavior-unverified',
                             'ready_seal': value['seal_sha256'], 'build': built,
                             'process': process, 'producer': pin(__file__)})
            import build_native as builder
            cached = builder._verified(CACHE / 'entries' / built['cache_key'], built['cache_key'])
            require(cached is not None, 'Playable native cache invalid')
            emitted = CACHE / 'sources' / cached['key_data']['prekey'] / 'generated.c'
            files = dict(value['files'])
            dependencies = Host.dependency_admission(built['dependencies'])
            for item in dependencies:
                for key in ('lookup', 'target'):
                    files[item[key]['lookup']] = item[key]
            for path in (BINARY, BUILD, READY, emitted, Path(built['artifact']),
                         CACHE / 'entries' / built['cache_key'] / 'manifest.json'):
                files[str(path.absolute())] = pin(path)
            exclusive(CONSUMER, Host.sealed({'schema': 2, 'files': files,
                'ready_seal': value['seal_sha256'], 'build_receipt': pin(BUILD),
                'emitted_C': pin(emitted), 'native_dependencies': dependencies}))
            verify_build(require_completion=False)
            summary = {'status': 'built-behavior-unverified', 'binary': pin(BINARY),
                       'receipt': pin(BUILD), 'consumer': pin(CONSUMER),
                       'emitted_C': pin(emitted), 'native_dependencies': len(dependencies),
                       'timings': built['timings'], 'retries': 0, 'cache_hit': built['cache_hit'],
                       'cleanup': str(directory / 'final-cleanup.json')}
        exclusive(BUILD_RESULT, summary)
        print(json.dumps(summary), flush=True)
    except BaseException as cause:
        Host.failure(directory / 'first-failure.json', cause,
                     last_execution=LAST_EXECUTION)
        raise






def playable_inventory(creative=True, maybuild=True):
    return {'selected': 0, 'slots': [None] * 36,
            'abilities': {'instabuild': creative, 'maybuild': maybuild}}


def playable_payload(record, inventory):
    """Independent exact specification of the inventory codec, including legacy."""
    legacy = playable_inventory(False, True)
    if inventory == legacy:
        return S.local_bytes(record)
    slots = []
    for slot in inventory['slots']:
        slots.append(S.WC.compound([] if slot is None else [
            ('id', S.WC.txt(slot['id'])), ('count', S.WC.integer(slot['count']))]))
    return S.N.encode_root(S.N.RootTag(S.N.text('bendex:local-player-inventory-record'),
        S.WC.compound([
            ('format', S.WC.integer(2)), ('record', S.N.Value(7, S.local_bytes(record))),
            ('selected', S.WC.integer(inventory['selected'])),
            ('instabuild', S.WC.byte(int(inventory['abilities']['instabuild']))),
            ('maybuild', S.WC.byte(int(inventory['abilities']['maybuild']))),
            ('slots', S.N.Value(9, (10, tuple(slots))))])))


def playable_bundle(world, highwater, record, inventory):
    root = S.bundle_root(world, highwater, record)
    payload = playable_payload(record, inventory)
    extension = S.WC.compound([
        ('namespace', S.WC.txt(S.NAMESPACE)), ('schema', S.WC.integer(1)),
        ('payload', S.N.Value(7, payload))])
    return S.N.encode_root(S.N.RootTag(root.name, S.N.Value(10, tuple(
        (name, extension if name == S.N.text('extension') else value)
        for name, value in root.value.payload))))


def playable_parse_bundle(data, count, identity):
    """Validate full Core, then independent inventory wrapper and nested Local."""
    root = S.N.Reader(data, max_bytes=16846848, max_depth=6,
                      max_elements=16846848).root()
    S.require(root.name == S.N.text('bendex:bundle'), 'Playable bundle root')
    fields = S.WC.fields(root.value, S.BUNDLE_FIELDS)
    S.require(fields['format'] == S.WC.integer(1) and
              S.WC.scalar_text(fields['minecraft']) == '26.3' and
              S.WC.scalar_text(fields['registry']) == identity, 'Playable bundle identity')
    S.require(fields['core'].kind == 7, 'Playable Core byte-array type')
    world = S.WC.validate(S.N.parse(fields['core'].payload), count, identity)
    extension = S.WC.fields(fields['extension'], S.EXTENSION_FIELDS)
    S.require(S.WC.scalar_text(extension['namespace']) == S.NAMESPACE and
              extension['schema'] == S.WC.integer(1), 'Playable closed outer codec')
    S.require(extension['payload'].kind == 7 and len(extension['payload'].payload) <= 65536,
              'Playable extension type/bound')
    payload = bytes(extension['payload'].payload)
    inner = S.N.Reader(payload, max_bytes=65536, max_depth=4, max_elements=16384).root()
    if inner.name == S.N.text(S.NAMESPACE):
        record, inventory = S.decode_local(payload), playable_inventory(False, True)
    else:
        S.require(inner.name == S.N.text('bendex:local-player-inventory-record'),
                  'Playable inner inventory root')
        value = S.WC.fields(inner.value,
            ('format', 'record', 'selected', 'instabuild', 'maybuild', 'slots'))
        S.require(value['format'] == S.WC.integer(2) and value['record'].kind == 7,
                  'Playable inner version/nested record')
        record = S.decode_local(bytes(value['record'].payload))
        selected = S.WC.uint(value['selected'])
        S.require(selected < 9 and all(value[name] in (S.WC.byte(0), S.WC.byte(1))
                  for name in ('instabuild', 'maybuild')), 'Playable hotbar/abilities')
        listing = value['slots']
        S.require(listing.kind == 9 and listing.payload[0] == 10 and
                  len(listing.payload[1]) == 36, 'Playable 36-slot compound list')
        slots = []
        for item in listing.payload[1]:
            S.require(item.kind == 10, 'Playable slot compound')
            if not item.payload:
                slots.append(None)
                continue
            entry = S.WC.fields(item, ('id', 'count'))
            name, amount = S.WC.scalar_text(entry['id']), S.WC.uint(entry['count'])
            S.require(name in ('minecraft:stone', 'minecraft:dirt', 'minecraft:oak_planks')
                      and 1 <= amount <= 64, 'Playable admitted item/count')
            slots.append({'id': name, 'components': '', 'count': amount})
        inventory = {'selected': selected, 'slots': slots, 'abilities': {
            'instabuild': value['instabuild'].payload == 1,
            'maybuild': value['maybuild'].payload == 1}}
    S.require(payload == playable_payload(record, inventory), 'Noncanonical playable payload')
    highwater = S.WC.uint(fields['peer_highwater'])
    effective = max(highwater, world['max_peer'] or 0)
    S.require(effective < 0xffffffff, 'Playable peer range exhausted')
    return world, record, inventory, effective + 1


def playable_terrain(count, identity, palette):
    """Explicit fixture expectation; does not consume backend snapshots or saves."""
    world = S.WC.empty_world(count, identity)
    world['sections'] = [S.WC.section(S.BASE.section_key(x, y, z), palette['minecraft:air'])
        for x in (-32, -16, 0, 16, 32) for y in (-80, -64, -48)
        for z in (-32, -16, 0, 16, 32)]
    by_key = {section['key']: section for section in world['sections']}
    for section in world['sections']:
        section['cells'] = list(section['cells'])
    for x in range(-32, 48):
        for z in range(-32, 48):
            for y, material in ((-64, 'minecraft:stone'), (-63, 'minecraft:dirt'),
                                (-62, 'minecraft:dirt'), (-61, 'minecraft:stone')):
                by_key[S.BASE.section_key(x, y, z)]['cells'][
                    (x & 15) + ((z & 15) << 4) + ((y & 15) << 8)] = palette[material]
    for section in world['sections']:
        section['cells'] = tuple(section['cells'])
    world['sections'].sort(key=lambda item: item['key'])
    world['revision'] = 1
    world['events'] = [{'stamp': (0, 0, 0), 'kind': 0, 'revision': 1}]
    S.require(len(world['sections']) == 75 and sum(
        state != palette['minecraft:air'] for section in world['sections']
        for state in section['cells']) == 25600, 'Independent terrain dimensions')
    S.P.canonical_expected(world)
    return world


def playable_spawn(position=(0.5, -60.0, 0.5)):
    base = S.default_record()
    words = S.PC.snapshot(position=tuple(map(S.PC.raw64, position)), speed=0)
    motion = S.N.encode_root(S.PR.root(
        S.N.encode_root(S.PC.snapshot_root(words, 'minecraft:overworld')), (0, 0, 0, 0)))
    position = tuple(S.PC.bits64(words[:6]))
    return S.validate_local(dataclasses.replace(base, motion=motion,
        old_positions=position + position))


def playable_look(record, pitch):
    motion, look = S.PR.decode(record.motion)
    words, dimension = S.PC.parse_snapshot(motion)
    words = list(words)
    look = (0, S.PC.raw32(pitch), 0, S.PC.raw32(pitch))
    words[39], words[40] = S.PR.projection(look[0]), S.PR.projection(look[1])
    return S.validate_local(dataclasses.replace(record, motion=S.N.encode_root(S.PR.root(
        S.N.encode_root(S.PC.snapshot_root(tuple(words), dimension)), look))))


class PlayablePrivate:
    """Actual private socket, retaining each exact test packet and reply."""
    def __init__(self, backend):
        self.backend, self.sequence, self.epoch, self.buffer = backend, 1, None, b''
        self.socket = socket.create_connection(('127.0.0.1', backend.private_port), timeout=5)
        self.requests = (backend.directory / 'private.requests').open('xb')
        self.responses = (backend.directory / 'private.responses').open('xb')
        backend.private = self
        reply = self.exchange([1, 0, backend.token])
        S.require(len(reply) == 4 and reply[:2] == [1, 0] and reply[3] == 0,
                  'Playable private hello response')
        self.epoch = reply[2]
        S.require(isinstance(self.epoch, str) and self.epoch, 'Playable private epoch')

    def exchange(self, request):
        S.require(time.monotonic() < self.backend.deadline, 'Playable actor lifetime cap')
        data = json.dumps(request, ensure_ascii=True, separators=(',', ':')).encode('ascii') + b'\n'
        S.require(len(data) - 1 <= 16384, 'Playable private request budget')
        self.requests.write(data); self.requests.flush(); self.socket.sendall(data)
        deadline = min(time.monotonic() + 5, self.backend.deadline)
        while b'\n' not in self.buffer:
            remaining = deadline - time.monotonic()
            S.require(remaining > 0, 'Playable private response timeout')
            self.socket.settimeout(remaining)
            chunk = self.socket.recv(8192)
            self.responses.write(chunk); self.responses.flush()
            S.require(chunk, 'Playable private EOF before response')
            self.buffer += chunk
            S.require(len(self.buffer) <= 65537, 'Playable private physical frame bound')
        line, self.buffer = self.buffer.split(b'\n', 1)
        S.require(not self.buffer and len(line) <= 65536 and all(byte < 128 for byte in line),
                  'Playable private ASCII frame/tail')
        return json.loads(line)

    def call(self, body, kind=2):
        sequence = self.sequence
        reply = self.exchange([1, 1, self.epoch, sequence, body])
        self.sequence += 1
        S.require(reply[:4] == [1, kind, self.epoch, sequence],
                  'Playable private reply identity/tag: ' + str(reply[:4]))
        return reply

    def inventory(self, expected):
        slots = [[0] if item is None else [1, item['id'], '', item['count']]
                 for item in expected['slots']]
        snapshot = [expected['selected'], expected['abilities']['instabuild'],
                    expected['abilities']['maybuild'], slots]
        S.require(self.call([5], 4)[4:] == [snapshot], 'Private owned inventory differs')

    def aim_down(self):
        # Real protocol instrumentation: first relative event consumes the
        # default ignore-first flag, second clamps authoritative pitch to +90.
        self.call([1, [True, True, [[1, True, [3, 0, 0]],
            [1, True, [3, 0, S.PC.raw32(1000.0)]]]]])

    def close(self):
        self.socket.close(); self.requests.close(); self.responses.close()


class PlayableBackend:
    def __init__(self, directory, binary, path, bridge, *, create=False, mode='creative'):
        self.directory, self.path, self.bridge = Path(directory), Path(path), Path(bridge)
        self.directory.mkdir(exist_ok=False)
        self.port, self.private_port = S.MCP.free_port(), S.MCP.free_port()
        while self.private_port == self.port:
            self.private_port = S.MCP.free_port()
        # Fixed verification capabilities are not credentials or personal state.
        self.token = 'playable-acceptance-test-capability'
        self.private, self.clients, self.stopped = None, [], False
        env = S.BASE.environment(self.path, self.port, S.P.OFFICIAL, 'create' if create else None)
        env.update(MC_RENDER_PORT=str(self.private_port), MC_RENDER_TOKEN=self.token,
                   MC_RENDER_EPOCH='playable-test-' + self.directory.name[:18])
        self.argv = [str(binary), '--gpu', 'off', '--threads', '2', '--',
                     '--paused', '--game-mode', mode, '--stdin-control', '--sine', str(S.TABLE)]
        self.started = time.monotonic(); self.deadline = self.started + 120
        S.exclusive_json(self.directory / 'attempt.json', {'argv': self.argv,
            'save': str(self.path), 'public_port': self.port, 'private_port': self.private_port,
            'startup_cap_seconds': 20, 'lifetime_cap_seconds': 120})
        self.out = (self.directory / 'stdout').open('xb')
        self.err = (self.directory / 'stderr').open('xb')
        S.activation()
        self.process = subprocess.Popen(self.argv, cwd=S.ROOT, env=env, stdin=subprocess.PIPE,
            stdout=self.out, stderr=self.err, start_new_session=True)
        S.register_group(self.process.pid, 'playable-backend-' + self.directory.name)
        S.exclusive_json(self.directory / 'launched.json',
            {'pid': self.process.pid, 'pgid': self.process.pid, 'argv': self.argv})
        try:
            deadline = min(self.deadline, time.monotonic() + 20)
            while time.monotonic() < deadline:
                lines = (self.directory / 'stdout').read_bytes().split(b'\n')[:-1]
                events = [json.loads(line) for line in lines if line]
                public = [row for row in events if row.get('event') == 'server.ready']
                private = [row for row in events if row.get('event') == 'renderer.ready']
                if public and private:
                    S.require(public[0]['host'] == private[0]['host'] == '127.0.0.1'
                        and public[0]['port'] == self.port and private[0]['port'] == self.private_port
                        and private[0]['protocol'] == 1, 'Playable listener identity')
                    return
                S.require(self.process.poll() is None, 'Playable backend startup refused')
                time.sleep(.02)
            raise AssertionError('Playable paired readiness timeout')
        except BaseException:
            self.stop(failed=True)
            raise

    def tcp(self, developer=False):
        client = S.WireTCP(self.port, self.directory / ('tcp-' + str(len(self.clients))))
        self.clients.append(client)
        ping = client.call('ping')
        S.require(ping['sequence'] == 1 and ping['mode'] == 'observer', 'Playable raw startup')
        if developer:
            client.call('session.open', {'mode': 'developer', 'token': S.MCP.TOKEN})
        return client, ping

    def mcp(self, developer=True):
        client = S.WireMCP(self.bridge, self.port, S.MCP.TOKEN if developer else None,
                           self.directory / ('mcp-' + str(len(self.clients))))
        self.clients.append(client); client.initialize()
        ping = client.call('ping')
        S.require(ping['mode'] == ('developer' if developer else 'observer') and
                  ping['sequence'] == (3 if developer else 2), 'Playable actual MCP startup')
        return client, ping

    def stop(self, *, failed=False, kill=False):
        if self.stopped:
            return
        self.stopped = True
        errors = []
        if self.private is not None:
            try:
                self.private.close()
            except BaseException as cause:
                errors.append('private: ' + type(cause).__name__ + ': ' + str(cause))
        for client in self.clients:
            try:
                client.cleanup() if isinstance(client, S.WireMCP) else client.close()
            except BaseException as cause:
                errors.append('public: ' + type(cause).__name__ + ': ' + str(cause))
        try:
            if self.process.poll() is None:
                if kill:
                    os.killpg(self.process.pid, signal.SIGKILL)
                else:
                    self.process.stdin.write(b'stop\n'); self.process.stdin.flush()
                self.process.wait(timeout=5)
        except BaseException as cause:
            errors.append('stop: ' + type(cause).__name__ + ': ' + str(cause))
        finally:
            try:
                absent = S.reap(self.process)
            except BaseException as cause:
                absent = None
                errors.append('reap: ' + type(cause).__name__ + ': ' + str(cause))
            if self.process.stdin is not None and not self.process.stdin.closed:
                self.process.stdin.close()
            self.out.close(); self.err.close()
            listeners_absent = []
            for port in (self.port, self.private_port):
                with socket.socket() as probe:
                    probe.settimeout(.5)
                    listeners_absent.append(probe.connect_ex(('127.0.0.1', port)) != 0)
            receipt = {'pid': self.process.pid, 'argv': self.argv,
                'exit_code': self.process.returncode, 'group_absent': absent,
                'listeners_absent': listeners_absent, 'errors': errors,
                'seconds': time.monotonic() - self.started, 'actual_SIGKILL': kill,
                'stdout': S.pin(self.directory / 'stdout'), 'stderr': S.pin(self.directory / 'stderr')}
            S.exclusive_json(self.directory / 'process.json', receipt)
        if not failed:
            S.require(absent and all(listeners_absent) and not errors and
                      self.process.returncode == (-9 if kill else 0), 'Playable process teardown')
            S.require((self.directory / 'stderr').read_bytes() ==
                      (b'' if kill else b'resource backend stopped\n'), 'Playable lifetime diagnostic')


def playable_save(client, path, world, highwater, record, inventory, directory, label):
    reply = client.call('world.save', {})
    actual, expected = path.read_bytes(), playable_bundle(world, highwater, record, inventory)
    S.exclusive_json(directory / (label + '.json'), {'response': reply,
        'actual': {'bytes': len(actual), 'sha256': S.sha(actual)},
        'expected': {'bytes': len(expected), 'sha256': S.sha(expected)}})
    S.require(reply == {'status': 'durable', 'published': True, 'durable': True,
        'bytes': len(expected), 'peer_highwater': highwater}, 'Playable durable save response')
    S.require(actual == expected, 'Playable complete Core/Local/inventory save bytes')
    restored, local, items, nextpeer = playable_parse_bundle(actual, world['state_count'], world['registry'])
    S.require(S.P.canonical_expected(restored) == S.P.canonical_expected(world) and
              local == record and items == inventory and nextpeer == highwater + 1,
              'Playable independent full saved bundle')
    return actual


def playable_frame(control, world, record, palette):
    """Require real generated-terrain Frame; do not silently accept wire failure."""
    sample = control.call([0, 128, 128], 1)[4]
    S.require(isinstance(sample, list) and len(sample) == 7, 'Playable frame sample shape')
    tick, revision, origin, camera, colors, reads, rows = sample
    words, _ = S.PC.parse_snapshot(S.PR.decode(record.motion)[0])
    position = tuple(S.PC.f64(raw) for raw in S.PC.bits64(words[:6]))
    eye = (position[0], position[1] + S.PC.f32(record.eye), position[2])
    S.require((tick, revision) == (world['tick'], world['revision']) and
        origin == list(S.PC.words64(tuple(map(S.PC.raw64, eye)))) and
        camera == [0, 0, 0, *words[39:41]] and
        colors == [palette[name] for name in ('minecraft:air', 'minecraft:stone',
                                             'minecraft:dirt', 'minecraft:oak_planks')],
        'Playable frame clock/owned eye/camera/palette')
    by_key = {section['key']: section for section in world['sections']}
    def cell(x, y, z):
        return by_key[S.BASE.section_key(x, y, z)]['cells'][
            (x & 15) + ((z & 15) << 4) + ((y & 15) << 8)]
    expected = []
    directions = ((0, -1, 0), (0, 1, 0), (0, 0, -1), (0, 0, 1), (-1, 0, 0), (1, 0, 0))
    materials = {palette['minecraft:stone']: 0, palette['minecraft:dirt']: 1,
                 palette['minecraft:oak_planks']: 2}
    for z in range(-3, 5):
        for y in range(-64, -56):
            for x in range(-3, 5):
                state = cell(x, y, z)
                if state == palette['minecraft:air']:
                    continue
                mask = sum(1 << index for index, (dx, dy, dz) in enumerate(directions)
                           if cell(x + dx, y + dy, z + dz) == palette['minecraft:air'])
                boundary = int(x in (-3, 4)) + int(y in (-64, -57)) + int(z in (-3, 4))
                expected.append([S.unsigned(x), S.unsigned(y), S.unsigned(z), boundary,
                    state, materials[state], mask, *[S.PC.raw32(value - base)
                    for value, base in zip((x, y, z), eye)]])
    S.require(rows == expected and reads == 6 * len(expected),
              'Playable exact independent terrain rows/relative coords/visibility/read count')
    return {'rows': len(rows), 'reads': reads, 'sample_sha256': S.sha(S.canonical(sample))}


def _playable_backend_session(directory, binary, bridge):
    """Five real lifetimes plus one refused startup; all endpoints are loopback."""
    identity, count, _ = S.P.registry_identity(S.P.OFFICIAL)
    with S.P.OFFICIAL.open(newline='') as source:
        palette = {row['identifier']: int(row['default_state_id'])
                   for row in csv.DictReader(source, delimiter='\t')
                   if row['identifier'] in ('minecraft:air', 'minecraft:stone',
                                            'minecraft:dirt', 'minecraft:oak_planks')}
    S.require(len(palette) == 4, 'Playable official supported palette')
    world, record, inventory = playable_terrain(count, identity, palette), playable_spawn(), playable_inventory()
    path = directory / 'playable.nbt'
    actor = PlayableBackend(directory / 'generated', binary, path, bridge, create=True)
    frames, saved, highwater = [], None, None
    try:
        raw, ping = actor.tcp(True)
        S.require(ping['peer'] == 2, 'Fresh renderer Player1/public peer2 allocation')
        developer, dping = actor.mcp(); observer, oping = actor.mcp(False)
        highwater = max(ping['peer'], dping['peer'], oping['peer'])
        control = PlayablePrivate(actor)
        names = [entry['name'] for entry in developer.request('tools/list')['result']['tools']]
        S.require(len(names) == len(set(names)) and
            {'player.inspect', 'inventory.inspect', 'inventory.selected', 'inventory.select',
             'inventory.transfer', 'inventory.acquire', 'world.save', 'simulation.step'} <= set(names)
            and not any(name.startswith('fixture.') for name in names), 'Playable public MCP catalog')
        observer.call('world.save', {}, fault='PermissionDenied')
        observer.call('world.block.set', {'dimension': 'minecraft:overworld', 'x': 0,
            'y': -61, 'z': 0, 'state': palette['minecraft:air']}, fault='PermissionDenied')
        S.require(raw.call('simulation.pause', {'paused': True}) == S.P.clock(world), 'Generated clock')
        S.inspect(raw, record); S.require(observer.call('inventory.inspect', {}) == inventory, 'Fresh public inventory')
        control.inventory(inventory)
        S.require(observer.call('inventory.selected', {}) == {'index': 0, 'slot': None}, 'Fresh selected item')
        for point, state in (((-32, -64, -32), 'minecraft:stone'), ((47, -63, 47), 'minecraft:dirt'),
            ((0, -62, 0), 'minecraft:dirt'), ((0, -61, 0), 'minecraft:stone'),
            ((0, -60, 0), 'minecraft:air'), ((-32, -80, -32), 'minecraft:air'), ((47, -33, 47), 'minecraft:air')):
            x, y, z = point
            S.require(raw.call('world.block.get', {'dimension': 'minecraft:overworld', 'x': x,
                'y': y, 'z': z}) == {'state': palette[state]}, 'Generated layer/halo sample')
        raw.call('world.block.get', {'dimension': 'minecraft:overworld', 'x': 48,
                                    'y': -64, 'z': 0}, fault='MissingSection')
        frames.append(playable_frame(control, world, record, palette))
        S.require(control.call([3, 0], 5)[4:] == [False, 'interaction:miss'], 'Initial horizontal ray miss')
        observer.call('inventory.select', {'slot': 9}, fault='InvalidArguments')
        observer.call('inventory.acquire', {'slot': 0, 'item': 'minecraft:dirt', 'count': 65}, fault='InvalidArguments')
        S.require(observer.call('inventory.acquire', {'slot': 0, 'item': 'minecraft:dirt', 'count': 4})
                  == {'acquired': True}, 'Ability-authorized observer acquisition')
        inventory['slots'][0] = {'id': 'minecraft:dirt', 'components': '', 'count': 4}
        S.require(observer.call('inventory.transfer', {'source': 0, 'destination': 9, 'count': 2,
                                                      'mode': 'split'}) == {'moved': 2}, 'Inventory split')
        inventory['slots'][0]['count'] = 2; inventory['slots'][9] = copy.deepcopy(inventory['slots'][0])
        S.require(raw.call('inventory.inspect') == inventory, 'TCP observes MCP split')
        S.require(observer.call('inventory.transfer', {'source': 9, 'destination': 0, 'count': 99,
                                                      'mode': 'merge'}) == {'moved': 2}, 'Inventory merge clamp')
        inventory['slots'][0]['count'] = 4; inventory['slots'][9] = None
        control.aim_down(); record = playable_look(record, 90.0); S.inspect(raw, record)
        control.call([4, 1]); inventory['selected'] = 1; control.inventory(inventory)
        S.require(control.call([3, 1], 5)[4:] == [False, 'interaction:empty-hand'], 'Empty-hand placement refusal')
        control.call([4, 0]); inventory['selected'] = 0
        target = {'dimension': 'minecraft:overworld', 'x': 0, 'y': -61, 'z': 0}
        for button, state in ((0, 'minecraft:air'), (1, 'minecraft:dirt')):
            sequence = control.sequence
            S.require(control.call([3, button], 5)[4:] == [True, ''], 'Actual first-person edit')
            S.BASE.set_block(world, 0, -61, 0, palette[state]); world['revision'] += 1
            world['events'].insert(0, {'stamp': (world['tick'], 1, sequence), 'kind': 0,
                                       'revision': world['revision']})
            S.require(raw.call('world.block.get', target) == {'state': palette[state]}, 'Owned first-person target')
            S.require(raw.call('world.clock') == S.P.clock(world), 'Private edit exact event clock')
        S.inspect(raw, record); S.require(observer.call('inventory.inspect', {}) == inventory, 'Creative edits preserve count')
        control.inventory(inventory); frames.append(playable_frame(control, world, record, palette))
        control.call([2]); S.inspect(raw, record)
        saved = playable_save(developer, path, world, highwater, record, inventory, directory, 'acknowledged-save')
        # Actual unsaved inventory and first-person world edits, then SIGKILL.
        observer.call('inventory.acquire', {'slot': 2, 'item': 'minecraft:oak_planks', 'count': 1})
        S.require(control.call([3, 0], 5)[4:] == [True, ''], 'Unsaved actual first-person edit')
        S.require(raw.call('world.block.get', target) == {'state': palette['minecraft:air']} and
                  path.read_bytes() == saved, 'Unsaved edits touched durable bytes')
        actor.stop(kill=True)
    except BaseException:
        actor.stop(failed=True)
        raise
    finally:
        actor.stop()
    actor = PlayableBackend(directory / 'cold-reload', binary, path, bridge)
    try:
        raw, ping = actor.tcp(True)
        S.require(ping['peer'] == highwater + 2, 'Reload reserves saved highwater+1 Player then public+2')
        control = PlayablePrivate(actor)
        S.inspect(raw, record); S.require(raw.call('inventory.inspect') == inventory, 'Cold inventory/abilities/selection reload')
        S.require(raw.call('world.clock') == S.P.clock(world), 'Cold exact Core clock/queue')
        control.inventory(inventory); frames.append(playable_frame(control, world, record, palette))
        S.require(path.read_bytes() == saved, 'Cold open/frame/release changed acknowledged bytes')
        playable_save(raw, path, world, ping['peer'], record, inventory, directory, 'cold-reloaded-save')
    except BaseException:
        actor.stop(failed=True)
        raise
    finally:
        actor.stop()
    refusals = []
    for label, creative, maybuild in (('survival', False, True), ('no-build', True, False)):
        denied = playable_inventory(creative, maybuild)
        denied['slots'][0] = {'id': 'minecraft:dirt', 'components': '', 'count': 4}
        denied_path = directory / (label + '.nbt')
        denied_path.write_bytes(playable_bundle(world, 40, record, denied))
        actor = PlayableBackend(directory / label, binary, denied_path, bridge)
        try:
            raw, ping = actor.tcp(True); control = PlayablePrivate(actor)
            S.require(ping['peer'] == 42 and raw.call('inventory.inspect') == denied,
                      'Saved abilities must survive creative CLI default')
            control.inventory(denied)
            for button in (0, 1):
                S.require(control.call([3, button], 5)[4:] ==
                          [False, 'interaction:creative-build-ability-required'], 'Saved ability edit refusal')
            if not creative:
                raw.call('inventory.acquire', {'slot': 1, 'item': 'minecraft:stone', 'count': 1},
                         fault='InventoryAcquisitionRejected')
            S.inspect(raw, record); S.require(raw.call('inventory.inspect') == denied and
                raw.call('world.clock') == S.P.clock(world), 'Refused ability request changed live state')
            playable_save(raw, denied_path, world, ping['peer'], record, denied,
                          directory, label + '-refused-save')
            refusals.append({'case': label, 'instabuild': creative, 'maybuild': maybuild,
                             'both_buttons_refused': True})
        except BaseException:
            actor.stop(failed=True)
            raise
        finally:
            actor.stop()
    empty = S.WC.empty_world(count, identity)
    nondefault = dataclasses.replace(playable_spawn((1.5, -60.0, 0.5)), count=7, invulnerable=9)
    nondefault = playable_look(nondefault, 30.0)
    loaded_items = playable_inventory(False, True)
    loaded_items['selected'] = 3
    loaded_path = directory / 'loaded-empty-core.nbt'
    loaded_bytes = playable_bundle(empty, 60, nondefault, loaded_items)
    loaded_path.write_bytes(loaded_bytes)
    actor = PlayableBackend(directory / 'loaded-empty-core', binary, loaded_path, bridge)
    try:
        raw, ping = actor.tcp(True)
        S.require(ping['peer'] == 62, 'Loaded empty Core owner/public peer allocation')
        S.inspect(raw, nondefault)
        S.require(raw.call('world.clock') == S.P.clock(empty) and
                  raw.call('inventory.inspect') == loaded_items, 'Loaded empty Core/player regeneration')
        raw.call('world.block.get', {'dimension': 'minecraft:overworld', 'x': 0,
            'y': -61, 'z': 0}, fault='MissingSection')
        S.require(loaded_path.read_bytes() == loaded_bytes, 'Loaded view setup modified save bytes')
        playable_save(raw, loaded_path, empty, ping['peer'], nondefault, loaded_items,
                      directory, 'loaded-empty-Core-preserved-save')
    except BaseException:
        actor.stop(failed=True)
        raise
    finally:
        actor.stop()
    # Existing records outside the supported vertical view are refused rather
    # than being silently replaced with the new-world body/terrain initializer.
    outside_path = directory / 'loaded-outside-view.nbt'
    outside_bytes = playable_bundle(empty, 80, playable_spawn((0.5, 1.0, 0.5)), loaded_items)
    outside_path.write_bytes(outside_bytes)
    refused_directory = directory / 'loaded-outside-view'
    try:
        actor = PlayableBackend(refused_directory, binary, outside_path, bridge)
    except AssertionError as cause:
        S.require(str(cause) == 'Playable backend startup refused',
                  'Outside-view startup failed through unexpected mechanism')
    else:
        actor.stop(failed=True)
        raise AssertionError('Outside-view loaded player was silently accepted/replaced')
    receipt = json.loads((refused_directory / 'process.json').read_bytes())
    error = (refused_directory / 'stderr').read_bytes()
    S.require(receipt['exit_code'] not in (None, 0, -9) and receipt['group_absent'] is True
        and all(receipt['listeners_absent']) and not (refused_directory / 'stdout').read_bytes()
        and b'unsupported-superflat-view:outside-generated-region' in error
        and outside_path.read_bytes() == outside_bytes, 'Outside-view refusal/save preservation')
    summary = {'status': 'PASS', 'backends': 5, 'refused_startups': 1, 'terrain_sections': 75,
        'generated_nonair_cells': 25600, 'complete_saved_Core_compared': True,
        'complete_Local_record_compared': True, 'inventory_slots': 36,
        'private_actual_arrays_recorded': True, 'public_actual_TCP_MCP_recorded': True,
        'first_person_break_place': True, 'actual_unsaved_SIGKILL_recovery': True,
        'frames': frames, 'ability_refusals': refusals,
        'loaded_empty_Core_not_regenerated': True, 'loaded_outside_view_refused': True,
        'initial_saved_sha256': S.sha(saved), 'scope':
        'Bounded custom superflat/creative full-cube backend acceptance with synthetic private packets; '
        'no OS input, native presentation, new Java behavior oracle, or whole Minecraft parity.'}
    S.exclusive_json(directory / 'summary.json', summary)
    return summary


def current_backend_session(directory, binary, bridge):
    """Current002 actor boundary: complete v3 authority and durable recovery.

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
        developer.call('inventory.acquire', {'slot': 0, 'item': 'minecraft:dirt', 'count': 4})
        full['main']['slots'][0] = Inventory.stack('minecraft:dirt', 4)
        full['main']['selected'] = 0; observed(control, [12, 0], 'select')
        menu['opened'] = True; observed(control, [9], 'open')
        menu['carried'], full['main']['slots'][0] = full['main']['slots'][0], None
        menu['revision'] += 1; observed(control, [11, 36, [0, 0]], 'pickup-hotbar-to-carried')
        observed(control, [10], 'close-retains-carried', False,
                 'menu retains carried or crafting items; return/drop authority is required before closing')
        raw.call('world.save', {}, fault='SaveEncodingFailed')
        S.require(path.read_bytes() == initial, 'Refused temporary-item save published bytes')
        full['main']['slots'][1], menu['carried'] = menu['carried'], None
        menu['revision'] += 1; observed(control, [11, 37, [0, 0]], 'place-carried-into-hotbar')
        observed(control, [11, 37, [1]], 'unsupported-quickmove-preserves', False,
                 'menu click kind requires its authoritative vanilla consumer')
        menu['opened'] = False; observed(control, [10], 'close-empty-temporary')
        full['main']['slots'][0], full['main']['slots'][1] = full['main']['slots'][1], None
        observed(control, [6, 1, 0, 99, 0], 'private-transfer')
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
        full['main']['slots'][2] = Inventory.stack('minecraft:oak_planks', 1)
        observed(control, [7, 2, ['minecraft:oak_planks', ''], 1], 'unsaved-private-acquire')
        S.require(path.read_bytes() == acknowledged, 'Unsaved private acquisition changed durable bytes')
        full['main']['slots'][2] = None
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
        saved(raw, path, ping['peer'], 'cold-reloaded-save')
    except BaseException:
        actor.stop(failed=True)
        raise
    finally:
        actor.stop()
    result = {'status': 'PASS', 'actor_generation': 'immutable-current002/producer010',
        'backends': 2, 'public_TCP_MCP': True, 'private_menu_checks': checks,
        'complete_menu_authority': True, 'main_slots': 36, 'equipment_slots': 7,
        'raw_status': full['status'], 'generation_sha256': S.sha(full['generation']),
        'terrain_sections': 104, 'frames': frames, 'first_person_break_place': True,
        'save_comparisons': saves, 'actual_SIGKILL_cold_reload': True,
        'scope': 'Actual current002 transport/menu/v3/WG durable boundary; synthetic private packets. '
                 'The later extracted selector, next-generation close disposition, physical window input '
                 'and numerical flight/world fidelity are separate.'}
    S.exclusive_json(directory / 'summary.json', result)
    return result


def backend_session(directory, binary, bridge):
    """Caller must provide the FRR2 admission and unconditional group sweep."""
    directory = Path(directory)
    directory.mkdir(exist_ok=False)
    try:
        return _playable_backend_session(directory, binary, bridge)
    except BaseException as cause:
        S.exclusive_json(directory / 'first-failure.json', {
            'status': 'FAIL', 'error': type(cause).__name__ + ': ' + str(cause),
            'retained_process_receipts': [S.pin(path) for path in sorted(directory.rglob('process.json'))],
            'retained_raw_streams': [S.pin(path) for path in sorted(directory.rglob('*'))
                if path.is_file() and path.name in ('stdout', 'stderr', 'private.requests', 'private.responses')],
            'scope': 'Actual backend/private/public transport lane; parent retains owned PID cleanup journal.'})
        raise


def backend_child(directory):
    value, _, _ = verify_build()
    require(directory == WORK / 'native-attempt/backend', 'Unknown backend directory')
    journal = directory.parent / 'backend-owned-groups.jsonl'
    journal.touch(exist_ok=False)
    bridge, _ = retained_bridge()
    with session_scope(journal):
        if value['contract_generation'] == 'current-v3-menu-status-demand-generation':
            result = current_backend_session(directory, BINARY, bridge)
        else:
            result = backend_session(directory, BINARY, bridge)
    exclusive(directory / 'acceptance.json', {'status': 'passed', 'result': result})


def child_lane(name, directory):
    pending = json.loads((WORK / 'native-attempt' / (name + '-request.json')).read_bytes())
    expected = child_command('--_native-child', name)
    require(pending['argv'] == expected and pending['cap_seconds'] == 120,
            'Missing bounded native child reservation')
    if name == 'atomic':
        atomic_child(directory)
    elif name == 'backend':
        backend_child(directory)
    else:
        raise Host.Refused('Unknown child lane: ' + name)


def native():
    if ROLE == 'block-reference':
        return native_reference_lane()
    value, receipt, _ = verify_build()
    directory = WORK / 'native-attempt'
    Host.unused(directory, NATIVE_RESULT)
    directory.mkdir()
    lanes = []
    try:
        with execution_scope(directory):
            for name in ('backend', 'atomic'):
                verify_build()
                argv = child_command('--_native-child', name)
                exclusive(directory / (name + '-request.json'),
                          {'argv': argv, 'cap_seconds': 120,
                           'ready_seal': value['seal_sha256']})
                _, process = execute(argv, name)
                cleaned = OldConsumer.sweep_directory(directory, name + '-descendant-cleanup')
                require(cleaned['status'] == 'PASS', 'Managed child groups not absent: ' + name)
                result = json.loads((directory / name / 'acceptance.json').read_bytes())
                require(result['status'] == 'passed', 'Boundary lane failed: ' + name)
                lanes.append({'lane': name, 'process': process,
                              'summary': pin(directory / name /
                                  'acceptance.json')})
            verify_build()
            summary = {'status': 'passed', 'binary': pin(BINARY),
                       'consumer': pin(CONSUMER), 'ready_seal': value['seal_sha256'],
                       'lanes': lanes,
                       'historical': value['historical'],
                       'scope': 'Mapped ' + value['contract_generation'] +
                       ' actual TCP/MCP/private gameplay/save/cold reload; retained exact Atomic primitive interruptions. Pure proofs/reference fidelity and visible presentation remain separate.'}
        exclusive(directory / 'summary.json', summary)
        exclusive(NATIVE_RESULT, summary)
        print(json.dumps(summary), flush=True)
    except BaseException as cause:
        # Sweep journals even when a child refuses before its own cleanup receipt.
        cleaned = OldConsumer.sweep_directory(directory, 'failure-descendant-cleanup')
        Host.failure(directory / 'first-failure.json', cause,
                     completed_lanes=len(lanes), cleanup=cleaned,
                     last_execution=LAST_EXECUTION)
        raise


@contextlib.contextmanager
def reference_scope():
    reference = importlib.import_module('test_player_block_reference')
    with Host.bindings(reference, {'ENTRY': ENTRY, 'TABLE': SOURCE_ROOT / 'generated/reference_mth_sin.f32'}), \
         Host.bindings(reference.R, {'OUTPUT': SOURCE_ROOT / 'reference/player_block_interaction.json'}):
        yield reference


def prepare_reference_lane():
    import build_native as builder
    summary_path = ROOT / ('evidence/playable-client-reference-prepared-' + ATTEMPT + '.json')
    Host.unused(WORK, summary_path)
    WORK.mkdir(parents=True, exist_ok=False)
    with reference_scope() as reference:
        fixture = reference.prepare_reference(WORK / 'cases')
    snapshot = builder.Snapshot()
    snapshot.add(Session.BEND, 'bend-compiler')
    base = (Session.BEND.resolve().parent.parent / 'bend2/base.bend').resolve()
    builder.source_graph(ENTRY, base, dict(os.environ), snapshot)
    closure = snapshot.manifest()
    paths = {Path(row[key]) for row in closure for key in ('lookup', 'path')}
    paths.update(Session.tool_closure([Path(__file__), ROOT / 'tools/build_native.py',
                                      ROOT / 'tools/test_player_block_reference.py']))
    paths.update([HISTORICAL, CLI_RECIPE, Path(sys.executable),
                  SOURCE_ROOT / 'source-map.json', WORK / 'cases/manifest.json'])
    for field in ('reference', 'input', 'expected', 'entry', 'helper', 'sine_table'):
        paths.add(Path(fixture[field]['path']))
    value = Host.sealed({'schema': 3, 'status': 'prepared-reference-unverified',
        'role': ROLE, 'entry': pin(ENTRY), 'runner': IMPORT_PIN,
        'documentation': {'pin': pin(DOC), 'role': 'Informational; not consumed by build or native checks.'},
        'files': {str(path.absolute()): pin(path) for path in sorted(paths, key=str)},
        'Bend_imports': closure, 'source_dependencies': Host.dependency_admission(closure),
        'mapped_source': pin(SOURCE_ROOT / 'source-map.json'),
        'environment_sha256': Session.environment_pin(), 'fixed_helpers': fixed_helpers(),
        'reference_manifest': pin(WORK / 'cases/manifest.json'),
        'native_arguments': fixture['arguments'], 'admitted_cases': fixture['admitted_cases'],
        'excluded_cases': fixture['excluded_cases'],
        'scope': 'Separate actual C/Java block numeric/geometry fidelity gap; no product actor or proof acceptance inferred.',
        'compiler_executions': 0, 'native_executions': 0, 'Java_executions': 0})
    exclusive(READY, value)
    audit()
    summary = {'status': value['status'], 'role': ROLE, 'ready': pin(READY),
               'seal_sha256': value['seal_sha256'], 'admitted_cases': value['admitted_cases'],
               'excluded_cases': value['excluded_cases'], 'Bend_imports': len(closure),
               'compiler_executions': 0, 'native_executions': 0}
    exclusive(summary_path, summary)
    print(json.dumps(summary), flush=True)


def native_reference_lane():
    value, receipt, _ = verify_build()
    directory = WORK / 'native-attempt'
    Host.unused(directory, NATIVE_RESULT)
    directory.mkdir()
    try:
        with execution_scope(directory):
            out, process = execute([str(BINARY), '--gpu', 'off', '--threads', '1', '--',
                                    *value['native_arguments']], 'reference604', 60)
            with reference_scope() as reference:
                comparison = reference.compare(out, WORK / 'cases/manifest.json')
            require(comparison['status'] == 'passed', 'Actual reference replay failed')
            summary = {'status': 'passed', 'role': ROLE, 'binary': pin(BINARY),
                       'consumer': pin(CONSUMER), 'ready_seal': value['seal_sha256'],
                       'comparison': comparison, 'process': process,
                       'scope': value['scope']}
        summary['cleanup'] = pin(directory / 'final-cleanup.json')
        exclusive(directory / 'summary.json', summary)
        exclusive(NATIVE_RESULT, summary)
        print(json.dumps(summary), flush=True)
    except BaseException as cause:
        Host.failure(directory / 'first-failure.json', cause, last_execution=LAST_EXECUTION)
        raise


def child_command(*args):
    return [sys.executable, str(Path(__file__)), '--role', ROLE, '--attempt', ATTEMPT, *args]


def select_attempt(name, role):
    global ROLE, RUN_ROOT, SOURCE_ROOT, ENTRY, ATTEMPT, WORK, READY, BINARY, BUILD, CONSUMER, BUILD_RESULT, NATIVE_RESULT
    require(re.fullmatch(r'[0-9]{3}', name) is not None, 'Attempt must be three decimal digits')
    ROLE = role
    stem = 'backend' if role == 'backend' else 'reference'
    RUN_ROOT = ROOT / ('build/playable-client-' + stem + '-session')
    SOURCE_ROOT = (ROOT / 'build/playable-client-current-source' / name
                   if role == 'backend' and name != '001' else
                   ROOT / 'build/playable-client-live-source')
    ENTRY = SOURCE_ROOT / ('remote_resource_server.bend' if role == 'backend' else 'tests/player_block_reference.bend')
    ATTEMPT = name
    WORK = RUN_ROOT / name
    READY = WORK / 'prepared.json'
    BINARY = WORK / (stem + '-native')
    BUILD = WORK / 'native-build.json'
    CONSUMER = WORK / 'consumer-manifest.json'
    BUILD_RESULT = ROOT / ('evidence/playable-client-' + stem + '-build-' + name + '.json')
    NATIVE_RESULT = ROOT / ('evidence/playable-client-' + stem + '-native-' + name + '.json')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--attempt', default='001')
    parser.add_argument('--role', choices=('backend', 'block-reference'), default='backend')
    mode = parser.add_mutually_exclusive_group(required=True)
    for name in ('prepare', 'audit', 'build-only', 'native'):
        mode.add_argument('--' + name, action='store_true')
    mode.add_argument('--_build-child', type=Path)
    mode.add_argument('--_native-child', choices=('backend', 'atomic'))
    args = parser.parse_args()
    select_attempt(args.attempt, args.role)
    if args.prepare:
        prepare()
    elif args.audit:
        value = audit()
        print(json.dumps({'status': 'passed', 'files': len(value['files']),
                          'ready': pin(READY), 'scope': 'Read-only admission.'}), flush=True)
    elif args.build_only:
        build()
    elif args.native:
        native()
    elif args._build_child:
        build_child(args._build_child)
    else:
        child_lane(args._native_child, WORK / 'native-attempt' / args._native_child)


if __name__ == '__main__':
    main()
