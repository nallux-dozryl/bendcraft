import Base
import ./client_world.bend as W
import ./client_render.bend as R
import ./movement.bend as MV
import ./world_mesh.bend as WM
import ./blockstate_model.bend as S
import ./resource_block_catalog.bend as C
import ./resource_catalog_world.bend as CW

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

def override(found:Bool,+values:Map<&2,WM.Appearance>,key:String,fallback:WM.Appearance) -> WM.Appearance:
  match found:
    case False{}: fallback
    case True{}: S.map_value(WM.Appearance,Map.get(WM.Appearance,WM.appearance(),values,key))

def appearance(+point:W.Cell,+state:U32,policy:Policy) -> WM.Appearance:
  Policy{seed,default,+states,+cells} = policy
  +key = point_key(point)
  override(S.map_present(WM.Appearance,Map.has(&2,WM.Appearance,cells,key)),cells,key,
    override(S.map_present(WM.Appearance,Map.has(&2,WM.Appearance,states,U32.show(state))),states,U32.show(state),default))

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
        Bool.not(S.map_present(Unit,Map.has(&2,Unit,seen,point_key(point)))) &&
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

def choice_ticket(choice:S.Choice,seed:U32) -> Result<&2,&2,C.Error,Maybe<&2,U32>>:
  match choice:
    case S.Single{variant}: Done{None{}}
    case S.WeightedChoice{entries,+total}:
      do Result<&2,&2,C.Error,Maybe<&2,U32>>:
        C.require(U32.is_gt(total,0),"InvalidWeightedChoice","catalog","zero total")
        Done{Some{U32.mod(seed,total)}}

def ticketed_part(ticket:Maybe<&2,U32>,index:U32,out:Map<&2,U32>) -> Map<&2,U32>:
  match ticket:
    case None{}: out
    case Some{value}: Map.set(&2,U32,out,U32.show(index),value)

def part_tickets(values:List<&2,S.SelectedPart>,+seed:U32,out:Map<&2,U32>) -> Result<&2,&2,C.Error,Map<&2,U32>>:
  match values:
    case Nil{}: Done{out}
    case S.SelectedPart{+index,choice} <> tail:
      do Result<&2,&2,C.Error,Map<&2,U32>>:
        ticket:Maybe<&2,U32> <- choice_ticket(choice,mixed(seed,index))
        part_tickets(tail,seed,ticketed_part(ticket,index,out))

def selection(entry:C.Entry,seed:U32) -> Result<&2,&2,C.Error,C.Selection>:
  C.Entry{identity,mode,root} = entry
  match root:
    case None{}: Done{C.Selection{None{},MTip{}}}
    case Some{S.VariantRoot{choice}}:
      do Result<&2,&2,C.Error,C.Selection>:
        ticket:Maybe<&2,U32> <- choice_ticket(choice,seed)
        Done{C.Selection{ticket,MTip{}}}
    case Some{S.MultipartRoot{parts,names}}:
      do Result<&2,&2,C.Error,C.Selection>:
        tickets:Map<&2,U32> <- part_tickets(parts,seed,MTip{})
        Done{C.Selection{None{},tickets}}

def retained_instance(mode:C.Mode,point:W.Cell,state:U32,selection:C.Selection,
    appearance:WM.Appearance,origin:MV.Vec3,tail:List<&2,CW.Instance>) -> List<&2,CW.Instance>:
  match mode:
    case C.Invisible{}: tail
    case _: CW.Instance{W.relative_block(W.RawBlock{point,state,0},origin),selection,appearance} <> tail

def entry_mode(entry:C.Entry) -> C.Mode:
  C.Entry{identity,mode,root} = entry
  mode

def instances(values:List<&2,Cell>,+origin:MV.Vec3,+catalog:C.Catalog) -> Result<&2,&2,C.Error,List<&2,CW.Instance>>:
  match values:
    case Nil{}: Done{Nil{}}
    case Cell{point,+state,seed,appearance} <> tail:
      do Result<&2,&2,C.Error,List<&2,CW.Instance>>:
        +entry:C.Entry <- C.lookup(catalog,state)
        decision:C.Selection <- selection(entry,seed)
        rest:List<&2,CW.Instance> <- instances(tail,origin,catalog)
        Done{retained_instance(entry_mode(entry),point,state,decision,appearance,origin,rest)}

def framed(value:Result<&2,&2,C.Error,List<&2,CW.Instance>>,identity:String,tick:Nat,
    revision:Nat,camera:R.Camera) -> Result<&2,&2,C.Error,CW.Frame>:
  match value:
    case Fail{error}: Fail{error}
    case Done{instances}: Done{CW.Frame{identity,tick,revision,instances,camera}}

def frame_configured(valid:Bool,sample:Sample,catalog:C.Catalog) -> Result<&2,&2,C.Error,CW.Frame>:
  match valid sample:
    case False{} _: Fail{C.Error{"InvalidSample","world",""}}
    case True{} Sample{identity,tick,revision,origin,camera,cells}:
      framed(instances(cells,origin,catalog),identity,tick,revision,camera)

def frame_gated(value:Result<&2,&2,C.Error,Unit>,+sample:Sample,catalog:C.Catalog) -> Result<&2,&2,C.Error,CW.Frame>:
  match value:
    case Fail{error}: Fail{error}
    case Done{unit}: frame_configured(sample_valid(sample),sample,catalog)

def frame(+sample:Sample,+catalog:C.Catalog) -> Result<&2,&2,C.Error,CW.Frame>:
  Sample{+identity,tick,revision,origin,camera,cells} = sample
  C.Catalog{+registry,entries,loaded} = catalog
  frame_gated(CW.identity_guard(String.eq(identity,registry),identity,registry),sample,catalog)

def draw_frame(sample:Sample,info:CW.Info) -> Result<&2,&2,C.Error,CW.Frame>:
  CW.Info{catalog,textures} = info
  frame(sample,catalog)
