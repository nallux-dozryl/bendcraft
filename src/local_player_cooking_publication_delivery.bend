import Base
import ./game.bend as G
import ./core.bend as C
import ./registry.bend as Registry
import ./local_player_cooking.bend as Cooking
import ./local_player_cooking_entities.bend as Entities
import ./local_player_cooking_entity_owner.bend as Owner
import ./local_player_cooking_publication_owner.bend as Publisher
import ./local_player_cooking_dirty_stamp.bend as Sources
import ./cooking_world_bindings.bend as B
import ./cooking_world_store.bend as Store
import ./cooking_effect_publication_journal.bend as J

def with_effects(sidecar:Cooking.Sidecar,effects:List<&2,Store.Effect>) -> Cooking.Sidecar:
  match sidecar:
    case Cooking.Uninitialized{}: Cooking.Uninitialized{}
    case Cooking.Initialized{context,light,loading,entries,phase,keys,old,details,incarnations,acknowledged,owner,tail}:
      Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,owner,tail}

def source_selected(hit:Bool,source:J.Source,found:Maybe<&2,J.Source>) -> Result<&2,&2,String,Maybe<&2,J.Source>>:
  match hit found:
    case False{} found: Done{found}
    case True{} None{}: Done{Some{source}}
    case True{} Some{previous}: Fail{"local-cooking:duplicate-current-publication-owner"}

def source_returned(+point:C.Position,source:J.Source,hit:Bool,
    result:Result<&2,&2,String,Maybe<&2,J.Source>>) -> Result<&2,&2,String,Maybe<&2,J.Source>>:
  match result:
    case Fail{message}: Fail{message}
    case Done{found}: source_selected(hit,source,found)

def source_at(values:List<&2,J.Source>,+point:C.Position) -> Result<&2,&2,String,Maybe<&2,J.Source>>:
  match values:
    case Nil{}: Done{None{}}
    case +head <> rest:
      J.Source{candidate,binding,incarnation} = head
      source_returned(point,head,B.equal_position(candidate,point),source_at(rest,point))

def dirty_ordered(result:G.Engine & Publisher.Carrier & Result<&2,&2,String,Unit>) ->
    Publisher.Carrier & G.Engine & Result<&2,&2,String,Unit>:
  (engine,publisher,status) = result
  (publisher,engine,status)

def dirty_returned(restore:Owner.Carrier -> Cooking.Sidecar,
    result:Owner.Carrier & G.Engine & Result<&2,&2,String,Unit>) -> G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>:
  (owner,engine,status) = result
  (engine,restore(owner),status)

def dirty_current(engine:G.Engine,restore:Owner.Carrier -> Cooking.Sidecar,owner:Owner.Carrier,source:J.Source,
    result:Result<&2,&2,String,Maybe<&2,J.Source>>) -> G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>:
  match result:
    case Fail{message}: (engine,restore(owner),Fail{message})
    case Done{current}:
      dirty_returned(restore,Owner.with_publisher(G.Engine & Result<&2,&2,String,Unit>,owner,
        publisher => dirty_ordered(Publisher.dirty(engine,publisher,source,current))))

def dirty_captured(engine:G.Engine,restore:List<&1,Store.Entry> -> Owner.Carrier -> Cooking.Sidecar,owner:Owner.Carrier,
    +source:J.Source,result:List<&1,Store.Entry> & List<&2,J.Source>) ->
    G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>:
  (entries,values) = result
  dirty_current(engine,owner => restore(entries)(owner),owner,source,source_at(values,Publisher.position(source)))

# The actual current descriptor is read from the retained Store, not supplied
# by a request or inferred from an older queued source. The Core query inside
# Publisher.dirty also validates the current state and four loaded neighbours.
def dirty(engine:G.Engine,sidecar:Cooking.Sidecar,source:J.Source) ->
    G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>:
  match sidecar:
    case Cooking.Uninitialized{}: (engine,Cooking.Uninitialized{},Fail{"local-cooking:uninitialized"})
    case Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,owner,child <> rest}:
      (engine,Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,owner,child <> rest},
        Fail{"local-cooking:noncanonical-sidecar-tail"})
    case Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,+incarnations,acknowledged,owner,Nil{}}:
      dirty_captured(engine,entries => owner => Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,owner,[]},
        owner,source,Sources.captured(entries,incarnations))

def stopped(rest:List<&2,Store.Effect>,engine:G.Engine,message:String,result:Cooking.Sidecar & List<&2,Store.Effect>) ->
    IO(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>):
  (sidecar,pending) = result
  IO.pure(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>,
    (engine,with_effects(sidecar,List.append(&2,Store.Effect,pending,rest)),Fail{message}))

def completed(rest:List<&2,Store.Effect>,result:G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>,
    next:G.Engine -> Cooking.Sidecar -> IO(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>)) ->
    IO(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>):
  (engine,sidecar,status) = result
  match status:
    case Fail{message}: stopped(rest,engine,message,Cooking.pending_snapshot(sidecar))
    case Done{unit}: next(engine)(sidecar)

def dirty_completed(+effect:Store.Effect,rest:List<&2,Store.Effect>,
    result:G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>,
    next:G.Engine -> Cooking.Sidecar -> IO(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>)) ->
    IO(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>):
  (engine,sidecar,status) = result
  match status:
    case Fail{message}: IO.pure(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>,
      (engine,with_effects(sidecar,effect <> rest),Fail{message}))
    case Done{unit}: next(engine)(sidecar)

def effect(+value:Store.Effect,rest:List<&2,Store.Effect>,engine:G.Engine,sidecar:Cooking.Sidecar,
    next:G.Engine -> Cooking.Sidecar -> IO(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>)) ->
    IO(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>):
  match value:
    case Store.OwnedDirty{source}: dirty_completed(value,rest,dirty(engine,sidecar,source),next)
    case other:
      do IO<G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>>:
        result : G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit> <-
          Entities.deliver_engine_io(with_effects(sidecar,[other]),engine)
        completed(rest,result,next)

# Each actual effect is committed at most once. Successful prefixes stay in
# their returned owners; the first refused effect and the ordered suffix are
# restored exactly. The existing entity route still owns geometry/clock retry.
def deliver(effects:List<&2,Store.Effect>,engine:G.Engine,sidecar:Cooking.Sidecar) ->
    IO(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>):
  match effects:
    case Nil{}: IO.pure(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>,(engine,sidecar,Done{Unit{}}))
    case head <> +rest:
      effect(head,rest,engine,sidecar,engine => sidecar => deliver(rest,engine,with_effects(sidecar,[])))

def started(engine:G.Engine,result:Cooking.Sidecar & List<&2,Store.Effect>) ->
    IO(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>):
  (sidecar,effects) = result
  deliver(effects,engine,with_effects(sidecar,[]))

def checked(sidecar:Cooking.Sidecar,registry:Registry.Registry,result:C.World & Bool) ->
    IO(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>):
  match result:
    case (world,False{}): IO.pure(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>,
      (G.Engine{world,registry},sidecar,Fail{"local-cooking:invalid-context"}))
    case (world,True{}): started(G.Engine{world,registry},Cooking.pending_snapshot(sidecar))

def check_engine(context:Cooking.Context,sidecar:Cooking.Sidecar,engine:G.Engine) ->
    IO(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>):
  G.Engine{world,registry} = engine
  checked(sidecar,registry,Cooking.checked_world(world,context))

def deliver_io(engine:G.Engine,sidecar:Cooking.Sidecar) -> IO(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>):
  match sidecar:
    case Cooking.Uninitialized{}:
      IO.pure(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>,(engine,Cooking.Uninitialized{},Done{Unit{}}))
    case Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,owner,child <> rest}:
      IO.pure(G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>,
        (engine,Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,owner,child <> rest},
          Fail{"local-cooking:noncanonical-sidecar-tail"}))
    case Cooking.Initialized{+context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,owner,Nil{}}:
      check_engine(context,Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,owner,[]},engine)
