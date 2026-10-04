# Dependency queue and integration ownership

This queue supports the full 26.3 objective. A finite scene, renderer, or save
fixture is a verification instrument; none satisfies a gameplay completion gate.

## Current critical path

1. Actual Level collision/move, locomotion, neutral Player.travel, Player.aiStep
   and logical keyboard sampling, support/cache reads, owned Player ticking and
   actual MouseHandler projection are checked. Next: LocalPlayer override and
   owned motion composition → authoritative 20 Hz
   held-input controls and typed player saves. The plain Player runtime now passes
   73 actual Java comparisons with per-tick queued edits, packet/physics rollback
   and raw record restoration. The owned LocalPlayer input/travel/finish lanes
   pass separately. Fresh full-tick phase evidence fixes scheduler, input-cache,
   support/minor/fall, late pose/dimensions and cached eye ordering; the composed
   local runtime still needs those authorities and lifecycle consumers.
   Owned local move/fall history now passes two native comparisons with full
   failure rollback. Loaded-world travel and conditional pose/dimension replay
   are being prepared around those frozen authorities.
   The discrete debug controller is
   an integration instrument, not vanilla walking.
2. Registry identity → leased save-owning server → durable publication → actual
   restart/queued-action/MCP tests and the same save-owning state in a client are
   checked. Typed atomic extension saves, neutral player and raw-degree record
   codecs also pass. Atomic runtime save composition passes two actual
   TCP/MCP/save/restart runs and the continuous client. Next: full player/mod state,
   recovery policy and vanilla-format compatibility.
3. Official ZIP/DEFLATE/PNG decoding and bounded texture pixels are checked.
   Typed model parsing/inheritance, the actual first-value resource reader and
   actual-quad mesh rendering are checked. Bend model bake, blockstate/RNG selection, static resource closure and world
   quad production now pass bounded corpora. Actual neighbor sampling and quad
   filtering also pass their split native corpora. Resource-to-frame drawing,
   asset audit and geometry pass twice on their retained artifacts. Same-process
   neighbor-culled resource frames also pass exact geometry/pixel/owner checks.
   The first resource-client build timed out during C emission without an
   artifact; its prepared integration scenarios remain unexecuted. Diagnose that
   frozen generation before changing the frame representation or building again.
   Next: connect that pipeline to native client frames → atlas,
   world lighting and complete presentation.
4. Exact signed-cell snapshot caching and camera-relative F64 subtraction before
   F32 narrowing and verified far-coordinate views are checked in the shared
   persistent client. Visible OS input/presentation acceptance is mandatory and
   unverified; begin its bounded smoke once held controls are stable, with
   verified isolation or a coordinated foreground session.

Contextual block shapes, player input/pose rules and complete resource semantics
remain required, as do all other full-goal systems. Ready work stays bounded by
declared interfaces; integration evidence determines subsequent work.

## Owners and interfaces

| Owner | Exclusive working files or subsystem | Stable integration interface |
| --- | --- | --- |
| Lead | `player_runtime.bend`, `player_session.bend`, `player_storage.bend`, `player_scene.bend`, `player_client.bend`, `client_presenter.bend`, new resource entry/scene and window input | Verified plain Player runtime and saved-session TCP/MCP/restart composition; one W body plus metadata, Tables, support and complete Controller. Continuous entry passes 22 bounded launches; the separate resource/visibility client's first build timed out without an artifact. Read-only emission diagnosis precedes a changed generation. Visible presentation and physical focused input remain required |
| World bridge | Completed PW/SW, `local_tick_world.bend`, phase audit and `player_pose.bend`; new `player_pose_world.bend` preparation | Pose fit replay, ordered short circuits, exact dimension refresh and cached eye position pass 243 raw native rows and full-import kernel. The new bounded operator will supply fit answers through frozen actual Core/Registry queries, retaining complete prior View/Pose on errors. No current runtime consumer changes |
| Client/render | Completed BR/texture metadata, resource frames, atlas packing, UV mapping and owned CPU mipmaps; new sprite animation preparation | All 498 admitted mip inputs pass twice and production scalar laws pass kernel. Original uneven-array construction failure remains archived with explicit retained-artifact adoption. Derive actual animation/frame timeline and CPU interpolation before integrating metadata/mips/atlas consumers; GPU upload and visible presentation remain required |
| Player motion | Completed support, LocalPlayer input, collision hooks, `local_collision_world.bend`, `local_move_world.bend` and `local_move_history.bend`; new `local_travel_history.bend` preparation | Exact minor arithmetic and edge hooks pass native/kernel; actual Core backoff/collision/support/minor/history composition passes retained native corpora with explicit entity/border/ray admission. Travel preparation/final gravity and drag will wrap those hook phases. The actual receiver fixture must establish loaded chunks for the gravity branch. Full world-composition kernel and lifecycle consumers remain unresolved |
| Model interpretation | Completed `blockstate_model.bend`; presenter integration test | Exact selector/multipart/ordered state semantics; 28 hidden actor/window/failure cleanup executions pass; actual visible focused input remains required |
| Model bake | Completed Bake/Choice/Record/Session verification | Exact quads, RNG consumption and atomic raw degree save composition pass; complete player lifecycle persistence remains open |
| World mesh | Completed `world_mesh.bend` and `world_visibility.bend` | Exact relative quads, actual four-state neighbor visibility and owned halo reads pass; sampler O0 and geometry O3 are separate measured artifacts |
| Player codec/input | Completed Codec/Look/Mouse; new `player_controls.bend` | Whole frame accumulation → one Entity turn, atomic rejection, capture/release transitions |
| Float parsing | Completed, stable source | Separate strict RFC and Java-string binary32 parsers |
| Persistence | Completed core and extension foundations, stable sources | Effectful sole-engine/lease State; closed owned codec and catalog |
| Build reuse | Cache complete; runtime integration tests complete; full Pclient cache queued | Shared plain Player tick/input/restore native evidence passes; whole-runtime kernel export timed out; cached full-client test remains queued |
| Block catalog | Completed stored-factor catalog and owned world lookup; new `slab_collision.bend` preparation | All-state stored factors and exact Core/Registry lookup pass; actual registered slab-state shapes are being derived before a broader world-collision consumer |
| Save reference | New actual player/entity serialization evidence | Current saves use the custom PlayerRecord extension. Official save/load fields, raw types, default/reset rules and runtime-only state are being observed before vanilla-format compatibility work |
| Kernel diagnosis | Completed exact JSON serializer localization; production unchanged | The unchanged serializer projection fails independent descent checking while its exact predefinition control passes. All 93 translated definitions match retained full export. Rebuilt array/object tail wrappers lose kernel proper-piece paths. No complete source repair is prepared; preserve public AST, exact unbounded serialization semantics and existing native evidence |
| Local runtime design | Completed read-only `LOCAL_RUNTIME_DESIGN.md`; new entity scheduler snapshot preparation | Keep Core step, actual Entity.commonTick and direct LocalPlayer.tick separate. One MH.State owns motion/support/minor/history; physical buttons and prior LI keys remain distinct. Travel occurs before drag and late pose. Prepare exact old-position/rotation, signed invulnerability and tick-count handling. General required fall rays need resolved-motion staging; a narrow runtime may admit only checked NotRequired moves |

Owners integrate through these interfaces; they do not concurrently modify
another owner's source. Changes to an interface are announced before dependent
work. Finished source and matching evidence are checkpointed with scoped Git
paths. Checks run once on the final changed dependency set, then the relevant
integration suite runs. Repeated broad tests require a new failure, source change,
or unresolved concern.

Limit heavy native emission/full kernel jobs to two concurrently. Eight observed
Bend jobs on 2026-10-04 left about 95 MiB free RAM with substantial compressor
and swap activity; final builds slowed to several minutes. Lower-priority
resource/cache/verdict attempts were deliberately interrupted and remain
unverified, with no correctness inference from cancellation. Keep lightweight
oracle/source preparation parallel. A granted slot includes the gaps between a
runner's sequential phases; an empty process snapshot does not grant a new
build. The lead coordinates build slots.

Compiler expansion also requires a separate diagnosis: the old support harness
remained unfinished after more than 21 minutes with a sampled 12.0 GiB physical
footprint. Removing other test-module imports and separating operation parsers,
without changing gameplay source, reduced the final native build to 3.216 s and
the full import kernel check to 7.988 s. The original attempt remains
inconclusive. Blockstate/resource compiler samples later showed about 13.0/
11.6 GiB footprints; bounded attempts and harness-only narrowing are recorded
separately from ordinary machine contention. Keep production behavior and
independent fixture expectations fixed during these diagnostics.

Current narrower builds separate WorldVisibility sampling and geometry, and
ResourceFrame drawing, asset audit and geometry. Their former combined attempts
reached 600-second bounds without artifacts. WorldVisibility now passes through
its retained exact-C O0 sampler and separately built O3 geometry; this mixed
optimization result establishes behavior, not release performance. ResourceFrame
drawing, audit and geometry now pass the complete retained-artifact suite twice,
including all independent pixels and owner-recovery checks. Audit C/actual native
invocation were missed and remain unobserved; no provenance-filling re-emission ran.
The LocalPlayer world harness hit the installed compiler's 247-word continuation
limit, including its split motion entry. Read-only diagnostics identified both
finish injection and motion reporting captures. Harness-only boxing and a small
sprint-report header preserve production code and exact Java expectations. Each
installed retry remains bounded and independently recorded; a diagnostic timeout
establishes no native result.

The revised LocalPlayer motion and finish entries now pass their retained native
comparison lanes. The single full-source kernel attempt returned the existing
checker mismatch. A small sprint-report capture solved the installed arity limit
without changing production or Java expectations; reference path relocation and
receipt compaction preserve the measured generation explicitly.

## Measured build work

One concurrent-load observation recorded in `evidence/build-timings.json`:
server C emission 9.740 s, native build 16.749 s, MCP native build 6.102 s.
These are individual observations, not isolated medians. Build reuse therefore
targets actual compilation work. It must fingerprint the complete loaded source
and native-effect graph, installed Base/runtime/compiler, flags and platform;
check cached executable bytes; and preserve every test/proof execution obligation.
It must decline reuse when dependencies are unresolved. No compiler/runtime
modification or unchecked game effect is introduced for caching.

Actual integration cache measurements are recorded separately. The first server
miss took 28.321 s including separate C emission and ordinary native compilation;
an uncontended verified reuse took 3.192 s with zero emission/native compilation.
These single measurements have different load conditions and are not medians or
game benchmarks. A 15.599 s concurrent reuse included waiting for the first
builder's lock and must not be presented as uncontended lookup cost.

The separate Window cache passed 31 checks and 26 hidden native executions,
including exact unchanged transform comparison and CPU-to-GPU mutation refusal.
Its tiny-fixture miss/hit/direct build observations are 9.249/6.768/0.613 s;
lookup probes dominate such a small fixture. Actual persistent-client cache
compilation and unchanged integration are queued after a resource-pressure
cancellation; no full-client cache speed claim is established.

## Evidence limits that affect scheduling

- The movement corpus includes 159 untouched `Entity.move` calls; world travel
  and Player aiStep add actual bounded observations. These admit neutral finite
  worlds and explicitly supplied context; full Player/LocalPlayer ticking,
  supporting-state integration and contextual hazards remain open.
- JSON's independent-kernel termination mismatch remains explicit. Ordinary
  typing or unrelated module laws do not repair it.
- The actor's stop message closes its state/timer. A parked accept operation is
  released by explicit native process exit in the current client instrument.
- The world lease and restart tests are available. They do not establish a
  journal/recovery protocol, hostile-writer exclusion, network-filesystem lock
  behavior or physical power-loss durability.
- CPU/Metal pixel equality on a small finite scene does not establish vanilla
  models, lighting, UI, gameplay, world generation, or game-scale performance.
