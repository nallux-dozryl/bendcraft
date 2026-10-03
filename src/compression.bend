import Base

# RFC 1951/1950/1952 decoding. All parsing, checksums and byte production are
# pure checked Bend. Public inflate_*/store_* APIs and checksum helpers are
# documented in COMPRESSION.md; internal state constructors are not a contract.
type Limits is Data:
  Limits{max_input: U32, max_output: U32}

type Error is Data:
  Error{code: String}

type Decoded is Data:
  Decoded{bytes: List<&2, U32>, size: U32, consumed: U32, adler32: U32, crc32: U32}

type Encoded is Data:
  Encoded{bytes: List<&2, U32>, size: U32, source_size: U32, adler32: U32, crc32: U32}

type Writer is Data:
  Writer{reversed: List<&2, U32>, size: U32, limit: U32}

type StoredStep is Data:
  StoredMore{bytes: List<&2, U32>, remaining: U32, writer: Writer}
  StoredDone{writer: Writer}

type Reader is Data:
  Reader{bytes: List<&2, U32>, bits: U32, count: U32}

type Huffman is Type:
  Huffman{counts: Array<U32>, symbols: Array<U32>, maximum: U32}

type Output is Type:
  Output{history: Array<U32>, reversed: List<&2, U32>, total: U32,
    member: U32, limit: U32, window: U32, a: U32, b: U32, crc: U32, member_crc: U32}

type Expansion is Type:
  Expansion{reader: Reader, table: Huffman, used: U32, total: U32,
    previous: Maybe<&2, U32>, reversed: List<&2, U32>}

type Mode is Type:
  Header{}
  Codes{final: Bool, literals: Huffman, distances: Huffman}

type Decoder is Type:
  Decoder{reader: Reader, output: Output, mode: Mode}

type Step is Type:
  More{decoder: Decoder}
  Finished{reader: Reader, output: Output}

type GHeader is Data:
  GHeader{bytes: List<&2, U32>, crc: U32}

def paired(-A: Type, -B: Type, -R: Type, pair: A & B, body: A -> B -> R) -> R:
  match pair:
    case Tuple{a, b}: body(a)(b)

def choose(-A: Type, yes: A, no: A, condition: Bool) -> A:
  match condition:
    case True{}: yes
    case False{}: no

def require(condition: Bool, code: String) -> Result<&2, &1, Error, Unit>:
  match condition:
    case True{}: Done{Unit{}}
    case False{}: Fail{Error{code}}

def checked_input(bytes: List<&2, U32>, +limit: U32, +count: U32) -> Result<&2, &1, Error, U32>:
  match bytes:
    case Nil{}: Done{count}
    case +byte <> rest:
      do Result<&2, &1, Error, U32>:
        require(U32.is_lt(byte, 256), "InvalidByte")
        require(U32.is_lt(count, limit), "InputLimit")
        checked_input(rest, limit, U32.inc(count))

def crc_bits(n: Nat, crc: U32) -> U32:
  match n:
    case 0n: crc
    case 1n+p:
      +value = crc
      crc_bits(p, U32.xor(U32.shr(value), U32.and(3988292384, U32.sub(0, U32.and(value, 1)))))

def crc_byte(crc: U32, byte: U32) -> U32:
  crc_bits(8n, U32.xor(crc, byte))

def crc_loop(bytes: List<&2, U32>, crc: U32) -> U32:
  match bytes:
    case Nil{}: U32.not(crc)
    case byte <> rest: crc_loop(rest, crc_byte(crc, byte))

def crc32(bytes: List<&2, U32>) -> U32:
  crc_loop(bytes, 4294967295)

def adler_reduce(+value: U32) -> U32:
  choose(U32, U32.sub(value, 65521), value, U32.is_ge(value, 65521))

def adler_loop(bytes: List<&2, U32>, a: U32, b: U32) -> U32:
  match bytes:
    case Nil{}: U32.or(U32.shln(b, 16n), a)
    case byte <> rest:
      +next = adler_reduce(U32.add(a, byte))
      adler_loop(rest, next, adler_reduce(U32.add(b, next)))

def adler32(bytes: List<&2, U32>) -> U32:
  adler_loop(bytes, 1, 0)

def one_bit(reader: Reader) -> Result<&2, &1, Error, Reader & U32>:
  match reader:
    case Reader{Nil{}, bits, 0}: Fail{Error{"Truncated"}}
    case Reader{+byte <> rest, bits, 0}:
      Done{(Reader{rest, U32.shr(byte), 7}, U32.and(byte, 1))}
    case Reader{bytes, +bits, count}:
      Done{(Reader{bytes, U32.shr(bits), U32.sub(count, 1)}, U32.and(bits, 1))}

def read_bits(n: Nat, reader: Reader, +shift: Nat, value: U32) -> Result<&2, &1, Error, Reader & U32>:
  match n:
    case 0n: Done{(reader, value)}
    case 1n+p:
      do Result<&2, &1, Error, Reader & U32>:
        got : Reader & U32 <- one_bit(reader)
        (
          paired(Reader, U32, Result<&2, &1, Error, Reader & U32>, got, next => bit => (
            do Result<&2, &1, Error, Reader & U32>:
              read_bits(p, next, 1n+shift, U32.or(value, U32.shln(bit, shift)))
          ))
        )

def bits(reader: Reader, n: Nat) -> Result<&2, &1, Error, Reader & U32>:
  read_bits(n, reader, 0n, 0)

def align(reader: Reader) -> Reader:
  Reader{bytes, buffer, count} = reader
  Reader{bytes, 0, 0}

def take(n: Nat, bytes: List<&2, U32>, reversed: List<&2, U32>) -> List<&2, U32>:
  match n bytes:
    case 0n _: List.reverse(&2, U32, reversed)
    case _ Nil{}: List.reverse(&2, U32, reversed)
    case 1n+p byte <> rest: take(p, rest, byte <> reversed)

def at(n: Nat, bytes: List<&2, U32>) -> Maybe<&2, U32>:
  match n bytes:
    case _ Nil{}: None{}
    case 0n byte <> rest: Some{byte}
    case 1n+p byte <> rest: at(p, rest)

def count_lengths(lengths: List<&2, U32>, counts: Array<U32>) -> Result<&2, &1, Error, Array<U32>>:
  match lengths:
    case Nil{}: Done{counts}
    case 0 <> rest: count_lengths(rest, counts)
    case +length <> rest:
      do Result<&2, &1, Error, Array<U32>>:
        require(U32.is_le(length, 15), "HuffmanLength")
        (
          paired(Array<U32>, U32, Result<&2, &1, Error, Array<U32>>, counts[length], counts => count => (
            counts[length] <- U32.inc(count)
            do Result<&2, &1, Error, Array<U32>>:
              count_lengths(rest, counts)
          ))
        )

def shape_end(counts: Array<U32>, +left: U32, +maximum: U32, +total: U32, +kind: U32) -> Result<&2, &1, Error, Array<U32> & U32>:
  do Result<&2, &1, Error, Array<U32> & U32>:
    require(U32.is_zero(left) || (U32.is_ne(kind, 0) && U32.is_eq(maximum, 1) && U32.is_eq(total, 1)) ||
      (U32.is_eq(kind, 2) && U32.is_zero(total)), "HuffmanIncomplete")
    return (counts, maximum)

def check_shape(n: Nat, counts: Array<U32>, +length: U32, +left: U32, maximum: U32, +total: U32, +kind: U32) -> Result<&2, &1, Error, Array<U32> & U32>:
  match n:
    case 0n: shape_end(counts, left, maximum, total, kind)
    case 1n+p:
      do Result<&2, &1, Error, Array<U32> & U32>:
        (
          paired(Array<U32>, U32, Result<&2, &1, Error, Array<U32> & U32>, counts[length], counts => +count => (
            do Result<&2, &1, Error, Array<U32> & U32>:
              require(U32.is_le(count, U32.shl(left)), "HuffmanOversubscribed")
              check_shape(p, counts, U32.inc(length), U32.sub(U32.shl(left), count),
                choose(U32, length, maximum, U32.is_gt(count, 0)), U32.add(total, count), kind)
          ))
        )

def offsets(n: Nat, counts: Array<U32>, starts: Array<U32>, +length: U32, +total: U32) -> Array<U32> & Array<U32>:
  match n:
    case 0n: (counts, starts)
    case 1n+p:
      paired(Array<U32>, U32, Array<U32> & Array<U32>, counts[length], counts => count => (
        starts[length] <- total
        offsets(p, counts, starts, U32.inc(length), U32.add(total, count))
      ))

def symbols(lengths: List<&2, U32>, +symbol: U32, starts: Array<U32>, table: Array<U32>) -> Array<U32>:
  match lengths:
    case Nil{}: table
    case 0 <> rest: symbols(rest, U32.inc(symbol), starts, table)
    case +length <> rest:
      paired(Array<U32>, U32, Array<U32>, starts[length], starts => +index => (
        starts[length] <- U32.inc(index)
        table[index] <- symbol
        symbols(rest, U32.inc(symbol), starts, table)
      ))

# kind=0 code-length alphabet (complete), 1 literal, 2 distance (may be empty).
def huffman(+lengths: List<&2, U32>, kind: U32) -> Result<&2, &1, Error, Huffman>:
  do Result<&2, &1, Error, Huffman>:
    counts : Array<U32> <- count_lengths(lengths, [0 : U32^4n])
    shaped : Array<U32> & U32 <- check_shape(15n, counts, 1, 1, 0, 0, kind)
    (
      paired(Array<U32>, U32, Result<&2, &1, Error, Huffman>, shaped, counts => maximum => (
        paired(Array<U32>, Array<U32>, Result<&2, &1, Error, Huffman>, offsets(15n, counts, [0 : U32^4n], 1, 0), counts => starts => (
          do Result<&2, &1, Error, Huffman>:
            return Huffman{counts, symbols(lengths, 0, starts, [0 : U32^9n]), maximum}
      ))
      ))
    )

def symbol_loop(n: Nat, table: Huffman, reader: Reader, +length: U32, code: U32, +first: U32, +index: U32,
    found: Bool) -> Result<&2, &1, Error, Huffman & Reader & U32>:
  match n table found:
    case _ Huffman{counts, symbols, maximum} True{}:
      paired(Array<U32>, U32, Result<&2, &1, Error, Huffman & Reader & U32>, symbols[index], symbols => value => (
        Done{(Huffman{counts, symbols, maximum}, (reader, value))}
      ))
    case 0n _ False{}: Fail{Error{"HuffmanCode"}}
    case 1n+p Huffman{counts, symbols, maximum} False{}:
      do Result<&2, &1, Error, Huffman & Reader & U32>:
        got : Reader & U32 <- bits(reader, 1n)
        (
          paired(Reader, U32, Result<&2, &1, Error, Huffman & Reader & U32>, got, reader => bit => (
            +next_code = U32.or(code, bit)
            paired(Array<U32>, U32, Result<&2, &1, Error, Huffman & Reader & U32>, counts[length], counts => +count => (
              +hit = U32.is_ge(next_code, first) && U32.is_lt(U32.sub(next_code, first), count)
              do Result<&2, &1, Error, Huffman & Reader & U32>:
                symbol_loop(p, Huffman{counts, symbols, maximum}, reader, U32.inc(length), U32.shl(next_code),
                  U32.shl(U32.add(first, count)), choose(U32, U32.add(index, U32.sub(next_code, first)), U32.add(index, count), hit), hit)
          ))
          ))
        )

def symbol(table: Huffman, reader: Reader) -> Result<&2, &1, Error, Huffman & Reader & U32>:
  Huffman{counts, symbols, +maximum} = table
  symbol_loop(U32.to_nat(maximum), Huffman{counts, symbols, maximum}, reader, 1, 0, 0, 0, False{})

def array_list(n: Nat, array: Array<U32>, +index: U32, reversed: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: List.reverse(&2, U32, reversed)
    case 1n+p:
      paired(Array<U32>, U32, List<&2, U32>, array[index], array => value => (
        array_list(p, array, U32.inc(index), value <> reversed)
      ))

def code_lengths(n: Nat, order: List<&2, U32>, reader: Reader, table: Array<U32>) -> Result<&2, &1, Error, Reader & Array<U32>>:
  match n order:
    case 0n _: Done{(reader, table)}
    case _ Nil{}: Fail{Error{"CodeLengthCount"}}
    case 1n+p index <> rest:
      do Result<&2, &1, Error, Reader & Array<U32>>:
        got : Reader & U32 <- bits(reader, 3n)
        (
          paired(Reader, U32, Result<&2, &1, Error, Reader & Array<U32>>, got, reader => length => (
            table[index] <- length
            do Result<&2, &1, Error, Reader & Array<U32>>:
              code_lengths(p, rest, reader, table)
          ))
        )

def repeat(n: Nat, +value: U32, reversed: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: reversed
    case 1n+p: repeat(p, value, value <> reversed)

def expanded(reader: Reader, table: Huffman, +used: U32, +total: U32, reversed: List<&2, U32>, +value: U32, +count: U32) -> Result<&2, &1, Error, Bool & Expansion>:
  do Result<&2, &1, Error, Bool & Expansion>:
    require(U32.is_le(count, U32.sub(total, used)), "CodeLengthRepeat")
    (
      +next = U32.add(used, count)
      do Result<&2, &1, Error, Bool & Expansion>:
        return (U32.is_eq(next, total), Expansion{reader, table, next, total, Some{value}, repeat(U32.to_nat(count), value, reversed)})
    )

def expand_repeat(previous: Maybe<&2, U32>, reader: Reader, table: Huffman, used: U32, total: U32, reversed: List<&2, U32>) -> Result<&2, &1, Error, Bool & Expansion>:
  match previous:
    case None{}: Fail{Error{"CodeLengthRepeat"}}
    case Some{value}:
      do Result<&2, &1, Error, Bool & Expansion>:
        got : Reader & U32 <- bits(reader, 2n)
        (
          paired(Reader, U32, Result<&2, &1, Error, Bool & Expansion>, got, reader => count => (
            do Result<&2, &1, Error, Bool & Expansion>:
              expanded(reader, table, used, total, reversed, value, U32.add(count, 3))
          ))
        )

def expand_value(value: U32, reader: Reader, table: Huffman, used: U32, total: U32, previous: Maybe<&2, U32>, reversed: List<&2, U32>) -> Result<&2, &1, Error, Bool & Expansion>:
  match value:
    case 16: expand_repeat(previous, reader, table, used, total, reversed)
    case 17:
      do Result<&2, &1, Error, Bool & Expansion>:
        got : Reader & U32 <- bits(reader, 3n)
        (
          paired(Reader, U32, Result<&2, &1, Error, Bool & Expansion>, got, reader => count => (
            do Result<&2, &1, Error, Bool & Expansion>:
              expanded(reader, table, used, total, reversed, 0, U32.add(count, 3))
          ))
        )
    case 18:
      do Result<&2, &1, Error, Bool & Expansion>:
        got : Reader & U32 <- bits(reader, 7n)
        (
          paired(Reader, U32, Result<&2, &1, Error, Bool & Expansion>, got, reader => count => (
            do Result<&2, &1, Error, Bool & Expansion>:
              expanded(reader, table, used, total, reversed, 0, U32.add(count, 11))
          ))
        )
    case _: expanded(reader, table, used, total, reversed, value, 1)

def expand_one(expansion: Expansion) -> Result<&2, &1, Error, Bool & Expansion>:
  Expansion{reader, table, used, total, previous, reversed} = expansion
  do Result<&2, &1, Error, Bool & Expansion>:
    got : Huffman & Reader & U32 <- symbol(table, reader)
    (
      paired(Huffman, Reader & U32, Result<&2, &1, Error, Bool & Expansion>, got, table => parts_b_16 => (
        paired(Reader, U32, Result<&2, &1, Error, Bool & Expansion>, parts_b_16, reader => value => (
          do Result<&2, &1, Error, Bool & Expansion>:
            expand_value(value, reader, table, used, total, previous, reversed)
        ))
      ))
    )

def expand_loop(n: Nat, done: Bool, expansion: Expansion) -> Result<&2, &1, Error, Reader & List<&2, U32>>:
  match n done expansion:
    case _ True{} Expansion{reader, table, used, total, previous, reversed}:
      Done{(reader, List.reverse(&2, U32, reversed))}
    case 0n False{} _: Fail{Error{"CodeLengthCount"}}
    case 1n+p False{} state:
      do Result<&2, &1, Error, Reader & List<&2, U32>>:
        got : Bool & Expansion <- expand_one(state)
        (
          paired(Bool, Expansion, Result<&2, &1, Error, Reader & List<&2, U32>>, got, done => next => (
            do Result<&2, &1, Error, Reader & List<&2, U32>>:
              expand_loop(p, done, next)
          ))
        )

def split(n: Nat, bytes: List<&2, U32>, reversed: List<&2, U32>) -> List<&2, U32> & List<&2, U32>:
  match n bytes:
    case 0n rest: (List.reverse(&2, U32, reversed), rest)
    case _ Nil{}: (List.reverse(&2, U32, reversed), Nil{})
    case 1n+p value <> rest: split(p, rest, value <> reversed)

def end_code(found: Maybe<&2, U32>) -> Bool:
  match found:
    case Some{value}: U32.is_gt(value, 0)
    case None{}: False{}

def dynamic(reader: Reader) -> Result<&2, &1, Error, Reader & Huffman & Huffman>:
  do Result<&2, &1, Error, Reader & Huffman & Huffman>:
    g1 : Reader & U32 <- bits(reader, 5n)
    (
      paired(Reader, U32, Result<&2, &1, Error, Reader & Huffman & Huffman>, g1, reader => +nl => (
        do Result<&2, &1, Error, Reader & Huffman & Huffman>:
          require(U32.is_le(nl, 29), "LiteralCount")
          g2 : Reader & U32 <- bits(reader, 5n)
          (
            paired(Reader, U32, Result<&2, &1, Error, Reader & Huffman & Huffman>, g2, reader => +nd => (
              do Result<&2, &1, Error, Reader & Huffman & Huffman>:
                g3 : Reader & U32 <- bits(reader, 4n)
                (
                  paired(Reader, U32, Result<&2, &1, Error, Reader & Huffman & Huffman>, g3, reader => nc => (
                    do Result<&2, &1, Error, Reader & Huffman & Huffman>:
                      g4 : Reader & Array<U32> <- code_lengths(U32.to_nat(U32.add(nc, 4)),
                        [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15], reader, [0 : U32^5n])
                      (
                        paired(Reader, Array<U32>, Result<&2, &1, Error, Reader & Huffman & Huffman>, g4, reader => table => (
                          do Result<&2, &1, Error, Reader & Huffman & Huffman>:
                            codes : Huffman <- huffman(array_list(19n, table, 0, []), 0)
                            (
                              +total = U32.add(U32.add(nl, nd), 258)
                              do Result<&2, &1, Error, Reader & Huffman & Huffman>:
                                g5 : Reader & List<&2, U32> <- expand_loop(U32.to_nat(total), False{}, Expansion{reader, codes, 0, total, None{}, []})
                                (
                                  paired(Reader, List<&2, U32>, Result<&2, &1, Error, Reader & Huffman & Huffman>, g5, reader => lengths => (
                                    paired(List<&2, U32>, List<&2, U32>, Result<&2, &1, Error, Reader & Huffman & Huffman>, split(U32.to_nat(U32.add(nl, 257)), lengths, []), +literals => distances => (
                                      do Result<&2, &1, Error, Reader & Huffman & Huffman>:
                                        require(end_code(at(256n, literals)), "MissingEndCode")
                                        lit : Huffman <- huffman(literals, 1)
                                        dist : Huffman <- huffman(distances, 2)
                                        return (reader, (lit, dist))
                                  ))
                                  ))
                        ))
                  ))
            ))
      ))
                        )
                    )
                )
            )
        )
    )

def fixed_lengths(n: Nat, +index: U32, reversed: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: List.reverse(&2, U32, reversed)
    case 1n+p:
      length = choose(U32, 8, choose(U32, 9, choose(U32, 7, 8, U32.is_le(index, 279)), U32.is_le(index, 255)), U32.is_le(index, 143))
      fixed_lengths(p, U32.inc(index), length <> reversed)

def fixed() -> Result<&2, &1, Error, Huffman & Huffman>:
  do Result<&2, &1, Error, Huffman & Huffman>:
    lit : Huffman <- huffman(fixed_lengths(288n, 0, []), 1)
    dist : Huffman <- huffman(repeat(32n, 5, []), 2)
    return (lit, dist)

def output_new(limit: U32, window: U32) -> Output:
  Output{[0 : U32^15n], [], 0, 0, limit, window, 1, 0, 4294967295, 4294967295}

def next_member_crc(same: Bool, value: U32, previous: U32, byte: U32) -> U32:
  match same:
    case True{}: value
    case False{}: crc_byte(previous, byte)

def emit(output: Output, +byte: U32) -> Result<&2, &1, Error, Output>:
  Output{history, reversed, +total, +member, +limit, window, a, b, +crc, +member_crc} = output
  do Result<&2, &1, Error, Output>:
    require(U32.is_lt(total, limit), "OutputLimit")
    (
      +next_a = adler_reduce(U32.add(a, byte))
      +next_crc = crc_byte(crc, byte)
      history[U32.and(member, 32767)] <- byte
      do Result<&2, &1, Error, Output>:
        return Output{history, byte <> reversed, U32.inc(total), U32.inc(member), limit, window,
          next_a, adler_reduce(U32.add(b, next_a)), next_crc, next_member_crc(U32.is_eq(crc, member_crc), next_crc, member_crc, byte)}
    )

def copy_loop(n: Nat, +distance: U32, output: Output) -> Result<&2, &1, Error, Output>:
  match n:
    case 0n: Done{output}
    case 1n+p:
      Output{history, reversed, total, +member, limit, window, a, b, crc, member_crc} = output
      paired(Array<U32>, U32, Result<&2, &1, Error, Output>, history[U32.and(U32.sub(member, distance), 32767)], history => byte => (
        do Result<&2, &1, Error, Output>:
          next : Output <- emit(Output{history, reversed, total, member, limit, window, a, b, crc, member_crc}, byte)
          copy_loop(p, distance, next)
      ))

def copy(+length: U32, +distance: U32, output: Output) -> Result<&2, &1, Error, Output>:
  Output{history, reversed, +total, +member, +limit, +window, a, b, crc, member_crc} = output
  do Result<&2, &1, Error, Output>:
    require(U32.is_gt(distance, 0) && U32.is_le(distance, member) && U32.is_le(distance, window), "Distance")
    require(U32.is_le(length, U32.sub(limit, total)), "OutputLimit")
    copy_loop(U32.to_nat(length), distance, Output{history, reversed, total, member, limit, window, a, b, crc, member_crc})

def stored_loop(n: Nat, reader: Reader, output: Output) -> Result<&2, &1, Error, Reader & Output>:
  match n:
    case 0n: Done{(reader, output)}
    case 1n+p:
      do Result<&2, &1, Error, Reader & Output>:
        got : Reader & U32 <- bits(reader, 8n)
        (
          paired(Reader, U32, Result<&2, &1, Error, Reader & Output>, got, reader => byte => (
            do Result<&2, &1, Error, Reader & Output>:
              next : Output <- emit(output, byte)
              stored_loop(p, reader, next)
          ))
        )

def stored(reader: Reader, output: Output) -> Result<&2, &1, Error, Reader & Output>:
  do Result<&2, &1, Error, Reader & Output>:
    g1 : Reader & U32 <- bits(align(reader), 16n)
    (
      paired(Reader, U32, Result<&2, &1, Error, Reader & Output>, g1, reader => +length => (
        do Result<&2, &1, Error, Reader & Output>:
          g2 : Reader & U32 <- bits(reader, 16n)
          (
            paired(Reader, U32, Result<&2, &1, Error, Reader & Output>, g2, reader => inverse => (
              do Result<&2, &1, Error, Reader & Output>:
                require(U32.is_eq(U32.xor(length, 65535), inverse), "StoredLength")
                stored_loop(U32.to_nat(length), reader, output)
            ))
      ))
        )
    )

def length_extended(+code: U32) -> U32 & Nat:
  +extra = U32.shrn(U32.sub(code, 261), 2n)
  (U32.add(U32.shln(U32.add(4, U32.and(U32.sub(code, 265), 3)), U32.to_nat(extra)), 3), U32.to_nat(extra))

def length_info(code: U32) -> U32 & Nat:
  match code:
    case 257: (3, 0n)
    case 258: (4, 0n)
    case 259: (5, 0n)
    case 260: (6, 0n)
    case 261: (7, 0n)
    case 262: (8, 0n)
    case 263: (9, 0n)
    case 264: (10, 0n)
    case 285: (258, 0n)
    case _: length_extended(code)

def distance_extended(+code: U32) -> U32 & Nat:
  +extra = U32.sub(U32.shr(code), 1)
  (U32.inc(U32.shln(U32.add(2, U32.and(code, 1)), U32.to_nat(extra))), U32.to_nat(extra))

def distance_info(code: U32) -> U32 & Nat:
  match code:
    case 0: (1, 0n)
    case 1: (2, 0n)
    case 2: (3, 0n)
    case 3: (4, 0n)
    case _: distance_extended(code)

def match_bytes(+code: U32, literals: Huffman, distances: Huffman, reader: Reader, output: Output) -> Result<&2, &1, Error, Reader & Output & Huffman & Huffman>:
  do Result<&2, &1, Error, Reader & Output & Huffman & Huffman>:
    require(U32.is_le(code, 285), "ReservedLiteral")
    (
      paired(U32, Nat, Result<&2, &1, Error, Reader & Output & Huffman & Huffman>, length_info(code), base => extra => (
        do Result<&2, &1, Error, Reader & Output & Huffman & Huffman>:
          g1 : Reader & U32 <- bits(reader, extra)
          (
            paired(Reader, U32, Result<&2, &1, Error, Reader & Output & Huffman & Huffman>, g1, reader => value => (
              length = U32.add(base, value)
              do Result<&2, &1, Error, Reader & Output & Huffman & Huffman>:
                g2 : Huffman & Reader & U32 <- symbol(distances, reader)
                (
                  paired(Huffman, Reader & U32, Result<&2, &1, Error, Reader & Output & Huffman & Huffman>, g2, distances => parts_b_31 => (
                    paired(Reader, U32, Result<&2, &1, Error, Reader & Output & Huffman & Huffman>, parts_b_31, reader => +dc => (
                      do Result<&2, &1, Error, Reader & Output & Huffman & Huffman>:
                        require(U32.is_lt(dc, 30), "ReservedDistance")
                        (
                          paired(U32, Nat, Result<&2, &1, Error, Reader & Output & Huffman & Huffman>, distance_info(dc), db => de => (
                            do Result<&2, &1, Error, Reader & Output & Huffman & Huffman>:
                              g3 : Reader & U32 <- bits(reader, de)
                              (
                                paired(Reader, U32, Result<&2, &1, Error, Reader & Output & Huffman & Huffman>, g3, reader => dv => (
                                  do Result<&2, &1, Error, Reader & Output & Huffman & Huffman>:
                                    next : Output <- copy(length, U32.add(db, dv), output)
                                    return (reader, (next, (literals, distances)))
                                ))
                          ))
            ))
      ))
                ))
              ))
                    )
                )
            )
        )
    )

def block_done(final: Bool, reader: Reader, output: Output) -> Step:
  match final:
    case True{}: Finished{align(reader), output}
    case False{}: More{Decoder{reader, output, Header{}}}

def code_step(final: Bool, literals: Huffman, distances: Huffman, reader: Reader, output: Output, +code: U32) -> Result<&2, &1, Error, Step>:
  match code:
    case 256: Done{block_done(final, reader, output)}
    case _:
      do Result<&2, &1, Error, Step>:
        require(U32.is_ge(code, 257), "InternalLiteralDispatch")
        got : Reader & Output & Huffman & Huffman <- match_bytes(code, literals, distances, reader, output)
        (
          paired(Reader, Output & Huffman & Huffman, Result<&2, &1, Error, Step>, got, reader => parts_b_35 => (
            paired(Output, Huffman & Huffman, Result<&2, &1, Error, Step>, parts_b_35, output => parts_b_36 => (
              paired(Huffman, Huffman, Result<&2, &1, Error, Step>, parts_b_36, literals => distances => (
                do Result<&2, &1, Error, Step>:
                  return More{Decoder{reader, output, Codes{final, literals, distances}}}
              ))
            ))
          ))
        )

def literal_step(small: Bool, final: Bool, literals: Huffman, distances: Huffman, reader: Reader, output: Output, code: U32) -> Result<&2, &1, Error, Step>:
  match small:
    case True{}:
      do Result<&2, &1, Error, Step>:
        next : Output <- emit(output, code)
        return More{Decoder{reader, next, Codes{final, literals, distances}}}
    case False{}: code_step(final, literals, distances, reader, output, code)

def header_step(kind: U32, final: Bool, reader: Reader, output: Output) -> Result<&2, &1, Error, Step>:
  match kind:
    case 0:
      do Result<&2, &1, Error, Step>:
        got : Reader & Output <- stored(reader, output)
        (
          paired(Reader, Output, Result<&2, &1, Error, Step>, got, reader => output => (
            do Result<&2, &1, Error, Step>:
              return block_done(final, reader, output)
          ))
        )
    case 1:
      do Result<&2, &1, Error, Step>:
        tables : Huffman & Huffman <- fixed()
        (
          paired(Huffman, Huffman, Result<&2, &1, Error, Step>, tables, literals => distances => (
            do Result<&2, &1, Error, Step>:
              return More{Decoder{reader, output, Codes{final, literals, distances}}}
          ))
        )
    case 2:
      do Result<&2, &1, Error, Step>:
        got : Reader & Huffman & Huffman <- dynamic(reader)
        (
          paired(Reader, Huffman & Huffman, Result<&2, &1, Error, Step>, got, reader => parts_b_40 => (
            paired(Huffman, Huffman, Result<&2, &1, Error, Step>, parts_b_40, literals => distances => (
              do Result<&2, &1, Error, Step>:
                return More{Decoder{reader, output, Codes{final, literals, distances}}}
            ))
          ))
        )
    case _: Fail{Error{"ReservedBlock"}}

def step(decoder: Decoder) -> Result<&2, &1, Error, Step>:
  match decoder:
    case Decoder{reader, output, Header{}}:
      do Result<&2, &1, Error, Step>:
        got : Reader & U32 <- bits(reader, 3n)
        (
          paired(Reader, U32, Result<&2, &1, Error, Step>, got, reader => +header => (
            do Result<&2, &1, Error, Step>:
              header_step(U32.shr(header), U32.is_ne(U32.and(header, 1), 0), reader, output)
          ))
        )
    case Decoder{reader, output, Codes{final, literals, distances}}:
      do Result<&2, &1, Error, Step>:
        got : Huffman & Reader & U32 <- symbol(literals, reader)
        (
          paired(Huffman, Reader & U32, Result<&2, &1, Error, Step>, got, literals => parts_b_43 => (
            paired(Reader, U32, Result<&2, &1, Error, Step>, parts_b_43, reader => +code => (
              do Result<&2, &1, Error, Step>:
                literal_step(U32.is_lt(code, 256), final, literals, distances, reader, output, code)
            ))
          ))
        )

def decode_loop(fuel: Nat, state: Step) -> Result<&2, &1, Error, Reader & Output>:
  match fuel state:
    case _ Finished{reader, output}: Done{(reader, output)}
    case 0n More{decoder}: Fail{Error{"WorkLimit"}}
    case 1n+p More{decoder}:
      do Result<&2, &1, Error, Reader & Output>:
        next : Step <- step(decoder)
        decode_loop(p, next)

def work(+size: U32) -> Nat:
  1n+Nat.mul(8n, U32.to_nat(size))

def decoded(consumed: U32, output: Output) -> Decoded:
  Output{history, reversed, total, member, limit, window, a, b, crc, member_crc} = output
  Decoded{List.reverse(&2, U32, reversed), total, consumed, U32.or(U32.shln(b, 16n), a), U32.not(crc)}

def exhausted(reader: Reader) -> Bool:
  match reader:
    case Reader{Nil{}, buffer, count}: True{}
    case _: False{}

def inflate_raw(+bytes: List<&2, U32>, limits: Limits) -> Result<&2, &1, Error, Decoded>:
  Limits{max_input, max_output} = limits
  do Result<&2, &1, Error, Decoded>:
    +size : U32 <- checked_input(bytes, max_input, 0)
    got : Reader & Output <- decode_loop(work(size), More{Decoder{Reader{bytes, 0, 0}, output_new(max_output, 32768), Header{}}})
    (
      paired(Reader, Output, Result<&2, &1, Error, Decoded>, got, reader => output => (
        do Result<&2, &1, Error, Decoded>:
          require(exhausted(reader), "TrailingData")
          return decoded(size, output)
      ))
    )

def le32(+a: U32, +b: U32, +c: U32, +d: U32) -> U32:
  U32.or(a, U32.or(U32.shln(b, 8n), U32.or(U32.shln(c, 16n), U32.shln(d, 24n))))

def zlib_header(bytes: List<&2, U32>) -> Result<&2, &1, Error, Reader & U32>:
  match bytes:
    case +cmf <> +flg <> rest:
      do Result<&2, &1, Error, Reader & U32>:
        require(U32.is_eq(U32.and(cmf, 15), 8) && U32.is_le(U32.shrn(cmf, 4n), 7), "ZlibHeader")
        require(U32.is_zero(U32.mod(U32.add(U32.shln(cmf, 8n), flg), 31)), "ZlibHeader")
        require(U32.is_zero(U32.and(flg, 32)), "UnsupportedDictionary")
        return (Reader{rest, 0, 0}, U32.shln(1, U32.to_nat(U32.add(U32.shrn(cmf, 4n), 8))))
    case _: Fail{Error{"Truncated"}}

def checked_adler(expected: U32, result: Decoded) -> Result<&2, &1, Error, Decoded>:
  Decoded{bytes, size, consumed, +adler, crc} = result
  do Result<&2, &1, Error, Decoded>:
    require(U32.is_eq(adler, expected), "AdlerMismatch")
    return Decoded{bytes, size, consumed, adler, crc}

def zlib_trailer(reader: Reader, output: Output, size: U32) -> Result<&2, &1, Error, Decoded>:
  match reader:
    case Reader{a <> b <> c <> d <> Nil{}, buffer, count}:
      checked_adler(le32(d, c, b, a), decoded(size, output))
    case Reader{a <> b <> c <> d <> rest, buffer, count}: Fail{Error{"TrailingData"}}
    case _: Fail{Error{"Truncated"}}

def inflate_zlib(+bytes: List<&2, U32>, limits: Limits) -> Result<&2, &1, Error, Decoded>:
  Limits{max_input, max_output} = limits
  do Result<&2, &1, Error, Decoded>:
    +size : U32 <- checked_input(bytes, max_input, 0)
    header : Reader & U32 <- zlib_header(bytes)
    (
      paired(Reader, U32, Result<&2, &1, Error, Decoded>, header, reader => window => (
        do Result<&2, &1, Error, Decoded>:
          got : Reader & Output <- decode_loop(work(size), More{Decoder{reader, output_new(max_output, window), Header{}}})
          (
            paired(Reader, Output, Result<&2, &1, Error, Decoded>, got, reader => output => (
              do Result<&2, &1, Error, Decoded>:
                zlib_trailer(reader, output, size)
            ))
      ))
        )
    )

def hbyte(header: GHeader) -> Result<&2, &1, Error, GHeader & U32>:
  match header:
    case GHeader{Nil{}, crc}: Fail{Error{"Truncated"}}
    case GHeader{+byte <> rest, crc}: Done{(GHeader{rest, crc_byte(crc, byte)}, byte)}

def hskip(n: Nat, header: GHeader) -> Result<&2, &1, Error, GHeader>:
  match n:
    case 0n: Done{header}
    case 1n+p:
      do Result<&2, &1, Error, GHeader>:
        got : GHeader & U32 <- hbyte(header)
        (
          paired(GHeader, U32, Result<&2, &1, Error, GHeader>, got, header => byte => (
            do Result<&2, &1, Error, GHeader>:
              hskip(p, header)
          ))
        )

def hzero(bytes: List<&2, U32>, crc: U32) -> Result<&2, &1, Error, GHeader>:
  match bytes:
    case Nil{}: Fail{Error{"Truncated"}}
    case 0 <> rest: Done{GHeader{rest, crc_byte(crc, 0)}}
    case +byte <> rest: hzero(rest, crc_byte(crc, byte))

def hstring(present: Bool, header: GHeader) -> Result<&2, &1, Error, GHeader>:
  match present header:
    case False{} _: Done{header}
    case True{} GHeader{bytes, crc}: hzero(bytes, crc)

def hextra(present: Bool, header: GHeader) -> Result<&2, &1, Error, GHeader>:
  match present:
    case False{}: Done{header}
    case True{}:
      do Result<&2, &1, Error, GHeader>:
        g1 : GHeader & U32 <- hbyte(header)
        (
          paired(GHeader, U32, Result<&2, &1, Error, GHeader>, g1, header => a => (
            do Result<&2, &1, Error, GHeader>:
              g2 : GHeader & U32 <- hbyte(header)
              (
                paired(GHeader, U32, Result<&2, &1, Error, GHeader>, g2, header => b => (
                  do Result<&2, &1, Error, GHeader>:
                    hskip(U32.to_nat(U32.or(a, U32.shln(b, 8n))), header)
                ))
          ))
            )
        )

def hcrc(present: Bool, header: GHeader) -> Result<&2, &1, Error, Reader>:
  match present header:
    case False{} GHeader{bytes, crc}: Done{Reader{bytes, 0, 0}}
    case True{} GHeader{a <> b <> rest, crc}:
      do Result<&2, &1, Error, Reader>:
        require(U32.is_eq(U32.or(a, U32.shln(b, 8n)), U32.and(U32.not(crc), 65535)), "HeaderCrcMismatch")
        return Reader{rest, 0, 0}
    case True{} _: Fail{Error{"Truncated"}}

def gzip_header(bytes: List<&2, U32>) -> Result<&2, &1, Error, Reader>:
  match bytes:
    case +a <> +b <> +cm <> +flags <> +t0 <> +t1 <> +t2 <> +t3 <> +xfl <> +os <> rest:
      do Result<&2, &1, Error, Reader>:
        require(U32.is_eq(a, 31) && U32.is_eq(b, 139) && U32.is_eq(cm, 8) && U32.is_zero(U32.and(flags, 224)), "GzipHeader")
        header : GHeader <- hextra(U32.is_ne(U32.and(flags, 4), 0), GHeader{rest, U32.not(crc32([a, b, cm, flags, t0, t1, t2, t3, xfl, os]))})
        header : GHeader <- hstring(U32.is_ne(U32.and(flags, 8), 0), header)
        header : GHeader <- hstring(U32.is_ne(U32.and(flags, 16), 0), header)
        hcrc(U32.is_ne(U32.and(flags, 2), 0), header)
    case _: Fail{Error{"Truncated"}}

def member_reset(output: Output) -> Output:
  Output{history, reversed, total, member, limit, window, a, b, crc, member_crc} = output
  Output{history, reversed, total, 0, limit, 32768, a, b, crc, 4294967295}

def gzip_trailer(reader: Reader, output: Output) -> Result<&2, &1, Error, List<&2, U32> & Output>:
  match reader output:
    case Reader{a <> b <> c <> d <> e <> f <> g <> h <> rest, buffer, count}
        Output{history, reversed, total, +member, limit, window, aa, bb, crc, +member_crc}:
      do Result<&2, &1, Error, List<&2, U32> & Output>:
        require(U32.is_eq(le32(a, b, c, d), U32.not(member_crc)), "CrcMismatch")
        require(U32.is_eq(le32(e, f, g, h), member), "SizeMismatch")
        return (rest, Output{history, reversed, total, member, limit, window, aa, bb, crc, member_crc})
    case _ _: Fail{Error{"Truncated"}}

def gzip_member(bytes: List<&2, U32>, output: Output, +size: U32) -> Result<&2, &1, Error, List<&2, U32> & Output>:
  do Result<&2, &1, Error, List<&2, U32> & Output>:
    reader : Reader <- gzip_header(bytes)
    got : Reader & Output <- decode_loop(work(size), More{Decoder{reader, member_reset(output), Header{}}})
    (
      paired(Reader, Output, Result<&2, &1, Error, List<&2, U32> & Output>, got, reader => output => (
        do Result<&2, &1, Error, List<&2, U32> & Output>:
          gzip_trailer(reader, output)
      ))
    )

def gzip_loop(fuel: Nat, bytes: List<&2, U32>, output: Output, +size: U32) -> Result<&2, &1, Error, Decoded>:
  match fuel bytes:
    case _ Nil{}: Done{decoded(size, output)}
    case 0n _: Fail{Error{"WorkLimit"}}
    case 1n+p rest:
      do Result<&2, &1, Error, Decoded>:
        got : List<&2, U32> & Output <- gzip_member(rest, output, size)
        (
          paired(List<&2, U32>, Output, Result<&2, &1, Error, Decoded>, got, remaining => output => (
            do Result<&2, &1, Error, Decoded>:
              gzip_loop(p, remaining, output, size)
          ))
        )

def inflate_gzip(+bytes: List<&2, U32>, limits: Limits) -> Result<&2, &1, Error, Decoded>:
  Limits{max_input, max_output} = limits
  do Result<&2, &1, Error, Decoded>:
    +size : U32 <- checked_input(bytes, max_input, 0)
    require(U32.is_gt(size, 0), "Truncated")
    gzip_loop(U32.to_nat(size), bytes, output_new(max_output, 32768), size)

# Deliberately uncompressed, deterministic, interoperable stored-block output.
def write_byte(writer: Writer, byte: U32) -> Result<&2, &1, Error, Writer>:
  Writer{reversed, +size, +limit} = writer
  do Result<&2, &1, Error, Writer>:
    require(U32.is_lt(size, limit), "OutputLimit")
    return Writer{byte <> reversed, U32.inc(size), limit}

def write_bytes(bytes: List<&2, U32>, writer: Writer) -> Result<&2, &1, Error, Writer>:
  match bytes:
    case Nil{}: Done{writer}
    case byte <> rest:
      do Result<&2, &1, Error, Writer>:
        next : Writer <- write_byte(writer, byte)
        write_bytes(rest, next)

def stored_bytes(n: Nat, bytes: List<&2, U32>, writer: Writer) -> Result<&2, &1, Error, List<&2, U32> & Writer>:
  match n bytes:
    case 0n rest: Done{(rest, writer)}
    case _ Nil{}: Fail{Error{"InternalStoredInput"}}
    case 1n+p byte <> rest:
      do Result<&2, &1, Error, List<&2, U32> & Writer>:
        next : Writer <- write_byte(writer, byte)
        stored_bytes(p, rest, next)

def little_bytes(+value: U32) -> List<&2, U32>:
  [U32.and(value, 255), U32.and(U32.shrn(value, 8n), 255), U32.and(U32.shrn(value, 16n), 255), U32.shrn(value, 24n)]

def stored_header(+size: U32, final: Bool) -> List<&2, U32>:
  +inverse = U32.xor(size, 65535)
  [choose(U32, 1, 0, final), U32.and(size, 255), U32.shrn(size, 8n), U32.and(inverse, 255), U32.shrn(inverse, 8n)]

def stored_next(done: Bool, bytes: List<&2, U32>, remaining: U32, writer: Writer) -> StoredStep:
  match done:
    case True{}: StoredDone{writer}
    case False{}: StoredMore{bytes, remaining, writer}

def stored_chunk(bytes: List<&2, U32>, +remaining: U32, writer: Writer) -> Result<&2, &1, Error, StoredStep>:
  +count = U32.min(remaining, 65535)
  +final = U32.is_eq(count, remaining)
  do Result<&2, &1, Error, StoredStep>:
    header : Writer <- write_bytes(stored_header(count, final), writer)
    got : List<&2, U32> & Writer <- stored_bytes(U32.to_nat(count), bytes, header)
    paired(List<&2, U32>, Writer, Result<&2, &1, Error, StoredStep>, got, tail => next =>
      Done{stored_next(final, tail, U32.sub(remaining, count), next)})

def stored_encode_loop(fuel: Nat, state: StoredStep) -> Result<&2, &1, Error, Writer>:
  match fuel state:
    case _ StoredDone{writer}: Done{writer}
    case 0n _: Fail{Error{"WorkLimit"}}
    case 1n+p StoredMore{bytes, remaining, writer}:
      do Result<&2, &1, Error, Writer>:
        next : StoredStep <- stored_chunk(bytes, remaining, writer)
        stored_encode_loop(p, next)

def store_body(bytes: List<&2, U32>, +size: U32, writer: Writer) -> Result<&2, &1, Error, Writer>:
  stored_encode_loop(1n+U32.to_nat(U32.div(size, 65535)), StoredMore{bytes, size, writer})

def encoded(writer: Writer, source_size: U32, adler: U32, crc: U32) -> Encoded:
  Writer{reversed, size, limit} = writer
  Encoded{List.reverse(&2, U32, reversed), size, source_size, adler, crc}

def store_raw(+bytes: List<&2, U32>, limits: Limits) -> Result<&2, &1, Error, Encoded>:
  Limits{max_input, max_output} = limits
  do Result<&2, &1, Error, Encoded>:
    +size : U32 <- checked_input(bytes, max_input, 0)
    result : Writer <- store_body(bytes, size, Writer{[], 0, max_output})
    return encoded(result, size, adler32(bytes), crc32(bytes))

def store_zlib(+bytes: List<&2, U32>, limits: Limits) -> Result<&2, &1, Error, Encoded>:
  Limits{max_input, max_output} = limits
  do Result<&2, &1, Error, Encoded>:
    +size : U32 <- checked_input(bytes, max_input, 0)
    +adler : U32 = adler32(bytes)
    header : Writer <- write_bytes([120, 1], Writer{[], 0, max_output})
    body : Writer <- store_body(bytes, size, header)
    result : Writer <- write_bytes(List.reverse(&2, U32, little_bytes(adler)), body)
    return encoded(result, size, adler, crc32(bytes))

def store_gzip(+bytes: List<&2, U32>, limits: Limits) -> Result<&2, &1, Error, Encoded>:
  Limits{max_input, max_output} = limits
  do Result<&2, &1, Error, Encoded>:
    +size : U32 <- checked_input(bytes, max_input, 0)
    +crc : U32 = crc32(bytes)
    header : Writer <- write_bytes([31, 139, 8, 0, 0, 0, 0, 0, 0, 255], Writer{[], 0, max_output})
    body : Writer <- store_body(bytes, size, header)
    trailer : Writer <- write_bytes(little_bytes(crc), body)
    result : Writer <- write_bytes(little_bytes(size), trailer)
    return encoded(result, size, adler32(bytes), crc)
