#!/usr/bin/env python3
"""Compare actual Core-owned Bend sky receiver with retained pinned Java phases.

Only fixture geometry and Java-observed block/face properties enter Bend.
Java levels and source thresholds remain exclusively in this comparator.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / 'build/sky-light-native'
BEND = Path.home() / '.bend/bin/bend'
HARNESS = ROOT / 'tests/sky_light_receiver.bend'
BINARY = WORK / 'receiver'
REFERENCE = ROOT / 'reference/sky_light.json'
CLOCK = '0/137/f/f/0/0'


def digest(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':')).encode()


def run(kind, args, timeout=60):
    started = time.monotonic()
    try:
        result = subprocess.run(list(map(str, args)), cwd=ROOT, capture_output=True,
                                text=True, timeout=timeout)
    except subprocess.TimeoutExpired as error:
        row = {'kind': kind, 'command': list(map(str, args)), 'status': 'timeout',
               'seconds': round(time.monotonic() - started, 4),
               'stdout': (error.stdout or b'').decode() if isinstance(error.stdout, bytes) else error.stdout,
               'stderr': (error.stderr or b'').decode() if isinstance(error.stderr, bytes) else error.stderr}
        (WORK / (kind + '.json')).write_text(json.dumps(row, indent=2) + '\n')
        raise
    row = {'kind': kind, 'command': list(map(str, args)),
           'seconds': round(time.monotonic() - started, 4), 'exit': result.returncode,
           'stdout': result.stdout.strip(), 'stderr': result.stderr.strip()}
    (WORK / (kind + '.json')).write_text(json.dumps(row, indent=2) + '\n')
    assert result.returncode == 0, {**row, 'stdout': row['stdout'][-4000:], 'stderr': row['stderr'][-4000:]}
    return result.stdout, row


def source_closure(path=HARNESS, found=None):
    found = {} if found is None else found
    path = path.resolve()
    key = str(path.relative_to(ROOT))
    if key in found:
        return found
    found[key] = digest(path)
    for match in re.finditer(r'^import\s+(\.\.?/\S+\.bend)\s+as\s+', path.read_text(), re.MULTILINE):
        source_closure(path.parent / match.group(1), found)
    return found


def prepare_native(reuse):
    sources = source_closure()
    cache_path = WORK / 'native-cache.json'
    if reuse and cache_path.exists() and BINARY.exists():
        cache = json.loads(cache_path.read_text())
        if cache['source_sha256'] == sources and cache['binary_sha256'] == digest(BINARY):
            return {'mode': 'reused_verified_native', 'source_sha256': sources,
                    'binary_sha256': cache['binary_sha256'], 'build_checks': cache['build_checks']}
    checks = []
    for kind, command in (
        ('ordinary', [BEND, HARNESS, '--check-only']),
        ('emit', [BEND, HARNESS, '-o', WORK / 'receiver.c']),
        ('native', [shutil.which('clang') or '/usr/bin/clang', '-std=c11', '-O3',
                    WORK / 'receiver.c', '-lpthread', '-lm', '-o', BINARY]),
    ):
        _, row = run(kind, command, 60)
        checks.append({k: row[k] for k in ('kind', 'command', 'seconds', 'exit')})
    assert source_closure() == sources, 'Production sources changed during native build'
    cache = {'source_sha256': sources, 'binary_sha256': digest(BINARY),
             'c_sha256': digest(WORK / 'receiver.c'), 'build_checks': checks}
    cache_path.write_text(json.dumps(cache, indent=2) + '\n')
    return {'mode': 'fresh_native', **cache}


def properties(reference):
    return {p['id']: p for p in reference['observations']['properties']}


def origins(scenario):
    minimum = scenario['bounds']['min_y']
    height = scenario['bounds']['height']
    return [(cx * 16, y, cz * 16) for cx, cz in scenario['chunks']
            for y in range(minimum, minimum + height, 16)]


def initial_geometry(scenario, prop):
    cells = {}
    for fill in scenario['fills']:
        x0, y0, z0 = fill['from']
        x1, y1, z1 = fill['to']
        for y in range(y0, y1 + 1):
            for z in range(z0, z1 + 1):
                for x in range(x0, x1 + 1):
                    cells[x, y, z] = prop[fill['state']]['state']
    for write in scenario['writes']:
        cells[tuple(write['position'])] = prop[write['state']]['state']
    return cells


def request(reference, scenario, budget):
    prop = properties(reference)
    closed = [edge for edge in reference['observations']['edges'] if edge['closed']]
    args = [budget, scenario['bounds']['min_y'] & 0xffffffff,
            scenario['bounds']['height'], prop['air']['state'], int(scenario['initial_enabled']), len(prop)]
    for item in prop.values():
        args.extend((item['state'], item['dampening']))
    args.append(len(closed))
    for edge in closed:
        args.extend((prop[edge['from']]['state'], prop[edge['to']]['state'], edge['direction']))
    declared = origins(scenario)
    default = prop[scenario['default_state']]['state']
    args.append(len(declared))
    for position in declared:
        args.extend(value & 0xffffffff for value in position)
        args.append(default)
    writes = initial_geometry(scenario, prop)
    args.append(len(writes))
    for position, state in writes.items():
        args.extend(value & 0xffffffff for value in position)
        args.append(state)
    args.append(len(scenario['samples']))
    for position in scenario['samples']:
        args.extend(value & 0xffffffff for value in position)
    args.append(len(scenario['phases']))
    for phase in scenario['phases']:
        args.append(len(phase['writes']))
        for write in phase['writes']:
            args.extend(value & 0xffffffff for value in write['position'])
            args.append(prop[write['state']]['state'])
        args.append(len(phase['enabled']))
        for toggle in phase['enabled']:
            cx, cz = toggle['chunk']
            args.extend((cx * 16 & 0xffffffff, 0, cz * 16 & 0xffffffff, int(toggle['value'])))
        args.append(len(phase['propagate']))
        for cx, cz in phase['propagate']:
            args.extend((cx * 16 & 0xffffffff, 0, cz * 16 & 0xffffffff))
        args.append(len(phase['checks']))
        for position in phase['checks']:
            args.extend(value & 0xffffffff for value in position)
    return list(map(str, args))


def expected_arrays(scenario, cells, default):
    arrays = []
    for ox, oy, oz in origins(scenario):
        arrays.append([cells.get((ox + (index & 15), oy + (index >> 8),
                                 oz + ((index >> 4) & 15)), default) for index in range(4096)])
    return arrays


def decode_owner(line):
    marker, clock, storage = line.strip().split(' ', 2)
    assert marker == 'owner'
    arrays = []
    for section in storage.split(';')[:-1]:
        assert section != '?', 'Declared resident section disappeared during sky operation'
        cells = []
        for run_value in section.split(','):
            state, count = map(int, run_value.split(':'))
            assert 0 < count <= 4096
            cells.extend([state] * count)
        assert len(cells) == 4096
        arrays.append(cells)
    return clock, arrays


def decode_frame(line):
    marker, clock, *values = line.split()
    assert marker == 'stable', line
    return clock, [tuple(None if value == '?' else int(value) for value in pair.split(':'))
                   for pair in values]


def compare_scenario(reference, scenario, output, budget):
    actual_lines = output.splitlines()
    observed = next(s for s in reference['observations']['scenarios'] if s['id'] == scenario['id'])
    assert len(actual_lines) == 1 + 2 * len(observed['phases']), (scenario['id'], output[-4000:])
    prop = properties(reference)
    default = prop[scenario['default_state']]['state']
    cells = initial_geometry(scenario, prop)
    clock, before = decode_owner(actual_lines[0])
    assert clock == CLOCK
    assert before == expected_arrays(scenario, cells, default), 'Fresh Core storage differs from declared geometry'
    resident_chunks = {tuple(c) for c in scenario['chunks']}
    low, high = scenario['bounds']['min_y'], scenario['bounds']['min_y'] + scenario['bounds']['height']
    rows = []
    for index, phase in enumerate(observed['phases']):
        if index:
            for write in scenario['phases'][index - 1]['writes']:
                cells[tuple(write['position'])] = prop[write['state']]['state']
        clock, actual = decode_frame(actual_lines[1 + 2 * index])
        assert clock == CLOCK, (scenario['id'], phase['id'], clock)
        assert len(actual) == len(scenario['samples'])
        expected = []
        resident_samples = 0
        for position, java_state, level in zip(scenario['samples'], phase['state_ids'], phase['levels']):
            x, y, z = position
            if (x >> 4, z >> 4) in resident_chunks and low <= y < high:
                state = cells.get(tuple(position), default)
                assert state == java_state, (scenario['id'], phase['id'], position, state, java_state)
                expected.append((state, level))
                resident_samples += 1
            else:
                expected.append((None, None))
        assert actual == expected, (scenario['id'], phase['id'], actual, expected)
        owner_clock, after = decode_owner(actual_lines[2 + 2 * index])
        assert owner_clock == CLOCK
        assert after == expected_arrays(scenario, cells, default), (scenario['id'], phase['id'], 'Core block arrays changed')
        rows.append({'scenario': scenario['id'], 'phase': phase['id'], 'budget': budget,
                     'resident_java_sample_pairs': resident_samples,
                     'explicit_core_missing_sample_pairs': len(actual) - resident_samples,
                     'core_cells_compared': sum(map(len, after)),
                     'actual_block_and_light_sha256': hashlib.sha256(canonical(actual)).hexdigest(),
                     'actual_core_arrays_sha256': hashlib.sha256(canonical(after)).hexdigest()})
    return rows


def guard_check():
    output, row = run('guards', [BINARY, '--gpu', 'off', '--threads', '1', '--', 'guards'], 45)
    lines = output.splitlines()
    assert len(lines) == 5, output[-4000:]
    before_clock, before = decode_owner(lines[0])
    assert before_clock == '0/37/f/f/0/1' and before == [[0] * 4096]
    assert lines[1] == 'guard refused:loading'
    assert lines[2] == 'guards bounds unknown accepted descriptor accepted', lines[2]
    assert lines[3].startswith('guard ')
    clock, cells = decode_frame(lines[3][6:])
    assert clock == before_clock and cells == [(0, 15), (None, None), (None, None)]
    after_clock, after = decode_owner(lines[4])
    assert after_clock == before_clock and after == before
    return {'command': row['command'], 'seconds': row['seconds'], 'exit': row['exit'],
            'refusals': ['InvalidBounds', 'UnknownSection', 'MissingDescriptor'],
            'retries': ['correct bounds', 'KnownEmpty admission', 'restore descriptor'],
            'all_clock_fields_retained': True, 'future_core_mutation_retained': True,
            'actual_core_arrays_equal': True, 'known_empty_does_not_fabricate_core_residency': True}


def halo_check():
    output, row = run('below-min-resident-halo', [BINARY, '--gpu', 'off', '--threads', '1', '--', 'halo'], 45)
    lines = output.splitlines()
    assert len(lines) == 3, output[-4000:]
    before_clock, before = decode_owner(lines[0])
    assert before_clock == '0/71/f/f/0/0' and before == [[0] * 4096] * 2
    clock, cells = decode_frame(lines[1])
    assert clock == before_clock and cells == [(0, 15)] * 4 + [(None, None)] * 2
    after_clock, after = decode_owner(lines[2])
    assert after_clock == before_clock and after == before
    return {'command': row['command'], 'seconds': row['seconds'], 'exit': row['exit'],
            'resident_sections_below_build_minimum_retained': True,
            'direct_source_membership_extends_one_section_below_minimum': True,
            'all_clock_fields_retained': True, 'actual_core_arrays_equal': True,
            'boundary': 'Declared native Core residency/source-membership regression for all-air one-section storage halo. No additional Java execution or sparse Java-storage equivalence claim.'}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--reuse-native', action='store_true')
    parser.add_argument('--scenario', action='append')
    args = parser.parse_args()
    WORK.mkdir(parents=True, exist_ok=True)
    reference = json.loads(REFERENCE.read_text())
    assert reference['pin'] == '26.3'
    assert reference['observations_sha256'] == hashlib.sha256(canonical(reference['observations'])).hexdigest()
    reference_hash = digest(REFERENCE)
    native = prepare_native(args.reuse_native)
    rows, runs = [], []
    selected = [s for s in reference['inputs']['scenarios'] if not args.scenario or s['id'] in args.scenario]
    assert selected
    for scenario in selected:
        command = [BINARY, '--gpu', 'off', '--threads', '1', '--', *request(reference, scenario, 64)]
        output, run_row = run(scenario['id'], command, 60)
        rows.extend(compare_scenario(reference, scenario, output, 64))
        runs.append({k: run_row[k] for k in ('kind', 'seconds', 'exit')})
    budgets = []
    if not args.scenario:
        for name, budget in (('horizontal_shape_union', 1), ('water_attenuation', 256)):
            scenario = next(s for s in selected if s['id'] == name)
            output, run_row = run(name + '-budget-' + str(budget),
                                  [BINARY, '--gpu', 'off', '--threads', '1', '--', *request(reference, scenario, budget)], 60)
            rows.extend(compare_scenario(reference, scenario, output, budget))
            budgets.append({'scenario': name, 'budget': budget, 'seconds': run_row['seconds'], 'exit': run_row['exit']})
    guards = guard_check()
    halo = halo_check()
    assert source_closure() == native['source_sha256'], 'Production sources changed during receiver verification'
    assert digest(REFERENCE) == reference_hash, 'Retained Java reference changed during receiver verification'
    evidence = {'status': 'passed', 'pin': '26.3', 'command': 'python3 tools/test_sky_light.py' + (' --reuse-native' if args.reuse_native else ''),
                'test_source_sha256': digest(Path(__file__)), 'reference_sha256': reference_hash,
                'java_observations_sha256': reference['observations_sha256'], 'native': native,
                'java_receiver_rerun': False, 'scenarios': len(selected), 'phase_comparisons': len(rows),
                'resident_java_block_and_light_pairs': sum(row['resident_java_sample_pairs'] for row in rows),
                'explicit_core_missing_pairs': sum(row['explicit_core_missing_sample_pairs'] for row in rows),
                'actual_core_array_cell_comparisons': sum(row['core_cells_compared'] for row in rows),
                'runs': runs, 'budget_checks': budgets, 'observations': rows, 'guards': guards,
                'resident_halo_guard': halo,
                'boundary': 'Actual native Bend Core.World/Section arrays, source scans from Core physical descriptors, initial source bootstrap, accepted Core edits with resumable refresh, source enablement/propagation lifecycle, and settled Core-aware samples. Full resident arrays and all clock fields checked through every phase; guard retains a future Core mutation and retries rejected bounds/policy/descriptor. Geometry and actual Java descriptors/faces are fixture inputs; expected levels and source heights never enter Bend. Java public above-top/absent lookup is mapped explicitly to None/None when Core lacks residency. No Java rerun, rendering/lightmap, save/packet persistence, world-scale performance, or independent-kernel proof claim.'}
    path = ROOT / 'evidence/sky-light-native.json'
    path.write_text(json.dumps(evidence, indent=2) + '\n')
    print(json.dumps({k: evidence[k] for k in ('status', 'scenarios', 'phase_comparisons', 'resident_java_block_and_light_pairs', 'actual_core_array_cell_comparisons')}))


if __name__ == '__main__':
    main()
