"""Independent ordered NBT expectations for the actual cooking publisher.

This file owns fixture serialization and physical-byte inspection only. It does
not advance a world, construct a live owner, or infer incarnation history from
notifications. Strings inside recovery payloads remain raw U32 Char words.
Pass the actual pinned cooking catalog to authenticate complete cached bindings.
"""
from __future__ import annotations

import re

import test_nbt as N

MAX_NAT = (1 << 48) - 1
MAX_U32 = (1 << 32) - 1
PUBLICATION_ROOT = 'bendex:cooking-publication'
EFFECTS_ROOT = 'bendex:cooking-effects'
DIMENSIONS = ('minecraft:overworld', 'minecraft:the_nether', 'minecraft:the_end')
DIMENSION_WORDS = frozenset(tuple(map(ord, value)) for value in DIMENSIONS)


def require(valid, message):
    if not valid:
        raise ValueError('Independent cooking publication: ' + message)


def words(value):
    """Convert fixture strings to Bend Char words without UTF normalization."""
    result = tuple(map(ord, value)) if isinstance(value, str) else tuple(value)
    require(all(type(word) is int and 0 <= word <= MAX_U32 for word in result), 'raw Char words')
    return result


def text(value):
    """Readable ASCII identity; opaque raw strings should remain word tuples."""
    result = words(value)
    require(all(word < 128 for word in result), 'ASCII identity')
    return ''.join(map(chr, result))


def position(dimension, x, y, z):
    return {'dimension': words(dimension), 'x': x, 'y': y, 'z': z}


def chunk(dimension, x, z):
    return {'dimension': words(dimension), 'x': x, 'z': z}


def binding(state, block, family, lit, unlit_state, lit_state):
    return {'state': state, 'block': words(block), 'family': family, 'lit': int(lit),
            'unlit_state': unlit_state, 'lit_state': lit_state}


def source(point, cached, incarnation):
    return {'position': point, 'binding': cached, 'incarnation': incarnation}


def receipt(point, producer, target, sequence):
    return {'position': point, 'source': producer, 'chunk': target, 'sequence': sequence}


def dirty(target, sequence):
    return {'chunk': target, 'sequence': sequence}


def tip():
    return {'kind': 0}


def leaf(key, value):
    return {'kind': 1, 'key': words(key), 'value': value}


def node(position, lo, hi):
    return {'kind': 2, 'position': position, 'lo': lo, 'hi': hi}


def catalog_bindings(catalog):
    """Normalize actual reference rows or an already indexed binding mapping."""
    rows = catalog['bindings'] if 'bindings' in catalog else catalog
    rows = rows.values() if isinstance(rows, dict) else rows
    result = {}
    for row in rows:
        family = row['family']
        if isinstance(family, str):
            if family == 'campfire':
                require(row.get('fire_damage') in (1, 2), 'actual catalog campfire damage')
                family = 3 + row['fire_damage']
            else:
                require(family in ('smelting', 'blasting', 'smoking'), 'actual catalog family')
                family = {'smelting': 0, 'blasting': 1, 'smoking': 2}[family]
        value = binding(row['state'], row['block'], family, row['lit'],
                        row['unlit_state'], row['lit_state'])
        require(value['state'] not in result, 'duplicate actual catalog state')
        result[value['state']] = value
    return result


def binding_for(catalog, state):
    values = catalog_bindings(catalog)
    require(state in values, 'state is absent from actual cooking catalog')
    return values[state]


def _compound(**values):
    return N.Value(10, tuple((N.text(name), value) for name, value in values.items()))


def _members(value, names):
    require(value.kind == 10 and tuple(name for name, _ in value.payload) ==
            tuple(N.text(name) for name in names), 'exact ordered fields: ' + ','.join(names))
    return {name: item for name, (_, item) in zip(names, value.payload, strict=True)}


def _uint(value):
    require(value.kind == 3, 'raw U32 TAG_Int')
    return value.payload


def _integer(value):
    require(type(value) is int and 0 <= value <= MAX_U32, 'fixture raw U32')
    return N.Value(3, value)


def _array(value):
    return N.Value(11, words(value))


def _raw(value):
    require(value.kind == 11, 'raw Char TAG_IntArray')
    return words(value.payload)


def _natural(value):
    raw = _raw(value)
    require(1 <= len(raw) <= 15 and all(48 <= word <= 57 for word in raw),
            'ASCII Nat digits and length')
    encoded = ''.join(map(chr, raw))
    require(re.fullmatch(r'0|[1-9][0-9]*', encoded) is not None, 'canonical Nat decimal')
    number = int(encoded)
    require(number <= MAX_NAT, '48-bit native Nat bound')
    return number


def _nat_value(value):
    require(type(value) is int and 0 <= value <= MAX_NAT, 'fixture Nat bound')
    return _array(str(value))


def _list(value):
    require(value.kind == 9 and value.payload[0] == 10, 'exact Compound list')
    return value.payload[1]


def _position_value(value):
    return _compound(dimension=_array(value['dimension']), x=_integer(value['x']),
                     y=_integer(value['y']), z=_integer(value['z']))


def _position_read(value):
    fields = _members(value, ('dimension', 'x', 'y', 'z'))
    return position(_raw(fields['dimension']), *(_uint(fields[name]) for name in ('x', 'y', 'z')))


def _chunk_value(value):
    return _compound(dimension=_array(value['dimension']), x=_integer(value['x']), z=_integer(value['z']))


def _chunk_read(value):
    fields = _members(value, ('dimension', 'x', 'z'))
    return chunk(_raw(fields['dimension']), _uint(fields['x']), _uint(fields['z']))


def _binding_value(value):
    return _compound(state=_integer(value['state']), block=_array(value['block']),
                     family=_integer(value['family']), lit=_integer(value['lit']),
                     unlit_state=_integer(value['unlit_state']), lit_state=_integer(value['lit_state']))


def _binding_read(value):
    fields = _members(value, ('state', 'block', 'family', 'lit', 'unlit_state', 'lit_state'))
    result = binding(_uint(fields['state']), _raw(fields['block']), _uint(fields['family']),
                     _uint(fields['lit']), _uint(fields['unlit_state']), _uint(fields['lit_state']))
    require(result['family'] in range(6) and result['lit'] in (0, 1), 'binding family and boolean')
    return result


def _source_value(value):
    return _compound(position=_position_value(value['position']), binding=_binding_value(value['binding']),
                     incarnation=_nat_value(value['incarnation']))


def _source_read(value, catalog):
    fields = _members(value, ('position', 'binding', 'incarnation'))
    result = source(_position_read(fields['position']), _binding_read(fields['binding']),
                    _natural(fields['incarnation']))
    cached = result['binding']
    require(result['position']['dimension'] in DIMENSION_WORDS, 'source known dimension')
    require(cached['state'] == cached['lit_state' if cached['lit'] else 'unlit_state'],
            'source cached state/LIT partner')
    if catalog is not None:
        require(catalog.get(cached['state']) == cached, 'complete actual catalog binding authentication')
    return result


def _receipt_value(value):
    return _compound(position=_position_value(value['position']), source=_source_value(value['source']),
                     chunk=_chunk_value(value['chunk']), sequence=_nat_value(value['sequence']))


def _receipt_read(value, catalog):
    fields = _members(value, ('position', 'source', 'chunk', 'sequence'))
    return receipt(_position_read(fields['position']), _source_read(fields['source'], catalog),
                   _chunk_read(fields['chunk']), _natural(fields['sequence']))


def _dirty_value(value):
    return _compound(chunk=_chunk_value(value['chunk']), sequence=_nat_value(value['sequence']))


def _dirty_read(value):
    fields = _members(value, ('chunk', 'sequence'))
    return dirty(_chunk_read(fields['chunk']), _natural(fields['sequence']))


def _map_value(value):
    kind = value['kind']
    if kind == 0:
        return _compound(kind=_integer(0))
    if kind == 1:
        return _compound(kind=_integer(1), key=_array(value['key']), value=_nat_value(value['value']))
    require(kind == 2, 'map discriminant')
    return _compound(kind=_integer(2), position=_nat_value(value['position']),
                     lo=_map_value(value['lo']), hi=_map_value(value['hi']))


def _map_read(value):
    require(value.kind == 10 and value.payload and value.payload[0][0] == N.text('kind'), 'map kind field')
    kind = _uint(value.payload[0][1])
    if kind == 0:
        _members(value, ('kind',))
        return tip()
    if kind == 1:
        fields = _members(value, ('kind', 'key', 'value'))
        return leaf(_raw(fields['key']), _natural(fields['value']))
    require(kind == 2, 'map discriminant')
    fields = _members(value, ('kind', 'position', 'lo', 'hi'))
    return node(_natural(fields['position']), _map_read(fields['lo']), _map_read(fields['hi']))


def _key_valid(key):
    parts = text(key).split('/')
    require(len(parts) == 4 and parts[0] in DIMENSIONS, 'canonical incarnation position key')
    for coordinate in parts[1:]:
        require(1 <= len(coordinate) <= 10 and re.fullmatch(r'0|[1-9][0-9]*', coordinate) is not None
                and int(coordinate) <= MAX_U32, 'canonical raw U32 coordinate key')


def _bit(key, position):
    index, offset = divmod(position, 33)
    return False if index >= len(key) else True if offset == 0 else bool(key[index] >> (32 - offset) & 1)


def _diff(left, right):
    for index, (a, b) in enumerate(zip(left, right)):
        if a != b:
            return index * 33 + 33 - (a ^ b).bit_length()
    return min(len(left), len(right)) * 33


def _tree_leaves(tree):
    """Validate the stored topology directly; never normalize by reinsertion."""
    kind = tree['kind']
    if kind == 0:
        return ()
    if kind == 1:
        _key_valid(tree['key'])
        require(type(tree['value']) is int and 0 <= tree['value'] <= MAX_NAT, 'incarnation counter bound')
        return ((tree['key'], tree['value']),)
    require(kind == 2, 'map discriminant')
    left, right = _tree_leaves(tree['lo']), _tree_leaves(tree['hi'])
    split = tree['position']
    require(type(split) is int and 0 <= split <= MAX_NAT, 'Patricia split Nat bound')
    require(left and right and _diff(left[0][0], right[0][0]) == split, 'Patricia first split and nonempty children')
    for branch, leaves, high in ((tree['lo'], left, False), (tree['hi'], right, True)):
        require(branch['kind'] != 2 or branch['position'] > split, 'strictly increasing Patricia split')
        require(all(_diff(key, left[0][0]) >= split and _bit(key, split) == high for key, _ in leaves),
                'Patricia descendant prefix and bit partition')
    combined = left + right
    require(len({key for key, _ in combined}) == len(combined), 'unique incarnation map keys')
    return combined


def map_items(tree):
    """Independent lookup view alongside, without replacing, the retained tree."""
    return dict(_tree_leaves(tree))


def position_key(point):
    return words(text(point['dimension']) + '/' + '/'.join(str(point[name]) for name in ('x', 'y', 'z')))


def _chunk_key(target):
    return target['dimension'], target['x'], target['z']


def _chunk_valid(target):
    require(target['dimension'] in DIMENSION_WORDS, 'dirty known dimension')
    require(all(value < 134217728 or value >= 4160749568 for value in (target['x'], target['z'])),
            'signed section coordinate bound')


def chunk_for(point):
    def signed_section(value):
        return ((value if value < 1 << 31 else value - (1 << 32)) >> 4) & MAX_U32
    return chunk(point['dimension'], signed_section(point['x']), signed_section(point['z']))


def _journal_valid(sequence, unsaved, last, counters):
    seen = set()
    for value in unsaved:
        _chunk_valid(value['chunk'])
        require(0 < value['sequence'] <= sequence, 'positive bounded dirty revision')
        key = _chunk_key(value['chunk'])
        require(key not in seen, 'unique unsaved chunk')
        seen.add(key)
    require((sequence == 0 and last is None) or (sequence > 0 and last is not None), 'latest receipt presence')
    if last is not None:
        require(last['sequence'] == sequence and last['position'] == last['source']['position'] and
                last['chunk'] == chunk_for(last['position']), 'complete latest receipt chronology and owner/chunk position')
        require(last['source']['incarnation'] <= counters.get(position_key(last['position']), 0),
                'historical receipt incarnation bounded by retained counter')


def _publication_root(tree, sequence, unsaved, last):
    return N.RootTag(N.text(PUBLICATION_ROOT), _compound(format=_integer(1), incarnations=_map_value(tree),
        journal=_compound(sequence=_nat_value(sequence), unsaved=N.Value(9, (10, tuple(_dirty_value(v) for v in unsaved))),
                          last=N.Value(9, (10, () if last is None else (_receipt_value(last),))))))


def _publication_read(root, catalog):
    require(root.name == N.text(PUBLICATION_ROOT), 'exact publication root name')
    fields = _members(root.value, ('format', 'incarnations', 'journal'))
    require(_uint(fields['format']) == 1, 'publication format1')
    tree = _map_read(fields['incarnations'])
    counters = map_items(tree)
    journal = _members(fields['journal'], ('sequence', 'unsaved', 'last'))
    sequence = _natural(journal['sequence'])
    unsaved = tuple(_dirty_read(value) for value in _list(journal['unsaved']))
    latest = _list(journal['last'])
    require(len(latest) <= 1, 'zero or one latest receipt')
    last = _receipt_read(latest[0], catalog) if latest else None
    _journal_valid(sequence, unsaved, last, counters)
    return {'format': 1, 'incarnations': tree, 'journal': {'sequence': sequence, 'unsaved': unsaved, 'last': last}}


def encode_publication(tree, sequence, unsaved, last, catalog=None):
    root = _publication_root(tree, sequence, tuple(unsaved), last)
    _publication_read(root, None if catalog is None else catalog_bindings(catalog))
    return N.encode_root(root)


def decode_publication(raw, catalog=None):
    raw = bytes(raw)
    result = _publication_read(N.parse(raw), None if catalog is None else catalog_bindings(catalog))
    journal = result['journal']
    require(N.encode_root(_publication_root(result['incarnations'], journal['sequence'], journal['unsaved'], journal['last']))
            == raw, 'every physical publication byte independently reencoded')
    return result | {'raw': raw}


def _slot_value(value):
    return _compound() if value is None else _compound(id=_array(value['id']), components=_array(value['components']),
                                                       count=_integer(value['count']))


def _slot_read(value):
    if value.kind == 10 and not value.payload:
        return None
    fields = _members(value, ('id', 'components', 'count'))
    return {'id': _raw(fields['id']), 'components': _raw(fields['components']), 'count': _uint(fields['count'])}


def effect(kind, point, payload=None):
    return {'kind': kind, 'position': point, 'payload': payload}


def _effect_value(value):
    kind, payload = value['kind'], value['payload']
    if kind in (0, 3):
        require(payload is None, 'empty OwnerReset/legacy Dirty payload')
        encoded = _compound()
    elif kind == 1:
        encoded = _compound(slot=_integer(payload['slot']), item=_slot_value(payload['item']))
    elif kind == 2:
        encoded = _compound(recipe=_array(payload['recipe']), uses=_integer(payload['uses']),
                            experience_bits=_integer(payload['experience_bits']))
    elif kind in (4, 5):
        encoded = _nat_value(payload)
    else:
        require(kind == 6, 'effect discriminant')
        encoded = _source_value(payload)
    return _compound(kind=_integer(kind), position=_position_value(value['position']), payload=encoded)


def _effect_read(value, catalog):
    fields = _members(value, ('kind', 'position', 'payload'))
    kind, point, raw = _uint(fields['kind']), _position_read(fields['position']), fields['payload']
    if kind in (0, 3):
        _members(raw, ())
        payload = None
    elif kind == 1:
        payload_fields = _members(raw, ('slot', 'item'))
        payload = {'slot': _uint(payload_fields['slot']), 'item': _slot_read(payload_fields['item'])}
    elif kind == 2:
        payload_fields = _members(raw, ('recipe', 'uses', 'experience_bits'))
        payload = {'recipe': _raw(payload_fields['recipe']), 'uses': _uint(payload_fields['uses']),
                   'experience_bits': _uint(payload_fields['experience_bits'])}
    elif kind in (4, 5):
        payload = _natural(raw)
    else:
        require(kind == 6, 'effect discriminant')
        payload = _source_read(raw, catalog)
        require(point == payload['position'], 'OwnedDirty outer/source position equality')
    return effect(kind, point, payload)


def _effects_root(effects):
    format = 2 if any(value['kind'] == 6 for value in effects) else 1
    return N.RootTag(N.text(EFFECTS_ROOT), _compound(format=_integer(format),
        effects=N.Value(9, (10, tuple(_effect_value(value) for value in effects)))))


def _effects_read(root, catalog):
    require(root.name == N.text(EFFECTS_ROOT), 'exact effects root name')
    fields = _members(root.value, ('format', 'effects'))
    effects = tuple(_effect_read(value, catalog) for value in _list(fields['effects']))
    require(_uint(fields['format']) == (2 if any(value['kind'] == 6 for value in effects) else 1),
            'canonical effects format for actual OwnedDirty presence')
    return effects


def encode_effects(effects, catalog=None):
    root = _effects_root(tuple(effects))
    _effects_read(root, None if catalog is None else catalog_bindings(catalog))
    return N.encode_root(root)


def decode_effects(raw, catalog=None):
    raw = bytes(raw)
    effects = _effects_read(N.parse(raw), None if catalog is None else catalog_bindings(catalog))
    require(N.encode_root(_effects_root(effects)) == raw, 'every ordered effect byte independently reencoded')
    return effects
