import Base
import ../src/f64.bend as F
import ../src/geometry.bend as G
import ../src/movement.bend as M
import ../src/locomotion.bend as L
import ../src/travel.bend as T
import ../src/player_input.bend as PI
import ../src/player_tick.bend as P
import ../src/local_input.bend as I

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

def vector_show(vector: PI.Vector) -> String:
  PI.Vector{x, z} = vector
  U32.show(F32.bits(x)) ++ "|" ++ U32.show(F32.bits(z))

def state_show(state: I.State) -> String:
  I.State{keys, move, trigger, crouching, x, y, xo, yo} = state
  U32.show(PI.mask(keys)) ++ "|" ++ vector_show(move) ++ "|" ++ U32.show(trigger) ++ "|" ++ U32.show(Bool.to_u32(crouching)) ++ "|" ++
    U32.show(F32.bits(x)) ++ "|" ++ U32.show(F32.bits(y)) ++ "|" ++ U32.show(F32.bits(xo)) ++ "|" ++ U32.show(F32.bits(yo))

def f64_show(value: F.F64) -> String:
  F.F64{hi, lo} = value
  U32.show(hi) ++ "|" ++ U32.show(lo)

def vec3_show(value: M.Vec3) -> String:
  M.Vec3{x, y, z} = value
  f64_show(x) ++ "|" ++ f64_show(y) ++ "|" ++ f64_show(z)

def box_show(value: G.AABB) -> String:
  G.AABB{a, b, c, d, e, f} = value
  f64_show(a) ++ "|" ++ f64_show(b) ++ "|" ++ f64_show(c) ++ "|" ++ f64_show(d) ++ "|" ++ f64_show(e) ++ "|" ++ f64_show(f)

def body_show(value: M.Body) -> String:
  M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below} = value
  vec3_show(position) ++ "|" ++ box_show(box) ++ "|" ++ vec3_show(velocity) ++ "|" ++ U32.show(F32.bits(width)) ++ "|" ++ U32.show(F32.bits(height)) ++ "|" ++
    U32.show(Bool.to_u32(ground)) ++ "|" ++ U32.show(Bool.to_u32(horizontal)) ++ "|" ++ U32.show(Bool.to_u32(vertical)) ++ "|" ++ U32.show(Bool.to_u32(below))

def player_show(value: P.State) -> String:
  P.State{body, P.Input{x, y, z}, jump, delay, trigger, sync, speed, head} = value
  body_show(body) ++ "|" ++ U32.show(F32.bits(x)) ++ "|" ++ U32.show(F32.bits(y)) ++ "|" ++ U32.show(F32.bits(z)) ++ "|" ++
    U32.show(Bool.to_u32(jump)) ++ "|" ++ U32.show(delay) ++ "|" ++ U32.show(trigger) ++ "|" ++ U32.show(Bool.to_u32(sync)) ++ "|" ++ U32.show(F32.bits(speed)) ++ "|" ++ U32.show(F32.bits(head))

def parse_state(fields: List<&2, U32>) -> Maybe<&2, I.Controls>:
  match fields:
    case keys <> x <> z <> trigger <> crouching <> bx <> by <> ox <> oy <> sprinting <> Nil{}:
      Some{I.Controls{I.State{PI.from_mask(keys), PI.Vector{L.float_bits(x), L.float_bits(z)}, trigger, bit(crouching), L.float_bits(bx), L.float_bits(by), L.float_bits(ox), L.float_bits(oy)}, bit(sprinting), Nil{}}}
    case _: None{}

def parse_player_input(body: M.Body, fields: List<&2, U32>) -> Maybe<&2, P.State>:
  match fields:
    case x <> y <> z <> jump <> delay <> trigger <> sync <> speed <> head <> Nil{}:
      Some{P.State{body, P.Input{L.float_bits(x), L.float_bits(y), L.float_bits(z)}, bit(jump), delay, trigger, bit(sync), L.float_bits(speed), L.float_bits(head)}}
    case _: None{}

def parse_player(fields: List<&2, U32>) -> Maybe<&2, P.State>:
  match fields:
    case xh <> xl <> yh <> yl <> zh <> zl <> ah <> al <> bh <> bl <> ch <> cl <> dh <> dl <> eh <> el <> fh <> fl <> vxh <> vxl <> vyh <> vyl <> vzh <> vzl <> width <> height <> ground <> horizontal <> vertical <> below <> rest:
      parse_player_input(M.Body{M.Vec3{F.F64{xh, xl}, F.F64{yh, yl}, F.F64{zh, zl}},
        G.AABB{F.F64{ah, al}, F.F64{bh, bl}, F.F64{ch, cl}, F.F64{dh, dl}, F.F64{eh, el}, F.F64{fh, fl}},
        M.Vec3{F.F64{vxh, vxl}, F.F64{vyh, vyl}, F.F64{vzh, vzl}}, L.float_bits(width), L.float_bits(height), bit(ground), bit(horizontal), bit(vertical), bit(below)}, rest)
    case _: None{}

def parse_apply(fields: List<&2, U32>) -> Maybe<&2, I.ApplyContext>:
  match fields:
    case x <> y <> z <> friction <> sh <> sl <> gh <> gl <> fh <> fl <> dh <> dl <> yaw <> maximum <> sprinting <> no_gravity <> discard <> strength_hi <> strength_lo <> factor <> affected <> sneak_hi <> sneak_lo <> pitch <> Nil{}:
      Some{I.ApplyContext{P.Context{T.Context{T.GroundSample{T.BlockPos{x, y, z}, L.float_bits(friction)}, T.Attributes{F.F64{sh, sl}, F.F64{gh, gl}, F.F64{fh, fl}, F.F64{dh, dl}}, L.float_bits(yaw), L.float_bits(maximum), bit(sprinting), bit(no_gravity), bit(discard), T.NeutralDryAir{}}, F.F64{strength_hi, strength_lo}, L.float_bits(factor), bit(affected), P.Neutral{}}, F.F64{sneak_hi, sneak_lo}, L.float_bits(pitch)}}
    case _: None{}

def optional_numbers(value: Maybe<&2, List<&2, U32>>, kind: U32) -> Maybe<&2, I.Controls>:
  match value:
    case None{}: None{}
    case Some{fields}: parse_state(fields)

def optional_player(value: Maybe<&2, List<&2, U32>>) -> Maybe<&2, P.State>:
  match value:
    case None{}: None{}
    case Some{fields}: parse_player(fields)

def optional_apply(value: Maybe<&2, List<&2, U32>>) -> Maybe<&2, I.ApplyContext>:
  match value:
    case None{}: None{}
    case Some{fields}: parse_apply(fields)

def applied_show(value: I.State & P.State) -> String:
  (state, player) = value
  "applied|" ++ state_show(state) ++ "|" ++ player_show(player)

def error_show(error: I.Error) -> String:
  match error:
    case I.UnsupportedContext{mode}: "mode"
    case I.UnsupportedPose{}: "pose"
    case I.UnsupportedAbilities{}: "abilities"
    case I.InvalidState{field}: "state|" ++ U32.show(field)
    case I.InvalidAttribute{}: "attribute"
    case I.InvalidPitch{}: "pitch"
    case I.SprintContextMismatch{}: "sprint"
    case I.PlayerError{cause}: "player"


def preparation_show(value: Result<&2, &2, I.Error, I.PreTravel>) -> String:
  match value:
    case Fail{error}: "error|" ++ error_show(error)
    case Done{I.PreTravel{state, P.PreTravel{player, input, attempted, jumped}}}:
      "prepared|" ++ state_show(state) ++ "|" ++ player_show(player) ++ "|" ++ vec3_show(input) ++ "|" ++ U32.show(Bool.to_u32(attempted)) ++ "|" ++ U32.show(Bool.to_u32(jumped))

def print_preparation(id: String, result: L.Tables & Result<&2, &2, I.Error, I.PreTravel>) -> IO(L.Tables):
  (tables, value) = result
  do IO<L.Tables>:
    IO.print(id ++ "|" ++ preparation_show(value))
    return tables

def print_applied(id: String, tables: L.Tables, controls: I.Controls, player: P.State, context: I.ApplyContext) -> IO(L.Tables):
  I.Controls{local, sprinting, updates} = controls
  do IO<L.Tables>:
    IO.print(id ++ "|" ++ applied_show(I.applied_state(local, player, context)))
    return tables

def phase(id: String, op: String, tables: L.Tables, controls: I.Controls, player: P.State, context: I.ApplyContext) -> IO(L.Tables):
  match op:
    case "prepare": print_preparation(id, I.prepare_checked(tables, controls, player, context))
    case "apply": print_applied(id, tables, controls, player, context)
    case _: IO.die(L.Tables, 2, "invalid local input phase")

def phase_parsed(id: String, op: String, tables: L.Tables, controls: Maybe<&2, I.Controls>, player: Maybe<&2, P.State>, context: Maybe<&2, I.ApplyContext>) -> IO(L.Tables):
  match controls player context:
    case Some{controls} Some{player} Some{context}: phase(id, op, tables, controls, player, context)
    case _ _ _: IO.die(L.Tables, 2, "invalid local input phase fields")


def commands_word(values: List<&2, Bool>, acc: U32) -> U32:
  match values:
    case Nil{}: acc
    case value <> rest: commands_word(rest, U32.add(U32.mul(acc, 2), Bool.to_u32(value)))

def controls_show(value: Result<&2, &2, I.Error, I.Controls>) -> String:
  match value:
    case Fail{error}: "error|" ++ error_show(error)
    case Done{I.Controls{state, sprinting, +updates}}: "controls|" ++ state_show(state) ++ "|" ++ U32.show(Bool.to_u32(sprinting)) ++ "|" ++ U32.show(U32.from_nat(List.length(&2, Bool, updates))) ++ "|" ++ U32.show(commands_word(updates, 0))

def pose(word: U32) -> I.Pose:
  match word:
    case 0: I.Standing{}
    case 1: I.Crouching{}
    case _: I.OtherPose{}

def mode(word: U32) -> I.Mode:
  match word:
    case 0: I.Neutral{}
    case 1: I.NonControlledCamera{}
    case 2: I.Swimming{}
    case 3: I.FallFlying{}
    case 4: I.Passenger{}
    case 5: I.UsingItem{}
    case 6: I.Screen{}
    case 7: I.AutoJump{}
    case 8: I.NoPhysics{}
    case 9: I.Sleeping{}
    case 10: I.VisualCrawling{}
    case 11: I.Portal{}
    case 12: I.PushOutNeeded{}
    case 13: I.EdgeBackoffNeeded{}
    case 14: I.Immobile{}
    case _: I.NonNeutralEffects{}

def keyboard_show(sample: PI.Sample) -> String:
  PI.Sample{keys, move, has_forward} = sample
  "keyboard|" ++ U32.show(PI.mask(keys)) ++ "|" ++ vector_show(move) ++ "|" ++ U32.show(Bool.to_u32(has_forward))

def parse_keyboard(fields: List<&2, U32>) -> String:
  match fields:
    case mask <> Nil{}: keyboard_show(PI.sample(PI.from_mask(mask)))
    case _: "invalid"

def vector_values(+value: PI.Vector) -> String:
  "vector|" ++ vector_show(I.square_movement(value)) ++ "|" ++ U32.show(F32.bits(I.distance_to_square(value))) ++ "|" ++
    U32.show(F32.bits(I.length(value))) ++ "|" ++ U32.show(F32.bits(I.length_squared(value)))

def parse_vector(fields: List<&2, U32>) -> String:
  match fields:
    case x <> z <> Nil{}: vector_values(PI.Vector{L.float_bits(x), L.float_bits(z)})
    case _: "invalid"

def parse_modify(fields: List<&2, U32>) -> String:
  match fields:
    case x <> z <> hi <> lo <> slow <> Nil{}:
      "modify|" ++ vector_show(I.modify_input(PI.Vector{L.float_bits(x), L.float_bits(z)}, F.F64{hi, lo}, bit(slow)))
    case _: "invalid"

def parse_bob(fields: List<&2, U32>) -> String:
  match fields:
    case old <> angle <> Nil{}: "bob|" ++ U32.show(F32.bits(I.bob(L.float_bits(old), L.float_bits(angle))))
    case _: "invalid"

def predicates(current: Bool, movement: PI.Vector, food: U32, mayfly: Bool, mobility: Bool, slow: Bool) -> String:
  +allowed = I.possible(food, mayfly, mobility)
  "predicates|" ++ U32.show(Bool.to_u32(allowed)) ++ "|" ++ U32.show(Bool.to_u32(I.can_start(current, I.forward(movement), allowed, slow)))

def parse_predicates(fields: List<&2, U32>) -> String:
  match fields:
    case current <> x <> z <> food <> mayfly <> mobility <> slow <> Nil{}:
      predicates(bit(current), PI.Vector{L.float_bits(x), L.float_bits(z)}, food, bit(mayfly), bit(mobility), bit(slow))
    case _: "invalid"

def parse_controls_context(state: I.State, fields: List<&2, U32>) -> String:
  match fields:
    case current <> held <> standing <> crouching <> food <> mayfly <> flying <> mobility <> horizontal <> minor <> window <> pose_word <> mode_word <> Nil{}:
      controls_show(I.controls_checked(state, bit(current), PI.from_mask(held),
        I.Context{bit(standing), bit(crouching), food, I.Abilities{bit(mayfly), bit(flying)}, bit(mobility), bit(horizontal), bit(minor), window, pose(pose_word), mode(mode_word)}))
    case _: "invalid"

def parse_controls(fields: List<&2, U32>) -> String:
  match fields:
    case keys <> x <> z <> trigger <> crouching <> bx <> by <> ox <> oy <> rest:
      parse_controls_context(I.State{PI.from_mask(keys), PI.Vector{L.float_bits(x), L.float_bits(z)}, trigger, bit(crouching), L.float_bits(bx), L.float_bits(by), L.float_bits(ox), L.float_bits(oy)}, rest)
    case _: "invalid"

def parsed(op: String, fields: List<&2, U32>) -> String:
  match op:
    case "keyboard": parse_keyboard(fields)
    case "vector": parse_vector(fields)
    case "modify": parse_modify(fields)
    case "bob": parse_bob(fields)
    case "predicates": parse_predicates(fields)
    case "controls": parse_controls(fields)
    case _: "invalid"

def result_id(id: String, value: String) -> String:
  match value:
    case "invalid": "invalid"
    case _: id ++ "|" ++ value

def parsed_fields(id: String, op: String, fields: Maybe<&2, List<&2, U32>>) -> String:
  match fields:
    case None{}: "invalid"
    case Some{fields}: result_id(id, parsed(op, fields))

def dispatch(fields: List<&2, String>) -> String:
  match fields:
    case id <> op <> rest: parsed_fields(id, op, numbers(rest))
    case _: "invalid"

def print_result(value: String) -> IO(Unit):
  match value:
    case "invalid": IO.die(Unit, 2, "invalid local input protocol")
    case _: IO.print(value)

def phase_header(parts: List<&2, String>, local: String, player: String, context: String, tables: L.Tables) -> IO(L.Tables):
  match parts:
    case id <> op <> Nil{}:
      phase_parsed(id, op, tables, optional_numbers(numbers(String.split(local, '|')), 0), optional_player(numbers(String.split(player, '|'))), optional_apply(numbers(String.split(context, '|'))))
    case _: IO.die(L.Tables, 2, "invalid local input phase header")

def dispatch_parts(parts: List<&2, String>, tables: L.Tables) -> IO(L.Tables):
  match parts:
    case header <> Nil{}:
      do IO<L.Tables>:
        print_result(dispatch(String.split(header, '|')))
        return tables
    case header <> local <> player <> context <> Nil{}: phase_header(String.split(header, '|'), local, player, context, tables)
    case _: IO.die(L.Tables, 2, "invalid local input field groups")

def run_args(args: List<String>, tables: L.Tables) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case arg <> rest:
      do IO<Unit>:
        tables : L.Tables <- dispatch_parts(String.split(arg, ';'), tables)
        run_args(rest, tables)

def loaded(args: List<String>, result: Result<&2, &1, L.Error, L.Tables>) -> IO(Unit):
  match result:
    case Fail{error}: IO.die(Unit, 3, "invalid local input table")
    case Done{tables}: run_args(args, tables)

def table_path(args: List<String>) -> IO(Unit):
  match args:
    case path <> rest:
      do IO<Unit>:
        result : Result<&2, &1, L.Error, L.Tables> <- L.Tables.load(path)
        loaded(rest, result)
    case _: IO.die(Unit, 2, "local input table path required")

def drop_program(args: List<String>) -> IO(Unit):
  match args:
    case program <> rest: table_path(rest)
    case _: IO.die(Unit, 2, "local input arguments required")

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), drop_program)
