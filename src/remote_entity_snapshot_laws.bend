import Base
import ./remote_entity_snapshot_wire.bend as W
import ./remote_entity_frame.bend as Frame
import ./generic_resource_world_sample.bend as GS
import ./item_entity_render_model.bend as D
import ./movement.bend as M
import ./client_render.bend as R

# These quantify the complete immutable publication, including all raw item
# keys/counts, common fields and records. They do not authorize an entity owner
# or replace the separate actual Session atomic-capture/transport obligations.
law extracted_stamp_preserves_all_capture_fields:
  for +registry:String
  for +tick:Nat
  for +revision:Nat
  for +dimension:String
  for +origin:M.Vec3
  for +camera:R.Camera
  for +partial:F32
  for cells:List<&2,GS.Cell>
  for entities:D.Snapshot
  {W.stamp(Frame.Frame{GS.Sample{registry,tick,revision,origin,camera,cells},entities,dimension,partial}) ==
    W.Stamp{registry,tick,revision,dimension,origin,camera,partial} : W.Stamp}

law capture_stamp_mismatch_refuses_complete_frame:
  for +expected:W.Stamp
  for +frame:Frame.Frame
  for mismatch:{W.matches(expected,frame) == False{} : Bool}
  {W.checked_stamp(expected,frame) == Fail{"entity-wire:capture-stamp-mismatch"} : Result<&2,&2,String,Frame.Frame>}

law capture_stamp_match_returns_complete_frame:
  for +expected:W.Stamp
  for +frame:Frame.Frame
  for matching:{W.matches(expected,frame) == True{} : Bool}
  {W.checked_stamp(expected,frame) == Done{frame} : Result<&2,&2,String,Frame.Frame>}
