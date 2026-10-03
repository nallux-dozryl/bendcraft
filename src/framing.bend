import Base

# Buffer values originate in new/feed. size is the length of reversed, and
# bounds bytes before LF, including any terminal CR.
type Buffer is Data:
  Buffer{reversed: List<&2, U32>, size: U32}

type Utf8 is Data:
  Utf8{need: U32, code: U32, minimum: U32, reversed: String, count: U32}

type Progress is Data:
  Progress{buffer: Buffer, lines: List<&2, String>}

def new() -> Buffer:
  Buffer{Nil{}, 0}

def scalar(+code: U32) -> Bool:
  U32.is_le(code, 1114111) && Bool.not(U32.is_ge(code, 55296) && U32.is_le(code, 57343))

def decoded_room(room: Bool, code: U32, reversed: String, count: U32) -> Result<&2, &2, String, Utf8>:
  match room:
    case True{}: Done{Utf8{0, 0, 0, SCon{Chr{code}, reversed}, U32.add(count, 1)}}
    case False{}: Fail{"line exceeds 16384 Unicode scalar code points"}

def decoded_scalar(valid: Bool, code: U32, reversed: String, +count: U32) -> Result<&2, &2, String, Utf8>:
  match valid:
    case False{}: Fail{"invalid UTF-8 scalar or overlong encoding"}
    case True{}: decoded_room(U32.is_lt(count, 16384), code, reversed, count)

def decode_complete(last: Bool, +code: U32, +minimum: U32, need: U32, reversed: String, count: U32) -> Result<&2, &2, String, Utf8>:
  match last:
    case True{}: decoded_scalar(U32.is_ge(code, minimum) && scalar(code), code, reversed, count)
    case False{}: Done{Utf8{U32.sub(need, 1), code, minimum, reversed, count}}

def decode_continuation(valid: Bool, +byte: U32, +need: U32, code: U32, minimum: U32, reversed: String, count: U32) -> Result<&2, &2, String, Utf8>:
  match valid:
    case False{}: Fail{"expected UTF-8 continuation byte"}
    case True{}:
      decode_complete(U32.is_eq(need, 1), U32.add(U32.mul(code, 64), U32.sub(byte, 128)), minimum, need, reversed, count)

def decode_four(valid: Bool, byte: U32, reversed: String, count: U32) -> Result<&2, &2, String, Utf8>:
  match valid:
    case True{}: Done{Utf8{3, U32.sub(byte, 240), 65536, reversed, count}}
    case False{}: Fail{"invalid UTF-8 leading byte"}

def decode_three(valid: Bool, +byte: U32, reversed: String, count: U32) -> Result<&2, &2, String, Utf8>:
  match valid:
    case True{}: Done{Utf8{2, U32.sub(byte, 224), 2048, reversed, count}}
    case False{}: decode_four(U32.is_ge(byte, 240) && U32.is_le(byte, 244), byte, reversed, count)

def decode_two(valid: Bool, +byte: U32, reversed: String, count: U32) -> Result<&2, &2, String, Utf8>:
  match valid:
    case True{}: Done{Utf8{1, U32.sub(byte, 192), 128, reversed, count}}
    case False{}: decode_three(U32.is_ge(byte, 224) && U32.is_le(byte, 239), byte, reversed, count)

def decode_leading(ascii: Bool, +byte: U32, reversed: String, count: U32) -> Result<&2, &2, String, Utf8>:
  match ascii:
    case True{}: decoded_scalar(True{}, byte, reversed, count)
    case False{}: decode_two(U32.is_ge(byte, 194) && U32.is_le(byte, 223), byte, reversed, count)

def decode_byte(state: Utf8, +byte: U32) -> Result<&2, &2, String, Utf8>:
  match state:
    case Utf8{0, code, minimum, reversed, count}:
      decode_leading(U32.is_lt(byte, 128), byte, reversed, count)
    case Utf8{need, code, minimum, reversed, count}:
      decode_continuation(U32.is_ge(byte, 128) && U32.is_le(byte, 191), byte, need, code, minimum, reversed, count)

def decode_end(state: Utf8) -> Result<&2, &2, String, String>:
  match state:
    case Utf8{0, code, minimum, reversed, count}: Done{String.reverse(reversed)}
    case _: Fail{"truncated UTF-8 encoding at completed line"}

def decode_loop(bytes: List<&2, U32>, result: Result<&2, &2, String, Utf8>) -> Result<&2, &2, String, String>:
  match bytes result:
    case _ Fail{message}: Fail{message}
    case Nil{} Done{state}: decode_end(state)
    case byte <> rest Done{state}: decode_loop(rest, decode_byte(state, byte))

def trim_cr(reversed: List<&2, U32>) -> List<&2, U32>:
  match reversed:
    case 13 <> rest: rest
    case _: reversed

def completed(result: Result<&2, &2, String, String>, lines: List<&2, String>) -> Result<&2, &2, String, Progress>:
  match result:
    case Fail{message}: Fail{message}
    case Done{line}: Done{Progress{new(), line <> lines}}

def append_byte(room: Bool, byte: U32, reversed: List<&2, U32>, size: U32, lines: List<&2, String>) -> Result<&2, &2, String, Progress>:
  match room:
    case False{}: Fail{"line exceeds 65536 bytes before LF"}
    case True{}: Done{Progress{Buffer{byte <> reversed, U32.add(size, 1)}, lines}}

def feed_valid(valid: Bool, progress: Progress, byte: U32) -> Result<&2, &2, String, Progress>:
  match valid progress:
    case False{} _: Fail{"input byte exceeds 255"}
    case True{} Progress{Buffer{reversed, +size}, lines}:
      match byte:
        case 10: completed(decode_loop(List.reverse(&2, U32, trim_cr(reversed)), Done{Utf8{0, 0, 0, SNil{}, 0}}), lines)
        case _: append_byte(U32.is_lt(size, 65536), byte, reversed, size, lines)

def feed_byte(progress: Progress, +byte: U32) -> Result<&2, &2, String, Progress>:
  feed_valid(U32.is_le(byte, 255), progress, byte)

def feed_loop(bytes: List<&2, U32>, result: Result<&2, &2, String, Progress>) -> Result<&1, &1, String, Buffer & List<&2, String>>:
  match bytes result:
    case _ Fail{message}: Fail{message}
    case Nil{} Done{Progress{buffer, lines}}:
      Done{(buffer, List.reverse(&2, String, lines))}
    case byte <> rest Done{progress}: feed_loop(rest, feed_byte(progress, byte))

# One feed is atomic on failure: no buffer or successful prefix lines escape.
# Partial bytes are not decoded until LF, so codepoints may span any reads.
def feed(buffer: Buffer, bytes: List<&2, U32>) -> Result<&1, &1, String, Buffer & List<&2, String>>:
  feed_loop(bytes, Done{Progress{buffer, Nil{}}})

def segments_loop(bytes: List<&2, U32>, reversed: List<&2, U32>, completed: List<&2, List<&2, U32>>) -> List<&2, List<&2, U32>>:
  match bytes reversed:
    case Nil{} Nil{}: List.reverse(&2, List<&2, U32>, completed)
    case Nil{} _: List.reverse(&2, List<&2, U32>, List.reverse(&2, U32, reversed) <> completed)
    case 10 <> rest _: segments_loop(rest, Nil{}, List.reverse(&2, U32, 10 <> reversed) <> completed)
    case byte <> rest _: segments_loop(rest, byte <> reversed, completed)

# Preserve each LF in its own completed segment, followed by a nonempty tail
# if present. Empty input yields no segments. Feed/dispatch each segment before
# the next so malformed later records cannot erase an earlier valid record.
def segments(bytes: List<&2, U32>) -> List<&2, List<&2, U32>>:
  segments_loop(bytes, Nil{}, Nil{})

# NDJSON requires a terminating LF. Closing a connection never dispatches a
# partial final record, even when its bytes happen to be complete UTF-8/JSON.
def finish(buffer: Buffer) -> Result<&1, &1, String, Unit>:
  match buffer:
    case Buffer{Nil{}, 0}: Done{Unit{}}
    case _: Fail{"unterminated NDJSON record at EOF"}
