# Typed mod manifests and lifecycle classifications

`src/mods.bend` implements pure typed manifest decoding, dependency/version
validation, load ordering, side compatibility, client/server metadata matching,
and reload classifications. It imports only Base and the pure JSON module.
There is no host resolver, IO, foreign plugin, unsafe recursion, unfilled law,
or lifecycle execution in this module.

These are **own mod API semantics**, independent of Java mod-loader conventions
and independent of Minecraft's version numbering. Minecraft remains pinned to
26.3. The resolver's caller supplies the exact supported API `Version`; tests
use `1.0.0`. This module does not infer Java loader compatibility or prove
Minecraft gameplay parity.

The runtime's compile-time typed `Server.Driver<State>` can replace arbitrary
owned simulation state, stepping, and dispatch. Manifest declarations do not
restrict a mod to content registration: names such as `world.clock` are valid,
and base-operation names are not reserved by this metadata kernel. Linking,
selecting, authorizing, running, debugging, and reloading those drivers remain
separate work. Declaring an operation never counts as implementing it.

## Public typed interface

```python
type Version is Data:
  Version{major: U32, minor: U32, patch: U32}

type Bound is Data:
  Bound{version: Version, inclusive: Bool}

type Range is Data:
  Range{minimum: Maybe<&2, Bound>, maximum: Maybe<&2, Bound>}

type Dependency is Data:
  Dependency{id: String, range: Range}

type Side is Data:
  Client{}
  Server{}
  Both{}

type Reload is Data:
  Safe{}
  Restart{}

type Manifest is Data:
  Manifest{id: String, version: Version, api_version: Version, side: Side,
    dependencies: List<&2, Dependency>, before: List<&2, String>,
    after: List<&2, String>, operations: List<&2, String>,
    queries: List<&2, String>, events: List<&2, String>,
    data_version: U32, reload: Reload}

decode(value: Json.Value) -> Result<&2, &2, String, Manifest>
decode_pack(value: Json.Value) -> Result<&2, &2, String, List<&2, Manifest>>
resolve(target: Side, api: Version, manifests: List<&2, Manifest>)
  -> Result<&2, &2, String, List<&2, Manifest>>
match_sides(client: List<&2, Manifest>, server: List<&2, Manifest>, api: Version)
  -> Result<&2, &2, String, MatchReport>
classify_reload(old: Manifest, next: Manifest) -> ReloadReport
```

A `MatchReport` contains ordered client/server IDs and their common Both-side
ID order. A `ReloadReport` contains a typed classification, nonempty diagnostic
reasons, and `execution_verified`, currently always false.

`decode` validates field types and local metadata. Pack-wide dependency,
uniqueness, side and API checks happen in `resolve`. Callers that construct
`Manifest` values directly still receive local metadata validation there.
Failures are strings beginning with a named category and include IDs or the
conflicting declaration where relevant. Version/data mismatch diagnostics
include expected and observed values.

## JSON manifest format

The required fields are `id`, `version`, `api_version`, `side`, `data_version`,
and `reload`. The six array fields shown below are optional and default to
empty arrays. Unknown/duplicate fields are rejected at every manifest,
dependency, range, and bound object level. A pack is an array of manifests.

```json
{
  "id": "example:simulation",
  "version": "2.0.1",
  "api_version": [1, 0, 0],
  "side": "both",
  "dependencies": [
    {
      "id": "example:base",
      "range": {
        "min": {"version": "1.0.0", "inclusive": true},
        "max": {"version": [2, 0, 0], "inclusive": false}
      }
    }
  ],
  "before": [],
  "after": ["example:base"],
  "operations": ["world.clock", "example:configure"],
  "queries": ["example:inspect"],
  "events": ["example:changed"],
  "data_version": 3,
  "reload": "restart"
}
```

IDs are opaque namespaced identifiers, not file paths. They contain exactly
one colon and nonempty namespace/path parts. Namespace characters are lowercase
ASCII letters, digits, underscore, hyphen, and period; the path also permits
slash. No trimming or normalization is performed. IDs and declaration names
are limited to 128 characters. Declaration names can additionally contain
uppercase ASCII letters and colon; they need not belong to the mod ID's
namespace. Empty names, whitespace, control characters, and other characters
are rejected.

Versions are exactly three U32 components, provided either as an array or a
canonical `major.minor.patch` string. String components reject leading zeros,
signs, whitespace, exponents, and overflow. Array components require unsigned
integer lexemes and reject booleans, fractions, exponents, and negative zero.
Prerelease/build syntax is unsupported; this is an explicit three-component
core-version domain rather than a claim to the complete SemVer text grammar.
Comparison is numeric lexicographic order, not string order.

Every dependency requires an explicit `range` object. `min` and `max` can be
omitted for an open endpoint; `{}` explicitly means an unbounded range. A
present endpoint requires both `version` and Boolean `inclusive`. Reversed
ranges are rejected. Equal endpoints are valid only when both are inclusive.
There are no inferred caret/tilde ranges, optional dependencies, or implicit
version coercions.

`data_version` is an unsigned U32 version of that mod's persistent state/data
contract. It is not Minecraft's data version and does not implement a data
migration. `reload` is exactly `safe` or `restart`; its meaning is limited by
the classification rules below.

## Pack validation and deterministic ordering

The resolver accepts a mixed installation pack with at most 64 manifests and a
deployment target of Client or Server. Both is a manifest side, not a valid
single deployment target. Each manifest permits at most 64 dependencies, 64
before targets, 64 after targets, and 256 entries in each declaration list.
The JSON decoder also retains the shared JSON parser's input/depth envelope
when the caller uses `Json.parse`.

The resolver performs these checks and transformations:

1. Validate local metadata, duplicate IDs, and exact API-version equality for
   the entire supplied installation pack.
2. Require every dependency and before/after target to exist. Check each
   dependency's range against its provider's version.
3. Require referenced targets to cover the source mod's side. Both providers
   cover Client, Server, and Both; a side-only provider covers only that same
   side. Thus Both cannot require/order against a side-only mod, and Server
   cannot require/order against Client.
4. Select the deployment's side-only and Both manifests. An inactive side's
   bad metadata/dependencies still fail the global contract rather than being
   silently hidden by filtering.
5. Reject operation/query name collisions within the active deployment.
   Operations and queries share one callable namespace. Events have a separate
   namespace, with collisions checked there. Inactive Client/Server mods may
   reuse a declaration without creating a deployment collision.
6. Topologically order the active graph. A dependency and an `after` target
   precede their source mod; a `before` source precedes its target. Among all
   ready mods, choose the lexicographically smallest ASCII ID. Input order does
   not break ties. Self-dependencies and contradictory cycles are rejected.

All before/after references are required constraints, not hints that can be
ignored when a target is missing. The topological loop receives fuel equal to
the active manifest count and removes one exact ID per successful iteration.
No ready candidate reports a cycle with the remaining IDs. Structural helpers
have additional finite work; no constant-time or linear-time resolver claim is
made.

## Client/server matching

`match_sides` takes actual deployment lists, not a mixed installation list.
A Server-only mod in the Client list, or Client-only mod in the Server list,
returns `ForbiddenDeploymentSide`. Each list then resolves independently
against the same caller-provided API version.

Every Both manifest on either side requires a counterpart. Counterparts must
agree on version, API, side, mod data version, dependency IDs/ranges, before and
after requirements, operation/query/event declaration sets, and reload policy.
Versions and range endpoints are normalized typed triples. Order within those
metadata sets is ignored, so equivalent string/triple versions and permuted
requirements are compatible. The relative resolved order of Both mods must
also match; side-only prerequisites can otherwise perturb initialization order.

Failures distinguish `MissingSharedMod`, `SharedVersionMismatch`,
`SharedDataVersionMismatch`, `SharedManifestMismatch`, and
`SharedOrderMismatch`, in addition to resolver/deployment errors. Side-only
mods are independently allowed on their appropriate side.

A successful match validates **declared metadata**. It does not establish code
identity, resource identity, synchronization, network gameplay behavior, or
actual hook compatibility. Those require the later linking/runtime handshake
and external client/server tests.

## Reload/restart classifications

`classify_reload` never executes a reload, swaps state, loads code, or migrates
saves. It produces these deterministic metadata classifications:

| Classification | Conditions | Diagnostic meaning |
|---|---|---|
| `incompatible` | Invalid metadata, changed ID, or changed API version | This cannot be treated as the same compatible mod contract. |
| `restart-required` | Changed mod data version | A migration is needed and is currently unimplemented. |
| `restart-required` | Changed side, dependencies, order, declarations, or reload policy | The installation/runtime contract changed. |
| `no-change` | Same normalized metadata and version | The manifest is unchanged; code identity has not been checked. |
| `restart-required` | Version downgrade or existing `restart` policy on an upgrade | Metadata does not authorize a reload candidate. |
| `safe-candidate` | Version upgrade, identical contract/data metadata, both policies `safe` | Metadata permits consideration; runtime hooks/state migration remain unverified. |

Every result has `execution_verified:false` and a reason. In particular,
`safe-candidate` does not claim that arbitrary opaque owned state can already
be hot-swapped. Build/debug/reload controls and recovery must implement and
verify the actual lifecycle separately.

## Fixtures and verification

Four actual JSON fixture manifests form a representative installation:
`mods/fixtures/base.json` and `biome.json` are Both; `hud.json` is Client;
`telemetry.json` is Server. They exercise mixed string/triple versions,
open/closed bounds, side-only extensions, named declarations, order
requirements, and safe/restart metadata. They are metadata fixtures, not
implemented game mods.

```sh
python3 tools/test_mods.py
```

The runner checks both Bend modules, builds `build/mods-tests`, and executes
503 independent native cases. Python's oracle uses numeric tuples and a heap
based DAG algorithm; it does not call the Bend resolver or implement game/mod
runtime behavior. There are 200 generated DAGs and 200 independent input
permutations, along with fixed success/failure cases for range boundaries,
cycles, missing/duplicate IDs, side constraints, namespace conflicts, API and
Both-side mismatches, strict manifest decoding, and reload classifications.

One general law proves that a Both provider covers every side by exhaustive
case analysis. One finite law checks inclusive lower/exclusive upper range
endpoints. These claims do not prove full resolver or lifecycle correctness.
Both files pass the ordinary checker. Kernel verdicts are recorded separately;
the current attempts inherit the JSON serializer's known descent mismatch, so
no full-module kernel validation is claimed.

`evidence/mods-tests.json` records source/dependency/binary/fixture hashes,
commands, checker/verdict outputs, exact counts, and native results.

## Compiled driver startup manifest

The actual `mods/examples/time_overhaul.bend` executable validates
`mods/examples/time_overhaul.json` before loading the registry or running the
server. Set `MC_MOD_MANIFEST` to select another path; relative paths use the
process working directory. The default assumes launch from the project root,
as does the example's default registry path. An explicitly empty path fails.

The gate reads at most 65,536 bytes and requires EOF after that bounded read.
The existing pure UTF-8 decoder rejects malformed, overlong, surrogate,
out-of-range and truncated encodings, and bounds decoded input to 16,384
Unicode scalar code points. The pure JSON parser applies its own grammar,
duplicate-member, trailing-input and nesting checks. `Mods.decode` and
`Mods.resolve(Server, Version{1,0,0}, [manifest])` validate typed metadata,
API compatibility, dependencies, ordering, conflicts and cycles.

The compiled driver then requires identity `bendex:time_overhaul`, version and
API `1.0.0`, side `server`, data version `0`, and reload policy `restart`.
It requires exactly the operation `mod.time_overhaul.configure`, the query
`mod.time_overhaul.status`, and no events, mod dependencies or ordering
requirements. The combined declared callables must also match the actual
compiled operation catalog. Equivalent string/triple versions and ASCII
escape spellings normalize before comparison. Merely swapping an operation
and a query fails even when the union of names is unchanged.

This is a gate for one compile-time linked replacement of the server's owned
state and transition functions. Editing the JSON cannot install code, change
the `State` type, replace handlers, or authorize hot reload. The manifest's
restart policy reflects that the example has no reload/state-migration
implementation. Neither the startup gate nor the metadata classifier
establishes lifecycle hook execution, save persistence or Java mod-loader
compatibility.

```sh
python3 tools/test_mod_manifest_startup.py
```

The test builds the actual driver executable, launches valid default and
overridden manifest paths, and checks real TCP discovery and both custom
handlers. Invalid manifests must exit with status 2 and a diagnostic before
any `server.ready` output or listener, even with a deliberately broken registry
path and empty developer token. Cases include compiled metadata mismatches,
missing dependencies, cycles, strict JSON/UTF-8 failures and exact input-limit
boundaries. `evidence/mods-startup.json` records each result and source/binary
hashes. The executable's `--check-only` result is recorded separately: it
reaches the standard server's existing unsafe IO loops, while the startup
helpers themselves have no reported checker error. The pure Mods source and
laws retain their independent ordinary-checker results above.
