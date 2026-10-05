#!/usr/bin/env python3
"""Actual paused cooking-menu TCP consumer; consumes a selected actor, never builds.

File-only preparation verifies retained Java outcomes and physical fixtures.
The independent empty-owner lifecycle is an explicit separate route. The
optional large-component case runs after the main positive/save checks.
"""
from __future__ import annotations

import argparse
import copy
import json
import socket
import sys
import time
from pathlib import Path

import playable_client_cooking_menu_expectations as E
import test_playable_client_cooking_entities as Storage

C19, B, A, P, R, S, H = E.C19, E.B, E.A, E.P, E.R, E.S, E.H
ROOT = E.ROOT
WORK = ROOT / 'build/playable-client-cooking-menu'
OVERFLOW = 'cooking-menu:prospective-reply-refused'


class MenuPrivate(B.Private):
    """Existing journal/lease owner with an explicit optional receiver time budget."""
    def __init__(self, actor):
        self.response_seconds = 5
        super().__init__(actor)

    def exchange(self, request):
        S.require(time.monotonic() < self.backend.deadline, 'Actor lifetime cap')
        data = json.dumps(request, ensure_ascii=True, separators=(',', ':')).encode('ascii') + b'\n'
        S.require(len(data) - 1 <= 65536, 'Production private ASCII request bound')
        self.requests.write(data); self.requests.flush(); self.socket.sendall(data)
        deadline = min(time.monotonic() + self.response_seconds, self.backend.deadline)
        while b'\n' not in self.buffer:
            remaining = deadline - time.monotonic()
            S.require(remaining > 0, 'Cooking response timeout')
            self.socket.settimeout(remaining)
            part = self.socket.recv(8192)
            self.responses.write(part); self.responses.flush()
            S.require(part, 'Cooking EOF before reply')
            self.buffer += part
            S.require(len(self.buffer) <= 65537, 'Physical private reply bound')
        line, self.buffer = self.buffer.split(b'\n', 1)
        S.require(not self.buffer and len(line) <= 65536 and all(byte < 128 for byte in line),
                  'ASCII reply framing and empty tail')
        reply = json.loads(line)
        if request[:2] == [1, 0] and reply == [1, 3, '', 0, 'RendererLeaseBusy']:
            self.close()
            raise R.LeaseBusy('RendererLeaseBusy')
        return reply


def connect(actor):
    with H.bindings(R, {'Private': MenuPrivate}):
        return R.acquire(actor)


def runtime_pins():
    return C19.runtime_pins() | {str(path): R.pin(path) for path in
        (E.REFERENCE, B.FULL_FIXTURE, Path(E.__file__), Path(C19.__file__),
         Path(B.__file__), Path(Storage.__file__))}


def cooking(control, checks, command, label, snapshot, *, accepted=True, message=''):
    sequence = control.sequence
    started = time.monotonic()
    reply = control.call(command, 8)
    S.require(reply[4:] == [accepted, message, snapshot],
              'Complete cooking reply ' + label + ': ' + str(reply[4:6]))
    checks.append({'label': label, 'command': command, 'sequence': sequence,
                   'accepted': accepted, 'message': message,
                   'snapshot_sha256': S.sha(S.canonical(snapshot)),
                   'seconds': time.monotonic() - started})
    return reply


def menu(control, checks, full, current, command, label):
    reply = control.call(command, 6)
    S.require(reply[4:] == [True, '', B.authority(full, current)],
              'Complete private inventory reply: ' + label)
    checks.append({'label': label, 'command': command, 'sequence': reply[3],
                   'accepted': True, 'authority_sha256': S.sha(S.canonical(reply[6]))})


def inspect_record(raw):
    return S.decode_local(bytes(raw.call('player.inspect', {})['nbt_bytes']))


def physical_save(raw, path, facts, world, record, full, *, expected_body=None):
    reply = raw.call('world.save', {})
    data = path.read_bytes()
    # This consumer may intentionally retain a real Dirty publisher refusal.
    # The entity consumer's stricter drained-queue projection is therefore not
    # appropriate. Parse the same format3 fields and retain the complete queue.
    outer = S.N.Reader(data, max_bytes=33624064, max_depth=16, max_elements=33624064).root()
    S.require(outer.name == S.N.text('bendex:bundle'), 'Physical envelope root')
    fields = S.WC.fields(outer.value, S.BUNDLE_FIELDS)
    S.require(S.WC.uint(fields['format']) == 1 and S.WC.scalar_text(fields['minecraft']) == '26.3' and
              S.WC.scalar_text(fields['registry']) == facts['identity'], 'Physical envelope identity')
    actual_world = S.WC.validate(S.N.parse(fields['core'].payload), facts['count'], facts['identity'])
    extension = S.WC.fields(fields['extension'], S.EXTENSION_FIELDS)
    S.require(S.WC.scalar_text(extension['namespace']) == S.NAMESPACE and
              S.WC.uint(extension['schema']) == 1, 'Atomic namespace/schema')
    wrapper = S.N.parse(bytes(extension['payload'].payload))
    S.require(wrapper.name == S.N.text(C19.WRAPPER), 'Actual cooking wrapper root')
    saved = S.WC.fields(wrapper.value, ('format', 'player', 'bodies', 'effects', 'entities', 'clock_inputs'))
    S.require(S.WC.uint(saved['format']) == 3 and saved['player'].kind == saved['effects'].kind ==
              saved['entities'].kind == 7 and saved['clock_inputs'].kind == 12 and
              saved['bodies'].kind == 9 and saved['bodies'].payload[0] == 10,
              'Complete format3 owner/effects/entity framing')
    actual_record, actual_full = B.Inventory.parse_inventory_full(bytes(saved['player'].payload))
    bodies = []
    for value in saved['bodies'].payload[1]:
        physical = S.WC.fields(value, ('dimension', 'x', 'y', 'z', 'body'))
        S.require((S.WC.scalar_text(physical['dimension']), *(S.WC.uint(physical[k]) for k in ('x', 'y', 'z'))) == E.POSITION and
                  physical['body'].kind == 7, 'Exact keyed cooking body')
        bodies.append(bytes(physical['body'].payload))
    bodies = tuple(bodies)
    highwater = S.WC.uint(fields['peer_highwater'])
    entities = Storage.E.decode(bytes(saved['entities'].payload))
    clocks = saved['clock_inputs'].payload
    pending = bytes(saved['effects'].payload)
    pending_root = S.N.parse(pending)
    S.require(pending_root.name == S.N.text(C19.EFFECTS_ROOT), 'Actual retained effect queue root')
    S.require(reply == {'status': 'durable', 'published': True, 'durable': True,
        'bytes': len(data), 'peer_highwater': highwater}, 'Actual save acknowledgement')
    S.require(S.P.canonical_expected(actual_world) == S.P.canonical_expected(world) and
              actual_record == S.local_bytes(record) and actual_full == full and
              len(bodies) == 1 and not clocks and not entities['records'],
              'Physical Core/record/all43 durable cells/raw status/body ownership')
    if expected_body is not None:
        S.require(bodies == (expected_body,), 'Exact physical body bytes and cleared old Details')
    return data, {'reply': reply, 'sha256': S.sha(data), 'body_sha256': S.sha(bodies[0]),
                  'complete_pending_effects_sha256': S.sha(pending),
                  'entity_records': 0,
                  'scope': 'All exposed durable fields and body bytes; fresh entity/RNG entropy is not re-oracled here.'}


def optional_overflow(control, raw, path, facts, world, record, full, current, checks):
    # One fixed, independently admitted profile is reused. No generated entropy
    # or arbitrary string is substituted for actual initialized item authority.
    key = B.component_key()
    control.response_seconds = 90
    full['main']['slots'][2] = B.stack('minecraft:suspicious_stew', 1, key)
    menu(control, checks, full, current, [7, 2, ['minecraft:suspicious_stew', key], 1], 'one-initialized-large-key')
    current['opened'] = True
    old = E.handle(2)
    furnace = E.view([None] * 3, [10, 10, 0, 200])
    cooking(control, checks, [14, list(E.POSITION)], 'open-single-key-profile', E.snapshot(full, current, old, furnace))
    full['main']['slots'][2] = None
    current.update(carried=B.stack('minecraft:suspicious_stew', 1, key), revision=current['revision'] + 1)
    cooking(control, checks, [16, 2, 32, 0], 'pickup-large-key-from-real-hotbar', E.snapshot(full, current, old, furnace))
    current.update(carried=None, revision=current['revision'] + 1)
    furnace = E.view([B.stack('minecraft:suspicious_stew', 1, key), None, None], [10, 10, 0, 200])
    cooking(control, checks, [16, 2, 0, 0], 'deposit-exact-patch-in-actual-furnace', E.snapshot(full, current, old, furnace))
    current['opened'] = False
    cooking(control, checks, [18, 2], 'close-single-key-furnace', E.snapshot(full, current, [0], [0]))
    full['main']['slots'][3] = B.stack('minecraft:suspicious_stew', 1, key)
    menu(control, checks, full, current, [7, 3, ['minecraft:suspicious_stew', key], 1], 'player-key-beside-closed-furnace-key')
    before, saved = physical_save(raw, path, facts, world, record, full)
    old_snapshot = E.snapshot(full, current, [0], [0])
    prospective_menu = copy.deepcopy(current); prospective_menu['opened'] = True
    prospective = [1, 8, control.epoch, control.sequence, True, '',
                   E.snapshot(full, prospective_menu, E.handle(3), furnace)]
    before_bytes = len(json.dumps([1, 8, control.epoch, control.sequence, False, OVERFLOW, old_snapshot],
                                ensure_ascii=True, separators=(',', ':')).encode('ascii'))
    after_bytes = len(json.dumps(prospective, ensure_ascii=True, separators=(',', ':')).encode('ascii'))
    S.require(before_bytes <= 65536 < after_bytes, 'Actual aggregate cooking reply crosses transport bound')
    cooking(control, checks, [14, list(E.POSITION)], 'aggregate-open-refusal', old_snapshot,
            accepted=False, message=OVERFLOW)
    cooking(control, checks, [15, 0], 'same-lease-closed-discovery-after-refusal', old_snapshot)
    after, second = physical_save(raw, path, facts, world, record, full)
    S.require(after == before, 'Complete acknowledged physical owner bytes changed on reply refusal')
    # Removing only the explicitly acquired creative player copy exposes the
    # retained furnace key and the unconsumed next-menu ID after the refusal.
    full['main']['slots'][3] = None
    menu(control, checks, full, current, [7, 3, ['minecraft:dirt', ''], 0], 'clear-explicit-creative-test-copy')
    current['opened'] = True
    cooking(control, checks, [14, list(E.POSITION)], 'open-retained-furnace-id-after-refusal',
            E.snapshot(full, current, E.handle(3), furnace))
    cooking(control, checks, [15, 3], 'continued-exact-furnace-key-and-timers',
            E.snapshot(full, current, E.handle(3), furnace))
    current['opened'] = False
    cooking(control, checks, [18, 3], 'close-after-aggregate-refusal-recovery', E.snapshot(full, current, [0], [0]))
    return {'status': 'PASS', 'key_sha256': S.sha(key.encode()), 'effects': 1200,
            'old_reply_bytes': before_bytes, 'prospective_reply_bytes': after_bytes,
            'complete_physical_before_after_equal': True, 'saves': [saved, second],
            'context_scope': 'Same retained actor/initialized key/furnace and unconsumed ID after refusal; opaque recipe caches are not exposed.'}


def scenario(directory, binary, bridge, *, component_overflow=False):
    directory.mkdir(exist_ok=False)
    facts = C19.independent_expectations()
    observed_java = E.reference_cases()
    world, record, full, slots, body, initial = E.fixture(facts)
    path = directory / 'menu.nbt'; path.write_bytes(initial)
    checks, faults = [], []
    current = B.empty_menu()
    actor = A.PlayableBackend(directory / 'actor', binary, path, bridge,
                              lifetime_seconds=600 if component_overflow else 240)
    try:
        raw, ping = actor.tcp(True)
        S.require(ping['peer'] == 42, 'Reserved player41 and public42 from durable highwater40')
        observer, _ = actor.tcp()
        control = connect(actor)
        S.inspect(raw, record)
        cooking(control, checks, [15, 0], 'initial-closed-discovery', E.snapshot(full, current, [0], [0]))
        current['opened'] = True
        active = E.handle(1)
        furnace = E.view(slots, [10, 10, 40, 200])
        cooking(control, checks, [14, list(E.POSITION)], 'authoritative-open', E.snapshot(full, current, active, furnace))
        for command, label, message in (
            ([15, 2], 'wrong-menu-inspect', 'cooking-menu:authority-menu-range-or-incarnation-refused'),
            ([18, 2], 'wrong-menu-close', 'cooking-menu:wrong-close-owner'),
            ([14, ['minecraft:overworld', 999, 8, 12]], 'out-of-range-open-retains-old-handle', 'cooking-menu:open-authority-or-range-refused'),
            ([14, ['minecraft:the_nether', 12, 8, 12]], 'wrong-dimension-open-retains-old-handle', 'cooking-menu:open-authority-or-range-refused')):
            cooking(control, checks, command, label, E.snapshot(full, current, active, [0]), accepted=False, message=message)
            cooking(control, checks, [15, 0], label + '-actual-old-owner', E.snapshot(full, current, active, furnace))
        observer.call('inventory.acquire', {'slot': 1, 'item': 'minecraft:dirt', 'count': 1}, fault='PermissionDenied')
        for label, request, expected in (
            ('bad-capability', [1, 0, 'wrong-verification-capability'], [1, 3, '', 0, 'RendererAuthenticationFailed']),
            ('second-owner', [1, 0, actor.token], [1, 3, '', 0, 'RendererLeaseBusy']),
            ('unassigned-cooking-socket', [1, 1, control.epoch, control.sequence, [16, 1, 0, 0]],
             [1, 3, control.epoch, control.sequence, 'Wire:SocketEpoch']),
            ('bad-version-header', [2, 0, actor.token], [1, 3, '', 0, 'Wire:MalformedRequest'])):
            B.peer_fault(actor, request, expected, directory, label)
            faults.append(label)
        cooking(control, checks, [15, 1], 'same-owner-after-foreign-faults', E.snapshot(full, current, active, furnace))
        bad = control.sequence + 1
        answer = control.exchange([1, 1, control.epoch, bad, [16, 1, 0, 0]])
        S.require(answer == [1, 3, control.epoch, bad, 'RendererLeaseOrSequence'], 'Stale cooking lease refusal')
        faults.append('stale-owner-sequence')
        control.close(); actor.private = None
        control = connect(actor)
        cooking(control, checks, [15, 0], 'reconnect-complete-old-handle', E.snapshot(full, current, active, furnace))
        steps = E.expected_steps(full)
        for row in steps:
            full, current = copy.deepcopy(row['full']), copy.deepcopy(row['menu'])
            closed = row['command'][0] == 18
            cooking(control, checks, row['command'], row['label'],
                    E.snapshot(full, current, [0] if closed else active,
                               [0] if closed else E.view(row['slots'], row['timers'])))
        S.require(raw.call('world.clock') == S.P.clock(world) and inspect_record(raw) == record,
                  'Polling and menu operations never advance Core/player time')
        S.exclusive_json(directory / 'menu-positive-summary.json', {
            'status': 'PASS', 'checks': len(checks), 'lease_header_faults': faults,
            'actual_Open_Inspect_Click_QuickMove_Close': True,
            'complete_exposed_player_furnace_snapshots_equal': True,
            'Core_player_time_unchanged': True,
            'scope': 'Published before explicit lifecycle tick or optional large-component work.'})
        _, saved = physical_save(raw, path, facts, world, record, full,
                                 expected_body=E.body(facts, [None] * 3, progress=0, remaining=10))
        # Publish the positive result before an optional expensive old-CC path,
        # so its failure cannot obscure actual menu availability and routing.
        positive = {'status': 'PASS', 'checks': len(checks), 'lease_header_faults': faults,
                    'real_incarnation_reset': False, 'save_projection': saved}
        S.exclusive_json(directory / 'positive-summary.json', positive)
        overflow = optional_overflow(control, raw, path, facts, world, record, full, current, checks) if component_overflow else {'status': 'NOT_RUN; optional initialized-large-key case'}
        result = {'status': 'PASS', 'generation': A.generation_name(), 'actual_TCP': True,
            'paused': True, 'backends': 1, 'cooking_checks': checks, 'lease_header_faults': faults,
            'retained_java_cases': list(observed_java), 'optional_aggregate': overflow,
            'positive': positive, 'scope': 'Real private TCP/correlated authority and acknowledged save. Full exposed48-slot MenuSnapshot/all43 durable slots/raw status/3furnace slots/timers. Empty-owner reset is a separate --lifecycle-only route. Hidden player48..63 and furnace backing4 remain prior51 native scope. No render/OS, complete opaque context inspection, entity/RNG constructors or crash replay.'}
        S.exclusive_json(directory / 'summary.json', result)
        return result
    except BaseException:
        actor.stop(failed=True)
        raise
    finally:
        actor.stop()


def lifecycle_scenario(directory, binary, bridge):
    """Actual empty-owner removal/recreation without earlier GUI mutations."""
    directory.mkdir(exist_ok=False)
    facts = C19.independent_expectations()
    world, record, full, slots, body, seed = E.empty_fixture(facts)
    path = directory / 'lifecycle.nbt'; path.write_bytes(seed)
    checks, current = [], B.empty_menu()
    actor = A.PlayableBackend(directory / 'actor', binary, path, bridge, lifetime_seconds=240)
    try:
        raw, ping = actor.tcp(True)
        S.require(ping['peer'] == 42, 'Lifecycle retained durable highwater40')
        control = connect(actor)
        S.inspect(raw, record)
        current['opened'] = True
        old = E.handle(1)
        cooking(control, checks, [14, list(E.POSITION)], 'initial-empty-owner-open',
                E.snapshot(full, current, old, E.view(slots, [0, 0, 0, 0])))
        for state in (facts['palette']['minecraft:air'], facts['unlit']):
            S.queue_set(raw, world, E.POSITION, state, world['tick'] + 1)
        raw.call('simulation.step', {'ticks': 1})
        S.BASE.apply_tick(world)
        record = inspect_record(raw)
        S.require(record.count == 1 and raw.call('world.clock') == S.P.clock(world) and
                  raw.call('world.block.get', dict(zip(('dimension', 'x', 'y', 'z'), E.POSITION))) ==
                  {'state': facts['unlit']}, 'Actual explicit empty-owner reset tick and Core state')
        cooking(control, checks, [16, 1, 0, 0], 'old-incarnation-refusal',
                E.snapshot(full, current, old, [0]), accepted=False,
                message='cooking-menu:authority-menu-range-or-incarnation-refused')
        current['opened'] = False
        cooking(control, checks, [18, 1], 'close-stale-empty-handle', E.snapshot(full, current, [0], [0]))
        current['opened'] = True
        fresh = E.handle(2, 1)
        expected = E.snapshot(full, current, fresh, E.view(slots, [0, 0, 0, 0]))
        cooking(control, checks, [14, list(E.POSITION)], 'new-incarnation-and-monotonic-id', expected)
        cooking(control, checks, [15, 2], 'inspect-actual-new-empty-owner', expected)
        current['opened'] = False
        cooking(control, checks, [18, 2], 'close-new-empty-owner', E.snapshot(full, current, [0], [0]))
        _, saved = physical_save(raw, path, facts, world, record, full, expected_body=C19.fresh_body())
        result = {'status': 'PASS', 'generation': A.generation_name(), 'actual_TCP': True,
            'paused': True, 'backends': 1, 'cooking_checks': checks,
            'real_incarnation_reset': True, 'save_projection': saved,
            'scope': 'Separate initially empty furnace: sole Core remove/recreate, old token refusal, monotonic menu ID, exposed inventory retention and physical old Details clearing. No preceding menu Dirty, host drain, render/OS, item/orb constructor or RNG parity claim.'}
        S.exclusive_json(directory / 'summary.json', result)
        return result
    except BaseException:
        actor.stop(failed=True)
        raise
    finally:
        actor.stop()


def fresh_directory():
    WORK.mkdir(exist_ok=True)
    for number in range(1, 10000):
        path = WORK / f'{number:03}'
        try:
            path.mkdir()
            return number, path
        except FileExistsError:
            continue
    raise RuntimeError('No unused cooking-menu directory')


def prepare(generation, *, lifecycle_only=False):
    reference = E.reference_cases()
    facts = C19.independent_expectations()
    world, record, full, slots, body, seed = (E.empty_fixture if lifecycle_only else E.fixture)(facts)
    with H.bindings(C19, {'POSITION': E.POSITION}):
        actual_world, actual_record, actual_full, actual_body, peer, pending = C19.projection(seed, facts)
    S.require(S.P.canonical_expected(actual_world) == S.P.canonical_expected(world) and
              actual_record == S.local_bytes(record) and actual_full == full and
              actual_body == body and peer == 40 and not pending, 'Independent menu seed physical roundtrip')
    number, directory = fresh_directory()
    (directory / 'seed.nbt').write_bytes(seed)
    projected = []
    for row in ([] if lifecycle_only else E.expected_steps(full)):
        closed = row['command'][0] == 18
        projected.append({'label': row['label'], 'command': row['command'],
            'snapshot': E.snapshot(row['full'], row['menu'], [0] if closed else E.handle(1),
                                   [0] if closed else E.view(row['slots'], row['timers']))})
    S.exclusive_json(directory / 'expected-steps.json', projected)
    value = {'status': 'PREPARED; native pending', 'native_executed': False,
        'actor_generation': generation, 'runtime_inputs': runtime_pins(),
        'lifecycle_only': lifecycle_only,
        'runner': R.pin(Path(__file__)), 'expectations': R.pin(Path(E.__file__)),
        'seed': R.pin(directory / 'seed.nbt'), 'steps': R.pin(directory / 'expected-steps.json'),
        'physical_position': list(E.POSITION), 'reserved_player_peer': 41,
        'raw_status': full['status'], 'equipment': full['equipment'],
        'retained_java_cases': list(reference),
        'specification_scope': 'Retained independent single-click Java cases composed with other unchanged cells. The complete sequential live-world run is not a retained Java world observation.',
        'planned_native_argv': [sys.executable, '-B', str(Path(__file__)), '--actor-generation', str(generation), '--native'],
        'optional_large_components': 'Explicit --component-overflow only, after positive/save receipt. Actual1200-effect initialized key;90s per reply/600s actor budget, failure retained. Frozen020 old-CC may be expensive.',
        'known_publication_dependency': 'Frozen020 Store.Dirty is explicitly refused by the effect publisher. The actual positive menu receipt precedes save. Empty-owner reset is a separate --lifecycle-only route with no preceding GUI Dirty; no host effect drain substitutes.',
        'unexposed': ['hidden player48..63', 'hidden furnace backing4', 'opaque recipe/context cache'],
        'separate_acceptance': ['Entry entity/RNG publications, five saves/two crashes', 'OS input/render/presenter']}
    output = ROOT / f'evidence/playable-client-cooking-menu-prepared-{number:03}.json'
    if lifecycle_only:
        value['planned_native_argv'].append('--lifecycle-only')
    R.write(directory / 'prepared.json', value, True); R.write(output, value, True)
    print(json.dumps({'status': value['status'], 'evidence': str(output)}), flush=True)


def child(directory, component_overflow, lifecycle_only):
    build = B.artifact()
    before = runtime_pins()
    journal = directory / 'owned-groups.jsonl'; journal.touch(exist_ok=False)
    bridge, _ = P.retained_bridge()
    def identity():
        S.require(R.pin(A.ACTOR) == build['binary'], 'Selected actor changed')
    with H.bindings(S, {'SERVER': A.ACTOR, 'ROOT': ROOT, 'activation': identity, 'OWNED_GROUPS': journal}):
        try:
            result = (lifecycle_scenario(directory / 'actors', A.ACTOR, bridge) if lifecycle_only else
                      scenario(directory / 'actors', A.ACTOR, bridge, component_overflow=component_overflow))
            S.require(runtime_pins() == before, 'Inputs changed during TCP menu check')
            identity()
        except BaseException as error:
            S.exclusive_json(directory / 'first-failure.json',
                             {'type': type(error).__name__, 'message': str(error)})
            raise
    print(json.dumps({'status': result['status'], 'cooking_checks': len(result['cooking_checks'])}), flush=True)


def native(component_overflow, lifecycle_only):
    build = B.artifact()
    number, directory = fresh_directory()
    before, own = runtime_pins(), R.pin(Path(__file__))
    S.exclusive_json(directory / 'inputs.json', {'binary': build['binary'], 'build': R.pin(A.WORK / 'native-build.json'),
        'source_map': build['source_map'], 'runtime': before, 'runner': own})
    bridge, _ = P.retained_bridge()
    with H.bindings(R, {'WORK': directory}):
        try:
            argv = [sys.executable, '-B', str(Path(__file__)), '--actor-generation', str(A.generation()), '--_child', str(directory)]
            if component_overflow:
                argv.append('--component-overflow')
            if lifecycle_only:
                argv.append('--lifecycle-only')
            process = R.bounded(argv, 720 if component_overflow else 300, 'execution')
        finally:
            B.descendant_cleanup(directory, bridge)
    success = process['exit_code'] == 0 and not process['timed_out']
    output = ROOT / f'evidence/playable-client-cooking-menu-native-{number:03}.json'
    value = {'status': 'PASS' if success else 'FAIL', 'binary': build['binary'],
        'process': R.pin(directory / 'execution/result.full.json'), 'cleanup': R.pin(directory / 'cleanup.json'),
        'inputs': R.pin(directory / 'inputs.json'), 'component_overflow_requested': component_overflow,
        'lifecycle_only': lifecycle_only}
    for name in ('menu-positive-summary.json', 'positive-summary.json', 'summary.json'):
        path = directory / 'actors' / name
        if path.exists():
            value[name] = json.loads(path.read_bytes())
    R.write(output, value, True)
    R.process_ok(process)
    S.require(runtime_pins() == before and R.pin(Path(__file__)) == own, 'Runner or runtime inputs changed')
    print(json.dumps({'status': value['status'], 'evidence': str(output)}), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--actor-generation', type=int, required=True)
    parser.add_argument('--expectations', action='store_true')
    parser.add_argument('--native', action='store_true')
    parser.add_argument('--component-overflow', action='store_true')
    parser.add_argument('--lifecycle-only', action='store_true')
    parser.add_argument('--_child', type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.actor_generation < 20 or sum((args.expectations, args.native, bool(args._child))) != 1:
        parser.error('explicit producer20 or later and exactly one mode required')
    if args.lifecycle_only and args.component_overflow:
        parser.error('lifecycle-only and optional component overflow are separate scenarios')
    selected = ROOT / f'build/compiler-producer-diagnostic-{args.actor_generation:03}'
    with H.bindings(A, {'WORK': selected, 'SOURCE': selected / 'source', 'ACTOR': selected / 'actor'}):
        if args._child:
            child(args._child, args.component_overflow, args.lifecycle_only)
        elif args.native:
            native(args.component_overflow, args.lifecycle_only)
        else:
            prepare(args.actor_generation, lifecycle_only=args.lifecycle_only)


if __name__ == '__main__':
    main()
