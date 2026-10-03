import Base
import ./compression.bend as C
import ./framing.bend as F

# ZIP interpretation and entry checking are pure Bend. File effects only read
# bounded byte slices; this module never writes/extracts filesystem paths.
type NameEncoding is Data:
  UTF8Fallback{}
  CP437Fallback{}

type Limits is Data:
  Limits{max_file: U32, max_index: U32, max_entries: U32, max_name: U32,
    max_compressed: U32, max_output: U32}

type Error is Data:
  Error{code: String, offset: U32, message: String}

type End is Data:
  End{file_size: U32, offset: U32, central_offset: U32, central_size: U32,
    entries: U32, disk: U32, central_disk: U32, disk_entries: U32}

type Entry is Data:
  Entry{ordinal: U32, name: String, raw_name: List<&2, U32>, needed: U32,
    flags: U32, method: U32, crc32: U32, compressed_size: U32, size: U32,
    local_offset: U32, ceiling: U32}

type Directory is Data:
  Directory{end: End, entries: List<&2, Entry>, names: Map<&2, Maybe<&2, Entry>>}

type Archive is Type:
  Archive{file: File, directory: Directory, limits: Limits}

type Cursor is Data:
  Cursor{bytes: List<&2, U32>, offset: U32}

type Read<-A: Data> is Data:
  Read{cursor: Cursor, value: A}

def read_with(-A: Data, -R: Type, read: Read<A>, body: Cursor -> A -> R) -> R:
  match read:
    case Read{cursor, value}: body(cursor)(value)

def default_limits() -> Limits:
  Limits{536870912, 16777216, 65534, 4096, 33554432, 33554432}

def fail(-A: Data, code: String, offset: U32, message: String) -> Result<&2, &2, Error, A>:
  Fail{Error{code, offset, message}}

def require(valid: Bool, code: String, offset: U32, message: String) -> Result<&2, &2, Error, Unit>:
  match valid:
    case True{}: Done{Unit{}}
    case False{}: fail(Unit, code, offset, message)

def choose(-A: Data, yes: A, no: A, condition: Bool) -> A:
  match condition:
    case True{}: yes
    case False{}: no

def error_text(error: Error) -> String:
  Error{code, offset, message} = error
  code ++ " at byte " ++ U32.show(offset) ++ ": " ++ message

def limits_valid(limits: Limits) -> Bool:
  Limits{file, index, entries, name, compressed, output} = limits
  U32.is_le(file, 1073741824) && U32.is_le(index, 67108864) && U32.is_le(entries, 65534) &&
    U32.is_le(name, 16384) && U32.is_le(compressed, 67108864) && U32.is_le(output, 67108864)

def span(+offset: U32, length: U32, +limit: U32) -> Bool:
  U32.is_le(offset, limit) && U32.is_le(length, U32.sub(limit, offset))

def byte_count(bytes: List<&2, U32>, +limit: U32, +count: U32) -> Result<&2, &2, Error, U32>:
  match bytes:
    case Nil{}: Done{count}
    case +byte <> rest:
      do Result<&2, &2, Error, U32>:
        require(U32.is_le(byte, 255), "InvalidByte", count, "input element exceeds 255")
        require(U32.is_lt(count, limit), "InputLimit", count, "byte slice exceeds limit")
        byte_count(rest, limit, U32.inc(count))

def le16(bytes: List<&2, U32>) -> U32:
  match bytes:
    case a <> b <> rest: U32.or(a, U32.shln(b, 8n))
    case _: 0

def le32(bytes: List<&2, U32>) -> U32:
  match bytes:
    case a <> b <> c <> d <> rest: U32.or(a, U32.or(U32.shln(b, 8n), U32.or(U32.shln(c, 16n), U32.shln(d, 24n))))
    case _: 0

def word16(bytes: List<&2, U32>, offset: U32) -> U32:
  le16(List.drop(&2, U32, bytes, U32.to_nat(offset)))

def word32(bytes: List<&2, U32>, offset: U32) -> U32:
  le32(List.drop(&2, U32, bytes, U32.to_nat(offset)))

def chunk(n: Nat, cursor: Cursor, reversed: List<&2, U32>) -> Result<&2, &2, Error, Read<List<&2, U32>>>:
  match n cursor:
    case 0n _: Done{Read{cursor, List.reverse(&2, U32, reversed)}}
    case 1n+rest Cursor{Nil{}, offset}: fail(Read<List<&2, U32>>, "Truncated", offset, "byte slice ends inside a record")
    case 1n+rest Cursor{byte <> tail, offset}:
      chunk(rest, Cursor{tail, U32.inc(offset)}, byte <> reversed)

def skip(n: Nat, cursor: Cursor) -> Result<&2, &2, Error, Cursor>:
  match n cursor:
    case 0n _: Done{cursor}
    case 1n+rest Cursor{Nil{}, offset}: fail(Cursor, "Truncated", offset, "byte slice ends inside a record")
    case 1n+rest Cursor{byte <> tail, offset}: skip(rest, Cursor{tail, U32.inc(offset)})

def zip64_recent(bytes: List<&2, U32>) -> Bool:
  U32.is_eq(le32(List.reverse(&2, U32, bytes)), 117853008)

def end_candidate(+bytes: List<&2, U32>, +offset: U32, +size: U32, recent: List<&2, U32>) -> Maybe<&2, End>:
  match bytes:
    case 80 <> 75 <> 5 <> 6 <> a <> b <> c <> d <> e <> f <> g <> h <> i <> j <> k <> l <> m <> n <> o <> p <> q <> r <> tail:
      +central_size = le32([i, j, k, l])
      +central_offset = le32([m, n, o, p])
      +comment = le16([q, r])
      choose(Maybe<&2, End>, Some{End{size, offset, central_offset, central_size, le16([g, h]), le16([a, b]), le16([c, d]), le16([e, f])}}, None{},
        span(offset, U32.add(22, comment), size) && U32.is_eq(U32.add(offset, U32.add(22, comment)), size) &&
        ((span(central_offset, central_size, offset) && U32.is_eq(U32.add(central_offset, central_size), offset)) ||
          U32.is_eq(le16([g, h]), 65535) || U32.is_eq(central_size, 4294967295) || U32.is_eq(central_offset, 4294967295) || zip64_recent(recent)))
    case _: None{}

def end_scan(bytes: List<&2, U32>, +offset: U32, +size: U32, found: Maybe<&2, End>, +recent: List<&2, U32>) -> Maybe<&2, End>:
  match bytes:
    case Nil{}: found
    case +byte <> +rest:
      +candidate = end_candidate(byte <> rest, offset, size, recent)
      end_scan(rest, U32.inc(offset), size, choose(Maybe<&2, End>, candidate, found, Maybe.is_some(&2, End, candidate)), List.take(&2, U32, byte <> recent, 20n))

def locator_at(tail: List<&2, U32>, relative: U32, available: Bool) -> Bool:
  match available:
    case False{}: False{}
    case True{}: U32.is_eq(word32(tail, U32.sub(relative, 20)), 117853008)

def locator_before(tail: List<&2, U32>, +relative: U32) -> Bool:
  locator_at(tail, relative, U32.is_ge(relative, 20))

def end_checked(found: Maybe<&2, End>, +tail: List<&2, U32>, +start: U32, limits: Limits) -> Result<&2, &2, Error, End>:
  match found:
    case None{}: fail(End, "MissingEOCD", start, "no classic end record with matching comment and directory extent")
    case Some{+end}:
      End{size, +offset, central_offset, +central_size, +entries, +disk, +central_disk, +disk_entries} = end
      Limits{max_file, max_index, max_entries, max_name, compressed, output} = limits
      do Result<&2, &2, Error, End>:
        require(U32.is_ne(entries, 65535) && U32.is_ne(central_size, 4294967295) && U32.is_ne(central_offset, 4294967295), "UnsupportedZIP64", offset, "classic fields contain ZIP64 sentinels")
        require(Bool.not(locator_before(tail, U32.sub(offset, start))), "UnsupportedZIP64", offset, "ZIP64 locator precedes end record")
        require(U32.is_zero(disk) && U32.is_zero(central_disk) && U32.is_eq(disk_entries, entries), "UnsupportedMultiDisk", offset, "split archives are not implemented")
        require(U32.is_le(central_size, max_index) && U32.is_le(entries, max_entries), "IndexLimit", offset, "directory bytes or entry count exceed limits")
        return end

def end_record(+size: U32, +tail: List<&2, U32>, +limits: Limits) -> Result<&2, &2, Error, End>:
  Limits{+max_file, index, entries, name, compressed, output} = limits
  do Result<&2, &2, Error, End>:
    require(limits_valid(limits), "InvalidLimits", 0, "configured limits exceed supported bounds")
    require(U32.is_le(size, max_file), "FileLimit", 0, "archive exceeds file-size limit")
    +length : U32 <- byte_count(tail, 65577, 0)
    require(U32.is_eq(length, choose(U32, size, 65577, U32.is_lt(size, 65577))), "TailSize", 0, "tail must be the exact final min(file size,65577) bytes")
    end_checked(end_scan(tail, U32.sub(size, length), size, None{}, []), tail, U32.sub(size, length), limits)

def extras_loop(fuel: Nat, cursor: Cursor) -> Result<&2, &2, Error, Unit>:
  match fuel cursor:
    case _ Cursor{Nil{}, offset}: Done{Unit{}}
    case 0n Cursor{_, offset}: fail(Unit, "ExtraWorkLimit", offset, "extra parsing exhausted finite byte-count fuel")
    case 1n+next Cursor{a <> b <> c <> d <> rest, +offset}:
      +id = le16([a, b])
      +length = le16([c, d])
      do Result<&2, &2, Error, Unit>:
        require(U32.is_ne(id, 1), "UnsupportedZIP64", offset, "ZIP64 extra field is not implemented")
        skipped : Cursor <- skip(U32.to_nat(length), Cursor{rest, U32.add(offset, 4)})
        extras_loop(next, skipped)
    case _ Cursor{_, offset}: fail(Unit, "TruncatedExtra", offset, "extra field has no complete type/length header")

def extras(+bytes: List<&2, U32>, offset: U32) -> Result<&2, &2, Error, Unit>:
  extras_loop(List.length(&2, U32, bytes), Cursor{bytes, offset})

def cp437_table() -> String:
  "ÇüéâäàåçêëèïîìÄÅÉæÆôöòûùÿÖÜ¢£¥₧ƒáíóúñÑªº¿⌐¬½¼¡«»░▒▓│┤╡╢╖╕╣║╗╝╜╛┐└┴┬├─┼╞╟╚╔╩╦╠═╬╧╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀αßΓπΣσµτΦΘΩδ∞φε∩≡±≥≤⌠⌡÷≈°∙·√ⁿ²■ "

def cp437_high(found: Maybe<&2, Char>) -> Char:
  match found:
    case Some{char}: char
    case None{}: Chr{65533}

def cp437_checked(byte: U32, ascii: Bool) -> Char:
  match ascii:
    case True{}: Chr{byte}
    case False{}: cp437_high(String.get(cp437_table(), U32.to_nat(U32.sub(byte, 128))))

def cp437_char(+byte: U32) -> Char:
  cp437_checked(byte, U32.is_lt(byte, 128))

def cp437_name(bytes: List<&2, U32>, reversed: String) -> String:
  match bytes:
    case Nil{}: String.reverse(reversed)
    case byte <> rest: cp437_name(rest, SCon{cp437_char(byte), reversed})

def name_utf8(result: Result<&2, &2, String, String>, offset: U32) -> Result<&2, &2, Error, String>:
  match result:
    case Done{name}: Done{name}
    case Fail{message}: fail(String, "InvalidNameUTF8", offset, message)

def name_decode_inner(bytes: List<&2, U32>, encoding: NameEncoding, utf8: Bool, offset: U32) -> Result<&2, &2, Error, String>:
  match encoding utf8:
    case CP437Fallback{} False{}: Done{cp437_name(bytes, "")}
    case _ _: name_utf8(F.decode_loop(bytes, Done{F.Utf8{0, 0, 0, "", 0}}), offset)

def name_decode(bytes: List<&2, U32>, flags: U32, encoding: NameEncoding, offset: U32) -> Result<&2, &2, Error, String>:
  name_decode_inner(bytes, encoding, U32.is_ne(U32.and(flags, 2048), 0), offset)

# Comments need charset validation but no decoded text. Reset only the discarded
# output/count after each byte, preserving pending UTF-8 state. This removes the
# framing decoder's line-length cap without weakening its scalar validation.
def comment_next(result: Result<&2, &2, String, F.Utf8>) -> Result<&2, &2, String, F.Utf8>:
  match result:
    case Fail{message}: Fail{message}
    case Done{F.Utf8{need, code, minimum, reversed, count}}: Done{F.Utf8{need, code, minimum, "", 0}}

def comment_loop(bytes: List<&2, U32>, result: Result<&2, &2, String, F.Utf8>, +offset: U32) -> Result<&2, &2, Error, Unit>:
  match bytes result:
    case _ Fail{message}: fail(Unit, "InvalidCommentUTF8", offset, message)
    case Nil{} Done{F.Utf8{0, code, minimum, reversed, count}}: Done{Unit{}}
    case Nil{} Done{_}: fail(Unit, "InvalidCommentUTF8", offset, "truncated UTF-8 entry comment")
    case byte <> rest Done{state}: comment_loop(rest, comment_next(F.decode_byte(state, byte)), U32.inc(offset))

def comment_inner(bytes: List<&2, U32>, encoding: NameEncoding, utf8: Bool, offset: U32) -> Result<&2, &2, Error, Unit>:
  match encoding utf8:
    case CP437Fallback{} False{}: Done{Unit{}}
    case _ _: comment_loop(bytes, Done{F.Utf8{0, 0, 0, "", 0}}, offset)

def comment_valid(bytes: List<&2, U32>, flags: U32, encoding: NameEncoding, offset: U32) -> Result<&2, &2, Error, Unit>:
  comment_inner(bytes, encoding, U32.is_ne(U32.and(flags, 2048), 0), offset)

def flags_valid(+flags: U32, +method: U32, +offset: U32) -> Result<&2, &2, Error, Unit>:
  do Result<&2, &2, Error, Unit>:
    require(U32.is_zero(U32.and(flags, 8257)), "UnsupportedEncryption", offset, "encrypted/masked entries are not implemented")
    require(U32.is_zero(U32.and(flags, 63473)), "UnsupportedFlags", offset, "entry uses unsupported general-purpose flags")
    require(U32.is_eq(method, 0) || U32.is_eq(method, 8), "UnsupportedMethod", offset, "only stored and deflate entries are implemented")
    require(U32.is_eq(method, 8) || U32.is_zero(U32.and(flags, 6)), "UnsupportedFlags", offset, "deflate speed flags are invalid for stored entries")

def central_variable(+header: List<&2, U32>, cursor: Cursor, +ordinal: U32, +encoding: NameEncoding, limits: Limits) -> Result<&2, &2, Error, Read<Entry>>:
  Limits{file, index, entries, +max_name, +max_compressed, +max_output} = limits
  +flags = word16(header, 8)
  +method = word16(header, 10)
  +compressed = word32(header, 20)
  +size = word32(header, 24)
  +name_size = word16(header, 28)
  +extra_size = word16(header, 30)
  +comment_size = word16(header, 32)
  +offset = word32(header, 42)
  +needed = word16(header, 6)
  do Result<&2, &2, Error, Read<Entry>>:
    require(U32.is_ne(compressed, 4294967295) && U32.is_ne(size, 4294967295) && U32.is_ne(offset, 4294967295), "UnsupportedZIP64", offset, "entry contains ZIP64 sentinels")
    require(U32.is_zero(word16(header, 34)), "UnsupportedMultiDisk", offset, "entry refers to a different disk")
    flags_valid(flags, method, offset)
    require(U32.is_le(needed, 20), "UnsupportedVersion", offset, "entry requires ZIP features beyond version 2.0")
    require(U32.is_le(U32.add(46, U32.add(name_size, U32.add(extra_size, comment_size))), 65535), "CentralRecordLimit", offset, "central header plus variable fields exceeds Java ZipFile's 65535-byte record bound")
    require(U32.is_le(name_size, max_name) && U32.is_le(compressed, max_compressed) && U32.is_le(size, max_output), "EntryLimit", offset, "name/compressed/output length exceeds limit")
    require(U32.is_eq(method, 8) || U32.is_eq(compressed, size), "StoredSizeMismatch", offset, "stored lengths must agree")
    named : Read<List<&2, U32>> <- chunk(U32.to_nat(name_size), cursor, [])
    read_with(List<&2, U32>, Result<&2, &2, Error, Read<Entry>>, named, cursor => +raw_name => (
      do Result<&2, &2, Error, Read<Entry>>:
        name : String <- name_decode(raw_name, flags, encoding, offset)
        extra : Read<List<&2, U32>> <- chunk(U32.to_nat(extra_size), cursor, [])
        read_with(List<&2, U32>, Result<&2, &2, Error, Read<Entry>>, extra, cursor => bytes => (
          do Result<&2, &2, Error, Read<Entry>>:
            extras(bytes, offset)
            commented : Read<List<&2, U32>> <- chunk(U32.to_nat(comment_size), cursor, [])
            read_with(List<&2, U32>, Result<&2, &2, Error, Read<Entry>>, commented, cursor => comment => (
              do Result<&2, &2, Error, Read<Entry>>:
                comment_valid(comment, flags, encoding, offset)
                return Read{cursor, Entry{ordinal, name, raw_name, needed, flags, method, word32(header, 16), compressed, size, offset, 0}}
            ))
        ))
    ))

def cursor_offset(cursor: Cursor) -> U32:
  Cursor{bytes, offset} = cursor
  offset

def central_one(cursor: Cursor, +ordinal: U32, encoding: NameEncoding, limits: Limits) -> Result<&2, &2, Error, Read<Entry>>:
  do Result<&2, &2, Error, Read<Entry>>:
    got : Read<List<&2, U32>> <- chunk(46n, cursor, [])
    read_with(List<&2, U32>, Result<&2, &2, Error, Read<Entry>>, got, +cursor => +header => (
      do Result<&2, &2, Error, Read<Entry>>:
        require(U32.is_eq(le32(header), 33639248), "CentralSignature", U32.sub(cursor_offset(cursor), 46), "central record has invalid signature")
        central_variable(header, cursor, ordinal, encoding, limits)
    ))

def central_loop(n: Nat, cursor: Cursor, +ordinal: U32, +encoding: NameEncoding, +limits: Limits, reversed: List<&2, Entry>) -> Result<&2, &2, Error, List<&2, Entry>>:
  match n cursor:
    case 0n Cursor{Nil{}, offset}: Done{List.reverse(&2, Entry, reversed)}
    case 0n Cursor{_, offset}: fail(List<&2, Entry>, "CentralSize", offset, "entry count leaves unparsed directory bytes")
    case 1n+rest _:
      do Result<&2, &2, Error, List<&2, Entry>>:
        got : Read<Entry> <- central_one(cursor, ordinal, encoding, limits)
        read_with(Entry, Result<&2, &2, Error, List<&2, Entry>>, got, cursor => entry => (
          central_loop(rest, cursor, U32.inc(ordinal), encoding, limits, entry <> reversed)
        ))

def offset_of(entry: Entry) -> U32:
  Entry{ordinal, name, raw, needed, flags, method, crc, compressed, size, offset, ceiling} = entry
  offset

def ordinal_of(entry: Entry) -> U32:
  Entry{ordinal, name, raw, needed, flags, method, crc, compressed, size, offset, ceiling} = entry
  ordinal

def entry_name(entry: Entry) -> String:
  Entry{ordinal, name, raw, needed, flags, method, crc, compressed, size, offset, ceiling} = entry
  name

def by_offset(a: Entry, b: Entry) -> Bool:
  U32.is_le(offset_of(a), offset_of(b))

def by_ordinal(a: Entry, b: Entry) -> Bool:
  U32.is_le(ordinal_of(a), ordinal_of(b))

def bounded_entry(entry: Entry, +ceiling: U32) -> Result<&2, &2, Error, Entry>:
  Entry{ordinal, name, +raw, needed, +flags, method, crc, +compressed, size, +offset, old_ceiling} = entry
  +minimum = U32.add(30, U32.add(U32.from_nat(List.length(&2, U32, raw)), compressed))
  +descriptor = choose(U32, 12, 0, U32.is_ne(U32.and(flags, 8), 0))
  do Result<&2, &2, Error, Entry>:
    require(span(offset, U32.add(minimum, descriptor), ceiling), "LocalOverlap", offset, "minimum local span crosses the next local header or central directory")
    return Entry{ordinal, name, raw, needed, flags, method, crc, compressed, size, offset, ceiling}

def next_offset(entries: List<&2, Entry>, central_offset: U32) -> U32:
  match entries:
    case Nil{}: central_offset
    case entry <> rest: offset_of(entry)

def bound_offsets(sorted: List<&2, Entry>, +central_offset: U32, reversed: List<&2, Entry>) -> Result<&2, &2, Error, List<&2, Entry>>:
  match sorted:
    case Nil{}: Done{List.reverse(&2, Entry, reversed)}
    case entry <> +rest:
      do Result<&2, &2, Error, List<&2, Entry>>:
        bounded : Entry <- bounded_entry(entry, next_offset(rest, central_offset))
        bound_offsets(rest, central_offset, bounded <> reversed)

def names_index(entries: List<&2, Entry>, names: Map<&2, Maybe<&2, Entry>>) -> Map<&2, Maybe<&2, Entry>>:
  match entries:
    case Nil{}: names
    case +entry <> rest: names_index(rest, Map.set(&2, Maybe<&2, Entry>, names, entry_name(entry), Some{entry}))

def directory(+end: End, +bytes: List<&2, U32>, encoding: NameEncoding, +limits: Limits) -> Result<&2, &2, Error, Directory>:
  End{+file_size, +offset, +central_offset, +central_size, +entries, disk, central_disk, disk_entries} = end
  Limits{max_file, max_index, max_entries, name, compressed, output} = limits
  do Result<&2, &2, Error, Directory>:
    require(limits_valid(limits), "InvalidLimits", 0, "configured limits exceed supported bounds")
    require(U32.is_le(file_size, max_file) && U32.is_le(central_size, max_index) && U32.is_le(entries, max_entries), "IndexLimit", central_offset, "directory exceeds configured file/index/count limits")
    require(span(offset, 22, file_size) && span(central_offset, central_size, offset) && U32.is_eq(U32.add(central_offset, central_size), offset), "CentralBounds", central_offset, "central/end record extents are inconsistent")
    require(U32.is_zero(disk) && U32.is_zero(central_disk) && U32.is_eq(disk_entries, entries), "UnsupportedMultiDisk", offset, "split archives are not implemented")
    actual : U32 <- byte_count(bytes, central_size, 0)
    require(U32.is_eq(actual, central_size), "CentralSize", central_offset, "directory slice has the wrong byte length")
    records : List<&2, Entry> <- central_loop(U32.to_nat(entries), Cursor{bytes, central_offset}, 0, encoding, limits, [])
    bounded : List<&2, Entry> <- bound_offsets(List.sort(~Entry, ~by_offset, records), central_offset, [])
    (
      +ordered = List.sort(~Entry, ~by_ordinal, bounded)
      Done{Directory{end, ordered, names_index(ordered, MTip{})}}
    )

def lookup_result(result: Map<&2, Maybe<&2, Entry>> & Maybe<&2, Entry>) -> Maybe<&2, Entry>:
  (names, found) = result
  found

def lookup(directory: Directory, name: String) -> Maybe<&2, Entry>:
  Directory{end, entries, names} = directory
  lookup_result(Map.get(Maybe<&2, Entry>, None{}, names, name))

def lookup_slash(directory: Directory, name: String, needed: Bool) -> Maybe<&2, Entry>:
  match needed:
    case True{}: lookup(directory, name ++ "/")
    case False{}: None{}

def lookup_java_found(found: Maybe<&2, Entry>, directory: Directory, +name: String) -> Maybe<&2, Entry>:
  match found:
    case Some{entry}: Some{entry}
    case None{}: lookup_slash(directory, name, Bool.not(String.ends_with(name, "/")))

def lookup_java(+directory: Directory, +name: String) -> Maybe<&2, Entry>:
  lookup_java_found(lookup(directory, name), directory, name)

def names_of(entries: List<&2, Entry>) -> List<&2, String>:
  match entries:
    case Nil{}: []
    case entry <> rest: entry_name(entry) <> names_of(rest)

def entry_names(directory: Directory) -> List<&2, String>:
  Directory{end, entries, names} = directory
  names_of(entries)

def parse_directory(+end: End, bytes: List<&2, U32>, encoding: NameEncoding, limits: Limits) -> Result<&2, &2, Error, Directory>:
  End{file_size, offset, central_offset, central_size, entries, disk, central_disk, disk_entries} = end
  directory(end, List.take(&2, U32, List.drop(&2, U32, bytes, U32.to_nat(central_offset)), U32.to_nat(central_size)), encoding, limits)

def parse(+bytes: List<&2, U32>, +encoding: NameEncoding, +limits: Limits) -> Result<&2, &2, Error, Directory>:
  Limits{+max_file, index, entries, name, compressed, output} = limits
  do Result<&2, &2, Error, Directory>:
    +size : U32 <- byte_count(bytes, max_file, 0)
    end : End <- end_record(size, List.drop(&2, U32, bytes, U32.to_nat(choose(U32, 0, U32.sub(size, 65577), U32.is_le(size, 65577)))), limits)
    parse_directory(end, bytes, encoding, limits)

def bytes_equal(a: List<&2, U32>, b: List<&2, U32>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case x <> xs y <> ys: U32.is_eq(x, y) && bytes_equal(xs, ys)
    case _ _: False{}

def local_count(entry: Entry, +header: List<&2, U32>, +limits: Limits) -> Result<&2, &2, Error, U32>:
  Entry{ordinal, name, raw, +needed, +flags, +method, +crc, +compressed, +size, +offset, +ceiling} = entry
  Limits{file, index, entries, +max_name, max_compressed, max_output} = limits
  +name_size = word16(header, 26)
  +extra_size = word16(header, 28)
  +data_length = U32.add(30, U32.add(name_size, U32.add(extra_size, compressed)))
  +descriptor = U32.is_ne(U32.and(flags, 8), 0)
  do Result<&2, &2, Error, U32>:
    require(limits_valid(limits), "InvalidLimits", offset, "configured limits exceed supported bounds")
    require(U32.is_le(compressed, max_compressed) && U32.is_le(size, max_output), "EntryLimit", offset, "compressed/output lengths exceed limit")
    require(U32.is_eq(method, 8) || U32.is_eq(compressed, size), "StoredSizeMismatch", offset, "stored lengths must agree")
    count : U32 <- byte_count(header, 30, 0)
    require(U32.is_eq(count, 30), "TruncatedLocal", offset, "local header needs 30 bytes")
    require(U32.is_eq(le32(header), 67324752), "LocalSignature", offset, "local header has invalid signature")
    require(U32.is_eq(word16(header, 4), needed) && U32.is_eq(word16(header, 6), flags) && U32.is_eq(word16(header, 8), method), "LocalMetadataMismatch", offset, "local version/flags/method differ from central record")
    require(U32.is_le(name_size, max_name), "EntryLimit", offset, "local name exceeds configured limit")
    require(span(offset, data_length, ceiling), "LocalOverlap", offset, "local metadata or compressed data crosses its entry ceiling")
    require((descriptor && (U32.is_zero(word32(header, 14)) || U32.is_eq(word32(header, 14), crc)) &&
      (U32.is_zero(word32(header, 18)) || U32.is_eq(word32(header, 18), compressed)) &&
      (U32.is_zero(word32(header, 22)) || U32.is_eq(word32(header, 22), size))) ||
      (Bool.not(descriptor) && U32.is_eq(word32(header, 14), crc) && U32.is_eq(word32(header, 18), compressed) && U32.is_eq(word32(header, 22), size)),
      "LocalSizeMismatch", offset, "local CRC/length fields contradict the central record")
    (
      +room = U32.sub(ceiling, U32.add(offset, data_length))
      +extra = choose(U32, choose(U32, room, 16, U32.is_lt(room, 16)), 0, descriptor)
      Done{U32.add(data_length, extra)}
    )

def descriptor_matches(+bytes: List<&2, U32>, +crc: U32, +compressed: U32, +size: U32, +shift: U32) -> Bool:
  U32.is_ge(U32.from_nat(List.length(&2, U32, bytes)), U32.add(shift, 12)) &&
    U32.is_eq(word32(bytes, shift), crc) && U32.is_eq(word32(bytes, U32.add(shift, 4)), compressed) && U32.is_eq(word32(bytes, U32.add(shift, 8)), size)

def descriptor_checked(+bytes: List<&2, U32>, flags: U32, +crc: U32, +compressed: U32, +size: U32, offset: U32) -> Result<&2, &2, Error, Unit>:
  require(U32.is_zero(U32.and(flags, 8)) || descriptor_matches(bytes, crc, compressed, size, 0) ||
    (U32.is_eq(le32(bytes), 134695760) && descriptor_matches(bytes, crc, compressed, size, 4)), "DescriptorMismatch", offset, "classic descriptor is truncated or disagrees with central CRC/lengths")

def inflated(result: Result<&2, &1, C.Error, C.Decoded>, +compressed: U32, +size: U32, +crc: U32, +offset: U32) -> Result<&2, &2, Error, List<&2, U32>>:
  match result:
    case Fail{C.Error{code}}: fail(List<&2, U32>, "DeflateError", offset, code)
    case Done{C.Decoded{bytes, +actual_size, consumed, adler, +actual_crc}}:
      do Result<&2, &2, Error, List<&2, U32>>:
        require(U32.is_eq(consumed, compressed), "CompressedSizeMismatch", offset, "deflate decoder did not consume the exact entry slice")
        require(U32.is_eq(actual_size, size), "OutputSizeMismatch", offset, "deflate output length disagrees with central record")
        require(U32.is_eq(actual_crc, crc), "CRCMismatch", offset, "decoded entry CRC32 disagrees with central record")
        return bytes

def payload(method: U32, +bytes: List<&2, U32>, compressed: U32, +size: U32, +crc: U32, +offset: U32, limits: Limits) -> Result<&2, &2, Error, List<&2, U32>>:
  match method:
    case 0:
      do Result<&2, &2, Error, List<&2, U32>>:
        require(U32.is_eq(C.crc32(bytes), crc), "CRCMismatch", offset, "stored entry CRC32 disagrees with central record")
        return bytes
    case 8:
      Limits{file, index, entries, name, max_compressed, +max_output} = limits
      inflated(C.inflate_raw(bytes, C.Limits{max_compressed, choose(U32, size, max_output, U32.is_le(size, max_output))}), compressed, size, crc, offset)
    case _: fail(List<&2, U32>, "UnsupportedMethod", offset, "only stored and deflate entries are implemented")

def extract_payload(cursor: Cursor, flags: U32, method: U32, data: List<&2, U32>, +compressed: U32, +size: U32, +crc: U32, offset: U32, limits: Limits) -> Result<&2, &2, Error, List<&2, U32>>:
  match cursor:
    case Cursor{tail, end}:
      do Result<&2, &2, Error, List<&2, U32>>:
        descriptor_checked(tail, flags, crc, compressed, size, end)
        payload(method, data, compressed, size, crc, offset, limits)

def extract_body(+entry: Entry, +header: List<&2, U32>, cursor: Cursor, +limits: Limits) -> Result<&2, &2, Error, List<&2, U32>>:
  Entry{ordinal, name, +raw, needed, +flags, +method, +crc, +compressed, +size, +offset, ceiling} = entry
  do Result<&2, &2, Error, List<&2, U32>>:
    named : Read<List<&2, U32>> <- chunk(U32.to_nat(word16(header, 26)), cursor, [])
    read_with(List<&2, U32>, Result<&2, &2, Error, List<&2, U32>>, named, cursor => local_name => (
      do Result<&2, &2, Error, List<&2, U32>>:
        require(bytes_equal(raw, local_name), "LocalNameMismatch", offset, "raw local name differs from central name")
        extra : Read<List<&2, U32>> <- chunk(U32.to_nat(word16(header, 28)), cursor, [])
        read_with(List<&2, U32>, Result<&2, &2, Error, List<&2, U32>>, extra, cursor => extra_bytes => (
          do Result<&2, &2, Error, List<&2, U32>>:
            extras(extra_bytes, offset)
            data : Read<List<&2, U32>> <- chunk(U32.to_nat(compressed), cursor, [])
            read_with(List<&2, U32>, Result<&2, &2, Error, List<&2, U32>>, data, cursor => data_bytes => (
              extract_payload(cursor, flags, method, data_bytes, compressed, size, crc, offset, limits)
            ))
        ))
    ))

def extract(+entry: Entry, +bytes: List<&2, U32>, +limits: Limits) -> Result<&2, &2, Error, List<&2, U32>>:
  Limits{file, index, entries, name, +max_compressed, max_output} = limits
  do Result<&2, &2, Error, List<&2, U32>>:
    +actual : U32 <- byte_count(bytes, U32.add(max_compressed, 131116), 0)
    got : Read<List<&2, U32>> <- chunk(30n, Cursor{bytes, offset_of(entry)}, [])
    read_with(List<&2, U32>, Result<&2, &2, Error, List<&2, U32>>, got, cursor => +header => (
      do Result<&2, &2, Error, List<&2, U32>>:
        expected : U32 <- local_count(entry, header, limits)
        require(U32.is_eq(actual, expected), "LocalSliceSize", offset_of(entry), "entry slice length differs from planned bounded read")
        extract_body(entry, header, cursor, limits)
    ))

def io_error(offset: U32, code: U32, message: String) -> Error:
  Error{"FileIO", offset, "host error " ++ U32.show(code) ++ ": " ++ message}

def load_error(file: File, error: Error) -> IO(Result<&2, &1, Error, Archive>):
  do IO<Result<&2, &1, Error, Archive>>:
    File.close(file)
    return Fail{error}

def load_index_checked(file: File, result: Result<&2, &2, Error, Directory>, limits: Limits) -> IO(Result<&2, &1, Error, Archive>):
  match result:
    case Fail{error}: load_error(file, error)
    case Done{directory}: IO.pure(Result<&2, &1, Error, Archive>, Done{Archive{file, directory, limits}})

def load_central_read(read: File & Result<&1, &1, U32 & String, List<&2, U32>>, end: End, encoding: NameEncoding, +limits: Limits) -> IO(Result<&2, &1, Error, Archive>):
  (file, result) = read
  match result:
    case Fail{(code, message)}: load_error(file, io_error(0, code, message))
    case Done{bytes}: load_index_checked(file, directory(end, bytes, encoding, limits), limits)

def load_end_checked(file: File, result: Result<&2, &2, Error, End>, encoding: NameEncoding, limits: Limits) -> IO(Result<&2, &1, Error, Archive>):
  match result:
    case Fail{error}: load_error(file, error)
    case Done{+end}:
      End{file_size, offset, central_offset, central_size, entries, disk, central_disk, disk_entries} = end
      do IO<Result<&2, &1, Error, Archive>>:
        read : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_at(file, central_offset, central_size)
        load_central_read(read, end, encoding, limits)

def load_tail_read(read: File & Result<&1, &1, U32 & String, List<&2, U32>>, size: U32, encoding: NameEncoding, +limits: Limits) -> IO(Result<&2, &1, Error, Archive>):
  (file, result) = read
  match result:
    case Fail{(code, message)}: load_error(file, io_error(0, code, message))
    case Done{bytes}: load_end_checked(file, end_record(size, bytes, limits), encoding, limits)

def size_allowed(+size: U32, +limits: Limits) -> Bool:
  Limits{max_file, index, entries, name, compressed, output} = limits
  limits_valid(limits) && U32.is_le(size, max_file)

def load_size_checked(file: File, +size: U32, encoding: NameEncoding, +limits: Limits, allowed: Bool) -> IO(Result<&2, &1, Error, Archive>):
  match allowed:
    case False{}: load_error(file, choose(Error, Error{"FileLimit", 0, "archive exceeds file-size limit"}, Error{"InvalidLimits", 0, "configured limits exceed supported bounds"}, limits_valid(limits)))
    case True{}:
      +length = choose(U32, size, 65577, U32.is_lt(size, 65577))
      do IO<Result<&2, &1, Error, Archive>>:
        read : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_at(file, U32.sub(size, length), length)
        load_tail_read(read, size, encoding, limits)

def load_size_read(read: File & Result<&1, &1, U32 & String, U32>, encoding: NameEncoding, +limits: Limits) -> IO(Result<&2, &1, Error, Archive>):
  (file, result) = read
  match result:
    case Fail{(code, message)}: load_error(file, io_error(0, code, message))
    case Done{+size}: load_size_checked(file, size, encoding, limits, size_allowed(size, limits))

def load_open(opened: Result<&1, &1, U32 & String, File>, encoding: NameEncoding, limits: Limits) -> IO(Result<&2, &1, Error, Archive>):
  match opened:
    case Fail{(code, message)}: IO.pure(Result<&2, &1, Error, Archive>, Fail{io_error(0, code, message)})
    case Done{file}:
      do IO<Result<&2, &1, Error, Archive>>:
        read : File & Result<&1, &1, U32 & String, U32> <- File.size(file)
        load_size_read(read, encoding, limits)

def load(path: String, encoding: NameEncoding, limits: Limits) -> IO(Result<&2, &1, Error, Archive>):
  do IO<Result<&2, &1, Error, Archive>>:
    opened : Result<&1, &1, U32 & String, File> <- File.open(path, "r")
    load_open(opened, encoding, limits)

def Archive.close(archive: Archive) -> IO(Unit):
  match archive:
    case Archive{file, directory, limits}: File.close(file)

def Archive.directory(archive: Archive) -> Archive & Directory:
  match archive:
    case Archive{file, +directory, limits}: (Archive{file, directory, limits}, directory)

def entry_read_result(read: File & Result<&1, &1, U32 & String, List<&2, U32>>, directory: Directory, +limits: Limits, entry: Entry) -> IO(Archive & Result<&2, &2, Error, List<&2, U32>>):
  (file, result) = read
  match result:
    case Fail{(code, message)}: IO.pure(Archive & Result<&2, &2, Error, List<&2, U32>>, (Archive{file, directory, limits}, Fail{io_error(0, code, message)}))
    case Done{bytes}: IO.pure(Archive & Result<&2, &2, Error, List<&2, U32>>, (Archive{file, directory, limits}, extract(entry, bytes, limits)))

def entry_read_planned(file: File, directory: Directory, limits: Limits, +entry: Entry, result: Result<&2, &2, Error, U32>) -> IO(Archive & Result<&2, &2, Error, List<&2, U32>>):
  match result:
    case Fail{error}: IO.pure(Archive & Result<&2, &2, Error, List<&2, U32>>, (Archive{file, directory, limits}, Fail{error}))
    case Done{count}:
      do IO<Archive & Result<&2, &2, Error, List<&2, U32>>>:
        read : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_at(file, offset_of(entry), count)
        entry_read_result(read, directory, limits, entry)

def entry_header_read(read: File & Result<&1, &1, U32 & String, List<&2, U32>>, directory: Directory, +limits: Limits, +entry: Entry) -> IO(Archive & Result<&2, &2, Error, List<&2, U32>>):
  (file, result) = read
  match result:
    case Fail{(code, message)}: IO.pure(Archive & Result<&2, &2, Error, List<&2, U32>>, (Archive{file, directory, limits}, Fail{io_error(0, code, message)}))
    case Done{bytes}: entry_read_planned(file, directory, limits, entry, local_count(entry, bytes, limits))

def entry_read(archive: Archive, +entry: Entry) -> IO(Archive & Result<&2, &2, Error, List<&2, U32>>):
  match archive:
    case Archive{file, directory, limits}:
      do IO<Archive & Result<&2, &2, Error, List<&2, U32>>>:
        read : File & Result<&1, &1, U32 & String, List<&2, U32>> <- File.read_at(file, offset_of(entry), 30)
        entry_header_read(read, directory, limits, entry)

def entry_found(archive: Archive, found: Maybe<&2, Entry>) -> IO(Archive & Result<&2, &2, Error, List<&2, U32>>):
  match found:
    case None{}: IO.pure(Archive & Result<&2, &2, Error, List<&2, U32>>, (archive, Fail{Error{"MissingEntry", 0, "virtual entry was not found"}}))
    case Some{entry}: entry_read(archive, entry)

def Archive.read(archive: Archive, name: String) -> IO(Archive & Result<&2, &2, Error, List<&2, U32>>):
  match archive:
    case Archive{file, +directory, limits}: entry_found(Archive{file, directory, limits}, lookup_java(directory, name))

def find_ordinal(entries: List<&2, Entry>, +ordinal: U32) -> Maybe<&2, Entry>:
  match entries:
    case Nil{}: None{}
    case +entry <> rest: choose(Maybe<&2, Entry>, Some{entry}, find_ordinal(rest, ordinal), U32.is_eq(ordinal_of(entry), ordinal))

def Archive.read_ordinal(archive: Archive, ordinal: U32) -> IO(Archive & Result<&2, &2, Error, List<&2, U32>>):
  match archive:
    case Archive{file, +directory, limits}:
      Directory{end, entries, names} = directory
      entry_found(Archive{file, directory, limits}, find_ordinal(entries, ordinal))
