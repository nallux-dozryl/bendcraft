import Base
import ./client_world.bend as W
import ./game.bend as G
import ./movement.bend as M
import ./locomotion.bend as L
import ./travel.bend as T

# An explicit neutral travel call, not a Player tick or a ground resolver.
type Error is Data:
  PreparationError{cause: T.Error}
  WorldMovementError{cause: String}
  FinishError{cause: T.Error}

def with_body(view: W.View, body: M.Body) -> W.View:
  W.View{old, yaw, pitch, palette, region, cache} = view
  W.View{body, yaw, pitch, palette, region, cache}

def finished(state: W.State, tables: L.Tables, original: W.View, result: Result<&2, &2, T.Error, M.Transition>) -> W.State & L.Tables & Result<&2, &2, Error, M.Transition>:
  match result:
    case Fail{error}:
      W.paired(G.Engine, W.View, W.State & L.Tables & Result<&2, &2, Error, M.Transition>, W.take(state), engine => discarded => (W.attach(engine, original), tables, Fail{FinishError{error}}))
    case Done{+transition}:
      M.Transition{body, displacement, stepped, changed} = transition
      W.paired(G.Engine, W.View, W.State & L.Tables & Result<&2, &2, Error, M.Transition>, W.take(state), engine => discarded => (W.attach(engine, with_body(original, body)), tables, Done{transition}))

def moved(tables: L.Tables, original: W.View, prepared: T.Prepared, result: W.State & Result<&2, &2, String, M.Transition>) -> W.State & L.Tables & Result<&2, &2, Error, M.Transition>:
  (state, status) = result
  match status:
    case Fail{error}:
      W.paired(G.Engine, W.View, W.State & L.Tables & Result<&2, &2, Error, M.Transition>, W.take(state), engine => discarded => (W.attach(engine, original), tables, Fail{WorldMovementError{error}}))
    case Done{transition}: finished(state, tables, original, T.finish_checked(prepared, transition))

def prepared(engine: G.Engine, +original: W.View, result: L.Tables & Result<&2, &2, T.Error, T.Prepared>) -> W.State & L.Tables & Result<&2, &2, Error, M.Transition>:
  (tables, status) = result
  match status:
    case Fail{error}: (W.attach(engine, original), tables, Fail{PreparationError{error}})
    case Done{+value}:
      T.Prepared{body, requested, friction, acceleration, maximum, gravity, drag, discard} = value
      moved(tables, original, value, W.move(W.attach(engine, with_body(original, body)), requested, maximum))

def extracted(tables: L.Tables, input: M.Vec3, context: T.Context, result: G.Engine & W.View) -> W.State & L.Tables & Result<&2, &2, Error, M.Transition>:
  (engine, +view) = result
  W.View{body, yaw, pitch, palette, region, cache} = view
  prepared(engine, view, T.prepare_checked(tables, body, input, context))

def travel_checked(state: W.State, tables: L.Tables, input: M.Vec3, context: T.Context) -> W.State & L.Tables & Result<&2, &2, Error, M.Transition>:
  extracted(tables, input, context, W.take(state))

law rejected_preparation_retains_world_view_and_tables:
  for engine: G.Engine
  for +view: W.View
  for tables: L.Tables
  for +error: T.Error
  {prepared(engine, view, (tables, Fail{error})) == (W.attach(engine, view), tables, Fail{PreparationError{error}}) : W.State & L.Tables & Result<&2, &2, Error, M.Transition>}

def rejected_preparation_retains_world_view_and_tables(engine, view, tables, error):
  {==}

law rejected_world_movement_restores_original_view:
  for engine: G.Engine
  for intermediate: W.View
  for +original: W.View
  for tables: L.Tables
  for value: T.Prepared
  for +error: String
  {moved(tables, original, value, (W.attach(engine, intermediate), Fail{error})) == (W.attach(engine, original), tables, Fail{WorldMovementError{error}}) : W.State & L.Tables & Result<&2, &2, Error, M.Transition>}

def rejected_world_movement_restores_original_view(engine, intermediate, original, tables, value, error):
  match intermediate:
    case W.View{body, yaw, pitch, palette, region, cache}: {==}

law rejected_finish_restores_original_view:
  for engine: G.Engine
  for intermediate: W.View
  for +original: W.View
  for tables: L.Tables
  for +error: T.Error
  {finished(W.attach(engine, intermediate), tables, original, Fail{error}) == (W.attach(engine, original), tables, Fail{FinishError{error}}) : W.State & L.Tables & Result<&2, &2, Error, M.Transition>}

def rejected_finish_restores_original_view(engine, intermediate, original, tables, error):
  match intermediate:
    case W.View{body, yaw, pitch, palette, region, cache}: {==}

law body_update_preserves_view_fields:
  for old: M.Body
  for +next: M.Body
  for +yaw: F32
  for +pitch: F32
  for +palette: Maybe<&2, W.Palette>
  for +region: W.Bounds
  for +cache: Maybe<&2, W.SnapshotCache>
  {with_body(W.View{old, yaw, pitch, palette, region, cache}, next) == W.View{next, yaw, pitch, palette, region, cache} : W.View}

def body_update_preserves_view_fields(old, next, yaw, pitch, palette, region, cache):
  {==}
