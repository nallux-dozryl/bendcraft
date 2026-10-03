import Base
import ../src/f64.bend as F
import ../src/geometry.bend as G
import ../src/movement.bend as M
import ../src/locomotion.bend as L
import ../src/travel.bend as V
import ../src/player_tick.bend as P
import ./geometry.bend as GT
import ./movement.bend as MT
import ./locomotion.bend as LT
import ./travel.bend as VT

def mode(index: U32) -> P.Mode:
  match index:
    case 0: P.Neutral{}
    case 1: P.Immobile{}
    case 2: P.Interpolating{}
    case 3: P.SimulationDisabled{}
    case 4: P.IneffectiveAi{}
    case 5: P.NonEmptyEquipment{}
    case 6: P.NearbyActors{}
    case _: P.NonNeutralEffects{}

def mode_show(mode: P.Mode) -> String:
  match mode:
    case P.Neutral{}: "0"
    case P.Immobile{}: "1"
    case P.Interpolating{}: "2"
    case P.SimulationDisabled{}: "3"
    case P.IneffectiveAi{}: "4"
    case P.NonEmptyEquipment{}: "5"
    case P.NearbyActors{}: "6"
    case P.NonNeutralEffects{}: "7"

def error_show(error: P.Error) -> String:
  match error:
    case P.UnsupportedContext{mode}: "mode|" ++ mode_show(mode)
    case P.TravelError{cause}: "travel|" ++ VT.error_show(cause)
    case P.InvalidState{field}: "state|" ++ U32.show(field)
    case P.InvalidJump{field}: "jump|" ++ U32.show(field)

def state_show(state: P.State) -> String:
  match state:
    case P.State{body, P.Input{x, y, z}, jumping, delay, trigger, sync, speed, head}:
      VT.body_show(body) ++ "|" ++ U32.show(F32.bits(x)) ++ "|" ++ U32.show(F32.bits(y)) ++ "|" ++ U32.show(F32.bits(z)) ++ "|" ++ U32.show(Bool.to_u32(jumping)) ++ "|" ++ U32.show(delay) ++ "|" ++ U32.show(trigger) ++ "|" ++ U32.show(Bool.to_u32(sync)) ++ "|" ++ U32.show(F32.bits(speed)) ++ "|" ++ U32.show(F32.bits(head))

def moved_show(id: String, prior: Maybe<&2, P.State>, read: L.Tables & Result<&2, &2, P.Error, P.Transition>) -> IO(L.Tables & Maybe<&2, P.State>):
  (tables, result) = read
  match result:
    case Fail{error}:
      do IO<L.Tables & Maybe<&2, P.State>>:
        IO.print(id ++ "|error|" ++ error_show(error))
        return (tables, prior)
    case Done{P.Transition{+state, movement, attempted, jumped}}:
      do IO<L.Tables & Maybe<&2, P.State>>:
        IO.print(id ++ "|state|" ++ state_show(state))
        return (tables, Some{state})

def prepared_show(id: String, prior: Maybe<&2, P.State>, read: L.Tables & Result<&2, &2, P.Error, P.PreTravel>) -> IO(L.Tables & Maybe<&2, P.State>):
  (tables, result) = read
  match result:
    case Fail{error}:
      do IO<L.Tables & Maybe<&2, P.State>>:
        IO.print(id ++ "|error|" ++ error_show(error))
        return (tables, prior)
    case Done{P.PreTravel{state, input, attempted, jumped}}:
      do IO<L.Tables & Maybe<&2, P.State>>:
        IO.print(id ++ "|prepared|" ++ state_show(state) ++ "|" ++ LT.vector_show(input))
        return (tables, prior)

def choose_input(prior: P.Input, next: P.Input, updated: Bool) -> P.Input:
  match updated:
    case True{}: next
    case False{}: prior

def choose_jump(prior: Bool, next: Bool, updated: Bool) -> Bool:
  match updated:
    case True{}: next
    case False{}: prior

def controlled(prior: P.State, next: P.State, input_update: Bool, jump_update: Bool) -> P.State:
  match prior next:
    case P.State{body, input, jumping, delay, trigger, sync, speed, head}
         P.State{discarded, next_input, next_jump, next_delay, next_trigger, next_sync, next_speed, next_head}:
      P.State{body, choose_input(input, next_input, input_update), choose_jump(jumping, next_jump, jump_update), delay, trigger, sync, speed, head}

def continue_tick(id: String, tables: L.Tables, prior: Maybe<&2, P.State>, next: P.State, context: P.Context, initial: List<&2, G.Collider>, step: List<&2, G.Collider>, input_update: Bool, jump_update: Bool) -> IO(L.Tables & Maybe<&2, P.State>):
  match prior:
    case None{}: IO.die(L.Tables & Maybe<&2, P.State>, 2, "invalid player tick chain")
    case Some{+previous}: moved_show(id, Some{previous}, P.tick_checked(tables, controlled(previous, next, input_update, jump_update), context, initial, step))

def jump_show(id: String, prior: Maybe<&2, P.State>, power: F32, read: L.Tables & P.PreTravel) -> IO(L.Tables & Maybe<&2, P.State>):
  (tables, value) = read
  P.PreTravel{P.State{body, input, jumping, delay, trigger, sync, speed, head}, vector, attempted, jumped} = value
  do IO<L.Tables & Maybe<&2, P.State>>:
    IO.print(id ++ "|jump|" ++ VT.body_show(body) ++ "|" ++ U32.show(Bool.to_u32(sync)) ++ "|" ++ U32.show(F32.bits(power)))
    return (tables, prior)

def jump_sample(id: String, tables: L.Tables, prior: Maybe<&2, P.State>, state: P.State, +context: P.Context) -> IO(L.Tables & Maybe<&2, P.State>):
  P.Context{travel, strength, factor, affected, mode} = context
  jump_show(id, prior, P.jump_power(strength, factor), P.jump_attempt(tables, state, context))

def execute(id: String, op: String, tables: L.Tables, prior: Maybe<&2, P.State>, state: P.State, context: P.Context, initial: List<&2, G.Collider>, step: List<&2, G.Collider>, input_update: Bool, jump_update: Bool) -> IO(L.Tables & Maybe<&2, P.State>):
  match op:
    case "prepare": prepared_show(id, prior, P.prepare_checked(tables, state, context))
    case "tick": moved_show(id, prior, P.tick_checked(tables, state, context, initial, step))
    case "chain": continue_tick(id, tables, prior, state, context, initial, step, input_update, jump_update)
    case "jump": jump_sample(id, tables, prior, state, context)
    case _: IO.die(L.Tables & Maybe<&2, P.State>, 2, "invalid player tick operation")

def parsed(id: String, op: String, tables: L.Tables, prior: Maybe<&2, P.State>, fields: Maybe<&2, List<&2, U32>>, initial: Maybe<&2, List<&2, G.Collider>>, step: Maybe<&2, List<&2, G.Collider>>) -> IO(L.Tables & Maybe<&2, P.State>):
  match fields initial step:
    case Some{pxh <> pxl <> pyh <> pyl <> pzh <> pzl <> axh <> axl <> ayh <> ayl <> azh <> azl <> bxh <> bxl <> byh <> byl <> bzh <> bzl <> vxh <> vxl <> vyh <> vyl <> vzh <> vzl <> width <> height <> ground <> horizontal <> vertical <> below <> ix <> iy <> iz <> jumping <> delay <> trigger <> sync <> speed <> head <> gx <> gy <> gz <> friction <> sh <> sl <> gh <> gl <> fh <> fl <> dh <> dl <> yaw <> maximum <> sprint <> no_gravity <> discard <> travel_mode <> jh <> jl <> jump_factor <> affected <> tick_mode <> input_update <> jump_update <> Nil{}} Some{initial} Some{step}:
      body = {M.Body{M.Vec3{F.F64{pxh, pxl}, F.F64{pyh, pyl}, F.F64{pzh, pzl}}, G.AABB{F.F64{axh, axl}, F.F64{ayh, ayl}, F.F64{azh, azl}, F.F64{bxh, bxl}, F.F64{byh, byl}, F.F64{bzh, bzl}}, M.Vec3{F.F64{vxh, vxl}, F.F64{vyh, vyl}, F.F64{vzh, vzl}}, L.float_bits(width), L.float_bits(height), U32.is_ne(ground, 0), U32.is_ne(horizontal, 0), U32.is_ne(vertical, 0), U32.is_ne(below, 0)} : M.Body}
      state = {P.State{body, P.Input{L.float_bits(ix), L.float_bits(iy), L.float_bits(iz)}, U32.is_ne(jumping, 0), delay, trigger, U32.is_ne(sync, 0), L.float_bits(speed), L.float_bits(head)} : P.State}
      travel = {V.Context{V.GroundSample{V.BlockPos{gx, gy, gz}, L.float_bits(friction)}, V.Attributes{F.F64{sh, sl}, F.F64{gh, gl}, F.F64{fh, fl}, F.F64{dh, dl}}, L.float_bits(yaw), L.float_bits(maximum), U32.is_ne(sprint, 0), U32.is_ne(no_gravity, 0), U32.is_ne(discard, 0), VT.mode(travel_mode)} : V.Context}
      context = {P.Context{travel, F.F64{jh, jl}, L.float_bits(jump_factor), U32.is_ne(affected, 0), mode(tick_mode)} : P.Context}
      execute(id, op, tables, prior, state, context, initial, step, U32.is_ne(input_update, 0), U32.is_ne(jump_update, 0))
    case _ _ _: IO.die(L.Tables & Maybe<&2, P.State>, 2, "invalid player tick fields")

def header(parts: List<&2, String>, tables: L.Tables, prior: Maybe<&2, P.State>, initial: List<&2, String>, step: List<&2, String>) -> IO(L.Tables & Maybe<&2, P.State>):
  match parts:
    case id <> op <> rest: parsed(id, op, tables, prior, LT.numbers(rest), GT.read_colliders(initial), GT.read_colliders(step))
    case _: IO.die(L.Tables & Maybe<&2, P.State>, 2, "invalid player tick header")

def dispatch(parts: List<&2, String>, tables: L.Tables, prior: Maybe<&2, P.State>) -> IO(L.Tables & Maybe<&2, P.State>):
  match parts:
    case first <> initial <> step <> Nil{}: header(String.split(first, '|'), tables, prior, MT.shape_fields(initial), MT.shape_fields(step))
    case _: IO.die(L.Tables & Maybe<&2, P.State>, 2, "invalid player tick protocol")

def pair_action(read: L.Tables & Maybe<&2, P.State>, next: L.Tables -> Maybe<&2, P.State> -> IO(Unit)) -> IO(Unit):
  (tables, state) = read
  next(tables, state)

def run_args(args: List<String>, tables: L.Tables, prior: Maybe<&2, P.State>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case arg <> rest:
      IO.bind(L.Tables & Maybe<&2, P.State>, Unit, dispatch(String.split(arg, ';'), tables, prior), read => pair_action(read, tables => state => run_args(rest, tables, state)))

def loaded(args: List<String>, result: Result<&2, &1, L.Error, L.Tables>) -> IO(Unit):
  match result:
    case Fail{error}: IO.die(Unit, 3, "invalid player tick table|" ++ LT.error_text(error))
    case Done{tables}: run_args(args, tables, None{})

def table_path(args: List<String>) -> IO(Unit):
  match args:
    case path <> rest:
      do IO<Unit>:
        result : Result<&2, &1, L.Error, L.Tables> <- L.Tables.load(path)
        loaded(rest, result)
    case _: IO.die(Unit, 2, "player tick table path required")

def drop_program(args: List<String>) -> IO(Unit):
  match args:
    case program <> rest: table_path(rest)
    case _: IO.die(Unit, 2, "player tick arguments required")

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), drop_program)
