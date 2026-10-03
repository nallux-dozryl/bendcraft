import Base
import ../src/client_world.bend as W
import ../src/travel_world.bend as TW
import ../src/travel.bend as V
import ../src/locomotion.bend as L
import ../src/movement.bend as M
import ../src/f64.bend as F
import ../src/geometry.bend as G
import ../src/game.bend as E
import ../src/core.bend as C
import ../src/registry.bend as B
import ../src/schedule.bend as Q
import ./travel.bend as VT
import ./locomotion.bend as LT
import ./client_world.bend as CW

import ../src/client_render.bend as R

def raw_show(blocks: List<&2, W.RawBlock>) -> String:
  match blocks:
    case Nil{}: ""
    case W.RawBlock{W.Cell{x, y, z, boundary}, state, material} <> rest:
      U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z) ++ "," ++ U32.show(boundary) ++ "," ++ U32.show(state) ++ "," ++ U32.show(material) ++ ";" ++ raw_show(rest)

def bounds_show(bounds: W.Bounds) -> String:
  W.Bounds{x, y, z, w, h, d} = bounds
  U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z) ++ "," ++ U32.show(w) ++ "," ++ U32.show(h) ++ "," ++ U32.show(d)

def palette_show(palette: W.Palette) -> String:
  W.Palette{air, stone, dirt, planks} = palette
  U32.show(air) ++ "," ++ U32.show(stone) ++ "," ++ U32.show(dirt) ++ "," ++ U32.show(planks)

def optional_palette(palette: Maybe<&2, W.Palette>) -> String:
  match palette:
    case None{}: "none"
    case Some{value}: palette_show(value)

def cache_show(cache: Maybe<&2, W.SnapshotCache>) -> String:
  match cache:
    case None{}: "none"
    case Some{W.SnapshotCache{revision, region, palette, blocks}}:
      Nat.show(revision) ++ ":" ++ bounds_show(region) ++ ":" ++ palette_show(palette) ++ ":" ++ raw_show(blocks)

def view_show(view: W.View) -> String:
  W.View{body, yaw, pitch, palette, region, cache} = view
  U32.show(F32.bits(yaw)) ++ "|" ++ U32.show(F32.bits(pitch)) ++ "|" ++ optional_palette(palette) ++ "|" ++ bounds_show(region) ++ "|" ++ cache_show(cache)

def state_report(+id: String, state: W.State) -> IO(W.State):
  W.State{E.Engine{C.World{+tick, +time, +paused, +daylight, +revision, count, sections, +pending, +events}, registry}, +body, +yaw, +pitch, +palette, +region, +cache} = state
  do IO<W.State>:
    IO.print(id ++ "|body|" ++ VT.body_show(body))
    IO.print(id ++ "|clock|" ++ Nat.show(tick) ++ "|" ++ Nat.show(time) ++ "|" ++ U32.show(Bool.to_u32(paused)) ++ "|" ++ U32.show(Bool.to_u32(daylight)) ++ "|" ++ Nat.show(revision) ++ "|" ++ Nat.show(List.length(&2, Q.Pending<C.Mutation>, pending)) ++ "|" ++ Nat.show(List.length(&2, C.CoreEvent, events)))
    IO.print(id ++ "|view|" ++ view_show(W.View{body, yaw, pitch, palette, region, cache}))
    return W.State{E.Engine{C.World{tick, time, paused, daylight, revision, count, sections, pending, events}, registry}, body, yaw, pitch, palette, region, cache}

def continued(+id: String, tables: L.Tables, result: W.State & Result<&2, &2, String, R.Snapshot>) -> IO(L.Tables):
  (state, status) = result
  match status:
    case Fail{error}:
      do IO<L.Tables>:
        IO.print(id ++ "|continued|error|" ++ error)
        return tables
    case Done{value}:
      do IO<L.Tables>:
        IO.print(id ++ "|continued|done")
        return tables

def error_show(error: TW.Error) -> String:
  match error:
    case TW.PreparationError{cause}: "prepare|" ++ VT.error_show(cause)
    case TW.WorldMovementError{cause}: "world|" ++ cause
    case TW.FinishError{cause}: "finish|" ++ VT.error_show(cause)

def result_report(+id: String, result: W.State & L.Tables & Result<&2, &2, TW.Error, M.Transition>) -> IO(W.State & L.Tables):
  (state, tables, status) = result
  match status:
    case Fail{error}:
      do IO<W.State & L.Tables>:
        IO.print(id ++ "|error|" ++ error_show(error))
        after : W.State <- state_report(id ++ "-after", state)
        return (after, tables)
    case Done{M.Transition{+body, displacement, stepped, changed}}:
      do IO<W.State & L.Tables>:
        IO.print(id ++ "|body|" ++ VT.body_show(body))
        IO.print(id ++ "|transition|" ++ LT.vector_show(displacement) ++ "|" ++ U32.show(Bool.to_u32(stepped)) ++ "|" ++ U32.show(Bool.to_u32(changed)))
        after : W.State <- state_report(id ++ "-after", state)
        return (after, tables)

def retained(+id: String, result: W.State & L.Tables) -> IO(L.Tables):
  (state, tables) = result
  continued(id, tables, W.snapshot(state, 64, 48))

def neutral(context: V.Context) -> V.Context:
  V.Context{ground, attributes, yaw, maximum, sprint, gravity, discard, mode} = context
  V.Context{ground, attributes, yaw, maximum, sprint, gravity, discard, V.NeutralDryAir{}}

def retry(+id: String, input: M.Vec3, context: V.Context, result: W.State & L.Tables) -> IO(L.Tables):
  (state, tables) = result
  do IO<L.Tables>:
    next : W.State & L.Tables <- result_report(id ++ "-retry", TW.travel_checked(state, tables, input, neutral(context)))
    retained(id ++ "-retry", next)

def warmed(result: W.State & Result<&2, &2, String, R.Snapshot>) -> W.State:
  (state, status) = result
  state

def shapes_show(values: List<&2, G.Collider>) -> String:
  match values:
    case Nil{}: ""
    case G.EmptyCollider{} <> rest: "empty;" ++ shapes_show(rest)
    case G.BoxCollider{box} <> rest: CW.box(box) ++ ";" ++ shapes_show(rest)

def trace_step(+id: String, registry: B.Registry, view: W.View, tables: L.Tables, initial: List<&2, G.Collider>, result: C.World & Result<&2, &2, String, List<&2, G.Collider>>) -> IO(L.Tables):
  (world, status) = result
  match status:
    case Fail{error}: IO.die(L.Tables, 4, "step trace:" ++ error)
    case Done{step}:
      do IO<L.Tables>:
        IO.print(id ++ "|colliders|" ++ shapes_show(initial) ++ "|" ++ shapes_show(step))
        checked : W.State <- state_report(id ++ "-after", W.attach(E.Engine{world, registry}, view))
        retained(id, (checked, tables))

def grounded(body: M.Body) -> Bool:
  M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below} = body
  ground

def trace_initial_status(+id: String, registry: B.Registry, +view: W.View, tables: L.Tables, prepared: V.Prepared, world: C.World, status: Result<&2, &2, String, List<&2, G.Collider>>) -> IO(L.Tables):
  match view prepared status:
    case _ _ Fail{error}: IO.die(L.Tables, 4, "initial trace:" ++ error)
    case W.View{old, yaw, pitch, Some{+colors}, region, cache} V.Prepared{+body, +delta, friction, accel, +maximum, gravity, drag, discard} Done{+initial}:
      +box = W.body_box(body)
      +baseline = M.resolve(box, grounded(body), 0.0, delta, initial, [])
      trace_step(id, registry, view, tables, initial, W.step_read(world, colors, W.resolution_query(box, delta, maximum, baseline), W.needs_step(body, maximum, delta, baseline)))
    case _ _ _: IO.die(L.Tables, 4, "trace palette unavailable")

def trace_initial(id: String, registry: B.Registry, view: W.View, tables: L.Tables, prepared: V.Prepared, result: C.World & Result<&2, &2, String, List<&2, G.Collider>>) -> IO(L.Tables):
  (world, status) = result
  trace_initial_status(id, registry, view, tables, prepared, world, status)

def trace_prepared(+id: String, tables: L.Tables, +prepared: V.Prepared, engine: E.Engine, +view: W.View) -> IO(L.Tables):
  match prepared engine view:
    case V.Prepared{+body, +delta, friction, accel, maximum, gravity, drag, discard} E.Engine{world, registry} W.View{old, yaw, pitch, Some{+colors}, region, cache}:
      trace_initial(id, registry, view, tables, prepared, W.initial_read(world, colors, body, delta, F.is_zero(M.Vec3.length_squared(delta))))
    case _ _ _: IO.die(L.Tables, 4, "trace palette unavailable")

def trace_extracted(id: String, tables: L.Tables, prepared: V.Prepared, result: E.Engine & W.View) -> IO(L.Tables):
  (engine, view) = result
  trace_prepared(id, tables, prepared, engine, view)

def prepared_value(+id: String, op: String, state: W.State, tables: L.Tables, +value: V.Prepared) -> IO(L.Tables):
  match op:
    case "prepare":
      V.Prepared{body, requested, friction, acceleration, maximum, gravity, drag, discard} = value
      do IO<L.Tables>:
        IO.print(id ++ "|prepared|" ++ LT.vector_show(requested) ++ "|" ++ U32.show(F32.bits(friction)) ++ "|" ++ U32.show(F32.bits(acceleration)))
        checked : W.State <- state_report(id ++ "-after", state)
        retained(id, (checked, tables))
    case "trace": trace_extracted(id, tables, value, W.take(state))
    case _:
      V.Prepared{body, requested, friction, acceleration, maximum, gravity, drag, discard} = value
      do IO<L.Tables>:
        moved : W.State <- CW.movement_report(id ++ "-raw", W.move(CW.replace_body(state, body), requested, maximum))
        checked : W.State <- state_report(id ++ "-after", moved)
        retained(id, (checked, tables))

def prepared_operation(+id: String, op: String, state: W.State, result: L.Tables & Result<&2, &2, V.Error, V.Prepared>) -> IO(L.Tables):
  match result:
    case (tables, Fail{error}): IO.die(L.Tables, 4, "prepared phase:" ++ VT.error_show(error))
    case (tables, Done{value}): prepared_value(id, op, state, tables, value)

def set_running(state: W.State) -> W.State:
  W.State{E.Engine{world, registry}, body, yaw, pitch, palette, region, cache} = state
  W.State{E.Engine{C.set_paused(world, False{}), registry}, body, yaw, pitch, palette, region, cache}

def retained_or_retry(op: String, id: String, input: M.Vec3, context: V.Context, result: W.State & L.Tables) -> IO(L.Tables):
  match op:
    case "retry": retry(id, input, context, result)
    case _: retained(id, result)

def finish_injected(+id: String, tables: L.Tables, result: E.Engine & W.View) -> IO(L.Tables):
  (engine, +view) = result
  W.View{+body, yaw, pitch, palette, region, cache} = view
  M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below} = body
  +changed = M.Body.new(M.Vec3.add(position, M.Vec3{F.from_f32(0.25), M.zero(), M.zero()}), width, height, velocity, ground)
  malformed = {V.Prepared{body, M.Vec3.zero(), 0.6, 0.1, 0.6, F.F64{2146959360, 0}, M.one(), False{}} : V.Prepared}
  movement = {M.Transition{changed, M.Vec3{F.from_f32(0.25), M.zero(), M.zero()}, False{}, True{}} : M.Transition}
  do IO<L.Tables>:
    next : W.State & L.Tables <- result_report(id, TW.finished(W.attach(engine, TW.with_body(view, changed)), tables, view, V.finish_checked(malformed, movement)))
    retained(id, next)

def execute_original(+id: String, op: String, tables: L.Tables, body: M.Body, original: W.State, +input: M.Vec3, +context: V.Context) -> IO(L.Tables):
  match op:
    case "prepare": prepared_operation(id, op, original, V.prepare_checked(tables, body, input, context))
    case "trace": prepared_operation(id, op, original, V.prepare_checked(tables, body, input, context))
    case "movement": prepared_operation(id, op, original, V.prepare_checked(tables, body, input, context))
    case "finish-injection": finish_injected(id, tables, W.take(original))
    case _:
      do IO<L.Tables>:
        result : W.State & L.Tables <- result_report(id, TW.travel_checked(original, tables, input, context))
        retained_or_retry(op, id, input, context, result)

def execute(+id: String, op: String, tables: L.Tables, state: W.State, input: M.Vec3, context: V.Context) -> IO(L.Tables):
  W.State{engine, +body, yaw, pitch, palette, region, cache} = state
  do IO<L.Tables>:
    original : W.State <- state_report(id ++ "-before", W.State{engine, body, yaw, pitch, palette, region, cache})
    execute_original(id, op, tables, body, original, input, context)

def parsed(id: String, op: String, tables: L.Tables, state: W.State, fields: Maybe<&2, List<&2, U32>>) -> IO(L.Tables):
  match fields:
    case Some{pxh <> pxl <> pyh <> pyl <> pzh <> pzl <> axh <> axl <> ayh <> ayl <> azh <> azl <> bxh <> bxl <> byh <> byl <> bzh <> bzl <> vxh <> vxl <> vyh <> vyl <> vzh <> vzl <> width <> height <> ground <> horizontal <> vertical <> below <> ixh <> ixl <> iyh <> iyl <> izh <> izl <> gx <> gy <> gz <> friction <> sh <> sl <> gh <> gl <> fh <> fl <> dh <> dl <> yaw <> maximum <> sprint <> no_gravity <> discard <> mode_index <> Nil{}}:
      body = {M.Body{M.Vec3{F.F64{pxh, pxl}, F.F64{pyh, pyl}, F.F64{pzh, pzl}}, G.AABB{F.F64{axh, axl}, F.F64{ayh, ayl}, F.F64{azh, azl}, F.F64{bxh, bxl}, F.F64{byh, byl}, F.F64{bzh, bzl}}, M.Vec3{F.F64{vxh, vxl}, F.F64{vyh, vyl}, F.F64{vzh, vzl}}, L.float_bits(width), L.float_bits(height), U32.is_ne(ground, 0), U32.is_ne(horizontal, 0), U32.is_ne(vertical, 0), U32.is_ne(below, 0)} : M.Body}
      input = {M.Vec3{F.F64{ixh, ixl}, F.F64{iyh, iyl}, F.F64{izh, izl}} : M.Vec3}
      context = {V.Context{V.GroundSample{V.BlockPos{gx, gy, gz}, L.float_bits(friction)}, V.Attributes{F.F64{sh, sl}, F.F64{gh, gl}, F.F64{fh, fl}, F.F64{dh, dl}}, L.float_bits(yaw), L.float_bits(maximum), U32.is_ne(sprint, 0), U32.is_ne(no_gravity, 0), U32.is_ne(discard, 0), VT.mode(mode_index)} : V.Context}
      execute(id, op, tables, CW.replace_body(state, body), input, context)
    case _: IO.die(L.Tables, 2, "invalid travel fields")

def header(fields: List<&2, String>, tables: L.Tables, state: W.State) -> IO(L.Tables):
  match fields:
    case id <> op <> rest: parsed(id, op, tables, state, LT.numbers(rest))
    case _: IO.die(L.Tables, 2, "invalid travel-world protocol")

def loaded_world_status(+fields: List<&2, String>, tables: L.Tables, state: W.State, status: Result<&2, &2, String, Unit>) -> IO(L.Tables):
  match fields status:
    case _ Fail{error}: IO.die(L.Tables, 3, "world:" ++ error)
    case id <> "running" <> rest Done{unit}: header(fields, tables, warmed(W.snapshot(set_running(state), 64, 48)))
    case id <> "unsupported" <> rest Done{unit}: header(fields, tables, CW.unsupported(warmed(W.snapshot(state, 64, 48))))
    case _ Done{unit}: header(fields, tables, warmed(W.snapshot(state, 64, 48)))

def loaded_world(fields: List<&2, String>, tables: L.Tables, result: W.State & Result<&2, &2, String, Unit>) -> IO(L.Tables):
  (state, status) = result
  loaded_world_status(fields, tables, state, status)

def load_world(fields: List<&2, String>, tables: L.Tables, engine: E.Engine) -> IO(L.Tables):
  match fields:
    case id <> "missing" <> rest: loaded_world(fields, tables, W.new(engine))
    case _: loaded_world(fields, tables, W.fixture(engine))

def run_args(args: List<String>, tables: L.Tables) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case value <> rest:
      do IO<Unit>:
        engine : E.Engine <- E.load()
        next : L.Tables <- load_world(String.split(value, '|'), tables, engine)
        run_args(rest, next)

def loaded(args: List<String>, result: Result<&2, &1, L.Error, L.Tables>) -> IO(Unit):
  match result:
    case Fail{error}: IO.die(Unit, 3, "table:" ++ LT.error_text(error))
    case Done{tables}: run_args(args, tables)

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case program <> path <> rest:
      do IO<Unit>:
        tables : Result<&2, &1, L.Error, L.Tables> <- L.Tables.load(path)
        loaded(rest, tables)
    case _: IO.die(Unit, 2, "travel-world table path required")

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), arguments)
