"""Independent literal cooking-menu fixtures; no runtime or process launcher."""
from __future__ import annotations

import copy
import json

import test_playable_client_cooking as C19

B, A, P, R, S, H = C19.B, C19.A, C19.P, C19.R, C19.S, C19.H
ROOT = C19.ROOT
POSITION = ('minecraft:overworld', 12, 8, 12)
REFERENCE = ROOT / 'reference/player_cooking_menu.json'
REFERENCE_SHA = '91e1ee5292b5925337d4a4b5f334a2f2ff3ccbd61483507a9b77b46dfe338fea'


def reference_cases():
    reference = json.loads(REFERENCE.read_bytes())
    S.require(S.sha(REFERENCE.read_bytes()) == REFERENCE_SHA and reference['pin'] == '26.3',
              'Original Java cooking-menu observations changed')
    selected = ('input-right-take', 'input-right-put', 'quick-output-reverse',
                'quick-fuel-forward', 'quick-input-forward', 'quick-hotbar-other-main')
    rows = {source['id']: (source, result) for source, result in
            zip(reference['inputs'], reference['observations'], strict=True)}
    S.require(set(selected) <= rows.keys(), 'Required retained Java menu cases')
    # Check literal outcomes before using their independently observed routing.
    for name, index, item in (('quick-output-reverse', 8, 'minecraft:stone'),
                              ('quick-fuel-forward', 9, 'minecraft:coal'),
                              ('quick-input-forward', 9, 'minecraft:cobblestone'),
                              ('quick-hotbar-other-main', 9, 'minecraft:dirt')):
        source, result = rows[name]
        actual = result['after']['player']['inventory']['main_slots'][index]
        S.require(actual is not None and actual.get('id', actual.get('item')) == item and actual['count'] == 17,
                  'Retained Java literal destination changed: ' + name)
    source, result = rows['input-right-take']
    S.require(result['after']['furnace'][0]['visible_count'] == 8 and
              result['after']['carried']['visible_count'] == 9,
              'Retained Java ceil-half pickup changed')
    return {name: {'input': rows[name][0], 'after': rows[name][1]['after']} for name in selected}


def body(facts, slots, *, progress=40, remaining=10):
    original = C19.body_root(facts, progress=progress, remaining=remaining)
    items = tuple(C19.JavaBody.item(index, value['id'], value['count'])
                  for index, value in enumerate(slots) if value is not None)
    values = tuple((name, S.N.Value(9, (10 if items else 0, items)) if name == S.N.text('Items') else value)
                   for name, value in original.value.payload)
    return S.N.encode_root(S.N.RootTag(original.name, S.N.Value(10, values)))


def fixture(facts):
    world, _, _, _, _ = C19.fixture(facts)
    S.BASE.set_block(world, *C19.POSITION[1:], facts['palette']['minecraft:air'])
    S.BASE.set_block(world, *POSITION[1:], facts['lit'])
    record = A.playable_spawn((11.5, 8.0, 10.5))
    _, full = B.Inventory.parse_inventory_full(B.FULL_FIXTURE.read_bytes())
    full = copy.deepcopy(full)
    full['main'].update(selected=7, slots=[None] * 36)
    full['main']['slots'][0] = B.stack('minecraft:dirt', 13)
    # The raw signed-zero walk word and NaN fly payload remain exact. Flight is
    # inactive so the one explicit empty-owner reset tick does not use fly speed.
    full['status']['flying'] = False
    full['generation'] = C19.legacy_generation()
    slots = [B.stack('minecraft:cobblestone', 17), B.stack('minecraft:coal', 17),
             B.stack('minecraft:stone', 17)]
    physical = body(facts, slots)
    with H.bindings(C19, {'POSITION': POSITION}):
        data = C19.bundle(world, 40, record, full, physical)
    return world, record, full, slots, physical, data


def empty_fixture(facts):
    """Fresh test input with retained physical Details and no prior menu Dirty."""
    world, record, full, _, _, _ = fixture(facts)
    S.BASE.set_block(world, *POSITION[1:], facts['unlit'])
    original = C19.body_root(facts, progress=0, remaining=0)
    zero = {S.N.text('cooking_total_time'), S.N.text('lit_total_time')}
    values = tuple((name, S.WC.integer(0) if name in zero else
                    S.N.Value(9, (10, ())) if name == S.N.text('Items') else value)
                   for name, value in original.value.payload)
    physical = S.N.encode_root(S.N.RootTag(original.name, S.N.Value(10, values)))
    with H.bindings(C19, {'POSITION': POSITION}):
        data = C19.bundle(world, 40, record, full, physical)
    return world, record, full, [None] * 3, physical, data


def handle(menu, token=0):
    return [1, menu, 41, list(POSITION), 'minecraft:furnace', 0, token]


def view(slots, timers):
    return [1, 0, *map(B.slot, slots), *timers]


def snapshot(full, menu, current, furnace):
    return [current, furnace, B.authority(full, menu)]


def expected_steps(initial_full):
    """Literal composed deltas, not a second implementation of click routing."""
    full = copy.deepcopy(initial_full)
    menu = B.empty_menu()
    menu['opened'] = True
    slots = [B.stack('minecraft:cobblestone', 17), B.stack('minecraft:coal', 17),
             B.stack('minecraft:stone', 17)]
    timers = [10, 10, 40, 200]
    rows = []
    def retain(label, command):
        rows.append({'label': label, 'command': command, 'full': copy.deepcopy(full),
                     'menu': copy.deepcopy(menu), 'slots': copy.deepcopy(slots),
                     'timers': list(timers)})
    slots[0] = B.stack('minecraft:cobblestone', 8)
    menu.update(carried=B.stack('minecraft:cobblestone', 9), revision=1)
    retain('java-right-half-input', [16, 1, 0, 1])
    slots[0] = B.stack('minecraft:cobblestone', 17)
    menu.update(carried=None, revision=2)
    retain('deposit-retains-input-identity-timers', [16, 1, 0, 0])
    slots[2] = None
    full['main']['slots'][8] = B.stack('minecraft:stone', 17)
    menu['revision'] = 3
    retain('java-output-reverse-hotbar', [17, 1, 2])
    slots[1] = None
    full['main']['slots'][9] = B.stack('minecraft:coal', 17)
    menu['revision'] = 4
    retain('java-fuel-forward-main', [17, 1, 1])
    slots[0] = None
    full['main']['slots'][10] = B.stack('minecraft:cobblestone', 17)
    timers[2] = 0
    menu['revision'] = 5
    retain('java-input-forward-after-occupied-coal', [17, 1, 0])
    full['main']['slots'][0] = None
    full['main']['slots'][11] = B.stack('minecraft:dirt', 13)
    menu['revision'] = 6
    retain('java-hotbar-other-forward-after-occupied-main', [17, 1, 30])
    full['main']['slots'][9] = None
    menu.update(carried=B.stack('minecraft:coal', 17), revision=7)
    retain('pickup-main-coal-before-real-close-return', [16, 1, 3, 0])
    full['main']['slots'][0] = B.stack('minecraft:coal', 17)
    menu.update(carried=None, opened=False, revision=8)
    retain('close-returns-carried-first-empty-main', [18, 1])
    return rows
