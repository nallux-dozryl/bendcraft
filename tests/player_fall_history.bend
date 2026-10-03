import Base
import ../src/f64.bend as F
import ../src/player_fall_history.bend as H

law rejected_movement_retains_history_owner:
  for mode:H.Mode
  for +history:H.History
  for movement:H.Movement
  for +error:H.Error
  {H.movement_gate(mode,H.State{history},movement,Some{error}) == (H.State{history},Fail{error}) : H.State & Result<&2,&2,H.Error,Unit>}
def rejected_movement_retains_history_owner(mode,history,movement,error):
  {==}

law no_physics_history_is_unchanged:
  for +history:H.History
  for movement:H.Movement
  {H.movement_mode(H.NoPhysics{},H.State{history},movement) == (H.State{history},Done{Unit{}}) : H.State & Result<&2,&2,H.Error,Unit>}
def no_physics_history_is_unchanged(history,movement):
  {==}

law nonnegative_displacement_preserves_distance:
  for +distance:F.F64
  for y:F.F64
  {H.accumulate_if(distance,y,False{}) == distance : F.F64}
def nonnegative_displacement_preserves_distance(distance,y):
  {==}

law safe_landing_resets_positive_zero:
  for original:H.State
  for distance:F.F64
  {H.finish_ground(original,distance,True{},True{}) == (H.State{H.History{F.from_u32(0)}},Done{Unit{}}) : H.State & Result<&2,&2,H.Error,Unit>}
def safe_landing_resets_positive_zero(original,distance):
  {==}

law unsupported_landing_rolls_back_accumulation:
  for +history:H.History
  for distance:F.F64
  {H.finish_ground(H.State{history},distance,True{},False{}) == (H.State{history},Fail{H.UnsupportedLanding{}}) : H.State & Result<&2,&2,H.Error,Unit>}
def unsupported_landing_rolls_back_accumulation(history,distance):
  {==}

law nonfinite_result_rolls_back_accumulation:
  for +history:H.History
  for distance:F.F64
  for ground:Bool
  {H.finish_finite(H.State{history},distance,ground,False{}) == (H.State{history},Fail{H.NonFiniteResult{}}) : H.State & Result<&2,&2,H.Error,Unit>}
def nonfinite_result_rolls_back_accumulation(history,distance,ground):
  {==}

law reset_error_retains_history_owner:
  for +history:H.History
  for +error:H.Error
  {H.reset_gate(H.State{history},Some{error}) == (H.State{history},Fail{error}) : H.State & Result<&2,&2,H.Error,Unit>}
def reset_error_retains_history_owner(history,error):
  {==}

law reset_success_has_positive_zero:
  for history:H.History
  {H.reset_gate(H.State{history},None{}) == (H.State{H.History{F.from_u32(0)}},Done{Unit{}}) : H.State & Result<&2,&2,H.Error,Unit>}
def reset_success_has_positive_zero(history):
  {==}

law clamp_false_preserves_raw_distance:
  for +distance:F.F64
  {H.clamp_if(distance,False{}) == distance : F.F64}
def clamp_false_preserves_raw_distance(distance):
  {==}

law clamp_true_is_exact_one:
  for distance:F.F64
  {H.clamp_if(distance,True{}) == F.from_u32(1) : F.F64}
def clamp_true_is_exact_one(distance):
  {==}

law missing_required_clip_is_rejected:
  {H.clip_error(True{},H.NotRequired{}) == Some{H.MissingClipObservation{}} : Maybe<&2,H.Error>}
def missing_required_clip_is_rejected():
  {==}

law skipped_position_has_no_clip_requirement:
  for distance:F.F64
  for squared:F.F64
  {H.clip_required(distance,False{},squared) == False{} : Bool}
def skipped_position_has_no_clip_requirement(distance,squared):
  {==}

# Runtime arguments are raw words only. Flags pack operation/mode/clip/gate and
# ground, keeping seven narrow parsed words and named continuations throughout.
def wide_words(value:F.F64) -> String:
  match value:
    case F.F64{hi,lo}: "[" ++ U32.show(hi) ++ "," ++ U32.show(lo) ++ "]"

def mode_code(mode:H.Mode) -> U32:
  match mode:
    case H.NeutralDryNoDamage{}: 0
    case H.NoPhysics{}: 1
    case H.WaterOrFluid{}: 2
    case H.FlightOrPassenger{}: 3
    case H.ClimbOrEffects{}: 4
    case H.UnsupportedWorld{}: 5
    case H.NonLocalAuthority{}: 6

def error_words(error:H.Error) -> String:
  match error:
    case H.NonFinite{field}: "{\"kind\":\"NonFinite\",\"field\":" ++ U32.show(field) ++ "}"
    case H.InvalidLengthSquared{}: "{\"kind\":\"InvalidLengthSquared\"}"
    case H.UnsupportedMode{mode}: "{\"kind\":\"UnsupportedMode\",\"mode\":" ++ U32.show(mode_code(mode)) ++ "}"
    case H.MissingClipObservation{}: "{\"kind\":\"MissingClipObservation\"}"
    case H.UnexpectedClipObservation{}: "{\"kind\":\"UnexpectedClipObservation\"}"
    case H.UnsupportedResetHit{}: "{\"kind\":\"UnsupportedResetHit\"}"
    case H.UnsupportedLanding{}: "{\"kind\":\"UnsupportedLanding\"}"
    case H.NonFiniteResult{}: "{\"kind\":\"NonFiniteResult\"}"

def status_words(result:Result<&2,&2,H.Error,Unit>) -> String:
  match result:
    case Done{_}: "\"ok\":true"
    case Fail{error}: "\"ok\":false,\"error\":" ++ error_words(error)

def report(result:H.State & Result<&2,&2,H.Error,Unit>) -> String:
  (H.State{H.History{distance}},status) = result
  "{" ++ status_words(status) ++ ",\"distance\":" ++ wide_words(distance) ++ "}"

def recovery(result:H.State & Result<&2,&2,H.Error,Unit>) -> String:
  (H.State{+history},status) = result
  "{\"first\":" ++ report((H.State{history},status)) ++ ",\"recovered\":" ++ report(H.reset(H.State{history})) ++ "}"

def twice_result(mode:H.Mode,movement:H.Movement,result:H.State & Result<&2,&2,H.Error,Unit>) -> String:
  (state,status) = result
  "{\"first_status\": {" ++ status_words(status) ++ "},\"second\":" ++ report(H.movement(mode,movement,state)) ++ "}"

def read_mode(word:U32) -> H.Mode:
  match word:
    case 0: H.NeutralDryNoDamage{}
    case 1: H.NoPhysics{}
    case 2: H.WaterOrFluid{}
    case 3: H.FlightOrPassenger{}
    case 4: H.ClimbOrEffects{}
    case 6: H.NonLocalAuthority{}
    case _: H.UnsupportedWorld{}

def read_clip(word:U32) -> H.Clip:
  match word:
    case 0: H.NotRequired{}
    case 1: H.Miss{}
    case 2: H.Hit{}
    case _: H.Unknown{}

def operation(op:U32,+mode:H.Mode,+movement:H.Movement,state:H.State,+y:F.F64) -> String:
  match op:
    case 0: report(H.movement(mode,movement,state))
    case 1: report(H.reset(state))
    case 2: report(H.check_accumulation(y,state))
    case 3: recovery(H.movement(mode,movement,state))
    case 4: twice_result(mode,movement,H.movement(mode,movement,state))
    case _: "{\"invalid_operation\":true}"

def flags_operation(+flags:U32,distance:F.F64,+y:F.F64,squared:F.F64) -> String:
  operation(U32.and(flags,15),read_mode(U32.and(U32.shrn(flags,4n),15)),H.Movement{U32.is_ne(U32.and(flags,4096),0),y,squared,U32.is_ne(U32.and(flags,8192),0),read_clip(U32.and(U32.shrn(flags,8n),3))},H.State{H.History{distance}},y)

def last_read(flags:U32,distance:F.F64,y:F.F64,hi:U32,lo:Maybe<&2,U32>) -> IO(Unit):
  match lo:
    case Some{lo}: IO.print(flags_operation(flags,distance,y,F.F64{hi,lo}))
    case None{}: IO.die(Unit,2,"invalid squared low word")

def squared_read(flags:U32,distance:F.F64,y:F.F64,hi:Maybe<&2,U32>,lo:String) -> IO(Unit):
  match hi:
    case Some{hi}: last_read(flags,distance,y,hi,U32.read(lo))
    case None{}: IO.die(Unit,2,"invalid squared high word")

def y_low_read(flags:U32,distance:F.F64,hi:U32,lo:Maybe<&2,U32>,squared_hi:String,squared_lo:String) -> IO(Unit):
  match lo:
    case Some{lo}: squared_read(flags,distance,F.F64{hi,lo},U32.read(squared_hi),squared_lo)
    case None{}: IO.die(Unit,2,"invalid Y low word")

def y_read(flags:U32,distance:F.F64,hi:Maybe<&2,U32>,lo:String,squared_hi:String,squared_lo:String) -> IO(Unit):
  match hi:
    case Some{hi}: y_low_read(flags,distance,hi,U32.read(lo),squared_hi,squared_lo)
    case None{}: IO.die(Unit,2,"invalid Y high word")

def distance_low_read(flags:U32,hi:U32,lo:Maybe<&2,U32>,y_hi:String,y_lo:String,squared_hi:String,squared_lo:String) -> IO(Unit):
  match lo:
    case Some{lo}: y_read(flags,F.F64{hi,lo},U32.read(y_hi),y_lo,squared_hi,squared_lo)
    case None{}: IO.die(Unit,2,"invalid distance low word")

def distance_read(flags:U32,hi:Maybe<&2,U32>,lo:String,y_hi:String,y_lo:String,squared_hi:String,squared_lo:String) -> IO(Unit):
  match hi:
    case Some{hi}: distance_low_read(flags,hi,U32.read(lo),y_hi,y_lo,squared_hi,squared_lo)
    case None{}: IO.die(Unit,2,"invalid distance high word")

def flags_read(flags:Maybe<&2,U32>,distance_hi:String,distance_lo:String,y_hi:String,y_lo:String,squared_hi:String,squared_lo:String) -> IO(Unit):
  match flags:
    case Some{flags}: distance_read(flags,U32.read(distance_hi),distance_lo,y_hi,y_lo,squared_hi,squared_lo)
    case None{}: IO.die(Unit,2,"invalid flags word")

def batch(args:List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case flags <> distance_hi <> distance_lo <> y_hi <> y_lo <> squared_hi <> squared_lo <> rest:
      do IO<Unit>:
        flags_read(U32.read(flags),distance_hi,distance_lo,y_hi,y_lo,squared_hi,squared_lo)
        batch(rest)
    case _: IO.die(Unit,2,"expected FLAGS DISTANCE_HI DISTANCE_LO Y_HI Y_LO SQUARED_HI SQUARED_LO groups")

def main() -> IO(Unit):
  do IO<Unit>:
    args:List<String> <- IO.args()
    batch(List.tail(&1,String,args))
