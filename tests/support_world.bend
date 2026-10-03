import ../src/schedule.bend as Q
import Base
import ../src/support_world.bend as SW
import ../src/support.bend as S
import ../src/client_world.bend as W
import ../src/player_tick_world.bend as PW
import ../src/player_tick.bend as P
import ../src/travel_world.bend as TW
import ../src/travel.bend as T
import ../src/locomotion.bend as L
import ../src/movement.bend as M
import ../src/geometry.bend as A
import ../src/f64.bend as F
import ../src/core.bend as C
import ../src/game.bend as G
import ../src/registry.bend as R
import ../src/client_render.bend as V

type Harness is Type:
  Harness{world: W.State, tables: L.Tables, player: Maybe<&2, P.State>, support: S.State, tail: List<&1, Harness>}

type Config is Data:
  Config{position: M.Vec3, velocity: M.Vec3, ground: Bool, input: P.Input,
    jumping: Bool, delay: U32, trigger: U32, sync: Bool, speed: F32, head: F32,
    attrs: T.Attributes, yaw: F32, maximum: F32, sprint: Bool, no_gravity: Bool, discard: Bool,
    strength: F.F64, input_update: Bool, jump_update: Bool, seed: S.State,
    movement: Maybe<&2, M.Vec3>, tail: List<&2, Config>}

def scalar(value: F.F64) -> String:
  F.F64{high, low} = value
  U32.show(high) ++ "|" ++ U32.show(low)

def vector(value: M.Vec3) -> String:
  M.Vec3{x, y, z} = value
  scalar(x) ++ "|" ++ scalar(y) ++ "|" ++ scalar(z)

def box(value: A.AABB) -> String:
  A.AABB{a, b, c, d, e, f} = value
  scalar(a) ++ "|" ++ scalar(b) ++ "|" ++ scalar(c) ++ "|" ++ scalar(d) ++ "|" ++ scalar(e) ++ "|" ++ scalar(f)

def flag(value: Bool) -> String:
  U32.show(Bool.to_u32(value))

def body(value: M.Body) -> String:
  M.Body{position, bounds, velocity, width, height, ground, horizontal, vertical, below} = value
  vector(position) ++ "|" ++ box(bounds) ++ "|" ++ vector(velocity) ++ "|" ++ U32.show(F32.bits(width)) ++ "|" ++ U32.show(F32.bits(height)) ++ "|" ++ flag(ground) ++ "|" ++ flag(horizontal) ++ "|" ++ flag(vertical) ++ "|" ++ flag(below)

def player(value: P.State) -> String:
  P.State{b, P.Input{x, y, z}, jumping, delay, trigger, sync, speed, head} = value
  body(b) ++ "|" ++ U32.show(F32.bits(x)) ++ "|" ++ U32.show(F32.bits(y)) ++ "|" ++ U32.show(F32.bits(z)) ++ "|" ++ flag(jumping) ++ "|" ++ U32.show(delay) ++ "|" ++ U32.show(trigger) ++ "|" ++ flag(sync) ++ "|" ++ U32.show(F32.bits(speed)) ++ "|" ++ U32.show(F32.bits(head))

def block(position: T.BlockPos) -> String:
  T.BlockPos{x, y, z} = position
  U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z)

def support(value: S.State) -> String:
  match value:
    case S.State{None{}, no_blocks}: "none|" ++ flag(no_blocks)
    case S.State{Some{position}, no_blocks}: block(position) ++ "|" ++ flag(no_blocks)

def palette(value: W.Palette) -> String:
  W.Palette{a, b, c, d} = value
  U32.show(a) ++ "," ++ U32.show(b) ++ "," ++ U32.show(c) ++ "," ++ U32.show(d)

def bounds(value: W.Bounds) -> String:
  W.Bounds{x, y, z, w, h, d} = value
  U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z) ++ "," ++ U32.show(w) ++ "," ++ U32.show(h) ++ "," ++ U32.show(d)

def raw_blocks(values: List<&2, W.RawBlock>) -> String:
  match values:
    case Nil{}: ""
    case W.RawBlock{W.Cell{x, y, z, edge}, state, material} <> rest: block(T.BlockPos{x, y, z}) ++ "," ++ U32.show(edge) ++ "," ++ U32.show(state) ++ "," ++ U32.show(material) ++ ";" ++ raw_blocks(rest)

def cache(value: Maybe<&2, W.SnapshotCache>) -> String:
  match value:
    case None{}: "none"
    case Some{W.SnapshotCache{rev, region, colors, blocks}}: Nat.show(rev) ++ "/" ++ bounds(region) ++ "/" ++ palette(colors) ++ "/" ++ raw_blocks(blocks)

def view(value: W.View) -> String:
  match value:
    case W.View{body, yaw, pitch, None{}, region, old}: U32.show(F32.bits(yaw)) ++ "|" ++ U32.show(F32.bits(pitch)) ++ "|none|" ++ bounds(region) ++ "|" ++ cache(old)
    case W.View{body, yaw, pitch, Some{colors}, region, old}: U32.show(F32.bits(yaw)) ++ "|" ++ U32.show(F32.bits(pitch)) ++ "|" ++ palette(colors) ++ "|" ++ bounds(region) ++ "|" ++ cache(old)

def world_report(+id: String, engine: G.Engine, +saved: W.View) -> IO(W.State):
  G.Engine{C.World{+tick, +time, +paused, +daylight, +revision, count, sections, +pending, +events}, registry} = engine
  do IO<W.State>:
    IO.print(id ++ "|body|" ++ body(PW.view_body(saved)))
    IO.print(id ++ "|clock|" ++ Nat.show(tick) ++ "|" ++ Nat.show(time) ++ "|" ++ flag(paused) ++ "|" ++ flag(daylight) ++ "|" ++ Nat.show(revision) ++ "|" ++ Nat.show(List.length(&2, C.CoreEvent, events)) ++ "|" ++ Nat.show(Q.length(C.Mutation, pending)))
    IO.print(id ++ "|view|" ++ view(saved))
    return W.attach(G.Engine{C.World{tick, time, paused, daylight, revision, count, sections, pending, events}, registry}, saved)

def report_extracted(id: String, result: G.Engine & W.View) -> IO(W.State):
  (engine, saved) = result
  world_report(id, engine, saved)

def report(id: String, world: W.State) -> IO(W.State):
  report_extracted(id, W.take(world))

def install_body(world: W.State, body: M.Body) -> W.State:
  W.paired(G.Engine, W.View, W.State, W.take(world), engine => saved => W.attach(engine, TW.with_body(saved, body)))

def config_body(config: Config) -> M.Body:
  Config{position, velocity, ground, input, jumping, delay, trigger, sync, speed, head, attrs, yaw, maximum, sprint, no_gravity, discard, strength, input_update, jump_update, seed, movement, tail} = config
  M.Body.new(position, 0.6, 1.8, velocity, ground)

def config_seed(config: Config) -> S.State:
  Config{position, velocity, ground, input, jumping, delay, trigger, sync, speed, head, attrs, yaw, maximum, sprint, no_gravity, discard, strength, input_update, jump_update, seed, movement, tail} = config
  seed

def config_movement(config: Config) -> Maybe<&2, M.Vec3>:
  Config{position, velocity, ground, input, jumping, delay, trigger, sync, speed, head, attrs, yaw, maximum, sprint, no_gravity, discard, strength, input_update, jump_update, seed, movement, tail} = config
  movement

def initial_player(+config: Config) -> P.State:
  Config{position, velocity, ground, input, jumping, delay, trigger, sync, speed, head, attrs, yaw, maximum, sprint, no_gravity, discard, strength, input_update, jump_update, seed, movement, tail} = config
  P.State{config_body(config), input, jumping, delay, trigger, sync, speed, head}

def controlled(previous: P.State, config: Config) -> P.State:
  match previous config:
    case P.State{body, old_input, old_jump, delay, trigger, sync, speed, head} Config{position, velocity, ground, input, jumping, d, t, s, a, h, attrs, yaw, maximum, sprint, no_gravity, discard, strength, input_update, jump_update, seed, movement, tail}:
      P.State{body, W.choose(P.Input, input, old_input, input_update), W.choose(Bool, jumping, old_jump, jump_update), delay, trigger, sync, speed, head}

def context(config: Config, sample: SW.Sample) -> P.Context:
  match config sample:
    case Config{position, velocity, ground, input, jumping, delay, trigger, sync, speed, head, attrs, yaw, maximum, sprint, no_gravity, discard, strength, input_update, jump_update, seed, movement, tail} SW.Sample{below, factor}:
      P.Context{T.Context{below, attrs, yaw, maximum, sprint, no_gravity, discard, T.NeutralDryAir{}}, strength, factor, True{}, P.Neutral{}}

def sample_report(+id: String, result: W.State & Result<&2, &2, SW.Error, SW.Sample>) -> IO(W.State):
  (world, status) = result
  match status:
    case Fail{error}:
      do IO<W.State>:
        IO.print(id ++ "|sample-error|" ++ SW.error_text(error))
        return world
    case Done{SW.Sample{T.GroundSample{position, friction}, factor}}:
      do IO<W.State>:
        IO.print(id ++ "|sample|" ++ block(position) ++ "|" ++ U32.show(F32.bits(friction)) ++ "|" ++ U32.show(F32.bits(factor)))
        return world


def raw_finished(+id: String, tables: L.Tables, prior_player: Maybe<&2, P.State>, +old_support: S.State, result: W.State & Result<&2, &2, SW.Error, S.State>) -> IO(Harness):
  (world, status) = result
  match status:
    case Fail{error}:
      do IO<Harness>:
        IO.print(id ++ "|error|" ++ SW.error_text(error))
        IO.print(id ++ "|support|" ++ support(old_support))
        kept : W.State <- report(id ++ "-after", world)
        return Harness{kept, tables, prior_player, old_support, []}
    case Done{+updated}:
      do IO<Harness>:
        IO.print(id ++ "|support|" ++ support(updated))
        sampled : W.State <- sample_report(id, SW.sample_checked(world, updated))
        kept : W.State <- report(id ++ "-after", sampled)
        return Harness{kept, tables, prior_player, updated, []}


# Parser and execution are appended below; each native call retains the same
# affine world/tables and the preceding immutable support/player state.

def cubes(values: List<&2, S.Candidate>) -> String:
  match values:
    case Nil{}: ""
    case S.FullCube{position} <> rest: block(position) ++ ";" ++ cubes(rest)

def trace_read(+id: String, +which: String, registry: R.Registry, saved: W.View, +query: A.AABB, result: C.World & Result<&2, &2, SW.Error, List<&2, S.Candidate>>) -> IO(W.State):
  (world, status) = result
  match status:
    case Fail{error}:
      do IO<W.State>:
        IO.print(id ++ "|" ++ which ++ "-error|" ++ SW.error_text(error))
        return W.attach(G.Engine{world, registry}, saved)
    case Done{items}:
      do IO<W.State>:
        IO.print(id ++ "|" ++ which ++ "|" ++ box(query) ++ "|" ++ cubes(items))
        return W.attach(G.Engine{world, registry}, saved)

def trace_extract(id: String, which: String, +query: A.AABB, result: G.Engine & W.View) -> IO(W.State):
  match result:
    case (G.Engine{world, registry}, +saved):
      match saved:
        case W.View{body, yaw, pitch, Some{colors}, region, cache}: trace_read(id, which, registry, saved, query, SW.collect(world, colors, query))
        case _: IO.pure(W.State, W.attach(G.Engine{world, registry}, saved))

def trace_one(id: String, which: String, world: W.State, query: A.AABB) -> IO(W.State):
  trace_extract(id, which, query, W.take(world))

def traced_fallback(id: String, world: W.State, fallback: Maybe<&2, A.AABB>) -> IO(W.State):
  match fallback:
    case None{}: IO.pure(W.State, world)
    case Some{query}: trace_one(id, "fallback", world, query)

def traced_queries(+id: String, world: W.State, result: Result<&2, &2, S.Error, S.Queries>) -> IO(W.State):
  match result:
    case Fail{error}: IO.pure(W.State, world)
    case Done{S.Queries{primary, fallback}}:
      do IO<W.State>:
        first : W.State <- trace_one(id, "primary", world, primary)
        traced_fallback(id, first, fallback)

def trace_world(id: String, world: W.State, movement: Maybe<&2, M.Vec3>) -> IO(W.State):
  W.paired(W.State, M.Body, IO(W.State), W.body(world), next => body => traced_queries(id, next, S.queries_checked(W.body_box(body), movement)))

def raw_call(+id: String, harness: Harness, +config: Config) -> IO(Harness):
  Harness{world, tables, previous, +old_support, tail} = harness
  +movement = config_movement(config)
  do IO<Harness>:
    before : W.State <- report(id ++ "-before", world)
    traced : W.State <- trace_world(id, before, movement)
    raw_finished(id, tables, previous, old_support, SW.update_with_movement_checked(traced, old_support, movement))

def after_tick_support(+id: String, tables: L.Tables, +state: P.State, +old_support: S.State, result: W.State & Result<&2, &2, SW.Error, S.State>) -> IO(Harness):
  (world, status) = result
  match status:
    case Fail{error}: IO.die(Harness, 4, "tick support:" ++ SW.error_text(error))
    case Done{+updated}:
      do IO<Harness>:
        IO.print(id ++ "|state|" ++ player(state))
        IO.print(id ++ "|support|" ++ support(updated))
        sampled : W.State <- sample_report(id ++ "-post", SW.sample_checked(world, updated))
        kept : W.State <- report(id ++ "-after", sampled)
        return Harness{kept, tables, Some{state}, updated, []}

def tick_support(+id: String, tables: L.Tables, state: P.State, +old_support: S.State, +movement: M.Transition, result: W.State) -> IO(Harness):
  M.Transition{body, +delta, stepped, changed} = movement
  do IO<Harness>:
    IO.print(id ++ "|transition|" ++ vector(delta) ++ "|" ++ flag(stepped) ++ "|" ++ flag(changed))
    traced : W.State <- trace_world(id, result, Some{delta})
    after_tick_support(id, tables, state, old_support, SW.update_checked(traced, old_support, movement))

def tick_result(+id: String, old_support: S.State, result: W.State & L.Tables & P.State & Result<&2, &2, PW.Error, P.Transition>) -> IO(Harness):
  (world, tables, state, status) = result
  match status:
    case Fail{error}: IO.die(Harness, 4, "unexpected PW rejection")
    case Done{P.Transition{next, movement, attempted, jumped}}: tick_support(id, tables, state, old_support, movement, world)

def tick_sampled(+id: String, tables: L.Tables, +state: P.State, old_support: S.State, config: Config, result: W.State & Result<&2, &2, SW.Error, SW.Sample>) -> IO(Harness):
  (world, status) = result
  match status:
    case Fail{error}: IO.die(Harness, 4, "tick sample:" ++ SW.error_text(error))
    case Done{+sample}:
      SW.Sample{T.GroundSample{position, friction}, factor} = sample
      do IO<Harness>:
        IO.print(id ++ "|sample|" ++ block(position) ++ "|" ++ U32.show(F32.bits(friction)) ++ "|" ++ U32.show(F32.bits(factor)))
        IO.print(id ++ "-before|state|" ++ player(state))
        kept : W.State <- report(id ++ "-before", world)
        tick_result(id, old_support, PW.tick_checked(kept, tables, state, context(config, sample)))

def tick_call(id: String, harness: Harness, +config: Config) -> IO(Harness):
  Harness{world, tables, previous, +old_support, tail} = harness
  match previous:
    case None{}: IO.die(Harness, 2, "absent player chain")
    case Some{old}: tick_sampled(id, tables, controlled(old, config), old_support, config, SW.sample_checked(world, old_support))

def initial_choice(id: String, op: String, next: Harness, config: Config) -> IO(Harness):
  match op:
    case "raw-start": raw_call(id, next, config)
    case _: tick_call(id, next, config)

def initial(id: String, op: String, harness: Harness, +config: Config) -> IO(Harness):
  Harness{world, tables, previous, old_support, tail} = harness
  +state = initial_player(config)
  initial_choice(id, op, Harness{install_body(world, PW.player_body(state)), tables, Some{state}, config_seed(config), []}, config)

def raw_install(id: String, harness: Harness, +config: Config) -> IO(Harness):
  Harness{world, tables, previous, old_support, tail} = harness
  raw_call(id, Harness{install_body(world, config_body(config)), tables, previous, old_support, []}, config)

def sample_call(+id: String, harness: Harness) -> IO(Harness):
  Harness{world, tables, previous, +old_support, tail} = harness
  do IO<Harness>:
    before : W.State <- report(id ++ "-before", world)
    after : W.State <- sample_report(id, SW.sample_checked(before, old_support))
    kept : W.State <- report(id ++ "-after", after)
    return Harness{kept, tables, previous, old_support, []}

def number_gate(value: Maybe<&2, U32>, rest: Maybe<&2, List<&2, U32>>) -> Maybe<&2, List<&2, U32>>:
  match value rest:
    case Some{value} Some{rest}: Some{value <> rest}
    case _ _: None{}

def numbers(fields: List<&2, String>) -> Maybe<&2, List<&2, U32>>:
  match fields:
    case Nil{}: Some{[]}
    case field <> rest: number_gate(U32.read(field), numbers(rest))

def execute(id: String, op: String, harness: Harness, +config: Config) -> IO(Harness):
  match op:
    case "start": initial(id, op, harness, config)
    case "raw-start": initial(id, op, harness, config)
    case "raw": raw_install(id, harness, config)
    case "sample-position":
      Harness{world, tables, previous, old_support, tail} = harness
      sample_call(id, Harness{install_body(world, config_body(config)), tables, previous, config_seed(config), []})
    case _: tick_call(id, harness, config)

def parsed(id: String, +op: String, harness: Harness, fields: Maybe<&2, List<&2, U32>>) -> IO(Harness):
  match fields:
    case Some{pxh <> pxl <> pyh <> pyl <> pzh <> pzl <> vxh <> vxl <> vyh <> vyl <> vzh <> vzl <> ground <> ix <> iy <> iz <> jumping <> delay <> trigger <> sync <> speed <> head <> sh <> sl <> gh <> gl <> fh <> fl <> dh <> dl <> yaw <> maximum <> sprint <> no_gravity <> discard <> jh <> jl <> input_update <> jump_update <> has_main <> mx <> my <> mz <> no_blocks <> has_movement <> dxh <> dxl <> dyh <> dyl <> dzh <> dzl <> Nil{}}:
      +config = {Config{M.Vec3{F.F64{pxh, pxl}, F.F64{pyh, pyl}, F.F64{pzh, pzl}}, M.Vec3{F.F64{vxh, vxl}, F.F64{vyh, vyl}, F.F64{vzh, vzl}}, U32.is_ne(ground, 0), P.Input{L.float_bits(ix), L.float_bits(iy), L.float_bits(iz)}, U32.is_ne(jumping, 0), delay, trigger, U32.is_ne(sync, 0), L.float_bits(speed), L.float_bits(head), T.Attributes{F.F64{sh, sl}, F.F64{gh, gl}, F.F64{fh, fl}, F.F64{dh, dl}}, L.float_bits(yaw), L.float_bits(maximum), U32.is_ne(sprint, 0), U32.is_ne(no_gravity, 0), U32.is_ne(discard, 0), F.F64{jh, jl}, U32.is_ne(input_update, 0), U32.is_ne(jump_update, 0), S.State{W.choose(Maybe<&2, T.BlockPos>, Some{T.BlockPos{mx, my, mz}}, None{}, U32.is_ne(has_main, 0)), U32.is_ne(no_blocks, 0)}, W.choose(Maybe<&2, M.Vec3>, Some{M.Vec3{F.F64{dxh, dxl}, F.F64{dyh, dyl}, F.F64{dzh, dzl}}}, None{}, U32.is_ne(has_movement, 0)), []} : Config}
      execute(id, op, harness, config)
    case _: IO.die(Harness, 2, "invalid support-world numeric fields")


def edited(id: String, registry: R.Registry, saved: W.View, tables: L.Tables, previous: Maybe<&2, P.State>, old_support: S.State, result: C.World & Result<&2, &2, C.Error, Unit>) -> IO(Harness):
  (world, status) = result
  match status:
    case Fail{error}: IO.die(Harness, 3, "edit:" ++ W.error_text(error))
    case Done{unit}:
      do IO<Harness>:
        next : W.State <- report(id, W.attach(G.Engine{C.step(world), registry}, saved))
        return Harness{next, tables, previous, old_support, []}

def queue_edit(id: String, x: U32, y: U32, z: U32, value: U32, harness: Harness) -> IO(Harness):
  Harness{world, tables, previous, old_support, tail} = harness
  W.State{G.Engine{core, registry}, body, yaw, pitch, palette, region, cache} = world
  C.World{+tick, time, paused, daylight, revision, count, sections, pending, events} = core
  edited(id, registry, W.View{body, yaw, pitch, palette, region, cache}, tables, previous, old_support, C.admit(C.World{tick, time, paused, daylight, revision, count, sections, pending, events}, C.Developer{}, Q.Stamp{1n+tick, 1, 0n}, C.BlockSet{C.Position{"minecraft:overworld", x, y, z}, value}))

def default_block(result: R.Registry & Result<&2, &2, R.Error, R.Block>) -> R.Registry & U32:
  (registry, status) = result
  match status:
    case Fail{error}: (registry, 4294967295)
    case Done{R.Block{protocol, name, first, count, default_id, properties}}: (registry, default_id)

def glass_edit(id: String, x: U32, y: U32, z: U32, harness: Harness) -> IO(Harness):
  Harness{world, tables, previous, old_support, tail} = harness
  W.State{G.Engine{core, registry}, body, yaw, pitch, palette, region, cache} = world
  W.paired(R.Registry, U32, IO(Harness), default_block(R.Registry.block(registry, "minecraft:glass")), owner => value => queue_edit(id, x, y, z, value, Harness{W.State{G.Engine{core, owner}, body, yaw, pitch, palette, region, cache}, tables, previous, old_support, tail}))

def edit_chosen(id: String, x: U32, y: U32, z: U32, kind: U32, harness: Harness, palette: W.Palette) -> IO(Harness):
  match kind palette:
    case 4 _: glass_edit(id, x, y, z, harness)
    case +kind W.Palette{air, stone, dirt, planks}: queue_edit(id, x, y, z, W.choose(U32, air, W.choose(U32, stone, W.choose(U32, dirt, planks, U32.is_eq(kind, 2)), U32.is_eq(kind, 1)), U32.is_eq(kind, 0)), harness)

def edit_palette(id: String, fields: List<&2, U32>, harness: Harness, palette: W.Palette) -> IO(Harness):
  match fields:
    case x <> y <> z <> kind <> Nil{}: edit_chosen(id, x, y, z, kind, harness, palette)
    case _: IO.die(Harness, 2, "invalid edit fields")

def edit(id: String, fields: Maybe<&2, List<&2, U32>>, harness: Harness) -> IO(Harness):
  match fields harness:
    case Some{fields} Harness{W.State{engine, body, yaw, pitch, Some{+palette}, region, cache}, tables, previous, old_support, tail}: edit_palette(id, fields, Harness{W.State{engine, body, yaw, pitch, Some{palette}, region, cache}, tables, previous, old_support, tail}, palette)
    case _ _: IO.die(Harness, 2, "edit needs palette")

def rejected_result(+id: String, tables: L.Tables, previous: Maybe<&2, P.State>, result: W.State & S.State & Result<&2, &2, SW.Error, Unit>) -> IO(Harness):
  (world, +old_support, status) = result
  match status:
    case Done{unit}: IO.die(Harness, 4, "mismatch was admitted")
    case Fail{error}:
      do IO<Harness>:
        IO.print(id ++ "|error|" ++ SW.error_text(error))
        IO.print(id ++ "|support|" ++ support(old_support))
        kept : W.State <- report(id ++ "-after", world)
        return Harness{kept, tables, previous, old_support, []}

def rejected_call(+id: String, harness: Harness) -> IO(Harness):
  Harness{world, tables, previous, old_support, tail} = harness
  do IO<Harness>:
    before : W.State <- report(id ++ "-before", world)
    rejected_result(id, tables, previous, SW.update_retained_checked(before, old_support, M.Transition{M.Body.new(M.Vec3.zero(), 1.0, 1.0, M.Vec3.zero(), False{}), M.Vec3.zero(), False{}, False{}}))

def raw_edit_done(id: String, registry: R.Registry, saved: W.View, tables: L.Tables, previous: Maybe<&2, P.State>, old_support: S.State, result: C.World & Result<&2, &2, C.Error, Unit>) -> IO(Harness):
  (world, status) = result
  match status:
    case Fail{error}: IO.die(Harness, 3, "raw edit:" ++ W.error_text(error))
    case Done{unit}:
      do IO<Harness>:
        next : W.State <- report(id, W.attach(G.Engine{world, registry}, saved))
        return Harness{next, tables, previous, old_support, []}

def raw_edit(id: String, fields: Maybe<&2, List<&2, U32>>, harness: Harness) -> IO(Harness):
  match fields harness:
    case Some{x <> y <> z <> +kind <> Nil{}} Harness{W.State{G.Engine{core, registry}, body, yaw, pitch, Some{+colors}, region, cache}, tables, previous, old_support, tail}:
      W.Palette{air, stone, dirt, planks} = colors
      raw_edit_done(id, registry, W.View{body, yaw, pitch, Some{colors}, region, cache}, tables, previous, old_support, C.write_block(core, C.Position{"minecraft:overworld", x, y, z}, W.choose(U32, air, W.choose(U32, stone, W.choose(U32, dirt, planks, U32.is_eq(kind, 2)), U32.is_eq(kind, 1)), U32.is_eq(kind, 0))))
    case _ _: IO.die(Harness, 2, "raw edit requires palette")


def special_selected(+id: String, op: String, core: C.World, registry: R.Registry, saved: W.View, tables: L.Tables, previous: Maybe<&2, P.State>, old_support: S.State) -> IO(Harness):
  match op saved:
    case "no-palette" W.View{body, yaw, pitch, palette, region, cache}: sample_call(id, Harness{W.attach(G.Engine{core, registry}, W.View{body, yaw, pitch, None{}, region, cache}), tables, previous, old_support, []})
    case "running" _:
      do IO<Harness>:
        next : W.State <- report(id, W.attach(G.Engine{C.set_paused(core, False{}), registry}, saved))
        return Harness{next, tables, previous, old_support, []}
    case _ _: IO.die(Harness, 2, "unknown special operation")

def special(id: String, op: String, harness: Harness) -> IO(Harness):
  Harness{W.State{G.Engine{core, registry}, body, yaw, pitch, palette, region, cache}, tables, previous, old_support, tail} = harness
  special_selected(id, op, core, registry, W.View{body, yaw, pitch, palette, region, cache}, tables, previous, old_support)


def dispatch(fields: List<&2, String>, harness: Harness) -> IO(Harness):
  match fields:
    case id <> "raw-edit" <> rest: raw_edit(id, numbers(rest), harness)
    case id <> "running" <> rest: special(id, "running", harness)
    case id <> "no-palette" <> rest: special(id, "no-palette", harness)
    case id <> "edit" <> rest: edit(id, numbers(rest), harness)
    case id <> "mismatch" <> rest: rejected_call(id, harness)
    case id <> "sample" <> rest: sample_call(id, harness)
    case id <> op <> rest: parsed(id, op, harness, numbers(rest))
    case _: IO.die(Harness, 2, "invalid support-world request")

def continue_args(args: List<String>, harness: Harness) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case value <> rest:
      do IO<Unit>:
        next : Harness <- dispatch(String.split(value, '|'), harness)
        continue_args(rest, next)

def warmed(result: W.State & Result<&2, &2, String, V.Snapshot>) -> W.State:
  (world, status) = result
  world

def loaded_world(args: List<String>, tables: L.Tables, result: W.State & Result<&2, &2, String, Unit>) -> IO(Unit):
  (world, status) = result
  match status:
    case Fail{error}: IO.die(Unit, 3, "fixture:" ++ error)
    case Done{unit}: continue_args(args, Harness{warmed(W.snapshot(world, 64, 48)), tables, None{}, S.empty(), []})

def loaded_table(args: List<String>, result: Result<&2, &1, L.Error, L.Tables>) -> IO(Unit):
  match result:
    case Fail{error}: IO.die(Unit, 3, "sine table")
    case Done{tables}:
      do IO<Unit>:
        engine : G.Engine <- G.load()
        loaded_world(args, tables, W.fixture(engine))

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case program <> path <> rest:
      do IO<Unit>:
        tables : Result<&2, &1, L.Error, L.Tables> <- L.Tables.load(path)
        loaded_table(rest, tables)
    case _: IO.die(Unit, 2, "support-world table path required")

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), arguments)
