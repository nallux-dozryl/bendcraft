import Base
import ./local_collision.bend as L
import ./client_world.bend as W
import ./movement.bend as M
import ./geometry.bend as A
import ./f64.bend as F
import ./core.bend as C
import ./game.bend as G
import ./registry.bend as B

# These are explicit caller admission declarations, not inferred world facts.
type EntityPolicy is Data:
  KnownEmptyEntityCollisions{}
  UnresolvedEntityCollisions{}

type BorderPolicy is Data:
  KnownClearBorderInterior{box: A.AABB}
  UnresolvedWorldBorder{}

type Environment is Data:
  Environment{entities: EntityPolicy, border: BorderPolicy}

type Error is Data:
  BodyMismatch{}
  MissingPalette{}
  StalePalette{}
  PaletteError{reason: String}
  UnknownEntities{}
  UnknownBorder{}
  InvalidInterior{}
  OutsideInterior{}
  WorldError{reason: String}
  HookError{cause: L.Error}
  QueryBudget{}

type Read is Data:
  Read{position: C.Position, state: U32}

type QueryRecord is Data:
  QueryRecord{box: A.AABB, clear: Bool, yielded: Maybe<&2, A.AABB>,
              reads: List<&2, Read>}

type Observation is Data:
  Observation{corrected: M.Vec3, queries: List<&2, QueryRecord>}

# Recursive boxes prevent flattening Body/context/view into native continuations.
# Production callers construct empty tails; tails carry no gameplay meaning.
type Request is Data:
  Request{body: M.Body, requested: M.Vec3, context: L.EdgeContext,
          environment: Environment, fuel: Nat, tail: List<&2, Request>}

type Frame is Data:
  Frame{view: W.View, environment: Environment,
        reversed: List<&2, QueryRecord>, tail: List<&2, Frame>}

type Scan is Data:
  Scan{box: A.AABB, bounds: W.Bounds, palette: W.Palette,
       tail: List<&2, Scan>}

type ScanStep is Data:
  ScanNext{reversed: List<&2, Read>}
  ScanHit{box: A.AABB, reversed: List<&2, Read>}

def error_text(error: Error) -> String:
  match error:
    case BodyMismatch{}: "edge-body-mismatch"
    case MissingPalette{}: "edge-palette-unavailable"
    case StalePalette{}: "edge-palette-stale"
    case PaletteError{reason}: "edge-palette: " ++ reason
    case UnknownEntities{}: "edge-entities-unresolved"
    case UnknownBorder{}: "edge-border-unresolved"
    case InvalidInterior{}: "edge-invalid-interior"
    case OutsideInterior{}: "edge-query-outside-interior"
    case WorldError{reason}: reason
    case HookError{cause}: "edge-hook-rejected"
    case QueryBudget{}: "edge-query-budget"

def bool_bits(a: Bool, b: Bool) -> Bool:
  U32.is_eq(Bool.to_u32(a), Bool.to_u32(b))

def vector_bits(a: M.Vec3, b: M.Vec3) -> Bool:
  match a b:
    case M.Vec3{ax, ay, az} M.Vec3{bx, by, bz}:
      M.same_bits(ax, bx) && M.same_bits(ay, by) && M.same_bits(az, bz)

def same_body(a: M.Body, b: M.Body) -> Bool:
  match a b:
    case M.Body{ap, ab, av, aw, ah, ag, ax, ay, az} M.Body{bp, bb, bv, bw, bh, bg, bx, by, bz}:
      vector_bits(ap, bp) && L.same_box(ab, bb) && vector_bits(av, bv) &&
        U32.is_eq(F32.bits(aw), F32.bits(bw)) && U32.is_eq(F32.bits(ah), F32.bits(bh)) &&
        bool_bits(ag, bg) && bool_bits(ax, bx) && bool_bits(ay, by) && bool_bits(az, bz)

def view_body(view: W.View) -> M.Body:
  W.View{body, yaw, pitch, palette, region, cache} = view
  body

def view_palette(view: W.View) -> Maybe<&2, W.Palette>:
  W.View{body, yaw, pitch, palette, region, cache} = view
  palette

def request_body(request: Request) -> M.Body:
  Request{body, requested, context, environment, fuel, tail} = request
  body

def frame_view(frame: Frame) -> W.View:
  Frame{view, environment, reversed, tail} = frame
  view

def environment_error(environment: Environment) -> Maybe<&2, Error>:
  match environment:
    case Environment{UnresolvedEntityCollisions{}, border}: Some{UnknownEntities{}}
    case Environment{KnownEmptyEntityCollisions{}, UnresolvedWorldBorder{}}: Some{UnknownBorder{}}
    case Environment{KnownEmptyEntityCollisions{}, KnownClearBorderInterior{+box}}:
      W.choose(Maybe<&2, Error>, None{}, Some{InvalidInterior{}},
        Maybe.is_none(&2, U32, A.AABB.invalid_field(box)) && W.query_ordered(box))

def contained(query: A.AABB, interior: A.AABB) -> Bool:
  match query interior:
    case A.AABB{a, b, c, d, e, f} A.AABB{x, y, z, u, v, w}:
      F.is_ge(a, x) && F.is_ge(b, y) && F.is_ge(c, z) &&
        F.is_le(d, u) && F.is_le(e, v) && F.is_le(f, w)

def query_admitted(query: A.AABB, environment: Environment) -> Bool:
  match environment:
    case Environment{KnownEmptyEntityCollisions{}, KnownClearBorderInterior{interior}}:
      contained(query, interior)
    case _: False{}

def scan_box(scan: Scan) -> A.AABB:
  Scan{box, bounds, palette, tail} = scan
  box

def scan_bounds(scan: Scan) -> W.Bounds:
  Scan{box, bounds, palette, tail} = scan
  bounds

def scan_palette(scan: Scan) -> W.Palette:
  Scan{box, bounds, palette, tail} = scan
  palette

def scan_material(scan: Scan, +point: W.Cell, +state: U32,
                  reversed: List<&2, Read>, result: Result<&2, &2, String, Maybe<&2, U32>>) -> Result<&2, &2, Error, ScanStep>:
  match result:
    case Fail{error}: Fail{WorldError{error}}
    case Done{None{}}: Done{ScanNext{Read{W.position(point), state} <> reversed}}
    case Done{Some{material}}:
      +next : List<&2, Read> = Read{W.position(point), state} <> reversed
      +cube = W.full_cube(point)
      W.choose(Result<&2, &2, Error, ScanStep>, Done{ScanHit{cube, next}}, Done{ScanNext{next}},
        U32.is_eq(W.boundary(point), 0) && A.AABB.intersects(scan_box(scan), cube))

def scan_read(+scan: Scan, point: W.Cell, reversed: List<&2, Read>,
              result: C.World & Result<&2, &2, C.Error, U32>) -> C.World & Result<&2, &2, Error, ScanStep>:
  (world, status) = result
  match status:
    case Fail{error}: (world, Fail{WorldError{W.error_text(error)}})
    case Done{+state}: (world, scan_material(scan, point, state, reversed, W.material(scan_palette(scan), state)))

def scan_cell(world: C.World, +scan: Scan, +point: W.Cell,
              reversed: List<&2, Read>, corner: Bool) -> C.World & Result<&2, &2, Error, ScanStep>:
  match corner:
    case True{}: (world, Done{ScanNext{reversed}})
    case False{}: scan_read(scan, point, reversed, C.read_block(world, W.position(point)))

def scan_loop(fuel: Nat, +index: U32, +scan: Scan, world: C.World,
              step: Result<&2, &2, Error, ScanStep>) -> C.World & Result<&2, &2, Error, QueryRecord>:
  match fuel step:
    case _ Fail{error}: (world, Fail{error})
    case _ Done{ScanHit{cube, reversed}}:
      (world, Done{QueryRecord{scan_box(scan), False{}, Some{cube}, List.reverse(&2, Read, reversed)}})
    case 0n Done{ScanNext{reversed}}:
      (world, Done{QueryRecord{scan_box(scan), True{}, None{}, List.reverse(&2, Read, reversed)}})
    case 1n+rest Done{ScanNext{reversed}}:
      +point = W.cell(scan_bounds(scan), index)
      W.paired(C.World, Result<&2, &2, Error, ScanStep>, C.World & Result<&2, &2, Error, QueryRecord>,
        scan_cell(world, scan, point, reversed, U32.is_eq(W.boundary(point), 3)),
        next => status => scan_loop(rest, U32.inc(index), scan, next, status))

def scan_checked(world: C.World, palette: W.Palette, +box: A.AABB,
                 bounds: Result<&2, &2, String, W.Bounds>) -> C.World & Result<&2, &2, Error, QueryRecord>:
  match bounds:
    case Fail{error}: (world, Fail{WorldError{error}})
    case Done{+actual}:
      scan_loop(U32.to_nat(W.volume(actual)), 0, Scan{box, actual, palette, []}, world, Done{ScanNext{[]}})

def query_gate(admitted: Bool, world: C.World, palette: W.Palette, +box: A.AABB) -> C.World & Result<&2, &2, Error, QueryRecord>:
  match admitted:
    case False{}: (world, Fail{OutsideInterior{}})
    case True{}: scan_checked(world, palette, box, W.query_bounds(box))

def query(world: C.World, palette: W.Palette, +box: A.AABB, environment: Environment) -> C.World & Result<&2, &2, Error, QueryRecord>:
  query_gate(query_admitted(box, environment), world, palette, box)

def progress_error(result: Result<&2, &2, L.Error, L.EdgeProgress>) -> Result<&2, &2, Error, L.EdgeProgress>:
  match result:
    case Fail{error}: Fail{HookError{error}}
    case Done{progress}: Done{progress}

def record_clear(record: QueryRecord) -> Bool:
  QueryRecord{box, clear, yielded, reads} = record
  clear

def appended(frame: Frame, record: QueryRecord) -> Frame:
  Frame{view, environment, reversed, tail} = frame
  Frame{view, environment, record <> reversed, []}

def edge_query_finished(frame: Frame, progress: L.EdgeProgress,
                        result: C.World & Result<&2, &2, Error, QueryRecord>) -> C.World & Frame & Result<&2, &2, Error, L.EdgeProgress>:
  match result:
    case (world, Fail{error}): (world, frame, Fail{error})
    case (world, Done{+record}):
      (world, appended(frame, record), progress_error(L.edge_answer_checked(progress, Done{record_clear(record)})))

def edge_loop(fuel: Nat, +palette: W.Palette, frame: Frame, world: C.World,
              progress: Result<&2, &2, Error, L.EdgeProgress>) -> C.World & Result<&2, &2, Error, Observation>:
  match fuel frame progress:
    case _ _ Fail{error}: (world, Fail{error})
    case _ Frame{view, environment, reversed, tail} Done{L.EdgeDone{movement}}:
      (world, Done{Observation{movement, List.reverse(&2, QueryRecord, reversed)}})
    case 0n _ Done{L.EdgeQuery{box, continuation}}: (world, Fail{QueryBudget{}})
    case 1n+rest Frame{view, +environment, reversed, tail} Done{L.EdgeQuery{+box, continuation}}:
      W.paired(C.World, Frame & Result<&2, &2, Error, L.EdgeProgress>, C.World & Result<&2, &2, Error, Observation>,
        edge_query_finished(Frame{view, environment, reversed, []}, L.EdgeQuery{box, continuation}, query(world, palette, box, environment)),
        next => updated => W.paired(Frame, Result<&2, &2, Error, L.EdgeProgress>, C.World & Result<&2, &2, Error, Observation>,
          updated, frame => progress => edge_loop(rest, palette, frame, next, progress)))

def packed(-T: Data, registry: B.Registry, frame: Frame,
            result: C.World & Result<&2, &2, Error, T>) -> W.State & Result<&2, &2, Error, T>:
  (world, status) = result
  (W.attach(G.Engine{world, registry}, frame_view(frame)), status)

def palette_error(expected: Maybe<&2, W.Palette>, actual: W.Palette) -> Maybe<&2, Error>:
  match expected:
    case None{}: Some{MissingPalette{}}
    case Some{prior}: W.choose(Maybe<&2, Error>, None{}, Some{StalePalette{}}, W.same_palette(prior, actual))

def palette_result(result: B.Registry & Result<&2, &2, String, W.Palette>) -> B.Registry & Result<&2, &2, Error, W.Palette>:
  (registry, status) = result
  match status:
    case Fail{error}: (registry, Fail{PaletteError{error}})
    case Done{palette}: (registry, Done{palette})

def current_palette(registry: B.Registry) -> B.Registry & Result<&2, &2, Error, W.Palette>:
  palette_result(W.palette_air(W.supported_block(B.Registry.block(registry, "minecraft:air"))))

def palette_gate(error: Maybe<&2, Error>, world: C.World, registry: B.Registry,
                  +frame: Frame, request: Request, palette: W.Palette) -> W.State & Result<&2, &2, Error, Observation>:
  match error:
    case Some{cause}: (W.attach(G.Engine{world, registry}, frame_view(frame)), Fail{cause})
    case None{}:
      Request{body, requested, context, environment, fuel, tail} = request
      packed(Observation, registry, frame,
        edge_loop(fuel, palette, frame, world, progress_error(L.edge_begin_checked(body, requested, context))))

def palette_read(world: C.World, +frame: Frame, request: Request,
                 result: B.Registry & Result<&2, &2, Error, W.Palette>) -> W.State & Result<&2, &2, Error, Observation>:
  (registry, status) = result
  match status:
    case Fail{error}: (W.attach(G.Engine{world, registry}, frame_view(frame)), Fail{error})
    case Done{+palette}:
      palette_gate(palette_error(view_palette(frame_view(frame)), palette), world, registry, frame, request, palette)

def environment_gate(error: Maybe<&2, Error>, engine: G.Engine, +frame: Frame,
                     request: Request) -> W.State & Result<&2, &2, Error, Observation>:
  match error:
    case Some{cause}: (W.attach(engine, frame_view(frame)), Fail{cause})
    case None{}:
      G.Engine{world, registry} = engine
      palette_read(world, frame, request, current_palette(registry))

def authority_gate(equal: Bool, engine: G.Engine, +view: W.View,
                   +request: Request) -> W.State & Result<&2, &2, Error, Observation>:
  match equal:
    case False{}: (W.attach(engine, view), Fail{BodyMismatch{}})
    case True{}:
      Request{body, requested, context, +environment, fuel, tail} = request
      environment_gate(environment_error(environment), engine, Frame{view, environment, [], []}, request)

def extracted(+request: Request, result: G.Engine & W.View) -> W.State & Result<&2, &2, Error, Observation>:
  (engine, +view) = result
  authority_gate(same_body(view_body(view), request_body(request)), engine, view, request)

def backoff_checked(world: W.State, request: Request) -> W.State & Result<&2, &2, Error, Observation>:
  extracted(request, W.take(world))

law body_mismatch_retains_complete_world:
  for engine: G.Engine
  for +view: W.View
  for request: Request
  {authority_gate(False{}, engine, view, request) == (W.attach(engine, view), Fail{BodyMismatch{}}) : W.State & Result<&2, &2, Error, Observation>}

def body_mismatch_retains_complete_world(engine, view, request):
  {==}

law query_outside_admission_retains_core:
  for world: C.World
  for palette: W.Palette
  for box: A.AABB
  {query_gate(False{}, world, palette, box) == (world, Fail{OutsideInterior{}}) : C.World & Result<&2, &2, Error, QueryRecord>}

def query_outside_admission_retains_core(world, palette, box):
  {==}

law cursor_corner_skips_core_read:
  for world: C.World
  for scan: Scan
  for point: W.Cell
  for reversed: List<&2, Read>
  {scan_cell(world, scan, point, reversed, True{}) == (world, Done{ScanNext{reversed}}) : C.World & Result<&2, &2, Error, ScanStep>}

def cursor_corner_skips_core_read(world, scan, point, reversed):
  {==}

law unresolved_environment_retains_complete_world:
  for cause: Error
  for engine: G.Engine
  for +frame: Frame
  for request: Request
  {environment_gate(Some{cause}, engine, frame, request) == (W.attach(engine, frame_view(frame)), Fail{cause}) : W.State & Result<&2, &2, Error, Observation>}

def unresolved_environment_retains_complete_world(cause, engine, frame, request):
  {==}

law zero_query_budget_retains_core:
  for palette: W.Palette
  for frame: Frame
  for world: C.World
  for box: A.AABB
  for continuation: L.Continuation
  {edge_loop(0n, palette, frame, world, Done{L.EdgeQuery{box, continuation}}) == (world, Fail{QueryBudget{}}) : C.World & Result<&2, &2, Error, Observation>}

def zero_query_budget_retains_core(palette, frame, world, box, continuation):
  match frame:
    case Frame{view, environment, reversed, tail}: {==}
