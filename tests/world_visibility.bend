import Base
import ../src/world_mesh.bend as WM
import ../src/client_world.bend as W
import ../src/client_render.bend as R
import ../src/mesh_render.bend as M
import ../src/block_bake.bend as K
import ../src/block_model.bend as B
import ../src/game.bend as G
import ../src/f64.bend as F
import ../src/movement.bend as MV
import ../src/png.bend as P
import ../src/core.bend as C
import ../src/registry.bend as Reg
import ../src/schedule.bend as Q

import ../src/world_visibility.bend as V
import ../src/json.bend as J
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
        R.write_ppm("build/world-visibility-" ++ id ++ ".ppm",image,32,24)
        IO.print("frame|" ++ id ++ "|32|24|build/world-visibility-" ++ id ++ ".ppm")
def render_pair(pair:R.Assets & Result<&2,&2,M.Error,Image>,id:String) -> IO(R.Assets):
  (assets,result) = pair
  do IO<R.Assets>:
    drawn(result,id)
    return assets
def scene_draw(draw:Bool,scene:M.Scene,assets:R.Assets,id:String) -> IO(R.Assets):
  match draw:
    case False{}: IO.pure(R.Assets,assets)
    case True{}: render_pair(M.render_flat(scene,assets,32,24),id)

type Inputs is Data:
  Inputs{library:B.Library,textures:List<&2,R.Texture>}
type Fixture is Data:
  Fixture{region:W.Bounds,body:MV.Vec3,mutations:List<&2,C.Mutation>}

def visibility_text(values:List<&2,V.Visibility>) -> String:
  match values:
    case Nil{}: ""
    case V.Visibility{W.Cell{x,y,z,boundary},state,visible} <> tail:
      U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z) ++ "," ++ U32.show(state) ++ "," ++ U32.show(visible) ++ ";" ++ visibility_text(tail)
def scene_report(result:Result<&2,&2,V.Error,M.Scene>,assets:R.Assets,+id:String,draw:Bool) -> IO(R.Assets):
  match result:
    case Fail{V.Error{code,cell,state,detail}}: IO.die(R.Assets,1,"visibility producer:" ++ code ++ ":" ++ detail)
    case Done{+scene}:
      M.Scene{camera,quads,settings} = scene
      do IO<R.Assets>:
        quads_report(quads,id,0)
        scene_draw(draw,scene,assets,id)
def sampled(result:W.State & Result<&2,&2,V.Error,V.Sample>,assets:R.Assets,+bindings:List<&2,WM.Binding>,+id:String,draw:Bool) -> IO(Owned):
  (state,status) = result
  match status:
    case Fail{V.Error{code,cell,current,detail}}: IO.die(Owned,1,"visibility sample:" ++ code ++ ":" ++ detail)
    case Done{+value}:
      V.Sample{snapshot,raw,masks,origin,palette,reads} = value
      do IO<Owned>:
        IO.print("snapshot|" ++ id ++ "|" ++ snapshot_text(snapshot))
        IO.print("mask|" ++ id ++ "|" ++ U32.show(reads) ++ "|" ++ visibility_text(masks))
        assets : R.Assets <- scene_report(V.produce(value,bindings,3,WM.frame(32,24),WM.defaults()),assets,id,draw)
        return Owned{state,assets}
def sample(owned:Owned,bindings:List<&2,WM.Binding>,id:String,draw:Bool) -> IO(Owned):
  Owned{state,assets} = owned
  sampled(V.sample(state,V.defaults()),assets,bindings,id,draw)
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
def edit(owned:Owned) -> Owned:
  Owned{state,assets} = owned
  Owned{edit_state(state),assets}
def uncached(owned:Owned) -> Owned:
  Owned{state,assets} = owned
  Owned{W.invalidate_cache(state),assets}
def basic(owned:Owned,+bindings:List<&2,WM.Binding>) -> IO(Unit):
  do IO<Unit>:
    owned : Owned <- sample(owned,bindings,"initial",True{})
    owned : Owned <- sample(owned,bindings,"cached",True{})
    owned : Owned <- sample(edit(owned),bindings,"raw-edit",True{})
    owned : Owned <- sample(uncached(owned),bindings,"uncached",True{})
    return Unit{}
def halo_write_result(result:C.World & Result<&2,&2,C.Error,Unit>,registry:Reg.Registry,view:W.View) -> W.State:
  (world,status) = result
  W.attach(G.Engine{world,registry},view)
def halo_edit(owned:Owned) -> Owned:
  Owned{W.State{G.Engine{world,registry},body,yaw,pitch,+palette,+region,cache},assets} = owned
  match palette region:
    case None{} _: Owned{W.State{G.Engine{world,registry},body,yaw,pitch,palette,region,cache},assets}
    case Some{W.Palette{air,stone,dirt,planks}} W.Bounds{x,y,z,w,h,d}:
      Owned{halo_write_result(C.write_block(world,W.position(V.neighbor(W.Cell{x,y,z,0},B.Down{})),air),registry,
        W.View{body,yaw,pitch,palette,region,cache}),assets}
def halo_basic(owned:Owned,+bindings:List<&2,WM.Binding>) -> IO(Unit):
  do IO<Unit>:
    owned : Owned <- sample(owned,bindings,"halo-initial",True{})
    owned : Owned <- sample(owned,bindings,"halo-cached",True{})
    owned : Owned <- sample(halo_edit(owned),bindings,"halo-edit",True{})
    owned : Owned <- sample(owned,bindings,"halo-recached",True{})
    return Unit{}

def model_error(-A:Data,result:Result<&2,&2,B.Error,A>) -> Result<&2,&2,String,A>:
  match result:
    case Fail{B.Error{code,path}}: Fail{code ++ ":" ++ path}
    case Done{value}: Done{value}
def bake_error(result:Result<&2,&2,K.Error,List<&2,K.Baked>>) -> Result<&2,&2,String,List<&2,K.Baked>>:
  match result:
    case Done{values}: Done{values}
    case Fail{K.Unsupported{code}}: Fail{code}
    case Fail{K.Invalid{code}}: Fail{code}
    case Fail{K.MissingMaterial{name}}: Fail{name}
def context() -> K.Context:
  K.Context{Map.set(&2,K.Sprite,Map.set(&2,K.Sprite,Map.set(&2,K.Sprite,MTip{},
    "minecraft:block/dirt",K.Sprite{0,0.0,0.0,1.0,1.0,K.Solid{},False{}}),
    "minecraft:block/oak_planks",K.Sprite{1,0.0,0.0,1.0,1.0,K.Solid{},False{}}),
    "minecraft:block/stone",K.Sprite{2,0.0,0.0,1.0,1.0,K.Solid{},False{}}),None{}}
def bake(library:B.Library,name:String) -> Result<&2,&2,String,List<&2,K.Baked>>:
  do Result<&2,&2,String,List<&2,K.Baked>>:
    model : B.Resolved <- model_error(B.Resolved,B.resolve(library,name))
    bake_error(K.bake(model,K.State{0,0,0,False{}},context()))
def bindings(+library:B.Library,palette:Maybe<&2,W.Palette>) -> Result<&2,&2,String,List<&2,WM.Binding>>:
  match palette:
    case None{}: Fail{"palette"}
    case Some{W.Palette{air,stone,dirt,planks}}:
      do Result<&2,&2,String,List<&2,WM.Binding>>:
        stone_quads : List<&2,K.Baked> <- bake(library,"minecraft:block/stone")
        dirt_quads : List<&2,K.Baked> <- bake(library,"minecraft:block/dirt")
        planks_quads : List<&2,K.Baked> <- bake(library,"minecraft:block/oak_planks")
        Done{[WM.Binding{stone,stone_quads,WM.appearance()},WM.Binding{dirt,dirt_quads,WM.appearance()},WM.Binding{planks,planks_quads,WM.appearance()}]}

def u32_found(value:Maybe<&2,U32>) -> Result<&2,&2,B.Error,U32>:
  match value:
    case Some{word}: Done{word}
    case None{}: B.fail(U32,"FixtureU32","fixture")
def u32(value:J.Value) -> Result<&2,&2,B.Error,U32>:
  u32_found(J.as_u32(value))
def numbers(values:List<&2,J.Value>) -> Result<&2,&2,B.Error,List<&2,U32>>:
  match values:
    case Nil{}: Done{[]}
    case head <> tail:
      do Result<&2,&2,B.Error,List<&2,U32>>:
        value : U32 <- u32(head)
        rest : List<&2,U32> <- numbers(tail)
        Done{value <> rest}
def number_array(value:J.Value) -> Result<&2,&2,B.Error,List<&2,U32>>:
  match value:
    case J.JArray{values}: numbers(values)
    case _: B.fail(List<&2,U32>,"FixtureArray","fixture")
def texture(value:J.Value) -> Result<&2,&2,B.Error,R.Texture>:
  do Result<&2,&2,B.Error,R.Texture>:
    +obj : J.Value <- B.object(value,"texture")
    width : U32 <- B.optional_int(J.member(obj,"width"),0,"width")
    height : U32 <- B.optional_int(J.member(obj,"height"),0,"height")
    found : J.Value <- B.required(J.member(obj,"pixels"),"pixels")
    pixels : List<&2,U32> <- number_array(found)
    Done{R.texture(P.Decoded{width,height,pixels})}
def textures(value:J.Value) -> Result<&2,&2,B.Error,List<&2,R.Texture>>:
  match value:
    case J.JArray{values}:
      List.foldr(&2,J.Value,Result<&2,&2,B.Error,List<&2,R.Texture>>,v => rest =>
        do Result<&2,&2,B.Error,List<&2,R.Texture>>:
          t : R.Texture <- texture(v)
          ts : List<&2,R.Texture> <- rest
          Done{t <> ts},values,Done{[]})
    case _: B.fail(List<&2,R.Texture>,"TextureArray","textures")
def inputs(+value:J.Value) -> Result<&2,&2,B.Error,Inputs>:
  do Result<&2,&2,B.Error,Inputs>:
    models : J.Value <- B.required(J.member(value,"models"),"models")
    library : B.Library <- B.decode_library(models,B.empty_model())
    texture_values : J.Value <- B.required(J.member(value,"textures"),"textures")
    textures : List<&2,R.Texture> <- textures(texture_values)
    Done{Inputs{library,textures}}

def coordinate3(values:List<&2,U32>) -> Result<&2,&2,B.Error,W.Cell>:
  match values:
    case x <> y <> z <> Nil{}: Done{W.Cell{x,y,z,0}}
    case _: B.fail(W.Cell,"Coordinate3","fixture")
def section(value:J.Value,air:U32) -> Result<&2,&2,B.Error,C.Mutation>:
  do Result<&2,&2,B.Error,C.Mutation>:
    values : List<&2,U32> <- number_array(value)
    cell : W.Cell <- coordinate3(values)
    Done{C.SectionCreate{W.position(cell),air}}
def state_name(name:String,palette:W.Palette) -> Result<&2,&2,B.Error,U32>:
  match name palette:
    case "minecraft:air" W.Palette{air,stone,dirt,planks}: Done{air}
    case "minecraft:stone" W.Palette{air,stone,dirt,planks}: Done{stone}
    case "minecraft:dirt" W.Palette{air,stone,dirt,planks}: Done{dirt}
    case "minecraft:oak_planks" W.Palette{air,stone,dirt,planks}: Done{planks}
    case _ _: B.fail(U32,"StateName","fixture")
def cell(value:J.Value,palette:W.Palette) -> Result<&2,&2,B.Error,C.Mutation>:
  match value:
    case J.JArray{[x,y,z,name]}:
      do Result<&2,&2,B.Error,C.Mutation>:
        px : U32 <- u32(x)
        py : U32 <- u32(y)
        pz : U32 <- u32(z)
        text : String <- B.strict_string(name,"state")
        state : U32 <- state_name(text,palette)
        Done{C.BlockSet{C.Position{"minecraft:overworld",px,py,pz},state}}
    case _: B.fail(C.Mutation,"Cell4","fixture")
def mutation(sections:Bool,value:J.Value,palette:W.Palette) -> Result<&2,&2,B.Error,C.Mutation>:
  match sections:
    case True{}:
      W.Palette{air,stone,dirt,planks} = palette
      section(value,air)
    case False{}: cell(value,palette)
def mutations(values:List<&2,J.Value>,+palette:W.Palette,+sections:Bool) -> Result<&2,&2,B.Error,List<&2,C.Mutation>>:
  match values:
    case Nil{}: Done{[]}
    case value <> rest:
      do Result<&2,&2,B.Error,List<&2,C.Mutation>>:
        head : C.Mutation <- mutation(sections,value,palette)
        tail : List<&2,C.Mutation> <- mutations(rest,palette,sections)
        Done{head <> tail}
def mutation_array(value:J.Value,palette:W.Palette,sections:Bool) -> Result<&2,&2,B.Error,List<&2,C.Mutation>>:
  match value:
    case J.JArray{values}: mutations(values,palette,sections)
    case _: B.fail(List<&2,C.Mutation>,"MutationArray","fixture")
def bounds(values:List<&2,U32>) -> Result<&2,&2,B.Error,W.Bounds>:
  match values:
    case x <> y <> z <> w <> h <> d <> Nil{}: Done{W.Bounds{x,y,z,w,h,d}}
    case _: B.fail(W.Bounds,"Bounds6","fixture")
def position64(values:List<&2,U32>) -> Result<&2,&2,B.Error,MV.Vec3>:
  match values:
    case xh <> xl <> yh <> yl <> zh <> zl <> Nil{}: Done{MV.Vec3{F.F64{xh,xl},F.F64{yh,yl},F.F64{zh,zl}}}
    case _: B.fail(MV.Vec3,"Position6","fixture")
def fixture(+value:J.Value,+palette:W.Palette) -> Result<&2,&2,B.Error,Fixture>:
  do Result<&2,&2,B.Error,Fixture>:
    bounds_json : J.Value <- B.required(J.member(value,"bounds"),"bounds")
    bounds_words : List<&2,U32> <- number_array(bounds_json)
    region : W.Bounds <- bounds(bounds_words)
    position_json : J.Value <- B.required(J.member(value,"body_words"),"body_words")
    position_words : List<&2,U32> <- number_array(position_json)
    body : MV.Vec3 <- position64(position_words)
    sections_json : J.Value <- B.required(J.member(value,"sections"),"sections")
    sections : List<&2,C.Mutation> <- mutation_array(sections_json,palette,True{})
    cells_json : J.Value <- B.required(J.member(value,"cells"),"cells")
    cells : List<&2,C.Mutation> <- mutation_array(cells_json,palette,False{})
    Done{Fixture{region,body,List.append(&2,C.Mutation,sections,cells)}}
def fixture_result(result:C.World & Result<&2,&2,String,Unit>,registry:Reg.Registry,body:MV.Vec3,palette:Maybe<&2,W.Palette>,region:W.Bounds) -> W.State & Result<&2,&2,String,Unit>:
  (world,status) = result
  (W.State{G.Engine{world,registry},MV.Body.new(body,0.6,1.8,MV.Vec3.zero(),True{}),0.0,0.2,palette,region,None{}},status)
def fixture_ready(result:Result<&2,&2,B.Error,Fixture>,state:W.State) -> IO(W.State):
  match result:
    case Fail{B.Error{code,path}}: IO.die(W.State,1,"fixture parse:" ++ code ++ ":" ++ path)
    case Done{Fixture{region,body,mutations}}:
      W.State{G.Engine{world,registry},old,yaw,pitch,palette,oldregion,cache} = state
      loaded_fixture(fixture_result(W.fixture_enqueue(mutations,0n,world,Done{Unit{}}),registry,body,palette,region))
def custom_initialized(result:W.State & Result<&2,&2,String,Unit>,value:J.Value) -> IO(W.State):
  (state,status) = result
  W.State{engine,body,yaw,pitch,+palette,region,cache} = state
  match palette:
    case None{}: IO.die(W.State,1,"custom palette unavailable")
    case Some{actual}: fixture_ready(fixture(value,actual),W.State{engine,body,yaw,pitch,palette,region,cache})
def initialize(value:Maybe<&2,J.Value>,engine:G.Engine) -> IO(W.State):
  match value:
    case None{}: loaded_fixture(W.fixture(engine))
    case Some{obj}: custom_initialized(W.new(engine),obj)


def error_code(result:Result<&2,&2,V.Error,M.Scene>) -> String:
  match result:
    case Fail{V.Error{code,cell,state,detail}}: code
    case Done{scene}: "Done"
def pure_report(+id:String,result:Result<&2,&2,V.Error,M.Scene>) -> IO(Unit):
  IO.print("error|" ++ id ++ "|" ++ error_code(result))
def first_raw(values:List<&2,W.RawBlock>) -> W.RawBlock:
  match values:
    case head <> tail: head
    case Nil{}: W.RawBlock{V.empty_cell(),0,0}
def replace_mask(value:V.Sample,masks:List<&2,V.Visibility>) -> V.Sample:
  V.Sample{snapshot,raw,old,origin,palette,reads} = value
  V.Sample{snapshot,raw,masks,origin,palette,reads}
def replace_first_mask(values:List<&2,V.Visibility>,mask:V.Visibility) -> List<&2,V.Visibility>:
  match values:
    case Nil{}: [mask]
    case head <> tail: mask <> tail
def replace_first_raw(values:List<&2,W.RawBlock>,raw:W.RawBlock) -> List<&2,W.RawBlock>:
  match values:
    case Nil{}: [raw]
    case head <> tail: raw <> tail
def sample_palette(value:V.Sample,palette:W.Palette) -> V.Sample:
  V.Sample{snapshot,raw,masks,origin,old,reads} = value
  V.Sample{snapshot,raw,masks,origin,palette,reads}
def sample_raw(value:V.Sample,raw:List<&2,W.RawBlock>) -> V.Sample:
  V.Sample{snapshot,old,masks,origin,palette,reads} = value
  V.Sample{snapshot,raw,masks,origin,palette,reads}
def sample_reads(value:V.Sample,reads:U32) -> V.Sample:
  V.Sample{snapshot,raw,masks,origin,palette,old} = value
  V.Sample{snapshot,raw,masks,origin,palette,reads}
def sample_snapshot(value:V.Sample,snapshot:R.Snapshot) -> V.Sample:
  V.Sample{old,raw,masks,origin,palette,reads} = value
  V.Sample{snapshot,raw,masks,origin,palette,reads}
def sample_origin(value:V.Sample,origin:MV.Vec3) -> V.Sample:
  V.Sample{snapshot,raw,masks,old,palette,reads} = value
  V.Sample{snapshot,raw,masks,origin,palette,reads}
def bad_snapshot(value:R.Snapshot) -> R.Snapshot:
  match value:
    case R.Snapshot{tick,revision,R.Block{x,y,z,state,material} <> rest,camera}:
      R.Snapshot{tick,revision,R.Block{F32.add(x,1.0),y,z,state,material} <> rest,camera}
    case other: other
def group(value:K.Baked,cf:Maybe<&2,B.Direction>) -> K.Baked:
  K.Baked{a,b,c,d,direction,old,sprite,texture,index,emission,override,layer,force,animated,ds,ns} = value
  K.Baked{a,b,c,d,direction,cf,sprite,texture,index,emission,override,layer,force,animated,ds,ns}
def first_binding(values:List<&2,WM.Binding>) -> WM.Binding:
  match values:
    case head <> tail: head
    case Nil{}: WM.Binding{0,[],WM.appearance()}
def first_baked(values:List<&2,K.Baked>) -> Maybe<&2,K.Baked>:
  match values:
    case head <> tail: Some{head}
    case Nil{}: None{}
def retained_report(result:Result<&2,&2,V.Error,M.Scene>,+id:String) -> IO(Unit):
  match result:
    case Fail{V.Error{code,cell,state,detail}}: IO.die(Unit,1,"retained:" ++ code)
    case Done{M.Scene{camera,quads,settings}}: quads_report(quads,id,0)
def group_cases(value:Maybe<&2,K.Baked>,+state:U32,+palette:W.Palette) -> IO(Unit):
  match value:
    case None{}: IO.die(Unit,1,"no actual baked face")
    case Some{+baked}:
      +raw = {W.RawBlock{V.empty_cell(),state,0} : W.RawBlock}
      +snapshot = {R.Snapshot{1n,1n,[R.Block{0.0,0.0,0.0,state,0}],R.Camera{0.0,0.0,0.0,0.0,0.2}} : R.Snapshot}
      +origin = {MV.Vec3{F.F64{0,0},F.F64{0,0},F.F64{0,0}} : MV.Vec3}
      +base = {V.Sample{snapshot,[raw],[V.Visibility{V.empty_cell(),state,0}],origin,palette,6} : V.Sample}
      +appearance = {WM.Appearance{[],4294967295,M.Repeat{},M.NoCull{},True{},128} : WM.Appearance}
      do IO<Unit>:
        retained_report(V.produce(base,[WM.Binding{state,[group(baked,None{})],appearance}],3,WM.frame(32,24),WM.defaults()),"ungrouped-hidden-neighbors")
        retained_report(V.produce(replace_mask(base,[V.Visibility{V.empty_cell(),state,32}]),[WM.Binding{state,[group(baked,Some{B.East{}})],appearance}],3,WM.frame(32,24),WM.defaults()),"declared-east-normal-down")
        retained_report(V.produce(replace_mask(base,[V.Visibility{V.empty_cell(),state,1}]),[WM.Binding{state,[group(baked,Some{B.East{}})],appearance}],3,WM.frame(32,24),WM.defaults()),"declared-east-hidden")
def pure_cases_ready(head:W.RawBlock,binding:WM.Binding,+value:V.Sample,+bindings:List<&2,WM.Binding>) -> IO(Unit):
  match head binding value:
    case W.RawBlock{+cell,+state,+material} WM.Binding{binding_state,+baked,appearance} V.Sample{+snapshot,+raw,+masks,origin,W.Palette{+air,+stone,+dirt,+planks},reads}:
      +palette = {W.Palette{air,stone,dirt,planks} : W.Palette}
      +duplicate = {W.RawBlock{cell,state,material} <> raw : List<&2,W.RawBlock>}
      +same = {V.Visibility{cell,state,63} : V.Visibility}
      do IO<Unit>:
        pure_report("valid",V.produce(value,bindings,3,WM.frame(32,24),WM.defaults()))
        pure_report("missing-masks",V.produce(replace_mask(value,[]),bindings,3,WM.frame(32,24),WM.defaults()))
        pure_report("extra-mask",V.produce(replace_mask(value,same <> masks),bindings,3,WM.frame(32,24),WM.defaults()))
        pure_report("mask-range",V.produce(replace_mask(value,replace_first_mask(masks,V.Visibility{cell,state,64})),bindings,3,WM.frame(32,24),WM.defaults()))
        pure_report("mask-cell",V.produce(replace_mask(value,replace_first_mask(masks,V.Visibility{V.neighbor(cell,B.East{}),state,63})),bindings,3,WM.frame(32,24),WM.defaults()))
        pure_report("mask-state",V.produce(replace_mask(value,replace_first_mask(masks,V.Visibility{cell,air,63})),bindings,3,WM.frame(32,24),WM.defaults()))
        pure_report("duplicate-raw",V.produce(sample_raw(value,duplicate),bindings,3,WM.frame(32,24),WM.defaults()))
        pure_report("raw-material",V.produce(sample_raw(value,replace_first_raw(raw,W.RawBlock{cell,state,99})),bindings,3,WM.frame(32,24),WM.defaults()))
        pure_report("palette-alias",V.produce(sample_palette(value,W.Palette{air,air,dirt,planks}),bindings,3,WM.frame(32,24),WM.defaults()))
        pure_report("relative-coordinate",V.produce(sample_snapshot(value,bad_snapshot(snapshot)),bindings,3,WM.frame(32,24),WM.defaults()))
        pure_report("read-count",V.produce(sample_reads(value,0),bindings,3,WM.frame(32,24),WM.defaults()))
        pure_report("invalid-origin",V.produce(sample_origin(value,MV.Vec3{F.F64{2146435072,0},F.F64{0,0},F.F64{0,0}}),bindings,3,WM.frame(32,24),WM.defaults()))
        pure_report("missing-binding",V.produce(value,[],3,WM.frame(32,24),WM.defaults()))
        pure_report("pre-filter-budget",V.produce(value,bindings,3,WM.frame(32,24),WM.Limits{4096,1024,108,64,256}))
        group_cases(first_baked(baked),stone,palette)

def pure_cases(+value:V.Sample,+bindings:List<&2,WM.Binding>) -> IO(Unit):
  V.Sample{snapshot,raw,masks,origin,palette,reads} = value
  pure_cases_ready(first_raw(raw),first_binding(bindings),value,bindings)

def owner_read(result:C.World & Result<&2,&2,C.Error,U32>,registry:Reg.Registry,view:W.View,+id:String,+tick:Nat,+revision:Nat) -> IO(W.State):
  (world,status) = result
  match status:
    case Fail{error}: IO.die(W.State,1,"owner read failed")
    case Done{state}:
      do IO<W.State>:
        IO.print("owner|" ++ id ++ "|" ++ Nat.show(tick) ++ "," ++ Nat.show(revision) ++ "," ++ U32.show(state))
        return W.attach(G.Engine{world,registry},view)
def owner_clock(result:C.World & C.Clock,registry:Reg.Registry,view:W.View,id:String) -> IO(W.State):
  (world,C.Clock{tick,time,paused,daylight,revision,pending}) = result
  owner_read(C.read_block(world,C.Position{"minecraft:overworld",0,0,0}),registry,view,id,tick,revision)
def owner_probe(state:W.State,id:String) -> IO(W.State):
  W.State{G.Engine{world,registry},body,yaw,pitch,palette,region,cache} = state
  owner_clock(C.clock(world),registry,W.View{body,yaw,pitch,palette,region,cache},id)
def restore(state:W.State,view:W.View) -> W.State:
  W.State{engine,body,yaw,pitch,palette,region,cache} = state
  W.attach(engine,view)
def sample_error(result:W.State & Result<&2,&2,V.Error,V.Sample>,view:W.View,+id:String) -> IO(W.State):
  (state,status) = result
  match status:
    case Done{value}: IO.die(W.State,1,"unexpected sample success:" ++ id)
    case Fail{V.Error{code,cell,current,detail}}:
      do IO<W.State>:
        IO.print("error|" ++ id ++ "|" ++ code)
        owner_probe(restore(state,view),id)
def bad_palette(state:W.State) -> W.State:
  W.State{engine,body,yaw,pitch,palette,region,cache} = state
  match palette:
    case None{}: W.State{engine,body,yaw,pitch,None{},region,cache}
    case Some{W.Palette{air,stone,dirt,planks}}: W.State{engine,body,yaw,pitch,Some{W.Palette{stone,air,dirt,planks}},region,cache}
def no_palette(state:W.State) -> W.State:
  W.State{engine,body,yaw,pitch,palette,region,cache} = state
  W.State{engine,body,yaw,pitch,None{},region,cache}
def bad_region(state:W.State) -> W.State:
  W.State{engine,body,yaw,pitch,palette,region,cache} = state
  W.State{engine,body,yaw,pitch,palette,W.Bounds{0,0,0,0,1,1},cache}
def cached_cells(+head:W.RawBlock,+raw:List<&2,W.RawBlock>,duplicate:Bool) -> List<&2,W.RawBlock>:
  W.RawBlock{cell,state,material} = head
  W.choose(List<&2,W.RawBlock>,head <> raw,[W.RawBlock{cell,state,99}],duplicate)
def bad_cache(state:W.State,+duplicate:Bool) -> W.State:
  W.State{engine,body,yaw,pitch,palette,region,cache} = state
  match cache:
    case None{}: W.State{engine,body,yaw,pitch,palette,region,cache}
    case Some{W.SnapshotCache{revision,bounds,colors,+raw}}:
      W.State{engine,body,yaw,pitch,palette,region,Some{W.SnapshotCache{revision,bounds,colors,cached_cells(first_raw(raw),raw,duplicate)}}}
def owned_cases(state:W.State,+view:W.View) -> IO(W.State):
  do IO<W.State>:
    state : W.State <- sample_error(V.sample(state,V.Limits{WM.defaults(),24577}),view,"unsupported-neighbor-limit")
    state : W.State <- sample_error(V.sample(state,V.Limits{WM.Limits{4097,1024,4096,64,256},24576}),view,"unsupported-mesh-limit")
    state : W.State <- sample_error(V.sample(state,V.Limits{WM.Limits{38,1024,4096,64,256},24576}),view,"block-limit")
    state : W.State <- sample_error(V.sample(state,V.Limits{WM.defaults(),233}),view,"neighbor-limit")
    state : W.State <- sample_error(V.sample(bad_region(state),V.defaults()),view,"invalid-region")
    state : W.State <- sample_error(V.sample(no_palette(state),V.defaults()),view,"no-palette")
    state : W.State <- sample_error(V.sample(bad_palette(state),V.defaults()),view,"palette-mismatch")
    state : W.State <- sample_error(V.sample(bad_cache(state,True{}),V.defaults()),view,"cached-duplicate")
    state : W.State <- sample_error(V.sample(bad_cache(state,False{}),V.defaults()),view,"cached-material")
    return state
def errors_ready(state:W.State,value:V.Sample,bindings:List<&2,WM.Binding>) -> IO(Unit):
  W.State{engine,+body,+yaw,+pitch,+palette,+region,+cache} = state
  +view = {W.View{body,yaw,pitch,palette,region,cache} : W.View}
  do IO<Unit>:
    pure_cases(value,bindings)
    state : W.State <- owned_cases(W.State{engine,body,yaw,pitch,palette,region,cache},view)
    return Unit{}
def errors_sampled(result:W.State & Result<&2,&2,V.Error,V.Sample>,bindings:List<&2,WM.Binding>) -> IO(Unit):
  (state,status) = result
  match status:
    case Fail{error}: IO.die(Unit,1,"initial error sample failed")
    case Done{value}: errors_ready(state,value,bindings)
def errors(state:W.State,bindings:List<&2,WM.Binding>) -> IO(Unit):
  errors_sampled(V.sample(state,V.defaults()),bindings)
def direct_sample_error(result:W.State & Result<&2,&2,V.Error,V.Sample>,+id:String) -> IO(Unit):
  (state,status) = result
  match status:
    case Done{value}: IO.die(Unit,1,"unexpected custom sample success")
    case Fail{V.Error{code,cell,current,detail}}:
      do IO<Unit>:
        IO.print("error|" ++ id ++ "|" ++ code)
        state : W.State <- owner_probe(state,id)
        return Unit{}
def unknown_halo(state:W.State) -> W.State:
  W.State{G.Engine{C.World{tick,time,paused,daylight,revision,+count,sections,pending,events},registry},body,yaw,pitch,+palette,region,cache} = state
  halo_write_result(C.write_block(C.World{tick,time,paused,daylight,revision,count,sections,pending,events},
    C.Position{"minecraft:overworld",0,4294967295,0},U32.sub(count,1)),registry,W.View{body,yaw,pitch,palette,W.Bounds{0,0,0,1,1,1},None{}})
def ready(result:Result<&2,&2,String,List<&2,WM.Binding>>,state:W.State,assets:R.Assets,args:List<&2,String>) -> IO(Unit):
  match result:
    case Fail{error}: IO.die(Unit,1,"binding:" ++ error)
    case Done{+bindings}:
      match args:
        case Nil{}: basic(Owned{state,assets},bindings)
        case "halo-edit" <> Nil{}: halo_basic(Owned{state,assets},bindings)
        case "errors" <> Nil{}: errors(state,bindings)
        case "sample-error" <> id <> Nil{}: direct_sample_error(V.sample(state,V.defaults()),id)
        case "unknown-halo" <> Nil{}: direct_sample_error(V.sample(unknown_halo(state),V.defaults()),"unknown-halo")
        case id <> Nil{}:
          do IO<Unit>:
            owned : Owned <- sample(Owned{state,assets},bindings,id,True{})
            return Unit{}
        case id <> draw <> Nil{}:
          do IO<Unit>:
            owned : Owned <- sample(Owned{state,assets},bindings,id,U32.is_eq(number(draw),1))
            return Unit{}
        case _: IO.die(Unit,2,"invalid visibility arguments")
def initialized(state:W.State,library:B.Library,textures:List<&2,R.Texture>,args:List<&2,String>) -> IO(Unit):
  W.State{engine,body,yaw,pitch,+palette,region,cache} = state
  ready(bindings(library,palette),W.State{engine,body,yaw,pitch,palette,region,cache},R.Assets{textures},args)
def prepared(result:Result<&2,&2,B.Error,Inputs>,+value:J.Value,args:List<&2,String>) -> IO(Unit):
  match result:
    case Fail{B.Error{code,path}}: IO.die(Unit,1,"inputs:" ++ code ++ ":" ++ path)
    case Done{Inputs{library,textures}}:
      do IO<Unit>:
        engine : G.Engine <- G.load()
        state : W.State <- initialize(J.member(value,"fixture"),engine)
        initialized(state,library,textures,args)
def parsed(result:Result<&2,&2,String,J.Value>,args:List<&2,String>) -> IO(Unit):
  match result:
    case Fail{error}: IO.die(Unit,1,"input JSON:" ++ error)
    case Done{+value}: prepared(inputs(value),value,args)
def shared_args(args:List<String>) -> List<&2,String>:
  match args:
    case Nil{}: []
    case head <> tail: head <> shared_args(tail)

def direction(index:U32) -> B.Direction:
  match index:
    case 0: B.Down{}
    case 1: B.Up{}
    case 2: B.North{}
    case 3: B.South{}
    case 4: B.West{}
    case _: B.East{}
def bool_text(value:Bool) -> String:
  match value:
    case True{}: "true"
    case False{}: "false"
def pair_text(result:Result<&2,&2,V.Error,Bool>) -> String:
  match result:
    case Fail{error}: "Fail"
    case Done{value}: bool_text(value)
def pairs(n:Nat,+index:U32) -> IO(Unit):
  match n:
    case 0n: IO.pure(Unit,Unit{})
    case 1n+rest:
      +current = U32.div(index,24)
      +adjacent = U32.mod(U32.div(index,6),4)
      +d = U32.mod(index,6)
      do IO<Unit>:
        IO.print("pair|" ++ U32.show(current) ++ "|" ++ U32.show(adjacent) ++ "|" ++ U32.show(d) ++ "|" ++
          pair_text(V.should_render_face(current,adjacent,W.Palette{0,1,2,3},V.empty_cell())))
        pairs(rest,U32.inc(index))
type NamedCell is Data:
  NamedCell{id:String,cell:W.Cell}
def mask_cell(+index:U32,+positive:U32,+negative:U32) -> W.Cell:
  W.Cell{W.choose(U32,negative,positive,U32.is_ne(U32.and(index,1),0)),
    W.choose(U32,negative,positive,U32.is_ne(U32.and(index,2),0)),
    W.choose(U32,negative,positive,U32.is_ne(U32.and(index,4),0)),0}
def test_positions(n:Nat,+index:U32) -> List<&2,NamedCell>:
  match n:
    case 0n: []
    case 1n+rest:
      NamedCell{"far-" ++ U32.show(index),mask_cell(index,30000000,4264967296)} <>
        NamedCell{"i32-boundary-" ++ U32.show(index),mask_cell(index,2147483647,2147483648)} <> test_positions(rest,U32.inc(index))
def neighbor_report(cell:W.Cell,id:String,index:U32) -> IO(Unit):
  W.Cell{x,y,z,boundary} = cell
  IO.print("neighbor|" ++ id ++ "|" ++ U32.show(index) ++ "|" ++ U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z))
def neighbors_directions(n:Nat,+index:U32,+id:String,+cell:W.Cell) -> IO(Unit):
  match n:
    case 0n: IO.pure(Unit,Unit{})
    case 1n+rest:
      do IO<Unit>:
        neighbor_report(V.neighbor(cell,direction(index)),id,index)
        neighbors_directions(rest,U32.inc(index),id,cell)
def neighbors(values:List<&2,NamedCell>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case NamedCell{id,cell} <> tail:
      do IO<Unit>:
        neighbors_directions(6n,0,id,cell)
        neighbors(tail)
def arguments(args:List<String>) -> IO(Unit):
  match args:
    case program <> "pairs" <> Nil{}: pairs(96n,0)
    case program <> "neighbors" <> Nil{}: neighbors(NamedCell{"origin",V.empty_cell()} <> test_positions(8n,0))
    case program <> input <> tail: parsed(J.parse_with(input,J.Limits{1048576n,64}),shared_args(tail))
    case _: IO.die(Unit,2,"source input JSON required")

# Separated native entries: original model baking is a separately verified
# native stage; these test-only readers never receive Java expected quads.
def raw_text(values:List<&2,W.RawBlock>) -> String:
  match values:
    case Nil{}: ""
    case W.RawBlock{W.Cell{x,y,z,boundary},state,material} <> tail:
      U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z) ++ "," ++ U32.show(boundary) ++ "," ++ U32.show(state) ++ "," ++ U32.show(material) ++ ";" ++ raw_text(tail)
def origin_text(value:MV.Vec3) -> String:
  MV.Vec3{F.F64{xh,xl},F.F64{yh,yl},F.F64{zh,zl}} = value
  U32.show(xh) ++ "," ++ U32.show(xl) ++ "," ++ U32.show(yh) ++ "," ++ U32.show(yl) ++ "," ++ U32.show(zh) ++ "," ++ U32.show(zl)
def palette_text(value:W.Palette) -> String:
  W.Palette{air,stone,dirt,planks} = value
  U32.show(air) ++ "," ++ U32.show(stone) ++ "," ++ U32.show(dirt) ++ "," ++ U32.show(planks)
def mask_data_text(values:List<&2,V.Visibility>) -> String:
  match values:
    case Nil{}: ""
    case V.Visibility{W.Cell{x,y,z,boundary},state,visible} <> tail:
      U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z) ++ "," ++ U32.show(boundary) ++ "," ++ U32.show(state) ++ "," ++ U32.show(visible) ++ ";" ++ mask_data_text(tail)
def sample_payload(+value:V.Sample,+id:String) -> IO(Unit):
  V.Sample{snapshot,raw,+masks,origin,palette,reads} = value
  do IO<Unit>:
    IO.print("snapshot|" ++ id ++ "|" ++ snapshot_text(snapshot))
    IO.print("mask|" ++ id ++ "|" ++ U32.show(reads) ++ "|" ++ visibility_text(masks))
    IO.print("maskdata|" ++ id ++ "|" ++ mask_data_text(masks))
    IO.print("sampledata|" ++ id ++ "|" ++ origin_text(origin) ++ "|" ++ palette_text(palette) ++ "|" ++ raw_text(raw))
def sampler_result(result:W.State & Result<&2,&2,V.Error,V.Sample>,id:String) -> IO(W.State):
  (state,status) = result
  match status:
    case Fail{V.Error{code,cell,current,detail}}: IO.die(W.State,1,"sampler:" ++ code ++ ":" ++ detail)
    case Done{value}:
      do IO<W.State>:
        sample_payload(value,id)
        return state
def sampler_sample(state:W.State,id:String) -> IO(W.State):
  sampler_result(V.sample(state,V.defaults()),id)
def sampler_basic(state:W.State) -> IO(Unit):
  do IO<Unit>:
    state : W.State <- sampler_sample(state,"initial")
    state : W.State <- sampler_sample(state,"cached")
    state : W.State <- sampler_sample(edit_state(state),"raw-edit")
    state : W.State <- sampler_sample(W.invalidate_cache(state),"uncached")
    return Unit{}

def sampler_halo_edit(state:W.State) -> W.State:
  W.State{G.Engine{world,registry},body,yaw,pitch,+palette,+region,cache} = state
  match palette region:
    case None{} _: W.State{G.Engine{world,registry},body,yaw,pitch,palette,region,cache}
    case Some{W.Palette{air,stone,dirt,planks}} W.Bounds{x,y,z,w,h,d}:
      halo_write_result(C.write_block(world,W.position(V.neighbor(W.Cell{x,y,z,0},B.Down{})),air),registry,W.View{body,yaw,pitch,palette,region,cache})

def sampler_halo(state:W.State) -> IO(Unit):
  do IO<Unit>:
    state : W.State <- sampler_sample(state,"halo-initial")
    state : W.State <- sampler_sample(state,"halo-cached")
    state : W.State <- sampler_sample(sampler_halo_edit(state),"halo-edit")
    state : W.State <- sampler_sample(state,"halo-recached")
    return Unit{}
def sampler_errors_ready(state:W.State) -> IO(Unit):
  W.State{engine,+body,+yaw,+pitch,+palette,+region,+cache} = state
  do IO<Unit>:
    state : W.State <- owned_cases(W.State{engine,body,yaw,pitch,palette,region,cache},W.View{body,yaw,pitch,palette,region,cache})
    return Unit{}
def sampler_errors_result(result:W.State & Result<&2,&2,V.Error,V.Sample>) -> IO(Unit):
  (state,status) = result
  match status:
    case Fail{error}: IO.die(Unit,1,"sampler error preparation failed")
    case Done{value}: sampler_errors_ready(state)
def sampler_ready(state:W.State,args:List<&2,String>) -> IO(Unit):
  match args:
    case Nil{}: sampler_basic(state)
    case "halo-edit" <> Nil{}: sampler_halo(state)
    case "errors" <> Nil{}: sampler_errors_result(V.sample(state,V.defaults()))
    case "sample-error" <> id <> Nil{}: direct_sample_error(V.sample(state,V.defaults()),id)
    case "unknown-halo" <> Nil{}: direct_sample_error(V.sample(unknown_halo(state),V.defaults()),"unknown-halo")
    case id <> Nil{}:
      do IO<Unit>:
        state : W.State <- sampler_sample(state,id)
        return Unit{}
    case id <> draw <> Nil{}:
      do IO<Unit>:
        state : W.State <- sampler_sample(state,id)
        return Unit{}
    case _: IO.die(Unit,2,"sampler arguments")
def sampler_parsed(result:Result<&2,&2,String,J.Value>,args:List<&2,String>) -> IO(Unit):
  match result:
    case Fail{error}: IO.die(Unit,1,"sampler input JSON:" ++ error)
    case Done{value}:
      do IO<Unit>:
        engine : G.Engine <- G.load()
        state : W.State <- initialize(J.member(value,"fixture"),engine)
        sampler_ready(state,args)
def sampler_arguments(args:List<String>) -> IO(Unit):
  match args:
    case program <> "pairs" <> Nil{}: pairs(96n,0)
    case program <> "neighbors" <> Nil{}: neighbors(NamedCell{"origin",V.empty_cell()} <> test_positions(8n,0))
    case program <> input <> tail: sampler_parsed(J.parse_with(input,J.Limits{1048576n,64}),shared_args(tail))
    case _: IO.die(Unit,2,"sampler source input required")

# Raw bits are read without model-number parsing or float conversion.
def f32_bits(value:U32) -> F32:
  match value:
    case U32{bits}: F32{bits}
def dto_vertex(value:J.Value) -> Result<&2,&2,B.Error,M.Vertex>:
  match value:
    case J.JArray{[x,y,z,u,v]}:
      do Result<&2,&2,B.Error,M.Vertex>:
        px : U32 <- u32(x)
        py : U32 <- u32(y)
        pz : U32 <- u32(z)
        tu : U32 <- u32(u)
        tv : U32 <- u32(v)
        Done{M.Vertex{M.Vec3{f32_bits(px),f32_bits(py),f32_bits(pz)},M.UV{f32_bits(tu),f32_bits(tv)}}}
    case _: B.fail(M.Vertex,"Vertex5","dto")
def dto_direction(value:J.Value) -> Result<&2,&2,B.Error,B.Direction>:
  do Result<&2,&2,B.Error,B.Direction>:
    name : String <- B.strict_string(value,"direction")
    B.direction(name,"direction")
def dto_group(value:J.Value) -> Result<&2,&2,B.Error,Maybe<&2,B.Direction>>:
  match value:
    case J.JNull{}: Done{None{}}
    case other:
      do Result<&2,&2,B.Error,Maybe<&2,B.Direction>>:
        direction : B.Direction <- dto_direction(other)
        Done{Some{direction}}
def dto_layer(value:J.Value) -> Result<&2,&2,B.Error,K.Layer>:
  match value:
    case J.JString{"SOLID"}: Done{K.Solid{}}
    case J.JString{"CUTOUT"}: Done{K.Cutout{}}
    case J.JString{"TRANSLUCENT"}: Done{K.Translucent{}}
    case _: B.fail(K.Layer,"Layer","dto")
def dto_bool(value:J.Value) -> Result<&2,&2,B.Error,Bool>:
  match value:
    case J.JBool{value}: Done{value}
    case _: B.fail(Bool,"Bool","dto")
def dto_baked(value:J.Value) -> Result<&2,&2,B.Error,K.Baked>:
  match value:
    case J.JArray{[a,b,c,d,direction,cf,sprite,slot,index,emission,override,layer,force,animated,ds,ns]}:
      do Result<&2,&2,B.Error,K.Baked>:
        va : M.Vertex <- dto_vertex(a)
        vb : M.Vertex <- dto_vertex(b)
        vc : M.Vertex <- dto_vertex(c)
        vd : M.Vertex <- dto_vertex(d)
        dir : B.Direction <- dto_direction(direction)
        cull : Maybe<&2,B.Direction> <- dto_group(cf)
        name : String <- B.strict_string(sprite,"sprite")
        texture : U32 <- u32(slot)
        tint : U32 <- u32(index)
        light : U32 <- u32(emission)
        shade_override : Maybe<&2,B.Direction> <- dto_group(override)
        render_layer : K.Layer <- dto_layer(layer)
        forced : Bool <- dto_bool(force)
        animation : Bool <- dto_bool(animated)
        default_shade : U32 <- u32(ds)
        nether_shade : U32 <- u32(ns)
        Done{K.Baked{va,vb,vc,vd,dir,cull,name,texture,tint,light,shade_override,render_layer,forced,animation,f32_bits(default_shade),f32_bits(nether_shade)}}
    case _: B.fail(K.Baked,"Baked16","dto")
def dto_bakeds(values:List<&2,J.Value>) -> Result<&2,&2,B.Error,List<&2,K.Baked>>:
  match values:
    case Nil{}: Done{[]}
    case value <> tail:
      do Result<&2,&2,B.Error,List<&2,K.Baked>>:
        head : K.Baked <- dto_baked(value)
        rest : List<&2,K.Baked> <- dto_bakeds(tail)
        Done{head <> rest}
def dto_binding(value:J.Value) -> Result<&2,&2,B.Error,WM.Binding>:
  match value:
    case J.JArray{[state,J.JArray{quads}]}:
      do Result<&2,&2,B.Error,WM.Binding>:
        id : U32 <- u32(state)
        baked : List<&2,K.Baked> <- dto_bakeds(quads)
        Done{WM.Binding{id,baked,WM.appearance()}}
    case _: B.fail(WM.Binding,"Binding2","dto")
def dto_bindings(value:J.Value) -> Result<&2,&2,B.Error,List<&2,WM.Binding>>:
  match value:
    case J.JArray{Nil{}}: Done{[]}
    case J.JArray{head <> tail}:
      do Result<&2,&2,B.Error,List<&2,WM.Binding>>:
        binding : WM.Binding <- dto_binding(head)
        rest : List<&2,WM.Binding> <- dto_bindings(J.JArray{tail})
        Done{binding <> rest}
    case _: B.fail(List<&2,WM.Binding>,"Bindings","dto")
def dto_block(value:J.Value) -> Result<&2,&2,B.Error,R.Block>:
  match value:
    case J.JArray{[x,y,z,state,material]}:
      do Result<&2,&2,B.Error,R.Block>:
        px : U32 <- u32(x)
        py : U32 <- u32(y)
        pz : U32 <- u32(z)
        id : U32 <- u32(state)
        slot : U32 <- u32(material)
        Done{R.Block{f32_bits(px),f32_bits(py),f32_bits(pz),id,slot}}
    case _: B.fail(R.Block,"Block5","dto")
def dto_blocks(values:List<&2,J.Value>) -> Result<&2,&2,B.Error,List<&2,R.Block>>:
  match values:
    case Nil{}: Done{[]}
    case value <> tail:
      do Result<&2,&2,B.Error,List<&2,R.Block>>:
        head : R.Block <- dto_block(value)
        rest : List<&2,R.Block> <- dto_blocks(tail)
        Done{head <> rest}
def dto_raw(value:J.Value) -> Result<&2,&2,B.Error,W.RawBlock>:
  match value:
    case J.JArray{[x,y,z,boundary,state,material]}:
      do Result<&2,&2,B.Error,W.RawBlock>:
        px : U32 <- u32(x)
        py : U32 <- u32(y)
        pz : U32 <- u32(z)
        edge : U32 <- u32(boundary)
        id : U32 <- u32(state)
        slot : U32 <- u32(material)
        Done{W.RawBlock{W.Cell{px,py,pz,edge},id,slot}}
    case _: B.fail(W.RawBlock,"Raw6","dto")
def dto_raws(values:List<&2,J.Value>) -> Result<&2,&2,B.Error,List<&2,W.RawBlock>>:
  match values:
    case Nil{}: Done{[]}
    case value <> tail:
      do Result<&2,&2,B.Error,List<&2,W.RawBlock>>:
        head : W.RawBlock <- dto_raw(value)
        rest : List<&2,W.RawBlock> <- dto_raws(tail)
        Done{head <> rest}
def dto_mask(value:J.Value) -> Result<&2,&2,B.Error,V.Visibility>:
  match value:
    case J.JArray{[x,y,z,boundary,state,visible]}:
      do Result<&2,&2,B.Error,V.Visibility>:
        px : U32 <- u32(x)
        py : U32 <- u32(y)
        pz : U32 <- u32(z)
        edge : U32 <- u32(boundary)
        id : U32 <- u32(state)
        mask : U32 <- u32(visible)
        Done{V.Visibility{W.Cell{px,py,pz,edge},id,mask}}
    case _: B.fail(V.Visibility,"Mask6","dto")
def dto_masks(values:List<&2,J.Value>) -> Result<&2,&2,B.Error,List<&2,V.Visibility>>:
  match values:
    case Nil{}: Done{[]}
    case value <> tail:
      do Result<&2,&2,B.Error,List<&2,V.Visibility>>:
        head : V.Visibility <- dto_mask(value)
        rest : List<&2,V.Visibility> <- dto_masks(tail)
        Done{head <> rest}
def dto_camera(value:J.Value) -> Result<&2,&2,B.Error,R.Camera>:
  match value:
    case J.JArray{[x,y,z,yaw,pitch]}:
      do Result<&2,&2,B.Error,R.Camera>:
        px : U32 <- u32(x)
        py : U32 <- u32(y)
        pz : U32 <- u32(z)
        ry : U32 <- u32(yaw)
        rp : U32 <- u32(pitch)
        Done{R.Camera{f32_bits(px),f32_bits(py),f32_bits(pz),f32_bits(ry),f32_bits(rp)}}
    case _: B.fail(R.Camera,"Camera5","dto")
def dto_palette(value:J.Value) -> Result<&2,&2,B.Error,W.Palette>:
  match value:
    case J.JArray{[air,stone,dirt,planks]}:
      do Result<&2,&2,B.Error,W.Palette>:
        a : U32 <- u32(air)
        b : U32 <- u32(stone)
        c : U32 <- u32(dirt)
        d : U32 <- u32(planks)
        Done{W.Palette{a,b,c,d}}
    case _: B.fail(W.Palette,"Palette4","dto")
def array_values(value:J.Value) -> Result<&2,&2,B.Error,List<&2,J.Value>>:
  match value:
    case J.JArray{values}: Done{values}
    case _: B.fail(List<&2,J.Value>,"Array","dto")
def dto_sample(+obj:J.Value) -> Result<&2,&2,B.Error,V.Sample>:
  do Result<&2,&2,B.Error,V.Sample>:
    tick_value : J.Value <- B.required(J.member(obj,"tick"),"tick")
    tick : U32 <- u32(tick_value)
    revision_value : J.Value <- B.required(J.member(obj,"revision"),"revision")
    revision : U32 <- u32(revision_value)
    block_value : J.Value <- B.required(J.member(obj,"blocks"),"blocks")
    block_array : List<&2,J.Value> <- array_values(block_value)
    blocks : List<&2,R.Block> <- dto_blocks(block_array)
    camera_value : J.Value <- B.required(J.member(obj,"camera"),"camera")
    camera : R.Camera <- dto_camera(camera_value)
    raw_value : J.Value <- B.required(J.member(obj,"raw"),"raw")
    raw_array : List<&2,J.Value> <- array_values(raw_value)
    raw : List<&2,W.RawBlock> <- dto_raws(raw_array)
    masks_value : J.Value <- B.required(J.member(obj,"masks"),"masks")
    masks_array : List<&2,J.Value> <- array_values(masks_value)
    masks : List<&2,V.Visibility> <- dto_masks(masks_array)
    origin_value : J.Value <- B.required(J.member(obj,"origin"),"origin")
    origin_array : List<&2,U32> <- number_array(origin_value)
    origin : MV.Vec3 <- position64(origin_array)
    palette_value : J.Value <- B.required(J.member(obj,"palette"),"palette")
    palette : W.Palette <- dto_palette(palette_value)
    reads_value : J.Value <- B.required(J.member(obj,"reads"),"reads")
    reads : U32 <- u32(reads_value)
    Done{V.Sample{R.Snapshot{U32.to_nat(tick),U32.to_nat(revision),blocks,camera},raw,masks,origin,palette,reads}}
def simple_texture(+value:J.Value) -> Result<&2,&2,B.Error,R.Texture>:
  do Result<&2,&2,B.Error,R.Texture>:
    w_value : J.Value <- B.required(J.member(value,"width"),"width")
    width : U32 <- u32(w_value)
    h_value : J.Value <- B.required(J.member(value,"height"),"height")
    height : U32 <- u32(h_value)
    pixel_value : J.Value <- B.required(J.member(value,"pixels"),"pixels")
    pixels : List<&2,U32> <- number_array(pixel_value)
    Done{R.texture(P.Decoded{width,height,pixels})}
def simple_textures(value:J.Value) -> Result<&2,&2,B.Error,List<&2,R.Texture>>:
  match value:
    case J.JArray{Nil{}}: Done{[]}
    case J.JArray{head <> tail}:
      do Result<&2,&2,B.Error,List<&2,R.Texture>>:
        texture : R.Texture <- simple_texture(head)
        rest : List<&2,R.Texture> <- simple_textures(J.JArray{tail})
        Done{texture <> rest}
    case _: B.fail(List<&2,R.Texture>,"Textures","dto")
type GeometryInput is Data:
  GeometryInput{sample:V.Sample,bindings:List<&2,WM.Binding>,textures:List<&2,R.Texture>}
def geometry_input(+value:J.Value) -> Result<&2,&2,B.Error,GeometryInput>:
  do Result<&2,&2,B.Error,GeometryInput>:
    sample_value : J.Value <- B.required(J.member(value,"sample"),"sample")
    sample : V.Sample <- dto_sample(sample_value)
    bindings_value : J.Value <- B.required(J.member(value,"bindings"),"bindings")
    bindings : List<&2,WM.Binding> <- dto_bindings(bindings_value)
    textures_value : J.Value <- B.required(J.member(value,"textures"),"textures")
    textures : List<&2,R.Texture> <- simple_textures(textures_value)
    Done{GeometryInput{sample,bindings,textures}}
def geometry_ready(result:Result<&2,&2,B.Error,GeometryInput>,args:List<&2,String>) -> IO(Unit):
  match result:
    case Fail{B.Error{code,path}}: IO.die(Unit,1,"geometry DTO:" ++ code ++ ":" ++ path)
    case Done{GeometryInput{+value,+bindings,textures}}:
      match args:
        case "errors" <> Nil{}: pure_cases(value,bindings)
        case id <> draw <> Nil{}:
          do IO<Unit>:
            assets : R.Assets <- scene_report(V.produce(value,bindings,3,WM.frame(32,24),WM.defaults()),R.Assets{textures},id,U32.is_eq(number(draw),1))
            return Unit{}
        case _: IO.die(Unit,2,"geometry arguments")
def geometry_parsed(result:Result<&2,&2,String,J.Value>,args:List<&2,String>) -> IO(Unit):
  match result:
    case Fail{error}: IO.die(Unit,1,"geometry JSON:" ++ error)
    case Done{value}: geometry_ready(geometry_input(value),args)
def geometry_arguments(args:List<String>) -> IO(Unit):
  match args:
    case program <> input <> tail: geometry_parsed(J.parse_with(input,J.Limits{1048576n,64}),shared_args(tail))
    case _: IO.die(Unit,2,"geometry input required")

def main() -> IO(Unit):
  IO.bind(List<String>,Unit,IO.args(),arguments)
