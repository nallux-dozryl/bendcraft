# Block-state registry

`src/registry.bend` loads the dynamic block inventory in `generated/reference_blocks.tsv`, resolves resource identifiers and property assignments to U32 state IDs, and reverses IDs to identifiers and ordered property assignments. Its native resolver has been checked against every explicit state in the pinned Minecraft Java **26.3** official reports: **1,286 blocks and 35,723 states**.

This component implements metadata loading and state conversion. It does not implement block behavior, world generation, palette/save/network codecs, pack discovery, registry synchronization, or a mod lifecycle.

## Public interface

Import with `import ./registry.bend as R`.

| Name | Signature |
| --- | --- |
| `Registry.parse` | `String -> Result<&2, &1, Error, Registry>` |
| `Registry.load` | `String -> IO(Result<&2, &1, Error, Registry>)` |
| `Registry.block` | `(Registry, String) -> Registry & Result<&2, &2, Error, Block>` |
| `Registry.resolve` | `(Registry, String, List<&2, Assignment>, Policy) -> Registry & Result<&2, &2, Error, U32>` |
| `Registry.decode` | `(Registry, U32) -> Registry & Result<&2, &2, Error, Resolved>` |
| `Registry.state_block` | `(Registry, U32) -> Registry & Result<&2, &2, Error, Block>` |
| `error_text` | `Error -> String` |

`Registry` is affine `Type`. It owns an `Array<Block>` and a scalar-valued `Map<&2,U32>` mapping resource identifiers to metadata indices. The array has capacity 4,096, while `block_count` and `state_count` record the loaded ranges. Lookups return the owner beside their result. No arrays are reusable or stored as values inside a generic map. Immutable metadata is `Data`:

```text
Property{name: String, values: List<&2,String>, count: U32, stride: U32}
Block{protocol_id: U32, name: String, first: U32, count: U32,
      default_id: U32, properties: List<&2,Property>}
Assignment{name: String, value: String}
Resolved{protocol_id: U32, name: String, state_id: U32,
         assignments: List<&2,Assignment>}
Policy = Exact{} | Defaults{}
```

Resource identifiers require an explicit namespace, exactly one colon, nonempty namespace/path, and lowercase resource characters. Namespace accepts `[a-z0-9_.-]`; path additionally accepts `/`. `stone` is rejected; `minecraft:stone` is accepted. Unknown well-formed identifiers return `UnknownBlock`.

Assignments may arrive in any order. `Exact{}` requires every declared property, while `Defaults{}` explicitly expands missing properties from the block's declared default ID. Both reject unknown properties, duplicate assignments, and values outside the exact domain. A duplicate is rejected even if its second value is invalid. Assignment validation precedes the missing-property check. Decode emits the original ordered property sequence.

`Error` has the constructors `SchemaError{row,message}`, `ReadError{code,message}`, `InvalidResource{name}`, `UnknownBlock{name}`, `InvalidState{state_id}`, `UnknownProperty{name}`, `DuplicateProperty{name}`, `MissingProperty{name}`, and `InvalidValue{property,value}`. Schema row numbers start at 1, including the header; row 0 identifies input-limit or internal metadata errors. Failed lookups/resolutions return the registry owner. Failed loading returns no partial registry.

Raw constructors and implementation helpers remain module-visible. Construct registries through `Registry.parse/load`; their checks establish the metadata/array invariants used by resolution. No behavior is promised for arbitrarily forged registry records.

## Input validation and mixed-radix indexing

The TSV schema is consumed directly:

```text
block_protocol_id  identifier  first_state_id  state_count  default_state_id  ordered_properties_json
```

Fields are separated by literal tabs. The header must match exactly. LF and CRLF are accepted, including a final row without a newline. Blank internal rows, missing/extra fields, malformed or overflowing decimal U32 values, invalid names, duplicate names, noncontiguous protocol/state IDs, empty domains, duplicate property names/values, invalid property JSON shapes, count/product disagreement, default IDs outside their interval, and arithmetic overflow are rejected.

Protocol IDs start at 0 and increase by one. State intervals start at 0 and are contiguous. The JSON property array preserves significance order; the loader derives each stride as the product of all following domain lengths. No giant hand-written block switch or generated Bend literal inventory is used.

For a validated block and each property's domain index `digit`:

```text
state_id = first_state_id + sum(digit * stride)
digit    = ((state_id - first_state_id) / stride) % domain_count
```

Forward name lookup uses the scalar index map. Reverse state lookup binary-searches the ordered block intervals, with 14 bounded steps covering the 4,096-block capacity. Property domains are bounded lists. Default expansion decodes the default state's digits and replaces only the explicitly assigned digits.

The current envelope is 4 MiB for file reads, 4,194,304 code points for direct text parsing, 4,096 blocks, 64 properties per block, 256 values per domain, 512 code points per resource identifier, 128 per property name, and 256 per nonempty domain value. Each property JSON field also inherits the JSON module's 16,384-code-point and 64-level bounds. State counts/endpoints must fit a U32 exclusive range; state ID `4294967295` is outside the supported loaded range. These are explicit implementation limits, not Minecraft behavior claims.

Base IO supplies bounded file reads and UTF-8 strings. Header, TSV, numeric, JSON property, domain and registry interpretation all execute in Bend. Python is used only for test orchestration and independent report-derived expectations. Custom namespace/domain fixtures and the capacity boundary demonstrate that metadata comes from the loaded source; no mod registration API or gameplay integration is claimed.

## Verification

`tools/test_registry.py` verifies the pinned report fingerprints against `reference/release.json`, then uses explicit official `blocks.json` state entries as the expected answers. It independently derives expected metadata from those entries and registry protocol IDs. Forward requests deliberately reverse lexical assignment order.

The native suite verifies:

- All 1,286 block metadata records, including ordered domains and strides.
- All 35,723 forward state resolutions and all 35,723 reverse decodes.
- All 1,286 default IDs, 2,313 partial default overrides, and 884 strict missing-property errors.
- 1,286 unknown-property errors, 884 invalid-value errors, and 884 duplicate-property errors.
- Invalid names/IDs, lexical U32 overflow, value spelling differences, and continued operation after rejected requests.
- Malformed loader inputs, duplicate decoded JSON strings, custom names/domains, CRLF/EOF handling, and accepted/rejected 4,096/4,097-block capacity boundaries.

Five small implementation laws cover missing-property rejection, duplicate priority, a mixed-radix default fixture, ordered decode, and preservation of the affine owner after an invalid public decode. They introduce no axioms, placeholders, unsafe code, or custom foreign implementations. The Bend checker accepts them. At the initial run, the separate BendTT kernel rejected imported `json.encode_go` with `affine live code, calls that descend`; kernel status is recorded independently in `evidence/registry-verification.json` and must be read before claiming kernel verification.

Reproduce from `minecraft`:

```sh
python3 tools/test_registry.py
/Users/chuah/.bend/bin/bend src/registry.bend --check-only
/Users/chuah/.bend/bin/bend src/registry.bend --verdict
/Users/chuah/.bend/bin/bend tests/registry.bend -o build/registry-tests
build/registry-tests --threads 1 --gpu off generated/reference_blocks.tsv
```

Evidence contains source/report fingerprints, coverage counts, malformed-input results, native execution summaries, and kernel status. Query fixtures, emitted C and native executables are generated under ignored `build/registry-oracle`/`build`; original reference files remain unchanged. Runtime durations describe this metadata test workload and imply no Minecraft speedup.
