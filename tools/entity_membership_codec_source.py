#!/usr/bin/env python3
"""One original full-module source check with the existing bounded runner."""
import argparse
import json
import os
from pathlib import Path

import test_local_player_effect_entities_codec as H


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--entry', type=Path, default=H.ROOT / 'src/entity_membership_codec.bend')
    args = parser.parse_args()
    base = H.ROOT / 'build/entity-membership-codec/source'
    base.mkdir(parents=True, exist_ok=True)
    number = 1
    while (directory := base / f'{number:03}').exists():
        number += 1
    directory.mkdir()
    snapshot = H.Build.Snapshot()
    H.Build.source_graph(args.entry.resolve(), H.BEND.resolve().parent.parent / 'bend2/base.bend',
                        os.environ, snapshot)
    before = snapshot.manifest()
    H.write(directory / 'sources.json', before)
    process = H.bounded(directory, [H.BEND, args.entry.resolve(), '--check-only'], 'ordinary', 60)
    drift = [row['path'] for row in before if H.pin(row['path'])['sha256'] != row['sha256']]
    H.write(directory / 'source-result.json', {'process': process, 'source_drift': drift})
    print(json.dumps({'directory': str(directory), 'exit_code': process['exit_code'],
        'seconds': process['seconds'], 'source_drift': drift,
        'stderr': Path(process['stderr']['path']).read_text()}), flush=True)
    H.process_ok(process)
    H.require(not drift, 'Actual source graph changed during checking')


if __name__ == '__main__':
    main()
