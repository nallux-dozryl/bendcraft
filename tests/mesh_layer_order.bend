import Base
import ../src/world_mesh.bend as WM
import ../src/mesh_render.bend as M
import ../src/client_render.bend as R
import ../src/block_bake.bend as K
import ../src/block_model.bend as B

# Synthetic textures isolate the pinned inclusive-depth/layer-order contract.
# The real WM binding/baking and M ray/color/coverage paths supply every result.
type Case is Data:
  Case{name:String,baked:List<&2,K.Baked>,textures:List<&2,R.Texture>}

def raw(value:U32) -> F32:
  match value:
    case U32{word}: F32{word}

def vertex(x:F32,y:F32,z:F32,u:F32,v:F32) -> M.Vertex:
  M.Vertex{M.Vec3{x,y,z},M.UV{u,v}}

def plane(layer:K.Layer,slot:U32,+z:F32) -> K.Baked:
  K.Baked{vertex(1.0,1.0,z,0.0,0.0),vertex(1.0,F32.neg(1.0),z,0.0,1.0),
    vertex(F32.neg(1.0),F32.neg(1.0),z,1.0,1.0),vertex(F32.neg(1.0),1.0,z,1.0,0.0),
    B.North{},None{},"test:block/color",slot,4294967295,0,None{},layer,
    False{},False{},1.0,1.0}

def textures(alpha:U32) -> List<&2,R.Texture>:
  [R.Texture{1,1,1,Pix{4294901760}},
    R.Texture{1,1,1,Pix{U32.or(U32.shln(alpha,24n),65280)}},
    R.Texture{1,1,1,Pix{4278190335}}]

def cases() -> List<&2,Case>:
  [Case{"solid-before-covered-cutout",[plane(K.Solid{},0,2.0),plane(K.Cutout{},1,2.0)],textures(255)},
   Case{"cutout-before-solid",[plane(K.Cutout{},1,2.0),plane(K.Solid{},0,2.0)],textures(255)},
   Case{"discarded-cutout",[plane(K.Solid{},0,2.0),plane(K.Cutout{},1,2.0)],textures(0)},
   Case{"alpha127-discarded",[plane(K.Solid{},0,2.0),plane(K.Cutout{},1,2.0)],textures(127)},
   Case{"alpha128-covered",[plane(K.Solid{},0,2.0),plane(K.Cutout{},1,2.0)],textures(128)},
   Case{"solid-nearer",[plane(K.Solid{},0,1.5),plane(K.Cutout{},1,2.0)],textures(255)},
   Case{"cutout-nearer",[plane(K.Solid{},0,2.0),plane(K.Cutout{},1,1.5)],textures(255)},
   Case{"cutout-one-ulp-farther",[plane(K.Solid{},0,2.0),plane(K.Cutout{},1,raw(1073741825))],textures(255)},
   Case{"solid-one-ulp-farther",[plane(K.Solid{},0,raw(1073741825)),plane(K.Cutout{},1,2.0)],textures(255)},
   Case{"same-solid-layer-policy",[plane(K.Solid{},0,2.0),plane(K.Solid{},2,2.0)],textures(255)},
   Case{"same-cutout-layer-policy",[plane(K.Cutout{},1,2.0),plane(K.Cutout{},2,2.0)],textures(255)}]

def order(value:M.Quad) -> String:
  M.Quad{a,b,c,d,material,cull,index} = value
  U32.show(index)

def orders(values:List<&2,M.Quad>) -> List<&2,String>:
  match values:
    case Nil{}: []
    case head <> tail: order(head) <> orders(tail)

def traced(value:M.Fragment,name:String,orders:List<&2,String>) -> String:
  M.Fragment{distance,index,source,color} = value
  "{\"name\":\"" ++ name ++ "\",\"pixel\":" ++ U32.show(color) ++
    ",\"orders\":[" ++ String.join(orders,",") ++ "]}"

def observed(status:Result<&2,&2,WM.Error,M.Scene>,name:String,textures:List<&2,R.Texture>) -> String:
  match status:
    case Fail{WM.Error{code,state}}:
      "{\"name\":\"" ++ name ++ "\",\"error\":\"" ++ code ++ "\",\"state\":" ++ U32.show(state) ++ "}"
    case Done{M.Scene{camera,+quads,settings}}:
      traced(M.opaque_trace(M.prepare(quads,0),M.Vec3{0.0,0.0,0.0},
        M.Vec3{0.0,0.0,1.0},settings,textures,M.Fragment{65.0,4294967295,4294967295,4284784875}),name,orders(quads))

def observe(value:Case) -> String:
  Case{name,baked,+textures} = value
  observed(WM.produce(R.Snapshot{7n,9n,[R.Block{0.0,0.0,0.0,42,0}],R.Camera{0.0,0.0,0.0,0.0,0.0}},
    [WM.Binding{42,baked,WM.appearance()}],U32.from_nat(List.length(&2,R.Texture,textures)),WM.frame(31,17),WM.defaults()),name,textures)

def observed_cases(values:List<&2,Case>) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit,Unit{})
    case head <> tail:
      do IO<Unit>:
        IO.print(observe(head))
        observed_cases(tail)

def main() -> IO(Unit):
  observed_cases(cases())
