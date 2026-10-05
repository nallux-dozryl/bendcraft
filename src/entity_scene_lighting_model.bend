import Base
import ./core.bend as C
import ./block_light_world.bend as BW
import ./sky_light_world.bend as SW
import ./sky_light_flat_authority.bend as F
import ./remote_entity_snapshot_wire.bend as W
import ./vanilla_lightmap_model.bend as VM

# The only World owner is block.world. Sky contains facts and work, not Core.
type State is Type:
  State{block:BW.State,sky:SW.State,authority:F.Context,epoch:String}
type Error is Data:
  AuthorityUnavailable{}
  EpochMismatch{}
  StampMismatch{}
  InvalidPartial{}
  DimensionMismatch{position:C.Position}
  BlockFailure{error:BW.Error}
  SkyFailure{error:SW.Error}
  MissingResident{position:C.Position}
  InconsistentSample{position:C.Position}
  StencilLimit{}
  InvalidSite{}
type Detached is Type:
  Detached{sky:SW.State,authority:F.Context,epoch:String}
type Attachment is Type:
  Retained{block:BW.State,error:Error}
  Attached{state:State}
type Progress is Data:
  Progress{block:BW.Progress,sky:SW.Progress}
type Commit is Data:
  Applied{}
  RepairRequired{error:SW.Error}

# Sites are supplied by the actual face/vertex/entity consumer. This producer
# does not invent AO neighbors, geometric weights, or entity sampling offsets.
type Role is Data:
  Face{face:U32,vertex:U32,point:U32}
  Entity{entity:U32,point:U32}
type Site is Data:
  Site{role:Role,position:C.Position}
type Sample is Data:
  Sample{site:Site,state:U32,block:U32,sky:U32}
type Request is Data:
  Request{epoch:String,stamp:W.Stamp,sites:List<&2,Site>}

# Capture must come from the same real outer engine continuation as the frame,
# before another tick/edit. Missing environment remains missing. No RNG, gamma,
# day/weather probe, flicker, lightmap texture or AO result is manufactured here.
type Capture is Data:
  Capture{epoch:String,stamp:W.Stamp,environment:Maybe<&2,VM.Inputs>}
type Publication is Data:
  Publication{capture:Capture,clock:C.Clock,samples:List<&2,Sample>}
