#!/usr/bin/env python3
"""Actor004 real TCP/MCP, crafting publication and durable recovery boundaries.

Builds belong to test_playable_client_actor004.py. This runner consumes only its
successful current artifact, using the existing socket and process owners.
Python constructs independent fixtures/expected bytes; gameplay stays in Bend.
"""
from __future__ import annotations

import argparse
import copy
import csv
import dataclasses
import json
import socket
import struct
import sys
import time
import zipfile
from pathlib import Path

import test_playable_client_actor004 as A
import test_player_inventory as Inventory
import test_world_generation_settings as Generation
import item_component_check as Components

P, R, S, H = A.P, A.R, A.S, A.H
ROOT = A.ROOT
JAR = Path.home() / 'Library/Application Support/minecraft/versions/26.3/26.3.jar'
FACTS = ROOT / 'generated/reference_crafting_authority_metadata.json'
TABLE = ROOT / 'generated/reference_item_metadata.tsv'
REFERENCE = ROOT / 'reference/player_crafting_authority.json'
SWAP_REFERENCE = ROOT / 'reference/player_inventory_click.json'
COMPONENT_REFERENCE = ROOT / 'reference/item_component.json'
FULL_FIXTURE = ROOT / 'build/player-inventory-screen/full-codec-fixtures/full-status-equipment.nbt'
KEY_SHA = 'aceb743fcbd88fbd6fa24e87b392446f74b87a7bf70c3c6d6b0b954107b0de1c'
FACTS_SHA = '9105c1fa3a9eefbab94d21626e1d5be1ad69c9765e19b608e257e458b9e853d1'
SWAP_SHA = '87542aa31acc94f3ff563b7810e69e205e9c660b47c22a1a4543b38cca53466b'
OVERFLOW = 'inventory:prospective-reply-refused'


def stack(identifier, count, components=''):
    return {'id': identifier, 'components': components, 'count': count}


def component_key():
    reference = json.loads(COMPONENT_REFERENCE.read_bytes())
    base = reference['default_components']
    effective = copy.deepcopy(base)
    effective[Components.EFFECTS] = [{'id': 'minecraft:speed'}] * 1200
    key = Components.identity(effective, base)
    S.require(S.sha(key.encode()) == KEY_SHA and len(key) == 30680,
              'Pinned 1200-effect canonical key changed')
    return key


def runtime_pins():
    return {str(path): R.pin(path) for path in
            (JAR, FACTS, TABLE, S.P.OFFICIAL, S.TABLE, REFERENCE,
             SWAP_REFERENCE, COMPONENT_REFERENCE, FULL_FIXTURE)}


def requirements():
    """Read only actual data/references; no Bend/Java/native process."""
    pins = runtime_pins()
    S.require(pins[str(FACTS)]['sha256'] == FACTS_SHA, 'Crafting startup facts changed')
    S.require(pins[str(SWAP_REFERENCE)]['sha256'] == SWAP_SHA, 'Swap Java reference changed')
    facts = json.loads(FACTS.read_bytes())
    S.require(len(facts['ordered_recipe_ids']) == 2042, 'Original recipe order cardinality')
    with zipfile.ZipFile(JAR) as jar:
        recipes = {name: json.loads(jar.read('data/minecraft/recipe/' + name + '.json'))
                   for name in ('stick', 'sugar_from_honey_bottle', 'oak_button')}
    S.require(recipes['stick']['result'] == {'id': 'minecraft:stick', 'count': 4}
              and recipes['sugar_from_honey_bottle']['result'] ==
              {'id': 'minecraft:sugar', 'count': 3}
              and recipes['oak_button']['result']['id'] == 'minecraft:oak_button',
              'Actual original-JAR recipe outcomes changed')
    rows = json.loads(REFERENCE.read_bytes())['observations']
    S.require(any(row['id'] == 'stick-button0-empty' for row in rows)
              and any(row['id'] == 'honey-2-empty:CREATIVE' for row in rows),
              'Independent Java take/remainder observations missing')
    key = component_key()
    jar_reference = json.loads(REFERENCE.read_bytes())['provenance']['client']
    S.require(pins[str(JAR)]['sha256'] == jar_reference['sha256'], 'Actual pinned Java JAR differs')
    request = [1, 1, 'fixture:epoch', 1,
               [7, 2, ['minecraft:suspicious_stew', key], 1]]
    request_bytes = len(json.dumps(request, ensure_ascii=True, separators=(',', ':')).encode())
    S.require(16384 < request_bytes <= 65536, 'Meaningful large actual request boundary')
    _, full = Inventory.parse_inventory_full(FULL_FIXTURE.read_bytes())
    full['main']['slots'] = [None] * 36
    full['main']['slots'][2] = stack('minecraft:suspicious_stew', 1, key)
    menu = empty_menu()
    reply_bytes = lambda: len(json.dumps([1, 6, 'fixture:epoch', 1, True, '', authority(full, menu)],
                                        ensure_ascii=True, separators=(',', ':')).encode())
    one = reply_bytes()
    physical = payload(A.playable_spawn(), full, key)
    S.N.Reader(physical, max_bytes=65536, max_depth=8, max_elements=16384).root()
    full['main']['slots'][3] = stack('minecraft:suspicious_stew', 1, key)
    two = reply_bytes()
    S.require(one <= 65536 < two and len(physical) <= 65536,
              'Actual aggregate refusal fixture does not cross physical reply boundary')
    return {'status': 'prepared; native behavior pending', 'runtime_inputs': pins,
        'entry': 'remote_resource_server.bend; current successful A.WORK artifact only',
        'native_argv': ['ACTOR', '--gpu', 'off', '--threads', '2', '--', '--paused',
                        '--game-mode', 'creative', '--stdin-control', '--sine', str(S.TABLE)],
        'cwd': str(ROOT), 'missing_save': 'create', 'original_recipes': 2042,
        'recipes': recipes, 'component_key_sha256': KEY_SHA,
        'component_key_chars': len(key), 'large_request_bytes': request_bytes,
        'complete_one_stack_reply_bytes': one, 'complete_two_stack_reply_bytes': two,
        'one_stack_typed_NBT_bytes': len(physical),
        'cases': ['fresh complete v3 demand world and scheduled control/release',
            'actual TCP and MCP permissions, non-owner and stale lease admission',
            'Java-backed accepted Swap with all other authority retained',
            'original-JAR stick output take, honey output and glass-bottle remainder',
            '1200-effect aggregate MenuReply refusal and direct cached result take',
            'generic FrameCatalog including glass/slab/stairs and all air cells',
            'complete typed v3/Core/Local/status/equipment/WG save acknowledgement',
            'actual SIGKILL after unsaved mutation and exact cold restoration'],
        'unexposed': ['opaque crafting catalog/cache representation',
            'hidden backing cells48..63', 'private lease remaining pulse counter',
            'Receiver transient fields'],
        'scope': 'Real actor and transport boundaries with synthetic private input. Whole-owner native/proof fixtures cover unexposed state. This is not OS input, rendering, positionRandom/light parity or general motion parity.'}


class Private(A.PlayablePrivate):
    """Existing correlated client, widened to the production ASCII budget."""
    def __init__(self, backend):
        ordinal = getattr(backend, 'private_ordinal', 0)
        backend.private_ordinal = ordinal + 1
        label = 'private-' + str(ordinal).zfill(3)
        journal = backend.directory / label
        journal.mkdir(exist_ok=False)
        with H.bindings(backend, {'directory': journal}):
            super().__init__(backend)

    def exchange(self, request):
        S.require(time.monotonic() < self.backend.deadline, 'Actor lifetime cap')
        data = json.dumps(request, ensure_ascii=True, separators=(',', ':')).encode('ascii') + b'\n'
        S.require(len(data) - 1 <= 65536, 'Production private request ASCII budget')
        self.requests.write(data); self.requests.flush(); self.socket.sendall(data)
        deadline = min(time.monotonic() + 5, self.backend.deadline)
        while b'\n' not in self.buffer:
            remaining = deadline - time.monotonic()
            S.require(remaining > 0, 'Private response timeout')
            self.socket.settimeout(remaining)
            chunk = self.socket.recv(8192)
            self.responses.write(chunk); self.responses.flush()
            S.require(chunk, 'Private EOF before response')
            self.buffer += chunk
            S.require(len(self.buffer) <= 65537, 'Private physical reply frame bound')
        line, self.buffer = self.buffer.split(b'\n', 1)
        S.require(not self.buffer and len(line) <= 65536 and all(byte < 128 for byte in line),
                  'Private ASCII frame/tail')
        reply = json.loads(line)
        if request[:2] == [1, 0] and reply == [1, 3, '', 0, 'RendererLeaseBusy']:
            self.close()
            raise R.LeaseBusy('RendererLeaseBusy')
        return reply


def connect(actor):
    # Reuse the existing bounded observation of asynchronous disconnect/Busy.
    with H.bindings(R, {'Private': Private}):
        return R.acquire(actor)


def slot(value):
    return [0] if value is None else [1, value['id'], value['components'], value['count']]


def authority(full, menu):
    main = full['main']
    return [[main['selected'], main['abilities']['instabuild'], main['abilities']['maybuild'],
             list(map(slot, main['slots']))], list(map(slot, full['equipment'])),
            [full['status'][name] for name in Inventory.STATUS_FIELDS],
            list(map(slot, menu['craft'])), slot(menu['carried']),
            [0] if menu['result'] is None else [1, slot(menu['result'])],
            menu['opened'], menu['revision']]


def empty_menu():
    return {'craft': [None] * 4, 'carried': None, 'result': None,
            'opened': False, 'revision': 0}


def item_tag(value, key):
    if value is None:
        return S.WC.compound([])
    fields = [('id', S.WC.txt(value['id'])), ('count', S.WC.integer(value['count']))]
    if value['components']:
        S.require(value['id'] == 'minecraft:suspicious_stew' and value['components'] == key
                  and value['count'] == 1, 'Unexpected typed fixture component')
        effects = tuple(S.WC.compound([('id', S.WC.txt('minecraft:speed')),
                                      ('duration', S.WC.integer(160))]) for _ in range(1200))
        fields.append(('components', S.WC.compound([
            (Components.EFFECTS, S.N.Value(9, (10, effects)))])))
    return S.WC.compound(fields)


def payload(record, full, key):
    root = Inventory.inventory_full_root(S.local_bytes(record), full['main'],
        full['equipment'], full['status'], full['generation'])
    fields = [(name, S.N.Value(9, (10, tuple(item_tag(item, key) for item in
                    (full['main']['slots'] if name == S.N.text('slots') else full['equipment']))))
               if name in (S.N.text('slots'), S.N.text('equipment')) else value)
              for name, value in root.value.payload]
    return S.N.encode_root(S.N.RootTag(root.name, S.N.Value(10, tuple(fields))))


def bundle(world, highwater, record, full, key):
    root = S.bundle_root(world, highwater, record)
    extension = S.WC.compound([('namespace', S.WC.txt(S.NAMESPACE)),
        ('schema', S.WC.integer(1)), ('payload', S.N.Value(7, payload(record, full, key)))])
    return S.N.encode_root(S.N.RootTag(root.name, S.N.Value(10, tuple(
        (name, extension if name == S.N.text('extension') else value)
        for name, value in root.value.payload))))


def terrain(count, identity, palette, *, fresh=False):
    world = S.WC.empty_world(count, identity)
    air = (palette['minecraft:air'],) * 4096
    ground = tuple(palette['minecraft:' + name] for name in ('stone', 'dirt', 'dirt', 'stone')
                   for _ in range(256)) + air[:3072]
    world['sections'] = [{'key': S.BASE.section_key(x, y, z),
                          'cells': ground if y == -64 else air}
                        for x in (-16, 0) for y in range(-80, 336, 16) for z in (-16, 0)]
    world['sections'].sort(key=lambda section: section['key'])
    world['revision'] = 1 if fresh else 7
    world['events'] = [{'stamp': (0, 0, 0) if fresh else (3, 9, 4),
                       'kind': 0, 'revision': world['revision']}]
    if not fresh:
        world.update(tick=7, day_time=99, daylight=False)
        for point, name in [((-1, -60, 0), 'minecraft:glass'),
                            ((1, -60, 0), 'minecraft:oak_slab'),
                            ((2, -60, 0), 'minecraft:oak_stairs')]:
            S.BASE.set_block(world, *point, palette[name])
    S.require(len(world['sections']) == 104 and world['paused'], 'Complete paused demand fixture')
    S.P.canonical_expected(world)
    return world


def palette_and_registry():
    identity, count, _ = S.P.registry_identity(S.P.OFFICIAL)
    with S.P.OFFICIAL.open(newline='') as source:
        palette = {row['identifier']: int(row['default_state_id'])
                   for row in csv.DictReader(source, delimiter='\t')}
    return palette, identity, count


def generic_frame(control, world, record):
    frame = control.call([13, 128, 128], 7)[4]
    S.require(len(frame) == 6, 'Generic FrameCatalog field count')
    registry, tick, revision, origin, camera, cells = frame
    words, _ = S.PC.parse_snapshot(S.PR.decode(record.motion)[0])
    position = tuple(struct.unpack('>d', struct.pack('>Q', raw))[0]
                     for raw in S.PC.bits64(words[:6]))
    eye = (position[0], position[1] + S.PC.f32(record.eye), position[2])
    S.require((registry, tick, revision) == (world['registry'], world['tick'], world['revision'])
              and origin == list(S.PC.words64(tuple(map(S.PC.raw64, eye))))
              and camera == [0, 0, 0, *words[39:41]],
              'Generic actual registry/clock/pose-aware eye/camera')
    sections = {section['key']: section['cells'] for section in world['sections']}
    def cell(x, y, z):
        return sections[S.BASE.section_key(x, y, z)][
            (x & 15) + ((z & 15) << 4) + ((y & 15) << 8)]
    def mixed(seed, index):
        return ((seed ^ (((index + 1) & 0xffffffff) * 2246822519 & 0xffffffff))
                * 3266489917) & 0xffffffff
    # Literal production default is8^3, floorBody-4. It is not a general region
    # cardinality assumption, nor Java's positionRandom or lighting algorithm.
    low = tuple(int(value // 1) - 4 for value in position)
    expected = []
    for z in range(low[2], low[2] + 8):
        for y in range(low[1], low[1] + 8):
            for x in range(low[0], low[0] + 8):
                raw = tuple(map(S.unsigned, (x, y, z)))
                boundary = sum(value in (base, base + 7) for value, base in zip((x, y, z), low))
                seed = mixed(mixed(mixed(0, raw[0]), raw[1]), raw[2])
                expected.append([*raw, boundary, cell(x, y, z), seed,
                                 [[], 4294967295, 0, 0, False, 128]])
    S.require(cells == expected and len(cells) == 512,
              'All generic arbitrary-state/air cells, order/boundaries/seed/policy')
    return {'sample_sha256': S.sha(S.canonical(frame)), 'cells': len(cells),
            'state_ids': sorted({value[4] for value in cells}),
            'tick': tick, 'revision': revision}


def saved(client, path, world, highwater, record, full, key, directory, label):
    reply = client.call('world.save', {})
    actual = path.read_bytes()
    expected = bundle(world, highwater, record, full, key)
    receipt = {'label': label, 'reply': reply, 'bytes': len(actual),
               'actual_sha256': S.sha(actual), 'expected_sha256': S.sha(expected)}
    S.exclusive_json(directory / (label + '.json'), receipt)
    S.require(reply == {'status': 'durable', 'published': True, 'durable': True,
        'bytes': len(expected), 'peer_highwater': highwater} and actual == expected,
        'Complete typed v3/Core/Local/status/equipment/WG durable bytes: ' + label)
    outer = S.N.Reader(actual, max_bytes=16846848, max_depth=8,
                       max_elements=16846848).root()
    fields = S.WC.fields(outer.value, S.BUNDLE_FIELDS)
    identity, count, _ = S.P.registry_identity(S.P.OFFICIAL)
    core = S.WC.validate(S.N.parse(fields['core'].payload), count, identity)
    extra = S.WC.fields(fields['extension'], S.EXTENSION_FIELDS)
    nested = S.N.Reader(bytes(extra['payload'].payload), max_bytes=65536,
                        max_depth=8, max_elements=16384).root()
    physical = S.WC.fields(nested.value, Inventory.FULL_FIELDS)
    S.require(S.P.canonical_expected(core) == S.P.canonical_expected(world)
              and bytes(physical['record'].payload) == S.local_bytes(record)
              and bytes(physical['generation'].payload) == full['generation'],
              'Independent full Core/Local/WG physical projection: ' + label)
    return actual, receipt


def admitted_menu(control, full, menu, checks, command, label, *, accepted=True, message=''):
    sequence = control.sequence
    reply = control.call(command, 6)
    S.require(reply[4:] == [accepted, message, authority(full, menu)],
              'Complete correlated MenuReply: ' + label + ': ' + str(reply[4:6]))
    checks.append({'label': label, 'sequence': sequence, 'accepted': accepted,
                   'authority_sha256': S.sha(S.canonical(reply[6]))})


def peer_fault(actor, request, expected, directory, label):
    with socket.create_connection(('127.0.0.1', actor.private_port), timeout=5) as peer:
        data = json.dumps(request, ensure_ascii=True, separators=(',', ':')).encode() + b'\n'
        peer.sendall(data)
        stream = peer.makefile('rb')
        line = stream.readline(65538)
        reply = json.loads(line)
        S.exclusive_json(directory / (label + '.json'), {'request': request, 'reply': reply})
        S.require(reply == expected and stream.read(1) == b'', 'Private non-owner fault: ' + label)
        stream.close()


def fresh_spawn():
    # Explicit generated-settings spawn starts ungrounded until actual travel.
    # Legacy fixed-profile spawn and loaded fixture expectations stay unchanged.
    record = A.playable_spawn()
    motion, look = S.PR.decode(record.motion)
    words, dimension = S.PC.parse_snapshot(motion)
    words = list(words)
    words[26] = 0
    return S.validate_local(dataclasses.replace(record, motion=S.N.encode_root(S.PR.root(
        S.N.encode_root(S.PC.snapshot_root(tuple(words), dimension)), S.PR.look_words(look)))))


def scenario(directory, binary, bridge, *, component_stress=True):
    directory.mkdir(exist_ok=False)
    key = component_key()
    palette, identity, count = palette_and_registry()
    checks, saves, frames = [], [], []
    fresh = terrain(count, identity, palette, fresh=True)
    record = fresh_spawn()
    full = {'main': P.playable_inventory(), 'equipment': [None] * 7,
            'status': dict(zip(Inventory.STATUS_FIELDS,
                (True, True, False, 1036831949, 1028443341), strict=True)),
            'generation': Generation.stone_dirt_bytes()}
    menu = empty_menu()
    fresh_path = directory / 'fresh.nbt'
    actor = A.PlayableBackend(directory / 'fresh-create', binary, fresh_path, bridge, create=True)
    try:
        raw, ping = actor.tcp(True)
        developer, dping = actor.mcp()
        observer, oping = actor.mcp(False)
        highwater = max(ping['peer'], dping['peer'], oping['peer'])
        S.require(ping['peer'] == 2 and not fresh_path.exists(), 'Fresh reserved player/public IDs')
        control = connect(actor)
        admitted_menu(control, full, menu, checks, [8], 'fresh-complete-defaults')
        S.inspect(raw, record)
        observer.call('world.save', {}, fault='PermissionDenied')
        observer.call('inventory.select', {'slot': 0}, fault='PermissionDenied')
        # Release and press are in one actual owned command. The later key is
        # not discarded by the release path. Public steps are scheduled ticks,
        # not evidence of unpaused realtime pulses or general numerical parity.
        control.call([1, [True, True, [[0], [1, True, [0, 119, True]]]]])
        raw.call('simulation.step', {'ticks': 1})
        S.BASE.apply_tick(fresh)
        observed = S.decode_local(bytes(raw.call('player.inspect', {})['nbt_bytes']))
        S.require(observed.keys == (1, 0, 0, 0, 0, 0, 0) and observed.count == 1,
                  'Atomic Release preserves following W key and joined scheduled tick')
        control.call([2])
        admitted_menu(control, full, menu, checks, [8], 'release-retains-lease-authority')
        raw.call('simulation.step', {'ticks': 1})
        S.BASE.apply_tick(fresh)
        record = S.decode_local(bytes(raw.call('player.inspect', {})['nbt_bytes']))
        S.require(record.keys == (0,) * 7 and record.floats[:2] == (0, 0) and record.count == 2,
                  'Released controller consumed by actual next scheduled receiver tick')
        _, receipt = saved(developer, fresh_path, fresh, highwater, record, full, key,
                           directory, 'fresh-acknowledged-save')
        saves.append(receipt)
    except BaseException:
        actor.stop(failed=True); raise
    finally:
        actor.stop()

    record = dataclasses.replace(A.playable_spawn(), count=7, invulnerable=9)
    fixture = FULL_FIXTURE
    _, full = Inventory.parse_inventory_full(fixture.read_bytes())
    full['main']['slots'] = [None] * 36
    full['main']['selected'] = 7
    full['main']['slots'][0] = stack('minecraft:dirt', 4)
    full['main']['slots'][10] = stack('minecraft:stone', 17)
    full['main']['slots'][35] = stack('minecraft:oak_planks', 6)
    full['generation'] = Generation.stone_dirt_bytes(seed=0xffffffffffffffff)
    world = terrain(count, identity, palette)
    path = directory / 'current.nbt'
    initial = bundle(world, 40, record, full, key)
    path.write_bytes(initial)
    S.exclusive_json(directory / 'fixture.json', {'bundle': R.pin(path), 'fixture': R.pin(fixture),
        'raw_status': full['status'], 'generation_sha256': S.sha(full['generation']),
        'sections': 104, 'arbitrary_states': {name: palette[name] for name in
        ('minecraft:glass', 'minecraft:oak_slab', 'minecraft:oak_stairs')}})
    menu = empty_menu()
    actor = A.PlayableBackend(directory / 'loaded-authority', binary, path, bridge)
    try:
        raw, ping = actor.tcp(True)
        developer, dping = actor.mcp()
        observer, oping = actor.mcp(False)
        highwater = max(ping['peer'], dping['peer'], oping['peer'])
        S.require(ping['peer'] == 42, 'Saved40 reserved player41/public42')
        control = connect(actor)
        S.inspect(raw, record)
        admitted_menu(control, full, menu, checks, [8], 'loaded-43-and-raw-status')
        frames.append(generic_frame(control, world, record))
        observer.call('inventory.acquire', {'slot': 1, 'item': 'minecraft:dirt', 'count': 1},
                      fault='PermissionDenied')
        observer.call('inventory.transfer', {'source': 0, 'destination': 1, 'count': 1, 'mode': 'split'},
                      fault='PermissionDenied')
        peer_fault(actor, [1, 0, 'wrong-verification-capability'],
            [1, 3, '', 0, 'RendererAuthenticationFailed'], directory, 'bad-capability')
        peer_fault(actor, [1, 0, actor.token], [1, 3, '', 0, 'RendererLeaseBusy'],
                   directory, 'second-owner')
        peer_fault(actor, [1, 1, control.epoch, control.sequence, [8]],
            [1, 3, control.epoch, control.sequence, 'Wire:SocketEpoch'], directory, 'unassigned-socket')
        admitted_menu(control, full, menu, checks, [8], 'owner-after-foreign-disconnects')
        bad_sequence = control.sequence + 1
        stale = control.exchange([1, 1, control.epoch, bad_sequence, [8]])
        S.require(stale == [1, 3, control.epoch, bad_sequence, 'RendererLeaseOrSequence'],
                  'Stale owner sequence refusal')
        control.close()
        control = connect(actor)
        admitted_menu(control, full, menu, checks, [8], 'reconnected-exact-authority')
        menu['opened'] = True
        admitted_menu(control, full, menu, checks, [9], 'open-actual-recipe-service')
        full['main']['slots'][0], full['main']['slots'][10] = full['main']['slots'][10], full['main']['slots'][0]
        menu['revision'] = 1
        admitted_menu(control, full, menu, checks, [11, 10, [2, 0]], 'accepted-Java-backed-Swap')
        # Literal original-JAR stick fixture; the one-plank intermediate also
        # matches the original oak_button recipe, so derived output is checked.
        for target in (1, 3):
            full['main']['slots'][8] = stack('minecraft:oak_planks', 2)
            admitted_menu(control, full, menu, checks, [7, 8, ['minecraft:oak_planks', ''], 2],
                          'acquire-planks-for-grid' + str(target))
            menu['carried'], full['main']['slots'][8] = full['main']['slots'][8], None
            menu['revision'] += 1
            admitted_menu(control, full, menu, checks, [11, 44, [0, 0]], 'pickup-grid-source' + str(target))
            menu['craft'][target - 1], menu['carried'] = menu['carried'], None
            menu['revision'] += 1
            menu['result'] = stack('minecraft:oak_button', 1) if target == 1 else stack('minecraft:stick', 4)
            admitted_menu(control, full, menu, checks, [11, target, [0, 0]], 'place-grid' + str(target))
        if component_stress:
            full['main']['slots'][2] = stack('minecraft:suspicious_stew', 1, key)
            admitted_menu(control, full, menu, checks, [7, 2, ['minecraft:suspicious_stew', key], 1],
                          'admit-one-1200-effect-stack')
            admitted_menu(control, full, menu, checks, [7, 3, ['minecraft:suspicious_stew', key], 1],
                          'aggregate-reply-rollback', accepted=False, message=OVERFLOW)
        # The full profile witnesses the retained recipe plan directly after
        # rollback. The small profile takes the same actual original-JAR result
        # without claiming the separately blocked large transport boundary.
        for number in (1, 2):
            menu['craft'][0] = menu['craft'][2] = stack('minecraft:oak_planks', 1) if number == 1 else None
            menu['carried'] = stack('minecraft:stick', number * 4)
            menu['result'] = stack('minecraft:stick', 4) if number == 1 else None
            menu['revision'] += 1
            label = 'cached-result-take-after-rollback' if component_stress else 'original-JAR-result-take'
            admitted_menu(control, full, menu, checks, [11, 0, [0, 0]], label + str(number))
        raw.call('world.save', {}, fault='SaveEncodingFailed')
        S.require(path.read_bytes() == initial, 'Temporary crafting saved prematurely')
        full['main']['slots'][1] = stack('minecraft:stick', 8)
        menu.update(carried=None, craft=[None] * 4, result=None, opened=False,
                    revision=menu['revision'] + 1)
        admitted_menu(control, full, menu, checks, [10], 'close-returns-crafted-sticks')
        menu['opened'] = True
        admitted_menu(control, full, menu, checks, [9], 'open-honey-remainder-fixture')
        full['main']['slots'][8] = stack('minecraft:honey_bottle', 2)
        admitted_menu(control, full, menu, checks, [7, 8, ['minecraft:honey_bottle', ''], 2], 'acquire-honey2')
        menu['carried'], full['main']['slots'][8] = full['main']['slots'][8], None
        menu['revision'] += 1
        admitted_menu(control, full, menu, checks, [11, 44, [0, 0]], 'pickup-honey2')
        menu['craft'][0], menu['carried'] = menu['carried'], None
        menu.update(result=stack('minecraft:sugar', 3), revision=menu['revision'] + 1)
        admitted_menu(control, full, menu, checks, [11, 1, [0, 0]], 'place-original-JAR-honey-recipe')
        # Small profile leaves main2 empty; the full profile has the stew there.
        bottle_slot = 3 if component_stress else 2
        full['main']['slots'][bottle_slot] = stack('minecraft:glass_bottle', 1)
        menu.update(craft=[stack('minecraft:honey_bottle', 1), None, None, None],
                    carried=stack('minecraft:sugar', 3), revision=menu['revision'] + 1)
        admitted_menu(control, full, menu, checks, [11, 0, [0, 0]], 'honey-take-output-and-inventory-remainder')
        menu.update(craft=[stack('minecraft:glass_bottle', 1), None, None, None],
                    carried=stack('minecraft:sugar', 6), result=None, revision=menu['revision'] + 1)
        admitted_menu(control, full, menu, checks, [11, 0, [0, 0]], 'honey-take-output-and-grid-remainder')
        full['main']['slots'][bottle_slot] = stack('minecraft:glass_bottle', 2)
        full['main']['slots'][bottle_slot + 1] = stack('minecraft:sugar', 6)
        menu.update(craft=[None] * 4, carried=None, result=None, opened=False,
                    revision=menu['revision'] + 1)
        admitted_menu(control, full, menu, checks, [10], 'close-returns-remainders-and-output')
        full['main']['slots'][5] = stack('minecraft:dirt', 1)
        admitted_menu(control, full, menu, checks, [7, 5, ['minecraft:dirt', ''], 1], 'acquire-placement-dirt')
        full['main']['selected'] = 5
        admitted_menu(control, full, menu, checks, [12, 5], 'select-placement-dirt')
        control.aim_down(); record = A.playable_look(record, 90.0)
        S.inspect(raw, record)
        for button, material in ((0, 'minecraft:air'), (1, 'minecraft:dirt')):
            sequence = control.sequence
            S.require(control.call([3, button], 5)[4:] == [True, ''], 'Actual player break/place')
            S.BASE.set_block(world, 0, -61, 0, palette[material]); world['revision'] += 1
            world['events'].insert(0, {'stamp': (world['tick'], 41, sequence),
                                     'kind': 0, 'revision': world['revision']})
        frames.append(generic_frame(control, world, record))
        control.call([2])
        admitted_menu(control, full, menu, checks, [8], 'release-before-durable-save')
        acknowledged, receipt = saved(developer, path, world, highwater, record, full, key,
                                      directory, 'complete-typed-acknowledged-save')
        saves.append(receipt)
        full['main']['slots'][6] = stack('minecraft:oak_planks', 1)
        admitted_menu(control, full, menu, checks, [7, 6, ['minecraft:oak_planks', ''], 1], 'unsaved-before-SIGKILL')
        S.require(path.read_bytes() == acknowledged, 'Unacknowledged mutation changed disk')
        full['main']['slots'][6] = None
    except BaseException:
        actor.stop(failed=True); raise
    finally:
        actor.stop(kill=not actor.stopped)

    actor = A.PlayableBackend(directory / 'cold-reload', binary, path, bridge)
    try:
        raw, ping = actor.tcp(True)
        S.require(ping['peer'] == highwater + 2, 'Cold reserved player/public identity')
        control = connect(actor)
        menu = empty_menu()
        admitted_menu(control, full, menu, checks, [8], 'cold-exact-typed43-raw-status')
        S.inspect(raw, record)
        S.require(path.read_bytes() == acknowledged and raw.call('world.clock') == S.P.clock(world),
                  'SIGKILL restores last complete acknowledged Core/player snapshot')
        frames.append(generic_frame(control, world, record))
        _, receipt = saved(raw, path, world, ping['peer'], record, full, key,
                           directory, 'cold-reloaded-acknowledged-save')
        saves.append(receipt)
    except BaseException:
        actor.stop(failed=True); raise
    finally:
        actor.stop()
    result = {'status': 'PASS', 'generation': 'actor004/' + A.WORK.name,
        'backends': 3, 'TCP_MCP': True, 'scheduled_control_release': True,
        'private_menu_checks': checks, 'original_JAR_crafting': True,
        'profile': 'full' if component_stress else 'small-inventory-crafting-control-save',
        'prospective_reply_refusal': {'effects': 1200, 'key_sha256': KEY_SHA,
            'message': OVERFLOW, 'next_sequence_same_epoch': True,
            'direct_cache_witness': 'two result takes without intervening inspect/refresh'} if component_stress else
            {'status': 'not run; separately retained 35,620-byte private framing refusal'},
        'accepted_Swap': True, 'generic_frames': frames, 'player_break_place': True,
        'complete_saved_comparisons': saves, 'actual_SIGKILL_cold_reload': True,
        'main_slots': 36, 'equipment_slots': 7, 'raw_status': full['status'],
        'world_sections': 104, 'world_cells': 104 * 4096,
        'generation_sha256': S.sha(full['generation']),
        'scope': requirements()['scope'], 'unexposed': requirements()['unexposed']}
    S.exclusive_json(directory / 'summary.json', result)
    return result


def artifact():
    build = json.loads((A.WORK / 'native-build.json').read_bytes())
    S.require(build['status'] == 'PASS' and build['binary'] == R.pin(A.ACTOR)
              and build['source_map'] == R.pin(A.SOURCE / 'source-map.json')
              and build['runtime_inputs'] == R.pin(A.WORK / 'runtime-inputs.json'),
              'Actual current actor producer/binary/source identity differs')
    S.require(R.pin(A.ACTOR)['sha256'] != R.pin(A.OLD / 'actor')['sha256'], 'Old actor reused')
    mapping = json.loads((A.SOURCE / 'source-map.json').read_bytes())
    for row in mapping['files']:
        if row['path'] in ('generated/reference_item_metadata.tsv', 'generated/reference_mth_sin.f32'):
            S.require(R.pin(ROOT / row['path'])['sha256'] == row['original_sha256'],
                      'Actual runtime data differs from compiled mapped generation: ' + row['path'])
    for row in json.loads((A.WORK / 'runtime-inputs.json').read_bytes())['files']:
        S.require(R.pin(row['original']['path']) == row['original'], 'Actual startup facts drift')
    return build


def child(directory, *, component_stress=True):
    build = artifact()
    before = runtime_pins()
    journal = directory / 'owned-groups.jsonl'
    journal.touch(exist_ok=False)
    bridge, _ = P.retained_bridge()
    def identity():
        S.require(R.pin(A.ACTOR) == build['binary'], 'Actor changed during boundary run')
    with H.bindings(S, {'SERVER': A.ACTOR, 'ROOT': ROOT, 'activation': identity,
                        'OWNED_GROUPS': journal}):
        try:
            result = scenario(directory / 'actors', A.ACTOR, bridge, component_stress=component_stress)
            S.require(runtime_pins() == before, 'Actual JAR/table/facts/reference changed')
            identity()
        except BaseException as error:
            S.exclusive_json(directory / 'first-failure.json',
                             {'type': type(error).__name__, 'message': str(error)})
            raise
    print(json.dumps({'status': result['status'], 'backends': result['backends'],
                      'menu_checks': len(result['private_menu_checks'])}), flush=True)


def descendant_cleanup(directory, bridge):
    """Adapt the existing owned journal to the existing cleanup operation."""
    source = directory / 'owned-groups.jsonl'
    target = directory / 'cleanup-groups.jsonl'
    rows = []
    if source.exists():
        for line in source.read_bytes().splitlines():
            row = json.loads(line)
            executable = str(bridge if row['label'] == 'MCP' else A.ACTOR)
            rows.append({'pid': row['pid'], 'label': row['label'], 'argv': [executable]})
    with target.open('xb') as stream:
        for row in rows:
            stream.write(S.canonical(row) + b'\n')
    with H.bindings(R, {'GROUPS': target}):
        observed = R.registered_cleanup()
    S.exclusive_json(directory / 'cleanup.json', observed)
    S.require(all(not row['errors'] and not R.live(row['after']) for row in observed),
              'Actor/MCP descendant cleanup not verified')


def native(*, component_stress=True):
    build = artifact()
    prefix = 'boundary-' if component_stress else 'boundary-small-'
    number = 1
    while (A.WORK / (prefix + str(number).zfill(3))).exists():
        number += 1
    directory = A.WORK / (prefix + str(number).zfill(3))
    directory.mkdir(exist_ok=False)
    before = runtime_pins()
    own_pin = R.pin(Path(__file__))
    S.exclusive_json(directory / 'inputs.json', {'binary': build['binary'],
        'build': R.pin(A.WORK / 'native-build.json'), 'source_map': build['source_map'],
        'runtime': before, 'runner': own_pin})
    bridge, _ = P.retained_bridge()
    with H.bindings(R, {'WORK': directory}):
        try:
            argv = [sys.executable, str(Path(__file__)), '--_child', str(directory)]
            if not component_stress:
                argv.append('--_small')
            process = R.bounded(argv, 180, 'execution')
        finally:
            descendant_cleanup(directory, bridge)
    R.process_ok(process)
    S.require(runtime_pins() == before and R.pin(Path(__file__)) == own_pin,
              'Native input or runner changed')
    summary = json.loads((directory / 'actors/summary.json').read_bytes())
    output = ROOT / ('evidence/playable-client-actor004-' + prefix + str(number).zfill(3) + '.json')
    R.write(output, {'status': summary['status'], 'binary': build['binary'],
        'build': R.pin(A.WORK / 'native-build.json'), 'source_map': build['source_map'],
        'runtime_inputs': before, 'summary': R.pin(directory / 'actors/summary.json'),
        'seconds': process['seconds'], 'process': R.pin(directory / 'execution/result.full.json'),
        'cleanup': R.pin(directory / 'cleanup.json'), 'boundary': summary}, True)
    print(json.dumps({'status': summary['status'], 'evidence': R.pin(output)}), flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--expectations', action='store_true', help='file-only fixture/data checks')
    parser.add_argument('--native', action='store_true', help='consume the actual successful current actor')
    parser.add_argument('--small-native', action='store_true',
                        help='inventory/crafting/control/save without the separately blocked large component frame')
    parser.add_argument('--_child', type=Path, help=argparse.SUPPRESS)
    parser.add_argument('--_small', action='store_true', help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args._child:
        child(args._child, component_stress=not args._small)
    elif args.native:
        native()
    elif args.small_native:
        native(component_stress=False)
    elif args.expectations:
        value = requirements()
        output = ROOT / 'evidence/playable-client-actor004-boundary-expectations.json'
        R.write(output, value)
        print(json.dumps({'status': value['status'], 'expectations': R.pin(output)}), flush=True)
    else:
        parser.print_help()


if __name__ == '__main__':
    main()
