import Base

# Logical KeyboardInput buttons. OS key codes/binding choice are caller inputs.
type Buttons is Data:
  Buttons{forward:Bool,backward:Bool,left:Bool,right:Bool,jump:Bool,shift:Bool,sprint:Bool}

type Bindings is Data:
  Bindings{forward:U32,backward:U32,left:U32,right:U32,jump:U32,shift:U32,sprint:U32}

type Vector is Data:
  Vector{left:F32,forward:F32}

type Sample is Data:
  Sample{buttons:Buttons,movement:Vector,has_forward:Bool}

def empty() -> Buttons:
  Buttons{False{},False{},False{},False{},False{},False{},False{}}

def float(value:U32) -> F32:
  match value:
    case U32{word}: F32{word}

def impulse(positive:Bool,negative:Bool) -> F32:
  match positive negative:
    case False{} False{}: 0.0
    case True{} True{}: 0.0
    case True{} False{}: 1.0
    case False{} True{}: F32.neg(1.0)

def normalized(x:F32,z:F32,diagonal:Bool) -> Vector:
  match diagonal:
    case False{}: Vector{x,z}
    case True{}:
      # Exactly 1f / (float)Math.sqrt(2f), measured from actual Vec2.normalized.
      # This specialization admits only KeyboardInput's {-1f,+0f,1f} impulses.
      Vector{F32.mul(x,float(1060439283)),F32.mul(z,float(1060439283))}

def vector(+x:F32,+z:F32) -> Vector:
  normalized(x,z,F32.is_ne(x,0.0) && F32.is_ne(z,0.0))

def sample_vector(buttons:Buttons,+movement:Vector) -> Sample:
  Vector{x,z} = movement
  Sample{buttons,movement,F32.is_gt(z,float(925353388))}

def sample(+buttons:Buttons) -> Sample:
  Buttons{forward,backward,left,right,jump,shift,sprint} = buttons
  sample_vector(buttons,vector(impulse(left,right),impulse(forward,backward)))

def changed(old:Bool,next:Bool,selected:Bool) -> Bool:
  match selected:
    case False{}: old
    case True{}: next

# Apply key-down AND key-up. Repeats are idempotent and shared bindings update
# every matching logical button, as independent key mappings do.
def key(bindings:Bindings,buttons:Buttons,+code:U32,+down:Bool) -> Buttons:
  match bindings buttons:
    case Bindings{f,b,l,r,j,h,s} Buttons{ff,bb,ll,rr,jj,hh,ss}:
      Buttons{changed(ff,down,U32.is_eq(f,code)),changed(bb,down,U32.is_eq(b,code)),
        changed(ll,down,U32.is_eq(l,code)),changed(rr,down,U32.is_eq(r,code)),
        changed(jj,down,U32.is_eq(j,code)),changed(hh,down,U32.is_eq(h,code)),
        changed(ss,down,U32.is_eq(s,code))}

def clear(buttons:Buttons) -> Buttons:
  empty()

def make_jump(buttons:Buttons) -> Buttons:
  Buttons{f,b,l,r,j,h,s} = buttons
  Buttons{f,b,l,r,True{},h,s}

def bit(+mask:U32,n:U32) -> Bool:
  U32.is_ne(U32.and(mask,n),0)

def from_mask(+mask:U32) -> Buttons:
  Buttons{bit(mask,1),bit(mask,2),bit(mask,4),bit(mask,8),bit(mask,16),bit(mask,32),bit(mask,64)}

def flag(value:Bool,n:U32) -> U32:
  match value:
    case True{}: n
    case False{}: 0

def mask(buttons:Buttons) -> U32:
  Buttons{f,b,l,r,j,h,s} = buttons
  U32.or(flag(f,1),U32.or(flag(b,2),U32.or(flag(l,4),U32.or(flag(r,8),U32.or(flag(j,16),U32.or(flag(h,32),flag(s,64)))))))

law opposing_buttons_cancel:
  for both:Bool
  {impulse(both,both) == 0.0 : F32}

def opposing_buttons_cancel(both):
  match both:
    case False{}: {==}
    case True{}: {==}

law unselected_event_retains_button:
  for +old:Bool
  for next:Bool
  {changed(old,next,False{}) == old : Bool}

def unselected_event_retains_button(old,next):
  {==}

law selected_event_installs_requested_button:
  for old:Bool
  for +next:Bool
  {changed(old,next,True{}) == next : Bool}

def selected_event_installs_requested_button(old,next):
  {==}

law clearing_releases_every_button:
  for old:Buttons
  {clear(old) == empty() : Buttons}

def clearing_releases_every_button(old):
  {==}

law injected_jump_preserves_other_buttons:
  for +f:Bool
  for +b:Bool
  for +l:Bool
  for +r:Bool
  for old:Bool
  for +h:Bool
  for +s:Bool
  {make_jump(Buttons{f,b,l,r,old,h,s}) == Buttons{f,b,l,r,True{},h,s} : Buttons}

def injected_jump_preserves_other_buttons(f,b,l,r,old,h,s):
  {==}
