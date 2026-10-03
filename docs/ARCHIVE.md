# Checked ZIP/JAR byte access

`src/archive.bend` implements a bounded classic ZIP reader in Bend. It indexes
the central directory and reads verified entry bytes from a single owned file
handle. It is a substrate for later resource/data packs: it does not discover
pack stacks, interpret resources, create filesystem paths or write extracted
files. The installed Minecraft 26.3 JAR is the independent integration input.

ZIP record layouts and descriptor conventions follow the
[PKWARE ZIP specification](https://pkware.cachefly.net/webdocs/casestudies/APPNOTE.TXT).
The supported methods are stored and raw deflate, with CRC32 and exact output
length checks. Classic signed and unsigned data descriptors are accepted.
Unused final deflate padding bits are allowed by the compression decoder;
extra complete compressed bytes fail. See [COMPRESSION.md](COMPRESSION.md).

## API and ownership

```text
NameEncoding = UTF8Fallback | CP437Fallback
Limits { max_file, max_index, max_entries, max_name,
         max_compressed, max_output }  # U32 fields
Error { code:String, offset:U32, message:String }

parse(bytes:List<&2,U32>, encoding, limits)
  -> Result<&2,&2,Error,Directory>
end_record(file_size, exact_tail_bytes, limits)
  -> Result<&2,&2,Error,End>
directory(end, exact_central_bytes, encoding, limits)
  -> Result<&2,&2,Error,Directory>

load(path:String, encoding, limits)
  -> IO(Result<&2,&1,Error,Archive>)
Archive.directory(archive) -> Archive & Directory
Archive.read(archive, name:String)
  -> IO(Archive & Result<&2,&2,Error,List<&2,U32>>)
Archive.read_ordinal(archive, ordinal:U32)
  -> IO(Archive & Result<&2,&2,Error,List<&2,U32>>)
Archive.close(archive) -> IO(Unit)
```

`Directory` is reusable Data containing the end record, entries in central
order, and a name index. Each `Entry` records ordinal, decoded/raw name,
required version, flags, method, CRC32, compressed/output sizes, local offset
and a local ceiling. `Archive` is Type because its file handle has one owner.
Reads return that owner on success and failure; a missing or corrupt entry
does not close it or emit a partial payload. A failed load closes any file it
opened. `error_text` formats the category, byte context and diagnostic.
Offsets identify the implicated record or failing byte slice; central entry
metadata errors use that entry's declared local offset as context.

The low-level `extract(entry, exact_local_slice, limits)` is pure. It checks
the slice against a parsed entry, and `local_count` plans its bounded size
from a 30-byte prefix. These helpers do not authenticate a caller-created
`Entry` as belonging to an archive. Use the owned `Archive.read`/ordinal APIs
to obtain bytes authorized by the loaded index.

## Names and Java observations

The default is Java `ZipFile`'s UTF-8 fallback. Explicit `CP437Fallback` maps
unflagged bytes through IBM437. Bit 11 overrides either fallback with strict
UTF-8. This follows the charset selection documented in
[Java ZipFile](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/util/zip/ZipFile.html),
and is checked against the installed Java 25 runtime. Central entry comments
use the same charset rule and reject invalid UTF-8. They are validated but not
returned. The EOCD archive comment remains opaque bytes and may contain nulls,
invalid UTF-8 and record signatures.

The local Java oracle establishes these concrete behaviors:

- Central enumeration preserves order and duplicate names. Exact duplicate
  lookup returns the last central record. Ordinal reads preserve separate
  physical entries; the duplicate fixture yields `first`, then `last`.
- `lookup` requires an exact name. `lookup_java` and `Archive.read` first try
  that name, then append `/` when missing and not already ending in `/`.
- Raw UTF-8 names work without bit 11 under the default fallback. An unflagged
  CP437 byte name requires explicit CP437 mode. UTF-8 bit 11 still wins in
  CP437 mode. The 128 high-byte CP437 mappings are independently checked.
- Java ignores the Info-ZIP Unicode path extra field in the exercised fixture;
  this reader uses the central raw name too. Unknown extra fields must still
  be structurally well formed. ZIP64 extra fields are rejected.
- A complete central record, including its 46-byte header and variable fields,
  may contain at most 65,535 bytes in the tested Java runtime. A one-byte name
  therefore permits a 65,488-byte entry comment; 65,489 fails. This reader
  enforces the observed boundary as `CentralRecordLimit`.

Names remain virtual and case sensitive. No normalization of `..`, leading
slashes, repeated separators, backslashes or Unicode is performed. Null bytes
are preserved in decoded names, as observed with Java. None of these names is
used to construct an output filesystem path. Filesystem extraction semantics
are outside this module.

## Structural and payload validation

The file loader reads only the final `min(file_size, 65577)` bytes and the
declared central directory. The tail includes a maximum classic comment plus
room for a ZIP64 locator. Candidate end records must reach EOF through their
declared comment and have a consistent directory extent, or an explicit ZIP64
marker/sentinel that can be diagnosed. Arbitrary signatures within comments
do not themselves become records. Unclaimed trailing file bytes fail.

The index requires the declared central count to consume the exact central
slice. It validates supported flags/methods/version, byte and list limits,
names/comments, disk references, stored lengths, extra-field lengths, and
classic offsets. Entries are sorted by local offset solely to assign ceilings
at the next local offset or central start, then restored to central order.
Minimum local/header/name/data/descriptor spans must fit those ceilings;
repeated local offsets and overlapping minimum spans fail.

Local validation is lazy and explicit. Indexing does **not** read every local
header. Each requested entry reads a 30-byte prefix, plans a bounded slice, and
then validates the actual local version/flags/method/raw name, extra fields,
CRC/length fields, full span and optional descriptor. Its compressed data and
descriptor cannot cross the assigned ceiling. Descriptor entries permit local
CRC/length fields that are zero or agree with the central values; contradictory
fields fail. Deflate output is bounded by the declared entry size as well as
the configured output cap. CRC and exact decoded size must match before bytes
are returned. Extra gap bytes between physical entries are not treated as
payload or a new path.

This is intentionally stricter than merely obtaining an input stream from
`ZipFile`: local/central inconsistencies, physical overlap, CRC failures and
trailing deflate bytes are rejected. Valid fixtures and the pinned JAR are
compared with Java; universal malformed-input equivalence is not claimed.

## Limits and unsupported features

| Limit | Default | Largest accepted configuration |
|---|---:|---:|
| Archive file bytes | 536,870,912 | 1,073,741,824 |
| Central index bytes | 16,777,216 | 67,108,864 |
| Central entries | 65,534 | 65,534 |
| Name bytes | 4,096 | 16,384 |
| Compressed bytes per entry | 33,554,432 | 67,108,864 |
| Output bytes per entry | 33,554,432 | 67,108,864 |

These bounds fit classic U32 arithmetic without wraparound in accepted spans.
Byte lists reject values above 255. Name decoding also respects the byte bound,
so the reused UTF-8 scalar decoder's 16,384-codepoint cap cannot truncate an
accepted name. Comments have the central-record bound rather than that network
line cap. Parsing loops descend a byte list or explicit finite count/fuel.
Sorting and name indexing are finite but no constant-time cost is claimed.
The pure whole-byte `parse` convenience function retains its input list; file
`load` avoids reading the complete JAR into Bend memory.

Encrypted/masked entries, multidisk archives, ZIP64 sentinels/extra fields/
locators, methods other than 0/8, unsupported flag bits and required versions
above 2.0 return explicit unsupported-feature diagnostics. Central digital
signatures or other nonclassic gaps are unsupported layouts. Absolute offsets
with a prefix are tested; automatic offset correction for malformed or
relative self-extracting ZIPs is not implemented. Base file effects report
files beyond U32 size as an IO error. A short host read fails the exact slice
checks. The caller must keep the opened file stable; no snapshot or concurrent
mutation guarantee is provided.

## Verification

```sh
python3 tools/test_archive.py
```

The runner builds the actual native Bend harness. The recorded run passes 340
native cases and checks 127 valid archives through Java. Independent fixtures include
100 generated archives with permuted central/physical order, stored/fixed/
dynamic deflate, both descriptors, Unicode/CP437 names, duplicates, virtual
names, comments/signatures, input boundaries and corrupt record/payload cases.
The Java oracle opens real files through `ZipFile`; Python constructs fixtures
and checks results, and is never an archive implementation called by the Bend
runtime.

Before integration reads, the runner verifies the installed client JAR's
41,483,720-byte size, SHA-1
`e877b6a07acd633fb3bb475002175cec036e7b87` and SHA-256
`4508d006323f24fa02876310c192d739af56516eb259000ac50f0909a68c9a2d`.
All 34,227 central records are compared with Java and Python. Requested version,
language, image and data-tag bytes are compared exactly with independent
`zipfile` output; hashes and lengths are retained in evidence. A missing query
followed by a successful read verifies continued ownership/use of the handle.

`evidence/archive-tests.json` records exact native counts, oracle observations,
commands, source/dependency/binary hashes, checker and separate kernel verdicts.
Two finite laws check empty EOCD and a known CRC vector; one general law checks
empty-list equality. These laws do not prove complete ZIP parsing, decompression
or Java parity. Both source and harness pass the ordinary checker.
`src/archive.bend --verdict` reports `ALL PROOFS CHECK`. The complete
`tests/archive.bend --verdict` run times out at 120 seconds without a verdict;
it is **not** reported as kernel validated. All three laws separately pass in
isolated generated proof modules, whose exact source and commands are retained
in `evidence/archive-laws.json`. Native success does not substitute for a
kernel verdict or establish broader archive/resource semantics.
