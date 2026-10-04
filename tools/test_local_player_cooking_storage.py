#!/usr/bin/env python3
"""Changed cooking wrapper/extras guards through Bend's actual default JS route."""
import json
import os
from pathlib import Path

import build_native as Build
import test_campfire_authority as Paths
import test_remote_resource_client as R

ROOT = Path(__file__).resolve().parents[1]
ENTRY = ROOT / 'tests/local_player_cooking_storage.bend'
EXPECTED = [
    'actual empty inventory codec payload remains byte-identical',
    'empty cooking payload preserves player bytes',
    'physical wrapper retains dimensions coordinate bits body order and bytes',
    'duplicate body positions refuse complete projection',
    'unsupported cooking format refuses',
    'wrong cooking list element type refuses',
    'physical root UTF16 duplicate extras types and raw bits retained',
    'malformed known body refuses extras merge',
    'noncompound known body refuses extras merge',
    'pending effects retain order coordinates and player payload in format2',
    'empty recovery payload refuses noncanonical format2',
    'recovery effects require complete ByteArray',
]


def sources():
    snapshot = Build.Snapshot()
    Build.source_graph(ENTRY, Paths.BEND.resolve().parent.parent / 'bend2/base.bend',
                       os.environ, snapshot)
    snapshot.add(Path(__file__), 'verification-tool')
    snapshot.add(Paths.BEND, 'compiler')
    return snapshot.manifest()


def main():
    work = ROOT / 'build/local-player-cooking-storage'
    work.mkdir(exist_ok=True)
    for number in range(1, 10000):
        directory = work / f'{number:03}'
        try:
            directory.mkdir()
            break
        except FileExistsError:
            continue
    else:
        raise RuntimeError('No unused attempt directory')
    before = sources()
    R.write(directory / 'sources.json', before, True)
    old_work = R.WORK
    process = None
    try:
        R.WORK = directory
        process = R.bounded([Paths.BEND, ENTRY], 90, 'actual-js')
        R.process_ok(process)
        lines = Path(process['stdout']['path']).read_text().splitlines()
        R.require(lines == ['ok ' + name for name in EXPECTED] and
                  not Path(process['stderr']['path']).read_bytes(),
                  'Cooking wrapper/extras guards differ')
        R.require(before == sources(), 'Cooking storage graph changed during execution')
        result = {'status': 'PASS', 'guards': EXPECTED, 'process': process,
                  'source_manifest': R.pin(directory / 'sources.json'),
                  'entry': R.pin(ENTRY),
                  'storage': R.pin(ROOT / 'src/local_player_cooking_storage.bend'),
                  'scope': 'Actual Bend default-JS codec guards. Known physical body bytes plus explicit '
                           'accepted-load Details metadata; no forged metadata is used as item/world authority. '
                           'Native actor atomic publication, interrupted saves, cold world discovery and '
                           'body admission require the subsequent coherent actor consumer.'}
        R.write(directory / 'result.json', result, True)
        evidence = ROOT / f'evidence/local-player-cooking-storage-{number:03}.json'
        R.write(evidence, result, True)
        print(json.dumps({'status': 'PASS', 'guards': len(EXPECTED),
                          'evidence': str(evidence)}), flush=True)
    except BaseException as error:
        failure = {'status': 'FAIL', 'type': type(error).__name__, 'message': str(error),
                   'process': process}
        R.write(directory / 'failure.json', failure, True)
        R.write(ROOT / f'evidence/local-player-cooking-storage-{number:03}-failure.json', failure, True)
        raise
    finally:
        R.WORK = old_work


if __name__ == '__main__':
    main()
