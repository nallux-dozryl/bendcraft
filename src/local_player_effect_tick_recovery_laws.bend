import Base
import ./local_player_effect_tick_recovery.bend as Q
import ./cooking_effect_entities_model.bend as E
import ./item_entity_tick_model.bend as T
import ./random.bend as R

# Full record/owner composition, not a selected-field projection. These laws
# deliberately quantify ordered records, all runtime fields and independent
# sound authority; the physical NBT boundary is verified separately.
def inspected_restoration(value:Result<&2,&1,String,T.State>) -> Result<&2,&1,String,T.State & Q.Recovery>:
  match value:
    case Fail{message}: Fail{message}
    case Done{state}: Done{Q.inspect(state)}
law records_install_inspect_is_lossless:
  for +records:List<&2,E.Record>
  {E.records(E.install_records(records)) == (E.install_records(records),records) : List<&1,E.Entity> & List<&2,E.Record>}
law entity_install_inspect_is_lossless:
  for +view:E.View
  {E.inspect(E.install(view)) == (E.install(view),view) : E.State & E.View}
law tick_inspect_retains_complete_owner:
  for +view:E.View
  for +runtimes:List<&2,T.RuntimeEntry>
  for +sound:Maybe<&2,R.Source>
  {Q.inspect(T.State{E.install(view),runtimes,sound}) ==
    (T.State{E.install(view),runtimes,sound},Q.Recovery{view,Some{runtimes},sound}) : T.State & Q.Recovery}
law restore_inspect_retains_complete_recovery:
  for +view:E.View
  for +runtimes:List<&2,T.RuntimeEntry>
  for +sound:Maybe<&2,R.Source>
  {inspected_restoration(Q.restore(Q.Recovery{view,Some{runtimes},sound})) ==
    Done{(T.State{E.install(view),runtimes,sound},Q.Recovery{view,Some{runtimes},sound})} : Result<&2,&1,String,T.State & Q.Recovery>}
law unavailable_runtime_refuses_full_restore:
  for view:E.View
  for sound:Maybe<&2,R.Source>
  {Q.restore(Q.Recovery{view,None{},sound}) ==
    Fail{"local-player-effect-tick-recovery:runtime authority unavailable"} : Result<&2,&1,String,T.State>}
law absent_sound_cannot_borrow_level_source:
  for view:E.View
  for runtimes:Maybe<&2,List<&2,T.RuntimeEntry>>
  {Q.require_sound(Q.Recovery{view,runtimes,None{}}) ==
    Fail{"local-player-effect-tick-recovery:sound authority unavailable"} : Result<&2,&2,String,R.Source>}
