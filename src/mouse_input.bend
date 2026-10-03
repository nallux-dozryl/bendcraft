import Base
import ./f64.bend as F

# The pure angle-input projection of neutral captured/uncaptured MouseHandler.
# Coordinates and accumulated deltas are raw binary64 words. The actual SDL
# adapter first widens binary32 event fields; it never narrows accumulated sums.
type State is Data:
  State{position_x: F.F64, position_y: F.F64, accumulated_x: F.F64, accumulated_y: F.F64, ignore_first_move: Bool}

type Move is Data:
  PointerMove{x: F.F64, y: F.F64, relative_x: F.F64, relative_y: F.F64, window_matches: Bool}

type Options is Data:
  Options{sensitivity: F.F64, invert_x: Bool, invert_y: Bool, smooth_camera: Bool, scoping: Bool}

type Deltas is Data:
  Deltas{dx: F.F64, dy: F.F64}

type Frame is Data:
  Frame{state: State, turn: Maybe<&2, Deltas>}

type Error is Data:
  InvalidState{field: U32}
  InvalidMove{field: U32}
  InvalidSensitivity{}
  UnsupportedSmoothCamera{}
  UnsupportedScoping{}
  UnsupportedRelativeMode{}
  NonFiniteAccumulation{axis: U32}
  NonFiniteDeltas{axis: U32}

def choose(-A: Data, yes: A, no: A, test: Bool) -> A:
  match test:
    case True{}: yes
    case False{}: no

def initial() -> State:
  State{F.F64{0, 0}, F.F64{0, 0}, F.F64{0, 0}, F.F64{0, 0}, True{}}

def default_options() -> Options:
  Options{F.F64{1071644672, 0}, False{}, False{}, False{}, False{}}

def ignore_next_move(state: State) -> State:
  match state:
    case State{x, y, ax, ay, _}: State{x, y, ax, ay, True{}}

def clear(state: State) -> State:
  match state:
    case State{x, y, _, _, first}: State{x, y, F.F64{0, 0}, F.F64{0, 0}, first}

def first_error(first: Maybe<&2, Error>, rest: Maybe<&2, Error>) -> Maybe<&2, Error>:
  match first:
    case Some{error}: Some{error}
    case None{}: rest

def field_error(valid: Bool, error: Error, rest: Maybe<&2, Error>) -> Maybe<&2, Error>:
  match valid:
    case False{}: Some{error}
    case True{}: rest

def state_error(state: State) -> Maybe<&2, Error>:
  match state:
    case State{x, y, ax, ay, _}:
      field_error(F.is_finite(x), InvalidState{0}, field_error(F.is_finite(y), InvalidState{1}, field_error(F.is_finite(ax), InvalidState{2}, field_error(F.is_finite(ay), InvalidState{3}, None{}))))

def move_error(move: Move) -> Maybe<&2, Error>:
  match move:
    case PointerMove{x, y, rx, ry, _}:
      field_error(F.is_finite(x), InvalidMove{0}, field_error(F.is_finite(y), InvalidMove{1}, field_error(F.is_finite(rx), InvalidMove{2}, field_error(F.is_finite(ry), InvalidMove{3}, None{}))))

def sensitivity_valid(+value: F.F64) -> Bool:
  Bool.and(F.is_finite(value), Bool.and(Bool.not(F.is_lt(value, F.F64{0, 0})), Bool.not(F.is_gt(value, F.from_u32(1)))))

def options_error(options: Options) -> Maybe<&2, Error>:
  match options:
    case Options{sensitivity, _, _, smooth, scoping}:
      field_error(sensitivity_valid(sensitivity), InvalidSensitivity{},
        choose(Maybe<&2, Error>, Some{UnsupportedSmoothCamera{}},
          choose(Maybe<&2, Error>, Some{UnsupportedScoping{}}, None{}, scoping), smooth))

def accumulated_error(state: State) -> Maybe<&2, Error>:
  match state:
    case State{_, _, x, y, _}:
      field_error(F.is_finite(x), NonFiniteAccumulation{0}, field_error(F.is_finite(y), NonFiniteAccumulation{1}, None{}))

def moved_accum(+state: State, move: Move, +focused: Bool, +captured: Bool) -> State:
  match state move:
    case State{old_x, old_y, ax, ay, _} PointerMove{+x, +y, rx, ry, _}:
      State{x, y,
        choose(F.F64, F.add(ax, choose(F.F64, rx, F.sub(x, old_x), captured)), ax, focused),
        choose(F.F64, F.add(ay, choose(F.F64, ry, F.sub(y, old_y), captured)), ay, focused), False{}}

def moved_first(first: Bool, +move: Move, state: State, focused: Bool, captured: Bool) -> State:
  match first move:
    case True{} PointerMove{x, y, _, _, _}:
      match state:
        case State{_, _, ax, ay, _}: State{x, y, ax, ay, False{}}
    case False{} _: moved_accum(state, move, focused, captured)

def moved(matches: Bool, state: State, +move: Move, focused: Bool, captured: Bool) -> State:
  match matches state:
    case False{} _: state
    case True{} State{x, y, ax, ay, +first}: moved_first(first, move, State{x, y, ax, ay, first}, focused, captured)

def move_done(result: State, error: Maybe<&2, Error>) -> Result<&2, &2, Error, State>:
  match error:
    case Some{error}: Fail{error}
    case None{}: Done{result}

def move_ready(state: State, move: Move, focused: Bool, captured: Bool, matches: Bool) -> Result<&2, &2, Error, State>:
  +result = moved(matches, state, move, focused, captured)
  move_done(result, accumulated_error(result))

def move_gate(state: State, move: Move, focused: Bool, captured: Bool, matches: Bool, error: Maybe<&2, Error>) -> Result<&2, &2, Error, State>:
  match error:
    case Some{error}: Fail{error}
    case None{}: move_ready(state, move, focused, captured, matches)

def on_move(+state: State, +move: Move, focused: Bool, captured: Bool) -> Result<&2, &2, Error, State>:
  match move:
    case PointerMove{+x, +y, +rx, +ry, +matches}:
      move_gate(state, PointerMove{x, y, rx, ry, matches}, focused, captured, matches,
        first_error(state_error(state), move_error(PointerMove{x, y, rx, ry, matches})))

# Captured relative-only inputs have no absolute position observation. Retain
# the supplied position; uncaptured use requires an absolute Move instead.
def relative_gate(captured: Bool, state: State, dx: F.F64, dy: F.F64, focused: Bool) -> Result<&2, &2, Error, State>:
  match captured state:
    case False{} _: Fail{UnsupportedRelativeMode{}}
    case True{} State{+x, +y, ax, ay, first}: on_move(State{x, y, ax, ay, first}, PointerMove{x, y, dx, dy, True{}}, focused, True{})

def relative(state: State, dx: F.F64, dy: F.F64, focused: Bool, captured: Bool) -> Result<&2, &2, Error, State>:
  relative_gate(captured, state, dx, dy, focused)

# Promoted float constants, followed by strictly ordered binary64 operations.
def scale(+sensitivity: F.F64) -> F.F64:
  +a = F.add(F.mul(sensitivity, F.F64{1071854387, 1073741824}), F.F64{1070176665, 2684354560})
  F.mul(F.mul(F.mul(a, a), a), F.from_u32(8))

def invert(value: F.F64, inverted: Bool) -> F.F64:
  match inverted:
    case False{}: value
    case True{}: F.neg(value)

def scaled(state: State, options: Options) -> Deltas:
  match state options:
    case State{_, _, x, y, _} Options{sensitivity, ix, iy, _, _}:
      +factor = scale(sensitivity)
      Deltas{invert(F.mul(x, factor), ix), invert(F.mul(y, factor), iy)}

def deltas_error(deltas: Deltas) -> Maybe<&2, Error>:
  match deltas:
    case Deltas{x, y}:
      field_error(F.is_finite(x), NonFiniteDeltas{0}, field_error(F.is_finite(y), NonFiniteDeltas{1}, None{}))

def frame_done(state: State, deltas: Deltas, error: Maybe<&2, Error>) -> Result<&2, &2, Error, Frame>:
  match error:
    case Some{error}: Fail{error}
    case None{}: Done{Frame{clear(state), Some{deltas}}}

def finish_ready(+state: State, options: Options, active: Bool) -> Result<&2, &2, Error, Frame>:
  match active:
    case False{}: Done{Frame{clear(state), None{}}}
    case True{}:
      +deltas = scaled(state, options)
      frame_done(state, deltas, deltas_error(deltas))

def finish_gate(state: State, options: Options, active: Bool, error: Maybe<&2, Error>) -> Result<&2, &2, Error, Frame>:
  match error:
    case Some{error}: Fail{error}
    case None{}: finish_ready(state, options, active)

def finish(+state: State, +options: Options, focused: Bool, captured: Bool, player_present: Bool) -> Result<&2, &2, Error, Frame>:
  finish_gate(state, options, Bool.and(focused, Bool.and(captured, player_present)), first_error(state_error(state), options_error(options)))
