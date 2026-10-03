#!/usr/bin/env python3
"""Standalone owned-runtime integration; Java supplies plain Player.aiStep results.

--prepare performs independent Java observations and ordinary checking only.
The native lane requires an explicit lead build slot. Python orchestrates fixtures,
reads raw NBT, and computes exact look expectations; gameplay executes in Bend.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import signal
import struct
import subprocess
import sys
import time

import build_native as Build
import test_nbt as N
import test_world_codec as WorldNBT
import test_player_codec as MotionNBT
import test_player_record as RecordNBT
import test_player_controls as Controls
import test_player_input as Keyboard
import test_player_look as Look
import test_mouse_input as Mouse
import test_support_world as Support
from reference_inventory import ROOT, JAVA, canonical, fingerprint
from reference_block_probe import verified_classpath
from reference_travel_probe import bits, fbits
from test_geometry import run, sha
from test_player_tick import parse as parse_player
from test_travel import parse as parse_body
from test_travel_world import world_blocks

ENTRY = ROOT / 'tests/player_runtime.bend'
BEND = Path('/Users/chuah/.bend/bin/bend')
WORK = ROOT / 'build/player-runtime'
BINARY = WORK / 'tests'
TABLE = ROOT / 'generated/reference_mth_sin.f32'
REFERENCE = ROOT / 'evidence/player-runtime-reference.json'
EVIDENCE = ROOT / 'evidence/player-runtime-verification.json'
BINDINGS = [119, 115, 97, 100, 32, 340, 341]
SUPPORT_SHA = 'a2e42fb06cab36408e7631e8ff3b9e61793696d4b049592d3ce137f69fa3b381'
KINDS = ('body', 'metadata', 'support', 'controls', 'view', 'error', 'record', 'world')


def bounded_run(argv, *, timeout=600, required=True):
    started = time.monotonic()
    process = subprocess.Popen(list(map(str, argv)), cwd=ROOT, text=True,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               start_new_session=True)
    print(json.dumps({'process_group': process.pid, 'timeout_seconds': timeout,
                      'command': list(map(str, argv))}), flush=True)
    timed_out = False
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        os.killpg(process.pid, signal.SIGTERM)
        try:
            stdout, stderr = process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            stdout, stderr = process.communicate()
    result = {'command': list(map(str, argv)), 'pid': process.pid,
              'exit_code': process.returncode, 'stdout': stdout, 'stderr': stderr,
              'timed_out': timed_out, 'seconds': round(time.monotonic() - started, 6)}
    if required and (timed_out or process.returncode):
        raise RuntimeError(json.dumps(compact(result), sort_keys=True))
    return result


def write_json(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, sort_keys=True, indent=2) + '\n')


def compact(report):
    result = dict(report)
    for key in ('stdout', 'stderr'):
        if key not in result:
            continue
        text = result.pop(key)
        result[key + '_bytes'] = len(text.encode())
        result[key + '_sha256'] = hashlib.sha256(text.encode()).hexdigest()
        if key == 'stderr' and text:
            result[key + '_excerpt'] = text[-2000:]
    argv = list(result.get('command', []))
    if '-cp' in argv:
        index = argv.index('-cp') + 1
        path = argv[index]
        result['classpath_argument'] = {'sha256': hashlib.sha256(path.encode()).hexdigest(), 'entries': len(path.split(os.pathsep))}
        argv[index] = '<classpath retained in ignored full reference>'
        result['command'] = argv
    return result


def words(raw):
    if isinstance(raw, str):
        return [int(raw[:8], 16), int(raw[8:], 16)]
    return [part for value in raw for part in words(value)]


def unsigned(value):
    return int(value, 16) if isinstance(value, str) else int(value) & 0xffffffff


def command(identity, op, *fields):
    return '|'.join(map(str, [identity, op, *fields]))


def state_words(state):
    return [*words(state['position']), *words(state['box']), *words(state['velocity']),
            unsigned(state['width_f32_bits']), unsigned(state['height_f32_bits']),
            *map(int, state['flags']), *metadata_words(state)]


def metadata_words(state):
    return [*map(unsigned, state['input_f32_bits']), int(state['jumping']),
            unsigned(state['jump_delay']), unsigned(state['jump_trigger']),
            int(state['needs_sync']), unsigned(state['stored_speed_f32_bits']),
            unsigned(state['head_yaw_f32_bits'])]


def seed_controller(mask=0, look=(0, 0, 0, 0), mouse=(0, 0, 0, 0, True), options=None):
    return Controls.controller(mask, look, mouse, options or Controls.DEFAULT_OPTIONS)


def device_command(identity, controller):
    return command(identity, 'controls', controller['buttons'],
                   *Mouse.state_words(controller['mouse']), *Mouse.options_words(controller['options']))


def packet_command(identity, frame):
    fields = [int(frame['focused']), int(frame['captured'])]
    for tag, a, b, captured, d, e in frame['actions']:
        assert captured or tag == 0, 'harness packets use captured platform events'
        fields += [0 if tag == 1 else 1 if tag == 2 else 2, a, b]
    return command(identity, 'packet', *fields)


def cases(records):
    result = []

    def add(label, masks, *, edits=None, **changes):
        data = {'position': list(map(bits, [.5, 1., -2.5])), 'velocity': [bits(0.)] * 3,
                'grounded': True, 'input_f32_bits': [fbits(.5), fbits(.25), fbits(-.25)],
                'jumping': False, 'sprinting': False, 'no_gravity': False,
                'discard_friction': False, 'yaw_f32_bits': fbits(0.),
                'movement_speed': bits(.1), 'gravity': bits(.08),
                'friction_modifier': bits(1.), 'air_drag_modifier': bits(1.),
                'step_height': bits(.6), 'jump_strength': bits(.42),
                'jump_delay': 0, 'jump_trigger': 3, 'needs_sync': False,
                'stored_speed_f32_bits': fbits(.7), 'head_yaw_f32_bits': fbits(-90.),
                'world_blocks': world_blocks(),
                'initial_cache': {'main': None, 'on_ground_no_blocks': False}}
        data.update(changes)
        updates = []
        for index, mask in enumerate(masks):
            sample = list(map(int, records['tick', mask].split('|')))
            assert len(sample) == 4 and sample[0] == mask
            update = {'input_f32_bits': [f'{sample[1]:08x}', fbits(0.), f'{sample[2]:08x}'],
                      'jumping': bool(mask & 16), 'sprinting': bool(mask & 64)}
            if edits and index in edits:
                update['world_edits'] = edits[index]
            updates.append(update)
        data['ticks'] = updates
        result.append({'id': 'runtime-' + label, 'operation': 'player_ai_step',
                       'input': data, 'masks': masks})

    add('held-forward-release', [1] * 8 + [0] * 4)
    add('held-jump', [17] * 24)
    add('diagonal-cancel', [5] * 6 + [15] * 2 + [0] * 2,
        position=list(map(bits, [-1.5, 1., -.5])), yaw_f32_bits=fbits(45.))
    add('dirt-step', [0] * 6, position=list(map(bits, [.5, 1., 1.5])),
        velocity=list(map(bits, [.8, -.1, 0.])), step_height=bits(1.))
    half = struct.unpack('>f', bytes.fromhex('3f19999a'))[0] / 2
    add('fully-blocked', [0] * 6, position=list(map(bits, [1. - half, 1., 1.5])),
        velocity=list(map(bits, [.8, 0., 0.])), step_height=bits(0.))
    add('negative-counters', [16, 0, 16, 0], position=list(map(bits, [.5, 1., .5])),
        jump_delay=-1, jump_trigger=-2)
    add('due-floor-edits', [0] * 6, position=list(map(bits, [.5, 1., .5])),
        edits={0: [{'position': [0, 0, 0], 'identifier': 'minecraft:air'}],
               2: [{'position': [0, 0, 0], 'identifier': 'minecraft:stone'}],
               4: [{'position': [0, 0, 0], 'identifier': 'minecraft:dirt'}]})
    add('due-collision-edits', [0] * 5, position=list(map(bits, [.5, 1., -.5])),
        velocity=list(map(bits, [.8, 0., 0.])), step_height=bits(.6),
        edits={0: [{'position': [1, 1, -1], 'identifier': 'minecraft:stone'}],
               1: [{'position': [1, 1, -1], 'identifier': 'minecraft:air'}]})
    return result


def java_source():
    source = Support.java_source().replace('ReferenceSupportWorldProbe', 'ReferencePlayerRuntimeProbe')
    marker = '   inputs(p,update.getAsJsonObject());'
    assert source.count(marker) == 1
    # Only the fixture level changes between calls. Actual Player.aiStep,
    # Entity movement, support and sample methods still execute untouched.
    replacement = r'''   JsonObject change=update.getAsJsonObject();
   if(change.has("world_edits"))for(JsonElement edit:change.getAsJsonArray("world_edits")){
    JsonObject b=edit.getAsJsonObject();JsonArray at=b.getAsJsonArray("position");
    BlockPos where=new BlockPos(at.get(0).getAsInt(),at.get(1).getAsInt(),at.get(2).getAsInt());
    Block block=BuiltInRegistries.BLOCK.getValue(Identifier.parse(b.get("identifier").getAsString()));
    if(block==Blocks.AIR)level.blocks.remove(where);
    else if(block==Blocks.STONE||block==Blocks.DIRT||block==Blocks.OAK_PLANKS)level.blocks.put(where,block.defaultBlockState());
    else throw new IllegalArgumentException("Unsupported runtime fixture edit");
   }
   inputs(p,update.getAsJsonObject());'''
    return source.replace(marker, replacement)


def prepare():
    WORK.mkdir(parents=True, exist_ok=True)
    assert sha(ROOT / 'src/support_world.bend') == SUPPORT_SHA
    records, keyboard_provenance = Keyboard.oracle()
    incoming_cases = cases(records)
    jars, release = verified_classpath()
    derived = java_source()
    sources = [('ReferenceMovementProbe', Support.MOVE_SOURCE),
               ('ReferenceDirectMovementProbe', Support.DIRECT_SOURCE),
               ('ReferenceTravelProbe', Support.TRAVEL_SOURCE),
               ('ReferencePlayerTickProbe', Support.TICK_SOURCE),
               ('ReferenceSupportProbe', Support.SUPPORT_SOURCE),
               ('ReferencePlayerRuntimeProbe', derived)]
    paths = []
    for name, source in sources:
        path = WORK / (name + '.java')
        path.write_text(source)
        paths.append(path)
    cp = os.pathsep.join(map(str, jars))
    build = run([JAVA.with_name('javac'), '-cp', cp, '-d', WORK, *paths])
    incoming, outgoing = WORK / 'input.jsonl', WORK / 'output.jsonl'
    incoming.write_text(''.join(canonical(case).decode() + '\n' for case in incoming_cases))
    execution = run([JAVA, '-cp', str(WORK) + os.pathsep + cp,
                     'ReferencePlayerRuntimeProbe', incoming, outgoing])
    observed = list(map(json.loads, outgoing.read_text().splitlines()))
    assert [v['id'] for v in observed] == [v['id'] for v in incoming_cases]
    combined = [{**given, **actual} for given, actual in zip(incoming_cases, observed, strict=True)]
    for case in combined:
        assert len(case['ticks']) == len(case['masks'])
        for tick in case['ticks']:
            assert tick['observation']['full_player_ai_step_executed']
            assert len(tick['observation']['support_calls']) == 1
            assert tick['observation']['support_calls'][0]['movement'] is not None
    full = WORK / 'reference.full.json'
    full_value = {'cases': combined, 'keyboard': {f'{kind}:{mask}': value for (kind, mask), value in records.items()},
                  'full_commands_and_keyboard_provenance': {'java_build': build, 'java_execution': execution, 'keyboard': keyboard_provenance}}
    write_json(full, full_value)
    generation = MotionNBT.imports([ENTRY, ROOT / 'src/player_runtime.bend'])
    checks = [compact(run([BEND, path, '--check-only'])) for path in (ROOT / 'src/player_runtime.bend', ENTRY)]
    helper_hashes = {str(path.relative_to(ROOT)): sha(path) for path in
                     (ROOT / 'tools/test_support_world.py', ROOT / 'tools/reference_player_tick_probe.py',
                      ROOT / 'tools/reference_support_probe.py', ROOT / 'tools/reference_travel_probe.py',
                      ROOT / 'tools/reference_movement_probe.py', ROOT / 'tools/test_player_input.py',
                      ROOT / 'tools/test_player_controls.py', ROOT / 'tools/test_player_look.py',
                      ROOT / 'tools/test_mouse_input.py', ROOT / 'tools/test_player_record.py',
                      ROOT / 'tools/test_player_codec.py', ROOT / 'tools/test_world_codec.py', ROOT / 'tools/test_nbt.py')}
    evidence = {'schema_version': 1, 'status': 'reference_and_ordinary_passed_native_pending',
                'pin': '26.3', 'actual_player_ai_step_calls': sum(len(c['ticks']) for c in combined),
                'cases': [{'id': c['id'], 'ticks': len(c['ticks']),
                           'scheduled_edits': sum(len(t.get('world_edits', [])) for t in c['input']['ticks'])} for c in combined],
                'full_reference': fingerprint(full), 'full_reference_cases_sha256': hashlib.sha256(canonical(combined)).hexdigest(),
                'java': {'build': compact(build), 'execution': compact(execution),
                         'sources_sha256': {name: hashlib.sha256(source.encode()).hexdigest() for name, source in sources},
                         'input_sha256': sha(incoming), 'output_sha256': sha(outgoing),
                         'classpath': [fingerprint(path) for path in jars], 'runtime': fingerprint(JAVA), 'release': release},
                'keyboard': {**keyboard_provenance, 'build': compact(keyboard_provenance['build']),
                             'runs': [compact(report) for report in keyboard_provenance['runs']]},
                'checks': checks, 'sources_sha256': generation,
                'oracle_helpers_sha256': helper_hashes, 'table': fingerprint(TABLE),
                'scope': 'plain neutral Player.aiStep in declared 39block scene, physical buttons sampled anew each tick; no LocalPlayer override or OS capture'}
    assert generation == MotionNBT.imports([ENTRY, ROOT / 'src/player_runtime.bend'])
    write_json(REFERENCE, evidence)
    return evidence, full_value


def load_reference():
    summary = json.loads(REFERENCE.read_text())
    full = WORK / summary['full_reference']['file']
    assert fingerprint(full) == summary['full_reference']
    assert MotionNBT.imports([ENTRY, ROOT / 'src/player_runtime.bend']) == summary['sources_sha256']
    assert fingerprint(TABLE) == summary['table']
    jars, _ = verified_classpath()
    assert [fingerprint(path) for path in jars] == summary['java']['classpath']
    assert fingerprint(JAVA) == summary['java']['runtime']
    for path, expected in summary['oracle_helpers_sha256'].items():
        assert sha(ROOT / path) == expected, ('oracle helper changed', path)
    full_value = json.loads(full.read_text())
    assert hashlib.sha256(java_source().encode()).hexdigest() == summary['java']['sources_sha256']['ReferencePlayerRuntimeProbe']
    records = {(kind, int(mask)): value for key, value in full_value['keyboard'].items() for kind, mask in [key.split(':')]}
    given = [{k: v for k, v in case.items() if k != 'ticks'} for case in full_value['cases']]
    assert given == cases(records), 'fixture inputs changed; prepare fresh observations'
    assert hashlib.sha256(canonical(full_value['cases'])).hexdigest() == summary['full_reference_cases_sha256']
    return summary, full_value


def verify_receipt(native, sources):
    assert native['sources_sha256'] == sources
    assert fingerprint(BEND) == native['bend']
    cache = ROOT / 'build/native-cache'
    record = Build._verified(cache / 'entries' / native['cache_key'], native['cache_key'])
    assert record is not None, 'native cache failed content verification'
    assert native['dependencies'] == record['key_data']['dependencies']
    for key in ('binary_sha256', 'binary_bytes', 'emitted_c_sha256', 'compiler'):
        assert native[key] == record[key], ('receipt differs from keyed generation', key)
    artifact = cache / 'artifacts' / record['binary_sha256'] / 'program'
    assert Path(native['artifact']) == artifact
    emitted = cache / 'sources' / record['key_data']['prekey'] / 'generated.c'
    assert sha(emitted) == record['emitted_c_sha256']
    assert Look.verify_build(native) == artifact  # Includes Base/runtime/SDK/toolchain lookup/content.
    return artifact


def parse(stdout):
    reports = {}
    for line in stdout.splitlines():
        identity, kind, *fields = line.split('|')
        assert kind in (*KINDS, 'status') and (identity, kind) not in reports, line[:200]
        reports[identity, kind] = fields
    identities = {identity for identity, kind in reports}
    result = {}
    for identity in identities:
        assert all((identity, kind) in reports for kind in KINDS), identity
        item = {kind: reports[identity, kind] for kind in KINDS}
        body = item['body'][0].split(',')
        metadata = item['metadata'][0].split(',')
        item['body_value'] = parse_body('|'.join([identity, 'body', *body]))[1]
        item['player'] = parse_player('|'.join([identity, 'state', *body, *metadata]))[1]
        item['body_words'] = list(map(int, body))
        item['metadata_words'] = list(map(int, metadata))
        item['control_words'] = list(map(int, item['controls'][0].split(',')))
        sw = list(map(int, item['support'][0].split(',')))
        item['support_value'] = {'main': [v if v < 2**31 else v - 2**32 for v in sw[1:4]] if sw[0] else None,
                                 'on_ground_no_blocks': bool(sw[4])}
        world_bytes = bytes.fromhex(item['world'][0])
        root = N.parse(world_bytes)
        count = dict(root.value.payload)[N.text('state_count')].payload
        item['world_value'] = WorldNBT.validate(root, count, 'runtime-fixture')
        item['world_sha256'] = hashlib.sha256(world_bytes).hexdigest()
        if item['record'][0] != 'invalid':
            look = item['control_words'][1:5]
            view = list(map(int, item['view'][0].split(',')))
            snapshot = tuple([*map(int, body), *map(int, metadata), *view, *sw])
            # Independent physical NBT encoding, including raw signed zeros.
            motion = RecordNBT.physical_motion(snapshot, 'minecraft:overworld')
            expected = RecordNBT.encode(motion, RecordNBT.look_bytes(look))
            assert bytes.fromhex(item['record'][0]) == expected, ('record raw bytes', identity)
        item['status'] = reports.get((identity, 'status'), [None])[0]
        result[identity] = item
    return result


def run_native(binary, label, commands):
    before = sha(binary)
    report = run([binary, '--gpu', 'off', TABLE, *commands], timeout=120)
    assert sha(binary) == before
    directory = WORK / 'native'
    directory.mkdir(exist_ok=True)
    output = directory / (label + '.stdout')
    output.write_text(report['stdout'])
    return parse(report['stdout']), {**compact(report), 'raw_output': fingerprint(output), 'operations': len(commands)}


def setup(case):
    initial = case['ticks'][0]['observation']['initial']
    original = {**initial, **{key: case['input'][key] for key in
                ('input_f32_bits', 'jumping', 'jump_delay', 'jump_trigger', 'needs_sync', 'stored_speed_f32_bits', 'head_yaw_f32_bits')}}
    return [command('seed-body', 'body', *state_words(initial)[:30]),
            command('seed-metadata', 'metadata', *metadata_words(original)),
            command('seed-look', 'look', unsigned(case['input']['yaw_f32_bits']), 0, 0, 0),
            command('seed-project', 'packet', 1, 1),
            command('seed-settings', 'settings', 0, unsigned(case['ticks'][0]['observation']['attributes']['maximum_f32_bits']))]


def queue_commands(case):
    commands, index = [], 0
    for offset, update in enumerate(case['input']['ticks']):
        for edit in update.get('world_edits', []):
            material = ['minecraft:air', 'minecraft:stone', 'minecraft:dirt', 'minecraft:oak_planks'].index(edit['identifier'])
            commands.append(command('queue-' + str(index), 'edit', offset + 2, index,
                                    *map(unsigned, edit['position']), material))
            index += 1
    return commands


def cell(world, position):
    x, y, z = position
    key = 'minecraft:overworld/' + '/'.join(str((v // 16) & 0xffffffff) for v in position)
    section = next(s for s in world['sections'] if s['key'] == key)
    return section['cells'][(x % 16) + 16 * (z % 16) + 256 * (y % 16)]


def whole_equal(a, b, *, exclude=()):
    for kind in KINDS:
        if kind not in exclude:
            assert a[kind] == b[kind], ('rollback/retention field', kind, a[kind][:1], b[kind][:1])


def verify_cases(binary, cases):
    reports, tick_count = [], 0
    for case in cases:
        commands = setup(case) + queue_commands(case)
        previous = 0
        for index, mask in enumerate(case['masks']):
            for bit, code in enumerate(BINDINGS):
                if (mask ^ previous) & (1 << bit):
                    commands.append(command(f'key-{index}-{bit}', 'key', code, int(bool(mask & (1 << bit)))))
            if previous and not mask:
                commands.append(command('release-' + str(index), 'release'))
            commands.append(command('tick-' + str(index), 'step'))
            previous = mask
        actual, report = run_native(binary, case['id'], commands)
        seed = actual['seed-settings']['world_value']
        palette = list(map(int, actual['seed-settings']['view'][1].split(',')))
        edit_count = 0
        for index, expected in enumerate(case['ticks']):
            item = actual['tick-' + str(index)]
            assert item['player'] == expected['expected'], (case['id'], index, expected['expected'], item['player'])
            assert item['support_value'] == expected['observation']['support_cache'], (case['id'], index, item['support_value'])
            assert item['control_words'][0] == case['masks'][index]
            world = item['world_value']
            assert world['tick'] == seed['tick'] + index + 1
            assert world['day_time'] == seed['day_time'] + index + 1
            assert world['paused'] and world['daylight'] == seed['daylight']
            for edit in case['input']['ticks'][index].get('world_edits', []):
                edit_count += 1
                material = ['minecraft:air', 'minecraft:stone', 'minecraft:dirt', 'minecraft:oak_planks'].index(edit['identifier'])
                assert cell(world, edit['position']) == palette[material]
            assert world['revision'] == seed['revision'] + edit_count
            assert len(world['pending']) == sum(len(t.get('world_edits', [])) for t in case['input']['ticks'][index + 1:])
            assert item['error'] == ['none']
            tick_count += 1
        # RT.advance itself must interleave Core and physics; closed default driver.
        if case['id'].endswith(('due-floor-edits', 'due-collision-edits')):
            bulk, bulk_report = run_native(binary, case['id'] + '-advance',
                                          setup(case) + queue_commands(case) + [command('final', 'advance', len(case['ticks']))])
            whole_equal(actual['tick-' + str(len(case['ticks']) - 1)], bulk['final'])
            reports.append({'case': case['id'], 'bulk_matches_individual_steps': True, 'run': bulk_report})
        reports.append({'case': case['id'], 'ticks': len(case['ticks']), 'scheduled_edits': edit_count, 'run': report})
    return reports, tick_count


def verify_packets(binary, records):
    initial = seed_controller(1, [unsigned(fbits(v)) for v in (10., 20., 30., 40.)],
                              [int(bits(5.), 16), int(bits(6.), 16), 0, 0, True])
    frames = [Controls.packet([Controls.look(unsigned(fbits(4.)), unsigned(fbits(-2.)))]),
              Controls.packet([Controls.key(97, True), Controls.look(unsigned(fbits(4.)), unsigned(fbits(-2.)))]),
              Controls.packet([Controls.RELEASE, Controls.look(unsigned(fbits(100.)), unsigned(fbits(100.)))]),
              Controls.packet([Controls.look(unsigned(fbits(2.)), unsigned(fbits(3.)))]),
              Controls.packet([Controls.key(100, True), Controls.look(0x7fc01234, 0)]),
              Controls.packet([Controls.look(unsigned(fbits(.5)), unsigned(fbits(.25)))])]
    commands = [device_command('devices', initial), command('angles', 'look', *initial['look'])]
    expected = []
    current = initial
    for index, frame in enumerate(frames):
        output, current, delta = Controls.apply_expected(current, BINDINGS, frame, records)
        expected.append((output, copy.deepcopy(current)))
        commands.append(packet_command('packet-' + str(index), frame))
    actual, report = run_native(binary, 'packets', commands)
    for index, (expected_output, expected_controller) in enumerate(expected):
        item = actual['packet-' + str(index)]
        assert item['control_words'] == Controls.controller_words(expected_controller), (index, item['control_words'], expected_controller)
        assert (item['status'] == 'none') == expected_output['ok']
        if expected_output['ok']:
            assert list(map(int, item['view'][0].split(','))) == [RecordNBT.projection(v) for v in expected_controller['look'][:2]]
        else:
            whole_equal(actual['packet-' + str(index - 1)], item)
        assert item['world'] == actual['angles']['world']
    # Inactive finish does not clamp a finite out-of-range degree state. Its
    # rejected radians projection must roll back prospective key/mouse changes.
    projection = initial.copy()
    projection['look'] = [0, unsigned(fbits(100.)), 0, 0]
    projected, projection_report = run_native(binary, 'projection-rejection',
        [device_command('devices', projection), command('before', 'look', *projection['look']),
         packet_command('rejected', Controls.packet([Controls.key(100, True), Controls.look(unsigned(fbits(1.)), 0)], focused=False))])
    assert projected['rejected']['status'] == 'invalid-camera-angles'
    whole_equal(projected['before'], projected['rejected'])
    return {'packets': len(frames), 'fold_rejections': 1, 'projection_rejections': 1,
            'runs': [report, projection_report], 'rational_and_raw_float_expectations': True}


def verify_paused(binary, case):
    initial = seed_controller(17, [0, 0, 0, 0], [int(bits(3.), 16), int(bits(4.), 16), int(bits(.25), 16), int(bits(-.5), 16), False])
    commands = setup(case) + [device_command('devices', initial), command('prior', 'error', 'retained-error'),
                             command('realtime-0', 'realtime'), command('query', 'query'),
                             command('snapshot-0', 'snapshot'), command('snapshot-1', 'snapshot'),
                             command('realtime-1', 'realtime'), command('release', 'release'),
                             command('running', 'pause', 0), command('running-tick', 'realtime')]
    actual, report = run_native(binary, 'paused', commands)
    whole_equal(actual['prior'], actual['realtime-0'])
    whole_equal(actual['prior'], actual['query'])
    # Snapshot may populate the read cache; every semantic field and the Core
    # snapshot must remain unchanged, and repeated snapshots become identical.
    whole_equal(actual['query'], actual['snapshot-0'], exclude=('view',))
    assert actual['query']['view'][:3] == actual['snapshot-0']['view'][:3]
    whole_equal(actual['snapshot-0'], actual['snapshot-1'])
    whole_equal(actual['snapshot-1'], actual['realtime-1'])
    expected_release = Controls.release_raw(initial)
    assert actual['release']['control_words'] == Controls.controller_words(expected_release)
    assert actual['release']['world'] == actual['realtime-1']['world']
    assert actual['running-tick']['world_value']['tick'] == actual['running']['world_value']['tick'] + 1
    assert actual['running-tick']['error'] == ['none']
    return {'run': report, 'paused_realtime_whole_owner_retained': True,
            'render_query_clock_unchanged': True, 'release_rearms_first_discard': True}


def verify_failures(binary, case):
    reports = []
    for mode, error in [(1, 'player-context: injected-context'), (2, 'player-preparation-rejected'),
                        (3, 'player-support: injected-support')]:
        commands = setup(case) + [command('fill-cache', 'snapshot'), command('held', 'key', 119, 1),
                                 command('devices', 'controls', 17, *words([bits(3.), bits(4.), bits(.25), bits(-.5)]), 0,
                                         *words(bits(.25)), 1, 0, 0, 0),
                                 command('queue', 'edit', 2, 0, 0, 0, 0, 2),
                                 command('settings', 'settings', mode, unsigned(fbits(.6))),
                                 command('before', 'error', 'earlier-error'), command('rejected', 'step'),
                                 command('normal', 'settings', 0, unsigned(fbits(.6))), command('recovered', 'step')]
        actual, report = run_native(binary, 'failure-' + str(mode), commands)
        prior, rejected = actual['before'], actual['rejected']
        whole_equal(prior, rejected, exclude=('world', 'error'))
        assert rejected['error'] == [error]
        a, b = prior['world_value'], rejected['world_value']
        assert b['tick'] == a['tick'] + 1 and b['day_time'] == a['day_time'] + 1
        assert b['revision'] == a['revision'] + 1 and not b['pending']
        palette = list(map(int, rejected['view'][1].split(',')))
        assert cell(b, [0, 0, 0]) == palette[2]
        assert actual['recovered']['error'] == ['none']
        assert actual['recovered']['world_value']['tick'] == b['tick'] + 1
        reports.append({'phase': mode, 'error': error, 'same_owner_recovered': True,
                        'due_edit_and_clock_retained': True, 'run': report})
    return reports


def verify_restore(binary, case):
    options = [int(bits(.25), 16), True, False, False, False]
    dirty = seed_controller(127, [0, 0, 0, 0], [int(bits(3.), 16), int(bits(4.), 16), int(bits(.5), 16), int(bits(-.5), 16), False], options)
    saved_look = [unsigned(fbits(v)) for v in (123456.25, -30., 7.25, -8.5)]
    changed_look = [unsigned(fbits(v)) for v in (-12.5, 45., -17., -.25)]
    commands = setup(case) + [command('saved-look', 'look', *saved_look), command('saved-project', 'packet', 0, 1),
                              command('first', 'step'), command('cache', 'snapshot'), command('saved', 'save-record'),
                              command('dirty-look', 'look', *changed_look), command('dirty-project', 'packet', 0, 1),
                              device_command('dirty-devices', dirty), command('dirty-error', 'error', 'clear-on-restore'),
                              command('moved', 'step'), command('changed', 'error', 'clear-on-restore'), command('mismatch', 'restore', 1), command('end', 'restore', 2),
                              command('restored', 'restore', 0), command('restore-first-look', 'packet', 1, 1, 1, unsigned(fbits(20.)), 0),
                              command('post-restore-step', 'step')]
    actual, report = run_native(binary, 'restore', commands)
    for identity, message in [('mismatch', 'invalid player record'), ('end', 'current player runtime requires minecraft:overworld')]:
        assert actual[identity]['status'] == message
        whole_equal(actual['changed'], actual[identity])
    saved, restored = actual['saved'], actual['restored']
    assert saved['control_words'][1:5] == saved_look
    assert actual['changed']['control_words'][1:5] == changed_look
    for kind in ('body', 'metadata', 'support', 'record'):
        assert saved[kind] == restored[kind], (kind, saved[kind], restored[kind])
    assert restored['view'][:1] == saved['view'][:1]
    assert restored['view'][1:] == actual['end']['view'][1:]
    assert restored['world'] == actual['end']['world']
    clean = seed_controller(0, saved['control_words'][1:5], options=options)
    assert restored['control_words'] == Controls.controller_words(clean)
    assert restored['error'] == ['none'] and restored['status'] == 'none'
    assert actual['restore-first-look']['control_words'][1:5] == clean['look']
    assert actual['restore-first-look']['control_words'][13] == 0
    assert actual['post-restore-step']['error'] == ['none']
    assert actual['post-restore-step']['control_words'][0] == 0
    return {'run': report, 'invalid_record_rollback': True, 'dimension_rollback': True,
            'body_metadata_support_raw_look_restored': True, 'ephemeral_controls_cleared_options_preserved': True,
            'core_cache_region_palette_preserved': True, 'post_restore_same_owner_physics': True,
            'nonzero_distinct_current_and_previous_degree_fields': True}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--prepare', action='store_true')
    parser.add_argument('--skip-build', action='store_true')
    parser.add_argument('--fresh-reference', action='store_true')
    parser.add_argument('--build-worker', action='store_true', help=argparse.SUPPRESS)
    parser.add_argument('--resume-kernel-attempt', type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    summary, full = prepare() if args.prepare or args.fresh_reference else load_reference()
    if args.prepare:
        print(json.dumps({'status': summary['status'], 'actual_player_ai_step_calls': summary['actual_player_ai_step_calls'],
                          'cases': summary['cases'], 'native_build_started': False}, indent=2))
        return
    started = time.monotonic()
    sources = MotionNBT.imports([ENTRY, ROOT / 'src/player_runtime.bend'])
    assert sources == summary['sources_sha256']
    receipt = WORK / 'native-build.full.json'
    if args.build_worker:
        native = Build.ensure_native(ENTRY, BINARY, bend=BEND)
        native.update(sources_sha256=sources, bend=fingerprint(BEND))
        write_json(receipt, native)
        print(json.dumps({k: native[k] for k in ('artifact', 'cache_hit', 'binary_sha256', 'timings')}, sort_keys=True))
        return
    if args.skip_build:
        native = json.loads(receipt.read_text())
        verify_receipt(native, sources)
    else:
        attempt = bounded_run([sys.executable, Path(__file__), '--build-worker'], required=False)
        attempt_evidence = {'schema_version': 1, 'status': 'built' if attempt['exit_code'] == 0 and not attempt['timed_out'] else 'native_unverified',
                            'attempt': compact(attempt), 'sources_sha256': sources,
                            'stable_sources': sources == MotionNBT.imports([ENTRY, ROOT / 'src/player_runtime.bend']),
                            'compiler': fingerprint(BEND), 'artifact_adopted': attempt['exit_code'] == 0 and not attempt['timed_out']}
        write_json(ROOT / 'evidence/player-runtime-build-attempt.json', attempt_evidence)
        if attempt['exit_code'] or attempt['timed_out']:
            raise RuntimeError(json.dumps(attempt_evidence, sort_keys=True))
        native = json.loads(receipt.read_text())
    binary = verify_receipt(native, sources)
    checks = [compact(bounded_run([BEND, path, '--check-only'])) for path in (ROOT / 'src/player_runtime.bend', ENTRY)]
    if args.resume_kernel_attempt:
        previous_attempt = json.loads(args.resume_kernel_attempt.read_text())
        assert previous_attempt['sources_sha256'] == sources
        assert previous_attempt['compiler'] == fingerprint(BEND)
        kernel = previous_attempt['kernel']
        assert kernel['command'] == list(map(str, [BEND, ROOT / 'src/player_runtime.bend', '--verdict']))
        assert kernel['timed_out'] or kernel['exit_code'] != 0
        kernel_verified = False
    else:
        kernel_run = bounded_run([BEND, ROOT / 'src/player_runtime.bend', '--verdict'], required=False)
        kernel = compact(kernel_run)
        kernel_verified = kernel_run['exit_code'] == 0 and not kernel_run['timed_out'] and 'ALL PROOFS CHECK' in kernel_run['stdout']
        raw_checks = WORK / 'runtime-kernel.full.json'
        write_json(raw_checks, {'kernel': kernel_run, 'sources_sha256': sources, 'compiler': fingerprint(BEND)})
    checks.append(kernel)
    write_json(ROOT / 'evidence/player-runtime-kernel-attempt.json',
               {'schema_version': 1, 'status': 'runtime_kernel_verified' if kernel_verified else 'runtime_kernel_unverified',
                'kernel': kernel, 'sources_sha256': sources, 'compiler': fingerprint(BEND),
                'scope': 'whole production Runtime import closure; no separate aggregate gap claim'})
    records = {(kind, int(mask)): value for key, value in full['keyboard'].items() for kind, mask in [key.split(':')]}
    native_cases, tick_count = verify_cases(binary, full['cases'])
    packets = verify_packets(binary, records)
    paused = verify_paused(binary, full['cases'][0])
    failures = verify_failures(binary, full['cases'][0])
    restore = verify_restore(binary, full['cases'][0])
    assert sources == MotionNBT.imports([ENTRY, ROOT / 'src/player_runtime.bend'])
    assert sha(binary) == native['binary_sha256']
    evidence = {'schema_version': 1, 'status': 'passed' if kernel_verified else 'native_behavior_passed_runtime_kernel_unverified', 'pin': '26.3',
                'actual_player_ai_step_comparisons': tick_count, 'native_sequences': native_cases,
                'packets': packets, 'paused': paused, 'rejected_physics': failures, 'restore': restore,
                'checks': checks, 'ordinary_checked': True, 'runtime_kernel_verified': kernel_verified,
                'standalone_harness_ordinary_and_native_checked': True,
                'native_build': {k: native[k] for k in ('artifact', 'cache_key', 'cache_hit', 'binary_sha256', 'emitted_c_sha256', 'timings')},
                'native_dependency_count': len(native['dependencies']),
                'native_dependency_manifest_sha256': hashlib.sha256(canonical(native['dependencies'])).hexdigest(),
                'sources_sha256': sources, 'reference_summary': fingerprint(REFERENCE),
                'table': fingerprint(TABLE), 'tool': fingerprint(Path(__file__)),
                'verification_seconds': round(time.monotonic() - started, 6),
                'proof_scope': 'Whole Runtime BendTT verdict only when runtime_kernel_verified; existing stated laws are limited to paused-selection identity and metadata roundtrip. Native behavior is independent Java evidence.',
                'confidence': 'high within the tested plain Player facade and four-state finite scene',
                'unsupported': ['LocalPlayer.aiStep/input-assignment and sprint override', 'actual OS input/capture/presentation',
                                'complete Player/ServerPlayer tick', 'general worlds/nonneutral blocks/effects/actors/fluid/flight']}
    write_json(EVIDENCE, evidence)
    print(json.dumps({k: evidence[k] for k in ('status', 'actual_player_ai_step_comparisons', 'runtime_kernel_verified', 'verification_seconds')}, indent=2))


if __name__ == '__main__':
    main()
