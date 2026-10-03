import Base
import ./f64.bend as F
import ./geometry.bend as G
import ./movement.bend as M
import ./locomotion.bend as L
import ./travel.bend as T

# Transient Java Entity support cache, independent of the authoritative Body.
type State is Data:
  State{main: Maybe<&2, T.BlockPos>, on_ground_no_blocks: Bool}

type Candidate is Data:
  FullCube{position: T.BlockPos}

type Queries is Data:
  Queries{primary: G.AABB, fallback: Maybe<&2, G.AABB>}

type Selection is Data:
  Selection{position: Maybe<&2, T.BlockPos>, distance: F.F64}

type Error is Data:
  InvalidPosition{field: U32}
  InvalidBox{field: U32}
  ReversedBox{axis: U32}
  InvalidMovement{field: U32}
  InvalidOffset{}

def empty() -> State:
  State{None{}, False{}}

def half() -> F.F64:
  F.F64{1071644672, 0}

def primary_query(box: G.AABB) -> G.AABB:
  match box:
    case G.AABB{x1, +y1, z1, x2, y2, z2}:
      G.AABB.new(x1, F.sub(y1, F.F64{1051772663, 2696277389}), z1, x2, y1, z2)

def fallback_query(primary: G.AABB, movement: M.Vec3) -> G.AABB:
  match movement:
    case M.Vec3{x, y, z}: G.AABB.move(primary, F.neg(x), M.zero(), F.neg(z))

def query_movement(primary: G.AABB, movement: Maybe<&2, M.Vec3>) -> Maybe<&2, G.AABB>:
  match movement:
    case None{}: None{}
    case Some{movement}: Some{fallback_query(primary, movement)}

def queries(box: G.AABB, movement: Maybe<&2, M.Vec3>) -> Queries:
  +primary = primary_query(box)
  Queries{primary, query_movement(primary, movement)}

def candidate_box(candidate: Candidate) -> G.AABB:
  match candidate:
    case FullCube{T.BlockPos{x, y, z}}:
      +xf = F.from_i32(x)
      +yf = F.from_i32(y)
      +zf = F.from_i32(z)
      G.AABB{xf, yf, zf, F.add(xf, M.one()), F.add(yf, M.one()), F.add(zf, M.one())}

def center_distance(position: M.Vec3, block: T.BlockPos) -> F.F64:
  match position block:
    case M.Vec3{x, y, z} T.BlockPos{bx, by, bz}:
      +dx = F.sub(F.add(F.from_i32(bx), half()), x)
      +dy = F.sub(F.add(F.from_i32(by), half()), y)
      +dz = F.sub(F.add(F.from_i32(bz), half()), z)
      F.add(F.add(F.mul(dx, dx), F.mul(dy, dy)), F.mul(dz, dz))

# Java Vec3i.compareTo subtracts signed ints and may overflow.
def compare_x(x: U32, y: U32, +z: U32, bx: U32, by: U32, +bz: U32, same_z: Bool) -> U32:
  match same_z:
    case True{}: U32.sub(x, bx)
    case False{}: U32.sub(z, bz)

def compare_y(x: U32, +y: U32, +z: U32, bx: U32, +by: U32, +bz: U32, same_y: Bool) -> U32:
  match same_y:
    case True{}: compare_x(x, y, z, bx, by, bz, U32.is_eq(z, bz))
    case False{}: U32.sub(y, by)

def compare_position(a: T.BlockPos, b: T.BlockPos) -> U32:
  match a b:
    case T.BlockPos{x, +y, z} T.BlockPos{bx, +by, bz}: compare_y(x, y, z, bx, by, bz, U32.is_eq(y, by))

def tie_preferred(previous: Maybe<&2, T.BlockPos>, candidate: T.BlockPos) -> Bool:
  match previous:
    case None{}: True{}
    case Some{previous}: U32.is_ge(compare_position(previous, candidate), 2147483648)

def choose_candidate(previous: Maybe<&2, T.BlockPos>, previous_distance: F.F64, candidate: T.BlockPos, distance: F.F64, use: Bool) -> Selection:
  match use:
    case False{}: Selection{previous, previous_distance}
    case True{}: Selection{Some{candidate}, distance}

def consider_distance(+previous: Maybe<&2, T.BlockPos>, +previous_distance: F.F64, +candidate: T.BlockPos, +distance: F.F64) -> Selection:
  choose_candidate(previous, previous_distance, candidate, distance,
    F.is_lt(distance, previous_distance) || (F.is_eq(distance, previous_distance) && tie_preferred(previous, candidate)))

def consider(position: M.Vec3, query: G.AABB, previous: Maybe<&2, T.BlockPos>, previous_distance: F.F64, candidate: Candidate, intersects: Bool) -> Selection:
  match candidate intersects:
    case _ False{}: Selection{previous, previous_distance}
    case FullCube{+block} True{}: consider_distance(previous, previous_distance, block, center_distance(position, block))

def selected_position(read: Selection) -> Maybe<&2, T.BlockPos>:
  Selection{position, distance} = read
  position

def selected_distance(read: Selection) -> F.F64:
  Selection{position, distance} = read
  distance

def select_go(candidates: List<&2, Candidate>, +position: M.Vec3, +query: G.AABB, previous: Maybe<&2, T.BlockPos>, previous_distance: F.F64) -> Selection:
  match candidates:
    case Nil{}: Selection{previous, previous_distance}
    case +candidate <> rest:
      +read = consider(position, query, previous, previous_distance, candidate, G.AABB.intersects(query, candidate_box(candidate)))
      select_go(rest, position, query, selected_position(read), selected_distance(read))

def select(position: M.Vec3, query: G.AABB, candidates: List<&2, Candidate>) -> Maybe<&2, T.BlockPos>:
  selected_position(select_go(candidates, position, query, None{}, F.F64{2146435071, 4294967295}))

def has_movement(movement: Maybe<&2, M.Vec3>) -> Bool:
  match movement:
    case None{}: False{}
    case Some{value}: True{}

def needs_fallback(state: State, grounded: Bool, primary: Maybe<&2, T.BlockPos>, movement: Maybe<&2, M.Vec3>) -> Bool:
  match state grounded primary:
    case _ False{} _: False{}
    case _ True{} Some{block}: False{}
    case State{main, True{}} True{} None{}: False{}
    case State{main, False{}} True{} None{}: has_movement(movement)

def cache_fallback_present(fallback: Maybe<&2, T.BlockPos>) -> State:
  match fallback:
    case None{}: State{None{}, True{}}
    case Some{block}: State{Some{block}, False{}}

def cache_fallback_checked(previous: Maybe<&2, T.BlockPos>, fallback: Maybe<&2, T.BlockPos>, movement: Bool) -> State:
  match movement:
    case False{}: State{previous, True{}}
    case True{}: cache_fallback_present(fallback)

def update_grounded(state: State, primary: Maybe<&2, T.BlockPos>, fallback: Maybe<&2, T.BlockPos>, movement: Bool) -> State:
  match state primary:
    case _ Some{block}: State{Some{block}, False{}}
    case State{main, True{}} None{}: State{None{}, True{}}
    case State{main, False{}} None{}: cache_fallback_checked(main, fallback, movement)

def update_cached(state: State, grounded: Bool, primary: Maybe<&2, T.BlockPos>, fallback: Maybe<&2, T.BlockPos>, movement: Bool) -> State:
  match grounded:
    case False{}: empty()
    case True{}: update_grounded(state, primary, fallback, movement)

# Pinned Mth.floor is Math.floor followed by Java saturating d2i.
def floor_saturation(value: F.F64, nan: Bool) -> U32:
  match nan:
    case True{}: 0
    case False{}:
      +negative = F.sign(value)
      (2147483647 + Bool.to_u32(negative) : U32)

def floor_result(+value: F.F64, converted: Result<&2, &2, F.F64ConversionError, U32>) -> U32:
  match converted:
    case Done{word}: word
    case Fail{error}: floor_saturation(value, F.is_nan(value))

def floor_word(+value: F.F64) -> U32:
  floor_result(value, F.floor_i32(value))

def block_position(position: M.Vec3) -> T.BlockPos:
  match position:
    case M.Vec3{x, y, z}: T.BlockPos{floor_word(x), floor_word(y), floor_word(z)}

def offset_position(position: M.Vec3, offset: F32) -> T.BlockPos:
  match position:
    case M.Vec3{x, y, z}: T.BlockPos{floor_word(x), floor_word(F.sub(y, F.from_f32(offset))), floor_word(z)}

def supported_y(position: M.Vec3, block: T.BlockPos, offset: F32) -> T.BlockPos:
  match position block:
    case M.Vec3{x, y, z} T.BlockPos{bx, by, bz}: T.BlockPos{bx, floor_word(F.sub(y, F.from_f32(offset))), bz}

def supported_offset(position: M.Vec3, block: T.BlockPos, offset: F32, replace_y: Bool) -> T.BlockPos:
  match replace_y:
    case False{}: block
    case True{}: supported_y(position, block, offset)

# This raw getOnPos projection admits cached full-cube states only.
def get_on_pos(position: M.Vec3, state: State, +offset: F32) -> T.BlockPos:
  match state:
    case State{None{}, flag}: offset_position(position, offset)
    case State{Some{block}, flag}:
      supported_offset(position, block, offset, F.is_gt(F.from_f32(offset), F.from_f32(L.float_bits(925353388))))

def below_position(position: M.Vec3, state: State) -> T.BlockPos:
  get_on_pos(position, state, L.float_bits(1056964625))

def jump_factor_gate(current: F32, below: F32, unit: Bool) -> F32:
  match unit:
    case True{}: below
    case False{}: current

def jump_factor(+current: F32, below: F32) -> F32:
  jump_factor_gate(current, below, F.is_eq(F.from_f32(current), M.one()))

def first_error(first: Maybe<&2, Error>, rest: Maybe<&2, Error>) -> Maybe<&2, Error>:
  match first:
    case Some{error}: Some{error}
    case None{}: rest

def position_error(field: Maybe<&2, U32>) -> Maybe<&2, Error>:
  match field:
    case Some{field}: Some{InvalidPosition{field}}
    case None{}: None{}

def box_field_error(field: Maybe<&2, U32>) -> Maybe<&2, Error>:
  match field:
    case Some{field}: Some{InvalidBox{field}}
    case None{}: None{}

def box_order(x: Bool, y: Bool, z: Bool) -> Maybe<&2, Error>:
  match x y z:
    case False{} _ _: Some{ReversedBox{0}}
    case True{} False{} _: Some{ReversedBox{1}}
    case True{} True{} False{}: Some{ReversedBox{2}}
    case True{} True{} True{}: None{}

def box_bounds(box: G.AABB) -> Maybe<&2, Error>:
  match box:
    case G.AABB{a, b, c, d, e, f}: box_order(F.is_le(a, d), F.is_le(b, e), F.is_le(c, f))

def box_error(+box: G.AABB) -> Maybe<&2, Error>:
  first_error(box_field_error(G.AABB.invalid_field(box)), box_bounds(box))

def movement_field_error(field: Maybe<&2, U32>) -> Maybe<&2, Error>:
  match field:
    case Some{field}: Some{InvalidMovement{field}}
    case None{}: None{}

def movement_error(movement: Maybe<&2, M.Vec3>) -> Maybe<&2, Error>:
  match movement:
    case None{}: None{}
    case Some{movement}: movement_field_error(M.Vec3.invalid_field(movement))

def queries_error(value: Queries) -> Maybe<&2, Error>:
  match value:
    case Queries{primary, None{}}: box_error(primary)
    case Queries{primary, Some{fallback}}: first_error(box_error(primary), box_error(fallback))

def queries_result(value: Queries, error: Maybe<&2, Error>) -> Result<&2, &2, Error, Queries>:
  match error:
    case Some{error}: Fail{error}
    case None{}: Done{value}

def queries_value(+value: Queries) -> Result<&2, &2, Error, Queries>:
  queries_result(value, queries_error(value))

def queries_gate(box: G.AABB, movement: Maybe<&2, M.Vec3>, error: Maybe<&2, Error>) -> Result<&2, &2, Error, Queries>:
  match error:
    case Some{error}: Fail{error}
    case None{}: queries_value(queries(box, movement))

def queries_checked(+box: G.AABB, +movement: Maybe<&2, M.Vec3>) -> Result<&2, &2, Error, Queries>:
  queries_gate(box, movement, first_error(box_error(box), movement_error(movement)))

def select_gate(position: M.Vec3, query: G.AABB, candidates: List<&2, Candidate>, error: Maybe<&2, Error>) -> Result<&2, &2, Error, Maybe<&2, T.BlockPos>>:
  match error:
    case Some{error}: Fail{error}
    case None{}: Done{select(position, query, candidates)}

def select_checked(+position: M.Vec3, +query: G.AABB, candidates: List<&2, Candidate>) -> Result<&2, &2, Error, Maybe<&2, T.BlockPos>>:
  select_gate(position, query, candidates, first_error(position_error(M.Vec3.invalid_field(position)), box_error(query)))

def offset_gate(valid: Bool) -> Maybe<&2, Error>:
  match valid:
    case False{}: Some{InvalidOffset{}}
    case True{}: None{}

def offset_error(offset: F32) -> Maybe<&2, Error>:
  offset_gate(F.is_finite(F.from_f32(offset)))

def on_pos_gate(position: M.Vec3, state: State, offset: F32, error: Maybe<&2, Error>) -> Result<&2, &2, Error, T.BlockPos>:
  match error:
    case Some{error}: Fail{error}
    case None{}: Done{get_on_pos(position, state, offset)}

def get_on_pos_checked(+position: M.Vec3, state: State, +offset: F32) -> Result<&2, &2, Error, T.BlockPos>:
  on_pos_gate(position, state, offset, first_error(position_error(M.Vec3.invalid_field(position)), offset_error(offset)))

def fallback_selection(state: State, position: M.Vec3, primary_choice: Maybe<&2, T.BlockPos>, fallback: Maybe<&2, G.AABB>, candidates: List<&2, Candidate>, movement: Bool) -> State:
  match fallback:
    case None{}: update_cached(state, True{}, primary_choice, None{}, movement)
    case Some{query}: update_cached(state, True{}, primary_choice, select(position, query, candidates), movement)

def update_primary(state: State, position: M.Vec3, primary_choice: Maybe<&2, T.BlockPos>, fallback: Maybe<&2, G.AABB>, candidates: List<&2, Candidate>, movement: Bool, needed: Bool) -> State:
  match needed:
    case False{}: update_cached(state, True{}, primary_choice, None{}, movement)
    case True{}: fallback_selection(state, position, primary_choice, fallback, candidates, movement)

def update_queries(+state: State, +position: M.Vec3, grounded: Bool, +movement: Maybe<&2, M.Vec3>, query: Queries, candidates: List<&2, Candidate>, fallback_candidates: List<&2, Candidate>) -> State:
  match grounded query:
    case False{} _: empty()
    case True{} Queries{primary, fallback}:
      +choice = select(position, primary, candidates)
      update_primary(state, position, choice, fallback, fallback_candidates, has_movement(movement), needs_fallback(state, True{}, choice, movement))

def update_query_result(state: State, position: M.Vec3, grounded: Bool, movement: Maybe<&2, M.Vec3>, candidates: List<&2, Candidate>, fallback_candidates: List<&2, Candidate>, result: Result<&2, &2, Error, Queries>) -> Result<&2, &2, Error, State>:
  match result:
    case Fail{error}: Fail{error}
    case Done{query}: Done{update_queries(state, position, grounded, movement, query, candidates, fallback_candidates)}

def update_gate(state: State, position: M.Vec3, box: G.AABB, grounded: Bool, +movement: Maybe<&2, M.Vec3>, candidates: List<&2, Candidate>, fallback_candidates: List<&2, Candidate>, error: Maybe<&2, Error>) -> Result<&2, &2, Error, State>:
  match error:
    case Some{error}: Fail{error}
    case None{}: update_query_result(state, position, grounded, movement, candidates, fallback_candidates, queries_checked(box, movement))

def update_checked(state: State, +position: M.Vec3, box: G.AABB, grounded: Bool, movement: Maybe<&2, M.Vec3>, candidates: List<&2, Candidate>, fallback_candidates: List<&2, Candidate>) -> Result<&2, &2, Error, State>:
  update_gate(state, position, box, grounded, movement, candidates, fallback_candidates, position_error(M.Vec3.invalid_field(position)))

law airborne_clears_cached_support:
  for state: State
  for primary: Maybe<&2, T.BlockPos>
  for fallback: Maybe<&2, T.BlockPos>
  for movement: Bool
  {update_cached(state, False{}, primary, fallback, movement) == empty() : State}

def airborne_clears_cached_support(state, primary, fallback, movement):
  match state:
    case State{main, flag}: {==}

law null_movement_retains_previous_support:
  for +main: Maybe<&2, T.BlockPos>
  for fallback: Maybe<&2, T.BlockPos>
  {update_cached(State{main, False{}}, True{}, None{}, fallback, False{}) == State{main, True{}} : State}

def null_movement_retains_previous_support(main, fallback):
  match main:
    case None{}: {==}
    case Some{position}: {==}

law known_absent_support_skips_fallback:
  for main: Maybe<&2, T.BlockPos>
  for fallback: Maybe<&2, T.BlockPos>
  for movement: Bool
  {update_cached(State{main, True{}}, True{}, None{}, fallback, movement) == State{None{}, True{}} : State}

def known_absent_support_skips_fallback(main, fallback, movement):
  {==}

law unit_current_jump_factor_selects_below:
  for current: F32
  for +below: F32
  {jump_factor_gate(current, below, True{}) == below : F32}

def unit_current_jump_factor_selects_below(current, below):
  {==}
