#!/usr/bin/env python3
"""Focused checks of the actual same-owner direct player cooking edit.

Reuses the existing original source checker, exact-declaration kernel closure,
guarded ordinary C preparation and bounded native process runner.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import sys

from build_native import foreign_paths, file_digest, guard_route
from test_player_look import imports
from test_player_block_inside_stuck import run
from bendtt_closure import retain

ROOT = Path(__file__).resolve().parents[1]
ENTRY = ROOT / 'tests/local_player_cooking_edit.bend'
PROOF = ROOT / 'src/local_player_cooking_edit_proof.bend'
CHECKER = ROOT / 'tools/player_crafting_backend_proof.mjs'
NODE = Path('/opt/homebrew/bin/node')
KERNEL = Path('/Users/chuah/.bend/bendtt/e15042434e73aab0/bendtt')
LAWS = [
    'disabled_build_retains_complete_core_and_cooking_owner',
    'observer_retains_complete_core_and_cooking_owner',
    'invalid_player_retains_complete_core_and_cooking_owner',
    'refused_prepared_edit_retains_core_light_and_entry_owners',
]
EXPECTED = [
    'stale revision retains complete Core and sidecar',
    'disabled build retains complete Core and sidecar',
    'observer retains complete Core and sidecar',
    'invalid peer retains complete Core and sidecar',
    'residency mismatch retains complete Core and sidecar',
    'missing section retains complete Core and sidecar',
    'recursive tail retains complete Core and sidecar',
    'successful edit records current tick actual peer and sequence',
    'actual Core final block',
    'furnace teardown retains unrelated owner and exact ordered prior/drop/XP intents',
    'successful reset removes only old physical Details and increments only its incarnation',
    'successful edit publishes actual air descriptor and pending light work',
    'successful edit retains complete entity RNG clock and geometry carrier',
    'pinned furnace outline families admitted while campfire remains unsupported',
    'actual DDA and pinned full cube outline select furnace south face',
    'actual ray callback accepts exactly one furnace break',
    'successful edit records current tick actual peer and sequence',
    'actual Core final block',
    'furnace teardown retains unrelated owner and exact ordered prior/drop/XP intents',
    'successful reset removes only old physical Details and increments only its incarnation',
    'successful edit publishes actual air descriptor and pending light work',
    'successful edit retains complete entity RNG clock and geometry carrier',
]


def require(value, message):
    if not value:
        raise AssertionError(message)


def pin(path):
    data = path.read_bytes()
    return {'path': str(path), 'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}


def source_check(work, entry):
    command = ['/usr/bin/env', 'CRAFT_BACKEND_SOURCE_ONLY=1', NODE, '--expose-gc',
               '--max-old-space-size=8192', '--stack-size=4096',
               '--experimental-transform-types', CHECKER, work, entry]
    _, receipt = run(command, work, 'source', 120)
    checked = json.loads((work / 'source-check.json').read_text())
    require(checked['ordinary_source_api_check_passed'] and checked['original_order_restored'],
            'original source checker did not finish the unchanged book')
    return {'receipt': receipt, 'source_manifest': pin(work / 'source-check.json')}


def proof_check(work):
    # Only the exact requested root names change in this read-only script copy.
    # The established helper still checks the whole original Book before any
    # selection and preserves original maps, definitions, types and bodies.
    roots = ['local_player_cooking_edit_laws:' + law for law in LAWS]
    script = CHECKER.read_text()
    script, count = re.subn(r'const roots=\[.*?\];',
                           'const roots=' + json.dumps(roots) + ';', script, count=1)
    require(count == 1, 'established exact-root selector changed')
    executed = work / 'proof.mjs'
    executed.write_text(script)
    _, export = run([NODE, '--expose-gc', '--max-old-space-size=8192', '--stack-size=4096',
                     '--experimental-transform-types', executed, work, PROOF], work, 'export', 120)
    scope = json.loads((work / 'scope.json').read_text())
    require(not scope['exclusions'], 'proof export excluded definitions')
    exact, manifest = retain((work / 'selected.bendtt').read_bytes(),
                             [root.replace(':', '.') for root in roots])
    closure = work / 'closure.bendtt'
    closure.write_bytes(exact)
    (work / 'closure.json').write_text(json.dumps(manifest, indent=2) + '\n')
    output, kernel = run(['/usr/bin/env', 'LEAN_STACK_SIZE=67108864', KERNEL, closure],
                         work, 'kernel', 60)
    require(b'ALL PROOFS CHECK' in output and not (work / 'kernel.stderr').read_bytes(),
            'independent kernel did not accept the exact four-root closure')
    return {'laws': LAWS, 'export': export, 'kernel': kernel,
            'selection': pin(work / 'selection.json'), 'closure': pin(closure),
            'closure_manifest': pin(work / 'closure.json'), 'kernel_binary': pin(KERNEL)}


def included_proof_check(work, exported):
    # Reuse the retained full four-root export without rechecking or altering
    # its terms. The three failed roots stay failed; only the independently
    # exportable actual CWEdit refusal contract is submitted to the kernel.
    root = 'local_player_cooking_edit_laws.' + LAWS[3]
    scope = json.loads((exported / 'scope.json').read_text())
    selection = json.loads((exported / 'selection.json').read_text())
    require(selection['ordinary_source_api_check_passed'] and
            selection['checked_types_and_bodies_unchanged'] and
            selection['all_original_tlds_ctrs_tmps_retained'], 'unchecked or rewritten export')
    require(selection['roots'] == ['local_player_cooking_edit_laws:' + law for law in LAWS],
            'retained four-root scope changed')
    exclusions = scope['exclusions']
    expected = ['local_player_cooking_edit_laws.' + law for law in LAWS[:3]]
    require(len(exclusions) == 3 and all(
        exclusion.startswith('- ' + name + ': names local_player_cooking_edit.player_edit,') and
        'mutual recursion through Nat.show.fin, Nat.show.go' in exclusion
        for exclusion, name in zip(exclusions, expected)), 'unexpected export boundary')
    exact, manifest = retain((exported / 'selected.bendtt').read_bytes(), [root])
    retained = {row['name'] for row in manifest['retained']}
    require(not retained.intersection(expected), 'excluded law belongs to included closure')
    closure = work / 'included-refusal.bendtt'
    closure.write_bytes(exact)
    (work / 'closure.json').write_text(json.dumps(manifest, indent=2) + '\n')
    output, kernel = run(['/usr/bin/env', 'LEAN_STACK_SIZE=67108864', KERNEL, closure],
                         work, 'kernel', 60)
    require(b'ALL PROOFS CHECK' in output and not (work / 'kernel.stderr').read_bytes(),
            'kernel rejected the exact included CWEdit refusal root')
    return {'certified_roots': [root], 'excluded_permission_laws_certified': False,
            'full_four_root_kernel_passed': False, 'exclusions': exclusions,
            'retained_export': pin(exported / 'selected.bendtt'),
            'retained_selection': pin(exported / 'selection.json'), 'kernel': kernel,
            'closure': pin(closure), 'closure_manifest': pin(work / 'closure.json'),
            'kernel_binary': pin(KERNEL)}


def frozen_entry(work):
    sources = imports([ENTRY])
    original_bend = dict(sources)
    for name in original_bend:
        path = ROOT / name
        for effect in foreign_paths(path.read_text()):
            if effect.endswith('.c'):
                path = (ROOT / name).parent / effect
                sources[str(path.resolve().relative_to(ROOT))] = file_digest(path)
    for name, expected in sources.items():
        data = (ROOT / name).read_bytes()
        require(hashlib.sha256(data).hexdigest() == expected, 'source drift while copying ' + name)
        destination = work / 'source' / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
    require(imports([ENTRY]) == original_bend, 'Bend source drift during snapshot')
    require(all(file_digest(ROOT / name) == digest for name, digest in sources.items()),
            'native effect drift during snapshot')
    (work / 'sources.json').write_text(json.dumps(sources, indent=2) + '\n')
    return work / 'source/tests/local_player_cooking_edit.bend'


def native_check(work):
    entry = frozen_entry(work)
    prepare = ROOT / 'tools/player_crafting_authority_native.py'
    _, emission = run([sys.executable, prepare, entry, '--report', work / 'prepared.json'],
                       work, 'prepare', 600)
    prepared = json.loads((work / 'prepared.json').read_text())
    emitted = Path(prepared['emitted_file'])
    require(file_digest(emitted) == prepared['emitted_c_sha256'], 'guarded C bytes changed')
    guard_route(emitted.read_text())
    require(prepared['context']['compiler']['flags'] ==
            ['-std=c11', '-O3', '<emitted.c>', '-lpthread', '-lm', '-o', '<native>'],
            'ordinary CPU compiler flags changed')
    binary = work / 'edit-tests'
    _, clang = run([prepared['context']['compiler']['path'], '-std=c11', '-O3', emitted,
                    '-lpthread', '-lm', '-o', binary], work, 'clang', 600)
    _, checked = run([sys.executable, prepare, entry, '--report', work / 'prepared-after.json'],
                      work, 'prepare-after', 600)
    after = json.loads((work / 'prepared-after.json').read_text())
    require(after['cache_key'] == prepared['cache_key'] and
            after['emitted_c_sha256'] == prepared['emitted_c_sha256'], 'native dependency drift')
    output, native = run([binary, '--gpu', 'off', '--threads', '2'], work, 'native', 30)
    actual = [line[3:] for line in output.decode().splitlines() if line.startswith('ok ')]
    require(actual == EXPECTED and not (work / 'native.stderr').read_bytes(),
            'actual native edit guards differ from independent expected outcomes')
    return {'guards': actual, 'emission': emission, 'clang': clang, 'dependency_check': checked,
            'native': native, 'binary': pin(binary), 'source_snapshot': pin(work / 'sources.json')}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--work', type=Path, required=True)
    parser.add_argument('--mode', choices=['source', 'proof', 'included-proof', 'native'], default='source')
    parser.add_argument('--export', type=Path, help='Retained four-root export for included-proof mode')
    args = parser.parse_args()
    work = args.work.resolve()
    work.mkdir(parents=True, exist_ok=False)
    try:
        if args.mode == 'source':
            result = source_check(work, ENTRY)
        elif args.mode == 'proof':
            result = proof_check(work)
        elif args.mode == 'included-proof':
            require(args.export is not None, '--export is required for included-proof mode')
            result = included_proof_check(work, args.export.resolve())
        else:
            result = native_check(work)
        result.update({'status': 'pass', 'mode': args.mode, 'directory': str(work),
                       'runner': pin(Path(__file__)), 'fixture': pin(ENTRY),
                       'adapter': pin(ROOT / 'src/local_player_cooking_edit.bend')})
        (work / 'result.json').write_text(json.dumps(result, indent=2) + '\n')
        print(json.dumps({'status': 'pass', 'mode': args.mode, 'result': str(work / 'result.json')}))
    except BaseException as error:
        (work / 'failure.json').write_text(json.dumps({'status': 'failed', 'mode': args.mode,
            'error': repr(error), 'runner': pin(Path(__file__))}, indent=2) + '\n')
        raise


if __name__ == '__main__':
    main()
