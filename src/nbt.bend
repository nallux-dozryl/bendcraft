import Base

# Physical, uncompressed Java NBT. Numeric fields are unsigned raw bit patterns.
type Word64 is Data:
  Word64{hi: U32, lo: U32}

type Text is Data:
  Text{units: List<&2, U32>}

type Value is Data:
  End{}
  Byte{bits: U32}
  Short{bits: U32}
  Int{bits: U32}
  Long{bits: Word64}
  Float{bits: U32}
  Double{bits: Word64}
  ByteArray{values: List<&2, U32>}
  StringTag{text: Text}
  ListTag{element: U32, values: List<&2, Value>}
  Compound{members: List<&2, Member>}
  IntArray{values: List<&2, U32>}
  LongArray{values: List<&2, Word64>}

type Member is Data:
  Member{name: Text, value: Value}

type Root is Data:
  Root{name: Text, value: Value}

type Limits is Data:
  Limits{max_bytes: U32, max_depth: U32, max_elements: U32}

def default_limits() -> Limits:
  Limits{16777216, 512, 1048576}

def choose(-A: Data, yes: A, no: A, test: Bool) -> A:
  match test:
    case True{}: yes
    case False{}: no

def lazy_choose(-A: Type, yes: Unit -> A, no: Unit -> A, test: Bool) -> A:
  match test:
    case True{}: yes(Unit{})
    case False{}: no(Unit{})

def tag(value: Value) -> U32:
  match value:
    case End{}: 0
    case Byte{bits}: 1
    case Short{bits}: 2
    case Int{bits}: 3
    case Long{bits}: 4
    case Float{bits}: 5
    case Double{bits}: 6
    case ByteArray{values}: 7
    case StringTag{text}: 8
    case ListTag{element, values}: 9
    case Compound{members}: 10
    case IntArray{values}: 11
    case LongArray{values}: 12

type Reader is Data:
  Reader{bytes: List<&2, U32>, offset: U32}

type Read<-A: Data> is Data:
  Read{reader: Reader, value: A}

def fault(+offset: U32, message: String) -> String:
  message ++ " at byte " ++ U32.show(offset)

def scan(fuel: Nat, bytes: List<&2, U32>, +size: U32) -> Result<&2, &2, String, U32>:
  match fuel bytes:
    case _ Nil{}: Done{size}
    case 0n h <> t: Fail{"NBT input byte limit exceeded"}
    case 1n+rest +h <> t:
      choose(Result<&2, &2, String, U32>, scan(rest, t, U32.add(size, 1)),
        Fail{fault(size, "input element is not a byte")}, U32.is_le(h, 255))

def read_word(count: Nat, reader: Reader, +hi: U32, +lo: U32) -> Result<&2, &2, String, Read<Word64>>:
  match count reader:
    case 0n Reader{bytes, offset}: Done{Read{Reader{bytes, offset}, Word64{hi, lo}}}
    case 1n+rest Reader{Nil{}, offset}: Fail{fault(offset, "truncated NBT")}
    case 1n+rest Reader{h <> t, offset}:
      read_word(rest, Reader{t, U32.add(offset, 1)}, U32.or(U32.shln(hi, 8n), U32.shrn(lo, 24n)), U32.add(U32.shln(lo, 8n), h))

def read_elements(count: Nat, chunk: Nat, +width: Nat, reader: Reader, +hi: U32, +lo: U32, values: List<&2, Word64>) -> Result<&2, &2, String, Read<List<&2, Word64>>>:
  match count chunk reader:
    case 0n _ Reader{bytes, offset}: Done{Read{Reader{bytes, offset}, List.reverse(&2, Word64, values)}}
    case 1n+rest 0n Reader{bytes, offset}:
      read_elements(rest, width, width, Reader{bytes, offset}, 0, 0, Word64{hi, lo} <> values)
    case 1n+rest 1n+c Reader{Nil{}, offset}: Fail{fault(offset, "truncated NBT array")}
    case 1n+rest 1n+c Reader{h <> t, offset}:
      read_elements(1n+rest, c, width, Reader{t, U32.add(offset, 1)}, U32.or(U32.shln(hi, 8n), U32.shrn(lo, 24n)), U32.add(U32.shln(lo, 8n), h), values)

def low_words(words: List<&2, Word64>) -> List<&2, U32>:
  match words:
    case Nil{}: Nil{}
    case Word64{hi, lo} <> rest: lo <> low_words(rest)

# Decode the 1/2/3-byte grammar used by DataInputStream.readUTF, preserving UTF-16.
def utf_units(count: Nat, reader: Reader, phase: U32, +code: U32, +units: List<&2, U32>) -> Result<&2, &2, String, Read<Text>>:
  match count reader phase:
    case 0n Reader{bytes, offset} 0: Done{Read{Reader{bytes, offset}, Text{List.reverse(&2, U32, units)}}}
    case 0n Reader{bytes, offset} _: Fail{fault(offset, "partial modified UTF-8 character")}
    case 1n+rest Reader{Nil{}, offset} _: Fail{fault(offset, "truncated modified UTF-8")}
    case 1n+ +rest Reader{+h <> t, +offset} 0:
      +next : Reader = Reader{t, U32.add(offset, 1)}
      lazy_choose(Result<&2, &2, String, Read<Text>>, u => utf_units(rest, next, 0, 0, h <> units),
        u => lazy_choose(Result<&2, &2, String, Read<Text>>, u => utf_units(rest, next, 1, U32.and(h, 31), units),
          u => lazy_choose(Result<&2, &2, String, Read<Text>>, u => utf_units(rest, next, 2, U32.and(h, 15), units),
            u => Fail{fault(offset, "invalid modified UTF-8 leading byte")}, U32.is_ge(h, 224) && U32.is_le(h, 239)),
          U32.is_ge(h, 192) && U32.is_le(h, 223)), U32.is_le(h, 127))
    case 1n+rest Reader{+h <> t, +offset} 1:
      lazy_choose(Result<&2, &2, String, Read<Text>>, u => utf_units(rest, Reader{t, U32.add(offset, 1)}, 0, 0, U32.add(U32.mul(code, 64), U32.and(h, 63)) <> units),
        u => Fail{fault(offset, "invalid modified UTF-8 continuation")}, U32.is_eq(U32.and(h, 192), 128))
    case 1n+rest Reader{+h <> t, +offset} _:
      lazy_choose(Result<&2, &2, String, Read<Text>>, u => utf_units(rest, Reader{t, U32.add(offset, 1)}, 1, U32.add(U32.mul(code, 64), U32.and(h, 63)), units),
        u => Fail{fault(offset, "invalid modified UTF-8 continuation")}, U32.is_eq(U32.and(h, 192), 128))

def read_text_length(result: Result<&2, &2, String, Read<Word64>>) -> Result<&2, &2, String, Read<Text>>:
  match result:
    case Fail{message}: Fail{message}
    case Done{Read{reader, Word64{hi, lo}}}: utf_units(U32.to_nat(lo), reader, 0, 0, Nil{})

def read_text(reader: Reader) -> Result<&2, &2, String, Read<Text>>:
  read_text_length(read_word(2n, reader, 0, 0))

def octets(count: Nat, +value: U32) -> List<&2, U32>:
  match count:
    case 0n: Nil{}
    case 1n+rest: List.append(&2, U32, octets(rest, U32.shrn(value, 8n)), U32.and(value, 255) <> Nil{})

def wide_octets(value: Word64) -> List<&2, U32>:
  match value:
    case Word64{hi, lo}: List.append(&2, U32, octets(4n, hi), octets(4n, lo))


type DecodeFrame is Data:
  ListFrame{element: U32, left: U32, values: List<&2, Value>}
  CompoundFrame{count: U32, members: List<&2, Member>, name: Text}

type DecodeMode is Data:
  Need{kind: U32}
  ListWant{element: U32, left: U32, values: List<&2, Value>}
  CompoundWant{count: U32, members: List<&2, Member>}
  Produced{value: Value}

type DecodeState is Data:
  DecodeState{reader: Reader, name: Text, frames: List<&2, DecodeFrame>, mode: DecodeMode, depth: U32, limits: Limits}

type DecodeStep is Data:
  DecodeContinue{state: DecodeState}
  DecodeFinished{root: Root, reader: Reader}
  DecodeRejected{message: String}

def resume(state: DecodeState, reader: Reader, mode: DecodeMode) -> DecodeStep:
  match state:
    case DecodeState{old, name, frames, unused, depth, limits}:
      DecodeContinue{DecodeState{reader, name, frames, mode, depth, limits}}

def push_frame(state: DecodeState, reader: Reader, frame: DecodeFrame, mode: DecodeMode) -> DecodeStep:
  match state:
    case DecodeState{old, name, frames, unused, depth, limits}:
      DecodeContinue{DecodeState{reader, name, frame <> frames, mode, depth, limits}}

def open_decode(state: DecodeState, reader: Reader, mode: DecodeMode) -> DecodeStep:
  match state:
    case DecodeState{old, name, frames, unused, +depth, +limits}:
      match limits:
        case Limits{bytes, max_depth, elements}:
          choose(DecodeStep, DecodeContinue{DecodeState{reader, name, frames, mode, U32.add(depth, 1), limits}},
            DecodeRejected{"NBT nesting limit exceeded"}, U32.is_lt(depth, max_depth))

def close_decode(state: DecodeState, reader: Reader, value: Value) -> DecodeStep:
  match state:
    case DecodeState{old, name, frames, unused, depth, limits}:
      DecodeContinue{DecodeState{reader, name, frames, Produced{value}, U32.sub(depth, 1), limits}}

def scalar_value(kind: U32, bits: Word64) -> Value:
  match kind bits:
    case 1 Word64{hi, lo}: Byte{lo}
    case 2 Word64{hi, lo}: Short{lo}
    case 3 Word64{hi, lo}: Int{lo}
    case 4 _: Long{bits}
    case 5 Word64{hi, lo}: Float{lo}
    case _ _: Double{bits}

def scalar_read(state: DecodeState, kind: U32, result: Result<&2, &2, String, Read<Word64>>) -> DecodeStep:
  match result:
    case Fail{message}: DecodeRejected{message}
    case Done{Read{reader, bits}}: resume(state, reader, Produced{scalar_value(kind, bits)})

def string_read(state: DecodeState, result: Result<&2, &2, String, Read<Text>>) -> DecodeStep:
  match result:
    case Fail{message}: DecodeRejected{message}
    case Done{Read{reader, text}}: resume(state, reader, Produced{StringTag{text}})

def array_value(kind: U32, values: List<&2, Word64>) -> Value:
  match kind:
    case 7: ByteArray{low_words(values)}
    case 11: IntArray{low_words(values)}
    case _: LongArray{values}

def array_read(state: DecodeState, kind: U32, result: Result<&2, &2, String, Read<List<&2, Word64>>>) -> DecodeStep:
  match result:
    case Fail{message}: DecodeRejected{message}
    case Done{Read{reader, values}}: resume(state, reader, Produced{array_value(kind, values)})

def array_width(kind: U32) -> Nat:
  match kind:
    case 7: 1n
    case 11: 4n
    case _: 8n

def array_header(+state: DecodeState, +kind: U32, result: Result<&2, &2, String, Read<Word64>>) -> DecodeStep:
  match state result:
    case DecodeState{old, name, frames, mode, depth, Limits{bytes, levels, +elements}} Fail{message}: DecodeRejected{message}
    case DecodeState{old, name, frames, mode, depth, Limits{bytes, levels, +elements}} Done{Read{reader, Word64{hi, +count}}}:
      lazy_choose(DecodeStep, u => array_read(state, kind, read_elements(U32.to_nat(count), array_width(kind), array_width(kind), reader, 0, 0, Nil{})),
        u => DecodeRejected{"negative or excessive NBT array length"}, U32.is_le(count, 2147483647) && U32.is_le(count, elements))

def list_header(+state: DecodeState, result: Result<&2, &2, String, Read<Word64>>) -> DecodeStep:
  match state result:
    case DecodeState{old, name, frames, mode, depth, Limits{bytes, levels, elements}} Fail{message}: DecodeRejected{message}
    case DecodeState{old, name, frames, mode, depth, Limits{bytes, levels, elements}} Done{Read{reader, Word64{+element, +count}}}:
      choose(DecodeStep, open_decode(state, reader, ListWant{element, count, Nil{}}),
        DecodeRejected{"invalid NBT list type or length"},
        U32.is_le(count, 2147483647) && U32.is_le(count, elements) && U32.is_le(element, 12) && (U32.is_ne(element, 0) || U32.is_eq(count, 0)))

def named_member_read(state: DecodeState, kind: U32, count: U32, members: List<&2, Member>, result: Result<&2, &2, String, Read<Text>>) -> DecodeStep:
  match result:
    case Fail{message}: DecodeRejected{message}
    case Done{Read{reader, name}}:
      push_frame(state, reader, CompoundFrame{count, members, name}, Need{kind})

def compound_header(+state: DecodeState, +count: U32, +members: List<&2, Member>, result: Result<&2, &2, String, Read<Word64>>) -> DecodeStep:
  match state result:
    case DecodeState{old, name, frames, mode, depth, Limits{bytes, levels, elements}} Fail{message}: DecodeRejected{message}
    case DecodeState{old, name, frames, mode, depth, Limits{bytes, levels, elements}} Done{Read{reader, Word64{hi, 0}}}:
      close_decode(state, reader, Compound{List.reverse(&2, Member, members)})
    case DecodeState{old, name, frames, mode, depth, Limits{bytes, levels, elements}} Done{Read{+reader, Word64{hi, +kind}}}:
      lazy_choose(DecodeStep, u => named_member_read(state, kind, U32.add(count, 1), members, read_text(reader)),
        u => DecodeRejected{"unknown NBT tag or compound member limit exceeded"}, U32.is_le(kind, 12) && U32.is_lt(count, elements))

def produced(state: DecodeState, value: Value) -> DecodeStep:
  match state:
    case DecodeState{reader, name, Nil{}, mode, depth, limits}: DecodeFinished{Root{name, value}, reader}
    case DecodeState{reader, name, ListFrame{element, left, values} <> rest, mode, depth, limits}:
      DecodeContinue{DecodeState{reader, name, rest, ListWant{element, left, value <> values}, depth, limits}}
    case DecodeState{reader, name, CompoundFrame{count, members, key} <> rest, mode, depth, limits}:
      DecodeContinue{DecodeState{reader, name, rest, CompoundWant{count, Member{key, value} <> members}, depth, limits}}

def decode_step(+state: DecodeState) -> DecodeStep:
  match state:
    case DecodeState{+reader, name, frames, Need{kind}, depth, limits}:
      match kind:
        case 1: scalar_read(state, 1, read_word(1n, reader, 0, 0))
        case 2: scalar_read(state, 2, read_word(2n, reader, 0, 0))
        case 3: scalar_read(state, 3, read_word(4n, reader, 0, 0))
        case 4: scalar_read(state, 4, read_word(8n, reader, 0, 0))
        case 5: scalar_read(state, 5, read_word(4n, reader, 0, 0))
        case 6: scalar_read(state, 6, read_word(8n, reader, 0, 0))
        case 7: array_header(state, 7, read_word(4n, reader, 0, 0))
        case 8: string_read(state, read_text(reader))
        case 9: list_header(state, read_word(5n, reader, 0, 0))
        case 10: open_decode(state, reader, CompoundWant{0, Nil{}})
        case 11: array_header(state, 11, read_word(4n, reader, 0, 0))
        case 12: array_header(state, 12, read_word(4n, reader, 0, 0))
        case _: DecodeRejected{"unknown NBT payload tag"}
    case DecodeState{reader, name, frames, ListWant{element, 0, values}, depth, limits}:
      close_decode(state, reader, ListTag{element, List.reverse(&2, Value, values)})
    case DecodeState{reader, name, frames, ListWant{element, left, values}, depth, limits}:
      push_frame(state, reader, ListFrame{element, U32.sub(left, 1), values}, Need{element})
    case DecodeState{+reader, name, frames, CompoundWant{count, members}, depth, limits}:
      compound_header(state, count, members, read_word(1n, reader, 0, 0))
    case DecodeState{reader, name, frames, Produced{value}, depth, limits}: produced(state, value)

def complete(root: Root, reader: Reader) -> Result<&2, &2, String, Root>:
  match reader:
    case Reader{Nil{}, offset}: Done{root}
    case Reader{h <> t, offset}: Fail{fault(offset, "trailing NBT data")}

def decode_run(fuel: Nat, step: DecodeStep) -> Result<&2, &2, String, Root>:
  match fuel step:
    case _ DecodeFinished{root, reader}: complete(root, reader)
    case _ DecodeRejected{message}: Fail{message}
    case 0n DecodeContinue{state}: Fail{"NBT decode transition budget exceeded"}
    case 1n+rest DecodeContinue{state}: decode_run(rest, decode_step(state))

def decode_root_name(limits: Limits, fuel: Nat, kind: U32, result: Result<&2, &2, String, Read<Text>>) -> Result<&2, &2, String, Root>:
  match result:
    case Fail{message}: Fail{message}
    case Done{Read{reader, name}}:
      decode_run(fuel, DecodeContinue{DecodeState{reader, name, Nil{}, Need{kind}, 0, limits}})

def decode_root_tag(+limits: Limits, +size: U32, result: Result<&2, &2, String, Read<Word64>>) -> Result<&2, &2, String, Root>:
  match result:
    case Fail{message}: Fail{message}
    case Done{Read{reader, Word64{hi, 0}}}: complete(Root{Text{Nil{}}, End{}}, reader)
    case Done{Read{reader, Word64{hi, +kind}}}:
      lazy_choose(Result<&2, &2, String, Root>, u => decode_root_name(limits, Nat.add(16n, Nat.mul(4n, U32.to_nat(size))), kind, read_text(reader)),
        u => Fail{"unknown NBT root tag"}, U32.is_le(kind, 12))

def decode_scanned(limits: Limits, bytes: List<&2, U32>, result: Result<&2, &2, String, U32>) -> Result<&2, &2, String, Root>:
  match result:
    case Fail{message}: Fail{message}
    case Done{size}: decode_root_tag(limits, size, read_word(1n, Reader{bytes, 0}, 0, 0))

def decode_with(+limits: Limits, +bytes: List<&2, U32>) -> Result<&2, &2, String, Root>:
  match limits:
    case Limits{max_bytes, depth, elements}:
      decode_scanned(limits, bytes, scan(U32.to_nat(max_bytes), bytes, 0))

def decode(bytes: List<&2, U32>) -> Result<&2, &2, String, Root>:
  decode_with(default_limits(), bytes)

type TextBytes is Data:
  TextBytes{bytes: List<&2, U32>, count: U32}

def unit_octets(+unit: U32) -> List<&2, U32>:
  choose(List<&2, U32>, 192 <> 128 <> Nil{},
    choose(List<&2, U32>, unit <> Nil{},
      choose(List<&2, U32>, U32.add(192, U32.shrn(unit, 6n)) <> U32.add(128, U32.and(unit, 63)) <> Nil{},
        U32.add(224, U32.shrn(unit, 12n)) <> U32.add(128, U32.and(U32.shrn(unit, 6n), 63)) <> U32.add(128, U32.and(unit, 63)) <> Nil{}, U32.is_le(unit, 2047)), U32.is_le(unit, 127)), U32.is_eq(unit, 0))

def unit_width(+unit: U32) -> U32:
  choose(U32, 2, choose(U32, 1, choose(U32, 2, 3, U32.is_le(unit, 2047)), U32.is_le(unit, 127)), U32.is_eq(unit, 0))

def text_cons(+unit: U32, result: Result<&2, &2, String, TextBytes>) -> Result<&2, &2, String, TextBytes>:
  match result:
    case Fail{message}: Fail{message}
    case Done{TextBytes{bytes, +count}}:
      choose(Result<&2, &2, String, TextBytes>, Done{TextBytes{List.append(&2, U32, unit_octets(unit), bytes), U32.add(count, unit_width(unit))}},
        Fail{"invalid UTF-16 unit or modified UTF-8 byte length exceeds 65535"}, U32.is_le(unit, 65535) && U32.is_le(U32.add(count, unit_width(unit)), 65535))

def text_bytes(units: List<&2, U32>) -> Result<&2, &2, String, TextBytes>:
  match units:
    case Nil{}: Done{TextBytes{Nil{}, 0}}
    case h <> t: text_cons(h, text_bytes(t))

def text_prefix(result: Result<&2, &2, String, TextBytes>) -> Result<&2, &2, String, List<&2, U32>>:
  match result:
    case Fail{message}: Fail{message}
    case Done{TextBytes{bytes, count}}: Done{List.append(&2, U32, octets(2n, count), bytes)}

def encode_text(text: Text) -> Result<&2, &2, String, List<&2, U32>>:
  match text:
    case Text{units}: text_prefix(text_bytes(units))

def length_bound(-A: Data, fuel: Nat, values: List<&2, A>, +count: U32) -> Result<&2, &2, String, U32>:
  match fuel values:
    case _ Nil{}: Done{count}
    case 0n h <> t: Fail{"NBT container element limit exceeded"}
    case 1n+rest h <> t: length_bound(A, rest, t, U32.add(count, 1))

def count_values(-A: Data, limits: Limits, values: List<&2, A>) -> Result<&2, &2, String, U32>:
  match limits:
    case Limits{bytes, depth, +elements}:
      length_bound(A, U32.to_nat(choose(U32, elements, 2147483647, U32.is_le(elements, 2147483647))), values, 0)

def bytes_join(prefix: List<&2, U32>, result: Result<&2, &2, String, List<&2, U32>>) -> Result<&2, &2, String, List<&2, U32>>:
  match result:
    case Fail{message}: Fail{message}
    case Done{bytes}: Done{List.append(&2, U32, prefix, bytes)}

def word_cons(width: Nat, +maximum: U32, +value: U32, result: Result<&2, &2, String, List<&2, U32>>) -> Result<&2, &2, String, List<&2, U32>>:
  choose(Result<&2, &2, String, List<&2, U32>>, bytes_join(octets(width, value), result), Fail{"NBT numeric payload out of range"}, U32.is_le(value, maximum))

def word_array(values: List<&2, U32>, +width: Nat, +maximum: U32) -> Result<&2, &2, String, List<&2, U32>>:
  match values:
    case Nil{}: Done{Nil{}}
    case h <> t: word_cons(width, maximum, h, word_array(t, width, maximum))

def long_array(values: List<&2, Word64>) -> List<&2, U32>:
  match values:
    case Nil{}: Nil{}
    case h <> t: List.append(&2, U32, wide_octets(h), long_array(t))

type Buffer is Data:
  Buffer{reversed: List<&2, U32>, size: U32}

def write_bytes(bytes: List<&2, U32>, buffer: Buffer, +limits: Limits) -> Result<&2, &2, String, Buffer>:
  match bytes buffer limits:
    case Nil{} _ _: Done{buffer}
    case h <> t Buffer{reversed, +size} Limits{max_bytes, depth, elements}:
      lazy_choose(Result<&2, &2, String, Buffer>, u => write_bytes(t, Buffer{h <> reversed, U32.add(size, 1)}, limits),
        u => Fail{"NBT output byte limit exceeded"}, U32.is_lt(size, max_bytes))

type EncodeTask is Data:
  Payload{value: Value, depth: U32}
  ListItems{element: U32, values: List<&2, Value>, depth: U32}
  CompoundItems{members: List<&2, Member>, depth: U32}

type EncodeState is Data:
  EncodeState{tasks: List<&2, EncodeTask>, buffer: Buffer, limits: Limits}

type EncodeStep is Data:
  EncodeContinue{state: EncodeState}
  EncodeFinished{bytes: List<&2, U32>}
  EncodeRejected{message: String}

def written(tasks: List<&2, EncodeTask>, limits: Limits, result: Result<&2, &2, String, Buffer>) -> EncodeStep:
  match result:
    case Fail{message}: EncodeRejected{message}
    case Done{buffer}: EncodeContinue{EncodeState{tasks, buffer, limits}}

def emit(tasks: List<&2, EncodeTask>, buffer: Buffer, +limits: Limits, result: Result<&2, &2, String, List<&2, U32>>) -> EncodeStep:
  match result:
    case Fail{message}: EncodeRejected{message}
    case Done{bytes}: written(tasks, limits, write_bytes(bytes, buffer, limits))

def array_encode(tasks: List<&2, EncodeTask>, buffer: Buffer, +limits: Limits, +kind: U32, values: List<&2, U32>, result: Result<&2, &2, String, U32>) -> EncodeStep:
  match result:
    case Fail{message}: EncodeRejected{message}
    case Done{count}:
      emit(tasks, buffer, limits, bytes_join(octets(4n, count), word_array(values, array_width(kind), choose(U32, 255, 4294967295, U32.is_eq(kind, 7)))))

def long_array_encode(tasks: List<&2, EncodeTask>, buffer: Buffer, limits: Limits, values: List<&2, Word64>, result: Result<&2, &2, String, U32>) -> EncodeStep:
  match result:
    case Fail{message}: EncodeRejected{message}
    case Done{count}: emit(tasks, buffer, limits, Done{List.append(&2, U32, octets(4n, count), long_array(values))})

def list_encode(tasks: List<&2, EncodeTask>, buffer: Buffer, +limits: Limits, +depth: U32, +element: U32, +values: List<&2, Value>, result: Result<&2, &2, String, U32>) -> EncodeStep:
  match limits result:
    case Limits{bytes, max_depth, elements} Fail{message}: EncodeRejected{message}
    case Limits{bytes, max_depth, elements} Done{+count}:
      lazy_choose(EncodeStep, u => emit(ListItems{element, values, U32.add(depth, 1)} <> tasks, buffer, limits, Done{element <> octets(4n, count)}),
        u => EncodeRejected{"invalid NBT list type or nesting limit exceeded"}, U32.is_lt(depth, max_depth) && U32.is_le(element, 12) && (U32.is_ne(element, 0) || U32.is_eq(count, 0)))

def compound_encode(tasks: List<&2, EncodeTask>, buffer: Buffer, +limits: Limits, +depth: U32, members: List<&2, Member>, result: Result<&2, &2, String, U32>) -> EncodeStep:
  match limits result:
    case Limits{bytes, max_depth, elements} Fail{message}: EncodeRejected{message}
    case Limits{bytes, max_depth, elements} Done{count}:
      choose(EncodeStep, EncodeContinue{EncodeState{CompoundItems{members, U32.add(depth, 1)} <> tasks, buffer, limits}},
        EncodeRejected{"NBT nesting limit exceeded"}, U32.is_lt(depth, max_depth))

def encode_payload(value: Value, depth: U32, tasks: List<&2, EncodeTask>, buffer: Buffer, +limits: Limits) -> EncodeStep:
  match value:
    case End{}: EncodeRejected{"TAG_End cannot be a value payload"}
    case Byte{+bits}: emit(tasks, buffer, limits, word_cons(1n, 255, bits, Done{Nil{}}))
    case Short{+bits}: emit(tasks, buffer, limits, word_cons(2n, 65535, bits, Done{Nil{}}))
    case Int{bits}: emit(tasks, buffer, limits, Done{octets(4n, bits)})
    case Long{bits}: emit(tasks, buffer, limits, Done{wide_octets(bits)})
    case Float{bits}: emit(tasks, buffer, limits, Done{octets(4n, bits)})
    case Double{bits}: emit(tasks, buffer, limits, Done{wide_octets(bits)})
    case ByteArray{+values}: array_encode(tasks, buffer, limits, 7, values, count_values(U32, limits, values))
    case StringTag{text}: emit(tasks, buffer, limits, encode_text(text))
    case ListTag{element, +values}: list_encode(tasks, buffer, limits, depth, element, values, count_values(Value, limits, values))
    case Compound{+members}: compound_encode(tasks, buffer, limits, depth, members, count_values(Member, limits, members))
    case IntArray{+values}: array_encode(tasks, buffer, limits, 11, values, count_values(U32, limits, values))
    case LongArray{+values}: long_array_encode(tasks, buffer, limits, values, count_values(Word64, limits, values))

def encode_step(state: EncodeState) -> EncodeStep:
  match state:
    case EncodeState{Nil{}, Buffer{bytes, size}, limits}: EncodeFinished{List.reverse(&2, U32, bytes)}
    case EncodeState{Payload{value, depth} <> rest, buffer, limits}: encode_payload(value, depth, rest, buffer, limits)
    case EncodeState{ListItems{element, Nil{}, depth} <> rest, buffer, limits}: EncodeContinue{EncodeState{rest, buffer, limits}}
    case EncodeState{ListItems{+element, +h <> t, +depth} <> rest, buffer, limits}:
      choose(EncodeStep, EncodeContinue{EncodeState{Payload{h, depth} <> ListItems{element, t, depth} <> rest, buffer, limits}},
        EncodeRejected{"heterogeneous NBT list"}, U32.is_eq(tag(h), element))
    case EncodeState{CompoundItems{Nil{}, depth} <> rest, buffer, limits}: emit(rest, buffer, limits, Done{0 <> Nil{}})
    case EncodeState{CompoundItems{Member{name, +value} <> t, +depth} <> rest, buffer, limits}:
      lazy_choose(EncodeStep, u => emit(Payload{value, depth} <> CompoundItems{t, depth} <> rest, buffer, limits, bytes_join(tag(value) <> Nil{}, encode_text(name))),
        u => EncodeRejected{"compound member cannot be TAG_End"}, U32.is_ne(tag(value), 0))

def encode_run(fuel: Nat, step: EncodeStep) -> Result<&2, &2, String, List<&2, U32>>:
  match fuel step:
    case _ EncodeFinished{bytes}: Done{bytes}
    case _ EncodeRejected{message}: Fail{message}
    case 0n EncodeContinue{state}: Fail{"NBT encode transition budget exceeded"}
    case 1n+rest EncodeContinue{state}: encode_run(rest, encode_step(state))

def encode_with(+limits: Limits, root: Root) -> Result<&2, &2, String, List<&2, U32>>:
  match limits root:
    case Limits{+max_bytes, depth, elements} Root{Text{Nil{}}, End{}}:
      encode_run(16n, emit(Nil{}, Buffer{Nil{}, 0}, limits, Done{0 <> Nil{}}))
    case Limits{max_bytes, depth, elements} Root{Text{h <> t}, End{}}: Fail{"TAG_End root must have an empty name"}
    case Limits{+max_bytes, depth, elements} Root{name, +value}:
      encode_run(Nat.add(16n, Nat.mul(4n, U32.to_nat(max_bytes))), emit(Payload{value, 0} <> Nil{}, Buffer{Nil{}, 0}, limits, bytes_join(tag(value) <> Nil{}, encode_text(name))))

def encode(root: Root) -> Result<&2, &2, String, List<&2, U32>>:
  encode_with(default_limits(), root)
