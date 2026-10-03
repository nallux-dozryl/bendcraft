# Direct decimal to binary32 parsing

Confidence: **high** for the recorded native fixtures. `src/float_parse.bend` implements bounded, pure Bend conversion directly from an exact JSON decimal token to an RN-even binary32 value. It imports only Base and the pure `src/big_uint.bend` helper. There is no host float parser, foreign/unsafe dependency, axiom, F64 intermediate, or runtime/compiler modification.

```bend
import ./float_parse.bend as P

P.parse_f32(text: String) -> Result<&2, &2, String, F32>
```

The strict `parse_f32` grammar is exactly:

```text
-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?
```

The entire string must be one token. Empty strings, surrounding whitespace, leading `+`, leading integer zeros, `.5`, `5.`, numeric suffixes, underscores, hexadecimal, Unicode digits, and textual `NaN`/`Infinity` are rejected. This is the number grammar of [RFC 8259 §6](https://www.rfc-editor.org/rfc/rfc8259#section-6). Java `Float.parseFloat` also accepts a broader textual grammar; the separately named `parse_java_f32` extension below handles it. Gson string coercion must explicitly select that API. Exact rounding follows [Java 25 `Float.valueOf(String)`](https://docs.oracle.com/en/java/javase/25/docs/api/java.base/java/lang/Float.html#valueOf(java.lang.String)).

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

## Separate Java textual grammar

```bend
P.parse_java_f32(text: String) -> Result<&2, &2, String, F32>
```

This bounded API supports Java's decimal and hexadecimal float-string forms while leaving the strict API unchanged. It trims leading/trailing codepoints `<= U+0020`, accepts an optional `+` or `-`, leading integer zeros, `.5` and `5.`, and one optional `f/F/d/D` numeric suffix. Hexadecimal forms begin `0x/0X`, contain at least one hex digit with at most one dot, and require `p/P` followed by a signed decimal integer exponent. There are no underscores or Unicode digits. Whitespace inside the token, unsupported suffixes, and incomplete mantissa/exponent forms fail. Signed `Infinity` is accepted. `NaN`, `+NaN`, and `-NaN` all return canonical **positive** `0x7fc00000`, as observed independently on the installed Java 25 runtime. Suffixes apply to numeric forms and cannot be appended to special names.

The 4,096-codepoint budget applies to the original string **before trimming**. Both decimal and hexadecimal mantissas have the same 1,024-digit cap. These are explicit resource restrictions beyond Java's unbounded parser contract. Error names remain `InvalidDecimal`, `InputLimit`, `DigitLimit`, and the defensive `RoundingBudget`.

Decimal forms share the original exact rational rounder. Hexadecimal digits build an exact integer coefficient, with exponent corrected by four bits per fractional hex digit. Bit length permits exact coarse overflow/underflow classification before constructing a bounded power-of-two rational. The same RN-even midpoint search then handles finite, subnormal, and overflow boundaries. A 1,024-digit hex coefficient is at most 4,096 bits; all midpoint intermediates fit **4,373 bits**, below a 4,608-bit envelope. No intermediate binary floating value is formed.

Run the Java grammar suite and the strict follow-up separately:

```sh
python3 tools/test_float_parse.py --java-only
python3 tools/test_float_parse.py
```

The Java suite records **38,718 exact native/Java 25 bit comparisons**: all 20,323 strict decimal regression tokens, 6,132 hex midpoint/below/above cases across every finite F32 exponent, 2,044 exact hex roundtrips, 10,000 random hex literals, 150 decimal syntax variants, every trim character from U+0000 through U+0020, signed special names, huge exponents, long mantissas, and budget boundaries. A test-only C oracle observes the same exact value after syntax normalization and provides **38,714 exact non-NaN comparisons** plus four NaN-class checks. Java receives the original text through a hex-encoded UTF-8 test protocol, including newline/control/NUL characters; it supplies the independent original-grammar oracle. The native parser also rejects all **43 error fixtures** with the specified message; Java independently rejects the 39 malformed-grammar cases, while the other four exercise this module's resource limits.

`evidence/float-parse-java-native.json` stores the extension results. The initial strict report is preserved at commit **5535b4b** in `evidence/float-parse-native.json`. `evidence/float-parse-strict-followup.json` records the original 20,323 valid/39 rejected fixtures against the extended module, with an identical fixture digest and an identical source prefix through `parse_f32`. Default test runs write this follow-up report rather than overwrite the original baseline. The Java name/negative-zero finite law also passes the independent kernel. These results validate the recorded grammar and numeric fixtures; caller model-field policy and gameplay parity remain separate.
