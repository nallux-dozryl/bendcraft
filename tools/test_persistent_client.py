#!/usr/bin/env python3
"""Actual hidden client edits/save/restart with independent pixels and NBT.

This tests the finite scene and shared ownership, not vanilla player gameplay.
"""
from __future__ import annotations

from datetime import datetime, timezone
import hashlib
from io import BytesIO
import json
import os
from pathlib import Path
import select
import socket
import subprocess
import time
import zipfile

import test_client_render as R
import test_persistence as P
from test_server import Client, free_port

ROOT = Path(__file__).resolve().parents[1]
WORK = ROOT / 'build/persistent-client-integration'
SOURCES = ['persistent_client.bend', 'client.bend', 'src/client_host.bend',
           'src/persistent_client_world.bend', 'src/client_world.bend',
           'src/client_render.bend', 'src/persistence.bend', 'src/server.bend',
           'src/world_lock.bend', 'src/native/world_lock.c', 'src/world_codec.bend',
           'src/atomic_file.bend', 'src/durability.bend', 'src/native/durability.c',
           'src/core.bend', 'src/game.bend', 'src/registry.bend', 'src/section_map.bend',
           'src/movement.bend', 'src/f64.bend', 'tools/platform_build.py',
           'tools/test_persistent_client.py', 'tools/test_client_render.py',
           'tools/test_persistence.py']


def hashes():
    return {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest() for p in SOURCES}


def blocks(changed=False):
    floor = [(x, 0, z, 0, 2 if changed else 1 if x == 2 else 0)
             for z in range(-3, 3) for x in range(-3, 3)]
    raised = [(1, 1, 1, 0, 1), (2, 1, 2, 0, 2), (2, 2, 2, 0, 2)]
    # The eye height is an actual F32 constant widened before exact F64 add.
    eye = (.5, 1.0 + R.f(1.62), -2.5)
    return [(R.f(x-eye[0]), R.f(y-eye[1]), R.f(z-eye[2]), state, material)
            for x, y, z, state, material in sorted(floor+raised, key=lambda b: (b[2], b[1], b[0]))]


class Running:
    def __init__(self, binary, save, dump, *, create=False, frames=500):
        self.port = free_port()
        self.dump = dump
        if dump.exists():
            dump.unlink()
        env = P.clean_env(save, self.port, P.OFFICIAL, 'create' if create else None)
        env['BEND_MINECRAFT_LAUNCH_MODE'] = 'hidden'
        self.process = subprocess.Popen(
            [str(binary), '--gpu', 'off', '--verification-fixture', '--frames', str(frames), '--dump', str(dump)],
            cwd=ROOT, env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, bufsize=0)
        self.client = None
        if not select.select([self.process.stdout], [], [], 60)[0]:
            self.cleanup()
            raise AssertionError('persistent client readiness timeout')
        line = self.process.stdout.readline()
        if not line:
            error = self.process.stderr.read().decode(errors='replace')
            self.cleanup()
            raise AssertionError('persistent client startup failed: '+error)
        self.ready = json.loads(line)
        assert self.ready['event'] == 'server.ready' and self.ready['port'] == self.port, self.ready
        self.client = Client(self.port)
        self.client.result('session.open', {'mode': 'developer', 'token': P.M.TOKEN})
        self.peer = self.client.result('ping')['peer']

    def pixels(self, expected):
        from PIL import Image
        deadline = time.monotonic()+20
        while time.monotonic() < deadline:
            try:
                image = Image.open(self.dump)
                data = image.tobytes()
                if image.size == (128, 128) and data == expected:
                    return data
            except (OSError, ValueError):
                pass
            if self.process.poll() is not None:
                break
            time.sleep(.01)
        raise AssertionError('persistent client did not show the independently expected complete image')

    def finish(self):
        self.client.close()
        self.client = None
        out, err = self.process.communicate(timeout=60)
        assert self.process.returncode == 0, (out[-2000:], err[-2000:])
        logs = [json.loads(line) for line in out.splitlines() if line.startswith(b'{')]
        with socket.socket() as probe:
            probe.settimeout(.5)
            assert probe.connect_ex(('127.0.0.1', self.port)) != 0
        return [row for row in logs if row.get('event') == 'client.snapshot']

    def cleanup(self):
        if self.client is not None:
            self.client.close()
            self.client = None
        if self.process.poll() is None:
            self.process.kill()
        self.process.communicate(timeout=10)


def main():
    from PIL import Image
    WORK.mkdir(parents=True, exist_ok=True)
    before_hashes = hashes()
    binary = WORK / 'client'
    report = WORK / 'native-build.json'
    _, _, build_seconds = R.run([R.PYTHON, 'tools/platform_build.py', 'persistent_client.bend',
                                 '-o', binary, '--report', report], hidden=True, timeout=300)
    identity, count, registry = P.registry_identity(P.OFFICIAL)
    with zipfile.ZipFile(R.JAR) as jar:
        textures = [Image.open(BytesIO(jar.read('assets/minecraft/textures/block/'+n+'.png'))).convert('RGBA')
                    for n in ['stone', 'dirt', 'oak_planks']]
    before = R.reference(128, textures, blocks(), (0, 0, 0, 0, .2))
    after = R.reference(128, textures, blocks(True), (0, 0, 0, 0, .2))
    save = WORK / 'world.nbt'
    if save.exists():
        save.unlink()
    first = Running(binary, save, WORK / 'first.ppm', create=True)
    try:
        first.pixels(before)
        initial = first.client.result('world.clock')
        assert initial['tick'] == 1 and initial['revision'] == 47 and initial['paused'] is True, initial
        catalog = first.client.result('discover')
        assert len(catalog['operations']) == 17
        planks = first.client.result('registry.state.resolve',
                                     {'name': 'minecraft:oak_planks', 'properties': {}, 'policy': 'defaults'})['state']
        for z in range(-3, 3):
            for x in range(-3, 3):
                first.client.result('world.block.set', {'dimension': 'minecraft:overworld', 'x': x, 'y': 0, 'z': z, 'state': planks})
        edited = first.client.result('simulation.step', {'ticks': 1})
        assert edited['tick'] == 2 and edited['revision'] == 83, edited
        first.pixels(after)
        published = first.client.result('world.save')
        assert published['published'] is True and published['durable'] is True, published
        raw = save.read_bytes()
        model, highwater, next_peer, world_bytes = P.validate_save(raw, count, identity)
        assert highwater >= first.peer and model['tick'] == 2 and model['revision'] == 83, (highwater, model)
        first_logs = first.finish()
        assert any(row['tick'] == 1 and row['revision'] == 47 for row in first_logs)
        assert any(row['tick'] == 2 and row['revision'] == 83 for row in first_logs)
    finally:
        first.cleanup()
    second = Running(binary, save, WORK / 'restart.ppm', frames=150)
    try:
        second.pixels(after)
        restored = second.client.result('world.clock')
        assert restored['tick'] == 2 and restored['revision'] == 83 and restored['paused'] is True, restored
        assert second.peer >= next_peer and second.peer > first.peer, (first.peer, second.peer, next_peer)
        for z in range(-3, 3):
            for x in range(-3, 3):
                assert second.client.result('world.block.get', {'dimension': 'minecraft:overworld', 'x': x, 'y': 0, 'z': z})['state'] == planks
        assert save.read_bytes() == raw, 'client reload republished or replaced its saved world'
        second_logs = second.finish()
        assert all(row['tick'] == 2 and row['revision'] == 83 for row in second_logs), second_logs[:3]
    finally:
        second.cleanup()
    assert hashes() == before_hashes, 'source generation changed while integration ran'
    result = {'date': datetime.now(timezone.utc).isoformat(), 'status': 'passed',
              'scope': 'finite shared save-owning actor client; no vanilla player/world/render claim',
              'source_sha256': before_hashes, 'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
              'native_build': json.loads(report.read_text()), 'build_seconds': build_seconds,
              'registry': registry, 'initial_clock': initial, 'edited_clock': edited, 'restored_clock': restored,
              'remote_edits': 36, 'persisted_blocks_checked': 36, 'catalog_operations': 17,
              'peer_before': first.peer, 'peer_after': second.peer, 'saved_highwater': highwater,
              'save_bytes': len(raw), 'save_sha256': hashlib.sha256(raw).hexdigest(),
              'independent_nbt_validation': True, 'independent_pixel_comparisons': 49152,
              'before_pixel_sha256': hashlib.sha256(before).hexdigest(),
              'after_and_restart_pixel_sha256': hashlib.sha256(after).hexdigest(),
              'first_frames': len(first_logs), 'restart_frames': len(second_logs),
              'teardown': 'both clients exited0 and real listener ports refused',
              'not_yet_persisted': ['view/body', 'inventory', 'player mode', 'mod state'],
              'confidence': 'high for recorded shared ownership, edit/save/restart and pixel observations'}
    (ROOT / 'evidence/persistent-client-integration.json').write_text(json.dumps(result, indent=2)+'\n')
    print(json.dumps(result, indent=2))


if __name__ == '__main__':
    main()
