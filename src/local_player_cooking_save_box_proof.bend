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
import ./local_player_cooking_save_box_laws.bend as Laws

def Laws.boxed_nondurable_save_retains_complete_session(completed_depth,anchor_depth,engine,identity,path,highwater,limits,lease,record,inventory,fresh,generation,maximum,catalog,detached,cooking,bodies,pending,entities,publication,snapshot,session,value,returned_player,attached):
  match completed_depth anchor_depth:
    case 1n+rest depth:
      Laws.boxed_nondurable_save_retains_complete_session(rest,depth,engine,identity,path,highwater,limits,lease,record,inventory,fresh,generation,maximum,catalog,detached,cooking,bodies,pending,entities,publication,snapshot,session,value,returned_player,attached)
    case 0n 1n+rest:
      Laws.boxed_nondurable_save_retains_complete_session(0n,rest,engine,identity,path,highwater,limits,lease,record,inventory,fresh,generation,maximum,catalog,detached,cooking,bodies,pending,entities,publication,snapshot,session,value,returned_player,attached)
    case 0n 0n:
      %Equal.sym(X.State,R.attach(engine,record,detached),returned_player,attached) :
        {(S.State{_,S.Shell{identity,path,highwater,limits,lease,maximum,catalog,
      inventory,fresh,generation,cooking}},session,value) ==
          (S.State{returned_player,S.Shell{identity,path,highwater,limits,lease,maximum,catalog,
      inventory,fresh,generation,cooking}},session,value) : S.State & L.Session & J.Value}
      {==}

def Laws.boxed_durable_without_snapshot_retains_complete_session(completed_depth,anchor_depth,engine,identity,path,highwater,limits,lease,record,inventory,fresh,generation,maximum,catalog,detached,cooking,bodies,pending,entities,publication,session,value,returned_player,attached):
  match completed_depth anchor_depth:
    case 1n+rest depth:
      Laws.boxed_durable_without_snapshot_retains_complete_session(rest,depth,engine,identity,path,highwater,limits,lease,record,inventory,fresh,generation,maximum,catalog,detached,cooking,bodies,pending,entities,publication,session,value,returned_player,attached)
    case 0n 1n+rest:
      Laws.boxed_durable_without_snapshot_retains_complete_session(0n,rest,engine,identity,path,highwater,limits,lease,record,inventory,fresh,generation,maximum,catalog,detached,cooking,bodies,pending,entities,publication,session,value,returned_player,attached)
    case 0n 0n:
      %Equal.sym(X.State,R.attach(engine,record,detached),returned_player,attached) :
        {(S.State{_,S.Shell{identity,path,highwater,limits,lease,maximum,catalog,
      inventory,fresh,generation,cooking}},session,value) ==
          (S.State{returned_player,S.Shell{identity,path,highwater,limits,lease,maximum,catalog,
      inventory,fresh,generation,cooking}},session,value) : S.State & L.Session & J.Value}
      {==}

def Laws.boxed_durable_save_uses_exact_captured_acknowledgement(completed_depth,anchor_depth,engine,identity,path,highwater,limits,lease,record,inventory,fresh,generation,maximum,catalog,detached,cooking,bodies,pending,entities,publication,snapshot,session,value,returned_player,attached):
  match completed_depth anchor_depth:
    case 1n+rest depth:
      Laws.boxed_durable_save_uses_exact_captured_acknowledgement(rest,depth,engine,identity,path,highwater,limits,lease,record,inventory,fresh,generation,maximum,catalog,detached,cooking,bodies,pending,entities,publication,snapshot,session,value,returned_player,attached)
    case 0n 1n+rest:
      Laws.boxed_durable_save_uses_exact_captured_acknowledgement(0n,rest,engine,identity,path,highwater,limits,lease,record,inventory,fresh,generation,maximum,catalog,detached,cooking,bodies,pending,entities,publication,snapshot,session,value,returned_player,attached)
    case 0n 0n:
      %Equal.sym(X.State,R.attach(engine,record,detached),returned_player,attached) :
        {(S.cooking_save_acknowledged(S.State{_,S.Shell{identity,path,highwater,limits,lease,maximum,catalog,
      inventory,fresh,generation,cooking}},snapshot),session,value) ==
          (S.cooking_save_acknowledged(S.State{returned_player,S.Shell{identity,path,highwater,limits,lease,maximum,catalog,
      inventory,fresh,generation,cooking}},snapshot),session,value) : S.State & L.Session & J.Value}
      {==}
