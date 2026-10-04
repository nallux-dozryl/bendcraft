"""Independent test expectations for the declared fresh Actor020 entity owner.

Only fixture/oracle code lives here. It never advances a live world or supplies
entropy to the actor. Real constructor times are recovered from saved raw local
RNG words and must lie inside the observed monotonic operation interval.
"""
from __future__ import annotations

import copy
import json
import struct
from pathlib import Path

import test_nbt as N

MASK48 = (1 << 48) - 1
MASK64 = (1 << 64) - 1
LCG = 25214903917
INVERSE = 246154705703781
FACTORY = 1181783497276652981
INITIAL_FACTORY = 8682522807148012
ROOT_NAME = 'bendex:cooking-effect-entities'


def require(test, message):
    if not test:
        raise AssertionError(message)


def words(value):
    return [value >> 32 & 0xffffffff, value & 0xffffffff]


def number(value):
    require(len(value) == 2 and all(0 <= v <= 0xffffffff for v in value), '64-bit raw words')
    return value[0] << 32 | value[1]


def f32(value):
    return struct.unpack('>f', struct.pack('>f', value))[0]


def float_bits(value):
    return int.from_bytes(struct.pack('>f', value), 'big')


def double_words(value):
    return words(int.from_bytes(struct.pack('>d', value), 'big'))


def vector_words(value):
    return [word for x in value for word in double_words(x)]


def signed32(value):
    return value if value < 1 << 31 else value - (1 << 32)


class Legacy:
    def __init__(self, raw):
        self.raw = raw & MASK48
        self.draws = 0

    def next(self, bits):
        self.raw = (self.raw * LCG + 11) & MASK48
        self.draws += 1
        return self.raw >> (48 - bits)

    def double(self):
        return ((self.next(26) << 27) + self.next(27)) / float(1 << 53)

    def floating(self):
        return f32(self.next(24) / float(1 << 24))

    def long(self):
        return ((signed32(self.next(32)) << 32) + signed32(self.next(32))) & MASK64

    def bounded(self, bound):
        if bound & (bound - 1) == 0:
            return bound * self.next(31) >> 31
        while True:
            bits = self.next(31)
            value = bits % bound
            if bits - value + bound - 1 < 1 << 31:
                return value


def source(raw):
    return {'kind': 0, 'words': words(raw)}


def source_raw(value):
    require(value['kind'] == 0 and number(value['words']) <= MASK48, 'Actual fresh Legacy LEVEL source')
    return number(value['words'])


def factory_after(value, allocations=1):
    for _ in range(allocations):
        value = value * FACTORY & MASK64
    return value


def unwind(raw, count):
    for _ in range(count):
        raw = ((raw - 11) * INVERSE) & MASK48
    return raw


def clock_from_raw(raw, unique, begin, end):
    require(0 <= begin <= end and end - begin < 1 << 48, 'Observed constructor monotonic interval')
    low = (raw ^ LCG ^ unique) & MASK48
    observed = begin & ~MASK48 | low
    if observed < begin:
        observed += 1 << 48
    require(begin <= observed <= end, 'Recovered constructor time must be inside actual CLOCK_MONOTONIC interval')
    return observed


def fields(position, velocity, yaw):
    return {'position': vector_words(position), 'velocity': vector_words(velocity),
        'position_o': [0] * 6, 'position_old': [0] * 6, 'look': [yaw, 0, 0, 0],
        'head_yaw': 0, 'body_yaw': 0, 'fall_distance': [0, 0], 'on_ground': 0,
        'air': 300, 'fire': 0, 'portal_cooldown': 0, 'invulnerable': 0, 'needs_sync': 0}


def constructor(kind, unique, timestamp, dimension, entity_id, order, position, velocity, payload):
    unique = factory_after(unique)
    local = Legacy((unique ^ timestamp ^ LCG) & MASK48)
    most = local.long() & ~0xf000 | 0x4000
    least = local.long() & 0x3fffffffffffffff | 0x8000000000000000
    payload = copy.deepcopy(payload)
    if kind == 0:
        bob = f32(f32(local.floating() * f32(3.1415927)) * f32(2.0))
        yaw = float_bits(f32(local.floating() * f32(360.0)))
        local.double()
        local.double()
        payload['bob'] = float_bits(bob)
        require(local.draws == 10, 'Pinned ItemEntity constructor ten primitive local draws')
    else:
        yaw = float_bits(f32(local.floating() * f32(360.0)))
        velocity = ((local.double() * .2 - .1) * 2.,
                    local.double() * .2 * 2., (local.double() * .2 - .1) * 2.)
        require(local.draws == 11, 'Pinned ExperienceOrb constructor eleven primitive local draws')
    common = {'dimension': dimension, 'id': entity_id, 'uuid_most': words(most),
        'uuid_least': words(least), 'random': source(local.raw),
        'fields': fields(position, velocity, yaw), 'tick_count': 0, 'first_tick': 1,
        'removed': 0, 'accessible': 1, 'section_order': str(order)}
    return unique, {'kind': kind, 'common': common, 'payload': payload}


def item_payload(item):
    return {'item': item, 'age': 0, 'pickup_delay': 0, 'health': 5,
            'thrower': [], 'target': []}


def orb_payload(value):
    return {'value': value, 'age': 0, 'health': 5, 'count': 1, 'following': []}


def drop_position(level, position):
    x, y, z = position
    return x + level.double() * .75 + .125, y + level.double() * .75, z + level.double() * .75 + .125


def drop_velocity(level):
    def triangle(mean):
        a, b = level.double(), level.double()
        return mean + .11485000171139836 * (a - b)
    return triangle(0.), triangle(.2), triangle(0.)


def reset_expected(before, observed, begin, end, position, items):
    """Two count2 Drops, EmptyDrop, and guaranteed exact7 XP; no orb merge."""
    level = Legacy(source_raw(before['level_random']))
    unique = number(before['seed_uniquifier'])
    cursor, order = before['last_id'], int(before['next_section_order'])
    records = copy.deepcopy(before['records'])
    require(not records, 'Focused fresh owner starts with no entities before removal')
    require(len(observed['records']) == 3, 'Two actual Item records and one actual Orb record')
    times = []
    for index, item in enumerate(items):
        point = drop_position(level, position[1:])
        require(item['count'] == 2, 'Focused count2 fixture has one split chunk')
        level.bounded(21)
        velocity = drop_velocity(level)
        unique_next = factory_after(unique)
        raw = source_raw(observed['records'][index]['common']['random'])
        timestamp = clock_from_raw(unwind(raw, 10), unique_next, begin, end)
        times.append(timestamp)
        cursor += 1
        unique, record = constructor(0, unique, timestamp, position[0], cursor, order,
                                     point, velocity, item_payload(item))
        records.append(record)
        order += 1
    # Containers.dropItemStack draws its location before checking EMPTY.
    drop_position(level, position[1:])
    level.bounded(40)
    unique_next = factory_after(unique)
    raw = source_raw(observed['records'][2]['common']['random'])
    timestamp = clock_from_raw(unwind(raw, 11), unique_next, begin, end)
    times.append(timestamp)
    require(times == sorted(times), 'Actual constructor-clock observations follow ordered delivery')
    cursor += 1
    point = tuple(float(x) + .5 for x in position[1:])
    unique, record = constructor(1, unique, timestamp, position[0], cursor, order,
                                 point, None, orb_payload(7))
    records.append(record)
    expected = {'level_random': source(level.raw), 'seed_uniquifier': words(unique),
        'last_id': cursor, 'next_section_order': str(order + 1), 'records': records}
    require(level.draws >= 45, 'Includes both Item splits, EmptyDrop six primitive draws and XP ticket')
    require(observed == expected, 'Exact typed entity/LEVEL/factory/ID snapshot from independent Java expectation')
    return expected, {'recovered_constructor_times_ns': times, 'monotonic_interval_ns': [begin, end],
                      'LEVEL_primitive_draws': level.draws, 'EmptyDrop_primitive_draws': 6}


def fresh_expected(view, begin, end):
    unique_level = factory_after(INITIAL_FACTORY)
    unique_sound = factory_after(unique_level)
    require(view['seed_uniquifier'] == words(unique_sound) and view['last_id'] == 0 and
            view['next_section_order'] == '0' and not view['records'],
            'Declared isolated Level-then-Sound factory boundary and entity cursor0')
    timestamp = clock_from_raw(source_raw(view['level_random']), unique_level, begin, end)
    return {'recovered_Level_constructor_time_ns': timestamp,
            'monotonic_interval_ns': [begin, end], 'factory_allocations': 2,
            'Sound_time_scope': 'Sound allocation advances the factory; its discarded RNG cannot reveal its clock input.'}


def compound(**values):
    return N.Value(10, tuple((N.text(name), value) for name, value in values.items()))


def integer(value):
    return N.Value(3, value)


def array(value):
    return N.Value(11, tuple(value))


def chars(value):
    return array(map(ord, value))


def random_value(value):
    return compound(kind=integer(value['kind']), words=array(value['words']))


def fields_value(value):
    return compound(**{key: array(raw) if isinstance(raw, list) else integer(raw)
                       for key, raw in value.items()})


def common_value(value):
    return compound(dimension=chars(value['dimension']), id=integer(value['id']),
        uuid_most=array(value['uuid_most']), uuid_least=array(value['uuid_least']),
        random=random_value(value['random']), fields=fields_value(value['fields']),
        tick_count=integer(value['tick_count']), first_tick=integer(value['first_tick']),
        removed=integer(value['removed']), accessible=integer(value['accessible']),
        section_order=chars(value['section_order']))


def record_value(value):
    payload = value['payload']
    if value['kind'] == 0:
        item = payload['item']
        stack = compound() if item is None else compound(id=chars(item['id']),
            components=chars(item['components']), count=integer(item['count']))
        data = compound(item=stack, age=integer(payload['age']),
            pickup_delay=integer(payload['pickup_delay']), health=integer(payload['health']),
            thrower=array(payload['thrower']), target=array(payload['target']), bob=integer(payload['bob']))
    else:
        data = compound(value=integer(payload['value']), age=integer(payload['age']),
            health=integer(payload['health']), count=integer(payload['count']), following=array(payload['following']))
    return compound(kind=integer(value['kind']), common=common_value(value['common']), payload=data)


def encode(view):
    return N.encode_root(N.RootTag(N.text(ROOT_NAME), compound(format=integer(1),
        level_random=random_value(view['level_random']), seed_uniquifier=array(view['seed_uniquifier']),
        last_id=integer(view['last_id']), next_section_order=chars(view['next_section_order']),
        records=N.Value(9, (10, tuple(record_value(r) for r in view['records']))))))


def members(value, names):
    require(value.kind == 10 and [k for k, v in value.payload] == [N.text(k) for k in names],
            'Exact ordered entity DTO fields: ' + ','.join(names))
    return {key: raw for key, (_, raw) in zip(names, value.payload, strict=True)}


def uint(value):
    require(value.kind == 3, 'Raw entity U32 Int')
    return value.payload


def raw_array(value, size=None):
    require(value.kind == 11 and (size is None or len(value.payload) == size), 'Raw entity IntArray words')
    return list(value.payload)


def text(value):
    return ''.join(map(chr, raw_array(value)))


def read_random(value):
    fields = members(value, ('kind', 'words'))
    kind = uint(fields['kind'])
    require(kind in (0, 1), 'Entity RNG discriminant')
    return {'kind': kind, 'words': raw_array(fields['words'], 2 if kind == 0 else 4)}


def read_fields(value):
    names = ('position', 'velocity', 'position_o', 'position_old', 'look', 'head_yaw',
             'body_yaw', 'fall_distance', 'on_ground', 'air', 'fire', 'portal_cooldown',
             'invulnerable', 'needs_sync')
    sizes = dict.fromkeys(names[:4], 6) | {'look': 4, 'fall_distance': 2}
    return {k: raw_array(v, sizes[k]) if k in sizes else uint(v) for k, v in members(value, names).items()}


def read_common(value):
    names = ('dimension', 'id', 'uuid_most', 'uuid_least', 'random', 'fields',
             'tick_count', 'first_tick', 'removed', 'accessible', 'section_order')
    v = members(value, names)
    return {'dimension': text(v['dimension']), 'id': uint(v['id']),
        'uuid_most': raw_array(v['uuid_most'], 2), 'uuid_least': raw_array(v['uuid_least'], 2),
        'random': read_random(v['random']), 'fields': read_fields(v['fields']),
        **{k: uint(v[k]) for k in ('tick_count', 'first_tick', 'removed', 'accessible')},
        'section_order': text(v['section_order'])}


def read_record(value):
    v = members(value, ('kind', 'common', 'payload'))
    kind = uint(v['kind'])
    require(kind in (0, 1), 'Typed Item/Orb discriminant')
    if kind == 0:
        p = members(v['payload'], ('item', 'age', 'pickup_delay', 'health', 'thrower', 'target', 'bob'))
        item = None
        if p['item'].payload:
            stack = members(p['item'], ('id', 'components', 'count'))
            item = {'id': text(stack['id']), 'components': text(stack['components']), 'count': uint(stack['count'])}
        else:
            members(p['item'], ())
        payload = {'item': item, **{k: uint(p[k]) for k in ('age', 'pickup_delay', 'health')},
                   'thrower': raw_array(p['thrower']), 'target': raw_array(p['target']), 'bob': uint(p['bob'])}
    else:
        p = members(v['payload'], ('value', 'age', 'health', 'count', 'following'))
        payload = {**{k: uint(p[k]) for k in ('value', 'age', 'health', 'count')}, 'following': raw_array(p['following'])}
    return {'kind': kind, 'common': read_common(v['common']), 'payload': payload}


def decode(data):
    root = N.parse(data)
    require(root.name == N.text(ROOT_NAME), 'Exact entity snapshot root')
    v = members(root.value, ('format', 'level_random', 'seed_uniquifier', 'last_id', 'next_section_order', 'records'))
    require(uint(v['format']) == 1 and v['records'].kind == 9 and v['records'].payload[0] == 10,
            'Exact entity root version and typed record list')
    view = {'level_random': read_random(v['level_random']), 'seed_uniquifier': raw_array(v['seed_uniquifier'], 2),
        'last_id': uint(v['last_id']), 'next_section_order': text(v['next_section_order']),
        'records': [read_record(row) for row in v['records'].payload[1]]}
    require(encode(view) == data, 'Every raw entity snapshot byte retained by independent DTO decoder')
    return view


def java_record(value):
    """Project independent Java observation into the complete internal DTO."""
    c = value['common']
    f = fields((0., 0., 0.), (0., 0., 0.), c['yaw'])
    for key in ('position', 'velocity', 'position_o'):
        f[key] = [word for pair in c[key] for word in pair]
    f['look'] = [c[k] for k in ('yaw', 'pitch', 'yaw_o', 'pitch_o')]
    for key in ('on_ground', 'air', 'fire', 'portal_cooldown', 'invulnerable', 'needs_sync'):
        f[key] = int(c[key])
    common = {'dimension': c['dimension'], 'id': c['id'], 'uuid_most': c['uuid_most'],
        'uuid_least': c['uuid_least'], 'random': source(number(c['random']['seed'])), 'fields': f,
        **{k: int(c[k]) for k in ('tick_count', 'first_tick', 'removed', 'accessible')},
        'section_order': str(c['section_order'])}
    if value['kind'] == 'item':
        item = {'id': value['item']['id'], 'components': '', 'count': value['item']['count']}
        payload = {**item_payload(item), 'bob': value['bob']}
        kind = 0
    else:
        payload, kind = orb_payload(value['value']), 1
    return {'kind': kind, 'common': common, 'payload': payload}


def verify_retained_java(path: Path):
    ref = json.loads(path.read_bytes())
    require(ref['pin'] == '26.3', 'Pinned constructor/reference receivers')
    cases = {row['id']: row for row in ref['observations']['cases']}
    empty = cases['legacy-empty']
    level = Legacy(number(empty['level_before']['seed']))
    drop_position(level, (-7, 65, 3))
    require(words(level.raw) == empty['level_after']['seed'] and not empty['records'] and level.draws == 6,
            'Retained actual Java EmptyDrop commits three LEVEL doubles')
    single = cases['legacy-single']
    level = Legacy(number(single['level_before']['seed']))
    point = drop_position(level, (-7, 65, 3))
    level.bounded(21)
    velocity = drop_velocity(level)
    unique, item = constructor(0, number(single['unique_before']), number(single['times'][0]),
        'minecraft:overworld', 1, 0, point, velocity,
        item_payload({'id': 'minecraft:stone', 'components': '', 'count': 1}))
    require(item == java_record(single['records'][0]) and words(unique) == single['unique_after'] and
            words(level.raw) == single['level_after']['seed'], 'Retained actual Java complete Item constructor and LEVEL draws')
    orb_case = cases['legacy-denominations']
    unique, orb = constructor(1, number(orb_case['unique_before']), number(orb_case['times'][0]),
        'minecraft:overworld', 1, 0, (-6.5, 65.5, 3.5), None, orb_payload(1))
    require(orb == java_record(orb_case['records'][0]), 'Retained actual Java complete first Orb constructor')
    return {'status': 'PASS_FILE_ONLY', 'cases': ['legacy-empty', 'legacy-single', 'legacy-denominations:first-orb'],
            'scope': 'Independent test arithmetic/constructor expectations checked against retained pinned Java receivers; no new Java/Bend/native execution.'}
