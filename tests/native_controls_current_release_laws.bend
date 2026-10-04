import Base
import ../src/f64.bend as F
import ../src/player_input.bend as PI
import ../src/player_look.bend as PL
import ../src/mouse_input.bend as MI
import ../src/client_controls.bend as CC
import ../src/player_controls.bend as C

law canonical_release_consumes_existing_packet:
  for +controller:C.Controller
  {C.release_packet(controller,CC.release()) == C.release(controller) : C.Controller}

law capture_release_preserves_complete_controller_fields:
  for buttons:PI.Buttons
  for +look:PL.State
  for +x:F.F64
  for +y:F.F64
  for accumulated_x:F.F64
  for accumulated_y:F.F64
  for first:Bool
  for +options:MI.Options
  {C.capture_release(C.Controller{buttons,look,MI.State{x,y,accumulated_x,accumulated_y,first},options}) ==
    C.Controller{PI.empty(),look,MI.State{x,y,F.F64{0,0},F.F64{0,0},True{}},options} : C.Controller}

law capture_release_is_idempotent:
  for +controller:C.Controller
  {C.capture_release(C.capture_release(controller)) == C.capture_release(controller) : C.Controller}

law release_packet_is_idempotent:
  for +controller:C.Controller
  for +packet:CC.Packet
  {C.release_packet(C.release_packet(controller,packet),packet) == C.release_packet(controller,packet) : C.Controller}

law release_signal_precedes_arbitrary_tail:
  for +controller:C.Controller
  for rest:List<&2,CC.Action>
  for focused:Bool
  for captured:Bool
  {C.release_packet(controller,CC.Packet{CC.Release{} <> rest,focused,captured}) ==
    C.capture_release(controller) : C.Controller}

law release_survives_arbitrary_platform_payload:
  for +controller:C.Controller
  for event:Event
  for event_captured:Bool
  for focused:Bool
  for captured:Bool
  {C.release_packet(controller,CC.Packet{[CC.PlatformEvent{event,event_captured},CC.Release{}],focused,captured}) ==
    C.capture_release(controller) : C.Controller}

law no_release_signal_retains_complete_controller:
  for +controller:C.Controller
  for +actions:List<&2,CC.Action>
  for focused:Bool
  for captured:Bool
  for absent:{C.release_requested(actions) == False{} : Bool}
  {C.release_packet(controller,CC.Packet{actions,focused,captured}) == controller : C.Controller}

law requested_release_retains_complete_result:
  for +controller:C.Controller
  for +actions:List<&2,CC.Action>
  for focused:Bool
  for captured:Bool
  for present:{C.release_requested(actions) == True{} : Bool}
  {C.release_packet(controller,CC.Packet{actions,focused,captured}) == C.capture_release(controller) : C.Controller}

law release_before_rejected_input_is_retained:
  for +controller:C.Controller
  for bindings:PI.Bindings
  for packet:CC.Packet
  for +error:C.Error
  for invalid:{C.controller_error(C.capture_release(controller)) == Some{error} : Maybe<&2,C.Error>}
  {(C.capture_release(controller),C.apply(C.capture_release(controller),bindings,packet)) ==
    (C.capture_release(controller),Fail{error}) : C.Controller & Result<&2,&2,C.Error,C.Controller>}

law malformed_look_refuses_input_after_valid_capture_release:
  for +controller:C.Controller
  for bindings:PI.Bindings
  for captured:Bool
  for valid:{C.controller_error(C.capture_release(controller)) == None{} : Maybe<&2,C.Error>}
  {(C.capture_release(controller),C.apply(C.capture_release(controller),bindings,
      CC.Packet{[CC.Release{},CC.PlatformEvent{Look{PL.float_bits(2143289635),0.0},captured}],False{},False{}})) ==
    (C.capture_release(controller),Fail{C.MouseFailure{MI.InvalidMove{2}}}) : C.Controller & Result<&2,&2,C.Error,C.Controller>}
