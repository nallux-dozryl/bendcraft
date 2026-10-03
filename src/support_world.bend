import Base
import ./support.bend as S
import ./travel.bend as T
import ./movement.bend as M
import ./locomotion.bend as L
import ./geometry.bend as A
import ./f64.bend as F
import ./client_world.bend as W
import ./player_tick_world.bend as P
import ./core.bend as C
import ./game.bend as G
import ./registry.bend as B

type Sample is Data:
  Sample{ground: T.GroundSample, jump_factor: F32}

type Properties is Data:
  Properties{friction: F32, jump_factor: F32}

type Error is Data:
  SupportError{cause: S.Error}
  WorldError{cause: String}
  MissingPalette{}
  BodyMismatch{}
  UnexpectedCollider{}

def support_error_text(error: S.Error) -> String:
  match error:
    case S.InvalidPosition{field}: "invalid-support-position:" ++ U32.show(field)
    case S.InvalidBox{field}: "invalid-support-box:" ++ U32.show(field)
    case S.ReversedBox{axis}: "reversed-support-box:" ++ U32.show(axis)
    case S.InvalidMovement{field}: "invalid-support-movement:" ++ U32.show(field)
    case S.InvalidOffset{}: "invalid-support-offset"

def error_text(error: Error) -> String:
  match error:
    case SupportError{cause}: support_error_text(cause)
    case WorldError{cause}: cause
    case MissingPalette{}: "support-palette-unavailable"
    case BodyMismatch{}: "support-body-mismatch"
    case UnexpectedCollider{}: "support-non-full-cube"

# These four admitted Java blocks share these raw properties. Their names/IDs
# are dynamically resolved by W.Palette; fresh pinned Java metadata checks
# establish the property values and absence of fence/wall/gate tags.
def admitted_properties() -> Properties:
  Properties{0.6, 1.0}

def core_position(position: T.BlockPos) -> C.Position:
  T.BlockPos{x, y, z} = position
  C.Position{"minecraft:overworld", x, y, z}

def body_position(body: M.Body) -> M.Vec3:
  M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below} = body
  position

def body_ground(body: M.Body) -> Bool:
  M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below} = body
  ground

def classified(result: Result<&2, &2, String, Maybe<&2, U32>>) -> Result<&2, &2, Error, Properties>:
  match result:
    case Fail{error}: Fail{WorldError{error}}
    case Done{material}: Done{admitted_properties()}

def properties_read(palette: W.Palette, result: C.World & Result<&2, &2, C.Error, U32>) -> C.World & Result<&2, &2, Error, Properties>:
  (world, status) = result
  match status:
    case Fail{error}: (world, Fail{WorldError{W.error_text(error)}})
    case Done{state}: (world, classified(W.material(palette, state)))

def properties(world: C.World, palette: W.Palette, position: T.BlockPos) -> C.World & Result<&2, &2, Error, Properties>:
  properties_read(palette, C.read_block(world, core_position(position)))

# Cached coordinates are transient history, not cached block identities.
# Even a removed support block must be read and admitted as current AIR.
def cached_admission(world: C.World, palette: W.Palette, state: S.State) -> C.World & Result<&2, &2, Error, Unit>:
  match state:
    case S.State{None{}, flag}: (world, Done{Unit{}})
    case S.State{Some{position}, flag}:
      W.paired(C.World, Result<&2, &2, Error, Properties>, C.World & Result<&2, &2, Error, Unit>, properties(world, palette, position), next => status => (next, Result.map(&2, &2, Error, Properties, Unit, values => Unit{}, status)))

def sample_below_status(current: Properties, below: T.BlockPos, world: C.World, status: Result<&2, &2, Error, Properties>) -> C.World & Result<&2, &2, Error, Sample>:
  match current status:
    case _ Fail{error}: (world, Fail{error})
    case Properties{friction, jump} Done{Properties{below_friction, below_jump}}:
      (world, Done{Sample{T.GroundSample{below, below_friction}, S.jump_factor(jump, below_jump)}})

def sample_below(current: Properties, below: T.BlockPos, result: C.World & Result<&2, &2, Error, Properties>) -> C.World & Result<&2, &2, Error, Sample>:
  (world, status) = result
  sample_below_status(current, below, world, status)

def sample_current(palette: W.Palette, +below: T.BlockPos, result: C.World & Result<&2, &2, Error, Properties>) -> C.World & Result<&2, &2, Error, Sample>:
  (world, status) = result
  match status:
    case Fail{error}: (world, Fail{error})
    case Done{current}: sample_below(current, below, properties(world, palette, below))

def sample_admitted(+palette: W.Palette, position: M.Vec3, below: T.BlockPos, result: C.World & Result<&2, &2, Error, Unit>) -> C.World & Result<&2, &2, Error, Sample>:
  (world, status) = result
  match status:
    case Fail{error}: (world, Fail{error})
    case Done{unit}: sample_current(palette, below, properties(world, palette, S.block_position(position)))

def sample_position(world: C.World, +palette: W.Palette, position: M.Vec3, +state: S.State, below: Result<&2, &2, S.Error, T.BlockPos>) -> C.World & Result<&2, &2, Error, Sample>:
  match below:
    case Fail{error}: (world, Fail{SupportError{error}})
    case Done{below}: sample_admitted(palette, position, below, cached_admission(world, palette, state))

def sample_core(world: C.World, +palette: W.Palette, +position: M.Vec3, +state: S.State) -> C.World & Result<&2, &2, Error, Sample>:
  sample_position(world, palette, position, state, S.get_on_pos_checked(position, state, L.float_bits(1056964625)))

def sampled(registry: B.Registry, view: W.View, result: C.World & Result<&2, &2, Error, Sample>) -> W.State & Result<&2, &2, Error, Sample>:
  (world, status) = result
  (W.attach(G.Engine{world, registry}, view), status)

def sample_extracted(result: G.Engine & W.View, state: S.State) -> W.State & Result<&2, &2, Error, Sample>:
  match result:
    case (G.Engine{world, registry}, +view):
      match view:
        case W.View{body, yaw, pitch, None{}, region, cache}: (W.attach(G.Engine{world, registry}, view), Fail{MissingPalette{}})
        case W.View{body, yaw, pitch, Some{palette}, region, cache}: sampled(registry, view, sample_core(world, palette, body_position(body), state))

def sample_checked(world: W.State, state: S.State) -> W.State & Result<&2, &2, Error, Sample>:
  sample_extracted(W.take(world), state)

def coordinate(result: Result<&2, &2, F.F64ConversionError, U32>) -> Result<&2, &2, Error, U32>:
  match result:
    case Fail{error}: Fail{UnexpectedCollider{}}
    case Done{word}: Done{word}

def candidate_gate(candidate: S.Candidate, valid: Bool) -> Result<&2, &2, Error, S.Candidate>:
  match valid:
    case False{}: Fail{UnexpectedCollider{}}
    case True{}: Done{candidate}

def canonical_candidate(box: A.AABB, +candidate: S.Candidate) -> Result<&2, &2, Error, S.Candidate>:
  candidate_gate(candidate, P.box_bits(box, S.candidate_box(candidate)))

def candidate(collider: A.Collider) -> Result<&2, &2, Error, S.Candidate>:
  match collider:
    case A.BoxCollider{+box}:
      A.AABB{x, y, z, hx, hy, hz} = box
      do Result<&2, &2, Error, S.Candidate>:
        bx : U32 <- coordinate(F.floor_i32(x))
        by : U32 <- coordinate(F.floor_i32(y))
        bz : U32 <- coordinate(F.floor_i32(z))
        canonical_candidate(box, S.FullCube{T.BlockPos{bx, by, bz}})
    case _: Fail{UnexpectedCollider{}}

def candidates(colliders: List<&2, A.Collider>) -> Result<&2, &2, Error, List<&2, S.Candidate>>:
  match colliders:
    case Nil{}: Done{[]}
    case collider <> rest:
      do Result<&2, &2, Error, List<&2, S.Candidate>>:
        block : S.Candidate <- candidate(collider)
        remaining : List<&2, S.Candidate> <- candidates(rest)
        return block <> remaining

def collected(result: C.World & Result<&2, &2, String, List<&2, A.Collider>>) -> C.World & Result<&2, &2, Error, List<&2, S.Candidate>>:
  (world, status) = result
  match status:
    case Fail{error}: (world, Fail{WorldError{error}})
    case Done{colliders}: (world, candidates(colliders))

def collect(world: C.World, palette: W.Palette, query: A.AABB) -> C.World & Result<&2, &2, Error, List<&2, S.Candidate>>:
  collected(W.collect(world, palette, query))

def update_fallback_selected(state: S.State, primary: Maybe<&2, T.BlockPos>, movement: Bool, result: Result<&2, &2, S.Error, Maybe<&2, T.BlockPos>>) -> Result<&2, &2, Error, S.State>:
  match result:
    case Fail{error}: Fail{SupportError{error}}
    case Done{fallback}: Done{S.update_cached(state, True{}, primary, fallback, movement)}

def update_fallback_read(state: S.State, position: M.Vec3, query: A.AABB, primary: Maybe<&2, T.BlockPos>, movement: Bool, result: C.World & Result<&2, &2, Error, List<&2, S.Candidate>>) -> C.World & Result<&2, &2, Error, S.State>:
  (world, status) = result
  match status:
    case Fail{error}: (world, Fail{error})
    case Done{candidates}: (world, update_fallback_selected(state, primary, movement, S.select_checked(position, query, candidates)))

def update_needed(world: C.World, palette: W.Palette, state: S.State, position: M.Vec3, fallback: Maybe<&2, A.AABB>, primary: Maybe<&2, T.BlockPos>, movement: Bool, needed: Bool) -> C.World & Result<&2, &2, Error, S.State>:
  match fallback needed:
    case Some{+query} True{}: update_fallback_read(state, position, query, primary, movement, collect(world, palette, query))
    case _ _: (world, Done{S.update_cached(state, True{}, primary, None{}, movement)})

def update_primary_selected(world: C.World, palette: W.Palette, +state: S.State, position: M.Vec3, fallback: Maybe<&2, A.AABB>, +movement: Maybe<&2, M.Vec3>, result: Result<&2, &2, S.Error, Maybe<&2, T.BlockPos>>) -> C.World & Result<&2, &2, Error, S.State>:
  match result:
    case Fail{error}: (world, Fail{SupportError{error}})
    case Done{+primary}: update_needed(world, palette, state, position, fallback, primary, S.has_movement(movement), S.needs_fallback(state, True{}, primary, movement))

def update_primary_read(palette: W.Palette, state: S.State, +position: M.Vec3, fallback: Maybe<&2, A.AABB>, movement: Maybe<&2, M.Vec3>, +query: A.AABB, result: C.World & Result<&2, &2, Error, List<&2, S.Candidate>>) -> C.World & Result<&2, &2, Error, S.State>:
  (world, status) = result
  match status:
    case Fail{error}: (world, Fail{error})
    case Done{candidates}: update_primary_selected(world, palette, state, position, fallback, movement, S.select_checked(position, query, candidates))

def update_queries(world: C.World, +palette: W.Palette, state: S.State, position: M.Vec3, grounded: Bool, movement: Maybe<&2, M.Vec3>, result: Result<&2, &2, S.Error, S.Queries>) -> C.World & Result<&2, &2, Error, S.State>:
  match grounded result:
    case _ Fail{error}: (world, Fail{SupportError{error}})
    case False{} Done{query}: (world, Done{S.empty()})
    case True{} Done{S.Queries{+primary, fallback}}: update_primary_read(palette, state, position, fallback, movement, primary, collect(world, palette, primary))

def update_position(world: C.World, palette: W.Palette, state: S.State, position: M.Vec3, box: A.AABB, grounded: Bool, +movement: Maybe<&2, M.Vec3>, error: Maybe<&2, S.Error>) -> C.World & Result<&2, &2, Error, S.State>:
  match error:
    case Some{error}: (world, Fail{SupportError{error}})
    case None{}: update_queries(world, palette, state, position, grounded, movement, S.queries_checked(box, movement))

def update_core(world: C.World, palette: W.Palette, state: S.State, body: M.Body, movement: Maybe<&2, M.Vec3>) -> C.World & Result<&2, &2, Error, S.State>:
  M.Body{+position, box, velocity, width, height, ground, horizontal, vertical, below} = body
  update_position(world, palette, state, position, box, ground, movement, S.position_error(M.Vec3.invalid_field(position)))

def updated(registry: B.Registry, view: W.View, result: C.World & Result<&2, &2, Error, S.State>) -> W.State & Result<&2, &2, Error, S.State>:
  (world, status) = result
  (W.attach(G.Engine{world, registry}, view), status)

def update_extracted(result: G.Engine & W.View, state: S.State, movement: Maybe<&2, M.Vec3>) -> W.State & Result<&2, &2, Error, S.State>:
  match result:
    case (G.Engine{world, registry}, +view):
      match view:
        case W.View{body, yaw, pitch, None{}, region, cache}: (W.attach(G.Engine{world, registry}, view), Fail{MissingPalette{}})
        case W.View{body, yaw, pitch, Some{palette}, region, cache}: updated(registry, view, update_core(world, palette, state, body, movement))

def update_with_movement_checked(world: W.State, state: S.State, movement: Maybe<&2, M.Vec3>) -> W.State & Result<&2, &2, Error, S.State>:
  update_extracted(W.take(world), state, movement)

def update_matched(valid: Bool, engine: G.Engine, view: W.View, state: S.State, delta: M.Vec3) -> W.State & Result<&2, &2, Error, S.State>:
  match valid:
    case False{}: (W.attach(engine, view), Fail{BodyMismatch{}})
    case True{}: update_with_movement_checked(W.attach(engine, view), state, Some{delta})

def update_transition_extracted(state: S.State, transition: M.Transition, engine: G.Engine, +view: W.View) -> W.State & Result<&2, &2, Error, S.State>:
  match transition:
    case M.Transition{body, delta, stepped, changed}: update_matched(P.same_body(body, P.view_body(view)), engine, view, state, delta)

def update_transition(state: S.State, transition: M.Transition, result: G.Engine & W.View) -> W.State & Result<&2, &2, Error, S.State>:
  (engine, view) = result
  update_transition_extracted(state, transition, engine, view)

def update_checked(world: W.State, state: S.State, transition: M.Transition) -> W.State & Result<&2, &2, Error, S.State>:
  update_transition(state, transition, W.take(world))

def retain_original(original: S.State, result: W.State & Result<&2, &2, Error, S.State>) -> W.State & S.State & Result<&2, &2, Error, Unit>:
  (world, status) = result
  match status:
    case Fail{error}: (world, original, Fail{error})
    case Done{updated}: (world, updated, Done{Unit{}})

def update_retained_checked(world: W.State, +state: S.State, transition: M.Transition) -> W.State & S.State & Result<&2, &2, Error, Unit>:
  retain_original(state, update_checked(world, state, transition))

law retained_failure_preserves_prior_support:
  for world: W.State
  for +state: S.State
  for +error: Error
  {retain_original(state, (world, Fail{error})) == (world, state, Fail{error}) : W.State & S.State & Result<&2, &2, Error, Unit>}

def retained_failure_preserves_prior_support(world, state, error):
  {==}

law body_mismatch_preserves_owned_world_and_view:
  for engine: G.Engine
  for +view: W.View
  for state: S.State
  for delta: M.Vec3
  {update_matched(False{}, engine, view, state, delta) == (W.attach(engine, view), Fail{BodyMismatch{}}) : W.State & Result<&2, &2, Error, S.State>}

def body_mismatch_preserves_owned_world_and_view(engine, view, state, delta):
  {==}
