import Base
import ./client_render.bend as R
import ./mesh_render.bend as M
import ./block_bake.bend as K
import ./png.bend as P

# Pure camera-relative snapshot producer. Model/state selection and lighting
# remain explicit inputs. Neighbor cull groups never discard a face here.
type Tint is Data:
  Tint{index:U32,color:U32}
type Appearance is Data:
  Appearance{tints:List<&2,Tint>,light:U32,address:M.Address,cull:M.Cull,
    nether:Bool,cutout_threshold:U32}
type Binding is Data:
  Binding{state:U32,baked:List<&2,K.Baked>,appearance:Appearance}
type Frame is Data:
  Frame{width:U32,height:U32,settings:M.Settings}
type Limits is Data:
  Limits{max_blocks:U32,max_bindings:U32,max_quads:U32,
    max_translucent:U32,max_tints:U32}
type Error is Data:
  Error{code:String,state:U32}
type Accumulator is Data:
  Accumulator{reversed:List<&2,M.Quad>,count:U32,translucent:U32}
type Surface is Data:
  Surface{material:M.Material,cull:M.Cull,order:U32}

def defaults() -> Limits:
  Limits{4096,1024,4096,64,256}
def appearance() -> Appearance:
  Appearance{[],4294967295,M.Clamp{},M.Back{},False{},128}
def frame(width:U32,height:U32) -> Frame:
  Frame{width,height,M.defaults()}

def limits_valid(value:Limits) -> Bool:
  Limits{blocks,bindings,quads,translucent,tints} = value
  U32.is_le(blocks,4096) && U32.is_le(bindings,4096) &&
    U32.is_le(quads,4096) && U32.is_le(translucent,64) && U32.is_le(tints,4096)

def relative_camera(+camera:R.Camera) -> Bool:
  R.Camera{x,y,z,yaw,pitch} = camera
  M.camera_valid(camera) && F32.is_eq(x,0.0) && F32.is_eq(y,0.0) && F32.is_eq(z,0.0)

def frame_valid(value:Frame) -> Bool:
  Frame{+width,+height,settings} = value
  M.dimensions(width,height) && M.settings_valid(settings)

def fits(-A:Data,values:List<&2,A>,+remaining:U32) -> Bool:
  match values:
    case Nil{}: True{}
    case head <> tail: U32.is_gt(remaining,0) && fits(A,tail,U32.sub(remaining,1))

def has_tint(values:List<&2,Tint>,+index:U32) -> Bool:
  match values:
    case Nil{}: False{}
    case Tint{current,color} <> tail: U32.is_eq(current,index) || has_tint(tail,index)

def tints_valid(values:List<&2,Tint>,+remaining:U32) -> Bool:
  match values:
    case Nil{}: True{}
    case Tint{+index,color} <> +tail:
      U32.is_gt(remaining,0) && U32.is_ne(index,4294967295) &&
        Bool.not(has_tint(tail,index)) && tints_valid(tail,U32.sub(remaining,1))

def appearance_valid(value:Appearance,+max_tints:U32) -> Bool:
  Appearance{+tints,light,address,cull,nether,threshold} = value
  U32.is_eq(U32.shrn(light,24n),255) && U32.is_le(threshold,255) &&
    fits(Tint,tints,max_tints) && tints_valid(tints,max_tints)

def tint_lookup(values:List<&2,Tint>,+index:U32) -> Maybe<&2,U32>:
  match values:
    case Nil{}: None{}
    case Tint{current,color} <> tail:
      P.choose(Maybe<&2,U32>,Some{color},tint_lookup(tail,index),U32.is_eq(current,index))

def tint(value:Appearance,+index:U32) -> Maybe<&2,U32>:
  Appearance{tints,light,address,cull,nether,threshold} = value
  P.choose(Maybe<&2,U32>,Some{4294967295},tint_lookup(tints,index),U32.is_eq(index,4294967295))

def mesh_appearance(value:Appearance,color:U32) -> K.Appearance:
  Appearance{tints,light,address,cull,nether,threshold} = value
  K.Appearance{color,light,address,cull,nether,threshold}

def translate_vertex(value:M.Vertex,origin:M.Vec3) -> M.Vertex:
  match value origin:
    case M.Vertex{M.Vec3{x,y,z},uv} M.Vec3{ox,oy,oz}:
      M.Vertex{M.Vec3{F32.add(x,ox),F32.add(y,oy),F32.add(z,oz)},uv}

def translate_quad(value:M.Quad,+origin:M.Vec3) -> M.Quad:
  M.Quad{a,b,c,d,material,cull,order} = value
  M.Quad{translate_vertex(a,origin),translate_vertex(b,origin),
    translate_vertex(c,origin),translate_vertex(d,origin),material,cull,order}

def vertex_uv(value:M.Vertex) -> M.UV:
  M.Vertex{position,uv} = value
  uv
def surface(value:M.Quad) -> Surface:
  M.Quad{a,b,c,d,material,cull,order} = value
  Surface{material,cull,order}

law translated_vertex_preserves_uv:
  for position:M.Vec3
  for +uv:M.UV
  for origin:M.Vec3
  {vertex_uv(translate_vertex(M.Vertex{position,uv},origin)) == uv : M.UV}

def translated_vertex_preserves_uv(position,uv,origin):
  match position origin:
    case M.Vec3{x,y,z} M.Vec3{ox,oy,oz}: {==}

law translated_quad_preserves_surface:
  for a:M.Vertex
  for b:M.Vertex
  for c:M.Vertex
  for d:M.Vertex
  for +material:M.Material
  for +cull:M.Cull
  for +order:U32
  for origin:M.Vec3
  {surface(translate_quad(M.Quad{a,b,c,d,material,cull,order},origin)) == Surface{material,cull,order} : Surface}

def translated_quad_preserves_surface(a,b,c,d,material,cull,order,origin):
  {==}

def quad_valid(value:M.Quad,textures:U32) -> Bool:
  M.Quad{a,b,c,d,material,cull,order} = value
  M.valid_vertex(a) && M.valid_vertex(b) && M.valid_vertex(c) &&
    M.valid_vertex(d) && M.valid_material(material,textures)

def forced_layer(layer:K.Layer,force:Bool) -> Bool:
  match layer:
    case K.Translucent{}: True{}
    case _: Bool.not(force)

def baked_error(+value:K.Baked,+appearance:Appearance,textures:U32) -> String:
  K.Baked{a,b,c,d,direction,cf,sprite,texture,+index,emission,override,+layer,+force,+animated,ds,ns} = value
  P.choose(String,"UnsupportedAnimation",P.choose(String,"BakedMetadata",
    P.choose(String,"MissingTint",P.choose(String,"BakedQuad","",
      Bool.not(quad_valid(K.mesh(value,mesh_appearance(appearance,4294967295),0),textures))),
      Maybe.is_none(&2,U32,tint(appearance,index))),
    U32.is_gt(emission,15) || Bool.not(forced_layer(layer,force))),animated)

def checked_baked(error:String) -> Result<&2,&2,String,Unit>:
  match error:
    case "": Done{Unit{}}
    case error: Fail{error}

def baked_check(values:List<&2,K.Baked>,+appearance:Appearance,+textures:U32,+remaining:U32) -> Result<&2,&2,String,U32>:
  match values:
    case Nil{}: Done{remaining}
    case head <> tail:
      do Result<&2,&2,String,U32>:
        unit : Unit <- checked_baked(baked_error(head,appearance,textures))
        P.choose(Result<&2,&2,String,U32>,Fail{"SourceQuadLimit"},
          baked_check(tail,appearance,textures,U32.sub(remaining,1)),U32.is_eq(remaining,0))

def has_state(bindings:List<&2,Binding>,+state:U32) -> Bool:
  match bindings:
    case Nil{}: False{}
    case Binding{current,baked,appearance} <> tail: U32.is_eq(current,state) || has_state(tail,state)

def bindings_check(bindings:List<&2,Binding>,+textures:U32,+remaining:U32,+quads:U32,+max_tints:U32) -> Result<&2,&2,String,Unit>:
  match bindings:
    case Nil{}: Done{Unit{}}
    case Binding{+state,baked,+appearance} <> +tail:
      do Result<&2,&2,String,Unit>:
        unit : Unit <- checked_baked(P.choose(String,"BindingLimit",P.choose(String,"DuplicateState",
          P.choose(String,"Appearance","",Bool.not(appearance_valid(appearance,max_tints))),
          has_state(tail,state)),U32.is_eq(remaining,0)))
        left : U32 <- baked_check(baked,appearance,textures,quads)
        bindings_check(tail,textures,U32.sub(remaining,1),left,max_tints)

def bindings_error(result:Result<&2,&2,String,Unit>) -> String:
  match result:
    case Fail{error}: error
    case Done{unit}: ""

def bindings_gate(valid:Bool,bindings:List<&2,Binding>,textures:U32,remaining:U32,quads:U32,max_tints:U32) -> String:
  match valid:
    case False{}: "BindingLimit"
    case True{}: bindings_error(bindings_check(bindings,textures,remaining,quads,max_tints))

def lookup(bindings:List<&2,Binding>,+state:U32) -> Maybe<&2,Binding>:
  match bindings:
    case Nil{}: None{}
    case +head <> tail:
      Binding{current,baked,appearance} = head
      P.choose(Maybe<&2,Binding>,Some{head},lookup(tail,state),U32.is_eq(current,state))

def add_valid(valid:Bool,+quad:M.Quad,acc:Accumulator,+limits:Limits,+state:U32) -> Result<&2,&2,Error,Accumulator>:
  match valid:
    case False{}: Fail{Error{"TranslatedQuad",state}}
    case True{}:
      M.Quad{a,b,c,d,+material,cull,order} = quad
      Accumulator{reversed,+count,+translucent} = acc
      Limits{blocks,bindings,+max_quads,+max_translucent,tints} = limits
      P.choose(Result<&2,&2,Error,Accumulator>,Fail{Error{"QuadLimit",state}},
        P.choose(Result<&2,&2,Error,Accumulator>,Fail{Error{"TranslucentLimit",state}},
          Done{Accumulator{quad <> reversed,U32.inc(count),U32.add(translucent,M.material_translucent(material))}},
          U32.is_ge(translucent,max_translucent) && U32.is_eq(M.material_translucent(material),1)),
        U32.is_ge(count,max_quads))

def translated(color:Maybe<&2,U32>,value:K.Baked,+appearance:Appearance,+origin:M.Vec3,+acc:Accumulator,textures:U32,limits:Limits,state:U32) -> Result<&2,&2,Error,Accumulator>:
  match color:
    case None{}: Fail{Error{"MissingTint",state}}
    case Some{color}:
      Accumulator{reversed,count,layers} = acc
      +quad = translate_quad(K.mesh(value,mesh_appearance(appearance,color),count),origin)
      add_valid(quad_valid(quad,textures),quad,acc,limits,state)

def baked_produce(values:List<&2,K.Baked>,+appearance:Appearance,+origin:M.Vec3,acc:Accumulator,+textures:U32,+limits:Limits,+state:U32) -> Result<&2,&2,Error,Accumulator>:
  match values:
    case Nil{}: Done{acc}
    case +head <> tail:
      K.Baked{a,b,c,d,direction,cf,sprite,texture,index,emission,override,layer,force,animated,ds,ns} = head
      do Result<&2,&2,Error,Accumulator>:
        acc : Accumulator <- translated(tint(appearance,index),head,appearance,origin,acc,textures,limits,state)
        baked_produce(tail,appearance,origin,acc,textures,limits,state)

def block_bound(block:R.Block) -> Bool:
  R.Block{x,y,z,state,material} = block
  M.valid_position(M.Vec3{x,y,z})

def bound_block(valid:Bool,block:R.Block,binding:Maybe<&2,Binding>,acc:Accumulator,textures:U32,limits:Limits) -> Result<&2,&2,Error,Accumulator>:
  match valid:
    case False{}: Fail{Error{"BlockOrigin",0}}
    case True{}:
      R.Block{x,y,z,+state,material} = block
      match binding:
        case None{}: Fail{Error{"MissingState",state}}
        case Some{Binding{current,baked,appearance}}:
          baked_produce(baked,appearance,M.Vec3{x,y,z},acc,textures,limits,state)

def blocks_produce(blocks:List<&2,R.Block>,+bindings:List<&2,Binding>,acc:Accumulator,+textures:U32,+limits:Limits,+remaining:U32) -> Result<&2,&2,Error,Accumulator>:
  match blocks:
    case Nil{}: Done{acc}
    case +head <> tail:
      R.Block{x,y,z,state,material} = head
      do Result<&2,&2,Error,Accumulator>:
        acc : Accumulator <- P.choose(Result<&2,&2,Error,Accumulator>,Fail{Error{"BlockLimit",state}},
          bound_block(block_bound(head),head,lookup(bindings,state),acc,textures,limits),U32.is_eq(remaining,0))
        blocks_produce(tail,bindings,acc,textures,limits,U32.sub(remaining,1))

def finish(result:Result<&2,&2,Error,Accumulator>,camera:R.Camera,settings:M.Settings) -> Result<&2,&2,Error,M.Scene>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Accumulator{reversed,count,layers}}:
      Done{M.Scene{camera,List.reverse(&2,M.Quad,reversed),settings}}

def produce_valid(error:String,snapshot:R.Snapshot,bindings:List<&2,Binding>,textures:U32,frame:Frame,+limits:Limits) -> Result<&2,&2,Error,M.Scene>:
  match error:
    case "":
      R.Snapshot{tick,revision,blocks,camera} = snapshot
      Frame{width,height,settings} = frame
      Limits{max_blocks,max_bindings,max_quads,max_translucent,max_tints} = limits
      finish(blocks_produce(blocks,bindings,Accumulator{[],0,0},textures,limits,max_blocks),camera,settings)
    case error: Fail{Error{error,0}}

def produce(+snapshot:R.Snapshot,+bindings:List<&2,Binding>,+texture_count:U32,+frame:Frame,+limits:Limits) -> Result<&2,&2,Error,M.Scene>:
  R.Snapshot{tick,revision,blocks,camera} = snapshot
  Limits{max_blocks,max_bindings,max_quads,max_translucent,max_tints} = limits
  produce_valid(P.choose(String,"Limits",P.choose(String,"Frame",P.choose(String,"RelativeCamera",
    P.choose(String,"TextureCount",bindings_gate(fits(Binding,bindings,max_bindings),bindings,texture_count,max_bindings,max_quads,max_tints),
      U32.is_eq(texture_count,0)),Bool.not(relative_camera(camera))),Bool.not(frame_valid(frame))),
    Bool.not(limits_valid(limits))),snapshot,bindings,texture_count,frame,limits)
