#!/usr/bin/env python3
"""Check the actual Entry cooking splice with the original compiler book."""
from __future__ import annotations
import json
import pathlib
import time
import argparse
from reference_inventory import fingerprint, write_json
from test_player_motion_current import run

ROOT = pathlib.Path(__file__).resolve().parents[1]
NODE = pathlib.Path('/opt/homebrew/bin/node')

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--diagnose', action='store_true', help='Observe original checker order; bound the failed-graph diagnosis to 40 seconds.')
    parser.add_argument('--generation', type=int, help='Keep a later changed-source receipt distinct from the initial 018 splice.')
    parser.add_argument('--scene', action='store_true', help='Check the actual Scene closure before Entry bootstrap adoption; keep its receipt distinct.')
    options = parser.parse_args()
    directory = ROOT / 'build/local-player-cooking/source' / str(time.time_ns())
    directory.mkdir(parents=True, exist_ok=False)
    command = [NODE, '--expose-gc', '--max-old-space-size=8192', '--stack-size=4096',
               '--experimental-transform-types', ROOT / 'tools/local_player_cooking_source.mjs', directory]
    if options.diagnose:
        command.append('--diagnose')
    if options.scene:
        command.append('--scene')
    try:
        _, receipt = run(command, directory, 'original-source', 40 if options.diagnose else 120)
        source = json.loads((directory / 'source.json').read_bytes())
        assert source['original_book_checked'] and source['holes'] == 0
        evidence = {**source, 'directory': str(directory), 'receipt': receipt,
                    'runner': fingerprint(pathlib.Path(__file__)),
                    'checker': fingerprint(ROOT / 'tools/local_player_cooking_source.mjs')}
        suffix = '' if options.generation is None else f'-{options.generation:03d}'
        if options.scene:
            suffix = '-scene' + suffix
        write_json(ROOT / f'evidence/local-player-cooking-source{suffix}.json', evidence)
        print(json.dumps({'status': source['status'], 'seconds': receipt['seconds'],
                          'declarations': source['declarations'], 'holes': source['holes']}))
    except BaseException as error:
        write_json(directory / 'failure.json', {'status': 'failed', 'error': repr(error)})
        raise

if __name__ == '__main__':
    main()
