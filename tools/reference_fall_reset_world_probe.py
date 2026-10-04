#!/usr/bin/env python3
"""Direct original reset clip/DDA with normally constructed tagged client fixture."""
from __future__ import annotations
import argparse,base64,copy,hashlib,json,math,os,re,signal,struct,subprocess,time,zipfile
from pathlib import Path
from reference_inventory import ROOT,JAVA,canonical,fingerprint
from reference_model_probe import CLIENT,verified_client_classpath
import reference_local_collision_probe as LC
import reference_local_travel_history_probe as T
LI=LC.LI
OUTPUT=ROOT/'reference/fall_reset_world.json'
RAW=ROOT/'build/fall-reset-world-reference'
CLASS='net.minecraft.fixture.FallResetWorldReceiverFixture'
FROZEN_LC_SOURCE='6f2fc332d15358118488b715de467a1ebd53739574488f8de8efb17a1dcbfbce'
FROZEN_TRAVEL_REFERENCE='07646e7fef0e55f3fd89421d1862b0e6dc5fdde3a0a84800b70b857a66609dbf'
FROZEN_HISTORY_REFERENCE='2b510ed3c932d830ed0481343ac4508cfea9e9e98dfcb7856dd2d1ce191f2f95'
def sha(v):return hashlib.sha256(canonical(v)).hexdigest()
def save(p,v):p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(canonical(v)+b'\n')

OBSERVERS=r'''
 static List<Integer> position(BlockPos p){return List.of(p.getX(),p.getY(),p.getZ());}
 static List<List<String>> boxes(VoxelShape s){List<List<String>> r=new ArrayList<>();for(AABB b:s.toAabbs())r.add(box(b));return r;}
 static Map<String,Object> fluid(net.minecraft.world.level.material.FluidState f){return Map.of("fluid_id",BuiltInRegistries.FLUID.getKey(f.getType()).toString(),"empty",f.isEmpty(),"source",f.isSource(),"amount",f.getAmount(),"water_tag",f.is(net.minecraft.tags.FluidTags.WATER),"water_can_pick",net.minecraft.world.level.ClipContext.Fluid.WATER.canPick(f));}
 static Map<String,Object> block(BlockState b){return Map.of("block_id",BuiltInRegistries.BLOCK.getKey(b.getBlock()).toString(),"state_id",Block.getId(b),"state_name",b.toString(),"reset_tag",b.is(net.minecraft.tags.BlockTags.FALL_DAMAGE_RESETTING),"fluid",fluid(b.getFluidState()));}
 static Map<String,Object> hitResult(BlockHitResult r){return Map.of("type",r.getType().name(),"position",position(r.getBlockPos()),"location",vector(r.getLocation()),"direction",r.getDirection().name(),"inside",r.isInside());}
 static class ReadBudgetExceeded extends RuntimeException {ReadBudgetExceeded(){super("external finite-world read watchdog");}}
 static class BudgetLevel extends LocalInputReceiverFixture.FixtureLevel {
  boolean active=false;int readCount=0,readLimit=256;
  BudgetLevel(ClientPacketListener c,Holder<net.minecraft.world.level.dimension.DimensionType> d){super(c,d);}
  public BlockState getBlockState(BlockPos p){if(active&&++readCount>readLimit)throw new ReadBudgetExceeded();return super.getBlockState(p);}
  public BlockHitResult clip(net.minecraft.world.level.ClipContext c){boolean old=active;readCount=0;active=true;try{return super.clip(c);}finally{active=old;}}
 }
 static class TraceLevel extends BudgetLevel {
  final List<Map<String,Object>> events=new ArrayList<>();boolean capture=false;int fluidDepth=0;
  TraceLevel(ClientPacketListener c,Holder<net.minecraft.world.level.dimension.DimensionType> d){super(c,d);}
  void add(Map<String,Object> original){if(capture&&events!=null){Map<String,Object> e=new TreeMap<>(original);e.put("sequence",events.size());events.add(e);}}
  public BlockState getBlockState(BlockPos p){BlockState result=super.getBlockState(p);if(capture&&events!=null){Map<String,Object> e=new TreeMap<>(block(result));e.put("method","getBlockState");e.put("position",position(p));e.put("read_ordinal",readCount-1);e.put("fluid_depth",fluidDepth);e.put("phase",fluidDepth==0?"BlockSample":"FluidSource");add(e);}return result;}
  public net.minecraft.world.level.material.FluidState getFluidState(BlockPos p){add(Map.of("method","getFluidState_entry","position",position(p)));fluidDepth++;try{var r=super.getFluidState(p);add(Map.of("method","getFluidState_exit","position",position(p),"fluid",fluid(r)));return r;}finally{fluidDepth--;}}
  public BlockHitResult clip(net.minecraft.world.level.ClipContext c){add(Map.of("method","clip_entry","from",vector(c.getFrom()),"to",vector(c.getTo())));BlockHitResult r=super.clip(c);add(Map.of("method","clip_exit","result",hitResult(r)));return r;}
 }
 static class ObservedClip extends net.minecraft.world.level.ClipContext {
  final TraceLevel trace;
  ObservedClip(Vec3 from,Vec3 to,LocalPlayer p,TraceLevel trace){super(from,to,Block.FALLDAMAGE_RESETTING,Fluid.WATER,p);this.trace=trace;}
  public VoxelShape getBlockShape(BlockState b,net.minecraft.world.level.BlockGetter l,BlockPos p){VoxelShape r=super.getBlockShape(b,l,p);trace.add(Map.of("method","getBlockShape_exit","position",position(p),"block",block(b),"boxes",boxes(r)));return r;}
  public VoxelShape getFluidShape(net.minecraft.world.level.material.FluidState f,net.minecraft.world.level.BlockGetter l,BlockPos p){VoxelShape r=super.getFluidShape(f,l,p);trace.add(Map.of("method","getFluidShape_exit","position",position(p),"fluid",fluid(f),"boxes",boxes(r)));return r;}
 }
 static class ObservedPlayer extends LocalPlayer {
  ObservedPlayer(Minecraft mc,ClientLevel level,ClientPacketListener connection){super(mc,level,connection,new StatsCounter(),new ClientRecipeBook(),Input.EMPTY,false,ChatAbilities.NO_RESTRICTIONS,new ItemActivation());}
 }
'''

EXTRA=r'''
 static <T> Map<String,Object> reload(net.minecraft.core.Registry<T> registry,JsonObject resources){Map<net.minecraft.resources.Identifier,List<net.minecraft.tags.TagLoader.EntryWithSource>> parsed=new HashMap<>();for(var file:resources.entrySet()){JsonObject data=JsonParser.parseString(file.getValue().getAsString()).getAsJsonObject();List<net.minecraft.tags.TagLoader.EntryWithSource> entries=new ArrayList<>();for(JsonElement value:data.getAsJsonArray("values")){var entry=net.minecraft.tags.TagEntry.CODEC.parse(com.mojang.serialization.JsonOps.INSTANCE,value).getOrThrow();entries.add(new net.minecraft.tags.TagLoader.EntryWithSource(entry,"official26.3:"+file.getKey()));}parsed.put(net.minecraft.resources.Identifier.parse(file.getKey()),entries);}net.minecraft.tags.TagLoader<Holder<T>> loader=new net.minecraft.tags.TagLoader<>((id,required)->registry.get(id).map(h->(Holder<T>)h),"official26.3");var built=loader.build(parsed);Map<net.minecraft.tags.TagKey<T>,List<Holder<T>>> wrapped=new HashMap<>();Map<String,Object> members=new TreeMap<>();for(var e:built.entrySet()){wrapped.put(net.minecraft.tags.TagKey.create(registry.key(),e.getKey()),e.getValue());members.put(e.getKey().toString(),e.getValue().stream().map(h->registry.getKey(h.value()).toString()).toList());}var pending=registry.prepareTagReload(new net.minecraft.tags.TagLoader.LoadResult<>(registry.key(),wrapped));int size=pending.size();pending.apply();return Map.of("built_members",members,"applied_size",size,"pending_class",pending.getClass().getName());}
 static Map<String,Object> memberships(){Map<String,Object> blocks=new TreeMap<>(),fluids=new TreeMap<>();for(String id:List.of("air","stone","dirt","oak_planks","ladder","vine","scaffolding","sweet_berry_bush","cobweb","end_portal","end_gateway","nether_portal","water","lava")){var b=BuiltInRegistries.BLOCK.getValue(net.minecraft.resources.Identifier.withDefaultNamespace(id)).defaultBlockState();blocks.put(id,block(b));}for(String id:List.of("empty","water","flowing_water","lava","flowing_lava")){var f=BuiltInRegistries.FLUID.getValue(net.minecraft.resources.Identifier.withDefaultNamespace(id)).defaultFluidState();fluids.put(id,fluid(f));}return Map.of("blocks",blocks,"fluids",fluids);}
 static Map<String,Object> expanded(Vec3 from,Vec3 to){Vec3 end=new Vec3(Mth.lerp(-1.0E-7,to.x,from.x),Mth.lerp(-1.0E-7,to.y,from.y),Mth.lerp(-1.0E-7,to.z,from.z));Vec3 start=new Vec3(Mth.lerp(-1.0E-7,from.x,to.x),Mth.lerp(-1.0E-7,from.y,to.y),Mth.lerp(-1.0E-7,from.z,to.z));return Map.of("scope","Direct actual Mth.lerp supporting helper calls, not captured private DDA locals","start",vector(start),"end",vector(end),"equals",from.equals(to));}
 static Map<String,Object> vectorHelpers(Vec3 from,Vec3 to){Vec3 delta=to.subtract(from);double squared=delta.lengthSqr(),length=delta.length(),limit=Math.min(length,8.0);Vec3 normalized=delta.normalize(),scaled=normalized.scale(limit);return Map.of("scope","Independent calls to original Vec3 lengthSqr/length/normalize/scale/add and Math.min, not captured Entity.move locals or decisive clip expected endpoints","delta",vector(delta),"length_squared_f64_bits",bits(squared),"length_f64_bits",bits(length),"normalized",vector(normalized),"capped_length_f64_bits",bits(limit),"scaled",vector(scaled),"helper_endpoint",vector(from.add(scaled)));}
 static void writes(Context c,JsonArray changes){for(JsonElement e:changes){var w=e.getAsJsonObject();var p=w.getAsJsonArray("position");var id=net.minecraft.resources.Identifier.withDefaultNamespace(w.get("block").getAsString());if(!BuiltInRegistries.BLOCK.containsKey(id))throw new IllegalArgumentException("Unknown fixture block "+id);c.level.blocks.put(new BlockPos(p.get(0).getAsInt(),p.get(1).getAsInt(),p.get(2).getAsInt()),BuiltInRegistries.BLOCK.getValue(id).defaultBlockState());}}
 static Map<String,Object> selectors(Context c){BlockPos pos=new BlockPos(0,1,0);var context=new net.minecraft.world.level.ClipContext(new Vec3(.5,.5,.5),new Vec3(.5,1.5,.5),net.minecraft.world.level.ClipContext.Block.FALLDAMAGE_RESETTING,net.minecraft.world.level.ClipContext.Fluid.WATER,c.p);Map<String,Object> r=new TreeMap<>();for(String id:List.of("air","stone","dirt","oak_planks","ladder","sweet_berry_bush","cobweb","end_portal","end_gateway","nether_portal","water","lava")){BlockState b=BuiltInRegistries.BLOCK.getValue(net.minecraft.resources.Identifier.withDefaultNamespace(id)).defaultBlockState();r.put(id,Map.of("block",block(b),"selected_block_boxes",boxes(context.getBlockShape(b,c.level,pos)),"selected_fluid_boxes",boxes(context.getFluidShape(b.getFluidState(),c.level,pos))));}return r;}
 static void emit(Object v){OUTPUT.println("FALL_RESET_WORLD_JSON:"+JSON.toJson(v));}
 static void runtime()throws Exception{Map<String,String> r=new TreeMap<>();for(String name:List.of("java.lang.Math","java.lang.StrictMath","java.lang.FdLibm","java.lang.FdLibm$Acos")){Class<?> c=Class.forName(name);r.put(name,HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(c.getResourceAsStream("/"+name.replace('.','/')+".class").readAllBytes())));}OUTPUT.println("FALL_RESET_WORLD_RUNTIME:"+JSON.toJson(r));}
 public static void run(String ignored)throws Exception{SharedConstants.tryDetectVersion();Bootstrap.bootStrap();runtime();var inputs=JsonParser.parseString(new String(Base64.getDecoder().decode(__INPUT_BASE64__),java.nio.charset.StandardCharsets.UTF_8)).getAsJsonObject();var before=memberships();var blockReload=reload(BuiltInRegistries.BLOCK,inputs.getAsJsonObject("tag_files").getAsJsonObject("block"));var fluidReload=reload(BuiltInRegistries.FLUID,inputs.getAsJsonObject("tag_files").getAsJsonObject("fluid"));var after=memberships();emit(Map.of("group","tag_reload","before",before,"block_reload",blockReload,"fluid_reload",fluidReload,"after",after));HolderLookup.Provider lookup=VanillaRegistries.createWorldLookup();
  for(JsonElement e:inputs.getAsJsonArray("cases")){JsonObject in=e.getAsJsonObject();for(boolean observed:List.of(false,true)){Context c=new Context(lookup,observed);((BudgetLevel)c.level).readLimit=in.get("read_limit").getAsInt();writes(c,in.getAsJsonArray("world_writes"));Vec3 from=vec(in.getAsJsonArray("from")),to=vec(in.getAsJsonArray("to"));var beforeBody=state(c.p);var expansion=expanded(from,to);var helpers=vectorHelpers(from,to);TraceLevel trace=observed?(TraceLevel)c.level:null;if(observed){trace.events.clear();trace.capture=true;}var clip=observed?new ObservedClip(from,to,c.p,trace):new net.minecraft.world.level.ClipContext(from,to,net.minecraft.world.level.ClipContext.Block.FALLDAMAGE_RESETTING,net.minecraft.world.level.ClipContext.Fluid.WATER,c.p);Map<String,Object> row=new TreeMap<>();try{row.put("result",hitResult(c.level.clip(clip)));row.put("actual_returned",true);}catch(Throwable error){row.put("actual_returned",false);row.put("error_class",error.getClass().getName());row.put("error_message",String.valueOf(error.getMessage()));}if(observed)trace.capture=false;row.put("id",in.get("id").getAsString());row.put("observed",observed);row.put("before",beforeBody);row.put("after",state(c.p));row.put("expanded",expansion);row.put("vector_helpers",helpers);row.put("read_attempt_count",((BudgetLevel)c.level).readCount);row.put("events",observed?List.copyOf(trace.events):List.of());emit(row);}}Context helper=new Context(lookup,false);emit(Map.of("group","selectors","values",selectors(helper)));
 }
}
'''
def source():
    assert hashlib.sha256(LC.SOURCE.encode()).hexdigest()==FROZEN_LC_SOURCE
    s=LC.SOURCE.replace('LocalCollisionReceiverFixture','FallResetWorldReceiverFixture')
    a=s.index(' static class TraceLevel');b=s.index(' static class Context',a);s=s[:a]+OBSERVERS+s[b:]
    s=s.replace('new LocalInputReceiverFixture.FixtureLevel(connection,LocalInputReceiverFixture.dimension(lookup))','new BudgetLevel(connection,LocalInputReceiverFixture.dimension(lookup))')
    a=s.index(' static void configure(');return s[:a]+EXTRA
SOURCE=source()

def tag_files():
    result={'block':{},'fluid':{}};pins={}
    with zipfile.ZipFile(CLIENT) as jar:
        def load(kind,id):
            if id in result[kind]:return
            namespace,path=id.split(':',1);entry=f'data/{namespace}/tags/{kind}/{path}.json';raw=jar.read(entry);data=json.loads(raw);result[kind][id]=raw.decode();pins[entry]={'bytes':len(raw),'sha256':hashlib.sha256(raw).hexdigest(),'json':data}
            for item in data['values']:
                value=item if isinstance(item,str) else item['id']
                if value.startswith('#'):load(kind,value[1:])
        load('block','minecraft:fall_damage_resetting');load('fluid','minecraft:water')
    return result,pins
def inputs():
    tags,_=tag_files();d=LC.db
    def case(id,from_,to,writes=(),**kwargs):return {'id':id,'from':[d(v) for v in from_],'to':[d(v) for v in to],'world_writes':list(writes),'read_limit':256,'scope':'four-state-default-tag-empty-fluid',**kwargs}
    cases=[case('floor_miss',(.5,3,.5),(.5,1,.5)),case('xyz_tie',(.5,.5,.5),(2.5,2.5,2.5)),case('signed_zero',(0.,0.,0.),(-0.,0.,0.)),case('water_hit',(.5,3,.5),(.5,.2,.5),[{'position':[0,1,0],'block':'water'}],scope='unsupported-selected-fluid'),case('cobweb_hit',(.5,3,.5),(.5,.2,.5),[{'position':[0,1,0],'block':'cobweb'}],scope='unsupported-reset-block')]
    for point in [(0.,0.,0.),(-0.,-0.,-0.),(-1.,-1.,-1.),(.5,.5,.5),(2147483000.,0.,0.),(-2147483000.,0.,0.)]:cases.append(case('equal:'+','.join(map(str,point)),point,point,read_limit=0))
    for mask in range(1,8):
        from_=[-0. if mask&(1<<i) else 0. for i in range(3)];cases.append(case('signed_zero_mask:'+str(mask),from_,[0.,0.,0.]))
    for axis in range(3):
        for direction in [-1,1]:
            for fixed in [0.,-2.,.5]:
                from_=[fixed]*3;to=from_.copy();to[axis]=fixed+direction*2.5;cases.append(case(f'stationary:{axis}:{direction}:{fixed}',from_,to))
        for length in [5e-324,1e-320,1e-12,1e-7,1e-5,.00031622776601683794,.001]:
            for direction in [-1,1]:
                from_=[0.]*3;to=from_.copy();to[axis]=length*direction;cases.append(case(f'tiny:{axis}:{direction}:{length}',from_,to))
    for from_,to in [((2.5,2.5,2.5),(-2.5,-2.5,-2.5)),((.5,.5,.5),(3.5,3.5,.5)),((.5,.5,.5),(3.5,.5,3.5)),((.5,.5,.5),(.5,3.5,3.5)),((0,0,0),(3,3,3)),((0,0,0),(-3,-3,-3)),((-.5,-.5,-.5),(-3.5,2.5,-3.5)),((.5,.5,.5),(math.nextafter(3.5,math.inf),3.5,3.5))]:cases.append(case('tie:'+str(len(cases)),from_,to))
    for boundary in [-1.,0.,1.]:
        for point in [math.nextafter(boundary,-math.inf),boundary,math.nextafter(boundary,math.inf),boundary-1e-7,boundary+1e-7]:
            cases.append(case('epsilon:'+str(len(cases)),(point,.5,.5),(point+1.,.5,.5)))
    for palette in ['air','stone','dirt','oak_planks']:
        writes=[{'position':[x,0,z],'block':palette} for x in range(-2,3) for z in range(-2,3)];cases.append(case('palette:'+palette,(-2.,1.,-2.),(2.,-1.,2.),writes))
    cases.append(case('mixed_world',(-2.5,.5,-2.5),(2.5,.5,2.5),[{'position':[0,0,0],'block':'air'},{'position':[1,0,1],'block':'dirt'},{'position':[2,0,2],'block':'oak_planks'}]))
    for block in ['ladder','sweet_berry_bush','end_portal','end_gateway','nether_portal','lava']:
        cases.append(case('unsupported:'+block,(.5,3.,.5),(.5,.2,.5),[{'position':[0,1,0],'block':block}],scope='unsupported-block-or-fluid-profile'))
    for from_,to,scope in [((15.5,.5,.5),(16.5,.5,.5),'outside-owned-core'),((-15.5,.5,.5),(-16.5,.5,.5),'outside-owned-core'),((1e20,.5,.5),(1e20,.5,.5),'outside-endpoint-admission'),((2147483647.5,.5,.5),(2147483648.5,.5,.5),'outside-endpoint-admission'),((-2147483648.5,.5,.5),(-2147483649.5,.5,.5),'outside-endpoint-admission')]:cases.append(case('boundary:'+str(len(cases)),from_,to,scope=scope))
    cases.append(case('bounded_read_watchdog',(.5,.5,.5),(1000000.5,.5,.5),scope='external-read-watchdog-partial-trace',read_limit=32))
    for tiny in [5e-324,1e-320]:cases.append(case('mixed_negative_y_subnormal:'+str(tiny),(0.,0.,0.),(1.,-tiny,0.)))
    for ref in [T.OUTPUT,T.MH.OUTPUT]:
        data=json.loads(ref.read_text())
        for original in data['cases']:
            writes=copy.deepcopy(original['initial']['world_writes'])
            for si,step in enumerate(original['steps']):
                writes+=copy.deepcopy(step['world_writes'])
                for event in step.get('ray_observation',{}).get('clip_calls',[]):
                    if event['method']=='fallClip_entry':cases.append({'id':ref.stem+':'+original['id']+':'+str(si),'from':copy.deepcopy(event['from']),'to':copy.deepcopy(event['to']),'world_writes':copy.deepcopy(writes),'read_limit':256,'scope':'four-state-default-tag-empty-fluid','origin_reference':{'path':str(ref.relative_to(ROOT)),'case_id':original['id'],'step_index':si,'clip_entry_sequence':event['sequence'],'endpoint_scope':'Exact frozen actual Entity.move ray endpoints copied byte-for-byte; no Python endpoint arithmetic'}})
    return {'tag_files':tags,'cases':cases}
def dependencies():
    assert fingerprint(T.OUTPUT)['sha256']==FROZEN_TRAVEL_REFERENCE
    assert fingerprint(T.MH.OUTPUT)['sha256']==FROZEN_HISTORY_REFERENCE
    return {'li_dependency':LC.dependency_pin(),'receiver_templates':{n:hashlib.sha256(s.encode()).hexdigest() for n,s in LI.RECEIVER_SOURCES.items()},'launcher_sha256':hashlib.sha256(LI.RECEIVER_LAUNCHER.encode()).hexdigest(),'lc_source_sha256':FROZEN_LC_SOURCE,'lc_producer':fingerprint(Path(LC.__file__)),'travel_producer':fingerprint(Path(T.__file__)),'travel_reference':fingerprint(T.OUTPUT),'history_reference':fingerprint(T.MH.OUTPUT)}
def runtime_files():return T.runtime_files()
def boundary():return {'decisive':'Original BlockGetter.clip/traverseBlocks and ClipContext selectors execute on a normal LocalPlayer/ClientLevel. Plain/observed body and actual raw hit/MISS/error projections agree. No host ray expected algorithm supplies results.','services':'Four frozen LI services and real finite FixtureLevel world. TraceLevel.clip/getBlockState/getFluidState and ObservedClip selectors call super. External block map otherwise air plus25-stone floor and exact sequential writes. External read watchdog bounds admitted/unsupported fixture work; rejected attempts are separately counted.','tags':'Explicit official26.3 default reset/water profile: raw jar fall_damage_resetting recursively includes climbable; water tag loaded separately. Exact TagEntry.CODEC→TagLoader.build→Registry.prepareTagReload(LoadResult).apply. Other unrelated tags are not represented as a complete loaded data pack. Actual before/after membership and build/apply results are retained.','reads':'Each admitted callback performs one direct BlockSample getBlockState then nested getFluidState→getBlockState FluidSource. Exact duplicate visits and two ordered reads per cell retained; no inferred order. Unsupported selected water may consult/cache original FlowingFluid shapes; observer parity covers body/result, not equality of its cache-sensitive read count. Standalone selectors run after decisive ray cases.','expanded':'Direct official Mth.lerp helper calls expose expanded endpoints separately, not private production locals. Decisive actual visits come from super-calling getBlockShape per callback.','endpoints':'Required Entity.move rays/world writes copied raw from frozen LocalTravelHistory/LocalMoveHistory, never recomposed. Original Entity.move/Vec3 endpoint operations and DDA helpers are independently bytecode-pinned.','admission':'Current supported palette is air/stone/dirt/oak_planks under default tags with empty fluids and empty selected shapes. Admitted visited cells lie wholly in[-16,16)^3; bounded out-of-Core/endpoint-domain/reset/fluid/portal/watchdog observations remain explicitly excluded. Equal rays within endpoint bounds can perform zero reads anywhere.','scope':'Bounded four-state default-tag reset-ray MISS/read-order projection only, no general resetting/fluid Hit/no-damage gameplay or full world/tick parity.'}
def source_inventory():
    result=T.source_inventory();wanted={'move','normalize','length','lengthSqr','scale','multiply','add','equals','subtract','distanceToSqr','clip','clipWithInteractionOverride','traverseBlocks','lambda$clip$0','lambda$clip$1','getBlockShape','getFluidShape','get','canPick','lambda$static$0','lambda$static$2','lerp','floor','lfloor','frac','sign','containing','set','build','prepareTagReload','apply','bindTags','refreshTagsInHolders','getShape','getHeight','getOwnHeight','hasSameAbove','lambda$getShape$0','is','getInteractionShape','getFluidState','TagEntry','EntryWithSource','LoadResult','TagLoader','getApproximateNearest','miss'}
    owners=['net.minecraft.world.entity.Entity','net.minecraft.world.phys.Vec3','net.minecraft.util.Mth','net.minecraft.world.level.BlockGetter','net.minecraft.world.level.ClipContext','net.minecraft.world.level.ClipContext$Block','net.minecraft.world.level.ClipContext$Fluid','net.minecraft.world.phys.shapes.VoxelShape','net.minecraft.tags.TagEntry','net.minecraft.tags.TagEntry$Lookup','net.minecraft.tags.TagLoader','net.minecraft.tags.TagLoader$ElementLookup','net.minecraft.tags.TagLoader$EntryWithSource','net.minecraft.tags.TagLoader$LoadResult','net.minecraft.core.Registry','net.minecraft.core.Registry$PendingTags','net.minecraft.core.MappedRegistry','net.minecraft.core.MappedRegistry$2','net.minecraft.core.MappedRegistry$3','net.minecraft.core.Holder$Reference','net.minecraft.core.HolderSet$Named','net.minecraft.world.level.material.FluidState','net.minecraft.world.level.material.FlowingFluid','net.minecraft.world.level.block.state.BlockBehaviour','net.minecraft.world.level.block.state.BlockBehaviour$BlockStateBase','net.minecraft.world.level.block.state.BlockState','net.minecraft.core.BlockPos','net.minecraft.core.BlockPos$MutableBlockPos','net.minecraft.core.Direction','net.minecraft.world.phys.BlockHitResult','net.minecraft.tags.BlockTags','net.minecraft.tags.FluidTags']
    with zipfile.ZipFile(CLIENT) as jar:
        for owner in owners:
            text=subprocess.run([str(JAVA.parent/'javap'),'-classpath',str(CLIENT),'-c','-p',owner],capture_output=True,text=True,check=True).stdout;methods=[]
            for sig,body in re.findall(r'^  ((?:public|protected|private|static)[^\n]*?\([^\n]*\);)\n(.*?)(?=^  (?:public|protected|private|static)|\Z)',text,re.M|re.S):
                name=re.search(r'([\w$<>]+)\([^\n]*\);$',sig)
                if name and name[1] in wanted:methods.append({'signature':sig,'bytecode_text_sha256':hashlib.sha256(body.encode()).hexdigest(),'direct_call_references':sorted(set(re.findall(r'// (?:InterfaceMethod|Method) (.+)',body))),'field_references':sorted(set(re.findall(r'// Field (.+)',body)))})
            prior=result.get(owner,{}).get('methods',[]);seen={m['signature'] for m in methods};methods += [m for m in prior if m['signature'] not in seen];entry=owner.replace('.','/')+'.class';result[owner]={'class_entry':entry,'class_sha256':hashlib.sha256(jar.read(entry)).hexdigest(),'complete_bytecode_text_sha256':hashlib.sha256(text.encode()).hexdigest(),'methods':methods}
    return result
def sources(values):
    result=LI.receiver_sources();result[CLASS]=SOURCE.replace('__INPUT_BASE64__',LI.java_string(base64.b64encode(canonical(values)).decode()));return result
def collect(values,rows):
    reload=next(r for r in rows if r.get('group')=='tag_reload');selectors=next(r for r in rows if r.get('group')=='selectors');cases=[]
    for request in values['cases']:
        pair=[r for r in rows if r.get('id')==request['id']];assert len(pair)==2
        plain=next(r for r in pair if not r['observed']);actual=next(r for r in pair if r['observed']);assert {k:v for k,v in plain.items() if k not in ('events','observed','read_attempt_count')}=={k:v for k,v in actual.items() if k not in ('events','observed','read_attempt_count')},request['id']+' observer parity';assert actual['before']==actual['after']
        events=actual['events'];cells=[e['position'] for e in events if e['method']=='getBlockShape_exit'];reads=[e for e in events if e['method']=='getBlockState'];shape_events=[e for e in events if e['method'] in ('getBlockShape_exit','getFluidShape_exit')]
        admitted=request['scope']=='four-state-default-tag-empty-fluid' and actual['actual_returned'] and actual['result']['type']=='MISS' and all(not e['boxes'] for e in shape_events) and all(not e['reset_tag'] and e['fluid']['empty'] and e['block_id'] in {'minecraft:air','minecraft:stone','minecraft:dirt','minecraft:oak_planks'} for e in reads) and all(all(-16<=v<16 for v in p) for p in cells)
        item={**request,**{k:v for k,v in actual.items() if k not in ('id','observed','events')},'plain_read_attempt_count':plain['read_attempt_count'],'plain_observer_parity':True,'admission':{'supported':admitted},'visited_cells':cells,'reads':reads,'fluid_events':[e for e in events if e['method'].startswith('getFluidState')],'shape_events':shape_events,'clip_calls':[e for e in events if e['method'].startswith('clip_')]}
        if not admitted:item['admission']['exclusion']=request['scope'] if actual['actual_returned'] else 'external read watchdog interrupted actual clip: '+actual['error_class']
        if admitted:
            assert len(reads)==2*len(cells) and actual['read_attempt_count']==plain['read_attempt_count']==len(reads)
            assert [e['read_ordinal'] for e in reads]==list(range(len(reads)))
            for i,p in enumerate(cells):assert reads[2*i]['position']==reads[2*i+1]['position']==p and reads[2*i]['phase']=='BlockSample' and reads[2*i+1]['phase']=='FluidSource'
            item['minimum_core_read_budget']=len(reads)
        cases.append(item)
    return {'tag_reload':reload,'selectors':selectors['values'],'cases':cases}
def counts(value):return {'cases':len(value['cases']),'supported':sum(c['admission']['supported'] for c in value['cases']),'actual_returns':sum(c['actual_returned'] for c in value['cases']),'visited_cells':sum(len(c['visited_cells']) for c in value['cases']),'block_reads':sum(len(c['reads']) for c in value['cases']),'hits':sum(c.get('result',{}).get('type')=='BLOCK' for c in value['cases']),'interrupted_clips':sum(not c['actual_returned'] for c in value['cases']),'supported_visited_cells':sum(len(c['visited_cells']) for c in value['cases'] if c['admission']['supported']),'supported_block_reads':sum(len(c['reads']) for c in value['cases'] if c['admission']['supported']),'required_actual_move_rays':sum('origin_reference' in c for c in value['cases'])}
def run(values,label):
    dep=dependencies();cp,prov=verified_client_classpath();ss=sources(values);payload={'sources':ss,'client_jar':str(CLIENT),'mode':'fall_reset_world'};encoded=base64.b64encode(canonical(payload)).decode();launcher=LI.RECEIVER_LAUNCHER.replace('net.minecraft.fixture.LocalInputReceiverFixture',CLASS).replace('Base64.getDecoder().decode(args[0])','Base64.getDecoder().decode('+LI.java_string(encoded)+')',1)
    command=[str(JAVA),'--source','25','--class-path',':'.join(map(str,cp)),'/dev/stdin'];started=time.monotonic();process=subprocess.Popen(command,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
    timed_out=False
    try:stdout,stderr=process.communicate(launcher,timeout=120)
    except subprocess.TimeoutExpired:os.killpg(process.pid,signal.SIGKILL);stdout,stderr=process.communicate();timed_out=True
    p=subprocess.CompletedProcess(command,process.returncode,stdout,stderr);parse=lambda prefix:[json.loads(line[len(prefix):]) for line in p.stdout.splitlines() if line.startswith(prefix)]
    rows=parse('FALL_RESET_WORLD_JSON:');loaded=parse('LOCAL_INPUT_CLASSES:');runtime=parse('FALL_RESET_WORLD_RUNTIME:');raw=RAW/(label+'.full.json');save(raw,{'status':'raw','producer':fingerprint(Path(__file__)),'dependency':dep,'provenance':prov,'source_sha256':hashlib.sha256(SOURCE.encode()).hexdigest(),'inputs':values,'sources':ss,'launcher':launcher,'command':command,'pid':process.pid,'cap_seconds':120,'timed_out':timed_out,'rows':rows,'loaded_official_classes':loaded,'runtime':runtime,'stdout':p.stdout,'stderr':p.stderr,'returncode':p.returncode})
    if p.returncode:
        failed=RAW/f'{label}-setup-failure-{time.time_ns()}.full.json';failed.write_bytes(raw.read_bytes());save(ROOT/f'evidence/fall-reset-world-reference-{label}-setup-failure.json',{'status':'setup-only-failed','producer':fingerprint(Path(__file__)),'source_sha256':hashlib.sha256(SOURCE.encode()).hexdigest(),'raw_report':{'path':str(failed.relative_to(ROOT)),**fingerprint(failed)}})
    assert not timed_out,('120s actual reset-ray fixture watchdog expired',str(raw));assert p.returncode==0,('Setup failure',str(raw),p.stdout[-5000:],p.stderr[-2000:]);assert len(loaded)==len(runtime)==1
    with zipfile.ZipFile(CLIENT) as jar:
        for name,h in loaded[0].items():assert hashlib.sha256(jar.read(name.replace('.','/')+'.class')).hexdigest()==h
    projected=collect(values,rows);inventory=source_inventory()
    for name,h in runtime[0].items():inventory[name]['class_sha256']=h
    expanded_sources={n:hashlib.sha256(s.encode()).hexdigest() for n,s in ss.items()}
    full=json.loads(raw.read_text());full.update(source_inventory=inventory,runtime_files=runtime_files(),expanded_sources_sha256=expanded_sources,compiled_launcher_sha256=hashlib.sha256(launcher.encode()).hexdigest(),boundary=boundary(),projected_sha256=sha(projected),tag_files=tag_files()[1]);save(raw,full)
    report={'status':'passed','producer':fingerprint(Path(__file__)),'dependency':dep,'provenance':{k:v for k,v in prov.items() if k not in ('libraries','missing_other_platform_natives')},'provenance_sha256':sha(prov),'source_sha256':hashlib.sha256(SOURCE.encode()).hexdigest(),'expanded_sources_sha256':expanded_sources,'launcher_sha256':hashlib.sha256(LI.RECEIVER_LAUNCHER.encode()).hexdigest(),'tag_files':tag_files()[1],'raw_report':{'path':str(raw.relative_to(ROOT)),**fingerprint(raw)},'observations_sha256':sha(rows),'projected_sha256':sha(projected),'counts':counts(projected),'loaded_official_class_count':len(loaded[0]),'loaded_official_class_tree_sha256':sha(loaded[0]),'runtime_classes':runtime[0],'runtime_files':runtime_files(),'source_inventory_sha256':sha(inventory),'source_classes':{n:v['class_sha256']for n,v in inventory.items()},'source_methods_sha256':{n:sha(v['methods'])for n,v in inventory.items()},'boundary':boundary(),'seconds':round(time.monotonic()-started,6),'command_prefix':command[:3],'command_sha256':sha(command),'pid':process.pid,'cap_seconds':120,'stdout_sha256':hashlib.sha256(p.stdout.encode()).hexdigest(),'stderr_sha256':hashlib.sha256(p.stderr.encode()).hexdigest(),'compiled_launcher_sha256':hashlib.sha256(launcher.encode()).hexdigest(),'reproduce':'PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_fall_reset_world_probe.py --'+('rerun' if label=='independent' else 'debug' if label=='debug' else 'extract')}
    for key in ['libraries','missing_other_platform_natives']:report['provenance'][key+'_count']=len(prov[key]);report['provenance'][key+'_sha256']=sha(prov[key])
    path=ROOT/f'evidence/fall-reset-world-reference-{label}.json';save(path,report);verify_report(path);return projected,report
def verify_report(path):
    report=json.loads(path.read_text());raw=ROOT/report['raw_report']['path'];assert report['raw_report']=={'path':report['raw_report']['path'],**fingerprint(raw)};e=json.loads(raw.read_text());assert sha(e['rows'])==report['observations_sha256'];assert sha(e['provenance'])==report['provenance_sha256'];assert sha(e['loaded_official_classes'][0])==report['loaded_official_class_tree_sha256'];assert len(e['loaded_official_classes'][0])==report['loaded_official_class_count'];assert sha(e['source_inventory'])==report['source_inventory_sha256'];assert sha(e['command'])==report['command_sha256'];assert e['runtime_files']==report['runtime_files'];assert e['runtime'][0]==report['runtime_classes'];assert e['tag_files']==report['tag_files'];assert e['projected_sha256']==report['projected_sha256'];assert {n:hashlib.sha256(s.encode()).hexdigest()for n,s in e['sources'].items()}==report['expanded_sources_sha256'];assert hashlib.sha256(e['launcher'].encode()).hexdigest()==report['compiled_launcher_sha256']
    for stream in ['stdout','stderr']:assert hashlib.sha256(e[stream].encode()).hexdigest()==report[stream+'_sha256']
    assert e['producer']==report['producer'] and e['dependency']==report['dependency'] and e['source_sha256']==report['source_sha256'] and e['boundary']==report['boundary'];assert e['pid']==report['pid'] and e['cap_seconds']==report['cap_seconds'] and not e['timed_out'] and e['returncode']==0
    assert {n:v['class_sha256']for n,v in e['source_inventory'].items()}==report['source_classes'];assert {n:sha(v['methods'])for n,v in e['source_inventory'].items()}==report['source_methods_sha256'];assert e['expanded_sources_sha256']==report['expanded_sources_sha256'];assert collect(e['inputs'],e['rows']) and sha(collect(e['inputs'],e['rows']))==report['projected_sha256'] and counts(collect(e['inputs'],e['rows']))==report['counts']
    for key in ['libraries','missing_other_platform_natives']:assert report['provenance'][key+'_count']==len(e['provenance'][key]) and report['provenance'][key+'_sha256']==sha(e['provenance'][key])
    return report
def verify_data(d,prov,inventory):
    values=inputs();assert d['pin']=='26.3'and d['schema_version']==1;assert d['inputs_sha256']==sha(values);assert d['dependency']==dependencies();assert d['provenance']==prov;assert d['runtime_files']==runtime_files();assert d['runtime_classes']==LC.runtime_inventory();assert d['source_sha256']==hashlib.sha256(SOURCE.encode()).hexdigest();assert d['expanded_sources_sha256']=={n:hashlib.sha256(s.encode()).hexdigest()for n,s in sources(values).items()};assert d['launcher_sha256']==hashlib.sha256(LI.RECEIVER_LAUNCHER.encode()).hexdigest();assert d['tag_files']==tag_files()[1];assert d['boundary']==boundary()
    for n,h in d['runtime_classes'].items():inventory[n]['class_sha256']=h
    assert d['source']==inventory;assert d['projected_sha256']==sha({k:d[k]for k in ['tag_reload','selectors','cases']});assert d['counts']==counts(d)
    raw=ROOT/d['raw_report']['path'];assert d['raw_report']=={'path':d['raw_report']['path'],**fingerprint(raw)};e=json.loads(raw.read_text());assert e['inputs']==values;assert collect(values,e['rows'])=={k:d[k]for k in ['tag_reload','selectors','cases']};assert sha(e['rows'])==d['observations_sha256'];assert sha(e['loaded_official_classes'][0])==d['loaded_official_class_tree_sha256'];assert len(e['loaded_official_classes'][0])==d['loaded_official_class_count'];assert e['source_inventory']==d['source'];assert e['provenance']==d['provenance'];assert {n:hashlib.sha256(s.encode()).hexdigest()for n,s in e['sources'].items()}==d['expanded_sources_sha256']
    with zipfile.ZipFile(CLIENT)as jar:
        for n,h in e['loaded_official_classes'][0].items():assert hashlib.sha256(jar.read(n.replace('.','/')+'.class')).hexdigest()==h
def verify(selftest=False):
    d=json.loads(OUTPUT.read_text());_,prov=verified_client_classpath();inventory=source_inventory();verify_data(d,prov,inventory);r={'status':'passed','scope':'Stored actual observations/provenance integrity only; no new ray run.','producer':fingerprint(Path(__file__)),'reference':fingerprint(OUTPUT),'counts':d['counts']}
    if selftest:
        r['failure_injections']=[]
        for label,path in [('client',['provenance','client','sha256']),('runtime',['provenance','java','sha256']),('library',['provenance','libraries',0,'sha256']),('modules',['runtime_files','jrt_modules','sha256']),('source',['source_sha256']),('tag_file',['tag_files','data/minecraft/tags/block/fall_damage_resetting.json','sha256']),('bound_membership',['tag_reload','after','blocks','cobweb','reset_tag']),('class_tree',['loaded_official_class_tree_sha256']),('read',['cases',0,'reads',0,'state_id']),('read_phase',['cases',0,'reads',1,'phase']),('raw_report',['raw_report','sha256'])]:
            v=copy.deepcopy(d);o=v
            for key in path[:-1]:o=o[key]
            o[path[-1]]='injected-mismatch'
            try:verify_data(v,prov,inventory)
            except AssertionError:r['failure_injections'].append({'injection':label,'rejected':True})
            else:raise AssertionError('Mutation accepted: '+label)
    save(ROOT/'evidence/fall-reset-world-reference-integrity.json',r);return r
def extract(debug=False):
    values=inputs()
    if debug:values['cases']=values['cases'][:5]
    v,e=run(values,'debug' if debug else 'actual')
    if not debug:
        raw=json.loads((ROOT/e['raw_report']['path']).read_text());d={k:e[k]for k in ['dependency','runtime_files','runtime_classes','source_sha256','expanded_sources_sha256','launcher_sha256','tag_files','raw_report','observations_sha256','projected_sha256','counts','loaded_official_class_count','loaded_official_class_tree_sha256','boundary']};d.update(**v,inputs_sha256=sha(values),pin='26.3',schema_version=1,provenance=raw['provenance'],source=raw['source_inventory']);save(OUTPUT,d)
    return {'status':'passed','counts':e['counts'],'evidence':fingerprint(ROOT/f'evidence/fall-reset-world-reference-{"debug" if debug else "actual"}.json'),'source_sha256':e['source_sha256'],**({'reference':fingerprint(OUTPUT)} if not debug else {})}
def rerun():
    d=json.loads(OUTPUT.read_text());_,prov=verified_client_classpath();verify_data(d,prov,source_inventory());v,e=run(inputs(),'independent');assert v=={k:d[k]for k in ['tag_reload','selectors','cases']};assert e['observations_sha256']==d['observations_sha256'];assert e['loaded_official_class_tree_sha256']==d['loaded_official_class_tree_sha256'];e['independent_actual_observation_parity']=True;e['reference_compared']=fingerprint(OUTPUT);save(ROOT/'evidence/fall-reset-world-reference-independent.json',e);return {'status':'passed','independent_actual_observation_parity':True,'evidence':fingerprint(ROOT/'evidence/fall-reset-world-reference-independent.json'),'reference':fingerprint(OUTPUT)}
def storage():
    d=json.loads(OUTPUT.read_text());_,prov=verified_client_classpath();verify_data(d,prov,source_inventory());receipts=[]
    for label in ['debug','actual','independent']:
        path=ROOT/f'evidence/fall-reset-world-reference-{label}.json';r=verify_report(path)
        assert r['producer']==fingerprint(Path(__file__));assert r['source_sha256']==d['source_sha256'];assert r['provenance_sha256']==sha(prov)
        if label!='debug':assert r['observations_sha256']==d['observations_sha256'] and r['projected_sha256']==d['projected_sha256']
        if label=='independent':assert r['independent_actual_observation_parity'] and r['reference_compared']==fingerprint(OUTPUT)
        receipts.append({'receipt':{'path':str(path.relative_to(ROOT)),**fingerprint(path)},'raw_report':r['raw_report'],'observations_sha256':r['observations_sha256'],'projected_sha256':r['projected_sha256'],'counts':r['counts'],'loaded_official_class_count':r['loaded_official_class_count'],'loaded_official_class_tree_sha256':r['loaded_official_class_tree_sha256']})
    integrity=ROOT/'evidence/fall-reset-world-reference-integrity.json';checks=json.loads(integrity.read_text());assert checks['reference']==fingerprint(OUTPUT) and checks['producer']==fingerprint(Path(__file__)) and len(checks['failure_injections'])>=6 and all(x['rejected'] for x in checks['failure_injections'])
    r={'status':'passed','scope':'Tracked receipts retain fingerprints, counts, exact canonical observation digests and execution/provenance pins. Complete commands, source bytes, runtime/class trees, streams and ordered actual observations are retained in ignored raw reports; reference retains the complete typed projection.','producer':fingerprint(Path(__file__)),'reference':fingerprint(OUTPUT),'counts':d['counts'],'source_sha256':d['source_sha256'],'observations_sha256':d['observations_sha256'],'projected_sha256':d['projected_sha256'],'runtime_classes':d['runtime_classes'],'runtime_files':d['runtime_files'],'receipts':receipts,'integrity':{'path':str(integrity.relative_to(ROOT)),**fingerprint(integrity)},'failure_injection_count':len(checks['failure_injections'])}
    path=ROOT/'evidence/fall-reset-world-reference-storage.json';save(path,r);return {'status':'passed','evidence':fingerprint(path),'reference':fingerprint(OUTPUT),'receipts':len(receipts)}
def main():
    p=argparse.ArgumentParser();g=p.add_mutually_exclusive_group(required=True)
    for flag in ['debug','extract','verify-existing','selftest','rerun','storage']:g.add_argument('--'+flag,action='store_true')
    a=p.parse_args()
    if a.selftest or a.verify_existing:r=verify(a.selftest)
    elif a.rerun:r=rerun()
    elif a.storage:r=storage()
    else:r=extract(a.debug)
    print(json.dumps(r,indent=2))
if __name__=='__main__':main()
