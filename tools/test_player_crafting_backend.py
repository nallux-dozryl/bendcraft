#!/usr/bin/env python3
"""Focused native checks of the production crafting Backend and Session join."""
from pathlib import Path
import argparse
import json
import hashlib
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
from test_player_block_inside_stuck import run
from test_player_look import imports
from build_native import foreign_paths, file_digest, guard_route


def require(value, message):
    if not value:
        raise AssertionError(message)


def stack(name, count):
    return [1, name, '', count]


def frozen_entry(work):
    """Keep the actual imported declarations stable during the ordinary build."""
    entry = ROOT / 'tests/player_crafting_backend.bend'
    pins = imports([entry])
    bend_pins = dict(pins)
    for relative in bend_pins:
        path = ROOT / relative
        for effect in foreign_paths(path.read_text()):
            if effect.endswith('.c'):
                native = (path.parent / effect).resolve()
                pins[str(native.relative_to(ROOT))] = hashlib.sha256(native.read_bytes()).hexdigest()
    source = work / 'source'
    require(not source.exists(), 'fresh source snapshot directory required')
    for relative, expected in pins.items():
        data = (ROOT / relative).read_bytes()
        require(hashlib.sha256(data).hexdigest() == expected, 'source changed while copying: ' + relative)
        destination = source / relative
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
    require(imports([entry]) == bend_pins, 'source changed during snapshot')
    require(all(hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == expected
        for name, expected in pins.items()), 'native effect changed during snapshot')
    (work / 'source-snapshot.json').write_text(json.dumps({'original_source_sha256': pins,
        'declaration_bytes_unchanged': True, 'fixture_entry': str(source / 'tests/player_crafting_backend.bend')}, indent=2) + '\n')
    return source / 'tests/player_crafting_backend.bend'


def verify(rows):
    labels = ['opened', 'inspected', 'wrong-sequence', 'stale', 'refreshed',
              'first', 'second', 'absent', 'closed', 'observer', 'invalid-player', 'legacy-open',
              'legacy-result', 'failure-open', 'committed-refresh-failure']
    require([r['label'] for r in rows] == labels, 'native case order/count changed')
    for row in rows:
        require(len(row['cells']) == 64, row['label'] + ': complete backing length')
        require(row['cells'][0] == stack('minecraft:dirt', 3), row['label'] + ': durable marker')
        require(row['cells'][48:63] == [[0]] * 15, row['label'] + ': backing cells changed')
        require(row['cells'][63] == stack('minecraft:dirt', 7), row['label'] + ': last backing cell changed')
    by = {r['label']: r for r in rows}
    require([r['next'] for r in rows[:9]] == [2, 3, 3, 4, 5, 6, 7, 8, 9], 'lease sequence handling')
    require(by['opened']['accepted'] and by['opened']['menu'][5] == [1, stack('minecraft:stick', 4)], 'actual output authority on open')
    require(by['inspected']['cells'] == by['opened']['cells'], 'observation mutated inventory')
    require(not by['wrong-sequence']['protocol'] and by['wrong-sequence']['message'] == 'RendererLeaseOrSequence', 'wrong sequence admitted')
    require(by['wrong-sequence']['cells'] == by['inspected']['cells'] and by['wrong-sequence']['context'] == by['inspected']['context'], 'lease refusal changed inventory/context')
    require(not by['stale']['accepted'] and 'stale crafting plan' in by['stale']['message'], 'stale plan admitted')
    require(by['stale']['context'] == by['inspected']['context'], 'stale refusal changed original plan')
    require(by['stale']['cells'][43] == stack('minecraft:oak_planks', 3) and by['stale']['cells'][47] == [0], 'stale refusal committed inventory')
    require(by['refreshed']['accepted'] and by['refreshed']['context'] != by['stale']['context'], 'authority did not replace stale plan')
    require(by['first']['accepted'] and by['first']['cells'][43] == stack('minecraft:oak_planks', 2) and by['first']['cells'][45] == stack('minecraft:oak_planks', 1), 'first actual ingredient consumption')
    require(by['first']['cells'][47] == stack('minecraft:stick', 4) and by['first']['menu'][7] == 1, 'first carried craft/revision')
    require(by['second']['accepted'] and by['second']['cells'][43] == stack('minecraft:oak_planks', 1) and by['second']['cells'][45] == [0], 'second actual ingredient consumption')
    require(by['second']['cells'][47] == stack('minecraft:stick', 8) and by['second']['menu'][7] == 2 and by['second']['menu'][5] == [0], 'second carried craft/output/revision')
    require(not by['absent']['accepted'] and by['absent']['cells'] == by['second']['cells'] and by['absent']['context'] == by['second']['context'], 'absent plan refusal changed owner')
    require(by['closed']['accepted'] and by['closed']['menu'][6] is False, 'close failed')
    require(by['closed']['cells'][43:48] == [[0]] * 5 and by['closed']['menu'][5] == [0], 'close retained transient item/output')
    totals = {}
    for cell in by['closed']['cells']:
        if len(cell) == 4:
            totals[cell[1]] = totals.get(cell[1], 0) + cell[3]
    require(totals == {'minecraft:dirt': 10, 'minecraft:oak_planks': 1, 'minecraft:stick': 8}, 'close complete item ledger differs')
    require(not by['observer']['accepted'] and by['observer']['message'] == 'inventory:player-permission' and by['observer']['context'][1] is None, 'observer refreshed/mutated authority')
    require(not by['invalid-player']['accepted'] and by['invalid-player']['message'] == 'inventory:player-permission' and by['invalid-player']['context'][1] is None, 'invalid player refreshed/mutated authority')
    require(by['legacy-open']['accepted'] and by['legacy-open']['context'] is None and by['legacy-open']['menu'][5] == [0], 'None context changed legacy menu')
    require(not by['legacy-result']['accepted'] and by['legacy-result']['cells'] == by['legacy-open']['cells'], 'legacy result acquired recipe semantics')
    failure = by['committed-refresh-failure']
    require(by['failure-open']['accepted'] and failure['accepted'] and failure['message'], 'post-commit refresh failure reported as refusal')
    require(failure['cells'][43] == stack('minecraft:bucket', 1) and failure['cells'][47] == stack('minecraft:stick', 4), 'post-commit refresh error lost actual take/remainder')
    require(failure['context'][1] is None and failure['menu'][7] == 1, 'post-commit context/revision differs')
    return {'cases': len(rows), 'complete_raw_core_unchanged_each_case': True,
            'all_64_inventory_cells_observed': True, 'post_commit_refresh_failure_accepted': True}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--work', type=Path, default=ROOT / 'build/player-crafting-backend/native-001')
    parser.add_argument('--binary', type=Path)
    args = parser.parse_args()
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=True)
    binary = args.binary.resolve() if args.binary else work / 'backend-tests'
    if args.binary is None:
        entry = frozen_entry(work)
        prepare = ROOT / 'tools/player_crafting_authority_native.py'
        run([sys.executable, prepare, entry, '--report', work / 'prepared.json'], work, 'prepare', 600)
        prepared = json.loads((work / 'prepared.json').read_text())
        emitted = Path(prepared['emitted_file'])
        require(file_digest(emitted) == prepared['emitted_c_sha256'], 'prepared C bytes changed')
        guard_route(emitted.read_text())
        require(prepared['context']['compiler']['flags'] ==
            ['-std=c11', '-O3', '<emitted.c>', '-lpthread', '-lm', '-o', '<native>'],
            'original CLI CPU flags changed')
        run([prepared['context']['compiler']['path'], '-std=c11', '-O3', emitted,
             '-lpthread', '-lm', '-o', binary], work, 'clang', 600)
        run([sys.executable, prepare, entry, '--report', work / 'prepared-after.json'], work, 'prepare-after', 600)
        checked = json.loads((work / 'prepared-after.json').read_text())
        require(checked['cache_key'] == prepared['cache_key'] and
            checked['emitted_c_sha256'] == prepared['emitted_c_sha256'],
            'build dependencies changed during clang')
    stdout, native = run([binary, '--gpu', 'off', '--threads', '2'], work, 'native', 30)
    rows = [json.loads(x) for x in stdout.decode().splitlines() if x.startswith('{')]
    result = verify(rows)
    result.update({'binary': str(binary), 'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
                   'native_receipt': native, 'records_sha256': hashlib.sha256(stdout).hexdigest()})
    (work / 'summary.json').write_text(json.dumps(result, indent=2) + '\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
