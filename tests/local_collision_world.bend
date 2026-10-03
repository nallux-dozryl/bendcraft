import Base
import ../src/local_collision_world.bend as E
import ../src/local_collision.bend as L
import ../src/client_world.bend as W
import ../src/client_render.bend as R
import ../src/movement.bend as M
import ../src/geometry.bend as A
import ../src/f64.bend as F
import ../src/player_input.bend as PI
import ../src/core.bend as C
import ../src/game.bend as G
import ../src/registry.bend as B
import ../src/schedule.bend as Q

type BackoffContext is Data:
  BackoffContext{context:L.EdgeContext,fuel:Nat}

type Slot<-T: Data> is Data:
  Slot{value: T, tail: List<&2, Slot<T>>}

def slot_value(-T: Data, slot: Slot<T>) -> T:
  Slot{value, tail} = slot
  value

def context_value(slot: Slot<BackoffContext>) -> L.EdgeContext:
  Slot{BackoffContext{context, fuel}, tail} = slot
  context

def context_fuel(slot: Slot<BackoffContext>) -> Nat:
  Slot{BackoffContext{context, fuel}, tail} = slot
  fuel

def float_bits(value:U32) -> F32:
  match value:
    case U32{word}: F32{word}

def number_gate(value: Maybe<&2, U32>, rest: Maybe<&2, List<&2, U32>>) -> Maybe<&2, List<&2, U32>>:
  match value rest:
    case Some{word} Some{words}: Some{word <> words}
    case _ _: None{}

def numbers(fields: List<&2, String>) -> Maybe<&2, List<&2, U32>>:
  match fields:
    case Nil{}: Some{Nil{}}
    case word <> rest: number_gate(U32.read(word), numbers(rest))

def bit(value: U32) -> Bool:
  U32.is_ne(value, 0)

def f64_show(value: F.F64) -> String:
  F.F64{hi, lo} = value
  U32.show(hi) ++ "|" ++ U32.show(lo)

def vec3_show(value: M.Vec3) -> String:
  M.Vec3{x, y, z} = value
  f64_show(x) ++ "|" ++ f64_show(y) ++ "|" ++ f64_show(z)

def box_show(value: A.AABB) -> String:
  A.AABB{a, b, c, d, e, f} = value
  f64_show(a) ++ "|" ++ f64_show(b) ++ "|" ++ f64_show(c) ++ "|" ++ f64_show(d) ++ "|" ++ f64_show(e) ++ "|" ++ f64_show(f)

def body_show(value: M.Body) -> String:
  M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below} = value
  vec3_show(position) ++ "|" ++ box_show(box) ++ "|" ++ vec3_show(velocity) ++ "|" ++ U32.show(F32.bits(width)) ++ "|" ++ U32.show(F32.bits(height)) ++ "|" ++
    U32.show(Bool.to_u32(ground)) ++ "|" ++ U32.show(Bool.to_u32(horizontal)) ++ "|" ++ U32.show(Bool.to_u32(vertical)) ++ "|" ++ U32.show(Bool.to_u32(below))

def parse_body(fields: List<&2, U32>) -> Maybe<&2, M.Body>:
  match fields:
    case xh <> xl <> yh <> yl <> zh <> zl <> ah <> al <> bh <> bl <> ch <> cl <> dh <> dl <> eh <> el <> fh <> fl <> vxh <> vxl <> vyh <> vyl <> vzh <> vzl <> width <> height <> ground <> horizontal <> vertical <> below <> Nil{}:
      Some{M.Body{M.Vec3{F.F64{xh, xl}, F.F64{yh, yl}, F.F64{zh, zl}},
        A.AABB{F.F64{ah, al}, F.F64{bh, bl}, F.F64{ch, cl}, F.F64{dh, dl}, F.F64{eh, el}, F.F64{fh, fl}},
        M.Vec3{F.F64{vxh, vxl}, F.F64{vyh, vyl}, F.F64{vzh, vzl}}, float_bits(width), float_bits(height), bit(ground), bit(horizontal), bit(vertical), bit(below)}}
    case _: None{}

def parse_vec3(fields: List<&2, U32>) -> Maybe<&2, M.Vec3>:
  match fields:
    case xh <> xl <> yh <> yl <> zh <> zl <> Nil{}:
      Some{M.Vec3{F.F64{xh, xl}, F.F64{yh, yl}, F.F64{zh, zl}}}
    case _: None{}

def mode(word: U32) -> L.Mode:
  match word:
    case 0: L.NeutralDry{}
    case 1: L.Flight{}
    case 2: L.Swimming{}
    case 3: L.Passenger{}
    case 4: L.NoPhysics{}
    case 5: L.NonNeutralEffects{}
    case _: L.UnsupportedWorld{}

def mover(word: U32) -> L.Mover:
  match word:
    case 0: L.Self{}
    case 1: L.Player{}
    case _: L.OtherMover{}

def parse_context(fields: List<&2, U32>) -> Maybe<&2, BackoffContext>:
  match fields:
    case maximum <> fh <> fl <> flying <> keys <> moving <> admit <> fuel <> Nil{}:
      Some{BackoffContext{L.EdgeContext{float_bits(maximum), F.F64{fh, fl}, bit(flying), PI.from_mask(keys), mover(moving), mode(admit)}, U32.to_nat(fuel)}}
    case _: None{}

def optional_body(value: Maybe<&2, List<&2, U32>>) -> Maybe<&2, M.Body>:
  match value:
    case None{}: None{}
    case Some{fields}: parse_body(fields)

def optional_vector(value: Maybe<&2, List<&2, U32>>) -> Maybe<&2, M.Vec3>:
  match value:
    case None{}: None{}
    case Some{fields}: parse_vec3(fields)

def optional_context(value: Maybe<&2, List<&2, U32>>) -> Maybe<&2, BackoffContext>:
  match value:
    case None{}: None{}
    case Some{fields}: parse_context(fields)

def parse_environment(fields: List<&2, U32>) -> Maybe<&2, E.Environment>:
  match fields:
    case entities <> border <> ah <> al <> bh <> bl <> ch <> cl <> dh <> dl <> eh <> el <> fh <> fl <> Nil{}:
      Some{E.Environment{
        W.choose(E.EntityPolicy, E.KnownEmptyEntityCollisions{}, E.UnresolvedEntityCollisions{}, U32.is_eq(entities, 0)),
        W.choose(E.BorderPolicy, E.KnownClearBorderInterior{A.AABB{F.F64{ah, al}, F.F64{bh, bl}, F.F64{ch, cl}, F.F64{dh, dl}, F.F64{eh, el}, F.F64{fh, fl}}}, E.UnresolvedWorldBorder{}, U32.is_eq(border, 0))}}
    case _: None{}

def optional_environment(value: Maybe<&2, List<&2, U32>>) -> Maybe<&2, E.Environment>:
  match value:
    case None{}: None{}
    case Some{fields}: parse_environment(fields)

def parsed_request(body: Maybe<&2, Slot<M.Body>>, context: Maybe<&2, Slot<BackoffContext>>,
                   movement: Maybe<&2, Slot<M.Vec3>>, environment: Maybe<&2, Slot<E.Environment>>) -> Maybe<&2, E.Request>:
  match body context movement environment:
    case Some{body} Some{+context} Some{movement} Some{environment}:
      Some{E.Request{slot_value(M.Body, body), slot_value(M.Vec3, movement), context_value(context), slot_value(E.Environment, environment), context_fuel(context), []}}
    case _ _ _ _: None{}

def flag(value: Bool) -> String:
  U32.show(Bool.to_u32(value))

def position(value: C.Position) -> String:
  C.Position{dimension, x, y, z} = value
  U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z)

def bounds(value: W.Bounds) -> String:
  W.Bounds{x, y, z, w, h, d} = value
  U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z) ++ "," ++ U32.show(w) ++ "," ++ U32.show(h) ++ "," ++ U32.show(d)

def colors(value: W.Palette) -> String:
  W.Palette{a, b, c, d} = value
  U32.show(a) ++ "," ++ U32.show(b) ++ "," ++ U32.show(c) ++ "," ++ U32.show(d)

def raw_blocks(values: List<&2, W.RawBlock>) -> String:
  match values:
    case Nil{}: ""
    case W.RawBlock{W.Cell{x, y, z, edge}, state, material} <> rest:
      position(C.Position{"minecraft:overworld", x, y, z}) ++ "," ++ U32.show(edge) ++ "," ++ U32.show(state) ++ "," ++ U32.show(material) ++ ";" ++ raw_blocks(rest)

def cache(value: Maybe<&2, W.SnapshotCache>) -> String:
  match value:
    case None{}: "none"
    case Some{W.SnapshotCache{revision, region, palette, blocks}}:
      Nat.show(revision) ++ "/" ++ bounds(region) ++ "/" ++ colors(palette) ++ "/" ++ raw_blocks(blocks)

def view(value: W.View) -> String:
  match value:
    case W.View{body, yaw, pitch, None{}, region, cached}:
      U32.show(F32.bits(yaw)) ++ "|" ++ U32.show(F32.bits(pitch)) ++ "|none|" ++ bounds(region) ++ "|" ++ cache(cached)
    case W.View{body, yaw, pitch, Some{palette}, region, cached}:
      U32.show(F32.bits(yaw)) ++ "|" ++ U32.show(F32.bits(pitch)) ++ "|" ++ colors(palette) ++ "|" ++ bounds(region) ++ "|" ++ cache(cached)

def stamp(value: Q.Stamp) -> String:
  Q.Stamp{tick, peer, sequence} = value
  Nat.show(tick) ++ "," ++ U32.show(peer) ++ "," ++ Nat.show(sequence)

def mutation(value: C.Mutation) -> String:
  match value:
    case C.SectionCreate{point, fill}: "section," ++ position(point) ++ "," ++ U32.show(fill)
    case C.BlockSet{point, state}: "block," ++ position(point) ++ "," ++ U32.show(state)
    case C.TimeSet{time}: "time," ++ Nat.show(time)
    case C.DaylightSet{enabled}: "daylight," ++ flag(enabled)

def pending_show(values: List<&2, Q.Pending<C.Mutation>>) -> String:
  match values:
    case Nil{}: ""
    case Q.Pending{when, operation} <> rest: stamp(when) ++ "," ++ mutation(operation) ++ ";" ++ pending_show(rest)

def events_show(values: List<&2, C.CoreEvent>) -> String:
  match values:
    case Nil{}: ""
    case C.Applied{when, revision} <> rest: "applied," ++ stamp(when) ++ "," ++ Nat.show(revision) ++ ";" ++ events_show(rest)
    case C.Rejected{when, reason} <> rest: "rejected," ++ stamp(when) ++ "," ++ W.error_text(reason) ++ ";" ++ events_show(rest)

def report_engine(+id: String, engine: G.Engine, +saved: E.Frame) -> IO(W.State):
  G.Engine{C.World{+tick, +time, +paused, +daylight, +revision, +count, sections, +pending, +events}, registry} = engine
  do IO<W.State>:
    IO.print(id ++ "|body|" ++ body_show(E.view_body(E.frame_view(saved))))
    IO.print(id ++ "|clock|" ++ Nat.show(tick) ++ "|" ++ Nat.show(time) ++ "|" ++ flag(paused) ++ "|" ++ flag(daylight) ++ "|" ++ Nat.show(revision) ++ "|" ++ Nat.show(Q.length(C.Mutation, pending)) ++ "|" ++ Nat.show(List.length(&2, C.CoreEvent, events)) ++ "|" ++ U32.show(count))
    IO.print(id ++ "|queue|" ++ pending_show(pending) ++ "|" ++ events_show(events))
    IO.print(id ++ "|view|" ++ view(E.frame_view(saved)))
    return W.attach(G.Engine{C.World{tick, time, paused, daylight, revision, count, sections, pending, events}, registry}, E.frame_view(saved))

def report_taken(id: String, result: G.Engine & W.View) -> IO(W.State):
  (engine, view) = result
  report_engine(id, engine, E.Frame{view, E.Environment{E.UnresolvedEntityCollisions{}, E.UnresolvedWorldBorder{}}, [], []})

def report(id: String, world: W.State) -> IO(W.State):
  report_taken(id, W.take(world))

def reads(values: List<&2, E.Read>) -> String:
  match values:
    case Nil{}: ""
    case E.Read{point, state} <> rest: position(point) ++ "," ++ U32.show(state) ++ ";" ++ reads(rest)

def yielded(value: Maybe<&2, A.AABB>) -> String:
  match value:
    case None{}: "none"
    case Some{box}: box_show(box)

def query_records(+id: String, values: List<&2, E.QueryRecord>, +index: Nat) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case E.QueryRecord{box, clear, hit, observed} <> rest:
      do IO<Unit>:
        IO.print(id ++ "|query|" ++ Nat.show(index) ++ "|" ++ box_show(box) ++ "|" ++ flag(clear) ++ "|" ++ yielded(hit) ++ "|" ++ reads(observed))
        query_records(id, rest, 1n+index)

def result_report(+id: String, result: W.State & Result<&2, &2, E.Error, E.Observation>) -> IO(W.State):
  (world, status) = result
  match status:
    case Fail{error}:
      do IO<W.State>:
        IO.print(id ++ "|error|" ++ E.error_text(error))
        report(id ++ "-after", world)
    case Done{E.Observation{corrected, queries}}:
      do IO<W.State>:
        IO.print(id ++ "|corrected|" ++ vec3_show(corrected))
        query_records(id, queries, 0n)
        report(id ++ "-after", world)

def install_body(world: W.State, body: M.Body) -> W.State:
  W.State{engine, old, yaw, pitch, palette, region, cache} = world
  W.State{engine, body, yaw, pitch, palette, region, cache}

def install_gate(install: Bool, world: W.State, request: E.Request) -> W.State:
  match install:
    case False{}: world
    case True{}: install_body(world, E.request_body(request))

def backoff_parsed(+id: String, world: W.State, install: Bool, parsed: Maybe<&2, E.Request>) -> IO(W.State):
  match parsed:
    case None{}: IO.die(W.State, 2, "invalid local-collision-world request")
    case Some{+request}:
      do IO<W.State>:
        prior : W.State <- report(id ++ "-before", install_gate(install, world, request))
        result_report(id, E.backoff_checked(prior, request))

def phase_header(header: List<&2, String>, world: W.State, body: String,
                 context: String, movement: String, environment: String) -> IO(W.State):
  match header:
    case id <> "backoff" <> install <> Nil{}:
      backoff_parsed(id, world, String.eq(install, "1"), parsed_request(
        Maybe.map(&2, M.Body, Slot<M.Body>, value => Slot{value, []}, optional_body(numbers(String.split(body, '|')))),
        Maybe.map(&2, BackoffContext, Slot<BackoffContext>, value => Slot{value, []}, optional_context(numbers(String.split(context, '|')))),
        Maybe.map(&2, M.Vec3, Slot<M.Vec3>, value => Slot{value, []}, optional_vector(numbers(String.split(movement, '|')))),
        Maybe.map(&2, E.Environment, Slot<E.Environment>, value => Slot{value, []}, optional_environment(numbers(String.split(environment, '|'))))))
    case _: IO.die(W.State, 2, "invalid local-collision-world header")

def mutation_done(registry: B.Registry, saved: E.Frame,
                  result: C.World & Result<&2, &2, C.Error, Unit>) -> IO(W.State):
  (world, status) = result
  match status:
    case Fail{error}: IO.die(W.State, 3, "local-collision-world mutation:" ++ W.error_text(error))
    case Done{unit}: IO.pure(W.State, W.attach(G.Engine{world, registry}, E.frame_view(saved)))

def mutate_world(world: W.State, mutation: C.Mutation) -> IO(W.State):
  W.State{G.Engine{core, registry}, body, yaw, pitch, palette, region, cache} = world
  mutation_done(registry, E.Frame{W.View{body, yaw, pitch, palette, region, cache}, E.Environment{E.UnresolvedEntityCollisions{}, E.UnresolvedWorldBorder{}}, [], []}, C.apply(core, mutation))

def section_setup(n: Nat, +index: U32, +air: U32, world: W.State) -> IO(W.State):
  match n:
    case 0n: IO.pure(W.State, world)
    case 1n+rest:
      x = W.choose(U32, 0, 4294967280, U32.is_eq(U32.and(index, 1), 0))
      y = W.choose(U32, 0, 4294967280, U32.is_eq(U32.and(index, 2), 0))
      z = W.choose(U32, 0, 4294967280, U32.is_eq(U32.and(index, 4), 0))
      do IO<W.State>:
        next : W.State <- mutate_world(world, C.SectionCreate{C.Position{"minecraft:overworld", x, y, z}, air})
        section_setup(rest, U32.inc(index), air, next)

def floor_setup(n: Nat, +index: U32, +stone: U32, world: W.State) -> IO(W.State):
  match n:
    case 0n: IO.pure(W.State, world)
    case 1n+rest:
      x = U32.add(4294967294, U32.mod(index, 5))
      z = U32.add(4294967294, U32.div(index, 5))
      do IO<W.State>:
        next : W.State <- mutate_world(world, C.BlockSet{C.Position{"minecraft:overworld", x, 0, z}, stone})
        floor_setup(rest, U32.inc(index), stone, next)

def fixture_palette(world: W.State, palette: W.Palette) -> IO(W.State):
  W.Palette{air, stone, dirt, planks} = palette
  do IO<W.State>:
    sections : W.State <- section_setup(8n, 0, air, world)
    floor_setup(25n, 0, stone, sections)

def snapshot_kept(result: W.State & Result<&2, &2, String, R.Snapshot>) -> IO(W.State):
  (world, status) = result
  match status:
    case Fail{error}: IO.die(W.State, 3, "local-collision-world snapshot:" ++ error)
    case Done{snapshot}: IO.pure(W.State, world)

def default_block(result: B.Registry & Result<&2, &2, B.Error, B.Block>) -> B.Registry & Result<&2, &2, String, U32>:
  (registry, status) = result
  match status:
    case Fail{error}: (registry, Fail{B.error_text(error)})
    case Done{B.Block{protocol, name, first, count, default_id, properties}}: (registry, Done{default_id})

def edit_value(world: W.State, x: U32, y: U32, z: U32, value: U32) -> IO(W.State):
  mutate_world(world, C.BlockSet{C.Position{"minecraft:overworld", x, y, z}, value})

def edit_resolved(x: U32, y: U32, z: U32, core: C.World, saved: E.Frame,
                  result: B.Registry & Result<&2, &2, String, U32>) -> IO(W.State):
  (registry, status) = result
  match status:
    case Fail{error}: IO.die(W.State, 3, "local-collision-world edit state:" ++ error)
    case Done{value}: edit_value(W.attach(G.Engine{core, registry}, E.frame_view(saved)), x, y, z, value)

def edit_glass(x: U32, y: U32, z: U32, world: W.State) -> IO(W.State):
  W.State{G.Engine{core, registry}, body, yaw, pitch, palette, region, cache} = world
  edit_resolved(x, y, z, core, E.Frame{W.View{body, yaw, pitch, palette, region, cache}, E.Environment{E.UnresolvedEntityCollisions{}, E.UnresolvedWorldBorder{}}, [], []}, default_block(B.Registry.block(registry, "minecraft:glass")))

def edit_material(+kind: U32, x: U32, y: U32, z: U32, world: W.State, palette: W.Palette) -> IO(W.State):
  match kind palette:
    case 4 _: edit_glass(x, y, z, world)
    case _ W.Palette{air, stone, dirt, planks}:
      edit_value(world, x, y, z, W.choose(U32, air, W.choose(U32, stone, W.choose(U32, dirt, planks, U32.is_eq(kind, 2)), U32.is_eq(kind, 1)), U32.is_eq(kind, 0)))

def edit_fields(fields: Maybe<&2, List<&2, U32>>, world: W.State) -> IO(W.State):
  match fields world:
    case Some{x <> y <> z <> kind <> Nil{}} W.State{engine, body, yaw, pitch, Some{+palette}, region, cache}:
      edit_material(kind, x, y, z, W.State{engine, body, yaw, pitch, Some{palette}, region, cache}, palette)
    case _ _: IO.die(W.State, 2, "invalid local-collision-world edit")

def with_palette(view: W.View, palette: W.Palette) -> W.View:
  W.View{body, yaw, pitch, old, region, cache} = view
  W.View{body, yaw, pitch, Some{palette}, region, cache}

def held_pending(world: W.State) -> IO(W.State):
  W.State{G.Engine{core, registry}, body, yaw, pitch, palette, region, cache} = world
  mutation_done(registry, E.Frame{W.View{body, yaw, pitch, palette, region, cache}, E.Environment{E.UnresolvedEntityCollisions{}, E.UnresolvedWorldBorder{}}, [], []},
    C.admit(core, C.Developer{}, Q.Stamp{100n, 9, 0n}, C.TimeSet{999n}))

def refreshed_palette(core: C.World, saved: W.View,
                      result: B.Registry & Result<&2, &2, E.Error, W.Palette>) -> IO(W.State):
  (registry, status) = result
  match status:
    case Fail{error}: IO.die(W.State, 3, "local-collision-world palette:" ++ E.error_text(error))
    case Done{palette}: IO.pure(W.State, W.attach(G.Engine{core, registry}, with_palette(saved, palette)))

def seeded_clock(world: W.State) -> IO(W.State):
  do IO<W.State>:
    timed : W.State <- mutate_world(world, C.TimeSet{777n})
    mutate_world(timed, C.DaylightSet{False{}})

def special(op: String, world: W.State) -> IO(W.State):
  match op world:
    case "no-palette" W.State{engine, body, yaw, pitch, palette, region, cache}:
      IO.pure(W.State, W.State{engine, body, yaw, pitch, None{}, region, cache})
    case "stale-palette" W.State{engine, body, yaw, pitch, Some{W.Palette{a, b, c, d}}, region, cache}:
      IO.pure(W.State, W.State{engine, body, yaw, pitch, Some{W.Palette{a, c, b, d}}, region, cache})
    case "palette-refresh" W.State{G.Engine{core, registry}, body, yaw, pitch, palette, region, cache}:
      refreshed_palette(core, W.View{body, yaw, pitch, palette, region, cache}, E.current_palette(registry))
    case "running" W.State{G.Engine{core, registry}, body, yaw, pitch, palette, region, cache}:
      IO.pure(W.State, W.State{G.Engine{C.set_paused(core, False{}), registry}, body, yaw, pitch, palette, region, cache})
    case "clock" _: seeded_clock(world)
    case "pending" _: held_pending(world)
    case "warm" _: snapshot_kept(W.snapshot(world, 64, 48))
    case _ _: IO.die(W.State, 2, "invalid local-collision-world scalar")

def scalar_header(fields: List<&2, String>, world: W.State) -> IO(W.State):
  match fields:
    case id <> "edit" <> rest:
      do IO<W.State>:
        next : W.State <- edit_fields(numbers(rest), world)
        report(id, next)
    case id <> op <> Nil{}:
      do IO<W.State>:
        next : W.State <- special(op, world)
        report(id, next)
    case _: IO.die(W.State, 2, "invalid local-collision-world command")

def dispatch(parts: List<&2, String>, world: W.State) -> IO(W.State):
  match parts:
    case header <> Nil{}: scalar_header(String.split(header, '|'), world)
    case header <> body <> context <> movement <> environment <> Nil{}:
      phase_header(String.split(header, '|'), world, body, context, movement, environment)
    case _: IO.die(W.State, 2, "invalid local-collision-world protocol")

def run_args(args: List<String>, world: W.State) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case arg <> rest:
      do IO<Unit>:
        next : W.State <- dispatch(String.split(arg, ';'), world)
        run_args(rest, next)

def loaded_world(args: List<String>, result: W.State & Result<&2, &2, String, Unit>) -> IO(Unit):
  match result:
    case (world, Fail{error}): IO.die(Unit, 3, "local-collision-world setup:" ++ error)
    case (W.State{engine, body, yaw, pitch, Some{+palette}, region, cache}, Done{unit}):
      do IO<Unit>:
        fixture : W.State <- fixture_palette(W.State{engine, body, 0.375, F32.neg(0.25), Some{palette}, region, cache}, palette)
        cached : W.State <- snapshot_kept(W.snapshot(fixture, 64, 48))
        run_args(args, cached)
    case (world, Done{unit}): IO.die(Unit, 3, "local-collision-world setup missing palette")

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case program <> rest:
      do IO<Unit>:
        engine : G.Engine <- G.load()
        loaded_world(rest, W.new(engine))
    case _: IO.die(Unit, 2, "local-collision-world arguments required")

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), arguments)
