# Typed blockstate resources and state dispatch

`src/blockstate_model.bend` implements pure typed decoding and property-based
dispatch for the measured Minecraft Java **26.3** blockstate resource codecs.
It consumes the existing `J.Value` AST and `ResourceJson` production reader. It
does not read registries/files, resolve model parents/textures, bake geometry,
own a random source, or create a client world. Confidence in the covered behavior
is high where the native runner agrees with direct execution of the pinned Java
classes; fixture coverage does not establish universal game correspondence.

## Public boundary

- `parse(text)` and `parse_with(text, J.Limits)` return
  `Result<&2,&2,Error,Definition>` through `ResourceJson.parse/parse_with`.
- `decode(J.Value)` accepts a supplied tree. `Definition` retains optional
  source-ordered `Selector` and `Part` lists.
- `Variant{model,x,y,z,uvlock}` retains a normalized model identifier, degrees
  in `0/90/180/270` on each of the three confirmed resource axes, and UV lock.
  These fields can be supplied directly to `BlockBake.State`; model resolution
  and sprite context remain separate inputs to the baker.
- `Choice` is `Single{variant}` or
  `WeightedChoice{entries:List<&2,Weighted>,total:U32}`. Each weighted entry
  retains its original order and positive signed-32-bit weight.
- `Schema{owner,properties:Map<&2,Property>}` supplies the actual block property
  domains. `Property{values,integer}` distinguishes integer-property spelling
  rules from exact enum/boolean names. Domains contain unique canonical names;
  the recorded value order is used in selector diagnostics.
- `State{id,properties}` supplies actual ordered registry states and canonical
  property values. `instantiate(definition,schema,orderedStates)` returns
  `Prepared{models,diagnostics}`; `lookup(prepared,id)` returns an optional root.
  State IDs are retained and are independent of list position. Instantiation
  validates domain spelling, complete state property maps, and unique IDs.
  The caller supplies the full actual state iteration for game correspondence;
  this boundary does not acquire the registry or prove that a supplied list
  contains its entire Cartesian state space.
- `compile_selector(schema,text)` and `match_selector` expose simple selectors.
  `decode_condition`, `bind_condition`, and `matches` expose multipart conditions.
  `matches` binds every term before evaluation, including terms made redundant
  by other alternatives. `bound_matches` returns a checked result as well.
- `candidates(definition,schema,properties)` reports all independently matching
  valid simple selectors and multipart parts, with invalid-selector diagnostics.
  This helper is **not the actual overlapping-selector state-map construction**.
  Use `instantiate` with the real ordered states for that construction.
- `dependencies(root)` returns unique model IDs in sorted identifier order.
  A multipart root retains dependencies from **all declared parts**, including
  inactive parts and parts with conditions that match no supplied state.

`Error{code,path,detail}` is a structured diagnostic. All recorded simple
selector errors have byte-identical Java `message` details. The aggregate
`DataResult` exception text for condition/dispatcher union failures is not a
public byte-for-byte error contract: Bend exposes the underlying failure with
its path, and the evidence retains the exact Java exception class/message.

## Observed decoding rules

The resource text profile is the actual `GsonHelper.fromJson` STRICT first-value
reader, without a trailing-document check. Duplicate object members replace
the value at the first key position. `ResourceJson` owns these text semantics;
the ordinary live API's `J.parse` is unchanged. Lone UTF-16 units can survive in
the in-memory tree; the existing JSON serializer's limitations are documented
separately in `RESOURCE_JSON.md` / `JSON_KERNEL.md`.
Supplied `J.Value` objects are expected to have unique member keys, as Gson's
tree and both supplied JSON parsers do; manually forged duplicate AST members
do not constitute a Gson tree.

Unknown resource fields are ignored. For these codecs, null fields behave as
absent: null rotations default to zero, null UV lock defaults to false, null
array-entry weight defaults to one, and null `when` means unconditional. A
required null model is missing. A null variant-map value or null multipart-list
element still fails; field absence does not remove collection entries.

Model IDs require JSON strings. Omitted or empty namespaces normalize to
`minecraft`. Namespace/path character checks match the measured identifier
codec, including accepted empty paths; identifiers do not denote filesystem
paths. Rotation and weight fields require JSON numeric primitives, rather than
numeric strings or booleans. The integer codec truncates exact decimal lexemes
toward zero and retains the low signed-32-bit word. Rotation then normalizes
signed degrees modulo 360 and rejects non-quarter turns. For example, `90.9`
becomes 90, `-90` becomes 270, and `4294967386` wraps to 90.

A model object forms `Single` and completely ignores its `weight` member,
including malformed/negative values. A model array must be nonempty; every
entry's weight and the sum must be positive and at most `2147483647`.

## Property selectors and conditions

Simple selectors split on comma and the first equals sign. They preserve
whitespace, retain trailing empty pieces, and ignore pieces with an empty
property name. Repeated property tests replace the previous test only after
each encountered value has passed validation. Consequently a preceding invalid
value cannot be rescued by a later valid value. `north|south` is one invalid
simple enum value, rather than a union selector.

Integer properties use measured Java `Integer.parseInt` spelling: optional
ASCII `+/-`, leading zeros, signed-32-bit bounds, and decimal digits from the
37 measured BMP digit families. Supplementary digit characters are rejected,
matching Java's UTF-16 `char` parsing. Canonical domain names remain ordinary
signed decimal strings. The fresh Java runner enumerates all digit-zero
characters and independently checks all ten digits from every family against
the actual wheat age property.

Multipart conditions are nonempty key/value maps, or singleton `AND` / `OR`
members whose values are arrays. Empty `AND` is true and empty `OR` is false.
Multiple map entries combine property tests with AND; pipe-separated terms
within a property combine with OR. A single leading `!` negates that individual
term. Empty terms fail. Every term is validated eagerly, so
`true|false|bad` still fails. Numeric and boolean condition primitives follow
the actual legacy INT/BOOL-to-string alternatives before property binding.
`AND`/`OR` primitive values may reach the key/value fallback and subsequently
fail as unknown properties; mixed combiners and key/value entries are not
silently reinterpreted.

## Exact ordered instantiation and weighted tickets

Variant selectors are applied in the actual decoded map iteration order. An
invalid selector records a diagnostic and is skipped. For each valid selector,
matching states are visited in the caller-supplied registry iteration order.
When a state already has a variant root, the new root first **replaces** it,
then the Java-equivalent overlap diagnostic aborts the remaining states for
that selector. Later selectors still execute. Multipart roots fill states
left unmapped by variants. Unknown properties/values in multipart conditions
are fatal during binding, including when variants already cover every state.

This behavior makes input iteration order part of the boundary. A list of
matching candidates for one state cannot reproduce that global construction.
The fresh Java oracle records both actual variant-map iteration order and
per-state root contents, rather than relying on Python dictionary behavior.

`choose(choice,ticket)` selects weighted cumulative half-open integer intervals
in entry order. A `[1,3]` choice gives the first entry ticket 0 and the second
tickets 1 through 3. Weighted tickets must be less than the validated total;
forged totals, nonpositive weights, overflowing sums, and uncovered tickets
fail. `Single` ignores every ticket, including `4294967295`.

A Java `RandomSource` proxy independently records bounded calls and selected
entries for all 23 valid tickets in six fixtures. Nonuniform, unit-weight,
equal-weight and singleton arrays call `nextInt(totalWeight)` exactly once;
single model objects make no RNG call. Bend receives a ticket explicitly and
does not advance a random source. This establishes interval behavior, not
whole client/world RNG sequence parity.

## Bounds and verification

- Condition decoding, binding, and evaluation each allow 262144 node/finish
  work steps, with explicit `ConditionWorkLimit` failure. The implementation
  uses single bounded work-list loops, without mutually recursive definitions,
  unsafe annotations, foreign code, axioms, or a host resolver.
- Instantiation accepts at most 65535 ordered states.
- Numeric conversion supports exponent magnitude at most 100000, returning
  `IntegerExponentLimit` above it. Exact raw numbers are first checked with the
  resource parser; no binary floating-point conversion is used.
- Default text parsing uses the existing resource budget of 1048576 input
  characters, depth at most 255, and numeric tokens at most 1023 ASCII units.
  Explicit text limits remain subject to that parser's documented caps.

Reproduce the actual Java oracle and native comparison with:

```sh
python3 tools/test_blockstate_model.py
```

`--oracle-only` executes only the pinned Java probe. `--prepare-only` prepares
the exact production-definition kernel projection without compiling it.
`--reuse-oracle` validates cached oracle input/output hashes before reuse.
`--skip-build` requires a receipt matching every transitive source hash,
compiler hash, and native binary hash. `--skip-kernel` omits only verdict runs.
The runner's subprocess timeouts are recorded even when independent full
verdicts cannot finish, and native evidence is saved separately from a general
game-parity claim.

Ordinary source/harness/projection checks pass. Direct Java observations are
saved in `evidence/blockstate-model-java.json`. The first native harness build
timed out after 600 seconds with a sampled physical footprint of 13 GiB; its
exact command, hashes and empty output are preserved in
`evidence/blockstate-model-build-attempts.json`. The narrowed harness retry
built in 204.938 seconds with production and Java expectations unchanged.
All **560 native requests** pass: 388 successful results and 172 expected
rejections. Coverage includes 404 simple selectors, 56 conditions, 80
dispatcher edge cases, eight official resources covering all 124 supplied
registry states, six weighted-selection fixtures with 23 directly measured
valid Java tickets, out-of-range tickets, and six explicit schema/state
boundary failures. The final comparison took 0.769 seconds after a receipt-
validated build reuse; the initial comparison took 1.449 seconds.

Both full-import `--verdict` commands report a compiler/kernel mismatch
(17.436 and 17.793 seconds). They are **not independently validated**. The
complete isolated projection's verdict passes in **22.786 seconds**, checking
the production ResourceJson and Blockstate definitions and eight finite laws.
Commands, exact stdout/stderr, source/projection/native hashes and build receipt
are recorded in `evidence/blockstate-model-native.json`. Full imports include
the separately measured JSON serializer verification limitation. The
isolated projection retains **every** ResourceJson and Blockstate production
type/function, exact JSON AST/Limits declarations, and eight finite fixture
laws, changing only imports and lexically safe namespace names. It excludes
the unreachable JSON parser/serializer and native IO harness; it does not
replace a production body, check, limit, or condition. Even a successful
projection proves typed termination and those finite laws, not universal
Minecraft codec or dispatch correspondence.
