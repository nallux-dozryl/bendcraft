#!/usr/bin/env python3
"""Pinned Java26.3 lighting receiver observations; Python never propagates light."""
from __future__ import annotations
import hashlib, json, os, subprocess, zipfile
from pathlib import Path
from reference_model_probe import verified_client_classpath, JAVA, CLIENT
from reference_inventory import ROOT, canonical, fingerprint

WORK = ROOT/'build/block-light-reference'
OUTPUT = ROOT/'reference/block_light.json'
CLASSES = ['net.minecraft.world.level.lighting.LightEngine',
           'net.minecraft.world.level.lighting.BlockLightEngine',
           'net.minecraft.world.level.lighting.LightEngine$QueueEntry',
           'net.minecraft.world.level.lighting.BlockLightSectionStorage',
           'net.minecraft.world.level.lighting.LayerLightSectionStorage',
           'net.minecraft.world.phys.shapes.Shapes']

SOURCE = r'''import java.nio.file.*;import java.util.*;import java.util.function.*;import java.lang.reflect.*;
import com.google.gson.*;import net.minecraft.SharedConstants;import net.minecraft.server.Bootstrap;
import net.minecraft.core.*;import net.minecraft.core.registries.BuiltInRegistries;
import net.minecraft.world.level.*;import net.minecraft.world.level.block.*;
import net.minecraft.world.level.block.entity.BlockEntity;import net.minecraft.world.level.block.state.*;
import net.minecraft.world.level.block.state.properties.Property;import net.minecraft.world.level.chunk.*;
import net.minecraft.world.level.lighting.*;import net.minecraft.world.level.material.FluidState;
import net.minecraft.world.phys.shapes.*;
class BlockLightReference {
 static Gson JSON=new Gson();static Map<String,BlockState> states=new LinkedHashMap<>();
 static BlockPos pos(JsonArray a){return new BlockPos(a.get(0).getAsInt(),a.get(1).getAsInt(),a.get(2).getAsInt());}
 static List<Integer> xyz(BlockPos p){return List.of(p.getX(),p.getY(),p.getZ());}
 static <T extends Comparable<T>> String value(Property<T> p,BlockState s){return p.getName(s.getValue(p));}
 static BlockState resolve(JsonObject input){
  String name="minecraft:"+input.get("name").getAsString();JsonObject properties=input.getAsJsonObject("properties");
  for(BlockState s:Block.BLOCK_STATE_REGISTRY){
   if(!BuiltInRegistries.BLOCK.getKey(s.getBlock()).toString().equals(name))continue;
   boolean good=true;for(var e:properties.entrySet()){
    Property<?> p=s.getBlock().getStateDefinition().getProperty(e.getKey());
    if(p==null||!value(p,s).equals(e.getValue().getAsString())){good=false;break;}
   }
   if(good)return s;
  }throw new IllegalArgumentException("No actual registered state:"+input);
 }
 static class Fixture implements LightChunk,LightChunkGetter {
  Map<BlockPos,BlockState> blocks=new HashMap<>();Set<ChunkPos> chunks=new HashSet<>();
  public int getHeight(){return 64;}public int getMinY(){return -16;}
  public BlockEntity getBlockEntity(BlockPos p){return null;}
  public BlockState getBlockState(BlockPos p){return blocks.getOrDefault(p,Blocks.BEDROCK.defaultBlockState());}
  public FluidState getFluidState(BlockPos p){return getBlockState(p).getFluidState();}
  public void findBlockLightSources(BiConsumer<BlockPos,BlockState> c){for(var e:blocks.entrySet())if(e.getValue().getLightEmission()>0)c.accept(e.getKey(),e.getValue());}
  public ChunkSkyLightSources getSkyLightSources(){return null;}
  public LightChunk getChunkForLighting(int x,int z){return chunks.contains(new ChunkPos(x,z))?this:null;}
  public BlockGetter getLevel(){return this;}
 }
 static int drain(BlockLightEngine engine){int work=0;for(int i=0;i<100;i++){if(!engine.hasLightWork())return work;work+=engine.runLightUpdates();}throw new AssertionError("Receiver did not settle");}
 static Map<String,Object> snapshot(String label,Fixture f,BlockLightEngine e,List<BlockPos> sample,int work){
  var levels=new ArrayList<Integer>();for(BlockPos p:sample)levels.add(e.getLightValue(p));
  return Map.of("id",label,"levels",levels,"receiver_work",work,"has_work",e.hasLightWork());
 }
 public static void main(String[] args)throws Exception{
  SharedConstants.tryDetectVersion();Bootstrap.bootStrap();
  JsonObject input=JsonParser.parseString(Files.readString(Path.of(args[0]))).getAsJsonObject();
  for(var entry:input.getAsJsonObject("states").entrySet())states.put(entry.getKey(),resolve(entry.getValue().getAsJsonObject()));
  var properties=new ArrayList<Map<String,Object>>();
  for(var e:states.entrySet()){BlockState s=e.getValue();properties.add(Map.of("id",e.getKey(),"state",Block.getId(s),"emission",s.getLightEmission(),"dampening",s.getLightDampening(),"can_occlude",s.canOcclude(),"shape_light_occlusion",s.useShapeForLightOcclusion()));}
  Method occludes=LightEngine.class.getDeclaredMethod("shapeOccludes",BlockState.class,BlockState.class,Direction.class);occludes.setAccessible(true);
  var edgeEngine=new BlockLightEngine(new Fixture());var edges=new ArrayList<Map<String,Object>>();
  for(var a:states.entrySet())for(var b:states.entrySet())for(Direction direction:Direction.values()){
   boolean closed=(boolean)occludes.invoke(edgeEngine,a.getValue(),b.getValue(),direction);
   edges.add(Map.of("from",a.getKey(),"to",b.getKey(),"direction",direction.get3DDataValue(),"closed",closed,
      "public_dampening_into",LightEngine.getLightDampeningInto(a.getValue(),b.getValue(),direction,b.getValue().getLightDampening())));
  }
  var scenarios=new ArrayList<Map<String,Object>>();
  for(JsonElement entry:input.getAsJsonArray("scenarios")){
   JsonObject scenario=entry.getAsJsonObject();Fixture fixture=new Fixture();var sample=new ArrayList<BlockPos>();var sections=new HashSet<SectionPos>();
   for(JsonElement cell:scenario.getAsJsonArray("domain")){BlockPos p=pos(cell.getAsJsonArray());fixture.blocks.put(p,states.get("air"));fixture.chunks.add(new ChunkPos(p.getX()>>4,p.getZ()>>4));sections.add(SectionPos.of(p));sample.add(p);}
   BlockLightEngine engine=new BlockLightEngine(fixture);for(SectionPos section:sections)engine.updateSectionStatus(section,false);
   for(ChunkPos chunk:fixture.chunks)engine.setLightEnabled(chunk,true);drain(engine);
   var phases=new ArrayList<Map<String,Object>>();
   for(JsonElement phase:scenario.getAsJsonArray("phases")){
    JsonObject update=phase.getAsJsonObject();
    for(JsonElement write:update.getAsJsonArray("writes")){JsonObject w=write.getAsJsonObject();BlockPos p=pos(w.getAsJsonArray("position"));
     String state=w.get("state").getAsString();if(state.equals("unloaded"))fixture.blocks.remove(p);else fixture.blocks.put(p,states.get(state));engine.checkBlock(p);
    }
    int work=drain(engine);phases.add(snapshot(update.get("id").getAsString(),fixture,engine,sample,work));
   }
   scenarios.add(Map.of("id",scenario.get("id").getAsString(),"phases",phases));
  }
  var distribution=new TreeMap<String,Integer>();for(BlockState state:Block.BLOCK_STATE_REGISTRY){String key=state.getLightEmission()+","+state.getLightDampening()+","+state.canOcclude()+","+state.useShapeForLightOcclusion();distribution.merge(key,1,Integer::sum);}
  var out=new TreeMap<String,Object>();out.put("version",SharedConstants.getCurrentVersion().id());out.put("state_count",Block.BLOCK_STATE_REGISTRY.size());out.put("property_distribution",distribution);out.put("properties",properties);out.put("edges",edges);out.put("scenarios",scenarios);
  Files.writeString(Path.of(args[1]),JSON.toJson(out));
 }
}'''

def inputs():
    states = {name:{'name':name,'properties':{}} for name in
              ('air','stone','glass','water','ice','torch','glowstone','sea_lantern','redstone_torch')}
    states['redstone_torch']['properties']={'lit':'true'}
    for label, block, properties in (
        ('lamp_on','redstone_lamp',{'lit':'true'}),('lamp_off','redstone_lamp',{'lit':'false'}),
        ('redstone_torch_off','redstone_torch',{'lit':'false'}),
        ('slab_bottom','oak_slab',{'type':'bottom','waterlogged':'false'}),
        ('slab_top','oak_slab',{'type':'top','waterlogged':'false'}),
        ('slab_double','oak_slab',{'type':'double','waterlogged':'false'}),
        ('slab_wet','oak_slab',{'type':'bottom','waterlogged':'true'}),
        ('stairs_bottom','oak_stairs',{'half':'bottom','facing':'east','shape':'straight','waterlogged':'false'}),
        ('stairs_top','oak_stairs',{'half':'top','facing':'east','shape':'straight','waterlogged':'false'}),
        ('candle_one','candle',{'candles':'1','lit':'true','waterlogged':'false'}),
        ('candle_four','candle',{'candles':'4','lit':'true','waterlogged':'false'})):
        states[label]={'name':block,'properties':properties}
    scenarios=[]
    def add(name, domain, phases):
        scenarios.append({'id':name,'domain':domain,'phases':[{'id':label,'writes':[{'position':p,'state':s} for p,s in writes]} for label,writes in phases]})
    line=[[x,8,8] for x in range(0,25)]
    add('source_add_remove',line,[('add',[([2,8,8],'torch')]),('remove',[([2,8,8],'air')]),('readd',[([2,8,8],'sea_lantern')])])
    add('competing_sources',line,[('both',[([2,8,8],'glowstone'),([20,8,8],'torch')]),('remove_stronger',[([2,8,8],'air')]),('remove_last',[([20,8,8],'air')])])
    add('opaque_edit',line,[('closed',[([2,8,8],'glowstone'),([7,8,8],'stone')]),('open',[([7,8,8],'air')]),('reclose',[([7,8,8],'stone')])])
    add('attenuation',line,[('water',[([2,8,8],'glowstone'),([4,8,8],'water'),([5,8,8],'water')]),('ice',[([4,8,8],'ice'),([5,8,8],'ice')]),('glass',[([4,8,8],'glass'),([5,8,8],'glass')])])
    add('partial_complementary',line,[('halves_closed',[([2,8,8],'glowstone'),([5,8,8],'slab_bottom'),([6,8,8],'slab_top')]),('halves_open',[([6,8,8],'slab_bottom')]),('halves_reclosed',[([6,8,8],'slab_top')])])
    add('emission_change',line,[('lit',[([8,8,8],'lamp_on')]),('unlit',[([8,8,8],'lamp_off')]),('low',[([8,8,8],'candle_one')]),('high',[([8,8,8],'candle_four')])])
    add('resident_boundary',line,[('add',[([2,8,8],'glowstone')]),('unload',[([7,8,8],'unloaded')]),('reload',[([7,8,8],'air')])])
    negative=[[x,-8,-8] for x in range(-20,5)]
    add('signed_coordinates',negative,[('add',[([-16,-8,-8],'torch')]),('barrier',[([-11,-8,-8],'stone')]),('remove',[([-16,-8,-8],'air')])])
    chunk_edge=[[x,8,8] for x in range(27,32)]
    add('absent_neighbor_chunk',chunk_edge,[('edge_source',[([31,8,8],'torch')]),('remove',[([31,8,8],'air')]),('readd',[([31,8,8],'redstone_torch')])])
    cube=[[x,y,z] for y in range(5,12) for z in range(5,12) for x in range(5,12)]
    add('six_directions',cube,[('center',[([8,8,8],'torch')]),('opaque_shell',[([8+dx,8+dy,8+dz],'stone') for dx,dy,dz in ((0,-1,0),(0,1,0),(0,0,-1),(0,0,1),(-1,0,0),(1,0,0))]),('reopen',[([8+dx,8+dy,8+dz],'air') for dx,dy,dz in ((0,-1,0),(0,1,0),(0,0,-1),(0,0,1),(-1,0,0),(1,0,0))])])
    return {'states':states,'scenarios':scenarios}

def main():
    WORK.mkdir(parents=True,exist_ok=True)
    paths, provenance=verified_client_classpath()
    request=inputs();(WORK/'inputs.json').write_bytes(canonical(request))
    (WORK/'BlockLightReference.java').write_text(SOURCE)
    command=[str(JAVA),'-Xmx512m','--source','25','--class-path',os.pathsep.join(map(str,paths)),str(WORK/'BlockLightReference.java'),str(WORK/'inputs.json'),str(WORK/'output.json')]
    result=subprocess.run(command,capture_output=True,text=True,timeout=90)
    (WORK/'stdout').write_text(result.stdout);(WORK/'stderr').write_text(result.stderr)
    assert result.returncode==0,(result.returncode,result.stdout,result.stderr)
    observations=json.loads((WORK/'output.json').read_text())
    assert observations['version']=='26.3' and observations['state_count']==35723
    assert len(observations['edges'])==len(request['states'])**2*6
    assert [x['id'] for x in observations['scenarios']]==[x['id'] for x in request['scenarios']]
    with zipfile.ZipFile(CLIENT) as jar:
        hashes={name:hashlib.sha256(jar.read(name.replace('.','/')+'.class')).hexdigest() for name in CLASSES}
    data={'schema':1,'pin':'26.3','inputs':request,'observations':observations,
          'observations_sha256':hashlib.sha256(canonical(observations)).hexdigest(),
          'provenance':{'classpath':provenance,'official_classes_sha256':hashes,'harness_sha256':hashlib.sha256(SOURCE.encode()).hexdigest(),'command':command},
          'boundary':'Actual unmodified BlockLightEngine plus declared LightChunk/LightChunkGetter receiver fixture. Unlisted resident positions and absent chunks return bedrock, forming closed boundaries. All sampled phases settle the real receiver; work ordering/count is not a Bend parity target. Sky light, real chunk persistence/packet updates, face shading and lighting-enable lifecycle are separate.'}
    OUTPUT.write_bytes(canonical(data)+b'\n')
    (ROOT/'evidence/block-light-reference.json').write_text(json.dumps({'status':'passed','pin':'26.3','reference':str(OUTPUT.relative_to(ROOT)),'sha256':hashlib.sha256(OUTPUT.read_bytes()).hexdigest(),'scenarios':len(request['scenarios']),'phases':sum(len(s['phases']) for s in request['scenarios']),'properties':len(request['states']),'directed_edges':len(observations['edges']),'command':'python3 tools/reference_block_light_probe.py','boundary':data['boundary']},indent=2)+'\n')
    print(json.dumps({'status':'passed','scenarios':len(request['scenarios']),'properties':observations['properties']}))

if __name__=='__main__':main()
