import Base
import ./client_world.bend as W
import ./client_render.bend as R
import ./movement.bend as MV
import ./world_mesh.bend as WM

# The actor transports state identity and per-cell decisions independently of
# the client's texture owner. No legacy three-material palette is consulted.
type Cell is Data:
  Cell{point:W.Cell,state:U32,seed:U32,appearance:WM.Appearance}
type Sample is Data:
  Sample{registry_identity:String,tick:Nat,revision:Nat,origin:MV.Vec3,
    camera:R.Camera,cells:List<&2,Cell>}
type Policy is Data:
  Policy{seed:U32,default:WM.Appearance,states:Map<&2,WM.Appearance>,
    cells:Map<&2,WM.Appearance>}

def defaults() -> Policy:
  Policy{0,WM.appearance(),MTip{},MTip{}}

def point_key(point:W.Cell) -> String:
  W.Cell{x,y,z,boundary} = point
  U32.show(x) ++ ":" ++ U32.show(y) ++ ":" ++ U32.show(z)

def appearance_value(pair:Map<&2,WM.Appearance> & WM.Appearance) -> WM.Appearance:
  (values,value) = pair
  value

def appearance_present(pair:Map<&2,WM.Appearance> & Bool) -> Bool:
  (values,present) = pair
  present

def point_seen(pair:Map<&2,Unit> & Bool) -> Bool:
  (values,present) = pair
  present

def override(found:Bool,+values:Map<&2,WM.Appearance>,key:String,fallback:WM.Appearance) -> WM.Appearance:
  match found:
    case False{}: fallback
    case True{}: appearance_value(Map.get(WM.Appearance,WM.appearance(),values,key))

def appearance(+point:W.Cell,+state:U32,policy:Policy) -> WM.Appearance:
  Policy{seed,default,+states,+cells} = policy
  +key = point_key(point)
  override(appearance_present(Map.has(&2,WM.Appearance,cells,key)),cells,key,
    override(appearance_present(Map.has(&2,WM.Appearance,states,U32.show(state))),states,U32.show(state),default))

# Explicit deterministic stream for the generic client. This mixer is not a
# claim of Minecraft's position-seeded Java Random sequence.
def mixed(+seed:U32,index:U32) -> U32:
  U32.mul(U32.xor(seed,U32.mul(U32.inc(index),2246822519)),3266489917)

def position_seed(point:W.Cell,seed:U32) -> U32:
  W.Cell{x,y,z,boundary} = point
  mixed(mixed(mixed(seed,x),y),z)

def cell_value(+point:W.Cell,+state:U32,+policy:Policy) -> Cell:
  Policy{seed,default,states,cells} = policy
  Cell{point,state,position_seed(point,seed),appearance(point,state,policy)}

def same_point(first:W.Cell,second:W.Cell) -> Bool:
  match first second:
    case W.Cell{x,y,z,boundary} W.Cell{a,b,c,edge}:
      U32.is_eq(x,a) && U32.is_eq(y,b) && U32.is_eq(z,c)

def point_present(+point:W.Cell,values:List<&2,Cell>) -> Bool:
  match values:
    case Nil{}: False{}
    case Cell{other,state,seed,appearance} <> tail:
      same_point(point,other) || point_present(point,tail)

def cells_valid_go(values:List<&2,Cell>,+remaining:U32,+seen:Map<&2,Unit>) -> Bool:
  match values:
    case Nil{}: True{}
    case Cell{+point,state,seed,appearance} <> tail:
      U32.is_gt(remaining,0) && U32.is_le(W.boundary(point),3) &&
        WM.appearance_valid(appearance,256) &&
        Bool.not(point_seen(Map.has(&2,Unit,seen,point_key(point)))) &&
        cells_valid_go(tail,U32.sub(remaining,1),Map.set(&2,Unit,seen,point_key(point),Unit{}))

def cells_valid(values:List<&2,Cell>,remaining:U32) -> Bool:
  cells_valid_go(values,remaining,MTip{})

def sample_valid(value:Sample) -> Bool:
  Sample{registry,tick,revision,origin,camera,cells} = value
  Bool.not(String.is_empty(registry)) && W.finite_relative_origin(origin) &&
    WM.relative_camera(camera) && cells_valid(cells,4096)

def sample_admitted(valid:Bool,value:Sample) -> Result<&2,&2,String,Sample>:
  match valid:
    case False{}: Fail{"generic-resource:invalid-sample"}
    case True{}: Done{value}

def sample_checked(+value:Sample) -> Result<&2,&2,String,Sample>:
  sample_admitted(sample_valid(value),value)
