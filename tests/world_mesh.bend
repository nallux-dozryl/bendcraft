import Base
import ../src/world_mesh.bend as WM
import ../src/client_world.bend as W
import ../src/client_render.bend as R
import ../src/mesh_render.bend as M
import ../src/block_bake.bend as K
import ../src/block_model.bend as B
import ../src/block_resources.bend as BR
import ../src/game.bend as G
import ../src/f64.bend as F
import ../src/movement.bend as MV
import ../src/png.bend as P
import ../src/core.bend as C
import ../src/registry.bend as Reg
import ../src/schedule.bend as Q

type Owned is Type:
  Owned{state:W.State,assets:R.Assets}

def word(value:F32) -> String:
  U32.show(F32.bits(value))
def number_result(result:Maybe<&2,U32>) -> U32:
  match result:
    case Some{value}: value
    case None{}: 0
def number(text:String) -> U32:
  number_result(U32.read(text))
def count_blocks(blocks:List<&2,R.Block>) -> Nat:
  match blocks:
    case Nil{}: 0n
    case block <> rest: 1n+count_blocks(rest)
def blocks_text(blocks:List<&2,R.Block>) -> String:
  match blocks:
    case Nil{}: ""
    case R.Block{x,y,z,state,material} <> rest:
      word(x) ++ "," ++ word(y) ++ "," ++ word(z) ++ "," ++ U32.show(state) ++ "," ++ U32.show(material) ++ ";" ++ blocks_text(rest)
def snapshot_text(value:R.Snapshot) -> String:
  R.Snapshot{tick,revision,+blocks,R.Camera{x,y,z,yaw,pitch}} = value
  Nat.show(tick) ++ "|" ++ Nat.show(revision) ++ "|" ++ Nat.show(count_blocks(blocks)) ++ "|" ++
    word(x) ++ "," ++ word(y) ++ "," ++ word(z) ++ "," ++ word(yaw) ++ "," ++ word(pitch) ++ "|" ++ blocks_text(blocks)
def loaded_fixture(result:W.State & Result<&2,&2,String,Unit>) -> IO(W.State):
  (state,status) = result
  match status:
    case Fail{error}: IO.die(W.State,1,"fixture failed:" ++ error)
    case Done{unit}: IO.pure(W.State,state)
def vertex_text(vertex:M.Vertex) -> String:
  M.Vertex{M.Vec3{x,y,z},M.UV{u,v}} = vertex
  word(x) ++ "," ++ word(y) ++ "," ++ word(z) ++ "," ++ word(u) ++ "," ++ word(v)
def mode_text(mode:M.Mode) -> String:
  match mode:
    case M.Opaque{}: "0,0"
    case M.Cutout{threshold}: "1," ++ U32.show(threshold)
    case M.Translucent{}: "2,0"
def address_text(address:M.Address) -> String:
  match address:
    case M.Clamp{}: "0"
    case M.Repeat{}: "1"
def cull_text(cull:M.Cull) -> String:
  match cull:
    case M.NoCull{}: "0"
    case M.Back{}: "1"
def quad_text(quad:M.Quad) -> String:
  M.Quad{a,b,c,d,M.Material{texture,tint,light,shade,mode,address},cull,order} = quad
  vertex_text(a) ++ "," ++ vertex_text(b) ++ "," ++ vertex_text(c) ++ "," ++ vertex_text(d) ++ "," ++
    U32.show(texture) ++ "," ++ U32.show(tint) ++ "," ++ U32.show(light) ++ "," ++ word(shade) ++ "," ++
    mode_text(mode) ++ "," ++ address_text(address) ++ "," ++ cull_text(cull) ++ "," ++ U32.show(order)
def quads_report(quads:List<&2,M.Quad>,+id:String,+index:U32) -> IO(Unit):
  match quads:
    case Nil{}: IO.pure(Unit,Unit{})
    case head <> tail:
      do IO<Unit>:
        IO.print("quad|" ++ id ++ "|" ++ U32.show(index) ++ "|" ++ quad_text(head))
        quads_report(tail,id,U32.inc(index))

def drawn(result:Result<&2,&2,M.Error,Image>,+id:String) -> IO(Unit):
  match result:
    case Fail{M.Error{code}}: IO.die(Unit,1,"renderer failed:" ++ code)
    case Done{image}:
      do IO<Unit>:
        R.write_ppm("build/world-mesh-" ++ id ++ ".ppm",image,32,24)
        IO.print("frame|" ++ id ++ "|32|24|build/world-mesh-" ++ id ++ ".ppm")
def render_pair(pair:R.Assets & Result<&2,&2,M.Error,Image>,id:String) -> IO(R.Assets):
  (assets,result) = pair
  do IO<R.Assets>:
    drawn(result,id)
    return assets
def scene_draw(draw:Bool,scene:M.Scene,assets:R.Assets,id:String) -> IO(R.Assets):
  match draw:
    case False{}: IO.pure(R.Assets,assets)
    case True{}: render_pair(M.render_flat(scene,assets,32,24),id)
def scene_report(result:Result<&2,&2,WM.Error,M.Scene>,assets:R.Assets,+id:String,draw:Bool) -> IO(R.Assets):
  match result:
    case Fail{WM.Error{code,state}}: IO.die(R.Assets,1,"producer failed:" ++ code ++ ":" ++ U32.show(state))
    case Done{+scene}:
      M.Scene{camera,quads,settings} = scene
      do IO<R.Assets>:
        quads_report(quads,id,0)
        scene_draw(draw,scene,assets,id)

def sampled(result:W.State & Result<&2,&2,String,R.Snapshot>,assets:R.Assets,bindings:List<&2,WM.Binding>,+id:String,draw:Bool) -> IO(Owned):
  (state,status) = result
  match status:
    case Fail{error}: IO.die(Owned,1,"snapshot failed:" ++ error)
    case Done{+snapshot}:
      do IO<Owned>:
        IO.print("snapshot|" ++ id ++ "|" ++ snapshot_text(snapshot))
        assets : R.Assets <- scene_report(WM.produce(snapshot,bindings,3,WM.frame(32,24),WM.defaults()),assets,id,draw)
        return Owned{state,assets}
def sample(owned:Owned,bindings:List<&2,WM.Binding>,id:String,draw:Bool) -> IO(Owned):
  Owned{state,assets} = owned
  sampled(W.relative_snapshot(state,32,24),assets,bindings,id,draw)
def raw_write_result(result:C.World & Result<&2,&2,C.Error,Unit>,registry:Reg.Registry,
    body:MV.Body,yaw:F32,pitch:F32,palette:Maybe<&2,W.Palette>,region:W.Bounds,cache:Maybe<&2,W.SnapshotCache>) -> W.State:
  (world,status) = result
  W.invalidate_cache(W.State{G.Engine{world,registry},body,yaw,pitch,palette,region,cache})
def edit_state(state:W.State) -> W.State:
  W.State{G.Engine{world,registry},body,yaw,pitch,+palette,region,cache} = state
  match palette:
    case None{}: W.State{G.Engine{world,registry},body,yaw,pitch,palette,region,cache}
    case Some{W.Palette{air,stone,dirt,planks}}:
      raw_write_result(C.write_block(world,C.Position{"minecraft:overworld",0,1,0},planks),registry,body,yaw,pitch,palette,region,cache)
def raw_edit(owned:Owned) -> Owned:
  Owned{state,assets} = owned
  Owned{edit_state(state),assets}
def invalidate(owned:Owned) -> Owned:
  Owned{state,assets} = owned
  Owned{W.invalidate_cache(state),assets}

def model_result(result:Result<&2,&2,BR.Error,B.Resolved>) -> Result<&2,&2,String,B.Resolved>:
  match result:
    case Fail{BR.Error{code,resource,message}}: Fail{code ++ ":" ++ resource ++ ":" ++ message}
    case Done{model}: Done{model}
def bake_result(result:Result<&2,&2,K.Error,List<&2,K.Baked>>) -> Result<&2,&2,String,List<&2,K.Baked>>:
  match result:
    case Done{baked}: Done{baked}
    case Fail{K.Unsupported{code}}: Fail{code}
    case Fail{K.Invalid{code}}: Fail{code}
    case Fail{K.MissingMaterial{reference}}: Fail{"missing:" ++ reference}
def binding(+catalog:BR.Catalog,id:String,state:U32) -> Result<&2,&2,String,WM.Binding>:
  BR.Catalog{roots,source,models,sprites,context,usage} = catalog
  do Result<&2,&2,String,WM.Binding>:
    model : B.Resolved <- model_result(BR.model(catalog,id))
    baked : List<&2,K.Baked> <- bake_result(K.bake(model,K.State{0,0,0,False{}},context))
    Done{WM.Binding{state,baked,WM.appearance()}}
def bindings(palette:Maybe<&2,W.Palette>,+catalog:BR.Catalog) -> Result<&2,&2,String,List<&2,WM.Binding>>:
  match palette:
    case None{}: Fail{"fixture palette unavailable"}
    case Some{W.Palette{air,stone,dirt,planks}}:
      do Result<&2,&2,String,List<&2,WM.Binding>>:
        stone : WM.Binding <- binding(catalog,"minecraft:block/stone",stone)
        dirt : WM.Binding <- binding(catalog,"minecraft:block/dirt",dirt)
        planks : WM.Binding <- binding(catalog,"minecraft:block/oak_planks",planks)
        Done{[stone,dirt,planks]}
def state_bindings(state:W.State,catalog:BR.Catalog) -> W.State & Result<&2,&2,String,List<&2,WM.Binding>>:
  W.State{engine,body,yaw,pitch,+palette,region,cache} = state
  (W.State{engine,body,yaw,pitch,palette,region,cache},bindings(palette,catalog))

def basic(owned:Owned,+bindings:List<&2,WM.Binding>) -> IO(Unit):
  do IO<Unit>:
    before : Owned <- sample(owned,bindings,"initial",True{})
    cached : Owned <- sample(before,bindings,"cached",True{})
    changed : Owned <- sample(raw_edit(cached),bindings,"raw-edit",True{})
    checked : Owned <- sample(invalidate(changed),bindings,"uncached",True{})
    return Unit{}

def far_admitted(result:C.World & Result<&2,&2,C.Error,Unit>,registry:Reg.Registry,
    body:MV.Body,palette:Maybe<&2,W.Palette>,region:W.Bounds) -> IO(W.State):
  (world,status) = result
  match status:
    case Fail{error}: IO.die(W.State,1,"far fixture admission:" ++ W.error_text(error))
    case Done{unit}: IO.pure(W.State,W.State{G.Engine{C.step(world),registry},body,0.0,0.2,palette,region,None{}})
def far_owned(state:W.State,+x:U32,+y:U32,+z:U32,position:MV.Vec3) -> IO(W.State):
  W.State{G.Engine{world,registry},old,yaw,pitch,+palette,region,cache} = state
  match palette:
    case None{}: IO.die(W.State,1,"far fixture palette unavailable")
    case Some{W.Palette{air,stone,dirt,planks}}:
      far_admitted(C.admit(world,C.Developer{},Q.Stamp{1n,3,0n},C.SectionCreate{C.Position{"minecraft:overworld",x,y,z},stone}),
        registry,MV.Body.new(position,0.6,1.8,MV.Vec3.zero(),True{}),palette,W.Bounds{x,y,z,3,2,3})

def far(fields:List<&2,String>,state:W.State,assets:R.Assets,bindings:List<&2,WM.Binding>) -> IO(Unit):
  match fields:
    case id <> draw <> x <> y <> z <> xh <> xl <> yh <> yl <> zh <> zl <> Nil{}:
      do IO<Unit>:
        initialized : W.State <- far_owned(state,number(x),number(y),number(z),
          MV.Vec3{F.F64{number(xh),number(xl)},F.F64{number(yh),number(yl)},F.F64{number(zh),number(zl)}})
        sampled : Owned <- sample(Owned{initialized,assets},bindings,id,U32.is_eq(number(draw),1))
        return Unit{}
    case _: IO.die(Unit,2,"invalid far arguments")

def ready(result:Result<&2,&2,String,List<&2,WM.Binding>>,state:W.State,assets:R.Assets,args:List<&2,String>) -> IO(Unit):
  match result:
    case Fail{error}: IO.die(Unit,1,"binding failed:" ++ error)
    case Done{+bindings}:
      match args:
        case Nil{}: basic(Owned{state,assets},bindings)
        case "far" <> fields: far(fields,state,assets,bindings)
        case _: IO.die(Unit,2,"invalid world mesh command")
def prepared(pair:W.State & Result<&2,&2,String,List<&2,WM.Binding>>,assets:R.Assets,args:List<&2,String>) -> IO(Unit):
  (state,result) = pair
  ready(result,state,assets,args)
def initial(args:List<&2,String>,engine:G.Engine) -> W.State & Result<&2,&2,String,Unit>:
  match args:
    case "far" <> fields: W.new(engine)
    case _: W.fixture(engine)
def loaded(result:Result<&2,&1,BR.Error,BR.Loaded>,+args:List<&2,String>) -> IO(Unit):
  match result:
    case Fail{BR.Error{code,resource,message}}: IO.die(Unit,1,"resource load:" ++ code ++ ":" ++ resource ++ ":" ++ message)
    case Done{BR.Loaded{assets,catalog}}:
      do IO<Unit>:
        engine : G.Engine <- G.load()
        state : W.State <- loaded_fixture(initial(args,engine))
        prepared(state_bindings(state,catalog),assets,args)

def required_env(result:Result<&1,&1,U32 & String,String>) -> IO(String):
  match result:
    case Fail{error}: IO.die(String,2,"MC_WORLD_MESH_JAR is required")
    case Done{path}: IO.pure(String,path)

def raw(value:U32) -> F32:
  match value:
    case U32{word}: F32{word}
def synthetic(texture:U32,index:U32,layer:K.Layer,force:Bool,animated:Bool,emission:U32,x:F32,u:F32,+shade:F32) -> K.Baked:
  K.Baked{M.Vertex{M.Vec3{x,1.0,0.0},M.UV{u,0.0}},M.Vertex{M.Vec3{1.0,0.0,0.0},M.UV{0.0,1.0}},
    M.Vertex{M.Vec3{0.0,0.0,0.0},M.UV{1.0,1.0}},M.Vertex{M.Vec3{0.0,1.0,0.0},M.UV{1.0,0.0}},
    B.North{},Some{B.North{}},"synthetic",texture,index,emission,None{},layer,force,animated,shade,shade}
def normal() -> K.Baked:
  synthetic(0,4294967295,K.Solid{},False{},False{},0,1.0,0.0,0.6)
def nether(value:K.Baked,shade:F32) -> K.Baked:
  K.Baked{a,b,c,d,direction,cf,sprite,texture,index,emission,override,layer,force,animated,ds,ns} = value
  K.Baked{a,b,c,d,direction,cf,sprite,texture,index,emission,override,layer,force,animated,ds,shade}
def snapshot(blocks:List<&2,R.Block>) -> R.Snapshot:
  R.Snapshot{1n,47n,blocks,R.Camera{0.0,0.0,0.0,0.0,0.2}}
def one() -> R.Snapshot:
  snapshot([R.Block{0.0,0.0,0.0,1,4294967295}])
def fixture_binding(value:K.Baked,appearance:WM.Appearance) -> List<&2,WM.Binding>:
  [WM.Binding{1,[value],appearance}]
def outcome(result:Result<&2,&2,WM.Error,M.Scene>) -> String:
  match result:
    case Fail{WM.Error{code,state}}: code
    case Done{scene}: "Done"
def error_case(id:String,snapshot:R.Snapshot,bindings:List<&2,WM.Binding>,textures:U32,frame:WM.Frame,limits:WM.Limits) -> IO(Unit):
  IO.print("error|" ++ id ++ "|" ++ outcome(WM.produce(snapshot,bindings,textures,frame,limits)))
def fixture_quad(result:Result<&2,&2,WM.Error,M.Scene>,id:String) -> IO(Unit):
  match result:
    case Done{M.Scene{camera,head <> Nil{},settings}}: IO.print("fixture|" ++ id ++ "|" ++ quad_text(head))
    case _: IO.die(Unit,1,"fixture must produce exactly one quad")
def errors() -> IO(Unit):
  +bindings = fixture_binding(normal(),WM.appearance())
  +snap = one()
  +frame = WM.frame(32,24)
  +limits = WM.defaults()
  do IO<Unit>:
    error_case("valid",snap,bindings,1,frame,limits)
    error_case("empty",snapshot([]),[],1,frame,limits)
    error_case("missing-state",snapshot([R.Block{0.0,0.0,0.0,2,0}]),bindings,1,frame,limits)
    error_case("duplicate-state",snap,[WM.Binding{1,[normal()],WM.appearance()},WM.Binding{1,[normal()],WM.appearance()}],1,frame,limits)
    error_case("binding-limit",snap,bindings,1,frame,WM.Limits{4096,0,4096,64,256})
    error_case("source-limit",snap,bindings,1,frame,WM.Limits{4096,1024,0,64,256})
    error_case("block-limit",snap,bindings,1,frame,WM.Limits{0,1024,4096,64,256})
    error_case("quad-limit",snapshot([R.Block{0.0,0.0,0.0,1,0},R.Block{1.0,0.0,0.0,1,0}]),bindings,1,frame,WM.Limits{4096,1024,1,64,256})
    error_case("translucent-limit",snap,fixture_binding(synthetic(0,4294967295,K.Translucent{},False{},False{},0,1.0,0.0,0.6),WM.appearance()),1,frame,WM.Limits{4096,1024,4096,0,256})
    error_case("unsupported-limits",snap,bindings,1,frame,WM.Limits{4096,1024,4097,64,256})
    error_case("relative-camera",R.Snapshot{1n,47n,[],R.Camera{1.0,0.0,0.0,0.0,0.2}},bindings,1,frame,limits)
    error_case("nan-camera",R.Snapshot{1n,47n,[],R.Camera{0.0,0.0,0.0,0.0,raw(2143289344)}},bindings,1,frame,limits)
    error_case("dimensions-low",snap,bindings,1,WM.frame(3,24),limits)
    error_case("dimensions-high",snap,bindings,1,WM.frame(32,1025),limits)
    error_case("infinite-settings",snap,bindings,1,WM.Frame{32,24,M.Settings{0.0001,raw(2139095040),0.7,4294967295}},limits)
    error_case("texture-count",snap,bindings,0,frame,limits)
    error_case("texture-index",snap,fixture_binding(synthetic(1,4294967295,K.Solid{},False{},False{},0,1.0,0.0,0.6),WM.appearance()),1,frame,limits)
    error_case("nan-source",snap,fixture_binding(synthetic(0,4294967295,K.Solid{},False{},False{},0,raw(2143289344),0.0,0.6),WM.appearance()),1,frame,limits)
    error_case("nan-uv",snap,fixture_binding(synthetic(0,4294967295,K.Solid{},False{},False{},0,1.0,raw(2143289344),0.6),WM.appearance()),1,frame,limits)
    error_case("nan-shade",snap,fixture_binding(synthetic(0,4294967295,K.Solid{},False{},False{},0,1.0,0.0,raw(2143289344)),WM.appearance()),1,frame,limits)
    error_case("light-alpha",snap,fixture_binding(normal(),WM.Appearance{[],16777215,M.Clamp{},M.Back{},False{},128}),1,frame,limits)
    error_case("cutout-threshold",snap,fixture_binding(normal(),WM.Appearance{[],4294967295,M.Clamp{},M.Back{},False{},256}),1,frame,limits)
    error_case("duplicate-tint",snap,fixture_binding(normal(),WM.Appearance{[WM.Tint{0,1},WM.Tint{0,2}],4294967295,M.Clamp{},M.Back{},False{},128}),1,frame,limits)
    error_case("untinted-map",snap,fixture_binding(normal(),WM.Appearance{[WM.Tint{4294967295,1}],4294967295,M.Clamp{},M.Back{},False{},128}),1,frame,limits)
    error_case("tint-limit",snap,fixture_binding(normal(),WM.Appearance{[WM.Tint{0,1}],4294967295,M.Clamp{},M.Back{},False{},128}),1,frame,WM.Limits{4096,1024,4096,64,0})
    error_case("missing-tint",snap,fixture_binding(synthetic(0,3,K.Solid{},False{},False{},0,1.0,0.0,0.6),WM.appearance()),1,frame,limits)
    error_case("mapped-tint",snap,fixture_binding(synthetic(0,3,K.Solid{},False{},False{},0,1.0,0.0,0.6),WM.Appearance{[WM.Tint{3,4279312947}],4294967295,M.Repeat{},M.NoCull{},True{},128}),1,frame,limits)
    error_case("animation",snap,fixture_binding(synthetic(0,4294967295,K.Solid{},False{},True{},0,1.0,0.0,0.6),WM.appearance()),1,frame,limits)
    error_case("force-layer",snap,fixture_binding(synthetic(0,4294967295,K.Solid{},True{},False{},0,1.0,0.0,0.6),WM.appearance()),1,frame,limits)
    error_case("emission-range",snap,fixture_binding(synthetic(0,4294967295,K.Solid{},False{},False{},16,1.0,0.0,0.6),WM.appearance()),1,frame,limits)
    error_case("nan-origin",snapshot([R.Block{raw(2143289344),0.0,0.0,1,0}]),bindings,1,frame,limits)
    error_case("translated-bound",snapshot([R.Block{4096.0,0.0,0.0,1,0}]),bindings,1,frame,limits)
    fixture_quad(WM.produce(snap,fixture_binding(nether(synthetic(0,3,K.Solid{},False{},False{},0,1.0,0.0,0.6),0.9),
      WM.Appearance{[WM.Tint{3,4279312947}],4294967295,M.Repeat{},M.NoCull{},True{},128}),1,frame,limits),"mapped-tint")

def run(args:List<&2,String>) -> IO(Unit):
  match args:
    case "errors" <> Nil{}: errors()
    case args:
      do IO<Unit>:
        env : Result<&1,&1,U32 & String,String> <- IO.get_env("MC_WORLD_MESH_JAR")
        path : String <- required_env(env)
        resources : Result<&2,&1,BR.Error,BR.Loaded> <- BR.load(path,
          ["minecraft:block/stone","minecraft:block/dirt","minecraft:block/oak_planks"],
          BR.StaticNormalized{Map.set(&2,K.Layer,Map.set(&2,K.Layer,Map.set(&2,K.Layer,MTip{},"minecraft:block/stone",K.Solid{}),"minecraft:block/dirt",K.Solid{}),"minecraft:block/oak_planks",K.Solid{})},BR.defaults())
        loaded(resources,args)
def shared_args(args:List<String>) -> List<&2,String>:
  match args:
    case Nil{}: []
    case head <> tail: head <> shared_args(tail)
def arguments(args:List<String>) -> IO(Unit):
  match args:
    case Nil{}: run([])
    case program <> tail: run(shared_args(tail))
def main() -> IO(Unit):
  IO.bind(List<String>,Unit,IO.args(),arguments)
