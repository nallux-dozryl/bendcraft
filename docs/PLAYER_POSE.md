# Player pose phase

`src/player_pose.bend` implements the conditional pose choice and client-side
dimension/eye refresh of pinned Java 26.3 `Player.updatePlayerPose`. It is a pure
phase: it owns no Engine, Core, collision store, player input cache, clock or
Tables. Actual `Level.noCollision` answers must come from a separate authority.
Missing observations are errors.

The source and harness pass installed Bend 2.0.35 ordinary checks. The fresh
actual Java reference passes plain/observed parity and an exact second run.
The frozen native build passes all 243 exact raw-word rows (25.497481 seconds
to build, 0.491586 seconds to compare). The single complete-import harness
`--verdict` passes the independent mathematical kernel in 9.270143 seconds.
The mathematical verdict includes the four source laws; it establishes their
stated preservation/refusal contracts, not universal vanilla behavioral parity.

## Authority and checked interface

All public values are Data. The one authoritative `M.Body` lives in `Request`;
`State` holds only current pose and cached eye height. The module does not infer
pose from `LI.State.crouching`, previous key presses, or Body height.

```text
State{pose:Pose, eye_height:F32, tail:[]}
Flags{sleeping,swimming,fall_flying,auto_spin_attack,
      shift,flying,spectator,passenger:Bool}
Context{flags:Flags, scale:F32, baby:Bool, mode:AdultUnscaledClient{}}
Request{state:State, body:M.Body, context:Context, tail:[]}
FitAnswer{pose:Pose, box:G.AABB, answer:Result<String,Bool>}

metadata(Pose) -> Result<Error,Metadata{width,height,eye_height:F32,fixed:Bool}>
begin_checked(Request) -> Result<Error,Progress>
answer_checked(Progress,FitAnswer) -> Result<Error,Progress>
replay_checked(Request,List<FitAnswer>) -> Result<Error,Transition>
eye_position_checked(Request) -> Result<Error,M.Vec3>
```

The Bend Results have quantities `Result<&2,&2,...>`. `Progress` is either
`Query{work,tail:[]}` or `Finished{transition,tail:[]}`. `Work.query` is a
`FitQuery{pose,box}`. `Transition` contains next `state`, next `body`,
`desired:Maybe<Pose>`, `selected:Pose`, `changed`, `refreshed`, ordered
`queries:List<QueryRecord{pose,box,clear}>`, and `tail:[]`.

Admission requires declared adult client state, raw F32 scale `3f800000`, a
recognized pose, finite Body position/box/velocity/dimensions, the exact current
metadata width/height and cached eye height, and an exact raw box rebuilt from
the existing feet. Stable pose/dimension coherence is required; the transient
state between SynchedEntityData pose notification and dimension refresh rejects.
Unsupported lifecycle mode, age, scale, pose or stale eye/body rejects before a
fit query. Nonempty State, Request or Progress tails reject. Tails box the native
ABI; their payloads are never silently discarded.

`answer_checked` validates the current Request and reconstructs the exact
history prefix, then verifies phase, desired pose, candidate pose and all six
raw F64 box coordinates. It rejects forged progress, NaN/infinity query fields,
wrong order, wrong candidate pose, a one-word box difference, signed-zero
differences and explicit refusal. This verifies a replay's internal consistency;
it does not authenticate the supplier or establish that a world is clear.
`replay_checked` additionally rejects missing or extra observations.

An error returns no replacement state. Data callers retain their original
Request and prior Progress and can retry with corrected observations; the
harness compares the retained original raw state/body and executes an actual
reference-matched recovery afterward. No affine world owner enters this module.

## Actual conditional order

The official bytecode and fresh receiver observations agree on this sequence:

1. Test whether **Swimming** fits. Failure returns immediately, without calling
   `getDesiredPose` or `setPose`; `Transition.desired` is `None`.
2. Determine desired pose, in order: sleeping, swimming, fall flying, auto spin
   attack, current sampled shift while not flying, otherwise standing.
3. Spectator or passenger accepts desired pose without a desired fit query.
   The first Swimming fit test still applies.
4. Otherwise query desired pose. On failure, query Crouching. On another
   failure, select Swimming without repeating the initial Swimming fit test.
5. Call actual `setPose(selected)`. Equal poses skip the SynchedEntityData
   notification and dimension refresh. Changed poses refresh dimensions and
   cached eye height, then reapply the existing feet position.

Duplicate fit queries are observable and retained: desired Swimming is queried
after the initial Swimming query, and desired Crouching can be queried again as
fallback Crouching. Spectator/passenger exemptions and early return must not be
replaced with an unconditional list of all possible queries.

The Java fit box is actual `getDimensions(pose).makeBoundingBox(position())`,
then actual `AABB.deflate(1.0E-7d)`. Width is divided by F32 `2.0f` before
widening, and every coordinate operation retains binary64 words. Bend uses the
same checked `M.make_box` arithmetic and exact double epsilon
`3e7ad7f29abcaf48`. Queries preserve signed zero and coordinates near
±30,000,000 without absolute F32 narrowing.

## Measured metadata and refresh

The table contains raw F32 words from actual `getDimensions`, the cached Entity
eyeHeight, and actual `getEyeHeight`; no value is derived as a height ratio.

| Pose | Width | Height | Eye | Fixed |
| --- | --- | --- | --- | --- |
| Standing | `3f19999a` | `3fe66666` | `3fcf5c29` | false |
| Crouching | `3f19999a` | `3fc00000` | `3fa28f5c` | false |
| FallFlying / Swimming / SpinAttack | `3f19999a` | `3f19999a` | `3ecccccd` | false |
| Sleeping | `3e4ccccd` | `3e4ccccd` | `3e4ccccd` | true |
| Dying | `3e4ccccd` | `3e4ccccd` | `3fcf5c29` | true |

Dying's eye height exceeds its Body height. Other official Pose enum values
currently use Avatar's default standing metadata; they remain explicit
`UnsupportedPose` values in this phase's admitted domain. The reference records
all 18 enum values at scale inputs 1, 0.5 and 2 (54 rows), including Sleeping's
unscaled fixed metadata and Dying's fixed dimensions behavior. The implementation
admits only stable adult unit-scale state.

A changed admitted pose builds the new AABB from the exact stored feet and
measured dimensions. It retains position, velocity, grounding and all three
collision flags, and replaces only box, width, height and cached eye metadata.
An unchanged pose retains the entire original State and Body, including their
raw words. `eye_position_checked` returns the actual formula `(x,y+(double)eye,z)`
after coherence admission. No W.View or renderer consumes this metadata yet.

## Independent receiver boundary

`tools/reference_player_pose_probe.py` privately copies the frozen LocalInput
receiver templates and adds a separate pose observer. Official LocalPlayer,
Avatar, Player, LivingEntity, Entity, EntityDimensions, ClientLevel,
SynchedEntityData and BlockCollisions classes load directly from untouched
installed 26.3 JAR bytes. All receivers use their normal constructors. The same
four declared external service fixtures (Minecraft, Gui, Tutorial,
ClientPacketListener) are reused; no foreground app, window, unsafe allocation
or skipped constructor is involved.

The fixture supplies a 25-stone-cell floor, all other air, and explicit finite
stone/air writes. Its actual ClientLevel actor store and default world border
remain in use. Super-calling observers record the actual short-circuit stages
`noBlockCollision`, `noEntityCollision`, `noBorderCollision`, actual ordered
block reads and actual lazy shape yields, separately from the overall actual
noCollision result. Entity and border stages are absent when an earlier stage
rejects. `reference/player_pose.json` records the stage booleans with each fit
answer; full ordered read/yield traces stay under ignored
`build/player-pose-reference/`.

Sleeping/shared/living flags and passenger relationship are explicit preseeded
fixture state, without lifecycle notifications. Spectator uses the actual
PlayerInfo game-mode setter; the passenger target has a normal ArmorStand
constructor but is not registered in the level actor store. Actual context
getters and the entire pose algorithm execute untouched. These fixtures verify
conditional pose behavior, not sleep activation, vehicle lifecycle, gliding
sound, combat spin lifecycle or their reachability within a whole tick.

The fresh corpus has 46 pose updates (44 admitted and two explicit scale
refusals), 86 actual fit queries, 28 refreshes and 54 metadata rows. Plain and
observed final projections agree; two fresh runs agree on every observation.
It includes open fit, crouch/swim ceilings, blocked initial Swimming, duplicate
queries, exemptions, flag priority, old cached crouching opposite current
shift, unchanged poses, raw negative-zero feet, numeric-equality signed-zero
setter retention, a positive-zero deflated boundary and far coordinates.

The verified Bend harness contains 46 actual update cases, 18 metadata cases
(seven exact mappings and 11 explicit unsupported enum refusals), and 29
rejection/recovery cases. Every output row preserves all raw words. Rejections
cover stale dimensions/eye/box, nonfinite position/velocity/box/dimensions/eye,
unsupported pose/age/scale/mode, nonempty tails, missing/extra/refused/wrong
pose/wrong raw box answers, and forged pending/finished progress. Every altered
case then retries the unchanged original against the independent Java result.

## Reproduction and remaining boundary

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_player_pose_probe.py --extract
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_player_pose.py --prepare
```

Fresh Java runs have a 120-second process-group cap; ordinary checks have a
30-second cap. The installed native command requires an explicit build-queue
grant:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_player_pose.py --native
```

It has a 600-second process-group cap, retains actual emitted C and clang flags
through a read-only compiler wrapper, and compares all 243 expected output rows
exactly. The measured build used `-std=c11 -O3`, pthread and libm. `--skip-build`
requires unchanged retained source/reference/binary pins and performs no Java
or native build refresh. The separate complete-import
`bend tests/player_pose.bend --verdict` attempt had a 60-second process-group
cap and passed without timeout; ordinary checks remain a distinct verdict.

Final receipts are `evidence/player-pose-verification.json`,
`evidence/player-pose-native.json` and `evidence/player-pose-kernel.json`.
Full stdout, installed compiler build manifest, exact clang invocations,
emitted C and binary remain under ignored `build/` paths with SHA-256 pins in
the compact receipts. All ten source/harness/runner/probe/reference/compiler
dependency pins remained unchanged through native and kernel verification.

Future owned integration must supply authoritative pose fit observations,
including entity/border policy and actual block collision short circuit, then
commit the checked Body and eye metadata at the observed late Player.tick pose
phase. This module does not execute commonTick, input sampling, aiStep,
movement/support/fall/minor/restitution, network synchronization, death, scale
attribute lifecycle, server growth repositioning or world clock advancement.
