#!/usr/bin/env python3
"""Actual native MCP/TCP save, process termination, reload and failure tests.

Python creates independent NBT/registry fixtures and orchestrates processes.
All live mutation, save encoding, publication and reload policy execute in Bend.
This is the current Core.World save format, not a vanilla Minecraft world save.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import select
import socket
import struct
import subprocess
import time

import test_mcp as M
import test_nbt as N
import test_world_codec as W

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / 'build/persistence-integration'
SERVER = ROOT / 'build/persistence-server'
BRIDGE = ROOT / 'build/persistence-mcp'
TESTS = ROOT / 'build/persistence-tests'
OFFICIAL = ROOT / 'generated/reference_blocks.tsv'
FILE_MAX = 16 * 1024 * 1024 + 4096
SAVE_FIELDS = ('format', 'minecraft', 'registry', 'peer_highwater', 'world')
HEADER = 'block_protocol_id\tidentifier\tfirst_state_id\tstate_count\tdefault_state_id\tordered_properties_json'
TINY_TSV = (HEADER + '\n0\tminecraft:air\t0\t1\t0\t[]\n'
            '1\tminecraft:stone\t1\t1\t1\t[]\n'
            '2\tminecraft:oak_log\t2\t3\t3\t[{"name":"axis","values":["x","y","z"]}]\n')
SOURCE_FILES = [
    'persistence_server.bend', 'src/persistence.bend',
    'tests/persistence.bend', 'src/world_codec.bend', 'src/nbt.bend', 'src/core.bend',
    'src/section.bend', 'src/section_map.bend', 'src/schedule.bend', 'src/game.bend',
    'src/registry.bend', 'src/hash.bend', 'src/server.bend', 'src/live.bend', 'src/json.bend',
    'src/atomic_file.bend', 'src/durability.bend', 'src/native/durability.c',
    'src/native/durability.js', 'src/world_lock.bend', 'src/native/world_lock.c',
    'src/native/world_lock.js', 'mcp.bend', 'src/mcp.bend', 'src/framing.bend',
    'tools/test_persistence.py', 'tools/test_mcp.py', 'tools/test_nbt.py', 'tools/test_world_codec.py',
]


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def fingerprint(path):
    return sha(Path(path).read_bytes())


def registry_identity(path):
    """Independent parsed-metadata identity v1; TSV spacing is not identity."""
    lines = Path(path).read_text().splitlines()
    require(lines[0] == HEADER, 'registry fixture header')
    blocks = []
    for line in lines[1:]:
        if not line:
            continue
        protocol, name, first, count, default, properties = line.split('\t')
        blocks.append((int(protocol), name, int(first), int(count), int(default), json.loads(properties)))
    state_count = sum(block[3] for block in blocks)
    out = bytearray(b'BendRegistryIdentity\0')
    def number(value):
        out.extend(struct.pack('>I', value))
    def string(value):
        raw = value.encode('utf-8', errors='strict')
        number(len(raw)); out.extend(raw)
    for value in (1, len(blocks), state_count):
        number(value)
    for protocol, name, first, count, default, properties in blocks:
        number(protocol); string(name)
        for value in (first, count, default, len(properties)):
            number(value)
        strides, product = [], 1
        for prop in reversed(properties):
            strides.append(product); product *= len(prop['values'])
        require(product == count, 'independent property count disagrees with registry')
        for prop, stride in zip(properties, reversed(strides), strict=True):
            string(prop['name']); number(len(prop['values'])); number(stride)
            for value in prop['values']:
                string(value)
    return sha(out), state_count, {'blocks': len(blocks), 'states': state_count,
                                  'canonical_bytes': len(out), 'canonical_sha256': sha(out),
                                  'source_sha256': fingerprint(path)}


def envelope_root(world, identity, highwater):
    return N.RootTag(N.text('bendex:save'), W.compound([
        ('format', W.integer(1)), ('minecraft', W.txt('26.3')), ('registry', W.txt(identity)),
        ('peer_highwater', W.integer(highwater)), ('world', N.Value(7, world)),
    ]))


def envelope(world, identity, highwater):
    return N.encode_root(envelope_root(world, identity, highwater))


def validate_save(data, count, identity):
    root = N.Reader(data, max_bytes=FILE_MAX, max_elements=min(FILE_MAX, N.DEFAULT_BYTES), max_depth=4).root()
    if root.name != N.text('bendex:save'):
        raise ValueError('wrong save root name')
    fields = W.fields(root.value, SAVE_FIELDS)
    if W.uint(fields['format']) != 1 or W.scalar_text(fields['minecraft']) != '26.3':
        raise ValueError('save format/version mismatch')
    if W.scalar_text(fields['registry']) != identity:
        raise ValueError('save registry identity mismatch')
    highwater = W.uint(fields['peer_highwater'])
    if fields['world'].kind != 7:
        raise ValueError('save world is not TAG_ByteArray')
    world_bytes = fields['world'].payload
    model = W.validate(N.parse(world_bytes), count, identity)
    peer = max(highwater, model['max_peer'] or 0)
    if peer == 0xffffffff:
        raise ValueError('peer identity range exhausted')
    return model, highwater, peer + 1, world_bytes


def clean_env(path, port, registry, missing=None):
    env = os.environ.copy()
    for key in ('MC_WORLD_PATH', 'MC_WORLD_MISSING', 'MC_ATOMIC_PAUSE'):
        env.pop(key, None)
    env.update(MC_LIVE_PORT=str(port), MC_DEV_TOKEN=M.TOKEN, MC_BLOCK_REGISTRY=str(registry))
    if path is not None:
        env['MC_WORLD_PATH'] = str(path)
    if missing is not None:
        env['MC_WORLD_MISSING'] = missing
    return env


class Runtime:
    observed = []

    def __init__(self, path, registry=OFFICIAL, missing=None):
        self.port = M.free_port()
        self.process = subprocess.Popen([str(SERVER), '--threads', '2', '--gpu', 'off'],
                                        cwd=ROOT, env=clean_env(path, self.port, registry, missing),
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.clients = []
        try:
            require(select.select([self.process.stdout], [], [], 15)[0], 'persistence startup timed out')
            line = self.process.stdout.readline()
            if not line:
                error = self.process.stderr.read().decode(errors='replace')
                raise AssertionError('persistence startup failed: ' + error)
            self.ready = json.loads(line)
            require(self.ready.get('port') == self.port, 'wrong persistence readiness port')
        except Exception:
            if self.process.poll() is None:
                self.process.kill()
            self.process.communicate(timeout=5)
            raise
        self.observed_peers = []
        Runtime.observed.append(self)

    def client(self, developer=True):
        client = M.MCP(BRIDGE, self.port, M.TOKEN if developer else None)
        self.clients.append(client)
        client.initialize()
        ping = client.call('ping')
        require(ping['mode'] == ('developer' if developer else 'observer'), 'startup session capability')
        require(ping['sequence'] == (3 if developer else 2), 'fresh session sequence was not reset')
        self.observed_peers.append(ping['peer'])
        return client, ping

    def stop(self, kill=False):
        for client in self.clients:
            client.cleanup()
        if self.process.poll() is None:
            self.process.kill() if kill else self.process.terminate()
        stdout, stderr = self.process.communicate(timeout=5)
        require(M.TOKEN.encode() not in stdout + stderr, 'server output leaked configured token')
        require(not stdout and not stderr, 'unexpected persistence lifetime output')
        if kill:
            require(self.process.returncode == -9, 'actual SIGKILL was not observed')


def rejection(name, path, registry, records, missing=None):
    started = time.monotonic()
    timeout = 60 if isinstance(path, Path) and path.is_file() and path.stat().st_size >= 1024 * 1024 else 15
    port = M.free_port()
    process = subprocess.Popen([str(SERVER), '--threads', '1', '--gpu', 'off'], cwd=ROOT,
                               env=clean_env(path, port, registry, missing),
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    try:
        stdout, stderr = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        process.kill(); process.communicate(timeout=5)
        raise AssertionError('invalid startup did not refuse: ' + name) from None
    require(process.returncode != 0 and not stdout, 'invalid startup emitted readiness: ' + name)
    require(stderr and M.TOKEN.encode() not in stderr, 'missing or secret-bearing startup diagnostic: ' + name)
    with socket.socket() as probe:
        probe.settimeout(1)
        require(probe.connect_ex(('127.0.0.1', port)) != 0, 'invalid startup left a listener: ' + name)
    record = {'case': name, 'exit_code': process.returncode, 'listener_refused': True,
              'elapsed_seconds': round(time.monotonic() - started, 6),
              'startup_deadline_seconds': timeout,
              'diagnostic': stderr.decode(errors='replace').strip()[:512]}
    if isinstance(path, Path) and path.is_file():
        record.update(bytes=path.stat().st_size, input_sha256=fingerprint(path))
    records.append(record)


def canonical_expected(world):
    encoded = N.encode_root(W.snapshot_root(world))
    W.validate(N.parse(encoded), world['state_count'], world['registry'])
    return encoded


def saved(client, path, model, highwater, saves, label):
    result = client.call('world.save', {})
    data = path.read_bytes()
    expected_world = canonical_expected(model)
    expected = envelope(expected_world, model['registry'], highwater)
    require(data == expected, 'saved physical NBT differs from independent fixture: ' + label)
    require(result == {'status': 'durable', 'published': True, 'durable': True,
                       'bytes': len(data), 'peer_highwater': highwater}, 'durable save response differs')
    decoded, actual_highwater, _, world_bytes = validate_save(data, model['state_count'], model['registry'])
    require(world_bytes == expected_world and actual_highwater == highwater, 'saved envelope metadata')
    require(decoded['sections'] == model['sections'] and decoded['events'] == model['events']
            and decoded['pending'] == model['pending'], 'saved independent World model differs')
    saves.append({'scenario': label, 'bytes': len(data), 'save_sha256': sha(data),
                  'world_sha256': sha(world_bytes), 'peer_highwater': highwater,
                  'response': result, 'clock': {k: model[k] for k in
                                               ('tick', 'day_time', 'paused', 'daylight', 'revision')}})
    return data


def clock(world):
    return {k: world[k] for k in ('tick', 'day_time', 'paused', 'daylight', 'revision')} | {'pending': len(world['pending'])}


def stamp(result):
    s = result['stamp']
    return (s['tick'], s['peer'], s['sequence'])


def live_roundtrip(identity, count, saves, checks, metrics, records):
    path = WORK / 'live-world.nbt'; path.unlink(missing_ok=True)
    runtime = Runtime(path, missing='create')
    model = W.empty_world(count, identity)
    origin = {'dimension': 'minecraft:overworld', 'x': -17, 'y': -1, 'z': 31}
    other = {'dimension': 'minecraft:the_nether', 'x': -2147483648, 'y': 2147483647, 'z': -16}
    origin_key = 'minecraft:overworld/4294967294/4294967295/1'
    other_key = 'minecraft:the_nether/4160749568/134217727/4294967295'
    try:
        actor, actor_ping = runtime.client()
        listed = actor.request('tools/list')['result']['tools']
        tool = [tool for tool in listed if tool['name'] == 'world.save']
        require(len(tool) == 1, 'actual MCP discovery omitted or duplicated world.save')
        observer, idle_ping = runtime.client(False)
        observer.call('world.save', {}, fault='PermissionDenied')
        require(not path.exists(), 'observer save wrote a file')
        actor.call('world.save', {'unexpected': True}, fault='InvalidArguments')
        actor.call('world.save', {}, at=1, fault='InvalidArguments')
        require(not path.exists() and actor.call('world.clock') == clock(model), 'rejected save changed state')
        saved(actor, path, model, idle_ping['peer'], saves, 'empty-with-observed-idle-peer')
        checks.append('actual MCP discovery, developer-only save, strict empty args/no at, and idle observed peer highwater')

        first = stamp(actor.call('world.section.create', origin | {'fill': 0}))
        second = stamp(actor.call('world.section.create', other | {'fill': 2}))
        require(first[0] == second[0] == 1, 'creation target tick')
        require(actor.call('simulation.step', {'ticks': 1})['revision'] == 2, 'two section creations')
        third = stamp(actor.call('world.block.set', origin | {'state': 1}))
        actor.call('simulation.step', {'ticks': 1})
        fourth = stamp(actor.call('world.time.set', {'day_time': 1000}))
        fifth = stamp(actor.call('world.daylight.set', {'enabled': False}))
        rejected = stamp(actor.call('world.section.create', origin | {'fill': 3}))
        actor.call('simulation.step', {'ticks': 1})
        model.update(tick=3, day_time=1000, revision=5, daylight=False)
        model['sections'] = [W.section(origin_key, 0, [(4095, 1)]), W.section(other_key, 2)]
        model['events'] = [
            {'stamp': rejected, 'kind': 1, 'error': {'kind': 4, 'key': origin_key}},
            {'stamp': fifth, 'kind': 0, 'revision': 5}, {'stamp': fourth, 'kind': 0, 'revision': 4},
            {'stamp': third, 'kind': 0, 'revision': 3}, {'stamp': second, 'kind': 0, 'revision': 2},
            {'stamp': first, 'kind': 0, 'revision': 1},
        ]
        block = stamp(actor.call('world.block.set', origin | {'state': 7}, at=5))
        time_set = stamp(actor.call('world.time.set', {'day_time': 999}, at=6))
        daylight = stamp(actor.call('world.daylight.set', {'enabled': True}, at=6))
        model['pending'] = [
            {'stamp': block, 'mutation': {'kind': 1, 'dimension': origin['dimension'],
                                         'x': (-17) & 0xffffffff, 'y': 0xffffffff, 'z': 31, 'state': 7}},
            {'stamp': time_set, 'mutation': {'kind': 2, 'day_time': 999}},
            {'stamp': daylight, 'mutation': {'kind': 3, 'enabled': True}},
        ]
        require(actor.call('world.clock') == clock(model), 'paused rich live clock')
        before_events = actor.call('world.events')
        require(before_events['events'][0]['kind'] == 'rejected'
                and before_events['events'][0]['error']['code'] == 'SectionExists', 'rejected event missing')
        saver, saver_ping = runtime.client()
        highwater = saver_ping['peer']
        saved(saver, path, model, highwater, saves, 'signed-sections-events-and-future-queue')
        acknowledged = path.read_bytes()
        lock_path = Path(str(path) + '.lock')
        require(lock_path.is_file(), 'world lease lock file is absent')
        lock_inode = lock_path.stat().st_ino
        rejection('concurrent-world-writer-lease', path, OFFICIAL, records)
        require(path.read_bytes() == acknowledged, 'rejected concurrent writer changed the save')
        actor.call('world.time.set', {'day_time': 1234}, at=4)
        require(actor.call('simulation.step', {'ticks': 1})['day_time'] == 1234,
                'unsaved mutation fixture did not change the running world')
        require(path.read_bytes() == acknowledged, 'an unsaved live mutation changed acknowledged file bytes')
        metrics['first_generation_peers'] = runtime.observed_peers
        metrics['first_generation_save_peer'] = highwater
        runtime.stop(kill=True)
        runtime = None
        checks.append('exact independently constructed outer and inner NBT bytes persist paused clock, signed sections, applied/rejected events and future queue; actual server SIGKILL after an additional unsaved mutation recovers the last durable snapshot')

        runtime = Runtime(path)
        require(lock_path.is_file() and lock_path.stat().st_ino == lock_inode,
                'restart replaced or unlinked the existing world lease file')
        new_observer, observer_ping = runtime.client(False)
        require(observer_ping['peer'] == highwater + 1 and observer_ping['mode'] == 'observer', 'restart peer/capability policy')
        new_observer.call('world.clock', fault='PermissionDenied')
        actor, ping = runtime.client()
        require(ping['peer'] == highwater + 2, 'restart monotonically allocated next peer')
        require(actor.call('world.clock') == clock(model), 'restart changed paused clock')
        require(actor.call('world.events') == before_events, 'restart changed event history')
        require(actor.call('world.block.get', origin)['state'] == 1
                and actor.call('world.block.get', other)['state'] == 2, 'restart lost section contents')
        require(actor.call('simulation.step', {'ticks': 1})['tick'] == 4, 'restart future queue pre-target')
        require(actor.call('world.block.get', origin)['state'] == 1, 'queued block applied early')
        actor.call('simulation.step', {'ticks': 1})
        require(actor.call('world.block.get', origin)['state'] == 7, 'queued block did not execute after restart')
        final_clock = actor.call('simulation.step', {'ticks': 1})
        model.update(tick=6, day_time=999, daylight=True, revision=8)
        model['pending'] = []
        model['sections'][0] = W.section(origin_key, 0, [(4095, 7)])
        model['events'] = [
            {'stamp': daylight, 'kind': 0, 'revision': 8}, {'stamp': time_set, 'kind': 0, 'revision': 7},
            {'stamp': block, 'kind': 0, 'revision': 6},
        ] + model['events']
        require(final_clock == clock(model), 'future queue post-restart final clock differs')
        old = saved(actor, path, model, ping['peer'], saves, 'queued-actions-executed-after-restart')
        checks.append('new observer sessions retain no developer capability; peers resume above saved callers; future actions execute at exact original stamps after reload')
        checks.append('actual second server on another port refuses the held world lease without readiness or listener; SIGKILL releases the OS lease and restart acquires the unchanged lock-file inode')
        metrics['world_lock_file_survives_sigkill'] = True

        # Actual exclusive-create failure at the exact next save sequence.
        latest = actor.call('ping')
        collision = Path(str(path) + f'.pending-save-{latest["peer"]}-{latest["sequence"] + 2}')
        collision.write_bytes(b'unowned-pending-fixture')
        actor.call('world.save', {}, fault='SaveNotPublished')
        require(path.read_bytes() == old and collision.read_bytes() == b'unowned-pending-fixture', 'failed publish changed old/unowned file')
        require(actor.call('world.clock') == clock(model) and actor.call('world.block.get', origin)['state'] == 7,
                'failed publication lost the affine live owner')
        collision.unlink()
        saved(actor, path, model, latest['peer'], saves, 'owner-reused-after-exclusive-temp-collision')
        checks.append('actual OS exclusive-create collision reports SaveNotPublished, preserves complete prior bytes and unowned pending file, and retains live World for query and subsequent durable save')
        metrics['second_generation_peers'] = runtime.observed_peers
        runtime.stop(kill=True); runtime = None
        runtime = Runtime(path)
        actor, last_ping = runtime.client()
        require(last_ping['peer'] == latest['peer'] + 1 and actor.call('world.clock') == clock(model), 'second restart byte/peer recovery')
        require(actor.call('world.block.get', origin)['state'] == 7, 'second restart lost recovered owner save')
        metrics['third_generation_peer'] = last_ping['peer']
    finally:
        if runtime is not None:
            runtime.stop()


def malformed_cases(identity, count):
    world = canonical_expected(W.empty_world(count, identity))
    root = envelope_root(world, identity, 0)
    cases = []
    def add(name, changed):
        data = N.encode_root(changed) if isinstance(changed, N.RootTag) else changed
        try:
            validate_save(data, count, identity)
        except (ValueError, UnicodeError, struct.error):
            pass
        else:
            raise AssertionError('independent oracle accepted corrupt fixture: ' + name)
        cases.append((name, data))
    def field(name, value):
        return N.RootTag(root.name, W.replace_field(root.value, name, value))
    add('root-name', N.RootTag(N.text('other:save'), root.value))
    add('root-type', N.RootTag(root.name, W.integer(1)))
    add('root-end', b'\0')
    add('format-version', field('format', W.integer(2)))
    add('minecraft-version', field('minecraft', W.txt('26.4')))
    add('registry-identity', field('registry', W.txt('0' * 64)))
    add('registry-uppercase', field('registry', W.txt(identity.upper())))
    add('exhausted-envelope-peer', field('peer_highwater', W.integer(0xffffffff)))
    for name in SAVE_FIELDS:
        target = N.text(name)
        members = root.value.payload
        item = next(item for key, item in members if key == target)
        add('duplicate-' + name, N.RootTag(root.name, N.Value(10, members + ((target, item),))))
        add('missing-' + name, N.RootTag(root.name, N.Value(10, tuple(p for p in members if p[0] != target))))
        add('wrong-type-' + name, field(name, W.byte(1)))
    add('unknown-member', N.RootTag(root.name, N.Value(10, root.value.payload + ((N.text('unknown'), W.byte(0)),))))
    add('lone-surrogate-root', N.RootTag((0xd800,), root.value))
    add('world-trailing', field('world', N.Value(7, world + b'\0')))
    add('world-empty-bytearray', field('world', N.Value(7, b'')))
    add('world-inner-truncation', field('world', N.Value(7, world[:-1])))
    add('world-byte-limit', field('world', N.Value(7, bytes(N.DEFAULT_BYTES + 1))))
    nested = W.byte(0)
    for _ in range(5):
        nested = W.compound([('nested', nested)])
    add('outer-nbt-depth', field('world', nested))
    inner = N.parse(world)
    for name, changed in [
        ('world-root-name', N.RootTag(N.text('other:world'), inner.value)),
        ('world-count-mismatch', N.RootTag(inner.name, W.replace_field(inner.value, 'state_count', W.integer(count + 1)))),
        ('world-identity-mismatch', N.RootTag(inner.name, W.replace_field(inner.value, 'registry', W.txt('f' * 64)))),
        ('world-malformed-nat', N.RootTag(inner.name, W.replace_field(inner.value, 'tick', W.txt('00')))),
        ('world-nat-overflow', N.RootTag(inner.name, W.replace_field(inner.value, 'revision', W.txt(W.NAT_MAX + 1)))),
        ('world-wrong-list-declaration', N.RootTag(inner.name, W.replace_field(inner.value, 'sections', W.listing([], 0)))),
        ('world-unknown-field', N.RootTag(inner.name, N.Value(10, inner.value.payload + ((N.text('unknown'), W.byte(0)),)))),
        ('world-duplicate-field', N.RootTag(inner.name, N.Value(10, inner.value.payload + (inner.value.payload[0],)))),
        ('world-missing-field', N.RootTag(inner.name, N.Value(10, inner.value.payload[1:]))),
    ]:
        add(name, field('world', N.Value(7, N.encode_root(changed))))
    for name, modify in [
        ('world-cell-count', lambda w: w.update(sections=[{'key': 'minecraft:overworld/0/0/0', 'cells': (0,) * 4095}])),
        ('world-cell-state', lambda w: w.update(sections=[W.section('minecraft:overworld/0/0/0', count)])),
        ('world-exhausted-pending-peer', lambda w: w.update(pending=[{'stamp': (1, 0xffffffff, 1), 'mutation': {'kind': 2, 'day_time': 0}}])),
        ('world-exhausted-event-peer', lambda w: w.update(events=[{'stamp': (0, 0xffffffff, 1), 'kind': 1, 'error': {'kind': 0}}])),
    ]:
        model = W.empty_world(count, identity); modify(model)
        add(name, field('world', N.Value(7, N.encode_root(W.snapshot_root(model)))))
    valid = N.encode_root(root)
    for end in sorted(set([*range(min(32, len(valid))), *range(len(valid) - 16, len(valid)), len(valid) // 2])):
        add('truncated-' + str(end), valid[:end])
    add('outer-trailing-zero', valid + b'\0')
    add('outer-trailing-tag', valid + b'\x03\0\0\0\0\0\0')
    add('outer-file-too-large', valid + bytes(FILE_MAX + 1 - len(valid)))
    return cases


def startup_tests(tiny, identity, count, official_identity, records, checks):
    missing = WORK / 'missing-world.nbt'; missing.unlink(missing_ok=True)
    rejection('path-unset', None, tiny, records)
    rejection('path-empty', '', tiny, records)
    rejection('missing-default-refuse', missing, tiny, records)
    rejection('missing-explicit-refuse', missing, tiny, records, 'refuse')
    rejection('missing-invalid-policy', missing, tiny, records, 'invalid')
    rejection('missing-empty-policy', missing, tiny, records, '')
    folder = WORK / 'world-directory'; folder.mkdir(exist_ok=True)
    rejection('world-path-directory', folder, tiny, records, 'create')
    for name, data in malformed_cases(identity, count):
        path = WORK / 'corrupt.nbt'; path.write_bytes(data)
        rejection(name, path, tiny, records, 'create')
        require(path.read_bytes() == data, 'startup rejection altered corrupt file: ' + name)
    checks.append('actual startup processes reject missing/refused/invalid configuration, malformed exact envelope, malformed inner World, truncation, trailing data, file bound and exhausted peer IDs before any listener')

    official_world = canonical_expected(W.empty_world(registry_identity(OFFICIAL)[1], official_identity))
    path = WORK / 'registry-bound.nbt'; path.write_bytes(envelope(official_world, official_identity, 0))
    sibling = WORK / 'official-sibling.tsv'
    sibling.write_text(OFFICIAL.read_text().replace('minecraft:air\t', 'fixture:air\t', 1))
    require(registry_identity(sibling)[0] != official_identity
            and registry_identity(sibling)[1] == registry_identity(OFFICIAL)[1], 'sibling fixture must have same count but different digest')
    rejection('official-same-count-sibling-registry', path, sibling, records)
    broken = WORK / 'corrupt-registry.tsv'; broken.write_text(HEADER + '\nnot-a-row\n')
    rejection('corrupt-registry-input', path, broken, records)
    checks.append('full official-registry same-state-count metadata substitution and corrupt registry input refuse startup')


def peer_fixtures(tiny, identity, count, saves, checks, metrics):
    scenarios = [('envelope-dominates', 100, None, None, 101),
                 ('pending-dominates', 3, 105, None, 106),
                 ('event-dominates', 7, None, 109, 110)]
    results = []
    for name, highwater, pending_peer, event_peer, expected in scenarios:
        model = W.empty_world(count, identity)
        if pending_peer is not None:
            model['pending'] = [{'stamp': (1, pending_peer, 8), 'mutation': {'kind': 2, 'day_time': 90}}]
        if event_peer is not None:
            model['events'] = [{'stamp': (0, event_peer, 9), 'kind': 1, 'error': {'kind': 0}}]
        canonical = canonical_expected(model)
        # Both compound schemas accept arbitrary member order; saves canonicalize.
        inner = N.parse(canonical)
        permuted_world = N.encode_root(N.RootTag(inner.name, N.Value(10, tuple(reversed(inner.value.payload)))))
        outer = envelope_root(permuted_world, identity, highwater)
        data = N.encode_root(N.RootTag(outer.name, N.Value(10, tuple(reversed(outer.value.payload)))))
        require(validate_save(data, count, identity)[2] == expected, 'independent next-peer fixture')
        path = WORK / (name + '.nbt'); path.write_bytes(data)
        runtime = Runtime(path, tiny)
        try:
            actor, ping = runtime.client()
            require(ping['peer'] == expected, 'loaded max peer policy: ' + name)
            require(actor.call('world.clock') == clock(model), 'fixture clock load')
            saved(actor, path, model, expected, saves, name)
            results.append({'case': name, 'envelope_highwater': highwater,
                            'pending_peer': pending_peer, 'event_peer': event_peer, 'actual_first_peer': ping['peer']})
        finally:
            runtime.stop()
    metrics['loaded_peer_fixtures'] = results
    checks.append('independent envelope/pending/event maxima drive first allocated peer; both compound member orders are accepted and canonicalized on actual save')


def run(command, timeout=180):
    result = subprocess.run([str(x) for x in command], cwd=ROOT, text=True, capture_output=True, timeout=timeout)
    record = {'command': [str(x) for x in command], 'exit_code': result.returncode,
              'stdout': result.stdout.strip(), 'stderr': result.stderr.strip()}
    require(result.returncode == 0, 'Bend build or finite persistence test failed: ' + json.dumps(record))
    return record


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--bend', type=Path, default=Path.home() / '.bend/bin/bend')
    parser.add_argument('--skip-build', action='store_true')
    parser.add_argument('--fixtures-only', action='store_true')
    args = parser.parse_args()
    started = time.monotonic(); oracle_hash = fingerprint(__file__)
    WORK.mkdir(parents=True, exist_ok=True)
    tiny = WORK / 'tiny-registry.tsv'; tiny.write_text(TINY_TSV)
    tiny_identity, tiny_count, tiny_meta = registry_identity(tiny)
    identity, count, official_meta = registry_identity(OFFICIAL)
    corruptions = malformed_cases(tiny_identity, tiny_count)
    if args.fixtures_only:
        print(json.dumps({'corrupt_fixtures': len(corruptions), 'tiny_identity': tiny_identity,
                          'official_identity': identity, 'official_states': count}, indent=2))
        return 0
    commands = []
    if not args.skip_build:
        for source, binary in [('persistence_server.bend', SERVER), ('mcp.bend', BRIDGE), ('tests/persistence.bend', TESTS)]:
            commands.append(run([args.bend, source, '-o', binary]))
    source_at_start = {name: fingerprint(ROOT / name) for name in SOURCE_FILES}
    binaries_at_start = {name: fingerprint(path) for name, path in
                         [('server', SERVER), ('mcp', BRIDGE), ('tests', TESTS)]}
    commands.append(run([TESTS, '--threads', '1', '--gpu', 'off']))
    require(commands[-1]['stdout'] == 'regressions\tpass', 'native persistence builtins did not pass')
    commands.append(run([TESTS, '--threads', '1', '--gpu', 'off', 'outcome']))
    unsynced = json.loads(commands[-1]['stdout'])
    require(unsynced == {'status': 'published_unsynced', 'published': True, 'durable': False,
                         'code': 5, 'message': 'directory sync fixture', 'bytes': 123, 'peer_highwater': 7},
            'finite PublishedUnsynced response semantics differ')
    checks, saves, records, metrics = [], [], [], {}
    live_roundtrip(identity, count, saves, checks, metrics, records)
    startup_tests(tiny, tiny_identity, tiny_count, identity, records, checks)
    peer_fixtures(tiny, tiny_identity, tiny_count, saves, checks, metrics)
    all_clients = [client for runtime in Runtime.observed for client in runtime.clients]
    metrics.update(native_ready_servers=len(Runtime.observed), native_mcp_processes=len(all_clients),
                   stdio_requests=sum(client.requests for client in all_clients),
                   stdio_responses=sum(client.responses for client in all_clients),
                   stdio_notifications=sum(client.notifications for client in all_clients))
    checks.append('finite native PublishedUnsynced response retains published=true/durable=false and OS code/message; no injected directory-sync failure claimed')
    require(oracle_hash == fingerprint(__file__), 'test runner changed during native execution')
    require(official_meta['source_sha256'] == fingerprint(OFFICIAL), 'official registry changed during integration execution')
    require(source_at_start == {name: fingerprint(ROOT / name) for name in SOURCE_FILES},
            'persistence implementation or harness changed during native execution')
    require(binaries_at_start == {name: fingerprint(path) for name, path in
                                 [('server', SERVER), ('mcp', BRIDGE), ('tests', TESTS)]},
            'native binary changed during integration execution')
    report = {'schema_version': 1, 'status': 'passed', 'kind': 'actual_native_persistence_mcp_tcp_integration',
              'recorded_at_utc': datetime.now(timezone.utc).isoformat(),
              'command': 'python3 tools/test_persistence.py' + (' --skip-build' if args.skip_build else ''),
              'confidence': 'high for the recorded fixture, process-crash, startup and OS-error observations',
              'checks': checks, 'save_observations': saves, 'startup_rejections': records,
              'startup_rejection_count': len(records), 'malformed_nbt_fixture_count': len(corruptions),
              'actual_server_sigkill_cases': 2, 'actual_save_os_failures': 1,
              'finite_published_unsynced_result': unsynced, 'metrics': metrics,
              'registry': {'official': official_meta, 'tiny_fixture': tiny_meta},
              'fixture_corpus_sha256': sha(b''.join(name.encode() + b'\0' + data for name, data in corruptions)),
              'resolved_resource_regression': {
                  'case': 'world-byte-limit',
                  'input_sha256': sha(dict(corruptions)['world-byte-limit']),
                  'prior_behavior': 'Outer NBT allowed a 16 MiB+1 ByteArray and allocated its payload before the inner World byte policy rejected it.',
                  'prior_measured_seconds': 30.783, 'prior_peak_child_rss_bytes': 1612824576,
                  'prior_exit_code': 1, 'prior_stdout': '',
                  'prior_diagnostic': 'world startup refused: NBT input byte limit exceeded',
                  'prior_provenance_limit': 'The bounded old-binary probe did not capture its binary hash; final source/binary hashes below describe the corrected full run only.',
                  'resolution': 'Apply the existing inner World byte cap to the outer NBT array element count, rejecting the declared oversized payload before allocation.',
                  'corrected_bounded_probe': {
                      'seconds': 15.366, 'exit_code': 1, 'stdout': '',
                      'diagnostic': 'world startup refused: negative or excessive NBT array length',
                      'peak_child_rss_bytes': 807534592,
                      'source_sha256': '1561a863a74fdfc676b8ba4bbb5eddd206823f7363bf05c8a50ddffbbc30a4af',
                      'binary_sha256': '7389194e6d65eac9f62640ba5b72bcfc6dd6534001da4182c03aa23c8081ffdb',
                      'input_sha256': '4d0d559d18651e428609284a5e9ed73505193a6943ea12af788355a0094fb0e7',
                      'resource_boundary': 'The bounded whole-file reader still creates the raw byte list before NBT header parsing. This is not a streaming file decoder.',
                  },
                  'corrected_observation': next(record for record in records if record['case'] == 'world-byte-limit'),
              },
              'oracle_sha256': oracle_hash, 'source_sha256': source_at_start,
              'binary_sha256': {'server': fingerprint(SERVER), 'mcp': fingerprint(BRIDGE), 'tests': fingerprint(TESTS)},
              'compiler_sha256': fingerprint(args.bend), 'commands': commands,
              'elapsed_seconds': round(time.monotonic() - started, 3),
              'limits': [
                  'Current Core.World snapshot and custom save envelope; no vanilla Minecraft save-format or gameplay parity claim.',
                  'SIGKILL occurs after acknowledged durable publication; publication-stage interruption cases are separately recorded in evidence/atomic-file.json.',
                  'No simulated power loss, automatic orphan recovery, injected directory-sync OS failure or save checksum established.',
                  'Python supplies independent fixtures and process/protocol orchestration only; actual mutation, codec, atomic publication and reload execute in native Bend.',
                  'Effectful process lifetime and OS durability adapters are outside the pure kernel proof boundary.',
              ]}
    (ROOT / 'evidence/persistence-integration.json').write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps({'status': report['status'], 'checks': len(checks), 'actual_saves': len(saves),
                      'startup_rejections': len(records), 'actual_server_sigkills': 2,
                      'elapsed_seconds': report['elapsed_seconds']}, indent=2))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
