#!/usr/bin/env python3
"""Actual immutable Actor020 interruption after a real incomplete temp witness.

Never builds or installs production hooks. File-only preparation reuses the
verified full player/entity snapshot; native execution is separately scheduled.
"""
from __future__ import annotations

import argparse
import copy
import json
import os
import select
import signal
import stat
import sys
import time
from pathlib import Path

import test_playable_client_cooking_entities as C

B, A, P, R, S, H, E = C.B, C.A, C.P, C.R, C.S, C.H, C.E
ROOT = C.ROOT
WORK = ROOT / 'build/playable-client-cooking-atomic-crash'
VERIFIED = ROOT / 'evidence/playable-client-cooking-entities-native-005.json'
SECTIONS = 104
CHANGE = ('minecraft:overworld', 12, 8, 12)
DAY_TIME = 12345


def bundle(world, highwater, record, full, view):
    ordinary = S.N.Reader(B.bundle(world, highwater, record, full, ''),
        max_bytes=33624064, max_elements=33624064).root()
    fields = S.WC.fields(dict(ordinary.value.payload)[S.N.text('extension')], S.EXTENSION_FIELDS)
    extension = S.WC.compound([('namespace', fields['namespace']), ('schema', fields['schema']),
        ('payload', S.N.Value(7, C.wrapper(bytes(fields['payload'].payload), (), view)))])
    return S.N.encode_root(S.N.RootTag(ordinary.name, S.N.Value(10, tuple(
        (name, extension if name == S.N.text('extension') else value)
        for name, value in ordinary.value.payload))))


def acknowledged(client, path, facts, world, record, full, highwater, view, directory, label):
    reply = client.call('world.save', {})
    actual, expected = path.read_bytes(), bundle(world, highwater, record, full, view)
    decoded = C.projection(actual, facts)
    S.require(reply == {'status': 'durable', 'published': True, 'durable': True,
        'bytes': len(actual), 'peer_highwater': highwater} and actual == expected and
        decoded[1:] == (S.local_bytes(record), full, (), highwater, view, ()) and
        S.P.canonical_expected(decoded[0]) == S.P.canonical_expected(world),
        'Exact complete big Core/player/entity format3 atomic save: ' + label)
    receipt = {'label': label, 'reply': reply, 'bytes': len(actual), 'sha256': S.sha(actual),
        'expected_sha256': S.sha(expected), 'full_atomic_bytes_equal': True,
        'pending_effects': 0, 'clock_inputs': 0, 'full_entity_records': len(view['records'])}
    S.exclusive_json(directory / (label + '.json'), receipt)
    return actual, receipt


def fresh_directory():
    WORK.mkdir(exist_ok=True)
    index = max((int(p.name) for p in WORK.iterdir() if p.is_dir() and p.name.isdigit()), default=0) + 1
    directory = WORK / f'{index:03}'
    directory.mkdir(exist_ok=False)
    return index, directory


def fixture():
    retained = json.loads(VERIFIED.read_bytes())
    S.require(retained['status'] == 'PASS_NARROW' and
              retained['binary']['sha256'] == '54b79ea92479b84ebd3d194d2f2fadd8f8504970d6aa9db2b42beb2d865741e8',
              'Use the verified actual020 full entity snapshot')
    source = Path(retained['final_atomic_snapshot']['path'])
    S.require(R.pin(source) == retained['final_atomic_snapshot'], 'Retained actual final snapshot changed')
    facts = C.expected_facts()
    world, player, full, bodies, highwater, view, clocks = C.projection(source.read_bytes(), facts)
    S.require(not bodies and not clocks and len(view['records']) == 3 and
              view == retained['final_entity_view'], 'Actual complete two Item/one Orb owner')
    record = S.decode_local(player)
    original = {row['key']: row for row in world['sections']}
    air = facts['palette']['minecraft:air']
    world['sections'] = [copy.deepcopy(original.get(S.BASE.section_key(x, y, z),
        S.WC.section(S.BASE.section_key(x, y, z), air)))
        for x in (-16, 0) for y in range(-80, 336, 16) for z in (-16, 0)]
    world['sections'].sort(key=lambda row: row['key'])
    S.require(len(world['sections']) == SECTIONS and not world['pending'], 'Full paused 104-section crash fixture')
    S.P.canonical_expected(world)
    return facts, world, record, full, highwater, view, source


def queue_time(client, world, at):
    stamp = S.P.stamp(client.call('world.time.set', {'day_time': DAY_TIME}, at=at))
    world['pending'].append({'stamp': stamp, 'mutation': {'kind': 2, 'day_time': DAY_TIME}})
    world['pending'].sort(key=lambda row: row['stamp'])


def request_save(client):
    request = {'id': 'raw-' + str(client.count), 'op': 'world.save', 'args': {}}
    data = S.MCP.encode(request)
    client.wire_in.write(data)
    client.wire_in.flush()
    client.socket.sendall(data)
    return request


def receive_save(client, request):
    client.socket.settimeout(10)
    line, transport_error = b'', None
    try:
        while not line.endswith(b'\n'):
            chunk = client.socket.recv(65536)
            client.wire_out.write(chunk)
            client.wire_out.flush()
            if not chunk:
                break
            line += chunk
            S.require(len(line) <= 2 * 1024 * 1024, 'Actual deferred save frame limit')
    except OSError as cause:
        transport_error = {'type': type(cause).__name__, 'message': str(cause)}
    client.count += 1
    response = json.loads(line) if line.endswith(b'\n') else None
    if response is not None:
        S.require(response['id'] == request['id'], 'Deferred actual save reply identity')
    return {'frame_bytes': len(line), 'complete_frame': line.endswith(b'\n'),
        'response': response, 'transport_error': transport_error}


def incomplete_then_kill(actor, client, path, expected, directory):
    latest = client.call('ping')
    temp = Path(str(path) + f'.pending-save-{latest["peer"]}-{latest["sequence"] + 1}')
    S.require(not list(path.parent.glob(path.name + '.pending-*')), 'No stale fixture temporary before save')
    request = request_save(client)
    begun = time.monotonic_ns()
    deadline = min(actor.deadline - 10, time.monotonic() + 120)
    changes, fd, last_size, witness = [], None, None, None
    try:
        while time.monotonic() < deadline:
            if fd is None:
                try:
                    fd = os.open(temp, os.O_RDONLY | os.O_NOFOLLOW)
                except FileNotFoundError:
                    pass
            if fd is not None:
                info = os.fstat(fd)
                S.require(stat.S_ISREG(info.st_mode), 'Actual atomic temporary must be a regular file')
                if info.st_size != last_size:
                    changes.append({'elapsed_ns': time.monotonic_ns() - begun, 'bytes': info.st_size,
                                    'device': info.st_dev, 'inode': info.st_ino})
                    last_size = info.st_size
                if 0 < info.st_size < len(expected):
                    prefix = os.pread(fd, min(info.st_size, 4096), 0)
                    if prefix == expected[:len(prefix)] and prefix:
                        witness = {'kind': 'positive-incomplete-expected-prefix', 'temporary': str(temp),
                            'observed_monotonic_ns': time.monotonic_ns(), 'bytes': info.st_size,
                            'expected_complete_bytes': len(expected), 'device': info.st_dev,
                            'inode': info.st_ino, 'sample_bytes': len(prefix), 'sample_sha256': S.sha(prefix)}
                        S.exclusive_json(directory / 'pre-kill-witness.json', witness)
                        os.killpg(actor.process.pid, signal.SIGKILL)
                        witness['signal_monotonic_ns'] = time.monotonic_ns()
                        S.exclusive_json(directory / 'signal.json', {'pid': actor.process.pid,
                            'process_group': actor.process.pid, 'signal': 'SIGKILL',
                            'monotonic_ns': witness['signal_monotonic_ns']})
                        actor.process.wait(timeout=5)
                        after = os.fstat(fd)
                        payload = os.pread(fd, after.st_size, 0)
                        S.require((after.st_dev, after.st_ino) == (info.st_dev, info.st_ino) and
                                  0 < len(payload) == after.st_size <= len(expected) and
                                  payload == expected[:len(payload)], 'Retained same-inode actual temporary prefix')
                        retained = directory / 'interrupted-temporary-image.bin'
                        retained.write_bytes(payload)
                        witness['after_exit'] = {'bytes': after.st_size, 'retained': R.pin(retained),
                            'complete_payload': payload == expected, 'named_temp_exists': temp.exists()}
                        break
            if select.select([client.socket], [], [], .0005)[0]:
                break
        reply = receive_save(client, request) if witness or select.select([client.socket], [], [], 0)[0] else None
        outcome = {'status': 'OBSERVED' if witness else 'UNOBSERVED', 'save_request': request,
            'predicted_temporary': str(temp), 'size_transitions': changes, 'witness': witness,
            'deferred_reply': reply, 'seconds': (time.monotonic_ns() - begun) / 1e9,
            'active_syscall_phase': 'UNOBSERVED; file observation does not identify the exact active effect'}
        S.exclusive_json(directory / 'interruption.json', outcome)
        return outcome
    finally:
        if fd is not None:
            os.close(fd)


def scenario(directory, binary, bridge):
    directory.mkdir(exist_ok=False)
    facts, world, record, full, initial_highwater, view, source = fixture()
    path = directory / 'world.nbt'
    path.write_bytes(bundle(world, initial_highwater, record, full, view))
    S.exclusive_json(directory / 'fixture.json', {'source': R.pin(source), 'initial': R.pin(path),
        'sections': SECTIONS, 'cells': SECTIONS * 4096, 'entity_records': len(view['records'])})
    actor = A.PlayableBackend(directory / 'writer', binary, path, bridge,
        startup_seconds=180, lifetime_seconds=270)
    interrupted = False
    try:
        client, ping = actor.tcp(True)
        client.socket.settimeout(120)
        S.inspect(client, record)
        S.require(client.call('world.clock') == S.P.clock(world), 'Actual big-world startup preserves sole Core')
        old, baseline = acknowledged(client, path, facts, world, record, full,
            ping['peer'], view, directory, 'acknowledged-baseline')
        (directory / 'acknowledged-old.nbt').write_bytes(old)
        old_world = copy.deepcopy(world)
        S.queue_set(client, world, CHANGE, facts['palette']['minecraft:stone'], world['tick'] + 1)
        queue_time(client, world, world['tick'] + 2)
        new = bundle(world, ping['peer'], record, full, view)
        (directory / 'expected-new.nbt').write_bytes(new)
        S.require(new != old and path.read_bytes() == old, 'Meaningful admitted next state remains unsaved')
        lock = Path(str(path) + '.lock')
        lock_inode = lock.stat().st_ino
        observation = incomplete_then_kill(actor, client, path, new, directory)
        interrupted = observation['witness'] is not None
        if not interrupted:
            unobserved_image = path.read_bytes()
            S.require(unobserved_image in (old, new), 'Unobserved attempt retains a complete old/new destination')
            result = {'status': 'UNOBSERVED', 'baseline': baseline, 'observation': observation,
                'actual_SIGKILL_after_incomplete_witness': False,
                'destination_at_monitor_end': R.pin(path),
                'complete_image_at_monitor_end': 'old' if unobserved_image == old else 'new',
                'scope': 'No positive incomplete temporary payload was observed; no crash-during-write acceptance claim.'}
            S.exclusive_json(directory / 'summary.json', result)
            return result
        actor.stop(kill=True)
        actual = path.read_bytes()
        S.require(actual in (old, new), 'SIGKILL destination must be exact old or complete new image')
        chosen = 'old' if actual == old else 'new'
        selected_world = old_world if chosen == 'old' else copy.deepcopy(world)
        (directory / 'post-crash-destination.nbt').write_bytes(actual)
        projected = C.projection(actual, facts)
        S.require(projected[1:] == (S.local_bytes(record), full, (), ping['peer'], view, ()) and
                  S.P.canonical_expected(projected[0]) == S.P.canonical_expected(selected_world),
                  'Complete old/new Core/player/entity image, no hybrid')
    except BaseException:
        actor.stop(failed=True)
        raise
    finally:
        actor.stop(kill=interrupted)

    cold = A.PlayableBackend(directory / 'cold-restore', binary, path, bridge,
        startup_seconds=180, lifetime_seconds=270)
    try:
        client, cold_ping = cold.tcp(True)
        client.socket.settimeout(120)
        S.inspect(client, record)
        S.require(path.read_bytes() == actual and lock.stat().st_ino == lock_inode and
                  client.call('world.clock') == S.P.clock(selected_world),
                  'Cold restore decodes exact chosen image under the same lock inode')
        S.require(len(selected_world['pending']) == (0 if chosen == 'old' else 2), 'No duplicated/restored admitted actions')
        for _ in range(2):
            S.BASE.apply_tick(selected_world)
            S.require(client.call('simulation.step', {'ticks': 1}) == S.P.clock(selected_world),
                      'Actual cold continuation applies chosen action set exactly once')
        continued = S.decode_local(bytes(client.call('player.inspect', {})['nbt_bytes']))
        S.require(continued.count == record.count + 2 and not selected_world['pending'],
                  'Two sole Core/player continuations with no pending replay duplication')
        _, continuation = acknowledged(client, path, facts, selected_world, continued, full,
            cold_ping['peer'], view, directory, 'cold-continued-authority')
        result = {'status': 'PASS_NARROW_OBSERVED', 'baseline': baseline, 'observation': observation,
            'selected_image': chosen, 'post_crash_image': R.pin(directory / 'post-crash-destination.nbt'),
            'acknowledged_old': R.pin(directory / 'acknowledged-old.nbt'),
            'expected_new': R.pin(directory / 'expected-new.nbt'), 'continuation': continuation,
            'actual_SIGKILL_after_incomplete_witness': True, 'sections': SECTIONS,
            'entity_records_preserved': 3, 'duplicate_replay': False,
            'scope': 'Actual quiet actor020 atomic publication interrupted after a witnessed incomplete payload. '
                     'Complete old/new image and cold continuation only; no active-syscall, power-loss or whole-game claim.'}
        S.exclusive_json(directory / 'summary.json', result)
        return result
    except BaseException:
        cold.stop(failed=True)
        raise
    finally:
        cold.stop()


def pins():
    return C.runtime_pins() | {str(VERIFIED): R.pin(VERIFIED), str(Path(C.__file__)): R.pin(C.__file__)}


def prepare():
    index, directory = fresh_directory()
    facts, world, record, full, highwater, view, source = fixture()
    old = bundle(world, highwater, record, full, view)
    changed = copy.deepcopy(world)
    changed['pending'] = [
        {'stamp': (world['tick'] + 1, highwater + 2, 4), 'mutation':
            {'kind': 1, 'dimension': CHANGE[0], 'x': CHANGE[1], 'y': CHANGE[2], 'z': CHANGE[3],
             'state': facts['palette']['minecraft:stone']}},
        {'stamp': (world['tick'] + 2, highwater + 2, 5), 'mutation': {'kind': 2, 'day_time': DAY_TIME}}]
    new = bundle(changed, highwater, record, full, view)
    for name, image, expected_world in (('old.nbt', old, world), ('new.nbt', new, changed)):
        (directory / name).write_bytes(image)
        decoded = C.projection(image, facts)
        S.require(decoded[1:] == (S.local_bytes(record), full, (), highwater, view, ()) and
                  S.P.canonical_expected(decoded[0]) == S.P.canonical_expected(expected_world),
                  'File-only complete large format3 fixture framing')
    S.require(old != new and len(old) > 104 * 16384, 'Meaningful large independent old/new images')
    frozen = ROOT / 'build/compiler-producer-diagnostic-020/source/src'
    writer = {str(path): R.pin(path) for path in
        (frozen / 'atomic_file.bend', frozen / 'extended_persistence.bend', frozen / 'native/durability.c')}
    receipt = {'status': 'PREPARED_FILE_ONLY', 'native_executed': False, 'explicit_actor_generation': 20,
        'runner': R.pin(Path(__file__)), 'source_snapshot': R.pin(source), 'verified_consumer': R.pin(VERIFIED),
        'runtime_inputs': pins(), 'writer_sources': writer, 'fixture_old': R.pin(directory / 'old.nbt'),
        'generated_writer': {'C': json.loads((ROOT / 'build/compiler-producer-diagnostic-020/native-build.json').read_bytes())['C'],
            'write_loop_line': 1631795, 'byte_conversion_line': 1631827},
        'preparation_failure': R.pin(ROOT / 'evidence/playable-client-cooking-atomic-crash-prepared-failure-001.json'),
        'fixture_new': R.pin(directory / 'new.nbt'), 'sections': SECTIONS, 'cells': SECTIONS * 4096,
        'full_entity_records': 3, 'full_player_inventory_equipment_status_generation': True,
        'witness': '0 < same-inode temporary size < independently expected new length, matching actual prefix before owned SIGKILL',
        'race_policy': 'After signal/reap destination must be exact old OR fully published new; post-exit inode/prefix retained.',
        'no_witness': 'UNOBSERVED, no stage/crash acceptance inference',
        'native_command': [sys.executable, '-B', str(Path(__file__)), '--actor-generation', '20', '--native'],
        'scope': 'File-only fixture/protocol preparation, no source/compiler/proof/native execution or production hook.'}
    output = ROOT / f'evidence/playable-client-cooking-atomic-crash-prepared-{index:03}.json'
    R.write(output, receipt, True)
    print(json.dumps({'status': receipt['status'], 'evidence': str(output)}), flush=True)


def child(directory):
    build = B.artifact()
    S.require(build['generation'] == 'immutable-actor004/producer020', 'Only actual frozen020 artifact')
    journal = directory / 'owned-groups.jsonl'
    journal.touch(exist_ok=False)
    bridge, _ = P.retained_bridge()
    before = pins()
    def identity():
        S.require(R.pin(A.ACTOR) == build['binary'], 'Frozen actual020 actor changed')
    with H.bindings(S, {'SERVER': A.ACTOR, 'ROOT': ROOT, 'activation': identity, 'OWNED_GROUPS': journal}):
        result = scenario(directory / 'actors', A.ACTOR, bridge)
    S.require(pins() == before, 'Pinned crash consumer inputs changed')
    identity()
    print(json.dumps({'status': result['status']}), flush=True)


def native():
    build = B.artifact()
    S.require(build['generation'] == 'immutable-actor004/producer020', 'Only actual successful020 artifact')
    index, directory = fresh_directory()
    before = pins()
    S.exclusive_json(directory / 'inputs.json', {'binary': build['binary'], 'source_map': build['source_map'],
        'runtime': before, 'runner': R.pin(Path(__file__))})
    bridge, _ = P.retained_bridge()
    with H.bindings(R, {'WORK': directory}):
        try:
            process = R.bounded([sys.executable, '-B', str(Path(__file__)), '--actor-generation', '20',
                '--_child', str(directory)], 600, 'execution')
        finally:
            B.descendant_cleanup(directory, bridge)
    common = {'binary': build['binary'], 'inputs': R.pin(directory / 'inputs.json'),
        'process': R.pin(directory / 'execution/result.full.json'), 'cleanup': R.pin(directory / 'cleanup.json')}
    try:
        R.process_ok(process)
    except BaseException:
        R.write(ROOT / f'evidence/playable-client-cooking-atomic-crash-failure-{index:03}.json',
            {'status': 'FAIL', **common, 'error': R.pin(directory / 'execution/stderr'),
             'scope': 'Actual current020 attempt retained; no crash/publication acceptance claim.'}, True)
        raise
    S.require(pins() == before, 'Pinned crash inputs changed')
    summary = json.loads((directory / 'actors/summary.json').read_bytes())
    output = ROOT / f'evidence/playable-client-cooking-atomic-crash-native-{index:03}.json'
    R.write(output, {'status': summary['status'], **common, 'summary': summary,
        'summary_pin': R.pin(directory / 'actors/summary.json')}, True)
    print(json.dumps({'status': summary['status'], 'evidence': str(output)}), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--actor-generation', type=int, required=True, choices=(20,))
    modes = parser.add_mutually_exclusive_group(required=True)
    modes.add_argument('--expectations', action='store_true')
    modes.add_argument('--native', action='store_true')
    modes.add_argument('--_child', type=Path)
    args = parser.parse_args()
    selected = ROOT / 'build/compiler-producer-diagnostic-020'
    with H.bindings(A, {'WORK': selected, 'SOURCE': selected / 'source', 'ACTOR': selected / 'actor'}):
        prepare() if args.expectations else child(args._child) if args._child else native()


if __name__ == '__main__':
    main()
