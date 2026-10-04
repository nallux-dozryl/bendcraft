#!/usr/bin/env python3
"""Independent pinned-Java SWAP comparison; no host click implementation."""
from __future__ import annotations
from collections import Counter
from pathlib import Path
import copy
import json

from reference_inventory import canonical
from test_player_inventory import TABLE_SHA256, stack, sha, require

DISPOSITION = 'swap needs real drop or creative-discard ownership for the displaced item'
RECIPE = 'crafting output or outside slot requires recipe/drop authority'


def actual_stack(observed):
    if observed is None or observed.get('empty', False):
        return None
    item = observed.get('item', observed.get('visible_item'))
    count = observed.get('count', observed.get('visible_count'))
    require(isinstance(item, str) and isinstance(count, int) and count > 0,
            'Invalid nonempty Java swap slot')
    return stack(item, count)


def logical(observed):
    inventory = observed['inventory']
    require(inventory['container_size'] == 43 and inventory['main_length'] == 36,
            'Java durable topology differs')
    main = [actual_stack(s) for s in inventory['main_slots']]
    equipment = [actual_stack(s) for s in observed['equipment']]
    craft = [actual_stack(s) for s in observed['craft']]
    require((len(main), len(equipment), len(craft)) == (36, 7, 4),
            'Java complete menu dimensions differ')
    return main + equipment + craft + [actual_stack(observed['carried'])]


def abilities(observed):
    raw = observed['inventory']['abilities']
    result = {key: raw[key] for key in
              ('instabuild', 'maybuild', 'invulnerable', 'mayfly', 'flying')}
    result.update(walking_speed=int(raw['walking_speed_f32_bits'], 16),
                  flying_speed=int(raw['flying_speed_f32_bits'], 16))
    return result


def item_counts(slots):
    values = Counter()
    for slot in slots:
        if slot:
            values[(slot['id'], slot['components'])] += slot['count']
    return values


def fixtures(reference, table):
    reference, table = Path(reference), Path(table)
    raw = reference.read_bytes()
    data = json.loads(raw)
    require(data['pin'] == '26.3' and sha(canonical(data['observations'])) ==
            data['observations_sha256'], 'Java SWAP observation seal differs')
    require(data['loaded_official_classes']['all_verified_against_client_jar'],
            'Actual SWAP receiver class checks absent')
    require(sha(table.read_bytes()) == TABLE_SHA256, 'Full item table identity differs')
    require(len(data['observations']) == 49, 'Observed SWAP corpus count differs')
    tail = [stack('minecraft:stone', n + 1) for n in range(16)]
    revision, result = 23, []
    for row in data['observations']:
        require(row['ok'], 'Actual SWAP receiver failed: ' + row['id'])
        before, after = logical(row['before']), logical(row['after'])
        accepted, message, scope = True, '', 'exact-Java-count-retaining-swap'
        if 'head-full-disposition:' in row['id']:
            require(item_counts(before) - item_counts(after) ==
                    Counter({('minecraft:diamond_helmet', ''): 1}),
                    'Observed world-drop/creative-discard disposition differs')
            accepted, message, scope = False, DISPOSITION, 'atomic-disposition-refusal'
        elif row['input']['target'] == 0:
            require(before == after, 'Empty recipe result unexpectedly mutated')
            accepted, message, scope = False, RECIPE, 'explicit-recipe-dependency'
        else:
            require(item_counts(before) == item_counts(after),
                    'Java supported SWAP loses/invents an item: ' + row['id'])
        expected_slots = (after if accepted else before) + tail
        expected = {'id': row['id'], 'accepted': accepted, 'message': message,
                    'selected': row['before']['inventory']['selected'],
                    'abilities': abilities(row['before']), 'opened': True,
                    'revision': revision + int(accepted and before != after),
                    'result': None, 'logical_length': 48, 'catalog_count': 1658,
                    'all_backing_slots': expected_slots}
        result.append({'before_slots': before + tail, 'before_result': None,
                       'before_opened': True, 'target': row['input']['target'],
                       'button': row['input']['button'] & 0xffffffff,
                       'expected': expected, 'scope': scope})

    basis = next(f for f in result if f['expected']['id'] == 'different-items:creative')
    for label, patch in [
            ('raw-signed-zero-nan', {'walking_speed': 2147483648, 'flying_speed': 2143289429}),
            ('raw-negative-infinite', {'walking_speed': 4286578688, 'flying_speed': 3212836864}),
            ('maybuild-false-swap', {'maybuild': False})]:
        fixture = copy.deepcopy(basis)
        fixture['expected']['id'] = label
        fixture['expected']['abilities'].update(patch)
        fixture['scope'] = 'full-profile-retention'
        result.append(fixture)
    for name in ('ignored-button-9:creative', 'head-clips-stack:creative',
                 'head-full-disposition:creative'):
        fixture = copy.deepcopy(next(f for f in result if f['expected']['id'] == name))
        fixture['expected']['id'] = 'derived-cache:' + name
        fixture['before_result'] = stack('minecraft:stone', 1)
        if fixture['expected']['revision'] == revision:
            fixture['expected']['result'] = fixture['before_result']
        fixture['scope'] = 'derived-cache-retention-or-invalidation'
        result.append(fixture)
    for name, target, opened, message in [
            ('closed-menu-retention', 10, False, 'player inventory menu is closed'),
            ('outside-slot-retention', 4294967295, True, RECIPE)]:
        fixture = copy.deepcopy(basis)
        fixture.update(before_opened=opened, target=target)
        fixture['expected'].update(id=name, accepted=False, message=message,
                                   opened=opened, revision=revision,
                                   all_backing_slots=copy.deepcopy(fixture['before_slots']))
        fixture['scope'] = 'actual-menu-authority-and-slot-domain'
        result.append(fixture)

    arguments = [str(table.resolve())]
    for fixture in result:
        expected, before = fixture['expected'], fixture['before_slots']
        require(len(before) == len(expected['all_backing_slots']) == 64,
                'SWAP full backing dimensions differ')
        require(item_counts(before) == item_counts(expected['all_backing_slots']),
                'Expected owned SWAP loses/invents an item')
        ability = expected['abilities']
        header = [expected['id'], expected['selected'],
                  *[int(ability[k]) for k in ('instabuild', 'maybuild', 'invulnerable', 'mayfly', 'flying')],
                  ability['walking_speed'], ability['flying_speed'], revision,
                  '_' if fixture['before_result'] is None else
                  f'{fixture["before_result"]["id"]}~{fixture["before_result"]["count"]}',
                  int(fixture['before_opened']), fixture['target'], fixture['button']]
        encoded = ['_' if s is None else f'{s["id"]}~{s["count"]}' for s in before]
        arguments.append('|'.join(map(str, header + encoded)))
    return arguments, result, {'path': str(reference), 'sha256': sha(raw),
                              'observations_sha256': data['observations_sha256']}


def suite(executor, reference, table):
    """executor(label,args,env=None) executes the actual Bend click harness."""
    arguments, cases, reference_pin = fixtures(reference, table)
    stdout, pin = executor('player-inventory-click-swap', arguments)
    observed = [json.loads(line) for line in stdout.splitlines() if line.strip()]
    require(len(observed) == len(cases), 'Native SWAP response count differs')
    for actual, case in zip(observed, cases):
        require(actual == case['expected'], 'Native SWAP differs: ' + case['expected']['id'])
    return {'cases': len(cases), 'scope_counts': dict(Counter(c['scope'] for c in cases)),
            'all64_backing_cells_and_all_saved_ability_words_compared': True,
            'expected_sha256': sha(canonical([c['expected'] for c in cases])),
            'reference': reference_pin, 'process': pin,
            'explicit_gaps': ['real world-owned item drop', 'creative overflow-discard ownership',
                              'derived crafting result take/consumption', 'native number-key/offhand input binding']}
