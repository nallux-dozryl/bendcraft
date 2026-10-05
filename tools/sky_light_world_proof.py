#!/usr/bin/env python3
"""Bound and retain ordinary and independent-kernel sky world production checks."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[1]
BEND = Path('/Users/chuah/.bend/bin/bend')
BASE = Path('/Users/chuah/.bend/bend2/base.bend')
KERNEL = Path('/Users/chuah/.bend/bendtt/e15042434e73aab0/bendtt')
ENTRY = ROOT / 'src/sky_light_world_proof.bend'
LAWS = ROOT / 'src/sky_light_world_laws.bend'
EVIDENCE = ROOT / 'evidence/sky-light-world-proof.json'
SCOPE = ('The stated actual borrowed-Core enumeration, bootstrap, revision/queue admission, '
         'refusal, deferred source repair and disabling-only complete stored-field contracts. '
         'Enumeration preserves arbitrary trie/bucket/section owners without asserting key validity '
         'or uniqueness. The failed Core-read composition preserves the complete sidecar and '
         'the world returned by the read under its explicit result premise. Zero-budget/provider '
         'contracts instantiate actual registry callbacks and unreachable admission adapters. '
         'No enabling-True field-retention law, source geometry/threshold correctness, whole-field '
         'convergence, settled Java equivalence, persistence, native behavior or client integration '
         'is claimed.')


def fingerprint(path):
    data = path.read_bytes()
    return {'path': str(path.resolve()), 'bytes': len(data),
            'sha256': hashlib.sha256(data).hexdigest()}


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + '\n')


def source_closure(entry):
    pending, loaded = [entry.resolve()], {}
    while pending:
        path = pending.pop()
        if str(path) in loaded:
            continue
        loaded[str(path)] = fingerprint(path)
        for imported in re.findall(r'^import\s+(\S+)', path.read_text(), re.MULTILINE):
            if imported == 'Base':
                pending.append(BASE.resolve())
            elif imported.startswith('./') or imported.startswith('../'):
                pending.append((path.parent / imported).resolve())
    return loaded


def run(argv, folder, phase, timeout):
    environment = os.environ.copy()
    environment['BENDTT'] = str(KERNEL)
    started = time.monotonic()
    process = subprocess.Popen(argv, cwd=ROOT, env=environment, text=True,
                               stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               start_new_session=True)
    timed_out, interrupted = False, None

    def kill_group():
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass

    def terminated(signum, frame):
        raise InterruptedError('Proof runner interrupted by signal ' + str(signum))

    previous = signal.signal(signal.SIGTERM, terminated)
    try:
        try:
            stdout, stderr = process.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            timed_out = True
            kill_group()
            stdout, stderr = process.communicate()
        except BaseException as error:
            interrupted = repr(error)
            kill_group()
            stdout, stderr = process.communicate()
    finally:
        signal.signal(signal.SIGTERM, previous)
    (folder / (phase + '.stdout')).write_text(stdout)
    (folder / (phase + '.stderr')).write_text(stderr)
    receipt = {'argv': argv, 'BENDTT': str(KERNEL), 'exit_code': process.returncode,
               'seconds': round(time.monotonic() - started, 6), 'timed_out': timed_out,
               'interrupted': interrupted, 'stdout': fingerprint(folder / (phase + '.stdout')),
               'stderr': fingerprint(folder / (phase + '.stderr'))}
    write_json(folder / (phase + '.json'), receipt)
    return stdout, receipt


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--ordinary-timeout', type=int, default=60)
    parser.add_argument('--kernel-timeout', type=int, default=120)
    args = parser.parse_args()
    if args.ordinary_timeout <= 0 or args.kernel_timeout <= 0:
        raise SystemExit('Timeouts must be positive')
    folder = ROOT / 'build/sky-light-world-proof' / str(time.time_ns())
    folder.mkdir(parents=True, exist_ok=False)
    sources = source_closure(ENTRY)
    tools = [fingerprint(path) for path in [BEND, KERNEL, KERNEL.parent / 'bendtt.lean',
                                          Path(__file__).resolve()]]
    roots = re.findall(r'^law\s+([A-Za-z_][\w.]*)\s*:', LAWS.read_text(), re.MULTILINE)
    if not roots or len(roots) != len(set(roots)):
        raise SystemExit('Missing or duplicate stated laws')
    write_json(folder / 'source-pins.json', sources)
    write_json(folder / 'toolchain-pins.json', tools)
    evidence = {'status': 'failed', 'folder': str(folder), 'entry': str(ENTRY),
                'laws': len(roots), 'roots': roots, 'source_files': sources,
                'toolchain': tools, 'receipts': [], 'ordinary_check_passed': False,
                'independent_kernel_passed': False, 'scope': SCOPE}
    for phase, flag, timeout in [('ordinary', '--check-only', args.ordinary_timeout),
                                 ('independent-kernel', '--verdict', args.kernel_timeout)]:
        stdout, receipt = run([str(BEND), str(ENTRY), flag], folder, phase, timeout)
        evidence['receipts'].append(receipt)
        accepted = (not receipt['timed_out'] and receipt['interrupted'] is None and
                    receipt['exit_code'] == 0 and stdout.splitlines()[0:1] == ['ALL PROOFS CHECK'])
        if phase == 'independent-kernel':
            accepted = accepted and stdout.strip() == 'ALL PROOFS CHECK'
        if not accepted:
            evidence['failed_phase'] = phase
            break
        evidence['ordinary_check_passed' if phase == 'ordinary' else 'independent_kernel_passed'] = True
    evidence['sources_unchanged'] = source_closure(ENTRY) == sources
    evidence['toolchain_unchanged'] = [fingerprint(Path(pin['path'])) for pin in tools] == tools
    if (evidence['ordinary_check_passed'] and evidence['independent_kernel_passed'] and
            evidence['sources_unchanged'] and evidence['toolchain_unchanged']):
        evidence['status'] = 'passed'
        # Standard --verdict accepts only when its full emitted closure has no exclusions.
        evidence['scope_exclusions'] = []
    write_json(folder / 'result.json', evidence)
    temporary = EVIDENCE.with_name(EVIDENCE.name + '.' + folder.name + '.tmp')
    write_json(temporary, evidence)
    temporary.replace(EVIDENCE)
    print(json.dumps({'status': evidence['status'], 'folder': str(folder),
                      'laws': len(roots), 'seconds': [row['seconds'] for row in evidence['receipts']],
                      'independent_kernel_passed': evidence['independent_kernel_passed']}))
    if evidence['status'] != 'passed':
        raise SystemExit(1)


if __name__ == '__main__':
    main()
