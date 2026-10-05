import Base
import ./entity_scene_lighting_model.bend as M
import ./entity_scene_lighting.bend as L
import ./entity_scene_lighting_sample.bend as S
import ./sky_light_flat_authority.bend as F
import ./block_light_world.bend as BW
import ./sky_light_world.bend as SW
import ./core.bend as C

def rejoined(result:BW.State & M.Detached) -> M.State:
  (block,detached) = result
  L.rejoin(block,detached)

law detach_rejoin_retains_complete_world_and_both_engines:
  for state:M.State
  {rejoined(L.split(state)) == state : M.State}

law missing_attachment_authority_retains_original_block_owner:
  for authority:F.Context
  for epoch:String
  for block:BW.State
  {L.attach_checked(authority,epoch,block,False{}) ==
    M.Retained{block,M.AuthorityUnavailable{}} : M.Attachment}

law zero_acquisition_budgets_retain_complete_owner:
  for block:BW.State
  for sky:SW.State
  for authority:F.Context
  for epoch:String
  {L.load(0n,0n,M.State{block,sky,authority,epoch}) ==
    (M.State{block,sky,authority,epoch},Done{Unit{}}) : M.State & Result<&2,&2,M.Error,Unit>}

law refused_sky_preflight_cannot_publish_either_engine_or_core:
  for mutation:C.Mutation
  for state:M.State
  for +error:SW.Error
  {L.apply_checked(mutation,state,Fail{error}) ==
    (state,Fail{M.SkyFailure{error}}) : M.State & Result<&2,&2,M.Error,M.Commit>}

law refused_actual_core_result_retains_original_sky_owner:
  for mutation:C.Mutation
  for sky:SW.State
  for authority:F.Context
  for epoch:String
  for block:BW.State
  for +error:BW.Error
  {L.applied(mutation,sky,authority,epoch,(block,Fail{error})) ==
    (M.State{block,sky,authority,epoch},Fail{M.BlockFailure{error}}) :
    M.State & Result<&2,&2,M.Error,M.Commit>}

law refused_capture_preflight_retains_full_state:
  for capture:M.Capture
  for sites:List<&2,M.Site>
  for state:M.State
  for +error:M.Error
  {S.sample_checked(capture,sites,state,Fail{error}) == (state,Fail{error}) :
    M.State & Result<&2,&2,M.Error,M.Publication>}

law stale_core_stamp_cannot_sample_or_change_full_state:
  for capture:M.Capture
  for sites:List<&2,M.Site>
  for state:M.State
  {S.sample_clock_checked(capture,sites,state,False{}) == (state,Fail{M.StampMismatch{}}) :
    M.State & Result<&2,&2,M.Error,M.Publication>}
