#!/usr/bin/env python3
"""Observe pinned Java26.3 sky sources, receiver, and sparse storage lookup.

Python declares geometry and validates pinned artifacts. All source-height,
occlusion, propagation, section allocation, and light lookup run in official
unmodified Java classes. No client instance, world launch, or native renderer.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import time
import zipfile
from reference_inventory import ROOT, canonical
from reference_model_probe import CLIENT, JAVA, verified_client_classpath

WORK = ROOT / 'build/sky-light-reference'
OUTPUT = ROOT / 'reference/sky_light.json'
EVIDENCE = ROOT / 'evidence/sky-light-reference.json'
CLASSES = [
    'net.minecraft.world.level.lighting.SkyLightEngine',
    'net.minecraft.world.level.lighting.SkyLightSectionStorage',
    'net.minecraft.world.level.lighting.SkyLightSectionStorage$SkyDataLayerStorageMap',
    'net.minecraft.world.level.lighting.ChunkSkyLightSources',
    'net.minecraft.world.level.lighting.LightEngine',
    'net.minecraft.world.level.lighting.LightEngine$QueueEntry',
    'net.minecraft.world.level.lighting.LayerLightSectionStorage',
    'net.minecraft.world.level.lighting.DataLayerStorageMap',
    'net.minecraft.world.level.chunk.ProtoChunk',
    'net.minecraft.world.level.chunk.ChunkAccess',
    'net.minecraft.world.level.chunk.LevelChunkSection',
    'net.minecraft.world.level.chunk.PalettedContainer',
    'net.minecraft.world.level.chunk.Strategy',
    'net.minecraft.world.level.chunk.DataLayer',
    'net.minecraft.world.level.LevelHeightAccessor',
    'net.minecraft.world.phys.shapes.Shapes',
]

SOURCE = r'''import java.nio.file.*;import java.util.*;import java.lang.reflect.*;
import com.google.gson.*;import net.minecraft.SharedConstants;import net.minecraft.server.Bootstrap;
import net.minecraft.core.*;import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.world.level.*;import net.minecraft.world.level.block.*;
import net.minecraft.world.level.block.entity.BlockEntity;import net.minecraft.world.level.block.state.*;
import net.minecraft.world.level.block.state.properties.Property;import net.minecraft.world.level.chunk.*;
import net.minecraft.world.level.lighting.*;import net.minecraft.world.level.material.FluidState;
class SkyLightReference {
 static Gson JSON=new GsonBuilder().serializeNulls().create();
 static Map<String,BlockState> states=new LinkedHashMap<>();
 static BlockPos pos(JsonArray a){return new BlockPos(a.get(0).getAsInt(),a.get(1).getAsInt(),a.get(2).getAsInt());}
 static ChunkPos chunk(JsonArray a){return new ChunkPos(a.get(0).getAsInt(),a.get(1).getAsInt());}
 static <T extends Comparable<T>> String value(Property<T> p,BlockState s){return p.getName(s.getValue(p));}
 static BlockState resolve(JsonObject input){
  String name="minecraft:"+input.get("name").getAsString();JsonObject properties=input.getAsJsonObject("properties");
  for(BlockState s:Block.BLOCK_STATE_REGISTRY){
   if(!BuiltInRegistries.BLOCK.getKey(s.getBlock()).toString().equals(name))continue;
   boolean good=true;for(var e:properties.entrySet()){
    Property<?> p=s.getBlock().getStateDefinition().getProperty(e.getKey());
    if(p==null||!value(p,s).equals(e.getValue().getAsString())){good=false;break;}
   }if(good)return s;
  }throw new IllegalArgumentException("No registered state:"+input);
 }
 static Method method(Class<?> c,String name,Class<?>...args)throws Exception{Method m=c.getDeclaredMethod(name,args);m.setAccessible(true);return m;}
 static Object field(Object x,Class<?> c,String name)throws Exception{Field f=c.getDeclaredField(name);f.setAccessible(true);return f.get(x);}
 static class Fixture implements BlockGetter,LightChunkGetter {
  final LevelHeightAccessor height;final Map<ChunkPos,ProtoChunk> chunks=new LinkedHashMap<>();
  Fixture(int minY,int h){height=LevelHeightAccessor.create(minY,h);}
  public int getHeight(){return height.getHeight();}public int getMinY(){return height.getMinY();}
  void add(ChunkPos p,BlockState defaultState){
   LevelChunkSection[] sections=new LevelChunkSection[height.getSectionsCount()];
   for(int i=0;i<sections.length;i++)sections[i]=new LevelChunkSection(
    new PalettedContainer<BlockState>(defaultState,Strategy.createForBlockStates(Block.BLOCK_STATE_REGISTRY)),null);
   // Source scan/lighting never consumes biomes, ticks, factory, or blending.
   // All block sections are actual official palettes with actual block counts.
   chunks.put(p,new ProtoChunk(p,UpgradeData.EMPTY,sections,null,null,height,null,null));
  }
  ProtoChunk resident(BlockPos p){return chunks.get(new ChunkPos(p.getX()>>4,p.getZ()>>4));}
  void write(BlockPos p,BlockState s){ProtoChunk c=resident(p);if(c==null||height.isOutsideBuildHeight(p))throw new IllegalArgumentException("Write outside declared chunks/height:"+p);
   c.getSection(height.getSectionIndex(p.getY())).setBlockState(p.getX()&15,p.getY()&15,p.getZ()&15,s);
  }
  void fill(JsonObject f){BlockPos a=pos(f.getAsJsonArray("from")),b=pos(f.getAsJsonArray("to"));BlockState s=states.get(f.get("state").getAsString());
   for(int y=a.getY();y<=b.getY();y++)for(int z=a.getZ();z<=b.getZ();z++)for(int x=a.getX();x<=b.getX();x++)write(new BlockPos(x,y,z),s);
  }
  public BlockEntity getBlockEntity(BlockPos p){return null;}
  public BlockState getBlockState(BlockPos p){ProtoChunk c=resident(p);return c==null?Blocks.BEDROCK.defaultBlockState():c.getBlockState(p);}
  public FluidState getFluidState(BlockPos p){return getBlockState(p).getFluidState();}
  public LightChunk getChunkForLighting(int x,int z){return chunks.get(new ChunkPos(x,z));}
  public BlockGetter getLevel(){return this;}
  Integer source(BlockPos p){ProtoChunk c=resident(p);return c==null?null:c.getSkyLightSources().getLowestSourceY(p.getX()&15,p.getZ()&15);}
 }
 static int drain(SkyLightEngine e){int work=e.runLightUpdates();for(int i=0;i<100;i++){if(!e.hasLightWork())return work;work+=e.runLightUpdates();}throw new AssertionError("Sky receiver did not settle");}
 static Map<String,Object> snapshot(String label,Fixture f,SkyLightEngine e,List<BlockPos> samples,int work)throws Exception{
  var levels=new ArrayList<Integer>();var heights=new ArrayList<Integer>();var stateIds=new ArrayList<Integer>();
  var stored=new ArrayList<Boolean>();var enabled=new ArrayList<Boolean>();var updateLevels=new ArrayList<Integer>();
  Object storage=field(e,LightEngine.class,"storage");
  Method has=method(LayerLightSectionStorage.class,"storingLightForSection",long.class);
  Method on=method(LayerLightSectionStorage.class,"lightOnInSection",long.class);
  Method updating=method(SkyLightSectionStorage.class,"getLightValue",long.class,boolean.class);
  for(BlockPos p:samples){levels.add(e.getLightValue(p));heights.add(f.source(p));stateIds.add(Block.getId(f.getBlockState(p)));
   long section=SectionPos.blockToSection(p.asLong());stored.add((boolean)has.invoke(storage,section));enabled.add((boolean)on.invoke(storage,section));
   updateLevels.add((int)updating.invoke(storage,p.asLong(),true));
  }
  var out=new LinkedHashMap<String,Object>();out.put("id",label);out.put("levels",levels);out.put("lowest_source_y",heights);out.put("state_ids",stateIds);
  out.put("stored_sections",stored);out.put("enabled_columns",enabled);out.put("updating_levels",updateLevels);out.put("receiver_work",work);out.put("has_work",e.hasLightWork());return out;
 }
 static List<Map<String,Object>> receiver(JsonArray scenarios)throws Exception{
  var out=new ArrayList<Map<String,Object>>();
  for(JsonElement entry:scenarios){JsonObject s=entry.getAsJsonObject(),bounds=s.getAsJsonObject("bounds");Fixture f=new Fixture(bounds.get("min_y").getAsInt(),bounds.get("height").getAsInt());
   for(JsonElement c:s.getAsJsonArray("chunks"))f.add(chunk(c.getAsJsonArray()),states.get(s.get("default_state").getAsString()));
   for(JsonElement fill:s.getAsJsonArray("fills"))f.fill(fill.getAsJsonObject());
   for(JsonElement write:s.getAsJsonArray("writes")){JsonObject w=write.getAsJsonObject();f.write(pos(w.getAsJsonArray("position")),states.get(w.get("state").getAsString()));}
   for(ProtoChunk c:f.chunks.values())c.initializeLightSources();
   SkyLightEngine engine=new SkyLightEngine(f);var samples=new ArrayList<BlockPos>();for(JsonElement p:s.getAsJsonArray("samples"))samples.add(pos(p.getAsJsonArray()));
   for(ChunkPos c:f.chunks.keySet())for(int sy=f.getMinSectionY();sy<=f.getMaxSectionY();sy++)engine.updateSectionStatus(SectionPos.of(c,sy),false);
   int initialWork=drain(engine);boolean initial=s.get("initial_enabled").getAsBoolean();
   if(initial){for(ChunkPos c:f.chunks.keySet()){engine.setLightEnabled(c,true);engine.propagateLightSources(c);}initialWork+=drain(engine);}
   var phases=new ArrayList<Map<String,Object>>();phases.add(snapshot("initial",f,engine,samples,initialWork));
   for(JsonElement phase:s.getAsJsonArray("phases")){JsonObject p=phase.getAsJsonObject();var sourceChanges=new ArrayList<Map<String,Object>>();
    for(JsonElement write:p.getAsJsonArray("writes")){JsonObject w=write.getAsJsonObject();BlockPos at=pos(w.getAsJsonArray("position"));f.write(at,states.get(w.get("state").getAsString()));
     ProtoChunk c=f.resident(at);boolean changed=c.getSkyLightSources().update(c,at.getX()&15,at.getY(),at.getZ()&15);sourceChanges.add(Map.of("position",w.get("position"),"changed",changed));engine.checkBlock(at);
    }
    for(JsonElement toggle:p.getAsJsonArray("enabled")){JsonObject t=toggle.getAsJsonObject();engine.setLightEnabled(chunk(t.getAsJsonArray("chunk")),t.get("value").getAsBoolean());}
    for(JsonElement check:p.getAsJsonArray("checks"))engine.checkBlock(pos(check.getAsJsonArray()));
    for(JsonElement propagate:p.getAsJsonArray("propagate"))engine.propagateLightSources(chunk(propagate.getAsJsonArray()));
    int work=drain(engine);Map<String,Object> snap=snapshot(p.get("id").getAsString(),f,engine,samples,work);snap.put("source_updates",sourceChanges);
    int heightChecks=0;for(ProtoChunk c:f.chunks.values()){ChunkSkyLightSources rescan=new ChunkSkyLightSources(f.height);rescan.fillFrom(c);
     for(int z=0;z<16;z++)for(int x=0;x<16;x++){if(rescan.getLowestSourceY(x,z)!=c.getSkyLightSources().getLowestSourceY(x,z))throw new AssertionError("Incremental/full source scan mismatch:"+s.get("id")+":"+p.get("id")+":"+x+":"+z);heightChecks++;}}
    snap.put("incremental_full_source_checks",heightChecks);phases.add(snap);
   }
   out.add(Map.of("id",s.get("id").getAsString(),"phases",phases));
  }return out;
 }
 static Map<String,Object> sparseStorage()throws Exception{
  Fixture f=new Fixture(0,80);f.add(new ChunkPos(0,0),states.get("air"));f.chunks.values().forEach(ProtoChunk::initializeLightSources);
  SkyLightEngine e=new SkyLightEngine(f);e.updateSectionStatus(SectionPos.of(0,0,0),false);e.updateSectionStatus(SectionPos.of(0,4,0),false);drain(e);
  DataLayer above=new DataLayer(7);above.set(8,0,8,11);above.set(8,15,8,3);e.queueSectionData(SectionPos.asLong(0,3,0),above);drain(e);
  var samples=List.of(new BlockPos(8,-32,8),new BlockPos(8,0,8),new BlockPos(8,16,8),new BlockPos(8,32,8),new BlockPos(8,47,8),new BlockPos(8,48,8),new BlockPos(8,49,8),new BlockPos(8,63,8),new BlockPos(8,80,8),new BlockPos(8,96,8),new BlockPos(40,0,40));
  var disabled=snapshot("disabled",f,e,samples,0);e.setLightEnabled(new ChunkPos(0,0),true);drain(e);var enabled=snapshot("enabled",f,e,samples,0);
  Object storage=field(e,LightEngine.class,"storage");int top=(int)method(SkyLightSectionStorage.class,"getTopSectionY",long.class).invoke(storage,SectionPos.getZeroNode(0,0));int bottom=(int)method(SkyLightSectionStorage.class,"getBottomSectionY").invoke(storage);
  return Map.of("samples",samples.stream().map(p->List.of(p.getX(),p.getY(),p.getZ())).toList(),"active_sections",List.of(0,4),"queued_section_y",3,"queued_layer_default",7,"queued_bottom_sample",11,"queued_top_sample",3,"top_section_y",top,"bottom_section_y",bottom,"phases",List.of(disabled,enabled));
 }
 static Map<String,Object> missingChunk()throws Exception{
  Fixture f=new Fixture(-16,32);f.add(new ChunkPos(0,0),states.get("air"));f.chunks.values().forEach(ProtoChunk::initializeLightSources);
  SkyLightEngine e=new SkyLightEngine(f);e.updateSectionStatus(SectionPos.of(0,0,0),false);drain(e);
  Method getState=method(LightEngine.class,"getState",BlockPos.class),lowest=method(SkyLightEngine.class,"getLowestSourceY",int.class,int.class,int.class);
  Method sources=method(SkyLightEngine.class,"getChunkSources",int.class,int.class);
  BlockPos at=new BlockPos(16,0,8);var samples=List.of(at,new BlockPos(16,32,8),new BlockPos(64,0,8));
  var before=snapshot("disabled",f,e,samples,0);e.setLightEnabled(new ChunkPos(1,0),true);e.propagateLightSources(new ChunkPos(1,0));int work=drain(e);var after=snapshot("explicitly_enabled_missing_chunk",f,e,samples,work);
  return Map.of("state_name",BuiltInRegistries.BLOCK.getKey(((BlockState)getState.invoke(e,at)).getBlock()).toString(),"sky_sources_null",sources.invoke(e,1,0)==null,
   "source_fallback_min",lowest.invoke(e,16,8,Integer.MIN_VALUE),"source_fallback_max",lowest.invoke(e,16,8,Integer.MAX_VALUE),"samples",samples.stream().map(p->List.of(p.getX(),p.getY(),p.getZ())).toList(),"phases",List.of(before,after));
 }
 static Map<String,Object> ordinaryDownward()throws Exception{
  Fixture f=new Fixture(-16,32);f.add(new ChunkPos(0,0),states.get("bedrock"));
  for(int y=0;y<=8;y++)f.write(new BlockPos(8,y,8),states.get("air"));f.chunks.values().forEach(ProtoChunk::initializeLightSources);
  SkyLightEngine e=new SkyLightEngine(f);for(int sy=f.getMinSectionY();sy<=f.getMaxSectionY();sy++)e.updateSectionStatus(SectionPos.of(0,sy,0),false);drain(e);
  DataLayer seed=new DataLayer();seed.set(8,8,8,15);e.queueSectionData(SectionPos.asLong(0,0,0),seed);drain(e);
  var samples=List.of(new BlockPos(8,8,8),new BlockPos(8,7,8),new BlockPos(8,6,8),new BlockPos(8,0,8));var before=snapshot("seeded_storage",f,e,samples,0);
  Class<?> queue=Class.forName("net.minecraft.world.level.lighting.LightEngine$QueueEntry");
  long entry=(long)method(queue,"increaseOnlyOneDirection",int.class,boolean.class,Direction.class).invoke(null,15,true,Direction.DOWN);
  method(SkyLightEngine.class,"propagateIncrease",long.class,long.class,int.class).invoke(e,new BlockPos(8,8,8).asLong(),entry,15);
  int work=drain(e);var after=snapshot("actual_downward_propagation",f,e,samples,work);
  return Map.of("samples",samples.stream().map(p->List.of(p.getX(),p.getY(),p.getZ())).toList(),"phases",List.of(before,after),
   "boundary","Explicit queued storage seed15 in a blocked source column, then actual protected SkyLightEngine.propagateIncrease with an official DOWN-only queue entry. This isolates ordinary transfer; it is not a claim that the seed is a valid fresh natural direct source.");
 }
 public static void main(String[] args)throws Exception{
  SharedConstants.tryDetectVersion();Bootstrap.bootStrap();JsonObject input=JsonParser.parseString(Files.readString(Path.of(args[0]))).getAsJsonObject();
  for(var e:input.getAsJsonObject("states").entrySet())states.put(e.getKey(),resolve(e.getValue().getAsJsonObject()));
  var properties=new ArrayList<Map<String,Object>>();for(var e:states.entrySet()){BlockState s=e.getValue();properties.add(Map.of("id",e.getKey(),"state",Block.getId(s),"dampening",s.getLightDampening(),"can_occlude",s.canOcclude(),"shape_light_occlusion",s.useShapeForLightOcclusion()));}
  var edges=new ArrayList<Map<String,Object>>();SkyLightEngine edgeEngine=new SkyLightEngine(new Fixture(-16,32));Method occludes=method(LightEngine.class,"shapeOccludes",BlockState.class,BlockState.class,Direction.class);
  Method opacity=method(LightEngine.class,"getOpacity",BlockState.class);
  Method sourceEdge=method(ChunkSkyLightSources.class,"isEdgeOccluded",BlockState.class,BlockState.class);
  for(var a:states.entrySet())for(var b:states.entrySet())for(Direction d:Direction.values())edges.add(Map.of("from",a.getKey(),"to",b.getKey(),"direction",d.get3DDataValue(),"closed",occludes.invoke(edgeEngine,a.getValue(),b.getValue(),d),"ordinary_attenuation",opacity.invoke(edgeEngine,b.getValue())));
  var sourceEdges=new ArrayList<Map<String,Object>>();for(var a:states.entrySet())for(var b:states.entrySet())sourceEdges.add(Map.of("upper",a.getKey(),"lower",b.getKey(),"closed",sourceEdge.invoke(null,a.getValue(),b.getValue())));
  var out=new TreeMap<String,Object>();out.put("version",SharedConstants.getCurrentVersion().id());out.put("state_count",Block.BLOCK_STATE_REGISTRY.size());out.put("properties",properties);out.put("edges",edges);out.put("source_edges",sourceEdges);out.put("scenarios",receiver(input.getAsJsonArray("scenarios")));out.put("sparse_storage",sparseStorage());out.put("missing_chunk",missingChunk());out.put("ordinary_downward",ordinaryDownward());
  Files.writeString(Path.of(args[1]),JSON.toJson(out));
 }
}'''


def inputs():
    states = {name: {'name': name, 'properties': {}}
              for name in ('air', 'stone', 'bedrock', 'glass', 'water', 'ice')}
    for label, properties in (
        ('slab_bottom', {'type': 'bottom', 'waterlogged': 'false'}),
        ('slab_top', {'type': 'top', 'waterlogged': 'false'}),
        ('slab_wet', {'type': 'bottom', 'waterlogged': 'true'}),
    ):
        states[label] = {'name': 'oak_slab', 'properties': properties}

    def fill(a, b, state='air'):
        return {'from': a, 'to': b, 'state': state}

    def phase(label, writes=(), enabled=(), propagate=(), checks=()):
        return {'id': label, 'writes': [{'position': p, 'state': s} for p, s in writes],
                'enabled': [{'chunk': c, 'value': v} for c, v in enabled],
                'propagate': list(propagate), 'checks': list(checks)}

    scenarios = []

    def add(label, default, fills, writes, samples, phases, chunks=((0, 0),), enabled=True):
        scenarios.append({'id': label, 'bounds': {'min_y': -16, 'height': 32},
                          'chunks': [list(c) for c in chunks], 'default_state': default,
                          'fills': fills, 'writes': [{'position': p, 'state': s} for p, s in writes],
                          'samples': samples, 'initial_enabled': enabled, 'phases': phases})

    vertical = [[8, y, 8] for y in (-16, -8, -1, 0, 6, 7, 8, 9, 14, 15, 16, 32)]
    add('open_sky', 'air', [], [], vertical, [phase('unchanged_check', checks=[[8, 0, 8]])])
    roof = [([x, 8, z], 'stone') for z in range(16) for x in range(16)]
    roof_samples = vertical + [[7, 7, 8], [6, 7, 8], [9, 7, 8], [15, 7, 8]]
    add('roof_add_remove', 'air', [], [], roof_samples,
        [phase('roof', roof), phase('hole', [([8, 8, 8], 'air')]),
         phase('reclose', [([8, 8, 8], 'stone')]),
         phase('remove_roof', [(p, 'air') for p, _ in roof])])
    duct = [fill([8, -16, 8], [8, 15, 8])]
    add('water_attenuation', 'bedrock', duct, [], vertical,
        [phase('two_water', [([8, 8, 8], 'water'), ([8, 7, 8], 'water')]),
         phase('one_water', [([8, 7, 8], 'air')]),
         phase('glass', [([8, 8, 8], 'glass')]),
         phase('ice', [([8, 8, 8], 'ice')]),
         phase('remove', [([8, 8, 8], 'air')])])
    horizontal = [fill([2, -16, 8], [2, 15, 8]), fill([2, 0, 8], [12, 0, 8])]
    line = [[x, 0, 8] for x in range(2, 13)]
    add('horizontal_shape_union', 'bedrock', horizontal, [], line,
        [phase('complementary', [([5, 0, 8], 'slab_bottom'), ([6, 0, 8], 'slab_top')]),
         phase('matching_halves', [([6, 0, 8], 'slab_bottom')]),
         phase('reclose', [([6, 0, 8], 'slab_top')]),
         phase('clear', [([5, 0, 8], 'air'), ([6, 0, 8], 'air')])])
    add('vertical_shape_source_edge', 'bedrock', duct, [], vertical,
        [phase('bottom_slab', [([8, 8, 8], 'slab_bottom')]),
         phase('top_slab', [([8, 8, 8], 'slab_top')]),
         phase('wet_bottom', [([8, 8, 8], 'slab_wet')]),
         phase('clear', [([8, 8, 8], 'air')])])
    add('lighting_enablement', 'air', [], [], vertical,
        [phase('enable_only', enabled=[([0, 0], True)]),
         phase('propagate', propagate=[[0, 0]]),
         phase('disable', enabled=[([0, 0], False)]),
         phase('disabled_after_roof_edit', roof),
         phase('reenable_only_after_edit', enabled=[([0, 0], True)]),
         phase('propagate_after_reenable', propagate=[[0, 0]])], enabled=False)
    low_roof = [([x, -8, z], 'stone') for z in range(16) for x in range(16)]
    add('lighting_enablement_low_roof', 'air', [], low_roof, vertical,
        [phase('enable_only', enabled=[([0, 0], True)]),
         phase('propagate', propagate=[[0, 0]])], enabled=False)
    cross = [fill([-18, -16, -8], [-18, 15, -8]), fill([-18, -8, -8], [-6, -8, -8])]
    signed = [[x, -8, -8] for x in range(-18, -5)]
    add('signed_chunk_boundary', 'bedrock', cross, [], signed,
        [phase('closed', [([-16, -8, -8], 'stone')]),
         phase('open', [([-16, -8, -8], 'air')])], chunks=((-2, -1), (-1, -1)))
    return {'states': states, 'scenarios': scenarios}


SEMANTICS = {
    'authority': 'Pinned official class declarations/bytecode plus actual unmodified Java execution.',
    'source_height': 'ChunkSkyLightSources stores the upper-cell Y of the highest blocked downward edge; target dampening > 0 or upper DOWN / lower UP face union closes an edge. No blocked edge maps to Integer.MIN_VALUE, extending sources below build height.',
    'direct_sources': 'SkyLightEngine directly stores 15 at each allocated cell Y >= the column source threshold when lighting is enabled. This supplies lossless downward sky columns.',
    'ordinary_transfer': 'SkyLightEngine.propagateIncrease requires a target stored section and open source-direction / target-opposite face union; target value is source level minus max(1,target dampening). There is no DOWN/15 zero-attenuation branch in ordinary propagation.',
    'enablement': 'updateSectionStatus(false) means nonempty and allocates neighbor layers. setLightEnabled toggles source-column admission and may fill empty upper layers. propagateLightSources enables and injects sources. Disabling alone retains existing stored light.',
    'missing_chunk': 'LightEngine.getState returns actual BEDROCK for absent chunks. Source-height fallback is contextual: checkNode uses Integer.MAX_VALUE, addSourcesAbove neighbor comparisons use Integer.MIN_VALUE, explicit source propagation substitutes empty source heights. Absent storage public lookup can nevertheless return 15; lookup is not a chunk-residency oracle.',
    'top_lookup': 'SkyLightSectionStorage public visible lookup returns 15 at/above the column top or when no top exists, irrespective of enablement. Updating lookup returns 0 there when disabled. Below top, an absent data layer searches upward and samples the bottom plane of the first present layer; reaching the top yields 15.',
}


def sha(data):
    return hashlib.sha256(data).hexdigest()


def source_records(paths):
    with zipfile.ZipFile(CLIENT) as jar:
        classes = {name: {'bytes': len(jar.read(name.replace('.', '/') + '.class')),
                          'sha256': sha(jar.read(name.replace('.', '/') + '.class'))}
                   for name in CLASSES}
    command = [str(JAVA.with_name('javap')), '-p', '-c', '-classpath',
               os.pathsep.join(map(str, paths)), *CLASSES]
    run = subprocess.run(command, capture_output=True, text=True, check=True, timeout=30)
    path = WORK / 'official-javap.txt'
    path.write_text(run.stdout)
    return {'official_classes': classes, 'javap_sha256': sha(run.stdout.encode()),
            'javap_cache_path': str(path.relative_to(ROOT)),
            'harness_sha256': sha(SOURCE.encode()), 'method_authority': SEMANTICS['authority']}


def execute(request, paths, tag):
    harness = WORK / 'SkyLightReference.java'
    harness.write_text(SOURCE)
    input_path, output_path = WORK / (tag + '-inputs.json'), WORK / (tag + '-output.json')
    input_path.write_bytes(canonical(request))
    command = [str(JAVA), '-Xmx512m', '--source', '25', '--class-path',
               os.pathsep.join(map(str, paths)), str(harness), str(input_path), str(output_path)]
    started = time.monotonic()
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=90)
    (WORK / (tag + '-stdout')).write_text(result.stdout)
    (WORK / (tag + '-stderr')).write_text(result.stderr)
    if result.returncode:
        raise RuntimeError(f'Actual Java sky probe failed ({result.returncode}):\n{result.stderr[-6000:]}\n{result.stdout[-2000:]}')
    observations = json.loads(output_path.read_text())
    return observations, {'command': command, 'exit_code': result.returncode,
                          'seconds': round(time.monotonic() - started, 4),
                          'raw_observations_sha256': sha(output_path.read_bytes())}


def validate(observed, request):
    assert observed['version'] == '26.3' and observed['state_count'] == 35723
    assert len(observed['edges']) == len(request['states']) ** 2 * 6
    assert len(observed['source_edges']) == len(request['states']) ** 2
    assert [s['id'] for s in observed['scenarios']] == [s['id'] for s in request['scenarios']]
    for actual, expected in zip(observed['scenarios'], request['scenarios']):
        assert [p['id'] for p in actual['phases']] == ['initial'] + [p['id'] for p in expected['phases']]
        for phase in actual['phases']:
            assert not phase['has_work']
            for field in ('levels', 'lowest_source_y', 'state_ids', 'stored_sections', 'enabled_columns', 'updating_levels'):
                assert len(phase[field]) == len(expected['samples'])
            assert all(0 <= level <= 15 for level in phase['levels'])
    cases = {s['id']: {p['id']: p for p in s['phases']} for s in observed['scenarios']}
    assert set(cases['open_sky']['initial']['levels']) == {15}
    assert set(cases['open_sky']['initial']['lowest_source_y']) == {-2147483648}
    assert cases['roof_add_remove']['roof']['lowest_source_y'][0] == 9
    assert cases['roof_add_remove']['roof']['levels'][4:8] == [0, 0, 0, 15]
    assert cases['roof_add_remove']['hole']['levels'][4:8] == [15, 15, 15, 15]
    assert cases['water_attenuation']['two_water']['levels'][4:8] == [12, 13, 14, 15]
    assert cases['water_attenuation']['one_water']['levels'][4:8] == [12, 13, 14, 15]
    assert cases['water_attenuation']['glass']['levels'][:10] == [15] * 10
    assert cases['vertical_shape_source_edge']['bottom_slab']['lowest_source_y'][0] == 8
    assert cases['vertical_shape_source_edge']['top_slab']['lowest_source_y'][0] == 9
    assert cases['horizontal_shape_union']['complementary']['levels'][4:] == [0] * 7
    assert cases['horizontal_shape_union']['matching_halves']['levels'] == list(range(15, 4, -1))
    assert cases['lighting_enablement']['disable']['levels'] == cases['lighting_enablement']['propagate']['levels']
    assert cases['lighting_enablement_low_roof']['initial']['levels'] == [0] * 11 + [15]
    assert cases['lighting_enablement_low_roof']['enable_only']['levels'] == [0] * 3 + [15] * 9
    assert cases['lighting_enablement_low_roof']['propagate']['levels'] == [0, 0] + [15] * 10
    missing = observed['missing_chunk']
    assert missing['state_name'] == 'minecraft:bedrock' and missing['sky_sources_null']
    assert missing['source_fallback_min'] == -2147483648 and missing['source_fallback_max'] == 2147483647
    sparse = observed['sparse_storage']
    assert sparse['top_section_y'] == 6 and sparse['bottom_section_y'] == -1
    assert sparse['phases'][0]['levels'][3:8] == [11, 11, 11, 7, 3]
    assert sparse['phases'][0]['levels'][-2:] == [15, 15]
    assert sparse['phases'][0]['updating_levels'][-2:] == [0, 0]
    assert observed['ordinary_downward']['phases'][0]['levels'] == [15, 0, 0, 0]
    assert observed['ordinary_downward']['phases'][1]['levels'] == [15, 14, 13, 7]
    assert observed['ordinary_downward']['phases'][1]['lowest_source_y'] == [16] * 4


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('action', nargs='?', choices=['extract', 'check'], default='extract')
    args = parser.parse_args()
    WORK.mkdir(parents=True, exist_ok=True)
    paths, provenance = verified_client_classpath()
    request = inputs()
    observed, run = execute(request, paths, args.action)
    validate(observed, request)
    source = source_records(paths)
    boundary = ('Actual unmodified pinned Java SkyLightEngine/SkyLightSectionStorage/ChunkSkyLightSources, '
                'actual ProtoChunk sections and block palettes behind a controlled LightChunkGetter. '
                'Unused biome/tick/factory/blending fields are null; probes do not query them. '
                'Declared default blocks and fills are fixture geometry. Source-height scan/update and '
                'all receiver levels come from Java, not Python. Work count/order is not a parity target. '
                'No client/world launch, rendering/lightmap, save/packet persistence, world scheduling, '
                'dimension policy, or exhaustive state-pair parity claim.')
    data = {'schema': 1, 'pin': '26.3', 'oracle_version': 'java26.3-sky-light-v1',
            'inputs': request, 'inputs_sha256': sha(canonical(request)),
            'observations': observed, 'observations_sha256': sha(canonical(observed)),
            'provenance': {'classpath': provenance, **source},
            'semantics': SEMANTICS, 'boundary': boundary}
    if args.action == 'check':
        retained = json.loads(OUTPUT.read_text())
        assert retained == data, 'Fresh actual Java observations/provenance differ from retained sky reference'
    else:
        OUTPUT.write_bytes(canonical(data) + b'\n')
    evidence = {'status': 'passed', 'pin': '26.3', 'action': args.action,
                'command': 'python3 tools/reference_sky_light.py ' + args.action,
                'reference': str(OUTPUT.relative_to(ROOT)), 'reference_sha256': sha(OUTPUT.read_bytes()),
                'inputs_sha256': data['inputs_sha256'], 'observations_sha256': data['observations_sha256'],
                'official_classes_sha256': {k: v['sha256'] for k, v in source['official_classes'].items()},
                'harness_sha256': source['harness_sha256'], 'javap_sha256': source['javap_sha256'],
                'run': run, 'scenarios': len(request['scenarios']),
                'receiver_phases': sum(len(s['phases']) for s in observed['scenarios']),
                'receiver_samples': sum(len(s['samples']) * (len(s['phases']) + 1) for s in request['scenarios']),
                'properties': len(request['states']), 'directed_shape_edges': len(observed['edges']),
                'downward_source_edges': len(observed['source_edges']),
                'storage_missing_chunk_and_direct_transfer_probes': 3,
                'incremental_full_source_checks': sum(p.get('incremental_full_source_checks', 0)
                                                     for s in observed['scenarios'] for p in s['phases']),
                'boundary': boundary}
    EVIDENCE.write_text(json.dumps(evidence, indent=2) + '\n')
    print(json.dumps({k: evidence[k] for k in ('status', 'action', 'scenarios', 'receiver_phases', 'receiver_samples', 'observations_sha256')}))


if __name__ == '__main__':
    main()
