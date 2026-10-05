#!/usr/bin/env python3
"""One original five-law source/export and unchanged independent-kernel check."""
import json
import os
from pathlib import Path

import test_local_player_effect_entities_codec as H

ROOT = H.ROOT
EXPORT = ROOT / 'tools/entity_membership_codec_proof.mjs'
KERNEL = Path('/Users/chuah/.bend/bendtt/e15042434e73aab0/bendtt')
COMPILER = ROOT.parent / 'bend/bend2'
NODE = Path('/opt/homebrew/bin/node')


def main():
    base = ROOT / 'build/entity-membership-codec/proof'
    base.mkdir(parents=True, exist_ok=True)
    number = 1
    while (directory := base / f'{number:03}').exists():
        number += 1
    directory.mkdir()
    entry = ROOT / 'src/entity_membership_codec_proof.bend'
    snapshot = H.Build.Snapshot()
    H.Build.source_graph(entry, H.BEND.resolve().parent.parent / 'bend2/base.bend',
                         os.environ, snapshot)
    for path in [EXPORT, Path(__file__), NODE, KERNEL, KERNEL.parent / 'bendtt.lean',
                 COMPILER / 'bendtt.lean', COMPILER / 'bend.ts', COMPILER / 'safe.ts']:
        snapshot.add(path, 'proof-tool')
    before = snapshot.manifest()
    H.write(directory / 'inputs.json', before)
    processes = []
    phase = 'source-and-export'
    report = None
    artifact = None
    try:
        H.require(H.pin(KERNEL.parent / 'bendtt.lean')['sha256'][:16] == KERNEL.parent.name,
                  'Independent kernel source does not match cached identity')
        H.require(H.pin(KERNEL.parent / 'bendtt.lean')['sha256'] ==
                  H.pin(COMPILER / 'bendtt.lean')['sha256'],
                  'Compiler exporter and independent kernel source differ')
        source = H.bounded(directory, [NODE, '--experimental-transform-types',
            '--stack-size=4096', '--max-old-space-size=8192', EXPORT, directory],
            phase, 60)
        processes.append(source)
        H.process_ok(source)
        report = json.loads((directory / 'source-proof.json').read_text())
        H.require(report['status'] == 'source_checked' and report['holes'] == 0 and
                  len(report['roots']) == 5 and report['exclusions'] == [] and
                  report['original_book_checks'] == 1 and
                  report['checked_types_and_bodies_unchanged'] and
                  report['all_original_declaration_maps_retained'],
                  'Actual complete five-law source/export scope differs')
        artifact = H.pin(directory / 'membership.bendtt')
        phase = 'independent-kernel'
        kernel = H.bounded(directory, ['/usr/bin/env', 'LEAN_STACK_SIZE_KB=4194304',
            KERNEL, directory / 'membership.bendtt'], phase, 60)
        processes.append(kernel)
        H.process_ok(kernel)
        H.require(Path(kernel['stdout']['path']).read_text().strip() == 'ALL PROOFS CHECK',
                  'Independent kernel did not accept every actual law')
        H.require(H.pin(directory / 'membership.bendtt') == artifact,
                  'Independent kernel artifact changed')
        for row in before:
            H.require(H.pin(row['path'])['sha256'] == row['sha256'],
                      'Loaded source/tool changed: ' + row['path'])
        result = {'schema': 1, 'status': 'PASS', 'laws': 5,
            'source_report': report, 'artifact': artifact, 'kernel': H.pin(KERNEL),
            'inputs': H.pin(directory / 'inputs.json'), 'processes': processes,
            'scope': 'Five actual raw field roundtrip and complete manager inspect/encode owner laws. Physical parser admission, loader-authorized manager installation and durable IO remain separate evidence.'}
        H.write(directory / 'result.json', result)
        H.write(ROOT / 'evidence/entity-membership-codec-proof.json', result)
        print(json.dumps({'status': 'PASS', 'laws': 5, 'directory': str(directory),
                          'seconds': [p['seconds'] for p in processes]}), flush=True)
    except BaseException as error:
        if (directory / 'source-proof.json').exists():
            report = json.loads((directory / 'source-proof.json').read_text())
        result = {'schema': 1, 'status': 'FAIL', 'phase': phase,
            'error': repr(error), 'source_report': report, 'artifact': artifact,
            'inputs': H.pin(directory / 'inputs.json'), 'processes': processes,
            'scope': 'This attempt establishes no independent-kernel law. Source typing and prior native owner/physical results remain separately recorded.'}
        H.write(directory / 'failure.json', result)
        H.write(ROOT / f'evidence/entity-membership-codec-proof-{number:03}-failure.json', result)
        print(json.dumps({'status': 'FAIL', 'phase': phase, 'directory': str(directory),
                          'error': repr(error)}), flush=True)
        raise


if __name__ == '__main__':
    main()
