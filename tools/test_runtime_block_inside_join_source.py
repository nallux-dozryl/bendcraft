#!/usr/bin/env python3
"""Ordinary check the actual joined runtime and all five constructor observers."""
from __future__ import annotations
import json, pathlib, time
from reference_inventory import fingerprint, write_json
from test_player_motion_current import run
ROOT = pathlib.Path(__file__).resolve().parents[1]
FILES = ['src/local_phase_runtime.bend', 'src/local_player_runtime.bend',
         'src/local_player_session.bend', 'src/local_player_scene.bend',
         'tests/local_phase_runtime.bend', 'tests/local_phase_reset.bend',
         'tests/local_player_runtime.bend', 'tests/local_player_session.bend',
         'tests/playable_client_transport.bend', 'tests/runtime_block_inside_join_source.bend']
def main():
    folder = ROOT / 'build/runtime-block-inside-join-source' / str(time.time_ns())
    folder.mkdir(parents=True, exist_ok=False)
    before = [dict(relative_path=p, **fingerprint(ROOT / p)) for p in FILES]
    receipt = None
    try:
        # The existing Scene/Session OS boundary is reported by the standard
        # checker after typing; it is not admitted into any proof claim.
        foreign = []
        try:
            stdout, receipt = run(['/Users/chuah/.bend/bin/bend', ROOT / 'tests/runtime_block_inside_join_source.bend', '--check-only'], folder, 'ordinary', 120)
            assert 'ALL PROOFS CHECK' in stdout, stdout
        except AssertionError as error:
            receipt = error.args[0] if error.args and isinstance(error.args[0], dict) else None
            if not receipt:
                raise
            text = (folder / 'ordinary.stdout').read_text() + (folder / 'ordinary.stderr').read_text()
            assert receipt['exit_code'] == 1 and not receipt['timed_out'] and receipt['group_absent'], receipt
            assert 'defs rely on unsafe or foreign code' in text and 'Location:' not in text, text
            foreign = [line[2:] for line in text.splitlines() if line.startswith('- ')]
            assert foreign, text
        after = [dict(relative_path=p, **fingerprint(ROOT / p)) for p in FILES]
        assert before == after, 'Joined observer source changed during ordinary check'
        evidence = {'status':'passed-with-existing-foreign-boundaries' if foreign else 'passed', 'folder':str(folder), 'receipt':receipt, 'foreign_boundaries':foreign,
                    'sources':after, 'scope':'Ordinary typing and source law checking of the four actual runtime consumers and all five updated constructor observer closures. No independent kernel/native/transport claim.'}
        write_json(ROOT / 'evidence/runtime-block-inside-join-source.json', evidence)
        print(json.dumps({'status':evidence['status'], 'seconds':receipt['seconds'], 'sources':len(after), 'foreign_boundaries':len(foreign)}))
    except BaseException as error:
        write_json(folder / 'failure.json', {'status':'failed', 'error':repr(error), 'receipt':receipt, 'sources':before})
        raise
if __name__ == '__main__': main()
