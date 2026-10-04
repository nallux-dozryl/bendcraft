import Base
import ./block_physics.bend as BP
import ./client_world.bend as W
import ./core.bend as C
import ./game.bend as G
import ./registry.bend as B
import ./f64.bend as F
import ./movement.bend as M

# Stored getters only. No palette, collision, body-position or entity policy.
type Observation is Data:
  Observation{state_id:U32,sample:BP.Sample}

type Error is Data:
  UnknownDimension{name:String}
  InvalidCoordinate{axis:U32}
  RegistryStateCount{provided:U32}
  CoreStateCount{provided:U32}
  RegistryIdentityError{message:String}
  ForeignRegistry{identity:String}
  WorldError{cause:C.Error}
  PrimitiveError{cause:BP.Error}
  BatchLimit{}

def error_text(error:Error) -> String:
  match error:
    case UnknownDimension{name}: "unknown-dimension:" ++ name
    case InvalidCoordinate{axis}: "invalid-exact-cell-coordinate:" ++ U32.show(axis)
    case RegistryStateCount{provided}: "registry-state-count:" ++ U32.show(provided)
    case CoreStateCount{provided}: "core-state-count:" ++ U32.show(provided)
    case RegistryIdentityError{message}: "registry-identity:" ++ message
    case ForeignRegistry{identity}: "foreign-registry:" ++ identity
    case WorldError{cause}: W.error_text(cause)
    case PrimitiveError{cause}: BP.error_text(cause)
    case BatchLimit{}: "stored-factor-batch-limit:65536"

def batch_limit() -> Nat:
  65536n

def cells_fit(fuel:Nat,cells:List<&2,C.Position>) -> Bool:
  match fuel cells:
    case _ Nil{}: True{}
    case 0n _: False{}
    case 1n+rest _ <> tail: cells_fit(rest,tail)

def sample_read(state:U32,result:BP.Catalog & Result<&2,&2,BP.Error,BP.Sample>) -> BP.Catalog & Result<&2,&2,Error,Observation>:
  (catalog,status) = result
  match status:
    case Fail{cause}: (catalog,Fail{PrimitiveError{cause}})
    case Done{sample}: (catalog,Done{Observation{state,sample}})

def cell_read(catalog:BP.Catalog,result:C.World & Result<&2,&2,C.Error,U32>) -> C.World & BP.Catalog & Result<&2,&2,Error,Observation>:
  (world,status) = result
  match status:
    case Fail{cause}: (world,catalog,Fail{WorldError{cause}})
    case Done{+state}:
      W.paired(BP.Catalog,Result<&2,&2,Error,Observation>,C.World & BP.Catalog & Result<&2,&2,Error,Observation>,sample_read(state,BP.Catalog.query(catalog,BP.pinned_identity(),state)),kept => observed => (world,kept,observed))

# Core.read_block does not itself check dimension_known; do not trust a forged
# unknown-dimension section merely because its key happens to be present.
def cell_gate(world:C.World,catalog:BP.Catalog,cell:C.Position,name:String,known:Bool) -> C.World & BP.Catalog & Result<&2,&2,Error,Observation>:
  match known:
    case False{}: (world,catalog,Fail{UnknownDimension{name}})
    case True{}: cell_read(catalog,C.read_block(world,cell))

def cell_admitted(world:C.World,catalog:BP.Catalog,+cell:C.Position) -> C.World & BP.Catalog & Result<&2,&2,Error,Observation>:
  +name = C.dimension(cell)
  cell_gate(world,catalog,cell,name,C.dimension_known(name))

def cells_step(acc:List<&2,Result<&2,&2,Error,Observation>>,result:C.World & BP.Catalog & Result<&2,&2,Error,Observation>,finish:C.World -> BP.Catalog -> List<&2,Result<&2,&2,Error,Observation>> -> C.World & BP.Catalog & List<&2,Result<&2,&2,Error,Observation>>) -> C.World & BP.Catalog & List<&2,Result<&2,&2,Error,Observation>>:
  (world,catalog,status) = result
  finish(world,catalog,status <> acc)

def cells_go(cells:List<&2,C.Position>,acc:List<&2,Result<&2,&2,Error,Observation>>,world:C.World,catalog:BP.Catalog) -> C.World & BP.Catalog & List<&2,Result<&2,&2,Error,Observation>>:
  match cells:
    case Nil{}: (world,catalog,List.reverse(&2,Result<&2,&2,Error,Observation>,acc))
    case cell <> rest: cells_step(acc,cell_admitted(world,catalog,cell),next => kept => values => cells_go(rest,values,next,kept))

def cells_attached(registry:B.Registry,view:W.View,result:C.World & BP.Catalog & List<&2,Result<&2,&2,Error,Observation>>) -> W.State & BP.Catalog & Result<&2,&2,Error,List<&2,Result<&2,&2,Error,Observation>>>:
  (world,catalog,observations) = result
  (W.attach(G.Engine{world,registry},view),catalog,Done{observations})

def identity_gate(world:C.World,registry:B.Registry,view:W.View,catalog:BP.Catalog,cells:List<&2,C.Position>,identity:String,valid:Bool) -> W.State & BP.Catalog & Result<&2,&2,Error,List<&2,Result<&2,&2,Error,Observation>>>:
  match valid:
    case False{}: (W.attach(G.Engine{world,registry},view),catalog,Fail{ForeignRegistry{identity}})
    case True{}: cells_attached(registry,view,cells_go(cells,[],world,catalog))

def identity_checked(world:C.World,view:W.View,catalog:BP.Catalog,cells:List<&2,C.Position>,result:B.Registry & Result<&2,&2,String,String>) -> W.State & BP.Catalog & Result<&2,&2,Error,List<&2,Result<&2,&2,Error,Observation>>>:
  (registry,status) = result
  match status:
    case Fail{message}: (W.attach(G.Engine{world,registry},view),catalog,Fail{RegistryIdentityError{message}})
    case Done{+identity}: identity_gate(world,registry,view,catalog,cells,identity,String.eq(identity,BP.pinned_identity()))

def counts_gate(world:C.World,registry:B.Registry,view:W.View,catalog:BP.Catalog,cells:List<&2,C.Position>,registry_count:U32,core_count:U32,registry_ok:Bool,core_ok:Bool) -> W.State & BP.Catalog & Result<&2,&2,Error,List<&2,Result<&2,&2,Error,Observation>>>:
  match registry_ok core_ok:
    case False{} _: (W.attach(G.Engine{world,registry},view),catalog,Fail{RegistryStateCount{registry_count}})
    case True{} False{}: (W.attach(G.Engine{world,registry},view),catalog,Fail{CoreStateCount{core_count}})
    case True{} True{}: identity_checked(world,view,catalog,cells,B.Registry.identity(registry))

def counts_checked(world:C.World,registry:B.Registry,view:W.View,catalog:BP.Catalog,cells:List<&2,C.Position>) -> W.State & BP.Catalog & Result<&2,&2,Error,List<&2,Result<&2,&2,Error,Observation>>>:
  C.World{tick,time,paused,daylight,revision,+core_count,sections,pending,events} = world
  B.Registry{blocks,names,count,+registry_count} = registry
  counts_gate(C.World{tick,time,paused,daylight,revision,core_count,sections,pending,events},B.Registry{blocks,names,count,registry_count},view,catalog,cells,registry_count,core_count,U32.is_eq(registry_count,BP.pinned_states()),U32.is_eq(core_count,BP.pinned_states()))

def cells_extracted(catalog:BP.Catalog,cells:List<&2,C.Position>,result:G.Engine & W.View) -> W.State & BP.Catalog & Result<&2,&2,Error,List<&2,Result<&2,&2,Error,Observation>>>:
  (G.Engine{core,registry},view) = result
  counts_checked(core,registry,view,catalog,cells)

def cells_bounded(world:W.State,catalog:BP.Catalog,cells:List<&2,C.Position>,fits:Bool) -> W.State & BP.Catalog & Result<&2,&2,Error,List<&2,Result<&2,&2,Error,Observation>>>:
  match fits:
    case False{}: (world,catalog,Fail{BatchLimit{}})
    case True{}: cells_extracted(catalog,cells,W.take(world))

# Actual registry identity is checked once for this call, never cached as a
# caller-copyable admission token. Individual dimension/read/catalog errors
# remain in input order and do not short-circuit the remaining cells.
def query_cells(world:W.State,catalog:BP.Catalog,+cells:List<&2,C.Position>) -> W.State & BP.Catalog & Result<&2,&2,Error,List<&2,Result<&2,&2,Error,Observation>>>:
  cells_bounded(world,catalog,cells,cells_fit(batch_limit(),cells))

def single_result(result:W.State & BP.Catalog & Result<&2,&2,Error,List<&2,Result<&2,&2,Error,Observation>>>) -> W.State & BP.Catalog & Result<&2,&2,Error,Observation>:
  (world,catalog,status) = result
  match status:
    case Fail{error}: (world,catalog,Fail{error})
    case Done{head <> rest}: (world,catalog,head)
    case Done{Nil{}}: (world,catalog,Fail{BatchLimit{}})

def single_gate(world:W.State,catalog:BP.Catalog,cell:C.Position,name:String,known:Bool) -> W.State & BP.Catalog & Result<&2,&2,Error,Observation>:
  match known:
    case False{}: (world,catalog,Fail{UnknownDimension{name}})
    case True{}: single_result(query_cells(world,catalog,[cell]))

# Every U32 coordinate is an exact signed-I32 bit pattern. No palette inference,
# unloaded-air fallback, unsigned reinterpretation or floating conversion.
def query_cell(world:W.State,catalog:BP.Catalog,+cell:C.Position) -> W.State & BP.Catalog & Result<&2,&2,Error,Observation>:
  +name = C.dimension(cell)
  single_gate(world,catalog,cell,name,C.dimension_known(name))

def coordinate_exact(word:U32,axis:U32,valid:Bool) -> Result<&2,&2,Error,U32>:
  match valid:
    case False{}: Fail{InvalidCoordinate{axis}}
    case True{}: Done{word}

def coordinate_integer(+value:F.F64,axis:U32,result:Result<&2,&2,F.F64ConversionError,U32>) -> Result<&2,&2,Error,U32>:
  match result:
    case Fail{cause}: Fail{InvalidCoordinate{axis}}
    case Done{+word}: coordinate_exact(word,axis,F.is_eq(value,F.from_i32(word)))

def coordinate(+value:F.F64,axis:U32) -> Result<&2,&2,Error,U32>:
  coordinate_integer(value,axis,F.trunc_i32(value))

def exact_cell(dimension:String,position:M.Vec3) -> Result<&2,&2,Error,C.Position>:
  M.Vec3{x,y,z} = position
  do Result<&2,&2,Error,C.Position>:
    a : U32 <- coordinate(x,0)
    b : U32 <- coordinate(y,1)
    c : U32 <- coordinate(z,2)
    return C.Position{dimension,a,b,c}

def exact_result(world:W.State,catalog:BP.Catalog,result:Result<&2,&2,Error,C.Position>) -> W.State & BP.Catalog & Result<&2,&2,Error,Observation>:
  match result:
    case Fail{error}: (world,catalog,Fail{error})
    case Done{cell}: query_cell(world,catalog,cell)

# Finite, integral, signed-I32 only. Numeric +/-zero both designate cell0.
# Fractions never floor or clamp; NaN/infinity/out-of-range fail explicitly.
def query_exact(world:W.State,catalog:BP.Catalog,dimension:String,position:M.Vec3) -> W.State & BP.Catalog & Result<&2,&2,Error,Observation>:
  exact_result(world,catalog,exact_cell(dimension,position))

law unknown_dimension_retains_both_owners:
  for world:W.State
  for catalog:BP.Catalog
  for cell:C.Position
  for name:String
  {single_gate(world,catalog,cell,name,False{}) == (world,catalog,Fail{UnknownDimension{name}}) : W.State & BP.Catalog & Result<&2,&2,Error,Observation>}

def unknown_dimension_retains_both_owners(world,catalog,cell,name):
  {==}

law exact_failure_retains_both_owners:
  for world:W.State
  for catalog:BP.Catalog
  for error:Error
  {exact_result(world,catalog,Fail{error}) == (world,catalog,Fail{error}) : W.State & BP.Catalog & Result<&2,&2,Error,Observation>}

def exact_failure_retains_both_owners(world,catalog,error):
  {==}

law batch_limit_retains_both_owners:
  for world:W.State
  for catalog:BP.Catalog
  for cells:List<&2,C.Position>
  {cells_bounded(world,catalog,cells,False{}) == (world,catalog,Fail{BatchLimit{}}) : W.State & BP.Catalog & Result<&2,&2,Error,List<&2,Result<&2,&2,Error,Observation>>>}

def batch_limit_retains_both_owners(world,catalog,cells):
  {==}
