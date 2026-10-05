import Base
import ./item_entity_tick_model.bend as T
import ./item_entity_tick_profiles.bend as P
import ./item_entity_tick_fields.bend as U
import ./cooking_effect_geometry_world.bend as GP
import ./cooking_effect_geometry.bend as G
import ./local_collision_world.bend as L
import ./slab_collision_world.bend as Q
import ./slab_collision.bend as S
import ./game.bend as Game
import ./core.bend as Core
import ./client_world.bend as W
import ./campfire_authority_items.bend as CI
import ./geometry.bend as A
import ./f64.bend as F

# The actual world owner is queried once, then retained. Entity collision facts,
# server lifecycle services, minY and loaded-section state remain explicit inputs.
type Request is Data:
  Request{geometry:GP.Request,items:CI.Context,profiles:List<&2,P.Profile>,
    entities:List<&2,A.AABB>,min_y:U32,server:Bool,fast_lava:Bool,
    loaded_fluid_sections:Bool,entity_queries_complete:Bool,rain:Bool,
    neutral_portal:Bool,neutral_mount:Bool,step_budget:Nat,fall_clip:Maybe<&2,Bool>}
def cells(reads:List<&2,L.Read>,+profiles:List<&2,P.Profile>) -> Result<&2,&2,T.Error,List<&2,T.Cell>>:
  match reads:
    case Nil{}: Done{[]}
    case L.Read{Core.Position{+d,+x,+y,+z},+state} <> +rest:
      do Result<&2,&2,T.Error,List<&2,T.Cell>>:
        profile : P.Profile <- P.find(profiles,state)
        tail : List<&2,T.Cell> <- cells(rest,profiles)
        return P.cell(profile,x,y,z) <> tail
def context(+request:Request,+blocks:List<&2,G.Obstacle>,+cells:List<&2,T.Cell>) -> T.Context:
  Request{GP.Request{+d,+coverage,+environment,+cell_budget,+voxel_budget},+items,+profiles,+entities,+min,+server,+fast,+loaded,+complete,+rain,+portal,+mount,+steps,+clip}=request
  T.Context{items,G.Context{d,coverage,blocks,entities,voxel_budget},cells,coverage,min,server,fast,loaded,complete,rain,portal,mount,steps,clip,[]}
def completed(request:Request,engine:Game.Engine,catalog:S.Catalog,result:Result<&2,&2,T.Error,List<&2,T.Cell>>,blocks:List<&2,G.Obstacle>) -> Game.Engine & S.Catalog & Result<&2,&2,T.Error,T.Context>:
  match result:
    case Fail{error}: (engine,catalog,Fail{error})
    case Done{cells}: (engine,catalog,Done{context(request,blocks,cells)})
def converted(+request:Request,engine:Game.Engine,+reads:List<&2,L.Read>,result:S.Catalog & Result<&2,&2,String,List<&2,G.Obstacle>>) -> Game.Engine & S.Catalog & Result<&2,&2,T.Error,T.Context>:
  Request{+g,+items,+profiles,+entities,+min,+server,+fast,+loaded,+complete,+rain,+portal,+mount,+steps,+clip}=request
  (catalog,status)=result
  match status:
    case Fail{message}: (engine,catalog,Fail{T.Refused{message}})
    case Done{blocks}: completed(request,engine,catalog,cells(reads,profiles),blocks)
def queried(+request:Request,result:Game.Engine & S.Catalog & Result<&2,&2,Q.Error,Q.Observation>) -> Game.Engine & S.Catalog & Result<&2,&2,T.Error,T.Context>:
  (engine,catalog,status)=result
  match status:
    case Fail{cause}: (engine,catalog,Fail{T.Refused{Q.error_text(cause)}})
    case Done{Q.Observation{+box,+clear,+reads,+yields}}: converted(request,engine,reads,GP.captured_blocks(yields,catalog,[]))
def ready(engine:Game.Engine,catalog:S.Catalog,+request:Request) -> Game.Engine & S.Catalog & Result<&2,&2,T.Error,T.Context>:
  Request{GP.Request{+d,+coverage,+environment,+cell_budget,+voxel_budget},+items,+profiles,+entities,+min,+server,+fast,+loaded,+complete,+rain,+portal,+mount,+steps,+clip}=request
  queried(request,Q.query_engine(engine,catalog,Q.Request{d,G.inflate(coverage,F.from_u32(1)),environment,cell_budget,Q.AllYields{},[]}))
def guarded(engine:Game.Engine,catalog:S.Catalog,request:Request,status:Result<&2,&2,String,Unit>) -> Game.Engine & S.Catalog & Result<&2,&2,T.Error,T.Context>:
  match status:
    case Fail{message}: (engine,catalog,Fail{T.Refused{message}})
    case Done{unit}: ready(engine,catalog,request)
def capture(engine:Game.Engine,catalog:S.Catalog,+request:Request) -> Game.Engine & S.Catalog & Result<&2,&2,T.Error,T.Context>:
  Request{+geometry,+items,+profiles,+entities,+min,+server,+fast,+loaded,+complete,+rain,+portal,+mount,+steps,+clip}=request
  guarded(engine,catalog,request,GP.validation(geometry))
def attached(view:W.View,result:Game.Engine & S.Catalog & Result<&2,&2,T.Error,T.Context>) -> W.State & S.Catalog & Result<&2,&2,T.Error,T.Context>:
  (engine,catalog,status)=result
  (W.attach(engine,view),catalog,status)
def taken(catalog:S.Catalog,request:Request,result:Game.Engine & W.View) -> W.State & S.Catalog & Result<&2,&2,T.Error,T.Context>:
  (engine,view)=result
  attached(view,capture(engine,catalog,request))
def capture_world(world:W.State,catalog:S.Catalog,request:Request) -> W.State & S.Catalog & Result<&2,&2,T.Error,T.Context>:
  taken(catalog,request,W.take(world))
