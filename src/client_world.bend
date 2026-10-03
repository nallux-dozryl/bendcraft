import Base
import ./game.bend as G
import ./core.bend as C
import ./registry.bend as B
import ./live.bend as L
import ./json.bend as J
import ./f64.bend as F
import ./geometry.bend as A
import ./movement.bend as M
import ./client_render.bend as R
import ./section_map.bend as S
import ./schedule.bend as Q

# This finite scene is an integration instrument. It has no terrain generator,
# entity collisions, world border, player travel, or implicit unloaded air.
type Palette is Data:
  Palette{air: U32, stone: U32, dirt: U32, planks: U32}

type Bounds is Data:
  Bounds{x: U32, y: U32, z: U32, width: U32, height: U32, depth: U32}

type Cell is Data:
  Cell{x: U32, y: U32, z: U32, boundary: U32}

type RawBlock is Data:
  RawBlock{cell: Cell, state: U32, material: U32}

type SnapshotMode is Data:
  AbsoluteSnapshot{}
  RelativeSnapshot{}

type SnapshotCache is Data:
  SnapshotCache{revision: Nat, region: Bounds, palette: Palette, blocks: List<&2, RawBlock>}

type View is Data:
  View{body: M.Body, yaw: F32, pitch: F32,
    palette: Maybe<&2, Palette>, region: Bounds, cache: Maybe<&2, SnapshotCache>}

type State is Type:
  State{engine: G.Engine, body: M.Body, yaw: F32, pitch: F32,
    palette: Maybe<&2, Palette>, region: Bounds, cache: Maybe<&2, SnapshotCache>}

def choose(-T: Data, yes: T, no: T, value: Bool) -> T:
  match value:
    case True{}: yes
    case False{}: no

def paired(-A: Type, -B: Type, -T: Type, value: A & B, finish: A -> B -> T) -> T:
  match value:
    case (a, b): finish(a, b)

def error_text(error: C.Error) -> String:
  match error:
    case C.PermissionDenied{}: "permission-denied"
    case C.UnknownDimension{name}: "unknown-dimension:" ++ name
    case C.InvalidState{state}: "invalid-state:" ++ U32.show(state)
    case C.MissingSection{key}: "missing-section:" ++ key
    case C.SectionExists{key}: "section-exists:" ++ key
    case C.InvalidCoordinate{}: "invalid-coordinate"
    case C.PastTick{}: "past-tick"
    case C.TooManyPending{}: "too-many-pending"

def supported_block(result: B.Registry & Result<&2, &2, B.Error, B.Block>) -> B.Registry & Result<&2, &2, String, U32>:
  (registry, status) = result
  match status:
    case Fail{error}: (registry, Fail{B.error_text(error)})
    case Done{B.Block{protocol, name, first, count, default_id, properties}}:
      (registry, choose(Result<&2, &2, String, U32>, Done{default_id}, Fail{"unsupported-palette-domain:" ++ name}, U32.is_eq(count, 1) && List.is_empty(&2, B.Property, properties)))

def palette_planks(air: U32, stone: U32, dirt: U32, result: B.Registry & Result<&2, &2, String, U32>) -> B.Registry & Result<&2, &2, String, Palette>:
  (registry, status) = result
  match status:
    case Fail{error}: (registry, Fail{error})
    case Done{planks}: (registry, Done{Palette{air, stone, dirt, planks}})

def palette_dirt(air: U32, stone: U32, result: B.Registry & Result<&2, &2, String, U32>) -> B.Registry & Result<&2, &2, String, Palette>:
  (registry, status) = result
  match status:
    case Fail{error}: (registry, Fail{error})
    case Done{dirt}: palette_planks(air, stone, dirt, supported_block(B.Registry.block(registry, "minecraft:oak_planks")))

def palette_stone(air: U32, result: B.Registry & Result<&2, &2, String, U32>) -> B.Registry & Result<&2, &2, String, Palette>:
  (registry, status) = result
  match status:
    case Fail{error}: (registry, Fail{error})
    case Done{stone}: palette_dirt(air, stone, supported_block(B.Registry.block(registry, "minecraft:dirt")))

def palette_air(result: B.Registry & Result<&2, &2, String, U32>) -> B.Registry & Result<&2, &2, String, Palette>:
  (registry, status) = result
  match status:
    case Fail{error}: (registry, Fail{error})
    case Done{air}: palette_stone(air, supported_block(B.Registry.block(registry, "minecraft:stone")))

def default_region() -> Bounds:
  Bounds{4294967292, 4294967295, 4294967292, 8, 6, 8}

def instrument_body() -> M.Body:
  M.Body.new(M.Vec3{F.from_f32(0.5), F.from_u32(1), F.from_f32(F32.neg(2.5))}, 0.6, 1.8, M.Vec3.zero(), True{})

def new_result(world: C.World, result: B.Registry & Result<&2, &2, String, Palette>) -> State & Result<&2, &2, String, Unit>:
  (registry, status) = result
  match status:
    case Fail{error}: (State{G.Engine{world, registry}, instrument_body(), 0.0, 0.2, None{}, default_region(), None{}}, Fail{error})
    case Done{palette}: (State{G.Engine{world, registry}, instrument_body(), 0.0, 0.2, Some{palette}, default_region(), None{}}, Done{Unit{}})

def new(engine: G.Engine) -> State & Result<&2, &2, String, Unit>:
  G.Engine{world, registry} = engine
  new_result(world, palette_air(supported_block(B.Registry.block(registry, "minecraft:air"))))

def take(state: State) -> G.Engine & View:
  State{engine, body, yaw, pitch, palette, region, cache} = state
  (engine, View{body, yaw, pitch, palette, region, cache})

def attach(engine: G.Engine, view: View) -> State:
  View{body, yaw, pitch, palette, region, cache} = view
  State{engine, body, yaw, pitch, palette, region, cache}

law take_attach_preserves_owned_state:
  for engine: G.Engine
  for body: M.Body
  for yaw: F32
  for pitch: F32
  for palette: Maybe<&2, Palette>
  for region: Bounds
  for cache: Maybe<&2, SnapshotCache>
  {paired(G.Engine, View, State, take(State{engine, body, yaw, pitch, palette, region, cache}), engine => view => attach(engine, view)) == State{engine, body, yaw, pitch, palette, region, cache} : State}

def take_attach_preserves_owned_state(engine, body, yaw, pitch, palette, region, cache):
  {==}

def step(state: State) -> State:
  State{engine, body, yaw, pitch, palette, region, cache} = state
  State{G.realtime_step(engine), body, yaw, pitch, palette, region, cache}

def body(state: State) -> State & M.Body:
  State{engine, +body, yaw, pitch, palette, region, cache} = state
  (State{engine, body, yaw, pitch, palette, region, cache}, body)

def invalidate_cache(state: State) -> State:
  State{engine, body, yaw, pitch, palette, region, cache} = state
  State{engine, body, yaw, pitch, palette, region, None{}}

def dispatch_result(body: M.Body, yaw: F32, pitch: F32, palette: Maybe<&2, Palette>, region: Bounds, cache: Maybe<&2, SnapshotCache>, result: G.Engine & L.Session & J.Value) -> State & L.Session & J.Value:
  (engine, session, value) = result
  (State{engine, body, yaw, pitch, palette, region, cache}, session, value)

def dispatch(state: State, session: L.Session, token: String, request: J.Value) -> State & L.Session & J.Value:
  State{engine, body, yaw, pitch, palette, region, cache} = state
  dispatch_result(body, yaw, pitch, palette, region, cache, G.dispatch(engine, session, token, request))

def look_gate(valid: Bool, state: State, yaw: F32, pitch: F32) -> State & Result<&2, &2, String, Unit>:
  match valid:
    case False{}: (state, Fail{"invalid-camera-angles"})
    case True{}:
      State{engine, body, old_yaw, old_pitch, palette, region, cache} = state
      (State{engine, body, yaw, pitch, palette, region, cache}, Done{Unit{}})

def look(state: State, +yaw: F32, +pitch: F32) -> State & Result<&2, &2, String, Unit>:
  look_gate(F.is_finite(F.from_f32(yaw)) && F.is_finite(F.from_f32(pitch)) && F32.is_ge(pitch, F32.neg(1.5707963268)) && F32.is_le(pitch, 1.5707963268), state, yaw, pitch)

def volume(bounds: Bounds) -> U32:
  Bounds{x, y, z, width, height, depth} = bounds
  U32.mul(U32.mul(width, height), depth)

def axis_valid(origin: U32, +size: U32) -> Bool:
  F.is_le(F.add(F.from_i32(origin), F.from_u32(U32.sub(size, 1))), F.from_i32(2147483647))

def bounds_valid(bounds: Bounds) -> Bool:
  Bounds{+x, +y, +z, +w, +h, +d} = bounds
  U32.is_ge(w, 1) && U32.is_le(w, 16) && U32.is_ge(h, 1) && U32.is_le(h, 16) && U32.is_ge(d, 1) && U32.is_le(d, 16) && axis_valid(x, w) && axis_valid(y, h) && axis_valid(z, d)

def region_gate(valid: Bool, state: State, region: Bounds) -> State & Result<&2, &2, String, Unit>:
  match valid:
    case False{}: (state, Fail{"invalid-region-bounds"})
    case True{}:
      State{engine, body, yaw, pitch, palette, old, cache} = state
      (State{engine, body, yaw, pitch, palette, region, cache}, Done{Unit{}})

def set_region(state: State, +region: Bounds) -> State & Result<&2, &2, String, Unit>:
  region_gate(bounds_valid(region), state, region)

def edge(+index: U32, size: U32) -> U32:
  Bool.to_u32(U32.is_eq(index, 0) || U32.is_eq(U32.inc(index), size))

def cell(+bounds: Bounds, +index: U32) -> Cell:
  Bounds{x, y, z, +w, +h, d} = bounds
  +ix = U32.mod(index, w)
  +iy = U32.mod(U32.div(index, w), h)
  +iz = U32.div(U32.div(index, w), h)
  Cell{U32.add(x, ix), U32.add(y, iy), U32.add(z, iz), U32.add(U32.add(edge(ix, w), edge(iy, h)), edge(iz, d))}

def position(cell: Cell) -> C.Position:
  Cell{x, y, z, boundary} = cell
  C.Position{"minecraft:overworld", x, y, z}

def boundary(cell: Cell) -> U32:
  Cell{x, y, z, value} = cell
  value

def material(+palette: Palette, +state: U32) -> Result<&2, &2, String, Maybe<&2, U32>>:
  Palette{air, stone, dirt, planks} = palette
  choose(Result<&2, &2, String, Maybe<&2, U32>>, Done{None{}}, choose(Result<&2, &2, String, Maybe<&2, U32>>, Done{Some{0}}, choose(Result<&2, &2, String, Maybe<&2, U32>>, Done{Some{1}}, choose(Result<&2, &2, String, Maybe<&2, U32>>, Done{Some{2}}, Fail{"unsupported-block-state:" ++ U32.show(state)}, U32.is_eq(state, planks)), U32.is_eq(state, dirt)), U32.is_eq(state, stone)), U32.is_eq(state, air))

def render_block(cell: Cell, state: U32, material: U32) -> R.Block:
  Cell{x, y, z, boundary} = cell
  R.Block{F.to_f32(F.from_i32(x)), F.to_f32(F.from_i32(y)), F.to_f32(F.from_i32(z)), state, material}

def absolute_blocks(blocks: List<&2, RawBlock>) -> List<&2, R.Block>:
  match blocks:
    case Nil{}: []
    case RawBlock{cell, state, material} <> rest: render_block(cell, state, material) <> absolute_blocks(rest)

def eye_position(body: M.Body) -> M.Vec3:
  M.Body{M.Vec3{x, y, z}, box, velocity, width, height, ground, horizontal, vertical, below} = body
  M.Vec3{x, F.add(y, F.from_f32(1.62)), z}

def relative_block(raw: RawBlock, origin: M.Vec3) -> R.Block:
  match raw origin:
    case RawBlock{Cell{x, y, z, boundary}, state, material} M.Vec3{ox, oy, oz}:
      R.Block{F.to_f32(F.sub(F.from_i32(x), ox)), F.to_f32(F.sub(F.from_i32(y), oy)), F.to_f32(F.sub(F.from_i32(z), oz)), state, material}

def relative_blocks(blocks: List<&2, RawBlock>, +origin: M.Vec3) -> List<&2, R.Block>:
  match blocks:
    case Nil{}: []
    case raw <> rest: relative_block(raw, origin) <> relative_blocks(rest, origin)

def rendered_blocks(mode: SnapshotMode, blocks: List<&2, RawBlock>, body: M.Body) -> List<&2, R.Block>:
  match mode:
    case AbsoluteSnapshot{}: absolute_blocks(blocks)
    case RelativeSnapshot{}: relative_blocks(blocks, eye_position(body))

def sample_material(cell: Cell, state: U32, reversed: List<&2, RawBlock>, result: Result<&2, &2, String, Maybe<&2, U32>>) -> Result<&2, &2, String, List<&2, RawBlock>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{None{}}: Done{reversed}
    case Done{Some{material}}: Done{RawBlock{cell, state, material} <> reversed}

def sample_read(+palette: Palette, +cell: Cell, reversed: List<&2, RawBlock>, result: C.World & Result<&2, &2, C.Error, U32>) -> C.World & Result<&2, &2, String, List<&2, RawBlock>>:
  (world, status) = result
  match status:
    case Fail{error}: (world, Fail{error_text(error)})
    case Done{+state}: (world, sample_material(cell, state, reversed, material(palette, state)))

def sample(n: Nat, +index: U32, +bounds: Bounds, +palette: Palette, world: C.World, result: Result<&2, &2, String, List<&2, RawBlock>>) -> C.World & Result<&2, &2, String, List<&2, RawBlock>>:
  match n result:
    case _ Fail{error}: (world, Fail{error})
    case 0n Done{reversed}: (world, Done{List.reverse(&2, RawBlock, reversed)})
    case 1n+rest Done{reversed}:
      +point = cell(bounds, index)
      paired(C.World, Result<&2, &2, String, List<&2, RawBlock>>, C.World & Result<&2, &2, String, List<&2, RawBlock>>, sample_read(palette, point, reversed, C.read_block(world, position(point))), next => status => sample(rest, U32.inc(index), bounds, palette, next, status))

def camera(body: M.Body, yaw: F32, pitch: F32) -> R.Camera:
  M.Body{M.Vec3{x, y, z}, box, velocity, width, height, ground, horizontal, vertical, below} = body
  R.Camera{F.to_f32(x), F.to_f32(F.add(y, F.from_f32(1.62))), F.to_f32(z), yaw, pitch}

def rendered_camera(mode: SnapshotMode, body: M.Body, yaw: F32, pitch: F32) -> R.Camera:
  match mode:
    case AbsoluteSnapshot{}: camera(body, yaw, pitch)
    case RelativeSnapshot{}: R.Camera{0.0, 0.0, 0.0, yaw, pitch}

def body_box(body: M.Body) -> A.AABB:
  M.Body{position, box, velocity, width, height, ground, horizontal, vertical, below} = body
  box

def cache_value(palette: Maybe<&2, Palette>, revision: Nat, region: Bounds, blocks: List<&2, RawBlock>) -> Maybe<&2, SnapshotCache>:
  match palette:
    case None{}: None{}
    case Some{actual}: Some{SnapshotCache{revision, region, actual, blocks}}

def snapshot_status(status: Result<&2, &2, String, List<&2, RawBlock>>, state: State, tick: Nat, +revision: Nat, +mode: SnapshotMode) -> State & Result<&2, &2, String, R.Snapshot>:
  match status:
    case Fail{error}: (state, Fail{error})
    case Done{+blocks}:
      State{engine, +body, +yaw, +pitch, +palette, +region, old_cache} = state
      (State{engine, body, yaw, pitch, palette, region, cache_value(palette, revision, region, blocks)}, Done{R.Snapshot{tick, revision, rendered_blocks(mode, blocks, body), rendered_camera(mode, body, yaw, pitch)}})

def snapshot_result(registry: B.Registry, body: M.Body, yaw: F32, pitch: F32, palette: Maybe<&2, Palette>, region: Bounds, cache: Maybe<&2, SnapshotCache>, mode: SnapshotMode, result: C.World & Result<&2, &2, String, List<&2, RawBlock>>) -> State & Result<&2, &2, String, R.Snapshot>:
  (world, status) = result
  C.World{+tick, time, paused, daylight, +revision, count, sections, pending, events} = world
  state = {State{G.Engine{C.World{tick, time, paused, daylight, revision, count, sections, pending, events}, registry}, body, yaw, pitch, palette, region, cache} : State}
  snapshot_status(status, state, tick, revision, mode)

def same_region(a: Bounds, b: Bounds) -> Bool:
  match a b:
    case Bounds{x, y, z, w, h, d} Bounds{bx, by, bz, bw, bh, bd}: U32.is_eq(x, bx) && U32.is_eq(y, by) && U32.is_eq(z, bz) && U32.is_eq(w, bw) && U32.is_eq(h, bh) && U32.is_eq(d, bd)

def same_palette(a: Palette, b: Palette) -> Bool:
  match a b:
    case Palette{a, b, c, d} Palette{x, y, z, w}: U32.is_eq(a, x) && U32.is_eq(b, y) && U32.is_eq(c, z) && U32.is_eq(d, w)

def cache_match(revision: Nat, region: Bounds, palette: Palette, actual: Nat, bounds: Bounds, colors: Palette) -> Bool:
  Nat.is_eq(actual, revision) && same_region(bounds, region) && same_palette(colors, palette)

def cached_blocks(cache: Maybe<&2, SnapshotCache>, revision: Nat, region: Bounds, palette: Palette) -> Maybe<&2, List<&2, RawBlock>>:
  match cache:
    case None{}: None{}
    case Some{SnapshotCache{actual, bounds, colors, blocks}}:
      choose(Maybe<&2, List<&2, RawBlock>>, Some{blocks}, None{}, cache_match(revision, region, palette, actual, bounds, colors))

law cache_hit_returns_exact_blocks:
  for +revision: Nat
  for +region: Bounds
  for +palette: Palette
  for +actual: Nat
  for +bounds: Bounds
  for +colors: Palette
  for +blocks: List<&2, RawBlock>
  for hit: {cache_match(revision, region, palette, actual, bounds, colors) == True{} : Bool}
  {cached_blocks(Some{SnapshotCache{actual, bounds, colors, blocks}}, revision, region, palette) == Some{blocks} : Maybe<&2, List<&2, RawBlock>>}

def cache_hit_returns_exact_blocks(revision, region, palette, actual, bounds, colors, blocks, hit):
  %Equal.sym(Bool, cache_match(revision, region, palette, actual, bounds, colors), True{}, hit) : {choose(Maybe<&2, List<&2, RawBlock>>, Some{blocks}, None{}, _) == Some{blocks} : Maybe<&2, List<&2, RawBlock>>}
  {==}

law cache_miss_rejects_cached_blocks:
  for +revision: Nat
  for +region: Bounds
  for +palette: Palette
  for +actual: Nat
  for +bounds: Bounds
  for +colors: Palette
  for blocks: List<&2, RawBlock>
  for miss: {cache_match(revision, region, palette, actual, bounds, colors) == False{} : Bool}
  {cached_blocks(Some{SnapshotCache{actual, bounds, colors, blocks}}, revision, region, palette) == None{} : Maybe<&2, List<&2, RawBlock>>}

def cache_miss_rejects_cached_blocks(revision, region, palette, actual, bounds, colors, blocks, miss):
  %Equal.sym(Bool, cache_match(revision, region, palette, actual, bounds, colors), False{}, miss) : {choose(Maybe<&2, List<&2, RawBlock>>, Some{blocks}, None{}, _) == None{} : Maybe<&2, List<&2, RawBlock>>}
  {==}

def snapshot_cached(found: Maybe<&2, List<&2, RawBlock>>, world: C.World, registry: B.Registry, body: M.Body, yaw: F32, pitch: F32, +palette: Palette, +region: Bounds, cache: Maybe<&2, SnapshotCache>, mode: SnapshotMode) -> State & Result<&2, &2, String, R.Snapshot>:
  match found:
    case Some{blocks}: snapshot_result(registry, body, yaw, pitch, Some{palette}, region, cache, mode, (world, Done{blocks}))
    case None{}: snapshot_result(registry, body, yaw, pitch, Some{palette}, region, cache, mode, sample(U32.to_nat(volume(region)), 0, region, palette, world, Done{[]}))

def snapshot_clocked(result: C.World & C.Clock, registry: B.Registry, body: M.Body, yaw: F32, pitch: F32, +palette: Maybe<&2, Palette>, +region: Bounds, +cache: Maybe<&2, SnapshotCache>, mode: SnapshotMode) -> State & Result<&2, &2, String, R.Snapshot>:
  (world, C.Clock{tick, time, paused, daylight, revision, pending}) = result
  match palette:
    case None{}: (State{G.Engine{world, registry}, body, yaw, pitch, palette, region, cache}, Fail{"palette-unavailable"})
    case Some{+actual}: snapshot_cached(cached_blocks(cache, revision, region, actual), world, registry, body, yaw, pitch, actual, region, cache, mode)

def snapshot(state: State, width: U32, height: U32) -> State & Result<&2, &2, String, R.Snapshot>:
  State{G.Engine{world, registry}, body, yaw, pitch, palette, region, cache} = state
  snapshot_clocked(C.clock(world), registry, body, yaw, pitch, palette, region, cache, AbsoluteSnapshot{})

def relative_snapshot_gate(valid: Bool, state: State) -> State & Result<&2, &2, String, R.Snapshot>:
  match valid:
    case False{}: (state, Fail{"invalid-relative-camera"})
    case True{}:
      State{G.Engine{world, registry}, body, yaw, pitch, palette, region, cache} = state
      snapshot_clocked(C.clock(world), registry, body, yaw, pitch, palette, region, cache, RelativeSnapshot{})

def finite_relative_origin(origin: M.Vec3) -> Bool:
  M.Vec3{x, y, z} = origin
  Result.is_done(&2, &2, F.F64ConversionError, U32, F.floor_i32(x)) && Result.is_done(&2, &2, F.F64ConversionError, U32, F.floor_i32(y)) && Result.is_done(&2, &2, F.F64ConversionError, U32, F.floor_i32(z))

def relative_snapshot(state: State, width: U32, height: U32) -> State & Result<&2, &2, String, R.Snapshot>:
  State{engine, +body, +yaw, +pitch, palette, region, cache} = state
  relative_snapshot_gate(finite_relative_origin(eye_position(body)) && F.is_finite(F.from_f32(yaw)) && F.is_finite(F.from_f32(pitch)), State{engine, body, yaw, pitch, palette, region, cache})

def full_cube(cell: Cell) -> A.AABB:
  Cell{x, y, z, boundary} = cell
  +a = F.from_i32(x)
  +b = F.from_i32(y)
  +c = F.from_i32(z)
  A.AABB{a, b, c, F.add(a, F.from_u32(1)), F.add(b, F.from_u32(1)), F.add(c, F.from_u32(1))}

def floor_result(result: Result<&2, &2, F.F64ConversionError, U32>) -> Result<&2, &2, String, U32>:
  match result:
    case Fail{error}: Fail{"collision-query-outside-i32"}
    case Done{coordinate}: Done{coordinate}

def floor_coordinate(value: F.F64) -> Result<&2, &2, String, U32>:
  floor_result(F.floor_i32(value))

def query_bounds_gate(x: U32, y: U32, z: U32, w: U32, h: U32, d: U32, valid: Bool) -> Result<&2, &2, String, Bounds>:
  match valid:
    case False{}: Fail{"collision-query-limit"}
    case True{}: Done{Bounds{x, y, z, w, h, d}}

def signed_le(a: U32, b: U32) -> Bool:
  U32.is_le(U32.xor(a, 2147483648), U32.xor(b, 2147483648))

def query_coordinates(+lx: U32, +ly: U32, +lz: U32, +hx: U32, +hy: U32, +hz: U32) -> Result<&2, &2, String, Bounds>:
  +w = U32.add(U32.sub(hx, lx), 3)
  +h = U32.add(U32.sub(hy, ly), 3)
  +depth = U32.add(U32.sub(hz, lz), 3)
  query_bounds_gate(U32.sub(lx, 1), U32.sub(ly, 1), U32.sub(lz, 1), w, h, depth, Bool.not(U32.is_eq(lx, 2147483648) || U32.is_eq(ly, 2147483648) || U32.is_eq(lz, 2147483648) || U32.is_eq(hx, 2147483647) || U32.is_eq(hy, 2147483647) || U32.is_eq(hz, 2147483647)) && signed_le(lx, hx) && signed_le(ly, hy) && signed_le(lz, hz) && U32.is_ge(w, 3) && U32.is_le(w, 16) && U32.is_ge(h, 3) && U32.is_le(h, 16) && U32.is_ge(depth, 3) && U32.is_le(depth, 16))

def query_valid_bounds(box: A.AABB) -> Result<&2, &2, String, Bounds>:
  A.AABB{a, b, c, d, e, f} = box
  do Result<&2, &2, String, Bounds>:
    lx : U32 <- floor_coordinate(F.sub(a, A.epsilon()))
    ly : U32 <- floor_coordinate(F.sub(b, A.epsilon()))
    lz : U32 <- floor_coordinate(F.sub(c, A.epsilon()))
    hx : U32 <- floor_coordinate(F.add(d, A.epsilon()))
    hy : U32 <- floor_coordinate(F.add(e, A.epsilon()))
    hz : U32 <- floor_coordinate(F.add(f, A.epsilon()))
    query_coordinates(lx, ly, lz, hx, hy, hz)

def query_ordered(box: A.AABB) -> Bool:
  A.AABB{a, b, c, d, e, f} = box
  F.is_le(a, d) && F.is_le(b, e) && F.is_le(c, f)

def query_bounds_checked(valid: Bool, box: A.AABB) -> Result<&2, &2, String, Bounds>:
  match valid:
    case False{}: Fail{"invalid-collision-query"}
    case True{}: query_valid_bounds(box)

def query_bounds(+box: A.AABB) -> Result<&2, &2, String, Bounds>:
  query_bounds_checked(Maybe.is_none(&2, U32, A.AABB.invalid_field(box)) && query_ordered(box), box)

def collider_material(result: Result<&2, &2, String, Maybe<&2, U32>>, +query: A.AABB, +point: Cell, +reversed: List<&2, A.Collider>) -> Result<&2, &2, String, List<&2, A.Collider>>:
  match result:
    case Fail{error}: Fail{error}
    case Done{None{}}: Done{reversed}
    case Done{Some{material}}:
      Cell{x, y, z, boundary} = point
      +box = full_cube(point)
      Done{choose(List<&2, A.Collider>, A.BoxCollider{box} <> reversed, reversed, U32.is_eq(boundary, 0) && A.AABB.intersects(query, box))}

def collider_read(+palette: Palette, query: A.AABB, point: Cell, reversed: List<&2, A.Collider>, result: C.World & Result<&2, &2, C.Error, U32>) -> C.World & Result<&2, &2, String, List<&2, A.Collider>>:
  (world, status) = result
  match status:
    case Fail{error}: (world, Fail{error_text(error)})
    case Done{+state}: (world, collider_material(material(palette, state), query, point, reversed))

def choose_collision_read(world: C.World, palette: Palette, query: A.AABB, +point: Cell, reversed: List<&2, A.Collider>, corner: Bool) -> C.World & Result<&2, &2, String, List<&2, A.Collider>>:
  match corner:
    case True{}: (world, Done{reversed})
    case False{}: collider_read(palette, query, point, reversed, C.read_block(world, position(point)))

def colliders(n: Nat, +index: U32, +bounds: Bounds, +palette: Palette, +query: A.AABB, world: C.World, result: Result<&2, &2, String, List<&2, A.Collider>>) -> C.World & Result<&2, &2, String, List<&2, A.Collider>>:
  match n result:
    case _ Fail{error}: (world, Fail{error})
    case 0n Done{reversed}: (world, Done{List.reverse(&2, A.Collider, reversed)})
    case 1n+rest Done{reversed}:
      +point = cell(bounds, index)
      paired(C.World, Result<&2, &2, String, List<&2, A.Collider>>, C.World & Result<&2, &2, String, List<&2, A.Collider>>, choose_collision_read(world, palette, query, point, reversed, U32.is_eq(boundary(point), 3)), next => status => colliders(rest, U32.inc(index), bounds, palette, query, next, status))

def collect_bounds(world: C.World, palette: Palette, query: A.AABB, bounds: Result<&2, &2, String, Bounds>) -> C.World & Result<&2, &2, String, List<&2, A.Collider>>:
  match bounds:
    case Fail{error}: (world, Fail{error})
    case Done{+actual}: colliders(U32.to_nat(volume(actual)), 0, actual, palette, query, world, Done{[]})

def collect(world: C.World, palette: Palette, +query: A.AABB) -> C.World & Result<&2, &2, String, List<&2, A.Collider>>:
  collect_bounds(world, palette, query, query_bounds(query))

def moved_result(registry: B.Registry, world: C.World, body: M.Body, yaw: F32, pitch: F32, palette: Maybe<&2, Palette>, region: Bounds, cache: Maybe<&2, SnapshotCache>, result: Result<&2, &2, M.Error, M.Transition>) -> State & Result<&2, &2, String, M.Transition>:
  match result:
    case Fail{error}: (State{G.Engine{world, registry}, body, yaw, pitch, palette, region, cache}, Fail{"invalid-movement"})
    case Done{+transition}:
      M.Transition{next, delta, stepped, changed} = transition
      (State{G.Engine{world, registry}, next, yaw, pitch, palette, region, cache}, Done{transition})

def resolution_query(box: A.AABB, delta: M.Vec3, maximum: F32, baseline: M.Resolution) -> A.AABB:
  M.Resolution{displacement, stepped} = baseline
  M.step_query(box, delta, displacement, maximum)

def needs_step(body: M.Body, maximum: F32, requested: M.Vec3, result: M.Resolution) -> Bool:
  M.Body{position, box, velocity, width, height, grounded, horizontal, vertical, below} = body
  M.Vec3{+x, +y, +z} = requested
  M.Resolution{M.Vec3{cx, +cy, cz}, stepped} = result
  F.is_gt(F.from_f32(maximum), M.zero()) && (grounded || (F.is_ne(y, cy) && F.is_lt(y, M.zero()))) && (F.is_ne(x, cx) || F.is_ne(z, cz))

def step_read(world: C.World, palette: Palette, query: A.AABB, eligible: Bool) -> C.World & Result<&2, &2, String, List<&2, A.Collider>>:
  match eligible:
    case False{}: (world, Done{[]})
    case True{}: collect(world, palette, query)

def move_step(registry: B.Registry, +body: M.Body, yaw: F32, pitch: F32, palette: Maybe<&2, Palette>, region: Bounds, cache: Maybe<&2, SnapshotCache>, delta: M.Vec3, maximum: F32, initial: List<&2, A.Collider>, result: C.World & Result<&2, &2, String, List<&2, A.Collider>>) -> State & Result<&2, &2, String, M.Transition>:
  (world, status) = result
  match status:
    case Fail{error}: (State{G.Engine{world, registry}, body, yaw, pitch, palette, region, cache}, Fail{error})
    case Done{step}: moved_result(registry, world, body, yaw, pitch, palette, region, cache, M.move_checked(body, delta, maximum, initial, step))

def move_initial(result: C.World & Result<&2, &2, String, List<&2, A.Collider>>, registry: B.Registry, +body: M.Body, yaw: F32, pitch: F32, +palette: Palette, region: Bounds, cache: Maybe<&2, SnapshotCache>, +delta: M.Vec3, +maximum: F32) -> State & Result<&2, &2, String, M.Transition>:
  (world, status) = result
  match status:
    case Fail{error}: (State{G.Engine{world, registry}, body, yaw, pitch, Some{palette}, region, cache}, Fail{error})
    case Done{+initial}:
      M.Body{position, +box, velocity, width, height, +ground, horizontal, vertical, below} = body
      +baseline = M.resolve(box, ground, 0.0, delta, initial, [])
      query = resolution_query(box, delta, maximum, baseline)
      move_step(registry, body, yaw, pitch, Some{palette}, region, cache, delta, maximum, initial, step_read(world, palette, query, needs_step(body, maximum, delta, baseline)))

def initial_read(world: C.World, palette: Palette, body: M.Body, delta: M.Vec3, stationary: Bool) -> C.World & Result<&2, &2, String, List<&2, A.Collider>>:
  match stationary:
    case True{}: (world, Done{[]})
    case False{}: collect(world, palette, M.initial_block_query(body_box(body), delta))

def move_gate(valid: Bool, state: State, +delta: M.Vec3, +maximum: F32) -> State & Result<&2, &2, String, M.Transition>:
  match valid:
    case False{}: (state, Fail{"invalid-movement"})
    case True{}:
      State{G.Engine{world, registry}, +body, yaw, pitch, palette, region, cache} = state
      match palette:
        case None{}: (State{G.Engine{world, registry}, body, yaw, pitch, palette, region, cache}, Fail{"palette-unavailable"})
        case Some{+actual}:
          move_initial(initial_read(world, actual, body, delta, F.is_zero(M.Vec3.length_squared(delta))), registry, body, yaw, pitch, actual, region, cache, delta, maximum)

def move(state: State, +delta: M.Vec3, +maximum: F32) -> State & Result<&2, &2, String, M.Transition>:
  State{engine, +body, yaw, pitch, palette, region, cache} = state
  +height = F.from_f32(maximum)
  move_gate(Maybe.is_none(&2, M.Error, M.Body.invalid(body)) && Maybe.is_none(&2, U32, M.Vec3.invalid_field(delta)) && F.is_finite(height) && F.is_ge(height, M.zero()), State{engine, body, yaw, pitch, palette, region, cache}, delta, maximum)

def floor_mutations(n: Nat, +index: U32, +palette: Palette) -> List<&2, C.Mutation>:
  match n:
    case 0n: []
    case 1n+rest:
      Palette{air, +stone, +dirt, planks} = palette
      +x = U32.add(4294967293, U32.mod(index, 6))
      +z = U32.add(4294967293, U32.div(index, 6))
      C.BlockSet{C.Position{"minecraft:overworld", x, 0, z}, choose(U32, dirt, stone, U32.is_eq(U32.mod(index, 6), 5))} <> floor_mutations(rest, U32.inc(index), palette)

def fixture_mutations(+palette: Palette) -> List<&2, C.Mutation>:
  Palette{+air, stone, +dirt, +planks} = palette
  +dimension = {"minecraft:overworld" : String}
  List.append(&2, C.Mutation,
    [C.SectionCreate{C.Position{dimension, 4294967280, 4294967280, 4294967280}, air},
     C.SectionCreate{C.Position{dimension, 0, 4294967280, 4294967280}, air},
     C.SectionCreate{C.Position{dimension, 4294967280, 0, 4294967280}, air},
     C.SectionCreate{C.Position{dimension, 0, 0, 4294967280}, air},
     C.SectionCreate{C.Position{dimension, 4294967280, 4294967280, 0}, air},
     C.SectionCreate{C.Position{dimension, 0, 4294967280, 0}, air},
     C.SectionCreate{C.Position{dimension, 4294967280, 0, 0}, air},
     C.SectionCreate{C.Position{dimension, 0, 0, 0}, air}],
    List.append(&2, C.Mutation, floor_mutations(36n, 0, palette),
      [C.BlockSet{C.Position{dimension, 1, 1, 1}, dirt}, C.BlockSet{C.Position{dimension, 2, 1, 2}, planks}, C.BlockSet{C.Position{dimension, 2, 2, 2}, planks}]))

def fixture_admitted(result: C.World & Result<&2, &2, C.Error, Unit>) -> C.World & Result<&2, &2, String, Unit>:
  (world, status) = result
  match status:
    case Fail{error}: (world, Fail{error_text(error)})
    case Done{unit}: (world, Done{unit})

def fixture_enqueue(mutations: List<&2, C.Mutation>, +sequence: Nat, world: C.World, status: Result<&2, &2, String, Unit>) -> C.World & Result<&2, &2, String, Unit>:
  match mutations status:
    case _ Fail{error}: (world, Fail{error})
    case Nil{} Done{unit}: (C.step(world), Done{Unit{}})
    case mutation <> rest Done{unit}:
      paired(C.World, Result<&2, &2, String, Unit>, C.World & Result<&2, &2, String, Unit>, fixture_admitted(C.admit(world, C.Developer{}, Q.Stamp{1n, 0, sequence}, mutation)), next => result => fixture_enqueue(rest, 1n+sequence, next, result))

def fixture_pack(registry: B.Registry, body: M.Body, yaw: F32, pitch: F32, palette: Maybe<&2, Palette>, region: Bounds, cache: Maybe<&2, SnapshotCache>, result: C.World & Result<&2, &2, String, Unit>) -> State & Result<&2, &2, String, Unit>:
  (world, status) = result
  (State{G.Engine{world, registry}, body, yaw, pitch, palette, region, cache}, status)

def fixture_empty(sections: S.Sections) -> S.Sections & Bool:
  match sections:
    case S.EmptySections{}: (S.EmptySections{}, True{})
    case other: (other, False{})

def fixture_world_gate(valid: Bool, state: State) -> State & Result<&2, &2, String, Unit>:
  match valid:
    case False{}: (state, Fail{"fixture-requires-fresh-empty-world"})
    case True{}:
      State{G.Engine{world, registry}, body, yaw, pitch, +palette, region, cache} = state
      match palette:
        case None{}: (State{G.Engine{world, registry}, body, yaw, pitch, palette, region, cache}, Fail{"palette-unavailable"})
        case Some{actual}: fixture_pack(registry, body, yaw, pitch, palette, region, cache, fixture_enqueue(fixture_mutations(actual), 0n, world, Done{Unit{}}))

def fixture_status(status: Result<&2, &2, String, Unit>, state: State) -> State & Result<&2, &2, String, Unit>:
  match status:
    case Fail{error}: (state, Fail{error})
    case Done{unit}:
      State{G.Engine{world, registry}, body, yaw, pitch, palette, region, cache} = state
      C.World{+tick, time, paused, daylight, +revision, count, sections, +pending, +events} = world
      paired(S.Sections, Bool, State & Result<&2, &2, String, Unit>, fixture_empty(sections), kept => empty => fixture_world_gate(empty && Nat.is_eq(tick, 0n) && Nat.is_eq(revision, 0n) && List.is_empty(&2, Q.Pending<C.Mutation>, pending) && List.is_empty(&2, C.CoreEvent, events), State{G.Engine{C.World{tick, time, paused, daylight, revision, count, kept, pending, events}, registry}, body, yaw, pitch, palette, region, cache}))

def fixture_new(result: State & Result<&2, &2, String, Unit>) -> State & Result<&2, &2, String, Unit>:
  (state, status) = result
  fixture_status(status, state)

def fixture(engine: G.Engine) -> State & Result<&2, &2, String, Unit>:
  fixture_new(new(engine))
