#!/usr/bin/env python3
"""Focused actual initialized-default validator/slot-codec consumer.

The caller supplies the existing bounded native executor. This helper builds
independent fixtures from pinned Java maps/outputs and compares every owned
inventory cell and raw player field; it never implements live game admission.
"""
from __future__ import annotations
import copy
import hashlib
import json
from pathlib import Path
import test_nbt as N

ROOT = Path(__file__).resolve().parents[1]
ENTRY = ROOT / 'tests/player_item_components.bend'
TABLE = ROOT / 'generated/reference_item_metadata.tsv'
REFERENCE = ROOT / 'reference/crafting_recipe_components.json'


def pin(path):
    path = Path(path)
    data = path.read_bytes()
    return {'path': str(path.resolve()), 'bytes': len(data),
            'sha256': hashlib.sha256(data).hexdigest()}


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=False)


def identity(effective, defaults):
    if effective == defaults:
        return ''
    limit = effective.get('minecraft:max_stack_size', 1)
    return 'BendCraftComponents1\t' + str(limit) + '\t' + canonical(effective)


def compound(fields):
    return N.Value(10, tuple((N.text(name), value) for name, value in fields))


def component_tag(name, value):
    if name.startswith('!') or name == 'minecraft:unbreakable':
        return compound([])
    if name == 'minecraft:enchantment_glint_override':
        return N.Value(1, int(value))
    if name == 'minecraft:suspicious_stew_effects':
        entries = []
        for effect in value:
            fields = [('id', N.Value(8, N.text(effect['id'])))]
            if effect.get('duration', 160) != 160:
                fields.append(('duration', N.Value(3, effect['duration'] & 0xffffffff)))
            entries.append(compound(fields))
        return N.Value(9, (10 if entries else 0, tuple(entries)))
    return N.Value(3, value & 0xffffffff)


def physical(case, defaults):
    fields = [('id', N.Value(8, N.text(case['id']))),
              ('count', N.Value(3, case['count']))]
    if case['components']:
        effective = json.loads(case['components'].split('\t', 2)[2])
        base = defaults[case['id']]
        patch = {name: value for name, value in effective.items()
                 if name not in base or value != base[name]}
        patch.update({'!' + name: {} for name in base if name not in effective})
        # Actual patch reconstruction lists sorted additions then sorted
        # removals; each value comes from the pinned codec observation.
        ordered = sorted((n, v) for n, v in patch.items() if not n.startswith('!'))
        ordered += sorted((n, v) for n, v in patch.items() if n.startswith('!'))
        fields.append(('components', compound([(n, component_tag(n, v)) for n, v in ordered])))
    return N.encode_root(N.RootTag(N.text(''), compound(fields)))


def raw_physical_cases(defaults):
    rows = []
    def add(label, item, count, members, decoded=None):
        value = compound([('id', N.Value(8, N.text(item))),
                          ('count', N.Value(3, count)), ('components', compound(members))])
        rows.append({'case': {'label': label, 'bytes': list(N.encode_root(N.RootTag(N.text(''), value)))},
                     'decoded': decoded})
    def key(item, count, patch):
        effective = copy.deepcopy(defaults[item]); effective.update(patch)
        return {'id': item, 'components': identity(effective, defaults[item]), 'count': count}
    add('numeric-repair-tag', 'minecraft:stone', 64, [('minecraft:repair_cost', N.Value(1, 17))],
        key('minecraft:stone', 64, {'minecraft:repair_cost': 17}))
    add('no-op-physical-patch', 'minecraft:stone', 64, [],
        {'id': 'minecraft:stone', 'components': '', 'count': 64})
    def effect(fields):
        return N.Value(9, (10, (compound(fields),)))
    speed = ('id', N.Value(8, N.text('minecraft:speed')))
    for label, fields in [
        ('unknown-effect', [('id', N.Value(8, N.text('minecraft:missing_effect')))]),
        ('wrong-duration-type', [speed, ('duration', N.Value(8, N.text('bad')))]),
        ('duplicate-effect-field', [speed, ('duration', N.Value(3, 7)), ('duration', N.Value(3, 8))]),
        ('discarded-effect-field', [speed, ('unexpected', N.Value(3, 7))]),
    ]:
        add(label, 'minecraft:suspicious_stew', 1, [('minecraft:suspicious_stew_effects', effect(fields))])
    add('wrong-effect-list-type', 'minecraft:suspicious_stew', 1,
        [('minecraft:suspicious_stew_effects', N.Value(9, (8, (N.Value(8, N.text('minecraft:speed')),))))])
    add('duplicate-patch-field', 'minecraft:stone', 1,
        [('minecraft:enchantment_glint_override', N.Value(1, 0)),
         ('minecraft:enchantment_glint_override', N.Value(1, 1))])
    add('qualified-alias-duplicate', 'minecraft:stone', 1,
        [('repair_cost', N.Value(3, 7)), ('minecraft:repair_cost', N.Value(3, 17))])
    add('discarded-unknown-patch', 'minecraft:stone', 1, [('bendcraft:missing', N.Value(3, 7))])
    add('wrong-glint-type', 'minecraft:stone', 1,
        [('minecraft:enchantment_glint_override', N.Value(8, N.text('true')))])
    add('physical-oversized-damageable', 'minecraft:diamond_sword', 2, [('minecraft:damage', N.Value(3, 1))])
    return rows


def complete_owner(key, accepted):
    backing = [None] * 64
    backing[0] = {'id': 'minecraft:stone', 'components': '', 'count': 7}
    backing[63] = {'id': 'hidden:sentinel', 'components': 'opaque\tretained', 'count': 0xffffffff}
    if accepted:
        backing[2] = key
    return {'accepted': accepted, 'backing': backing, 'length': 48,
            'selected': 7, 'abilities': [True, False],
            'status': [True, True, True, 0x7fc01234, 0x80000000],
            'opened': True, 'revision': '23',
            'result': {'id': 'minecraft:dirt', 'components': '', 'count': 4},
            'catalog_count': 1658}


def prepare(directory):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    reference = json.loads(REFERENCE.read_text())
    assert reference['pin'] == '26.3'
    defaults = {row['id']: row['components'] for row in reference['defaults']}
    java = {row['id']: row for row in reference['cases']}
    cases, expected = [], []

    def add(label, item, key, count, maximum, valid, structural, *, mode='initialized', observed=None):
        row = {'label': label, 'id': item, 'components': key, 'count': count, 'mode': mode}
        cases.append(row)
        expected.append({'case': row, 'metadata': maximum, 'valid': valid,
                         'structural': structural, 'java_case': observed})

    labels = ['duration_negative', 'remove_effects', 'remove_stack_size', 'stack99',
              'damage_and_stack1', 'remove_damage', 'damage_above_max',
              'unbreakable', 'glint_false', 'glint_true', 'remove_default_rarity']
    for label in labels:
        observed = java['bendcraft:' + label]
        output = observed['output']
        assert observed['accepted'] and not output['empty']
        item = output['id']
        add(label, item, identity(output['components'], defaults[item]), output['count'],
            output['limit'], True, True, observed=observed['id'])

    stone, sword = defaults['minecraft:stone'], defaults['minecraft:diamond_sword']
    def modified(label, item, patch, count=1, maximum=None, valid=True, structural=True, mode='initialized'):
        base = defaults[item]
        value = copy.deepcopy(base)
        for name, replacement in patch.items():
            if name.startswith('!'):
                value.pop(name[1:], None)
            else:
                value[name] = replacement
        limit = value.get('minecraft:max_stack_size', 1) if maximum is None else maximum
        add(label, item, identity(value, base), count, limit, valid, structural, mode=mode)

    modified('repair-cost', 'minecraft:stone', {'minecraft:repair_cost': 17}, count=64)
    modified('modified-pearl', 'minecraft:ender_pearl', {'minecraft:enchantment_glint_override': True}, count=16)
    modified('damageable-count2', 'minecraft:diamond_sword', {'minecraft:damage': 1}, count=2, valid=False, structural=False)
    modified('damageable-stack64', 'minecraft:diamond_sword', {'minecraft:max_stack_size': 64}, maximum=None, valid=False, structural=False)
    expected[-1]['metadata'] = None
    modified('unsupported-changed-rarity', 'minecraft:stone', {'minecraft:rarity': 'epic'}, valid=False)
    expected[-1]['metadata'] = None
    modified('forged-item-model', 'minecraft:stone', {'minecraft:item_model': 'minecraft:dirt'}, valid=False)
    expected[-1]['metadata'] = None
    modified('unknown-component', 'minecraft:stone', {'bendcraft:missing': {}}, valid=False, structural=False)
    expected[-1]['metadata'] = None
    for mode in ['disabled', 'missing_defaults', 'uninitialized']:
        modified(mode, 'minecraft:stone', {'minecraft:enchantment_glint_override': True}, valid=False, mode=mode)
        expected[-1]['metadata'] = None
    modified('air', 'minecraft:air', {'minecraft:enchantment_glint_override': True}, valid=False)
    expected[-1]['metadata'] = None
    glint = next(c for c in cases if c['label'] == 'glint_true')['components']
    add('missing-item', 'minecraft:missing_item', glint, 1, None, False, True)
    add('wrong-header-limit', 'minecraft:stone', glint.replace('\t64\t', '\t1\t', 1), 1, None, False, False)
    add('noncanonical-whitespace', 'minecraft:stone', glint.replace('\t{', '\t {', 1), 1, None, False, False)
    add('opaque', 'minecraft:stone', 'opaque', 1, None, False, False)
    add('default-equal-envelope', 'minecraft:stone', 'BendCraftComponents1\t64\t' + canonical(stone), 1, None, False, True)
    add('duplicate-map-member', 'minecraft:stone', glint[:-1] + ',"minecraft:repair_cost":0}', 1, None, False, False)
    stew = next(c for c in cases if c['label'] == 'duration_negative')
    add('legacy-stew-authority', stew['id'], stew['components'], 1, 1, True, True, mode='uninitialized')
    add('plain-stone', 'minecraft:stone', '', 64, 64, True, True)
    wanted = sorted({c['id'] for c in cases if c['id'] in defaults})
    raw = raw_physical_cases(defaults)
    request = {'defaults': [{'id': item, 'components': defaults[item]} for item in wanted], 'cases': cases,
               'physical_cases': [row['case'] for row in raw]}
    path = directory / 'fixtures.json'
    path.write_text(canonical(request) + '\n')
    assert path.stat().st_size <= 65536
    for value in expected:
        if value['valid']:
            value['physical'] = list(physical(value['case'], defaults))
    return {'input': pin(path), 'table': pin(TABLE), 'reference': pin(REFERENCE),
            'expected': expected, 'initialized_maps': len(wanted),
            'java_observations': len(labels), 'physical_expected': raw}


def suite(executor, directory):
    prepared = prepare(directory)
    stdout, process = executor('player-item-components', [str(TABLE), prepared['input']['path']])
    payload = json.loads(stdout)
    assert set(payload) == {'admission', 'physical'}
    actual = payload['admission']
    assert len(actual) == len(prepared['expected'])
    for row, expected in zip(actual, prepared['expected']):
        case = expected['case']
        for name in ['label', 'metadata', 'valid', 'structural']:
            wanted = case['label'] if name == 'label' else expected[name]
            assert row[name] == wanted, (case['label'], name, row[name], wanted)
        if expected['valid']:
            assert row['physical']['bytes'] == expected['physical'], ('physical', case['label'])
            assert row['physical']['decoded'] == {k: case[k] for k in ['id', 'components', 'count']}
        else:
            assert set(row['physical']) == {'error'}, ('codec refusal', case['label'])
        owner = complete_owner({k: case[k] for k in ['id', 'components', 'count']}, expected['valid'])
        assert row['owner'] == owner, ('complete owner', case['label'])
    assert len(payload['physical']) == len(prepared['physical_expected'])
    for row, expected in zip(payload['physical'], prepared['physical_expected']):
        label = expected['case']['label']
        assert row['label'] == label
        if expected['decoded'] is None:
            assert set(row['decoded']) == {'error'}, ('physical refusal', label, row['decoded'])
        else:
            assert row['decoded'] == expected['decoded'], ('physical decoded', label, row['decoded'])
        assert row['owner'] == complete_owner(expected['decoded'], expected['decoded'] is not None), ('physical owner', label)
    for name in ['table', 'reference', 'input']:
        assert pin(prepared[name]['path']) == prepared[name], ('input drift', name)
    return {'result': 'pass', 'cases': len(actual), 'physical_cases': len(payload['physical']), 'process': process,
            'input': prepared['input'], 'table': prepared['table'], 'reference': prepared['reference'],
            'java_observations': prepared['java_observations'], 'initialized_maps': prepared['initialized_maps']}
