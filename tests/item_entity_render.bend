import Base
import ../src/json.bend as J
import ../src/crafting_recipe_decoder.bend as Decode
import ../src/crafting_recipe_components.bend as Components
import ../src/player_item_definitions.bend as Definitions
import ../src/inventory.bend as I
import ../src/random.bend as RNG
import ../src/vanilla_entity_fields.bend as V
import ../src/f64.bend as F
import ../src/player_look.bend as Look
import ../src/locomotion.bend as Sine
import ../src/block_resources.bend as BR
import ../src/client_render.bend as R
import ../src/mesh_render.bend as Mesh
import ../src/cooking_effect_entities_model.bend as E
import ../src/item_entity_render_model.bend as Model
import ../src/item_entity_render.bend as Render
import ../src/item_entity_render_resources.bend as Resources
import ./cooking_effect_entities_values.bend as T

type Fixture is Data:
  Fixture{record:Model.Record,partial:F32,scan:Nat,budget:Nat}
type Input is Data:
  Input{definitions:Definitions.Catalog,jar:String,sine:String,values:List<&2,J.Value>}

def raw(word:U32) -> F32:
  U32{bits} = word
  F32{bits}
def number(value:F32) -> J.Value: T.num(F32.bits(value))
def point(value:Mesh.Vec3) -> J.Value:
  Mesh.Vec3{x,y,z} = value
  J.JArray{[number(x),number(y),number(z)]}
def uv(value:Mesh.UV) -> J.Value:
  Mesh.UV{u,v} = value
  J.JArray{[number(u),number(v)]}
def vertex(value:Mesh.Vertex) -> J.Value:
  Mesh.Vertex{position,coords} = value
  T.obj([J.JMember{"position",point(position)},J.JMember{"uv",uv(coords)}])
def quad(value:Mesh.Quad) -> J.Value:
  Mesh.Quad{a,b,c,d,Mesh.Material{texture,tint,light,shade,mode,address},cull,order} = value
  T.obj([J.JMember{"vertices",J.JArray{[vertex(a),vertex(b),vertex(c),vertex(d)]}},J.JMember{"texture",T.num(texture)},J.JMember{"tint",T.num(tint)},J.JMember{"light",T.num(light)}])
def quads(values:List<&2,Mesh.Quad>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case head <> rest: quad(head) <> quads(rest)
def points(values:List<&2,Mesh.Vec3>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case head <> rest: point(head) <> points(rest)
def draw(value:Model.Draw) -> J.Value:
  match value:
    case Model.ItemDraw{id,I.ItemKey{name,components},age,origin,hover,spin,copies,light,block,mesh}:
      T.obj([J.JMember{"kind",T.txt("item")},J.JMember{"item",T.txt(name)},J.JMember{"age",number(age)},J.JMember{"origin",point(origin)},J.JMember{"hover",number(hover)},J.JMember{"spin",number(spin)},J.JMember{"copies",J.JArray{points(copies)}},J.JMember{"packed_light",T.num(light)},J.JMember{"quads",J.JArray{quads(mesh)}}])
    case Model.OrbDraw{id,age,origin,icon,light,color,mesh}:
      T.obj([J.JMember{"kind",T.txt("orb")},J.JMember{"age",number(age)},J.JMember{"origin",point(origin)},J.JMember{"icon",T.num(icon)},J.JMember{"packed_light",T.num(light)},J.JMember{"color",T.num(color)},J.JMember{"quads",J.JArray{[quad(mesh)]}}])
def draws(values:List<&2,Model.Draw>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case head <> rest: draw(head) <> draws(rest)
def texture_slot(values:List<&2,Mesh.Quad>) -> U32:
  match values:
    case Nil{}: 0
    case Mesh.Quad{a,b,c,d,Mesh.Material{slot,tint,light,shade,mode,address},cull,order} <> rest: slot
def texture_pixels(+textures:List<&2,R.Texture>,+index:U32) -> J.Value:
  J.JArray{[T.num(Mesh.sample(textures,U32.to_nat(index),Mesh.Clamp{},0.0,0.0)),T.num(Mesh.sample(textures,U32.to_nat(index),Mesh.Clamp{},0.5,0.5)),T.num(Mesh.sample(textures,U32.to_nat(index),Mesh.Clamp{},1.0,1.0)),T.num(Mesh.sample(textures,U32.to_nat(index),Mesh.Clamp{},0.25,0.75))]}
def pixel_ground(value:Model.Ground,textures:List<&2,R.Texture>) -> J.Value:
  Model.Ground{I.ItemKey{id,identity},seed,qs,low,high,block} = value
  T.obj([J.JMember{"item",T.txt(id)},J.JMember{"pixels",texture_pixels(textures,texture_slot(qs))}])
def pixel_grounds(values:List<&2,Model.Ground>,+textures:List<&2,R.Texture>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case head <> rest: pixel_ground(head,textures) <> pixel_grounds(rest,textures)
def pixels(assets:Resources.Assets) -> J.Value:
  Resources.Assets{R.Assets{textures},Model.Catalog{items,count,orb}} = assets
  J.JArray{pixel_grounds(items,textures)}
def ground(value:Model.Ground) -> J.Value:
  Model.Ground{I.ItemKey{id,identity},seed,mesh,low,high,block} = value
  T.obj([J.JMember{"item",T.txt(id)},J.JMember{"seed",T.num(seed)},J.JMember{"low",point(low)},J.JMember{"high",point(high)},J.JMember{"quads",J.JArray{quads(mesh)}}])
def grounds(values:List<&2,Model.Ground>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case head <> rest: ground(head) <> grounds(rest)
def render_error(error:Model.Error) -> String:
  match error:
    case Model.Refused{message}: message
    case Model.ScanBudget{}: "scan budget"
    case Model.QuadBudget{}: "quad budget"
def rendered(pair:Sine.Tables & Result<&2,&2,Model.Error,Model.Frame>) -> Sine.Tables & J.Value:
  (tables,result) = pair
  match result:
    case Fail{error}: (tables,T.obj([J.JMember{"error",T.txt(render_error(error))}]))
    case Done{Model.Frame{ds,qs}}: (tables,T.obj([J.JMember{"draws",J.JArray{draws(ds)}},J.JMember{"quad_count",T.num(U32.from_nat(List.length(&2,Mesh.Quad,qs)))}]))
def common() -> Model.Common:
  Model.Common{"minecraft:overworld",71,V.zero_vector(),V.zero_vector(),33,False{},True{},19n}
def item_case(value:Model.Common,kind:Bool,name:String,count:U32,bob:F32,xp:U32) -> Model.Record:
  match kind:
    case True{}: Model.Item{value,I.InvStack{I.ItemKey{name,""},count},bob}
    case False{}: Model.Orb{value,xp}
def changed_common(value:Model.Common,ticks:U32,removed:Bool,dimension:String) -> Model.Common:
  Model.Common{d,id,p,old,t,r,accessible,order} = value
  Model.Common{dimension,id,p,old,ticks,removed,accessible,order}
def fixture_values(+value:J.Value) -> Result<&2,&2,String,Fixture>:
  do Result<&2,&2,String,Fixture>:
    kind : String <- Decode.text_field(value,"kind")
    name : String <- Decode.text_field(value,"item")
    count : U32 <- Decode.number_field(value,"count")
    xp : U32 <- Decode.number_field(value,"xp")
    ticks : U32 <- Decode.number_field(value,"ticks")
    partial : U32 <- Decode.number_field(value,"partial")
    scan : U32 <- Decode.number_field(value,"scan")
    budget : U32 <- Decode.number_field(value,"budget")
    removed : Bool <- T.flag(value,"removed")
    dimension : String <- Decode.text_field(value,"dimension")
    return Fixture{item_case(changed_common(common(),ticks,removed,dimension),String.eq(kind,"item"),name,count,0.5,xp),raw(partial),U32.to_nat(scan),U32.to_nat(budget)}
def fixture_read(value:J.Value,catalog:Model.Catalog,tables:Sine.Tables,result:Result<&2,&2,String,Fixture>) -> Sine.Tables & J.Value:
  match result:
    case Fail{message}: (tables,T.obj([J.JMember{"error",T.txt(message)}]))
    case Done{Fixture{record,partial,scan,budget}}:
      rendered(Render.prepare_snapshot(Model.Context{"minecraft:overworld",V.zero_vector(),partial,Model.Quaternion{0.0,0.0,0.0,1.0},catalog,[Model.Light{71,0,15,4294967295,4294967295}],scan,budget},Model.Bound{[record]},tables))
def fixture(+value:J.Value,+catalog:Model.Catalog,tables:Sine.Tables) -> Sine.Tables & J.Value:
  fixture_read(value,catalog,tables,fixture_values(value))


def case_next(head:J.Value,pair:Sine.Tables & List<&2,J.Value>) -> Sine.Tables & List<&2,J.Value>:
  (tables,rest) = pair
  (tables,head <> rest)
def case_head(pair:Sine.Tables & J.Value,next:Sine.Tables -> Sine.Tables & List<&2,J.Value>) -> Sine.Tables & List<&2,J.Value>:
  (tables,head) = pair
  case_next(head,next(tables))
def cases(values:List<&2,J.Value>,+catalog:Model.Catalog,tables:Sine.Tables) -> Sine.Tables & List<&2,J.Value>:
  match values:
    case Nil{}: (tables,[])
    case head <> rest: case_head(fixture(head,catalog,tables),tables => cases(rest,catalog,tables))
def uuid(value:Maybe<&2,E.Uuid>) -> J.Value:
  match value:
    case None{}: J.JNull{}
    case Some{E.Uuid{a,b}}: J.JArray{[T.bits(a),T.bits(b)]}
def look_value(value:Look.State) -> J.Value:
  Look.State{yaw,pitch,yawo,pitcho} = value
  J.JArray{[number(yaw),number(pitch),number(yawo),number(pitcho)]}
def entire_common(value:E.Common) -> J.Value:
  E.Common{dimension,id,a,b,random,V.Fields{p,v,xo,old,look,head,body,fall,ground,air,fire,portal,invulnerable,sync},tick,first,removed,accessible,order} = value
  T.obj([J.JMember{"dimension",T.txt(dimension)},J.JMember{"id",T.num(id)},J.JMember{"uuid",J.JArray{[T.bits(a),T.bits(b)]}},J.JMember{"random",T.source(random)},J.JMember{"vectors",J.JArray{[T.vector(p),T.vector(v),T.vector(xo),T.vector(old)]}},J.JMember{"look",look_value(look)},J.JMember{"head",number(head)},J.JMember{"body",number(body)},J.JMember{"fall",T.double(fall)},J.JMember{"ground",T.bool(ground)},J.JMember{"air",T.num(air)},J.JMember{"fire",T.num(fire)},J.JMember{"portal",T.num(portal)},J.JMember{"invulnerable",T.bool(invulnerable)},J.JMember{"sync",T.bool(sync)},J.JMember{"tick",T.num(tick)},J.JMember{"first",T.bool(first)},J.JMember{"removed",T.bool(removed)},J.JMember{"accessible",T.bool(accessible)},J.JMember{"order",T.num(U32.from_nat(order))}])
def entire_record(value:E.Record) -> J.Value:
  match value:
    case E.Item{c,item,age,delay,health,thrower,target,bob}:
      T.obj([J.JMember{"common",entire_common(c)},J.JMember{"item",T.slot(item)},J.JMember{"age",T.num(age)},J.JMember{"delay",T.num(delay)},J.JMember{"health",T.num(health)},J.JMember{"thrower",uuid(thrower)},J.JMember{"target",uuid(target)},J.JMember{"bob",number(bob)}])
    case E.Orb{c,value,age,health,count,following}:
      T.obj([J.JMember{"common",entire_common(c)},J.JMember{"value",T.num(value)},J.JMember{"age",T.num(age)},J.JMember{"health",T.num(health)},J.JMember{"count",T.num(count)},J.JMember{"following",uuid(following)}])
def entire_records(values:List<&2,E.Record>) -> List<&2,J.Value>:
  match values:
    case Nil{}: []
    case head <> rest: entire_record(head) <> entire_records(rest)
def entire_view(value:E.View) -> J.Value:
  E.View{level,unique,cursor,order,values} = value
  T.obj([J.JMember{"level",T.source(level)},J.JMember{"factory",T.bits(unique)},J.JMember{"id",T.num(cursor)},J.JMember{"order",T.num(U32.from_nat(order))},J.JMember{"records",J.JArray{entire_records(values)}}])
def captured_owner(pair:E.State & E.View,+expected:E.View) -> J.Value:
  (state,actual) = pair
  T.bool(String.eq(J.encode(entire_view(actual)),J.encode(entire_view(expected))))
def capture_status(value:Result<&2,&2,Model.Error,Model.Frame>) -> J.Value:
  match value:
    case Done{frame}: T.txt("done")
    case Fail{error}: T.txt(render_error(error))
def capture_checked(pair:E.State & Sine.Tables & Result<&2,&2,Model.Error,Model.Frame>,expected:E.View) -> Sine.Tables & J.Value:
  (state,tables,result) = pair
  (tables,T.obj([J.JMember{"retained",captured_owner(E.inspect(state),expected)},J.JMember{"result",capture_status(result)}]))
def authority_view() -> E.View:
  +fields : V.Fields = V.Fields{V.Vec3{F.from_i32(10),F.from_i32(1),F.from_i32(12)},V.Vec3{F.from_i32(1),F.from_i32(2),F.from_i32(3)},V.Vec3{F.from_i32(99),F.from_i32(98),F.from_i32(97)},V.Vec3{F.from_i32(8),F.F64{0,0},F.from_i32(9)},Look.State{0.1,0.2,0.3,0.4},0.5,0.6,F.from_i32(7),True{},23,24,25,True{},True{}}
  +c : E.Common = E.Common{"minecraft:overworld",71,RNG.Bits64{11,12},RNG.Bits64{13,14},RNG.Legacy{RNG.Bits64{15,16}},fields,33,False{},False{},True{},19n}
  E.View{RNG.Legacy{RNG.Bits64{50,60}},RNG.Bits64{70,80},81,100n,[E.Item{c,I.InvStack{I.ItemKey{"minecraft:cooked_beef",""},17},177,31,7,Some{E.Uuid{RNG.Bits64{3,4},RNG.Bits64{5,6}}},None{},0.5}]}
def authority_scan(+catalog:Model.Catalog,+scan:Nat,tables:Sine.Tables) -> Sine.Tables & J.Value:
  +view = authority_view()
  capture_checked(Render.capture(Model.Context{"minecraft:overworld",V.zero_vector(),0.25,Model.Quaternion{0.0,0.0,0.0,1.0},catalog,[Model.Light{71,0,15,4294967295,4294967295}],scan,4096n},E.install(view),tables),view)
def authority_second(first:J.Value,pair:Sine.Tables & J.Value) -> Sine.Tables & J.Value:
  (tables,second) = pair
  (tables,J.JArray{[first,second]})
def authority_pair(+catalog:Model.Catalog,pair:Sine.Tables & J.Value) -> Sine.Tables & J.Value:
  (tables,first) = pair
  authority_second(first,authority_scan(catalog,0n,tables))
def authority(+catalog:Model.Catalog,tables:Sine.Tables) -> Sine.Tables & J.Value:
  authority_pair(catalog,authority_scan(catalog,100n,tables))
def completed_owner(assets:Resources.Assets,catalog:Model.Catalog,outputs:List<&2,J.Value>,pair:Sine.Tables & J.Value) -> J.Value:
  Model.Catalog{items,count,orb} = catalog
  (tables,owner) = pair
  T.obj([J.JMember{"grounds",J.JArray{grounds(items)}},J.JMember{"cases",J.JArray{outputs}},J.JMember{"texture_count",T.num(count)},J.JMember{"retained_authority",owner},J.JMember{"texture_samples",pixels(assets)}])
def complete(assets:Resources.Assets,+catalog:Model.Catalog,pair:Sine.Tables & List<&2,J.Value>) -> J.Value:
  (tables,outputs) = pair
  completed_owner(assets,catalog,outputs,authority(catalog,tables))
def prepared(pair:Resources.Assets & Model.Catalog,values:List<&2,J.Value>,tables:Sine.Tables) -> J.Value:
  (assets,+catalog) = pair
  complete(assets,catalog,cases(values,catalog,tables))
def loaded(result:Result<&2,&1,String,Resources.Assets>,values:List<&2,J.Value>,tables:Sine.Tables) -> IO(Unit):
  match result:
    case Fail{message}: IO.print(J.encode(T.obj([J.JMember{"error",T.txt(message)}])))
    case Done{assets}: IO.print(J.encode(prepared(Resources.inspect(assets),values,tables)))
def tables_ready(result:Result<&2,&1,Sine.Error,Sine.Tables>,definitions:Definitions.Catalog,jar:String,values:List<&2,J.Value>) -> IO(Unit):
  match result:
    case Fail{error}: IO.print("sine load failed")
    case Done{tables}:
      do IO<Unit>:
        result : Result<&2,&1,String,Resources.Assets> <- Resources.load(jar,definitions,[I.ItemKey{"minecraft:stone",""},I.ItemKey{"minecraft:cooked_beef",""},I.ItemKey{"minecraft:iron_ingot",""},I.ItemKey{"minecraft:suspicious_stew",""}],BR.defaults())
        loaded(result,values,tables)
def initialized(definitions:Definitions.Catalog,defaults:List<&2,Components.Default>,jar:String,sine:String,values:List<&2,J.Value>) -> Result<&2,&2,String,Input>:
  Done{Input{Definitions.with_initialized_defaults(definitions,defaults),jar,sine,values}}
def input(+value:J.Value) -> Result<&2,&2,String,Input>:
  do Result<&2,&2,String,Input>:
    +raw : J.Value <- Decode.field(value,"catalog")
    raw_items : J.Value <- Decode.field(raw,"items")
    items : List<&2,J.Value> <- Decode.array(raw_items)
    defaults : List<&2,Components.Default> <- Decode.defaults_rows(items,[])
    item_table : String <- Decode.text_field(value,"item_table")
    definitions : Definitions.Catalog <- Definitions.parse(item_table)
    jar : String <- Decode.text_field(value,"jar")
    sine : String <- Decode.text_field(value,"sine")
    values : List<&2,J.Value> <- T.array_field(value,"cases")
    initialized(definitions,defaults,jar,sine,values)

def input_ready(value:Result<&2,&2,String,Input>) -> IO(Unit):
  match value:
    case Fail{message}: IO.print(message)
    case Done{Input{definitions,jar,sine,values}}:
      do IO<Unit>:
        tables : Result<&2,&1,Sine.Error,Sine.Tables> <- Sine.Tables.load(sine)
        tables_ready(tables,definitions,jar,values)
def parsed(value:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match value:
    case Fail{message}: IO.print(message)
    case Done{value}: input_ready(input(value))

def read_result(value:Result<&1,&1,U32 & String,String>) -> IO(Unit):
  match value:
    case Fail{error}: IO.print("read failed")
    case Done{text}: parsed(J.parse_bounded(text,16777216n,255))

def read(pair:File & Result<&1,&1,U32 & String,String>) -> IO(Unit):
  (file,value) = pair
  do IO<Unit>:
    File.close(file)
    read_result(value)

def opened(value:Result<&1,&1,U32 & String,File>) -> IO(Unit):
  match value:
    case Fail{error}: IO.print("input open failed")
    case Done{file}:
      do IO<Unit>:
        pair : File & Result<&1,&1,U32 & String,String> <- File.read(file,16777216)
        read(pair)
def args_ready(args:List<&1,String>) -> IO(Unit):
  match args:
    case exe <> path <> Nil{}:
      do IO<Unit>:
        result : Result<&1,&1,U32 & String,File> <- File.open(path,"r")
        opened(result)
    case _: IO.print("input path required")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<&1,String> <- IO.args()
    args_ready(args)
