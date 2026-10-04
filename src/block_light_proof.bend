import Base
import ./block_light.bend as B
import ./block_light_laws.bend as L

def L.rejected_descriptor_preserves_complete_state(state,position,descriptor,invalid):
  %Equal.sym(Bool,B.descriptor_valid(descriptor),False{},invalid) :
    {B.publish_valid(_,state,position,descriptor) == (state,Fail{B.InvalidDescriptor{}}) :
      B.State & Result<&2,&2,B.Error,Unit>}
  {==}

def L.zero_budget_preserves_complete_state(state):
  match state:
    case B.State{cells,front,back,queued,pending}: {==}

def L.settled_field_has_no_work_for_any_budget(cells,budget):
  match budget:
    case 0n: {==}
    case 1n+remaining: {==}

def L.new_field_distinguishes_unknown_from_dark(position): {==}

def L.facing_direction_is_an_involution(direction):
  match direction:
    case B.Down{}: {==}
    case B.Up{}: {==}
    case B.North{}: {==}
    case B.South{}: {==}
    case B.West{}: {==}
    case B.East{}: {==}

def L.closed_face_prevents_all_transfer(level,dampening): {==}

def L.insufficient_light_cannot_wrap_subtraction(level,dampening,insufficient):
  %Equal.sym(Bool,U32.is_gt(level,U32.max(1,dampening)),False{},insufficient) :
    {B.transfer_open(level,U32.max(1,dampening),_) == 0 : U32}
  {==}

def L.unknown_neighbor_cannot_supply_light(target,direction): {==}
