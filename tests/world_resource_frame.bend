import Base
import ../src/world_resource_frame.bend as WRF
import ../src/resource_frame.bend as RF
import ../src/client_render.bend as R
import ../src/client_world.bend as W
import ../src/world_visibility.bend as V
import ../src/world_mesh.bend as WM
import ../src/mesh_render.bend as M
import ../src/block_bake.bend as K
import ../src/block_resources.bend as BR
import ../src/block_model.bend as B
import ../src/movement.bend as MV
import ../src/f64.bend as F
import ../src/json.bend as J
import ../src/unicode.bend as Unicode
import ../src/png.bend as P
import ../src/compression.bend as C

# No test-module imports. Only the Sample DTO is handed across native entries;
# RF.Assets is produced by RF.load and retained in this same Bend process.
type Fault is Data:
  Normal{}
  SceneOnly{}
  BadTexture{}
  MissingBinding{}
  BadMaterial{}
type Case is Data:
  Case{id:String,sample:V.Sample,draw:WRF.DrawConfig,output:String,fault:Fault}
type Input is Data:
  Input{jar:String,palette:RF.Palette,cases:List<&2,Case>}

# These exact word decoders preserve the previously checked WV native DTO.
# Test tick/revision fields are explicitly U32, not arbitrary native Nat text.
def f32_bits(value:U32) -> F32:
  match value:
    case U32{word}: F32{word}
def position64(values:List<&2,U32>) -> Result<&2,&2,B.Error,MV.Vec3>:
  match values:
    case [xh,xl,yh,yl,zh,zl]: Done{MV.Vec3{F.F64{xh,xl},F.F64{yh,yl},F.F64{zh,zl}}}
    case _: B.fail(MV.Vec3,"Position6","dto")
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

def fault(text:String) -> Result<&2,&2,B.Error,Fault>:
  match text:
    case "normal": Done{Normal{}}
    case "scene-only": Done{SceneOnly{}}
    case "bad-texture": Done{BadTexture{}}
    case "missing-binding": Done{MissingBinding{}}
    case "bad-material": Done{BadMaterial{}}
    case _: B.fail(Fault,"Fault","case")
def limits(value:Maybe<&2,J.Value>) -> Result<&2,&2,B.Error,WM.Limits>:
  match value:
    case None{}: Done{WM.defaults()}
    case Some{J.JArray{[a,b,c,d,e]}}:
      do Result<&2,&2,B.Error,WM.Limits>:
        blocks : U32 <- u32(a)
        bindings : U32 <- u32(b)
        quads : U32 <- u32(c)
        translucent : U32 <- u32(d)
        tints : U32 <- u32(e)
        Done{WM.Limits{blocks,bindings,quads,translucent,tints}}
    case _: B.fail(WM.Limits,"Limits5","case")
def output(value:Maybe<&2,J.Value>,id:String) -> Result<&2,&2,B.Error,String>:
  match value:
    case None{}: Done{"build/world-resource-frame/frames/" ++ id ++ ".ppm"}
    case Some{value}: B.strict_string(value,"output")
def one_case(+obj:J.Value,+samples:J.Value) -> Result<&2,&2,B.Error,Case>:
  do Result<&2,&2,B.Error,Case>:
    id_value : J.Value <- B.required(J.member(obj,"id"),"id")
    +id : String <- B.strict_string(id_value,"id")
    key_value : J.Value <- B.required(J.member(obj,"sample"),"sample")
    +key : String <- B.strict_string(key_value,"sample")
    sample_value : J.Value <- B.required(J.member(samples,key),key)
    sample : V.Sample <- dto_sample(sample_value)
    width_value : J.Value <- B.required(J.member(obj,"width"),"width")
    width : U32 <- u32(width_value)
    height_value : J.Value <- B.required(J.member(obj,"height"),"height")
    height : U32 <- u32(height_value)
    mode_value : J.Value <- B.required(J.member(obj,"mode"),"mode")
    mode : String <- B.strict_string(mode_value,"mode")
    bad : Fault <- fault(mode)
    mesh : WM.Limits <- limits(J.member(obj,"limits"))
    path : String <- output(J.member(obj,"output"),id)
    Done{Case{id,sample,WRF.DrawConfig{width,height,mesh},path,bad}}
def cases(values:List<&2,J.Value>,+samples:J.Value) -> Result<&2,&2,B.Error,List<&2,Case>>:
  match values:
    case Nil{}: Done{[]}
    case head <> tail:
      do Result<&2,&2,B.Error,List<&2,Case>>:
        first : Case <- one_case(head,samples)
        rest : List<&2,Case> <- cases(tail,samples)
        Done{first <> rest}
def input(+obj:J.Value) -> Result<&2,&2,B.Error,Input>:
  do Result<&2,&2,B.Error,Input>:
    jar_value : J.Value <- B.required(J.member(obj,"jar"),"jar")
    jar : String <- B.strict_string(jar_value,"jar")
    palette_value : J.Value <- B.required(J.member(obj,"palette"),"palette")
    palette : W.Palette <- dto_palette(palette_value)
    sample_value : J.Value <- B.required(J.member(obj,"samples"),"samples")
    samples : J.Value <- B.object(sample_value,"samples")
    cases_value : J.Value <- B.required(J.member(obj,"cases"),"cases")
    values : List<&2,J.Value> <- array_values(cases_value)
    views : List<&2,Case> <- cases(values,samples)
    Done{Input{jar,WRF.resource_palette(palette),views}}

def words(values:List<&2,U32>) -> String:
  match values:
    case Nil{}: ""
    case head <> Nil{}: U32.show(head)
    case head <> tail: U32.show(head) ++ "," ++ words(tail)
def vertex(value:M.Vertex) -> String:
  M.Vertex{M.Vec3{x,y,z},M.UV{u,v}} = value
  words([F32.bits(x),F32.bits(y),F32.bits(z),F32.bits(u),F32.bits(v)])
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
    words([texture,tint,light,F32.bits(shade)]) ++ "," ++ mode(kind) ++ "," ++ address(addr) ++ "," ++ cull(face) ++ "," ++ U32.show(order)
def quad_lines(values:List<&2,M.Quad>,+id:String,+index:U32) -> String:
  match values:
    case Nil{}: ""
    case head <> tail: "quad|" ++ id ++ "|" ++ U32.show(index) ++ "|" ++ quad(head) ++ "\n" ++ quad_lines(tail,id,U32.inc(index))
def scene_text(value:Result<&2,&2,String,M.Scene>,+id:String) -> String:
  match value:
    case Fail{message}: "scene-error|" ++ id ++ "|" ++ message ++ "\n"
    case Done{M.Scene{camera,+quads,settings}}:
      "scene|" ++ id ++ "|" ++ Nat.show(List.length(&2,M.Quad,quads)) ++ "\n" ++ quad_lines(quads,id,0)
def texture_headers(values:List<&2,R.Texture>) -> String:
  match values:
    case Nil{}: ""
    case R.Texture{width,height,side,image} <> tail: words([width,height,side]) ++ ";" ++ texture_headers(tail)
def info_text(info:RF.Info) -> String:
  RF.Info{bindings,count,RF.Palette{air,stone,dirt,planks},BR.Catalog{roots,source,models,sprites,context,BR.Usage{bm,bs,text,png,pixels}}} = info
  words([count,air,stone,dirt,planks]) ++ "|" ++ Nat.show(List.length(&2,WM.Binding,bindings)) ++ "|" ++
    Nat.show(List.length(&2,String,roots)) ++ "|" ++ Nat.show(List.length(&2,BR.SpriteInfo,sprites)) ++ "|" ++ words([bm,bs,text,png,pixels])
def marker(assets:RF.Assets,id:String,when:String) -> RF.Assets & String:
  RF.Assets{R.Assets{+textures},+bindings,+count,+palette,+catalog} = assets
  (RF.Assets{R.Assets{textures},bindings,count,palette,catalog},
    "assets|" ++ id ++ "|" ++ when ++ "|" ++ info_text(RF.Info{bindings,count,palette,catalog}) ++ "|" ++ texture_headers(textures))
def direction(value:B.Direction) -> U32:
  match value:
    case B.Down{}: 0
    case B.Up{}: 1
    case B.North{}: 2
    case B.South{}: 3
    case B.West{}: 4
    case B.East{}: 5
def group(value:Maybe<&2,B.Direction>) -> U32:
  match value:
    case None{}: 4294967295
    case Some{value}: direction(value)
def layer(value:K.Layer) -> U32:
  match value:
    case K.Solid{}: 0
    case K.Cutout{}: 1
    case K.Translucent{}: 2
def boolean(value:Bool) -> U32:
  match value:
    case False{}: 0
    case True{}: 1
def baked_lines(values:List<&2,K.Baked>,+state:U32,+index:U32) -> String:
  match values:
    case Nil{}: ""
    case K.Baked{a,b,c,d,dir,cf,sprite,slot,tint,emission,override,kind,force,animated,ds,ns} <> tail:
      "asset-baked|" ++ U32.show(state) ++ "|" ++ U32.show(index) ++ "|" ++ sprite ++ "|" ++
        vertex(a) ++ "," ++ vertex(b) ++ "," ++ vertex(c) ++ "," ++ vertex(d) ++ "|" ++
        words([direction(dir),group(cf),slot,tint,emission,group(override),layer(kind),boolean(force),boolean(animated),F32.bits(ds),F32.bits(ns)]) ++ "\n" ++
        baked_lines(tail,state,U32.inc(index))
def tint_lines(values:List<&2,WM.Tint>) -> String:
  match values:
    case Nil{}: ""
    case WM.Tint{index,color} <> tail: words([index,color]) ++ ";" ++ tint_lines(tail)
def binding_lines(values:List<&2,WM.Binding>) -> String:
  match values:
    case Nil{}: ""
    case WM.Binding{+state,faces,WM.Appearance{tints,light,addr,face,nether,threshold}} <> tail:
      "asset-binding|" ++ U32.show(state) ++ "|" ++ U32.show(light) ++ "," ++ address(addr) ++ "," ++ cull(face) ++ "," ++
        words([boolean(nether),threshold]) ++ "|" ++ tint_lines(tints) ++ "\n" ++ baked_lines(faces,state,0) ++ binding_lines(tail)
def texture_lines(values:List<&2,R.Texture>,+slot:U32) -> String:
  match values:
    case Nil{}: ""
    case R.Texture{+width,+height,side,image} <> tail:
      "asset-texture|" ++ U32.show(slot) ++ "|" ++ words([width,height,side]) ++ "|" ++ words(R.pixels_of(image,width,height)) ++ "\n" ++ texture_lines(tail,U32.inc(slot))
def audited(assets:RF.Assets) -> RF.Assets & String:
  RF.Assets{R.Assets{+textures},+bindings,count,palette,catalog} = assets
  (RF.Assets{R.Assets{textures},bindings,count,palette,catalog},texture_lines(textures,0) ++ binding_lines(bindings))
def reported(value:RF.Assets & String) -> IO(RF.Assets):
  (assets,text) = value
  do IO<RF.Assets>:
    IO.print(text)
    return assets

def bad_faces(values:List<&2,K.Baked>,count:U32) -> List<&2,K.Baked>:
  match values:
    case K.Baked{a,b,c,d,dir,cf,sprite,slot,tint,emission,override,layer,force,animated,ds,ns} <> tail:
      K.Baked{a,b,c,d,dir,cf,sprite,count,tint,emission,override,layer,force,animated,ds,ns} <> tail
    case _: []
def changed_bindings(fault:Fault,values:List<&2,WM.Binding>,count:U32) -> List<&2,WM.Binding>:
  match fault values:
    case MissingBinding{} head <> tail: tail
    case BadMaterial{} WM.Binding{state,faces,appearance} <> tail: WM.Binding{state,bad_faces(faces,count),appearance} <> tail
    case _ values: values
def changed_textures(fault:Fault,values:List<&2,R.Texture>) -> List<&2,R.Texture>:
  match fault values:
    case BadTexture{} R.Texture{width,height,side,image} <> tail: R.Texture{0,height,side,image} <> tail
    case _ values: values
def inspected(value:RF.Assets & RF.Info,test:Case) -> RF.Assets & String:
  (assets,RF.Info{bindings,+count,palette,catalog}) = value
  Case{id,sample,WRF.DrawConfig{width,height,limits},output,+bad} = test
  (assets,scene_text(WRF.scene(sample,RF.Info{changed_bindings(bad,bindings,count),count,palette,catalog},width,height,limits),id))
def capture_marker(status:Result<&2,&2,String,Image>,value:RF.Assets & String) -> RF.Assets & (Result<&2,&2,String,Image> & String):
  (assets,retained) = value
  (assets,(status,retained))
def captured(value:RF.Assets & Result<&2,&2,String,Image>,id:String) -> RF.Assets & (Result<&2,&2,String,Image> & String):
  (assets,status) = value
  capture_marker(status,marker(assets,id,"returned"))
def restored(value:RF.Assets & (Result<&2,&2,String,Image> & String),textures:List<&2,R.Texture>,bindings:List<&2,WM.Binding>) -> RF.Assets & (Result<&2,&2,String,Image> & String):
  (RF.Assets{R.Assets{discard},ignored,count,palette,catalog},status) = value
  (RF.Assets{R.Assets{textures},bindings,count,palette,catalog},status)
def draw_fault(bad:Fault,assets:RF.Assets,sample:V.Sample,config:WRF.DrawConfig,id:String) -> RF.Assets & (Result<&2,&2,String,Image> & String):
  match bad:
    case Normal{}: captured(WRF.draw_config(sample,assets,config),id)
    case +bad:
      RF.Assets{R.Assets{+textures},+bindings,+count,+palette,+catalog} = assets
      WRF.DrawConfig{width,height,limits} = config
      restored(captured(WRF.draw_with(sample,
        RF.Assets{R.Assets{changed_textures(bad,textures)},changed_bindings(bad,bindings,count),count,palette,catalog},
        width,height,limits),id),textures,bindings)
def draw_case(assets:RF.Assets,test:Case) -> RF.Assets & (Result<&2,&2,String,Image> & String):
  Case{id,sample,config,output,bad} = test
  draw_fault(bad,assets,sample,config,id)
def status(value:Result<&2,&2,String,Image>,test:Case) -> IO(Unit):
  match value:
    case Fail{message}:
      Case{id,sample,config,path,bad} = test
      IO.print("error|" ++ id ++ "|" ++ message)
    case Done{+image}:
      Case{+id,sample,WRF.DrawConfig{+width,+height,limits},+path,bad} = test
      do IO<Unit>:
        IO.print("checksum|" ++ id ++ "|" ++ U32.show(C.crc32(P.rgba_bytes(R.pixels_of(image,width,height)))))
        R.write_ppm(path,image,width,height)
        IO.print("frame|" ++ id ++ "|" ++ U32.show(width) ++ "|" ++ U32.show(height) ++ "|" ++ path)
def drawn(value:RF.Assets & (Result<&2,&2,String,Image> & String),test:Case) -> IO(RF.Assets):
  (assets,(image,retained)) = value
  do IO<RF.Assets>:
    IO.print(retained)
    status(image,test)
    return assets
def run_draw(bad:Fault,assets:RF.Assets,+test:Case) -> IO(RF.Assets):
  match bad:
    case SceneOnly{}: IO.pure(RF.Assets,assets)
    case _: drawn(draw_case(assets,test),test)
def one(+test:Case,assets:RF.Assets) -> IO(RF.Assets):
  Case{+id,sample,config,output,+bad} = test
  do IO<RF.Assets>:
    assets : RF.Assets <- reported(marker(assets,id,"before"))
    assets : RF.Assets <- reported(inspected(RF.info(assets),test))
    assets : RF.Assets <- run_draw(bad,assets,test)
    reported(marker(assets,id,"after"))
def frames(values:List<&2,Case>,assets:RF.Assets) -> IO(RF.Assets):
  match values:
    case Nil{}: IO.pure(RF.Assets,assets)
    case head <> tail:
      do IO<RF.Assets>:
        assets : RF.Assets <- one(head,assets)
        frames(tail,assets)
def loaded(value:Result<&2,&1,String,RF.Assets>,cases:List<&2,Case>) -> IO(Unit):
  match value:
    case Fail{message}: IO.die(Unit,1,"load-error|" ++ message)
    case Done{assets}:
      do IO<Unit>:
        assets : RF.Assets <- reported(audited(assets))
        assets : RF.Assets <- frames(cases,assets)
        RF.close_assets(assets)
def ready(value:Result<&2,&2,B.Error,Input>) -> IO(Unit):
  match value:
    case Fail{B.Error{code,path}}: IO.die(Unit,1,"DTO-error|" ++ code ++ "|" ++ path)
    case Done{Input{jar,palette,cases}}:
      do IO<Unit>:
        assets : Result<&2,&1,String,RF.Assets> <- RF.load(jar,palette)
        loaded(assets,cases)
def parsed(value:Result<&2,&2,String,J.Value>) -> IO(Unit):
  match value:
    case Fail{message}: IO.die(Unit,1,"JSON-error|" ++ message)
    case Done{value}: ready(input(value))
def text_ready(value:Result<&2,&2,String,String>) -> IO(Unit):
  match value:
    case Fail{message}: IO.die(Unit,1,"input-error|" ++ message)
    case Done{text}: parsed(J.parse_with(text,J.Limits{1048576n,64}))
def tail_read(bytes:List<&2,U32>,value:File & Result<&1,&1,U32 & String,List<&2,U32>>) -> IO(Result<&2,&2,String,String>):
  (file,status) = value
  match status:
    case Fail{(code,message)}:
      do IO<Result<&2,&2,String,String>>:
        File.close(file)
        return Fail{"Read:" ++ U32.show(code) ++ ":" ++ message}
    case Done{Nil{}}:
      do IO<Result<&2,&2,String,String>>:
        File.close(file)
        return Unicode.decode(1048576n,bytes)
    case Done{_}:
      do IO<Result<&2,&2,String,String>>:
        File.close(file)
        return Fail{"file exceeds 1048576 bytes"}
def first_read(value:File & Result<&1,&1,U32 & String,List<&2,U32>>) -> IO(Result<&2,&2,String,String>):
  (file,status) = value
  match status:
    case Fail{(code,message)}:
      do IO<Result<&2,&2,String,String>>:
        File.close(file)
        return Fail{"Read:" ++ U32.show(code) ++ ":" ++ message}
    case Done{bytes}:
      do IO<Result<&2,&2,String,String>>:
        tail : File & Result<&1,&1,U32 & String,List<&2,U32>> <- File.read_bytes(file,1)
        tail_read(bytes,tail)
def opened(value:Result<&1,&1,U32 & String,File>) -> IO(Result<&2,&2,String,String>):
  match value:
    case Fail{(code,message)}: IO.pure(Result<&2,&2,String,String>,Fail{"Open:" ++ U32.show(code) ++ ":" ++ message})
    case Done{file}:
      do IO<Result<&2,&2,String,String>>:
        first : File & Result<&1,&1,U32 & String,List<&2,U32>> <- File.read_bytes(file,1048576)
        first_read(first)
def arguments(value:List<String>) -> IO(Unit):
  match value:
    case program <> path <> Nil{}:
      do IO<Unit>:
        file : Result<&1,&1,U32 & String,File> <- File.open(path,"r")
        text : Result<&2,&2,String,String> <- opened(file)
        text_ready(text)
    case _: IO.die(Unit,2,"one checked JSON input file required")
def main() -> IO(Unit):
  IO.bind(List<String>,Unit,IO.args(),arguments)
