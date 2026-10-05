#!/usr/bin/env python3
"""Actual actor022 cooking shutdown acceptance; reuses bounded socket owners."""
from __future__ import annotations

import argparse
import copy
import json
import os
import subprocess
import sys
from pathlib import Path

import test_playable_client_cooking_publication as Pub

Menu, A, B, P, R, S, H = Pub.Menu, Pub.A, Pub.B, Pub.P, Pub.R, Pub.S, Pub.H
ROOT = Pub.ROOT
WORK = ROOT / 'build/playable-client-cooking-close'
CLOSE = ROOT / 'tools/play_minecraft_close.py'


def release(actor, control):
    control.call([2])
    control.close()
    actor.private = None


def shutdown(actor, path, directory, label, *, success):
    env = dict(os.environ, MC_RENDER_PORT=str(actor.private_port),
               MC_RENDER_TOKEN=actor.token, MC_LIVE_PORT=str(actor.port),
               MC_DEV_TOKEN=S.MCP.TOKEN, MC_WORLD_PATH=str(path), MC_COOKING_PROTOCOL='1')
    result = subprocess.run([sys.executable, '-B', str(CLOSE)], cwd=ROOT, env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=25)
    (directory / (label + '.stdout')).write_bytes(result.stdout)
    (directory / (label + '.stderr')).write_bytes(result.stderr)
    rows = [json.loads(line) for line in result.stdout.splitlines() if line.startswith(b'{')]
    S.require(result.returncode == (0 if success else 1), 'Actual shutdown exit: ' + label)
    return rows


def scenario(directory, *, capacity):
    directory.mkdir(exist_ok=False)
    facts = Pub.C19.independent_expectations()
    world, record, full, slots, bodies, seed = Pub.fixture(facts)
    if capacity:
        full = copy.deepcopy(full)
        full['main']['slots'] = [B.stack('minecraft:stone', 64) for _ in range(36)]
        seed = Pub.bundle(world, 40, record, full, bodies, (), None, (),
                          Pub.J.encode_publication(Pub.counters(), 0, (), None, Pub.catalog()))
    path = directory / 'world.nbt'
    path.write_bytes(seed)
    bridge, _ = P.retained_bridge()
    actor = A.PlayableBackend(directory / 'actor', A.ACTOR, path, bridge, lifetime_seconds=180)
    checks = []
    try:
        raw, ping = actor.tcp(True)
        S.require(ping['peer'] == 42, 'Actual durable peer allocation')
        control = Menu.connect(actor)
        current = B.empty_menu()
        current['opened'] = True
        opened = Pub.handle(1, 0, 41)
        furnace = Menu.E.view(slots, [0, 10, 0, 200])
        Menu.cooking(control, checks, [14, list(Pub.POSITIONS[0])], 'actual-open',
                     Menu.E.snapshot(full, current, opened, furnace))
        changed = [B.stack('minecraft:beef', 1), B.stack('minecraft:coal', 2), None]
        current.update(carried=B.stack('minecraft:beef', 1), revision=1)
        before = Menu.E.snapshot(full, current, opened, Menu.E.view(changed, [0, 10, 0, 200]))
        Menu.cooking(control, checks, [16, 1, 0, 1], 'actual-carried-beef', before)
        release(actor, control)
        rows = shutdown(actor, path, directory, 'opened-close', success=not capacity)
        S.require([row['event'] for row in rows] == (
            ['client.cooking-inspect', 'client.cooking-close'] if capacity else
            ['client.cooking-inspect', 'client.cooking-close', 'client.menu-close', 'client.save']),
            'Actual shutdown event order')
        S.require(rows[0]['sequence'] == 1 and rows[0]['cooking'] == before and rows[0]['accepted'],
                  'Exact inspect of actual open cooking handle/carried owner')
        if capacity:
            S.require(rows[1]['sequence'] == 2 and rows[1]['accepted'] is False and
                      rows[1]['message'] == 'cooking-menu:close-needs-real-drop-owner' and
                      rows[1]['cooking'] == [opened, [0], B.authority(full, current)],
                      'Full-inventory genuine close refusal retains complete inventory/handle')
            S.require(path.read_bytes() == seed and actor.process.poll() is None,
                      'Refusal performs no save and leaves actual actor running')
            control = Menu.connect(actor)
            Menu.cooking(control, checks, [15, 0], 'same-actor-reconnect', before)
            # Restore the actual carried beef to the actual input; no host owner repair.
            current.update(carried=None, revision=2)
            Menu.cooking(control, checks, [16, 1, 0, 0], 'real-recovery-deposit',
                         Menu.E.snapshot(full, current, opened, furnace))
            release(actor, control)
            rows = shutdown(actor, path, directory, 'recovered-close', success=True)
            expected_bodies = bodies
            expected_revision = 2
        else:
            full['main']['slots'][1] = B.stack('minecraft:beef', 1)
            expected_bodies = tuple((point, Pub.physical(facts, changed) if point == Pub.POSITIONS[0] else body)
                                    for point, body in bodies)
            expected_revision = 2
        expected_menu = B.empty_menu()
        expected_menu['revision'] = expected_revision
        closed = Menu.E.snapshot(full, expected_menu, [0], [0])
        S.require(rows[1]['sequence'] == 2 and rows[1]['accepted'] is True and
                  rows[1]['cooking'] == closed and rows[2]['sequence'] == 3 and
                  rows[2]['menu'] == B.authority(full, expected_menu),
                  'Complete actual CookingClose then MenuClose return authority')
        saved = path.read_bytes()
        actual = Pub.projection(saved, facts)
        S.require(actual['full'] == full and actual['player'] == S.local_bytes(record) and
                  S.P.canonical_expected(actual['world']) == S.P.canonical_expected(world) and
                  actual['bodies'] == expected_bodies and actual['highwater'] == 43 and
                  not actual['clock_inputs'] and not actual['effects'] and
                  actual['publication']['incarnations'] == Pub.counters(),
                  'Complete independently reconstructed durable Core/player/43 cells/Details/publication')
        S.require(rows[-1]['result'] == {'status': 'durable', 'published': True, 'durable': True,
                                      'bytes': len(saved), 'peer_highwater': 43},
                  'Exact actual helper durable acknowledgement')
        # A second helper invocation exercises the genuine already-closed route.
        second = shutdown(actor, path, directory, 'already-closed', success=True)
        S.require([row['event'] for row in second] ==
                  ['client.cooking-inspect', 'client.menu-close', 'client.save'] and
                  second[0]['cooking'] == closed and second[1]['sequence'] == 2,
                  'Already-closed cooking route skips CookingClose')
        again = Pub.projection(path.read_bytes(), facts)
        S.require({key: value for key, value in again.items() if key != 'highwater'} ==
                  {key: value for key, value in actual.items() if key != 'highwater'} and
                  again['highwater'] == 44, 'Second helper save changes only allocated public highwater')
        summary = {'status': 'PASS', 'capacity': capacity, 'checks': checks,
                   'same_actor_recovery': capacity, 'complete_durable_owner_equal': True,
                   'helper_events': [row['event'] for row in rows], 'saved': R.pin(path),
                   'scope': 'Actual production actor/menu TCP and shutdown helper; no renderer or OS input claim.'}
        S.exclusive_json(directory / 'summary.json', summary)
        return summary
    except BaseException:
        actor.stop(failed=True)
        raise
    finally:
        actor.stop()


def stale_scenario(directory):
    directory.mkdir(exist_ok=False)
    facts = Pub.C19.independent_expectations()
    world, record, full, slots, bodies, seed = Pub.fixture(facts, empty=True)
    path = directory / 'world.nbt'
    path.write_bytes(seed)
    actor = A.PlayableBackend(directory / 'actor', A.ACTOR, path, P.retained_bridge()[0],
                              lifetime_seconds=180)
    checks = []
    try:
        raw, _ = actor.tcp(True)
        control = Menu.connect(actor)
        current = B.empty_menu()
        current['opened'] = True
        opened = Pub.handle(1, 0, 41)
        Menu.cooking(control, checks, [14, list(Pub.POSITIONS[0])], 'open-empty-owner',
                     Menu.E.snapshot(full, current, opened, Menu.E.view(slots, [0, 0, 0, 0])))
        # Carry a real durable stack while the empty furnace is replaced.
        full['main']['slots'][0] = None
        current.update(carried=B.stack('minecraft:dirt', 13), revision=1)
        Menu.cooking(control, checks, [16, 1, 30, 0], 'actual-carried-main-stack',
                     Menu.E.snapshot(full, current, opened, Menu.E.view(slots, [0, 0, 0, 0])))
        for state in (facts['palette']['minecraft:air'], facts['unlit']):
            S.queue_set(raw, world, Pub.POSITIONS[0], state, world['tick'] + 1)
        raw.call('simulation.step', {'ticks': 1})
        S.BASE.apply_tick(world)
        record = Menu.inspect_record(raw)
        S.require(record.count == 1 and raw.call('world.clock') == S.P.clock(world),
                  'Actual remove/recreate and sole player/Core tick')
        refused = Menu.E.snapshot(full, current, opened, [0])
        Menu.cooking(control, checks, [15, 0], 'actual-stale-handle-inspect', refused,
                     accepted=False, message='cooking-menu:authority-menu-range-or-incarnation-refused')
        release(actor, control)
        rows = shutdown(actor, path, directory, 'stale-inspect-close', success=True)
        full['main']['slots'][0] = B.stack('minecraft:dirt', 13)
        closed_menu = B.empty_menu()
        closed_menu['revision'] = 2
        closed = Menu.E.snapshot(full, closed_menu, [0], [0])
        S.require([row['event'] for row in rows] == ['client.cooking-inspect',
                  'client.cooking-close', 'client.menu-close', 'client.save'] and
                  rows[0]['accepted'] is False and rows[0]['cooking'] == refused and
                  rows[1]['sequence'] == 2 and rows[1]['accepted'] is True and
                  rows[1]['cooking'] == closed and rows[2]['menu'] == B.authority(full, closed_menu),
                  'Refused discovery still closes actual retained handle and returns carried item')
        actual = Pub.projection(path.read_bytes(), facts)
        # Store.change_go preserves other entries and inserts a newly found
        # position at its Nil tail, so remove/recreate moves this body last.
        expected_bodies = tuple((point, body) for point, body in bodies if point != Pub.POSITIONS[0]) + (
                                (Pub.POSITIONS[0], Pub.C19.fresh_body()),)
        incarnations = Pub.map_tree([(Pub.J.words('/'.join((point[0], *map(str, point[1:])))), count)
                    for point, count in zip(Pub.POSITIONS, (4, 5), strict=True)] +
                    [(Pub.J.words(Pub.REMOVED), 9)])
        S.require(actual['full'] == full and actual['player'] == S.local_bytes(record) and
                  S.P.canonical_expected(actual['world']) == S.P.canonical_expected(world) and
                  actual['bodies'] == expected_bodies and actual['highwater'] == 43 and
                  not actual['effects'] and not actual['clock_inputs'] and
                  actual['publication']['incarnations'] == incarnations and
                  not actual['entities']['records'], 'Full durable state after genuine incarnation replacement')
        summary = {'status': 'PASS', 'checks': checks, 'discovery_refused_close_accepted': True,
                   'actual_carried_stack_returned': True, 'actual_incarnation': 4,
                   'saved': R.pin(path),
                   'scope': 'Actual stale-target discovery, authenticated close, carried return and complete physical save reconstruction. Entity owner has no records; no new entity RNG oracle or OS input claim.'}
        S.exclusive_json(directory / 'summary.json', summary)
        return summary
    except BaseException:
        actor.stop(failed=True)
        raise
    finally:
        actor.stop()


def run_child(directory, *, stale_only=False):
    build = Pub.artifact()
    journal = directory / 'owned-groups.jsonl'
    journal.touch(exist_ok=False)
    with H.bindings(S, {'SERVER': A.ACTOR, 'ROOT': ROOT, 'OWNED_GROUPS': journal,
                        'activation': lambda: S.require(R.pin(A.ACTOR) == build['binary'], 'Actor pin drift')}):
        try:
            result = ({'status': 'PASS', 'stale': stale_scenario(directory / 'stale')} if stale_only else
                      {'status': 'PASS', 'return': scenario(directory / 'return', capacity=False),
                       'capacity': scenario(directory / 'capacity', capacity=True)})
            S.exclusive_json(directory / 'summary.json', result)
        except BaseException as error:
            S.exclusive_json(directory / 'first-failure.json',
                             {'type': type(error).__name__, 'message': str(error)})
            raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--_child', type=Path, help=argparse.SUPPRESS)
    parser.add_argument('--stale-only', action='store_true')
    args = parser.parse_args()
    selected = ROOT / 'build/compiler-producer-diagnostic-022'
    with H.bindings(A, {'WORK': selected, 'SOURCE': selected / 'source', 'ACTOR': selected / 'actor'}):
        if args._child:
            run_child(args._child, stale_only=args.stale_only)
            return
        WORK.mkdir(exist_ok=True)
        index = next(i for i in range(1, 10000) if not (WORK / f'{i:03}').exists())
        directory = WORK / f'{index:03}'
        directory.mkdir()
        build = Pub.artifact()
        before = R.pin(CLOSE)
        bridge, _ = P.retained_bridge()
        with H.bindings(R, {'WORK': directory}):
            try:
                argv = [sys.executable, '-B', str(Path(__file__)), '--_child', str(directory)]
                if args.stale_only:
                    argv.append('--stale-only')
                process = R.bounded(argv, 300, 'execution')
            finally:
                B.descendant_cleanup(directory, bridge)
        result = {'status': 'PASS' if process['exit_code'] == 0 else 'FAIL',
                  'actor': build['binary'], 'helper': before,
                  'process': R.pin(directory / 'execution/result.full.json'),
                  'cleanup': R.pin(directory / 'cleanup.json')}
        for name in ('summary.json', 'first-failure.json'):
            if (directory / name).exists():
                result[name] = json.loads((directory / name).read_bytes())
        output = ROOT / f'evidence/playable-client-cooking-close-native-{index:03}.json'
        R.write(output, result, True)
        R.process_ok(process)
        S.require(R.pin(CLOSE) == before, 'Helper changed during native acceptance')
        print(json.dumps({'status': result['status'], 'evidence': str(output)}), flush=True)


if __name__ == '__main__':
    main()
