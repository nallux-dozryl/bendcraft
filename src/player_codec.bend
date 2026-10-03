import Base
import ./f64.bend as F
import ./geometry.bend as G
import ./movement.bend as M
import ./travel.bend as T
import ./player_tick.bend as PT
import ./support.bend as SP
import ./nbt.bend as N

# Complete representation of the admitted neutral-player snapshot, not vanilla
# player.dat. State and support are Data: callers retain them on any failure.
type Snapshot is Data:
  Snapshot{state: PT.State, support: SP.State, yaw: F32, pitch: F32, dimension: String}

type Error is Data:
  NbtError{message: String}
  SchemaError{field: String, message: String}
  UnsupportedVersion{bits: U32}
  UnsupportedDimension{}
  UnsupportedByteBudget{max_bytes: U32}
  InvalidState{cause: PT.Error}
  InconsistentBody{}
  InvalidView{field: U32}

type Field is Data:
  Field{name: String, value: N.Value}

def default_max_bytes() -> U32:
  4096

def nbt_limits(max_bytes: U32) -> N.Limits:
  N.Limits{max_bytes, 3, 16}

def require(valid: Bool, field: String, message: String) -> Result<&2, &2, Error, Unit>:
  N.choose(Result<&2, &2, Error, Unit>, Done{Unit{}}, Fail{SchemaError{field, message}}, valid)

def nbt_result(-A: Data, result: Result<&2, &2, String, A>) -> Result<&2, &2, Error, A>:
  match result:
    case Done{value}: Done{value}
    case Fail{message}: Fail{NbtError{message}}

def float_bits(value: U32) -> F32:
  match value:
    case U32{word}: F32{word}

def dimension_known(+name: String) -> Bool:
  String.eq(name, "minecraft:overworld") || String.eq(name, "minecraft:the_nether") || String.eq(name, "minecraft:the_end")

def boxes_consistent(a: G.AABB, b: G.AABB) -> Bool:
  match a b:
    case G.AABB{+a, +b, +c, +d, +e, +f} G.AABB{aa, bb, cc, dd, ee, ff}:
      F.is_le(a, d) && F.is_le(b, e) && F.is_le(c, f) &&
      F.is_eq(a, aa) && F.is_eq(b, bb) && F.is_eq(c, cc) && F.is_eq(d, dd) && F.is_eq(e, ee) && F.is_eq(f, ff)

def body_consistent(body: M.Body) -> Bool:
  match body:
    case M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below}:
      boxes_consistent(box, M.make_box(position, width, height))

def consistency_error(valid: Bool, rest: Maybe<&2, Error>) -> Maybe<&2, Error>:
  match valid:
    case False{}: Some{InconsistentBody{}}
    case True{}: rest

def first_view_error(pitch: F32, first: Maybe<&2, Error>) -> Maybe<&2, Error>:
  match first:
    case Some{error}: Some{error}
    case None{}:
      +wide = F.from_f32(pitch)
      +bound = F.from_f32(float_bits(1070141403))
      N.choose(Maybe<&2, Error>, None{}, Some{InvalidView{1}},
        F.is_finite(wide) && F.is_ge(wide, F.neg(bound)) && F.is_le(wide, bound))

def view_error(yaw: F32, pitch: F32) -> Maybe<&2, Error>:
  first_view_error(pitch, N.choose(Maybe<&2, Error>, None{}, Some{InvalidView{0}}, F.is_finite(F.from_f32(yaw))))

def state_error(error: Maybe<&2, PT.Error>, rest: Maybe<&2, Error>) -> Maybe<&2, Error>:
  match error:
    case Some{cause}: Some{InvalidState{cause}}
    case None{}: rest

def dimension_error(valid: Bool, rest: Maybe<&2, Error>) -> Maybe<&2, Error>:
  match valid:
    case False{}: Some{UnsupportedDimension{}}
    case True{}: rest

def snapshot_error(snapshot: Snapshot) -> Maybe<&2, Error>:
  match snapshot:
    case Snapshot{+state, support, yaw, pitch, dimension}:
      PT.State{+body, input, jumping, delay, trigger, sync, speed, head} = state
      state_error(PT.state_error(state), consistency_error(body_consistent(body),
        dimension_error(dimension_known(dimension), view_error(yaw, pitch))))

def validated(snapshot: Snapshot, error: Maybe<&2, Error>) -> Result<&2, &2, Error, Snapshot>:
  match error:
    case Some{error}: Fail{error}
    case None{}: Done{snapshot}

def validate(+snapshot: Snapshot) -> Result<&2, &2, Error, Snapshot>:
  validated(snapshot, snapshot_error(snapshot))

# Schema names and supported dimensions are ASCII. Reject rather than replace a
# non-ASCII/surrogate name; byte/depth/count limits were checked by N.decode_with.
def text_units(text: String) -> List<&2, U32>:
  match text:
    case SNil{}: Nil{}
    case SCon{Chr{c}, rest}: c <> text_units(rest)

def text(text: String) -> N.Text:
  N.Text{text_units(text)}

def ascii_units(units: List<&2, U32>, acc: String) -> Result<&2, &2, Error, String>:
  match units:
    case Nil{}: Done{String.reverse(acc)}
    case +unit <> +rest:
      N.lazy_choose(Result<&2, &2, Error, String>, u => ascii_units(rest, SCon{Chr{unit}, acc}),
        u => Fail{SchemaError{"name", "expected ASCII schema text"}}, U32.is_le(unit, 127))

def read_text(value: N.Text) -> Result<&2, &2, Error, String>:
  match value:
    case N.Text{+units}:
      do Result<&2, &2, Error, String>:
        count : U32 <- nbt_result(U32, N.length_bound(U32, 64n, units, 0))
        ascii_units(units, "")

def member_present(names: List<&2, String>, +name: String) -> Bool:
  match names:
    case Nil{}: False{}
    case h <> rest: String.eq(h, name) || member_present(rest, name)

def fields_go(members: List<&2, N.Member>, +expected: List<&2, String>, +seen: List<&2, String>, +count: Nat,
              acc: List<&2, Field>) -> Result<&2, &2, Error, List<&2, Field>>:
  match members:
    case Nil{}:
      do Result<&2, &2, Error, List<&2, Field>>:
        require(Nat.is_eq(count, List.length(&2, String, expected)), "compound", "missing schema field")
        return acc
    case N.Member{name, value} <> rest:
      do Result<&2, &2, Error, List<&2, Field>>:
        +key : String <- read_text(name)
        require(member_present(expected, key), key, "unexpected schema field")
        require(Bool.not(member_present(seen, key)), key, "duplicate schema field")
        fields_go(rest, expected, key <> seen, 1n+count, Field{key, value} <> acc)

def fields(value: N.Value, expected: List<&2, String>) -> Result<&2, &2, Error, List<&2, Field>>:
  match value:
    case N.Compound{members}: fields_go(members, expected, Nil{}, 0n, Nil{})
    case _: Fail{SchemaError{"compound", "expected Compound tag"}}

def field(values: List<&2, Field>, +name: String) -> N.Value:
  match values:
    case Nil{}: N.End{}
    case Field{+key, +value} <> rest: N.choose(N.Value, value, field(rest, name), String.eq(key, name))

def float_value(value: N.Value, name: String) -> Result<&2, &2, Error, F32>:
  match value:
    case N.Float{bits}: Done{float_bits(bits)}
    case _: Fail{SchemaError{name, "expected Float tag"}}

def int_value(value: N.Value, name: String) -> Result<&2, &2, Error, U32>:
  match value:
    case N.Int{bits}: Done{bits}
    case _: Fail{SchemaError{name, "expected Int tag"}}

def bool_value(value: N.Value, name: String) -> Result<&2, &2, Error, Bool>:
  match value:
    case N.Byte{0}: Done{False{}}
    case N.Byte{1}: Done{True{}}
    case _: Fail{SchemaError{name, "expected Boolean Byte 0 or 1"}}

def vector_value(value: N.Value, name: String) -> Result<&2, &2, Error, M.Vec3>:
  match value:
    case N.ListTag{6, N.Double{N.Word64{a, b}} <> N.Double{N.Word64{c, d}} <> N.Double{N.Word64{e, f}} <> Nil{}}:
      Done{M.Vec3{F.F64{a, b}, F.F64{c, d}, F.F64{e, f}}}
    case _: Fail{SchemaError{name, "expected exactly three Double tags"}}

def box_value(value: N.Value) -> Result<&2, &2, Error, G.AABB>:
  match value:
    case N.ListTag{6, N.Double{N.Word64{a, b}} <> N.Double{N.Word64{c, d}} <> N.Double{N.Word64{e, f}} <>
         N.Double{N.Word64{g, h}} <> N.Double{N.Word64{i, j}} <> N.Double{N.Word64{k, l}} <> Nil{}}:
      Done{G.AABB{F.F64{a, b}, F.F64{c, d}, F.F64{e, f}, F.F64{g, h}, F.F64{i, j}, F.F64{k, l}}}
    case _: Fail{SchemaError{"box", "expected exactly six Double tags"}}

def input_value(value: N.Value) -> Result<&2, &2, Error, PT.Input>:
  match value:
    case N.ListTag{5, N.Float{a} <> N.Float{b} <> N.Float{c} <> Nil{}}:
      Done{PT.Input{float_bits(a), float_bits(b), float_bits(c)}}
    case _: Fail{SchemaError{"input", "expected exactly three Float tags"}}

def body_value(value: N.Value) -> Result<&2, &2, Error, M.Body>:
  do Result<&2, &2, Error, M.Body>:
    +fs : List<&2, Field> <- fields(value, ["position", "box", "velocity", "width", "height", "on_ground", "horizontal_collision", "vertical_collision", "vertical_collision_below"])
    position : M.Vec3 <- vector_value(field(fs, "position"), "position")
    box : G.AABB <- box_value(field(fs, "box"))
    velocity : M.Vec3 <- vector_value(field(fs, "velocity"), "velocity")
    width : F32 <- float_value(field(fs, "width"), "width")
    height : F32 <- float_value(field(fs, "height"), "height")
    ground : Bool <- bool_value(field(fs, "on_ground"), "on_ground")
    horizontal : Bool <- bool_value(field(fs, "horizontal_collision"), "horizontal_collision")
    vertical : Bool <- bool_value(field(fs, "vertical_collision"), "vertical_collision")
    below : Bool <- bool_value(field(fs, "vertical_collision_below"), "vertical_collision_below")
    return M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below}

def main_value(value: N.Value) -> Result<&2, &2, Error, Maybe<&2, T.BlockPos>>:
  match value:
    case N.ListTag{3, Nil{}}: Done{None{}}
    case N.ListTag{3, N.Int{x} <> N.Int{y} <> N.Int{z} <> Nil{}}: Done{Some{T.BlockPos{x, y, z}}}
    case _: Fail{SchemaError{"support.main", "expected zero or three Int tags"}}

def support_value(value: N.Value) -> Result<&2, &2, Error, SP.State>:
  do Result<&2, &2, Error, SP.State>:
    +fs : List<&2, Field> <- fields(value, ["main", "on_ground_no_blocks"])
    main : Maybe<&2, T.BlockPos> <- main_value(field(fs, "main"))
    no_blocks : Bool <- bool_value(field(fs, "on_ground_no_blocks"), "support.on_ground_no_blocks")
    return SP.State{main, no_blocks}

def version_value(value: N.Value) -> Result<&2, &2, Error, Unit>:
  match value:
    case N.Int{1}: Done{Unit{}}
    case N.Int{bits}: Fail{UnsupportedVersion{bits}}
    case _: Fail{SchemaError{"format", "expected Int tag"}}

def dimension_validated(name: String, valid: Bool) -> Result<&2, &2, Error, String>:
  match valid:
    case False{}: Fail{UnsupportedDimension{}}
    case True{}: Done{name}

def dimension_text(result: Result<&2, &2, Error, String>) -> Result<&2, &2, Error, String>:
  match result:
    case Fail{error}: Fail{UnsupportedDimension{}}
    case Done{+name}: dimension_validated(name, dimension_known(name))

def dimension_value(value: N.Value) -> Result<&2, &2, Error, String>:
  match value:
    case N.StringTag{name}: dimension_text(read_text(name))
    case _: Fail{SchemaError{"dimension", "expected String tag"}}

def snapshot(root: N.Root) -> Result<&2, &2, Error, Snapshot>:
  match root:
    case N.Root{name, value}:
      do Result<&2, &2, Error, Snapshot>:
        root_name : String <- read_text(name)
        require(String.eq(root_name, "bendex:player"), "$root", "wrong root name")
        +fs : List<&2, Field> <- fields(value, ["format", "dimension", "body", "support", "input", "jumping", "jump_delay", "jump_trigger", "needs_sync", "stored_speed", "head_yaw", "view_yaw", "view_pitch"])
        version_value(field(fs, "format"))
        dimension : String <- dimension_value(field(fs, "dimension"))
        body : M.Body <- body_value(field(fs, "body"))
        support : SP.State <- support_value(field(fs, "support"))
        input : PT.Input <- input_value(field(fs, "input"))
        jumping : Bool <- bool_value(field(fs, "jumping"), "jumping")
        delay : U32 <- int_value(field(fs, "jump_delay"), "jump_delay")
        trigger : U32 <- int_value(field(fs, "jump_trigger"), "jump_trigger")
        sync : Bool <- bool_value(field(fs, "needs_sync"), "needs_sync")
        speed : F32 <- float_value(field(fs, "stored_speed"), "stored_speed")
        head : F32 <- float_value(field(fs, "head_yaw"), "head_yaw")
        yaw : F32 <- float_value(field(fs, "view_yaw"), "view_yaw")
        pitch : F32 <- float_value(field(fs, "view_pitch"), "view_pitch")
        validate(Snapshot{PT.State{body, input, jumping, delay, trigger, sync, speed, head}, support, yaw, pitch, dimension})

def decode_root(result: Result<&2, &2, Error, N.Root>) -> Result<&2, &2, Error, Snapshot>:
  match result:
    case Fail{error}: Fail{error}
    case Done{root}: snapshot(root)

def decode_gate(max_bytes: U32, bytes: List<&2, U32>, supported: Bool) -> Result<&2, &2, Error, Snapshot>:
  match supported:
    case False{}: Fail{UnsupportedByteBudget{max_bytes}}
    case True{}: decode_root(nbt_result(N.Root, N.decode_with(nbt_limits(max_bytes), bytes)))

def decode_with(+max_bytes: U32, bytes: List<&2, U32>) -> Result<&2, &2, Error, Snapshot>:
  decode_gate(max_bytes, bytes, U32.is_le(max_bytes, 65536))

def decode(bytes: List<&2, U32>) -> Result<&2, &2, Error, Snapshot>:
  decode_with(default_max_bytes(), bytes)

def member(name: String, value: N.Value) -> N.Member:
  N.Member{text(name), value}

def bool_tag(value: Bool) -> N.Value:
  match value:
    case False{}: N.Byte{0}
    case True{}: N.Byte{1}

def double_tag(value: F.F64) -> N.Value:
  match value:
    case F.F64{hi, lo}: N.Double{N.Word64{hi, lo}}

def vector_tag(value: M.Vec3) -> N.Value:
  match value:
    case M.Vec3{x, y, z}: N.ListTag{6, [double_tag(x), double_tag(y), double_tag(z)]}

def box_tag(value: G.AABB) -> N.Value:
  match value:
    case G.AABB{a, b, c, d, e, f}: N.ListTag{6, [double_tag(a), double_tag(b), double_tag(c), double_tag(d), double_tag(e), double_tag(f)]}

def body_tag(value: M.Body) -> N.Value:
  match value:
    case M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below}:
      N.Compound{[member("position", vector_tag(position)), member("box", box_tag(box)), member("velocity", vector_tag(velocity)),
        member("width", N.Float{F32.bits(width)}), member("height", N.Float{F32.bits(height)}), member("on_ground", bool_tag(ground)),
        member("horizontal_collision", bool_tag(horizontal)), member("vertical_collision", bool_tag(vertical)), member("vertical_collision_below", bool_tag(below))]}

def main_tag(value: Maybe<&2, T.BlockPos>) -> N.Value:
  match value:
    case None{}: N.ListTag{3, Nil{}}
    case Some{T.BlockPos{x, y, z}}: N.ListTag{3, [N.Int{x}, N.Int{y}, N.Int{z}]}

def support_tag(value: SP.State) -> N.Value:
  match value:
    case SP.State{main, no_blocks}: N.Compound{[member("main", main_tag(main)), member("on_ground_no_blocks", bool_tag(no_blocks))]}

def input_tag(value: PT.Input) -> N.Value:
  match value:
    case PT.Input{x, y, z}: N.ListTag{5, [N.Float{F32.bits(x)}, N.Float{F32.bits(y)}, N.Float{F32.bits(z)}]}

def root(value: Snapshot) -> N.Root:
  match value:
    case Snapshot{PT.State{body, input, jumping, delay, trigger, sync, speed, head}, support, yaw, pitch, dimension}:
      N.Root{text("bendex:player"), N.Compound{[
        member("format", N.Int{1}), member("dimension", N.StringTag{text(dimension)}), member("body", body_tag(body)), member("support", support_tag(support)),
        member("input", input_tag(input)), member("jumping", bool_tag(jumping)), member("jump_delay", N.Int{delay}), member("jump_trigger", N.Int{trigger}),
        member("needs_sync", bool_tag(sync)), member("stored_speed", N.Float{F32.bits(speed)}), member("head_yaw", N.Float{F32.bits(head)}),
        member("view_yaw", N.Float{F32.bits(yaw)}), member("view_pitch", N.Float{F32.bits(pitch)})]}}

def encode_validated(max_bytes: U32, result: Result<&2, &2, Error, Snapshot>) -> Result<&2, &2, Error, List<&2, U32>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{value}: nbt_result(List<&2, U32>, N.encode_with(nbt_limits(max_bytes), root(value)))

def encode_gate(max_bytes: U32, snapshot: Snapshot, supported: Bool) -> Result<&2, &2, Error, List<&2, U32>>:
  match supported:
    case False{}: Fail{UnsupportedByteBudget{max_bytes}}
    case True{}: encode_validated(max_bytes, validate(snapshot))

def encode_with(+max_bytes: U32, snapshot: Snapshot) -> Result<&2, &2, Error, List<&2, U32>>:
  encode_gate(max_bytes, snapshot, U32.is_le(max_bytes, 65536))

def encode(snapshot: Snapshot) -> Result<&2, &2, Error, List<&2, U32>>:
  encode_with(default_max_bytes(), snapshot)
