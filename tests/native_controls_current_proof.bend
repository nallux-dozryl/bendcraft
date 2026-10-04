import Base
import ../src/player_input.bend as PI
import ../src/player_look.bend as PL
import ../src/mouse_input.bend as MI
import ../src/client_controls.bend as CC
import ../src/player_controls.bend as C

# These contracts bind successful ordered control actions to the actual pure
# production fold. They do not certify the foreign native view or OS delivery.
law ordered_action_prefix:
  for action:CC.Action
  for rest:List<&2,CC.Action>
  for +bindings:PI.Bindings
  for +controller:C.Controller
  {C.fold(action <> rest,bindings,Done{controller}) ==
    C.fold(rest,bindings,C.action(action,controller,bindings)) : Result<&2,&2,C.Error,C.Controller>}

def ordered_action_prefix(action,rest,bindings,controller):
  {==}

law captured_key_is_applied:
  for +bindings:PI.Bindings
  for buttons:PI.Buttons
  for +look:PL.State
  for +mouse:MI.State
  for +options:MI.Options
  for +code:U32
  for +down:Bool
  {C.fold([CC.PlatformEvent{Key{code,down},True{}}],bindings,
    Done{C.Controller{buttons,look,mouse,options}}) ==
    Done{C.Controller{PI.key(bindings,buttons,code,down),look,mouse,options}} : Result<&2,&2,C.Error,C.Controller>}

def captured_key_is_applied(bindings,buttons,look,mouse,options,code,down):
  {==}

law release_after_key_clears_held_controls:
  for +bindings:PI.Bindings
  for +controller:C.Controller
  for code:U32
  for down:Bool
  {C.fold([CC.PlatformEvent{Key{code,down},True{}},CC.Release{}],bindings,
    Done{controller}) == Done{C.release(controller)} : Result<&2,&2,C.Error,C.Controller>}

def release_after_key_clears_held_controls(bindings,controller,code,down):
  match controller:
    case C.Controller{buttons,look,mouse,options}: {==}

law uncaptured_key_cannot_restore_released_controls:
  for +bindings:PI.Bindings
  for +controller:C.Controller
  for code:U32
  for down:Bool
  {C.fold([CC.Release{},CC.PlatformEvent{Key{code,down},False{}}],bindings,
    Done{controller}) == Done{C.release(controller)} : Result<&2,&2,C.Error,C.Controller>}

def uncaptured_key_cannot_restore_released_controls(bindings,controller,code,down):
  match controller:
    case C.Controller{buttons,look,mouse,options}: {==}
