import Base
import ./game.bend as G
import ./cooking_world_bindings.bend as B
import ./cooking_world_store.bend as Store
import ./cooking_effect_publication.bend as Publication
import ./cooking_effect_publication_journal.bend as Journal
import ./local_player_cooking_publication_codec.bend as Codec
import ./core.bend as C

# Publication is independent of the entity/RNG domain. The recursive owner is
# boxed by the native representation; fresh/restored owners use a canonical
# empty tail, while every refusal retains an arbitrary existing tail.
type Carrier is Type:
  Unbound{}
  Bound{context:Publication.Context,journal:Journal.State,tail:List<&1,Carrier>}
type Prepared is Data:
  Prepared{recovery:Codec.Recovery,snapshot:Journal.Snapshot}

def empty() -> Carrier: Unbound{}

def contains_owned(effects:List<&2,Store.Effect>) -> Bool:
  match effects:
    case Nil{}: False{}
    case Store.OwnedDirty{source} <> rest: True{}
    case other <> rest: contains_owned(rest)

def snapshotted(context:Publication.Context,tail:List<&1,Carrier>,result:Journal.State & Journal.View) ->
    Carrier & Maybe<&2,Journal.View>:
  (owner,view) = result
  (Bound{context,owner,tail},Some{view})

def snapshot(carrier:Carrier) -> Carrier & Maybe<&2,Journal.View>:
  match carrier:
    case Unbound{}: (Unbound{},None{})
    case Bound{context,owner,tail}: snapshotted(context,tail,Journal.inspect(owner))

def prepared_view(context:Publication.Context,tail:List<&1,Carrier>,incarnations:Map<&2,Nat>,+snapshot:Journal.Snapshot,
    result:Journal.State & Journal.View) -> Carrier & Maybe<&2,Prepared>:
  (owner,view) = result
  (Bound{context,owner,tail},Some{Prepared{Codec.Recovery{incarnations,Journal.saved_view(view,snapshot)},snapshot}})

def prepared_snapshot(context:Publication.Context,tail:List<&1,Carrier>,incarnations:Map<&2,Nat>,
    result:Journal.State & Journal.Snapshot) -> Carrier & Maybe<&2,Prepared>:
  (owner,snapshot) = result
  prepared_view(context,tail,incarnations,snapshot,Journal.inspect(owner))

# Only the immutable image is marked clean here. The actual live journal is
# retained until the writer supplies a receipt backed by A.Durable.
def prepare(carrier:Carrier,incarnations:Map<&2,Nat>) -> Carrier & Maybe<&2,Prepared>:
  match carrier:
    case Unbound{}: (Unbound{},None{})
    case Bound{context,owner,tail}: prepared_snapshot(context,tail,incarnations,Journal.snapshot(owner))

def absent_completed(result:Result<&2,&1,String,Journal.SaveCommit>) -> Carrier:
  match result:
    case Fail{message}: Unbound{}
    case Done{Journal.FullCookingSaveCommitted{snapshot}}: Unbound{}

def save_completed(carrier:Carrier,result:Result<&2,&1,String,Journal.SaveCommit>) -> Carrier:
  match carrier:
    case Unbound{}: absent_completed(result)
    case Bound{context,owner,tail}: Bound{context,Journal.save_completed(owner,result),tail}

def ready(carrier:Carrier,effects:List<&2,Store.Effect>,incarnations:Map<&2,Nat>) -> Carrier & Result<&2,&2,String,Unit>:
  match carrier:
    case Unbound{}:
      (Unbound{},Bool.pick(Result<&2,&2,String,Unit>,contains_owned(effects) || Codec.map_nonempty(incarnations),
        Fail{"local-cooking:owned-dirty-without-publication-recovery"},Done{Unit{}}))
    case Bound{context,owner,Nil{}}: (Bound{context,owner,[]},Done{Unit{}})
    case Bound{context,owner,child <> rest}:
      (Bound{context,owner,child <> rest},Fail{"local-cooking:noncanonical-publication-tail"})

def restored(engine:G.Engine,context:Publication.Context,previous:Map<&2,Nat>,saved:Map<&2,Nat>,
    result:Result<&2,&1,String,Journal.State>) -> G.Engine & Carrier & Map<&2,Nat> & Result<&2,&2,String,Unit>:
  match result:
    case Fail{message}: (engine,Unbound{},previous,Fail{message})
    case Done{owner}: (engine,Bound{context,owner,[]},saved,Done{Unit{}})

def recovery_checked(valid:Bool,engine:G.Engine,+context:Publication.Context,previous:Map<&2,Nat>,
    saved:Map<&2,Nat>,view:Journal.View) -> G.Engine & Carrier & Map<&2,Nat> & Result<&2,&2,String,Unit>:
  match valid:
    case False{}: (engine,Unbound{},previous,Fail{"local-cooking:invalid-publication-recovery"})
    case True{}: restored(engine,context,previous,saved,Publication.restore_journal(context,view))

def fresh_checked(missing:Bool,engine:G.Engine,context:Publication.Context,incarnations:Map<&2,Nat>) ->
    G.Engine & Carrier & Map<&2,Nat> & Result<&2,&2,String,Unit>:
  match missing:
    case True{}: (engine,Unbound{},incarnations,Fail{"local-cooking:owned-dirty-without-publication-recovery"})
    case False{}: (engine,Bound{context,Journal.new(),[]},incarnations,Done{Unit{}})

def recovery(engine:G.Engine,+context:Publication.Context,incarnations:Map<&2,Nat>,effects:List<&2,Store.Effect>,
    saved:Maybe<&2,Codec.Recovery>) -> G.Engine & Carrier & Map<&2,Nat> & Result<&2,&2,String,Unit>:
  match saved:
    case None{}: fresh_checked(contains_owned(effects),engine,context,incarnations)
    case Some{Codec.Recovery{+counters,+view}}:
      recovery_checked(Codec.map_valid(counters) && Journal.view_valid(view) && Codec.recovery_valid_counters(counters,view),
        engine,context,incarnations,counters,view)

def authenticated(incarnations:Map<&2,Nat>,effects:List<&2,Store.Effect>,saved:Maybe<&2,Codec.Recovery>,
    result:G.Engine & Result<&2,&2,String,Publication.Context>) -> G.Engine & Carrier & Map<&2,Nat> & Result<&2,&2,String,Unit>:
  match result:
    case (engine,Fail{message}): (engine,Unbound{},incarnations,Fail{message})
    case (engine,Done{context}): recovery(engine,context,incarnations,effects,saved)

def initialize(engine:G.Engine,catalog:B.Catalog,carrier:Carrier,incarnations:Map<&2,Nat>,
    effects:List<&2,Store.Effect>,saved:Maybe<&2,Codec.Recovery>) ->
    G.Engine & Carrier & Map<&2,Nat> & Result<&2,&2,String,Unit>:
  match carrier:
    case Unbound{}: authenticated(incarnations,effects,saved,Publication.initialize(engine,catalog))
    case Bound{context,owner,tail}:
      (engine,Bound{context,owner,tail},incarnations,Fail{"local-cooking:publication-owner-already-bound"})

def published(context:Publication.Context,result:G.Engine & Journal.State & Result<&2,&2,String,Journal.Receipt>) ->
    G.Engine & Carrier & Result<&2,&2,String,Unit>:
  (engine,owner,status) = result
  (engine,Bound{context,owner,[]},Result.map(&2,&2,String,Journal.Receipt,Unit,receipt => Unit{},status))

def dirty_at(engine:G.Engine,carrier:Carrier,producer:Journal.Source,current:Maybe<&2,Journal.Source>,position:C.Position) ->
    G.Engine & Carrier & Result<&2,&2,String,Unit>:
  match carrier:
    case Unbound{}: (engine,Unbound{},Fail{"local-cooking:publication-owner-required"})
    case Bound{context,owner,child <> rest}:
      (engine,Bound{context,owner,child <> rest},Fail{"local-cooking:noncanonical-publication-tail"})
    case Bound{+context,owner,Nil{}}:
      published(context,Publication.dirty(engine,context,producer,current,position,owner))

def position(source:Journal.Source) -> C.Position:
  Journal.Source{point,binding,incarnation} = source
  point

def dirty(engine:G.Engine,carrier:Carrier,+producer:Journal.Source,current:Maybe<&2,Journal.Source>) ->
    G.Engine & Carrier & Result<&2,&2,String,Unit>:
  dirty_at(engine,carrier,producer,current,position(producer))
