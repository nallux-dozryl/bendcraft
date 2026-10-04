#!/usr/bin/env python3
"""Host-only required-reset Session lane for the next shared composite.

No builder, source mutation, Java extraction or standalone executable lives here.
The first move has an actual Java Body/history oracle. Other first-tick fields
are an explicitly component-composed projection; the second tick is a complete
cold-restart/uninterrupted relation, not a newly observed Java whole tick.
"""
from __future__ import annotations
import argparse
import copy
import dataclasses
import hashlib
import json
import re
from pathlib import Path
import test_local_player_session as S
import test_local_phase_reset as PhaseReset

ROOT = S.ROOT
REFERENCES = {
    'reference/local_travel_history.json': '07646e7fef0e55f3fd89421d1862b0e6dc5fdde3a0a84800b70b857a66609dbf',
    'reference/fall_reset_world.json': '5286ed1f9a8cfbb190d98f4ec8f67ef1e066910e7a5788aa3aef5570144a8014',
    'reference/local_phase_runtime.json': '6126038d6a5e3058e58dd0be100548cbeafce7b0f7cbede2075d9e2129ccdff7',
}
OLD_FACADE = 'fd932047be8c476e812d15618a5b0b9a8c71bea62aef5cb69bed707703b77ec7'
OLD_SESSION_HELPER = 'ffa2d9d7105b2fd1eb0b1e3bbace195f3dceed75bdbe80e8814349df3545b2c1'
BODY_FIELDS = ('position', 'box', 'velocity', 'width_f32_bits', 'height_f32_bits', 'body_flags')
COMPONENT_FIELDS = (*BODY_FIELDS, 'main_support', 'on_ground_no_blocks',
                    'minor_horizontal_collision', 'fall_distance_f64_bits')
WORK = ROOT / 'build/local-player-reset-consumer'


def require(valid, message):
    if not valid:
        raise AssertionError(message)


def digest(value):
    return hashlib.sha256(S.canonical(value)).hexdigest()


def pinned_references():
    result = {}
    for name, expected in REFERENCES.items():
        path = ROOT / name
        require(S.pin(path)['sha256'] == expected, 'Changed actual reference: ' + name)
        result[name] = json.loads(path.read_bytes())
    return result


def component_record(base, observed):
    """Copy observed raw words into the independent durable codec; no motion math."""
    motion, look_bytes = S.PR.decode(base.motion)
    words, dimension = S.PC.parse_snapshot(motion)
    words = list(words)
    words[:30] = [*S.PC.words64(tuple(int(v, 16) for v in
        observed['position'] + observed['box'] + observed['velocity'])),
        int(observed['width_f32_bits'], 16), int(observed['height_f32_bits'], 16),
        *map(int, observed['body_flags'])]
    support = observed['main_support']
    words[41:46] = [int(support is not None),
        *((S.unsigned(v) for v in support) if support is not None else (0, 0, 0)),
        int(observed['on_ground_no_blocks'])]
    nested = S.N.encode_root(S.PR.root(S.N.encode_root(S.PC.snapshot_root(tuple(words), dimension)),
                                     S.PR.look_words(look_bytes)))
    return S.validate_local(dataclasses.replace(base, motion=nested,
        minor=int(observed['minor_horizontal_collision']),
        distance=int(observed['fall_distance_f64_bits'], 16)))


def fixture():
    refs = pinned_references()
    history = refs['reference/local_travel_history.json']
    case = next(c for c in history['cases'] if c['id'] == 'air_miss')
    require(len(case['steps']) == 1, 'air_miss changed arity')
    step = case['steps'][0]
    ray = next(c for c in refs['reference/fall_reset_world.json']['cases']
               if c['id'] == 'local_travel_history:air_miss:0')
    require(step['travel_input'] == ['0000000000000000'] * 3, 'Direct travel is not zero input')
    require(step['actual_requested'] == ['0000000000000000', 'bff2000000000000', '0000000000000000'],
            'Actual required movement changed')
    entry = step['ray_observation']['clip_calls'][0]
    require(ray['from'] == entry['from'] and ray['to'] == entry['to'], 'Actual ray endpoints differ')
    require(case['plain_observer_parity'] is True and ray['actual_returned'] is True
            and ray['plain_observer_parity'] is True
            and ray['admission'] == {'supported': True} and ray['result']['type'] == 'MISS'
            and ray['minimum_core_read_budget'] == ray['read_attempt_count'] == 6,
            'Actual required ray provenance changed')
    require(ray['origin_reference']['path'] == 'reference/local_travel_history.json'
            and ray['origin_reference']['case_id'] == 'air_miss'
            and ray['origin_reference']['step_index'] == 0
            and step['world_writes'] == ray['world_writes'] == [],
            'Required ray no longer belongs to the untouched actual travel fixture')
    require([(r['position'], r['phase'], r['block_id']) for r in ray['reads']] == [
        ([0, y, 0], phase, 'minecraft:air') for y in (10, 9, 8)
        for phase in ('BlockSample', 'FluidSource')], 'Actual ordered ray reads changed')
    chosen, _, _ = S.reference_cases()
    zero = next(c for c in chosen if c['id'] == 'scheduled_zero')['steps'][0]
    require(zero['held_mask'] == 0 and zero['before'].keys == zero['after'].keys == (0,) * 7,
            'Neutral zero-key component fixture changed')
    require(zero['before'].count == 0 and zero['after'].count == 1,
            'Neutral zero-key component no longer has one common tick from zero')
    # The composition is conditional on unchanged neutral services. Keep these
    # raw source properties explicit instead of assuming a complete air tick.
    for name in ('gravity', 'movement_speed', 'jump_strength', 'sneaking_speed',
                 'friction_modifier', 'air_drag_modifier'):
        require(step['before'][name] == zero['raw']['before'][name],
                'Air/neutral component service differs: ' + name)
    for record in (zero['before'], zero['after']):
        require(record.pose == 0 and record.crouching == record.sprinting == 0
                and record.trigger == record.invulnerable == 0,
                'Neutral default projection changed')
    initial = component_record(zero['before'], step['before'])
    expected = component_record(zero['after'], step['expected'])
    # commonTick's two old-position triples come from the pre-move feet. This
    # raw field copy is a supported component projection, not a whole-tick oracle.
    feet = tuple(int(v, 16) for v in step['before']['position'])
    expected = S.validate_local(dataclasses.replace(expected, old_positions=feet + feet))
    require(S.decode_local(S.local_bytes(initial)) == initial and
            S.decode_local(S.local_bytes(expected)) == expected, 'Independent fixture encoding differs')
    return {'initial': initial, 'expected': expected, 'travel': step, 'ray': ray,
            'zero': zero, 'references': refs}


def preparation():
    """File-only preparation, safe before any native slot or enabled facade."""
    data = fixture()
    facade = PhaseReset.facade_generation()
    session_helper = S.pin(Path(S.__file__))
    require(session_helper['sha256'] == OLD_SESSION_HELPER,
            'Existing independent Session helper changed')
    return {
        'status': 'host-prepared-not-executed', 'module': S.pin(Path(__file__)),
        'immutable_session_helper': session_helper, 'facade_generation': facade,
        'references': [S.pin(ROOT / name) for name in REFERENCES],
        'initial_record': {'bytes': len(S.local_bytes(data['initial'])),
                           'sha256': S.sha(S.local_bytes(data['initial']))},
        'component_expected_record': {'bytes': len(S.local_bytes(data['expected'])),
                                      'sha256': S.sha(S.local_bytes(data['expected']))},
        'actual_first_motion': {name: data['travel']['expected'][name] for name in COMPONENT_FIELDS},
        'actual_required_ray': {name: data['ray'][name] for name in
            ('id', 'origin_reference', 'from', 'to', 'visited_cells', 'minimum_core_read_budget', 'result')},
        'actual_ordered_ray_reads_sha256': digest(data['ray']['reads']),
        'first_tick_scope': 'Actual TH Body/SP/minor/history plus conditional LI/PT/Pose/ECT/default-field composition; no fresh whole-X Java tick',
        'first_tick_field_provenance': {
            'motion.body': 'Actual local_travel_history air_miss step0 expected raw fields',
            'motion.support/minor/fall_distance': 'Same actual air_miss step0 expected raw fields',
            'motion.player/look/local/pose': 'Actual scheduled_zero step0 after, conditional on identical zero input, retained look/bob, neutral services and stable standing pose',
            'old_positions': 'Actual air_miss step0 before position copied to both commonTick triples',
            'invulnerable_time/tick_count': 'Actual scheduled_zero step0 after, same initial zero counters and exactly one commonTick',
        },
        'second_tick_scope': 'Complete supported Record/Core restarted-vs-uninterrupted relation; no air_miss_history reuse or host physics',
        'production_inputs': ['fixture.input held_mask0', 'simulation.step ticks1',
            'player.inspect', 'world.clock', 'world.save', 'fixture.release', 'fixture.snapshot'],
        'runtime_processes': 4, 'matching_peers': {'initial': [12, 13], 'continuation': [14, 15]},
        'refusal_scope': 'Due unsupported cell rejects the owned checked tick before supplier; actual supplier-budget refusal stays in imported phase-reset-cases',
        'native_builder': None, 'native_execution': 'not-run', 'java_execution': 'not-run',
        'mutation_scope': 'New fixture files and receipts only; existing helpers/source/reference immutable',
        'consumer_activation': ('Enabled source route; shared native execution must still seal and verify the actual apply_resolved body'
                                if facade['required_reset_enabled'] else
                                'Staged policy only; shared native execution must verify the actual enabled apply_resolved body'),
    }


def prepare_files(directory=WORK / 'prepared-001'):
    """Create only independent fixture bytes and a reviewed host preparation receipt."""
    directory = Path(directory)
    require(not directory.exists(), 'Existing required-reset preparation; refuse overwrite')
    directory.mkdir(parents=True)
    data = fixture()
    for name, record in (('initial-record.nbt', data['initial']),
                         ('component-expected-record.nbt', data['expected'])):
        with (directory / name).open('xb') as output:
            output.write(S.local_bytes(record))
    prepared = preparation()
    prepared.update(facade=S.pin(ROOT / 'src/local_player_runtime.bend'),
        focused_producers=[S.pin(ROOT / name) for name in (
            'tests/local_travel_reset.bend', 'tests/local_phase_reset.bend',
            'tools/test_local_travel_reset.py', 'tools/test_local_phase_reset.py')],
        documentation=[S.pin(ROOT / name) for name in (
            'docs/LOCAL_TRAVEL_RESET.md', 'docs/LOCAL_PHASE_RESET.md',
            'docs/LOCAL_PLAYER_RESET_CONSUMER.md')],
        fixtures=[S.pin(directory / name) for name in (
            'initial-record.nbt', 'component-expected-record.nbt')],
        private_subtree=str(directory.relative_to(ROOT)))
    S.exclusive_json(directory / 'prepared.json', prepared)
    return prepared


def observed_record(client):
    result = client.call('player.inspect', {})
    require(set(result) == {'format', 'nbt_bytes'} and result['format'] == S.NAMESPACE,
            'Unexpected supported-record observation envelope')
    values = result['nbt_bytes']
    require(isinstance(values, list) and all(type(v) is int and 0 <= v <= 255 for v in values),
            'Invalid observed NBT bytes')
    raw = bytes(values)
    value = S.decode_local(raw)
    require(S.local_bytes(value) == raw, 'Observed record is not independently canonical')
    return value


def consumer_admitted(binary_sha256, source_pins):
    # The next root supervisor binds S.SERVER/S.activation to its reviewed shared
    # artifact. This lane has no authority to replace or build that executable.
    require(S.pin(Path(S.__file__))['sha256'] == OLD_SESSION_HELPER,
            'Existing independent Session helper changed')
    S.activation()
    require(S.pin(S.SERVER)['sha256'] == binary_sha256, 'Wrong composite binary')
    needed = {'src/local_player_runtime.bend', 'src/local_phase_runtime.bend',
              'src/local_travel_history.bend', 'src/fall_reset_world.bend',
              'src/local_player_session.bend', 'tests/playable_client_session.bend'}
    require(needed <= set(source_pins), 'Missing new consumer closure pins')
    for name, expected in source_pins.items():
        require(S.pin(ROOT / name)['sha256'] == expected, 'Changed sealed consumer: ' + name)
    require(PhaseReset.facade_generation()['required_reset_enabled'],
            'Consumer facade is outside the exact reviewed reset generation')
    source = (ROOT / 'src/local_player_runtime.bend').read_text()
    applied = re.search(r'^def apply_resolved\([^\n]*\n(.*?)(?=^def |^law |\Z)', source, re.M | re.S)
    require(source_pins['src/local_player_runtime.bend'] != OLD_FACADE and applied is not None
            and applied.group(1) == '  (stage, status) = result\n  tick_result(X.resume_apply_with_reset_checked(stage, status, reset_policy()))\n\n',
            'Required-reset facade is not enabled in this consumer')


def run_reset_session(registry, count, identity, bridge, directory, saves, checks,
                      *, binary_sha256, source_pins):
    """Run only when the root shared-artifact supervisor explicitly calls it."""
    consumer_admitted(binary_sha256, source_pins)
    data = fixture()
    directory = Path(directory)
    require(not directory.exists(), 'Existing required-reset Session attempt')
    directory.mkdir(parents=True)
    S.exclusive_json(directory / 'prepared.json', preparation())
    live = []
    receipt = {'status': 'running', 'binary_sha256': binary_sha256,
               'first_tick_scope': preparation()['first_tick_scope'],
               'second_tick_scope': preparation()['second_tick_scope'], 'checks': []}

    def launch(path, label):
        consumer_admitted(binary_sha256, source_pins)
        runtime = S.Runtime(path, registry, bridge, directory / label)
        live.append(runtime)
        return runtime

    def stop(runtime):
        live.remove(runtime)
        runtime.stop()

    def peers(runtime, numbers):
        tcp, ping = runtime.tcp(True)
        mcp, mping = runtime.mcp()
        require([ping['peer'], mping['peer']] == numbers, 'Unmatched peer/highwater schedule')
        return tcp, mcp

    def checked_step(tcp, world, prior):
        S.inspect(tcp, prior)
        require(tcp.call('fixture.input', {'held_mask': 0}) == {'applied': True}, 'Zero-key packet failed')
        S.inspect(tcp, prior)
        require(tcp.call('fixture.transient')['buttons'] == 0, 'Actual neutral buttons differ')
        require(tcp.call('world.clock') == S.P.clock(world), 'Input packet advanced the Core clock')
        result = tcp.call('simulation.step', {'ticks': 1})
        S.BASE.apply_tick(world)
        require(result == S.P.clock(world), 'One paused explicit Core step differs')

    try:
        branches = {}
        for name in ('uninterrupted', 'cold'):
            world = S.scene_world(count, identity)
            path = directory / (name + '.nbt')
            path.write_bytes(S.bundle_bytes(world, 11, data['initial']))
            runtime = launch(path, name + '-initial')
            tcp, mcp = peers(runtime, [12, 13])
            S.inspect(tcp, data['initial']); S.inspect(mcp, data['initial'])
            checked_step(tcp, world, data['initial'])
            S.inspect(tcp, data['expected']); S.inspect(mcp, data['expected'])
            require(tcp.call('fixture.transient')['last_error'] == 'none', 'Required ray was refused')
            require(tcp.call('fixture.snapshot') == S.snapshot_expected(world, data['expected']),
                    'Pose-eye read-only snapshot differs')
            require(tcp.call('world.clock') == S.P.clock(world), 'Snapshot advanced required-ray state')
            tcp.call('fixture.release')
            S.inspect(tcp, data['expected'])
            saved = S.save(mcp, path, world, 13, data['expected'], saves, 'reset-' + name + '-first')
            branches[name] = {'world': world, 'path': path, 'runtime': runtime, 'saved': saved}
        require(branches['cold']['saved'] == branches['uninterrupted']['saved'], 'First acknowledged full bundles differ')
        stop(branches['cold']['runtime'])
        branches['cold']['runtime'] = launch(branches['cold']['path'], 'cold-restart')
        continued = {}
        for name, branch in branches.items():
            # A live control branch allocates the same fresh peers as coldload;
            # old peers remain idle, so no synthetic highwater rewrite is needed.
            tcp, mcp = peers(branch['runtime'], [14, 15])
            S.inspect(tcp, data['expected']); S.inspect(mcp, data['expected'])
            require(tcp.call('fixture.transient')['buttons'] == 0, 'Physical keys survived release/coldload')
            require(tcp.call('world.clock') == S.P.clock(branch['world']), 'Coldload changed complete Core clock')
            require(branch['path'].read_bytes() == branch['saved'], 'Coldload changed acknowledged bytes')
            checked_step(tcp, branch['world'], data['expected'])
            value = observed_record(tcp)
            S.inspect(mcp, value)
            require(tcp.call('fixture.transient')['last_error'] == 'none', 'Continued required reset failed')
            prior_motion, _ = S.PR.decode(data['expected'].motion)
            current_motion, _ = S.PR.decode(value.motion)
            prior_words, _ = S.PC.parse_snapshot(prior_motion)
            current_words, _ = S.PC.parse_snapshot(current_motion)
            common = S.record_with_common(data['expected'])
            require(value.count == common.count and value.invulnerable == common.invulnerable
                    and value.old_positions == common.old_positions
                    and current_words[:6] != prior_words[:6]
                    and value.distance != data['expected'].distance,
                    'Second tick did not advance common metadata, Body and durable fall history')
            require(tcp.call('fixture.snapshot') == S.snapshot_expected(branch['world'], value),
                    'Continued pose-eye read-only snapshot differs')
            S.inspect(tcp, value)
            require(tcp.call('world.clock') == S.P.clock(branch['world']), 'Continued snapshot advanced Core')
            continued[name] = value
            branch['continued_bytes'] = S.save(mcp, branch['path'], branch['world'], 15, value,
                                                saves, 'reset-' + name + '-continued')
        require(continued['cold'] == continued['uninterrupted'], 'Cold continuation lost supported local fields')
        require(branches['cold']['continued_bytes'] == branches['uninterrupted']['continued_bytes'],
                'Complete continued Core/Record/highwater bytes differ')
        for branch in branches.values():
            stop(branch['runtime'])

        # Real queued mutation + checked phase rejection. This is deliberately
        # not called a supplier-only failure: early fit/collision reads see it.
        world = S.scene_world(count, identity)
        path = directory / 'world-refusal.nbt'
        path.write_bytes(S.bundle_bytes(world, 11, data['initial']))
        runtime = launch(path, 'world-refusal')
        tcp, mcp = peers(runtime, [12, 13])
        before = tcp.call('fixture.owners')
        S.queue_set(tcp, world, ('minecraft:overworld', 0, 10, 0), 2, world['tick'] + 1)
        checked_step(tcp, world, data['initial'])
        anchor = S.record_with_common(data['initial'])
        S.inspect(tcp, anchor); S.inspect(mcp, anchor)
        refused = tcp.call('fixture.transient')['last_error']
        require(refused == 'unsupported-block-state:2', 'Unsupported checked tick refusal differs: ' + refused)
        after = tcp.call('fixture.owners')
        require(before['root']['table_digest'] == after['root']['table_digest'] and
                before['root']['motion']['world']['body'] == after['root']['motion']['world']['body'] and
                before['root']['motion']['history'] == after['root']['motion']['history'] and
                before['root']['motion']['world']['view'] == after['root']['motion']['world']['view'],
                'Checked refusal lost sole Body/history/View/tables')
        S.save(mcp, path, world, 13, anchor, saves, 'reset-world-refused-anchor')
        S.queue_set(tcp, world, ('minecraft:overworld', 0, 10, 0), 0, world['tick'] + 1)
        checked_step(tcp, world, anchor)
        recovered = dataclasses.replace(data['expected'], count=S.record_with_common(anchor).count)
        S.inspect(tcp, recovered); S.inspect(mcp, recovered)
        require(tcp.call('fixture.transient')['last_error'] == 'none', 'Same-owned-world recovery failed')
        S.save(mcp, path, world, 13, recovered, saves, 'reset-world-refusal-recovered')
        stop(runtime)
        consumer_admitted(binary_sha256, source_pins)
        receipt.update(status='passed', first_expected_record_sha256=S.sha(S.local_bytes(data['expected'])),
            continued_record_sha256=S.sha(S.local_bytes(continued['cold'])),
            continued_bundle_sha256=S.sha(branches['cold']['continued_bytes']),
            whole_record_cold_continuation=True, actual_supplier_only_refusal=False,
            queued_world_refusal_same_owner_recovery=True, queued_world_refusal=refused)
        return receipt
    except BaseException as cause:
        receipt.update(status='failed', error=type(cause).__name__ + ': ' + str(cause))
        S.exclusive_json(directory / 'first-failure.json', receipt)
        for runtime in live:
            runtime.failed = receipt['error']
        raise
    finally:
        cleanup = []
        while live:
            runtime = live.pop()
            try:
                runtime.stop()
            except BaseException as cause:
                cleanup.append(type(cause).__name__ + ': ' + str(cause))
        receipt['cleanup_errors'] = cleanup
        if cleanup:
            receipt['status'] = 'failed'
        S.exclusive_json(directory / 'summary.json', receipt)
        require(not cleanup, 'Required-reset lane cleanup failed: ' + str(cleanup))
        if receipt['status'] == 'passed':
            checks.append(copy.deepcopy(receipt))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prepare', action='store_true')
    parser.add_argument('--directory', type=Path, default=WORK / 'prepared-001')
    args = parser.parse_args()
    result = prepare_files(args.directory) if args.prepare else preparation()
    print(json.dumps(result, sort_keys=True, separators=(',', ':')))


if __name__ == '__main__':
    main()
