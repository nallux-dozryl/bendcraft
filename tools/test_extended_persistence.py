#!/usr/bin/env python3
"""Independent fixtures for the extension-aware native atomic save bundle.

Python builds/parses expected NBT and orchestrates actual MCP/TCP processes.
The affine extension array, live edits, migration, codecs and save publication
under test execute in native Bend. This is a fixture extension, not Minecraft
vanilla save-format or mod compatibility evidence.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
from pathlib import Path
import struct
import time

import test_persistence as P
import test_nbt as N
import test_world_codec as W

ROOT = P.ROOT
WORK = ROOT / 'build/extended-persistence-integration'
SERVER = ROOT / 'build/extended-persistence-server'
BRIDGE = ROOT / 'build/persistence-mcp'
TESTS = ROOT / 'build/extended-persistence-tests'
BEND = Path.home() / '.bend/bin/bend'
NAMESPACE = 'bendex:fixture-array'
BUNDLE_FIELDS = ('format', 'minecraft', 'registry', 'peer_highwater', 'core', 'extension')
EXTRA_FIELDS = ('namespace', 'schema', 'payload')
BUNDLE_MAX = 16846848
EXTENSION_MAX = 65536
FIXTURE_MODE = 'normal'
BASE_CLEAN_ENV = P.clean_env


def clean_env(path, port, registry, missing=None):
    env = BASE_CLEAN_ENV(path, port, registry, missing)
    env['MC_BUNDLE_FIXTURE'] = FIXTURE_MODE
    return env


def extra_root(cells, generation=0, schema=2):
    fields = [('cells', N.Value(11, tuple(cells)))]
    if schema == 2:
        fields.append(('generation', W.integer(generation)))
    return N.RootTag(N.text(NAMESPACE), W.compound(fields))


def extra_bytes(cells, generation=0, schema=2):
    return N.encode_root(extra_root(cells, generation, schema))


def bundle_root(core, identity, highwater, cells, generation=0, schema=2):
    return N.RootTag(N.text('bendex:bundle'), W.compound([
        ('format', W.integer(1)), ('minecraft', W.txt('26.3')), ('registry', W.txt(identity)),
        ('peer_highwater', W.integer(highwater)), ('core', N.Value(7, core)),
        ('extension', W.compound([('namespace', W.txt(NAMESPACE)), ('schema', W.integer(schema)),
                                 ('payload', N.Value(7, extra_bytes(cells, generation, schema)))])),
    ]))


def bundle_bytes(model, highwater, cells, generation=0, schema=2):
    return N.encode_root(bundle_root(P.canonical_expected(model), model['registry'], highwater,
                                   cells, generation, schema))


def parse_extra(payload, schema):
    root = N.Reader(payload, max_bytes=EXTENSION_MAX).root()
    if root.name != N.text(NAMESPACE) or schema not in (1, 2):
        raise ValueError('extension root/schema mismatch')
    fields = W.fields(root.value, ('cells',) if schema == 1 else ('cells', 'generation'))
    cells = fields['cells']
    if cells.kind != 11 or len(cells.payload) != 8:
        raise ValueError('extension cells must be IntArray with exactly eight U32 values')
    generation = 0 if schema == 1 else W.uint(fields['generation'])
    return cells.payload, generation


def validate_bundle(data, count, identity):
    root = N.Reader(data, max_bytes=BUNDLE_MAX, max_depth=6, max_elements=N.DEFAULT_BYTES).root()
    if root.name != N.text('bendex:bundle'):
        raise ValueError('wrong bundle root')
    fields = W.fields(root.value, BUNDLE_FIELDS)
    if W.uint(fields['format']) != 1 or W.scalar_text(fields['minecraft']) != '26.3':
        raise ValueError('wrong bundle format/version')
    if W.scalar_text(fields['registry']) != identity:
        raise ValueError('wrong bundle registry identity')
    highwater = W.uint(fields['peer_highwater'])
    core = fields['core']
    if core.kind != 7:
        raise ValueError('bundle core must be ByteArray')
    model = W.validate(N.parse(core.payload), count, identity)
    ext = W.fields(fields['extension'], EXTRA_FIELDS)
    if W.scalar_text(ext['namespace']) != NAMESPACE or ext['payload'].kind != 7:
        raise ValueError('wrong extension namespace/payload type')
    cells, generation = parse_extra(ext['payload'].payload, W.uint(ext['schema']))
    highwater = max(highwater, model['max_peer'] or 0)
    if highwater == 0xffffffff:
        raise ValueError('exhausted peer range')
    return model, cells, generation, highwater + 1


def corruption_fixtures(identity, count):
    model = W.empty_world(count, identity)
    root = bundle_root(P.canonical_expected(model), identity, 0, [0] * 8)
    result = []
    def add(name, value):
        data = N.encode_root(value) if isinstance(value, N.RootTag) else value
        try:
            validate_bundle(data, count, identity)
        except (ValueError, UnicodeError, struct.error):
            pass
        else:
            raise AssertionError('oracle accepted corrupt bundle: ' + name)
        result.append((name, data))
    def outer(name, value):
        return N.RootTag(root.name, W.replace_field(root.value, name, value))
    extension = dict(root.value.payload)[N.text('extension')]
    def ext(name, value):
        return outer('extension', W.replace_field(extension, name, value))
    add('bundle-root-name', N.RootTag(N.text('other:bundle'), root.value))
    add('bundle-format', outer('format', W.integer(2)))
    add('bundle-minecraft', outer('minecraft', W.txt('26.4')))
    add('bundle-registry', outer('registry', W.txt('f' * 64)))
    add('bundle-exhausted-peer', outer('peer_highwater', W.integer(0xffffffff)))
    for name in BUNDLE_FIELDS:
        target = N.text(name)
        field = next(field for key, field in root.value.payload if key == target)
        add('bundle-missing-' + name, N.RootTag(root.name, N.Value(10, tuple(f for f in root.value.payload if f[0] != target))))
        add('bundle-duplicate-' + name, N.RootTag(root.name, N.Value(10, root.value.payload + ((target, field),))))
        add('bundle-wrong-type-' + name, outer(name, W.byte(0)))
    add('bundle-unknown-member', N.RootTag(root.name, N.Value(10, root.value.payload + ((N.text('unknown'), W.byte(0)),))))
    for name in EXTRA_FIELDS:
        target = N.text(name)
        field = next(field for key, field in extension.payload if key == target)
        add('extension-missing-' + name, outer('extension', N.Value(10, tuple(f for f in extension.payload if f[0] != target))))
        add('extension-duplicate-' + name, outer('extension', N.Value(10, extension.payload + ((target, field),))))
        add('extension-wrong-type-' + name, ext(name, W.byte(0)))
    add('extension-unknown-member', outer('extension', N.Value(10, extension.payload + ((N.text('unknown'), W.byte(0)),))))
    for namespace in ('other:extension', '', 'Bendex:fixture-array'):
        add('extension-namespace-' + (namespace or 'empty'), ext('namespace', W.txt(namespace)))
    for schema in (0, 3, 0xffffffff):
        add('extension-schema-' + str(schema), ext('schema', W.integer(schema)))
    good = extra_root([0] * 8)
    def payload(name, changed):
        data = N.encode_root(changed) if isinstance(changed, N.RootTag) else changed
        add(name, ext('payload', N.Value(7, data)))
    payload('payload-root-name', N.RootTag(N.text('other:payload'), good.value))
    payload('payload-root-type', N.RootTag(good.name, W.integer(1)))
    payload('payload-cell-type', N.RootTag(good.name, W.replace_field(good.value, 'cells', N.Value(7, b'\0' * 8))))
    for length in (0, 7, 9):
        payload('payload-cell-count-' + str(length), extra_root([0] * length))
    payload('payload-generation-type', N.RootTag(good.name, W.replace_field(good.value, 'generation', W.txt('0'))))
    payload('payload-generation-missing', extra_root([0] * 8, schema=1))
    payload('payload-generation-duplicate', N.RootTag(good.name, N.Value(10, good.value.payload + (good.value.payload[-1],))))
    payload('payload-unknown-member', N.RootTag(good.name, N.Value(10, good.value.payload + ((N.text('unknown'), W.byte(0)),))))
    payload('payload-cell-duplicate', N.RootTag(good.name, N.Value(10, good.value.payload + (good.value.payload[0],))))
    payload('payload-trailing', N.encode_root(good) + b'\0')
    payload('payload-truncated', N.encode_root(good)[:-1])
    payload('payload-empty', b'')
    payload('payload-byte-limit', N.encode_root(good) + bytes(EXTENSION_MAX + 1 - len(N.encode_root(good))))
    add('schema1-with-generation', N.RootTag(root.name, W.replace_field(root.value, 'extension',
        W.replace_field(extension, 'schema', W.integer(1)))))
    for length in (7, 9):
        legacy = W.replace_field(W.replace_field(extension, 'schema', W.integer(1)),
                                 'payload', N.Value(7, extra_bytes([0] * length, schema=1)))
        add('schema1-cell-count-' + str(length), outer('extension', legacy))
    core = dict(root.value.payload)[N.text('core')].payload
    add('core-trailing', outer('core', N.Value(7, core + b'\0')))
    add('core-empty', outer('core', N.Value(7, b'')))
    inner = N.parse(core)
    add('core-count-mismatch', outer('core', N.Value(7, N.encode_root(N.RootTag(inner.name,
        W.replace_field(inner.value, 'state_count', W.integer(count + 1)))))))
    add('core-only-save-default-deny', P.envelope(core, identity, 0))
    raw = N.encode_root(root)
    for end in sorted(set([0, 1, 2, 3, 8, len(raw) // 2, *range(len(raw) - 16, len(raw))])):
        add('bundle-truncated-' + str(end), raw[:end])
    add('bundle-trailing', raw + b'\0')
    return result


def extra_snapshot(cells, generation, blocked=False):
    return {'cells': list(cells), 'generation': generation, 'blocked': blocked}


def get_extra(client, cells, generation, blocked=False):
    actual = client.call('extra.get', {})
    P.require(actual == extra_snapshot(cells, generation, blocked), 'extra.get differs from independent array/generation/flag fixture')
    return actual


def saved(client, path, model, highwater, cells, generation, records, name):
    response = client.call('world.save', {})
    data = path.read_bytes()
    expected = bundle_bytes(model, highwater, cells, generation)
    P.require(data == expected, 'physical bundle bytes differ from independent fixture: ' + name)
    P.require(response == {'status': 'durable', 'published': True, 'durable': True,
                           'bytes': len(data), 'peer_highwater': highwater}, 'bundle save response differs')
    core, extra, gen, _ = validate_bundle(data, model['state_count'], model['registry'])
    P.require(extra == tuple(cells) and gen == generation and core['sections'] == model['sections']
              and core['pending'] == model['pending'] and core['events'] == model['events'],
              'independent decoded bundle state differs')
    records.append({'scenario': name, 'bytes': len(data), 'sha256': P.sha(data),
                    'core_sha256': P.sha(P.canonical_expected(model)),
                    'extra_sha256': P.sha(extra_bytes(cells, generation)),
                    'generation': generation, 'cells': list(cells), 'peer_highwater': highwater,
                    'clock': P.clock(model), 'response': response})
    return data


def live_integration(identity, count, saves, rejections, checks, metrics):
    path = WORK / 'live-bundle.nbt'; path.unlink(missing_ok=True)
    model = W.empty_world(count, identity)
    cells = [0] * 8; generation = 0
    origin = {'dimension': 'minecraft:overworld', 'x': -17, 'y': -1, 'z': 31}
    key = 'minecraft:overworld/4294967294/4294967295/1'
    runtime = P.Runtime(path, missing='create')
    try:
        actor, actor_ping = runtime.client()
        observer, observer_ping = runtime.client(False)
        tools = actor.request('tools/list')['result']['tools']
        names = [tool['name'] for tool in tools]
        P.require(len(names) == len(set(names)) and {'world.save', 'extra.get', 'extra.set', 'extra.block'} <= set(names),
                  'actual MCP dynamic discovery omitted or duplicated extension operations')
        get_extra(observer, cells, generation)
        observer.call('extra.set', {'index': 0, 'value': 1}, fault='PermissionDenied')
        observer.call('extra.block', {'blocked': True}, fault='PermissionDenied')
        observer.call('world.save', {}, fault='PermissionDenied')
        for name, args, extra in [
            ('extra.get', {'unknown': True}, {}), ('extra.get', {}, {'at': 1}),
            ('extra.set', {'index': 8, 'value': 1}, {}), ('extra.set', {'index': -1, 'value': 1}, {}),
            ('extra.set', {'index': 0, 'value': 4294967296}, {}),
            ('extra.set', {'index': 0, 'value': '1'}, {}), ('extra.set', {'index': 0}, {}),
            ('extra.set', {'index': 0, 'value': 1, 'unknown': True}, {}),
            ('extra.set', {'index': 0, 'value': 1}, {'at': 1}),
            ('extra.block', {}, {}), ('extra.block', {'blocked': 1}, {}),
            ('extra.block', {'blocked': False, 'unknown': True}, {}),
            ('extra.block', {'blocked': False}, {'at': 1}),
        ]:
            actor.call(name, args, fault='InvalidArguments', **extra)
        get_extra(observer, cells, generation)
        P.require(actor.call('world.clock') == P.clock(model) and not path.exists(), 'extension/schema rejection mutated Core or published')
        saved(actor, path, model, observer_ping['peer'], cells, generation, saves, 'fresh-core-plus-eight-zero-cells')
        checks.append('actual native TCP/MCP dynamic catalog, observer Extra query, developer-only mutation/save, strict argument types/ranges/fieldsets and no-at enforcement')

        first = P.stamp(actor.call('world.section.create', origin | {'fill': 0}))
        actor.call('simulation.step', {'ticks': 1})
        second = P.stamp(actor.call('world.block.set', origin | {'state': 1}))
        actor.call('simulation.step', {'ticks': 1})
        block = P.stamp(actor.call('world.block.set', origin | {'state': 7}, at=4))
        future_time = P.stamp(actor.call('world.time.set', {'day_time': 999}, at=5))
        future_daylight = P.stamp(actor.call('world.daylight.set', {'enabled': False}, at=5))
        model.update(tick=2, day_time=2, revision=2)
        model['sections'] = [W.section(key, 0, [(4095, 1)])]
        model['events'] = [{'stamp': second, 'kind': 0, 'revision': 2}, {'stamp': first, 'kind': 0, 'revision': 1}]
        model['pending'] = [
            {'stamp': block, 'mutation': {'kind': 1, 'dimension': origin['dimension'],
                                         'x': (-17) & 0xffffffff, 'y': 0xffffffff, 'z': 31, 'state': 7}},
            {'stamp': future_time, 'mutation': {'kind': 2, 'day_time': 999}},
            {'stamp': future_daylight, 'mutation': {'kind': 3, 'enabled': False}},
        ]
        for index, value in [(0, 0xffffffff), (3, 0x80000000), (7, 7)]:
            cells[index] = value; generation += 1
            P.require(actor.call('extra.set', {'index': index, 'value': value}) == extra_snapshot(cells, generation),
                      'extra.set did not commit the exact value and generation increment')
        P.require(actor.call('world.clock') == P.clock(model), 'extension edits changed Core clock')
        saver, saver_ping = runtime.client()
        highwater = saver_ping['peer']
        prior = saved(saver, path, model, highwater, cells, generation, saves, 'queued-core-and-raw-u32-extra')
        lock_path = Path(str(path) + '.lock'); lock_inode = lock_path.stat().st_ino
        P.rejection('concurrent-extension-bundle-writer', path, P.OFFICIAL, rejections)
        P.require(path.read_bytes() == prior, 'contending bundle writer altered old bytes')

        # Failure after both owned components exist: neither owner may vanish.
        P.require(actor.call('extra.block', {'blocked': True}) == extra_snapshot(cells, generation, True), 'encode rejection flag toggle')
        actor.call('world.save', {}, fault='SaveEncodingFailed')
        get_extra(observer, cells, generation, True)
        P.require(actor.call('world.clock') == P.clock(model)
                  and actor.call('world.block.get', origin)['state'] == 1 and path.read_bytes() == prior,
                  'deliberate encode failure lost Core or changed previous bundle')
        P.require(actor.call('registry.block', {'name': 'minecraft:stone'})['default_state_id'] == 1,
                  'deliberate encoding failure lost the registry owner')
        P.require(actor.call('extra.block', {'blocked': False}) == extra_snapshot(cells, generation), 'encode rejection flag clear')
        cells[2] = 42; generation += 1
        P.require(actor.call('extra.set', {'index': 2, 'value': 42}) == extra_snapshot(cells, generation),
                  'Extra owner unusable after encoding failure')
        third = P.stamp(actor.call('world.block.set', origin | {'state': 2}, at=3))
        actor.call('simulation.step', {'ticks': 1})
        model.update(tick=3, day_time=3, revision=3)
        model['sections'] = [W.section(key, 0, [(4095, 2)])]
        model['events'] = [{'stamp': third, 'kind': 0, 'revision': 3}] + model['events']
        prior = saved(saver, path, model, highwater, cells, generation, saves, 'both-owners-reused-after-encode-failure')
        checks.append('a deliberately blocked Extra encoder reports SaveEncodingFailed without publishing, then both Core and affine Extra owners support exact mutation and durable save after clear')

        ping = saver.call('ping')
        collision = Path(str(path) + f'.pending-save-{ping["peer"]}-{ping["sequence"] + 2}')
        collision.write_bytes(b'unowned-extension-pending')
        saver.call('world.save', {}, fault='SaveNotPublished')
        P.require(path.read_bytes() == prior and collision.read_bytes() == b'unowned-extension-pending',
                  'OS save failure changed old bundle or unowned temp')
        get_extra(observer, cells, generation)
        P.require(actor.call('world.clock') == P.clock(model) and actor.call('world.block.get', origin)['state'] == 2,
                  'OS save failure lost either live owner')
        P.require(actor.call('registry.block', {'name': 'minecraft:stone'})['default_state_id'] == 1,
                  'OS save failure lost the registry owner')
        collision.unlink()
        saved(saver, path, model, highwater, cells, generation, saves, 'both-owners-reused-after-os-failure')
        checks.append('real exclusive-temp create failure leaves prior complete bundle and unowned temp untouched, retains both owners, and permits the next durable save')
        runtime.stop(kill=True); runtime = None
        runtime = P.Runtime(path)
        P.require(lock_path.stat().st_ino == lock_inode, 'bundle lease file was replaced at restart')
        observer, restored_observer = runtime.client(False)
        P.require(restored_observer['peer'] == highwater + 1, 'bundle restart observer peer')
        get_extra(observer, cells, generation)
        observer.call('extra.set', {'index': 0, 'value': 0}, fault='PermissionDenied')
        actor, restored = runtime.client()
        P.require(restored['peer'] == highwater + 2 and actor.call('world.clock') == P.clock(model), 'bundle restart Core/peer/session policy')
        P.require(actor.call('world.block.get', origin)['state'] == 2, 'bundle restart lost signed section')
        actor.call('simulation.step', {'ticks': 1})
        P.require(actor.call('world.block.get', origin)['state'] == 7, 'original queued Core block edit did not execute')
        actual_clock = actor.call('simulation.step', {'ticks': 1})
        model.update(tick=5, day_time=999, revision=6, daylight=False)
        model['pending'] = []
        model['sections'] = [W.section(key, 0, [(4095, 7)])]
        model['events'] = [
            {'stamp': future_daylight, 'kind': 0, 'revision': 6}, {'stamp': future_time, 'kind': 0, 'revision': 5},
            {'stamp': block, 'kind': 0, 'revision': 4},
        ] + model['events']
        P.require(actual_clock == P.clock(model), 'restarted queue final clock differs')
        get_extra(observer, cells, generation)
        saved(actor, path, model, restored['peer'], cells, generation, saves, 'restarted-core-queue-completed-extra-generation-stable')
        metrics.update(first_generation_save_peer=highwater, restarted_peers=[restored_observer['peer'], restored['peer']],
                       generation_after_restart=generation, lease_inode_preserved=True)
        checks.append('actual SIGKILL/restart atomically restores paused Core and exact Extra cells/generation; original queued Core edits execute after restart while Extra generation remains unchanged; lease reacquires without unlink')
    finally:
        if runtime is not None:
            runtime.stop()


def migrated_and_boundary_fixtures(tiny, identity, count, saves, checks, metrics):
    observations = []
    for name, schema, generation, highwater, cells in [
        ('schema1-migration', 1, 0, 80, [0, 1, 2, 3, 4, 0x80000000, 0xffffffff, 7]),
        ('schema2-generation-max', 2, 0xffffffff, 90, [0xffffffff] * 8),
        ('all-field-orders', 2, 123, 100, list(range(8))),
        ('core-larger-than-extension-budget', 2, 456, 110, list(range(8))),
    ]:
        model = W.empty_world(count, identity)
        if name == 'core-larger-than-extension-budget':
            model['sections'] = [W.section('minecraft:overworld/' + str(i) + '/0/0', i) for i in range(5)]
            P.require(len(P.canonical_expected(model)) > EXTENSION_MAX, 'Core field budget fixture is too small')
        root = bundle_root(P.canonical_expected(model), identity, highwater, cells, generation, schema)
        if name == 'all-field-orders':
            fields = dict(root.value.payload)
            core = N.parse(fields[N.text('core')].payload)
            reordered_core = N.encode_root(N.RootTag(core.name, N.Value(10, tuple(reversed(core.value.payload)))))
            ext = fields[N.text('extension')]
            extra = N.parse(dict(ext.payload)[N.text('payload')].payload)
            reordered_extra = N.encode_root(N.RootTag(extra.name, N.Value(10, tuple(reversed(extra.value.payload)))))
            ext = W.replace_field(ext, 'payload', N.Value(7, reordered_extra))
            root = N.RootTag(root.name, W.replace_field(W.replace_field(root.value, 'core', N.Value(7, reordered_core)),
                                                      'extension', N.Value(10, tuple(reversed(ext.payload)))))
            root = N.RootTag(root.name, N.Value(10, tuple(reversed(root.value.payload))))
        data = N.encode_root(root)
        P.require(validate_bundle(data, count, identity)[1:3] == (tuple(cells), generation), 'independent migration fixture')
        path = WORK / (name + '.nbt'); path.write_bytes(data)
        runtime = P.Runtime(path, tiny)
        try:
            observer, ping = runtime.client(False)
            P.require(ping['peer'] == highwater + 1, 'migrated fixture next peer')
            get_extra(observer, cells, generation)
            actor, developer_ping = runtime.client()
            P.require(actor.call('world.clock') == P.clock(model), 'migration/boundary fixture changed Core')
            if generation == 0xffffffff:
                actor.call('extra.set', {'index': 0, 'value': 1}, fault='GenerationExhausted')
                get_extra(observer, cells, generation)
                P.require(actor.call('world.clock') == P.clock(model), 'generation exhaustion lost Core owner')
            saved(actor, path, model, developer_ping['peer'], cells, generation, saves, name + '-canonical-schema2')
            observations.append({'case': name, 'input_schema': schema, 'input_generation': generation,
                                 'restored_generation': generation, 'canonical_output_schema': 2,
                                 'first_peer': ping['peer'], 'bytes': len(data), 'input_sha256': P.sha(data)})
        finally:
            runtime.stop()
    metrics['migration_and_generation_fixtures'] = observations
    checks.append('actual schema1 cells-only migration yields generation zero and canonical schema2 save; all compound orders canonicalize; generation U32MAX rejects mutation without changing Core or Extra; valid Core bytes above the Extra byte budget remain accepted')


def startup_rejections(tiny, identity, count, cases, records, checks):
    path = WORK / 'corrupt-bundle.nbt'
    for name, data in cases:
        path.write_bytes(data)
        P.rejection(name, path, tiny, records, 'create')
        P.require(path.read_bytes() == data, 'startup rejection altered bundle: ' + name)
    missing = WORK / 'missing-bundle.nbt'; missing.unlink(missing_ok=True)
    P.rejection('missing-bundle-refuse', missing, tiny, records)
    P.rejection('invalid-missing-policy', missing, tiny, records, 'invalid')
    checks.append('actual malformed bundle/extension/Extra/Core, wrong namespace/schema, extension byte limit, duplicate/missing/unknown fields, truncation/trailing data and core-only input all refuse before any listener')


def compiled_policy_fixtures(tiny, identity, count, saves, records, checks, metrics):
    global FIXTURE_MODE
    model = W.empty_world(count, identity)
    path = WORK / 'explicit-core-init.nbt'
    path.write_bytes(P.envelope(P.canonical_expected(model), identity, 120))
    FIXTURE_MODE = 'core-init'
    runtime = None
    try:
        runtime = P.Runtime(path, tiny)
        observer, ping = runtime.client(False)
        P.require(ping['peer'] == 121, 'explicit core-only init did not retain saved peer highwater')
        get_extra(observer, [0] * 8, 0)
        actor, developer = runtime.client()
        P.require(actor.call('world.clock') == P.clock(model), 'explicit core-only init changed Core')
        saved(actor, path, model, developer['peer'], [0] * 8, 0, saves, 'explicit-core-only-init-canonical-bundle')
        metrics['explicit_core_init'] = {'first_peer': 121, 'save_peer': developer['peer'],
                                         'cells': [0] * 8, 'generation': 0, 'output_format': 'bendex:bundle'}
    finally:
        if runtime is not None:
            runtime.stop()
        FIXTURE_MODE = 'normal'
    for mode in ('reserved', 'duplicate', 'invalid-schema', 'bad-namespace', 'bad-schema', 'fresh-fail', 'small-budget'):
        path = WORK / ('compiled-policy-' + mode + '.nbt'); path.unlink(missing_ok=True)
        FIXTURE_MODE = mode
        try:
            P.rejection('compiled-' + mode, path, tiny, records, 'create')
            P.require(not path.exists(), 'rejected compiled setup or fresh initializer published a file')
        finally:
            FIXTURE_MODE = 'normal'
    checks.append('explicit closed core-only migration initializes exactly eight zero cells/generation zero and saves a canonical bundle; seven compiled reserved/duplicate/schema/namespace/fresh/budget failures refuse before any listener')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--fixtures-only', action='store_true')
    parser.add_argument('--skip-build', action='store_true')
    parser.add_argument('--bend', type=Path, default=BEND)
    args = parser.parse_args()
    WORK.mkdir(parents=True, exist_ok=True)
    tiny = WORK / 'tiny-registry.tsv'; tiny.write_text(P.TINY_TSV)
    identity, count, tiny_registry = P.registry_identity(tiny)
    cases = corruption_fixtures(identity, count)
    if args.fixtures_only:
        print(json.dumps({'invalid_bundle_fixtures': len(cases), 'registry': identity, 'state_count': count}, indent=2))
        return 0
    started = time.monotonic()
    # The reused helpers remain independent protocol/process orchestration.
    # Their module-local target is redirected only in this test subprocess.
    P.SERVER = SERVER; P.BRIDGE = BRIDGE; P.clean_env = clean_env
    P.Runtime.observed = []
    commands = []
    if not args.skip_build:
        for source, binary in [('extended_persistence_server.bend', SERVER), ('mcp.bend', BRIDGE),
                               ('tests/extended_persistence.bend', TESTS)]:
            commands.append(P.run([args.bend, source, '-o', binary]))
    sources = list(dict.fromkeys(P.SOURCE_FILES + [
        'extended_persistence_server.bend', 'src/extended_persistence.bend',
        'tests/extended_persistence.bend', 'tools/test_extended_persistence.py',
    ]))
    frozen_sources = {name: P.fingerprint(ROOT / name) for name in sources}
    frozen_binaries = {name: P.fingerprint(path) for name, path in [('server', SERVER), ('mcp', BRIDGE), ('tests', TESTS)]}
    commands.append(P.run([TESTS, '--threads', '1', '--gpu', 'off']))
    P.require(commands[-1]['stdout'] == 'regressions\tpass', 'native extension persistence builtins')
    official_identity, official_count, official_registry = P.registry_identity(P.OFFICIAL)
    checks, saves, rejections, metrics = [], [], [], {}
    live_integration(official_identity, official_count, saves, rejections, checks, metrics)
    migrated_and_boundary_fixtures(tiny, identity, count, saves, checks, metrics)
    startup_rejections(tiny, identity, count, cases, rejections, checks)
    compiled_policy_fixtures(tiny, identity, count, saves, rejections, checks, metrics)
    clients = [client for runtime in P.Runtime.observed for client in runtime.clients]
    metrics.update(native_ready_servers=len(P.Runtime.observed), native_mcp_processes=len(clients),
                   stdio_requests=sum(client.requests for client in clients),
                   stdio_responses=sum(client.responses for client in clients),
                   notifications=sum(client.notifications for client in clients))
    P.require(frozen_sources == {name: P.fingerprint(ROOT / name) for name in sources},
              'source or independent oracle changed during native extension verification')
    P.require(frozen_binaries == {name: P.fingerprint(path) for name, path in [('server', SERVER), ('mcp', BRIDGE), ('tests', TESTS)]},
              'native extension binary changed during verification')
    P.require(official_registry['source_sha256'] == P.fingerprint(P.OFFICIAL), 'official registry changed during run')
    report = {
        'schema_version': 1, 'status': 'passed', 'kind': 'actual_native_extension_bundle_mcp_tcp_integration',
        'recorded_at_utc': datetime.now(timezone.utc).isoformat(),
        'command': 'python3 tools/test_extended_persistence.py' + (' --skip-build' if args.skip_build else ''),
        'confidence': 'high for the recorded fixture-extension save, migration, owner recovery and startup observations',
        'checks': checks, 'save_observations': saves, 'startup_rejections': rejections,
        'save_count': len(saves), 'startup_rejection_count': len(rejections), 'corrupt_bundle_fixtures': len(cases),
        'actual_server_sigkill_cases': 1, 'actual_save_os_failures': 1, 'actual_save_encode_failures': 1,
        'generation_exhaustion_cases': 1, 'metrics': metrics,
        'registry': {'official': official_registry, 'tiny': tiny_registry},
        'fixture_corpus_sha256': P.sha(b''.join(name.encode() + b'\0' + data for name, data in cases)),
        'source_sha256': frozen_sources, 'binary_sha256': frozen_binaries,
        'oracle_sha256': frozen_sources['tools/test_extended_persistence.py'],
        'compiler_sha256': P.fingerprint(args.bend), 'commands': commands,
        'elapsed_seconds': round(time.monotonic() - started, 3),
        'limits': [
            'Fixture extension with one affine eight-cell U32 Array and a U32 generation; no vanilla Minecraft save or arbitrary mod persistence claim.',
            'Schema1 migration is exactly cells-only to generation zero; schema2 is current. Unsupported namespaces/schemas and default core-only input refuse startup. A separate explicit compiled core-init policy initializes eight zero cells and is verified independently.',
            'SIGKILL follows acknowledged durable publication; no simulated power loss or injected directory-sync failure is claimed.',
            'Actual startup/adoption, mutation, codecs and atomic publication execute in native Bend; Python supplies expected fixtures and process/protocol orchestration.',
            'Effectful lifetimes/OS lease/durability adapters are outside the pure kernel proof boundary; this integration pass is not a universal proof.',
        ],
    }
    (ROOT / 'evidence/extended-persistence-integration.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({key: report[key] for key in ['status', 'save_count', 'startup_rejection_count',
                                                'corrupt_bundle_fixtures', 'elapsed_seconds']}, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
