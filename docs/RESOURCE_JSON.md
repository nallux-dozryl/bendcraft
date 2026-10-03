# Resource JSON text parsing

`src/resource_json.bend` implements a separate pure Bend parser for the text-reader profile used by Minecraft Java **26.3** `CuboidModel.fromStream(Reader)`. It returns the existing `J.Value` tree. The strict live-operation parser in `src/json.bend` is unchanged.

Confidence is **high for the recorded direct Java observations and native comparisons**. No universal theorem of Gson compatibility, full model behavior, or Java string serialization is claimed.

## Public interface and limits

```bend
import ./json.bend as J
import ./resource_json.bend as R

R.parse(text: String) -> Result<&2, &2, String, J.Value>
R.parse_with(text: String, limits: J.Limits) -> Result<&2, &2, String, J.Value>
R.default_limits() -> J.Limits
```

The default policy permits at most **1,048,576 Bend input characters**, including the initial BOM and any ignored suffix, and at most **255 open containers**. `parse_with` can lower the depth budget; a larger requested depth remains clamped to Java's measured 255. Input budgets above 4,294,967,295 fail explicitly, keeping offsets in U32 and the work-fuel expression below native Nat48. Input counting stops after at most the requested limit plus one characters. Work fuel is `4 * input_length + 16`; exhaustion returns a failure. Failed parses return no partial tree.

The whole-input budget is a project policy. The Java probe accepts a quoted string containing 1,048,576 characters, which is 1,048,578 characters including quotes. The native test admits that fixture with an explicitly raised budget and separately verifies default rejection. This is not an inferred Java input-size cap.

Numeric tokens have a fixed **1,023 ASCII-unit maximum**, matching the measured pinned reader's 1,024-unit buffer boundary. They remain decimal text; this parser performs no floating-point conversion. A 1,024-unit token fails in the production STRICT profile, even when the token would be valid arbitrary-length JSON syntax. The limit also applies inside objects and to long exponent spellings.

Errors use project messages and zero-based Bend-character offsets, including an initial BOM. Java exception class, line/column/path spelling, character-count conventions, and timing are not reproduced.

## Actual production reader profile

The probe executes installed production Java methods, with Minecraft 26.3, Java 25.0.1, and Gson **2.14.0** fingerprinted in `reference/resource_json.json`. Bytecode inspection establishes the call wiring; direct executions determine acceptance and tree values.

`CuboidModel.fromStream` calls `GsonHelper.fromJson`. That helper constructs a `JsonReader`, sets `Strictness.STRICT`, calls the requested adapter, and does **not** check `END_DOCUMENT` afterward. The resource parser targets this first-tree text behavior. It does not include the model adapter's field validation, object-root requirements, or null-model rejection; those belong to the model decoder.

| Feature | Production STRICT first-tree behavior |
| --- | --- |
| Strings and names | Double quotes required. Single-quoted and unquoted forms reject. |
| Comments and anti-XSSI prefix | Reject before or inside the tree. Text following a completed root can be ignored. |
| BOM | A single U+FEFF at input position zero is consumed. Leading whitespace followed by BOM, and a double BOM, reject. |
| Whitespace | Space, tab, LF, and CR. Other leading whitespace rejects. |
| Decimal numbers | Strict JSON decimal grammar. Raw tree spellings such as `-0`, `-0.0`, `1e0`, and `1E+0` are retained. |
| Other numeric spellings | Leading zeroes, `+1`, `.5`, `5.`, incomplete exponents, hexadecimal, suffixes, `NaN`, and `Infinity` reject. |
| Keywords | Lowercase `null`, `true`, and `false` only. |
| Duplicate object keys | The last value replaces the prior value; the key retains its first insertion position. Decoded key equality applies to escapes and surrogate pairs. |
| Arrays and objects | Missing elements, missing names/values, trailing delimiters, semicolons, and missing separators reject. |
| Escapes | Standard JSON escapes and four-digit `\u` units. Unknown escapes, escaped apostrophes, and backslash followed by a literal line break reject. |
| Quoted controls | Raw U+0000 through U+001F reject; escaped controls survive. |
| UTF-16 surrogates | Lone units and reversed or separated pairs survive in Java strings; see the projection boundary below. |
| Empty input | Rejects, including whitespace-only or BOM-only input. |
| Suffix / multiple roots | A finished object, array, or quoted string can ignore any following text. Numbers and keywords first validate their immediate token boundary. |
| Nesting | Depth 255 succeeds; 256 rejects. |

Token boundaries are material. `{}x`, `"x"x`, `{} {bad`, and `1 /*unterminated` succeed as one tree. `1x`, `truex`, `1/x`, and `1;2` reject during token lookahead. `1,2`, `1:x`, and `1` followed by form-feed and `x` succeed as the number `1`. Direct tests sweep every ASCII next-character for both a number and a keyword, plus selected Unicode separators. Form-feed is a token terminator in the pinned reader even though it is not accepted as leading whitespace or an interior separator.

The convenience API `JsonParser.parseReader(Reader)` has a different measured profile: its initial tree parsing admits lenient forms, and it checks trailing content under restored legacy strictness; a null root has a distinct skipped trailing-check path. `JsonParser.parseReader(JsonReader)` is measured separately as well. The reference contains those observations, but this module does **not** expose or claim a convenience-LENIENT implementation. For example, the convenience API can classify malformed decimal/nonfinite spellings as strings rather than numbers. Production resources do not select that profile merely because Gson is their library.

## Tree and Java string projection

`JNull`, `JBool`, `JNumber`, `JArray`, and `JObject` retain their existing meanings. `JNumber.raw` preserves the actual strict tree's numeric lexeme; the test oracle compares `JsonPrimitive.getAsString()`. Ordered `JMember` lists contain one entry per decoded key after duplicate replacement.

For `JString.value` and object keys, the projection preserves the complete Java UTF-16 sequence:

- An adjacent valid high/low surrogate pair becomes one Bend scalar character.
- A lone high or low unit remains `Chr{unit}`; it is not discarded or replaced.
- A supplementary Bend scalar corresponds to its two Java UTF-16 units. Raw supplementary characters and equivalent escaped pairs therefore compare as the same key.

This extends the scalar-string contract normally used by live JSON. A projected string containing a lone surrogate is valid as an in-memory resource tree, but the strict UTF-8 encoder rejects that unit. `J.encode` is not a validated serializer for these trees, and no Java-string-to-UTF8 replacement or encoding behavior is established. Callers must choose and verify a serialization policy before exporting such strings. The test harness avoids that ambiguity by returning ASCII hexadecimal UTF-16 units, not literal surrogate output.

Float interpretation and model range rules remain caller responsibilities. `FloatParse.parse_f32` handles strict numeric raw tokens; `parse_java_f32` is a separate textual API. This resource parser does not itself imply that any model getter accepts a quoted numeric spelling.

## Verification and proof boundary

Reproduce direct observations and the native/parser checks with:

```sh
python3 tools/reference_resource_json_probe.py selftest
python3 tools/test_resource_json.py
```

The frozen direct Java reference contains **525 fixtures and 2,100 observations** across production Cuboid parsing, production helper tree parsing, and both convenience parser overloads. Two fresh Java processes produce identical output. Runtime, dependency, model/helper class, input, and observation fingerprints are retained.

The complete run passes **1,315 native cases: 708 accepted trees and 607 rejections**. It additionally obtains fresh production helper trees for 512 deterministic generated inputs, 120 malformed tokens, 78 numeric-buffer boundaries, and 64 actual model-resource texts read from the verified pinned client JAR. Sixteen further cases exercise explicit project policies. Native Bend receives raw U32 character fixtures so raw controls and lone surrogate units do not depend on a host UTF-8 decoder. The parser and tree construction execute in Bend; Python only supplies inputs and compares independent expected observations.

Every unit of strings up to 2,048 UTF-16 units is compared exactly. Larger declarative stress strings compare parsed kind, UTF-16 length, and FNV-1a32, while their expected shape is independently checked against Java's SHA256/depth/node summary. This large-string test is a bounded fingerprint check, not an exact full-output equality. Numeric lexemes and ordinary/nested trees compare their exact projected output.

The source and complete native harness pass the ordinary Bend checker. The full-import `--verdict` remains subject to the existing `json.bend` serializer's formalized-kernel mismatch. `tools/test_resource_json.py` records these full attempts without reporting them as successes. It also builds an isolated kernel projection containing **all production parser definitions**, the exact existing AST declarations, and the seven finite fixture laws. The only transformations remove imports and change namespace prefixes; no parser checks, branches, bounds, or fuel are removed. The native-only observer and unrelated serializer are excluded from that projection. The evidence records the exact transformation, source and projection fingerprints, command outcomes, and proof scope. Independent-kernel acceptance establishes type/termination checking of the projected production definitions and those finite equalities, not a general theorem about Gson or Minecraft models.

Results and reproducible commands are in `evidence/resource-json-native.json`.
