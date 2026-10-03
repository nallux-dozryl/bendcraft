import Base
import ../src/f64.bend as F
import ../src/mouse_input.bend as M

law initial_first_move:
  {M.initial() == M.State{F.F64{0, 0}, F.F64{0, 0}, F.F64{0, 0}, F.F64{0, 0}, True{}} : M.State}

def initial_first_move():
  {==}

law invalid_window_preserves_state:
  for state: M.State
  for move: M.Move
  for focused: Bool
  for captured: Bool
  {M.moved(False{}, state, move, focused, captured) == state : M.State}

def invalid_window_preserves_state(state, move, focused, captured):
  {==}

law first_move_discards_relative:
  for x: F.F64
  for y: F.F64
  for old_x: F.F64
  for old_y: F.F64
  for ax: F.F64
  for ay: F.F64
  for rx: F.F64
  for ry: F.F64
  for focused: Bool
  for captured: Bool
  {M.moved_first(True{}, M.PointerMove{x, y, rx, ry, True{}}, M.State{old_x, old_y, ax, ay, True{}}, focused, captured) == M.State{x, y, ax, ay, False{}} : M.State}

def first_move_discards_relative(x, y, old_x, old_y, ax, ay, rx, ry, focused, captured):
  {==}

law clear_is_idempotent:
  for state: M.State
  {M.clear(M.clear(state)) == M.clear(state) : M.State}

def clear_is_idempotent(state):
  match state:
    case M.State{x, y, ax, ay, first}: {==}

law default_scale_fixture:
  {M.scale(F.F64{1071644672, 0}) == F.F64{1072693248, 402653196} : F.F64}

def default_scale_fixture():
  {==}

law inactive_frame_has_no_turn:
  for state: M.State
  for options: M.Options
  {M.finish_ready(state, options, False{}) == Done{M.Frame{M.clear(state), None{}}} : Result<&2, &2, M.Error, M.Frame>}

def inactive_frame_has_no_turn(state, options):
  {==}

law unsupported_relative_mode:
  for state: M.State
  for dx: F.F64
  for dy: F.F64
  for focused: Bool
  {M.relative(state, dx, dy, focused, False{}) == Fail{M.UnsupportedRelativeMode{}} : Result<&2, &2, M.Error, M.State>}

def unsupported_relative_mode(state, dx, dy, focused):
  {==}

law rejected_finish_retains_owner:
  for +state: M.State
  for options: M.Options
  for active: Bool
  for +error: M.Error
  {(state, M.finish_gate(state, options, active, Some{error})) == (state, Fail{error}) : M.State & Result<&2, &2, M.Error, M.Frame>}

def rejected_finish_retains_owner(state, options, active, error):
  {==}

law negative_zero_inversion:
  {M.invert(F.F64{2147483648, 0}, True{}) == F.F64{0, 0} : F.F64}

def negative_zero_inversion():
  {==}

def wide_words(value: F.F64) -> String:
  match value:
    case F.F64{hi, lo}: U32.show(hi) ++ "," ++ U32.show(lo)

def state_words(state: M.State) -> String:
  match state:
    case M.State{x, y, ax, ay, first}: "[" ++ wide_words(x) ++ "," ++ wide_words(y) ++ "," ++ wide_words(ax) ++ "," ++ wide_words(ay) ++ "," ++ U32.show(Bool.to_u32(first)) ++ "]"

def turn_words(value: Maybe<&2, M.Deltas>) -> String:
  match value:
    case None{}: "null"
    case Some{M.Deltas{x, y}}: "[" ++ wide_words(x) ++ "," ++ wide_words(y) ++ "]"

def error_words(error: M.Error) -> String:
  match error:
    case M.InvalidState{field}: "{\"kind\":\"InvalidState\",\"field\":" ++ U32.show(field) ++ "}"
    case M.InvalidMove{field}: "{\"kind\":\"InvalidMove\",\"field\":" ++ U32.show(field) ++ "}"
    case M.InvalidSensitivity{}: "{\"kind\":\"InvalidSensitivity\"}"
    case M.UnsupportedSmoothCamera{}: "{\"kind\":\"UnsupportedSmoothCamera\"}"
    case M.UnsupportedScoping{}: "{\"kind\":\"UnsupportedScoping\"}"
    case M.UnsupportedRelativeMode{}: "{\"kind\":\"UnsupportedRelativeMode\"}"
    case M.NonFiniteAccumulation{axis}: "{\"kind\":\"NonFiniteAccumulation\",\"field\":" ++ U32.show(axis) ++ "}"
    case M.NonFiniteDeltas{axis}: "{\"kind\":\"NonFiniteDeltas\",\"field\":" ++ U32.show(axis) ++ "}"

def result_state(result: Result<&2, &2, M.Error, M.State>) -> String:
  match result:
    case Done{state}: "{\"ok\":true,\"state\":" ++ state_words(state) ++ "}"
    case Fail{error}: "{\"ok\":false,\"error\":" ++ error_words(error) ++ "}"

def result_frame(result: Result<&2, &2, M.Error, M.Frame>) -> String:
  match result:
    case Done{M.Frame{state, turn}}: "{\"ok\":true,\"state\":" ++ state_words(state) ++ ",\"turn\":" ++ turn_words(turn) ++ "}"
    case Fail{error}: "{\"ok\":false,\"error\":" ++ error_words(error) ++ "}"

def pair_finish(result: Result<&2, &2, M.Error, M.State>, options: M.Options, focused: Bool, captured: Bool, player: Bool) -> Result<&2, &2, M.Error, M.Frame>:
  match result:
    case Fail{error}: Fail{error}
    case Done{state}: M.finish(state, options, focused, captured, player)

def pair_second(result: Result<&2, &2, M.Error, M.State>, move: M.Move, options: M.Options, +focused: Bool, +captured: Bool, player: Bool) -> Result<&2, &2, M.Error, M.Frame>:
  match result:
    case Fail{error}: Fail{error}
    case Done{state}: pair_finish(M.on_move(state, move, focused, captured), options, focused, captured, player)

def pair_initial(state: M.State, a: M.Move, b: M.Move, options: M.Options, +focused: Bool, +captured: Bool, player: Bool) -> Result<&2, &2, M.Error, M.Frame>:
  pair_second(M.on_move(state, a, focused, captured), b, options, focused, captured, player)

def number_cons(head: Maybe<&2, U32>, tail: Maybe<&2, List<&2, U32>>) -> Maybe<&2, List<&2, U32>>:
  match head tail:
    case Some{head} Some{tail}: Some{head <> tail}
    case _ _: None{}

def numbers(args: List<&2, String>) -> Maybe<&2, List<&2, U32>>:
  match args:
    case Nil{}: Some{Nil{}}
    case head <> tail: number_cons(U32.read(head), numbers(tail))

def flag_error(valid: Bool, output: String) -> IO(Unit):
  match valid:
    case True{}: IO.print(output)
    case False{}: IO.die(Unit, 2, "expected Boolean fixture word0or1")

def fixture_move(words: Maybe<&2, List<&2, U32>>) -> IO(Unit):
  match words:
    case Some{xh <> xl <> yh <> yl <> ah <> al <> bh <> bl <> +first <> mxh <> mxl <> myh <> myl <> rxh <> rxl <> ryh <> ryl <> +matches <> +focused <> +captured <> Nil{}}: flag_error(Bool.and(U32.is_le(captured, 1), Bool.and(U32.is_le(focused, 1), Bool.and(U32.is_le(matches, 1), Bool.and(U32.is_le(first, 1), True{})))), result_state(M.on_move(M.State{F.F64{xh, xl}, F.F64{yh, yl}, F.F64{ah, al}, F.F64{bh, bl}, U32.is_eq(first, 1)}, M.PointerMove{F.F64{mxh, mxl}, F.F64{myh, myl}, F.F64{rxh, rxl}, F.F64{ryh, ryl}, U32.is_eq(matches, 1)}, U32.is_eq(focused, 1), U32.is_eq(captured, 1))))
    case _: IO.die(Unit, 2, "invalid move fixture words")

def fixture_finish(words: Maybe<&2, List<&2, U32>>) -> IO(Unit):
  match words:
    case Some{xh <> xl <> yh <> yl <> ah <> al <> bh <> bl <> +first <> sh <> sl <> +ix <> +iy <> +smooth <> +scoping <> +focused <> +captured <> +player <> Nil{}}: flag_error(Bool.and(U32.is_le(player, 1), Bool.and(U32.is_le(captured, 1), Bool.and(U32.is_le(focused, 1), Bool.and(U32.is_le(scoping, 1), Bool.and(U32.is_le(smooth, 1), Bool.and(U32.is_le(iy, 1), Bool.and(U32.is_le(ix, 1), Bool.and(U32.is_le(first, 1), True{})))))))), result_frame(M.finish(M.State{F.F64{xh, xl}, F.F64{yh, yl}, F.F64{ah, al}, F.F64{bh, bl}, U32.is_eq(first, 1)}, M.Options{F.F64{sh, sl}, U32.is_eq(ix, 1), U32.is_eq(iy, 1), U32.is_eq(smooth, 1), U32.is_eq(scoping, 1)}, U32.is_eq(focused, 1), U32.is_eq(captured, 1), U32.is_eq(player, 1))))
    case _: IO.die(Unit, 2, "invalid finish fixture words")

def fixture_relative(words: Maybe<&2, List<&2, U32>>) -> IO(Unit):
  match words:
    case Some{xh <> xl <> yh <> yl <> ah <> al <> bh <> bl <> +first <> dxh <> dxl <> dyh <> dyl <> +focused <> +captured <> Nil{}}: flag_error(Bool.and(U32.is_le(captured, 1), Bool.and(U32.is_le(focused, 1), Bool.and(U32.is_le(first, 1), True{}))), result_state(M.relative(M.State{F.F64{xh, xl}, F.F64{yh, yl}, F.F64{ah, al}, F.F64{bh, bl}, U32.is_eq(first, 1)}, F.F64{dxh, dxl}, F.F64{dyh, dyl}, U32.is_eq(focused, 1), U32.is_eq(captured, 1))))
    case _: IO.die(Unit, 2, "invalid relative fixture words")

def fixture_pair(words: Maybe<&2, List<&2, U32>>) -> IO(Unit):
  match words:
    case Some{xh <> xl <> yh <> yl <> ah <> al <> bh <> bl <> +first <> axh <> axl <> ayh <> ayl <> arxh <> arxl <> aryh <> aryl <> +amatches <> bxh <> bxl <> byh <> byl <> brxh <> brxl <> bryh <> bryl <> +bmatches <> sh <> sl <> +ix <> +iy <> +smooth <> +scoping <> +focused <> +captured <> +player <> Nil{}}: flag_error(Bool.and(U32.is_le(player, 1), Bool.and(U32.is_le(captured, 1), Bool.and(U32.is_le(focused, 1), Bool.and(U32.is_le(scoping, 1), Bool.and(U32.is_le(smooth, 1), Bool.and(U32.is_le(iy, 1), Bool.and(U32.is_le(ix, 1), Bool.and(U32.is_le(bmatches, 1), Bool.and(U32.is_le(amatches, 1), Bool.and(U32.is_le(first, 1), True{})))))))))), result_frame(pair_initial(M.State{F.F64{xh, xl}, F.F64{yh, yl}, F.F64{ah, al}, F.F64{bh, bl}, U32.is_eq(first, 1)}, M.PointerMove{F.F64{axh, axl}, F.F64{ayh, ayl}, F.F64{arxh, arxl}, F.F64{aryh, aryl}, U32.is_eq(amatches, 1)}, M.PointerMove{F.F64{bxh, bxl}, F.F64{byh, byl}, F.F64{brxh, brxl}, F.F64{bryh, bryl}, U32.is_eq(bmatches, 1)}, M.Options{F.F64{sh, sl}, U32.is_eq(ix, 1), U32.is_eq(iy, 1), U32.is_eq(smooth, 1), U32.is_eq(scoping, 1)}, U32.is_eq(focused, 1), U32.is_eq(captured, 1), U32.is_eq(player, 1))))
    case _: IO.die(Unit, 2, "invalid pair fixture words")

def fixture_arm(words: Maybe<&2, List<&2, U32>>) -> IO(Unit):
  match words:
    case Some{xh <> xl <> yh <> yl <> ah <> al <> bh <> bl <> +first <> Nil{}}:
      flag_error(U32.is_le(first, 1), result_state(Done{M.ignore_next_move(M.State{F.F64{xh, xl}, F.F64{yh, yl}, F.F64{ah, al}, F.F64{bh, bl}, U32.is_eq(first, 1)})}))
    case _: IO.die(Unit, 2, "invalid arm fixture words")

def batch(args: List<String>) -> IO(Unit):
  match args:
    case Nil{}: IO.pure(Unit, Unit{})
    case "move" <> xh <> xl <> yh <> yl <> ah <> al <> bh <> bl <> first <> mxh <> mxl <> myh <> myl <> rxh <> rxl <> ryh <> ryl <> matches <> focused <> captured <> rest:
      do IO<Unit>:
        fixture_move(numbers([xh, xl, yh, yl, ah, al, bh, bl, first, mxh, mxl, myh, myl, rxh, rxl, ryh, ryl, matches, focused, captured]))
        batch(rest)
    case "finish" <> xh <> xl <> yh <> yl <> ah <> al <> bh <> bl <> first <> sh <> sl <> ix <> iy <> smooth <> scoping <> focused <> captured <> player <> rest:
      do IO<Unit>:
        fixture_finish(numbers([xh, xl, yh, yl, ah, al, bh, bl, first, sh, sl, ix, iy, smooth, scoping, focused, captured, player]))
        batch(rest)
    case "relative" <> xh <> xl <> yh <> yl <> ah <> al <> bh <> bl <> first <> dxh <> dxl <> dyh <> dyl <> focused <> captured <> rest:
      do IO<Unit>:
        fixture_relative(numbers([xh, xl, yh, yl, ah, al, bh, bl, first, dxh, dxl, dyh, dyl, focused, captured]))
        batch(rest)
    case "pair" <> xh <> xl <> yh <> yl <> ah <> al <> bh <> bl <> first <> axh <> axl <> ayh <> ayl <> arxh <> arxl <> aryh <> aryl <> amatches <> bxh <> bxl <> byh <> byl <> brxh <> brxl <> bryh <> bryl <> bmatches <> sh <> sl <> ix <> iy <> smooth <> scoping <> focused <> captured <> player <> rest:
      do IO<Unit>:
        fixture_pair(numbers([xh, xl, yh, yl, ah, al, bh, bl, first, axh, axl, ayh, ayl, arxh, arxl, aryh, aryl, amatches, bxh, bxl, byh, byl, brxh, brxl, bryh, bryl, bmatches, sh, sl, ix, iy, smooth, scoping, focused, captured, player]))
        batch(rest)
    case "arm" <> xh <> xl <> yh <> yl <> ah <> al <> bh <> bl <> first <> rest:
      do IO<Unit>:
        fixture_arm(numbers([xh, xl, yh, yl, ah, al, bh, bl, first]))
        batch(rest)
    case _: IO.die(Unit, 2, "expected move/finish/relative/pair/arm fixture packet")

def main() -> IO(Unit):
  do IO<Unit>:
    args : List<String> <- IO.args()
    batch(List.tail(&1, String, args))
