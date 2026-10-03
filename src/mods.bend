import Base
import ./json.bend as J

# Own mod API semantics; no Java mod-loader compatibility is implied.
type Version is Data:
  Version{major: U32, minor: U32, patch: U32}

type Bound is Data:
  Bound{version: Version, inclusive: Bool}

type Range is Data:
  Range{minimum: Maybe<&2, Bound>, maximum: Maybe<&2, Bound>}

type Dependency is Data:
  Dependency{id: String, range: Range}

type Side is Data:
  Client{}
  Server{}
  Both{}

type Reload is Data:
  Safe{}
  Restart{}

type Manifest is Data:
  Manifest{id: String, version: Version, api_version: Version, side: Side,
    dependencies: List<&2, Dependency>, before: List<&2, String>, after: List<&2, String>,
    operations: List<&2, String>, queries: List<&2, String>, events: List<&2, String>,
    data_version: U32, reload: Reload}

type MatchReport is Data:
  MatchReport{client_order: List<&2, String>, server_order: List<&2, String>, shared: List<&2, String>}

type ReloadClass is Data:
  NoChange{}
  SafeCandidate{}
  RestartRequired{}
  Incompatible{}

type ReloadReport is Data:
  ReloadReport{classification: ReloadClass, reasons: List<&2, String>, execution_verified: Bool}

def names_have(names: List<&2, String>, +name: String) -> Bool:
  match names:
    case Nil{}: False{}
    case h <> t: String.eq(h, name) || names_have(t, name)

def unique(names: List<&2, String>) -> Bool:
  match names:
    case Nil{}: True{}
    case +h <> +t: Bool.not(names_have(t, h)) && unique(t)

def members_have(members: List<&2, J.Member>, +name: String) -> Bool:
  match members:
    case Nil{}: False{}
    case J.JMember{k, v} <> t: String.eq(k, name) || members_have(t, name)

def keys_valid(members: List<&2, J.Member>, +allowed: List<&2, String>) -> Bool:
  match members:
    case Nil{}: True{}
    case J.JMember{+k, v} <> +t:
      names_have(allowed, k) && Bool.not(members_have(t, k)) && keys_valid(t, allowed)

def object_valid(value: J.Value, allowed: List<&2, String>) -> Bool:
  match value:
    case J.JObject{members}: keys_valid(members, allowed)
    case _: False{}

def alphanumeric(+c: U32) -> Bool:
  (U32.is_ge(c, 97) && U32.is_le(c, 122)) || J.digit(c)

def namespace_char(+c: U32) -> Bool:
  alphanumeric(c) || U32.is_eq(c, 95) || U32.is_eq(c, 45) || U32.is_eq(c, 46)

def id_tail(text: String, +colon_seen: Bool, part_nonempty: Bool) -> Bool:
  match text:
    case SNil{}: colon_seen && part_nonempty
    case SCon{Chr{+c}, t}:
      match c:
        case 58: Bool.not(colon_seen) && part_nonempty && id_tail(t, True{}, False{})
        case _: (namespace_char(c) || (colon_seen && U32.is_eq(c, 47))) && id_tail(t, colon_seen, True{})

def valid_id(+id: String) -> Bool:
  J.within(128n, id) && id_tail(id, False{}, False{})

def symbol_tail(text: String) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{+c}, t}:
      (namespace_char(c) || (U32.is_ge(c, 65) && U32.is_le(c, 90)) || U32.is_eq(c, 58) || U32.is_eq(c, 47)) && symbol_tail(t)

def valid_symbol(+name: String) -> Bool:
  Bool.not(String.is_empty(name)) && J.within(128n, name) && symbol_tail(name)

def version_tail(second: Cmp, apat: U32, bpat: U32) -> Cmp:
  match second:
    case EQ{}: U32.cmp(apat, bpat)
    case other: other

def version_major(first: Cmp, amin: U32, bmin: U32, apat: U32, bpat: U32) -> Cmp:
  match first:
    case EQ{}: version_tail(U32.cmp(amin, bmin), apat, bpat)
    case other: other

def compare(a: Version, b: Version) -> Cmp:
  match a b:
    case Version{am, ai, ap} Version{bm, bi, bp}: version_major(U32.cmp(am, bm), ai, bi, ap, bp)

def version_eq(a: Version, b: Version) -> Bool:
  Cmp.is_eq(compare(a, b))

def version_show(version: Version) -> String:
  match version:
    case Version{major, minor, patch}: U32.show(major) ++ "." ++ U32.show(minor) ++ "." ++ U32.show(patch)


def side_eq(a: Side, b: Side) -> Bool:
  match a b:
    case Client{} Client{}: True{}
    case Server{} Server{}: True{}
    case Both{} Both{}: True{}
    case _ _: False{}

def covers(provider: Side, consumer: Side) -> Bool:
  match provider consumer:
    case Both{} _: True{}
    case Client{} Client{}: True{}
    case Server{} Server{}: True{}
    case _ _: False{}

def side_name(side: Side) -> String:
  match side:
    case Client{}: "client"
    case Server{}: "server"
    case Both{}: "both"

def lower_bound(bound: Maybe<&2, Bound>, +version: Version) -> Bool:
  match bound:
    case None{}: True{}
    case Some{Bound{+minimum, inclusive}}:
      Cmp.is_gt(compare(version, minimum)) || (inclusive && version_eq(version, minimum))

def upper_bound(bound: Maybe<&2, Bound>, +version: Version) -> Bool:
  match bound:
    case None{}: True{}
    case Some{Bound{+maximum, inclusive}}:
      Cmp.is_lt(compare(version, maximum)) || (inclusive && version_eq(version, maximum))

def contains(range: Range, +version: Version) -> Bool:
  match range:
    case Range{minimum, maximum}: lower_bound(minimum, version) && upper_bound(maximum, version)

def valid_range(range: Range) -> Bool:
  match range:
    case Range{Some{Bound{+lo, li}}, Some{Bound{+hi, ui}}}:
      Cmp.is_lt(compare(lo, hi)) || (version_eq(lo, hi) && li && ui)
    case _: True{}

def number(found: Maybe<&2, U32>, name: String) -> Result<&2, &2, String, U32>:
  match found:
    case Some{n}: Done{n}
    case None{}: Fail{"InvalidManifest: unsigned integer required for " ++ name}

def string_field(found: Maybe<&2, J.Value>, name: String) -> Result<&2, &2, String, String>:
  match found:
    case Some{J.JString{s}}: Done{s}
    case _: Fail{"InvalidManifest: string required for " ++ name}

def get_string(+value: J.Value, +name: String) -> Result<&2, &2, String, String>:
  string_field(J.member(value, name), name)

def uint_field(found: Maybe<&2, J.Value>, name: String) -> Result<&2, &2, String, U32>:
  match found:
    case Some{value}: number(J.as_u32(value), name)
    case None{}: Fail{"InvalidManifest: missing " ++ name}

def get_uint(+value: J.Value, +name: String) -> Result<&2, &2, String, U32>:
  uint_field(J.member(value, name), name)

def version_strings(parts: List<&2, String>) -> Result<&2, &2, String, Version>:
  match parts:
    case a <> b <> c <> Nil{}:
      do Result<&2, &2, String, Version>:
        major : U32 <- number(J.u32_lexeme(a), "version.major")
        minor : U32 <- number(J.u32_lexeme(b), "version.minor")
        patch : U32 <- number(J.u32_lexeme(c), "version.patch")
        return Version{major, minor, patch}
    case _: Fail{"InvalidManifest: version must have exactly three unsigned components"}

def parse_version(value: J.Value) -> Result<&2, &2, String, Version>:
  match value:
    case J.JString{s}: version_strings(String.split(s, '.'))
    case J.JArray{a <> b <> c <> Nil{}}:
      do Result<&2, &2, String, Version>:
        major : U32 <- number(J.as_u32(a), "version.major")
        minor : U32 <- number(J.as_u32(b), "version.minor")
        patch : U32 <- number(J.as_u32(c), "version.patch")
        return Version{major, minor, patch}
    case _: Fail{"InvalidManifest: version must be a triple or a core version string"}

def version_field(found: Maybe<&2, J.Value>) -> Result<&2, &2, String, Version>:
  match found:
    case Some{v}: parse_version(v)
    case None{}: Fail{"InvalidManifest: version/api_version missing"}

def bool_field(found: Maybe<&2, J.Value>) -> Result<&2, &2, String, Bool>:
  match found:
    case Some{J.JBool{b}}: Done{b}
    case _: Fail{"InvalidManifest: bound inclusive must be a boolean"}

def bound_checked(+value: J.Value, valid: Bool) -> Result<&2, &2, String, Bound>:
  match valid:
    case False{}: Fail{"InvalidManifest: bound requires version/inclusive only"}
    case True{}:
      do Result<&2, &2, String, Bound>:
        version : Version <- version_field(J.member(value, "version"))
        inclusive : Bool <- bool_field(J.member(value, "inclusive"))
        return Bound{version, inclusive}

def parse_bound(found: Maybe<&2, J.Value>) -> Result<&2, &2, String, Maybe<&2, Bound>>:
  match found:
    case None{}: Done{None{}}
    case Some{+value}:
      do Result<&2, &2, String, Maybe<&2, Bound>>:
        bound : Bound <- bound_checked(value, object_valid(value, ["version", "inclusive"]))
        return Some{bound}

def range_checked(+range: Range, valid: Bool) -> Result<&2, &2, String, Range>:
  match valid:
    case False{}: Fail{"InvalidManifest: dependency version range is empty/reversed"}
    case True{}: Done{range}

def range_fields(+value: J.Value, valid: Bool) -> Result<&2, &2, String, Range>:
  match valid:
    case False{}: Fail{"InvalidManifest: dependency range must contain only min/max"}
    case True{}:
      do Result<&2, &2, String, Range>:
        lo : Maybe<&2, Bound> <- parse_bound(J.member(value, "min"))
        hi : Maybe<&2, Bound> <- parse_bound(J.member(value, "max"))
        +range : Range = Range{lo, hi}
        range_checked(range, valid_range(range))

def range_field(found: Maybe<&2, J.Value>) -> Result<&2, &2, String, Range>:
  match found:
    case None{}: Fail{"InvalidManifest: dependency requires explicit range object"}
    case Some{+value}: range_fields(value, object_valid(value, ["min", "max"]))

def dependency_fields(+value: J.Value, valid: Bool) -> Result<&2, &2, String, Dependency>:
  match valid:
    case False{}: Fail{"InvalidManifest: dependency requires id/range only"}
    case True{}:
      do Result<&2, &2, String, Dependency>:
        id : String <- get_string(value, "id")
        range : Range <- range_field(J.member(value, "range"))
        return Dependency{id, range}

def parse_dependencies(values: List<&2, J.Value>) -> Result<&2, &2, String, List<&2, Dependency>>:
  match values:
    case Nil{}: Done{[]}
    case +h <> t:
      do Result<&2, &2, String, List<&2, Dependency>>:
        dep : Dependency <- dependency_fields(h, object_valid(h, ["id", "range"]))
        tail : List<&2, Dependency> <- parse_dependencies(t)
        return dep <> tail

def dependencies_field(found: Maybe<&2, J.Value>) -> Result<&2, &2, String, List<&2, Dependency>>:
  match found:
    case None{}: Done{[]}
    case Some{J.JArray{values}}: parse_dependencies(values)
    case _: Fail{"InvalidManifest: dependencies must be an array"}

def parse_strings(values: List<&2, J.Value>) -> Result<&2, &2, String, List<&2, String>>:
  match values:
    case Nil{}: Done{[]}
    case J.JString{s} <> tail:
      do Result<&2, &2, String, List<&2, String>>:
        rest : List<&2, String> <- parse_strings(tail)
        return s <> rest
    case _: Fail{"InvalidManifest: declaration/order entries must be strings"}

def strings_field(found: Maybe<&2, J.Value>) -> Result<&2, &2, String, List<&2, String>>:
  match found:
    case None{}: Done{[]}
    case Some{J.JArray{values}}: parse_strings(values)
    case _: Fail{"InvalidManifest: declaration/order field must be an array"}

def parse_side(name: String) -> Result<&2, &2, String, Side>:
  match name:
    case "client": Done{Client{}}
    case "server": Done{Server{}}
    case "both": Done{Both{}}
    case _: Fail{"InvalidManifest: side must be client/server/both"}

def parse_reload(name: String) -> Result<&2, &2, String, Reload>:
  match name:
    case "safe": Done{Safe{}}
    case "restart": Done{Restart{}}
    case _: Fail{"InvalidManifest: reload must be safe/restart"}

def decode_fields(+value: J.Value, valid: Bool) -> Result<&2, &2, String, Manifest>:
  match valid:
    case False{}: Fail{"InvalidManifest: expected object with known unique fields"}
    case True{}:
      do Result<&2, &2, String, Manifest>:
        id : String <- get_string(value, "id")
        version : Version <- version_field(J.member(value, "version"))
        api : Version <- version_field(J.member(value, "api_version"))
        side_text : String <- get_string(value, "side")
        side : Side <- parse_side(side_text)
        deps : List<&2, Dependency> <- dependencies_field(J.member(value, "dependencies"))
        before : List<&2, String> <- strings_field(J.member(value, "before"))
        after : List<&2, String> <- strings_field(J.member(value, "after"))
        operations : List<&2, String> <- strings_field(J.member(value, "operations"))
        queries : List<&2, String> <- strings_field(J.member(value, "queries"))
        events : List<&2, String> <- strings_field(J.member(value, "events"))
        data_version : U32 <- get_uint(value, "data_version")
        reload_text : String <- get_string(value, "reload")
        reload : Reload <- parse_reload(reload_text)
        return Manifest{id, version, api, side, deps, before, after, operations, queries, events, data_version, reload}


def manifest_id(manifest: Manifest) -> String:
  Manifest{id, version, api, side, deps, before, after, ops, queries, events, data, reload} = manifest
  id

def manifest_ids(manifests: List<&2, Manifest>) -> List<&2, String>:
  match manifests:
    case Nil{}: []
    case h <> t: manifest_id(h) <> manifest_ids(t)

def find(manifests: List<&2, Manifest>, +id: String) -> Maybe<&2, Manifest>:
  match manifests:
    case Nil{}: None{}
    case +h <> t: J.choose(Maybe<&2, Manifest>, Some{h}, find(t, id), String.eq(manifest_id(h), id))

def dep_ids(deps: List<&2, Dependency>) -> List<&2, String>:
  match deps:
    case Nil{}: []
    case Dependency{id, range} <> t: id <> dep_ids(t)

def all_ids(ids: List<&2, String>) -> Bool:
  match ids:
    case Nil{}: True{}
    case h <> t: valid_id(h) && all_ids(t)

def all_symbols(names: List<&2, String>) -> Bool:
  match names:
    case Nil{}: True{}
    case h <> t: valid_symbol(h) && all_symbols(t)

def all_ranges(deps: List<&2, Dependency>) -> Bool:
  match deps:
    case Nil{}: True{}
    case Dependency{id, range} <> t: valid_range(range) && all_ranges(t)

def metadata_valid(manifest: Manifest) -> Bool:
  match manifest:
    case Manifest{id, version, api, side, +deps, +before, +after, +ops, +queries, +events, data, reload}:
      valid_id(id) && all_ids(dep_ids(deps)) && all_ranges(deps) && unique(dep_ids(deps)) &&
      all_ids(before) && all_ids(after) && unique(before) && unique(after) &&
      all_symbols(ops) && all_symbols(queries) && all_symbols(events) &&
      unique(List.append(&2, String, ops, queries)) && unique(events) &&
      Nat.is_le(List.length(&2, Dependency, deps), 64n) && Nat.is_le(List.length(&2, String, before), 64n) &&
      Nat.is_le(List.length(&2, String, after), 64n) && Nat.is_le(List.length(&2, String, ops), 256n) &&
      Nat.is_le(List.length(&2, String, queries), 256n) && Nat.is_le(List.length(&2, String, events), 256n)

def decode_metadata(result: Result<&2, &2, String, Manifest>) -> Result<&2, &2, String, Manifest>:
  match result:
    case Fail{error}: Fail{error}
    case Done{+manifest}:
      J.choose(Result<&2, &2, String, Manifest>, Done{manifest}, Fail{"InvalidMetadata: invalid IDs, declarations, ranges or list limits"}, metadata_valid(manifest))

def decode(+value: J.Value) -> Result<&2, &2, String, Manifest>:
  decode_metadata(decode_fields(value, object_valid(value, ["id", "version", "api_version", "side", "dependencies", "before", "after", "operations", "queries", "events", "data_version", "reload"])))

def decode_all(values: List<&2, J.Value>) -> Result<&2, &2, String, List<&2, Manifest>>:
  match values:
    case Nil{}: Done{[]}
    case h <> t:
      do Result<&2, &2, String, List<&2, Manifest>>:
        manifest : Manifest <- decode(h)
        tail : List<&2, Manifest> <- decode_all(t)
        return manifest <> tail

def decode_pack(value: J.Value) -> Result<&2, &2, String, List<&2, Manifest>>:
  match value:
    case J.JArray{values}: decode_all(values)
    case _: Fail{"InvalidManifest: mod pack must be an array"}


def require(valid: Bool, message: String) -> Result<&2, &2, String, Unit>:
  match valid:
    case True{}: Done{Unit{}}
    case False{}: Fail{message}

def dependency_target(found: Maybe<&2, Manifest>, +owner: String, owner_side: Side, +wanted: String, range: Range) -> Result<&2, &2, String, Unit>:
  match found:
    case None{}: Fail{"MissingDependency: " ++ owner ++ " requires " ++ wanted}
    case Some{Manifest{id, +version, api, +side, deps, before, after, ops, queries, events, data, reload}}:
      do Result<&2, &2, String, Unit>:
        require(covers(side, owner_side), "ForbiddenSide: " ++ owner ++ " requires " ++ wanted ++ " on incompatible side")
        require(contains(range, version), "IncompatibleDependency: " ++ owner ++ " rejects " ++ wanted ++ " version " ++ version_show(version))

def validate_dependencies(deps: List<&2, Dependency>, +pack: List<&2, Manifest>, +owner: String, +side: Side) -> Result<&2, &2, String, Unit>:
  match deps:
    case Nil{}: Done{Unit{}}
    case Dependency{+id, range} <> t:
      do Result<&2, &2, String, Unit>:
        dependency_target(find(pack, id), owner, side, id, range)
        validate_dependencies(t, pack, owner, side)

def order_target(found: Maybe<&2, Manifest>, owner: String, side: Side, wanted: String) -> Result<&2, &2, String, Unit>:
  match found:
    case None{}: Fail{"MissingOrderTarget: " ++ owner ++ " references " ++ wanted}
    case Some{Manifest{id, version, api, target_side, deps, before, after, ops, queries, events, data, reload}}:
      require(covers(target_side, side), "ForbiddenSide: " ++ owner ++ " orders against " ++ wanted ++ " on incompatible side")

def validate_order(ids: List<&2, String>, +pack: List<&2, Manifest>, +owner: String, +side: Side) -> Result<&2, &2, String, Unit>:
  match ids:
    case Nil{}: Done{Unit{}}
    case +id <> t:
      do Result<&2, &2, String, Unit>:
        order_target(find(pack, id), owner, side, id)
        validate_order(t, pack, owner, side)

def validate_pack(manifests: List<&2, Manifest>, +whole: List<&2, Manifest>, +api: Version) -> Result<&2, &2, String, Unit>:
  match manifests:
    case Nil{}: Done{Unit{}}
    case +manifest <> +tail:
      Manifest{+id, version, actual_api, +side, deps, before, after, ops, queries, events, data, reload} = manifest
      do Result<&2, &2, String, Unit>:
        require(metadata_valid(manifest), "InvalidMetadata: " ++ id ++ " has invalid IDs, declarations, ranges or list limits")
        require(Bool.not(names_have(manifest_ids(tail), id)), "DuplicateId: " ++ id)
        require(version_eq(api, actual_api), "ApiVersionMismatch: " ++ id)
        validate_dependencies(deps, whole, id, side)
        validate_order(before, whole, id, side)
        validate_order(after, whole, id, side)
        validate_pack(tail, whole, api)

def select(manifests: List<&2, Manifest>, +target: Side) -> List<&2, Manifest>:
  match manifests:
    case Nil{}: []
    case +h <> tail:
      Manifest{id, version, api, side, deps, before, after, ops, queries, events, data, reload} = h
      +rest = select(tail, target)
      J.choose(List<&2, Manifest>, h <> rest, rest, covers(side, target))

def callable_names(manifests: List<&2, Manifest>) -> List<&2, String>:
  match manifests:
    case Nil{}: []
    case Manifest{id, version, api, side, deps, before, after, ops, queries, events, data, reload} <> tail:
      List.append(&2, String, ops, List.append(&2, String, queries, callable_names(tail)))

def event_names(manifests: List<&2, Manifest>) -> List<&2, String>:
  match manifests:
    case Nil{}: []
    case Manifest{id, version, api, side, deps, before, after, ops, queries, events, data, reload} <> tail:
      List.append(&2, String, events, event_names(tail))

# A candidate is ready only if no remaining manifest has an incoming edge to it.
def candidate_incoming(candidate: Manifest, other: Manifest) -> Bool:
  match candidate other:
    case Manifest{+id, version, api, side, deps, before, after, ops, queries, events, data, reload}
         Manifest{+oid, over, oapi, oside, odeps, obefore, oafter, oops, oq, oe, od, orl}:
      names_have(dep_ids(deps), oid) || names_have(after, oid) || names_have(obefore, id)

def ready(remaining: List<&2, Manifest>, +candidate: Manifest) -> Bool:
  match remaining:
    case Nil{}: True{}
    case h <> t: Bool.not(candidate_incoming(candidate, h)) && ready(t, candidate)

def smaller(candidate: Manifest, current: Maybe<&2, Manifest>) -> Maybe<&2, Manifest>:
  match current:
    case None{}: Some{candidate}
    case Some{+old}:
      +next = {candidate : Manifest}
      J.choose(Maybe<&2, Manifest>, Some{next}, Some{old}, String.is_lt(manifest_id(next), manifest_id(old)))

def choose_ready(candidates: List<&2, Manifest>, +remaining: List<&2, Manifest>, +best: Maybe<&2, Manifest>) -> Maybe<&2, Manifest>:
  match candidates:
    case Nil{}: best
    case +h <> tail:
      choose_ready(tail, remaining, J.choose(Maybe<&2, Manifest>, smaller(h, best), best, ready(remaining, h)))

def remove(manifests: List<&2, Manifest>, +id: String) -> List<&2, Manifest>:
  match manifests:
    case Nil{}: []
    case +h <> t:
      +rest = remove(t, id)
      J.choose(List<&2, Manifest>, rest, h <> rest, String.eq(manifest_id(h), id))

# Fuel equals manifest count; every successful iteration removes one exact ID.
def order(fuel: Nat, remaining: List<&2, Manifest>, reversed: List<&2, Manifest>, picked: Maybe<&2, Manifest>) -> Result<&2, &2, String, List<&2, Manifest>>:
  match fuel remaining picked:
    case _ Nil{} _: Done{List.reverse(&2, Manifest, reversed)}
    case 0n h <> t _: Fail{"Cycle: ordering work exhausted"}
    case 1n+rest h <> t None{}:
      Fail{"Cycle: no ready mod among " ++ String.join(manifest_ids(h <> t), ",")}
    case 1n+rest h <> t Some{+next}:
      +tail = remove(h <> t, manifest_id(next))
      order(rest, tail, next <> reversed, choose_ready(tail, tail, None{}))

def duplicate_name(names: List<&2, String>) -> Maybe<&2, String>:
  match names:
    case Nil{}: None{}
    case +h <> +t: J.choose(Maybe<&2, String>, Some{h}, duplicate_name(t), names_have(t, h))

def unique_declarations(duplicate: Maybe<&2, String>, kind: String) -> Result<&2, &2, String, Unit>:
  match duplicate:
    case None{}: Done{Unit{}}
    case Some{name}: Fail{"ConflictingName: " ++ kind ++ " declaration " ++ name}

def resolve_checked(valid: Result<&2, &2, String, Unit>, +active: List<&2, Manifest>) -> Result<&2, &2, String, List<&2, Manifest>>:
  match valid:
    case Fail{message}: Fail{message}
    case Done{u}:
      do Result<&2, &2, String, List<&2, Manifest>>:
        unique_declarations(duplicate_name(callable_names(active)), "operation/query")
        unique_declarations(duplicate_name(event_names(active)), "event")
        order(List.length(&2, Manifest, active), active, [], choose_ready(active, active, None{}))

def resolve_target(target: Side, +api: Version, +manifests: List<&2, Manifest>, bounded: Bool) -> Result<&2, &2, String, List<&2, Manifest>>:
  match target bounded:
    case Both{} _: Fail{"InvalidTarget: deployment must be client or server"}
    case _ False{}: Fail{"TooManyMods: maximum is 64"}
    case side True{}: resolve_checked(validate_pack(manifests, manifests, api), select(manifests, side))

def resolve(target: Side, api: Version, +manifests: List<&2, Manifest>) -> Result<&2, &2, String, List<&2, Manifest>>:
  resolve_target(target, api, manifests, Nat.is_le(List.length(&2, Manifest, manifests), 64n))

def names_subset(names: List<&2, String>, +other: List<&2, String>) -> Bool:
  match names:
    case Nil{}: True{}
    case h <> t: names_have(other, h) && names_subset(t, other)

def names_same(+a: List<&2, String>, +b: List<&2, String>) -> Bool:
  names_subset(a, b) && names_subset(b, a)

def bounds_same(a: Maybe<&2, Bound>, b: Maybe<&2, Bound>) -> Bool:
  match a b:
    case None{} None{}: True{}
    case Some{Bound{av, ai}} Some{Bound{bv, bi}}: version_eq(av, bv) && Cmp.is_eq(Bool.cmp(ai, bi))
    case _ _: False{}

def ranges_same(a: Range, b: Range) -> Bool:
  match a b:
    case Range{alo, ahi} Range{blo, bhi}: bounds_same(alo, blo) && bounds_same(ahi, bhi)

def dep_present(deps: List<&2, Dependency>, +wanted: Dependency) -> Bool:
  match deps:
    case Nil{}: False{}
    case Dependency{id, range} <> t:
      Dependency{+wid, +wr} = wanted
      (String.eq(id, wid) && ranges_same(range, wr)) || dep_present(t, Dependency{wid, wr})

def deps_subset(deps: List<&2, Dependency>, +other: List<&2, Dependency>) -> Bool:
  match deps:
    case Nil{}: True{}
    case +h <> t: dep_present(other, h) && deps_subset(t, other)

def deps_same(+a: List<&2, Dependency>, +b: List<&2, Dependency>) -> Bool:
  deps_subset(a, b) && deps_subset(b, a)

def reload_same(a: Reload, b: Reload) -> Bool:
  match a b:
    case Safe{} Safe{}: True{}
    case Restart{} Restart{}: True{}
    case _ _: False{}

# Version is excluded; all compatibility/state-bearing metadata is included.
def shape_same(a: Manifest, b: Manifest) -> Bool:
  match a b:
    case Manifest{aid, av, aa, aside, adeps, abefore, aafter, aops, aq, ae, adata, ar}
         Manifest{bid, bv, ba, bside, bdeps, bbefore, bafter, bops, bq, be, bdata, br}:
      String.eq(aid, bid) && version_eq(aa, ba) && side_eq(aside, bside) &&
      deps_same(adeps, bdeps) && names_same(abefore, bbefore) && names_same(aafter, bafter) &&
      names_same(aops, bops) && names_same(aq, bq) && names_same(ae, be) && U32.is_eq(adata, bdata) && reload_same(ar, br)

def version_of(manifest: Manifest) -> Version:
  Manifest{id, version, api, side, deps, before, after, ops, queries, events, data, reload} = manifest
  version

def data_of(manifest: Manifest) -> U32:
  Manifest{id, version, api, side, deps, before, after, ops, queries, events, data, reload} = manifest
  data

def shared_target(found: Maybe<&2, Manifest>, +manifest: Manifest) -> Result<&2, &2, String, Unit>:
  match found:
    case None{}: Fail{"MissingSharedMod: both-side " ++ manifest_id(manifest) ++ " missing from counterpart"}
    case Some{+other}:
      do Result<&2, &2, String, Unit>:
        require(version_eq(version_of(manifest), version_of(other)), "SharedVersionMismatch: " ++ manifest_id(manifest) ++ " expected " ++ version_show(version_of(manifest)) ++ " observed " ++ version_show(version_of(other)))
        require(U32.is_eq(data_of(manifest), data_of(other)), "SharedDataVersionMismatch: " ++ manifest_id(manifest) ++ " expected " ++ U32.show(data_of(manifest)) ++ " observed " ++ U32.show(data_of(other)))
        require(shape_same(manifest, other), "SharedManifestMismatch: " ++ manifest_id(manifest))

def shared_requirements(manifests: List<&2, Manifest>, +other: List<&2, Manifest>) -> Result<&2, &2, String, Unit>:
  match manifests:
    case Nil{}: Done{Unit{}}
    case +h <> t:
      Manifest{+id, version, api, side, deps, before, after, ops, queries, events, data, reload} = h
      match side:
        case Both{}:
          do Result<&2, &2, String, Unit>:
            shared_target(find(other, id), h)
            shared_requirements(t, other)
        case _: shared_requirements(t, other)

def shared_ids(manifests: List<&2, Manifest>) -> List<&2, String>:
  match manifests:
    case Nil{}: []
    case Manifest{id, version, api, Both{}, deps, before, after, ops, queries, events, data, reload} <> t: id <> shared_ids(t)
    case h <> t: shared_ids(t)

def exact_names(a: List<&2, String>, b: List<&2, String>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case ah <> at bh <> bt: String.eq(ah, bh) && exact_names(at, bt)
    case _ _: False{}

def deployment(manifests: List<&2, Manifest>, +target: Side) -> Result<&2, &2, String, Unit>:
  match manifests:
    case Nil{}: Done{Unit{}}
    case Manifest{+id, version, api, side, deps, before, after, ops, queries, events, data, reload} <> t:
      do Result<&2, &2, String, Unit>:
        require(covers(side, target), "ForbiddenDeploymentSide: " ++ id ++ " in " ++ side_name(target))
        deployment(t, target)

def match_sides(+client: List<&2, Manifest>, +server: List<&2, Manifest>, +api: Version) -> Result<&2, &2, String, MatchReport>:
  do Result<&2, &2, String, MatchReport>:
    deployment(client, Client{})
    deployment(server, Server{})
    +client_order : List<&2, Manifest> <- resolve(Client{}, api, client)
    +server_order : List<&2, Manifest> <- resolve(Server{}, api, server)
    shared_requirements(client_order, server_order)
    shared_requirements(server_order, client_order)
    require(exact_names(shared_ids(client_order), shared_ids(server_order)), "SharedOrderMismatch: both-side load order differs")
    return MatchReport{manifest_ids(client_order), manifest_ids(server_order), shared_ids(client_order)}

def safe(reload: Reload) -> Bool:
  match reload:
    case Safe{}: True{}
    case Restart{}: False{}

def reload_inputs(valid: Bool, id_same: Bool, api_same: Bool, data_same: Bool, shape: Bool, same_version: Bool, upgrade: Bool, safe_policy: Bool) -> ReloadReport:
  match valid id_same api_same data_same shape same_version upgrade safe_policy:
    case False{} _ _ _ _ _ _ _: ReloadReport{Incompatible{}, ["invalid manifest metadata"], False{}}
    case True{} False{} _ _ _ _ _ _: ReloadReport{Incompatible{}, ["mod identity changed"], False{}}
    case True{} True{} False{} _ _ _ _ _: ReloadReport{Incompatible{}, ["API version changed"], False{}}
    case True{} True{} True{} False{} _ _ _ _: ReloadReport{RestartRequired{}, ["data version changed; migration is not implemented"], False{}}
    case True{} True{} True{} True{} False{} _ _ _: ReloadReport{RestartRequired{}, ["side, dependencies, order, declarations or reload policy changed"], False{}}
    case True{} True{} True{} True{} True{} True{} _ _: ReloadReport{NoChange{}, ["manifest metadata unchanged; code identity is not checked"], False{}}
    case True{} True{} True{} True{} True{} False{} False{} _: ReloadReport{RestartRequired{}, ["mod version downgrade"], False{}}
    case True{} True{} True{} True{} True{} False{} True{} False{}: ReloadReport{RestartRequired{}, ["manifest declares restart policy"], False{}}
    case True{} True{} True{} True{} True{} False{} True{} True{}: ReloadReport{SafeCandidate{}, ["metadata permits reload; runtime hooks and state migration are unverified"], False{}}

def classify_reload(+old: Manifest, +next: Manifest) -> ReloadReport:
  Manifest{+oid, +ov, +oa, os, od, ob, oafter, oo, oq, oe, +odata, +or} = old
  Manifest{+nid, +nv, +na, ns, nd, nb, nafter, no, nq, ne, +ndata, +nr} = next
  reload_inputs(metadata_valid(old) && metadata_valid(next), String.eq(oid, nid), version_eq(oa, na), U32.is_eq(odata, ndata),
    shape_same(old, next), version_eq(ov, nv), Bool.not(Cmp.is_lt(compare(nv, ov))), safe(or) && safe(nr))


def json_strings(names: List<&2, String>) -> J.Value:
  J.JArray{List.foldr(~&2, ~String, ~List<&2, J.Value>, ~(name => acc => J.JString{name} <> acc), names, [])}

def match_value(report: MatchReport) -> J.Value:
  match report:
    case MatchReport{client, server, shared}:
      J.JObject{[J.JMember{"client_order", json_strings(client)}, J.JMember{"server_order", json_strings(server)}, J.JMember{"shared", json_strings(shared)}]}

def reload_class_name(classification: ReloadClass) -> String:
  match classification:
    case NoChange{}: "no-change"
    case SafeCandidate{}: "safe-candidate"
    case RestartRequired{}: "restart-required"
    case Incompatible{}: "incompatible"

def reload_value(report: ReloadReport) -> J.Value:
  match report:
    case ReloadReport{classification, reasons, verified}:
      J.JObject{[J.JMember{"classification", J.JString{reload_class_name(classification)}}, J.JMember{"reasons", json_strings(reasons)}, J.JMember{"execution_verified", J.JBool{verified}}]}
