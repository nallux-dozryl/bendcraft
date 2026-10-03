# Pure Bend NDJSON byte framing

`src/framing.bend` owns persistent receive buffering, LF record boundaries,
CRLF handling, strict UTF-8 decoding, line limits and the EOF decision. It
contains no foreign effect, host parser, unsafe definition or networking
implementation. `src/json.bend` remains responsible for JSON syntax and its
semantic error messages.

## Public API

```python
import ./framing.bend as F

# The constructor is public in Bend, but callers construct state through
# new/feed so size equals the length of reversed.
type Buffer is Data:
  Buffer{reversed: List<&2, U32>, size: U32}

F.new() -> F.Buffer
F.feed(buffer: F.Buffer, bytes: List<&2, U32>) ->
  Result<&1, &1, String, F.Buffer & List<&2, String>>
F.finish(buffer: F.Buffer) -> Result<&1, &1, String, Unit>
```

For each successful TCP receive, pass the raw byte list and the current
connection buffer to `F.feed`. On `Done`, retain the returned buffer and
dispatch the returned strings in order to the JSON parser. One receive can
complete zero, one or multiple records. TCP receive boundaries have no meaning
to the framing API. Bytes of one Unicode scalar may span any number of reads.

On `Fail`, close the connection. A failure consumes the buffer and returns no
successful lines from that same `feed` call, even if earlier records within
the call were valid. Lines returned by previous successful calls are already
outside that transaction. This avoids silently returning a successful batch
prefix beside a malformed later record.

Call `F.finish` at EOF. It accepts only an empty buffer. An unterminated final
record is never dispatched, even if it contains complete UTF-8 and otherwise
valid JSON. `feed` preserves incomplete bytes until LF or EOF; `finish`
rejects the incomplete record rather than trying to flush it.

## Envelope and decoding rules

- Every input list value must be in `0..255`. An out-of-range U32 fails
  immediately, including when no LF has arrived.
- LF byte `10` terminates a record and is excluded from its byte count.
- A single CR byte `13` immediately before LF is removed before UTF-8
  decoding. Other CR bytes are retained. An unfinished terminal CR remains
  buffered until the LF arrives.
- A record may contain at most `65536` bytes before LF, including a terminal
  CR. Appending byte `65537` fails immediately without waiting for LF.
- A completed, CR-trimmed record may decode to at most `16384` Unicode scalar
  code points, matching the JSON parser's input limit. That limit is checked
  during decoding at record completion, not while raw partial bytes accumulate.
- UTF-8 decoding accepts ASCII and canonical two-, three- and four-byte
  encodings. It rejects overlong forms, surrogate values `U+D800..U+DFFF`,
  values above `U+10FFFF`, lone continuation bytes, invalid leading bytes,
  missing/invalid continuation bytes, and a truncated encoding at completed LF.
- Malformed UTF-8 bytes in an incomplete record remain pending until LF.
  Framing is still bounded by the byte limit while such a record is pending.
- Empty records are returned as empty strings. BOM, NUL and other scalar
  characters are preserved. The JSON/application layer decides whether those
  records are valid; the framer does not silently skip empty lines or remove BOM.
- Decoding performs no replacement-character substitution or normalization.

The byte and scalar limits apply independently. Exactly `16384` four-byte
scalars occupy `65536` bytes and fit with LF. Adding CR for CRLF would exceed
the byte limit. `16383` four-byte scalars plus one three-byte scalar and CR
occupy exactly `65536` bytes and fit with CRLF.

For valid buffer states, accumulating partial bytes is constant work per
byte. Completed records are reversed and decoded in linear time. The buffer
contains at most `65536` pending bytes. The result batch is proportional to the
receive's completed records; the transport remains responsible for bounding
the size of each receive.

`Buffer` is pure Data and may be copied, but each connection normally has one
current value. The size/byte invariants are established by `new` and retained
by successful `feed`; manually forged constructors are outside this API
contract. No mutable or shared host buffer is involved.

## Verification

```sh
python3 tools/test_framing.py
```

The script compiles and runs `tests/framing.bend` as a native executable. A
trusted fixture adapter in that Bend test file converts decimal command-line
chunks to U32 lists, then calls the actual pure Bend `feed`/`finish`. It reports
decoded scalar lists, pending byte counts and FNV-1a over reversed pending
bytes. The latter independently checks preservation and byte order without
dumping large partial records at every split.

Python's strict built-in UTF-8 decoder supplies the Unicode oracle. Python
constructs inputs and expected traces; it does not provide the implementation
under test. The deterministic corpus includes every partition of selected
Unicode boundary encodings plus LF, every single split of multirecord JSON
bytes, all 256 single-byte values, explicit U32 values above 255, seeded
Unicode/arbitrary-byte splits, CRLF and empty chunks, incomplete EOF records,
malformed UTF-8, batch atomicity and both limits.

The recorded native run passed `1069` cases in `37` native batches across
`4736` receive chunks. `src/framing.bend --verdict` and
`tests/framing.bend --verdict` both report `ALL PROOFS CHECK`. The test file's
checked equality covers five finite split/rejection fixtures. This is not a
general UTF-8 or arbitrary-segmentation correctness theorem. Exact commands,
source/compiler/binary digests, corpus/observation digests and limit results
are in `evidence/framing-native.json`.

Confidence is high for the tested pure framing behavior. These tests do not
establish TCP transport integration or Minecraft behavior; the live server
must separately demonstrate persistent sockets and real receive splits using
this API.
