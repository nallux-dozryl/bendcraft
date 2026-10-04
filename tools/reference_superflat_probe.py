#!/usr/bin/env python3
"""Narrow pinned FlatLevelSource base-column/base-height observation.

The untouched Java generator owns expected states/heights. This does not observe
feature, structure, biome, noise, lighting, spawn selection, or chunk filling.
"""
from __future__ import annotations
import argparse, hashlib, json, os, signal, subprocess, time, zipfile
from pathlib import Path
from reference_inventory import ROOT, JAVA, canonical, fingerprint, write_json
from reference_block_probe import verified_classpath

WORK = ROOT / 'build/superflat-world/reference'
OUTPUT = ROOT / 'reference/superflat_world.json'
OWNERS = ['net.minecraft.world.level.levelgen.FlatLevelSource',
          'net.minecraft.world.level.levelgen.flat.FlatLevelGeneratorSettings',
          'net.minecraft.world.level.levelgen.flat.FlatLayerInfo',
          'net.minecraft.data.registries.VanillaRegistries',
          'net.minecraft.world.level.NoiseColumn',
          'net.minecraft.world.level.LevelHeightAccessor',
          'net.minecraft.resources.RegistryOps',
          'net.minecraft.world.level.levelgen.Heightmap$Types']

SOURCE = r'''import java.util.*;
import com.google.gson.*;
import com.mojang.serialization.JsonOps;
import net.minecraft.SharedConstants;
import net.minecraft.server.Bootstrap;
import net.minecraft.data.registries.VanillaRegistries;
import net.minecraft.resources.RegistryOps;
import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.world.level.LevelHeightAccessor;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.levelgen.FlatLevelSource;
import net.minecraft.world.level.levelgen.Heightmap;
import net.minecraft.world.level.levelgen.flat.FlatLevelGeneratorSettings;

class ReferenceSuperflatProbe {
  public static void main(String[] args) {
    var output = System.out;
    SharedConstants.tryDetectVersion();
    Bootstrap.bootStrap();
    var ops = RegistryOps.create(JsonOps.INSTANCE, VanillaRegistries.createWorldLookup());
    var height = LevelHeightAccessor.create(-64,384);
    var profiles = new LinkedHashMap<String,String>();
    profiles.put("bendex:stone-dirt-superflat", "stone,stone");
    profiles.put("minecraft:classic_flat", "bedrock,grass_block");
    var cases = new ArrayList<Map<String,Object>>();
    for (var profile : profiles.entrySet()) {
      var names = profile.getValue().split(",");
      var data = JsonParser.parseString("{\"biome\":\"minecraft:plains\",\"features\":false,\"lakes\":false,\"structure_overrides\":[],\"layers\":[{\"height\":1,\"block\":\"minecraft:" + names[0] + "\"},{\"height\":2,\"block\":\"minecraft:dirt\"},{\"height\":1,\"block\":\"minecraft:" + names[1] + "\"}]}");
      var settings = FlatLevelGeneratorSettings.CODEC.parse(ops,data).getOrThrow();
      var generator = new FlatLevelSource(settings);
      for (int[] p : new int[][]{{-32,-32},{-17,-1},{-16,0},{-1,15},{0,16},{15,31},{16,32},{47,47}}) {
        var column = generator.getBaseColumn(p[0],p[1],height,null);
        var cells = new ArrayList<Map<String,Object>>();
        for (int y : new int[]{-80,-65,-64,-63,-62,-61,-60,-33,319,320}) {
          var state = column.getBlock(y);
          cells.add(Map.of("y",y,"state",Block.getId(state),"block",BuiltInRegistries.BLOCK.getKey(state.getBlock()).toString()));
        }
        var heights = new TreeMap<String,Integer>();
        for (var type : Heightmap.Types.values())
          heights.put(type.getSerializedName(),generator.getBaseHeight(p[0],p[1],type,height,null));
        cases.add(Map.of("profile",profile.getKey(),"x",p[0],"z",p[1],"column",cells,"heights",heights));
      }
    }
    output.println("SUPERFLAT_JSON:" + new Gson().toJson(cases));
  }
}
'''

def run(label, argv, cap):
    directory = WORK / label
    directory.mkdir(parents=True, exist_ok=False)
    record = {'argv': list(map(str, argv)), 'cwd': str(ROOT), 'cap_seconds': cap,
              'status': 'running', 'retry': False}
    write_json(directory / 'process.json', record)
    started = time.monotonic()
    process = None
    try:
        process = subprocess.Popen(argv, cwd=ROOT, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, start_new_session=True)
        record['pid'] = record['pgid'] = process.pid
        try:
            stdout, stderr = process.communicate(timeout=cap)
            record['timed_out'] = False
        except subprocess.TimeoutExpired:
            record['timed_out'] = True
            os.killpg(process.pid, signal.SIGKILL)
            stdout, stderr = process.communicate(timeout=5)
        record['exit_code'] = process.returncode
        (directory / 'stdout').write_bytes(stdout)
        (directory / 'stderr').write_bytes(stderr)
    finally:
        if process is not None:
            try:
                os.killpg(process.pid, 0)
                record['group_absent'] = False
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                record['group_absent'] = True
            record['leader_reaped'] = process.poll() is not None
        record['seconds'] = time.monotonic() - started
        for name in ('stdout', 'stderr'):
            path = directory / name
            if not path.exists(): path.write_bytes(b'')
            record[name] = fingerprint(path)
        record['status'] = ('passed' if record.get('exit_code') == 0 and
                            not record.get('timed_out') and record.get('group_absent')
                            and record.get('leader_reaped') else 'failed')
        write_json(directory / 'process.json', record)
    if record['status'] != 'passed':
        raise RuntimeError('Bounded attempt failed: ' + str(directory))
    return (directory / 'stdout').read_text(), record

def signatures():
    jars, release = verified_classpath()
    WORK.mkdir(parents=True, exist_ok=True)
    # Verification reuses existing official extraction and classpath bootstrap.
    # Previously observed installed preset/minY bytes are not re-extracted.
    facts = {'classpath': list(map(str, jars)),
             'checkpoint': [{ 'path': str(p), 'size': p.stat().st_size,
                              'mtime_ns': p.stat().st_mtime_ns } for p in jars],
             'server_bundle_sha256': release['server_bundle']['sha256'],
             'server_class_jar_sha256': release['server_bundle']['nested_server_sha256']}
    write_json(WORK / 'classpath.json', facts)
    text, receipt = run('signatures', [JAVA.parent / 'javap', '-classpath', jars[0],
                                      '-p', *OWNERS], 30)
    declarations = [line for line in text.splitlines()
                    if line.startswith(('public class ', 'public final class ', 'public interface '))]
    if any(not any(owner in line for line in declarations) for owner in OWNERS):
        raise RuntimeError('javap batch omitted a required class declaration')
    if receipt['stderr']['bytes']:
        raise RuntimeError('javap diagnostic retained; signatures are incomplete')
    write_json(ROOT / 'evidence/superflat-world-signatures.json',
               {'status': 'passed', 'pin': '26.3', 'owners': OWNERS,
                'execution': receipt, 'classpath': facts,
                'signatures_sha256': hashlib.sha256(text.encode()).hexdigest()})
    print(text)

def observe():
    facts = json.loads((WORK / 'classpath.json').read_text())
    for item in facts['checkpoint']:
        path = Path(item['path'])
        if path.stat().st_size != item['size'] or path.stat().st_mtime_ns != item['mtime_ns']:
            raise RuntimeError('Previously verified classpath checkpoint changed')
    source = WORK / 'ReferenceSuperflatProbe.java'
    source.write_text(SOURCE)
    text, execution = run('observe', [JAVA, '--source', '25', '--class-path',
                                     ':'.join(facts['classpath']), source], 60)
    matches = [line.removeprefix('SUPERFLAT_JSON:') for line in text.splitlines()
               if line.startswith('SUPERFLAT_JSON:')]
    if len(matches) != 1: raise RuntimeError('Actual generator output missing or duplicated')
    cases = json.loads(matches[0])
    if len(cases) != 16: raise RuntimeError('Actual generator case count differs')
    presets = {}
    install = Path.home() / 'Library/Application Support/minecraft/versions/26.3/26.3.jar'
    with zipfile.ZipFile(install) as archive:
        for member in ('data/minecraft/worldgen/world_preset/flat.json',
                       'data/minecraft/worldgen/flat_level_generator_preset/classic_flat.json',
                       'data/minecraft/dimension_type/overworld.json'):
            data = archive.read(member)
            presets[member] = {'sha256': hashlib.sha256(data).hexdigest(),
                               'bytes': len(data), 'json': json.loads(data)}
    result = {'schema_version': 1, 'pin': '26.3', 'status': 'observed',
              'confidence': 'high for these actual base-column/base-height calls',
              'scope': 'Configured four-layer FlatLevelSource only; no fill, structures, features, noise, biome generation or spawn-selection parity',
              'profiles': {'bendex:stone-dirt-superflat': ['stone', 'dirt', 'dirt', 'stone'],
                           'minecraft:classic_flat': ['bedrock', 'dirt', 'dirt', 'grass_block']},
              'cases': cases, 'cases_sha256': hashlib.sha256(canonical(cases)).hexdigest(),
              'execution': execution, 'source_sha256': hashlib.sha256(SOURCE.encode()).hexdigest(),
              'verified_classpath': facts, 'installed_source_entries': presets,
              'boundary': 'RegistryOps/CODEC creates settings; production methods receive real -64/384 LevelHeightAccessor and null unused RandomState. Structure overrides explicitly empty; only layer and height methods observed.',
              'signature_correction': 'First javap batch named NoiseColumn under levelgen; javap exited zero but printed class-not-found. Corrected level.NoiseColumn receipt retained separately; generator/settings signatures succeeded in first batch.'}
    write_json(OUTPUT, result)
    write_json(ROOT / 'evidence/superflat-world-reference.json',
               {'status': 'passed', 'reference': fingerprint(OUTPUT),
                'cases': len(cases), 'actual_column_cells': sum(len(c['column']) for c in cases),
                'execution': execution, 'scope': result['scope']})
    print(json.dumps({'status': 'passed', 'cases': len(cases), 'reference': str(OUTPUT)}))

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument('--signatures', action='store_true')
    group.add_argument('--observe', action='store_true')
    args = parser.parse_args()
    if args.signatures: signatures()
    else: observe()

if __name__ == '__main__': main()
