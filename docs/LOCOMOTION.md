# Exact input-vector prerequisites

`src/locomotion.bend` implements the pinned Minecraft Java **26.3** `Mth.sin(double)`, `Mth.cos(double)`, `Vec3.normalize()`, and protected static `Entity.getInputVector(Vec3,float,float)`. The sine table is extracted from the actual private `Mth.SIN` field. Binary64 arithmetic uses the pure exact payload implementation in `src/f64.bend`; the one explicit binary32 yaw multiplication uses Bend's ordinary CPU `F32.mul` primitive. There is no approximate sine function, GPU call, foreign gameplay implementation, or compiler modification.

Confidence is **high for the recorded direct Java numerical observations**. These prerequisites do not establish walking, `LivingEntity.travel`, `Player.aiStep`, a controller, or full player movement. Those remain required work under the full 26.3 goal.

## Owned interface

```bend
import ./locomotion.bend as L
import ./movement.bend as M
import ./f64.bend as F

type Tables is Type:
  Tables{sine: Array<F32>}

L.Tables.load(path) -> IO(Result<&2,&1,L.Error,L.Tables>)
L.Tables.decode(bytes: List<&2,U32>) -> Result<&2,&1,L.Error,L.Tables>
L.normalize(vector: M.Vec3) -> M.Vec3
L.sin(tables: L.Tables, angle: F.F64) -> L.Tables & F32
L.cos(tables: L.Tables, angle: F.F64) -> L.Tables & F32
L.get_input_vector(tables: L.Tables, vector: M.Vec3,
                   acceleration: F32, yaw: F32) -> L.Tables & M.Vec3
```

The caller retains the sole `Tables` owner returned with every lookup and input-vector result. A shared Engine can hold that owner alongside its existing world and registry owners. Movement vectors reuse `M.Vec3`; no F32 coordinate state replaces the authoritative binary64 body. Use the checked loader to establish the pinned table precondition. Bend's public constructor also permits callers to build arbitrary arrays; such values are outside this parity contract.

`generated/reference_mth_sin.f32` is numerical table data, with no header: **65,536 IEEE-754 binary32 raw words in little-endian order, exactly 262,144 bytes**. Its SHA-256 is:

```text
cdfaec6870788e193dff3f1ddfa3ca7d3f1a897042d78365a1fe3a433be3627d
```

The pure Bend decoder checks exact byte count, every in-memory byte in `[0,255]`, and the pinned SHA-256 before creating the `Array<F32>`. Its SHA implementation hashes this fixed-size message, including the 2,097,152-bit length padding; it is not exposed as a general-length cryptographic API. The file loader reads at most 262,145 bytes, closes its File owner, then decodes. Any extra byte rejects the file. Errors are `TableLength{bytes}`, `TableByte{index,value}`, `TableHash{}`, and `TableRead{code,message}`. Length on an oversized file reports the capped read count, not the entire file's size.

## Pinned numerical behavior

For sine, compute binary64 `angle * 10430.378350470453d`, cast that result to Java signed long, mask with `65535L`, then read the float table. Cosine adds binary64 `16384.0d` **before** the cast. The signed-long conversion truncates finite values toward zero, saturates overflow and infinities at the signed endpoints, and maps NaN to zero. Masking the low word therefore maps positive infinity to index 65535 and negative infinity to index 0. Cosine of NaN also reads index 0. This is the actual 26.3 double/long formula; older float/int formulas do not apply.

Normalization computes `sqrt((x*x + y*y) + z*z)` in exactly that binary64 order. If length is strictly less than the widened float `1.0E-5f`, raw double bits `3ee4f8b580000000`, it returns positive-zero `Vec3.ZERO`; otherwise each original coordinate is divided by that length. There is no scaled norm designed to avoid overflow. Thus large finite coordinates can produce infinite length and signed-zero normalized components. NaN lengths take the division branch and propagate NaN.

Input conversion first computes that same squared-length order. A squared length strictly below binary64 `1.0E-7d` returns positive-zero `Vec3.ZERO` without table access or float yaw arithmetic. A squared length strictly greater than `1.0d` selects normalization; otherwise it retains the original vector, including signed zeros. Unordered NaN bypasses both comparisons. The selected vector is scaled by the float acceleration widened to double. Compute yaw radians with binary32 `yaw * 0.017453292f`, raw multiplier bits `3c8efa35`, then widen that result to double for both table lookups. Finally:

```text
x' = scaled.x * widened_cos - scaled.z * widened_sin
y' = scaled.y
z' = scaled.z * widened_cos + scaled.x * widened_sin
```

Each multiply, add, and subtract is a separate binary64 operation, with no fused arithmetic. Requested finite, subnormal, overflow, NaN, infinity, and signed-zero cases are compared using actual raw Java result bits on the pinned runtime. No host Python operation computes an expected gameplay vector.

## Independent verification

```sh
python3 tools/reference_locomotion_probe.py
python3 tools/reference_locomotion_probe.py --verify-existing
python3 tools/reference_locomotion_probe.py --selftest
python3 tools/test_locomotion.py
```

The extractor invokes actual `Mth.sin/cos`, actual `Vec3.normalize`, and the actual reflected `Entity.getInputVector` method. It bootstraps official game registries only to initialize Entity's static dependencies. There is no composed locomotion algorithm in this oracle. Reflection separately copies `Mth.SIN` raw words to the explicit file format. Fixture metadata pins the server bundle, server class jar, installed runtime executable/version, official library hashes, class bytes, and named bytecode method texts. Additional travel/tick methods are inventoried as inspected dependencies, explicitly not runtime validation.

The current corpus contains **21,266 direct Java calls**: 4,166 sine, 4,166 cosine, 4,134 normalization, and 8,800 input-vector observations. It covers index-boundary neighborhoods, Java long saturation, huge finite angles, both infinities, NaN payloads, signed zero, subnormal coordinates, normalization and squared-length thresholds, float yaw rounding, overflowed lengths, exponent gaps, and ordinary inputs. The native suite also compares all 8,332 table indices and performs two complete owner-retaining table traversals: 131,072 entry comparisons. Loader probes reject missing, empty, truncated, extra-byte, oversized, changed-bit, and wrong-endian files. In-memory byte probes distinguish out-of-range bytes from valid bytes with a wrong digest. Three additional 262,144-byte messages compare the Bend SHA computation with independent Python `hashlib.sha256`.

Eight kernel-checked laws establish their specific gate, owner-retention, stationary-vector, and infinity-index statements. They do not prove general Java behavioral equivalence or cryptographic security. Native emission inspection records the sole float yaw multiplication; exact binary64 calculations and indexing remain integer code. Java self-tests repeat all observations and reproduce the table in two independent runs, then reject unsealed/resealed corrupted expected results and a corrupted table digest. Current counts, hashes, kernel/native/build timings, and boundaries are in `evidence/locomotion-verification.json` and `evidence/locomotion-reference*.json`. These are verification workloads, not performance claims about Minecraft.

An additional quantified law for the full stationary `get_input_vector` composition passed Bend's TypeScript checker but failed its independent BendTT translation check in 2.0.35. It was removed rather than accepted as proof or worked around through compiler changes. The accepted owner-retention law covers the actual early-return gate; stationary full-method behavior also has direct Java/native fixtures. The bounded experiment is recorded in `evidence/locomotion-kernel-experiment.json`.

## Next walking and gravity contract

Read-only inspection of actual 26.3 `LivingEntity`, `Avatar`, `Player`, and `Attributes` identifies **ordinary dry-air travel with explicit attributes and state** as the next bounded runtime experiment. Generic `Entity`, even when created with `minecraft:player` EntityType and dimensions, has no LivingEntity travel pipeline and has default gravity `0.0d`. A future oracle must execute actual inherited `LivingEntity.travel` or actual `Player.travel`.

The finite ordinary-air order is:

1. Before movement, sample `getBlockPosBelowThatAffectsMyMovement()` via actual supporting-block-aware `getOnPos(0.500001f)`, prior grounded state, and grounded block friction.
2. Narrow `FRICTION_MODIFIER` to float and compute `clamp_f32(1f - (1f - blockFriction) * modifier, 0f, 1f)`, rounding after every float operation. Airborne friction is `1f`.
3. Grounded widened friction `>0.6d` uses float `speed * (0.21600002f / ((friction*friction)*friction))`; grounded friction `<=0.6d` uses `getSpeed()` directly. Airborne input uses `getFlyingSpeed()`.
4. `moveRelative` adds the verified input vector to binary64 velocity. Apply the actual climbable helper, store velocity, then call `Entity.move(SELF,currentVelocity)`. **Gravity follows displacement and collision.**
5. Read post-move velocity. Climbing/powder-snow jumping can supply a temporary Y=`0.2d`; the ordinary bounded case excludes those branches.
6. Levitation adjusts Y as `y + (0.05d*(amplifier+1)-y)*0.2d`; otherwise the loaded authoritative path subtracts effective gravity. Slow Falling consults the entity's actual post-move velocity Y, not the helper's temporary Y. The ordinary initial case excludes both effects.
7. Unless friction is discarded, narrow `AIR_DRAG_MODIFIER`, compute modified `.91f` drag, multiply sampled friction by that float result for horizontal drag, and use modified `.98f` vertical drag for the ordinary non-omnidirectional entity. Widen those float multipliers before final binary64 component multiplication.

Required attribute/state inputs include `GRAVITY` (default `.08d`, range `[-1d,1d]`), `FRICTION_MODIFIER` and `AIR_DRAG_MODIFIER` (default `1d`, range `[0d,2048d]`), current movement speed, step height, no-gravity state, and discard-friction state. Unit block speed factor and suppressed bounce retain the existing movement boundary; general speed effects additionally need `MOVEMENT_EFFICIENCY`, restitution needs `BOUNCINESS`. Player movement speed defaults to widened `.1f`, not the generic attribute default `.7d`. `Player.getSpeed()` reads the current attribute and narrows it each call; replacing it with LivingEntity's stored speed field can use stale state. Ordinary airborne Player speed is `.02f`, or `.025999999f` while sprinting.

Initial explicit guards should exclude passengers/controllers, liquids, swimming, ability flight, fall flying, climbable/powder snow, Levitation/Slow Falling, unloaded client chunks, non-unit speed-factor blocks, and general bounce. These are boundaries of the next experiment, not removed full-goal requirements. Actual travel first dispatches fluid travel when `isInLiquid && isAffectedByFluids && !canStandOnFluid`, then fall flying, then air; bypassing that dispatcher without observing its guards cannot establish full travel parity.

The input tick wrapper remains separate: `LivingEntity.aiStep` handles interpolation/simulation, tiny-velocity cleanup, float `.98f` X/Z input decay, immobility, jumping/cooldown, and travel gating before block effects. Player-type horizontal cleanup zeros X/Z together below squared magnitude `9.0E-6d`, while other types test X/Z individually below absolute `.003d`; all types test Y below `.003d`. Player `aiStep` calls inherited processing before updating its stored speed field. Player tick also handles spectator/passenger state, fluid state, coordinate clamping, and pose updates. None of those behaviors is silently represented by `get_input_vector`.
