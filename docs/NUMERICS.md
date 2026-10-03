# Pure binary64 numeric substrate

Confidence: **high** for the tested add, subtract, multiply, divide, conversions, bit classification, sign, and numerical comparison behavior. Complete IEEE arithmetic correctness has **not** been mechanically proved. Minecraft collision/movement parity and its arithmetic workload remain **unknown**.

`src/f64.bend` implements binary64 arithmetic in pure typed Bend using U32 integer operations. It contains no foreign arithmetic, `@unsafe`, axioms, or F32 approximation. No compiler, parser, or runtime files were changed.

Java `double` corresponds to IEEE 754 binary64: 53 significand bits and 11 exponent bits, with subnormal values, signed zeros, infinities, and NaNs. Numerical operator comparisons equate signed zeros and treat NaNs as unordered. NaN result payload selection is not mandated by the Java specification; this module chooses the explicit policy below. [Java Language Specification §4.2.3](https://docs.oracle.com/javase/specs/jls/se25/html/jls-4.html#jls-4.2.3)

## Representation and public API

```bend
import ./f64.bend as F

# Exact binary64 payload, high word first.
F.F64{hi: U32, lo: U32}

# 1.0 = 0x3ff0000000000000
one = F.from_bits(1072693248, 0)
```

The high word contains sign bit 31, exponent bits 30–20, and the top 20 fraction bits. The low word contains the remaining 32 fraction bits. `F64` is immutable and Data-kinded, so reusable values require the ordinary Bend `+` annotation. The word order is semantic and independent of machine endianness.

| Function | Result | Contract |
| --- | --- | --- |
| `from_bits(hi: U32, lo: U32)` | `F64` | Stores any exact 64-bit payload. |
| `bits(value: F64)` | `U32 & U32` | Returns high and low words unchanged. |
| `classify(value)` | `F64Class` | Returns `F64Zero`, `F64Subnormal`, `F64Normal`, `F64Infinity`, or `F64NaN`. |
| `sign(value)` | `Bool` | Returns the raw sign bit, including signed zero and NaNs. |
| `neg(value)` | `F64` | Flips only the sign bit. NaN payloads and signaling status remain intact. |
| `abs(value)` | `F64` | Clears only the sign bit. |
| `is_nan(value)`, `is_zero(value)`, `is_finite(value)` | `Bool` | Class predicates; finite includes both zeros and subnormals. |
| `compare(a, b)` | `F64Order` | Returns `F64Less`, `F64Equal`, `F64Greater`, or `F64Unordered`. |
| `is_eq`, `is_ne`, `is_lt`, `is_le`, `is_gt`, `is_ge` | `Bool` | Numerical operator predicates derived from `compare`. |
| `add(a, b)`, `sub(a, b)`, `mul(a, b)`, `div(a, b)` | `F64` | Binary64 operations with round-to-nearest, ties to even, gradual underflow, signed zeros, infinity overflow, and the stated NaN policy. |
| `from_u32(value: U32)` | `F64` | Exact conversion of an unsigned 32-bit integer. |
| `from_i32(value: U32)` | `F64` | Exact conversion of a signed two's-complement 32-bit bit pattern. |
| `from_f32(value: Base.F32)` | `F64` | Exact finite widening; preserves zero/infinity sign and maps NaN payload as described below. |
| `to_f32(value: F64)` | `Base.F32` | Binary32 RN-even narrowing with gradual underflow, signed zero/infinity, and the explicit NaN payload policy below. |
| `trunc_i32(value: F64)`, `floor_i32(value: F64)` | `Result<&2, &2, F64ConversionError, U32>` | Checked integer conversion; `Done` contains signed two's-complement result bits, and `Fail` contains a declared error. |

All arithmetic arguments above are `F64`. Raw word equality is available by comparing `bits` independently of numerical equality. Both `+0` and `-0` compare `F64Equal`; any comparison with a NaN returns `F64Unordered`. In that case `is_ne` is true and the other five comparison predicates are false.

Remainder, square root, transcendentals, decimal parsing/formatting, 64-bit integer conversion, alternate rounding modes, and floating exception flags are unsupported. Callers must retain binary64 bit payloads rather than passing through F32 when constructing a binary64 simulation value; `from_f32` widens the already rounded F32 input exactly.

## Arithmetic semantics

Each finite operation rounds once to the nearest representable binary64 value, breaking exact midpoint ties toward an even least-significant significand bit. Tiny results retain subnormal precision rather than being flushed to zero. Overflow produces infinity with the result sign. Multiplication and division zero, infinity, and underflow-to-zero signs use the XOR of operand signs. A nonzero finite number divided by zero produces signed infinity; zero divided by a nonzero finite number or infinity produces signed zero.

Addition of two negative zeros produces negative zero. Exact opposite-sign cancellation produces positive zero. Subtraction applies the sign reversal to the right arithmetic operand after checking input NaNs, preserving the original right NaN's sign when it is selected.

The deterministic NaN policy is:

1. If the left operand is NaN, return its exact sign and payload with fraction bit 51 set to quiet it.
2. Otherwise, if the right operand is NaN, return its exact sign and payload with that quiet bit set.
3. Invalid arithmetic returns canonical positive quiet NaN `0x7ff8000000000000`: opposite infinities in addition, equal infinities in subtraction, infinity multiplied by zero, infinity divided by infinity, and zero divided by zero.

`neg` and `abs` operate on bits and do not quiet NaNs. The arithmetic NaN payload policy is a module contract; it does not establish the hardware-specific payload behavior of the installed Java VM.

`from_f32` retains an F32 NaN's sign, shifts its complete 23-bit fraction payload left by 29 binary64 fraction bits, and sets the binary64 quiet bit. It does no F32 arithmetic. All finite F32 values, including subnormals, have an exact binary64 result.

`to_f32` rounds directly to binary32 precision. It preserves signed zeros; results below the binary32 normal range retain subnormal precision, and overflow produces signed infinity. Exact halfway values round toward an even least-significant retained bit, including the midpoint between zero and the smallest subnormal. A binary64 NaN retains its sign, keeps the highest 23 fraction payload bits, and sets the F32 quiet bit. Even a payload entirely discarded by narrowing therefore remains a quiet NaN. This payload policy is explicit rather than relying on a hardware-specific NaN encoding. Java finite narrowing also uses nearest rounding. [Java Language Specification §5.1.3](https://docs.oracle.com/javase/specs/jls/se25/html/jls-5.html#jls-5.1.3)

`trunc_i32` rounds toward zero and `floor_i32` rounds toward negative infinity. They validate the resulting integer against `[-2147483648, 2147483647]`. NaN returns `F64NaNConversion`; infinity or an integer outside that range returns `F64OutOfI32Range`. Thus `trunc_i32(-2147483648.9)` succeeds with `0x80000000`, whereas `floor_i32` rejects that input. Both operations accept `2147483647.9` and return `0x7fffffff`. Both signed zeros produce integer zero. This checked API reports errors; Java integer casts instead map NaN to zero and saturate out-of-range values. [Java Language Specification §5.1.3](https://docs.oracle.com/javase/specs/jls/se25/html/jls-5.html#jls-5.1.3)

## Implementation and bounded work

Bend's pinned compiler specializes U32 and F32, with native Nat immediates capped at `2^48-1`. Base exposes no F64 type or F64 arithmetic primitive. A 53-bit significand therefore cannot safely live in one native Nat. This capability assessment comes from `bend base`, `bend2/comp.ts`'s numeric layouts and operation table, and emitted C inspection.

Two-word unsigned helpers handle carries, borrows, comparison, and logical shifts. Addition/subtraction unpack a 53-bit significand into two U32 words, append three guard/round/sticky bits, order magnitudes, and align the smaller operand using constant-time word shifts with a sticky predicate. Addition normalizes a carry. Subtraction normalizes cancellation with at most 53 structurally decreasing Nat steps. Rounding uses retained parity and the three low rounding bits.

Multiplication normalizes subnormal factors with at most 52 structural steps. A 53-step structurally decreasing loop accumulates their exact product into four U32 words, retaining all 106 significant product bits. It then normalizes the product, reduces to a significand with guard/round/sticky bits, adjusts underflow, and uses the shared rounding/packing path. Its shifted exponent representation stays nonnegative through subnormal normalization; unsigned wrap does not stand in for a negative exponent.

Division reuses factor normalization and computes one integer quotient bit plus 55 fractional bits in 56 structurally decreasing steps. Each step compares the two-word remainder to the divisor, conditionally subtracts, and shifts to the next bit. A nonzero final remainder becomes sticky information. The shifted exponent stays nonnegative even for the smallest/largest finite operand ratio; underflow reduction and final rounding use the shared arithmetic path. The bounded remainder fits the two-word representation. No reciprocal approximation or host arithmetic is involved.

Integer inputs use exact two-word normalization. F32 widening reads the raw Base.F32 payload and adjusts the exponent/fraction layout. Checked integer outputs derive the integer magnitude and discarded-fraction predicate from binary64 bits; floor increments a negative fractional magnitude before checking the signed range.

F32 narrowing reduces the unpacked significand to 24 bits plus guard/round/sticky information. The binary32 subnormal path performs the full precision reduction before its single rounding step, avoiding an intermediate rounding. Encoding the retained significand with an exponent offset also handles carry into a new binade, the smallest normal, and infinity. Finite narrowing uses bounded word shifts and no recursion, decimal serialization, or host cast.

`src/f64.bend --verdict` checks type correctness and termination through BendTT. It is not an IEEE 754 arithmetic theorem. IEEE result behavior is established here by independent native fixtures, with the precise testing coverage below.

## Independent native verification

Reproduce the full test and benchmarks:

```sh
python3 tools/test_f64.py
```

`tests/f64.bend` imports and executes the actual Bend module in a native CPU binary. Python generates input payloads and independent expected results; it performs no observed gameplay implementation. The generated C reference is a small test-only program that performs hardware double arithmetic, compiled with `-O3 -fno-fast-math -ffp-contract=off` and explicitly selects nearest rounding. It is never linked into the Bend implementation.

The default seed 640,263 produces 48,112 operand pairs:

| Fixture set | Pairs |
| --- | ---: |
| Cross-product of bit edges, signed zeros, powers/neighbors, subnormal boundaries, maximum finite values, infinities, and NaN payloads | 17,956 |
| Uniform random finite payload pairs | 20,000 |
| Independently generated midpoint neighborhoods using `nextafter` | 5,000 |
| Near-cancellation pairs | 5,000 |
| Division subnormal and halfway boundary cases, with both signs | 140 |
| Division overflow/underflow boundary cases | 16 |

Of those, 45,532 pairs have two finite operands. The native Bend add/subtract/multiply/divide results receive **182,128 exact bit comparisons** against independently generated Python expectations. The C reference provides **182,124 exact comparisons** and four NaN-class checks for zero divided by zero, whose hardware payload is outside this module's policy. An additional **8,156** checks use exact Python Fraction arithmetic followed by rounded conversion: 8,000 arithmetic checks over 2,000 random operand pairs and 156 targeted division boundary checks. All pairs also verify classifications, sign extraction, finite predicates, raw negation/absolute value, ordering, and all six numerical comparison predicates. NaN payload expectations follow the declared module contract.

A separate **26,586 conversion cases** cross unsigned/signed/F32 input edges with signed integer-range edges, random payloads, and dense integer/fraction neighborhoods. They provide **79,758 exact native input-conversion comparisons** and **53,172 checked truncation/floor result comparisons** against Python. The independent C driver also checks both integer input conversions, 26,123 exact F32 widenings, 463 NaN widening classes, and every checked output conversion. Signaling/quiet NaN input payloads are checked separately against the explicit widening policy.

F64-to-F32 narrowing adds **46,349 exact native bit comparisons**, including 19,674 halfway/neighbor cases across every finite F32 exponent, 6,558 exact F32 roundtrips, 20,000 random binary64 payloads, 27 requested movement-height edge neighborhoods, and **74 actual candidate deltas observed by the pinned 26.3 movement probe**. Independently compiled C and the installed Java 25 runtime each provide 46,332 exact non-NaN comparisons and 17 NaN-class checks. Another 20,000 comparisons use exact Fraction arithmetic and a binary search over adjacent F32 values; this nearest-neighbor oracle does not mirror the implementation's significand shifts. Requested height edges cover signed zeros, 0.5, promoted 0.6f, 1e-7, promoted 1e-5f, half the smallest F32 subnormal, and 2^24 neighbors. Observed deltas include adversarial values near 0.5 and promoted 0.6f.

Use `python3 tools/test_f64.py --cast-only --step-samples evidence/movement-cast-samples.json` for targeted narrowing checks including the observed deltas. The optional `--step-samples PATH` accepts a JSON object containing `candidate_delta_f64_bits`, a list of raw 16-digit hexadecimal deltas. The full test checks narrowing along with the existing arithmetic/conversion regressions. The recorded full suite covers 46,275 cast cases; the subsequent targeted suite adds the 74 observed deltas on identical source hashes. Current measured build times are recorded separately in evidence; no build caching behavior was changed.

`evidence/f64-oracle.json` records commands, source/binary/reference hashes, fixture digests, native backend, platform, exact counts, benchmark samples, build timings, Java narrowing oracle/runtime fingerprints, and emitted-C inspection. Earlier baselines are preserved in `evidence/f64-alignment-baseline.json`, `evidence/f64-add-sub-mul-baseline.json`, and `evidence/f64-div-conversion-baseline.json`.

`evidence/f64-cast-targeted.json` records the follow-up narrowing check with the observed movement deltas and their input-file digest. The full and targeted reports have identical hashes for the Bend module, Bend test harness, and Python runner.

These tests establish numeric behavior over the recorded fixtures. They are not Java gameplay fixtures, collision response tests, or a complete proof over all `2^128` operand pairs. GPU and JavaScript execution have not been separately verified.

## Measured arithmetic capability gap

On this Darwin arm64 machine, five repetitions of each one-million-operation serial dependency chain produced these medians. The result bits matched the C reference on every repetition.

| Workload | Pure Bend, ns/operation | C double, ns/operation | Bend/C ratio |
| --- | ---: | ---: | ---: |
| Add 1.0 repeatedly from zero | approximately 9 | 0.654 | 13.8× |
| Add 0.1 repeatedly from 1.0 | approximately 10 | 0.675 | 14.8× |
| Multiply repeatedly by `1.0 + 2^-52` from 1.0 | approximately 60 | 1.020 | 58.8× |
| Divide repeatedly by `1.0 + 2^-52` from 1.0 | approximately 169 | 2.726 | 62.0× |

Bend's `IO.now` has 1 ms resolution; its calls bracket an already evaluated loop via an explicit helper dependency. C uses monotonic nanosecond timing. Process startup and output are separately recorded and excluded from the arithmetic-loop ratio. Times vary with system load, and different operand distributions can change branch and normalization costs. These are arithmetic workload comparisons, not a Minecraft speed comparison or a complete tick-budget measurement.

The direct alignment change reduced the initial add benchmark from approximately 15–17 ns/operation to approximately 9–11 ns/operation while preserving all bit fixtures. Current emitted C is 510,545 bytes / 16,696 lines including the runtime, test harness, effects, and numeric helpers. Its 147 scalar inline helper bodies contain 236 U32 operations and no host floating arithmetic. The compiler lowers the pure numeric implementation to scalar unsigned C; an F32/double fallback is not hiding underneath it.

The measured multiplication/division gap supports considering a future narrow binary64 primitive or explicitly approved bit-payload arithmetic adapter if representative gameplay profiling shows numerical work consuming the tick budget. Such a boundary would need to preserve the exact tested rounding, subnormal, zero, infinity, and NaN policies. No acceleration boundary is implemented or approved here; simulation decisions remain in Bend.
