import Base
import ../src/fall_reset_world.bend as FR
import ../src/player_fall_history.bend as H
import ../src/local_collision_world.bend as E
import ../src/client_world.bend as W
import ../src/client_render.bend as R
import ../src/movement.bend as M
import ../src/geometry.bend as A
import ../src/f64.bend as F
import ../src/core.bend as C
import ../src/game.bend as G
import ../src/registry.bend as B
import ../src/schedule.bend as Q
import ../src/section.bend as S
import ../src/section_map.bend as SM

# Standalone owned Core fixture/report helpers, copied from frozen harness text;
# no large test module is imported and no host algorithm supplies expected rays.
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

def parse_vec3(fields: List<&2, U32>) -> Maybe<&2, M.Vec3>:
  match fields:
    case xh <> xl <> yh <> yl <> zh <> zl <> Nil{}:
      Some{M.Vec3{F.F64{xh, xl}, F.F64{yh, yl}, F.F64{zh, zl}}}
    case _: None{}

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

# Exact lossless run serialization reads and returns every owned section array.
# It compares all canonical cells and trie structure, not a probabilistic digest.
def run_show(value: U32, count: Nat) -> String:
  match count:
    case 0n: ""
    case other: U32.show(value) ++ ":" ++ Nat.show(other) ++ ","

def cells_continue(prior: U32, count: Nat, result: Array<U32> & String) -> Array<U32> & String:
  (array, text) = result
  (array, run_show(prior, count) ++ text)

def cells_choice(equal: Bool, array: Array<U32>, value: U32, prior: U32, count: Nat,
                 next: Array<U32> -> U32 -> Nat -> Array<U32> & String) -> Array<U32> & String:
  match equal:
    case True{}: next(array, value, 1n+count)
    case False{}: cells_continue(prior, count, next(array, value, 1n))

def cells_read(+prior: U32, count: Nat,
               next: Array<U32> -> U32 -> Nat -> Array<U32> & String,
               result: Array<U32> & U32) -> Array<U32> & String:
  (array, +value) = result
  cells_choice(U32.is_eq(value, prior), array, value, prior, count, next)

def cells_go(left: Nat, +index: U32, array: Array<U32>, prior: U32,
             count: Nat) -> Array<U32> & String:
  match left:
    case 0n: (array, run_show(prior, count))
    case 1n+rest:
      cells_read(prior,count, a => p => c => cells_go(rest,(index + 1 : U32),a,p,c),Array.get(U32,array,index))

def section_cells(result: Array<U32> & String) -> S.Section & String:
  (array, text) = result
  (S.Section{array}, text)

def section_snapshot(section: S.Section) -> S.Section & String:
  S.Section{array} = section
  section_cells(cells_go(4096n, 0, array, 0, 0n))

def entry_tail(+key: String, section: S.Section, text: String,
               result: List<&1,SM.Entry> & String) -> List<&1,SM.Entry> & String:
  (entries, suffix) = result
  (SM.Entry{key,section} <> entries, "[" ++ key ++ ":" ++ text ++ "]" ++ suffix)

def entry_section(+key: String, next: Unit -> List<&1,SM.Entry> & String,
                  result: S.Section & String) -> List<&1,SM.Entry> & String:
  (section, text) = result
  entry_tail(key, section, text, next(Unit{}))

def entries_snapshot(entries: List<&1,SM.Entry>) -> List<&1,SM.Entry> & String:
  match entries:
    case Nil{}: ([], "")
    case SM.Entry{key,section} <> rest:
      entry_section(key,unit => entries_snapshot(rest),section_snapshot(section))

def branch_hi(lo: SM.Sections, text: String,
               result: SM.Sections & String) -> SM.Sections & String:
  (hi, suffix) = result
  (SM.Branch{lo,hi}, "(" ++ text ++ suffix ++ ")")

def branch_lo(next: Unit -> SM.Sections & String,
              result: SM.Sections & String) -> SM.Sections & String:
  (lo,text) = result
  branch_hi(lo,text,next(Unit{}))

def bucket_snapshot(result: List<&1,SM.Entry> & String) -> SM.Sections & String:
  (entries,text) = result
  (SM.Bucket{entries},"{" ++ text ++ "}")

def sections_snapshot(sections: SM.Sections) -> SM.Sections & String:
  match sections:
    case SM.EmptySections{}: (SM.EmptySections{},".")
    case SM.Branch{lo,hi}: branch_lo(unit => sections_snapshot(hi),sections_snapshot(lo))
    case SM.Bucket{entries}: bucket_snapshot(entries_snapshot(entries))

type Header is Data:
  Header{tick:Nat,time:Nat,paused:Bool,daylight:Bool,revision:Nat,count:U32,
         pending:List<&2,Q.Pending<C.Mutation>>,events:List<&2,C.CoreEvent>}

def report_sections(+id: String, registry: B.Registry, header: Header,
                    +saved: E.Frame, result: SM.Sections & String) -> IO(W.State):
  Header{+tick,+time,+paused,+daylight,+revision,+count,+pending,+events} = header
  (sections,+serialized) = result
  do IO<W.State>:
    IO.print(id ++ "|body|" ++ body_show(E.view_body(E.frame_view(saved))))
    IO.print(id ++ "|clock|" ++ Nat.show(tick) ++ "|" ++ Nat.show(time) ++ "|" ++ flag(paused) ++ "|" ++ flag(daylight) ++ "|" ++ Nat.show(revision) ++ "|" ++ Nat.show(Q.length(C.Mutation, pending)) ++ "|" ++ Nat.show(List.length(&2, C.CoreEvent, events)) ++ "|" ++ U32.show(count))
    IO.print(id ++ "|queue|" ++ pending_show(pending) ++ "|" ++ events_show(events))
    IO.print(id ++ "|view|" ++ view(E.frame_view(saved)))
    IO.print(id ++ "|canonical|" ++ serialized)
    return W.attach(G.Engine{C.World{tick,time,paused,daylight,revision,count,sections,pending,events},registry},E.frame_view(saved))

def report_engine(+id: String, engine: G.Engine, +saved: E.Frame) -> IO(W.State):
  G.Engine{C.World{+tick, +time, +paused, +daylight, +revision, +count, sections, +pending, +events}, registry} = engine
  report_sections(id,registry,Header{tick,time,paused,daylight,revision,count,pending,events},saved,sections_snapshot(sections))

def report_taken(id: String, result: G.Engine & W.View) -> IO(W.State):
  (engine, view) = result
  report_engine(id, engine, E.Frame{view, E.Environment{E.UnresolvedEntityCollisions{}, E.UnresolvedWorldBorder{}}, [], []})

def report(id: String, world: W.State) -> IO(W.State):
  report_taken(id, W.take(world))

def mutation_done(registry: B.Registry, saved: E.Frame,
                  result: C.World & Result<&2, &2, C.Error, Unit>) -> IO(W.State):
  (world, status) = result
  match status:
    case Fail{error}: IO.die(W.State, 3, "fall-reset-world mutation:" ++ W.error_text(error))
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
    case Fail{error}: IO.die(W.State, 3, "fall-reset-world snapshot:" ++ error)
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
    case Fail{error}: IO.die(W.State, 3, "fall-reset-world edit state:" ++ error)
    case Done{value}: edit_value(W.attach(G.Engine{core, registry}, E.frame_view(saved)), x, y, z, value)

def edit_glass(x: U32, y: U32, z: U32, world: W.State) -> IO(W.State):
  W.State{G.Engine{core, registry}, body, yaw, pitch, palette, region, cache} = world
  edit_resolved(x, y, z, core, E.Frame{W.View{body, yaw, pitch, palette, region, cache}, E.Environment{E.UnresolvedEntityCollisions{}, E.UnresolvedWorldBorder{}}, [], []}, default_block(B.Registry.block(registry, "minecraft:glass")))

def edit_named(name: String, x: U32, y: U32, z: U32, world: W.State) -> IO(W.State):
  W.State{G.Engine{core, registry}, body, yaw, pitch, palette, region, cache} = world
  edit_resolved(x, y, z, core, E.Frame{W.View{body, yaw, pitch, palette, region, cache}, E.Environment{E.UnresolvedEntityCollisions{}, E.UnresolvedWorldBorder{}}, [], []}, default_block(B.Registry.block(registry, name)))

def edit_material(+kind: U32, x: U32, y: U32, z: U32, world: W.State, palette: W.Palette) -> IO(W.State):
  match kind palette:
    case 4 _: edit_glass(x, y, z, world)
    case 5 _: edit_named("minecraft:water", x, y, z, world)
    case 6 _: edit_named("minecraft:cobweb", x, y, z, world)
    case 7 _: edit_named("minecraft:sweet_berry_bush", x, y, z, world)
    case 8 _: edit_named("minecraft:ladder", x, y, z, world)
    case 9 _: edit_named("minecraft:end_portal", x, y, z, world)
    case 10 _: edit_named("minecraft:end_gateway", x, y, z, world)
    case 11 _: edit_named("minecraft:nether_portal", x, y, z, world)
    case 12 _: edit_named("minecraft:lava", x, y, z, world)
    case _ W.Palette{air, stone, dirt, planks}:
      edit_value(world, x, y, z, W.choose(U32, air, W.choose(U32, stone, W.choose(U32, dirt, planks, U32.is_eq(kind, 2)), U32.is_eq(kind, 1)), U32.is_eq(kind, 0)))

def edit_fields(fields: Maybe<&2, List<&2, U32>>, world: W.State) -> IO(W.State):
  match fields world:
    case Some{x <> y <> z <> kind <> Nil{}} W.State{engine, body, yaw, pitch, Some{+palette}, region, cache}:
      edit_material(kind, x, y, z, W.State{engine, body, yaw, pitch, Some{palette}, region, cache}, palette)
    case _ _: IO.die(W.State, 2, "invalid fall-reset-world edit")

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
    case Fail{error}: IO.die(W.State, 3, "fall-reset-world palette:" ++ E.error_text(error))
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
    case _ _: IO.die(W.State, 2, "invalid fall-reset-world scalar")


def parse_box(fields: List<&2, U32>) -> Maybe<&2, A.AABB>:
  match fields:
    case ah <> al <> bh <> bl <> ch <> cl <> dh <> dl <> eh <> el <> fh <> fl <> Nil{}:
      Some{A.AABB{F.F64{ah, al}, F.F64{bh, bl}, F.F64{ch, cl}, F.F64{dh, dl}, F.F64{eh, el}, F.F64{fh, fl}}}
    case _: None{}

def box_fields(fields: Maybe<&2, List<&2, U32>>) -> Maybe<&2, Slot<A.AABB>>:
  match fields:
    case None{}: None{}
    case Some{words}: Maybe.map(&2, A.AABB, Slot<A.AABB>, b => Slot{b, []}, parse_box(words))

def vector_fields(fields: Maybe<&2, List<&2, U32>>) -> Maybe<&2, Slot<M.Vec3>>:
  match fields:
    case None{}: None{}
    case Some{words}: Maybe.map(&2, M.Vec3, Slot<M.Vec3>, b => Slot{b, []}, parse_vec3(words))

type Policy is Data:
  Policy{work: Nat, profile: FR.Profile, noncanonical: Bool, tail: List<&2, Policy>}

def policy_fields(fields: Maybe<&2, List<&2, U32>>) -> Maybe<&2, Policy>:
  match fields:
    case Some{work <> profile <> malformed <> Nil{}}:
      Some{Policy{U32.to_nat(work), W.choose(FR.Profile, FR.DefaultClientOverworldFourState{}, FR.UnresolvedTags{}, U32.is_eq(profile, 0)), bit(malformed), []}}
    case _: None{}

def canonical_gate(malformed: Bool, +request: FR.Request) -> FR.Request:
  match malformed request:
    case False{} _: request
    case True{} FR.Request{from, to, interior, work, profile, tail}:
      FR.Request{from, to, interior, work, profile, request <> []}

def parsed_request(from: Maybe<&2, Slot<M.Vec3>>, to: Maybe<&2, Slot<M.Vec3>>,
                   interior: Maybe<&2, Slot<A.AABB>>, policy: Maybe<&2, Policy>) -> Maybe<&2, FR.Request>:
  match from to interior policy:
    case Some{from} Some{to} Some{interior} Some{Policy{work, profile, malformed, tail}}:
      Some{canonical_gate(malformed, FR.Request{slot_value(M.Vec3, from), slot_value(M.Vec3, to), slot_value(A.AABB, interior), work, profile, []})}
    case _ _ _ _: None{}

def read_phase(phase: FR.Phase) -> String:
  match phase:
    case FR.BlockSample{}: "block"
    case FR.FluidSource{}: "fluid-source"

def read_records(+id: String, values: List<&2, FR.Read>, +index: Nat) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case FR.Read{point, phase, state} <> rest:
      do IO<Unit>:
        IO.print(id ++ "|read|" ++ Nat.show(index) ++ "|" ++ read_phase(phase) ++ "|" ++ position(point) ++ "|" ++ U32.show(state))
        read_records(id, rest, 1n+index)

def observation_report(+id: String, observation: FR.Observation) -> IO(Unit):
  match observation:
    case FR.Observation{H.Miss{}, from, to, expanded_from, expanded_to, reads, Nil{}}:
      do IO<Unit>:
        IO.print(id ++ "|clip|miss")
        IO.print(id ++ "|from|" ++ vec3_show(from))
        IO.print(id ++ "|to|" ++ vec3_show(to))
        IO.print(id ++ "|expanded-from|" ++ vec3_show(expanded_from))
        IO.print(id ++ "|expanded-to|" ++ vec3_show(expanded_to))
        read_records(id, reads, 0n)
    case _: IO.die(Unit, 3, "invalid fall-reset-world observation")

def result_report(+id: String, result: W.State & Result<&2, &2, FR.Error, FR.Observation>) -> IO(W.State):
  match result:
    case (world, Fail{cause}):
      do IO<W.State>:
        IO.print(id ++ "|error|" ++ FR.error_text(cause))
        report(id ++ "-after", world)
    case (world, Done{observation}):
      do IO<W.State>:
        observation_report(id, observation)
        report(id ++ "-after", world)

def request_parsed(+id: String, world: W.State, parsed: Maybe<&2, FR.Request>) -> IO(W.State):
  match parsed:
    case None{}: IO.die(W.State, 2, "invalid fall-reset-world request")
    case Some{request}:
      do IO<W.State>:
        prior : W.State <- report(id ++ "-before", world)
        result_report(id, FR.clip_checked(prior, request))

def phase_header(header: List<&2, String>, world: W.State, from: String,
                 to: String, interior: String, policy: String) -> IO(W.State):
  match header:
    case id <> "clip" <> Nil{}:
      request_parsed(id, world, parsed_request(vector_fields(numbers(String.split(from, '|'))), vector_fields(numbers(String.split(to, '|'))), box_fields(numbers(String.split(interior, '|'))), policy_fields(numbers(String.split(policy, '|')))))
    case _: IO.die(W.State, 2, "invalid fall-reset-world header")

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
    case _: IO.die(W.State, 2, "invalid fall-reset-world command")

def dispatch(parts: List<&2, String>, world: W.State) -> IO(W.State):
  match parts:
    case header <> Nil{}: scalar_header(String.split(header, '|'), world)
    case header <> from <> to <> interior <> policy <> Nil{}:
      phase_header(String.split(header, '|'), world, from, to, interior, policy)
    case _: IO.die(W.State, 2, "invalid fall-reset-world protocol")

def run_args(args: List<String>, world: W.State) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case arg <> rest:
      do IO<Unit>:
        next : W.State <- dispatch(String.split(arg, ';'), world)
        run_args(rest, next)

def body_velocity(body: M.Body) -> M.Body:
  M.Body{position, box, old_velocity, width, height, ground, horizontal, vertical, below} = body
  M.Body{position, box, M.Vec3{F.F64{1073217536, 0}, F.F64{3218079744, 0}, F.F64{2147483648, 0}}, width, height, ground, horizontal, vertical, below}

def loaded_world(args: List<String>, result: W.State & Result<&2, &2, String, Unit>) -> IO(Unit):
  match result:
    case (world, Fail{error}): IO.die(Unit, 3, "fall-reset-world setup:" ++ error)
    case (W.State{engine, body, yaw, pitch, Some{+palette}, region, cache}, Done{unit}):
      do IO<Unit>:
        fixture : W.State <- fixture_palette(W.State{engine, body_velocity(body), 0.375, F32.neg(0.25), Some{palette}, region, cache}, palette)
        cached : W.State <- snapshot_kept(W.snapshot(fixture, 64, 48))
        run_args(args, cached)
    case (world, Done{unit}): IO.die(Unit, 3, "fall-reset-world setup missing palette")

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case program <> rest:
      do IO<Unit>:
        engine : G.Engine <- G.load()
        loaded_world(rest, W.new(engine))
    case _: IO.die(Unit, 2, "fall-reset-world arguments required")

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), arguments)

law signed_zero_endpoints_are_distinct:
  {FR.equal_endpoints(M.Vec3{F.F64{0,0},F.F64{0,0},F.F64{0,0}}, M.Vec3{F.F64{2147483648,0},F.F64{2147483648,0},F.F64{2147483648,0}}) == False{} : Bool}

def signed_zero_endpoints_are_distinct():
  {==}

law exact_axis_tie_steps_z_first:
  {FR.axes_advance(FR.Axes{FR.Axis{0,1,F.F64{1072693248,0},F.F64{0,0},[]},FR.Axis{0,1,F.F64{1072693248,0},F.F64{0,0},[]},FR.Axis{0,1,F.F64{1072693248,0},F.F64{0,0},[]},[]}) == FR.Axes{FR.Axis{0,1,F.F64{1072693248,0},F.F64{0,0},[]},FR.Axis{0,1,F.F64{1072693248,0},F.F64{0,0},[]},FR.Axis{1,1,F.F64{1072693248,0},F.F64{1072693248,0},[]},[]} : FR.Axes}

def exact_axis_tie_steps_z_first():
  {==}
