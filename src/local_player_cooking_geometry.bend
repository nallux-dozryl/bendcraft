import Base
import ./game.bend as G
import ./core.bend as C
import ./registry.bend as Registry
import ./local_player_cooking.bend as Cooking
import ./local_player_cooking_entity_owner.bend as Carrier
import ./local_player_cooking_geometry_owner.bend as Owner
import ./slab_collision.bend as Slab
import ./local_collision_world.bend as Collision
import ./cooking_effect_geometry.bend as Geometry
import ./cooking_effect_geometry_world.bend as World
import ./cooking_effect_entities_math.bend as Math
import ./cooking_world_store.bend as Store

# Authentication uses the actual retained Registry. The catalog is transient;
# saved entity Views restore without reusing a stale geometry capture.
def loaded(world:C.World,environment:Collision.Environment,
    restore:Maybe<&1,Owner.Owner> -> Cooking.Sidecar,
    result:Registry.Registry & Result<&2,&1,Slab.Error,Slab.Catalog>) ->
    G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>:
  (registry,status) = result
  match status:
    case Fail{error}: (G.Engine{world,registry},restore(None{}),Fail{"local-cooking:geometry-catalog:" ++ Slab.error_text(error)})
    case Done{catalog}: (G.Engine{world,registry},restore(Some{Owner.Owner{catalog,environment}}),Done{Unit{}})

def load_ready(engine:G.Engine,path:String,environment:Collision.Environment,
    restore:Maybe<&1,Owner.Owner> -> Cooking.Sidecar) -> IO(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>):
  G.Engine{world,registry} = engine
  do IO<G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>>:
    result : Registry.Registry & Result<&2,&1,Slab.Error,Slab.Catalog> <- Slab.Catalog.load(registry,path)
    return loaded(world,environment,restore,result)

def admitted(engine:G.Engine,path:String,environment:Collision.Environment,
    restore:Maybe<&1,Owner.Owner> -> Cooking.Sidecar,valid:Bool) ->
    IO(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>):
  match valid:
    case False{}: IO.pure(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>,
      (engine,restore(None{}),Fail{"local-cooking:invalid-context"}))
    case True{}: load_ready(engine,path,environment,restore)

def checked(registry:Registry.Registry,path:String,environment:Collision.Environment,
    restore:Maybe<&1,Owner.Owner> -> Cooking.Sidecar,result:C.World & Bool) ->
    IO(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>):
  (world,valid) = result
  admitted(G.Engine{world,registry},path,environment,restore,valid)

def load(sidecar:Cooking.Sidecar,engine:G.Engine,path:String,environment:Collision.Environment) ->
    IO(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>):
  match sidecar:
    case Cooking.Uninitialized{}:
      IO.pure(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>,(engine,Cooking.Uninitialized{},Fail{"local-cooking:uninitialized"}))
    case Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,carrier,child <> rest}:
      IO.pure(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>,
        (engine,Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,carrier,child <> rest},
          Fail{"local-cooking:noncanonical-sidecar-tail"}))
    case Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,Carrier.Unbound{},Nil{}}:
      IO.pure(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>,
        (engine,Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,Carrier.Unbound{},[]},
          Fail{"local-cooking:entity-owner-unbound"}))
    case Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,Carrier.PublicationOnly{publisher},Nil{}}:
      IO.pure(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>,
        (engine,Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,Carrier.PublicationOnly{publisher},[]},
          Fail{"local-cooking:entity-owner-unbound"}))
    case Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,
        Carrier.Bound{entity_context,owner,inputs,Some{geometry},publisher},Nil{}}:
      IO.pure(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>,
        (engine,Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,
          Carrier.Bound{entity_context,owner,inputs,Some{geometry},publisher},[]},Fail{"local-cooking:geometry-owner-already-bound"}))
    case Cooking.Initialized{+context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,
        Carrier.Bound{entity_context,owner,inputs,None{},publisher},Nil{}}:
      G.Engine{world,registry} = engine
      checked(registry,path,environment,
        geometry => Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,
          Carrier.Bound{entity_context,owner,inputs,geometry,publisher},[]},Cooking.checked_world(world,context))
    case Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,
        Carrier.TickBound{entity_context,owner,inputs,Some{geometry},publisher,tick},Nil{}}:
      IO.pure(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>,
        (engine,Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,
          Carrier.TickBound{entity_context,owner,inputs,Some{geometry},publisher,tick},[]},Fail{"local-cooking:geometry-owner-already-bound"}))
    case Cooking.Initialized{+context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,
        Carrier.TickBound{entity_context,owner,inputs,None{},publisher,tick},Nil{}}:
      G.Engine{world,registry} = engine
      checked(registry,path,environment,
        geometry => Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,
          Carrier.TickBound{entity_context,owner,inputs,geometry,publisher,tick},[]},Cooking.checked_world(world,context))

def request_prepared(position:C.Position,environment:Collision.Environment,value:Geometry.Prepared) -> World.Request:
  Geometry.Prepared{point,body,center,search,outer} = value
  World.Request{Math.dimension(position),outer,environment,4096n,65536}

def request(effect:Store.Effect,environment:Collision.Environment) -> Result<&2,&2,String,World.Request>:
  match effect:
    case Store.Experience{+position,request}:
      do Result<&2,&2,String,World.Request>:
        prepared : Geometry.Prepared <- Geometry.prepare(Math.center(position))
        return request_prepared(position,environment,prepared)
    case _: Fail{"local-cooking:unexpected-geometry-request"}

def captured(environment:Collision.Environment,
    result:G.Engine & Slab.Catalog & Result<&2,&2,String,Geometry.Context>) ->
    G.Engine & Owner.Owner & Result<&2,&2,String,Geometry.Context>:
  (engine,catalog,status) = result
  (engine,Owner.Owner{catalog,environment},status)

def capture_ready(engine:G.Engine,catalog:Slab.Catalog,+environment:Collision.Environment,
    status:Result<&2,&2,String,World.Request>) ->
    G.Engine & Owner.Owner & Result<&2,&2,String,Geometry.Context>:
  match status:
    case Fail{message}: (engine,Owner.Owner{catalog,environment},Fail{message})
    case Done{request}: captured(environment,World.capture(engine,catalog,request))

# Captures are per placement request, so a changed Core never uses old shapes.
# The parent's scanner returns both affine owners even on unknown/unloaded cells.
def capture(engine:G.Engine,owner:Owner.Owner,effect:Store.Effect) ->
    G.Engine & Owner.Owner & Result<&2,&2,String,Geometry.Context>:
  Owner.Owner{catalog,+environment} = owner
  capture_ready(engine,catalog,environment,request(effect,environment))
