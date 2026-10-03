import Base
import ../src/f64.bend as F
import ../src/geometry.bend as G
import ../src/movement.bend as M
import ../src/locomotion.bend as L
import ../src/travel.bend as T
import ../src/support.bend as S

def f64_show(value: F.F64) -> String:
  match value:
    case F.F64{hi, lo}: U32.show(hi) ++ "|" ++ U32.show(lo)

def box_show(value: G.AABB) -> String:
  match value:
    case G.AABB{a, b, c, d, e, f}:
      f64_show(a) ++ "|" ++ f64_show(b) ++ "|" ++ f64_show(c) ++ "|" ++ f64_show(d) ++ "|" ++ f64_show(e) ++ "|" ++ f64_show(f)

def number_gate(value: Maybe<&2, U32>, rest: Maybe<&2, List<&2, U32>>) -> Maybe<&2, List<&2, U32>>:
  match value rest:
    case Some{value} Some{rest}: Some{value <> rest}
    case _ _: None{}

def numbers(fields: List<&2, String>) -> Maybe<&2, List<&2, U32>>:
  match fields:
    case Nil{}: Some{Nil{}}
    case field <> rest: number_gate(U32.read(field), numbers(rest))

def block_show(block: T.BlockPos) -> String:
  match block:
    case T.BlockPos{x, y, z}: U32.show(x) ++ "|" ++ U32.show(y) ++ "|" ++ U32.show(z)

def optional_show(value: Maybe<&2, T.BlockPos>) -> String:
  match value:
    case None{}: "0|0|0|0"
    case Some{block}: "1|" ++ block_show(block)

def state_show(value: S.State) -> String:
  match value:
    case S.State{main, flag}: optional_show(main) ++ "|" ++ U32.show(Bool.to_u32(flag))

def error_show(error: S.Error) -> String:
  match error:
    case S.InvalidPosition{field}: "position|" ++ U32.show(field)
    case S.InvalidBox{field}: "box|" ++ U32.show(field)
    case S.ReversedBox{axis}: "order|" ++ U32.show(axis)
    case S.InvalidMovement{field}: "movement|" ++ U32.show(field)
    case S.InvalidOffset{}: "offset"

def optional_block_gate(present: Bool, x: U32, y: U32, z: U32) -> Maybe<&2, T.BlockPos>:
  match present:
    case False{}: None{}
    case True{}: Some{T.BlockPos{x, y, z}}

def optional_block(present: U32, x: U32, y: U32, z: U32) -> Maybe<&2, T.BlockPos>:
  optional_block_gate(U32.is_ne(present, 0), x, y, z)

def optional_movement_gate(present: Bool, xh: U32, xl: U32, yh: U32, yl: U32, zh: U32, zl: U32) -> Maybe<&2, M.Vec3>:
  match present:
    case False{}: None{}
    case True{}: Some{M.Vec3{F.F64{xh, xl}, F.F64{yh, yl}, F.F64{zh, zl}}}

def optional_movement(present: U32, xh: U32, xl: U32, yh: U32, yl: U32, zh: U32, zl: U32) -> Maybe<&2, M.Vec3>:
  optional_movement_gate(U32.is_ne(present, 0), xh, xl, yh, yl, zh, zl)

def candidates_add(x: U32, y: U32, z: U32, rest: Maybe<&2, List<&2, S.Candidate>>) -> Maybe<&2, List<&2, S.Candidate>>:
  match rest:
    case None{}: None{}
    case Some{rest}: Some{S.FullCube{T.BlockPos{x, y, z}} <> rest}

def candidates(fields: List<&2, U32>) -> Maybe<&2, List<&2, S.Candidate>>:
  match fields:
    case Nil{}: Some{Nil{}}
    case x <> y <> z <> rest: candidates_add(x, y, z, candidates(rest))
    case _: None{}

def candidate_numbers(fields: Maybe<&2, List<&2, U32>>) -> Maybe<&2, List<&2, S.Candidate>>:
  match fields:
    case None{}: None{}
    case Some{fields}: candidates(fields)

def candidate_fields(field: String) -> Maybe<&2, List<&2, S.Candidate>>:
  match field:
    case "": Some{Nil{}}
    case _: candidate_numbers(numbers(String.split(field, '|')))

def block_result(id: String, prior: Maybe<&2, S.State>, read: Result<&2, &2, S.Error, T.BlockPos>) -> IO(Maybe<&2, S.State>):
  match read:
    case Fail{error}:
      do IO<Maybe<&2, S.State>>:
        IO.print(id ++ "|error|" ++ error_show(error))
        return prior
    case Done{block}:
      do IO<Maybe<&2, S.State>>:
        IO.print(id ++ "|block|" ++ block_show(block))
        return prior

def selection_result(id: String, prior: Maybe<&2, S.State>, read: Result<&2, &2, S.Error, Maybe<&2, T.BlockPos>>) -> IO(Maybe<&2, S.State>):
  match read:
    case Fail{error}:
      do IO<Maybe<&2, S.State>>:
        IO.print(id ++ "|error|" ++ error_show(error))
        return prior
    case Done{selection}:
      do IO<Maybe<&2, S.State>>:
        IO.print(id ++ "|selection|" ++ optional_show(selection))
        return prior

def query_fallback_show(value: Maybe<&2, G.AABB>) -> String:
  match value:
    case None{}: "0"
    case Some{box}: "1|" ++ box_show(box)

def query_result(id: String, prior: Maybe<&2, S.State>, read: Result<&2, &2, S.Error, S.Queries>) -> IO(Maybe<&2, S.State>):
  match read:
    case Fail{error}:
      do IO<Maybe<&2, S.State>>:
        IO.print(id ++ "|error|" ++ error_show(error))
        return prior
    case Done{S.Queries{primary, fallback}}:
      do IO<Maybe<&2, S.State>>:
        IO.print(id ++ "|queries|" ++ box_show(primary) ++ "|" ++ query_fallback_show(fallback))
        return prior

def update_result(id: String, prior: Maybe<&2, S.State>, read: Result<&2, &2, S.Error, S.State>) -> IO(Maybe<&2, S.State>):
  match read:
    case Fail{error}:
      do IO<Maybe<&2, S.State>>:
        IO.print(id ++ "|error|" ++ error_show(error))
        return prior
    case Done{+state}:
      do IO<Maybe<&2, S.State>>:
        IO.print(id ++ "|state|" ++ state_show(state))
        return Some{state}

def update_chain(id: String, prior: Maybe<&2, S.State>, state: S.State, position: M.Vec3, box: G.AABB, grounded: Bool, movement: Maybe<&2, M.Vec3>, primary: List<&2, S.Candidate>, fallback: List<&2, S.Candidate>, chained: Bool) -> IO(Maybe<&2, S.State>):
  match prior chained:
    case None{} True{}: IO.die(Maybe<&2, S.State>, 2, "invalid support chain")
    case Some{+prior} True{}: update_result(id, Some{prior}, S.update_checked(prior, position, box, grounded, movement, primary, fallback))
    case prior False{}: update_result(id, prior, S.update_checked(state, position, box, grounded, movement, primary, fallback))

def update_operation(id: String, op: String, prior: Maybe<&2, S.State>, state: S.State, position: M.Vec3, box: G.AABB, grounded: Bool, movement: Maybe<&2, M.Vec3>, primary: List<&2, S.Candidate>, fallback: List<&2, S.Candidate>) -> IO(Maybe<&2, S.State>):
  match op:
    case "update": update_chain(id, prior, state, position, box, grounded, movement, primary, fallback, False{})
    case "chain": update_chain(id, prior, state, position, box, grounded, movement, primary, fallback, True{})
    case _: IO.die(Maybe<&2, S.State>, 2, "invalid support operation")

def parse_compare(id: String, fields: List<&2, U32>, primary: List<&2, S.Candidate>, fallback: List<&2, S.Candidate>, prior: Maybe<&2, S.State>) -> IO(Maybe<&2, S.State>):
  match fields:
    case ax <> ay <> az <> bx <> by <> bz <> Nil{}:
      do IO<Maybe<&2, S.State>>:
        IO.print(id ++ "|word|" ++ U32.show(S.compare_position(T.BlockPos{ax, ay, az}, T.BlockPos{bx, by, bz})))
        return prior
    case _: IO.die(Maybe<&2, S.State>, 2, "invalid support compare fields")

def parse_distance(id: String, fields: List<&2, U32>, primary: List<&2, S.Candidate>, fallback: List<&2, S.Candidate>, prior: Maybe<&2, S.State>) -> IO(Maybe<&2, S.State>):
  match fields:
    case bx <> by <> bz <> xh <> xl <> yh <> yl <> zh <> zl <> Nil{}:
      do IO<Maybe<&2, S.State>>:
        IO.print(id ++ "|f64|" ++ f64_show(S.center_distance(M.Vec3{F.F64{xh, xl}, F.F64{yh, yl}, F.F64{zh, zl}}, T.BlockPos{bx, by, bz})))
        return prior
    case _: IO.die(Maybe<&2, S.State>, 2, "invalid support distance fields")

def parse_jump(id: String, fields: List<&2, U32>, primary: List<&2, S.Candidate>, fallback: List<&2, S.Candidate>, prior: Maybe<&2, S.State>) -> IO(Maybe<&2, S.State>):
  match fields:
    case current <> below <> Nil{}:
      do IO<Maybe<&2, S.State>>:
        IO.print(id ++ "|word|" ++ U32.show(F32.bits(S.jump_factor(L.float_bits(current), L.float_bits(below)))))
        return prior
    case _: IO.die(Maybe<&2, S.State>, 2, "invalid support jump fields")

def parse_on_pos(id: String, fields: List<&2, U32>, primary: List<&2, S.Candidate>, fallback: List<&2, S.Candidate>, prior: Maybe<&2, S.State>) -> IO(Maybe<&2, S.State>):
  match fields:
    case xh <> xl <> yh <> yl <> zh <> zl <> main <> bx <> by <> bz <> flag <> offset <> Nil{}:
      block_result(id, prior, S.get_on_pos_checked(M.Vec3{F.F64{xh, xl}, F.F64{yh, yl}, F.F64{zh, zl}}, S.State{optional_block(main, bx, by, bz), U32.is_ne(flag, 0)}, L.float_bits(offset)))
    case _: IO.die(Maybe<&2, S.State>, 2, "invalid support on_pos fields")

def parse_on_pos_raw(id: String, fields: List<&2, U32>, primary: List<&2, S.Candidate>, fallback: List<&2, S.Candidate>, prior: Maybe<&2, S.State>) -> IO(Maybe<&2, S.State>):
  match fields:
    case xh <> xl <> yh <> yl <> zh <> zl <> main <> bx <> by <> bz <> flag <> offset <> Nil{}:
      block_result(id, prior, Done{S.get_on_pos(M.Vec3{F.F64{xh, xl}, F.F64{yh, yl}, F.F64{zh, zl}}, S.State{optional_block(main, bx, by, bz), U32.is_ne(flag, 0)}, L.float_bits(offset))})
    case _: IO.die(Maybe<&2, S.State>, 2, "invalid support on_pos_raw fields")

def parse_queries(id: String, fields: List<&2, U32>, primary: List<&2, S.Candidate>, fallback: List<&2, S.Candidate>, prior: Maybe<&2, S.State>) -> IO(Maybe<&2, S.State>):
  match fields:
    case ah <> al <> bh <> bl <> ch <> cl <> dh <> dl <> eh <> el <> fh <> fl <> present <> xh <> xl <> yh <> yl <> zh <> zl <> Nil{}:
      query_result(id, prior, S.queries_checked(G.AABB{F.F64{ah, al}, F.F64{bh, bl}, F.F64{ch, cl}, F.F64{dh, dl}, F.F64{eh, el}, F.F64{fh, fl}}, optional_movement(present, xh, xl, yh, yl, zh, zl)))
    case _: IO.die(Maybe<&2, S.State>, 2, "invalid support queries fields")

def parse_select(id: String, fields: List<&2, U32>, primary: List<&2, S.Candidate>, fallback: List<&2, S.Candidate>, prior: Maybe<&2, S.State>) -> IO(Maybe<&2, S.State>):
  match fields:
    case xh <> xl <> yh <> yl <> zh <> zl <> ah <> al <> bh <> bl <> ch <> cl <> dh <> dl <> eh <> el <> fh <> fl <> Nil{}:
      selection_result(id, prior, S.select_checked(M.Vec3{F.F64{xh, xl}, F.F64{yh, yl}, F.F64{zh, zl}}, G.AABB{F.F64{ah, al}, F.F64{bh, bl}, F.F64{ch, cl}, F.F64{dh, dl}, F.F64{eh, el}, F.F64{fh, fl}}, primary))
    case _: IO.die(Maybe<&2, S.State>, 2, "invalid support select fields")

def parse_update(id: String, op: String, fields: List<&2, U32>, primary: List<&2, S.Candidate>, fallback: List<&2, S.Candidate>, prior: Maybe<&2, S.State>) -> IO(Maybe<&2, S.State>):
  match fields:
    case xh <> xl <> yh <> yl <> zh <> zl <> ah <> al <> bh <> bl <> ch <> cl <> dh <> dl <> eh <> el <> fh <> fl <> main <> bx <> by <> bz <> flag <> ground <> present <> mxh <> mxl <> myh <> myl <> mzh <> mzl <> Nil{}:
      update_operation(id, op, prior, S.State{optional_block(main, bx, by, bz), U32.is_ne(flag, 0)}, M.Vec3{F.F64{xh, xl}, F.F64{yh, yl}, F.F64{zh, zl}}, G.AABB{F.F64{ah, al}, F.F64{bh, bl}, F.F64{ch, cl}, F.F64{dh, dl}, F.F64{eh, el}, F.F64{fh, fl}}, U32.is_ne(ground, 0), optional_movement(present, mxh, mxl, myh, myl, mzh, mzl), primary, fallback)
    case _: IO.die(Maybe<&2, S.State>, 2, "invalid support update fields")

def parsed(id: String, op: String, fields: List<&2, U32>, primary: List<&2, S.Candidate>, fallback: List<&2, S.Candidate>, prior: Maybe<&2, S.State>) -> IO(Maybe<&2, S.State>):
  match op:
    case "compare": parse_compare(id, fields, primary, fallback, prior)
    case "distance": parse_distance(id, fields, primary, fallback, prior)
    case "jump": parse_jump(id, fields, primary, fallback, prior)
    case "on_pos": parse_on_pos(id, fields, primary, fallback, prior)
    case "on_pos_raw": parse_on_pos_raw(id, fields, primary, fallback, prior)
    case "queries": parse_queries(id, fields, primary, fallback, prior)
    case "select": parse_select(id, fields, primary, fallback, prior)
    case "update": parse_update(id, "update", fields, primary, fallback, prior)
    case "chain": parse_update(id, "chain", fields, primary, fallback, prior)
    case _: IO.die(Maybe<&2, S.State>, 2, "invalid support operation")

def parsed_numbers(id: String, op: String, fields: Maybe<&2, List<&2, U32>>, primary: Maybe<&2, List<&2, S.Candidate>>, fallback: Maybe<&2, List<&2, S.Candidate>>, prior: Maybe<&2, S.State>) -> IO(Maybe<&2, S.State>):
  match fields primary fallback:
    case Some{fields} Some{primary} Some{fallback}: parsed(id, op, fields, primary, fallback, prior)
    case _ _ _: IO.die(Maybe<&2, S.State>, 2, "invalid support numbers")

def header(parts: List<&2, String>, primary: String, fallback: String, prior: Maybe<&2, S.State>) -> IO(Maybe<&2, S.State>):
  match parts:
    case id <> op <> rest: parsed_numbers(id, op, numbers(rest), candidate_fields(primary), candidate_fields(fallback), prior)
    case _: IO.die(Maybe<&2, S.State>, 2, "invalid support header")

def dispatch(parts: List<&2, String>, prior: Maybe<&2, S.State>) -> IO(Maybe<&2, S.State>):
  match parts:
    case first <> primary <> fallback <> Nil{}: header(String.split(first, '|'), primary, fallback, prior)
    case _: IO.die(Maybe<&2, S.State>, 2, "invalid support protocol")

def run_args(args: List<String>, prior: Maybe<&2, S.State>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case arg <> rest:
      do IO<Unit>:
        prior : Maybe<&2, S.State> <- dispatch(String.split(arg, ';'), prior)
        run_args(rest, prior)

def drop_program(args: List<String>) -> IO(Unit):
  match args:
    case program <> rest: run_args(rest, None{})
    case _: IO.die(Unit, 2, "support arguments required")

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), drop_program)
