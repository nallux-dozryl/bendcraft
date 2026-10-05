#!/usr/bin/env python3
"""Narrow real furnace/menu and campfire-use Dirty-source consumers."""
from __future__ import annotations
import argparse
import json
import shutil
from pathlib import Path
import test_player_cooking_menu as M

B, ROOT = M.B, M.ROOT


def run(generation, phase):
    work = ROOT / 'build/player-cooking-menu-owned-dirty' / f'{generation:03}'
    work.mkdir(parents=True, exist_ok=True)
    M.WORK = work; B.WORK = work
    M.Context.WORK = work / 'context'
    if phase != 'compare':
        M.Context.prepare()
    names = ('input-right-take', 'input-right-put', 'quick-output-reverse',
             'quick-hotbar-other-main', 'refusal-budget', 'refusal-incarnation',
             'campfire-0-0-place', 'campfire-0-0-budget',
             'campfire-hands-main-pass-offhand')
    available = {row['case']['id']: row for row in M.fixtures()}
    rows = [available[name] for name in names]
    if phase == 'compare':
        assert rows == json.loads((work / 'cases.json').read_bytes()), 'retained input cases changed'
    else:
        (work / 'cases.json').write_text(json.dumps(rows, indent=2) + '\n')
    inputs = json.loads((work / 'context/input.json').read_bytes())
    reference = json.loads((ROOT / 'reference/cooking_world.json').read_bytes())
    def source(state):
        binding = next(row for row in reference['bindings'] if row['state'] == state)
        return dict(dimension='minecraft:overworld', x=0, y=0, z=0,
            state=binding['state'], block=binding['block'], family=binding['family'],
            lit=binding['lit'], dark_state=binding['unlit_state'], lit_state=binding['lit_state'], incarnation=2)
    expected_source = source(inputs['states'][0])
    campfire_source = source(inputs['states'][3])
    expected = {name: [] for name in names}
    # FS.put_snapshot.changed emits slot Dirty only for an input identity reset.
    # The menu adds its own Dirty for each committed entity-slot command. Thus
    # same-item input pickup/output removal have one; new input identity has two.
    expected.update({names[0]: [expected_source], names[1]: [expected_source, expected_source],
                     names[2]: [expected_source]})
    expected.update({name: [campfire_source] for name in (names[6], names[8])})
    expected_file = work / ('corrected-expected-source.json' if phase == 'compare' else 'expected-source.json')
    assert phase != 'compare' or not expected_file.exists(), 'prior comparator repair is immutable'
    expected_file.write_text(json.dumps(expected, indent=2) + '\n')
    owned = ('src/player_cooking_menu.bend', 'src/player_cooking_menu_laws.bend',
             'src/player_cooking_menu_campfire.bend',
             'tests/player_cooking_menu.bend', 'tools/test_player_cooking_menu_owned_dirty.py',
             'reference/player_cooking_menu.json', 'reference/cooking_world.json')
    pins = {path: M.sha(ROOT / path) for path in owned}
    if phase == 'prepare':
        print(json.dumps(dict(status='PREPARED; native pending', cases=len(rows), expected_sources=expected)))
        return
    checks = []
    if phase in ('build', 'all'):
        checks.append(B.run('emit', ['/usr/bin/env', 'BEND_PRODUCER_LOG=' + str(work / 'emit-functions.jsonl'),
            'BEND_PRODUCER_GC=1', B.NODE, '--expose-gc', '--max-old-space-size=8192', '--stack-size=4096',
            '--experimental-transform-types', 'tools/player_cooking_menu_emit.mjs',
            'tests/player_cooking_menu.bend', work / 'receiver.c'], 600, 8 * 1024**3))
        checks.append(B.run('clang', [shutil.which('clang') or '/usr/bin/clang', '-std=c11', '-O1',
            work / 'receiver.c', '-lpthread', '-lm', '-o', work / 'receiver'], 300, 3 * 1024**3))
    if phase == 'build':
        return
    if phase in ('native', 'compare'):
        checks = [json.loads((work / (tag + '.json')).read_bytes()) for tag in ('emit', 'clang')]
    compiled = json.loads((work / 'receiver.c.sources.json').read_bytes())
    for path in ('src/player_cooking_menu.bend', 'src/player_cooking_menu_campfire.bend', 'tests/player_cooking_menu.bend'):
        assert compiled['source_sha256'][str(ROOT / path)] == M.sha(ROOT / path), 'owned source drift'
    drift = [dict(path=path, compiled_sha256=value, current_sha256=M.sha(path))
             for path, value in compiled['source_sha256'].items() if M.sha(path) != value]
    native = json.loads((work / 'native.json').read_bytes()) if phase == 'compare' else B.run('native',
        [work / 'receiver', '--gpu', 'off', '--threads', '1', M.TABLE,
         work / 'context/input.json', *[M.argument(row) for row in rows]], 120, 1024**3)
    observed = M.compare(rows)
    for row, value in zip(rows, observed, strict=True):
        wanted = expected[row['case']['id']]
        assert value['owned_dirty'] == wanted, (value['id'], value['owned_dirty'], wanted)
        assert value['legacy_dirty'] == 0, (value['id'], 'new menu mutation retained legacy Dirty')
    assert all(M.sha(ROOT / path) == value for path, value in pins.items()), 'owned/input drift'
    output = ROOT / 'evidence' / f'player-cooking-menu-owned-dirty-{generation:03}.json'
    assert not output.exists(), 'prior receipt is immutable'
    value = dict(status='PASS', cases=len(rows), furnace_source_cases=3, campfire_source_cases=2,
        player_only_or_refusal_cases=4, checks=checks, native=native, expected_sources=expected, source_sha256=pins,
        compiled_source_manifest_sha256=M.sha(work / 'receiver.c.sources.json'),
        compiled_source_count=len(compiled['source_sha256']), post_emission_import_drift=drift,
        binary_sha256=M.sha(work / 'receiver'), raw_native_sha256=M.sha(work / 'native.stdout'),
        scope='Actual Menu.dispatch and Camp.use/use_hands through Slots.dispatch; new effects only. Cached registered pre-operation binding/position and authenticated incarnation2 are exact; every existing fresh slot Dirty and appended menu Dirty is stamped in order without duplicate loss. Input identity reset emits two, same-item input count change/output removal one, and accepted campfire placement one. Whole Core,64 player backing,4 furnace backing/campfire cells, profile/timers/RecipesUsed retained and Java count/routing/placement deltas compared. Same-owner offhand fallback is exercised. Player-only and refused operations emit no source. No legacy pending drain/retroattest, public ABI change, socket/entity/publisher/native-window claim.')
    if phase == 'compare':
        value['host_oracle_correction'] = json.loads((work / 'oracle-failure.json').read_bytes())
        value['corrected_expected_source_sha256'] = M.sha(expected_file)
        value['native_replayed_for_comparator_repair'] = False
    output.write_text(json.dumps(value, indent=2) + '\n')
    print(json.dumps(dict(status='PASS', cases=len(rows), evidence=str(output))))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--generation', type=int, required=True)
    parser.add_argument('--phase', choices=('prepare', 'build', 'native', 'compare', 'all'), default='all')
    args = parser.parse_args()
    assert 1 <= args.generation <= 999
    run(args.generation, args.phase)


if __name__ == '__main__':
    main()
