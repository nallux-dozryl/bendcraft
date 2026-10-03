import Base
import ./nbt.bend as N
import ./core.bend as C
import ./schedule.bend as Q
import ./section.bend as S
import ./section_map.bend as M

# This schema saves the complete current foundation World, not Minecraft chunks.
type Limits is Data:
  Limits{nbt: N.Limits, max_sections: U32, max_map_nodes: U32, max_nat_digits: U32, max_string_units: U32}

type Walk is Data:
  Walk{nodes: Nat, count: U32, records: List<&2, Record>}

type Loaded is Type:
  Loaded{world: C.World, max_peer: Maybe<&2, U32>}

type Record is Data:
  Record{key: String, cells: List<&2, U32>}

type Snapshot is Data:
  Snapshot{tick: Nat, day_time: Nat, paused: Bool, daylight: Bool, revision: Nat,
    state_count: U32, sections: List<&2, Record>, pending: List<&2, Q.Pending<C.Mutation>>,
    events: List<&2, C.CoreEvent>, max_peer: Maybe<&2, U32>}

type Field is Data:
  Field{name: String, value: N.Value}

type Both<-A: Data, -B: Data> is Data:
  Both{left: A, right: B}

def default_limits() -> Limits:
  Limits{N.default_limits(), 512, 65536, 15, 65535}











def first(-A: Data, -B: Data, pair: Both<A, B>) -> A:
  Both{a, b} = pair
  a

def second(-A: Data, -B: Data, pair: Both<A, B>) -> B:
  Both{a, b} = pair
  b

def record_key(record: Record) -> String:
  Record{key, cells} = record
  key

def require(ok: Bool, message: String) -> Result<&2, &2, String, Unit>:
  N.choose(Result<&2, &2, String, Unit>, Done{Unit{}}, Fail{message}, ok)

def member_present(names: List<&2, String>, +name: String) -> Bool:
  match names:
    case Nil{}: False{}
    case h <> t: String.eq(h, name) || member_present(t, name)

def text_units(text: String) -> List<&2, U32>:
  match text:
    case SNil{}: []
    case SCon{Chr{+c}, t}:
      +tail = text_units(t)
      N.choose(List<&2, U32>, N.choose(List<&2, U32>, c <> tail, U32.add(55296, U32.shrn(U32.sub(c, 65536), 10n)) <> U32.add(56320, U32.and(U32.sub(c, 65536), 1023)) <> tail, U32.is_lt(c, 65536)), 65536 <> tail, U32.is_le(c, 1114111) && Bool.not(U32.is_ge(c, 55296) && U32.is_le(c, 57343)))

def text(text: String) -> N.Text:
  N.Text{text_units(text)}

def scalar_units(units: List<&2, U32>, +high: U32, +acc: String) -> Result<&2, &2, String, String>:
  match units:
    case Nil{}:
      N.choose(Result<&2, &2, String, String>, Done{String.reverse(acc)}, Fail{"unpaired UTF-16 surrogate in world string"}, U32.is_eq(high, 0))
    case +h <> +rest:
      N.lazy_choose(Result<&2, &2, String, String>, u =>
        N.lazy_choose(Result<&2, &2, String, String>, u => scalar_units(rest, 0, SCon{Chr{U32.add(65536, U32.add(U32.shln(U32.sub(high, 55296), 10n), U32.sub(h, 56320)))}, acc}), u => Fail{"unpaired UTF-16 surrogate in world string"}, U32.is_ge(h, 56320) && U32.is_le(h, 57343)), u =>
        N.lazy_choose(Result<&2, &2, String, String>, u => scalar_units(rest, h, acc), u =>
          N.lazy_choose(Result<&2, &2, String, String>, u => scalar_units(rest, 0, SCon{Chr{h}, acc}), u => Fail{"invalid UTF-16 unit in world string"}, U32.is_le(h, 65535) && Bool.not(U32.is_ge(h, 56320) && U32.is_le(h, 57343))), U32.is_ge(h, 55296) && U32.is_le(h, 56319)), U32.is_ne(high, 0))

def read_text(+limits: Limits, value: N.Text) -> Result<&2, &2, String, String>:
  Limits{nbt, sections, nodes, digits, units_limit} = limits
  N.Text{+units} = value
  do Result<&2, &2, String, String>:
    size : U32 <- N.length_bound(U32, U32.to_nat(units_limit), units, 0)
    scalar_units(units, 0, "")

def string_value(+limits: Limits, value: N.Value) -> Result<&2, &2, String, String>:
  match value:
    case N.StringTag{s}: read_text(limits, s)
    case _: Fail{"expected String tag"}

def int_value(value: N.Value) -> Result<&2, &2, String, U32>:
  match value:
    case N.Int{bits}: Done{bits}
    case _: Fail{"expected Int tag"}

def byte_value(value: N.Value) -> Result<&2, &2, String, U32>:
  match value:
    case N.Byte{bits}: Done{bits}
    case _: Fail{"expected Byte tag"}

def bool_value(value: N.Value) -> Result<&2, &2, String, Bool>:
  match value:
    case N.Byte{0}: Done{False{}}
    case N.Byte{1}: Done{True{}}
    case _: Fail{"expected Boolean Byte 0 or 1"}

def decimal_digits(s: String) -> Bool:
  match s:
    case SNil{}: True{}
    case SCon{Chr{+c}, t}: U32.is_ge(c, 48) && U32.is_le(c, 57) && decimal_digits(t)

def canonical_decimal(+s: String) -> Bool:
  match s:
    case "0": True{}
    case SCon{Chr{+c}, t}: U32.is_ge(c, 49) && U32.is_le(c, 57) && decimal_digits(t)
    case _: False{}

def native_nat_text(+s: String) -> Bool:
  +length = String.length(s)
  Nat.is_lt(length, 15n) || (Nat.is_eq(length, 15n) && String.is_le(s, "281474976710655"))

def nat_read_result(value: Maybe<&2, Nat>) -> Result<&2, &2, String, Nat>:
  match value:
    case Some{n}: Done{n}
    case None{}: Fail{"invalid world Nat"}

def nat_value(+limits: Limits, value: N.Value) -> Result<&2, &2, String, Nat>:
  Limits{nbt, sections, nodes, +digits, units} = limits
  do Result<&2, &2, String, Nat>:
    +s : String <- string_value(Limits{nbt, sections, nodes, digits, units}, value)
    require(canonical_decimal(s), "noncanonical Nat decimal")
    require(Nat.is_le(String.length(s), U32.to_nat(digits)), "world Nat digit limit exceeded")
    require(native_nat_text(s), "world Nat exceeds native 48-bit range")
    nat_read_result(Nat.read(s))

def fields_go(+limits: Limits, members: List<&2, N.Member>, +expected: List<&2, String>, +seen: List<&2, String>, +count: Nat, acc: List<&2, Field>) -> Result<&2, &2, String, List<&2, Field>>:
  match members:
    case Nil{}:
      do Result<&2, &2, String, List<&2, Field>>:
        require(Nat.is_eq(count, List.length(&2, String, expected)), "missing world schema field")
        return acc
    case N.Member{name, value} <> rest:
      do Result<&2, &2, String, List<&2, Field>>:
        +key : String <- read_text(limits, name)
        require(member_present(expected, key), "unknown world schema field: " ++ key)
        require(Bool.not(member_present(seen, key)), "duplicate world schema field: " ++ key)
        fields_go(limits, rest, expected, key <> seen, 1n+count, Field{key, value} <> acc)

def fields(+limits: Limits, value: N.Value, expected: List<&2, String>) -> Result<&2, &2, String, List<&2, Field>>:
  match value:
    case N.Compound{members}: fields_go(limits, members, expected, [], 0n, [])
    case _: Fail{"expected Compound tag"}

def field(values: List<&2, Field>, +name: String) -> N.Value:
  match values:
    case Nil{}: N.End{}
    case Field{+key, +value} <> rest: N.choose(N.Value, value, field(rest, name), String.eq(key, name))

def canonical_u32_result(value: Maybe<&2, U32>) -> Result<&2, &2, String, U32>:
  match value:
    case None{}: Fail{"section coordinate outside U32 range"}
    case Some{+n}:
      do Result<&2, &2, String, U32>:
        require(S.Coord.section_valid(n), "section coordinate outside world coordinate range")
        return n

def canonical_u32(+s: String) -> Result<&2, &2, String, U32>:
  do Result<&2, &2, String, U32>:
    require(canonical_decimal(s), "noncanonical section coordinate")
    canonical_u32_result(U32.read(s))

def section_key_parts(parts: List<&2, String>) -> Result<&2, &2, String, Unit>:
  match parts:
    case +d <> x <> y <> z <> Nil{}:
      do Result<&2, &2, String, Unit>:
        require(C.dimension_known(d), "unknown section dimension")
        a : U32 <- canonical_u32(x)
        b : U32 <- canonical_u32(y)
        c : U32 <- canonical_u32(z)
        return Unit{}
    case _: Fail{"noncanonical section key"}

def section_key(key: String) -> Result<&2, &2, String, Unit>:
  section_key_parts(String.split(key, '/'))

def cells_go(cells: List<&2, U32>, +count: U32, fuel: Nat) -> Result<&2, &2, String, Unit>:
  match cells fuel:
    case Nil{} 0n: Done{Unit{}}
    case +h <> rest 1n+n:
      do Result<&2, &2, String, Unit>:
        require(U32.is_lt(h, count), "section cell state outside registry")
        cells_go(rest, count, n)
    case _ _: Fail{"section must contain exactly 4096 cells"}

def read_record_cells(key: String, count: U32, value: N.Value) -> Result<&2, &2, String, Record>:
  match value:
    case N.IntArray{+cells}:
      do Result<&2, &2, String, Record>:
        cells_go(cells, count, 4096n)
        return Record{key, cells}
    case _: Fail{"section cells require IntArray"}

def read_record(+limits: Limits, count: U32, value: N.Value) -> Result<&2, &2, String, Record>:
  do Result<&2, &2, String, Record>:
    +fs : List<&2, Field> <- fields(limits, value, ["key", "cells"])
    +key : String <- string_value(limits, field(fs, "key"))
    section_key(key)
    read_record_cells(key, count, field(fs, "cells"))

def previous_key(previous: Maybe<&2, String>, key: String) -> Result<&2, &2, String, Unit>:
  match previous:
    case None{}: Done{Unit{}}
    case Some{old}: require(String.is_lt(old, key), "sections must have unique ascending keys")

def read_records_go(+limits: Limits, values: List<&2, N.Value>, +count: U32, fuel: Nat, +previous: Maybe<&2, String>, acc: List<&2, Record>) -> Result<&2, &2, String, List<&2, Record>>:
  match values fuel:
    case Nil{} _: Done{List.reverse(&2, Record, acc)}
    case h <> rest 0n: Fail{"world section limit exceeded"}
    case h <> rest 1n+n:
      do Result<&2, &2, String, List<&2, Record>>:
        +record : Record <- read_record(limits, count, h)
        (
          +key = record_key(record)
          do Result<&2, &2, String, List<&2, Record>>:
            previous_key(previous, key)
            read_records_go(limits, rest, count, n, Some{key}, record <> acc)
        )


def section_limit(+limits: Limits) -> U32:
  Limits{nbt, sections, nodes, digits, units} = limits
  sections

def read_records(+limits: Limits, count: U32, value: N.Value) -> Result<&2, &2, String, List<&2, Record>>:
  match value:
    case N.ListTag{10, values}: read_records_go(limits, values, count, U32.to_nat(section_limit(limits)), None{}, [])
    case _: Fail{"sections require a Compound list"}

def position(+limits: Limits, +count: U32, +fs: List<&2, Field>) -> Result<&2, &2, String, Both<C.Position, U32>>:
  do Result<&2, &2, String, Both<C.Position, U32>>:
    +dimension : String <- string_value(limits, field(fs, "dimension"))
    require(C.dimension_known(dimension), "unknown mutation dimension")
    x : U32 <- int_value(field(fs, "x"))
    y : U32 <- int_value(field(fs, "y"))
    z : U32 <- int_value(field(fs, "z"))
    +state : U32 <- int_value(field(fs, "state"))
    require(U32.is_lt(state, count), "mutation state outside registry")
    return Both{C.Position{dimension, x, y, z}, state}

def kind_members(+limits: Limits, members: List<&2, N.Member>) -> Result<&2, &2, String, U32>:
  match members:
    case Nil{}: Fail{"missing variant kind"}
    case N.Member{name, +value} <> +rest:
      do Result<&2, &2, String, U32>:
        key : String <- read_text(limits, name)
        N.lazy_choose(Result<&2, &2, String, U32>, u => byte_value(value), u => kind_members(limits, rest), String.eq(key, "kind"))

def kind(+limits: Limits, value: N.Value) -> Result<&2, &2, String, U32>:
  match value:
    case N.Compound{members}: kind_members(limits, members)
    case _: Fail{"expected variant Compound"}

def mutation_kind(+limits: Limits, count: U32, +value: N.Value, tag: U32) -> Result<&2, &2, String, C.Mutation>:
  match tag:
    case 0:
      do Result<&2, &2, String, C.Mutation>:
        fs : List<&2, Field> <- fields(limits, value, ["kind", "dimension", "x", "y", "z", "state"])
        +ps : Both<C.Position, U32> <- position(limits, count, fs)
        return C.SectionCreate{first(C.Position, U32, ps), second(C.Position, U32, ps)}
    case 1:
      do Result<&2, &2, String, C.Mutation>:
        fs : List<&2, Field> <- fields(limits, value, ["kind", "dimension", "x", "y", "z", "state"])
        +ps : Both<C.Position, U32> <- position(limits, count, fs)
        return C.BlockSet{first(C.Position, U32, ps), second(C.Position, U32, ps)}
    case 2:
      do Result<&2, &2, String, C.Mutation>:
        fs : List<&2, Field> <- fields(limits, value, ["kind", "day_time"])
        time : Nat <- nat_value(limits, field(fs, "day_time"))
        return C.TimeSet{time}
    case 3:
      do Result<&2, &2, String, C.Mutation>:
        fs : List<&2, Field> <- fields(limits, value, ["kind", "enabled"])
        enabled : Bool <- bool_value(field(fs, "enabled"))
        return C.DaylightSet{enabled}
    case _: Fail{"unknown mutation kind"}


def mutation(+limits: Limits, count: U32, +value: N.Value) -> Result<&2, &2, String, C.Mutation>:
  do Result<&2, &2, String, C.Mutation>:
    tag : U32 <- kind(limits, value)
    mutation_kind(limits, count, value, tag)

def stamp(+limits: Limits, +fs: List<&2, Field>) -> Result<&2, &2, String, Q.Stamp>:
  do Result<&2, &2, String, Q.Stamp>:
    tick : Nat <- nat_value(limits, field(fs, "tick"))
    peer : U32 <- int_value(field(fs, "peer"))
    sequence : Nat <- nat_value(limits, field(fs, "sequence"))
    return Q.Stamp{tick, peer, sequence}

def read_pending(+limits: Limits, count: U32, value: N.Value) -> Result<&2, &2, String, Q.Pending<C.Mutation>>:
  do Result<&2, &2, String, Q.Pending<C.Mutation>>:
    +fs : List<&2, Field> <- fields(limits, value, ["tick", "peer", "sequence", "mutation"])
    mark : Q.Stamp <- stamp(limits, fs)
    operation : C.Mutation <- mutation(limits, count, field(fs, "mutation"))
    return Q.Pending{mark, operation}

def cmp_le(cmp: Cmp) -> Bool:
  match cmp:
    case GT{}: False{}
    case _: True{}

def compare_le(a: Q.Stamp, b: Q.Stamp) -> Bool:
  cmp_le(Q.compare(a, b))

def previous_stamp(previous: Maybe<&2, Q.Stamp>, +mark: Q.Stamp, ascending: Bool) -> Result<&2, &2, String, Unit>:
  match previous:
    case None{}: Done{Unit{}}
    case Some{+old}: require(N.choose(Bool, compare_le(old, mark), compare_le(mark, old), ascending), "world stamp order invalid")

def peer_max(old: Maybe<&2, U32>, peer: U32) -> Maybe<&2, U32>:
  match old:
    case None{}: Some{peer}
    case Some{p}: Some{U32.max(p, peer)}

def pending_go(+limits: Limits, values: List<&2, N.Value>, +count: U32, +tick: Nat, fuel: Nat, +previous: Maybe<&2, Q.Stamp>, +high: Maybe<&2, U32>, acc: List<&2, Q.Pending<C.Mutation>>) -> Result<&2, &2, String, Both<List<&2, Q.Pending<C.Mutation>>, Maybe<&2, U32>>>:
  match values fuel:
    case Nil{} _: Done{Both{List.reverse(&2, Q.Pending<C.Mutation>, acc), high}}
    case h <> rest 0n: Fail{"pending capacity exceeded"}
    case h <> rest 1n+n:
      do Result<&2, &2, String, Both<List<&2, Q.Pending<C.Mutation>>, Maybe<&2, U32>>>:
        +p : Q.Pending<C.Mutation> <- read_pending(limits, count, h)
        (
          +mark = Q.pending_stamp(C.Mutation, p)
          do Result<&2, &2, String, Both<List<&2, Q.Pending<C.Mutation>>, Maybe<&2, U32>>>:
            require(Nat.is_gt(Q.stamp_tick(mark), tick), "pending stamp must be in the future")
            previous_stamp(previous, mark, True{})
            pending_go(limits, rest, count, tick, n, Some{mark}, peer_max(high, Q.stamp_peer(mark)), p <> acc)
        )


def pending(+limits: Limits, count: U32, tick: Nat, value: N.Value) -> Result<&2, &2, String, Both<List<&2, Q.Pending<C.Mutation>>, Maybe<&2, U32>>>:
  match value:
    case N.ListTag{10, values}: pending_go(limits, values, count, tick, 4096n, None{}, None{}, [])
    case _: Fail{"pending requires a Compound list"}

def core_error_kind(+limits: Limits, +value: N.Value, tag: U32) -> Result<&2, &2, String, C.Error>:
  match tag:
    case 0:
      do Result<&2, &2, String, C.Error>:
        fs : List<&2, Field> <- fields(limits, value, ["kind"])
        return C.PermissionDenied{}
    case 1:
      do Result<&2, &2, String, C.Error>:
        fs : List<&2, Field> <- fields(limits, value, ["kind", "dimension"])
        d : String <- string_value(limits, field(fs, "dimension"))
        return C.UnknownDimension{d}
    case 2:
      do Result<&2, &2, String, C.Error>:
        fs : List<&2, Field> <- fields(limits, value, ["kind", "state"])
        state : U32 <- int_value(field(fs, "state"))
        return C.InvalidState{state}
    case 3:
      do Result<&2, &2, String, C.Error>:
        fs : List<&2, Field> <- fields(limits, value, ["kind", "key"])
        +key : String <- string_value(limits, field(fs, "key"))
        section_key(key)
        return C.MissingSection{key}
    case 4:
      do Result<&2, &2, String, C.Error>:
        fs : List<&2, Field> <- fields(limits, value, ["kind", "key"])
        +key : String <- string_value(limits, field(fs, "key"))
        section_key(key)
        return C.SectionExists{key}
    case 5:
      do Result<&2, &2, String, C.Error>:
        fs : List<&2, Field> <- fields(limits, value, ["kind"])
        return C.InvalidCoordinate{}
    case 6:
      do Result<&2, &2, String, C.Error>:
        fs : List<&2, Field> <- fields(limits, value, ["kind"])
        return C.PastTick{}
    case 7:
      do Result<&2, &2, String, C.Error>:
        fs : List<&2, Field> <- fields(limits, value, ["kind"])
        return C.TooManyPending{}
    case _: Fail{"unknown core error kind"}


def core_error(+limits: Limits, +value: N.Value) -> Result<&2, &2, String, C.Error>:
  do Result<&2, &2, String, C.Error>:
    tag : U32 <- kind(limits, value)
    core_error_kind(limits, value, tag)

def event_kind(+limits: Limits, +value: N.Value, tag: U32) -> Result<&2, &2, String, C.CoreEvent>:
  match tag:
    case 0:
      do Result<&2, &2, String, C.CoreEvent>:
        +fs : List<&2, Field> <- fields(limits, value, ["tick", "peer", "sequence", "kind", "revision"])
        mark : Q.Stamp <- stamp(limits, fs)
        revision : Nat <- nat_value(limits, field(fs, "revision"))
        return C.Applied{mark, revision}
    case 1:
      do Result<&2, &2, String, C.CoreEvent>:
        +fs : List<&2, Field> <- fields(limits, value, ["tick", "peer", "sequence", "kind", "error"])
        mark : Q.Stamp <- stamp(limits, fs)
        error : C.Error <- core_error(limits, field(fs, "error"))
        return C.Rejected{mark, error}
    case _: Fail{"unknown event kind"}


def event(+limits: Limits, +value: N.Value) -> Result<&2, &2, String, C.CoreEvent>:
  do Result<&2, &2, String, C.CoreEvent>:
    tag : U32 <- kind(limits, value)
    event_kind(limits, value, tag)

def event_stamp(event: C.CoreEvent) -> Q.Stamp:
  match event:
    case C.Applied{mark, rev}: mark
    case C.Rejected{mark, error}: mark

def event_revision(event: C.CoreEvent, revision: Nat, previous: Maybe<&2, Nat>) -> Result<&2, &2, String, Maybe<&2, Nat>>:
  match event:
    case C.Rejected{mark, error}: Done{previous}
    case C.Applied{mark, +r}:
      do Result<&2, &2, String, Maybe<&2, Nat>>:
        require(Nat.is_gt(r, 0n) && Nat.is_le(r, revision), "event revision outside world revision")
        return Some{r}

def events_go(+limits: Limits, values: List<&2, N.Value>, +tick: Nat, +revision: Nat, fuel: Nat, +previous: Maybe<&2, Q.Stamp>, +previous_revision: Maybe<&2, Nat>, +high: Maybe<&2, U32>, acc: List<&2, C.CoreEvent>) -> Result<&2, &2, String, Both<List<&2, C.CoreEvent>, Maybe<&2, U32>>>:
  match values fuel:
    case Nil{} _: Done{Both{List.reverse(&2, C.CoreEvent, acc), high}}
    case h <> rest 0n: Fail{"event ring capacity exceeded"}
    case h <> rest 1n+n:
      do Result<&2, &2, String, Both<List<&2, C.CoreEvent>, Maybe<&2, U32>>>:
        +ev : C.CoreEvent <- event(limits, h)
        (
          +mark = event_stamp(ev)
          do Result<&2, &2, String, Both<List<&2, C.CoreEvent>, Maybe<&2, U32>>>:
            require(Nat.is_le(Q.stamp_tick(mark), tick), "event stamp is in the future")
            previous_stamp(previous, mark, False{})
            prior : Maybe<&2, Nat> <- event_revision(ev, revision, previous_revision)
            events_go(limits, rest, tick, revision, n, Some{mark}, prior, peer_max(high, Q.stamp_peer(mark)), ev <> acc)
        )


def events(+limits: Limits, tick: Nat, revision: Nat, high: Maybe<&2, U32>, value: N.Value) -> Result<&2, &2, String, Both<List<&2, C.CoreEvent>, Maybe<&2, U32>>>:
  match value:
    case N.ListTag{10, values}: events_go(limits, values, tick, revision, 1024n, None{}, None{}, high, [])
    case _: Fail{"events require a Compound list"}

def snapshot(+limits: Limits, root: N.Root, +expected_count: U32, +expected_registry: String) -> Result<&2, &2, String, Snapshot>:
  N.Root{name, value} = root
  do Result<&2, &2, String, Snapshot>:
    root_name : String <- read_text(limits, name)
    require(String.eq(root_name, "bendex:world"), "wrong world root name")
    +fs : List<&2, Field> <- fields(limits, value, ["format", "minecraft", "registry", "state_count", "tick", "day_time", "paused", "daylight", "revision", "sections", "pending", "events"])
    version : U32 <- int_value(field(fs, "format"))
    require(U32.is_eq(version, 1), "unsupported world format version")
    minecraft : String <- string_value(limits, field(fs, "minecraft"))
    require(String.eq(minecraft, "26.3"), "world Minecraft version mismatch")
    registry : String <- string_value(limits, field(fs, "registry"))
    require(String.eq(registry, expected_registry), "world registry identity mismatch")
    +count : U32 <- int_value(field(fs, "state_count"))
    require(U32.is_eq(count, expected_count), "world state count mismatch")
    +tick : Nat <- nat_value(limits, field(fs, "tick"))
    time : Nat <- nat_value(limits, field(fs, "day_time"))
    paused : Bool <- bool_value(field(fs, "paused"))
    daylight : Bool <- bool_value(field(fs, "daylight"))
    +revision : Nat <- nat_value(limits, field(fs, "revision"))
    sections : List<&2, Record> <- read_records(limits, count, field(fs, "sections"))
    +queued : Both<List<&2, Q.Pending<C.Mutation>>, Maybe<&2, U32>> <- pending(limits, count, tick, field(fs, "pending"))
    +history : Both<List<&2, C.CoreEvent>, Maybe<&2, U32>> <- events(limits, tick, revision, second(List<&2, Q.Pending<C.Mutation>>, Maybe<&2, U32>, queued), field(fs, "events"))
    return Snapshot{tick, time, paused, daylight, revision, count, sections,
      first(List<&2, Q.Pending<C.Mutation>>, Maybe<&2, U32>, queued),
      first(List<&2, C.CoreEvent>, Maybe<&2, U32>, history), second(List<&2, C.CoreEvent>, Maybe<&2, U32>, history)}

# Validate the exact balanced Array layout before any indexed access.
def join_cells(a: Result<&2, &2, String, List<&2, U32>>, b: Result<&2, &2, String, List<&2, U32>>) -> Result<&2, &2, String, List<&2, U32>>:
  match a b:
    case Fail{message} _: Fail{message}
    case Done{xs} Fail{message}: Fail{message}
    case Done{xs} Done{ys}: Done{List.append(&2, U32, xs, ys)}

def array_join(a: Array<U32> & Result<&2, &2, String, List<&2, U32>>, b: Array<U32> & Result<&2, &2, String, List<&2, U32>>) -> Array<U32> & Result<&2, &2, String, List<&2, U32>>:
  (xs, left) = a
  (ys, right) = b
  (ANode{xs, ys}, join_cells(left, right))

def array_cells(depth: Nat, blocks: Array<U32>, +count: U32) -> Array<U32> & Result<&2, &2, String, List<&2, U32>>:
  match depth blocks:
    case 0n ALeaf{+value}:
      (ALeaf{value}, N.choose(Result<&2, &2, String, List<&2, U32>>, Done{value <> Nil{}}, Fail{"section cell state outside registry"}, U32.is_lt(value, count)))
    case 1n+ +d ANode{left, right}:
      array_join(array_cells(d, left, count), array_cells(d, right, count))
    case _ other: (other, Fail{"malformed owned section Array layout"})

def section_cells_result(r: Array<U32> & Result<&2, &2, String, List<&2, U32>>) -> S.Section & Result<&2, &2, String, List<&2, U32>>:
  (blocks, result) = r
  (S.Section{blocks}, result)

def section_cells(section: S.Section, count: U32) -> S.Section & Result<&2, &2, String, List<&2, U32>>:
  S.Section{blocks} = section
  section_cells_result(array_cells(12n, blocks, count))



def add_record(+limits: Limits, state: Walk, +key: String, cells: List<&2, U32>) -> Result<&2, &2, String, Walk>:
  Walk{nodes, +count, records} = state
  do Result<&2, &2, String, Walk>:
    require(U32.is_lt(count, section_limit(limits)), "world section limit exceeded")
    return Walk{nodes, U32.add(count, 1), Record{key, cells} <> records}

def bucket_prepend(head: M.Entry, r: List<&1, M.Entry> & Result<&2, &2, String, Walk>) -> List<&1, M.Entry> & Result<&2, &2, String, Walk>:
  (tail, result) = r
  (head <> tail, result)

def bucket_step(key: String, section: S.Section, rest: List<&1, M.Entry>, checked: Result<&2, &2, String, Unit>, work: Unit -> S.Section -> List<&1, M.Entry> -> List<&1, M.Entry> & Result<&2, &2, String, Walk>) -> List<&1, M.Entry> & Result<&2, &2, String, Walk>:
  match checked:
    case Fail{message}: (M.Entry{key, section} <> rest, Fail{message})
    case Done{unit}: work(Unit{}, section, rest)

def bucket_state(head: M.Entry, state: Result<&2, &2, String, Walk>, rest: List<&1, M.Entry>, next: Walk -> List<&1, M.Entry> -> List<&1, M.Entry> & Result<&2, &2, String, Walk>) -> List<&1, M.Entry> & Result<&2, &2, String, Walk>:
  match state:
    case Fail{message}: (head <> rest, Fail{message})
    case Done{walk}: bucket_prepend(head, next(walk, rest))

def map_bucket(r: List<&1, M.Entry> & Result<&2, &2, String, Walk>) -> M.Sections & Result<&2, &2, String, Walk>:
  (entries, result) = r
  (M.Bucket{entries}, result)

def map_hi(lo: M.Sections, r: M.Sections & Result<&2, &2, String, Walk>) -> M.Sections & Result<&2, &2, String, Walk>:
  (hi, result) = r
  (M.Branch{lo, hi}, result)

def map_lo(hi: M.Sections, r: M.Sections & Result<&2, &2, String, Walk>, next: M.Sections -> Walk -> M.Sections & Result<&2, &2, String, Walk>) -> M.Sections & Result<&2, &2, String, Walk>:
  (lo, result) = r
  match result:
    case Fail{message}: (M.Branch{lo, hi}, Fail{message})
    case Done{state}: map_hi(lo, next(hi, state))

def record_before(a: Record, b: Record) -> Bool:
  String.is_lt(record_key(a), record_key(b))

def walked(result: Result<&2, &2, String, Walk>) -> Result<&2, &2, String, List<&2, Record>>:
  match result:
    case Fail{message}: Fail{message}
    case Done{Walk{nodes, count, records}}: Done{List.sort(~Record, ~record_before, records)}

# Assemble owned arrays only after every decoded field has been validated.
def fill_cells(cells: List<&2, U32>, +index: U32, blocks: Array<U32>) -> Array<U32>:
  match cells:
    case Nil{}: blocks
    case value <> rest: fill_cells(rest, U32.add(index, 1), Array.set(U32, blocks, index, value))

def install_records(records: List<&2, Record>, sections: M.Sections) -> M.Sections:
  match records:
    case Nil{}: sections
    case Record{key, cells} <> rest:
      install_records(rest, M.set(sections, key, S.Section{fill_cells(cells, 0, [0 : U32 * 4096n])}))

def loaded(snapshot: Snapshot) -> Loaded:
  Snapshot{tick, time, paused, daylight, revision, count, records, pending, events, max_peer} = snapshot
  Loaded{C.World{tick, time, paused, daylight, revision, count, install_records(records, M.EmptySections{}), pending, events}, max_peer}

def decoded_snapshot(result: Result<&2, &2, String, Snapshot>) -> Result<&2, &1, String, Loaded>:
  match result:
    case Fail{message}: Fail{message}
    case Done{snapshot}: Done{loaded(snapshot)}

def decode_root(limits: Limits, root: Result<&2, &2, String, N.Root>, count: U32, registry: String) -> Result<&2, &1, String, Loaded>:
  match root:
    case Fail{message}: Fail{message}
    case Done{value}: decoded_snapshot(snapshot(limits, value, count, registry))

def nbt_limits(limits: Limits) -> N.Limits:
  Limits{nbt, sections, nodes, digits, units} = limits
  nbt

def map_limit(limits: Limits) -> U32:
  Limits{nbt, sections, nodes, digits, units} = limits
  nodes

def decode_with(+limits: Limits, bytes: List<&2, U32>, count: U32, registry: String) -> Result<&2, &1, String, Loaded>:
  decode_root(limits, N.decode_with(nbt_limits(limits), bytes), count, registry)

def decode(bytes: List<&2, U32>, count: U32, registry: String) -> Result<&2, &1, String, Loaded>:
  decode_with(default_limits(), bytes, count, registry)
def bucket_cells(+limits: Limits, +key: String, r: S.Section & Result<&2, &2, String, List<&2, U32>>, +state: Walk, rest: List<&1, M.Entry>, next: Walk -> List<&1, M.Entry> -> List<&1, M.Entry> & Result<&2, &2, String, Walk>) -> List<&1, M.Entry> & Result<&2, &2, String, Walk>:
  (section, cells) = r
  match cells:
    case Fail{message}: (M.Entry{key, section} <> rest, Fail{message})
    case Done{values}: bucket_state(M.Entry{key, section}, add_record(limits, state, key, values), rest, next)

def bucket_key(+limits: Limits, +key: String, section: S.Section, rest: List<&1, M.Entry>, valid: Result<&2, &2, String, Unit>, state: Walk, count: U32, next: Walk -> List<&1, M.Entry> -> List<&1, M.Entry> & Result<&2, &2, String, Walk>) -> List<&1, M.Entry> & Result<&2, &2, String, Walk>:
  match valid:
    case Fail{message}: (M.Entry{key, section} <> rest, Fail{message})
    case Done{unit}: bucket_cells(limits, key, section_cells(section, count), state, rest, next)

def bucket_walk(fuel: Nat, +limits: Limits, entries: List<&1, M.Entry>, +path: U32, +count: U32, state: Walk) -> List<&1, M.Entry> & Result<&2, &2, String, Walk>:
  match fuel entries:
    case _ Nil{}: ([], Done{state})
    case 0n original: (original, Fail{"world section limit exceeded"})
    case 1n+n M.Entry{+key, section} <> rest:
      bucket_step(key, section, rest, require(U32.is_eq(M.hash(key), path), "owned section is stored under the wrong hash path"),
        u => section => rest => bucket_key(limits, key, section, rest, section_key(key), state, count,
          state => rest => bucket_walk(n, limits, rest, path, count, state)))

def map_walk(+limits: Limits, depth: Nat, sections: M.Sections, +path: U32, +power: U32, +count: U32, state: Walk) -> M.Sections & Result<&2, &2, String, Walk>:
  match depth sections state:
    case _ original Walk{0n, amount, records}: (original, Fail{"owned map node limit exceeded"})
    case _ M.EmptySections{} Walk{1n+fuel, amount, records}: (M.EmptySections{}, Done{Walk{fuel, amount, records}})
    case 0n M.Bucket{Nil{}} Walk{1n+fuel, amount, records}: (M.Bucket{Nil{}}, Fail{"owned section map has an empty bucket"})
    case 0n M.Bucket{entries} Walk{1n+fuel, amount, records}: map_bucket(bucket_walk(U32.to_nat(section_limit(limits)), limits, entries, path, count, Walk{fuel, amount, records}))
    case 1n+ +d M.Branch{lo, hi} Walk{1n+fuel, amount, records}:
      map_lo(hi, map_walk(limits, d, lo, path, U32.shl(power), count, Walk{fuel, amount, records}),
        hi => state => map_walk(limits, d, hi, U32.or(path, power), U32.shl(power), count, state))
    case _ other Walk{1n+fuel, amount, records}: (other, Fail{"malformed owned section map layout"})

# Serialization uses a deterministic key order, independent of collision bucket order.

# All world text is scalar Unicode; NBT Text itself preserves arbitrary UTF-16.
def string_tag(s: String) -> N.Value:
  N.StringTag{text(s)}

def nat_tag(n: Nat) -> N.Value:
  string_tag(Nat.show(n))

def bool_tag(b: Bool) -> N.Value:
  match b:
    case False{}: N.Byte{0}
    case True{}: N.Byte{1}

def named(name: String, value: N.Value) -> N.Member:
  N.Member{text(name), value}

def record_value(record: Record) -> N.Value:
  Record{key, cells} = record
  N.Compound{[named("key", string_tag(key)), named("cells", N.IntArray{cells})]}

def record_values(records: List<&2, Record>) -> List<&2, N.Value>:
  match records:
    case Nil{}: []
    case h <> t: record_value(h) <> record_values(t)

def position_members(tag: U32, position: C.Position, state: U32) -> List<&2, N.Member>:
  C.Position{dimension, x, y, z} = position
  [named("kind", N.Byte{tag}), named("dimension", string_tag(dimension)), named("x", N.Int{x}), named("y", N.Int{y}), named("z", N.Int{z}), named("state", N.Int{state})]

def mutation_value(mutation: C.Mutation) -> N.Value:
  match mutation:
    case C.SectionCreate{position, fill}: N.Compound{position_members(0, position, fill)}
    case C.BlockSet{position, state}: N.Compound{position_members(1, position, state)}
    case C.TimeSet{time}: N.Compound{[named("kind", N.Byte{2}), named("day_time", nat_tag(time))]}
    case C.DaylightSet{enabled}: N.Compound{[named("kind", N.Byte{3}), named("enabled", bool_tag(enabled))]}

def stamp_members(stamp: Q.Stamp) -> List<&2, N.Member>:
  Q.Stamp{tick, peer, sequence} = stamp
  [named("tick", nat_tag(tick)), named("peer", N.Int{peer}), named("sequence", nat_tag(sequence))]

def pending_value(p: Q.Pending<C.Mutation>) -> N.Value:
  Q.Pending{stamp, operation} = p
  N.Compound{List.append(&2, N.Member, stamp_members(stamp), [named("mutation", mutation_value(operation))])}

def pending_values(pending: List<&2, Q.Pending<C.Mutation>>) -> List<&2, N.Value>:
  match pending:
    case Nil{}: []
    case h <> t: pending_value(h) <> pending_values(t)

def error_value(error: C.Error) -> N.Value:
  match error:
    case C.PermissionDenied{}: N.Compound{[named("kind", N.Byte{0})]}
    case C.UnknownDimension{dimension}: N.Compound{[named("kind", N.Byte{1}), named("dimension", string_tag(dimension))]}
    case C.InvalidState{state}: N.Compound{[named("kind", N.Byte{2}), named("state", N.Int{state})]}
    case C.MissingSection{key}: N.Compound{[named("kind", N.Byte{3}), named("key", string_tag(key))]}
    case C.SectionExists{key}: N.Compound{[named("kind", N.Byte{4}), named("key", string_tag(key))]}
    case C.InvalidCoordinate{}: N.Compound{[named("kind", N.Byte{5})]}
    case C.PastTick{}: N.Compound{[named("kind", N.Byte{6})]}
    case C.TooManyPending{}: N.Compound{[named("kind", N.Byte{7})]}

def event_value(event: C.CoreEvent) -> N.Value:
  match event:
    case C.Applied{stamp, revision}: N.Compound{List.append(&2, N.Member, stamp_members(stamp), [named("kind", N.Byte{0}), named("revision", nat_tag(revision))])}
    case C.Rejected{stamp, error}: N.Compound{List.append(&2, N.Member, stamp_members(stamp), [named("kind", N.Byte{1}), named("error", error_value(error))])}

def event_values(events: List<&2, C.CoreEvent>) -> List<&2, N.Value>:
  match events:
    case Nil{}: []
    case h <> t: event_value(h) <> event_values(t)

def root(registry: String, tick: Nat, time: Nat, paused: Bool, daylight: Bool, revision: Nat, count: U32, records: List<&2, Record>, pending: List<&2, Q.Pending<C.Mutation>>, events: List<&2, C.CoreEvent>) -> N.Root:
  N.Root{text("bendex:world"), N.Compound{[
    named("format", N.Int{1}), named("minecraft", string_tag("26.3")), named("registry", string_tag(registry)), named("state_count", N.Int{count}),
    named("tick", nat_tag(tick)), named("day_time", nat_tag(time)), named("paused", bool_tag(paused)), named("daylight", bool_tag(daylight)), named("revision", nat_tag(revision)),
    named("sections", N.ListTag{10, record_values(records)}), named("pending", N.ListTag{10, pending_values(pending)}), named("events", N.ListTag{10, event_values(events)})]}}

def encode_verified(+limits: Limits, root: N.Root, result: Result<&2, &2, String, Snapshot>) -> Result<&2, &2, String, List<&2, U32>>:
  match result:
    case Fail{message}: Fail{message}
    case Done{snapshot}: N.encode_with(nbt_limits(limits), root)

def encode_records(+limits: Limits, +registry: String, tick: Nat, time: Nat, paused: Bool, daylight: Bool, revision: Nat, +count: U32, records: Result<&2, &2, String, List<&2, Record>>, pending: List<&2, Q.Pending<C.Mutation>>, events: List<&2, C.CoreEvent>) -> Result<&2, &2, String, List<&2, U32>>:
  match records:
    case Fail{message}: Fail{message}
    case Done{values}:
      +value = root(registry, tick, time, paused, daylight, revision, count, values, pending, events)
      encode_verified(limits, value, snapshot(limits, value, count, registry))

def encode_mapped(+limits: Limits, registry: String, +tick: Nat, +time: Nat, +paused: Bool, +daylight: Bool, +revision: Nat, +count: U32, +pending: List<&2, Q.Pending<C.Mutation>>, +events: List<&2, C.CoreEvent>, r: M.Sections & Result<&2, &2, String, Walk>) -> C.World & Result<&2, &2, String, List<&2, U32>>:
  (sections, walked_result) = r
  (C.World{tick, time, paused, daylight, revision, count, sections, pending, events}, encode_records(limits, registry, tick, time, paused, daylight, revision, count, walked(walked_result), pending, events))

def encode_with(+limits: Limits, world: C.World, registry: String) -> C.World & Result<&2, &2, String, List<&2, U32>>:
  C.World{tick, time, paused, daylight, revision, +count, sections, pending, events} = world
  encode_mapped(limits, registry, tick, time, paused, daylight, revision, count, pending, events,
    map_walk(limits, 32n, sections, 0, 1, count, Walk{U32.to_nat(map_limit(limits)), 0, []}))

def encode(world: C.World, registry: String) -> C.World & Result<&2, &2, String, List<&2, U32>>:
  encode_with(default_limits(), world, registry)
