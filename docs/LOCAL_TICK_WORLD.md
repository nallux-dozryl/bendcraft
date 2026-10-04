# Owned finite-world LocalPlayer aiStep motion projection

`src/local_tick_world.bend` composes the checked local input/apply-input phase,
neutral travel, exact owned-world collision queries and player finishing. It
accepts one existing World Engine and one sine Tables owner. It advances no
world clocks and creates no terrain.

```text
tick_checked(world: W.State, tables: L.Tables,
             prior_local: LI.State, player: PT.State,
             controls: LI.Controls, context: LI.ApplyContext)
  -> W.State & L.Tables & LI.State & PT.State
     & Result<LTW.Error, PT.Transition>
```

The explicit player body must match `W.View.body` bit for bit before preparation
or world reads. This includes position, box, velocity, dimensions and all four
collision flags; signed zero is significant. A host can keep one body in the
view, store only player metadata elsewhere, and construct the explicit player
state at this boundary. On success, the returned player state, transition state
and installed view body agree.

The caller first runs `LI.controls_checked`, replays its ordered
`sprint_updates`, and resolves current attributes after those setter calls. It
then passes the resulting `Controls` and supporting-aware `ApplyContext` here.
`context.tick.travel.sprinting` must equal `controls.sprinting`; an inconsistent
pair is rejected before preparation. `prior_local` is the complete local cache
from before control sampling, because `Controls.state` already contains the new
sampled keys, movement, timer and crouch state.

The operator runs `LI.prepare_checked` once, temporarily installs its prepared
player body, runs `TW.travel_checked` using its widened input, then calls
`PT.finish_checked` once. It does not call `PT.prepare_checked` or
`PW.tick_checked`: the LocalPlayer apply-input replacement already performs the
required `.98f` transformation. Calling the ordinary player preparation again
would apply a different decay twice. Travel performs acceleration, exact
world-backed block collision queries, checked movement, gravity and drag.
Finishing updates the projected player metadata. Local bob/key/timer/crouch
metadata comes from the admitted local preparation.

`LTW.Error` distinguishes `BodyMismatch`, `PreparationError`, `TravelError` and
`FinishError`. Every failure restores the original complete view, `prior_local`
and player state while returning the same World and Tables owners. The view
includes camera angles, dynamically resolved palette, region and render cache.
No failure selects an authority between two conflicting bodies. The internal
recursive Data rollback header has an empty tail and boxes only immutable Data;
it contains neither affine owner.

The caller supplies neutral-context admission facts, current resolved attributes,
support-aware friction/jump samples and Java degree yaw/pitch. Camera radians in
the render view remain independent. Support selection/update is a separate root
runtime operation: after each successful admitted movement it must receive
`Some(transition.displacement)`, including zero displacement and
`position_changed=false`. This module does not infer support history or fabricate
a supporting block.

The existing world bridge reads dynamically mapped air, stone, dirt and oak
planks only. Missing checked sections, unsupported states and excessive finite
query bounds are errors. Direct trusted low-level Core writes can bypass
revision; retain the `W.invalidate_cache` requirement after direct engine or
registry changes. The operator leaves Core sections, ticks, time, pause,
daylight, revision, queued mutations and events unchanged.

This facade covers the declared neutral local input and aiStep motion projection.
It does not implement LocalPlayer `commonTick`, rotation reset, pose updates,
push-out, lifecycle, general sneak-edge correction, minor horizontal collision
classification, nearby actors, fluids, equipment or a complete client tick.
Those contexts require their own observed and checked dependencies. See
[LOCAL_INPUT.md](LOCAL_INPUT.md), [PLAYER_TICK.md](PLAYER_TICK.md),
[TRAVEL_WORLD.md](TRAVEL_WORLD.md), [SUPPORT_WORLD.md](SUPPORT_WORLD.md) and
[CLIENT_WORLD.md](CLIENT_WORLD.md).

## Verification

Run `python3 tools/test_local_tick_world.py --check-entries-only` for the generated
entry checks. Both entries and their aggregate have a **passed native verdict**:
51 primary actual motion calls, eight rejection/recovery cases and dynamic
registry remapping agree with the retained untouched Java reference. The motion
build took 191.890137 seconds; the finish build took 194.262487 seconds. Run
`python3 tools/test_local_tick_world.py --entry motion` or `--entry finish`;
`--skip-build --reuse-reference --reference-sha256 <pinned-artifact-sha256>`
checks retained binary and the default `reference/local_tick_world.json` artifact
without rebuilding or refreshing Java. Its digest remains `d86edd49...`; the
location-only runner compatibility audit did not execute Java or native code. Whole-module mathematical verification remains unresolved. Three installed
compiler attempts rejected the combined harness with an arity-over-247 error,
before a binary or native parity verdict. Their receipts are retained in
`evidence/local-tick-world-native-attempts.json`. Two separate entries are now
generated from the shared harness: motion diagnostics and checked finish rollback
with real motion recovery on the returned owners. Only phase dispatch and named
main adapters differ; their ordinary checks and source pins are recorded in
`evidence/local-tick-world-split-entries.json`.

The separately compiled motion entry also failed with the installed compiler's
arity-over-247 error after 296.645689 seconds. Its exact generated entry, complete
28-file source closure, Python producers and compiler pins are retained in
`evidence/local-tick-world-motion-build-attempt-original.json`; the post-failure audit
confirmed all those sources and producers unchanged. That generation produced
no motion binary or native parity result. The runner can select either entry with
`--entry motion` or `--entry finish`; neither failure establishes a gameplay
mismatch.

A subsequent harness-only revision retains two sprint booleans for after-call
reporting instead of the complete prior local/player/control/context `Phase`.
The prior template and entries remain preserved, and output formatting and
Python expectations are unchanged. The revised shared template and motion entry
ordinary-check. One read-only named diagnostic reached its 120-second cap
without a named error and was terminated; this establishes neither diagnostic
success nor installed native emission. This generation and its unchanged
production/source pins are recorded in
`evidence/local-tick-world-report-reduction.json` and
`evidence/local-tick-world-motion-report-arity-diagnostic.json`. The later
installed native build passed for this revised generation. Its binary, emitted C
and clang flags are retained. A Python comparator framing failure was preserved
with exact stdout before a runner-only correction: the comparator now encodes
actual Java AABBs as twelve raw U32 words each and compares the entire collider
row, including record order, separators and empty groups. Every fixture,
expectation, Bend source and native dependency stayed unchanged. The retained
binary then passed all motion and recovery comparisons, with no Java or native
rebuild. Old/new runner AST/function pins and compatibility checks are in
`evidence/local-tick-world-runner-framing.json`. The revised separate finish
entry also passed its installed build, complete checked-finish rollback and
actual same-owner `LW.tick_checked` recovery, using the exact retained Java
artifact without refreshing observations. Aggregation checks both successful
entries have identical source, runner, table, compiler and reference generations.

The reference file hash changed from `b037e48c...` to `d86edd49...` only because
`execution.seconds` and `execution.stdout_sha256` changed during the later fresh
extraction. The complete canonical cases are byte-identical, canonical inputs
match both original digests, and all non-execution provenance fields agree.
This is sealed in `evidence/local-tick-world-reference-equality.json`; equality
is established from complete records, not counts. The old raw stdout streams
were not retained, so no cause is asserted for their byte-level digest difference.

The harness imports production modules only and retains its returned local/player
state, World and Tables across each sequence. Explicit control setters are applied
before taking current attributes. Expected values come from fresh untouched pinned Java
`LocalPlayer.aiStep` in an actual normally constructed ClientLevel receiver.
Official client class bytes remain unchanged. Four external service fixtures
provide headless Minecraft/GUI/tutorial/network boundaries. Super-calling
observers record control setters, preparation, actual `Entity.move`, collision
query boxes/shapes, support displacement and movement-record application;
observer-free final state is compared independently.

The shared world is exactly 25 stone cells at `x,z=-2..2,y=0`, with checked air
sections elsewhere. Two declared fixtures additionally place stone at `(1,1,0)`
to exercise a real step and blocked movement. Setup and checked queued repairs
occur outside the pure operator. Registry remapping changes numeric IDs without
changing expected movement.

The bounded corpus has 11 histories and 51 actual aiStep calls, including held
forward/diagonal input, double-tap/sprint, sprint cancellation, crouch-input
latency, held jump, sprint jump, release, supplied collision setters, a real step
and blocked movement. Comparisons include complete before/after local/player
state, prepared state/input, accelerated requests, post-toggle attributes, exact
initial/step query boxes, ordered shapes, resolved displacement and application
gates. Seven actual pre-collision sneak-edge probes are recorded separately;
these interior cases preserve the collision request, demonstrated by exact query
and result parity. They do not establish general edge-backoff behavior.

Rejection tests cover inconsistent sprint context, invalid sneaking speed, pitch
and jump factor, mismatched body, missing sections, unsupported states and a
phase-level actual checked finish rejection. Each checks complete rollback and
continued use after repair. The finish phase injection deliberately changes the
context between phases; it verifies the public finish rollback boundary rather
than claiming that a stable admitted context naturally changes mid-call.

Five source laws state owner/state/view rollback. Ordinary checking validates
the module and laws. One installed whole-module `--verdict` attempt failed after
17.226029 seconds with the reported TypeScript/BendTT implementation mismatch;
it did not establish a mathematical verdict. No retry was performed, and no
whole-kernel certification is claimed. The receipt is
`evidence/local-tick-world-kernel.json`.
The separate motion and finish receipts record the complete source closure,
actual Java templates, compiler, retained binaries, emitted C, native flags and
sine table. Their matching aggregate is
`evidence/local-tick-world-verification.json`, which keeps native success and
the unresolved mathematical verdict separate. The one complete canonical Java corpus is
`reference/local_tick_world.json`; concise provenance and digest summaries are in
`evidence/local-tick-world-reference.json`.

The public aggregate and lane receipts contain compact counts, verdicts and
provenance hashes. Their byte-identical full originals are preserved under
ignored `build/local-tick-world-receipts/` and pinned by `raw_artifact` fields.
`evidence/local-tick-world-receipt-compaction.json` verifies the raw mapping and
unchanged deterministic verification facts. The subsequent reference compaction also preserves both byte-identical original
Java artifacts under that ignored build directory. Exactly one unchanged full
corpus remains at `reference/local_tick_world.json`. The two public reference
evidence files now contain summaries. Four runner path literals were updated;
`evidence/local-tick-world-reference-relocation.json` seals the location-only
change against the runner that produced and compared the native generation.
Fixture builders, requests, comparisons, collider protocol, generated entries,
Bend sources, C and native binaries are unchanged. The relocated runner was not
executed during compaction. Recorded native-generation runner hashes are retained
as historical facts; the aggregate separately pins the current runner.
