#!/usr/bin/env python3
"""Production block-inside callbacks and stationary queries against pinned Java.

Python assembles explicit world fixtures and compares raw observed words. Every
callback, registry decode, ordered query and stationary scan executes in Bend.
"""
from __future__ import annotations

import argparse
import collections
import copy
import hashlib
import json
import os
from pathlib import Path
import signal
import struct
import subprocess
import time

import reference_player_block_inside_stuck_probe as R
import reference_player_motion_current_probe as MC
from reference_inventory import canonical, fingerprint, write_json
from test_player_look import imports, verify_build
from test_persistence import registry_identity
import test_nbt as N
import test_world_codec as WC

ROOT = Path(__file__).resolve().parents[1]
BEND = Path('/Users/chuah/.bend/bin/bend')
ENTRY = ROOT / 'tests/player_block_inside_stuck.bend'
BINARY = ROOT / 'build/player-block-inside-stuck-tests'
REFERENCE = ROOT / 'reference/player_block_inside_stuck.json'
REFERENCE_EVIDENCE = ROOT / 'evidence/player-block-inside-stuck-reference.json'
REGISTRY = ROOT / 'generated/reference_blocks.tsv'
MOTION_REFERENCE = ROOT / 'reference/player_motion_current.json'
MOTION_REFERENCE_EVIDENCE = ROOT / 'evidence/player-motion-current-reference.json'
BUILD_EVIDENCE = ROOT / 'evidence/player-block-inside-stuck-build.json'
NATIVE_EVIDENCE = ROOT / 'evidence/player-block-inside-stuck-native.json'
ZERO = '0000000000000000'
DIMENSION = 'minecraft:overworld'


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def bits(value):
    return struct.pack('>d', value).hex()


def words(raw):
    return [int(raw[:8], 16), int(raw[8:], 16)]


def vector(raws):
    return [word for raw in raws for word in words(raw)]


def word(value):
    return value & 0xffffffff


def text_words(values):
    return ','.join(map(str, values))


def receiver(snapshot):
    impact = snapshot.get('impulse_position', [])
    return '\t'.join([text_words(vector(snapshot['stuck_multiplier'])),
                      text_words(words(snapshot['fall_distance'])),
                      str(snapshot.get('impulse_grace', 0)),
                      text_words(vector(impact)) if impact else 'none'])


def state_ids():
    rows = {}
    for line in REGISTRY.read_text().splitlines()[1:]:
        protocol, name, first, count, default, properties = line.split('\t')
        rows[name] = {'protocol': int(protocol), 'first': int(first), 'count': int(count),
                      'default': int(default), 'properties': json.loads(properties)}
    return rows


def state_id(value, rows):
    row = rows[value['identifier']]
    if value['identifier'] == 'minecraft:sweet_berry_bush':
        require(row['properties'] == [{'name': 'age', 'values': ['0', '1', '2', '3']}],
                'berry registry property domain changed')
        return row['first'] + value['age']
    require(not row['properties'], 'unexpected callback properties')
    return row['default']


def reference_data():
    data = json.loads(REFERENCE.read_text())
    evidence = json.loads(REFERENCE_EVIDENCE.read_text())
    require(data['schema_version'] == 1 and evidence['status'] == 'passed', 'reference schema/status')
    require(fingerprint(REFERENCE) == evidence['reference'], 'reference bytes changed')
    require(data['probe_java_sources_sha256'] == {
        name: hashlib.sha256(source.encode()).hexdigest() for name, source in R.SOURCES.items()
    }, 'reference Java producer changed')
    observed = []
    for run in evidence['runs']:
        path = R.RAW / run['observations']['file']
        require(fingerprint(path) == run['observations'], 'original Java capture changed')
        records = [json.loads(line) for line in path.read_text().splitlines()]
        R.validate(data, records)
        observed.append(records)
    require(len(observed) == 2 and observed[0] == observed[1], 'independent Java captures differ')
    return data, observed[0], evidence


def reference_faults(data, observed):
    rejected = []
    for name in ['checksum', 'expected-unsealed', 'expected-resealed', 'input-resealed']:
        bad = copy.deepcopy(data)
        if name == 'checksum':
            bad['cases_sha256'] = '0' * 64
        elif name.startswith('expected'):
            bad['cases'][0]['expected']['final']['stuck_multiplier'][0] = bits(123.)
        else:
            bad['cases'][0]['input']['weaving'] = not bad['cases'][0]['input']['weaving']
        if name.endswith('resealed'):
            bad['cases_sha256'] = R.sha(bad['cases'])
        try:
            R.validate(bad, observed)
        except AssertionError:
            rejected.append(name)
        else:
            raise AssertionError('corrupt reference accepted: ' + name)
    return rejected


def motion_reference_data():
    data = json.loads(MOTION_REFERENCE.read_text())
    evidence = json.loads(MOTION_REFERENCE_EVIDENCE.read_text())
    require(data['schema_version'] == 1 and evidence['status'] == 'passed', 'motion reference schema/status')
    require(fingerprint(MOTION_REFERENCE) == evidence['reference'], 'motion reference bytes changed')
    sources = {'ReferenceMovementProbe': MC.MOVEMENT_SOURCE,
               'ReferenceDirectMovementProbe': MC.DIRECT_SOURCE,
               'ReferencePlayerMotionCurrentProbe': MC.SOURCE}
    require(data['probe_java_sources_sha256'] == {
        name: hashlib.sha256(source.encode()).hexdigest() for name, source in sources.items()
    }, 'motion reference Java producer changed')
    observed = []
    for run in evidence['runs']:
        path = MC.RAW / run['observations']['file']
        require(fingerprint(path) == run['observations'], 'original motion Java capture changed')
        records = [json.loads(line) for line in path.read_text().splitlines()]
        MC.validate(data, records)
        observed.append(records)
    require(len(observed) == 2 and observed[0] == observed[1], 'independent motion Java captures differ')
    rejected = []
    for name in ['checksum', 'actual-input-resealed', 'entry-multiplier-resealed']:
        bad = copy.deepcopy(data)
        if name == 'checksum':
            bad['cases_sha256'] = '0' * 64
        else:
            field = (bad['cases'][0]['observation']['actual_input']['stuck_multiplier']
                     if name == 'actual-input-resealed' else
                     bad['cases'][0]['observation']['stuck_phase']['entry_multiplier'])
            field[0] = bits(123.)
            bad['cases_sha256'] = MC.sha(bad['cases'])
        try:
            MC.validate(bad, observed[0])
        except AssertionError:
            rejected.append(name)
        else:
            raise AssertionError('corrupt motion reference accepted: ' + name)
    return data, rejected


def world_bytes(reads, writes, rows, count, identity):
    """Explicitly loaded Core sections; absent Java fixture cells are known air."""
    model = WC.empty_world(count, identity)
    model.update(tick=42, day_time=1000, paused=False, daylight=False, revision=13)
    sections = {}
    for value in [*reads, *writes]:
        x, y, z = value['position']
        key = DIMENSION + '/' + '/'.join(str(word(c >> 4)) for c in (x, y, z))
        cells = sections.setdefault(key, [rows['minecraft:air']['default']] * 4096)
        cells[(x & 15) + ((z & 15) << 4) + ((y & 15) << 8)] = state_id(value.get('state', value), rows)
    # Known hash-collision keys and unrelated cells exercise the complete owner.
    for key, fill in zip(WC.COLLISION_KEYS, [1, 10], strict=True):
        sections[key] = [fill] * 4096
    model['sections'] = [{'key': key, 'cells': tuple(cells)} for key, cells in sorted(sections.items())]
    model['pending'] = [
        {'stamp': (1000, 7, 1), 'mutation': {'kind': 0, 'dimension': DIMENSION, 'x': 160, 'y': 0, 'z': 0, 'state': 1}},
        {'stamp': (1001, 3, 100), 'mutation': {'kind': 2, 'day_time': 999}},
        {'stamp': (1001, 3, 101), 'mutation': {'kind': 3, 'enabled': True}},
    ]
    model['events'] = [
        {'stamp': (41, 9, 5), 'kind': 1, 'error': {'kind': 3, 'key': DIMENSION + '/10/0/0'}},
        {'stamp': (40, 1, 3), 'kind': 0, 'revision': 12},
    ]
    raw = N.encode_root(WC.snapshot_root(model))
    decoded = WC.validate(N.parse(raw), count, identity)
    require(raw == N.encode_root(WC.snapshot_root(decoded)), 'canonical independent Core fixture')
    return raw


class Corpus:
    def __init__(self, folder, rows, count, identity):
        self.folder, self.rows, self.count, self.identity = folder, rows, count, identity
        self.requests, self.expected, self.manifest = [], [], []
        self.worlds, self.categories = {}, collections.Counter()
        self.checking = False
        self.authority_checks = 0

    def add(self, label, category, args, answers):
        ident = 'c' + str(len(self.requests))
        self.requests.append('\t'.join(map(str, [ident, *args])))
        self.expected.extend(ident + '\t' + answer for answer in answers)
        self.manifest.append({'id': ident, 'label': label, 'category': category, 'responses': len(answers)})
        self.categories[category] += 1
        return ident

    def load(self, label, reads=(), writes=()):
        raw = world_bytes(reads, writes, self.rows, self.count, self.identity)
        sha = hashlib.sha256(raw).hexdigest()
        if sha not in self.worlds:
            path = self.folder / ('world-' + str(len(self.worlds)) + '.nbt')
            path.write_bytes(raw)
            self.worlds[sha] = path
        self.add(label, 'explicit-world-load', ['world', self.worlds[sha]], ['ok\tworld'])
        self.checking = False
        return self.worlds[sha]

    def seed(self, label, snapshot):
        impact = snapshot.get('impulse_position', [])
        fields = [*vector(snapshot['stuck_multiplier']), *words(snapshot['fall_distance']),
                  snapshot.get('impulse_grace', 0), int(bool(impact)), *vector(impact or [ZERO] * 3)]
        self.add(label, 'receiver-history-impulse-seed', ['seed', *fields], ['ok\tseed'])
        self.checking = False

    def context(self, label, incoming, level=0, known=None, old=None, alive=True):
        kind = {'player': 0, 'fox': 1, 'bee': 1, 'living': 2, 'nonliving': 3}[incoming['receiver']]
        flags = (kind | (int(incoming['flying']) << 2) | (int(incoming['weaving']) << 3)
                 | (int(incoming['removed']) << 4) | (int(incoming['no_physics']) << 5)
                 | (int(not alive) << 6))
        fields = [flags, level, *vector(incoming['position']),
                  *vector(known or [ZERO] * 3), *vector(old or incoming['position'])]
        self.add(label, 'receiver-world-context', ['context', *fields], ['ok\tcontext'])

    def checkpoint(self, label):
        self.add(label, 'complete-owner-checkpoint', ['checkpoint'], ['ok\tcheckpoint'])
        self.checking = True

    def outcome(self, label, category, args, snapshot, reset=False, reads=(), error=None):
        if error is None:
            read_text = ''.join(text_words([*(word(c) for c in value['position']), state_id(value['state'], self.rows)]) + ';' for value in reads)
            answer = 'ok\t' + receiver(snapshot) + '\t' + str(int(reset)) + '\t' + read_text
        else:
            answer = 'error\t' + error + '\t' + receiver(snapshot)
        answers = [answer]
        if error is None:
            answers.append('authority\t1')
            self.authority_checks += 1
        answers.extend(['owners\t1'] if self.checking else [])
        return self.add(label, category, args, answers)

    def query(self, label, category, contacts, snapshot, reset=False, reads=(), error=None, budget=4096, malformed=0, dimension=DIMENSION):
        fields = [word(c) if isinstance(c, int) else c for value in contacts for c in value]
        return self.outcome(label, category, ['ordered', dimension, budget, malformed, *fields], snapshot, reset, reads, error)

    def stationary(self, label, category, box, snapshot, reset=False, reads=(), error=None, budget=4096, dimension=DIMENSION):
        return self.outcome(label, category, ['stationary', dimension, budget, *vector(box)], snapshot, reset, reads, error)

    def raw_cell(self, label, position, state):
        self.add(label, 'forged-raw-world-cell', ['raw-cell', *(word(c) for c in position), state], ['ok\tforge'])
        self.checking = False

    def save(self):
        self.expected.append('final\towners\t1')
        requests = self.folder / 'requests.tsv'
        expected = self.folder / 'expected.tsv'
        requests.write_text('\n'.join(self.requests) + '\n')
        expected.write_text('\n'.join(self.expected) + '\n')
        write_json(self.folder / 'case-manifest.json', self.manifest)
        return {'operations': len(self.requests), 'responses': len(self.expected),
                'authority_consistency_checks': self.authority_checks,
                'categories': dict(self.categories), 'world_fixture_count': len(self.worlds),
                'requests': fingerprint(requests), 'expected': fingerprint(expected),
                'case_manifest': fingerprint(self.folder / 'case-manifest.json'),
                'worlds': [fingerprint(p) for p in self.worlds.values()]}


def prepare(folder, data, motion, count, identity):
    rows = state_ids()
    corpus = Corpus(folder, rows, count, identity)
    initial_world = corpus.load('initial-full-owner-world')
    callback_count = stationary_count = ordered_count = read_count = 0
    for lane in ['primary', 'ordered']:
        for case in data['cases']:
            incoming = case['input']
            if lane == 'ordered' and not any(s['operation'] == 'stationary_dispatch' for s in incoming['steps']):
                continue
            corpus.seed(case['id'] + ':' + lane, case['expected']['initial'])
            corpus.context(case['id'], incoming)
            for index, (step, actual) in enumerate(zip(incoming['steps'], case['expected']['steps'], strict=True)):
                label = case['id'] + ':' + lane + ':' + str(index)
                reset = actual.get('impulse_reset_calls', 0) > 0
                if step['operation'] == 'callback':
                    require(lane == 'primary', 'direct callbacks repeated in ordered lane')
                    require(actual['entity_inside_shape']['identity_block'], 'callback inside shape boundary')
                    corpus.outcome(label, 'actual-original-callback', ['callback', state_id(step['block'], rows)], actual['after'], reset)
                    callback_count += 1
                else:
                    require(all(s['shape']['identity_block'] for s in actual['entity_inside_shapes']), 'stationary inside shape boundary')
                    corpus.load(label, actual['inside_reads'], step['world_blocks'])
                    contacts = [(*r['position'], 'hit') for r in actual['inside_reads']]
                    if lane == 'primary':
                        corpus.stationary(label, 'actual-original-stationary-dispatch', actual['before']['body']['box'], actual['after'], reset, actual['inside_reads'])
                        stationary_count += 1
                    else:
                        corpus.query(label, 'actual-ordered-world-contacts', contacts, actual['after'], reset, actual['inside_reads'])
                        ordered_count += 1
                    read_count += len(actual['inside_reads'])
    base = next(c for c in data['cases'] if c['input']['receiver'] == 'player' and not c['input']['flying'] and not c['input']['weaving'] and c['input']['impulse'] == 'ready' and c['input']['steps'][0]['operation'] == 'callback' and c['input']['steps'][0]['block']['identifier'] == 'minecraft:cobweb')
    before, after = base['expected']['initial'], base['expected']['steps'][0]['after']
    web = {'identifier': 'minecraft:cobweb', 'position': [0, 1, 0]}
    berry = {'identifier': 'minecraft:sweet_berry_bush', 'position': [1, 1, 0], 'age': 3}
    web_read = {'position': web['position'], 'state': {'identifier': web['identifier']}}
    hits = [(*web['position'], 'hit'), (*berry['position'], 'hit')]
    recovery_count = failure_count = 0

    def reset(label, level=0, known=None, old=None):
        corpus.load(label, writes=[web, berry])
        corpus.seed(label, before)
        corpus.context(label, base['input'], level=level, known=known, old=old)

    def recovery(label):
        nonlocal recovery_count
        corpus.context(label + ':ordinary-recovery', base['input'])
        corpus.query(label + ':recovery', 'same-owner-recovery', [(*web['position'], 'hit')], after,
                     reset=True, reads=[web_read])
        recovery_count += 1

    for label, contacts, budget, malformed, error in [
        ('zero-budget', hits, 0, 0, 'query-budget'),
        ('budget-after-web', hits, 1, 0, 'query-budget'),
        ('unknown-intersection', [(0, 1, 0, 'unknown')], 4096, 0, 'unknown-intersection'),
        ('intersection-after-web', [hits[0], (1, 1, 0, 'unknown')], 4096, 0, 'unknown-intersection'),
        ('missing-section', [(16, 1, 0, 'hit')], 4096, 0, 'world:missing-section:' + DIMENSION + '/1/0/0'),
        ('missing-after-web', [hits[0], (16, 1, 0, 'hit')], 4096, 0, 'world:missing-section:' + DIMENSION + '/1/0/0'),
        ('noncanonical-request', hits, 4096, 1, 'noncanonical-request'),
    ]:
        reset(label)
        corpus.checkpoint(label)
        corpus.query(label, 'query-refusal-and-atomic-rollback', contacts, before, error=error, budget=budget, malformed=malformed)
        recovery(label)
        failure_count += 1

    for invalid, error in [(2, 'unsupported-callback:minecraft:granite:2'),
                           (count, 'registry:invalid-state:' + str(count)),
                           (0xffffffff, 'registry:invalid-state:4294967295')]:
        for partial in [False, True]:
            label = 'raw-state-' + str(invalid) + '-' + str(partial)
            reset(label)
            corpus.raw_cell(label, berry['position'], invalid)
            corpus.checkpoint(label)
            corpus.query(label, 'raw-registry-id-refusal-and-retention', hits if partial else [hits[1]], before, error=error)
            # Restore only the raw cell. A second query uses the exact same owners.
            corpus.raw_cell(label + ':restore', berry['position'], state_id(berry, rows))
            corpus.checkpoint(label + ':restored')
            recovery(label)
            failure_count += 1

    for level in [2, 6]:
        for partial in [False, True]:
            label = 'server-berry-' + str(level) + '-' + str(partial)
            reset(label, level=level, known=[bits(.01), ZERO, ZERO], old=[bits(0.), bits(1.), bits(.5)])
            corpus.checkpoint(label)
            corpus.query(label, 'server-damage-boundary-rollback', hits if partial else [hits[1]], before, error='server-berry-damage-required')
            recovery(label)
            failure_count += 1

    for bad in ['7ff0000000000000', 'fff0000000000000', '7ff8000000000123']:
        reset('nonfinite-server', level=6, known=[bad, ZERO, ZERO])
        corpus.checkpoint('nonfinite-server')
        corpus.query('nonfinite-server', 'server-movement-observation-refusal', hits, before, error='invalid-movement-observation')
        recovery('nonfinite-server')
        failure_count += 1

    normal_box = before['body']['box']
    for label, box, budget, error in [
        ('nan-box', ['7ff8000000000123', *normal_box[1:]], 4096, 'invalid-box'),
        ('infinite-box', ['7ff0000000000000', *normal_box[1:]], 4096, 'invalid-box'),
        ('reversed-box', [bits(2.), *normal_box[1:]], 4096, 'invalid-box'),
        ('outside-i32', [bits(2147483648.), *normal_box[1:3], bits(2147483649.), *normal_box[4:]], 4096, 'invalid-coordinate'),
        ('stationary-zero-budget', normal_box, 0, 'query-budget'),
        ('stationary-partial-budget', normal_box, 1, 'query-budget'),
    ]:
        reset(label)
        corpus.checkpoint(label)
        corpus.stationary(label, 'stationary-refusal-and-rollback', box, before, error=error, budget=budget)
        recovery(label)
        failure_count += 1

    for age in ['missing', 'duplicate', 'extra', '4', '-1', '01', 'garbage']:
        reset('berry-age-' + age)
        corpus.checkpoint('berry-age-' + age)
        corpus.outcome('berry-age-' + age, 'callback-property-refusal', ['raw-callback', berry['identifier'], age], before, error='invalid-berry-age')
        recovery('berry-age-' + age)
        failure_count += 1

    reset('explicit-no-intersection')
    corpus.checkpoint('explicit-no-intersection')
    corpus.query('explicit-no-intersection', 'intersection-skip-without-world-read', [(16, 1, 0, 'miss')], before)
    recovery('explicit-no-intersection')

    collision_reads = []
    for key, identifier in zip(WC.COLLISION_KEYS, ['minecraft:stone', 'minecraft:dirt'], strict=True):
        dimension, *section_coordinates = key.split('/')
        require(dimension == DIMENSION and len(section_coordinates) == 3, 'collision section key shape')
        coordinates = [word(int(value) << 4) for value in section_coordinates]
        require(all(value <= 0x7fffffff for value in coordinates), 'collision fixture origin outside signed I32')
        collision_reads.append({'position': coordinates, 'state': {'identifier': identifier}})
    require(WC.fnv(WC.COLLISION_KEYS[0]) == WC.fnv(WC.COLLISION_KEYS[1]), 'fixture keys no longer collide')
    for order in [[0, 1], [1, 0], [0, 1, 0]]:
        label = 'collision-bucket-order-' + ''.join(map(str, order))
        reset(label)
        corpus.checkpoint(label)
        reads = [collision_reads[index] for index in order]
        corpus.query(label, 'queried-hash-collision-bucket-retention',
                     [(*value['position'], 'hit') for value in reads], before, reads=reads)
    reset('collision-bucket-late-refusal')
    corpus.raw_cell('collision-bucket-late-refusal', berry['position'], 2)
    corpus.checkpoint('collision-bucket-late-refusal')
    corpus.query('collision-bucket-late-refusal', 'queried-bucket-and-candidate-atomic-rollback',
                 [(*collision_reads[1]['position'], 'hit'), hits[0],
                  (*collision_reads[0]['position'], 'hit'), hits[1]], before,
                 error='unsupported-callback:minecraft:granite:2')
    corpus.raw_cell('collision-bucket-late-refusal:restore', berry['position'], state_id(berry, rows))
    corpus.checkpoint('collision-bucket-late-refusal:restored')
    recovery('collision-bucket-late-refusal')
    failure_count += 1

    consumption = {}
    for case in motion['cases']:
        multiplier = case['observation']['actual_input']['stuck_multiplier']
        key = tuple(multiplier)
        result = case['observation']['stuck_phase']['entry_multiplier']
        if key in consumption:
            require(consumption[key] == result, 'actual Java stuck consumption disagrees for identical receiver')
        consumption[key] = result
    corpus.load('travel-consumption-owner')
    for multiplier, expected in consumption.items():
        prior = copy.deepcopy(before)
        prior['stuck_multiplier'] = list(multiplier)
        # Both impulse grace branches have the same already observed M phase;
        # this receiver API must preserve the complete impulse/history fields.
        for grace in [0, 7]:
            prior['impulse_grace'] = grace
            corpus.seed('travel-consumption', prior)
            wanted = copy.deepcopy(prior)
            wanted['stuck_multiplier'] = expected
            corpus.outcome('travel-consumption', 'actual-travel-multiplier-consumption', ['travel-succeeded'], wanted)
    reset('final-owner')
    corpus.checkpoint('final-owner')
    recovery('final-owner')
    # The same held owner remains valid after ordinary success and a second check.
    corpus.add('final-exact-owner-recheck', 'complete-owner-recheck', ['check'], ['owners\t1'])
    summary = corpus.save()
    summary.update(actual_callback_comparisons=callback_count, actual_stationary_comparisons=stationary_count,
                   actual_ordered_contact_comparisons=ordered_count, actual_ordered_reads=read_count,
                   checked_refusals=failure_count, same_owner_recoveries=recovery_count,
                   actual_consumption_vectors=len(consumption), actual_consumption_comparisons=2 * len(consumption),
                   queried_collision_bucket_sequences=4,
                   owner_scope='All raw Core section cells/trie/clock/queues/events and all Registry capacity slots/names/counts, plus receiver/fall history/impulse on refusal and held State versus Observation on every success; canonical State tails only. Nonliving Java receivers have no impulse service, so their inert test field is zero/None.')
    return corpus, initial_world, summary


def compare_output(actual, expected, requests):
    a, b = actual.splitlines(), expected.splitlines()
    require(len(a) == len(b), 'response count differs: ' + str((len(a), len(b))))
    by_id = {r.split('\t', 1)[0]: r for r in requests}
    for index, (observed, wanted) in enumerate(zip(a, b, strict=True)):
        if observed != wanted:
            ident = wanted.decode().split('\t', 1)[0]
            raise AssertionError('response ' + str(index) + ' request ' + by_id.get(ident, '<final>')[:350]
                                 + ' observed ' + repr(observed[:500]) + ' expected ' + repr(wanted[:500]))
    require(actual == expected, 'whole response bytes differ')


def comparison_faults(corpus):
    expected = ('\n'.join(corpus.expected) + '\n').encode()
    lines = expected.splitlines(keepends=True)
    rejected = []
    for label, malformed in [
        ('missing-row', b''.join(lines[:-1])), ('extra-row', expected + b'injected\n'),
        ('altered-row', b'injected\n' + b''.join(lines[1:])),
        ('reordered-row', b''.join([lines[1], lines[0], *lines[2:]])),
        ('missing-newline', expected[:-1]), ('crlf', expected.replace(b'\n', b'\r\n')),
        ('state-observation-disagreement', expected.replace(b'\tauthority\t1\n', b'\tauthority\t0\n', 1)),
    ]:
        try:
            compare_output(malformed, expected, corpus.requests)
        except AssertionError:
            rejected.append(label)
        else:
            raise AssertionError('malformed comparison accepted: ' + label)
    compare_output(expected, expected, corpus.requests)
    return rejected


def run(argv, folder, name, timeout):
    started = time.monotonic()
    child = subprocess.Popen([str(x) for x in argv], cwd=ROOT, stdout=subprocess.PIPE,
                             stderr=subprocess.PIPE, start_new_session=True)
    timed_out = False
    try:
        stdout, stderr = child.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        os.killpg(child.pid, signal.SIGKILL)
        stdout, stderr = child.communicate()
    (folder / (name + '.stdout')).write_bytes(stdout)
    (folder / (name + '.stderr')).write_bytes(stderr)
    probe_error = None
    absent = False
    for cleanup_poll in range(21):
        try:
            os.killpg(child.pid, 0)
        except ProcessLookupError:
            absent = True
        except PermissionError as error:
            # macOS can briefly retain a killed descendant as an exiting task,
            # or reject signal-zero after it has gone. Inspect exact membership
            # and allow at most one second for the exiting task to disappear.
            rows = subprocess.run(['/bin/ps', '-axo', 'pid=,pgid=,stat='], text=True,
                                  capture_output=True, check=True).stdout.splitlines()
            members = [line.strip() for line in rows if len(line.split()) >= 3 and int(line.split()[1]) == child.pid]
            absent = not members
            probe_error = {'type': type(error).__name__, 'errno': error.errno, 'group_members': members}
        else:
            if cleanup_poll == 0:
                os.killpg(child.pid, signal.SIGKILL)
        if absent:
            break
        if cleanup_poll < 20:
            time.sleep(.05)
    receipt = {'argv': [str(x) for x in argv], 'pid': child.pid, 'exit_code': child.returncode,
               'seconds': round(time.monotonic() - started, 6), 'timed_out': timed_out,
               'group_absent': absent, 'cleanup_poll_count': cleanup_poll + 1,
               'stdout': fingerprint(folder / (name + '.stdout')),
               'stderr': fingerprint(folder / (name + '.stderr'))}
    if probe_error is not None:
        receipt['group_probe_error'] = probe_error
    write_json(folder / (name + '.json'), receipt)
    require(not timed_out and child.returncode == 0 and absent, receipt)
    return stdout, receipt


def pins():
    result = imports([ENTRY])
    for path in [Path(__file__).resolve(), Path(R.__file__), Path(MC.__file__),
                 ROOT / 'tools/reference_movement_probe.py', ROOT / 'tools/reference_travel_probe.py',
                 REFERENCE, REFERENCE_EVIDENCE, MOTION_REFERENCE, MOTION_REFERENCE_EVIDENCE, REGISTRY]:
        result[str(path.relative_to(ROOT))] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


def retained_build():
    receipt = json.loads(BUILD_EVIDENCE.read_text())
    report_path = Path(receipt['folder']) / 'native-build.json'
    require(fingerprint(report_path) == receipt['build_report'], 'retained native report changed')
    report = json.loads(report_path.read_text())
    verify_build(report)
    require(fingerprint(BINARY)['sha256'] == report['binary_sha256'], 'published binary changed')
    require(report['retries'] == 0, 'build retried')
    return report, receipt['build_report']


def prior_failures():
    history = []
    base = ROOT / 'build/player-block-inside-stuck/native'
    for folder in sorted(base.iterdir()) if base.exists() else []:
        path = folder / 'failure.json'
        if not path.exists():
            continue
        failure = json.loads(path.read_text())
        item = {'folder': str(folder), 'failure': fingerprint(path),
                'error': failure['error'], 'target_executed': False}
        receipt = folder / 'build.json'
        if receipt.exists():
            item['build_receipt'] = json.loads(receipt.read_text())
        diagnosis = folder / 'diagnosis.json'
        if diagnosis.exists():
            item['diagnosis'] = json.loads(diagnosis.read_text())
        history.append(item)
    return history


def main():
    parser = argparse.ArgumentParser()
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--prepare-only', action='store_true')
    modes.add_argument('--build-only', action='store_true')
    modes.add_argument('--skip-build', action='store_true')
    args = parser.parse_args()
    data, observed, reference_evidence = reference_data()
    controls = reference_faults(data, observed)
    motion, motion_controls = motion_reference_data()
    identity, count, registry_info = registry_identity(REGISTRY)
    folder = ROOT / 'build/player-block-inside-stuck/native' / str(time.time_ns())
    folder.mkdir(parents=True, exist_ok=False)
    source_pins = pins()
    receipts = []
    try:
        corpus, world, summary = prepare(folder, data, motion, count, identity)
        comparator_controls = comparison_faults(corpus)
        require(source_pins == pins(), 'source/reference changed during preparation')
        common = {'pin': '26.3', 'folder': str(folder), 'sources_sha256': source_pins,
                  'reference': fingerprint(REFERENCE), 'reference_evidence': fingerprint(REFERENCE_EVIDENCE),
                  'motion_reference': fingerprint(MOTION_REFERENCE), 'motion_reference_evidence': fingerprint(MOTION_REFERENCE_EVIDENCE),
                  'registry': fingerprint(REGISTRY), 'registry_identity': identity, 'registry_info': registry_info,
                  'reference_corruptions_rejected': controls, 'comparison_corruptions_rejected': comparator_controls,
                  'motion_reference_corruptions_rejected': motion_controls,
                  'prior_failed_attempts': prior_failures(),
                  'corpus': summary}
        if args.prepare_only:
            evidence = {**common, 'status': 'prepared', 'native_execution': False}
            write_json(folder / 'prepared.json', evidence)
            print(json.dumps({'status': 'prepared', 'folder': str(folder), **{k: summary[k] for k in [
                'operations', 'responses', 'authority_consistency_checks', 'actual_callback_comparisons', 'actual_stationary_comparisons',
                'actual_ordered_contact_comparisons', 'checked_refusals', 'same_owner_recoveries',
                'actual_consumption_comparisons', 'queried_collision_bucket_sequences']}}))
            return
        if args.skip_build:
            build, build_fingerprint = retained_build()
        else:
            _, receipt = run(['python3', ROOT / 'tools/build_native.py', ENTRY, '-o', BINARY,
                              '--report', folder / 'native-build.json'], folder, 'build', 180)
            receipts.append(receipt)
            build = json.loads((folder / 'native-build.json').read_text())
            verify_build(build)
            require(build['retries'] == 0, 'build retried')
            build_fingerprint = fingerprint(folder / 'native-build.json')
        require(source_pins == pins(), 'source/reference changed during build')
        if not args.skip_build:
            build_evidence = {**common, 'status': 'build-passed', 'build_report': build_fingerprint,
                              'binary': fingerprint(BINARY), 'receipts': receipts}
            write_json(BUILD_EVIDENCE, build_evidence)
        if args.build_only:
            print(json.dumps({'status': 'build-passed', 'folder': str(folder)}))
            return
        stdout, receipt = run([BINARY, '--gpu', 'off', REGISTRY, world, folder / 'requests.tsv',
                               count, identity], folder, 'native', 120)
        receipts.append(receipt)
        compare_output(stdout, (folder / 'expected.tsv').read_bytes(), corpus.requests)
        # Deliberately wrong expected raw receiver words must fail even after
        # protocol construction; the comparator never reconstructs gameplay.
        wrong = (folder / 'expected.tsv').read_bytes().replace(b'\tok\t1070596096,0', b'\tok\t1079574528,0', 1)
        require(wrong != (folder / 'expected.tsv').read_bytes(), 'expected receiver corruption did not alter a comparison')
        try:
            compare_output(stdout, wrong, corpus.requests)
        except AssertionError:
            expected_rejected = True
        else:
            raise AssertionError('wrong expected receiver accepted')
        verify_build(build)
        require(source_pins == pins(), 'source/reference changed during native comparison')
        evidence = {**common, 'status': 'passed', 'build_report': build_fingerprint,
                    'binary': fingerprint(BINARY), 'receipts': receipts,
                    'expected_receiver_corruption_rejected': expected_rejected,
                    'scope': 'Actual production callback_checked, query, and stationary through persistent native State; exact Java multiplier/fall/impulse words and read order. Server berry damage is an explicit refused dependency; swept traversal and full tick are outside scope.'}
        write_json(NATIVE_EVIDENCE, evidence)
        print(json.dumps({'status': 'passed', 'folder': str(folder), **{k: summary[k] for k in [
            'actual_callback_comparisons', 'actual_stationary_comparisons', 'actual_ordered_contact_comparisons',
            'checked_refusals', 'same_owner_recoveries', 'actual_consumption_comparisons',
            'queried_collision_bucket_sequences']}}))
    except BaseException as error:
        for name in ['build', 'native']:
            receipt_path = folder / (name + '.json')
            if receipt_path.exists():
                receipt = json.loads(receipt_path.read_text())
                if not any(previous['pid'] == receipt['pid'] for previous in receipts):
                    receipts.append(receipt)
        write_json(folder / 'failure.json', {'status': 'failed', 'error': repr(error),
                                           'sources_sha256': source_pins, 'receipts': receipts})
        raise


if __name__ == '__main__':
    main()
