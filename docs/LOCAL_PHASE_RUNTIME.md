# Bounded neutral local phase runtime

`src/local_phase_runtime.bend` composes the existing checked reducers into a
single local phase. Its frozen fixed-facts path and additive staged consumer
path admit only the existing history reducer's **CheckedNotRequired** ray
domain. The saved-session/client consumer is being integrated separately; this
module does not establish a complete `LocalPlayer.tick` implementation.

Confidence is high for the inspected phase order and independent Java fixture
observations. Ordinary checking establishes that the source and harness fill
and their source laws check in ordinary mode. Native integrated parity and the
full imported kernel verdict are pending; neither is implied by preparation.

## Authority and API

`State` owns one `MH.State`, one `L.Tables`, one boxed `Metadata`, and an owned
structural tail. `MH.State` is the sole owner of the world/engine/Core, Body,
support state, minor collision state, and fall history. `Metadata` contains:

| Field | Authority |
| --- | --- |
| `local: LI.State` | Previous sampled keys, cached movement, sprint timer, crouching, and bob values |
| `player: PR.Metadata` | Body-free input, jumping/delay/trigger, synchronization flag, stored speed, and head yaw |
| `sprinting` | Final logical sprint flag |
| `pose: Pose.State` | Stable Standing/Crouching pose and cached F32 eye height |
| `controls: PC.Controller` | Complete physical buttons, authoritative degree angles including old angles, mouse state, and options |
| `entity: ECT.Metadata` | Both distinct old-position triples, signed invulnerability word, and wrapping tick count |
| `last_error` | Caller-retained prior diagnostic; phase errors are returned as status |
| `tail` | Data structural ownership, admitted only when empty |

The W view's angles are a derived radian projection of the Controller's degree
angles, using the existing F32 conversion constant. They do not replace the
Controller. The cached Pose eye height is widened to F64 before adding feet;
`W.eye_position`'s fixed eye-height helper is not used.

Public entries are:

| Entry | Effect |
| --- | --- |
| `local_checked(state, request)` | Direct local phase; no Core step or Entity common tick |
| `scheduled_checked(state, request)` | One `C.step`, one `ECT.common_tick`, then the local phase |
| `realtime_checked(state, request)` | Reads the Core paused flag; returns `Done{None}` while paused, otherwise uses scheduled entry |
| `input_checked(state, bindings, packet)` | Atomically applies `PC.apply` and publishes the checked W angle projection; no local sampling or ticks |
| `release(state)` | Physical buttons/mouse release through `PC.release`; sampled LI state and both clocks are retained |
| `query(A, state, operation)` | Threads the exact W owner through a caller's immediate operation; the wrapper itself performs no ticks or sampling |
| `eye_position_checked(state)` | Reads the cached Pose eye from the sole current Body, retaining every owner |

`query` is an owner adapter, not a guarantee that an arbitrary supplied W
operation is read-only. The prepared callers use `W.snapshot`, whose permitted
cache effects remain local to the returned W view. The staged consumer query
below has a concrete checked apply-facts result and a closed provider contract.

`Observation` contains ordered early and late world query records, the ordered
sprint setter list, jump attempt/result flags, and the eye position. It contains
no competing persistent Body, keys, angles, support state, or history authority.
Transient `Frame`/`Work` values contain immutable rollback evidence and prepared
reducer inputs, never a second engine/table owner.

## Conditional Facts

`Request` declares a neutral lifecycle and supplies `ControlFacts`, `ApplyFacts`,
the existing empty-entity/finite-clear-border environment, Entity common-tick
context, and four work budgets. These Facts are conditional evidence at their
named boundaries. Their presence does not implement food, abilities, mobility,
attribute modifiers, or an owned ground/attribute provider.

`ControlFacts` supplies food, abilities, mobility restriction, sprint window,
and the LI neutral mode before control sampling. `ApplyFacts` supplies the
post-sprint ground position/friction sample, attributes, step height, declared
final sprint state, gravity/friction flags, neutral travel/tick modes, jump
strength/factor, fluid-affect flag, and sneaking speed. The final sprint flag is
validated against both the LI decision and its replayed setter list. Repeated
setters remain observable; no attribute-modifier implementation is claimed.

Body, bounding box, velocity, collision flags, on-ground state, pose, current
physical keys, previous sampled keys, degree yaw/pitch, support/minor state,
history, and fit results are derived from the sole owned state. Callers cannot
supply those as Facts. Requests also cannot supply a fabricated clip result.

The Java producer reads food/ability/mobility facts at actual `aiStep` entry
and reads post-sprint ground/jump facts at actual travel entry. The existing
neutral histories keep the early facts equal at the later boundary. Attribute
and lifecycle declarations remain conditional until their owning world/service
sources are implemented and independently measured in general states.

## Phase order and real queries

The actual pre-control fit call at `LocalPlayer.aiStep` bytecode offset 123
checks **Crouching first**. A false result skips Standing. When Crouching clears,
prior sampled shift at offsets 130/133 skips Standing; only prior shift false
and the admitted sleeping=false domain reach Standing at offset 147.
`Crouching` and `Standing` are therefore not unconditionally scanned together.

The local phase performs:

1. Capture the full direct-entry or post-common anchor and check conditional
   admission, Controller/Entity/LI numbers, and coherent stable Pose/Body state.
2. Resolve the current four-state palette against the registry and validate the
   declared empty-entity/clear-border domain.
3. Construct the exact Pose fit boxes, including the official `1e-7` deflation,
   and call `E.query` in the actual short-circuit order above. Only an actual
   query spends one unit of `control_fuel`.
4. Run `LI.controls_checked`: previous sampled keys and movement are inputs;
   physical Controller-held keys become the new sample. Derive crouching and
   the ordered sprint setters, then validate final sprinting.
5. Run `LI.prepare_checked` once with post-sprint ApplyFacts. This applies the
   `.98f` input replacement, jump cleanup, and jump preparation once. It does
   not additionally call `P.prepare_checked`, which would decay input twice.
6. Install the prepared Body in the same MH owner and call frozen
   `TH.travel_checked` with neutral fixed hooks and `H.NotRequired`. The frozen
   reducer owns acceleration, collision movement, support/minor/history update,
   and post-movement drag.
7. Call `P.finish_checked` once, then normalize degree angle ranges through
   `Rotation.normalize`. `Rotation.common_tick` is not called; scheduled entry
   already ran Entity common tick once.
8. Call actual `PPW.update_checked` after movement. Its Swimming feasibility
   query and desired-pose query are late queries at the moved position, distinct
   from pre-control queries. Resize and cached eye installation happen there.
9. Require a stable Standing/Crouching result, publish the W angle projection,
   and read the cached Pose eye through `Pose.eye_position_checked`.

An unqueried Standing slot inside the transient `Fits` record is irrelevant to
LI's short-circuited crouching expression and is never exposed as an observed
world query. Late queries use a separate `pose_fuel` budget. Movement and angle
range budgets are also distinct.

## Checked ray boundary

History rays depend on **resolved collision movement**, not merely the requested
velocity. This generation supplies only `H.NotRequired`. If the frozen history
reducer determines that a ray is required, its checked error triggers complete
local rollback, including Body and history. No MISS is invented.

A general future generation must stage travel preparation, checked movement,
then real FR clipping from old position to
`oldPosition + resolved.normalize().scale(min(resolved.length(), 8))`, before
history application and travel finish, under explicit fixed neutral callback
conditions. That staging and FR ownership are outside this module. Actual FR
inspection already includes a mixed-ray DDA nonprogress case; a finite ray
length by itself does not establish termination or a safe NotRequired result.

## Project transactions and cadence

These rollback anchors are **project policy**, independently tested as policy.
They do not claim Java exception atomicity. The Java fixture's real failure
behavior is retained as separate evidence.

| Entry/failure | Retained anchor |
| --- | --- |
| Nonempty State, MH, Metadata, Pose, or Request tail | Complete original owner tree and all clocks; structural admission precedes extraction/Core work |
| Direct admitted phase failure | Complete direct-entry W view, Body, SP/minor/history, and all Metadata; no Core/common work |
| Scheduled Entity common-tick failure | `C.step` committed, original full Metadata and Body/view retained |
| Scheduled admitted local failure | `C.step` and successful `ECT.common_tick` committed; complete local state restored to that post-common anchor |
| Paused pulse | Exact state returned, no input sample, Core step, Entity common tick, or local phase |
| Failed input packet | Complete Controller, sampled state, Body/view, metadata, and clocks retained |
| Release/read/eye query | No ticks or LI sampling; read-cache discipline belongs to the concrete W operation |

The local rollback retains the engine and tables returned by the failing
reducer and reinstalls the complete anchor view/header/SP/minor/history. It
therefore does not erase a due Core block edit that committed before local
work. On scheduled local failure, both old-position triples, old degree angles,
signed invulnerability decrement, and wrapping tick count remain at their
post-common values. Prior mouse/options and prior diagnostic are preserved.

## Evidence and prepared validation

`tools/reference_local_phase_runtime_probe.py --extract` uses the unchanged
seven `player_tick_phases` histories and receiver services, normal constructed
plain and observed real receivers, the pinned official 26.3 client classes, and
actual world fit calls. Its observation override delegates to the real fit
method. Extra fits made solely by the inherited LI observer are suppressed
from the gameplay fit record. No replacement collision/travel/control/pose
algorithm is authored in Java or Python.

Two fresh paired extractions match exactly. There are 16 actual steps: 15
successful admitted projections and one unchanged sprint-particle fixture
failure (`java.lang.NoSuchFieldError`, missing `Minecraft.gameRenderer`). That
failure remains excluded from the integrated neutral domain; it is not repaired
by changing or adding fixture services. Every original before/after field is
checked against the existing tick-phase reference. Ordered phase snapshots are
losslessly delta encoded; full LI observer records remain in pinned ignored raw
artifacts. `reference/local_phase_runtime.json` and
`evidence/local-phase-runtime-reference.json` retain provenance and receipts.

`tests/local_phase_runtime.bend` contains those 15 raw successful phase inputs
plus 28 independent project-policy scenarios. It reports exact raw Body,
LI/PR/Pose/complete Controller/Entity metadata, support/minor/history, Core
clock/queue/events, complete section trie contents, W view/cache, table samples,
early/late fit boxes/results, ordered setters, and eye position. The policy
cases include direct/scheduled failure anchors, required-ray history rollback,
late crawl rejection, retained due edits, malformed data tails, failed/successful
packets, release, paused pulses, and returned-owner query reuse. State and MH
owned-tail cases carry two independent canonical child worlds with distinct
clocks; both are fully reported before rejection, afterward, and during reuse.

The original ready `tools/test_local_phase_runtime.py --prepare` checked
source/harness in ordinary mode, validated independent reference integrity, and
pinned the full imported source graph and producer generation. Host generation
2 now verifies that immutable preparation instead of regenerating or overwriting
it. The default does not execute Bend or native code. Explicit `--build`,
`--native-only`, and `--kernel` actions remain prepared for a later granted
verification generation. Native comparison only compares raw reference
observations; Python does not implement gameplay.

The original four production source laws state complete local-anchor restoration,
structural child retention, repeated ordered setters, and the zero-phase paused
pulse. Ordinary checking is not a full imported kernel mathematical verdict.

## Remaining domain and integration work

The admitted domain is dry, loaded, neutral, standing/crouching, with empty
entity collision declarations, a finite clear border interior, and the current
dynamic air/stone/dirt/planks palette. Sleeping, vehicles, flight/swimming,
active interpolation, nonneutral inherited callbacks, block effects, ticking
particles, and general attributes/services are not covered by this composition.
The common-tick context specifically names inactive interpolation and the
existing normal client metadata policy. Structural and unsupported admission
must be maintained when later domains are added.

This preparation does not replace `Core.step` scheduling policy, the current
runtime/JSON entry, rendering, persistence, networking, or the complete client.
PPW and ECT source generations are consumed through their current frozen APIs;
their independent evidence and any full-kernel/compiler limitations remain
separate. Native integrated parity, exact defensive policy results, and the
full-import kernel result must be recorded before adopting this module.

## Host execution adoption, generation 2

The original ready bytes, receipts, compiler binary, producer tools, raw oracle
observations, and all 80 imported Bend/Base/effect entries are preserved under
ignored `build/local-phase-runtime/lineage/ready-generation-1`. Its manifest
records the original preparation SHA256
`e88ec198cb25a5510c11699b5be305cc86debba212194f9e58421fb46cb333d9` and
closure SHA256
`aba739dba0cf69dc1dc6d7dcf4674024ad8670ce512ec71f3e6cff11f2bdc5f6`.

At its sealed checkpoint, this host-only adoption changed the runner and this documentation. Source,
harness, oracle, oracle producers/helpers, the imported closure, and ready
ordinary proof receipts remain byte-for-byte unchanged. The separate
`evidence/local-phase-runtime-host-adoption.json` bridges the immutable ready
preparation to the new runner/tool seal. Every mode verifies that preparation,
the complete closure, reference/table/compiler pins, frozen producers, and the
new host seal before execution. Native-only also verifies the retained build's
reference, table, compiler, sealed preparation, host adoption, full build
receipt, and binary pins.

Execution modes reject any occupied output, receipt, binary/cache, or claim
path before launching. Attempts are claimed exclusively and are never silently
overwritten. A new authorized attempt must have separately preserved lineage
and explicit host adoption; no overwrite/retry switch bypasses the guard.

The runner creates argv, stdout, stderr, and a running execution receipt before
launch. It writes the completed execution receipt before checking post-run
generation stability, then amends that same owned receipt with drift or
validation failure. Failed work exits 1; inconclusive work exits 2. A zero exit
requires passed execution and generation validation. Native comparison errors
also persist in their aggregate receipt before returning nonzero.

Each owned command starts a new session/process group. Finally cleanup sends
SIGKILL to that group even when its leader has already exited, waits the owned
leader, reaps any reachable children, and records a bounded enumeration of the
remaining group members. On macOS, orphan descendants are host-reaped; the
runner verifies that the group becomes empty, including absence of zombies,
instead of claiming it can `waitpid` non-child processes. Residual members,
cleanup errors, timeouts, interruption, or unexpected surviving descendants
make execution inconclusive. Spawn publication briefly blocks cancellation
signals; bounded cleanup ignores repeated cancellation while killing/reaping.

Only host Python subprocess fixtures validate this adoption. No new Bend,
native, Java, or kernel execution is part of it. The final read-only reviewer
also identified three unchanged assertion limits: the required-ray comparator
accepts generic TravelError; due-crawl checks changed sections/counts rather
than the exact edited cell and event stamp; and query reporting establishes
owner threading rather than successful snapshot status. These ready fixture
semantics remain frozen pending parent coordination.

## Additive staged consumer generation

The original 80-entry generation and its exact ready artifacts remain in the
generation-1 archive. The complete generation-2 host-adoption checkpoint was
preserved before source changes in ignored
`build/local-phase-runtime/lineage/host-adoption-generation-2`. The fixed
production definitions, fixed harness, reference corpus, and oracle producer
remain unchanged. The additive source and updated documentation deliberately
invalidate the old execution seal: the current runner refuses execution until
the final integrated consumer generation is sealed. No standalone native build
or new ready/preparation cycle accompanies this source addition.

The staged API removes the need to predict sprinting or attributes before
`LI.controls_checked`. `PrepareRequest` contains the lifecycle/common/control
facts, environment, and four budgets from `Request`, with no `ApplyFacts`.

| Entry/type | Contract |
| --- | --- |
| `prepare_local_checked(state, request)` | Capture the direct anchor, run the original fit order and one control decision, return `PrepareResult` |
| `prepare_scheduled_checked(state, request)` | Structural tails reject before one Core/common tick; then capture the post-common anchor and prepare locally |
| `prepare_realtime_checked(state, request)` | Retain the exact paused owner or use the scheduled preparation |
| `PrepareResult` | `AwaitApply{stage}`, `Rejected{state,error}`, or `Paused{state}` |
| `stage_intent(stage)` | Return the stage with `ApplyIntent{sprinting,sprint_updates}` from that decision |
| `stage_query(stage, operation)` | Thread sole `W.State` and immutable owned `SP.State` through one concrete provider, returning the stage with `Result<Error,ApplyFacts>` |
| `resume_apply_checked(stage, status)` | Validate actual facts against the retained sprint decision; prepare input and complete the original travel/finish/rotation/late-pose sequence once |

The concrete operation type is
`W.State -> SP.State -> W.State & Result<&2,&2,Error,ApplyFacts>`.
`ApplyStage` retains one `State`; its boxed `ApplyPending` is immutable
pre-frame/decision/query/failure evidence. It carries no second engine, tables,
or persistent Body. `PreFrame` includes the complete original view, support,
minor state, history, metadata, request, and a Core clock/count stamp.

The real facade resolves its ground sample through `SW.sample_checked` on that
same world/support after reading `ApplyIntent`. It constructs the measured
neutral default attributes after the ordered sprint decision. Control fits and
input sampling are not repeated. The transport does not expose arbitrary
provider closures or numerical `ApplyFacts`. Food/abilities/mobility/lifecycle
still describe the explicitly supported neutral profile; this addition does
not implement a general attribute modifier or service subsystem.

Before invoking the provider, `stage_query` compares the complete raw Body,
projected view angles, palette, region, support/minor/history, every Metadata
field, Core clock/revision, state count, pending count, and event count with
the captured authority. Precheck refusal returns the exact incoming stage and
`ViewError{"apply-provider-authority-drift"}` without calling the provider.
Resume repeats this admission and retains the exact incoming owner on refusal.
After a provider call, cache changes are permitted and Body/view/stamp drift
reinstalls the complete local anchor and remembers the failure. Provider
failures are also remembered, so supplying a later successful status cannot
bypass them. Successful queries retain their cache; admitted failures restore
the original cache with every local field.
Malformed state or staged protocol tails reject while retaining the exact
current affine owner, before a provider or local reducer is called.

This checked hook requires the facade's closed read-only provider and trusted
stage producer. Its stamp detects ordinary scheduling/mutation drift; it is
not a copy of all Core sections/registry/table contents and does not authenticate
arbitrary forged pending control evidence or prove arbitrary code read-only.
As with the fixed transaction, rollback retains the returned engine and tables.
The verified provider must therefore not change Core/world contents. Public
stage constructors are internal composition types, not transport input.

Three additional source laws state complete provider-failure anchor restoration,
exact paused-owner retention, and precheck refusal without invoking the supplied
provider. Source and the unchanged fixed harness pass
ordinary checking. Mathematical kernel validity, native fixed-corpus parity,
staged real-provider comparisons, persistence round trips, and saved-session
cadence remain pending the single final integrated verification generation.

## Frozen corpus in the shared consumer executable

The final integrated test entry is `tests/local_player_session.bend`. Its
entry/runner owner can expose `phase-cases TABLE` through a thin CLI branch that
calls the unchanged phase harness's `arguments([exe,table])`. The fixed harness
declarations, fixtures, and output format are retained; no standalone emission
or fresh Java extraction accompanies this branch.

`tools/test_local_phase_runtime.py` now exports two read-only host helpers:

| Helper | Effect |
| --- | --- |
| `phase_contract()` | Verify the immutable original preparation/80-entry map, all 79 unchanged dependencies and additive source, frozen harness/reference/table/compiler/producers, enabled Python assertions, imported-tool stability, and exact original comparator span |
| `compare_output(stdout)` | Immediately apply the unchanged actual/policy comparators to captured `phase-cases` output; return pinned results or raise on the first mismatch |

The session runner owns its complete final source/tool seal, executable
admission, bounded process group, raw stdout/stderr and execution receipt, and
nonzero failure propagation. The helper neither emits nor launches an
executable and does not grant execution admission. The separate old phase
runner modes continue to fail closed against the changed source/tool/docs;
they are not an alternative standalone validation route.

Prior post-staged source/docs and host-runner bytes are retained in ignored
`build/local-phase-runtime/lineage/comparison-adapter-before`. The helper
addition leaves all 33 original runner functions and the original comparator
span unchanged. `evidence/local-phase-runtime-consumer-comparison-adapter.json`
records host-only pin/admission/refusal checks; these are not gameplay/native
comparison results or a new ready preparation. Actual assertion-disabled Python
also rejects the adapter before comparisons.
