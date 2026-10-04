import Base
import ./resource_block_catalog.bend as T
import ./core_refusal.bend as RI
import ../src/generic_resource_world_sample_read.bend as Read
import ../src/generic_resource_world_sample.bend as GS
import ../src/client_world.bend as W
import ../src/core.bend as C
import ../src/game.bend as G
import ../src/registry.bend as B
import ../src/resource_client_wire.bend as Wire
import ../src/world_mesh.bend as WM
import ../src/mesh_render.bend as Mesh
import ../src/movement.bend as MV
import ../src/geometry.bend as A
import ../src/f64.bend as F
import ../src/json.bend as J
import ../src/schedule.bend as Q

# Test command decoding and observation only. Reads, section updates, sampling,
# appearance selection, ownership, and wire encoding use production imports.
def nat(value:Nat) -> J.Value: J.JNumber{Nat.show(value)}
type Inspection is Data:
  Inspection{report:J.Value,core:RI.WorldImage}
def field(value:Maybe<&2,J.Value>) -> J.Value:
  match value:
    case Some{value}: value
    case _: J.JNull{}
def get(value:J.Value,key:String) -> J.Value: field(J.member(value,key))
def uint(+value:J.Value,key:String,fallback:U32) -> U32:
  T.integer(J.member(value,key),fallback)
def word(value:J.Value) -> U32: T.integer(Some{value},0)
def bounds(+value:J.Value) -> W.Bounds:
  W.Bounds{uint(value,"x",0),uint(value,"y",0),uint(value,"z",0),
    uint(value,"width",1),uint(value,"height",1),uint(value,"depth",1)}
def bounds_value(value:W.Bounds) -> J.Value:
  W.Bounds{x,y,z,width,height,depth} = value
  J.JArray{[T.number(x),T.number(y),T.number(z),T.number(width),T.number(height),T.number(depth)]}
def origin(value:J.Value) -> MV.Vec3:
  match value:
    case J.JArray{[xh,xl,yh,yl,zh,zl]}:
      MV.Vec3{F.F64{word(xh),word(xl)},F.F64{word(yh),word(yl)},F.F64{word(zh),word(zl)}}
    case _: MV.Vec3{F.F64{0,0},F.F64{0,0},F.F64{0,0}}
def tints(values:List<&2,J.Value>) -> List<&2,WM.Tint>:
  match values:
    case Nil{}: []
    case J.JArray{[index,color]} <> tail: WM.Tint{word(index),word(color)} <> tints(tail)
    case _ <> tail: tints(tail)
def address(value:U32) -> Mesh.Address:
  match value:
    case 1: Mesh.Repeat{}
    case _: Mesh.Clamp{}
def cull(value:U32) -> Mesh.Cull:
  match value:
    case 1: Mesh.NoCull{}
    case _: Mesh.Back{}
def appearance(value:J.Value) -> WM.Appearance:
  match value:
    case J.JArray{[J.JArray{colors},light,mode,face,nether,threshold]}:
      WM.Appearance{tints(colors),word(light),address(word(mode)),cull(word(face)),
        T.boolean(Some{nether}),word(threshold)}
    case _: WM.appearance()
def state_appearances(values:List<&2,J.Value>,out:Map<&2,WM.Appearance>) -> Map<&2,WM.Appearance>:
  match values:
    case Nil{}: out
    case +value <> tail:
      state_appearances(tail,Map.set(&2,WM.Appearance,out,U32.show(uint(value,"state",0)),
        appearance(get(value,"appearance"))))
def cell_appearances(values:List<&2,J.Value>,out:Map<&2,WM.Appearance>) -> Map<&2,WM.Appearance>:
  match values:
    case Nil{}: out
    case +value <> tail:
      cell_appearances(tail,Map.set(&2,WM.Appearance,out,
        GS.point_key(W.Cell{uint(value,"x",0),uint(value,"y",0),uint(value,"z",0),0}),
        appearance(get(value,"appearance"))))
def policy(+value:J.Value) -> GS.Policy:
  GS.Policy{uint(value,"seed",0),appearance(get(value,"default")),
    state_appearances(T.values(J.member(value,"states")),MTip{}),
    cell_appearances(T.values(J.member(value,"cells")),MTip{})}
def palette(kind:String) -> Maybe<&2,W.Palette>:
  match kind:
    case "aliases": Some{W.Palette{7,7,7,7}}
    case "normal": Some{W.Palette{0,1,10,15}}
    case _: None{}
def cache(kind:String,region:W.Bounds) -> Maybe<&2,W.SnapshotCache>:
  match kind:
    case "bad": Some{W.SnapshotCache{999n,W.Bounds{0,0,0,0,1,1},W.Palette{7,7,7,7},
      [W.RawBlock{W.Cell{123,456,789,99},4294967295,99}]}}
    case "stale": Some{W.SnapshotCache{11n,region,W.Palette{0,1,10,15},
      [W.RawBlock{W.Cell{4294967295,0,4294967295,0},1,0}]}}
    case _: None{}
def body() -> MV.Body:
  MV.Body{MV.Vec3{F.from_u32(37),F.from_u32(9),F.neg(F.from_u32(13))},
    A.AABB{F.from_u32(1),F.from_u32(2),F.from_u32(3),F.from_u32(4),F.from_u32(5),F.from_u32(6)},
    MV.Vec3{F.from_u32(7),F.from_u32(8),F.from_u32(9)},0.6,1.8,True{},False{},True{},False{}}
def view(+config:J.Value) -> W.View:
  +region = bounds(get(config,"region"))
  W.View{body(),Wire.float_bits(uint(config,"yaw",0)),Wire.float_bits(uint(config,"pitch",0)),
    palette(T.string(J.member(config,"palette"),"none")),region,
    cache(T.string(J.member(config,"cache"),"none"),region)}
def position(+value:J.Value) -> C.Position:
  C.Position{"minecraft:overworld",uint(value,"x",0),uint(value,"y",0),uint(value,"z",0)}
def operation(section:Bool,+value:J.Value) -> C.Mutation:
  match section:
    case True{}: C.SectionCreate{position(value),uint(value,"state",0)}
    case False{}: C.BlockSet{position(value),uint(value,"state",0)}
def updates(values:List<&2,J.Value>,world:C.World,+section:Bool,status:Result<&2,&2,C.Error,Unit>) ->
    C.World & Result<&2,&2,C.Error,Unit>:
  match values status:
    case _ Fail{error}: (world,Fail{error})
    case Nil{} Done{unit}: (world,Done{Unit{}})
    case value <> tail Done{unit}:
      W.paired(C.World,Result<&2,&2,C.Error,Unit>,C.World & Result<&2,&2,C.Error,Unit>,
        C.apply(world,operation(section,value)),next => current => updates(tail,next,section,current))
def marked(world:C.World) -> C.World:
  C.World{tick,time,paused,daylight,revision,count,sections,pending,events} = world
  C.World{7n,12345n,False{},False{},11n,count,sections,
    [Q.Pending{Q.Stamp{99n,8,9n},C.TimeSet{777n}}],
    [C.Applied{Q.Stamp{6n,4,3n},10n},C.Rejected{Q.Stamp{5n,2,1n},C.InvalidState{4294967295}}]}
def writes_ready(result:C.World & Result<&2,&2,C.Error,Unit>,registry:B.Registry,+config:J.Value) -> IO(W.State):
  match result:
    case (world,Fail{error}): IO.die(W.State,1,"fixture:" ++ W.error_text(error))
    case (world,Done{unit}): IO.pure(W.State,W.attach(G.Engine{marked(world),registry},view(config)))
def sections_ready(result:C.World & Result<&2,&2,C.Error,Unit>,registry:B.Registry,+config:J.Value) -> IO(W.State):
  match result:
    case (world,Fail{error}): IO.die(W.State,1,"fixture:" ++ W.error_text(error))
    case (world,Done{unit}): writes_ready(updates(T.values(J.member(config,"writes")),world,False{},Done{Unit{}}),registry,config)
def fixture(engine:G.Engine,+config:J.Value) -> IO(W.State):
  G.Engine{world,registry} = engine
  sections_ready(updates(T.values(J.member(config,"sections")),world,True{},Done{Unit{}}),registry,config)
def stamp(value:Q.Stamp) -> J.Value:
  Q.Stamp{tick,peer,sequence} = value
  J.JArray{[nat(tick),T.number(peer),nat(sequence)]}
def mutation(value:C.Mutation) -> J.Value:
  match value:
    case C.TimeSet{value}: J.JArray{[T.text("time"),nat(value)]}
    case C.DaylightSet{value}: J.JArray{[T.text("daylight"),J.JBool{value}]}
    case C.SectionCreate{C.Position{dimension,x,y,z},state}:
      J.JArray{[T.text("create"),T.text(dimension),T.number(x),T.number(y),T.number(z),T.number(state)]}
    case C.BlockSet{C.Position{dimension,x,y,z},state}:
      J.JArray{[T.text("write"),T.text(dimension),T.number(x),T.number(y),T.number(z),T.number(state)]}
def pending(values:List<&2,Q.Pending<C.Mutation>>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case Q.Pending{time,op} <> tail: J.JArray{[stamp(time),mutation(op)]} <> pending(tail)
def events(values:List<&2,C.CoreEvent>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case C.Applied{time,revision} <> tail: J.JArray{[T.text("applied"),stamp(time),nat(revision)]} <> events(tail)
    case C.Rejected{time,error} <> tail: J.JArray{[T.text("rejected"),stamp(time),T.text(W.error_text(error))]} <> events(tail)
def body_value(value:MV.Body) -> J.Value:
  MV.Body{position,A.AABB{a,b,c,d,e,f},velocity,width,height,ground,horizontal,vertical,below} = value
  J.JArray{[Wire.origin_value(position),Wire.origin_value(MV.Vec3{a,b,c}),Wire.origin_value(MV.Vec3{d,e,f}),
    Wire.origin_value(velocity),T.number(F32.bits(width)),T.number(F32.bits(height)),
    J.JBool{ground},J.JBool{horizontal},J.JBool{vertical},J.JBool{below}]}
def palette_value(value:Maybe<&2,W.Palette>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{colors}: Wire.palette_value(colors)
def raw_values(values:List<&2,W.RawBlock>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case W.RawBlock{W.Cell{x,y,z,boundary},state,material} <> tail:
      J.JArray{[T.number(x),T.number(y),T.number(z),T.number(boundary),T.number(state),T.number(material)]} <> raw_values(tail)
def cache_value(value:Maybe<&2,W.SnapshotCache>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{W.SnapshotCache{revision,region,colors,blocks}}:
      J.JArray{[nat(revision),bounds_value(region),Wire.palette_value(colors),J.JArray{raw_values(blocks)}]}
def view_value(value:W.View) -> J.Value:
  W.View{body,yaw,pitch,palette,region,cache} = value
  J.JArray{[body_value(body),T.number(F32.bits(yaw)),T.number(F32.bits(pitch)),
    palette_value(palette),bounds_value(region),cache_value(cache)]}
def image_info(value:C.World & RI.WorldImage,registry:String,view:W.View) -> C.World & Inspection:
  (world,+image) = value
  RI.WorldImage{tick,time,paused,daylight,revision,count,tree,queue,history} = image
  (world,Inspection{T.obj([J.JMember{"registry",T.text(registry)},J.JMember{"view",view_value(view)},
      J.JMember{"core",J.JArray{[nat(tick),nat(time),J.JBool{paused},J.JBool{daylight},nat(revision),T.number(count),
        J.JArray{pending(queue)},J.JArray{events(history)}]}}]),image})
def core_info(world:C.World,registry:String,view:W.View) -> C.World & Inspection:
  image_info(RI.world_image(world),registry,view)
def inspected(value:C.World & Inspection,registry:B.Registry,view:W.View) -> W.State & Inspection:
  match value:
    case (world,report): (W.attach(G.Engine{world,registry},view),report)
def registry_info(value:B.Registry & Result<&2,&2,String,String>,world:C.World,+view:W.View) -> W.State & Inspection:
  match value:
    case (registry,Fail{error}): inspected(core_info(world,"ERROR:" ++ error,view),registry,view)
    case (registry,Done{identity}): inspected(core_info(world,identity,view),registry,view)
def inspect_taken(value:G.Engine & W.View) -> W.State & Inspection:
  (G.Engine{world,registry},+view) = value
  registry_info(B.Registry.identity(registry),world,view)
def inspect(world:W.State) -> W.State & Inspection: inspect_taken(W.take(world))
def codec_sample(value:Result<&2,&2,String,GS.Sample>) -> J.Value:
  match value:
    case Fail{error}: T.obj([J.JMember{"status",T.text("error")},J.JMember{"error",T.text(error)}])
    case Done{sample}: T.obj([J.JMember{"status",T.text("ok")},J.JMember{"sample",Wire.catalog_sample_value(sample)}])
def codec_reply(value:Result<&2,&2,String,Wire.Reply>) -> J.Value:
  match value:
    case Fail{error}: T.obj([J.JMember{"status",T.text("error")},J.JMember{"error",T.text(error)}])
    case Done{Wire.CatalogFrameReply{epoch,sequence,sample}}:
      T.obj([J.JMember{"status",T.text("ok")},J.JMember{"epoch",T.text(epoch)},
        J.JMember{"sequence",nat(sequence)},J.JMember{"sample",Wire.catalog_sample_value(sample)}])
    case _: T.obj([J.JMember{"status",T.text("wrong-reply") }])
def codec_encoded(value:Result<&2,&2,String,String>) -> J.Value:
  match value:
    case Fail{error}: T.obj([J.JMember{"status",T.text("error")},J.JMember{"error",T.text(error)}])
    case Done{+text}: T.obj([J.JMember{"status",T.text("ok")},J.JMember{"text",T.text(text)},
      J.JMember{"decoded",codec_reply(Wire.decode_reply(text))}])
def sampled(value:Result<&2,&2,String,GS.Sample>) -> J.Value:
  match value:
    case Fail{error}: T.obj([J.JMember{"status",T.text("error")},J.JMember{"error",T.text(error)}])
    case Done{+sample}: T.obj([J.JMember{"status",T.text("ok")},J.JMember{"sample",Wire.catalog_sample_value(sample)},
      J.JMember{"direct_wire",codec_sample(Wire.catalog_sample(Wire.catalog_sample_value(sample)))},
      J.JMember{"full_wire",codec_encoded(Wire.encode_reply(Wire.CatalogFrameReply{"sample-test",1n,sample}))}])
def observed_after(value:W.State & Inspection,before:Inspection,result:Result<&2,&2,String,GS.Sample>,name:String) -> IO(W.State):
  match value:
    case (world,Inspection{after,after_core}):
      Inspection{before,before_core} = before
      do IO<W.State>:
        IO.print(J.encode(T.obj([J.JMember{"name",T.text(name)},J.JMember{"before",before},
          J.JMember{"after",after},J.JMember{"complete_core_equal",J.JBool{RI.worlds_equal(before_core,after_core)}},
          J.JMember{"result",sampled(result)}])))
        return world
def observed_sample(value:W.State & Result<&2,&2,String,GS.Sample>,before:Inspection,name:String) -> IO(W.State):
  match value:
    case (world,result): observed_after(inspect(world),before,result,name)
def observed_before(value:W.State & Inspection,+config:J.Value,+step:J.Value) -> IO(W.State):
  match value:
    case (world,before): observed_sample(Read.snapshot(world,origin(get(config,"origin")),
      T.string(J.member(config,"identity"),""),policy(get(config,"policy"))),before,T.string(J.member(step,"name"),""))
def changed(result:C.World & Result<&2,&2,C.Error,Unit>,registry:B.Registry,view:W.View) -> IO(W.State):
  match result:
    case (world,Fail{error}): IO.die(W.State,1,"change:" ++ W.error_text(error))
    case (world,Done{unit}): IO.pure(W.State,W.attach(G.Engine{world,registry},view))
def change(world:W.State,values:List<&2,J.Value>) -> IO(W.State):
  W.State{G.Engine{core,registry},body,yaw,pitch,palette,region,cache} = world
  changed(updates(values,core,False{},Done{Unit{}}),registry,W.View{body,yaw,pitch,palette,region,cache})
def observations(values:List<&2,J.Value>,world:W.State,+config:J.Value) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case +step <> tail:
      do IO<Unit>:
        world:W.State <- change(world,T.values(J.member(step,"writes")))
        world:W.State <- observed_before(inspect(world),config,step)
        observations(tail,world,config)
def loaded(result:Result<&2,&1,B.Error,B.Registry>,+config:J.Value) -> IO(Unit):
  match result:
    case Fail{error}: IO.die(Unit,1,"registry:" ++ B.error_text(error))
    case Done{registry}:
      do IO<Unit>:
        world:W.State <- fixture(G.new(registry),config)
        observations(T.values(J.member(config,"observations")),world,config)
def config(result:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match result:
    case Fail{error}: IO.die(Unit,1,error)
    case Done{+value}:
      do IO<Unit>:
        registry:Result<&2,&1,B.Error,B.Registry> <- B.Registry.load(T.string(J.member(value,"registry"),"generated/reference_blocks.tsv"))
        loaded(registry,value)
def configs(values:List<String>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case value <> tail:
      do IO<Unit>:
        config(J.parse(value))
        configs(tail)
def arguments(values:List<String>) -> IO(Unit):
  match values:
    case exe <> rest: configs(rest)
    case _: IO.die(Unit,1,"expected sampler observer configs")
def main() -> IO(Unit):
  do IO<Unit>:
    args:List<String> <- IO.args()
    arguments(args)
