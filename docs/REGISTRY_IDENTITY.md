# Strict registry bytes and canonical identity

`src/registry.bend` loads registry files as raw bytes, decodes ordinary strict
UTF-8 in Bend, validates the TSV/JSON metadata, and computes a canonical SHA-256
identity from that metadata. Confidence is **high for the recorded native
fixtures**. This is inventory identity; it implements no block behavior, mod
lifecycle, save format, or registry installation policy.

## Public interface

```bend
import ./registry.bend as R

R.Registry.load(path: String)
  -> IO(Result<&2,&1,R.Error,R.Registry>)

R.Registry.identity(registry: R.Registry)
  -> R.Registry & Result<&2,&2,String,String>
```

`identity` returns the unique registry owner on success and failure. Its success
String contains exactly 64 lowercase hexadecimal SHA-256 characters. Its failure
String is a diagnostic, with no partial identity. Repeated identity calls and
intervening lookups retain the same metadata and produce the same digest.

The metadata must originate from `Registry.parse` or `Registry.load`, which
validate contiguous protocol/state intervals, defaults, names, property names,
unique domain values, cardinalities, and derived strides. The identity path also
checks array capacity before reads, at most 4096 loaded blocks, at most 64
properties per block, domain cardinalities between 1 and 256 and exact agreement
with their lists, strict UTF-8 serialization, and its byte budget. Manually
forged registry constructors do not establish the parser's metadata invariants.
The derived name lookup map is deliberately outside the serialized metadata;
equal identities do not establish equal lookup behavior for a manually corrupted
map.

## File boundary

The reader opens the file with Base File IO, reads at most **4,194,304 bytes**, and
reads one additional byte to require EOF. Every opened file is closed before
returning a read failure, a capacity failure, or a decoded String. A file exactly
at the byte limit is accepted by this boundary. A larger file fails with
`SchemaError{0,"file exceeds 4194304 bytes"}` before decoding or parsing.

The bounded bytes are passed to `Unicode.decode(4194304n, bytes)`. No host String
decoder participates. Overlong forms, encoded surrogates, invalid leading or
continuation bytes, out-of-range scalars, and incomplete final sequences produce
`SchemaError{0,"UTF-8: " ++ decoder_message}` before TSV/JSON parsing. Native file
failures retain `ReadError{code,message}`. The decoder preserves valid NUL,
noncharacters, BOM, and line endings; subsequent schema rules decide whether a
given character is legal metadata. CRLF and a final missing newline retain their
existing accepted TSV semantics.

## Canonical binary format, version 1

The hash input starts with these **21 fixed bytes**:

```text
ASCII "BendRegistryIdentity" followed by byte 00
42656e6452656769737472794964656e7469747900
```

All integers are unsigned 32-bit, exactly four bytes, big-endian. A String is
encoded as an unsigned 32-bit **UTF-8 byte length**, followed by those exact bytes.
There is no terminator, Unicode normalization, BOM, escaping, or padding within a
String field. Only the SHA-256 algorithm itself adds its standard final padding.

The remaining input is this grammar, with no extra bytes:

```text
u32 version = 1
u32 block_count
u32 state_count
repeat block_count, in parsed block/protocol order:
  u32 protocol_id
  string resource_identifier
  u32 first_state_id
  u32 state_count
  u32 default_state_id
  u32 property_count
  repeat property_count, in parsed property order:
    string property_name
    u32 domain_count
    u32 stride
    repeat domain_count, in parsed domain order:
      string domain_value
```

`domain_count` is the validated Property `count`; serialization requires exactly
that many domain values. Loaded blocks `[0,block_count)` are included. Unused
array cells, allocation identities, the names map, and original TSV/JSON source
text are excluded. LF/CRLF, final-newline presence, accepted JSON whitespace,
equivalent JSON escapes, and either accepted property-object member order share
the same identity. Block, property, and domain sequence order remain significant.
Length prefixes distinguish `['ab','c']` from `['a','bc']` and preserve embedded
NUL/control characters. Composed and decomposed Unicode remain distinct.

The pinned 26.3 registry's canonical input is **167,974 bytes**, with identity:

```text
4f75fa335a12e34cf74be71ff6a0ee530b13233212423f5463bb26a2fe4f3cfc
```

This is a digest of validated metadata, not the raw TSV byte hash. Future format
changes must use a new version and document their interpretation. Save/checksum
callers must pin the format version and define which registry they require.

## Bounds and ownership

Canonical assembly uses a reversed byte accumulator with a **67,108,864-byte
(64 MiB) budget**, then reverses once and invokes the pure Bend SHA-256 module.
It adds no native Nat lengths; budget consumption uses predecessors. Metadata
strings pass a 4096-byte strict encoder limit before their byte lengths are
narrowed to U32. Parser-produced resource/property/domain strings fit this bound.
Property counts use a bounded traversal. Domain emission counts down its checked
cardinality. Block reads use a structurally decreasing fuel count bounded by both
the actual array capacity and 4096, so Base Array's index masking cannot silently
accept a public count overflow.

For parser-produced metadata, let `B` be block count, `P` property count, `V`
domain-value count, `T` retained string scalar count, and `M` retained UTF-8 bytes.
The exact format length is `33 + 24B + 12P + 4V + M`. JSON unescaping does not
increase retained scalar count, so `T` is at most the parser's 4,194,304-scalar
source limit; nonempty domain values imply `V <= T`, and `M <= 4T`. With
`B <= 4096` and `P <= 64B`, a conservative bound is **36,798,497 bytes**, below
64 MiB. Strict file loading gives a tighter bound of **24,215,585 bytes**, since
retained UTF-8 bytes cannot exceed the 4 MiB file. These are implementation size
arguments, not formal kernel theorems.

The original registry array and names map travel through the traversal. Neither
is cloned or stored in a generic map containing arrays. Failure releases the
partial canonical accumulator and returns the registry owner.

## Verification and scope

Reproduce the complete registry checks from the Minecraft project root:

```sh
python3 tools/test_registry.py
```

The test independently derives every block's ordered domains/strides and every
state's properties from the pinned official reports. It reruns the complete
1286-block/35723-state forward/reverse resolver corpus. The canonical oracle
serializes metadata independently in Python using the binary grammar above,
then uses hashlib as the expected digest. Python does not implement runtime
registry loading, parsing, serialization, or hashing.

Targeted native file checks reject 13 malformed UTF-8 payloads before parsing,
retain existing schema/capacity rejections, accept CRLF and EOF without a final
newline, and accept a valid exactly-4-MiB/4096-block inventory. Identity fixtures
cover layout/escape equivalence, ordered metadata changes, control/NUL values,
Unicode normalization distinctions, 255/256 byte-length boundaries, supplementary
scalars, dense domains, repeated calls, and lookups after success/failure. Forged
surrogate and out-of-range characters force actual encoder failures; the harness
restores metadata through the returned owner and checks the identity and lookups
again.

Three added implementation laws state identity-finish failure ownership,
zero-budget canonical rejection, and strict overlong-NUL file-decoder rejection.
Their production metadata types, bounded byte-reader definitions, and canonical
identity definitions are extracted **verbatim** into an isolated verification
projection. That projection passes the independent kernel, including all three
new laws and typing/termination of the actual identity/reader functions. The
projection excludes unrelated JSON parsing/resolution definitions. It establishes
no full registry-module verdict: the direct kernel rejects the imported
`json.encode_go` definition with `affine live code, calls that descend`; the
complete native test module's verdict is bounded to 120 seconds and records a
timeout if it cannot finish. These limitations are retained explicitly.

Checker and independent-kernel outcomes, exact commands, source/slice hashes,
fixture identities, and native C provenance are recorded in
`evidence/registry-verification.json` and `evidence/registry-identity-kernel.json`.
Passing native tests do not turn failed or incomplete aggregate verdicts into
proofs.
No universal serialization correctness or cryptographic security theorem is
claimed, and SHA-256 digests do not establish mathematical injectivity.
