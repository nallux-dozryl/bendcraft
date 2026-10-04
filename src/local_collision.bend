import Base
import ./f64.bend as F
import ./geometry.bend as G
import ./movement.bend as M
import ./locomotion.bend as L
import ./player_input.bend as PI

type Mode is Data:
  NeutralDry{}
  Flight{}
  Swimming{}
  Passenger{}
  NoPhysics{}
  NonNeutralEffects{}
  UnsupportedWorld{}

type Mover is Data:
  Self{}
  Player{}
  OtherMover{}

type Error is Data:
  UnsupportedContext{mode: Mode}
  UnsupportedMover{}
  FlyingAbility{}
  InvalidInput{field: U32}
  InvalidBody{cause: M.Error}
  InvalidStep{}
  InvalidFallDistance{}
  InvalidQuery{field: U32}
  QueryDenied{reason: String}
  QueryBudget{}
  UnexpectedAnswer{}
  MissingObservation{}
  MismatchedQuery{}
  ExtraObservations{}

type MinorInput is Data:
  MinorInput{yaw_degrees: F32, xxa: F32, zza: F32}

type AngleDetails is Data:
  AngleDetails{dot: F.F64, ratio: F.F64, angle: F.F64}

type MinorObservation is Data:
  MinorObservation{minor: Bool, rotated_x: F.F64, rotated_z: F.F64,
                   input_squared: F.F64, movement_squared: F.F64,
                   angle: Maybe<&2, AngleDetails>}

type EdgeContext is Data:
  EdgeContext{maximum: F32, fall_distance: F.F64, flying: Bool,
              keys: PI.Buttons, mover: Mover, mode: Mode}

type EdgeWork is Data:
  EdgeWork{box: G.AABB, maximum: F.F64, x: F.F64, y: F.F64, z: F.F64,
           step_x: F.F64, step_z: F.F64}

type Continuation is Data:
  AboveProbe{work: EdgeWork}
  XProbe{work: EdgeWork}
  ZProbe{work: EdgeWork}
  BothProbe{work: EdgeWork}

# noCollision includes actual entity and world-border policy, not just blocks.
# The caller must reject observations it cannot resolve faithfully.
type EdgeProgress is Data:
  EdgeDone{movement: M.Vec3}
  EdgeQuery{box: G.AABB, continuation: Continuation}

type QueryObservation is Data:
  QueryObservation{box: G.AABB, answer: Result<&2, &2, Error, Bool>}

type BackoffObservation is Data:
  BackoffObservation{movement: M.Vec3, queries: Nat}

def zero() -> F.F64:
  F.F64{0, 0}

def one() -> F.F64:
  F.F64{1072693248, 0}

def half() -> F.F64:
  F.F64{1071644672, 0}

def two() -> F.F64:
  F.F64{1073741824, 0}

def pi() -> F.F64:
  F.F64{1074340347, 1413754136}

def pi_over_two() -> F.F64:
  F.F64{1073291771, 1413754136}

def pi_over_two_low() -> F.F64:
  F.F64{1016178214, 856972295}

# Exact binary64 coefficient words from OpenJDK25 FdLibm.Acos.
# Each arithmetic node calls an independently checked IEEE-754 operation.
def acos_p(+z: F.F64) -> F.F64:
  F.mul(z, F.add(F.F64{1069897045, 1431655765},
    F.mul(z, F.add(F.F64{3218396690, 65761149},
    F.mul(z, F.add(F.F64{1070186837, 243811413},
    F.mul(z, F.add(F.F64{3215229480, 3043528507},
    F.mul(z, F.add(F.F64{1061810144, 1963045512},
    F.mul(z, F.F64{1057111521, 234747657})))))))))))

def acos_q(+z: F.F64) -> F.F64:
  F.add(one(), F.mul(z, F.add(F.F64{3221436967, 478817611},
    F.mul(z, F.add(F.F64{1073752805, 2623113928},
    F.mul(z, F.add(F.F64{3219523180, 462225753},
    F.mul(z, F.F64{1068742853, 2972619394}))))))))

def acos_ratio(+z: F.F64) -> F.F64:
  F.div(acos_p(z), acos_q(z))

def high_part(value: F.F64) -> F.F64:
  F.F64{hi, lo} = value
  F.F64{hi, 0}

def acos_positive_root(+z: F.F64, +root: F.F64) -> F.F64:
  +top = high_part(root)
  correction = F.div(F.sub(z, F.mul(top, top)), F.add(root, top))
  F.mul(two(), F.add(top, F.add(F.mul(acos_ratio(z), root), correction)))

def acos_positive(+x: F.F64) -> F.F64:
  +z = F.mul(F.sub(one(), x), half())
  acos_positive_root(z, F.sqrt(z))

def acos_negative(+x: F.F64) -> F.F64:
  +z = F.mul(F.add(one(), x), half())
  +root = F.sqrt(z)
  tail = F.sub(F.mul(acos_ratio(z), root), pi_over_two_low())
  F.sub(pi(), F.mul(two(), F.add(root, tail)))

def acos_small(+x: F.F64, tiny: Bool) -> F.F64:
  match tiny:
    case True{}: F.add(pi_over_two(), pi_over_two_low())
    case False{}:
      F.sub(pi_over_two(), F.sub(x, F.sub(pi_over_two_low(), F.mul(x, acos_ratio(F.mul(x, x))))))

def acos_inside_gate(x: F.F64, high: U32, negative: Bool, small: Bool) -> F.F64:
  match negative small:
    case _ True{}: acos_small(x, U32.is_le(high, 1012924416))
    case True{} False{}: acos_negative(x)
    case False{} False{}: acos_positive(x)

def acos_inside(x: F.F64, +high: U32, negative: Bool) -> F.F64:
  acos_inside_gate(x, high, negative, U32.is_lt(high, 1071644672))

def acos_outside(+x: F.F64, exact_one: Bool, negative: Bool) -> F.F64:
  match exact_one negative:
    case True{} False{}: zero()
    case True{} True{}: F.add(pi(), F.mul(two(), pi_over_two_low()))
    case False{} _: F.div(F.sub(x, x), F.sub(x, x))

# This is pinned fdlibm arithmetic, not a mathematical correctly-rounded-acos
# claim. Actual installed Math/StrictMath calls decide its tested bit parity.
def acos_gate(+x: F.F64, magnitude: U32, lo: U32, outside: Bool) -> F.F64:
  match outside:
    case True{}: acos_outside(x, U32.is_eq(magnitude, 1072693248) && U32.is_eq(lo, 0), F.sign(x))
    case False{}: acos_inside(x, magnitude, F.sign(x))

def acos(+x: F.F64) -> F.F64:
  F.F64{+hi, lo} = x
  +magnitude = U32.and(hi, 2147483647)
  acos_gate(x, magnitude, lo, U32.is_ge(magnitude, 1072693248))

def minor_angle(+x: F.F64, +z: F.F64, +input_squared: F.F64,
                +movement_squared: F.F64, resolved: M.Vec3) -> MinorObservation:
  M.Vec3{dx, dy, dz} = resolved
  +dot = F.add(F.mul(x, dx), F.mul(z, dz))
  +ratio = F.div(dot, F.sqrt(F.mul(input_squared, movement_squared)))
  +angle = acos(ratio)
  MinorObservation{F.is_lt(angle, F.F64{1069670214, 2684354560}), x, z,
    input_squared, movement_squared, Some{AngleDetails{dot, ratio, angle}}}

def minor_magnitude_gate(x: F.F64, z: F.F64, input_squared: F.F64,
                         movement_squared: F.F64, resolved: M.Vec3, small: Bool) -> MinorObservation:
  match small:
    case True{}: MinorObservation{False{}, x, z, input_squared, movement_squared, None{}}
    case False{}: minor_angle(x, z, input_squared, movement_squared, resolved)

def minor_magnitudes(+x: F.F64, +z: F.F64, +resolved: M.Vec3) -> MinorObservation:
  +input_squared = F.add(F.mul(x, x), F.mul(z, z))
  +movement_squared = M.Vec3.horizontal_squared(resolved)
  +threshold = F.from_f32(L.float_bits(925353388))
  minor_magnitude_gate(x, z, input_squared, movement_squared, resolved,
    F.is_lt(input_squared, threshold) || F.is_lt(movement_squared, threshold))

def minor_rotated(input: MinorInput, sine: F32, cosine: F32, resolved: M.Vec3) -> MinorObservation:
  MinorInput{yaw, xxa, zza} = input
  +x = F.from_f32(xxa)
  +z = F.from_f32(zza)
  +s = F.from_f32(sine)
  +c = F.from_f32(cosine)
  minor_magnitudes(F.sub(F.mul(x, c), F.mul(z, s)), F.add(F.mul(z, c), F.mul(x, s)), resolved)

def minor_cosine(input: MinorInput, resolved: M.Vec3, sine: F32, read: L.Tables & F32) -> L.Tables & MinorObservation:
  (tables, cosine) = read
  (tables, minor_rotated(input, sine, cosine, resolved))

def minor_sine(input: MinorInput, resolved: M.Vec3, angle: F.F64, read: L.Tables & F32) -> L.Tables & MinorObservation:
  (tables, sine) = read
  minor_cosine(input, resolved, sine, L.cos(tables, angle))

def minor(tables: L.Tables, +input: MinorInput, resolved: M.Vec3) -> L.Tables & MinorObservation:
  MinorInput{yaw, xxa, zza} = input
  +angle = F.from_f32(F32.mul(yaw, L.float_bits(1016003125)))
  minor_sine(input, resolved, angle, L.sin(tables, angle))

def mode_error(mode: Mode) -> Maybe<&2, Error>:
  match mode:
    case NeutralDry{}: None{}
    case other: Some{UnsupportedContext{other}}

def input_error(invalid: Maybe<&2, U32>) -> Maybe<&2, Error>:
  match invalid:
    case None{}: None{}
    case Some{field}: Some{InvalidInput{field}}

def body_error(invalid: Maybe<&2, M.Error>) -> Maybe<&2, Error>:
  match invalid:
    case None{}: None{}
    case Some{cause}: Some{InvalidBody{cause}}

def first_error(first: Maybe<&2, Error>, second: Maybe<&2, Error>) -> Maybe<&2, Error>:
  match first:
    case None{}: second
    case Some{error}: Some{error}

def minor_error(body: M.Body, input: MinorInput, +resolved: M.Vec3, mode: Mode) -> Maybe<&2, Error>:
  MinorInput{yaw, xxa, zza} = input
  first_error(mode_error(mode), first_error(body_error(M.Body.invalid(body)),
    input_error(G.first_nonfinite(F.from_f32(yaw) <> F.from_f32(xxa) <> F.from_f32(zza) <>
      M.Vec3.axis(resolved, G.AxisX{}) <> M.Vec3.axis(resolved, G.AxisY{}) <>
      M.Vec3.axis(resolved, G.AxisZ{}) <> Nil{}, 0))))

def minor_result(read: L.Tables & MinorObservation) -> L.Tables & Result<&2, &2, Error, MinorObservation>:
  (tables, observed) = read
  (tables, Done{observed})

def minor_gate(tables: L.Tables, input: MinorInput, resolved: M.Vec3, error: Maybe<&2, Error>) -> L.Tables & Result<&2, &2, Error, MinorObservation>:
  match error:
    case Some{error}: (tables, Fail{error})
    case None{}: minor_result(minor(tables, input, resolved))

def minor_checked(tables: L.Tables, body: M.Body, +input: MinorInput,
                  +resolved: M.Vec3, mode: Mode) -> L.Tables & Result<&2, &2, Error, MinorObservation>:
  minor_gate(tables, input, resolved, minor_error(body, input, resolved, mode))

def epsilon() -> F.F64:
  F.F64{1048238066, 2596056904}

def decrement_size() -> F.F64:
  F.F64{1068079513, 2576980378}

def signed_step_gate(value: F.F64, zero: Bool, negative: Bool) -> F.F64:
  match zero:
    case True{}: F.mul(value, decrement_size())
    case False{}:
      match negative:
        case True{}: F.neg(decrement_size())
        case False{}: decrement_size()

def signed_step(+value: F.F64) -> F.F64:
  signed_step_gate(value, F.is_zero(value), F.sign(value))

def shrink_gate(value: F.F64, amount: F.F64, tiny: Bool) -> F.F64:
  match tiny:
    case True{}: zero()
    case False{}: F.sub(value, amount)

def shrink(+value: F.F64, amount: F.F64) -> F.F64:
  shrink_gate(value, amount, F.is_le(F.abs(value), decrement_size()))

def fall_query(box: G.AABB, +x: F.F64, +z: F.F64, drop: F.F64) -> G.AABB:
  G.AABB{a, +b, c, d, e, f} = box
  G.AABB.new(F.add(F.add(a, epsilon()), x), F.sub(F.sub(b, drop), epsilon()),
    F.add(F.add(c, epsilon()), z), F.add(F.sub(d, epsilon()), x), b,
    F.add(F.sub(f, epsilon()), z))

def query_result(box: G.AABB, continuation: Continuation, invalid: Maybe<&2, U32>) -> Result<&2, &2, Error, EdgeProgress>:
  match invalid:
    case None{}: Done{EdgeQuery{box, continuation}}
    case Some{field}: Fail{InvalidQuery{field}}

def checked_query(+box: G.AABB, continuation: Continuation) -> Result<&2, &2, Error, EdgeProgress>:
  query_result(box, continuation, G.AABB.invalid_field(box))

def finish_work(work: EdgeWork) -> Result<&2, &2, Error, EdgeProgress>:
  EdgeWork{box, maximum, x, y, z, sx, sz} = work
  Done{EdgeDone{M.Vec3{x, y, z}}}

def both_probe_gate(+work: EdgeWork, active: Bool) -> Result<&2, &2, Error, EdgeProgress>:
  EdgeWork{box, maximum, +x, y, +z, sx, sz} = work
  match active:
    case True{}: checked_query(fall_query(box, x, z, maximum), BothProbe{work})
    case False{}: finish_work(work)

def both_probe(+work: EdgeWork) -> Result<&2, &2, Error, EdgeProgress>:
  EdgeWork{box, maximum, x, y, z, sx, sz} = work
  both_probe_gate(work, Bool.not(F.is_zero(x)) && Bool.not(F.is_zero(z)))

def z_probe_gate(+work: EdgeWork, is_zero: Bool) -> Result<&2, &2, Error, EdgeProgress>:
  EdgeWork{box, maximum, x, y, +z, sx, sz} = work
  match is_zero:
    case True{}: both_probe(work)
    case False{}: checked_query(fall_query(box, zero(), z, maximum), ZProbe{work})

def z_probe(+work: EdgeWork) -> Result<&2, &2, Error, EdgeProgress>:
  EdgeWork{box, maximum, x, y, z, sx, sz} = work
  z_probe_gate(work, F.is_zero(z))

def x_probe_gate(+work: EdgeWork, is_zero: Bool) -> Result<&2, &2, Error, EdgeProgress>:
  EdgeWork{box, maximum, +x, y, z, sx, sz} = work
  match is_zero:
    case True{}: z_probe(work)
    case False{}: checked_query(fall_query(box, x, zero(), maximum), XProbe{work})

def x_probe(+work: EdgeWork) -> Result<&2, &2, Error, EdgeProgress>:
  EdgeWork{box, maximum, x, y, z, sx, sz} = work
  x_probe_gate(work, F.is_zero(x))

def advance_above(work: EdgeWork, clear: Bool) -> Result<&2, &2, Error, EdgeProgress>:
  match clear:
    case True{}: finish_work(work)
    case False{}: x_probe(work)

def advance_x(work: EdgeWork, clear: Bool) -> Result<&2, &2, Error, EdgeProgress>:
  match work clear:
    case EdgeWork{box, maximum, x, y, z, sx, sz} False{}:
      z_probe(EdgeWork{box, maximum, x, y, z, sx, sz})
    case EdgeWork{box, maximum, x, y, z, +sx, sz} True{}:
      x_probe(EdgeWork{box, maximum, shrink(x, sx), y, z, sx, sz})

def advance_z(work: EdgeWork, clear: Bool) -> Result<&2, &2, Error, EdgeProgress>:
  match work clear:
    case EdgeWork{box, maximum, x, y, z, sx, sz} False{}:
      both_probe(EdgeWork{box, maximum, x, y, z, sx, sz})
    case EdgeWork{box, maximum, x, y, z, sx, +sz} True{}:
      z_probe(EdgeWork{box, maximum, x, y, shrink(z, sz), sx, sz})

def advance_both(work: EdgeWork, clear: Bool) -> Result<&2, &2, Error, EdgeProgress>:
  match work clear:
    case EdgeWork{box, maximum, x, y, z, sx, sz} False{}:
      finish_work(EdgeWork{box, maximum, x, y, z, sx, sz})
    case EdgeWork{box, maximum, x, y, z, +sx, +sz} True{}:
      both_probe(EdgeWork{box, maximum, shrink(x, sx), y, shrink(z, sz), sx, sz})

def edge_advance(continuation: Continuation, clear: Bool) -> Result<&2, &2, Error, EdgeProgress>:
  match continuation:
    case AboveProbe{work}: advance_above(work, clear)
    case XProbe{work}: advance_x(work, clear)
    case ZProbe{work}: advance_z(work, clear)
    case BothProbe{work}: advance_both(work, clear)

def edge_answer_checked(progress: EdgeProgress, answer: Result<&2, &2, Error, Bool>) -> Result<&2, &2, Error, EdgeProgress>:
  match progress answer:
    case _ Fail{error}: Fail{error}
    case EdgeDone{movement} Done{clear}: Fail{UnexpectedAnswer{}}
    case EdgeQuery{box, continuation} Done{clear}: edge_advance(continuation, clear)

def shift(keys: PI.Buttons) -> Bool:
  PI.Buttons{f, b, l, r, j, h, s} = keys
  h

def above_probe(work: EdgeWork, box: G.AABB, drop: F.F64, fall: F.F64,
                active: Bool) -> Result<&2, &2, Error, EdgeProgress>:
  match active:
    case False{}: finish_work(work)
    case True{}: checked_query(fall_query(box, zero(), zero(), F.sub(drop, fall)), AboveProbe{work})

def above_ground_gate(+work: EdgeWork, box: G.AABB, +drop: F.F64,
                      +fall: F.F64, ground: Bool) -> Result<&2, &2, Error, EdgeProgress>:
  match ground:
    case True{}: x_probe(work)
    case False{}: above_probe(work, box, drop, fall, F.is_lt(fall, drop))

def make_work(box: G.AABB, maximum: F.F64, +x: F.F64, y: F.F64, +z: F.F64) -> EdgeWork:
  EdgeWork{box, maximum, x, y, z, signed_step(x), signed_step(z)}

def above_ground(body: M.Body, requested: M.Vec3, context: EdgeContext) -> Result<&2, &2, Error, EdgeProgress>:
  M.Body{position, +box, velocity, width, height, ground, horizontal, vertical, below} = body
  M.Vec3{+x, y, +z} = requested
  EdgeContext{maximum, +fall, flying, keys, mover, mode} = context
  +drop = F.from_f32(maximum)
  +work = make_work(box, drop, x, y, z)
  above_ground_gate(work, box, drop, fall, ground)

def edge_begin_active(body: M.Body, requested: M.Vec3, context: EdgeContext,
                      active: Bool) -> Result<&2, &2, Error, EdgeProgress>:
  match active:
    case False{}: Done{EdgeDone{requested}}
    case True{}: above_ground(body, requested, context)

def edge_begin(body: M.Body, +requested: M.Vec3, +context: EdgeContext) -> Result<&2, &2, Error, EdgeProgress>:
  M.Vec3{x, +y, z} = requested
  EdgeContext{maximum, fall, +flying, +keys, mover, mode} = context
  edge_begin_active(body, requested, context, Bool.not(flying) && Bool.not(F.is_gt(y, zero())) && shift(keys))

def bool_error(bad: Bool, error: Error) -> Maybe<&2, Error>:
  match bad:
    case False{}: None{}
    case True{}: Some{error}

def mover_error(mover: Mover) -> Maybe<&2, Error>:
  match mover:
    case OtherMover{}: Some{UnsupportedMover{}}
    case _: None{}

def edge_error(+body: M.Body, requested: M.Vec3, context: EdgeContext) -> Maybe<&2, Error>:
  M.Body{position, +box, velocity, width, height, grounded, horizontal, vertical, below} = body
  EdgeContext{+maximum, +fall, flying, keys, mover, mode} = context
  +step = F.from_f32(maximum)
  first_error(mode_error(mode), first_error(mover_error(mover),
    first_error(body_error(M.Body.invalid(body)),
    first_error(body_error(M.bounds_error(0, 0, box)), first_error(input_error(M.Vec3.invalid_field(requested)),
    first_error(bool_error(Bool.not(F.is_finite(step) && F.is_ge(step, zero())), InvalidStep{}),
      bool_error(Bool.not(F.is_finite(fall)), InvalidFallDistance{})))))))

def edge_begin_gate(body: M.Body, requested: M.Vec3, context: EdgeContext, error: Maybe<&2, Error>) -> Result<&2, &2, Error, EdgeProgress>:
  match error:
    case Some{error}: Fail{error}
    case None{}: edge_begin(body, requested, context)

def edge_begin_checked(+body: M.Body, +requested: M.Vec3, +context: EdgeContext) -> Result<&2, &2, Error, EdgeProgress>:
  edge_begin_gate(body, requested, context, edge_error(body, requested, context))

def same_box(first: G.AABB, second: G.AABB) -> Bool:
  G.AABB{a, b, c, d, e, f} = first
  G.AABB{g, h, i, j, k, l} = second
  M.same_bits(a, g) && M.same_bits(b, h) && M.same_bits(c, i) &&
    M.same_bits(d, j) && M.same_bits(e, k) && M.same_bits(f, l)

# Fuel counts actual noCollision observations, including the above-ground
# history probe. A caller can instead drive EdgeQuery/edge_answer_checked
# directly with its sole owned world and reject unsupported reads there.
def replay_answer_valid(continuation: Continuation, answer: Result<&2, &2, Error, Bool>) -> Result<&2, &2, Error, EdgeProgress>:
  match answer:
    case Fail{error}: Fail{error}
    case Done{clear}: edge_advance(continuation, clear)

def replay_answer(continuation: Continuation, answer: Result<&2, &2, Error, Bool>,
                  matches: Bool) -> Result<&2, &2, Error, EdgeProgress>:
  match matches:
    case False{}: Fail{MismatchedQuery{}}
    case True{}: replay_answer_valid(continuation, answer)

def edge_replay(fuel: Nat, count: Nat, observations: List<&2, QueryObservation>,
                result: Result<&2, &2, Error, EdgeProgress>) -> Result<&2, &2, Error, BackoffObservation>:
  match fuel observations result:
    case _ _ Fail{error}: Fail{error}
    case _ Nil{} Done{EdgeDone{movement}}: Done{BackoffObservation{movement, count}}
    case _ _ Done{EdgeDone{movement}}: Fail{ExtraObservations{}}
    case 0n _ Done{EdgeQuery{box, continuation}}: Fail{QueryBudget{}}
    case 1n+rest Nil{} Done{EdgeQuery{box, continuation}}: Fail{MissingObservation{}}
    case 1n+rest QueryObservation{observed_box, answer} <> tail Done{EdgeQuery{box, continuation}}:
      edge_replay(rest, 1n+count, tail, replay_answer(continuation, answer, same_box(box, observed_box)))

def backoff_checked(-Owner: Type, owner: Owner, fuel: Nat,
                    observations: List<&2, QueryObservation>, body: M.Body,
                    requested: M.Vec3, context: EdgeContext) -> Owner & Result<&2, &2, Error, BackoffObservation>:
  (owner, edge_replay(fuel, 0n, observations, edge_begin_checked(body, requested, context)))

law rejected_minor_retains_tables:
  for tables: L.Tables
  for input: MinorInput
  for resolved: M.Vec3
  for +error: Error
  {minor_gate(tables, input, resolved, Some{error}) == (tables, Fail{error}) : L.Tables & Result<&2, &2, Error, MinorObservation>}

def rejected_minor_retains_tables(tables, input, resolved, error):
  {==}

law skipped_edge_retains_original_movement:
  for body: M.Body
  for +requested: M.Vec3
  for context: EdgeContext
  {edge_begin_active(body, requested, context, False{}) == Done{EdgeDone{requested}} : Result<&2, &2, Error, EdgeProgress>}

def skipped_edge_retains_original_movement(body, requested, context):
  {==}

law zero_budget_does_not_consume_observations:
  for count: Nat
  for observations: List<&2, QueryObservation>
  for box: G.AABB
  for continuation: Continuation
  {edge_replay(0n, count, observations, Done{EdgeQuery{box, continuation}}) == Fail{QueryBudget{}} : Result<&2, &2, Error, BackoffObservation>}

def zero_budget_does_not_consume_observations(count, observations, box, continuation):
  match observations:
    case Nil{}: {==}
    case observation <> rest: {==}

law mismatched_query_does_not_advance:
  for continuation: Continuation
  for answer: Result<&2, &2, Error, Bool>
  {replay_answer(continuation, answer, False{}) == Fail{MismatchedQuery{}} : Result<&2, &2, Error, EdgeProgress>}

def mismatched_query_does_not_advance(continuation, answer):
  {==}

law signed_zero_horizontal_movement_does_not_query:
  for box: G.AABB
  for maximum: F.F64
  for +y: F.F64
  for sx: F.F64
  for sz: F.F64
  {x_probe(EdgeWork{box, maximum, F.F64{2147483648, 0}, y, F.F64{2147483648, 0}, sx, sz}) ==
    Done{EdgeDone{M.Vec3{F.F64{2147483648, 0}, y, F.F64{2147483648, 0}}}} : Result<&2, &2, Error, EdgeProgress>}

def signed_zero_horizontal_movement_does_not_query(box, maximum, y, sx, sz):
  {==}
