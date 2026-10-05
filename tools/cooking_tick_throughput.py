#!/usr/bin/env python3
"""Bounded actor-only cooking throughput; no renderer, compiler or OS input.

Each generation consumes the same already initialized production demo save.
Actual menu commands supply beef/fuel, and paused simulation.step batches run
the production tick facade. Elapsed RPC batches are throughput observations,
not ambient cadence, drawing, input latency or whole-game benchmarks.
"""
from __future__ import annotations

import argparse
import copy
import json
import os
import sys
import time
from pathlib import Path

PYTHON = Path.home()/'.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3'
if Path(sys.executable).resolve() != PYTHON.resolve():
    os.execv(str(PYTHON), [str(PYTHON), '-B', __file__, *sys.argv[1:]])
sys.dont_write_bytecode = True

import generic_resource_world_sample_cooking_runtime as C

G, Pub, B, A, Menu, S, R, Host, Pair = C.G, C.Pub, C.B, C.A, C.Menu, C.S, C.R, C.Host, C.Pair
ROOT = C.ROOT
SEED = ROOT/'build/cooking-demo.1bCC7c/world.nbt'
SEED_SHA = '517d8848128a5f7432232a3bd5fb57bb3df82f031c68ebd6700964b7b9a3d039'
require = C.require


def initialized_seed():
    require(C.pin(SEED)['sha256'] == SEED_SHA, 'Accepted initialized demo save changed')
    facts = Pub.C19.independent_expectations()
    data = C.publication_projection(SEED.read_bytes(), facts)
    require(data['world']['paused'] and data['world']['tick'] == 213
            and data['highwater'] == 44 and len(data['world']['sections']) == 104,
            'Actual initialized full104/tick213/paused/highwater44 fixture')
    require(data['full']['main']['slots'][:2] == [B.stack('minecraft:beef', 2), B.stack('minecraft:coal', 2)]
            and all(x is None for x in data['full']['main']['slots'][2:])
            and all(x is None for x in data['full']['equipment']), 'Actual complete43 ingredient fixture')
    require(data['bodies'] == ((C.POINT, Pub.physical(facts, [None]*3, total=0, lit_total=0)),)
            and data['effects'] == () and data['clock_inputs'] == ()
            and data['publication']['journal'] == {'sequence': 0, 'unsaved': (), 'last': None},
            'Actual empty furnace and initialized physical owners')
    return facts, data


def expected_slots(ticks):
    cooked = min(2, ticks//200)
    return [B.stack('minecraft:beef', 2-cooked) if cooked < 2 else None,
            B.stack('minecraft:coal', 1) if ticks else B.stack('minecraft:coal', 2),
            B.stack('minecraft:cooked_beef', cooked) if cooked else None]


def expected_timers(ticks):
    return [1601-ticks, 1600, ticks % 200 if ticks < 400 else 0, 200] if ticks else [0, 0, 0, 200]


def check_snapshot(snapshot, full, current, local_peer, slots, timers):
    require(snapshot[0] == [1, 1, local_peer, list(C.POINT), 'minecraft:furnace', 0, 3],
            'Complete current furnace handle/owner/incarnation')
    require(snapshot[1] == Menu.E.view(slots, timers)
            and snapshot[2] == B.authority(full, current), 'Complete furnace/full43/temp/menu authority')


def release(actor, control):
    control.call([2])
    control.close()
    actor.private = None


def inspect(actor, full, current, local_peer, ticks):
    control = Menu.connect(actor)
    actor.private = control
    try:
        reply = control.call([15, 1], 8)
        require(reply[4:6] == [True, ''], 'Accepted actual cooking inspection')
        check_snapshot(reply[6], full, current, local_peer, expected_slots(ticks), expected_timers(ticks))
    finally:
        release(actor, control)


def expected_world(initial, ticks, facts):
    world = copy.deepcopy(initial)
    for _ in range(ticks):
        S.BASE.apply_tick(world)
    S.BASE.set_block(world, *C.POINT[1:], facts['lit'])
    world['revision'] += 1
    world['events'].insert(0, {'stamp': (initial['tick']+1, 0, world['revision']),
                              'kind': 0, 'revision': world['revision']})
    # The retained ignition event contributes peer0 to the codec projection.
    world['max_peer'] = 0
    return world


def expected_body(facts, ticks):
    root = S.N.parse(Pub.physical(facts, expected_slots(ticks), progress=0,
                    remaining=1601-ticks, total=200, lit_total=1600))
    used = S.WC.compound([('minecraft:cooked_beef', S.WC.integer(2))])
    members = tuple((name, used if name == S.N.text('RecipesUsed') else value)
                    for name, value in root.value.payload)
    return S.N.encode_root(S.N.RootTag(root.name, S.N.Value(10, members)))


def fresh_directory():
    parent = ROOT/'build/cooking-tick-throughput'
    parent.mkdir(exist_ok=True)
    for number in range(1, 10000):
        path = parent/f'{number:03d}'
        try:
            path.mkdir()
            return path
        except FileExistsError:
            pass
    raise AssertionError('No new throughput attempt directory')


def native(directory, generation, comparison):
    facts, initial = initialized_seed()
    work = ROOT/f'build/compiler-producer-diagnostic-{generation:03d}'
    actor = None
    error = None
    rows, setup = [], []
    summary = {'status': 'RUNNING', 'generation': generation, 'helper': C.pin(__file__),
               'fixture': C.pin(SEED), 'bounds': {'startup_seconds': 120, 'actor_lifetime_seconds': 300,
                 'public_response_seconds': 45, 'batch_ticks': 50, 'cooking_ticks': 400, 'post_cooking_ticks': 100},
               'scope': 'Actual paused production simulation.step RPC throughput. No renderer, trace-image I/O, '
                        'ambient cadence, hardware input or whole-game speed claim.'}
    with Host.bindings(A, {'WORK': work, 'SOURCE': work/'source', 'ACTOR': work/'actor'}):
        artifact = B.artifact()
        summary['artifact'] = artifact['binary']
        with Host.bindings(R, {'WORK': directory, 'GROUPS': directory/'owned-groups.ndjson'}), \
             Host.bindings(Pair, {'WORK': directory}), \
             Host.bindings(G, {'BACKEND_LIFETIME_SECONDS': 300}):
            try:
                path = directory/'world.nbt'
                path.write_bytes(SEED.read_bytes())
                actor = G.backend(A.ACTOR, 'actor-throughput', path)
                raw, ping = actor.tcp(True)
                require(ping['peer'] == 46, 'Initialized44 reserves local45/public46')
                raw.socket.settimeout(45)
                require(raw.call('world.clock') == S.P.clock(initial['world']), 'Exact initial paused Core')
                require(S.local_bytes(Menu.inspect_record(raw)) == initial['player'], 'Complete cold LocalPlayer retention')
                full, current = copy.deepcopy(initial['full']), B.empty_menu()
                control = Menu.connect(actor)
                actor.private = control
                reply = control.call([14, list(C.POINT)], 8)
                require(reply[4:6] == [True, ''], 'Actual resident CookingOpen')
                current['opened'] = True
                check_snapshot(reply[6], full, current, 45, [None]*3, [0]*4)
                slots = [None]*3
                for label, logical, carried, family, offset, item, timers in (
                    ('pick-beef', 30, B.stack('minecraft:beef', 2), 'main', 0, None, [0]*4),
                    ('put-input', 0, None, 'furnace', 0, B.stack('minecraft:beef', 2), [0, 0, 0, 200]),
                    ('pick-coal', 31, B.stack('minecraft:coal', 2), 'main', 1, None, [0, 0, 0, 200]),
                    ('put-fuel', 1, None, 'furnace', 1, B.stack('minecraft:coal', 2), [0, 0, 0, 200])):
                    current.update(carried=carried, revision=current['revision']+1)
                    (full['main']['slots'] if family == 'main' else slots)[offset] = item
                    want = Menu.E.snapshot(full, current, [1, 1, 45, list(C.POINT), 'minecraft:furnace', 0, 3],
                                           Menu.E.view(slots, timers))
                    Menu.cooking(control, setup, [16, 1, logical, 0], label, want)
                release(actor, control)
                for phase, count in (('cooking', 8), ('input-empty', 2)):
                    for _ in range(count):
                        before = raw.call('world.clock')
                        started = time.monotonic()
                        after = raw.call('simulation.step', {'ticks': 50})
                        seconds = time.monotonic()-started
                        ticks = after['tick']-initial['world']['tick']
                        require(after['tick'] == before['tick']+50 and after['paused'], 'Exactly50 actual paused production ticks')
                        inspect(actor, full, current, 45, ticks)
                        row = {'phase': phase, 'start_tick': before['tick'], 'end_tick': after['tick'],
                               'seconds': seconds, 'ticks_per_second': 50/seconds}
                        rows.append(row)
                        G.exclusive(directory/f'batch-{len(rows):02d}.json', row)
                        print(json.dumps(row, separators=(',', ':')), flush=True)
                control = Menu.connect(actor)
                actor.private = control
                closed = control.call([18, 1], 8)
                # Returning an empty carried stack does not mutate inventory.
                current['opened'] = False
                require(closed[4:] == [True, '', [[0], [0], B.authority(full, current)]], 'Actual empty-carried cooking Close')
                release(actor, control)
                observed_player = S.local_bytes(Menu.inspect_record(raw))
                receipt = raw.call('world.save', {})
                require(receipt['status'] == 'durable' and receipt['published'] and receipt['durable'], 'Typed durable publication')
                final = C.publication_projection(path.read_bytes(), facts)
                require(final['world'] == expected_world(initial['world'], 500, facts)
                        and final['full'] == full and final['player'] == observed_player
                        and final['bodies'] == ((C.POINT, expected_body(facts, 500)),)
                        and final['highwater'] == 46 and final['effects'] == () and final['clock_inputs'] == ()
                        and final['entities'] == initial['entities']
                        and final['publication']['incarnations'] == initial['publication']['incarnations']
                        and final['publication']['journal']['unsaved'] == (),
                        'Full104/Core/full43/LocalPlayer/Details/entityRNG/incarnations/clean journal save')
                summary.update(status='PASS_NARROW', batches=rows, setup=setup, final_save=C.pin(path),
                               full_owner_checks=True, typed_save=receipt)
                if comparison is not None:
                    baseline = json.loads(comparison.read_bytes())
                    require(baseline['status'] in ('PASS_NARROW', 'PASS_TIMED_STAGE_NARROW')
                            and baseline['fixture'] == summary['fixture'],
                            'Accepted identical initialized comparison fixture')
                    require([(v['phase'], v['start_tick'], v['end_tick']) for v in baseline['batches']]
                            == [(v['phase'], v['start_tick'], v['end_tick']) for v in rows],
                            'Identical actual timed production clock ranges')
                    prior = baseline['final_save']
                    if prior is not None:
                        require(C.pin(prior['path']) == prior and path.read_bytes() == Path(prior['path']).read_bytes(),
                                'Exact complete durable owner bytes across artifacts')
                    else:
                        require(baseline['status'] == 'PASS_TIMED_STAGE_NARROW' and baseline['full_menu_tick_checks'],
                                'Explicit retained baseline timed-stage qualification')
                    summary['comparison'] = {'summary': C.pin(comparison), 'timed_clock_and_full_menu_checks_match': True,
                        'complete_saved_bytes_equal': True if prior is not None else None,
                        'limits': None if prior is not None else 'Baseline durable-save stage unexecuted after retained host Close-revision assertion; no full saved-byte equality claim.'}
            except BaseException as cause:
                error = cause
                summary.update(status='FAIL', batches=rows, setup=setup,
                               error={'type': type(cause).__name__, 'message': str(cause)})
            finally:
                if actor is not None:
                    try:
                        R.finish_backend(actor)
                    except BaseException as cleanup:
                        if error is None:
                            error = cleanup
                            summary.update(status='FAIL', error={'type': type(cleanup).__name__, 'message': str(cleanup)})
                G.sweep_owned(directory)
                G.exclusive(directory/'summary.json', summary)
    if error is not None:
        raise error
    return summary


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--actor-generation', type=int, default=23)
    parser.add_argument('--native', action='store_true')
    parser.add_argument('--compare-to', type=Path)
    args = parser.parse_args()
    directory = fresh_directory()
    initialized_seed()
    G.exclusive(directory/'prepared.json', {'status': 'PREPARED', 'helper': C.pin(__file__),
        'fixture': C.pin(SEED), 'actor_generation': args.actor_generation, 'native_processes': 0})
    if args.native:
        result = native(directory, args.actor_generation, args.compare_to)
        print(json.dumps({'directory': str(directory), 'status': result['status']}, separators=(',', ':')))
    else:
        print(json.dumps({'directory': str(directory), 'status': 'PREPARED'}, separators=(',', ':')))


if __name__ == '__main__':
    main()
