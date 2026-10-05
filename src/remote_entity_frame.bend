import Base
import ./generic_resource_world_sample.bend as GS
import ./item_entity_render_model.bend as D

# One immutable publication, captured by the sole Session continuation.
# Its sample carries the actual registry/Core clock/origin/camera; dimension
# comes from the retained player profile and partial is the requested fraction.
type Frame is Data:
  Frame{sample:GS.Sample,entities:D.Snapshot,dimension:String,partial:F32}
