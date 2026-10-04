import Base
import ./block_light.bend as B
import ./core.bend as C

# Contracts over the actual field owner and production transfer. Java receiver
# observations separately establish the tested settled-field specification.
def owner_after(result:B.State & B.Status) -> B.State:
  (state,status) = result
  state

def open(context:Unit,source:B.Descriptor,target:B.Descriptor,direction:B.Direction) -> Bool:
  False{}

law rejected_descriptor_preserves_complete_state:
  for state:B.State
  for position:C.Position
  for +descriptor:B.Descriptor
  for invalid:{B.descriptor_valid(descriptor) == False{} : Bool}
  {B.publish(state,position,descriptor) == (state,Fail{B.InvalidDescriptor{}}) :
    B.State & Result<&2,&2,B.Error,Unit>}

# No work, including no provider call, is performed at a zero budget. This
# instantiation proves preservation of every field, not just sampled levels.
law zero_budget_preserves_complete_state:
  for state:B.State
  {owner_after(B.advance(~Unit,~open,Unit{},0n,state)) == state : B.State}

law settled_field_has_no_work_for_any_budget:
  for cells:Map<&2,Maybe<&2,B.Cell>>
  for budget:Nat
  {B.advance(~Unit,~open,Unit{},budget,B.State{cells,[],[],MTip{},0n}) ==
    (B.State{cells,[],[],MTip{},0n},B.Stable{}) : B.State & B.Status}

law new_field_distinguishes_unknown_from_dark:
  for position:C.Position
  {B.sample(B.new(),position) == (B.new(),None{}) : B.State & Maybe<&2,U32>}

law facing_direction_is_an_involution:
  for +direction:B.Direction
  {B.opposite(B.opposite(direction)) == direction : B.Direction}

law closed_face_prevents_all_transfer:
  for level:U32
  for dampening:U32
  {B.transfer(True{},level,dampening) == 0 : U32}

law insufficient_light_cannot_wrap_subtraction:
  for +level:U32
  for +dampening:U32
  for insufficient:{U32.is_gt(level,U32.max(1,dampening)) == False{} : Bool}
  {B.transfer(False{},level,dampening) == 0 : U32}

law unknown_neighbor_cannot_supply_light:
  for target:B.Descriptor
  for direction:B.Direction
  {B.contribution(~Unit,~open,Unit{},target,direction,None{}) == 0 : U32}
