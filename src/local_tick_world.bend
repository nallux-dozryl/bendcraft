import Base
import ./local_input.bend as I
import ./player_tick.bend as P
import ./player_tick_world.bend as B
import ./travel_world.bend as T
import ./travel.bend as V
import ./client_world.bend as W
import ./game.bend as G
import ./locomotion.bend as L
import ./movement.bend as M

# Explicit local control/apply-input + neutral aiStep motion projection.
# Controls and its post-toggle attributes are resolved by the caller.
type Error is Data:
  BodyMismatch{}
  PreparationError{cause: I.Error}
  TravelError{cause: T.Error}
  FinishError{cause: P.Error}

# Box the complete rollback header rather than flattening it into every
# native continuation. Production constructors always use an empty tail.
type Prior is Data:
  Prior{view: W.View, local: I.State, player: P.State, tail: List<&2, Prior>}

def prior_view(prior: Prior) -> W.View:
  Prior{view, local, player, tail} = prior
  view

def context_tick(context: I.ApplyContext) -> P.Context:
  I.ApplyContext{tick, sneak, pitch} = context
  tick

def context_sprinting(context: I.ApplyContext) -> Bool:
  I.ApplyContext{P.Context{V.Context{ground, attrs, yaw, maximum, sprinting, no_gravity, discard, travel_mode}, strength, factor, affected, tick_mode}, sneak, pitch} = context
  sprinting

def controls_sprinting(controls: I.Controls) -> Bool:
  I.Controls{local, sprinting, updates} = controls
  sprinting

def rejected(engine: G.Engine, tables: L.Tables, prior: Prior, error: Error) -> W.State & L.Tables & I.State & P.State & Result<&2, &2, Error, P.Transition>:
  Prior{view, local, player, tail} = prior
  (W.attach(engine, view), tables, local, player, Fail{error})

def installed(engine: G.Engine, tables: L.Tables, prior: Prior, local: I.State, +transition: P.Transition) -> W.State & L.Tables & I.State & P.State & Result<&2, &2, Error, P.Transition>:
  match prior transition:
    case Prior{view, old_local, old_player, tail} P.Transition{+player, movement, attempted, jumped}:
      (W.attach(engine, T.with_body(view, B.player_body(player))), tables, local, player, Done{transition})

def completed(world: W.State, tables: L.Tables, prior: Prior, local: I.State, result: Result<&2, &2, P.Error, P.Transition>) -> W.State & L.Tables & I.State & P.State & Result<&2, &2, Error, P.Transition>:
  match result:
    case Fail{error}:
      W.paired(G.Engine, W.View, W.State & L.Tables & I.State & P.State & Result<&2, &2, Error, P.Transition>, W.take(world), engine => discarded => rejected(engine, tables, prior, FinishError{error}))
    case Done{transition}:
      W.paired(G.Engine, W.View, W.State & L.Tables & I.State & P.State & Result<&2, &2, Error, P.Transition>, W.take(world), engine => discarded => installed(engine, tables, prior, local, transition))

def finished(world: W.State, tables: L.Tables, original_view: W.View, original_local: I.State, original_player: P.State, local: I.State, result: Result<&2, &2, P.Error, P.Transition>) -> W.State & L.Tables & I.State & P.State & Result<&2, &2, Error, P.Transition>:
  completed(world, tables, Prior{original_view, original_local, original_player, []}, local, result)

def traveled(prior: Prior, local: I.State, prepared: P.PreTravel, context: P.Context, result: W.State & L.Tables & Result<&2, &2, T.Error, M.Transition>) -> W.State & L.Tables & I.State & P.State & Result<&2, &2, Error, P.Transition>:
  (world, tables, status) = result
  match status:
    case Fail{error}:
      W.paired(G.Engine, W.View, W.State & L.Tables & I.State & P.State & Result<&2, &2, Error, P.Transition>, W.take(world), engine => discarded => rejected(engine, tables, prior, TravelError{error}))
    case Done{movement}: completed(world, tables, prior, local, P.finish_checked(prepared, context, movement))

def prepared(engine: G.Engine, +prior: Prior, +context: P.Context, result: L.Tables & Result<&2, &2, I.Error, I.PreTravel>) -> W.State & L.Tables & I.State & P.State & Result<&2, &2, Error, P.Transition>:
  (tables, status) = result
  match status:
    case Fail{error}: rejected(engine, tables, prior, PreparationError{error})
    case Done{I.PreTravel{local, +value}}:
      P.PreTravel{player, input, attempted, jumped} = value
      traveled(prior, local, value, context, T.travel_checked(W.attach(engine, T.with_body(prior_view(prior), B.player_body(player))), tables, input, B.travel_context(context)))

def sprint_gate(valid: Bool, engine: G.Engine, tables: L.Tables, +prior: Prior, controls: I.Controls, +context: I.ApplyContext) -> W.State & L.Tables & I.State & P.State & Result<&2, &2, Error, P.Transition>:
  match valid:
    case False{}: rejected(engine, tables, prior, PreparationError{I.SprintContextMismatch{}})
    case True{}:
      Prior{view, local, player, tail} = prior
      prepared(engine, prior, context_tick(context), I.prepare_checked(tables, controls, player, context))

def authority_gate(valid: Bool, engine: G.Engine, view: W.View, tables: L.Tables, local: I.State, +player: P.State, +controls: I.Controls, +context: I.ApplyContext) -> W.State & L.Tables & I.State & P.State & Result<&2, &2, Error, P.Transition>:
  match valid:
    case False{}: (W.attach(engine, view), tables, local, player, Fail{BodyMismatch{}})
    case True{}: sprint_gate(I.same_bool(controls_sprinting(controls), context_sprinting(context)), engine, tables, Prior{view, local, player, []}, controls, context)

def extracted(tables: L.Tables, local: I.State, +player: P.State, controls: I.Controls, context: I.ApplyContext, result: G.Engine & W.View) -> W.State & L.Tables & I.State & P.State & Result<&2, &2, Error, P.Transition>:
  (engine, +view) = result
  authority_gate(B.same_body(B.view_body(view), B.player_body(player)), engine, view, tables, local, player, controls, context)

def tick_checked(world: W.State, tables: L.Tables, prior_local: I.State, player: P.State, controls: I.Controls, context: I.ApplyContext) -> W.State & L.Tables & I.State & P.State & Result<&2, &2, Error, P.Transition>:
  extracted(tables, prior_local, player, controls, context, W.take(world))

law body_mismatch_retains_owners_and_complete_prior_states:
  for engine: G.Engine
  for +view: W.View
  for tables: L.Tables
  for +local: I.State
  for +player: P.State
  for controls: I.Controls
  for context: I.ApplyContext
  {authority_gate(False{}, engine, view, tables, local, player, controls, context) == (W.attach(engine, view), tables, local, player, Fail{BodyMismatch{}}) : W.State & L.Tables & I.State & P.State & Result<&2, &2, Error, P.Transition>}

def body_mismatch_retains_owners_and_complete_prior_states(engine, view, tables, local, player, controls, context):
  {==}

law inconsistent_sprint_context_retains_complete_prior:
  for engine: G.Engine
  for tables: L.Tables
  for +view: W.View
  for +local: I.State
  for +player: P.State
  for controls: I.Controls
  for context: I.ApplyContext
  {sprint_gate(False{}, engine, tables, Prior{view, local, player, []}, controls, context) == (W.attach(engine, view), tables, local, player, Fail{PreparationError{I.SprintContextMismatch{}}}) : W.State & L.Tables & I.State & P.State & Result<&2, &2, Error, P.Transition>}

def inconsistent_sprint_context_retains_complete_prior(engine, tables, view, local, player, controls, context):
  {==}

law rejected_preparation_retains_complete_prior:
  for engine: G.Engine
  for tables: L.Tables
  for +view: W.View
  for +local: I.State
  for +player: P.State
  for context: P.Context
  for +error: I.Error
  {prepared(engine, Prior{view, local, player, []}, context, (tables, Fail{error})) == (W.attach(engine, view), tables, local, player, Fail{PreparationError{error}}) : W.State & L.Tables & I.State & P.State & Result<&2, &2, Error, P.Transition>}

def rejected_preparation_retains_complete_prior(engine, tables, view, local, player, context, error):
  {==}

law rejected_travel_restores_complete_prior:
  for engine: G.Engine
  for intermediate: W.View
  for tables: L.Tables
  for +view: W.View
  for +local: I.State
  for +player: P.State
  for next: I.State
  for value: P.PreTravel
  for context: P.Context
  for +error: T.Error
  {traveled(Prior{view, local, player, []}, next, value, context, (W.attach(engine, intermediate), tables, Fail{error})) == (W.attach(engine, view), tables, local, player, Fail{TravelError{error}}) : W.State & L.Tables & I.State & P.State & Result<&2, &2, Error, P.Transition>}

def rejected_travel_restores_complete_prior(engine, intermediate, tables, view, local, player, next, value, context, error):
  match intermediate:
    case W.View{body, yaw, pitch, palette, region, cache}: {==}

law rejected_finish_restores_complete_prior:
  for engine: G.Engine
  for intermediate: W.View
  for tables: L.Tables
  for +view: W.View
  for +local: I.State
  for +player: P.State
  for next: I.State
  for +error: P.Error
  {finished(W.attach(engine, intermediate), tables, view, local, player, next, Fail{error}) == (W.attach(engine, view), tables, local, player, Fail{FinishError{error}}) : W.State & L.Tables & I.State & P.State & Result<&2, &2, Error, P.Transition>}

def rejected_finish_restores_complete_prior(engine, intermediate, tables, view, local, player, next, error):
  match intermediate:
    case W.View{body, yaw, pitch, palette, region, cache}: {==}
