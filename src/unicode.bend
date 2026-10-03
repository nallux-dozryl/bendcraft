import Base

# Ordinary strict UTF-8. This is deliberately separate from NBT modified UTF-8.
# Public entry points are decode and encode; helper states are implementation
# details and must not be forged by callers.
type Encoder is Data:
  Encoder{room: Nat, reversed: List<&2, U32>}

type Decoder is Data:
  Decoder{need: U32, code: U32, minimum: U32, room: Nat, reversed: String}

def scalar(+code: U32) -> Bool:
  U32.is_le(code, 1114111) && Bool.not(U32.is_ge(code, 55296) && U32.is_le(code, 57343))

def decoded_put(room: Nat, code: U32, reversed: String) -> Result<&2, &2, String, Decoder>:
  match room:
    case 0n: Fail{"UTF-8 scalar limit exceeded"}
    case 1n+remaining: Done{Decoder{0, 0, 0, remaining, SCon{Chr{code}, reversed}}}

def decoded_scalar(valid: Bool, room: Nat, code: U32, reversed: String) -> Result<&2, &2, String, Decoder>:
  match valid:
    case False{}: Fail{"invalid UTF-8 scalar or overlong encoding"}
    case True{}: decoded_put(room, code, reversed)

def decode_complete(last: Bool, +code: U32, +minimum: U32, need: U32, room: Nat, reversed: String) -> Result<&2, &2, String, Decoder>:
  match last:
    case True{}: decoded_scalar(U32.is_ge(code, minimum) && scalar(code), room, code, reversed)
    case False{}: Done{Decoder{U32.sub(need, 1), code, minimum, room, reversed}}

def decode_continuation(valid: Bool, +byte: U32, +need: U32, code: U32, minimum: U32, room: Nat, reversed: String) -> Result<&2, &2, String, Decoder>:
  match valid:
    case False{}: Fail{"expected UTF-8 continuation byte"}
    case True{}:
      # A valid leading byte and at most three continuations keep code below
      # 2^21. Neither multiplication nor addition can overflow U32.
      decode_complete(U32.is_eq(need, 1), U32.add(U32.mul(code, 64), U32.sub(byte, 128)), minimum, need, room, reversed)

def decode_four(valid: Bool, byte: U32, room: Nat, reversed: String) -> Result<&2, &2, String, Decoder>:
  match valid:
    case True{}: Done{Decoder{3, U32.sub(byte, 240), 65536, room, reversed}}
    case False{}: Fail{"invalid UTF-8 leading byte"}

def decode_three(valid: Bool, +byte: U32, room: Nat, reversed: String) -> Result<&2, &2, String, Decoder>:
  match valid:
    case True{}: Done{Decoder{2, U32.sub(byte, 224), 2048, room, reversed}}
    case False{}: decode_four(U32.is_ge(byte, 240) && U32.is_le(byte, 244), byte, room, reversed)

def decode_two(valid: Bool, +byte: U32, room: Nat, reversed: String) -> Result<&2, &2, String, Decoder>:
  match valid:
    case True{}: Done{Decoder{1, U32.sub(byte, 192), 128, room, reversed}}
    case False{}: decode_three(U32.is_ge(byte, 224) && U32.is_le(byte, 239), byte, room, reversed)

def decode_leading(ascii: Bool, +byte: U32, room: Nat, reversed: String) -> Result<&2, &2, String, Decoder>:
  match ascii:
    case True{}: decoded_put(room, byte, reversed)
    case False{}: decode_two(U32.is_ge(byte, 194) && U32.is_le(byte, 223), byte, room, reversed)

def decode_valid(valid: Bool, state: Decoder, +byte: U32) -> Result<&2, &2, String, Decoder>:
  match valid state:
    case False{} _: Fail{"input byte exceeds 255"}
    case True{} Decoder{0, code, minimum, room, reversed}:
      decode_leading(U32.is_lt(byte, 128), byte, room, reversed)
    case True{} Decoder{need, code, minimum, room, reversed}:
      decode_continuation(U32.is_ge(byte, 128) && U32.is_le(byte, 191), byte, need, code, minimum, room, reversed)

def decode_byte(state: Decoder, +byte: U32) -> Result<&2, &2, String, Decoder>:
  decode_valid(U32.is_le(byte, 255), state, byte)

def decode_end(state: Decoder) -> Result<&2, &2, String, String>:
  match state:
    case Decoder{0, code, minimum, room, reversed}: Done{String.reverse(reversed)}
    case _: Fail{"incomplete UTF-8 sequence"}

def decode_loop(bytes: List<&2, U32>, result: Result<&2, &2, String, Decoder>) -> Result<&2, &2, String, String>:
  match bytes result:
    case _ Fail{message}: Fail{message}
    case Nil{} Done{state}: decode_end(state)
    case byte <> rest Done{state}: decode_loop(rest, decode_byte(state, byte))

# max_scalars bounds the resulting String's scalar count, not its byte count.
# Native Nat is 48-bit. Only predecessor operations consume this caller budget;
# no Nat length sum, successor, subtraction wrap, or conversion is needed.
def decode(max_scalars: Nat, bytes: List<&2, U32>) -> Result<&2, &2, String, String>:
  decode_loop(bytes, Done{Decoder{0, 0, 0, max_scalars, SNil{}}})

# Debit a canonical scalar's one-to-four bytes into the reversed output.
# On exhaustion the partial output is discarded, so encode is atomic.
def encoded_put(bytes: List<&2, U32>, room: Nat, reversed: List<&2, U32>) -> Result<&2, &2, String, Encoder>:
  match bytes room:
    case Nil{} _: Done{Encoder{room, reversed}}
    case _ 0n: Fail{"UTF-8 byte limit exceeded"}
    case byte <> rest 1n+remaining: encoded_put(rest, remaining, byte <> reversed)

def encode_four(+code: U32, room: Nat, reversed: List<&2, U32>) -> Result<&2, &2, String, Encoder>:
  encoded_put([
    U32.add(240, U32.shrn(code, 18n)),
    U32.add(128, U32.and(U32.shrn(code, 12n), 63)),
    U32.add(128, U32.and(U32.shrn(code, 6n), 63)),
    U32.add(128, U32.and(code, 63))], room, reversed)

def encode_three(small: Bool, +code: U32, room: Nat, reversed: List<&2, U32>) -> Result<&2, &2, String, Encoder>:
  match small:
    case False{}: encode_four(code, room, reversed)
    case True{}: encoded_put([
      U32.add(224, U32.shrn(code, 12n)),
      U32.add(128, U32.and(U32.shrn(code, 6n), 63)),
      U32.add(128, U32.and(code, 63))], room, reversed)

def encode_two(small: Bool, +code: U32, room: Nat, reversed: List<&2, U32>) -> Result<&2, &2, String, Encoder>:
  match small:
    case False{}: encode_three(U32.is_lt(code, 65536), code, room, reversed)
    case True{}: encoded_put([
      U32.add(192, U32.shrn(code, 6n)),
      U32.add(128, U32.and(code, 63))], room, reversed)

def encode_ascii(ascii: Bool, +code: U32, room: Nat, reversed: List<&2, U32>) -> Result<&2, &2, String, Encoder>:
  match ascii:
    case True{}: encoded_put([code], room, reversed)
    case False{}: encode_two(U32.is_lt(code, 2048), code, room, reversed)

def encode_valid(valid: Bool, +code: U32, room: Nat, reversed: List<&2, U32>) -> Result<&2, &2, String, Encoder>:
  match valid:
    case False{}: Fail{"invalid Unicode scalar in String"}
    case True{}: encode_ascii(U32.is_lt(code, 128), code, room, reversed)

def encode_char(+code: U32, room: Nat, reversed: List<&2, U32>) -> Result<&2, &2, String, Encoder>:
  encode_valid(scalar(code), code, room, reversed)

def encode_loop(text: String, result: Result<&2, &2, String, Encoder>) -> Result<&2, &2, String, List<&2, U32>>:
  match text result:
    case _ Fail{message}: Fail{message}
    case SNil{} Done{Encoder{room, reversed}}: Done{List.reverse(&2, U32, reversed)}
    case SCon{Chr{code}, rest} Done{Encoder{room, reversed}}:
      encode_loop(rest, encode_char(code, room, reversed))

# max_bytes bounds output bytes. Invalid forged Chr values are rejected even
# though Base's Char/String constructors permit them. NUL is one byte 0x00.
def encode(max_bytes: Nat, text: String) -> Result<&2, &2, String, List<&2, U32>>:
  encode_loop(text, Done{Encoder{max_bytes, Nil{}}})
