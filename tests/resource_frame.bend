import Base
import ../src/resource_frame.bend as RF
import ../src/client_render.bend as R
import ../src/world_mesh.bend as WM
import ../src/mesh_render.bend as M
import ../src/block_bake.bend as K
import ../src/block_resources.bend as BR
import ../src/json.bend as J
import ../src/f64.bend as F
import ../src/png.bend as P
import ../src/compression.bend as C

# Narrow native driver: no imports of another test or of W/Game/Server.
type Origin is Data:
  Origin{x:F.F64,y:F.F64,z:F.F64}
type View is Data:
  View{id:String,snapshot:R.Snapshot,width:U32,height:U32,path:String,corrupt:Bool}
type Config is Data:
  Config{path:String,palette:RF.Palette,views:List<&2,View>}

def number_result(value:Maybe<&2,U32>,fallback:U32) -> U32:
  match value:
    case Some{v}: v
    case _: fallback
def integer(value:Maybe<&2,J.Value>,fallback:U32) -> U32:
  match value:
    case Some{v}: number_result(J.as_u32(v),fallback)
    case _: fallback
def number(value:J.Value) -> U32:
  number_result(J.as_u32(value),0)
def string(value:Maybe<&2,J.Value>,fallback:String) -> String:
  match value:
    case Some{J.JString{s}}: s
    case _: fallback
def array(value:Maybe<&2,J.Value>) -> List<&2,J.Value>:
  match value:
    case Some{J.JArray{values}}: values
    case _: []
def raw(n:U32) -> F32:
  match n:
    case U32{word}: F32{word}
def word(value:F32) -> String:
  U32.show(F32.bits(value))
def f64(value:J.Value) -> F.F64:
  match value:
    case J.JArray{[hi,lo]}: F.from_bits(number(hi),number(lo))
    case _: F.from_bits(0,0)
def origin(value:Maybe<&2,J.Value>) -> Maybe<&2,Origin>:
  match value:
    case Some{J.JArray{[x,y,z]}}: Some{Origin{f64(x),f64(y),f64(z)}}
    case _: None{}
def block(value:J.Value,eye:Maybe<&2,Origin>) -> R.Block:
  match value eye:
    case J.JArray{[x,y,z,state,material]} None{}:
      R.Block{raw(number(x)),raw(number(y)),raw(number(z)),number(state),number(material)}
    case J.JArray{[x,y,z,state,material]} Some{Origin{ox,oy,oz}}:
      R.Block{F.to_f32(F.sub(F.from_i32(number(x)),ox)),
        F.to_f32(F.sub(F.from_i32(number(y)),oy)),
        F.to_f32(F.sub(F.from_i32(number(z)),oz)),number(state),number(material)}
    case _ _: R.Block{0.0,0.0,0.0,4294967295,0}
def blocks(values:List<&2,J.Value>,+eye:Maybe<&2,Origin>) -> List<&2,R.Block>:
  match values:
    case Nil{}: []
    case head <> tail: block(head,eye) <> blocks(tail,eye)
def camera(values:List<&2,J.Value>) -> R.Camera:
  match values:
    case [x,y,z,yaw,pitch]: R.Camera{raw(number(x)),raw(number(y)),raw(number(z)),raw(number(yaw)),raw(number(pitch))}
    case _: R.Camera{0.0,0.0,0.0,0.0,0.2}
def view(+value:J.Value) -> View:
  View{string(J.member(value,"id"),"frame"),
    R.Snapshot{U32.to_nat(integer(J.member(value,"tick"),1)),U32.to_nat(integer(J.member(value,"revision"),47)),
      blocks(array(J.member(value,"blocks")),origin(J.member(value,"origin"))),camera(array(J.member(value,"camera")))},
    integer(J.member(value,"width"),32),integer(J.member(value,"height"),24),
    string(J.member(value,"output"),"build/resource-frame/frame.ppm"),
    String.eq(string(J.member(value,"mode"),""),"bad-texture")}
def palette(value:Maybe<&2,J.Value>) -> RF.Palette:
  match value:
    case Some{J.JArray{[a,s,d,p]}}: RF.Palette{number(a),number(s),number(d),number(p)}
    case _: RF.Palette{0,1,2,3}

def numbers(values:List<&2,U32>) -> String:
  match values:
    case Nil{}: ""
    case value <> Nil{}: U32.show(value)
    case value <> rest: U32.show(value) ++ "," ++ numbers(rest)
def vertex(value:M.Vertex) -> String:
  M.Vertex{M.Vec3{x,y,z},M.UV{u,v}} = value
  word(x) ++ "," ++ word(y) ++ "," ++ word(z) ++ "," ++ word(u) ++ "," ++ word(v)
def mode(value:M.Mode) -> String:
  match value:
    case M.Opaque{}: "0,0"
    case M.Cutout{threshold}: "1," ++ U32.show(threshold)
    case M.Translucent{}: "2,0"
def address(value:M.Address) -> String:
  match value:
    case M.Clamp{}: "0"
    case M.Repeat{}: "1"
def cull(value:M.Cull) -> String:
  match value:
    case M.NoCull{}: "0"
    case M.Back{}: "1"
def quad(value:M.Quad) -> String:
  M.Quad{a,b,c,d,M.Material{texture,tint,light,shade,kind,addr},face,order} = value
  vertex(a) ++ "," ++ vertex(b) ++ "," ++ vertex(c) ++ "," ++ vertex(d) ++ "," ++
    U32.show(texture) ++ "," ++ U32.show(tint) ++ "," ++ U32.show(light) ++ "," ++ word(shade) ++ "," ++
    mode(kind) ++ "," ++ address(addr) ++ "," ++ cull(face) ++ "," ++ U32.show(order)
def quads(values:List<&2,M.Quad>,+id:String,+index:U32) -> String:
  match values:
    case Nil{}: ""
    case head <> tail: "quad|" ++ id ++ "|" ++ U32.show(index) ++ "|" ++ quad(head) ++ "\n" ++ quads(tail,id,U32.inc(index))
def baked(values:List<&2,K.Baked>,+state:U32,+index:U32) -> String:
  match values:
    case Nil{}: ""
    case +head <> tail:
      K.Baked{a,b,c,d,dir,cf,sprite,slot,tint,emission,override,layer,force,animated,ds,ns} = head
      "baked|" ++ U32.show(state) ++ "|" ++ U32.show(index) ++ "|" ++ sprite ++ "|" ++
        quad(K.mesh(head,K.Appearance{4294967295,4294967295,M.Clamp{},M.Back{},False{},128},0)) ++ "\n" ++ baked(tail,state,U32.inc(index))
def binding_records(values:List<&2,WM.Binding>) -> String:
  match values:
    case Nil{}: ""
    case WM.Binding{state,faces,appearance} <> tail: baked(faces,state,0) ++ binding_records(tail)
def texture_records(textures:List<&2,R.Texture>,sprites:List<&2,BR.SpriteInfo>) -> String:
  match textures sprites:
    case R.Texture{+width,+height,side,+image} <> tail BR.SpriteInfo{id,slot,w,h,layer,meta} <> rest:
      "texture|" ++ id ++ "|" ++ U32.show(slot) ++ "|" ++ U32.show(width) ++ "," ++ U32.show(height) ++ "," ++ U32.show(side) ++ "|" ++
        numbers(R.pixels_of(image,width,height)) ++ "\n" ++ texture_records(tail,rest)
    case _ _: ""
def catalog_sprites(value:BR.Catalog) -> List<&2,BR.SpriteInfo>:
  BR.Catalog{roots,source,models,sprites,context,usage} = value
  sprites
def report_assets(assets:RF.Assets) -> RF.Assets & String:
  RF.Assets{R.Assets{+textures},+bindings,+count,+palette,+catalog} = assets
  RF.Palette{air,stone,dirt,planks} = palette
  (RF.Assets{R.Assets{textures},bindings,count,palette,catalog},
    "assets|" ++ U32.show(count) ++ "|" ++ numbers([air,stone,dirt,planks]) ++ "\n" ++
      texture_records(textures,catalog_sprites(catalog)) ++ binding_records(bindings))
def blocks_text(values:List<&2,R.Block>) -> String:
  match values:
    case Nil{}: ""
    case R.Block{x,y,z,state,material} <> tail:
      word(x) ++ "," ++ word(y) ++ "," ++ word(z) ++ "," ++ U32.show(state) ++ "," ++ U32.show(material) ++ ";" ++ blocks_text(tail)
def snapshot_text(snapshot:R.Snapshot,id:String) -> String:
  R.Snapshot{tick,revision,blocks,R.Camera{x,y,z,yaw,pitch}} = snapshot
  "snapshot|" ++ id ++ "|" ++ Nat.show(tick) ++ "|" ++ Nat.show(revision) ++ "|" ++
    numbers([F32.bits(x),F32.bits(y),F32.bits(z),F32.bits(yaw),F32.bits(pitch)]) ++ "|" ++ blocks_text(blocks)
def scene_text(result:Result<&2,&2,WM.Error,M.Scene>,id:String) -> String:
  match result:
    case Fail{error}: ""
    case Done{M.Scene{camera,values,settings}}: quads(values,id,0)
def inspected(value:RF.Assets & RF.Info,+view:View) -> RF.Assets & String:
  (assets,RF.Info{bindings,count,palette,catalog}) = value
  View{id,snapshot,width,height,path,corrupt} = view
  (assets,scene_text(WM.produce(snapshot,bindings,count,WM.frame(width,height),WM.defaults()),id))
def corrupt_textures(values:List<&2,R.Texture>) -> List<&2,R.Texture>:
  match values:
    case R.Texture{w,h,side,image} <> tail: R.Texture{0,h,side,image} <> tail
    case _: []
def restored(value:RF.Assets & Result<&2,&2,String,Image>,textures:List<&2,R.Texture>) -> RF.Assets & Result<&2,&2,String,Image>:
  (RF.Assets{R.Assets{discard},bindings,count,palette,catalog},status) = value
  (RF.Assets{R.Assets{textures},bindings,count,palette,catalog},status)
def draw_forced(assets:RF.Assets,snapshot:R.Snapshot,width:U32,height:U32) -> RF.Assets & Result<&2,&2,String,Image>:
  RF.Assets{R.Assets{+textures},bindings,count,palette,catalog} = assets
  restored(RF.draw(snapshot,RF.Assets{R.Assets{corrupt_textures(textures)},bindings,count,palette,catalog},width,height),textures)
def draw_view(assets:RF.Assets,view:View) -> RF.Assets & Result<&2,&2,String,Image>:
  View{id,snapshot,width,height,path,corrupt} = view
  match corrupt:
    case False{}: RF.draw(snapshot,assets,width,height)
    case True{}: draw_forced(assets,snapshot,width,height)
def measured(+image:Image,+id:String,+path:String,+width:U32,+height:U32,before:Nat) -> IO(Unit):
  do IO<Unit>:
    IO.print("checksum|" ++ id ++ "|" ++ U32.show(C.crc32(P.rgba_bytes(R.pixels_of(image,width,height)))))
    ended : Nat <- IO.now()
    IO.print("time|" ++ id ++ "|" ++ Nat.show(Nat.sub(ended,before)))
    R.write_ppm(path,image,width,height)
    IO.print("frame|" ++ id ++ "|" ++ U32.show(width) ++ "|" ++ U32.show(height) ++ "|" ++ path)
def status(result:Result<&2,&2,String,Image>,+view:View,before:Nat) -> IO(Unit):
  match result:
    case Fail{message}:
      View{id,snapshot,width,height,path,corrupt} = view
      IO.print("error|" ++ id ++ "|" ++ message)
    case Done{image}:
      View{id,snapshot,width,height,path,corrupt} = view
      measured(image,id,path,width,height,before)
def drawn(value:RF.Assets & Result<&2,&2,String,Image>,view:View,before:Nat) -> IO(RF.Assets):
  (assets,result) = value
  do IO<RF.Assets>:
    status(result,view,before)
    return assets
# Each entry keeps a narrow, typed input across archive and frame effects.
# Separate audit/geometry/frame roots prevent diagnostic serializers from
# expanding into the actual draw entry; every production call is unchanged.
def frame_draw(+v:View,assets:RF.Assets) -> IO(RF.Assets):
  View{id,+snapshot,width,height,path,corrupt} = v
  do IO<RF.Assets>:
    IO.print(snapshot_text(snapshot,id))
    before : Nat <- IO.now()
    drawn(draw_view(assets,v),v,before)
def frames(values:List<&2,View>,assets:RF.Assets) -> IO(RF.Assets):
  match values:
    case Nil{}: IO.pure(RF.Assets,assets)
    case head <> tail:
      do IO<RF.Assets>:
        assets : RF.Assets <- frame_draw(head,assets)
        frames(tail,assets)
def draw_loaded(result:Result<&2,&1,String,RF.Assets>,views:List<&2,View>) -> IO(Unit):
  match result:
    case Fail{error}: IO.print("load-error|" ++ error)
    case Done{assets}:
      do IO<Unit>:
        assets : RF.Assets <- frames(views,assets)
        RF.close_assets(assets)
def audit_reported(value:RF.Assets & String) -> IO(Unit):
  (assets,report) = value
  do IO<Unit>:
    IO.print(report)
    RF.close_assets(assets)
def audit_loaded(result:Result<&2,&1,String,RF.Assets>) -> IO(Unit):
  match result:
    case Fail{error}: IO.print("load-error|" ++ error)
    case Done{assets}: audit_reported(report_assets(assets))
def geometry_one(value:RF.Assets & String) -> IO(RF.Assets):
  (assets,report) = value
  do IO<RF.Assets>:
    IO.print(report)
    return assets
def geometry_frames(values:List<&2,View>,assets:RF.Assets) -> IO(RF.Assets):
  match values:
    case Nil{}: IO.pure(RF.Assets,assets)
    case head <> tail:
      do IO<RF.Assets>:
        assets : RF.Assets <- geometry_one(inspected(RF.info(assets),head))
        geometry_frames(tail,assets)
def geometry_loaded(result:Result<&2,&1,String,RF.Assets>,views:List<&2,View>) -> IO(Unit):
  match result:
    case Fail{error}: IO.print("load-error|" ++ error)
    case Done{assets}:
      do IO<Unit>:
        assets : RF.Assets <- geometry_frames(views,assets)
        RF.close_assets(assets)
def parsed_views(values:List<&2,J.Value>) -> List<&2,View>:
  match values:
    case Nil{}: []
    case head <> tail: view(head) <> parsed_views(tail)
def parsed_config(+value:J.Value) -> Config:
  Config{string(J.member(value,"path"),""),palette(J.member(value,"palette")),
    parsed_views(array(J.member(value,"views")))}
def draw_config(value:Config) -> IO(Unit):
  Config{path,palette,views} = value
  do IO<Unit>:
    assets : Result<&2,&1,String,RF.Assets> <- RF.load(path,palette)
    draw_loaded(assets,views)
def audit_config(value:Config) -> IO(Unit):
  Config{path,palette,views} = value
  do IO<Unit>:
    assets : Result<&2,&1,String,RF.Assets> <- RF.load(path,palette)
    audit_loaded(assets)
def geometry_config(value:Config) -> IO(Unit):
  Config{path,palette,views} = value
  do IO<Unit>:
    assets : Result<&2,&1,String,RF.Assets> <- RF.load(path,palette)
    geometry_loaded(assets,views)
def draw_parsed(value:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match value:
    case Fail{message}: IO.die(Unit,1,message)
    case Done{value}: draw_config(parsed_config(value))
def audit_parsed(value:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match value:
    case Fail{message}: IO.die(Unit,1,message)
    case Done{value}: audit_config(parsed_config(value))
def geometry_parsed(value:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match value:
    case Fail{message}: IO.die(Unit,1,message)
    case Done{value}: geometry_config(parsed_config(value))
def arguments(args:List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case text <> rest:
      do IO<Unit>:
        draw_parsed(J.parse_with(text,J.Limits{1048576n,255}))
        arguments(rest)
def audit_arguments(args:List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case text <> rest:
      do IO<Unit>:
        audit_parsed(J.parse_with(text,J.Limits{1048576n,255}))
        audit_arguments(rest)
def geometry_arguments(args:List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case text <> rest:
      do IO<Unit>:
        geometry_parsed(J.parse_with(text,J.Limits{1048576n,255}))
        geometry_arguments(rest)
def drop_program(args:List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case program <> rest: arguments(rest)
def audit_drop_program(args:List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case program <> rest: audit_arguments(rest)
def geometry_drop_program(args:List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case program <> rest: geometry_arguments(rest)
def audit_main() -> IO(Unit):
  IO.bind(List<String>,Unit,IO.args(),audit_drop_program)
def geometry_main() -> IO(Unit):
  IO.bind(List<String>,Unit,IO.args(),geometry_drop_program)
def main() -> IO(Unit):
  IO.bind(List<String>,Unit,IO.args(),drop_program)
