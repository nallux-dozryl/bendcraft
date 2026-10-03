# Neutral player snapshot codec

`src/player_codec.bend` encodes and decodes the complete admitted neutral-player snapshot described here. This is a strict custom versioned physical NBT record, **not** Minecraft's vanilla `player.dat`, a complete player-content format, or evidence of full player persistence/replay parity.

Confidence is high for independently tested physical bytes and admitted-state readback. Source checks and laws have their stated scope; no universal NBT or gameplay correctness theorem is claimed.

## Public interface

```bend
import ./player_codec.bend as P

P.Snapshot{state: PT.State, support: SP.State,
           yaw: F32, pitch: F32, dimension: String}

P.encode(snapshot: P.Snapshot)
  -> Result<&2, &2, P.Error, List<&2, U32>>
P.decode(bytes: List<&2, U32>)
  -> Result<&2, &2, P.Error, P.Snapshot>
P.encode_with(max_bytes: U32, snapshot: P.Snapshot)
  -> Result<&2, &2, P.Error, List<&2, U32>>
P.decode_with(max_bytes: U32, bytes: List<&2, U32>)
  -> Result<&2, &2, P.Error, P.Snapshot>
P.validate(snapshot: P.Snapshot)
  -> Result<&2, &2, P.Error, P.Snapshot>
```

`PT` is the frozen `player_tick.bend` state contract; its SHA256 is `d583f3014011313097779b69ee0fd8d77bd3ed0e1e7895b629903eb64da9699f`. `SP` is `support.bend`, with `State{main: Maybe<&2, T.BlockPos>, on_ground_no_blocks: Bool}`. Position coordinates inside `T.BlockPos` are unsigned U32 representations of signed Java-int words.

All snapshot fields are `Data`. A caller can keep its existing snapshot while attempting encoding or decoding. Failure returns no encoded bytes or partial snapshot, and no simulation owner is transferred. This codec performs no IO and allocates no world, registry, or table owner.

The default byte cap is **4,096**. An explicit cap from zero through **65,536** is supported; larger requests fail with `UnsupportedByteBudget`. The physical NBT decoder first bounds the entire input and verifies every list element is a byte, then parses with a fixed depth cap **3** and maximum **16 elements per compound/list/array**. Array lengths are checked before reading their elements, and nested container depth before descent. Strings remain bounded by physical input bytes and the NBT u16 length; decoded schema names/dimension strings are additionally limited to 64 ASCII units before schema use. The cap applies to already-owned caller bytes; it is not a claim that a caller's earlier network/file allocation is bounded by this module.

## Version 1 physical schema

The root is a named `TAG_Compound`, **`bendex:player`**. Canonical encoding emits fields in the following order. Decoding permits reordered fields while requiring exactly one occurrence of each expected field.

| Root field | Physical type and meaning |
| --- | --- |
| `format` | `TAG_Int`, exactly raw word `1` |
| `dimension` | `TAG_String`, one of the three admitted names below |
| `body` | `TAG_Compound`, exact body fields below |
| `support` | `TAG_Compound`, exact cache fields below |
| `input` | `TAG_List<TAG_Float>`, exactly three elements: xxa, yya, zza |
| `jumping` | `TAG_Byte`, exactly 0 or 1 |
| `jump_delay` | `TAG_Int`, raw signed Java-int word |
| `jump_trigger` | `TAG_Int`, raw signed Java-int word |
| `needs_sync` | `TAG_Byte`, exactly 0 or 1 |
| `stored_speed` | `TAG_Float`, exact F32 bits |
| `head_yaw` | `TAG_Float`, exact stored F32 bits, retaining the PT state field's own units |
| `view_yaw` | `TAG_Float`, exact F32 bits, radians |
| `view_pitch` | `TAG_Float`, exact F32 bits, radians |

The `body` compound's canonical fields are:

| Field | Physical type |
| --- | --- |
| `position` | List of exactly three Doubles: feet-center x, y, z |
| `box` | List of exactly six Doubles: min x/y/z, max x/y/z |
| `velocity` | List of exactly three Doubles: x, y, z |
| `width`, `height` | Float |
| `on_ground`, `horizontal_collision`, `vertical_collision`, `vertical_collision_below` | Boolean Byte 0 or 1 |

The `support` compound contains `main`, a declared `List<Int>` with zero elements for `None` or three raw words for `Some{BlockPos{x,y,z}}`, followed by `on_ground_no_blocks`, a Boolean Byte. An empty list must still declare Int element type 3. No coordinate range or relationship to the body/flag is invented. In particular, a retained `Some` and `on_ground_no_blocks=true` can be a real cached state; all four main/flag combinations are admitted independently.

Float and Double payloads are stored as NBT's raw big-endian words. No decimal conversion, F64-to-F32 narrowing of persisted fields, native floating serializer, or NaN canonicalization occurs. Signed zeros retain their original bits. Both counters accept every U32 word, including negative and minimum signed-int representations. The schema name `head_yaw` does not convert the existing state field into view radians; only the separate view fields have that contract.

The record does not include inventory, equipment, abilities, health, effects, pose, entities, network state, player identity, dimension registry, or other gameplay content. Extending the schema requires an explicit version/admission decision.

## Admission and errors

Encoding and decoding both validate the resulting `Snapshot`:

- `PT.state_error` must succeed, including `M.Body.invalid` and finite input/stored-speed/head-yaw fields.
- The body box must have ordered finite endpoints and numerically equal `M.make_box(position, width, height)`. This is an **additional codec admission rule**, not an established PT invariant theorem. Numeric equality admits different raw signed-zero box endpoints, which are then preserved exactly. Any nonzero mismatch is rejected rather than silently rebuilding the saved box.
- View yaw must be finite. View pitch must be finite and in the existing client `look` admission interval, ±the exact F32 payload `0x3fc90fdb` (`F32(1.5707963268)`) radians. Validation uses exact F32-to-F64 widening and pure F64 comparison. This mirrors the project view policy and is not a claim about every vanilla/mod rotation value.
- Dimension must be `minecraft:overworld`, `minecraft:the_nether`, or `minecraft:the_end`.

Missing, duplicate, or unexpected members reject at every compound. Wrong tag IDs, list lengths or declared element types, Boolean values, root name, version, unsupported dimensions, nonfinite values, invalid dimensions, inconsistent box data, truncation, trailing bytes, malformed physical NBT, excessive input/depth/count, and unsupported byte budgets all return explicit errors. Decode retains the physical NBT module's modified UTF-8 decoding behavior; decoded schema equality prevents alternative spellings from bypassing duplicate checks. The codec does not require every accepted input byte sequence or compound order to be the canonical encoder spelling.

`Error` variants are `NbtError{message}`, `SchemaError{field,message}`, `UnsupportedVersion{bits}`, `UnsupportedDimension`, `UnsupportedByteBudget{max_bytes}`, `InvalidState{cause: PT.Error}`, `InconsistentBody`, and `InvalidView{field}` (0 yaw, 1 pitch).

## Verification

```sh
/Users/chuah/.bend/bin/bend src/player_codec.bend --verdict
/Users/chuah/.bend/bin/bend tests/player_codec.bend --verdict
python3 tools/test_player_codec.py
```

The independent Python oracle constructs physical NBT and reads expected results without the Bend codec. It preserves raw numeric words and compound order; Java object-model normalization is not substituted for this custom wire format. The native harness executes the actual Bend encoder/decoder, reads and writes physical bytes, and carries raw words through a separate little-endian fixture protocol. It does not implement player serialization in the host.

All **3,225 cases pass**: **920 exact canonical encodes**, **997 exact snapshot decodes**, and **1,308 rejections without output files**. The corpus exercises all flag/support combinations, fresh finite random snapshots, signed-zero variants, signed counters/support coordinates, F32 subnormal width-halving boundaries, exact bytes and readback, reordered fields, every truncation offset of the 532-byte canonical record, schema/type/length/Boolean/version/dimension errors, nonfinite/inconsistent states, byte/depth/array bombs, and independently classified mutations. Every rejection is followed by a known-good decode in the same native process: all **1,308 recovery followups** succeed, checking continued operation without publishing a failure payload. Python's integer F32-halving oracle is checked against hardware rounding, and tested F64 box additions/subtractions against exact rational conversion.

Both the complete production source and the full native harness pass the ordinary checker and independent `--verdict` kernel, with unchanged import fingerprints during each check. The seven checked laws cover raw signed-counter words, Double vector payload words, signed support coordinates, declared empty-support type, retained Data on encoder rejection, wrong-version rejection, and a malformed support list. A complete concrete schema equality was not retained as a proof: normalization stops at the Base `F32.bits` primitive, so the native exact-byte/readback corpus establishes those fixtures instead. No production validation is weakened to manufacture a proof.

Native evidence is in `evidence/player-codec-native.json`. Source and independent-kernel command evidence is recorded separately in `evidence/player-codec-kernel.json`; neither artifact establishes full player persistence or replay behavior.
