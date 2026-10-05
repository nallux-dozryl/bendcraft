#!/usr/bin/env python3
"""Check actual manager/T.State recovery laws with unchanged independent-kernel IR."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import signal
import subprocess
import sys
import time

from reference_inventory import fingerprint, write_json

ROOT = pathlib.Path(__file__).resolve().parents[1]
KERNEL = pathlib.Path('/Users/chuah/.bend/bendtt/e15042434e73aab0/bendtt')
NODE = pathlib.Path('/opt/homebrew/Cellar/node/23.5.0/bin/node')
BEND = pathlib.Path('/Users/chuah/.bend/bin/bend')
COMPILER = ROOT.parent / 'bend/bend2'
EXPORTER = ROOT / 'tools/entity_section_membership_recovery_proof.mjs'
EVIDENCE = ROOT / 'evidence/entity-section-membership-recovery-proof.json'
SCOPE = ('Only the actual entity_section_membership_recovery_laws theorem roots listed in this receipt '
         'are independently checked, with their complete unchanged production dependency closure '
         'and zero export exclusions. These laws cover full manager and T.State rollback/recovery '
         'owner retention and activation branches. Native/reference parity, save IO and rendering '
         'are separate evidence. Numeric Nat48 capacity, constructor_cursor and constructor_ready '
         'guard semantics, and their fresh_prepare wrapper consequences remain unproved here.')
UNPROVED_OBLIGATIONS = [
    'constructor_cursor_accepts_exactly_one_advance',
    'constructor_cursor_refuses_any_disagreeing_advance',
    'invalid_constructor_cursor_preserves_both_complete_owners',
    'constructor_cursor_exhaustion_refuses_before_addition',
    'exhausted_constructor_cursor_preserves_both_complete_owners',
    'constructor_preflight_refuses_exhausted_retained_cursor',
]
UNPROVED_REASON = ('These proposed goals were removed from the active laws/proof target after '
                   'the original checker raised RangeError in term_higher/compare_go while '
                   'converting actual Nat48 capacity/cursor wrappers, including with a 32 MiB '
                   'Node stack. They are not export exclusions or passed theorem roots.')


def require(condition, message):
    if not condition:
        raise AssertionError(message)


def path_pin(path):
    return {'path': str(path.resolve()), **fingerprint(path)}


def toolchain_pins():
    paths = [BEND, NODE, KERNEL, EXPORTER, pathlib.Path(__file__), pathlib.Path(sys.executable),
             ROOT / 'tools/reference_inventory.py',
             *[COMPILER / name for name in ['bend.ts', 'safe.ts', 'base.bend', 'bendtt.lean']],
             BEND.parent.parent / 'bend2/base.bend', KERNEL.parent / 'bendtt.lean']
    pins = [path_pin(path) for path in paths]
    kernel_source = fingerprint(KERNEL.parent / 'bendtt.lean')['sha256']
    require(kernel_source[:16] == KERNEL.parent.name, 'Pinned kernel source hash does not match cache identity')
    require(fingerprint(COMPILER / 'bendtt.lean')['sha256'] == kernel_source,
            'Compiler exporter and pinned independent-kernel source versions differ')
    return pins


def verify_toolchain(pins):
    for pin in pins:
        require(path_pin(pathlib.Path(pin['path'])) == pin, 'Toolchain changed: ' + pin['path'])


def verify_sources(pins):
    require(isinstance(pins, dict) and pins, 'Missing loaded production source pins')
    for name, expected in pins.items():
        path = pathlib.Path(name)
        require(path.is_absolute() and str(path.resolve()) == name, 'Production source alias changed: ' + name)
        require(hashlib.sha256(path.read_bytes()).hexdigest() == expected, 'Production source changed: ' + name)


class RunnerTerminated(RuntimeError):
    pass


def checked_run(argv, folder, name, timeout):
    # Based on test_player_motion_current.run, with interruption cleanup added:
    # every spawned process has an isolated group and a retained phase receipt.
    started = time.monotonic()
    process = subprocess.Popen([str(value) for value in argv], cwd=ROOT, text=True,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
    timed_out, interrupted = False, None

    def kill_group():
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    def terminated(signum, frame):
        # selectors retries InterruptedError, so use a distinct exception.
        raise RunnerTerminated('Bounded runner received signal ' + str(signum))

    previous_term = signal.signal(signal.SIGTERM, terminated)
    try:
        try:
            stdout, stderr = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            kill_group()
            stdout, stderr = process.communicate()
        except BaseException as error:
            interrupted = error
            kill_group()
            stdout, stderr = process.communicate()
    finally:
        signal.signal(signal.SIGTERM, previous_term)

    try:
        os.killpg(process.pid, 0)
    except ProcessLookupError:
        group_absent = True
    else:
        group_absent = False
        kill_group()
    (folder / (name + '.stdout')).write_text(stdout)
    (folder / (name + '.stderr')).write_text(stderr)
    receipt = {
        'argv': [str(value) for value in argv], 'pid': process.pid, 'exit_code': process.returncode,
        'seconds': round(time.monotonic() - started, 6), 'timed_out': timed_out,
        'group_absent': group_absent, 'interrupted': repr(interrupted) if interrupted else None,
        'stdout': fingerprint(folder / (name + '.stdout')), 'stderr': fingerprint(folder / (name + '.stderr')),
    }
    write_json(folder / (name + '.json'), receipt)
    if interrupted:
        raise interrupted
    require(not timed_out and process.returncode == 0 and group_absent, receipt)
    return stdout, receipt


def retained_receipts(folder):
    # checked_run() retains its receipt before raising; include the failed phase too.
    return [json.loads((folder / (name + '.json')).read_text())
            for name in ['source-and-export', 'independent-kernel']
            if (folder / (name + '.json')).exists()]


def available_artifacts(folder):
    return {name: fingerprint(folder / name) for name in [
        'toolchain-pins.json', 'loaded-source-pins.json', 'selection.json', 'scope.json',
        'source-pins.json', 'selected.bendtt', 'export-failure.json'] if (folder / name).exists()}


def publish(folder, evidence):
    write_json(folder / 'result.json', evidence)
    # Keep the authoritative summary whole even if the host interrupts a write.
    temporary = EVIDENCE.with_name(EVIDENCE.name + '.' + folder.name + '.tmp')
    write_json(temporary, evidence)
    temporary.replace(EVIDENCE)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--generation', type=int, help='Optional caller generation label; does not change proof scope')
    parser.add_argument('--export-timeout', type=int, default=180, help='Bound original source check/export in seconds')
    parser.add_argument('--kernel-timeout', type=int, default=60, help='Bound independent-kernel checking in seconds')
    args = parser.parse_args()
    require(args.export_timeout > 0 and args.kernel_timeout > 0, 'Timeouts must be positive')
    folder = ROOT / 'build/entity-section-membership-recovery-proof' / str(time.time_ns())
    folder.mkdir(parents=True, exist_ok=False)
    phase, pins, source_pins, selection = 'toolchain-pins', [], {}, None
    try:
        pins = toolchain_pins()
        write_json(folder / 'toolchain-pins.json', pins)
        phase = 'source-and-export'
        checked_run([NODE, '--experimental-transform-types', '--stack-size=6144', EXPORTER, folder],
                    folder, phase, args.export_timeout)
        selection = json.loads((folder / 'selection.json').read_text())
        scope = json.loads((folder / 'scope.json').read_text())
        source_pins = json.loads((folder / 'source-pins.json').read_text())
        declared = selection['declared_law_roots']
        roots = selection['roots']
        require(roots and len(roots) == len(set(roots)) and set(roots) == set(declared),
                'Selected roots differ from actual source law declarations')
        require(not any(root.rsplit(':', 1)[-1] in UNPROVED_OBLIGATIONS for root in roots),
                'Unproved-obligation metadata conflicts with the checked theorem roots')
        require(selection['selected_root_count'] == len(roots), 'Wrong dynamic theorem count')
        require(selection['holes'] == 0 and selection['original_book_loads'] == 1 and
                selection['original_book_checks'] == 1 and selection['ordinary_source_api_check_passed'],
                'Original production book was not checked exactly once without holes')
        require(selection['checked_types_and_bodies_unchanged'] and
                selection['all_original_tlds_ctrs_tmps_retained'] and
                selection['root_selection_only_changes_order'], 'Original checked declaration ownership changed')
        require(scope['exclusions'] == [], 'Selected theorem closure has export exclusions')
        require([term['name'] for term in selection['term_pins']] == roots, 'Missing actual theorem term pins')
        require(selection['base_source'] in source_pins, 'Actual compiler Base source is not pinned')
        for name in selection['required_production_sources']:
            require(name in source_pins, 'Actual production source is not pinned: ' + name)
        verify_sources(source_pins)
        verify_toolchain(pins)

        phase = 'independent-kernel'
        artifact = fingerprint(folder / 'selected.bendtt')
        stdout, _ = checked_run(['/usr/bin/env', 'LEAN_STACK_SIZE_KB=4194304', KERNEL, folder / 'selected.bendtt'],
                                folder, phase, args.kernel_timeout)
        require(stdout.strip() == 'ALL PROOFS CHECK', 'Independent kernel did not accept every selected law: ' + stdout)
        require(fingerprint(folder / 'selected.bendtt') == artifact, 'Checked independent-kernel artifact changed')
        verify_sources(source_pins)
        verify_toolchain(pins)
        evidence = {
            'status': 'passed', 'generation': args.generation, 'folder': str(folder),
            'laws': len(roots), 'roots': roots, 'scope_exclusions': [],
            'ordinary_source_api_check_passed': True, 'independent_kernel_passed': True,
            'original_book_loads': 1, 'original_book_checks': 1,
            'checked_types_and_bodies_unchanged': True, 'all_original_declaration_maps_retained': True,
            'source_files': source_pins, 'source_pins': fingerprint(folder / 'source-pins.json'),
            'term_pins': selection['term_pins'], 'receipts': retained_receipts(folder),
            'selection': fingerprint(folder / 'selection.json'), 'artifact': artifact,
            'kernel': path_pin(KERNEL), 'node': path_pin(NODE), 'export_script': path_pin(EXPORTER),
            'compiler_api': [path_pin(COMPILER / name) for name in ['bend.ts', 'safe.ts']],
            'base': path_pin(pathlib.Path(selection['base_source'])), 'toolchain': pins,
            'retained_artifacts': available_artifacts(folder), 'scope': SCOPE,
            'unproved_obligations': UNPROVED_OBLIGATIONS,
            'unproved_reason': UNPROVED_REASON,
            'failed_original_source_snapshot': str(ROOT / 'build/entity-section-membership-recovery-proof/'
                                                  '1791172144728096000/failed-source-snapshot.json'),
        }
        publish(folder, evidence)
        print(json.dumps({'status': 'passed', 'generation': args.generation, 'folder': str(folder),
                          'laws': len(roots), 'artifact_bytes': artifact['bytes'],
                          'scope_exclusions': [], 'seconds': [row['seconds'] for row in evidence['receipts']]}))
    except BaseException as error:
        if not source_pins and (folder / 'loaded-source-pins.json').exists():
            source_pins = json.loads((folder / 'loaded-source-pins.json').read_text())
        receipts = retained_receipts(folder)
        if selection is None and (folder / 'selection.json').exists():
            selection = json.loads((folder / 'selection.json').read_text())
        failure = {
            'status': 'failed', 'generation': args.generation, 'folder': str(folder),
            'phase': phase, 'error': repr(error), 'receipts': receipts,
            'independent_kernel_passed': False,
            'kernel_executed': any(row['stdout']['file'] == 'independent-kernel.stdout' for row in receipts),
            'source_files': source_pins, 'toolchain': pins,
            'source_selection': selection,
            'retained_artifacts': available_artifacts(folder),
            'scope': 'This failed attempt establishes no independently passed law. Native/reference evidence remains separate.',
        }
        write_json(folder / 'failure.json', failure)
        publish(folder, failure)
        print(json.dumps({'status': 'failed', 'generation': args.generation,
                          'folder': str(folder), 'phase': phase, 'error': repr(error)}))
        raise


if __name__ == '__main__':
    main()
