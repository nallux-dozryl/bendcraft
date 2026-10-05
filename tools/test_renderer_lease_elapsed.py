#!/usr/bin/env python3
"""Consume one explicit actor artifact through real idle/EOF lease boundaries.

No builder, clock substitution, timer hooks, or gameplay implementation here.
The normal ambient cooking caller is exercised separately by Catalog's runner.
"""
from __future__ import annotations

import argparse
import json
import socket
import sys
import time
from pathlib import Path

import test_playable_client_actor004_boundary as B
import test_playable_client_actor004_motion as Motion

A, P, R, S, H = B.A, B.P, B.R, B.S, B.H
ROOT = A.ROOT


def select(generation):
    A.WORK = ROOT / f'build/compiler-producer-diagnostic-{generation:03}'
    A.SOURCE, A.ACTOR = A.WORK / 'source', A.WORK / 'actor'


def held(client, expected, label, checks, *, wait_seconds=0):
    # Inspect the actual Receiver after its next scheduled physics tick; the
    # saved record's keys alone do not expose a newly released controller.
    started = time.monotonic()
    observations = []
    while True:
        client.call('simulation.step', {'ticks': 1})
        record = S.decode_local(bytes(client.call('player.inspect', {})['nbt_bytes']))
        observations.append({'keys': list(record.keys), 'count': record.count,
                             'host_seconds': time.monotonic() - started})
        if record.keys == expected:
            break
        S.require(time.monotonic() - started < wait_seconds,
                  label + ': next Receiver keys differ')
        time.sleep(.02)
    checks.append({'label': label, 'observations': observations})


def scenario(directory, binary):
    directory.mkdir(exist_ok=False)
    _, records = Motion.original_case()
    _, identity, count = B.palette_and_registry()
    world = S.scene_world(count, identity)
    path = directory / 'world.nbt'
    path.write_bytes(S.bundle_bytes(world, 40, records[0]))
    initial = R.pin(path)
    actor = A.PlayableBackend(directory / 'actor', binary, path, Path('/dev/null'),
                              lifetime_seconds=100)
    checks, timings = [], []
    try:
        public, _ = actor.tcp(True)
        control = B.connect(actor)
        first_epoch = control.epoch
        control.call(Motion.packet(1))
        held(public, (1, 0, 0, 0, 0, 0, 0), 'actual W held before idle', checks)

        # Actual socket deadline is renewed on successful send. Host time is
        # measured after receiving the ACK, so this bounds observed closure;
        # it is not a timestamp inside the actor or an immediate-release claim.
        control.call(Motion.packet(1))
        started = time.monotonic()
        control.socket.settimeout(4.2)
        try:
            premature = control.socket.recv(1)
        except socket.timeout:
            premature = None
        S.require(premature is None, 'Private socket closed before 4.2s idle observation')
        control.socket.settimeout(6)
        S.require(control.socket.recv(1) == b'', 'Actual private idle timeout did not close socket')
        elapsed = time.monotonic() - started
        S.require(4.5 <= elapsed < 10.2, 'Observed idle EOF outside bounded interval')
        timings.append({'label': 'real monotonic idle socket EOF', 'host_seconds_after_ACK': elapsed})
        held(public, (0,) * 7, 'idle disconnect releases actual next-tick controls', checks,
             wait_seconds=3)
        control.close()

        control = B.connect(actor)
        S.require(control.epoch != first_epoch, 'Timeout reacquisition reused epoch')
        control.call(Motion.packet(1))
        held(public, (1, 0, 0, 0, 0, 0, 0), 'reacquired owner can hold W', checks)
        eof_epoch = control.epoch
        started = time.monotonic()
        control.socket.shutdown(socket.SHUT_RDWR)
        control.close()
        # Observe before Hello, which independently releases controls itself.
        held(public, (0,) * 7, 'EOF disconnect releases actual next-tick controls', checks,
             wait_seconds=3)
        control = B.connect(actor)
        timings.append({'label': 'EOF release and fresh lease reacquisition',
                        'host_seconds': time.monotonic() - started})
        S.require(control.epoch != eof_epoch, 'EOF reacquisition reused epoch')

        # An old unassigned connection cannot disconnect the newly assigned
        # owner. No incoming epoch is used as cleanup authority.
        control.call(Motion.packet(1))
        B.peer_fault(actor, [1, 1, eof_epoch, 1, [2]],
                     [1, 3, eof_epoch, 1, 'Wire:SocketEpoch'], directory, 'old-socket-epoch')
        B.peer_fault(actor, [1, 0, 'wrong-test-capability'],
                     [1, 3, '', 0, 'RendererAuthenticationFailed'], directory, 'bad-capability')
        time.sleep(.1)
        control.call([15, 0], 8)
        held(public, (1, 0, 0, 0, 0, 0, 0), 'foreign EOF preserves new owner controls', checks)

        # Twelve seconds exceed the old nominal five-second pulse budget.
        # Actual pulse counts are unexposed; the real paused timer stays active.
        # Every request goes through the actual actor's sequence admission.
        started = time.monotonic()
        heartbeats = 0
        while time.monotonic() - started < 12:
            inspected = control.call([15, 0], 8)
            S.require(inspected[4] is True, 'Closed CookingInspect0 authority refused')
            control.call([1, [True, False, []]])
            heartbeats += 1
            time.sleep(.2)
        timings.append({'label': 'actual CookingInspect/Input continuation',
                        'host_seconds': time.monotonic() - started,
                        'inspect_input_pairs': heartbeats})

        # A replay is still refused by the original next-sequence guard and its
        # socket cleanup releases controls. Gameplay success is not fabricated.
        replay_sequence = control.sequence
        control.call([1, [True, True, [[1, True, [0, 119, True]]]]])
        replay = control.exchange([1, 1, control.epoch, replay_sequence,
                                   [1, [True, True, []]]])
        S.require(replay == [1, 3, control.epoch, replay_sequence, 'RendererLeaseOrSequence'],
                  'Replay guard changed')
        control.socket.settimeout(5)
        S.require(control.socket.recv(1) == b'', 'Replay fault did not close old socket')
        held(public, (0,) * 7, 'replay fault disconnect releases controls', checks, wait_seconds=3)
        control.close()
        control = B.connect(actor)
        control.call(Motion.packet(1))
        future = control.sequence + 1
        skipped = control.exchange([1, 1, control.epoch, future, [2]])
        S.require(skipped == [1, 3, control.epoch, future, 'RendererLeaseOrSequence'],
                  'Skipped sequence guard changed')
        control.socket.settimeout(5)
        S.require(control.socket.recv(1) == b'', 'Skipped sequence did not close old socket')
        held(public, (0,) * 7, 'skipped sequence disconnect releases controls', checks, wait_seconds=3)
        S.require(R.pin(path) == initial, 'Unsaved lease tests published durable world bytes')
    except BaseException:
        actor.stop(failed=True)
        raise
    finally:
        actor.stop()
    summary = {'status': 'PASS', 'checks': checks, 'timings': timings,
               'scope': 'Real private TCP idle/EOF/replay and epoch isolation; actual next scheduled Receiver tick observes control release. All simulation pulses remain enabled. Paused heartbeat continuation is not ambient cooking completion or a direct measurement of old pulse backlog. Actor mailbox serializes release; immediate wall-time control release is unclaimed.'}
    S.exclusive_json(directory / 'summary.json', summary)
    return summary


def child(directory):
    build = B.artifact()
    journal = directory / 'owned-groups.jsonl'
    journal.touch(exist_ok=False)
    def identity():
        S.require(R.pin(A.ACTOR) == build['binary'], 'Selected actor changed')
    with H.bindings(S, {'SERVER': A.ACTOR, 'ROOT': ROOT, 'activation': identity,
                        'OWNED_GROUPS': journal}):
        try:
            result = scenario(directory / 'actors', A.ACTOR)
        except BaseException as error:
            S.exclusive_json(directory / 'first-failure.json',
                             {'type': type(error).__name__, 'message': str(error)})
            raise
    print(json.dumps({'status': result['status'], 'checks': len(result['checks'])}), flush=True)


def native(generation):
    build = B.artifact()
    number = 1
    while (ROOT / f'build/renderer-lease-elapsed/native-{number:03}').exists():
        number += 1
    directory = ROOT / f'build/renderer-lease-elapsed/native-{number:03}'
    directory.mkdir(parents=True, exist_ok=False)
    own = R.pin(Path(__file__))
    S.exclusive_json(directory / 'inputs.json', {'binary': build['binary'],
                     'build': R.pin(A.WORK / 'native-build.json'), 'runner': own})
    with H.bindings(R, {'WORK': directory}):
        try:
            receipt = R.bounded([sys.executable, '-B', str(Path(__file__)),
                '--actor-generation', str(generation), '--_child', str(directory)], 130, 'execution')
        finally:
            B.descendant_cleanup(directory, Path('/dev/null'))
    passed = receipt['exit_code'] == 0 and not receipt['timed_out']
    evidence = {'status': 'PASS' if passed else 'FAIL', 'actor_generation': generation,
                'binary': build['binary'], 'inputs': R.pin(directory / 'inputs.json'),
                'process': R.pin(directory / 'execution/result.full.json'),
                'cleanup': R.pin(directory / 'cleanup.json')}
    if passed:
        evidence['result'] = json.loads((directory / 'actors/summary.json').read_bytes())
    else:
        evidence['failure'] = R.pin(directory / 'first-failure.json') if (directory / 'first-failure.json').exists() else None
    S.require(R.pin(Path(__file__)) == own, 'Consumer changed during execution')
    output = ROOT / f'evidence/renderer-lease-elapsed-native-{number:03}.json'
    R.write(output, evidence, True)
    R.process_ok(receipt)
    print(json.dumps({'status': 'PASS', 'evidence': str(output)}), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--actor-generation', type=int, required=True)
    parser.add_argument('--native', action='store_true')
    parser.add_argument('--_child', type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.actor_generation != 23 or bool(args.native) == bool(args._child):
        parser.error('explicit --actor-generation 23 and exactly one execution mode required')
    select(args.actor_generation)
    child(args._child) if args._child else native(args.actor_generation)


if __name__ == '__main__':
    main()
