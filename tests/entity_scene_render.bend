import Base
import ../src/entity_scene_render.bend as Scene
import ../src/entity_scene_render_model.bend as A
import ../src/entity_scene_render_assets.bend as Assets
import ../src/entity_scene_render_camera.bend as Camera
import ../src/remote_entity_frame.bend as EF
import ../src/remote_entity_snapshot_wire.bend as Wire
import ../src/generic_resource_world_sample.bend as GS
import ../src/client_world.bend as W
import ../src/client_render.bend as R
import ../src/world_mesh.bend as WM
import ../src/mesh_render.bend as M
import ../src/block_resources.bend as BR
import ../src/block_bake.bend as K
import ../src/blockstate_model.bend as S
import ../src/resource_block_catalog.bend as C
import ../src/resource_catalog_world.bend as CW
import ../src/registry.bend as Registry
import ../src/item_entity_render_resources.bend as IR
import ../src/item_entity_render_model.bend as D
import ../src/inventory.bend as Inv
import ../src/player_item_definitions.bend as Definitions
import ../src/locomotion.bend as L
import ../src/movement.bend as MV
import ../src/vanilla_entity_fields.bend as V
import ../src/f64.bend as F
import ../src/json.bend as J
import ../src/crafting_recipe_decoder.bend as Decode
import ../src/crafting_recipe_components.bend as Components
import ./cooking_effect_entities_values.bend as T

def nums(values:List<&2,U32>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case head <> rest: T.num(head) <> nums(rest)
def integer(value:Maybe<&2,U32>) -> U32:
  match value:
    case None{}: 0
    case Some{value}: value
type Input is Data:
  Input{definitions:Definitions.Catalog,jar:String,sine:String,values:List<&2,J.Value>}
def raw(value:U32) -> F32:
  U32{word} = value
  F32{word}
def vertex(value:M.Vertex) -> J.Value:
  M.Vertex{M.Vec3{x,y,z},M.UV{u,v}} = value
  T.obj([J.JMember{"position",J.JArray{nums([F32.bits(x),F32.bits(y),F32.bits(z)])}},J.JMember{"uv",J.JArray{nums([F32.bits(u),F32.bits(v)])}}])
def input_fields(+value:J.Value) -> Result<&2,&2,String,Input>:
  do Result<&2,&2,String,Input>:
    catalog:J.Value <- Decode.field(value,"catalog")
    raw_items:J.Value <- Decode.field(catalog,"items")
    items:List<&2,J.Value> <- Decode.array(raw_items)
    defaults:List<&2,Components.Default> <- Decode.defaults_rows(items,[])
    text:String <- Decode.text_field(value,"item_table")
    definitions:Definitions.Catalog <- Definitions.parse(text)
    jar:String <- Decode.text_field(value,"jar")
    sine:String <- Decode.text_field(value,"sine")
    values:List<&2,J.Value> <- T.array_field(value,"cases")
    Done{Input{Definitions.with_initialized_defaults(definitions,defaults),jar,sine,values}}
# Real loaded stone model and authenticated actual initialized cooked-beef item
# model. Lighting colors below are explicit synthetic input for composition,
# not a claim that a game lightmap or authoritative light actor is installed.
def world(loaded:BR.Loaded) -> CW.Assets:
  BR.Loaded{resources,+catalog} = loaded
  BR.Catalog{roots,source,models,+sprites,context,usage} = catalog
  CW.Assets{resources,C.Catalog{"fixture:pinned26.3:stone",Map.set(&2,C.Entry,MTip{},"1",C.Entry{Registry.Resolved{1,"minecraft:stone",1,[]},C.Model{},Some{S.VariantRoot{S.Single{S.Variant{"minecraft:block/stone",0,0,0,False{}}}}}}),catalog},U32.from_nat(List.length(&2,BR.SpriteInfo,sprites))}
def position(z:F32) -> V.Vec3: V.Vec3{F.from_f32(0.5),F.from_f32(0.15),F.from_f32(z)}
def common(id:U32,z:F32,order:Nat) -> D.Common:
  +pos = position(z)
  D.Common{"minecraft:overworld",id,pos,pos,33,False{},True{},order}
def snapshot(entities:Bool,+z:F32) -> D.Snapshot:
  match entities:
    case False{}: D.Bound{[]}
    case True{}: D.Bound{[D.Item{common(71,z,0n),Inv.InvStack{Inv.ItemKey{"minecraft:cooked_beef",""},1},0.5},D.Orb{common(72,z,1n),7}]}
def frame(entities:Bool,z:F32) -> EF.Frame:
  EF.Frame{GS.Sample{"fixture:pinned26.3:stone",7n,9n,MV.Vec3{F.from_f32(0.5),F.from_f32(0.5),F.from_f32(0.0)},R.Camera{0.0,0.0,0.0,0.0,0.0},[GS.Cell{W.Cell{0,0,2,0},1,0,WM.appearance()}]},snapshot(entities,z),"minecraft:overworld",0.25}
def light(stamp:Wire.Stamp) -> A.Lighting:
  A.Stable{stamp,Map.set(&2,Maybe<&2,A.WorldLight>,MTip{},"0:0:2",Some{A.WorldLight{1,2,4,4289777792}}),[D.Light{71,2,4,4292902992,4292902992},D.Light{72,2,4,4292902992,4292902992}]}
def context(+stamp:Wire.Stamp,lights:A.Lighting,budget:U32) -> A.Context:
  A.Context{stamp,lights,WM.frame(32,32),WM.Limits{4,4,budget,64,4},100n,4096n}
def quad(value:M.Quad) -> J.Value:
  M.Quad{a,b,c,d,M.Material{texture,tint,light,shade,mode,address},cull,order} = value
  T.obj([J.JMember{"vertices",J.JArray{[vertex(a),vertex(b),vertex(c),vertex(d)]}},J.JMember{"texture",T.num(texture)},J.JMember{"tint",T.num(tint)},J.JMember{"light",T.num(light)},J.JMember{"shade",T.num(F32.bits(shade))},J.JMember{"order",T.num(order)}])
def quads(values:List<&2,M.Quad>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case head <> rest: quad(head) <> quads(rest)
def image(value:Result<&2,&2,A.Error,Image>) -> J.Value:
  match value:
    case Fail{A.Refused{message}}: T.obj([J.JMember{"error",T.txt(message)}])
    case Done{image}: J.JArray{nums(R.pixels_of(image,32,32))}
def drew(pair:A.Assets & L.Tables & Result<&2,&2,A.Error,Image>,scene:J.Value,name:String) -> A.Assets & L.Tables & J.Value:
  (assets,tables,pixels) = pair
  (assets,tables,T.obj([J.JMember{"name",T.txt(name)},J.JMember{"scene",scene},J.JMember{"pixels",image(pixels)}]))
def prepared(pair:A.Assets & L.Tables & Result<&2,&2,A.Error,A.Prepared>,name:String) -> A.Assets & L.Tables & J.Value:
  (assets,tables,status) = pair
  match status:
    case Fail{A.Refused{message}}: (assets,tables,T.obj([J.JMember{"name",T.txt(name)},J.JMember{"error",T.txt(message)}]))
    case Done{A.Prepared{+stamp,+scene,+entities}}:
      M.Scene{camera,values,settings} = scene
      drew(Scene.draw_prepared((assets,tables,Done{A.Prepared{stamp,scene,entities}}),32,32),J.JArray{quads(values)},name)
def run_case(name:String,+input:EF.Frame,lights:A.Lighting,budget:U32,assets:A.Assets,tables:L.Tables) -> A.Assets & L.Tables & J.Value:
  prepared(Scene.prepare(context(Wire.stamp(input),lights,budget),input,assets,tables),name)
def cases_ready(pair:A.Assets & L.Tables & J.Value,next:A.Assets -> L.Tables -> List<&2,J.Value> -> A.Assets & L.Tables & List<&2,J.Value>,outputs:List<&2,J.Value>) -> A.Assets & L.Tables & List<&2,J.Value>:
  (assets,tables,row) = pair
  next(assets,tables,row <> outputs)
def cases(which:Nat,assets:A.Assets,tables:L.Tables,outputs:List<&2,J.Value>) -> A.Assets & L.Tables & List<&2,J.Value>:
  match which:
    case 0n: (assets,tables,List.reverse(&2,J.Value,outputs))
    case 1n: cases_ready(run_case("world-only",frame(False{},4.0),light(Wire.stamp(frame(False{},4.0))),4096,assets,tables),assets => tables => outputs => cases(0n,assets,tables,outputs),outputs)
    case 2n: cases_ready(run_case("behind",frame(True{},4.0),light(Wire.stamp(frame(True{},4.0))),4096,assets,tables),assets => tables => outputs => cases(1n,assets,tables,outputs),outputs)
    case 3n: cases_ready(run_case("front",frame(True{},1.0),light(Wire.stamp(frame(True{},1.0))),4096,assets,tables),assets => tables => outputs => cases(2n,assets,tables,outputs),outputs)
    case 4n: cases_ready(run_case("missing-light",frame(True{},1.0),A.Missing{"not published"},4096,assets,tables),assets => tables => outputs => cases(3n,assets,tables,outputs),outputs)
    case 5n: cases_ready(run_case("shared-quad-budget",frame(True{},1.0),light(Wire.stamp(frame(True{},1.0))),6,assets,tables),assets => tables => outputs => cases(4n,assets,tables,outputs),outputs)
    case _: (assets,tables,outputs)
def texture_samples(values:List<&2,R.Texture>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case R.Texture{+width,+height,+side,image} <> rest: J.JArray{nums([width,height,side,R.pixel_at(16n,image,U32.div(width,2),U32.div(height,2),side)])} <> texture_samples(rest)
def report(pair:A.Assets & L.Tables & List<&2,J.Value>,cameras:J.Value) -> IO(Unit):
  (A.Assets{R.Assets{textures},catalog,wc,prefix,items,ec},tables,rows) = pair
  IO.print(J.encode(T.obj([J.JMember{"cases",J.JArray{rows}},J.JMember{"world_count",T.num(wc)},J.JMember{"entity_count",T.num(ec)},J.JMember{"textures",J.JArray{texture_samples(textures)}},J.JMember{"cameras",cameras}])))
def camera_row(value:D.Quaternion,rest:List<&2,J.Value>) -> List<&2,J.Value>:
  D.Quaternion{x,y,z,w} = value
  J.JArray{nums([F32.bits(x),F32.bits(y),F32.bits(z),F32.bits(w)])} <> rest
def cameras_row(value:Maybe<&2,J.Value>,rest:List<&2,J.Value>) -> List<&2,J.Value>:
  match value:
    case Some{J.JArray{[J.JNumber{yaw},J.JNumber{pitch}]}}:
      camera_row(Camera.billboard(R.Camera{0.0,0.0,0.0,raw(integer(J.u32_lexeme(yaw))),raw(integer(J.u32_lexeme(pitch)))}),rest)
    case _: rest
def cameras(values:List<&2,J.Value>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case +head <> rest: cameras_row(J.member(head,"radians"),cameras(rest))
def joined(value:A.Join,tables:L.Tables,values:List<&2,J.Value>) -> IO(Unit):
  match value:
    case A.Rejected{world,items,A.Refused{message}}: IO.print(message)
    case A.Joined{assets}: report(cases(5n,assets,tables,[]),J.JArray{cameras(values)})
def item_loaded(value:Result<&2,&1,String,IR.Assets>,world:CW.Assets,tables:L.Tables,values:List<&2,J.Value>) -> IO(Unit):
  match value:
    case Fail{message}: IO.print(message)
    case Done{items}: joined(Assets.join(world,items),tables,values)
def world_loaded(value:Result<&2,&1,BR.Error,BR.Loaded>,definitions:Definitions.Catalog,jar:String,tables:L.Tables,values:List<&2,J.Value>) -> IO(Unit):
  match value:
    case Fail{BR.Error{code,name,message}}: IO.print(code ++ ":" ++ message)
    case Done{loaded}:
      do IO<Unit>:
        items:Result<&2,&1,String,IR.Assets> <- IR.load(jar,definitions,[Inv.ItemKey{"minecraft:cooked_beef",""}],BR.defaults())
        item_loaded(items,world(loaded),tables,values)
def tables_loaded(value:Result<&2,&1,L.Error,L.Tables>,definitions:Definitions.Catalog,+jar:String,values:List<&2,J.Value>) -> IO(Unit):
  match value:
    case Fail{error}: IO.print("sine load failed")
    case Done{tables}:
      do IO<Unit>:
        world:Result<&2,&1,BR.Error,BR.Loaded> <- BR.load(jar,["minecraft:block/stone"],BR.StaticNormalized{Map.set(&2,K.Layer,MTip{},"minecraft:block/stone",K.Solid{})},BR.defaults())
        world_loaded(world,definitions,jar,tables,values)
def input(value:Result<&2,&2,String,Input>) -> IO(Unit):
  match value:
    case Fail{message}: IO.print(message)
    case Done{Input{definitions,jar,sine,values}}:
      do IO<Unit>:
        tables:Result<&2,&1,L.Error,L.Tables> <- L.Tables.load(sine)
        tables_loaded(tables,definitions,jar,values)
def parsed(value:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match value:
    case Fail{message}: IO.print(message)
    case Done{value}: input(input_fields(value))
def read_text(value:Result<&1,&1,U32 & String,String>) -> IO(Unit):
  match value:
    case Fail{error}: IO.print("read failed")
    case Done{text}: parsed(J.parse_bounded(text,16777216n,255))
def read(value:File & Result<&1,&1,U32 & String,String>) -> IO(Unit):
  (file,text) = value
  do IO<Unit>:
    File.close(file)
    read_text(text)
def opened(value:Result<&1,&1,U32 & String,File>) -> IO(Unit):
  match value:
    case Fail{error}: IO.print("open failed")
    case Done{file}:
      do IO<Unit>:
        value:File & Result<&1,&1,U32 & String,String> <- File.read(file,16777216)
        read(value)
def args(values:List<&1,String>) -> IO(Unit):
  match values:
    case exe <> path <> Nil{}:
      do IO<Unit>:
        value:Result<&1,&1,U32 & String,File> <- File.open(path,"r")
        opened(value)
    case _: IO.print("input required")
def main() -> IO(Unit):
  do IO<Unit>:
    values:List<&1,String> <- IO.args()
    args(values)
