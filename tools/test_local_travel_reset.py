#!/usr/bin/env python3
"""Shared-artifact reset comparison. Host code encodes/compares actual fixtures.

No compiler, Java, native process or game algorithm is invoked by this driver.
The root composite runner supplies the explicitly admitted executor to suite().
"""
from __future__ import annotations
import argparse, ast, copy, hashlib, json, re, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'src/local_travel_history.bend'
HARNESS = ROOT / 'tests/local_travel_reset.bend'
WORK = ROOT / 'build/local-travel-reset'
BASELINE = ROOT / 'build/local-player-reset-integration/baseline/src/local_travel_history.bend'
REFERENCES = {name: ROOT / f'reference/{name}.json' for name in (
    'local_travel_history', 'local_move_history', 'fall_reset_world')}
IMPORTS = (b'import ./fall_reset_world.bend as FR\n'
           b'import ./geometry.bend as A\nimport ./f64.bend as F\n')

def canonical(value):
    return json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(',', ':'), allow_nan=False).encode()

def digest(value):
    return hashlib.sha256(canonical(value)).hexdigest()

def pin(path):
    path = Path(path); raw = path.read_bytes()
    return {'path': str(path.relative_to(ROOT)), 'bytes': len(raw),
            'sha256': hashlib.sha256(raw).hexdigest()}

def helpers():
    # Existing pinned serializers/comparators only. Never call their producers,
    # integrity JVM probes, builders or process runners.
    import test_local_travel_history as old
    import test_local_move_world as movement
    return old, movement

def load():
    return {name: json.loads(path.read_text()) for name, path in REFERENCES.items()}

def preserved_units():
    old = BASELINE.read_bytes(); current = SOURCE.read_bytes()
    assert current.count(IMPORTS) == 1
    stripped = current.replace(IMPORTS, b'', 1)
    assert stripped.startswith(old), 'Original TH bytes changed'
    # Identical unit text implies identical parsed unit contents; the compiler
    # parser is not run here. Source-position metadata necessarily changes.
    units = re.findall(rb'^(type|def|law) ([^\n]+)', old, re.M)
    return {'baseline': pin(BASELINE), 'original_bytes': len(old),
            'old_units': len(units), 'old_unit_headers_sha256': digest([
                [a.decode(), b.decode()] for a, b in units]),
            'original_body_exact_prefix_after_three_imports_removed': True,
            'ast_scope': 'Old unit text is identical; no new compiler-AST check claimed.'}

def policy_words(work=64, profile=0, interior=None):
    _, d = helpers()
    interior = interior if interior is not None else d.INTERIOR
    # Binary word formatting is protocol encoding, never endpoint arithmetic.
    return d.words([d.bits(v) for v in interior]) + [work, profile]

def request(step, id, install=False, shape=0, work=64, profile=0,
            ray_interior=None, **changes):
    old, _ = helpers()
    parts = old.request(step, id, install, shape=shape, **changes).split(';')
    parts[0] = f'{id}|reset|{int(install)}|{shape}'
    return ';'.join(parts + [old.group(policy_words(work, profile, ray_interior))])

def ray_request(step, id, work=64, profile=0, ray_interior=None):
    old, d = helpers()
    seed = d.seed_words(step['before']) + d.words([step['before']['fall_distance_f64_bits']])
    return ';'.join([f'{id}|ray-phase|{int(step["position_application_gate_entered"])}',
        old.group(d.body_words(step['before'])), old.group(d.body_words(step['expected'])),
        old.group(d.words(step['resolved'])), old.group(seed),
        old.group(policy_words(work, profile, ray_interior))])

def split_output(stdout):
    _, d = helpers(); ordinary = []; reads = {}
    for line in stdout.splitlines():
        fields = line.split('|')
        if len(fields) >= 2 and fields[1] == 'ray-read':
            reads.setdefault(fields[0], []).append(fields[2:])
        else: ordinary.append(line)
    return (*d.lines('\n'.join(ordinary)), reads)

def compare_ray(case, id, values, reads):
    _, d = helpers()
    assert case['actual_returned'] and case['admission']['supported']
    assert case['result']['type'] == 'MISS' and values[id, 'ray'] == ['miss']
    for field, expected in [('from', case['from']), ('to', case['to']),
                            ('expanded-from', case['expanded']['start']),
                            ('expanded-to', case['expanded']['end'])]:
        assert d.raw64(values[id, 'ray-' + field]) == expected, (id, field)
    ids = d.palette(values, id)
    expected_reads = [[str(i), {'BlockSample': 'block', 'FluidSource': 'fluid-source'}[row['phase']],
        ','.join(str(v & 0xffffffff) for v in row['position']), str(ids[row['block_id']])]
        for i, row in enumerate(case['reads'])]
    assert reads.get(id, []) == expected_reads, (id, 'actual ordered block/fluid reads')
    return {'id': id, 'actual_ray_fixture': case['id'], 'reads': len(expected_reads),
            'old_feet_endpoints_raw_exact': True, 'ordered_reads_raw_exact': True}

def selected(data):
    rays = {c['id']: c for c in data['fall_reset_world']['cases']}
    whole = [c for c in data['local_travel_history']['cases'] if c['id'] in {
        'air_miss', 'air_miss_history', 'floor', 'negative_zero', 'gate_skip',
        'gate_tiny', 'air_zero_history'}]
    phase = []
    for c in data['local_move_history']['cases']:
        for i, step in enumerate(c['steps']):
            key = f'local_move_history:{c["id"]}:{i}'
            if key in rays: phase.append((key, step, rays[key]))
    assert len(phase) == 2
    required = [f'local_travel_history:{c["id"]}:{i}' for c in whole
        for i, s in enumerate(c['steps']) if s['ray_observation']['status'] == 'Miss']
    assert len(required) == 5 and all(k in rays for k in required)
    return whole, phase, rays

def planned(data):
    old, d = helpers(); whole, phase, rays = selected(data); jobs = []
    for c in whole:
        commands = d.edits(c['initial']['world_writes'], 'initial-edit')
        ids = []
        for i, s in enumerate(c['steps']):
            id = c['id'] + ':' + str(i); ids.append(id)
            commands += d.edits(s['world_writes'], 'step-edit:' + str(i)) + [request(s, id, i == 0)]
        jobs.append({'label': 'travel:' + c['id'], 'scope': 'actual-whole-travel',
                     'commands': commands + ['final|table-probe'], 'ids': ids})
    for key, step, ray in phase:
        jobs.append({'label': 'phase:' + key, 'scope': 'actual-MH-endpoint-supplier-only',
                     'commands': d.edits(step['world_writes'], 'write') + [ray_request(step, key), 'final|table-probe'], 'ids': [key]})
    return jobs

def compare_job(data, job, stdout):
    old, d = helpers(); values, queries, colliders, support, reads = split_output(stdout)
    whole, phase, rays = selected(data); rows = []
    assert values['final', 'table-owner'] == ['0']
    if job['scope'] == 'actual-whole-travel':
        case = next(c for c in whole if job['label'] == 'travel:' + c['id'])
        for i, step in enumerate(case['steps']):
            id = case['id'] + ':' + str(i)
            row = old.compare(step, id, values, queries, colliders, support)
            key = 'local_travel_history:' + id
            if step['ray_observation']['status'] == 'Miss': row['checked_ray'] = compare_ray(rays[key], id, values, reads)
            else:
                assert values[id, 'ray'] == ['not-required'] and not reads.get(id)
                assert not any((id, k) in values for k in ['ray-from', 'ray-to', 'ray-expanded-from', 'ray-expanded-to'])
                row['no_supplier_observation_or_reads'] = True
            rows.append(row)
    else:
        key, step, ray = next(row for row in phase if job['label'] == 'phase:' + row[0])
        old.same_owner(values, key)
        rows.append({**compare_ray(ray, key, values, reads),
                     'scope': 'Actual MH endpoint/supplier phase only; no synthesized travel expectation.'})
    return rows

def policy_jobs(data):
    old, d = helpers(); whole, phase, rays = selected(data)
    miss = next(c['steps'][0] for c in whole if c['id'] == 'air_miss')
    base = next(c['steps'][0] for c in whole if c['id'] == 'floor')
    specs = []
    def add(id, error, step=miss, setup=None, cleanup=None, **options):
        specs.append({'id': id, 'error': error, 'step': step,
                      'setup': setup or [], 'cleanup': cleanup or [], 'options': options})
    add('ray-work-zero', 'reset-supplier:fall-reset-work-budget', work=0)
    add('ray-work-partial', 'reset-supplier:fall-reset-work-budget', work=4)
    add('ray-profile', 'reset-supplier:fall-reset-tags-unresolved', profile=1)
    add('ray-interior', 'reset-supplier:fall-reset-outside-interior', ray_interior=[-1., 9., -1., 2., 12., 2.])
    add('ray-interior-nan', 'reset-supplier:fall-reset-invalid-interior', ray_interior=[float('nan'), -64., -64., 64., 64., 64.])
    for shape, field in [(1, 0), (2, 1), (3, 2)]: add('noncanonical:' + str(shape), 'noncanonical-request:' + str(field), shape=shape)
    add('unsupported-travel', 'prepare:unsupported-context', context_changes={17: 1})
    add('unsupported-move', 'movement:move:local-move-context:4', hooks_changes={14: 1})
    add('history-nan', 'reset-history:nonfinite:0', history='7ff8000000000001')
    add('missing-world', 'movement:move:', setup=['missing|empty-sections'], cleanup=['repair|repair-sections'])
    add('unknown-world', 'movement:move:unsupported-block-state:', setup=['unknown|edit|0|9|0|4'], cleanup=['repair|edit|0|9|0|0'])
    for id, op, error in [('palette-absent', 'no-palette', 'edge-palette-unavailable'), ('palette-stale', 'stale-palette', 'edge-palette-stale')]:
        add(id, 'movement:move:' + error, setup=[id + '|' + op], cleanup=['repair|palette-refresh'])
    add('pending-ray-work', 'reset-supplier:fall-reset-work-budget', setup=['clock|clock','running|running','pending|pending','warm|warm'], work=2)
    jobs = []
    for spec in specs:
        id = spec['id']; step = spec['step']
        commands = d.edits(step['world_writes'], 'write') + spec['setup'] + [request(step, id, True, **spec['options'])]
        reseed = id == 'history-nan'
        recovery = base if reseed else step
        commands += spec['cleanup'] + [request(recovery, 'recovery', reseed), 'final|table-probe']
        jobs.append({'label': 'policy:' + id, 'scope': 'checked-policy-rollback-recovery',
                     'commands': commands, 'error': spec['error'], 'id': id, 'recovery': recovery,
                     'recovery_without_state_reseeding': not reseed})
    # Bad ray policy is intentionally unused on the actual no-ray branch.
    for c in whole:
        if c['id'] in {'floor', 'gate_skip', 'negative_zero', 'air_zero_history'}:
            step = c['steps'][0]; id = 'unused-policy:' + c['id']
            jobs.append({'label': id, 'scope': 'actual-no-ray-unused-policy',
                'commands': d.edits(step['world_writes'], 'write') + [request(step, id, True, work=0, profile=1,
                    ray_interior=[float('nan'), 0., 0., 0., 0., 0.]), 'final|table-probe'], 'id': id, 'step': step})
    # Late finish injection is a named checked-branch test, never Java parity.
    jobs.append({'label': 'policy:late-finish', 'scope': 'checked-policy-rollback-recovery',
        'id': 'late-finish', 'error': 'finish:invalid-context:99', 'recovery': base,
        'commands': [request(base, 'initialize', True), 'late-finish|finish-fail', request(base, 'recovery', True), 'final|table-probe']})
    jobs.append({'label': 'policy:owned-tail', 'scope': 'checked-policy-rollback-recovery',
        'id': 'owned-tail', 'error': 'noncanonical-state', 'recovery': base, 'child': True,
        'commands': [request(base, 'initialize', True), 'nested|nest', request(base, 'owned-tail'), 'select|select-child', request(base, 'recovery', True), 'final|table-probe']})
    # Source-world errors in the required supplier phase from actual MH data.
    key, step, ray = phase[0]
    for name, setup, cleanup, error in [
        ('supplier-missing', ['missing|empty-sections'], ['repair|repair-sections'], 'reset-supplier:'),
        ('supplier-unknown', ['unknown|edit|0|9|0|4'], ['repair|edit|0|9|0|0'], 'reset-supplier:')]:
        jobs.append({'label': 'policy:' + name, 'scope': 'supplier-phase-rollback-recovery', 'id': name,
            'error': error, 'ray': ray, 'recovery_id': 'recovery',
            'commands': setup + [ray_request(step, name)] + cleanup + [ray_request(step, 'recovery'), 'final|table-probe']})
    return jobs

def compare_policy(job, stdout):
    old, d = helpers(); p, q, c, s, reads = split_output(stdout); id = job['id']
    assert p['final', 'table-owner'] == ['0']
    if job['scope'] == 'actual-no-ray-unused-policy':
        row = old.compare(job['step'], id, p, q, c, s)
        assert p[id, 'ray'] == ['not-required'] and not reads.get(id)
        return {**row, 'unused_policy_not_admitted_or_read': True}
    old.same_owner(p, id, child=job.get('child', False))
    assert p[id, 'error'][0].startswith(job['error']), (id, job['error'], p[id, 'error'])
    assert not q.get(id) and not c.get(id) and not s.get(id) and not reads.get(id)
    if job['scope'] == 'supplier-phase-rollback-recovery':
        old.same_owner(p, 'recovery'); compare_ray(job['ray'], 'recovery', p, reads)
    else:
        old.compare(job['recovery'], 'recovery', p, q, c, s)
        if job['recovery']['ray_observation']['status'] == 'Miss':
            data = load()
            matching = [ray for ray in data['fall_reset_world']['cases'] if ray['id'].startswith('local_travel_history:')
                and ray['from'] == job['recovery']['before']['position']
                and ray['to'] == job['recovery']['ray_observation']['clip_calls'][0]['to']]
            assert matching, 'Recovery must have an existing actual ray observation'
            compare_ray(matching[0], 'recovery', p, reads)
        else:
            assert p['recovery', 'ray'] == ['not-required'] and not reads.get('recovery')
    return {'id': id, 'actual_error': p[id, 'error'][0], 'complete_prior_owner_retention': True,
            'returned_world_tables_reused': True, 'child_owner_reused': job.get('child', False),
            'recovery_without_state_reseeding': job.get('recovery_without_state_reseeding', False),
            'scope': job['scope']}

def suite(executor):
    """executor(label,commands,env) is the root's admitted shared-artifact lane.

    The caller retains complete argv/process/artifact/closure receipts. This
    module supplies protocol words and actual-observation comparisons only.
    """
    data = load(); rows = []; policies = []; receipts = []
    for job in planned(data):
        stdout, receipt = executor(job['label'], job['commands'], None)
        rows += compare_job(data, job, stdout); receipts.append(receipt)
    for job in policy_jobs(data):
        stdout, receipt = executor(job['label'], job['commands'], None)
        policies.append(compare_policy(job, stdout)); receipts.append(receipt)
    return {'rows': rows, 'policies': policies, 'receipts': receipts,
            'scope': 'Five actual required whole-travel calls plus two MH endpoint/supplier phases; no full tick claim.'}

def prepare():
    data = load(); jobs = planned(data); policies = policy_jobs(data)
    for job in jobs + policies:
        for command in job['commands']:
            parts = command.split(';')
            if len(parts) == 8: assert [len(p.split('|')) for p in parts] == [4,30,18,6,18,14,8,14]
            elif len(parts) == 6: assert [len(p.split('|')) for p in parts] == [3,30,30,6,8,14]
    WORK.mkdir(parents=True, exist_ok=True)
    raw = WORK / 'plan.json'; raw.write_bytes(canonical({'jobs': jobs, 'policies': policies}) + b'\n')
    report = {'status': 'source-and-file-prepared-no-native-or-kernel',
        'source': pin(SOURCE), 'harness': pin(HARNESS), 'driver': pin(Path(__file__)),
        'references': {name: pin(path) for name, path in REFERENCES.items()},
        'baseline_preservation': preserved_units(), 'plan': pin(raw),
        'actual_required_travel_calls': 5, 'actual_MH_supplier_phases': 2,
        'actual_whole_travel_calls': sum(len(j['ids']) for j in jobs if j['scope'] == 'actual-whole-travel'),
        'policy_processes': len(policies), 'shared_dispatch': 'travel-reset-cases',
        'proposed_ordinary_commands': [f'/Users/chuah/.bend/bin/bend {p} --check-only' for p in ['src/local_travel_history.bend','tests/local_travel_reset.bend']],
        'native_plan': 'Root shared LocalPlayer composite only; no standalone build mode.',
        'no_host_game_result_arithmetic': True, 'no_generator_or_process_execution': True}
    path = ROOT / 'evidence/local-travel-reset-preparation.json'; path.write_bytes(canonical(report) + b'\n')
    return report

def main():
    parser = argparse.ArgumentParser(); parser.add_argument('--prepare', action='store_true')
    parser.parse_args(); report = prepare()
    print(json.dumps({k: report[k] for k in ['status','actual_required_travel_calls','actual_MH_supplier_phases','actual_whole_travel_calls','policy_processes','shared_dispatch']}))

if __name__ == '__main__': main()
