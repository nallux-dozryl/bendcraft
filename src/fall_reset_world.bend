import Base
import ./client_world.bend as W
import ./local_collision_world.bend as E
import ./movement.bend as M
import ./geometry.bend as A
import ./f64.bend as F
import ./core.bend as C
import ./game.bend as G
import ./registry.bend as B
import ./player_fall_history.bend as H

# This conditional profile is the pinned default block/fluid tag semantics.
# Runtime data-pack tag resolution and other dimensions are outside this module.
type Profile is Data:
  DefaultClientOverworldFourState{}
  UnresolvedTags{}

type Request is Data:
  Request{from: M.Vec3, to: M.Vec3, interior: A.AABB, work: Nat,
          profile: Profile, tail: List<&2, Request>}

type Phase is Data:
  BlockSample{}
  FluidSource{}

# FluidSource is the second checked block read used by actual getFluidState.
# Each admitted state has observed empty fluid and empty selected reset shapes.
type Read is Data:
  Read{position: C.Position, phase: Phase, state: U32}

type Observation is Data:
  Observation{clip: H.Clip, from: M.Vec3, to: M.Vec3,
              expanded_from: M.Vec3, expanded_to: M.Vec3,
              reads: List<&2, Read>, tail: List<&2, Observation>}

type Error is Data:
  NonCanonicalRequest{}
  UnresolvedProfile{}
  InvalidEndpoint{field: U32}
  InvalidInterior{}
  ExpandedCoordinateRange{}
  CursorCoordinateRange{}
  OutsideInterior{}
  WorkBudget{}
  PaletteError{cause: E.Error}
  WorldError{reason: String}

type Axis is Data:
  Axis{cell: U32, step: U32, delta: F.F64, next: F.F64,
       tail: List<&2, Axis>}

type Axes is Data:
  Axes{x: Axis, y: Axis, z: Axis, tail: List<&2, Axes>}

# Recursive boxes limit native continuation capture width. All internal tails
# are created empty; checked external Request tails must be empty.
type Trace is Data:
  Trace{request: Request, expanded_from: M.Vec3, expanded_to: M.Vec3,
        axes: Axes, palette: W.Palette, reversed: List<&2, Read>,
        tail: List<&2, Trace>}

type CellResult is Data:
  CellResult{block: U32, fluid_source: U32}

type Progress is Data:
  NeedCell{trace: Trace}
  Complete{observation: Observation}

def error_text(error: Error) -> String:
  match error:
    case NonCanonicalRequest{}: "fall-reset-noncanonical-request"
    case UnresolvedProfile{}: "fall-reset-tags-unresolved"
    case InvalidEndpoint{field}: "fall-reset-invalid-endpoint:" ++ U32.show(field)
    case InvalidInterior{}: "fall-reset-invalid-interior"
    case ExpandedCoordinateRange{}: "fall-reset-expanded-coordinate-range"
    case CursorCoordinateRange{}: "fall-reset-cursor-coordinate-range"
    case OutsideInterior{}: "fall-reset-outside-interior"
    case WorkBudget{}: "fall-reset-work-budget"
    case PaletteError{cause}: "fall-reset:" ++ E.error_text(cause)
    case WorldError{reason}: reason

def request_from(request: Request) -> M.Vec3:
  Request{from, to, interior, work, profile, tail} = request
  from

def request_to(request: Request) -> M.Vec3:
  Request{from, to, interior, work, profile, tail} = request
  to

def request_work(request: Request) -> Nat:
  Request{from, to, interior, work, profile, tail} = request
  work

def observation_clip(observation: Observation) -> H.Clip:
  Observation{clip, from, to, expanded_from, expanded_to, reads, tail} = observation
  clip

# Pinned Mth.lerp(double) is start + amount * (end - start), three rounded ops.
def expanded_axis(+start: F.F64, end: F.F64) -> F.F64:
  F.add(start, F.mul(F.F64{3195721714, 2596056904}, F.sub(end, start)))

def expanded(start: M.Vec3, end: M.Vec3) -> M.Vec3:
  match start end:
    case M.Vec3{x, y, z} M.Vec3{a, b, c}:
      M.Vec3{expanded_axis(x, a), expanded_axis(y, b), expanded_axis(z, c)}

# Finite Vec3.equals uses Double.compare, distinguishing the two signed zeros.
def equal_endpoints(a: M.Vec3, b: M.Vec3) -> Bool:
  E.vector_bits(a, b)

def endpoint_error(value: M.Vec3, +offset: U32) -> Maybe<&2, Error>:
  match value:
    case M.Vec3{x, y, z}:
      W.choose(Maybe<&2, Error>,
        W.choose(Maybe<&2, Error>,
          W.choose(Maybe<&2, Error>, None{}, Some{InvalidEndpoint{U32.add(offset, 2)}}, F.is_finite(z)),
          Some{InvalidEndpoint{U32.add(offset, 1)}}, F.is_finite(y)),
        Some{InvalidEndpoint{offset}}, F.is_finite(x))

def safe_coordinate(+value: F.F64) -> Bool:
  F.is_ge(value, F.F64{3252682751, 1577058304}) &&
    F.is_le(value, F.F64{1105199103, 1577058304})

def safe_vector(value: M.Vec3) -> Bool:
  M.Vec3{x, y, z} = value
  safe_coordinate(x) && safe_coordinate(y) && safe_coordinate(z)

def profile_error(profile: Profile) -> Maybe<&2, Error>:
  match profile:
    case DefaultClientOverworldFourState{}: None{}
    case UnresolvedTags{}: Some{UnresolvedProfile{}}

def later_error(prior: Maybe<&2, Error>, next: Maybe<&2, Error>) -> Maybe<&2, Error>:
  match prior:
    case Some{error}: Some{error}
    case None{}: next

def request_error(+request: Request) -> Maybe<&2, Error>:
  Request{+from, +to, +interior, work, profile, tail} = request
  later_error(profile_error(profile), later_error(endpoint_error(from, 0),
    later_error(endpoint_error(to, 3),
      W.choose(Maybe<&2, Error>,
        W.choose(Maybe<&2, Error>, None{}, Some{ExpandedCoordinateRange{}},
          safe_vector(expanded(from, to)) && safe_vector(expanded(to, from))),
        Some{InvalidInterior{}}, Maybe.is_none(&2, U32, A.AABB.invalid_field(interior)) && W.query_ordered(interior)))))

def axis_step(+movement: F.F64) -> U32:
  W.choose(U32, 0, W.choose(U32, 1, 4294967295, F.is_gt(movement, F.F64{0, 0})), F.is_zero(movement))

def axis_delta(+step: U32, movement: F.F64) -> F.F64:
  W.choose(F.F64, F.F64{2146435071, 4294967295}, F.div(F.from_i32(step), movement), U32.is_eq(step, 0))

def axis_next(start: F.F64, cell: U32, +step: U32, delta: F.F64) -> F.F64:
  +fraction = F.sub(start, F.from_i32(cell))
  F.mul(delta, W.choose(F.F64, F.sub(F.F64{1072693248, 0}, fraction), fraction, U32.is_eq(step, 1)))

# Within admitted safe i32 coordinates, Math.floor -> long -> double in frac
# equals the exact floor_i32 conversion followed by from_i32. No saturation case
# is admitted, and coordinate iadd wrapping is outside this bounded projection.
def axis_cell(start: F.F64, +movement: F.F64,
              result: Result<&2, &2, F.F64ConversionError, U32>) -> Result<&2, &2, Error, Axis>:
  match result:
    case Fail{cause}: Fail{ExpandedCoordinateRange{}}
    case Done{+cell}:
      +step = axis_step(movement)
      +delta = axis_delta(step, movement)
      Done{Axis{cell, step, delta, axis_next(start, cell, step, delta), []}}

def axis(+start: F.F64, end: F.F64) -> Result<&2, &2, Error, Axis>:
  axis_cell(start, F.sub(end, start), F.floor_i32(start))

def axes_z(x: Axis, y: Axis, result: Result<&2, &2, Error, Axis>) -> Result<&2, &2, Error, Axes>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{z}: Done{Axes{x, y, z, []}}

def axes_y(x: Axis, z_start: F.F64, z_end: F.F64,
           result: Result<&2, &2, Error, Axis>) -> Result<&2, &2, Error, Axes>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{y}: axes_z(x, y, axis(z_start, z_end))

def axes_x(y_start: F.F64, y_end: F.F64, z_start: F.F64, z_end: F.F64,
           result: Result<&2, &2, Error, Axis>) -> Result<&2, &2, Error, Axes>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{x}: axes_y(x, z_start, z_end, axis(y_start, y_end))

def axes(start: M.Vec3, end: M.Vec3) -> Result<&2, &2, Error, Axes>:
  match start end:
    case M.Vec3{x, y, z} M.Vec3{a, b, c}: axes_x(y, b, z, c, axis(x, a))

def axis_time(axis: Axis) -> F.F64:
  Axis{cell, step, delta, next, tail} = axis
  next

def axis_advance(axis: Axis) -> Axis:
  Axis{cell, +step, +delta, next, tail} = axis
  Axis{U32.add(cell, step), step, delta, F.add(next, delta), []}

def axes_active(axes: Axes) -> Bool:
  Axes{x, y, z, tail} = axes
  F.is_le(axis_time(x), F.F64{1072693248, 0}) ||
    F.is_le(axis_time(y), F.F64{1072693248, 0}) ||
    F.is_le(axis_time(z), F.F64{1072693248, 0})

# Strict comparisons implement the actual one-axis-at-a-time Z/Y/X tie order.
def axes_advance(axes: Axes) -> Axes:
  Axes{+x, +y, +z, tail} = axes
  W.choose(Axes,
    W.choose(Axes, Axes{axis_advance(x), y, z, []}, Axes{x, y, axis_advance(z), []}, F.is_lt(axis_time(x), axis_time(z))),
    W.choose(Axes, Axes{x, axis_advance(y), z, []}, Axes{x, y, axis_advance(z), []}, F.is_lt(axis_time(y), axis_time(z))),
    F.is_lt(axis_time(x), axis_time(y)))

def axes_position(axes: Axes) -> C.Position:
  Axes{Axis{x, xs, xd, xt, xa}, Axis{y, ys, yd, yt, ya}, Axis{z, zs, zd, zt, za}, tail} = axes
  C.Position{"minecraft:overworld", x, y, z}

def trace_position(trace: Trace) -> C.Position:
  Trace{request, from, to, axes, palette, reversed, tail} = trace
  axes_position(axes)

def position_safe(position: C.Position) -> Bool:
  C.Position{dimension, x, y, z} = position
  safe_coordinate(F.from_i32(x)) && safe_coordinate(F.from_i32(y)) && safe_coordinate(F.from_i32(z))

def trace_palette(trace: Trace) -> W.Palette:
  Trace{request, from, to, axes, palette, reversed, tail} = trace
  palette

def position_inside(interior: A.AABB, position: C.Position) -> Bool:
  C.Position{dimension, x, y, z} = position
  E.contained(W.full_cube(W.Cell{x, y, z, 0}), interior)

def trace_inside(trace: Trace) -> Bool:
  Trace{Request{from, to, interior, work, profile, rt}, a, b, axes, palette, reversed, tail} = trace
  position_inside(interior, axes_position(axes))

def trace_recorded(trace: Trace, result: CellResult) -> Trace:
  Trace{request, from, to, +axes, palette, reversed, tail} = trace
  CellResult{block, fluid} = result
  +position = axes_position(axes)
  Trace{request, from, to, axes, palette,
    Read{position, FluidSource{}, fluid} <> Read{position, BlockSample{}, block} <> reversed, []}

def trace_advance(trace: Trace) -> Trace:
  Trace{request, from, to, axes, palette, reversed, tail} = trace
  Trace{request, from, to, axes_advance(axes), palette, reversed, []}

def trace_active(trace: Trace) -> Bool:
  Trace{request, from, to, axes, palette, reversed, tail} = trace
  axes_active(axes)

def trace_observation(trace: Trace) -> Observation:
  Trace{+request, from, to, axes, palette, reversed, tail} = trace
  Observation{H.Miss{}, request_from(request), request_to(request), from, to, List.reverse(&2, Read, reversed), []}

def material_checked(+state: U32, result: Result<&2, &2, String, Maybe<&2, U32>>) -> Result<&2, &2, Error, U32>:
  match result:
    case Fail{reason}: Fail{WorldError{reason}}
    case Done{material}: Done{state}

def read_checked(palette: W.Palette, result: C.World & Result<&2, &2, C.Error, U32>) -> C.World & Result<&2, &2, Error, U32>:
  (world, status) = result
  match status:
    case Fail{cause}: (world, Fail{WorldError{W.error_text(cause)}})
    case Done{+state}: (world, material_checked(state, W.material(palette, state)))

def fluid_status(world: C.World, block: U32, status: Result<&2, &2, Error, U32>) -> C.World & Result<&2, &2, Error, CellResult>:
  match status:
    case Fail{cause}: (world, Fail{cause})
    case Done{fluid}: (world, Done{CellResult{block, fluid}})

def fluid_read(palette: W.Palette, block: U32,
               result: C.World & Result<&2, &2, C.Error, U32>) -> C.World & Result<&2, &2, Error, CellResult>:
  W.paired(C.World, Result<&2, &2, Error, U32>, C.World & Result<&2, &2, Error, CellResult>,
    read_checked(palette, result), world => status => fluid_status(world, block, status))

def first_read(+trace: Trace, result: C.World & Result<&2, &2, Error, U32>) -> C.World & Result<&2, &2, Error, CellResult>:
  (world, status) = result
  match status:
    case Fail{cause}: (world, Fail{cause})
    case Done{block}: fluid_read(trace_palette(trace), block, C.read_block(world, trace_position(trace)))

def cell_read(world: C.World, +trace: Trace) -> C.World & Result<&2, &2, Error, CellResult>:
  first_read(trace, read_checked(trace_palette(trace), C.read_block(world, trace_position(trace))))

def progress_gate(active: Bool, trace: Trace) -> Result<&2, &2, Error, Progress>:
  match active:
    case False{}: Done{Complete{trace_observation(trace)}}
    case True{}: Done{NeedCell{trace_advance(trace)}}

def cell_progress(+trace: Trace, result: Result<&2, &2, Error, CellResult>) -> Result<&2, &2, Error, Progress>:
  match result:
    case Fail{cause}: Fail{cause}
    case Done{cell}:
      +recorded = trace_recorded(trace, cell)
      progress_gate(trace_active(recorded), recorded)

def scan_read_inside(inside: Bool, world: C.World, +trace: Trace) -> C.World & Result<&2, &2, Error, Progress>:
  match inside:
    case False{}: (world, Fail{OutsideInterior{}})
    case True{}:
      W.paired(C.World, Result<&2, &2, Error, CellResult>, C.World & Result<&2, &2, Error, Progress>,
        cell_read(world, trace), next => status => (next, cell_progress(trace, status)))

def scan_read_safe(safe: Bool, world: C.World, +trace: Trace) -> C.World & Result<&2, &2, Error, Progress>:
  match safe:
    case False{}: (world, Fail{CursorCoordinateRange{}})
    case True{}: scan_read_inside(trace_inside(trace), world, trace)

def scan_loop(work: Nat, world: C.World, progress: Result<&2, &2, Error, Progress>) -> C.World & Result<&2, &2, Error, Observation>:
  match work progress:
    case _ Fail{cause}: (world, Fail{cause})
    case _ Done{Complete{observation}}: (world, Done{observation})
    case 0n Done{NeedCell{trace}}: (world, Fail{WorkBudget{}})
    case 1n Done{NeedCell{trace}}: (world, Fail{WorkBudget{}})
    case 1n+1n+rest Done{NeedCell{+trace}}:
      W.paired(C.World, Result<&2, &2, Error, Progress>, C.World & Result<&2, &2, Error, Observation>,
        scan_read_safe(position_safe(trace_position(trace)), world, trace), next => status => scan_loop(rest, next, status))

def initial_axes(world: C.World, +request: Request, palette: W.Palette,
                 +from: M.Vec3, +to: M.Vec3,
                 result: Result<&2, &2, Error, Axes>) -> C.World & Result<&2, &2, Error, Observation>:
  match result:
    case Fail{cause}: (world, Fail{cause})
    case Done{axes}: scan_loop(request_work(request), world, Done{NeedCell{Trace{request, from, to, axes, palette, [], []}}})

def equal_expanded(equal: Bool, world: C.World, palette: W.Palette, +request: Request,
                   +from: M.Vec3, +to: M.Vec3) -> C.World & Result<&2, &2, Error, Observation>:
  match equal:
    case True{}: (world, Done{Observation{H.Miss{}, request_from(request), request_to(request), from, to, [], []}})
    case False{}: initial_axes(world, request, palette, from, to, axes(from, to))

def equal_gate(equal: Bool, world: C.World, palette: W.Palette, +request: Request) -> C.World & Result<&2, &2, Error, Observation>:
  equal_expanded(equal, world, palette, request,
    expanded(request_from(request), request_to(request)), expanded(request_to(request), request_from(request)))

def packed(registry: B.Registry, view: W.View,
           result: C.World & Result<&2, &2, Error, Observation>) -> W.State & Result<&2, &2, Error, Observation>:
  (world, status) = result
  (W.attach(G.Engine{world, registry}, view), status)

def palette_gate(error: Maybe<&2, E.Error>, world: C.World, registry: B.Registry,
                 view: W.View, +request: Request, palette: W.Palette) -> W.State & Result<&2, &2, Error, Observation>:
  match error:
    case Some{cause}: (W.attach(G.Engine{world, registry}, view), Fail{PaletteError{cause}})
    case None{}: packed(registry, view, equal_gate(equal_endpoints(request_from(request), request_to(request)), world, palette, request))

def palette_read(world: C.World, +view: W.View, request: Request,
                 result: B.Registry & Result<&2, &2, E.Error, W.Palette>) -> W.State & Result<&2, &2, Error, Observation>:
  (registry, status) = result
  match status:
    case Fail{cause}: (W.attach(G.Engine{world, registry}, view), Fail{PaletteError{cause}})
    case Done{+palette}: palette_gate(E.palette_error(E.view_palette(view), palette), world, registry, view, request, palette)

def admission_gate(error: Maybe<&2, Error>, engine: G.Engine, view: W.View,
                   request: Request) -> W.State & Result<&2, &2, Error, Observation>:
  match error:
    case Some{cause}: (W.attach(engine, view), Fail{cause})
    case None{}:
      G.Engine{world, registry} = engine
      palette_read(world, view, request, E.current_palette(registry))

def extracted(+request: Request, result: G.Engine & W.View) -> W.State & Result<&2, &2, Error, Observation>:
  (engine, view) = result
  admission_gate(request_error(request), engine, view, request)

def clip_checked(world: W.State, request: Request) -> W.State & Result<&2, &2, Error, Observation>:
  match request:
    case Request{from, to, interior, work, profile, Nil{}}:
      extracted(Request{from, to, interior, work, profile, []}, W.take(world))
    case _: (world, Fail{NonCanonicalRequest{}})

law rejected_admission_retains_complete_world:
  for cause: Error
  for engine: G.Engine
  for view: W.View
  for request: Request
  {admission_gate(Some{cause}, engine, view, request) == (W.attach(engine, view), Fail{cause}) : W.State & Result<&2, &2, Error, Observation>}

def rejected_admission_retains_complete_world(cause, engine, view, request):
  {==}

law outside_interior_reads_no_core:
  for world: C.World
  for trace: Trace
  {scan_read_inside(False{}, world, trace) == (world, Fail{OutsideInterior{}}) : C.World & Result<&2, &2, Error, Progress>}

def outside_interior_reads_no_core(world, trace):
  {==}

law insufficient_cell_budget_retains_core:
  for world: C.World
  for trace: Trace
  {scan_loop(1n, world, Done{NeedCell{trace}}) == (world, Fail{WorkBudget{}}) : C.World & Result<&2, &2, Error, Observation>}

def insufficient_cell_budget_retains_core(world, trace):
  {==}

law unsafe_cursor_reads_no_core:
  for world: C.World
  for trace: Trace
  {scan_read_safe(False{}, world, trace) == (world, Fail{CursorCoordinateRange{}}) : C.World & Result<&2, &2, Error, Progress>}

def unsafe_cursor_reads_no_core(world, trace):
  {==}

law equal_endpoints_read_no_core:
  for world: C.World
  for palette: W.Palette
  for +request: Request
  {equal_gate(True{}, world, palette, request) == (world, Done{Observation{H.Miss{}, request_from(request), request_to(request), expanded(request_from(request), request_to(request)), expanded(request_to(request), request_from(request)), [], []}}) : C.World & Result<&2, &2, Error, Observation>}

def equal_endpoints_read_no_core(world, palette, request):
  {==}

law noncanonical_request_retains_owner:
  for world: W.State
  for from: M.Vec3
  for to: M.Vec3
  for interior: A.AABB
  for work: Nat
  for profile: Profile
  for child: Request
  for tail: List<&2, Request>
  {clip_checked(world, Request{from, to, interior, work, profile, child <> tail}) == (world, Fail{NonCanonicalRequest{}}) : W.State & Result<&2, &2, Error, Observation>}

def noncanonical_request_retains_owner(world, from, to, interior, work, profile, child, tail):
  {==}
