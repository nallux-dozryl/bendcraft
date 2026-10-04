import Base
import ./cooking_effect_consumer.bend as Consumer
import ./cooking_effect_entities.bend as Entities
import ./cooking_effect_entities_model.bend as E
import ./cooking_world_store.bend as Store
import ./random.bend as R
import ./vanilla_entity_fields.bend as V

def unavailable(geometry:Unit,dimension:String,point:V.Vec3) -> Result<&2,&2,E.Error,V.Vec3>:
  Fail{E.Refused{"actual-world-orb-placement-unavailable"}}

law empty_delivery_retains_complete_entity_owner_and_clock_inputs:
  for context:E.Context
  for state:E.State
  for times:List<&2,R.Bits64>
  {Consumer.deliver(~Unit,~unavailable,Unit{},context,[],state,times) ==
    (state,Entities.Outcome{[],Done{Unit{}},times}) : E.State & Entities.Outcome}
def empty_delivery_retains_complete_entity_owner_and_clock_inputs(context,state,times): {==}

# The zero acquisition budget performs the complete real pure delivery once;
# it cannot hide a constructor clock read or throw away an unused input queue.
law zero_clock_budget_returns_complete_actual_delivery:
  for context:E.Context
  for effects:List<&2,Store.Effect>
  for state:E.State
  for times:List<&2,R.Bits64>
  {Consumer.deliver_io(~Unit,~unavailable,0n,Unit{},context,effects,state,times) ==
    IO.pure(E.State & Entities.Outcome,Consumer.deliver(~Unit,~unavailable,Unit{},context,effects,state,times)) : IO(E.State & Entities.Outcome)}
def zero_clock_budget_returns_complete_actual_delivery(context,effects,state,times): {==}

# Any whole entity owner can be the result of an already committed prefix.
# An unavailable publisher is final for this call: do not run another step,
# acquire a constructor clock, or lose any part of the refused suffix/owner.
law publisher_refusal_retains_complete_committed_prefix_and_entropy:
  for state:E.State
  for pending:List<&2,Store.Effect>
  for message:String
  for times:List<&2,R.Bits64>
  for next:List<&2,Store.Effect> -> E.State -> List<&2,R.Bits64> -> IO(E.State & Entities.Outcome)
  {Consumer.resumed((state,Entities.Outcome{pending,Fail{E.Refused{message}},times}),next) ==
    IO.pure(E.State & Entities.Outcome,(state,Entities.Outcome{pending,Fail{E.Refused{message}},times})) : IO(E.State & Entities.Outcome)}
def publisher_refusal_retains_complete_committed_prefix_and_entropy(state,pending,message,times,next): {==}

law completed_delivery_retains_all_unused_constructor_clocks:
  for state:E.State
  for times:List<&2,R.Bits64>
  for next:List<&2,Store.Effect> -> E.State -> List<&2,R.Bits64> -> IO(E.State & Entities.Outcome)
  {Consumer.resumed((state,Entities.Outcome{[],Done{Unit{}},times}),next) ==
    IO.pure(E.State & Entities.Outcome,(state,Entities.Outcome{[],Done{Unit{}},times})) : IO(E.State & Entities.Outcome)}
def completed_delivery_retains_all_unused_constructor_clocks(state,times,next): {==}
