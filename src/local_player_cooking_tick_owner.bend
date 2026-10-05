import Base
import ./item_entity_tick_model.bend as T
import ./entity_section_membership_model.bend as M
import ./cooking_effect_entities_model.bend as E
import ./local_player_effect_tick_recovery.bend as Q
import ./local_player_cooking_tick_storage.bend as Storage
import ./random.bend as R

# Only the one entity owner lives in EntityOwner. This recursive metadata box
# retains runtime availability, the distinct sound stream and a saved manager
# image. The image is not an installed manager or a visibility assertion.
type State is Data:
  State{runtimes:Maybe<&2,List<&2,T.RuntimeEntry>>,sound:Maybe<&2,R.Source>,
    membership:Maybe<&2,M.View>,tail:List<&2,State>}

def absent() -> State:
  State{None{},None{},None{},[]}

# Called only at the actual fresh isolated factory boundary, whose entity
# list is empty. The sound argument is that boundary's second allocation.
def fresh(sound:R.Source) -> State:
  State{Some{[]},Some{sound},None{},[]}

def canonical(value:State) -> Bool:
  match value:
    case State{runtimes,sound,membership,Nil{}}: True{}
    case State{runtimes,sound,membership,child <> tail}: False{}

def require_canonical(value:State) -> Result<&2,&2,String,Unit>:
  match value:
    case State{runtimes,sound,membership,Nil{}}: Done{Unit{}}
    case State{runtimes,sound,membership,child <> tail}:
      Fail{"local-cooking:noncanonical-tick-owner-tail"}

# Immutable projections do not replace the retained live entity or metadata
# owner. Persistence separately admits the complete recursive metadata tail.
def snapshot(view:E.View,inputs:List<&2,R.Bits64>,value:State) -> Storage.Stored:
  State{runtimes,sound,membership,tail} = value
  Storage.Stored{Q.Recovery{view,runtimes,sound},inputs,membership}

def installed(value:Storage.Stored) -> E.State & List<&2,R.Bits64> & State:
  Storage.Stored{Q.Recovery{view,runtimes,sound},inputs,membership} = value
  (E.install(view),inputs,State{runtimes,sound,membership,[]})
