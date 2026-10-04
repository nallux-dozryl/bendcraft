import Base
import ../src/player_block_inside_sweep.bend as S
import ../src/player_block_inside_sweep_clip.bend as K
import ../src/player_block_inside_sweep_world.bend as W
import ../src/player_block_inside_stuck.bend as P
import ../src/player_fall_history.bend as H
import ../src/core.bend as C
import ../src/registry.bend as B
import ../src/world_codec.bend as WC
import ../src/movement.bend as M
import ../src/geometry.bend as A
import ../src/f64.bend as F
import ./player_block_inside_stuck.bend as O

# Reuse the committed complete affine-owner observer without changing it.
# Pure helper observations never reconstruct traversal or expected callbacks.
def float_word(value: U32) -> F32:
  match value:
    case U32{word}: F32{word}

def traversal_error(error: S.Error) -> String:
  S.error_text(error)

def world_error(error: W.Error) -> String:
  W.error_text(error)

def point_text(point: S.Point) -> String:
  S.Point{x, y, z} = point
  U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z)

def resolved_text(identity: B.Resolved) -> String:
  B.Resolved{protocol, name, state, assignments} = identity
  U32.show(state)

def reads_text(reads: List<&2, W.Read>) -> String:
  match reads:
    case Nil{}: ""
    case W.Read{S.Visit{point, step, segment}, identity, collector, seen} <> rest:
      point_text(point) ++ "," ++ resolved_text(identity) ++ "," ++ U32.show(collector) ++ "," ++ O.flag(seen) ++ ";" ++ reads_text(rest)

def callbacks_text(callbacks: List<&2, W.Callback>) -> String:
  match callbacks:
    case Nil{}: ""
    case W.Callback{S.Visit{point, step, segment}, identity, inside} <> rest:
      point_text(point) ++ "," ++ resolved_text(identity) ++ "," ++ U32.show(step) ++ ";" ++ callbacks_text(rest)

def failed_sweep(+id: String, context: O.Context, checkpoint: Maybe<&2, O.Owner>, retained: Bool, active: P.State, cause: W.Error) -> IO(O.State):
  P.State{world, registry, +receiver, H.State{+history}, tail} = active
  do IO<O.State>:
    IO.print(id ++ "\terror\t" ++ world_error(cause) ++ "\t" ++ O.receiver_text(receiver, history))
    O.checked(id, P.State{world, registry, receiver, H.State{history}, tail}, context, checkpoint, retained, True{})

def done_sweep(+id: String, context: O.Context, checkpoint: Maybe<&2, O.Owner>, retained: Bool, active: P.State, observation: W.Observation) -> IO(O.State):
  W.Observation{effects, reads, callbacks} = observation
  do IO<O.State>:
    IO.print(id ++ "\ttraces\t" ++ reads_text(reads) ++ "\t" ++ callbacks_text(callbacks))
    O.done_answer(id, context, checkpoint, retained, active, effects)

def answered_sweep(+id: String, context: O.Context, checkpoint: Maybe<&2, O.Owner>, retained: Bool, result: P.State & Result<&2, &2, W.Error, W.Observation>) -> IO(O.State):
  (active, status) = result
  match status:
    case Fail{cause}: failed_sweep(id, context, checkpoint, retained, active, cause)
    case Done{observation}: done_sweep(id, context, checkpoint, retained, active, observation)

type SweepInput is Data:
  SweepInput{dimension: String, width: F32, height: F32, traversal: Nat, reads: Nat,
             malformed: Bool, tail: List<&2, SweepInput>}

type MovementPending is Data:
  MovementPending{from: M.Vec3, to: M.Vec3, original: Bool, tail: List<&2, MovementPending>}

type MovementRead is Data:
  MovementRead{movement: S.Movement, rest: List<&2, String>, tail: List<&2, MovementRead>}

def request_tail(+request: W.Request, malformed: Bool) -> W.Request:
  W.Request{facts, level, removed, physics, alive, width, height, movements, traversal, reads, tail} = request
  W.Request{facts, level, removed, physics, alive, width, height, movements, traversal, reads,
    P.choose(List<&2, W.Request>, [request], [], malformed)}

def sweep_ready(id: String, state: O.State, input: SweepInput, movements: List<&2, S.Movement>) -> IO(O.State):
  O.State{active, +context, checkpoint, retained, tail} = state
  O.Context{facts, level, removed, physics, alive, context_tail} = context
  SweepInput{dimension, +width, +height, +traversal, +reads, malformed, input_tail} = input
  request : W.Request = W.Request{facts, level, removed, physics, alive, width, height, movements, traversal, reads, []}
  answered_sweep(id, context, checkpoint, retained, W.query(active, dimension,
    request_tail(request, malformed)))

def movement_original(pending: MovementPending, parsed: Maybe<&2, O.VectorRead>) -> Maybe<&2, MovementRead>:
  match pending parsed:
    case MovementPending{from, to, original, tail} Some{O.VectorRead{vector, rest}}:
      Some{MovementRead{S.Movement{from, to, P.choose(Maybe<&2, M.Vec3>, Some{vector}, None{}, original)}, rest, []}}
    case _ _: None{}

def movement_to(from: M.Vec3, original: Bool, parsed: Maybe<&2, O.VectorRead>) -> Maybe<&2, MovementRead>:
  match parsed:
    case Some{O.VectorRead{to, rest}}:
      movement_original(MovementPending{from, to, original, []}, O.read_vector(rest))
    case None{}: None{}

def movement_from(original: Bool, parsed: Maybe<&2, O.VectorRead>) -> Maybe<&2, MovementRead>:
  match parsed:
    case Some{O.VectorRead{from, rest}}: movement_to(from, original, O.read_vector(rest))
    case None{}: None{}

def read_movement(fields: List<&2, String>) -> Maybe<&2, MovementRead>:
  match fields:
    case Nil{}: None{}
    case original <> rest: movement_from(U32.is_ne(O.number(original), 0), O.read_vector(rest))

def movement_append(reversed: List<&2, S.Movement>, entry: MovementRead) -> List<&2, S.Movement> & List<&2, String>:
  MovementRead{movement, rest, tail} = entry
  (movement <> reversed, rest)

def movement_branch(-T: Type, result: Maybe<&2, MovementRead>, accept: MovementRead -> T, reject: T) -> T:
  match result:
    case None{}: reject
    case Some{entry}: accept(entry)

def sweep_movements(fuel: Nat, id: String, state: O.State, input: SweepInput, reversed: List<&2, S.Movement>, fields: List<&2, String>) -> IO(O.State):
  match fuel fields:
    case _ Nil{}: sweep_ready(id, state, input, List.reverse(&2, S.Movement, reversed))
    case 0n _: IO.die(O.State, 2, "sweep parser budget")
    case 1n+p fields:
      movement_branch(IO(O.State), read_movement(fields), entry =>
        P.paired(List<&2, S.Movement>, List<&2, String>, IO(O.State), movement_append(reversed, entry),
          reversed => rest => sweep_movements(p, id, state, input, reversed, rest)),
        IO.die(O.State, 2, "invalid sweep movement"))

def visit_text(visits: List<&2, S.Visit>) -> String:
  match visits:
    case Nil{}: ""
    case S.Visit{S.Point{x, y, z}, step, segment} <> rest:
      U32.show(x) ++ "," ++ U32.show(y) ++ "," ++ U32.show(z) ++ "," ++ U32.show(step) ++ ";" ++ visit_text(rest)

def walk_finished(id: String, state: O.State, result: S.Build & U32) -> IO(O.State):
  (build, used) = result
  S.Build{fuel, seen, reversed, last, stopped, failure, tail} = build
  match failure:
    case Some{cause}:
      do IO<O.State>:
        IO.print(id ++ "\twalk-error\t" ++ traversal_error(cause))
        return state
    case None{}:
      do IO<O.State>:
        IO.print(id ++ "\twalk\t" ++ O.flag(Bool.not(stopped)) ++ "\t" ++ visit_text(List.reverse(&2, S.Visit, reversed)))
        return state

def walk_to(id: String, state: O.State, width: F32, height: F32, fuel: Nat, limit: U32, from: M.Vec3, parsed: Maybe<&2, O.VectorRead>) -> IO(O.State):
  match parsed:
    case Some{O.VectorRead{to, Nil{}}}:
      walk_finished(id, state, S.segment(S.Build{fuel, [], [], 0, False{}, None{}, []}, from, to, width, height, limit))
    case _: IO.die(O.State, 2, "invalid walk endpoint")

def walk_from(id: String, state: O.State, width: F32, height: F32, fuel: Nat, limit: U32, parsed: Maybe<&2, O.VectorRead>) -> IO(O.State):
  match parsed:
    case Some{O.VectorRead{from, rest}}: walk_to(id, state, width, height, fuel, limit, from, O.read_vector(rest))
    case None{}: IO.die(O.State, 2, "invalid walk start")

def clipped_text(value: Maybe<&2, M.Vec3>) -> String:
  match value:
    case None{}: "none"
    case Some{vector}: O.vector(vector)

def clip_to(id: String, state: O.State, box: A.AABB, from: M.Vec3, parsed: Maybe<&2, O.VectorRead>) -> IO(O.State):
  match parsed:
    case Some{O.VectorRead{to, Nil{}}}:
      do IO<O.State>:
        IO.print(id ++ "\tclip\t" ++ clipped_text(K.clip(box, from, to)))
        return state
    case _: IO.die(O.State, 2, "invalid clip endpoint")

def clip_from(id: String, state: O.State, box: A.AABB, parsed: Maybe<&2, O.VectorRead>) -> IO(O.State):
  match parsed:
    case Some{O.VectorRead{from, rest}}: clip_to(id, state, box, from, O.read_vector(rest))
    case None{}: IO.die(O.State, 2, "invalid clip start")

def clip_fields(id: String, state: O.State, fields: List<&2, String>) -> IO(O.State):
  match fields:
    case ah <> al <> bh <> bl <> ch <> cl <> dh <> dl <> eh <> el <> fh <> fl <> rest:
      clip_from(id, state, A.AABB{F.F64{O.number(ah), O.number(al)}, F.F64{O.number(bh), O.number(bl)}, F.F64{O.number(ch), O.number(cl)}, F.F64{O.number(dh), O.number(dl)}, F.F64{O.number(eh), O.number(el)}, F.F64{O.number(fh), O.number(fl)}}, O.read_vector(rest))
    case _: IO.die(O.State, 2, "invalid clip box")

def inspect(+id: String, state: O.State) -> IO(O.State):
  O.State{P.State{world, registry, +receiver, H.State{+history}, tail}, context, checkpoint, retained, state_tail} = state
  do IO<O.State>:
    IO.print(id ++ "\tstate\t" ++ O.receiver_text(receiver, history))
    return O.State{P.State{world, registry, receiver, H.State{history}, tail}, context, checkpoint, retained, state_tail}

def recheck(id: String, state: O.State) -> IO(O.State):
  O.State{active, context, checkpoint, retained, tail} = state
  O.checked(id, active, context, checkpoint, retained, True{})

def operation(fields: List<&2, String>, state: O.State, count: U32, identity: String) -> IO(O.State):
  match fields:
    case id <> "inspect" <> Nil{}: inspect(id, state)
    case id <> "sweep" <> dimension <> width <> height <> traversal <> reads <> malformed <> +rest:
      sweep_movements(List.length(&2, String, rest), id, state, SweepInput{dimension, float_word(O.number(width)), float_word(O.number(height)), U32.to_nat(O.number(traversal)), U32.to_nat(O.number(reads)), U32.is_ne(O.number(malformed), 0), []}, [], rest)
    case id <> "walk" <> width <> height <> fuel <> limit <> rest:
      walk_from(id, state, float_word(O.number(width)), float_word(O.number(height)), U32.to_nat(O.number(fuel)), O.number(limit), O.read_vector(rest))
    case id <> "clip" <> rest: clip_fields(id, state, rest)
    case id <> "seed" <> rest: O.seed_vector(id, state, O.read_vector(rest))
    case id <> "context" <> flags <> level <> rest:
      O.context_position(id, state, O.number(flags), O.number(level), O.read_vector(rest))
    case id <> "world" <> path <> Nil{}: O.world_file(id, state, path, count, identity)
    case id <> "raw-cell" <> x <> y <> z <> value <> Nil{}:
      O.raw_cell(id, state, C.Position{"minecraft:overworld", O.number(x), O.number(y), O.number(z)}, O.number(value))
    case id <> "checkpoint" <> Nil{}: O.checkpoint(id, state)
    case id <> "check" <> Nil{}: recheck(id, state)
    case "" <> Nil{}: IO.pure(O.State, state)
    case _: IO.die(O.State, 2, "invalid sweep request")

def operations(lines: List<&2, String>, state: O.State, +count: U32, +identity: String) -> IO(O.State):
  match lines:
    case Nil{}: IO.pure(O.State, state)
    case line <> rest:
      do IO<O.State>:
        next : O.State <- operation(String.split(line, Chr{9}), state, count, identity)
        operations(rest, next, count, identity)

def requests_loaded(state: O.State, count: U32, identity: String, result: Result<&2, &2, B.Error, String>) -> IO(Unit):
  match result:
    case Fail{cause}: IO.die(Unit, 2, B.error_text(cause))
    case Done{text}:
      do IO<Unit>:
        next : O.State <- operations(String.split(text, Chr{10}), state, count, identity)
        O.final_report(next)

def initial_world(registry: B.Registry, requests: String, count: U32, identity: String, result: Result<&2, &1, String, WC.Loaded>) -> IO(Unit):
  match result:
    case Fail{cause}: IO.die(Unit, 2, cause)
    case Done{WC.Loaded{world, peer}}:
      do IO<Unit>:
        text : Result<&2, &2, B.Error, String> <- B.read_text(requests)
        requests_loaded(O.State{P.State{world, registry, P.empty(), H.State{H.History{M.zero()}}, []}, O.Context{P.Player{False{}, False{}}, P.OrdinaryLevel{}, False{}, False{}, True{}, []}, None{}, True{}, []}, count, identity, text)

def registry_loaded(world: String, requests: String, +count: U32, +identity: String, result: Result<&2, &1, B.Error, B.Registry>) -> IO(Unit):
  match result:
    case Fail{cause}: IO.die(Unit, 2, B.error_text(cause))
    case Done{registry}:
      do IO<Unit>:
        bytes : List<&2, U32> <- O.raw_file(world)
        initial_world(registry, requests, count, identity, WC.decode(bytes, count, identity))

def arguments(args: List<String>) -> IO(Unit):
  match args:
    case registry <> world <> requests <> count <> identity <> Nil{}:
      do IO<Unit>:
        loaded : Result<&2, &1, B.Error, B.Registry> <- B.Registry.load(registry)
        registry_loaded(world, requests, O.number(count), identity, loaded)
    case _: IO.die(Unit, 2, "expected registry, world, requests, count and identity")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    arguments(List.tail(&1, String, args))
