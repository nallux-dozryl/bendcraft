import Base
import ./local_player_session.bend as S
import ./local_player_runtime.bend as R
import ./local_phase_runtime.bend as X
import ./client_world.bend as W
import ./client_render.bend as CR
import ./world_visibility.bend as V
import ./world_mesh.bend as WM
import ./movement.bend as M
import ./game.bend as G
import ./core.bend as C
import ./registry.bend as B

# Actor-side legacy sample extraction. S/X remains the sole runtime/Core owner.
# The original local_resource_world client API remains available; this module
# imports no resource loader or catalog owner and preserves V.Sample exactly.
type Config is Data:
  Config{width:U32,height:U32,limits:V.Limits}

type Capture is Data:
  Capture{snapshot:CR.Snapshot,origin:M.Vec3,palette:W.Palette,
    limits:V.Limits,tail:List<&2,Capture>}

type Collection is Data:
  Collection{view:W.View,capture:Capture,raw:List<&2,W.RawBlock>,
    tail:List<&2,Collection>}

# Pure legacy-sample diagnostic; identical wire text without a renderer import.
def visibility_error(value:V.Error) -> String:
  V.Error{code,W.Cell{x,y,z,boundary},state,detail} = value
  "Visibility:" ++ code ++ ":" ++ U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z) ++ "," ++ U32.show(boundary) ++
    ":" ++ U32.show(state) ++ ":" ++ detail

def failure(-A:Data,code:String,detail:String) -> Result<&2,&2,String,A>:
  Fail{visibility_error(V.Error{code,V.empty_cell(),0,detail})}

def binding(+actual:W.Palette,view:W.View) -> Bool:
  match view:
    case W.View{body,yaw,pitch,None{},region,cache}: False{}
    case W.View{body,yaw,pitch,Some{cached},region,cache}:
      V.palette_valid(actual) && W.same_palette(actual,cached)

def palette_bound(valid:Bool,world:W.State,actual:W.Palette) -> W.State & Result<&2,&2,String,W.Palette>:
  match valid:
    case False{}: (world,failure(W.Palette,"Palette","registry-palette-mismatch-or-unavailable"))
    case True{}: (world,Done{actual})

def palette_resolved(core:C.World,+view:W.View,result:B.Registry & Result<&2,&2,String,W.Palette>) -> W.State & Result<&2,&2,String,W.Palette>:
  (registry,status) = result
  match status:
    case Fail{error}: (W.attach(G.Engine{core,registry},view),failure(W.Palette,"Palette",error))
    case Done{+actual}: palette_bound(binding(actual,view),W.attach(G.Engine{core,registry},view),actual)

# Resolve the current Registry and validate the existing View binding. No cell,
# neighbor, clock advancement, or cache mutation occurs during this admission.
def world_palette(world:W.State) -> W.State & Result<&2,&2,String,W.Palette>:
  W.State{G.Engine{core,registry},body,yaw,pitch,palette,region,cache} = world
  palette_resolved(core,W.View{body,yaw,pitch,palette,region,cache},
    W.palette_air(W.supported_block(B.Registry.block(registry,"minecraft:air"))))

def limits_gate(valid:Bool,world:W.State) -> W.State & Result<&2,&2,String,W.Palette>:
  match valid:
    case False{}: (world,failure(W.Palette,"LimitsOrRegion","unsupported-configured-domain"))
    case True{}: world_palette(world)

def preflight(world:W.State,limits:V.Limits) -> W.State & Result<&2,&2,String,W.Palette>:
  W.State{engine,body,yaw,pitch,palette,+region,cache} = world
  V.Limits{mesh,max_reads} = limits
  limits_gate(WM.limits_valid(mesh) && U32.is_le(max_reads,24576) && W.bounds_valid(region),
    W.State{engine,body,yaw,pitch,palette,region,cache})

def collection_view(collection:Collection) -> W.View:
  Collection{view,capture,raw,tail} = collection
  view

def collected_success(collection:Collection,registry:B.Registry,core:C.World,values:V.Collected) -> W.State & Result<&2,&2,String,V.Sample>:
  Collection{view,Capture{snapshot,origin,palette,limits,capture_tail},raw,tail} = collection
  V.Collected{reversed,reads} = values
  (W.attach(G.Engine{core,registry},view),Done{V.Sample{snapshot,raw,List.reverse(&2,V.Visibility,reversed),origin,palette,reads}})

def collected(+collection:Collection,registry:B.Registry,result:C.World & Result<&2,&2,V.Error,V.Collected>) -> W.State & Result<&2,&2,String,V.Sample>:
  (core,status) = result
  match status:
    case Fail{error}: (W.attach(G.Engine{core,registry},collection_view(collection)),Fail{visibility_error(error)})
    case Done{values}: collected_success(collection,registry,core,values)

def capture_palette(capture:Capture) -> W.Palette:
  Capture{snapshot,origin,palette,limits,tail} = capture
  palette

def capture_limits(capture:Capture) -> V.Limits:
  Capture{snapshot,origin,palette,limits,tail} = capture
  limits

def aligned(valid:Bool,world:W.State,+capture:Capture,+raw:List<&2,W.RawBlock>) -> W.State & Result<&2,&2,String,V.Sample>:
  match valid:
    case False{}: (world,failure(V.Sample,"SnapshotAlignment","invalid-raw-cache"))
    case True{}:
      W.State{G.Engine{core,registry},body,yaw,pitch,palette,region,cache} = world
      collected(Collection{W.View{body,yaw,pitch,palette,region,cache},capture,raw,[]},registry,
        V.collect_blocks(raw,capture_palette(capture),core,Done{V.Collected{[],0}}))

def alignment_checked(world:W.State,+capture:Capture,+raw:List<&2,W.RawBlock>) -> W.State & Result<&2,&2,String,V.Sample>:
  Capture{snapshot,origin,palette,limits,tail} = capture
  aligned(V.raw_alignment(snapshot,raw,origin,palette),world,capture,raw)

def count_checked(error:String,world:W.State,+capture:Capture,+raw:List<&2,W.RawBlock>) -> W.State & Result<&2,&2,String,V.Sample>:
  match error:
    case "": alignment_checked(world,capture,raw)
    case error: (world,failure(V.Sample,error,"configured-before-neighbor-reads"))

def counts_checked(world:W.State,capture:Capture,+raw:List<&2,W.RawBlock>,limits:V.Limits) -> W.State & Result<&2,&2,String,V.Sample>:
  V.Limits{WM.Limits{max_blocks,max_bindings,max_quads,max_translucent,max_tints},max_reads} = limits
  count_checked(W.choose(String,"BlockLimit",W.choose(String,"NeighborReadLimit","",
    Bool.not(WM.fits(W.RawBlock,raw,U32.div(max_reads,6)))),Bool.not(WM.fits(W.RawBlock,raw,max_blocks))),world,capture,raw)

def cached(world:W.State,+capture:Capture,result:Maybe<&2,List<&2,W.RawBlock>>) -> W.State & Result<&2,&2,String,V.Sample>:
  match result:
    case None{}: (world,failure(V.Sample,"SnapshotCache","relative-snapshot-did-not-return-raw-cells"))
    case Some{+raw}: counts_checked(world,capture,raw,capture_limits(capture))

def cells_bound(valid:Bool,world:W.State,capture:Capture,raw:Maybe<&2,List<&2,W.RawBlock>>) -> W.State & Result<&2,&2,String,V.Sample>:
  match valid:
    case False{}: (world,failure(V.Sample,"Palette","registry-palette-mismatch-or-unavailable"))
    case True{}: cached(world,capture,raw)

def cells(world:W.State,+capture:Capture) -> W.State & Result<&2,&2,String,V.Sample>:
  W.State{engine,body,yaw,pitch,+palette,+region,+cache} = world
  Capture{CR.Snapshot{tick,+revision,blocks,camera},origin,+actual,limits,tail} = capture
  +view : W.View = W.View{body,yaw,pitch,palette,region,cache}
  cells_bound(binding(actual,view),W.attach(engine,view),capture,
    W.cached_blocks(cache,revision,region,actual))

def snapshot_ready(origin:M.Vec3,palette:W.Palette,config:Config,result:X.State & Result<&2,&2,String,CR.Snapshot>) -> X.State & Result<&2,&2,String,V.Sample>:
  Config{width,height,limits} = config
  (player,status) = result
  match status:
    case Fail{error}: (player,failure(V.Sample,"Snapshot",error))
    case Done{snapshot}:
      R.query(Result<&2,&2,String,V.Sample>,player,world => cells(world,Capture{snapshot,origin,palette,limits,[]}))

def eye_ready(palette:W.Palette,+config:Config,result:X.State & Result<&2,&2,String,M.Vec3>) -> X.State & Result<&2,&2,String,V.Sample>:
  Config{width,height,limits} = config
  (player,status) = result
  match status:
    case Fail{error}: (player,failure(V.Sample,"Snapshot",error))
    case Done{origin}: snapshot_ready(origin,palette,config,R.snapshot(player,width,height))

def preflight_ready(config:Config,result:X.State & Result<&2,&2,String,W.Palette>) -> X.State & Result<&2,&2,String,V.Sample>:
  (player,status) = result
  match status:
    case Fail{error}: (player,Fail{error})
    case Done{actual}: eye_ready(actual,config,R.eye(player))

def player_snapshot(player:X.State,+config:Config) -> X.State & Result<&2,&2,String,V.Sample>:
  Config{width,height,limits} = config
  preflight_ready(config,R.query(Result<&2,&2,String,W.Palette>,player,world => preflight(world,limits)))

def snapshot_valid(state:S.State,width:U32,height:U32,valid:Bool) -> S.State & Result<&2,&2,String,V.Sample>:
  match valid:
    case False{}: (state,Fail{"ResourceScene:Frame"})
    case True{}:
      S.query(Result<&2,&2,String,V.Sample>,state,p => player_snapshot(p,Config{width,height,V.defaults()}))

# Invoke this complete pure operation once in Server.local_call. Both eye reads
# are immutable Pose admission; R.snapshot performs no tick or control sampling.
def snapshot(state:S.State,+width:U32,+height:U32) -> S.State & Result<&2,&2,String,V.Sample>:
  snapshot_valid(state,width,height,WM.frame_valid(WM.frame(width,height)))

law invalid_frame_retains_complete_local_session:
  for state:S.State
  for width:U32
  for height:U32
  {snapshot_valid(state,width,height,False{}) == (state,Fail{"ResourceScene:Frame"}) : S.State & Result<&2,&2,String,V.Sample>}

def invalid_frame_retains_complete_local_session(state,width,height):
  {==}

law palette_refusal_retains_complete_world_owner:
  for world:W.State
  for palette:W.Palette
  {palette_bound(False{},world,palette) ==
    (world,failure(W.Palette,"Palette","registry-palette-mismatch-or-unavailable")) :
    W.State & Result<&2,&2,String,W.Palette>}

def palette_refusal_retains_complete_world_owner(world,palette):
  {==}

law alignment_refusal_retains_complete_world_owner:
  for world:W.State
  for capture:Capture
  for raw:List<&2,W.RawBlock>
  {aligned(False{},world,capture,raw) ==
    (world,failure(V.Sample,"SnapshotAlignment","invalid-raw-cache")) :
    W.State & Result<&2,&2,String,V.Sample>}

def alignment_refusal_retains_complete_world_owner(world,capture,raw):
  {==}

law absent_cache_retains_complete_world_owner:
  for world:W.State
  for capture:Capture
  {cached(world,capture,None{}) ==
    (world,failure(V.Sample,"SnapshotCache","relative-snapshot-did-not-return-raw-cells")) :
    W.State & Result<&2,&2,String,V.Sample>}

def absent_cache_retains_complete_world_owner(world,capture):
  {==}

law lost_palette_binding_retains_complete_world_owner:
  for world:W.State
  for capture:Capture
  for raw:Maybe<&2,List<&2,W.RawBlock>>
  {cells_bound(False{},world,capture,raw) ==
    (world,failure(V.Sample,"Palette","registry-palette-mismatch-or-unavailable")) :
    W.State & Result<&2,&2,String,V.Sample>}

def lost_palette_binding_retains_complete_world_owner(world,capture,raw):
  {==}

law read_refusal_retains_returned_core_registry_and_complete_view:
  for +collection:Collection
  for registry:B.Registry
  for core:C.World
  for +error:V.Error
  {collected(collection,registry,(core,Fail{error})) ==
    (W.attach(G.Engine{core,registry},collection_view(collection)),Fail{visibility_error(error)}) :
    W.State & Result<&2,&2,String,V.Sample>}

def read_refusal_retains_returned_core_registry_and_complete_view(collection,registry,core,error):
  {==}
