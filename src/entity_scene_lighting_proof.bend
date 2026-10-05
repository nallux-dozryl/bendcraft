import Base
import ./entity_scene_lighting_model.bend as M
import ./entity_scene_lighting_laws.bend as L
import ./block_light_world.bend as BW

def L.detach_rejoin_retains_complete_world_and_both_engines(state):
  match state:
    case M.State{block,sky,authority,epoch}: {==}
def L.missing_attachment_authority_retains_original_block_owner(authority,epoch,block):
  match block:
    case BW.State{world,light,loading}: {==}
def L.zero_acquisition_budgets_retain_complete_owner(block,sky,authority,epoch):
  match block:
    case BW.State{world,light,loading}: {==}
def L.refused_sky_preflight_cannot_publish_either_engine_or_core(mutation,state,error):
  match state:
    case M.State{block,sky,authority,epoch}: {==}
def L.refused_actual_core_result_retains_original_sky_owner(mutation,sky,authority,epoch,block,error):
  match block:
    case BW.State{world,light,loading}: {==}
def L.refused_capture_preflight_retains_full_state(capture,sites,state,error):
  match state:
    case M.State{BW.State{world,light,loading},sky,authority,epoch}: {==}
def L.stale_core_stamp_cannot_sample_or_change_full_state(capture,sites,state):
  match state:
    case M.State{block,sky,authority,epoch}: {==}
