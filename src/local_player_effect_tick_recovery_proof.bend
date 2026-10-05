import Base
import ./local_player_effect_tick_recovery_laws.bend as L
import ./local_player_effect_tick_recovery.bend as Q
import ./cooking_effect_entities_model.bend as E
import ./item_entity_tick_model.bend as T
import ./random.bend as R

def L.records_install_inspect_is_lossless(records):
  match records:
    case Nil{}: {==}
    case +head <> +rest:
      %L.records_install_inspect_is_lossless(rest) :
        {E.records_cons(head,E.records(E.install_records(rest))) == E.records_cons(head,_) : List<&1,E.Entity> & List<&2,E.Record>}
      {==}
def L.entity_install_inspect_is_lossless(view):
  match view:
    case E.View{+level,+seed,+id,+order,+records}:
      %L.records_install_inspect_is_lossless(records) :
        {E.inspected(level,seed,id,order,E.records(E.install_records(records))) == E.inspected(level,seed,id,order,_) : E.State & E.View}
      {==}
def L.tick_inspect_retains_complete_owner(view,runtimes,sound):
  %L.entity_install_inspect_is_lossless(view) :
    {Q.inspected(runtimes,sound,E.inspect(E.install(view))) == Q.inspected(runtimes,sound,_) : T.State & Q.Recovery}
  {==}
def L.restore_inspect_retains_complete_recovery(view,runtimes,sound):
  %L.tick_inspect_retains_complete_owner(view,runtimes,sound) :
    {Done{Q.inspect(T.State{E.install(view),runtimes,sound})} == Done{_} : Result<&2,&1,String,T.State & Q.Recovery>}
  {==}
def L.unavailable_runtime_refuses_full_restore(view,sound): {==}
def L.absent_sound_cannot_borrow_level_source(view,runtimes): {==}
