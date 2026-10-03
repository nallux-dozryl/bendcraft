import Base
import ../src/f64.bend as F
import ../src/geometry.bend as G
import ../src/movement.bend as M
import ../src/locomotion.bend as L
import ../src/player_input.bend as PI
import ../src/local_collision.bend as C

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

def parse_body(fields: List<&2, U32>) -> Maybe<&2, M.Body>:
  match fields:
    case xh <> xl <> yh <> yl <> zh <> zl <> ah <> al <> bh <> bl <> ch <> cl <> dh <> dl <> eh <> el <> fh <> fl <> vxh <> vxl <> vyh <> vyl <> vzh <> vzl <> width <> height <> ground <> horizontal <> vertical <> below <> Nil{}:
      Some{M.Body{M.Vec3{F.F64{xh, xl}, F.F64{yh, yl}, F.F64{zh, zl}},
        G.AABB{F.F64{ah, al}, F.F64{bh, bl}, F.F64{ch, cl}, F.F64{dh, dl}, F.F64{eh, el}, F.F64{fh, fl}},
        M.Vec3{F.F64{vxh, vxl}, F.F64{vyh, vyl}, F.F64{vzh, vzl}}, L.float_bits(width), L.float_bits(height), bit(ground), bit(horizontal), bit(vertical), bit(below)}}
    case _: None{}

def parse_vec3(fields: List<&2, U32>) -> Maybe<&2, M.Vec3>:
  match fields:
    case xh <> xl <> yh <> yl <> zh <> zl <> Nil{}:
      Some{M.Vec3{F.F64{xh, xl}, F.F64{yh, yl}, F.F64{zh, zl}}}
    case _: None{}

def mode(word: U32) -> C.Mode:
  match word:
    case 0: C.NeutralDry{}
    case 1: C.Flight{}
    case 2: C.Swimming{}
    case 3: C.Passenger{}
    case 4: C.NoPhysics{}
    case 5: C.NonNeutralEffects{}
    case _: C.UnsupportedWorld{}

def mover(word: U32) -> C.Mover:
  match word:
    case 0: C.Self{}
    case 1: C.Player{}
    case _: C.OtherMover{}

type MinorContext is Data:
  MinorContext{input: C.MinorInput, mode: C.Mode}

type BackoffContext is Data:
  BackoffContext{context: C.EdgeContext, fuel: Nat}

def parse_minor(fields: List<&2, U32>) -> Maybe<&2, MinorContext>:
  match fields:
    case yaw <> x <> z <> admit <> Nil{}:
      Some{MinorContext{C.MinorInput{L.float_bits(yaw), L.float_bits(x), L.float_bits(z)}, mode(admit)}}
    case _: None{}

def parse_context(fields: List<&2, U32>) -> Maybe<&2, BackoffContext>:
  match fields:
    case maximum <> fh <> fl <> flying <> keys <> moving <> admit <> fuel <> Nil{}:
      Some{BackoffContext{C.EdgeContext{L.float_bits(maximum), F.F64{fh, fl}, bit(flying), PI.from_mask(keys), mover(moving), mode(admit)}, U32.to_nat(fuel)}}
    case _: None{}

def parse_answer(kind: U32, clear: U32) -> Result<&2, &2, C.Error, Bool>:
  match kind:
    case 0: Done{bit(clear)}
    case _: Fail{C.QueryDenied{"fixture-denied"}}

def parse_observation(fields: List<&2, U32>) -> Maybe<&2, C.QueryObservation>:
  match fields:
    case ah <> al <> bh <> bl <> ch <> cl <> dh <> dl <> eh <> el <> fh <> fl <> kind <> clear <> Nil{}:
      Some{C.QueryObservation{G.AABB{F.F64{ah, al}, F.F64{bh, bl}, F.F64{ch, cl}, F.F64{dh, dl}, F.F64{eh, el}, F.F64{fh, fl}}, parse_answer(kind, clear)}}
    case _: None{}

def observation_words(words: Maybe<&2, List<&2, U32>>) -> Maybe<&2, C.QueryObservation>:
  match words:
    case None{}: None{}
    case Some{fields}: parse_observation(fields)

def observations_pair(first: Maybe<&2, C.QueryObservation>, rest: Maybe<&2, List<&2, C.QueryObservation>>) -> Maybe<&2, List<&2, C.QueryObservation>>:
  match first rest:
    case Some{head} Some{tail}: Some{head <> tail}
    case _ _: None{}

def observations(parts: List<&2, String>) -> Maybe<&2, List<&2, C.QueryObservation>>:
  match parts:
    case Nil{}: Some{Nil{}}
    case head <> rest: observations_pair(observation_words(numbers(String.split(head, '|'))), observations(rest))

def observations_text(text: String) -> Maybe<&2, List<&2, C.QueryObservation>>:
  match text:
    case "": Some{Nil{}}
    case _: observations(String.split(text, '/'))

def optional_body(value: Maybe<&2, List<&2, U32>>) -> Maybe<&2, M.Body>:
  match value:
    case None{}: None{}
    case Some{fields}: parse_body(fields)

def optional_vector(value: Maybe<&2, List<&2, U32>>) -> Maybe<&2, M.Vec3>:
  match value:
    case None{}: None{}
    case Some{fields}: parse_vec3(fields)

def optional_minor(value: Maybe<&2, List<&2, U32>>) -> Maybe<&2, MinorContext>:
  match value:
    case None{}: None{}
    case Some{fields}: parse_minor(fields)

def optional_context(value: Maybe<&2, List<&2, U32>>) -> Maybe<&2, BackoffContext>:
  match value:
    case None{}: None{}
    case Some{fields}: parse_context(fields)

def error_show(error: C.Error) -> String:
  match error:
    case C.UnsupportedContext{mode}: "mode"
    case C.UnsupportedMover{}: "mover"
    case C.FlyingAbility{}: "flying"
    case C.InvalidInput{field}: "input|" ++ U32.show(field)
    case C.InvalidBody{cause}: "body"
    case C.InvalidStep{}: "step"
    case C.InvalidFallDistance{}: "fall"
    case C.InvalidQuery{field}: "query|" ++ U32.show(field)
    case C.QueryDenied{reason}: "denied"
    case C.QueryBudget{}: "budget"
    case C.UnexpectedAnswer{}: "unexpected"
    case C.MissingObservation{}: "missing"
    case C.MismatchedQuery{}: "mismatch"
    case C.ExtraObservations{}: "extra"

def angle_show(angle: Maybe<&2, C.AngleDetails>) -> String:
  match angle:
    case None{}: "0"
    case Some{C.AngleDetails{dot, ratio, value}}:
      "1|" ++ f64_show(dot) ++ "|" ++ f64_show(ratio) ++ "|" ++ f64_show(value)

def minor_show(result: Result<&2, &2, C.Error, C.MinorObservation>) -> String:
  match result:
    case Fail{error}: "error|" ++ error_show(error)
    case Done{C.MinorObservation{minor, x, z, input, movement, angle}}:
      "minor|" ++ U32.show(Bool.to_u32(minor)) ++ "|" ++ f64_show(x) ++ "|" ++ f64_show(z) ++ "|" ++
        f64_show(input) ++ "|" ++ f64_show(movement) ++ "|" ++ angle_show(angle)

def backoff_show(result: Result<&2, &2, C.Error, C.BackoffObservation>) -> String:
  match result:
    case Fail{error}: "error|" ++ error_show(error)
    case Done{C.BackoffObservation{movement, queries}}: "backoff|" ++ vec3_show(movement) ++ "|" ++ Nat.show(queries)

def print_minor(id: String, read: L.Tables & Result<&2, &2, C.Error, C.MinorObservation>) -> IO(L.Tables):
  (tables, result) = read
  do IO<L.Tables>:
    IO.print(id ++ "|" ++ minor_show(result))
    return tables

def print_backoff(id: String, read: L.Tables & Result<&2, &2, C.Error, C.BackoffObservation>) -> IO(L.Tables):
  (tables, result) = read
  do IO<L.Tables>:
    IO.print(id ++ "|" ++ backoff_show(result))
    return tables

def minor_parsed(id: String, tables: L.Tables, body: Maybe<&2, M.Body>, context: Maybe<&2, MinorContext>, movement: Maybe<&2, M.Vec3>) -> IO(L.Tables):
  match body context movement:
    case Some{body} Some{MinorContext{input, mode}} Some{movement}:
      print_minor(id, C.minor_checked(tables, body, input, movement, mode))
    case _ _ _: IO.die(L.Tables, 2, "invalid local collision minor fields")

def backoff_parsed(id: String, tables: L.Tables, body: Maybe<&2, M.Body>, context: Maybe<&2, BackoffContext>, movement: Maybe<&2, M.Vec3>, observations: Maybe<&2, List<&2, C.QueryObservation>>) -> IO(L.Tables):
  match body context movement observations:
    case Some{body} Some{BackoffContext{context, fuel}} Some{movement} Some{observations}:
      print_backoff(id, C.backoff_checked(L.Tables, tables, fuel, observations, body, movement, context))
    case _ _ _ _: IO.die(L.Tables, 2, "invalid local collision backoff fields")

def phase_header(fields: List<&2, String>, body: String, context: String, movement: String, observations: String, tables: L.Tables) -> IO(L.Tables):
  match fields:
    case id <> "minor" <> Nil{}:
      minor_parsed(id, tables, optional_body(numbers(String.split(body, '|'))), optional_minor(numbers(String.split(context, '|'))), optional_vector(numbers(String.split(movement, '|'))))
    case id <> "backoff" <> Nil{}:
      backoff_parsed(id, tables, optional_body(numbers(String.split(body, '|'))), optional_context(numbers(String.split(context, '|'))), optional_vector(numbers(String.split(movement, '|'))), observations_text(observations))
    case _: IO.die(L.Tables, 2, "invalid local collision header")

def scalar_words(id: String, tables: L.Tables, values: Maybe<&2, List<&2, U32>>) -> IO(L.Tables):
  match values:
    case Some{hi <> lo <> Nil{}}:
      do IO<L.Tables>:
        IO.print(id ++ "|acos|" ++ f64_show(C.acos(F.F64{hi, lo})))
        return tables
    case _: IO.die(L.Tables, 2, "invalid local collision acos fields")

def scalar_header(fields: List<&2, String>, tables: L.Tables) -> IO(L.Tables):
  match fields:
    case id <> "acos" <> rest: scalar_words(id, tables, numbers(rest))
    case _: IO.die(L.Tables, 2, "invalid local collision scalar header")

def dispatch_parts(parts: List<&2, String>, tables: L.Tables) -> IO(L.Tables):
  match parts:
    case header <> Nil{}: scalar_header(String.split(header, '|'), tables)
    case header <> body <> context <> movement <> observations <> Nil{}:
      phase_header(String.split(header, '|'), body, context, movement, observations, tables)
    case _: IO.die(L.Tables, 2, "invalid local collision protocol")

def run_args(args: List<String>, tables: L.Tables) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case arg <> rest:
      do IO<Unit>:
        tables : L.Tables <- dispatch_parts(String.split(arg, ';'), tables)
        run_args(rest, tables)

def loaded(args: List<String>, result: Result<&2, &1, L.Error, L.Tables>) -> IO(Unit):
  match result:
    case Fail{error}: IO.die(Unit, 3, "invalid local collision table")
    case Done{tables}: run_args(args, tables)

def table_path(args: List<String>) -> IO(Unit):
  match args:
    case path <> rest:
      do IO<Unit>:
        result : Result<&2, &1, L.Error, L.Tables> <- L.Tables.load(path)
        loaded(rest, result)
    case _: IO.die(Unit, 2, "local collision table path required")

def drop_program(args: List<String>) -> IO(Unit):
  match args:
    case program <> rest: table_path(rest)
    case _: IO.die(Unit, 2, "local collision arguments required")

def main() -> IO(Unit):
  IO.bind(List<String>, Unit, IO.args(), drop_program)
