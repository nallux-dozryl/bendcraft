import Base
import ./cooking_effect_entities_model.bend as E
import ./item_entity_tick_model.bend as T
import ./random.bend as R

# A Data projection, never a second entity owner. None distinguishes an older
# save without runtime authority from a known, empty runtime list.
type Recovery is Data:
  Recovery{entities:E.View,runtimes:Maybe<&2,List<&2,T.RuntimeEntry>>,sound:Maybe<&2,R.Source>}

def inspected(+runtimes:List<&2,T.RuntimeEntry>,+sound:Maybe<&2,R.Source>,result:E.State & E.View) -> T.State & Recovery:
  (entities,view) = result
  (T.State{entities,runtimes,sound},Recovery{view,Some{runtimes},sound})
def inspect(state:T.State) -> T.State & Recovery:
  T.State{entities,runtimes,sound} = state
  inspected(runtimes,sound,E.inspect(entities))
def legacy(entities:E.View) -> Recovery:
  Recovery{entities,None{},None{}}
def require_runtimes(value:Recovery) -> Result<&2,&2,String,List<&2,T.RuntimeEntry>>:
  match value:
    case Recovery{entities,None{},sound}: Fail{"local-player-effect-tick-recovery:runtime authority unavailable"}
    case Recovery{entities,Some{runtimes},sound}: Done{runtimes}
def require_sound(value:Recovery) -> Result<&2,&2,String,R.Source>:
  match value:
    case Recovery{entities,runtimes,None{}}: Fail{"local-player-effect-tick-recovery:sound authority unavailable"}
    case Recovery{entities,runtimes,Some{sound}}: Done{sound}
# Only one E.State is installed. Sound None stays None; sound-dependent tick
# operations retain their existing refusal rather than borrowing LEVEL RNG.
def restore(value:Recovery) -> Result<&2,&1,String,T.State>:
  match value:
    case Recovery{entities,None{},sound}: Fail{"local-player-effect-tick-recovery:runtime authority unavailable"}
    case Recovery{entities,Some{runtimes},sound}: Done{T.State{E.install(entities),runtimes,sound}}

law legacy_has_no_runtime_authority:
  for value:E.View
  {require_runtimes(legacy(value)) == Fail{"local-player-effect-tick-recovery:runtime authority unavailable"} : Result<&2,&2,String,List<&2,T.RuntimeEntry>>}
def legacy_has_no_runtime_authority(value): {==}
law legacy_has_no_sound_authority:
  for value:E.View
  {require_sound(legacy(value)) == Fail{"local-player-effect-tick-recovery:sound authority unavailable"} : Result<&2,&2,String,R.Source>}
def legacy_has_no_sound_authority(value): {==}
