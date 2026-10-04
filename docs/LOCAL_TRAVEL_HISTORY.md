# Neutral local travel with owned movement and fall history (26.3)

This module is a bounded neutral `LocalPlayer.travel(Vec3)` field projection. It
composes the checked travel preparation and gravity/drag reducers with the frozen
owned local movement/history projection. It changes no runtime or consumer. The
single `MH.State` owns world/body, support cache, minor flag and fall history;
`L.Tables` is returned separately. Production and harness ordinary checks pass.
The granted native build and both unchanged native comparison suites pass: each
suite includes 87 admitted direct travel calls, 40 owner-recovery cases and 18
dynamically remapped calls. Fresh actual receiver extraction contains 63 cases
and 90 direct travel attempts; independent complete repetition and nine integrity
injections pass. Confidence is high for the measured neutral field projection.
The independent proof remains unverified: the single full imported harness
verdict exited with the compiler's generic TypeScript/BendTT implementation
mismatch. This does not identify a failed law or establish a proof.

## Interface and ownership

Import `src/local_travel_history.bend` as `TH`:

```text
travel_checked(MH.State, L.Tables, TH.Request)
 -> MH.State & L.Tables & Result<&2, &2, TH.Error, TH.Outcome>

Request Data {
 input: M.Vec3,
 context: T.Context,
 hooks: Hooks,
 clip: H.Clip,
 tail: List<&2, Request>
}
Hooks Data {
 keys: PI.Buttons,
 input: PI.Vector,                 // current xxa / zza, not travel Vec3
 flying: Bool,
 mode: LC.Mode,
 can_simulate: Bool,
 local_authoritative: Bool,
 stuck_multiplier: M.Vec3,
 removed: Bool,
 auto_jump_enabled: Bool,
 unit_block_speed: Bool,
 zero_restitution: Bool,
 environment: LCW.Environment,
 fuel: Nat,
 tail: List<&2, Hooks>
}
Outcome Data {
 prepared: Preparation { value: T.Prepared, tail: [] },
 movement: MH.Outcome,
 motion: LM.Motion { transition: M.Transition, tail: [] },
 tail: []
}
```

The request contains no independently authoritative body, history, grounded flag,
minor yaw, edge fall distance or edge maximum. Body and grounded flags come from
the sole world View. Edge fall distance comes from its owned history, with its raw
signed-zero payload preserved. Edge step maximum and minor degree yaw come from
`T.Context`. Actual dry travel always calls `MoverType.SELF`, so the adapter derives
`LC.Self{}`. The renderer's `W.View.yaw` uses radians and is neither substituted for
nor compared to the supplied travel degree yaw.

Request and Hooks tails must be empty. `MH.State.tail` must also be empty. A
noncanonical request returns `NonCanonicalRequest{field}` (outer 0, Hooks 1);
a noncanonical owned state returns `NonCanonicalState`, retaining every original
child owner. Recursive boxes bound native continuation capture width; tail
contents carry no gameplay meaning and are never silently ignored at admission.
Immutable outcome body/history snapshots are observations, not additional
persistent authorities.

## Explicit conditional observations

The caller must supply actual current travel inputs, key sample, xxa/zza fields,
resolved supporting-aware ground position and block friction, resolved Player
attributes including any already-applied sprint modifier, degree yaw, maximum
step, sprint/no-gravity/discard-friction flags and neutral movement admission.
Numeric checks establish finite ranges; they do not establish the provenance of
these observations. This module does not resolve attributes, abilities, pose,
current keys, friction or chunks from the owned world. In particular, shift key
and current crouching are distinct actual receiver fields; old crouch/support
caches cannot substitute for current keys. The current minor-collision axes can
differ from the explicit travel argument and must retain their actual values.

The admitted context is dry, locally authoritative and able to simulate, with no
physics bypass, flight, passenger, climbing, swimming, effects or unsupported
world state. Stuck multiplier must be numerically zero; removed and auto-jump must
be false. Only unit block speed and zero restitution are admitted. History uses
the existing fixed neutral dry no-damage contract: actual MISS/NotRequired ray
observations and default safe-fall/damage attributes. Damaging landings, reset-ray
hits and unresolved ray evidence reject. The finite world must dynamically
resolve its four-block palette; missing/unknown states reject rather than become
air. Known-empty entity collisions and a known-clear finite border interior remain
explicit caller declarations, not facts inferred from block contents.

## Actual phase projection

The implemented composition is:

```text
T.prepare_checked(current Body, direct travel argument, conditional Context)
 → install accelerated Body.velocity exactly once
 → MH.move_checked:
     edge backoff corrects request only
     collide / position application branch / collision flags
     support and conditional minor with prepared original velocity
     actual no-damage fall history field projection
     final collision restitution
 → T.finish_checked: gravity then horizontal/vertical drag
 → commit final authoritative Body
```

Preparation retains the pre-move friction and acceleration float operation order
from `T`. Requested/prepared velocity, corrected request, resolved displacement,
pre-restitution body, movement/history transition and final gravity/drag transition
remain distinct observations. Gravity affects final velocity, not this call's
collision request. The history reducer receives resolved Y and the ordered exact
resolved length squared from the collision transition before gravity/drag. It
does not use final Y velocity or old/new position subtraction. The actual position
application branch can execute for zero displacement; `position_changed` records
that branch, not raw position inequality. Support and history can execute even
when the position branch is skipped.

No `.98` input decay is applied. Inherited aiStep input decay belongs to the
separately verified input/tick phases; applying it here would duplicate that phase.
Movement emission, sounds, damaging callbacks, auto-jump and walked distance are
outside this field projection. The real receiver executes their actual inherited
code, with auto-jump explicitly disabled; their outputs are observations outside
the implemented authority. This module does not claim a full travel/tick/client.

Every preparation, movement/history or finish error restores the complete prior
View, support, minor flag and history, retaining the returned Core and Tables
owners. View includes raw body/velocity, camera yaw/pitch, palette, bounds and
snapshot cache. Read-only movement queries preserve canonical cell/trie contents,
revision, clocks and queued actions/events. Finish failure cannot publish the
already-computed movement/history candidate.

## Receiver preparation and verification

The new direct oracle derives the unchanged normal-constructor movement/history
receiver and its four explicitly substituted external LI services. Plain normal
LocalPlayer calls and super-calling observers must agree on projected receiver
state. Actual `p.travel(Vec3)` determines expected results. The observer records
actual acceleration, prepared velocity, whole movement phases, actual block
queries, actual support/minor, actual `ClientLevel.clip` results/reset calls and
final travel velocity. Python orchestrates and compares observed raw values; it
does not calculate the expected game transition.

The receiver experiment checks actual client chunk availability rather than
inferring it from the collision map or cache contents. An initial inference that
an empty actual ClientChunkCache would choose the unloaded-client vertical
fallback was disproved: pinned `ClientLevel.hasChunk(int,int)` returns true, and
`LevelReader.hasChunkAt` delegates to it. The original cache-uninstalled and
populated-cache floor receivers both observe true availability, actual effective
gravity and identical final raw output. Nine normally constructed LevelChunks
installed through original Storage.getIndex/replace methods also have observed
cache identity and all-air/no-fluid sections; this optional fixture setup is not
claimed as a gravity prerequisite. No availability method is substituted.

Five production laws ordinary-check the complete rollback branch, retained
noncanonical owned tail, retained noncanonical request, late finish rollback and
exact binding of degree yaw, maximum and owned history. Ordinary checking is not
an independent kernel verdict. The harness includes a separately labeled finish
failure injection over distinct temporary state, for owner rollback verification;
it is not an expected Java gameplay observation. All forty policy/recovery cases
pass in both native suites, including this injection, child-owner reuse,
post-backoff world failure and post-movement history failure. The five laws remain
independently unverified after the single full harness verdict; no source-only or
projected retry was made.

The first full direct extraction contains 87 admitted calls, two actual unshift
admission guards and one actual damaging-callback service failure. It records 549
queries, 11,953 ordered state reads, 279 yielded shapes, five real clip MISS calls,
85 NotRequired histories, nine minor callbacks and six skipped application
branches. The reference preserves all 90 attempts, including the three excluded
calls. The standalone command protocol has been checked for all 90 observed
inputs: header/body/context/vector/Hooks/environment/seed widths are respectively
5/30/18/6/18/14/8 words. This is input-format validation, not native execution.
Forty policy/recovery cases pass, including complete failure
retention after backoff/history and the separately labeled finish-error injection.

Reproduction and evidence:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_local_travel_history_probe.py --extract
PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_local_travel_history_probe.py --rerun
PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_local_travel_history_probe.py --selftest
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_local_travel_history.py --prepare
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_local_travel_history.py --skip-ordinary
```

`evidence/local-travel-history-preparation.json` pins the 66 Bend/Base/effect
closure, 12 tools/helpers, source, harness, sine table and complete reference.
The exact granted command was
`PYTHONDONTWRITEBYTECODE=1 python3 tools/test_local_travel_history.py --skip-ordinary`.
One installed native build passed in 83.157422 seconds under its 600-second cap;
the helper records 28.194582 seconds for associated C emission and 51.656670
seconds for its installed native phase. These are build timings, not gameplay
benchmarks. Each native process had a 120-second cap. Both complete comparison
suites passed, using 107 processes each, with aggregate process durations
13.350514 and 12.472857 seconds. Their canonical result digest is identical:
`60a6b917b3dd3b039fe29dad9155e3e016b45d8cc85ed9491c4855cd2c832cb4`.
Each suite includes five real MISS histories and six skipped position application
branches, three measured exclusions, forty complete owner recoveries and four
remap histories containing eighteen calls.

Native success was persisted before the one full imported harness kernel attempt,
which exited 1 after 23.779980 seconds under a 60-second cap. Its only diagnostic
is the compiler's generic mismatch between the TypeScript implementation and
formalized BendTT kernel. The independent verdict is unverified. The attempt
includes the exact five source laws; there is no evidence locating this mismatch
at any particular law. Build group 20197 and proof group 21016 were reaped, and the
granted heavy slot was explicitly released. No rebuild or proof retry occurred.

The immutable native binary is 3,585,080 bytes with SHA256
`f09bfb97a9ad236bed47c9ebb05a73c82b8049399cfd614a883d652e7c01a288`.
The retained, content-keyed **preflight C** is 9,953,113 bytes with SHA256
`5d00763ccea62f1dff3110b65ff96be1e73501fa067e3f876f9af10fba796671`.
It is associated with this source generation; the installed CLI's internal
temporary native C was removed and is neither retained nor asserted byte-identical
to that preflight C. The installed build command and compiler recipe, including
Apple clang 17 and `-std=c11 -O3 -lpthread -lm`, are pinned in the build receipt.
The 1,660-entry native dependency manifest is stored once under ignored
`build/local-travel-history-verification/native-build-full.json`, linked by exact
hash/size and canonical manifest digest from the compact tracked build receipt.
Five-second process-group RSS sampling is resource evidence, not a physical
footprint measurement.

See `evidence/local-travel-history-native.json` for the successful native verdict,
`evidence/local-travel-history-kernel.json` for the unchanged unverified proof
attempt, and `evidence/local-travel-history-final-verification.json` for the final
source/tool/dependency/raw-receipt audit. Full comparison reports and each exact
native stdout/stderr remain under ignored
`build/local-travel-history-verification/`; tracked receipts link them by hash and
size. The frozen preflight and preparation receipts retain their historical
pending status rather than being rewritten. The preflight document snapshot is
preserved separately; this final document changes reporting status only.

Reference SHA256:
`07646e7fef0e55f3fd89421d1862b0e6dc5fdde3a0a84800b70b857a66609dbf`.
Java SOURCE template SHA256:
`e0f551b6bb3f2dd7a4e7c1243610f496ed910cd716ffbff597a8b0b7fa85a669`.
Producer SHA256:
`1edea13e62a5d99d780f50020ba890a082f3d5bc6a1b36595b8428c28b522723`.
The complete actual and independent runs reproduce the entire raw observation
and 4,394-class tree digests, as well as the projected fixture values. Supporting
friction metadata uses direct original `computeModifiedFriction` when grounded;
its airborne value is explicitly the audited original float-1 operand. It is not
claimed to capture a private travelInAir local and does not supply decisive final
travel expectations.

Compact reference summaries link exact complete original bytes under ignored
`build/local-travel-history-reference/`; see the reference storage certificate.
The setup reflection-owner error is documented as an independently reproduced
old-source setup failure. Its original full raw output was lost, and is not
represented by the reproduction. It changed only the caller's reflected declaring
class from LivingEntity to Entity, not a method under verification.
