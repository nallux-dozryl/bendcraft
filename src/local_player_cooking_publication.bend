import Base
import ./game.bend as G
import ./local_player_cooking.bend as Cooking
import ./local_player_cooking_entity_owner.bend as Owner
import ./local_player_cooking_publication_owner.bend as Publisher
import ./local_player_cooking_publication_codec.bend as Codec
import ./cooking_effect_publication_journal.bend as Journal
import ./cooking_world.bend as CW
import ./cooking_world_bindings.bend as B
import ./cooking_world_store.bend as Store

def bindings(context:CW.Context) -> B.Catalog:
  CW.Context{catalog,campfire,fuel,depth} = context
  catalog

def initialize_ordered(result:G.Engine & Publisher.Carrier & Map<&2,Nat> & Result<&2,&2,String,Unit>) ->
    Publisher.Carrier & G.Engine & Map<&2,Nat> & Result<&2,&2,String,Unit>:
  (engine,publisher,incarnations,status) = result
  (publisher,engine,incarnations,status)

def initialized(restore:Map<&2,Nat> -> Owner.Carrier -> Cooking.Sidecar,
    result:Owner.Carrier & G.Engine & Map<&2,Nat> & Result<&2,&2,String,Unit>) ->
    G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>:
  (owner,engine,incarnations,status) = result
  (engine,restore(incarnations)(owner),status)

# Bodies are loaded first. The same actual catalog authenticates both fresh
# journal construction and historical receipt bindings; saved counters are
# restored as a complete tree, never derived from pending producer sources.
def initialize(engine:G.Engine,sidecar:Cooking.Sidecar,saved:Maybe<&2,Codec.Recovery>,pending:List<&2,Store.Effect>) ->
    G.Engine & Cooking.Sidecar & Result<&2,&2,String,Unit>:
  match sidecar:
    case Cooking.Uninitialized{}: (engine,Cooking.Uninitialized{},Fail{"local-cooking:uninitialized"})
    case Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,owner,child <> rest}:
      (engine,Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,owner,child <> rest},
        Fail{"local-cooking:noncanonical-sidecar-tail"})
    case Cooking.Initialized{+context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,owner,Nil{}}:
      initialized(incarnations => owner => Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,owner,[]},
        Owner.with_publisher(G.Engine & Map<&2,Nat> & Result<&2,&2,String,Unit>,owner,
          publisher => initialize_ordered(Publisher.initialize(engine,bindings(Cooking.cooking_context(context)),
            publisher,incarnations,pending,saved))))

def recovered(+incarnations:Map<&2,Nat>,result:Publisher.Carrier & Maybe<&2,Journal.View>) ->
    Publisher.Carrier & Maybe<&2,Codec.Recovery>:
  match result:
    case (publisher,None{}): (publisher,None{})
    case (publisher,Some{view}): (publisher,Some{Codec.Recovery{incarnations,view}})

def snapshotted(restore:Owner.Carrier -> Cooking.Sidecar,result:Owner.Carrier & Maybe<&2,Codec.Recovery>) ->
    Cooking.Sidecar & Maybe<&2,Codec.Recovery>:
  (owner,value) = result
  (restore(owner),value)

def snapshot(sidecar:Cooking.Sidecar) -> Cooking.Sidecar & Maybe<&2,Codec.Recovery>:
  match sidecar:
    case Cooking.Uninitialized{}: (Cooking.Uninitialized{},None{})
    case Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,+incarnations,acknowledged,owner,tail}:
      snapshotted(owner => Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,owner,tail},
        Owner.with_publisher(Maybe<&2,Codec.Recovery>,owner,
          publisher => recovered(incarnations,Publisher.snapshot(publisher))))

def prepared(restore:Owner.Carrier -> Cooking.Sidecar,result:Owner.Carrier & Maybe<&2,Publisher.Prepared>) ->
    Cooking.Sidecar & Maybe<&2,Publisher.Prepared>:
  (owner,value) = result
  (restore(owner),value)

def prepare_save(sidecar:Cooking.Sidecar) -> Cooking.Sidecar & Maybe<&2,Publisher.Prepared>:
  match sidecar:
    case Cooking.Uninitialized{}: (Cooking.Uninitialized{},None{})
    case Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,+incarnations,acknowledged,owner,tail}:
      prepared(owner => Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,owner,tail},
        Owner.with_publisher(Maybe<&2,Publisher.Prepared>,owner,publisher => Publisher.prepare(publisher,incarnations)))

def save_returned(restore:Owner.Carrier -> Cooking.Sidecar,result:Owner.Carrier & Unit) -> Cooking.Sidecar:
  (owner,unit) = result
  restore(owner)

def save_publisher_completed(publisher:Publisher.Carrier,result:Result<&2,&1,String,Journal.SaveCommit>) -> Publisher.Carrier & Unit:
  (Publisher.save_completed(publisher,result),Unit{})

def uninitialized_completed(result:Result<&2,&1,String,Journal.SaveCommit>) -> Cooking.Sidecar:
  match result:
    case Fail{message}: Cooking.Uninitialized{}
    case Done{Journal.FullCookingSaveCommitted{snapshot}}: Cooking.Uninitialized{}

def save_completed(sidecar:Cooking.Sidecar,result:Result<&2,&1,String,Journal.SaveCommit>) -> Cooking.Sidecar:
  match sidecar:
    case Cooking.Uninitialized{}: uninitialized_completed(result)
    case Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,owner,tail}:
      save_returned(owner => Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,owner,tail},
        Owner.with_publisher(Unit,owner,publisher => save_publisher_completed(publisher,result)))

def snapshotted_ready(restore:Owner.Carrier -> Cooking.Sidecar,result:Owner.Carrier & Result<&2,&2,String,Unit>) ->
    Cooking.Sidecar & Result<&2,&2,String,Unit>:
  (owner,status) = result
  (restore(owner),status)

def ready(sidecar:Cooking.Sidecar) -> Cooking.Sidecar & Result<&2,&2,String,Unit>:
  match sidecar:
    case Cooking.Uninitialized{}: (Cooking.Uninitialized{},Done{Unit{}})
    case Cooking.Initialized{context,light,loading,entries,phase,keys,+effects,details,+incarnations,acknowledged,owner,tail}:
      snapshotted_ready(owner => Cooking.Initialized{context,light,loading,entries,phase,keys,effects,details,incarnations,acknowledged,owner,tail},
        Owner.with_publisher(Result<&2,&2,String,Unit>,owner,publisher => Publisher.ready(publisher,effects,incarnations)))
