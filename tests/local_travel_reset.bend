import Base
import ../src/local_travel_history.bend as TH
import ../src/fall_reset_world.bend as FR
import ../src/local_move_history.bend as MH
import ../src/player_fall_history.bend as H
import ../src/section.bend as S
import ../src/section_map.bend as SM
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
    case "empty-sections" W.State{G.Engine{C.World{tick,time,paused,daylight,revision,count,sections,pending,events},registry},body,yaw,pitch,palette,region,cache}:
      IO.pure(W.State,W.State{G.Engine{C.World{tick,time,paused,daylight,revision,0,SM.EmptySections{},pending,events},registry},body,yaw,pitch,palette,region,cache})
    case "repair-sections" W.State{engine,body,yaw,pitch,Some{+palette},region,cache}:
      fixture_palette(W.State{engine,body,yaw,pitch,Some{palette},region,cache},palette)
    case "running" W.State{G.Engine{core, registry}, body, yaw, pitch, palette, region, cache}:
      IO.pure(W.State, W.State{G.Engine{C.set_paused(core, False{}), registry}, body, yaw, pitch, palette, region, cache})
    case "clock" _: seeded_clock(world)
    case "pending" _: held_pending(world)
    case "warm" _: snapshot_kept(W.snapshot(world, 64, 48))
    case _ _: IO.die(W.State, 2, "invalid local-collision-world scalar")


# Immutable finite-world fixture/report helpers copied from the frozen MH harness.
# This module imports production definitions only; no test-module dependency.
type Harness is Type:
  Harness{state: MH.State, tables: L.Tables, tail: List<&1, Harness>}

type Seed is Data:
  Seed{support: SP.State, minor: LM.MinorState, history: H.History}

def support_show(state: SP.State) -> String:
  match state:
    case SP.State{None{}, grounded}: "none|" ++ flag(grounded)
    case SP.State{Some{T.BlockPos{x, y, z}}, grounded}: U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z) ++ "|" ++ flag(grounded)

def minor_state_show(state: LM.MinorState) -> String:
  LM.MinorState{minor} = state
  flag(minor)

def parsed_seed(fields: Maybe<&2, List<&2, U32>>) -> Maybe<&2, Slot<Seed>>:
  match fields:
    case Some{present <> x <> y <> z <> grounded <> minor <> hi <> lo <> Nil{}}:
      Some{Slot{Seed{SP.State{W.choose(Maybe<&2,T.BlockPos>,Some{T.BlockPos{x,y,z}},None{},bit(present)),bit(grounded)},LM.MinorState{bit(minor)},H.History{F.F64{hi,lo}}},[]}}
    case _: None{}

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

def report_tail(+id: String, tail: List<&1,MH.State>, +index: Nat) -> IO(List<&1,MH.State>):
  match tail:
    case Nil{}: IO.pure(List<&1,MH.State>, [])
    case MH.State{world,+support,+minor,H.State{+history},children} <> rest:
      do IO<List<&1,MH.State>>:
        IO.print(id ++ "-owned" ++ Nat.show(index) ++ "|support|" ++ support_show(support))
        IO.print(id ++ "-owned" ++ Nat.show(index) ++ "|minor-state|" ++ minor_state_show(minor))
        IO.print(id ++ "-owned" ++ Nat.show(index) ++ "|history|" ++ f64_show(MH.history_distance(history)))
        next : W.State <- report(id ++ "-owned" ++ Nat.show(index),world)
        remaining : List<&1,MH.State> <- report_tail(id,rest,1n+index)
        return MH.State{next,support,minor,H.State{history},children} <> remaining

def report_state(+id: String, state: MH.State) -> IO(MH.State):
  match state:
    case MH.State{world,+support,+minor,H.State{+history},tail}:
      do IO<MH.State>:
        IO.print(id ++ "|support|" ++ support_show(support))
        IO.print(id ++ "|minor-state|" ++ minor_state_show(minor))
        IO.print(id ++ "|history|" ++ f64_show(MH.history_distance(history)))
        observed : W.State <- report(id,world)
        children : List<&1,MH.State> <- report_tail(id,tail,0n)
        return MH.State{observed,support,minor,H.State{history},children}

def report_harness(+id: String, harness: Harness) -> IO(Harness):
  Harness{state,tables,tail} = harness
  do IO<Harness>:
    observed : MH.State <- report_state(id,state)
    return Harness{observed,tables,tail}

def audited_state(tables: L.Tables, support: SP.State, minor: LM.MinorState,
                  history: H.State, world: W.State) -> Harness:
  Harness{MH.State{world,support,minor,history,[]},tables,[]}

def audit_outcome(+id: String, state: MH.State, tables: L.Tables,
                  +audit: Audit, +outcome: LM.Outcome) -> IO(Harness):
  MH.State{world,support,minor,history,tail} = state
  do IO<Harness>:
    collision : W.State <- trace_collision_gate(F.is_zero(M.Vec3.length_squared(outcome_corrected(outcome))),id,world,audit,outcome)
    supporting : W.State <- trace_support(id,collision,audit,outcome_phase(outcome))
    report_harness(id ++ "-after",audited_state(tables,support,minor,history,supporting))

# Clip is reported by the command; the derived numeric callback fields above do
# not rely on an independently supplied displacement or grounded flag.
def movement_show(value: H.Movement) -> String:
  H.Movement{applied,y,squared,ground,clip} = value
  flag(applied) ++ "|" ++ f64_show(y) ++ "|" ++ f64_show(squared) ++ "|" ++ flag(ground)

def travel_mode(word: U32) -> T.Mode:
  match word:
    case 0: T.NeutralDryAir{}
    case 1: T.Liquid{}
    case 2: T.Swimming{}
    case 3: T.AbilityFlight{}
    case 4: T.Gliding{}
    case 5: T.Climbing{}
    case 6: T.PowderSnow{}
    case 7: T.MobEffects{}
    case 8: T.Passenger{}
    case 9: T.UnloadedClient{}
    case 10: T.NonNeutralBlock{}
    case 11: T.NonAuthoritative{}
    case _: T.EdgeBackoff{}

def parsed_travel(fields: Maybe<&2,List<&2,U32>>) -> Maybe<&2,Slot<T.Context>>:
  match fields:
    case Some{x <> y <> z <> friction <> sh <> sl <> gh <> gl <> mh <> ml <> dh <> dl <> yaw <> maximum <> sprint <> no_gravity <> discard <> mode <> Nil{}}:
      Some{Slot{T.Context{T.GroundSample{T.BlockPos{x,y,z},float_bits(friction)},T.Attributes{F.F64{sh,sl},F.F64{gh,gl},F.F64{mh,ml},F.F64{dh,dl}},float_bits(yaw),float_bits(maximum),bit(sprint),bit(no_gravity),bit(discard),travel_mode(mode)},[]}}
    case _: None{}

def parsed_hooks(fields: Maybe<&2,List<&2,U32>>, environment: Maybe<&2,Slot<E.Environment>>) -> Maybe<&2,Slot<TH.Hooks>>:
  match fields environment:
    case Some{keys <> xx <> zz <> flying <> admit <> simulate <> authority <> xh <> xl <> yh <> yl <> zh <> zl <> removed <> auto <> speed <> restitution <> fuel <> Nil{}} Some{environment}:
      Some{Slot{TH.Hooks{PI.from_mask(keys),PI.Vector{float_bits(xx),float_bits(zz)},bit(flying),mode(admit),bit(simulate),bit(authority),M.Vec3{F.F64{xh,xl},F.F64{yh,yl},F.F64{zh,zl}},bit(removed),bit(auto),bit(speed),bit(restitution),slot_value(E.Environment,environment),U32.to_nat(fuel),[]},[]}}
    case _ _: None{}

def parsed_travel_request(input: Maybe<&2,Slot<M.Vec3>>, context: Maybe<&2,Slot<T.Context>>,
                          hooks: Maybe<&2,Slot<TH.Hooks>>, clipping: H.Clip) -> Maybe<&2,TH.Request>:
  match input context hooks:
    case Some{input} Some{context} Some{hooks}:
      Some{TH.Request{slot_value(M.Vec3,input),slot_value(T.Context,context),slot_value(TH.Hooks,hooks),clipping,[]}}
    case _ _ _: None{}

def travel_error(error: T.Error) -> String:
  match error:
    case T.UnsupportedContext{mode}: "unsupported-context"
    case T.InvalidContext{field}: "invalid-context:" ++ U32.show(field)
    case T.InvalidAttribute{field}: "invalid-attribute:" ++ U32.show(field)
    case T.InvalidInput{field}: "invalid-input:" ++ U32.show(field)
    case T.MovementError{cause}: "invalid-body"

def history_error(error: MH.Error) -> String:
  match error:
    case MH.NonCanonicalState{}: "noncanonical-state"
    case MH.NonCanonicalRequest{field}: "noncanonical-request:" ++ U32.show(field)
    case MH.HistoryMismatch{}: "history-mismatch"
    case MH.MoveError{cause}: "move:" ++ LM.error_text(cause)
    case MH.HistoryError{H.NonFinite{field}}: "history:nonfinite:" ++ U32.show(field)
    case MH.HistoryError{H.InvalidLengthSquared{}}: "history:negative-square"
    case MH.HistoryError{H.UnsupportedMode{mode}}: "history:unsupported-mode"
    case MH.HistoryError{H.MissingClipObservation{}}: "history:missing-clip"
    case MH.HistoryError{H.UnexpectedClipObservation{}}: "history:unexpected-clip"
    case MH.HistoryError{H.UnsupportedResetHit{}}: "history:reset-hit"
    case MH.HistoryError{H.UnsupportedLanding{}}: "history:landing"
    case MH.HistoryError{H.NonFiniteResult{}}: "history:nonfinite-result"

def error_show(error: TH.Error) -> String:
  match error:
    case TH.NonCanonicalState{}: "noncanonical-state"
    case TH.NonCanonicalRequest{field}: "noncanonical-request:" ++ U32.show(field)
    case TH.PreparationError{cause}: "prepare:" ++ travel_error(cause)
    case TH.MovementError{cause}: "movement:" ++ history_error(cause)
    case TH.FinishError{cause}: "finish:" ++ travel_error(cause)

type TravelAudit is Data:
  TravelAudit{request: TH.Request, support: SP.State, history: H.History,
              tail: List<&2,TravelAudit>}

def audit_from(audit: TravelAudit, +value: T.Prepared) -> Audit:
  TravelAudit{+request,support,history,tail} = audit
  Audit{LM.Request{TH.prepared_body(value),TH.prepared_request(value),
    TH.movement_context(TH.request_context(request),history,TH.request_hooks(request)),
    TH.hooks_environment(TH.request_hooks(request)),TH.hooks_fuel(TH.request_hooks(request)),[]},support,[]}

def preparation_report(+id: String, value: T.Prepared) -> IO(Unit):
  T.Prepared{body,requested,friction,acceleration,maximum,gravity,drag,discard} = value
  do IO<Unit>:
    IO.print(id ++ "|prepared-body|" ++ body_show(body))
    IO.print(id ++ "|prepared-request|" ++ vec3_show(requested))
    IO.print(id ++ "|prepared-context|" ++ U32.show(F32.bits(friction)) ++ "|" ++ U32.show(F32.bits(acceleration)) ++ "|" ++ U32.show(F32.bits(maximum)) ++ "|" ++ f64_show(gravity) ++ "|" ++ f64_show(drag) ++ "|" ++ flag(discard))

def ray_phase(phase: FR.Phase) -> String:
  match phase:
    case FR.BlockSample{}: "block"
    case FR.FluidSource{}: "fluid-source"

def ray_reads(+id: String, values: List<&2, FR.Read>, +index: Nat) -> IO(Unit):
  match values:
    case Nil{}: IO.pure(Unit, Unit{})
    case FR.Read{point, phase, state} <> rest:
      do IO<Unit>:
        IO.print(id ++ "|ray-read|" ++ Nat.show(index) ++ "|" ++ ray_phase(phase) ++ "|" ++ position(point) ++ "|" ++ U32.show(state))
        ray_reads(id, rest, 1n+index)

def ray_report(+id: String, observation: Maybe<&2, FR.Observation>) -> IO(Unit):
  match observation:
    case None{}: IO.print(id ++ "|ray|not-required")
    case Some{FR.Observation{H.Miss{}, from, to, expanded_from, expanded_to, reads, Nil{}}}:
      do IO<Unit>:
        IO.print(id ++ "|ray|miss")
        IO.print(id ++ "|ray-from|" ++ vec3_show(from))
        IO.print(id ++ "|ray-to|" ++ vec3_show(to))
        IO.print(id ++ "|ray-expanded-from|" ++ vec3_show(expanded_from))
        IO.print(id ++ "|ray-expanded-to|" ++ vec3_show(expanded_to))
        ray_reads(id, reads, 0n)
    case _: IO.die(Unit, 3, "invalid resolved-reset observation")

def result_report(+id: String, audit: TravelAudit,
                  result: MH.State & L.Tables & Result<&2,&2,TH.ResetError,TH.ResetOutcome>) -> IO(Harness):
  (state,tables,status) = result
  match status:
    case Fail{error}:
      do IO<Harness>:
        IO.print(id ++ "|error|" ++ TH.reset_error_text(error))
        report_harness(id ++ "-after",Harness{state,tables,[]})
    case Done{TH.ResetOutcome{TH.Outcome{TH.Preparation{+value,pt},MH.Outcome{+move,+history,mt},motion,tail},ray,rt}}:
      do IO<Harness>:
        preparation_report(id,value)
        outcome_report(id,move)
        IO.print(id ++ "|move-body|" ++ body_show(LM.transition_body(MH.outcome_transition(move))))
        IO.print(id ++ "|result-history|" ++ f64_show(MH.history_distance(history)))
        IO.print(id ++ "|history-input|" ++ movement_show(MH.movement_from(MH.outcome_transition(move),H.NotRequired{})))
        ray_report(id,ray)
        audit_outcome(id,state,tables,audit_from(audit,value),move)

def as_old_request(request: TH.ResetRequest) -> TH.Request:
  TH.ResetRequest{input,context,hooks,policy,tail} = request
  TH.Request{input,context,hooks,H.NotRequired{},[]}

def call_travel(id: String, harness: Harness, +request: TH.ResetRequest) -> IO(Harness):
  match harness:
    case Harness{MH.State{world,+support,minor,H.State{+history},tail},tables,ht}:
      result_report(id,TravelAudit{as_old_request(request),support,history,[]},TH.travel_with_reset_checked(MH.State{world,support,minor,H.State{history},tail},tables,request))

def seeded(harness: Harness, body: M.Body, seed: Seed) -> Harness:
  Harness{MH.State{world,support,minor,history,tail},tables,ht} = harness
  Seed{new_support,new_minor,new_history} = seed
  Harness{MH.State{install_body(world,body),new_support,new_minor,H.State{new_history},tail},tables,ht}

def seed_gate(install: Bool, harness: Harness, body: M.Body, seed: Seed) -> Harness:
  match install:
    case False{}: harness
    case True{}: seeded(harness,body,seed)

def clip(word: String) -> H.Clip:
  match word:
    case "0": H.NotRequired{}
    case "1": H.Miss{}
    case "2": H.Hit{}
    case _: H.Unknown{}

def parsed_policy(fields: Maybe<&2,List<&2,U32>>) -> Maybe<&2,Slot<TH.ResetPolicy>>:
  match fields:
    case Some{ah <> al <> bh <> bl <> ch <> cl <> dh <> dl <> eh <> el <> fh <> fl <> work <> profile <> Nil{}}:
      Some{Slot{TH.ResetPolicy{A.AABB{F.F64{ah,al},F.F64{bh,bl},F.F64{ch,cl},F.F64{dh,dl},F.F64{eh,el},F.F64{fh,fl}},U32.to_nat(work),W.choose(FR.Profile,FR.DefaultClientOverworldFourState{},FR.UnresolvedTags{},U32.is_eq(profile,0)),[]},[]}}
    case _: None{}

def shape_request(shape: String, +request: TH.ResetRequest) -> TH.ResetRequest:
  match shape request:
    case "1" TH.ResetRequest{input,context,hooks,policy,tail}: TH.ResetRequest{input,context,hooks,policy,[request]}
    case "2" TH.ResetRequest{input,context,TH.Hooks{+keys,+axes,+flying,+mode,+simulate,+authority,+stuck,+removed,+auto,+speed,+restitution,+environment,+fuel,tail},policy,rest}:
      TH.ResetRequest{input,context,TH.Hooks{keys,axes,flying,mode,simulate,authority,stuck,removed,auto,speed,restitution,environment,fuel,[TH.Hooks{keys,axes,flying,mode,simulate,authority,stuck,removed,auto,speed,restitution,environment,fuel,[]}]},policy,[]}
    case "3" TH.ResetRequest{input,context,hooks,+policy,rest}:
      TH.ResetPolicy{interior,work,profile,tail} = policy
      TH.ResetRequest{input,context,hooks,TH.ResetPolicy{interior,work,profile,[policy]},[]}
    case _ _: request

def reset_request(request: Maybe<&2,TH.Request>, policy: Maybe<&2,Slot<TH.ResetPolicy>>) -> Maybe<&2,TH.ResetRequest>:
  match request policy:
    case Some{TH.Request{input,context,hooks,clip,tail}} Some{policy}:
      Some{TH.ResetRequest{input,context,hooks,slot_value(TH.ResetPolicy,policy),[]}}
    case _ _: None{}

def travel_parsed(+id: String, harness: Harness, install: Bool, shape: String,
                  body: Maybe<&2,Slot<M.Body>>, request: Maybe<&2,TH.ResetRequest>,
                  seed: Maybe<&2,Slot<Seed>>) -> IO(Harness):
  match body request seed:
    case Some{body} Some{request} Some{seed}:
      do IO<Harness>:
        before : Harness <- report_harness(id ++ "-before",seed_gate(install,harness,slot_value(M.Body,body),slot_value(Seed,seed)))
        call_travel(id,before,shape_request(shape,request))
    case _ _ _: IO.die(Harness,2,"invalid local-travel-reset request")

def phase_header(header: List<&2,String>, harness: Harness, body: String,
                 context: String, input: String, hooks: String, environment: String,
                 seed: String, policy: String) -> IO(Harness):
  match header:
    case id <> "reset" <> install <> shape <> Nil{}:
      travel_parsed(id,harness,String.eq(install,"1"),shape,
        Maybe.map(&2,M.Body,Slot<M.Body>,value => Slot{value,[]},optional_body(numbers(String.split(body,'|')))),
        reset_request(parsed_travel_request(
          Maybe.map(&2,M.Vec3,Slot<M.Vec3>,value => Slot{value,[]},optional_vector(numbers(String.split(input,'|')))),
          parsed_travel(numbers(String.split(context,'|'))),
          parsed_hooks(numbers(String.split(hooks,'|')),
            Maybe.map(&2,E.Environment,Slot<E.Environment>,value => Slot{value,[]},optional_environment(numbers(String.split(environment,'|'))))),H.NotRequired{}),parsed_policy(numbers(String.split(policy,'|')))),
        parsed_seed(numbers(String.split(seed,'|'))))
    case _: IO.die(Harness,2,"invalid local-travel-reset header")

def table_probe_done(+id: String, state: MH.State, tail: List<&1,Harness>,
                     read: L.Tables & F32) -> IO(Harness):
  (tables,sine) = read
  do IO<Harness>:
    IO.print(id ++ "|table-owner|" ++ U32.show(F32.bits(sine)))
    return Harness{state,tables,tail}

def nested_ready(harness: Harness, child: W.State) -> Harness:
  Harness{MH.State{world,support,minor,history,tail},tables,ht} = harness
  Harness{MH.State{world,support,minor,history,MH.State{child,SP.State{Some{T.BlockPos{3,4,5}},True{}},LM.MinorState{True{}},H.State{H.History{F.from_u32(17)}},[]} <> tail},tables,ht}

def nested_setup(harness: Harness, result: W.State & Result<&2,&2,String,Unit>) -> IO(Harness):
  match result:
    case (W.State{engine,body,yaw,pitch,Some{+palette},region,cache},Done{unit}):
      do IO<Harness>:
        ready : W.State <- fixture_palette(W.State{engine,body,0.125,0.5,Some{palette},region,cache},palette)
        clocked : W.State <- seeded_clock(ready)
        return nested_ready(harness,clocked)
    case _: IO.die(Harness,3,"nested owner fixture failed")

def nested(harness: Harness) -> IO(Harness):
  do IO<Harness>:
    engine : G.Engine <- G.load()
    nested_setup(harness,W.new(engine))

def select_child(harness: Harness) -> Harness:
  match harness:
    case Harness{MH.State{world,support,minor,history,child <> Nil{}},tables,tail}:
      Harness{child,tables,tail}
    case _: harness

# Deliberate checked-finish failure injection: exercises the same production
# rollback branch after distinct temporary View/support/minor/history values.
# This is policy evidence, never an expected actual Java travel result.
def injection_request() -> TH.Request:
  TH.Request{M.Vec3.zero(),T.Context{T.GroundSample{T.BlockPos{0,0,0},0.6},T.Attributes{F.from_f32(0.1),F.from_f32(0.08),M.one(),M.one()},0.0,0.6,False{},False{},False{},T.NeutralDryAir{}},
    TH.Hooks{PI.from_mask(32),PI.Vector{0.0,0.0},False{},LC.NeutralDry{},True{},True{},M.Vec3.zero(),False{},False{},True{},True{},E.Environment{E.KnownEmptyEntityCollisions{},E.KnownClearBorderInterior{A.AABB{F.from_i32(4294967232),F.from_i32(4294967232),F.from_i32(4294967232),F.from_u32(64),F.from_u32(64),F.from_u32(64)}}},16n,[]},H.NotRequired{},[]}

def injected_taken(+id: String, tables: L.Tables, +support: SP.State,
                   +minor: LM.MinorState, +history: H.History,
                   result: G.Engine & W.View) -> IO(Harness):
  (engine,+view) = result
  +request = injection_request()
  +body = TH.view_body(view)
  +transition : M.Transition = M.Transition{body,M.Vec3.zero(),False{},True{}}
  +move : LM.Outcome = LM.Outcome{LM.Motion{transition,[]},E.Observation{M.Vec3.zero(),[]},LM.BodySnapshot{body,[]},None{},[]}
  +value : TH.Preparation = TH.Preparation{T.Prepared{body,M.Vec3.zero(),0.6,0.1,0.6,M.zero(),M.one(),False{}},[]}
  +frame : TH.Frame = TH.Frame{view,support,minor,history,request,[]}
  +policy : TH.ResetPolicy = TH.ResetPolicy{LM.body_box(body),0n,FR.UnresolvedTags{},[]}
  result_report(id,TravelAudit{request,support,history,[]},TH.reset_finished(
    W.attach(engine,TH.with_body(view,LM.with_velocity(body,M.Vec3{M.one(),M.one(),M.one()}))),tables,
    SP.State{None{},True{}},LM.MinorState{True{}},H.State{H.History{F.from_u32(17)}},
    TH.ResetWork{TH.ResetStage{frame,policy,value,[]},move,None{},[]},Fail{T.InvalidContext{99}}))

def injected_finish(id: String, harness: Harness) -> IO(Harness):
  Harness{MH.State{world,support,minor,H.State{history},tail},tables,ht} = harness
  injected_taken(id,tables,support,minor,history,W.take(world))

def scalar_header(fields: List<&2,String>, harness: Harness) -> IO(Harness):
  match fields harness:
    case +id <> "finish-fail" <> Nil{} _:
      do IO<Harness>:
        observed : Harness <- report_harness(id ++ "-before",harness)
        injected_finish(id,observed)
    case id <> "edit" <> rest Harness{MH.State{world,support,minor,history,tail},tables,ht}:
      do IO<Harness>:
        next : W.State <- edit_fields(numbers(rest),world)
        report_harness(id,Harness{MH.State{next,support,minor,history,tail},tables,ht})
    case id <> "table-probe" <> Nil{} Harness{state,tables,tail}:
      table_probe_done(id,state,tail,L.sin(tables,M.zero()))
    case id <> "nest" <> Nil{} _:
      do IO<Harness>:
        next : Harness <- nested(harness)
        report_harness(id,next)
    case id <> "select-child" <> Nil{} _: report_harness(id,select_child(harness))
    case id <> op <> Nil{} Harness{MH.State{world,support,minor,history,tail},tables,ht}:
      do IO<Harness>:
        next : W.State <- special(op,world)
        report_harness(id,Harness{MH.State{next,support,minor,history,tail},tables,ht})
    case _ _: IO.die(Harness,2,"invalid local-travel-reset scalar")

# MH-only fixtures exercise actual resolved-motion endpoint/supplier phase;
# their observations are not relabeled as an actual whole travel call.
# MH-only fixtures exercise actual resolved-motion endpoint/supplier phase;
# their observations are not relabeled as an actual whole travel call.
def ray_result(+id: String, tables: L.Tables, support: SP.State,
               minor: LM.MinorState, history: H.State,
               result: W.State & Result<&2,&2,FR.Error,FR.Observation>) -> IO(Harness):
  (world,status) = result
  match status:
    case Fail{error}:
      do IO<Harness>:
        IO.print(id ++ "|error|reset-supplier:" ++ FR.error_text(error))
        report_harness(id ++ "-after",Harness{MH.State{world,support,minor,history,[]},tables,[]})
    case Done{observation}:
      do IO<Harness>:
        ray_report(id,Some{observation})
        report_harness(id ++ "-after",Harness{MH.State{world,support,minor,history,[]},tables,[]})

def ray_taken(+id: String, tables: L.Tables, +support: SP.State,
              +minor: LM.MinorState, +history: H.History, transition: M.Transition,
              policy: TH.ResetPolicy, result: G.Engine & W.View) -> IO(Harness):
  (engine,+view) = result
  +body = TH.view_body(view)
  +stage : TH.ResetStage = TH.ResetStage{TH.Frame{view,support,minor,history,injection_request(),[]},policy,
    TH.Preparation{T.Prepared{body,M.Vec3.zero(),0.6,0.1,0.6,M.zero(),M.one(),False{}},[]},[]}
  ray_result(id,tables,support,minor,H.State{history},
    FR.clip_checked(W.attach(engine,view),TH.reset_ray_request(stage,transition)))

def ray_prior(id: String, transition: M.Transition, policy: TH.ResetPolicy,
              harness: Harness) -> IO(Harness):
  Harness{MH.State{world,support,minor,H.State{history},tail},tables,ht} = harness
  ray_taken(id,tables,support,minor,history,transition,policy,W.take(world))

def ray_parsed(+id: String, harness: Harness, applied: Bool,
               before: Maybe<&2,Slot<M.Body>>, after: Maybe<&2,Slot<M.Body>>,
               resolved: Maybe<&2,Slot<M.Vec3>>, seed: Maybe<&2,Slot<Seed>>,
               policy: Maybe<&2,Slot<TH.ResetPolicy>>) -> IO(Harness):
  match before after resolved seed policy:
    case Some{before} Some{after} Some{resolved} Some{seed} Some{policy}:
      do IO<Harness>:
        prior : Harness <- report_harness(id ++ "-before",seeded(harness,slot_value(M.Body,before),slot_value(Seed,seed)))
        ray_prior(id,M.Transition{slot_value(M.Body,after),slot_value(M.Vec3,resolved),False{},applied},slot_value(TH.ResetPolicy,policy),prior)
    case _ _ _ _ _: IO.die(Harness,2,"invalid MH reset phase fixture")

def ray_header(header: List<&2,String>, harness: Harness, before: String,
               after: String, resolved: String, seed: String, policy: String) -> IO(Harness):
  match header:
    case id <> "ray-phase" <> applied <> Nil{}:
      ray_parsed(id,harness,String.eq(applied,"1"),
        Maybe.map(&2,M.Body,Slot<M.Body>,value => Slot{value,[]},optional_body(numbers(String.split(before,'|')))),
        Maybe.map(&2,M.Body,Slot<M.Body>,value => Slot{value,[]},optional_body(numbers(String.split(after,'|')))),
        Maybe.map(&2,M.Vec3,Slot<M.Vec3>,value => Slot{value,[]},optional_vector(numbers(String.split(resolved,'|')))),
        parsed_seed(numbers(String.split(seed,'|'))),parsed_policy(numbers(String.split(policy,'|'))))
    case _: IO.die(Harness,2,"invalid MH reset phase header")

def dispatch_parts(parts: List<&2,String>, harness: Harness) -> IO(Harness):
  match parts:
    case header <> body <> context <> input <> hooks <> environment <> seed <> policy <> Nil{}:
      phase_header(String.split(header,'|'),harness,body,context,input,hooks,environment,seed,policy)
    case header <> before <> after <> resolved <> seed <> policy <> Nil{}:
      ray_header(String.split(header,'|'),harness,before,after,resolved,seed,policy)
    case header <> Nil{}: scalar_header(String.split(header,'|'),harness)
    case _: IO.die(Harness,2,"invalid local-travel-reset command")

def run_args(args: List<String>, harness: Harness) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit,Unit{})
    case arg <> rest:
      do IO<Unit>:
        next : Harness <- dispatch_parts(String.split(arg,';'),harness)
        run_args(rest,next)

def initialized(args: List<String>, tables: L.Tables, result: W.State & Result<&2,&2,String,Unit>) -> IO(Unit):
  match result:
    case (world,Fail{error}): IO.die(Unit,3,"local-travel-reset fixture:" ++ error)
    case (W.State{engine,body,yaw,pitch,Some{+palette},region,cache},Done{unit}):
      do IO<Unit>:
        ready : W.State <- fixture_palette(W.State{engine,body,0.375,F32.neg(0.25),Some{palette},region,cache},palette)
        cached : W.State <- snapshot_kept(W.snapshot(ready,64,48))
        run_args(args,Harness{MH.State{cached,SP.State{None{},False{}},LM.MinorState{False{}},H.State{H.History{F.from_u32(0)}},[]},tables,[]})
    case (world,Done{unit}): IO.die(Unit,3,"local-travel-reset missing palette")

def loaded(args: List<String>, result: Result<&2,&1,L.Error,L.Tables>) -> IO(Unit):
  match result:
    case Fail{error}: IO.die(Unit,3,"local-travel-reset sine table")
    case Done{tables}:
      do IO<Unit>:
        engine : G.Engine <- G.load()
        initialized(args,tables,W.new(engine))

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case path <> rest:
      do IO<Unit>:
        result : Result<&2,&1,L.Error,L.Tables> <- L.Tables.load(path)
        loaded(rest,result)
    case _: IO.die(Unit,2,"missing local-travel-reset table path")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(List.drop(&1,String,args,1n))
