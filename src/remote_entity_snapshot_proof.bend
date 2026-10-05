import Base
import ./remote_entity_snapshot_wire.bend as W
import ./remote_entity_snapshot_laws.bend as L
import ./remote_entity_frame.bend as Frame

def L.extracted_stamp_preserves_all_capture_fields(registry,tick,revision,dimension,origin,camera,partial,cells,entities): {==}
def L.capture_stamp_mismatch_refuses_complete_frame(expected,frame,mismatch):
  %Equal.sym(Bool,W.matches(expected,frame),False{},mismatch) :
    {W.stamp_checked(_,frame) == Fail{"entity-wire:capture-stamp-mismatch"} : Result<&2,&2,String,Frame.Frame>}
  {==}
def L.capture_stamp_match_returns_complete_frame(expected,frame,matching):
  %Equal.sym(Bool,W.matches(expected,frame),True{},matching) :
    {W.stamp_checked(_,frame) == Done{frame} : Result<&2,&2,String,Frame.Frame>}
  {==}
