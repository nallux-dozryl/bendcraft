import Base
import ./nbt.bend as N
import ./f64.bend as F
import ./player_look.bend as PL

# Selected neutral unmounted Entity fields; no Body or Player callback owner.
type Vec3 is Data:
  Vec3{x: F.F64, y: F.F64, z: F.F64}

type Fields is Data:
  Fields{position: Vec3, velocity: Vec3, position_o: Vec3, position_old: Vec3,
    look: PL.State, head_yaw: F32, body_yaw: F32, fall_distance: F.F64,
    on_ground: Bool, air: U32, fire: U32, portal_cooldown: U32,
    invulnerable: Bool, needs_sync: Bool}

type TagTree is Type:
  TagTree{root: N.Root}

type Document is Type:
  Document{tree: TagTree, fields: Fields}

type Config is Data:
  Config{limits: N.Limits, max_air: U32}

type Error is Data:
  UnsupportedConfig{}
  InvalidPrior{field: U32}
  InvalidPosition{axis: U32}
  NbtError{message: String}
  RootType{}
  DuplicateSelected{key: String}
  UnsupportedNumericLong{key: String}

type Note is Data:
  NonNumericScalar{key: String, tag: U32}
  InvalidVector{key: String}
  VectorSize{key: String, expected: U32, actual: U32, partial: Bool}

type LoadOutcome is Type:
  Accepted{document: Document, notes: List<&2, Note>}
  Rejected{prior: Document, candidate: TagTree, error: Error}

type SaveOutcome is Type:
  Saved{document: Document, output: TagTree}
  SaveRejected{document: Document, error: Error}

type Parsed<-A: Data> is Data:
  Parsed{value: A, notes: List<&2, Note>}

type Numeric is Data:
  Numeric{value: F.F64, valid: Bool}

type Angles is Data:
  Angles{yaw: F32, pitch: F32}

type LookProjection is Data:
  LookProjection{look: PL.State, head_yaw: F32, body_yaw: F32}

type Projected is Data:
  Projected{fields: Fields, notes: List<&2, Note>}

def default_config() -> Config:
  Config{N.Limits{65536, 32, 4096}, 300}

def zero() -> F.F64:
  F.F64{0, 0}

def zero_vector() -> Vec3:
  Vec3{zero(), zero(), zero()}

def default_fields() -> Fields:
  Fields{zero_vector(), zero_vector(), zero_vector(), zero_vector(),
    PL.State{PL.float_bits(0), PL.float_bits(0), PL.float_bits(0), PL.float_bits(0)},
    PL.float_bits(0), PL.float_bits(0), zero(), False{}, 300, 0, 0, False{}, False{}}

def choose(-A: Data, yes: A, no: A, test: Bool) -> A:
  match test:
    case True{}: yes
    case False{}: no

def units(text: String) -> List<&2, U32>:
  match text:
    case SNil{}: Nil{}
    case SCon{Chr{c}, rest}: c <> units(rest)

def text(value: String) -> N.Text:
  N.Text{units(value)}

def unit_eq(a: List<&2, U32>, b: List<&2, U32>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case a <> at b <> bt: U32.is_eq(a, b) && unit_eq(at, bt)
    case _ _: False{}

def text_eq(a: N.Text, b: N.Text) -> Bool:
  match a b:
    case N.Text{a} N.Text{b}: unit_eq(a, b)

def selected_names() -> List<&2, String>:
  ["Pos", "Motion", "Rotation", "fall_distance", "OnGround", "Air", "Fire", "PortalCooldown", "Invulnerable"]

def selected_key(names: List<&2, String>, +name: N.Text) -> Maybe<&2, String>:
  match names:
    case Nil{}: None{}
    case +key <> rest:
      choose(Maybe<&2, String>, Some{key}, selected_key(rest, name), text_eq(text(key), name))

def lookup(members: List<&2, N.Member>, +key: N.Text) -> Maybe<&2, N.Value>:
  match members:
    case Nil{}: None{}
    case N.Member{+name, +value} <> rest:
      choose(Maybe<&2, N.Value>, Some{value}, lookup(rest, key), text_eq(name, key))

def present(names: List<&2, String>, +key: String) -> Bool:
  match names:
    case Nil{}: False{}
    case h <> rest: String.eq(h, key) || present(rest, key)

def duplicate_key(key: Maybe<&2, String>, seen: List<&2, String>) -> Maybe<&2, Error>:
  match key:
    case None{}: None{}
    case Some{+name}:
      choose(Maybe<&2, Error>, Some{DuplicateSelected{name}}, None{}, present(seen, name))

def selected_seen(key: Maybe<&2, String>, +seen: List<&2, String>) -> List<&2, String>:
  match key:
    case None{}: seen
    case Some{+name}: choose(List<&2, String>, seen, name <> seen, present(seen,name))

def duplicate_first(a: Maybe<&2, Error>, b: Maybe<&2, Error>) -> Maybe<&2, Error>:
  match a:
    case Some{error}: Some{error}
    case None{}: b

def duplicate_members(members: List<&2, N.Member>, +seen: List<&2, String>) -> Maybe<&2, Error>:
  match members:
    case Nil{}: None{}
    case N.Member{name, value} <> rest:
      +key = selected_key(selected_names(), name)
      duplicate_first(duplicate_key(key, seen), duplicate_members(rest, selected_seen(key, seen)))

def signed8(+bits: U32) -> U32:
  choose(U32, U32.or(bits, 4294967040), bits, U32.is_ne(U32.and(bits, 128), 0))

def signed16(+bits: U32) -> U32:
  +low = U32.and(bits, 65535)
  choose(U32, U32.or(low, 4294901760), low, U32.is_ne(U32.and(low, 32768), 0))

def number_zero(+value: F.F64) -> F.F64:
  choose(F.F64, zero(), value, F.is_zero(value))

def float_zero(+bits: U32) -> U32:
  choose(U32, 0, bits, U32.is_eq(U32.and(bits, 2147483647), 0))

# Actual 26.3 Mth.floor = Math.floor followed by Java saturating int conversion.
def floor_result(value: F.F64, result: Result<&2, &2, F.F64ConversionError, U32>) -> U32:
  match result:
    case Done{word}: word
    case Fail{error}: choose(U32, 2147483648, 2147483647, F.sign(value))

def floor_word(+value: F.F64) -> U32:
  choose(U32, 0, floor_result(value, F.floor_i32(value)), F.is_nan(value))

def as_int(value: N.Value) -> Maybe<&2, U32>:
  match value:
    case N.Byte{bits}: Some{signed8(bits)}
    case N.Short{bits}: Some{signed16(bits)}
    case N.Int{bits}: Some{bits}
    case N.Long{N.Word64{hi, lo}}: Some{lo}
    case N.Float{bits}: Some{floor_word(F.widen_float_bits(bits))}
    case N.Double{N.Word64{hi, lo}}: Some{floor_word(F.F64{hi, lo})}
    case _: None{}

def scalar_int_result(key: String, fallback: U32, tag: U32, value: Maybe<&2, U32>) -> Parsed<U32>:
  match value:
    case Some{word}: Parsed{word, Nil{}}
    case None{}: Parsed{fallback, NonNumericScalar{key, tag} <> Nil{}}

def read_int(key: String, fallback: U32, value: Maybe<&2, N.Value>) -> Parsed<U32>:
  match value:
    case None{}: Parsed{fallback, Nil{}}
    case Some{+tag}: scalar_int_result(key, fallback, N.tag(tag), as_int(tag))

def as_double(value: N.Value, key: String) -> Result<&2, &2, Error, Numeric>:
  match value:
    case N.Byte{bits}: Done{Numeric{F.from_i32(signed8(bits)), True{}}}
    case N.Short{bits}: Done{Numeric{F.from_i32(signed16(bits)), True{}}}
    case N.Int{bits}: Done{Numeric{F.from_i32(bits), True{}}}
    case N.Long{word}: Fail{UnsupportedNumericLong{key}}
    case N.Float{bits}: Done{Numeric{F.widen_float_bits(float_zero(bits)), True{}}}
    case N.Double{N.Word64{hi, lo}}: Done{Numeric{number_zero(F.F64{hi, lo}), True{}}}
    case _: Done{Numeric{zero(), False{}}}

def scalar_double_result(key: String, tag: U32, result: Result<&2, &2, Error, Numeric>) -> Result<&2, &2, Error, Parsed<F.F64>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{Numeric{value, True{}}}: Done{Parsed{value, Nil{}}}
    case Done{Numeric{value, False{}}}: Done{Parsed{zero(), NonNumericScalar{key, tag} <> Nil{}}}

def read_double(+key: String, value: Maybe<&2, N.Value>) -> Result<&2, &2, Error, Parsed<F.F64>>:
  match value:
    case None{}: Done{Parsed{zero(), Nil{}}}
    case Some{+tag}: scalar_double_result(key, N.tag(tag), as_double(tag, key))

def byte_items(values: List<&2, U32>) -> List<&2, N.Value>:
  match values:
    case Nil{}: Nil{}
    case h <> t: N.Byte{h} <> byte_items(t)

def int_items(values: List<&2, U32>) -> List<&2, N.Value>:
  match values:
    case Nil{}: Nil{}
    case h <> t: N.Int{h} <> int_items(t)

def long_items(values: List<&2, N.Word64>) -> List<&2, N.Value>:
  match values:
    case Nil{}: Nil{}
    case h <> t: N.Long{h} <> long_items(t)

def sequence(value: N.Value) -> Maybe<&2, List<&2, N.Value>>:
  match value:
    case N.ListTag{element, values}: Some{values}
    case N.ByteArray{values}: Some{byte_items(values)}
    case N.IntArray{values}: Some{int_items(values)}
    case N.LongArray{values}: Some{long_items(values)}
    case _: None{}

def size_note(key: String, +expected: U32, +actual: U32, partial: Bool) -> List<&2, Note>:
  choose(List<&2, Note>, Nil{}, VectorSize{key, expected, actual, partial} <> Nil{}, U32.is_eq(expected, actual))

def count(values: List<&2, N.Value>, acc: U32) -> U32:
  match values:
    case Nil{}: acc
    case h <> t: count(t, U32.add(acc, 1))

def vector_numbers(+key: String, +actual: U32, a: Numeric, b: Numeric, c: Numeric) -> Parsed<Vec3>:
  match a b c:
    case Numeric{x, +va} Numeric{y, +vb} Numeric{z, +vc}:
      choose(Parsed<Vec3>, Parsed{Vec3{x, y, z}, size_note(key, 3, actual, True{})},
        Parsed{zero_vector(), InvalidVector{key} <> Nil{}}, va && vb && vc)

def vector_prefix(values: List<&2, N.Value>, +key: String, actual: U32) -> Result<&2, &2, Error, Parsed<Vec3>>:
  match values:
    case a <> b <> c <> rest:
      do Result<&2, &2, Error, Parsed<Vec3>>:
        x : Numeric <- as_double(a, key)
        y : Numeric <- as_double(b, key)
        z : Numeric <- as_double(c, key)
        return vector_numbers(key, actual, x, y, z)
    case _: Done{Parsed{zero_vector(), size_note(key, 3, actual, False{})}}

def vector_sequence(+key: String, result: Maybe<&2, List<&2, N.Value>>) -> Result<&2, &2, Error, Parsed<Vec3>>:
  match result:
    case None{}: Done{Parsed{zero_vector(), InvalidVector{key} <> Nil{}}}
    case Some{+values}: vector_prefix(values, key, count(values, 0))

def read_vector(key: String, value: Maybe<&2, N.Value>) -> Result<&2, &2, Error, Parsed<Vec3>>:
  match value:
    case None{}: Done{Parsed{zero_vector(), Nil{}}}
    case Some{tag}: vector_sequence(key, sequence(tag))

def angle_numbers(+key: String, +actual: U32, a: Numeric, b: Numeric) -> Parsed<Angles>:
  match a b:
    case Numeric{x, va} Numeric{y, vb}:
      choose(Parsed<Angles>, Parsed{Angles{F.to_f32(x), F.to_f32(y)}, size_note(key, 2, actual, True{})},
        Parsed{Angles{PL.float_bits(0), PL.float_bits(0)}, InvalidVector{key} <> Nil{}}, va && vb)

def angle_prefix(values: List<&2, N.Value>, +key: String, actual: U32) -> Result<&2, &2, Error, Parsed<Angles>>:
  match values:
    case a <> b <> rest:
      do Result<&2, &2, Error, Parsed<Angles>>:
        x : Numeric <- as_double(a, key)
        y : Numeric <- as_double(b, key)
        return angle_numbers(key, actual, x, y)
    case _: Done{Parsed{Angles{PL.float_bits(0), PL.float_bits(0)}, size_note(key, 2, actual, False{})}}

def angle_sequence(+key: String, result: Maybe<&2, List<&2, N.Value>>) -> Result<&2, &2, Error, Parsed<Angles>>:
  match result:
    case None{}: Done{Parsed{Angles{PL.float_bits(0), PL.float_bits(0)}, InvalidVector{key} <> Nil{}}}
    case Some{+values}: angle_prefix(values, key, count(values, 0))

def read_angles(value: Maybe<&2, N.Value>) -> Result<&2, &2, Error, Parsed<Angles>>:
  match value:
    case None{}: Done{Parsed{Angles{PL.float_bits(0), PL.float_bits(0)}, Nil{}}}
    case Some{tag}: angle_sequence("Rotation", sequence(tag))

def clamp(+value: F.F64, +limit: F.F64) -> F.F64:
  choose(F.F64, F.neg(limit), choose(F.F64, limit, value, F.is_gt(value, limit)), F.is_lt(value, F.neg(limit)))

def clamped_position(vector: Vec3) -> Vec3:
  match vector:
    case Vec3{x, y, z}: Vec3{clamp(x, F.from_u32(30000512)), clamp(y, F.from_u32(20000000)), clamp(z, F.from_u32(30000512))}

def motion_component(+value: F.F64) -> F.F64:
  choose(F.F64, zero(), value, F.is_gt(F.abs(value), F.from_u32(10)))

def clamped_motion(vector: Vec3) -> Vec3:
  match vector:
    case Vec3{x, y, z}: Vec3{motion_component(x), motion_component(y), motion_component(z)}

def vector_finite(vector: Vec3) -> Bool:
  match vector:
    case Vec3{x,y,z}: F.is_finite(x) && F.is_finite(y) && F.is_finite(z)

def loaded_motion(prior: Vec3, candidate: Vec3) -> Vec3:
  +clipped = clamped_motion(candidate)
  choose(Vec3, clipped, prior, vector_finite(clipped))

def loaded_look(prior: PL.State, angles: Angles) -> LookProjection:
  match prior angles:
    case PL.State{old_yaw, old_pitch, previous_yaw, previous_pitch} Angles{+yaw, +pitch}:
      +set_yaw = PL.set_yaw(old_yaw, yaw, PL.finite(yaw))
      +set_pitch = PL.set_pitch(old_pitch, pitch, PL.finite(pitch))
      LookProjection{PL.State{PL.remainder360(set_yaw), PL.set_pitch(set_pitch, PL.remainder360(set_pitch), True{}), set_yaw, set_pitch}, set_yaw, set_yaw}

def first(a: Maybe<&2, Error>, b: Maybe<&2, Error>) -> Maybe<&2, Error>:
  match a:
    case Some{error}: Some{error}
    case None{}: b

def finite_field(field: U32, valid: Bool) -> Maybe<&2, Error>:
  choose(Maybe<&2, Error>, None{}, Some{InvalidPrior{field}}, valid)

def vector_error(+base: U32, value: Vec3) -> Maybe<&2, Error>:
  match value:
    case Vec3{x, y, z}: first(finite_field(base, F.is_finite(x)), first(finite_field(U32.add(base, 1), F.is_finite(y)), finite_field(U32.add(base, 2), F.is_finite(z))))

def prior_error(fields: Fields) -> Maybe<&2, Error>:
  match fields:
    case Fields{pos, vel, o, old, PL.State{yaw, pitch, py, pp}, head, body, fall, ground, air, fire, portal, invul, sync}:
      first(vector_error(0, pos), first(vector_error(3, vel), first(vector_error(6, o), first(vector_error(9, old),
        first(finite_field(12, PL.finite(yaw)), first(finite_field(13, PL.finite(pitch)), first(finite_field(14, PL.finite(py)),
        first(finite_field(15, PL.finite(pp)), first(finite_field(16, PL.finite(head)), finite_field(17, PL.finite(body)))))))))))

def config_error(config: Config) -> Maybe<&2, Error>:
  match config:
    case Config{N.Limits{+bytes, +depth, +elements}, air}:
      choose(Maybe<&2, Error>, None{}, Some{UnsupportedConfig{}}, U32.is_gt(bytes, 0) && U32.is_le(bytes, 1048576) && U32.is_gt(depth, 0) && U32.is_le(depth, 64) && U32.is_gt(elements, 0) && U32.is_le(elements, 65536))

def position_error(vector: Vec3) -> Maybe<&2, Error>:
  match vector:
    case Vec3{x, y, z}:
      choose(Maybe<&2, Error>, choose(Maybe<&2, Error>, choose(Maybe<&2, Error>, None{}, Some{InvalidPosition{2}}, F.is_finite(z)), Some{InvalidPosition{1}}, F.is_finite(y)), Some{InvalidPosition{0}}, F.is_finite(x))

def nbt_checked(result: Result<&2, &2, String, List<&2, U32>>) -> Maybe<&2, Error>:
  match result:
    case Fail{message}: Some{NbtError{message}}
    case Done{bytes}: None{}

def root_error(root: N.Root) -> Maybe<&2, Error>:
  match root:
    case N.Root{name, N.Compound{members}}: duplicate_members(members, Nil{})
    case _: Some{RootType{}}

def bool_word(value: U32) -> Bool:
  U32.is_ne(U32.and(value, 255), 0)

def projected_fields(+pos: Vec3, prior_vel: Vec3, vel: Vec3, look: LookProjection, fall: F.F64,
    ground: U32, air: U32, fire: U32, portal: U32, invul: U32) -> Fields:
  match look:
    case LookProjection{angles, head, body}:
      Fields{pos, loaded_motion(prior_vel,vel), pos, pos, angles, head, body, fall, bool_word(ground), air, signed16(fire), portal, bool_word(invul), True{}}

def projected_result(fields: Fields, notes: List<&2, Note>, error: Maybe<&2, Error>) -> Result<&2, &2, Error, Projected>:
  match error:
    case Some{cause}: Fail{cause}
    case None{}: Done{Projected{fields, notes}}

def project_all(prior: Fields, position: Parsed<Vec3>, velocity: Parsed<Vec3>, angles: Parsed<Angles>,
    fall: Parsed<F.F64>, ground: Parsed<U32>, air: Parsed<U32>, fire: Parsed<U32>, portal: Parsed<U32>, invul: Parsed<U32>) -> Result<&2, &2, Error, Projected>:
  match prior position velocity angles fall ground air fire portal invul:
    case Fields{op, ov, oo, old, old_look, oh, ob, of, og, oa, off, opc, oi, os} Parsed{p, pn} Parsed{v, vn} Parsed{a, an} Parsed{f, fn} Parsed{g, gn} Parsed{ar, arn} Parsed{fi, fin} Parsed{pc, pcn} Parsed{iv, ivn}:
      +next_pos = clamped_position(p)
      +next = projected_fields(next_pos, ov, v, loaded_look(old_look, a), f, g, ar, fi, pc, iv)
      notes = List.append(&2, Note, pn, List.append(&2, Note, vn, List.append(&2, Note, an, List.append(&2, Note, fn,
        List.append(&2, Note, gn, List.append(&2, Note, arn, List.append(&2, Note, fin, List.append(&2, Note, pcn, ivn))))))))
      projected_result(next, notes, position_error(next_pos))

def project_values(prior: Fields, +members: List<&2, N.Member>, max_air: U32, position: Parsed<Vec3>,
    velocity: Parsed<Vec3>, angles: Parsed<Angles>, fall: Parsed<F.F64>) -> Result<&2, &2, Error, Projected>:
  project_all(prior, position, velocity, angles, fall,
    read_int("OnGround", 0, lookup(members, text("OnGround"))), read_int("Air", max_air, lookup(members, text("Air"))),
    read_int("Fire", 0, lookup(members, text("Fire"))), read_int("PortalCooldown", 0, lookup(members, text("PortalCooldown"))),
    read_int("Invulnerable", 0, lookup(members, text("Invulnerable"))))

def project_members(+members: List<&2, N.Member>, +prior: Fields, max_air: U32) -> Result<&2, &2, Error, Projected>:
  do Result<&2, &2, Error, Projected>:
    position : Parsed<Vec3> <- read_vector("Pos", lookup(members, text("Pos")))
    velocity : Parsed<Vec3> <- read_vector("Motion", lookup(members, text("Motion")))
    angles : Parsed<Angles> <- read_angles(lookup(members, text("Rotation")))
    fall : Parsed<F.F64> <- read_double("fall_distance", lookup(members, text("fall_distance")))
    project_values(prior, members, max_air, position, velocity, angles, fall)

def project(root: N.Root, prior: Fields, max_air: U32) -> Result<&2, &2, Error, Projected>:
  match root:
    case N.Root{name, N.Compound{members}}: project_members(members, prior, max_air)
    case _: Fail{RootType{}}

def close_tree(tree: TagTree) -> Unit:
  match tree:
    case TagTree{root}: Unit{}

def close_document(document: Document) -> Unit:
  match document:
    case Document{tree, fields}: close_tree(tree)

def reject(prior: Document, candidate: TagTree, error: Error) -> LoadOutcome:
  Rejected{prior, candidate, error}

def accept_closed(candidate: TagTree, result: Projected, closed: Unit) -> LoadOutcome:
  match result:
    case Projected{fields, notes}: Accepted{Document{candidate, fields}, notes}

def load_result(prior: Document, candidate: TagTree, result: Result<&2, &2, Error, Projected>) -> LoadOutcome:
  match result:
    case Fail{error}: reject(prior, candidate, error)
    case Done{projected}: accept_closed(candidate, projected, close_document(prior))

def load_guard(prior: Document, candidate: TagTree, config: Config, error: Maybe<&2, Error>) -> LoadOutcome:
  match prior candidate config error:
    case _ _ _ Some{cause}: reject(prior, candidate, cause)
    case Document{tree, +fields} TagTree{+root} Config{limits, air} None{}:
      load_result(Document{tree, fields}, TagTree{root}, project(root, fields, air))

def load_nbt(prior: Document, candidate: TagTree, config: Config, error: Maybe<&2, Error>) -> LoadOutcome:
  match prior candidate config error:
    case _ _ _ Some{cause}: reject(prior, candidate, cause)
    case _ TagTree{+root} _ None{}:
      load_guard(prior,TagTree{root},config,root_error(root))

def load_prior(prior: Document, candidate: TagTree, config: Config, error: Maybe<&2, Error>) -> LoadOutcome:
  match prior candidate config error:
    case _ _ _ Some{cause}: reject(prior,candidate,cause)
    case _ TagTree{+root} Config{+limits,air} None{}:
      load_nbt(prior,TagTree{root},Config{limits,air},nbt_checked(N.encode_with(limits,root)))

def load_config(prior: Document, candidate: TagTree, config: Config, error: Maybe<&2, Error>) -> LoadOutcome:
  match prior error:
    case _ Some{cause}: reject(prior,candidate,cause)
    case Document{tree,+fields} None{}:
      load_prior(Document{tree,fields},candidate,config,prior_error(fields))

def load(prior: Document, candidate: TagTree, +config: Config) -> LoadOutcome:
  load_config(prior, candidate, config, config_error(config))

def double_tag(value: F.F64) -> N.Value:
  match value:
    case F.F64{hi, lo}: N.Double{N.Word64{hi, lo}}

def canonical_double(+value: F.F64) -> N.Value:
  double_tag(choose(F.F64, F.canonical_nan(), number_zero(value), F.is_nan(value)))

def canonical_float(+value: F32) -> N.Value:
  +bits = PL.raw(value)
  N.Float{choose(U32, 2143289344, float_zero(bits), U32.is_eq(U32.and(bits, 2139095040), 2139095040) && U32.is_ne(U32.and(bits, 8388607), 0))}

def vector_tag(vector: Vec3) -> N.Value:
  match vector:
    case Vec3{x, y, z}: N.ListTag{6, [canonical_double(x), canonical_double(y), canonical_double(z)]}

def member(key: String, value: N.Value) -> N.Member:
  N.Member{text(key), value}

def saved_members(fields: Fields) -> List<&2, N.Member>:
  match fields:
    case Fields{pos, vel, o, old, PL.State{yaw, pitch, py, pp}, head, body, fall, ground, air, fire, portal, invul, sync}:
      [member("Pos", vector_tag(pos)), member("Motion", vector_tag(vel)),
       member("Rotation", N.ListTag{5, [canonical_float(yaw), canonical_float(pitch)]}),
       member("fall_distance", canonical_double(fall)), member("OnGround", N.Byte{Bool.to_u32(ground)}),
       member("Air", N.Short{U32.and(air, 65535)}), member("Fire", N.Short{U32.and(fire, 65535)}),
       member("PortalCooldown", N.Int{portal}), member("Invulnerable", N.Byte{Bool.to_u32(invul)})]

def replacement(original: N.Member, result: Maybe<&2, N.Value>) -> N.Member:
  match original result:
    case N.Member{name, value} None{}: N.Member{name, value}
    case N.Member{name, value} Some{new}: N.Member{name, new}

def rewrite_members(members: List<&2, N.Member>, +values: List<&2, N.Member>) -> List<&2, N.Member>:
  match members:
    case Nil{}: Nil{}
    case N.Member{+name, value} <> rest:
      replacement(N.Member{name, value}, lookup(values, name)) <> rewrite_members(rest, values)

def missing_member(member: N.Member, rest: List<&2, N.Member>, found: Maybe<&2, N.Value>) -> List<&2, N.Member>:
  match found:
    case None{}: member <> rest
    case Some{value}: rest

def missing_members(values: List<&2, N.Member>, +original: List<&2, N.Member>) -> List<&2, N.Member>:
  match values:
    case Nil{}: Nil{}
    case N.Member{+name, value} <> rest:
      missing_member(N.Member{name, value}, missing_members(rest, original), lookup(original, name))

def rewritten(root: N.Root, fields: Fields) -> Result<&2, &2, Error, N.Root>:
  match root:
    case N.Root{name, N.Compound{+members}}:
      +values = saved_members(fields)
      Done{N.Root{name, N.Compound{List.append(&2, N.Member, rewrite_members(members, values), missing_members(values, members))}}}
    case _: Fail{RootType{}}

def save_output(document: Document, root: N.Root, error: Maybe<&2, Error>) -> SaveOutcome:
  match error:
    case Some{cause}: SaveRejected{document, cause}
    case None{}: Saved{document, TagTree{root}}

def save_result(document: Document, limits: N.Limits, result: Result<&2, &2, Error, N.Root>) -> SaveOutcome:
  match result:
    case Fail{error}: SaveRejected{document, error}
    case Done{+root}: save_output(document, root, nbt_checked(N.encode_with(limits, root)))

def save_guard(document: Document, config: Config, error: Maybe<&2, Error>) -> SaveOutcome:
  match document config error:
    case _ _ Some{cause}: SaveRejected{document, cause}
    case Document{TagTree{+root}, +fields} Config{limits, air} None{}:
      save_result(Document{TagTree{root}, fields}, limits, rewritten(root, fields))

def save_nbt(document: Document, config: Config, error: Maybe<&2, Error>) -> SaveOutcome:
  match document config error:
    case _ _ Some{cause}: SaveRejected{document, cause}
    case Document{TagTree{+root},fields} _ None{}:
      save_guard(Document{TagTree{root},fields},config,root_error(root))

def save_prior(document: Document, config: Config, error: Maybe<&2, Error>) -> SaveOutcome:
  match document config error:
    case _ _ Some{cause}: SaveRejected{document,cause}
    case Document{TagTree{+root},fields} Config{+limits,air} None{}:
      save_nbt(Document{TagTree{root},fields},Config{limits,air},nbt_checked(N.encode_with(limits,root)))

def save_config(document: Document, config: Config, error: Maybe<&2, Error>) -> SaveOutcome:
  match document error:
    case _ Some{cause}: SaveRejected{document,cause}
    case Document{tree,+fields} None{}:
      save_prior(Document{tree,fields},config,prior_error(fields))

def save(document: Document, +config: Config) -> SaveOutcome:
  save_config(document, config, config_error(config))

law rejection_returns_both_complete_owners:
  for prior: Document
  for candidate: TagTree
  for error: Error
  {reject(prior, candidate, error) == Rejected{prior, candidate, error} : LoadOutcome}

def rejection_returns_both_complete_owners(prior, candidate, error):
  {==}

law unselected_member_is_preserved:
  for name: N.Text
  for value: N.Value
  {replacement(N.Member{name, value}, None{}) == N.Member{name, value} : N.Member}

def unselected_member_is_preserved(name, value):
  {==}
