#!/usr/bin/env python3
"""Run unchanged persistent-client integration checks against a cached artifact."""
from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
from io import BytesIO
import json
import os
from pathlib import Path
import tempfile
import time
import zipfile

import platform_cache as C
import test_persistent_client as B

ROOT = B.ROOT
SOURCE_KINDS = {"base", "bend", "native-effect", "bend-executable", "package-name",
                "cache-policy", "platform-cache-policy", "guarded-transform-policy"}
HELPERS = ["tools/test_persistent_client.py", "tools/test_client_render.py", "tools/test_persistence.py",
           "tools/test_server.py", "tools/test_live.py", "tools/test_world_codec.py", "tools/test_nbt.py",
           "tools/platform_cache.py", "tools/build_native.py", "tools/platform_build.py"]


def sha(path):
    return C.native.file_digest(Path(path))


def source_dependencies(report):
    return {item["path"]: item["sha256"] for item in report["dependencies"] if item["kind"] in SOURCE_KINDS}


def build_summary(report, *, include_sources=True):
    keys = ("path", "artifact", "cache_key", "cache_hit", "binary_sha256", "binary_bytes",
            "original_c_sha256", "transformed_c_sha256", "route", "output_replaced", "retries", "timings")
    tool_kinds = {"clang-driver", "clang-tool", "clang-driver-input", "toolchain-dylib-or-tool",
                  "clang-config", "objc-clang-config", "sdk-config", "bend-executable"}
    summarized = {**{key: report[key] for key in keys}, "dependency_count": len(report["dependencies"]),
            "dependency_kind_counts": dict(sorted(Counter(item["kind"] for item in report["dependencies"]).items())),
            "dependency_manifest_sha256": C.native.digest(C.native.encoded(report["dependencies"])),
            "environment_sha256": report["identity"]["environment_sha256"],
            "compiler": {"path": report["compiler"]["path"], "version": report["compiler"]["version"],
                         "resource_dir": report["compiler"]["resource_dir"], "sysroots": report["compiler"]["sysroots"],
                         "objc_flags": report["identity"]["objc_flags"],
                         "objc_driver_probe_sha256": C.native.digest(report["identity"]["objc_driver_probe"].encode()),
                         "selected_tool_and_config_sha256": {item["path"]:item["sha256"] for item in report["dependencies"]
                                                             if item["kind"] in tool_kinds}},
            "platform": {key: report["identity"][key] for key in ("system", "machine", "platform", "os_build")}}
    if include_sources:
        summarized["source_dependency_sha256"] = {
            str(Path(path).relative_to(ROOT)) if Path(path).is_relative_to(ROOT) else path: value
            for path, value in sorted(source_dependencies(report).items())}
    return summarized


def write_report(path, evidence):
    path.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(prefix='.persistent-client-cache-', dir=path.parent, delete=False) as output:
        output.write(json.dumps(evidence, indent=2).encode() + b'\n')
        temporary = output.name
    os.replace(temporary, path)


def summarize_cold(full_path, summary_path):
    assert full_path.resolve() != summary_path.resolve(), 'full report must stay separate'
    report = json.loads(full_path.read_text())
    assert not report['cache_hit'] and report['route'] == 'guarded-macos-cpu-window'
    assert Path(report['identity']['entry']).resolve() == ROOT / 'persistent_client.bend', 'cold report is not the persistent-client entry'
    assert sha(report['artifact']) == sha(report['path']) == report['binary_sha256']
    evidence = {'date': datetime.now(timezone.utc).isoformat(), 'status': 'built',
                'scope': 'single actual guarded persistent-client CPU compilation; integration is recorded separately',
                'full_report': str(full_path), 'full_report_sha256': sha(full_path),
                'command': 'python3 tools/platform_cache.py build persistent_client.bend -o build/persistent-client-cached --report build/persistent-client-cache-cold.full.json',
                'summary_tool_sha256': sha(Path(__file__)), **build_summary(report)}
    write_report(summary_path, evidence)
    return evidence


def audit(cold, warm, baseline, profile):
    assert cold["route"] == warm["route"] == "guarded-macos-cpu-window"
    assert not cold["cache_hit"], "supplied cold report is already a hit"
    assert warm["cache_hit"], "current environment/input generation did not reuse the supplied cold build"
    assert warm["timings"]["emission_seconds"] == warm["timings"]["guarded_native_build_seconds"] == 0
    for key in ("cache_key", "binary_sha256", "original_c_sha256", "transformed_c_sha256", "dependencies"):
        assert cold[key] == warm[key], "cold/warm build generation differs: " + key
    assert Path(warm["artifact"]).is_file() and os.access(warm["artifact"], os.X_OK)
    assert sha(warm["artifact"]) == sha(warm["path"]) == warm["binary_sha256"]
    native = baseline["native_build"]
    variant = profile["variants"]["persistent"]
    assert warm["original_c_sha256"] == native["generated_sha256"] == variant["raw_c"]["sha256"]
    assert warm["transformed_c_sha256"] == native["transformed_sha256"] == variant["transformed_c_sha256"]
    before = B.hashes()
    assert before == baseline["source_sha256"], "unchanged baseline integration source set differs"
    profiled = {item["path"]: item["sha256"] for item in profile["snapshot"]["files"]}
    sources = source_dependencies(warm)
    compared = {}
    for item in warm["dependencies"]:
        if item["kind"] not in {"base", "bend", "native-effect", "package-name"}:
            continue
        path = item["path"]
        assert path in profiled, "profile does not cover source dependency: " + path
        assert item["sha256"] == profiled[path] == sha(path), "profile/current source dependency differs: " + path
        compared[path] = item["sha256"]
    assert sources[str((ROOT / "persistent_client.bend").resolve())] == profile["snapshot"]["persistent_entry_sha256"]
    assert sources[str((ROOT / "src/client_world.bend").resolve())] == "05040abf35b2b9ceaf87fed5c48f8d074d211750a59ab00fa6ff08e60a9ea5d7"
    return {"cold_warm_key_binary_and_all_dependencies_equal": True,
            "warm_emission_and_native_build_skipped": True,
            "baseline_and_profile_original_transformed_c_equal": True,
            "unchanged_baseline_sources_equal": True,
            "profile_source_dependency_count": len(compared),
            "source_dependency_sha256": {str(Path(path).relative_to(ROOT)) if Path(path).is_relative_to(ROOT) else path: value
                                         for path, value in sorted(sources.items())}}


def integration(binary, work):
    """Replay B.main's behavior/assertions using B's real client/oracle helpers."""
    from PIL import Image
    identity, count, registry = B.P.registry_identity(B.P.OFFICIAL)
    with zipfile.ZipFile(B.R.JAR) as jar:
        textures = [Image.open(BytesIO(jar.read('assets/minecraft/textures/block/'+name+'.png'))).convert('RGBA')
                    for name in ['stone', 'dirt', 'oak_planks']]
    before = B.R.reference(128, textures, B.blocks(), (0, 0, 0, 0, .2))
    after = B.R.reference(128, textures, B.blocks(True), (0, 0, 0, 0, .2))
    save = work / 'world.nbt'
    if save.exists():
        save.unlink()
    first = B.Running(binary, save, work / 'first.ppm', create=True)
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
        model, highwater, next_peer, world_bytes = B.P.validate_save(raw, count, identity)
        assert highwater >= first.peer and model['tick'] == 2 and model['revision'] == 83, (highwater, model)
        first_logs = first.finish()
        assert any(row['tick'] == 1 and row['revision'] == 47 for row in first_logs)
        assert any(row['tick'] == 2 and row['revision'] == 83 for row in first_logs)
    finally:
        first.cleanup()
    second = B.Running(binary, save, work / 'restart.ppm', frames=150)
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
    assert len(first_logs) == 500 and len(second_logs) == 150, (len(first_logs), len(second_logs))
    return {'registry': registry, 'initial_clock': initial, 'edited_clock': edited, 'restored_clock': restored,
            'remote_edits': 36, 'persisted_blocks_checked': 36, 'catalog_operations': 17,
            'peer_before': first.peer, 'peer_after': second.peer, 'saved_highwater': highwater,
            'save_bytes': len(raw), 'save_sha256': hashlib.sha256(raw).hexdigest(),
            'independent_nbt_validation': True, 'independent_pixel_comparisons': 49152,
            'before_pixel_sha256': hashlib.sha256(before).hexdigest(),
            'after_and_restart_pixel_sha256': hashlib.sha256(after).hexdigest(),
            'first_frames': len(first_logs), 'restart_frames': len(second_logs),
            'teardown': 'both clients exited0 and real listener ports refused',
            'hidden_launches': 2, 'launch_mode': 'BEND_MINECRAFT_LAUNCH_MODE=hidden; --gpu off',
            'not_yet_persisted': ['view/body', 'inventory', 'player mode', 'mod state']}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--cold-report', type=Path, default=ROOT / 'build/persistent-client-cache-cold.full.json',
                        help='ignored complete cold build report, including dependency rows')
    parser.add_argument('--cold-summary', type=Path, default=ROOT / 'evidence/persistent-client-cache-cold.json')
    parser.add_argument('--report', type=Path, default=ROOT / 'evidence/persistent-client-cache-integration.json')
    parser.add_argument('--cache-dir', type=Path)
    parser.add_argument('--summarize-cold-only', action='store_true', help='compact an actual successful cold report without building/launching')
    args = parser.parse_args()
    assert args.report.resolve() != args.cold_report.resolve(), 'cold build evidence is read-only'
    if args.summarize_cold_only:
        result = summarize_cold(args.cold_report, args.cold_summary)
        print(json.dumps({'status':result['status'], 'summary':str(args.cold_summary),
                          'dependency_count':result['dependency_count'], 'timings':result['timings']}, indent=2))
        return
    started = time.perf_counter()
    frozen_reports = [args.cold_report, ROOT / 'evidence/persistent-client-integration.json',
                      ROOT / 'evidence/client-build-profile.json']
    assert args.report.resolve() not in {path.resolve() for path in frozen_reports+[args.cold_summary]}, 'baseline evidence is read-only'
    report_hashes = {str(path): sha(path) for path in frozen_reports}
    cold, baseline, profile = [json.loads(path.read_text()) for path in frozen_reports]
    compact = json.loads(args.cold_summary.read_text())
    report_hashes[str(args.cold_summary)] = sha(args.cold_summary)
    assert compact['full_report_sha256'] == report_hashes[str(args.cold_report)]
    assert compact['dependency_manifest_sha256'] == C.native.digest(C.native.encoded(cold['dependencies']))
    helper_before = {path: sha(ROOT / path) for path in HELPERS}
    source_before = B.hashes()
    work = ROOT / 'build/persistent-client-cache-integration'
    work.mkdir(parents=True, exist_ok=True)
    warm = C.ensure_platform(ROOT / 'persistent_client.bend', work / 'client', cache_dir=args.cache_dir)
    audited = audit(cold, warm, baseline, profile)
    binary = Path(warm['artifact'])
    executed = time.perf_counter()
    result = integration(binary, work)
    integration_seconds = time.perf_counter() - executed
    assert B.hashes() == source_before, 'baseline source generation changed during cached integration'
    assert {path: sha(ROOT / path) for path in HELPERS} == helper_before, 'baseline test/cache policies changed'
    assert {str(path): sha(path) for path in frozen_reports+[args.cold_summary]} == report_hashes, 'original evidence changed'
    for path, value in source_dependencies(warm).items():
        assert sha(path) == value, 'source dependency changed during cached integration: ' + path
    assert sha(binary) == warm['binary_sha256'], 'immutable artifact changed during execution'
    for key in ('initial_clock', 'edited_clock', 'restored_clock', 'remote_edits', 'persisted_blocks_checked',
                'catalog_operations', 'save_bytes', 'save_sha256', 'before_pixel_sha256',
                'after_and_restart_pixel_sha256', 'first_frames', 'restart_frames'):
        assert result[key] == baseline[key], 'cached execution differs from unchanged baseline: ' + key
    evidence = {'date': datetime.now(timezone.utc).isoformat(), 'status': 'passed',
                'scope': 'actual guarded CPU cached finite shared actor edit/save/restart; no vanilla gameplay or visible presentation claim',
                'command': 'python3 tools/test_persistent_client_cache.py',
                'test_sha256': sha(Path(__file__)), 'helper_sha256': helper_before,
                'referenced_evidence_sha256': report_hashes, 'source_sha256': source_before,
                'cold_build': build_summary(cold, include_sources=False),
                'warm_build': build_summary(warm, include_sources=False), 'audit': audited,
                'executed_artifact': str(binary), 'binary_sha256': sha(binary),
                'integration_seconds': integration_seconds, 'total_seconds': time.perf_counter() - started,
                'timing_scope': 'single cold/warm compilation observations; no runtime or whole-game speedup claim',
                'confidence': 'high for recorded source/hash/cache reuse and preserved actual hidden integration checks',
                **result}
    write_report(args.report, evidence)
    print(json.dumps({'status': evidence['status'], 'report': str(args.report),
                      'cold_seconds': cold['timings'], 'warm_seconds': warm['timings'],
                      'integration_seconds': integration_seconds, 'pixel_comparisons': result['independent_pixel_comparisons'],
                      'source_dependencies_compared_with_profile': audited['profile_source_dependency_count']}, indent=2))


if __name__ == '__main__':
    main()
