# Pure Bend SHA-256

Confidence: **high for the recorded independent native fixtures**. `src/hash.bend` implements the byte-oriented SHA-256 algorithm specified by [NIST FIPS 180-4](https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.180-4.pdf), sections 4.1.2, 4.2.2, 5.1.1, 5.2.1, 5.3.3, and 6.2.2. Digest execution uses only Base integer, list, string, and affine array operations. No host hash library, foreign implementation, unsafe declaration, axiom, or compiler change is involved.

## Public API

```bend
import ./hash.bend as Hash

Hash.digest(max_bytes: Nat, bytes: List<&2,U32>)
  -> Result<&2,&2,String,Hash.Digest>

Hash.Digest.bytes(digest: Hash.Digest) -> List<&2,U32>
Hash.Digest.hex(digest: Hash.Digest) -> String
Hash.Digest.words(digest: Hash.Digest) -> List<&2,U32>
```

`Digest` is immutable Data containing eight U32 words, named `a` through `h` in output order. `Digest.bytes` returns exactly 32 bytes in big-endian word order. `Digest.hex` returns exactly 64 lowercase hexadecimal characters, retaining leading zeros. `Digest.words` returns the eight words. Reusing a digest or immutable input byte list requires the ordinary Bend `+` annotation; the implementation never duplicates its mutable schedule.

Empty input succeeds with a zero budget. Exactly `max_bytes` valid input bytes are accepted; the next input position fails with `"byte limit exceeded"`. Every consumed U32 must be at most 255; otherwise the result is `Fail{"input byte exceeds 255"}`. Budget exhaustion takes precedence at that position, while an invalid earlier byte fails before later positions are processed. Failure returns no partial digest.

`max_bytes` must be within the native Nat range, **0 through 281,474,976,710,655 (`2^48-1`)**, inclusive. The public API checks that range and returns `"limit exceeds native Nat capacity"` for an oversized mathematical Nat. The test transport also uses Base's checked `Nat.read`, which rejects values beyond that native range. Limits count down, so processing never increments a Nat length past the native ceiling. The bit-length accumulator uses two U32 words with explicit carry, rather than multiplying a maximum native Nat by eight. The largest accepted message has at most `2^51-8` bits, comfortably inside SHA-256's length-field range.

This is a one-shot byte API. Caller text must first be converted with the strict ordinary UTF-8 module in [UNICODE.md](UNICODE.md), or another explicitly specified encoding. The hash function adds no text normalization, BOM, terminator, or newline. Registry identity and save checksum coverage are caller-level contracts; merely making SHA-256 available does not establish those integrations.

`State`, `Compression`, and scalar/array helpers are implementation details. A caller should use `digest` and the Digest formatting APIs. Forging internal state, indices, schedule shapes, or padding positions does not satisfy their invariants.

## Implementation and ownership

The implementation assembles each block's first sixteen words directly from input bytes. It extends a single owned 64-element `Array<U32>` for the remaining schedule words, executes 64 rounds, adds the working registers into the chaining words, and reuses that array for the next block. Schedule writes during input assembly use indices 0–15; expansion reads and writes indices 0–63; round reads use indices 0–63. Those bounds follow the fixed block size, 48 structurally decreasing expansion steps starting at 16, and the 64 fixed round constants. Array masking is not used to accept unchecked public indices.

Padding appends `0x80`, the zero bytes required to reach byte 56 of the final block, and the original message's 64-bit bit length in big-endian order. Messages ending at positions 56–63 need a second padding block. The original length is retained before padding bytes are appended. This path also handles an empty message and a message ending exactly on a block boundary.

All compression arithmetic uses U32 modular addition and logical word operations. Rotation reduces its shift modulo 32. Initial words and all 64 constants are the standard values. The array owner travels through each read and write and is released after the final digest is extracted. Input lists are processed structurally without constructing a second padded copy of the entire message.

The capacity check divides the Nat budget by 65,536 three times and tests whether the result is zero. This expresses `limit < 2^48` without constructing an out-of-range native Nat or forcing a huge computed Nat into unary form during proof reduction. An initial proof using the computed maximum directly exposed a checker stack-overflow during normalization; the revised check and its implementation law pass both checkers.

## Verification

Reproduce all checks:

```sh
python3 tools/test_hash.py
```

The script checks the implementation and test module with `--check-only` and `--verdict`, emits C, builds the native executable, and executes with `--gpu off`. Python serializes test inputs and checks outputs; production hashing runs in Bend. The test-only file reader uses Base byte IO and is bounded to 4 MiB; the public digest API has the larger caller-selected budget above.

Independent expected results use three paths: `hashlib.sha256`, OpenSSL's command-line binary digest output, and CPython's separate `_sha2` implementation. The first two use the same OpenSSL release on this machine, so they are not treated as two independent algorithms. `_sha2` supplies the separate implementation path. The two published one-block and two-block [NIST examples](https://csrc.nist.gov/CSRC/media/Projects/Cryptographic-Standards-and-Guidelines/documents/examples/SHA256.pdf) additionally supply fixed authoritative expected digests.

Fixtures cover every possible single byte, all lengths 0–256 with four byte distributions, exact padding/block transitions, seeded random messages, the native maximum budget on a small message, invalid U32 bytes at early and late positions, exhausted-budget priority, big-endian length-field carry boundaries up to the native maximum, and rotations including shifts beyond 32. Large fixtures include one million `a`, zero, and `0xff` bytes, a 4 MiB byte pattern, a random multi-megabyte input, and the actual loaded block-inventory TSV bytes. Every successful digest verifies both its hex representation and its 32 output bytes. Evidence records exact counts, commands, hashes, oracle versions, emitted-C review, and current verification status in `evidence/hash-verification.json`.

Eight implementation laws establish zero-budget rejection, rejection at the capacity gate, invalid-first-byte rejection with a positive budget, one explicit big-endian word encoding, a rotation wrap boundary, both critical padding boundaries, and a low-word length carry. They prove these stated implementation properties through the actual definitions. They do not prove SHA-256 collision resistance, universal algorithm correctness, or cryptographic security. This implementation has not undergone NIST module validation. GPU and JavaScript execution are not claimed.
