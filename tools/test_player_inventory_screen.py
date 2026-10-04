#!/usr/bin/env python3
"""Independent native-menu fixtures; process admission belongs to the caller.

executor(label, args, env=None) -> (stdout, process_pin). No subprocess/build.
"""
from __future__ import annotations

import csv
import hashlib
import io
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TABLE_SHA256 = '1cf2669ac760fed886b33d19b12e4782d5011c68c629d22328147d8a9a9bfa22'


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def stack(item, count):
    return [1, item, '', count]


def authority(opened):
    return [[4, True, False, [stack('minecraft:stone', 19)] + [[0] for _ in range(35)]],
            [stack('minecraft:dirt', 2), [0], stack('minecraft:oak_planks', 3), [0],
             stack('minecraft:stone', 4), stack('minecraft:dirt', 5), stack('minecraft:oak_planks', 6)],
            [True, True, False, 1036831949, 1028443341],
            [stack('minecraft:dirt', 7), [0], stack('minecraft:stone', 8), [0]],
            stack('minecraft:oak_planks', 9), [1, stack('minecraft:stone', 10)], opened, 11]


def rows(output):
    return [json.loads(line) for line in output.splitlines() if line.strip()]


def focused_suite(executor):
    stdout, pin = executor('inventory-screen-controller', ['cases'])
    observations = rows(stdout)
    expected = {
        'open': (False, ['release', {'capture': False}, 'open'], True, 1),
        'pending-close': (True, [], True, 3),
        'close': (True, ['release', {'capture': False}, 'close'], True, 2),
        'focus': (True, ['release', {'capture': False}], False, 3),
        'select': (True, [{'select': 8}], True, 3),
        'pickup': (True, [{'pickup': [36, 0]}], True, 3),
        'right': (True, [{'pickup': [36, 1]}], True, 3),
        'outside': (True, [], True, 0),
        'captured': (True, ['release', {'capture': False}], True, 0),
        'refused-close': (True, [], True, 0),
        'accepted-close': (False, ['release', {'capture': True}], False, 0),
        'open-reply': (True, [], True, 0),
        'look-consumed': (True, [], True, 0),
        'move-tab': (True, [], True, 0),
        'items-tab': (True, [], True, 0),
        'palette': (True, [], True, 0),
        'late-close-unfocused': (False, [], False, 0),
        'late-open-unfocused': (True, [], False, 0),
        'refused-open': (False, ['release', {'capture': True}], False, 0),
        'refused-already-closed': (False, ['release', {'capture': True}], False, 0),
        'move-all': (True, [{'transfer': [0, 9, 19]}], True, 3),
        'move-one': (True, [{'transfer': [0, 9, 1]}], True, 3),
        'acquire-max': (True, [{'acquire': [0, {'id': 'minecraft:stone', 'components': ''}, 64]}], True, 3),
        'acquire-one': (True, [{'acquire': [0, {'id': 'minecraft:stone', 'components': ''}, 1]}], True, 3),
        'refocus-open': (True, ['release', {'capture': False}], True, 0),
        'observe-pending': (False, [], True, 1),
        'observe-unfocused': (True, [], False, 0),
    }
    require(len(observations) == len(expected), 'controller observation count')
    for row in observations:
        label = row['label']
        opened, intents, ui_open, pending = expected.pop(label)
        require(row['authority'] == authority(opened), f'{label}: complete authority retention')
        require(row['intents'] == intents, f'{label}: exact intent order')
        require(row['controller']['open'] == ui_open, f'{label}: open state')
        require(row['controller']['pending'] == pending, f'{label}: pending lifecycle')
        require(row['consumed'] is True, f'{label}: control capture/consumption')
    require(not expected, 'missing controller cases')
    hit_stdout, hit_pin = executor('inventory-screen-topology', ['hits'])
    hits = rows(hit_stdout)
    require(len(hits) == 46, 'exact InventoryMenu topology')
    for index, row in enumerate(hits):
        require(row == {'slot': index, 'hit': {'slot': index}}, f'slot {index}: native hit mapping')
    return {'controller_cases': len(observations), 'slot_cases': len(hits),
            'processes': [pin, hit_pin]}


def definitions_suite(executor, path=None):
    path = Path(path or ROOT / 'generated/reference_item_metadata.tsv')
    raw = path.read_bytes()
    require(hashlib.sha256(raw).hexdigest() == TABLE_SHA256, 'pinned item table hash')
    parsed = list(csv.DictReader(io.StringIO(raw.decode()), delimiter='\t'))
    require(len(parsed) == 1658, 'pinned complete registry count')
    stdout, pin = executor('inventory-screen-all-definitions', ['definitions', str(path)])
    observed = rows(stdout)
    require(observed[0] == {'count': len(parsed)}, 'runtime catalog count')
    require(len(observed) == len(parsed) + 1, 'every registry definition observed')
    for source, actual in zip(parsed, observed[1:]):
        limit = int(source['default_stack_max_stack_size'])
        enabled = source['enabled_default_flags'] == 'True'
        expected = {'number': int(source['item_id']), 'id': source['identifier'], 'limit': limit,
                    'component_set': int(source['default_component_set_id']),
                    'components_sha256': source['default_components_sha256'], 'enabled': enabled,
                    'metadata': limit if enabled and source['identifier'] != 'minecraft:air' else None}
        require(actual == expected, f"definition {expected['number']}: complete default identity and limit")
    return {'registry_rows': len(parsed), 'metadata_cases': len(parsed), 'processes': [pin],
            'table_sha256': TABLE_SHA256}
