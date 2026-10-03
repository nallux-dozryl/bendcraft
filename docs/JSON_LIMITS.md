# Configurable pure Bend JSON limits

`src/json.bend` exposes `Limits{max_codepoints: Nat, max_depth: U32}` and
`parse_with(text: String, limits: Limits) -> Result<&2, &2, String, Value>`.
The original `parse(text)` calls `parse_with(text, default_limits())`, with
`default_limits()` returning `Limits{16384n, 64}`. Parsing remains pure Bend;
the AST, strict grammar, duplicate-key policy, number lexemes, serializer, and
typed accessors retain their existing behavior.

For a resource input budget of four Mi code points and depth 512:

```python
J.parse_with(text, J.Limits{4194304n, 512})
```

The cap counts Unicode code points in the input String, including whitespace,
quotes, and escape syntax. It does not count UTF-8 bytes or decoded string
characters. For example, each literal emoji is one input code point and four
UTF-8 bytes; the ASCII spelling `\ud83d\ude00` consumes twelve input code points
and decodes to one scalar. The caller's UTF-8 adapter remains responsible for
validating bytes before constructing a String.

## Supported caps and arithmetic

`max_codepoints` accepts `0..4294967295`, inclusive. Larger Nat values return
`Fail{"JSON max_codepoints exceeds supported limit 4294967295"}` before
counting the input or constructing parser fuel. `max_depth` accepts the full
U32 range, also `0..4294967295`. These are arithmetic bounds, not a claim that
four-billion-character inputs fit available memory or have been exercised.

Offsets and open-container depth use U32. No accepted input can advance its
offset past the code-point cap. Actual open-container depth is also bounded by
the number of input characters. An accepted input receives
`4 * actual_input_length + 16` transition fuel, whose maximum is
**17,179,869,196**. That is below the compiler's native Nat immediate bound
**281,474,976,710,655** (`2^48 - 1`). Fuel uses actual length, so a large configured
cap does not allocate work proportional to that cap for a short input.

The rejection gate is a match branch, so unsupported caps never evaluate the
counting or fuel helpers. This matters because a selection helper would build
both arguments before selecting one. The configured depth cap is carried as
an explicit pure argument through the transition loop and container-opening
check; no global state, host parser, foreign routine, or unchecked recursion
was introduced. The decreasing fuel parameter retains the termination check.

A zero length cap permits counting an empty input, which then fails with
`expected JSON value at offset 0`; every nonempty input exceeds that cap.
A zero depth cap permits scalar values and rejects an opening array/object at
its source offset. Limits can deliberately be smaller than the defaults.

## Errors and compatibility

Overlong input returns `JSON input exceeds N code points`, with the configured
decimal cap substituted for N. Input length is checked before syntax, retaining
the default precedence for an overlong malformed document. Depth failures retain
`nesting limit exceeded at offset N`. Every other syntax error and offset
calculation is unchanged. Offsets are zero-based code-point positions.

Before modifying the parser, all 536 native corpus outputs were recorded,
including the exact rejection messages for cases whose independent grammar
oracle only requires rejection. The modified default parser reproduces the same
aggregate output SHA256:

```text
c2243160169acc26080c84ce30f0b79ba470ece5c4edd37302a2fe27283ff7c9
```

The runner compares that digest on every invocation. All 299 successful
roundtrips still match exactly. It also compares all 503 parsing cases against
an explicit `Limits{16384n, 64}` invocation. The serializer/accessor suffix is
checked against its pre-change SHA256, so this task cannot silently truncate or
otherwise revise encoding.

## Native resource and boundary evidence

Run from the Minecraft directory:

```sh
python3 tools/test_json.py
python3 tools/test_json_limits.py
```

The second command builds `tests/json_limits.bend`, exercises the pure parser
in the native executable, and writes `evidence/json-limits.json`. Large inputs
travel through a test-only Base File reader, bounded at 32 MiB. Python supplies
only fixture generation, strict UTF-8 validation, extraction from the pinned
reference JAR, and an independent JSON oracle with exact number-token hooks,
decoded duplicate rejection, scalar validation, and independently computed
nesting depth. Generated inputs and extracted assets stay in ignored `build/`.

The accepted tested envelope reaches **4,194,304 input code points**,
**4,194,374 UTF-8 bytes**, and **512 simultaneously open containers**. Boundary
tests cover depths 1, 64, and 512 with arrays, objects, and mixed containers,
including exact acceptance and one-container-over rejection. They cover exact
length caps and one-character overflow at 16,384, 1,048,576, and 4,194,304,
large late grammar failures, cap rejection at `2^32` and `2^48 - 1`, and acceptance
of short inputs with the maximum supported caps. The Bend executable constructs
six typed ASTs independently of parsing: a four-Mi ASCII string, over one Mi
emoji scalars, over half a Mi newline scalars, 110,000 number lexemes,
12,000 ordered members, and depth 512. Their output and subsequent configured
parse/encode output match independently generated expected bytes.

The runner checks the SHA256 of the installed 26.3 JAR before selecting the
three largest JSON entries in each of blockstates, models, assets/resources,
and data. The largest entry in each category is:

| Category | Official entry | Bytes | Container depth |
| --- | --- | ---: | ---: |
| Blockstates | `assets/minecraft/blockstates/chiseled_bookshelf.json` | 15,010 | 6 |
| Models | `assets/minecraft/models/block/straw_bed_head.json` | 9,677 | 6 |
| Resources | `assets/minecraft/lang/en_us.json` | 546,577 | 1 |
| Data | `data/minecraft/block_transformer/axe.json` | 60,159 | 8 |

The largest selected density-function documents reach depth 16. All twelve
official inputs parse and serialize exactly as the independent oracle expects
with a four-Mi code-point cap and depth 512. Parsing these documents establishes
JSON behavior only; it does not implement their game/resource semantics.

## Proof status

The source and both test harnesses pass the ordinary checker. Four finite small
parser fixture equalities are included in `tests/json_limits.bend`; they are not
a universal parser-correctness or limit-safety proof. The large arithmetic-cap
rejection fixture executes natively and is deliberately outside that finite law:
comparing two four-billion-sized Peano naturals during proof normalization is
not an appropriate small fixture.

Independent kernel verdicts still reject the JSON module and the imported
fixture harness. The unchanged serializer's previously reproduced structural
descent mismatch remains documented in [JSON_KERNEL.md](JSON_KERNEL.md).
The current source's direct cached-kernel diagnostic, generic verdict output,
commands, hashes, and native results are recorded in `evidence/json-limits.json`.
No kernel validation or general JSON correctness theorem is claimed.
