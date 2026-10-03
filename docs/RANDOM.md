# Pinned Minecraft 26.3 random sources

Confidence: **high** for the tested supported sequences and exact state advancement. Complete RNG arithmetic equivalence has not been mechanically proved. World generation parity remains **unknown**.

`src/random.bend` implements the pinned official `LegacyRandomSource` and `XoroshiroRandomSource` arithmetic in pure typed Bend. Seeds, long outputs, and state words are pairs of U32 bit patterns. Floating outputs are assembled as exact F32/F64 bits, without a host RNG or floating approximation. No compiler/runtime files, foreign effects, unsafe arithmetic, or axioms are involved.

The authority is the locally verified official 26.3 server artifact, SHA-256 `a362163eec5d1612d520772bc16e5b39c09e3b234fdc045f56bf544284ee8ae6`. `tools/reference_random_probe.py` inspects its named classes with `javap`, records class-byte and bytecode-text hashes, and calls the actual Java methods. Python chooses test inputs and compares observations; it does not implement the RNG oracle.

## Public interface

```bend
import ./random.bend as R

def example() -> R.Source & Result<&2, &2, R.RandomError, U32>:
  # Signed -1, expressed as its exact two's-complement payload.
  seed = R.Bits64{4294967295, 4294967295}
  # Results return the advanced source explicitly.
  R.next_bounded(64n, R.seeded_legacy(seed), 100)
```

`Bits64{hi: U32, lo: U32}` stores the high word first, independently of machine byte order. A Java signed long or int is represented by its two's-complement bit pattern, not by a negative Bend numeric literal. `Source` and `Positional` are immutable Data values: callers can deliberately retain snapshots using `+`, and determinism means reusing a snapshot repeats its sequence.

| Type/function | Contract |
| --- | --- |
| `Source` | `Legacy{seed: Bits64}` or `Xoroshiro{low: Bits64, high: Bits64}`. Xoroshiro's `low` and `high` are the two complete 64-bit state words, not the halves of one word. |
| `Positional` | `LegacyPositional{seed: Bits64}` or `XoroshiroPositional{low: Bits64, high: Bits64}`. |
| `seeded_legacy(seed: Bits64)` | Constructs the 48-bit LCG state using Java's seed scrambling. |
| `seeded_xoroshiro(seed: Bits64)` | Upgrades a 64-bit seed to two mixed state words using `RandomSupport`. |
| `raw_xoroshiro(low, high)` | Constructs from two exact state words; the all-zero pair receives Java's fallback constants. |
| `reseed(source, seed)` | Recreates the same source kind from the supplied 64-bit seed. Gaussian state is outside the supported interface. |
| `next_int(source)` | Returns `Source & U32`; U32 contains the raw signed Java `nextInt()` bits. |
| `next_long(source)` | Returns `Source & Bits64`; preserves the raw signed Java result. |
| `next_boolean(source)` | Returns `Source & Bool`. |
| `next_float(source)` | Returns `Source & Base.F32`; exact Java result bits, in `[0,1)`. |
| `next_double(source)` | Returns `Source & F.F64`; exact Java result bits, in `[0,1)`. |
| `next_bounded(fuel: Nat, source, bound: U32)` | Returns `Source & Result<&2,&2,RandomError,U32>`; checked Java `nextInt(bound)` behavior with the explicit rejection-fuel contract below. |
| `consume_count(source, count: U32)` | Advances the Java primitive count. Count is interpreted as a signed Java int; negative counts and zero leave the source unchanged. |
| `fork(source)` | Returns advanced parent `Source & Source` child, using the exact source-specific fork rule. |
| `fork_positional(source)` | Returns advanced parent `Source & Positional`. |
| `at(factory, x: U32, y: U32, z: U32)` | Creates a source at signed Java int coordinates, supplied as raw bits. The factory is unchanged. |
| `from_seed(factory, seed: Bits64)` | Creates the source using the factory's actual source-specific rule. |
| `from_hash_of(factory, text: String)` | Returns `Result<&2,&2,RandomError,Source>`. Legacy uses exact Java UTF-16 `String.hashCode`; Xoroshiro returns `UnsupportedHash` because MD5 is not implemented. |

The other word and normalization helpers are implementation details. In particular, the internal shift/rotate helpers are used with fixed counts between 1 and 31; they are not general-purpose 64-bit shift APIs. Direct `Source` constructors expose raw state for inspection, but callers should use the seed/raw constructors to enforce the official constructor invariants.

## Seed, output, and fork rules

Legacy scrambles the input as `(seed XOR 0x5deece66d) AND (2^48-1)`. Each primitive step updates that state with `(state * 25214903917 + 11) AND (2^48-1)` and selects the requested high bits. Unbounded int, boolean, and float consume one step; long and double consume two. Long combines the first signed int shifted left 32 with the **sign-extended** second int. Thus a negative second int decrements the result's high word; simple concatenation would be wrong. Double combines 26 and 27 output bits and scales by `2^-53`; float scales 24 bits by `2^-24`.

Xoroshiro seeding first computes `low = seed XOR 0x6a09e667f3bcc909`, then `high = low + 0x9e3779b97f4a7c15`. Each word receives Stafford13 mixing: unsigned shifts by 30, 27, and 31, with multipliers `0xbf58476d1ce4e5b9` and `0x94d049bb133111eb`. The raw all-zero constructor pair becomes `(0x9e3779b97f4a7c15, 0x6a09e667f3bcc909)`.

For state `(s0,s1)`, Xoroshiro128++ returns `rotateLeft(s0+s1,17)+s0`. After `t=s1 XOR s0`, the next state is `(rotateLeft(s0,49) XOR t XOR (t<<21), rotateLeft(t,28))`. All word arithmetic wraps at 64 bits. Int takes the output's low 32 bits, boolean takes bit zero, float takes the high 24 bits, and double takes the high 53 bits. Each consumes one primitive step. Exact 32×32 products use 16-bit limbs; no 53/64-bit quantity is squeezed into Bend's native 48-bit Nat immediate.

Legacy source and positional forks consume one `nextLong`; a source child is seeded from that result and a positional factory stores it. Xoroshiro forks consume two `nextLong` outputs as its child/factory raw state words. Subsequent use of a positional factory does not advance its parent.

Coordinate factories use the exact `Mth.getSeed` expression. The X multiplication by 3,129,871 wraps as a **32-bit signed int before sign extension**. Z is sign-extended first and multiplied by 116,129,781 at 64 bits; Y is sign-extended. Their XOR is squared, multiplied by 42,317,861, added to eleven times itself, and arithmetically shifted right by 16. Legacy XORs this position seed with its factory seed and scrambles it as a new Legacy source. Xoroshiro XORs it with only the factory's low state word and retains the high word.

Legacy `from_seed` ignores the positional factory seed and constructs a newly seeded Legacy source. Xoroshiro `from_seed` XORs the input seed into both factory state words. Legacy text hashing uses UTF-16 units, including two surrogate units for a supplementary character. Xoroshiro's actual text path hashes UTF-8 using MD5, reads two big-endian 64-bit digest words, and XORs them with its factory words; that hashing operation is explicitly unsupported here.

## Bounded rejection and errors

Bounds are signed Java int bit patterns. Only `1..2147483647` are valid. Zero and any U32 with its sign bit set return `Fail{InvalidBound{}}` without advancing the source. Success returns `Done{value}` in `[0,bound)`.

Legacy uses its power-of-two shortcut, multiplying a 31-bit draw by the bound and taking the high scaled result. Other bounds use modulo and repeat while `bits - value + bound - 1` is negative after signed 32-bit overflow. Xoroshiro multiplies an unsigned 32-bit draw by the bound, uses the high 32 bits as the candidate, and rejects a low product below the threshold `unsigned(-bound) % bound` when the low product is below the bound. The implementations preserve their different output distributions and draw advancement.

Java rejection loops have no explicit attempt budget. Pure Bend requires structural termination, so `next_bounded` takes a real Nat fuel argument. Each candidate consumes one unit; a candidate accepted on the final available draw succeeds. Zero fuel, or exhaustion after rejected candidates, returns `Fail{RejectionFuelExhausted{}}` and the exact original source. This error/rollback is an explicit Bend extension. It is not a claim that Java itself exhausts fuel or rolls back a successful call. Increasing fuel and retrying from the returned snapshot preserves the Java sequence whenever the call succeeds.

`UnsupportedHash` reports the unavailable Xoroshiro MD5 text path. No Gaussian approximation, fallback random algorithm, or hidden native acceleration is substituted.

## Verification and reproducibility

```sh
# Regenerate observations by executing the pinned official Java methods,
# then kernel-check, compile, and compare the actual native Bend binary.
python3 tools/test_random.py --refresh-reference --random 1000

# Recheck the saved fixture digest, pinned runtime/artifacts, and native results.
python3 tools/test_random.py
```

The deterministic input-selection seed is 26,364,048. The recorded suite has **1,596 cases**, including **1,000 random mixed sequences**, and checks **38,714 output-and-state observations** over **37,118 operations**. It contains negative/extreme seeds, reseeding, raw zero-state protection, float/double zero and maximum fractions, signed long assembly, negative/extreme coordinates, UTF-16 strings, nested source/positional forks, and signed consume counts.

| Operation | Native observations after the operation |
| --- | ---: |
| Unbounded int / long / boolean | 3,546 / 3,283 / 2,906 |
| Float / double | 2,943 / 3,404 |
| Bounded int | 8,381 |
| Consume / reseed | 2,598 / 2,490 |
| Source fork | 2,498 |
| Positional coordinate / seed fork | 2,560 / 2,461 |
| Text fork | 48 |

The suite includes 1,459 invalid-bound failures and 1,162 fuel exhaustion rollbacks. Actual Java rejection paths consume between one and thirteen primitive draws in these fixtures. The Java probe invokes the official bounded method, captures its result/final state, and determines advancement by stepping a separately reconstructed official Java source until its state matches. No Python implementation computes the expected RNG outputs. Original Java bounded observations are retained even when the checked Bend policy rejects for insufficient fuel.

There are **37,528 direct Java output/state or mapped Java-error comparisons**, plus **1,186 explicit Bend-extension rollback comparisons**: 1,162 fuel errors and 24 unsupported Xoroshiro text hashes. The latter hash cases retain the actual Java child state separately for future implementation; they establish the unsupported contract, not hash parity.

The BendTT verdict is `ALL PROOFS CHECK`. Seven laws apply to the actual implementation: invalid guard rollback, zero-fuel rollback, arbitrary failed-draw commit rollback, public zero-bound rollback, zero consumption identity, successor consumption advancement, and inductively proved composition of consumption. These laws do not prove multiplication, Stafford mixing, RNG equivalence, distribution quality, or every possible sequence.

`reference/random.json` contains the input protocols, observed outputs/state, Java bounded-call details, official class hashes, Java runtime fingerprint, and reference probe commands. `evidence/random-reference.json` summarizes the Java extraction. `evidence/random-oracle.json` records native comparison counts, error/rejection counts, source and binary hashes, kernel scope, and emitted-C fingerprint. The recorded native CPU run uses `--gpu off --threads 1`; GPU and JavaScript execution have not been separately tested. This is numeric source parity evidence, not world-generation or full-game behavioral parity.

Unsupported capabilities remain Gaussian sampling/cached Gaussian state, Xoroshiro MD5 string hashing, nondeterministic unique/thread-local seeding, concurrent wrappers/threading-detector exceptions, and the additional range/triangle convenience methods. The supported sources do not silently switch algorithm when one of those capabilities is needed.
