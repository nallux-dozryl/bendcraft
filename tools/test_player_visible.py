#!/usr/bin/env python3
"""Prepare/audit a bounded visible smoke without foreground or input effects.

Default preparation audits the frozen native generation, creates an exclusive
disposable fixture and obtains actual Java receiver expectations. --audit checks
the saved preparation without Java/compiler/client/UI processes. --run attaches
to an already launched, explicitly authorized manual/CUA session. It never
launches the client or controls UI. The generated app launcher remains dormant
until a separate explicit root/human launch authorization exists.
"""
from __future__ import annotations

import argparse
import ctypes
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import plistlib
import secrets
import socket
import struct
import subprocess
import sys
import tempfile
import time

import test_player_client as Client
import test_player_session as Session

ROOT = Client.ROOT
WORK = ROOT / 'build/player-visible'
EVIDENCE = ROOT / 'evidence/player-visible-preparation.json'
HELPER = ROOT / 'tools/visible_os_input.swift'
HELPER_SHA = '4850508d835a7d91286d7b47f6c7a86ace35315f4e8782b046a3f3804890ef97'
HELPER_BINARY_SHA = '475b6be4b3260758039c540177c7d18f9a13fbb1f3ffe89f0fce50303989304d'
BUNDLE_ID = 'local.bendex.minecraft.visible-smoke'
KEY = 'cc54411dd05d4dff64679237368f48fb64540916138cc7c16f45ffbf29d9eac4'
BINARY_SHA = 'dc23c1d632273ce59b26e7a67bc79bab7cbf94497d7d49d709bf9ae1f1a455f3'
SOURCE_PINS = {
    'player_client.bend': 'b5ba15401a3b80ac045619fe5ad38de091bf96c6e7742c51fbc84834812a71c5',
    'src/player_scene.bend': '1887393c33a6eafc3b72e198518932c7c9465f4e6f8723d7cf5c5494a5b359ac',
    'src/player_runtime.bend': '0580f77db4a9e9d570938f6c6487867cd1ea92b0a2c24246fa0f354aa0604242',
    'src/player_session.bend': 'e4d515442e9446aa308dee68630ef48755565562a2441052f54d3e422416e6d2',
}
GAPS = [
    'No visible session has run. Root orchestration and explicit human foreground coordination remain required.',
    'Manual holds plus actual body/input/look response can establish narrow delivery; no native Base-event trace, raw held buttons, capture state or ignore-first flag is exposed.',
    'First-move discard/capture internals stay unverified unless independent observation is available; this does not block the early smoke.',
    'CUA screenshot, Escape, click/recapture and close are documented routes, but their actual target behavior remains to be observed after coordination.',
    'The app-wrapper/LaunchServices association has not been launched or registered; successful binding/launch remains an observation of the future session.',
    'The dormant CG helper lacks current post access. This plan uses manual held input and CUA observations, with no CG posts or permission requests.',
]
BOUNDARY = [
    'Preparation never launches a client/helper, requests permissions, posts input, captures screenshots or changes foreground/Spaces.',
    'Java executes actual pinned plain Player.aiStep/movement/support with the declared neutral test profile; it is not LocalPlayer acceptance.',
    'A frame description is not a screenshot. Posted process events are not proven delivery. Unchanged first-look angles alone do not prove discard.',
    'Nominal hold durations do not determine sampled tick inputs. Exact raw comparison requires the actual input/tick history to be independently established.',
    'Continuous movement must use the actor 50 ms timer. The visible plan forbids simulation.step; API inspection/pause/save are separate observations/controls.',
    'The finite floor/cube scene and missing UI do not cover inventory, menus/settings flows, full rendering, audio, latency or whole-game parity.',
]


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def sha(path):
    return Client.sha(path)


def write(path, value):
    Session.write_json(path, value)


def exclusive(path, data):
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, 'wb') as output:
        output.write(data)
        output.flush()
        os.fsync(output.fileno())


def process_identity(pid):
    """Read libproc identity, including launch time, without activation/input.

    Layout/constants were checked in the installed SDK sys/proc_info.h:
    PROC_PIDTBSDINFO=3, twelve U32 fields, char[16], char[32], six U32,
    followed by the two U64 start-time fields (136 bytes total).
    """
    lib = ctypes.CDLL('/usr/lib/libproc.dylib', use_errno=True)
    lib.proc_pidpath.argtypes = [ctypes.c_int, ctypes.c_void_p, ctypes.c_uint32]
    lib.proc_pidpath.restype = ctypes.c_int
    lib.proc_pidinfo.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_uint64,
                                ctypes.c_void_p, ctypes.c_int]
    lib.proc_pidinfo.restype = ctypes.c_int
    path, info = ctypes.create_string_buffer(4096), ctypes.create_string_buffer(136)
    if lib.proc_pidpath(pid, path, len(path)) <= 0 or lib.proc_pidinfo(pid, 3, 0, info, len(info)) != 136:
        return None
    return {'pid': pid, 'executable': os.fsdecode(path.value),
            'started_tvsec': struct.unpack_from('=Q', info.raw, 120)[0],
            'started_tvusec': struct.unpack_from('=Q', info.raw, 128)[0]}


LAUNCHER = r'''
import ctypes, hashlib, json, os, socket, struct, sys, time
from datetime import datetime, timezone
from pathlib import Path
def require(ok, message):
    if not ok: raise RuntimeError(message)
def digest(path): return hashlib.sha256(Path(path).read_bytes()).hexdigest()
def private_json(path):
    p=Path(path)
    require(p.is_file() and p.stat().st_mode & 0o777 == 0o600, 'missing private authorization')
    return json.loads(p.read_text())
def process_start(pid):
    lib=ctypes.CDLL('/usr/lib/libproc.dylib')
    buf=ctypes.create_string_buffer(136)
    path=ctypes.create_string_buffer(4096)
    lib.proc_pidinfo.argtypes=[ctypes.c_int,ctypes.c_int,ctypes.c_uint64,ctypes.c_void_p,ctypes.c_int]
    lib.proc_pidpath.argtypes=[ctypes.c_int,ctypes.c_void_p,ctypes.c_uint32]
    require(lib.proc_pidinfo(pid,3,0,buf,len(buf))==136,'process identity unavailable')
    require(lib.proc_pidpath(pid,path,len(path))>0,'process path unavailable')
    return list(struct.unpack_from('=QQ',buf.raw,120)),os.fsdecode(path.value)
def exclusive(path, data):
    with os.fdopen(os.open(path,os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600),'wb') as out:
        out.write(data);out.flush();os.fsync(out.fileno())
config_path=Path(__CONFIG_PATH__)
config=json.loads(config_path.read_text())
try:
    grant=private_json(config['launch_authorization'])
    expires=datetime.fromisoformat(grant['expires_at_utc'])
    require(grant.get('root_orchestration_authorized') is True and
            grant.get('human_foreground_coordination_obtained') is True and
            isinstance(grant.get('human_coordination_evidence'),str) and grant['human_coordination_evidence'].strip(),
            'explicit root and human coordination required')
    require(grant.get('launch_mode')=='human' and grant.get('input_lane')=='manual-and-cua' and
            grant.get('preparation_sha256')==digest(config['preparation']) and
            grant.get('target_binary_sha256')==config['binary_sha256'] and
            grant.get('app_path')==config['app_path'] and
            type(grant.get('timeout_seconds')) is int and 1<=grant['timeout_seconds']<=180 and
            expires.tzinfo is not None and datetime.now(timezone.utc)<expires,'authorization pins/expiry invalid')
    phase=grant.get('launch_phase')
    require(phase in ('initial','restart'),'only initial/restart phases are supported')
    prep=json.loads(Path(config['preparation']).read_text())
    require(digest(config_path)==prep['wrapper']['config_sha256'] and
            digest(__file__)==prep['wrapper']['launcher_sha256'] and
            digest(config['info_plist'])==prep['wrapper']['info_plist_sha256'] and
            digest(sys.executable)==prep['wrapper']['python_sha256'],'wrapper policy changed')
    started,runtime=process_start(os.getpid())
    require(runtime==prep['wrapper']['python_runtime'] and
            digest(runtime)==prep['wrapper']['python_runtime_sha256'],'actual Python runtime changed')
    require(digest(config['binary'])==config['binary_sha256'],'copied native executable changed')
    for path,expected in config['resource_sha256'].items():
        require(digest(path)==expected,'resource changed')
    token_path=Path(config['token_file'])
    require(token_path.stat().st_mode & 0o777 == 0o600,'private token mode changed')
    token=token_path.read_text('ascii')
    require(len(token)==64 and all(c in '0123456789abcdef' for c in token),'private token malformed')
    now=time.monotonic()
    if phase=='initial':
        require(digest(config['bundle'])==prep['fixture']['bundle_sha256'],'initial bundle changed')
        deadline=now+grant['timeout_seconds']
    else:
        previous=json.loads(Path(config['directory'],'initial.launch.json').read_text())
        finished=json.loads(Path(config['directory'],'initial.observer.json').read_text())
        require(finished.get('process_exit_observed') is True and finished.get('save_verified') is True,
                'restart requires observed exit and verified paused save')
        require(digest(config['bundle'])==finished['saved_bundle_sha256'],'saved bundle changed before restart')
        deadline=previous['session_deadline_monotonic']
        require(now<deadline,'single session budget expired')
    sock=socket.socket();sock.bind(('127.0.0.1',config['port']));sock.close()
    argv=config['argv'][phase]
    env=dict(config['environment']);env['MC_DEV_TOKEN']=token
    receipt={'pid':os.getpid(),'process_start':started,'binary':config['binary'],
             'binary_sha256':config['binary_sha256'],'launch_phase':phase,'argv':argv,
             'environment':config['environment'],'mode':'human','input_lane':'manual-and-cua',
             'started_monotonic':now,'session_deadline_monotonic':deadline,
             'launch_authorization_sha256':digest(config['launch_authorization']),
             'preparation_sha256':digest(config['preparation'])}
    exclusive(str(Path(config['directory'],phase+'.launch.json')),json.dumps(receipt,sort_keys=True).encode()+b'\n')
    out=os.open(str(Path(config['directory'],phase+'.stdout')),os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    err=os.open(str(Path(config['directory'],phase+'.stderr')),os.O_WRONLY|os.O_CREAT|os.O_EXCL,0o600)
    os.dup2(out,1);os.dup2(err,2);os.close(out);os.close(err)
    os.chdir(config['cwd'])
    os.execve(config['binary'],argv,env)
except Exception as error:
    # Guard diagnostics deliberately omit environment/token/authorization data.
    print('visible smoke launcher refused: '+str(error),file=sys.stderr)
    raise SystemExit(1)
'''


def package_app(artifact, setup):
    directory = Path(setup['directory'])
    app = directory / 'Minecraft Player Smoke.app'
    macos, resources = app / 'Contents/MacOS', app / 'Contents/Resources'
    macos.mkdir(parents=True, mode=0o700)
    resources.mkdir(mode=0o700)
    (directory / 'tmp').mkdir(mode=0o700)
    binary, launcher = macos / 'player-native', macos / 'launch-player'
    exclusive(binary, Path(artifact).read_bytes())
    binary.chmod(0o500)
    require(sha(binary) == BINARY_SHA, 'app native copy changed')
    plist = app / 'Contents/Info.plist'
    exclusive(plist, plistlib.dumps({'CFBundleIdentifier': BUNDLE_ID,
        'CFBundleExecutable': 'launch-player', 'CFBundleName': 'Minecraft Player Smoke',
        'CFBundleDisplayName': 'Minecraft Player Smoke', 'CFBundlePackageType': 'APPL',
        'CFBundleVersion': '1', 'CFBundleShortVersionString': '1',
        'NSHighResolutionCapable': True}))
    port = Session.MCP.free_port()
    environment = {'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'HOME': str(Path.home()),
                   'LANG': 'en_US.UTF-8', 'TMPDIR': str(directory / 'tmp'),
                   '__CFBundleIdentifier': BUNDLE_ID, 'BEND_MINECRAFT_LAUNCH_MODE': 'human',
                   'MC_WORLD_PATH': setup['bundle'], 'MC_BLOCK_REGISTRY': str(Session.P.OFFICIAL),
                   'MC_LIVE_PORT': str(port)}
    args = [str(binary), '--threads', '2', '--gpu', 'off', '--', '--verification-fixture']
    tail = ['--jar', str(Client.JAR), '--sine', str(Client.TABLE)]
    config = {'directory': str(directory), 'app_path': str(app), 'binary': str(binary),
              'binary_sha256': BINARY_SHA, 'cwd': str(ROOT), 'environment': environment,
              'argv': {'initial': args + ['--unpaused'] + tail, 'restart': args + tail},
              'port': port, 'bundle': setup['bundle'], 'token_file': setup['token_file'],
              'preparation': str(EVIDENCE), 'info_plist': str(plist),
              'launch_authorization': str(directory / 'launch-authorization.private.json'),
              'resource_sha256': {str(p): sha(p) for p in (Client.JAR, Client.TABLE, Session.P.OFFICIAL)}}
    config_path = resources / 'launch.json'
    exclusive(config_path, (json.dumps(config, sort_keys=True, indent=2) + '\n').encode())
    interpreter = str(Path(sys.executable).resolve())
    runtime = process_identity(os.getpid())
    require(runtime is not None, 'unable to pin actual Python runtime')
    require(' ' not in interpreter and '\n' not in interpreter, 'unsupported interpreter shebang path')
    source = '#!' + interpreter + ' -I\n' + LAUNCHER.replace('__CONFIG_PATH__', repr(str(config_path)))
    compile(source, str(launcher), 'exec')  # Syntax check only: never execute wrapper.
    exclusive(launcher, source.encode())
    launcher.chmod(0o500)
    return {'app_path': str(app), 'bundle_identifier': BUNDLE_ID, 'copied_binary': str(binary),
            'copied_binary_sha256': sha(binary), 'launcher': str(launcher),
            'launcher_sha256': sha(launcher), 'config': str(config_path), 'config_sha256': sha(config_path),
            'info_plist': str(plist), 'info_plist_sha256': sha(plist),
            'python': interpreter, 'python_sha256': sha(interpreter),
            'python_runtime': runtime['executable'], 'python_runtime_sha256': sha(runtime['executable']),
            'launch_authorization': config['launch_authorization'], 'port': port,
            'argv': config['argv'], 'environment_without_token': environment,
            'launch_or_registration_executed': False,
            'association_boundary': 'LaunchServices/CUA app association remains to be observed after authorized launch; no registration occurs during preparation'}


def audit_generation():
    native_path = ROOT / 'evidence/player-client-native.json'
    native = json.loads(native_path.read_text())
    require(native['status'] == 'passed' and native['build']['cache_key'] == KEY
            and native['build']['binary_sha256'] == BINARY_SHA, 'visible target is not the verified normal player client')
    full_path = Path(native['full_execution_report'])
    require(sha(full_path) == native['full_execution_report_sha256'], 'full execution receipt changed')
    full = json.loads(full_path.read_text())
    build_path = Path(native['full_build_report'])
    require(sha(build_path) == native['full_build_report_sha256'], 'full native build receipt changed')
    build = json.loads(build_path.read_text())
    expected = dict(full['snapshot'])
    # The accepted client receipt explicitly distinguishes the executed runner
    # from its later report-only compactor. No production/helper/resource input
    # may change. The visible orchestrator itself is pinned separately below.
    expected['runner_sha256'] = sha(Client.__file__)
    artifact = Client.audit_build(build, expected)
    require(sha(artifact) == BINARY_SHA, 'immutable visible executable changed')
    for name, digest in SOURCE_PINS.items():
        require(sha(ROOT / name) == digest, 'frozen source changed: ' + name)
    return artifact, build, native


def fixture():
    model, _, registry = Client.official_scene()
    words = Session.PC.snapshot(position=tuple(Session.PC.raw64(v) for v in (1.5, 1., -.5)), speed=0)
    player = Session.record_bytes(words)
    data = Session.bundle_bytes(model, 0, player)
    decoded, decoded_player, first_peer = Session.parse_bundle(data, model['state_count'], model['registry'])
    require(decoded_player == player and first_peer == 1
            and Session.P.canonical_expected(decoded) == Session.P.canonical_expected(model), 'disposable fixture independently failed admission')
    directory = Path(tempfile.mkdtemp(prefix='session-', dir=WORK))
    path, token = directory / 'world.nbt', directory / 'developer-token.private'
    exclusive(path, data)
    exclusive(token, secrets.token_hex(32).encode())
    return {'directory': str(directory), 'bundle': str(path), 'bundle_sha256': Session.sha(data),
            'bundle_bytes': len(data), 'core_sha256': Session.sha(Session.P.canonical_expected(model)),
            'record_sha256': Session.sha(player), 'token_file': str(token), 'token_policy': 'exclusive0600 disposable fixture token; never printed or retained in tracked evidence',
            'initial_body': [1.5, 1., -.5], 'initial_look_raw_f32': [0, 0, 0, 0],
            'initial_clock': Session.P.clock(model), 'first_peer': 1, 'registry': registry,
            'settings': {'sensitivity': .5, 'invert_x': False, 'invert_y': False, 'smoothing': False, 'scoping': False},
            'scope': '39 fixture blocks; neutral plain Player; saved nonpristine Core avoids scene/body reinitialization'}


def java_expectations():
    words = Session.PC.snapshot(position=tuple(Session.PC.raw64(v) for v in (1.5, 1., -.5)), speed=0)
    cases = []
    for held in (2, 4, 6):
        case = Session.java_input('visible-forward-' + str(held) + '-release-five', words=words, ticks=held + 5, held=False)
        for update in case['input']['ticks'][:held]:
            update['input_f32_bits'] = ['00000000', '00000000', '3f800000']
        cases.append(case)
    collision = Session.java_input('visible-collision-jump-release', words=words, ticks=28, held=False)
    for update in collision['input']['ticks'][:13]:
        update['input_f32_bits'] = ['00000000', '00000000', '3f800000']
    collision['input']['ticks'][8]['jumping'] = True
    cases.append(collision)
    cases.append(Session.java_input('visible-opposing-forward-backward-zero-input', words=words, ticks=5, held=False))
    saved = Session.WORK
    Session.WORK = WORK / 'java-reference'
    try:
        observed, provenance = Session.observe_java(cases)
    finally:
        Session.WORK = saved
    records = [[Session.java_record(t) for t in case['ticks']] for case in observed]
    full_path = WORK / 'java-reference.full.json'
    write(full_path, {'inputs': cases, 'observations': observed, 'provenance': provenance,
                     'record_sha256': [[Session.sha(v) for v in row] for row in records]})
    summaries = []
    for case, actual, row in zip(cases, observed, records, strict=True):
        expected = [tick['expected'] for tick in actual['ticks']]
        summaries.append({'id': case['id'], 'ticks': len(row), 'last_record_sha256': Session.sha(row[-1]),
                          'horizontal_collision_ticks': [i + 1 for i,tick in enumerate(expected) if tick['flags'][1]],
                          'jump_call_observed_ticks': [i + 1 for i,tick in enumerate(actual['ticks'])
                                                       if tick['observation']['jump_before'] is not None],
                          'final_position_f64_hex': expected[-1]['position'],
                          'comparison_rule': 'match admitted initial body/support/yaw/profile and actual sampled input/tick history; nominal OS hold duration is insufficient'})
    return {'pin': '26.3', 'cases': summaries, 'unique_actual_java_steps': sum(len(r) for r in records),
            'fresh_repeated_actual_java_steps': 2 * sum(len(r) for r in records),
            'fresh_runs_equal': True, 'input_sha256': provenance['input_sha256'], 'output_sha256': provenance['output_sha256'],
            'observer_source_sha256': provenance['sources_sha256'], 'runtime': provenance['runtime'],
            'classpath_manifest_sha256': hashlib.sha256(Session.canonical(provenance['classpath'])).hexdigest(),
            'ignored_full_reference': str(full_path), 'full_reference_sha256': sha(full_path)}


def plan(artifact, setup, wrapper):
    directory = Path(setup['directory'])
    observer_grant = directory / 'observer-authorization.private.json'
    observer = [str(Path(sys.executable).resolve()), str(Path(__file__).resolve()), '--run',
                '--authorization', str(observer_grant)]
    return {'app_path_for_later_cua_binding': wrapper['app_path'], 'bundle_identifier': BUNDLE_ID,
            'immutable_source_artifact': str(artifact), 'copied_native': wrapper['copied_binary'],
            'exact_client_argv_by_phase': wrapper['argv'],
            'shell_independent_environment_without_token': wrapper['environment_without_token'],
            'private_token_source': setup['token_file'], 'token_log_policy': 'value never logged',
            'port_policy': 'fixed disposable candidate, checked by dormant launcher immediately before exec; native bind still governs races',
            'timeout_seconds': 180, 'target_executable_sha256': BINARY_SHA,
            'observer_command': observer, 'observer_authorization': str(observer_grant),
            'launch_authorization': wrapper['launch_authorization'],
            'launch_authorization_required_fields': {
                'root_orchestration_authorized': True, 'human_foreground_coordination_obtained': True,
                'human_coordination_evidence': '<actual trusted human coordination reference>',
                'preparation_sha256': '<SHA256 of final preparation receipt>',
                'target_binary_sha256': BINARY_SHA, 'app_path': wrapper['app_path'],
                'launch_mode': 'human', 'input_lane': 'manual-and-cua', 'launch_phase': 'initial',
                'timeout_seconds': 180, 'expires_at_utc': '<timezone-qualified future expiry>'},
            'observer_authorization_additional_fields': {
                'target_pid': '<actual launch receipt PID>', 'target_executable': wrapper['copied_binary'],
                'launch_phase': '<initial or restart>'},
            'input_surface': {'holds_and_free_mouse_motion': 'coordinated human physical input',
                'screenshots_escape_click_recapture_close': 'root CUA documented native app APIs after coordination',
                'hid_observation': 'read-only helper --preflight only while target is independently observed frontmost; retain actual read interval and matching helper foreground PID',
                'cg_posting': 'not authorized, never invoked', 'permission_requests': 'none'},
            'timeline': [
                {'budget_seconds': 15, 'stage': 'After explicit coordination, root binds/launches the exact app by CUA. Read launch receipt, attach observer to actual PID, retain foreground/window identity and actual screenshot.'},
                {'budget_seconds': 25, 'stage': 'With initial zero look, human briefly holds W toward dirt cube and releases. Use actual timer ticks, measured HID where available, input metadata and body/collision response. Avoid backward/strafe holds near finite floor edges.'},
                {'budget_seconds': 20, 'stage': 'Human makes one short ground jump, releases Space/W and observes landing/collision. CUA screenshot retains actual visible output. Unknown tick-input history prevents exact sequence parity claims.'},
                {'budget_seconds': 20, 'stage': 'Pause via authorized observer command; human tests first and later captured mouse motions. Record raw-degree response and screenshots. First-discard/capture internals remain explicit gaps.'},
                {'budget_seconds': 20, 'stage': 'CUA Escape, human observes pointer release, CUA primary click requests recapture, human moves again. Record actual look/body response and any inaccessible UI failure.'},
                {'budget_seconds': 20, 'stage': 'Human releases all physical keys, observer pauses and saves. CUA normal close; observer records process exit/listener refusal and exact independently encoded bundle.'},
                {'budget_seconds': 25, 'stage': 'Root updates launch grant to restart within original deadline, CUA reopens same app without --unpaused. Attach new PID observer, inspect exact saved body/look/Core, screenshot, close.'},
                {'budget_seconds': 35, 'stage': 'Reserve for target readiness, API latency and coordinated cleanup; initial receipt imposes a single total180s budget across both phases.'}],
            'api': {'transport': 'actual loopback TCP; private developer authentication request never logged',
                    'read_only': ['ping', 'discover', 'world.clock', 'player.inspect'],
                    'controlled': ['simulation.pause', 'world.save'], 'forbidden': ['simulation.step'],
                    'poll_interval_seconds': .05, 'records': 'clock-before/raw Record/clock-after with monotonic intervals; concurrent ticks are explicitly marked',
                    'controls_command': [str(Path(sys.executable).resolve()), str(Path(__file__).resolve()),
                                         '--authorization', str(observer_grant), '--command', '<snapshot|pause|resume|save|abort>'],
                    'marker_command': [str(Path(sys.executable).resolve()), str(Path(__file__).resolve()),
                                       '--authorization', str(observer_grant), '--mark', '<human or CUA observation>',
                                       '--screenshot', '<optional existing CUA screenshot path>']},
            'abort': {'trigger': ['single deadline exhausted', 'target identity/content changed', 'body approaches floor edge', 'native/API error'],
                      'behavior': 'observer records refusal and stops; root/human release keys and close through coordinated UI. Observer never posts, kills, launches or controls UI; recovery termination must be separately recorded.'},
            'covered_if_observed': ['actual visible presented scene', 'manual held/released movement and input/body response',
                'real timer collision/jump/landing', 'raw look changes', 'Escape/click response',
                'exact custom Core/Record save and paused reload', 'normal close/listener release'],
            'uncovered': GAPS + BOUNDARY[1:]}


def helper_metadata():
    binary = ROOT / 'build/visible-os-input'
    raw = ROOT / 'build/visible-os-input-read-only.json'
    info = {'path': str(HELPER), 'source_exists': HELPER.is_file(),
            'source_sha256': sha(HELPER) if HELPER.is_file() else None,
            'executed_by_this_tool': False, 'native_executable_content_verified': False,
            'contract': 'read-only preflight/plan; armed holds and relative posts require PID/path/SHA/foreground/layout/access guards; attempted posts do not prove delivery'}
    if not (HELPER.is_file() and binary.is_file() and raw.is_file()):
        info['owner_receipt'] = 'not yet available'
        return info
    require(sha(HELPER) == HELPER_SHA and sha(binary) == HELPER_BINARY_SHA, 'input helper source/executable generation changed')
    rows = json.loads(raw.read_text())
    preflight = next(row for row in rows if row['case'] == 'preflight')['output']
    require(all(row['output']['post_attempts'] == 0 and row['output']['permission_requests'] == 0 for row in rows),
            'owner helper receipt includes posting or permission requests')
    capability = ROOT / 'evidence/visible-os-input-capability.json'
    receipt = json.loads(capability.read_text())
    require(receipt['source']['sha256'] == HELPER_SHA and receipt['binary']['sha256'] == HELPER_BINARY_SHA
            and receipt['read_only_tests']['raw_receipt']['sha256'] == sha(raw), 'helper final capability generation differs')
    info.update(native_executable_content_verified=True, binary=str(binary), binary_sha256=sha(binary),
                final_capability=str(capability), final_capability_sha256=sha(capability),
                owner_receipt=str(raw), owner_receipt_sha256=sha(raw), read_only_owner_cases=len(rows),
                owner_preflight={'post_event_access': preflight['post_event_access'],
                                 'accessibility_trusted': preflight['accessibility_trusted'],
                                 'foreground_pid': preflight['foreground_pid'], 'keyboard': preflight['keyboard'],
                                 'physical_keys': preflight['physical_keys'], 'post_attempts': 0, 'permission_requests': 0,
                                 'delivery_verified': False},
                current_permission_readiness='no synthetic posting access; manual coordinated holds/mouse with read-only HID observation and documented CUA UI observation/action lane')
    return info


def prepare():
    WORK.mkdir(parents=True, exist_ok=True)
    artifact, build, native = audit_generation()
    setup = fixture()
    wrapper = package_app(artifact, setup)
    reference = java_expectations()
    artifact2, _, _ = audit_generation()
    require(artifact == artifact2, 'target generation changed during preparation')
    helper = helper_metadata()
    validation_path = WORK / 'preparation-validation.json'
    validation = None
    if validation_path.is_file():
        observed = json.loads(validation_path.read_text())
        if observed.get('tool_sha256') == sha(__file__):
            validation = {'path': str(validation_path), 'sha256': sha(validation_path),
                          'status': observed['status'], 'refusal_cases': len(observed['refusals']),
                          'libproc_self_identity_verified': observed['read_only']['identity']['pid'] > 0,
                          'frontmost_pid_read_only_sample': observed['read_only']['frontmost_pid'],
                          'boundary': 'read-only self-process/foreground queries and Python CLI refusals; no client/app/helper/UI/input/screenshot execution'}
    prepared = {'date': datetime.now(timezone.utc).isoformat(), 'status': 'prepared-visible-unverified',
                'command': 'python3 tools/test_player_visible.py --prepare', 'tool_sha256': sha(__file__),
                'target': {'artifact': str(artifact), 'binary_sha256': BINARY_SHA, 'cache_key': KEY,
                           'source_sha256': SOURCE_PINS, 'source_closure_sha256': native['snapshot']['source_manifest_sha256'],
                           'dependency_count': len(build['dependencies']),
                           'dependency_manifest_sha256': Client.Cache.native.digest(Client.Cache.native.encoded(build['dependencies'])),
                           'original_c_sha256': build['original_c_sha256'], 'transformed_c_sha256': build['transformed_c_sha256'],
                           'native_receipt_sha256': sha(ROOT / 'evidence/player-client-native.json'),
                           'resources_sha256': Client.source_snapshot()['resource_sha256']},
                'fixture': setup, 'wrapper': wrapper, 'reference': reference, 'helper': helper,
                'plan': plan(artifact, setup, wrapper),
                'authorization': {'root_orchestration_granted': False, 'human_foreground_coordination_obtained': False,
                                  'isolated_compatible_desktop_demonstrated': False, 'permission_prompt_requested': False},
                'visible_execution_ready': True, 'readiness_scope': 'manual/CUA early smoke orchestration prepared; actual run still requires root and human coordination',
                'visible_acceptance': 'unverified', 'run_observation_gaps': GAPS, 'boundary': BOUNDARY,
                'preparation_validation': validation,
                'preparation_effects': {'client_launches': 0, 'app_registrations': 0, 'ui_actions': 0,
                    'input_posts': 0, 'permission_requests': 0, 'screenshots': 0, 'native_compilations': 0,
                    'java_receiver_steps': reference['fresh_repeated_actual_java_steps']}}
    write(EVIDENCE, prepared)
    return prepared


def audit_preparation(*, allow_runtime_bundle=False):
    prepared = json.loads(EVIDENCE.read_text())
    require(prepared['tool_sha256'] == sha(__file__), 'visible preparation tool changed')
    artifact, _, _ = audit_generation()
    require(str(artifact) == prepared['target']['artifact'], 'prepared artifact changed')
    setup = prepared['fixture']
    if not allow_runtime_bundle:
        require(sha(setup['bundle']) == setup['bundle_sha256'], 'disposable fixture changed before visible run')
    token = Path(setup['token_file'])
    require(token.is_file() and token.stat().st_mode & 0o777 == 0o600 and len(token.read_bytes()) == 64,
            'disposable private token missing or permissions changed')
    require(sha(prepared['reference']['ignored_full_reference']) == prepared['reference']['full_reference_sha256'],
            'independent reference changed')
    require(helper_metadata() == prepared['helper'], 'prepared input-helper source/executable/owner receipt changed')
    wrapper = prepared['wrapper']
    for name in ('copied_binary', 'launcher', 'config', 'info_plist', 'python', 'python_runtime'):
        require(sha(wrapper[name]) == wrapper[name + '_sha256'], 'prepared wrapper changed: ' + name)
    require(plistlib.loads(Path(wrapper['info_plist']).read_bytes())['CFBundleIdentifier'] == BUNDLE_ID,
            'app bundle identity changed')
    return prepared


def frontmost_pid():
    """Read NSWorkspace.frontmostApplication; no activation or AX action."""
    ctypes.CDLL('/System/Library/Frameworks/AppKit.framework/AppKit')
    objc = ctypes.CDLL('/usr/lib/libobjc.A.dylib')
    objc.objc_getClass.argtypes = [ctypes.c_char_p]
    objc.objc_getClass.restype = ctypes.c_void_p
    objc.sel_registerName.argtypes = [ctypes.c_char_p]
    objc.sel_registerName.restype = ctypes.c_void_p
    ptr = ctypes.cast(objc.objc_msgSend, ctypes.c_void_p).value
    msg = ctypes.CFUNCTYPE(ctypes.c_void_p, ctypes.c_void_p, ctypes.c_void_p)(ptr)
    integer = ctypes.CFUNCTYPE(ctypes.c_int, ctypes.c_void_p, ctypes.c_void_p)(ptr)
    sel = lambda name: objc.sel_registerName(name.encode('ascii'))
    pool = msg(msg(objc.objc_getClass(b'NSAutoreleasePool'), sel('alloc')), sel('init'))
    try:
        workspace = msg(objc.objc_getClass(b'NSWorkspace'), sel('sharedWorkspace'))
        app = msg(workspace, sel('frontmostApplication'))
        return integer(app, sel('processIdentifier')) if app else None
    finally:
        msg(pool, sel('drain'))


def validate_grant(authorization):
    require(authorization is not None, 'observer requires a later explicit root + human authorization record')
    require(authorization.is_file() and authorization.stat().st_mode & 0o777 == 0o600,
            'observer authorization must be an existing private0600 file')
    prepared = audit_preparation(allow_runtime_bundle=True)
    grant = json.loads(authorization.read_text())
    require(grant.get('root_orchestration_authorized') is True
            and grant.get('human_foreground_coordination_obtained') is True
            and isinstance(grant.get('human_coordination_evidence'), str)
            and bool(grant['human_coordination_evidence'].strip()),
            'observer lacks explicit root authorization and coordinated human foreground evidence')
    timeout = grant.get('timeout_seconds')
    require(grant.get('preparation_sha256') == sha(EVIDENCE)
            and grant.get('target_binary_sha256') == BINARY_SHA
            and type(timeout) is int and 1 <= timeout <= 180,
            'authorization does not pin this preparation/target/bounded budget')
    require(grant.get('launch_mode') == 'human' and grant.get('input_lane') == 'manual-and-cua'
            and grant.get('app_path') == prepared['wrapper']['app_path'], 'wrong visible branch/lane/app')
    phase = grant.get('launch_phase')
    require(phase in ('initial', 'restart'), 'unsupported observer phase')
    pid = grant.get('target_pid')
    binary = Path(prepared['wrapper']['copied_binary'])
    require(type(pid) is int and pid > 0 and Path(grant.get('target_executable', '')).resolve() == binary,
            'authorization does not identify actual target PID and copied pinned executable')
    expires = datetime.fromisoformat(grant['expires_at_utc'])
    require(expires.tzinfo is not None and datetime.now(timezone.utc) < expires,
            'authorization expired or has no timezone')
    directory = Path(prepared['fixture']['directory'])
    launch_path = directory / (phase + '.launch.json')
    require(launch_path.is_file(), 'no actual app launch receipt; observer never launches the app')
    launch = json.loads(launch_path.read_text())
    require(launch['pid'] == pid and launch['binary'] == str(binary)
            and launch['binary_sha256'] == BINARY_SHA and launch['mode'] == 'human'
            and launch['preparation_sha256'] == sha(EVIDENCE), 'actual launch receipt differs from grant')
    require(launch['argv'] == prepared['wrapper']['argv'][phase]
            and launch['environment'] == prepared['wrapper']['environment_without_token'], 'actual launch policy changed')
    identity = process_identity(pid)
    require(identity is not None and Path(identity['executable']).resolve() == binary
            and [identity['started_tvsec'], identity['started_tvusec']] == launch['process_start'],
            'actual running PID/path/start-time does not match authorized launcher receipt')
    require(sha(binary) == BINARY_SHA, 'target executable changed')
    initial = json.loads((directory / 'initial.launch.json').read_text())
    deadline = min(initial['session_deadline_monotonic'], initial['started_monotonic'] + timeout)
    require(time.monotonic() < deadline, 'single visible session budget expired')
    return prepared, grant, launch, identity, deadline, expires


def enqueue(authorization, command=None, marker=None, screenshot=None):
    prepared, grant, _, identity, deadline, _ = validate_grant(authorization)
    require(command is None or command in ('snapshot', 'pause', 'resume', 'save', 'abort'), 'unknown observer command')
    require(marker is None or isinstance(marker, str) and 0 < len(marker) <= 1024, 'invalid observation marker')
    value = {'phase': grant['launch_phase'], 'monotonic_seconds': time.monotonic(),
             'target_identity': identity, 'command': command, 'declared_human_or_cua_observation': marker,
             'provenance': 'external root/manual/CUA declaration; marker alone does not prove input delivery'}
    if screenshot is not None:
        require(marker is not None and screenshot.is_file() and screenshot.stat().st_size > 0,
                'screenshot marker requires an existing external screenshot, not a frame log')
        require(screenshot.suffix.lower() in ('.png', '.jpg', '.jpeg', '.webp'), 'unsupported screenshot artifact')
        head = screenshot.read_bytes()[:24]
        require(head.startswith(b'\x89PNG\r\n\x1a\n') or head.startswith(b'\xff\xd8\xff')
                or head[:4] == b'RIFF' and head[8:12] == b'WEBP', 'screenshot has no admitted image signature')
        value['external_screenshot'] = {'path': str(screenshot.resolve()), 'sha256': sha(screenshot),
            'bytes': screenshot.stat().st_size, 'target_pid': identity['pid'], 'app_identifier': BUNDLE_ID,
            'provenance': 'provided by root CUA observation; observer did not capture this image'}
        if head.startswith(b'\x89PNG\r\n\x1a\n') and len(head) == 24:
            value['external_screenshot']['png_dimensions'] = list(struct.unpack('>II', head[16:24]))
    directory = Path(prepared['fixture']['directory']) / 'commands'
    directory.mkdir(mode=0o700, exist_ok=True)
    file = directory / (str(time.monotonic_ns()).zfill(20) + '-' + secrets.token_hex(4) + '.json')
    exclusive(file, (json.dumps(value, sort_keys=True) + '\n').encode())
    return {'status': 'queued-authorized-observation', 'file': str(file), 'session_deadline_monotonic': deadline}


class ObservedTCP:
    def __init__(self, port, token, deadline, log):
        self.socket = socket.create_connection(('127.0.0.1', port), timeout=min(1., max(.01, deadline - time.monotonic())))
        self.reader = self.socket.makefile('rb')
        self.token, self.deadline, self.log, self.count = token, deadline, log, 0

    def call(self, op, args=None):
        require(op in ('session.open', 'ping', 'discover', 'world.clock', 'player.inspect', 'simulation.pause', 'world.save'),
                'observer forbids operation outside explicit bounded contract')
        self.socket.settimeout(min(1., max(.01, self.deadline - time.monotonic())))
        request = {'id': 'visible-' + str(self.count), 'op': op, 'args': args or {}}
        started = time.monotonic()
        self.socket.sendall(Session.MCP.encode(request))
        line = self.reader.readline(2 * 1024 * 1024)
        require(line.endswith(b'\n') and self.token.encode() not in line, 'invalid TCP frame or token disclosure')
        response = json.loads(line)
        require(response.get('id') == request['id'], 'TCP response id mismatch')
        # Authentication args/token are deliberately excluded from every log.
        self.log({'kind': 'api', 'id': request['id'], 'operation': op,
                  'args': '<private authentication omitted>' if op == 'session.open' else request['args'],
                  'started_monotonic': started, 'finished_monotonic': time.monotonic(), 'response': response})
        self.count += 1
        require(response.get('ok') is True, 'actual API refused ' + op)
        return response['result']

    def close(self):
        self.reader.close()
        self.socket.close()


def inspect_record(value):
    require(value['format'] == Session.NAMESPACE, 'wrong public Record format')
    record = bytes(value['nbt_bytes'])
    motion, raw_look = Session.PR.decode(record)
    words, dimension = Session.PC.parse_snapshot(motion)
    return record, {'record_sha256': Session.sha(record), 'motion_words_u32': list(words),
                    'raw_look_words_u32': list(Session.PR.look_words(raw_look)), 'dimension': dimension,
                    'position_f64': [Session.PC.f64(b) for b in Session.PC.bits64(words[:6])],
                    'input_f32_hex': [f'{w:08x}' for w in words[30:33]],
                    'collision_flags': list(words[26:30])}


def guarded_run(authorization):
    prepared, grant, launch, identity, deadline, expires = validate_grant(authorization)
    phase, pid = grant['launch_phase'], identity['pid']
    directory = Path(prepared['fixture']['directory'])
    full_path, report_path = directory / (phase + '.observations.jsonl'), directory / (phase + '.observer.json')
    fd = os.open(full_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    log_file = os.fdopen(fd, 'w', buffering=1)
    token = Path(prepared['fixture']['token_file']).read_text('ascii')
    def log(value):
        physical = json.dumps(value, sort_keys=True)
        require(token not in physical, 'observer refuses logging private token')
        log_file.write(physical + '\n')
    report = {'status': 'observed-visible-session-unreviewed', 'phase': phase, 'target_identity': identity,
              'tool_sha256': sha(__file__), 'preparation_sha256': sha(EVIDENCE),
              'authorization_sha256': sha(authorization), 'binary_sha256': BINARY_SHA,
              'full_observations': str(full_path), 'process_exit_observed': False,
              'save_verified': False, 'observer_launched_or_ui_controlled': False,
              'input_posts': 0, 'permission_requests': 0, 'capture_first_discard_verified': False,
              'direct_screenshot_calls': 0, 'samples': 0, 'hid_samples': 0,
              'observer_started_monotonic': time.monotonic(), 'external_screenshots': [],
              'deadline_monotonic': deadline, 'boundary': BOUNDARY + GAPS[1:]}
    client, consumed, first_clock, first_record = None, set(), None, None
    try:
        while time.monotonic() < deadline and datetime.now(timezone.utc) < expires:
            actual = process_identity(pid)
            if actual is None:
                report['process_exit_observed'] = True
                break
            require(actual == identity and sha(prepared['wrapper']['copied_binary']) == BINARY_SHA,
                    'running target identity/content changed')
            if client is None:
                try:
                    client = ObservedTCP(prepared['wrapper']['port'], token, deadline, log)
                except (ConnectionRefusedError, TimeoutError):
                    time.sleep(min(.05, max(0., deadline - time.monotonic())))
                    continue
                client.call('session.open', {'mode': 'developer', 'token': token})
                report['session_identity'] = client.call('ping')
                discovery = client.call('discover')
                require({op['name'] for op in discovery['operations']} == Client.EXPECTED_OPERATIONS,
                        'actual Session catalog differs from verified18 operations')
                log({'kind': 'catalog', 'actual': discovery})
            started = time.monotonic()
            before = client.call('world.clock')
            record, decoded = inspect_record(client.call('player.inspect'))
            after = client.call('world.clock')
            if first_clock is None:
                first_clock, first_record = before, record
                if phase == 'restart':
                    saved = json.loads((directory / 'initial.observer.json').read_text())
                    require(before == saved['saved_clock'] and before['paused'] and record.hex() == saved['saved_record_hex'],
                            'actual paused restart changed exact saved Core/Record')
                    report['restart_exact_saved_state_observed'] = True
                    require(sha(prepared['fixture']['bundle']) == saved['saved_bundle_sha256'], 'restart altered durable bundle')
            sample = {'kind': 'sample', 'started_monotonic': started, 'finished_monotonic': time.monotonic(),
                      'clock_before': before, 'clock_after': after, 'clock_stable': before == after,
                      'record_hex': record.hex(), 'decoded': decoded}
            log(sample)
            report['samples'] += 1
            if before['paused']:
                require(before == after, 'paused API sampling advanced Core')
            x, _, z = decoded['position_f64']
            require(-2.5 <= x <= 2.5 and -2.5 <= z <= 2.5, 'body approaches finite floor edge; root/human must release and close')
            # Read HID only after a separate read-only foreground check. The
            # helper rechecks foreground during its own read; retain keys only
            # when both samples match the verified target. No arm/post route.
            front = frontmost_pid()
            log({'kind': 'foreground', 'monotonic_seconds': time.monotonic(), 'pid': front})
            if front == pid:
                require(sha(prepared['helper']['binary']) == HELPER_BINARY_SHA, 'read-only helper changed')
                hid_start = time.monotonic()
                checked = subprocess.run([prepared['helper']['binary'], '--preflight'],
                    capture_output=True, text=True, timeout=min(1., max(.01, deadline - time.monotonic())),
                    env={'PATH': '/usr/bin:/bin', 'HOME': str(Path.home())})
                require(checked.returncode == 0 and not checked.stderr, 'read-only HID helper refused')
                hid = json.loads(checked.stdout)
                require(hid['post_attempts'] == 0 and hid['permission_requests'] == 0 and hid['event_objects_created'] == 0,
                        'preflight violated zero-post boundary')
                if hid['foreground_pid'] == pid and process_identity(pid) == identity:
                    require(hid['keyboard']['input_source']['id'] == prepared['helper']['owner_preflight']['keyboard']['input_source']['id']
                            and hid['keyboard']['layout_source']['id'] == prepared['helper']['owner_preflight']['keyboard']['layout_source']['id'],
                            'actual keyboard identity changed; stop coordinated input')
                    log({'kind': 'hid-read-only', 'started_monotonic': hid_start,
                         'finished_monotonic': time.monotonic(), 'actual': hid,
                         'boundary': 'human held-state readout availability must be established by actual holds; no OS delivery/capture proof'})
                    report['hid_samples'] += 1
                else:
                    log({'kind': 'hid-discarded-foreground-changed', 'monotonic_seconds': time.monotonic()})
            commands = directory / 'commands'
            for file in sorted(commands.glob('*.json')) if commands.exists() else []:
                if str(file) in consumed:
                    continue
                value = json.loads(file.read_text())
                if value['phase'] != phase:
                    continue
                require(value['target_identity'] == identity, 'command target identity changed')
                consumed.add(str(file))
                image = value.get('external_screenshot')
                if image is not None:
                    require(sha(image['path']) == image['sha256'], 'external screenshot changed after declared observation')
                    report['external_screenshots'].append(image)
                log({'kind': 'declared-stage', 'file': str(file), 'file_sha256': sha(file), 'value': value})
                command = value['command']
                if command in ('pause', 'resume'):
                    client.call('simulation.pause', {'paused': command == 'pause'})
                elif command == 'save':
                    clock = client.call('world.clock')
                    require(clock['paused'], 'release physical input and pause before save observation')
                    saved_record, _ = inspect_record(client.call('player.inspect'))
                    require(client.call('world.clock') == clock, 'save projection clock changed')
                    response = client.call('world.save')
                    require(response.get('published') is True and response.get('durable') is True
                            and response.get('status') == 'durable', 'normal save did not publish durably')
                    data = Path(prepared['fixture']['bundle']).read_bytes()
                    model, _, _ = Client.official_scene()
                    require(clock['revision'] == 47 and clock['pending'] == 0 and clock['daylight'] is True
                            and clock['tick'] == clock['day_time'], 'visible lane changed prescribed Core scene')
                    model.update({k: clock[k] for k in ('tick', 'day_time', 'paused', 'daylight', 'revision')})
                    highwater = response['peer_highwater']
                    expected = Session.bundle_bytes(model, highwater, saved_record)
                    require(data == expected and response['bytes'] == len(expected), 'exact independent Core/Record save differs')
                    require(client.call('world.clock') == clock and inspect_record(client.call('player.inspect'))[0] == saved_record,
                            'mouse/input changed paused save observation; exact comparison refused')
                    Session.parse_bundle(data, model['state_count'], model['registry'])
                    report.update(save_verified=True, saved_bundle_sha256=Session.sha(data),
                        saved_record_hex=saved_record.hex(), saved_record_sha256=Session.sha(saved_record),
                        saved_core_sha256=Session.sha(Session.P.canonical_expected(model)), saved_clock=clock,
                        saved_bundle_bytes=len(data), save_response=response)
                    exclusive(directory / (phase + '.saved.nbt'), data)
                elif command == 'abort':
                    report['status'] = 'observer-aborted-root-must-release-close'
                    break
            if report['status'].startswith('observer-aborted'):
                break
            time.sleep(min(max(0., .05 - (time.monotonic() - started)), max(0., deadline - time.monotonic())))
        if not report['process_exit_observed'] and not report['status'].startswith('observer-aborted'):
            report['status'] = 'observer-deadline-root-must-release-close'
    except Exception as error:
        # No token, auth request or inherited environment is placed in errors.
        if process_identity(pid) is None:
            report['process_exit_observed'] = True
            report['transport_interrupted_on_exit'] = str(error).replace(token, '<private token redacted>')
        else:
            report['status'] = 'observer-error-root-must-release-close'
            report['diagnostic'] = str(error).replace(token, '<private token redacted>')
    finally:
        if client is not None:
            report['tcp_requests'] = client.count
            try:
                client.close()
            except OSError:
                pass
        log_file.close()
    if report['process_exit_observed']:
        try:
            refused = socket.create_connection(('127.0.0.1', prepared['wrapper']['port']), timeout=.2)
        except ConnectionRefusedError:
            report['listener_refused_after_exit'] = True
        except OSError:
            report['listener_refused_after_exit'] = False
        else:
            refused.close()
            report['listener_refused_after_exit'] = False
    report['observed_exit_code'] = None  # App was launched elsewhere, not our child.
    report['observer_finished_monotonic'] = time.monotonic()
    report['full_observations_sha256'] = sha(full_path)
    for suffix in ('stdout', 'stderr'):
        path = directory / (phase + '.' + suffix)
        if path.is_file():
            require(token.encode() not in path.read_bytes(), 'client log disclosed private token')
            report[suffix] = {'path': str(path), 'bytes': path.stat().st_size, 'sha256': sha(path)}
    report['frame_descriptions'] = len([e for e in Client.events(directory / (phase + '.stdout')) if e.get('event') == 'client.frame'])
    report['frame_log_is_screenshot'] = False
    exclusive(report_path, (json.dumps(report, sort_keys=True, indent=2) + '\n').encode())
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument('--prepare', action='store_true')
    mode.add_argument('--audit', action='store_true')
    mode.add_argument('--run', action='store_true')
    mode.add_argument('--command', choices=('snapshot', 'pause', 'resume', 'save', 'abort'))
    mode.add_argument('--mark')
    parser.add_argument('--authorization', type=Path)
    parser.add_argument('--screenshot', type=Path)
    args = parser.parse_args()
    try:
        require(args.screenshot is None or args.mark is not None, '--screenshot needs an external CUA observation marker')
        if args.command is not None or args.mark is not None:
            observed = enqueue(args.authorization, args.command, args.mark, args.screenshot)
            print(json.dumps(observed))
            return 0
        if args.run:
            observed = guarded_run(args.authorization)
            print(json.dumps({k: observed[k] for k in ('status', 'phase', 'samples', 'hid_samples',
                'process_exit_observed', 'save_verified', 'full_observations', 'full_observations_sha256')}))
            return int(observed['status'].startswith('observer-'))
        prepared = audit_preparation() if args.audit else prepare()
        print(json.dumps({'status': prepared['status'], 'evidence': str(EVIDENCE),
                          'visible_execution_ready': prepared['visible_execution_ready'],
                          'visible_acceptance': prepared['visible_acceptance'],
                          'app_path': prepared['wrapper']['app_path'], 'target_binary_sha256': BINARY_SHA}))
        return 0
    except (AssertionError, ValueError, KeyError, OSError) as error:
        print('visible preparation refused: ' + str(error), file=__import__('sys').stderr)
        return 1


if __name__ == '__main__':
    raise SystemExit(main())
