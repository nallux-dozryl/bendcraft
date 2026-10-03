# Direct decimal to binary32 parsing

Confidence: **high** for the recorded native fixtures. `src/float_parse.bend` implements bounded, pure Bend conversion directly from an exact JSON decimal token to an RN-even binary32 value. It imports only Base and the pure `src/big_uint.bend` helper. There is no host float parser, foreign/unsafe dependency, axiom, F64 intermediate, or runtime/compiler modification.

```bend
import ./float_parse.bend as P

P.parse_f32(text: String) -> Result<&2, &2, String, F32>
```

The accepted grammar is exactly:

```text
-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?
```

The entire string must be one token. Empty strings, surrounding whitespace, leading `+`, leading integer zeros, `.5`, `5.`, numeric suffixes, underscores, hexadecimal, Unicode digits, and textual `NaN`/`Infinity` are rejected. This is the number grammar of [RFC 8259 §6](https://www.rfc-editor.org/rfc/rfc8259#section-6). Java `Float.parseFloat` also accepts a broader textual grammar, including whitespace, hexadecimal, and special names; this module **does not expose or claim `parse_java_f32` compatibility**. Gson string coercion needs that separate grammar or an explicit caller decision. The exact rounding behavior for tokens accepted here follows [Java 25 `Float.valueOf(String)`](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/lang/Float.html#valueOf(java.lang.String)).

There are two fixed public budgets: **4,096 Unicode codepoints** in the input and **1,024 mantissa digits**, counting integer and fractional digits including zeros. The input bound is checked first. Parsing returns `Fail{"InputLimit"}`, `Fail{"DigitLimit"}`, or `Fail{"InvalidDecimal"}`. Exponent digits count toward the input limit and are all grammar-checked. Their accumulated magnitude saturates at 100,000, which safely decides overflow/underflow after accounting for at most 1,024 mantissa digits. Syntactically invalid trailing data still fails even after the exponent saturates. No successful partial parse is returned. `RoundingBudget` is a defensive internal error if the fixed 31-comparison search fails to converge; no tested valid input reaches it.

Signed zeros survive both zero coefficients and underflow. Overflow returns signed infinity successfully. Decimal syntax cannot produce NaN. Model field range checks and handling of infinity belong to the caller: the pinned production model probe accepts `1e40` as UV positive infinity, while element endpoints apply a separate `[-16,32]` check after conversion. Numeric conversion alone establishes neither that field policy nor complete model parity.

## Exact integer algorithm and bounds

The parser accumulates the decimal coefficient in canonical, little-endian base-65,536 limbs. For the exact decimal value `N × 10^p`, it constructs a numerator and denominator. Coarse decimal-exponent bounds immediately return infinity for adjusted exponents at least 39 and zero for adjusted exponents at most -47; the remaining cases retain the entire coefficient with no digit truncation.

The converter searches over ordered positive F32 payloads from zero through infinity. At each step it compares the rational value to the exact midpoint between adjacent F32 values. The midpoint is an integer of at most 25 bits times a power of two. A comparison therefore needs only exact limb multiplication, shifting, and comparison. Equality selects the even payload. Maximum finite uses the exact overflow threshold against the virtual next finite value `2^128`; zero uses half the minimum subnormal. Sign is attached only after rounding. At most 31 midpoint comparisons cover the entire positive payload range.

With at most 1,024 mantissa digits, the coefficient needs at most 3,402 bits. Cases that need rational rounding have decimal denominator exponent at most 1,069, requiring at most 3,552 bits. A midpoint comparison adds at most 25 significand bits and 103 positive shift bits; a conservative bound for every intermediate is **3,680 bits**, below the documented 4,096-bit envelope. Limb lists allocate only the limbs used; there is no array-index wrapping. These bounds apply to `parse_f32` inputs, not forged internal `Decimal`/`BigUInt` values.

Each limb multiply splits its factor into low/high 16-bit parts. The largest low product plus low carry is `65,535² + 65,535 = 4,294,901,760`, below `2^32`; the high carry fits 25 bits. Generic large integers never inhabit native `Nat`. `Nat` holds only small structural fuel, lengths, and bounded shift/power counts, avoiding its native 48-bit payload limit.

## Independent validation

Reproduce:

```sh
python3 tools/test_float_parse.py
```

The native CPU harness imports and runs the actual parser. Java 25 `Float.parseFloat` and an independently compiled C `strtof` driver observe each valid token separately. The C driver selects the C numeric locale and nearest rounding; it accepts underflow/overflow results rather than mistaking `ERANGE` for malformed syntax. Neither oracle is linked into the implementation.

The default seed produces **20,323 valid token fixtures**, each checked bit for bit against Java, C, and an arbitrary-integer rational oracle. Coverage includes:

- 7,656 exact midpoint/below/above cases spanning every finite F32 exponent and the zero, subnormal/normal, and maximum-finite boundaries.
- 2,552 exact F32 value roundtrips and 10,000 independently generated decimal tokens.
- 64 mantissas of 511, 512, 1,023, and 1,024 digits, plus huge exponent and exact input/digit budget boundaries.
- 16 concrete decimal-to-F64-to-F32 double-rounding traps with tails down to `10^-1000`.
- Seven scalar lexemes from the actual pinned model probe (`raw_json_94`/`raw_json_95`): `0.1`, `-0.0`, `0.10000000149011612`, `1e-45`, the exact halfway value `1.000000059604644775390625`, its upper neighbor `1.0000000596046449`, and `1e40`.

The Python rounding oracle derives the binary exponent and rounds an exact quotient/remainder; it does not reproduce the Bend midpoint-search algorithm. Separate exact rational interval checks validate both neighboring midpoints and parity at ties. Values with enormous decimal exponents use explicit decimal magnitude bounds, recorded separately from rational interval checks. Another **39 invalid/budget fixtures** verify the exact error strings, including malformed exponents, unsupported Java grammar, embedded NUL, a forged surrogate codepoint, and both exceeded budgets.

`src/big_uint.bend`, `src/float_parse.bend`, and `tests/float_parse.bend` each pass the independent kernel. The test harness includes a finite strict-grammar/signed-zero normalization law. This establishes checked types, termination, and that finite law; it is **not a universal decimal-rounding theorem**. `evidence/float-parse-native.json` records hashes, commands, Java/compiler fingerprints, fixture counts/digest, and scalar emitted-C inspection. GPU/JavaScript behavior and numeric throughput are not claimed. Native wall time includes subprocess startup and argument/output IO.
