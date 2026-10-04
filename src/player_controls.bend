import Base
import ./f64.bend as F
import ./player_input.bend as PI
import ./player_look.bend as PL
import ./mouse_input.bend as MI
import ./client_controls.bend as CC

# A packet changes only neutral held controls and degree-authoritative view.
# World/body/ticking and OS focus/capture observations belong to the caller.
type Controller is Data:
  Controller{buttons:PI.Buttons,look:PL.State,mouse:MI.State,options:MI.Options}

type Error is Data:
  MouseFailure{cause:MI.Error}
  LookFailure{cause:PL.Error}

def mouse_error(error:Maybe<&2,MI.Error>) -> Maybe<&2,Error>:
  match error:
    case None{}: None{}
    case Some{cause}: Some{MouseFailure{cause}}

def look_error(error:Maybe<&2,PL.Error>) -> Maybe<&2,Error>:
  match error:
    case None{}: None{}
    case Some{cause}: Some{LookFailure{cause}}

def first_error(first:Maybe<&2,Error>,rest:Maybe<&2,Error>) -> Maybe<&2,Error>:
  match first:
    case Some{error}: Some{error}
    case None{}: rest

def controller_error(controller:Controller) -> Maybe<&2,Error>:
  match controller:
    case Controller{_,look,mouse,options}:
      first_error(mouse_error(MI.state_error(mouse)),first_error(mouse_error(MI.options_error(options)),look_error(PL.state_error(look))))

# This field operation is independent of admission. Close/focus-loss callers
# can always release stuck input, including when another controller field fails.
def release(controller:Controller) -> Controller:
  match controller:
    case Controller{_,look,mouse,options}: Controller{PI.empty(),look,MI.ignore_next_move(MI.clear(mouse)),options}

# Capture loss is a separate unconditional state operation, not an admitted
# input packet. Only an explicit Release signal is consumed; key/Look payloads
# cannot restore controls or roll this operation back. The ordinary apply/fold
# below retain their atomic validation and rollback contract.
def release_requested(actions:List<&2,CC.Action>) -> Bool:
  match actions:
    case Nil{}: False{}
    case CC.Release{} <> rest: True{}
    case other <> rest: release_requested(rest)

def release_selected(requested:Bool,controller:Controller) -> Controller:
  match requested:
    case False{}: controller
    case True{}: release(controller)

def release_packet(controller:Controller,packet:CC.Packet) -> Controller:
  CC.Packet{actions,focused,captured} = packet
  release_selected(release_requested(actions),controller)

def capture_release(controller:Controller) -> Controller:
  release_packet(controller,CC.release())

def install_mouse(controller:Controller,result:Result<&2,&2,MI.Error,MI.State>) -> Result<&2,&2,Error,Controller>:
  match controller result:
    case _ Fail{cause}: Fail{MouseFailure{cause}}
    case Controller{buttons,look,_,options} Done{mouse}: Done{Controller{buttons,look,mouse,options}}

def install_look(controller:Controller,result:Result<&2,&2,PL.Error,PL.State>) -> Result<&2,&2,Error,Controller>:
  match controller result:
    case _ Fail{cause}: Fail{LookFailure{cause}}
    case Controller{buttons,_,mouse,options} Done{look}: Done{Controller{buttons,look,mouse,options}}

def key_event(captured:Bool,controller:Controller,bindings:PI.Bindings,code:U32,down:Bool) -> Result<&2,&2,Error,Controller>:
  match captured controller:
    case False{} _: Done{controller}
    case True{} Controller{buttons,look,mouse,options}: Done{Controller{PI.key(bindings,buttons,code,down),look,mouse,options}}

# The platform carries F32 event fields. Validate them even when uncaptured,
# an explicit packet admission stricter than ignoring inactive numeric payloads.
def look_input_error(+dx:F32,+dy:F32) -> Maybe<&2,Error>:
  MI.choose(Maybe<&2,Error>,MI.choose(Maybe<&2,Error>,None{},Some{MouseFailure{MI.InvalidMove{3}}},PL.finite(dy)),Some{MouseFailure{MI.InvalidMove{2}}},PL.finite(dx))

def look_event_present(controller:Controller,dx:F32,dy:F32) -> Result<&2,&2,Error,Controller>:
  match controller:
    case Controller{buttons,look,+mouse,options}:
      install_mouse(Controller{buttons,look,mouse,options},MI.relative(mouse,PL.wide(dx),PL.wide(dy),True{},True{}))

def look_event_captured(captured:Bool,controller:Controller,dx:F32,dy:F32) -> Result<&2,&2,Error,Controller>:
  match captured:
    case False{}: Done{controller}
    case True{}: look_event_present(controller,dx,dy)

def look_event_gate(error:Maybe<&2,Error>,controller:Controller,dx:F32,dy:F32,captured:Bool) -> Result<&2,&2,Error,Controller>:
  match error:
    case Some{error}: Fail{error}
    case None{}: look_event_captured(captured,controller,dx,dy)

def platform_event(event:Event,captured:Bool,controller:Controller,bindings:PI.Bindings) -> Result<&2,&2,Error,Controller>:
  match event:
    case Key{code,down}: key_event(captured,controller,bindings,code,down)
    case Look{+dx,+dy}: look_event_gate(look_input_error(dx,dy),controller,dx,dy,captured)
    case _: Done{controller}

def action(action:CC.Action,controller:Controller,bindings:PI.Bindings) -> Result<&2,&2,Error,Controller>:
  match action:
    case CC.Release{}: Done{release(controller)}
    case CC.PlatformEvent{event,captured}: platform_event(event,captured,controller,bindings)

# Data is retained by the caller. Earlier prospective key/mouse changes cannot
# escape a failing fold: only the final Done controller is eligible to publish.
def fold(actions:List<&2,CC.Action>,+bindings:PI.Bindings,result:Result<&2,&2,Error,Controller>) -> Result<&2,&2,Error,Controller>:
  match actions result:
    case Nil{} _: result
    case _ Fail{error}: Fail{error}
    case head <> rest Done{controller}: fold(rest,bindings,action(head,controller,bindings))

def turn_once(turn:Maybe<&2,MI.Deltas>,controller:Controller) -> Result<&2,&2,Error,Controller>:
  match turn controller:
    case None{} _: Done{controller}
    case Some{MI.Deltas{dx,dy}} Controller{buttons,+look,mouse,options}:
      install_look(Controller{buttons,look,mouse,options},PL.turn(look,dx,dy))

def frame_finished(result:Result<&2,&2,MI.Error,MI.Frame>,controller:Controller) -> Result<&2,&2,Error,Controller>:
  match result controller:
    case Fail{cause} _: Fail{MouseFailure{cause}}
    case Done{MI.Frame{mouse,turn}} Controller{buttons,look,_,options}: turn_once(turn,Controller{buttons,look,mouse,options})

def finish_controller(controller:Controller,focused:Bool,captured:Bool) -> Result<&2,&2,Error,Controller>:
  match controller:
    case Controller{buttons,look,+mouse,+options}:
      frame_finished(MI.finish(mouse,options,focused,captured,True{}),Controller{buttons,look,mouse,options})

def folded(result:Result<&2,&2,Error,Controller>,focused:Bool,captured:Bool) -> Result<&2,&2,Error,Controller>:
  match result:
    case Fail{error}: Fail{error}
    case Done{controller}: finish_controller(controller,focused,captured)

def apply_ready(controller:Controller,bindings:PI.Bindings,packet:CC.Packet) -> Result<&2,&2,Error,Controller>:
  match packet:
    case CC.Packet{actions,focused,captured}: folded(fold(actions,bindings,Done{controller}),focused,captured)

def apply_gate(error:Maybe<&2,Error>,controller:Controller,bindings:PI.Bindings,packet:CC.Packet) -> Result<&2,&2,Error,Controller>:
  match error:
    case Some{error}: Fail{error}
    case None{}: apply_ready(controller,bindings,packet)

def apply(+controller:Controller,bindings:PI.Bindings,packet:CC.Packet) -> Result<&2,&2,Error,Controller>:
  apply_gate(controller_error(controller),controller,bindings,packet)

def describe_mouse(error:MI.Error) -> String:
  match error:
    case MI.InvalidState{field}: "mouse-state-" ++ U32.show(field)
    case MI.InvalidMove{field}: "mouse-event-" ++ U32.show(field)
    case MI.InvalidSensitivity{}: "mouse-sensitivity"
    case MI.UnsupportedSmoothCamera{}: "mouse-smooth-camera"
    case MI.UnsupportedScoping{}: "mouse-scoping"
    case MI.UnsupportedRelativeMode{}: "mouse-relative-mode"
    case MI.NonFiniteAccumulation{axis}: "mouse-accumulation-" ++ U32.show(axis)
    case MI.NonFiniteDeltas{axis}: "mouse-delta-" ++ U32.show(axis)

def describe_look(error:PL.Error) -> String:
  match error:
    case PL.InvalidState{field}: "look-state-" ++ U32.show(field)
    case PL.InvalidInput{axis}: "look-input-" ++ U32.show(axis)
    case PL.NonFiniteResult{field}: "look-result-" ++ U32.show(field)

def describe_error(error:Error) -> String:
  match error:
    case MouseFailure{cause}: describe_mouse(cause)
    case LookFailure{cause}: describe_look(cause)
