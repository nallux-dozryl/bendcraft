# Custom motion/look player record

Confidence is **high for the recorded finite fixtures**. All 5,734 cases passed twice against the frozen native Bend harness, with identical response/output SHA256 `587256d46a26061c8b6d320ec321b11cb95fa1bb1ef18275dec2fcecd9622d6c`. All 3,529 rejected cases passed an immediate known-good decode in the same native process. `evidence/player-record-native.json` records the complete comparisons, artifact generation and unchanged production dependency audit; `evidence/player-record-preflight.json` records the independent corpus expectations.

`src/player_record.bend` stores a neutral `PlayerCodec.Snapshot` together with the four raw `PlayerLook.State` degree fields. This is the project's custom bundle format, not vanilla `player.dat`. Java Entity look behavior is independently measured by the look reference; Java does not define this project's enclosing record.

The named NBT root is `bendex:player-record`, a Compound containing exactly three members:

| Canonical order | Name | Physical tag | Content |
|---|---|---|---|
| 1 | `format` | Int | Raw signed integer representation of 1 |
| 2 | `motion` | ByteArray | Canonical `bendex:player` motion NBT, using PlayerCodec's default 4096-byte ceiling |
| 3 | `look` | List, element type Float | Four raw binary32 words: current yaw, current pitch, previous yaw, previous pitch |

The outer limits are 8192 bytes, container depth 2 and 4096 elements per container. The inner motion has its own limits and schema. Field order can differ on input, and the physical NBT reader accepts its documented liberal modified UTF-8 encodings. Encoding always writes the canonical order above and canonical inner motion bytes.

Record validation first validates the motion snapshot, then requires all four degree fields to be finite. It compares the raw current motion view words against `RN_binary32(degree * Float.fromBits(1016003125))`, separately for yaw and pitch. The independent oracle evaluates this product with exact rational numbers and integer round-to-nearest-even, preserving negative zero. A numerical zero with the wrong sign is rejected. Yaw is not wrapped and previous degree fields are not clamped or projected by the record. Current motion pitch remains subject to the motion codec's finite ±binary32-pi/2 admission rule; the look record does not add an independent degree interval policy.

`Record.Record{motion,look}` is the production type. `validate`, `encode` and `decode` return explicit `PlayerError`, `LookError`, `ViewMismatch{axis}`, `SchemaError` or `NbtError` values. Axis 0 is checked before axis 1. The two structural laws in the module preserve an already-known validation error; they do not prove a general serialization roundtrip, Java equivalence or persistence theorem.

The Python runner imports the independent physical NBT tools from `tools/test_nbt.py`, the motion schema/body oracle from `tools/test_player_codec.py` and exact Fraction/binary32 rounding from `tools/test_player_look.py`. It does not read Bend output to construct expectations. The current corpus includes:

- Valid bodies, supports, metadata and three dimensions from the motion fixture corpus, including all 256 flag/support combinations, extreme coordinates, signed-zero box payloads, dimension half-rounding edges and seeded finite raw words.
- Degree zero signs, subnormals, ±180/360/365/720 and largest finite yaw values, current pitch projection boundaries and unrestricted finite previous yaw/pitch. Reordered outer and inner members must decode to exact canonical inner bytes and unchanged raw look words.
- Nonfinite look fields, wrong raw projections, invalid motion bodies/dimensions/types/booleans, exact field sets, root/version errors, wrong look element types and lengths, container-depth failures, trailing bytes, all 610 truncations of the baseline, negative/huge count headers and 8191/8192/8193-byte outer boundaries.
- Four hundred seeded outer byte mutations, each independently classified before native execution. Valid mutations require exact canonical bytes and raw look words; rejected mutations require the independently predicted error class.

The two complete runs each passed 1,073 exact record encodes and 1,132 exact motion/look decodes. Every rejected case was immediately followed by a known-good decode in the same native process. The runner removes each expected output before invocation and requires rejection to leave no output file. These checks demonstrate semantic failure recovery only. The harness's two file writes are not atomic; interrupted writes, save replacement/recovery and atomic motion/look persistence remain root integration work.

Reproduce the independent corpus without any Bend process:

```sh
python3 tools/test_player_record.py --preflight
```

Only after the lead grants a heavy build slot, compile one native harness with a 600-second process-group bound, verify its compiler/transitive-source/emitted-C/artifact generation, then test the immutable executable twice:

```sh
python3 tools/test_player_record.py --build-only
python3 tools/test_player_record.py --skip-build
```

The executable accepts repeated `MODE INPUT LOOK OUTPUT` groups after `--gpu off --threads 1 --`. For `encode`, INPUT is a physical motion NBT file and LOOK is four little-endian raw binary32 words. OUTPUT is the record. For `decode`, INPUT is a record, OUTPUT is canonical physical motion NBT and LOOK receives the four unchanged little-endian degree words. Test fixtures, outputs, build receipts and complete input hash manifests live under ignored `build/player-record`.

`--skip-build` requires the frozen receipt to match the complete current source closure and independently rehashes the actual compiler/runtime/toolchain dependencies and immutable artifact. The motion and look closures must also match their previous verified source receipts. The optional `--kernel` attempts the full imported production source with a 60-second bound and reports its actual result separately; no full-import proof claim is inferred from ordinary checks or native execution.

The measured fresh build took 10.545 seconds. Its native executable SHA256 is `7da5c601300c3849d6c8d180a2466c0d07f10bdbdbf10d0d5d256dfad9fefef4`, and emitted C SHA256 is `3dbdae29e252ae72136d1353697d516e38917f34b066a524ed63fafc1047e20d`. The frozen record source SHA256 is `1812d954991cbce193353490d5db002f26873f364c426f497f82e7b13594235b`; harness SHA256 is `8f92162630f77d88d8ec865a5fff02d7f0cac9be3da3dedee85714799172b0d8`. The receipt captures 12 local Bend sources and 1,638 total compiler/runtime/source/toolchain dependencies, and binds them to the keyed native cache generation and emitted C. Twelve independent receipt mutations covering source omission/digest, cache key, binary/C/compiler/dependency metadata and artifact aliasing are rejected; shared source, cache and artifact files are not mutated.

The actual full imported production `src/player_record.bend --verdict` succeeded with `ALL PROOFS CHECK` in 6.207 seconds, without a source projection. `evidence/player-record-kernel.json` preserves the command, source closure, result and the two narrow structural laws' scope. Reproduce that bounded check with `python3 tools/test_player_record.py --skip-build --kernel` after coordinating its compiler slot. No atomic-persistence or universal-codec theorem is claimed.
