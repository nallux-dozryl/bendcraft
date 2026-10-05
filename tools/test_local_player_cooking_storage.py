#!/usr/bin/env python3
"""Changed cooking wrapper guards through the existing JS or narrow native route."""
import argparse
import json
import os
from pathlib import Path
import sys

import build_native as Build
import test_campfire_authority as Paths
import test_remote_resource_client as R
import test_local_player_effect_entities_codec as Native

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
    'format3 retains empty entity owner RNG cursors and ordered raw clock inputs',
    'absent entity owner preserves format2 bytes exactly',
    'entity clock inputs require complete LongArray',
    'duplicate entity recovery clock field refuses',
    'absent publication preserves legacy recovery bytes exactly',
    'format4 retains complete publication and pending producer with unbound entities',
    'format4 retains publication together with full entity clock recovery',
    'owned pending effects require publication recovery when encoding',
    'owned pending effects refuse legacy wrapper when decoding',
    'format4 unbound entity owner refuses orphan clock inputs',
    'format5 retains one full tick and manager snapshot without publication',
    'format5 retains real publisher pending effects and clock inputs',
    'format5 refuses owned pending without publication when encoding',
    'format5 refuses owned pending without publication when decoding',
    'format5 unavailable manager differs from known empty manager',
    'format5 explicit unavailable runtime and sound stays unavailable',
    'format5 clock inputs require LongArray',
    'actual format5 player cooking tick and publication encode decode roundtrip',
]


def sources():
    snapshot = Build.Snapshot()
    Build.source_graph(ENTRY, Paths.BEND.resolve().parent.parent / 'bend2/base.bend',
                       os.environ, snapshot)
    snapshot.add(Path(__file__), 'verification-tool')
    snapshot.add(Paths.BEND, 'compiler')
    snapshot.add(Path(Native.__file__), 'native-verification-tool')
    return snapshot.manifest()


def build_child(directory):
    with Native.forbid_retries():
        report = Build.ensure_native(ENTRY, directory / 'native', bend=Paths.BEND,
                                     cache_dir=ROOT / 'build/local-player-cooking-storage/native-cache')
    R.require(report['retries'] == 0, 'Cooking storage builder retried')
    R.write(directory / 'build.json', report, True)


def main(native=False):
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
    processes = []
    try:
        R.WORK = directory
        if native:
            process = R.bounded([sys.executable, Path(__file__), '--build-child', directory],
                                600, 'native-build')
            processes.append(process)
            R.process_ok(process)
        argv = [directory / 'native', '--gpu', 'off', '--threads', '1'] if native else [Paths.BEND, ENTRY]
        process = R.bounded(argv, 90, 'actual-native' if native else 'actual-js')
        processes.append(process)
        R.process_ok(process)
        lines = Path(process['stdout']['path']).read_text().splitlines()
        R.require(lines == ['ok ' + name for name in EXPECTED] and
                  not Path(process['stderr']['path']).read_bytes(),
                  'Cooking wrapper/extras guards differ')
        R.require(before == sources(), 'Cooking storage graph changed during execution')
        result = {'status': 'PASS', 'mode': 'native' if native else 'default-js',
                  'guards': EXPECTED, 'process': process, 'processes': processes,
                  'source_manifest': R.pin(directory / 'sources.json'),
                  'entry': R.pin(ENTRY),
                  'storage': R.pin(ROOT / 'src/local_player_cooking_storage.bend'),
                  'scope': ('Actual Bend native codec guards. ' if native else 'Actual Bend default-JS codec guards. ') +
                           'Known physical body bytes plus explicit '
                           'accepted-load Details metadata; no forged metadata is used as item/world authority. '
                           'Native actor atomic publication, interrupted saves, cold world discovery and '
                           'body admission require the subsequent coherent actor consumer.'}
        if native:
            result.update(binary=R.pin(directory / 'native'), build=R.pin(directory / 'build.json'))
        R.write(directory / 'result.json', result, True)
        evidence = ROOT / f'evidence/local-player-cooking-storage-{number:03}.json'
        R.write(evidence, result, True)
        print(json.dumps({'status': 'PASS', 'guards': len(EXPECTED),
                          'evidence': str(evidence)}), flush=True)
    except BaseException as error:
        failure = {'status': 'FAIL', 'type': type(error).__name__, 'message': str(error),
                   'process': process, 'processes': processes}
        R.write(directory / 'failure.json', failure, True)
        R.write(ROOT / f'evidence/local-player-cooking-storage-{number:03}-failure.json', failure, True)
        raise
    finally:
        R.WORK = old_work


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--native', action='store_true')
    parser.add_argument('--build-child', type=Path, help=argparse.SUPPRESS)
    args = parser.parse_args()
    if args.build_child:
        build_child(args.build_child)
    else:
        main(args.native)
