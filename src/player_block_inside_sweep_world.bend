import Base
import ./core.bend as C
import ./registry.bend as B
import ./player_fall_history.bend as H
import ./player_block_inside_stuck.bend as P
import ./player_block_inside_sweep.bend as S

type Error is Data:
  TraversalError{cause: S.Error}
  ProducerError{cause: P.Error}
  UnsupportedInsideShape{name: String, state: U32}
  ReadBudget{}
  NonCanonicalRequest{}

def error_text(error: Error) -> String:
  match error:
    case TraversalError{cause}: "traversal:" ++ S.error_text(cause)
    case ProducerError{cause}: "producer:" ++ P.error_text(cause)
    case UnsupportedInsideShape{name, state}: "unsupported-inside-shape:" ++ name ++ ":" ++ U32.show(state)
    case ReadBudget{}: "read-budget"
    case NonCanonicalRequest{}: "noncanonical-request"

def committed(reads: List<&2, Read>, callbacks: List<&2, Callback>,
              result: P.State & Result<&2, &2, P.Error, P.Observation>) -> P.State & Result<&2, &2, Error, Observation>:
  (next, status) = result
  match status:
    case Fail{error}: (next, Fail{ProducerError{error}})
    case Done{result}: (next, Done{Observation{result, List.reverse(&2, Read, reads), List.reverse(&2, Callback, callbacks)}})

type Request is Data:
  Request{facts: P.Facts, level: P.Level, removed: Bool, no_physics: Bool,
          alive: Bool, width: F32, height: F32, movements: List<&2, S.Movement>,
          traversal_fuel: Nat, read_fuel: Nat, tail: List<&2, Request>}

type Read is Data:
  Read{visit: S.Visit, identity: B.Resolved, collector_step_before: U32,
       entity_seen_before: Bool}

type Callback is Data:
  Callback{visit: S.Visit, identity: B.Resolved, inside: Bool}

type Observation is Data:
  Observation{effects: P.Observation, reads: List<&2, Read>, callbacks: List<&2, Callback>}

type Scratch is Data:
  Scratch{effects: P.Scratch, seen: List<&2, S.PackedKey>, collector_step: U32,
          reads: List<&2, Read>, callbacks: List<&2, Callback>, tail: List<&2, Scratch>}

def position(dimension: String, visit: S.Visit) -> C.Position:
  S.Visit{S.Point{x, y, z}, step, segment} = visit
  C.Position{dimension, x, y, z}

def air(identity: B.Resolved) -> Bool:
  B.Resolved{protocol, +name, state, assignments} = identity
  String.eq(name, "minecraft:air") || String.eq(name, "minecraft:void_air") ||
    String.eq(name, "minecraft:cave_air")

# Only independently established full entity-inside shapes with empty fluids.
# Unknown metadata does not become an assumed cube or an empty callback.
def full_inside(identity: B.Resolved) -> Bool:
  B.Resolved{protocol, +name, state, assignments} = identity
  String.eq(name, "minecraft:stone") || String.eq(name, "minecraft:dirt") ||
    String.eq(name, "minecraft:oak_planks") || String.eq(name, "minecraft:cobweb") ||
    String.eq(name, "minecraft:sweet_berry_bush")

def initial(receiver: P.Receiver, history: H.History) -> Scratch:
  Scratch{P.initial(receiver, history), [], 4294967295, [], [], []}

def observation(scratch: Scratch) -> Observation:
  Scratch{effects, seen, collector, reads, callbacks, tail} = scratch
  Observation{P.observation(effects), List.reverse(&2, Read, reads), List.reverse(&2, Callback, callbacks)}

def commit(state: P.State, scratch: Scratch) -> P.State & Result<&2, &2, Error, Observation>:
  Scratch{+effects, seen, collector, reads, callbacks, tail} = scratch
  committed(reads, callbacks, P.commit(state, effects))

def candidate_scratch(+visit: S.Visit, identity: B.Resolved, keys: List<&2, S.PackedKey>,
                      reads: List<&2, Read>, callbacks: List<&2, Callback>, tail: List<&2, Scratch>,
                      next: Result<&2, &2, P.Error, P.Scratch>) -> Result<&2, &2, Error, Scratch>:
  match next:
    case Fail{error}: Fail{ProducerError{error}}
    case Done{effects}:
      Done{Scratch{effects, S.key(S.visit_point(visit)) <> keys, S.visit_step(visit), reads, Callback{visit, identity, S.inside(visit)} <> callbacks, tail}}

def finish(state: P.State, current: Result<&2, &2, Error, Scratch>, terminal: Maybe<&2, S.Error>) -> P.State & Result<&2, &2, Error, Observation>:
  match current terminal:
    case Fail{error} _: (state, Fail{error})
    case Done{scratch} Some{error}: (state, Fail{TraversalError{error}})
    case Done{scratch} None{}: commit(state, scratch)

def candidate_done(dimension: String, +visit: S.Visit, +identity: B.Resolved,
                   scratch: Scratch, result: Result<&2, &2, P.Error, P.Candidate>) -> Result<&2, &2, Error, Scratch>:
  match scratch result:
    case _ Fail{error}: Fail{ProducerError{error}}
    case Scratch{effects, +keys, collector, reads, callbacks, tail} Done{candidate}:
      candidate_scratch(visit, identity, keys, reads, callbacks, tail,
        P.step_candidate(position(dimension, visit), identity, effects, Done{candidate}))

def callback(dimension: String, visit: S.Visit, +identity: B.Resolved,
             +facts: P.Facts, level: P.Level, +scratch: Scratch) -> Result<&2, &2, Error, Scratch>:
  Scratch{P.Scratch{+candidate, reversed}, keys, collector, reads, callbacks, tail} = scratch
  candidate_done(dimension, visit, identity, scratch,
    P.callback_checked(P.candidate_receiver(candidate), P.candidate_history(candidate), facts, level, identity))

def unsupported(identity: B.Resolved) -> Result<&2, &2, Error, Scratch>:
  B.Resolved{protocol, name, state, assignments} = identity
  Fail{UnsupportedInsideShape{name, state}}

def admitted(dimension: String, visit: S.Visit, identity: B.Resolved,
             facts: P.Facts, level: P.Level, scratch: Scratch,
             is_air: Bool, shape: Bool, duplicate: Bool) -> Result<&2, &2, Error, Scratch>:
  match is_air shape duplicate:
    case True{} _ _: Done{scratch}
    case False{} False{} _: unsupported(identity)
    case False{} True{} True{}: Done{scratch}
    case False{} True{} False{}: callback(dimension, visit, identity, facts, level, scratch)

def decoded(state: P.State, dimension: String, +visit: S.Visit,
            facts: P.Facts, level: P.Level, scratch: Scratch,
            result: Result<&2, &2, B.Error, B.Resolved>) -> P.State & Result<&2, &2, Error, Scratch>:
  match scratch result:
    case _ Fail{error}: (state, Fail{ProducerError{P.RegistryError{error}}})
    case Scratch{effects, +keys, +collector, reads, callbacks, tail} Done{+identity}:
      +duplicate = S.seen(keys, S.key(S.visit_point(visit)))
      (state, admitted(dimension, visit, identity, facts, level,
        Scratch{effects, keys, collector, Read{visit, identity, collector, duplicate} <> reads, callbacks, tail},
        air(identity), full_inside(identity), duplicate))

def decoded_owner(world: C.World, receiver: P.Receiver, history: H.State,
                  tail: List<&1, P.State>, dimension: String, visit: S.Visit,
                  facts: P.Facts, level: P.Level, scratch: Scratch,
                  result: B.Registry & Result<&2, &2, B.Error, B.Resolved>) -> P.State & Result<&2, &2, Error, Scratch>:
  (registry, status) = result
  decoded(P.State{world, registry, receiver, history, tail}, dimension, visit, facts, level, scratch, status)

def read_owner(registry: B.Registry, receiver: P.Receiver, history: H.State,
               tail: List<&1, P.State>, dimension: String, visit: S.Visit,
               facts: P.Facts, level: P.Level, scratch: Scratch,
               result: C.World & Result<&2, &2, C.Error, U32>) -> P.State & Result<&2, &2, Error, Scratch>:
  (world, status) = result
  match status:
    case Fail{error}: (P.State{world, registry, receiver, history, tail}, Fail{ProducerError{P.WorldError{error}}})
    case Done{state}: decoded_owner(world, receiver, history, tail, dimension, visit, facts, level, scratch, B.Registry.decode(registry, state))

def read(state: P.State, +dimension: String, +visit: S.Visit,
         facts: P.Facts, level: P.Level, scratch: Scratch) -> P.State & Result<&2, &2, Error, Scratch>:
  P.State{world, registry, receiver, history, tail} = state
  read_owner(registry, receiver, history, tail, dimension, visit, facts, level, scratch, C.read_block(world, position(dimension, visit)))

def loop(fuel: Nat, state: P.State, +dimension: String, +facts: P.Facts, +level: P.Level,
         visits: List<&2, S.Visit>, terminal: Maybe<&2, S.Error>,
         current: Result<&2, &2, Error, Scratch>) -> P.State & Result<&2, &2, Error, Observation>:
  match fuel visits current:
    case _ _ Fail{error}: finish(state, Fail{error}, terminal)
    case _ Nil{} Done{scratch}: finish(state, Done{scratch}, terminal)
    case 0n _ Done{scratch}: finish(state, Fail{ReadBudget{}}, terminal)
    case 1n+p visit <> rest Done{scratch}:
      P.paired(P.State, Result<&2, &2, Error, Scratch>, P.State & Result<&2, &2, Error, Observation>,
        read(state, dimension, visit, facts, level, scratch),
        next => status => loop(p, next, dimension, facts, level, rest, terminal, status))

def started(state: P.State, dimension: String, facts: P.Facts, level: P.Level,
            read_fuel: Nat, plan: S.Plan) -> P.State & Result<&2, &2, Error, Observation>:
  match state plan:
    case P.State{world, registry, +receiver, H.State{+history}, tail} S.Plan{visits, terminal}:
      loop(read_fuel, P.State{world, registry, receiver, H.State{history}, tail}, dimension, facts, level,
        visits, terminal, Done{initial(receiver, history)})

def gated(state: P.State, dimension: String, facts: P.Facts, level: P.Level,
          width: F32, height: F32, movements: List<&2, S.Movement>,
          traversal_fuel: Nat, read_fuel: Nat, admitted: Bool) -> P.State & Result<&2, &2, Error, Observation>:
  match admitted:
    case False{}: started(state, dimension, facts, level, read_fuel, S.Plan{[], None{}})
    case True{}: started(state, dimension, facts, level, read_fuel, S.plan(movements, width, height, traversal_fuel))

def query(state: P.State, dimension: String, request: Request) -> P.State & Result<&2, &2, Error, Observation>:
  match request:
    case Request{facts, level, removed, physics, alive, width, height, movements, traversal_fuel, read_fuel, Nil{}}:
      gated(state, dimension, facts, level, width, height, movements, traversal_fuel, read_fuel,
        Bool.not(removed || physics) && alive)
    case _: (state, Fail{NonCanonicalRequest{}})
