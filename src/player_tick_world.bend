import Base
import ./f64.bend as F
import ./geometry.bend as A
import ./movement.bend as M
import ./locomotion.bend as L
import ./game.bend as G
import ./client_world.bend as W
import ./travel_world.bend as T
import ./travel.bend as V
import ./player_tick.bend as P

type Error is Data:
  BodyMismatch{}
  PreparationError{cause: P.Error}
  TravelError{cause: T.Error}
  FinishError{cause: P.Error}

def scalar_bits(a: F.F64, b: F.F64) -> Bool:
  match a b:
    case F.F64{ah, al} F.F64{bh, bl}: U32.is_eq(ah, bh) && U32.is_eq(al, bl)

def vector_bits(a: M.Vec3, b: M.Vec3) -> Bool:
  match a b:
    case M.Vec3{ax, ay, az} M.Vec3{bx, by, bz}: scalar_bits(ax, bx) && scalar_bits(ay, by) && scalar_bits(az, bz)

def box_bits(a: A.AABB, b: A.AABB) -> Bool:
  match a b:
    case A.AABB{a, b, c, d, e, f} A.AABB{x, y, z, u, v, w}:
      scalar_bits(a, x) && scalar_bits(b, y) && scalar_bits(c, z) && scalar_bits(d, u) && scalar_bits(e, v) && scalar_bits(f, w)

def bool_bits(a: Bool, b: Bool) -> Bool:
  U32.is_eq(Bool.to_u32(a), Bool.to_u32(b))

def same_body(a: M.Body, b: M.Body) -> Bool:
  match a b:
    case M.Body{ap, ab, av, aw, ah, ag, ax, ay, az} M.Body{bp, bb, bv, bw, bh, bg, bx, by, bz}:
      vector_bits(ap, bp) && box_bits(ab, bb) && vector_bits(av, bv) && U32.is_eq(F32.bits(aw), F32.bits(bw)) && U32.is_eq(F32.bits(ah), F32.bits(bh)) && bool_bits(ag, bg) && bool_bits(ax, bx) && bool_bits(ay, by) && bool_bits(az, bz)

def player_body(player: P.State) -> M.Body:
  P.State{body, input, jumping, delay, trigger, sync, speed, head} = player
  body

def view_body(view: W.View) -> M.Body:
  W.View{body, yaw, pitch, palette, region, cache} = view
  body

def travel_context(context: P.Context) -> V.Context:
  P.Context{travel, strength, factor, affected, mode} = context
  travel

# Recursive Data boxes the rollback header instead of flattening its words
# into every native continuation. Production constructors use an empty tail.
type Prior is Data:
  Prior{view: W.View, player: P.State, tail: List<&2, Prior>}

def prior_view(prior: Prior) -> W.View:
  Prior{view, player, tail} = prior
  view

def rejected(engine: G.Engine, tables: L.Tables, prior: Prior, error: Error) -> W.State & L.Tables & P.State & Result<&2, &2, Error, P.Transition>:
  Prior{view, player, tail} = prior
  (W.attach(engine, view), tables, player, Fail{error})

def installed(engine: G.Engine, tables: L.Tables, prior: Prior, +transition: P.Transition) -> W.State & L.Tables & P.State & Result<&2, &2, Error, P.Transition>:
  match prior transition:
    case Prior{view, old_player, tail} P.Transition{+player, movement, attempted, jumped}:
      (W.attach(engine, T.with_body(view, player_body(player))), tables, player, Done{transition})

def completed(world: W.State, tables: L.Tables, prior: Prior, result: Result<&2, &2, P.Error, P.Transition>) -> W.State & L.Tables & P.State & Result<&2, &2, Error, P.Transition>:
  match result:
    case Fail{error}:
      W.paired(G.Engine, W.View, W.State & L.Tables & P.State & Result<&2, &2, Error, P.Transition>, W.take(world), engine => discarded => rejected(engine, tables, prior, FinishError{error}))
    case Done{transition}:
      W.paired(G.Engine, W.View, W.State & L.Tables & P.State & Result<&2, &2, Error, P.Transition>, W.take(world), engine => discarded => installed(engine, tables, prior, transition))

def finished(world: W.State, tables: L.Tables, original_view: W.View, original_player: P.State, result: Result<&2, &2, P.Error, P.Transition>) -> W.State & L.Tables & P.State & Result<&2, &2, Error, P.Transition>:
  completed(world, tables, Prior{original_view, original_player, []}, result)

def traveled(prior: Prior, prepared: P.PreTravel, context: P.Context, result: W.State & L.Tables & Result<&2, &2, T.Error, M.Transition>) -> W.State & L.Tables & P.State & Result<&2, &2, Error, P.Transition>:
  (world, tables, status) = result
  match status:
    case Fail{error}:
      W.paired(G.Engine, W.View, W.State & L.Tables & P.State & Result<&2, &2, Error, P.Transition>, W.take(world), engine => discarded => rejected(engine, tables, prior, TravelError{error}))
    case Done{movement}: completed(world, tables, prior, P.finish_checked(prepared, context, movement))

def prepared(engine: G.Engine, +prior: Prior, +context: P.Context, result: L.Tables & Result<&2, &2, P.Error, P.PreTravel>) -> W.State & L.Tables & P.State & Result<&2, &2, Error, P.Transition>:
  (tables, status) = result
  match status:
    case Fail{error}: rejected(engine, tables, prior, PreparationError{error})
    case Done{+value}:
      P.PreTravel{player, input, attempted, jumped} = value
      traveled(prior, value, context, T.travel_checked(W.attach(engine, T.with_body(prior_view(prior), player_body(player))), tables, input, travel_context(context)))

def authority_gate(valid: Bool, engine: G.Engine, view: W.View, tables: L.Tables, +player: P.State, +context: P.Context) -> W.State & L.Tables & P.State & Result<&2, &2, Error, P.Transition>:
  match valid:
    case False{}: (W.attach(engine, view), tables, player, Fail{BodyMismatch{}})
    case True{}: prepared(engine, Prior{view, player, []}, context, P.prepare_checked(tables, player, context))

def extracted(tables: L.Tables, +player: P.State, context: P.Context, result: G.Engine & W.View) -> W.State & L.Tables & P.State & Result<&2, &2, Error, P.Transition>:
  (engine, +view) = result
  authority_gate(same_body(view_body(view), player_body(player)), engine, view, tables, player, context)

def tick_checked(world: W.State, tables: L.Tables, player: P.State, context: P.Context) -> W.State & L.Tables & P.State & Result<&2, &2, Error, P.Transition>:
  extracted(tables, player, context, W.take(world))

law body_mismatch_retains_both_owners_and_player:
  for engine: G.Engine
  for +view: W.View
  for tables: L.Tables
  for +player: P.State
  for context: P.Context
  {authority_gate(False{}, engine, view, tables, player, context) == (W.attach(engine, view), tables, player, Fail{BodyMismatch{}}) : W.State & L.Tables & P.State & Result<&2, &2, Error, P.Transition>}

def body_mismatch_retains_both_owners_and_player(engine, view, tables, player, context):
  {==}

law rejected_preparation_retains_original_player_and_view:
  for engine: G.Engine
  for +view: W.View
  for +player: P.State
  for context: P.Context
  for tables: L.Tables
  for +error: P.Error
  {prepared(engine, Prior{view, player, []}, context, (tables, Fail{error})) == (W.attach(engine, view), tables, player, Fail{PreparationError{error}}) : W.State & L.Tables & P.State & Result<&2, &2, Error, P.Transition>}

def rejected_preparation_retains_original_player_and_view(engine, view, player, context, tables, error):
  {==}

law rejected_travel_restores_original_player_and_view:
  for engine: G.Engine
  for intermediate: W.View
  for +view: W.View
  for +player: P.State
  for value: P.PreTravel
  for context: P.Context
  for tables: L.Tables
  for +error: T.Error
  {traveled(Prior{view, player, []}, value, context, (W.attach(engine, intermediate), tables, Fail{error})) == (W.attach(engine, view), tables, player, Fail{TravelError{error}}) : W.State & L.Tables & P.State & Result<&2, &2, Error, P.Transition>}

def rejected_travel_restores_original_player_and_view(engine, intermediate, view, player, value, context, tables, error):
  match intermediate:
    case W.View{body, yaw, pitch, palette, region, cache}: {==}

law rejected_finish_restores_original_player_and_view:
  for engine: G.Engine
  for intermediate: W.View
  for +view: W.View
  for +player: P.State
  for tables: L.Tables
  for +error: P.Error
  {finished(W.attach(engine, intermediate), tables, view, player, Fail{error}) == (W.attach(engine, view), tables, player, Fail{FinishError{error}}) : W.State & L.Tables & P.State & Result<&2, &2, Error, P.Transition>}

def rejected_finish_restores_original_player_and_view(engine, intermediate, view, player, tables, error):
  match intermediate:
    case W.View{body, yaw, pitch, palette, region, cache}: {==}
