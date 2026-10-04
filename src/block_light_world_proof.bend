import Base
import ./block_light_world.bend as W
import ./block_light.bend as B
import ./core.bend as C
import ./block_light_world_laws.bend as L

def L.zero_load_budget_preserves_both_actual_owners(state): {==}
def L.bootstrap_refuses_actual_world_mutations(world,light,cursor,mutation):
  match world:
    case C.World{tick,time,paused,daylight,revision,count,sections,pending,events}: {==}
def L.bootstrap_cannot_advance_simulation_clock(world,light,cursor):
  match world:
    case C.World{tick,time,paused,daylight,revision,count,sections,pending,events}: {==}
def L.bootstrap_refuses_frame_sampling_without_touching_world(world,light,cursor,positions): {==}
def L.failed_preflight_preserves_both_actual_owners(state,error):
  match state:
    case W.State{world,light,loading}: {==}
def L.pending_field_cannot_enter_a_frame(world,cells,front,back,queued,remaining,positions): {==}
def L.daylight_edit_preserves_complete_block_light_owner(world,light,enabled):
  match world:
    case C.World{tick,time,paused,daylight,revision,count,sections,pending,events}: {==}
def L.unknown_world_and_field_sample_remain_unknown(position,key): {==}
def L.field_without_world_cell_is_rejected_as_residency_mismatch(position,key,level): {==}
