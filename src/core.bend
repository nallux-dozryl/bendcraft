import Base
import ./schedule.bend as Q
import ./section.bend as S
import ./section_map.bend as M
import ./section_map_read.bend as Read
import ./section_map_update.bend as Update

type Capability is Data:
  Observer{}
  Player{peer: U32}
  Developer{}

type Position is Data:
  Position{dimension: String, x: U32, y: U32, z: U32}

type Mutation is Data:
  SectionCreate{position: Position, fill: U32}
  BlockSet{position: Position, state: U32}
  TimeSet{day_time: Nat}
  DaylightSet{enabled: Bool}

type Error is Data:
  PermissionDenied{}
  UnknownDimension{dimension: String}
  InvalidState{state: U32}
  MissingSection{key: String}
  SectionExists{key: String}
  InvalidCoordinate{}
  PastTick{}
  TooManyPending{}

type CoreEvent is Data:
  Applied{stamp: Q.Stamp, revision: Nat}
  Rejected{stamp: Q.Stamp, error: Error}

type Clock is Data:
  Clock{tick: Nat, day_time: Nat, paused: Bool, daylight: Bool, revision: Nat, pending: Nat}

type World is Type:
  World{tick: Nat, day_time: Nat, paused: Bool, daylight: Bool,
    revision: Nat, state_count: U32, sections: M.Sections,
    pending: List<&2, Q.Pending<Mutation>>, events: List<&2, CoreEvent>}

def new(state_count: U32) -> World:
  World{0n, 0n, True{}, True{}, 0n, state_count, M.EmptySections{}, [], []}

def developer(cap: Capability) -> Bool:
  match cap:
    case Developer{}:
      True{}
    case other:
      False{}

def dimension_known(+name: String) -> Bool:
  String.eq(name, "minecraft:overworld") || String.eq(name, "minecraft:the_nether") || String.eq(name, "minecraft:the_end")

def dimension(p: Position) -> String:
  Position{d, x, y, z} = p
  d

def section_key(p: Position) -> String:
  Position{d, x, y, z} = p
  d ++ "/" ++ U32.show(S.Coord.section(x)) ++ "/" ++ U32.show(S.Coord.section(y)) ++ "/" ++ U32.show(S.Coord.section(z))

def mutation_position_choose(d: String, known: Bool, state_ok: Bool, state: U32) -> Result<&2, &2, Error, Unit>:
  match known state_ok:
    case False{} _:
      Fail{UnknownDimension{d}}
    case True{} False{}:
      Fail{InvalidState{state}}
    case True{} True{}:
      Done{Unit{}}

def mutation_position_valid(+p: Position, +state: U32, count: U32) -> Result<&2, &2, Error, Unit>:
  +d = dimension(p)
  mutation_position_choose(d, dimension_known(d), U32.is_lt(state, count), state)


def validate(m: Mutation, count: U32) -> Result<&2, &2, Error, Unit>:
  match m:
    case SectionCreate{p, fill}:
      mutation_position_valid(p, fill, count)
    case BlockSet{p, state}:
      mutation_position_valid(p, state, count)
    case TimeSet{t}:
      Done{Unit{}}
    case DaylightSet{b}:
      Done{Unit{}}

def clock(w: World) -> World & Clock:
  World{+tick, +time, +paused, +daylight, +rev, count, sections, +pending, events} = w
  (World{tick, time, paused, daylight, rev, count, sections, pending, events}, Clock{tick, time, paused, daylight, rev, Q.length(Mutation, pending)})

def set_paused(w: World, paused: Bool) -> World:
  World{tick, time, old, daylight, rev, count, sections, pending, events} = w
  World{tick, time, paused, daylight, rev, count, sections, pending, events}

def replace_sections(w: World, sections: M.Sections) -> World:
  World{tick, time, paused, daylight, rev, count, old, pending, events} = w
  World{tick, time, paused, daylight, rev, count, sections, pending, events}

def set_time(w: World, time: Nat) -> World:
  World{tick, old, paused, daylight, rev, count, sections, pending, events} = w
  World{tick, time, paused, daylight, rev, count, sections, pending, events}

def set_daylight(w: World, enabled: Bool) -> World:
  World{tick, time, paused, old, rev, count, sections, pending, events} = w
  World{tick, time, paused, enabled, rev, count, sections, pending, events}

def enqueue(w: World, p: Q.Pending<Mutation>) -> World:
  World{tick, time, paused, daylight, rev, count, sections, pending, events} = w
  World{tick, time, paused, daylight, rev, count, sections, Q.insert(Mutation, pending, p), events}

def admit_checked(w: World, p: Q.Pending<Mutation>, permission: Bool, future: Bool, room: Bool, valid: Result<&2, &2, Error, Unit>) -> World & Result<&2, &2, Error, Unit>:
  match permission future room valid:
    case False{} _ _ _:
      (w, Fail{PermissionDenied{}})
    case True{} False{} _ _:
      (w, Fail{PastTick{}})
    case True{} True{} False{} _:
      (w, Fail{TooManyPending{}})
    case True{} True{} True{} Fail{error}:
      (w, Fail{error})
    case True{} True{} True{} Done{u}:
      (enqueue(w, p), Done{Unit{}})

def admit(w: World, cap: Capability, +stamp: Q.Stamp, +m: Mutation) -> World & Result<&2, &2, Error, Unit>:
  World{+tick, time, paused, daylight, rev, +count, sections, +pending, events} = w
  admit_checked(World{tick, time, paused, daylight, rev, count, sections, pending, events}, Q.Pending{stamp, m}, developer(cap), Nat.is_gt(Q.stamp_tick(stamp), tick), Nat.is_lt(Q.length(Mutation, pending), 4096n), validate(m, count))

def cancel(w: World, stamp: Q.Stamp) -> World:
  World{tick, time, paused, daylight, rev, count, sections, pending, events} = w
  World{tick, time, paused, daylight, rev, count, sections, Q.cancel(Mutation, pending, stamp), events}

def trim_events(events: List<&2, CoreEvent>, room: Nat) -> List<&2, CoreEvent>:
  match events room:
    case _ 0n:
      []
    case Nil{} _:
      []
    case Con{h, t} 1n+n:
      h <> trim_events(t, n)

def add_event(w: World, event: CoreEvent) -> World:
  World{tick, time, paused, daylight, rev, count, sections, pending, events} = w
  World{tick, time, paused, daylight, rev, count, sections, pending, trim_events(event <> events, 1024n)}

def accepted(w: World, stamp: Q.Stamp) -> World:
  World{tick, time, paused, daylight, +rev, count, sections, pending, events} = w
  +next = {1n+rev : Nat}
  add_event(World{tick, time, paused, daylight, next, count, sections, pending, events}, Applied{stamp, next})

def finish(w: World, stamp: Q.Stamp, result: Result<&2, &2, Error, Unit>) -> World:
  match result:
    case Fail{error}:
      add_event(w, Rejected{stamp, error})
    case Done{u}:
      accepted(w, stamp)

def create_checked(w: World, +p: Position, fill: U32, popped: M.Sections & Maybe<&1, S.Section>) -> World & Result<&2, &2, Error, Unit>:
  (sections, old) = popped
  match old:
    case Some{section}:
      (replace_sections(w, M.set(sections, section_key(p), section)), Fail{SectionExists{section_key(p)}})
    case None{}:
      (replace_sections(w, M.set(sections, section_key(p), S.Section.new(fill))), Done{Unit{}})

# Failed writes/creates retain the complete section representation, including
# empty buckets and the order of hash-colliding entries.
def updated_status(+p: Position, status: Result<&2, &2, Update.Error, Unit>) -> Result<&2, &2, Error, Unit>:
  match status:
    case Done{unit}: Done{unit}
    case Fail{Update.Existing{}}: Fail{SectionExists{section_key(p)}}
    case Fail{Update.Missing{}}: Fail{MissingSection{section_key(p)}}
    case Fail{Update.Malformed{}}: Fail{InvalidCoordinate{}}
    case Fail{Update.SectionRejected{error}}: Fail{InvalidCoordinate{}}

def updated_sections(w: World, p: Position, changed: M.Sections & Result<&2, &2, Update.Error, Unit>) -> World & Result<&2, &2, Error, Unit>:
  (sections, status) = changed
  (replace_sections(w, sections), updated_status(p, status))

def create_section(w: World, +p: Position, fill: U32) -> World & Result<&2, &2, Error, Unit>:
  World{tick, time, paused, daylight, rev, count, sections, pending, events} = w
  updated_sections(World{tick, time, paused, daylight, rev, count, M.EmptySections{}, pending, events}, p,
    Update.create(sections, section_key(p), fill))

def write_result(w: World, result: Result<&2, &2, S.Section.Error, Unit>) -> World & Result<&2, &2, Error, Unit>:
  match result:
    case Done{u}:
      (w, Done{Unit{}})
    case Fail{error}:
      (w, Fail{InvalidCoordinate{}})

def write_back(w: World, p: Position, sections: M.Sections, r: S.Section & Result<&2, &2, S.Section.Error, Unit>) -> World & Result<&2, &2, Error, Unit>:
  (section, result) = r
  write_result(replace_sections(w, M.set(sections, section_key(p), section)), result)

def write_local(w: World, +p: Position, state: U32, sections: M.Sections, section: S.Section) -> World & Result<&2, &2, Error, Unit>:
  Position{d, x, y, z} = p
  write_back(w, p, sections, S.Section.set(section, S.Coord.local(x), S.Coord.local(y), S.Coord.local(z), state))

def write_existing(w: World, +p: Position, state: U32, popped: M.Sections & Maybe<&1, S.Section>) -> World & Result<&2, &2, Error, Unit>:
  (sections, old) = popped
  match old:
    case None{}:
      (replace_sections(w, sections), Fail{MissingSection{section_key(p)}})
    case Some{section}:
      write_local(w, p, state, sections, section)

def write_block(w: World, +p: Position, state: U32) -> World & Result<&2, &2, Error, Unit>:
  World{tick, time, paused, daylight, rev, count, sections, pending, events} = w
  Position{dimension, x, y, z} = p
  updated_sections(World{tick, time, paused, daylight, rev, count, M.EmptySections{}, pending, events}, p,
    Update.write(sections, section_key(p), S.Coord.local(x), S.Coord.local(y), S.Coord.local(z), state))

def apply(w: World, m: Mutation) -> World & Result<&2, &2, Error, Unit>:
  match m:
    case SectionCreate{p, fill}:
      create_section(w, p, fill)
    case BlockSet{p, state}:
      write_block(w, p, state)
    case TimeSet{time}:
      (set_time(w, time), Done{Unit{}})
    case DaylightSet{enabled}:
      (set_daylight(w, enabled), Done{Unit{}})

def apply_finished(stamp: Q.Stamp, r: World & Result<&2, &2, Error, Unit>) -> World:
  (w, result) = r
  finish(w, stamp, result)

def apply_due(ps: List<&2, Q.Pending<Mutation>>, w: World) -> World:
  match ps:
    case Nil{}:
      w
    case Con{Q.Pending{+stamp, m}, rest}:
      apply_due(rest, apply_finished(stamp, apply(w, m)))

def daylight_tick(time: Nat, daylight: Bool) -> Nat:
  match daylight:
    case True{}:
      1n+time
    case False{}:
      time

def step_partition(w: World, partition: List<&2, Q.Pending<Mutation>> & List<&2, Q.Pending<Mutation>>) -> World:
  World{tick, time, paused, daylight, rev, count, sections, ignored, events} = w
  (due, future) = partition
  apply_due(due, World{tick, time, paused, daylight, rev, count, sections, future, events})

def step(w: World) -> World:
  World{+tick, time, paused, +daylight, rev, count, sections, pending, events} = w
  +next = {1n+tick : Nat}
  step_partition(World{next, daylight_tick(time, daylight), paused, daylight, rev, count, sections, [], events}, Q.take_due(Mutation, pending, next))

def advance(ticks: Nat, w: World) -> World:
  match ticks:
    case 0n:
      w
    case 1n+rest:
      advance(rest, step(w))

def realtime_choose(paused: Bool, w: World) -> World:
  match paused:
    case True{}:
      w
    case False{}:
      step(w)

def realtime_step(w: World) -> World:
  World{tick, time, +paused, daylight, rev, count, sections, pending, events} = w
  realtime_choose(paused, World{tick, time, paused, daylight, rev, count, sections, pending, events})


def read_result(w: World, result: Result<&2, &2, S.Section.Error, U32>) -> World & Result<&2, &2, Error, U32>:
  match result:
    case Done{state}:
      (w, Done{state})
    case Fail{error}:
      (w, Fail{InvalidCoordinate{}})

def read_back(w: World, p: Position, sections: M.Sections, r: S.Section & Result<&2, &2, S.Section.Error, U32>) -> World & Result<&2, &2, Error, U32>:
  (section, result) = r
  read_result(replace_sections(w, M.set(sections, section_key(p), section)), result)

def read_local(w: World, +p: Position, sections: M.Sections, section: S.Section) -> World & Result<&2, &2, Error, U32>:
  Position{d, x, y, z} = p
  read_back(w, p, sections, S.Section.get(section, S.Coord.local(x), S.Coord.local(y), S.Coord.local(z)))

def read_existing(w: World, +p: Position, popped: M.Sections & Maybe<&1, S.Section>) -> World & Result<&2, &2, Error, U32>:
  (sections, old) = popped
  match old:
    case None{}:
      (replace_sections(w, sections), Fail{MissingSection{section_key(p)}})
    case Some{section}:
      read_local(w, p, sections, section)

# Read preserves the owned trie and collision-bucket order. A query must not
# become an implicit pop/set update of the complete world representation.
def read_retained(w: World, +p: Position, observed: M.Sections & Maybe<&2, Result<&2, &2, S.Section.Error, U32>>) -> World & Result<&2, &2, Error, U32>:
  (sections, result) = observed
  match result:
    case None{}: (replace_sections(w, sections), Fail{MissingSection{section_key(p)}})
    case Some{status}: read_result(replace_sections(w, sections), status)

def read_block(w: World, +p: Position) -> World & Result<&2, &2, Error, U32>:
  World{tick, time, paused, daylight, rev, count, sections, pending, events} = w
  Position{dimension, x, y, z} = p
  read_retained(World{tick, time, paused, daylight, rev, count, M.EmptySections{}, pending, events}, p,
    Read.read(sections, section_key(p), S.Coord.local(x), S.Coord.local(y), S.Coord.local(z)))

def events(w: World) -> World & List<&2, CoreEvent>:
  World{tick, time, paused, daylight, rev, count, sections, pending, +events} = w
  (World{tick, time, paused, daylight, rev, count, sections, pending, events}, events)
