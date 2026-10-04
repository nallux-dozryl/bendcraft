import Base
import ../src/f64.bend as F
import ../src/player_input.bend as PI
import ../src/player_look.bend as PL
import ../src/mouse_input.bend as MI
import ../src/client_controls.bend as CC
import ../src/player_controls.bend as C
import ./native_controls_current_release_laws.bend as Laws

def Laws.canonical_release_consumes_existing_packet(controller):
  {==}

def Laws.capture_release_preserves_complete_controller_fields(buttons,look,x,y,accumulated_x,accumulated_y,first,options):
  {==}

def Laws.capture_release_is_idempotent(controller):
  match controller:
    case C.Controller{buttons,look,MI.State{x,y,ax,ay,first},options}: {==}

def selected_idempotent(+requested:Bool,+controller:C.Controller) ->
    {C.release_selected(requested,C.release_selected(requested,controller)) == C.release_selected(requested,controller) : C.Controller}:
  match requested controller:
    case False{} _: {==}
    case True{} C.Controller{buttons,look,MI.State{x,y,ax,ay,first},options}: {==}

def Laws.release_packet_is_idempotent(controller,packet):
  match packet:
    case CC.Packet{+actions,focused,captured}: selected_idempotent(C.release_requested(actions),controller)

def Laws.release_signal_precedes_arbitrary_tail(controller,rest,focused,captured):
  {==}

def Laws.release_survives_arbitrary_platform_payload(controller,event,event_captured,focused,captured):
  {==}

def Laws.no_release_signal_retains_complete_controller(controller,actions,focused,captured,absent):
  %Equal.sym(Bool,C.release_requested(actions),False{},absent) : {C.release_selected(_,controller) == controller : C.Controller}
  {==}

def Laws.requested_release_retains_complete_result(controller,actions,focused,captured,present):
  %Equal.sym(Bool,C.release_requested(actions),True{},present) : {C.release_selected(_,controller) == C.capture_release(controller) : C.Controller}
  {==}

def Laws.release_before_rejected_input_is_retained(controller,bindings,packet,error,invalid):
  %Equal.sym(Maybe<&2,C.Error>,C.controller_error(C.capture_release(controller)),Some{error},invalid) :
    {(C.capture_release(controller),C.apply_gate(_,C.capture_release(controller),bindings,packet)) == (C.capture_release(controller),Fail{error}) : C.Controller & Result<&2,&2,C.Error,C.Controller>}
  {==}

def Laws.malformed_look_refuses_input_after_valid_capture_release(controller,bindings,captured,valid):
  %Equal.sym(Maybe<&2,C.Error>,C.controller_error(C.capture_release(controller)),None{},valid) :
    {(C.capture_release(controller),C.apply_gate(_,C.capture_release(controller),bindings,
        CC.Packet{[CC.Release{},CC.PlatformEvent{Look{PL.float_bits(2143289635),0.0},captured}],False{},False{}})) ==
      (C.capture_release(controller),Fail{C.MouseFailure{MI.InvalidMove{2}}}) : C.Controller & Result<&2,&2,C.Error,C.Controller>}
  {==}
