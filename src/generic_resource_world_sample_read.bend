import Base
import ./generic_resource_world_sample.bend as GS
import ./client_world.bend as W
import ./core.bend as C
import ./game.bend as G
import ./registry.bend as B
import ./movement.bend as MV
import ./client_render.bend as R
import ./player_look.bend as PL
import ./world_mesh.bend as WM

# Immutable sampling context. The recursive tail keeps native continuations
# boxed; contexts constructed here have an empty tail. No Core owner is copied.
type Capture is Data:
  Capture{view:W.View,origin:MV.Vec3,registry_identity:String,tick:Nat,
    revision:Nat,tail:List<&2,Capture>}

# The caller supplies the actual pose-aware eye. It is already the coordinate
# origin, so camera XYZ is zero; deriving a standing eye from Body is incorrect.
def camera(view:W.View) -> R.Camera:
  W.View{body,yaw,pitch,palette,region,cache} = view
  R.Camera{0.0,0.0,0.0,yaw,pitch}

def preflight(+view:W.View,+origin:MV.Vec3,identity:String) -> String:
  W.View{body,+yaw,+pitch,palette,region,cache} = view
  W.choose(String,"generic-resource:invalid-region",
    W.choose(String,"generic-resource:invalid-origin",
      W.choose(String,"generic-resource:invalid-camera",
        W.choose(String,"generic-resource:invalid-registry-identity","",String.is_empty(identity)),
        Bool.not(PL.finite(yaw) && PL.finite(pitch) && WM.relative_camera(camera(view)))),
      Bool.not(W.finite_relative_origin(origin))),Bool.not(W.bounds_valid(region)))

def capture_view(value:Capture) -> W.View:
  Capture{view,origin,identity,tick,revision,tail} = value
  view

def sample_value(value:Capture,cells:List<&2,GS.Cell>) -> GS.Sample:
  Capture{view,origin,identity,tick,revision,tail} = value
  GS.Sample{identity,tick,revision,origin,camera(view),cells}

# Keep every observed U32 state, including air and IDs outside a loaded resource
# catalog. Catalog admission belongs to the later GS.frame/C.bind path.
def read_value(point:W.Cell,policy:GS.Policy,reversed:List<&2,GS.Cell>,
    value:C.World & Result<&2,&2,C.Error,U32>) ->
    C.World & Result<&2,&2,String,List<&2,GS.Cell>>:
  match value:
    case (world,Fail{error}): (world,Fail{W.error_text(error)})
    case (world,Done{state}): (world,Done{GS.cell_value(point,state,policy) <> reversed})

def collect(n:Nat,+index:U32,+region:W.Bounds,+policy:GS.Policy,world:C.World,
    status:Result<&2,&2,String,List<&2,GS.Cell>>) ->
    C.World & Result<&2,&2,String,List<&2,GS.Cell>>:
  match n status:
    case _ Fail{error}: (world,Fail{error})
    case 0n Done{reversed}: (world,Done{List.reverse(&2,GS.Cell,reversed)})
    case 1n+rest Done{reversed}:
      +point = W.cell(region,index)
      W.paired(C.World,Result<&2,&2,String,List<&2,GS.Cell>>,
        C.World & Result<&2,&2,String,List<&2,GS.Cell>>,
        read_value(point,policy,reversed,C.read_block(world,W.position(point))),
        next => result => collect(rest,U32.inc(index),region,policy,next,result))

def finished(value:C.World & Result<&2,&2,String,List<&2,GS.Cell>>,
    registry:B.Registry,+capture:Capture) -> W.State & Result<&2,&2,String,GS.Sample>:
  match value:
    case (world,Fail{error}):
      (W.attach(G.Engine{world,registry},capture_view(capture)),Fail{error})
    case (world,Done{cells}):
      (W.attach(G.Engine{world,registry},capture_view(capture)),GS.sample_checked(sample_value(capture,cells)))

# Clock observes the actual Core owner; sampling never ticks simulation and
# never consumes, populates, validates, or replaces the legacy raw cache.
def clocked(value:C.World & C.Clock,registry:B.Registry,+view:W.View,
    origin:MV.Vec3,identity:String,policy:GS.Policy) -> W.State & Result<&2,&2,String,GS.Sample>:
  (world,C.Clock{tick,time,paused,daylight,revision,pending}) = value
  W.View{body,yaw,pitch,palette,+region,cache} = view
  finished(collect(U32.to_nat(W.volume(region)),0,region,policy,world,Done{Nil{}}),
    registry,Capture{view,origin,identity,tick,revision,Nil{}})

def gated(error:String,engine:G.Engine,view:W.View,origin:MV.Vec3,
    identity:String,policy:GS.Policy) -> W.State & Result<&2,&2,String,GS.Sample>:
  match error:
    case "":
      G.Engine{world,registry} = engine
      clocked(C.clock(world),registry,view,origin,identity,policy)
    case error: (W.attach(engine,view),Fail{error})

def taken(value:G.Engine & W.View,+origin:MV.Vec3,+identity:String,policy:GS.Policy) ->
    W.State & Result<&2,&2,String,GS.Sample>:
  match value:
    case (engine,+view): gated(preflight(view,origin,identity),engine,view,origin,identity,policy)

# Admitted axes are 1..16, so the exact x/y/z traversal has at most 4096 reads.
# W.position fixes the current Core instrument's Overworld dimension.
def snapshot(world:W.State,origin:MV.Vec3,registry_identity:String,policy:GS.Policy) ->
    W.State & Result<&2,&2,String,GS.Sample>:
  taken(W.take(world),origin,registry_identity,policy)
