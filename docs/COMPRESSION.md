# Checked pure compression substrate

`src/compression.bend` implements bounded byte decoding in pure Bend:
[RFC 1951 DEFLATE](https://www.rfc-editor.org/rfc/rfc1951),
[RFC 1950 zlib](https://www.rfc-editor.org/rfc/rfc1950), and
[RFC 1952 gzip](https://www.rfc-editor.org/rfc/rfc1952). There is no host
inflater, compiler/runtime change, `unsafe` declaration or axiom. Base supplies
ordinary arithmetic, affine arrays and finite lists. Python creates fixtures,
extracts reference inputs and orchestrates native processes; it never supplies
decompressed bytes to the Bend decoder as an implementation shortcut.

## Public API

```python
type Limits is Data:
  Limits{max_input: U32, max_output: U32}

type Error is Data:
  Error{code: String}

type Decoded is Data:
  Decoded{bytes: List<&2, U32>, size: U32, consumed: U32,
          adler32: U32, crc32: U32}

type Encoded is Data:
  Encoded{bytes: List<&2, U32>, size: U32, source_size: U32,
          adler32: U32, crc32: U32}

inflate_raw(bytes, limits)  -> Result<&2, &1, Error, Decoded>
inflate_zlib(bytes, limits) -> Result<&2, &1, Error, Decoded>
inflate_gzip(bytes, limits) -> Result<&2, &1, Error, Decoded>

store_raw(bytes, limits)    -> Result<&2, &1, Error, Encoded>
store_zlib(bytes, limits)   -> Result<&2, &1, Error, Encoded>
store_gzip(bytes, limits)   -> Result<&2, &1, Error, Encoded>

adler32(bytes: List<&2, U32>) -> U32
crc32(bytes: List<&2, U32>)   -> U32
```

Every codec's `bytes` argument is `List<&2, U32>`. The entry points validate
the entire input first: each U32 must be 0–255, and its length must fit
`max_input`. A zero bound is permitted. Empty compressed input is truncated;
a valid empty compressed stream may decode with `max_output = 0`.
The standalone checksum helpers require valid byte-valued inputs. They do not
perform a second range check or return an error result.

For decoding, `max_output` bounds the complete decoded byte count, including
all gzip members together. `Decoded.adler32` and `crc32` describe that complete
decoded output. On success the supplied compressed slice is consumed exactly:
`consumed` equals its byte length. Raw DEFLATE permits unused bits in its final
byte, as the format requires, and rejects extra whole bytes. A ZIP caller should
pass the entry's exact declared compressed slice and independently compare its
declared uncompressed size and CRC against the returned values.

For encoding, `max_output` bounds the complete encoded result, including block
headers and wrapper trailers. `Encoded.source_size`, `adler32` and `crc32`
describe the source input; `size` describes the encoded byte list. These writers
emit deterministic, byte-aligned stored blocks of at most 65535 payload bytes.
They provide interoperable output for persistence and pack plumbing; they do
not perform entropy compression. Empty input produces one empty final stored
block. Zlib uses header `78 01`. Gzip uses MTIME=0, XFL=0, OS=255 and no optional
fields, followed by the actual CRC and source size. Encoded size is source
length plus five bytes per stored block, plus six zlib or eighteen gzip wrapper
bytes; empty input counts as one block.

All entry points return either a complete successful result or an error with
no output field. Internal partially produced bytes are discarded on failure.
There are no file effects in the codec: publishing or persisting a successful
result remains the caller's responsibility. Internal state constructors and
helper definitions are implementation details, not supported entry points for
forged decoder/writer state.

## Decoder behavior and bounds

Raw decoding handles stored, fixed-Huffman and dynamic-Huffman blocks. It checks
stored LEN/NLEN complements, reserved block/literal/distance symbols, dynamic
alphabet counts, code lengths, oversubscribed and incomplete trees, missing
end-of-block codes, invalid code paths, repeat-before-previous and repeat
overflow. Code-length repeats may cross the literal/distance alphabet boundary.
Single one-bit symbol trees are supported where permitted; an empty distance
tree is supported for streams containing only literals.

Length/distance extra bits cover the full 3–258 and 1–32768 ranges. Each copy
reads from the evolving history, so overlapping references work. References
can cross DEFLATE block boundaries and the ring can wrap. Distance must fit
the bytes already produced in the current gzip member and the applicable
window. A reference cannot obtain uninitialized or previous-member bytes.
Before a length copy starts, its entire expansion must fit the remaining output
bound. Stored/literal output is checked byte by byte.

The history is an affine `Array<U32>` with 32768 logical byte slots. This is a
Bend tree array, not a claim of 32768 physical bytes of memory. Canonical
Huffman decoding uses finite count/symbol arrays and reads no more than the
declared maximum code length. A reader retains at most seven unused bits and
never reads ahead into a wrapper trailer. Output is accumulated privately in a
finite reversed list and materialized when decoding succeeds. The full input
and output are resident; there is no streaming API.

The main decoder's termination fuel is eight times the validated input byte
count plus one. Every nonterminal block/symbol step consumes input bits; stored
copies and dynamic code-length expansion have separate finite bounds. Gzip
member traversal and the stored writer also have finite fuel. Bounds use
remaining-capacity comparisons before addition to prevent U32 counter wrap.
`WorkLimit` is a defensive invariant failure, not a configurable approximation
of valid stream processing.

Zlib validates CM=8, CINFO≤7, FCHECK divisibility, the declared window and its
big-endian Adler32 trailer. FDICT returns `UnsupportedDictionary`: preset
dictionary loading is explicitly unsupported. Data after the trailer is
rejected.

Gzip validates magic, CM=8 and reserved flag bits, consumes the fixed header,
bounded XLEN extra data and terminated name/comment fields, and verifies FHCRC
when present. FTEXT is accepted without altering bytes; MTIME, XFL and OS are
not interpreted. Each member's little-endian CRC32 and ISIZE are verified.
Concatenated members are decoded, with a fresh logical history and member
checksum scope. Header metadata is not exposed. An invalid later member fails
the entire result. Trailing bytes must constitute another complete member.

Checksum arithmetic is real Adler32 modulo 65521 and reflected IEEE CRC32
with polynomial `EDB88320`, initial all-one state and final complement. Gzip
FHCRC uses the low sixteen bits of the CRC32 of the preceding header bytes.

Errors are fixed code strings, including `InvalidByte`, `InputLimit`,
`OutputLimit`, `Truncated`, `TrailingData`, `ReservedBlock`, `StoredLength`,
`LiteralCount`, `HuffmanLength`, `HuffmanOversubscribed`, `HuffmanIncomplete`,
`HuffmanCode`, `CodeLengthCount`, `CodeLengthRepeat`, `MissingEndCode`,
`ReservedLiteral`, `ReservedDistance`, `Distance`, `ZlibHeader`,
`UnsupportedDictionary`, `AdlerMismatch`, `GzipHeader`, `HeaderCrcMismatch`,
`CrcMismatch` and `SizeMismatch`. A malformed stream can violate several
conditions; the first detected condition determines the code.

Two oracle differences are explicit. RFC1951 permits a declared distance
alphabet of 32 symbols, with reserved 30/31 unused; this decoder accepts that
declaration while Python's zlib rejects counts above 30. Actual reserved-symbol
use fails. The declared zlib window is enforced even when a default zlib build
would accept a farther reference. Python convenience decompressors may also
discard extra raw/zlib bytes; the independent test oracle explicitly requires
complete consumption for this API contract.

## Verification

```sh
python3 tools/test_compression.py
/Users/chuah/.bend/bin/bend src/compression.bend --verdict
/Users/chuah/.bend/bin/bend tests/compression.bend --verdict
```

The rebuilt native suite passed **853 cases: 398 successes and 455 rejections**.
Every success compares exact output bytes, size, consumed input size and both
checksums. Every rejection confirms that no output file was created. Cases
cover all three block types, every length and distance code, extra bits,
overlap, ring wrapping, references across blocks, code-length repetition,
malformed trees/codes/headers/trailers, every prefix of small compressed streams,
input/output bounds, one-MiB expansion bombs, seeded random data and 450 mutated
streams. Wrapper tests cover gzip optional fields, FHCRC, concatenated members
and history isolation. Stored writers are checked at the 65535-byte boundary,
against independent deterministic packets and Python/Bend decoding roundtrips.

Reference fixtures come from the actual installed pinned 26.3 jar: compressed
ZIP assets, PNG IDAT zlib streams and gzip structure NBT. Extracted bytes remain
in temporary ignored build files and are removed after the test. Evidence stores
entry names, sizes and hashes rather than copyrighted asset payloads.
`evidence/compression-native.json` records source/input/compiler/binary hashes,
fixture categories, the exact kernel verdict and benchmark trials.

The source and tests receive `ALL PROOFS CHECK` from the independent BendTT
kernel. This establishes checked pure code and its stated finite fixture
equalities: empty checksums, invalid-byte rejection, a stored-byte fixture and
empty stored writing. There is no universal DEFLATE roundtrip or RFC-conformance
law, and native oracle success is not such a proof. Successful decompression
establishes no NBT semantics, asset appearance, pack behavior, save durability
or Minecraft gameplay parity.

## Measured performance

The test compares one-thread native Bend with a temporary `clang -O2` C zlib
driver. Both read the same file once, repeatedly create a fresh decoder/output,
validate a complete bounded zlib wrapper, compute CRC32 and obtain Adler32, and
scan every materialized output byte with the same FNV function. The C driver
uses `z_stream.adler` from its wrapper verification. The extra output scan keeps
discarded-output optimization from changing the workload. Each fixture runs
101 iterations in five trials. Reading, steady work and subprocess wall times
are recorded separately; Bend's monotonic clock has one-millisecond resolution.
The C driver is an independent benchmark only, never an implementation
dependency.

| Workload | Bend steady output | C zlib steady output | Bend/C steady elapsed |
| --- | ---: | ---: | ---: |
| Repetitive, 101 × 104552 output bytes | 14.45 MB/s | 864.70 MB/s | 59.86× |
| Entropy, 101 × 32768 output bytes | 2.60 MB/s | 925.49 MB/s | 356.26× |

These are the observed trials recorded with the pinned compiler and current
implementation, not an estimate of game speed. The slower result is material:
the checked substrate supplies interoperability and explicit bounds, while
high-volume asset loading still needs profiling and optimization. No CPU/GPU
speedup or full-game performance claim follows from this benchmark.
