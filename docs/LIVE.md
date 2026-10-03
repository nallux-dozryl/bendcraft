# Pure Bend live-operation dispatcher

`src/live.bend` is the shared pure operation catalog and dispatcher for the live
TCP adapter and the later MCP adapter. It imports Base, the JSON module, the
core, and the deterministic scheduler. It contains no IO, foreign effects,
`@unsafe`, host validation, or calls to low-level `Core.apply`.

This is an implemented **section-and-tick foundation**, pinned to Minecraft
Java 26.3. It does not claim vanilla gameplay parity. Actual transport behavior
is verified separately from these pure dispatch tests.

## Ownership and interface

```python
type Session is Data:
  Session{peer: U32, sequence: Nat, capability: Core.Capability}

new_session(peer: U32) -> Session

dispatch(w: Core.World, session: Session, developer_token: String,
         request: Json.Value) -> Core.World & Session & Json.Value
```

`new_session` starts with Observer capability and sequence zero. Every call to
`dispatch`, including an invalid or denied request, increments the server
sequence once and retains its peer. Client request IDs do not choose ordering
or action identities. The returned world is the unique continuing owner of
its section arrays. The caller must use both the returned world and session
for the next request. Session counters are `Nat`, not wrapping U32 counters.

The configured developer token is supplied by the transport. The dispatcher
never includes it in discovery, responses, or diagnostic messages.

## Envelope and authorization

A request is exactly an object with:

- Required `id`: string, echoed in the response.
- Required `op`: string from the implemented catalog.
- Optional `args`: object; omission is equivalent to `{}`.
- Optional `at`: unsigned U32 integer lexeme, available only on admitted
  mutations.

Unknown envelope/argument fields, duplicate names in manually constructed
ASTs, wrong JSON types, missing required arguments, and out-of-range values
are rejected. Parsed duplicate keys are rejected earlier by the JSON module.
Malformed/non-string IDs produce an empty response ID. JSON text decoding is
a transport concern; `dispatch` accepts an already parsed AST.

Responses are exactly `{id,ok,result}` or `{id,ok,error}`. An error contains a
stable `code` and a nonempty `message`. Common codes are `InvalidRequest`,
`UnknownOperation`, `InvalidArguments`, `PermissionDenied`,
`AuthenticationFailed`, and `PlayerUnavailable`; admission/application errors
retain the core's named error categories.

Observer sessions can call `discover`, `ping`, and `session.open`. Every core
query, control, and mutation currently requires Developer capability.
`session.open` accepts `mode` equal to `observer`, `developer`, or `player`,
and an optional string `token`:

- `developer` succeeds only when the configured token is nonempty and the
  supplied token matches it exactly.
- `observer` explicitly selects Observer capability; the token is unused.
- `player` returns `PlayerUnavailable`; there is no fabricated player or
  ability binding.

Failed authentication, unavailable player mode, and malformed requests retain
the prior capability. Sequence assignment still advances.

## Central typed catalog

`catalog()` returns 13 typed `Operation` descriptors. Each has a tag, name,
phase, required access, argument descriptors, scheduling flag, and an explicit
foundation description. The same `Field`/`Argument` descriptors drive runtime
validation and discovery's input JSON schemas. The later MCP adapter can
consume this inventory instead of maintaining another operation list.

`discover` returns the 26.3 version, foundation surface name, the operation
schemas, and `false` flags for batching, subscriptions, and player mode.
Operation records contain `name`, `phase`, `permitted_mode`, `version`,
`status: "implemented-foundation"`, `scheduled`, `description`, and
`input_schema`. Public entries use `permitted_mode: "observer"` as their
minimum permission. Standard JSON schemas reject extra properties and derive
required arguments from the descriptor. Numeric schemas additionally carry
`x-number-format` because the dispatcher requires integer **lexemes**: `1.0`
and `1e0` are rejected even though generic JSON Schema considers them integers.

| Operation | Phase | Arguments | Behavior |
|---|---|---|---|
| `discover` | discovery | none | Return the actual catalog and implementation scope. |
| `ping` | discovery | none | Return version, peer, current server sequence, and mode. |
| `session.open` | session | `mode`, optional `token` | Select/authenticate a supported session mode. |
| `world.clock` | query | none | Return tick, day time, pause/daylight flags, revision, pending count. |
| `simulation.pause` | control | `paused: boolean` | Change pause immediately and return the clock. |
| `simulation.step` | control | `ticks: integer 1..1000` | Advance the shared core by this many ticks and return the clock. |
| `world.section.create` | admission | position, `fill: U32` | Queue creation of the section containing the position. |
| `world.block.get` | query | position | Read an existing section's registry state ID. |
| `world.block.set` | admission | position, `state: U32` | Queue one block state ID write. |
| `world.time.set` | admission | `day_time: U32` | Queue a foundation day-time value. |
| `world.daylight.set` | admission | `enabled: boolean` | Queue the daylight-cycle flag. |
| `action.cancel` | control | `peer: U32`, `sequence: U32 >= 1`, optional `tick: U32` | Cancel this peer's pending identity; tick is ignored. |
| `world.events` | query | none | Snapshot the newest retained application events. |

A position is `{dimension: string,x: I32,y: I32,z: I32}`. Signed coordinate
lexemes are checked before mapping them to the core's two's-complement U32
bit patterns. Both I32 endpoints are accepted; values outside
`-2147483648..2147483647`, fractions, exponents, booleans, and numeric strings
are rejected. Coordinate `-0` maps to zero. Coordinates are **block positions**;
section creation selects the containing 16×16×16 section rather than treating
the input coordinates as section indices. Dimension/state validity remains
subject to the core's admission checks and configured registry state count.

Unsigned inputs (`at`, day time, state IDs, fill, cancellation identity fields)
use `0..4294967295` with the operation-specific minima shown in discovery.
They reject negative-zero lexemes. Cancellation input sequences are currently
U32 even though the generated session sequence is Nat; this is an explicit
input-domain limit rather than counter wraparound.

## Tick-boundary mutations

The four admitted mutations call `Core.admit` with the current capability and
a stamp `{tick,peer,sequence}`. `tick` is explicit `at` or the next world tick.
`peer` and `sequence` come exclusively from the updated server session. Core
admission checks permission, a strictly future tick, pending capacity,
dimension, and state ID where applicable.

Success returns `{accepted:true,stamp:{tick,peer,sequence}}`. This means queued,
not applied. Section presence/existence is checked by the core when its tick
arrives, and a later failure is reported as a retained rejected event.
Queries and controls reject an `at` field instead of silently ignoring it.

`simulation.step` advances the core explicitly even when paused and preserves
the pause flag. `simulation.pause` only changes that flag. These controls do
not invent another simulation clock; realtime stepping remains the transport's
shared scheduler responsibility.

Cancellation requires `args.peer` equal to the session peer and a positive
server sequence strictly earlier than the cancellation request's own sequence.
The core identifies actions by peer/sequence alone. The optional `tick` field
is range/type checked but has no identity effect. The result includes
`cancelled`, `peer`, and `sequence`; a valid identity with no pending action
returns `cancelled:false`. Cancellation does not rewind applied state or emit
an application event.

`world.events` returns `{order:"newest-first",events:[...]}`. Each event has
`kind`, its original stamp, and either an applied revision or core error. This
is the core's bounded snapshot of up to 1024 events, not a subscription or a
consuming cursor. A snapshot response can exceed the JSON parser's request
size envelope; no response-size equivalence is claimed.

Batch execution, subscriptions, players, entities, saving, and the rest of
Minecraft gameplay are absent from this dispatcher. Unknown operation names
are rejected rather than exposed as placeholders.

## Verification

```sh
python3 tools/test_live.py
```

The runner checks both Bend modules, builds `build/live-tests`, and sends 142
requests through the actual native pure dispatcher across seven declarative
scenarios, plus 4098 real dispatches that authenticate, fill all 4096 pending
slots, and verify capacity rejection without fabricating queue state. Fixed expected responses, clocks, capabilities, and session
sequences are checked after every request. The world observations come from
the same returned owner and verify rejection preservation, queued/application
separation, application errors, cancellation identity, signed boundaries,
query ownership, and controls. The configured fixture token is public test
data, and every output is checked for accidental token disclosure.

Two finite fixture equalities are normalized by the ordinary checker: an
Observer ping and a denied world clock. They do not establish a general
security, schema, or gameplay theorem. Both Bend files report
`ALL PROOFS CHECK` under the ordinary checker. Kernel verdict attempts are
recorded separately in `evidence/live-tests.json`; the initial attempts inherit
the JSON serializer's known checker/kernel descent mismatch and are not
claimed as kernel validation. Rerun after any JSON serializer repair to update
the actual verdicts.

`evidence/live-tests.json` contains the source hash, commands, scenario counts,
checker/verdict outputs, and native result. The lead's transport tests provide
separate evidence for real TCP and MCP framing/dispatch integration.
