import Base
import ../src/player_block_inside_stuck.bend as P
import ../src/player_fall_history.bend as H
import ../src/core.bend as C
import ../src/registry.bend as B
import ../src/section.bend as S
import ../src/section_map.bend as SM
import ../src/schedule.bend as Q
import ../src/world_codec.bend as WC
import ../src/movement.bend as M
import ../src/geometry.bend as A
import ../src/f64.bend as F
import ../src/json.bend as J

# This observer owns and returns the production State. Signatures visit every
# raw section cell and registry array slot, including malformed state IDs and
# inactive metadata slots; no validated codec can hide corruption on refusal.
# Recursive inert tails keep observer records boxed at native continuation
# boundaries. Every constructed observer record has an empty tail.
type Context is Data:
  Context{facts: P.Facts, level: P.Level, removed: Bool, no_physics: Bool, alive: Bool, box_tail: List<&2, Context>}

type Owner is Data:
  Owner{world: String, registry: String, receiver: String, box_tail: List<&2, Owner>}

type State is Type:
  State{active: P.State, context: Context, checkpoint: Maybe<&2, Owner>, retained: Bool, box_tail: List<&1, State>}

def number(text: String) -> U32:
  Maybe.default(&2, U32, J.u32_lexeme(text), 4294967295)

def flag(value: Bool) -> String:
  U32.show(Bool.to_u32(value))

def wide(value: F.F64) -> String:
  F.F64{hi, lo} = value
  U32.show(hi) ++ "," ++ U32.show(lo)

def vector(value: M.Vec3) -> String:
  M.Vec3{x, y, z} = value
  wide(x) ++ "," ++ wide(y) ++ "," ++ wide(z)

def strings(values: List<&2, String>) -> String:
  match values:
    case Nil{}: ""
    case +value <> rest: Nat.show(String.length(value)) ++ ":" ++ value ++ ";" ++ strings(rest)

def properties(values: List<&2, B.Property>) -> String:
  match values:
    case Nil{}: ""
    case B.Property{name, values, count, stride} <> rest:
      name ++ "=" ++ U32.show(count) ++ "," ++ U32.show(stride) ++ ":" ++ strings(values) ++ "/" ++ properties(rest)

def block(value: B.Block) -> String:
  B.Block{protocol, name, first, count, default, props} = value
  U32.show(protocol) ++ "," ++ name ++ "," ++ U32.show(first) ++ "," ++ U32.show(count) ++ "," ++ U32.show(default) ++ "," ++ properties(props) ++ "\n"

def registry_read(result: Array<B.Block> & B.Block, finish: Array<B.Block> -> String -> Array<B.Block> & String) -> Array<B.Block> & String:
  (array, value) = result
  finish(array, block(value))

def registry_array(fuel: Nat, +index: U32, array: Array<B.Block>) -> Array<B.Block> & String:
  match fuel:
    case 0n: (array, "")
    case 1n+rest:
      registry_read(Array.get(B.Block, array, index), kept => text =>
        P.paired(Array<B.Block>, String, Array<B.Block> & String,
          registry_array(rest, U32.inc(index), kept), returned => tail => (returned, text ++ tail)))

def names_text(values: Map<&2, U32>) -> String:
  match values:
    case MTip{}: "tip"
    case MLeaf{name, value}: "leaf:" ++ name ++ "=" ++ U32.show(value)
    case MNode{position, lo, hi}: "node:" ++ Nat.show(position) ++ "(" ++ names_text(lo) ++ ")(" ++ names_text(hi) ++ ")"

def registry_sized(+names: Map<&2, U32>, +count: U32, +states: U32, result: Array<B.Block> & U32) -> B.Registry & String:
  (array, +capacity) = result
  P.paired(Array<B.Block>, String, B.Registry & String, registry_array(U32.to_nat(capacity), 0, array), array => text =>
    (B.Registry{array, names, count, states}, U32.show(count) ++ "," ++ U32.show(states) ++ "," ++ U32.show(capacity) ++ ":" ++ names_text(names) ++ ":" ++ text))

def registry_signature(registry: B.Registry) -> B.Registry & String:
  B.Registry{array, names, count, states} = registry
  registry_sized(names, count, states, Array.size(B.Block, array))

def cells_read(result: Array<U32> & U32, finish: Array<U32> -> String -> Array<U32> & String) -> Array<U32> & String:
  (array, value) = result
  finish(array, U32.show(value) ++ ",")

def cells_signature(fuel: Nat, +index: U32, array: Array<U32>) -> Array<U32> & String:
  match fuel:
    case 0n: (array, "")
    case 1n+rest:
      cells_read(Array.get(U32, array, index), kept => text =>
        P.paired(Array<U32>, String, Array<U32> & String,
          cells_signature(rest, U32.inc(index), kept), returned => tail => (returned, text ++ tail)))

def section_sized(result: Array<U32> & U32) -> S.Section & String:
  (array, +size) = result
  P.paired(Array<U32>, String, S.Section & String, cells_signature(U32.to_nat(size), 0, array), array => text =>
    (S.Section{array}, U32.show(size) ++ ":" ++ text))

def section_signature(section: S.Section) -> S.Section & String:
  S.Section{array} = section
  section_sized(Array.size(U32, array))

def bucket_signature(entries: List<&1, SM.Entry>) -> List<&1, SM.Entry> & String:
  match entries:
    case Nil{}: ([], "")
    case SM.Entry{+key, section} <> rest:
      P.paired(S.Section, String, List<&1, SM.Entry> & String, section_signature(section), section => text =>
        P.paired(List<&1, SM.Entry>, String, List<&1, SM.Entry> & String, bucket_signature(rest), rest => tail =>
          (SM.Entry{key, section} <> rest, key ++ ":" ++ text ++ ";" ++ tail)))

def sections_signature(sections: SM.Sections) -> SM.Sections & String:
  match sections:
    case SM.EmptySections{}: (SM.EmptySections{}, "empty")
    case SM.Branch{lo, hi}:
      P.paired(SM.Sections, String, SM.Sections & String, sections_signature(lo), lo => left =>
        P.paired(SM.Sections, String, SM.Sections & String, sections_signature(hi), hi => right =>
          (SM.Branch{lo, hi}, "branch(" ++ left ++ ")(" ++ right ++ ")")))
    case SM.Bucket{entries}:
      P.paired(List<&1, SM.Entry>, String, SM.Sections & String, bucket_signature(entries), entries => text =>
        (SM.Bucket{entries}, "bucket:" ++ text))

def position(point: C.Position) -> String:
  C.Position{dimension, x, y, z} = point
  dimension ++ "," ++ U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z)

def stamp(value: Q.Stamp) -> String:
  Q.Stamp{tick, peer, sequence} = value
  Nat.show(tick) ++ "," ++ U32.show(peer) ++ "," ++ Nat.show(sequence)

def mutation(value: C.Mutation) -> String:
  match value:
    case C.SectionCreate{point, fill}: "section:" ++ position(point) ++ "," ++ U32.show(fill)
    case C.BlockSet{point, state}: "block:" ++ position(point) ++ "," ++ U32.show(state)
    case C.TimeSet{time}: "time:" ++ Nat.show(time)
    case C.DaylightSet{enabled}: "daylight:" ++ flag(enabled)

def pending_signature(values: List<&2, Q.Pending<C.Mutation>>) -> String:
  match values:
    case Nil{}: ""
    case Q.Pending{when, operation} <> rest: stamp(when) ++ ":" ++ mutation(operation) ++ ";" ++ pending_signature(rest)

def events_signature(values: List<&2, C.CoreEvent>) -> String:
  match values:
    case Nil{}: ""
    case C.Applied{when, revision} <> rest: "applied:" ++ stamp(when) ++ ":" ++ Nat.show(revision) ++ ";" ++ events_signature(rest)
    case C.Rejected{when, cause} <> rest: "rejected:" ++ stamp(when) ++ ":" ++ P.world_error(cause) ++ ";" ++ events_signature(rest)

def world_signature(world: C.World) -> C.World & String:
  C.World{+tick, +time, +paused, +daylight, +revision, +count, sections, +pending, +events} = world
  P.paired(SM.Sections, String, C.World & String, sections_signature(sections), sections => text =>
    (C.World{tick, time, paused, daylight, revision, count, sections, pending, events}, Nat.show(tick) ++ "," ++ Nat.show(time) ++ "," ++ flag(paused) ++ "," ++ flag(daylight) ++ "," ++ Nat.show(revision) ++ "," ++ U32.show(count) ++ ":" ++ pending_signature(pending) ++ ":" ++ events_signature(events) ++ ":" ++ text))

def impact_text(impact: Maybe<&2, M.Vec3>) -> String:
  match impact:
    case None{}: "none"
    case Some{value}: vector(value)

def receiver_text(receiver: P.Receiver, history: H.History) -> String:
  P.Receiver{multiplier, P.Impulse{grace, impact}} = receiver
  H.History{distance} = history
  vector(multiplier) ++ "\t" ++ wide(distance) ++ "\t" ++ U32.show(grace) ++ "\t" ++ impact_text(impact)

def snapshot(active: P.State) -> P.State & Owner:
  match active:
    case P.State{world, registry, +receiver, H.State{+history}, Nil{}}:
      P.paired(C.World, String, P.State & Owner, world_signature(world), world => world_text =>
        P.paired(B.Registry, String, P.State & Owner, registry_signature(registry), registry => registry_text =>
          (P.State{world, registry, receiver, H.State{history}, []}, Owner{world_text, registry_text, receiver_text(receiver, history), Nil{}})))
    case state: (state, Owner{"noncanonical", "noncanonical", "noncanonical", Nil{}})

def same_owner(old: Owner, next: Owner, failed: Bool) -> Bool:
  Owner{+world, registry, receiver, owner_box_tail} = old
  Owner{next_world, next_registry, next_receiver, owner_box_tail} = next
  Bool.not(String.eq(world, "noncanonical")) && String.eq(world, next_world) && String.eq(registry, next_registry) && (Bool.not(failed) || String.eq(receiver, next_receiver))

def checked_snapshot(+id: String, context: Context, old: Owner, +retained: Bool, failed: Bool, result: P.State & Owner) -> IO(State):
  (active, +next) = result
  +valid = same_owner(old, next, failed)
  do IO<State>:
    IO.print(id ++ "\towners\t" ++ flag(valid))
    return State{active, context, Some{next}, retained && valid, Nil{}}

def checked(id: String, active: P.State, context: Context, checkpoint: Maybe<&2, Owner>, retained: Bool, failed: Bool) -> IO(State):
  match checkpoint:
    case None{}: IO.pure(State, State{active, context, None{}, retained, Nil{}})
    case Some{old}: checked_snapshot(id, context, old, retained, failed, snapshot(active))

def read_text(reads: List<&2, P.Read>) -> String:
  match reads:
    case Nil{}: ""
    case P.Read{C.Position{dimension, x, y, z}, B.Resolved{protocol, name, state, assignments}} <> rest:
      U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z) ++ "," ++ U32.show(state) ++ ";" ++ read_text(rest)

def failed_answer(+id: String, context: Context, checkpoint: Maybe<&2, Owner>, retained: Bool, active: P.State, cause: P.Error) -> IO(State):
  P.State{world, registry, +receiver, H.State{+history}, tail} = active
  do IO<State>:
    IO.print(id ++ "\terror\t" ++ P.error_text(cause) ++ "\t" ++ receiver_text(receiver, history))
    checked(id, P.State{world, registry, receiver, H.State{history}, tail}, context, checkpoint, retained, True{})

def done_answer(+id: String, context: Context, checkpoint: Maybe<&2, Owner>, retained: Bool, active: P.State, observation: P.Observation) -> IO(State):
  P.State{world, registry, +held_receiver, H.State{+held_history}, tail} = active
  P.Observation{+receiver, +history, reset, reads} = observation
  +valid = String.eq(receiver_text(held_receiver, held_history), receiver_text(receiver, history))
  do IO<State>:
    IO.print(id ++ "\tok\t" ++ receiver_text(receiver, history) ++ "\t" ++ flag(reset) ++ "\t" ++ read_text(reads))
    IO.print(id ++ "\tauthority\t" ++ flag(valid))
    checked(id, P.State{world, registry, held_receiver, H.State{held_history}, tail}, context, checkpoint, retained && valid, False{})

def answered(+id: String, context: Context, checkpoint: Maybe<&2, Owner>, retained: Bool, result: P.State & Result<&2, &2, P.Error, P.Observation>) -> IO(State):
  (active, status) = result
  match status:
    case Fail{cause}: failed_answer(id, context, checkpoint, retained, active, cause)
    case Done{observation}: done_answer(id, context, checkpoint, retained, active, observation)

def callback_result(world: C.World, registry: B.Registry, +receiver: P.Receiver, +history: H.History, tail: List<&1, P.State>, result: Result<&2, &2, P.Error, P.Candidate>) -> P.State & Result<&2, &2, P.Error, P.Observation>:
  match result:
    case Fail{cause}: (P.State{world, registry, receiver, H.State{history}, tail}, Fail{cause})
    case Done{P.Candidate{+next, +next_history, reset}}:
      (P.State{world, registry, next, H.State{next_history}, tail}, Done{P.Observation{next, next_history, reset, []}})

def callback_ready(id: String, world: C.World, registry: B.Registry, +receiver: P.Receiver, +history: H.History, tail: List<&1, P.State>, +context: Context, checkpoint: Maybe<&2, Owner>, retained: Bool, resolved: B.Resolved) -> IO(State):
  Context{facts, level, removed, physics, alive, context_box_tail} = context
  answered(id, context, checkpoint, retained, callback_result(world, registry, receiver, history, tail, P.callback_checked(receiver, history, facts, level, resolved)))

def callback_decoded(+id: String, world: C.World, +receiver: P.Receiver, +history: H.History, tail: List<&1, P.State>, +context: Context, checkpoint: Maybe<&2, Owner>, retained: Bool, result: B.Registry & Result<&2, &2, B.Error, B.Resolved>) -> IO(State):
  (registry, status) = result
  match status:
    case Fail{cause}:
      answered(id, context, checkpoint, retained, (P.State{world, registry, receiver, H.State{history}, tail}, Fail{P.RegistryError{cause}}))
    case Done{resolved}: callback_ready(id, world, registry, receiver, history, tail, context, checkpoint, retained, resolved)

def callback(id: String, state: State, state_id: U32) -> IO(State):
  State{P.State{world, registry, receiver, H.State{history}, tail}, context, checkpoint, retained, state_box_tail} = state
  callback_decoded(id, world, receiver, history, tail, context, checkpoint, retained, B.Registry.decode(registry, state_id))

type VectorRead is Data:
  VectorRead{value: M.Vec3, rest: List<&2, String>}

def read_vector(fields: List<&2, String>) -> Maybe<&2, VectorRead>:
  match fields:
    case ah <> al <> bh <> bl <> ch <> cl <> rest:
      Some{VectorRead{M.Vec3{F.F64{number(ah), number(al)}, F.F64{number(bh), number(bl)}, F.F64{number(ch), number(cl)}}, rest}}
    case _: None{}

def facts_gate(+bits: U32, kind: U32) -> P.Facts:
  match kind:
    case 0: P.Player{U32.is_ne(U32.and(bits, 4), 0), U32.is_ne(U32.and(bits, 8), 0)}
    case 1: P.OtherLiving{True{}, U32.is_ne(U32.and(bits, 8), 0)}
    case 2: P.OtherLiving{False{}, U32.is_ne(U32.and(bits, 8), 0)}
    case _: P.OtherEntity{}

def facts(+bits: U32) -> P.Facts:
  facts_gate(bits, U32.and(bits, 3))

def level_gate(+bits: U32, position: M.Vec3, known: M.Vec3, old: M.Vec3, kind: U32) -> P.Level:
  match kind:
    case 0: P.OrdinaryLevel{}
    case 1: P.ClientLevel{}
    case _: P.ServerLevel{U32.is_ne(U32.and(bits, 4), 0), known, old, position}

def level(+bits: U32, position: M.Vec3, known: M.Vec3, old: M.Vec3) -> P.Level:
  level_gate(bits, position, known, old, U32.and(bits, 3))

def context_old(+id: String, state: State, +flags: U32, level_bits: U32, position: M.Vec3, known: M.Vec3, result: Maybe<&2, VectorRead>) -> IO(State):
  match state result:
    case State{active, previous, checkpoint, retained, state_box_tail} Some{VectorRead{old, Nil{}}}:
      do IO<State>:
        IO.print(id ++ "\tok\tcontext")
        return State{active, Context{facts(flags), level(level_bits, position, known, old), U32.is_ne(U32.and(flags, 16), 0), U32.is_ne(U32.and(flags, 32), 0), U32.is_eq(U32.and(flags, 64), 0), Nil{}}, checkpoint, retained, Nil{}}
    case _ _: IO.die(State, 2, "invalid context old position")

def context_known(id: String, state: State, flags: U32, level_bits: U32, position: M.Vec3, result: Maybe<&2, VectorRead>) -> IO(State):
  match result:
    case Some{VectorRead{known, rest}}: context_old(id, state, flags, level_bits, position, known, read_vector(rest))
    case None{}: IO.die(State, 2, "invalid context movement")

def context_position(id: String, state: State, flags: U32, level_bits: U32, result: Maybe<&2, VectorRead>) -> IO(State):
  match result:
    case Some{VectorRead{position, rest}}: context_known(id, state, flags, level_bits, position, read_vector(rest))
    case None{}: IO.die(State, 2, "invalid context position")

def seeded(+id: String, state: State, multiplier: M.Vec3, distance: F.F64, grace: U32, impact: U32, result: Maybe<&2, VectorRead>) -> IO(State):
  match state result:
    case State{P.State{world, registry, previous, history, tail}, context, checkpoint, retained, state_box_tail} Some{VectorRead{value, Nil{}}}:
      do IO<State>:
        IO.print(id ++ "\tok\tseed")
        return State{P.State{world, registry, P.Receiver{multiplier, P.Impulse{grace, P.choose(Maybe<&2, M.Vec3>, Some{value}, None{}, U32.is_ne(impact, 0))}}, H.State{H.History{distance}}, tail}, context, None{}, retained, Nil{}}
    case _ _: IO.die(State, 2, "invalid seed impact position")

def seed_vector(id: String, state: State, result: Maybe<&2, VectorRead>) -> IO(State):
  match result:
    case Some{VectorRead{multiplier, hi <> lo <> grace <> impact <> rest}}:
      seeded(id, state, multiplier, F.F64{number(hi), number(lo)}, number(grace), number(impact), read_vector(rest))
    case _: IO.die(State, 2, "invalid receiver seed")

def admission(value: String) -> P.Admission:
  match value:
    case "hit": P.BlockIntersection{}
    case "miss": P.NoBlockIntersection{}
    case _: P.UnresolvedIntersection{}

def contacts(+dimension: String, fields: List<&2, String>) -> List<&2, P.Contact>:
  match fields:
    case Nil{}: []
    case x <> y <> z <> how <> rest:
      P.Contact{C.Position{dimension, number(x), number(y), number(z)}, admission(how)} <> contacts(dimension, rest)
    case _: []

def ordered_query(id: String, state: State, +dimension: String, +budget: U32, malformed: U32, +fields: List<&2, String>) -> IO(State):
  State{active, +context, checkpoint, retained, state_box_tail} = state
  Context{+facts, +level, +removed, +physics, +alive, context_box_tail} = context
  +request = {P.Request{facts, level, removed, physics, alive, contacts(dimension, fields), U32.to_nat(budget), []} : P.Request}
  answered(id, context, checkpoint, retained, P.query(active, P.Request{facts, level, removed, physics, alive, contacts(dimension, fields), U32.to_nat(budget), P.choose(List<&2, P.Request>, [request], [], U32.is_ne(malformed, 0))}))

def stationary_boxed(id: String, state: State, dimension: String, budget: U32, box: A.AABB) -> IO(State):
  State{active, +context, checkpoint, retained, state_box_tail} = state
  Context{facts, level, removed, physics, alive, context_box_tail} = context
  answered(id, context, checkpoint, retained, P.stationary(active, P.Stationary{facts, level, removed, physics, alive, dimension, box, U32.to_nat(budget)}))

def stationary_query(id: String, state: State, dimension: String, budget: U32, fields: List<&2, String>) -> IO(State):
  match fields:
    case ah <> al <> bh <> bl <> ch <> cl <> dh <> dl <> eh <> el <> fh <> fl <> Nil{}:
      stationary_boxed(id, state, dimension, budget, A.AABB{F.F64{number(ah), number(al)}, F.F64{number(bh), number(bl)}, F.F64{number(ch), number(cl)}, F.F64{number(dh), number(dl)}, F.F64{number(eh), number(el)}, F.F64{number(fh), number(fl)}})
    case _: IO.die(State, 2, "invalid stationary box")

def travel_succeeded(id: String, state: State) -> IO(State):
  State{P.State{world, registry, receiver, H.State{+history}, tail}, context, checkpoint, retained, state_box_tail} = state
  +next : P.Receiver = P.travel_succeeded(receiver)
  answered(id, context, checkpoint, retained, (P.State{world, registry, next, H.State{history}, tail}, Done{P.Observation{next, history, False{}, []}}))

def checkpoint_snapshot(+id: String, context: Context, retained: Bool, result: P.State & Owner) -> IO(State):
  (active, saved) = result
  do IO<State>:
    IO.print(id ++ "\tok\tcheckpoint")
    return State{active, context, Some{saved}, retained, Nil{}}

def checkpoint(id: String, state: State) -> IO(State):
  State{active, context, prior, retained, state_box_tail} = state
  checkpoint_snapshot(id, context, retained, snapshot(active))

def world_loaded(+id: String, state: State, result: Result<&2, &1, String, WC.Loaded>) -> IO(State):
  match state result:
    case State{P.State{old, registry, receiver, history, tail}, context, checkpoint, retained, state_box_tail} Done{WC.Loaded{world, peer}}:
      do IO<State>:
        IO.print(id ++ "\tok\tworld")
        return State{P.State{world, registry, receiver, history, tail}, context, None{}, retained, Nil{}}
    case _ Fail{cause}: IO.die(State, 2, cause)

def raw_closed(result: File & Result<&1, &1, U32 & String, List<&2, U32>>) -> IO(List<&2, U32>):
  (file, status) = result
  do IO<List<&2, U32>>:
    File.close(file)
    IO.pass(List<&2, U32>, status)

def raw_file(path: String) -> IO(List<&2, U32>):
  do IO<List<&2, U32>>:
    file : File <- IO.try(File, File.open(path, "r"))
    result : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_bytes(file, 4194304)
    raw_closed(result)

def world_file(id: String, state: State, path: String, count: U32, identity: String) -> IO(State):
  do IO<State>:
    bytes : List<&2, U32> <- raw_file(path)
    world_loaded(id, state, WC.decode(bytes, count, identity))

def forge_section(+id: String, state: State, key: String, value: U32) -> IO(State):
  State{P.State{C.World{tick, time, paused, daylight, revision, count, sections, pending, events}, registry, receiver, history, tail}, context, checkpoint, retained, state_box_tail} = state
  do IO<State>:
    IO.print(id ++ "\tok\tforge")
    return State{P.State{C.World{tick, time, paused, daylight, revision, count, SM.set(sections, key, S.Section.new(value)), pending, events}, registry, receiver, history, tail}, context, None{}, retained, Nil{}}

def raw_cell_section(+id: String, world: C.World, registry: B.Registry, receiver: P.Receiver, history: H.State, tail: List<&1, P.State>, context: Context, retained: Bool, sections: SM.Sections, +point: C.Position, value: U32, section: S.Section) -> IO(State):
  C.Position{dimension, x, y, z} = point
  S.Section{array} = section
  do IO<State>:
    IO.print(id ++ "\tok\tforge")
    return State{P.State{C.replace_sections(world, SM.set(sections, C.section_key(point), S.Section{Array.set(U32, array, S.Section.index_value(S.Coord.local(x), S.Coord.local(y), S.Coord.local(z)), value)})), registry, receiver, history, tail}, context, None{}, retained, Nil{}}

def raw_cell_popped(+id: String, world: C.World, registry: B.Registry, receiver: P.Receiver, history: H.State, tail: List<&1, P.State>, context: Context, retained: Bool, point: C.Position, value: U32, result: SM.Sections & Maybe<&1, S.Section>) -> IO(State):
  (sections, found) = result
  match found:
    case None{}: IO.die(State, 2, "raw cell requires an existing section")
    case Some{section}: raw_cell_section(id, world, registry, receiver, history, tail, context, retained, sections, point, value, section)

def raw_cell(id: String, state: State, +point: C.Position, value: U32) -> IO(State):
  State{P.State{C.World{tick, time, paused, daylight, revision, count, sections, pending, events}, registry, receiver, history, tail}, context, checkpoint, retained, state_box_tail} = state
  raw_cell_popped(id, C.World{tick, time, paused, daylight, revision, count, SM.EmptySections{}, pending, events}, registry, receiver, history, tail, context, retained, point, value, SM.pop(sections, C.section_key(point)))

def raw_assignments(value: String) -> List<&2, B.Assignment>:
  match value:
    case "missing": []
    case "duplicate": [B.Assignment{"age", "0"}, B.Assignment{"age", "1"}]
    case "extra": [B.Assignment{"age", "0"}, B.Assignment{"other", "0"}]
    case _: [B.Assignment{"age", value}]

def raw_callback(id: String, state: State, name: String, age: String) -> IO(State):
  State{P.State{world, registry, +receiver, H.State{+history}, tail}, +context, checkpoint, retained, state_box_tail} = state
  Context{facts, level, removed, physics, alive, context_box_tail} = context
  answered(id, context, checkpoint, retained, callback_result(world, registry, receiver, history, tail, P.callback_checked(receiver, history, facts, level, B.Resolved{0, name, 0, raw_assignments(age)})))

def operation(fields: List<&2, String>, state: State, +count: U32, +identity: String) -> IO(State):
  match fields:
    case id <> "seed" <> rest: seed_vector(id, state, read_vector(rest))
    case id <> "context" <> flags <> level_bits <> rest: context_position(id, state, number(flags), number(level_bits), read_vector(rest))
    case id <> "callback" <> state_id <> Nil{}: callback(id, state, number(state_id))
    case id <> "travel-succeeded" <> Nil{}: travel_succeeded(id, state)
    case id <> "raw-callback" <> name <> age <> Nil{}: raw_callback(id, state, name, age)
    case id <> "ordered" <> dimension <> budget <> malformed <> rest: ordered_query(id, state, dimension, number(budget), number(malformed), rest)
    case id <> "stationary" <> dimension <> budget <> rest: stationary_query(id, state, dimension, number(budget), rest)
    case id <> "world" <> path <> Nil{}: world_file(id, state, path, count, identity)
    case id <> "section" <> key <> value <> Nil{}: forge_section(id, state, key, number(value))
    case id <> "raw-cell" <> x <> y <> z <> value <> Nil{}: raw_cell(id, state, C.Position{"minecraft:overworld", number(x), number(y), number(z)}, number(value))
    case id <> "checkpoint" <> Nil{}: checkpoint(id, state)
    case id <> "check" <> Nil{}:
      State{active, context, checkpoint, retained, state_box_tail} = state
      checked(id, active, context, checkpoint, retained, True{})
    case "" <> Nil{}: IO.pure(State, state)
    case _: IO.die(State, 2, "invalid block-inside request")

def operations(lines: List<&2, String>, state: State, +count: U32, +identity: String) -> IO(State):
  match lines:
    case Nil{}: IO.pure(State, state)
    case line <> rest:
      do IO<State>:
        next : State <- operation(String.split(line, Chr{9}), state, count, identity)
        operations(rest, next, count, identity)

def final_report(state: State) -> IO(Unit):
  State{active, context, checkpoint, retained, state_box_tail} = state
  IO.print("final\towners\t" ++ flag(retained))

def requests_loaded(state: State, count: U32, identity: String, result: Result<&2, &2, B.Error, String>) -> IO(Unit):
  match result:
    case Fail{cause}: IO.die(Unit, 2, B.error_text(cause))
    case Done{text}:
      do IO<Unit>:
        next : State <- operations(String.split(text, Chr{10}), state, count, identity)
        final_report(next)

def initial_world(registry: B.Registry, requests: String, count: U32, identity: String, result: Result<&2, &1, String, WC.Loaded>) -> IO(Unit):
  match result:
    case Fail{cause}: IO.die(Unit, 2, cause)
    case Done{WC.Loaded{world, peer}}:
      do IO<Unit>:
        text : Result<&2, &2, B.Error, String> <- B.read_text(requests)
        requests_loaded(State{P.State{world, registry, P.empty(), H.State{H.History{F.from_u32(0)}}, []}, Context{P.Player{False{}, False{}}, P.OrdinaryLevel{}, False{}, False{}, True{}, Nil{}}, None{}, True{}, Nil{}}, count, identity, text)

def registry_loaded(world: String, requests: String, +count: U32, +identity: String, result: Result<&2, &1, B.Error, B.Registry>) -> IO(Unit):
  match result:
    case Fail{cause}: IO.die(Unit, 2, B.error_text(cause))
    case Done{registry}:
      do IO<Unit>:
        bytes : List<&2, U32> <- raw_file(world)
        initial_world(registry, requests, count, identity, WC.decode(bytes, count, identity))

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case registry <> world <> requests <> count <> identity <> Nil{}:
      do IO<Unit>:
        loaded : Result<&2, &1, B.Error, B.Registry> <- B.Registry.load(registry)
        registry_loaded(world, requests, number(count), identity, loaded)
    case _: IO.die(Unit, 2, "expected registry, world, requests, count and identity")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(List.tail(&1, String, args))
