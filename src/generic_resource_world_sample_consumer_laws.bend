import Base
import ./generic_resource_world_sample.bend as GS
import ./generic_resource_world_sample_session.bend as Session
import ./generic_resource_world_sample_backend.bend as Backend
import ./generic_resource_world_sample_presenter.bend as Presenter
import ./local_player_session.bend as S
import ./remote_resource_backend.bend as B
import ./resource_catalog_world.bend as CW
import ./resource_block_catalog.bend as C

law refused_dimensions_preserve_every_saved_session_owner:
  for state:S.State
  for width:U32
  for height:U32
  for policy:GS.Policy
  {Session.snapshot_checked(False{},state,width,height,policy) ==
    (state,Fail{"generic-resource:invalid-frame"}) : S.State & Result<&2,&2,String,GS.Sample>}

law refused_lease_preserves_every_actor_owner_and_context:
  for state:B.State
  for width:U32
  for height:U32
  for policy:GS.Policy
  {Backend.checked(False{},state,width,height,policy) ==
    (state,Fail{"RendererLeaseOrSequence"}) : B.State & Result<&2,&2,String,GS.Sample>}

law refused_binding_preserves_every_texture_owner:
  for +error:C.Error
  for assets:CW.Assets
  for width:U32
  for height:U32
  {Presenter.framed(Fail{error},assets,width,height) ==
    (assets,Fail{Presenter.error_text(error)}) : CW.Assets & Result<&2,&2,String,Image>}
