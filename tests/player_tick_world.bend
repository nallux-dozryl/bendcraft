import Base
import ../src/player_tick_world.bend as PW
import ../src/player_tick.bend as P
import ../src/client_world.bend as W
import ../src/travel_world.bend as TW
import ../src/travel.bend as V
import ../src/locomotion.bend as L
import ../src/movement.bend as M
import ../src/geometry.bend as G
import ../src/f64.bend as F
import ../src/core.bend as C
import ../src/game.bend as E
import ../src/registry.bend as B
import ./player_tick.bend as PTT
import ./travel.bend as VT
import ./travel_world.bend as WT
import ./locomotion.bend as LT
import ./client_world.bend as CW

type Harness is Type:
  Harness{world: W.State, tables: L.Tables, player: Maybe<&2, P.State>, tail: List<&1, Harness>}

def install(world: W.State, player: P.State) -> W.State:
  W.paired(E.Engine, W.View, W.State, W.take(world), engine => view => W.attach(engine, TW.with_body(view, PW.player_body(player))))

def error_show(error: PW.Error) -> String:
  match error:
    case PW.BodyMismatch{}: "body-mismatch"
    case PW.PreparationError{cause}: "prepare|" ++ PTT.error_show(cause)
    case PW.TravelError{cause}: "travel|" ++ WT.error_show(cause)
    case PW.FinishError{cause}: "finish|" ++ PTT.error_show(cause)

def result_report(+id: String, result: W.State & L.Tables & P.State & Result<&2, &2, PW.Error, P.Transition>) -> IO(Harness):
  (world, tables, +player, status) = result
  match status:
    case Fail{error}:
      do IO<Harness>:
        IO.print(id ++ "|error|" ++ error_show(error))
        IO.print(id ++ "|state|" ++ PTT.state_show(player))
        kept : W.State <- WT.state_report(id ++ "-after", world)
        return Harness{kept, tables, Some{player}, []}
    case Done{P.Transition{state, M.Transition{body, displacement, stepped, changed}, attempted, jumped}}:
      do IO<Harness>:
        IO.print(id ++ "|state|" ++ PTT.state_show(player))
        IO.print(id ++ "|transition-state|" ++ PTT.state_show(state))
        IO.print(id ++ "|transition|" ++ LT.vector_show(displacement) ++ "|" ++ U32.show(Bool.to_u32(stepped)) ++ "|" ++ U32.show(Bool.to_u32(changed)))
        IO.print(id ++ "|jumps|" ++ U32.show(Bool.to_u32(attempted)) ++ "|" ++ U32.show(Bool.to_u32(jumped)))
        kept : W.State <- WT.state_report(id ++ "-after", world)
        return Harness{kept, tables, Some{player}, []}

def call_tick(id: String, world: W.State, tables: L.Tables, player: P.State, context: P.Context) -> IO(Harness):
  result_report(id, PW.tick_checked(world, tables, player, context))

def trace_step(+id: String, registry: B.Registry, view: W.View, tables: L.Tables, player: P.State, context: P.Context, initial: List<&2, G.Collider>, result: C.World & Result<&2, &2, String, List<&2, G.Collider>>) -> IO(Harness):
  (world, status) = result
  match status:
    case Fail{error}: IO.die(Harness, 4, "step trace:" ++ error)
    case Done{step}:
      do IO<Harness>:
        IO.print(id ++ "|colliders|" ++ WT.shapes_show(initial) ++ "|" ++ WT.shapes_show(step))
        call_tick(id, W.attach(E.Engine{world, registry}, view), tables, player, context)

def trace_initial_status(+id: String, registry: B.Registry, +view: W.View, tables: L.Tables, player: P.State, context: P.Context, prepared: V.Prepared, world: C.World, status: Result<&2, &2, String, List<&2, G.Collider>>) -> IO(Harness):
  match view prepared status:
    case _ _ Fail{error}: IO.die(Harness, 4, "initial trace:" ++ error)
    case W.View{old, yaw, pitch, Some{+colors}, region, cache} V.Prepared{+body, +delta, friction, acceleration, +maximum, gravity, drag, discard} Done{+initial}:
      +box = W.body_box(body)
      +baseline = M.resolve(box, WT.grounded(body), 0.0, delta, initial, [])
      trace_step(id, registry, view, tables, player, context, initial, W.step_read(world, colors, W.resolution_query(box, delta, maximum, baseline), W.needs_step(body, maximum, delta, baseline)))
    case _ _ _: IO.die(Harness, 4, "trace palette unavailable")

def trace_initial(id: String, registry: B.Registry, view: W.View, tables: L.Tables, player: P.State, context: P.Context, prepared: V.Prepared, result: C.World & Result<&2, &2, String, List<&2, G.Collider>>) -> IO(Harness):
  (world, status) = result
  trace_initial_status(id, registry, view, tables, player, context, prepared, world, status)

def trace_world(+id: String, tables: L.Tables, player: P.State, context: P.Context, +prepared: V.Prepared, engine: E.Engine, +view: W.View) -> IO(Harness):
  match prepared engine view:
    case V.Prepared{+body, +delta, friction, acceleration, maximum, gravity, drag, discard} E.Engine{world, registry} W.View{old, yaw, pitch, Some{+colors}, region, cache}:
      trace_initial(id, registry, view, tables, player, context, prepared, W.initial_read(world, colors, body, delta, F.is_zero(M.Vec3.length_squared(delta))))
    case _ _ _: IO.die(Harness, 4, "trace palette unavailable")

def trace_extracted(id: String, tables: L.Tables, player: P.State, context: P.Context, prepared: V.Prepared, result: E.Engine & W.View) -> IO(Harness):
  (engine, view) = result
  trace_world(id, tables, player, context, prepared, engine, view)

def accelerated(+id: String, world: W.State, player: P.State, context: P.Context, result: L.Tables & Result<&2, &2, V.Error, V.Prepared>) -> IO(Harness):
  (tables, status) = result
  match status:
    case Fail{error}: IO.die(Harness, 4, "travel preparation:" ++ VT.error_show(error))
    case Done{+prepared}:
      V.Prepared{body, requested, friction, acceleration, maximum, gravity, drag, discard} = prepared
      do IO<Harness>:
        IO.print(id ++ "|accelerated|" ++ LT.vector_show(requested))
        trace_extracted(id, tables, player, context, prepared, W.take(world))

def observed_prepared(+id: String, world: W.State, player: P.State, +context: P.Context, result: L.Tables & Result<&2, &2, P.Error, P.PreTravel>) -> IO(Harness):
  (tables, status) = result
  match status:
    case Fail{error}: IO.die(Harness, 4, "tick preparation:" ++ PTT.error_show(error))
    case Done{P.PreTravel{+state, +input, attempted, jumped}}:
      do IO<Harness>:
        IO.print(id ++ "|prepared|" ++ PTT.state_show(state) ++ "|" ++ LT.vector_show(input))
        accelerated(id, world, player, context, V.prepare_checked(tables, PW.player_body(state), input, PW.travel_context(context)))

def injected_finish(+id: String, tables: L.Tables, +player: P.State, +context: P.Context, result: E.Engine & W.View) -> IO(Harness):
  (engine, +view) = result
  +body = PW.player_body(player)
  +changed = V.body_velocity(body, M.Vec3{F.from_f32(0.25), F.from_f32(0.5), M.zero()})
  malformed = {P.Context{PW.travel_context(context), M.zero(), 1.0, True{}, P.NearbyActors{}} : P.Context}
  prepared = {P.PreTravel{player, M.Vec3.zero(), False{}, False{}} : P.PreTravel}
  movement = {M.Transition{changed, M.Vec3.zero(), False{}, True{}} : M.Transition}
  result_report(id, PW.finished(W.attach(engine, TW.with_body(view, changed)), tables, view, player, P.finish_checked(prepared, malformed, movement)))

def run_current(+id: String, op: String, world: W.State, tables: L.Tables, +player: P.State, +context: P.Context) -> IO(Harness):
  match op:
    case "reject": call_tick(id, world, tables, player, context)
        case "finish-injection": injected_finish(id, tables, player, context, W.take(world))
    case _: observed_prepared(id, world, player, context, P.prepare_checked(tables, player, context))

def operation_world(op: String, world: W.State, player: P.State) -> W.State:
  match op:
    case "mismatch": CW.replace_body(world, V.body_velocity(PW.player_body(player), M.Vec3{F.from_f32(0.25), M.zero(), M.zero()}))
    case "zero-mismatch": CW.replace_body(world, V.body_velocity(PW.player_body(player), M.Vec3{F.F64{2147483648, 0}, M.zero(), M.zero()}))
    case _: world

def operation_name(op: String) -> String:
  match op:
    case "mismatch": "reject"
    case "zero-mismatch": "reject"
    case _: op

def before_current(+id: String, +op: String, world: W.State, tables: L.Tables, +player: P.State, context: P.Context) -> IO(Harness):
  do IO<Harness>:
    IO.print(id ++ "-before|state|" ++ PTT.state_show(player))
    original : W.State <- WT.state_report(id ++ "-before", operation_world(op, world, player))
    run_current(id, operation_name(op), original, tables, player, context)

def align_current(id: String, world: W.State, tables: L.Tables, +player: P.State, context: P.Context) -> IO(Harness):
  before_current(id, "chain", install(world, player), tables, player, context)

def continued_state(id: String, op: String, harness: Harness, next: P.State, context: P.Context, input_update: Bool, jump_update: Bool) -> IO(Harness):
  Harness{world, tables, prior, tail} = harness
  match prior:
    case None{}: IO.die(Harness, 2, "player world chain absent")
    case Some{previous}: before_current(id, op, world, tables, PTT.controlled(previous, next, input_update, jump_update), context)

def loaded_missing(+id: String, tables: L.Tables, +player: P.State, context: P.Context, result: W.State & Result<&2, &2, String, Unit>) -> IO(Harness):
  (world, status) = result
  match status:
    case Fail{error}: IO.die(Harness, 3, "empty world:" ++ error)
    case Done{unit}: before_current(id, "reject", install(world, player), tables, player, context)

def missing_world(id: String, tables: L.Tables, player: P.State, context: P.Context, result: E.Engine & W.View) -> IO(Harness):
  (E.Engine{discarded, registry}, view) = result
  loaded_missing(id, tables, player, context, W.new(E.new(registry)))

def repaired_fixture(+id: String, tables: L.Tables, +player: P.State, context: P.Context, result: W.State & Result<&2, &2, String, Unit>) -> IO(Harness):
  (world, status) = result
  match status:
    case Fail{error}: IO.die(Harness, 3, "repair fixture:" ++ error)
    case Done{unit}: align_current(id, WT.warmed(W.snapshot(install(world, player), 64, 48)), tables, player, context)

def fixture_engine(id: String, tables: L.Tables, player: P.State, context: P.Context, result: E.Engine & W.View) -> IO(Harness):
  (engine, view) = result
  repaired_fixture(id, tables, player, context, W.fixture(engine))

def execute(+id: String, op: String, harness: Harness, +next: P.State, context: P.Context, input_update: Bool, jump_update: Bool) -> IO(Harness):
  match op:
    case "start":
      Harness{world, tables, prior, tail} = harness
      align_current(id, world, tables, next, context)
    case "running-start":
      Harness{world, tables, prior, tail} = harness
      align_current(id, WT.set_running(world), tables, next, context)
    case "align":
      Harness{world, tables, prior, tail} = harness
      align_current(id, world, tables, next, context)
    case "missing":
      Harness{world, tables, prior, tail} = harness
      missing_world(id, tables, next, context, W.take(world))
    case "fixture-recovery":
      Harness{world, tables, prior, tail} = harness
      fixture_engine(id, tables, next, context, W.take(world))
    case "unsupported":
      Harness{world, tables, prior, tail} = harness
      before_current(id, "reject", install(CW.unsupported(world), next), tables, next, context)
    case "repair-air":
      Harness{world, tables, prior, tail} = harness
      W.State{engine, body, yaw, pitch, +palette, region, cache} = world
      match palette:
        case None{}: IO.die(Harness, 3, "repair palette unavailable")
        case Some{W.Palette{air, stone, dirt, planks}}: align_current(id, CW.advance(CW.change_block(W.State{engine, body, yaw, pitch, palette, region, cache}, air)), tables, next, context)
    case _: continued_state(id, op, harness, next, context, input_update, jump_update)

def parsed(id: String, op: String, harness: Harness, fields: Maybe<&2, List<&2, U32>>) -> IO(Harness):
  match fields:
    case Some{pxh <> pxl <> pyh <> pyl <> pzh <> pzl <> axh <> axl <> ayh <> ayl <> azh <> azl <> bxh <> bxl <> byh <> byl <> bzh <> bzl <> vxh <> vxl <> vyh <> vyl <> vzh <> vzl <> width <> height <> ground <> horizontal <> vertical <> below <> ix <> iy <> iz <> jumping <> delay <> trigger <> sync <> speed <> head <> gx <> gy <> gz <> friction <> sh <> sl <> gh <> gl <> fh <> fl <> dh <> dl <> yaw <> maximum <> sprint <> no_gravity <> discard <> travel_mode <> jh <> jl <> jump_factor <> affected <> tick_mode <> input_update <> jump_update <> Nil{}}:
      body = {M.Body{M.Vec3{F.F64{pxh, pxl}, F.F64{pyh, pyl}, F.F64{pzh, pzl}}, G.AABB{F.F64{axh, axl}, F.F64{ayh, ayl}, F.F64{azh, azl}, F.F64{bxh, bxl}, F.F64{byh, byl}, F.F64{bzh, bzl}}, M.Vec3{F.F64{vxh, vxl}, F.F64{vyh, vyl}, F.F64{vzh, vzl}}, L.float_bits(width), L.float_bits(height), U32.is_ne(ground, 0), U32.is_ne(horizontal, 0), U32.is_ne(vertical, 0), U32.is_ne(below, 0)} : M.Body}
      state = {P.State{body, P.Input{L.float_bits(ix), L.float_bits(iy), L.float_bits(iz)}, U32.is_ne(jumping, 0), delay, trigger, U32.is_ne(sync, 0), L.float_bits(speed), L.float_bits(head)} : P.State}
      travel = {V.Context{V.GroundSample{V.BlockPos{gx, gy, gz}, L.float_bits(friction)}, V.Attributes{F.F64{sh, sl}, F.F64{gh, gl}, F.F64{fh, fl}, F.F64{dh, dl}}, L.float_bits(yaw), L.float_bits(maximum), U32.is_ne(sprint, 0), U32.is_ne(no_gravity, 0), U32.is_ne(discard, 0), VT.mode(travel_mode)} : V.Context}
      context = {P.Context{travel, F.F64{jh, jl}, L.float_bits(jump_factor), U32.is_ne(affected, 0), PTT.mode(tick_mode)} : P.Context}
      execute(id, op, harness, state, context, U32.is_ne(input_update, 0), U32.is_ne(jump_update, 0))
    case _: IO.die(Harness, 2, "invalid player tick fields")

def dispatch(fields: List<&2, String>, harness: Harness) -> IO(Harness):
  match fields:
    case id <> op <> rest: parsed(id, op, harness, LT.numbers(rest))
    case _: IO.die(Harness, 2, "invalid player-world fields")

def continue_args(args: List<String>, harness: Harness) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case value <> rest:
      do IO<Unit>:
        next : Harness <- dispatch(String.split(value, '|'), harness)
        continue_args(rest, next)

def loaded_world(args: List<String>, tables: L.Tables, result: W.State & Result<&2, &2, String, Unit>) -> IO(Unit):
  (world, status) = result
  match status:
    case Fail{error}: IO.die(Unit, 3, "fixture:" ++ error)
    case Done{unit}: continue_args(args, Harness{WT.warmed(W.snapshot(world, 64, 48)), tables, None{}, []})

def loaded_table(args: List<String>, result: Result<&2, &1, L.Error, L.Tables>) -> IO(Unit):
  match result:
    case Fail{error}: IO.die(Unit, 3, "table:" ++ LT.error_text(error))
    case Done{tables}:
      do IO<Unit>:
        engine : E.Engine <- E.load()
        loaded_world(args, tables, W.fixture(engine))

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case program <> path <> rest:
      do IO<Unit>:
        tables : Result<&2, &1, L.Error, L.Tables> <- L.Tables.load(path)
        loaded_table(rest, tables)
    case _: IO.die(Unit, 2, "player-world table path required")

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), arguments)
