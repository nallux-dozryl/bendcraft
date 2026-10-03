#!/usr/bin/env python3
"""Extract pinned vanilla full-cube face visibility without a client window.

The JVM executes unmodified Block/BlockState/Shapes/BlockPos methods. Python
supplies named state/position fixtures and verifies provenance/reproduction;
there is no Python gameplay or face-visibility implementation here.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import time
from urllib.parse import unquote, urlparse
import zipfile

from reference_inventory import ROOT, JAVA, canonical, fingerprint
from reference_model_probe import CLIENT, verified_client_classpath

OUTPUT = ROOT / 'reference/world_visibility.json'
WORK = ROOT / 'build/world-visibility-probe'
PINNED_CLIENT_SHA = '4508d006323f24fa02876310c192d739af56516eb259000ac50f0909a68c9a2d'
CLASSES = (
    'net.minecraft.world.level.block.Block',
    'net.minecraft.world.level.block.Blocks',
    'net.minecraft.world.level.block.AirBlock',
    'net.minecraft.world.level.block.state.BlockBehaviour',
    'net.minecraft.world.level.block.state.BlockBehaviour$BlockStateBase',
    'net.minecraft.world.level.block.state.BlockState',
    'net.minecraft.core.BlockPos', 'net.minecraft.core.Direction',
    'net.minecraft.world.phys.shapes.Shapes',
    'net.minecraft.world.phys.shapes.VoxelShape',
    'net.minecraft.world.phys.shapes.BooleanOp',
)
SOURCE = r'''
import com.google.gson.*;
import java.nio.file.*;
import java.security.*;
import java.lang.reflect.*;
import java.util.*;
import net.minecraft.SharedConstants;
import net.minecraft.server.Bootstrap;
import net.minecraft.core.*;
import net.minecraft.core.registries.*;
import net.minecraft.world.level.block.*;
import net.minecraft.world.level.block.state.*;
import net.minecraft.world.phys.AABB;
import net.minecraft.world.phys.shapes.*;

class WorldVisibilityProbe {
  static final Gson JSON = new GsonBuilder().disableHtmlEscaping().serializeNulls().create();
  static final String[] NAMES = {"minecraft:air","minecraft:stone","minecraft:dirt","minecraft:oak_planks"};
  static BlockState[] STATES;
  static final Direction[] DIRECTIONS = {Direction.DOWN,Direction.UP,Direction.NORTH,Direction.SOUTH,Direction.WEST,Direction.EAST};
  static List<Integer> pos(BlockPos p) {return List.of(p.getX(),p.getY(),p.getZ());}
  static List<Long> raw(BlockPos p) {return List.of(Integer.toUnsignedLong(p.getX()),Integer.toUnsignedLong(p.getY()),Integer.toUnsignedLong(p.getZ()));}
  static String bits(double value) {return String.format(Locale.ROOT,"%016x",Double.doubleToRawLongBits(value));}
  static int stateIndex(BlockState state) {for(int i=0;i<STATES.length;i++)if(STATES[i]==state)return i;throw new AssertionError("undeclared fixture state");}
  static String hash(byte[] data) throws Exception {return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(data));}
  static Map<String,Object> shape(VoxelShape value) {
    var boxes = new ArrayList<List<String>>();
    for(AABB box:value.toAabbs()) boxes.add(List.of(bits(box.minX),bits(box.minY),bits(box.minZ),bits(box.maxX),bits(box.maxY),bits(box.maxZ)));
    return Map.of("identity_block",value==Shapes.block(),"identity_empty",value==Shapes.empty(),
        "is_empty",value.isEmpty(),"aabbs_f64_bits",boxes);
  }
  static Map<String,Object> source(Class<?> type) throws Exception {
    String resource="/"+type.getName().replace('.','/')+".class";
    return Map.of("class",type.getName(),"class_sha256",hash(type.getResourceAsStream(resource).readAllBytes()),
        "code_source",type.getProtectionDomain().getCodeSource().getLocation().toString());
  }
  static int cacheSize() throws Exception {
    var field=Block.class.getDeclaredField("OCCLUSION_CACHE");field.setAccessible(true);
    return ((Map<?,?>)((ThreadLocal<?>)field.get(null)).get()).size();
  }
  static Map<String,Object> pair(BlockState current,BlockState adjacent,Direction direction) {
    VoxelShape other=adjacent.getFaceOcclusionShape(direction.getOpposite()),own=current.getFaceOcclusionShape(direction);
    boolean skip=current.skipRendering(adjacent,direction);
    boolean result=Block.shouldRenderFace(current,adjacent,direction);
    String inferred=other==Shapes.block()?"adjacent_block_identity":skip?"skip_rendering":
        other==Shapes.empty()?"adjacent_empty_identity":own==Shapes.empty()?"current_empty_identity":"shape_difference_cache";
    var out=new LinkedHashMap<String,Object>();
    out.put("current",NAMES[stateIndex(current)]);out.put("adjacent",NAMES[stateIndex(adjacent)]);
    out.put("direction",direction.toString());out.put("direction_ordinal",direction.ordinal());
    out.put("should_render_face",result);out.put("skip_rendering",skip);
    out.put("current_can_occlude",current.canOcclude());out.put("adjacent_can_occlude",adjacent.canOcclude());
    out.put("current_face_identity_block",own==Shapes.block());out.put("current_face_identity_empty",own==Shapes.empty());
    out.put("adjacent_face_identity_block",other==Shapes.block());out.put("adjacent_face_identity_empty",other==Shapes.empty());
    out.put("only_first_shape_nonempty",Shapes.joinIsNotEmpty(own,other,BooleanOp.ONLY_FIRST));
    out.put("face_shape_union_occludes",Shapes.faceShapeOccludes(own,other));
    out.put("bytecode_inferred_shortcut",inferred);return out;
  }
  static List<Map<String,Object>> positions() {
    var out=new ArrayList<Map<String,Object>>();out.add(Map.of("id","origin","position",List.of(0,0,0)));
    for(int mask=0;mask<8;mask++) {
      out.add(Map.of("id","far-"+mask,"position",List.of((mask&1)==0?30000000:-30000000,
          (mask&2)==0?30000000:-30000000,(mask&4)==0?30000000:-30000000)));
      out.add(Map.of("id","i32-boundary-"+mask,"position",List.of((mask&1)==0?Integer.MAX_VALUE:Integer.MIN_VALUE,
          (mask&2)==0?Integer.MAX_VALUE:Integer.MIN_VALUE,(mask&4)==0?Integer.MAX_VALUE:Integer.MIN_VALUE)));
    }
    return out;
  }
  static boolean mathematicalOverflow(BlockPos p,Direction d) {
    long x=(long)p.getX()+d.getStepX(),y=(long)p.getY()+d.getStepY(),z=(long)p.getZ()+d.getStepZ();
    return x<Integer.MIN_VALUE||x>Integer.MAX_VALUE||y<Integer.MIN_VALUE||y>Integer.MAX_VALUE||z<Integer.MIN_VALUE||z>Integer.MAX_VALUE;
  }
  static boolean inside(BlockPos p,int[] bounds) {
    return p.getX()>=bounds[0]&&p.getX()<bounds[0]+bounds[3]&&p.getY()>=bounds[1]&&p.getY()<bounds[1]+bounds[4]&&p.getZ()>=bounds[2]&&p.getZ()<bounds[2]+bounds[5];
  }
  static Map<String,Object> scene(String id,Map<BlockPos,BlockState> world,int[] bounds) {
    var sorted=new ArrayList<>(world.keySet());sorted.removeIf(p->!inside(p,bounds));
    sorted.sort(Comparator.<BlockPos>comparingInt(p->p.getZ()).thenComparingInt(p->p.getY()).thenComparingInt(p->p.getX()));
    var blocks=new ArrayList<Map<String,Object>>();int visible=0,hidden=0,outside=0;
    for(BlockPos p:sorted) {
      BlockState current=world.get(p);var faces=new ArrayList<Map<String,Object>>();int mask=0;
      for(Direction d:DIRECTIONS) {
        BlockPos next=p.relative(d);BlockState adjacent=world.getOrDefault(next,STATES[0]);
        var f=new LinkedHashMap<String,Object>(pair(current,adjacent,d));
        f.put("neighbor",pos(next));f.put("neighbor_u32",raw(next));f.put("neighbor_explicit_in_fixture",world.containsKey(next));
        f.put("neighbor_outside_snapshot",!inside(next,bounds));
        if(!inside(next,bounds))outside++;
        if((Boolean)f.get("should_render_face")){visible++;mask|=1<<d.ordinal();}else hidden++;
        faces.add(f);
      }
      blocks.add(Map.of("position",pos(p),"position_u32",raw(p),"state",NAMES[stateIndex(current)],
          "state_id",Block.getId(current),"visible_direction_mask",mask,"faces",faces));
    }
    var all=new ArrayList<Map<String,Object>>();var allPositions=new ArrayList<>(world.keySet());
    allPositions.sort(Comparator.<BlockPos>comparingInt(p->p.getZ()).thenComparingInt(p->p.getY()).thenComparingInt(p->p.getX()));
    for(BlockPos p:allPositions)all.add(Map.of("position",pos(p),"state",NAMES[stateIndex(world.get(p))]));
    return Map.of("id",id,"snapshot_bounds",Arrays.stream(bounds).boxed().toList(),"world_nonair_cells",all,
        "blocks",blocks,"block_count",blocks.size(),"visible_faces",visible,"hidden_faces",hidden,"outside_snapshot_neighbor_queries",outside);
  }
  static Map<BlockPos,BlockState> basic(boolean edited) {
    var world=new HashMap<BlockPos,BlockState>();
    for(int z=-3;z<=2;z++)for(int x=-3;x<=2;x++)world.put(new BlockPos(x,0,z),x==2?STATES[2]:STATES[1]);
    world.put(new BlockPos(1,1,1),STATES[2]);world.put(new BlockPos(2,1,2),STATES[3]);world.put(new BlockPos(2,2,2),STATES[3]);
    if(edited)world.put(new BlockPos(0,1,0),STATES[3]);return world;
  }
  public static void main(String[] args) throws Exception {
    SharedConstants.tryDetectVersion();Bootstrap.bootStrap();
    STATES=new BlockState[]{Blocks.AIR.defaultBlockState(),Blocks.STONE.defaultBlockState(),
        Blocks.DIRT.defaultBlockState(),Blocks.OAK_PLANKS.defaultBlockState()};
    var root=new LinkedHashMap<String,Object>();root.put("minecraft_version",SharedConstants.getCurrentVersion().id());
    var states=new ArrayList<Map<String,Object>>();
    for(int i=0;i<STATES.length;i++) {
      var faces=new TreeMap<String,Object>();for(Direction d:DIRECTIONS)faces.put(d.toString(),shape(STATES[i].getFaceOcclusionShape(d)));
      states.add(Map.of("name",NAMES[i],"state_id",Block.getId(STATES[i]),"block_class",STATES[i].getBlock().getClass().getName(),
          "can_occlude",STATES[i].canOcclude(),"solid_render",STATES[i].isSolidRender(),"is_air",STATES[i].isAir(),
          "occlusion_shape",shape(STATES[i].getOcclusionShape()),"face_occlusion_shapes",faces));
    }
    root.put("states",states);root.put("occlusion_cache_size_before",cacheSize());
    var matrix=new ArrayList<Map<String,Object>>();var stepping=new ArrayList<Map<String,Object>>();
    for(var item:positions()) {
      var coordinates=(List<Integer>)item.get("position");BlockPos p=new BlockPos(coordinates.get(0),coordinates.get(1),coordinates.get(2));
      for(Direction d:DIRECTIONS) {
        BlockPos next=p.relative(d);var step=new LinkedHashMap<String,Object>();
        step.put("position_id",item.get("id"));step.put("position",pos(p));step.put("position_u32",raw(p));
        step.put("direction",d.toString());step.put("direction_ordinal",d.ordinal());
        step.put("step",List.of(d.getStepX(),d.getStepY(),d.getStepZ()));
        step.put("neighbor",pos(next));step.put("neighbor_u32",raw(next));step.put("mathematical_i32_overflow",mathematicalOverflow(p,d));
        stepping.add(step);
        for(BlockState current:STATES)for(BlockState adjacent:STATES) {
          var result=new LinkedHashMap<String,Object>(pair(current,adjacent,d));result.putAll(step);matrix.add(result);
        }
      }
    }
    root.put("positions",positions());root.put("neighbor_steps",stepping);root.put("state_pair_matrix",matrix);
    var scenes=new ArrayList<Map<String,Object>>();
    scenes.add(scene("fixture-39",basic(false),new int[]{-4,-1,-4,8,6,8}));
    scenes.add(scene("fixture-edited-40",basic(true),new int[]{-4,-1,-4,8,6,8}));
    for(int mask=-1;mask<8;mask++) {
      int x=mask<0?0:(mask&1)==0?30000000:-30000000,y=mask<0?0:(mask&2)==0?30000000:-30000000,z=mask<0?0:(mask&4)==0?30000000:-30000000;
      var world=new HashMap<BlockPos,BlockState>();world.put(new BlockPos(x+1,y,z+1),STATES[1]);
      world.put(new BlockPos(x+2,y,z+1),STATES[2]);world.put(new BlockPos(x+1,y-1,z+1),STATES[3]);world.put(new BlockPos(x+1,y,z+2),STATES[1]);
      world.put(new BlockPos(x+3,y,z+1),STATES[1]);
      scenes.add(scene(mask<0?"halo-edge-origin":"halo-edge-far-"+mask,world,new int[]{x-1,y,z-1,3,2,3}));
    }
    root.put("scenes",scenes);root.put("occlusion_cache_size_after",cacheSize());
    var sources=new ArrayList<Map<String,Object>>();
    for(String name:args[1].split(","))sources.add(source(Class.forName(name)));
    root.put("loaded_class_sources",sources);Files.writeString(Path.of(args[0]),JSON.toJson(root));
  }
}
'''


def sha(data):
    return hashlib.sha256(data).hexdigest()


def run(command, timeout=120):
    started = time.monotonic()
    result = subprocess.run(list(map(str, command)), cwd=ROOT, capture_output=True,
                            text=True, timeout=timeout)
    if result.returncode:
        raise RuntimeError({'command': list(map(str, command)), 'exit_code': result.returncode,
                            'stdout': result.stdout[-3000:], 'stderr': result.stderr[-3000:]})
    return result, {'command': list(map(str, command)), 'seconds': round(time.monotonic() - started, 6),
                    'stdout_sha256': sha(result.stdout.encode()), 'stderr': result.stderr[-3000:]}


def sources(classpath):
    result, execution = run([JAVA.with_name('javap'), '-classpath', str(CLIENT), '-p', '-c', *CLASSES])
    path = WORK / 'official-method-bytecode.txt'
    path.write_text(result.stdout)
    classes = {}
    with zipfile.ZipFile(CLIENT) as archive:
        for name in CLASSES:
            raw = archive.read(name.replace('.', '/') + '.class')
            classes[name] = {'bytes': len(raw), 'sha256': sha(raw)}
    return {'classes': classes, 'javap_sha256': sha(result.stdout.encode()),
            'javap_bytes': len(result.stdout.encode()), 'java_harness_sha256': sha(SOURCE.encode()),
            'method_authority': 'Pinned production class bytes/declarations/bytecode and unmodified JVM method execution',
            'javap_run': execution}


def counts(observations):
    matrix = observations['state_pair_matrix']
    return {'positions': len(observations['positions']), 'state_pairs': 16, 'directions': 6,
            'state_pair_direction_position_observations': len(matrix),
            'neighbor_step_observations': len(observations['neighbor_steps']),
            'overflowing_neighbor_steps': sum(step['mathematical_i32_overflow'] for step in observations['neighbor_steps']),
            'render_face_true': sum(item['should_render_face'] for item in matrix),
            'render_face_false': sum(not item['should_render_face'] for item in matrix),
            'skip_rendering_true': sum(item['skip_rendering'] for item in matrix),
            'scenes': len(observations['scenes']),
            'scene_blocks': sum(scene['block_count'] for scene in observations['scenes']),
            'scene_face_observations': sum(scene['visible_faces'] + scene['hidden_faces'] for scene in observations['scenes'])}


def summary(observations):
    state_order = [state['name'] for state in observations['states']]
    direction_order = ['down', 'up', 'north', 'south', 'west', 'east']
    origin = {(record['current'], record['adjacent'], record['direction']): record['should_render_face']
              for record in observations['state_pair_matrix'] if record['position_id'] == 'origin'}
    return {'state_order': state_order, 'direction_order': direction_order,
            'directional_pair_matrices': {
                direction: [[origin[(current, adjacent, direction)] for adjacent in state_order]
                            for current in state_order] for direction in direction_order},
            'scene_summary': [{'id': scene['id'], 'blocks': scene['block_count'],
                               'visible_faces': scene['visible_faces'], 'hidden_faces': scene['hidden_faces'],
                               'ordered_direction_masks': [block['visible_direction_mask'] for block in scene['blocks']]}
                              for scene in observations['scenes']],
            'matrix_skip_rendering_true': sum(record['skip_rendering'] for record in observations['state_pair_matrix']),
            'observed_bytecode_shortcuts': sorted(set(record['bytecode_inferred_shortcut']
                                                     for record in observations['state_pair_matrix']))}


def validate(data):
    if data.get('schema') != 1 or data.get('pin') != '26.3':
        raise ValueError('Visibility reference schema/pin mismatch')
    observations = data['observations']
    if observations['minecraft_version'] != '26.3':
        raise ValueError('Executed Minecraft version mismatch')
    if sha(canonical(observations)) != data['observations_sha256']:
        raise ValueError('Visibility observation checksum mismatch')
    if data['counts'] != counts(observations):
        raise ValueError('Visibility counts mismatch')
    if data['summary'] != summary(observations):
        raise ValueError('Visibility matrix/mask projection mismatch')
    if data['source']['java_harness_sha256'] != sha(SOURCE.encode()):
        raise ValueError('Visibility harness source changed')
    if data['probe_sha256'] != sha(Path(__file__).read_bytes()):
        raise ValueError('Visibility Python probe source changed')
    for record in observations['loaded_class_sources']:
        expected = data['source']['classes'][record['class']]['sha256']
        if record['class_sha256'] != expected:
            raise ValueError('Loaded class differs from pinned client class: ' + record['class'])
        location = urlparse(record['code_source'])
        if location.scheme != 'file' or Path(unquote(location.path)).resolve() != CLIENT.resolve():
            raise ValueError('Visibility class was not loaded from the installed pinned client JAR')
    directions = ['down', 'up', 'north', 'south', 'west', 'east']
    seen = set()
    for record in observations['state_pair_matrix']:
        key = (record['position_id'], record['current'], record['adjacent'], record['direction'])
        if key in seen or record['direction'] != directions[record['direction_ordinal']]:
            raise ValueError('Duplicate/malformed matrix record')
        seen.add(key)
    if len(seen) != len(observations['positions']) * 16 * 6:
        raise ValueError('Incomplete visibility matrix')
    for scene in observations['scenes']:
        if len(scene['blocks']) != scene['block_count']:
            raise ValueError('Scene block count mismatch')
        for block in scene['blocks']:
            mask = sum(1 << face['direction_ordinal'] for face in block['faces'] if face['should_render_face'])
            if mask != block['visible_direction_mask'] or len(block['faces']) != 6:
                raise ValueError('Scene direction-mask inconsistency')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--verify-existing', action='store_true')
    args = parser.parse_args()
    WORK.mkdir(parents=True, exist_ok=True)
    classpath, provenance = verified_client_classpath()
    if provenance['client']['sha256'] != PINNED_CLIENT_SHA:
        raise ValueError('Client is not the pinned 26.3 JAR')
    source = sources(classpath)
    if args.verify_existing:
        data = json.loads(OUTPUT.read_text())
        validate(data)
        if data['provenance'] != provenance or data['source']['classes'] != source['classes'] or data['source']['javap_sha256'] != source['javap_sha256']:
            raise ValueError('Visibility provenance no longer matches installed artifacts')
        print(json.dumps({'status': 'verified-existing', 'counts': data['counts'], 'output_sha256': sha(OUTPUT.read_bytes())}))
        return
    java = WORK / 'WorldVisibilityProbe.java'
    java.write_text(SOURCE)
    cp = ':'.join(map(str, classpath))
    _, compile_run = run([JAVA.with_name('javac'), '-cp', cp, '-d', WORK, java])
    executions, observations = [], []
    for suffix in ('a', 'b'):
        output = WORK / f'observations-{suffix}.json'
        _, execution = run([JAVA, '-cp', str(WORK) + ':' + cp, 'WorldVisibilityProbe', output, ','.join(CLASSES)])
        executions.append(execution)
        observations.append(json.loads(output.read_text()))
    if observations[0] != observations[1]:
        raise ValueError('Two fresh unmodified JVM observations differ')
    data = {'schema': 1, 'pin': '26.3', 'timestamp_utc': datetime.now(timezone.utc).isoformat(),
            'scope': 'Actual default air/stone/dirt/oak_planks state pairs and BlockPos stepping only; no window/client activation',
            'pair_method': 'Block.shouldRenderFace(BlockState current, BlockState adjacent, Direction)',
            'world_boundary': 'Pair API reads no world/position. Scene caller uses declared readonly block maps; unlisted cells are explicit fixture air.',
            'shortcut_boundary': 'bytecode_inferred_shortcut labels infer the first return branch from observed shape identity and skipRendering; production classes are not instrumented.',
            'coordinate_boundary': 'Actual Java BlockPos.relative wraps signed int overflow.',
            'provenance': provenance, 'source': source, 'probe_sha256': sha(Path(__file__).read_bytes()),
            'java_compile': compile_run, 'java_runs': executions,
            'observations': observations[0], 'observations_sha256': sha(canonical(observations[0])),
            'counts': counts(observations[0]), 'fresh_jvm_reproductions': 2}
    data['summary'] = summary(observations[0])
    validate(data)
    OUTPUT.write_text(json.dumps(data, sort_keys=True, indent=2) + '\n')
    print(json.dumps({'status': 'passed', 'counts': data['counts'], 'output_sha256': sha(OUTPUT.read_bytes()),
                      'scene_summary': [{'id': scene['id'], 'blocks': scene['block_count'],
                                         'visible': scene['visible_faces'], 'hidden': scene['hidden_faces']}
                                        for scene in observations[0]['scenes']]}))


if __name__ == '__main__':
    main()
