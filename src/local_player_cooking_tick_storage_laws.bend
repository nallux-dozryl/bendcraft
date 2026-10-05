import Base
import ./local_player_cooking_tick_storage.bend as S
import ./local_player_effect_tick_recovery.bend as Q
import ./cooking_effect_entities_model.bend as E
import ./item_entity_tick_model.bend as T
import ./random.bend as R
import ./entity_section_membership_model.bend as M

# These quantify every entity record, runtime field, separate sound source,
# constructor clock word and complete manager image. They concern the actual
# affine inspect/restore API; physical NBT admission is tested separately.
def inspected_restoration(value:Result<&2,&1,String,S.Restored>) -> Result<&2,&1,String,T.State & S.Stored>:
  match value:
    case Fail{message}: Fail{message}
    case Done{S.Restored{state,clocks,membership}}: Done{S.inspect(state,clocks,membership)}
law inspect_retains_complete_tick_owner_and_sidecars:
  for +view:E.View
  for +runtimes:List<&2,T.RuntimeEntry>
  for +sound:Maybe<&2,R.Source>
  for +clocks:List<&2,R.Bits64>
  for +membership:Maybe<&2,M.View>
  {S.inspect(T.State{E.install(view),runtimes,sound},clocks,membership) ==
    (T.State{E.install(view),runtimes,sound},S.Stored{Q.Recovery{view,Some{runtimes},sound},clocks,membership}) : T.State & S.Stored}
law restore_retains_complete_separate_authorities:
  for +view:E.View
  for +runtimes:List<&2,T.RuntimeEntry>
  for +sound:Maybe<&2,R.Source>
  for +clocks:List<&2,R.Bits64>
  for +membership:Maybe<&2,M.View>
  {S.restore(S.Stored{Q.Recovery{view,Some{runtimes},sound},clocks,membership}) ==
    Done{S.Restored{T.State{E.install(view),runtimes,sound},clocks,membership}} : Result<&2,&1,String,S.Restored>}
law full_restore_inspect_is_lossless:
  for +view:E.View
  for +runtimes:List<&2,T.RuntimeEntry>
  for +sound:Maybe<&2,R.Source>
  for +clocks:List<&2,R.Bits64>
  for +membership:Maybe<&2,M.View>
  {inspected_restoration(S.restore(S.Stored{Q.Recovery{view,Some{runtimes},sound},clocks,membership})) ==
    Done{(T.State{E.install(view),runtimes,sound},S.Stored{Q.Recovery{view,Some{runtimes},sound},clocks,membership})} : Result<&2,&1,String,T.State & S.Stored>}
law unavailable_runtime_cannot_be_restored_from_entity_records:
  for view:E.View
  for clocks:List<&2,R.Bits64>
  for membership:Maybe<&2,M.View>
  {S.restore(S.Stored{Q.legacy(view),clocks,membership}) ==
    Fail{"local-player-effect-tick-recovery:runtime authority unavailable"} : Result<&2,&1,String,S.Restored>}
