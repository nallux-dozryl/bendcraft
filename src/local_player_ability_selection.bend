import Base

# Actual LocalPlayer non-spectator jump-edge selection. This module is shared
# by the owning runtime and its focused native consumer; it owns no world.
type Selection is Data:
  Selection{flying:Bool,trigger:U32,takeoff:Bool,jump:Bool,sneak:Bool}

def timer(+flying:Bool,trigger:U32,ground:Bool,jump:Bool,sneak:Bool,empty:Bool) -> Selection:
  match empty:
    case True{}: Selection{flying,7,False{},jump,sneak}
    case False{}: Selection{Bool.not(flying),0,Bool.not(flying) && ground,jump,sneak}

def edge(flying:Bool,+trigger:U32,ground:Bool,jump:Bool,sneak:Bool,selected:Bool) -> Selection:
  match selected:
    case False{}: Selection{flying,trigger,False{},jump,sneak}
    case True{}: timer(flying,trigger,ground,jump,sneak,U32.is_eq(trigger,0))

def select(mayfly:Bool,flying:Bool,trigger:U32,ground:Bool,old_jump:Bool,+jump:Bool,sneak:Bool) -> Selection:
  edge(flying,trigger,ground,jump,sneak,mayfly && Bool.not(old_jump) && jump)
