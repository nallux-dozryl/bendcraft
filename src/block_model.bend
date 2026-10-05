import Base
import ./json.bend as J
import ./float_parse.bend as FP

# Model data only. Rotation matrices, baking and IO are outside this module.
type Error is Data:
  Error{code: String, path: String}

type Vec3 is Data:
  Vec3{x: F32, y: F32, z: F32}

type UV is Data:
  UV{u0: F32, v0: F32, u1: F32, v1: F32}

type Direction is Data:
  Down{}
  Up{}
  North{}
  South{}
  West{}
  East{}

type Axis is Data:
  X{}
  Y{}
  Z{}

type RotationValue is Data:
  SingleAxis{axis: Axis, angle: F32}
  Euler{angles: Vec3}

type Rotation is Data:
  Rotation{origin: Vec3, value: RotationValue, rescale: Bool}

type Face is Data:
  Face{direction: Direction, cullface: Maybe<&2, Direction>, uv: Maybe<&2, UV>,
    rotation: U32, texture: String, tint_index: U32}

type Element is Data:
  Element{from: Vec3, to: Vec3, rotation: Maybe<&2, Rotation>,
    faces: List<&2, Face>, light_emission: U32, shade_direction_override: Maybe<&2, Direction>}

type GuiLight is Data:
  Side{}
  Front{}

type Transform is Data:
  Transform{rotation: Vec3, translation: Vec3, scale: Vec3}

# Missing entries are NO_TRANSFORM, distinct from explicitly parsed identity.
type Display is Data:
  Display{transforms: Map<&2, Transform>}

type Material is Data:
  Material{sprite: String, force_translucent: Bool}

type Texture is Data:
  Sprite{material: Material}
  Alias{slot: String}

type Model is Data:
  Model{parent: Maybe<&2, String>, elements: Maybe<&2, List<&2, Element>>,
    ambient_occlusion: Maybe<&2, Bool>, gui_light: Maybe<&2, GuiLight>,
    display: Maybe<&2, Display>, textures: Map<&2, Texture>}

type Library is Data:
  Library{models: Map<&2, Model>, missing: Model}

type Diagnostic is Data:
  MissingModel{id: String}
  MissingParent{id: String}
  MissingTexture{slot: String}
  TextureCycle{slot: String}

type Resolved is Data:
  Resolved{id: String, parent: Maybe<&2, String>, elements: List<&2, Element>,
    geometry_present: Bool, ambient_occlusion: Bool, gui_light: GuiLight,
    display: Display, textures: Map<&2, Texture>, diagnostics: List<&2, Diagnostic>}

def fail(-A: Data, code: String, path: String) -> Result<&2, &2, Error, A>:
  Fail{Error{code, path}}

def map_value(-A: Data, pair: Map<&2, A> & A) -> A:
  (map, value) = pair
  value

def map_has(-A: Data, pair: Map<&2, A> & Bool) -> Bool:
  (map, present) = pair
  present

def with_path(-A: Data, result: Result<&2, &2, Error, A>, path: String) -> Result<&2, &2, Error, A>:
  match result:
    case Done{value}: Done{value}
    case Fail{Error{code, old_path}}: Fail{Error{code, path}}

def object(value: J.Value, path: String) -> Result<&2, &2, Error, J.Value>:
  match value:
    case J.JObject{members}: Done{J.JObject{members}}
    case _: fail(J.Value, "ExpectedObject", path)

def required(found: Maybe<&2, J.Value>, path: String) -> Result<&2, &2, Error, J.Value>:
  match found:
    case None{}: fail(J.Value, "MissingField", path)
    case Some{value}: Done{value}

def string(value: J.Value, path: String) -> Result<&2, &2, Error, String>:
  match value:
    case J.JString{text}: Done{text}
    case J.JNumber{raw}: Done{raw}
    case J.JBool{True{}}: Done{"true"}
    case J.JBool{False{}}: Done{"false"}
    case _: fail(String, "ExpectedPrimitiveString", path)

def strict_string(value: J.Value, path: String) -> Result<&2, &2, Error, String>:
  match value:
    case J.JString{text}: Done{text}
    case _: fail(String, "ExpectedString", path)

def boolean(value: J.Value, path: String) -> Result<&2, &2, Error, Bool>:
  match value:
    case J.JBool{b}: Done{b}
    case J.JNumber{raw}: Done{False{}}
    case J.JString{text}: Done{String.eq(String.to_lower(text), "true")}
    case _: fail(Bool, "ExpectedPrimitiveBoolean", path)

def strict_boolean(value: J.Value, path: String) -> Result<&2, &2, Error, Bool>:
  match value:
    case J.JBool{b}: Done{b}
    case _: fail(Bool, "ExpectedBoolean", path)

def float_result(result: Result<&2, &2, String, F32>, path: String) -> Result<&2, &2, Error, F32>:
  match result:
    case Done{value}: Done{value}
    case Fail{code}: fail(F32, "Float:" ++ code, path)

def float(value: J.Value, path: String) -> Result<&2, &2, Error, F32>:
  match value:
    case J.JNumber{raw}: float_result(FP.parse_f32(raw), path)
    case _: fail(F32, "ExpectedFloat", path)

def vec3(value: J.Value, +path: String) -> Result<&2, &2, Error, Vec3>:
  match value:
    case J.JArray{a <> b <> c <> Nil{}}:
      do Result<&2, &2, Error, Vec3>:
        x : F32 <- float(a, path ++ "[0]")
        y : F32 <- float(b, path ++ "[1]")
        z : F32 <- float(c, path ++ "[2]")
        Done{Vec3{x, y, z}}
    case _: fail(Vec3, "ExpectedThreeValues", path)

def uv(value: J.Value, +path: String) -> Result<&2, &2, Error, UV>:
  match value:
    case J.JArray{a <> b <> c <> d <> Nil{}}:
      do Result<&2, &2, Error, UV>:
        u0 : F32 <- float(a, path ++ "[0]")
        v0 : F32 <- float(b, path ++ "[1]")
        u1 : F32 <- float(c, path ++ "[2]")
        v1 : F32 <- float(d, path ++ "[3]")
        Done{UV{u0, v0, u1, v1}}
    case _: fail(UV, "ExpectedFourUVValues", path)

def vec_div(value: Vec3, +divisor: F32) -> Vec3:
  match value:
    case Vec3{x, y, z}: Vec3{F32.div(x, divisor), F32.div(y, divisor), F32.div(z, divisor)}

def java_clamp(+value: F32, low: F32, high: F32) -> F32:
  J.choose(F32, value, F32.clamp(value, low, high), Bool.not(F32.is_eq(value, value)))

def vec_clamp(value: Vec3, +low: F32, +high: F32) -> Vec3:
  match value:
    case Vec3{x, y, z}: Vec3{java_clamp(x, low, high), java_clamp(y, low, high), java_clamp(z, low, high)}

def endpoint_checked(value: Vec3, path: String, allowed: Bool) -> Result<&2, &2, Error, Vec3>:
  match allowed:
    case True{}: Done{value}
    case False{}: fail(Vec3, "EndpointOutsideMinus16To32", path)

def endpoint_bounds(value: Vec3, path: String) -> Result<&2, &2, Error, Vec3>:
  match value:
    case Vec3{+x, +y, +z}:
      endpoint_checked(Vec3{x, y, z}, path,
        Bool.not(F32.is_lt(x, F32.neg(16.0)) || F32.is_gt(x, 32.0) || F32.is_lt(y, F32.neg(16.0)) ||
          F32.is_gt(y, 32.0) || F32.is_lt(z, F32.neg(16.0)) || F32.is_gt(z, 32.0)))

def direction_name(name: String) -> Maybe<&2, Direction>:
  match name:
    case "down": Some{Down{}}
    case "up": Some{Up{}}
    case "north": Some{North{}}
    case "south": Some{South{}}
    case "west": Some{West{}}
    case "east": Some{East{}}
    case _: None{}

def direction_result(found: Maybe<&2, Direction>, path: String) -> Result<&2, &2, Error, Direction>:
  match found:
    case Some{d}: Done{d}
    case None{}: fail(Direction, "UnknownDirection", path)

def direction(text: String, path: String) -> Result<&2, &2, Error, Direction>:
  direction_result(direction_name(text), path)

def axis(text: String, path: String) -> Result<&2, &2, Error, Axis>:
  match text:
    case "x": Done{X{}}
    case "y": Done{Y{}}
    case "z": Done{Z{}}
    case _: fail(Axis, "UnknownAxis", path)

def namespace_char(+c: U32) -> Bool:
  (U32.is_ge(c, 97) && U32.is_le(c, 122)) || J.digit(c) ||
    U32.is_eq(c, 95) || U32.is_eq(c, 45) || U32.is_eq(c, 46)

def identifier_chars(text: String, +path: Bool) -> Bool:
  match text:
    case SNil{}: True{}
    case SCon{Chr{+c}, rest}: (namespace_char(c) || (path && U32.is_eq(c, 47))) && identifier_chars(rest, path)

type IdentifierParts is Data:
  IdentifierParts{namespace: String, path: String}

def identifier_split(text: String, reversed: String) -> IdentifierParts:
  match text:
    case SNil{}: IdentifierParts{"minecraft", String.reverse(reversed)}
    case SCon{Chr{58}, rest}: IdentifierParts{String.reverse(reversed), rest}
    case SCon{h, rest}: identifier_split(rest, SCon{h, reversed})

def identifier_checked(text: String, path: String, allowed: Bool) -> Result<&2, &2, Error, String>:
  match allowed:
    case True{}: Done{text}
    case False{}: fail(String, "InvalidIdentifier", path)

def identifier_parts(parts: IdentifierParts, path: String) -> Result<&2, &2, Error, String>:
  match parts:
    case IdentifierParts{+namespace, +name}:
      +ns = J.choose(String, "minecraft", namespace, String.eq(namespace, ""))
      identifier_checked(ns ++ ":" ++ name, path, identifier_chars(ns, False{}) && identifier_chars(name, True{}))

def identifier(text: String, path: String) -> Result<&2, &2, Error, String>:
  identifier_parts(identifier_split(text, ""), path)

# Exact Gson numeric getAsInt: truncate decimal, retaining its low 32 bits.
# Exponent magnitude is bounded explicitly, rather than overflowing counters.
type IntToken is Data:
  IntToken{digits: List<&2, U32>, fraction: U32, exponent: U32, exponent_negative: Bool, negative: Bool}

def int_exponent_guard(next: U32, allowed: Bool,
  continuation: U32 -> Result<&2, &2, Error, IntToken>) -> Result<&2, &2, Error, IntToken>:
  match allowed:
    case True{}: continuation(next)
    case False{}: fail(IntToken, "UnsupportedIntegerExponent", "integer")

def int_scan_finished(admitted: Bool, reversed: List<&2, U32>, fraction: U32, exponent: U32,
  exponent_negative: Bool, negative: Bool) -> Result<&2, &2, Error, IntToken>:
  match admitted:
    case False{}: fail(IntToken, "UnsupportedIntegerExponent", "integer")
    case True{}: Done{IntToken{List.reverse(&2, U32, reversed), fraction, exponent, exponent_negative, negative}}

def int_scan_admitted(text: String, admitted: Bool, +stage: U32, reversed: List<&2, U32>, +fraction: U32, +exponent: U32,
  +exponent_negative: Bool, +negative: Bool) -> Result<&2, &2, Error, IntToken>:
  match text:
    case SNil{}: int_scan_finished(admitted, reversed, fraction, exponent, exponent_negative, negative)
    case SCon{Chr{+c}, rest}:
      match c admitted:
        case _ False{}: fail(IntToken, "UnsupportedIntegerExponent", "integer")
        case 45 True{}:
          int_scan_admitted(rest, True{}, stage, reversed, fraction, exponent,
            J.choose(Bool, True{}, exponent_negative, U32.is_ge(stage, 2)),
            J.choose(Bool, negative, True{}, U32.is_ge(stage, 2)))
        case 43 True{}: int_scan_admitted(rest, True{}, stage, reversed, fraction, exponent, exponent_negative, negative)
        case 46 True{}: int_scan_admitted(rest, True{}, 1, reversed, fraction, exponent, exponent_negative, negative)
        case 101 True{}: int_scan_admitted(rest, True{}, 2, reversed, fraction, exponent, exponent_negative, negative)
        case 69 True{}: int_scan_admitted(rest, True{}, 2, reversed, fraction, exponent, exponent_negative, negative)
        case _ True{}:
          match stage:
            case 0: int_scan_admitted(rest, True{}, stage, U32.sub(c, 48) <> reversed, fraction, exponent, exponent_negative, negative)
            case 1: int_scan_admitted(rest, True{}, stage, U32.sub(c, 48) <> reversed, U32.add(fraction, 1), exponent, exponent_negative, negative)
            case _:
              +next = U32.add(U32.mul(exponent, 10), U32.sub(c, 48))
              int_scan_admitted(rest, U32.is_le(next, 100000), stage, reversed, fraction, next, exponent_negative, negative)

def int_scan(text: String, +stage: U32, reversed: List<&2, U32>, +fraction: U32, +exponent: U32,
  +exponent_negative: Bool, +negative: Bool) -> Result<&2, &2, Error, IntToken>:
  int_scan_admitted(text, True{}, stage, reversed, fraction, exponent, exponent_negative, negative)

def digit_word(fuel: Nat, digits: List<&2, U32>, acc: U32) -> U32:
  match fuel digits:
    case 1n+p h <> t: digit_word(p, t, U32.add(U32.mul(acc, 10), h))
    case _ _: acc

def decimal_shift(fuel: Nat, value: U32) -> U32:
  match fuel:
    case 0n: value
    case 1n+p: decimal_shift(p, U32.mul(value, 10))

def integer_shift(digits: List<&2, U32>, length: Nat, shift: U32, small: Bool) -> U32:
  match small:
    case False{}: 0
    case True{}: decimal_shift(U32.to_nat(shift), digit_word(length, digits, 0))

def integer_magnitude(digits: List<&2, U32>, length: Nat, +fraction: U32, +exponent: U32, exp_negative: Bool, shift: Bool) -> U32:
  match shift:
    case True{}: integer_shift(digits, length, U32.sub(exponent, fraction), U32.is_lt(U32.sub(exponent, fraction), 32))
    case False{}:
      drop = J.choose(U32, U32.add(fraction, exponent), U32.sub(fraction, exponent), exp_negative)
      digit_word(Nat.sub(length, U32.to_nat(drop)), digits, 0)

def integer_token(token: IntToken) -> U32:
  match token:
    case IntToken{+digits, +fraction, +exponent, +exp_negative, +negative}:
      length = List.length(&2, U32, digits)
      +magnitude = integer_magnitude(digits, length, fraction, exponent, exp_negative,
        Bool.not(exp_negative) && U32.is_ge(exponent, fraction))
      J.choose(U32, U32.sub(0, magnitude), magnitude, negative)

def integer(value: J.Value, +path: String) -> Result<&2, &2, Error, U32>:
  match value:
    case J.JNumber{+raw}:
      do Result<&2, &2, Error, U32>:
        checked : F32 <- float_result(FP.parse_f32(raw), path)
        token : IntToken <- with_path(IntToken, int_scan(raw, 0, Nil{}, 0, 0, False{}, False{}), path)
        Done{integer_token(token)}
    case _: fail(U32, "ExpectedInteger", path)

def optional_int(found: Maybe<&2, J.Value>, fallback: U32, path: String) -> Result<&2, &2, Error, U32>:
  match found:
    case None{}: Done{fallback}
    case Some{v}: integer(v, path)

def optional_float(found: Maybe<&2, J.Value>, fallback: F32, path: String) -> Result<&2, &2, Error, F32>:
  match found:
    case None{}: Done{fallback}
    case Some{v}: float(v, path)

def optional_bool(found: Maybe<&2, J.Value>, fallback: Bool, path: String) -> Result<&2, &2, Error, Bool>:
  match found:
    case None{}: Done{fallback}
    case Some{v}: boolean(v, path)

def optional_uv(found: Maybe<&2, J.Value>, path: String) -> Result<&2, &2, Error, Maybe<&2, UV>>:
  match found:
    case None{}: Done{None{}}
    case Some{v}:
      do Result<&2, &2, Error, Maybe<&2, UV>>:
        parsed : UV <- uv(v, path)
        Done{Some{parsed}}

def optional_cull(found: Maybe<&2, J.Value>, path: String) -> Result<&2, &2, Error, Maybe<&2, Direction>>:
  match found:
    case None{}: Done{None{}}
    case Some{v}:
      do Result<&2, &2, Error, Maybe<&2, Direction>>:
        text : String <- string(v, path)
        Done{direction_name(text)}

def face_rotation(+value: U32, path: String) -> Result<&2, &2, Error, U32>:
  # Remainder of signed int, then floorMod to [0,360).
  +magnitude = J.choose(U32, U32.sub(0, value), value, U32.is_ge(value, 2147483648))
  +rem = U32.mod(magnitude, 360)
  +wrapped = J.choose(U32, U32.mod(U32.sub(360, rem), 360), rem, U32.is_ge(value, 2147483648))
  J.choose(Result<&2, &2, Error, U32>, Done{wrapped}, fail(U32, "InvalidFaceQuarterRotation", path), U32.is_eq(U32.mod(wrapped, 90), 0))

def face(value: J.Value, facing: Direction, +path: String) -> Result<&2, &2, Error, Face>:
  do Result<&2, &2, Error, Face>:
    +obj : J.Value <- object(value, path)
    texture_value : J.Value <- required(J.member(obj, "texture"), path ++ ".texture")
    texture : String <- string(texture_value, path ++ ".texture")
    cull : Maybe<&2, Direction> <- optional_cull(J.member(obj, "cullface"), path ++ ".cullface")
    coords : Maybe<&2, UV> <- optional_uv(J.member(obj, "uv"), path ++ ".uv")
    raw_rotation : U32 <- optional_int(J.member(obj, "rotation"), 0, path ++ ".rotation")
    rotation : U32 <- face_rotation(raw_rotation, path ++ ".rotation")
    tint : U32 <- optional_int(J.member(obj, "tintindex"), 4294967295, path ++ ".tintindex")
    Done{Face{facing, cull, coords, rotation, texture, tint}}

def face_members(members: List<&2, J.Member>, +path: String) -> Result<&2, &2, Error, List<&2, Face>>:
  match members:
    case Nil{}: Done{Nil{}}
    case J.JMember{+name, value} <> rest:
      do Result<&2, &2, Error, List<&2, Face>>:
        facing : Direction <- direction(name, path ++ "." ++ name)
        parsed : Face <- face(value, facing, path ++ "." ++ name)
        tail : List<&2, Face> <- face_members(rest, path)
        Done{parsed <> tail}

def faces(value: J.Value, +path: String) -> Result<&2, &2, Error, List<&2, Face>>:
  match value:
    case J.JObject{+members}:
      do Result<&2, &2, Error, List<&2, Face>>:
        allowed : Unit <- J.choose(Result<&2, &2, Error, Unit>, Done{Unit{}}, fail(Unit, "ExpectedOneToSixFaces", path),
          Nat.is_ge(List.length(&2, J.Member, members), 1n) && Nat.is_le(List.length(&2, J.Member, members), 6n))
        face_members(members, path)
    case _: fail(List<&2, Face>, "ExpectedFacesObject", path)

def rotation_value(+obj: J.Value, +path: String, has_axis: Bool, has_euler: Bool) -> Result<&2, &2, Error, RotationValue>:
  match has_axis has_euler:
    case True{} _:
      do Result<&2, &2, Error, RotationValue>:
        axis_value : J.Value <- required(J.member(obj, "axis"), path ++ ".axis")
        axis_text : String <- string(axis_value, path ++ ".axis")
        selected : Axis <- axis(String.to_lower(axis_text), path ++ ".axis")
        angle_value : J.Value <- required(J.member(obj, "angle"), path ++ ".angle")
        angle : F32 <- float(angle_value, path ++ ".angle")
        Done{SingleAxis{selected, angle}}
    case False{} True{}:
      do Result<&2, &2, Error, RotationValue>:
        x : F32 <- optional_float(J.member(obj, "x"), 0.0, path ++ ".x")
        y : F32 <- optional_float(J.member(obj, "y"), 0.0, path ++ ".y")
        z : F32 <- optional_float(J.member(obj, "z"), 0.0, path ++ ".z")
        Done{Euler{Vec3{x, y, z}}}
    case False{} False{}: fail(RotationValue, "MissingRotationValue", path)

def rotation(value: J.Value, +path: String) -> Result<&2, &2, Error, Rotation>:
  do Result<&2, &2, Error, Rotation>:
    +obj : J.Value <- object(value, path)
    origin_value : J.Value <- required(J.member(obj, "origin"), path ++ ".origin")
    origin : Vec3 <- vec3(origin_value, path ++ ".origin")
    selected : RotationValue <- rotation_value(obj, path,
      Bool.not(Maybe.is_none(&2, J.Value, J.member(obj, "axis"))) || Bool.not(Maybe.is_none(&2, J.Value, J.member(obj, "angle"))),
      Bool.not(Maybe.is_none(&2, J.Value, J.member(obj, "x"))) || Bool.not(Maybe.is_none(&2, J.Value, J.member(obj, "y"))) ||
        Bool.not(Maybe.is_none(&2, J.Value, J.member(obj, "z"))))
    rescale : Bool <- optional_bool(J.member(obj, "rescale"), False{}, path ++ ".rescale")
    Done{Rotation{vec_div(origin, 16.0), selected, rescale}}

def optional_rotation(found: Maybe<&2, J.Value>, path: String) -> Result<&2, &2, Error, Maybe<&2, Rotation>>:
  match found:
    case None{}: Done{None{}}
    case Some{v}:
      do Result<&2, &2, Error, Maybe<&2, Rotation>>:
        parsed : Rotation <- rotation(v, path)
        Done{Some{parsed}}

def optional_shade(found: Maybe<&2, J.Value>, +path: String) -> Result<&2, &2, Error, Maybe<&2, Direction>>:
  match found:
    case None{}: Done{None{}}
    case Some{v}:
      do Result<&2, &2, Error, Maybe<&2, Direction>>:
        text : String <- string(v, path)
        parsed : Direction <- direction(text, path)
        Done{Some{parsed}}

def light_checked(+value: U32, path: String) -> Result<&2, &2, Error, U32>:
  J.choose(Result<&2, &2, Error, U32>, Done{value}, fail(U32, "LightEmissionOutsideZeroTo15", path), U32.is_le(value, 15))

def element(value: J.Value, +path: String) -> Result<&2, &2, Error, Element>:
  do Result<&2, &2, Error, Element>:
    +obj : J.Value <- object(value, path)
    from_value : J.Value <- required(J.member(obj, "from"), path ++ ".from")
    from : Vec3 <- vec3(from_value, path ++ ".from")
    from : Vec3 <- endpoint_bounds(from, path ++ ".from")
    to_value : J.Value <- required(J.member(obj, "to"), path ++ ".to")
    to : Vec3 <- vec3(to_value, path ++ ".to")
    to : Vec3 <- endpoint_bounds(to, path ++ ".to")
    rotation : Maybe<&2, Rotation> <- optional_rotation(J.member(obj, "rotation"), path ++ ".rotation")
    faces_value : J.Value <- required(J.member(obj, "faces"), path ++ ".faces")
    faces : List<&2, Face> <- faces(faces_value, path ++ ".faces")
    light : U32 <- optional_int(J.member(obj, "light_emission"), 0, path ++ ".light_emission")
    light : U32 <- light_checked(light, path ++ ".light_emission")
    shade : Maybe<&2, Direction> <- optional_shade(J.member(obj, "shade_direction_override"), path ++ ".shade_direction_override")
    Done{Element{from, to, rotation, faces, light, shade}}

def elements(values: List<&2, J.Value>, +index: U32, +path: String) -> Result<&2, &2, Error, List<&2, Element>>:
  match values:
    case Nil{}: Done{Nil{}}
    case h <> t:
      do Result<&2, &2, Error, List<&2, Element>>:
        parsed : Element <- element(h, path ++ "[" ++ U32.show(index) ++ "]")
        tail : List<&2, Element> <- elements(t, U32.add(index, 1), path)
        Done{parsed <> tail}

def optional_elements(found: Maybe<&2, J.Value>, path: String) -> Result<&2, &2, Error, Maybe<&2, List<&2, Element>>>:
  match found:
    case None{}: Done{None{}}
    case Some{J.JArray{values}}:
      do Result<&2, &2, Error, Maybe<&2, List<&2, Element>>>:
        parsed : List<&2, Element> <- elements(values, 0, path)
        Done{Some{parsed}}
    case _: fail(Maybe<&2, List<&2, Element>>, "ExpectedElementsArray", path)

def optional_vec(found: Maybe<&2, J.Value>, fallback: Vec3, path: String) -> Result<&2, &2, Error, Vec3>:
  match found:
    case None{}: Done{fallback}
    case Some{v}: vec3(v, path)

def identity_transform() -> Transform:
  Transform{Vec3{0.0, 0.0, 0.0}, Vec3{0.0, 0.0, 0.0}, Vec3{1.0, 1.0, 1.0}}

def transform(value: J.Value, +path: String) -> Result<&2, &2, Error, Transform>:
  do Result<&2, &2, Error, Transform>:
    +obj : J.Value <- object(value, path)
    rotation : Vec3 <- optional_vec(J.member(obj, "rotation"), Vec3{0.0, 0.0, 0.0}, path ++ ".rotation")
    translation : Vec3 <- optional_vec(J.member(obj, "translation"), Vec3{0.0, 0.0, 0.0}, path ++ ".translation")
    scale : Vec3 <- optional_vec(J.member(obj, "scale"), Vec3{1.0, 1.0, 1.0}, path ++ ".scale")
    Done{Transform{rotation, vec_clamp(vec_div(translation, 16.0), F32.neg(5.0), 5.0), vec_clamp(scale, F32.neg(4.0), 4.0)}}

def display_names() -> List<&2, String>:
  "thirdperson_righthand" <> "thirdperson_lefthand" <> "firstperson_righthand" <> "firstperson_lefthand" <>
    "head" <> "gui" <> "ground" <> "fixed" <> "on_shelf" <> Nil{}

def display_one(found: Maybe<&2, J.Value>, +name: String, out: Map<&2, Transform>) -> Result<&2, &2, Error, Map<&2, Transform>>:
  match found:
    case None{}: Done{out}
    case Some{value}:
      do Result<&2, &2, Error, Map<&2, Transform>>:
        parsed : Transform <- transform(value, "display." ++ name)
        Done{Map.set(&2, Transform, out, name, parsed)}

def display_members(names: List<&2, String>, +obj: J.Value, out: Map<&2, Transform>) -> Result<&2, &2, Error, Map<&2, Transform>>:
  match names:
    case Nil{}: Done{out}
    case +name <> rest:
      do Result<&2, &2, Error, Map<&2, Transform>>:
        next : Map<&2, Transform> <- display_one(J.member(obj, name), name, out)
        display_members(rest, obj, next)

def display_fallback(+out: Map<&2, Transform>, left: String, right: String, present: Bool) -> Map<&2, Transform>:
  match present:
    case True{}: out
    case False{}:
      Map.set(&2, Transform, out, left, map_value(Transform, Map.get(Transform, identity_transform(), out, right)))

def display_left(+out: Map<&2, Transform>, +left: String, right: String) -> Map<&2, Transform>:
  display_fallback(out, left, right, map_has(Transform, Map.has(&2, Transform, out, left)))

# Do not insert a fallback identity when the right field is absent: preserve the
# NO_TRANSFORM sentinel distinction needed by parent inheritance.
def display_right_checked(out: Map<&2, Transform>, left: String, right: String, present: Bool) -> Map<&2, Transform>:
  match present:
    case False{}: out
    case True{}: display_left(out, left, right)

def display_right(+out: Map<&2, Transform>, left: String, +right: String) -> Map<&2, Transform>:
  display_right_checked(out, left, right, map_has(Transform, Map.has(&2, Transform, out, right)))

def display(value: J.Value) -> Result<&2, &2, Error, Display>:
  do Result<&2, &2, Error, Display>:
    obj : J.Value <- object(value, "display")
    parsed : Map<&2, Transform> <- display_members(display_names(), obj, MTip{})
    Done{Display{display_right(display_right(parsed, "thirdperson_lefthand", "thirdperson_righthand"),
      "firstperson_lefthand", "firstperson_righthand")}}

def optional_display(found: Maybe<&2, J.Value>) -> Result<&2, &2, Error, Maybe<&2, Display>>:
  match found:
    case None{}: Done{None{}}
    case Some{v}:
      do Result<&2, &2, Error, Maybe<&2, Display>>:
        parsed : Display <- display(v)
        Done{Some{parsed}}

def material_bool(found: Maybe<&2, J.Value>, path: String) -> Result<&2, &2, Error, Bool>:
  match found:
    case None{}: Done{False{}}
    case Some{v}: strict_boolean(v, path)

def texture_string(text: String, path: String) -> Result<&2, &2, Error, Texture>:
  match text:
    case SCon{Chr{35}, rest}: Done{Alias{rest}}
    case rest:
      do Result<&2, &2, Error, Texture>:
        name : String <- identifier(rest, path)
        Done{Sprite{Material{name, False{}}}}

def texture(value: J.Value, +path: String) -> Result<&2, &2, Error, Texture>:
  match value:
    case J.JString{text}: texture_string(text, path)
    case J.JObject{+members}:
      +obj : J.Value = J.JObject{members}
      do Result<&2, &2, Error, Texture>:
        sprite_value : J.Value <- required(J.member(obj, "sprite"), path ++ ".sprite")
        sprite : String <- strict_string(sprite_value, path ++ ".sprite")
        sprite : String <- identifier(sprite, path ++ ".sprite")
        force : Bool <- material_bool(J.member(obj, "force_translucent"), path ++ ".force_translucent")
        Done{Sprite{Material{sprite, force}}}
    case _: fail(Texture, "ExpectedTextureStringOrObject", path)

def texture_members(members: List<&2, J.Member>, out: Map<&2, Texture>) -> Result<&2, &2, Error, Map<&2, Texture>>:
  match members:
    case Nil{}: Done{out}
    case J.JMember{+name, value} <> rest:
      do Result<&2, &2, Error, Map<&2, Texture>>:
        parsed : Texture <- texture(value, "textures." ++ name)
        texture_members(rest, Map.set(&2, Texture, out, name, parsed))

def optional_textures(found: Maybe<&2, J.Value>) -> Result<&2, &2, Error, Map<&2, Texture>>:
  match found:
    case None{}: Done{MTip{}}
    case Some{J.JObject{members}}: texture_members(members, MTip{})
    case _: fail(Map<&2, Texture>, "ExpectedTexturesObject", "textures")

def parent_string(text: String) -> Result<&2, &2, Error, Maybe<&2, String>>:
  match text:
    case SNil{}: Done{None{}}
    case rest:
      do Result<&2, &2, Error, Maybe<&2, String>>:
        name : String <- identifier(rest, "parent")
        Done{Some{name}}

def optional_parent(found: Maybe<&2, J.Value>) -> Result<&2, &2, Error, Maybe<&2, String>>:
  match found:
    case None{}: Done{None{}}
    case Some{v}:
      do Result<&2, &2, Error, Maybe<&2, String>>:
        text : String <- string(v, "parent")
        parent_string(text)

def optional_ambient(found: Maybe<&2, J.Value>) -> Result<&2, &2, Error, Maybe<&2, Bool>>:
  match found:
    case None{}: Done{None{}}
    case Some{v}:
      do Result<&2, &2, Error, Maybe<&2, Bool>>:
        b : Bool <- boolean(v, "ambientocclusion")
        Done{Some{b}}

def gui_light(text: String) -> Result<&2, &2, Error, GuiLight>:
  match text:
    case "side": Done{Side{}}
    case "front": Done{Front{}}
    case _: fail(GuiLight, "InvalidGuiLight", "gui_light")

def optional_gui(found: Maybe<&2, J.Value>) -> Result<&2, &2, Error, Maybe<&2, GuiLight>>:
  match found:
    case None{}: Done{None{}}
    case Some{v}:
      do Result<&2, &2, Error, Maybe<&2, GuiLight>>:
        text : String <- string(v, "gui_light")
        parsed : GuiLight <- gui_light(text)
        Done{Some{parsed}}

def empty_model() -> Model:
  Model{None{}, None{}, None{}, None{}, None{}, MTip{}}

def decode(value: J.Value) -> Result<&2, &2, Error, Model>:
  do Result<&2, &2, Error, Model>:
    +obj : J.Value <- object(value, "model")
    parent : Maybe<&2, String> <- optional_parent(J.member(obj, "parent"))
    elements : Maybe<&2, List<&2, Element>> <- optional_elements(J.member(obj, "elements"), "elements")
    ao : Maybe<&2, Bool> <- optional_ambient(J.member(obj, "ambientocclusion"))
    light : Maybe<&2, GuiLight> <- optional_gui(J.member(obj, "gui_light"))
    transforms : Maybe<&2, Display> <- optional_display(J.member(obj, "display"))
    textures : Map<&2, Texture> <- optional_textures(J.member(obj, "textures"))
    Done{Model{parent, elements, ao, light, transforms, textures}}

def library_members(members: List<&2, J.Member>, +out: Map<&2, Model>) -> Result<&2, &2, Error, Map<&2, Model>>:
  match members:
    case Nil{}: Done{out}
    case J.JMember{+id, value} <> rest:
      do Result<&2, &2, Error, Map<&2, Model>>:
        +name : String <- identifier(id, "library." ++ id)
        unique : Unit <- J.choose(Result<&2, &2, Error, Unit>, fail(Unit, "DuplicateModelId", name), Done{Unit{}},
          map_has(Model, Map.has(&2, Model, out, name)))
        parsed : Model <- decode(value)
        library_members(rest, Map.set(&2, Model, out, name, parsed))

def fallback_allowed(value: Model) -> Bool:
  match value:
    case Model{parent, es, ao, gui, transforms, textures}: Maybe.is_none(&2, String, parent)

def decode_library(value: J.Value, +missing: Model) -> Result<&2, &2, Error, Library>:
  match value:
    case J.JObject{members}:
      do Result<&2, &2, Error, Library>:
        allowed : Unit <- J.choose(Result<&2, &2, Error, Unit>, Done{Unit{}}, fail(Unit, "UnsupportedFallbackParent", "library.missing"), fallback_allowed(missing))
        models : Map<&2, Model> <- library_members(members, MTip{})
        Done{Library{models, missing}}
    case _: fail(Library, "ExpectedModelLibraryObject", "library")

type Chain is Data:
  Chain{models: List<&2, Model>, parent: Maybe<&2, String>, diagnostics: List<&2, Diagnostic>}

type ChainState is Data:
  ChainState{current: String, seen: Map<&2, Unit>, reversed: List<&2, Model>,
    parent: Maybe<&2, String>, started: Bool, diagnostics: List<&2, Diagnostic>}

type ChainStep is Data:
  ChainContinue{state: ChainState}
  ChainFinished{chain: Chain}
  ChainRejected{error: Error}

def actual_parent(parent: String, +models: Map<&2, Model>, present: Bool) -> Maybe<&2, String>:
  match present:
    case True{}: Some{parent}
    case False{}: Some{"minecraft:builtin/missing"}

def chain_model(value: Model, +models: Map<&2, Model>, +id: String, seen: Map<&2, Unit>, reversed: List<&2, Model>,
  +direct: Maybe<&2, String>, +started: Bool, diagnostics: List<&2, Diagnostic>, existing: Bool) -> ChainStep:
  match value:
    case Model{parent, +es, +ao, +gui, +transforms, +textures}:
      match parent existing:
        case _ False{}:
          ChainFinished{Chain{List.reverse(&2, Model, Model{None{}, es, ao, gui, transforms, textures} <> reversed), direct,
            J.choose(Diagnostic, MissingParent{id}, MissingModel{id}, started) <> diagnostics}}
        case None{} True{}:
          ChainFinished{Chain{List.reverse(&2, Model, Model{None{}, es, ao, gui, transforms, textures} <> reversed), direct, diagnostics}}
        case Some{+p} True{}:
          +model : Model = Model{Some{p}, es, ao, gui, transforms, textures}
          ChainContinue{ChainState{p, Map.set(&2, Unit, seen, id, Unit{}), model <> reversed,
            J.choose(Maybe<&2, String>, direct, actual_parent(p, models, map_has(Model, Map.has(&2, Model, models, p))), started),
            True{}, diagnostics}}

def chain_seen(+models: Map<&2, Model>, missing: Model, +id: String, seen: Map<&2, Unit>, reversed: List<&2, Model>,
  direct: Maybe<&2, String>, started: Bool, diagnostics: List<&2, Diagnostic>, cycle: Bool) -> ChainStep:
  match cycle:
    case True{}: ChainRejected{Error{"ParentCycle", id}}
    case False{}:
      chain_model(map_value(Model, Map.get(Model, missing, models, id)), models, id, seen, reversed, direct, started, diagnostics,
        map_has(Model, Map.has(&2, Model, models, id)))

def chain_step(models: Map<&2, Model>, missing: Model, state: ChainState) -> ChainStep:
  match state:
    case ChainState{+id, +seen, reversed, parent, started, diagnostics}:
      chain_seen(models, missing, id, seen, reversed, parent, started, diagnostics, map_has(Unit, Map.has(&2, Unit, seen, id)))

def chain_run(fuel: Nat, +models: Map<&2, Model>, +missing: Model, step: ChainStep) -> Result<&2, &2, Error, Chain>:
  match fuel step:
    case _ ChainFinished{chain}: Done{chain}
    case _ ChainRejected{error}: Fail{error}
    case 0n ChainContinue{state}: fail(Chain, "ParentResolutionBudget", "library")
    case 1n+p ChainContinue{state}: chain_run(p, models, missing, chain_step(models, missing, state))

def merge_texture_keys(keys: List<&2, String>, +source: Map<&2, Texture>, target: Map<&2, Texture>) -> Map<&2, Texture>:
  match keys:
    case Nil{}: target
    case +name <> rest:
      merge_texture_keys(rest, source, Map.set(&2, Texture, target, name, map_value(Texture, Map.get(Texture, Alias{""}, source, name))))

def merge_textures(values: List<&2, Model>) -> Map<&2, Texture>:
  match values:
    case Nil{}: MTip{}
    case Model{parent, es, ao, gui, display, +textures} <> rest:
      merge_texture_keys(Map.keys(&2, Texture, textures), textures, merge_textures(rest))

def merge_display_keys(keys: List<&2, String>, +source: Map<&2, Transform>, target: Map<&2, Transform>) -> Map<&2, Transform>:
  match keys:
    case Nil{}: target
    case +name <> rest:
      merge_display_keys(rest, source, Map.set(&2, Transform, target, name,
        map_value(Transform, Map.get(Transform, identity_transform(), source, name))))

def merge_display(found: Maybe<&2, Display>, target: Map<&2, Transform>) -> Map<&2, Transform>:
  match found:
    case None{}: target
    case Some{Display{+transforms}}: merge_display_keys(Map.keys(&2, Transform, transforms), transforms, target)

def merge_displays(values: List<&2, Model>) -> Map<&2, Transform>:
  match values:
    case Nil{}: MTip{}
    case Model{parent, es, ao, gui, display, textures} <> rest: merge_display(display, merge_displays(rest))

def chain_elements(values: List<&2, Model>) -> Maybe<&2, List<&2, Element>>:
  match values:
    case Nil{}: None{}
    case Model{parent, Some{es}, ao, gui, display, textures} <> rest: Some{es}
    case Model{parent, None{}, ao, gui, display, textures} <> rest: chain_elements(rest)

def chain_ambient(values: List<&2, Model>) -> Bool:
  match values:
    case Nil{}: True{}
    case Model{parent, es, Some{ao}, gui, display, textures} <> rest: ao
    case Model{parent, es, None{}, gui, display, textures} <> rest: chain_ambient(rest)

def chain_light(values: List<&2, Model>) -> GuiLight:
  match values:
    case Nil{}: Side{}
    case Model{parent, es, ao, Some{gui}, display, textures} <> rest: gui
    case Model{parent, es, ao, None{}, display, textures} <> rest: chain_light(rest)

def resolved_elements(id: String, parent: Maybe<&2, String>, es: Maybe<&2, List<&2, Element>>, ao: Bool, gui: GuiLight,
  transforms: Map<&2, Transform>, textures: Map<&2, Texture>, diagnostics: List<&2, Diagnostic>) -> Resolved:
  match es:
    case None{}: Resolved{id, parent, Nil{}, False{}, ao, gui, Display{transforms}, textures, diagnostics}
    case Some{values}: Resolved{id, parent, values, True{}, ao, gui, Display{transforms}, textures, diagnostics}

def resolved_chain(id: String, value: Chain) -> Resolved:
  match value:
    case Chain{+models, parent, diagnostics}:
      resolved_elements(id, parent, chain_elements(models), chain_ambient(models), chain_light(models),
        merge_displays(models), merge_textures(models), diagnostics)

def resolve_checked(library: Library, +id: String, supported: Bool) -> Result<&2, &2, Error, Resolved>:
  match library:
    case Library{+models, +missing}:
      match supported:
        case False{}: fail(Resolved, "LibraryLimitOrFallbackParent", id)
        case True{}:
          do Result<&2, &2, Error, Resolved>:
            chain : Chain <- chain_run(Nat.add(2n, List.length(&2, String, Map.keys(&2, Model, models))), models, missing,
              ChainContinue{ChainState{id, MTip{}, Nil{}, None{}, False{}, Nil{}}})
            Done{resolved_chain(J.choose(String, id, "minecraft:builtin/missing",
              map_has(Model, Map.has(&2, Model, models, id))), chain)}

def resolve(library: Library, id: String) -> Result<&2, &2, Error, Resolved>:
  match library:
    case Library{+models, +missing}:
      do Result<&2, &2, Error, Resolved>:
        name : String <- identifier(id, "model.id")
        resolve_checked(Library{models, missing}, name, fallback_allowed(missing) &&
          Nat.is_le(List.length(&2, String, Map.keys(&2, Model, models)), 65535n))

type MaterialStatus is Data:
  FoundMaterial{material: Material}
  UnresolvedMaterial{diagnostic: Diagnostic}

type MaterialState is Data:
  MaterialState{slot: String, seen: Map<&2, Unit>}

type MaterialStep is Data:
  MaterialContinue{state: MaterialState}
  MaterialFinished{status: MaterialStatus}

def material_texture(value: Texture, slot: String, seen: Map<&2, Unit>, present: Bool) -> MaterialStep:
  match value present:
    case _ False{}: MaterialFinished{UnresolvedMaterial{MissingTexture{slot}}}
    case Sprite{m} True{}: MaterialFinished{FoundMaterial{m}}
    case Alias{target} True{}: MaterialContinue{MaterialState{target, Map.set(&2, Unit, seen, slot, Unit{})}}

def material_seen(+textures: Map<&2, Texture>, +slot: String, seen: Map<&2, Unit>, cycle: Bool) -> MaterialStep:
  match cycle:
    case True{}: MaterialFinished{UnresolvedMaterial{TextureCycle{slot}}}
    case False{}:
      material_texture(map_value(Texture, Map.get(Texture, Alias{""}, textures, slot)), slot, seen,
        map_has(Texture, Map.has(&2, Texture, textures, slot)))

def material_step(textures: Map<&2, Texture>, state: MaterialState) -> MaterialStep:
  match state:
    case MaterialState{+slot, +seen}:
      material_seen(textures, slot, seen, map_has(Unit, Map.has(&2, Unit, seen, slot)))

def material_run(fuel: Nat, +textures: Map<&2, Texture>, step: MaterialStep) -> MaterialStatus:
  match fuel step:
    case _ MaterialFinished{status}: status
    case 0n MaterialContinue{MaterialState{slot, seen}}: UnresolvedMaterial{TextureCycle{slot}}
    case 1n+p MaterialContinue{state}: material_run(p, textures, material_step(textures, state))

def strip_slot(text: String) -> String:
  match text:
    case SCon{Chr{35}, rest}: rest
    case rest: rest

def material_status(value: Resolved, slot: String) -> MaterialStatus:
  match value:
    case Resolved{id, parent, es, present, ao, gui, display, +textures, diagnostics}:
      material_run(Nat.add(2n, List.length(&2, String, Map.keys(&2, Texture, textures))), textures,
        MaterialContinue{MaterialState{strip_slot(slot), MTip{}}})

def material_result(status: MaterialStatus) -> Maybe<&2, Material>:
  match status:
    case FoundMaterial{m}: Some{m}
    case UnresolvedMaterial{diagnostic}: None{}

def material(value: Resolved, slot: String) -> Maybe<&2, Material>:
  material_result(material_status(value, slot))

type Graph is Data:
  Graph{models: Map<&2, Resolved>, rejected: List<&2, Error>}

type GraphState is Data:
  GraphState{pending: List<&2, String>, seen: Map<&2, Unit>, models: Map<&2, Resolved>, rejected: List<&2, Error>}

type GraphStep is Data:
  GraphContinue{state: GraphState}
  GraphFinished{graph: Graph}

def parent_pending(model: Model, pending: List<&2, String>) -> List<&2, String>:
  match model:
    case Model{None{}, es, ao, gui, display, textures}: pending
    case Model{Some{id}, es, ao, gui, display, textures}: id <> pending

def graph_record(id: String, pending: List<&2, String>, seen: Map<&2, Unit>, models: Map<&2, Resolved>, rejected: List<&2, Error>,
  result: Result<&2, &2, Error, Resolved>) -> GraphStep:
  match result:
    case Fail{error}: GraphContinue{GraphState{pending, seen, models, error <> rejected}}
    case Done{value}: GraphContinue{GraphState{pending, seen, Map.set(&2, Resolved, models, id, value), rejected}}

def graph_seen(library: Library, +id: String, pending: List<&2, String>, seen: Map<&2, Unit>, models: Map<&2, Resolved>,
  rejected: List<&2, Error>, visited: Bool) -> GraphStep:
  match library:
    case Library{+source, +missing}:
      match visited:
        case True{}: GraphContinue{GraphState{pending, seen, models, rejected}}
        case False{}:
          graph_record(id, parent_pending(map_value(Model, Map.get(Model, missing, source, id)), pending),
            Map.set(&2, Unit, seen, id, Unit{}), models, rejected, resolve(Library{source, missing}, id))

def graph_step(library: Library, state: GraphState) -> GraphStep:
  match state:
    case GraphState{Nil{}, seen, models, rejected}: GraphFinished{Graph{models, List.reverse(&2, Error, rejected)}}
    case GraphState{+id <> pending, +seen, models, rejected}:
      graph_seen(library, id, pending, seen, models, rejected, map_has(Unit, Map.has(&2, Unit, seen, id)))

def graph_run(fuel: Nat, +library: Library, step: GraphStep) -> Result<&2, &2, Error, Graph>:
  match fuel step:
    case _ GraphFinished{graph}: Done{graph}
    case 0n GraphContinue{state}: fail(Graph, "GraphResolutionBudget", "library")
    case 1n+p GraphContinue{state}: graph_run(p, library, graph_step(library, state))

def normalize_roots(roots: List<&2, String>) -> Result<&2, &2, Error, List<&2, String>>:
  match roots:
    case Nil{}: Done{Nil{}}
    case h <> t:
      do Result<&2, &2, Error, List<&2, String>>:
        name : String <- identifier(h, "root")
        tail : List<&2, String> <- normalize_roots(t)
        Done{name <> tail}

def graph_checked(library: Library, +roots: List<&2, String>, supported: Bool) -> Result<&2, &2, Error, Graph>:
  match library:
    case Library{+models, +missing}:
      match supported:
        case False{}: fail(Graph, "LibraryLimitOrFallbackParent", "library")
        case True{}:
          fuel = Nat.add(4n, Nat.add(Nat.mul(2n, List.length(&2, String, roots)), Nat.mul(2n, List.length(&2, String, Map.keys(&2, Model, models)))))
          graph_run(fuel, Library{models, missing}, GraphContinue{GraphState{"minecraft:builtin/missing" <> roots, MTip{}, MTip{}, Nil{}}})

def resolve_graph(library: Library, roots: List<&2, String>) -> Result<&2, &2, Error, Graph>:
  match library:
    case Library{+models, +missing}:
      do Result<&2, &2, Error, Graph>:
        +names : List<&2, String> <- normalize_roots(roots)
        graph_checked(Library{models, missing}, names, fallback_allowed(missing) &&
          Nat.is_le(List.length(&2, String, Map.keys(&2, Model, models)), 65535n) &&
          Nat.is_le(List.length(&2, String, names), 65535n))
