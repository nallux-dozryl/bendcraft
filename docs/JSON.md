# Pure Bend JSON

`src/json.bend` contains the parser, serializer, and typed accessors. It imports
only Base and uses no IO, host JSON parser, foreign function, or `@unsafe`.
The implementation is intended for the bounded JSON messages used by the early
Minecraft core/API. This module does not establish Minecraft protocol parity or
complete resource/data-pack support.

## Public interface

```python
type Value is Data:
  JNull{}
  JBool{value: Bool}
  JNumber{raw: String}
  JString{value: String}
  JArray{values: List<&2, Value>}
  JObject{members: List<&2, Member>}

type Member is Data:
  JMember{key: String, value: Value}

parse(text: String) -> Result<&2, &2, String, Value>
encode(value: Value) -> String
member(value: Value, key: String) -> Maybe<&2, Value>
as_u32(value: Value) -> Maybe<&2, U32>
as_string(value: Value) -> Maybe<&2, String>
```

The ordinary `String & Value` pair syntax has affine `Type` kind in Bend 2.0.35.
A reusable object therefore stores `JMember` values instead of those pairs.
Arrays and objects retain source order. `member` returns `None{}` for a missing
key or any non-object; `as_string` returns `None{}` for any non-string.

`JNumber.raw` is the validated source lexeme, including its sign, fraction,
exponent, capitalization, and trailing fractional zeros. No F32/F64 conversion
occurs. Thus `9007199254740993`, `-0.00`, and `1E+999999` survive parse/encode
exactly. `as_u32` accepts only unsigned integer lexemes in `0..4294967295`;
`-0`, `1.0`, and `1e0` return `None{}` despite their integral mathematical values.
It detects overflow instead of exposing a wrapped integer. Hand-constructed
empty or leading-zero number lexemes also return `None{}`.

## Grammar and policies

The grammar baseline is [RFC 8259](https://www.rfc-editor.org/rfc/rfc8259),
sections 2–7. A top-level value can have any JSON type. Surrounding whitespace is
restricted to space, tab, line feed, and carriage return. Trailing junk,
comments, trailing commas, malformed literals, invalid escapes, unescaped
control characters, and malformed number grammar are rejected. A leading BOM
is rejected.

Duplicate object names are rejected, including names that become equal after
escape decoding. There is no Unicode normalization: `é` and `e` followed by a
combining acute remain different names. Each nested object has its own key set.

Strings contain Unicode scalar values. Valid escaped UTF-16 surrogate pairs
become one scalar character. Lone low surrogates, unpaired high surrogates,
incorrect low partners, raw surrogate characters, and code points above
U+10FFFF are rejected. This deliberately selects the interoperable scalar
subset discussed in RFC 8259 section 8.2; that section acknowledges that the
ABNF alone permits unpaired surrogates.

The public parser accepts a Bend `String`, not raw UTF-8 bytes. A transport
adapter must validate incoming UTF-8 before constructing that string. Byte
encoding validity is outside this module's tested claim.

## Bounds and errors

The maximum input is **16,384 code points**, including whitespace and escape
syntax. The maximum simultaneously open array/object depth is **64**; a scalar
has depth zero. Limits are currently fixed and explicit in `parse` and
`open_container`.

An initial structural pass rejects overlong input after inspecting at most
16,385 characters. Accepted input gets `4 * input_length + 16` parser-transition
fuel. An explicit stack tracks pending containers, and individual helpers
terminate structurally. There are no unchecked recursive calls. Fuel bounds
state transitions; key-trie operations and string comparisons have additional
structurally bounded work and are not claimed constant-time.

Failures return `Fail{message}`. Syntax/depth failures include a **zero-based
code-point offset** in the original input. The input-size and fuel-limit errors
are global and omit an offset. These are positions in the JSON text, not UTF-8
byte positions or positions in decoded string values. For example, parsing
`"é" x` reports trailing input at offset 4.

## Serialization contract

`encode` is a total structural traversal and emits compact JSON. It preserves
number lexemes and array/object member order. It escapes quotes, backslashes,
and every U+0000–U+001F character, using the conventional short escapes where
available and lowercase `\u00xx` for the remainder. Other scalar characters
remain literal; `/` is not escaped.

Values returned by `parse` satisfy the serializer's validity assumptions.
Callers constructing ASTs directly must provide legal JSON number lexemes,
scalar strings/keys, and unique object names. `encode` preserves these supplied
values rather than validating or repairing arbitrary manually constructed ASTs.
It does not sort keys or normalize numbers and is not a canonical-JSON scheme.
Its output may exceed the parser's size/depth envelope for a manually
constructed AST.

## Verification

Run from the Minecraft project directory:

```sh
python3 tools/test_json.py
```

The runner checks both Bend files, builds `build/json-tests`, executes native
Bend regression tests, and compares native output byte-for-byte with an
independent Python grammar decoder. The oracle keeps numeric tokens as exact
strings, detects duplicate names, and validates scalar Unicode. Python only
orchestrates and supplies expected outcomes; the exercised parser, serializer,
and accessors execute in native Bend.

The deterministic corpus covers primitive and nested values, number grammar
and precision, every control-character escape, valid/invalid Unicode pairs,
duplicate names after decoding, accessors, overflow, source offsets, size and
depth boundaries, and wide containers. It includes 250 generated valid trees
and 100 generated invalid leading-zero numbers. Successful outputs are parsed
and serialized again for idempotence. Native-only construction tests also
probe NUL, raw surrogate, and out-of-range `Char` values that cannot safely be
passed as ordinary process arguments.

`tests/json.bend` contains four finite fixture equalities normalized by the
ordinary checker. These are example proofs, not a general parser-correctness,
roundtrip, or RFC-conformance theorem. The 2.0.35 regular checker reports
`ALL PROOFS CHECK`; the independent native corpus provides behavioral evidence.
The proven-kernel `--verdict` attempt is separately recorded. The cached kernel
now runs but rejects `encode_go` with `affine live code, calls that descend`: the
ordinary checker accepts reconstructed `JArray{tail}` / `JObject{tail}` recursive
arguments that the formalized kernel does not accept. Both module and fixture
verdict attempts report this mismatch. No kernel validation is claimed.

The latest reproducible summary, source hash, exact case counts, commands, and
kernel limitation are saved in `evidence/json-tests.json`.
