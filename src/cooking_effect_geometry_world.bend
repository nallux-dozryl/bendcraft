import Base
import ./cooking_effect_geometry.bend as P
import ./cooking_effect_geometry_voxel.bend as V
import ./slab_collision_world.bend as Q
import ./slab_collision.bend as S
import ./local_collision_world.bend as L
import ./client_world.bend as W
import ./geometry.bend as A
import ./f64.bend as F
import ./game.bend as G
import ./core.bend as C

# Capture is a read transaction. Both affine owners return on every path.
# Environment facts come from the actual caller; unresolved facts never become air.
type Request is Data:
  Request{dimension:String,coverage:A.AABB,environment:L.Environment,cell_budget:Nat,voxel_budget:U32}

def range(grid:Q.Grid) -> V.Range:
  Q.Grid{coords,start,end} = grid
  V.Range{V.Axis{coords,False{}},start,end}
def shape(value:Q.QueryShape) -> Result<&2,&2,String,V.Shape>:
  match value:
    case Q.EmptyShape{}: Fail{"geometry:unexpected-empty-block"}
    case Q.RectShape{x,y,z}: Done{V.cube_rect(range(x),range(y),range(z))}
def obstacle(position:C.Position,+box:A.AABB,value:Q.CellShape) -> Result<&2,&2,String,P.Obstacle>:
  match position value:
    case C.Position{dimension,x,y,z} Q.FullShape{}:
      do Result<&2,&2,String,P.Obstacle>:
        grid : V.Shape <- shape(Q.slab_grids(S.DoubleSlab{},W.Cell{x,y,z,0}))
        return P.Obstacle{box,grid,True{}}
    case C.Position{dimension,x,y,z} Q.PartialShape{kind}:
      do Result<&2,&2,String,P.Obstacle>:
        grid : V.Shape <- shape(Q.slab_grids(kind,W.Cell{x,y,z,0}))
        return P.Obstacle{box,grid,False{}}
    case _ Q.AirShape{}: Fail{"geometry:unexpected-air-yield"}
def converted(position:C.Position,box:A.AABB,result:S.Catalog & Result<&2,&2,Q.Error,Q.CellShape>) -> S.Catalog & Result<&2,&2,String,P.Obstacle>:
  (catalog,status) = result
  match status:
    case Fail{error}: (catalog,Fail{Q.error_text(error)})
    case Done{kind}: (catalog,obstacle(position,box,kind))
def captured_one(reversed:List<&2,P.Obstacle>,result:S.Catalog & Result<&2,&2,String,P.Obstacle>,next:S.Catalog -> List<&2,P.Obstacle> -> S.Catalog & Result<&2,&2,String,List<&2,P.Obstacle>>) -> S.Catalog & Result<&2,&2,String,List<&2,P.Obstacle>>:
  (catalog,status) = result
  match status:
    case Fail{error}: (catalog,Fail{error})
    case Done{value}: next(catalog,value <> reversed)
def captured_blocks(values:List<&2,Q.Yield>,catalog:S.Catalog,reversed:List<&2,P.Obstacle>) -> S.Catalog & Result<&2,&2,String,List<&2,P.Obstacle>>:
  match values:
    case Nil{}: (catalog,Done{List.reverse(&2,P.Obstacle,reversed)})
    case Q.Yield{position,state,box} <> rest:
      captured_one(reversed,converted(position,box,Q.classify(catalog,state)),next => left => captured_blocks(rest,next,left))
def context_complete(request:Request,blocks:List<&2,P.Obstacle>) -> P.Context:
  Request{dimension,coverage,environment,cells,budget} = request
  P.Context{dimension,coverage,blocks,[],budget}
def context(request:Request,result:Result<&2,&2,String,List<&2,P.Obstacle>>) -> Result<&2,&2,String,P.Context>:
  match result:
    case Fail{error}: Fail{error}
    case Done{blocks}: Done{context_complete(request,blocks)}
def captured(request:Request,engine:G.Engine,result:S.Catalog & Result<&2,&2,String,List<&2,P.Obstacle>>) -> G.Engine & S.Catalog & Result<&2,&2,String,P.Context>:
  (catalog,status) = result
  (engine,catalog,context(request,status))
def queried(request:Request,result:G.Engine & S.Catalog & Result<&2,&2,Q.Error,Q.Observation>) -> G.Engine & S.Catalog & Result<&2,&2,String,P.Context>:
  (engine,catalog,status) = result
  match status:
    case Fail{error}: (engine,catalog,Fail{Q.error_text(error)})
    case Done{Q.Observation{box,clear,reads,yields}}: captured(request,engine,captured_blocks(yields,catalog,[]))
def validation(request:Request) -> Result<&2,&2,String,Unit>:
  Request{dimension,+coverage,+environment,cells,budget} = request
  do Result<&2,&2,String,Unit>:
    P.guard(Maybe.is_none(&2,U32,A.AABB.invalid_field(coverage)) && W.query_ordered(coverage),"geometry:invalid-coverage")
    # The scan has a one-block halo. Every yielded whole block bound has another
    # one-block margin inside the known border interior, so Java's border filter
    # accepts every possible obstacle without inventing a global border value.
    P.guard(L.query_admitted(P.inflate(coverage,F.from_u32(2)),environment),"geometry:environment-or-border-unresolved")
def capture_ready(engine:G.Engine,catalog:S.Catalog,+request:Request) -> G.Engine & S.Catalog & Result<&2,&2,String,P.Context>:
  Request{dimension,coverage,environment,cells,budget} = request
  queried(request,Q.query_engine(engine,catalog,Q.Request{dimension,P.inflate(coverage,F.from_u32(1)),environment,cells,Q.AllYields{},[]}))
def capture_refused(engine:G.Engine,catalog:S.Catalog,reason:String) -> G.Engine & S.Catalog & Result<&2,&2,String,P.Context>:
  (engine,catalog,Fail{reason})
def capture_gate(engine:G.Engine,catalog:S.Catalog,request:Request,status:Result<&2,&2,String,Unit>) -> G.Engine & S.Catalog & Result<&2,&2,String,P.Context>:
  match status:
    case Fail{error}: capture_refused(engine,catalog,error)
    case Done{unit}: capture_ready(engine,catalog,request)
def capture(engine:G.Engine,catalog:S.Catalog,+request:Request) -> G.Engine & S.Catalog & Result<&2,&2,String,P.Context>:
  capture_gate(engine,catalog,request,validation(request))
def attached(view:W.View,result:G.Engine & S.Catalog & Result<&2,&2,String,P.Context>) -> W.State & S.Catalog & Result<&2,&2,String,P.Context>:
  (engine,catalog,status) = result
  (W.attach(engine,view),catalog,status)
def taken(catalog:S.Catalog,request:Request,result:G.Engine & W.View) -> W.State & S.Catalog & Result<&2,&2,String,P.Context>:
  (engine,view) = result
  attached(view,capture(engine,catalog,request))
def capture_world(world:W.State,catalog:S.Catalog,request:Request) -> W.State & S.Catalog & Result<&2,&2,String,P.Context>:
  taken(catalog,request,W.take(world))
