import Base
import ../src/f64.bend as F
import ../src/geometry.bend as G
import ../src/movement.bend as M
import ../src/locomotion.bend as L
import ../src/travel.bend as V
import ./geometry.bend as T
import ./movement.bend as MT
import ./locomotion.bend as LT

def mode(index: U32) -> V.Mode:
  match index:
    case 0: V.NeutralDryAir{}
    case 1: V.Liquid{}
    case 2: V.Swimming{}
    case 3: V.AbilityFlight{}
    case 4: V.Gliding{}
    case 5: V.Climbing{}
    case 6: V.PowderSnow{}
    case 7: V.MobEffects{}
    case 8: V.Passenger{}
    case 9: V.UnloadedClient{}
    case 10: V.NonNeutralBlock{}
    case 11: V.NonAuthoritative{}
    case _: V.EdgeBackoff{}

def mode_show(mode: V.Mode) -> String:
  match mode:
    case V.NeutralDryAir{}: "0"
    case V.Liquid{}: "1"
    case V.Swimming{}: "2"
    case V.AbilityFlight{}: "3"
    case V.Gliding{}: "4"
    case V.Climbing{}: "5"
    case V.PowderSnow{}: "6"
    case V.MobEffects{}: "7"
    case V.Passenger{}: "8"
    case V.UnloadedClient{}: "9"
    case V.NonNeutralBlock{}: "10"
    case V.NonAuthoritative{}: "11"
    case V.EdgeBackoff{}: "12"

def error_show(error: V.Error) -> String:
  match error:
    case V.UnsupportedContext{mode}: "mode|" ++ mode_show(mode)
    case V.InvalidContext{field}: "context|" ++ U32.show(field)
    case V.InvalidAttribute{field}: "attribute|" ++ U32.show(field)
    case V.InvalidInput{field}: "input|" ++ U32.show(field)
    case V.MovementError{cause}: "movement|" ++ MT.error_show(cause)

def body_show(body: M.Body) -> String:
  match body:
    case M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below}:
      LT.vector_show(position) ++ "|" ++ T.box_show(box) ++ "|" ++ LT.vector_show(velocity) ++ "|" ++ U32.show(F32.bits(width)) ++ "|" ++ U32.show(F32.bits(height)) ++ "|" ++ U32.show(Bool.to_u32(ground)) ++ "|" ++ U32.show(Bool.to_u32(horizontal)) ++ "|" ++ U32.show(Bool.to_u32(vertical)) ++ "|" ++ U32.show(Bool.to_u32(below))

def moved_show(id: String, read: L.Tables & Result<&2, &2, V.Error, M.Transition>) -> IO(L.Tables):
  (tables, result) = read
  match result:
    case Fail{error}:
      do IO<L.Tables>:
        IO.print(id ++ "|error|" ++ error_show(error))
        return tables
    case Done{M.Transition{body, displacement, stepped, changed}}:
      do IO<L.Tables>:
        IO.print(id ++ "|body|" ++ body_show(body))
        return tables

def prepared_show(id: String, read: L.Tables & Result<&2, &2, V.Error, V.Prepared>) -> IO(L.Tables):
  (tables, result) = read
  match result:
    case Fail{error}:
      do IO<L.Tables>:
        IO.print(id ++ "|error|" ++ error_show(error))
        return tables
    case Done{V.Prepared{body, requested, friction, acceleration, maximum, gravity, drag, discard}}:
      do IO<L.Tables>:
        IO.print(id ++ "|prepared|" ++ LT.vector_show(requested) ++ "|" ++ U32.show(F32.bits(friction)) ++ "|" ++ U32.show(F32.bits(acceleration)))
        return tables

def movement_result(moved: Result<&2, &2, M.Error, M.Transition>) -> Result<&2, &2, V.Error, M.Transition>:
  match moved:
    case Fail{error}: Fail{V.MovementError{error}}
    case Done{value}: Done{value}

def movement_show(id: String, initial: List<&2, G.Collider>, step: List<&2, G.Collider>, read: L.Tables & Result<&2, &2, V.Error, V.Prepared>) -> IO(L.Tables):
  (tables, result) = read
  match result:
    case Fail{error}: moved_show(id, (tables, Fail{error}))
    case Done{V.Prepared{body, requested, friction, acceleration, maximum, gravity, drag, discard}}:
      moved_show(id, (tables, movement_result(M.move_checked(body, requested, maximum, initial, step))))

def execute(id: String, op: String, tables: L.Tables, body: M.Body, input: M.Vec3, context: V.Context, initial: List<&2, G.Collider>, step: List<&2, G.Collider>) -> IO(L.Tables):
  match op:
    case "prepare": prepared_show(id, V.prepare_checked(tables, body, input, context))
    case "movement": movement_show(id, initial, step, V.prepare_checked(tables, body, input, context))
    case "travel": moved_show(id, V.travel_checked(tables, body, input, context, initial, step))
    case _: IO.die(L.Tables, 2, "invalid travel operation")

def parsed(id: String, op: String, tables: L.Tables, fields: Maybe<&2, List<&2, U32>>, initial: Maybe<&2, List<&2, G.Collider>>, step: Maybe<&2, List<&2, G.Collider>>) -> IO(L.Tables):
  match fields initial step:
    case Some{pxh <> pxl <> pyh <> pyl <> pzh <> pzl <> axh <> axl <> ayh <> ayl <> azh <> azl <> bxh <> bxl <> byh <> byl <> bzh <> bzl <> vxh <> vxl <> vyh <> vyl <> vzh <> vzl <> width <> height <> ground <> horizontal <> vertical <> below <> ixh <> ixl <> iyh <> iyl <> izh <> izl <> gx <> gy <> gz <> friction <> sh <> sl <> gh <> gl <> fh <> fl <> dh <> dl <> yaw <> maximum <> sprint <> no_gravity <> discard <> mode_index <> Nil{}} Some{initial} Some{step}:
      body = {M.Body{M.Vec3{F.F64{pxh, pxl}, F.F64{pyh, pyl}, F.F64{pzh, pzl}}, G.AABB{F.F64{axh, axl}, F.F64{ayh, ayl}, F.F64{azh, azl}, F.F64{bxh, bxl}, F.F64{byh, byl}, F.F64{bzh, bzl}}, M.Vec3{F.F64{vxh, vxl}, F.F64{vyh, vyl}, F.F64{vzh, vzl}}, L.float_bits(width), L.float_bits(height), U32.is_ne(ground, 0), U32.is_ne(horizontal, 0), U32.is_ne(vertical, 0), U32.is_ne(below, 0)} : M.Body}
      input = {M.Vec3{F.F64{ixh, ixl}, F.F64{iyh, iyl}, F.F64{izh, izl}} : M.Vec3}
      context = {V.Context{V.GroundSample{V.BlockPos{gx, gy, gz}, L.float_bits(friction)}, V.Attributes{F.F64{sh, sl}, F.F64{gh, gl}, F.F64{fh, fl}, F.F64{dh, dl}}, L.float_bits(yaw), L.float_bits(maximum), U32.is_ne(sprint, 0), U32.is_ne(no_gravity, 0), U32.is_ne(discard, 0), mode(mode_index)} : V.Context}
      execute(id, op, tables, body, input, context, initial, step)
    case _ _ _: IO.die(L.Tables, 2, "invalid travel fields")

def header(parts: List<&2, String>, tables: L.Tables, initial: List<&2, String>, step: List<&2, String>) -> IO(L.Tables):
  match parts:
    case id <> op <> rest: parsed(id, op, tables, LT.numbers(rest), T.read_colliders(initial), T.read_colliders(step))
    case _: IO.die(L.Tables, 2, "invalid travel header")

def dispatch(parts: List<&2, String>, tables: L.Tables) -> IO(L.Tables):
  match parts:
    case first <> initial <> step <> Nil{}: header(String.split(first, '|'), tables, MT.shape_fields(initial), MT.shape_fields(step))
    case _: IO.die(L.Tables, 2, "invalid travel protocol")

def run_args(args: List<String>, tables: L.Tables) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case arg <> rest:
      do IO<Unit>:
        tables : L.Tables <- dispatch(String.split(arg, ';'), tables)
        run_args(rest, tables)

def loaded(args: List<String>, result: Result<&2, &1, L.Error, L.Tables>) -> IO(Unit):
  match result:
    case Fail{error}: IO.die(Unit, 3, "invalid travel table|" ++ LT.error_text(error))
    case Done{tables}: run_args(args, tables)

def table_path(args: List<String>) -> IO(Unit):
  match args:
    case path <> rest:
      do IO<Unit>:
        result : Result<&2, &1, L.Error, L.Tables> <- L.Tables.load(path)
        loaded(rest, result)
    case _: IO.die(Unit, 2, "travel table path required")

def drop_program(args: List<String>) -> IO(Unit):
  match args:
    case program <> rest: table_path(rest)
    case _: IO.die(Unit, 2, "travel arguments required")

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), drop_program)
