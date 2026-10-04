import Base
import ../src/local_move_world.bend as LM
import ../src/local_collision_world.bend as E
import ../src/local_collision.bend as LC
import ../src/client_world.bend as W
import ../src/client_render.bend as R
import ../src/support_world.bend as SW
import ../src/support.bend as SP
import ../src/travel.bend as T
import ../src/locomotion.bend as L
import ../src/movement.bend as M
import ../src/geometry.bend as A
import ../src/f64.bend as F
import ../src/player_input.bend as PI
import ../src/core.bend as C
import ../src/game.bend as G
import ../src/registry.bend as B
import ../src/schedule.bend as Q

type BackoffContext is Data:
  BackoffContext{context:LC.EdgeContext,fuel:Nat}

type Slot<-T: Data> is Data:
  Slot{value: T, tail: List<&2, Slot<T>>}

def slot_value(-T: Data, slot: Slot<T>) -> T:
  Slot{value, tail} = slot
  value

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

def mode(word: U32) -> LC.Mode:
  match word:
    case 0: LC.NeutralDry{}
    case 1: LC.Flight{}
    case 2: LC.Swimming{}
    case 3: LC.Passenger{}
    case 4: LC.NoPhysics{}
    case 5: LC.NonNeutralEffects{}
    case _: LC.UnsupportedWorld{}

def mover(word: U32) -> LC.Mover:
  match word:
    case 0: LC.Self{}
    case 1: LC.Player{}
    case _: LC.OtherMover{}

def parse_context(fields: List<&2, U32>) -> Maybe<&2, BackoffContext>:
  match fields:
    case maximum <> fh <> fl <> flying <> keys <> moving <> admit <> fuel <> Nil{}:
      Some{BackoffContext{LC.EdgeContext{float_bits(maximum), F.F64{fh, fl}, bit(flying), PI.from_mask(keys), mover(moving), mode(admit)}, U32.to_nat(fuel)}}
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

def install_body(world: W.State, body: M.Body) -> W.State:
  W.State{engine, old, yaw, pitch, palette, region, cache} = world
  W.State{engine, body, yaw, pitch, palette, region, cache}

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


type Harness is Type:
  Harness{world: W.State, tables: L.Tables, support: SP.State, minor: LM.MinorState,
          tail: List<&1, Harness>}

type Seed is Data:
  Seed{support: SP.State, minor: LM.MinorState}

def support_show(state: SP.State) -> String:
  match state:
    case SP.State{None{}, grounded}: "none|" ++ flag(grounded)
    case SP.State{Some{T.BlockPos{x, y, z}}, grounded}: U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z) ++ "|" ++ flag(grounded)

def minor_state_show(state: LM.MinorState) -> String:
  LM.MinorState{minor} = state
  flag(minor)

def edge_value(value: BackoffContext) -> LC.EdgeContext:
  BackoffContext{context, fuel} = value
  context

def parsed_context_neutral(edge: BackoffContext, yaw: U32, xx: U32, zz: U32,
                          fields: List<&2, U32>) -> Maybe<&2, Slot<LM.Context>>:
  match fields:
    case simulate <> authority <> xh <> xl <> yh <> yl <> zh <> zl <> removed <> auto <> speed <> restitution <> Nil{}:
      Some{Slot{LM.Context{edge_value(edge), LC.MinorInput{float_bits(yaw), float_bits(xx), float_bits(zz)}, bit(simulate), bit(authority), M.Vec3{F.F64{xh, xl}, F.F64{yh, yl}, F.F64{zh, zl}}, bit(removed), bit(auto), bit(speed), bit(restitution)}, []}}
    case _: None{}

def parsed_context_fields(fields: List<&2, U32>) -> Maybe<&2, Slot<LM.Context>>:
  match fields:
    case maximum <> fh <> fl <> flying <> keys <> moving <> admit <> fuel <> yaw <> xx <> zz <> rest:
      parsed_context_neutral(BackoffContext{LC.EdgeContext{float_bits(maximum), F.F64{fh, fl}, bit(flying), PI.from_mask(keys), mover(moving), mode(admit)}, U32.to_nat(fuel)}, yaw, xx, zz, rest)
    case _: None{}

def parsed_context(fields: Maybe<&2, List<&2, U32>>) -> Maybe<&2, Slot<LM.Context>>:
  match fields:
    case None{}: None{}
    case Some{words}: parsed_context_fields(words)

def parsed_fuel(fields: Maybe<&2, List<&2, U32>>) -> Nat:
  match fields:
    case Some{a <> b <> c <> d <> e <> f <> g <> value <> rest}: U32.to_nat(value)
    case _: 0n

def parsed_seed(fields: Maybe<&2, List<&2, U32>>) -> Maybe<&2, Slot<Seed>>:
  match fields:
    case Some{present <> x <> y <> z <> grounded <> minor <> Nil{}}:
      Some{Slot{Seed{SP.State{W.choose(Maybe<&2, T.BlockPos>, Some{T.BlockPos{x, y, z}}, None{}, bit(present)), bit(grounded)}, LM.MinorState{bit(minor)}}, []}}
    case _: None{}

def parsed_request(body: Maybe<&2, Slot<M.Body>>, movement: Maybe<&2, Slot<M.Vec3>>,
                   context: Maybe<&2, Slot<LM.Context>>, environment: Maybe<&2, Slot<E.Environment>>,
                   fuel: Nat) -> Maybe<&2, LM.Request>:
  match body movement context environment:
    case Some{body} Some{movement} Some{context} Some{environment}:
      Some{LM.Request{slot_value(M.Body, body), slot_value(M.Vec3, movement), slot_value(LM.Context, context), slot_value(E.Environment, environment), fuel, []}}
    case _ _ _ _: None{}

def report_harness_done(tables: L.Tables, support: SP.State, minor: LM.MinorState,
                        world: W.State) -> Harness:
  Harness{world, tables, support, minor, []}

def report_harness(+id: String, state: Harness) -> IO(Harness):
  match state:
    case Harness{world, tables, +support, +minor, tail}:
      do IO<Harness>:
        IO.print(id ++ "|support|" ++ support_show(support))
        IO.print(id ++ "|minor-state|" ++ minor_state_show(minor))
        observed : W.State <- report(id, world)
        return report_harness_done(tables, support, minor, observed)

def minor_angle(angle: Maybe<&2, LC.AngleDetails>) -> String:
  match angle:
    case None{}: "none"
    case Some{LC.AngleDetails{dot, ratio, value}}: f64_show(dot) ++ "|" ++ f64_show(ratio) ++ "|" ++ f64_show(value)

def minor_observation(value: Maybe<&2, LC.MinorObservation>) -> String:
  match value:
    case None{}: "none"
    case Some{LC.MinorObservation{minor, x, z, a, b, angle}}:
      flag(minor) ++ "|" ++ f64_show(x) ++ "|" ++ f64_show(z) ++ "|" ++ f64_show(a) ++ "|" ++ f64_show(b) ++ "|" ++ minor_angle(angle)

def outcome_report(+id: String, +outcome: LM.Outcome) -> IO(Unit):
  match outcome:
    case LM.Outcome{LM.Motion{M.Transition{body, delta, stepped, applied}, mt}, E.Observation{corrected, queries}, LM.BodySnapshot{before, bt}, minor, tail}:
      do IO<Unit>:
        IO.print(id ++ "|corrected|" ++ vec3_show(corrected))
        IO.print(id ++ "|resolved|" ++ vec3_show(delta))
        IO.print(id ++ "|transition|" ++ flag(stepped) ++ "|" ++ flag(applied))
        IO.print(id ++ "|pre-restitution|" ++ body_show(before))
        IO.print(id ++ "|minor-hook|" ++ minor_observation(minor))
        query_records(id, queries, 0n)

def table_probe_done(+id: String, world: W.State, support: SP.State, minor: LM.MinorState,
                     read: L.Tables & F32) -> IO(Harness):
  (tables, sine) = read
  do IO<Harness>:
    IO.print(id ++ "|table-owner|" ++ U32.show(F32.bits(sine)))
    return Harness{world, tables, support, minor, []}

type Audit is Data:
  Audit{request: LM.Request, support: SP.State, tail: List<&2, Audit>}

def audit_request(audit: Audit) -> LM.Request:
  Audit{request, support, tail} = audit
  request

def audit_support(audit: Audit) -> SP.State:
  Audit{request, support, tail} = audit
  support

def outcome_corrected(outcome: LM.Outcome) -> M.Vec3:
  LM.Outcome{motion, E.Observation{corrected, records}, before, minor, tail} = outcome
  corrected

def outcome_phase(outcome: LM.Outcome) -> M.Transition:
  LM.Outcome{LM.Motion{motion, mt}, backoff, before, minor, tail} = outcome
  LM.pre_transition(motion, LM.body_velocity(LM.snapshot_body(before)))

def collider_boxes(values: List<&2, A.Collider>) -> String:
  match values:
    case Nil{}: ""
    case A.BoxCollider{box} <> rest: box_show(box) ++ ";" ++ collider_boxes(rest)
    case A.EmptyCollider{} <> rest: "empty;" ++ collider_boxes(rest)

def support_position(value: Maybe<&2, T.BlockPos>) -> String:
  match value:
    case None{}: "none"
    case Some{T.BlockPos{x, y, z}}: U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z)

def trace_support_selected(+id: String, +which: String, engine: G.Engine, saved: W.View,
                           +query: A.AABB, choice: Result<&2, &2, SP.Error, Maybe<&2, T.BlockPos>>) -> IO(W.State):
  match choice:
    case Fail{error}: IO.die(W.State, 3, "local-move support audit selection")
    case Done{selected}:
      do IO<W.State>:
        IO.print(id ++ "|support-query|" ++ which ++ "|" ++ box_show(query) ++ "|" ++ support_position(selected))
        return W.attach(engine, saved)

def trace_support_read(+id: String, +which: String, registry: B.Registry, saved: W.View,
                       +query: A.AABB, +body: M.Body,
                       result: C.World & Result<&2, &2, SW.Error, List<&2, SP.Candidate>>) -> IO(W.State):
  (world, status) = result
  match status:
    case Fail{error}: IO.die(W.State, 3, "local-move support audit read:" ++ SW.error_text(error))
    case Done{candidates}:
      trace_support_selected(id, which, G.Engine{world, registry}, saved, query,
        SP.select_checked(SW.body_position(body), query, candidates))

def trace_fallback_world(+id: String, +body: M.Body, delta: M.Vec3,
                        eligible: Bool, world: W.State) -> IO(W.State):
  match eligible world:
    case False{} _: IO.pure(W.State, world)
    case True{} W.State{G.Engine{core, registry}, current, yaw, pitch, Some{+palette}, region, cache}:
      +query = SP.fallback_query(SP.primary_query(LM.body_box(body)), delta)
      trace_support_read(id, "fallback", registry, W.View{current, yaw, pitch, Some{palette}, region, cache}, query, body, SW.collect(core, palette, query))
    case _ _: IO.die(W.State, 3, "local-move support audit palette")

def trace_support_fallback(+id: String, world: W.State, +body: M.Body, +delta: M.Vec3,
                           +prior: SP.State, primary: Result<&2, &2, SP.Error, Maybe<&2, T.BlockPos>>) -> IO(W.State):
  match primary:
    case Fail{error}: IO.die(W.State, 3, "local-move primary audit selection")
    case Done{choice}: trace_fallback_world(id, body, delta, SP.needs_fallback(prior, True{}, choice, Some{delta}), world)

def trace_primary_read(+id: String, +body: M.Body, delta: M.Vec3, prior: SP.State,
                       registry: B.Registry, +saved: W.View, +query: A.AABB,
                       result: C.World & Result<&2, &2, SW.Error, List<&2, SP.Candidate>>) -> IO(W.State):
  (world, status) = result
  match status:
    case Fail{error}: IO.die(W.State, 3, "local-move primary audit read:" ++ SW.error_text(error))
    case Done{+candidates}:
      do IO<W.State>:
        kept : W.State <- trace_support_selected(id, "primary", G.Engine{world, registry}, saved, query,
          SP.select_checked(SW.body_position(body), query, candidates))
        trace_support_fallback(id, kept, body, delta, prior,
          SP.select_checked(SW.body_position(body), query, candidates))

def trace_support_gate(grounded: Bool, +id: String, world: W.State, +audit: Audit,
                       +phase: M.Transition) -> IO(W.State):
  match grounded:
    case False{}: IO.pure(W.State, world)
    case True{}:
      match world:
        case W.State{G.Engine{core, registry}, body, yaw, pitch, Some{+palette}, region, cache}:
          +pre = LM.transition_body(phase)
          +query = SP.primary_query(LM.body_box(pre))
          trace_primary_read(id, pre, LM.transition_displacement(phase), audit_support(audit), registry,
            W.View{body, yaw, pitch, Some{palette}, region, cache}, query, SW.collect(core, palette, query))
        case _: IO.die(W.State, 3, "local-move support audit palette")

def trace_support(id: String, world: W.State, audit: Audit, +phase: M.Transition) -> IO(W.State):
  trace_support_gate(SW.body_ground(LM.transition_body(phase)), id, world, audit, phase)

def trace_step_result(+id: String, registry: B.Registry, saved: W.View,
                      +query: A.AABB, result: C.World & Result<&2, &2, String, List<&2, A.Collider>>) -> IO(W.State):
  (world, status) = result
  match status:
    case Fail{error}: IO.die(W.State, 3, "local-move collision audit:" ++ error)
    case Done{colliders}:
      do IO<W.State>:
        IO.print(id ++ "|collision-query|step|" ++ box_show(query) ++ "|" ++ collider_boxes(colliders))
        return W.attach(G.Engine{world, registry}, saved)

def trace_step_gate(eligible: Bool, +id: String, registry: B.Registry, saved: W.View,
                    +palette: W.Palette, +query: A.AABB, world: C.World) -> IO(W.State):
  match eligible:
    case False{}: IO.pure(W.State, W.attach(G.Engine{world, registry}, saved))
    case True{}: trace_step_result(id, registry, saved, query, W.collect(world, palette, query))

def trace_initial_result(+id: String, registry: B.Registry, +saved: W.View,
                        +palette: W.Palette, +original: M.Body, +delta: M.Vec3,
                        +maximum: F32,
                        result: C.World & Result<&2, &2, String, List<&2, A.Collider>>) -> IO(W.State):
  (world, status) = result
  match status:
    case Fail{error}: IO.die(W.State, 3, "local-move initial audit:" ++ error)
    case Done{+colliders}:
      +baseline = M.resolve(LM.body_box(original), SW.body_ground(original), 0.0, delta, colliders, [])
      do IO<W.State>:
        IO.print(id ++ "|collision-query|initial|" ++ box_show(M.initial_block_query(LM.body_box(original), delta)) ++ "|" ++ collider_boxes(colliders))
        trace_step_gate(W.needs_step(original, maximum, delta, baseline), id, registry, saved, palette,
          W.resolution_query(LM.body_box(original), delta, maximum, baseline), world)

def trace_collision_gate(stationary: Bool, +id: String, world: W.State,
                         +audit: Audit, +outcome: LM.Outcome) -> IO(W.State):
  match stationary:
    case True{}: IO.pure(W.State, world)
    case False{}:
      match world:
        case W.State{G.Engine{core, registry}, body, yaw, pitch, Some{+palette}, region, cache}:
          +request = audit_request(audit)
          +original = LM.request_body(request)
          +delta = outcome_corrected(outcome)
          trace_initial_result(id, registry, W.View{body, yaw, pitch, Some{palette}, region, cache}, palette,
            original, delta, LM.context_maximum(LM.request_context(request)),
            W.collect(core, palette, M.initial_block_query(LM.body_box(original), delta)))
        case _: IO.die(W.State, 3, "local-move collision audit palette")

def audit_outcome(+id: String, world: W.State, tables: L.Tables, support: SP.State,
                  minor: LM.MinorState, +audit: Audit, +outcome: LM.Outcome) -> IO(Harness):
  do IO<Harness>:
    collision : W.State <- trace_collision_gate(F.is_zero(M.Vec3.length_squared(outcome_corrected(outcome))), id, world, audit, outcome)
    supporting : W.State <- trace_support(id, collision, audit, outcome_phase(outcome))
    report_harness(id ++ "-after", Harness{supporting, tables, support, minor, []})

def result_report(+id: String, audit: Audit, result: W.State & L.Tables & SP.State & LM.MinorState & Result<&2, &2, LM.Error, LM.Outcome>) -> IO(Harness):
  (world, tables, support, minor, status) = result
  match status:
    case Fail{error}:
      do IO<Harness>:
        IO.print(id ++ "|error|" ++ LM.error_text(error))
        after : Harness <- report_harness(id ++ "-after", Harness{world, tables, support, minor, []})
        return after
    case Done{+outcome}:
      do IO<Harness>:
        outcome_report(id, outcome)
        audit_outcome(id, world, tables, support, minor, audit, outcome)

def call_move(id: String, state: Harness, +request: LM.Request) -> IO(Harness):
  Harness{world, tables, +support, minor, tail} = state
  result_report(id, Audit{request, support, []}, LM.move_checked(world, tables, support, minor, request))

def seeded(state: Harness, body: M.Body, seed: Seed) -> Harness:
  Harness{world, tables, support, minor, tail} = state
  Seed{new_support, new_minor} = seed
  Harness{install_body(world, body), tables, new_support, new_minor, []}

def seed_gate(install: Bool, state: Harness, request: LM.Request, seed: Seed) -> Harness:
  match install:
    case False{}: state
    case True{}: seeded(state, LM.request_body(request), seed)

def move_parsed(+id: String, state: Harness, install: Bool,
                parsed: Maybe<&2, LM.Request>, seed: Maybe<&2, Slot<Seed>>) -> IO(Harness):
  match parsed seed:
    case Some{+request} Some{seed}:
      do IO<Harness>:
        before : Harness <- report_harness(id ++ "-before", seed_gate(install, state, request, slot_value(Seed, seed)))
        call_move(id, before, request)
    case _ _: IO.die(Harness, 2, "invalid local-move request")

def phase_header(header: List<&2, String>, state: Harness, body: String,
                 +context: String, movement: String, environment: String, seed: String) -> IO(Harness):
  match header:
    case id <> "move" <> install <> Nil{}:
      move_parsed(id, state, String.eq(install, "1"), parsed_request(
        Maybe.map(&2, M.Body, Slot<M.Body>, value => Slot{value, []}, optional_body(numbers(String.split(body, '|')))),
        Maybe.map(&2, M.Vec3, Slot<M.Vec3>, value => Slot{value, []}, optional_vector(numbers(String.split(movement, '|')))),
        parsed_context(numbers(String.split(context, '|'))),
        Maybe.map(&2, E.Environment, Slot<E.Environment>, value => Slot{value, []}, optional_environment(numbers(String.split(environment, '|')))),
        parsed_fuel(numbers(String.split(context, '|')))), parsed_seed(numbers(String.split(seed, '|'))))
    case _: IO.die(Harness, 2, "invalid local-move header")

def scalar_done(tables: L.Tables, support: SP.State, minor: LM.MinorState,
                world: W.State) -> Harness:
  Harness{world, tables, support, minor, []}

def scalar_header(fields: List<&2, String>, state: Harness) -> IO(Harness):
  match fields state:
    case id <> "edit" <> rest Harness{world, tables, support, minor, tail}:
      do IO<Harness>:
        next : W.State <- edit_fields(numbers(rest), world)
        observed : W.State <- report(id, next)
        return scalar_done(tables, support, minor, observed)
    case id <> "table-probe" <> Nil{} Harness{world, tables, support, minor, tail}:
      table_probe_done(id, world, support, minor, L.sin(tables, M.zero()))
    case id <> op <> Nil{} Harness{world, tables, support, minor, tail}:
      do IO<Harness>:
        next : W.State <- special(op, world)
        observed : W.State <- report(id, next)
        return scalar_done(tables, support, minor, observed)
    case _ _: IO.die(Harness, 2, "invalid local-move scalar")

def dispatch_parts(parts: List<&2, String>, state: Harness) -> IO(Harness):
  match parts:
    case header <> body <> context <> movement <> environment <> seed <> Nil{}:
      phase_header(String.split(header, '|'), state, body, context, movement, environment, seed)
    case header <> Nil{}: scalar_header(String.split(header, '|'), state)
    case _: IO.die(Harness, 2, "invalid local-move command")

def run_args(args: List<String>, state: Harness) -> IO(Unit):
  match args:
    case Nil{}:
      Harness{world, tables, support, minor, tail} = state
      IO.pure(Unit, Unit{})
    case arg <> rest:
      do IO<Unit>:
        next : Harness <- dispatch_parts(String.split(arg, ';'), state)
        run_args(rest, next)

def initialized(args: List<String>, tables: L.Tables, result: W.State & Result<&2, &2, String, Unit>) -> IO(Unit):
  match result:
    case (world, Fail{error}): IO.die(Unit, 3, "local-move fixture:" ++ error)
    case (W.State{engine, body, yaw, pitch, Some{+palette}, region, cache}, Done{unit}):
      do IO<Unit>:
        ready : W.State <- fixture_palette(W.State{engine, body, 0.375, F32.neg(0.25), Some{palette}, region, cache}, palette)
        cached : W.State <- snapshot_kept(W.snapshot(ready, 64, 48))
        run_args(args, Harness{cached, tables, SP.State{None{}, False{}}, LM.MinorState{False{}}, []})
    case (world, Done{unit}): IO.die(Unit, 3, "local-move setup missing palette")

def loaded(args: List<String>, result: Result<&2, &1, L.Error, L.Tables>) -> IO(Unit):
  match result:
    case Fail{error}: IO.die(Unit, 3, "local-move sine table")
    case Done{tables}:
      do IO<Unit>:
        engine : G.Engine <- G.load()
        initialized(args, tables, W.new(engine))

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case path <> rest:
      do IO<Unit>:
        result : Result<&2, &1, L.Error, L.Tables> <- L.Tables.load(path)
        loaded(rest, result)
    case _: IO.die(Unit, 2, "missing local-move table path")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(List.drop(&1, String, args, 1n))
