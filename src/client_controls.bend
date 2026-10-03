import Base

# One physical frame is delivered to the shared actor as one operation. Each
# event records actual capture at that point; capture can change within a frame.
# Release is explicit because pinned Base emits no focus-loss event.
type Action is Data:
  PlatformEvent{event:Event,captured:Bool}
  Release{}

type Packet is Data:
  Packet{actions:List<&2,Action>,focused:Bool,captured:Bool}

def release() -> Packet:
  Packet{[Release{}],False{},False{}}
