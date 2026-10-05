import Base
import ./local_player_session.bend as S
import ./local_player_runtime.bend as R
import ./local_phase_runtime.bend as X
import ./local_player_cooking.bend as Cooking
import ./local_player_cooking_storage.bend as CS
import ./local_player_cooking_publication_codec.bend as Publication
import ./cooking_effect_publication_journal.bend as Journal
import ./cooking_world_store.bend as Store
import ./extended_persistence.bend as E
import ./persistence.bend as P
import ./world_lock.bend as WL
import ./game.bend as G
import ./local_player_record.bend as Record
import ./player_inventory.bend as I
import ./player_inventory_codec.bend as IC
import ./world_generation_settings.bend as WG
import ./live.bend as L
import ./json.bend as J

# These builders only produce the actual recursive input constructors. They
# define no result projection, save implementation or model of external IO.
def anchor(depth:Nat,transient:R.Transient,snapshot:Maybe<&2,Journal.Snapshot>) -> S.CookingSaveAnchor:
  match depth:
    case 0n: S.SaveAnchorData{transient,snapshot}
    case 1n+rest: S.SaveAnchorNested{anchor(rest,transient,snapshot)}

def completed(depth:Nat,held:S.CookingSaveAnchor,
    result:E.State<CS.Saved> & L.Session & J.Value & E.SaveCompletion) -> S.CompletedSave:
  match depth:
    case 0n: S.SaveCompletedData{held,result}
    case 1n+rest: S.SaveCompletedNested{completed(rest,held,result)}

# An arbitrary JSON reply cannot turn NotCommitted into acknowledgement.
# The actual attach-return premise preserves every Runtime.Detached field,
# including owned state/motion/metadata tails and the raw Receiver. The live
# Sidecar is arbitrary; copied physical/recovery DTOs cannot replace it.
law boxed_nondurable_save_retains_complete_session:
  for completed_depth:Nat
  for anchor_depth:Nat
  for engine:G.Engine
  for identity:String
  for path:String
  for highwater:U32
  for limits:P.Limits
  for lease:WL.Lease
  for record:Record.Record
  for inventory:I.State
  for fresh:Bool
  for generation:WG.Settings
  for maximum:U32
  for catalog:List<&2,E.Operation>
  for detached:R.Detached
  for cooking:Cooking.Sidecar
  for bodies:List<&2,CS.Body>
  for pending:List<&2,Store.Effect>
  for entities:Maybe<&2,CS.EntityRecovery>
  for publication:Maybe<&2,Publication.Recovery>
  for snapshot:Maybe<&2,Journal.Snapshot>
  for session:L.Session
  for value:J.Value
  for returned_player:X.State
  for attached:{R.attach(engine,record,detached) == returned_player : X.State}
  {S.cooking_saved(completed(completed_depth,
      anchor(anchor_depth,R.Transient{detached,cooking},snapshot),
      (E.State{P.State{engine,identity,path,highwater,limits,lease},
      CS.Saved{IC.Saved{record,inventory,fresh,generation},bodies,pending,entities,publication},maximum,catalog},session,value,E.NotCommitted{}))) ==
    (S.State{returned_player,S.Shell{identity,path,highwater,limits,lease,maximum,catalog,
      inventory,fresh,generation,cooking}},session,value) : S.State & L.Session & J.Value}

# Even a typed durable completion has no captured publication snapshot here.
# All retained owners and the exact returned transport Session/value survive;
# no stale recovery DTO is installed into the live cooking sidecar.
law boxed_durable_without_snapshot_retains_complete_session:
  for completed_depth:Nat
  for anchor_depth:Nat
  for engine:G.Engine
  for identity:String
  for path:String
  for highwater:U32
  for limits:P.Limits
  for lease:WL.Lease
  for record:Record.Record
  for inventory:I.State
  for fresh:Bool
  for generation:WG.Settings
  for maximum:U32
  for catalog:List<&2,E.Operation>
  for detached:R.Detached
  for cooking:Cooking.Sidecar
  for bodies:List<&2,CS.Body>
  for pending:List<&2,Store.Effect>
  for entities:Maybe<&2,CS.EntityRecovery>
  for publication:Maybe<&2,Publication.Recovery>
  for session:L.Session
  for value:J.Value
  for returned_player:X.State
  for attached:{R.attach(engine,record,detached) == returned_player : X.State}
  {S.cooking_saved(completed(completed_depth,
      anchor(anchor_depth,R.Transient{detached,cooking},None{}),
      (E.State{P.State{engine,identity,path,highwater,limits,lease},
      CS.Saved{IC.Saved{record,inventory,fresh,generation},bodies,pending,entities,publication},maximum,catalog},session,value,E.DurablyCommitted{}))) ==
    (S.State{returned_player,S.Shell{identity,path,highwater,limits,lease,maximum,catalog,
      inventory,fresh,generation,cooking}},session,value) : S.State & L.Session & J.Value}

# The typed durable branch passes the exact captured snapshot to the actual
# acknowledgement consumer on the actual attached owner. Its validation and
# journal mutation remain that consumer's contract; this law does not prove
# filesystem durability or assert that an arbitrary snapshot clears a journal.
law boxed_durable_save_uses_exact_captured_acknowledgement:
  for completed_depth:Nat
  for anchor_depth:Nat
  for engine:G.Engine
  for identity:String
  for path:String
  for highwater:U32
  for limits:P.Limits
  for lease:WL.Lease
  for record:Record.Record
  for inventory:I.State
  for fresh:Bool
  for generation:WG.Settings
  for maximum:U32
  for catalog:List<&2,E.Operation>
  for detached:R.Detached
  for cooking:Cooking.Sidecar
  for bodies:List<&2,CS.Body>
  for pending:List<&2,Store.Effect>
  for entities:Maybe<&2,CS.EntityRecovery>
  for publication:Maybe<&2,Publication.Recovery>
  for snapshot:Journal.Snapshot
  for session:L.Session
  for value:J.Value
  for returned_player:X.State
  for attached:{R.attach(engine,record,detached) == returned_player : X.State}
  {S.cooking_saved(completed(completed_depth,
      anchor(anchor_depth,R.Transient{detached,cooking},Some{snapshot}),
      (E.State{P.State{engine,identity,path,highwater,limits,lease},
      CS.Saved{IC.Saved{record,inventory,fresh,generation},bodies,pending,entities,publication},maximum,catalog},session,value,E.DurablyCommitted{}))) ==
    (S.cooking_save_acknowledged(S.State{returned_player,S.Shell{identity,path,highwater,limits,lease,maximum,catalog,
      inventory,fresh,generation,cooking}},snapshot),session,value) : S.State & L.Session & J.Value}
