#!/usr/bin/env python3
"""Independent inventory transition and physical NBT fixture comparators.

The caller supplies the admitted native executor. This module never builds or
launches a process; Python owns fixtures/expected bytes, Bend owns transitions.
"""
from __future__ import annotations

import copy
from collections import Counter
import csv
import dataclasses
import hashlib
import io
import json
from pathlib import Path
import test_nbt as N
import test_player_codec as P
import test_local_player_record as R
from reference_inventory import canonical

ITEMS = ('minecraft:stone', 'minecraft:dirt', 'minecraft:oak_planks')
NAME = 'bendex:local-player-inventory-record'
FIELDS = ('format', 'record', 'selected', 'instabuild', 'maybuild', 'slots')
FULL_FIELDS = FIELDS + ('equipment', 'abilities', 'generation')
STATUS_FIELDS = ('invulnerable', 'mayfly', 'flying', 'walking_speed', 'flying_speed')
TABLE_SHA256 = '1cf2669ac760fed886b33d19b12e4782d5011c68c629d22328147d8a9a9bfa22'


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def empty(*, creative=False):
    return {'selected': 0, 'slots': [None] * 36,
            'abilities': {'instabuild': creative, 'maybuild': True}}


def stack(item, count):
    return {'id': item, 'components': '', 'count': count} if count else None


def transition(before, command):
    """Declarative integer rules, independent of the production Nat recurrence."""
    state = copy.deepcopy(before)
    fields = command.split('|')
    label, operation, *args = fields
    status = 'ok'
    if operation == 'selected':
        status = 'selected:' + json.dumps(state['slots'][state['selected']], separators=(',', ':'))
    elif operation == 'select':
        index = int(args[0])
        if index >= 9:
            status = 'rejected:hotbar slot must be 0 through 8'
        else:
            state['selected'] = index
    elif operation == 'abilities':
        state['abilities'] = dict(zip(('instabuild', 'maybuild'), (int(v) == 1 for v in args)))
    elif operation in ('acquire', 'modified'):
        index, item, count = int(args[0]), args[1], int(args[2])
        if not state['abilities']['instabuild']:
            status = 'rejected:creative acquisition requires player instabuild ability'
        elif item not in ITEMS or operation == 'modified':
            status = 'rejected:unsupported item or modified components'
        elif index >= 36 or count > 64:
            status = 'rejected:invalid inventory slot or count'
        else:
            state['slots'][index] = stack(item, count)
    elif operation == 'transfer':
        source, target, requested = map(int, args[:3])
        mode = args[3]
        reason = None
        if source >= 36 or target >= 36:
            reason = 'bounds'
        elif source == target:
            reason = 'same_slot'
        else:
            old, destination = state['slots'][source], state['slots'][target]
            if mode == 'split' and destination:
                reason = 'split_needs_empty'
            elif mode == 'merge' and not destination:
                reason = 'merge_needs_stack'
            elif not old:
                reason = 'no_source'
            elif destination and destination['id'] != old['id']:
                reason = 'different_item'
            elif destination and destination['count'] == 64:
                reason = 'full'
            else:
                moved = min(requested, old['count'], 64 - (destination['count'] if destination else 0))
                if moved:
                    state['slots'][source] = stack(old['id'], old['count'] - moved)
                    state['slots'][target] = stack(old['id'], (destination['count'] if destination else 0) + moved)
                status = f'moved:{moved}'
        if reason:
            status = 'rejected:' + reason
    elif operation != 'inspect':
        raise ValueError(operation)
    return state, {'label': label, 'status': status, 'inventory': copy.deepcopy(state)}


def transition_actions():
    actions = ['initial|inspect', 'last-hotbar|select|8', 'empty-selected|selected',
               'stone|acquire|0|minecraft:stone|64', 'almost-full|acquire|1|minecraft:stone|63',
               'different|acquire|2|minecraft:dirt|7', 'last-main|acquire|35|minecraft:oak_planks|16',
               'clamped-merge|transfer|0|1|64|merge', 'split|transfer|0|3|20|split',
               'identity|transfer|0|2|1|transfer', 'split-occupied|transfer|3|0|2|split',
               'merge-empty|transfer|3|4|2|merge', 'same-slot|transfer|0|0|1|transfer',
               'no-source|transfer|4|5|1|transfer', 'source-bound|transfer|36|0|1|transfer',
               'target-bound|transfer|0|36|1|transfer', 'zero-count|transfer|3|4|0|transfer',
               'max-clamp|transfer|3|4|4294967295|transfer', 'full|transfer|0|1|1|transfer',
               'selected-stone|select|1', 'full-selected|selected', 'select-bound|select|9',
               'select-wrap|select|4294967295', 'acquire-bound|acquire|36|minecraft:stone|1',
               'oversized-stack|acquire|0|minecraft:stone|65', 'zero-clears|acquire|1|minecraft:stone|0',
               'modified-key|modified|0|minecraft:stone|1', 'unsupported-key|acquire|0|minecraft:bedrock|1',
               'survival|abilities|0|1', 'survival-refused|acquire|0|minecraft:dirt|1',
               'survival-transfer|transfer|4|5|1|split', 'creative-no-build|abilities|1|0',
               'no-build-acquire|acquire|8|minecraft:dirt|1', 'no-build-selected|select|8',
               'no-build-held|selected', 'creative-restore|abilities|1|1']
    # Count clipping boundaries independently expected, with untouched sentinels
    # in slots 2, 8 and 35 and exact main-array equality after every transition.
    for i, (source, destination, requested) in enumerate(
            [(1, 0, 0), (1, 0, 1), (1, 0, 64), (64, 0, 63),
             (64, 0, 4294967295), (64, 63, 0), (64, 63, 64), (1, 64, 1)]):
        actions.extend([f'edge-{i}-source|acquire|10|minecraft:stone|{source}',
                        f'edge-{i}-target|acquire|11|minecraft:stone|{destination}',
                        f'edge-{i}-transfer|transfer|10|11|{requested}|transfer'])
    return actions


def focused_suite(executor):
    """executor(label,args,env=None) -> (stdout, process provenance)."""
    actions = transition_actions()
    expected = []
    current = empty(creative=True)
    for action in actions:
        current, observation = transition(current, action)
        expected.append(observation)
    stdout, processpin = executor('player-inventory-transitions', ['transitions', 'creative', *actions])
    actual = [json.loads(line) for line in stdout.splitlines() if line.strip()]
    require(len(actual) == len(expected), 'Inventory transition response count differs')
    for observed, desired in zip(actual, expected):
        require(observed == desired, 'Inventory transition differs: ' + desired['label'])
    survival = ['default-survival|inspect', 'default-refusal|acquire|0|minecraft:stone|1']
    expected_survival = []
    current = empty()
    for action in survival:
        current, observation = transition(current, action)
        expected_survival.append(observation)
    text, second_pin = executor('player-inventory-survival', ['transitions', 'survival', *survival])
    require([json.loads(line) for line in text.splitlines() if line.strip()] == expected_survival,
            'Default survival ability gate differs')
    return {'cases': len(expected) + len(expected_survival), 'processes': [processpin, second_pin],
            'expected_sha256': sha(json.dumps(expected + expected_survival, sort_keys=True).encode()),
            'full_slot_snapshot_compared_after_every_transition': True}


def close_fixtures(reference, table):
    """Actual Java insertion outcomes, with explicit retained-ownership refusal.

    The four client-side InventoryMenu.removed observations are not server
    close fixtures. The two ordered receiver sequences use the carried-first
    ordering established separately by the pinned server bytecode.
    """
    reference, table = Path(reference), Path(table)
    raw = reference.read_bytes()
    value = json.loads(raw)
    require(value['pin'] == '26.3' and sha(canonical(value['observations'])) ==
            value['observations_sha256'], 'Java close observation seal differs')
    require(value['loaded_official_classes']['all_verified_against_client_jar'],
            'Java close official class checks absent')
    require(sha(table.read_bytes()) == TABLE_SHA256, 'Full item table identity differs')

    def actual_stack(observed):
        if observed is None or observed.get('empty', False):
            return None
        item = observed.get('item', observed.get('visible_item'))
        count = observed.get('count', observed.get('visible_count'))
        require(isinstance(item, str) and isinstance(count, int) and count > 0,
                'Invalid nonempty Java close slot')
        return stack(item, count)

    def logical(observed):
        inventory = observed['inventory']
        require(inventory['container_size'] == 43 and inventory['main_length'] == 36,
                'Java durable topology differs')
        main = [actual_stack(slot) for slot in inventory['main_slots']]
        equipment = [actual_stack(slot) for slot in observed['equipment']]
        craft = [actual_stack(slot) for slot in observed['craft']]
        require((len(main), len(equipment), len(craft)) == (36, 7, 4),
                'Java close complete slot dimensions differ')
        return main + equipment + craft + [actual_stack(observed['carried'])]

    def abilities(observed):
        source = observed['inventory']['abilities']
        fields = {key: source[key] for key in
                  ('instabuild', 'maybuild', 'invulnerable', 'mayfly', 'flying')}
        fields.update(walking_speed=int(source['walking_speed_f32_bits'], 16),
                      flying_speed=int(source['flying_speed_f32_bits'], 16))
        return fields

    def item_counts(slots):
        counts = Counter()
        for slot in slots:
            if slot:
                counts[(slot['id'], slot['components'])] += slot['count']
        return counts

    tail = [stack(ITEMS[index % 3], index + 1) for index in range(16)]
    revision, fixtures = 23, []
    rows = [row for row in value['observations']
            if row['operation'] in ('return', 'return_sequence')]
    require(len(rows) == 22, 'Observed return receiver subset differs')
    for row in rows:
        require(row['ok'], 'Java close receiver failed: ' + row['id'])
        before, after = logical(row['before']), logical(row['after'])
        require(item_counts(before) == item_counts(after),
                'Executed receiver count retention differs: ' + row['id'])
        accepted = not any(after[43:])
        expected_slots = (after if accepted else before) + tail
        expected = {'id': row['id'], 'accepted': accepted,
                    'message': '' if accepted else
                    'menu retains carried or crafting items; return/drop authority is required before closing',
                    'selected': row['before']['inventory']['selected'],
                    'abilities': abilities(row['before']), 'opened': not accepted,
                    'revision': revision + int(accepted and any(before[43:])),
                    'result': None, 'logical_length': 48, 'catalog_count': 1658,
                    'all_backing_slots': expected_slots}
        fixtures.append({'before_slots': before + tail, 'expected': expected,
                         'before_result': None,
                         'scope': 'actual-return-match' if accepted else 'atomic-capacity-refusal'})

    # Separate complete raw-word/permission retention checks; these are not
    # relabeled Java observations. They reuse an observed returnable topology.
    basis = next(f for f in fixtures if f['expected']['id'] == 'return-order:creative')
    for label, patch in [
            ('raw-signed-zero-nan', {'walking_speed': 2147483648, 'flying_speed': 2143289429}),
            ('raw-negative-infinite', {'walking_speed': 4286578688, 'flying_speed': 3212836864}),
            ('maybuild-false-inventory-return', {'maybuild': False})]:
        fixture = copy.deepcopy(basis)
        fixture['expected']['id'] = label
        fixture['expected']['abilities'].update(patch)
        fixture['scope'] = 'full-profile-retention'
        fixtures.append(fixture)

    for source_id in ('empty:survival', 'empty:creative',
                      'return-order:creative', 'return-full:creative'):
        fixture = copy.deepcopy(next(f for f in fixtures if f['expected']['id'] == source_id))
        fixture['expected']['id'] = 'derived-cache:' + source_id
        fixture['before_result'] = stack('minecraft:stone', 1)
        if fixture['expected']['accepted']:
            fixture['expected']['revision'] = revision + 1
        else:
            fixture['expected']['result'] = fixture['before_result']
        fixture['scope'] = 'derived-cache-disposition'
        fixtures.append(fixture)

    arguments = [str(table.resolve())]
    for fixture in fixtures:
        expected, before = fixture['expected'], fixture['before_slots']
        require(len(before) == len(expected['all_backing_slots']) == 64,
                'Close fixture full backing length differs')
        require(item_counts(before) == item_counts(expected['all_backing_slots']),
                'Expected close outcome loses/invents an item')
        ability = expected['abilities']
        header = [expected['id'], expected['selected'],
                  *[int(ability[key]) for key in
                    ('instabuild', 'maybuild', 'invulnerable', 'mayfly', 'flying')],
                  ability['walking_speed'], ability['flying_speed'], revision,
                  '_' if fixture['before_result'] is None else
                  f'{fixture["before_result"]["id"]}~{fixture["before_result"]["count"]}']
        encoded = ['_' if slot is None else f'{slot["id"]}~{slot["count"]}' for slot in before]
        arguments.append('|'.join(map(str, header + encoded)))
    return arguments, fixtures, {'path': str(reference), 'sha256': sha(raw),
                                 'observations_sha256': value['observations_sha256']}


def close_suite(executor, reference, table):
    """executor(label,args,env=None) runs tests/player_inventory_close.bend."""
    arguments, fixtures, reference_pin = close_fixtures(reference, table)
    stdout, processpin = executor('player-inventory-close', arguments)
    actual = [json.loads(line) for line in stdout.splitlines() if line.strip()]
    require(len(actual) == len(fixtures), 'Native close observation count differs')
    for observed, fixture in zip(actual, fixtures):
        require(observed == fixture['expected'], 'Native close differs: ' + fixture['expected']['id'])
    return {'cases': len(fixtures), 'java_returnable_cases': 16,
            'atomic_capacity_refusal_cases': 6, 'additional_profile_retention_cases': 3,
            'derived_cache_disposition_cases': 4,
            'all64_backing_cells_and_all_saved_ability_words_compared': True,
            'expected_sha256': sha(canonical([fixture['expected'] for fixture in fixtures])),
            'reference': reference_pin, 'process': processpin,
            'excluded': 'whole ServerPlayer lifecycle, world-owned item drops, client removed no-op branch'}


def reference_suite(executor, reference):
    """Compare the observed selected/Slot.safeInsert subset, not click protocols.

    Setup uses explicit creative test acquisition, then restores the observed
    two build abilities before the tested call. Rejection names remain custom;
    every compared main-slot/selected/ability value comes directly from Java.
    """
    reference = Path(reference)
    data = reference.read_bytes()
    value = json.loads(data)
    rows = value['observations']
    require(value['pin'] == '26.3' and sha(canonical(rows)) == value['observations_sha256'],
            'Inventory Java observation seal differs')
    require(value['loaded_official_classes']['all_verified_against_client_jar'],
            'Inventory official class identity checks absent')

    def projection(state):
        require(state['main_length'] == 36 and state['selection_size'] == 9,
                'Observed main/hotbar dimensions differ')
        slots = [None if slot is None else stack(slot['item'], slot['count'])
                 for slot in state['main_slots']]
        require(len(slots) == 36, 'Observed main slots differ')
        return {'selected': state['selected'], 'slots': slots,
                'abilities': {key: state['abilities'][key] for key in ('instabuild', 'maybuild')}}

    selected = [row for row in rows if row['operation'] in ('select', 'insert', 'insert_empty')]
    require(len(selected) == 91, 'Pinned inventory comparison subset differs')
    actions, expected = [], []
    current = empty(creative=True)
    for index, row in enumerate(selected):
        before, after = projection(row['before']), projection(row['after'])
        setup = [f'ref-{index}-creative|abilities|1|1']
        touched = {i for i, slot in enumerate(current['slots']) if slot is not None}
        touched.update(i for i, slot in enumerate(before['slots']) if slot is not None)
        for slot in sorted(touched):
            target = before['slots'][slot]
            setup.append(f'ref-{index}-setup-{slot}|acquire|{slot}|{target["id"] if target else ITEMS[0]}|{target["count"] if target else 0}')
        setup.extend([f'ref-{index}-selection|select|{before["selected"]}',
                      f'ref-{index}-profile|abilities|{int(before["abilities"]["instabuild"])}|{int(before["abilities"]["maybuild"])}',
                      f'ref-{index}-before|inspect'])
        for command in setup:
            current, observation = transition(current, command)
            actions.append(command)
            expected.append(observation)
        require(current == before, 'Java fixture setup projection differs: ' + row['id'])
        if row['operation'] == 'select':
            command = f'ref-{index}-call|select|{row["input"]["slot"] & 0xffffffff}'
        else:
            amount = row['input']['amount'] if row['operation'] == 'insert' else 1
            command = f'ref-{index}-call|transfer|1|34|{amount}|transfer'
        current, observation = transition(current, command)
        require(current == after, 'Integer oracle differs from actual Java subset: ' + row['id'])
        # Use the raw observed projection as the expected native state.
        observation['inventory'] = after
        actions.append(command)
        expected.append(observation)
    stdout, processpin = executor('player-inventory-java-selected-transfer', ['transitions', 'creative', *actions])
    observed = [json.loads(line) for line in stdout.splitlines() if line.strip()]
    require(len(observed) == len(expected), 'Java inventory native response count differs')
    for actual, target in zip(observed, expected):
        require(actual == target, 'Java inventory state comparison differs: ' + target['label'])
    return {'java_cases': len(selected), 'selected_slot_cases': 9, 'safe_insert_cases': 82,
            'native_observations_including_setup': len(expected), 'process': processpin,
            'reference': {'path': str(reference), 'sha256': sha(data)},
            'observations_sha256': value['observations_sha256'],
            'comparison': 'exact 36 main slots, selected slot and two build abilities',
            'excluded': 'custom rejection names, split/merge admission, menu clicks, equipment, modified components'}


def inventory_root(record, snapshot):
    slots = [P.compound([]) if slot is None else P.compound([
        ('id', N.Value(8, N.text(slot['id']))), ('count', N.Value(3, slot['count']))])
        for slot in snapshot['slots']]
    return N.RootTag(N.text(NAME), P.compound([
        ('format', N.Value(3, 2)), ('record', N.Value(7, record)),
        ('selected', N.Value(3, snapshot['selected'])),
        ('instabuild', N.Value(1, int(snapshot['abilities']['instabuild']))),
        ('maybuild', N.Value(1, int(snapshot['abilities']['maybuild']))),
        ('slots', N.Value(9, (10, slots)))]))


def inventory_bytes(record, snapshot):
    return record if snapshot == empty() else N.encode_root(inventory_root(record, snapshot))


def inventory_full_root(record, snapshot, equipment, status, generation):
    """Independently construct the explicit format3 physical NBT fixture.

    record and generation are complete standalone NBT bytes. Equipment order is
    feet, legs, chest, head, offhand, BODY, SADDLE. The five status fields retain
    all raw binary32 words; no Python float conversion occurs. This constructor
    intentionally emits format3 even if a particular fixture could use format2.
    """
    slot_tags = lambda slots: [P.compound([]) if slot is None else P.compound([
        ('id', N.Value(8, N.text(slot['id']))), ('count', N.Value(3, slot['count']))])
        for slot in slots]
    ability_fields = [(name, N.Value(1, int(status[name]))) for name in STATUS_FIELDS[:3]]
    ability_fields.extend((name, N.Value(5, status[name])) for name in STATUS_FIELDS[3:])
    return N.RootTag(N.text(NAME), P.compound([
        ('format', N.Value(3, 3)), ('record', N.Value(7, record)),
        ('selected', N.Value(3, snapshot['selected'])),
        ('instabuild', N.Value(1, int(snapshot['abilities']['instabuild']))),
        ('maybuild', N.Value(1, int(snapshot['abilities']['maybuild']))),
        ('slots', N.Value(9, (10, slot_tags(snapshot['slots'])))),
        ('equipment', N.Value(9, (10, slot_tags(equipment)))),
        ('abilities', P.compound(ability_fields)), ('generation', N.Value(7, generation))]))


def inventory_full_bytes(record, snapshot, equipment, status, generation):
    return N.encode_root(inventory_full_root(record, snapshot, equipment, status, generation))


def _full_item_limits(table=None):
    path = Path(table or Path(__file__).resolve().parents[1] / 'generated/reference_item_metadata.tsv')
    raw = path.read_bytes()
    require(sha(raw) == TABLE_SHA256, 'Full inventory item table hash differs')
    rows = list(csv.DictReader(io.StringIO(raw.decode()), delimiter='\t'))
    require(len(rows) == 1658, 'Full inventory registry count differs')
    return {row['identifier']: int(row['default_stack_max_stack_size']) for row in rows
            if row['enabled_default_flags'] == 'True' and row['identifier'] != 'minecraft:air'}


def parse_inventory_full(data, *, table=None):
    """Independent format3 durable projection for current save/reload fixtures.

    Generator bytes stay exact and receive a separate bounded physical NBT
    parse. Generator-semantic acceptance belongs to the focused WGC suite.
    Legacy/version2 acceptance keeps its existing parse_inventory entry point.
    """
    root = N.Reader(data, max_bytes=65536, max_depth=4, max_elements=16384).root()
    require(root.name == N.text(NAME), 'Full inventory root differs')
    fields = P.fields(root.value, FULL_FIELDS)
    require(P.scalar(fields['format'], 3) == 3, 'Full inventory format differs')
    require(fields['record'].kind == 7, 'Full player record is not ByteArray')
    record = R.encode(R.decode(fields['record'].payload))
    selected = P.scalar(fields['selected'], 3)
    require(0 <= selected < 9, 'Full inventory selection differs')
    abilities = {name: bool(P.boolean(fields[name])) for name in ('instabuild', 'maybuild')}
    limits = _full_item_limits(table)

    def slots(tag, count):
        require(tag.kind == 9 and tag.payload[0] == 10 and len(tag.payload[1]) == count,
                'Full inventory slot shape differs')
        result = []
        for value in tag.payload[1]:
            require(value.kind == 10, 'Full inventory slot is not Compound')
            if not value.payload:
                result.append(None)
                continue
            members = P.fields(value, ('id', 'count'))
            require(members['id'].kind == 8, 'Full inventory item is not String')
            item = ''.join(chr(unit) for unit in members['id'].payload)
            amount = P.scalar(members['count'], 3)
            require(item in limits and 1 <= amount <= limits[item], 'Full inventory item limit differs')
            result.append(stack(item, amount))
        return result

    status_fields = P.fields(fields['abilities'], STATUS_FIELDS)
    status = {name: bool(P.boolean(status_fields[name])) for name in STATUS_FIELDS[:3]}
    status.update((name, P.scalar(status_fields[name], 5)) for name in STATUS_FIELDS[3:])
    generation = fields['generation']
    require(generation.kind == 7, 'Full inventory generation is not ByteArray')
    N.Reader(generation.payload, max_bytes=16384, max_depth=8, max_elements=4096).root()
    return record, {'main': {'selected': selected, 'slots': slots(fields['slots'], 36), 'abilities': abilities},
                    'equipment': slots(fields['equipment'], 7), 'status': status,
                    'generation': generation.payload}


def parse_inventory(data):
    """Independent saved-payload projection, also used by atomic-save acceptance."""
    root = N.Reader(data, max_bytes=65536, max_depth=4, max_elements=16384).root()
    if root.name == R.NAME:
        return R.encode(R.decode(data)), empty()
    require(root.name == N.text(NAME), 'Inventory record root differs')
    fields = P.fields(root.value, FIELDS)
    require(P.scalar(fields['format'], 3) == 2, 'Inventory record version differs')
    require(fields['record'].kind == 7, 'Nested player record is not ByteArray')
    record = R.encode(R.decode(fields['record'].payload))
    selected = P.scalar(fields['selected'], 3)
    require(0 <= selected <= 8, 'Inventory hotbar selection differs')
    abilities = {'instabuild': bool(P.boolean(fields['instabuild'])),
                 'maybuild': bool(P.boolean(fields['maybuild']))}
    tag = fields['slots']
    require(tag.kind == 9 and tag.payload[0] == 10 and len(tag.payload[1]) == 36, 'Inventory slot shape differs')
    slots = []
    for value in tag.payload[1]:
        require(value.kind == 10, 'Inventory slot is not Compound')
        if not value.payload:
            slots.append(None)
            continue
        fs = P.fields(value, ('id', 'count'))
        require(fs['id'].kind == 8, 'Inventory item is not String')
        item = ''.join(chr(v) for v in fs['id'].payload)
        count = P.scalar(fs['count'], 3)
        require(item in ITEMS and 1 <= count <= 64, 'Inventory item/count is invalid')
        slots.append(stack(item, count))
    return record, {'selected': selected, 'slots': slots, 'abilities': abilities}


@dataclasses.dataclass(frozen=True)
class CodecCase:
    name: str
    data: bytes
    expected: bytes | None
    snapshot: dict | None
    schema: int = 1


def codec_corpus():
    record = R.encode(R.default_record())
    base = empty(creative=True)
    base['selected'] = 8
    for index, item, count in ((0, ITEMS[0], 64), (8, ITEMS[1], 1), (35, ITEMS[2], 16)):
        base['slots'][index] = stack(item, count)
    cases = [CodecCase('legacy-byte-identical', record, record, empty())]
    for name, snapshot in [('empty-survival', empty()), ('empty-creative', empty(creative=True)), ('populated', base)]:
        cases.append(CodecCase(name, N.encode_root(inventory_root(record, snapshot)), inventory_bytes(record, snapshot), snapshot))
    for build, maybuild in ((False, False), (False, True), (True, False), (True, True)):
        snapshot = copy.deepcopy(base)
        snapshot['abilities'] = {'instabuild': build, 'maybuild': maybuild}
        expected = inventory_bytes(record, snapshot)
        cases.append(CodecCase(f'abilities-{int(build)}-{int(maybuild)}', expected, expected, snapshot))
    tree = inventory_root(record, base)
    fields = list(tree.value.payload)
    reordered = N.RootTag(tree.name, N.Value(10, list(reversed(fields))))
    cases.append(CodecCase('top-field-order', N.encode_root(reordered), inventory_bytes(record, base), base))

    def reject(name, root=None, schema=1, data=None):
        cases.append(CodecCase(name, data if data is not None else N.encode_root(root), None, None, schema))

    def replace(name, value):
        return N.RootTag(tree.name, N.Value(10, [(key, value if key == N.text(name) else old) for key, old in fields]))

    for name in FIELDS:
        reject('missing-' + name, N.RootTag(tree.name, N.Value(10, [(key, value) for key, value in fields if key != N.text(name)])))
        reject('duplicate-' + name, N.RootTag(tree.name, N.Value(10, fields + [next(pair for pair in fields if pair[0] == N.text(name))])))
        reject('wrong-type-' + name, replace(name, N.Value(6, 0)))
    reject('extra-field', N.RootTag(tree.name, N.Value(10, fields + [(N.text('extra'), N.Value(3, 0))])))
    reject('wrong-root', N.RootTag(N.text('bendex:other'), tree.value))
    reject('wrong-format', replace('format', N.Value(3, 1)))
    reject('wrong-schema', schema=2, data=N.encode_root(tree))
    for selected in (9, 0xffffffff):
        reject(f'selected-{selected}', replace('selected', N.Value(3, selected)))
    for field in ('instabuild', 'maybuild'):
        reject(field + '-not-bool', replace(field, N.Value(1, 2)))
    slots = next(value.payload[1] for key, value in fields if key == N.text('slots'))
    reject('slot-count-35', replace('slots', N.Value(9, (10, slots[:35]))))
    reject('slot-count-37', replace('slots', N.Value(9, (10, slots + [P.compound([])]))))
    reject('slot-list-kind', replace('slots', N.Value(9, (3, [N.Value(3, 0)] * 36))))
    for name, slot in [('unsupported-item', P.compound([('id', N.Value(8, N.text('minecraft:bedrock'))), ('count', N.Value(3, 1))])),
                       ('zero-count', P.compound([('id', N.Value(8, N.text(ITEMS[0]))), ('count', N.Value(3, 0))])),
                       ('count-65', P.compound([('id', N.Value(8, N.text(ITEMS[0]))), ('count', N.Value(3, 65))])),
                       ('slot-extra', P.compound([('id', N.Value(8, N.text(ITEMS[0]))), ('count', N.Value(3, 1)), ('components', N.Value(8, N.text('')))])),
                       ('slot-missing-count', P.compound([('id', N.Value(8, N.text(ITEMS[0])))])),
                       ('slot-duplicate-id', P.compound([('id', N.Value(8, N.text(ITEMS[0]))), ('id', N.Value(8, N.text(ITEMS[0]))), ('count', N.Value(3, 1))]))]:
        changed = list(slots)
        changed[0] = slot
        reject(name, replace('slots', N.Value(9, (10, changed))))
    reject('empty-nested-record', replace('record', N.Value(7, b'')))
    reject('trailing-byte', data=N.encode_root(tree) + b'\x00')
    reject('truncated-payload', data=N.encode_root(tree)[:-1])
    reject('byte-budget', data=N.encode_root(tree) + b'\x00' * 65537)
    # Encoding fresh is deliberately excluded from the wire; decoding every
    # accepted payload must report False, even if it came from fresh creation.
    return record, cases


def codec_suite(executor, work):
    work = Path(work)
    work.mkdir(parents=True, exist_ok=True)
    record, cases = codec_corpus()
    args = ['codec-batch']
    outputs = []
    for index, case in enumerate(cases):
        input_path = work / f'{index:03d}-{case.name}.nbt'
        output_path = work / f'{index:03d}-{case.name}.out'
        input_path.write_bytes(case.data)
        require(not output_path.exists(), 'Codec output must be fresh: ' + str(output_path))
        outputs.append(output_path)
        args.extend([str(case.schema), str(input_path), str(output_path)])
    stdout, processpin = executor('player-inventory-codec-corpus', args)
    actual = [json.loads(line) for line in stdout.splitlines() if line.strip()]
    require(len(actual) == len(cases), 'Inventory codec response count differs')
    for case, result, output in zip(cases, actual, outputs):
        if case.expected is None:
            require(result.get('status') == 'error' and not output.exists(), 'Invalid inventory accepted: ' + case.name)
        else:
            require(result == {'status': 'ok', 'fresh': False, 'inventory': case.snapshot}, 'Codec projection differs: ' + case.name)
            require(output.read_bytes() == case.expected, 'Codec physical bytes differ: ' + case.name)
            require(parse_inventory(output.read_bytes()) == (record, case.snapshot), 'Independent codec decode differs: ' + case.name)
    pins = [processpin]
    for profile, snapshot in [('survival', empty()), ('creative', empty(creative=True))]:
        output = work / ('initial-' + profile + '.nbt')
        require(not output.exists(), 'Fresh initial output already exists')
        stdout, pin = executor('player-inventory-initial-' + profile, ['initial', profile, str(output)])
        require(json.loads(stdout) == {'status': 'ok', 'fresh': True, 'inventory': snapshot}, 'Fresh profile/provenance differs: ' + profile)
        require(output.read_bytes() == inventory_bytes(record, snapshot), 'Fresh profile bytes differ: ' + profile)
        pins.append(pin)
    return {'cases': len(cases) + 2, 'accepted': sum(case.expected is not None for case in cases) + 2,
            'rejected': sum(case.expected is None for case in cases), 'processes': pins,
            'corpus_sha256': sha(b''.join(case.data for case in cases)),
            'legacy_empty_byte_identical': True, 'fresh_flag_excluded_from_wire': True,
            'loaded_abilities_preserved': True}
