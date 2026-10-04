#!/usr/bin/env python3
"""Bounded native checks for the new block-inside runtime adapter.

The default prepares files only. Compilation/execution require explicit modes.
Expected consumption comes from retained original Player.travel captures;
expected ordered callbacks come from retained original stored dispatch captures.
This does not certify the X/local_player_runtime/Scene integration or execute travel.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import time

import test_player_block_inside_stuck as T
import test_player_block_inside_sweep as Sweep
from reference_inventory import fingerprint, write_json

ROOT = T.ROOT
ENTRY = ROOT / 'tests/runtime_block_inside.bend'
BINARY = ROOT / 'build/runtime-block-inside-tests'
BASE = ROOT / 'build/runtime-block-inside/native'
BUILD_EVIDENCE = ROOT / 'evidence/runtime-block-inside-build.json'
NATIVE_EVIDENCE = ROOT / 'evidence/runtime-block-inside-native.json'
ZERO = T.ZERO


def receiver_fields(value):
    impact = value.get('impulse_position', [])
    return [*T.vector(value['stuck_multiplier']), value.get('impulse_grace', 0),
            int(bool(impact)), *T.vector(impact or [ZERO] * 3)]


def body_fields(value):
    return [*T.vector(value['position']), *T.vector(value['box']),
            *T.vector(value['velocity']), int(value['width_f32_bits'], 16),
            int(value['height_f32_bits'], 16), *map(int, value['flags'])]


def raw_receiver(multiplier=None, grace=0, impact=None):
    return {'stuck_multiplier': multiplier or [ZERO] * 3,
            'fall_distance': ZERO, 'impulse_grace': grace,
            'impulse_position': impact or []}


def compare_cases():
    base = raw_receiver()
    values = [base,
              raw_receiver(['8000000000000000', ZERO, ZERO]),
              raw_receiver([ZERO, '8000000000000000', ZERO]),
              raw_receiver([ZERO, ZERO, '8000000000000000']),
              raw_receiver(['7ff8000000000123', ZERO, ZERO]),
              raw_receiver(['7ff8000000000456', ZERO, ZERO]),
              raw_receiver(grace=0xffffffff),
              raw_receiver(impact=[ZERO] * 3),
              raw_receiver(impact=['8000000000000000', ZERO, ZERO]),
              raw_receiver(impact=['7ff8000000000123', ZERO, ZERO]),
              raw_receiver(impact=['7ff8000000000456', ZERO, ZERO])]
    pairs = [(value, copy.deepcopy(value), True) for value in values]
    pairs.extend((base, value, False) for value in values[1:])
    pairs.extend([(values[4], values[5], False), (values[9], values[10], False),
                  (values[7], values[8], False)])
    return pairs


class Corpus(T.Corpus):
    def join(self, label, body, prepared, old, original, displacement, changed,
             before, after=None, *, framed=False, malformed=False,
             traversal=4096, reads=4096, actual=None, error=None, category=None):
        fields = ['join', int(framed), int(malformed), traversal, reads,
                  *body_fields(body), *body_fields(prepared), *T.vector(old),
                  *T.vector(original), *T.vector(displacement), int(changed)]
        if error is not None:
            answers = ['error\t' + error + '\t' + T.receiver(before), 'owners\t1']
        else:
            answers = []
            if framed:
                T.require(actual is not None, 'framed success lacks original callback observations')
                trace = ''.join(T.text_words([*(T.word(c) for c in read['position']),
                                             T.state_id(read['state'], self.rows),
                                             T.word(read['collector_step_before']),
                                             int(read['entity_seen_before'])]) + ';'
                                for read in actual['inside_reads'])
                callbacks = Sweep.cell_text(actual['callbacks'], self.rows, collector=True)
                answers.append('traces\t' + trace + '\t' + callbacks)
            answers.extend(['ok\t' + T.receiver(after) + '\t'
                            + str(int(bool(actual and actual['impulse_reset_calls']))),
                            'authority\t1', 'owners\t1'])
            self.authority_checks += 1
        category = category or ('original-stored-callback-framed-join' if framed else
                               ('adapter-refusal-full-owner' if error else 'original-motion-consumption-join'))
        self.add(label, category, fields, answers)


def prepare(folder, motion, sweep, count, identity):
    corpus = Corpus(folder, T.state_ids(), count, identity)
    initial_world = corpus.load('initial-complete-owner')
    pairs = compare_cases()
    for index, (left, right, expected) in enumerate(pairs):
        corpus.add('raw-receiver-' + str(index), 'raw-receiver-comparison',
                   ['compare', *receiver_fields(left), *receiver_fields(right)],
                   ['compare\t' + str(int(expected))])
    for index, (value, _, _) in enumerate(pairs[:11]):
        corpus.add('no-physics-' + str(index), 'no-physics-raw-preservation',
                   ['consume', 1, *receiver_fields(value)], ['consume\t' + T.receiver(value)])

    selected = [next(c for c in motion['cases'] if c['id'] == 'motion-current:threshold-0-' + str(i) + '-False')
                for i in range(6)]
    for case in selected:
        observed = case['observation']
        seed = raw_receiver(case['input']['stuck_multiplier'], 0xffffffff,
                            ['8000000000000000', '7ff8000000000123', ZERO])
        final = copy.deepcopy(seed)
        final['stuck_multiplier'] = observed['final_stuck_multiplier']
        corpus.add(case['id'] + ':consume', 'original-motion-consumption',
                   ['consume', 0, *receiver_fields(seed)], ['consume\t' + T.receiver(final)])
        # An explicitly loaded air section admits these bounded neutral paths.
        # The collision result is supplied from Java; this entry does not travel.
        T.require(all(int(raw, 16) < 0x8000000000000000 for raw in case['expected']['position']),
                  'selected neutral motion escaped positive fixture section')
        corpus.load(case['id'], writes=[{'identifier': 'minecraft:air', 'position': [0, 0, 0]}])
        corpus.seed(case['id'], seed)
        context = {'receiver': 'player', 'flying': False, 'weaving': False,
                   'removed': False, 'no_physics': False,
                   'position': case['expected']['position']}
        corpus.context(case['id'], context, level=1, old=case['input']['position'])
        corpus.join(case['id'] + ':after-success', case['expected'], observed['pre_move_body'],
                    case['input']['position'], observed['requested'], observed['recorded_displacement'],
                    observed['movement_recorded'], seed, final)

    # The unchanged original dispatcher returns before any level read for this
    # noPhysics receiver. The carrier is inert; no movement is executed or claimed.
    physics_case = next(c for c in sweep['cases'] if c['id'] == 'block-inside-sweep:gate-False-True')
    physics_step = physics_case['expected']['steps'][0]
    before = physics_step['before']
    T.require(before['no_physics'] and not physics_step['inside_reads'] and not physics_step['callbacks'],
              'original noPhysics case reached a callback')
    corpus.load(physics_case['id'])
    corpus.seed(physics_case['id'], before)
    corpus.context(physics_case['id'], physics_case['input'], level=1, old=before['old_position'])
    corpus.join(physics_case['id'] + ':after-success', before['body'], before['body'],
                before['old_position'], [ZERO] * 3, [ZERO] * 3, False,
                before, physics_step['after'], traversal=0, reads=0, actual=physics_step,
                category='original-no-physics-dispatch-adapter')

    framed_count = 0
    callbacks = reads = 0
    for suffix in ['stored-empty', 'stored-queued']:
        case = next(c for c in sweep['cases'] if c['id'].endswith(suffix))
        request = case['input']['steps'][0]
        observed = case['expected']['steps'][0]
        before = observed['before']
        body = before['body']
        prepared = copy.deepcopy(body)
        queue = request['movements']
        if queue:
            T.require(len(queue) == 1 and bool(queue[0]['axis_original']), 'framed record must match Entity.move form')
            actual_record = observed['movements'][0]
            prepared['position'] = actual_record['from']
            original, displacement, changed = actual_record['axis_original'], actual_record['delta'], True
        else:
            original, displacement, changed = [ZERO] * 3, [ZERO] * 3, False
        corpus.load(case['id'], observed['inside_reads'], request['world_blocks'])
        corpus.seed(case['id'], before)
        corpus.context(case['id'], case['input'], level=1, old=before['old_position'])
        corpus.join(case['id'], body, prepared, before['old_position'], original, displacement,
                    changed, before, observed['after'], framed=True, actual=observed)
        framed_count += 1
        callbacks += len(observed['callbacks'])
        reads += len(observed['inside_reads'])

    base = next(c for c in sweep['cases'] if c['id'].endswith('stored-queued'))
    request = base['input']['steps'][0]
    observed = base['expected']['steps'][0]
    before = observed['before']
    body = before['body']
    prepared = copy.deepcopy(body)
    movement = observed['movements'][0]
    prepared['position'] = movement['from']
    common = [body, prepared, before['old_position'], movement['axis_original'], movement['delta'], True, before]
    refusals = recoveries = 0
    late = observed['inside_reads'][-1]
    T.require(any(v['state']['identifier'] in ['minecraft:cobweb', 'minecraft:sweet_berry_bush']
                  for v in observed['inside_reads'][:-1]), 'late shape refusal has no prior callback')
    for label, options, error in [
        ('malformed-hooks', {'malformed': True}, 'noncanonical-block-inside-hooks'),
        ('read-budget-zero', {'reads': 0}, 'read-budget'),
        ('read-budget-late', {'reads': len(observed['inside_reads']) - 1}, 'read-budget'),
        ('traversal-budget-zero', {'traversal': 0}, 'traversal:traversal-budget'),
        ('late-shape', {}, 'unsupported-inside-shape:minecraft:granite:2'),
        ('missing-section', {}, 'producer:world:missing-section:minecraft:overworld/0/0/0'),
    ]:
        corpus.load(label, [] if label == 'missing-section' else observed['inside_reads'],
                    [] if label == 'missing-section' else request['world_blocks'])
        corpus.seed(label, before)
        corpus.context(label, base['input'], level=1, old=before['old_position'])
        if label == 'late-shape':
            corpus.raw_cell(label, late['position'], 2)
        corpus.join(label, *common, error=error, **options)
        refusals += 1
        if label == 'late-shape':
            corpus.raw_cell(label + ':repair', late['position'], T.state_id(late['state'], corpus.rows))
        if label != 'missing-section':
            # Same returned parent world/receiver is reused; every new MH wrapper
            # again carries two distinct child owners and nontrivial cache/header.
            corpus.join(label + ':recovery', *common, observed['after'], framed=True, actual=observed)
            recoveries += 1
    summary = corpus.save()
    summary.update(raw_receiver_comparisons=len(pairs), no_physics_preservations=11,
                   no_physics_adapter_joins=1,
                   actual_consumption_comparisons=len(selected), successful_travel_adapter_joins=len(selected),
                   original_framed_callback_joins=framed_count, original_framed_reads=reads,
                   original_framed_callbacks=callbacks, adapter_refusals=refusals,
                   same_parent_owner_recoveries=recoveries,
                   owner_scope='Complete Core/Registry capacity/bucket fields, raw Body/view/palette/cache/support/minor/history, receiver; two distinct immediate MH child owners including all their capacity cells and inactive metadata. Constructed MH depth is one; observer tails canonical.')
    return corpus, initial_world, summary


def pins():
    result = T.imports([ENTRY])
    for path in [Path(__file__), Path(T.__file__), Path(Sweep.__file__), Path(T.MC.__file__),
                 Path(Sweep.R.__file__), Path(Sweep.R.PRIOR.__file__),
                 ROOT / 'tools/reference_movement_probe.py', ROOT / 'tools/reference_travel_probe.py',
                 ROOT / 'tools/test_player_look.py', ROOT / 'tools/test_persistence.py',
                 ROOT / 'tools/test_world_codec.py', ROOT / 'tools/test_nbt.py',
                 T.MOTION_REFERENCE, T.MOTION_REFERENCE_EVIDENCE,
                 Sweep.REFERENCE, Sweep.REFERENCE_EVIDENCE, T.REGISTRY]:
        result[str(path.resolve().relative_to(ROOT))] = hashlib.sha256(path.read_bytes()).hexdigest()
    return result


def main():
    parser = argparse.ArgumentParser()
    modes = parser.add_mutually_exclusive_group()
    modes.add_argument('--prepare-only', action='store_true')
    modes.add_argument('--build-only', action='store_true')
    modes.add_argument('--run', action='store_true')
    modes.add_argument('--skip-build', action='store_true')
    args = parser.parse_args()
    motion, motion_controls = T.motion_reference_data()
    sweep, sweep_captures, _ = Sweep.reference_data()
    sweep_controls = Sweep.R.corruption_controls(sweep, sweep_captures)
    identity, count, registry_info = T.registry_identity(T.REGISTRY)
    folder = BASE / str(time.time_ns())
    folder.mkdir(parents=True, exist_ok=False)
    source_pins = pins()
    corpus, world, summary = prepare(folder, motion, sweep, count, identity)
    comparator_controls = T.comparison_faults(corpus)
    T.require(source_pins == pins(), 'source/reference changed during file preparation')
    common = {'status': 'prepared', 'pin': '26.3', 'folder': str(folder),
              'sources_sha256': source_pins, 'corpus': summary, 'registry_info': registry_info,
              'motion_reference': fingerprint(T.MOTION_REFERENCE),
              'sweep_reference': fingerprint(Sweep.REFERENCE),
              'motion_corruptions_rejected': motion_controls,
              'sweep_corruptions_rejected': sweep_controls,
              'comparison_corruptions_rejected': comparator_controls,
              'scope': 'New R.same_receiver/R.consume/R.after_successful_travel/R.framed adapter only. TH carriers project compared original capture fields and explicitly inert unused fields; no actual travel executes. Callback success/read order uses two original stored dispatches through framed, and a noPhysics gate uses its original no-read dispatch observation. X/local_player_runtime/Scene integration, outer finish execution, arbitrary queue formation, general child depth and whole tick are outside scope.'}
    if not (args.run or args.build_only or args.skip_build):
        write_json(folder / 'prepared.json', {**common, 'native_execution': False, 'source_check': False})
        print(json.dumps({k: summary[k] for k in ['operations', 'responses', 'raw_receiver_comparisons',
                                                'successful_travel_adapter_joins', 'adapter_refusals']}))
        print(str(folder))
        return
    receipts = []
    try:
        if args.skip_build:
            retained = json.loads(BUILD_EVIDENCE.read_text())
            report = Path(retained['folder']) / 'native-build.json'
            T.require(fingerprint(report) == retained['build_report'], 'retained build report changed')
            T.require(source_pins == retained['sources_sha256'], 'retained build source/reference pins differ')
        else:
            _, receipt = T.run(['python3', ROOT / 'tools/build_native.py', ENTRY,
                                '-o', BINARY, '--report', folder / 'native-build.json'], folder, 'build', 180)
            receipts.append(receipt)
            report = folder / 'native-build.json'
        build = json.loads(report.read_text())
        T.verify_build(build)
        T.require(build['retries'] == 0 and source_pins == pins(), 'build retried or sources changed')
        T.require(Path(build['artifact']).resolve() == BINARY.resolve(), 'build artifact belongs to another target')
        T.require(fingerprint(BINARY)['sha256'] == build['binary_sha256'], 'retained binary mismatch')
        if not args.skip_build:
            write_json(BUILD_EVIDENCE, {**common, 'status': 'build-passed', 'build_report': fingerprint(report),
                                       'binary': fingerprint(BINARY), 'receipts': receipts})
        if args.build_only:
            return
        stdout, receipt = T.run([BINARY, '--gpu', 'off', T.REGISTRY, world, folder / 'requests.tsv', count, identity],
                                folder, 'native', 120)
        receipts.append(receipt)
        T.compare_output(stdout, (folder / 'expected.tsv').read_bytes(), corpus.requests)
        T.verify_build(build)
        T.require(source_pins == pins(), 'source/reference changed during native comparison')
        write_json(NATIVE_EVIDENCE, {**common, 'status': 'passed', 'build_report': fingerprint(report),
                                    'binary': fingerprint(BINARY), 'receipts': receipts})
        print(json.dumps({'status': 'passed', 'folder': str(folder), 'operations': summary['operations']}))
    except BaseException as error:
        for name in ['build', 'native']:
            path = folder / (name + '.json')
            if path.exists():
                receipt = json.loads(path.read_text())
                if not any(prior['pid'] == receipt['pid'] for prior in receipts):
                    receipts.append(receipt)
        failure = {'status': 'failed', 'folder': str(folder), 'error': repr(error),
                   'sources_sha256': source_pins, 'receipts': receipts,
                   'native_started': (folder / 'native.json').exists()}
        write_json(folder / 'failure.json', failure)
        write_json(ROOT / 'evidence' / ('runtime-block-inside-failure-' + folder.name + '.json'), failure)
        raise


if __name__ == '__main__':
    main()
