#!/usr/bin/env python3
"""Focused real Registry/Core publication and typed save-journal consumer.

Python constructs independent physical Core fixtures and literal expectations.
Every publication, block read, registry decode, owner query and journal update
under test executes in the production Bend modules. Native compilation uses the
already verified private single-emission producer, after its complete original
Book checker. Fresh generation directories preserve failed attempts.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
import shutil
import subprocess
from pathlib import Path

import test_campfire_authority as B
import test_nbt as N
import test_persistence as Persistence
import test_world_codec as W

ROOT = Path(__file__).resolve().parents[1]
ENTRY = ROOT / 'tests/cooking_effect_publication.bend'
TABLE = ROOT / 'generated/reference_blocks.tsv'
BINDINGS = ROOT / 'reference/cooking_world_bindings.tsv'
JAVA = ROOT / 'reference/cooking_effect_publication.json'
MAX_SEQUENCE = (1 << 48) - 1
POSITION = ['minecraft:overworld', 12, 8, 12]
PREFIX = 'cooking-publication:'


def pin(path):
    path = Path(path)
    data = path.read_bytes()
    return dict(path=str(path.resolve()), bytes=len(data), sha256=hashlib.sha256(data).hexdigest())


def binding(state=6884, *, block='minecraft:furnace'):
    assert state in (6883, 6884, 24119, 24120)
    if state in (24119, 24120):
        return dict(state=state, block='minecraft:blast_furnace', family='blasting', lit=state == 24119, dark=24120, bright=24119)
    return dict(state=state, block=block, family='smelting', lit=state == 6883, dark=6884, bright=6883)


def source(position=POSITION, state=6884, incarnation=2):
    return dict(position=list(position), binding=binding(state), incarnation=str(incarnation))


def chunk(position):
    return [position[0], ((position[1] if position[1] < 1 << 31 else position[1] - (1 << 32)) >> 4) & 0xffffffff,
            ((position[3] if position[3] < 1 << 31 else position[3] - (1 << 32)) >> 4) & 0xffffffff]


def receipt(position, captured, sequence):
    return dict(position=list(position), source=copy.deepcopy(captured), chunk=chunk(position), sequence=str(sequence))


def journal(sequence, chunks, last=None):
    return dict(sequence=str(sequence), unsaved=[dict(chunk=c, sequence=str(s)) for c, s in chunks], last=last)


def entry():
    return dict(length=3, frame=['smelting', 71, 1600, 83, 200, 0x80000000, 'minecraft:cooked_beef',
                               [['minecraft:cooked_beef', 7], ['minecraft:iron_ingot', 9]]],
                backing=[dict(id=i, count=c, components=p) for i, c, p in
                         [('minecraft:beef', 2, ''), ('minecraft:coal', 3, ''),
                          ('minecraft:cooked_beef', 5, ''), ('fixture:hidden-furnace', 31, 'raw\ttail')]])


def world(identity, writes, loaded=((0, 0, 0),)):
    model = W.empty_world(35723, identity)
    model.update(tick=42, day_time=1000, paused=False, daylight=False, revision=13)
    sections = {f'minecraft:overworld/{x & 0xffffffff}/{y & 0xffffffff}/{z & 0xffffffff}': [0] * 4096
                for x, y, z in loaded}
    for (x, y, z), state in writes.items():
        key = 'minecraft:overworld/' + '/'.join(str((v >> 4) & 0xffffffff) for v in (x, y, z))
        if key in sections:
            sections[key][(x & 15) + ((z & 15) << 4) + ((y & 15) << 8)] = state
    # Two colliding hash keys and a second dimension expose accidentally replaced
    # section maps; nonempty pending/events expose projected Core comparisons.
    for i, key in enumerate(W.COLLISION_KEYS):
        sections[key] = [3705 if i == 0 else 3708] * 4096
    sections['minecraft:the_nether/1/0/0'] = [1] * 4096
    model['sections'] = [dict(key=k, cells=tuple(c)) for k, c in sorted(sections.items())]
    model['pending'] = [dict(stamp=(1000, 7, 1), mutation=dict(kind=0, dimension='minecraft:overworld', x=160, y=0, z=0, state=3705)),
                        dict(stamp=(1001, 3, 100), mutation=dict(kind=2, day_time=999)),
                        dict(stamp=(1001, 3, 101), mutation=dict(kind=3, enabled=True))]
    model['events'] = [dict(stamp=(41, 9, 5), kind=1, error=dict(kind=3, key='minecraft:overworld/10/0/0')),
                       dict(stamp=(40, 1, 3), kind=0, revision=12)]
    raw = N.encode_root(W.snapshot_root(model))
    assert raw == N.encode_root(W.snapshot_root(W.validate(N.parse(raw), 35723, identity)))
    return raw


def prepare(directory):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    identity, count, registry_info = Persistence.registry_identity(TABLE)
    assert count == 35723
    header = BINDINGS.read_text().splitlines()[0].split('\t')
    assert header == ['pin', '26.3', identity, '35723']
    assert pin(BINDINGS)['sha256'] == '7f083e1ae13c83a20a576fcf1fd4b6f5c505b1e203eff691ffa2eacedcb8b290'
    java = json.loads(JAVA.read_text())
    assert java['pin'] == '26.3'
    observed = {r['id']: r for r in java['observations']['cases']}
    java_inputs = {r['id']: r for r in java['inputs']}
    defaults = {line.split('\t')[1]: int(line.split('\t')[4]) for line in TABLE.read_text().splitlines()[1:] if line}
    assert [defaults[i] for i in ('minecraft:air', 'minecraft:cave_air', 'minecraft:void_air')] == [0, 18650, 18649]
    assert defaults['minecraft:furnace'] == 6884 and defaults['minecraft:glass'] == 661
    cases = []

    def add(label, writes=None, *, position=POSITION, current=6884, gate='', sequence=17, repeats=1,
            status='done', loaded=((0, 0, 0),), java_id=None):
        writes = dict(writes or {tuple(position[1:]): current})
        path = directory / (label + '.nbt')
        path.write_bytes(world(identity, writes, loaded))
        captured = source(position)
        actual = source(position, current, 3 if gate == 'stale' else 2)
        if gate == 'current-position':
            actual['position'][1] += 1
        if gate == 'forged-current':
            actual['binding']['block'] = 'minecraft:blast_furnace'
        # Output's current comes from the real Entry query before request-only
        # forged source/current attestations, so it retains authenticated data.
        output_current = source(position, current, 3 if gate == 'stale' else 2)
        if gate == 'current-position':
            output_current['position'][1] += 1
        old_position = ['minecraft:the_nether', 144, 7, 176]
        old = journal(sequence, [(['minecraft:the_nether', 9, 11], sequence)],
                      receipt(old_position, source(old_position), sequence))
        final = old if status != 'done' else journal(sequence + repeats,
            [(chunk(position), sequence + repeats), (['minecraft:the_nether', 9, 11], sequence)],
            receipt(position, captured, sequence + repeats))
        expected = dict(label=label, status=status, core_retained=True, registry_retained=True,
                        entry_retained=True, entry=entry(), current=output_current, journal=final)
        cases.append(dict(label=label, path=str(path), position=list(position), source=6884, current=current,
                          gate=gate, sequence=sequence, repeats=repeats, expected=expected, java_case=java_id,
                          world=pin(path)))

    # Exact admitted Java receiver rows; unsupported notification domains remain
    # explicit atomic refusals, including glass that Java correctly skips.
    for label in ('air-only', 'air-kinds', 'vertical-comparators', 'already-dirty', 'repeated-mark'):
        inp, obs = java_inputs[label], observed[label]
        assert obs['dirty_after'] and not obs['notifications']
        writes = {tuple(w['position']): defaults[w['block']] for w in inp['writes']}
        add(label, writes, repeats=inp['repeats'], java_id=label)
    add('same-incarnation-lit', current=6883)
    add('different-authenticated-family', current=24120, status=PREFIX + 'stale-block-entity-incarnation')
    for gate, message in [('missing-current', 'current-block-entity-owner-required'),
                          ('stale', 'stale-block-entity-incarnation'),
                          ('current-position', 'stale-block-entity-incarnation'),
                          ('effect-position', 'source-position-mismatch'),
                          ('forged-source', 'unauthenticated-source-binding'),
                          ('forged-current', 'unauthenticated-source-binding')]:
        add(gate, gate=gate, status=PREFIX + message)
    add('core-wrong-state', {(12, 8, 12): 6883}, status=PREFIX + 'core-block-identity-or-state-mismatch')
    add('core-wrong-block', {(12, 8, 12): 1}, status=PREFIX + 'core-block-identity-or-state-mismatch')
    add('missing-target', loaded=(), status=PREFIX + 'loaded-cooker-required', java_id='missing-origin-chunk')
    add('missing-horizontal', position=['minecraft:overworld', 0, 8, 0], loaded=((0, 0, 0), (-1, 0, 0)),
        status=PREFIX + 'loaded-horizontal-neighbour-required', java_id='missing-north-chunk')
    for label in ('direct-comparators', 'conductor-comparator', 'conductor-air', 'nonconductor-comparator'):
        inp = java_inputs[label]
        writes = {tuple(w['position']): defaults[w['block']] for w in inp['writes']}
        add(label, writes, status=PREFIX + 'comparator-or-conductor-receiver-required', java_id=label)
    # Independently put each non-air receiver at each horizontal position so a
    # premature scan success cannot hide behind the first N/E/S/W cell.
    for direction, pos in [('east', (13, 8, 12)), ('south', (12, 8, 13)), ('west', (11, 8, 12))]:
        add('comparator-' + direction, {(12, 8, 12): 6884, pos: defaults['minecraft:comparator']},
            status=PREFIX + 'comparator-or-conductor-receiver-required')
    add('sequence-last-admitted', sequence=MAX_SEQUENCE - 1)
    add('sequence-exhausted', sequence=MAX_SEQUENCE, status=PREFIX + 'journal-sequence-exhausted')
    commands = ['|'.join(map(str, [c['label'], c['path'], *c['position'][1:], c['source'], c['current'],
                                  c['gate'], c['sequence'], c['repeats']])) for c in cases]
    input_path = directory / 'cases.txt'
    input_path.write_text('\n'.join(commands) + '\n')
    p, q = POSITION, ['minecraft:overworld', 28, 8, 12]
    captured = source(p)
    r3, r4 = receipt(q, source(q), 3), receipt(p, captured, 4)
    three = journal(3, [(chunk(q), 3), (chunk(p), 2)], r3)
    four = journal(4, [(chunk(p), 4)], r4)
    journal_cases = [dict(label=i, journal=copy.deepcopy(v)) for i, v in
                     [('journal-three', three), ('save-failed', three), ('save-old', three),
                      ('save-covered-prefix', four), ('save-future-refused', four),
                      ('save-invalid-chunk-refused', four), ('save-duplicate-chunks-refused', four),
                      ('save-zero-chunk-refused', four), ('save-coordinate-refused', four),
                      ('save-dimension-refused', four), ('save-image-duplicate-refused', four),
                      ('save-image-current', journal(4, [], r4)), ('save-image-keeps-live-owner', four),
                      ('save-current', journal(4, [], r4))]]
    valid = journal(3, [(chunk(p), 3)], receipt(p, source(p), 3))
    restore_cases = []
    def restored(label, value=None, error='invalid-recovered-journal'):
        restore_cases.append(dict(label=label, status='done' if value is not None else PREFIX + error,
                                  journal=copy.deepcopy(value)))
    restored('restore-empty', journal(0, []))
    restored('restore-valid', valid)
    restored('restore-clean-latest', journal(3, [], receipt(p, source(p), 3)))
    for label in ('future-chunk', 'duplicate-chunks', 'missing-last', 'wrong-position', 'wrong-chunk',
                  'wrong-last-sequence', 'zero-chunk', 'invalid-chunk-coordinate'):
        restored('restore-' + label)
    maximum_inc = copy.deepcopy(valid)
    maximum_inc['last']['source']['incarnation'] = str(MAX_SEQUENCE)
    restored('restore-max-incarnation', maximum_inc)
    restored('restore-authenticated', valid)
    restored('restore-forged-historical-binding', error='unauthenticated-source-binding')
    result = dict(cases=cases, journal_cases=journal_cases, input=pin(input_path),
                  restore_cases=restore_cases,
                  inputs=[pin(TABLE), pin(BINDINGS), pin(JAVA)], registry=registry_info,
                  java_admitted=5, java_refused_domain=6, reference_scope=java['validation']['boundary'])
    (directory / 'fixtures.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


def compare(prepared, stdout):
    actual = [json.loads(line) for line in Path(stdout).read_text().splitlines()]
    expected = [c['expected'] for c in prepared['cases']] + prepared['journal_cases'] + prepared['restore_cases']
    assert len(actual) == len(expected), (len(actual), len(expected))
    for value, want in zip(actual, expected, strict=True):
        assert value == want, dict(label=want['label'], actual=value, expected=want)
    return actual


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--phase', choices=('prepare', 'source', 'build', 'native', 'all'), default='prepare')
    parser.add_argument('--generation', type=int, default=1)
    args = parser.parse_args()
    work = ROOT / 'build/cooking-effect-publication-native' / f'{args.generation:03d}'
    evidence = ROOT / 'evidence' / f'cooking-effect-publication-native-{args.generation:03d}.json'
    B.WORK = work
    prepared = prepare(work)
    checks = []
    started_pins = {str(p): pin(p) for p in (ENTRY, Path(__file__), ROOT / 'tools/player_cooking_menu_emit.mjs')}
    try:
        if args.phase == 'prepare':
            print(json.dumps(dict(status='PREPARED_FILE_ONLY', publication_cases=len(prepared['cases']),
                                  journal_cases=len(prepared['journal_cases']), restore_cases=len(prepared['restore_cases']), work=str(work))))
            return
        if args.phase in ('source', 'all'):
            checks.append(B.run('source', [B.BEND, ENTRY, '--check-only'], 60, 2 * 1024 ** 3))
        if args.phase == 'source':
            print(json.dumps(dict(status='SOURCE_PASS', checks=checks)))
            return
        if args.phase in ('build', 'all'):
            assert not (work / 'receiver.c').exists() and not (work / 'receiver').exists(), 'Use a fresh generation for a changed build'
            checks.append(B.run('emit', ['/usr/bin/env', 'BEND_PRODUCER_LOG=' + str(work / 'emit-functions.jsonl'),
                                        'BEND_PRODUCER_GC=1', B.NODE, '--expose-gc', '--max-old-space-size=8192',
                                        '--stack-size=4096', '--experimental-transform-types',
                                        ROOT / 'tools/player_cooking_menu_emit.mjs', ENTRY, work / 'receiver.c'], 600, 8 * 1024 ** 3))
            checks.append(B.run('clang', [shutil.which('clang') or '/usr/bin/clang', '-std=c11', '-O1',
                                         work / 'receiver.c', '-lpthread', '-lm', '-o', work / 'receiver'], 300, 3 * 1024 ** 3))
        if args.phase == 'build':
            print(json.dumps(dict(status='BUILD_PASS', binary=pin(work / 'receiver'), checks=checks)))
            return
        if args.phase == 'native':
            checks = [json.loads((work / (name + '.json')).read_text()) for name in ('source', 'emit', 'clang')
                      if (work / (name + '.json')).exists()]
        compiled = json.loads((work / 'receiver.c.sources.json').read_text())
        critical = {str(ENTRY), str(ROOT / 'src/cooking_effect_publication.bend'),
                    str(ROOT / 'src/cooking_effect_publication_journal.bend')}
        assert all(pin(path)['sha256'] == compiled['source_sha256'][path] for path in critical), 'Focused publication source changed before native comparison'
        # The emitted artifact remains pinned to its complete checked graph.
        # Concurrent unrelated actor joins may legitimately change imports after
        # emission; expose that difference without rebuilding the same artifact.
        imported_drift = [dict(path=path, compiled_sha256=value, current_sha256=pin(path)['sha256'])
                          for path, value in compiled['source_sha256'].items() if pin(path)['sha256'] != value]
        for thread_count in (1, 4):
            checks.append(B.run('native-' + str(thread_count), [work / 'receiver', '--gpu', 'off', '--threads', str(thread_count),
                              TABLE, BINDINGS, prepared['input']['path']], 120, 1024 ** 3))
            compare(prepared, work / ('native-' + str(thread_count) + '.stdout'))
        assert (work / 'native-1.stdout').read_bytes() == (work / 'native-4.stdout').read_bytes()
        assert all(pin(row['path']) == row for row in prepared['inputs']), 'Reference input changed during native run'
        assert all(pin(path) == value for path, value in started_pins.items()), 'Owned consumer changed during native run'
        live = subprocess.check_output(['ps', '-axo', 'pid,command'], text=True).splitlines()[1:]
        owned_live = [line.strip() for line in live if str(work) in line and int(line.split(None, 1)[0]) != os.getpid()]
        assert not owned_live, ('Owned receiver/compiler process remained live', owned_live)
        result = dict(status='PASS_NARROW', publication_cases=len(prepared['cases']), journal_cases=len(prepared['journal_cases']),
                      restore_cases=len(prepared['restore_cases']), native_incarnation_overflow='Not representable beyond verified native48 domain; maximum value admitted, encoded range refusal belongs to fmt4 codec consumer.',
                      threads=[1, 4], exact_thread_outputs=True, checks=checks,
                      inputs=prepared['inputs'], fixtures=pin(work / 'fixtures.json'),
                      source_sha256=compiled['source_sha256'], source_manifest=pin(work / 'receiver.c.sources.json'),
                      post_emission_import_drift=imported_drift, owned_processes_gone=True,
                      emitted_c=pin(work / 'receiver.c'), binary=pin(work / 'receiver'),
                      java_admitted_receiver_rows=prepared['java_admitted'], java_refused_domains=prepared['java_refused_domain'],
                      scope='Actual authenticated full Registry and bindings; real loaded Core reads/decode; complete Core bytes, registry identity, actual Store.Entry four-cell backing, frame, and journal retained. Same-incarnation LIT switch preserves producer cached source. Typed full-save completion hook only; no actual writer, actor/network integration, comparator scheduling or whole-block publication parity claim.')
        assert not evidence.exists(), 'Earlier receipt remains immutable'
        evidence.write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps(dict(status=result['status'], publication_cases=result['publication_cases'],
                              journal_cases=result['journal_cases'], restore_cases=result['restore_cases'], evidence=str(evidence))))
    except BaseException as error:
        failure = dict(status='FAIL', phase=args.phase, error=repr(error), checks=checks, inputs=prepared['inputs'],
                       consumer_pins=started_pins, work=str(work))
        path = work / ('failure-' + args.phase + '.json')
        assert not path.exists(), 'Failure receipt remains immutable; use a fresh generation'
        path.write_text(json.dumps(failure, indent=2) + '\n')
        raise


if __name__ == '__main__':
    main()
