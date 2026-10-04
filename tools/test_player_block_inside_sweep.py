#!/usr/bin/env python3
"""Actual production moving block traversal against independent pinned Java.

Python assembles explicit owned-world fixtures and projects recorded expectations.
All traversal, packing, deduplication, registry reads and callbacks execute in Bend.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import time

import reference_player_block_inside_sweep_probe as R
import test_player_block_inside_stuck as T
from reference_inventory import fingerprint, write_json

ROOT = T.ROOT
ENTRY = ROOT / 'tests/player_block_inside_sweep.bend'
BINARY = ROOT / 'build/player-block-inside-sweep-tests'
REFERENCE = ROOT / 'reference/player_block_inside_sweep.json'
REFERENCE_EVIDENCE = ROOT / 'evidence/player-block-inside-sweep-reference.json'
BUILD_EVIDENCE = ROOT / 'evidence/player-block-inside-sweep-build.json'
NATIVE_EVIDENCE = ROOT / 'evidence/player-block-inside-sweep-native.json'
BASE = ROOT / 'build/player-block-inside-sweep/native'
ZERO = T.ZERO
DIMENSION = T.DIMENSION


def reference_data():
    data = json.loads(REFERENCE.read_text())
    evidence = json.loads(REFERENCE_EVIDENCE.read_text())
    T.require(data['schema_version'] == 1 and evidence['status'] == 'passed', 'reference schema/status')
    T.require(fingerprint(REFERENCE) == evidence['reference'], 'reference bytes changed')
    T.require(fingerprint(Path(R.__file__)) == evidence['generator'], 'reference extractor changed')
    T.require(data['probe_java_sources_sha256'] == {
        name: hashlib.sha256(source.encode()).hexdigest() for name, source in R.SOURCES.items()
    }, 'original Java observer sources changed')
    captures = []
    for run in evidence['runs']:
        path = R.RAW / run['observations']['file']
        T.require(fingerprint(path) == run['observations'], 'independent original capture changed')
        records = [json.loads(line) for line in path.read_text().splitlines()]
        R.validate(data, records)
        captures.append(records)
    T.require(len(captures) == 2 and captures[0] == captures[1], 'independent original captures differ')
    return data, captures[0], evidence


def movement_fields(movements):
    return [word for movement in movements for word in [
        int(bool(movement['axis_original'])), *T.vector(movement['from']),
        *T.vector(movement['to']), *T.vector(movement['axis_original'] or [ZERO] * 3)]]


def cell_text(values, rows, collector=False):
    return ''.join(T.text_words([*(T.word(c) for c in value['position']),
                               T.state_id(value['state'], rows),
                               *([T.word(value['collector_step'])] if collector else [])]) + ';'
                   for value in values)


class Corpus(T.Corpus):
    def __init__(self, *args):
        super().__init__(*args)
        self.trace_reads = self.trace_callbacks = 0

    def inspect(self, label, snapshot):
        self.add(label, 'held-receiver-before-operation', ['inspect'], ['state\t' + T.receiver(snapshot)])

    def sweep(self, label, category, movements, before, after, actual=None, *,
              traversal=16384, reads=16384, malformed=0, dimension=DIMENSION,
              width=None, height=None, error=None):
        body = before['body']
        fields = ['sweep', dimension,
                  width if width is not None else int(body['width_f32_bits'], 16),
                  height if height is not None else int(body['height_f32_bits'], 16),
                  traversal, reads, malformed, *movement_fields(movements)]
        if error is not None:
            answers = ['error\t' + error + '\t' + T.receiver(before)]
        else:
            actual = actual or {'inside_reads': [], 'callbacks': [], 'impulse_reset_calls': 0}
            self.trace_reads += len(actual['inside_reads'])
            self.trace_callbacks += len(actual['callbacks'])
            trace = ''.join(T.text_words([*(T.word(c) for c in value['position']),
                                         T.state_id(value['state'], self.rows),
                                         T.word(value['collector_step_before']),
                                         int(value['entity_seen_before'])]) + ';'
                            for value in actual['inside_reads'])
            callbacks = cell_text(actual['callbacks'], self.rows, collector=True)
            answers = ['traces\t' + trace + '\t' + callbacks,
                       'ok\t' + T.receiver(after) + '\t'
                       + str(int(actual.get('impulse_reset_calls', 0) > 0)) + '\t'
                       + cell_text(actual['callbacks'], self.rows), 'authority\t1']
            self.authority_checks += 1
        if self.checking:
            answers.append('owners\t1')
        self.add(label, category, fields, answers)


def prepare(folder, data, count, identity):
    rows = T.state_ids()
    corpus = Corpus(folder, rows, count, identity)
    initial_world = corpus.load('initial-complete-owner')
    walks = accepted_visits = sweeps = read_count = callback_count = clips = collision_sequences = 0
    for case in data['cases']:
        seeded = False
        for index, (request, actual) in enumerate(zip(case['input']['steps'], case['expected']['steps'], strict=True)):
            label = case['id'] + ':' + str(index)
            before = actual['before']
            if request['operation'] == 'walk':
                movement = request['movement']
                expected_visits = [v for v in actual['visits'] if v['accepted']]
                visits_text = ''.join(T.text_words([*(T.word(c) for c in v['position']), v['step']]) + ';' for v in expected_visits)
                corpus.add(label, 'original-blockgetter-accepted-visits', [
                    'walk', int(before['body']['width_f32_bits'], 16), int(before['body']['height_f32_bits'], 16),
                    16384, T.word(request['stop_step']), *T.vector(movement['from']), *T.vector(movement['to'])],
                    ['walk\t' + str(int(actual['completed'])) + '\t' + visits_text])
                walks += 1
                accepted_visits += len(expected_visits)
            elif request['operation'] == 'geometry':
                for target, expected in zip(request['targets'], actual['target_clips'], strict=True):
                    corpus.add(label, 'original-aabb-clip', ['clip', *T.vector(target),
                               *T.vector(request['movement']['from']), *T.vector(request['movement']['to'])],
                               ['clip\t' + (T.text_words(T.vector(expected)) if expected else 'none')])
                    clips += 1
            else:
                T.require(request['operation'] == 'sweep', 'unexpected operation')
                T.require(all(shape['shape']['identity_block'] for shape in actual['entity_inside_shapes']), 'unsupported original inside shape')
                corpus.load(label, actual['inside_reads'], request['world_blocks'])
                if not seeded:
                    corpus.seed(label, before)
                    seeded = True
                corpus.context(label, case['input'], old=before['old_position'],
                               known=before['known_movement'], alive=before['alive'])
                corpus.inspect(label + ':before', before)
                corpus.checkpoint(label)
                movements = actual.get('final_movements', actual['movements'])
                corpus.sweep(label, 'original-entity-moving-dispatch', movements, before, actual['after'], actual)
                sweeps += 1
                read_count += len(actual['inside_reads'])
                callback_count += len(actual['callbacks'])
                collision_sequences += 'collision-' in case['id']

    base = next(c for c in data['cases'] if c['id'].endswith('dispatch-direction-0-public'))
    request, actual = base['input']['steps'][0], base['expected']['steps'][0]
    before, after, movements = actual['before'], actual['after'], actual['movements']
    late = actual['inside_reads'][-1]
    T.require(any(v['state']['identifier'] == 'minecraft:cobweb' for v in actual['inside_reads'][:-1]), 'late refusal must follow a stuck callback')
    malformed_movement = copy.deepcopy(movements[0])
    malformed_movement['to'][0] = '7ff8000000000123'
    outside_movement = copy.deepcopy(movements[0])
    outside_movement['from'][0] = T.bits(2147483648.)
    outside_movement['to'][0] = T.bits(2147483649.)
    failures = recoveries = 0

    def reset(label, level=0, known=None):
        corpus.load(label, actual['inside_reads'], request['world_blocks'])
        corpus.seed(label, before)
        corpus.context(label, base['input'], level=level, known=known,
                       old=before['old_position'], alive=True)

    def recover(label):
        nonlocal recoveries
        corpus.context(label + ':ordinary', base['input'], old=before['old_position'])
        corpus.sweep(label + ':recovery', 'same-owned-state-recovery', movements, before, after, actual)
        corpus.inspect(label + ':committed', after)
        recoveries += 1

    for label, kwargs, error in [
        ('read-zero', {'reads': 0}, 'read-budget'),
        ('read-late', {'reads': 3}, 'read-budget'),
        ('traversal-zero', {'traversal': 0}, 'traversal:traversal-budget'),
        ('traversal-prefix', {'traversal': 2}, 'traversal:traversal-budget'),
        ('noncanonical-request', {'malformed': 1}, 'noncanonical-request'),
        ('infinite-width', {'width': 0x7f800000}, 'traversal:invalid-dimensions:0'),
        ('negative-width', {'width': 0xbf19999a}, 'traversal:invalid-dimensions:0'),
        ('nan-height', {'height': 0x7fc00012}, 'traversal:invalid-dimensions:1'),
        ('missing-dimension', {'dimension': 'minecraft:missing'},
         'producer:world:missing-section:minecraft:missing/' + '/'.join(str(T.word(c >> 4)) for c in actual['inside_reads'][0]['position'])),
    ]:
        reset(label)
        corpus.checkpoint(label)
        corpus.sweep(label, 'atomic-query-refusal', movements, before, before, error=error, **kwargs)
        failures += 1
        recover(label)

    for label, selected, kwargs, error in [
        ('invalid-first-movement', [malformed_movement], {}, 'traversal:invalid-movement:0:0'),
        ('invalid-later-movement', [*movements, malformed_movement], {}, 'traversal:invalid-movement:1:0'),
        ('read-before-later-movement', [*movements, malformed_movement], {'reads': 3}, 'read-budget'),
        ('outside-coordinate', [outside_movement], {}, 'traversal:invalid-coordinate'),
        ('outside-later-coordinate', [*movements, outside_movement], {}, 'traversal:invalid-coordinate'),
    ]:
        reset(label)
        corpus.checkpoint(label)
        corpus.sweep(label, 'deferred-geometry-refusal-and-precedence', selected, before, before, error=error, **kwargs)
        failures += 1
        recover(label)

    for invalid, error in [(2, 'unsupported-inside-shape:minecraft:granite:2'),
                           (count, 'producer:registry:invalid-state:' + str(count)),
                           (0xffffffff, 'producer:registry:invalid-state:4294967295')]:
        for deferred in [False, True]:
            label = 'late-raw-state-' + str(invalid) + '-' + str(deferred)
            reset(label)
            corpus.raw_cell(label, late['position'], invalid)
            corpus.checkpoint(label)
            corpus.sweep(label, 'late-world-refusal-atomic-retention',
                         [*movements, malformed_movement] if deferred else movements,
                         before, before, error=error)
            failures += 1
            corpus.inspect(label + ':retained', before)
            corpus.raw_cell(label + ':restore', late['position'], T.state_id(late['state'], rows))
            corpus.checkpoint(label + ':restored')
            recover(label)

    for level in [2, 6]:
        label = 'server-berry-' + str(level)
        reset(label, level=level, known=[T.bits(.01), ZERO, ZERO])
        corpus.checkpoint(label)
        corpus.sweep(label, 'server-damage-service-refusal', movements, before, before,
                     error='producer:server-berry-damage-required')
        failures += 1
        recover(label)

    reset('nonfinite-server-known')
    corpus.context('nonfinite-server-known', base['input'], level=6,
                   known=['7ff8000000000123', ZERO, ZERO], old=before['old_position'])
    corpus.checkpoint('nonfinite-server-known')
    corpus.sweep('nonfinite-server-known', 'actual-receiver-service-refusal', movements, before, before,
                 error='producer:invalid-movement-observation')
    failures += 1
    recover('nonfinite-server-known')

    collision_cases = [next(c for c in data['cases'] if c['id'].endswith('collision-list-' + str(reverse)))
                       for reverse in [False, True]]
    collision_request = collision_cases[0]['input']['steps'][0]
    collision_actual = collision_cases[0]['expected']['steps'][0]
    T.require(T.receiver(collision_actual['before']) == T.receiver(before), 'collision and callback receivers differ')
    label = 'collision-buckets-before-late-refusal'
    corpus.load(label, [*collision_actual['inside_reads'], *actual['inside_reads']],
                [*collision_request['world_blocks'], *request['world_blocks']])
    corpus.seed(label, before)
    corpus.context(label, base['input'])
    corpus.raw_cell(label, late['position'], 2)
    corpus.checkpoint(label)
    corpus.sweep(label, 'queried-collision-buckets-and-candidate-rollback',
                 [*collision_actual['movements'], *movements, malformed_movement],
                 before, before, error='unsupported-inside-shape:minecraft:granite:2')
    failures += 1
    collision_sequences += 1
    corpus.inspect(label + ':retained', before)
    corpus.raw_cell(label + ':restore', late['position'], T.state_id(late['state'], rows))
    corpus.checkpoint(label + ':restored')
    for case in collision_cases:
        recorded = case['expected']['steps'][0]
        T.require(T.receiver(recorded['before']) == T.receiver(before)
                  and T.receiver(recorded['after']) == T.receiver(before), 'neutral collision receiver changed')
        corpus.sweep(case['id'] + ':same-owner-recovery', 'collision-owner-recovery',
                     recorded['movements'], before, before, recorded)
        recoveries += 1
        collision_sequences += 1
    recover(label)

    gate_count = 0
    for name in ['gate-True-False', 'gate-False-True', 'gate-True-True', 'dead-player']:
        case = next(c for c in data['cases'] if c['id'].endswith(name))
        recorded = case['expected']['steps'][0]
        T.require(not recorded['inside_reads'] and not recorded['callbacks'], 'original gate unexpectedly dispatches')
        corpus.load(name)
        corpus.seed(name, recorded['before'])
        corpus.context(name, case['input'], alive=recorded['before']['alive'])
        corpus.checkpoint(name)
        corpus.sweep(name, 'checked-dispatch-gate-suppression', [malformed_movement],
                     recorded['before'], recorded['after'], recorded,
                     traversal=0, reads=0, width=0x7fc00012)
        gate_count += 1
    corpus.add('final-owner-recheck', 'complete-owner-recheck', ['check'], ['owners\t1'])
    summary = corpus.save()
    summary.update(actual_walk_comparisons=walks, actual_accepted_visits=accepted_visits,
                   actual_sweep_comparisons=sweeps, actual_ordered_reads=read_count,
                   actual_callback_comparisons=callback_count, actual_clip_comparisons=clips,
                   total_native_read_trace_comparisons=corpus.trace_reads,
                   total_native_callback_trace_comparisons=corpus.trace_callbacks,
                   queried_collision_bucket_sequences=collision_sequences,
                   checked_refusals=failures, same_owner_recoveries=recoveries,
                   checked_dispatch_gate_suppressions=gate_count,
                   owner_scope='Complete raw Core fields/SectionMap trie/bucket order/all capacity cells, complete Registry fields/capacity slots/names map; receiver/history/impulse exact on refusal and held State versus Observation on every success. Canonical State and observer tails only.')
    return corpus, initial_world, summary


def pins():
    result = T.imports([ENTRY])
    for path in [Path(__file__), Path(T.__file__), Path(R.__file__), Path(R.PRIOR.__file__),
                 ROOT / 'tools/reference_movement_probe.py', ROOT / 'tools/reference_travel_probe.py',
                 ROOT / 'tools/test_world_codec.py', ROOT / 'tools/test_nbt.py',
                 REFERENCE, REFERENCE_EVIDENCE, T.REGISTRY]:
        result[str(path.resolve().relative_to(ROOT))] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


def prior_failures():
    result = []
    for folder in sorted(BASE.iterdir()) if BASE.exists() else []:
        path = folder / 'failure.json'
        if path.exists():
            item = {'folder': str(folder), 'failure': fingerprint(path), **json.loads(path.read_text())}
            diagnosis = folder / 'diagnosis.json'
            if diagnosis.exists():
                item['diagnosis'] = json.loads(diagnosis.read_text())
            result.append(item)
    return result


def main():
    parser = argparse.ArgumentParser()
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--prepare-only', action='store_true')
    modes.add_argument('--build-only', action='store_true')
    modes.add_argument('--skip-build', action='store_true')
    args = parser.parse_args()
    data, observed, reference_evidence = reference_data()
    controls = R.corruption_controls(data, observed)
    identity, count, registry_info = T.registry_identity(T.REGISTRY)
    folder = BASE / str(time.time_ns())
    folder.mkdir(parents=True, exist_ok=False)
    source_pins, receipts = pins(), []
    try:
        corpus, world, summary = prepare(folder, data, count, identity)
        comparator_controls = T.comparison_faults(corpus)
        T.require(source_pins == pins(), 'source/reference changed during preparation')
        common = {'pin': '26.3', 'folder': str(folder), 'sources_sha256': source_pins,
                  'reference': fingerprint(REFERENCE), 'reference_evidence': fingerprint(REFERENCE_EVIDENCE),
                  'registry': fingerprint(T.REGISTRY), 'registry_identity': identity, 'registry_info': registry_info,
                  'reference_validation': R.validate(data, observed),
                  'reference_corruptions_rejected': controls, 'comparison_corruptions_rejected': comparator_controls,
                  'prior_failed_attempts': prior_failures(), 'corpus': summary}
        if args.prepare_only:
            write_json(folder / 'prepared.json', {**common, 'status': 'prepared', 'native_execution': False})
            print(json.dumps({'status': 'prepared', 'folder': str(folder),
                              'corpus': {k: v for k, v in summary.items() if isinstance(v, int)}}))
            return
        if args.skip_build:
            retained = json.loads(BUILD_EVIDENCE.read_text())
            report_path = Path(retained['folder']) / 'native-build.json'
            T.require(fingerprint(report_path) == retained['build_report'], 'retained build report changed')
            build = json.loads(report_path.read_text())
            T.verify_build(build)
            T.require(fingerprint(BINARY)['sha256'] == build['binary_sha256'], 'retained binary changed')
        else:
            _, receipt = T.run(['python3', ROOT / 'tools/build_native.py', ENTRY, '-o', BINARY,
                                '--report', folder / 'native-build.json'], folder, 'build', 180)
            receipts.append(receipt)
            report_path = folder / 'native-build.json'
            build = json.loads(report_path.read_text())
            T.verify_build(build)
        T.require(build['retries'] == 0, 'builder retried')
        T.require(source_pins == pins(), 'source/reference changed during build')
        if not args.skip_build:
            write_json(BUILD_EVIDENCE, {**common, 'status': 'build-passed', 'build_report': fingerprint(report_path),
                                      'binary': fingerprint(BINARY), 'receipts': receipts})
        if args.build_only:
            print(json.dumps({'status': 'build-passed', 'folder': str(folder)}))
            return
        stdout, receipt = T.run([BINARY, '--gpu', 'off', T.REGISTRY, world, folder / 'requests.tsv',
                                count, identity], folder, 'native', 120)
        receipts.append(receipt)
        expected = (folder / 'expected.tsv').read_bytes()
        T.compare_output(stdout, expected, corpus.requests)
        wrong = expected.replace(b'\tauthority\t1\n', b'\tauthority\t0\n', 1)
        T.require(wrong != expected, 'authority corruption did not change comparison')
        try:
            T.compare_output(stdout, wrong, corpus.requests)
        except AssertionError:
            authority_corruption_rejected = True
        else:
            raise AssertionError('altered authority expected row accepted')
        T.verify_build(build)
        T.require(source_pins == pins(), 'source/reference changed during native comparison')
        write_json(NATIVE_EVIDENCE, {**common, 'status': 'passed', 'build_report': fingerprint(report_path),
            'binary': fingerprint(BINARY), 'receipts': receipts,
            'authority_expected_corruption_rejected': authority_corruption_rejected,
            'scope': 'Actual production S.segment/S.plan/W.query/K.clip through persistent affine P.State. Exact independent original accepted visits/completion, full read order/state/collector-before/seen, callback positions/state/collector-step, multiplier/fall/impulse/reset, complete owner retention and held State/Observation joins. Ready lists for stored-route use original observed final_movements; queue formation, arbitrary inside shapes/fluids, callback inside boolean, collidedWithShapeMovingFrom aggregate and full tick effects are outside native comparison scope.'})
        print(json.dumps({'status': 'passed', 'folder': str(folder),
                          'corpus': {k: v for k, v in summary.items() if isinstance(v, int)}}))
    except BaseException as error:
        for name in ['build', 'native']:
            path = folder / (name + '.json')
            if path.exists():
                receipt = json.loads(path.read_text())
                if not any(prior['pid'] == receipt['pid'] for prior in receipts):
                    receipts.append(receipt)
        failure = {'status': 'failed', 'folder': str(folder), 'error': repr(error),
                   'sources_sha256': source_pins, 'receipts': receipts,
                   'target_executed': (folder / 'native.json').exists()}
        write_json(folder / 'failure.json', failure)
        write_json(ROOT / 'evidence' / ('player-block-inside-sweep-failure-' + folder.name + '.json'), failure)
        raise


if __name__ == '__main__':
    main()
