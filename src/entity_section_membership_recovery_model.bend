import Base
import ./entity_section_membership_model.bend as M
import ./cooking_effect_entities_model.bend as E
import ./item_entity_tick_model.bend as T
import ./random.bend as R

# Immutable proposals only; activation retains the one actual T.State owner.
type Plan is Data:
  Plan{entities:E.View,runtimes:List<&2,T.RuntimeEntry>,membership:M.View,journal:List<&2,M.CallbackEvent>}
type Fresh is Data:
  Fresh{plan:Plan,remaining_times:List<&2,R.Bits64>}
type FreshPublication is Data:
  FreshPublication{journal:List<&2,M.CallbackEvent>,remaining_times:List<&2,R.Bits64>}
