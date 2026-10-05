import Base
import ./local_player_entity_scene_laws.bend as Laws

def Laws.invalid_frame_guard_retains_complete_session(state,width,height,policy,partial):
  {==}
def Laws.invalid_partial_guard_retains_complete_session(state,width,height,policy,partial):
  {==}
def Laws.unsupported_dimension_retains_complete_session(state,dimension,width,height,policy,partial):
  {==}
def Laws.sample_refusal_retains_returned_session_and_exact_error(state,dimension,partial,message):
  {==}
def Laws.captured_bound_projection_retains_complete_returned_session(state,dimension,partial,sample,view,inputs):
  {==}
def Laws.captured_unbound_owner_remains_explicitly_unbound(state,dimension,partial,sample):
  {==}
