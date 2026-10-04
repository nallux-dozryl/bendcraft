#!/usr/bin/env python3
"""Read-only comparator for phase-reset-cases in the shared LocalPlayer binary.

No build, native launch, Java extraction or game-result arithmetic is available
here. The integration runner owns sealed producer/binary admission and receipts.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path

from build_native import Snapshot, source_graph
import test_local_phase_runtime as Phase

ROOT = Path(__file__).resolve().parents[1]
BASELINE = ROOT / 'build/local-player-reset-integration/baseline/manifest.json'
SOURCE = ROOT / 'src/local_phase_runtime.bend'
HARNESS = ROOT / 'tests/local_phase_reset.bend'
AIR_REFERENCE = ROOT / 'reference/local_travel_history.json'
PHASE_REFERENCE = ROOT / 'reference/local_phase_runtime.json'
FIXED_PINS = {
    'build/local-player-reset-integration/baseline/manifest.json': '22a651f1f6799390ce8031f9c5d6bea00e297815d24da73f6ebbc1f6606cb2a8',
    'tests/local_phase_runtime.bend': '9589c37194a807e01b3ac27eb4e83935ceaec4fba544b6fb05b00b1a9a2aeb22',
    'tools/test_local_phase_runtime.py': '4c2105a6f6283394bbd794e8db7ef9fd667ab35b85f5968b4dbe21c133bbb69d',
    'reference/local_phase_runtime.json': '6126038d6a5e3058e58dd0be100548cbeafce7b0f7cbede2075d9e2129ccdff7',
    'reference/local_travel_history.json': '07646e7fef0e55f3fd89421d1862b0e6dc5fdde3a0a84800b70b857a66609dbf',
    'reference/fall_reset_world.json': '5286ed1f9a8cfbb190d98f4ec8f67ef1e066910e7a5788aa3aef5570144a8014',
    'generated/reference_mth_sin.f32': 'cdfaec6870788e193dff3f1ddfa3ca7d3f1a897042d78365a1fe3a433be3627d',
}
AIR_CASES = [('reset:air-direct', False), ('reset:air-scheduled', True)]
REFUSALS = [
    ('reset:work-direct', False, 'local-phase-reset:reset-supplier:fall-reset-work-budget'),
    ('reset:work-scheduled', True, 'local-phase-reset:reset-supplier:fall-reset-work-budget'),
    ('reset:interior-direct', False, 'local-phase-reset:reset-supplier:fall-reset-outside-interior'),
    ('reset:interior-scheduled', True, 'local-phase-reset:reset-supplier:fall-reset-outside-interior'),
    ('reset:profile-direct', False, 'local-phase-reset:reset-supplier:fall-reset-tags-unresolved'),
    ('reset:profile-scheduled', True, 'local-phase-reset:reset-supplier:fall-reset-tags-unresolved'),
    ('reset:policy-tail', True, 'travel-request-tail:2'),
]
OWNER_FIELDS = ('body', 'support', 'minor', 'history', 'metadata', 'clock', 'queue',
                'sections', 'view', 'state-tail', 'motion-tail', 'table-sample')
OLD_FACADE = 'fd932047be8c476e812d15618a5b0b9a8c71bea62aef5cb69bed707703b77ec7'
ABILITIES_PROOF = ROOT / 'evidence/local-player-abilities-proof-001.json'
ABILITIES_PROOF_SHA = '9217624e78cd0073eb40c8b04be25a70ee2b96748bf246af4e15ef5ac7611f92'
OLD_RESUME = b'tick_result(X.resume_apply_checked(stage, status))'
RESET_RESUME = b'tick_result(X.resume_apply_with_reset_checked(stage, status, reset_policy()))'
RESET_IMPORT = b'import ./fall_reset_world.bend as FR\n'
RESET_POLICY = (
    b'\n# This bounded supplier policy is staged separately from apply_resolved. Native\n'
    b'# supplier admission precedes enabling the saved LocalPlayer resume entry.\n'
    b'def reset_policy() -> TH.ResetPolicy:\n'
    b'  TH.ResetPolicy{A.AABB{F.from_i32(4294967232), F.from_i32(4294967232), F.from_i32(4294967232), F.from_u32(64), F.from_u32(64), F.from_u32(64)},\n'
    b'    128n, FR.DefaultClientOverworldFourState{}, []}\n'
)


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def pin(path):
    data = Path(path).read_bytes()
    return {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}


def facade_generation():
    """Admit the original exact delta or the separately certified status generation."""
    archive = ROOT / 'build/local-player-reset-integration/baseline/src/local_player_runtime.bend'
    require(pin(archive)['sha256'] == OLD_FACADE, 'Original facade archive changed')
    current = (ROOT / 'src/local_player_runtime.bend').read_bytes()
    enabled = RESET_RESUME in current
    require(current.count(RESET_IMPORT) == current.count(RESET_POLICY) == 1,
            'Closed consumer reset policy is missing or duplicated')
    require(current.count(RESET_RESUME if enabled else OLD_RESUME) == 1,
            'Consumer resume route is missing or duplicated')
    stripped = current.replace(RESET_IMPORT, b'', 1).replace(RESET_POLICY, b'', 1)
    if enabled:
        stripped = stripped.replace(RESET_RESUME, OLD_RESUME, 1)
    preserved = stripped == archive.read_bytes()
    abilities = None
    if not preserved:
        require(pin(ABILITIES_PROOF)['sha256'] == ABILITIES_PROOF_SHA,
                'Certified abilities receipt changed')
        abilities = json.loads(ABILITIES_PROOF.read_text())
        require(abilities['status'] == 'PASS' and abilities['scope']['exclusions'] == []
                and abilities['independent_kernel']['process']['exit_code'] == 0
                and abilities['independent_kernel']['unchanged'],
                'Abilities whole-owner certificate is incomplete')
        for name, digest in abilities['production_source_pins'].items():
            require(pin(Path(name))['sha256'] == digest,
                    'Certified abilities production source changed: ' + name)
    return {'pin': pin(ROOT / 'src/local_player_runtime.bend'),
            'required_reset_enabled': enabled, 'old_facade_preserved_outside_admitted_delta': preserved,
            'certified_abilities_generation': abilities is not None,
            'abilities_proof': pin(ABILITIES_PROOF) if abilities is not None else None,
            'policy': {'whole_cell_interior': [-64, 64], 'read_work': 128,
                       'profile': 'DefaultClientOverworldFourState'}}


def contract():
    require(__debug__, 'Frozen component comparator assertions are disabled')
    for name, digest in FIXED_PINS.items():
        require(pin(ROOT / name)['sha256'] == digest, 'Frozen input changed: ' + name)
    baseline = json.loads(BASELINE.read_text())
    require(len(baseline['files']) == 14, 'Incomplete original baseline')
    for row in baseline['files']:
        require(pin(ROOT / row['archive']) == {'bytes': row['bytes'], 'sha256': row['sha256']},
                'Original archived baseline changed: ' + row['source'])
    old = (ROOT / 'build/local-player-reset-integration/baseline/src/local_phase_runtime.bend').read_bytes()
    old_prefix = SOURCE.read_bytes().startswith(old)
    facade = facade_generation()
    require(old_prefix or facade['certified_abilities_generation'],
            'X is outside both exact admitted source generations')
    compiler = Path('/Users/chuah/.bend/bin/bend')
    snapshot = Snapshot()
    source_graph(HARNESS, (compiler.resolve().parent.parent / 'bend2/base.bend').resolve(),
                 dict(os.environ), snapshot)
    return {'source': pin(SOURCE), 'harness': pin(HARNESS), 'tool': pin(__file__),
            'facade': facade,
            'baseline': pin(BASELINE), 'old_x_exact_prefix': old_prefix, 'old_x_bytes': len(old),
            'fixed': {name: pin(ROOT / name) for name in FIXED_PINS},
            'closure': snapshot.manifest(), 'compiler': pin(compiler),
            'scope': 'Existing independent component observations and project phase/rollback policies; no whole-tick required-ray Java oracle.'}


def parse(output):
    require(len(output.encode()) <= 32 * 1024 * 1024, 'Oversized focused transcript')
    rows, queries = {}, {}
    for line in output.splitlines():
        fields = line.split('|', 2)
        require(len(fields) == 3, 'Malformed focused transcript line')
        name, kind, value = fields
        if kind in ('early', 'late'):
            queries.setdefault((name, kind), []).append(value)
        else:
            require((name, kind) not in rows, 'Duplicate focused transcript field')
            rows[name, kind] = value
    require(rows.get(('local-phase-reset', 'complete')) == 'true', 'Focused transcript is incomplete')
    return rows, queries


def same_owner(rows, before, after):
    for kind in OWNER_FIELDS:
        require(rows[before, kind] == rows[after, kind], (before, after, kind))
    children = lambda prefix: {(name[len(prefix):], kind): value for (name, kind), value in rows.items()
                               if name.startswith(prefix + ':owned:') or name.startswith(prefix + ':motion-owned:')}
    require(children(before) == children(after), 'A refused stage changed an owned child')


def clock_policy(rows, name, scheduled):
    before = rows[name + '-before', 'clock'].split('|')
    anchor = rows[name + '-anchor', 'clock'].split('|')
    require(int(anchor[0]) == int(before[0]) + int(scheduled) and anchor[1:] == before[1:],
            'Wrong direct/postCommon anchor: ' + name)
    if not scheduled:
        same_owner(rows, name + '-before', name + '-anchor')
    else:
        feet = list(map(int, rows[name + '-before', 'body'].split('|')[:6]))
        metadata = Phase.parse_metadata(rows[name + '-anchor', 'metadata'])
        require(metadata['entity'] == feet + feet + [0, 1],
                'Scheduled air fixture did not retain exactly one common tick: ' + name)


def compare_air(rows, name, expected):
    require(rows[name, 'diagnostic'] == 'done' and (name, 'error') not in rows,
            'Air required-ray path failed: ' + name)
    require(rows[name + '-after', 'body'] == Phase.body(expected), 'Actual TH Body mismatch: ' + name)
    require(rows[name + '-after', 'history'] == Phase.text(Phase.words(expected['fall_distance_f64_bits'])),
            'Actual TH history mismatch, including duplicate accumulation: ' + name)
    require(rows[name + '-after', 'support'] == 'none|0' and rows[name + '-after', 'minor'] == '0',
            'Actual TH support/minor mismatch: ' + name)
    require(rows[name, 'ok'].split('|')[1:] == ['0', '0'], 'Unexpected air jump: ' + name)
    for kind in ('clock', 'queue', 'sections', 'state-tail', 'motion-tail', 'table-sample'):
        require(rows[name + '-anchor', kind] == rows[name + '-after', kind],
                'Local apply advanced an owner/clock twice: ' + name)


def compare_output(output):
    before = contract()
    rows, queries = parse(output)
    travel = json.loads(AIR_REFERENCE.read_text())
    air = next(case for case in travel['cases'] if case['id'] == 'air_miss')['steps'][0]
    require(air['ray_observation']['status'] == 'Miss' and air['travel_input'] == ['0000000000000000'] * 3,
            'Air source observation no longer binds this fixture')
    for name, scheduled in AIR_CASES:
        clock_policy(rows, name, scheduled)
        compare_air(rows, name, air['expected'])
    for name, scheduled, error in REFUSALS:
        clock_policy(rows, name, scheduled)
        require(rows[name, 'diagnostic'] == error, 'Exact refusal changed: ' + name)
        same_owner(rows, name + '-anchor', name + '-after')
        recovery = name + ':recovery'
        same_owner(rows, name + '-after', recovery + '-before')
        clock_policy(rows, recovery, False)
        compare_air(rows, recovery, air['expected'])
    for name, error in [('reset:owned-stage', 'local-player-tail:0'),
                        ('reset:pending-tail', 'local-player-request-tail')]:
        require(rows[name, 'diagnostic'] == error, 'Malformed stage refusal changed: ' + name)
        same_owner(rows, name + '-before', name + '-after')
    phase = json.loads(PHASE_REFERENCE.read_text())
    Phase.RP.integrity(phase)
    jump = Phase.RP.decode(next(case for case in phase['cases'] if case['id'] == 'scheduled_jump'))
    exact_jump = [Phase.compare_actual(jump, index, step, rows, queries)
                  for index, step in enumerate(jump['steps'])]
    require(contract() == before, 'Focused comparison generation drifted')
    return {'status': 'passed', 'contract': before, 'required_air_successes': len(AIR_CASES),
            'checked_failures_and_same_owner_recoveries': len(REFUSALS), 'preprovider_refusals': 2,
            'exact_actual_jump_steps': exact_jump, 'stdout_sha256': hashlib.sha256(output.encode()).hexdigest(),
            'air_scope': 'TH component-supported Body/support/minor/history. Hold0 omits the observed shift-only sneak probe; no whole-X airborne metadata oracle.',
            'phase_scope': 'Existing full scheduled_jump raw comparisons establish one prepare/jump/.98 decay/finish and common/rotation/late pose per step.'}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compare-stdout', type=Path)
    args = parser.parse_args()
    result = compare_output(args.compare_stdout.read_text()) if args.compare_stdout else contract()
    print(json.dumps(result, sort_keys=True, separators=(',', ':')))


if __name__ == '__main__':
    main()
