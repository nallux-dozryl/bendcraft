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
        'select': (True, [], True, 0),
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


def swap_suite(executor, reference=None):
    """Observed Java request producer plus literal controller lifecycle cases.

    Native Base.Key currently carries ASCII only. The Java physical default
    and modifier observations are recorded, not claimed as OS/layout parity.
    """
    reference = Path(reference or ROOT / 'reference/player_inventory_click_gui.json')
    observed_java = json.loads(reference.read_text())
    java = {row['id']: row for row in observed_java['observations']}
    require(len(java) == 18, 'bounded actual InventoryScreen producer corpus')
    stdout, pin = executor('inventory-screen-swap-keys', ['swap-keys'])
    observed = {row['label']: row for row in rows(stdout)}
    require(len(observed) == 34, 'complete swap/capture/coordinate case count')

    def controller(**changes):
        value = {'open': True, 'keys': 0, 'buttons': 0, 'captured': False,
                 'focused': True, 'pending': 0, 'tab': 0, 'row': 0,
                 'query': '', 'hover': {'slot': 10}, 'source': None,
                 'offer': None, 'notice': 'ready', 'hover_viewport': [320, 180, 960, 540]}
        value.update(changes)
        return value

    def check(label, expected_controller, intents, carried=None, opened=True, consumed=True):
        row = observed.pop(label)
        expected_authority = authority(opened)
        expected_authority[4] = [0] if carried is None else carried
        require(row['authority'] == expected_authority, f'{label}: all authoritative fields retained')
        require(row['controller'] == expected_controller, f'{label}: entire controller lifecycle')
        require(row['intents'] == intents, f'{label}: exact typed request')
        require(row['consumed'] is consumed, f'{label}: world input isolation')

    for label, source in java.items():
        require(source['ok'] and source['before'] == source['after'], f'{label}: recording boundary retained Java owner')
        require(source['event_input'] == source['input']['key'], f'{label}: physical Java key observed')
        require(source['hotbar_value'] == 30 and source['offhand_value'] == 9, '26.3 pinned physical defaults')
        calls = source['calls']
        require(all(call['action'] == 'SWAP' for call in calls), f'{label}: actual Java action')
        intents = [{'swap': [call['slot'], call['button']]} for call in calls]
        code = source['input']['native_ascii']
        mask = 2048 if code == 70 else 1 << (code - 49)
        slot = source['input']['hover']
        hover = 'outside' if slot < 0 else {'slot': slot}
        carried = stack('minecraft:dirt', 3) if source['input']['carried'] else None
        check(label, controller(keys=mask, hover=hover, pending=3 if intents else 0,
                                notice='waiting' if intents else 'ready'), intents, carried)

    check('offhand-lowercase', controller(keys=2048, pending=3, notice='waiting'), [{'swap': [10, 40]}])
    check('pending-blocks-key', controller(keys=2304, pending=3, notice='waiting'), [])
    check('held-after-reply', controller(keys=2048), [])
    check('release-rearm', controller(keys=2048, pending=3, notice='waiting'), [{'swap': [10, 40]}])
    check('resize-clears-hover', controller(keys=2048, hover='outside', hover_viewport=None), [])
    check('scale-clears-hover', controller(keys=1, hover='outside', hover_viewport=None), [])
    check('capture-clears-hover', controller(keys=2048, hover='outside', hover_viewport=None), [])
    check('resized-new-move', controller(keys=2048, pending=3, notice='waiting', hover_viewport=[320, 180, 1920, 1080]), [{'swap': [10, 40]}])
    for label, mask, tab in [('world-digit', 256, 0), ('world-offhand', 2048, 0), ('world-retained-search', 256, 3)]:
        check(label, controller(open=False, keys=mask, tab=tab, hover='outside', hover_viewport=None), [], opened=False, consumed=False)
    check('search-digit', controller(keys=256, tab=3, query='9', hover='outside', hover_viewport=None), [])
    check('search-offhand-carried', controller(keys=2048, tab=3, query='f', hover='outside', hover_viewport=None), [], stack('minecraft:dirt', 3))
    check('tab-clears-hover', controller(keys=2048, buttons=1, tab=1, hover='outside', hover_viewport=None), [])
    check('focus-clears-hover', controller(open=False, focused=False, hover='outside', hover_viewport=None), ['release', {'capture': False}])
    check('late-refused-focus', controller(open=False, focused=False, notice='rejected', hover='outside', hover_viewport=None), [])
    require(not observed, 'all lifecycle fixtures compared')
    return {'java_request_cases': len(java), 'literal_lifecycle_cases': 16,
            'full_authority_and_controller_cases': 34, 'processes': [pin],
            'reference_sha256': hashlib.sha256(reference.read_bytes()).hexdigest(),
            'boundary': 'CPU Base.Event request producer; physical input/layout/rebinding is not represented'}
