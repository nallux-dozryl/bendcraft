import Base
import ../src/player_look.bend as L
import ../src/player_rotation_tick.bend as T

law snapshot_copies_current:
  for +yaw: F32
  for +pitch: F32
  for previous_yaw: F32
  for previous_pitch: F32
  for count: U32
  {T.snapshot(L.State{yaw,pitch,previous_yaw,previous_pitch},count,False{}) == T.State{L.State{yaw,pitch,yaw,pitch},count} : T.State}

def snapshot_copies_current(yaw,pitch,previous_yaw,previous_pitch,count):
  {==}

law rejected_snapshot_retains_owner:
  for +look: L.State
  for +count: U32
  for increment: Bool
  for +error: T.Error
  {T.snapshot_gate(T.State{look,count},increment,Some{error}) == (T.State{look,count},Fail{error}) : T.State & Result<&2,&2,T.Error,Unit>}

def rejected_snapshot_retains_owner(look,count,increment,error):
  {==}

law rejected_normalization_retains_owner:
  for +look: L.State
  for +count: U32
  for fuel: Nat
  for +error: T.Error
  for bounded: Bool
  {T.normalize_gate(T.State{look,count},fuel,Some{error},bounded) == (T.State{look,count},Fail{error}) : T.State & Result<&2,&2,T.Error,Unit>}

def rejected_normalization_retains_owner(look,count,fuel,error,bounded):
  {==}

law excessive_fuel_retains_owner:
  for +look: L.State
  for +count: U32
  for fuel: Nat
  {T.normalize_gate(T.State{look,count},fuel,None{},False{}) == (T.State{look,count},Fail{T.FuelLimit{}}) : T.State & Result<&2,&2,T.Error,Unit>}

def excessive_fuel_retains_owner(look,count,fuel):
  {==}

law no_negative_update_spends_no_fuel:
  for +fuel: Nat
  for axis: U32
  for current: F32
  for +previous: F32
  {T.lower_loop(fuel,axis,current,previous,False{}) == Done{T.Axis{previous,fuel}} : Result<&2,&2,T.Error,T.Axis>}

def no_negative_update_spends_no_fuel(fuel,axis,current,previous):
  match fuel:
    case 0n: {==}
    case 1n+rest: {==}

law no_positive_update_spends_no_fuel:
  for +fuel: Nat
  for axis: U32
  for current: F32
  for +previous: F32
  {T.upper_loop(fuel,axis,current,previous,False{}) == Done{T.Axis{previous,fuel}} : Result<&2,&2,T.Error,T.Axis>}

def no_positive_update_spends_no_fuel(fuel,axis,current,previous):
  match fuel:
    case 0n: {==}
    case 1n+rest: {==}

law zero_fuel_update_rejected:
  for axis: U32
  for current: F32
  for previous: F32
  {T.lower_loop(0n,axis,current,previous,True{}) == Fail{T.FuelExhausted{axis}} : Result<&2,&2,T.Error,T.Axis>}

def zero_fuel_update_rejected(axis,current,previous):
  {==}

law common_counter_wrap_fixture:
  {T.snapshot_count(4294967295,True{}) == 0 : U32}

def common_counter_wrap_fixture():
  {==}

law finite_field_has_no_angle_gate:
  for field: U32
  {T.field_error(field,True{}) == None{} : Maybe<&2,T.Error>}

def finite_field_has_no_angle_gate(field):
  {==}

law zero_fuel_positive_update_rejected:
  for axis: U32
  for current: F32
  for previous: F32
  {T.upper_loop(0n,axis,current,previous,True{}) == Fail{T.FuelExhausted{axis}} : Result<&2,&2,T.Error,T.Axis>}

def zero_fuel_positive_update_rejected(axis,current,previous):
  {==}

law pitch_failure_rolls_back_completed_yaw:
  for +look: L.State
  for +count: U32
  for yaw: F32
  for +error: T.Error
  {T.pitch_done(T.State{look,count},yaw,Fail{error}) == (T.State{look,count},Fail{error}) : T.State & Result<&2,&2,T.Error,Unit>}

def pitch_failure_rolls_back_completed_yaw(look,count,yaw,error):
  match look:
    case L.State{a,b,c,d}: {==}

# Native inputs are raw words. Named continuations avoid wide computed matches;
# no other test module or JSON implementation participates in this executable.
def look_words(value:L.State) -> String:
  match value:
    case L.State{a,b,c,d}: "[" ++ U32.show(L.raw(a)) ++ "," ++ U32.show(L.raw(b)) ++ "," ++ U32.show(L.raw(c)) ++ "," ++ U32.show(L.raw(d)) ++ "]"

def error_words(error:T.Error) -> String:
  match error:
    case T.InvalidState{field}: "{\"kind\":\"InvalidState\",\"field\":" ++ U32.show(field) ++ "}"
    case T.FuelLimit{}: "{\"kind\":\"FuelLimit\"}"
    case T.FuelExhausted{axis}: "{\"kind\":\"FuelExhausted\",\"axis\":" ++ U32.show(axis) ++ "}"

def status_words(result:Result<&2,&2,T.Error,Unit>) -> String:
  match result:
    case Done{_}: "\"ok\":true"
    case Fail{error}: "\"ok\":false,\"error\":" ++ error_words(error)

def report(result:T.State & Result<&2,&2,T.Error,Unit>) -> String:
  (T.State{look,count},status) = result
  "{" ++ status_words(status) ++ ",\"state\":" ++ look_words(look) ++ ",\"count\":" ++ U32.show(count) ++ "}"

def recovery(result:T.State & Result<&2,&2,T.Error,Unit>) -> String:
  (T.State{+look,+count},status) = result
  "{\"first\":" ++ report((T.State{look,count},status)) ++ ",\"recovered\":" ++ report(T.common_tick(T.State{look,count})) ++ "}"

def both_phases(result:T.State & Result<&2,&2,T.Error,Unit>) -> String:
  (state,status) = result
  "{\"snapshot_status\": {" ++ status_words(status) ++ "},\"normalized\":" ++ report(T.normalize(16384n,state)) ++ "}"

def truth(value:Bool) -> String:
  match value:
    case True{}: "true"
    case False{}: "false"

def numeric_axis(+current:F32,+previous:F32) -> String:
  +minus = T.sub(previous,L.float_bits(1135869952))
  +plus = L.add(previous,L.float_bits(1135869952))
  "{\"difference\":" ++ U32.show(L.raw(T.sub(current,previous))) ++
  ",\"negative_needed\":" ++ truth(T.below(current,previous)) ++
  ",\"positive_needed\":" ++ truth(T.above(current,previous)) ++
  ",\"minus360\":" ++ U32.show(L.raw(minus)) ++
  ",\"plus360\":" ++ U32.show(L.raw(plus)) ++
  ",\"minus_difference\":" ++ U32.show(L.raw(T.sub(current,minus))) ++
  ",\"plus_difference\":" ++ U32.show(L.raw(T.sub(current,plus))) ++
  ",\"minus_finished\":" ++ truth(Bool.not(T.below(current,minus)) && Bool.not(T.above(current,minus))) ++
  ",\"plus_finished\":" ++ truth(Bool.not(T.below(current,plus)) && Bool.not(T.above(current,plus))) ++ "}"

# Standalone arithmetic diagnostic, independently observed from Java operators.
# This path does not invoke a Minecraft full tick or implement one in the host.
def numeric_state(state:T.State) -> String:
  match state:
    case T.State{L.State{yaw,pitch,old_yaw,old_pitch},_}:
      "{\"yaw\":" ++ numeric_axis(yaw,old_yaw) ++ ",\"pitch\":" ++ numeric_axis(pitch,old_pitch) ++ "}"

def operation(op:U32,fuel:Nat,state:T.State) -> String:
  match op:
    case 0: report(T.set_old_rot(state))
    case 1: report(T.common_tick(state))
    case 2: report(T.normalize(fuel,state))
    case 3: report((state,Done{Unit{}}))
    case 4: recovery(T.normalize(fuel,state))
    case 5: both_phases(T.common_tick(state))
    case 6: numeric_state(state)
    case _: "{\"invalid_operation\":true}"

# Parsing is sequential: raw fixture words have no application semantics here.
def count_read(op:U32,fuel:Nat,look:L.State,count:Maybe<&2,U32>) -> IO(Unit):
  match count:
    case Some{count}: IO.print(operation(op,fuel,T.State{look,count}))
    case None{}: IO.die(Unit,2,"invalid count word")

def previous_read(op:U32,fuel:Nat,yaw:F32,pitch:F32,old_yaw:F32,old_pitch:Maybe<&2,U32>,count:String) -> IO(Unit):
  match old_pitch:
    case Some{old_pitch}: count_read(op,fuel,L.State{yaw,pitch,old_yaw,L.float_bits(old_pitch)},U32.read(count))
    case None{}: IO.die(Unit,2,"invalid previous pitch word")

def old_yaw_read(op:U32,fuel:Nat,yaw:F32,pitch:F32,old_yaw:Maybe<&2,U32>,old_pitch:String,count:String) -> IO(Unit):
  match old_yaw:
    case Some{old_yaw}: previous_read(op,fuel,yaw,pitch,L.float_bits(old_yaw),U32.read(old_pitch),count)
    case None{}: IO.die(Unit,2,"invalid previous yaw word")

def pitch_read(op:U32,fuel:Nat,yaw:F32,pitch:Maybe<&2,U32>,old_yaw:String,old_pitch:String,count:String) -> IO(Unit):
  match pitch:
    case Some{pitch}: old_yaw_read(op,fuel,yaw,L.float_bits(pitch),U32.read(old_yaw),old_pitch,count)
    case None{}: IO.die(Unit,2,"invalid pitch word")

def yaw_read(op:U32,fuel:Nat,yaw:Maybe<&2,U32>,pitch:String,old_yaw:String,old_pitch:String,count:String) -> IO(Unit):
  match yaw:
    case Some{yaw}: pitch_read(op,fuel,L.float_bits(yaw),U32.read(pitch),old_yaw,old_pitch,count)
    case None{}: IO.die(Unit,2,"invalid yaw word")

def fuel_read(op:U32,fuel:Maybe<&2,Nat>,yaw:String,pitch:String,old_yaw:String,old_pitch:String,count:String) -> IO(Unit):
  match fuel:
    case Some{fuel}: yaw_read(op,fuel,U32.read(yaw),pitch,old_yaw,old_pitch,count)
    case None{}: IO.die(Unit,2,"invalid fuel")

def op_read(op:Maybe<&2,U32>,fuel:String,yaw:String,pitch:String,old_yaw:String,old_pitch:String,count:String) -> IO(Unit):
  match op:
    case Some{op}: fuel_read(op,Nat.read(fuel),yaw,pitch,old_yaw,old_pitch,count)
    case None{}: IO.die(Unit,2,"invalid operation word")

def batch(args:List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case op <> fuel <> yaw <> pitch <> old_yaw <> old_pitch <> count <> rest:
      do IO<Unit>:
        op_read(U32.read(op),fuel,yaw,pitch,old_yaw,old_pitch,count)
        batch(rest)
    case _: IO.die(Unit,2,"expected OP FUEL YAW PITCH PREV_YAW PREV_PITCH COUNT groups")

def main() -> IO(Unit):
  do IO<Unit>:
    args:List<String> <- IO.args()
    batch(List.tail(&1,String,args))
