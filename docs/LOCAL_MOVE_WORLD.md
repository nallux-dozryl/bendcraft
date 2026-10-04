# Neutral LocalPlayer movement projection

`src/local_move_world.bend` composes the checked owned-world backoff, collision, support and horizontal-minor helpers in the order observed in Minecraft Java 26.3. It has passed ordinary source/harness checking and a native build. All 74 admitted actual movement cases and one measured guard pass the native corpus comparison. All 23 policy/recovery cases and 14 moves across four registry-remap histories also pass. The single independent full-harness kernel attempt remains unverified after a TypeScript/BendTT mismatch.

This is an intermediate projection within the full implementation goal. It does not establish a complete player tick, general world collision implementation or full Minecraft parity.

## Owned interface

```bend
move_checked(world: W.State, tables: L.Tables, support: SP.State,
             minor: MinorState, request: Request)
  -> W.State & L.Tables & SP.State & MinorState
     & Result<&2, &2, Error, Outcome>
```

`W.State` retains the sole Core/Registry owner and authoritative `W.View.body`. `L.Tables` retains the exact pinned sine-table array owner. `SP.State` stores transient supporting-block history; `MinorState{minor:Bool}` stores the separate collision flag that `M.Body` does not contain.

`Request{body,requested,context,environment,fuel,tail:[]}` supplies a raw copy of the current Body, requested displacement, observed context and bounded query fuel. The raw Body must equal the world Body, including every F64/F32 word and flag. Numerical equality does not admit a different signed zero.

`Context` contains `LC.EdgeContext`, `LC.MinorInput` and explicit admission observations: can-simulate, local authority, stuck multiplier, removed, auto-jump enabled, unit block-speed factor and zero restitution. The admitted lane requires simulation/local authority, numerical zero stuck multiplier, live receiver, disabled auto-jump and actual unit-speed/zero-restitution behavior. Edge context carries observed current key presses, actual fall distance, current maximum step and mover; minor input carries actual yaw degrees and current `xxa`/`zza`. Unsupported LC modes, flying and movers reject. The adapter does not manufacture these observations from crouch/support caches. The current corpus resolves zero restitution through actual shift/suppressed-bounce observations; its unshifted guard is denied.

`Environment` is the LCW declaration of known-empty entity collisions and known-clear world-border interior. These tokens authorize only the stated finite neutral fixture/interior policy. They are not observations of an arbitrary world's actors or border. The current finite world uses dynamically looked-up AIR, STONE, DIRT and OAK_PLANKS default states. Missing sections, unknown states and absent/stale palettes reject; they never become assumed air.

`Outcome` stores boxed `Motion{transition,tail:[]}`, exact LCW backoff records, boxed immutable pre-restitution Body evidence and an optional `LC.MinorObservation`. The authoritative resulting Body remains in returned W.State. Recursive Data tails are structural boxes for native capture limits and are constructed empty by the protocol; they carry no movement semantics. Helpers `motion_transition`, `snapshot_body`, `transition_body` and `transition_displacement` expose the values without broad pattern captures.

On every error the original full View, Body, support history and minor flag return with the same World/Tables owners. Core reads remain reads: ticks, world time, revisions, pause/daylight state, pending mutations/events, registry, palette, camera, region and snapshot cache are preserved. No world mutation or owner replacement occurs within move_checked.

## Actual ordering and temporary velocity

Untouched `Entity.move`, inherited `Player.maybeBackOffFromEdge`, inherited private collision/restitution and `LocalPlayer.move/isHorizontalCollisionMinor` execute in the real-constructor oracle. Super-calling observers record the callbacks without substituting methods under verification.

1. Actual edge backoff corrects the request before private collision. The **corrected** request drives the length gate, horizontal/vertical collision comparisons and restitution.
2. The actual position branch executes when resolved squared length exceeds `1.0E-7`, or corrected squared length minus resolved squared length is below `1.0E-7`. Transition.position_changed records branch application, not whether numerical coordinates differ. A zero move can enter this branch.
3. Flags update, then locally authoritative `setOnGroundWithMovement` passes the actual resolved Vec3 to `checkSupportingBlock`, including when the position branch skips.
4. Support runs before minor classification. Minor is called only on horizontalCollision; otherwise the minor flag becomes false.
5. `getOnPosLegacy`/block-state sampling and `checkFallDamage(resolvedY,onGround,state,pos)` follow support/minor. The removed check follows fall handling.
6. Velocity restitution follows those callbacks, then movement emission, block-speed sampling and horizontal speed scaling. LocalPlayer's wrapper calls updateAutoJump and addWalkedDistance afterward.

The actual support/minor callbacks see original `deltaMovement`, including signed zeros, even though position, box and collision flags already reflect resolution. W.move computes the final restituted Body. This adapter temporarily installs the corresponding position/box/flags with the original velocity for support/minor, then commits the final Body. The temporary value is an immutable evidence snapshot, not a second persistent authority.

The current projection leaves fall-history mutation, movement/emission bookkeeping, auto-jump and walked-distance projection pending. AutoJumpEnabled=false is an observed admitted fixture condition. Their untouched Java methods still execute in the oracle. The separate PlayerFallHistory work must bind EdgeContext.fall_distance to one authoritative history and consume resolvedY, branch application and real clip evidence at the recorded phase; this adapter provides no forged clip MISS or fall-distance update.

## Query and recovery policy

LCW produces exact ordered noCollision requests and actual owned Core read/first-yield records. Collision admission additionally contains a conservative initial/entity/step sweep inside the declared clear interior, with a downward margin enclosing the real negative step-query epsilon. After resolution, exact support primary and backward-fallback boxes are separately admitted before support reads. This also covers a skipped-position gate's backward query. The adapter conservatively admits both computed support boxes even if selection will avoid the fallback; this is explicit caller policy and may reject a narrow interior that would happen to avoid that query.

The harness additionally replays production W.collect and support selection on the same unchanged Core generation to expose initial/step collider boxes/lists and primary/fallback query boxes/selections. These are labeled **read-only query replays**, not claimed instrumentation of each internal production Core read. The source's outcome supplies actual backoff records directly. Oracle totals include all actual observed queries and reads; the completed native comparison asserts exact backoff read traces, exact collision-list order, exact support query/selection, raw Body/flags, temporary callback velocity and final minor state.

Recovery verification covers raw signed-zero Body mismatch, each neutral admission flag, unknown actors/border, query fuel, outside interior, absent/stale palette, missing section, unknown block state, a real collision-only unknown read after successful backoff, unsupported modes, nondefault running clocks/pending queues, and four dynamically remapped registry fixtures. Every failed request is followed by a successful request and sine-table owner read on the retained owners. All 23 policy/recovery cases, the nondefault running/pending-queue case and four registry-remap histories/14 moves pass. The interior case initially stopped on its expected error string after full prior-owner rollback checks passed: the source correctly reports `local-move-sweep-outside-interior`, while the test expected an earlier edge-query error. The root-authorized repair changes that single expected literal; an exact whole-runner AST audit proves no other change. The retained-binary comparison then passes. No source, oracle, harness, fixture input or executable fix/rebuild was needed for either comparator correction.

Three production laws passed the ordinary checker: failure restores full View/support/minor while retaining World/Tables; the temporary Body retains original velocity; context denial uses the same rollback path. Ordinary acceptance is not independent proof.

## Independent actual reference

The frozen reference contains **61 cases / 75 whole moves**, of which **74** satisfy current neutral admission. It observes **503 actual queries / 13,743 ordered state reads / 364 yields**. Plain normal-constructor and observed receivers match all projected final states/context. An independent actual rerun matches every reference case/step and the 4,383-class official loaded tree. Six integrity mutations are rejected, including client/runtime/library/JRT/fixture-source/ordered-read changes.

The completed native actual-corpus comparison covers 74 moves, 187 backoff queries/4,523 ordered backoff reads, 102 initial/step collision lists/247 shape yields, 63 support queries/selections, seven skipped position branches and 22 minor calls. The actual reference additionally records one noCollision query inside PLAYER `recordMovement` (26 reads/one yield), after maybeBackOff has returned. It remains preserved outside this movement/emission projection. The first comparator incorrectly counted that recordMovement query as backoff; the root-approved repair selects queries strictly between actual maybeBackOff entry/exit markers and rejects an excluded query unless its markers lie inside actual recordMovement. Exact comparison/report AST audit proves all other helpers/math/body expectations, source, harness, oracle, fixture inputs and binary stayed unchanged.

Observed cases include held shift at an edge, airborne eligibility and landing, wall/corner collision, exact and partial step height, tiny/zero movement, support-primary absence and backward fallback with both old onGroundNoBlocks states, cached support removal, sequential four-block changes, and velocity positive/negative zero/subnormal signs. All 75 observed before-support velocities and every called before-minor velocity equal the exact initial velocity words. Actual floor/wall restitution confirms negative zero from positive prior components, rather than a canonical-zero assignment.

The receiver uses the same four explicit external LI service substitutes as the frozen normal-constructor boundary. Actual ClientLevel/LocalPlayer constructors and all methods/inherited classes under verification remain official and untouched. This does not establish a complete rendered client service environment. Full raw reports/source/runtime records remain ignored under `build/local-move-world-reference`; tracked reports are compact summaries with exact hash/size links.

Reference SHA256: `94afc9b4b47138115207d1d6e5936c9498cea49008f6c86e52d4b1932178a820`.

Actual Java fixture SOURCE SHA256: `37b814cb487ede0ba517c0282e3e4e5b2cebb4a54f24888c302a7c49bf1f01bd`.

Reference producer SHA256: `de5f495e51a178aec022e721062df287250081ddfcac997a9273b930516da494`.

Production source SHA256: `3823c3e6d4ebd0ab8743792aad3bf0cacae7a081a5791bd23d888037bd569f81`.

## Reproduce and status

```sh
PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_local_move_world_probe.py --verify-existing --selftest
PYTHONDONTWRITEBYTECODE=1 python3 tools/reference_local_move_world_probe.py --rerun
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_local_move_world.py --prepare
# Retained-binary comparison (already passed):
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_local_move_world.py --skip-build --skip-ordinary --skip-kernel
# Native/kernel command requires the lead's heavy-slot grant:
PYTHONDONTWRITEBYTECODE=1 python3 tools/test_local_move_world.py
```

Preparation performs only ordinary checking and pins. The executed native route is the installed content-pinned Bend 2.0.35 build, capped at 600 seconds, followed by unchanged native comparisons and one sequential full-harness kernel attempt capped at 60 seconds. Process groups receive bounded termination/cleanup and sampled RSS/virtual sizes; these are build measurements, not gameplay benchmarks. Native success is sealed before independent proof status, so a later proof failure cannot erase a passed native receipt. Full build dependency manifests/stdout and full native results remain ignored; tracked receipts summarize canonical hashes/counts. Associated content-keyed preflight C is distinguished from the installed native compiler's unretained internal temporary C.

The installed native build passed in 43.9851 seconds: associated preflight emission 12.371107 seconds and installed native phase 27.616474 seconds. The immutable executable is 2,943,192 bytes, SHA256 `f52976b6a0e2affff62a7c70d2376db7801e2f5a75d1b979b23030157ec9189d`. The associated content-keyed preflight C SHA256 is `53ce009480486b1ffb0c0968c0c6191e2014fa496be90d95ab63064bc524fcb5`; it is not the unretained native-internal temporary C. Apple clang 17 uses `-std=c11 -O3 -lpthread -lm`; the full 1,657-file native dependency receipt is ignored and linked by exact hash/size and canonical manifest digest. The initial native corpus stopped on the extra recordMovement query. The root-approved immutable-binary replay passed the full actual corpus and stopped on the policy expected-string mismatch described above. After the single literal correction, one retained-binary full comparison passed every corpus/policy/remap assertion. No native rebuild followed those stops. The successful native receipt was sealed before the single independent kernel attempt. That attempt exited 1 after 18.240721 seconds, below its 60-second cap, with the compiler diagnostic “mismatch between the TypeScript implementation, and the formalized BendTT kernel.” It named no law or location and said proof validation was unavailable. This is recorded as unverified independent proof, not a demonstrated gameplay or semantic-law failure. No retry or separate kernel diagnostic was performed. All three production laws retain ordinary-only status. No consumer integration, flight/swimming/passenger/effect world, damaging landing, general actor/border collision, full LocalPlayer tick or whole-game completion is established.

Executed native-build runner SHA256: `9225b0e1f6c050151b5ad93bd42451f7b6109b6f62ee4c36dabdaf8d33d05974`. The phase-scoped replay runner was `acd239901642351538dfbd5d5db52aa98c8166c4e910b3984bd26409a13dc025`. Final single-literal corrected runner SHA256: `f5fd83f662cd0ae36313ad73e5f13d70df5374395a4a3a255074c9c11d22feef`. Both historical runners and raw failed outputs are retained under ignored build storage, with exact AST-change certificates and source/binary pins in the tracked query-scope/policy repair receipts. The original build source closure contains 63 Bend/Base/effect files. All source generations remain identical through the retained-artifact comparisons.
